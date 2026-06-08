#!/usr/bin/env bash
set -euo pipefail

# Build helper for the 0303 resampling demo scripts.  It delegates to the most
# recent CUDA build script available in the branch so the demo layer does not
# duplicate the build recipe.

OUT="${OUT:-build/src_mpcd_base_cuda_0303}"
CUDA_ARCH_FLAGS="${CUDA_ARCH_FLAGS:-}"

candidates=(
  scripts/build_src_mpcd_cuda_0302.sh
  scripts/build_src_mpcd_cuda_0301.sh
  scripts/build_src_mpcd_cuda_0300.sh
  scripts/build_src_mpcd_cuda_0299.sh
  scripts/build_src_mpcd_cuda_0298.sh
  scripts/build_src_mpcd_cuda_0297.sh
  scripts/build_src_mpcd_cuda_0296.sh
  scripts/build_src_mpcd_cuda_0295.sh
  scripts/build_src_mpcd_cuda_0294.sh
  scripts/build_src_mpcd_cuda_0293.sh
  scripts/build_src_mpcd_cuda_0291b.sh
)

for script in "${candidates[@]}"; do
  if [[ -x "$script" || -f "$script" ]]; then
    echo "[0303-build] OUT=$OUT"
    echo "[0303-build] delegate=$script"
    OUT="$OUT" CUDA_ARCH_FLAGS="$CUDA_ARCH_FLAGS" bash "$script"
    if [[ ! -x "$OUT" ]]; then
      echo "[0303-build] ERROR: delegated build did not create executable: $OUT" >&2
      exit 127
    fi
    echo "[0303-build] built $OUT"
    exit 0
  fi
done

echo "[0303-build] ERROR: no CUDA build script found" >&2
exit 127
