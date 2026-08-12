-- ============================================================================
-- DrsListing AI - Google Places API Usage Count Migration
-- Date: 2024-08-05
-- Description: Tracks how many times the Google Places (health search) API
--   is called, counted per day per endpoint. This lets the team monitor
--   API spend and validate that the local cache is reducing call volume.
--
-- Tables:
--   1. api_usage_count  - One row per (usage_date, endpoint) holding a
--     running daily counter, incremented atomically via the
--     increment_api_usage RPC function.
--
-- App usage (SupabaseService):
--   - incrementApiUsage(endpoint) → SELECT increment_api_usage(p_endpoint)
--   - getApiUsageToday()          → SELECT SUM(count) WHERE usage_date = today
--   - getApiUsageForDate(date, endpoint) → SELECT count WHERE both match
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.api_usage_count (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    usage_date  DATE NOT NULL DEFAULT CURRENT_DATE,
    endpoint    TEXT NOT NULL,
    count       INTEGER NOT NULL DEFAULT 0,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- One counter per endpoint per day
    CONSTRAINT api_usage_count_unique_day_endpoint UNIQUE (usage_date, endpoint)
);

COMMENT ON TABLE public.api_usage_count IS 'Daily Google Places API call counts (cost tracking)';
COMMENT ON COLUMN public.api_usage_count.usage_date IS 'Calendar day the calls were made';
COMMENT ON COLUMN public.api_usage_count.endpoint IS 'API endpoint, e.g. text_search, place_details';
COMMENT ON COLUMN public.api_usage_count.count IS 'Number of calls made to this endpoint on this day';


-- Index for fast daily rollups
CREATE INDEX IF NOT EXISTS idx_api_usage_count_date
    ON public.api_usage_count (usage_date);


ALTER TABLE public.api_usage_count ENABLE ROW LEVEL SECURITY;

-- Allow anonymous users to read usage counts (scoped by date in the query)
CREATE POLICY "anon_can_select_api_usage_count"
    ON public.api_usage_count
    FOR SELECT
    TO anon
    USING (true);


-- ============================================================================
-- INCREMENT RPC
-- ============================================================================
-- Atomically increments today's counter for a given endpoint.
-- Creates the row on first call of the day, then bumps `count`.
-- SECURITY DEFINER so the anon role can upsert through the function.
CREATE OR REPLACE FUNCTION public.increment_api_usage(p_endpoint TEXT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    INSERT INTO public.api_usage_count (usage_date, endpoint, count)
    VALUES (CURRENT_DATE, p_endpoint, 1)
    ON CONFLICT (usage_date, endpoint)
    DO UPDATE SET count = public.api_usage_count.count + 1,
                  updated_at = NOW();
END;
$$;

COMMENT ON FUNCTION public.increment_api_usage(TEXT)
    IS 'Increments today''s call counter for the given Places API endpoint';

GRANT EXECUTE ON FUNCTION public.increment_api_usage(TEXT) TO anon;
