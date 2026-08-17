#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"
SIGMAS="${SIGMAS:-0 256 512}"
SEED="${SEED:-493904}"
RX_CELLS="${RX_CELLS:-50}"
RY_CELLS="${RY_CELLS:-32}"
STEPS="${STEPS:-500}"
for SIGMA in $SIGMAS; do
  BASE_RUN_ROOT="runs/0493x9f_ellipse_relaxation/seed${SEED}_sigma${SIGMA}" \
  SEED="$SEED" SIGMA="$SIGMA" RX_CELLS="$RX_CELLS" RY_CELLS="$RY_CELLS" \
  STEPS="$STEPS" SUMMARY_EVERY=1 LIVE_PROGRESS=1 LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-1}" \
  LIVE_VIS_HOLD_ON_EXIT=0 FILTERED_RECORDING_ENABLE=0 \
  bash scripts/run_0493x9f_ellipse_relaxation.sh
done
