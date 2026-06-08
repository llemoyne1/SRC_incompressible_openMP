#!/usr/bin/env bash
set -euo pipefail

# 0302 — documented nominal backward-step validation.
#
# This is a thin, isolated wrapper around the 0301 backward-step long runner. It
# launches only two modes:
#   1. classic SRC CUDA
#   2. active local CUDA population guard with the provisional nominal setting
#      Nmin:Ntarget:Nmax = 12:20:32
#
# It is intended for reproducibility and documentation, not for broad sweeps.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BIN=${BIN:-build/src_mpcd_base_cuda_0302}
ART_DIR=${ART_DIR:-dev_history/artifacts/gpu_cuda_resampling_backward_step_nominal_0302}
FORCE_REBUILD=${FORCE_REBUILD:-1}

NX=${NX:-96}
NY=${NY:-48}
STEPS=${STEPS:-3000}
UIN=${UIN:-0.60}
SUMMARY_EVERY=${SUMMARY_EVERY:-100}
DUMP_STATE_EVERY=${DUMP_STATE_EVERY:-1000}
GUARD_TRIPLE=${GUARD_TRIPLE:-12:20:32}
GUARD_EVERY=${GUARD_EVERY:-50}
THERMOSTAT_ENABLE=${THERMOSTAT_ENABLE:-1}

if [[ "$FORCE_REBUILD" != "0" && "$FORCE_REBUILD" != "false" && "$FORCE_REBUILD" != "FALSE" ]]; then
  echo "[0302-step-nominal] rebuilding $BIN"
  OUT="$BIN" CUDA_ARCH_FLAGS="${CUDA_ARCH_FLAGS:-}" bash scripts/build_src_mpcd_cuda_0302.sh
elif [[ ! -x "$BIN" ]]; then
  OUT="$BIN" CUDA_ARCH_FLAGS="${CUDA_ARCH_FLAGS:-}" bash scripts/build_src_mpcd_cuda_0302.sh
fi

if [[ ! -x "$BIN" ]]; then
  echo "[0302-step-nominal] ERROR: missing binary $BIN" >&2
  exit 127
fi

mkdir -p "$ART_DIR"

echo "[0302-step-nominal] UIN=$UIN NX=$NX NY=$NY STEPS=$STEPS GUARD_TRIPLE=$GUARD_TRIPLE"

BIN="$BIN" \
FORCE_REBUILD=0 \
ART_DIR="$ART_DIR" \
NX="$NX" \
NY="$NY" \
STEPS="$STEPS" \
UIN_GRID="$UIN" \
SUMMARY_EVERY="$SUMMARY_EVERY" \
DUMP_STATE_EVERY="$DUMP_STATE_EVERY" \
GUARD_GRID="$GUARD_TRIPLE" \
GUARD_EVERY="$GUARD_EVERY" \
THERMOSTAT_ENABLE="$THERMOSTAT_ENABLE" \
RUN_MASS_ONLY=0 \
GUARD_WITH_MASS_RECONDITION=0 \
RESTORE_ENABLE=1 \
BOUNDARY_AWARE=1 \
OPEN_BOUNDARY_HALO_CELLS=1 \
BOUNDARY_HALO_CELLS=0 \
SOLID_HALO_CELLS=0 \
bash scripts/run_cuda_resampling_backward_step_long_0301.sh

if [[ -f scripts/summarize_cuda_resampling_backward_step_0302.py ]]; then
  python3 scripts/summarize_cuda_resampling_backward_step_0302.py "$ART_DIR"
fi

echo "[0302-step-nominal] artifacts=$ART_DIR"
