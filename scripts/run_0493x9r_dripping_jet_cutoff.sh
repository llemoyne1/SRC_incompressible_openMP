#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
export CASES="${CASES:-capillary}"
export SIGMA_ACTIVE="${SIGMA_ACTIVE:-9450.0}"
export GRAVITY_Y="${GRAVITY_Y:--0.05}"
export KBT="${KBT:-0.00000125}"
export SURFACE_TENSION_MIN_RADIUS_CELLS="${SURFACE_TENSION_MIN_RADIUS_CELLS:-3}"
export DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-5000}"
export VACUUM_BACKGROUND="${VACUUM_BACKGROUND:-1}"
 
export LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
export LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-1}"
export LIVE_VIS_HOLD_ON_EXIT="${LIVE_VIS_HOLD_ON_EXIT:-0}"
export FILTERED_RECORDING_ENABLE="${FILTERED_RECORDING_ENABLE:-1}"
echo "[0493x9r-suite] sigma=$SIGMA_ACTIVE gravityY=$GRAVITY_Y kBT=$KBT minRadiusCells=$SURFACE_TENSION_MIN_RADIUS_CELLS"
bash scripts/run_0493x9q_dripping_jet_potential.sh
CSV="runs/0493x9q_dripping_jet_potential/${CASES%% *}/output/cuda_surface_tension_limiter_0493x9r.csv"
if [[ -f "$CSV" ]]; then
  python3 scripts/analyze_0493x9r_limiter.py --csv "$CSV"
fi
