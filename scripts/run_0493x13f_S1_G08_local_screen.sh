#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$ROOT/scripts/src_mpcd_run_common_0434.sh"
suite_root_cd_0434

CASE_LABEL=src_G08_local_transport_screen_0493x13f
CAMPAIGN_ROOT="${CAMPAIGN_ROOT:-runs/0493x13f_G08_local_transport_optimization}"
RUN_ROOT="$CAMPAIGN_ROOT/S1_screen_Ny128"
BIN="${BIN:-build/src_mpcd_base_cuda_q6_resident_livevis_0486}"

PREFLIGHT_ONLY="${PREFLIGHT_ONLY:-0}"
ANALYZE_ONLY="${ANALYZE_ONLY:-0}"
CLEAN_ROOT="${CLEAN_ROOT:-0}"
SKIP_EXISTING="${SKIP_EXISTING:-1}"
LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
THREADS="${THREADS:-8}"

ALPHAS="${ALPHAS:-120,130,140,150}"
LAMBDAS="${LAMBDAS:-0.48,0.56,0.64,0.72,0.80}"
S1_SEEDS="${S1_SEEDS:-4931411,4931412}"
SHEAR_NY="${SHEAR_NY:-128}"
SHEAR_NX="${SHEAR_NX:-32}"
SHEAR_AMPLITUDE="${SHEAR_AMPLITUDE:-0.05}"
TARGET_EFOLDS="${TARGET_EFOLDS:-1.4}"
DUMP_COUNT="${DUMP_COUNT:-96}"
SHORTLIST_N="${SHORTLIST_N:-3}"
PREFLIGHT_FIRST_SEED_ONLY="${PREFLIGHT_FIRST_SEED_ONLY:-1}"

GAMMA_FIXED=8
CELL_SIZE="0.00390625"
KBT="0.125"
MASS="1.0"
MODE_Y=1
CS_REF="${CS_REF:-0.3554482475790296}"

# Canonical helper globals; overridden per run.
NX="$SHEAR_NX"; NY="$SHEAR_NY"; GAMMA="$GAMMA_FIXED"; DT=.004231421876608172; PARTICLE_MASS="$MASS"
ROTATION_ANGLE=2.0943951023931953; RANDOM_ROTATION_SIGN=true; GRID_SHIFT_ENABLE=true
THERMOSTAT_ENABLE=true; THERMOSTAT_MODE=cell_relative_rescale; THERMOSTAT_EVERY=1
THERMOSTAT_TARGET_KBT="$KBT"; THERMOSTAT_MIN_PARTICLES=3; SEED=4931411

for dep in \
  scripts/generate_0493x13b_shear_state.py \
  scripts/analyze_0493x13b_constitutive_transport.py \
  scripts/analyze_0493w1_src_fluid_calibrator.py \
  scripts/analyze_0493x13f_S1_G08_local_screen.py; do
  [[ -f "$dep" ]] || { echo "[0493x13f-S1] missing dependency: $dep" >&2; exit 2; }
done
command -v python3 >/dev/null

if [[ "$ANALYZE_ONLY" == 1 ]]; then
  python3 scripts/analyze_0493x13f_S1_G08_local_screen.py \
    --campaign-root "$CAMPAIGN_ROOT" --repo-root "$ROOT" --shortlist-n "$SHORTLIST_N" --cs-ref "$CS_REF"
  exit 0
fi

if [[ "$CLEAN_ROOT" == 1 ]]; then rm -rf "$RUN_ROOT"; fi
mkdir -p "$RUN_ROOT"
rm -f "$RUN_ROOT/CAMPAIGN_COMPLETE_0493x13f_S1"
manifest="$RUN_ROOT/manifest_0493x13f_S1.csv"

python3 - "$manifest" "$ALPHAS" "$LAMBDAS" "$S1_SEEDS" "$SHEAR_NY" "$SHEAR_NX" "$CELL_SIZE" "$KBT" "$MASS" "$SHEAR_AMPLITUDE" "$TARGET_EFOLDS" "$DUMP_COUNT" <<'PY'
import csv,math,sys
(out,alphas,lambdas,seeds,ny,nx,h,kbt,mass,amp,target_efolds,dump_count)=sys.argv[1:]
ny=int(ny);nx=int(nx);h=float(h);kbt=float(kbt);mass=float(mass);amp=float(amp);target_efolds=float(target_efolds);dump_count=int(dump_count)
A=[float(x) for x in alphas.split(',') if x.strip()];L=[float(x) for x in lambdas.split(',') if x.strip()];S=[int(x) for x in seeds.split(',') if x.strip()]
if not A or not L or not S: raise SystemExit('empty x13f-S1 design axis')
gamma=8;vmean=math.sqrt(math.pi*kbt/(2*mass));rows=[]
for alpha in A:
  rad=math.radians(alpha);fg=(gamma-1.0+math.exp(-gamma))/gamma;q=fg*(1-math.cos(rad))
  for lam in L:
    dt=lam*h/vmean;nu=kbt*dt/mass*(1/q-0.5)+h*h*q/(12*dt)
    Lx=nx*h;Ly=ny*h;k=2*math.pi/Ly;T=target_efolds/(nu*k*k);steps=math.ceil(T/dt);dump=max(1,math.ceil(steps/dump_count))
    key=f'A{int(round(alpha)):03d}_L{int(round(lam*100)):03d}'
    for si,seed in enumerate(S):
      rows.append(dict(candidate=key,fluid='G08',role='gamma8_local_screen',gamma=gamma,rotationAngleDeg=alpha,rotationAngleRad=rad,targetLambdaMeanOverCell=lam,dt=dt,cellSize=h,lambdaPhysical=lam*h,viscositySRDKinematic=nu,Nx=nx,Ny=ny,Lx=Lx,Ly=Ly,wavelengthCells=ny,modeY=1,amplitude=amp,seedIndex=si,seed=seed,steps=steps,dumpEvery=dump,physicalTime=steps*dt,targetEfolds=target_efolds,kLambda=k*lam*h,runDir=f'{key}/Ny{ny}/seed{seed}',estimatedParticleSteps=nx*ny*gamma*steps))
with open(out,'w',newline='') as f:
  w=csv.DictWriter(f,fieldnames=list(rows[0]),lineterminator='\n');w.writeheader();w.writerows(rows)
print(f'[0493x13f-S1] manifest={out} candidates={len(A)*len(L)} runs={len(rows)} seeds={S} Ny={ny}')
print(f'[0493x13f-S1] totalParticleSteps={sum(int(r["estimatedParticleSteps"]) for r in rows)}')
PY

export OMP_NUM_THREADS="$THREADS" LIVE_PROGRESS
INACTIVE_SLOTS=0; SUMMARY_ROLE_FILTER=fluid; DUMP_ROLE_FILTER=fluid
SPECIES_RESAMPLING_ENABLE=false; WEIGHTED_RESAMPLING_ENABLE_OVERRIDE=false
CUDA_EMPTY_REFILL_ENABLE_OVERRIDE=false; RESAMPLING_THERMAL_RENORMALIZATION_ENABLE=false
RESAMPLING_MASS_GUARD_ENABLE=false; PROJECTION_BACKEND=cuda; PROJECTION_OPERATOR=auto_fv_cg
PROJECTION_MAX_ITERATIONS=100; PROJECTION_TOLERANCE=1e-12
PROJECTION_MOMENTUM_CORRECTION_ENABLE=true; Q6_PROJECTION_STRENGTH=1.0
LIVE_VIS_ENABLE=0; FILTERED_RECORDING_ENABLE=0; RECORD_ENABLE=false; PARTICLE_TYPE_FILTER=-1
suite_defaults_common_0434
suite_compute_derived_0434
[[ "$PREFLIGHT_ONLY" == 1 ]] || suite_ensure_binary_0434

runs_done=0;runs_skipped=0;preflight_done=0
while IFS=, read -r candidate fluid role gamma deg rad lam dt h lamphys nuSrd nx ny lx ly wc mode amp seedIndex seed steps dump T efolds klambda runDir particleSteps; do
  [[ "$candidate" == candidate ]] && continue
  if [[ "$PREFLIGHT_ONLY" == 1 && "$PREFLIGHT_FIRST_SEED_ONLY" == 1 && "$seedIndex" != 0 ]]; then continue; fi
  dir="$RUN_ROOT/$runDir";marker="$dir/RUN_COMPLETE_0493x13f_S1"
  if [[ "$PREFLIGHT_ONLY" != 1 && "$SKIP_EXISTING" == 1 && -f "$marker" ]]; then echo "[0493x13f-S1] SKIP $candidate seed=$seed";runs_skipped=$((runs_skipped+1));continue;fi
  mkdir -p "$dir/init" "$dir/output" "$dir/logs" "$dir/params"
  state="$dir/init/shear_0493x13f.smpcd"
  python3 scripts/generate_0493x13b_shear_state.py --output "$state" --Lx "$lx" --Ly "$ly" --Nx "$nx" --Ny "$ny" --gamma "$gamma" --kBT "$KBT" --mass "$MASS" --seed "$seed" --mode-y "$mode" --amplitude "$amp"
  SUMMARY_EVERY="$dump";DUMP_STATE_EVERY="$dump"
  cat > "$dir/params/params_0493x13f_S1.kv" <<PARAMS
inputState = $state
outputDir = $dir/output
Lx = $lx
Ly = $ly
Nx = $nx
Ny = $ny
dt = $dt
nSteps = $steps
bodyAccelerationX = 0.0
bodyAccelerationY = 0.0
keepMeanFlowEnable = false
taylorGreenForcingEnable = false
bcLeft = periodic
bcRight = periodic
bcBottom = periodic
bcTop = periodic
bcX = periodic
bcY = periodic
speciesRegistryEnable = false
speciesQ6Enable = false
PARAMS
  GAMMA="$gamma" DT="$dt" KBT="$KBT" PARTICLE_MASS="$MASS" ROTATION_ANGLE="$rad" RANDOM_ROTATION_SIGN=true GRID_SHIFT_ENABLE=true THERMOSTAT_ENABLE=true THERMOSTAT_MODE=cell_relative_rescale THERMOSTAT_EVERY=1 THERMOSTAT_TARGET_KBT="$KBT" THERMOSTAT_MIN_PARTICLES=3 SEED="$seed" suite_write_common_params_0434 src >> "$dir/params/params_0493x13f_S1.kv"
  suite_export_cuda_flags_0434 src periodic
  suite_preflight_run_ok_0492 "$dir/params/params_0493x13f_S1.kv"
  echo "[0493x13f-S1] candidate=$candidate alpha=$deg lambda/h=$lam seed=$seed nuSRD=$nuSrd steps=$steps kLambda=$klambda"
  if [[ "$PREFLIGHT_ONLY" == 1 ]]; then preflight_done=$((preflight_done+1));continue;fi
  rm -f "$marker"
  set +e
  /usr/bin/time -o "$dir/logs/time_0493x13f.txt" -f 'elapsed=%e user=%U sys=%S' "$BIN" "$dir/params/params_0493x13f_S1.kv" 2>&1 | tee "$dir/logs/run_0493x13f.log"
  rc=${PIPESTATUS[0]};set -e;[[ $rc -eq 0 ]] || exit "$rc";touch "$marker";runs_done=$((runs_done+1))
done < "$manifest"

if [[ "$PREFLIGHT_ONLY" == 1 ]]; then echo "[0493x13f-S1] PREFLIGHT PASS checked=$preflight_done";exit 0;fi
python3 scripts/analyze_0493x13f_S1_G08_local_screen.py --campaign-root "$CAMPAIGN_ROOT" --repo-root "$ROOT" --shortlist-n "$SHORTLIST_N" --cs-ref "$CS_REF"
touch "$RUN_ROOT/CAMPAIGN_COMPLETE_0493x13f_S1"
echo "[0493x13f-S1] CAMPAIGN COMPLETE new=$runs_done skipped=$runs_skipped"
