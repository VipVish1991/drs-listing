-- ============================================================================
-- DrsListing — Doctor Unavailability (date ranges)
-- Date: 2026-08-06
-- Description: Adds an `unavailable_ranges` JSONB column to the doctors table
--   storing date ranges when the doctor is NOT available (leave, holiday,
--   travel): [{"start":"2026-08-10","end":"2026-08-12"}]. Doctors set these
--   from their profile via the Available/Unavailable button + calendar range
--   picker. The Flutter app + the booking-page Edge Function hide those dates
--   from patients; a DB trigger enforces the rule server-side so NO code path
--   (Flutter app insert, Edge Function, future clients) can create an
--   appointment on an unavailable date.
-- ============================================================================

-- ── 1. Column ───────────────────────────────────────────────────────
ALTER TABLE public.doctors
    ADD COLUMN IF NOT EXISTS unavailable_ranges JSONB NOT NULL DEFAULT '[]'::jsonb;

COMMENT ON COLUMN public.doctors.unavailable_ranges IS
    'Inclusive date ranges (YYYY-MM-DD) when the doctor is unavailable, '
    'e.g. [{"start":"2026-08-10","end":"2026-08-12"}]. Booking is blocked on these dates.';

-- ── 2. Trigger function ─────────────────────────────────────────────
-- Mirrors the enforce_slot_booking_rule pattern: SECURITY DEFINER + pinned
-- search_path so the check always reads public.doctors even under a
-- restrictive RLS context.
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

    -- Normalize the doctor identity: prefer the top-level column, fall
    -- back to the JSONB snapshot for legacy rows.
    v_doctor_place_id := COALESCE(
        NULLIF(NEW.doctor_place_id, ''),
        NEW.doctor_details->>'place_id'
    );
    IF v_doctor_place_id IS NULL THEN
        RETURN NEW;
    END IF;

    -- A doctor marked unavailable on this date blocks the booking. The
    -- marker prefix "appointments_unavailable_date" lets the Edge Function
    -- return a friendly message instead of a raw database error. Ranges
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

-- ── 3. Trigger ───────────────────────────────────────────────────────
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
