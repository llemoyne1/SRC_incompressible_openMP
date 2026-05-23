#!/usr/bin/env bash
set -euo pipefail

# Run the first backward-step/immersed-rectangle classic validation suite.
#
# This suite deliberately stays in classic compressible SRC/MPCD mode. Q6/Q9 are
# left disabled until the elliptic operator receives an internal solid mask.
#
# Required initial state, generated from matlab/:
#   generate_backward_step_state('output','../initial_state_backward_step_96x48_g20.smpcd');

BIN="${BIN:-./build/src_mpcd_base}"
RUN_SMOKE="${RUN_SMOKE:-1}"
RUN_LONG="${RUN_LONG:-1}"

if [[ ! -x "$BIN" ]]; then
  echo "Executable not found: $BIN" >&2
  echo "Build first, e.g.: ./scripts/build_src_mpcd_base.sh" >&2
  exit 1
fi

if [[ ! -f initial_state_backward_step_96x48_g20.smpcd ]]; then
  echo "Missing initial_state_backward_step_96x48_g20.smpcd" >&2
  echo "From matlab/: addpath('.'); generate_backward_step_state('output','../initial_state_backward_step_96x48_g20.smpcd');" >&2
  exit 1
fi

run_case() {
  local params="$1"
  echo
  echo "=== running $params ==="
  "$BIN" "$params"
}

if [[ "$RUN_SMOKE" != "0" ]]; then
  run_case examples/params_backward_step_classic_smoke_96x48.kv
fi

if [[ "$RUN_LONG" != "0" ]]; then
  run_case examples/params_backward_step_classic_long_96x48.kv
fi

echo
echo "Backward-step classic validation runs finished."
echo "From matlab/:"
echo "  addpath('.');"
echo "  smoke = validate_backward_step_smoke('../runs/backward_step_classic_smoke_96x48');"
echo "  long  = validate_backward_step_classic_long('../runs/backward_step_classic_long_96x48');"
