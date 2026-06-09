#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BIN="${BIN:-build/src_mpcd_base_cuda_0308}"
FORCE_REBUILD="${FORCE_REBUILD:-0}"

if [[ "$FORCE_REBUILD" != "0" && "$FORCE_REBUILD" != "false" && "$FORCE_REBUILD" != "FALSE" ]]; then
  OUT="$BIN" CUDA_ARCH_FLAGS="${CUDA_ARCH_FLAGS:-}" bash scripts/build_src_mpcd_cuda_0308.sh
elif [[ ! -x "$BIN" ]]; then
  OUT="$BIN" CUDA_ARCH_FLAGS="${CUDA_ARCH_FLAGS:-}" bash scripts/build_src_mpcd_cuda_0308.sh
fi

# Nominal split-safe post-SRC CUDA resampling mode, consolidated in 0308.
export MPCD_CUDA_RESAMPLING_SPLIT_SAFETY_0307="${MPCD_CUDA_RESAMPLING_SPLIT_SAFETY_0307:-1}"
export MPCD_CUDA_RESAMPLING_SPLIT_PREFER_MAX_MASS_DONOR_0307="${MPCD_CUDA_RESAMPLING_SPLIT_PREFER_MAX_MASS_DONOR_0307:-1}"
export MPCD_CUDA_RESAMPLING_SPLIT_DONOR_MIN_MASS_0307="${MPCD_CUDA_RESAMPLING_SPLIT_DONOR_MIN_MASS_0307:-0.5}"
export MPCD_CUDA_RESAMPLING_SPLIT_NEW_PARTICLE_MIN_MASS_0307="${MPCD_CUDA_RESAMPLING_SPLIT_NEW_PARTICLE_MIN_MASS_0307:-0.25}"
export MPCD_CUDA_RESAMPLING_SOLID_ADJACENT_SPLIT_MODE_0307="${MPCD_CUDA_RESAMPLING_SOLID_ADJACENT_SPLIT_MODE_0307:-0}"

# Keep the support/outlier diagnostics lightweight but available for visual runs.
export MPCD_CUDA_RESAMPLING_ADAPTIVE_FLAG_0304="${MPCD_CUDA_RESAMPLING_ADAPTIVE_FLAG_0304:-1}"
export MPCD_CUDA_RESAMPLING_ADAPTIVE_FLAG_0304_EVERY="${MPCD_CUDA_RESAMPLING_ADAPTIVE_FLAG_0304_EVERY:-50}"
export MPCD_CUDA_RESAMPLING_ADAPTIVE_FLAG_0304_TRIGGER_NMIN="${MPCD_CUDA_RESAMPLING_ADAPTIVE_FLAG_0304_TRIGGER_NMIN:-6}"
export MPCD_CUDA_RESAMPLING_ADAPTIVE_FLAG_0304_TRIGGER_EMPTY="${MPCD_CUDA_RESAMPLING_ADAPTIVE_FLAG_0304_TRIGGER_EMPTY:-1}"
export MPCD_CUDA_RESAMPLING_GEOMETRY_DIAG_0305_HIGH_U="${MPCD_CUDA_RESAMPLING_GEOMETRY_DIAG_0305_HIGH_U:-1.0}"
export MPCD_CUDA_RESAMPLING_OUTLIER_0306_U_THRESHOLD="${MPCD_CUDA_RESAMPLING_OUTLIER_0306_U_THRESHOLD:-1.0}"

# 0314: visual runs usually do not need restart-compatible dumps containing a
# huge Inactive reservoir.  Write and summarize only Fluid particles by default;
# override with DUMP_ROLE_FILTER=all SUMMARY_ROLE_FILTER=all for restart dumps.
export DUMP_ROLE_FILTER="${DUMP_ROLE_FILTER:-fluid}"
export SUMMARY_ROLE_FILTER="${SUMMARY_ROLE_FILTER:-fluid}"

run_modes_0309() {
  local script="$1"
  local base_root="$2"
  local mode_label
  local modes="${VIS_MODES:-classic resampling}"

  mkdir -p "$base_root"
  for mode_label in $modes; do
    case "$mode_label" in
      classic|off|0)
        echo "[0309-visual] running classic: $script"
        RESAMPLING_ENABLE=0 RUN_ROOT="$base_root/classic" bash "$script"
        ;;
      resampling|on|1)
        echo "[0309-visual] running resampling split-safe: $script"
        RESAMPLING_ENABLE=1 RUN_ROOT="$base_root/resampling_split_safe" bash "$script"
        ;;
      *)
        echo "[0309-visual] unknown mode in VIS_MODES: $mode_label" >&2
        exit 2
        ;;
    esac
  done
}

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/src_gpu_demo_common_0283.sh"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/src_gpu_resampling_demo_common_0303.sh"

CASE_NAME="backward_step_io_visual_0309"
Lx="${Lx:-3.0}"; Ly="${Ly:-1.0}"; NX="${NX:-128}"; NY="${NY:-48}"
GAMMA="${GAMMA:-20}"; STEPS="${STEPS:-6000}"; DT="${DT:-0.0008}"; KBT="${KBT:-0.001}"
SEED="${SEED:-1629302}"; SUMMARY_EVERY="${SUMMARY_EVERY:-100}"; DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-100}"
THREADS="${THREADS:-8}"
UIN="${UIN:-0.60}"
STEP_XMIN="${STEP_XMIN:-0.0}"; STEP_XMAX="${STEP_XMAX:-0.5}"; STEP_YMIN="${STEP_YMIN:-0.0}"; STEP_YMAX="${STEP_YMAX:-0.42}"
INACTIVE_SLOTS="${INACTIVE_SLOTS:-120000}"
BASE_RUN_ROOT="${BASE_RUN_ROOT:-runs/visual_src_resampling_cuda_backward_step_0309}"

run_one_0309() {
  local mode="$1"
  local root="$2"
  local resampling_enable="$3"

  export RESAMPLING_ENABLE="$resampling_enable"
  RUN_ROOT="$root"
  prepare_demo_dirs_0283 "$RUN_ROOT"

  STATE_FILE="$RUN_ROOT/init/${CASE_NAME}_${NX}x${NY}_g${GAMMA}.smpcd"
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
  if [[ "$RESAMPLING_ENABLE" != "0" ]]; then
    src_gpu_resampling_env_0303
  fi
  run_demo_case_0283 "$PARAMS_FILE" "$LOG_FILE" "$TIME_FILE" "$OUT_DIR"
}

mkdir -p "$BASE_RUN_ROOT"
if [[ "${VIS_MODES:-classic resampling}" == *classic* ]]; then
  echo "[0309-step] classic -> $BASE_RUN_ROOT/classic"
  run_one_0309 classic "$BASE_RUN_ROOT/classic" 0
fi
if [[ "${VIS_MODES:-classic resampling}" == *resampling* ]]; then
  echo "[0309-step] resampling split-safe -> $BASE_RUN_ROOT/resampling_split_safe"
  run_one_0309 resampling "$BASE_RUN_ROOT/resampling_split_safe" 1
fi

cat > "$BASE_RUN_ROOT/visualize_backward_step_0309.m" <<'MATLAB'
% Example visualization commands for backward step 0309.
root = 'runs/visual_src_resampling_cuda_backward_step_0309';
classic = fullfile(root, 'classic', 'output');
resamp  = fullfile(root, 'resampling_split_safe', 'output');

figure;
play_smpcd_dumps(classic, 'field', 'N', 'frameStride', 5, ...
    'showParticles', true, 'particleRoleFilter', 'fluid', ...
    'particleColorMode', 'role', 'particleMarkerSize', 5, ...
    'pauseTime', 0.02);

figure;
play_smpcd_dumps(resamp, 'field', 'speed', 'frameStride', 5, ...
    'showParticles', true, 'particleRoleFilter', 'fluid', ...
    'particleColorMode', 'masslog', 'particleMassMax', 0.5, ...
    'particleSpeedMin', 1.0, 'particleThresholdLogic', 'or', ...
    'particleLabelMode', 'mass_speed', 'particleLabelMax', 30, ...
    'particleMarkerSize', 14, 'pauseTime', 0.02);
MATLAB

echo "[0309-step] done. MATLAB helper: $BASE_RUN_ROOT/visualize_backward_step_0309.m"
