#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$ROOT/scripts/src_mpcd_run_common_0434.sh"
suite_root_cd_0434

# 0446 smoke: periodic wall-free nonzero-plan case for the in-solver CUDA
# resampling pipeline shadow hook.  The initial state deliberately contains
# paired poor/rich cells so passive extraction/insertion operations are built,
# while all walls/chi/Darcy/inlet-outlet mechanisms remain disabled.

CASE_LABEL="periodic_nonzero_plan_0446"
TOPOLOGY="periodic"
Lx="${Lx:-1.0}"; Ly="${Ly:-1.0}"; NX="${NX:-64}"; NY="${NY:-64}"
GAMMA="${GAMMA:-40}"; STEPS="${STEPS:-5}"; DT="${DT:-0.001}"; KBT="${KBT:-0.001}"
SEED="${SEED:-1628638}"; U0="${U0:-0.02}"
BASE_RUN_ROOT="${BASE_RUN_ROOT:-runs/0446_periodic_nonzero_plan_shadow_smoke}"
INACTIVE_SLOTS_CELL_FRACTION="${INACTIVE_SLOTS_CELL_FRACTION:-0.25}"
SUMMARY_EVERY="${SUMMARY_EVERY:-1}"; DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-$STEPS}"
RUN_MODES="${RUN_MODES:-src-resampling src-q6-resampling}"
LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-0}"
FILTERED_RECORDING_ENABLE="${FILTERED_RECORDING_ENABLE:-0}"
FAIL_ON_ANY="${FAIL_ON_ANY:-1}"

# Clean profile controls: no CUDA-local auxiliaries, no population/mass guards.
export MPCD_CUDA_ACTIVE_PREFIX_HOST_TAIL_FULL_REPAIR_0315H="${MPCD_CUDA_ACTIVE_PREFIX_HOST_TAIL_FULL_REPAIR_0315H:-1}"
export MPCD_CUDA_ACTIVE_PREFIX_UPLOAD_FULL_ROLE_TAIL_0315K="${MPCD_CUDA_ACTIVE_PREFIX_UPLOAD_FULL_ROLE_TAIL_0315K:-1}"
export MASS_RECONDITION_ENABLE="${MASS_RECONDITION_ENABLE:-0}"
export RESAMPLING_SURVEY_ENABLE="${RESAMPLING_SURVEY_ENABLE:-0}"
export RESAMPLING_ADAPTIVE_FLAG_ENABLE="${RESAMPLING_ADAPTIVE_FLAG_ENABLE:-0}"
export CUDA_EMPTY_REFILL_ENABLE_OVERRIDE="${CUDA_EMPTY_REFILL_ENABLE_OVERRIDE:-0}"
export GUARD_EVERY="${GUARD_EVERY:-1000000000}"
export GUARD_NMIN="${GUARD_NMIN:-1}"
export GUARD_NTARGET="${GUARD_NTARGET:-$GAMMA}"
export GUARD_NMAX="${GUARD_NMAX:-100000}"
export RESAMPLING_EXTRACTION_ENABLE="${RESAMPLING_EXTRACTION_ENABLE:-true}"
export RESAMPLING_INSERTION_ENABLE="${RESAMPLING_INSERTION_ENABLE:-true}"
export RESAMPLING_REMAP_ENABLE="${RESAMPLING_REMAP_ENABLE:-true}"
export RESAMPLING_THERMAL_RENORMALIZATION_ENABLE="${RESAMPLING_THERMAL_RENORMALIZATION_ENABLE:-true}"
export RESAMPLING_MASS_GUARD_ENABLE="${RESAMPLING_MASS_GUARD_ENABLE:-false}"
export MPCD_CUDA_RESAMPLING_PIPELINE_SHADOW_0445="${MPCD_CUDA_RESAMPLING_PIPELINE_SHADOW_0445:-1}"
export MPCD_CUDA_RESAMPLING_PIPELINE_SHADOW_EVERY_0445="${MPCD_CUDA_RESAMPLING_PIPELINE_SHADOW_EVERY_0445:-1}"

RESAMPLING_NMIN_COEF="${RESAMPLING_NMIN_COEF:-0.40}"
RESAMPLING_NMAX_COEF="${RESAMPLING_NMAX_COEF:-0.60}"
suite_defaults_common_0434
suite_compute_derived_0434

write_nonzero_plan_state_0446() {
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
poor_count=max(1, gamma//8)
rich_count=2*gamma - poor_count
poor_cells=0; rich_cells=0
for j in range(Ny):
    y0=j*dy
    for i in range(Nx):
        x0=i*dx
        count=gamma
        # Paired poor/rich cells every 16 cells.  The pair conserves the total
        # particle count and mass exactly: poor_count + rich_count = 2*gamma.
        if (i % 16 == 0) and (j % 16 == 0) and i + 1 < Nx:
            count=poor_count; poor_cells += 1
        elif ((i-1) % 16 == 0) and (j % 16 == 0) and i > 0:
            count=rich_count; rich_cells += 1
        for _ in range(count):
            xp=x0+dx*rng.random(); yp=y0+dy*rng.random()
            ux=u0*math.sin(2.0*math.pi*yp/Ly)
            x.append(xp); y.append(yp)
            vx.append(ux + (sigma*rng.gauss(0.0,1.0) if sigma else 0.0))
            vy.append(sigma*rng.gauss(0.0,1.0) if sigma else 0.0)
            typ.append(btype); masses.append(mass); role.append(1)
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
reserved=[0]*8; reserved[0]=1; reserved[1]=sum(1 for r in role if r==1)
with open(state,'wb') as f:
    f.write(magic)
    f.write(struct.pack('<IIIIQIIII',2,0x01020304,2,1,n,1,1,8,4))
    f.write(struct.pack('<8Q',*reserved))
    for arr,fmt in [(x,'d'),(y,'d'),(vx,'d'),(vy,'d'),(typ,'I'),(masses,'d'),(role,'B')]:
        f.write(struct.pack(f'<{n}{fmt}',*arr))
print(f"[0446-generate] state={state} grid={Nx}x{Ny} gamma={gamma} fluid={sum(1 for r in role if r==1)} inactive={sum(1 for r in role if r==0)} poorCellsSeeded={poor_cells} richCellsSeeded={rich_cells} poorCount={poor_count} richCount={rich_count}")
PY
}

write_params_0446() {
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

run_one_mode_0446() {
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
  write_nonzero_plan_state_0446 "$state"
  write_params_0446 "$mode" "$state" "$out" "$params"
  suite_export_cuda_flags_0434 "$mode" "$TOPOLOGY"
  suite_prepare_livevis_control_0434 "$run_root" "$mode"
  suite_export_livevis_0434
  suite_write_env_file_0434 "$run_root/logs/environment_0434.env" "$mode"
  echo "[0446] case=$CASE_LABEL mode=$mode root=$run_root"
  suite_run_binary_0434 "$params" "$log" "$time" "$out"
}

mkdir -p "$BASE_RUN_ROOT"
STATUS="$BASE_RUN_ROOT/launch_status.csv"
echo "mode,exit_code" > "$STATUS"
failures=0
for mode in $RUN_MODES; do
  set +e
  run_one_mode_0446 "$mode"
  rc=$?
  set -e
  echo "$mode,$rc" >> "$STATUS"
  if [[ "$rc" != 0 ]]; then failures=$((failures+1)); fi
done

python3 - <<'PY'
import csv, pathlib, sys, os
root = pathlib.Path(os.environ.get('BASE_RUN_ROOT', 'runs/0446_periodic_nonzero_plan_shadow_smoke'))
rows=[]
for path in sorted(root.glob('**/cuda_resampling_pipeline_shadow_0445.csv')):
    with path.open(newline='') as f:
        for r in csv.DictReader(f):
            r['csv']=str(path); rows.append(r)
print(f"0446 shadow rows: {len(rows)}")
if not rows:
    sys.exit(2)

def num(r,k):
    try: return float(r.get(k,'0') or 0)
    except Exception: return 0.0
handled=[r for r in rows if r.get('handled')=='1']
failed=[r for r in handled if r.get('pass')!='1']
skipped=[r for r in rows if r.get('skipped')=='1']
nonzero=[r for r in handled if num(r,'passiveOps')>0]
print(f"handled={len(handled)} failed={len(failed)} skipped={len(skipped)} nonzeroPassiveRows={len(nonzero)}")
if nonzero:
    print(f"maxPassiveOps={max(num(r,'passiveOps') for r in nonzero):.0f}")
    print(f"maxRoleMismatch={max(num(r,'roleMismatch') for r in handled):.0f}")
    print(f"maxTypeMismatch={max(num(r,'typeMismatch') for r in handled):.0f}")
    print(f"maxBadPrefixCpu={max(num(r,'badPrefixCpu') for r in handled):.0f} maxBadPrefixGpu={max(num(r,'badPrefixGpu') for r in handled):.0f}")
    print(f"maxAbsX={max(abs(num(r,'maxAbsX')) for r in handled):.3e} maxAbsY={max(abs(num(r,'maxAbsY')) for r in handled):.3e}")
    print(f"maxAbsMass={max(abs(num(r,'maxAbsMass')) for r in handled):.3e} maxAbsVx={max(abs(num(r,'maxAbsVx')) for r in handled):.3e} maxAbsVy={max(abs(num(r,'maxAbsVy')) for r in handled):.3e}")
for r in failed[:10]:
    print('FAIL', r.get('csv'), 'step', r.get('step'), 'reason', r.get('skipReason'))
if failed or skipped or not nonzero:
    sys.exit(1)
PY

if [[ "$failures" != 0 && "$FAIL_ON_ANY" == 1 ]]; then
  echo "[0446] FAIL: failures=$failures" >&2
  exit 1
fi
