-- ============================================================================
-- DrsListing — Push Notifications: master switch
-- Date: 2026-08-06
--
-- Adds an `all` key to `users.notification_prefs` that acts as a master
-- switch: `"all": false` disables EVERY push for the user at once, regardless
-- of the per-event keys. The notifications Edge Function checks it FIRST —
-- a user with `all: false` gets nothing.
--
-- Design notes:
--   * The per-event keys (appointment_booked / appointment_cancelled /
--     appointment_status_changed) are PRESERVED underneath, so toggling the
--     master off and back on restores the user's granular choices instead of
--     wiping them.
--   * Fail-open: a missing `all` key (accounts created before this
--     migration) means "send" — nobody silently loses alerts.
-- ============================================================================

-- ── New default includes the master switch ───────────────────────
ALTER TABLE public.users
    ALTER COLUMN notification_prefs SET DEFAULT
        '{"appointment_booked": true, "appointment_cancelled": true, "appointment_status_changed": true, "all": true}'::jsonb;

-- ── Backfill existing rows (fail-open: treat as enabled) ─────────
UPDATE public.users
SET notification_prefs = notification_prefs || '{"all": true}'::jsonb
WHERE NOT notification_prefs ? 'all';

COMMENT ON COLUMN public.users.notification_prefs IS
    'Per-user push-notification preferences. JSONB map of event name → bool '
    '(appointment_booked, appointment_cancelled, appointment_status_changed) '
    'plus a master key `all` checked FIRST by the notifications Edge '
    'Function — false disables every alert at once while the per-event keys '
    'stay preserved. A missing key or true means "send"; false means "skip". '
    'Defaults to all events + master enabled.';
