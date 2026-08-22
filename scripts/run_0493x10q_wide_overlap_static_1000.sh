#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"
mkdir -p logs

export MPCD_X10P_INITIAL_OVERLAP_RESOLUTION=1
export LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
export LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-1}"
export LIVE_VIS_EVERY="${LIVE_VIS_EVERY:-1}"
export LIVE_VIS_RECORD_ENABLE="${LIVE_VIS_RECORD_ENABLE:-1}"
export LIVE_VIS_RECORD_EVERY="${LIVE_VIS_RECORD_EVERY:-100}"
export LIVE_VIS_RECORD_FIELDS="${LIVE_VIS_RECORD_FIELDS:-mass}"
export LIVE_VIS_HOLD_ON_EXIT="${LIVE_VIS_HOLD_ON_EXIT:-1}"
export FILTER_SAMPLE_EVERY="${FILTER_SAMPLE_EVERY:-100}"

RUN_ROOT="${RUN_ROOT:-runs/0493x10q_wide_overlap_static_s4500_1000}"
export RUN_ROOT

echo '===== 0493x10q STATIC 1000 / WIDE OVERLAP RECOVERY ====='
echo '[0493x10q] normal swept broad phase=3x3; initial-overlap fallback=outer ring to 7x7'
echo '[0493x10q] known s0>0 overlap is always resolved; 2.5h is diagnostic only'
echo "[0493x10q] liveEvery=$LIVE_VIS_EVERY recordEvery=$LIVE_VIS_RECORD_EVERY fields=$LIVE_VIS_RECORD_FIELDS filterSampleEvery=$FILTER_SAMPLE_EVERY"

STEPS="${STEPS:-1000}" \
SUMMARY_EVERY="${SUMMARY_EVERY:-25}" \
DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-100}" \
CLEAN_RUN_ROOT="${CLEAN_RUN_ROOT:-1}" \
bash scripts/run_0493x10o_q6_thermal_interface_static_drop.sh \
2>&1 | tee logs/0493x10q_wide_overlap_static_1000.log

CSV="$RUN_ROOT/output/cuda_phase_kinetic_crossing_0493x9z.csv"
python3 scripts/analyze_0493x10q_wide_overlap.py "$CSV"
