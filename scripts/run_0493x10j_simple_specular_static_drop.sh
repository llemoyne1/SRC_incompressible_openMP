#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"

export MPCD_X10J_SIMPLE_SPECULAR_ABLATION=1
export TARGET=wall
export RUN_ROOT="${RUN_ROOT:-runs/0493x10j_simple_specular_static_s4500}"
export GAMMA="${GAMMA:-20}"
export DT="${DT:-0.002}"
export KBT="${KBT:-0.125}"
export LIQUID_MASS="${LIQUID_MASS:-1.0}"
export SIGMA_ACTIVE="${SIGMA_ACTIVE:-4500.0}"
export SURFACE_TENSION_MIN_RADIUS_CELLS="${SURFACE_TENSION_MIN_RADIUS_CELLS:-3}"
export KINETIC_REFLECTION_FRACTION=1.0
export EVAPORATION_TARGET_TYPE=-1
export DROP_RADIUS_CELLS="${DROP_RADIUS_CELLS:-40}"
export DROP_CENTER_X="${DROP_CENTER_X:-1.5625}"
export DROP_CENTER_Y="${DROP_CENTER_Y:-0.78125}"
export DROP_VX=0.0
export DROP_VY=0.0
export GRAVITY_Y=0.0
export STEPS="${STEPS:-800}"
export SUMMARY_EVERY="${SUMMARY_EVERY:-25}"
export DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-0}"
export LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
export LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-1}"
export LIVE_VIS_FIELD="${LIVE_VIS_FIELD:-mass}"
export CLEAN_RUN_ROOT="${CLEAN_RUN_ROOT:-1}"
# 0493x10j qualification defaults requested for future runners.
export LIVE_VIS_EVERY="${LIVE_VIS_EVERY:-100}"
export LIVE_VIS_RECORD_ENABLE="${LIVE_VIS_RECORD_ENABLE:-1}"
export LIVE_VIS_RECORD_EVERY="${LIVE_VIS_RECORD_EVERY:-100}"
export LIVE_VIS_RECORD_FIELDS="${LIVE_VIS_RECORD_FIELDS:-mass}"
export LIVE_VIS_HOLD_ON_EXIT="${LIVE_VIS_HOLD_ON_EXIT:-1}"
export FILTER_SAMPLE_EVERY="${FILTER_SAMPLE_EVERY:-100}"
export FILTERED_RECORDING_ENABLE="${FILTERED_RECORDING_ENABLE:-1}"
export OVERWRITE_LIVEVIS_CONTROL="${OVERWRITE_LIVEVIS_CONTROL:-1}"

# 0434 common-writer variable names.
if [[ "$LIVE_VIS_RECORD_ENABLE" == 1 || "$LIVE_VIS_RECORD_ENABLE" == true ]]; then
  export RECORD_ENABLE=true
else
  export RECORD_ENABLE=false
fi
export RECORD_EVERY="$LIVE_VIS_RECORD_EVERY"
export RECORD_FIELDS="$LIVE_VIS_RECORD_FIELDS"


echo "===== 0493x10j STATIC DROP / SIMPLE LAB SPECULAR ====="
echo "[0493x10j] sigma=$SIGMA_ACTIVE kBT=$KBT; no B8/global receiver reaction"
echo "[0493x10j] v' = v - 2(v.n)n; interface counter-impulse intentionally ignored"
echo "[0493x10j] liveEvery=$LIVE_VIS_EVERY recordEvery=$RECORD_EVERY recordFields=$RECORD_FIELDS filterSampleEvery=$FILTER_SAMPLE_EVERY hold=$LIVE_VIS_HOLD_ON_EXIT"

bash scripts/run_0493x9s_splash.sh
CSV="$RUN_ROOT/output/cuda_phase_kinetic_crossing_0493x9z.csv"
[[ -f "$CSV" ]] || { echo "[0493x10j] ERROR missing $CSV" >&2; exit 2; }
python3 scripts/analyze_0493x10j_simple_specular.py "$CSV"
