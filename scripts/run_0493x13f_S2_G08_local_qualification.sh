#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$ROOT/scripts/src_mpcd_run_common_0434.sh"
suite_root_cd_0434
CASE_LABEL=src_G08_local_transport_qualification_0493x13f
CAMPAIGN_ROOT="${CAMPAIGN_ROOT:-runs/0493x13f_G08_local_transport_optimization}"
S1_ROOT="$CAMPAIGN_ROOT/S1_screen_Ny128"
RUN_ROOT="$CAMPAIGN_ROOT/S2_qualification"
ANALYSIS_ROOT="$CAMPAIGN_ROOT/analysis"
SHORTLIST="$ANALYSIS_ROOT/S1_shortlist_0493x13f.csv"
BIN="${BIN:-build/src_mpcd_base_cuda_q6_resident_livevis_0486}"
PREFLIGHT_ONLY="${PREFLIGHT_ONLY:-0}";ANALYZE_ONLY="${ANALYZE_ONLY:-0}";CLEAN_ROOT="${CLEAN_ROOT:-0}";SKIP_EXISTING="${SKIP_EXISTING:-1}";LIVE_PROGRESS="${LIVE_PROGRESS:-1}";THREADS="${THREADS:-8}"
H_SEEDS="${H_SEEDS:-4931411,4931412,4931413,4931414}";NY_LIST="${NY_LIST:-128,256}";SHEAR_NX="${SHEAR_NX:-32}";SHEAR_AMPLITUDE="${SHEAR_AMPLITUDE:-0.05}";TARGET_EFOLDS="${TARGET_EFOLDS:-1.4}";DUMP_COUNT="${DUMP_COUNT:-96}";PREFLIGHT_FIRST_SEED_ONLY="${PREFLIGHT_FIRST_SEED_ONLY:-1}"
GAMMA_FIXED=8;CELL_SIZE="0.00390625";KBT="0.125";MASS="1.0";CS_REF="${CS_REF:-0.3554482475790296}"
NX="$SHEAR_NX";NY=128;GAMMA=8;DT=.004231421876608172;PARTICLE_MASS="$MASS";ROTATION_ANGLE=2.0943951023931953;RANDOM_ROTATION_SIGN=true;GRID_SHIFT_ENABLE=true;THERMOSTAT_ENABLE=true;THERMOSTAT_MODE=cell_relative_rescale;THERMOSTAT_EVERY=1;THERMOSTAT_TARGET_KBT="$KBT";THERMOSTAT_MIN_PARTICLES=3;SEED=4931411
for dep in scripts/generate_0493x13b_shear_state.py scripts/analyze_0493x13b_constitutive_transport.py scripts/analyze_0493x13f_S2_G08_local_qualification.py; do [[ -f "$dep" ]] || { echo "[0493x13f-S2] missing $dep" >&2;exit 2;};done
[[ -f "$SHORTLIST" ]] || { echo "[0493x13f-S2] missing shortlist $SHORTLIST; run S1 first" >&2;exit 2;}
if [[ "$ANALYZE_ONLY" == 1 ]]; then python3 scripts/analyze_0493x13f_S2_G08_local_qualification.py --campaign-root "$CAMPAIGN_ROOT" --repo-root "$ROOT" --cs-ref "$CS_REF";exit 0;fi
[[ "$CLEAN_ROOT" == 1 ]] && rm -rf "$RUN_ROOT";mkdir -p "$RUN_ROOT";rm -f "$RUN_ROOT/CAMPAIGN_COMPLETE_0493x13f_S2"
manifest="$RUN_ROOT/manifest_0493x13f_S2.csv"
python3 - "$manifest" "$SHORTLIST" "$H_SEEDS" "$NY_LIST" "$SHEAR_NX" "$CELL_SIZE" "$KBT" "$MASS" "$SHEAR_AMPLITUDE" "$TARGET_EFOLDS" "$DUMP_COUNT" <<'PY'
import csv,math,sys
out,short,seeds,nys,nx,h,kbt,mass,amp,efolds,dumps=sys.argv[1:];nx=int(nx);h=float(h);kbt=float(kbt);mass=float(mass);amp=float(amp);efolds=float(efolds);dumps=int(dumps)
with open(short,newline='') as f: sel=list(csv.DictReader(f))
S=[int(x) for x in seeds.split(',') if x.strip()];NY=[int(x) for x in nys.split(',') if x.strip()];gamma=8;vmean=math.sqrt(math.pi*kbt/(2*mass));rows=[]
for c in sel:
  key=c['candidate'];alpha=float(c['alphaDeg']);lam=float(c['lambdaOverH']);rad=math.radians(alpha);fg=(gamma-1+math.exp(-gamma))/gamma;q=fg*(1-math.cos(rad));dt=lam*h/vmean;nu=kbt*dt/mass*(1/q-.5)+h*h*q/(12*dt)
  for ny in NY:
    Lx=nx*h;Ly=ny*h;k=2*math.pi/Ly;T=efolds/(nu*k*k);steps=math.ceil(T/dt);dump=max(1,math.ceil(steps/dumps))
    for si,seed in enumerate(S):
      reuse=1 if ny==128 and si<2 else 0;source='S1' if reuse else 'S2'
      rows.append(dict(candidate=key,fluid='G08',role='gamma8_local_qualification',gamma=gamma,rotationAngleDeg=alpha,rotationAngleRad=rad,targetLambdaMeanOverCell=lam,dt=dt,cellSize=h,lambdaPhysical=lam*h,viscositySRDKinematic=nu,Nx=nx,Ny=ny,Lx=Lx,Ly=Ly,wavelengthCells=ny,modeY=1,amplitude=amp,seedIndex=si,seed=seed,steps=steps,dumpEvery=dump,physicalTime=steps*dt,targetEfolds=efolds,kLambda=k*lam*h,runDir=f'{key}/Ny{ny}/seed{seed}',reuseFromS1=reuse,sourceRoot=source,estimatedParticleSteps=0 if reuse else nx*ny*gamma*steps))
with open(out,'w',newline='') as f:w=csv.DictWriter(f,fieldnames=list(rows[0]),lineterminator='\n');w.writeheader();w.writerows(rows)
print(f'[0493x13f-S2] selected={[x["candidate"] for x in sel]} manifestRuns={len(rows)} newRuns={sum(1-int(r["reuseFromS1"]) for r in rows)} totalNewParticleSteps={sum(int(r["estimatedParticleSteps"]) for r in rows)}')
PY
export OMP_NUM_THREADS="$THREADS" LIVE_PROGRESS
INACTIVE_SLOTS=0;SUMMARY_ROLE_FILTER=fluid;DUMP_ROLE_FILTER=fluid;SPECIES_RESAMPLING_ENABLE=false;WEIGHTED_RESAMPLING_ENABLE_OVERRIDE=false;CUDA_EMPTY_REFILL_ENABLE_OVERRIDE=false;RESAMPLING_THERMAL_RENORMALIZATION_ENABLE=false;RESAMPLING_MASS_GUARD_ENABLE=false;PROJECTION_BACKEND=cuda;PROJECTION_OPERATOR=auto_fv_cg;PROJECTION_MAX_ITERATIONS=100;PROJECTION_TOLERANCE=1e-12;PROJECTION_MOMENTUM_CORRECTION_ENABLE=true;Q6_PROJECTION_STRENGTH=1.0;LIVE_VIS_ENABLE=0;FILTERED_RECORDING_ENABLE=0;RECORD_ENABLE=false;PARTICLE_TYPE_FILTER=-1
suite_defaults_common_0434;suite_compute_derived_0434;[[ "$PREFLIGHT_ONLY" == 1 ]] || suite_ensure_binary_0434
runs_done=0;runs_skipped=0;preflight_done=0
while IFS=, read -r candidate fluid role gamma deg rad lam dt h lamphys nuSrd nx ny lx ly wc mode amp seedIndex seed steps dump T efolds klambda runDir reuse sourceRoot particleSteps; do
  [[ "$candidate" == candidate ]] && continue
  if [[ "$reuse" == 1 ]]; then echo "[0493x13f-S2] REUSE S1 $candidate Ny=$ny seed=$seed";continue;fi
  if [[ "$PREFLIGHT_ONLY" == 1 && "$PREFLIGHT_FIRST_SEED_ONLY" == 1 && "$seedIndex" != 0 ]]; then continue;fi
  dir="$RUN_ROOT/$runDir";marker="$dir/RUN_COMPLETE_0493x13f_S2"
  if [[ "$PREFLIGHT_ONLY" != 1 && "$SKIP_EXISTING" == 1 && -f "$marker" ]]; then echo "[0493x13f-S2] SKIP $candidate Ny=$ny seed=$seed";runs_skipped=$((runs_skipped+1));continue;fi
  mkdir -p "$dir/init" "$dir/output" "$dir/logs" "$dir/params";state="$dir/init/shear_0493x13f.smpcd"
  python3 scripts/generate_0493x13b_shear_state.py --output "$state" --Lx "$lx" --Ly "$ly" --Nx "$nx" --Ny "$ny" --gamma "$gamma" --kBT "$KBT" --mass "$MASS" --seed "$seed" --mode-y "$mode" --amplitude "$amp"
  SUMMARY_EVERY="$dump";DUMP_STATE_EVERY="$dump"
  cat > "$dir/params/params_0493x13f_S2.kv" <<PARAMS
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
  GAMMA="$gamma" DT="$dt" KBT="$KBT" PARTICLE_MASS="$MASS" ROTATION_ANGLE="$rad" RANDOM_ROTATION_SIGN=true GRID_SHIFT_ENABLE=true THERMOSTAT_ENABLE=true THERMOSTAT_MODE=cell_relative_rescale THERMOSTAT_EVERY=1 THERMOSTAT_TARGET_KBT="$KBT" THERMOSTAT_MIN_PARTICLES=3 SEED="$seed" suite_write_common_params_0434 src >> "$dir/params/params_0493x13f_S2.kv"
  suite_export_cuda_flags_0434 src periodic;suite_preflight_run_ok_0492 "$dir/params/params_0493x13f_S2.kv"
  echo "[0493x13f-S2] candidate=$candidate alpha=$deg lambda/h=$lam Ny=$ny seed=$seed steps=$steps"
  if [[ "$PREFLIGHT_ONLY" == 1 ]]; then preflight_done=$((preflight_done+1));continue;fi
  rm -f "$marker";set +e;/usr/bin/time -o "$dir/logs/time_0493x13f.txt" -f 'elapsed=%e user=%U sys=%S' "$BIN" "$dir/params/params_0493x13f_S2.kv" 2>&1 | tee "$dir/logs/run_0493x13f.log";rc=${PIPESTATUS[0]};set -e;[[ $rc -eq 0 ]] || exit "$rc";touch "$marker";runs_done=$((runs_done+1))
done < "$manifest"
if [[ "$PREFLIGHT_ONLY" == 1 ]]; then echo "[0493x13f-S2] PREFLIGHT PASS checked=$preflight_done";exit 0;fi
python3 scripts/analyze_0493x13f_S2_G08_local_qualification.py --campaign-root "$CAMPAIGN_ROOT" --repo-root "$ROOT" --cs-ref "$CS_REF"
touch "$RUN_ROOT/CAMPAIGN_COMPLETE_0493x13f_S2";echo "[0493x13f-S2] CAMPAIGN COMPLETE new=$runs_done skipped=$runs_skipped"
