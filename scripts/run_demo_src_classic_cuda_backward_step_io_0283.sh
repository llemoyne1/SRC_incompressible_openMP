#!/usr/bin/env bash
set -euo pipefail
# 0303: resampling-capable demo wrapper.  RESAMPLING_ENABLE=0 keeps the
# classic CUDA path while preserving the passive survey for diagnostics.
BIN="${BIN:-build/src_mpcd_base_cuda_0303}"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/src_gpu_demo_common_0283.sh"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/src_gpu_resampling_demo_common_0303.sh"

CASE_NAME="backward_step_io"
Lx="${Lx:-3.0}"; Ly="${Ly:-1.0}"; NX="${NX:-86}"; NY="${NY:-32}"
GAMMA="${GAMMA:-20}"; STEPS="${STEPS:-75000}"; DT="${DT:-0.0001}"; KBT="${KBT:-0.1}"
SEED="${SEED:-1628304}"; SUMMARY_EVERY="${SUMMARY_EVERY:-100}"; DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-100}"
UIN="${UIN:-3.0}"
UINIT="${UINIT:-0.0}"
STEP_XMIN="${STEP_XMIN:-0.0}"; STEP_XMAX="${STEP_XMAX:-0.5}"; STEP_YMIN="${STEP_YMIN:-0.0}"; STEP_YMAX="${STEP_YMAX:-0.42}"
BASE_RUN_ROOT="${BASE_RUN_ROOT:-runs/demo_src_resampling_cuda_${CASE_NAME}_0303}"
RUN_ROOT="${RUN_ROOT:-$(resampling_demo_root_0303 "$CASE_NAME" "$BASE_RUN_ROOT")}"
prepare_demo_dirs_0283 "$RUN_ROOT"
STATE_FILE="$RUN_ROOT/init/${CASE_NAME}_${NX}x${NY}_g${GAMMA}.smpcd"
PARAMS_FILE="$RUN_ROOT/params/${CASE_NAME}.kv"
OUT_DIR="$RUN_ROOT/output"
LOG_FILE="$RUN_ROOT/logs/${CASE_NAME}.log"
TIME_FILE="$RUN_ROOT/logs/${CASE_NAME}.time"
INACTIVE_SLOTS="${INACTIVE_SLOTS:-$((GAMMA * NY * 8))}"

generate_demo_state_0283 "$STATE_FILE" "$Lx" "$Ly" "$NX" "$NY" "$GAMMA" "$KBT" "$SEED" uniform "$UINIT" 0.0 0.0 0.0 -1.0 0.0 -1.0 "$INACTIVE_SLOTS" "rect:${STEP_XMIN},${STEP_XMAX},${STEP_YMIN},${STEP_YMAX}"
mkdir -p "$OUT_DIR"
cat > "$PARAMS_FILE" <<PARAMS
inputState = ${STATE_FILE}
outputDir = ${OUT_DIR}

Lx = ${Lx}
Ly = ${Ly}
Nx = ${NX}
Ny = ${NY}

bcLeft = inlet
bcRight = outlet
bcBottom = solid
bcTop = solid

bodyAccelerationX = 0.0
bodyAccelerationY = 0.0
taylorGreenForcingEnable = false

inletUxLeft = ${UIN}
inletUyLeft = 0.0
inletVelocityRampEnable = true
inletVelocityRampStartTime = 0.0
inletVelocityRampEndTime = 0.25
inletVelocityRampInitialFactor = 0.2
inletVelocityRampFinalFactor = 1.0
inletVelocityRampProfile = smoothstep
inletVelocitySpatialProfile = flat_taper_y
inletVelocityWallTaperCells = 2.0
inletKBT = -1.0
inletThermalNoise = 0.0
inletInjectionMode = hard_cell_density
inletReservoirMode = hard_cell_density
inletReservoirCells = 3
inletTargetOccupancy = ${GAMMA}
inletHardCellVelocityMean = true
inletHardCellThermalRescale = true
inletRandomizeTangential = true
inletReinjectBackflow = true

openBoundaryOutletMode = hybrid
openBoundaryOutletHybridBlend = 0.0
openBoundaryOutletFeedbackGain = 0.0

immersedSolidEnable = true
immersedSolidShape = rectangle
immersedSolidXMin = ${STEP_XMIN}
immersedSolidXMax = ${STEP_XMAX}
immersedSolidYMin = ${STEP_YMIN}
immersedSolidYMax = ${STEP_YMAX}
immersedSolidFractionSamples = 4
immersedSolidVx = 0.0
immersedSolidVy = 0.0
immersedSolidWallUx = 0.0
immersedSolidWallUy = 0.0
immersedSolidOmega = 0.0

wallAccommodation = 1.0
wallVpGamma = ${GAMMA}
wallVpMass = 1.0
wallKBT = -1.0
wallThermalNoise = 0.0

$(write_src_classic_common_params_0283 "$STEPS" "$DT" "$KBT" "$SEED" "$SUMMARY_EVERY" "$DUMP_STATE_EVERY" "$THREADS" 1.5)
PARAMS

src_gpu_cuda_env_io_fullface_resident_thermostat_0283
src_gpu_resampling_env_0303
write_resampling_demo_metadata_0303 "$RUN_ROOT/logs/resampling_0303.env"
print_resampling_demo_banner_0303 "$CASE_NAME" "$RUN_ROOT"
run_demo_case_0283 "$PARAMS_FILE" "$LOG_FILE" "$TIME_FILE" "$OUT_DIR"
