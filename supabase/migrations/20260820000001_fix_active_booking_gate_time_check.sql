-- ============================================================================
-- DrsListing — Fix one-active-booking gate: respect appointment time
-- Date: 2026-08-20
-- Description: An "Upcoming" appointment whose date+time has already passed
--   should be treated as effectively Completed for the purpose of the
--   one-active-booking-per-doctor gate. Before this fix, a patient whose
--   previous Upcoming appointment was never marked Completed/Cancelled
--   (e.g. the doctor forgot to complete it) was permanently blocked from
--   re-booking the same doctor.
--
--   Mirrors the effectiveStatus logic in AppointmentController and the
--   time-aware bookingGateError in the booking-page Edge Function.
-- ============================================================================

-- ── 1. Helper: convert "HH:MM AM/PM" to minutes-since-midnight ────
-- Returns NULL on unparseable input (callers treat NULL as "unknown,
-- assume active" — fail-open).
CREATE OR REPLACE FUNCTION public.time_to_minutes(time_str TEXT)
RETURNS INTEGER
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  cleaned TEXT;
  is_pm   BOOLEAN;
  hour    INT;
  minute  INT;
BEGIN
  IF time_str IS NULL OR trim(time_str) = '' THEN
    RETURN NULL;
  END IF;
  cleaned := upper(trim(time_str));
  is_pm := cleaned LIKE '%PM';
  cleaned := replace(replace(cleaned, 'AM', ''), 'PM', '');
  cleaned := trim(cleaned);
  hour   := split_part(cleaned, ':', 1)::int;
  minute := COALESCE(NULLIF(split_part(cleaned, ':', 2), '')::int, 0);
  IF is_pm AND hour != 12 THEN hour := hour + 12; END IF;
  IF NOT is_pm AND hour = 12 THEN hour := 0; END IF;
  RETURN hour * 60 + minute;
END;
$$;

COMMENT ON FUNCTION public.time_to_minutes(TEXT) IS
    'Converts a 12-hour "HH:MM AM/PM" time string to minutes since midnight. Returns NULL on unparseable input.';

-- ── 2. Updated trigger function ────────────────────────────────────
CREATE OR REPLACE FUNCTION public.enforce_one_active_booking_rule()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_doctor_place_id TEXT;
    v_active_id       TEXT;
    v_today           DATE;
    v_now_minutes     INT;
BEGIN
    IF NEW.user_id IS NULL THEN
        RETURN NEW;
    END IF;

    v_doctor_place_id := COALESCE(
        NULLIF(NEW.doctor_place_id, ''),
        NEW.doctor_details->>'place_id'
    );

    IF v_doctor_place_id IS NULL THEN
        RETURN NEW;
    END IF;

    -- Pre-compute today as DATE and current minutes-since-midnight
    -- in UTC so the per-row comparison stays fast and timezone-consistent.
    v_today       := CURRENT_DATE;
    v_now_minutes := extract(hour FROM now())::int * 60
                   + extract(minute FROM now())::int;

    -- ONE active booking per (patient, doctor):
    --   • Pending appointments ALWAYS block (no time check — they
    --     haven't been confirmed into a specific slot yet).
    --   • Upcoming appointments block ONLY when their date+time is in
    --     the future. Past or same-day-past Upcoming rows are treated
    --     as effectively Completed.
    --   • Missing date/time → treat as active (fail-open).
    -- Bookings with OTHER doctors never block.
    SELECT a.appointment_id INTO v_active_id
    FROM public.appointments AS a
    WHERE a.user_id = NEW.user_id
      AND (
            a.status = 'Pending'
            OR (
              a.status = 'Upcoming'
              AND (
                -- No date recorded → assume active (fail-open)
                a.appointment_date IS NULL
                -- Future date → definitely active
                OR a.appointment_date > v_today
                -- Same date → compare time components
                OR (
                  a.appointment_date = v_today
                  AND (
                    a.appointment_time IS NULL
                    OR public.time_to_minutes(a.appointment_time) IS NULL
                    OR public.time_to_minutes(a.appointment_time) > v_now_minutes
                  )
                )
              )
            )
          )
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
    'Blocks a new appointment when the patient already holds an active booking with the SAME doctor. Pending always blocks; Upcoming blocks only when the appointment date+time is in the future. Past Upcoming rows are treated as Completed (shared rule with AppointmentController.bookingBlockMessage).';
