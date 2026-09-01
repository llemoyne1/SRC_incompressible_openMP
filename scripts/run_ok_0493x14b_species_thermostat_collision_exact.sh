#!/usr/bin/env bash
set -euo pipefail

# 0493x14b — dynamic two-species thermostat qualification with active SRC collision.
# Exact validation uses gridShift=false so the final .smpcd positions identify
# the same cells used by the final thermostat operation.
# This runner NEVER creates, rewrites, or normalizes ./livevis_control.kv.

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$ROOT/scripts/src_mpcd_run_ok_common.sh"
suite_root_cd_0434

RUN_OK_ENTRYPOINT="$ROOT/scripts/run_ok_0493x14b_species_thermostat_collision_exact.sh"
BIN="${BIN:-build/src_mpcd_base_cuda_q6_resident_livevis_0486}"
RUN_ROOT="${RUN_ROOT:-runs/0493x14b_species_thermostat_collision_exact}"
CLEAN_RUN_ROOT="${CLEAN_RUN_ROOT:-1}"
PREFLIGHT_ONLY="${PREFLIGHT_ONLY:-0}"
CASE_LABEL="${CASE_LABEL:-0493x14b_species_thermostat_collision_exact}"

# ----- Physical / numerical parameters: deliberately visible here -----
NX="${NX:-32}"
NY="${NY:-16}"
GAMMA="${GAMMA:-20}"                 # 10 particles/type/cell initially
Lx=1.0
Ly=1.0
DT="${DT:-0.002}"
STEPS="${STEPS:-2000}"
SEED="${SEED:-493141}"
THREADS="${THREADS:-8}"
ROTATION_ANGLE="${ROTATION_ANGLE:-2.0943951023931953}"   # 120 deg
RANDOM_ROTATION_SIGN=true
GRID_SHIFT_ENABLE=false               # intentional: exact cell-local thermostat audit
MASS_TYPE1="${MASS_TYPE1:-1.0}"
MASS_TYPE2="${MASS_TYPE2:-0.1}"
TARGET_EQUAL="${TARGET_EQUAL:-0.02}"
TARGET_SPLIT_1="${TARGET_SPLIT_1:-0.02}"
TARGET_SPLIT_2="${TARGET_SPLIT_2:-0.08}"
THERMOSTAT_MIN_PARTICLES="${THERMOSTAT_MIN_PARTICLES:-3}"
THERMOSTAT_ENABLE=true
THERMOSTAT_MODE=cell_relative_rescale
THERMOSTAT_EVERY=1
THERMOSTAT_TARGET_KBT="$TARGET_EQUAL" # legacy fallback only
SUMMARY_EVERY="${SUMMARY_EVERY:-100}"
DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-1000}"
DUMP_ROLE_FILTER=fluid
SUMMARY_ROLE_FILTER=fluid
PARTICLE_MASS="$MASS_TYPE1"
KBT="$TARGET_EQUAL"
U0=0.0
UIN=0.0
INACTIVE_SLOTS=0
PROJECTION_BACKEND=cuda
PROJECTION_OPERATOR=auto_fv_cg
PROJECTION_MAX_ITERATIONS=100
PROJECTION_TOLERANCE=1.0e-12
PROJECTION_MOMENTUM_CORRECTION_ENABLE=true
Q6_PROJECTION_STRENGTH=0.0             # retain resident CUDA thermostat plumbing, no Q6 velocity correction
SPECIES_RESAMPLING_ENABLE=false
WEIGHTED_RESAMPLING_ENABLE_OVERRIDE=false
CUDA_EMPTY_REFILL_ENABLE_OVERRIDE=false
RESAMPLING_THERMAL_RENORMALIZATION_ENABLE=false
RESAMPLING_MASS_GUARD_ENABLE=false
CUDA_RESAMPLING_CHI_FILTER_ENABLE=false
CUDA_RESAMPLING_CHI_MIN=0.05
GUARD_NMIN=$((GAMMA - 4))
GUARD_NTARGET="$GAMMA"
GUARD_NMAX=$((GAMMA + 4))
LIVE_VIS_ENABLE=0
FILTERED_RECORDING_ENABLE=0
RECORD_ENABLE=false
PARTICLE_TYPE_FILTER=-1
export LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
export OMP_NUM_THREADS="$THREADS"

if (( GAMMA < 12 || GAMMA % 2 != 0 )); then
  echo "[0493x14b] ERROR GAMMA must be even and >=12" >&2
  exit 2
fi

suite_defaults_common_0434
suite_compute_derived_0434

if [[ "$CLEAN_RUN_ROOT" == 1 && "$PREFLIGHT_ONLY" != 1 ]]; then rm -rf "$RUN_ROOT"; fi
mkdir -p "$RUN_ROOT/init" "$RUN_ROOT/logs"
STATE="$RUN_ROOT/init/two_type_uniform_dynamic_0493x14b.smpcd"

make_state() {
  python3 - "$STATE" "$NX" "$NY" "$GAMMA" "$MASS_TYPE1" "$MASS_TYPE2" "$TARGET_EQUAL" <<'PY'
import math, os, struct, sys
path,nx,ny,gamma,m1,m2,T = sys.argv[1:]
nx=int(nx); ny=int(ny); gamma=int(gamma); m1=float(m1); m2=float(m2); T=float(T)
per=gamma//2
# Opposite type drifts with exactly zero total momentum for equal counts and m2=m1/10.
mean={1:(0.02,0.0),2:(-0.20,0.0)}
x=[]; y=[]; vx=[]; vy=[]; typ=[]; mass=[]; role=[]
for j in range(ny):
    for i in range(nx):
        for t,m in ((1,m1),(2,m2)):
            ux,uy=mean[t]
            # Exact type-local cell target: 0.5*n*m*a^2=(n-1)*kBT in 2-D.
            a=math.sqrt(2.0*(per-1)*T/(per*m))
            for k in range(per):
                th=2.0*math.pi*(k+0.5)/per
                ph=th+(0.19 if t==2 else 0.0)
                x.append((i+0.5+0.30*math.cos(ph))/nx)
                y.append((j+0.5+0.30*math.sin(ph))/ny)
                vx.append(ux+a*math.cos(th)); vy.append(uy+a*math.sin(th))
                typ.append(t); mass.append(m); role.append(1)
N=len(x)
os.makedirs(os.path.dirname(path),exist_ok=True)
magic=b"SRCMPCD_STATE"+b"\0"*(16-len("SRCMPCD_STATE")); reserved=[0]*8; reserved[0]=1; reserved[1]=1
with open(path,"wb") as f:
    f.write(magic); f.write(struct.pack("<IIIIQIIII",2,0x01020304,2,1,N,1,1,8,4)); f.write(struct.pack("<8Q",*reserved))
    for arr,fmt in ((x,"d"),(y,"d"),(vx,"d"),(vy,"d"),(typ,"I"),(mass,"d"),(role,"B")):
        f.write(struct.pack(f"<{N}{fmt}",*arr))
print(f"[0493x14b-state] path={path} grid={nx}x{ny} gamma={gamma} perType={per} masses={m1}/{m2} initialKBT={T} N={N}")
PY
}

write_params() {
  local case_dir=$1 target1=$2 target2=$3
  local params="$case_dir/params/params_0493x14b.kv"
  mkdir -p "$case_dir/params" "$case_dir/output" "$case_dir/logs"
  cat > "$params" <<EOF
inputState = $STATE
outputDir = $case_dir/output
Lx = $Lx
Ly = $Ly
Nx = $NX
Ny = $NY
dt = $DT
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
speciesRegistryEnable = true
speciesCount = 2
species0 = 1 liquid liquid 1.0 1.0 $(python3 -c "print(($GAMMA//2)*float('$MASS_TYPE1'))")
species1 = 2 gas gas 0.0 1.0 $(python3 -c "print(($GAMMA//2)*float('$MASS_TYPE2'))")
speciesRequireRegisteredTypes = true
speciesDiagnosticsEnable = true
speciesDiagnosticsFilename = species_runtime_0493x14b.csv
speciesCellDiagnosticsEnable = false
speciesThermostatEnable = true
species0ThermostatTargetKBT = $target1
species1ThermostatTargetKBT = $target2
speciesQ6Enable = false
speciesQ6Mode = common
EOF
  suite_write_common_params_0434 src-q6 >> "$params"
  printf '%s\n' "$params"
}

make_state
if [[ "$PREFLIGHT_ONLY" != 1 ]]; then suite_ensure_binary_0434; fi

run_one() {
  local label=$1 t1=$2 t2=$3
  local dir="$RUN_ROOT/$label" params log time_file final_state
  params="$(write_params "$dir" "$t1" "$t2")"
  log="$dir/logs/run_0493x14b.log"; time_file="$dir/logs/time_0493x14b.txt"
  final_state="$dir/output/state_step_$(printf '%08d' "$STEPS").smpcd"

  suite_export_cuda_flags_0434 src-q6 periodic
  export MPCD_X12A_LOCAL_THERMAL_COOLING=0
  export SRC_LIVE_VIS_ENABLE=0 MPCD_LIVE_VIS_ENABLE=0

  echo "===== 0493x14b $label ====="
  echo "PATHS: runner=$RUN_OK_ENTRYPOINT binary=$BIN state=$STATE params=$params output=$dir/output"
  echo "GRID:  L=${Lx}x${Ly} N=${NX}x${NY} gamma=$GAMMA dt=$DT steps=$STEPS gridShift=$GRID_SHIFT_ENABLE"
  echo "SRC:   angle=$ROTATION_ANGLE randomSign=$RANDOM_ROTATION_SIGN collision=ACTIVE/common-two-type"
  echo "TYPES: type1 mass=$MASS_TYPE1 kBT=$t1 ; type2 mass=$MASS_TYPE2 kBT=$t2 ; minParticles=$THERMOSTAT_MIN_PARTICLES"
  echo "THERMO: per-type cell_relative_rescale every=$THERMOSTAT_EVERY ; x12a=OFF"
  echo "DUMPS: every=$DUMP_STATE_EVERY ; final=$final_state"
  echo "NOTE:  gridShift=false is intentional for exact cell-local thermostat audit; ./livevis_control.kv is untouched"
  suite_preflight_run_ok_0492 "$params"
  if [[ "$PREFLIGHT_ONLY" == 1 ]]; then return 0; fi
  /usr/bin/time -o "$time_file" -f 'elapsed=%e user=%U sys=%S' "$BIN" "$params" | tee "$log"
  [[ -s "$final_state" ]] || { echo "[0493x14b] FAIL missing final dump $final_state" >&2; exit 3; }
  python3 "$ROOT/tools/analyze_0493x14_species_thermostat_dynamic.py" \
    --initial "$STATE" --state "$final_state" \
    --species-csv "$dir/output/species_runtime_0493x14b.csv" \
    --label "$label" --nx "$NX" --ny "$NY" --min-particles "$THERMOSTAT_MIN_PARTICLES" \
    --target1 "$t1" --target2 "$t2" --grid-shift 0
}

run_one equal_temperature "$TARGET_EQUAL" "$TARGET_EQUAL"
run_one split_temperature "$TARGET_SPLIT_1" "$TARGET_SPLIT_2"

if [[ "$PREFLIGHT_ONLY" != 1 ]]; then
  echo "[0493x14b] PASS dynamic active-collision exact-grid qualification"
fi
