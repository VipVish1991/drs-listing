// ═══════════════════════════════════════════════════════════════════
// DrsListing — Booking Page (Supabase Edge Function)
//
// Backend for the QR-code booking flow. The static booking page
// (booking.html — the drsListing-web GitHub repo, hosted on GitHub Pages)
// calls this function for everything:
//
//   GET  /booking-page?doctor=<place_id>&token=<secret>&action=slots
//        → { ok, doctor, slots, booked } — the doctor's weekly availability
//          (doctor_slots rows, enabled only) plus the already-booked
//          "date|time" keys (every status except Cancelled) so the web
//          page can disable taken slots exactly like the Flutter booking
//          screen (shared rule: a slot stays booked until Cancelled).
//   GET  /booking-page?doctor=<place_id>&token=<secret>&action=history&mobile=<m>
//        → { ok, user, appointments } — all bookings for that mobile
//          number (empty list when the number was never registered).
//          Each appointment carries `payment` ({ amount, method, status,
//          currency } or null) when a consultation fee was recorded, so
//          the page can show the amount + settlement status.
//   GET  /booking-page?doctor=<place_id>&token=<secret>   (no action)
//        → legacy HTML form (kept for the deploy-time GET verification).
//   POST /booking-page?doctor=<place_id>
//        body { action: 'register', name, mobile }
//        → upserts the patient into `users` (name + mobile) — the "save
//          patient first" step — and returns { ok, userId, name, mobile }.
//   POST /booking-page?doctor=<place_id>
//        body { action: 'book', name, mobile, date, time, description, type }
//        (action defaults to 'book' for backward compatibility)
//        → registers the patient if needed, then creates a 'Pending'
//          appointment for the chosen date + time. `date` is 'YYYY-MM-DD',
//          `time` is 'HH:MM AM/PM', `type` is the schedule type of the
//          chosen slot ('tele' | 'video' | 'clinic'). Omitted date/time →
//          today + 'Flexible' (legacy behaviour). A slot that was just
//          booked by someone else is rejected via a race-condition guard
//          (every status except Cancelled occupies the slot) AND by the
//          DB-level enforce_slot_booking_rule trigger, which is the final
//          authority for every code path.
//        When a concrete slot with a fee is booked, a `payments` row is
//        also recorded — method 'offline' (the web/QR flow is pay-at-clinic;
//        there is no UPI intent on the page), status 'Pending', amount = the
//        slot's fee resolved AUTHORITATIVELY from doctor_slots (never
//        trusted from the client). The clinic marks it Paid/Refunded from
//        the appointments screen, exactly like the app's "Offline Pay"
//        path. Recording the payment is non-fatal — it never fails a
//        booking. The response includes the payment summary when one was
//        recorded.
//   POST /booking-page?doctor=<place_id>&action=prescription&appointment=<id>
//        headers { 'x-booking-token': <secret>, 'Content-Type': image/* }
//        body: raw image bytes (JPEG/PNG) — the doctor app uploads the
//        prescription photo here. The image is decoded, downscaled to at
//        most 2560px on the longest side, re-encoded as a quality-92 JPEG
//        (with a light sharpen so prescription text stays crisp) and only
//        THEN written to the public `prescriptions` storage bucket — so
//        storage never holds multi-megabyte originals. Returns
//        { ok: true, url } with the public URL to store on the appointment.
//
// Environment variables (set in Supabase Dashboard — available
// automatically on Edge Functions):
//   SUPABASE_URL              — project URL
//   SUPABASE_SERVICE_ROLE_KEY — service role key (bypasses RLS)
//   BOOKING_SHARED_SECRET     — shared token embedded in the QR code
//                               URL. GET requests must carry it as the
//                               `token` query param; POST requests as the
//                               `x-booking-token` header. Any request
//                               without a matching token is rejected.
//                               Set via:
//                                 supabase secrets set BOOKING_SHARED_SECRET=<value>
// ═══════════════════════════════════════════════════════════════════

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
// Pure-JS image processing (no native bindings — sharp/libvips do not run
// in the Edge Runtime). Buffers are provided explicitly because the
// runtime has no global Buffer. Bundled server-side by the Supabase CLI
// (`--use-api`) or locally with Docker.
import { Buffer } from "https://esm.sh/buffer@6.0.3";
import Jimp from "https://esm.sh/jimp@0.22.12";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_ROLE_KEY =
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const BOOKING_SECRET = Deno.env.get("BOOKING_SHARED_SECRET") ?? "";
// Same project-level secret the notifications Edge Function uses — lets this
// function fire the doctor push after a web/QR booking lands.
const NOTIFY_SECRET = Deno.env.get("NOTIFY_SHARED_SECRET") ?? "";

// The single static Google Meet room used by every consultation in the
// app. New appointments are created with it pre-filled in meet_link so
// both the patient and the clinic always join the SAME meeting.
const STATIC_MEET_LINK = "https://meet.google.com/rnz-wivx-yze";

// "One active booking per doctor" gate: a patient may hold at most one
// active (Pending/Upcoming) booking with a GIVEN doctor at a time. Other
// doctors are never affected — the patient can book a different doctor
// while an appointment with doctor A is still active, and can re-book
// doctor A immediately once that booking is Completed or Cancelled (no
// cooldown). Mirrors AppointmentController.bookingBlockMessage in the app.

// Shared gate message — the SAME wording the Flutter app shows. Used both
// by the pre-insert bookingGateError() check and when the DB-level
// enforce_one_active_booking_rule trigger catches a race after it.
const GATE_ACTIVE_MSG =
  "You already have an active appointment with this doctor. Please " +
  "wait for it to be completed or cancelled before booking again.";

serve(async (req) => {
  // ── CORS preflight ─────────────────────────────────────────────
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders() });
  }

  try {
    // ── Shared-secret gate ─────────────────────────────────────────
    // Only scans carrying the token (embedded in the QR URL) may open
    // the booking form or create appointments. Fail closed if the
    // secret hasn't been configured yet.
    if (!BOOKING_SECRET) {
      return jsonResponse(
        {
          ok: false,
          error:
            "Booking is temporarily unavailable. Please try again later.",
        },
        503,
      );
    }

    const url = new URL(req.url);
    const token = req.method === "POST"
      ? req.headers.get("x-booking-token") ?? ""
      : url.searchParams.get("token") ?? "";
    if (!secureEqual(token, BOOKING_SECRET)) {
      if (req.method === "POST") {
        return jsonResponse(
          {
            ok: false,
            error:
              "This booking link is no longer valid. Please rescan the QR code.",
          },
          401,
        );
      }
      return htmlResponse(
        "This booking link is no longer valid. Please rescan the QR code from the doctor profile.",
        false,
      );
    }

    const doctorPlaceId = url.searchParams.get("doctor") ?? "";

    if (!doctorPlaceId) {
      return htmlResponse(
        "Missing doctor parameter. Please rescan the QR code.",
        true,
      );
    }

    // ── GET: JSON data endpoints + legacy HTML form ───────────────
    if (req.method === "GET") {
      const action = url.searchParams.get("action") ?? "";
      if (action === "slots") {
        return jsonResponse(await slotsPayload(doctorPlaceId), 200);
      }
      if (action === "history") {
        return jsonResponse(
          await historyPayload(url.searchParams.get("mobile") ?? ""),
          200,
        );
      }
      // Legacy HTML form — used only by the deploy-time GET verification.
      // The live page is the static booking.html served from the static
      // host (Supabase's shared domain rewrites text/html to text/plain).
      const doctorName = await lookupDoctorName(doctorPlaceId);
      return htmlResponse(null, false, doctorName);
    }

    // ── POST: prescription upload, register patient, or book ───────
    if (req.method === "POST") {
      const contentType = req.headers.get("content-type") ?? "";
      // Raw-image prescription upload (the doctor app sends the photo
      // bytes with an image/* content type). Distinguished from the JSON
      // booking/register calls by the content type + action param.
      if (
        contentType.startsWith("image/") &&
        url.searchParams.get("action") === "prescription"
      ) {
        const result = await uploadPrescription(doctorPlaceId, url, req);
        return jsonResponse(result, result.ok ? 200 : 400);
      }
      const body = await req.json().catch(() => null);
      const action = body?.action ?? "book";
      const result = action === "register"
        ? await registerUser(body)
        : await createBooking(doctorPlaceId, body);
      if (!result.ok) {
        return jsonResponse(result, 400);
      }
      return jsonResponse(result, 200);
    }

    return jsonResponse({ ok: false, error: "Method not allowed" }, 405);
  } catch (e) {
    const message = e instanceof Error ? e.message : "Unknown error";
    return jsonResponse({ ok: false, error: message }, 500);
  }
});

// ── Availability + history payloads ────────────────────────────────

/// Weekly availability for a doctor: enabled doctor_slots rows + the
/// already-booked "date|time" keys so the web page can disable taken
/// slots exactly like the Flutter booking screen. Shared rule: a slot is
/// occupied by EVERY appointment status except Cancelled.
async function slotsPayload(doctorPlaceId: string) {
  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: { persistSession: false },
  });

  // Only the doctor fields the web page actually renders are selected:
  // name/specialization for the title + subtitle, and the phone/address/
  // coords the header card's Call + Get Directions links need. Everything
  // else (rating, components, etc.) stays out of the payload.
  const doctor = await supabase
    .from("doctors")
    .select(
      "name, specialization, hospital_name, address, vicinity, " +
        "phone_number, international_phone_number, place_id, " +
        "latitude, longitude, unavailable_ranges",
    )
    .eq("place_id", doctorPlaceId)
    .maybeSingle();

  const slots = await supabase
    .from("doctor_slots")
    .select()
    .eq("doctor_place_id", doctorPlaceId)
    .eq("is_enabled", true)
    .order("day_of_week")
    .order("schedule_type");

  const booked = await supabase
    .from("appointments")
    .select("appointment_date, appointment_time")
    .or(
      `doctor_place_id.eq.${doctorPlaceId},` +
        `doctor_details->>place_id.eq.${doctorPlaceId}`,
    )
    .neq("status", "Cancelled");

  const bookedKeys = [
    ...new Set(
      (booked.data ?? [])
        .map((a) =>
          `${a.appointment_date ?? ""}|${a.appointment_time ?? ""}`
        )
        .filter((k) => !k.startsWith("|") && !k.endsWith("|")),
    ),
  ];

  return {
    ok: true,
    doctor: doctor.data ?? null,
    slots: slots.data ?? [],
    booked: bookedKeys,
  };
}

/// All bookings for a mobile number (the patient's booking history shown
/// at the bottom of the web page when they rescan the QR code).
async function historyPayload(mobileRaw: string) {
  const mobile = normalizeMobile(mobileRaw);
  if (!mobile) {
    return { ok: false, error: "Missing or invalid mobile number." };
  }

  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: { persistSession: false },
  });

  const user = await supabase
    .from("users")
    .select("id, name, mobile")
    .eq("mobile", mobile)
    .maybeSingle();
  if (user.error) return { ok: false, error: user.error.message };
  if (!user.data) {
    return { ok: true, user: null, appointments: [] };
  }

  // Only the doctor_details JSONB sub-keys the web page renders are
  // projected (name, hospital_name, address, vicinity, phone, coords) so
  // the history payload stays slim — the doctor snapshot can carry a lot
  // of extra fields (rating, components, etc.) nobody needs here.
  const apts = await supabase
    .from("appointments")
    .select(
      "appointment_id, doctor_name, doctor_place_id, appointment_date, " +
        "appointment_time, status, symptoms, created_at, " +
        "patient_name, patient_phone, consultation_type, " +
        "doctor_details->name, doctor_details->hospital_name, " +
        "doctor_details->address, doctor_details->vicinity, " +
        "doctor_details->phone_number, " +
        "doctor_details->international_phone_number, " +
        "doctor_details->place_id, " +
        "doctor_details->latitude, doctor_details->longitude, " +
        "upload_prescription, " +
        "payments(amount, payment_method, payment_status, currency)",
    )
    .eq("user_id", user.data.id)
    .order("appointment_date", { ascending: false })
    .order("created_at", { ascending: false });
  if (apts.error) return { ok: false, error: apts.error.message };

  // PostgREST flattens JSONB sub-key projections into top-level fields
  // (doctor_details->name comes back as `name`). Rebuild the nested
  // doctor_details object the page reads (a.doctor_details.hospital_name
  // etc.), dropping nulls so missing keys stay absent instead of null.
  const SLIM_DD_KEYS = [
    "name",
    "hospital_name",
    "address",
    "vicinity",
    "phone_number",
    "international_phone_number",
    "place_id",
    "latitude",
    "longitude",
  ];
  const appointments = (apts.data ?? []).map((a) => {
    const dd: Record<string, string> = {};
    for (const key of SLIM_DD_KEYS) {
      const v = (a as Record<string, unknown>)[key];
      if (v != null) dd[key] = String(v);
    }
    const { name, hospital_name, address, vicinity, payments, ...rest } = a;
    // Attach the payment summary (at most one payments row per
    // appointment; fee-less legacy bookings have none) so the page can
    // show the amount and settlement status in the history accordion.
    const pay = Array.isArray(payments) && payments.length
      ? (payments[0] as Record<string, unknown>)
      : null;
    const payment = pay
      ? {
          amount: Number(pay.amount ?? 0),
          method: String(pay.payment_method ?? "offline"),
          status: String(pay.payment_status ?? "Pending"),
          currency: String(pay.currency ?? "INR"),
        }
      : null;
    return { ...rest, doctor_details: dd, payment };
  });

  return {
    ok: true,
    user: user.data,
    appointments,
  };
}

// ── One-active-booking-per-doctor gate ─────────────────────────────

/// The "one active booking per doctor" rule: returns an error message
/// when the patient already holds an active (Pending/Upcoming) booking
/// with [doctorPlaceId] — other doctors stay bookable, and the same
/// doctor can be re-booked immediately once the active booking is
/// Completed or Cancelled — or null when booking is allowed. Query
/// failures FAIL OPEN (a gate glitch must never block a legitimate
/// booking; the slot-occupancy trigger still guards slots). Mirrors
/// AppointmentController.bookingBlockMessage in the app.
async function bookingGateError(
  supabase: ReturnType<typeof createClient>,
  userId: string,
  doctorPlaceId: string,
): Promise<string | null> {
  const active = await supabase
    .from("appointments")
    .select("appointment_id")
    .eq("user_id", userId)
    .eq("doctor_place_id", doctorPlaceId)
    .in("status", ["Pending", "Upcoming"])
    .limit(1);
  if (active.error) {
    console.error("bookingGateError: active check failed:", active.error.message);
    return null;
  }
  if (active.data && active.data.length > 0) {
    return GATE_ACTIVE_MSG;
  }
  return null;
}

// ── Register patient (step 1 of the web flow) ──────────────────────

/// Upsert a patient into `users` by mobile — the "save name and mobile
/// number in the user table first" step the web page runs before showing
/// the date/time picker.
async function registerUser(body: {
  name?: string;
  mobile?: string;
} | null) {
  const name = (body?.name ?? "").trim();
  const mobile = normalizeMobile(body?.mobile ?? "");

  if (!name) return { ok: false, error: "Please enter your full name." };
  if (!mobile) {
    return { ok: false, error: "Please enter a valid mobile number." };
  }

  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: { persistSession: false },
  });

  const { data, error } = await supabase
    .from("users")
    .upsert({ name, mobile }, { onConflict: "mobile" })
    .select("id, name, mobile")
    .single();
  if (error) return { ok: false, error: error.message };

  return {
    ok: true,
    userId: data.id,
    name: data.name,
    mobile: data.mobile,
  };
}

// ── Booking logic ─────────────────────────────────────────────────

async function createBooking(
  doctorPlaceId: string,
  body: {
    name?: string;
    mobile?: string;
    description?: string;
    date?: string;
    time?: string;
    type?: string;
  } | null,
) {
  const name = (body?.name ?? "").trim();
  const description = (body?.description ?? "").trim();
  const mobile = normalizeMobile(body?.mobile ?? "");

  if (!name) return { ok: false, error: "Please enter your full name." };
  if (!mobile) {
    return { ok: false, error: "Please enter a valid mobile number." };
  }

  // Chosen date + time (new slot-based flow). Falls back to today +
  // 'Flexible' when omitted — legacy behaviour kept so the deploy-time
  // POST verification keeps working unchanged.
  const rawDate = (body?.date ?? "").trim();
  const rawTime = (body?.time ?? "").trim();
  const dateKey = rawDate ? normalizeDate(rawDate) : todayInKolkata();
  if (rawDate && !dateKey) {
    return { ok: false, error: "Please choose a valid appointment date." };
  }
  const timeSlot = rawTime ? normalizeTime(rawTime) : "Flexible";
  if (rawTime && !timeSlot) {
    return { ok: false, error: "Please choose a valid time slot." };
  }

  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: { persistSession: false },
  });

  // 1. Look up the patient by mobile; register if they don't exist.
  const existing = await supabase
    .from("users")
    .select("id")
    .eq("mobile", mobile)
    .maybeSingle();

  if (existing.error) return { ok: false, error: existing.error.message };

  let userId: string;
  if (existing.data) {
    userId = existing.data.id;
  } else {
    const created = await supabase
      .from("users")
      .insert({ name, mobile })
      .select("id")
      .single();
    if (created.error) return { ok: false, error: created.error.message };
    userId = created.data.id;
  }

  // 1b. One active booking per doctor: an active (Pending/Upcoming)
  //     booking with THIS doctor blocks a second one — other doctors stay
  //     bookable — with the same message the app shows.
  const gateError = await bookingGateError(supabase, userId, doctorPlaceId);
  if (gateError) return { ok: false, error: gateError };

  // 2. Pull the doctor snapshot (for doctor_name + doctor_details).
  const doctor = await supabase
    .from("doctors")
    .select()
    .eq("place_id", doctorPlaceId)
    .maybeSingle();

  if (doctor.error) return { ok: false, error: doctor.error.message };

  const doctorData = doctor.data ?? { place_id: doctorPlaceId };
  const doctorName = doctorData?.name?.toString() || "Doctor";

  // 2b. The doctor may have marked date ranges unavailable (leave,
  //     holiday, travel) — block the booking on those dates. Ranges are
  //     inclusive YYYY-MM-DD strings (lexicographic == chronological).
  //     The DB trigger enforce_unavailability_rule is the final authority.
  const ranges: { start?: string; end?: string }[] = Array.isArray(
    (doctorData as Record<string, unknown>)?.unavailable_ranges,
  )
    ? ((doctorData as Record<string, unknown>)
        .unavailable_ranges as { start?: string; end?: string }[])
    : [];
  const unavailableOnDate = ranges.some(
    (r) =>
      r &&
      typeof r.start === "string" &&
      typeof r.end === "string" &&
      r.start &&
      r.end &&
      dateKey >= r.start &&
      dateKey <= r.end,
  );
  if (unavailableOnDate) {
    return {
      ok: false,
      error:
        "The doctor is unavailable on this date. Please pick another day.",
    };
  }

  // 3. Race-condition guard: with a concrete slot, refuse to double-book
  //    a slot another patient just took. Shared rule: a slot is occupied
  //    by EVERY appointment status except Cancelled (the DB trigger
  //    enforce_slot_booking_rule is the final authority on this).
  if (timeSlot !== "Flexible") {
    const taken = await supabase
      .from("appointments")
      .select("appointment_id")
      .or(
        `doctor_place_id.eq.${doctorPlaceId},` +
          `doctor_details->>place_id.eq.${doctorPlaceId}`,
      )
      .eq("appointment_date", dateKey)
      .eq("appointment_time", timeSlot)
      .neq("status", "Cancelled")
      .maybeSingle();
    if (taken.error) return { ok: false, error: taken.error.message };
    if (taken.data) {
      return {
        ok: false,
        error: "This slot was just booked. Please pick another time.",
      };
    }
  }

  // 4. Create the appointment with the chosen date + time. The schedule
  //    type of the chosen slot is stored too (tele/video/clinic) so the
  //    doctor side can offer the prescription upload for Tele/Video
  //    consultations.
  const appointmentId = `APT${Date.now()}`;
  const rawType = (body?.type ?? "").trim().toLowerCase();
  const consultationType = ["tele", "video", "clinic"].includes(rawType)
    ? rawType
    : undefined;

  const { error: insertError } = await supabase.from("appointments").insert({
    appointment_id: appointmentId,
    user_id: userId,
    patient_name: name,
    patient_phone: mobile, // the patient's own number — shown with tap-to-call on the doctor side
    doctor_name: doctorName,
    doctor_place_id: doctorPlaceId,
    doctor_details: doctorData,
    symptoms: description || null,
    appointment_date: dateKey,
    appointment_time: timeSlot,
    consultation_type: consultationType,
    // Every new appointment carries the same static Google Meet room —
    // both sides always join the SAME meeting.
    meet_link: STATIC_MEET_LINK,
    status: "Pending",
  });

  if (insertError) {
    // The DB trigger enforce_slot_booking_rule rejected the insert because
    // another non-Cancelled appointment took the slot in the microseconds
    // since the race-condition guard above ran — surface the same friendly
    // message the guard uses instead of a raw database error.
    const message = insertError.message ?? "";
    if (message.includes("appointments_slot_occupied")) {
      return {
        ok: false,
        error: "This slot was just booked. Please pick another time.",
      };
    }
    // The DB-level gate (enforce_one_active_booking_rule) caught a race:
    // the patient booked on another device (or their earlier booking
    // landed) in the microseconds since bookingGateError() ran — surface
    // the same friendly message instead of a raw database error.
    if (message.includes("appointments_one_active_booking")) {
      return { ok: false, error: GATE_ACTIVE_MSG };
    }
    return { ok: false, error: insertError.message };
  }

  // 5. Record the consultation fee (pay-at-clinic) when the chosen slot
  //    has one. Non-fatal — a payment record must never fail a booking.
  let payment: { amount: number; method: string; status: string } | null =
    null;
  try {
    payment = await recordBookingPayment({
      supabase,
      doctorPlaceId,
      doctorName,
      appointmentId,
      userId,
      consultationType,
      dateKey,
      timeSlot,
    });
  } catch (e) {
    console.error("recordBookingPayment failed (non-fatal):", e);
  }

  // Fire-and-forget push to the doctor — never blocks or fails the booking.
  // If NOTIFY_SHARED_SECRET isn't set yet, this simply no-ops.
  notifyDoctorPush(appointmentId, mobile).catch((e) => {
    console.error("notifyDoctorPush failed (non-fatal):", e);
  });

  return {
    ok: true,
    appointmentId,
    doctorName,
    patientName: name,
    date: dateKey,
    time: timeSlot,
    payment,
  };
}

/// Record the consultation fee for a web/QR booking as an OFFLINE Pending
/// payment — the web flow is pay-at-clinic (no UPI intent on the page), so
/// the row is created exactly like the app's "Offline Pay" path, and the
/// clinic marks it Paid/Refunded from the appointments screen.
///
/// The fee is resolved AUTHORITATIVELY from the doctor's slot row for the
/// chosen calendar day + schedule type (doctor_slots.day_of_week /
/// schedule_type / fee) — never trusted from the client. Returns the
/// payment summary, or null when no fee applies (legacy Flexible booking,
/// unknown/omitted consultation type, disabled slot, zero fee). Throws only
/// when the insert itself fails, which the caller treats as non-fatal.
async function recordBookingPayment(opts: {
  supabase: ReturnType<typeof createClient>;
  doctorPlaceId: string;
  doctorName: string;
  appointmentId: string;
  userId: string;
  consultationType: string | undefined;
  dateKey: string;
  timeSlot: string;
}): Promise<{ amount: number; method: string; status: string } | null> {
  const {
    supabase,
    doctorPlaceId,
    doctorName,
    appointmentId,
    userId,
    consultationType,
    dateKey,
    timeSlot,
  } = opts;

  // Only concrete slot bookings with a known consultation type carry a fee.
  if (!consultationType || timeSlot === "Flexible") return null;

  // Calendar-weekday name of the booking date ('Monday' …) — matches
  // doctor_slots.day_of_week. Parsed as UTC so the calendar date maps
  // deterministically regardless of the runtime's timezone.
  const weekday = new Date(`${dateKey}T00:00:00Z`)
    .toLocaleDateString("en-US", { weekday: "long", timeZone: "UTC" });

  const slot = await supabase
    .from("doctor_slots")
    .select("fee")
    .eq("doctor_place_id", doctorPlaceId)
    .eq("day_of_week", weekday)
    .eq("schedule_type", consultationType)
    .eq("is_enabled", true)
    .maybeSingle();
  if (slot.error) {
    // Diagnosable, never fatal: a lookup failure must not drop the fee
    // silently — the booking itself already succeeded.
    console.error("recordBookingPayment: slot lookup failed:", slot.error.message);
    return null;
  }

  const fee = Number(slot.data?.fee ?? 0);
  if (!fee || fee <= 0) return null;

  // The clinic's own UPI VPA (set in the doctor profile) so web payment
  // rows carry the same receiver as the app's "Offline Pay" rows; null
  // when unset. Diagnosable, never fatal — a lookup failure must not drop
  // the fee silently.
  let doctorUpiId: string | null = null;
  const doctorRow = await supabase
    .from("doctors")
    .select("upi_id")
    .eq("place_id", doctorPlaceId)
    .maybeSingle();
  if (doctorRow.error) {
    console.error(
      "recordBookingPayment: doctor upi_id lookup failed:",
      doctorRow.error.message,
    );
  } else {
    const vpa = (doctorRow.data?.upi_id as string | null)?.trim();
    doctorUpiId = vpa ? vpa : null;
  }

  const { error } = await supabase.from("payments").insert({
    appointment_id: appointmentId,
    patient_id: userId,
    doctor_place_id: doctorPlaceId,
    doctor_name: doctorName,
    consultation_type: consultationType,
    payment_type: "consultation",
    payment_status: "Pending",
    payment_method: "offline",
    amount: fee,
    currency: "INR",
    upi_id: doctorUpiId,
  });
  if (error) throw new Error(`recordBookingPayment: ${error.message}`);

  return { amount: fee, method: "offline", status: "Pending" };
}

// ── Doctor push notification (web/QR bookings) ─────────────────────

/// Fires the notifications Edge Function so the doctor receives an FCM push
/// for a web/QR booking. Mirrors exactly what the Flutter app does after an
/// in-app booking — one code path for "appointment booked → notify doctor".
async function notifyDoctorPush(
  appointmentId: string,
  senderMobile: string,
): Promise<void> {
  if (!NOTIFY_SECRET) return; // not configured → skip silently

  const res = await fetch(
    `${SUPABASE_URL}/functions/v1/notifications`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-notify-token": NOTIFY_SECRET,
        "x-user-mobile": senderMobile,
      },
      body: JSON.stringify({
        event: "appointment_booked",
        appointment_id: appointmentId,
        sender_mobile: senderMobile,
      }),
    },
  );
  if (!res.ok) {
    const text = await res.text().catch(() => "");
    throw new Error(`notify (${res.status}): ${text.slice(0, 200)}`);
  }
}

// ── Prescription photo upload ──────────────────────────────────────

/// Downscales + compresses a prescription photo server-side, uploads it
/// to the public `prescriptions` bucket, and returns its public URL.
///
/// The doctor app POSTs the raw camera bytes (JPEG/PNG — image_picker
/// re-encodes to JPEG, so EXIF orientation is already baked into the
/// pixels client-side). This function decodes, downscales to at most
/// [MAX_DIM] px on the longest side (never upscales), sharpens lightly
/// (keeps prescription text edges crisp after the resize), re-encodes as
/// a quality-92 JPEG, and only then writes it to storage — so the bucket
/// never holds the multi-megabyte original.
async function uploadPrescription(
  _doctorPlaceId: string,
  url: URL,
  req: Request,
): Promise<{ ok: boolean; url?: string; error?: string }> {
  const appointmentId = (url.searchParams.get("appointment") ?? "").trim();
  if (!appointmentId) {
    return { ok: false, error: "Missing appointment parameter." };
  }

  const arrayBuffer = await req.arrayBuffer();
  if (arrayBuffer.byteLength === 0) {
    return { ok: false, error: "Empty image payload." };
  }
  // Hard cap so a corrupt or absurd upload can't burn CPU/memory.
  if (arrayBuffer.byteLength > 10 * 1024 * 1024) {
    return { ok: false, error: "Image is too large (max 10 MB)." };
  }

  let image: Jimp;
  try {
    image = await Jimp.read(Buffer.from(arrayBuffer));
  } catch {
    return { ok: false, error: "Unsupported or corrupted image format." };
  }

  // Downscale only — small images pass through untouched. Sharpen runs
  // ONLY when a resize actually happened: resizing is what softens edges
  // (sharpen counteracts it), and sharpening a pass-through photo would
  // add faint halos to already-crisp text for zero benefit. App uploads
  // are always client-optimized to <= MAX_DIM, so they skip this branch
  // entirely.
  const MAX_DIM = 2560;
  if (image.bitmap.width > MAX_DIM || image.bitmap.height > MAX_DIM) {
    image.scaleToFit(MAX_DIM, MAX_DIM);
    // Light sharpen so downscaled prescription text stays legible. NOTE:
    // jimp@0.22.12 has NO `.sharpen()` method — `convolution` with a
    // standard 3x3 sharpen kernel (sums to 1 → no brightness shift) is
    // used instead. Edge handling is EDGE_EXTEND, alpha is preserved.
    image.convolution([
      [0, -1, 0],
      [-1, 5, -1],
      [0, -1, 0],
    ]);
  }
  image.quality(92);

  let jpeg: Buffer;
  try {
    jpeg = await image.getBufferAsync(Jimp.MIME_JPEG);
  } catch {
    return { ok: false, error: "Failed to compress the image." };
  }

  // Unique path per upload so re-shoots never overwrite each other and
  // the gallery can show every prescription photo.
  const path = `${appointmentId}/${Date.now()}_${randomSuffix()}.jpg`;
  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: { persistSession: false },
  });
  const { error } = await supabase.storage
    .from("prescriptions")
    .upload(path, jpeg, {
      contentType: "image/jpeg",
      cacheControl: "3600",
      upsert: false,
    });
  if (error) return { ok: false, error: error.message };

  const publicUrl = supabase.storage
    .from("prescriptions")
    .getPublicUrl(path)
    .data.publicUrl;
  return { ok: true, url: publicUrl };
}

/// 4-char alphanumeric suffix for upload path uniqueness.
///
/// NOTE: the previous implementation derived indices from
/// `Math.floor(Math.random() * 0xffffffff) >> shift` — values >= 2^31 become
/// NEGATIVE after the signed `>>`, so `chars[-x]` is `undefined` and the
/// filename ended with a garbage `_undefinedundefinedundefinedundefined`
/// suffix ~50% of the time. Fixed to always index within range.
function randomSuffix(): string {
  const chars = "abcdefghijklmnopqrstuvwxyz0123456789";
  let out = "";
  for (let i = 0; i < 4; i++) {
    out += chars[Math.floor(Math.random() * chars.length)];
  }
  return out;
}

// ── Validation helpers ─────────────────────────────────────────────

/// Strip everything that isn't a digit and validate the length. Returns
/// the normalized number or "" when invalid — so "+91 98765 43210" and
/// "9876543210" resolve to the same user.
function normalizeMobile(raw: string): string {
  const digits = raw.replace(/\D/g, "");
  return digits.length >= 7 && digits.length <= 15 ? digits : "";
}

/// Validate + normalize a 'YYYY-MM-DD' date string. Returns the input on
/// success, "" when malformed or not a real calendar date.
function normalizeDate(raw: string): string {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(raw.trim());
  if (!m) return "";
  const year = Number(m[1]);
  const month = Number(m[2]);
  const day = Number(m[3]);
  if (month < 1 || month > 12 || day < 1 || day > 31) return "";
  const d = new Date(year, month - 1, day);
  if (
    d.getFullYear() !== year ||
    d.getMonth() !== month - 1 ||
    d.getDate() !== day
  ) {
    return "";
  }
  return raw.trim();
}

/// Validate + normalize a 'HH:MM AM/PM' time slot to the EXACT format the
/// Flutter app stores in doctor_slots.slots / appointments.appointment_time
/// (time_slot_generator.to12h: unpadded hour, e.g. "9:00 AM"). Padding the
/// hour ("09:00 AM") would break the app's isSlotBooked() booked-key lookup,
/// which compares against the unpadded strings it generated. Returns ""
/// when malformed.
function normalizeTime(raw: string): string {
  const m = /^(\d{1,2}):(\d{2})\s*(AM|PM)$/i.exec(raw.trim());
  if (!m) return "";
  const hour = Number(m[1]);
  const minute = Number(m[2]);
  if (hour < 1 || hour > 12 || minute > 59) return "";
  const h12 = hour % 12 === 0 ? 12 : hour % 12;
  return `${h12}:${m[2]} ${m[3].toUpperCase()}`;
}

/// Constant-time string comparison — avoids leaking the secret via
/// early-exit timing on a common prefix.
function secureEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) {
    diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return diff === 0;
}

async function lookupDoctorName(placeId: string): Promise<string | null> {
  try {
    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
      auth: { persistSession: false },
    });
    const { data } = await supabase
      .from("doctors")
      .select("name")
      .eq("place_id", placeId)
      .maybeSingle();
    return data?.name?.toString() ?? null;
  } catch {
    return null;
  }
}

/// Returns today's date (YYYY-MM-DD) in Asia/Kolkata — the timezone the
/// Flutter app uses for its local date handling.
function todayInKolkata(): string {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: "Asia/Kolkata",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(new Date());
  const get = (type: string) =>
    parts.find((p) => p.type === type)?.value ?? "00";
  return `${get("year")}-${get("month")}-${get("day")}`;
}

// ── Responses ─────────────────────────────────────────────────────

function corsHeaders(): Record<string, string> {
  return {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
    "Access-Control-Allow-Headers":
      "Content-Type, Authorization, x-booking-token",
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

function htmlResponse(
  error: string | null,
  missingDoctor: boolean,
  doctorName: string | null = null,
): Response {
  const page = renderPage(error, missingDoctor, doctorName);
  return new Response(page, {
    status: 200,
    headers: {
      ...corsHeaders(),
      "Content-Type": "text/html; charset=utf-8",
    },
  });
}

function escapeHtml(value: string): string {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}

// ── HTML template (legacy — kept for the deploy-time GET verification) ──

function renderPage(
  error: string | null,
  missingDoctor: boolean,
  doctorName: string | null,
): string {
  const safeDoctorName = doctorName ? escapeHtml(doctorName) : null;
  const title = missingDoctor
    ? "Booking Unavailable"
    : safeDoctorName
      ? `Book with ${safeDoctorName}`
      : "Book an Appointment";

  const intro = missingDoctor
    ? "This booking link is incomplete. Please rescan the QR code from the doctor profile."
    : "Fill in your details below to book an appointment for today. The clinic will confirm your booking shortly.";

  const errorHtml = error ? `<div class="status info">${escapeHtml(error)}</div>` : "";

  const formHtml = missingDoctor
    ? ""
    : `<form id="bookingForm">
      <label for="name">Full Name</label>
      <input type="text" id="name" name="name" placeholder="e.g. Rahul Sharma" autocomplete="name" required>

      <label for="mobile">Mobile Number</label>
      <input type="tel" id="mobile" name="mobile" placeholder="e.g. 9876543210" inputmode="tel" autocomplete="tel" required>

      <label for="description">Describe your problem (optional)</label>
      <textarea id="description" name="description" placeholder="Briefly describe your symptoms or reason for the visit"></textarea>

      <button type="submit" id="submitBtn">Book Appointment</button>
    </form>
    <div id="status" class="status"></div>`;

  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>${title}</title>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
      background: #F7F2E8;
      min-height: 100vh;
      display: flex;
      align-items: center;
      justify-content: center;
      padding: 20px;
    }
    .card {
      background: #FFFFFF;
      border-radius: 24px;
      box-shadow: 0 8px 30px rgba(0,0,0,0.08);
      padding: 32px 24px;
      width: 100%;
      max-width: 420px;
    }
    .logo {
      width: 56px; height: 56px;
      border-radius: 16px;
      background: linear-gradient(135deg, #0E7C66, #12A48B);
      display: flex; align-items: center; justify-content: center;
      font-size: 28px; color: #fff;
      margin-bottom: 16px;
    }
    h1 { font-size: 22px; color: #1F2933; margin-bottom: 6px; }
    .intro { font-size: 14px; color: #6B7280; line-height: 1.5; margin-bottom: 22px; }
    label { font-size: 12.5px; font-weight: 600; color: #374151; display: block; margin: 14px 0 6px; }
    input, textarea {
      width: 100%;
      padding: 12px 14px;
      border: 1.5px solid #E5E7EB;
      border-radius: 12px;
      font-size: 15px;
      font-family: inherit;
      background: #FAFAF9;
      outline: none;
      transition: border-color 0.2s;
    }
    input:focus, textarea:focus { border-color: #0E7C66; background: #fff; }
    textarea { resize: vertical; min-height: 90px; }
    button {
      width: 100%;
      margin-top: 22px;
      padding: 14px;
      background: linear-gradient(135deg, #0E7C66, #12A48B);
      color: #fff;
      border: none;
      border-radius: 14px;
      font-size: 16px;
      font-weight: 700;
      cursor: pointer;
      transition: opacity 0.2s;
    }
    button:hover { opacity: 0.9; }
    button:disabled { opacity: 0.6; cursor: not-allowed; }
    .status {
      margin-top: 16px;
      padding: 12px 14px;
      border-radius: 12px;
      font-size: 13.5px;
      line-height: 1.5;
      display: none;
    }
    .status.ok { display: block; background: #ECFDF5; color: #065F46; }
    .status.err { display: block; background: #FEF2F2; color: #991B1B; }
    .status.info { display: block; background: #FFFBEB; color: #92400E; }
    .foot { margin-top: 18px; font-size: 11.5px; color: #9CA3AF; text-align: center; }
  </style>
</head>
<body>
  <div class="card">
    <div class="logo">🩺</div>
    <h1>${title}</h1>
    <p class="intro">${intro}</p>

    ${formHtml}
    ${errorHtml}

    <div class="foot">DrsListing · Appointment booked for today</div>
  </div>

  <script>
    const form = document.getElementById('bookingForm');
    if (form) {
      // The shared token from the QR URL is replayed on submit so the
      // POST can prove it came from a valid scan.
      const token = new URL(window.location.href).searchParams.get('token') || '';
      form.addEventListener('submit', async (e) => {
        e.preventDefault();
        const status = document.getElementById('status');
        const btn = document.getElementById('submitBtn');
        btn.disabled = true;
        btn.textContent = 'Booking...';

        const body = {
          name: document.getElementById('name').value,
          mobile: document.getElementById('mobile').value,
          description: document.getElementById('description').value,
        };

        try {
          const res = await fetch(window.location.href, {
            method: 'POST',
            headers: {
              'Content-Type': 'application/json',
              'x-booking-token': token,
            },
            body: JSON.stringify(body),
          });
          const data = await res.json();
          if (data.ok) {
            status.className = 'status ok';
            status.innerHTML = '🎉 <b>Appointment booked!</b><br>Reference: <b>' +
              data.appointmentId + '</b><br>Date: <b>' + data.date + '</b> (status: Pending).<br>' +
              'The clinic will confirm shortly.';
            form.reset();
          } else {
            status.className = 'status err';
            status.textContent = '❌ ' + (data.error || 'Something went wrong. Please try again.');
          }
        } catch (err) {
          status.className = 'status err';
          status.textContent = '❌ Network error. Please check your connection and try again.';
        } finally {
          btn.disabled = false;
          btn.textContent = 'Book Appointment';
        }
      });
    }
  </script>
</body>
</html>`;
}
