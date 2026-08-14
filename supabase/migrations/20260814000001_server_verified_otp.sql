-- ============================================================================
-- DrsListing — Server-verified OTP (replaces the hardcoded dev code 1111)
-- Date: 2026-08-14
--
-- WHY:
--   The app previously verified OTPs against the client-side constant
--   '1111' — a UNIVERSAL backdoor: anyone could register/login as ANY
--   mobile number (patient or doctor) by typing 1111. There was no
--   server involvement at all.
--
--   This migration makes OTP verification SERVER-SIDE:
--     * request_otp(mobile) generates a fresh 6-digit code, stores only a
--       SHA-256 hash (never the plaintext) with a 10-minute expiry and an
--       attempt counter, and returns the code so the app can display it
--       (DEMO MODE — there is no SMS provider wired up yet).
--     * verify_otp(mobile, code) checks the hash, expiry, and attempt
--       limit (5 tries) before returning true/false, and single-use
--       marks the code used on success.
--
--   This is strictly better than the old design but NOT production-grade:
--   request_otp returns the code to whoever calls it, so anyone can still
--   mint a code for any mobile and read it. In production, REPLACE the
--   `RETURN v_otp;` with an SMS/WhatsApp send (Twilio/MessageBird/etc.)
--   and return nothing. The rate limits (30s cooldown, 5 attempts, 10-min
--   expiry, single-use) already constrain abuse either way.
--
-- ⚠️ DEPLOYMENT ORDER: apply this migration together with the app release
--   that makes the OTP screens call request_otp()/verify_otp(). If the
--   migration lands first, the OLD app build (which checks the constant
--   '1111') still works — it never touches this table. If the NEW app
--   build lands first, request_otp() returns a 503 "function not found"
--   until the migration is applied — the screens must degrade gracefully
--   (they do: a request failure shows a friendly error, nothing crashes).
-- ============================================================================

-- SHA-256 hashing for OTP storage (never store plaintext codes).
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ── 1. OTP requests table ───────────────────────────────────────────────
-- One row per code issued. A mobile may have several rows; verification
-- always checks the LATEST unused, unexpired one.
CREATE TABLE IF NOT EXISTS public.otp_requests (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    mobile      TEXT NOT NULL,
    -- SHA-256 hex of the 6-digit code (plaintext is never stored).
    otp_hash    TEXT NOT NULL,
    expires_at  TIMESTAMPTZ NOT NULL,
    -- Wrong-code attempts against this code (max 5 → code invalidated).
    attempts    INT NOT NULL DEFAULT 0,
    used_at     TIMESTAMPTZ,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE public.otp_requests IS
    'Server-verified OTP codes (hash-only storage). request_otp() mints and verify_otp() checks. Demo mode returns the code to the app for display; production should SMS it instead.';
COMMENT ON COLUMN public.otp_requests.otp_hash IS 'SHA-256 hex of the 6-digit code — plaintext is never persisted.';
COMMENT ON COLUMN public.otp_requests.attempts IS 'Wrong-code attempts; 5 invalidates the code (verify_otp returns false thereafter).';
COMMENT ON COLUMN public.otp_requests.used_at IS 'Set on successful verification — codes are single-use.';

-- Cooldown + latest-code lookups by mobile.
CREATE INDEX IF NOT EXISTS idx_otp_requests_mobile
    ON public.otp_requests (mobile, created_at DESC);

-- No RLS needed: this table is only reachable through the SECURITY
-- DEFINER functions below (they bypass RLS by design and validate input).

-- ── 2. request_otp(mobile) — mint a fresh code ──────────────────────────
-- Generates a 6-digit code, stores its hash with a 10-minute expiry,
-- enforces a 30s per-mobile cooldown, and RETURNS the plaintext code so
-- the app can display it (demo mode — no SMS yet). In production, replace
-- `RETURN v_otp;` with an SMS send and return nothing.
CREATE OR REPLACE FUNCTION public.request_otp(p_mobile TEXT)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_mobile  TEXT;
    v_otp     TEXT;
    v_recent  TIMESTAMPTZ;
BEGIN
    v_mobile := btrim(p_mobile);
    IF v_mobile = '' OR v_mobile ~ '[^0-9]' OR length(v_mobile) < 10 THEN
        RAISE EXCEPTION 'Invalid mobile number' USING ERRCODE = 'P0001';
    END IF;

    -- Cooldown: max one code per mobile per 30 seconds.
    SELECT MAX(created_at) INTO v_recent
      FROM public.otp_requests
     WHERE mobile = v_mobile;
    IF v_recent IS NOT NULL AND (NOW() - v_recent) < interval '30 seconds' THEN
        RAISE EXCEPTION 'Please wait before requesting another code'
            USING ERRCODE = 'P0001';
    END IF;

    -- 6-digit code (000000–999999, zero-padded).
    v_otp := lpad(floor(random() * 1000000)::int::text, 6, '0');

    INSERT INTO public.otp_requests (mobile, otp_hash, expires_at)
    VALUES (
        v_mobile,
        encode(digest(v_otp, 'sha256'), 'hex'),
        NOW() + interval '10 minutes'
    );

    -- DEMO MODE: return the code so the app can display it.
    -- PRODUCTION: replace with SMS/WhatsApp delivery; return NULL.
    RETURN v_otp;
END;
$$;

COMMENT ON FUNCTION public.request_otp(TEXT) IS
    'Mints a 6-digit OTP for a mobile (30s cooldown, 10-min expiry) and returns it for DEMO display. Production: send via SMS and return nothing.';

-- ── 3. verify_otp(mobile, code) — server-side check ─────────────────────
-- Checks the latest unused, unexpired code for the mobile: max 5 wrong
-- attempts, hash match required, single-use. Returns true only on success.
CREATE OR REPLACE FUNCTION public.verify_otp(p_mobile TEXT, p_otp TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_mobile  TEXT;
    v_otp     TEXT;
    v_row     public.otp_requests%ROWTYPE;
    v_hash    TEXT;
BEGIN
    v_mobile := btrim(p_mobile);
    v_otp    := btrim(p_otp);
    IF v_mobile = '' OR v_otp = '' THEN
        RETURN FALSE;
    END IF;

    -- Latest code issued for this mobile that is still unused.
    SELECT * INTO v_row
      FROM public.otp_requests
     WHERE mobile = v_mobile
       AND used_at IS NULL
     ORDER BY created_at DESC
     LIMIT 1;

    IF v_row.id IS NULL THEN
        RETURN FALSE; -- no active code
    END IF;

    IF NOW() > v_row.expires_at THEN
        RETURN FALSE; -- expired
    END IF;

    IF v_row.attempts >= 5 THEN
        RETURN FALSE; -- attempt limit exhausted
    END IF;

    v_hash := encode(digest(v_otp, 'sha256'), 'hex');
    IF v_hash <> v_row.otp_hash THEN
        UPDATE public.otp_requests
           SET attempts = attempts + 1
         WHERE id = v_row.id;
        RETURN FALSE;
    END IF;

    -- Single-use: mark consumed on success.
    UPDATE public.otp_requests
       SET used_at = NOW()
     WHERE id = v_row.id;
    RETURN TRUE;
END;
$$;

COMMENT ON FUNCTION public.verify_otp(TEXT, TEXT) IS
    'Server-side OTP check: latest unused code, 10-min expiry, max 5 attempts, SHA-256 match, single-use.';

-- ── 4. Grant to the app's roles ─────────────────────────────────────────
-- The anon key (with the app's x-user-* headers) and any authenticated
-- client may call both functions; SECURITY DEFINER lets them read/write
-- otp_requests without RLS while the functions themselves validate input.
GRANT EXECUTE ON FUNCTION public.request_otp(TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.verify_otp(TEXT, TEXT) TO anon, authenticated;
