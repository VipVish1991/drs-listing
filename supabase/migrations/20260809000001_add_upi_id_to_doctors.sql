-- ============================================================================
-- Add per-doctor UPI VPA (upi_id) to the doctors table
-- ============================================================================
-- Doctors enter their UPI ID from the doctor profile ("UPI Payment ID" card).
-- The booking flow uses this VPA as the receiver for online consultation fees,
-- falling back to the app-wide default (AppConstants.upiReceiverVpa) when unset.

ALTER TABLE public.doctors ADD COLUMN IF NOT EXISTS upi_id TEXT;

COMMENT ON COLUMN public.doctors.upi_id IS
  'UPI VPA the clinic receives online consultation fees on, e.g. "clinic@okhdfcbank". Set by the doctor in their profile; null falls back to the app-wide default VPA.';
