#!/usr/bin/env python3
"""
DrsListing - End-to-end verification of the IN-APP booking -> doctor
notification chain.

Simulates EXACTLY what the Flutter app does when a patient books an
appointment in-app, then proves the doctor's push history row lands:

  1. Inserts an appointment with the exact payload
     AppointmentController.bookAppointment() sends (APT-prefixed id,
     status 'Upcoming', consultation_type, patient_phone, doctor_details,
     ...). The doctor user carries a registered device token - without one
     the notifications function early-returns and NO history row is
     written (the shared-phone bug fixed in NotificationService).
  2. Calls the live notifications Edge Function exactly like
     NotificationService.notifyAppointmentBooked() does
     (event 'appointment_booked' + x-notify-token + x-user-mobile).
  3. Asserts the doctor's notification row landed in the live
     `notifications` table with the enriched payload (doctor_name,
     patient_name, appointment_date, appointment_time).
  4. All probe rows are deleted afterwards (same safe markers
     cleanup_test_data.py uses).

Usage:
    python supabase/verify_booking_notify.py            # full chain -> clean up
    python supabase/verify_booking_notify.py --keep     # leave probe rows
                                                       # (cleanup_test_data.py
                                                       #  --yes removes them)
    python supabase/verify_booking_notify.py --project-ref <ref>

The SUPABASE_ACCESS_TOKEN is read from .env.deploy (recommended) or the
environment, exactly like verify_fcm_delivery.py.
"""

import json
import os
import re
import sys
import uuid
import urllib.error
import urllib.request

# Default target project. Override with --project-ref <ref>.
PROJECT_REF = "qxukzqdsmlurollltrjp"

DEPLOY_ENV_FILE = ".env.deploy"

# Must match AppConstants.notifySharedSecret in lib/config/constants.dart
# and the NOTIFY_SHARED_SECRET secret set on the deployed function.
NOTIFY_SECRET = "n9Kq4Zx7Vm2Lp8Rt5Ys3Cb6Hf1Wj0AeD"

# Probe markers - deliberately the SAME values cleanup_test_data.py matches,
# so rows left behind (e.g. via --keep) are still caught by that script.
PROBE_NAME = "Test Patient QA"
PROBE_ROLE_DOCTOR = "doctor"
# Symptom marker matched by cleanup_test_data.py (VERIFY_SYMPTOM_MARKERS).
PROBE_SYMPTOMS = "e2e verification - automated in-app booking -> notify check"

# Far-future date/time so the probe booking never collides with a real
# slot or the past-slot guard.
PROBE_DATE = "2099-01-01"
PROBE_TIME = "10:00 AM"
PROBE_CONSULTATION_TYPE = "clinic"


def load_deploy_env() -> None:
    """Load KEY=VALUE pairs from .env.deploy into the environment.

    Same lenient semantics as deploy_notifications.py: existing env vars win,
    quotes stripped, inline comments dropped, and multi-line JSON values are
    concatenated until they parse.
    """
    env_path = os.path.join(
        os.path.dirname(os.path.abspath(__file__)), "..", DEPLOY_ENV_FILE
    )
    try:
        with open(env_path, encoding="utf-8") as f:
            current_key = None
            current_value = None
            for line in f:
                if current_key is not None:
                    current_value += "\n" + line.rstrip("\n")
                    try:
                        json.loads(current_value)
                        os.environ[current_key] = current_value
                        current_key = None
                        current_value = None
                    except json.JSONDecodeError:
                        pass
                    continue
                stripped = line.strip()
                if not stripped or stripped.startswith("#") or "=" not in stripped:
                    continue
                key, _, value = stripped.partition("=")
                key = key.strip()
                if not key or key in os.environ:
                    continue
                value = value.strip()
                if " #" in value:
                    value = value.split(" #", 1)[0].rstrip()
                if (value.startswith('"') and value.endswith('"')) or (
                    value.startswith("'") and value.endswith("'")
                ):
                    value = value[1:-1]
                if value.startswith("{"):
                    current_key = key
                    current_value = value
                    try:
                        json.loads(value)
                        os.environ[key] = value
                        current_key = None
                        current_value = None
                    except json.JSONDecodeError:
                        pass
                else:
                    os.environ[key] = value
    except OSError:
        pass


def api(method: str, path: str, body=None):
    """Call the Supabase Management API and return (status, parsed)."""
    token = os.environ.get("SUPABASE_ACCESS_TOKEN", "").strip()
    if not token:
        sys.exit(
            "ERROR: SUPABASE_ACCESS_TOKEN is not set.\n"
            "Create one at https://supabase.com/dashboard/account/tokens, "
            f"save it in {DEPLOY_ENV_FILE}, or export it and re-run."
        )

    url = f"https://api.supabase.com/v1/projects/{PROJECT_REF}" + path
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(
        url,
        data=data,
        method=method,
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
            "User-Agent": "curl/8.5.0 (DrsListing booking-notify verify)",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=45) as resp:
            raw = resp.read().decode()
            if not raw.strip():
                return resp.status, None
            try:
                return resp.status, json.loads(raw)
            except json.JSONDecodeError:
                return resp.status, raw
    except urllib.error.HTTPError as e:
        raw = e.read().decode()
        try:
            return e.code, json.loads(raw)
        except json.JSONDecodeError:
            return e.code, raw


def main() -> None:
    load_deploy_env()

    global PROJECT_REF
    if "--project-ref" in sys.argv:
        idx = sys.argv.index("--project-ref")
        if idx + 1 >= len(sys.argv):
            sys.exit("ERROR: --project-ref requires a value.")
        PROJECT_REF = sys.argv[idx + 1]
    keep = "--keep" in sys.argv

    print("== DrsListing in-app booking -> doctor notification verification ==")
    print(f"  project ref: {PROJECT_REF}")

    # ── 1. Token gate against the live function ────────────────────
    base = f"https://{PROJECT_REF}.supabase.co/functions/v1/notifications"

    def post(headers, body):
        req = urllib.request.Request(
            base,
            data=json.dumps(body).encode(),
            method="POST",
            headers={**headers, "Content-Type": "application/json",
                     "User-Agent": "curl/8.5.0 (DrsListing booking-notify verify)"},
        )
        try:
            with urllib.request.urlopen(req, timeout=45) as resp:
                return resp.status, resp.read().decode(errors="replace")
        except urllib.error.HTTPError as e:
            return e.code, e.read().decode(errors="replace")

    print("\n[1/4] Token gate...")
    status, _ = post({"x-notify-token": "wrong-secret"},
                     {"event": "appointment_booked", "appointment_id": "APT000"})
    print(f"  -> bad token: HTTP {status} (expected 401)")
    if status != 401:
        sys.exit("  ! Token gate failed - deployed NOTIFY_SHARED_SECRET mismatch. Aborting.")

    # ── 2. Probe data (doctor + patient + appointment) ─────────────
    # Everything from here down is inside try/finally so ANY failure still
    # cleans up the rows created so far.
    doc_id = pat_id = place_id = appointment_id = None
    suffix = uuid.uuid4().hex[:8]
    try:
        print("\n[2/4] Creating isolated probe data...")
        doc_mobile = "9" + str(abs(hash("d" + suffix)) % 9000000000 + 1000000000)
        pat_mobile = "9" + str(abs(hash("p" + suffix)) % 9000000000 + 1000000000)
        place_id = "book-notify-probe-" + suffix
        # Same id shape the app generates (AppointmentController.bookAppointment:
        # 'APT' + DateTime.now().millisecondsSinceEpoch).
        appointment_id = "APT" + str(int(__import__("time").time() * 1000))

        # Doctor user (mobile -> place_id) + a registered device token.
        # The token MUST be present: the notifications function skips the
        # history write entirely when the doctor has no registered devices.
        status, resp = api("POST", "/database/query", {"query": f"""
INSERT INTO public.users (id, mobile, name, role, doctor_place_id, device_tokens, notification_prefs)
VALUES (gen_random_uuid(), '{doc_mobile}', '{PROBE_NAME}', '{PROBE_ROLE_DOCTOR}',
        '{place_id}', '[{{"token": "book-notify-probe-token-{suffix}", "platform": "android"}}]'::jsonb,
        '{{"appointment_booked": true, "appointment_cancelled": true, "appointment_status_changed": true, "all": true}}'::jsonb)
RETURNING id::text
"""})
        if status not in (200, 201) or not resp:
            sys.exit(f"  ! Failed to create probe doctor user: {status} {resp}")
        doc_id = resp[0]["id"]

        status, resp = api("POST", "/database/query", {"query": f"""
INSERT INTO public.users (id, mobile, name, role, device_tokens, notification_prefs)
VALUES (gen_random_uuid(), '{pat_mobile}', '{PROBE_NAME}', 'patient', '[]'::jsonb,
        '{{"appointment_booked": true, "appointment_cancelled": true, "appointment_status_changed": true, "all": true}}'::jsonb)
RETURNING id::text
"""})
        if status not in (200, 201) or not resp:
            sys.exit(f"  ! Failed to create probe patient user: {status} {resp}")
        pat_id = resp[0]["id"]

        # Doctor row (doctors table) so doctorDevices() also resolves via
        # doctors.user_id, mirroring completeDoctorConnection.
        status, resp = api("POST", "/database/query", {"query": f"""
INSERT INTO public.doctors (place_id, user_id, name)
VALUES ('{place_id}', '{doc_id}', '{PROBE_NAME}')
ON CONFLICT (place_id) DO NOTHING
RETURNING place_id
"""})
        print(f"  -> probe doctor + patient + doctor row created (suffix {suffix})")

        # Appointment booked BY the patient FOR the doctor - the exact
        # payload AppointmentController.bookAppointment() inserts in-app.
        status, resp = api("POST", "/database/query", {"query": f"""
INSERT INTO public.appointments (
    appointment_id, user_id, patient_name, patient_phone, doctor_name,
    doctor_place_id, doctor_details, appointment_date, appointment_time,
    symptoms, status, consultation_type
) VALUES (
    '{appointment_id}', '{pat_id}', '{PROBE_NAME}', '{pat_mobile}', '{PROBE_NAME}',
    '{place_id}', '{{"place_id": "{place_id}", "name": "{PROBE_NAME}"}}'::jsonb,
    '{PROBE_DATE}', '{PROBE_TIME}', '{PROBE_SYMPTOMS}', 'Upcoming', '{PROBE_CONSULTATION_TYPE}'
)
RETURNING appointment_id
"""})
        if status not in (200, 201):
            sys.exit(f"  ! Failed to create probe appointment: {status} {resp}")
        print(f"  -> probe appointment {appointment_id} created ('Upcoming', "
              f"{PROBE_DATE} {PROBE_TIME}, {PROBE_CONSULTATION_TYPE})")

        # ── 3. Fire the notifications function exactly as the app does ──
        # NotificationService.notifyAppointmentBooked() -> _sendEvent() posts
        # {event, appointment_id, sender_mobile} with the same headers.
        print("\n[3/4] Firing notifyAppointmentBooked (as the app does)...")
        status, body = post(
            {"x-notify-token": NOTIFY_SECRET, "x-user-mobile": pat_mobile},
            {"event": "appointment_booked", "appointment_id": appointment_id,
             "sender_mobile": pat_mobile},
        )
        print(f"  -> HTTP {status}: {body[:200]}")
        if status != 200:
            sys.exit(f"  ! Unexpected response: HTTP {status} {body[:200]}")
        try:
            parsed = json.loads(body)
        except json.JSONDecodeError:
            sys.exit(f"  ! Non-JSON response: {body[:200]}")
        if parsed.get("ok") is not True:
            sys.exit(f"  ! Function returned ok:false: {body[:200]}")

        # delivered: 0 is EXPECTED (probe token is not a real device - FCM
        # reports it unregistered). The point is the history row: it only
        # lands when the doctor resolved via doctor_place_id AND had a
        # registered device (the shared-phone fix's whole point).
        print("  -> ok:true, delivered:", parsed.get("delivered"),
              "(0 expected - probe token is not a real device)")

        # ── 4. History row landed for the doctor? ──────────────────
        print("\n[4/4] Doctor notification history row check...")
        status, resp = api("POST", "/database/query", {"query": f"""
SELECT type, title, read, data->>'doctor_name' AS doctor_name,
       data->>'patient_name' AS patient_name,
       data->>'appointment_date' AS appointment_date,
       data->>'appointment_time' AS appointment_time,
       data->>'doctor_place_id' AS doctor_place_id,
       data->>'appointment_id' AS appointment_id
FROM public.notifications
WHERE user_id = '{doc_id}' AND data->>'appointment_id' = '{appointment_id}'
ORDER BY created_at DESC LIMIT 1
"""})
        ok_history = (
            status in (200, 201)
            and resp
            and resp[0].get("type") == "appointment_booked"
            and resp[0].get("doctor_name") == PROBE_NAME
            and resp[0].get("patient_name") == PROBE_NAME
            and resp[0].get("appointment_date") == PROBE_DATE
            and resp[0].get("appointment_time") == PROBE_TIME
            and resp[0].get("doctor_place_id") == place_id
        )
        if ok_history:
            print("  -> history row landed with the enriched payload [OK]")
            print("\nSUCCESS: in-app booking -> doctor notification verified end-to-end.")
        else:
            print(f"  ! History row missing or malformed: {status} {resp}")
            sys.exit("PARTIAL: notify ok but the doctor's history row check failed.")

    finally:
        # ── Cleanup (always) ───────────────────────────────────────
        if keep:
            print("\n  --keep set - leaving probe rows for cleanup_test_data.py --yes.")
            return
        print("\n  Cleaning up probe rows...")
        for label, sql in [
            ("appointments", f"DELETE FROM public.appointments WHERE appointment_id = '{appointment_id}'"),
            ("doctors", f"DELETE FROM public.doctors WHERE place_id = '{place_id}'"),
            ("users", f"DELETE FROM public.users WHERE id IN ('{doc_id}', '{pat_id}')"),
        ]:
            s, r = api("POST", "/database/query", {"query": sql})
            print(f"  -> {label}: {s}")
        leftover = 0
        for marker_sql in [
            f"SELECT COUNT(*) AS n FROM public.users WHERE id IN ('{doc_id}', '{pat_id}')",
            f"SELECT COUNT(*) AS n FROM public.appointments WHERE appointment_id = '{appointment_id}'",
            f"SELECT COUNT(*) AS n FROM public.doctors WHERE place_id = '{place_id}'",
        ]:
            s, r = api("POST", "/database/query", {"query": marker_sql})
            try:
                leftover += r[0]["n"] if r else 0
            except (TypeError, IndexError, KeyError):
                pass
        if leftover == 0:
            print("  -> cleanup verified: 0 probe rows remain.")
        else:
            print(f"  !! {leftover} probe row(s) remain - run cleanup_test_data.py --yes.")
        print("  Done.")


if __name__ == "__main__":
    main()
