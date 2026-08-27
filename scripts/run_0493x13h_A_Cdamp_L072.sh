#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$ROOT/scripts/src_mpcd_run_common_0434.sh"
suite_root_cd_0434
CASE_LABEL=src_G08L072_Cdamp_0493x13h
CAMPAIGN_ROOT="${CAMPAIGN_ROOT:-runs/0493x13h_L072_qualification}"
RUN_ROOT="$CAMPAIGN_ROOT/A_Cdamp"
BIN="${BIN:-build/src_mpcd_base_cuda_q6_resident_livevis_0486}"
PREFLIGHT_ONLY="${PREFLIGHT_ONLY:-0}"; ANALYZE_ONLY="${ANALYZE_ONLY:-0}"; CLEAN_ROOT="${CLEAN_ROOT:-0}"; SKIP_EXISTING="${SKIP_EXISTING:-1}"
LIVE_PROGRESS="${LIVE_PROGRESS:-1}"; THREADS="${THREADS:-8}"
AMPLITUDES="${AMPLITUDES:-0.04,0.08}"; REPLICATES="${REPLICATES:-30}"; NX_SOUND="${NX_SOUND:-64}"; NY_SOUND="${NY_SOUND:-16}"
PHYSICAL_TIME_BASE="${PHYSICAL_TIME_BASE:-2.4}"; DUMP_COUNT="${DUMP_COUNT:-120}"; SEED_BASE="${SEED_BASE:-4931811}"; PREFLIGHT_FIRST_REP_ONLY="${PREFLIGHT_FIRST_REP_ONLY:-1}"
BOOTSTRAP="${BOOTSTRAP:-500}"
GAMMA_FIXED=8; CELL_SIZE="0.00390625"; KBT="0.125"; MASS="1.0"; ALPHA_DEG="120.0"; ALPHA_RAD="2.0943951023931953"; LAMBDA_OVER_H="0.72"
for dep in scripts/generate_0493x13h_sound_state_fractional.py scripts/analyze_0493x13h_A_Cdamp_L072.py scripts/analyze_0493w1_src_fluid_calibrator.py; do [[ -f "$dep" ]] || { echo "[0493x13h-A] missing $dep" >&2; exit 2; }; done
if [[ "$ANALYZE_ONLY" == 1 ]]; then python3 scripts/analyze_0493x13h_A_Cdamp_L072.py --campaign-root "$CAMPAIGN_ROOT" --repo-root "$ROOT" --bootstrap "$BOOTSTRAP" --validate-local; exit 0; fi
[[ "$CLEAN_ROOT" == 1 ]] && rm -rf "$RUN_ROOT"; mkdir -p "$RUN_ROOT"; rm -f "$RUN_ROOT/CAMPAIGN_COMPLETE_0493x13h_A_Cdamp"
manifest="$RUN_ROOT/manifest_0493x13h_A_Cdamp.csv"
python3 - "$manifest" "$AMPLITUDES" "$REPLICATES" "$NX_SOUND" "$NY_SOUND" "$CELL_SIZE" "$KBT" "$MASS" "$ALPHA_DEG" "$LAMBDA_OVER_H" "$PHYSICAL_TIME_BASE" "$DUMP_COUNT" <<'PY'
import csv,math,sys
out,amps,reps,nx,ny,h,kbt,mass,adeg,lam,Tbase,dumps=sys.argv[1:]
reps=int(reps);nx=int(nx);ny=int(ny);h=float(h);kbt=float(kbt);mass=float(mass);adeg=float(adeg);lam=float(lam);Tbase=float(Tbase);dumps=int(dumps);gamma=8
vmean=math.sqrt(math.pi*kbt/(2*mass));dt=lam*h/vmean;Lx=nx*h;Ly=ny*h;steps=math.ceil(Tbase/dt);dump=max(1,math.ceil(steps/dumps));k=2*math.pi/Lx;rows=[]
for amp in map(float,amps.split(',')):
    tag=f'E{amp:.4f}'.replace('.','p'); run=f'G08L072/Nx{nx}/{tag}'
    rows.append(dict(fluid='G08L072',role='G08_alpha120_lambda072',gamma=gamma,rotationAngleDeg=adeg,rotationAngleRad=math.radians(adeg),targetLambdaMeanOverCell=lam,dt=dt,cellSize=h,lambdaPhysical=lam*h,Nx=nx,Ny=ny,Lx=Lx,Ly=Ly,wavelengthCells=nx,modeX=1,amplitude=amp,replicates=reps,steps=steps,dumpEvery=dump,physicalTime=steps*dt,kLambda=k*lam*h,runDir=run,estimatedParticleStepsPerRep=nx*ny*gamma*steps,estimatedParticleStepsGroup=nx*ny*gamma*steps*reps))
with open(out,'w',newline='') as f:
    w=csv.DictWriter(f,fieldnames=list(rows[0]),lineterminator='\n');w.writeheader();w.writerows(rows)
print(f'[0493x13h-A] groups={len(rows)} reps/group={reps} dt={dt:.12g} steps={steps} totalParticleSteps={sum(r["estimatedParticleStepsGroup"] for r in rows)}')
PY
NX="$NX_SOUND"; NY="$NY_SOUND"; GAMMA="$GAMMA_FIXED"; DT=.0063471328149122585; PARTICLE_MASS="$MASS"; ROTATION_ANGLE="$ALPHA_RAD"; RANDOM_ROTATION_SIGN=true; GRID_SHIFT_ENABLE=true; THERMOSTAT_ENABLE=true; THERMOSTAT_MODE=cell_relative_rescale; THERMOSTAT_EVERY=1; THERMOSTAT_TARGET_KBT="$KBT"; THERMOSTAT_MIN_PARTICLES=3; SEED="$SEED_BASE"
export OMP_NUM_THREADS="$THREADS" LIVE_PROGRESS
INACTIVE_SLOTS=0; SUMMARY_ROLE_FILTER=fluid; DUMP_ROLE_FILTER=fluid; SPECIES_RESAMPLING_ENABLE=false; WEIGHTED_RESAMPLING_ENABLE_OVERRIDE=false; CUDA_EMPTY_REFILL_ENABLE_OVERRIDE=false; RESAMPLING_THERMAL_RENORMALIZATION_ENABLE=false; RESAMPLING_MASS_GUARD_ENABLE=false; PROJECTION_BACKEND=cuda; PROJECTION_OPERATOR=auto_fv_cg; PROJECTION_MAX_ITERATIONS=100; PROJECTION_TOLERANCE=1e-12; PROJECTION_MOMENTUM_CORRECTION_ENABLE=true; Q6_PROJECTION_STRENGTH=1.0; LIVE_VIS_ENABLE=0; FILTERED_RECORDING_ENABLE=0; RECORD_ENABLE=false; PARTICLE_TYPE_FILTER=-1
suite_defaults_common_0434; suite_compute_derived_0434; [[ "$PREFLIGHT_ONLY" == 1 ]] || suite_ensure_binary_0434
new=0;skip=0;pf=0
while IFS=, read -r fluid role gamma deg rad lam dt h lamphys nx ny lx ly wc mode amp reps steps dump T klambda runDir psRep psGroup; do
  [[ "$fluid" == fluid ]] && continue
  for ((rep=0; rep<reps; ++rep)); do
    [[ "$PREFLIGHT_ONLY" == 1 && "$PREFLIGHT_FIRST_REP_ONLY" == 1 && "$rep" != 0 ]] && continue
    repTag=$(printf 'rep%02d' "$rep"); dir="$RUN_ROOT/$runDir/$repTag"; marker="$dir/RUN_COMPLETE_0493x13h_A_Cdamp"
    if [[ "$PREFLIGHT_ONLY" != 1 && "$SKIP_EXISTING" == 1 && -f "$marker" ]]; then skip=$((skip+1)); continue; fi
    mkdir -p "$dir/init" "$dir/output" "$dir/logs" "$dir/params"; state="$dir/init/sound_0493x13h.smpcd"; meta="$dir/init/sound_0493x13h.meta.json"
    seed=$((SEED_BASE + rep*1009 + 800003 + nx*101))
    python3 scripts/generate_0493x13h_sound_state_fractional.py --output "$state" --metadata "$meta" --Lx "$lx" --Ly "$ly" --Nx "$nx" --Ny "$ny" --gamma "$gamma" --dt "$dt" --kBT "$KBT" --mass "$MASS" --seed "$seed" --sound-mode-x "$mode" --sound-density-amplitude "$amp"
    SUMMARY_EVERY="$dump"; DUMP_STATE_EVERY="$dump"
    cat > "$dir/params/params_0493x13h_A.kv" <<PARAMS
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
    GAMMA="$gamma" DT="$dt" KBT="$KBT" PARTICLE_MASS="$MASS" ROTATION_ANGLE="$rad" RANDOM_ROTATION_SIGN=true GRID_SHIFT_ENABLE=true THERMOSTAT_ENABLE=true THERMOSTAT_MODE=cell_relative_rescale THERMOSTAT_EVERY=1 THERMOSTAT_TARGET_KBT="$KBT" THERMOSTAT_MIN_PARTICLES=3 SEED="$seed" suite_write_common_params_0434 src >> "$dir/params/params_0493x13h_A.kv"
    suite_export_cuda_flags_0434 src periodic; suite_preflight_run_ok_0492 "$dir/params/params_0493x13h_A.kv"
    echo "[0493x13h-A] eps=$amp rep=$rep/$reps seed=$seed steps=$steps"
    if [[ "$PREFLIGHT_ONLY" == 1 ]]; then pf=$((pf+1)); continue; fi
    rm -f "$marker"; set +e; /usr/bin/time -o "$dir/logs/time_0493x13h_A.txt" -f 'elapsed=%e user=%U sys=%S' "$BIN" "$dir/params/params_0493x13h_A.kv" 2>&1 | tee "$dir/logs/run_0493x13h_A.log"; rc=${PIPESTATUS[0]}; set -e; [[ $rc -eq 0 ]] || exit "$rc"; touch "$marker"; new=$((new+1))
  done
done < "$manifest"
if [[ "$PREFLIGHT_ONLY" == 1 ]]; then echo "[0493x13h-A] PREFLIGHT PASS checked=$pf"; exit 0; fi
python3 scripts/analyze_0493x13h_A_Cdamp_L072.py --campaign-root "$CAMPAIGN_ROOT" --repo-root "$ROOT" --bootstrap "$BOOTSTRAP" --validate-local
touch "$RUN_ROOT/CAMPAIGN_COMPLETE_0493x13h_A_Cdamp"; echo "[0493x13h-A] COMPLETE new=$new skipped=$skip"
