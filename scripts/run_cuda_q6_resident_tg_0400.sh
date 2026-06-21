#!/usr/bin/env bash
set -euo pipefail

# 0400 -- TG validation harness for the CUDA-resident Q6 elliptic prototype.
# Default run isolates Q6 from weighted-resampling discreteness. Set
# RESAMPLING_ENABLE=true for the coupled Q6+resampling sensitivity check.
# For full SRC->Q6 residency use scripts/run_cuda_q6_resident_src_step_tg_0401.sh.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BIN=${BIN:-build/src_mpcd_base_cuda_q6_resident_0400}
if [[ ! -x "$BIN" ]]; then
  bash scripts/build_src_mpcd_cuda_q6_resident_0400.sh
fi

NX=${NX:-64}
NY=${NY:-64}
GAMMA=${GAMMA:-20}
STEPS=${STEPS:-100}
SUMMARY_EVERY=${SUMMARY_EVERY:-$STEPS}
THREADS=${THREADS:-8}
RESAMPLING_ENABLE=${RESAMPLING_ENABLE:-false}
RUN_ROOT_CPU=${RUN_ROOT_CPU:-runs/q6_resident_0400_tg_cpu_${NX}x${NY}_${STEPS}}
RUN_ROOT_CUDA=${RUN_ROOT_CUDA:-runs/q6_resident_0400_tg_cuda_${NX}x${NY}_${STEPS}}
ART_DIR=${ART_DIR:-dev_history/artifacts/q6_resident_0400_${NX}x${NY}_${STEPS}}

env BIN="$BIN" BUILD_IF_MISSING=0 \
    NX="$NX" NY="$NY" GAMMA="$GAMMA" STEPS="$STEPS" SUMMARY_EVERY="$SUMMARY_EVERY" \
    THREADS="$THREADS" CHECK_UNSUPPORTED=0 CUDA_Q6_MIN_ITERATIONS=1 CUDA_Q6_DIV_AFTER_MAX=${CUDA_Q6_DIV_AFTER_MAX:-1e-8} \
    RUN_ROOT_CPU="$RUN_ROOT_CPU" RUN_ROOT_CUDA="$RUN_ROOT_CUDA" ART_DIR="$ART_DIR" \
    MPCD_CUDA_Q6_RESIDENT_0400=1 \
    MPCD_CUDA_Q6_RESIDENT_THERMOSTAT_0400=${MPCD_CUDA_Q6_RESIDENT_THERMOSTAT_0400:-1} \
    RESAMPLING_ENABLE="$RESAMPLING_ENABLE" \
    bash scripts/run_cuda_q6_tg_regression_0189.sh
