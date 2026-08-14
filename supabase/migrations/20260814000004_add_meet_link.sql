-- Google Meet video-call integration (launcher + share, no API keys).
--
-- The appointment's shared Google Meet URL for VIDEO consultations. Stays
-- NULL until either side starts a meeting (meet.new) and pastes the real
-- Google-generated link back into the app; both the patient and the owning
-- clinic can write it (the appointments UPDATE policy is column-agnostic).
ALTER TABLE public.appointments
    ADD COLUMN IF NOT EXISTS meet_link TEXT;

COMMENT ON COLUMN public.appointments.meet_link IS
    'Shared Google Meet URL for video consultations (null until a meeting is started and the link is saved).';
