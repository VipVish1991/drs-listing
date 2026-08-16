-- Google Meet consultation link (video/tele) — re-added after the
-- WebView-era migration (20260814000004) was deleted in the SDK refactor.
--
-- The appointment's shared Google Meet URL for VIDEO/TELE consultations.
-- Stays NULL until either side starts a meeting (Google Sign-In → calendar
-- event → meet.google.com/<id> link); the flow then SAVES the link here so
-- BOTH the patient and the owning clinic join the SAME room — the details
-- sheet reuses a stored link instead of creating a new event each time.
-- Both the patient and the owning clinic can write it (the appointments
-- UPDATE policy is column-agnostic).
--
-- Idempotent: the column already exists on the live project (applied in
-- the Meet era), so ADD COLUMN IF NOT EXISTS is a no-op there; fresh
-- environments get the column from this file.
ALTER TABLE public.appointments
    ADD COLUMN IF NOT EXISTS meet_link TEXT;

COMMENT ON COLUMN public.appointments.meet_link IS
    'Shared Google Meet URL for video/tele consultations (null until a meeting is started and the link is saved).';
