-- ============================================================================
-- DrsListing — Enforce the slot-occupancy rule server-side
-- Date: 2026-08-05
-- Description: A booked slot stays occupied until the appointment is
--   Cancelled — every other status (Pending / Upcoming / Completed / …)
--   disables the slot. This is the SAME rule the Flutter booking screen
--   and the booking-page Edge Function implement client-side
--   (AppointmentStatus.occupiesSlot in the app). This trigger makes it a
--   database-level guarantee so no code path — the Flutter app's direct
--   PostgREST insert, the Edge Function, or any future client — can
--   double-book a slot. A Cancelled appointment never blocks and always
--   frees its slot.
--
-- Enforced for (doctor_place_id|doctor_details->>'place_id',
-- appointment_date, appointment_time) on INSERT, and on UPDATE of the
-- columns that affect the slot (date / time / doctor / status). Legacy
-- 'Flexible' bookings (no concrete time) are not checked, matching the
-- Edge Function's existing behaviour. Ending a booking (Cancelled, or
-- Completed on an existing row) never creates NEW occupancy, so those
-- transitions skip the conflict check — this keeps the doctor able to
-- finish/cancel an appointment even when legacy data shares a slot.
--
-- Known limitation: under READ COMMITTED, two truly simultaneous inserts
-- can both take their statement snapshot before either commits, so the
-- trigger closes every sequential/committed double-booking but not the
-- sub-millisecond in-flight race. The app's pre-check + the Edge
-- Function's race guard + this trigger cover all normal flows.
-- ============================================================================

-- ── 1. Trigger function ──────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.enforce_slot_booking_rule()
RETURNS TRIGGER
LANGUAGE plpgsql
-- SECURITY DEFINER + pinned search_path so the occupancy check always
-- reads the table even if a caller's RLS context is restrictive, and so
-- the function can't be fooled by a search_path hijack.
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_doctor_place_id TEXT;
    v_conflict_id     TEXT;
BEGIN
    -- Ending a booking never CREATES new occupancy, so it is always
    -- allowed and frees nothing extra:
    --   * Cancelled (insert or update) never occupies a slot.
    --   * Completed on an existing row is the doctor finishing a visit —
    --     exempt from the conflict check so legacy rows that share a slot
    --     can still be completed. (New bookings on occupied slots are
    --     still blocked by the INSERT path and any slot-moving UPDATE.)
    IF NEW.status = 'Cancelled'
       OR (TG_OP = 'UPDATE' AND NEW.status = 'Completed') THEN
        RETURN NEW;
    END IF;

    -- Normalize the doctor identity: prefer the top-level column, fall
    -- back to the JSONB snapshot for legacy rows written before the
    -- doctor_place_id column existed.
    v_doctor_place_id := COALESCE(
        NULLIF(NEW.doctor_place_id, ''),
        NEW.doctor_details->>'place_id'
    );

    -- No concrete slot to check (missing identity/date, or the legacy
    -- 'Flexible' booking) — let it through.
    IF v_doctor_place_id IS NULL
       OR NEW.appointment_date IS NULL
       OR NEW.appointment_time IS NULL
       OR NEW.appointment_time = 'Flexible' THEN
        RETURN NEW;
    END IF;

    -- Any OTHER appointment (any status except Cancelled) on the same
    -- doctor + date + time occupies the slot. The marker prefix
    -- "appointments_slot_occupied" lets the Edge Function return a
    -- friendly message instead of a raw database error.
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

-- ── 2. Trigger ───────────────────────────────────────────────────────
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

-- ── 3. Supporting index ──────────────────────────────────────────────
-- Speeds up the occupancy check (the common path uses the top-level
-- doctor_place_id column).
CREATE INDEX IF NOT EXISTS idx_appointments_slot_occupancy
    ON public.appointments (doctor_place_id, appointment_date, appointment_time)
    WHERE status <> 'Cancelled';
