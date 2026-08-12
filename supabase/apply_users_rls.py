#!/usr/bin/env python3
"""
DrsListing — Apply & verify the tightened RLS policies on public.users.

Why: the mobile app talks to PostgREST with the anon key, and the old
policies let ANY anon client read every user row and update any row.
This script (convention-matched with deploy_booking.py):

  1. Reads SUPABASE_ACCESS_TOKEN from .env.deploy and the project ref
     from supabase/.temp/linked-project.json.
  2. Applies supabase/migrations/20260801000001_tighten_users_rls.sql
     (idempotent: DROP IF EXISTS + CREATE POLICY).
  3. Verifies the new behaviour through the PUBLIC PostgREST API with the
     anon key:
       * SELECT  without x-user-mobile  → no rows (RLS hides everything)
       * INSERT  without x-user-mobile  → rejected
       * INSERT  with    x-user-mobile  → succeeds (own row only)
       * UPDATE  without x-user-id      → 0 rows affected
       * UPDATE  with    x-user-id + x-user-mobile → succeeds on own
         row (BOTH headers are required: supabase-dart requests
         `return=representation`, so PostgREST materializes the row
         through the SELECT policy — x-user-id alone silently affects
         0 rows)
       * SELECT  with    x-user-mobile  → own row visible
  4. Deletes the test rows afterwards (cleanup, like cleanup_test_data.py).

The web booking page / Edge Function uses the service-role key and is
unaffected (RLS is bypassed for service_role).

Usage:
    python supabase/apply_users_rls.py
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
MIGRATION = ROOT / "supabase" / "migrations" / "20260801000001_tighten_users_rls.sql"
TEST_MOBILE = "9999990001"  # clearly-fake test mobile; cleaned up at the end
TEST_NAME = "RLS Verify Test"


def _load_token() -> str:
    env = ROOT / ".env.deploy"
    if not env.exists():
        sys.exit("error: .env.deploy not found — add SUPABASE_ACCESS_TOKEN=...")
    m = re.search(r"^SUPABASE_ACCESS_TOKEN\s*=\s*(.+)$", env.read_text(encoding="utf-8"), re.M)
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
        # WAF-friendly UA — Cloudflare may 403 the default urllib agent.
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


def main():
    print(f"target: {REF} (token loaded, anon key loaded)")
    print(f"migration: {MIGRATION.name}")

    # 0. Pre-clean any leftover test rows from a previous interrupted run.
    #    By mobile only: the number is a clearly-fake test constant, and a
    #    row renamed by step 6 would otherwise survive a name-scoped delete.
    mgmt(f"delete from public.users where mobile = '{TEST_MOBILE}';")

    print("\n── before: policies on public.users ──")
    st, rows = mgmt(
        "select policyname, cmd, roles from pg_policies "
        "where schemaname='public' and tablename='users' order by policyname;"
    )
    print(rows if st in (200, 201) else f"HTTP {st}: {rows}")

    # 1. Apply the migration
    print("\n── applying migration ──")
    sql = MIGRATION.read_text(encoding="utf-8")
    st, body = mgmt(sql)
    if st not in (200, 201):
        sys.exit(f"error: migration failed (HTTP {st}): {body}")
    print(f"  applied (HTTP {st})")

    print("\n── after: policies on public.users ──")
    st, rows = mgmt(
        "select policyname, cmd, roles from pg_policies "
        "where schemaname='public' and tablename='users' order by policyname;"
    )
    print(rows if st in (200, 201) else f"HTTP {st}: {rows}")
    names = [r.get("policyname") for r in rows] if isinstance(rows, list) else []
    policy_ok = (
        "anon_can_select_users" not in names
        and "anon_can_insert_users" not in names
        and "anon_can_update_users" not in names
        and "users_select_own_row" in names
        and "users_insert_own_row" in names
        and "users_update_own_row" in names
    )
    if not check("old permissive policies gone, scoped policies present", policy_ok, ", ".join(names)):
        sys.exit("error: policy swap did not happen as expected — aborting before REST checks")

    results = []

    # 2. SELECT without header → RLS hides everything
    st, body = rest("GET", "/users?select=mobile", prefer="")
    results.append(check(
        "anon SELECT (no header) returns no rows",
        st == 200 and isinstance(body, list) and len(body) == 0,
        f"HTTP {st}, rows={len(body) if isinstance(body, list) else body}",
    ))

    # 3. INSERT without header → rejected by WITH CHECK
    st, body = rest("POST", "/users", {"name": TEST_NAME, "mobile": TEST_MOBILE})
    denied = st == 403 or "row-level security" in str(body).lower() or "policy" in str(body).lower()
    results.append(check(
        "anon INSERT (no header) rejected",
        denied,
        f"HTTP {st}: {str(body)[:120]}",
    ))

    # 4. INSERT with x-user-mobile header → succeeds
    st, body = rest(
        "POST", "/users", {"name": TEST_NAME, "mobile": TEST_MOBILE},
        headers={"x-user-mobile": TEST_MOBILE},
    )
    user_id = body[0]["id"] if isinstance(body, list) and body and "id" in body[0] else None
    results.append(check(
        "anon INSERT with x-user-mobile succeeds",
        st in (200, 201) and user_id is not None,
        f"HTTP {st}, id={user_id}",
    ))
    if not user_id:
        sys.exit("error: could not create the test row — aborting")

    # 5. UPDATE without x-user-id → 0 rows affected
    st, body = rest("PATCH", f"/users?id=eq.{user_id}", {"name": "Hacked"})
    zero = (st == 200 and isinstance(body, list) and len(body) == 0) or st == 403
    results.append(check(
        "anon UPDATE (no x-user-id) affects 0 rows",
        zero,
        f"HTTP {st}, affected={len(body) if isinstance(body, list) else body}",
    ))

    # 6. UPDATE with x-user-id + x-user-mobile headers (own row) → succeeds.
    #    ⚠️ BOTH headers are REQUIRED — verified against the live project:
    #    with only x-user-id (what the app used to send) PostgREST silently
    #    affects 0 rows (HTTP 200, name unchanged) because supabase-dart
    #    requests `return=representation`, and PostgREST materializes the
    #    affected row through the SELECT policy. The mobile header makes
    #    the row visible to the response AND the update land.
    st, body = rest("PATCH", f"/users?id=eq.{user_id}", {"name": "RLS Verify Updated"},
                    headers={"x-user-id": user_id, "x-user-mobile": TEST_MOBILE})
    results.append(check(
        "anon UPDATE with x-user-id (own row) succeeds",
        st in (200, 201) and isinstance(body, list) and len(body) == 1,
        f"HTTP {st}",
    ))

    # 6b. Prove the update actually landed: SELECT with x-user-mobile shows
    #     the new name (also exercises the header-scoped SELECT again).
    st, body = rest("GET", f"/users?select=name&mobile=eq.{TEST_MOBILE}", prefer="",
                    headers={"x-user-mobile": TEST_MOBILE})
    updated_name = body[0]["name"] if isinstance(body, list) and body else None
    results.append(check(
        "updated row visible with new name",
        st == 200 and updated_name == "RLS Verify Updated",
        f"HTTP {st}, name={updated_name}",
    ))

    # 7. SELECT with x-user-mobile → own row visible
    st, body = rest("GET", f"/users?select=mobile,name&mobile=eq.{TEST_MOBILE}", prefer="",
                    headers={"x-user-mobile": TEST_MOBILE})
    results.append(check(
        "anon SELECT with x-user-mobile sees own row",
        st == 200 and isinstance(body, list) and len(body) == 1,
        f"HTTP {st}, rows={len(body) if isinstance(body, list) else 0}",
    ))

    print("\n── cleanup test rows ──")
    # Delete by the captured user id (exact — survives the step-6 rename),
    # then sweep by the fake test mobile for any older leaked rows, and
    # finally verify nothing remains.
    st, _ = mgmt(f"delete from public.users where id = '{user_id}';")
    st, _ = mgmt(f"delete from public.users where mobile = '{TEST_MOBILE}';")
    st, rows = mgmt(
        f"select count(*) as n from public.users where mobile = '{TEST_MOBILE}';"
    )
    n = rows[0].get("n") if isinstance(rows, list) and rows else None
    print(f"  deleted; rows remaining for test mobile: {n} (HTTP {st})")
    if st not in (200, 201) or n not in (None, 0):
        sys.exit("error: test rows still present after cleanup (or count query failed)")

    failed = [r for r in results if not r]
    print("")
    if failed:
        sys.exit(f"❌ {len(failed)} check(s) FAILED")
    print("✅ all RLS checks passed — users table tightened and anon-key app scoping works")


if __name__ == "__main__":
    main()
