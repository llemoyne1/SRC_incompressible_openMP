#!/usr/bin/env bash
set -euo pipefail

# 0273 — performance pass for collision wrapper/per-step overhead in the validated CUDA resident classic SRC stack.
# This runner keeps the 0265c validation structure and profiles the 0273
# role-count/launch-check/setup-sync reductions.
# It does not enable Q6/resampling/virial/thermostat in the classic-only cases;
# that remains a validation choice, not an architectural lock.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BIN=${BIN:-build/src_mpcd_base_cuda_0273}
ART_DIR=${ART_DIR:-dev_history/artifacts/gpu_cuda_classic_src_resident_perf_0273}
OUT_CSV=${OUT_CSV:-$ART_DIR/cuda_classic_src_resident_perf_validation_0273.csv}
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
  echo "[0273-perf] rebuilding $BIN"
  OUT="$BIN" CUDA_ARCH_FLAGS=${CUDA_ARCH_FLAGS:-} bash scripts/build_src_mpcd_cuda_0273.sh
elif [[ ! -x "$BIN" ]]; then
  OUT="$BIN" CUDA_ARCH_FLAGS=${CUDA_ARCH_FLAGS:-} bash scripts/build_src_mpcd_cuda_0273.sh
fi

export MPCD_INTERNAL_PROFILES=1
export MPCD_CUDA_RESIDENT_PROFILE_0266=1
export MPCD_CUDA_RESIDENT_PROFILE_0271=1
export MPCD_CUDA_RESIDENT_PROFILE_0273=1
# Keep 0271 fixed-overhead optimizations active; 0273 adds collision-specific reductions.
export MPCD_CUDA_CLASSIC_SRC_RESIDENT_0271_ASYNC_STREAM=${MPCD_CUDA_CLASSIC_SRC_RESIDENT_0271_ASYNC_STREAM:-1}
export MPCD_CUDA_CLASSIC_SRC_WALL_RESIDENT_0271_FAST_DIAGNOSTICS=${MPCD_CUDA_CLASSIC_SRC_WALL_RESIDENT_0271_FAST_DIAGNOSTICS:-1}
export MPCD_CUDA_PERSISTENT_SRC_COLLISION_DEVICE_ROTATION_0272=${MPCD_CUDA_PERSISTENT_SRC_COLLISION_DEVICE_ROTATION_0272:-1}
export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_WORKSPACE_DOWNLOAD_0272=${MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_WORKSPACE_DOWNLOAD_0272:-1}
export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_FINAL_SYNC_0272=${MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_FINAL_SYNC_0272:-1}
export MPCD_CUDA_PERSISTENT_SRC_COLLISION_LAZY_KERNEL_CHECK_0273=${MPCD_CUDA_PERSISTENT_SRC_COLLISION_LAZY_KERNEL_CHECK_0273:-1}
export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_SETUP_SYNC_0273=${MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_SETUP_SYNC_0273:-1}
# Leave the 0273 explicit-gamma host role-count fast path enabled by default.
# Set MPCD_CUDA_PERSISTENT_SRC_COLLISION_DISABLE_EXPLICIT_GAMMA_ROLE_FASTPATH_0273=1
# to restore the pre-0273 host scan when debugging.

# Keep child validation CSV parsing from 0265c, but place all artifacts under the
# 0273 performance root and use the 0273 binary.
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

python3 scripts/summarize_cuda_resident_perf_0273.py "$ART_DIR/validation_runs" \
  --summary-out "$ART_DIR/cuda_classic_src_resident_perf_summary_0273.csv" \
  --phases-out "$ART_DIR/cuda_classic_src_resident_perf_phases_0273.csv"

echo "[0273-perf] validation manifest: $OUT_CSV"
echo "[0273-perf] performance summary: $ART_DIR/cuda_classic_src_resident_perf_summary_0273.csv"
echo "[0273-perf] detailed phases: $ART_DIR/cuda_classic_src_resident_perf_phases_0273.csv"
echo "[0273-perf] Q6/resampling remain disabled only in these classic-only validators; reactivation paths are intentionally preserved."
echo "[0273-perf] CUDA thermostat wall/solid/piston/IO-aware remains a separate future chantier."
