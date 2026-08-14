-- ============================================================================
-- DrsListing AI - COMPLETE DATABASE SCHEMA (single consolidated migration)
-- Date: 2026-08-07
-- Description: Full schema for a fresh DrsListing database. Consolidates all
--   15 incremental migrations into one file containing EVERY table, column,
--   index, RLS policy, function, trigger and storage object.
--
-- Tables:
--   1. users            - Patient/user accounts (mobile-number login)
--   2. appointments     - Doctor appointment bookings (full doctor snapshot)
--   3. saved_doctors    - User's saved/favorite doctors
--   4. doctors          - Canonical doctor/clinic profiles (Places API)
--   5. doctor_slots     - Weekly consultation availability slots per doctor
--   6. api_usage_count  - Daily Google Places API call counters
--   7. notifications    - In-app push-notification history (notification center)
--
-- Storage:
--   7. prescriptions bucket (storage.objects policies)
--
-- Security Model:
--   Mobile-number login with no OTP. User identity tracked via locally-stored
--   UUID (flutter_secure_storage). The anon key is used for all requests;
--   RLS policies are scoped to custom request headers (x-user-mobile /
--   x-user-id) set by the app. The QR booking-page Edge Function writes with
--   the SERVICE ROLE key (bypasses RLS).
-- ============================================================================

-- ============================================================================
-- 1. USERS TABLE
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.users (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name            TEXT NOT NULL,
    mobile          TEXT NOT NULL UNIQUE,
    role            TEXT NOT NULL DEFAULT 'patient'
                        CHECK (role IN ('patient', 'doctor')),
    doctor_place_id TEXT,
    device_tokens   JSONB NOT NULL DEFAULT '[]'::jsonb,
    notification_prefs JSONB NOT NULL DEFAULT
        '{"appointment_booked": true, "appointment_cancelled": true, "appointment_rescheduled": true, "appointment_status_changed": true, "all": true}'::jsonb,
    is_active       BOOLEAN NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE public.users IS 'Patient/user accounts registered via the app';
COMMENT ON COLUMN public.users.id IS 'UUID generated server-side, stored locally on device';
COMMENT ON COLUMN public.users.mobile IS 'Mobile number used as the login identifier (no OTP)';
COMMENT ON COLUMN public.users.name IS 'Patient full name provided during registration';
COMMENT ON COLUMN public.users.role IS 'User role: patient (default) or doctor';
COMMENT ON COLUMN public.users.doctor_place_id IS 'Google Place ID of the clinic/doctor this user manages, if role = doctor';
COMMENT ON COLUMN public.users.device_tokens IS 'FCM device registration tokens for push notifications. Array of {token, platform, updated_at} objects — one per device. Managed only via add_device_token() / remove_device_token().';
COMMENT ON COLUMN public.users.notification_prefs IS 'Per-user push-notification preferences. JSONB map of event name → bool (appointment_booked, appointment_cancelled, appointment_rescheduled, appointment_status_changed) plus a master key `all` checked FIRST by the notifications Edge Function — false disables every alert at once while the per-event keys stay preserved. A missing key or true means "send"; false means "skip". Defaults to all events + master enabled.';
COMMENT ON COLUMN public.users.is_active IS 'Account status: TRUE = active (can log in), FALSE = inactive (login blocked, user told to contact support). Defaults to TRUE.';

-- Indexes for mobile lookup and doctor dashboard join. Both names are
-- declared by the incremental chain (20240801000001 adds
-- idx_users_doctor_place_id; 20260806000002 adds the token-lookup alias
-- with the same definition), so the full-schema build must produce BOTH
-- to match the objects a fresh incremental apply would create.
CREATE INDEX IF NOT EXISTS idx_users_mobile ON public.users (mobile);
CREATE INDEX IF NOT EXISTS idx_users_doctor_place_id
    ON public.users (doctor_place_id)
    WHERE doctor_place_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_users_doctor_place_id_token_lookup
    ON public.users (doctor_place_id)
    WHERE doctor_place_id IS NOT NULL;

ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;

-- Scoped policies (rely on x-user-mobile / x-user-id headers from the app):
--   SELECT — only the row whose mobile matches the x-user-mobile header
CREATE POLICY "users_select_own_row" ON public.users
    FOR SELECT
    TO anon, authenticated
    USING (
        (current_setting('request.headers', true)::jsonb ->> 'x-user-mobile') = mobile::text
    );

--   INSERT — can only create the row whose mobile the header names
CREATE POLICY "users_insert_own_row" ON public.users
    FOR INSERT
    TO anon, authenticated
    WITH CHECK (
        (current_setting('request.headers', true)::jsonb ->> 'x-user-mobile') = mobile::text
    );

--   UPDATE — only the row whose id the x-user-id header names
CREATE POLICY "users_update_own_row" ON public.users
    FOR UPDATE
    TO anon, authenticated
    USING (
        (current_setting('request.headers', true)::jsonb ->> 'x-user-id') = id::text
    )
    WITH CHECK (
        (current_setting('request.headers', true)::jsonb ->> 'x-user-id') = id::text
    );

-- ── Device-token RPC helpers (multi-device push notifications) ──
-- Tokens are only ever written through these SECURITY DEFINER functions,
-- which verify ownership via the SAME x-user-id header convention as the
-- UPDATE policy above — the anon key can never touch another user's tokens.
CREATE OR REPLACE FUNCTION public.add_device_token(
    p_token    TEXT,
    p_platform TEXT DEFAULT 'android'
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id UUID;
    v_tokens  JSONB;
BEGIN
    v_user_id := (current_setting('request.headers', true)::jsonb ->> 'x-user-id')::UUID;
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'add_device_token: missing x-user-id header'
            USING ERRCODE = 'P0001';
    END IF;
    IF p_token IS NULL OR btrim(p_token) = '' THEN
        RAISE EXCEPTION 'add_device_token: empty token'
            USING ERRCODE = 'P0001';
    END IF;

    SELECT device_tokens INTO v_tokens
    FROM public.users
    WHERE id = v_user_id;

    v_tokens := COALESCE(v_tokens, '[]'::jsonb);

    SELECT COALESCE(jsonb_agg(elem), '[]'::jsonb)
    INTO v_tokens
    FROM jsonb_array_elements(v_tokens) AS elem
    WHERE elem ->> 'token' <> p_token;

    v_tokens := v_tokens || jsonb_build_object(
        'token',      p_token,
        'platform',   p_platform,
        'updated_at', NOW()
    );

    UPDATE public.users
    SET device_tokens = v_tokens
    WHERE id = v_user_id;
END;
$$;

COMMENT ON FUNCTION public.add_device_token(TEXT, TEXT) IS
    'Registers (or refreshes) the caller''s FCM device token. Ownership is '
    'proven by the x-user-id request header, matching the users UPDATE RLS '
    'policy. Dedupes per token so a device re-login refreshes instead of '
    'duplicating.';

GRANT EXECUTE ON FUNCTION public.add_device_token(TEXT, TEXT) TO anon;

CREATE OR REPLACE FUNCTION public.remove_device_token(p_token TEXT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id UUID;
    v_tokens  JSONB;
BEGIN
    v_user_id := (current_setting('request.headers', true)::jsonb ->> 'x-user-id')::UUID;
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'remove_device_token: missing x-user-id header'
            USING ERRCODE = 'P0001';
    END IF;
    IF p_token IS NULL OR btrim(p_token) = '' THEN
        RETURN; -- nothing to remove
    END IF;

    SELECT device_tokens INTO v_tokens
    FROM public.users
    WHERE id = v_user_id;

    SELECT COALESCE(jsonb_agg(elem), '[]'::jsonb)
    INTO v_tokens
    FROM jsonb_array_elements(COALESCE(v_tokens, '[]'::jsonb)) AS elem
    WHERE elem ->> 'token' <> p_token;

    UPDATE public.users
    SET device_tokens = v_tokens
    WHERE id = v_user_id;
END;
$$;

COMMENT ON FUNCTION public.remove_device_token(TEXT) IS
    'Removes an FCM device token from the caller''s own row (logout). '
    'Ownership proven by the x-user-id request header.';

GRANT EXECUTE ON FUNCTION public.remove_device_token(TEXT) TO anon;


-- ============================================================================
-- 7. NOTIFICATIONS TABLE (in-app push history)
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.notifications (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    type        TEXT NOT NULL,
    title       TEXT NOT NULL,
    body        TEXT,
    data        JSONB NOT NULL DEFAULT '{}'::jsonb,
    read        BOOLEAN NOT NULL DEFAULT false,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE public.notifications IS 'In-app push-notification history. One row per recipient per push sent by the notifications Edge Function; read by the app (x-user-id scoped) to power the notification center.';
COMMENT ON COLUMN public.notifications.type IS 'Event type matching the notifications Edge Function: appointment_booked, appointment_cancelled, appointment_rescheduled or appointment_status_changed.';
COMMENT ON COLUMN public.notifications.data IS 'Deep-link payload: {appointment_id, doctor_place_id, status} — used to navigate when the user taps the notification.';
COMMENT ON COLUMN public.notifications.read IS 'Whether the user has opened/seen this notification (unread badge source).';

-- Fast per-user history reads ordered newest-first.
CREATE INDEX IF NOT EXISTS idx_notifications_user_created
    ON public.notifications (user_id, created_at DESC);

-- Only the user's unread count matters for the badge — partial index keeps it small.
CREATE INDEX IF NOT EXISTS idx_notifications_user_unread
    ON public.notifications (user_id)
    WHERE NOT read;

ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

-- SELECT / UPDATE are scoped to the x-user-id header (the app knows its own
-- UUID once logged in). The Edge Function inserts via the service role, so
-- no anon INSERT/DELETE policies are needed. Compared as TEXT (not casting
-- the header to UUID) so a malformed header fails closed with zero rows
-- instead of throwing — same pattern as the users UPDATE policy.
CREATE POLICY "notifications_select_own" ON public.notifications
    FOR SELECT
    TO anon, authenticated
    USING (
        (current_setting('request.headers', true)::jsonb ->> 'x-user-id') = user_id::text
    );

CREATE POLICY "notifications_update_own" ON public.notifications
    FOR UPDATE
    TO anon, authenticated
    USING (
        (current_setting('request.headers', true)::jsonb ->> 'x-user-id') = user_id::text
    )
    WITH CHECK (
        (current_setting('request.headers', true)::jsonb ->> 'x-user-id') = user_id::text
    );

-- ── Retention: auto-clean old history rows ───────────────────────
-- Deletes notifications older than 90 days. Run daily by the pg_cron job
-- `prune-notifications-daily` and opportunistically by the Edge Function.
CREATE INDEX IF NOT EXISTS idx_notifications_created_at
    ON public.notifications (created_at);

CREATE OR REPLACE FUNCTION public.prune_old_notifications(
    p_days integer DEFAULT 90
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_deleted integer;
BEGIN
    DELETE FROM public.notifications
    WHERE created_at < NOW() - make_interval(days => p_days);
    GET DIAGNOSTICS v_deleted = ROW_COUNT;
    RETURN v_deleted;
END;
$$;

COMMENT ON FUNCTION public.prune_old_notifications(integer) IS 'Retention policy for the in-app notification history: deletes rows older than p_days (default 90) and returns the count removed. Called daily by the pg_cron job `prune-notifications-daily` and opportunistically by the notifications Edge Function.';

-- SECURITY DEFINER + global DELETE: clients must NOT be able to call it
-- (prune_old_notifications(0) would wipe the table). Only cron (postgres)
-- and the service role need it; the Edge Function deletes directly.
REVOKE ALL ON FUNCTION public.prune_old_notifications(integer)
    FROM PUBLIC, anon, authenticated;

-- Daily retention job (idempotent; skipped if pg_cron cannot be enabled).
-- $do$ outer tags because cron.schedule nests a second dollar-quoted string.
DO $do$
BEGIN
    CREATE EXTENSION IF NOT EXISTS pg_cron;
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'pg_cron could not be enabled (%). Relying on Edge Function opportunistic pruning.', SQLERRM;
END;
$do$;

DO $do$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
        PERFORM cron.unschedule(jobid)
        FROM cron.job
        WHERE jobname = 'prune-notifications-daily';

        PERFORM cron.schedule(
            'prune-notifications-daily',
            '0 3 * * *',
            $$SELECT public.prune_old_notifications(90)$$
        );
    END IF;
END;
$do$;


-- ============================================================================
-- 2. APPOINTMENTS TABLE
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.appointments (
    appointment_id      TEXT PRIMARY KEY,
    user_id             UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    doctor_name         TEXT NOT NULL,
    doctor_place_id     TEXT,
    appointment_date    DATE NOT NULL,
    appointment_time    TEXT NOT NULL,
    doctor_details      JSONB DEFAULT '{}'::jsonb,
    call_number         TEXT,
    map_location        JSONB DEFAULT '{}'::jsonb,
    symptoms            TEXT,
    patient_name        TEXT,
    patient_phone       TEXT,
    consultation_type   TEXT,
    upload_prescription TEXT[] DEFAULT '{}',
    status              TEXT NOT NULL DEFAULT 'Upcoming'
                            CHECK (status IN ('Pending', 'Upcoming', 'Completed', 'Cancelled')),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE public.appointments IS 'Patient appointment bookings with a snapshot of doctor details';
COMMENT ON COLUMN public.appointments.appointment_id IS 'Custom formatted ID like APT1001, APT1002...';
COMMENT ON COLUMN public.appointments.doctor_place_id IS 'Google Place ID of the doctor for efficient direct querying';
COMMENT ON COLUMN public.appointments.doctor_details IS 'Full JSON snapshot of DoctorModel from Google Places API';
COMMENT ON COLUMN public.appointments.map_location IS 'JSON with latitude/longitude for Google Maps launch';
COMMENT ON COLUMN public.appointments.patient_phone IS 'Patient mobile number captured at booking time (tap-to-dial on doctor side)';
COMMENT ON COLUMN public.appointments.consultation_type IS 'Booking schedule type: tele | video | clinic (null for legacy rows). Prescription upload is offered only for tele/video.';
COMMENT ON COLUMN public.appointments.upload_prescription IS 'Public Supabase Storage URLs of uploaded prescription photos, newest appended last.';
COMMENT ON COLUMN public.appointments.status IS 'Lifecycle status: Pending (QR web booking awaiting confirmation) → Upcoming → Completed | Cancelled';

-- Indexes for common query patterns
CREATE INDEX IF NOT EXISTS idx_appointments_user_id ON public.appointments (user_id);
CREATE INDEX IF NOT EXISTS idx_appointments_status ON public.appointments (status);
CREATE INDEX IF NOT EXISTS idx_appointments_date ON public.appointments (appointment_date DESC);
CREATE INDEX IF NOT EXISTS idx_appointments_user_status
    ON public.appointments (user_id, status);
CREATE INDEX IF NOT EXISTS idx_appointments_doctor_place_id
    ON public.appointments (doctor_place_id);
-- Speeds up the slot-occupancy check in enforce_slot_booking_rule()
CREATE INDEX IF NOT EXISTS idx_appointments_slot_occupancy
    ON public.appointments (doctor_place_id, appointment_date, appointment_time)
    WHERE status <> 'Cancelled';

ALTER TABLE public.appointments ENABLE ROW LEVEL SECURITY;

-- Owner-scoped policies (matching the hardening migration
-- 20260814000002_harden_ownership_rls.sql). The patient who booked OR the
-- owning clinic (a doctors row whose user_id = the caller's x-user-id and
-- whose place_id = the appointment's doctor_place_id) may read/insert/
-- update. The booking screen's "which slots are taken" peek goes through
-- the minimal get_booked_slot_keys() SECURITY DEFINER RPC instead.
CREATE OR REPLACE FUNCTION public.is_appointment_owner(p_apt public.appointments)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SET search_path = public
AS $$
    SELECT (
        (current_setting('request.headers', true)::jsonb ->> 'x-user-id') = p_apt.user_id::text
        OR EXISTS (
            SELECT 1 FROM public.doctors d
            WHERE d.user_id = (current_setting('request.headers', true)::jsonb ->> 'x-user-id')
              AND d.place_id = p_apt.doctor_place_id
        )
    );
$$;

CREATE POLICY "appointments_select_owner" ON public.appointments
    FOR SELECT
    TO anon, authenticated
    USING (public.is_appointment_owner(appointments));

CREATE POLICY "appointments_insert_owner" ON public.appointments
    FOR INSERT
    TO anon, authenticated
    WITH CHECK (public.is_appointment_owner(appointments));

CREATE POLICY "appointments_update_owner" ON public.appointments
    FOR UPDATE
    TO anon, authenticated
    USING (public.is_appointment_owner(appointments))
    WITH CHECK (public.is_appointment_owner(appointments));

-- No DELETE policy needed (app never deletes appointments)


-- ============================================================================
-- 8. PAYMENTS TABLE (UPI / offline consultation fees)
-- ============================================================================
-- Records every consultation payment against an appointment so patients and
-- clinics have a durable payment history. Written by the Flutter app at
-- booking time:
--
--   * Online (UPI intent via upi_india) — payment_status 'Paid' with
--     the UPI transaction id / approval ref, or 'Pending' when the UPI app
--     only reported 'submitted'.
--   * Offline ("pay at clinic") — payment_status 'Pending', payment_method
--     'offline'; the clinic marks it paid/refunded later.
--
-- RLS mirrors the notifications table: rows are scoped to the caller's own
-- `x-user-id` header (the app knows its UUID once logged in), so patients can
-- only read/insert their own payment rows through the anon key.
CREATE TABLE IF NOT EXISTS public.payments (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    appointment_id    TEXT NOT NULL REFERENCES public.appointments(appointment_id) ON DELETE CASCADE,
    patient_id        UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    doctor_place_id   TEXT,
    doctor_name       TEXT,
    -- Which consultation the fee covers: tele | video | clinic (mirrors
    -- appointments.consultation_type so payment history groups by visit type).
    consultation_type TEXT,
    payment_type      TEXT NOT NULL DEFAULT 'consultation' CHECK (payment_type IN ('consultation')),
    -- Lifecycle: Pending → Paid | Failed | Refunded
    payment_status    TEXT NOT NULL DEFAULT 'Pending'
                      CHECK (payment_status IN ('Pending', 'Paid', 'Failed', 'Refunded')),
    payment_method    TEXT NOT NULL CHECK (payment_method IN ('online', 'offline')),
    amount            NUMERIC(10, 2) NOT NULL DEFAULT 0,
    currency          TEXT NOT NULL DEFAULT 'INR',
    -- UPI transaction details (online payments). transaction_id is the UPI
    -- app's txnId / approval ref; upi_id is the receiver's (merchant) VPA.
    transaction_id    TEXT,
    upi_id            TEXT,
    paid_at           TIMESTAMPTZ,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE public.payments IS 'Consultation fee payments per appointment (UPI online or offline pay-at-clinic). Patient-scoped via x-user-id RLS.';
COMMENT ON COLUMN public.payments.payment_status IS 'Lifecycle: Pending → Paid | Failed | Refunded. Online UPI success = Paid; UPI "submitted" and offline bookings = Pending until the clinic confirms.';
COMMENT ON COLUMN public.payments.payment_method IS 'online (UPI intent) or offline (pay at clinic).';
COMMENT ON COLUMN public.payments.transaction_id IS 'UPI transaction id / approval ref from the UPI app response (online only).';
COMMENT ON COLUMN public.payments.upi_id IS 'Receiver (merchant) UPI VPA the payment was made to.';

-- Fast lookups: one appointment's payment, a patient's history, a clinic's
-- income per doctor.
CREATE INDEX IF NOT EXISTS idx_payments_appointment
    ON public.payments (appointment_id);
CREATE INDEX IF NOT EXISTS idx_payments_patient
    ON public.payments (patient_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_payments_doctor
    ON public.payments (doctor_place_id, created_at DESC);

ALTER TABLE public.payments ENABLE ROW LEVEL SECURITY;

-- Patients can only see their own payment rows (x-user-id = patient_id,
-- compared as TEXT so a malformed header fails closed like the users policy).
CREATE POLICY "payments_select_own" ON public.payments
    FOR SELECT
    TO anon, authenticated
    USING (
        (current_setting('request.headers', true)::jsonb ->> 'x-user-id') = patient_id::text
    );

-- Patients can insert payment rows only for themselves. The app sends the
-- x-user-id context header when writing (same convention as add_device_token).
CREATE POLICY "payments_insert_own" ON public.payments
    FOR INSERT
    TO anon, authenticated
    WITH CHECK (
        (current_setting('request.headers', true)::jsonb ->> 'x-user-id') = patient_id::text
    );

-- Doctors (clinics owned by the caller) may READ payment rows for their own
-- appointments — powers the payment line on the doctor appointments screen.
-- Ownership: doctors.user_id (TEXT UUID) = the x-user-id request header, and
-- doctors.place_id = payments.doctor_place_id. Fails closed on missing header.
DROP POLICY IF EXISTS "payments_select_doctor" ON public.payments;
CREATE POLICY "payments_select_doctor" ON public.payments
    FOR SELECT
    TO anon, authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.doctors d
            WHERE d.user_id = (current_setting('request.headers', true)::jsonb ->> 'x-user-id')
              AND d.place_id = payments.doctor_place_id
        )
    );

-- Doctors may UPDATE the status of payment rows for their clinics — the
-- offline 'Pending' → 'Paid' / 'Refunded' flip from the appointments screen.
DROP POLICY IF EXISTS "payments_update_doctor" ON public.payments;
CREATE POLICY "payments_update_doctor" ON public.payments
    FOR UPDATE
    TO anon, authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.doctors d
            WHERE d.user_id = (current_setting('request.headers', true)::jsonb ->> 'x-user-id')
              AND d.place_id = payments.doctor_place_id
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.doctors d
            WHERE d.user_id = (current_setting('request.headers', true)::jsonb ->> 'x-user-id')
              AND d.place_id = payments.doctor_place_id
        )
    );

-- Column-restrict the doctor UPDATE surface: only the status fields may be
-- written, never the amount / patient / method / doctor_place_id.
REVOKE UPDATE ON public.payments FROM anon, authenticated;
GRANT UPDATE (payment_status, paid_at, updated_at)
    ON public.payments TO anon, authenticated;



-- Booking screen's minimal "which slots are taken" peek (no patient data).
-- Matches 20260814000002_harden_ownership_rls.sql.
CREATE OR REPLACE FUNCTION public.get_booked_slot_keys(p_doctor_place_id TEXT)
RETURNS TEXT[]
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT ARRAY(
        SELECT appointment_date::text || '|' || appointment_time
        FROM public.appointments
        WHERE doctor_place_id = p_doctor_place_id
          AND status IS DISTINCT FROM 'Cancelled'
    );
$$;

GRANT EXECUTE ON FUNCTION public.get_booked_slot_keys(TEXT) TO anon, authenticated;


-- ============================================================================
-- 3. SAVED DOCTORS TABLE
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.saved_doctors (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    doctor_data JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE public.saved_doctors IS 'Doctors bookmarked by users for quick access';
COMMENT ON COLUMN public.saved_doctors.doctor_data IS 'Full DoctorModel JSON from Google Places API including place_id';

-- Index for fast user-scoped queries and place_id lookups
CREATE INDEX IF NOT EXISTS idx_saved_doctors_user_id ON public.saved_doctors (user_id);
CREATE INDEX IF NOT EXISTS idx_saved_doctors_place_id
    ON public.saved_doctors ((doctor_data->>'place_id'));

ALTER TABLE public.saved_doctors ENABLE ROW LEVEL SECURITY;

-- Owner-scoped (user_id = x-user-id), matching 20260814000002.
CREATE POLICY "saved_doctors_select_own" ON public.saved_doctors
    FOR SELECT
    TO anon, authenticated
    USING (
        (current_setting('request.headers', true)::jsonb ->> 'x-user-id') = user_id::text
    );

CREATE POLICY "saved_doctors_insert_own" ON public.saved_doctors
    FOR INSERT
    TO anon, authenticated
    WITH CHECK (
        (current_setting('request.headers', true)::jsonb ->> 'x-user-id') = user_id::text
    );

CREATE POLICY "saved_doctors_delete_own" ON public.saved_doctors
    FOR DELETE
    TO anon, authenticated
    USING (
        (current_setting('request.headers', true)::jsonb ->> 'x-user-id') = user_id::text
    );


-- ============================================================================
-- 4. DOCTORS TABLE
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.doctors (
    place_id                    TEXT PRIMARY KEY,
    name                        TEXT NOT NULL,
    address                     TEXT,
    vicinity                    TEXT,
    latitude                    DOUBLE PRECISION,
    longitude                   DOUBLE PRECISION,
    phone_number                TEXT,
    international_phone_number  TEXT,
    website                     TEXT,
    url                         TEXT,
    plus_code                   TEXT,
    rating                      DOUBLE PRECISION,
    user_ratings_total          INTEGER,
    is_open                     BOOLEAN,
    business_status             TEXT,
    price_level                 INTEGER,
    photos                      JSONB DEFAULT '[]'::jsonb,
    photo_details               JSONB DEFAULT '[]'::jsonb,
    opening_hours               JSONB DEFAULT '[]'::jsonb,
    opening_hours_periods       JSONB DEFAULT '[]'::jsonb,
    current_opening_hours       JSONB DEFAULT '{}'::jsonb,
    reviews                     JSONB DEFAULT '[]'::jsonb,
    specialization              TEXT,
    hospital_name               TEXT,
    types                       JSONB DEFAULT '[]'::jsonb,
    primary_type                TEXT,
    address_components          JSONB DEFAULT '[]'::jsonb,
    editorial_summary           TEXT,
    experience_years            INTEGER,
    wheelchair_accessible       BOOLEAN,
    user_id                     TEXT,
    unavailable_ranges          JSONB NOT NULL DEFAULT '[]'::jsonb,
    upi_id                      TEXT,
    created_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE public.doctors IS 'Canonical doctor/clinic profiles synced from Google Places API';
COMMENT ON COLUMN public.doctors.place_id IS 'Google Place ID from the Places API';
COMMENT ON COLUMN public.doctors.photos IS 'Array of photo reference strings';
COMMENT ON COLUMN public.doctors.photo_details IS 'Full photo metadata objects';
COMMENT ON COLUMN public.doctors.opening_hours IS 'Weekday text descriptions';
COMMENT ON COLUMN public.doctors.opening_hours_periods IS 'Raw opening hours period objects';
COMMENT ON COLUMN public.doctors.current_opening_hours IS 'Real-time opening hours accounting for holiday schedules, temporary closures';
COMMENT ON COLUMN public.doctors.reviews IS 'Full review objects from Places API';
COMMENT ON COLUMN public.doctors.address_components IS 'Structured address components (Google Places or Mapbox context)';
COMMENT ON COLUMN public.doctors.types IS 'Place types from Google Places API e.g. ["doctor", "health"]';
COMMENT ON COLUMN public.doctors.primary_type IS 'Google primary place type e.g. cardiologist, general_doctor, dentist, hospital';
COMMENT ON COLUMN public.doctors.wheelchair_accessible IS 'Whether the entrance is wheelchair accessible (from Places API)';
COMMENT ON COLUMN public.doctors.experience_years IS 'Years of experience (user-provided)';
COMMENT ON COLUMN public.doctors.user_id IS 'References the app user who owns/connected this doctor profile';
COMMENT ON COLUMN public.doctors.unavailable_ranges IS 'Inclusive date ranges (YYYY-MM-DD) when the doctor is unavailable, e.g. [{"start":"2026-08-10","end":"2026-08-12"}]. Booking is blocked on these dates.';
COMMENT ON COLUMN public.doctors.upi_id IS 'UPI VPA the clinic receives online consultation fees on, e.g. "clinic@okhdfcbank". Set by the doctor in their profile; null falls back to the app-wide default VPA.';
COMMENT ON COLUMN public.doctors.plus_code IS 'Google Plus Code e.g. "7MH37M6G+R6" (global_code) — human-friendly compound_code also available from API';

-- Indexes for fast lookups
CREATE INDEX IF NOT EXISTS idx_doctors_name ON public.doctors (name);
CREATE INDEX IF NOT EXISTS idx_doctors_specialization ON public.doctors (specialization);
CREATE INDEX IF NOT EXISTS idx_doctors_rating ON public.doctors (rating DESC);
CREATE INDEX IF NOT EXISTS idx_doctors_user_id ON public.doctors (user_id);
CREATE INDEX IF NOT EXISTS idx_doctors_primary_type ON public.doctors (primary_type);

ALTER TABLE public.doctors ENABLE ROW LEVEL SECURITY;

-- SELECT stays OPEN (doctor/clinic discovery). Writes are owner-scoped:
-- only the user who CONNECTED to the clinic (doctors.user_id =
-- x-user-id; legacy NULL rows are adoptable by the first connector) may
-- create/update it — protects the UPI payment ID from hijack. Matches
-- 20260814000002_harden_ownership_rls.sql.
CREATE POLICY "anon_can_select_doctors"
    ON public.doctors
    FOR SELECT
    TO anon
    USING (true);

CREATE POLICY "doctors_insert_owner" ON public.doctors
    FOR INSERT
    TO anon, authenticated
    WITH CHECK (
        (current_setting('request.headers', true)::jsonb ->> 'x-user-id') = user_id::text
    );

CREATE POLICY "doctors_update_owner" ON public.doctors
    FOR UPDATE
    TO anon, authenticated
    USING (
        user_id IS NULL
        OR (current_setting('request.headers', true)::jsonb ->> 'x-user-id') = user_id::text
    )
    WITH CHECK (
        user_id IS NULL
        OR (current_setting('request.headers', true)::jsonb ->> 'x-user-id') = user_id::text
    );


-- ============================================================================
-- 5. DOCTOR SLOTS TABLE
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.doctor_slots (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    doctor_place_id  TEXT NOT NULL REFERENCES public.doctors(place_id) ON DELETE CASCADE,
    day_of_week      TEXT NOT NULL,
    schedule_type    TEXT NOT NULL CHECK (schedule_type IN ('tele', 'video', 'clinic')),
    -- schedule_type: tele = phone consultation, video = video call, clinic = in-person
    start_time       TEXT NOT NULL,           -- HH:MM format (24h)
    end_time         TEXT NOT NULL,           -- HH:MM format (24h)
    duration_minutes INTEGER NOT NULL DEFAULT 30,
    fee              INTEGER NOT NULL DEFAULT 0,
    slots            JSONB NOT NULL DEFAULT '[]'::jsonb,
    is_enabled       BOOLEAN NOT NULL DEFAULT true,
    user_id          TEXT,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT doctor_slots_unique_key
        UNIQUE (doctor_place_id, day_of_week, schedule_type)
);

COMMENT ON TABLE public.doctor_slots IS 'Weekly availability slots for each consultation type per doctor';
COMMENT ON COLUMN public.doctor_slots.schedule_type IS 'Consultation type: tele (phone), video (video call), clinic (in-person)';
COMMENT ON COLUMN public.doctor_slots.start_time IS 'Start time in 24h HH:MM format, e.g. 09:00';
COMMENT ON COLUMN public.doctor_slots.end_time IS 'End time in 24h HH:MM format, e.g. 17:00';
COMMENT ON COLUMN public.doctor_slots.duration_minutes IS 'Duration per slot in minutes (e.g. 15, 30, 60)';
COMMENT ON COLUMN public.doctor_slots.fee IS 'Consultation fee in INR (₹)';
COMMENT ON COLUMN public.doctor_slots.slots IS 'Array of generated time slot strings like ["09:00 AM", "09:30 AM"]';
COMMENT ON COLUMN public.doctor_slots.is_enabled IS 'Whether this schedule row is active';
COMMENT ON COLUMN public.doctor_slots.user_id IS 'References the app user who owns this slot configuration';

-- Indexes for fast doctor-scoped queries
CREATE INDEX IF NOT EXISTS idx_doctor_slots_doctor ON public.doctor_slots (doctor_place_id);
CREATE INDEX IF NOT EXISTS idx_doctor_slots_day ON public.doctor_slots (day_of_week);
CREATE INDEX IF NOT EXISTS idx_doctor_slots_user_id ON public.doctor_slots (user_id);

ALTER TABLE public.doctor_slots ENABLE ROW LEVEL SECURITY;

-- SELECT stays OPEN (patients need to see availability). Writes are
-- owner-scoped to the owning clinic (doctors.user_id = x-user-id, place
-- match; legacy NULL user_id clinics adoptable) — matches
-- 20260814000002_harden_ownership_rls.sql.
CREATE POLICY "anon_can_select_doctor_slots"
    ON public.doctor_slots
    FOR SELECT
    TO anon
    USING (true);

CREATE OR REPLACE FUNCTION public.is_slot_owner(p_slot public.doctor_slots)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.doctors d
        WHERE d.place_id = p_slot.doctor_place_id
          AND (
              d.user_id IS NULL
              OR d.user_id = (current_setting('request.headers', true)::jsonb ->> 'x-user-id')
          )
    );
$$;

CREATE POLICY "doctor_slots_insert_owner" ON public.doctor_slots
    FOR INSERT
    TO anon, authenticated
    WITH CHECK (public.is_slot_owner(doctor_slots));

CREATE POLICY "doctor_slots_update_owner" ON public.doctor_slots
    FOR UPDATE
    TO anon, authenticated
    USING (public.is_slot_owner(doctor_slots))
    WITH CHECK (public.is_slot_owner(doctor_slots));

CREATE POLICY "doctor_slots_delete_owner" ON public.doctor_slots
    FOR DELETE
    TO anon, authenticated
    USING (public.is_slot_owner(doctor_slots));


-- ============================================================================
-- 6. API USAGE COUNT TABLE
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.api_usage_count (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    usage_date  DATE NOT NULL DEFAULT CURRENT_DATE,
    endpoint    TEXT NOT NULL,
    count       INTEGER NOT NULL DEFAULT 0,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT api_usage_count_unique_day_endpoint UNIQUE (usage_date, endpoint)
);

COMMENT ON TABLE public.api_usage_count IS 'Daily Google Places API call counts (cost tracking)';
COMMENT ON COLUMN public.api_usage_count.usage_date IS 'Calendar day the calls were made';
COMMENT ON COLUMN public.api_usage_count.endpoint IS 'API endpoint, e.g. text_search, place_details';
COMMENT ON COLUMN public.api_usage_count.count IS 'Number of calls made to this endpoint on this day';

CREATE INDEX IF NOT EXISTS idx_api_usage_count_date ON public.api_usage_count (usage_date);

ALTER TABLE public.api_usage_count ENABLE ROW LEVEL SECURITY;

CREATE POLICY "anon_can_select_api_usage_count"
    ON public.api_usage_count
    FOR SELECT
    TO anon
    USING (true);


-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

-- Auto-update updated_at timestamp
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;

-- Generate the next appointment ID (APT1001, APT1002, ...)
CREATE OR REPLACE FUNCTION public.generate_appointment_id()
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
    next_num INTEGER;
BEGIN
    SELECT COALESCE(
        MAX(SUBSTRING(appointment_id FROM 'APT(\d+)')::INTEGER),
        1000
    ) + 1 INTO next_num
    FROM public.appointments;

    RETURN 'APT' || next_num::TEXT;
END;
$$;

COMMENT ON FUNCTION public.generate_appointment_id()
    IS 'Generates sequential appointment IDs like APT1001, APT1002, etc.';

-- Utility: Count appointments for a user by status
CREATE OR REPLACE FUNCTION public.get_appointment_counts(p_user_id UUID)
RETURNS TABLE (status TEXT, count BIGINT)
LANGUAGE sql
STABLE
AS $$
    SELECT status, COUNT(*)::BIGINT
    FROM public.appointments
    WHERE user_id = p_user_id
    GROUP BY status
    ORDER BY status;
$$;

COMMENT ON FUNCTION public.get_appointment_counts(UUID)
    IS 'Returns appointment counts grouped by status for a given user';

-- Atomic daily API-usage counter (SECURITY DEFINER so anon can upsert)
CREATE OR REPLACE FUNCTION public.increment_api_usage(p_endpoint TEXT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    INSERT INTO public.api_usage_count (usage_date, endpoint, count)
    VALUES (CURRENT_DATE, p_endpoint, 1)
    ON CONFLICT (usage_date, endpoint)
    DO UPDATE SET count = public.api_usage_count.count + 1,
                  updated_at = NOW();
END;
$$;

COMMENT ON FUNCTION public.increment_api_usage(TEXT)
    IS 'Increments today''s call counter for the given Places API endpoint';

GRANT EXECUTE ON FUNCTION public.increment_api_usage(TEXT) TO anon;


-- ============================================================================
-- TRIGGERS (updated_at)
-- ============================================================================
CREATE TRIGGER set_doctors_updated_at
    BEFORE UPDATE ON public.doctors
    FOR EACH ROW
    EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER set_doctor_slots_updated_at
    BEFORE UPDATE ON public.doctor_slots
    FOR EACH ROW
    EXECUTE FUNCTION public.update_updated_at_column();


-- ============================================================================
-- SERVER-SIDE BOOKING RULES
-- ============================================================================

-- ── Rule 1: Slot occupancy — a slot is occupied until the appointment is
--    Cancelled (every other status disables the slot). Database-level
--    guarantee so no code path can double-book a slot.
CREATE OR REPLACE FUNCTION public.enforce_slot_booking_rule()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_doctor_place_id TEXT;
    v_conflict_id     TEXT;
BEGIN
    -- Ending a booking never CREATES new occupancy:
    --   * Cancelled (insert or update) never occupies a slot.
    --   * Completed on an existing row is the doctor finishing a visit —
    --     exempt so legacy rows that share a slot can still be completed.
    IF NEW.status = 'Cancelled'
       OR (TG_OP = 'UPDATE' AND NEW.status = 'Completed') THEN
        RETURN NEW;
    END IF;

    -- Normalize doctor identity: prefer the top-level column, fall back to
    -- the JSONB snapshot for legacy rows.
    v_doctor_place_id := COALESCE(
        NULLIF(NEW.doctor_place_id, ''),
        NEW.doctor_details->>'place_id'
    );

    -- No concrete slot to check (missing identity/date, or legacy
    -- 'Flexible' booking) — let it through.
    IF v_doctor_place_id IS NULL
       OR NEW.appointment_date IS NULL
       OR NEW.appointment_time IS NULL
       OR NEW.appointment_time = 'Flexible' THEN
        RETURN NEW;
    END IF;

    -- Any OTHER appointment (any status except Cancelled) on the same
    -- doctor + date + time occupies the slot.
    SELECT a.appointment_id INTO v_conflict_id
    FROM public.appointments AS a
    WHERE a.status <> 'Cancelled'
      AND a.appointment_id <> NEW.appointment_id
      AND a.appointment_date = NEW.appointment_date
      AND a.appointment_time = NEW.appointment_time
      AND (
            a.doctor_place_id = v_doctor_place_id
            OR a.doctor_details->>'place_id' = v_doctor_place_id
          )
    LIMIT 1;

    IF v_conflict_id IS NOT NULL THEN
        RAISE EXCEPTION 'appointments_slot_occupied: slot already booked for % on % at % (existing appointment %)',
            v_doctor_place_id,
            NEW.appointment_date,
            NEW.appointment_time,
            v_conflict_id
            USING ERRCODE = 'P0001';
    END IF;

    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.enforce_slot_booking_rule() IS
    'Blocks a non-Cancelled appointment when another non-Cancelled appointment '
    'already occupies the same doctor + date + time slot. A slot only frees '
    'once the appointment is Cancelled (shared AppointmentStatus.occupiesSlot rule).';

DROP TRIGGER IF EXISTS trg_appointments_enforce_slot_rule
    ON public.appointments;

CREATE TRIGGER trg_appointments_enforce_slot_rule
    BEFORE INSERT OR UPDATE OF
        appointment_date,
        appointment_time,
        doctor_place_id,
        doctor_details,
        status
    ON public.appointments
    FOR EACH ROW
    EXECUTE FUNCTION public.enforce_slot_booking_rule();

COMMENT ON TRIGGER trg_appointments_enforce_slot_rule
    ON public.appointments IS
    'Prevents double-booking a slot: a slot is occupied by any non-Cancelled '
    'appointment and only frees when the appointment is Cancelled.';


-- ── Rule 2: Doctor unavailability — no appointment on dates the doctor
--    marked unavailable (doctors.unavailable_ranges).
CREATE OR REPLACE FUNCTION public.enforce_unavailability_rule()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_doctor_place_id TEXT;
    v_range           RECORD;
BEGIN
    -- Cancelled bookings never create new occupancy; rows without a date
    -- have nothing to check.
    IF NEW.status = 'Cancelled' OR NEW.appointment_date IS NULL THEN
        RETURN NEW;
    END IF;

    -- Normalize doctor identity: prefer the top-level column, fall back
    -- to the JSONB snapshot for legacy rows.
    v_doctor_place_id := COALESCE(
        NULLIF(NEW.doctor_place_id, ''),
        NEW.doctor_details->>'place_id'
    );
    IF v_doctor_place_id IS NULL THEN
        RETURN NEW;
    END IF;

    -- A doctor marked unavailable on this date blocks the booking. Ranges
    -- are compared as YYYY-MM-DD strings (lexicographic == chronological).
    FOR v_range IN
        SELECT r.value->>'start' AS start_date,
               r.value->>'end'   AS end_date
        FROM public.doctors AS d
        CROSS JOIN LATERAL jsonb_array_elements(d.unavailable_ranges) AS r(value)
        WHERE d.place_id = v_doctor_place_id
    LOOP
        -- appointment_date is a DATE column; the range bounds are YYYY-MM-DD
        -- text. Cast to text so the comparison is lexicographic (equal to
        -- chronological for this format) and identical to the Edge
        -- Function + Flutter date math.
        IF v_range.start_date IS NOT NULL
           AND v_range.end_date IS NOT NULL
           AND NEW.appointment_date::text >= v_range.start_date
           AND NEW.appointment_date::text <= v_range.end_date THEN
            RAISE EXCEPTION 'appointments_unavailable_date: doctor % is unavailable on %',
                v_doctor_place_id,
                NEW.appointment_date
                USING ERRCODE = 'P0001';
        END IF;
    END LOOP;

    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.enforce_unavailability_rule() IS
    'Blocks creating an appointment on a date the doctor marked unavailable '
    '(doctors.unavailable_ranges inclusive date ranges). Cancelled bookings skip the check.';

DROP TRIGGER IF EXISTS trg_appointments_enforce_unavailability
    ON public.appointments;

CREATE TRIGGER trg_appointments_enforce_unavailability
    BEFORE INSERT OR UPDATE OF
        appointment_date,
        doctor_place_id,
        doctor_details
    ON public.appointments
    FOR EACH ROW
    EXECUTE FUNCTION public.enforce_unavailability_rule();

COMMENT ON TRIGGER trg_appointments_enforce_unavailability
    ON public.appointments IS
    'Prevents appointments on dates the doctor marked unavailable.';


-- ── Rule 3: One patient, one doctor at a time — a patient may hold at
--    most ONE active (Pending/Upcoming) appointment, and the next booking
--    is only allowed once 12 hours have passed since their most recent
--    booking was CREATED (Completed / Cancelled bookings still trigger
--    the wait). INSERT-only: status transitions (Cancel / Complete) and
--    reschedules (UPDATE) never re-trigger the gate. Mirrors
--    AppointmentController.bookingBlockMessage + the Edge Function's
--    bookingGateError; the markers let the Edge Function return a
--    friendly message when a race trips the gate after its pre-check.
CREATE OR REPLACE FUNCTION public.enforce_one_active_booking_rule()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_active_id    TEXT;
    v_last_created TIMESTAMPTZ;
BEGIN
    -- The rule applies only to bookings tied to a patient.
    IF NEW.user_id IS NULL THEN
        RETURN NEW;
    END IF;

    -- 1. One ACTIVE booking at a time: any existing Pending/Upcoming
    --    appointment for this patient blocks the new booking, no matter
    --    how old it is (it stays active until completed/cancelled).
    SELECT a.appointment_id INTO v_active_id
    FROM public.appointments AS a
    WHERE a.user_id = NEW.user_id
      AND a.status IN ('Pending', 'Upcoming')
    LIMIT 1;

    IF v_active_id IS NOT NULL THEN
        RAISE EXCEPTION
            'appointments_one_active_booking: patient % already has an active appointment %',
            NEW.user_id,
            v_active_id
            USING ERRCODE = 'P0001';
    END IF;

    -- 2. 12h cooldown from the MOST RECENT booking (any status) created
    --    at — Completed / Cancelled bookings still trigger the wait.
    SELECT MAX(a.created_at) INTO v_last_created
    FROM public.appointments AS a
    WHERE a.user_id = NEW.user_id;

    IF v_last_created IS NOT NULL
       AND v_last_created > NOW() - INTERVAL '12 hours' THEN
        RAISE EXCEPTION
            'appointments_booking_cooldown: patient % must wait 12 hours after their last booking',
            NEW.user_id
            USING ERRCODE = 'P0001';
    END IF;

    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.enforce_one_active_booking_rule() IS
    'Blocks a new appointment when the patient already holds an active '
    '(Pending/Upcoming) booking, or when less than 12 hours have passed '
    'since their most recent booking was created (shared '
    'AppointmentController.bookingBlockMessage rule).';

DROP TRIGGER IF EXISTS trg_appointments_enforce_one_active_booking
    ON public.appointments;

CREATE TRIGGER trg_appointments_enforce_one_active_booking
    BEFORE INSERT
    ON public.appointments
    FOR EACH ROW
    EXECUTE FUNCTION public.enforce_one_active_booking_rule();

COMMENT ON TRIGGER trg_appointments_enforce_one_active_booking
    ON public.appointments IS
    'One patient, one doctor at a time: blocks a new booking when the '
    'patient has an active (Pending/Upcoming) appointment or booked one '
    'within the last 12 hours.';

-- Speeds up both gate checks per user (also serves patient history reads).
CREATE INDEX IF NOT EXISTS idx_appointments_user_created
    ON public.appointments (user_id, created_at DESC);


-- ============================================================================
-- STORAGE: PRESCRIPTIONS BUCKET
-- ============================================================================
-- Public bucket so uploaded photos render straight from the public URL.
INSERT INTO storage.buckets (id, name, public)
VALUES ('prescriptions', 'prescriptions', true)
ON CONFLICT (id) DO NOTHING;

CREATE POLICY "prescriptions_anon_upload"
    ON storage.objects
    FOR INSERT
    TO anon
    WITH CHECK (bucket_id = 'prescriptions');

CREATE POLICY "prescriptions_anon_read"
    ON storage.objects
    FOR SELECT
    TO anon
    USING (bucket_id = 'prescriptions');

CREATE POLICY "prescriptions_anon_update"
    ON storage.objects
    FOR UPDATE
    TO anon
    USING (bucket_id = 'prescriptions')
    WITH CHECK (bucket_id = 'prescriptions');
