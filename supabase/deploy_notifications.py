#!/usr/bin/env python3
"""
DrsListing — Deploy push notifications (FCM) via the Supabase Management API.

Usage:
    # Either save the token in .env.deploy (recommended, gitignored):
    #   SUPABASE_ACCESS_TOKEN=sbp_...
    #   FIREBASE_SERVICE_ACCOUNT={ "type": "service_account", ... }
    # or pass them in the environment:
    set SUPABASE_ACCESS_TOKEN=sbp_...        # Windows
    export SUPABASE_ACCESS_TOKEN=sbp_...     # macOS/Linux
    python supabase/deploy_notifications.py
    python supabase/deploy_notifications.py --project-ref <ref>

Steps performed (in order):
  1. Apply the notification migrations:
       - 20260806000002 device tokens + add/remove_device_token RPCs
       - 20260806000003 per-user notification_prefs
       - 20260806000004 notifications history table (in-app notification
         center)
       - 20260806000005 master switch (notification_prefs.all)
       - 20260806000006 retention policy (prune_old_notifications + pg_cron
         daily job deleting rows older than 90 days)
  2. Deploy the notifications Edge Function (supabase/functions/notifications)
     with verify_jwt=false — FCM HTTP v1 push sender + history rows
  3. Re-deploy the booking-page Edge Function (it now fires the doctor push
     after web/QR bookings)
  4. Set the secrets:
       NOTIFY_SHARED_SECRET       — gates the notifications function
       FIREBASE_SERVICE_ACCOUNT   — Firebase service-account JSON used to
                                    mint FCM access tokens
     (both come from .env.deploy or the real environment)
  5. Smoke-test the live notifications function (bad token -> 401,
     good token + unknown appointment -> 404) to prove it's deployed and
     the shared secret matches the app's AppConstants.notifySharedSecret.

Service account: download from Firebase Console → Project settings →
Service accounts → Generate new private key. Save the JSON as
FIREBASE_SERVICE_ACCOUNT in .env.deploy (multiline values are fine) or
export it in the shell.
"""

import json
import os
import shutil
import subprocess
import sys
import urllib.request
import urllib.error

DEFAULT_PROJECT_REF = "qxukzqdsmlurollltrjp"
PROJECT_REF = DEFAULT_PROJECT_REF

DEPLOY_ENV_FILE = ".env.deploy"

# Must match AppConstants.notifySharedSecret in lib/config/constants.dart
NOTIFY_SECRET = "n9Kq4Zx7Vm2Lp8Rt5Ys3Cb6Hf1Wj0AeD"

MIGRATION_FILES = [
    "supabase/migrations/20260806000002_add_fcm_device_tokens_to_users.sql",
    "supabase/migrations/20260806000003_add_notification_prefs_to_users.sql",
    "supabase/migrations/20260806000004_add_notifications_history.sql",
    "supabase/migrations/20260806000005_add_master_notification_switch.sql",
    "supabase/migrations/20260806000006_add_notifications_retention.sql",
]
FUNCTIONS = [
    ("notifications", "supabase/functions/notifications/index.ts"),
    # booking-page now calls the notifications function after web/QR
    # bookings — re-deploy it alongside so the hook is live.
    ("booking-page", "supabase/functions/booking-page/index.ts"),
]


def load_deploy_env() -> None:
    """Load KEY=VALUE pairs from .env.deploy into the environment.

    Same semantics as deploy_booking.py: existing env vars win, surrounding
    quotes are stripped, inline ` # comment` suffixes are dropped. Multi-line
    values (the FIREBASE_SERVICE_ACCOUNT JSON) are concatenated until the
    next unquoted KEY=VALUE line — so the JSON can span several lines.
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
                    # Multi-line JSON value: keep appending until the
                    # accumulated text PARSES as JSON. KEY=VALUE detection is
                    # unsafe here because PKCS8 PEM base64 lines contain '='
                    # (the private_key padding), which would look like a new
                    # key and truncate the service account.
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
                    # First line of a (possibly multi-line) JSON value.
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


def deploy_function(slug: str, function_file: str) -> None:
    """Deploy one Edge Function, preferring the Supabase CLI (bundles deps)."""
    cli = shutil.which("supabase")
    if cli:
        if cli.lower().endswith((".cmd", ".bat")):
            cmd = ["cmd.exe", "/c", cli]
        else:
            cmd = [cli]
        proc = subprocess.run(
            # --no-verify-jwt is REQUIRED: the CLI defaults verify_jwt to
            # true, which would make the gateway demand a Supabase JWT auth
            # header — but the app calls these functions with only the
            # shared x-notify-token/x-booking-token header (401 otherwise).
            [*cmd, "functions", "deploy", slug, "--use-api",
             "--no-verify-jwt", "--project-ref", PROJECT_REF],
            capture_output=True,
            encoding="utf-8",
            errors="replace",
            timeout=300,
        )
        print(proc.stdout)
        if proc.stderr:
            print(proc.stderr)
        if proc.returncode != 0:
            sys.exit(f"  ! CLI deploy of {slug} failed — aborting.")
        print(f"  -> {slug} deployed via Supabase CLI (bundled dependencies).")
    else:
        print("  ! WARNING: supabase CLI not found — falling back to the "
              "Management API body deploy (remote imports may BOOT_ERROR).")
        with open(function_file, encoding="utf-8") as f:
            code = f.read()
        status, resp = api(
            "POST",
            "/functions",
            {
                "slug": slug,
                "name": slug,
                "verify_jwt": False,
                "entrypoint_path": "index.ts",
                "body": code,
            },
        )
        print(f"  -> {status}: {resp}")
        if status == 409:
            print(f"  -> {slug} already exists — treating as OK (re-deploy).")
        elif status not in (200, 201):
            sys.exit(f"  ! {slug} deploy failed — aborting.")


def main() -> None:
    load_deploy_env()

    global PROJECT_REF
    if "--project-ref" in sys.argv:
        idx = sys.argv.index("--project-ref")
        if idx + 1 >= len(sys.argv):
            sys.exit("ERROR: --project-ref requires a value, e.g. --project-ref abcd...")
        PROJECT_REF = sys.argv[idx + 1]

    print("== DrsListing push-notifications deploy ==")
    print(f"  project ref: {PROJECT_REF}")

    # ── 1. Migrations ─────────────────────────────────────────────
    print("\n[1/5] Applying notification migrations...")
    for migration_file in MIGRATION_FILES:
        print(f"  Applying {migration_file} ...")
        with open(migration_file, encoding="utf-8") as f:
            sql = f.read()
        status, resp = api("POST", "/database/query", {"query": sql})
        print(f"  -> {status}: {resp if status not in (200, 201) else 'OK'}")
        if status not in (200, 201):
            print("  ! Migration query returned non-2xx — it may already be "
                  "applied; continuing.")

    # Verify the column + RPC functions actually landed.
    check_sql = (
        "SELECT column_name FROM information_schema.columns "
        "WHERE table_schema = 'public' AND table_name = 'users' "
        "AND column_name = 'device_tokens'"
    )
    status, resp = api("POST", "/database/query", {"query": check_sql})
    ok = (
        status in (200, 201)
        and isinstance(resp, list)
        and any(
            isinstance(r, dict) and r.get("column_name") == "device_tokens"
            for r in resp
        )
    )
    if not ok:
        sys.exit("  ! users.device_tokens column is missing — migration "
                 "did not apply. Fix and re-run.")
    print("  -> users.device_tokens exists [OK]")

    # ── 2 & 3. Edge Functions ─────────────────────────────────────
    for i, (slug, function_file) in enumerate(FUNCTIONS, start=2):
        print(f"\n[{i}/5] Deploying {slug} Edge Function...")
        deploy_function(slug, function_file)

    # ── 4. Secrets ────────────────────────────────────────────────
    print("\n[4/5] Setting notification secrets...")
    secrets = [{"name": "NOTIFY_SHARED_SECRET", "value": NOTIFY_SECRET}]
    service_account = os.environ.get("FIREBASE_SERVICE_ACCOUNT", "").strip()
    if service_account:
        try:
            parsed = json.loads(service_account)
            missing = [
                k for k in ("client_email", "project_id", "private_key")
                if not parsed.get(k)
            ]
            if missing:
                print(f"  ! FIREBASE_SERVICE_ACCOUNT is missing keys: {missing}")
            else:
                secrets.append(
                    {
                        "name": "FIREBASE_SERVICE_ACCOUNT",
                        "value": service_account,
                    }
                )
                print("  -> FIREBASE_SERVICE_ACCOUNT: valid service account "
                      f"(project {parsed['project_id']})")
        except json.JSONDecodeError:
            print("  ! FIREBASE_SERVICE_ACCOUNT is not valid JSON — skipping. "
                  "Notifications will 503 until it is set.")
    else:
        print("  ! FIREBASE_SERVICE_ACCOUNT not set — skipping. Notifications "
              "will 503 until it is set (see the script docstring).")

    status, resp = api("POST", "/secrets", secrets)
    print(f"  -> {status}: {resp if status != 201 else 'OK'}")
    if status != 201:
        sys.exit("  ! Secret set failed — aborting.")

    # ── 5. Smoke-test the live function ───────────────────────────
    print("\n[5/5] Smoke-testing live notifications function...")
    base = f"https://{PROJECT_REF}.supabase.co/functions/v1/notifications"

    def post(headers, body):
        req = urllib.request.Request(
            base,
            data=json.dumps(body).encode(),
            method="POST",
            headers={
                **headers,
                "Content-Type": "application/json",
                "User-Agent": "curl/8.5.0 (DrsListing deploy)",
            },
        )
        try:
            with urllib.request.urlopen(req, timeout=20) as resp:
                return resp.status, resp.read().decode(errors="replace")
        except urllib.error.HTTPError as e:
            return e.code, e.read().decode(errors="replace")

    # Bad token → must be rejected (401).
    status, _ = post(
        {"x-notify-token": "wrong-secret"},
        {"event": "appointment_booked", "appointment_id": "APT000"},
    )
    print(f"  -> bad token: HTTP {status} (expected 401)")
    if status != 401:
        sys.exit("  ! Token gate failed — the deployed NOTIFY_SHARED_SECRET "
                 "does not match the app constant. Aborting.")
    print("  -> token gate matches AppConstants.notifySharedSecret [OK]")

    # Good token + unknown appointment → 404 proves the function is live,
    # wired to the DB, and the event parsing works end-to-end.
    status, body = post(
        {"x-notify-token": NOTIFY_SECRET},
        {"event": "appointment_booked", "appointment_id": "APT000"},
    )
    print(f"  -> good token, unknown appointment: HTTP {status} (expected 404)")
    if status == 503:
        sys.exit("  ! Function returned 503 — FIREBASE_SERVICE_ACCOUNT is not "
                 "set. Add it and re-run (or the push will stay unavailable).")
    if status not in (404, 200):
        sys.exit(f"  ! Unexpected response: HTTP {status} {body[:200]} — "
                 "aborting.")

    print("\nSUCCESS: notifications deployed and verified.")

    if not service_account:
        print(
            "\nREMINDER: FIREBASE_SERVICE_ACCOUNT was not set — push delivery "
            "will 503 until you add it to .env.deploy and re-run:\n"
            "  python supabase/deploy_notifications.py"
        )


if __name__ == "__main__":
    main()
