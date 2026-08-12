-- ============================================================================
-- DrsListing — Tighten RLS on public.users
-- Date: 2026-08-01
--
-- WHY:
--   The previous anon policies let ANY anon-key client:
--     * read EVERY user row (all mobile numbers, roles, doctor_place_ids)
--     * UPDATE any row (e.g. escalate a patient to doctor, hijack another
--       clinic's doctor_place_id)
--
--   The QR web booking page (supabase/functions/booking-page) writes to
--   users with the SERVICE ROLE key, which BYPASSES RLS — so it is
--   unaffected by these policies.
--
--   The mobile app talks to PostgREST with the anon key, so it must prove
--   ownership of the rows it touches.  lib/services/supabase_service.dart
--   attaches custom request headers that these policies scope on:
--
--     x-user-mobile  → SELECT / INSERT  (the app only knows the typed
--                      mobile at lookup/registration time)
--     x-user-id      → UPDATE           (the app knows the row UUID once
--                      the account exists)
--
--   Headers are read via current_setting('request.headers', true), which
--   PostgREST populates from the incoming HTTP request (names lowercased).
--
-- ⚠️ DEPLOYMENT ORDER: apply this migration TOGETHER WITH the app release
--   that adds usersContextHeaders() to lib/services/supabase_service.dart.
--   If the migration lands first, the current app build can no longer
--   read the users table (login/registration would appear "not registered").
--
-- ⚠️ Residual risk (accepted): because the phone number is the login
--   identifier, any client that knows a victim's mobile can still SELECT
--   that one user's row. What this change actually fixes is mass
--   enumeration of all users and cross-row UPDATEs (privilege escalation
--   / hijacking doctor_place_id).
-- ============================================================================

-- ── 1. Drop the old permissive anon policies ─────────────────────────────
DROP POLICY IF EXISTS "anon_can_select_users" ON public.users;
DROP POLICY IF EXISTS "anon_can_insert_users" ON public.users;
DROP POLICY IF EXISTS "anon_can_update_users" ON public.users;

-- Idempotency: drop the scoped policies too so re-runs are safe.
DROP POLICY IF EXISTS "users_select_own_row" ON public.users;
DROP POLICY IF EXISTS "users_insert_own_row" ON public.users;
DROP POLICY IF EXISTS "users_update_own_row" ON public.users;

-- ── 2. SELECT — own row only (matched by the x-user-mobile header) ───────
CREATE POLICY "users_select_own_row" ON public.users
  FOR SELECT
  TO anon, authenticated
  USING (
    (current_setting('request.headers', true)::jsonb ->> 'x-user-mobile') = mobile::text
  );

-- ── 3. INSERT — can only create the row whose mobile the header names ────
CREATE POLICY "users_insert_own_row" ON public.users
  FOR INSERT
  TO anon, authenticated
  WITH CHECK (
    (current_setting('request.headers', true)::jsonb ->> 'x-user-mobile') = mobile::text
  );

-- ── 4. UPDATE — only the row whose id the x-user-id header names ─────────
CREATE POLICY "users_update_own_row" ON public.users
  FOR UPDATE
  TO anon, authenticated
  USING (
    (current_setting('request.headers', true)::jsonb ->> 'x-user-id') = id::text
  )
  WITH CHECK (
    (current_setting('request.headers', true)::jsonb ->> 'x-user-id') = id::text
  );
