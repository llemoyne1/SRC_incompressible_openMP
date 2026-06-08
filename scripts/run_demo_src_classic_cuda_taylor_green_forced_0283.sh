#!/usr/bin/env bash
set -euo pipefail
# 0303: resampling-capable demo wrapper.  RESAMPLING_ENABLE=0 keeps the
# classic CUDA path while preserving the passive survey for diagnostics.
BIN="${BIN:-build/src_mpcd_base_cuda_0303}"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/src_gpu_demo_common_0283.sh"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/src_gpu_resampling_demo_common_0303.sh"

CASE_NAME="taylor_green_forced"
Lx="${Lx:-1.0}"; Ly="${Ly:-1.0}"; NX="${NX:-128}"; NY="${NY:-128}"
GAMMA="${GAMMA:-20}"; STEPS="${STEPS:-3000}"; DT="${DT:-0.001}"; KBT="${KBT:-0.001}"
SEED="${SEED:-1628301}"; SUMMARY_EVERY="${SUMMARY_EVERY:-100}"; DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-100}"
TG_U0="${TG_U0:-0.04}"; TG_FORCING_AMPLITUDE="${TG_FORCING_AMPLITUDE:-0.02}"
BASE_RUN_ROOT="${BASE_RUN_ROOT:-runs/demo_src_resampling_cuda_${CASE_NAME}_0303}"
RUN_ROOT="${RUN_ROOT:-$(resampling_demo_root_0303 "$CASE_NAME" "$BASE_RUN_ROOT")}"
prepare_demo_dirs_0283 "$RUN_ROOT"
STATE_FILE="$RUN_ROOT/init/${CASE_NAME}_${NX}x${NY}_g${GAMMA}.smpcd"
PARAMS_FILE="$RUN_ROOT/params/${CASE_NAME}.kv"
OUT_DIR="$RUN_ROOT/output"
LOG_FILE="$RUN_ROOT/logs/${CASE_NAME}.log"
TIME_FILE="$RUN_ROOT/logs/${CASE_NAME}.time"
INACTIVE_SLOTS="${INACTIVE_SLOTS:-$((GAMMA * NX * NY / 4))}"

generate_demo_state_0283 "$STATE_FILE" "$Lx" "$Ly" "$NX" "$NY" "$GAMMA" "$KBT" "$SEED" taylor_green 0.0 0.0 "$TG_U0" 0.0 -1.0 0.0 -1.0 "$INACTIVE_SLOTS" none
mkdir -p "$OUT_DIR"
cat > "$PARAMS_FILE" <<PARAMS
inputState = ${STATE_FILE}
outputDir = ${OUT_DIR}

Lx = ${Lx}
Ly = ${Ly}
Nx = ${NX}
Ny = ${NY}

bcLeft = periodic
bcRight = periodic
bcBottom = periodic
bcTop = periodic

bodyAccelerationX = 0.0
bodyAccelerationY = 0.0
taylorGreenForcingEnable = true
taylorGreenForcingAmplitude = ${TG_FORCING_AMPLITUDE}
taylorGreenForcingModeX = 1
taylorGreenForcingModeY = 1

$(write_src_classic_common_params_0283 "$STEPS" "$DT" "$KBT" "$SEED" "$SUMMARY_EVERY" "$DUMP_STATE_EVERY" "$THREADS")
PARAMS

src_gpu_cuda_env_periodic_resident_thermostat_0283
src_gpu_resampling_env_0303
write_resampling_demo_metadata_0303 "$RUN_ROOT/logs/resampling_0303.env"
print_resampling_demo_banner_0303 "$CASE_NAME" "$RUN_ROOT"
run_demo_case_0283 "$PARAMS_FILE" "$LOG_FILE" "$TIME_FILE" "$OUT_DIR"
