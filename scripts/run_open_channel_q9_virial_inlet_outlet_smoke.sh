#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
./scripts/build_src_mpcd_base.sh

if [[ ! -f initial_state_open_channel_64x32_g20_kbt0p01.smpcd ]]; then
  cat >&2 <<'MSG'
Missing initial_state_open_channel_64x32_g20_kbt0p01.smpcd
Generate it from MATLAB with:
  cd matlab
  generate_open_channel_classic_state('output','../initial_state_open_channel_64x32_g20_kbt0p01.smpcd');
  cd ..
MSG
  exit 2
fi

./build/src_mpcd_base examples/params_open_channel_q9_virial_inlet_outlet_keepmean_64x32.kv
