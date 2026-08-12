-- ============================================================================
-- DrsListing AI - Add role column to users table
-- Date: 2024-07-28
-- Description: Adds a role column to the users table for role-based access
--   control. Default role is 'patient'. Doctor role is set during registration
--   or when a user connects a doctor.
-- ============================================================================

ALTER TABLE public.users
    ADD COLUMN IF NOT EXISTS role TEXT NOT NULL DEFAULT 'patient'
    CHECK (role IN ('patient', 'doctor'));

COMMENT ON COLUMN public.users.role
    IS 'User role: patient (default) or doctor';
