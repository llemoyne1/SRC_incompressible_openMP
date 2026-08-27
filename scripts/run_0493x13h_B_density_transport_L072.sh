#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"; source "$ROOT/scripts/src_mpcd_run_common_0434.sh"; suite_root_cd_0434
CASE_LABEL=src_G08L072_density_transport_0493x13h
CAMPAIGN_ROOT="${CAMPAIGN_ROOT:-runs/0493x13h_L072_qualification}"; RUN_ROOT="$CAMPAIGN_ROOT/B_density"; BIN="${BIN:-build/src_mpcd_base_cuda_q6_resident_livevis_0486}"
PREFLIGHT_ONLY="${PREFLIGHT_ONLY:-0}"; ANALYZE_ONLY="${ANALYZE_ONLY:-0}"; CLEAN_ROOT="${CLEAN_ROOT:-0}"; SKIP_EXISTING="${SKIP_EXISTING:-1}"; LIVE_PROGRESS="${LIVE_PROGRESS:-1}"; THREADS="${THREADS:-8}"
GAMMAS_128="${GAMMAS_128:-3,4,6,8,12,16}"; GAMMAS_256="${GAMMAS_256:-3,4,6,8}"; SEEDS="${SEEDS:-4931911,4931912,4931913,4931914,4931915,4931916}"; SHEAR_NX="${SHEAR_NX:-32}"; AMPLITUDE="${AMPLITUDE:-0.05}"; TARGET_EFOLDS="${TARGET_EFOLDS:-1.4}"; DUMP_COUNT="${DUMP_COUNT:-96}"; PREFLIGHT_FIRST_SEED_ONLY="${PREFLIGHT_FIRST_SEED_ONLY:-1}"
CELL_SIZE="0.00390625"; KBT="0.125"; MASS="1.0"; ALPHA_DEG="120.0"; ALPHA_RAD="2.0943951023931953"; LAMBDA_OVER_H="0.72"
for dep in scripts/generate_0493x13h_shear_state.py scripts/analyze_0493x13b_constitutive_transport.py scripts/analyze_0493x13h_B_density_transport_L072.py; do [[ -f "$dep" ]] || { echo "[0493x13h-B] missing $dep" >&2; exit 2; }; done
if [[ "$ANALYZE_ONLY" == 1 ]]; then python3 scripts/analyze_0493x13h_B_density_transport_L072.py --campaign-root "$CAMPAIGN_ROOT" --repo-root "$ROOT"; exit 0; fi
[[ "$CLEAN_ROOT" == 1 ]] && rm -rf "$RUN_ROOT"; mkdir -p "$RUN_ROOT"; rm -f "$RUN_ROOT/CAMPAIGN_COMPLETE_0493x13h_B_density"; manifest="$RUN_ROOT/manifest_0493x13h_B_density.csv"
python3 - "$manifest" "$GAMMAS_128" "$GAMMAS_256" "$SEEDS" "$SHEAR_NX" "$CELL_SIZE" "$KBT" "$MASS" "$ALPHA_DEG" "$LAMBDA_OVER_H" "$AMPLITUDE" "$TARGET_EFOLDS" "$DUMP_COUNT" <<'PY'
import csv,math,sys
out,g128,g256,seeds,nx,h,kbt,mass,adeg,lam,amp,efolds,dumps=sys.argv[1:];nx=int(nx);h=float(h);kbt=float(kbt);mass=float(mass);adeg=float(adeg);lam=float(lam);amp=float(amp);efolds=float(efolds);dumps=int(dumps);seedv=[int(x) for x in seeds.split(',') if x]
vmean=math.sqrt(math.pi*kbt/(2*mass));dt=lam*h/vmean;rad=math.radians(adeg);rows=[]
for ny,gl in [(128,g128),(256,g256)]:
  for gamma in map(int,gl.split(',')):
    fg=(gamma-1+math.exp(-gamma))/gamma;q=fg*(1-math.cos(rad));nu=kbt*dt/mass*(1/q-.5)+h*h*q/(12*dt);Lx=nx*h;Ly=ny*h;k=2*math.pi/Ly;T=efolds/(nu*k*k);steps=math.ceil(T/dt);dump=max(1,math.ceil(steps/dumps))
    for seed in seedv:
      run=f'G{gamma:02d}/Ny{ny}/seed{seed}';rows.append(dict(gamma=gamma,rotationAngleDeg=adeg,rotationAngleRad=rad,targetLambdaMeanOverCell=lam,dt=dt,cellSize=h,lambdaPhysical=lam*h,viscositySRDKinematic=nu,Nx=nx,Ny=ny,Lx=Lx,Ly=Ly,wavelengthCells=ny,modeY=1,amplitude=amp,expectedSeeds=len(seedv),seed=seed,steps=steps,dumpEvery=dump,physicalTime=steps*dt,targetEfolds=efolds,kLambda=k*lam*h,runDir=run,estimatedParticleSteps=nx*ny*gamma*steps))
with open(out,'w',newline='') as f:w=csv.DictWriter(f,fieldnames=list(rows[0]),lineterminator='\n');w.writeheader();w.writerows(rows)
print(f'[0493x13h-B] runs={len(rows)} particleSteps={sum(int(r["estimatedParticleSteps"]) for r in rows)}')
for ny in (128,256):
  print('[0493x13h-B] Ny',ny,'gammas',sorted({r['gamma'] for r in rows if r['Ny']==ny}))
PY
NX="$SHEAR_NX"; NY=128; GAMMA=8; DT=.0063471328149122585; PARTICLE_MASS="$MASS"; ROTATION_ANGLE="$ALPHA_RAD"; RANDOM_ROTATION_SIGN=true; GRID_SHIFT_ENABLE=true; THERMOSTAT_ENABLE=true; THERMOSTAT_MODE=cell_relative_rescale; THERMOSTAT_EVERY=1; THERMOSTAT_TARGET_KBT="$KBT"; THERMOSTAT_MIN_PARTICLES=3; SEED=4931911
export OMP_NUM_THREADS="$THREADS" LIVE_PROGRESS; INACTIVE_SLOTS=0; SUMMARY_ROLE_FILTER=fluid; DUMP_ROLE_FILTER=fluid; SPECIES_RESAMPLING_ENABLE=false; WEIGHTED_RESAMPLING_ENABLE_OVERRIDE=false; CUDA_EMPTY_REFILL_ENABLE_OVERRIDE=false; RESAMPLING_THERMAL_RENORMALIZATION_ENABLE=false; RESAMPLING_MASS_GUARD_ENABLE=false; PROJECTION_BACKEND=cuda; PROJECTION_OPERATOR=auto_fv_cg; PROJECTION_MAX_ITERATIONS=100; PROJECTION_TOLERANCE=1e-12; PROJECTION_MOMENTUM_CORRECTION_ENABLE=true; Q6_PROJECTION_STRENGTH=1.0; LIVE_VIS_ENABLE=0; FILTERED_RECORDING_ENABLE=0; RECORD_ENABLE=false; PARTICLE_TYPE_FILTER=-1
suite_defaults_common_0434; suite_compute_derived_0434; [[ "$PREFLIGHT_ONLY" == 1 ]] || suite_ensure_binary_0434
new=0;skip=0;pf=0
while IFS=, read -r gamma deg rad lam dt h lamphys nuSrd nx ny lx ly wc mode amp expSeeds seed steps dump T efolds klambda runDir psteps; do
 [[ "$gamma" == gamma ]] && continue
 [[ "$PREFLIGHT_ONLY" == 1 && "$PREFLIGHT_FIRST_SEED_ONLY" == 1 && "$seed" != "${SEEDS%%,*}" ]] && continue
 dir="$RUN_ROOT/$runDir"; marker="$dir/RUN_COMPLETE_0493x13h_B_density"; if [[ "$PREFLIGHT_ONLY" != 1 && "$SKIP_EXISTING" == 1 && -f "$marker" ]]; then skip=$((skip+1));continue;fi
 mkdir -p "$dir/init" "$dir/output" "$dir/logs" "$dir/params"; state="$dir/init/shear_0493x13h_B.smpcd"
 python3 scripts/generate_0493x13h_shear_state.py --output "$state" --Lx "$lx" --Ly "$ly" --Nx "$nx" --Ny "$ny" --gamma "$gamma" --kBT "$KBT" --mass "$MASS" --seed "$seed" --mode-y "$mode" --amplitude "$amp"
 SUMMARY_EVERY="$dump";DUMP_STATE_EVERY="$dump"
 cat > "$dir/params/params_0493x13h_B.kv" <<PARAMS
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
 GAMMA="$gamma" DT="$dt" KBT="$KBT" PARTICLE_MASS="$MASS" ROTATION_ANGLE="$rad" RANDOM_ROTATION_SIGN=true GRID_SHIFT_ENABLE=true THERMOSTAT_ENABLE=true THERMOSTAT_MODE=cell_relative_rescale THERMOSTAT_EVERY=1 THERMOSTAT_TARGET_KBT="$KBT" THERMOSTAT_MIN_PARTICLES=3 SEED="$seed" suite_write_common_params_0434 src >> "$dir/params/params_0493x13h_B.kv"
 suite_export_cuda_flags_0434 src periodic;suite_preflight_run_ok_0492 "$dir/params/params_0493x13h_B.kv";echo "[0493x13h-B] gamma=$gamma Ny=$ny seed=$seed steps=$steps nuSRD=$nuSrd"
 if [[ "$PREFLIGHT_ONLY" == 1 ]];then pf=$((pf+1));continue;fi
 rm -f "$marker";set +e;/usr/bin/time -o "$dir/logs/time_0493x13h_B.txt" -f 'elapsed=%e user=%U sys=%S' "$BIN" "$dir/params/params_0493x13h_B.kv" 2>&1 | tee "$dir/logs/run_0493x13h_B.log";rc=${PIPESTATUS[0]};set -e;[[ $rc -eq 0 ]] || exit "$rc";touch "$marker";new=$((new+1))
done < "$manifest"
if [[ "$PREFLIGHT_ONLY" == 1 ]];then echo "[0493x13h-B] PREFLIGHT PASS checked=$pf";exit 0;fi
python3 scripts/analyze_0493x13h_B_density_transport_L072.py --campaign-root "$CAMPAIGN_ROOT" --repo-root "$ROOT";touch "$RUN_ROOT/CAMPAIGN_COMPLETE_0493x13h_B_density";echo "[0493x13h-B] COMPLETE new=$new skipped=$skip"
