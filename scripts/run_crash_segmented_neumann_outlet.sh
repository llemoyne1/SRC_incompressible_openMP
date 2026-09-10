#!/usr/bin/env bash
set -euo pipefail
set -o pipefail

# 0493x9e-fix3 — simple crash-test for a genuinely segmented Neumann outlet.
#
# Geometry inherited from run_ok_air_assisted_atomizer.sh.
# Only the right outlet is changed from full-face to a partial segment:
#
#       right face
#       wall
#       -----
#       Neumann outlet   s in [OUTLET_SMIN, OUTLET_SMAX]
#       -----
#       wall
#
# On the right face, s is the normalized tangential coordinate y/Ly.
#
# Purpose:
#   - exercise the resident segmented boundary path;
#   - exercise x9c phase continuation + x9e/fix3 recycle/targeted repair;
#   - detect crashes/fallbacks quickly;
#   - NOT a physical qualification.
#
# Every default below can be overridden from the environment.

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
BASE_RUNNER="${BASE_RUNNER:-$ROOT/scripts/run_ok_air_assisted_atomizer.sh}"

[[ -x "$BASE_RUNNER" || -f "$BASE_RUNNER" ]] || {
  echo "[seg-neumann-crash] ERROR missing base runner: $BASE_RUNNER" >&2
  exit 2
}

# --- Small, square-cell test domain ------------------------------------------------
export Lx="${Lx:-0.78125}"
export Ly="${Ly:-1.5625}"
export NX="${NX:-200}"
export NY="${NY:-400}"
export STEPS="${STEPS:-250}"
export SEED="${SEED:-493215}"

# --- Segmented Neumann outlet -------------------------------------------------------
export OUTLET_MODE=neumann
export OUTLET_SMIN="${OUTLET_SMIN:-0.25}"
export OUTLET_SMAX="${OUTLET_SMAX:-0.75}"

python3 - "$OUTLET_SMIN" "$OUTLET_SMAX" <<'PY'
import sys
s0, s1 = map(float, sys.argv[1:3])
if not (0.0 <= s0 < s1 <= 1.0):
    raise SystemExit(
        f"[seg-neumann-crash] ERROR expected 0 <= OUTLET_SMIN < OUTLET_SMAX <= 1, got {s0}, {s1}"
    )
PY

# --- Qualified optimized Neumann implementation -----------------------------------
export NEUMANN_PROFILE="${NEUMANN_PROFILE:-x9e}"

# --- Keep the crash-test cheap and deterministic ----------------------------------
export LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
export LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-1}"
export LIVE_VIS_HOLD_ON_EXIT="${LIVE_VIS_HOLD_ON_EXIT:-1}"
export RECORD_ENABLE="${RECORD_ENABLE:-true}"
export FILTERED_RECORDING_ENABLE="${FILTERED_RECORDING_ENABLE:-1}"
export ANALYZE_ENABLE="${ANALYZE_ENABLE:-0}"
export DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-1000}"
export CLEAN_RUN_ROOT="${CLEAN_RUN_ROOT:-1}"

export CASE_LABEL="${CASE_LABEL:-0493x9e_fix3_segmented_neumann_crash}"

CAPTURE_LOG="${CAPTURE_LOG:-/tmp/${CASE_LABEL}.console.log}"

echo "[seg-neumann-crash] baseRunner=$BASE_RUNNER"
echo "[seg-neumann-crash] grid=${NX}x${NY} L=${Lx}x${Ly} steps=${STEPS} seed=${SEED}"
echo "[seg-neumann-crash] rightOutlet s=[${OUTLET_SMIN},${OUTLET_SMAX}] profile=${NEUMANN_PROFILE}"
echo "[seg-neumann-crash] consoleLog=$CAPTURE_LOG"

bash "$BASE_RUNNER" 2>&1 | tee "$CAPTURE_LOG"

echo
echo "[seg-neumann-crash] ---- key markers ----"
grep -E \
  '0493x9e-neumann|0493x9e-fastpath|0493x9e-fallback|step=[0-9]+/[0-9]+|done' \
  "$CAPTURE_LOG" | tail -20 || true

if ! grep -Fq "[src_mpcd_base] done" "$CAPTURE_LOG"; then
  echo "[seg-neumann-crash] FAIL: solver did not reach done" >&2
  exit 3
fi

if grep -Fq "[0493x9e-fallback]" "$CAPTURE_LOG"; then
  echo "[seg-neumann-crash] REVIEW: x9e/fix3 fell back to 0315c at least once" >&2
  exit 4
fi

if [[ "$NEUMANN_PROFILE" == "x9e" ]] &&
   ! grep -Fq "[0493x9e-fastpath] prefixRepair=targeted_deleted_list_exact" "$CAPTURE_LOG"; then
  echo "[seg-neumann-crash] REVIEW: expected x9e/fix3 fast-path marker was not observed" >&2
  exit 5
fi

echo "[seg-neumann-crash] PASS: segmented Neumann crash-test completed without x9e fallback"
