#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"

export RUN_ROOT="${RUN_ROOT:-runs/0493x10g_global_reduction_perf}"
export STEPS="${STEPS:-800}"
export SUMMARY_EVERY="${SUMMARY_EVERY:-25}"
export LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
export LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-1}"
export LIVE_VIS_HOLD_ON_EXIT="${LIVE_VIS_HOLD_ON_EXIT:-0}"
export FILTERED_RECORDING_ENABLE="${FILTERED_RECORDING_ENABLE:-0}"
export CLEAN_RUN_ROOT="${CLEAN_RUN_ROOT:-1}"

printf '%s\n' \
  "[0493x10g-suite] PERFORMANCE ONLY: x10f global reaction equations/particle paths unchanged" \
  "[0493x10g-suite] reduction=cell-block partials -> one GPU block -> existing x10f finalizer" \
  "[0493x10g-suite] no new particle pass; no host reduction; no physics/configuration change" \
  "[0493x10g-suite] baseline x10f observed by user: 800 steps elapsed=146.04 s" \
  "[0493x10g-suite] kBT=0.125 r=1 LiveVis=$LIVE_VIS_ENABLE filteredRecording=$FILTERED_RECORDING_ENABLE"

bash scripts/run_0493x10f_global_reservoir_ablation.sh
