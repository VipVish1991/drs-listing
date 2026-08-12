-- ============================================================================
-- DrsListing — Enforce the "one patient, one doctor at a time" rule
-- Date: 2026-08-12
-- Description: A patient may hold at most ONE active appointment
--   (Pending / Upcoming) at a time, and the next booking is only allowed
--   once 12 hours have passed since their most recent booking was CREATED
--   (Completed / Cancelled bookings still trigger the wait). This is the
--   SAME rule the Flutter booking screen (AppointmentController.
--   bookingBlockMessage) and the booking-page Edge Function
--   (bookingGateError) implement client-side. This trigger makes it a
--   database-level guarantee so no code path — the Flutter app's direct
--   PostgREST insert, the Edge Function, or any future client — can
--   bypass it (e.g. two devices booking in parallel, a stale
--   appointments list, or a direct controller call).
--
-- Enforced on INSERT only. Status transitions (Cancel / Complete) and
-- reschedules (UPDATE date/time) never re-trigger the gate — the same
-- patient is simply moving or ending their existing booking, which the
-- rule never blocks.
--
-- Race caveat (same as enforce_slot_booking_rule): under READ COMMITTED
-- two truly simultaneous inserts can both take their statement snapshot
-- before either commits, so the trigger closes every sequential /
-- committed violation but not the sub-millisecond in-flight race. The
-- app's pre-check + the Edge Function's gate + this trigger cover all
-- normal flows.
--
-- Marker prefixes ("appointments_one_active_booking" /
-- "appointments_booking_cooldown") let the booking-page Edge Function
-- return a friendly message instead of a raw database error when a race
-- trips the gate after its own pre-check.
-- ============================================================================

-- ── 1. Trigger function ──────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.enforce_one_active_booking_rule()
RETURNS TRIGGER
LANGUAGE plpgsql
-- SECURITY DEFINER + pinned search_path so the gate always reads the
-- table even if a caller's RLS context is restrictive, and so the
-- function can't be fooled by a search_path hijack.
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

-- ── 2. Trigger ───────────────────────────────────────────────────────
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

-- ── 3. Supporting index ──────────────────────────────────────────────
-- Speeds up both gate checks (the active-booking scan and the MAX
-- created_at cooldown) per user; also serves the patient appointment
-- history reads that sort newest-first.
CREATE INDEX IF NOT EXISTS idx_appointments_user_created
    ON public.appointments (user_id, created_at DESC);
