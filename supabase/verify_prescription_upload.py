#!/usr/bin/env python3
"""
DrsListing — End-to-end smoke test for the prescription upload chain.

Simulates exactly what the doctor app does when marking a Tele/Video
consultation as Complete with a prescription photo:

  1. GET  action=slots     -> sanity check the doctor exists (availability).
  2. POST action=register  -> saves the patient (name + mobile) into users.
  3. POST action=book      -> books a concrete date+time slot (type=video,
                             the consultation type that unlocks the
                             prescription upload) as a 'Pending' appointment.
  4. POST action=prescription with the raw image bytes -> the Edge Function
     downscales to 2560px / q92 (with a light sharpen) and returns the
     public storage URL.
  5. UPDATE appointments.upload_prescription = ARRAY[url] — the write the
     app performs after the upload returns (TEXT[] column).
  6. SELECT the row back -> confirms the URL actually landed on the
     appointment record.
  7. GET the public URL   -> confirms the stored image is really fetchable
     (HTTP 200, image/jpeg) — the full round-trip storage read.
  8. Deletes the test appointment, the test user, AND the uploaded storage
     object(s), so the live project stays clean.

Before booking it also PRE-CLEANS any leftover marker-matching test rows
(previous failed/interrupted runs), so the script is idempotent.

Storage objects cannot be deleted via SQL (Supabase blocks direct DELETE on
storage.objects), so the script fetches the service_role key from the
Management API /api-keys endpoint and removes objects through the Storage
API DELETE endpoint instead.

Usage:
    python supabase/verify_prescription_upload.py --image <path-to-jpeg>
    python supabase/verify_prescription_upload.py --image x.jpg --keep
    python supabase/verify_prescription_upload.py --image x.jpg --doctor <placeId>

The SUPABASE_ACCESS_TOKEN is read from .env.deploy (recommended) or the
environment, exactly like verify_booking_post.py / cleanup_test_data.py.

To regenerate a realistic test photo (exercises the server-side 2560px
downscale) using the project's own `image` package:

    cat > _gen_test_jpeg.dart <<'EOF'
    import 'dart:io';
    import 'package:image/image.dart' as img;
    void main() {
      final im = img.Image(width: 3000, height: 2250);
      img.fill(im, color: img.ColorRgb8(198, 84, 68));
      for (var y = 250; y < 2000; y++) {
        for (var x = 1000; x < 2000; x++) { im.setPixelRgb(x, y, 255, 255, 255); }
      }
      File('_prescription_test.jpg').writeAsBytesSync(img.encodeJpg(im, quality: 85));
    }
    EOF
    dart run _gen_test_jpeg.dart && rm _gen_test_jpeg.dart
"""

import json
import os
import sys
import urllib.error
import urllib.request
from datetime import datetime, timezone, timedelta
from urllib.parse import quote

PROJECT_REF = "qxukzqdsmlurollltrjp"
BASE_URL = f"https://api.supabase.com/v1/projects/{PROJECT_REF}"
FUNCTION_URL = f"https://{PROJECT_REF}.supabase.co/functions/v1/booking-page"
STORAGE_URL = f"https://{PROJECT_REF}.supabase.co/storage/v1"

DEPLOY_ENV_FILE = ".env.deploy"

# Must match AppConstants.bookingSharedSecret in lib/config/constants.dart
# and the BOOKING_SHARED_SECRET secret set on the deployed function.
BOOKING_SECRET = "cAZrwHpDFJ4HaSNXowJnmvzi-0YD5rYE"

DEFAULT_DOCTOR_PLACE_ID = "ChIJN1t_tDeuEmsRUsoyG83frY4"

# Same test markers as verify_booking_post.py / cleanup_test_data.py, so a
# row left behind (e.g. via --keep) is still caught by cleanup_test_data.py.
TEST_NAME = "Test Patient QA"
TEST_MOBILE = "919876500123"
TEST_SYMPTOMS = "e2e verification — automated POST check"

TEST_DATE = (datetime.now(timezone(timedelta(hours=5, minutes=30))) + timedelta(days=1)).strftime("%Y-%m-%d")
TEST_TIMES = ["10:00 AM", "10:30 AM", "11:00 AM"]


def load_deploy_env() -> None:
    """Load KEY=VALUE pairs from .env.deploy into the environment."""
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


def management_api(method: str, path: str, body=None):
    """Call the Supabase Management API and return (status, json|text)."""
    token = os.environ.get("SUPABASE_ACCESS_TOKEN", "").strip()
    if not token:
        sys.exit(
            "ERROR: SUPABASE_ACCESS_TOKEN is not set.\n"
            f"Save it in {DEPLOY_ENV_FILE} or export it and re-run."
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
            "User-Agent": "curl/8.5.0 (DrsListing verify-prescription)",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
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
    status, resp = management_api("POST", "/database/query", {"query": sql})
    if status not in (200, 201):
        sys.exit(f"  ! Query failed ({status}): {resp}")
    return resp if isinstance(resp, list) else []


def service_role_key() -> str:
    """Fetch the project service_role key via the Management API."""
    status, resp = management_api("GET", "/api-keys")
    if status not in (200, 201) or not isinstance(resp, list):
        sys.exit(f"  ! Could not read project API keys ({status}): {resp}")
    for k in resp:
        if k.get("name") == "service_role":
            key = k.get("api_key") or k.get("secret_key") or ""
            if key:
                return key
    sys.exit("  ! service_role key not found in /api-keys response.")


def storage_delete(path: str, sr_key: str) -> int:
    """DELETE one storage object via the Storage API. Returns HTTP status."""
    # safe='/' keeps the path separators intact (the Storage API expects
    # real slashes, not %2F).
    url = f"{STORAGE_URL}/object/prescriptions/{quote(path, safe='/')}"
    req = urllib.request.Request(
        url,
        data=b"",
        method="DELETE",
        headers={
            "Authorization": f"Bearer {sr_key}",
            "apikey": sr_key,
            "User-Agent": "curl/8.5.0 (DrsListing verify-prescription)",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            resp.read()
            return resp.status
    except urllib.error.HTTPError as e:
        return e.code


def delete_appointment_objects(appointment_id: str, sr_key: str) -> int:
    """List + delete every storage object under <appointmentId>/ (SQL DELETE
    is blocked by Supabase storage, so objects go through the Storage API)."""
    rows = run_query(
        "SELECT name FROM storage.objects "
        "WHERE bucket_id = 'prescriptions' "
        f"AND name LIKE '{appointment_id}/%'"
    )
    removed = 0
    for r in rows:
        path = r.get("name")
        if not path:
            continue
        code = storage_delete(path, sr_key)
        print(f"    - deleted {path} (HTTP {code})")
        if code == 200:
            removed += 1
    return removed


def call_function(params: str, payload=None, raw_bytes=None, content_type=None):
    """Call the live Edge Function; GET when payload/raw_bytes is None, else POST.

    Pass raw_bytes for the image upload (Content-Type: image/jpeg).
    """
    url = f"{FUNCTION_URL}?{params}"
    headers = {"User-Agent": "curl/8.5.0 (DrsListing verify-prescription)"}
    data = None
    if raw_bytes is not None:
        data = raw_bytes
        headers["x-booking-token"] = BOOKING_SECRET
        headers["Content-Type"] = content_type or "image/jpeg"
    elif payload is not None:
        data = json.dumps(payload).encode()
        headers["x-booking-token"] = BOOKING_SECRET
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(url, data=data, method="POST" if data else "GET", headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
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


def fetch_public_url(url: str):
    """GET a public storage URL; return (status, content_type, byte_length)."""
    req = urllib.request.Request(url, method="GET", headers={
        "User-Agent": "curl/8.5.0 (DrsListing verify-prescription)",
    })
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            body = resp.read()
            return resp.status, resp.headers.get("Content-Type", ""), len(body)
    except urllib.error.HTTPError as e:
        return e.code, e.headers.get("Content-Type", ""), 0


def main() -> None:
    load_deploy_env()
    keep = "--keep" in sys.argv
    place_id = DEFAULT_DOCTOR_PLACE_ID
    if "--doctor" in sys.argv:
        idx = sys.argv.index("--doctor")
        if idx + 1 < len(sys.argv):
            place_id = sys.argv[idx + 1]

    image_path = None
    if "--image" in sys.argv:
        idx = sys.argv.index("--image")
        if idx + 1 < len(sys.argv):
            image_path = sys.argv[idx + 1]
    if not image_path or not os.path.isfile(image_path):
        sys.exit(
            "ERROR: --image <path> is required and must point to an existing "
            "JPEG file.\n"
            "Regenerate a realistic 2400x1800 test photo with the dart snippet "
            "in this script's docstring, then re-run."
        )

    with open(image_path, "rb") as f:
        image_bytes = f.read()
    print(f"  test image: {image_path} ({len(image_bytes)} bytes)")

    doctor_q = f"doctor={quote(place_id, safe='')}"

    print("== DrsListing prescription-upload smoke test ==")
    print(f"  doctor placeId: {place_id}")
    print(f"  test name:      {TEST_NAME}")
    print(f"  test mobile:    {TEST_MOBILE}")
    print(f"  test slots:     {TEST_DATE} {' / '.join(TEST_TIMES)}")
    if keep:
        print("  --keep: test rows + storage object will be left for cleanup.")

    if not os.environ.get("SUPABASE_ACCESS_TOKEN", "").strip():
        sys.exit(
            "ERROR: SUPABASE_ACCESS_TOKEN is not set.\n"
            f"Save it in {DEPLOY_ENV_FILE} or export it and re-run."
        )

    sr_key = service_role_key() if not keep else None

    # ── 0. Pre-clean leftover marker rows (idempotent re-runs) ────
    print("\n[0/9] Pre-cleaning leftover marker test data...")
    if keep:
        print("  --keep set — skipping pre-clean.")
    else:
        # Marker-guarded: name + our e2e symptom text, so a real booking
        # with the same name is never touched.
        leftover_appts = run_query(
            "SELECT appointment_id FROM public.appointments "
            f"WHERE patient_name = '{TEST_NAME}' "
            f"AND symptoms ILIKE '%e2e verification%'"
        )
        for a in leftover_appts:
            aid = a.get("appointment_id")
            if not aid:
                continue
            print(f"  - removing leftover appointment {aid}")
            run_query(f"DELETE FROM public.appointments WHERE appointment_id = '{aid}'")
            delete_appointment_objects(aid, sr_key)
        if leftover_appts:
            run_query(
                "DELETE FROM public.users "
                f"WHERE name = '{TEST_NAME}' AND mobile = '{TEST_MOBILE}' "
                "AND id NOT IN (SELECT user_id FROM public.appointments "
                "                 WHERE user_id IS NOT NULL)"
            )
        print(f"  -> cleaned {len(leftover_appts)} leftover appointment(s)")

    # ── 1. GET action=slots ──────────────────────────────────────
    print("\n[1/9] GET action=slots (availability JSON)...")
    status, slots = call_function(f"{doctor_q}&token={BOOKING_SECRET}&action=slots")
    if status != 200 or not isinstance(slots, dict) or not slots.get("ok"):
        print(f"  ! slots failed ({status}): {slots}")
        sys.exit(1)
    print(f"  -> ok: true, doctor rows: {len(slots.get('slots', []))}")

    # ── 2. POST action=register ──────────────────────────────────
    print("\n[2/9] POST action=register (save patient)...")
    status, reg = call_function(
        doctor_q, {"action": "register", "name": TEST_NAME, "mobile": TEST_MOBILE}
    )
    if status != 200 or not isinstance(reg, dict) or not reg.get("ok"):
        print(f"  ! register failed ({status}): {reg}")
        sys.exit(1)
    reg_user_id = str(reg.get("userId") or "")
    print(f"  -> ok: true, userId: {reg_user_id}")

    # ── 3. POST action=book (type=video) ─────────────────────────
    print("\n[3/9] POST action=book (video consultation)...")
    status, resp = None, None
    booked_time = None
    for t in TEST_TIMES:
        status, resp = call_function(
            doctor_q,
            {
                "action": "book",
                "name": TEST_NAME,
                "mobile": TEST_MOBILE,
                "description": TEST_SYMPTOMS,
                "date": TEST_DATE,
                "time": t,
                "type": "video",
            },
        )
        if status == 200 and isinstance(resp, dict) and resp.get("ok"):
            booked_time = t
            break
        err = (resp or {}).get("error", "") if isinstance(resp, dict) else ""
        print(f"  -> {t}: taken/refused ({err or status}) - trying next...")

    if booked_time is None:
        print("  ! All candidate slots taken - falling back to legacy book (today/Flexible).")
        status, resp = call_function(
            doctor_q,
            {"name": TEST_NAME, "mobile": TEST_MOBILE, "description": TEST_SYMPTOMS, "type": "video"},
        )

    if status != 200 or not isinstance(resp, dict) or not resp.get("ok"):
        print(f"  ! Booking failed ({status}): {resp}")
        sys.exit(1)
    appointment_id = str(resp.get("appointmentId", ""))
    print(f"  -> appointmentId: {appointment_id} ({resp.get('time')})")

    if not appointment_id:
        print("  ! Response missing appointmentId - cannot verify the chain.")
        sys.exit(1)

    # ── 4. POST action=prescription (raw image bytes) ────────────
    print("\n[4/9] POST action=prescription (upload photo)...")
    status, up = call_function(
        f"{doctor_q}&action=prescription&appointment={quote(appointment_id, safe='')}",
        raw_bytes=image_bytes,
        content_type="image/jpeg",
    )
    if status != 200 or not isinstance(up, dict) or not up.get("ok"):
        print(f"  ! prescription upload failed ({status}): {up}")
        sys.exit(1)
    url = str(up.get("url") or "")
    if not url:
        print("  ! Upload returned ok but no url.")
        sys.exit(1)
    print("  -> ok: true")
    print(f"  -> url: {url}")

    # ── 5. Write the URL onto the appointment (what the app does) ─
    print("\n[5/9] Writing url into appointments.upload_prescription (TEXT[])...")
    escaped_url = url.replace("'", "''").replace("\\", "\\\\")
    run_query(
        "UPDATE public.appointments "
        f"SET upload_prescription = ARRAY['{escaped_url}'] "
        f"WHERE appointment_id = '{appointment_id}'"
    )
    print("  -> update executed (array literal)")

    # ── 6. Confirm the field landed on the row ───────────────────
    print("\n[6/9] Confirming upload_prescription on the appointment row...")
    rows = run_query(
        "SELECT appointment_id, patient_name, consultation_type, status, "
        "upload_prescription FROM public.appointments "
        f"WHERE appointment_id = '{appointment_id}'"
    )
    if len(rows) != 1:
        print(f"  ! Expected 1 row for {appointment_id}, found {len(rows)}.")
        sys.exit(1)
    row = rows[0]
    raw_field = row.get("upload_prescription")
    # PostgREST returns TEXT[] as a JSON list (e.g. ['https://...']).
    if isinstance(raw_field, list):
        urls_in_field = [str(u) for u in raw_field if u]
        field_str = ", ".join(urls_in_field)
        in_field = url in urls_in_field
    else:
        field_str = str(raw_field or "")
        in_field = field_str == url
    print(f"  -> {row.get('appointment_id')}  {row.get('patient_name')}  "
          f"type={row.get('consultation_type')}  ({row.get('status')})")
    print(f"  -> upload_prescription: {field_str}")
    if not in_field:
        print("  ! Field does not contain the URL returned by the upload.")
        sys.exit(1)
    if row.get("status") != "Pending":
        print(f"  ! Expected status 'Pending', got '{row.get('status')}'.")
        sys.exit(1)
    print("  -> field contains the returned URL [OK]")

    # ── 7. Fetch the public URL (round-trip storage read) ────────
    print("\n[7/9] GET public URL (storage read)...")
    fstatus, fctype, flen = fetch_public_url(url)
    print(f"  -> HTTP {fstatus}, Content-Type: {fctype or '(none)'}, {flen} bytes")
    if fstatus != 200:
        print("  ! Public URL is not fetchable.")
        sys.exit(1)
    if not (fctype or "").startswith("image/"):
        print(f"  ! Expected image/* content type, got '{fctype}'.")
        sys.exit(1)
    if flen <= 0:
        print("  ! Public URL returned an empty body.")
        sys.exit(1)
    # The edge function re-encodes at quality 92 — the stored payload should
    # be noticeably smaller than a 120KB+ camera capture. Log, don't fail,
    # because small source photos legitimately pass through untouched.
    if flen < len(image_bytes):
        print(f"  -> server-side downscale confirmed: {len(image_bytes)} -> {flen} bytes")
    print("  -> public image fetchable [OK]")

    # ── 8. Clean up (unless --keep) ──────────────────────────────
    print("\n[8/9] Cleaning up the test booking + upload...")
    if keep:
        print("  --keep set - leaving rows + storage object for manual cleanup.")
    else:
        run_query(f"DELETE FROM public.appointments WHERE appointment_id = '{appointment_id}'")
        print("  -> deleted appointment [OK]")

        delete_appointment_objects(appointment_id, sr_key)
        print("  -> storage object(s) deleted via Storage API")

        run_query(
            "DELETE FROM public.users "
            f"WHERE name = '{TEST_NAME}' AND mobile = '{TEST_MOBILE}' "
            "AND id NOT IN (SELECT user_id FROM public.appointments "
            "                 WHERE user_id IS NOT NULL)"
        )
        print("  -> deleted test user [OK]")

    # ── Verify cleanup ───────────────────────────────────────────
    print("\n  Verifying cleanup...")
    remaining = run_query(
        "SELECT COUNT(*) AS c FROM public.appointments "
        f"WHERE appointment_id = '{appointment_id}'"
    )
    appt_count = int(remaining[0].get("c", 0)) if remaining else -1
    objs = run_query(
        "SELECT COUNT(*) AS c FROM storage.objects "
        "WHERE bucket_id = 'prescriptions' "
        f"AND name LIKE '{appointment_id}/%'"
    )
    obj_count = int(objs[0].get("c", 0)) if objs else -1
    users = run_query(
        "SELECT COUNT(*) AS c FROM public.users "
        f"WHERE name = '{TEST_NAME}' AND mobile = '{TEST_MOBILE}'"
    )
    user_count = int(users[0].get("c", 0)) if users else -1

    if keep:
        if appt_count != 1 or obj_count != 1 or user_count != 1:
            print("  ! Expected kept rows (1 appt / 1 object / 1 user) - inspect manually.")
            sys.exit(1)
        print("  -> kept rows present [OK] (removable via cleanup_test_data.py --yes + Storage API)")
        print("\nSUCCESS: prescription chain verified end-to-end (test data kept).")
    else:
        if appt_count != 0:
            print(f"  ! Appointment still present ({appt_count} row(s)).")
            sys.exit(1)
        if obj_count != 0:
            print(f"  ! Storage object(s) still present ({obj_count}).")
            sys.exit(1)
        if user_count != 0:
            print(f"  ! Test user still present ({user_count} row(s)) - "
                  "likely a protected user with real appointments; inspect manually.")
            sys.exit(1)
        print("  -> appointment removed [OK]")
        print("  -> storage object(s) removed [OK]")
        print("  -> test user removed [OK]")
        print("\nSUCCESS: prescription upload chain verified end-to-end and cleaned up.")


if __name__ == "__main__":
    main()
