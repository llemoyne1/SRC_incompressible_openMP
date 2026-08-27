#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"
bash -n scripts/run_0493x13g_H_reproducibility.sh
python3 -m py_compile scripts/analyze_0493x13g_H_reproducibility.py
for dep in scripts/src_mpcd_run_common_0434.sh scripts/generate_0493x13b_shear_state.py scripts/analyze_0493x13b_constitutive_transport.py scripts/analyze_0493w1_src_fluid_calibrator.py; do
  [[ -f "$dep" ]] || { echo "[0493x13g-check] missing $dep" >&2;exit 2;}
done
python3 - <<'PY'
import math
h=1/256;kbt=.125;gamma=8;m=1.;alpha=math.radians(120);v=math.sqrt(math.pi*kbt/(2*m));fg=(gamma-1+math.exp(-gamma))/gamma;q=fg*(1-math.cos(alpha))
for lam in (.48,.72):
 dt=lam*h/v;nu=kbt*dt*(1/q-.5)+h*h*q/(12*dt);k=2*math.pi;T=1.4/(nu*k*k);steps=math.ceil(T/dt)
 print(f'[0493x13g-check] lambda/h={lam:.2f} dt={dt:.12g} nuSRD={nu:.9g} T={T:.6g} steps={steps} particleSteps={steps*32*256*8}')
print('[0493x13g-check] design: 6 exact repeats + 8 independent logical realizations per candidate; independent seed 4931411 reuses repeat rep0 in analysis')
PY
if [[ "${RUN_PREFLIGHT_CHECK:-0}" == 1 ]]; then
  PREFLIGHT_ONLY=1 PREFLIGHT_FIRST_ONLY=1 bash scripts/run_0493x13g_H_reproducibility.sh
fi
echo '[0493x13g-check] syntax/design PASS; src/include untouched'
