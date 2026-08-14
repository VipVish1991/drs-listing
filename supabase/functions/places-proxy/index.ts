// ═══════════════════════════════════════════════════════════════════
// DrsListing — Google Places API Proxy (Supabase Edge Function)
//
// Proxies the Google Places Text Search and Place Details APIs so
// that the Flutter web build avoids CORS errors (browsers block
// direct calls to maps.googleapis.com).
//
// Endpoints:
//   GET  /textsearch/json?query=...&location=...&radius=...&token=<secret>
//   GET  /details/json?place_id=...&fields=...&token=<secret>
//
// Security: every request must carry the shared `token` query parameter
// (constant-time compared). Without it the proxy refuses to relay — this
// stops random internet traffic from burning the Google Maps API quota
// (which the anon key alone cannot prevent). The token is embedded in the
// app (extractable, same tradeoff as the booking/notify secrets), so it
// gates casual/automated abuse rather than being a hard auth boundary.
//
// Environment variables (set in Supabase Dashboard):
//   GOOGLE_MAPS_API_KEY   — required
//   PLACES_SHARED_SECRET  — required; must match AppConstants.placesProxyToken
//
// Usage tracking: every request relayed to Google is recorded in the
// `api_usage_count` table (see
// supabase/migrations/20240805000001_add_api_usage_count.sql) via the
// increment_api_usage RPC. Because the Flutter app routes ALL Places
// calls through this proxy (mobile + web), it is the single counting
// point — do NOT also increment from the client or calls double-count.
// ═══════════════════════════════════════════════════════════════════

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const GOOGLE_PLACES_BASE = "https://maps.googleapis.com/maps/api/place";
const GOOGLE_MAPS_API_KEY = Deno.env.get("GOOGLE_MAPS_API_KEY") ?? "";
const PLACES_SECRET = Deno.env.get("PLACES_SHARED_SECRET") ?? "";

// Auto-injected by Supabase into every Edge Function.
const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY") ?? "";

/** Constant-time string compare (same helper as the booking-page fn). */
function secureEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) {
    diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return diff === 0;
}

serve(async (req) => {
  // ── CORS preflight ─────────────────────────────────────────────
  if (req.method === "OPTIONS") {
    return corsResponse(null, 204);
  }

  try {
    // ── Shared-secret gate (fail closed if unconfigured) ───────────
    if (!PLACES_SECRET) {
      return corsResponse(
        { error: "Places proxy is not configured yet." },
        503,
      );
    }
    const url = new URL(req.url);
    const token = url.searchParams.get("token") ?? "";
    if (!secureEqual(token, PLACES_SECRET)) {
      return corsResponse({ error: "Invalid token." }, 401);
    }

    const path = url.pathname.replace(/^\/functions\/v1\/places-proxy/, "")
                              .replace(/^\/places-proxy/, "");

    // ── Route matching ───────────────────────────────────────────
    if (path === "/textsearch/json" && req.method === "GET") {
      return await handleTextSearch(url);
    }

    if (path === "/details/json" && req.method === "GET") {
      return await handlePlaceDetails(url);
    }

    return corsResponse(
      { error: `Not found: ${req.method} ${path}` },
      404,
    );
  } catch (e) {
    const message = e instanceof Error ? e.message : "Unknown error";
    return corsResponse({ error: message }, 500);
  }
});

// ── Handlers ─────────────────────────────────────────────────────

async function handleTextSearch(url: URL): Promise<Response> {
  if (!GOOGLE_MAPS_API_KEY) {
    return corsResponse({ error: "GOOGLE_MAPS_API_KEY not configured" }, 500);
  }

  // Forward all query parameters + inject the API key
  const googleUrl = new URL(`${GOOGLE_PLACES_BASE}/textsearch/json`);
  copyParams(url, googleUrl);
  googleUrl.searchParams.set("key", GOOGLE_MAPS_API_KEY);

  const resp = await fetch(googleUrl.toString());
  const data = await resp.json();
  // Count the call (a request reached Google regardless of its status).
  incrementUsage("text_search");
  return corsResponse(data, resp.status);
}

async function handlePlaceDetails(url: URL): Promise<Response> {
  if (!GOOGLE_MAPS_API_KEY) {
    return corsResponse({ error: "GOOGLE_MAPS_API_KEY not configured" }, 500);
  }

  const googleUrl = new URL(`${GOOGLE_PLACES_BASE}/details/json`);
  copyParams(url, googleUrl);
  googleUrl.searchParams.set("key", GOOGLE_MAPS_API_KEY);

  const resp = await fetch(googleUrl.toString());
  const data = await resp.json();
  // Count the call (a request reached Google regardless of its status).
  incrementUsage("place_details");
  return corsResponse(data, resp.status);
}

// ── Usage tracking ───────────────────────────────────────────────

/**
 * Records one Google Places API call against [endpoint] in the
 * `api_usage_count` table via the increment_api_usage RPC.
 *
 * Fire-and-forget: the result is intentionally not awaited so a slow or
 * failing counter never delays the search response. Deno keeps the event
 * loop alive until the pending fetch settles, so the increment still
 * lands after the reply goes out.
 */
function incrementUsage(endpoint: string): void {
  if (!SUPABASE_URL || !SUPABASE_ANON_KEY) return;
  fetch(`${SUPABASE_URL}/rest/v1/rpc/increment_api_usage`, {
    method: "POST",
    headers: {
      "apikey": SUPABASE_ANON_KEY,
      "Authorization": `Bearer ${SUPABASE_ANON_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ p_endpoint: endpoint }),
  }).catch(() => {
    // Usage tracking must never fail the search request itself.
  });
}

// ── Helpers ──────────────────────────────────────────────────────

/** Copy all query parameters from [src] to [dst]. */
function copyParams(src: URL, dst: URL): void {
  src.searchParams.forEach((value, key) => {
    if (key !== "key") dst.searchParams.set(key, value);
  });
}

/** Wrap a JSON body (or null) in a CORS-friendly Response. */
function corsResponse(
  body: unknown,
  status: number,
): Response {
  const init: ResponseInit = {
    status,
    headers: {
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
      "Access-Control-Allow-Headers": "Content-Type, Authorization",
      "Content-Type": "application/json",
    },
  };
  return new Response(body != null ? JSON.stringify(body) : null, init);
}
