#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"
mkdir -p logs

for B in 4 5; do
  echo
  echo "===== 0493x10i B=${B}x${B} ====="
  MPCD_X10I_REACTION_BLOCK_CELLS="$B" \
  RUN_ROOT="runs/0493x10i_mesoscopic_drop_b${B}" \
  LIVE_PROGRESS="${LIVE_PROGRESS:-1}" \
  LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-1}" \
  LIVE_VIS_HOLD_ON_EXIT=0 \
  FILTERED_RECORDING_ENABLE=0 \
  STEPS="${STEPS:-800}" \
  SUMMARY_EVERY="${SUMMARY_EVERY:-25}" \
  CLEAN_RUN_ROOT=1 \
  bash scripts/run_0493x10i_mesoscopic_drop.sh \
    2>&1 | tee "logs/0493x10i_mesoscopic_drop_b${B}.log"
done
