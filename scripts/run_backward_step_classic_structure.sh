#!/usr/bin/env bash
set -euo pipefail

# Run the high-signal periodic-x backward-step visualization case.
# This is a classic-compressible SRC/MPCD case; Q6/Q9 remain disabled.

BIN="${BIN:-./build/src_mpcd_base}"
PARAMS="${PARAMS:-examples/params_backward_step_classic_structure_96x48.kv}"

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

echo "=== running $PARAMS ==="
"$BIN" "$PARAMS"

echo
echo "Finished. From matlab/:"
echo "  addpath('.');"
echo "  out = validate_backward_step_classic_long('../runs/backward_step_classic_structure_96x48','field','omega');"
