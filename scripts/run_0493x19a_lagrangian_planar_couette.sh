#!/usr/bin/env bash
# 0493x19a — first tangential-accommodation qualification for the persistent
# x17 Lagrangian material boundary. A full-width horizontal chi slab is a moving
# belt with prescribed tangential Ux; fixed accommodating y-walls close two
# planar Couette gaps. 0493x19a-fix1 rotates the original benchmark into the
# CUDA wall-simple 0253 supported periodic-x / bounded-y channel topology. KINETIC_MODE=specular is the zero-shear ablation,
# KINETIC_MODE=bounceback is the new deterministic local-wall accommodation.

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$ROOT/scripts/src_mpcd_run_common_0434.sh"
suite_root_cd_0434 || exit $?

KINETIC_MODE="${KINETIC_MODE:-bounceback}"
CASE_LABEL="${CASE_LABEL:-0493x19a_${KINETIC_MODE}}"
BASE_RUN_ROOT="${BASE_RUN_ROOT:-runs/0493x19a_lagrangian_planar_couette/${KINETIC_MODE}}"
MODE="${MODE:-src-q6}"
TOPOLOGY="wall"
GEN_CASE="step"

Lx="${Lx:-0.50}"
Ly="${Ly:-0.25}"
NX="${NX:-128}"
NY="${NY:-64}"
GAMMA="${GAMMA:-12}"
STEPS="${STEPS:-5000}"
DT="${DT:-0.006}"
KBT="${KBT:-0.05}"
SEED="${SEED:-4931901}"
PARTICLE_MASS="${PARTICLE_MASS:-1.0}"
WALL_SPEED_X="${WALL_SPEED_X:-0.04}"
SLAB_CELLS="${SLAB_CELLS:-8}"
INITIAL_DEACTIVATE_BELOW_CHI="${INITIAL_DEACTIVATE_BELOW_CHI:-0.5}"
DARCY_THREADS_PER_BLOCK="${DARCY_THREADS_PER_BLOCK:-256}"

SUMMARY_EVERY="${SUMMARY_EVERY:-10}"
DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-1000}"
LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-1}"
LIVE_VIS_FIELD="${LIVE_VIS_FIELD:-ux}"
LIVE_VIS_EVERY="${LIVE_VIS_EVERY:-1}"
LIVE_VIS_NX="${LIVE_VIS_NX:-64}"
LIVE_VIS_NY="${LIVE_VIS_NY:-64}"
LIVE_VIS_HOLD_ON_EXIT="${LIVE_VIS_HOLD_ON_EXIT:-0}"
FILTERED_RECORDING_ENABLE="${FILTERED_RECORDING_ENABLE:-1}"
RECORD_ENABLE="${RECORD_ENABLE:-true}"
RECORD_FIELDS="${RECORD_FIELDS:-rho,ux,uy}"
RECORD_EVERY="${RECORD_EVERY:-100}"
FILTER_MODE="${FILTER_MODE:-none}"
FILTER_SAMPLE_EVERY="${FILTER_SAMPLE_EVERY:-100}"
PARTICLE_TYPE_FILTER="${PARTICLE_TYPE_FILTER:--1}"
CLEAN_RUN_ROOT="${CLEAN_RUN_ROOT:-1}"
PREFLIGHT_ONLY="${PREFLIGHT_ONLY:-0}"
RESTART_STATE="${RESTART_STATE:-}"
RESTART_FROM_STEP="${RESTART_FROM_STEP:-0}"

VELOCITY_MODE=uniform_x
U0=0.0
BACKGROUND_TYPE=0
INACTIVE_TYPE=0
INACTIVE_SLOTS=0
SKIP_SOLID_CELLS=true
SKIP_SOLID_PARTICLES=true
REMOVE_MEAN_DRIFT=false
ROTATION_ANGLE="${ROTATION_ANGLE:-1.5707963267948966}"
RANDOM_ROTATION_SIGN=true
GRID_SHIFT_ENABLE=true
THERMOSTAT_ENABLE=true
THERMOSTAT_MODE=cell_relative_rescale
THERMOSTAT_EVERY=1
THERMOSTAT_TARGET_KBT="$KBT"
THERMOSTAT_MIN_PARTICLES=3
WEIGHTED_RESAMPLING_ENABLE_OVERRIDE=false
CUDA_EMPTY_REFILL_ENABLE_OVERRIDE=false
SPECIES_RESAMPLING_ENABLE=false
DUMP_ROLE_FILTER=all
SUMMARY_ROLE_FILTER=fluid

suite_defaults_common_0434
suite_compute_derived_0434
suite_validate_path_0434 "$MODE" || exit $?

case "$KINETIC_MODE" in
  specular|bounceback) ;;
  *) echo "[0493x19a] ERROR KINETIC_MODE must be specular or bounceback" >&2; exit 2 ;;
esac

if (( NX < 32 || NY < 32 || SLAB_CELLS < 2 || SLAB_CELLS >= NY/2 )); then
  echo "[0493x19a] ERROR require NX,NY>=32 and 2<=SLAB_CELLS<NY/2" >&2
  exit 2
fi

read -r SLAB_YMIN SLAB_YMAX <<EOF_GEOM
$(python3 - "$Ly" "$NY" "$SLAB_CELLS" <<'PY'
import sys
Ly=float(sys.argv[1]); ny=int(sys.argv[2]); cells=int(sys.argv[3])
dy=Ly/ny; w=cells*dy; c=0.5*Ly
print(f"{c-0.5*w:.17g} {c+0.5*w:.17g}")
PY
)
EOF_GEOM
STEP_XMIN=0.0
STEP_XMAX="$Lx"
STEP_YMIN="$SLAB_YMIN"
STEP_YMAX="$SLAB_YMAX"

RUN_ROOT="$BASE_RUN_ROOT/fresh"
if suite_truthy_0434 "$CLEAN_RUN_ROOT"; then rm -rf "$RUN_ROOT"; fi
suite_prepare_dirs_0434 "$RUN_ROOT"
STATE="$RUN_ROOT/init/${CASE_LABEL}_${NX}x${NY}_g${GAMMA}.smpcd"
PARAMS="$RUN_ROOT/params/${CASE_LABEL}.kv"
OUT="$RUN_ROOT/output"
LOG="$RUN_ROOT/logs/${CASE_LABEL}.log"
TIMEFILE="$RUN_ROOT/logs/${CASE_LABEL}.time"
LIVE_VIS_CONTROL_FILE="$RUN_ROOT/params/${CASE_LABEL}_livevis_control.kv"
mkdir -p "$OUT"

INITIAL_DEACTIVATE_EFFECTIVE="$INITIAL_DEACTIVATE_BELOW_CHI"
if [[ -n "$RESTART_STATE" ]]; then
  if [[ ! -f "$RESTART_STATE" ]]; then
    echo "[0493x19a] ERROR restart state not found: $RESTART_STATE" >&2
    exit 2
  fi
  STATE="$RESTART_STATE"
  INITIAL_DEACTIVATE_EFFECTIVE=-1
  echo "[0493x19a] RESTART state=$STATE fromStep=$RESTART_FROM_STEP"
else
  suite_generate_case_0434 "$STATE" "" || exit $?
fi

cat > "$PARAMS" <<PARAMS
inputState = $STATE
outputDir = $OUT
Lx = $Lx
Ly = $Ly
Nx = $NX
Ny = $NY
dt = $DT
nSteps = $STEPS
bcLeft = periodic
bcRight = periodic
bcBottom = solid
bcTop = solid
bcX = periodic
bcY = wall
openBoundarySegmentsEnable = false
openBoundarySegmentCount = 0
bodyAccelerationX = 0.0
bodyAccelerationY = 0.0
taylorGreenForcingEnable = false
wallAccommodation = 1.0
wallThermalNoise = 0.0
wallVpEnable = false
wallVpGamma = $GAMMA
wallVpMass = $PARTICLE_MASS
wallVpUxBottom = 0.0
wallVpUyBottom = 0.0
wallVpUxTop = 0.0
wallVpUyTop = 0.0
phaseInterfaceKineticReflectionFraction = 0.0
PARAMS
suite_write_common_params_0434 "$MODE" >> "$PARAMS"
cat >> "$PARAMS" <<PARAMS
darcyBrinkmanEnable = true
darcyChiMode = box
darcyBoxXMin = 0.0
darcyBoxXMax = $Lx
darcyBoxYMin = $SLAB_YMIN
darcyBoxYMax = $SLAB_YMAX
darcyInterfaceWidth = 0.0
darcyAlphaMin = 0.0
darcyAlphaMax = 0.0
darcyQ = 0.1
darcyUSolidX = $WALL_SPEED_X
darcyUSolidY = 0.0
darcyCostEvery = 1000000
darcyCostFilename = darcy_cost_0343.csv
darcyThreadsPerBlock = $DARCY_THREADS_PER_BLOCK
darcyInitialDeactivateBelowChi = $INITIAL_DEACTIVATE_EFFECTIVE
darcyBrinkmanForcingMode = mean
darcyChiCollisionVpEnable = false
chiKineticBoundaryMode = $KINETIC_MODE
chiSolidDynamicsEnable = false
chiSolidModel = none
chiSolidQualificationDiagnosticsEnable = true
PARAMS

cat > "$LIVE_VIS_CONTROL_FILE" <<KV
recordEnable = ${RECORD_ENABLE}
recordSession = ${CASE_LABEL}_${MODE}
recordFields = ${RECORD_FIELDS}
recordFormat = ${RECORD_FORMAT}
recordEvery = ${RECORD_EVERY}
liveGridNx = ${LIVE_VIS_NX}
liveGridNy = ${LIVE_VIS_NY}
field = ${LIVE_VIS_FIELD}
filterMode = ${FILTER_MODE}
filterSampleEvery = ${FILTER_SAMPLE_EVERY}
smoothPasses = 0
particleTypeFilter = ${PARTICLE_TYPE_FILTER}
KV

suite_export_cuda_flags_0434 "$MODE" "$TOPOLOGY"
suite_export_livevis_0434
suite_write_env_file_0434 "$RUN_ROOT/logs/environment_0493x19a.env" "$MODE"
cat >> "$RUN_ROOT/logs/environment_0493x19a.env" <<META_ENV
X19A_KINETIC_MODE=$KINETIC_MODE
X19A_RESTART_STATE=${RESTART_STATE:-NONE}
X19A_RESTART_FROM_STEP=$RESTART_FROM_STEP
META_ENV

cat > "$RUN_ROOT/run_meta_0493x19a.txt" <<META
case=$CASE_LABEL
purpose=lagrangian-planar-couette-tangential-accommodation
mode=$MODE
kineticMode=$KINETIC_MODE
Lx=$Lx
Ly=$Ly
Nx=$NX
Ny=$NY
dt=$DT
steps=$STEPS
gamma=$GAMMA
kBT=$KBT
wallSpeedX=$WALL_SPEED_X
slabYMin=$SLAB_YMIN
slabYMax=$SLAB_YMAX
outerWalls=stationary-accommodating-y-walls
innerWall=x17-lagrangian-periodic-x-prescribed-tangential-belt
topology=periodic-x-bounded-y-wall-simple-0253
restartState=${RESTART_STATE:-NONE}
restartFromStep=$RESTART_FROM_STEP
META

printf '\n===== 0493x19a LAGRANGIAN PLANAR COUETTE =====\n'
printf 'run=%s mode=%s kinetic=%s grid=%sx%s steps=%s dt=%s\n' "$RUN_ROOT" "$MODE" "$KINETIC_MODE" "$NX" "$NY" "$STEPS" "$DT"
printf 'inner slab y=[%s,%s] Ux=%s; outer y walls fixed/accommodating\n' "$SLAB_YMIN" "$SLAB_YMAX" "$WALL_SPEED_X"
printf 'dumps every %s; livevis=%s every=%s; record every=%s\n' "$DUMP_STATE_EVERY" "$LIVE_VIS_ENABLE" "$LIVE_VIS_EVERY" "$RECORD_EVERY"
printf '================================================\n\n'

suite_run_binary_0434 "$PARAMS" "$LOG" "$TIMEFILE" "$OUT" || exit $?
if suite_truthy_0434 "$PREFLIGHT_ONLY"; then exit 0; fi

[[ -s "$OUT/chi_kinetic_boundary_0493x16j.csv" ]] || { echo "[0493x19a] ERROR missing kinetic-boundary CSV" >&2; exit 2; }
grep -q "\[0493x16j-chi-kinetic\] mode=$KINETIC_MODE timing=prestream" "$LOG" || {
  echo "[0493x19a] ERROR requested x17 kinetic mode not reported" >&2; exit 2; }
grep -q "movingSolid=1" "$LOG" || {
  echo "[0493x19a] ERROR x17 reports movingSolid=0 although WALL_SPEED_X=$WALL_SPEED_X" >&2; exit 2; }
[[ -s "$OUT/chi_lagrangian_mesh_0493x17a.csv" ]] || { echo "[0493x19a] ERROR missing x17 mesh CSV" >&2; exit 2; }

echo "[0493x19a] COMPLETE run=$RUN_ROOT"
