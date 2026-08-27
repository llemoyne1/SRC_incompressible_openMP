#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}";cd "$ROOT"
for f in scripts/generate_0493x13e_longitudinal_velocity_state.py scripts/analyze_0493x13e_Ciso_mach_sweep.py scripts/run_0493x13e_Ciso_mach_sweep.sh; do [[ -f "$f" ]] || { echo "missing $f" >&2;exit 2;};done
python3 -m py_compile scripts/generate_0493x13e_longitudinal_velocity_state.py scripts/analyze_0493x13e_Ciso_mach_sweep.py
bash -n scripts/run_0493x13e_Ciso_mach_sweep.sh
python3 scripts/analyze_0493x13e_Ciso_mach_sweep.py --self-test
TMP=$(mktemp -d);trap 'rm -rf "$TMP"' EXIT
python3 scripts/generate_0493x13e_longitudinal_velocity_state.py --output "$TMP/test.smpcd" --metadata "$TMP/test.json" --Lx .5 --Ly .0625 --Nx 128 --Ny 16 --gamma 8 --kBT .125 --mass 1 --seed 4931611 --mode-x 1 --amplitude .1777241237895148 --mach-requested .5 --sound-speed-reference .3554482475790296
python3 - "$TMP/test.json" <<'PY'
import json,sys
m=json.load(open(sys.argv[1]));err=abs(m['relativeVelocityAmplitudeError']);assert m['totalParticles']==128*16*8;assert err<0.01,err
print(f"[0493x13e-check] generator conservation PASS relAmpErr={err:.3e}")
PY
echo "[0493x13e-check] syntax/selftest/generator PASS"
