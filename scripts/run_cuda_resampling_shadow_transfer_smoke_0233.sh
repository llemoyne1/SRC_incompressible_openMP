#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-$(pwd)}"
ART="$ROOT/dev_history/artifacts/gpu_cuda_resampling_0233"
mkdir -p "$ART"
bash "$ROOT/scripts/build_cuda_resampling_shadow_transfer_0233.sh"
OUT_CSV="$ART/cuda_resampling_shadow_transfer_smoke_0233.csv" \
GRID_CASES="${GRID_CASES:-64:64:20 128:128:20}" \
"$ROOT/build/validate_cuda_resampling_shadow_transfer_0233" | tee "$ART/cuda_resampling_shadow_transfer_smoke_0233.log"
echo "[0233-resampling-shadow-transfer] csv: $ART/cuda_resampling_shadow_transfer_smoke_0233.csv"
