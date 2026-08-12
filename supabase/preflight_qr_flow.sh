#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════
# DrsListing — QR-flow pre-flight check (curl-based).
#
# Verifies the whole QR → booking chain after every deploy:
#
#   1. Static booking page  — https://<bookingHost>/book/<placeId>?token=…
#      must serve booking.html (the page the QR code encodes).
#   2. Edge Function GET    — …/functions/v1/booking-page?doctor=<placeId>
#      must return the legacy HTML form (token gate passes).
#   3. Edge Function GET action=slots — the new availability JSON the web
#      page uses to render the 14-day date strip + slot chips.
#   4. Edge Function POST action=register — saves name + mobile into the
#      users table ("save the patient first" step).
#   5. Edge Function POST action=book with a concrete date + time — must
#      create a Pending appointment at that date/time, which we confirm in
#      the live DB, confirm it appears in GET action=history for that
#      mobile, then delete the test rows so the project stays clean.
#
# Usage:
#   bash supabase/preflight_qr_flow.sh
#   bash supabase/preflight_qr_flow.sh --host https://your-site.vercel.app
#   bash supabase/preflight_qr_flow.sh --doctor <placeId> --keep
#
# Flags:
#   --host <url>     Override bookingHost (default: read from constants.dart)
#   --doctor <id>    Doctor place id (default: the deploy verify place)
#   --keep           Leave the test appointment + user behind (so
#                    cleanup_test_data.py --yes can be demonstrated)
#
# The SUPABASE_ACCESS_TOKEN is read from .env.deploy (recommended) or the
# environment, exactly like deploy_booking.py / cleanup_test_data.py.
# ═══════════════════════════════════════════════════════════════════

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${ROOT_DIR}/.env.deploy"
CONSTANTS_FILE="${ROOT_DIR}/lib/config/constants.dart"

PROJECT_REF="qxukzqdsmlurollltrjp"
FUNCTION_URL="https://${PROJECT_REF}.supabase.co/functions/v1/booking-page"
MANAGE_URL="https://api.supabase.com/v1/projects/${PROJECT_REF}/database/query"
DEFAULT_DOCTOR="ChIJN1t_tDeuEmsRUsoyG83frY4"

# Test markers — deliberately the SAME values cleanup_test_data.py and
# verify_booking_post.py match, so a leftover row is always caught.
TEST_NAME="Test Patient QA"
TEST_MOBILE="919876500123"
TEST_SYMPTOMS="e2e verification — preflight check"

# ── Args ────────────────────────────────────────────────────────────
BOOKING_HOST=""
DOCTOR="${DEFAULT_DOCTOR}"
KEEP=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --host) BOOKING_HOST="$2"; shift 2 ;;
    --doctor) DOCTOR="$2"; shift 2 ;;
    --keep) KEEP=1; shift ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

# ── Load token from .env.deploy (won't clobber an exported var) ─────
if [[ -z "${SUPABASE_ACCESS_TOKEN:-}" && -f "${ENV_FILE}" ]]; then
  while IFS= read -r line; do
    line="${line%%$'\r'}"
    [[ "${line}" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]] || continue
    key="${line%%=*}"
    if [[ "${key}" == "SUPABASE_ACCESS_TOKEN" ]]; then
      val="${line#*=}"
      val="${val% #*}"   # drop inline comment (same as the Python siblings)
      # strip surrounding single/double quotes (same as load_deploy_env)
      if [[ "${val}" == \"*\" || "${val}" == \'*\' ]]; then
        val="${val:1:${#val}-2}"
      fi
      SUPABASE_ACCESS_TOKEN="${val}"
    fi
  done < "${ENV_FILE}"
fi
if [[ -z "${SUPABASE_ACCESS_TOKEN:-}" ]]; then
  echo "ERROR: SUPABASE_ACCESS_TOKEN is not set (save it in ${ENV_FILE})." >&2
  exit 1
fi

# ── Read bookingHost + secret from constants.dart unless overridden ─
# Extract a `static const String X = 'value';` that may be formatted either
# on ONE line or across TWO (declaration, then value on the next line).
extract_const() {
  local name="$1"
  # Prefer the single-line form: `static const String X = 'value'`
  # (anchored to the line start so a commented-out example can't match).
  local val
  val="$(grep -oE "^[[:space:]]*static const String ${name} = '[^']*'" "${CONSTANTS_FILE}" | head -1 | sed -n "s/.*'\\([^']*\\)'.*/\\1/p")"
  if [[ -z "${val}" ]]; then
    # Fall back to the two-line form: `static const String X =` with the
    # value on a following line. Scan a few lines after the declaration,
    # skipping comment lines, so a comment between the declaration and the
    # value can't break extraction (a `grep -A1 | tail -1` would have
    # grabbed the comment line instead of the value).
    val="$(grep -A6 "^[[:space:]]*static const String ${name} =" "${CONSTANTS_FILE}" \
      | grep -v '^[[:space:]]*//' \
      | grep -m1 -oE "'[^']*'" \
      | tr -d "'")"
  fi
  printf '%s' "${val}"
}
BOOKING_SECRET="$(extract_const bookingSharedSecret)"
if [[ -z "${BOOKING_HOST}" ]]; then
  BOOKING_HOST="$(extract_const bookingHost)"
fi

UA="curl/8.5.0 (DrsListing preflight)"
FAILED=0
STATIC_SKIPPED=0
PASS() { echo "  -> OK: $1"; }
FAIL() { echo "  -> FAIL: $1"; FAILED=1; }

# URL-encode a value (e.g. a doctor place id) for safe use in query
# strings — parity with verify_booking_post.py's urllib quote().
urlencode() {
  local s="$1" i c
  for ((i = 0; i < ${#s}; i++)); do
    c="${s:i:1}"
    case "${c}" in
      [a-zA-Z0-9._~-]) printf '%s' "${c}" ;;
      *) printf '%%%02X' "'${c}" ;;
    esac
  done
}
DOCTOR_ENC="$(urlencode "${DOCTOR}")"

# Tomorrow's date (YYYY-MM-DD) in Asia/Kolkata — used for the slot-based
# test booking so it lands on a real future date the function accepts.
# Falls back to UTC if python3 is unavailable.
TODAY_IST=""
if command -v python3 >/dev/null 2>&1; then
  TODAY_IST="$(python3 - <<'PY'
from datetime import date, timedelta, datetime, timezone
now = datetime.now(timezone(timedelta(hours=5, minutes=30)))
print((now + timedelta(days=1)).strftime('%Y-%m-%d'))
PY
)"
fi
if [[ -z "${TODAY_IST}" ]]; then
  TODAY_IST="$(date -d '+1 day' +%Y-%m-%d 2>/dev/null || date -v+1d +%Y-%m-%d)"
fi

# Run a SQL statement against the live project via the Management API.
mgmt_query() {
  curl -s --max-time 20 -X POST "${MANAGE_URL}" \
    -H "User-Agent: ${UA}" \
    -H "Authorization: Bearer ${SUPABASE_ACCESS_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{\"query\":\"$1\"}"
}

echo "== DrsListing QR-flow pre-flight =="
echo "  bookingHost: ${BOOKING_HOST}"
echo "  doctor:      ${DOCTOR}"
echo "  test date:   ${TODAY_IST} (Asia/Kolkata, tomorrow)"
[[ "${KEEP}" == 1 ]] && echo "  --keep: test rows left behind"
echo ""

# ── 1. Static booking page ─────────────────────────────────────────
echo "[1/5] Static booking page (booking.html)..."
if [[ -z "${BOOKING_HOST}" || "${BOOKING_HOST}" == *"REPLACE-WITH"* ]]; then
  echo "  SKIP: bookingHost is still the placeholder in constants.dart."
  echo "        Set it to your deployed URL (or pass --host https://…)."
  echo "        The static-page half of the QR chain can't be verified yet."
  STATIC_SKIPPED=1
else
  STATIC_URL="${BOOKING_HOST}/book/${DOCTOR_ENC}?token=${BOOKING_SECRET}"
  BODY="$(curl -s -L --max-time 20 -H "User-Agent: ${UA}" "${STATIC_URL}")"
  if [[ -n "${BODY}" && "${BODY}" == *"Book an Appointment"* ]]; then
    PASS "static page serves booking.html at /book/<placeId>"
  else
    FAIL "static page did not render (got $(printf '%s' "${BODY}" | head -c 80))"
  fi
fi

# ── 2. Edge Function GET (legacy HTML form — token gate) ────────────
echo ""
echo "[2/5] Edge Function GET (legacy HTML form)..."
GET_URL="${FUNCTION_URL}?doctor=${DOCTOR_ENC}&token=${BOOKING_SECRET}"
GET_BODY="$(curl -s --max-time 20 -H "User-Agent: ${UA}" "${GET_URL}")"
if [[ -n "${GET_BODY}" && "${GET_BODY}" == *'id="bookingForm"'* ]]; then
  PASS "GET returns the legacy booking form"
else
  FAIL "GET did not return the form (got $(printf '%s' "${GET_BODY}" | head -c 80))"
fi

# ── 3. GET action=slots (availability JSON) ─────────────────────────
echo ""
echo "[3/5] Edge Function GET action=slots (availability JSON)..."
SLOTS_URL="${FUNCTION_URL}?doctor=${DOCTOR_ENC}&token=${BOOKING_SECRET}&action=slots"
SLOTS_BODY="$(curl -s --max-time 20 -H "User-Agent: ${UA}" "${SLOTS_URL}")"
if [[ -n "${SLOTS_BODY}" && "${SLOTS_BODY}" == *'"ok":true'* && "${SLOTS_BODY}" == *'"slots"'* ]]; then
  PASS "action=slots returns availability JSON"
else
  FAIL "action=slots did not return JSON (got $(printf '%s' "${SLOTS_BODY}" | head -c 80))"
fi

# ── 4. POST action=register (save patient to users table) ───────────
echo ""
echo "[4/5] Edge Function POST action=register (save patient)..."
REG_RESP="$(curl -s --max-time 30 -X POST "${FUNCTION_URL}?doctor=${DOCTOR_ENC}" \
  -H "User-Agent: ${UA}" \
  -H "Content-Type: application/json" \
  -H "x-booking-token: ${BOOKING_SECRET}" \
  -d "{\"action\":\"register\",\"name\":\"${TEST_NAME}\",\"mobile\":\"${TEST_MOBILE}\"}")"

REG_USER_ID="$(printf '%s' "${REG_RESP}" | sed -n 's/.*"userId":"\([^"]*\)".*/\1/p')"
if [[ -n "${REG_USER_ID}" && "${REG_RESP}" == *'"ok":true'* ]]; then
  PASS "registered patient (userId ${REG_USER_ID})"
else
  FAIL "register did not return a userId (got $(printf '%s' "${REG_RESP}" | head -c 120))"
fi

# ── 5. POST action=book (date+time) → confirm → history → clean up ──
echo ""
echo "[5/5] Edge Function POST action=book (slot booking) → confirm → history → clean up..."
# Try a couple of candidate slots; the race guard rejects genuinely-taken
# ones (a real patient may own tomorrow's 10:00 AM), so fall back to the
# legacy today+Flexible book if every candidate is taken — a deploy must
# never fail because the default doctor has a real booking at that slot.
BOOKED_TIME=""
for T in "10:00 AM" "10:30 AM" "11:00 AM"; do
  POST_RESP="$(curl -s --max-time 30 -X POST "${FUNCTION_URL}?doctor=${DOCTOR_ENC}" \
    -H "User-Agent: ${UA}" \
    -H "Content-Type: application/json" \
    -H "x-booking-token: ${BOOKING_SECRET}" \
    -d "{\"action\":\"book\",\"name\":\"${TEST_NAME}\",\"mobile\":\"${TEST_MOBILE}\",\"description\":\"${TEST_SYMPTOMS}\",\"date\":\"${TODAY_IST}\",\"time\":\"${T}\"}")"
  APPT_ID="$(printf '%s' "${POST_RESP}" | sed -n 's/.*"appointmentId":"\([^"]*\)".*/\1/p')"
  if [[ -n "${APPT_ID}" ]]; then
    BOOKED_TIME="${T}"
    break
  fi
  echo "  -> ${T}: taken/refused — trying next..."
done

if [[ -z "${APPT_ID}" ]]; then
  echo "  ! All candidate slots taken — falling back to legacy book (today/Flexible)."
  POST_RESP="$(curl -s --max-time 30 -X POST "${FUNCTION_URL}?doctor=${DOCTOR_ENC}" \
    -H "User-Agent: ${UA}" \
    -H "Content-Type: application/json" \
    -H "x-booking-token: ${BOOKING_SECRET}" \
    -d "{\"name\":\"${TEST_NAME}\",\"mobile\":\"${TEST_MOBILE}\",\"description\":\"${TEST_SYMPTOMS}\"}")"
  APPT_ID="$(printf '%s' "${POST_RESP}" | sed -n 's/.*"appointmentId":"\([^"]*\)".*/\1/p')"
fi

if [[ -z "${APPT_ID}" ]]; then
  FAIL "book did not return an appointmentId (got $(printf '%s' "${POST_RESP}" | head -c 120))"
else
  if [[ -n "${BOOKED_TIME}" ]]; then
    PASS "booked appointment ${APPT_ID} for ${TODAY_IST} ${BOOKED_TIME}"
  else
    PASS "booked appointment ${APPT_ID} (legacy today/Flexible fallback)"
  fi
  echo "  -> response: ${POST_RESP}"

  # Confirm the row landed with status Pending + the right date/time.
  CONFIRM_SQL="SELECT appointment_id, status, appointment_date, appointment_time FROM public.appointments WHERE appointment_id = '${APPT_ID}'"
  CONFIRM="$(mgmt_query "${CONFIRM_SQL}")"
  if [[ -n "${BOOKED_TIME}" ]]; then
    if [[ "${CONFIRM}" == *"Pending"* && "${CONFIRM}" == *"${TODAY_IST}"* && "${CONFIRM}" == *"${BOOKED_TIME}"* ]]; then
      PASS "appointment row is Pending at ${TODAY_IST} ${BOOKED_TIME} (${CONFIRM})"
    else
      FAIL "appointment row not Pending/date/time as expected (got ${CONFIRM})"
    fi
  else
    if [[ "${CONFIRM}" == *"Pending"* ]]; then
      PASS "appointment row is Pending (legacy fallback) (${CONFIRM})"
    else
      FAIL "appointment row not Pending (got ${CONFIRM})"
    fi
  fi

  # Confirm it shows up in the patient's booking history.
  HIST_URL="${FUNCTION_URL}?doctor=${DOCTOR_ENC}&token=${BOOKING_SECRET}&action=history&mobile=${TEST_MOBILE}"
  HIST_BODY="$(curl -s --max-time 20 -H "User-Agent: ${UA}" "${HIST_URL}")"
  if [[ "${HIST_BODY}" == *"${APPT_ID}"* && "${HIST_BODY}" == *'"ok":true'* ]]; then
    PASS "GET action=history lists ${APPT_ID} for ${TEST_MOBILE}"
  else
    FAIL "history did not include the new appointment (got $(printf '%s' "${HIST_BODY}" | head -c 120))"
  fi

  # Clean up (unless --keep).
  if [[ "${KEEP}" == 1 ]]; then
    echo "  --keep set — leaving the test rows for cleanup_test_data.py --yes."
  else
    DEL_APPT="DELETE FROM public.appointments WHERE appointment_id = '${APPT_ID}'"
    DEL_APPT_RESP="$(mgmt_query "${DEL_APPT}")"
    [[ "${DEL_APPT_RESP}" != *"error"* ]] \
      && PASS "deleted appointment" || FAIL "appointment delete failed: ${DEL_APPT_RESP}"

    DEL_USER="DELETE FROM public.users WHERE name = '${TEST_NAME}' AND mobile = '${TEST_MOBILE}' AND id NOT IN (SELECT user_id FROM public.appointments WHERE user_id IS NOT NULL)"
    DEL_USER_RESP="$(mgmt_query "${DEL_USER}")"
    [[ "${DEL_USER_RESP}" != *"error"* ]] \
      && PASS "deleted test user" || FAIL "user delete failed: ${DEL_USER_RESP}"

    # Verify the appointment is really gone.
    CHECK_SQL="SELECT COUNT(*) AS c FROM public.appointments WHERE appointment_id = '${APPT_ID}'"
    CHECK="$(mgmt_query "${CHECK_SQL}")"
    if [[ "${CHECK}" == *'"c":0'* || "${CHECK}" == *'"c": 0'* ]]; then
      PASS "cleanup verified (0 rows remain for ${APPT_ID})"
    else
      FAIL "appointment still present: ${CHECK}"
    fi
  fi
fi

echo ""
if [[ "${FAILED}" == 1 ]]; then
  echo "PRE-FLIGHT FAILED — fix the failing step, then re-run."
  exit 1
fi
if [[ "${STATIC_SKIPPED}" == 1 ]]; then
  echo "  note: static page not verified (bookingHost is the placeholder)."
  echo "        Run with --host https://your-site.vercel.app to verify it too."
fi
echo "SUCCESS: QR chain is healthy (static page, slots, register, book, history)."
