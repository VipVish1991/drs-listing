#!/usr/bin/env python3
"""
DrsListing — Clean up test/QA data created during verification.

Deletes appointments and user rows that were created by the automated
verification runs (booking-page smoke tests, dashboard Pending checks,
browser walkthroughs). Real patient data is never touched.

Usage:
    python supabase/cleanup_test_data.py --dry-run  # preview only (no delete)
    python supabase/cleanup_test_data.py --yes      # real delete (requires --yes)

The SUPABASE_ACCESS_TOKEN is read from .env.deploy (recommended) or the
environment, exactly like deploy_booking.py.

What it deletes:
  Appointments with:
    - appointment_id LIKE 'APT_VERIFY%'      (dashboard/live verification rows)
    - patient_name IN (...VERIFY_NAMES)      (all the QA names we used)
    - symptoms LIKE '%verify pending%' etc.  (marker text in symptoms)
  Users (patients) linked to those appointments — but ONLY rows whose
  name/mobile match the known test markers, so real patients can never
  be removed accidentally.
"""

import json
import os
import sys
import urllib.request
import urllib.error

PROJECT_REF = "qxukzqdsmlurollltrjp"
BASE_URL = f"https://api.supabase.com/v1/projects/{PROJECT_REF}"

DEPLOY_ENV_FILE = ".env.deploy"

# Test markers used by our verification runs. Keep in sync if new
# automated checks are added.
VERIFY_APPT_ID_PREFIX = "APT_VERIFY"
VERIFY_NAMES = [
    "Test Patient QA",
    "Browser Test Patient",
    "Browser Flow Patient",
    "Dashboard Verify Patient",
    "Verify Patient",
    "Verify User",
]
VERIFY_MOBILES = [
    "919876500001",
    "919876500077",
    "919876500099",
    "919876500123",
]
VERIFY_SYMPTOM_MARKERS = [
    "verify pending visibility",
    "verify pending",
    "e2e verification",
    "walkthrough verification",
]


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

    url = BASE_URL + path
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
            "User-Agent": "curl/8.5.0 (DrsListing cleanup)",
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


def quote_list(values):
    """Turn a Python list of strings into SQL literal list text."""
    return ", ".join(f"'{v}'" for v in values)


def main() -> None:
    load_deploy_env()
    dry_run = "--dry-run" in sys.argv
    confirmed = "--yes" in sys.argv

    print("== DrsListing test-data cleanup ==")
    if dry_run:
        print("  DRY RUN — no rows will be deleted.\n")

    # ── 1. Find matching appointments ─────────────────────────────
    print("[1/2] Finding test appointments...")
    name_list = quote_list(VERIFY_NAMES)
    mobile_list = quote_list(VERIFY_MOBILES)
    symptom_clause = " OR ".join(
        f"symptoms ILIKE '%{m}%'" for m in VERIFY_SYMPTOM_MARKERS
    )
    appt_clauses = [
        f"appointment_id LIKE '{VERIFY_APPT_ID_PREFIX}%'",
        f"patient_name IN ({name_list})",
    ]
    if symptom_clause:
        appt_clauses.append(symptom_clause)
    find_sql = (
        "SELECT appointment_id, patient_name, user_id, status "
        "FROM public.appointments WHERE " + " OR ".join(appt_clauses)
    )
    del_sql = (
        "DELETE FROM public.appointments WHERE " + " OR ".join(appt_clauses)
    )
    appts = run_query(find_sql)
    print(f"  -> {len(appts)} test appointment(s) found.")
    for a in appts:
        print(f"     - {a.get('appointment_id')}  {a.get('patient_name')}  "
              f"({a.get('status')})")

    # ── 2. Find matching users (test markers only) ────────────────
    print("\n[2/2] Finding test users...")
    find_users_sql = (
        f"SELECT id, name, mobile FROM public.users "
        f"WHERE name IN ({name_list}) OR mobile IN ({mobile_list})"
    )
    users = run_query(find_users_sql)
    print(f"  -> {len(users)} test user(s) found.")
    for u in users:
        print(f"     - {u.get('id')}  {u.get('name')}  {u.get('mobile')}")

    if dry_run:
        print("\nDRY RUN complete — no rows deleted.")
        return

    if not appts and not users:
        print("\nNothing to clean up. Exiting.")
        return

    if not confirmed:
        sys.exit(
            "  ! Refusing to delete without confirmation.\n"
            "    This deletes rows from the LIVE project. Re-run with "
            "--yes to proceed (use --dry-run first to preview)."
        )

    # ── 3. Delete appointments ────────────────────────────────────
    print("\nDeleting test appointments...")
    status, resp = api("POST", "/database/query", {"query": del_sql})
    print(f"  -> {status}: {resp if status not in (200, 201) else 'OK'}")

    # ── 4. Delete test users (only ones matching markers AND no
    #       remaining appointments, so real patients are safe) ─────
    print("Deleting test users...")
    if users:
        user_ids = quote_list(u["id"] for u in users if u.get("id"))
        del_users_sql = (
            f"DELETE FROM public.users "
            f"WHERE id IN ({user_ids}) "
            f"AND (name IN ({name_list}) OR mobile IN ({mobile_list})) "
            f"AND id NOT IN (SELECT user_id FROM public.appointments "
            f"                 WHERE user_id IS NOT NULL)"
        )
        status, resp = api("POST", "/database/query", {"query": del_users_sql})
        print(f"  -> {status}: {resp if status not in (200, 201) else 'OK'}")
    else:
        print("  -> no test users to delete")

    # ── 5. Verify ─────────────────────────────────────────────────
    print("\nVerifying cleanup...")
    remaining_appts = run_query(find_sql)
    remaining_users = run_query(find_users_sql)
    print(f"  -> remaining test appointments: {len(remaining_appts)}")
    print(f"  -> remaining test users: {len(remaining_users)}")
    if remaining_appts or remaining_users:
        # Marker-matching rows can legitimately remain when a user is
        # protected because they still have a REAL appointment.
        sys.exit(
            "  ! Some marker-matching rows remain (possibly protected "
            "real users) — inspect manually."
        )
    print("\nSUCCESS: test data cleaned up.")


if __name__ == "__main__":
    main()
