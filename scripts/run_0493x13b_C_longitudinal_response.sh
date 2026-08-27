#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"; source "$ROOT/scripts/src_mpcd_run_common_0434.sh"; suite_root_cd_0434
CASE_LABEL=src_longitudinal_response_0493x13b
CAMPAIGN_ROOT="${CAMPAIGN_ROOT:-runs/0493x13b_constitutive_transport}"; RUN_ROOT="$CAMPAIGN_ROOT/C_longitudinal"; BIN="${BIN:-build/src_mpcd_base_cuda_q6_resident_livevis_0486}"
PREFLIGHT_ONLY="${PREFLIGHT_ONLY:-0}"; ANALYZE_ONLY="${ANALYZE_ONLY:-0}"; CLEAN_ROOT="${CLEAN_ROOT:-1}"; LIVE_PROGRESS="${LIVE_PROGRESS:-1}"; THREADS="${THREADS:-8}"
FLUIDS="${FLUIDS:-A0,A1,G06,G08,G10,G14}"; AMPLITUDES="${SOUND_AMPLITUDES:-0.02,0.04,0.08}"; SOUND_NX_LIST="${SOUND_NX_LIST:-64}"; NY="${SOUND_NY:-16}"
CELL_SIZE=.00390625; KBT=.125; MASS=1.0; MODE_X=1; SEED=4931321; DUMPS="${SOUND_DUMP_COUNT:-120}"
# Canonical globals needed by the shared 0434 helper; per-run values override them when params are written.
NX=64; GAMMA=20; DT=.002; PARTICLE_MASS="$MASS"; ROTATION_ANGLE=1.5707963267948966; RANDOM_ROTATION_SIGN=true; GRID_SHIFT_ENABLE=true; THERMOSTAT_ENABLE=true; THERMOSTAT_MODE=cell_relative_rescale; THERMOSTAT_EVERY=1; THERMOSTAT_TARGET_KBT="$KBT"; THERMOSTAT_MIN_PARTICLES=3
fluid_spec(){ case "$1" in A0) echo '20|90|0.22687409291590604|historical_reference';; A1) echo '20|120|0.48|A1_reference';; A2) echo '20|150|0.95|transition_probe';; A3) echo '20|165|1.32|mesoscopic_probe';; A4) echo '20|175|1.50|kinetic_probe';; A6) echo '20|175|3.00|extended_flight_probe';; G06) echo '6|120|0.48|low_gamma_A1';; G08) echo '8|120|0.48|low_gamma_A1';; G10) echo '10|120|0.48|low_gamma_A1';; G14) echo '14|120|0.48|low_gamma_A1';; *) return 1;; esac; }
IFS=',' read -ra FARR <<< "$FLUIDS"; for f in "${FARR[@]}";do fluid_spec "$f" >/dev/null||exit 2;done
if [[ "$ANALYZE_ONLY" == 1 ]]; then python3 scripts/analyze_0493x13b_constitutive_transport.py --campaign-root "$CAMPAIGN_ROOT" --repo-root "$ROOT";exit 0;fi
[[ "$CLEAN_ROOT" == 1 ]]&&rm -rf "$RUN_ROOT";mkdir -p "$RUN_ROOT"
manifest="$RUN_ROOT/manifest_0493x13b_C.csv"
python3 - "$manifest" "$FLUIDS" "$AMPLITUDES" "$SOUND_NX_LIST" "$NY" "$CELL_SIZE" "$KBT" "$MASS" <<'PY'
import csv,math,sys
out,fluids,amps,nxs,ny,h,kbt,m=sys.argv[1:];ny=int(ny);h=float(h);kbt=float(kbt);m=float(m)
spec={'A0':(20,90,.22687409291590604,'historical_reference'),'A1':(20,120,.48,'A1_reference'),'A2':(20,150,.95,'transition_probe'),'A3':(20,165,1.32,'mesoscopic_probe'),'A4':(20,175,1.5,'kinetic_probe'),'A6':(20,175,3.0,'extended_flight_probe'),'G06':(6,120,.48,'low_gamma_A1'),'G08':(8,120,.48,'low_gamma_A1'),'G10':(10,120,.48,'low_gamma_A1'),'G14':(14,120,.48,'low_gamma_A1')}
vmean=math.sqrt(math.pi*kbt/(2*m));rows=[]
for f in fluids.split(','):
 g,deg,lam,role=spec[f];dt=lam*h/vmean; reps=max(3,math.ceil(60/g))
 for nx in map(int,nxs.split(',')):
  Lx=nx*h;Ly=ny*h;T=2.4*(nx/64);steps=math.ceil(T/dt);dump=max(1,math.ceil(steps/120));k=2*math.pi/Lx
  for amp in map(float,amps.split(',')):
   tag=f'E{amp:.4f}'.replace('.','p');run=f'{f}/Nx{nx}/{tag}'
   rows.append(dict(fluid=f,role=role,gamma=g,rotationAngleDeg=deg,rotationAngleRad=math.radians(deg),targetLambdaMeanOverCell=lam,dt=dt,cellSize=h,lambdaPhysical=lam*h,Nx=nx,Ny=ny,Lx=Lx,Ly=Ly,wavelengthCells=nx,modeX=1,amplitude=amp,replicates=reps,steps=steps,dumpEvery=dump,physicalTime=steps*dt,kLambda=k*lam*h,runDir=run))
with open(out,'w',newline='') as fp:w=csv.DictWriter(fp,fieldnames=list(rows[0]),lineterminator='\n');w.writeheader();w.writerows(rows)
print(f'[0493x13b-C] manifest={out} groups={len(rows)}')
PY
export OMP_NUM_THREADS="$THREADS" LIVE_PROGRESS; INACTIVE_SLOTS=0; SUMMARY_ROLE_FILTER=fluid; DUMP_ROLE_FILTER=fluid; SPECIES_RESAMPLING_ENABLE=false; WEIGHTED_RESAMPLING_ENABLE_OVERRIDE=false; CUDA_EMPTY_REFILL_ENABLE_OVERRIDE=false; RESAMPLING_THERMAL_RENORMALIZATION_ENABLE=false; RESAMPLING_MASS_GUARD_ENABLE=false; PROJECTION_BACKEND=cuda; PROJECTION_OPERATOR=auto_fv_cg; PROJECTION_MAX_ITERATIONS=100; PROJECTION_TOLERANCE=1e-12; PROJECTION_MOMENTUM_CORRECTION_ENABLE=true; Q6_PROJECTION_STRENGTH=1.0; LIVE_VIS_ENABLE=0; FILTERED_RECORDING_ENABLE=0; RECORD_ENABLE=false; PARTICLE_TYPE_FILTER=-1
suite_defaults_common_0434;suite_compute_derived_0434; [[ "$PREFLIGHT_ONLY" == 1 ]]||suite_ensure_binary_0434
groups_done=0; subruns_done=0
while IFS=, read -r fluid role gamma deg rad lam dt h lamphys nx ny lx ly wc mode amp reps steps dump T klambda runDir;do
 [[ "$fluid" == fluid ]]&&continue; group="$RUN_ROOT/$runDir"; mkdir -p "$group"
 for ((rep=0;rep<reps;++rep));do
  dir="$group/rep$(printf '%02d' "$rep")";mkdir -p "$dir/init" "$dir/output" "$dir/logs" "$dir/params";state="$dir/init/sound_0493x13b.smpcd";meta="$dir/init/sound_0493x13b.meta.json";seed=$((SEED+rep*1009+gamma*100003+nx*101))
  python3 scripts/generate_0493x13b_sound_state_fractional.py --output "$state" --metadata "$meta" --Lx "$lx" --Ly "$ly" --Nx "$nx" --Ny "$ny" --gamma "$gamma" --dt "$dt" --kBT "$KBT" --mass "$MASS" --seed "$seed" --sound-mode-x "$mode" --sound-density-amplitude "$amp"
  SUMMARY_EVERY="$dump";DUMP_STATE_EVERY="$dump"
  cat > "$dir/params/params_0493x13b_C.kv" <<EOF
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
EOF
  GAMMA="$gamma" DT="$dt" KBT="$KBT" PARTICLE_MASS="$MASS" ROTATION_ANGLE="$rad" RANDOM_ROTATION_SIGN=true GRID_SHIFT_ENABLE=true THERMOSTAT_ENABLE=true THERMOSTAT_MODE=cell_relative_rescale THERMOSTAT_EVERY=1 THERMOSTAT_TARGET_KBT="$KBT" THERMOSTAT_MIN_PARTICLES=3 suite_write_common_params_0434 src >> "$dir/params/params_0493x13b_C.kv"
  suite_export_cuda_flags_0434 src periodic;suite_preflight_run_ok_0492 "$dir/params/params_0493x13b_C.kv"
  echo "[0493x13b-C] fluid=$fluid gamma=$gamma angle=$deg lambda/h=$lam Nx=$nx eps=$amp rep=$rep/$reps steps=$steps"
  if [[ "$PREFLIGHT_ONLY" != 1 ]];then set +e;/usr/bin/time -o "$dir/logs/time_0493x13b.txt" -f 'elapsed=%e user=%U sys=%S' "$BIN" "$dir/params/params_0493x13b_C.kv" 2>&1|tee "$dir/logs/run_0493x13b.log";rc=${PIPESTATUS[0]};set -e;[[ $rc -eq 0 ]]||exit "$rc";fi
  subruns_done=$((subruns_done+1))
 done
 groups_done=$((groups_done+1))
done < "$manifest"
if [[ "$PREFLIGHT_ONLY" == 1 ]];then echo "[0493x13b-C] PREFLIGHT PASS groups=$groups_done subruns=$subruns_done";exit 0;fi
python3 scripts/analyze_0493x13b_constitutive_transport.py --campaign-root "$CAMPAIGN_ROOT" --repo-root "$ROOT"
touch "$RUN_ROOT/CAMPAIGN_COMPLETE_0493x13b_C"
echo "[0493x13b-C] CAMPAIGN COMPLETE groups=$groups_done subruns=$subruns_done marker=$RUN_ROOT/CAMPAIGN_COMPLETE_0493x13b_C"
