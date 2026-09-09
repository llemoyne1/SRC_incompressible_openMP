#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$ROOT/scripts/src_mpcd_run_common_0434.sh"
suite_root_cd_0434

CASE_LABEL=src_kbt_scaling_0493x13i
CAMPAIGN_ROOT="${CAMPAIGN_ROOT:-runs/0493x13i_kbt_scaling}"
BIN="${BIN:-build/src_mpcd_base_cuda_q6_resident_livevis_0486}"
STAGES="${STAGES:-S,C,M}"   # S=shear nuT, C=longitudinal cs/nuL, M=MSD Dself

PREFLIGHT_ONLY="${PREFLIGHT_ONLY:-0}"
ANALYZE_ONLY="${ANALYZE_ONLY:-0}"
CLEAN_ROOT="${CLEAN_ROOT:-0}"
SKIP_EXISTING="${SKIP_EXISTING:-1}"
PREFLIGHT_FIRST_SEED_ONLY="${PREFLIGHT_FIRST_SEED_ONLY:-1}"
LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
THREADS="${THREADS:-8}"

KBT_VALUES="${KBT_VALUES:-0.03125,0.125,0.5}"
SEEDS="${SEEDS:-4932111,4932112,4932113,4932114,4932115,4932116}"
LOCAL_SEED_COUNT="${LOCAL_SEED_COUNT:-4}"
BOOTSTRAP="${BOOTSTRAP:-1000}"
SOUND_BOOTSTRAP="${SOUND_BOOTSTRAP:-500}"

GAMMA_FIXED="${GAMMA_FIXED:-8}"
CELL_SIZE="${CELL_SIZE:-0.00390625}"
MASS="${MASS:-1.0}"
ALPHA_DEG="${ALPHA_DEG:-120.0}"
ALPHA_RAD="${ALPHA_RAD:-2.0943951023931953}"
LAMBDA_OVER_H="${LAMBDA_OVER_H:-0.72}"
REFERENCE_KBT="${REFERENCE_KBT:-0.125}"
REFERENCE_SHEAR_AMPLITUDE="${REFERENCE_SHEAR_AMPLITUDE:-0.05}"

SHEAR_NX="${SHEAR_NX:-32}"
SHEAR_NY_MAIN="${SHEAR_NY_MAIN:-256}"
SHEAR_NY_LOCAL="${SHEAR_NY_LOCAL:-128}"
SHEAR_TARGET_EFOLDS="${SHEAR_TARGET_EFOLDS:-1.4}"
SHEAR_DUMP_COUNT="${SHEAR_DUMP_COUNT:-96}"

SOUND_NX="${SOUND_NX:-64}"
SOUND_NY="${SOUND_NY:-16}"
SOUND_MODE_X="${SOUND_MODE_X:-1}"
SOUND_DENSITY_AMPLITUDE="${SOUND_DENSITY_AMPLITUDE:-0.08}"
# 0493x13h reference: ceil(2.4/dt0)=379. Keep the same number of steps at all kBT
# so acoustic time, damping and sampling remain dimensionlessly similar.
SOUND_STEPS="${SOUND_STEPS:-379}"
SOUND_DUMP_COUNT="${SOUND_DUMP_COUNT:-120}"

MSD_NX="${MSD_NX:-64}"
MSD_NY="${MSD_NY:-64}"
MSD_STEPS="${MSD_STEPS:-3000}"
MSD_DUMP_COUNT="${MSD_DUMP_COUNT:-60}"
MSD_SAMPLE_PARTICLES="${MSD_SAMPLE_PARTICLES:-20000}"

# Requested campaign convention. Recording remains OFF: state dumps are the calibrator data.
# HOLD_ON_EXIT must be 0 because this is a many-run batch campaign.
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
  scripts/analyze_0493x13b_constitutive_transport.py \
  scripts/analyze_0493x13h_A_Cdamp_L072.py \
  scripts/analyze_0493w1_src_fluid_calibrator.py \
  scripts/analyze_0493x13i_kbt_scaling.py; do
  [[ -f "$dep" ]] || { echo "[0493x13i] missing dependency: $dep" >&2; exit 2; }
done

IFS=',' read -ra KBT_ARR <<< "$KBT_VALUES"
IFS=',' read -ra SEED_ARR <<< "$SEEDS"
[[ ${#KBT_ARR[@]} -ge 3 ]] || { echo '[0493x13i] need at least three KBT values' >&2; exit 2; }
[[ ${#SEED_ARR[@]} -ge 4 ]] || { echo '[0493x13i] need at least four seeds' >&2; exit 2; }
(( LOCAL_SEED_COUNT >= 1 && LOCAL_SEED_COUNT <= ${#SEED_ARR[@]} )) || { echo '[0493x13i] invalid LOCAL_SEED_COUNT' >&2; exit 2; }

echo '===== 0493x13i kBT SCALE CAMPAIGN ====='
echo "physics gamma=$GAMMA_FIXED alphaDeg=$ALPHA_DEG h=$CELL_SIZE lambda/h=$LAMBDA_OVER_H mass=$MASS"
echo "kBT values=$KBT_VALUES seeds=$SEEDS"
echo "shear main Ny=$SHEAR_NY_MAIN seeds=${#SEED_ARR[@]}; locality Ny=$SHEAR_NY_LOCAL seeds=$LOCAL_SEED_COUNT; U0 scales as sqrt(kBT)"
echo "sound grid=${SOUND_NX}x${SOUND_NY} epsRho=$SOUND_DENSITY_AMPLITUDE steps=$SOUND_STEPS reps=${#SEED_ARR[@]}"
echo "MSD grid=${MSD_NX}x${MSD_NY} steps=$MSD_STEPS reps=${#SEED_ARR[@]} sample=$MSD_SAMPLE_PARTICLES"
echo "livevis enable=$LIVE_VIS_ENABLE liveEvery=$LIVE_VIS_EVERY recordEnable=false holdOnExit=$LIVE_VIS_HOLD_ON_EXIT"
python3 - "$KBT_VALUES" "$CELL_SIZE" "$LAMBDA_OVER_H" "$MASS" "$REFERENCE_KBT" "$REFERENCE_SHEAR_AMPLITUDE" <<'PY_SCALE'
import math,sys
vals=[float(x) for x in sys.argv[1].split(',') if x]
h,lam,m,kref,uref=map(float,sys.argv[2:])
for kbt in vals:
    dt=lam*h/math.sqrt(math.pi*kbt/(2*m)); scale=math.sqrt(kbt/kref)
    print(f'[0493x13i] scale kBT={kbt:.8g} dt={dt:.17g} sqrtScale={scale:.8g} shearU0={uref*scale:.8g}')
PY_SCALE
echo "[0493x13i] planned runs: shear=$(( ${#KBT_ARR[@]} * (${#SEED_ARR[@]} + LOCAL_SEED_COUNT) )) sound=$(( ${#KBT_ARR[@]} * ${#SEED_ARR[@]} )) msd=$(( ${#KBT_ARR[@]} * ${#SEED_ARR[@]} ))"

[[ "$CLEAN_ROOT" == 1 && "$ANALYZE_ONLY" != 1 ]] && rm -rf "$CAMPAIGN_ROOT"
mkdir -p "$CAMPAIGN_ROOT"/{audit,analysis}

if [[ "$ANALYZE_ONLY" != 1 ]]; then
  {
    echo "campaign=0493x13i_kbt_scaling"
    echo "createdUtc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "gitHead=$(git rev-parse HEAD 2>/dev/null || echo UNKNOWN)"
    echo "gitBranch=$(git branch --show-current 2>/dev/null || echo UNKNOWN)"
    echo "binary=$BIN"
    if [[ -f "$BIN" ]]; then echo "binarySha256=$(sha256sum "$BIN" | awk '{print $1}')"; else echo "binarySha256=MISSING"; fi
    echo "kBTValues=$KBT_VALUES"
    echo "seeds=$SEEDS"
    echo "gamma=$GAMMA_FIXED"
    echo "alphaDeg=$ALPHA_DEG"
    echo "lambdaOverH=$LAMBDA_OVER_H"
    echo "cellSize=$CELL_SIZE"
    echo "liveVisEnable=$LIVE_VIS_ENABLE"
    echo "liveVisEvery=$LIVE_VIS_EVERY"
  } > "$CAMPAIGN_ROOT/audit/environment_0493x13i.txt"
fi

export OMP_NUM_THREADS="$THREADS" LIVE_PROGRESS
INACTIVE_SLOTS=0
SUMMARY_ROLE_FILTER=fluid
DUMP_ROLE_FILTER=fluid
SPECIES_RESAMPLING_ENABLE=false
WEIGHTED_RESAMPLING_ENABLE_OVERRIDE=false
CUDA_EMPTY_REFILL_ENABLE_OVERRIDE=false
RESAMPLING_THERMAL_RENORMALIZATION_ENABLE=false
RESAMPLING_MASS_GUARD_ENABLE=false
PROJECTION_BACKEND=cuda
PROJECTION_OPERATOR=auto_fv_cg
PROJECTION_MAX_ITERATIONS=100
PROJECTION_TOLERANCE=1e-12
PROJECTION_MOMENTUM_CORRECTION_ENABLE=true
Q6_PROJECTION_STRENGTH=1.0
NX="$SHEAR_NX"; NY="$SHEAR_NY_MAIN"; GAMMA="$GAMMA_FIXED"; KBT="$REFERENCE_KBT"; DT=0.0063471328149122585
PARTICLE_MASS="$MASS"; ROTATION_ANGLE="$ALPHA_RAD"; RANDOM_ROTATION_SIGN=true; GRID_SHIFT_ENABLE=true
THERMOSTAT_ENABLE=true; THERMOSTAT_MODE=cell_relative_rescale; THERMOSTAT_EVERY=1; THERMOSTAT_TARGET_KBT="$REFERENCE_KBT"; THERMOSTAT_MIN_PARTICLES=3
SEED="${SEED_ARR[0]}"
suite_defaults_common_0434
suite_compute_derived_0434
[[ "$PREFLIGHT_ONLY" == 1 || "$ANALYZE_ONLY" == 1 ]] || suite_ensure_binary_0434

LAMBDA_PHYSICAL=$(python3 -c 'import sys;print(float(sys.argv[1])*float(sys.argv[2]))' "$CELL_SIZE" "$LAMBDA_OVER_H")
BIN_SHA256=MISSING
[[ -f "$BIN" ]] && BIN_SHA256=$(sha256sum "$BIN" | awk '{print $1}')

calc_dt() {
  python3 - "$1" "$CELL_SIZE" "$LAMBDA_OVER_H" "$MASS" <<'PY'
import math,sys
kbt,h,lam,m=map(float,sys.argv[1:])
print(f"{lam*h/math.sqrt(math.pi*kbt/(2*m)):.17g}")
PY
}

kbt_tag() {
  python3 - "$1" <<'PY'
import sys
x=float(sys.argv[1])
s=(f"{x:.8g}").replace('.','p').replace('-','m').replace('+','')
print('K'+s)
PY
}

csv_join_first_n() {
  local n=$1; shift
  local out="" i=0 x
  for x in "$@"; do
    (( i >= n )) && break
    [[ -n "$out" ]] && out+=','
    out+="$x"; i=$((i+1))
  done
  printf '%s\n' "$out"
}

write_src_params() {
  local dir=$1 state=$2 lx=$3 ly=$4 nx=$5 ny=$6 dt=$7 kbt=$8 seed=$9 steps=${10} dump=${11}
  mkdir -p "$dir"/{params,output,logs}
  SUMMARY_EVERY="$dump"; DUMP_STATE_EVERY="$dump"
  GAMMA="$GAMMA_FIXED"; DT="$dt"; KBT="$kbt"; PARTICLE_MASS="$MASS"; ROTATION_ANGLE="$ALPHA_RAD"
  RANDOM_ROTATION_SIGN=true; GRID_SHIFT_ENABLE=true; THERMOSTAT_ENABLE=true; THERMOSTAT_MODE=cell_relative_rescale
  THERMOSTAT_EVERY=1; THERMOSTAT_TARGET_KBT="$kbt"; THERMOSTAT_MIN_PARTICLES=3; SEED="$seed"
  cat > "$dir/params/params_0493x13i.kv" <<PARAMS
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
  suite_write_common_params_0434 src >> "$dir/params/params_0493x13i.kv"
}

prepare_run_environment() {
  local dir=$1 nx=$2 ny=$3 field=$4
  NX="$nx"; NY="$ny"; LIVE_VIS_NX="$nx"; LIVE_VIS_NY="$ny"; LIVE_VIS_FIELD="$field"
  LIVE_VIS_CONTROL_FILE="$dir/livevis_control_0493x13i.kv"
  suite_export_cuda_flags_0434 src periodic
  suite_prepare_livevis_control_0434 "$dir" src
  suite_export_livevis_0434
  suite_preflight_run_ok_0492 "$dir/params/params_0493x13i.kv"
}

signature_value() {
  local payload=$1
  printf '%s\nbinary=%s\n' "$payload" "$BIN_SHA256" | sha256sum | awk '{print $1}'
}

should_skip() {
  local dir=$1 expected=$2 marker=$3
  if [[ "$SKIP_EXISTING" == 1 && -f "$marker" && -f "$dir/run_signature.sha256" ]]; then
    local got; got=$(cat "$dir/run_signature.sha256")
    if [[ "$got" == "$expected" ]]; then return 0; fi
    echo "[0493x13i] ERROR completed run has different signature: $dir" >&2
    echo "[0493x13i] expected=$expected found=$got; use a new CAMPAIGN_ROOT or CLEAN_ROOT=1" >&2
    exit 2
  fi
  return 1
}

launch() {
  local dir=$1 label=$2 signature=$3
  local marker="$dir/RUN_COMPLETE_0493x13i_${label}"
  if [[ "$PREFLIGHT_ONLY" != 1 ]] && should_skip "$dir" "$signature" "$marker"; then
    echo "[0493x13i] SKIP $label $dir"
    return 0
  fi
  echo "$signature" > "$dir/run_signature.sha256"
  if [[ "$PREFLIGHT_ONLY" == 1 ]]; then
    echo "[0493x13i] PREFLIGHT stage=$label dir=$dir"
    return 0
  fi
  echo "[0493x13i] RUN stage=$label dir=$dir"
  rm -f "$marker"
  set +e
  /usr/bin/time -o "$dir/logs/time_0493x13i.txt" -f 'elapsed=%e user=%U sys=%S' \
    "$BIN" "$dir/params/params_0493x13i.kv" 2>&1 | tee "$dir/logs/run_0493x13i.log"
  rc=${PIPESTATUS[0]}
  set -e
  [[ $rc -eq 0 ]] || { echo "[0493x13i] ERROR stage=$label rc=$rc dir=$dir" >&2; exit "$rc"; }
  touch "$marker"
}

run_shear() {
  local root="$CAMPAIGN_ROOT/S_shear"; mkdir -p "$root"
  local manifest="$root/manifest_0493x13i_shear.csv"
  echo 'kBT,kBTScale,dt,gamma,rotationAngleDeg,rotationAngleRad,targetLambdaMeanOverCell,cellSize,lambdaPhysical,Nx,Ny,Lx,Ly,wavelengthCells,modeY,amplitude,expectedSeeds,seed,steps,dumpEvery,physicalTime,targetEfolds,kLambda,viscositySRDKinematic,runDir' > "$manifest"
  local kbt tag dt scale amp ny nseed seed lx ly nu steps dump T klambda runDir dir sig first_seed
  first_seed="${SEED_ARR[0]}"
  for kbt in "${KBT_ARR[@]}"; do
    tag=$(kbt_tag "$kbt"); dt=$(calc_dt "$kbt")
    scale=$(python3 - "$kbt" "$REFERENCE_KBT" <<'PY'
import math,sys
print(f"{math.sqrt(float(sys.argv[1])/float(sys.argv[2])):.17g}")
PY
)
    amp=$(python3 - "$REFERENCE_SHEAR_AMPLITUDE" "$scale" <<'PY'
import sys
print(f"{float(sys.argv[1])*float(sys.argv[2]):.17g}")
PY
)
    for ny in "$SHEAR_NY_MAIN" "$SHEAR_NY_LOCAL"; do
      nseed=${#SEED_ARR[@]}; [[ "$ny" == "$SHEAR_NY_LOCAL" ]] && nseed="$LOCAL_SEED_COUNT"
      read -r lx ly nu steps dump T klambda < <(python3 - "$kbt" "$dt" "$ny" "$CELL_SIZE" "$GAMMA_FIXED" "$ALPHA_DEG" "$SHEAR_NX" "$SHEAR_TARGET_EFOLDS" "$SHEAR_DUMP_COUNT" "$LAMBDA_OVER_H" <<'PY'
import math,sys
kbt=float(sys.argv[1]); dt=float(sys.argv[2]); ny=int(sys.argv[3]); h=float(sys.argv[4])
gamma=int(sys.argv[5]); alpha=math.radians(float(sys.argv[6])); nx=int(sys.argv[7]); ef=float(sys.argv[8]); dumps=int(sys.argv[9]); lam=float(sys.argv[10])
fg=(gamma-1+math.exp(-gamma))/gamma; q=fg*(1-math.cos(alpha))
nu=kbt*dt*(1/q-.5)+h*h*q/(12*dt)
lx=nx*h; ly=ny*h; k=2*math.pi/ly; T=ef/(nu*k*k); steps=math.ceil(T/dt); dump=max(1,math.ceil(steps/dumps))
print(f'{lx:.17g} {ly:.17g} {nu:.17g} {steps} {dump} {steps*dt:.17g} {k*lam*h:.17g}')
PY
)
      for ((i=0;i<nseed;++i)); do
        seed="${SEED_ARR[$i]}"; runDir="$tag/Ny${ny}/seed${seed}"; dir="$root/$runDir"
        echo "$kbt,$scale,$dt,$GAMMA_FIXED,$ALPHA_DEG,$ALPHA_RAD,$LAMBDA_OVER_H,$CELL_SIZE,$LAMBDA_PHYSICAL,$SHEAR_NX,$ny,$lx,$ly,$ny,1,$amp,$nseed,$seed,$steps,$dump,$T,$SHEAR_TARGET_EFOLDS,$klambda,$nu,$runDir" >> "$manifest"
        if [[ "$ANALYZE_ONLY" == 1 ]]; then continue; fi
        if [[ "$PREFLIGHT_ONLY" == 1 && "$PREFLIGHT_FIRST_SEED_ONLY" == 1 && "$seed" != "$first_seed" ]]; then continue; fi
        mkdir -p "$dir/init"; state="$dir/init/shear_0493x13i.smpcd"
        if [[ "$PREFLIGHT_ONLY" != 1 ]]; then
          python3 scripts/generate_0493x13h_shear_state.py --output "$state" --Lx "$lx" --Ly "$ly" --Nx "$SHEAR_NX" --Ny "$ny" --gamma "$GAMMA_FIXED" --kBT "$kbt" --mass "$MASS" --seed "$seed" --mode-y 1 --amplitude "$amp"
        fi
        write_src_params "$dir" "$state" "$lx" "$ly" "$SHEAR_NX" "$ny" "$dt" "$kbt" "$seed" "$steps" "$dump"
        prepare_run_environment "$dir" "$SHEAR_NX" "$ny" ux
        sig=$(signature_value "stage=shear kBT=$kbt dt=$dt gamma=$GAMMA_FIXED alpha=$ALPHA_RAD lambdaOverH=$LAMBDA_OVER_H nx=$SHEAR_NX ny=$ny amp=$amp seed=$seed steps=$steps dump=$dump")
        launch "$dir" shear "$sig"
      done
    done
  done
}

run_sound() {
  local root="$CAMPAIGN_ROOT/A_Cdamp"; mkdir -p "$root"
  local manifest="$root/manifest_0493x13h_A_Cdamp.csv"
  echo 'fluid,kBT,kBTScale,gamma,rotationAngleDeg,rotationAngleRad,targetLambdaMeanOverCell,dt,cellSize,lambdaPhysical,Nx,Ny,Lx,Ly,wavelengthCells,modeX,amplitude,replicates,steps,dumpEvery,physicalTime,kLambda,runDir' > "$manifest"
  local kbt tag dt scale lx ly dump klambda runDir dir seed state meta sig first_seed
  first_seed="${SEED_ARR[0]}"
  lx=$(python3 -c 'import sys;print(int(sys.argv[1])*float(sys.argv[2]))' "$SOUND_NX" "$CELL_SIZE")
  ly=$(python3 -c 'import sys;print(int(sys.argv[1])*float(sys.argv[2]))' "$SOUND_NY" "$CELL_SIZE")
  dump=$(( (SOUND_STEPS + SOUND_DUMP_COUNT - 1) / SOUND_DUMP_COUNT )); (( dump < 1 )) && dump=1
  for kbt in "${KBT_ARR[@]}"; do
    tag=$(kbt_tag "$kbt"); dt=$(calc_dt "$kbt")
    scale=$(python3 -c 'import math,sys;print(math.sqrt(float(sys.argv[1])/float(sys.argv[2])))' "$kbt" "$REFERENCE_KBT")
    klambda=$(python3 - "$lx" "$SOUND_MODE_X" "$CELL_SIZE" "$LAMBDA_OVER_H" <<'PY'
import math,sys
Lx=float(sys.argv[1]);mode=int(sys.argv[2]);h=float(sys.argv[3]);lam=float(sys.argv[4]);print(2*math.pi*mode/Lx*lam*h)
PY
)
    runDir="$tag"; echo "$tag,$kbt,$scale,$GAMMA_FIXED,$ALPHA_DEG,$ALPHA_RAD,$LAMBDA_OVER_H,$dt,$CELL_SIZE,$LAMBDA_PHYSICAL,$SOUND_NX,$SOUND_NY,$lx,$ly,$SOUND_NX,$SOUND_MODE_X,$SOUND_DENSITY_AMPLITUDE,${#SEED_ARR[@]},$SOUND_STEPS,$dump,$(python3 -c 'import sys;print(int(sys.argv[1])*float(sys.argv[2]))' "$SOUND_STEPS" "$dt"),$klambda,$runDir" >> "$manifest"
    for ((i=0;i<${#SEED_ARR[@]};++i)); do
      seed="${SEED_ARR[$i]}"; printf -v repTag 'rep%02d' "$i"; dir="$root/$runDir/$repTag"
      if [[ "$ANALYZE_ONLY" == 1 ]]; then continue; fi
      if [[ "$PREFLIGHT_ONLY" == 1 && "$PREFLIGHT_FIRST_SEED_ONLY" == 1 && "$seed" != "$first_seed" ]]; then continue; fi
      mkdir -p "$dir/init"; state="$dir/init/sound_0493x13h.smpcd"; meta="$dir/init/sound_0493x13h.meta.json"
      if [[ "$PREFLIGHT_ONLY" != 1 ]]; then
        python3 scripts/generate_0493x13h_sound_state_fractional.py --output "$state" --metadata "$meta" --Lx "$lx" --Ly "$ly" --Nx "$SOUND_NX" --Ny "$SOUND_NY" --gamma "$GAMMA_FIXED" --dt "$dt" --kBT "$kbt" --mass "$MASS" --seed "$seed" --sound-mode-x "$SOUND_MODE_X" --sound-density-amplitude "$SOUND_DENSITY_AMPLITUDE"
      fi
      write_src_params "$dir" "$state" "$lx" "$ly" "$SOUND_NX" "$SOUND_NY" "$dt" "$kbt" "$seed" "$SOUND_STEPS" "$dump"
      prepare_run_environment "$dir" "$SOUND_NX" "$SOUND_NY" density
      sig=$(signature_value "stage=sound kBT=$kbt dt=$dt gamma=$GAMMA_FIXED alpha=$ALPHA_RAD lambdaOverH=$LAMBDA_OVER_H nx=$SOUND_NX ny=$SOUND_NY eps=$SOUND_DENSITY_AMPLITUDE seed=$seed steps=$SOUND_STEPS dump=$dump")
      launch "$dir" sound "$sig"
      if [[ "$PREFLIGHT_ONLY" != 1 && -f "$dir/RUN_COMPLETE_0493x13i_sound" ]]; then
        touch "$dir/RUN_COMPLETE_0493x13h_A_Cdamp"
      fi
    done
  done
}

run_msd() {
  local root="$CAMPAIGN_ROOT/M_msd"; mkdir -p "$root"
  local manifest="$root/manifest_0493x13i_msd.csv"
  echo 'kBT,kBTScale,dt,gamma,rotationAngleDeg,rotationAngleRad,targetLambdaMeanOverCell,cellSize,lambdaPhysical,Nx,Ny,Lx,Ly,expectedSeeds,seed,steps,dumpEvery,sampleParticles,runDir' > "$manifest"
  local kbt tag dt scale lx ly dump seed runDir dir caseRoot state sig first_seed
  first_seed="${SEED_ARR[0]}"
  lx=$(python3 -c 'import sys;print(int(sys.argv[1])*float(sys.argv[2]))' "$MSD_NX" "$CELL_SIZE")
  ly=$(python3 -c 'import sys;print(int(sys.argv[1])*float(sys.argv[2]))' "$MSD_NY" "$CELL_SIZE")
  dump=$(( (MSD_STEPS + MSD_DUMP_COUNT - 1) / MSD_DUMP_COUNT )); (( dump < 1 )) && dump=1
  for kbt in "${KBT_ARR[@]}"; do
    tag=$(kbt_tag "$kbt"); dt=$(calc_dt "$kbt")
    scale=$(python3 -c 'import math,sys;print(math.sqrt(float(sys.argv[1])/float(sys.argv[2])))' "$kbt" "$REFERENCE_KBT")
    for seed in "${SEED_ARR[@]}"; do
      runDir="$tag/seed${seed}"; caseRoot="$root/$runDir"; dir="$caseRoot/msd"
      echo "$kbt,$scale,$dt,$GAMMA_FIXED,$ALPHA_DEG,$ALPHA_RAD,$LAMBDA_OVER_H,$CELL_SIZE,$LAMBDA_PHYSICAL,$MSD_NX,$MSD_NY,$lx,$ly,${#SEED_ARR[@]},$seed,$MSD_STEPS,$dump,$MSD_SAMPLE_PARTICLES,$runDir" >> "$manifest"
      if [[ "$ANALYZE_ONLY" == 1 ]]; then continue; fi
      if [[ "$PREFLIGHT_ONLY" == 1 && "$PREFLIGHT_FIRST_SEED_ONLY" == 1 && "$seed" != "$first_seed" ]]; then continue; fi
      mkdir -p "$caseRoot/init" "$dir"; state="$caseRoot/init/msd_0493x13i.smpcd"
      if [[ "$PREFLIGHT_ONLY" != 1 ]]; then
        python3 scripts/generate_0493w1_src_fluid_calibrator_states.py --case msd --output "$state" --Lx "$lx" --Ly "$ly" --Nx "$MSD_NX" --Ny "$MSD_NY" --gamma "$GAMMA_FIXED" --dt "$dt" --kBT "$kbt" --mass "$MASS" --seed "$seed"
      fi
      write_src_params "$dir" "$state" "$lx" "$ly" "$MSD_NX" "$MSD_NY" "$dt" "$kbt" "$seed" "$MSD_STEPS" "$dump"
      prepare_run_environment "$dir" "$MSD_NX" "$MSD_NY" density
      sig=$(signature_value "stage=msd kBT=$kbt dt=$dt gamma=$GAMMA_FIXED alpha=$ALPHA_RAD lambdaOverH=$LAMBDA_OVER_H nx=$MSD_NX ny=$MSD_NY seed=$seed steps=$MSD_STEPS dump=$dump sample=$MSD_SAMPLE_PARTICLES")
      launch "$dir" msd "$sig"
    done
  done
}

run_sound_analysis() {
  [[ -f "$CAMPAIGN_ROOT/A_Cdamp/manifest_0493x13h_A_Cdamp.csv" ]] || return 0
  python3 scripts/analyze_0493x13h_A_Cdamp_L072.py \
    --campaign-root "$CAMPAIGN_ROOT" --repo-root "$ROOT" \
    --bootstrap "$SOUND_BOOTSTRAP" --cs-min 0.10 --cs-max 0.90 --validate-local
}

if [[ "$ANALYZE_ONLY" != 1 ]]; then
  IFS=',' read -ra STAGE_ARR <<< "$STAGES"
  for stage in "${STAGE_ARR[@]}"; do
    case "$stage" in
      S) echo '[0493x13i] === S: transverse shear nuT ==='; run_shear ;;
      C) echo '[0493x13i] === C: damped longitudinal cs/nuL ==='; run_sound ;;
      M) echo '[0493x13i] === M: MSD Dself ==='; run_msd ;;
      *) echo "[0493x13i] unknown stage: $stage" >&2; exit 2 ;;
    esac
  done
fi

if [[ "$PREFLIGHT_ONLY" == 1 ]]; then
  echo "[0493x13i] PREFLIGHT PASS stages=$STAGES"
  exit 0
fi

run_sound_analysis
python3 scripts/analyze_0493x13i_kbt_scaling.py \
  --campaign-root "$CAMPAIGN_ROOT" --repo-root "$ROOT" \
  --bootstrap "$BOOTSTRAP" --reference-kBT "$REFERENCE_KBT" \
  --target-lambda-over-h "$LAMBDA_OVER_H"

touch "$CAMPAIGN_ROOT/CAMPAIGN_COMPLETE_0493x13i_kbt_scaling"
echo "[0493x13i] COMPLETE root=$CAMPAIGN_ROOT"
