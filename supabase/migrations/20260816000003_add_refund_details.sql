-- ============================================================================
-- 8d. PAYMENTS — REFUND DETAILS (how/when a consultation fee was refunded)
-- ============================================================================
-- The doctor can now refund a consultation fee two ways:
--   * Online — the clinic's UPI app pays the PATIENT's own VPA (the doctor
--     enters the VPA from the patient's UPI app / QR code). The refund is
--     recorded only when the UPI app CONFIRMS the payment (status 'success')
--     — an unconfirmed payment never flips the payment to Refunded.
--   * Cash — handed over at the clinic, recorded directly.
-- Refunded rows keep the ORIGINAL payment fields untouched (amount, method,
-- transaction_id of the incoming payment) and add the refund specifics, so
-- the history is complete and a dispute can be traced to the exact refund
-- UPI transaction.
--
-- All columns are nullable — a payment that was never refunded simply has
-- no refund row data, so existing rows are untouched.
ALTER TABLE public.payments
    ADD COLUMN IF NOT EXISTS refund_method          TEXT
        CHECK (refund_method IN ('online', 'cash')),
    ADD COLUMN IF NOT EXISTS refunded_at            TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS refund_upi_id          TEXT,
    ADD COLUMN IF NOT EXISTS refund_transaction_id  TEXT,
    ADD COLUMN IF NOT EXISTS refund_raw_response    TEXT;

COMMENT ON COLUMN public.payments.refund_method IS 'How the refund was given back: online (UPI to the patient) or cash (at the clinic).';
COMMENT ON COLUMN public.payments.refunded_at IS 'When the refund was issued (online = confirmed UPI success; cash = clinic confirmation).';
COMMENT ON COLUMN public.payments.refund_upi_id IS 'Patient UPI VPA the online refund was sent to (online refunds only).';
COMMENT ON COLUMN public.payments.refund_transaction_id IS 'UPI transaction id / approval ref of the REFUND payment (online refunds only).';
COMMENT ON COLUMN public.payments.refund_raw_response IS 'Raw UPI response string of the refund payment, stored verbatim for disputes (online refunds only).';

-- The doctor UPDATE grant is column-restricted (payments_update_doctor
-- policy); extend it to the new refund columns so the appointments screen
-- can write them. GRANT is additive — the existing payment_status /
-- paid_at / updated_at grant stays in place.
GRANT UPDATE (refund_method, refunded_at, refund_upi_id,
              refund_transaction_id, refund_raw_response)
    ON public.payments TO anon, authenticated;
