#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════
# DrsListing — real-browser (Chrome headless) verification.
#
# Wraps the real-Chrome headless checks that prove the STATIC side of
# the QR booking flow actually works in a browser engine (JS executed):
#
#   1. Root page        — https://<bookingHost>/ renders the DrsListing
#      landing page (not the host's default 404).
#   2. Token preserved  — visiting the root with ?token=...&name=...
#      must make index.html's query-preservation script rewrite the
#      "Open Booking Page" button href to /booking?token=... (so the
#      form opens pre-authorized).
#   3. booking.html form — https://<bookingHost>/booking.html?doctor=<id>&token=...
#      renders the booking form (title "Book with <name>", form visible,
#      NOT the fail-closed "invalid link" message) and responds HTTP 200
#      (a real static file — the old /book/<placeId> path returns 404 via
#      Pages' 404.html fallback, which crawlers treat as missing).
#
# The POST booking chain (book → confirm Pending → clean up) is covered
# by preflight_qr_flow.sh — pass --with-post to run it after these
# browser checks, so a single command verifies the whole QR flow.
#
# Chrome headless is used because the browser-use agent wrapper is not
# available in every environment; --headless=new --dump-dom executes the
# page's real JavaScript and dumps the resulting DOM (Chrome normalizes
# attributes to double quotes, which the greps account for).
#
# Usage:
#   bash supabase/verify_browser_flow.sh
#   bash supabase/verify_browser_flow.sh --host https://your-site.vercel.app
#   bash supabase/verify_browser_flow.sh --with-post
#
# Flags:
#   --host <url>    Override bookingHost (default: read from constants.dart)
#   --doctor <id>   Doctor place id (default: the deploy verify place)
#   --token <tok>   Override the shared secret (default: constants.dart)
#   --chrome <bin>  Chrome/Chromium executable path (default: auto-detect)
#   --with-post     Also run preflight_qr_flow.sh (full POST booking chain)
# ═══════════════════════════════════════════════════════════════════

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
CONSTANTS_FILE="${ROOT_DIR}/lib/config/constants.dart"

DEFAULT_DOCTOR="ChIJN1t_tDeuEmsRUsoyG83frY4"
TEST_NAME="Shashwat Hospital"   # shown in the /book/ page title
DOM_TMP="$(mktemp -d)"
trap 'rm -rf "${DOM_TMP}"' EXIT

# ── Args ────────────────────────────────────────────────────────────
BOOKING_HOST=""
DOCTOR="${DEFAULT_DOCTOR}"
TOKEN_OVERRIDE=""
CHROME_BIN=""
WITH_POST=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --host) BOOKING_HOST="$2"; shift 2 ;;
    --doctor) DOCTOR="$2"; shift 2 ;;
    --token) TOKEN_OVERRIDE="$2"; shift 2 ;;
    --chrome) CHROME_BIN="$2"; shift 2 ;;
    --with-post) WITH_POST=1; shift ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

# ── Reuse extract_const() from preflight_qr_flow.sh (single source of
#    truth — guarded by test_extract_const.sh). tr -d '\r' keeps the eval
#    intact if the file is ever saved with CRLF. ─────────────────────
if [[ ! -f "${SCRIPT_DIR}/preflight_qr_flow.sh" ]]; then
  echo "ERROR: ${SCRIPT_DIR}/preflight_qr_flow.sh not found." >&2
  exit 1
fi
eval "$(sed -n '/^extract_const() {/,/^}/p' "${SCRIPT_DIR}/preflight_qr_flow.sh" | tr -d '\r')"

BOOKING_SECRET="${TOKEN_OVERRIDE:-$(extract_const bookingSharedSecret)}"
if [[ -z "${BOOKING_HOST}" ]]; then
  BOOKING_HOST="$(extract_const bookingHost)"
fi
if [[ -z "${BOOKING_HOST}" || "${BOOKING_HOST}" == *"REPLACE-WITH"* ]]; then
  echo "ERROR: bookingHost is missing/placeholder in constants.dart." >&2
  echo "       Set it (or pass --host https://…)." >&2
  exit 1
fi
if [[ -z "${BOOKING_SECRET}" ]]; then
  echo "ERROR: bookingSharedSecret is empty in constants.dart." >&2
  echo "       Set it (or pass --token …)." >&2
  exit 1
fi

# ── Locate Chrome/Chromium ──────────────────────────────────────────
find_chrome() {
  # --chrome flag wins.
  if [[ -n "${CHROME_BIN}" && -x "${CHROME_BIN}" ]]; then
    printf '%s' "${CHROME_BIN}"; return 0
  fi
  # Common Windows paths (Git Bash / MSYS).
  for p in \
    "/c/Program Files/Google/Chrome/Application/chrome.exe" \
    "/c/Program Files (x86)/Google/Chrome/Application/chrome.exe" \
    "$(ls /c/Users/*/AppData/Local/Google/Chrome/Application/chrome.exe 2>/dev/null | head -1)" \
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
    ; do
    if [[ -n "${p}" && -x "${p}" ]]; then
      printf '%s' "${p}"; return 0
    fi
  done
  # PATH fallbacks (Linux).
  for b in google-chrome chromium chromium-browser; do
    if command -v "${b}" >/dev/null 2>&1; then
      printf '%s' "$(command -v "${b}")"; return 0
    fi
  done
  return 1
}
CHROME="$(find_chrome)" || {
  echo "ERROR: Chrome/Chromium not found. Install it or pass --chrome <path>." >&2
  exit 1
}
echo "Using Chrome: ${CHROME}"

# ── Helpers ─────────────────────────────────────────────────────────
FAILED=0
UA="curl/8.5.0 (DrsListing browser verify)"
PASS() { echo "  -> OK: $1"; }
FAIL() { echo "  -> FAIL: $1"; FAILED=1; }

# dump_dom <url> <outfile> — run the page's JS and dump the DOM.
# Fails loudly if Chrome produced no output (binary/launch problem)
# instead of leaving the caller with a confusing empty grep.
dump_dom() {
  "${CHROME}" --headless=new --disable-gpu --no-sandbox \
    --dump-dom --virtual-time-budget=5000 "$1" 2>/dev/null > "$2"
  if [[ ! -s "$2" ]]; then
    echo "  -> ERROR: Chrome produced no output for $1"
    echo "            (binary launch failure? try --chrome <path>)"
    FAILED=1
    return 1
  fi
  return 0
}

# URL-encode a value for query strings (parity with preflight).
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
NAME_ENC="$(urlencode "${TEST_NAME}")"

echo "== DrsListing real-browser (Chrome headless) verification =="
echo "  bookingHost: ${BOOKING_HOST}"
echo "  doctor:      ${DOCTOR}"
echo ""

# ── 1. Root landing page renders (not 404) ─────────────────────────
echo "[1/3] Root page renders the DrsListing landing page..."
dump_dom "${BOOKING_HOST}/" "${DOM_TMP}/root.html"
ROOT_OK=0
grep -q 'DrsListing' "${DOM_TMP}/root.html" && ROOT_OK=1
if [[ "${ROOT_OK}" == 1 && "$(grep -c 'Open Booking Page' "${DOM_TMP}/root.html")" -ge 1 ]]; then
  PASS "landing page rendered (DrsListing + Open Booking Page button)"
else
  FAIL "root did not render the landing page (host 404 or missing content?)"
fi

# ── 2. Query-preserving JS rewrites the button href with the token ──
echo ""
echo "[2/3] Root visit with ?token= rewrites the button href..."
PARAMS_URL="${BOOKING_HOST}/?token=${BOOKING_SECRET}&name=${NAME_ENC}"
dump_dom "${PARAMS_URL}" "${DOM_TMP}/root_params.html"
BTN_TAG="$(grep -oE '<a[^>]*bookingBtn[^>]*>' "${DOM_TMP}/root_params.html" | head -1)"
echo "  button: ${BTN_TAG:-<none found>}"
# GitHub Pages (current host) points the button at booking.html; the
# legacy Netlify host used /booking (a rewrite). Both must carry the token.
if [[ -n "${BTN_TAG}" &&       ( "${BTN_TAG}" == *"/booking?token="* || "${BTN_TAG}" == *"booking.html?token="* ) &&       "${BTN_TAG}" == *"${BOOKING_SECRET}"* ]]; then
  PASS "query-preservation JS rewrote href with the shared token: ${BTN_TAG}"
else
  FAIL "button href missing the rewritten booking path with the shared token"
fi

# ── 3. /book/ form renders visible for a valid QR link ──────────────
echo ""
echo "[3/4] booking.html form renders (HTTP 200, visible, not fail-closed)..."
BOOK_URL="${BOOKING_HOST}/booking.html?doctor=${DOCTOR_ENC}&token=${BOOKING_SECRET}&name=${NAME_ENC}"
# The whole point of the booking.html URL: it is a REAL file, so Pages
# answers 200 (the /book/<placeId> path would answer 404 via 404.html).
BOOK_STATUS="$(curl -s -o /dev/null -w '%{http_code}' -L --max-time 20 -H "User-Agent: ${UA}" "${BOOK_URL}")"
dump_dom "${BOOK_URL}" "${DOM_TMP}/book.html"
TITLE="$(grep -oE 'Book with [^<]*' "${DOM_TMP}/book.html" | head -1)"
FORM_TAG="$(grep -oE '<form[^>]*id="bookingForm"[^>]*>' "${DOM_TMP}/book.html" | head -1)"
FIELDS="$(grep -c -E 'Full Name|Mobile Number|Book Appointment' "${DOM_TMP}/book.html")"
echo "  status: ${BOOK_STATUS} (must be 200)"
echo "  title:  ${TITLE:-<none>}"
echo "  form:   ${FORM_TAG:-<none>}"
echo "  fields: ${FIELDS} / 3 required markers"
if [[ "${BOOK_STATUS}" == "200" && "${TITLE}" == *"Book with ${TEST_NAME}"* && "${FORM_TAG}" != *"display: none"* && "${FIELDS}" -ge 3 ]]; then
  PASS "booking form visible with HTTP 200 + title '${TITLE}' and all fields"
else
  FAIL "booking form not rendered with 200 (status=${BOOK_STATUS:-none}; title/form/fields check)"
fi

# ── 4. Modern UI markers (Download App header, date strip, history) ──
echo ""
echo "[4/4] Modern UI markers (Download App + date strip + history)..."
DL_APP="$(grep -c 'Download App' "${DOM_TMP}/book.html")"
DATE_STRIP="$(grep -c 'date-strip\|date-chip' "${DOM_TMP}/book.html")"
HISTORY="$(grep -c 'Your Bookings' "${DOM_TMP}/book.html")"
SLOT_BOOK="$(grep -c 'Book Appointment' "${DOM_TMP}/book.html")"
echo "  Download App: ${DL_APP}"
echo "  date strip:   ${DATE_STRIP} markers"
echo "  history:      ${HISTORY}"
echo "  book button:  ${SLOT_BOOK}"
if [[ "${DL_APP}" -ge 1 && "${DATE_STRIP}" -ge 1 && "${HISTORY}" -ge 1 && "${SLOT_BOOK}" -ge 1 ]]; then
  PASS "modern booking UI present (Download App, date strip, history, book button)"
else
  FAIL "modern booking UI markers missing (Download App=${DL_APP}, date=${DATE_STRIP}, history=${HISTORY}, book=${SLOT_BOOK})"
fi

echo ""
if [[ "${WITH_POST}" == 1 ]]; then
  echo "── Running preflight_qr_flow.sh (full POST booking chain) ──"
  if ! bash "${SCRIPT_DIR}/preflight_qr_flow.sh" --doctor "${DOCTOR}"; then
    FAILED=1
  fi
fi

echo ""
if [[ "${FAILED}" == 1 ]]; then
  echo "BROWSER VERIFICATION FAILED — fix the failing step, then re-run."
  exit 1
fi
echo "BROWSER VERIFICATION PASSED — landing page, token preservation and booking.html (HTTP 200) all render correctly in real Chrome."
