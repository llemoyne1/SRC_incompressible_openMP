#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$ROOT/scripts/src_mpcd_run_common_0434.sh"
suite_root_cd_0434

TAG=0493x13j
CASE_LABEL=src_transport_calibrator_0493x13j
TOPOLOGY=periodic
CALIBRATION_PATH="${CALIBRATION_PATH:-src}"
case "$CALIBRATION_PATH" in src|src-q6|src-q6-g-f) ;; *) echo "[$TAG] ERROR CALIBRATION_PATH must be src, src-q6 or src-q6-g-f" >&2; exit 2;; esac
suite_validate_path_0434 "$CALIBRATION_PATH"

BIN="${BIN:-build/src_mpcd_base_cuda_q6_resident_livevis_0486}"
RUN_LABEL="${RUN_LABEL:-G08_A120_L072}"
RUN_ROOT="${RUN_ROOT:-runs/0493x13j_transport_${RUN_LABEL}_${CALIBRATION_PATH}}"
STAGES="${STAGES:-S,C,M}"                         # shear, base-SRC acoustics, MSD
SEEDS="${SEEDS:-4932211,4932212,4932213,4932214,4932215,4932216}"
BOOTSTRAP="${BOOTSTRAP:-500}"
ANALYSIS_BOOTSTRAP_SEED="${ANALYSIS_BOOTSTRAP_SEED:-4932299}"

# Fluid point.  DT is derived from lambda/h unless explicitly overridden.
GAMMA="${GAMMA:-8}"
CELL_SIZE="${CELL_SIZE:-0.00390625}"
KBT="${KBT:-0.125}"
PARTICLE_MASS="${PARTICLE_MASS:-1.0}"
ROTATION_ANGLE_DEG="${ROTATION_ANGLE_DEG:-120.0}"
LAMBDA_OVER_H="${LAMBDA_OVER_H:-0.72}"
DT_OVERRIDE="${DT_OVERRIDE:-}"
RANDOM_ROTATION_SIGN="${RANDOM_ROTATION_SIGN:-true}"
GRID_SHIFT_ENABLE="${GRID_SHIFT_ENABLE:-true}"
THERMOSTAT_ENABLE="${THERMOSTAT_ENABLE:-true}"
THERMOSTAT_MODE="${THERMOSTAT_MODE:-cell_relative_rescale}"
THERMOSTAT_EVERY="${THERMOSTAT_EVERY:-1}"
THERMOSTAT_TARGET_KBT="${THERMOSTAT_TARGET_KBT:-$KBT}"
THERMOSTAT_MIN_PARTICLES="${THERMOSTAT_MIN_PARTICLES:-3}"

# Transverse shear qualification.
SHEAR_NX="${SHEAR_NX:-32}"
SHEAR_NY_MAIN="${SHEAR_NY_MAIN:-256}"
SHEAR_NY_LOCAL="${SHEAR_NY_LOCAL:-128}"
SHEAR_MODE_Y="${SHEAR_MODE_Y:-1}"
SHEAR_AMPLITUDE="${SHEAR_AMPLITUDE:-}"
SHEAR_TARGET_EFOLDS="${SHEAR_TARGET_EFOLDS:-1.4}"
SHEAR_DUMP_COUNT="${SHEAR_DUMP_COUNT:-96}"

# Base-SRC damped longitudinal mode.  This remains SRC even when the requested
# effective path is Q6/Q6-G-F; projected-path acoustics are NOT_APPLICABLE_Q6.
RUN_BASE_SRC_SOUND="${RUN_BASE_SRC_SOUND:-1}"
SOUND_NX="${SOUND_NX:-64}"
SOUND_NY="${SOUND_NY:-16}"
SOUND_MODE_X="${SOUND_MODE_X:-1}"
SOUND_DENSITY_AMPLITUDE="${SOUND_DENSITY_AMPLITUDE:-0.08}"
SOUND_STEPS_OVERRIDE="${SOUND_STEPS_OVERRIDE:-}"
SOUND_DUMP_COUNT="${SOUND_DUMP_COUNT:-120}"
SOUND_CS_MIN="${SOUND_CS_MIN:-}"
SOUND_CS_MAX="${SOUND_CS_MAX:-}"

# Path-effective self diffusion.
MSD_NX="${MSD_NX:-64}"
MSD_NY="${MSD_NY:-64}"
MSD_STEPS="${MSD_STEPS:-3000}"
MSD_DUMP_COUNT="${MSD_DUMP_COUNT:-60}"
MSD_SAMPLE_PARTICLES="${MSD_SAMPLE_PARTICLES:-20000}"

# Optional application scales for automatic Re/Ma/Pe in the report.
CHARACTERISTIC_U="${CHARACTERISTIC_U:--1}"
CHARACTERISTIC_L="${CHARACTERISTIC_L:--1}"

PREFLIGHT_ONLY="${PREFLIGHT_ONLY:-0}"
ANALYZE_ONLY="${ANALYZE_ONLY:-0}"
CLEAN_ROOT="${CLEAN_ROOT:-0}"
SKIP_EXISTING="${SKIP_EXISTING:-1}"
PREFLIGHT_FIRST_SEED_ONLY="${PREFLIGHT_FIRST_SEED_ONLY:-1}"
THREADS="${THREADS:-8}"
LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-1}"
LIVE_VIS_EVERY="${LIVE_VIS_EVERY:-1}"
LIVE_VIS_HOLD_ON_EXIT="${LIVE_VIS_HOLD_ON_EXIT:-0}"
FILTERED_RECORDING_ENABLE=0
RECORD_ENABLE=false
PARTICLE_TYPE_FILTER=-1
OVERWRITE_LIVEVIS_CONTROL=1

for dep in \
  scripts/generate_0493x13h_shear_state.py \
  scripts/generate_0493x13h_sound_state_fractional.py \
  scripts/generate_0493w1_src_fluid_calibrator_states.py \
  scripts/analyze_0493w1_src_fluid_calibrator.py \
  scripts/analyze_0493x13h_A_Cdamp_L072.py \
  scripts/analyze_0493x13j_src_transport.py; do
  [[ -f "$dep" ]] || { echo "[$TAG] ERROR missing dependency $dep" >&2; exit 2; }
done

IFS=',' read -ra SEED_ARR <<< "$SEEDS"
(( ${#SEED_ARR[@]} >= 4 )) || { echo "[$TAG] ERROR at least four seeds required" >&2; exit 2; }

readarray -t D < <(python3 - "$CELL_SIZE" "$LAMBDA_OVER_H" "$KBT" "$PARTICLE_MASS" "$ROTATION_ANGLE_DEG" "$DT_OVERRIDE" "$SHEAR_AMPLITUDE" "$SOUND_STEPS_OVERRIDE" "$SOUND_CS_MIN" "$SOUND_CS_MAX" <<'PY'
import math,sys
h,lam,kbt,m,adeg=map(float,sys.argv[1:6]); dto=sys.argv[6]; amp=sys.argv[7]; ss=sys.argv[8]; cslo=sys.argv[9]; cshi=sys.argv[10]
if min(h,lam,kbt,m)<=0: raise SystemExit('positive h, lambda/h, kBT, mass required')
rad=math.radians(adeg); vmean=math.sqrt(math.pi*kbt/(2*m)); dt=float(dto) if dto else lam*h/vmean
uamp=float(amp) if amp else .05*math.sqrt(kbt/.125)
steps=int(ss) if ss else int(math.ceil(379*.72/lam))
cs0=math.sqrt(kbt/m); lo=float(cslo) if cslo else .55*cs0; hi=float(cshi) if cshi else 1.45*cs0
print(f'{rad:.17g}'); print(f'{dt:.17g}'); print(f'{vmean:.17g}'); print(f'{uamp:.17g}'); print(steps); print(f'{lo:.17g}'); print(f'{hi:.17g}')
PY
)
ROTATION_ANGLE="${D[0]}"; DT="${D[1]}"; VMEAN="${D[2]}"; SHEAR_AMPLITUDE="${D[3]}"; SOUND_STEPS="${D[4]}"; SOUND_CS_MIN="${D[5]}"; SOUND_CS_MAX="${D[6]}"

# Common transport settings.  Resampling/refill stay disabled for constitutive calibration.
export OMP_NUM_THREADS="$THREADS" LIVE_PROGRESS
INACTIVE_SLOTS=0; INACTIVE_SLOTS_CELL_FRACTION=0
SUMMARY_ROLE_FILTER=fluid; DUMP_ROLE_FILTER=fluid
SPECIES_RESAMPLING_ENABLE=false; WEIGHTED_RESAMPLING_ENABLE_OVERRIDE=false; CUDA_EMPTY_REFILL_ENABLE_OVERRIDE=false
RESAMPLING_THERMAL_RENORMALIZATION_ENABLE=false; RESAMPLING_MASS_GUARD_ENABLE=false
PROJECTION_BACKEND="${PROJECTION_BACKEND:-cuda}"
PROJECTION_OPERATOR="${PROJECTION_OPERATOR:-auto_fv_cg}"
PROJECTION_MAX_ITERATIONS="${PROJECTION_MAX_ITERATIONS:-800}"
PROJECTION_TOLERANCE="${PROJECTION_TOLERANCE:-1e-5}"
PROJECTION_MOMENTUM_CORRECTION_ENABLE="${PROJECTION_MOMENTUM_CORRECTION_ENABLE:-true}"
Q6_PROJECTION_STRENGTH="${Q6_PROJECTION_STRENGTH:-1.0}"
Q6_GF_HAS_GAS_PHASE="${Q6_GF_HAS_GAS_PHASE:-0}"
Q6_GF_EXTERNAL_SPECIES="${Q6_GF_EXTERNAL_SPECIES:-0}"
Q6_GF_SPECIES_DIAGNOSTICS_ENABLE="${Q6_GF_SPECIES_DIAGNOSTICS_ENABLE:-false}"
Q6_GF_SINGLE_PHASE_TYPE="${Q6_GF_SINGLE_PHASE_TYPE:-0}"
Q6_GF_SINGLE_PHASE_PARTICLE_MASS="${Q6_GF_SINGLE_PHASE_PARTICLE_MASS:-$PARTICLE_MASS}"
BACKGROUND_TYPE=0; U0=0.0; UIN=0.0

# Seed values for common defaults before per-run overrides.
NX="$SHEAR_NX"; NY="$SHEAR_NY_MAIN"; SEED="${SEED_ARR[0]}"
RANDOM_ROTATION_SIGN="$RANDOM_ROTATION_SIGN"; GRID_SHIFT_ENABLE="$GRID_SHIFT_ENABLE"
THERMOSTAT_TARGET_KBT="$THERMOSTAT_TARGET_KBT"
suite_defaults_common_0434
suite_compute_derived_0434
[[ "$ANALYZE_ONLY" == 1 || "$PREFLIGHT_ONLY" == 1 ]] || suite_ensure_binary_0434

BIN_SHA256=MISSING
[[ -f "$BIN" ]] && BIN_SHA256=$(sha256sum "$BIN" | awk '{print $1}')
GIT_HEAD=$(git rev-parse HEAD 2>/dev/null || echo UNKNOWN)
GIT_BRANCH=$(git branch --show-current 2>/dev/null || echo UNKNOWN)

has_stage(){ [[ ",${STAGES}," == *",$1,"* ]]; }
truthy(){ case "${1:-0}" in 1|true|TRUE|yes|YES|on|ON) return 0;; *) return 1;; esac; }

[[ "$CLEAN_ROOT" == 1 && "$ANALYZE_ONLY" != 1 ]] && rm -rf "$RUN_ROOT"
mkdir -p "$RUN_ROOT"/{analysis,audit,shear,sound,msd}

# Machine-readable campaign manifest and human preflight summary.
python3 - "$RUN_ROOT/manifest_0493x13j.json" "$CALIBRATION_PATH" "$GAMMA" "$ROTATION_ANGLE_DEG" "$LAMBDA_OVER_H" "$DT" "$KBT" "$PARTICLE_MASS" "$CELL_SIZE" "$THERMOSTAT_ENABLE" "$THERMOSTAT_MODE" "$THERMOSTAT_EVERY" "$SHEAR_NY_MAIN" "$SHEAR_NY_LOCAL" "$SOUND_CS_MIN" "$SOUND_CS_MAX" "$CHARACTERISTIC_U" "$CHARACTERISTIC_L" "$ANALYSIS_BOOTSTRAP_SEED" "$BIN" "$BIN_SHA256" "$GIT_HEAD" "$GIT_BRANCH" "$SEEDS" <<'PY'
import json,sys
(out,path,gamma,adeg,lam,dt,kbt,mass,h,te,tm,tev,nym,nyl,cslo,cshi,U,L,bs,binary,bsha,head,branch,seeds)=sys.argv[1:]
d={'schema':'0493x13j-v1','calibrationPath':path,'gamma':int(gamma),'alphaDeg':float(adeg),'lambdaOverH':float(lam),'dt':float(dt),'kBT':float(kbt),'mass':float(mass),'cellSize':float(h),
   'thermostatEnable':te,'thermostatMode':tm,'thermostatEvery':int(tev),'shearNyMain':int(nym),'shearNyLocal':int(nyl),'soundCsMin':float(cslo),'soundCsMax':float(cshi),
   'characteristicU':float(U),'characteristicL':float(L),'analysisBootstrapSeed':int(bs),'binary':binary,'binarySha256':bsha,'gitHead':head,'gitBranch':branch,'seeds':[int(x) for x in seeds.split(',') if x]}
open(out,'w').write(json.dumps(d,indent=2,sort_keys=True)+'\n')
PY
{
  echo "campaign=$TAG"
  echo "createdUtc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "gitHead=$GIT_HEAD"; echo "gitBranch=$GIT_BRANCH"; echo "binary=$BIN"; echo "binarySha256=$BIN_SHA256"
  echo "path=$CALIBRATION_PATH"; echo "seeds=$SEEDS"; echo "gamma=$GAMMA"; echo "alphaDeg=$ROTATION_ANGLE_DEG"; echo "lambdaOverH=$LAMBDA_OVER_H"; echo "dt=$DT"; echo "kBT=$KBT"; echo "mass=$PARTICLE_MASS"; echo "cellSize=$CELL_SIZE"
  echo "thermostat=$THERMOSTAT_ENABLE mode=$THERMOSTAT_MODE every=$THERMOSTAT_EVERY target=$THERMOSTAT_TARGET_KBT"
  echo "liveVisEnable=$LIVE_VIS_ENABLE liveVisEvery=$LIVE_VIS_EVERY holdOnExit=$LIVE_VIS_HOLD_ON_EXIT recording=false"
  echo "--- selected q6/projection environment ---"
  env | grep -E '^(Q6_|MPCD_Q6_|PROJECTION_|SPECIES_)' | sort || true
} > "$RUN_ROOT/audit/environment_0493x13j.txt"

echo '===== 0493x13j AUTONOMOUS TRANSPORT CALIBRATOR ====='
echo "path=$CALIBRATION_PATH root=$RUN_ROOT"
echo "fluid gamma=$GAMMA alphaDeg=$ROTATION_ANGLE_DEG h=$CELL_SIZE kBT=$KBT mass=$PARTICLE_MASS lambda/h=$LAMBDA_OVER_H dt=$DT"
echo "seeds=${#SEED_ARR[@]} [$SEEDS] shearAmplitude=$SHEAR_AMPLITUDE"
echo "shear wavelengths=$SHEAR_NY_LOCAL,$SHEAR_NY_MAIN cells; base-src sound=${SOUND_NX}x${SOUND_NY} steps=$SOUND_STEPS epsRho=$SOUND_DENSITY_AMPLITUDE; MSD=${MSD_NX}x${MSD_NY} steps=$MSD_STEPS"
echo "livevis enable=$LIVE_VIS_ENABLE every=$LIVE_VIS_EVERY recording=false hold=$LIVE_VIS_HOLD_ON_EXIT"
if [[ "$CALIBRATION_PATH" != src ]]; then echo "[$TAG] NOTE Q6 path acoustics are NOT_APPLICABLE; stage C measures underlying SRC acoustics only"; fi

# Audit the effective common parameter block, because early placeholder
# assignments are intentionally overridden later by the path writer.
PATH_PREVIEW=$(mktemp)
trap 'rm -f "$PATH_PREVIEW"' EXIT
suite_write_common_params_0434 "$CALIBRATION_PATH" > "$PATH_PREVIEW"
python3 - "$PATH_PREVIEW" "$CALIBRATION_PATH" <<'PY_PATH_AUDIT'
import sys
p,path=sys.argv[1:]; last={}
for raw in open(p):
    s=raw.strip()
    if not s or s.startswith('#') or '=' not in s: continue
    k,v=s.split('=',1); last[k.strip()]=v.strip()
def b(k): return last.get(k,'').lower() in ('true','1','yes','on')
q6=path!='src'; q6gf=path=='src-q6-g-f'; err=[]
if b('projectionEnable') != q6: err.append(f"projectionEnable={last.get('projectionEnable')} expectedQ6={q6}")
if b('resamplingEnable'): err.append('resamplingEnable must be false for constitutive transport calibration')
if q6gf:
    req={'q6ForceProjectionMode':'prestream_single_fused','projectionMomentumCorrectionEnable':'false','speciesRegistryEnable':'true','speciesQ6Enable':'true','speciesQ6Mode':'free_surface_masked'}
    for k,v in req.items():
        if last.get(k,'').lower()!=v.lower(): err.append(f"{k}={last.get(k)!r} expected={v!r}")
print('===== 0493x13j EFFECTIVE PATH AUDIT =====')
for k in ('projectionEnable','projectionBackend','projectionOperator','projectionTolerance','projectionMaxIterations','projectionMomentumCorrectionEnable','resamplingEnable','q6ForceProjectionMode','q6DensityRelaxationTime','speciesRegistryEnable','speciesQ6Enable','speciesQ6Mode'):
    if k in last: print(f'{k}={last[k]}')
print('observableApplicability=nuT:applicable Dself:applicable pathSound:' + ('NOT_APPLICABLE_Q6' if q6 else 'applicable'))
if err:
    [print('[0493x13j] PATH AUDIT ERROR '+e,file=sys.stderr) for e in err]; raise SystemExit(2)
print('[0493x13j] effectivePathAudit=PASS')
PY_PATH_AUDIT
rm -f "$PATH_PREVIEW"; trap - EXIT

# Helpers --------------------------------------------------------------------
write_params(){
  local mode=$1 dir=$2 state=$3 lx=$4 ly=$5 nx=$6 ny=$7 steps=$8 dump=$9 seed=${10}
  mkdir -p "$dir"/{params,output,logs}
  SUMMARY_EVERY="$dump"; DUMP_STATE_EVERY="$dump"; SEED="$seed"; NX="$nx"; NY="$ny"
  GAMMA="$GAMMA"; KBT="$KBT"; PARTICLE_MASS="$PARTICLE_MASS"; ROTATION_ANGLE="$ROTATION_ANGLE"
  THERMOSTAT_TARGET_KBT="$THERMOSTAT_TARGET_KBT"
  cat > "$dir/params/params_0493x13j.kv" <<EOF
inputState = $state
outputDir = $dir/output
Lx = $lx
Ly = $ly
Nx = $nx
Ny = $ny
dt = $DT
nSteps = $steps
bcLeft = periodic
bcRight = periodic
bcBottom = periodic
bcTop = periodic
bcX = periodic
bcY = periodic
openBoundarySegmentsEnable = false
openBoundarySegmentCount = 0
bodyAccelerationX = 0.0
bodyAccelerationY = 0.0
taylorGreenForcingEnable = false
keepMeanFlowEnable = false
speciesRegistryEnable = false
speciesQ6Enable = false
EOF
  suite_write_common_params_0434 "$mode" >> "$dir/params/params_0493x13j.kv"
}

prepare_env(){
  local mode=$1 dir=$2 nx=$3 ny=$4
  NX="$nx"; NY="$ny"; LIVE_VIS_NX="$nx"; LIVE_VIS_NY="$ny"; LIVE_VIS_FIELD=mass
  LIVE_VIS_CONTROL_FILE="$dir/livevis_control_0493x13j.kv"
  suite_export_cuda_flags_0434 "$mode" periodic
  suite_prepare_livevis_control_0434 "$dir" "$mode"
  suite_export_livevis_0434
  suite_preflight_run_ok_0492 "$dir/params/params_0493x13j.kv"
  suite_write_env_file_0434 "$dir/logs/environment_0493x13j.env" "$mode"
}

signature(){
  local mode=$1 dir=$2 state=$3
  {
    echo "path=$mode"; echo "binary=$BIN_SHA256"
    sha256sum "$dir/params/params_0493x13j.kv" "$state"
    env | grep -E '^(Q6_|MPCD_Q6_|PROJECTION_|SPECIES_|MPCD_CUDA_Q6_)' | sort || true
  } | sha256sum | awk '{print $1}'
}

launch(){
  local label=$1 mode=$2 dir=$3 state=$4 marker=$5
  local sig; sig=$(signature "$mode" "$dir" "$state")
  if [[ "$PREFLIGHT_ONLY" != 1 && "$SKIP_EXISTING" == 1 && -f "$marker" && -f "$dir/run_signature.sha256" ]]; then
    local old; old=$(cat "$dir/run_signature.sha256")
    [[ "$old" == "$sig" ]] || { echo "[$TAG] ERROR signature mismatch for completed run $dir" >&2; exit 2; }
    echo "[$TAG] SKIP $label $dir"; return 0
  fi
  echo "$sig" > "$dir/run_signature.sha256"
  if [[ "$PREFLIGHT_ONLY" == 1 ]]; then echo "[$TAG] PREFLIGHT $label $dir"; return 0; fi
  rm -f "$marker"
  echo "[$TAG] RUN $label path=$mode dir=$dir"
  set +e
  /usr/bin/time -o "$dir/logs/time_0493x13j.txt" -f 'elapsed=%e user=%U sys=%S' "$BIN" "$dir/params/params_0493x13j.kv" 2>&1 | tee "$dir/logs/run_0493x13j.log"
  rc=${PIPESTATUS[0]}; set -e
  [[ $rc -eq 0 ]] || { echo "[$TAG] ERROR rc=$rc $dir" >&2; exit "$rc"; }
  touch "$marker"
}

# Manifests ------------------------------------------------------------------
python3 - "$RUN_ROOT" "$SEEDS" "$GAMMA" "$DT" "$KBT" "$CELL_SIZE" "$SHEAR_NX" "$SHEAR_NY_MAIN" "$SHEAR_NY_LOCAL" "$SHEAR_MODE_Y" "$SHEAR_AMPLITUDE" "$SHEAR_TARGET_EFOLDS" "$SHEAR_DUMP_COUNT" "$ROTATION_ANGLE" "$SOUND_NX" "$SOUND_NY" "$SOUND_MODE_X" "$SOUND_DENSITY_AMPLITUDE" "$SOUND_STEPS" "$SOUND_DUMP_COUNT" "$MSD_NX" "$MSD_NY" "$MSD_STEPS" "$MSD_DUMP_COUNT" "$MSD_SAMPLE_PARTICLES" "$PARTICLE_MASS" <<'PY'
import csv,math,sys
(root,seeds,gamma,dt,kbt,h,snx,nym,nyl,mode,amp,efolds,sdumps,arad,cnx,cny,cmode,camp,csteps,cdumps,mnx,mny,msteps,mdumps,msample,mass)=sys.argv[1:]
from pathlib import Path
root=Path(root); sv=[int(x) for x in seeds.split(',') if x]; gamma=int(gamma);dt=float(dt);kbt=float(kbt);h=float(h);snx=int(snx);nym=int(nym);nyl=int(nyl);mode=int(mode);amp=float(amp);efolds=float(efolds);sdumps=int(sdumps);arad=float(arad);mass=float(mass)
fg=(gamma-1+math.exp(-gamma))/gamma; q=fg*(1-math.cos(arad)); nu=kbt*dt/mass*(1/q-.5)+h*h*q/(12*dt)
rows=[]
for ny in (nym,nyl):
  Lx=snx*h; Ly=ny*h; k=2*math.pi*mode/Ly; T=efolds/(nu*k*k); steps=int(math.ceil(T/dt)); dump=max(1,int(math.ceil(steps/sdumps)))
  for seed in sv: rows.append(dict(runDir=f'Ny{ny}/seed{seed}',seed=seed,gamma=gamma,dt=dt,kBT=kbt,cellSize=h,Nx=snx,Ny=ny,Lx=Lx,Ly=Ly,modeY=mode,amplitude=amp,steps=steps,dumpEvery=dump,nuSrdEstimate=nu))
p=root/'shear'/'manifest_shear_0493x13j.csv'; p.parent.mkdir(parents=True,exist_ok=True)
with p.open('w',newline='') as f:w=csv.DictWriter(f,fieldnames=list(rows[0]),lineterminator='\n');w.writeheader();w.writerows(rows)
cnx=int(cnx);cny=int(cny);cmode=int(cmode);csteps=int(csteps);cdumps=int(cdumps); crow=[dict(runDir='base_src',gamma=gamma,dt=dt,kBT=kbt,cellSize=h,Nx=cnx,Ny=cny,Lx=cnx*h,Ly=cny*h,modeX=cmode,amplitude=float(camp),replicates=len(sv),steps=csteps,dumpEvery=max(1,int(math.ceil(csteps/cdumps))))]
p=root/'sound'/'manifest_sound_0493x13j.csv'
with p.open('w',newline='') as f:w=csv.DictWriter(f,fieldnames=list(crow[0]),lineterminator='\n');w.writeheader();w.writerows(crow)
mnx=int(mnx);mny=int(mny);msteps=int(msteps);mdumps=int(mdumps); mrows=[]
for seed in sv:mrows.append(dict(runDir=f'seed{seed}/msd',seed=seed,gamma=gamma,dt=dt,kBT=kbt,cellSize=h,Nx=mnx,Ny=mny,Lx=mnx*h,Ly=mny*h,steps=msteps,dumpEvery=max(1,int(math.ceil(msteps/mdumps))),sampleParticles=int(msample)))
p=root/'msd'/'manifest_msd_0493x13j.csv'
with p.open('w',newline='') as f:w=csv.DictWriter(f,fieldnames=list(mrows[0]),lineterminator='\n');w.writeheader();w.writerows(mrows)
print(f'[0493x13j] derived nuSRD={nu:.9g} shearRuns={len(rows)} soundRuns={len(sv)} msdRuns={len(mrows)}')
PY

if [[ "$ANALYZE_ONLY" != 1 ]]; then
  # S: target-path transverse shear ------------------------------------------
  if has_stage S; then
    while IFS=, read -r runDir seed gamma dt kbt h nx ny lx ly mode amp steps dump nuSrd; do
      [[ "$runDir" == runDir ]] && continue
      if [[ "$PREFLIGHT_ONLY" == 1 && "$PREFLIGHT_FIRST_SEED_ONLY" == 1 && "$seed" != "${SEED_ARR[0]}" ]]; then continue; fi
      dir="$RUN_ROOT/shear/$runDir"; state="$dir/init/shear_0493x13j.smpcd"; mkdir -p "$dir/init"
      python3 scripts/generate_0493x13h_shear_state.py --output "$state" --Lx "$lx" --Ly "$ly" --Nx "$nx" --Ny "$ny" --gamma "$GAMMA" --kBT "$KBT" --mass "$PARTICLE_MASS" --seed "$seed" --mode-y "$mode" --amplitude "$amp"
      write_params "$CALIBRATION_PATH" "$dir" "$state" "$lx" "$ly" "$nx" "$ny" "$steps" "$dump" "$seed"
      prepare_env "$CALIBRATION_PATH" "$dir" "$nx" "$ny"
      launch shear "$CALIBRATION_PATH" "$dir" "$state" "$dir/RUN_COMPLETE_0493x13j_shear"
    done < "$RUN_ROOT/shear/manifest_shear_0493x13j.csv"
  fi

  # C: underlying SRC acoustics ---------------------------------------------
  if has_stage C && truthy "$RUN_BASE_SRC_SOUND"; then
    IFS=, read -r _runDir _gamma _dt _kbt _h _nx _ny _lx _ly _mode _amp _reps _steps _dump < <(tail -n +2 "$RUN_ROOT/sound/manifest_sound_0493x13j.csv" | head -1)
    for ((i=0;i<${#SEED_ARR[@]};++i)); do
      [[ "$PREFLIGHT_ONLY" == 1 && "$PREFLIGHT_FIRST_SEED_ONLY" == 1 && $i -gt 0 ]] && continue
      seed="${SEED_ARR[$i]}"; printf -v rep 'rep%02d' "$i"; dir="$RUN_ROOT/sound/base_src/$rep"; state="$dir/init/sound_0493x13j.smpcd"; meta="$dir/init/sound_0493x13j.meta.json"; mkdir -p "$dir/init"
      python3 scripts/generate_0493x13h_sound_state_fractional.py --output "$state" --metadata "$meta" --Lx "$_lx" --Ly "$_ly" --Nx "$_nx" --Ny "$_ny" --gamma "$GAMMA" --dt "$DT" --kBT "$KBT" --mass "$PARTICLE_MASS" --seed "$seed" --sound-mode-x "$_mode" --sound-density-amplitude "$_amp"
      write_params src "$dir" "$state" "$_lx" "$_ly" "$_nx" "$_ny" "$_steps" "$_dump" "$seed"
      prepare_env src "$dir" "$_nx" "$_ny"
      launch sound src "$dir" "$state" "$dir/RUN_COMPLETE_0493x13j_sound"
    done
  fi

  # M: target-path MSD -------------------------------------------------------
  if has_stage M; then
    while IFS=, read -r runDir seed gamma dt kbt h nx ny lx ly steps dump sample; do
      [[ "$runDir" == runDir ]] && continue
      if [[ "$PREFLIGHT_ONLY" == 1 && "$PREFLIGHT_FIRST_SEED_ONLY" == 1 && "$seed" != "${SEED_ARR[0]}" ]]; then continue; fi
      dir="$RUN_ROOT/msd/$runDir"; state="$dir/init/msd_0493x13j.smpcd"; mkdir -p "$dir/init"
      python3 scripts/generate_0493w1_src_fluid_calibrator_states.py --case msd --output "$state" --Lx "$lx" --Ly "$ly" --Nx "$nx" --Ny "$ny" --gamma "$GAMMA" --dt "$DT" --kBT "$KBT" --mass "$PARTICLE_MASS" --seed "$seed"
      write_params "$CALIBRATION_PATH" "$dir" "$state" "$lx" "$ly" "$nx" "$ny" "$steps" "$dump" "$seed"
      prepare_env "$CALIBRATION_PATH" "$dir" "$nx" "$ny"
      launch msd "$CALIBRATION_PATH" "$dir" "$state" "$dir/RUN_COMPLETE_0493x13j_msd"
    done < "$RUN_ROOT/msd/manifest_msd_0493x13j.csv"
  fi
fi

if [[ "$PREFLIGHT_ONLY" == 1 ]]; then echo "[$TAG] PREFLIGHT PASS; no simulation launched"; exit 0; fi

python3 scripts/analyze_0493x13j_src_transport.py --campaign-root "$RUN_ROOT" --repo-root "$ROOT" --bootstrap "$BOOTSTRAP"
echo "[$TAG] COMPLETE report=$RUN_ROOT/analysis/README_RESULTS_0493x13j.md"
