#!/usr/bin/env bash
set -euo pipefail

# Injection/fill resampling validation adapted for SRC_GPU-VIZ 0342a.
#
# This script keeps the original 0139/0209a four-case validation structure
# (classic, classic_resampling, q6, q6_resampling) but launches the CUDA-VIZ
# binary and enables 0341/0342 live visualization runtime controls.
#
# The default CUDA settings are intentionally conservative: the script does not
# force a resident segmented-inlet CUDA path by default because the purpose of
# this validation is to preserve the Q6/resampling reference behavior. Enable
# FILL_CUDA_SEGMENTED_RESIDENT=1 explicitly only after a dedicated comparison.

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT_DIR"

BIN="${BIN:-build/src_mpcd_base_cuda_livevis_0342a}"
AUTO_BUILD="${AUTO_BUILD:-1}"
BUILD_HELPER="${BUILD_HELPER:-scripts/build_src_mpcd_cuda_0315b.sh}"
FORCE_REBUILD="${FORCE_REBUILD:-0}"
THREADS="${THREADS:-${FILL_THREADS:-8}}"
export OMP_NUM_THREADS="${OMP_NUM_THREADS:-$THREADS}"
export OMP_PROC_BIND="${OMP_PROC_BIND:-close}"
export OMP_PLACES="${OMP_PLACES:-cores}"
export OMP_DYNAMIC="${OMP_DYNAMIC:-false}"

# 0209a validation mode: reuse the resampling pool at step start only.
# Keep the more aggressive guard/maps experiments disabled unless overridden.
export MPCD_ENABLE_INCREMENTAL_RESAMPLING_POOL="${MPCD_ENABLE_INCREMENTAL_RESAMPLING_POOL:-1}"

portable_bool_true_0342() {
  case "${1:-0}" in
    1|true|TRUE|yes|YES|on|ON|enable|enabled) return 0 ;;
    *) return 1 ;;
  esac
}

build_solver() {
  if [[ -x "$BIN" && "$FORCE_REBUILD" != "1" && "$FORCE_REBUILD" != "true" && "$FORCE_REBUILD" != "TRUE" ]]; then
    return 0
  fi
  if ! portable_bool_true_0342 "$AUTO_BUILD"; then
    echo "[0342a-injection-fill] missing binary: $BIN" >&2
    exit 127
  fi
  if [[ ! -f "$BUILD_HELPER" ]]; then
    echo "[0342a-injection-fill] missing CUDA build helper: $BUILD_HELPER" >&2
    exit 127
  fi
  echo "[0342a-injection-fill] building $BIN with $BUILD_HELPER"
  MPCD_ENABLE_LIVE_VIS="${MPCD_ENABLE_LIVE_VIS:-1}" \
  OUT="$BIN" CUDA_ARCH_FLAGS="${CUDA_ARCH_FLAGS:-}" bash "$BUILD_HELPER"
}

RUN_ROOT=${RUN_ROOT:-runs/validate_0342a_livevis_injection_fill_resampling_0139}
INIT_ROOT=${INIT_ROOT:-init/injection_fill_resampling_0139}
STATE=${FILL_INITIAL_STATE:-$INIT_ROOT/initial_state_injection_fill_0139.smpcd}
RUN_CASES=${RUN_CASES:-classic classic_resampling q6 q6_resampling}
CLEAN_RUN_ROOT=${CLEAN_RUN_ROOT:-1}
LIVE_PROGRESS=${LIVE_PROGRESS:-0}

FILL_LX=${FILL_LX:-4.0}
FILL_LY=${FILL_LY:-1.0}
FILL_NX=${FILL_NX:-192}
FILL_NY=${FILL_NY:-48}
FILL_GAMMA=${FILL_GAMMA:-20}
FILL_STEPS=${FILL_STEPS:-14000}
FILL_DT=${FILL_DT:-0.0001}
FILL_KBT=${FILL_KBT:-0.1}
FILL_SEED=${FILL_SEED:-1390139}
FILL_SUMMARY_EVERY=${FILL_SUMMARY_EVERY:-25}
FILL_DUMP_EVERY=${FILL_DUMP_EVERY:-1000}
FILL_THREADS=${FILL_THREADS:-$THREADS}

FILL_INLET_UX=${FILL_INLET_UX:-0.9}
FILL_INLET_CENTER_Y=${FILL_INLET_CENTER_Y:-0.5}
FILL_INLET_HEIGHT_CELLS=${FILL_INLET_HEIGHT_CELLS:-5.0}
FILL_INLET_RESERVOIR_CELLS=${FILL_INLET_RESERVOIR_CELLS:-1}
FILL_INLET_PROFILE=${FILL_INLET_PROFILE:-uniform}
FILL_INLET_TAPER_CELLS=${FILL_INLET_TAPER_CELLS:-0.0}
FILL_INLET_THERMAL_NOISE=${FILL_INLET_THERMAL_NOISE:-1.0}
FILL_RAMP_END_TIME=${FILL_RAMP_END_TIME:-0.2}
FILL_OUTLET_MODE=${FILL_OUTLET_MODE:-hybrid}
FILL_OUTLET_HYBRID_BLEND=${FILL_OUTLET_HYBRID_BLEND:-0.5}
FILL_OUTLET_FEEDBACK_GAIN=${FILL_OUTLET_FEEDBACK_GAIN:-0.0}
FILL_PROJECTION_OPERATOR=${FILL_PROJECTION_OPERATOR:-elliptic_fv_cg}
FILL_SRC_CLASSIC_CUDA_MODE_ENABLE=${FILL_SRC_CLASSIC_CUDA_MODE_ENABLE:-true}

FILL_WALL_ACCOMMODATION=${FILL_WALL_ACCOMMODATION:-1.0}
FILL_WALL_VP_GAMMA=${FILL_WALL_VP_GAMMA:-$FILL_GAMMA}
FILL_WALL_THERMAL_NOISE=${FILL_WALL_THERMAL_NOISE:-1.0}

FILL_RESAMP_POOR_FRACTION=${FILL_RESAMP_POOR_FRACTION:-0.50}
FILL_RESAMP_RICH_FRACTION=${FILL_RESAMP_RICH_FRACTION:-1.50}
FILL_MASS_MIN=${FILL_MASS_MIN:-0.5}
FILL_MASS_MAX=${FILL_MASS_MAX:-2.0}
FILL_MASS_RENORM_PERIOD=${FILL_MASS_RENORM_PERIOD:-10}

# Live visualization defaults for an injection/fill front.  The control file can
# be edited while the run is active; recommended fields are density, speed, ux,
# uy and vorticity.
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

export LIVE_VIS_CONTROL_ENABLE LIVE_VIS_CONTROL_FILE LIVE_VIS_CONTROL_DIR
export LIVE_VIS_CONTROL_BASENAME LIVE_VIS_CONTROL_EVERY LIVE_VIS_CONTROL_LOG
export LIVE_VIS_COLORMAP

# Optional experimental CUDA segmented resident path. Disabled by default to keep
# the Q6/resampling validation conservative. It is automatically not applied to
# Q6 cases unless FILL_CUDA_SEGMENTED_RESIDENT_Q6=1 is explicitly set.
FILL_CUDA_SEGMENTED_RESIDENT=${FILL_CUDA_SEGMENTED_RESIDENT:-0}
FILL_CUDA_SEGMENTED_RESIDENT_Q6=${FILL_CUDA_SEGMENTED_RESIDENT_Q6:-0}

FILL_INLET_YMIN=${FILL_INLET_YMIN:-$(awk -v cy="$FILL_INLET_CENTER_Y" -v h="$FILL_INLET_HEIGHT_CELLS" -v ly="$FILL_LY" -v ny="$FILL_NY" 'BEGIN{dy=ly/ny; y=cy-0.5*h*dy; if(y<0)y=0; printf "%.17g", y}')}
FILL_INLET_YMAX=${FILL_INLET_YMAX:-$(awk -v cy="$FILL_INLET_CENTER_Y" -v h="$FILL_INLET_HEIGHT_CELLS" -v ly="$FILL_LY" -v ny="$FILL_NY" 'BEGIN{dy=ly/ny; y=cy+0.5*h*dy; if(y>ly)y=ly; printf "%.17g", y}')}

build_solver
if [[ ! -x "$BIN" ]]; then
  echo "Missing executable '$BIN'." >&2
  exit 127
fi

if [[ ! -f "$STATE" ]]; then
  cat >&2 <<MSG
Missing initial inactive-pool state:
  $STATE

Generate it from MATLAB before launching the CUDA-VIZ validation. From the repository root:

  cd matlab

then in MATLAB:

  prepare_injection_fill_resampling_0139( ...
      'output', '../$STATE', ...
      'Lx', $FILL_LX, 'Ly', $FILL_LY, ...
      'Nx', $FILL_NX, 'Ny', $FILL_NY, 'gamma', $FILL_GAMMA, ...
      'capacityMultiplier', 1.0, ...
      'kBT', $FILL_KBT, ...
      'seed', $FILL_SEED, ...
      'inletYCenter', $FILL_INLET_CENTER_Y, ...
      'inletHeightCells', $FILL_INLET_HEIGHT_CELLS, ...
      'makePreview', true);

Then return to the repository root and rerun:
  $0
MSG
  exit 2
fi

if portable_bool_true_0342 "$CLEAN_RUN_ROOT"; then
  rm -rf "$RUN_ROOT"
fi
mkdir -p "$RUN_ROOT/logs"

livevis_prepare_control_0342a() {
  local case_dir=$1
  LIVE_VIS_CONTROL_FILE_EFFECTIVE=""
  if ! portable_bool_true_0342 "$LIVE_VIS_CONTROL_ENABLE"; then
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
# 0342a live visualization runtime controls. Edit this file while the simulation runs.
# Supported keys: field, colormap, clip, gain, smoothPasses.
# Colormaps: blue_red, gray, thermal.
field = ${LIVE_VIS_FIELD}
colormap = ${LIVE_VIS_COLORMAP}
clip = ${LIVE_VIS_CLIP}
gain = ${LIVE_VIS_GAIN}
smoothPasses = ${LIVE_VIS_SMOOTH_PASSES}
CONTROL
  fi
  echo "[0342a-livevis] runtime control file: $LIVE_VIS_CONTROL_FILE_EFFECTIVE"
}

livevis_env_0342a() {
  local resampling=$1
  export SRC_LIVE_VIS_ENABLE="$LIVE_VIS_ENABLE"
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
  if [[ "$resampling" == "on" ]]; then
    export SRC_LIVE_VIS_RESAMPLING_HOST_MIRROR="$LIVE_VIS_RESAMPLING_HOST_MIRROR"
  else
    export SRC_LIVE_VIS_RESAMPLING_HOST_MIRROR=0
  fi
}

cuda_env_clear_0342a() {
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
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_STRICT=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_ACTIVE_STRICT=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_MINIMAL_DOWNLOAD_0257=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SHARED_0251=0
  export MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_USE=0
  export MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_SHARED_0251_0260=0
  export MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_SHARED_0251_0260_STRICT=1
  export MPCD_CUDA_PERSISTENT_PARTICLE_STATE_USE=1
  export MPCD_CUDA_PERSISTENT_PARTICLE_METADATA_CACHE=1
  export MPCD_CUDA_PERSISTENT_CELL_WORKSPACE_USE=1
  export MPCD_CUDA_PERSISTENT_THREADS_PER_BLOCK="${MPCD_CUDA_PERSISTENT_THREADS_PER_BLOCK:-256}"
}

cuda_env_for_case_0342a() {
  local projection=$1 resampling=$2
  cuda_env_clear_0342a
  local allow_resident="$FILL_CUDA_SEGMENTED_RESIDENT"
  if [[ "$projection" == "true" ]] && ! portable_bool_true_0342 "$FILL_CUDA_SEGMENTED_RESIDENT_Q6"; then
    allow_resident=0
  fi
  if portable_bool_true_0342 "$allow_resident"; then
    export MPCD_CUDA_CLASSIC_SRC_IO_SEGMENTED_RESIDENT_0264=1
    export MPCD_CUDA_CLASSIC_SRC_IO_SEGMENTED_RESIDENT_0264_STRICT=1
    export MPCD_CUDA_INLET_OUTLET_SEGMENTED_0249B=1
    export MPCD_CUDA_PERSISTENT_SRC_COLLISION_USE=1
    export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SHARED_0251=1
    export MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_USE=1
    export MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_SHARED_0251_0260=1
    echo "[0342a-cuda] segmented resident path requested for projection=$projection resampling=$resampling"
  else
    echo "[0342a-cuda] conservative CUDA-VIZ mode: no segmented resident path forced for projection=$projection resampling=$resampling"
  fi
}

write_env_file_0342a() {
  local file=$1 label=$2 projection=$3 resampling=$4
  mkdir -p "$(dirname "$file")"
  env | grep -E '^(MPCD_CUDA_|SRC_LIVE_VIS_|MPCD_ENABLE_LIVE_VIS=|OMP_|BIN=|THREADS=|RUN_CASES=|RUN_ROOT=|STATE=|FILL_|LIVE_VIS_)' | sort > "$file"
  cat >> "$file" <<META
label=${label}
projection=${projection}
resampling=${resampling}
BIN=${BIN}
RUN_ROOT=${RUN_ROOT}
STATE=${STATE}
META
}

write_params() {
  local label=$1
  local projection=$2
  local resampling=$3
  local out_dir="$RUN_ROOT/$label"
  local params_file="$RUN_ROOT/params_${label}.kv"
  mkdir -p "$out_dir"
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

srcClassicCudaModeEnable = $FILL_SRC_CLASSIC_CUDA_MODE_ENABLE

bodyAccelerationX = 0.0
bodyAccelerationY = 0.0

bcLeft = solid
bcRight = solid
bcBottom = solid
bcTop = solid

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
inletKBT = -1.0
inletThermalNoise = $FILL_INLET_THERMAL_NOISE
inletInjectionMode = hard_cell_density
inletReservoirMode = hard_cell_density
inletReservoirCells = $FILL_INLET_RESERVOIR_CELLS
inletTargetOccupancy = $FILL_GAMMA
inletHardCellVelocityMean = true
inletHardCellThermalRescale = true
inletRandomizeTangential = true
inletReinjectBackflow = true

openBoundarySegmentsEnable = true
openBoundarySegmentCount = 1
openBoundarySegment0 = left inlet $(awk -v y="$FILL_INLET_YMIN" -v ly="$FILL_LY" 'BEGIN{printf "%.17g", y/ly}') $(awk -v y="$FILL_INLET_YMAX" -v ly="$FILL_LY" 'BEGIN{printf "%.17g", y/ly}') $FILL_INLET_UX 0.0 0 1.0
openBoundaryOutletMode = $FILL_OUTLET_MODE
openBoundaryOutletHybridBlend = $FILL_OUTLET_HYBRID_BLEND
openBoundaryOutletFeedbackGain = $FILL_OUTLET_FEEDBACK_GAIN

projectionEnable = $projection
projectionOperator = $FILL_PROJECTION_OPERATOR
projectionMaxIterations = 800
projectionTolerance = 1.0e-10
projectionMomentumCorrectionEnable = true
q6ProjectionStrength = 1.0
projectionImmersedSolidMaskEnable = false
projectionImmersedSolidCloseCutFaces = false
projectionAllowUnmaskedImmersedSolid = true

immersedSolidEnable = false

wallAccommodation = $FILL_WALL_ACCOMMODATION
wallVpGamma = $FILL_WALL_VP_GAMMA
wallVpMass = 1.0
wallKBT = -1.0
wallThermalNoise = $FILL_WALL_THERMAL_NOISE

thermostatEnable = true
thermostatMode = cell_relative_rescale
thermostatEvery = 1
thermostatTargetKBT = -1.0
thermostatMinParticles = 3
kBT = $FILL_KBT

summaryEvery = $FILL_SUMMARY_EVERY
dumpStateEvery = $FILL_DUMP_EVERY
summaryRoleFilter = ${SUMMARY_ROLE_FILTER:-fluid}
dumpRoleFilter = ${DUMP_ROLE_FILTER:-fluid}
numThreads = $FILL_THREADS
PARAMS

  if [[ "$resampling" == "on" ]]; then
    cat >> "$params_file" <<PARAMS

# Wet/dry injection/fill stress test. Empty cells remain dry: they must not be
# forced to Mtarget before the advected front reaches them.
resamplingEnable = true
resamplingPopulationNMin = ${RESAMP_N_MIN:-14}
resamplingPopulationNTarget = ${RESAMP_N_TARGET:-20}
resamplingPopulationNMax = ${RESAMP_N_MAX:-26}
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
  echo "$params_file"
}

case_tuple_0342a() {
  case "$1" in
    classic) echo "classic false off" ;;
    classic_resampling) echo "classic_resampling false on" ;;
    q6) echo "q6 true off" ;;
    q6_resampling) echo "q6_resampling true on" ;;
    *) echo "[0342a-injection-fill] unknown case '$1'. Expected classic, classic_resampling, q6, q6_resampling" >&2; return 2 ;;
  esac
}

run_case() {
  local label=$1 projection=$2 resampling=$3
  local params_file out_dir log_file time_file env_file
  params_file=$(write_params "$label" "$projection" "$resampling")
  out_dir="$RUN_ROOT/$label"
  log_file="$RUN_ROOT/logs/${label}_0342a_livevis.log"
  time_file="$RUN_ROOT/logs/${label}_0342a_livevis.time"
  env_file="$RUN_ROOT/logs/environment_${label}_0342a.env"

  cuda_env_for_case_0342a "$projection" "$resampling"
  livevis_prepare_control_0342a "$out_dir"
  livevis_env_0342a "$resampling"
  write_env_file_0342a "$env_file" "$label" "$projection" "$resampling"

  echo "[0139-0342a] Running $label (projection=$projection, resampling=$resampling)"
  echo "[0139-0342a] binary : $BIN"
  echo "[0139-0342a] params : $params_file"
  echo "[0139-0342a] output : $out_dir"
  local rc=0
  if portable_bool_true_0342 "$LIVE_PROGRESS"; then
    MPCD_ENABLE_INCREMENTAL_RESAMPLING_POOL="$MPCD_ENABLE_INCREMENTAL_RESAMPLING_POOL" \
    /usr/bin/time -f 'elapsed=%e user=%U sys=%S' "$BIN" "$params_file" 2> "$time_file" | tee "$log_file" || rc=$?
  else
    MPCD_ENABLE_INCREMENTAL_RESAMPLING_POOL="$MPCD_ENABLE_INCREMENTAL_RESAMPLING_POOL" \
    /usr/bin/time -f 'elapsed=%e user=%U sys=%S' "$BIN" "$params_file" > "$log_file" 2> "$time_file" || rc=$?
  fi
  cat "$time_file"
  if [[ "$rc" != "0" ]]; then
    echo "[0139-0342a] ERROR: $label failed rc=$rc" >&2
    tail -80 "$log_file" >&2 || true
    tail -80 "$time_file" >&2 || true
    return "$rc"
  fi
}

for case_name in $RUN_CASES; do
  read -r label projection resampling <<< "$(case_tuple_0342a "$case_name")"
  run_case "$label" "$projection" "$resampling"
done

cat <<MSG
[0139-0342a] Injection/fill CUDA-VIZ validation completed.
Run root: $RUN_ROOT

Runtime livevis control files are under each case directory by default, e.g.:
  $RUN_ROOT/classic/$LIVE_VIS_CONTROL_BASENAME

Example live edit while a run is active:
  cat > $RUN_ROOT/classic/$LIVE_VIS_CONTROL_BASENAME <<'EOF_CONTROL'
field = speed
colormap = thermal
clip = 0.5
gain = 2.0
smoothPasses = 2
EOF_CONTROL

MATLAB post-processing command from the repository root:
  cd matlab
  analyze_injection_fill_resampling_0139('../$RUN_ROOT');
MSG
