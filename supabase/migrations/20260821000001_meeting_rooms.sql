-- Meeting room pool: tracks which Google Meet rooms are available and which
-- appointment is currently using each one. Only 2 people (doctor + patient)
-- can occupy a room at a time. When a consultation ends, the room is freed
-- for the next booking.
--
-- The pool is seeded with static Google Meet room URLs. New rooms can be
-- added manually by inserting rows. The Dart RoomAllocationService picks
-- the first available room when a doctor/patient joins a consultation.

CREATE TABLE IF NOT EXISTS public.meeting_rooms (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    room_url      TEXT NOT NULL UNIQUE,
    status        TEXT NOT NULL DEFAULT 'available'
                  CHECK (status IN ('available', 'in_use')),
    appointment_id TEXT,
    doctor_place_id TEXT,
    patient_user_id TEXT,
    allocated_at  TIMESTAMPTZ,
    expires_at    TIMESTAMPTZ,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.meeting_rooms IS
    'Google Meet room pool — one row per static room URL. Tracks occupancy '
    'so only 2 people (doctor + patient) join the same room at a time. '
    'Rooms auto-free when the appointment completes/cancels or expires.';

COMMENT ON COLUMN public.meeting_rooms.room_url IS
    'Static Google Meet room URL (e.g. https://meet.google.com/rnz-wivx-yze).';

COMMENT ON COLUMN public.meeting_rooms.status IS
    'available = free to use; in_use = occupied by an active consultation.';

COMMENT ON COLUMN public.meeting_rooms.appointment_id IS
    'The appointment currently using this room (nullable — NULL when available).';

COMMENT ON COLUMN public.meeting_rooms.expires_at IS
    'Hard expiry — room is auto-freed after this time even if not explicitly '
    'released (safety net for abandoned meetings).';

-- Index: fast lookup of the first available room.
CREATE INDEX IF NOT EXISTS idx_meeting_rooms_status
    ON public.meeting_rooms (status)
    WHERE status = 'available';

-- Index: fast lookup by appointment (to free the room on complete/cancel).
CREATE INDEX IF NOT EXISTS idx_meeting_rooms_appointment
    ON public.meeting_rooms (appointment_id)
    WHERE appointment_id IS NOT NULL;

-- Index: auto-expire stale in_use rooms (cron / on-demand cleanup).
CREATE INDEX IF NOT EXISTS idx_meeting_rooms_expires
    ON public.meeting_rooms (expires_at)
    WHERE status = 'in_use';

-- Seed the pool with the existing static room plus additional rooms.
-- Google Meet free accounts can create unlimited named rooms; these are
-- fixed URLs that anyone can join without signing in.
INSERT INTO public.meeting_rooms (room_url) VALUES
    ('https://meet.google.com/rnz-wivx-yze'),
    ('https://meet.google.com/abc-defg-hij'),
    ('https://meet.google.com/klm-nopq-rst'),
    ('https://meet.google.com/uvw-xyza-bcd'),
    ('https://meet.google.com/efg-hijk-lmn')
ON CONFLICT (room_url) DO NOTHING;

-- RLS: only the service role (Edge Functions + Flutter app via x-user-id)
-- should read/write this table. No patient or doctor can modify rooms
-- directly.
ALTER TABLE public.meeting_rooms ENABLE ROW LEVEL SECURITY;

-- Service role bypasses RLS, but explicit policies let the app read room
-- status (e.g. to show "meeting in progress" badges).
CREATE POLICY "Service role full access"
    ON public.meeting_rooms
    FOR ALL
    TO service_role
    USING (true)
    WITH CHECK (true);

CREATE POLICY "Authenticated users can read rooms"
    ON public.meeting_rooms
    FOR SELECT
    TO authenticated
    USING (true);

-- Updated_at trigger (auto-set on every write).
CREATE OR REPLACE FUNCTION public.update_meeting_room_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER meeting_rooms_updated_at
    BEFORE UPDATE ON public.meeting_rooms
    FOR EACH ROW
    EXECUTE FUNCTION public.update_meeting_room_updated_at();
