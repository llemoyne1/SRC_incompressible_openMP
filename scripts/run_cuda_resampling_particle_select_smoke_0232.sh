#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-$(pwd)}"
ART="$ROOT/dev_history/artifacts/gpu_cuda_resampling_0232"
mkdir -p "$ART"
bash "$ROOT/scripts/build_cuda_resampling_particle_select_0232.sh"
OUT_CSV="$ART/cuda_resampling_particle_select_smoke_0232.csv" \
GRID_CASES="${GRID_CASES:-64:64:20 128:128:20}" \
"$ROOT/build/validate_cuda_resampling_particle_select_0232" | tee "$ART/cuda_resampling_particle_select_smoke_0232.log"
echo "[0232-resampling-particle-select] csv: $ART/cuda_resampling_particle_select_smoke_0232.csv"
