#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"
mkdir -p logs

echo "===== 0493x10k DUAL QUALIFICATION: STATIC THEN DRIPPING ====="
echo "[0493x10k] local-liquid-frame reflection; no B8/global receiver reaction"
echo "[0493x10k] sequential on one GPU; close LiveVis after static to continue"

echo
echo "===== STATIC DROP ====="
RUN_ROOT="${STATIC_RUN_ROOT:-runs/0493x10k_local_frame_specular_static_s4500}" \
SIGMA_ACTIVE="${STATIC_SIGMA_ACTIVE:-4500}" \
STEPS="${STATIC_STEPS:-800}" \
SUMMARY_EVERY="${STATIC_SUMMARY_EVERY:-25}" \
LIVE_PROGRESS=1 LIVE_VIS_ENABLE=1 \
LIVE_VIS_EVERY="${LIVE_VIS_EVERY:-100}" \
LIVE_VIS_RECORD_ENABLE="${LIVE_VIS_RECORD_ENABLE:-1}" \
LIVE_VIS_RECORD_EVERY="${LIVE_VIS_RECORD_EVERY:-100}" \
LIVE_VIS_RECORD_FIELDS="${LIVE_VIS_RECORD_FIELDS:-mass}" \
LIVE_VIS_HOLD_ON_EXIT="${LIVE_VIS_HOLD_ON_EXIT:-1}" \
FILTER_SAMPLE_EVERY="${FILTER_SAMPLE_EVERY:-100}" \
bash scripts/run_0493x10k_local_frame_specular_static_drop.sh \
2>&1 | tee logs/0493x10k_local_frame_specular_static.log

echo
echo "===== DRIPPING ====="
RUN_ROOT="${DRIP_RUN_ROOT:-runs/0493x10k_local_frame_specular_dripping_s4500_g01}" \
SIGMA_ACTIVE="${DRIP_SIGMA_ACTIVE:-4500}" \
GRAVITY_Y="${DRIP_GRAVITY_Y:--0.1}" \
STEPS="${DRIP_STEPS:-8000}" \
SUMMARY_EVERY="${DRIP_SUMMARY_EVERY:-25}" \
LIVE_PROGRESS=1 LIVE_VIS_ENABLE=1 \
LIVE_VIS_EVERY="${LIVE_VIS_EVERY:-100}" \
LIVE_VIS_RECORD_ENABLE="${LIVE_VIS_RECORD_ENABLE:-1}" \
LIVE_VIS_RECORD_EVERY="${LIVE_VIS_RECORD_EVERY:-100}" \
LIVE_VIS_RECORD_FIELDS="${LIVE_VIS_RECORD_FIELDS:-mass}" \
LIVE_VIS_HOLD_ON_EXIT="${LIVE_VIS_HOLD_ON_EXIT:-1}" \
FILTER_SAMPLE_EVERY="${FILTER_SAMPLE_EVERY:-100}" \
bash scripts/run_0493x10k_local_frame_specular_dripping.sh \
2>&1 | tee logs/0493x10k_local_frame_specular_dripping.log
