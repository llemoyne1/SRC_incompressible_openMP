#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$ROOT/scripts/src_mpcd_run_common_0434.sh"
suite_root_cd_0434

CASE_LABEL=src_G08_compressible_mach_sweep_0493x13e
CAMPAIGN_ROOT="${CAMPAIGN_ROOT:-runs/0493x13e_compressible_mach_reach}"
RUN_ROOT="$CAMPAIGN_ROOT/Ciso_mach"
BIN="${BIN:-build/src_mpcd_base_cuda_q6_resident_livevis_0486}"
PREFLIGHT_ONLY="${PREFLIGHT_ONLY:-0}";ANALYZE_ONLY="${ANALYZE_ONLY:-0}";CLEAN_ROOT="${CLEAN_ROOT:-0}";SKIP_EXISTING="${SKIP_EXISTING:-1}"
LIVE_PROGRESS="${LIVE_PROGRESS:-1}";THREADS="${THREADS:-8}";CONTINUE_ON_FAILURE="${CONTINUE_ON_FAILURE:-1}"
MACH_LIST="${MACH_LIST:-0.05,0.10,0.20,0.30,0.40,0.50,0.70,0.90,1.00}"
NX_LIST="${NX_LIST:-128,256}";NY="${NY:-16}";SEEDS="${SEEDS:-4931611,4931612,4931613}"
ACOUSTIC_CYCLES="${ACOUSTIC_CYCLES:-3.0}";DUMP_COUNT="${DUMP_COUNT:-80}";PREFLIGHT_FIRST_SEED_ONLY="${PREFLIGHT_FIRST_SEED_ONLY:-1}"
CELL_SIZE="0.00390625";GAMMA_G08=8;KBT="0.125";MASS="1.0";ROTATION_DEG=120;ROTATION_RAD="2.0943951023931953";TARGET_LAMBDA_OVER_H="0.48";MODE_X=1
CS_REF="${CS_REF:-0.3554482475790296}";NUT_REF="${NUT_REF:-0.0005328464868639473}"
NX=128;GAMMA=$GAMMA_G08;DT=.004231421876608172;PARTICLE_MASS="$MASS";ROTATION_ANGLE="$ROTATION_RAD";RANDOM_ROTATION_SIGN=true;GRID_SHIFT_ENABLE=true
THERMOSTAT_ENABLE=true;THERMOSTAT_MODE=cell_relative_rescale;THERMOSTAT_EVERY=1;THERMOSTAT_TARGET_KBT="$KBT";THERMOSTAT_MIN_PARTICLES=3;SEED=4931611
for dep in scripts/generate_0493x13e_longitudinal_velocity_state.py scripts/analyze_0493x13e_Ciso_mach_sweep.py scripts/analyze_0493w1_src_fluid_calibrator.py; do [[ -f "$dep" ]] || { echo "[0493x13e-Ciso] missing $dep" >&2; exit 2; }; done
command -v python3 >/dev/null
if [[ "$ANALYZE_ONLY" == 1 ]]; then python3 scripts/analyze_0493x13e_Ciso_mach_sweep.py --campaign-root "$CAMPAIGN_ROOT" --repo-root "$ROOT" --cs-ref "$CS_REF" --nuT-ref "$NUT_REF"; exit 0; fi
[[ "$CLEAN_ROOT" == 1 ]] && rm -rf "$RUN_ROOT";mkdir -p "$RUN_ROOT";rm -f "$RUN_ROOT/CAMPAIGN_COMPLETE_0493x13e_Ciso"
manifest="$RUN_ROOT/manifest_0493x13e_Ciso.csv"
python3 - "$manifest" "$MACH_LIST" "$NX_LIST" "$NY" "$SEEDS" "$CELL_SIZE" "$GAMMA_G08" "$KBT" "$MASS" "$ROTATION_DEG" "$TARGET_LAMBDA_OVER_H" "$CS_REF" "$ACOUSTIC_CYCLES" "$DUMP_COUNT" <<'PY'
import csv,math,sys
(out,machs,nxs,ny,seeds,h,gamma,kbt,mass,angle,lam,cs,cycles,dumps)=sys.argv[1:]
ny=int(ny);h=float(h);gamma=int(gamma);kbt=float(kbt);mass=float(mass);angle=float(angle);lam=float(lam);cs=float(cs);cycles=float(cycles);dumps=int(dumps)
vmean=math.sqrt(math.pi*kbt/(2*mass));dt=lam*h/vmean;seedv=[int(x) for x in seeds.split(',') if x.strip()];rows=[]
for nx in map(int,nxs.split(',')):
  Lx=nx*h;Ly=ny*h;period=Lx/cs;T=cycles*period;steps=math.ceil(T/dt);dump=max(1,math.ceil(steps/dumps));k=2*math.pi/Lx
  for ma in map(float,machs.split(',')):
    U=ma*cs
    for si,seed in enumerate(seedv):
      tag=f'Ma{ma:.2f}'.replace('.','p');run=f'G08/Nx{nx}/{tag}/seed{seed}'
      rows.append(dict(fluid='G08',role='compressible_isothermal_mach_scan',gamma=gamma,rotationAngleDeg=angle,rotationAngleRad=math.radians(angle),targetLambdaMeanOverCell=lam,dt=dt,cellSize=h,lambdaPhysical=lam*h,Nx=nx,Ny=ny,Lx=Lx,Ly=Ly,wavelengthCells=nx,modeX=1,mach=ma,velocityAmplitude=U,csReference=cs,expectedSeeds=len(seedv),seedIndex=si,seed=seed,acousticCycles=cycles,steps=steps,dumpEvery=dump,physicalTime=steps*dt,kLambda=k*lam*h,runDir=run,estimatedParticleSteps=nx*ny*gamma*steps))
with open(out,'w',newline='') as fp:
  w=csv.DictWriter(fp,fieldnames=list(rows[0]),lineterminator='\n');w.writeheader();w.writerows(rows)
print(f'[0493x13e-Ciso] manifest={out} runs={len(rows)}')
for nx in sorted(set(r['Nx'] for r in rows)):
  r=next(x for x in rows if x['Nx']==nx);print(f"[0493x13e-Ciso] Nx={nx} cycles={cycles} T={r['physicalTime']:.5g} steps={r['steps']} dump={r['dumpEvery']}")
PY
export OMP_NUM_THREADS="$THREADS" LIVE_PROGRESS
INACTIVE_SLOTS=0;SUMMARY_ROLE_FILTER=fluid;DUMP_ROLE_FILTER=fluid
SPECIES_RESAMPLING_ENABLE=false;WEIGHTED_RESAMPLING_ENABLE_OVERRIDE=false;CUDA_EMPTY_REFILL_ENABLE_OVERRIDE=false;RESAMPLING_THERMAL_RENORMALIZATION_ENABLE=false;RESAMPLING_MASS_GUARD_ENABLE=false
PROJECTION_BACKEND=cuda;PROJECTION_OPERATOR=auto_fv_cg;PROJECTION_MAX_ITERATIONS=100;PROJECTION_TOLERANCE=1e-12;PROJECTION_MOMENTUM_CORRECTION_ENABLE=true;Q6_PROJECTION_STRENGTH=1.0
LIVE_VIS_ENABLE=0;FILTERED_RECORDING_ENABLE=0;RECORD_ENABLE=false;PARTICLE_TYPE_FILTER=-1
suite_defaults_common_0434;suite_compute_derived_0434
[[ "$PREFLIGHT_ONLY" == 1 ]] || suite_ensure_binary_0434
new=0;skip=0;failed=0;pf=0
while IFS=, read -r fluid role gamma deg rad lam dt h lamphys nx ny lx ly wc mode ma U csRef expSeeds seedIndex seed cycles steps dump T klambda runDir psteps; do
  [[ "$fluid" == fluid ]] && continue
  [[ "$PREFLIGHT_ONLY" == 1 && "$PREFLIGHT_FIRST_SEED_ONLY" == 1 && "$seedIndex" != 0 ]] && continue
  dir="$RUN_ROOT/$runDir";marker="$dir/RUN_COMPLETE_0493x13e_Ciso";failmarker="$dir/RUN_FAILED_0493x13e_Ciso"
  if [[ "$PREFLIGHT_ONLY" != 1 && "$SKIP_EXISTING" == 1 && -f "$marker" ]]; then echo "[0493x13e-Ciso] SKIP $runDir";skip=$((skip+1));continue;fi
  mkdir -p "$dir/init" "$dir/output" "$dir/logs" "$dir/params";state="$dir/init/longitudinal_0493x13e.smpcd";meta="$dir/init/longitudinal_0493x13e.meta.json"
  python3 scripts/generate_0493x13e_longitudinal_velocity_state.py --output "$state" --metadata "$meta" --Lx "$lx" --Ly "$ly" --Nx "$nx" --Ny "$ny" --gamma "$gamma" --kBT "$KBT" --mass "$MASS" --seed "$seed" --mode-x "$mode" --amplitude "$U" --mach-requested "$ma" --sound-speed-reference "$csRef"
  SUMMARY_EVERY="$dump";DUMP_STATE_EVERY="$dump"
  cat > "$dir/params/params_0493x13e_Ciso.kv" <<PARAMS
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
  GAMMA="$gamma" DT="$dt" KBT="$KBT" PARTICLE_MASS="$MASS" ROTATION_ANGLE="$rad" RANDOM_ROTATION_SIGN=true GRID_SHIFT_ENABLE=true THERMOSTAT_ENABLE=true THERMOSTAT_MODE=cell_relative_rescale THERMOSTAT_EVERY=1 THERMOSTAT_TARGET_KBT="$KBT" THERMOSTAT_MIN_PARTICLES=3 SEED="$seed" suite_write_common_params_0434 src >> "$dir/params/params_0493x13e_Ciso.kv"
  suite_export_cuda_flags_0434 src periodic;suite_preflight_run_ok_0492 "$dir/params/params_0493x13e_Ciso.kv"
  echo "[0493x13e-Ciso] Nx=$nx Ma=$ma U0=$U seed=$seed steps=$steps cycles=$cycles"
  if [[ "$PREFLIGHT_ONLY" == 1 ]];then pf=$((pf+1));continue;fi
  rm -f "$marker" "$failmarker";set +e
  /usr/bin/time -o "$dir/logs/time_0493x13e.txt" -f 'elapsed=%e user=%U sys=%S' "$BIN" "$dir/params/params_0493x13e_Ciso.kv" 2>&1 | tee "$dir/logs/run_0493x13e.log"
  rc=${PIPESTATUS[0]};set -e
  if [[ $rc -ne 0 ]];then touch "$failmarker";failed=$((failed+1));echo "[0493x13e-Ciso] RUN FAILED rc=$rc $runDir" >&2;[[ "$CONTINUE_ON_FAILURE" == 1 ]] && continue || exit "$rc";fi
  touch "$marker";new=$((new+1))
done < "$manifest"
if [[ "$PREFLIGHT_ONLY" == 1 ]];then echo "[0493x13e-Ciso] PREFLIGHT PASS checked=$pf";exit 0;fi
python3 scripts/analyze_0493x13e_Ciso_mach_sweep.py --campaign-root "$CAMPAIGN_ROOT" --repo-root "$ROOT" --cs-ref "$CS_REF" --nuT-ref "$NUT_REF"
touch "$RUN_ROOT/CAMPAIGN_COMPLETE_0493x13e_Ciso";echo "[0493x13e-Ciso] CAMPAIGN COMPLETE new=$new skipped=$skip failed=$failed"
