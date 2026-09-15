#!/usr/bin/env bash
set -euo pipefail

# 0493x17d — article demonstrator A: a thin material membrane/strip is
# clamped at its two y-extrema and bows under a transverse fluid stream.
# Geometry input remains chi (analytic box here; file mode is equally valid).

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$ROOT/scripts/src_mpcd_run_common_0434.sh"
suite_root_cd_0434 || exit $?

CASE_LABEL="${CASE_LABEL:-0493x17d_fixed_membrane}"
MODE="${MODE:-src-q6}"
TOPOLOGY=periodic
GEN_CASE=uniform

Lx="${Lx:-0.75}"; Ly="${Ly:-0.5}"; NX="${NX:-576}"; NY="${NY:-384}"
GAMMA="${GAMMA:-20}"; STEPS="${STEPS:-6000}"; DT="${DT:-0.002}"
KBT="${KBT:-0.125}"; SEED="${SEED:-4931711}"; PARTICLE_MASS="${PARTICLE_MASS:-1.0}"
FLOW_UX="${FLOW_UX:-0.18}"
H="$(python3 - "$Lx" "$Ly" "$NX" "$NY" <<'PY'
import sys
Lx,Ly=float(sys.argv[1]),float(sys.argv[2]); nx,ny=int(sys.argv[3]),int(sys.argv[4])
print(f"{min(Lx/nx,Ly/ny):.17g}")
PY
)"
MEMBRANE_CX="${MEMBRANE_CX:-0.375}"
MEMBRANE_HALF_THICKNESS_CELLS="${MEMBRANE_HALF_THICKNESS_CELLS:-2.0}"
MEMBRANE_YMIN="${MEMBRANE_YMIN:-0.125}"
MEMBRANE_YMAX="${MEMBRANE_YMAX:-0.375}"
read -r BOX_XMIN BOX_XMAX < <(python3 - "$MEMBRANE_CX" "$MEMBRANE_HALF_THICKNESS_CELLS" "$H" <<'PY'
import sys
c=float(sys.argv[1]); q=float(sys.argv[2]); h=float(sys.argv[3])
print(f"{c-q*h:.17g} {c+q*h:.17g}")
PY
)
SOLID_MASS="${SOLID_MASS:-4096.0}"
MEMBRANE_K_STRETCH="${MEMBRANE_K_STRETCH:-500000.0}"
MEMBRANE_K_AREA="${MEMBRANE_K_AREA:-10000000.0}"
MEMBRANE_DAMPING="${MEMBRANE_DAMPING:-500.0}"
MEMBRANE_ANCHOR_BAND_CELLS="${MEMBRANE_ANCHOR_BAND_CELLS:-1.5}"
MEMBRANE_OUTPUT_EVERY="${MEMBRANE_OUTPUT_EVERY:-10}"
INITIAL_DEACTIVATE_BELOW_CHI="${INITIAL_DEACTIVATE_BELOW_CHI:-0.5}"
DARCY_THREADS_PER_BLOCK="${DARCY_THREADS_PER_BLOCK:-256}"

VELOCITY_MODE=uniform_x; U0="$FLOW_UX"; BACKGROUND_TYPE=0; INACTIVE_TYPE=0; INACTIVE_SLOTS=0
SKIP_SOLID_CELLS=false; SKIP_SOLID_PARTICLES=false; REMOVE_MEAN_DRIFT=true
ROTATION_ANGLE="${ROTATION_ANGLE:-1.5707963267948966}"; RANDOM_ROTATION_SIGN=true; GRID_SHIFT_ENABLE=true
THERMOSTAT_ENABLE=true; THERMOSTAT_MODE=cell_relative_rescale; THERMOSTAT_EVERY=1
THERMOSTAT_TARGET_KBT="$KBT"; THERMOSTAT_MIN_PARTICLES=3
WEIGHTED_RESAMPLING_ENABLE_OVERRIDE=false; CUDA_EMPTY_REFILL_ENABLE_OVERRIDE=false; SPECIES_RESAMPLING_ENABLE=false
DUMP_ROLE_FILTER=all; SUMMARY_ROLE_FILTER=fluid
SUMMARY_EVERY="${SUMMARY_EVERY:-1}"; DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-1000}"; DARCY_COST_EVERY="${DARCY_COST_EVERY:-100}"
LIVE_PROGRESS="${LIVE_PROGRESS:-1}"; LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-1}"; LIVE_VIS_FIELD="${LIVE_VIS_FIELD:-rho}"
LIVE_VIS_EVERY="${LIVE_VIS_EVERY:-1}"; LIVE_VIS_NX="${LIVE_VIS_NX:-576}"; LIVE_VIS_NY="${LIVE_VIS_NY:-384}"; LIVE_VIS_HOLD_ON_EXIT="${LIVE_VIS_HOLD_ON_EXIT:-0}"
FILTERED_RECORDING_ENABLE="${FILTERED_RECORDING_ENABLE:-1}"; RECORD_ENABLE="${RECORD_ENABLE:-true}"
RECORD_FIELDS="${RECORD_FIELDS:-rho,ux,uy}"; RECORD_EVERY="${RECORD_EVERY:-10}"; FILTER_MODE="${FILTER_MODE:-none}"; FILTER_SAMPLE_EVERY="${FILTER_SAMPLE_EVERY:-100}"; PARTICLE_TYPE_FILTER="${PARTICLE_TYPE_FILTER:--1}"

BASE_RUN_ROOT="${BASE_RUN_ROOT:-runs/0493x17d_fixed_membrane}"
CLEAN_RUN_ROOT="${CLEAN_RUN_ROOT:-1}"; PREFLIGHT_ONLY="${PREFLIGHT_ONLY:-0}"

suite_defaults_common_0434
suite_compute_derived_0434
suite_validate_path_0434 "$MODE" || exit $?

python3 - "$BOX_XMIN" "$BOX_XMAX" "$MEMBRANE_YMIN" "$MEMBRANE_YMAX" "$Lx" "$Ly" "$H" <<'PY'
import sys
xmin,xmax,ymin,ymax,Lx,Ly,h=map(float,sys.argv[1:])
if not (0 < xmin < xmax < Lx and 0 < ymin < ymax < Ly): raise SystemExit("0493x17d fixed membrane must be internal")
if min(xmin,Lx-xmax,ymin,Ly-ymax) <= 4*h: raise SystemExit("0493x17d fixed membrane requires >4h periodic-seam margin")
if xmax-xmin < 2*h: raise SystemExit("0493x17d fixed membrane thickness must be >=2h")
PY

RUN_ROOT="$BASE_RUN_ROOT/fresh"
if suite_truthy_0434 "$CLEAN_RUN_ROOT"; then rm -rf "$RUN_ROOT"; fi
suite_prepare_dirs_0434 "$RUN_ROOT"
STATE="$RUN_ROOT/init/${CASE_LABEL}_${NX}x${NY}_g${GAMMA}.smpcd"
PARAMS="$RUN_ROOT/params/${CASE_LABEL}.kv"; OUT="$RUN_ROOT/output"; LOG="$RUN_ROOT/logs/${CASE_LABEL}.log"; TIMEFILE="$RUN_ROOT/logs/${CASE_LABEL}.time"
LIVE_VIS_CONTROL_FILE="$RUN_ROOT/params/${CASE_LABEL}_livevis_control.kv"; mkdir -p "$OUT"
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
darcyChiMode = box
darcyBoxXMin = $BOX_XMIN
darcyBoxXMax = $BOX_XMAX
darcyBoxYMin = $MEMBRANE_YMIN
darcyBoxYMax = $MEMBRANE_YMAX
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
chiSolidModel = membrane_2d
chiSolidMass = $SOLID_MASS
chiSolidMembraneStretchStiffness = $MEMBRANE_K_STRETCH
chiSolidMembraneAreaStiffness = $MEMBRANE_K_AREA
chiSolidMembraneDamping = $MEMBRANE_DAMPING
chiSolidMembraneOutputEvery = $MEMBRANE_OUTPUT_EVERY
chiSolidMembraneAnchorMode = y_extrema
chiSolidMembraneAnchorBandCells = $MEMBRANE_ANCHOR_BAND_CELLS
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
unset SRC_X16G_CAPTURE_BATH_MEAN_NEUTRALIZE SRC_X16H_CAPTURE_SPATIAL_REINJECT SRC_X16I_IMPERMEABLE_EXCLUSION_MODE SRC_X16I_PRESCRIBED_DEFORMABLE SRC_X16I_STATIC_CURVED_0493X16M
suite_export_livevis_0434
suite_write_env_file_0434 "$RUN_ROOT/logs/environment_0493x17d.env" "$MODE"

cat > "$RUN_ROOT/run_meta_0493x17d.txt" <<META
case=fixed_deformable_membrane
purpose=article-demonstrator-fixed-flexible-solid
userGeometryInput=chi
initialGeometry=thin-box
materialBoundary=initial-chi-0.5-contour
geometryAuthorityAfterInitialization=Lagrangian-nodes
support=y-extrema-clamped
flowUx=$FLOW_UX
boxXMin=$BOX_XMIN
boxXMax=$BOX_XMAX
boxYMin=$MEMBRANE_YMIN
boxYMax=$MEMBRANE_YMAX
anchorBandCells=$MEMBRANE_ANCHOR_BAND_CELLS
META

printf '\n===== 0493x17d FIXED DEFORMABLE MEMBRANE =====\n'
printf 'run=%s grid=%sx%s steps=%s flowUx=%s box=[%s,%s]x[%s,%s] anchorBand/h=%s\n' "$RUN_ROOT" "$NX" "$NY" "$STEPS" "$FLOW_UX" "$BOX_XMIN" "$BOX_XMAX" "$MEMBRANE_YMIN" "$MEMBRANE_YMAX" "$MEMBRANE_ANCHOR_BAND_CELLS"
printf 'M=%s kS=%s kA=%s damping=%s\n\n' "$SOLID_MASS" "$MEMBRANE_K_STRETCH" "$MEMBRANE_K_AREA" "$MEMBRANE_DAMPING"

suite_run_binary_0434 "$PARAMS" "$LOG" "$TIMEFILE" "$OUT" || exit $?
if suite_truthy_0434 "$PREFLIGHT_ONLY"; then exit 0; fi
for f in chi_membrane_0493x17c.csv chi_membrane_nodes_0493x17c.csv chi_kinetic_boundary_0493x16j.csv chi_penetration_0493x16l.csv chi_solid_dynamics_0493x16a.csv; do
  [[ -s "$OUT/$f" ]] || { echo "[0493x17d] ERROR missing $OUT/$f" >&2; exit 2; }
done
grep -q 'anchorMode=y_extrema' "$LOG" || { echo "[0493x17d] ERROR anchored membrane runtime marker absent" >&2; exit 2; }
grep -q 'measure=closed-loop-parity+nearest-edge-depth' "$LOG" || { echo "[0493x17d] ERROR corrected Lagrangian penetration marker absent" >&2; exit 2; }
echo "[0493x17d] COMPLETE fixed membrane run=$RUN_ROOT"
