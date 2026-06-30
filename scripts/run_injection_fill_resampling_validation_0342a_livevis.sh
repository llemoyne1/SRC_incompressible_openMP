#!/usr/bin/env bash
set -euo pipefail

# 0431 -- portable injection/fill validation with current SRC_GPU-Q6-CUDA path logic.
#
# This is the updated successor of run_injection_fill_resampling_validation_0342a_livevis.sh.
# It keeps the four validation families but uses the consolidated integration path
# names introduced in the lr_segmented/Darcy scripts:
#
#   RUN_CASES="src src-resampling src-q6 src-q6-resampling"
#
# Aliases are accepted:
#   classic -> src
#   classic_resampling -> src-resampling
#   q6 -> src-q6
#   q6_resampling -> src-q6-resampling
#
# The script is autonomous:
#   - if FILL_INITIAL_STATE exists, it is reused;
#   - otherwise an inactive-pool .smpcd state is generated inline.
#
# Boundary model:
#   - left face is solid with a segmented inlet;
#   - optional right outlet can be added as a full-height segmented outlet
#     with FILL_OUTLET_ENABLE=1.
#
# The current validated fast resident CUDA flags are enabled by default.
# Disable only for controlled ablations:
#   MPCD_INJECTION_FASTFLAGS_ENABLE=0

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

bool_true_0431() {
  case "${1:-0}" in
    1|true|TRUE|yes|YES|on|ON|enable|enabled) return 0 ;;
    *) return 1 ;;
  esac
}

BIN="${BIN:-build/src_mpcd_base_cuda_q6_resident_0400_livevis}"
AUTO_BUILD="${AUTO_BUILD:-1}"
BUILD_HELPER="${BUILD_HELPER:-scripts/build_src_mpcd_cuda_q6_resident_0400.sh}"
FORCE_REBUILD="${FORCE_REBUILD:-0}"

THREADS="${THREADS:-${FILL_THREADS:-8}}"
export OMP_NUM_THREADS="${OMP_NUM_THREADS:-$THREADS}"
export OMP_PROC_BIND="${OMP_PROC_BIND:-close}"
export OMP_PLACES="${OMP_PLACES:-cores}"
export OMP_DYNAMIC="${OMP_DYNAMIC:-false}"

RUN_ROOT=${RUN_ROOT:-runs/validate_0431_livevis_injection_fill_resampling}
INIT_ROOT=${INIT_ROOT:-init/injection_fill_resampling_0431}
STATE=${FILL_INITIAL_STATE:-$INIT_ROOT/initial_state_injection_fill_pool_0431.smpcd}
RUN_CASES=${RUN_CASES:-src src-resampling src-q6 src-q6-resampling}
CLEAN_RUN_ROOT=${CLEAN_RUN_ROOT:-1}
LIVE_PROGRESS=${LIVE_PROGRESS:-1}

FILL_LX=${FILL_LX:-4.0}
FILL_LY=${FILL_LY:-1.0}
FILL_NX=${FILL_NX:-192}
FILL_NY=${FILL_NY:-48}
FILL_GAMMA=${FILL_GAMMA:-20}
FILL_STEPS=${FILL_STEPS:-5000}
FILL_DT=${FILL_DT:-0.0005}
FILL_KBT=${FILL_KBT:-0.0001}
FILL_SEED=${FILL_SEED:-1390431}
FILL_STATE_SEED=${FILL_STATE_SEED:-$((FILL_SEED + 17))}
FILL_SUMMARY_EVERY=${FILL_SUMMARY_EVERY:-25}
FILL_DUMP_EVERY=${FILL_DUMP_EVERY:-1000}
FILL_THREADS=${FILL_THREADS:-$THREADS}
FILL_PARTICLE_MASS=${FILL_PARTICLE_MASS:-1.0}

# Initial pool capacity: one full-domain filling by default.
FILL_INACTIVE_SLOTS=${FILL_INACTIVE_SLOTS:-$((FILL_GAMMA * FILL_NX * FILL_NY))}

FILL_INLET_UX=${FILL_INLET_UX:-1.0}
FILL_INLET_TYPE=${FILL_INLET_TYPE:-0}
FILL_INLET_MASS=${FILL_INLET_MASS:-1.0}
FILL_INLET_CENTER_Y=${FILL_INLET_CENTER_Y:-0.5}
FILL_INLET_HEIGHT_CELLS=${FILL_INLET_HEIGHT_CELLS:-1.0}
FILL_INLET_RESERVOIR_CELLS=${FILL_INLET_RESERVOIR_CELLS:-1}
FILL_INLET_PROFILE=${FILL_INLET_PROFILE:-uniform}
FILL_INLET_TAPER_CELLS=${FILL_INLET_TAPER_CELLS:-0.0}
FILL_INLET_THERMAL_NOISE=${FILL_INLET_THERMAL_NOISE:-1.0}
FILL_RAMP_END_TIME=${FILL_RAMP_END_TIME:-0.2}

FILL_OUTLET_ENABLE=${FILL_OUTLET_ENABLE:-0}
FILL_OUTLET_MODE=${FILL_OUTLET_MODE:-hybrid}
FILL_OUTLET_HYBRID_BLEND=${FILL_OUTLET_HYBRID_BLEND:-0.5}
FILL_OUTLET_FEEDBACK_GAIN=${FILL_OUTLET_FEEDBACK_GAIN:-0.0}
FILL_OUTLET_SMIN=${FILL_OUTLET_SMIN:-0.0}
FILL_OUTLET_SMAX=${FILL_OUTLET_SMAX:-1.0}

PROJECTION_BACKEND=${PROJECTION_BACKEND:-cuda}
PROJECTION_OPERATOR=${PROJECTION_OPERATOR:-auto_fv_cg}
PROJECTION_MAX_ITERATIONS=${PROJECTION_MAX_ITERATIONS:-800}
PROJECTION_TOLERANCE=${PROJECTION_TOLERANCE:-1e-10}
PROJECTION_MOMENTUM_CORRECTION_ENABLE=${PROJECTION_MOMENTUM_CORRECTION_ENABLE:-true}
Q6_PROJECTION_STRENGTH=${Q6_PROJECTION_STRENGTH:-1.0}
Q6_STRICT=${Q6_STRICT:-1}

FILL_WALL_ACCOMMODATION=${FILL_WALL_ACCOMMODATION:-1.0}
FILL_WALL_VP_GAMMA=${FILL_WALL_VP_GAMMA:-$FILL_GAMMA}
FILL_WALL_THERMAL_NOISE=${FILL_WALL_THERMAL_NOISE:-0.0}

THERMOSTAT_ENABLE=${THERMOSTAT_ENABLE:-true}
THERMOSTAT_MODE=${THERMOSTAT_MODE:-cell_relative_rescale}
THERMOSTAT_EVERY=${THERMOSTAT_EVERY:-1}
THERMOSTAT_TARGET_KBT=${THERMOSTAT_TARGET_KBT:--1.0}
THERMOSTAT_MIN_PARTICLES=${THERMOSTAT_MIN_PARTICLES:-3}

FILL_RESAMP_POOR_FRACTION=${FILL_RESAMP_POOR_FRACTION:-0.50}
FILL_RESAMP_RICH_FRACTION=${FILL_RESAMP_RICH_FRACTION:-1.50}
FILL_MASS_MIN=${FILL_MASS_MIN:-0.5}
FILL_MASS_MAX=${FILL_MASS_MAX:-2.0}
FILL_MASS_RENORM_PERIOD=${FILL_MASS_RENORM_PERIOD:-10}

RESAMP_N_MIN=${RESAMP_N_MIN:-14}
RESAMP_N_TARGET=${RESAMP_N_TARGET:-20}
RESAMP_N_MAX=${RESAMP_N_MAX:-26}
GUARD_EVERY=${GUARD_EVERY:-5}

SUMMARY_ROLE_FILTER=${SUMMARY_ROLE_FILTER:-fluid}
DUMP_ROLE_FILTER=${DUMP_ROLE_FILTER:-fluid}

# Live visualization.
LIVE_VIS_ENABLE=${LIVE_VIS_ENABLE:-1}
LIVE_VIS_FIELD=${LIVE_VIS_FIELD:-density}
LIVE_VIS_COLORMAP=${LIVE_VIS_COLORMAP:-gray}
LIVE_VIS_EVERY=${LIVE_VIS_EVERY:-25}
LIVE_VIS_NX=${LIVE_VIS_NX:-768}
LIVE_VIS_NY=${LIVE_VIS_NY:-192}
LIVE_VIS_ALPHA=${LIVE_VIS_ALPHA:-0.08}
LIVE_VIS_CLIP=${LIVE_VIS_CLIP:--1}
LIVE_VIS_QUANTILE=${LIVE_VIS_QUANTILE:-0.995}
LIVE_VIS_GAIN=${LIVE_VIS_GAIN:-1.0}
LIVE_VIS_SMOOTH_PASSES=${LIVE_VIS_SMOOTH_PASSES:-2}
LIVE_VIS_WINDOW_SCALE=${LIVE_VIS_WINDOW_SCALE:-1}
LIVE_VIS_VSYNC=${LIVE_VIS_VSYNC:-0}
LIVE_VIS_LOG_SOURCE=${LIVE_VIS_LOG_SOURCE:-0}
LIVE_VIS_CUDA_FIELD=${LIVE_VIS_CUDA_FIELD:-1}
LIVE_VIS_CUDA_SNAPSHOT=${LIVE_VIS_CUDA_SNAPSHOT:-0}
LIVE_VIS_RESAMPLING_HOST_MIRROR=${LIVE_VIS_RESAMPLING_HOST_MIRROR:-0}
LIVE_VIS_FORCE_HOST_MIRROR=${LIVE_VIS_FORCE_HOST_MIRROR:-0}
LIVE_VIS_CONTROL_ENABLE=${LIVE_VIS_CONTROL_ENABLE:-1}
LIVE_VIS_CONTROL_FILE=${LIVE_VIS_CONTROL_FILE:-}
LIVE_VIS_CONTROL_DIR=${LIVE_VIS_CONTROL_DIR:-.}
LIVE_VIS_CONTROL_BASENAME=${LIVE_VIS_CONTROL_BASENAME:-livevis_control.kv}
LIVE_VIS_CONTROL_FILE_EFFECTIVE=""
LIVE_VIS_CONTROL_EVERY=${LIVE_VIS_CONTROL_EVERY:-1}
LIVE_VIS_CONTROL_LOG=${LIVE_VIS_CONTROL_LOG:-1}
LIVE_VIS_HOLD_ON_EXIT=${LIVE_VIS_HOLD_ON_EXIT:-1}

FILL_INLET_YMIN=${FILL_INLET_YMIN:-$(awk -v cy="$FILL_INLET_CENTER_Y" -v h="$FILL_INLET_HEIGHT_CELLS" -v ly="$FILL_LY" -v ny="$FILL_NY" 'BEGIN{dy=ly/ny; y=cy-0.5*h*dy; if(y<0)y=0; printf "%.17g", y}')}
FILL_INLET_YMAX=${FILL_INLET_YMAX:-$(awk -v cy="$FILL_INLET_CENTER_Y" -v h="$FILL_INLET_HEIGHT_CELLS" -v ly="$FILL_LY" -v ny="$FILL_NY" 'BEGIN{dy=ly/ny; y=cy+0.5*h*dy; if(y>ly)y=ly; printf "%.17g", y}')}

build_solver_0431() {
  if [[ -x "$BIN" && "$FORCE_REBUILD" != "1" && "$FORCE_REBUILD" != "true" && "$FORCE_REBUILD" != "TRUE" ]]; then
    return 0
  fi
  if ! bool_true_0431 "$AUTO_BUILD"; then
    echo "[0431-injection-fill] missing binary: $BIN" >&2
    exit 127
  fi
  if [[ ! -f "$BUILD_HELPER" ]]; then
    echo "[0431-injection-fill] missing CUDA build helper: $BUILD_HELPER" >&2
    exit 127
  fi
  echo "[0431-injection-fill] building $BIN with $BUILD_HELPER"
  MPCD_ENABLE_LIVE_VIS="${MPCD_ENABLE_LIVE_VIS:-1}" OUT="$BIN" CUDA_ARCH_FLAGS="${CUDA_ARCH_FLAGS:-}" bash "$BUILD_HELPER"
}

generate_empty_pool_state_0431() {
  local state=$1
  mkdir -p "$(dirname "$state")"
  python3 - "$state" "$FILL_INACTIVE_SLOTS" "$FILL_PARTICLE_MASS" <<'PYGEN'
import os, struct, sys
out, nslot, mass0 = sys.argv[1:]
nslot=int(nslot); mass0=float(mass0)
x=[0.0]*nslot; y=[0.0]*nslot; vx=[0.0]*nslot; vy=[0.0]*nslot
typ=[0]*nslot; mass=[mass0]*nslot; role=[0]*nslot
magic=b'SRCMPCD_STATE'+b'\0'*(16-len('SRCMPCD_STATE'))
reserved=[0]*8; reserved[0]=1; reserved[1]=1
os.makedirs(os.path.dirname(out) or '.', exist_ok=True)
with open(out,'wb') as f:
    f.write(magic)
    f.write(struct.pack('<IIIIQIIII',2,0x01020304,2,1,nslot,1,1,8,4))
    f.write(struct.pack('<8Q',*reserved))
    for arr,fmt in [(x,'d'),(y,'d'),(vx,'d'),(vy,'d'),(typ,'I'),(mass,'d'),(role,'B')]:
        f.write(struct.pack('<%d%s'%(nslot,fmt),*arr))
print(f"[0431-state] generated empty inactive-pool state={out} inactive={nslot}")
PYGEN
}

case_tuple_0431() {
  case "$1" in
    src|classic) echo "src false off true" ;;
    src-resampling|resampling|classic_resampling) echo "src-resampling false on true" ;;
    src-q6|q6) echo "src-q6 true off false" ;;
    src-q6-resampling|q6-resampling|q6_resampling) echo "src-q6-resampling true on false" ;;
    *) echo "[0431-injection-fill] unknown case '$1'. Expected src, src-resampling, src-q6, src-q6-resampling" >&2; return 2 ;;
  esac
}

path_has_q6_0431() { [[ "$1" == "src-q6" || "$1" == "src-q6-resampling" ]]; }
path_has_resampling_0431() { [[ "$1" == "src-resampling" || "$1" == "src-q6-resampling" ]]; }

livevis_prepare_control_0431() {
  local case_dir=$1
  LIVE_VIS_CONTROL_FILE_EFFECTIVE=""
  if ! bool_true_0431 "$LIVE_VIS_CONTROL_ENABLE"; then
    export LIVE_VIS_CONTROL_FILE_EFFECTIVE
    return 0
  fi
  if [[ -n "${LIVE_VIS_CONTROL_FILE:-}" ]]; then
    LIVE_VIS_CONTROL_FILE_EFFECTIVE="$LIVE_VIS_CONTROL_FILE"
  elif [[ -n "${LIVE_VIS_CONTROL_DIR:-}" ]]; then
    LIVE_VIS_CONTROL_FILE_EFFECTIVE="$LIVE_VIS_CONTROL_DIR/$LIVE_VIS_CONTROL_BASENAME"
  else
    LIVE_VIS_CONTROL_FILE_EFFECTIVE="$case_dir/$LIVE_VIS_CONTROL_BASENAME"
  fi
  export LIVE_VIS_CONTROL_FILE_EFFECTIVE
  mkdir -p "$(dirname "$LIVE_VIS_CONTROL_FILE_EFFECTIVE")"
  if [[ ! -f "$LIVE_VIS_CONTROL_FILE_EFFECTIVE" ]]; then
    cat > "$LIVE_VIS_CONTROL_FILE_EFFECTIVE" <<CONTROL
field = ${LIVE_VIS_FIELD}
colormap = ${LIVE_VIS_COLORMAP}
clip = ${LIVE_VIS_CLIP}
gain = ${LIVE_VIS_GAIN}
smoothPasses = ${LIVE_VIS_SMOOTH_PASSES}
CONTROL
  fi
  echo "[0431-livevis] runtime control file: $LIVE_VIS_CONTROL_FILE_EFFECTIVE"
}

livevis_env_0431() {
  local resampling=$1
  export SRC_LIVE_VIS_ENABLE="$LIVE_VIS_ENABLE"
  export MPCD_LIVE_VIS_ENABLE="$LIVE_VIS_ENABLE"
  export SRC_LIVE_VIS_FIELD="$LIVE_VIS_FIELD"
  export SRC_LIVE_VIS_COLORMAP="$LIVE_VIS_COLORMAP"
  export SRC_LIVE_VIS_EVERY="$LIVE_VIS_EVERY"
  export SRC_LIVE_VIS_NX="$LIVE_VIS_NX"
  export SRC_LIVE_VIS_NY="$LIVE_VIS_NY"
  export SRC_LIVE_VIS_ALPHA="$LIVE_VIS_ALPHA"
  export SRC_LIVE_VIS_CLIP="$LIVE_VIS_CLIP"
  export SRC_LIVE_VIS_QUANTILE="$LIVE_VIS_QUANTILE"
  export SRC_LIVE_VIS_GAIN="$LIVE_VIS_GAIN"
  export SRC_LIVE_VIS_SMOOTH_PASSES="$LIVE_VIS_SMOOTH_PASSES"
  export SRC_LIVE_VIS_WINDOW_SCALE="$LIVE_VIS_WINDOW_SCALE"
  export SRC_LIVE_VIS_VSYNC="$LIVE_VIS_VSYNC"
  export SRC_LIVE_VIS_LOG_SOURCE="$LIVE_VIS_LOG_SOURCE"
  export SRC_LIVE_VIS_CUDA_FIELD="$LIVE_VIS_CUDA_FIELD"
  export SRC_LIVE_VIS_CUDA_SNAPSHOT="$LIVE_VIS_CUDA_SNAPSHOT"
  export SRC_LIVE_VIS_FORCE_HOST_MIRROR="$LIVE_VIS_FORCE_HOST_MIRROR"
  export SRC_LIVE_VIS_CONTROL_FILE="${LIVE_VIS_CONTROL_FILE_EFFECTIVE:-}"
  export SRC_LIVE_VIS_CONTROL_EVERY="$LIVE_VIS_CONTROL_EVERY"
  export SRC_LIVE_VIS_CONTROL_LOG="$LIVE_VIS_CONTROL_LOG"
  export SRC_LIVE_VIS_HOLD_ON_EXIT="$LIVE_VIS_HOLD_ON_EXIT"
  if [[ "$resampling" == "on" ]]; then
    export SRC_LIVE_VIS_RESAMPLING_HOST_MIRROR="$LIVE_VIS_RESAMPLING_HOST_MIRROR"
  else
    export SRC_LIVE_VIS_RESAMPLING_HOST_MIRROR=0
  fi
}

cuda_env_clear_0431() {
  export MPCD_CUDA_CLASSIC_SRC_PERIODIC_RESIDENT_0260=0
  export MPCD_CUDA_CLASSIC_SRC_WALL_RESIDENT_0261=0
  export MPCD_CUDA_CLASSIC_SRC_SOLID_RESIDENT_0262=0
  export MPCD_CUDA_CLASSIC_SRC_IO_FULLFACE_RESIDENT_0263=0
  export MPCD_CUDA_CLASSIC_SRC_IO_FULLFACE_RESIDENT_0263_STRICT=0
  export MPCD_CUDA_CLASSIC_SRC_IO_SEGMENTED_RESIDENT_0264=0
  export MPCD_CUDA_CLASSIC_SRC_IO_SEGMENTED_RESIDENT_0264_STRICT=0
  export MPCD_CUDA_STREAMING_PERIODIC_0245=0
  export MPCD_CUDA_STREAMING_WALL_SIMPLE_0246=0
  export MPCD_CUDA_INLET_OUTLET_FULLFACE_0249A=0
  export MPCD_CUDA_INLET_OUTLET_SEGMENTED_0249B=0
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_USE=0
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SHARED_0251=0
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_WALL_SIMPLE_0253=0
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_STRICT=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SHARED_0251_STRICT=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_ACTIVE_STRICT=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_MINIMAL_DOWNLOAD_0257=1
  export MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_USE=0
  export MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_STRICT=1
  export MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_SHARED_0251_0260=0
  export MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_SHARED_0251_0260_STRICT=0
  export MPCD_CUDA_Q6_RESIDENT_0400=0
  export MPCD_CUDA_Q6_RESIDENT_STRICT_0400=0
  export MPCD_CUDA_Q6_RESIDENT_SRC_IO_SEGMENTED_0409=0
  export MPCD_CUDA_RESAMPLING_MASS_RECONDITION_0296=0
  export MPCD_CUDA_RESAMPLING_EMPTY_REFILL_0319=0
  export MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297=0
  export MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0299_BOUNDARY_AWARE=0
  export MPCD_CUDA_RESAMPLING_SPLIT_SAFETY_0307=0
}

apply_fastflags_0431() {
  case "${MPCD_INJECTION_FASTFLAGS_ENABLE:-1}" in
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

cuda_env_for_case_0431() {
  local path=$1
  cuda_env_clear_0431
  export MPCD_CUDA_CLASSIC_SRC_IO_SEGMENTED_RESIDENT_0264=1
  export MPCD_CUDA_CLASSIC_SRC_IO_SEGMENTED_RESIDENT_0264_STRICT=1
  export MPCD_CUDA_INLET_OUTLET_SEGMENTED_0249B=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_USE=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SHARED_0251=1
  if path_has_q6_0431 "$path"; then
    export MPCD_CUDA_Q6_RESIDENT_0400=1
    export MPCD_CUDA_Q6_RESIDENT_STRICT_0400="$Q6_STRICT"
    export MPCD_CUDA_Q6_RESIDENT_SRC_IO_SEGMENTED_0409=1
    export MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_USE=0
    export MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_SHARED_0251_0260=0
  else
    export MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_USE=1
    export MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_SHARED_0251_0260=0
  fi
  if path_has_resampling_0431 "$path"; then
    export MPCD_CUDA_RESAMPLING_MASS_RECONDITION_0296="${MPCD_CUDA_RESAMPLING_MASS_RECONDITION_0296:-1}"
    export MPCD_CUDA_RESAMPLING_MASS_RECONDITION_0296_EVERY="${MPCD_CUDA_RESAMPLING_MASS_RECONDITION_0296_EVERY:-$GUARD_EVERY}"
    export MPCD_CUDA_RESAMPLING_MASS_RECONDITION_0296_STRENGTH="${MPCD_CUDA_RESAMPLING_MASS_RECONDITION_0296_STRENGTH:-1.0}"
    export MPCD_CUDA_RESAMPLING_EMPTY_REFILL_0319=1
    export MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297="${MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297:-1}"
    export MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0299_BOUNDARY_AWARE="${MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0299_BOUNDARY_AWARE:-1}"
    export MPCD_CUDA_RESAMPLING_SPLIT_SAFETY_0307=1
    export MPCD_CUDA_RESAMPLING_SPLIT_PREFER_MAX_MASS_DONOR_0307=1
  fi
  apply_fastflags_0431
}

write_env_file_0431() {
  local file=$1 label=$2 projection=$3 resampling=$4
  mkdir -p "$(dirname "$file")"
  env | grep -E '^(MPCD_INJECTION_FASTFLAGS_ENABLE=|MPCD_CUDA_|SRC_LIVE_VIS_|MPCD_LIVE_VIS_ENABLE=|OMP_|BIN=|THREADS=|RUN_CASES=|RUN_ROOT=|STATE=|FILL_|LIVE_VIS_|PROJECTION_|Q6_)' | sort > "$file"
  cat >> "$file" <<META
label=${label}
projection=${projection}
resampling=${resampling}
BIN=${BIN}
RUN_ROOT=${RUN_ROOT}
STATE=${STATE}
META
}

write_params_0431() {
  local label=$1 projection=$2 resampling=$3 classic_cuda=$4
  local out_dir="$RUN_ROOT/$label"
  local params_file="$RUN_ROOT/params_${label}.kv"
  mkdir -p "$out_dir"
  local inlet_smin inlet_smax seg_count
  inlet_smin=$(awk -v y="$FILL_INLET_YMIN" -v ly="$FILL_LY" 'BEGIN{printf "%.17g", y/ly}')
  inlet_smax=$(awk -v y="$FILL_INLET_YMAX" -v ly="$FILL_LY" 'BEGIN{printf "%.17g", y/ly}')
  if bool_true_0431 "$FILL_OUTLET_ENABLE"; then seg_count=2; else seg_count=1; fi
  cat > "$params_file" <<PARAMS
inputState = $STATE
outputDir = $out_dir

Lx = $FILL_LX
Ly = $FILL_LY
Nx = $FILL_NX
Ny = $FILL_NY

fluidXMin0 = 0.0
fluidXMax0 = -1.0
fluidYMin0 = 0.0
fluidYMax0 = -1.0

dt = $FILL_DT
nSteps = $FILL_STEPS

rotationAngle = 2.0943951023931953
randomRotationSign = true
gridShiftEnable = true
rngSeed = $FILL_SEED

srcClassicCudaModeEnable = $classic_cuda
projectionEnable = $projection
projectionBackend = $PROJECTION_BACKEND
projectionOperator = $PROJECTION_OPERATOR
projectionMaxIterations = $PROJECTION_MAX_ITERATIONS
projectionTolerance = $PROJECTION_TOLERANCE
projectionMomentumCorrectionEnable = $PROJECTION_MOMENTUM_CORRECTION_ENABLE
q6ProjectionStrength = $Q6_PROJECTION_STRENGTH
projectionImmersedSolidMaskEnable = false
projectionImmersedSolidCloseCutFaces = false
projectionAllowUnmaskedImmersedSolid = true

bodyAccelerationX = 0.0
bodyAccelerationY = 0.0

bcLeft = solid
bcRight = solid
bcBottom = solid
bcTop = solid
bcX = solid
bcY = solid

openBoundarySegmentsEnable = true
openBoundarySegmentCount = $seg_count
openBoundarySegment0 = left inlet $inlet_smin $inlet_smax $FILL_INLET_UX 0.0 $FILL_INLET_TYPE $FILL_INLET_MASS
PARAMS
  if bool_true_0431 "$FILL_OUTLET_ENABLE"; then
    cat >> "$params_file" <<PARAMS
openBoundarySegment1 = right outlet $FILL_OUTLET_SMIN $FILL_OUTLET_SMAX $FILL_INLET_UX 0.0 0 1.0
PARAMS
  fi
  cat >> "$params_file" <<PARAMS

inletUxLeft = $FILL_INLET_UX
inletUyLeft = 0.0
inletVelocityRampEnable = true
inletVelocityRampStartTime = 0.0
inletVelocityRampEndTime = $FILL_RAMP_END_TIME
inletVelocityRampInitialFactor = 0.0
inletVelocityRampFinalFactor = 1.0
inletVelocityRampProfile = smoothstep
inletVelocitySpatialProfile = $FILL_INLET_PROFILE
inletVelocityWallTaperCells = $FILL_INLET_TAPER_CELLS
inletKBT = -0.0001
inletThermalNoise = $FILL_INLET_THERMAL_NOISE
inletInjectionMode = hard_cell_density
inletReservoirMode = hard_cell_density
inletReservoirCells = $FILL_INLET_RESERVOIR_CELLS
inletTargetOccupancy = $FILL_GAMMA
inletHardCellVelocityMean = true
inletHardCellThermalRescale = true
inletRandomizeTangential = true
inletReinjectBackflow = true

openBoundaryOutletMode = $FILL_OUTLET_MODE
openBoundaryOutletHybridBlend = $FILL_OUTLET_HYBRID_BLEND
openBoundaryOutletFeedbackGain = $FILL_OUTLET_FEEDBACK_GAIN

immersedSolidEnable = false

wallAccommodation = $FILL_WALL_ACCOMMODATION
wallVpGamma = $FILL_WALL_VP_GAMMA
wallVpMass = $FILL_PARTICLE_MASS
wallKBT = -1.0
wallThermalNoise = $FILL_WALL_THERMAL_NOISE

thermostatEnable = $THERMOSTAT_ENABLE
thermostatMode = $THERMOSTAT_MODE
thermostatEvery = $THERMOSTAT_EVERY
thermostatTargetKBT = $THERMOSTAT_TARGET_KBT
thermostatMinParticles = $THERMOSTAT_MIN_PARTICLES
kBT = $FILL_KBT

closedCapacityResponseEnable = false
closedCapacityVirialKickEnable = false
PARAMS
  if [[ "$resampling" == "on" ]]; then
    cat >> "$params_file" <<PARAMS

resamplingEnable = true
resamplingPopulationNMin = $RESAMP_N_MIN
resamplingPopulationNTarget = $RESAMP_N_TARGET
resamplingPopulationNMax = $RESAMP_N_MAX
resamplingPopulationMaxSplitsPerCell = ${RESAMP_POP_MAX_SPLITS_PER_CELL:-16}
resamplingPopulationMaxSplitsPerStep = ${RESAMP_POP_MAX_SPLITS_PER_STEP:-200000}
resamplingPopulationMaxExtractionsPerCell = ${RESAMP_POP_MAX_EXTRACT_PER_CELL:-64}
resamplingPopulationMaxExtractionsPerStep = ${RESAMP_POP_MAX_EXTRACT_PER_STEP:-200000}
resamplingTargetCellMass = $FILL_GAMMA
resamplingWetMaskMode = occupied
resamplingWetCellMassThreshold = 0.0
resamplingPoorCellMassFraction = $FILL_RESAMP_POOR_FRACTION
resamplingRichCellMassFraction = $FILL_RESAMP_RICH_FRACTION
resamplingActiveFluidFractionThreshold = 0.5
resamplingExtractionEnable = true
resamplingInsertionEnable = true
resamplingRemapEnable = true
resamplingMassRenormalizationPeriod = $FILL_MASS_RENORM_PERIOD
resamplingThermalRenormalizationEnable = true
resamplingMassGuardEnable = true
resamplingParticleMassMin = $FILL_MASS_MIN
resamplingParticleMassMax = $FILL_MASS_MAX
resamplingLatentActivationEnable = false
PARAMS
  else
    cat >> "$params_file" <<PARAMS

resamplingEnable = false
PARAMS
  fi
  cat >> "$params_file" <<PARAMS

summaryEvery = $FILL_SUMMARY_EVERY
dumpStateEvery = $FILL_DUMP_EVERY
summaryRoleFilter = $SUMMARY_ROLE_FILTER
dumpRoleFilter = $DUMP_ROLE_FILTER
numThreads = $FILL_THREADS
PARAMS
  echo "$params_file"
}

run_case_0431() {
  local label=$1 projection=$2 resampling=$3 classic_cuda=$4
  local params_file out_dir log_file time_file env_file
  params_file=$(write_params_0431 "$label" "$projection" "$resampling" "$classic_cuda")
  out_dir="$RUN_ROOT/$label"
  log_file="$RUN_ROOT/logs/${label}_0431_livevis.log"
  time_file="$RUN_ROOT/logs/${label}_0431_livevis.time"
  env_file="$RUN_ROOT/logs/environment_${label}_0431.env"

  cuda_env_for_case_0431 "$label"
  livevis_prepare_control_0431 "$out_dir"
  livevis_env_0431 "$resampling"
  write_env_file_0431 "$env_file" "$label" "$projection" "$resampling"

  echo "[0431-injection-fill] Running $label (projection=$projection, resampling=$resampling, classicCuda=$classic_cuda)"
  echo "[0431-injection-fill] binary : $BIN"
  echo "[0431-injection-fill] params : $params_file"
  echo "[0431-injection-fill] output : $out_dir"
  local rc=0
  if bool_true_0431 "$LIVE_PROGRESS"; then
    /usr/bin/time -f 'elapsed=%e user=%U sys=%S' "$BIN" "$params_file" 2> "$time_file" | tee "$log_file" || rc=$?
  else
    /usr/bin/time -f 'elapsed=%e user=%U sys=%S' "$BIN" "$params_file" > "$log_file" 2> "$time_file" || rc=$?
  fi
  cat "$time_file"
  if [[ "$rc" != "0" ]]; then
    echo "[0431-injection-fill] ERROR: $label failed rc=$rc" >&2
    tail -80 "$log_file" >&2 || true
    tail -80 "$time_file" >&2 || true
    return "$rc"
  fi
}

build_solver_0431
if [[ ! -x "$BIN" ]]; then echo "[0431-injection-fill] missing executable: $BIN" >&2; exit 127; fi

if [[ ! -f "$STATE" ]]; then
  echo "[0431-injection-fill] initial state not found; generating autonomous inactive pool: $STATE"
  generate_empty_pool_state_0431 "$STATE"
else
  echo "[0431-injection-fill] using existing initial state: $STATE"
fi

if bool_true_0431 "$CLEAN_RUN_ROOT"; then rm -rf "$RUN_ROOT"; fi
mkdir -p "$RUN_ROOT/logs"

for case_name in $RUN_CASES; do
  read -r label projection resampling classic_cuda <<< "$(case_tuple_0431 "$case_name")"
  run_case_0431 "$label" "$projection" "$resampling" "$classic_cuda"
done

cat <<MSG
[0431-injection-fill] completed.
Run root: $RUN_ROOT
Initial state: $STATE

Typical short smoke test:
  FILL_STEPS=100 RUN_CASES=src LIVE_VIS_ENABLE=0 bash scripts/run_injection_fill_resampling_validation_0342a_livevis.sh
MSG
