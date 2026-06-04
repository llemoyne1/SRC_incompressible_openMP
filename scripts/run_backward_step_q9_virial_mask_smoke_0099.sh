#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [[ ! -x build/src_mpcd_base ]]; then
  ./scripts/build_src_mpcd_base.sh
fi

STATE="initial_state_backward_step_96x48_g20.smpcd"
if [[ ! -f "$STATE" ]]; then
  if command -v matlab >/dev/null 2>&1; then
    matlab -batch "cd('matlab'); generate_backward_step_state('output','../${STATE}');"
  else
    echo "Missing ${STATE}. Generate it from MATLAB:" >&2
    echo "  cd matlab" >&2
    echo "  generate_backward_step_state('output','../${STATE}');" >&2
    echo "  cd .." >&2
    exit 1
  fi
fi

echo "[backward-step-q9-virial-mask-0099] running 100-step Q9+virial smoke"
./build/src_mpcd_base examples/params_backward_step_q9_virial_mask_smoke_96x48.kv

echo "[backward-step-q9-virial-mask-0099] done"
