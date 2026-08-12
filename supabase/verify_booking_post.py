#!/usr/bin/env python3
"""
DrsListing — End-to-end POST verification for the live booking Edge Function.

Simulates exactly what the new static booking page (booking.html from the
drsListing-web GitHub repo, hosted on GitHub Pages) does for the QR-scan flow:

  1. GET  action=slots      → the availability JSON the web page uses to
                              render the 14-day date strip + slot chips.
  2. POST action=register   → saves the patient (name + mobile) into the
                              users table — the "register first" step.
  3. POST action=book       → books a concrete date + time slot (not just
                              today/Flexible) as a 'Pending' appointment,
                              sending the slot's `type` like the web page.
  4. Confirms the row landed in the live `appointments` table with the
     right status + date + time — the end-to-end check the deploy script's
     GET-only verify can't cover — AND that the booking-page function
     recorded the matching `payments` row (Pending / offline / slot fee)
     when the chosen slot carries a fee.
  5. GET  action=history    → confirms the new booking appears in the
     patient's history for that mobile number — and, on the fee path,
     that the history appointment carries the payment summary the web
     page renders (amount / method / status / currency).
  6. Deletes the test appointment + the patient user it created, so the
     live project stays clean (same safe markers cleanup_test_data.py uses).

Usage:
    python supabase/verify_booking_post.py             # full chain → clean up
    python supabase/verify_booking_post.py --keep      # leave the test rows
                                                       # (cleanup_test_data.py
                                                       #  --yes can remove them)
    python supabase/verify_booking_post.py --doctor <placeId>   # custom doctor
    python supabase/verify_booking_post.py --project-ref <ref>
        # verify against a different project (deploy_booking.py passes
        # this automatically when deploying with --fresh --project-ref)

The SUPABASE_ACCESS_TOKEN is read from .env.deploy (recommended) or the
environment, exactly like deploy_booking.py / cleanup_test_data.py.
"""

import json
import os
import sys
import urllib.error
import urllib.request
from datetime import date, datetime, timezone, timedelta
from urllib.parse import quote

# Windows consoles default to cp1252, which cannot encode the ₹ and box-drawing
# characters used below. Force UTF-8 so the script behaves identically on
# every platform (same fix as the deploy_*.py scripts).
for _stream in (sys.stdout, sys.stderr):
    try:
        _stream.reconfigure(encoding="utf-8")
    except (AttributeError, ValueError):
        pass

# Default target project. Override with --project-ref <ref> (deploy_booking.py
# forwards its own --project-ref here when bootstrapping a new environment).
PROJECT_REF = "qxukzqdsmlurollltrjp"

DEPLOY_ENV_FILE = ".env.deploy"

# Must match AppConstants.bookingSharedSecret in lib/config/constants.dart
# and the BOOKING_SHARED_SECRET secret set on the deployed function.
BOOKING_SECRET = "cAZrwHpDFJ4HaSNXowJnmvzi-0YD5rYE"

# A real place used by the deploy script's GET verification.
DEFAULT_DOCTOR_PLACE_ID = "ChIJN1t_tDeuEmsRUsoyG83frY4"

# Test markers — deliberately the SAME values cleanup_test_data.py matches,
# so a row left behind (e.g. via --keep) is still caught by that script.
TEST_NAME = "Test Patient QA"
TEST_MOBILE = "919876500123"
TEST_SYMPTOMS = "e2e verification — automated POST check"

# The slots the test tries. Tomorrow (Asia/Kolkata) — real future
# date/times so the slot-based path is exercised end to end. The race
# guard rejects already-taken slots, so the verifier tries each in turn
# and falls back to the legacy today+Flexible book only if every one is
# genuinely taken (a real patient may own tomorrow's 10:00 AM).
TEST_DATE = (datetime.now(timezone(timedelta(hours=5, minutes=30))) + timedelta(days=1)).strftime("%Y-%m-%d")
TEST_TIMES = ["10:00 AM", "10:30 AM", "11:00 AM"]


def load_deploy_env() -> None:
    """Load KEY=VALUE pairs from .env.deploy into the environment.

    Only sets variables that aren't already present, so an explicit
    SUPABASE_ACCESS_TOKEN exported in the shell always wins.
    """
    env_path = os.path.join(
        os.path.dirname(os.path.abspath(__file__)), "..", DEPLOY_ENV_FILE
    )
    try:
        with open(env_path, encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                key, _, value = line.partition("=")
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
                os.environ[key] = value
    except OSError:
        pass


def api(method: str, path: str, body=None):
    """Call the Supabase Management API and return (status, json|text)."""
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
            # Cloudflare (in front of api.supabase.com) returns HTTP 403 /
            # "error code: 1010" for the default Python-urllib user agent.
            "User-Agent": "curl/8.5.0 (DrsListing verify-booking)",
        },
    )
    try:
        with urllib.request.urlopen(req) as resp:
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


def run_query(sql: str):
    """POST a SQL statement via /database/query and return parsed rows."""
    status, resp = api("POST", "/database/query", {"query": sql})
    if status not in (200, 201):
        sys.exit(f"  ! Query failed ({status}): {resp}")
    return resp if isinstance(resp, list) else []


def call_function(params: str, payload=None):
    """Call the live Edge Function; GET when payload is None, else POST.

    The place id is URL-encoded (matching `Uri.encodeComponent` used by
    AppConstants.bookingPageUrl) so custom ids containing `=`, `&`, `#` or
    spaces survive as a single `doctor` query parameter.
    """
    url = f"https://{PROJECT_REF}.supabase.co/functions/v1/booking-page?{params}"
    headers = {
        "User-Agent": "curl/8.5.0 (DrsListing verify-booking)",
        "Content-Type": "application/json",
    }
    if payload is not None:
        headers["x-booking-token"] = BOOKING_SECRET
        req = urllib.request.Request(
            url, data=json.dumps(payload).encode(), method="POST", headers=headers
        )
    else:
        req = urllib.request.Request(url, method="GET", headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            raw = resp.read().decode()
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
    keep = "--keep" in sys.argv
    place_id = DEFAULT_DOCTOR_PLACE_ID
    if "--doctor" in sys.argv:
        idx = sys.argv.index("--doctor")
        if idx + 1 < len(sys.argv):
            place_id = sys.argv[idx + 1]
    if "--project-ref" in sys.argv:
        idx = sys.argv.index("--project-ref")
        if idx + 1 >= len(sys.argv):
            sys.exit("ERROR: --project-ref requires a value, e.g. --project-ref abcd...")
        PROJECT_REF = sys.argv[idx + 1]

    doctor_q = f"doctor={quote(place_id, safe='')}"

    print("== DrsListing booking POST verification ==")
    print(f"  project ref:    {PROJECT_REF}")
    print(f"  doctor placeId: {place_id}")
    print(f"  test name:      {TEST_NAME}")
    print(f"  test mobile:    {TEST_MOBILE}")
    print(f"  test slots:     {TEST_DATE} {' / '.join(TEST_TIMES)}")
    if keep:
        print("  --keep: test rows will be left for cleanup_test_data.py --yes")

    if not os.environ.get("SUPABASE_ACCESS_TOKEN", "").strip():
        sys.exit(
            "ERROR: SUPABASE_ACCESS_TOKEN is not set.\n"
            f"Save it in {DEPLOY_ENV_FILE} or export it and re-run."
        )

    # ── 0. Pre-flight: clear leftover marker rows ─────────────────
    # The one-patient-one-doctor gate (active booking + 12h cooldown from
    # the last booking's created_at) blocks a NEW booking for this mobile
    # within 12h of any leftover row — so a row left behind by an
    # interrupted run or an earlier --keep run would fail THIS run with
    # the gate message instead of the slot-taken fallback. Clear any
    # marker rows first (same markers as the end-of-run cleanup, so real
    # patients can never be touched).
    print("\n[0/6] Pre-flight: clearing leftover test bookings...")
    leftovers = run_query(
        "SELECT appointment_id FROM public.appointments "
        f"WHERE patient_name = '{TEST_NAME}' AND patient_phone = '{TEST_MOBILE}'"
    )
    for leftover in leftovers:
        apt_id = str(leftover.get("appointment_id") or "")
        if not apt_id:
            continue
        api(
            "POST",
            "/database/query",
            {"query": f"DELETE FROM public.payments WHERE appointment_id = '{apt_id}'"},
        )
        api(
            "POST",
            "/database/query",
            {"query": f"DELETE FROM public.appointments WHERE appointment_id = '{apt_id}'"},
        )
        print(f"  -> removed leftover {apt_id}")
    if not leftovers:
        print("  -> none found")

    # ── 1. GET action=slots ──────────────────────────────────────
    print("\n[1/6] GET action=slots (availability JSON)...")
    status, slots = call_function(
        f"{doctor_q}&token={BOOKING_SECRET}&action=slots"
    )
    if status != 200 or not isinstance(slots, dict) or not slots.get("ok"):
        print(f"  ! slots failed ({status}): {slots}")
        sys.exit(1)
    print(f"  -> ok: true, doctor rows: {len(slots.get('slots', []))}, "
          f"booked keys: {len(slots.get('booked', []))}")
    if not isinstance(slots.get("slots"), list):
        print("  ! slots payload missing 'slots' list.")
        sys.exit(1)

    # The chosen slot type + fee for the payment assertion. Web/QR bookings
    # are offline pay-at-clinic, so the Edge Function records a Pending /
    # offline payment row with the slot's fee (resolved server-side from
    # doctor_slots) — this verifier sends the same `type` the web page does
    # and expects that row to land. Falls back to the legacy no-type path
    # (no fee applies) when tomorrow has no fee'd slot.
    weekday_name = datetime.strptime(TEST_DATE, "%Y-%m-%d").strftime("%A")
    slot_type = None
    expected_fee = None
    for s in slots.get("slots", []):
        if (
            s.get("day_of_week") == weekday_name
            and s.get("is_enabled", False)
            and float(s.get("fee") or 0) > 0
            and s.get("slots")
        ):
            slot_type = s.get("schedule_type")
            expected_fee = float(s.get("fee"))
            break
    if slot_type:
        print(f"  -> fee slot: {weekday_name} {slot_type} = ₹{expected_fee}")
    else:
        print("  -> no fee'd slot tomorrow — will verify the legacy no-payment path")

    # ── 2. POST action=register ──────────────────────────────────
    print("\n[2/6] POST action=register (save patient to users table)...")
    status, reg = call_function(
        doctor_q,
        {"action": "register", "name": TEST_NAME, "mobile": TEST_MOBILE},
    )
    if status != 200 or not isinstance(reg, dict) or not reg.get("ok"):
        print(f"  ! register failed ({status}): {reg}")
        sys.exit(1)
    reg_user_id = str(reg.get("userId") or "")
    if not reg_user_id:
        print("  ! register did not return a userId.")
        sys.exit(1)
    print(f"  -> ok: true, userId: {reg_user_id}")

    # ── 3. POST action=book (slot-based) ─────────────────────────
    print("\n[3/6] POST action=book (slot booking)...")
    booked_time = None
    for t in TEST_TIMES:
        book_payload = {
            "action": "book",
            "name": TEST_NAME,
            "mobile": TEST_MOBILE,
            "description": TEST_SYMPTOMS,
            "date": TEST_DATE,
            "time": t,
        }
        if slot_type:
            book_payload["type"] = slot_type
        status, resp = call_function(doctor_q, book_payload)
        if status == 200 and isinstance(resp, dict) and resp.get("ok"):
            booked_time = t
            break
        err = (resp or {}).get("error", "") if isinstance(resp, dict) else ""
        print(f"  -> {t}: taken/refused ({err or status}) — trying next...")

    # Every candidate slot was taken by a real patient — fall back to the
    # legacy today+Flexible book so a deploy never fails spuriously.
    if booked_time is None:
        print("  ! All candidate slots taken — falling back to legacy book (today/Flexible).")
        status, resp = call_function(
            doctor_q,
            {"name": TEST_NAME, "mobile": TEST_MOBILE, "description": TEST_SYMPTOMS},
        )

    if status != 200 or not isinstance(resp, dict) or not resp.get("ok"):
        print(f"  ! Booking failed ({status}): {resp}")
        sys.exit(1)

    appointment_id = str(resp.get("appointmentId", ""))
    print(f"  -> ok: true")
    print(f"  -> appointmentId: {appointment_id}")
    print(f"  -> doctorName:    {resp.get('doctorName')}")
    print(f"  -> patientName:   {resp.get('patientName')}")
    print(f"  -> date:          {resp.get('date')}")
    print(f"  -> time:          {resp.get('time')}")

    if not appointment_id:
        print("  ! Response missing appointmentId — cannot verify the DB row.")
        sys.exit(1)

    # ── 4. Confirm the row landed in the live DB ─────────────────
    print("\n[4/6] Confirming the row in the appointments table...")
    rows = run_query(
        "SELECT appointment_id, patient_name, doctor_place_id, status, "
        "appointment_date, appointment_time "
        "FROM public.appointments "
        f"WHERE appointment_id = '{appointment_id}'"
    )
    if len(rows) != 1:
        print(f"  ! Expected 1 row for {appointment_id}, found {len(rows)}.")
        sys.exit(1)
    row = rows[0]
    print(f"  -> {row.get('appointment_id')}  {row.get('patient_name')}  "
          f"{row.get('doctor_place_id')}  ({row.get('status')})  "
          f"{row.get('appointment_date')} {row.get('appointment_time')}")
    if row.get("status") != "Pending":
        print(f"  ! Expected status 'Pending', got '{row.get('status')}'.")
        sys.exit(1)
    if booked_time is not None:
        if row.get("appointment_date") != TEST_DATE:
            print(f"  ! Expected date '{TEST_DATE}', got '{row.get('appointment_date')}'.")
            sys.exit(1)
        if row.get("appointment_time") != booked_time:
            print(f"  ! Expected time '{booked_time}', got '{row.get('appointment_time')}'.")
            sys.exit(1)
        print(f"  -> status 'Pending' + {TEST_DATE} {booked_time} match [OK]")
    else:
        print("  -> status 'Pending' (legacy today/Flexible fallback) [OK]")

    # ── 4b. Payment row (web/QR bookings are offline pay-at-clinic) ─
    print("  → payment record...")
    pay_rows = run_query(
        "SELECT appointment_id, patient_id, payment_status, payment_method, amount "
        "FROM public.payments "
        f"WHERE appointment_id = '{appointment_id}'"
    )
    # A payment row is expected ONLY when a concrete slot was actually
    # booked WITH a type. When every TEST_TIMES slot was taken and the
    # script fell back to the legacy today/Flexible book (no type), the
    # function correctly records NO payment — asserting one would false-FAIL.
    if booked_time is not None and slot_type is not None and expected_fee is not None:
        if len(pay_rows) != 1:
            print(f"  ! Expected 1 payment row for {appointment_id}, "
                  f"found {len(pay_rows)}.")
            sys.exit(1)
        pr = pay_rows[0]
        pay_ok = (
            pr.get("payment_status") == "Pending"
            and pr.get("payment_method") == "offline"
            and abs(float(pr.get("amount") or 0) - expected_fee) < 0.01
            and str(pr.get("patient_id")) == str(reg_user_id)
        )
        if not pay_ok:
            print(f"  ! Payment row mismatch: {pr}")
            sys.exit(1)
        print(f"  -> payment row: Pending / offline / ₹{expected_fee} "
              f"for patient {reg_user_id} [OK]")
    else:
        if pay_rows:
            print(f"  ! Unexpected payment row for legacy booking: {pay_rows}")
            sys.exit(1)
        print("  -> no payment recorded (legacy today/Flexible fallback) [OK]")

    # ── 5. GET action=history includes the new booking ───────────
    print("\n[5/6] GET action=history (patient history)...")
    status, hist = call_function(
        f"{doctor_q}&token={BOOKING_SECRET}&action=history&mobile={TEST_MOBILE}"
    )
    if status != 200 or not isinstance(hist, dict) or not hist.get("ok"):
        print(f"  ! history failed ({status}): {hist}")
        sys.exit(1)
    appts = hist.get("appointments", [])
    ids = [a.get("appointment_id") for a in appts]
    if appointment_id not in ids:
        print(f"  ! history missing {appointment_id} (found {ids}).")
        sys.exit(1)
    print(f"  -> history lists {appointment_id} [OK] ({len(appts)} total)")

    # The history payload must carry the payment summary on the matching
    # appointment (what booking.html renders as the Fee row) — asserted on
    # the SAME gate as the payments-table check above: only when a
    # concrete fee'd slot was actually booked. The legacy fallback
    # (today + Flexible) records no payment, so its history row must have
    # payment == null — asserting one would false-FAIL the deploy.
    mine = [a for a in appts if a.get("appointment_id") == appointment_id]
    hist_pay = mine[0].get("payment") if mine else None
    if booked_time is not None and slot_type is not None and expected_fee is not None:
        ok_pay = (
            isinstance(hist_pay, dict)
            and abs(float(hist_pay.get("amount") or 0) - expected_fee) < 0.01
            and hist_pay.get("method") == "offline"
            and hist_pay.get("status") == "Pending"
            and hist_pay.get("currency") == "INR"
        )
        if not ok_pay:
            print(f"  ! history payment summary missing/mismatched: {hist_pay}")
            sys.exit(1)
        print(f"  -> history payment: ₹{expected_fee} / offline / Pending [OK]")
    elif hist_pay is not None:
        print(f"  ! unexpected history payment summary for legacy booking: {hist_pay}")
        sys.exit(1)
    else:
        print("  -> history payment: none (legacy no-fee path) [OK]")

    # ── 6. Clean up (unless --keep) ──────────────────────────────
    print("\n[6/6] Cleaning up the test booking...")
    if keep:
        print("  --keep set — leaving the rows for cleanup_test_data.py --yes.")
    else:
        # Delete the payment row first (the appointment FK would cascade,
        # but explicit is safer and keeps the --keep bookkeeping clear).
        del_pay = (
            "DELETE FROM public.payments "
            f"WHERE appointment_id = '{appointment_id}'"
        )
        status, resp = api("POST", "/database/query", {"query": del_pay})
        print(f"  -> deleted payment:     {status}: "
              f"{resp if status not in (200, 201) else 'OK'}")

        del_appt = (
            "DELETE FROM public.appointments "
            f"WHERE appointment_id = '{appointment_id}'"
        )
        status, resp = api("POST", "/database/query", {"query": del_appt})
        print(f"  -> deleted appointment: {status}: "
              f"{resp if status not in (200, 201) else 'OK'}")

        # Delete the patient user ONLY if they match the test markers AND
        # have no remaining appointments (real patients can never be hit).
        del_user = (
            "DELETE FROM public.users "
            f"WHERE name = '{TEST_NAME}' AND mobile = '{TEST_MOBILE}' "
            "AND id NOT IN (SELECT user_id FROM public.appointments "
            "                 WHERE user_id IS NOT NULL)"
        )
        status, resp = api("POST", "/database/query", {"query": del_user})
        print(f"  -> deleted test user:  {status}: "
              f"{resp if status not in (200, 201) else 'OK'}")

    # ── Verify cleanup ───────────────────────────────────────────
    print("\n  Verifying cleanup...")
    remaining = run_query(
        "SELECT COUNT(*) AS c FROM public.appointments "
        f"WHERE appointment_id = '{appointment_id}'"
    )
    count = remaining[0].get("c", 0) if remaining else 0
    try:
        count = int(count)
    except (TypeError, ValueError):
        count = -1

    remaining_users = run_query(
        "SELECT COUNT(*) AS c FROM public.users "
        f"WHERE name = '{TEST_NAME}' AND mobile = '{TEST_MOBILE}'"
    )
    user_count = remaining_users[0].get("c", 0) if remaining_users else 0
    try:
        user_count = int(user_count)
    except (TypeError, ValueError):
        user_count = -1

    if keep:
        if count != 1:
            print(f"  ! Expected the kept appointment ({count} found) — "
                  "inspect manually.")
            sys.exit(1)
        if user_count != 1:
            print(f"  ! Expected the kept user row ({user_count} found) — "
                  "inspect manually.")
            sys.exit(1)
        print("  -> kept rows present [OK] (removable via "
              "cleanup_test_data.py --yes)")
        print("\nSUCCESS: booking POST verified end-to-end (test rows kept).")
    else:
        if count != 0:
            print(f"  ! Appointment still present ({count} row(s)) — "
                  "inspect manually.")
            sys.exit(1)
        if user_count != 0:
            print(f"  ! Test user still present ({user_count} row(s)) — "
                  "likely a protected user with real appointments; inspect "
                  "manually.")
            sys.exit(1)
        print("  -> appointment removed [OK]")
        print("  -> test user removed [OK]")
        print("\nSUCCESS: booking POST verified end-to-end and cleaned up.")


if __name__ == "__main__":
    main()
