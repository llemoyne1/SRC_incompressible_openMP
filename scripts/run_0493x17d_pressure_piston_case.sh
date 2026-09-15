#!/usr/bin/env bash
set -euo pipefail
# 0493x17d — article demonstrator B: rigid piston accelerated by a pressure
# imbalance in a closed chamber.  Same chi input and x17 kinetic material wall.
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$ROOT/scripts/src_mpcd_run_common_0434.sh"
suite_root_cd_0434 || exit $?
CASE_LABEL="${CASE_LABEL:-0493x17d_pressure_piston}"; MODE="${MODE:-src-q6}"; TOPOLOGY=wall
Lx="${Lx:-0.5}"; Ly="${Ly:-0.25}"; NX="${NX:-128}"; NY="${NY:-64}"
DT="${DT:-0.002}"; STEPS="${STEPS:-500}"; KBT="${KBT:-0.125}"; PARTICLE_MASS="${PARTICLE_MASS:-1.0}"; SEED="${SEED:-4931712}"
GAMMA_LEFT="${GAMMA_LEFT:-24}"; GAMMA_RIGHT="${GAMMA_RIGHT:-16}"; GAMMA="$GAMMA_LEFT"
PISTON_CENTER_X="${PISTON_CENTER_X:-0.25}"; PISTON_THICKNESS_CELLS="${PISTON_THICKNESS_CELLS:-8}"
H="$(python3 - "$Lx" "$Ly" "$NX" "$NY" <<'PY'
import sys
Lx,Ly=float(sys.argv[1]),float(sys.argv[2]); nx,ny=int(sys.argv[3]),int(sys.argv[4]); print(f"{min(Lx/nx,Ly/ny):.17g}")
PY
)"
read -r SLAB_XMIN SLAB_XMAX < <(python3 - "$PISTON_CENTER_X" "$PISTON_THICKNESS_CELLS" "$H" <<'PY'
import sys
c=float(sys.argv[1]); q=float(sys.argv[2]); h=float(sys.argv[3]); w=q*h; print(f"{c-0.5*w:.17g} {c+0.5*w:.17g}")
PY
)
SOLID_MASS="${SOLID_MASS:-131072.0}"; INITIAL_DEACTIVATE_BELOW_CHI="${INITIAL_DEACTIVATE_BELOW_CHI:-0.5}"; DARCY_THREADS_PER_BLOCK="${DARCY_THREADS_PER_BLOCK:-256}"
ROTATION_ANGLE="${ROTATION_ANGLE:-1.5707963267948966}"; RANDOM_ROTATION_SIGN=true; GRID_SHIFT_ENABLE=true
THERMOSTAT_ENABLE=true; THERMOSTAT_MODE=cell_relative_rescale; THERMOSTAT_EVERY=1; THERMOSTAT_TARGET_KBT="$KBT"; THERMOSTAT_MIN_PARTICLES=3
WEIGHTED_RESAMPLING_ENABLE_OVERRIDE=false; CUDA_EMPTY_REFILL_ENABLE_OVERRIDE=false; SPECIES_RESAMPLING_ENABLE=false
DUMP_ROLE_FILTER=all; SUMMARY_ROLE_FILTER=fluid; SUMMARY_EVERY="${SUMMARY_EVERY:-1}"; DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-1000}"; DARCY_COST_EVERY="${DARCY_COST_EVERY:-100}"
LIVE_PROGRESS="${LIVE_PROGRESS:-1}"; LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-1}"; LIVE_VIS_FIELD="${LIVE_VIS_FIELD:-rho}"; LIVE_VIS_EVERY="${LIVE_VIS_EVERY:-1}"; LIVE_VIS_NX="${LIVE_VIS_NX:-128}"; LIVE_VIS_NY="${LIVE_VIS_NY:-64}"; LIVE_VIS_HOLD_ON_EXIT="${LIVE_VIS_HOLD_ON_EXIT:-0}"
FILTERED_RECORDING_ENABLE="${FILTERED_RECORDING_ENABLE:-1}"; RECORD_ENABLE="${RECORD_ENABLE:-true}"; RECORD_FIELDS="${RECORD_FIELDS:-rho,ux,uy}"; RECORD_EVERY="${RECORD_EVERY:-10}"; FILTER_MODE="${FILTER_MODE:-none}"; FILTER_SAMPLE_EVERY="${FILTER_SAMPLE_EVERY:-100}"; PARTICLE_TYPE_FILTER="${PARTICLE_TYPE_FILTER:--1}"
BASE_RUN_ROOT="${BASE_RUN_ROOT:-runs/0493x17d_pressure_piston}"; CLEAN_RUN_ROOT="${CLEAN_RUN_ROOT:-1}"; PREFLIGHT_ONLY="${PREFLIGHT_ONLY:-0}"
# Variables expected by common helpers even though the custom state generator is used.
GEN_CASE=uniform; VELOCITY_MODE=zero; U0=0.0; BACKGROUND_TYPE=0; INACTIVE_TYPE=0; INACTIVE_SLOTS=0; SKIP_SOLID_CELLS=false; SKIP_SOLID_PARTICLES=false; REMOVE_MEAN_DRIFT=true
suite_defaults_common_0434; suite_compute_derived_0434; suite_validate_path_0434 "$MODE" || exit $?
RUN_ROOT="$BASE_RUN_ROOT/fresh"; if suite_truthy_0434 "$CLEAN_RUN_ROOT"; then rm -rf "$RUN_ROOT"; fi; suite_prepare_dirs_0434 "$RUN_ROOT"
STATE="$RUN_ROOT/init/${CASE_LABEL}_${NX}x${NY}_g${GAMMA_LEFT}_${GAMMA_RIGHT}.smpcd"; PARAMS="$RUN_ROOT/params/${CASE_LABEL}.kv"; OUT="$RUN_ROOT/output"; LOG="$RUN_ROOT/logs/${CASE_LABEL}.log"; TIMEFILE="$RUN_ROOT/logs/${CASE_LABEL}.time"; LIVE_VIS_CONTROL_FILE="$RUN_ROOT/params/${CASE_LABEL}_livevis_control.kv"; mkdir -p "$OUT"
python3 scripts/generate_0493x17d_piston_state.py --state "$STATE" --Lx "$Lx" --Ly "$Ly" --Nx "$NX" --Ny "$NY" --gamma-left "$GAMMA_LEFT" --gamma-right "$GAMMA_RIGHT" --split-x "$PISTON_CENTER_X" --kBT "$KBT" --mass "$PARTICLE_MASS" --seed "$SEED"
cat > "$PARAMS" <<PARAMS
inputState = $STATE
outputDir = $OUT
Lx = $Lx
Ly = $Ly
Nx = $NX
Ny = $NY
dt = $DT
nSteps = $STEPS
bcLeft = solid
bcRight = solid
bcBottom = periodic
bcTop = periodic
bcX = wall
bcY = periodic
openBoundarySegmentsEnable = false
openBoundarySegmentCount = 0
bodyAccelerationX = 0.0
bodyAccelerationY = 0.0
taylorGreenForcingEnable = false
wallAccommodation = 0.0
wallVpEnable = false
phaseInterfaceKineticReflectionFraction = 0.0
PARAMS
suite_write_common_params_0434 "$MODE" >> "$PARAMS"
cat >> "$PARAMS" <<PARAMS
darcyBrinkmanEnable = true
darcyChiMode = box
darcyBoxXMin = $SLAB_XMIN
darcyBoxXMax = $SLAB_XMAX
darcyBoxYMin = 0.0
darcyBoxYMax = $Ly
darcyInterfaceWidth = 0.0
darcyAlphaMin = 0.0
darcyAlphaMax = 0.0
darcyQ = 0.1
darcyUSolidX = 0.0
darcyUSolidY = 0.0
darcyCostEvery = $DARCY_COST_EVERY
darcyCostFilename = darcy_cost_0343.csv
darcyThreadsPerBlock = $DARCY_THREADS_PER_BLOCK
darcyInitialDeactivateBelowChi = $INITIAL_DEACTIVATE_BELOW_CHI
darcyBrinkmanForcingMode = mean
darcyChiCollisionVpEnable = false
chiKineticBoundaryMode = specular
chiSolidDynamicsEnable = true
chiSolidModel = rigid_slab_1d
chiSolidMass = $SOLID_MASS
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
suite_export_cuda_flags_0434 "$MODE" "$TOPOLOGY"; suite_export_livevis_0434; suite_write_env_file_0434 "$RUN_ROOT/logs/environment_0493x17d.env" "$MODE"
cat > "$RUN_ROOT/run_meta_0493x17d.txt" <<META
case=pressure_driven_rigid_piston
purpose=article-demonstrator-pressure-to-solid-motion
userGeometryInput=chi
initialPressureProxyGammaLeft=$GAMMA_LEFT
initialPressureProxyGammaRight=$GAMMA_RIGHT
pistonCenterX0=$PISTON_CENTER_X
pistonThicknessCells=$PISTON_THICKNESS_CELLS
solidMass=$SOLID_MASS
META
printf '\n===== 0493x17d PRESSURE-DRIVEN PISTON =====\n'; printf 'run=%s grid=%sx%s steps=%s gammaL/R=%s/%s pistonX0=%s M=%s\n\n' "$RUN_ROOT" "$NX" "$NY" "$STEPS" "$GAMMA_LEFT" "$GAMMA_RIGHT" "$PISTON_CENTER_X" "$SOLID_MASS"
suite_run_binary_0434 "$PARAMS" "$LOG" "$TIMEFILE" "$OUT" || exit $?
if suite_truthy_0434 "$PREFLIGHT_ONLY"; then exit 0; fi
for f in chi_kinetic_boundary_0493x16j.csv chi_penetration_0493x16l.csv chi_solid_dynamics_0493x16a.csv; do [[ -s "$OUT/$f" ]] || { echo "[0493x17d] ERROR missing $OUT/$f" >&2; exit 2; }; done
grep -q 'backend=x17a-lagrangian-edge-mesh' "$LOG" || { echo "[0493x17d] ERROR x17 backend marker absent" >&2; exit 2; }
echo "[0493x17d] COMPLETE piston run=$RUN_ROOT"
