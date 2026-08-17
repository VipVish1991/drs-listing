-- Backfill the static Google Meet room onto ALL existing appointments
-- that don't have a link yet (including in-clinic visits).
--
-- New bookings store 'https://meet.google.com/rnz-wivx-yze' — the Flutter
-- booking flow and the booking-page Edge Function write it at insert
-- time. This backfill brings older rows created before that change up to
-- the same shared room, so the patient and the clinic always join the
-- SAME meeting regardless of when the appointment was booked.
--
-- Deliberately scoped: only rows with a NULL/empty meet_link — a stored
-- link (e.g. a room created under the old SDK flow) is never overwritten.
--
-- Idempotent: running it again is a no-op because no matching row is
-- left with a missing link.
UPDATE public.appointments
SET meet_link = 'https://meet.google.com/rnz-wivx-yze'
WHERE meet_link IS NULL OR meet_link = '';
