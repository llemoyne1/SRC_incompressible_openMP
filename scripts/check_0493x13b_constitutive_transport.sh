#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}";cd "$ROOT"
for f in scripts/run_0493x13b_H_constitutive_shear.sh scripts/run_0493x13b_C_longitudinal_response.sh scripts/run_0493x13b_constitutive_transport.sh;do bash -n "$f";done
python3 -m py_compile scripts/generate_0493x13b_shear_state.py scripts/generate_0493x13b_sound_state_fractional.py scripts/analyze_0493x13b_constitutive_transport.py
for f in scripts/src_mpcd_run_common_0434.sh scripts/analyze_0493w1_src_fluid_calibrator.py;do [[ -f "$f" ]]||{ echo "missing $f" >&2;exit 2;};done

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
python3 scripts/generate_0493x13b_sound_state_fractional.py \
  --output "$tmp/g06_e002.smpcd" --metadata "$tmp/g06_e002.json" \
  --Lx .25 --Ly .0625 --Nx 64 --Ny 16 --gamma 6 --dt .004231421876608172 \
  --kBT .125 --mass 1 --seed 4931321 --sound-mode-x 1 --sound-density-amplitude .02 >/dev/null
python3 - "$tmp/g06_e002.json" <<'PY'
import json,sys
m=json.load(open(sys.argv[1]))
assert m['totalParticles']==m['expectedParticles']==64*16*6
assert m['minCellPopulation']>=4
assert abs(m['realizedCosDensityAmplitude']-.02)/.02 < .02
assert abs(m['realizedSinDensityAmplitude']) < 1e-6
print('[0493x13b-check] fractional sound G06 eps=.02 realized=',m['realizedCosDensityAmplitude'])
PY

echo '[0493x13b-check] syntax/dependencies/fractional-sound PASS'
