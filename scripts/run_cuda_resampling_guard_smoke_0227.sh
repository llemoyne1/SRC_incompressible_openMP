#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-$(pwd)}"
ART="$ROOT/dev_history/artifacts/gpu_cuda_resampling_0227"
mkdir -p "$ART"
bash "$ROOT/scripts/build_cuda_resampling_guard_0227.sh"
OUT_CSV="$ART/cuda_resampling_guard_smoke_0227.csv" \
GRID_CASES="${GRID_CASES:-64:64:20 128:128:20}" \
  "$ROOT/build/validate_cuda_resampling_guard_0227" | tee "$ART/cuda_resampling_guard_smoke_0227.log"
