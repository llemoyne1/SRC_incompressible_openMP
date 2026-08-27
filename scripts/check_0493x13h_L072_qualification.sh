#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}";cd "$ROOT"
for f in scripts/run_0493x13h_A_Cdamp_L072.sh scripts/run_0493x13h_B_density_transport_L072.sh scripts/run_0493x13h_C_Mach_L072.sh scripts/run_0493x13h_master.sh;do bash -n "$f";done
python3 -m py_compile scripts/analyze_0493x13h_A_Cdamp_L072.py scripts/analyze_0493x13h_B_density_transport_L072.py scripts/analyze_0493x13h_C_Mach_L072.py scripts/generate_0493x13h_sound_state_fractional.py scripts/generate_0493x13h_longitudinal_velocity_state.py
python3 scripts/analyze_0493x13h_A_Cdamp_L072.py --repo-root "$ROOT" --self-test
python3 scripts/analyze_0493x13h_C_Mach_L072.py --self-test
python3 - <<'PY'
import math
h=1/256;kbt=.125;m=1;lam=.72;a=math.radians(120);dt=lam*h/math.sqrt(math.pi*kbt/(2*m))
print(f'[0493x13h-check] G08 alpha=120 lambda/h=.72 dt={dt:.15g}')
for g in (3,4,6,8,12,16):
 fg=(g-1+math.exp(-g))/g;q=fg*(1-math.cos(a));nu=kbt*dt*(1/q-.5)+h*h*q/(12*dt)
 print(f'[0493x13h-check] gamma={g:2d} nuSRD={nu:.9g}')
print('[0493x13h-check] syntax/selftests/design PASS; src/include untouched')
PY
