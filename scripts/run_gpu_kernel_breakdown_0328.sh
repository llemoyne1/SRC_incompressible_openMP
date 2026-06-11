#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

ART_DIR=${ART_DIR:-dev_history/artifacts/gpu_kernel_breakdown_0328}
STEPS=${STEPS:-300}
REPEATS=${REPEATS:-1}
INACTIVE_SLOTS=${INACTIVE_SLOTS:-100000}
RUN_VKKH=${RUN_VKKH:-0}

# This harness is profiling-only.  It deliberately enables the 0324 CUDA-event
# microprofile and the 0328 append mode so that the CSV contains all profiled
# steps, not only the last solver step.
echo "[0328-kernel-breakdown] ART_DIR=$ART_DIR STEPS=$STEPS REPEATS=$REPEATS RUN_VKKH=$RUN_VKKH"
echo "[0328-kernel-breakdown] SRC_BUILD=${SRC_BUILD:-0} VKKH_BUILD=${VKKH_BUILD:-0}"

ART_DIR="$ART_DIR" CLEAN_ART_DIR=1 \
SRC_BUILD="${SRC_BUILD:-0}" VKKH_BUILD="${VKKH_BUILD:-0}" \
SRC_GPU_KERNEL_BREAKDOWN_0324=1 \
SRC_GPU_KERNEL_BREAKDOWN_APPEND_0328=1 \
WARMUP=0 STEPS="$STEPS" REPEATS="$REPEATS" INACTIVE_SLOTS="$INACTIVE_SLOTS" \
RUN_SRC_PERIODIC=1 RUN_SRC_IO=0 RUN_VKKH="$RUN_VKKH" \
bash scripts/run_gpu_phase_profile_0317d.sh

python3 scripts/summarize_gpu_kernel_breakdown_0328.py "$ART_DIR"
