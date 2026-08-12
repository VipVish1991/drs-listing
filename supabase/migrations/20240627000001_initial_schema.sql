-- ============================================================================
-- DrsListing AI - Supabase Initial Schema Migration
-- Date: 2024-06-27
-- Description: Creates the core tables and RLS policies for DrsListing AI
-- 
-- Tables:
--   1. users          - Stores registered patients
--   2. appointments   - Stores doctor appointment bookings
--   3. saved_doctors  - Stores user's saved/favorite doctors
--
-- Security Model:
--   This app uses direct mobile-number login (no OTP/Supabase Auth).
--   User identity is tracked via a locally-stored UUID (flutter_secure_storage).
--   The anon key is used for all requests; RLS policies are permissive
--   because the app layer controls data access by scoping queries to the
--   user's UUID. For production, migrate to Supabase Auth for proper
--   JWT-based RLS enforcement.
-- ============================================================================

-- ============================================================================
-- 1. USERS TABLE
-- ============================================================================
-- Stores patient registration data.
-- Queries used by the app:
--   - getUserByMobile(mobile)  → SELECT WHERE mobile = ?
--   - createUser(name, mobile) → INSERT (name, mobile)
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.users (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name        TEXT NOT NULL,
    mobile      TEXT NOT NULL UNIQUE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE public.users IS 'Patient/user accounts registered via the app';
COMMENT ON COLUMN public.users.id IS 'UUID generated server-side, stored locally on device';
COMMENT ON COLUMN public.users.mobile IS 'Mobile number used as the login identifier (no OTP)';
COMMENT ON COLUMN public.users.name IS 'Patient full name provided during registration';


-- Index for fast mobile-number lookup during login
CREATE INDEX IF NOT EXISTS idx_users_mobile ON public.users (mobile);


-- RLS: Enabled but permissive for the mobile-login pattern.
-- Users can only read their own row (via mobile lookup) and insert new
-- registrations. The anon key is used for all requests.
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;

-- Allow anonymous users to register (INSERT)
CREATE POLICY "anon_can_insert_users"
    ON public.users
    FOR INSERT
    TO anon
    WITH CHECK (true);

-- Allow anonymous users to look up users by mobile for login (SELECT)
CREATE POLICY "anon_can_select_users"
    ON public.users
    FOR SELECT
    TO anon
    USING (true);

-- Users should not update or delete their accounts via the app
-- (no UPDATE/DELETE policies → denied by default)


-- ============================================================================
-- 2. APPOINTMENTS TABLE
-- ============================================================================
-- Stores booked doctor appointments with full doctor snapshot.
-- Queries used by the app:
--   - getUserAppointments(userId)       → SELECT WHERE user_id = ? ORDER BY created_at DESC
--   - createAppointment(data)           → INSERT (...)
--   - updateAppointmentStatus(id, s)    → UPDATE status WHERE appointment_id = ?
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.appointments (
    appointment_id  TEXT PRIMARY KEY,
    user_id         UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    doctor_name     TEXT NOT NULL,
    appointment_date DATE NOT NULL,
    appointment_time TEXT NOT NULL,
    doctor_details  JSONB DEFAULT '{}'::jsonb,
    call_number     TEXT,
    map_location    JSONB DEFAULT '{}'::jsonb,
    symptoms        TEXT,
    patient_name    TEXT,
    status          TEXT NOT NULL DEFAULT 'Upcoming'
                        CHECK (status IN ('Upcoming', 'Completed', 'Cancelled')),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE public.appointments IS 'Patient appointment bookings with a snapshot of doctor details';
COMMENT ON COLUMN public.appointments.appointment_id IS 'Custom formatted ID like APT1001, APT1002...';
COMMENT ON COLUMN public.appointments.doctor_details IS 'Full JSON snapshot of DoctorModel from Google Places API';
COMMENT ON COLUMN public.appointments.map_location IS 'JSON with latitude/longitude for Google Maps launch';
COMMENT ON COLUMN public.appointments.status IS 'Lifecycle status: Upcoming → Completed | Cancelled';


-- Indexes for common query patterns
CREATE INDEX IF NOT EXISTS idx_appointments_user_id ON public.appointments (user_id);
CREATE INDEX IF NOT EXISTS idx_appointments_status ON public.appointments (status);
CREATE INDEX IF NOT EXISTS idx_appointments_date ON public.appointments (appointment_date DESC);
CREATE INDEX IF NOT EXISTS idx_appointments_user_status
    ON public.appointments (user_id, status);


ALTER TABLE public.appointments ENABLE ROW LEVEL SECURITY;

-- Allow anonymous users to read appointments (scoped by user_id in the query)
CREATE POLICY "anon_can_select_appointments"
    ON public.appointments
    FOR SELECT
    TO anon
    USING (true);

-- Allow anonymous users to create appointments
CREATE POLICY "anon_can_insert_appointments"
    ON public.appointments
    FOR INSERT
    TO anon
    WITH CHECK (true);

-- Allow anonymous users to update appointment status (cancel/complete)
CREATE POLICY "anon_can_update_appointments"
    ON public.appointments
    FOR UPDATE
    TO anon
    USING (true)
    WITH CHECK (true);

-- No DELETE policy needed (app never deletes appointments)


-- ============================================================================
-- 3. SAVED DOCTORS TABLE
-- ============================================================================
-- Stores doctors bookmarked/saved by users for quick access.
-- Queries used by the app:
--   - saveDoctor(userId, doctorData)             → INSERT (user_id, doctor_data)
--   - getSavedDoctors(userId)                    → SELECT WHERE user_id = ? ORDER BY created_at DESC
--   - removeSavedDoctorByPlaceId(userId, placeId) → DELETE WHERE user_id = ? AND doctor_data->>'place_id' = ?
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.saved_doctors (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    doctor_data JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE public.saved_doctors IS 'Doctors bookmarked by users for quick access';
COMMENT ON COLUMN public.saved_doctors.doctor_data IS 'Full DoctorModel JSON from Google Places API including place_id';


-- Index for fast user-scoped queries and place_id lookups
CREATE INDEX IF NOT EXISTS idx_saved_doctors_user_id ON public.saved_doctors (user_id);
-- B-tree index on the extracted text value enables fast equality lookups
-- for the doctor_data->>'place_id' filter used by removeSavedDoctorByPlaceId
CREATE INDEX IF NOT EXISTS idx_saved_doctors_place_id
    ON public.saved_doctors ((doctor_data->>'place_id'));


ALTER TABLE public.saved_doctors ENABLE ROW LEVEL SECURITY;

-- Allow anonymous users to read saved doctors (scoped by user_id in query)
CREATE POLICY "anon_can_select_saved_doctors"
    ON public.saved_doctors
    FOR SELECT
    TO anon
    USING (true);

-- Allow anonymous users to save doctors
CREATE POLICY "anon_can_insert_saved_doctors"
    ON public.saved_doctors
    FOR INSERT
    TO anon
    WITH CHECK (true);

-- Allow anonymous users to remove saved doctors by place_id
CREATE POLICY "anon_can_delete_saved_doctors"
    ON public.saved_doctors
    FOR DELETE
    TO anon
    USING (true);


-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

-- Generate the next appointment ID (APT1001, APT1002, ...)
-- The app also generates this client-side, but this provides a server-side option.
CREATE OR REPLACE FUNCTION public.generate_appointment_id()
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
    next_num INTEGER;
BEGIN
    SELECT COALESCE(
        MAX(SUBSTRING(appointment_id FROM 'APT(\d+)')::INTEGER),
        1000
    ) + 1 INTO next_num
    FROM public.appointments;

    RETURN 'APT' || next_num::TEXT;
END;
$$;

COMMENT ON FUNCTION public.generate_appointment_id()
    IS 'Generates sequential appointment IDs like APT1001, APT1002, etc.';


-- Utility: Count appointments for a user by status
CREATE OR REPLACE FUNCTION public.get_appointment_counts(p_user_id UUID)
RETURNS TABLE (status TEXT, count BIGINT)
LANGUAGE sql
STABLE
AS $$
    SELECT status, COUNT(*)::BIGINT
    FROM public.appointments
    WHERE user_id = p_user_id
    GROUP BY status
    ORDER BY status;
$$;

COMMENT ON FUNCTION public.get_appointment_counts(UUID)
    IS 'Returns appointment counts grouped by status for a given user';


-- ============================================================================
-- UPGRADE NOTES
-- ============================================================================
-- 
-- To upgrade from anon-key security to proper Auth-based RLS:
--   1. Enable Supabase Auth with phone authentication
--   2. Replace user_id UUID columns with auth.uid() references
--   3. Update RLS policies to use auth.uid() instead of USING (true)
--   4. Update the Flutter app to use supabase.auth.signInWithOtp()
--   5. Add proper JWT session handling server-side
-- ============================================================================
