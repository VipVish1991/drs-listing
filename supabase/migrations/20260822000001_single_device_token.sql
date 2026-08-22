-- ============================================================================
-- DrsListing — Single device token per user
-- Date: 2026-08-22
--
-- Problem: add_device_token() accumulated an array of tokens over time.
-- Each login/registration appended a new entry (deduped by token value),
-- so users who reinstall or switch accounts ended up with stale entries
-- from old sessions. The array grew unbounded.
--
-- Fix: Replace add_device_token() so it ALWAYS stores exactly ONE token.
-- When a new token is saved, the entire device_tokens array is replaced
-- with a single-element array containing only the new token. This
-- guarantees:
--   1. Only the current device receives pushes (no stale token leaks)
--   2. The array never grows beyond 1 entry
--   3. Logout + re-login with a new token cleanly replaces the old one
--
-- remove_device_token() is also simplified: it just empties the array
-- since there's only ever one token.
-- ============================================================================

-- ── RPC: add_device_token (single-token version) ─────────────────
-- Registers the caller's FCM device token, REPLACING any existing token.
-- Ownership proven by the x-user-id request header (same convention as
-- the users UPDATE RLS policy).
CREATE OR REPLACE FUNCTION public.add_device_token(
    p_token    TEXT,
    p_platform TEXT DEFAULT 'android'
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id UUID;
BEGIN
    v_user_id := (current_setting('request.headers', true)::jsonb ->> 'x-user-id')::UUID;
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'add_device_token: missing x-user-id header'
            USING ERRCODE = 'P0001';
    END IF;
    IF p_token IS NULL OR btrim(p_token) = '' THEN
        RAISE EXCEPTION 'add_device_token: empty token'
            USING ERRCODE = 'P0001';
    END IF;

    -- Always replace with a single-element array containing only this token.
    UPDATE public.users
    SET device_tokens = jsonb_build_array(
        jsonb_build_object(
            'token',      p_token,
            'platform',   p_platform,
            'updated_at', NOW()
        )
    )
    WHERE id = v_user_id;
END;
$$;

COMMENT ON FUNCTION public.add_device_token(TEXT, TEXT) IS
    'Registers the caller''s FCM device token, ALWAYS replacing any '
    'existing token (single token per user). Ownership proven by the '
    'x-user-id request header.';

GRANT EXECUTE ON FUNCTION public.add_device_token(TEXT, TEXT) TO anon;

-- ── RPC: remove_device_token (single-token version) ──────────────
-- Clears the device_tokens array entirely (there's only ever one token).
-- Used on logout so a shared device stops receiving the previous user's
-- notifications.
CREATE OR REPLACE FUNCTION public.remove_device_token(p_token TEXT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id UUID;
BEGIN
    v_user_id := (current_setting('request.headers', true)::jsonb ->> 'x-user-id')::UUID;
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'remove_device_token: missing x-user-id header'
            USING ERRCODE = 'P0001';
    END IF;
    IF p_token IS NULL OR btrim(p_token) = '' THEN
        RETURN; -- nothing to remove
    END IF;

    -- Clear the entire array — there's only ever one token.
    UPDATE public.users
    SET device_tokens = '[]'::jsonb
    WHERE id = v_user_id;
END;
$$;

COMMENT ON FUNCTION public.remove_device_token(TEXT) IS
    'Clears the device_tokens array (single token per user). '
    'Called on logout. Ownership proven by the x-user-id request header.';

GRANT EXECUTE ON FUNCTION public.remove_device_token(TEXT) TO anon;
