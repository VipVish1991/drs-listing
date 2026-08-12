-- ============================================================================
-- DrsListing - Add Google Places API fields to doctors table
-- Date: 2024-08-04
-- Description: Adds 3 new columns to the doctors table that map to fields
--   available from the Google Places API (Text Search + Place Details).
--
-- New columns:
--   1. primary_type             TEXT     – Google's primary place type
--      e.g. "cardiologist", "general_doctor", "dentist", "hospital"
--      More specific than the generic types[] array.
--
--   2. wheelchair_accessible    BOOLEAN  – wheelchair_accessible_entrance
--      from the Places API. Critical accessibility info for patients.
--
--   3. current_opening_hours    JSONB    – Real-time opening hours that
--      account for holiday schedules, temporary closures, etc.
--      Stored as a JSON object with weekday_text, periods, etc.
-- ============================================================================

-- Add primary_type column (TEXT, nullable for backward compatibility)
ALTER TABLE public.doctors
    ADD COLUMN IF NOT EXISTS primary_type TEXT;

COMMENT ON COLUMN public.doctors.primary_type
    IS 'Google primary place type e.g. cardiologist, general_doctor, dentist, hospital';

-- Create index for filtering by primary type
CREATE INDEX IF NOT EXISTS idx_doctors_primary_type
    ON public.doctors (primary_type);


-- Add wheelchair_accessible column (BOOLEAN, nullable)
ALTER TABLE public.doctors
    ADD COLUMN IF NOT EXISTS wheelchair_accessible BOOLEAN;

COMMENT ON COLUMN public.doctors.wheelchair_accessible
    IS 'Whether the entrance is wheelchair accessible (from Places API)';


-- Add current_opening_hours column (JSONB, default empty object)
ALTER TABLE public.doctors
    ADD COLUMN IF NOT EXISTS current_opening_hours JSONB DEFAULT '{}'::jsonb;

COMMENT ON COLUMN public.doctors.current_opening_hours
    IS 'Real-time opening hours accounting for holiday schedules, temporary closures';

-- Update the plus_code comment to clarify both global_code and compound_code
-- are available from the API (no index needed for compound_code at this time).
COMMENT ON COLUMN public.doctors.plus_code
    IS 'Google Plus Code e.g. "7MH37M6G+R6" (global_code) — human-friendly compound_code also available from API';
