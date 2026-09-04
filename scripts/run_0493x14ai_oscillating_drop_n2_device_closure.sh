#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"
BASE="$ROOT/scripts/run_ok_0493x14x_two_phase_oscillating_drop_n2.sh"
SRC="$ROOT/src/cuda_q6_resident_0400.cu"
[[ -x "$BASE" || -f "$BASE" ]] || { echo "[0493x14ai-n2] missing $BASE" >&2; exit 2; }
grep -q '0493x14ai — production-candidate device-side Q6 resultant closure' "$SRC" || { echo '[0493x14ai-n2] x14ai source marker missing' >&2; exit 2; }

export MPCD_X14V_GAS_KINETIC_EXCESS_KICK=1
export MPCD_X14V_SUBTRACT_X6G_THERMODYNAMIC_TRACTION=1
export MPCD_X14V_X6G_FACE_THERMO_TRACTION=0
export MPCD_X14V_X6G_GAUGE_FACE_THERMO_TRACTION=0
export MPCD_X14V_X6G_GAUGE_RESULTANT_PROJECTION=0
export MPCD_X14V_X6G_LOCAL_FACE_GAUGE_PROJECTION=1
export MPCD_X14V_REFERENCE_PRESSURE_GEOMETRIC_CLOSURE=0
export MPCD_X14V_SCATTER_LOSS_DIAGNOSTIC=0
export MPCD_X14V_GLOBAL_BALANCE_DIAGNOSTIC="${MPCD_X14V_GLOBAL_BALANCE_DIAGNOSTIC:-0}"
export MPCD_X14V_DEVICE_APPLIED_Q6_RESULTANT_CLOSURE=1

CASE_LABEL="${CASE_LABEL:-0493x14ai_n2_device_q6_resultant_closure}"
SEED="${SEED:-493180}"
CAMPAIGN_ROOT="${CAMPAIGN_ROOT:-runs/0493x14ai_n2_device_q6_resultant_closure_seed${SEED}}"
STEPS="${STEPS:-2000}"
SUMMARY_EVERY="${SUMMARY_EVERY:-10}"
DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-1000}"
LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-1}"
LIVE_VIS_EVERY="${LIVE_VIS_EVERY:-1}"
LIVE_VIS_HOLD_ON_EXIT="${LIVE_VIS_HOLD_ON_EXIT:-1}"
FILTERED_RECORDING_ENABLE="${FILTERED_RECORDING_ENABLE:-1}"
RECORD_ENABLE="${RECORD_ENABLE:-true}"
RECORD_EVERY="${RECORD_EVERY:-100}"
RECORD_FIELDS="${RECORD_FIELDS:-mass,ux,uy}"

export CASE_LABEL SEED CAMPAIGN_ROOT STEPS SUMMARY_EVERY DUMP_STATE_EVERY
export LIVE_VIS_ENABLE LIVE_VIS_EVERY LIVE_VIS_HOLD_ON_EXIT
export FILTERED_RECORDING_ENABLE RECORD_ENABLE RECORD_EVERY RECORD_FIELDS

echo "===== 0493x14ai n=2 DEVICE Q6 RESULTANT CLOSURE ====="
echo "PATHS: runner=$ROOT/scripts/run_0493x14ai_oscillating_drop_n2_device_closure.sh"
echo "       base=$BASE"
echo "CHAIN: x14ad local pressure + x14ai exact B1 device resultant target"
echo "COST:  +16 B O(1), no new kernel/pass/host transfer/second CG"
echo "RUN:   steps=$STEPS summaryEvery=$SUMMARY_EVERY campaign=$CAMPAIGN_ROOT"
echo "VIS:   enable=$LIVE_VIS_ENABLE recorderBackend=$FILTERED_RECORDING_ENABLE record=$RECORD_ENABLE"
echo "====================================================="

bash "$BASE"
