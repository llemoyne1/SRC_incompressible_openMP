#!/usr/bin/env bash
# 0493x16n — qualify the explicit continuous piecewise-Q2 owner convention.
# No new physics model: fixed-curved stress test + complete x16m mobile suite.
set -euo pipefail
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"
BASE="${BASE_RUN_ROOT:-runs/0493x16n_q2_dual_square_qualification}"
STATIC_STEPS="${STATIC_STEPS:-800}"
FULL_STEPS="${FULL_STEPS:-600}"
LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-1}"

if ! grep -q 'q2Owner=x16n-dual-square-clipped' src/cuda_q6_resident_0400.cu; then
  echo '[0493x16n] ERROR source marker absent' >&2; exit 2
fi

rm -rf "$BASE"
mkdir -p "$BASE"

echo "[0493x16n] phase=static-curved steps=$STATIC_STEPS"
BASE_RUN_ROOT="$BASE/static_curved" \
STEPS="$STATIC_STEPS" \
LIVE_VIS_ENABLE="$LIVE_VIS_ENABLE" \
bash scripts/run_0493x16m_static_curved_characterization.sh

echo "[0493x16n] phase=full-mobile steps=$FULL_STEPS"
set +e
BASE_RUN_ROOT="$BASE/full_mobile" \
STEPS="$FULL_STEPS" \
LIVE_VIS_ENABLE="$LIVE_VIS_ENABLE" \
bash scripts/run_0493x16m_q2_root_refinement_qualification.sh
full_rc=$?
set -e
if (( full_rc != 0 && full_rc != 3 )); then
  echo "[0493x16n] ERROR full-mobile execution failed rc=$full_rc" >&2
  exit "$full_rc"
fi

python3 scripts/analyze_0493x16n_q2_dual_square_qualification.py "$BASE"
