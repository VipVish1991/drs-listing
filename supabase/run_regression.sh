#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════
# DrsListing — full regression runner (one command, everything).
#
# Runs, in order:
#
#   1. flutter analyze            — static analysis / lints
#   2. flutter test               — the full unit + widget + e2e suite
#   3. test_extract_const.sh      — parser regression guard (bookingHost /
#                                   bookingSharedSecret extraction)
#   4. check_schema_drift.py      — declared migrations vs LIVE DB
#                                   (optionally --reconcile auto-fixes)
#   5. verify_booking_post.py     — LIVE booking Edge Function end-to-end
#                                   (form GET -> register -> book -> confirm
#                                    Pending row -> history -> cleanup)
#   6. verify_fcm_delivery.py     — LIVE FCM push chain (service-account
#                                   OAuth2 -> FCM HTTP v1 -> history row)
#   7. verify_prescription_upload.py — LIVE prescription upload chain
#                                   (book video slot -> upload JPEG ->
#                                    server-side downscale -> storage GET ->
#                                    cleanup). The test JPEG is generated
#                                    on the fly with the project's own
#                                    `image` package (no manual step).
#
# Each step runs independently; a failure in one does not stop the
# others, and the script exits non-zero if ANY step failed.
#
# Usage:
#   bash supabase/run_regression.sh                    # everything
#   bash supabase/run_regression.sh --skip-flutter     # skip 1 + 2 (fast infra)
#   bash supabase/run_regression.sh --skip-live        # skip 5 + 6 + 7 (no
#                                                      # live-DB writes)
#   bash supabase/run_regression.sh --reconcile        # pass --reconcile to
#                                                      # the drift check (auto-
#                                                      # applies missing objects)
#   bash supabase/run_regression.sh --keep             # leave test rows behind
#                                                      # (cleanup_test_data.py
#                                                      # --yes can demo cleanup)
#   bash supabase/run_regression.sh --doctor <placeId> # custom doctor for the
#                                                      # live harnesses
#
# The SUPABASE_ACCESS_TOKEN (and FIREBASE_SERVICE_ACCOUNT for step 6) are
# read from .env.deploy, exactly like the other verify/deploy scripts.
# ═══════════════════════════════════════════════════════════════════

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${ROOT_DIR}/.env.deploy"

# ── Flag parsing ────────────────────────────────────────────────────
SKIP_FLUTTER=0
SKIP_LIVE=0
RECONCILE=0
KEEP=0
DOCTOR=""
EXTRA=()

for arg in "$@"; do
  case "${arg}" in
    --skip-flutter) SKIP_FLUTTER=1 ;;
    --skip-live)    SKIP_LIVE=1 ;;
    --reconcile)    RECONCILE=1 ;;
    --keep)         KEEP=1 ;;
    --doctor=*)     DOCTOR="${arg#*=}" ;;
    --doctor)       DOCTOR="__NEXT__" ;;
    *)              EXTRA+=("${arg}") ;;
  esac
done

# --doctor <placeId> (bare flag followed by the value in EXTRA).
# `__NEXT__` is a sentinel, not a real placeId (placeIds start with "ChI").
if [[ "${DOCTOR}" == "__NEXT__" && ${#EXTRA[@]} -gt 0 ]]; then
  # Reject a flag-looking value so `--doctor --keep` does not consume --keep.
  if [[ "${EXTRA[0]}" == --* ]]; then
    echo "ERROR: --doctor requires a value (got '${EXTRA[0]}')."
    exit 1
  fi
  DOCTOR="${EXTRA[0]}"
  EXTRA=("${EXTRA[@]:1}")
fi

# Unknown/typo'd flags are silently swallowed by EXTRA — surface them so a
# mis-typed flag cannot silently run (or skip) the wrong steps.
if [[ ${#EXTRA[@]} -gt 0 ]]; then
  echo "WARNING: unknown argument(s) ignored: ${EXTRA[*]}"
fi

# Common flags for the harnesses that support them. `--doctor` is only
# understood by the booking + prescription harnesses (FCM probes its own
# isolated doctor), so it is added per-harness below, not globally.
HARNESS_ARGS=()
if [[ "${KEEP}" == 1 ]]; then
  HARNESS_ARGS+=("--keep")
fi
DOCTOR_ARGS=()
if [[ -n "${DOCTOR}" && "${DOCTOR}" != "__NEXT__" ]]; then
  DOCTOR_ARGS+=("--doctor" "${DOCTOR}")
fi

# ── State ────────────────────────────────────────────────────────────
PASSED=0
FAILED=0
FAILED_STEPS=()

BANNER="================================================================"

step_header() {
  echo ""
  echo "${BANNER}"
  echo "▶ $1"
  echo "${BANNER}"
}

# run_step <name> <command...>
run_step() {
  local name="$1"; shift
  step_header "${name}"
  if "$@" 2>&1; then
    echo ""
    echo "  ✓ ${name}: PASS"
    PASSED=$((PASSED + 1))
  else
    local code=$?
    echo ""
    echo "  ✗ ${name}: FAIL (exit ${code})"
    FAILED=$((FAILED + 1))
    FAILED_STEPS+=("${name}")
  fi
}

# Pre-flight: the live harnesses need .env.deploy.
if [[ ! -f "${ENV_FILE}" ]]; then
  echo "ERROR: ${ENV_FILE} not found — live harnesses cannot run."
  echo "Create it with SUPABASE_ACCESS_TOKEN=... (and FIREBASE_SERVICE_ACCOUNT=...)."
  exit 1
fi

# Run everything from the project root so flutter/dart and relative paths
# behave identically (and PASS/FAIL counters stay in this shell — a
# subshell would lose them).
cd "${ROOT_DIR}"

echo "== DrsListing full regression =="
echo "  root:      ${ROOT_DIR}"
echo "  skip-flutter: ${SKIP_FLUTTER}   skip-live: ${SKIP_LIVE}   reconcile: ${RECONCILE}"
echo "  keep:      ${KEEP}   doctor: ${DOCTOR:-<default>}"
echo "  started:   $(date '+%Y-%m-%d %H:%M:%S')"

# ── 1 + 2. Flutter analyze + test ───────────────────────────────────
if [[ "${SKIP_FLUTTER}" == 0 ]]; then
  run_step "flutter analyze" flutter analyze
  run_step "flutter test" flutter test
else
  echo ""
  echo "⏭  Skipping flutter analyze + flutter test (--skip-flutter)"
fi

# ── 3. Parser regression guard ──────────────────────────────────────
run_step "test_extract_const.sh" bash "${SCRIPT_DIR}/test_extract_const.sh"

# ── 4. Schema drift (with optional --reconcile) ─────────────────────
if [[ "${RECONCILE}" == 1 ]]; then
  run_step "schema drift (--reconcile)" python "${SCRIPT_DIR}/check_schema_drift.py" --reconcile
else
  run_step "schema drift" python "${SCRIPT_DIR}/check_schema_drift.py"
fi

# ── 5 + 6 + 7. Live Edge Function harnesses ─────────────────────────
if [[ "${SKIP_LIVE}" == 1 ]]; then
  echo ""
  echo "⏭  Skipping live Edge Function harnesses (--skip-live)"
else
  run_step "booking POST chain" python "${SCRIPT_DIR}/verify_booking_post.py" "${HARNESS_ARGS[@]}" "${DOCTOR_ARGS[@]}"
  # FCM deliberately gets no --doctor (it creates its own isolated probe
  # doctor); HARNESS_ARGS (--keep) still applies.
  run_step "FCM push delivery" python "${SCRIPT_DIR}/verify_fcm_delivery.py" "${HARNESS_ARGS[@]}"

  # Prescription chain needs a real JPEG; generate it with the project's
  # own `image` package (exercises the server-side 1600px downscale).
  GEN_DIR="${ROOT_DIR}/.tmp_check"
  GEN_DART="${GEN_DIR}/_gen_test_jpeg.dart"
  GEN_JPG="${GEN_DIR}/_regression_test.jpg"
  # Interrupt-safe: remove any generated temp files even on Ctrl+C/kill.
  trap 'rm -f "${GEN_DART}" "${GEN_JPG}"' EXIT
  mkdir -p "${GEN_DIR}"
  cat > "${GEN_DART}" <<'DART'
import 'dart:io';
import 'package:image/image.dart' as img;
void main() {
  final im = img.Image(width: 2400, height: 1800);
  img.fill(im, color: img.ColorRgb8(198, 84, 68));
  for (var y = 200; y < 1600; y++) {
    for (var x = 800; x < 1600; x++) { im.setPixelRgb(x, y, 255, 255, 255); }
  }
  File('_regression_test.jpg').writeAsBytesSync(img.encodeJpg(im, quality: 85));
}
DART
  if ( cd "${GEN_DIR}" && dart run "${GEN_DART}" ) 2>&1; then
    echo "  test JPEG generated: ${GEN_JPG}"
  else
    echo "  WARN: could not generate test JPEG"
    GEN_JPG=""
  fi
  rm -f "${GEN_DART}"

  if [[ -n "${GEN_JPG}" && -f "${GEN_JPG}" ]]; then
    run_step "prescription upload chain" \
      python "${SCRIPT_DIR}/verify_prescription_upload.py" \
        --image "${GEN_JPG}" "${HARNESS_ARGS[@]}" "${DOCTOR_ARGS[@]}"
    rm -f "${GEN_JPG}"
  else
    echo ""
    echo "  ✗ prescription upload chain: SKIP (no test image)"
    FAILED=$((FAILED + 1))
    FAILED_STEPS+=("prescription upload chain (no test image)")
  fi
fi

# ── Summary ─────────────────────────────────────────────────────────
echo ""
echo "${BANNER}"
echo "REGRESSION SUMMARY"
echo "${BANNER}"
echo "  passed: ${PASSED}   failed: ${FAILED}   finished: $(date '+%H:%M:%S')"
if [[ ${#FAILED_STEPS[@]} -gt 0 ]]; then
  echo ""
  echo "  Failed steps:"
  for s in "${FAILED_STEPS[@]}"; do
    echo "    ✗ ${s}"
  done
  echo ""
  echo "RESULT: FAILED"
  exit 1
fi
echo ""
echo "RESULT: ALL PASSED"
exit 0
