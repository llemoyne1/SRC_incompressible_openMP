#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"

files=(
  scripts/run_0493x12cal_capillary_calibrator.sh
  scripts/analyze_0493x12cal_capillary_calibrator.py
  scripts/generate_0493x11b_capillary_wave_state.py
  doc/README_0493X12CAL_CAPILLARY_CALIBRATOR.md
)
for file in "${files[@]}"; do
  [[ -f "$file" ]] || { echo "[0493x12cal-check] missing=$file" >&2; exit 2; }
done

bash -n scripts/run_0493x12cal_capillary_calibrator.sh
python3 -m py_compile scripts/analyze_0493x12cal_capillary_calibrator.py scripts/generate_0493x11b_capillary_wave_state.py

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

python3 scripts/generate_0493x11b_capillary_wave_state.py \
  --output "$tmp/wave.smpcd" --Lx 0.25 --Ly 0.125 --nx 32 --ny 16 \
  --gamma 8 --mean-height 0.0625 --amplitude-cells 0.5 --mode 1 \
  --liquid-type 1 --liquid-mass 1 --kBT 0.01 --seed 493 >/dev/null
[[ -s "$tmp/wave.smpcd" ]]

python3 - "$ROOT/scripts/analyze_0493x12cal_capillary_calibrator.py" <<'PY_SYNTH'
import importlib.util, math, sys
path=sys.argv[1]
spec=importlib.util.spec_from_file_location("capcal",path)
m=importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

rho=1000.0
sigma_decl=2.0
gain=0.97
k=4.0
H=0.3
omega_decl=math.sqrt((sigma_decl/rho)*k**3*math.tanh(k*H))
omega=omega_decl*math.sqrt(gain)
dt=(2*math.pi/omega_decl)/100.0
t=[i*dt for i in range(126)]
y=[0.02*math.exp(-0.07*tt)*math.cos(omega*tt+0.2)+0.001 for tt in t]
fit=m.fit_damped(t,y,omega_decl)
omega_fit=fit[1]
sigma_eff=m.sigma_from_omega(rho,omega_fit,k,H)
assert abs(sigma_eff/(sigma_decl*gain)-1.0)<0.015,(sigma_eff,fit)
print(f"[0493x12cal-check] synthetic sigmaEff={sigma_eff:.8g} target={sigma_decl*gain:.8g} PASS")
PY_SYNTH

PREFLIGHT_ONLY=1 PROFILE=quick SIGMA_DECLARED=945 \
  RUN_ROOT="$tmp/preflight" \
  bash scripts/run_0493x12cal_capillary_calibrator.sh >/dev/null

grep -q 'surfaceTensionEffectiveRaw' scripts/analyze_0493x12cal_capillary_calibrator.py
grep -q 'WeberEffectiveRaw' scripts/analyze_0493x12cal_capillary_calibrator.py
grep -q 'MPCD_X12A_LOCAL_THERMAL_COOLING=1' scripts/run_0493x12cal_capillary_calibrator.sh
grep -q 'local SEED="$seed"' scripts/run_0493x12cal_capillary_calibrator.sh

python3 - "$ROOT/scripts/analyze_0493x12cal_capillary_calibrator.py" <<'PY_FIX2'
import importlib.util, math, sys
path=sys.argv[1]
spec=importlib.util.spec_from_file_location("capcal_fix2",path)
m=importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

# Regression 1: exact linear column-mass height despite over/under-occupied cells.
nx,ny=4,3
dy=0.25
mref=20.0
# Column totals = [20,40,60,80], but deliberately include cells >mref and
# compensating low/zero cells.  A clipped-alpha estimator would be biased.
data=[
    30,  5, 45,  0,
   -10, 30,  5, 50,
     0,  5, 10, 30,
]
heights,total=m.column_mass_heights(data,nx,ny,dy,mref)
expected=[0.25,0.50,0.75,1.00]
for got,want in zip(heights,expected):
    assert abs(got-want)<1e-12,(heights,expected)
assert abs(total-sum(data))<1e-12

# Regression 2: signed seed averaging must cancel equal/opposite perturbations
# before fitting/qualification.
base=[]
plus=[]
minus=[]
for step in range(20):
    t=0.1*step
    signal=0.01*math.cos(1.2*t)
    common={"step":step,"time":t,"meanHeight":0.25,
            "massEquivalentMeanHeight":0.25,"totalRecordedMass":100.0}
    base.append(dict(common,modeCosine=signal,modeSine=0.0,
                     modePrimary=signal,modeAmplitude=abs(signal)))
    plus.append(dict(common,modeCosine=signal+0.003,modeSine=0.002,
                     modePrimary=signal+0.003,
                     modeAmplitude=math.hypot(signal+0.003,0.002)))
    minus.append(dict(common,modeCosine=signal-0.003,modeSine=-0.002,
                      modePrimary=signal-0.003,
                      modeAmplitude=math.hypot(signal-0.003,-0.002)))
ens=m.ensemble_signed_trace([plus,minus])
for got,want in zip(ens,base):
    assert abs(got["modeCosine"]-want["modeCosine"])<1e-12
    assert abs(got["modeSine"])<1e-12
print("[0493x12cal-check] FIX2 column-mass+signed-ensemble regressions PASS")
PY_FIX2

echo "[0493x12cal-check] PASS syntax+generator+synthetic-fit+preflight+seed-contract+fix2-analysis"
