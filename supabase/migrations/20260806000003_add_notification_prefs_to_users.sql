-- ============================================================================
-- DrsListing — Push Notifications: per-user preferences
-- Date: 2026-08-06
--
-- Adds `notification_prefs` to `users` so each user can toggle which push
-- alerts they receive. Keys are the notifications Edge Function's event
-- names:
--
--   appointment_booked         → "New bookings"     (recipient: the doctor)
--   appointment_cancelled      → "Cancellations"    (recipient: the doctor)
--   appointment_status_changed → "Status updates"   (recipient: the patient)
--
-- The Edge Function reads this map for the RECIPIENT of each notification
-- and skips delivery when the value is `false` — so the preference is
-- enforced server-side (the sender's device can't know the recipient's
-- choice, and the web/QR booking flow goes through the same function).
--
-- Values default to true for every event; a missing key also means "send"
-- (fail-open), so accounts that never opened the settings screen keep
-- receiving everything.
--
-- Writes go through the EXISTING users UPDATE RLS policy (x-user-id header
-- convention) — no new RPC needed.
-- ============================================================================

ALTER TABLE public.users
    ADD COLUMN IF NOT EXISTS notification_prefs JSONB NOT NULL DEFAULT
        '{"appointment_booked": true, "appointment_cancelled": true, "appointment_status_changed": true}'::jsonb;

COMMENT ON COLUMN public.users.notification_prefs IS
    'Per-user push-notification preferences. JSONB map of event name → bool, '
    'where event names match the notifications Edge Function (appointment_booked, '
    'appointment_cancelled, appointment_status_changed). A missing key or true '
    'means "send"; false means "skip". Defaults to all events enabled.';
