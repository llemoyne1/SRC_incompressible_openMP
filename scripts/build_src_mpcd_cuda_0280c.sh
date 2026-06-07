#!/usr/bin/env bash
set -euo pipefail

# 0280c — CUDA/OpenMP build alias for resident inlet/outlet + fused SRC thermostat validation.
# Source change is in cuda_classic_src_io_resident_0263.cu; compile with the same CUDA feature set as 0279.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

OUT=${OUT:-build/src_mpcd_base_cuda_0280c}

if [[ -x scripts/build_src_mpcd_cuda_0279.sh || -f scripts/build_src_mpcd_cuda_0279.sh ]]; then
  OUT="$OUT" CUDA_ARCH_FLAGS=${CUDA_ARCH_FLAGS:-} bash scripts/build_src_mpcd_cuda_0279.sh
elif [[ -x scripts/build_src_mpcd_cuda_0278.sh || -f scripts/build_src_mpcd_cuda_0278.sh ]]; then
  OUT="$OUT" CUDA_ARCH_FLAGS=${CUDA_ARCH_FLAGS:-} bash scripts/build_src_mpcd_cuda_0278.sh
else
  echo "[0280c-cuda-build] ERROR: expected scripts/build_src_mpcd_cuda_0279.sh or 0278 fallback" >&2
  exit 2
fi

echo "[0280c-cuda-build] Built $OUT"
