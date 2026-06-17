#!/usr/bin/env bash
set -euo pipefail

# 0356/topo: autonomous CUDA SRC classic Von-Karman-like cylinder runner.
# The script generates its own initial state, writes its own parameter file,
# activates the validated wall+immersed-circle CUDA resident path, and runs it.
# Scope: SRC classic only. Q6/resampling/virial/Darcy are disabled here.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ ! -f scripts/src_gpu_demo_common_0283.sh ]]; then
  echo "[0356-vk] missing helper scripts/src_gpu_demo_common_0283.sh" >&2
  exit 2
fi
# shellcheck source=/dev/null
source scripts/src_gpu_demo_common_0283.sh

# User-requested reference parameters.
Lx="${Lx:-1.5}"
Ly="${Ly:-0.4}"
NX="${NX:-1200}"
NY="${NY:-640}"
GAMMA="${GAMMA:-6}"
DT="${DT:-0.0005}"
STEPS="${STEPS:-10000}"
ALPHA_DEG="${ALPHA_DEG:-90}"
U0="${U0:-0.9}"
KBT="${KBT:-5}"
# Accept either USE_THERMOSTAT or THERMOSTAT_ENABLE.  The common helper uses
# THERMOSTAT_ENABLE for both parameter writing and CUDA backend activation.
THERMOSTAT_ENABLE="${THERMOSTAT_ENABLE:-${USE_THERMOSTAT:-1}}"

CYLINDER_CX="${CYLINDER_CX:-0.25}"
CYLINDER_CY="${CYLINDER_CY:-0.205}"
CYLINDER_R="${CYLINDER_R:-0.04}"

# Optional Darcy/Brinkman cylinder penalization on top of the immersed circle.
# This is distinct from ALPHA_DEG, which is the SRC collision rotation angle.
# For dt=5e-4, alphaMax=1000 only damps by lambda=1-exp(-0.5)=0.393 per step;
# alphaMax=5000 gives lambda=0.918 and is much more no-slip-like.
DARCY_ENABLE="${DARCY_ENABLE:-0}"
DARCY_CHI_MODE="${DARCY_CHI_MODE:-circle}"
DARCY_ALPHA_MIN="${DARCY_ALPHA_MIN:-0}"
DARCY_ALPHA_MAX="${DARCY_ALPHA_MAX:-5000}"
DARCY_Q="${DARCY_Q:-0.05}"
DARCY_USOLID_X="${DARCY_USOLID_X:-0.0}"
DARCY_USOLID_Y="${DARCY_USOLID_Y:-0.0}"
DARCY_CX="${DARCY_CX:-$CYLINDER_CX}"
DARCY_CY="${DARCY_CY:-$CYLINDER_CY}"
DARCY_R="${DARCY_R:-$CYLINDER_R}"
DARCY_INTERFACE_WIDTH="${DARCY_INTERFACE_WIDTH:-0.002}"
DARCY_COST_EVERY="${DARCY_COST_EVERY:-100}"

# Cylinder model selection for clean comparisons:
#   immersed : code-defined immersed solid only, no Darcy field
#   darcy    : Darcy/Brinkman chi circle only, no immersed-solid reflection
#   both     : superposed immersed solid + Darcy penalty; diagnostic only
CYLINDER_MODEL="${CYLINDER_MODEL:-immersed}"
case "${CYLINDER_MODEL}" in
  immersed)
    IMMERSED_SOLID_ENABLE=true
    DARCY_ENABLE=0
    STATE_SOLID_SPEC="circle:${CYLINDER_CX},${CYLINDER_CY},${CYLINDER_R}"
    ;;
  darcy)
    IMMERSED_SOLID_ENABLE=false
    DARCY_ENABLE=1
    STATE_SOLID_SPEC="none"
    ;;
  both)
    IMMERSED_SOLID_ENABLE=true
    DARCY_ENABLE=1
    STATE_SOLID_SPEC="circle:${CYLINDER_CX},${CYLINDER_CY},${CYLINDER_R}"
    ;;
  *)
    echo "[0356-vk] unsupported CYLINDER_MODEL=${CYLINDER_MODEL}; use immersed|darcy|both" >&2
    exit 2
    ;;
esac

# Periodic-x / wall-y VK-like runner.  By default, the flow is initialized with
# mean U0 but not actively driven.  Set BODY_AX>0 for a forced periodic channel,
# or KEEP_MEAN_FLOW=1 to maintain targetMeanUx=U0 via the CPU mean-flow pass.
BODY_AX="${BODY_AX:-0.0}"
KEEP_MEAN_FLOW="${KEEP_MEAN_FLOW:-0}"

SEED="${SEED:-1628505}"
SUMMARY_EVERY="${SUMMARY_EVERY:-1000}"
DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-1000}"
DUMP_ROLE_FILTER="${DUMP_ROLE_FILTER:-fluid}"
SUMMARY_ROLE_FILTER="${SUMMARY_ROLE_FILTER:-fluid}"
THREADS="${THREADS:-8}"
export THREADS OMP_NUM_THREADS="${OMP_NUM_THREADS:-$THREADS}"
export OMP_PROC_BIND="${OMP_PROC_BIND:-close}"
export OMP_PLACES="${OMP_PLACES:-cores}"
export OMP_DYNAMIC="${OMP_DYNAMIC:-false}"

BIN="${BIN:-build/src_mpcd_base_cuda_topo_0348a}"
AUTO_BUILD="${AUTO_BUILD:-0}"
# Match the validated portable VK periodic-circle CUDA path by default.
# Use io_fullface only for legacy inlet/outlet-style experiments.
VK_CUDA_PATH="${VK_CUDA_PATH:-periodic_circle}"
THERMOSTAT_SHARED_0251_0260="${THERMOSTAT_SHARED_0251_0260:-0}"

# Live visualization.  The control file defaults to repository-root
# livevis_control.kv and is persistent: it is created if missing, but not
# overwritten unless LIVE_VIS_CONTROL_RESET=1.
LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-1}"
LIVE_VIS_FIELD="${LIVE_VIS_FIELD:-vorticity}"
LIVE_VIS_EVERY="${LIVE_VIS_EVERY:-5}"
LIVE_VIS_NX="${LIVE_VIS_NX:-1200}"
LIVE_VIS_NY="${LIVE_VIS_NY:-320}"
LIVE_VIS_CLIP="${LIVE_VIS_CLIP:--20}"
LIVE_VIS_GAIN="${LIVE_VIS_GAIN:-1.0}"
LIVE_VIS_SMOOTH_PASSES="${LIVE_VIS_SMOOTH_PASSES:-3}"
LIVE_VIS_COLORMAP="${LIVE_VIS_COLORMAP:-thermal}"
LIVE_VIS_WINDOW_SCALE="${LIVE_VIS_WINDOW_SCALE:-1}"
LIVE_VIS_VSYNC="${LIVE_VIS_VSYNC:-0}"
LIVE_VIS_CONTROL_FILE="${LIVE_VIS_CONTROL_FILE:-livevis_control.kv}"
LIVE_VIS_CONTROL_RESET="${LIVE_VIS_CONTROL_RESET:-0}"
LIVE_VIS_CONTROL_EVERY="${LIVE_VIS_CONTROL_EVERY:-1}"
LIVE_VIS_CONTROL_LOG="${LIVE_VIS_CONTROL_LOG:-1}"

CASE_NAME="topo_von_karman_cylinder_0356"
TAG="${TAG:-${CASE_NAME}_nx${NX}_ny${NY}_g${GAMMA}_u${U0//./p}}"
RUN_ROOT="${RUN_ROOT:-runs/${TAG}}"

# Dumps are large for the default 4.6M particles.  If dumps are disabled, do not
# let the older demo helper reject the run because no dump file was produced.
if [[ "$DUMP_STATE_EVERY" == "0" ]]; then
  export SRC_GPU_DEMO_REQUIRE_DUMPS=0
else
  export SRC_GPU_DEMO_REQUIRE_DUMPS="${SRC_GPU_DEMO_REQUIRE_DUMPS:-1}"
fi

ROTATION_ANGLE="${ROTATION_ANGLE:-$(python3 - <<PY
import math
print('{:.17g}'.format(float('${ALPHA_DEG}')*math.pi/180.0))
PY
)}"

NP_EST="$(( NX * NY * GAMMA ))"
echo "[0356-vk] case=${CASE_NAME} tag=${TAG}"
echo "[0356-vk] grid=${NX}x${NY} gamma=${GAMMA} particles~${NP_EST}"
echo "[0356-vk] L=${Lx}x${Ly} dt=${DT} steps=${STEPS} alphaDeg=${ALPHA_DEG} rotationAngle=${ROTATION_ANGLE}"
echo "[0356-vk] U0=${U0} kBT=${KBT} thermostat=${THERMOSTAT_ENABLE} BODY_AX=${BODY_AX} KEEP_MEAN_FLOW=${KEEP_MEAN_FLOW}"
echo "[0356-vk] cylinderModel=${CYLINDER_MODEL} immersed=${IMMERSED_SOLID_ENABLE} stateSolidSpec=${STATE_SOLID_SPEC}"
echo "[0356-vk] cylinder cx=${CYLINDER_CX} cy=${CYLINDER_CY} R=${CYLINDER_R}"
echo "[0356-vk] darcy=${DARCY_ENABLE} alphaMax=${DARCY_ALPHA_MAX} q=${DARCY_Q} circle=[${DARCY_CX},${DARCY_CY},${DARCY_R}] interface=${DARCY_INTERFACE_WIDTH}"
echo "[0356-vk] dumpStateEvery=${DUMP_STATE_EVERY} dumpRoleFilter=${DUMP_ROLE_FILTER}"
echo "[0356-vk] livevis=${LIVE_VIS_ENABLE} field=${LIVE_VIS_FIELD} grid=${LIVE_VIS_NX}x${LIVE_VIS_NY} every=${LIVE_VIS_EVERY} control=${LIVE_VIS_CONTROL_FILE}"
echo "[0356-vk] cudaPath=${VK_CUDA_PATH} thermostatShared0251_0260=${THERMOSTAT_SHARED_0251_0260}"

prepare_demo_dirs_0283 "$RUN_ROOT"
STATE_FILE="$RUN_ROOT/init/${CASE_NAME}_${NX}x${NY}_g${GAMMA}.smpcd"
PARAMS_FILE="$RUN_ROOT/params/${CASE_NAME}.kv"
OUT_DIR="$RUN_ROOT/output"
LOG_FILE="$RUN_ROOT/logs/${CASE_NAME}.log"
TIME_FILE="$RUN_ROOT/logs/${CASE_NAME}.time"
ENV_FILE="$RUN_ROOT/logs/${CASE_NAME}.env"

# No inactive reservoir is needed for the default periodic-x case.
INACTIVE_SLOTS="${INACTIVE_SLOTS:-7500}"

generate_demo_state_0283 \
  "$STATE_FILE" "$Lx" "$Ly" "$NX" "$NY" "$GAMMA" "$KBT" "$SEED" \
  uniform "$U0" 0.0 0.0 \
  0.0 -1.0 0.0 -1.0 "$INACTIVE_SLOTS" \
  "${STATE_SOLID_SPEC}"

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
bcBottom = solid
bcTop = solid

bodyAccelerationX = ${BODY_AX}
bodyAccelerationY = 0.0
taylorGreenForcingEnable = false
keepMeanFlowEnable = ${KEEP_MEAN_FLOW}
targetMeanUx = ${U0}
targetMeanUy = 0.0

immersedSolidEnable = ${IMMERSED_SOLID_ENABLE}
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

darcyBrinkmanEnable = ${DARCY_ENABLE}
darcyChiMode = ${DARCY_CHI_MODE}
darcyAlphaMin = ${DARCY_ALPHA_MIN}
darcyAlphaMax = ${DARCY_ALPHA_MAX}
darcyQ = ${DARCY_Q}
darcyUSolidX = ${DARCY_USOLID_X}
darcyUSolidY = ${DARCY_USOLID_Y}
darcyCircleCx = ${DARCY_CX}
darcyCircleCy = ${DARCY_CY}
darcyCircleR = ${DARCY_R}
darcyInterfaceWidth = ${DARCY_INTERFACE_WIDTH}
darcyCostEvery = ${DARCY_COST_EVERY}
darcyCostFilename = darcy_cost_0356.csv

wallAccommodation = 1.0
wallVpGamma = ${GAMMA}
wallVpMass = 1.0
wallKBT = -1.0
wallThermalNoise = 0.0

$(write_src_classic_common_params_0283 "$STEPS" "$DT" "$KBT" "$SEED" "$SUMMARY_EVERY" "$DUMP_STATE_EVERY" "$THREADS" "$ROTATION_ANGLE")
PARAMS

cat > "$ENV_FILE" <<ENV
CASE_NAME=${CASE_NAME}
RUN_ROOT=${RUN_ROOT}
BIN=${BIN}
VK_CUDA_PATH=${VK_CUDA_PATH}
THERMOSTAT_SHARED_0251_0260=${THERMOSTAT_SHARED_0251_0260}
Lx=${Lx}
Ly=${Ly}
NX=${NX}
NY=${NY}
GAMMA=${GAMMA}
NP_EST=${NP_EST}
DT=${DT}
STEPS=${STEPS}
ALPHA_DEG=${ALPHA_DEG}
ROTATION_ANGLE=${ROTATION_ANGLE}
U0=${U0}
KBT=${KBT}
THERMOSTAT_ENABLE=${THERMOSTAT_ENABLE}
BODY_AX=${BODY_AX}
KEEP_MEAN_FLOW=${KEEP_MEAN_FLOW}
CYLINDER_CX=${CYLINDER_CX}
CYLINDER_CY=${CYLINDER_CY}
CYLINDER_R=${CYLINDER_R}
CYLINDER_MODEL=${CYLINDER_MODEL}
IMMERSED_SOLID_ENABLE=${IMMERSED_SOLID_ENABLE}
STATE_SOLID_SPEC=${STATE_SOLID_SPEC}
DARCY_ENABLE=${DARCY_ENABLE}
DARCY_CHI_MODE=${DARCY_CHI_MODE}
DARCY_ALPHA_MIN=${DARCY_ALPHA_MIN}
DARCY_ALPHA_MAX=${DARCY_ALPHA_MAX}
DARCY_Q=${DARCY_Q}
DARCY_USOLID_X=${DARCY_USOLID_X}
DARCY_USOLID_Y=${DARCY_USOLID_Y}
DARCY_CX=${DARCY_CX}
DARCY_CY=${DARCY_CY}
DARCY_R=${DARCY_R}
DARCY_INTERFACE_WIDTH=${DARCY_INTERFACE_WIDTH}
DARCY_COST_EVERY=${DARCY_COST_EVERY}
SEED=${SEED}
SUMMARY_EVERY=${SUMMARY_EVERY}
DUMP_STATE_EVERY=${DUMP_STATE_EVERY}
DUMP_ROLE_FILTER=${DUMP_ROLE_FILTER}
SUMMARY_ROLE_FILTER=${SUMMARY_ROLE_FILTER}
THREADS=${THREADS}
PARAMS_FILE=${PARAMS_FILE}
STATE_FILE=${STATE_FILE}
OUT_DIR=${OUT_DIR}
LIVE_VIS_ENABLE=${LIVE_VIS_ENABLE}
LIVE_VIS_FIELD=${LIVE_VIS_FIELD}
LIVE_VIS_EVERY=${LIVE_VIS_EVERY}
LIVE_VIS_NX=${LIVE_VIS_NX}
LIVE_VIS_NY=${LIVE_VIS_NY}
LIVE_VIS_CLIP=${LIVE_VIS_CLIP}
LIVE_VIS_GAIN=${LIVE_VIS_GAIN}
LIVE_VIS_SMOOTH_PASSES=${LIVE_VIS_SMOOTH_PASSES}
LIVE_VIS_COLORMAP=${LIVE_VIS_COLORMAP}
LIVE_VIS_WINDOW_SCALE=${LIVE_VIS_WINDOW_SCALE}
LIVE_VIS_VSYNC=${LIVE_VIS_VSYNC}
LIVE_VIS_CONTROL_FILE=${LIVE_VIS_CONTROL_FILE}
LIVE_VIS_CONTROL_RESET=${LIVE_VIS_CONTROL_RESET}
ENV

control_dir="$(dirname "$LIVE_VIS_CONTROL_FILE")"
if [[ "$control_dir" != "." ]]; then
  mkdir -p "$control_dir"
fi
if [[ ! -f "$LIVE_VIS_CONTROL_FILE" || "$LIVE_VIS_CONTROL_RESET" == "1" || "$LIVE_VIS_CONTROL_RESET" == "true" || "$LIVE_VIS_CONTROL_RESET" == "TRUE" ]]; then
  cat > "$LIVE_VIS_CONTROL_FILE" <<CONTROL
# 0356/topo persistent live visualization controls.
# Default location is repository root: livevis_control.kv.
# Edit this file while the VK run is active; it is reloaded at runtime.
# Useful fields: vorticity, speed, ux, uy, mass.
field = ${LIVE_VIS_FIELD}
clip = ${LIVE_VIS_CLIP}
gain = ${LIVE_VIS_GAIN}
smoothPasses = ${LIVE_VIS_SMOOTH_PASSES}
colormap = ${LIVE_VIS_COLORMAP}
CONTROL
  echo "[0356-vk] wrote live control=$LIVE_VIS_CONTROL_FILE"
else
  echo "[0356-vk] reusing live control=$LIVE_VIS_CONTROL_FILE"
fi

if [[ ! -x "$BIN" ]]; then
  if [[ "$AUTO_BUILD" == "1" || "$AUTO_BUILD" == "true" || "$AUTO_BUILD" == "TRUE" ]]; then
    echo "[0356-vk] missing $BIN; building with scripts/build_src_mpcd_cuda_topo_0343.sh"
    OUT="$BIN" MPCD_ENABLE_LIVE_VIS="${MPCD_ENABLE_LIVE_VIS:-1}" FORCE_REBUILD=1 \
      bash scripts/build_src_mpcd_cuda_topo_0343.sh
  else
    echo "[0356-vk] missing binary: $BIN" >&2
    echo "[0356-vk] set AUTO_BUILD=1 or provide BIN=..." >&2
    exit 127
  fi
fi

# CUDA resident wall+circle SRC classic path, aligned with the validated VK demo
# family, but kept here so this runner can be controlled independently.
src_gpu_cuda_env_clear_0283
case "${VK_CUDA_PATH}" in
  periodic_circle)
    export MPCD_CUDA_CLASSIC_SRC_IO_FULLFACE_RESIDENT_0263=0
    export MPCD_CUDA_CLASSIC_SRC_IO_FULLFACE_RESIDENT_0263_STRICT=0
    ;;
  io_fullface)
    export MPCD_CUDA_CLASSIC_SRC_IO_FULLFACE_RESIDENT_0263=1
    export MPCD_CUDA_CLASSIC_SRC_IO_FULLFACE_RESIDENT_0263_STRICT=1
    ;;
  *)
    echo "[0356-vk] unsupported VK_CUDA_PATH=${VK_CUDA_PATH}; use periodic_circle|io_fullface" >&2
    exit 2
    ;;
esac
if [[ "${IMMERSED_SOLID_ENABLE}" == "true" ]]; then
  export MPCD_CUDA_IMMERSED_CIRCLE_0284=1
  export MPCD_CUDA_IMMERSED_CIRCLE_0284_DOWNLOAD_ALL=0
  export MPCD_CUDA_IMMERSED_CIRCLE_FAST_DIAGNOSTICS_0330="${SRC_GPU_IMMERSED_CIRCLE_FAST_DIAG_0330:-1}"
  export MPCD_CUDA_CLASSIC_SRC_WALL_CIRCLE_RESIDENT_0318=1
else
  export MPCD_CUDA_IMMERSED_CIRCLE_0284=0
  export MPCD_CUDA_IMMERSED_CIRCLE_0284_DOWNLOAD_ALL=1
  export MPCD_CUDA_IMMERSED_CIRCLE_FAST_DIAGNOSTICS_0330=0
  export MPCD_CUDA_CLASSIC_SRC_WALL_CIRCLE_RESIDENT_0318=0
fi
export MPCD_CUDA_STREAMING_WALL_SIMPLE_0246=1
export MPCD_CUDA_STREAMING_WALL_SIMPLE_0246_DOWNLOAD_ALL=0
export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_WALL_VP_DIAG_0319="${SRC_GPU_SKIP_WALL_VP_DIAG_0319:-1}"
export MPCD_CUDA_CLASSIC_SRC_RESIDENT_0271_ASYNC_STREAM="${SRC_GPU_ASYNC_STREAM_0320:-1}"
export MPCD_CUDA_CLASSIC_SRC_WALL_RESIDENT_0271_FAST_DIAGNOSTICS="${SRC_GPU_WALL_FAST_DIAG_0320:-1}"
export MPCD_CUDA_PERSISTENT_SRC_COLLISION_USE=1
export MPCD_CUDA_PERSISTENT_SRC_COLLISION_STRICT=1
export MPCD_CUDA_PERSISTENT_SRC_COLLISION_ACTIVE_STRICT=1
export MPCD_CUDA_PERSISTENT_SRC_COLLISION_MINIMAL_DOWNLOAD_0257=1
export MPCD_CUDA_PERSISTENT_SRC_COLLISION_FAST_THERMOSTAT_DIAG_0321="${SRC_GPU_FAST_THERMOSTAT_DIAG_0321:-1}"
export MPCD_CUDA_PERSISTENT_SRC_COLLISION_DEVICE_ROTATION_0272="${SRC_GPU_DEVICE_ROTATION_0322:-1}"
export MPCD_CUDA_PERSISTENT_SRC_COLLISION_LAZY_KERNEL_CHECK_0273="${SRC_GPU_LAZY_KERNEL_CHECK_0322:-1}"
export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_SETUP_SYNC_0273="${SRC_GPU_SKIP_SETUP_SYNC_0322:-1}"
export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_HOST_CELLID_FILL_0327="${SRC_GPU_SKIP_HOST_CELLID_FILL_0327:-1}"
export MPCD_CUDA_PERSISTENT_SRC_COLLISION_WALL_SIMPLE_0253=1
if [[ "${IMMERSED_SOLID_ENABLE}" == "true" ]]; then
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_IMMERSED_CIRCLE_0284=1
else
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_IMMERSED_CIRCLE_0284=0
fi
export MPCD_CUDA_PERSISTENT_PARTICLE_STATE_USE=1
export MPCD_CUDA_PERSISTENT_PARTICLE_METADATA_CACHE=1
export MPCD_CUDA_PERSISTENT_CELL_WORKSPACE_USE=1
if [[ "$THERMOSTAT_ENABLE" == "1" || "$THERMOSTAT_ENABLE" == "true" || "$THERMOSTAT_ENABLE" == "TRUE" ]]; then
  export MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_USE=1
  export MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_STRICT=1
  export MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_SHARED_0251_0260="${THERMOSTAT_SHARED_0251_0260}"
else
  export MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_USE=0
  export MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_STRICT=0
  export MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_SHARED_0251_0260=0
fi
export MPCD_CUDA_PERSISTENT_THREADS_PER_BLOCK="${MPCD_CUDA_PERSISTENT_THREADS_PER_BLOCK:-256}"

export SRC_LIVE_VIS_ENABLE="$LIVE_VIS_ENABLE"
export SRC_LIVE_VIS_FIELD="$LIVE_VIS_FIELD"
export SRC_LIVE_VIS_EVERY="$LIVE_VIS_EVERY"
export SRC_LIVE_VIS_NX="$LIVE_VIS_NX"
export SRC_LIVE_VIS_NY="$LIVE_VIS_NY"
export SRC_LIVE_VIS_CLIP="$LIVE_VIS_CLIP"
export SRC_LIVE_VIS_GAIN="$LIVE_VIS_GAIN"
export SRC_LIVE_VIS_SMOOTH_PASSES="$LIVE_VIS_SMOOTH_PASSES"
export SRC_LIVE_VIS_COLORMAP="$LIVE_VIS_COLORMAP"
export SRC_LIVE_VIS_WINDOW_SCALE="$LIVE_VIS_WINDOW_SCALE"
export SRC_LIVE_VIS_VSYNC="$LIVE_VIS_VSYNC"
export SRC_LIVE_VIS_CUDA_FIELD=1
export SRC_LIVE_VIS_CUDA_SNAPSHOT=0
export SRC_LIVE_VIS_FORCE_HOST_MIRROR=0
export SRC_LIVE_VIS_CONTROL_FILE="$LIVE_VIS_CONTROL_FILE"
export SRC_LIVE_VIS_CONTROL_EVERY="$LIVE_VIS_CONTROL_EVERY"
export SRC_LIVE_VIS_CONTROL_LOG="$LIVE_VIS_CONTROL_LOG"
export MPCD_CUDA_DARCY_BRINKMAN_LOG_0343="${MPCD_CUDA_DARCY_BRINKMAN_LOG_0343:-0}"

# Capture the effective CUDA/livevis runtime environment after all exports.
env | grep -E '^(MPCD_CUDA_|SRC_LIVE_VIS_|OMP_)' | sort > "$RUN_ROOT/logs/runtime_environment_0356.env"

run_demo_case_0283 "$PARAMS_FILE" "$LOG_FILE" "$TIME_FILE" "$OUT_DIR"

summary="$RUN_ROOT/von_karman_cylinder_0356_summary.txt"
{
  echo "RUN_ROOT=${RUN_ROOT}"
  echo "PARAMS_FILE=${PARAMS_FILE}"
  echo "OUTPUT_DIR=${OUT_DIR}"
  echo "SUMMARY_CSV=${OUT_DIR}/summary_runtime.csv"
  echo "LIVE_VIS_CONTROL_FILE=${LIVE_VIS_CONTROL_FILE}"
  echo "CYLINDER_MODEL=${CYLINDER_MODEL}"
  echo "VK_CUDA_PATH=${VK_CUDA_PATH}"
  echo "THERMOSTAT_SHARED_0251_0260=${THERMOSTAT_SHARED_0251_0260}"
  echo "IMMERSED_SOLID_ENABLE=${IMMERSED_SOLID_ENABLE}"
  echo "DARCY_ENABLE=${DARCY_ENABLE}"
  echo "DARCY_ALPHA_MAX=${DARCY_ALPHA_MAX}"
  echo "DARCY_Q=${DARCY_Q}"
  echo "DARCY_COST_CSV=${OUT_DIR}/darcy_cost_0356.csv"
  echo "DUMP_COUNT=$(find "$OUT_DIR" -maxdepth 1 -name 'state_step_*.smpcd' -type f | wc -l | tr -d ' ')"
  echo "FINAL_SUMMARY_LINE=$(tail -n 1 "$OUT_DIR/summary_runtime.csv")"
} > "$summary"

echo "[0356-vk] summary=$summary"
cat "$summary"
