#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$ROOT/scripts/src_mpcd_run_common_0434.sh"
suite_root_cd_0434

# -----------------------------------------------------------------------------
# 0438 periodic wall-free path-equivalence runner: shear-wave decay.
# No wall, no solid/chi/Darcy, no inlet/outlet, no new solver parameter.
# -----------------------------------------------------------------------------
CASE_LABEL="periodic_shear_wave_0438"
TOPOLOGY="periodic"
Lx="${Lx:-1.0}"; Ly="${Ly:-1.0}"; NX="${NX:-64}"; NY="${NY:-64}"
GAMMA="${GAMMA:-40}"; STEPS="${STEPS:-2000}"; DT="${DT:-0.001}"; KBT="${KBT:-0.001}"
SEED="${SEED:-1628638}"; U0="${U0:-0.04}"
BASE_RUN_ROOT="${BASE_RUN_ROOT:-runs/0438_periodic_shear_wave_${NX}x${NY}_g${GAMMA}_s${STEPS}}"
INACTIVE_SLOTS_CELL_FRACTION="${INACTIVE_SLOTS_CELL_FRACTION:-0.25}"
SUMMARY_EVERY="${SUMMARY_EVERY:-100}"; DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-$STEPS}"
RUN_MODES="${RUN_MODES:-${INTEG_PATH:-${SRC_INTEG_PATH:-src src-resampling src-q6 src-q6-resampling}}}"

LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-0}"
FILTERED_RECORDING_ENABLE="${FILTERED_RECORDING_ENABLE:-0}"
LIVE_VIS_FIELD="${LIVE_VIS_FIELD:-ux}"
LIVE_VIS_EVERY="${LIVE_VIS_EVERY:-25}"
LIVE_VIS_NX="${LIVE_VIS_NX:-128}"; LIVE_VIS_NY="${LIVE_VIS_NY:-128}"
LIVE_VIS_COLORMAP="${LIVE_VIS_COLORMAP:-blue_red}"
LIVE_VIS_CLIP="${LIVE_VIS_CLIP:--1}"; LIVE_VIS_GAIN="${LIVE_VIS_GAIN:-1.0}"
LIVE_VIS_SMOOTH_PASSES="${LIVE_VIS_SMOOTH_PASSES:-4}"
RECORD_FIELDS="${RECORD_FIELDS:-rho,ux,uy}"; RECORD_STRIDE="${RECORD_STRIDE:-1}"
FILTER_MODE="${FILTER_MODE:-none}"; FILTER_SAMPLE_EVERY="${FILTER_SAMPLE_EVERY:-1}"

RESAMPLING_NMIN_COEF="${RESAMPLING_NMIN_COEF:-0.40}"
RESAMPLING_NMAX_COEF="${RESAMPLING_NMAX_COEF:-0.60}"
GUARD_EVERY="${GUARD_EVERY:-5}"
FAIL_ON_ANY="${FAIL_ON_ANY:-1}"

suite_defaults_common_0434
suite_compute_derived_0434

write_shear_state_0438() {
  local state=$1
  python3 - "$state" "$Lx" "$Ly" "$NX" "$NY" "$GAMMA" "$KBT" "$PARTICLE_MASS" "$SEED" "$U0" "$INACTIVE_SLOTS" "$BACKGROUND_TYPE" "$INACTIVE_TYPE" <<'PY'
import math, os, random, struct, sys
state, Lx, Ly, Nx, Ny, gamma, kBT, mass, seed, u0, inactive_slots, btype, itype = sys.argv[1:]
Lx=float(Lx); Ly=float(Ly); Nx=int(Nx); Ny=int(Ny); gamma=int(gamma)
kBT=float(kBT); mass=float(mass); seed=int(seed); u0=float(u0)
inactive_slots=int(inactive_slots); btype=int(btype); itype=int(itype)
rng=random.Random(seed)
dx=Lx/Nx; dy=Ly/Ny
sigma=math.sqrt(kBT/mass) if kBT > 0.0 and mass > 0.0 else 0.0
x=[]; y=[]; vx=[]; vy=[]; typ=[]; masses=[]; role=[]
for j in range(Ny):
    y0=j*dy
    for i in range(Nx):
        x0=i*dx
        for _ in range(gamma):
            xp=x0+dx*rng.random(); yp=y0+dy*rng.random()
            ux=u0*math.sin(2.0*math.pi*yp/Ly)
            uy=0.0
            x.append(xp); y.append(yp)
            vx.append(ux + (sigma*rng.gauss(0.0,1.0) if sigma else 0.0))
            vy.append(uy + (sigma*rng.gauss(0.0,1.0) if sigma else 0.0))
            typ.append(btype); masses.append(mass); role.append(1)
# Remove the finite-sample drift without changing the target shear mode.
fluid_mass=sum(m for m,r in zip(masses,role) if r == 1)
if fluid_mass > 0.0:
    mvx=sum(m*u for m,u,r in zip(masses,vx,role) if r == 1)/fluid_mass
    mvy=sum(m*v for m,v,r in zip(masses,vy,role) if r == 1)/fluid_mass
    for k,r in enumerate(role):
        if r == 1:
            vx[k]-=mvx; vy[k]-=mvy
for _ in range(max(0,inactive_slots)):
    x.append(0.0); y.append(0.0); vx.append(0.0); vy.append(0.0)
    typ.append(itype); masses.append(mass); role.append(0)
os.makedirs(os.path.dirname(state) or '.', exist_ok=True)
n=len(x)
magic=b"SRCMPCD_STATE" + b"\0"*(16-len("SRCMPCD_STATE"))
reserved=[0]*8; reserved[0]=1; reserved[1]=1
with open(state,'wb') as f:
    f.write(magic)
    f.write(struct.pack('<IIIIQIIII',2,0x01020304,2,1,n,1,1,8,4))
    f.write(struct.pack('<8Q',*reserved))
    for arr,fmt in [(x,'d'),(y,'d'),(vx,'d'),(vy,'d'),(typ,'I'),(masses,'d'),(role,'B')]:
        f.write(struct.pack(f'<{n}{fmt}',*arr))
print(f"[0438-shear-generate] state={state} grid={Nx}x{Ny} gamma={gamma} fluid={sum(1 for r in role if r==1)} inactive={sum(1 for r in role if r==0)} u0={u0}")
PY
}

write_params_0438() {
  local mode=$1 state=$2 out=$3 params=$4
  cat > "$params" <<PARAMS
inputState = $state
outputDir = $out
Lx = $Lx
Ly = $Ly
Nx = $NX
Ny = $NY
dt = $DT
nSteps = $STEPS
bcLeft = periodic
bcRight = periodic
bcBottom = periodic
bcTop = periodic
bcX = periodic
bcY = periodic
bodyAccelerationX = 0.0
bodyAccelerationY = 0.0
taylorGreenForcingEnable = false
PARAMS
  suite_write_common_params_0434 "$mode" >> "$params"
}

run_one_mode_0438() {
  local mode=$1
  suite_validate_path_0434 "$mode"
  local run_root="$BASE_RUN_ROOT/$mode"
  suite_prepare_dirs_0434 "$run_root"
  local state="$run_root/init/${CASE_LABEL}_${NX}x${NY}_g${GAMMA}.smpcd"
  local params="$run_root/params/${CASE_LABEL}.kv"
  local out="$run_root/output"
  local log="$run_root/logs/${CASE_LABEL}.log"
  local time="$run_root/logs/${CASE_LABEL}.time"
  mkdir -p "$out"
  write_shear_state_0438 "$state"
  write_params_0438 "$mode" "$state" "$out" "$params"
  suite_export_cuda_flags_0434 "$mode" "$TOPOLOGY"
  suite_prepare_livevis_control_0434 "$run_root" "$mode"
  suite_export_livevis_0434
  suite_write_env_file_0434 "$run_root/logs/environment_0434.env" "$mode"
  echo "[0438-shear] case=$CASE_LABEL mode=$mode root=$run_root"
  echo "[0438-shear] periodic wall-free; thresholds: Nmin=$GUARD_NMIN Ntarget=$GUARD_NTARGET Nmax=$GUARD_NMAX"
  suite_run_binary_0434 "$params" "$log" "$time" "$out"
}

mkdir -p "$BASE_RUN_ROOT"
STATUS="$BASE_RUN_ROOT/launch_status.csv"
echo "mode,exit_code" > "$STATUS"
failures=0
for mode in $RUN_MODES; do
  set +e
  run_one_mode_0438 "$mode"
  rc=$?
  set -e
  echo "$mode,$rc" >> "$STATUS"
  if [[ "$rc" != 0 ]]; then failures=$((failures+1)); fi
done

read -r -a MODES_ARRAY <<< "$RUN_MODES"
python3 scripts/analyze_periodic_modes_0438.py \
  --root "$BASE_RUN_ROOT" --case shear --modes "${MODES_ARRAY[@]}" \
  --Lx "$Lx" --Ly "$Ly" \
  --csv "$BASE_RUN_ROOT/periodic_shear_wave_summary_0438.csv" \
  --markdown "$BASE_RUN_ROOT/periodic_shear_wave_report_0438.md"

echo "[0438-shear] root=$BASE_RUN_ROOT"
echo "[0438-shear] summary=$BASE_RUN_ROOT/periodic_shear_wave_summary_0438.csv"
echo "[0438-shear] report=$BASE_RUN_ROOT/periodic_shear_wave_report_0438.md"
if [[ "$failures" != 0 && "$FAIL_ON_ANY" == 1 ]]; then
  echo "[0438-shear] FAIL: failures=$failures" >&2
  exit 1
fi
