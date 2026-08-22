#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"
mkdir -p logs

export LIVE_VIS_EVERY="${LIVE_VIS_EVERY:-1}"
export LIVE_VIS_RECORD_ENABLE="${LIVE_VIS_RECORD_ENABLE:-1}"
export LIVE_VIS_RECORD_EVERY="${LIVE_VIS_RECORD_EVERY:-100}"
export LIVE_VIS_RECORD_FIELDS="${LIVE_VIS_RECORD_FIELDS:-mass}"
export LIVE_VIS_HOLD_ON_EXIT="${LIVE_VIS_HOLD_ON_EXIT:-1}"
export FILTER_SAMPLE_EVERY="${FILTER_SAMPLE_EVERY:-100}"
export LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
export LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-1}"

STATIC_ROOT="${STATIC_RUN_ROOT:-runs/0493x10o_q6_thermal_interface_static_s4500}"
DRIP_ROOT="${DRIP_RUN_ROOT:-runs/0493x10o_q6_thermal_interface_dripping_s4500_g01}"

echo "===== 0493x10o Q6 HYDRO + THERMAL INTERFACE DUAL QUALIFICATION ====="
echo "[0493x10o] centreline=continuous Q6-style alpha=.5"
echo "[0493x10o] wall velocity=projected Q6 hydrodynamic normal velocity only"
echo "[0493x10o] kinetic envelope delta=min(C*dt*sqrt(kBT/m), maxCells*h)"
echo "[0493x10o] C=${MPCD_X10O_THERMAL_SIGMAS:-3.0} maxCells=${MPCD_X10O_THERMAL_MAX_CELLS:-0.75}"
echo "[0493x10o] no B8/global reaction; interface impulse diagnostic only"
echo "[0493x10o] static=${STATIC_STEPS:-800}; dripping=${DRIP_STEPS:-3000}"
echo "[0493x10o] liveEvery=$LIVE_VIS_EVERY recordEvery=$LIVE_VIS_RECORD_EVERY recordFields=$LIVE_VIS_RECORD_FIELDS filterSampleEvery=$FILTER_SAMPLE_EVERY hold=$LIVE_VIS_HOLD_ON_EXIT"

echo
echo "===== STATIC DROP ====="
RUN_ROOT="$STATIC_ROOT" \
SIGMA_ACTIVE="${STATIC_SIGMA_ACTIVE:-4500}" \
STEPS="${STATIC_STEPS:-10}" \
SUMMARY_EVERY="${STATIC_SUMMARY_EVERY:-25}" \
CLEAN_RUN_ROOT=1 \
bash scripts/run_0493x10o_q6_thermal_interface_static_drop.sh \
2>&1 | tee logs/0493x10o_q6_thermal_interface_static.log

echo
echo "===== DRIPPING ====="
RUN_ROOT="$DRIP_ROOT" \
SIGMA_ACTIVE="${DRIP_SIGMA_ACTIVE:-4500}" \
GRAVITY_Y="${DRIP_GRAVITY_Y:--0.1}" \
STEPS="${DRIP_STEPS:-3000}" \
SUMMARY_EVERY="${DRIP_SUMMARY_EVERY:-25}" \
CLEAN_RUN_ROOT=1 \
bash scripts/run_0493x10o_q6_thermal_interface_dripping.sh \
2>&1 | tee logs/0493x10o_q6_thermal_interface_dripping.log
