#!/usr/bin/env bash
set -euo pipefail

# 0285 — Von Karman cylinder demonstration on the full CUDA SRC classic path.
# SRC classic means: advection/streaming + random grid shift + SRC rotation/collision + thermostat.
# Q6, resampling and virial/capacity closure remain disabled in this demo.

BIN="${BIN:-build/src_mpcd_base_cuda_0293}"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/src_gpu_demo_common_0283.sh"

if [[ ! -x "$BIN" ]]; then
  echo "[0285-demo] building $BIN with build_src_mpcd_cuda_0293.sh"
  OUT="$BIN" CUDA_ARCH_FLAGS="${CUDA_ARCH_FLAGS:-}" bash scripts/build_src_mpcd_cuda_0293.sh
fi
AUTO_BUILD=0

CASE_NAME="von_karman_cylinder"
Lx="${Lx:-3.0}"; Ly="${Ly:-1.0}"; NX="${NX:-192}"; NY="${NY:-64}"
GAMMA="${GAMMA:-20}"; STEPS="${STEPS:-10000}"; DT="${DT:-0.001}"; KBT="${KBT:-0.001}"
SEED="${SEED:-1628505}"; SUMMARY_EVERY="${SUMMARY_EVERY:-100}"; DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-100}"
UIN="${UIN:-0.2}"; CYLINDER_CX="${CYLINDER_CX:-0.65}"; CYLINDER_CY="${CYLINDER_CY:-0.50}"; CYLINDER_R="${CYLINDER_R:-0.15}"
RUN_ROOT="${RUN_ROOT:-runs/demo_src_classic_cuda_von_karman_cylinder_0285}"
prepare_demo_dirs_0283 "$RUN_ROOT"
STATE_FILE="$RUN_ROOT/init/${CASE_NAME}_${NX}x${NY}_g${GAMMA}.smpcd"
PARAMS_FILE="$RUN_ROOT/params/${CASE_NAME}.kv"
OUT_DIR="$RUN_ROOT/output"
LOG_FILE="$RUN_ROOT/logs/${CASE_NAME}.log"
TIME_FILE="$RUN_ROOT/logs/${CASE_NAME}.time"
# Hard reservoir reuses inactive slots; allocate a generous pool for long animated runs.
INACTIVE_SLOTS="${INACTIVE_SLOTS:-$((GAMMA * NY * 32))}"
OUTLET_MODE="${OUTLET_MODE:-equilibrium_flux}"
OUTLET_FORCED_MASS_FLUX="${OUTLET_FORCED_MASS_FLUX:-0.0}"
OUTLET_FORCED_MASS_PER_STEP="${OUTLET_FORCED_MASS_PER_STEP:-0.0}"
OUTLET_FORCED_PARTICLE_FLUX="${OUTLET_FORCED_PARTICLE_FLUX:-0.0}"
OUTLET_FORCED_PARTICLES_PER_STEP="${OUTLET_FORCED_PARTICLES_PER_STEP:-0}"
OUTLET_FORCED_LAYER_CELLS="${OUTLET_FORCED_LAYER_CELLS:-3}"
THERMOSTAT_ENABLE="${THERMOSTAT_ENABLE:-1}"

generate_demo_state_0283 "$STATE_FILE" "$Lx" "$Ly" "$NX" "$NY" "$GAMMA" "$KBT" "$SEED" uniform "$UIN" 0.0 0.0 0.0 -1.0 0.0 -1.0 "$INACTIVE_SLOTS" "circle:${CYLINDER_CX},${CYLINDER_CY},${CYLINDER_R}"
mkdir -p "$OUT_DIR"
cat > "$PARAMS_FILE" <<PARAMS
inputState = ${STATE_FILE}
outputDir = ${OUT_DIR}

Lx = ${Lx}
Ly = ${Ly}
Nx = ${NX}
Ny = ${NY}

# bcLeft = inlet
# bcRight = outlet
# bcBottom = solid
# bcTop = solid

bcLeft = periodic
bcRight = periodic
bcBottom = solid
bcTop = solid

bodyAccelerationX = 0.05
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
# 0330: fast immersed-circle diagnostics for the classic resident VK benchmark.
# The CUDA circle reflection still modifies particles on device, but the per-step
# diagnostic hit counter allocation/copy/free is skipped.  This only affects the
# immersed hits diagnostic reported in summary_runtime.csv; set
# SRC_GPU_IMMERSED_CIRCLE_FAST_DIAG_0330=0 to restore the legacy hit counter.
export MPCD_CUDA_IMMERSED_CIRCLE_FAST_DIAGNOSTICS_0330="${SRC_GPU_IMMERSED_CIRCLE_FAST_DIAG_0330:-1}"
echo "[0330b-demo] IMMERSED_CIRCLE_FAST_DIAG_0330=${MPCD_CUDA_IMMERSED_CIRCLE_FAST_DIAGNOSTICS_0330}"
# 0318b: force the measured wall+circle resident path after
# src_gpu_cuda_env_clear_0283.  The clear helper resets
# MPCD_CUDA_STREAMING_WALL_SIMPLE_0246=0, so relying on an outer environment
# variable is not sufficient.  This is script-only and does not modify the
# solver or require recompilation.
export MPCD_CUDA_CLASSIC_SRC_WALL_CIRCLE_RESIDENT_0318=1
export MPCD_CUDA_STREAMING_WALL_SIMPLE_0246=1
export MPCD_CUDA_STREAMING_WALL_SIMPLE_0246_DOWNLOAD_ALL=0
# 0319: skip the CPU reconstruction of wall virtual-particle diagnostics in
# the CUDA persistent collision path.  The CUDA collision kernel has already
# applied the physical virtual-wall/circle contribution; this only affects the
# runtime_summary virtualParticle*/virtualMass* diagnostic columns.  Set
# SRC_GPU_SKIP_WALL_VP_DIAG_0319=0 to restore the legacy diagnostic.
export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_WALL_VP_DIAG_0319="${SRC_GPU_SKIP_WALL_VP_DIAG_0319:-1}"
echo "[0318b-demo] WALL_CIRCLE_RESIDENT_0318=${MPCD_CUDA_CLASSIC_SRC_WALL_CIRCLE_RESIDENT_0318} STREAMING_WALL_SIMPLE_0246=${MPCD_CUDA_STREAMING_WALL_SIMPLE_0246} DOWNLOAD_ALL=${MPCD_CUDA_STREAMING_WALL_SIMPLE_0246_DOWNLOAD_ALL}"
echo "[0319-demo] SKIP_WALL_VP_DIAG_0319=${MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_WALL_VP_DIAG_0319}"
# 0320: measured wall resident fast diagnostics defaults.  The 0320 probe
# showed that the existing 0271 fast diagnostics/async stream flags reduce
# wall_simple_0246 from about 4.00 s to about 0.50 s on the 192x64 VK-like
# benchmark, without changing the solver.  Set SRC_GPU_WALL_FAST_DIAG_0320=0
# or SRC_GPU_ASYNC_STREAM_0320=0 to restore legacy behavior for debugging.
export MPCD_CUDA_CLASSIC_SRC_RESIDENT_0271_ASYNC_STREAM="${SRC_GPU_ASYNC_STREAM_0320:-1}"
export MPCD_CUDA_CLASSIC_SRC_WALL_RESIDENT_0271_FAST_DIAGNOSTICS="${SRC_GPU_WALL_FAST_DIAG_0320:-1}"
echo "[0320-demo] WALL_FAST_DIAG_0320=${MPCD_CUDA_CLASSIC_SRC_WALL_RESIDENT_0271_FAST_DIAGNOSTICS} ASYNC_STREAM_0320=${MPCD_CUDA_CLASSIC_SRC_RESIDENT_0271_ASYNC_STREAM}"
export MPCD_CUDA_PERSISTENT_SRC_COLLISION_USE=1
export MPCD_CUDA_PERSISTENT_SRC_COLLISION_STRICT=1
export MPCD_CUDA_PERSISTENT_SRC_COLLISION_ACTIVE_STRICT=1
export MPCD_CUDA_PERSISTENT_SRC_COLLISION_MINIMAL_DOWNLOAD_0257=1
# 0321: the measured residual after 0318/0319/0320 is the D2H/sync block that
# reconstructs thermostat/cell population diagnostics after the persistent
# collision+thermostat kernels.  The physical thermostat remains on GPU; this
# flag only skips per-step diagnostic downloads in this benchmark runner.
export MPCD_CUDA_PERSISTENT_SRC_COLLISION_FAST_THERMOSTAT_DIAG_0321="${SRC_GPU_FAST_THERMOSTAT_DIAG_0321:-1}"
echo "[0321-demo] FAST_THERMOSTAT_DIAG_0321=${MPCD_CUDA_PERSISTENT_SRC_COLLISION_FAST_THERMOSTAT_DIAG_0321}"
# 0322: apply the already validated 0272/0273 collision-wrapper reductions to
# the shared collision+thermostat path.  These flags avoid per-step H2D rotation
# table uploads and the setup synchronization that remained visible after 0321.
# They can be disabled independently for debugging.
export MPCD_CUDA_PERSISTENT_SRC_COLLISION_DEVICE_ROTATION_0272="${SRC_GPU_DEVICE_ROTATION_0322:-1}"
export MPCD_CUDA_PERSISTENT_SRC_COLLISION_LAZY_KERNEL_CHECK_0273="${SRC_GPU_LAZY_KERNEL_CHECK_0322:-1}"
export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_SETUP_SYNC_0273="${SRC_GPU_SKIP_SETUP_SYNC_0322:-1}"
echo "[0322-demo] DEVICE_ROTATION_0322=${MPCD_CUDA_PERSISTENT_SRC_COLLISION_DEVICE_ROTATION_0272} LAZY_KERNEL_CHECK_0322=${MPCD_CUDA_PERSISTENT_SRC_COLLISION_LAZY_KERNEL_CHECK_0273} SKIP_SETUP_SYNC_0322=${MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_SETUP_SYNC_0273}"
# 0327b: measured post-0322 residual includes host-side sentinel filling of
# cellIdOut in the strict classic resident fast-diagnostics path.  The 0327b
# implementation keeps cellIdOut sized with resize(n), rather than clear(),
# because the CPU thermostat wrapper still validates the vector size before
# consuming GPU thermostat diagnostics.  The classic
# VK benchmark has no CPU Q6/resampling/virial continuation after the fused
# GPU collision+thermostat step; hybrid paths must keep using their own runner
# with srcClassicCudaModeEnable=false.  Set SRC_GPU_SKIP_HOST_CELLID_FILL_0327=0
# to restore the conservative host vector shape for debugging.
export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_HOST_CELLID_FILL_0327="${SRC_GPU_SKIP_HOST_CELLID_FILL_0327:-1}"
echo "[0327b-demo] SKIP_HOST_CELLID_FILL_0327=${MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_HOST_CELLID_FILL_0327} MODE=resize_no_sentinel_fill"
# 0324: optional internal CUDA-event kernel breakdown for the persistent
# collision+thermostat batch.  Disabled by default because it synchronizes
# after every kernel launch.  Enable only on short profiling runs with
# SRC_GPU_KERNEL_BREAKDOWN_0324=1.
export MPCD_CUDA_PERSISTENT_SRC_COLLISION_KERNEL_BREAKDOWN_0324="${SRC_GPU_KERNEL_BREAKDOWN_0324:-0}"
export MPCD_CUDA_PERSISTENT_SRC_COLLISION_KERNEL_BREAKDOWN_0324_FILE="${OUT_DIR}/cuda_persistent_kernel_breakdown_0324.csv"
# 0328: when enabled, 0324 microprofile rows are appended over all steps
# instead of keeping only the last step.  This is profiling-only and remains
# disabled in normal runs.
export MPCD_CUDA_PERSISTENT_SRC_COLLISION_KERNEL_BREAKDOWN_APPEND_0328="${SRC_GPU_KERNEL_BREAKDOWN_APPEND_0328:-0}"
echo "[0324-demo] KERNEL_BREAKDOWN_0324=${MPCD_CUDA_PERSISTENT_SRC_COLLISION_KERNEL_BREAKDOWN_0324} FILE=${MPCD_CUDA_PERSISTENT_SRC_COLLISION_KERNEL_BREAKDOWN_0324_FILE}"
echo "[0328-demo] KERNEL_BREAKDOWN_APPEND_0328=${MPCD_CUDA_PERSISTENT_SRC_COLLISION_KERNEL_BREAKDOWN_APPEND_0328}"
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
