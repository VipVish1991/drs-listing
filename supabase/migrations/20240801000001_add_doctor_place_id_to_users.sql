-- ============================================================================
-- DrsListing AI - Add doctor_place_id column to users table
-- Date: 2024-08-01
-- Description: Adds a doctor_place_id column to the users table so that when
--   a user connects as a doctor, the association persists across devices and
--   login sessions. Without this column, the doctor_place_id is only saved
--   locally and is lost on reinstall or new device.
-- ============================================================================

ALTER TABLE public.users
    ADD COLUMN IF NOT EXISTS doctor_place_id TEXT;

COMMENT ON COLUMN public.users.doctor_place_id
    IS 'Google Place ID of the clinic/doctor this user manages, if role = doctor';

-- Index for fast lookups when navigating to doctor dashboard on login
CREATE INDEX IF NOT EXISTS idx_users_doctor_place_id
    ON public.users (doctor_place_id)
    WHERE doctor_place_id IS NOT NULL;
