// ═══════════════════════════════════════════════════════════════════
// DrsListing — Push Notifications (Supabase Edge Function)
//
// Sends Firebase Cloud Messaging (FCM) notifications for appointment
// events:
//
//   POST /functions/v1/notifications
//   headers { 'x-notify-token': <NOTIFY_SHARED_SECRET> }
//   body    {
//             event:          'appointment_booked' | 'appointment_status_changed',
//             appointment_id: 'APT…',
//             status?:        'Confirmed' | 'Cancelled' | …  (status_changed only),
//             sender_mobile?: the caller's mobile (also accepted via the
//                             x-user-mobile header) — used to verify the
//                             caller is part of this appointment.
//           }
//
//   appointment_booked        → notifies the DOCTOR (all the doctor user's
//                               registered devices) that a patient booked.
//   appointment_cancelled     → notifies the DOCTOR that the PATIENT
//                               cancelled their appointment.
//   appointment_rescheduled   → notifies the DOCTOR that the PATIENT moved
//                               their appointment to a different slot.
//   appointment_rescheduled_by_doctor → notifies the PATIENT that the
//                               DOCTOR moved their appointment to a
//                               different slot (doctor-initiated reschedule).
//   appointment_status_changed → notifies the PATIENT (all the patient's
//                               registered devices) that their appointment
//                               status changed (e.g. Confirmed/Cancelled).
//
// Environment variables:
//   NOTIFY_SHARED_SECRET     — shared token the Flutter app + the
//                              booking-page function replay as the
//                              `x-notify-token` header. Set via:
//                                supabase secrets set NOTIFY_SHARED_SECRET=<value>
//   FIREBASE_SERVICE_ACCOUNT — the Firebase service-account JSON (as-is,
//                              or base64-encoded) used to mint OAuth2
//                              access tokens for the FCM HTTP v1 API.
//                              Download it from Firebase Console →
//                              Project settings → Service accounts →
//                              "Generate new private key". Set via:
//                                supabase secrets set FIREBASE_SERVICE_ACCOUNT="$(cat firebase-adminsdk.json)"
//
// Sending is done through the modern FCM HTTP v1 API (the legacy server
// key API was shut down in June 2024). The function mints a short-lived
// Google OAuth2 access token from the service account using a self-signed
// RS256 JWT — no external SDK needed, pure Web Crypto (Deno native).
// ═══════════════════════════════════════════════════════════════════

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_ROLE_KEY =
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const NOTIFY_SECRET = Deno.env.get("NOTIFY_SHARED_SECRET") ?? "";
const FIREBASE_SA = Deno.env.get("FIREBASE_SERVICE_ACCOUNT") ?? "";

/// Cached OAuth2 access token (valid ~1h, refreshed when nearly expired).
let cachedAccessToken = "";
let cachedAccessTokenExpiry = 0;

serve(async (req) => {
  // ── CORS preflight ─────────────────────────────────────────────
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders() });
  }

  try {
    if (!NOTIFY_SECRET) {
      return jsonResponse(
        { ok: false, error: "Notifications are not configured yet." },
        503,
      );
    }

    // ── Shared-secret gate (same pattern as the booking-page function) ──
    const token = req.headers.get("x-notify-token") ?? "";
    if (!secureEqual(token, NOTIFY_SECRET)) {
      return jsonResponse({ ok: false, error: "Invalid token." }, 401);
    }

    if (req.method !== "POST") {
      return jsonResponse({ ok: false, error: "Method not allowed" }, 405);
    }

    const body = await req.json().catch(() => null);
    const event = body?.event ?? "";
    const appointmentId = (body?.appointment_id ?? "").trim();
    const status = (body?.status ?? "").trim();
    const paymentStatus = (body?.payment_status ?? "").trim();

    if (
      ![
        "appointment_booked",
        "appointment_cancelled",
        "appointment_rescheduled",
        "appointment_rescheduled_by_doctor",
        "appointment_status_changed",
        "payment_status_changed",
      ].includes(event)
    ) {
      return jsonResponse(
        { ok: false, error: "Unknown event." },
        400,
      );
    }
    if (!appointmentId) {
      return jsonResponse(
        { ok: false, error: "Missing appointment_id." },
        400,
      );
    }

    // Sender mobile — from the body or the header (the Flutter app sends
    // x-user-mobile; the booking-page function sends sender_mobile).
    const senderMobile = normalizeMobile(
      body?.sender_mobile ?? req.headers.get("x-user-mobile") ?? "",
    );

    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
      auth: { persistSession: false },
    });

    // Opportunistic retention: keeps the in-app history bounded on top of
    // the nightly pg_cron job (migration 20260806000006). Non-fatal.
    await pruneHistory(supabase);

    // ── Load the appointment ──────────────────────────────────────
    const { data: apt, error: aptError } = await supabase
      .from("appointments")
      .select(
        "appointment_id, user_id, patient_name, patient_phone, " +
          "doctor_name, doctor_place_id, appointment_date, " +
          "appointment_time, status, doctor_details->place_id",
      )
      .eq("appointment_id", appointmentId)
      .maybeSingle();
    if (aptError) return jsonResponse({ ok: false, error: aptError.message }, 500);
    if (!apt) {
      return jsonResponse(
        { ok: false, error: "Appointment not found." },
        404,
      );
    }

    // Prefer the indexed column; legacy rows only carry the place id inside
    // the doctor_details JSONB snapshot (PostgREST flattens ->place_id to
    // the top-level `place_id` key here).
    const doctorPlaceId = apt.doctor_place_id ?? apt.place_id ?? "";

    // ── Caller verification (MANDATORY — fail closed) ─────────────
    // The caller must be part of this appointment: the patient who booked
    // it, or the doctor it belongs to. The shared secret is embedded in the
    // app (extractable), so this check is the real security boundary — a
    // caller without a matching mobile is rejected outright. Both legit
    // callers (the Flutter app and the booking-page function) always send
    // the mobile, so no real flow breaks.
    if (!senderMobile) {
      return jsonResponse(
        { ok: false, error: "Missing sender mobile." },
        403,
      );
    }
    const isPatient = senderMobile === normalizeMobile(apt.patient_phone ?? "");
    const isDoctor = await isDoctorFor(
      supabase,
      senderMobile,
      doctorPlaceId,
    );
    // Role-per-event: the PATIENT books/cancels/reschedules; only the
    // DOCTOR changes a status or moves the appointment to a new slot
    // (appointment_rescheduled_by_doctor). This stops e.g. a patient
    // forging a "rescheduled by clinic" message.
    const patientInitiated = event === "appointment_booked" ||
        event === "appointment_cancelled" ||
        event === "appointment_rescheduled";
    const senderOk = patientInitiated ? isPatient : isDoctor;
    if (!senderOk) {
      return jsonResponse(
        { ok: false, error: "Sender is not authorised for this event." },
        403,
      );
    }

    // ── Route the notification ────────────────────────────────────
    // Patient-initiated events (booked / cancelled / rescheduled) notify
    // the DOCTOR; status changes and payment status changes notify the
    // PATIENT.
    const isDoctorEvent =
      event === "appointment_booked" ||
      event === "appointment_cancelled" ||
      event === "appointment_rescheduled";
    if (isDoctorEvent) {
      // Notify the DOCTOR (all their devices).
      const devices = await filterByPrefs(
        supabase,
        await doctorDevices(supabase, doctorPlaceId),
        event,
      );
      if (devices.length === 0) {
        return jsonResponse(
          { ok: true, delivered: 0, note: "Doctor has no registered devices or has disabled this alert." },
          200,
        );
      }
      const date = formatDisplayDate(apt.appointment_date ?? "");
      const time = apt.appointment_time ?? "";
      const when = [date, time].filter(Boolean).join(" at ");
      const cancelled = event === "appointment_cancelled";
      const rescheduled = event === "appointment_rescheduled";
      const title = cancelled
        ? "Appointment Cancelled"
        : rescheduled
          ? "Appointment Rescheduled"
          : "New Appointment Request";
      const bodyText = cancelled
        ? `${apt.patient_name ?? "A patient"} cancelled${when ? " their " + when + " booking" : " their booking"}.`
        : rescheduled
          ? `${apt.patient_name ?? "A patient"} moved their appointment to ${when || "a new slot"}.`
          : `${apt.patient_name ?? "A patient"} booked${when ? " for " + when : ""}.`;
      const dataType = cancelled
        ? "appointment_cancelled"
        : rescheduled
          ? "appointment_rescheduled"
          : "appointment_booked";
      const delivered = await sendAll(
        supabase,
        devices,
        title,
        bodyText,
        {
          type: dataType,
          appointment_id: apt.appointment_id,
          doctor_place_id: doctorPlaceId,
        },
      );
      // In-app history: one row per RECIPIENT user (not per device) so the
      // doctor's notification center shows this even if FCM delivery failed
      // or the app was closed.
      for (const userId of new Set(
        devices.map((d) => d.userId).filter(Boolean) as string[],
      )) {
        await recordHistory(supabase, userId, event, title, bodyText, {
          type: dataType,
          appointment_id: apt.appointment_id,
          doctor_place_id: doctorPlaceId,
          // Rendered on the notification-center card so the doctor knows
          // which patient/clinic this alert is about at a glance.
          doctor_name: apt.doctor_name ?? "",
          patient_name: apt.patient_name ?? "",
          appointment_date: apt.appointment_date ?? "",
          appointment_time: apt.appointment_time ?? "",
        });
      }
      return jsonResponse({ ok: true, delivered }, 200);
    }

    // event is patient-directed: "appointment_status_changed" (doctor
    // changed the status), "appointment_rescheduled_by_doctor" (doctor
    // moved the appointment to a new slot), or "payment_status_changed"
    // (doctor marked payment as Paid or Refunded). All notify the PATIENT
    // (all their devices), with the recipient's notification_prefs checked
    // under the event's own key.
const isPaymentEvent = event === "payment_status_changed";
    const movedByClinic = event === "appointment_rescheduled_by_doctor";
    const date = formatDisplayDate(apt.appointment_date ?? "");
    const time = apt.appointment_time ?? "";
    const when = [date, time].filter(Boolean).join(" at ");

    let title = "";
    let bodyText = "";
    const payload: Record<string, string> = {
      type: event,
      appointment_id: apt.appointment_id,
      doctor_place_id: doctorPlaceId,
    };

    if (isPaymentEvent) {
      const pStatus = paymentStatus || "";
      const pFriendly = pStatus.toLowerCase();
      title = `Payment ${pStatus || "Updated"}`;
      bodyText = pFriendly === "paid"
        ? `${apt.doctor_name ?? "The clinic"} marked your payment of ₹${(apt as any).payment_amount ?? ""} as paid${when ? " for " + when : ""}.`
        : pFriendly === "refunded"
          ? `${apt.doctor_name ?? "The clinic"} has refunded your payment${when ? " for " + when : ""}.`
          : `${apt.doctor_name ?? "The clinic"} updated your payment status to ${pStatus}.`;
      payload.payment_status = pStatus;
    } else if (movedByClinic) {
      title = "Appointment Rescheduled by Clinic";
      bodyText = `${apt.doctor_name ?? "Your doctor"} moved your appointment to ${when || "a new slot"}.`;
    } else {
      const newStatus = status || apt.status || "";
      const friendly = newStatus.toLowerCase();
      title = `Appointment ${newStatus || "Updated"}`;
      bodyText = `${apt.doctor_name ?? "Your doctor"} ${
          friendly === "cancelled"
            ? "cancelled"
            : friendly === "confirmed"
              ? "confirmed"
              : friendly === "completed"
                ? "marked completed"
                : "updated"
        } your appointment${when ? " on " + when : ""}.`;
      payload.status = newStatus;
    }
    const devices = await filterByPrefs(
      supabase,
      await patientDevices(supabase, apt.user_id),
      event,
    );
    if (devices.length === 0) {
      return jsonResponse(
        { ok: true, delivered: 0, note: "Patient has no registered devices or has disabled this alert." },
        200,
      );
    }
    const delivered = await sendAll(
      supabase,
      devices,
      title,
      bodyText,
      payload,
    );
    // In-app history: one row for the patient so their notification center
    // shows this even if FCM delivery failed or the app was closed.
    if (apt.user_id) {
      await recordHistory(supabase, apt.user_id, event, title, bodyText, {
        ...payload,
        // Rendered on the notification-center card so the patient knows
        // which clinic/hospital this alert is about at a glance.
        doctor_name: apt.doctor_name ?? "",
        appointment_date: apt.appointment_date ?? "",
        appointment_time: apt.appointment_time ?? "",
      });
    }
    return jsonResponse({ ok: true, delivered }, 200);
  } catch (e) {
    const message = e instanceof Error ? e.message : "Unknown error";
    return jsonResponse({ ok: false, error: message }, 500);
  }
});

// ── Recipient resolution ──────────────────────────────────────────

type Device = { token: string; userId?: string };

/// Every registered device token belonging to the DOCTOR of an appointment.
/// The doctor is identified two ways (both are set by completeDoctorConnection):
///   * users.doctor_place_id == appointment.doctor_place_id
///   * doctors.user_id (doctors table → the owning user row)
/// Each device remembers its owner so stale (revoked) tokens can be pruned.
async function doctorDevices(
  supabase: any,
  doctorPlaceId: string,
): Promise<Device[]> {
  const byToken = new Map<string, Device>();

  if (doctorPlaceId) {
    // Direct: users whose doctor_place_id matches.
    const { data: users } = await supabase
      .from("users")
      .select("id, device_tokens")
      .eq("doctor_place_id", doctorPlaceId);
    for (const u of users ?? []) collectDevices(byToken, u.id, u.device_tokens);

    // Fallback: the doctors table row's user_id.
    const { data: doc } = await supabase
      .from("doctors")
      .select("user_id")
      .eq("place_id", doctorPlaceId)
      .maybeSingle();
    if (doc?.user_id) {
      const { data: owner } = await supabase
        .from("users")
        .select("id, device_tokens")
        .eq("id", doc.user_id)
        .maybeSingle();
      collectDevices(byToken, owner?.id, owner?.device_tokens);
    }
  }

  return [...byToken.values()];
}

/// Every registered device token belonging to the PATIENT (appointment owner).
async function patientDevices(
  supabase: any,
  userId: string,
): Promise<Device[]> {
  if (!userId) return [];
  const { data: user } = await supabase
    .from("users")
    .select("id, device_tokens")
    .eq("id", userId)
    .maybeSingle();
  const byToken = new Map<string, Device>();
  collectDevices(byToken, user?.id, user?.device_tokens);
  return [...byToken.values()];
}

/// device_tokens is a JSONB array of { token, platform, updated_at } objects.
function collectDevices(
  byToken: Map<string, Device>,
  userId: string | undefined,
  raw: unknown,
): void {
  if (!Array.isArray(raw)) return;
  for (const entry of raw) {
    const t = typeof entry === "object" && entry !== null
      ? (entry as Record<string, unknown>).token
      : entry;
    if (typeof t === "string" && t.trim() && !byToken.has(t.trim())) {
      byToken.set(t.trim(), { token: t.trim(), userId: userId || undefined });
    }
  }
}

/// True when [mobile] belongs to a user whose doctor_place_id is [doctorPlaceId].
async function isDoctorFor(
  supabase: any,
  mobile: string,
  doctorPlaceId: string,
): Promise<boolean> {
  if (!doctorPlaceId) return false;
  const { data } = await supabase
    .from("users")
    .select("id")
    .eq("doctor_place_id", doctorPlaceId)
    .eq("mobile", mobile)
    .maybeSingle();
  return !!data;
}

// ── FCM sending (HTTP v1) ─────────────────────────────────────────

async function sendAll(
  supabase: any,
  devices: Device[],
  title: string,
  body: string,
  data: Record<string, string>,
): Promise<number> {
  let delivered = 0;
  for (const device of devices) {
    try {
      const outcome = await sendFcm(device.token, title, body, data);
      if (outcome === "sent") {
        delivered++;
      } else if (outcome === "unregistered" && device.userId) {
        // The device is gone (reinstall / app removed) — stop accumulating
        // dead tokens in the user's device_tokens array.
        await pruneToken(supabase, device.userId, device.token).catch(() => {});
      }
    } catch (e) {
      // A single failing device must not abort the rest of the batch.
      console.error("sendFcm failed:", e);
    }
  }
  return delivered;
}

async function sendFcm(
  token: string,
  title: string,
  body: string,
  data: Record<string, string>,
): Promise<"sent" | "unregistered" | "failed"> {
  const accessToken = await firebaseAccessToken();
  const projectId = serviceAccount().project_id;
  const res = await fetch(
    `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        message: {
          token,
          notification: { title, body },
          data,
          android: {
            priority: "high",
            notification: {
              sound: "default",
              // High-importance channel created by the app (MainActivity.kt)
              // so pushes show as heads-up banners with sound. Keep the id
              // in sync with MainActivity's createNotificationChannel().
              channel_id: "drslisting_appointments",
            },
          },
          apns: {
            headers: { "apns-priority": "10" },
            payload: { aps: { sound: "default" } },
          },
        },
      }),
    },
  );

  if (!res.ok) {
    const text = await res.text().catch(() => "");
    if (res.status === 404) {
      // 404 = token is unregistered/revoked — safe to prune.
      console.error(`FCM token unregistered: ${text.slice(0, 300)}`);
      return "unregistered";
    }
    console.error(`FCM send failed (${res.status}): ${text.slice(0, 300)}`);
    return "failed";
  }
  return "sent";
}

/// Drop every device whose owner has disabled [event] in their
/// notification_prefs (users.notification_prefs[event] === false), OR whose
/// master switch is off (notification_prefs.all === false — checked FIRST,
/// so it overrides every per-event key).
/// Fail-open: unknown/missing prefs (column not migrated yet, key absent)
/// still deliver, so nobody silently loses alerts.
async function filterByPrefs(
  supabase: any,
  devices: Device[],
  event: string,
): Promise<Device[]> {
  const ids = [
    ...new Set(devices.map((d) => d.userId).filter(Boolean) as string[]),
  ];
  if (ids.length === 0) return devices;

  const { data: users } = await supabase
    .from("users")
    .select("id, notification_prefs")
    .in("id", ids);
  const prefs = new Map(
    (users ?? []).map((u: any) => [u.id, u.notification_prefs ?? {}]),
  );

  return devices.filter((d) => {
    if (!d.userId) return true; // owner unknown → nothing to check
    const map = prefs.get(d.userId) ?? {};
    // Master switch: `all: false` disables every event at once. Missing key
    // (pre-master-switch accounts) or true → per-event keys decide.
    if (map.all === false) return false;
    return map[event] !== false; // true / missing → send
  });
}

// Retention window for the in-app notification history (days). Must match
// migration 20260806000006 (prune_old_notifications default).
const RETENTION_DAYS = 90;

// Throttle: the opportunistic prune only runs once per hour per instance,
// because the nightly pg_cron job is the primary cleanup. Prevents an
// unnecessary DB round-trip on every push.
let lastPruneMs = 0;
const PRUNE_INTERVAL_MS = 60 * 60 * 1000;

/// Opportunistic retention: delete history rows older than RETENTION_DAYS.
/// Throttled to once per hour (the nightly pg_cron job is primary).
/// Non-fatal — pruning must never break the push flow.
async function pruneHistory(supabase: any): Promise<void> {
  const now = Date.now();
  if (now - lastPruneMs < PRUNE_INTERVAL_MS) return;
  lastPruneMs = now;
  try {
    const cutoff = new Date(
      now - RETENTION_DAYS * 24 * 60 * 60 * 1000,
    ).toISOString();
    await supabase.from("notifications").delete().lt("created_at", cutoff);
  } catch (e) {
    console.error("pruneHistory failed (non-fatal):", e);
  }
}

/// Insert one row into the in-app `notifications` history table (service
/// role — RLS bypassed, the app reads its own rows via the x-user-id header).
/// Non-fatal: history must never break the push flow.
async function recordHistory(
  supabase: any,
  userId: string,
  type: string,
  title: string,
  body: string,
  data: Record<string, string>,
): Promise<void> {
  if (!userId) return;
  try {
    await supabase.from("notifications").insert({
      user_id: userId,
      type,
      title,
      body,
      data,
    });
  } catch (e) {
    console.error("recordHistory failed (non-fatal):", e);
  }
}

/// Remove a stale device token from a user's device_tokens array.
/// With single-token-per-user, this empties the array entirely.
/// (service role — the user-gated RPC is for the app's own writes).
async function pruneToken(
  supabase: any,
  userId: string,
  token: string,
): Promise<void> {
  const { data: user } = await supabase
    .from("users")
    .select("device_tokens")
    .eq("id", userId)
    .maybeSingle();
  if (!user) return;
  const cleaned = (Array.isArray(user.device_tokens)
    ? user.device_tokens
    : []
  ).filter((e: any) => e?.token !== token);
  await supabase
    .from("users")
    .update({ device_tokens: cleaned })
    .eq("id", userId);
}

// ── Google OAuth2 access token (service-account JWT) ──────────────

function serviceAccount(): { client_email: string; project_id: string; private_key: string } {
  const raw = FIREBASE_SA.trim();
  const json = raw.startsWith("{")
    ? raw
    : new TextDecoder().decode(decodeBase64(raw.replace(/\s+/g, "")));
  const parsed = JSON.parse(json);
  return {
    client_email: parsed.client_email ?? "",
    project_id: parsed.project_id ?? "",
    private_key: parsed.private_key ?? "",
  };
}

/// Returns a valid FCM access token, reusing the cached one until it's
/// within 60s of expiry. Mints a self-signed RS256 JWT (Web Crypto — no
/// external SDK) and exchanges it at Google's token endpoint.
async function firebaseAccessToken(): Promise<string> {
  if (
    cachedAccessToken &&
    cachedAccessTokenExpiry > Date.now() + 60_000
  ) {
    return cachedAccessToken;
  }

  const sa = serviceAccount();
  if (!sa.client_email || !sa.private_key || !sa.project_id) {
    throw new Error(
      "FIREBASE_SERVICE_ACCOUNT secret is missing or invalid.",
    );
  }

  const now = Math.floor(Date.now() / 1000);
  const header = { alg: "RS256", typ: "JWT" };
  const claims = {
    iss: sa.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  };

  const enc = new TextEncoder();
  const signingInput =
    base64UrlEncode(enc.encode(JSON.stringify(header))) +
    "." +
    base64UrlEncode(enc.encode(JSON.stringify(claims)));

  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToBinary(sa.private_key),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = new Uint8Array(
    await crypto.subtle.sign(
      "RSASSA-PKCS1-v1_5",
      key,
      enc.encode(signingInput),
    ),
  );

  const jwt = signingInput + "." + base64UrlEncode(signature);
  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body:
      "grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=" +
      encodeURIComponent(jwt),
  });
  if (!res.ok) {
    const text = await res.text().catch(() => "");
    throw new Error(`OAuth2 token exchange failed (${res.status}): ${text.slice(0, 300)}`);
  }
  const data = await res.json();
  if (!data.access_token) throw new Error("OAuth2 response missing access_token.");

  cachedAccessToken = data.access_token;
  cachedAccessTokenExpiry = Date.now() + ((data.expires_in ?? 3600) - 60) * 1000;
  return cachedAccessToken;
}

// ── Helpers ───────────────────────────────────────────────────────

/// "-----BEGIN PRIVATE KEY-----" PEM → PKCS8 DER bytes.
function pemToBinary(pem: string): Uint8Array {
  const base64 = pem
    .replace(/-----BEGIN [A-Z ]+-----/g, "")
    .replace(/-----END [A-Z ]+-----/g, "")
    .replace(/\s+/g, "");
  return decodeBase64(base64);
}

function decodeBase64(b64: string): Uint8Array {
  const bin = atob(b64);
  const bytes = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
  return bytes;
}

function base64UrlEncode(bytes: Uint8Array): string {
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin)
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");
}

/// Converts a stored 'YYYY-MM-DD' appointment date to the app's display
/// format 'DD-MM-YYYY' (e.g. '2026-08-10' → '10-08-2026') so push bodies
/// and in-app notification history match the rest of the app's UI.
/// Returns the raw value unchanged when it isn't a parseable ISO date.
function formatDisplayDate(raw: string): string {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(raw.trim());
  if (!m) return raw;
  return `${m[3]}-${m[2]}-${m[1]}`;
}

/// Strip everything that isn't a digit AND drop a leading Indian country
/// code — "+91 98765 43210" and "9876543210" resolve to the same user
/// (mirrors the booking function, plus the +91 normalisation the sender
/// verification needs: patient_phone is stored as plain 10 digits).
function normalizeMobile(raw: string): string {
  let digits = (raw ?? "").replace(/\D/g, "");
  if (digits.length === 12 && digits.startsWith("91")) {
    digits = digits.slice(2);
  }
  return digits.length >= 7 && digits.length <= 15 ? digits : "";
}

/// Constant-time string comparison (same as the booking function).
function secureEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) {
    diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return diff === 0;
}

function corsHeaders(): Record<string, string> {
  return {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Allow-Headers":
      "Content-Type, Authorization, x-notify-token, x-user-mobile",
  };
}

function jsonResponse(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders(),
      "Content-Type": "application/json",
    },
  });
}
