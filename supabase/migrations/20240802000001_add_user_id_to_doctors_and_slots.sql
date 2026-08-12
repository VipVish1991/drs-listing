-- ============================================================================
-- DrsListing - Add user_id to doctors & doctor_slots
-- Date: 2024-08-02
-- Description: Adds a user_id column to the doctors and doctor_slots tables
--   so the app can join with the users table and fetch all data for a
--   particular user.
-- ============================================================================

-- Add user_id to doctors table (nullable for backward compatibility)
ALTER TABLE public.doctors
    ADD COLUMN user_id TEXT;

COMMENT ON COLUMN public.doctors.user_id IS 'References the app user who owns/connected this doctor profile';

CREATE INDEX IF NOT EXISTS idx_doctors_user_id ON public.doctors (user_id);

-- Add user_id to doctor_slots table
ALTER TABLE public.doctor_slots
    ADD COLUMN user_id TEXT;

COMMENT ON COLUMN public.doctor_slots.user_id IS 'References the app user who owns this slot configuration';

CREATE INDEX IF NOT EXISTS idx_doctor_slots_user_id ON public.doctor_slots (user_id);
