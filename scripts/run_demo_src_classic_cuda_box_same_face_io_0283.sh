#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/src_gpu_demo_common_0283.sh"

CASE_NAME="box_same_face_io"
Lx="${Lx:-1.0}"; Ly="${Ly:-1.0}"; NX="${NX:-96}"; NY="${NY:-96}"
GAMMA="${GAMMA:-20}"; STEPS="${STEPS:-3000}"; DT="${DT:-0.001}"; KBT="${KBT:-0.001}"
SEED="${SEED:-1628303}"; SUMMARY_EVERY="${SUMMARY_EVERY:-100}"; DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-100}"
UIN="${UIN:-0.08}"; UOUT="${UOUT:--0.08}"
# THERMOSTAT_ENABLE is read by src_gpu_demo_common_0283.sh and written to
# thermostatEnable in params.kv. It also gates CUDA thermostat environment flags.
THERMOSTAT_ENABLE="${THERMOSTAT_ENABLE:-1}"
OUTLET_MODE="${OUTLET_MODE:-neumann}"
OUTLET_FORCED_MASS_FLUX="${OUTLET_FORCED_MASS_FLUX:-0.0}"
OUTLET_FORCED_MASS_PER_STEP="${OUTLET_FORCED_MASS_PER_STEP:-0.0}"
OUTLET_FORCED_PARTICLE_FLUX="${OUTLET_FORCED_PARTICLE_FLUX:-0.0}"
OUTLET_FORCED_PARTICLES_PER_STEP="${OUTLET_FORCED_PARTICLES_PER_STEP:-0}"
OUTLET_FORCED_LAYER_CELLS="${OUTLET_FORCED_LAYER_CELLS:-3}"
RUN_ROOT="${RUN_ROOT:-runs/demo_src_classic_cuda_box_same_face_io_0283}"
prepare_demo_dirs_0283 "$RUN_ROOT"
STATE_FILE="$RUN_ROOT/init/${CASE_NAME}_${NX}x${NY}_g${GAMMA}.smpcd"
PARAMS_FILE="$RUN_ROOT/params/${CASE_NAME}.kv"
OUT_DIR="$RUN_ROOT/output"
LOG_FILE="$RUN_ROOT/logs/${CASE_NAME}.log"
TIME_FILE="$RUN_ROOT/logs/${CASE_NAME}.time"
INACTIVE_SLOTS="${INACTIVE_SLOTS:-$((GAMMA * NX * NY))}"

generate_demo_state_0283 "$STATE_FILE" "$Lx" "$Ly" "$NX" "$NY" "$GAMMA" "$KBT" "$SEED" zero 0.0 0.0 0.0 0.0 -1.0 0.0 -1.0 "$INACTIVE_SLOTS" none
mkdir -p "$OUT_DIR"
cat > "$PARAMS_FILE" <<PARAMS
inputState = ${STATE_FILE}
outputDir = ${OUT_DIR}

Lx = ${Lx}
Ly = ${Ly}
Nx = ${NX}
Ny = ${NY}

bcLeft = solid
bcRight = solid
bcBottom = solid
bcTop = solid

bodyAccelerationX = 0.0
bodyAccelerationY = 0.0
taylorGreenForcingEnable = false

openBoundarySegmentsEnable = true
openBoundarySegmentCount = 2
openBoundarySegment0 = left inlet 0.10 0.35 ${UIN} 0.0 0 1.0
openBoundarySegment1 = left outlet 0.65 0.90 ${UOUT} 0.0 0 1.0

inletVelocityRampEnable = true
inletVelocityRampStartTime = 0.0
inletVelocityRampEndTime = 0.25
inletVelocityRampInitialFactor = 0.2
inletVelocityRampFinalFactor = 1.0
inletVelocityRampProfile = smoothstep
inletVelocitySpatialProfile = uniform
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
openBoundaryOutletHybridBlend = 0.0
openBoundaryOutletFeedbackGain = 0.0
openBoundaryOutletForcedMassFlux = ${OUTLET_FORCED_MASS_FLUX}
openBoundaryOutletForcedMassPerStep = ${OUTLET_FORCED_MASS_PER_STEP}
openBoundaryOutletForcedParticleFlux = ${OUTLET_FORCED_PARTICLE_FLUX}
openBoundaryOutletForcedParticlesPerStep = ${OUTLET_FORCED_PARTICLES_PER_STEP}
openBoundaryOutletForcedLayerCells = ${OUTLET_FORCED_LAYER_CELLS}

wallAccommodation = 1.0
wallVpGamma = ${GAMMA}
wallVpMass = 1.0
wallKBT = -1.0
wallThermalNoise = 0.0
wallUxLeft = 0.0
wallUyLeft = 0.0
wallUxRight = 0.0
wallUyRight = 0.0
wallUxBottom = 0.0
wallUyBottom = 0.0
wallUxTop = 0.0
wallUyTop = 0.0

$(write_src_classic_common_params_0283 "$STEPS" "$DT" "$KBT" "$SEED" "$SUMMARY_EVERY" "$DUMP_STATE_EVERY" "$THREADS")
PARAMS

src_gpu_cuda_env_io_segmented_resident_thermostat_0283
run_demo_case_0283 "$PARAMS_FILE" "$LOG_FILE" "$TIME_FILE" "$OUT_DIR"
