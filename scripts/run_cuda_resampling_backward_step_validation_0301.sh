#!/usr/bin/env bash
set -euo pipefail

# 0301 — isolated backward-step validation case for long CUDA resampling tests.
#
# This script is self-contained and does not modify the older 0283 demo script.
# It intentionally keeps the validated full-face inlet/outlet + immersed
# rectangle CUDA path, while exposing long-run and velocity parameters for the
# support-control sweep.

BIN="${BIN:-build/src_mpcd_base_cuda_0301}"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/src_gpu_demo_common_0283.sh"

if [[ ! -x "$BIN" ]]; then
  echo "[0301-step] building $BIN with build_src_mpcd_cuda_0301.sh"
  OUT="$BIN" CUDA_ARCH_FLAGS="${CUDA_ARCH_FLAGS:-}" bash scripts/build_src_mpcd_cuda_0301.sh
fi
AUTO_BUILD=0

CASE_NAME="backward_step_resampling_validation_0301"
Lx="${Lx:-3.0}"; Ly="${Ly:-1.0}"; NX="${NX:-96}"; NY="${NY:-48}"
GAMMA="${GAMMA:-20}"; STEPS="${STEPS:-3000}"; DT="${DT:-0.0008}"; KBT="${KBT:-0.001}"
SEED="${SEED:-1628304}"; SUMMARY_EVERY="${SUMMARY_EVERY:-100}"; DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-1000}"
UIN="${UIN:-0.45}"
STEP_XMIN="${STEP_XMIN:-0.0}"; STEP_XMAX="${STEP_XMAX:-0.75}"; STEP_YMIN="${STEP_YMIN:-0.0}"; STEP_YMAX="${STEP_YMAX:-0.42}"
RUN_ROOT="${RUN_ROOT:-runs/cuda_resampling_backward_step_validation_0301}"
OUTLET_MODE="${OUTLET_MODE:-hybrid}"
OUTLET_HYBRID_BLEND="${OUTLET_HYBRID_BLEND:-0.0}"
OUTLET_FEEDBACK_GAIN="${OUTLET_FEEDBACK_GAIN:-0.0}"
INLET_RAMP_END_TIME="${INLET_RAMP_END_TIME:-0.25}"
INLET_RAMP_INITIAL_FACTOR="${INLET_RAMP_INITIAL_FACTOR:-0.2}"
INACTIVE_SLOTS="${INACTIVE_SLOTS:-$((GAMMA * NY * 8))}"

prepare_demo_dirs_0283 "$RUN_ROOT"
STATE_FILE="$RUN_ROOT/init/${CASE_NAME}_${NX}x${NY}_g${GAMMA}_uin${UIN}.smpcd"
PARAMS_FILE="$RUN_ROOT/params/${CASE_NAME}.kv"
OUT_DIR="$RUN_ROOT/output"
LOG_FILE="$RUN_ROOT/logs/${CASE_NAME}.log"
TIME_FILE="$RUN_ROOT/logs/${CASE_NAME}.time"

generate_demo_state_0283 "$STATE_FILE" "$Lx" "$Ly" "$NX" "$NY" "$GAMMA" "$KBT" "$SEED" uniform "$UIN" 0.0 0.0 0.0 -1.0 0.0 -1.0 "$INACTIVE_SLOTS" "rect:${STEP_XMIN},${STEP_XMAX},${STEP_YMIN},${STEP_YMAX}"
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
keepMeanFlowEnable = false

inletUxLeft = ${UIN}
inletUyLeft = 0.0
inletVelocityRampEnable = true
inletVelocityRampStartTime = 0.0
inletVelocityRampEndTime = ${INLET_RAMP_END_TIME}
inletVelocityRampInitialFactor = ${INLET_RAMP_INITIAL_FACTOR}
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

openBoundaryOutletMode = ${OUTLET_MODE}
openBoundaryOutletHybridBlend = ${OUTLET_HYBRID_BLEND}
openBoundaryOutletFeedbackGain = ${OUTLET_FEEDBACK_GAIN}

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
run_demo_case_0283 "$PARAMS_FILE" "$LOG_FILE" "$TIME_FILE" "$OUT_DIR"
