-- ============================================================================
-- DrsListing — Harden RLS on appointments / doctors / doctor_slots /
-- saved_doctors (owner-scoped, matching the users/payments/notifications
-- convention)
-- Date: 2026-08-14
--
-- WHY:
--   Several tables still had the original PERMISSIVE anon policies
--   (USING/WITH CHECK true) left over from the initial schema:
--
--     * appointments  — anyone could UPDATE any row (cancel/confirm/complete
--                       someone else's booking) and SELECT the whole table
--                       (patient names + phone numbers).
--     * doctors       — anyone could INSERT/UPDATE any doctor row, including
--                       the UPI ID that receives online consultation fees
--                       (a payment-redirection attack).
--     * doctor_slots  — anyone could INSERT/UPDATE/DELETE any clinic's
--                       weekly availability.
--     * saved_doctors — anyone could SELECT/DELETE any user's saved list.
--
--   This migration replaces them with owner-scoped policies that mirror the
--   existing convention on users/payments/notifications: the app proves
--   ownership via its `x-user-id` request header (the logged-in user's UUID,
--   same header the users UPDATE / payments policies already use), and
--   PostgREST surfaces the header to RLS via
--   current_setting('request.headers', true).
--
-- ⚠️ DEPLOYMENT ORDER: apply this migration TOGETHER WITH the app release
--   that adds the x-user-id context headers to the affected calls
--   (lib/services/supabase_service.dart). If the migration lands first, the
--   current app build loses write access to these tables (silent 0-row
--   writes) until the header-wired release ships.
--
-- Residual risk (accepted, same as the users table): the anon key is public
-- and the x-user-id header is client-settable, so a client that KNOWS a
-- victim's UUID could still impersonate them. What this change actually
-- fixes is the no-knowledge mass attack: a client can no longer read/write
-- rows it has no UUID for. Combined with the client-side demo OTP (no
-- universal 1111), an attacker can no longer trivially become any user.
-- ============================================================================

-- ═══════════════════════════════════════════════════════════════════════
-- 1. APPOINTMENTS — patient owns, or the clinic owns (via doctors.user_id)
-- ═══════════════════════════════════════════════════════════════════════
-- Ownership has TWO legitimate holders:
--   * the PATIENT who booked (user_id = x-user-id) — reads own history,
--     cancels/reschedules own bookings;
--   * the CLINIC (a doctors row whose user_id = x-user-id and whose
--     place_id = the appointment's doctor_place_id) — reads its bookings,
--     flips status (Confirm/Complete/Cancel), reschedules as the clinic.
-- Shared helper predicate used by every policy below.
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

DROP POLICY IF EXISTS "anon_can_select_appointments" ON public.appointments;
DROP POLICY IF EXISTS "anon_can_insert_appointments" ON public.appointments;
DROP POLICY IF EXISTS "anon_can_update_appointments" ON public.appointments;

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

COMMENT ON POLICY "appointments_select_owner" ON public.appointments IS
    'A patient (user_id = x-user-id) or the clinic (doctors.user_id = x-user-id, place match) can read the appointment.';
COMMENT ON POLICY "appointments_insert_owner" ON public.appointments IS
    'A patient can create appointments for themselves; a clinic can create bookings on its own behalf.';
COMMENT ON POLICY "appointments_update_owner" ON public.appointments IS
    'Only the booking patient or the owning clinic can update an appointment (status flips, reschedules).';

-- ═══════════════════════════════════════════════════════════════════════
-- 2. DOCTORS — the connecting user owns the row
-- ═══════════════════════════════════════════════════════════════════════
-- SELECT stays OPEN: doctor/clinic discovery is the app's core feature and
-- every patient needs to read the directory. Only writes are scoped: a
-- doctor row may be created/updated only by the user who CONNECTED to it
-- (doctors.user_id = x-user-id) — the same rule the nearby-doctors screen
-- uses to disable re-connecting an already-owned clinic.

DROP POLICY IF EXISTS "anon_can_insert_doctors" ON public.doctors;
DROP POLICY IF EXISTS "anon_can_update_doctors" ON public.doctors;

-- Legacy rows (created before user_id tracking, or by the web booking
-- page) carry user_id NULL — the FIRST user to connect adopts them. Once
-- adopted (user_id set), only that user may write. This matches the app's
-- "connect to a clinic" model: whoever connects first owns it.
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

COMMENT ON POLICY "doctors_insert_owner" ON public.doctors IS
    'A doctor row can only be created by the user who connects to it (user_id = x-user-id).';
COMMENT ON POLICY "doctors_update_owner" ON public.doctors IS
    'Only the connecting user may update a doctor row (legacy NULL user_id rows are adoptable by the first connector) — protects the UPI payment ID and profile from hijack.';

-- ═══════════════════════════════════════════════════════════════════════
-- 3. DOCTOR SLOTS — only the owning clinic's user may write
-- ═══════════════════════════════════════════════════════════════════════
-- SELECT stays OPEN: patients need to see availability to book.
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

DROP POLICY IF EXISTS "anon_can_insert_doctor_slots" ON public.doctor_slots;
DROP POLICY IF EXISTS "anon_can_update_doctor_slots" ON public.doctor_slots;
DROP POLICY IF EXISTS "anon_can_delete_doctor_slots" ON public.doctor_slots;

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

COMMENT ON POLICY "doctor_slots_insert_owner" ON public.doctor_slots IS
    'Only the owning clinic (doctors.user_id = x-user-id, place match) can create slots.';
COMMENT ON POLICY "doctor_slots_update_owner" ON public.doctor_slots IS
    'Only the owning clinic can edit its weekly availability.';
COMMENT ON POLICY "doctor_slots_delete_owner" ON public.doctor_slots IS
    'Only the owning clinic can delete its slots.';

-- ═══════════════════════════════════════════════════════════════════════
-- 3b. BOOKED-SLOT KEYS RPC — the booking screen's one allowed peek
-- ═══════════════════════════════════════════════════════════════════════
-- The patient booking screen must show which slots are ALREADY TAKEN
-- (so the UI can disable them). It does NOT need — and under the new
-- appointments SELECT policy must NOT get — the full appointment rows
-- (other patients' names/phones). This SECURITY DEFINER function returns
-- only the minimal `date|time` keys of non-Cancelled appointments for a
-- clinic, with no PII. SECURITY DEFINER bypasses RLS deliberately: it is
-- the single narrow, non-leaking window the booking flow needs.
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

COMMENT ON FUNCTION public.get_booked_slot_keys(TEXT) IS
    'Returns only the date|time keys of non-Cancelled appointments for a clinic — the single non-PII window the patient booking screen needs (appointments SELECT is owner-scoped).';

GRANT EXECUTE ON FUNCTION public.get_booked_slot_keys(TEXT) TO anon, authenticated;

-- ═══════════════════════════════════════════════════════════════════════
-- 4. SAVED DOCTORS — strictly the user's own rows
-- ═══════════════════════════════════════════════════════════════════════
DROP POLICY IF EXISTS "anon_can_select_saved_doctors" ON public.saved_doctors;
DROP POLICY IF EXISTS "anon_can_insert_saved_doctors" ON public.saved_doctors;
DROP POLICY IF EXISTS "anon_can_delete_saved_doctors" ON public.saved_doctors;

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

COMMENT ON POLICY "saved_doctors_select_own" ON public.saved_doctors IS
    'Users can only read their own saved doctors (user_id = x-user-id).';
COMMENT ON POLICY "saved_doctors_insert_own" ON public.saved_doctors IS
    'Users can only save doctors to their own list.';
COMMENT ON POLICY "saved_doctors_delete_own" ON public.saved_doctors IS
    'Users can only remove doctors from their own list.';

-- ═══════════════════════════════════════════════════════════════════════
-- 5. API USAGE COUNT — leave as-is
-- ═══════════════════════════════════════════════════════════════════════
-- Aggregate counters only (no PII); the app reads them for the admin-style
-- usage screen and they are harmless to expose. No change.
