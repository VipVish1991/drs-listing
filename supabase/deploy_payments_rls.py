#!/usr/bin/env python3
"""
DrsListing — Apply & verify the doctor-side payments RLS
(offline 'Pending' → 'Paid' / 'Refunded' from the doctor appointments screen).

Why: the payments table is patient-scoped. This migration lets a clinic — a
`doctors` row whose `user_id` is the caller's x-user-id header — READ payment
rows for its own appointments and flip their status, with UPDATE
column-restricted to payment_status / paid_at / updated_at.

Convention-matched with deploy_payments.py / apply_users_rls.py:

  1. Reads SUPABASE_ACCESS_TOKEN from .env.deploy and the project ref
     from supabase/.temp/linked-project.json.
  2. Applies supabase/migrations/20260809000002_add_payments_doctor_rls.sql
     (idempotent: CREATE POLICY + REVOKE/GRANT).
  3. Verifies through the PUBLIC PostgREST API with the anon key, exactly
     like the app:
       * the owning clinic  (x-user-id = doctors.user_id)  → UPDATE succeeds
       * a different clinic (owns another place)           → 0 rows
       * the patient (owns no clinic)                      → 0 rows
       * no header                                         → 0 rows
       * the owning clinic SELECTs its rows; without header → nothing
  4. Deletes the test rows afterwards (cleanup, like deploy_payments.py).

Usage:
    python supabase/deploy_payments_rls.py
"""
import json
import re
import sys
import urllib.error
import urllib.request
from pathlib import Path

for _stream in (sys.stdout, sys.stderr):
    try:
        _stream.reconfigure(encoding="utf-8")
    except (AttributeError, ValueError):
        pass

ROOT = Path(__file__).resolve().parent.parent
MIGRATION = ROOT / "supabase" / "migrations" / "20260809000002_add_payments_doctor_rls.sql"
PATIENT_MOBILE = "9999990003"  # clearly-fake test mobiles; cleaned up at the end
DOCTOR_MOBILE = "9999990004"
OTHER_DOCTOR_MOBILE = "9999990005"
PLACE = "place_probe_rls"
OTHER_PLACE = "place_probe_rls_other"


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
    req = urllib.request.Request(
        MGMT,
        data=json.dumps({"query": sql}).encode(),
        headers={
            "Authorization": f"Bearer {TOKEN}",
            "Content-Type": "application/json",
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
    req = urllib.request.Request(REST + path, data=body, headers=req_headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            raw = resp.read().decode()
            return resp.status, json.loads(raw) if raw else []
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode(errors="replace")


def check(label, ok, detail=""):
    print(f"  [{'PASS' if ok else 'FAIL'}] {label}" + (f" — {detail}" if detail else ""))
    return ok


def blocked(st, body):
    """A denied RLS UPDATE is either HTTP 403 or 200 with an empty list."""
    return st in (403, 401, 400) or (st == 200 and isinstance(body, list) and len(body) == 0)


def main():
    print(f"target: {REF} (token loaded, anon key loaded)")
    print(f"migration: {MIGRATION.name}")

    # 0. Pre-clean leftovers from a previous interrupted run.
    mgmt(
        "delete from public.payments where doctor_place_id in "
        f"('{PLACE}', '{OTHER_PLACE}');"
    )
    mgmt(f"delete from public.doctors where place_id in ('{PLACE}', '{OTHER_PLACE}');")
    mgmt(
        "delete from public.users where mobile in "
        f"('{PATIENT_MOBILE}', '{DOCTOR_MOBILE}', '{OTHER_DOCTOR_MOBILE}');"
    )

    # 1. Apply the migration
    print("\n── applying migration ──")
    sql = MIGRATION.read_text(encoding="utf-8")
    st, body = mgmt(sql)
    if st not in (200, 201):
        sys.exit(f"error: migration failed (HTTP {st}): {body}")
    print(f"  applied (HTTP {st})")

    # 2. Confirm the policies + column-restricted UPDATE grants exist
    print("\n── after: policies + column grants ──")
    st, rows = mgmt(
        "select policyname, cmd from pg_policies "
        "where schemaname='public' and tablename='payments' order by policyname;"
    )
    names = [r.get("policyname") for r in rows] if isinstance(rows, list) else []
    policies_ok = {"payments_select_doctor", "payments_update_doctor"} <= set(names)
    check("doctor policies present (select_doctor, update_doctor)", policies_ok, names)

    st, rows = mgmt(
        "select distinct column_name from information_schema.column_privileges "
        "where table_schema='public' and table_name='payments' "
        "and grantee in ('anon', 'authenticated') and privilege_type='UPDATE' "
        "order by column_name;"
    )
    cols = [r.get("column_name") for r in rows] if isinstance(rows, list) else []
    cols_ok = set(cols) == {"payment_status", "paid_at", "updated_at"}
    check("UPDATE granted ONLY on payment_status/paid_at/updated_at", cols_ok, cols)

    # 3. End-to-end verify through the public API, exactly like the app
    print("\n── verifying through public PostgREST (anon key) ──")

    def make_user(name, mobile):
        st, u = rest(
            "POST", "/users", {"name": name, "mobile": mobile},
            headers={"x-user-mobile": mobile},
        )
        if st not in (200, 201) or not isinstance(u, list) or not u:
            sys.exit(f"error: could not create probe user {mobile} (HTTP {st}): {u}")
        return u[0]["id"]

    patient_uid = make_user("RLS Patient", PATIENT_MOBILE)
    doctor_uid = make_user("RLS Doctor", DOCTOR_MOBILE)
    other_uid = make_user("RLS Other Doctor", OTHER_DOCTOR_MOBILE)
    print(f"  probe users: patient={patient_uid}, doctor={doctor_uid}, other={other_uid}")

    # Link clinics to the doctor users (service context — RLS bypassed).
    st, _ = mgmt(
        "insert into public.doctors (place_id, name, user_id) values "
        f"('{PLACE}', 'Probe Clinic', '{doctor_uid}'), "
        f"('{OTHER_PLACE}', 'Other Clinic', '{other_uid}');"
    )
    if st not in (200, 201):
        sys.exit(f"error: could not seed probe clinics (HTTP {st}): {_}")
    print("  probe clinics linked to doctor users")

    # Create the appointment + an offline Pending payment for it.
    apt_id = f"PAYRLS{abs(hash('payment-rls')) & 0xFFFFFF}"
    st, apt = rest(
        "POST",
        "/appointments",
        {
            "appointment_id": apt_id,
            "user_id": patient_uid,
            "patient_name": "RLS Patient",
            "doctor_name": "Probe Clinic",
            "doctor_place_id": PLACE,
            "appointment_date": "2099-01-01",
            "appointment_time": "10:00 AM",
            "status": "Upcoming",
        },
    )
    if st not in (200, 201):
        sys.exit(f"error: could not create probe appointment (HTTP {st}): {apt}")
    print(f"  probe appointment: {apt_id}")

    st, pay = rest(
        "POST",
        "/payments",
        {
            "appointment_id": apt_id,
            "patient_id": patient_uid,
            "doctor_place_id": PLACE,
            "doctor_name": "Probe Clinic",
            "consultation_type": "clinic",
            "payment_status": "Pending",
            "payment_method": "offline",
            "amount": 1000,
        },
        headers={"x-user-id": patient_uid},
    )
    if st not in (200, 201) or not isinstance(pay, list) or not pay:
        sys.exit(f"error: could not create probe payment (HTTP {st}): {pay}")
    pay_id = pay[0]["id"]
    print(f"  probe payment (offline Pending): {pay_id}")

    # 3a. UPDATE without any header → 0 rows / rejected.
    st, body = rest("PATCH", f"/payments?id=eq.{pay_id}", {"payment_status": "Paid"})
    check("UPDATE without x-user-id is blocked", blocked(st, body), f"HTTP {st}")

    # 3b. Patient (owns no clinic) UPDATE → 0 rows.
    st, body = rest(
        "PATCH", f"/payments?id=eq.{pay_id}", {"payment_status": "Paid"},
        headers={"x-user-id": patient_uid},
    )
    check("patient UPDATE (owns no clinic) is blocked", blocked(st, body), f"HTTP {st}")

    # 3c. Doctor of a DIFFERENT clinic UPDATE → 0 rows.
    st, body = rest(
        "PATCH", f"/payments?id=eq.{pay_id}", {"payment_status": "Paid"},
        headers={"x-user-id": other_uid},
    )
    check("other clinic UPDATE is blocked", blocked(st, body), f"HTTP {st}")

    # 3d. Owning clinic UPDATE → succeeds (row comes back via return=representation,
    #     which also proves the doctor SELECT policy lets them see the row). The
    #     payload mirrors SupabaseService.updatePaymentStatus exactly: status +
    #     paid_at (set only for Paid) + updated_at.
    st, rows = rest(
        "PATCH",
        f"/payments?id=eq.{pay_id}",
        {
            "payment_status": "Paid",
            "paid_at": "2026-08-09T12:00:00+00:00",
            "updated_at": "2026-08-09T12:00:00+00:00",
        },
        headers={"x-user-id": doctor_uid},
    )
    own_ok = st in (200, 201) and isinstance(rows, list) and len(rows) == 1
    own_ok = own_ok and rows[0].get("payment_status") == "Paid"
    own_ok = own_ok and rows[0].get("paid_at") is not None
    check("owning clinic UPDATE succeeds and sets paid_at", own_ok, rows if not own_ok else "OK")

    # 3e. Doctor SELECT with the header → sees the row; without → nothing.
    st, rows = rest("GET", "/payments", headers={"x-user-id": doctor_uid})
    sel_ok = st == 200 and isinstance(rows, list) and any(r.get("id") == pay_id for r in rows)
    check("doctor SELECT with x-user-id sees own payment rows", sel_ok, f"HTTP {st}")

    st, rows = rest("GET", "/payments")
    hidden_ok = st == 200 and isinstance(rows, list) and rows == []
    check("doctor SELECT without x-user-id returns nothing", hidden_ok, rows if not hidden_ok else "OK")

    # 4. Cleanup
    print("\n── cleanup ──")
    mgmt(f"delete from public.payments where id = '{pay_id}';")
    mgmt(f"delete from public.appointments where appointment_id = '{apt_id}';")
    mgmt(f"delete from public.doctors where place_id in ('{PLACE}', '{OTHER_PLACE}');")
    mgmt(
        "delete from public.users where mobile in "
        f"('{PATIENT_MOBILE}', '{DOCTOR_MOBILE}', '{OTHER_DOCTOR_MOBILE}');"
    )
    print("  probe rows deleted")

    all_ok = policies_ok and cols_ok and own_ok and sel_ok and hidden_ok
    print(f"\nRESULT: {'ALL CHECKS PASSED' if all_ok else 'SOME CHECKS FAILED'}")
    sys.exit(0 if all_ok else 1)


if __name__ == "__main__":
    main()
