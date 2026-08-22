#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"

export MPCD_X10P_INITIAL_OVERLAP_RESOLUTION=1
export LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
export LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-1}"
export LIVE_VIS_HOLD_ON_EXIT=0
export LIVE_VIS_RECORD_ENABLE=0

RUN_ROOT="${RUN_ROOT:-runs/0493x10p_initial_overlap_static_5step}"
export RUN_ROOT

STEPS="${STEPS:-1000}" \
SUMMARY_EVERY="${SUMMARY_EVERY:-1}" \
DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-100}" \
CLEAN_RUN_ROOT="${CLEAN_RUN_ROOT:-1}" \
bash scripts/run_0493x10o_q6_thermal_interface_static_drop.sh

CSV="$RUN_ROOT/output/cuda_phase_kinetic_crossing_0493x9z.csv"
python3 scripts/analyze_0493x10p_initial_overlap.py "$CSV"
