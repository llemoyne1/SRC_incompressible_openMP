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

RUN_CLASSIC="${RUN_CLASSIC:-1}"
RUN_Q6="${RUN_Q6:-1}"
RUN_Q9="${RUN_Q9:-1}"
RUN_ANALYSIS="${RUN_ANALYSIS:-0}"

if [[ "$RUN_CLASSIC" != "0" ]]; then
  echo "[backward-step-structure] running classic structure"
  ./build/src_mpcd_base examples/params_backward_step_classic_structure_96x48.kv
fi

if [[ "$RUN_Q6" != "0" ]]; then
  echo "[backward-step-structure] running masked Q6 structure"
  ./build/src_mpcd_base examples/params_backward_step_q6_mask_structure_96x48.kv
fi

if [[ "$RUN_Q9" != "0" ]]; then
  echo "[backward-step-structure] running masked Q9 filtered structure"
  ./build/src_mpcd_base examples/params_backward_step_q9_mask_structure_96x48.kv
fi

if [[ "$RUN_ANALYSIS" != "0" ]]; then
  if command -v matlab >/dev/null 2>&1; then
    echo "[backward-step-structure] running MATLAB comparison"
    matlab -batch "cd('matlab'); validate_backward_step_masked_structure_suite('makePlots',false);"
  else
    echo "[backward-step-structure] MATLAB not found; skipping analysis" >&2
  fi
fi

echo "[backward-step-structure] done"
