#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/src_gpu_demo_common_0283.sh"

CASE_NAME="von_karman_cylinder"
Lx="${Lx:-3.0}"; Ly="${Ly:-1.0}"; NX="${NX:-192}"; NY="${NY:-64}"
GAMMA="${GAMMA:-20}"; STEPS="${STEPS:-5000}"; DT="${DT:-0.0005}"; KBT="${KBT:-0.001}"
SEED="${SEED:-1628305}"; SUMMARY_EVERY="${SUMMARY_EVERY:-100}"; DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-100}"
UIN="${UIN:-0.08}"; CYLINDER_CX="${CYLINDER_CX:-0.65}"; CYLINDER_CY="${CYLINDER_CY:-0.50}"; CYLINDER_R="${CYLINDER_R:-0.12}"
RUN_ROOT="${RUN_ROOT:-runs/demo_src_classic_cuda_von_karman_cylinder_0283}"
prepare_demo_dirs_0283 "$RUN_ROOT"
STATE_FILE="$RUN_ROOT/init/${CASE_NAME}_${NX}x${NY}_g${GAMMA}.smpcd"
PARAMS_FILE="$RUN_ROOT/params/${CASE_NAME}.kv"
OUT_DIR="$RUN_ROOT/output"
LOG_FILE="$RUN_ROOT/logs/${CASE_NAME}.log"
TIME_FILE="$RUN_ROOT/logs/${CASE_NAME}.time"
INACTIVE_SLOTS="${INACTIVE_SLOTS:-$((GAMMA * NY * 8))}"

generate_demo_state_0283 "$STATE_FILE" "$Lx" "$Ly" "$NX" "$NY" "$GAMMA" "$KBT" "$SEED" uniform "$UIN" 0.0 0.0 0.0 -1.0 0.0 -1.0 "$INACTIVE_SLOTS" "circle:${CYLINDER_CX},${CYLINDER_CY},${CYLINDER_R}"
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
immersedSolidShape = circle
immersedSolidCx = ${CYLINDER_CX}
immersedSolidCy = ${CYLINDER_CY}
immersedSolidR = ${CYLINDER_R}
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

cat >&2 <<'NOTE'
[0283-demo] Note: circular immersed-solid reflection currently remains on the CPU path;
[0283-demo] the script still runs SRC classic only, with CUDA SRC collision and CUDA thermostat.
[0283-demo] Rectangle/step demos exercise the resident CUDA immersed-rectangle path.
NOTE
src_gpu_cuda_env_circle_boundary_cpu_collision_cuda_0283
run_demo_case_0283 "$PARAMS_FILE" "$LOG_FILE" "$TIME_FILE" "$OUT_DIR"
