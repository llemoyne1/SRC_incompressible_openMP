#!/usr/bin/env bash
set -euo pipefail

# Run the dynamic liquid-closure validation suite:
#   - Taylor--Green: classic / Q6 / filtered Q9 / filtered Q9 + virial
#   - Poiseuille channel: classic / Q6 / filtered Q9 / filtered Q9 + virial
#
# Required initial states, generated from matlab/:
#   generate_taylor_green_high_snr_short_state();
#   generate_poiseuille_q6_channel_short_state();

BIN="${BIN:-./build/src_mpcd_base}"

if [[ ! -x "$BIN" ]]; then
  echo "Executable not found: $BIN" >&2
  echo "Build first, e.g.: ./scripts/build_src_mpcd_base.sh" >&2
  exit 1
fi

if [[ ! -f initial_state_tg_64x64_g80_u0p08_kbt0p01.smpcd ]]; then
  echo "Missing initial_state_tg_64x64_g80_u0p08_kbt0p01.smpcd" >&2
  echo "From matlab/: addpath('.'); generate_taylor_green_high_snr_short_state();" >&2
  exit 1
fi

if [[ ! -f initial_state_poiseuille_32x32_g40_kbt0p01.smpcd ]]; then
  echo "Missing initial_state_poiseuille_32x32_g40_kbt0p01.smpcd" >&2
  echo "From matlab/: addpath('.'); generate_poiseuille_q6_channel_short_state();" >&2
  exit 1
fi

run_case() {
  local params="$1"
  echo
  echo "=== running $params ==="
  "$BIN" "$params"
}

run_case examples/params_taylor_green_high_snr_classic_64x64_g80_short.kv
run_case examples/params_taylor_green_high_snr_q6_64x64_g80_short.kv
run_case examples/params_taylor_green_high_snr_q9_filtered_64x64_g80_short.kv
run_case examples/params_taylor_green_high_snr_q9_virial_K0p500_beta0p20_64x64_g80_short.kv

run_case examples/params_poiseuille_y_classic_solid_thermal_long.kv
run_case examples/params_poiseuille_y_q6_solid_thermal_long.kv
run_case examples/params_poiseuille_y_q9_filtered_solid_thermal_long.kv
run_case examples/params_poiseuille_y_q9_virial_K0p500_beta0p20_solid_thermal_long.kv

echo
echo "All dynamic liquid-closure runs finished."
echo "From matlab/: addpath('.'); out = validate_liquid_closure_dynamic_suite('makePlots', true);"
