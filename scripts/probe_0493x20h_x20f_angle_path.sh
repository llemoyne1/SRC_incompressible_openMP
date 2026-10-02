#!/usr/bin/env bash
# 0493x20h — exact x20f SRC rotation-angle path probe
# Non-destructive: writes only under its dedicated RUN_ROOT.
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
# If launched from /mnt/data, prefer current working repository.
if [[ ! -f "$ROOT/scripts/src_mpcd_run_common_0434.sh" ]]; then
  ROOT="${ROOT_OVERRIDE:-$PWD}"
fi
[[ -f "$ROOT/scripts/src_mpcd_run_common_0434.sh" ]] || {
  echo "[x20h] ERROR repository root not found; run from SRC_GPU-SURF or set ROOT=/path/to/SRC_GPU-SURF" >&2
  exit 2
}
source "$ROOT/scripts/src_mpcd_run_common_0434.sh"
suite_root_cd_0434

CASE_LABEL=x20f_rotation_angle_path_probe_0493x20h
BIN="${BIN:-build/src_mpcd_base_cuda_q6_resident_livevis_0486}"
RUN_ROOT="${RUN_ROOT:-runs/0493x20h_x20f_angle_probe}"
CLEAN_ROOT="${CLEAN_ROOT:-1}"
STEPS="${STEPS:-3}"
SEED="${SEED:-4938601}"
THREADS="${THREADS:-8}"

CELL_SIZE=0.00390625
KBT=0.125
MASS=1.0
CS_REF=0.35512
MACH=0.10
NX_NOM=64
NY_NOM=16
MODE_X=1
GAMMA_NOM=8
DT_NOM=0.0063471328149122585
RAD30=0.52359877559829882
RAD175=3.0543261909900767
U0="$(awk -v ma="$MACH" -v c="$CS_REF" 'BEGIN{printf "%.17g",ma*c}')"
LX="$(awk -v n="$NX_NOM" -v h="$CELL_SIZE" 'BEGIN{printf "%.17g",n*h}')"
LY="$(awk -v n="$NY_NOM" -v h="$CELL_SIZE" 'BEGIN{printf "%.17g",n*h}')"

for dep in \
  scripts/src_mpcd_run_common_0434.sh \
  scripts/generate_0493x13e_longitudinal_velocity_state.py; do
  [[ -f "$dep" ]] || { echo "[x20h] ERROR missing $dep" >&2; exit 2; }
done
[[ "$STEPS" =~ ^[1-9][0-9]*$ ]] || { echo "[x20h] ERROR STEPS must be >=1" >&2; exit 2; }

if [[ "$CLEAN_ROOT" == 1 ]]; then rm -rf "$RUN_ROOT"; fi
mkdir -p "$RUN_ROOT/common_init" "$RUN_ROOT/audit"

# Exact x20f campaign-wide globals before suite_defaults_common_0434.
export OMP_NUM_THREADS="$THREADS" LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
INACTIVE_SLOTS=0; SUMMARY_ROLE_FILTER=fluid; DUMP_ROLE_FILTER=fluid
SPECIES_RESAMPLING_ENABLE=false; WEIGHTED_RESAMPLING_ENABLE_OVERRIDE=false; CUDA_EMPTY_REFILL_ENABLE_OVERRIDE=false
RESAMPLING_THERMAL_RENORMALIZATION_ENABLE=false; RESAMPLING_MASS_GUARD_ENABLE=false
PROJECTION_BACKEND=cuda; PROJECTION_OPERATOR=auto_fv_cg; PROJECTION_MAX_ITERATIONS=2500; PROJECTION_TOLERANCE=1e-5
PROJECTION_MOMENTUM_CORRECTION_ENABLE=false; Q6_PROJECTION_STRENGTH=1.0
Q6_GF_DENSITY_RELAXATION_TIME=0.25; Q6_GF_DENSITY_COMPRESSION_GATE_ENABLE=1
Q6_GF_DENSITY_COMPRESSION_THRESHOLD_PARTICLES=3; Q6_GF_DENSITY_TRACTION_THRESHOLD_PARTICLES=6; Q6_GF_DENSITY_TRACTION_GAIN=1.0
Q6_GF_MIN_FILL_FRACTION=0.10; Q6_GF_HAS_GAS_PHASE=0; Q6_GF_EXTERNAL_SPECIES=0
LIVE_VIS_ENABLE=0; FILTERED_RECORDING_ENABLE=0; RECORD_ENABLE=false; PARTICLE_TYPE_FILTER=-1

NX="$NX_NOM"; NY="$NY_NOM"; GAMMA="$GAMMA_NOM"; DT="$DT_NOM"; PARTICLE_MASS="$MASS"
ROTATION_ANGLE=2.0943951023931953
RANDOM_ROTATION_SIGN=true; GRID_SHIFT_ENABLE=true
THERMOSTAT_ENABLE=true; THERMOSTAT_MODE=cell_relative_rescale; THERMOSTAT_EVERY=1
THERMOSTAT_TARGET_KBT="$KBT"; THERMOSTAT_MIN_PARTICLES=3
Lx="$LX"; Ly="$LY"; SUMMARY_EVERY=1; DUMP_STATE_EVERY=1
suite_defaults_common_0434
suite_compute_derived_0434
suite_ensure_binary_0434

BIN_ABS="$(readlink -f "$BIN")"
COMMON_ABS="$(readlink -f scripts/src_mpcd_run_common_0434.sh)"
GEN_ABS="$(readlink -f scripts/generate_0493x13e_longitudinal_velocity_state.py)"

# One authoritative initial state, copied to every run.
COMMON_STATE="$RUN_ROOT/common_init/longitudinal_common.smpcd"
COMMON_META="$RUN_ROOT/common_init/longitudinal_common.meta.json"
python3 scripts/generate_0493x13e_longitudinal_velocity_state.py \
  --output "$COMMON_STATE" --metadata "$COMMON_META" \
  --Lx "$LX" --Ly "$LY" --Nx "$NX_NOM" --Ny "$NY_NOM" \
  --gamma "$GAMMA_NOM" --kBT "$KBT" --mass "$MASS" --seed "$SEED" \
  --mode-x "$MODE_X" --amplitude "$U0" --mach-requested "$MACH" \
  --sound-speed-reference "$CS_REF"
COMMON_STATE_SHA="$(sha256sum "$COMMON_STATE" | awk '{print $1}')"

write_params_x20f_exact() {
  local state=$1 params=$2 outdir=$3 rad=$4
  cat > "$params" <<PARAMS
inputState = $state
outputDir = $outdir
Lx = $LX
Ly = $LY
Nx = $NX_NOM
Ny = $NY_NOM
dt = $DT_NOM
nSteps = $STEPS
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
  # This is intentionally the x20f writing idiom: per-run values are temporary
  # assignments only for suite_write_common_params_0434.
  GAMMA="$GAMMA_NOM" NX="$NX_NOM" NY="$NY_NOM" Lx="$LX" Ly="$LY" \
  DT="$DT_NOM" KBT="$KBT" PARTICLE_MASS="$MASS" ROTATION_ANGLE="$rad" \
  RANDOM_ROTATION_SIGN=true GRID_SHIFT_ENABLE=true THERMOSTAT_ENABLE=true \
  THERMOSTAT_MODE=cell_relative_rescale THERMOSTAT_EVERY=1 \
  THERMOSTAT_TARGET_KBT="$KBT" THERMOSTAT_MIN_PARTICLES=3 SEED="$SEED" \
  SUMMARY_EVERY=1 DUMP_STATE_EVERY=1 \
    suite_write_common_params_0434 src >> "$params"
}

sanitize_runtime_env() {
  # Remove only runtime feature variables which can bypass the shared helper.
  # This is done in a subshell, so the invoking environment is untouched.
  local k
  while IFS='=' read -r k _; do
    case "$k" in
      MPCD_CUDA_*|MPCD_Q6_*|SRC_GPU_*|SRC_LIVE_VIS_*|MPCD_LIVE_VIS_*) unset "$k" || true ;;
    esac
  done < <(env)
  export LIVE_PROGRESS="${LIVE_PROGRESS:-1}" OMP_NUM_THREADS="$THREADS"
}

prepare_profile() {
  local profile=$1 rad=$2
  case "$profile" in
    ORIGINAL)
      # Exact x20f prepare(): only geometry/occupancy globals are refreshed.
      NX="$NX_NOM"; NY="$NY_NOM"; Lx="$LX"; Ly="$LY"; GAMMA="$GAMMA_NOM"
      ;;
    SYNCED)
      # Same helper path, but synchronize every per-run global before export.
      NX="$NX_NOM"; NY="$NY_NOM"; Lx="$LX"; Ly="$LY"; GAMMA="$GAMMA_NOM"
      DT="$DT_NOM"; KBT="$KBT"; PARTICLE_MASS="$MASS"; ROTATION_ANGLE="$rad"
      RANDOM_ROTATION_SIGN=true; GRID_SHIFT_ENABLE=true; THERMOSTAT_ENABLE=true
      THERMOSTAT_MODE=cell_relative_rescale; THERMOSTAT_EVERY=1
      THERMOSTAT_TARGET_KBT="$KBT"; THERMOSTAT_MIN_PARTICLES=3
      SEED="$SEED"; SUMMARY_EVERY=1; DUMP_STATE_EVERY=1
      ;;
    SANITIZED)
      sanitize_runtime_env
      NX="$NX_NOM"; NY="$NY_NOM"; Lx="$LX"; Ly="$LY"; GAMMA="$GAMMA_NOM"
      DT="$DT_NOM"; KBT="$KBT"; PARTICLE_MASS="$MASS"; ROTATION_ANGLE="$rad"
      RANDOM_ROTATION_SIGN=true; GRID_SHIFT_ENABLE=true; THERMOSTAT_ENABLE=true
      THERMOSTAT_MODE=cell_relative_rescale; THERMOSTAT_EVERY=1
      THERMOSTAT_TARGET_KBT="$KBT"; THERMOSTAT_MIN_PARTICLES=3
      SEED="$SEED"; SUMMARY_EVERY=1; DUMP_STATE_EVERY=1
      ;;
    *) echo "[x20h] ERROR unknown profile=$profile" >&2; return 2 ;;
  esac
  suite_export_cuda_flags_0434 src periodic
}

run_one() (
  set -euo pipefail
  local profile=$1 deg=$2 rad=$3
  local dir="$RUN_ROOT/$profile/alpha${deg}"
  local state="$dir/init/longitudinal_0493x20h.smpcd"
  local params="$dir/params/params_0493x20h.kv"
  local out="$dir/output"
  local log="$dir/logs/run.log"
  mkdir -p "$dir/init" "$dir/params" "$out" "$dir/logs" "$dir/audit"
  cp "$COMMON_STATE" "$state"
  write_params_x20f_exact "$state" "$params" "$out" "$rad"
  prepare_profile "$profile" "$rad"
  suite_preflight_run_ok_0492 "$params"

  # Full runtime snapshot, plus focused variables. This is intentionally broader
  # than suite_write_env_file_0434.
  env | sort > "$dir/audit/environment_full.txt"
  {
    echo "profile=$profile"
    echo "angleDeg=$deg"
    echo "requestedRad=$rad"
    echo "shell_ROTATION_ANGLE=${ROTATION_ANGLE:-UNSET}"
    echo "shell_DT=${DT:-UNSET}"
    echo "shell_SEED=${SEED:-UNSET}"
    echo "paramsRotationAngle=$(awk -F= '$1 ~ /^[[:space:]]*rotationAngle[[:space:]]*$/ {gsub(/[[:space:]]/,"",$2);v=$2} END{print v}' "$params")"
    echo "paramsSha256=$(sha256sum "$params" | awk '{print $1}')"
    echo "initialSha256=$(sha256sum "$state" | awk '{print $1}')"
    env | grep -E '^(MPCD_CUDA_|MPCD_Q6_|SRC_GPU_|SUITE_ACTIVE_|OMP_|LIVE_PROGRESS=)' | sort || true
  } > "$dir/audit/runtime_focus.txt"

  echo "[x20h] profile=$profile alpha=$deg rad=$rad steps=$STEPS"
  /usr/bin/time -o "$dir/logs/time.txt" -f 'elapsed=%e user=%U sys=%S' \
    "$BIN" "$params" > "$log" 2>&1
)

for profile in ORIGINAL SYNCED SANITIZED; do
  run_one "$profile" 30  "$RAD30"
  run_one "$profile" 175 "$RAD175"
done

# Summarize hashes and determine the earliest differing dump.
HASH_CSV="$RUN_ROOT/audit/x20h_hashes.csv"
REPORT="$RUN_ROOT/audit/x20h_verdict.txt"
python3 - "$RUN_ROOT" "$COMMON_STATE_SHA" "$BIN_ABS" "$COMMON_ABS" "$GEN_ABS" "$HASH_CSV" "$REPORT" <<'PY'
import csv,hashlib,pathlib,re,sys
root=pathlib.Path(sys.argv[1]); common_sha,binp,commonp,genp,outcsv,report=sys.argv[2:]
profiles=['ORIGINAL','SYNCED','SANITIZED']; angles=['30','175']
def sha(p):
    h=hashlib.sha256()
    with open(p,'rb') as f:
        for b in iter(lambda:f.read(1<<20),b''):h.update(b)
    return h.hexdigest()
def dumps(profile,angle):
    d=root/profile/f'alpha{angle}'/'output'
    pairs=[]
    for p in d.glob('state_step_*.smpcd'):
        m=re.search(r'state_step_(\d+)\.smpcd$',p.name)
        if m:pairs.append((int(m.group(1)),p))
    return dict(sorted(pairs))
def kv(profile,angle,key):
    p=root/profile/f'alpha{angle}'/'params'/'params_0493x20h.kv'; v=''
    for line in p.read_text().splitlines():
        if '=' in line:
            k,x=line.split('=',1)
            if k.strip()==key:v=x.strip()
    return v
rows=[]; summary={}
for prof in profiles:
    ds={a:dumps(prof,a) for a in angles}
    common=sorted(set(ds['30']) & set(ds['175']))
    first=None
    for st in common:
        if sha(ds['30'][st])!=sha(ds['175'][st]): first=st; break
    last=max(common) if common else None
    s1=(1 in ds['30'] and 1 in ds['175'] and sha(ds['30'][1])==sha(ds['175'][1]))
    sl=(last is not None and sha(ds['30'][last])==sha(ds['175'][last]))
    summary[prof]=dict(first=first,step1_identical=s1,last=last,last_identical=sl)
    for a in angles:
        init=root/prof/f'alpha{a}'/'init'/'longitudinal_0493x20h.smpcd'
        p=root/prof/f'alpha{a}'/'params'/'params_0493x20h.kv'
        rows.append({
          'profile':prof,'alphaDeg':a,'rotationAngleKV':kv(prof,a,'rotationAngle'),
          'paramsSha256':sha(p),'initialSha256':sha(init),
          'step1Sha256':sha(ds[a][1]) if 1 in ds[a] else '',
          'finalStep':max(ds[a]) if ds[a] else '',
          'finalSha256':sha(ds[a][max(ds[a])]) if ds[a] else ''})
with open(outcsv,'w',newline='') as f:
    w=csv.DictWriter(f,fieldnames=list(rows[0]));w.writeheader();w.writerows(rows)
orig=summary['ORIGINAL']['first']; sync=summary['SYNCED']['first']; san=summary['SANITIZED']['first']
if orig is not None:
    verdict='FRESH_X20F_PATH_ANGLE_SENSITIVE'
    impact='The exact x20f helper path distinguishes 30 and 175 deg in a fresh isolated probe. The previous x20f campaign equality is therefore not reproduced; investigate stale/reused outputs or campaign-specific state/environment history.'
elif sync is not None:
    verdict='X20F_GLOBAL_SYNC_BUG_CONFIRMED'
    impact='The exact x20f path ignores the angle until per-run globals are synchronized before suite_export_cuda_flags_0434. Repair prepare() and rerun only the x20f alpha cases.'
elif san is not None:
    verdict='X20F_ENVIRONMENT_CONTAMINATION_CONFIRMED'
    impact='Global synchronization alone is insufficient, but sanitizing inherited CUDA/SRC runtime flags restores angle sensitivity. Audit the invoking environment and helper clear-list.'
else:
    verdict='X20F_HELPER_PATH_ANGLE_INSENSITIVE'
    impact='Even the synchronized and sanitized shared-helper path does not distinguish the angles. Compare helper-selected runtime flags against the historical direct calibrator before any x20f alpha rerun.'
lines=[
 '===== 0493x20h X20F ROTATION-ANGLE PATH PROBE =====',
 f'runRoot={root}',f'binary={binp}',f'binarySha256={sha(binp)}',
 f'commonHelper={commonp}',f'commonHelperSha256={sha(commonp)}',
 f'generator={genp}',f'generatorSha256={sha(genp)}',f'commonInitialSha256={common_sha}',
 '', 'anglesDeg=30,175', 'sameSeed=4938601', 'profiles=ORIGINAL,SYNCED,SANITIZED','',
]
for p in profiles:
    s=summary[p]
    lines += [f'{p}_firstDifferentStep={s["first"] if s["first"] is not None else "NONE"}',
              f'{p}_step1Identical={"YES" if s["step1_identical"] else "NO"}',
              f'{p}_finalComparedStep={s["last"] if s["last"] is not None else "NONE"}',
              f'{p}_finalIdentical={"YES" if s["last_identical"] else "NO"}','']
lines += [f'VERDICT={verdict}',f'IMPACT={impact}','',f'hashTable={outcsv}']
pathlib.Path(report).write_text('\n'.join(lines)+'\n')
print('\n'.join(lines))
PY

printf '\n[x20h] COMPLETE\n[x20h] report=%s\n[x20h] hashes=%s\n' "$REPORT" "$HASH_CSV"
