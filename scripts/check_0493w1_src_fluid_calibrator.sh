#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"
files=(
  scripts/run_0493w1_src_fluid_calibrator.sh
  scripts/generate_0493w1_src_fluid_calibrator_states.py
  scripts/analyze_0493w1_src_fluid_calibrator.py
  scripts/run_0493w1_src_fluid_presweep.sh
  scripts/analyze_0493w1_src_fluid_presweep.py
  doc/README_0493W1_SRC_FLUID_CALIBRATOR.md
)
for file in "${files[@]}"; do [[ -f "$file" ]] || { echo "[0493w1-check] missing=$file" >&2; exit 2; }; done
bash -n scripts/run_0493w1_src_fluid_calibrator.sh
bash -n scripts/run_0493w1_src_fluid_presweep.sh
python3 -m py_compile scripts/generate_0493w1_src_fluid_calibrator_states.py scripts/analyze_0493w1_src_fluid_calibrator.py scripts/analyze_0493w1_src_fluid_presweep.py
python3 - <<'PY'
import numpy
print('[0493w1-check] numpy=' + numpy.__version__)
PY

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
for case_name in tg sound msd; do
  python3 scripts/generate_0493w1_src_fluid_calibrator_states.py --case "$case_name" --output "$tmp/$case_name.smpcd" --Lx 1 --Ly 1 --Nx 8 --Ny 8 --gamma 8 --dt .001 --kBT .01 --mass 1 --sound-mode-x 1 >/dev/null
  [[ -s "$tmp/$case_name.smpcd" ]]
done

grep -q 'ensemble_cumulative_hydrodynamic_regression' scripts/analyze_0493w1_src_fluid_calibrator.py
grep -q 'SOUND_REPLICATES="${SOUND_REPLICATES:-4}"' scripts/run_0493w1_src_fluid_calibrator.sh
grep -q 'SOUND_DENSITY_AMPLITUDE="${SOUND_DENSITY_AMPLITUDE:-0.08}"' scripts/run_0493w1_src_fluid_calibrator.sh
grep -q 'soundStatus' scripts/analyze_0493w1_src_fluid_calibrator.py
grep -q 'reynoldsAtMach0p3' scripts/analyze_0493w1_src_fluid_calibrator.py
grep -q 'physical6' scripts/run_0493w1_src_fluid_presweep.sh

python3 - "$ROOT/scripts/analyze_0493w1_src_fluid_calibrator.py" <<'PY_HYDRO'
import importlib.util, math, sys
import numpy as np
spec=importlib.util.spec_from_file_location('cal',sys.argv[1]); m=importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
def exact(cs,nu,k,dt,n):
    g=np.array([[0,-1j*k],[-1j*k*cs*cs,-nu*k*k]],complex)
    w,v=np.linalg.eig(g); iv=np.linalg.inv(v); q0=np.array([.08+0j,0j]); t=np.arange(n)*dt
    q=np.array([v@np.diag(np.exp(w*x))@iv@q0 for x in t]); return t,q[:,0],q[:,1]
for regime,cs,nu in [('underdamped',.4,.01),('overdamped',.05,.2)]:
    t,r,u=exact(cs,nu,2*math.pi,.005,251)
    z=m.fit_longitudinal_hydrodynamics(t,r,u,2*math.pi)
    assert z['regime']==regime,z
    assert abs(z['soundSpeed']/cs-1)<.01,z
    assert abs(z['nuL']/nu-1)<.03,z
    assert z['momentumRelativeRms']<1e-3,z
    assert z['continuityRelativeRms']<1e-3,z
# Ensemble averaging should reduce independent velocity noise.
rng=np.random.default_rng(493)
t,r,u=exact(.35,.015,2*math.pi,.005,241)
noisy=[]
for _ in range(8): noisy.append(u + (rng.normal(size=len(u))+1j*rng.normal(size=len(u)))*2e-3)
avg=np.mean(noisy,axis=0)
z=m.fit_longitudinal_hydrodynamics(t,r,avg,2*math.pi)
assert abs(z['soundSpeed']/.35-1)<.08,z
print('[0493w1-check] cumulativeSynthetic=PASS underdamped+overdamped+ensemble')
PY_HYDRO

PREFLIGHT_ONLY=1 Lx=.25 Ly=.25 NX=64 NY=64 DT=.002 KBT=.125 THERMOSTAT_ENABLE=true THERMOSTAT_TARGET_KBT=.125 SOUND_REPLICATES=4 bash scripts/run_0493w1_src_fluid_calibrator.sh >/dev/null
PREFLIGHT_ONLY=1 PROFILE=smoke2 bash scripts/run_0493w1_src_fluid_presweep.sh >/dev/null

echo '[0493w1-check] PASS fix3=ensemble-cumulative-physical-presweep'
