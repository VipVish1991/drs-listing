-- Store the patient's own mobile number on the appointment at booking
-- time (both the in-app booking flow and the QR / browser booking-page
-- function). The doctor's appointment-details sheet shows this number
-- with tap-to-dial. The users table itself is RLS-locked (doctors can't
-- read other users' rows), so the phone must travel with the appointment.
ALTER TABLE public.appointments
    ADD COLUMN IF NOT EXISTS patient_phone TEXT;
