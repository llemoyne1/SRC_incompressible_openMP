#!/usr/bin/env bash
set -euo pipefail

# 0286 — final SRC classic CUDA demonstration suite.
# Runs the five user-facing demonstrations with frequent dumps for animation.
# The Von Karman cylinder script is the 0285 circular-solid + inlet/outlet CUDA path.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

run_one() {
  local script=$1
  echo "[0286-demo-all] =========================================="
  echo "[0286-demo-all] running $script"
  echo "[0286-demo-all] =========================================="
  bash "$script"
}

run_one scripts/run_demo_src_classic_cuda_taylor_green_forced_0283.sh
run_one scripts/run_demo_src_classic_cuda_poiseuille_periodic_forced_0283.sh
run_one scripts/run_demo_src_classic_cuda_box_same_face_io_0283.sh
run_one scripts/run_demo_src_classic_cuda_backward_step_io_0283.sh
run_one scripts/run_demo_src_classic_cuda_von_karman_cylinder_0285.sh
