-- ============================================================================
-- DrsListing — Push Notifications: retention policy
-- Date: 2026-08-06
--
-- Auto-cleans old rows from the in-app `notifications` history table so it
-- stays bounded as pushes accumulate. Two complementary mechanisms:
--
--   1. PRIMARY: a pg_cron job runs `prune_old_notifications(90)` every day
--      at 03:00 server time, deleting rows older than 90 days.
--   2. SAFETY NET: the notifications Edge Function also prunes
--      opportunistically (once per hour per instance) so the table stays
--      bounded even on projects where pg_cron cannot be enabled.
--
-- The retention window (90 days) is a parameter of the function, so it can
-- be changed by editing the cron job or calling the function with a
-- different day count — no schema change required.
-- ============================================================================

-- ── Index for the retention DELETE ───────────────────────────────
-- The existing (user_id, created_at DESC) index helps per-user reads but
-- not a global created_at scan; a dedicated index keeps the nightly prune
-- fast as the table grows.
CREATE INDEX IF NOT EXISTS idx_notifications_created_at
    ON public.notifications (created_at);

-- ── Retention function ───────────────────────────────────────────
-- Deletes history rows older than p_days and returns how many were removed.
-- SECURITY DEFINER so the cron job (and the service-role Edge Function)
-- can call it without RLS interference; search_path is pinned.
CREATE OR REPLACE FUNCTION public.prune_old_notifications(
    p_days integer DEFAULT 90
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_deleted integer;
BEGIN
    DELETE FROM public.notifications
    WHERE created_at < NOW() - make_interval(days => p_days);
    GET DIAGNOSTICS v_deleted = ROW_COUNT;
    RETURN v_deleted;
END;
$$;

COMMENT ON FUNCTION public.prune_old_notifications(integer) IS
    'Retention policy for the in-app notification history: deletes rows '
    'older than p_days (default 90) and returns the count removed. Called '
    'daily by the pg_cron job `prune-notifications-daily` and '
    'opportunistically by the notifications Edge Function.';

-- Lock it down: the function is SECURITY DEFINER (RLS bypassed) with a
-- GLOBAL delete parameterized by p_days — a client calling
-- prune_old_notifications(0) would wipe the whole table. The Edge Function
-- does NOT use this RPC (it deletes directly via the service role), so only
-- the cron job (running as postgres) needs it.
REVOKE ALL ON FUNCTION public.prune_old_notifications(integer)
    FROM PUBLIC, anon, authenticated;

-- ── Enable pg_cron (if the image allows it) ──────────────────────
-- Graceful: if pg_cron cannot be created here, the Edge Function's
-- opportunistic prune still keeps the table bounded.
-- NOTE: $do$ (not $$) delimiters — the cron.schedule command below nests
-- a second dollar-quoted string, and nesting the SAME delimiter is a
-- syntax error. Distinct tags are required.
DO $do$
BEGIN
    CREATE EXTENSION IF NOT EXISTS pg_cron;
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'pg_cron could not be enabled (%). Relying on Edge Function opportunistic pruning.', SQLERRM;
END;
$do$;

-- ── Schedule the daily retention job (idempotent) ────────────────
DO $do$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
        -- Drop any previous version of the job first so re-runs don't stack.
        PERFORM cron.unschedule(jobid)
        FROM cron.job
        WHERE jobname = 'prune-notifications-daily';

        PERFORM cron.schedule(
            'prune-notifications-daily',
            '0 3 * * *',   -- 03:00 daily, server timezone
            $$SELECT public.prune_old_notifications(90)$$
        );
    END IF;
END;
$do$;

-- ── One-time immediate prune ─────────────────────────────────────
-- Cleans rows that predate this policy right away (currently 0 rows live,
-- but keeps the table tidy on projects where history accumulated already).
SELECT public.prune_old_notifications(90);
