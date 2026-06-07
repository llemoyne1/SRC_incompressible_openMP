#!/usr/bin/env bash
set -euo pipefail

# 0281 — build alias for consolidated CUDA thermostat validation.
# Expected base: SRC_GPU after 0280c. 0281 adds no CUDA source change; it
# reuses the latest source state, including the 0276 real-particle thermostat
# moment reconstruction and the 0280c resident inlet/outlet thermostat guards.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

OUT=${OUT:-build/src_mpcd_base_cuda_0281}

if [[ -x scripts/build_src_mpcd_cuda_0280c.sh || -f scripts/build_src_mpcd_cuda_0280c.sh ]]; then
  OUT="$OUT" CUDA_ARCH_FLAGS=${CUDA_ARCH_FLAGS:-} bash scripts/build_src_mpcd_cuda_0280c.sh
elif [[ -x scripts/build_src_mpcd_cuda_0279.sh || -f scripts/build_src_mpcd_cuda_0279.sh ]]; then
  echo "[0281-cuda-build] WARNING: 0280c build script not found; falling back to 0279 build. Make sure 0280c source changes are already applied." >&2
  OUT="$OUT" CUDA_ARCH_FLAGS=${CUDA_ARCH_FLAGS:-} bash scripts/build_src_mpcd_cuda_0279.sh
else
  echo "[0281-cuda-build] ERROR: expected scripts/build_src_mpcd_cuda_0280c.sh or 0279 fallback" >&2
  exit 2
fi

echo "[0281-cuda-build] Built $OUT"
