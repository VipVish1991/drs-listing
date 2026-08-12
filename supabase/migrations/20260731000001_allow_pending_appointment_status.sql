-- ============================================================================
-- DrsListing AI - Allow 'Pending' appointment status
-- Date: 2026-07-31
-- Description: Adds 'Pending' to the allowed status values on the
--   appointments table. 'Pending' is used for appointments created from
--   the browser booking page (QR code) — they are awaiting clinic
--   confirmation before becoming 'Upcoming'.
--
-- Migration of the CHECK constraint:
--   Before: ('Upcoming', 'Completed', 'Cancelled')
--   After:  ('Pending', 'Upcoming', 'Completed', 'Cancelled')
-- ============================================================================

-- Drop the auto-generated check constraint from the initial schema.
-- Postgres names inline column CHECK constraints as:
--   <table>_<column>_check  →  appointments_status_check
ALTER TABLE public.appointments
    DROP CONSTRAINT IF EXISTS appointments_status_check;

-- Re-create it with 'Pending' included.
ALTER TABLE public.appointments
    ADD CONSTRAINT appointments_status_check
    CHECK (status IN ('Pending', 'Upcoming', 'Completed', 'Cancelled'));

COMMENT ON COLUMN public.appointments.status IS
    'Lifecycle status: Pending (QR web booking awaiting confirmation) → Upcoming → Completed | Cancelled';
