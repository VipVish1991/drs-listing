#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════
# DrsListing — Web booking flow verification (curl-based, reusable).
#
# Simulates exactly what the static booking page does when a patient
# scans the QR code — the Edge Function web flow — end to end, using
# plain curl:
#
#   1. POST action=register → saves name + mobile into the users table
#      (the "register the patient first" step).
#   2. POST action=book     → books a concrete date + time slot, which
#      must land as a 'Pending' appointment in the live DB.
#   3. GET  action=history  → confirms the new booking appears in the
#      patient's history for that mobile number.
#   4. Clean up             → deletes the test appointment + test user
#      via the Management API and verifies nothing remains, so the
#      project stays clean after every run.
#
# Focus vs the siblings (same API, different tooling):
#   - preflight_qr_flow.sh   → the full QR chain (static page + GET + flow)
#   - verify_booking_post.py → the same web flow, written in Python
#   - verify_web_flow.sh     → the web flow, curl-only (this script)
#
# Usage:
#   bash supabase/verify_web_flow.sh
#   bash supabase/verify_web_flow.sh --doctor <placeId>
#   bash supabase/verify_web_flow.sh --keep      # leave the test rows
#                                                # (cleanup_test_data.py
#                                                #  --yes can remove them)
#
# Flags:
#   --doctor <id>    Doctor place id (default: the deploy verify place)
#   --keep           Leave the test appointment + user behind
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

# Test markers — deliberately the SAME values cleanup_test_data.py and the
# other verifiers match, so a leftover row is always caught.
TEST_NAME="Test Patient QA"
TEST_MOBILE="919876500123"
TEST_SYMPTOMS="e2e verification — web flow curl test"

# ── Args ────────────────────────────────────────────────────────────
DOCTOR="${DEFAULT_DOCTOR}"
KEEP=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --doctor) DOCTOR="$2"; shift 2 ;;
    --keep) KEEP=1; shift ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

# ── Load token from .env.deploy (won't clobber an exported var) ─────
# (same parsing as deploy_booking.py's load_deploy_env)
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

# ── Read the booking shared secret from constants.dart ──────────────
# Extract a `static const String X = 'value';` that may be formatted on
# ONE line or across TWO (declaration, then value on the next line) —
# robust to a comment line between them (mirrors preflight_qr_flow.sh).
extract_const() {
  local name="$1"
  local val
  val="$(grep -oE "^[[:space:]]*static const String ${name} = '[^']*'" "${CONSTANTS_FILE}" | head -1 | sed -n "s/.*'\([^']*\)'.*/\1/p")"
  if [[ -z "${val}" ]]; then
    val="$(grep -A6 "^[[:space:]]*static const String ${name} =" "${CONSTANTS_FILE}" \
      | grep -v '^[[:space:]]*//' \
      | grep -m1 -oE "'[^']*'" \
      | tr -d "'")"
  fi
  printf '%s' "${val}"
}
BOOKING_SECRET="$(extract_const bookingSharedSecret)"
if [[ -z "${BOOKING_SECRET}" ]]; then
  echo "ERROR: could not read bookingSharedSecret from ${CONSTANTS_FILE}." >&2
  exit 1
fi

UA="curl/8.5.0 (DrsListing web-flow)"
FAILED=0
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
# Falls back to UTC-ish `date` if python3 is unavailable.
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

echo "== DrsListing web booking flow verification =="
echo "  doctor:    ${DOCTOR}"
echo "  test date: ${TODAY_IST} (Asia/Kolkata, tomorrow)"
[[ "${KEEP}" == 1 ]] && echo "  --keep: test rows left behind"
echo ""

# ── 1. POST action=register ─────────────────────────────────────────
echo "[1/4] POST action=register (save patient to users table)..."
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

# ── 2. POST action=book (date+time) ─────────────────────────────────
echo ""
echo "[2/4] POST action=book (slot booking)..."
# Try a couple of candidate slots; the race guard rejects genuinely-taken
# ones (a real patient may own tomorrow's 10:00 AM), so fall back to the
# legacy today+Flexible book if every candidate is taken — a verification
# run must never fail because the default doctor has a real booking.
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
  # The test user may have been registered just before the booking failed —
  # clean it up with the same safe guard (markers + no remaining
  # appointments) so nothing is left behind even on a failing run.
  if [[ -n "${REG_USER_ID:-}" ]]; then
    DEL_USER="DELETE FROM public.users WHERE id = '${REG_USER_ID}' AND name = '${TEST_NAME}' AND mobile = '${TEST_MOBILE}' AND id NOT IN (SELECT user_id FROM public.appointments WHERE user_id IS NOT NULL)"
    DEL_USER_RESP="$(mgmt_query "${DEL_USER}")"
    if [[ "${DEL_USER_RESP}" != *"error"* ]]; then
      PASS "cleaned up test user after failed booking"
    else
      echo "  ! test-user cleanup failed: ${DEL_USER_RESP} "
      echo "    (cleanup_test_data.py --yes will catch the leftover)"
    fi
  fi
else
  if [[ -n "${BOOKED_TIME}" ]]; then
    PASS "booked appointment ${APPT_ID} for ${TODAY_IST} ${BOOKED_TIME}"
  else
    PASS "booked appointment ${APPT_ID} (legacy today/Flexible fallback)"
  fi
  echo "  -> response: ${POST_RESP}"

  # ── 3. Confirm DB row + history ────────────────────────────────
  echo ""
  echo "[3/4] Confirming the Pending row + GET action=history..."

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

  HIST_URL="${FUNCTION_URL}?doctor=${DOCTOR_ENC}&token=${BOOKING_SECRET}&action=history&mobile=${TEST_MOBILE}"
  HIST_BODY="$(curl -s --max-time 20 -H "User-Agent: ${UA}" "${HIST_URL}")"
  if [[ "${HIST_BODY}" == *"${APPT_ID}"* && "${HIST_BODY}" == *'"ok":true'* ]]; then
    PASS "GET action=history lists ${APPT_ID} for ${TEST_MOBILE}"
  else
    FAIL "history did not include the new appointment (got $(printf '%s' "${HIST_BODY}" | head -c 120))"
  fi

  # ── 4. Clean up ────────────────────────────────────────────────
  echo ""
  echo "[4/4] Cleaning up the test booking..."
  if [[ "${KEEP}" == 1 ]]; then
    echo "  --keep set — leaving the test rows for cleanup_test_data.py --yes."
  else
    DEL_APPT="DELETE FROM public.appointments WHERE appointment_id = '${APPT_ID}'"
    DEL_APPT_RESP="$(mgmt_query "${DEL_APPT}")"
    [[ "${DEL_APPT_RESP}" != *"error"* ]] \
      && PASS "deleted appointment" || FAIL "appointment delete failed: ${DEL_APPT_RESP}"

    # Delete the patient user ONLY if they match the test markers AND
    # have no remaining appointments (real patients can never be hit).
    DEL_USER="DELETE FROM public.users WHERE name = '${TEST_NAME}' AND mobile = '${TEST_MOBILE}' AND id NOT IN (SELECT user_id FROM public.appointments WHERE user_id IS NOT NULL)"
    DEL_USER_RESP="$(mgmt_query "${DEL_USER}")"
    [[ "${DEL_USER_RESP}" != *"error"* ]] \
      && PASS "deleted test user" || FAIL "user delete failed: ${DEL_USER_RESP}"

    # Verify both are really gone.
    CHECK_APPT="$(mgmt_query "SELECT COUNT(*) AS c FROM public.appointments WHERE appointment_id = '${APPT_ID}'")"
    if [[ "${CHECK_APPT}" == *'"c":0'* || "${CHECK_APPT}" == *'"c": 0'* ]]; then
      PASS "cleanup verified (0 rows remain for ${APPT_ID})"
    else
      FAIL "appointment still present: ${CHECK_APPT}"
    fi

    CHECK_USER="$(mgmt_query "SELECT COUNT(*) AS c FROM public.users WHERE name = '${TEST_NAME}' AND mobile = '${TEST_MOBILE}'")"
    if [[ "${CHECK_USER}" == *'"c":0'* || "${CHECK_USER}" == *'"c": 0'* ]]; then
      PASS "test user removed (0 rows remain)"
    else
      FAIL "test user still present: ${CHECK_USER}"
    fi
  fi
fi

echo ""
if [[ "${FAILED}" == 1 ]]; then
  echo "WEB FLOW FAILED — fix the failing step, then re-run."
  exit 1
fi
echo "SUCCESS: web booking flow verified end-to-end (register → book → history → clean up)."
