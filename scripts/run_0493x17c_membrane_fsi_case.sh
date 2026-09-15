#!/usr/bin/env bash
set -euo pipefail

# 0493x17c — true fluid-coupled elastic membrane demonstrator.
# User geometry remains chi.  The initial chi=0.5 circle is extracted once as
# a persistent Lagrangian closed loop.  The loop then evolves from fluid impact
# impulses + edge elasticity + area conservation; chi is never re-extracted.

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$ROOT/scripts/src_mpcd_run_common_0434.sh"
suite_root_cd_0434 || exit $?

CASE_LABEL="${CASE_LABEL:-0493x17c_membrane_fsi}"
FRAME_LABEL="${FRAME_LABEL:-rest}"
MODE="${MODE:-src-q6}"
TOPOLOGY=periodic
GEN_CASE=uniform

Lx="${Lx:-0.75}"
Ly="${Ly:-0.5}"
NX="${NX:-192}"
NY="${NY:-128}"
GAMMA="${GAMMA:-20}"
STEPS="${STEPS:-800}"
DT="${DT:-0.002}"
KBT="${KBT:-0.125}"
SEED="${SEED:-4931703}"
PARTICLE_MASS="${PARTICLE_MASS:-1.0}"

RELATIVE_UX="${RELATIVE_UX:-0.08}"
BOOST_UX="${BOOST_UX:-0.0}"
FLUID_UX="$(python3 - "$RELATIVE_UX" "$BOOST_UX" <<'PY'
import sys
print(f"{float(sys.argv[1])+float(sys.argv[2]):.17g}")
PY
)"
SOLID_UX="$BOOST_UX"

CIRCLE_CX="${CIRCLE_CX:-0.375}"
CIRCLE_CY="${CIRCLE_CY:-0.25}"
CIRCLE_R="${CIRCLE_R:-0.078125}"
SOLID_MASS="${SOLID_MASS:-8192.0}"
MEMBRANE_K_STRETCH="${MEMBRANE_K_STRETCH:-200000.0}"
MEMBRANE_K_AREA="${MEMBRANE_K_AREA:-200000.0}"
MEMBRANE_DAMPING="${MEMBRANE_DAMPING:-500.0}"
MEMBRANE_OUTPUT_EVERY="${MEMBRANE_OUTPUT_EVERY:-40}"
INITIAL_DEACTIVATE_BELOW_CHI="${INITIAL_DEACTIVATE_BELOW_CHI:-0.5}"
DARCY_THREADS_PER_BLOCK="${DARCY_THREADS_PER_BLOCK:-256}"

VELOCITY_MODE=uniform_x
U0="$FLUID_UX"
BACKGROUND_TYPE=0
INACTIVE_TYPE=0
INACTIVE_SLOTS=0
SKIP_SOLID_CELLS=false
SKIP_SOLID_PARTICLES=false
REMOVE_MEAN_DRIFT=true

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

SUMMARY_EVERY="${SUMMARY_EVERY:-1}"
DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-1000}"
DARCY_COST_EVERY="${DARCY_COST_EVERY:-100}"
LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-1}"
LIVE_VIS_FIELD="${LIVE_VIS_FIELD:-rho}"
LIVE_VIS_EVERY="${LIVE_VIS_EVERY:-1}"
LIVE_VIS_NX="${LIVE_VIS_NX:-128}"
LIVE_VIS_NY="${LIVE_VIS_NY:-86}"
LIVE_VIS_HOLD_ON_EXIT="${LIVE_VIS_HOLD_ON_EXIT:-0}"
FILTERED_RECORDING_ENABLE="${FILTERED_RECORDING_ENABLE:-1}"
RECORD_ENABLE="${RECORD_ENABLE:-true}"
# 0432 has no chi field. Membrane geometry is recorded by the x17c nodal CSV.
RECORD_FIELDS="${RECORD_FIELDS:-rho,ux,uy}"
RECORD_EVERY="${RECORD_EVERY:-20}"
FILTER_MODE="${FILTER_MODE:-none}"
FILTER_SAMPLE_EVERY="${FILTER_SAMPLE_EVERY:-100}"
PARTICLE_TYPE_FILTER="${PARTICLE_TYPE_FILTER:--1}"

BASE_RUN_ROOT="${BASE_RUN_ROOT:-runs/0493x17c_membrane_fsi/${FRAME_LABEL}}"
CLEAN_RUN_ROOT="${CLEAN_RUN_ROOT:-1}"
PREFLIGHT_ONLY="${PREFLIGHT_ONLY:-0}"

suite_defaults_common_0434
suite_compute_derived_0434
suite_validate_path_0434 "$MODE" || exit $?

python3 - "$Lx" "$Ly" "$CIRCLE_CX" "$CIRCLE_CY" "$CIRCLE_R" "$NX" "$NY" <<'PY'
import sys
Lx,Ly,cx,cy,r=map(float,sys.argv[1:6]); nx=int(sys.argv[6]); ny=int(sys.argv[7])
if not (r>0 and r<min(Lx,Ly)/2):
    raise SystemExit("0493x17c invalid circle radius")
margin=min(cx-r,Lx-(cx+r),cy-r,Ly-(cy+r))
if margin <= 4.0*min(Lx/nx,Ly/ny):
    raise SystemExit("0493x17c first article case requires an internal closed contour away from periodic seams")
PY

RUN_ROOT="$BASE_RUN_ROOT/fresh"
if suite_truthy_0434 "$CLEAN_RUN_ROOT"; then rm -rf "$RUN_ROOT"; fi
suite_prepare_dirs_0434 "$RUN_ROOT"
STATE="$RUN_ROOT/init/${CASE_LABEL}_${FRAME_LABEL}_${NX}x${NY}_g${GAMMA}.smpcd"
PARAMS="$RUN_ROOT/params/${CASE_LABEL}_${FRAME_LABEL}.kv"
OUT="$RUN_ROOT/output"
LOG="$RUN_ROOT/logs/${CASE_LABEL}_${FRAME_LABEL}.log"
TIMEFILE="$RUN_ROOT/logs/${CASE_LABEL}_${FRAME_LABEL}.time"
LIVE_VIS_CONTROL_FILE="$RUN_ROOT/params/${CASE_LABEL}_${FRAME_LABEL}_livevis_control.kv"
mkdir -p "$OUT"

suite_generate_case_0434 "$STATE" "" || exit $?

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
bcBottom = periodic
bcTop = periodic
bcX = periodic
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
darcyChiMode = circle
darcyCircleCx = $CIRCLE_CX
darcyCircleCy = $CIRCLE_CY
darcyCircleR = $CIRCLE_R
darcyInterfaceWidth = 0.0
darcyAlphaMin = 0.0
darcyAlphaMax = 0.0
darcyQ = 0.1
darcyUSolidX = $SOLID_UX
darcyUSolidY = 0.0
darcyCostEvery = $DARCY_COST_EVERY
darcyCostFilename = darcy_cost_0343.csv
darcyThreadsPerBlock = $DARCY_THREADS_PER_BLOCK
darcyInitialDeactivateBelowChi = $INITIAL_DEACTIVATE_BELOW_CHI
darcyBrinkmanForcingMode = mean
darcyChiCollisionVpEnable = false
chiKineticBoundaryMode = specular
chiSolidDynamicsEnable = true
chiSolidModel = membrane_2d
chiSolidMass = $SOLID_MASS
chiSolidMembraneStretchStiffness = $MEMBRANE_K_STRETCH
chiSolidMembraneAreaStiffness = $MEMBRANE_K_AREA
chiSolidMembraneDamping = $MEMBRANE_DAMPING
chiSolidMembraneOutputEvery = $MEMBRANE_OUTPUT_EVERY
PARAMS

cat > "$LIVE_VIS_CONTROL_FILE" <<LIVEVIS_CONTROL_KV
recordEnable = ${RECORD_ENABLE}
recordSession = ${CASE_LABEL}_${FRAME_LABEL}_${MODE}
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
LIVEVIS_CONTROL_KV

suite_export_cuda_flags_0434 "$MODE" "$TOPOLOGY"
unset SRC_X16G_CAPTURE_BATH_MEAN_NEUTRALIZE
unset SRC_X16H_CAPTURE_SPATIAL_REINJECT
unset SRC_X16I_IMPERMEABLE_EXCLUSION_MODE
unset SRC_X16I_PRESCRIBED_DEFORMABLE
unset SRC_X16I_DEFORM_AMPLITUDE_CELLS
unset SRC_X16I_DEFORM_PERIOD_STEPS
unset SRC_X16I_STATIC_CURVED_0493X16M
suite_export_livevis_0434
suite_write_env_file_0434 "$RUN_ROOT/logs/environment_0493x17c.env" "$MODE"

cat > "$RUN_ROOT/run_meta_0493x17c.txt" <<META
case=$CASE_LABEL
frame=$FRAME_LABEL
purpose=article-demonstrator-fluid-coupled-elastic-membrane
userGeometryInput=chi
initialGeometry=circle-chi
materialBoundary=initial-chi-0.5-contour
geometryAuthorityAfterInitialization=Lagrangian-nodes
collision=space-time-moving-segment-quadratic
response=local-frame-specular
mechanics=edge-spring+area-penalty+edge-dashpot
coupling=direct-impact-linear-edge-shape-functions
relativeFluidVelocityX=$RELATIVE_UX
commonBoostX=$BOOST_UX
fluidVelocityX0=$FLUID_UX
solidVelocityX0=$SOLID_UX
circleCx=$CIRCLE_CX
circleCy=$CIRCLE_CY
circleR=$CIRCLE_R
solidMass=$SOLID_MASS
stretchStiffness=$MEMBRANE_K_STRETCH
areaStiffness=$MEMBRANE_K_AREA
damping=$MEMBRANE_DAMPING
initialDeactivateBelowChi=$INITIAL_DEACTIVATE_BELOW_CHI
runtimeRemap=none
chiReextract=never
META

printf '\n===== 0493x17c ELASTIC MEMBRANE FSI — %s =====\n' "$FRAME_LABEL"
printf 'run=%s mode=%s grid=%sx%s gamma=%s steps=%s dt=%s\n' "$RUN_ROOT" "$MODE" "$NX" "$NY" "$GAMMA" "$STEPS" "$DT"
printf 'relativeUx=%s boostUx=%s fluidUx0=%s solidUx0=%s\n' "$RELATIVE_UX" "$BOOST_UX" "$FLUID_UX" "$SOLID_UX"
printf 'chi circle=(%s,%s) R=%s; membrane M=%s kS=%s kA=%s damping=%s\n' "$CIRCLE_CX" "$CIRCLE_CY" "$CIRCLE_R" "$SOLID_MASS" "$MEMBRANE_K_STRETCH" "$MEMBRANE_K_AREA" "$MEMBRANE_DAMPING"
printf 'recorder fields=%s (membrane nodes recorded separately)\n' "$RECORD_FIELDS"
printf '=================================================\n\n'

suite_run_binary_0434 "$PARAMS" "$LOG" "$TIMEFILE" "$OUT" || exit $?
if suite_truthy_0434 "$PREFLIGHT_ONLY"; then exit 0; fi

for f in \
  chi_membrane_0493x17c.csv \
  chi_membrane_nodes_0493x17c.csv \
  chi_membrane_initial_0493x17c.csv \
  chi_kinetic_boundary_0493x16j.csv \
  chi_penetration_0493x16l.csv \
  chi_solid_dynamics_0493x16a.csv; do
  [[ -s "$OUT/$f" ]] || { echo "[0493x17c] ERROR missing $OUT/$f" >&2; exit 2; }
done

grep -q '\[0493x17c-membrane\] model=membrane_2d' "$LOG" || {
  echo "[0493x17c] ERROR membrane runtime marker absent" >&2; exit 2; }
grep -q 'backend=x17a-lagrangian-edge-mesh' "$LOG" || {
  echo "[0493x17c] ERROR x17 Lagrangian collision backend marker absent" >&2; exit 2; }

echo "[0493x17c] COMPLETE frame=$FRAME_LABEL run=$RUN_ROOT"
