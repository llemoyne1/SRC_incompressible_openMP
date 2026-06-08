#!/usr/bin/env bash
set -euo pipefail

# 0300 — isolated Von Karman validation case for CUDA resampling sweeps.
#
# This script intentionally does not call or modify
# scripts/run_demo_src_classic_cuda_von_karman_cylinder_0285.sh.  It is a
# self-contained validation harness derived from the validated 0285 setup, with
# short-run defaults and thermostat disabled by default so that it can be used
# as a strict reproducibility witness when requested.

BIN="${BIN:-build/src_mpcd_base_cuda_0300}"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/src_gpu_demo_common_0283.sh"

if [[ ! -x "$BIN" ]]; then
  echo "[0300-vk] building $BIN with build_src_mpcd_cuda_0300.sh"
  OUT="$BIN" CUDA_ARCH_FLAGS="${CUDA_ARCH_FLAGS:-}" bash scripts/build_src_mpcd_cuda_0300.sh
fi
AUTO_BUILD=0

CASE_NAME="von_karman_resampling_validation_0300"
Lx="${Lx:-3.0}"; Ly="${Ly:-1.0}"; NX="${NX:-64}"; NY="${NY:-64}"
GAMMA="${GAMMA:-20}"; STEPS="${STEPS:-80}"; DT="${DT:-0.0005}"; KBT="${KBT:-0.001}"
SEED="${SEED:-1628505}"; SUMMARY_EVERY="${SUMMARY_EVERY:-$STEPS}"; DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-$STEPS}"
UIN="${UIN:-0.30}"; CYLINDER_CX="${CYLINDER_CX:-0.65}"; CYLINDER_CY="${CYLINDER_CY:-0.50}"; CYLINDER_R="${CYLINDER_R:-0.12}"
RUN_ROOT="${RUN_ROOT:-runs/cuda_resampling_von_karman_validation_0300}"
prepare_demo_dirs_0283 "$RUN_ROOT"
STATE_FILE="$RUN_ROOT/init/${CASE_NAME}_${NX}x${NY}_g${GAMMA}.smpcd"
PARAMS_FILE="$RUN_ROOT/params/${CASE_NAME}.kv"
OUT_DIR="$RUN_ROOT/output"
LOG_FILE="$RUN_ROOT/logs/${CASE_NAME}.log"
TIME_FILE="$RUN_ROOT/logs/${CASE_NAME}.time"

# The hard inlet reservoir uses inactive slots.  Keep this local to the
# validation script so user edits to the 0285 demo cannot affect sweep runs.
INACTIVE_SLOTS="${INACTIVE_SLOTS:-$((GAMMA * NY * 32))}"
OUTLET_MODE="${OUTLET_MODE:-equilibrium_flux}"
OUTLET_FORCED_MASS_FLUX="${OUTLET_FORCED_MASS_FLUX:-0.0}"
OUTLET_FORCED_MASS_PER_STEP="${OUTLET_FORCED_MASS_PER_STEP:-0.0}"
OUTLET_FORCED_PARTICLE_FLUX="${OUTLET_FORCED_PARTICLE_FLUX:-0.0}"
OUTLET_FORCED_PARTICLES_PER_STEP="${OUTLET_FORCED_PARTICLES_PER_STEP:-0}"
OUTLET_FORCED_LAYER_CELLS="${OUTLET_FORCED_LAYER_CELLS:-3}"
THERMOSTAT_ENABLE="${THERMOSTAT_ENABLE:-0}"

# Disable Q6/virial/resampling by parameters; CUDA resampling validation modules
# are activated only through explicit MPCD_CUDA_RESAMPLING_* environment flags
# supplied by the parent sweep script.
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

openBoundaryOutletMode = ${OUTLET_MODE}
openBoundaryOutletForcedMassFlux = ${OUTLET_FORCED_MASS_FLUX}
openBoundaryOutletForcedMassPerStep = ${OUTLET_FORCED_MASS_PER_STEP}
openBoundaryOutletForcedParticleFlux = ${OUTLET_FORCED_PARTICLE_FLUX}
openBoundaryOutletForcedParticlesPerStep = ${OUTLET_FORCED_PARTICLES_PER_STEP}
openBoundaryOutletForcedLayerCells = ${OUTLET_FORCED_LAYER_CELLS}
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

src_gpu_cuda_env_clear_0283
export MPCD_CUDA_CLASSIC_SRC_IO_FULLFACE_RESIDENT_0263=1
export MPCD_CUDA_CLASSIC_SRC_IO_FULLFACE_RESIDENT_0263_STRICT=1
export MPCD_CUDA_IMMERSED_CIRCLE_0284=1
export MPCD_CUDA_IMMERSED_CIRCLE_0284_DOWNLOAD_ALL=0
export MPCD_CUDA_PERSISTENT_SRC_COLLISION_USE=1
export MPCD_CUDA_PERSISTENT_SRC_COLLISION_STRICT=1
export MPCD_CUDA_PERSISTENT_SRC_COLLISION_ACTIVE_STRICT=1
export MPCD_CUDA_PERSISTENT_SRC_COLLISION_MINIMAL_DOWNLOAD_0257=1
export MPCD_CUDA_PERSISTENT_SRC_COLLISION_WALL_SIMPLE_0253=1
export MPCD_CUDA_PERSISTENT_SRC_COLLISION_IMMERSED_CIRCLE_0284=1
if [[ "${THERMOSTAT_ENABLE}" == "1" || "${THERMOSTAT_ENABLE}" == "true" || "${THERMOSTAT_ENABLE}" == "TRUE" ]]; then
  export MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_USE=1
  export MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_STRICT=1
  export MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_SHARED_0251_0260=1
else
  export MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_USE=0
  export MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_STRICT=0
  export MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_SHARED_0251_0260=0
fi
export MPCD_CUDA_PERSISTENT_THREADS_PER_BLOCK="${MPCD_CUDA_PERSISTENT_THREADS_PER_BLOCK:-256}"

run_demo_case_0283 "$PARAMS_FILE" "$LOG_FILE" "$TIME_FILE" "$OUT_DIR"
