#!/usr/bin/env python3
"""
DrsListing — Deploy the Google Places proxy Edge Function.

The Flutter web build calls maps.googleapis.com directly, which the browser
blocks with CORS. The `places-proxy` function relays those calls server-side
with the API key injected from its secret, so the browser only ever talks to
*.supabase.co/functions/v1/places-proxy (no CORS block, key stays off the web).

Usage:
    python supabase/deploy_places_proxy.py             # deploy + secret
    python supabase/deploy_places_proxy.py --key <k>   # override the key
    python supabase/deploy_places_proxy.py --project-ref <ref>

The GOOGLE_MAPS_API_KEY is read from .env (the app's own key) — it must be
the same key the app uses, since the proxy calls Google with it.
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

FUNCTION_SLUG = "places-proxy"
FUNCTION_FILE = "supabase/functions/places-proxy/index.ts"


def load_deploy_env() -> None:
    """Load SUPABASE_ACCESS_TOKEN (+ friends) from .env.deploy into env.

    Needed for the CLI subprocess, which reads SUPABASE_ACCESS_TOKEN from
    the environment rather than the file.
    """
    env_path = os.path.join(
        os.path.dirname(os.path.abspath(__file__)), "..", ".env.deploy"
    )
    try:
        with open(env_path, encoding="utf-8") as f:
            for line in f:
                s = line.strip()
                if not s or s.startswith("#") or "=" not in s:
                    continue
                k, _, v = s.partition("=")
                k = k.strip()
                if not k or k in os.environ:
                    continue
                v = v.strip()
                if v.startswith('"') and v.endswith('"'):
                    v = v[1:-1]
                os.environ[k] = v
    except OSError:
        pass


def load_env():
    """Load GOOGLE_MAPS_API_KEY from .env (the app's runtime key file)."""
    env_path = os.path.join(
        os.path.dirname(os.path.abspath(__file__)), "..", ".env"
    )
    try:
        with open(env_path, encoding="utf-8") as f:
            for line in f:
                s = line.strip()
                if not s or s.startswith("#") or "=" not in s:
                    continue
                k, _, v = s.partition("=")
                k, v = k.strip(), v.strip()
                if k == "GOOGLE_MAPS_API_KEY" and v:
                    return v
    except OSError:
        pass
    return ""


def api(method: str, path: str, body=None):
    token = os.environ.get("SUPABASE_ACCESS_TOKEN", "").strip()
    if not token:
        sys.exit(
            "ERROR: SUPABASE_ACCESS_TOKEN is not set.\n"
            "Create one at https://supabase.com/dashboard/account/tokens "
            "and save it in .env.deploy or export it."
        )
    url = f"https://api.supabase.com/v1/projects/{PROJECT_REF}" + path
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(
        url, data=data, method=method,
        headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json",
                 "User-Agent": "curl/8.5.0 (DrsListing places-proxy deploy)"},
    )
    try:
        with urllib.request.urlopen(req, timeout=45) as resp:
            raw = resp.read().decode()
            return resp.status, (json.loads(raw) if raw.strip() else None)
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

    api_key = ""
    if "--key" in sys.argv:
        idx = sys.argv.index("--key")
        api_key = sys.argv[idx + 1] if idx + 1 < len(sys.argv) else ""
    if not api_key:
        api_key = os.environ.get("GOOGLE_MAPS_API_KEY", "").strip()
    if not api_key:
        api_key = load_env()

    print("== DrsListing places-proxy deploy ==")
    print(f"  project ref: {PROJECT_REF}")
    if not api_key:
        sys.exit("ERROR: GOOGLE_MAPS_API_KEY not found (.env or --key).")
    print(f"  GOOGLE_MAPS_API_KEY: present ({len(api_key)} chars)")

    # ── 1. Deploy the function (CLI preferred, no-verify-jwt as usual) ──
    print("\n[1/2] Deploying places-proxy Edge Function...")
    cli = shutil.which("supabase")
    if cli:
        if cli.lower().endswith((".cmd", ".bat")):
            cmd = ["cmd.exe", "/c", cli]
        else:
            cmd = [cli]
        proc = subprocess.run(
            [*cmd, "functions", "deploy", FUNCTION_SLUG, "--use-api",
             "--no-verify-jwt", "--project-ref", PROJECT_REF],
            capture_output=True, encoding="utf-8", errors="replace", timeout=300,
        )
        print(proc.stdout or "")
        if proc.stderr:
            print(proc.stderr)
        if proc.returncode != 0:
            sys.exit("  ! CLI deploy failed — aborting.")
        print("  -> places-proxy deployed via Supabase CLI.")
    else:
        print("  ! WARNING: supabase CLI not found — Management API body deploy.")
        with open(FUNCTION_FILE, encoding="utf-8") as f:
            code = f.read()
        status, resp = api("POST", "/functions", {
            "slug": FUNCTION_SLUG, "name": FUNCTION_SLUG, "verify_jwt": False,
            "entrypoint_path": "index.ts", "body": code,
        })
        print(f"  -> {status}: {resp}")
        if status == 409:
            print("  -> already exists — treating as OK.")
        elif status not in (200, 201):
            sys.exit(f"  ! deploy failed ({status}) — aborting.")

    # ── 2. Set the API-key secret ──────────────────────────────────
    print("\n[2/2] Setting GOOGLE_MAPS_API_KEY secret...")
    status, resp = api("POST", "/secrets", [
        {"name": "GOOGLE_MAPS_API_KEY", "value": api_key},
    ])
    print(f"  -> {status}: {resp if status != 201 else 'OK'}")
    if status != 201:
        sys.exit("  ! Secret set failed — aborting.")

    # ── 3. Smoke-test the live proxy ───────────────────────────────
    print("\nSmoke-testing live places-proxy...")
    base = f"https://{PROJECT_REF}.supabase.co/functions/v1/places-proxy"
    for label, path in [
        ("textsearch", "/textsearch/json?query=clinic&location=28.6,77.2&radius=5000"),
        ("details (invalid id, still a proxied response)", "/details/json?place_id=nonexistent"),
    ]:
        try:
            req = urllib.request.Request(base + path, method="GET",
                headers={"User-Agent": "curl/8.5.0 (DrsListing places-proxy check)"})
            with urllib.request.urlopen(req, timeout=20) as r:
                body = r.read().decode(errors="replace")
                print(f"  -> {label}: HTTP {r.status} | CORS {r.headers.get('Access-Control-Allow-Origin')} | {body[:120]}")
        except urllib.error.HTTPError as e:
            body = e.read().decode(errors="replace")
            print(f"  -> {label}: HTTP {e.code} | CORS {e.headers.get('Access-Control-Allow-Origin')} | {body[:120]}")

    print("\nSUCCESS: places-proxy deployed with the API key.")


if __name__ == "__main__":
    main()
