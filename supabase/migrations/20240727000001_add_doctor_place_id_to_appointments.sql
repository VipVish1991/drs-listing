-- ============================================================================
-- DrsListing AI - Add doctor_place_id column to appointments table
-- Date: 2024-07-27
-- Description: Adds a top-level doctor_place_id column to the appointments
--   table so the doctor dashboard can query appointments by doctor directly
--   using an indexed column instead of filtering on JSONB field
--   (doctor_details->>place_id).
--
-- Benefits:
--   - Indexed column query is much faster than JSONB traversal
--   - Simpler filter syntax: .eq('doctor_place_id', placeId)
--   - No dependency on the JSON structure of doctor_details
--
-- Backward compatibility:
--   Existing rows will have NULL doctor_place_id until the app is updated
--   to include it in new appointment inserts. The old JSONB filter in
--   getDoctorAppointments() is kept as a fallback for those rows.
-- ============================================================================

-- Add the column (nullable for backward compatibility with existing rows)
ALTER TABLE public.appointments
    ADD COLUMN IF NOT EXISTS doctor_place_id TEXT;

COMMENT ON COLUMN public.appointments.doctor_place_id
    IS 'Google Place ID of the doctor for efficient direct querying';

-- Index for fast doctor-specific queries
CREATE INDEX IF NOT EXISTS idx_appointments_doctor_place_id
    ON public.appointments (doctor_place_id);

-- Also index the status column which is queried alongside doctor_place_id
-- for the stats calculations (completed/cancelled/upcoming counts).
CREATE INDEX IF NOT EXISTS idx_appointments_status
    ON public.appointments (status);
