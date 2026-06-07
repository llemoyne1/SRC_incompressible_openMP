#!/usr/bin/env bash
set -euo pipefail

# 0280 — CUDA/OpenMP build alias for segmented inlet/outlet fused thermostat validation.
# No CUDA kernel is changed in 0280. The compiled feature set is inherited from
# the already validated 0276-0279 thermostat-aware CUDA backend.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

OUT=${OUT:-build/src_mpcd_base_cuda_0280}

if [[ -x scripts/build_src_mpcd_cuda_0279.sh || -f scripts/build_src_mpcd_cuda_0279.sh ]]; then
  OUT="$OUT" CUDA_ARCH_FLAGS=${CUDA_ARCH_FLAGS:-} bash scripts/build_src_mpcd_cuda_0279.sh
elif [[ -x scripts/build_src_mpcd_cuda_0278.sh || -f scripts/build_src_mpcd_cuda_0278.sh ]]; then
  OUT="$OUT" CUDA_ARCH_FLAGS=${CUDA_ARCH_FLAGS:-} bash scripts/build_src_mpcd_cuda_0278.sh
else
  echo "[0280-cuda-build] ERROR: expected scripts/build_src_mpcd_cuda_0279.sh or 0278 fallback" >&2
  exit 2
fi

echo "[0280-cuda-build] Built $OUT"
