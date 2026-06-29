#!/usr/bin/env bash
set -euo pipefail

# 0414 -- autonomous SRC classic CUDA + Darcy/Brinkman NACA chi-file demo.
# Periodic left/right, solid top/bottom, no Q6, no resampling, livevis enabled.
# External .smpcd initial state is homogeneous with mean velocity U0.
# Darcy topoBenchmark diagnostics are enabled by default.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

truthy_0411() { case "${1:-0}" in 1|true|TRUE|yes|YES|on|ON|enable|enabled) return 0 ;; *) return 1 ;; esac; }

Lx=${Lx:-${LX:-1.0}}
Ly=${Ly:-${LY:-1.0}}
NX=${NX:-128}
NY=${NY:-128}
GAMMA=${GAMMA:-20}
STEPS=${STEPS:-5000}
SUMMARY_EVERY=${SUMMARY_EVERY:-100}
DUMP_STATE_EVERY=${DUMP_STATE_EVERY:-${DUMPS_EVERY:-100}}
THREADS=${THREADS:-8}
SEED=${SEED:-1628414}
DT=${DT:-0.001}
KBT=${KBT:-0.001}
PARTICLE_MASS=${PARTICLE_MASS:-1.0}
U0=${U0:-1.0}
UINIT=${UINIT:-0.0}
INACTIVE_SLOTS=${INACTIVE_SLOTS:-0}

# Periodic x-channel around a Darcy/Brinkman NACA chi obstacle.
# No open boundary segments are used in this variant.
AX=${AX:-0.0}
AY=${AY:-0.0}

# Darcy/Brinkman chi file.  The file must be row-major iy*Nx+ix and match NX,NY.
CHI_FILE=${CHI_FILE:-${DARCY_CHI_FILE:-./chi/chi_naca0012_alpha5_centered_128x128_f32.f32}}
CHI_FILE_FORMAT=${CHI_FILE_FORMAT:-${DARCY_CHI_FILE_FORMAT:-float32}}
ALPHA=${ALPHA:-${DARCY_ALPHA_MAX:-80.0}}
ALPHA_MIN=${ALPHA_MIN:-${DARCY_ALPHA_MIN:-0.0}}
DARCY_Q=${DARCY_Q:-0.1}
DARCY_USOLID_X=${DARCY_USOLID_X:-0.0}
DARCY_USOLID_Y=${DARCY_USOLID_Y:-0.0}
DARCY_COST_EVERY=${DARCY_COST_EVERY:-$SUMMARY_EVERY}
DARCY_THREADS_PER_BLOCK=${DARCY_THREADS_PER_BLOCK:-256}

# Darcy/Brinkman benchmark observables: force, drag/lift proxies, and benchmark CSV.
TOPO_BENCHMARK_ENABLE=${TOPO_BENCHMARK_ENABLE:-true}
TOPO_BENCHMARK_EVERY=${TOPO_BENCHMARK_EVERY:-$DARCY_COST_EVERY}
TOPO_BENCHMARK_FILENAME=${TOPO_BENCHMARK_FILENAME:-topo_benchmark_0348.csv}
TOPO_BENCHMARK_FORCE_ENABLE=${TOPO_BENCHMARK_FORCE_ENABLE:-true}
TOPO_BENCHMARK_DRAG_LIFT_ENABLE=${TOPO_BENCHMARK_DRAG_LIFT_ENABLE:-true}
TOPO_BENCHMARK_FLOW_DIR_X=${TOPO_BENCHMARK_FLOW_DIR_X:-1.0}
TOPO_BENCHMARK_FLOW_DIR_Y=${TOPO_BENCHMARK_FLOW_DIR_Y:-0.0}
TOPO_BENCHMARK_LIFT_DIR_X=${TOPO_BENCHMARK_LIFT_DIR_X:-0.0}
TOPO_BENCHMARK_LIFT_DIR_Y=${TOPO_BENCHMARK_LIFT_DIR_Y:-1.0}

ROTATION_ANGLE=${ROTATION_ANGLE:-1.5707963267948966}
RANDOM_ROTATION_SIGN=${RANDOM_ROTATION_SIGN:-true}
GRID_SHIFT_ENABLE=${GRID_SHIFT_ENABLE:-true}
THERMOSTAT_ENABLE=${THERMOSTAT_ENABLE:-true}
THERMOSTAT_MODE=${THERMOSTAT_MODE:-cell_relative_rescale}
THERMOSTAT_EVERY=${THERMOSTAT_EVERY:-1}
THERMOSTAT_TARGET_KBT=${THERMOSTAT_TARGET_KBT:--1.0}
THERMOSTAT_MIN_PARTICLES=${THERMOSTAT_MIN_PARTICLES:-3}
DUMP_ROLE_FILTER=${DUMP_ROLE_FILTER:-fluid}
SUMMARY_ROLE_FILTER=${SUMMARY_ROLE_FILTER:-fluid}

FORCE_BUILD=${FORCE_BUILD:-0}
BUILD_IF_STALE=${BUILD_IF_STALE:-1}
LIVE_PROGRESS=${LIVE_PROGRESS:-1}
LIVE_VIS_ENABLE=${LIVE_VIS_ENABLE:-${SRC_LIVE_VIS_ENABLE:-1}}
LIVE_VIS_FIELD=${LIVE_VIS_FIELD:-chi}
LIVE_VIS_EVERY=${LIVE_VIS_EVERY:-10}
LIVE_VIS_NX=${LIVE_VIS_NX:-768}
LIVE_VIS_NY=${LIVE_VIS_NY:-768}
LIVE_VIS_CLIP=${LIVE_VIS_CLIP:--1}
LIVE_VIS_GAIN=${LIVE_VIS_GAIN:-1.0}
LIVE_VIS_SMOOTH_PASSES=${LIVE_VIS_SMOOTH_PASSES:-1}
LIVE_VIS_COLORMAP=${LIVE_VIS_COLORMAP:-thermal}
LIVE_VIS_WINDOW_SCALE=${LIVE_VIS_WINDOW_SCALE:-1}
LIVE_VIS_VSYNC=${LIVE_VIS_VSYNC:-0}
LIVE_VIS_CUDA_FIELD=${LIVE_VIS_CUDA_FIELD:-1}
LIVE_VIS_CUDA_SNAPSHOT=${LIVE_VIS_CUDA_SNAPSHOT:-1}
LIVE_VIS_LOG_SOURCE=${LIVE_VIS_LOG_SOURCE:-0}
LIVE_VIS_CONTROL_FILE=${LIVE_VIS_CONTROL_FILE:-./livevis_control.kv}
LIVE_VIS_CONTROL_EVERY=${LIVE_VIS_CONTROL_EVERY:-1}
LIVE_VIS_CONTROL_LOG=${LIVE_VIS_CONTROL_LOG:-0}

TAG=${TAG:-src_classic_cuda_darcy_chi_naca_periodic_0414_${NX}x${NY}_u${U0}_alpha${ALPHA}}
RUN_ROOT=${RUN_ROOT:-runs/${TAG}}
STATE_SOURCE=${STATE_SOURCE:-${INPUT_STATE:-./init/src_classic_darcy_homogeneous_U1_128x128_g20.smpcd}}
STATE=${STATE:-$RUN_ROOT/init/$(basename "$STATE_SOURCE")}
PARAMS=${PARAMS:-$RUN_ROOT/params/src_classic_darcy_chi.kv}
OUT_DIR=${OUT_DIR:-$RUN_ROOT/output}
TIME_FILE=${TIME_FILE:-$RUN_ROOT/logs/src_classic_darcy_chi.time}
ENV_FILE=${ENV_FILE:-$RUN_ROOT/logs/environment_0411.env}

if [[ -z "$CHI_FILE" ]]; then
  echo "[0414-darcy-naca] ERROR: provide CHI_FILE=/path/to/chi.f32 or DARCY_CHI_FILE=/path/to/chi.f32" >&2
  exit 2
fi
if [[ ! -f "$CHI_FILE" ]]; then
  echo "[0414-darcy-naca] ERROR: chi file not found: $CHI_FILE" >&2
  exit 2
fi
if [[ -z "$STATE_SOURCE" ]]; then
  echo "[0414-darcy-naca] ERROR: provide STATE_SOURCE=/path/to/state.smpcd or INPUT_STATE=/path/to/state.smpcd" >&2
  exit 2
fi
if [[ ! -f "$STATE_SOURCE" ]]; then
  echo "[0414-darcy-naca] ERROR: initial state file not found: $STATE_SOURCE" >&2
  exit 2
fi

USER_BIN_SET=0
if [[ -n "${BIN+x}" ]]; then USER_BIN_SET=1; fi
if truthy_0411 "$LIVE_VIS_ENABLE" && [[ "$USER_BIN_SET" == "0" ]]; then
  BIN=build/src_mpcd_base_cuda_q6_resident_0400_livevis
else
  BIN=${BIN:-build/src_mpcd_base_cuda_q6_resident_0400}
fi

needs_build=0
if truthy_0411 "$FORCE_BUILD" || [[ ! -x "$BIN" ]]; then
  needs_build=1
elif truthy_0411 "$BUILD_IF_STALE"; then
  if find src include scripts/build_src_mpcd_cuda_q6_resident_0400.sh -type f -newer "$BIN" -print -quit | grep -q .; then needs_build=1; fi
fi
if [[ "$needs_build" == "1" ]]; then
  if truthy_0411 "$LIVE_VIS_ENABLE"; then MPCD_ENABLE_LIVE_VIS=1 OUT="$BIN" bash scripts/build_src_mpcd_cuda_q6_resident_0400.sh; else OUT="$BIN" bash scripts/build_src_mpcd_cuda_q6_resident_0400.sh; fi
fi
if [[ ! -x "$BIN" ]]; then echo "[0414-darcy-naca] ERROR missing binary: $BIN" >&2; exit 127; fi

mkdir -p "$RUN_ROOT/init" "$RUN_ROOT/params" "$RUN_ROOT/logs" "$OUT_DIR"

cp "$STATE_SOURCE" "$STATE"
echo "[0411-state] input=$STATE_SOURCE copied=$STATE"

cat > "$PARAMS" <<PARAMS
inputState = $STATE
outputDir = $OUT_DIR
Lx = $Lx
Ly = $Ly
Nx = $NX
Ny = $NY

dt = $DT
nSteps = $STEPS

bcLeft = periodic
bcRight = periodic
bcBottom = solid
bcTop = solid
bcX = periodic
bcY = solid

openBoundarySegmentsEnable = false
openBoundarySegmentCount = 0

bodyAccelerationX = $AX
bodyAccelerationY = $AY

wallAccommodation = 1.0
wallVpGamma = $GAMMA
wallVpMass = $PARTICLE_MASS
wallKBT = -1.0
wallThermalNoise = 0.0

srcClassicCudaModeEnable = true
projectionEnable = false
resamplingEnable = false
closedCapacityResponseEnable = false
closedCapacityVirialKickEnable = false

rotationAngle = $ROTATION_ANGLE
randomRotationSign = $RANDOM_ROTATION_SIGN
gridShiftEnable = $GRID_SHIFT_ENABLE
rngSeed = $SEED

thermostatEnable = $THERMOSTAT_ENABLE
thermostatMode = $THERMOSTAT_MODE
thermostatEvery = $THERMOSTAT_EVERY
thermostatTargetKBT = $THERMOSTAT_TARGET_KBT
thermostatMinParticles = $THERMOSTAT_MIN_PARTICLES
kBT = $KBT

darcyBrinkmanEnable = true
darcyChiMode = file
darcyChiFile = $CHI_FILE
darcyChiNx = $NX
darcyChiNy = $NY
darcyChiFileFormat = $CHI_FILE_FORMAT
darcyAlphaMin = $ALPHA_MIN
darcyAlphaMax = $ALPHA
darcyQ = $DARCY_Q
darcyUSolidX = $DARCY_USOLID_X
darcyUSolidY = $DARCY_USOLID_Y
darcyCostEvery = $DARCY_COST_EVERY
darcyCostFilename = darcy_cost_0343.csv
darcyThreadsPerBlock = $DARCY_THREADS_PER_BLOCK

topoBenchmarkEnable = $TOPO_BENCHMARK_ENABLE
topoBenchmarkEvery = $TOPO_BENCHMARK_EVERY
topoBenchmarkFilename = $TOPO_BENCHMARK_FILENAME
topoBenchmarkForceEnable = $TOPO_BENCHMARK_FORCE_ENABLE
topoBenchmarkDragLiftEnable = $TOPO_BENCHMARK_DRAG_LIFT_ENABLE
topoBenchmarkFlowDirX = $TOPO_BENCHMARK_FLOW_DIR_X
topoBenchmarkFlowDirY = $TOPO_BENCHMARK_FLOW_DIR_Y
topoBenchmarkLiftDirX = $TOPO_BENCHMARK_LIFT_DIR_X
topoBenchmarkLiftDirY = $TOPO_BENCHMARK_LIFT_DIR_Y

summaryEvery = $SUMMARY_EVERY
dumpStateEvery = $DUMP_STATE_EVERY
summaryRoleFilter = $SUMMARY_ROLE_FILTER
dumpRoleFilter = $DUMP_ROLE_FILTER
numThreads = $THREADS
PARAMS

if truthy_0411 "$LIVE_VIS_ENABLE"; then
  if [[ ! -f "$LIVE_VIS_CONTROL_FILE" ]]; then
    cat > "$LIVE_VIS_CONTROL_FILE" <<CONTROL
field = ${LIVE_VIS_FIELD}
clip = ${LIVE_VIS_CLIP}
gain = ${LIVE_VIS_GAIN}
smoothPasses = ${LIVE_VIS_SMOOTH_PASSES}
colormap = ${LIVE_VIS_COLORMAP}
quiverScale = ${SRC_LIVE_VIS_QUIVER_SCALE:--1}
CONTROL
  fi
fi

export OMP_NUM_THREADS="${OMP_NUM_THREADS:-$THREADS}"
export OMP_PROC_BIND="${OMP_PROC_BIND:-close}"
export OMP_PLACES="${OMP_PLACES:-cores}"
export OMP_DYNAMIC="${OMP_DYNAMIC:-false}"

# 0426 fast resident CUDA collision/thermostat controls.
# These defaults reproduce the optimized resident SRC path observed in the
# solid/full-face validation and avoid the slow generic collision/thermostat
# path in Darcy/chi demo scripts. Set MPCD_DARCY_FASTFLAGS_ENABLE=0 to disable.
export_src_cuda_resident_fastflags_0426() {
  case "${MPCD_DARCY_FASTFLAGS_ENABLE:-1}" in
    1|true|TRUE|yes|YES|on|ON|enable|enabled) ;;
    *) return 0 ;;
  esac

  export MPCD_CUDA_CLASSIC_SRC_RESIDENT_0271_ASYNC_STREAM="${MPCD_CUDA_CLASSIC_SRC_RESIDENT_0271_ASYNC_STREAM:-1}"
  export MPCD_CUDA_PERSISTENT_THREADS_PER_BLOCK="${MPCD_CUDA_PERSISTENT_THREADS_PER_BLOCK:-256}"
  export MPCD_CUDA_PERSISTENT_PARTICLE_STATE_USE="${MPCD_CUDA_PERSISTENT_PARTICLE_STATE_USE:-1}"
  export MPCD_CUDA_PERSISTENT_PARTICLE_METADATA_CACHE="${MPCD_CUDA_PERSISTENT_PARTICLE_METADATA_CACHE:-1}"
  export MPCD_CUDA_PERSISTENT_CELL_WORKSPACE_USE="${MPCD_CUDA_PERSISTENT_CELL_WORKSPACE_USE:-1}"

  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_DEVICE_ROTATION_0272="${MPCD_CUDA_PERSISTENT_SRC_COLLISION_DEVICE_ROTATION_0272:-1}"
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_FAST_THERMOSTAT_DIAG_0321="${MPCD_CUDA_PERSISTENT_SRC_COLLISION_FAST_THERMOSTAT_DIAG_0321:-1}"
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_FUSED_STREAM_DEPOSIT_0274="${MPCD_CUDA_PERSISTENT_SRC_COLLISION_FUSED_STREAM_DEPOSIT_0274:-1}"
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_LAZY_KERNEL_CHECK_0273="${MPCD_CUDA_PERSISTENT_SRC_COLLISION_LAZY_KERNEL_CHECK_0273:-1}"
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_FINAL_SYNC_0272="${MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_FINAL_SYNC_0272:-1}"
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_SETUP_SYNC_0273="${MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_SETUP_SYNC_0273:-1}"
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_WORKSPACE_DOWNLOAD_0272="${MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_WORKSPACE_DOWNLOAD_0272:-1}"
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_HOST_CELLID_FILL_0327="${MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_HOST_CELLID_FILL_0327:-1}"
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_WALL_VP_DIAG_0319="${MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_WALL_VP_DIAG_0319:-1}"
}


# CUDA classic SRC wall-channel resident path: periodic x, solid top/bottom.
export MPCD_CUDA_CLASSIC_SRC_IO_SEGMENTED_RESIDENT_0264=0
export MPCD_CUDA_CLASSIC_SRC_IO_SEGMENTED_RESIDENT_0264_STRICT=0
export MPCD_CUDA_INLET_OUTLET_SEGMENTED_0249B=0
export MPCD_CUDA_STREAMING_WALL_SIMPLE_0246=1
export MPCD_CUDA_CLASSIC_SRC_WALL_RESIDENT_0261=1
export MPCD_CUDA_STREAMING_WALL_SIMPLE_0246_DOWNLOAD_ALL=0
export MPCD_CUDA_PERSISTENT_SRC_COLLISION_USE=1
export MPCD_CUDA_PERSISTENT_SRC_COLLISION_MINIMAL_DOWNLOAD_0257=1
export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SHARED_0251=1
export MPCD_CUDA_PERSISTENT_SRC_COLLISION_WALL_SIMPLE_0253=1
export MPCD_CUDA_PERSISTENT_SRC_COLLISION_STRICT=1
export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SHARED_0251_STRICT=1
export MPCD_CUDA_PERSISTENT_SRC_COLLISION_ACTIVE_STRICT=1
export MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_USE=1
export MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_STRICT=1
export MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_CONSUME_STRICT=1
export MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_SHARED_0251_0260=1
export MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_SHARED_0251_0260_STRICT=1


export_src_cuda_resident_fastflags_0426

export SRC_LIVE_VIS_ENABLE="$LIVE_VIS_ENABLE"
export MPCD_LIVE_VIS_ENABLE="$LIVE_VIS_ENABLE"
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
export SRC_LIVE_VIS_CUDA_FIELD="$LIVE_VIS_CUDA_FIELD"
export SRC_LIVE_VIS_CUDA_SNAPSHOT="$LIVE_VIS_CUDA_SNAPSHOT"
export SRC_LIVE_VIS_LOG_SOURCE="$LIVE_VIS_LOG_SOURCE"
export SRC_LIVE_VIS_CONTROL_FILE="$LIVE_VIS_CONTROL_FILE"
export SRC_LIVE_VIS_CONTROL_EVERY="$LIVE_VIS_CONTROL_EVERY"
export SRC_LIVE_VIS_CONTROL_LOG="$LIVE_VIS_CONTROL_LOG"

env | grep -E '^(MPCD_DARCY_FASTFLAGS_ENABLE=|MPCD_CUDA_|SRC_LIVE_VIS_|MPCD_LIVE_VIS_ENABLE=|OMP_|BIN=|CHI_FILE=|STATE_SOURCE=|INPUT_STATE=|DARCY_|TOPO_BENCHMARK_|ALPHA=|U0=|DT=|KBT=|NX=|NY=)' | sort > "$ENV_FILE"

echo "[0414-darcy-naca] binary=$BIN"
echo "[0414-darcy-naca] params=$PARAMS"
echo "[0414-darcy-naca] output=$OUT_DIR"
echo "[0414-darcy-naca] chi=$CHI_FILE format=$CHI_FILE_FORMAT alpha=$ALPHA U0=$U0 kBT=$KBT dt=$DT"
echo "[0414-darcy-naca] stateSource=$STATE_SOURCE"
echo "[0414-darcy-naca] topoBenchmark=$TOPO_BENCHMARK_ENABLE file=$TOPO_BENCHMARK_FILENAME every=$TOPO_BENCHMARK_EVERY force=$TOPO_BENCHMARK_FORCE_ENABLE dragLift=$TOPO_BENCHMARK_DRAG_LIFT_ENABLE"
echo "[0414-darcy-naca] periodic x-channel: bcLeft/right=periodic, bcBottom/top=solid, U0 initial=$U0"
echo "[0414-darcy-naca] livevis=$LIVE_VIS_ENABLE control=$LIVE_VIS_CONTROL_FILE field=$LIVE_VIS_FIELD"

/usr/bin/time -o "$TIME_FILE" -f 'elapsed=%e user=%U sys=%S' "$BIN" "$PARAMS"

echo "[0414-darcy-naca] time=$(cat "$TIME_FILE")"
echo "[0414-darcy-naca] darcy csv=$OUT_DIR/darcy_cost_0343.csv"
if [[ "$TOPO_BENCHMARK_ENABLE" == "true" || "$TOPO_BENCHMARK_ENABLE" == "1" || "$TOPO_BENCHMARK_ENABLE" == "TRUE" ]]; then
  echo "[0414-darcy-naca] topo benchmark csv=$OUT_DIR/$TOPO_BENCHMARK_FILENAME"
fi
echo "[0414-darcy-naca] dumps/root=$RUN_ROOT"
