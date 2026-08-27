#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"

echo '[0493x13c-check] syntax'
bash -n scripts/run_0493x13c_H_gamma_multiseed.sh
bash -n scripts/run_0493x13c_C_longitudinal_statistics.sh
python3 -m py_compile scripts/analyze_0493x13c_H_gamma_multiseed.py scripts/analyze_0493x13c_C_longitudinal_statistics.py

for dep in \
 scripts/src_mpcd_run_common_0434.sh \
 scripts/generate_0493x13b_shear_state.py \
 scripts/generate_0493x13b_sound_state_fractional.py \
 scripts/analyze_0493x13b_constitutive_transport.py \
 scripts/analyze_0493w1_src_fluid_calibrator.py; do
 [[ -f "$dep" ]] || { echo "[0493x13c-check] missing $dep" >&2; exit 2; }
done

# Directly recheck the low-gamma fractional stimulus that motivated fix1.
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
python3 scripts/generate_0493x13b_sound_state_fractional.py \
 --output "$tmp/g06.smpcd" --metadata "$tmp/g06.json" \
 --Lx .25 --Ly .0625 --Nx 64 --Ny 16 --gamma 6 --dt .004231421876608172 \
 --kBT .125 --mass 1 --seed 4931511 --sound-mode-x 1 --sound-density-amplitude .04 >/dev/null
python3 - "$tmp/g06.json" <<'PY'
import json,sys
m=json.load(open(sys.argv[1])); req=float(m['requestedDensityAmplitude']); got=float(m['realizedCosDensityAmplitude'])
assert int(m['totalParticles'])==64*16*6
assert abs(got-req)/req < 0.01, (req,got)
print(f'[0493x13c-check] fractional sound gamma=6 requested={req:.6g} realized={got:.9g} conservation=exact')
PY

echo '[0493x13c-check] PASS'
