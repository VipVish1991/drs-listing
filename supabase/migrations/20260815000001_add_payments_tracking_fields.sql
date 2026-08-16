-- ============================================================================
-- 8c. PAYMENTS — FULL UPI RESPONSE TRACKING
-- ============================================================================
-- The app records a consultation payment per appointment (online UPI via the
-- vendored quantupi plugin, or offline pay-at-clinic). Online payments now
-- carry every field the UPI app returns in its response extra — previously
-- only transaction_id + upi_id were stored, so the bank approval ref, the
-- response code, the echoed transaction ref, which UPI app processed the
-- payment, and the raw response string were all lost.
--
-- This migration adds those columns. All are nullable (offline payments and
-- historical rows simply have no UPI response), so existing rows are
-- untouched.
ALTER TABLE public.payments
    ADD COLUMN IF NOT EXISTS approval_ref_no TEXT,
    ADD COLUMN IF NOT EXISTS response_code   TEXT,
    ADD COLUMN IF NOT EXISTS txn_ref         TEXT,
    ADD COLUMN IF NOT EXISTS upi_app_id      TEXT,
    ADD COLUMN IF NOT EXISTS raw_response    TEXT;

COMMENT ON COLUMN public.payments.approval_ref_no IS 'Bank approval reference number from the UPI app response (online only).';
COMMENT ON COLUMN public.payments.response_code IS 'UPI app response code — 00 on a confirmed success, otherwise the raw value returned.';
COMMENT ON COLUMN public.payments.txn_ref IS 'The transaction ref the intent was fired with (tr), echoed back by the UPI app — reconciles the payment to the bank statement.';
COMMENT ON COLUMN public.payments.upi_app_id IS 'Package id of the UPI app that processed the payment (e.g. com.phonepe.app, com.dreamplug.androidapp).';
COMMENT ON COLUMN public.payments.raw_response IS 'The complete raw UPI response string, stored verbatim for dispute tracing.';
