#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"
mkdir -p logs

# User-requested LiveVis/recording defaults.
export LIVE_VIS_EVERY="${LIVE_VIS_EVERY:-100}"
export LIVE_VIS_RECORD_ENABLE="${LIVE_VIS_RECORD_ENABLE:-1}"
export LIVE_VIS_RECORD_EVERY="${LIVE_VIS_RECORD_EVERY:-100}"
export LIVE_VIS_RECORD_FIELDS="${LIVE_VIS_RECORD_FIELDS:-mass}"
export LIVE_VIS_HOLD_ON_EXIT="${LIVE_VIS_HOLD_ON_EXIT:-1}"
export FILTER_SAMPLE_EVERY="${FILTER_SAMPLE_EVERY:-100}"
export LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
export LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-1}"
export MPCD_X10L_PREWALL_INTERFACE_DIAGNOSTICS=1

STATIC_ROOT="${STATIC_RUN_ROOT:-runs/0493x10l_prewall_static_s4500}"
DRIP_ROOT="${DRIP_RUN_ROOT:-runs/0493x10l_prewall_dripping_s4500_g01}"

echo "===== 0493x10l PASSIVE PRE-WALL DIAGNOSTICS ====="
echo "[0493x10l] no physics change; x10k remains active"
echo "[0493x10l] diagnostic location: post-Q6/B1, pre-kinetic-reflection"
echo "[0493x10l] static=${STATIC_STEPS:-200} steps; dripping=${DRIP_STEPS:-500} steps"
echo "[0493x10l] liveEvery=$LIVE_VIS_EVERY recordEvery=$LIVE_VIS_RECORD_EVERY recordFields=$LIVE_VIS_RECORD_FIELDS filterSampleEvery=$FILTER_SAMPLE_EVERY hold=$LIVE_VIS_HOLD_ON_EXIT"

echo
echo "===== STATIC DROP ====="
RUN_ROOT="$STATIC_ROOT" \
SIGMA_ACTIVE="${STATIC_SIGMA_ACTIVE:-4500}" \
STEPS="${STATIC_STEPS:-200}" \
SUMMARY_EVERY="${STATIC_SUMMARY_EVERY:-10}" \
CLEAN_RUN_ROOT=1 \
bash scripts/run_0493x10k_local_frame_specular_static_drop.sh \
2>&1 | tee logs/0493x10l_prewall_static.log

python3 scripts/analyze_0493x10l_prewall_interface.py \
  "$STATIC_ROOT/output/cuda_phase_kinetic_crossing_0493x9z.csv" \
  --mode static --dt "${DT:-0.002}"

echo
echo "===== DRIPPING ====="
RUN_ROOT="$DRIP_ROOT" \
SIGMA_ACTIVE="${DRIP_SIGMA_ACTIVE:-4500}" \
GRAVITY_Y="${DRIP_GRAVITY_Y:--0.1}" \
STEPS="${DRIP_STEPS:-500}" \
SUMMARY_EVERY="${DRIP_SUMMARY_EVERY:-10}" \
CLEAN_RUN_ROOT=1 \
bash scripts/run_0493x10k_local_frame_specular_dripping.sh \
2>&1 | tee logs/0493x10l_prewall_dripping.log

python3 scripts/analyze_0493x10l_prewall_interface.py \
  "$DRIP_ROOT/capillary/output/cuda_phase_kinetic_crossing_0493x9z.csv" \
  --mode dripping --dt "${DT:-0.002}"
