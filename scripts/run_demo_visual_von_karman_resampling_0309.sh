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

# This wrapper intentionally uses the dedicated 0303 VK script, not the user's
# locally edited 0285 demo.
CASE_NAME="von_karman_circle_io_visual_0309"
BASE_RUN_ROOT="${BASE_RUN_ROOT:-runs/visual_src_resampling_cuda_von_karman_0309}"

# Defaults chosen for visualization; override freely from the shell.
export NX="${NX:-196}"
export NY="${NY:-64}"
export STEPS="${STEPS:-12000}"
export DT="${DT:-0.0005}"
export UIN="${UIN:-0.45}"
export GAMMA="${GAMMA:-20}"
export KBT="${KBT:-0.001}"
export SUMMARY_EVERY="${SUMMARY_EVERY:-100}"
export DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-100}"
export THREADS="${THREADS:-8}"
export INACTIVE_SLOTS="${INACTIVE_SLOTS:-250000}"
export GUARD_EVERY="${GUARD_EVERY:-5}"
export VK_THERMOSTAT_ENABLE="${VK_THERMOSTAT_ENABLE:-1}"
export THERMOSTAT_ENABLE="${THERMOSTAT_ENABLE:-$VK_THERMOSTAT_ENABLE}"

run_one_0309() {
  local mode="$1"
  local root="$2"
  local resampling_enable="$3"
  echo "[0309-vk] $mode -> $root"
  RESAMPLING_ENABLE="$resampling_enable" \
  RUN_ROOT="$root" \
  bash scripts/run_demo_src_resampling_cuda_von_karman_cylinder_0303.sh
}

mkdir -p "$BASE_RUN_ROOT"
if [[ "${VIS_MODES:-classic resampling}" == *classic* ]]; then
  run_one_0309 classic "$BASE_RUN_ROOT/classic" 0
fi
if [[ "${VIS_MODES:-classic resampling}" == *resampling* ]]; then
  run_one_0309 resampling "$BASE_RUN_ROOT/resampling_split_safe" 1
fi

cat > "$BASE_RUN_ROOT/visualize_von_karman_0309.m" <<'MATLAB'
% Example visualization commands for Von Karman 0309.
root = 'runs/visual_src_resampling_cuda_von_karman_0309';
classic = fullfile(root, 'classic', 'output');
resamp  = fullfile(root, 'resampling_split_safe', 'output');

figure;
play_smpcd_dumps(classic, 'field', 'speed', 'frameStride', 5, ...
    'showParticles', true, 'particleRoleFilter', 'fluid', ...
    'particleColorMode', 'speedlog', 'particleSpeedMin', 1.0, ...
    'particleLabelMode', 'mass_speed', 'particleLabelMax', 30, ...
    'particleMarkerSize', 12, 'pauseTime', 0.02);

figure;
play_smpcd_dumps(resamp, 'field', 'speed', 'frameStride', 5, ...
    'showParticles', true, 'particleRoleFilter', 'fluid', ...
    'particleColorMode', 'masslog', 'particleMassMax', 0.5, ...
    'particleSpeedMin', 1.0, 'particleThresholdLogic', 'or', ...
    'particleLabelMode', 'mass_speed', 'particleLabelMax', 30, ...
    'particleMarkerSize', 14, 'pauseTime', 0.02);
MATLAB

echo "[0309-vk] done. MATLAB helper: $BASE_RUN_ROOT/visualize_von_karman_0309.m"
