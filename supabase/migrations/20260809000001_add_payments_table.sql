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

-- No UPDATE/DELETE policies: payment rows are append-only from the app; the
-- clinic marks status changes via the service role (or a future Edge Function).
