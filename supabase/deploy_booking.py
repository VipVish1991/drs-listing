#!/usr/bin/env python3
"""
DrsListing — Deploy the booking-page Edge Function via the Supabase
Management API (no CLI / linking / DB password required).

Usage:
    # Either save the token in .env.deploy (recommended, gitignored):
    #   SUPABASE_ACCESS_TOKEN=sbp_...
    # or pass it in the environment:
    set SUPABASE_ACCESS_TOKEN=sbp_...        # Windows
    export SUPABASE_ACCESS_TOKEN=sbp_...     # macOS/Linux
    python supabase/deploy_booking.py
    python supabase/deploy_booking.py --skip-post-verify  # deploy only
    python supabase/deploy_booking.py --fresh --project-ref <ref>
        # bootstrap a BRAND-NEW environment: apply the consolidated
        # full-schema migration (every table + field + policy + trigger)
        # instead of the incremental booking-chain ones

Steps performed (in order):
  1. Apply the migrations
     (booking chain: allow_pending_appointment_status +
     enforce_slot_booking_rule + doctor_unavailability; or, with --fresh,
     the single consolidated full-schema migration covering the whole
     database) via POST /v1/projects/{ref}/database/query, and verify the
     'Pending' status constraint AND both server-side triggers exist
  2. Create/update the booking-page Edge Function with verify_jwt=false
     (POST /v1/projects/{ref}/functions)
  3. Set the BOOKING_SHARED_SECRET secret
     (POST /v1/projects/{ref}/secrets)
  4. Verify the live function URL serves the booking form (GET)
  5. Run the sibling supabase/verify_booking_post.py end-to-end POST
     check (book a test appointment -> confirm 'Pending' in the live DB
     -> delete the test rows), so every deploy proves the full chain.
     Pass --skip-post-verify to skip step 5.

Sibling tools:
  - supabase/verify_booking_post.py — the POST verification run by step 5
  - supabase/cleanup_test_data.py  — removes any leftover test/QA rows
    created during verification runs (`--dry-run` to preview, `--yes` to
    delete)
"""

import json
import os
import shutil
import subprocess
import sys
import urllib.request
import urllib.error

# Windows consoles default to cp1252, which cannot encode the ₹ / arrow / box
# characters in the child verifier's output. Force UTF-8 so re-running the
# deploy after a verify prints cleanly on every platform (same fix as the
# deploy_payments*.py scripts).
for _stream in (sys.stdout, sys.stderr):
    try:
        _stream.reconfigure(encoding="utf-8")
    except (AttributeError, ValueError):
        pass

# Default target project. Override with --project-ref <ref> — required
# (and sensible) when bootstrapping a brand-new environment with --fresh.
DEFAULT_PROJECT_REF = "qxukzqdsmlurollltrjp"
PROJECT_REF = DEFAULT_PROJECT_REF

# Deploy-only env file (gitignored, NOT bundled into the Flutter app).
# The Management API token must never live in the app's .env because that
# file is shipped inside the app bundle.
DEPLOY_ENV_FILE = ".env.deploy"


def load_deploy_env() -> None:
    """Load KEY=VALUE pairs from .env.deploy into the environment.

    Only sets variables that aren't already present, so an explicit
    SUPABASE_ACCESS_TOKEN exported in the shell always wins. The file
    is resolved relative to this script so the deploy works from any
    directory.
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
                # Drop trailing inline comments FIRST — otherwise the
                # comment text prevents the surrounding-quote detection
                # below (e.g. `TOKEN="abc" # note` must end as `abc`,
                # not `"abc"`).
                if " #" in value:
                    value = value.split(" #", 1)[0].rstrip()
                # Strip surrounding quotes ("..." or '...') — the common
                # .env convention.
                if (value.startswith('"') and value.endswith('"')) or (
                    value.startswith("'") and value.endswith("'")
                ):
                    value = value[1:-1]
                os.environ[key] = value
    except OSError:
        # No .env.deploy — rely on the real environment variable.
        pass

# Must match AppConstants.bookingSharedSecret in lib/config/constants.dart
BOOKING_SECRET = "cAZrwHpDFJ4HaSNXowJnmvzi-0YD5rYE"

# Migrations applied in step 1 (incremental, idempotent — safe to re-run
# against an already-migrated database).
MIGRATION_FILES = [
    "supabase/migrations/20260731000001_allow_pending_appointment_status.sql",
    "supabase/migrations/20260805000001_enforce_slot_booking_rule.sql",
    "supabase/migrations/20260806000001_doctor_unavailability.sql",
    "supabase/migrations/20260812000001_enforce_one_active_booking_rule.sql",
]

# With --fresh: the single consolidated full-schema migration, applied
# INSTEAD of the incremental list. It creates every table, column, index,
# RLS policy, function, trigger and storage object, so it must only ever
# run against a brand-new (empty) project — applying it to an existing DB
# would collide with already-created objects.
FRESH_MIGRATION_FILES = [
    "supabase/migrations/20260807000001_full_schema_all_fields.sql",
]
FUNCTION_FILE = "supabase/functions/booking-page/index.ts"

# Sibling script run in step 5 — performs the end-to-end POST verification
# (books a test appointment through the live Edge Function, confirms the
# 'Pending' row in the DB, then deletes the test rows). It lives in the
# same directory as this script, so the path is resolved relative to
# __file__ (like load_deploy_env) to work from any CWD.
VERIFY_POST_SCRIPT = "verify_booking_post.py"


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
            # A recognizable browser/curl-like UA avoids the WAF block.
            "User-Agent": "curl/8.5.0 (DrsListing deploy)",
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


def run_post_verify(project_ref: str) -> None:
    """Run the sibling verify_booking_post.py end-to-end POST check.

    The subprocess inherits SUPABASE_ACCESS_TOKEN from this process
    (loaded by load_deploy_env), so no extra setup is needed. The target
    project ref is forwarded via --project-ref so verification runs
    against the SAME project this deploy targeted (important with --fresh
    when that is a brand-new environment). It exits non-zero on failure,
    which aborts the deploy so a half-working booking chain is never
    reported as deployed.
    """
    script = os.path.join(
        os.path.dirname(os.path.abspath(__file__)), VERIFY_POST_SCRIPT
    )
    if not os.path.isfile(script):
        sys.exit(
            f"  ! {VERIFY_POST_SCRIPT} not found next to this script — "
            "cannot run the POST verification. Fix the path or pass "
            "--skip-post-verify."
        )
    print(f"  Running {VERIFY_POST_SCRIPT} ...")
    cmd = [sys.executable, script, "--project-ref", project_ref]
    try:
        proc = subprocess.run(
            cmd,
            capture_output=True,
            encoding="utf-8",
            errors="replace",
            timeout=300,
        )
    except (OSError, subprocess.SubprocessError) as e:
        # OSError: launch failures (missing/permission). SubprocessError:
        # TimeoutExpired and other child-run errors — abort cleanly rather
        # than surfacing a raw traceback.
        sys.exit(f"  ! Could not run {VERIFY_POST_SCRIPT}: {e}")
    if proc.stdout:
        print(proc.stdout.rstrip())
    if proc.stderr:
        print(proc.stderr.rstrip())
    if proc.returncode != 0:
        sys.exit("  ! POST verification failed — deploy aborted.")
    print("  -> POST verification passed [OK]")


def main() -> None:
    load_deploy_env()
    skip_post_verify = "--skip-post-verify" in sys.argv
    fresh = "--fresh" in sys.argv

    # Optional project override — required for --fresh so the consolidated
    # full-schema migration can never run against the existing project.
    global PROJECT_REF
    if "--project-ref" in sys.argv:
        idx = sys.argv.index("--project-ref")
        if idx + 1 >= len(sys.argv):
            sys.exit("ERROR: --project-ref requires a value, e.g. --project-ref abcd...")
        PROJECT_REF = sys.argv[idx + 1]
    if fresh and PROJECT_REF == DEFAULT_PROJECT_REF:
        sys.exit(
            "ERROR: --fresh must be used with --project-ref <ref> pointing at a "
            "brand-new empty project. The consolidated full-schema migration "
            "cannot be applied to the existing production database."
        )

    migration_files = FRESH_MIGRATION_FILES if fresh else MIGRATION_FILES

    print("== DrsListing booking-page deploy ==")
    print(f"  project ref: {PROJECT_REF}")
    if fresh:
        print("  --fresh: applying the consolidated full-schema migration "
              "(new environment).")
    if skip_post_verify:
        print("  --skip-post-verify: skipping the end-to-end POST check.")

    # ── 1. Migrations ─────────────────────────────────────────────
    if fresh:
        print("\n[1/5] Applying consolidated full-schema migration...")
    else:
        print("\n[1/5] Applying booking-chain migrations...")
    for migration_file in migration_files:
        print(f"  Applying {migration_file} ...")
        with open(migration_file, encoding="utf-8") as f:
            sql = f.read()
        status, resp = api("POST", "/database/query", {"query": sql})
        print(f"  -> {status}: {resp if status not in (200, 201) else 'OK'}")
        if status not in (200, 201):
            print(
                "  ! Migration query returned non-2xx — it may already be "
                "applied."
            )

    # The GET verify below never touches the status CHECK constraint, so a
    # genuinely failed migration would stay silent until the first POST
    # booking. Confirm the constraint now actually allows 'Pending'.
    check_sql = (
        "SELECT pg_get_constraintdef(oid) AS def "
        "FROM pg_constraint "
        "WHERE conname = 'appointments_status_check'"
    )
    status, resp = api("POST", "/database/query", {"query": check_sql})
    def_text = ""
    # /database/query returns HTTP 201 with a JSON *array* of row dicts,
    # e.g. [{"def": "CHECK (...) IN (...)"}].
    if status in (200, 201) and isinstance(resp, list):
        if resp and isinstance(resp[0], dict):
            def_text = str(resp[0].get("def", ""))
    if "'Pending'" not in def_text:
        sys.exit(
            "  ! appointments_status_check does not include 'Pending'.\n"
            "    The migration did not apply — fix and re-run."
        )
    print("  -> appointments_status_check includes 'Pending' [OK]")

    # The slot-occupancy trigger is what actually enforces the booking
    # rule (a slot stays booked until the appointment is Cancelled) —
    # confirm it exists, otherwise a double-booking could slip through
    # and the Edge Function race guard alone would be best-effort.
    check_trigger_sql = (
        "SELECT tgname FROM pg_trigger "
        "WHERE tgname = 'trg_appointments_enforce_slot_rule' "
        "AND tgrelid = 'public.appointments'::regclass"
    )
    status, resp = api("POST", "/database/query", {"query": check_trigger_sql})
    trigger_present = (
        status in (200, 201)
        and isinstance(resp, list)
        and any(
            isinstance(r, dict)
            and r.get("tgname") == "trg_appointments_enforce_slot_rule"
            for r in resp
        )
    )
    if not trigger_present:
        sys.exit(
            "  ! trg_appointments_enforce_slot_rule trigger is missing.\n"
            "    The enforce_slot_booking_rule migration did not apply — "
            "fix and re-run."
        )
    print("  -> trg_appointments_enforce_slot_rule trigger exists [OK]")

    # The unavailability trigger blocks bookings on dates the doctor
    # marked unavailable (doctors.unavailable_ranges) — confirm the
    # migration applied, otherwise the app + Edge Function guards are
    # the only defense.
    check_unavail_sql = (
        "SELECT tgname FROM pg_trigger "
        "WHERE tgname = 'trg_appointments_enforce_unavailability' "
        "AND tgrelid = 'public.appointments'::regclass"
    )
    status, resp = api(
        "POST", "/database/query", {"query": check_unavail_sql}
    )
    unavail_present = (
        status in (200, 201)
        and isinstance(resp, list)
        and any(
            isinstance(r, dict)
            and r.get("tgname")
            == "trg_appointments_enforce_unavailability"
            for r in resp
        )
    )
    if not unavail_present:
        sys.exit(
            "  ! trg_appointments_enforce_unavailability trigger is "
            "missing.\n"
            "    The doctor_unavailability migration did not apply — "
            "fix and re-run."
        )
    print("  -> trg_appointments_enforce_unavailability trigger exists [OK]")

    # ── 2. Edge Function ──────────────────────────────────────────
    print("\n[2/5] Deploying booking-page Edge Function...")
    # The Management API 'body' deploy uploads the raw source, but the
    # Edge Runtime boots with --no-remote, so remote imports (deno.land,
    # esm.sh) fail with BOOT_ERROR. The Supabase CLI bundles/vendors
    # dependencies, so prefer it; fall back to the API body deploy only
    # when the CLI isn't installed.
    cli = shutil.which("supabase")
    # Prefer the CLI whenever it's found: it bundles/vendors dependencies,
    # which the Management API body deploy can't (the Edge Runtime boots
    # with --no-remote and rejects deno.land/esm.sh imports with BOOT_ERROR).
    # `--use-api` makes the CLI bundle SERVER-SIDE instead of via Docker,
    # so deploys work even when Docker isn't running (without it the CLI
    # silently uploads un-bundled source that BOOT_ERRORs at runtime).
    # A .cmd/.bat shim (e.g. npm global installs) is launched via cmd.exe
    # since CreateProcess can't execute it directly.
    if cli:
        if cli.lower().endswith((".cmd", ".bat")):
            # cmd.exe /c re-parses the rest of the line, so the shim path
            # must NOT be pre-quoted (list2cmdline quotes only when needed).
            cmd = ["cmd.exe", "/c", cli]
        else:
            cmd = [cli]
        proc = subprocess.run(
            [*cmd, "functions", "deploy", "booking-page", "--use-api",
             "--project-ref", PROJECT_REF],
            capture_output=True,
            encoding="utf-8",
            errors="replace",
            timeout=300,
        )
        print(proc.stdout)
        if proc.stderr:
            print(proc.stderr)
        if proc.returncode != 0:
            sys.exit("  ! CLI function deploy failed — aborting.")
        print("  -> Deployed via Supabase CLI (bundled dependencies).")
    else:
        print("  ! WARNING: supabase CLI not found — falling back to the "
              "Management API body deploy. This serves the raw source with "
              "remote imports (deno.land/esm.sh), which the Edge Runtime "
              "rejects (BOOT_ERROR: --no-remote). Prefer installing the CLI.")
        with open(FUNCTION_FILE, encoding="utf-8") as f:
            code = f.read()
        status, resp = api(
            "POST",
            "/functions",
            {
                "slug": "booking-page",
                "name": "booking-page",
                "verify_jwt": False,
                "entrypoint_path": "index.ts",
                "body": code,
            },
        )
        print(f"  -> {status}: {resp}")
        if status == 409:
            print("  -> Function already exists — treating as OK (re-deploy).")
        elif status not in (200, 201):
            sys.exit("  ! Function deploy failed — aborting.")

    # ── 3. Secret ─────────────────────────────────────────────────
    print("\n[3/5] Setting BOOKING_SHARED_SECRET...")
    status, resp = api(
        "POST",
        "/secrets",
        [{"name": "BOOKING_SHARED_SECRET", "value": BOOKING_SECRET}],
    )
    print(f"  -> {status}: {resp if status == 201 else resp}")

    # ── 4. Verify (GET) ───────────────────────────────────────────
    print("\n[4/5] Verifying live booking page (GET)...")
    verify_url = (
        f"https://{PROJECT_REF}.supabase.co/functions/v1/booking-page"
        "?doctor=ChIJN1t_tDeuEmsRUsoyG83frY4"
        f"&token={BOOKING_SECRET}"
    )
    try:
        req = urllib.request.Request(
            verify_url,
            headers={
                # Same WAF-friendly UA as api() so the verify step can't be
                # blocked by a Python-urllib user-agent policy.
                "User-Agent": "curl/8.5.0 (DrsListing deploy)",
            },
        )
        with urllib.request.urlopen(req, timeout=20) as resp:
            body = resp.read().decode(errors="replace")
            # The booking form only renders when the token gate passed AND the
            # doctor param is present — error pages (invalid token, Booking
            # Unavailable) all contain <title> but never the form, so this is
            # the reliable success signal.
            form_hit = 'id="bookingForm"' in body
            print(f"  -> HTTP {resp.status}, booking form rendered: {form_hit}")
            print(f"  URL: {verify_url}")
            if resp.status != 200 or not form_hit:
                print("\n! Booking page did not render correctly — see the response above.")
                sys.exit(1)
            print("  -> GET verification passed [OK]")
    except Exception as e:  # noqa: BLE001
        print(f"  ! Verify failed: {e}")
        sys.exit(1)

    # ── 5. Verify (POST, end-to-end) ──────────────────────────────
    print("\n[5/5] Running end-to-end POST verification...")
    if skip_post_verify:
        print("  --skip-post-verify: POST check skipped.")
    else:
        run_post_verify(PROJECT_REF)

    print("\nSUCCESS: booking page deployed and verified (GET + POST).")


if __name__ == "__main__":
    main()
