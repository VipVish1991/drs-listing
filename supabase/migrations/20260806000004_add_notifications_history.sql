-- ============================================================================
-- DrsListing — Push Notifications: in-app history table
-- Date: 2026-08-06
--
-- Adds a `notifications` table that records every push notification sent
-- to a user, so the app can show an in-app notification center with the
-- full history of received alerts (not just what arrived while the app
-- was open).
--
--   * The notifications Edge Function writes one row per RECIPIENT user
--     whenever it sends a push (service role → RLS bypassed).
--   * The app reads + marks-read its own rows through the same x-user-id
--     request-header convention the users UPDATE policy uses — an anon
--     client can only ever see/touch its own notifications.
--   * `read` powers the unread badge; `data` carries the deep-link payload
--     (appointment_id, doctor_place_id, status) so tapping a row can
--     navigate to the right screen.
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.notifications (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    type        TEXT NOT NULL,
    title       TEXT NOT NULL,
    body        TEXT,
    data        JSONB NOT NULL DEFAULT '{}'::jsonb,
    read        BOOLEAN NOT NULL DEFAULT false,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE public.notifications IS
    'In-app push-notification history. One row per recipient per push sent '
    'by the notifications Edge Function; read by the app (x-user-id scoped) '
    'to power the notification center.';
COMMENT ON COLUMN public.notifications.type IS
    'Event type matching the notifications Edge Function: appointment_booked, '
    'appointment_cancelled or appointment_status_changed.';
COMMENT ON COLUMN public.notifications.data IS
    'Deep-link payload: {appointment_id, doctor_place_id, status} — used to '
    'navigate when the user taps the notification.';
COMMENT ON COLUMN public.notifications.read IS
    'Whether the user has opened/seen this notification (unread badge source).';

-- Fast per-user history reads ordered newest-first.
CREATE INDEX IF NOT EXISTS idx_notifications_user_created
    ON public.notifications (user_id, created_at DESC);

-- Only the user's unread count matters for the badge — partial index keeps
-- it small.
CREATE INDEX IF NOT EXISTS idx_notifications_user_unread
    ON public.notifications (user_id)
    WHERE NOT read;

ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

-- SELECT / UPDATE are scoped to the x-user-id header (the app knows its own
-- UUID once logged in). The Edge Function inserts via the service role, so
-- no anon INSERT/DELETE policies are needed. Compared as TEXT (not casting
-- the header to UUID) so a malformed header fails closed with zero rows
-- instead of throwing — same pattern as the users UPDATE policy.
CREATE POLICY "notifications_select_own" ON public.notifications
    FOR SELECT
    TO anon, authenticated
    USING (
        (current_setting('request.headers', true)::jsonb ->> 'x-user-id') = user_id::text
    );

CREATE POLICY "notifications_update_own" ON public.notifications
    FOR UPDATE
    TO anon, authenticated
    USING (
        (current_setting('request.headers', true)::jsonb ->> 'x-user-id') = user_id::text
    )
    WITH CHECK (
        (current_setting('request.headers', true)::jsonb ->> 'x-user-id') = user_id::text
    );
