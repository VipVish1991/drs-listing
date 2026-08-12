-- ============================================================================
-- DrsListing AI - Prescription upload support
-- Date: 2026-08-04
-- Description:
--   1. appointments.consultation_type — the schedule type of the booking
--      ('tele' | 'video' | 'clinic'), captured at booking time so the
--      doctor side knows whether a Tele/Video consultation happened
--      (prescription upload is offered only for those two).
--   2. appointments.upload_prescription — TEXT[] of public storage URLs
--      of uploaded prescription photos (appended each time the doctor
--      uploads, so the gallery grows over time).
--   3. A public `prescriptions` storage bucket + RLS policies matching
--      the app's anon-key model (everyone can upload/read; the app layer
--      controls the actual flow).
-- ============================================================================

-- ── 1. Appointments columns ────────────────────────────────────────
ALTER TABLE public.appointments
    ADD COLUMN IF NOT EXISTS consultation_type TEXT;

ALTER TABLE public.appointments
    ADD COLUMN IF NOT EXISTS upload_prescription TEXT[] DEFAULT '{}';

COMMENT ON COLUMN public.appointments.consultation_type
    IS 'Booking schedule type: tele | video | clinic (null for legacy rows). Prescription upload is offered only for tele/video.';
COMMENT ON COLUMN public.appointments.upload_prescription
    IS 'Public Supabase Storage URLs of uploaded prescription photos, newest appended last.';

-- ── 2. Prescriptions storage bucket ────────────────────────────────
-- Public bucket so uploaded photos can be rendered straight from the
-- public URL (getPublicUrl) without extra auth in Image.network.
INSERT INTO storage.buckets (id, name, public)
VALUES ('prescriptions', 'prescriptions', true)
ON CONFLICT (id) DO NOTHING;

-- Storage RLS policies mirror the app's permissive anon-key model used
-- everywhere else: any anon client may upload/read prescription photos.
-- (The app never deletes prescriptions, so no DELETE policy is added.)
CREATE POLICY "prescriptions_anon_upload"
    ON storage.objects
    FOR INSERT
    TO anon
    WITH CHECK (bucket_id = 'prescriptions');

CREATE POLICY "prescriptions_anon_read"
    ON storage.objects
    FOR SELECT
    TO anon
    USING (bucket_id = 'prescriptions');

CREATE POLICY "prescriptions_anon_update"
    ON storage.objects
    FOR UPDATE
    TO anon
    USING (bucket_id = 'prescriptions')
    WITH CHECK (bucket_id = 'prescriptions');
