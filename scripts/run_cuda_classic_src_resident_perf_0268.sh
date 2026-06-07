#!/usr/bin/env bash
set -euo pipefail

# 0268 — performance pass for the validated CUDA resident classic SRC stack.
# This runner keeps the 0265c validation structure and profiles the 0268
# full-face hard-cell reservoir allocator.
# It does not enable Q6/resampling/virial/thermostat in the classic-only cases;
# that remains a validation choice, not an architectural lock.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BIN=${BIN:-build/src_mpcd_base_cuda_0268}
ART_DIR=${ART_DIR:-dev_history/artifacts/gpu_cuda_classic_src_resident_perf_0268}
OUT_CSV=${OUT_CSV:-$ART_DIR/cuda_classic_src_resident_perf_validation_0268.csv}
THREADS=${THREADS:-8}
GAMMA=${GAMMA:-20}
FORCE_REBUILD=${FORCE_REBUILD:-1}
STOP_ON_FAIL=${STOP_ON_FAIL:-1}

# Short enough for iteration, but includes one 128x128 point where resident CUDA
# overheads start to become visible.  Override these from the shell for deeper
# profiling, e.g. PERF_GRID_CASES="64:64:300 128:128:240 256:128:120".
PERF_GRID_CASES=${PERF_GRID_CASES:-"64:64:220 128:128:140"}
PERF_PISTON_GRID_CASES=${PERF_PISTON_GRID_CASES:-"64:64:160"}
PERIODIC_GRID_CASES=${PERIODIC_GRID_CASES:-$PERF_GRID_CASES}
WALL_GRID_CASES=${WALL_GRID_CASES:-$PERF_GRID_CASES}
SOLID_GRID_CASES=${SOLID_GRID_CASES:-$PERF_GRID_CASES}
IO_FULLFACE_GRID_CASES=${IO_FULLFACE_GRID_CASES:-$PERF_GRID_CASES}
IO_SEGMENTED_GRID_CASES=${IO_SEGMENTED_GRID_CASES:-$PERF_GRID_CASES}
PISTON_GRID_CASES=${PISTON_GRID_CASES:-$PERF_PISTON_GRID_CASES}
SUMMARY_EVERY_MODE=${SUMMARY_EVERY_MODE:-final}

mkdir -p "$ART_DIR"

if [[ "$FORCE_REBUILD" != "0" && "$FORCE_REBUILD" != "false" && "$FORCE_REBUILD" != "FALSE" ]]; then
  echo "[0268-perf] rebuilding $BIN"
  OUT="$BIN" CUDA_ARCH_FLAGS=${CUDA_ARCH_FLAGS:-} bash scripts/build_src_mpcd_cuda_0268.sh
elif [[ ! -x "$BIN" ]]; then
  OUT="$BIN" CUDA_ARCH_FLAGS=${CUDA_ARCH_FLAGS:-} bash scripts/build_src_mpcd_cuda_0268.sh
fi

export MPCD_INTERNAL_PROFILES=1
export MPCD_CUDA_RESIDENT_PROFILE_0266=1
export MPCD_CUDA_RESIDENT_PROFILE_0268=1

# Keep child validation CSV parsing from 0265c, but place all artifacts under the
# 0268 performance root and use the 0268 binary.
BIN="$BIN" \
ART_DIR="$ART_DIR/validation_runs" \
OUT_CSV="$OUT_CSV" \
FORCE_REBUILD=0 \
THREADS="$THREADS" \
GAMMA="$GAMMA" \
STOP_ON_FAIL="$STOP_ON_FAIL" \
SUMMARY_EVERY_MODE="$SUMMARY_EVERY_MODE" \
PERIODIC_GRID_CASES="$PERIODIC_GRID_CASES" \
WALL_GRID_CASES="$WALL_GRID_CASES" \
SOLID_GRID_CASES="$SOLID_GRID_CASES" \
IO_FULLFACE_GRID_CASES="$IO_FULLFACE_GRID_CASES" \
IO_SEGMENTED_GRID_CASES="$IO_SEGMENTED_GRID_CASES" \
PISTON_GRID_CASES="$PISTON_GRID_CASES" \
bash scripts/run_cuda_classic_src_resident_consolidated_0265c.sh

python3 scripts/summarize_cuda_resident_perf_0268.py "$ART_DIR/validation_runs" \
  --summary-out "$ART_DIR/cuda_classic_src_resident_perf_summary_0268.csv" \
  --phases-out "$ART_DIR/cuda_classic_src_resident_perf_phases_0268.csv"

echo "[0268-perf] validation manifest: $OUT_CSV"
echo "[0268-perf] performance summary: $ART_DIR/cuda_classic_src_resident_perf_summary_0268.csv"
echo "[0268-perf] detailed phases: $ART_DIR/cuda_classic_src_resident_perf_phases_0268.csv"
echo "[0268-perf] Q6/resampling remain disabled only in these classic-only validators; reactivation paths are intentionally preserved."
echo "[0268-perf] CUDA thermostat wall/solid/piston/IO-aware remains a separate future chantier."
