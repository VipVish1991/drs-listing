-- ============================================================================
-- DrsListing — Push Notifications: device tokens on users
-- Date: 2026-08-06
--
-- Adds Firebase Cloud Messaging (FCM) registration-token storage to the
-- `users` table so the app can push appointment notifications:
--
--   * Appointment booked (app or web/QR)  → notify the DOCTOR
--   * Doctor changes an appointment status → notify the PATIENT
--
-- Multi-device support: `device_tokens` is a JSONB ARRAY of
-- { token, platform, updated_at } objects — one entry per registered device,
-- so the same user receives pushes on every device they've logged into.
--
-- The tokens are only ever written through SECURITY DEFINER RPC functions
-- (add_device_token / remove_device_token) which verify the caller owns the
-- row via the same x-user-id request-header convention the UPDATE RLS policy
-- uses — never through a direct table UPDATE from the anon key.
-- ============================================================================

-- ── Column: device_tokens ─────────────────────────────────────────
ALTER TABLE public.users
    ADD COLUMN IF NOT EXISTS device_tokens JSONB NOT NULL DEFAULT '[]'::jsonb;

COMMENT ON COLUMN public.users.device_tokens IS
    'FCM device registration tokens for push notifications. Array of '
    '{token, platform, updated_at} objects — one per device, so a user with '
    'several phones/tablets receives a notification on each. Managed only via '
    'add_device_token() / remove_device_token().';

-- Index for the notifications Edge Function (lookups by doctor_place_id) —
-- the token writes themselves are by primary key.
CREATE INDEX IF NOT EXISTS idx_users_doctor_place_id_token_lookup
    ON public.users (doctor_place_id)
    WHERE doctor_place_id IS NOT NULL;

-- ── RPC: add_device_token ─────────────────────────────────────────
-- Registers (or refreshes) an FCM token for the CALLER'S OWN row. Ownership
-- is proven by the x-user-id request header — the exact same convention the
-- users UPDATE RLS policy relies on, so this function is safe for the anon
-- key to execute (the caller can only ever touch their own tokens).
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
    v_tokens  JSONB;
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

    SELECT device_tokens INTO v_tokens
    FROM public.users
    WHERE id = v_user_id;

    v_tokens := COALESCE(v_tokens, '[]'::jsonb);

    -- Drop any previous entry with the same token, then re-append (refresh
    -- the platform/updated_at instead of duplicating the token).
    SELECT COALESCE(jsonb_agg(elem), '[]'::jsonb)
    INTO v_tokens
    FROM jsonb_array_elements(v_tokens) AS elem
    WHERE elem ->> 'token' <> p_token;

    v_tokens := v_tokens || jsonb_build_object(
        'token',      p_token,
        'platform',   p_platform,
        'updated_at', NOW()
    );

    UPDATE public.users
    SET device_tokens = v_tokens
    WHERE id = v_user_id;
END;
$$;

COMMENT ON FUNCTION public.add_device_token(TEXT, TEXT) IS
    'Registers (or refreshes) the caller''s FCM device token. Ownership is '
    'proven by the x-user-id request header, matching the users UPDATE RLS '
    'policy. Dedupes per token so a device re-login refreshes instead of '
    'duplicating.';

GRANT EXECUTE ON FUNCTION public.add_device_token(TEXT, TEXT) TO anon;

-- ── RPC: remove_device_token ──────────────────────────────────────
-- Removes a token from the caller's own row (used on logout so a shared
-- device never pushes the previous user's notifications to the next user).
CREATE OR REPLACE FUNCTION public.remove_device_token(p_token TEXT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id UUID;
    v_tokens  JSONB;
BEGIN
    v_user_id := (current_setting('request.headers', true)::jsonb ->> 'x-user-id')::UUID;
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'remove_device_token: missing x-user-id header'
            USING ERRCODE = 'P0001';
    END IF;
    IF p_token IS NULL OR btrim(p_token) = '' THEN
        RETURN; -- nothing to remove
    END IF;

    SELECT device_tokens INTO v_tokens
    FROM public.users
    WHERE id = v_user_id;

    SELECT COALESCE(jsonb_agg(elem), '[]'::jsonb)
    INTO v_tokens
    FROM jsonb_array_elements(COALESCE(v_tokens, '[]'::jsonb)) AS elem
    WHERE elem ->> 'token' <> p_token;

    UPDATE public.users
    SET device_tokens = v_tokens
    WHERE id = v_user_id;
END;
$$;

COMMENT ON FUNCTION public.remove_device_token(TEXT) IS
    'Removes an FCM device token from the caller''s own row (logout). '
    'Ownership proven by the x-user-id request header.';

GRANT EXECUTE ON FUNCTION public.remove_device_token(TEXT) TO anon;
