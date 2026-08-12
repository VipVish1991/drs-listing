#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════
# DrsListing — extract_const() regression test.
#
# Guards the constant-extraction logic used by preflight_qr_flow.sh,
# which reads `static const String bookingHost` / `bookingSharedSecret`
# from lib/config/constants.dart. The parser must survive formatting
# changes, so this test pins the FORMATS it must handle:
#
#   1. Two-line declaration with a comment line between declaration
#      and value (the old `grep -A1 | tail -1` fell over here — it
#      grabbed the comment line and returned empty).
#   2. Two-line declaration with a MULTI-LINE comment block between
#      declaration and value (pins the fallback's -A6 scan window).
#   3. Two-line declaration without a comment (regression).
#   4. Single-line declaration (regression).
#   5. A commented-out example must NOT be picked up (anchoring).
#   6. The REAL constants.dart must still yield a valid host + secret
#      (shape-checked, not value-pinned — see below).
#
# Why shape checks for the real file: the host and shared secret are
# expected to change over time (host redeploys, secret rotation).
# Pinning today's exact values would make this test fail on a
# legitimate deploy. The fixtures above are the value-pinned part; the
# real-file check only requires a non-empty https host and a non-empty
# secret, so a formatting regression is still caught.
#
# Run:
#   bash supabase/test_extract_const.sh
# ═══════════════════════════════════════════════════════════════════

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REAL_CONSTANTS="${SCRIPT_DIR}/../lib/config/constants.dart"
FIXTURE="$(mktemp)"
trap 'rm -f "${FIXTURE}"' EXIT   # only ever removes the temp fixture

# Pull the extract_const() function definition out of the real script.
# tr -d '\r' keeps the eval intact if the file is ever saved with CRLF.
eval "$(sed -n '/^extract_const() {/,/^}/p' "${SCRIPT_DIR}/preflight_qr_flow.sh" | tr -d '\r')"

FAILED=0
check() { # check <label> <expected> <actual>
  if [[ "$2" == "$3" ]]; then
    echo "  PASS: $1"
  else
    echo "  FAIL: $1 — expected [$2] got [$3]"
    FAILED=1
  fi
}

fixture() { # fixture <<EOF writes a fixture and points CONSTANTS_FILE at it
  CONSTANTS_FILE="${FIXTURE}"
  cat > "${FIXTURE}"
}

echo "--- fixture 1: comment between declaration and value ---"
fixture <<'EOF'
class AppConstants {
  // A commented-out example must NOT be picked up:
  // static const String bookingHost = 'https://WRONG.example';

  static const String bookingHost =
      // Live host with a comment wedged between declaration and value.
      'https://VipVish1991.github.io/drsListing-web';
}
EOF
check "two-line + comment" "https://VipVish1991.github.io/drsListing-web" "$(extract_const bookingHost)"

echo "--- fixture 2: multi-line comment block between decl and value ---"
fixture <<'EOF'
class AppConstants {
  static const String bookingHost =
      // A longer comment block:
      //   line two
      //   line three
      //   line four
      // The -A6 window must skip all of these and reach the value.
      'https://VipVish1991.github.io/drsListing-web';
}
EOF
check "two-line + multi-line comment" "https://VipVish1991.github.io/drsListing-web" "$(extract_const bookingHost)"

echo "--- fixture 3: two-line without comment (regression) ---"
fixture <<'EOF'
class AppConstants {
  static const String bookingSharedSecret =
      'cAZrwHpDFJ4HaSNXowJnmvzi-0YD5rYE';
}
EOF
check "two-line no comment" "cAZrwHpDFJ4HaSNXowJnmvzi-0YD5rYE" "$(extract_const bookingSharedSecret)"

echo "--- fixture 4: single-line form (regression) ---"
fixture <<'EOF'
class AppConstants {
  static const String bookingHost = 'https://VipVish1991.github.io/drsListing-web';
}
EOF
check "single-line" "https://VipVish1991.github.io/drsListing-web" "$(extract_const bookingHost)"

echo "--- fixture 5: commented-out example must NOT match ---"
fixture <<'EOF'
class AppConstants {
  // static const String bookingSharedSecret = 'https://WRONG.example';
}
EOF
check "commented-out example ignored" "" "$(extract_const bookingSharedSecret)"

echo "--- fixture 6: real constants.dart (read-only, shape checks) ---"
CONSTANTS_FILE="${REAL_CONSTANTS}"
REAL_HOST="$(extract_const bookingHost)"
REAL_SECRET="$(extract_const bookingSharedSecret)"
if [[ -n "${REAL_HOST}" && "${REAL_HOST}" == https://* ]]; then
  echo "  PASS: real bookingHost looks like an https URL (${REAL_HOST})"
else
  echo "  FAIL: real bookingHost missing/not-https — got [${REAL_HOST}]"
  FAILED=1
fi
if [[ -n "${REAL_SECRET}" ]]; then
  echo "  PASS: real bookingSharedSecret is non-empty"
else
  echo "  FAIL: real bookingSharedSecret is empty"
  FAILED=1
fi

echo ""
if [[ "${FAILED}" == 1 ]]; then
  echo "RESULT: FAILED"
  exit 1
fi
echo "RESULT: ALL PASSED"
