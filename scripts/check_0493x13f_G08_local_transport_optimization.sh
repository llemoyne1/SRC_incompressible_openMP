#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}";cd "$ROOT"
for f in scripts/run_0493x13f_S1_G08_local_screen.sh scripts/analyze_0493x13f_S1_G08_local_screen.py scripts/run_0493x13f_S2_G08_local_qualification.sh scripts/analyze_0493x13f_S2_G08_local_qualification.py; do [[ -f "$f" ]] || { echo "missing $f" >&2;exit 2;};done
bash -n scripts/run_0493x13f_S1_G08_local_screen.sh
bash -n scripts/run_0493x13f_S2_G08_local_qualification.sh
python3 -m py_compile scripts/analyze_0493x13f_S1_G08_local_screen.py scripts/analyze_0493x13f_S2_G08_local_qualification.py
python3 - <<'PY'
import math
h=1/256;kbt=.125;gamma=8;mass=1.;cs=.3554482475790296
v=math.sqrt(math.pi*kbt/(2*mass))
for a,l in [(120,.48),(150,.80)]:
 dt=l*h/v;fg=(gamma-1+math.exp(-gamma))/gamma;q=fg*(1-math.cos(math.radians(a)));nu=kbt*dt*(1/q-.5)+h*h*q/(12*dt);H=cs*h/nu
 print(f'[0493x13f-check] alpha={a} lambda/h={l:.2f} nuSRD={nu:.9g} HhProxy={H:.4f}')
assert 3.0e-4 < nu < 7.0e-4
PY
echo '[0493x13f-check] syntax/design PASS; src/include untouched'
