-- ============================================================================
-- DrsListing — Enforce "one active booking per doctor" rule
-- Date: 2026-08-13
-- Description: A patient may hold at most ONE active appointment
--   (Pending / Upcoming) with a GIVEN doctor at a time. Other doctors are
--   never affected — the patient can book a different doctor while an
--   appointment with doctor A is still active, and can re-book doctor A
--   immediately once that booking is Completed or Cancelled (no cooldown).
--   This REPLACES the earlier global rule (one active booking across ALL
--   doctors + a 12h cooldown after the most recent booking), which was
--   stricter than the product rule.
--
--   This is the SAME rule the Flutter booking screen
--   (AppointmentController.bookingBlockMessage) and the booking-page Edge
--   Function (bookingGateError) implement client-side. This trigger makes
--   it a database-level guarantee so no code path — the Flutter app's
--   direct PostgREST insert, the Edge Function, or any future client —
--   can bypass it (e.g. two devices booking in parallel, a stale
--   appointments list, or a direct controller call).
--
--   Enforced on INSERT only. Status transitions (Cancel / Complete) and
--   reschedules (UPDATE date/time) never re-trigger the gate — the same
--   patient is simply moving or ending their existing booking, which the
--   rule never blocks.
--
--   Race caveat (same as the slot rule): under READ COMMITTED two truly
--   simultaneous inserts can both take their statement snapshot before
--   either commits, so the trigger closes every sequential / committed
--   violation but not the sub-millisecond in-flight race. The app's
--   pre-check + the Edge Function's gate + this trigger cover all normal
--   flows.
--
--   Marker prefix ("appointments_one_active_booking") lets the
--   booking-page Edge Function return a friendly message instead of a raw
--   database error when a race trips the gate after its own pre-check.
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
    v_doctor_place_id TEXT;
    v_active_id       TEXT;
BEGIN
    -- The rule applies only to bookings tied to a patient.
    IF NEW.user_id IS NULL THEN
        RETURN NEW;
    END IF;

    -- Normalize the doctor identity: prefer the top-level column, fall
    -- back to the JSONB snapshot for legacy rows written before the
    -- doctor_place_id column existed.
    v_doctor_place_id := COALESCE(
        NULLIF(NEW.doctor_place_id, ''),
        NEW.doctor_details->>'place_id'
    );

    -- No doctor identity to scope the rule to — let it through (the
    -- slot-occupancy trigger still guards slots).
    IF v_doctor_place_id IS NULL THEN
        RETURN NEW;
    END IF;

    -- ONE active booking per (patient, doctor): any existing
    -- Pending/Upcoming appointment for this patient with the SAME doctor
    -- blocks the new booking, no matter how old it is (it stays active
    -- until completed/cancelled). Bookings with OTHER doctors never
    -- block.
    SELECT a.appointment_id INTO v_active_id
    FROM public.appointments AS a
    WHERE a.user_id = NEW.user_id
      AND a.status IN ('Pending', 'Upcoming')
      AND (
            a.doctor_place_id = v_doctor_place_id
            OR a.doctor_details->>'place_id' = v_doctor_place_id
          )
    LIMIT 1;

    IF v_active_id IS NOT NULL THEN
        RAISE EXCEPTION
            'appointments_one_active_booking: patient % already has an active appointment % with this doctor',
            NEW.user_id,
            v_active_id
            USING ERRCODE = 'P0001';
    END IF;

    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.enforce_one_active_booking_rule() IS
    'Blocks a new appointment when the patient already holds an active '
    '(Pending/Upcoming) booking with the SAME doctor. Other doctors stay '
    'bookable, and the same doctor can be re-booked immediately once the '
    'active booking is Completed or Cancelled (no cooldown — shared '
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
    'One active booking per doctor: blocks a new booking when the patient '
    'already has an active (Pending/Upcoming) appointment with that doctor. '
    'Bookings with other doctors are never blocked, and the same doctor '
    'can be re-booked once the active booking is Completed or Cancelled.';

-- ── 3. Supporting indexes ────────────────────────────────────────────
-- Speeds up the per-doctor gate check (user + doctor + active status);
-- also serves the patient appointment history reads that sort
-- newest-first.
CREATE INDEX IF NOT EXISTS idx_appointments_user_created
    ON public.appointments (user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_appointments_user_doctor_active
    ON public.appointments (user_id, doctor_place_id)
    WHERE status IN ('Pending', 'Upcoming');
