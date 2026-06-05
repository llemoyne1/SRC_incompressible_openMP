#!/usr/bin/env bash
set -euo pipefail

# 0240 active-path smoke launcher.
# It enables the 0240 hook and delegates to the best available 0239 persistent
# state-op validator.  Use bash explicitly instead of requiring executable bits,
# because files exchanged through archives may lose chmod +x.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

export MPCD_CUDA_RESAMPLING_PERSISTENT_0240=${MPCD_CUDA_RESAMPLING_PERSISTENT_0240:-1}
export MPCD_CUDA_RESAMPLING_PERSISTENT_0240_MIN_PARTICLES=${MPCD_CUDA_RESAMPLING_PERSISTENT_0240_MIN_PARTICLES:-0}

run_if_present() {
  local script="$1"
  shift || true
  if [[ -f "$script" ]]; then
    echo "[0240] running $script"
    bash "$script" "$@"
    return 0
  fi
  return 1
}

# Build the ordinary src_mpcd_base binary if a matching build script is present.
# Do not require executable permission: invoke with bash.
if [[ -f scripts/build_src_mpcd_base_cuda_0240.sh ]]; then
  bash scripts/build_src_mpcd_base_cuda_0240.sh
elif [[ -f scripts/build_src_mpcd_base_cuda.sh ]]; then
  bash scripts/build_src_mpcd_base_cuda.sh
elif [[ -f scripts/build_src_mpcd_base.sh ]]; then
  bash scripts/build_src_mpcd_base.sh
fi

# The actual validated 0239 launcher in the current SRC_GPU snapshot is named
# run_cuda_resampling_persistent_state_ops_smoke_0239.sh.  Keep the older aliases
# as fallbacks for local trees that used a slightly different name.
if run_if_present scripts/run_cuda_resampling_persistent_state_ops_smoke_0239.sh; then
  exit 0
elif run_if_present scripts/run_cuda_resampling_persistent_state_ops_0239.sh; then
  exit 0
elif run_if_present scripts/run_cuda_resampling_ops_0239.sh; then
  exit 0
else
  cat <<'MSG'
[0240] No 0239 CUDA resampling validation launcher was found.
[0240] The active-path hook has been enabled through:
       MPCD_CUDA_RESAMPLING_PERSISTENT_0240=1
[0240] Expected one of:
       scripts/run_cuda_resampling_persistent_state_ops_smoke_0239.sh
       scripts/run_cuda_resampling_persistent_state_ops_0239.sh
       scripts/run_cuda_resampling_ops_0239.sh
[0240] Connect the real 0239 backend in src/cuda_resampling_persistent_active_path_0240.cpp
       or run your local CUDA resampling smoke/validation script manually.
MSG
fi
