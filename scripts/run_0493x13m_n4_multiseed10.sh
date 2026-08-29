#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"

for SEED in 4931401 4931402 4931403 4931404 4931405 4931406 4931407 4931408 4931409 4931410; do
  echo
  echo "===== 0493x13m n=4 epsilon=0.04 seed=${SEED} ====="
  MODE=4 \
  EPSILON=0.04 \
  SEED="$SEED" \
  STEPS=200 \
  SUMMARY_EVERY=5 \
  DUMP_STATE_EVERY=5 \
  FIT_PERIODS=2.5 \
  RUN_ROOT="runs/0493x13m_oscillating_drop_n4_x13h_s10000_n4_r40_eps0.04_seed${SEED}" \
  CLEAN_RUN_ROOT=1 \
  LIVE_PROGRESS=1 \
  LIVE_VIS_ENABLE=0 \
  LIVE_VIS_HOLD_ON_EXIT=0 \
  LIVE_VIS_RECORD_ENABLE=0 \
  FILTERED_RECORDING_ENABLE=0 \
  bash scripts/run_0493x13m_oscillating_drop_n4_x13h.sh
done
