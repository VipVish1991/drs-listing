-- ============================================================================
-- DrsListing AI - Doctors & Availability Slots Migration
-- Date: 2024-07-20
-- Description: Creates the doctors table and doctor_slots table for storing
--   doctor/clinic profiles and their weekly consultation availability.
--
-- Tables:
--   1. doctors         - Stores doctor/clinic profiles (full data from Places API)
--   2. doctor_slots    - Stores weekly availability slots per doctor per day
--
-- Security Model:
--   Uses the same anon-key pattern as existing tables.
--   The app layer controls data access by scoping queries.
-- ============================================================================

-- ============================================================================
-- 1. DOCTORS TABLE
-- ============================================================================
-- Stores the full doctor/clinic profile data fetched from the Places API.
-- This is a canonical record that can be referenced by other tables.
-- Queries used by the app:
--   - saveDoctorToDb(doctor)   → INSERT ON CONFLICT (place_id) DO UPDATE
--   - getDoctorFromDb(placeId) → SELECT WHERE place_id = ?
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.doctors (
    place_id                    TEXT PRIMARY KEY,
    name                        TEXT NOT NULL,
    address                     TEXT,
    vicinity                    TEXT,
    latitude                    DOUBLE PRECISION,
    longitude                   DOUBLE PRECISION,
    phone_number                TEXT,
    international_phone_number  TEXT,
    website                     TEXT,
    url                         TEXT,
    plus_code                   TEXT,
    rating                      DOUBLE PRECISION,
    user_ratings_total          INTEGER,
    is_open                     BOOLEAN,
    business_status             TEXT,
    price_level                 INTEGER,
    photos                      JSONB DEFAULT '[]'::jsonb,
    photo_details               JSONB DEFAULT '[]'::jsonb,
    opening_hours               JSONB DEFAULT '[]'::jsonb,
    opening_hours_periods       JSONB DEFAULT '[]'::jsonb,
    reviews                     JSONB DEFAULT '[]'::jsonb,
    specialization              TEXT,
    hospital_name               TEXT,
    types                       JSONB DEFAULT '[]'::jsonb,
    address_components          JSONB DEFAULT '[]'::jsonb,
    editorial_summary           TEXT,
    experience_years            INTEGER,
    created_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE public.doctors IS 'Canonical doctor/clinic profiles synced from Google Places API';
COMMENT ON COLUMN public.doctors.place_id IS 'Google Place ID from the Places API';
COMMENT ON COLUMN public.doctors.photos IS 'Array of photo reference strings';
COMMENT ON COLUMN public.doctors.photo_details IS 'Full photo metadata objects';
COMMENT ON COLUMN public.doctors.opening_hours IS 'Weekday text descriptions';
COMMENT ON COLUMN public.doctors.opening_hours_periods IS 'Raw opening hours period objects';
COMMENT ON COLUMN public.doctors.reviews IS 'Full review objects from Places API';
COMMENT ON COLUMN public.doctors.address_components IS 'Structured address components (Google Places or Mapbox context)';
COMMENT ON COLUMN public.doctors.types IS 'Place types from Google Places API e.g. ["doctor", "health"]';
COMMENT ON COLUMN public.doctors.experience_years IS 'Years of experience (user-provided)';


-- Index for fast name and specialization lookups
CREATE INDEX IF NOT EXISTS idx_doctors_name ON public.doctors (name);
CREATE INDEX IF NOT EXISTS idx_doctors_specialization ON public.doctors (specialization);
CREATE INDEX IF NOT EXISTS idx_doctors_rating ON public.doctors (rating DESC);


ALTER TABLE public.doctors ENABLE ROW LEVEL SECURITY;

-- Allow anonymous users to read all doctors
CREATE POLICY "anon_can_select_doctors"
    ON public.doctors
    FOR SELECT
    TO anon
    USING (true);

-- Allow anonymous users to insert/update doctors (upsert pattern)
CREATE POLICY "anon_can_insert_doctors"
    ON public.doctors
    FOR INSERT
    TO anon
    WITH CHECK (true);

CREATE POLICY "anon_can_update_doctors"
    ON public.doctors
    FOR UPDATE
    TO anon
    USING (true)
    WITH CHECK (true);


-- ============================================================================
-- 2. DOCTOR SLOTS TABLE
-- ============================================================================
-- Stores weekly consultation availability for each doctor.
-- Each row represents one schedule type on one day of the week.
-- The `slots` JSONB column stores the auto-generated time slots.
-- Queries used by the app:
--   - getDoctorSlots(doctorPlaceId) → SELECT WHERE doctor_place_id = ?
--   - saveDoctorSlot(slot)          → INSERT ON CONFLICT ON CONSTRAINT
--     unique_doctor_day_type DO UPDATE
--   - deleteDoctorSlot(slotId)      → DELETE WHERE id = ?
--   - deleteDoctorSlotByDayType(placeId, day, type) → DELETE by composite
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.doctor_slots (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    doctor_place_id TEXT NOT NULL REFERENCES public.doctors(place_id) ON DELETE CASCADE,
    day_of_week     TEXT NOT NULL,
    schedule_type   TEXT NOT NULL CHECK (schedule_type IN ('tele', 'video', 'clinic')),
    -- schedule_type: tele = phone consultation, video = video call, clinic = in-person

    start_time      TEXT NOT NULL,           -- HH:MM format (24h)
    end_time        TEXT NOT NULL,           -- HH:MM format (24h)
    duration_minutes INTEGER NOT NULL DEFAULT 30,
    fee             INTEGER NOT NULL DEFAULT 0,

    -- Auto-generated time slots like ["09:00 AM", "09:30 AM", ...]
    slots           JSONB NOT NULL DEFAULT '[]'::jsonb,

    is_enabled      BOOLEAN NOT NULL DEFAULT true,

    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE public.doctor_slots IS 'Weekly availability slots for each consultation type per doctor';
COMMENT ON COLUMN public.doctor_slots.schedule_type IS 'Consultation type: tele (phone), video (video call), clinic (in-person)';
COMMENT ON COLUMN public.doctor_slots.start_time IS 'Start time in 24h HH:MM format, e.g. 09:00';
COMMENT ON COLUMN public.doctor_slots.end_time IS 'End time in 24h HH:MM format, e.g. 17:00';
COMMENT ON COLUMN public.doctor_slots.duration_minutes IS 'Duration per slot in minutes (e.g. 15, 30, 60)';
COMMENT ON COLUMN public.doctor_slots.fee IS 'Consultation fee in INR (₹)';
COMMENT ON COLUMN public.doctor_slots.slots IS 'Array of generated time slot strings like ["09:00 AM", "09:30 AM"]';
COMMENT ON COLUMN public.doctor_slots.is_enabled IS 'Whether this schedule row is active';


-- Unique constraint: one schedule row per doctor per day per type
-- (used by the app's upsert onConflict clause)
ALTER TABLE public.doctor_slots
    ADD CONSTRAINT doctor_slots_unique_key
    UNIQUE (doctor_place_id, day_of_week, schedule_type);

-- Index for fast doctor-scoped queries
CREATE INDEX IF NOT EXISTS idx_doctor_slots_doctor
    ON public.doctor_slots (doctor_place_id);

CREATE INDEX IF NOT EXISTS idx_doctor_slots_day
    ON public.doctor_slots (day_of_week);


ALTER TABLE public.doctor_slots ENABLE ROW LEVEL SECURITY;

-- Allow anonymous users to read all doctor slots
CREATE POLICY "anon_can_select_doctor_slots"
    ON public.doctor_slots
    FOR SELECT
    TO anon
    USING (true);

-- Allow anonymous users to insert/update slots
CREATE POLICY "anon_can_insert_doctor_slots"
    ON public.doctor_slots
    FOR INSERT
    TO anon
    WITH CHECK (true);

CREATE POLICY "anon_can_update_doctor_slots"
    ON public.doctor_slots
    FOR UPDATE
    TO anon
    USING (true)
    WITH CHECK (true);

CREATE POLICY "anon_can_delete_doctor_slots"
    ON public.doctor_slots
    FOR DELETE
    TO anon
    USING (true);


-- ============================================================================
-- HELPER: Auto-update updated_at timestamp
-- ============================================================================
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;

CREATE TRIGGER set_doctors_updated_at
    BEFORE UPDATE ON public.doctors
    FOR EACH ROW
    EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER set_doctor_slots_updated_at
    BEFORE UPDATE ON public.doctor_slots
    FOR EACH ROW
    EXECUTE FUNCTION public.update_updated_at_column();
