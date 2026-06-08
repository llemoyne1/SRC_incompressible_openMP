#!/usr/bin/env bash
set -euo pipefail

# Convenience launcher: run the 0303 demo cases in classic+survey and
# resampling mode.  Individual scripts can also be run directly.

BIN="${BIN:-build/src_mpcd_base_cuda_0303}"
FORCE_REBUILD="${FORCE_REBUILD:-0}"
if [[ "$FORCE_REBUILD" == "1" || ! -x "$BIN" ]]; then
  OUT="$BIN" CUDA_ARCH_FLAGS="${CUDA_ARCH_FLAGS:-}" bash scripts/build_src_mpcd_cuda_resampling_demos_0303.sh
fi

RUN_TG="${RUN_TG:-1}"
RUN_POISEUILLE="${RUN_POISEUILLE:-1}"
RUN_STEP="${RUN_STEP:-1}"
RUN_SEGMENTED="${RUN_SEGMENTED:-1}"
RUN_VK="${RUN_VK:-1}"
RUN_CLASSIC="${RUN_CLASSIC:-1}"
RUN_RESAMPLING="${RUN_RESAMPLING:-1}"

run_case() {
  local script=$1
  if [[ "$RUN_CLASSIC" == "1" ]]; then
    echo "[0303-suite] classic+survey: $script"
    RESAMPLING_ENABLE=0 RESAMPLING_SURVEY_ENABLE="${RESAMPLING_SURVEY_ENABLE:-1}" BIN="$BIN" bash "$script"
  fi
  if [[ "$RUN_RESAMPLING" == "1" ]]; then
    echo "[0303-suite] resampling: $script"
    RESAMPLING_ENABLE=1 RESAMPLING_SURVEY_ENABLE="${RESAMPLING_SURVEY_ENABLE:-1}" BIN="$BIN" bash "$script"
  fi
}

[[ "$RUN_TG" == "1" ]] && run_case scripts/run_demo_src_classic_cuda_taylor_green_forced_0283.sh
[[ "$RUN_POISEUILLE" == "1" ]] && run_case scripts/run_demo_src_classic_cuda_poiseuille_periodic_forced_0283.sh
[[ "$RUN_STEP" == "1" ]] && run_case scripts/run_demo_src_classic_cuda_backward_step_io_0283.sh
[[ "$RUN_SEGMENTED" == "1" ]] && run_case scripts/run_demo_src_classic_cuda_box_same_face_io_0283.sh
[[ "$RUN_VK" == "1" ]] && run_case scripts/run_demo_src_resampling_cuda_von_karman_cylinder_0303.sh

echo "[0303-suite] done"
