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

RUN_POISEUILLE="${RUN_POISEUILLE:-1}"
RUN_STEP="${RUN_STEP:-1}"
RUN_VK="${RUN_VK:-1}"

if [[ "$RUN_POISEUILLE" != "0" ]]; then
  bash scripts/run_demo_visual_poiseuille_resampling_0309.sh
fi
if [[ "$RUN_STEP" != "0" ]]; then
  bash scripts/run_demo_visual_backward_step_resampling_0309.sh
fi
if [[ "$RUN_VK" != "0" ]]; then
  bash scripts/run_demo_visual_von_karman_resampling_0309.sh
fi
