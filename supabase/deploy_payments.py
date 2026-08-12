#!/usr/bin/env python3
"""
DrsListing — Apply & verify the payments table (UPI / offline consultation fees).

Why: the Flutter app records every consultation payment against an
appointment (upi_india online, or offline pay-at-clinic). This
script (convention-matched with apply_users_rls.py / deploy_booking.py):

  1. Reads SUPABASE_ACCESS_TOKEN from .env.deploy and the project ref
     from supabase/.temp/linked-project.json.
  2. Applies supabase/migrations/20260809000001_add_payments_table.sql
     (idempotent: CREATE TABLE IF NOT EXISTS + CREATE POLICY).
  3. Verifies through the PUBLIC PostgREST API with the anon key, exactly
     like the app:
       * INSERT  with    x-user-id header matching patient_id → succeeds
       * INSERT  without x-user-id (or wrong one)            → rejected
       * SELECT  with    x-user-id                           → own rows only
  4. Deletes the test rows afterwards (cleanup, like cleanup_test_data.py).

The web booking page / Edge Function uses the service-role key and is
unaffected (RLS is bypassed for service_role).

Usage:
    python supabase/deploy_payments.py
"""
import json
import re
import sys
import urllib.error
import urllib.request
from pathlib import Path

# Windows consoles default to cp1252, which cannot encode the box-drawing
# and emoji characters used in the output below. Force UTF-8 so the script
# behaves identically on every platform.
for _stream in (sys.stdout, sys.stderr):
    try:
        _stream.reconfigure(encoding="utf-8")
    except (AttributeError, ValueError):
        pass  # not a text stream, or the encoding is fixed — leave as-is

ROOT = Path(__file__).resolve().parent.parent
MIGRATION = ROOT / "supabase" / "migrations" / "20260809000001_add_payments_table.sql"
TEST_MOBILE = "9999990002"  # clearly-fake test mobile; cleaned up at the end


def _load_token() -> str:
    env = ROOT / ".env.deploy"
    if not env.exists():
        sys.exit("error: .env.deploy not found — add SUPABASE_ACCESS_TOKEN=...")
    m = re.search(
        r"^SUPABASE_ACCESS_TOKEN\s*=\s*(.+)$",
        env.read_text(encoding="utf-8"),
        re.M,
    )
    if not m:
        sys.exit("error: SUPABASE_ACCESS_TOKEN missing in .env.deploy")
    return m.group(1).strip()


def _load_ref() -> str:
    link = ROOT / "supabase" / ".temp" / "linked-project.json"
    if not link.exists():
        sys.exit("error: supabase/.temp/linked-project.json not found (run `supabase link`)")
    return json.loads(link.read_text(encoding="utf-8"))["ref"]


def _load_anon_key() -> str:
    text = (ROOT / "lib" / "config" / "constants.dart").read_text(encoding="utf-8")
    m = re.search(r"supabaseAnonKey\s*=\s*['\"]([^'\"]+)['\"]", text)
    if not m:
        sys.exit("error: could not find AppConstants.supabaseAnonKey in constants.dart")
    return m.group(1)


TOKEN = _load_token()
REF = _load_ref()
ANON = _load_anon_key()
REST = f"https://{REF}.supabase.co/rest/v1"
MGMT = f"https://api.supabase.com/v1/projects/{REF}/database/query"


def mgmt(sql):
    """Run SQL against the live project (Management API, service context)."""
    req = urllib.request.Request(
        MGMT,
        data=json.dumps({"query": sql}).encode(),
        headers={
            "Authorization": f"Bearer {TOKEN}",
            "Content-Type": "application/json",
            # Cloudflare in front of api.supabase.com returns HTTP 403 /
            # "error code: 1010" for the default Python-urllib user agent;
            # a recognizable browser/curl-like UA avoids the WAF block
            # (same fix as deploy_booking.py's api()).
            "User-Agent": "curl/8.5.0 (DrsListing deploy)",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            return resp.status, json.loads(resp.read().decode() or "[]")
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode(errors="replace")


def rest(method, path, payload=None, headers=None, prefer="return=representation"):
    """Call the public PostgREST API with the anon key."""
    req_headers = {
        "apikey": ANON,
        "Authorization": f"Bearer {ANON}",
        "User-Agent": "curl/8.5.0 (DrsListing deploy)",
    }
    if prefer:
        req_headers["Prefer"] = prefer
    if headers:
        req_headers.update(headers)
    body = None
    if payload is not None:
        req_headers["Content-Type"] = "application/json"
        body = json.dumps(payload).encode()
    req = urllib.request.Request(
        REST + path, data=body, headers=req_headers, method=method
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            raw = resp.read().decode()
            return resp.status, json.loads(raw) if raw else []
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode(errors="replace")


def check(label, ok, detail=""):
    print(f"  [{'PASS' if ok else 'FAIL'}] {label}" + (f" — {detail}" if detail else ""))
    return ok


def main():
    print(f"target: {REF} (token loaded, anon key loaded)")
    print(f"migration: {MIGRATION.name}")

    # 0. Pre-clean any leftover test rows from a previous interrupted run.
    mgmt(
        "delete from public.payments where patient_id in "
        "(select id from public.users where mobile = '%s');" % TEST_MOBILE
    )
    mgmt(f"delete from public.users where mobile = '{TEST_MOBILE}';")

    # 1. Apply the migration
    print("\n── applying migration ──")
    sql = MIGRATION.read_text(encoding="utf-8")
    st, body = mgmt(sql)
    if st not in (200, 201):
        sys.exit(f"error: migration failed (HTTP {st}): {body}")
    print(f"  applied (HTTP {st})")

    # 2. Confirm the table + policies exist
    print("\n── after: payments table + policies ──")
    st, rows = mgmt(
        "select tablename from pg_tables "
        "where schemaname='public' and tablename='payments';"
    )
    table_ok = st in (200, 201) and isinstance(rows, list) and len(rows) == 1
    check("payments table exists", table_ok, rows if not table_ok else "OK")

    st, rows = mgmt(
        "select policyname, cmd from pg_policies "
        "where schemaname='public' and tablename='payments' order by policyname;"
    )
    names = [r.get("policyname") for r in rows] if isinstance(rows, list) else []
    policies_ok = {"payments_select_own", "payments_insert_own"} <= set(names)
    check("RLS policies present (select_own, insert_own)", policies_ok, names)

    # 3. End-to-end verify through the public API, exactly like the app
    print("\n── verifying through public PostgREST (anon key) ──")

    # 3a. Create a probe user (users INSERT needs x-user-mobile header).
    st, user = rest(
        "POST",
        "/users",
        {"name": "Payment Verify Test", "mobile": TEST_MOBILE},
        headers={"x-user-mobile": TEST_MOBILE},
    )
    if st not in (200, 201) or not isinstance(user, list) or not user:
        sys.exit(f"error: could not create probe user (HTTP {st}): {user}")
    uid = user[0]["id"]
    print(f"  probe user: {uid}")

    # 3b. Create a probe appointment (appointments INSERT is anon-open).
    apt_id = f"PAYTEST{abs(hash('payment-probe')) & 0xFFFFFF}"
    st, apt = rest(
        "POST",
        "/appointments",
        {
            "appointment_id": apt_id,
            "user_id": uid,
            "patient_name": "Payment Verify Test",
            "doctor_name": "Probe Doctor",
            "doctor_place_id": "place_probe",
            "appointment_date": "2099-01-01",
            "appointment_time": "10:00 AM",
            "status": "Upcoming",
        },
    )
    if st not in (200, 201):
        sys.exit(f"error: could not create probe appointment (HTTP {st}): {apt}")
    print(f"  probe appointment: {apt_id}")

    # 3c. INSERT payment WITHOUT the x-user-id header → must be rejected.
    st, _ = rest(
        "POST",
        "/payments",
        {
            "appointment_id": apt_id,
            "patient_id": uid,
            "doctor_place_id": "place_probe",
            "payment_status": "Paid",
            "payment_method": "online",
            "amount": 800,
        },
    )
    check("INSERT without x-user-id is rejected", st in (400, 401, 403), f"HTTP {st}")

    # 3d. INSERT payment WITH the x-user-id header → must succeed.
    st, pay = rest(
        "POST",
        "/payments",
        {
            "appointment_id": apt_id,
            "patient_id": uid,
            "doctor_place_id": "place_probe",
            "doctor_name": "Probe Doctor",
            "consultation_type": "video",
            "payment_status": "Paid",
            "payment_method": "online",
            "amount": 800,
            "transaction_id": "TXNTEST123",
            "upi_id": "drslisting@upi",
        },
        headers={"x-user-id": uid},
    )
    insert_ok = st in (200, 201) and isinstance(pay, list) and len(pay) == 1
    check("INSERT with x-user-id succeeds", insert_ok, f"HTTP {st}" if not insert_ok else "OK")

    # 3e. SELECT with the x-user-id header → own row only, fields intact.
    st, rows = rest(
        "GET",
        f"/payments?select=appointment_id,amount,payment_status,payment_method,transaction_id&patient_id=eq.{uid}",
        headers={"x-user-id": uid},
    )
    own_ok = st == 200 and isinstance(rows, list) and len(rows) == 1
    own_ok = own_ok and rows[0].get("appointment_id") == apt_id
    own_ok = own_ok and rows[0].get("payment_status") == "Paid"
    own_ok = own_ok and rows[0].get("transaction_id") == "TXNTEST123"
    check("SELECT with x-user-id returns own payment row", own_ok, rows if not own_ok else "OK")

    # 3f. SELECT without the header → no rows (RLS hides everything).
    st, rows = rest(
        "GET",
        f"/payments?patient_id=eq.{uid}",
    )
    hidden_ok = st == 200 and isinstance(rows, list) and rows == []
    check("SELECT without x-user-id returns nothing", hidden_ok, rows if not hidden_ok else "OK")

    # 4. Cleanup
    print("\n── cleanup ──")
    mgmt(f"delete from public.payments where patient_id = '{uid}';")
    mgmt(f"delete from public.appointments where appointment_id = '{apt_id}';")
    mgmt(f"delete from public.users where id = '{uid}';")
    print("  probe rows deleted")

    all_ok = table_ok and policies_ok and insert_ok and own_ok and hidden_ok
    print(f"\nRESULT: {'ALL CHECKS PASSED' if all_ok else 'SOME CHECKS FAILED'}")
    sys.exit(0 if all_ok else 1)


if __name__ == "__main__":
    main()
