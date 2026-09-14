#!/usr/bin/env bash

# 0493x16b — cell-resolved generic dynamic chi-solid load, RigidSlab1D qualifier.
# Physics: historical mean_outward_bath + chiVP closure, no permanent particle
# deactivation, no external/body force. The slab has only one mechanical DOF
# Xs(t); its shape/thickness are immutable by construction.
#
# New architecture under test:
#   SolidDynamics(q,qdot) -> SolidGeometry[chi(x,t),u_s(x,t)] -> MPCD
#   MPCD exact impulse -> opposite solid reaction -> SolidDynamics.advance()

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$ROOT/scripts/src_mpcd_run_common_0434.sh"
suite_root_cd_0434 || exit $?

CASE_LABEL="${CASE_LABEL:-0493x16b_spatial_solid_load}"
MODE="src"
TOPOLOGY="periodic"
GEN_CASE="uniform"

Lx="${Lx:-0.5}"
Ly="${Ly:-0.25}"
NX="${NX:-128}"
NY="${NY:-64}"
GAMMA="${GAMMA:-20}"
STEPS="${STEPS:-2000}"
DT="${DT:-0.002}"
KBT="${KBT:-0.125}"
SEED="${SEED:-4931601}"
PARTICLE_MASS="${PARTICLE_MASS:-1.0}"
U0=0.0
VELOCITY_MODE=zero
BACKGROUND_TYPE=0
INACTIVE_TYPE=0
INACTIVE_SLOTS=0
SKIP_SOLID_CELLS=false
SKIP_SOLID_PARTICLES=false

SLAB_CELLS="${SLAB_CELLS:-8}"
SOLID_MASS="${SOLID_MASS:-32768.0}"
SOLID_UX0="${SOLID_UX0:-0.02}"
ALPHA="${ALPHA:-800000.0}"
ALPHA_MIN=0.0
DARCY_Q="${DARCY_Q:-0.1}"
DARCY_BRINKMAN_FORCING_MODE=mean_outward_bath
DARCY_CHI_COLLISION_VP_ENABLE=true
DARCY_CHI_COLLISION_VP_MODE=interface_band
DARCY_CHI_COLLISION_VP_GAMMA=-1
DARCY_CHI_COLLISION_VP_MASS="$PARTICLE_MASS"
DARCY_CHI_COLLISION_VP_LAYERS="${DARCY_CHI_COLLISION_VP_LAYERS:-1}"
DARCY_CHI_COLLISION_VP_THRESHOLD="${DARCY_CHI_COLLISION_VP_THRESHOLD:-0.5}"
DARCY_CHI_COLLISION_VP_STRENGTH="${DARCY_CHI_COLLISION_VP_STRENGTH:-0.25}"
BODY_AX=0.0

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

SUMMARY_EVERY=1
DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-1000}"
DARCY_COST_EVERY=1
TOPO_BENCHMARK_ENABLE=true
TOPO_BENCHMARK_EVERY=1
TOPO_BENCHMARK_FILENAME=topo_benchmark_0493x16b.csv
TOPO_BENCHMARK_FORCE_ENABLE=true
TOPO_BENCHMARK_DRAG_LIFT_ENABLE=false

LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-1}"
LIVE_VIS_FIELD="${LIVE_VIS_FIELD:-ux}"
LIVE_VIS_EVERY="${LIVE_VIS_EVERY:-1}"
LIVE_VIS_NX="${LIVE_VIS_NX:-96}"
LIVE_VIS_NY="${LIVE_VIS_NY:-48}"
LIVE_VIS_HOLD_ON_EXIT="${LIVE_VIS_HOLD_ON_EXIT:-0}"
FILTERED_RECORDING_ENABLE="${FILTERED_RECORDING_ENABLE:-1}"
RECORD_ENABLE="${RECORD_ENABLE:-true}"
RECORD_FIELDS="${RECORD_FIELDS:-rho,ux,uy}"
RECORD_EVERY="${RECORD_EVERY:-100}"
FILTER_MODE="${FILTER_MODE:-none}"
FILTER_SAMPLE_EVERY="${FILTER_SAMPLE_EVERY:-100}"
PARTICLE_TYPE_FILTER="${PARTICLE_TYPE_FILTER:--1}"

RESTART="${RESTART:-0}"
RESTART_STATE="${RESTART_STATE:-}"
RESTART_TAG="${RESTART_TAG:-restart}"
BASE_RUN_ROOT="${BASE_RUN_ROOT:-runs/0493x16b_spatial_solid_load}"
CLEAN_RUN_ROOT="${CLEAN_RUN_ROOT:-1}"
PREFLIGHT_ONLY="${PREFLIGHT_ONLY:-0}"

suite_defaults_common_0434
suite_compute_derived_0434
suite_validate_path_0434 "$MODE" || exit $?

if (( NX < 32 || NY < 16 || SLAB_CELLS < 1 || SLAB_CELLS >= NX/2 )); then
  echo "[0493x16b] ERROR require NX>=32 NY>=16 and 1<=SLAB_CELLS<NX/2" >&2
  exit 2
fi

# Initial rigid geometry. The dynamics module subsequently owns the center;
# thickness is recovered once from these existing Darcy box parameters.
read -r SLAB_XMIN SLAB_XMAX <<EOF_GEOM
$(python3 - "$Lx" "$NX" "$SLAB_CELLS" <<'PY'
import sys
Lx=float(sys.argv[1]); nx=int(sys.argv[2]); cells=int(sys.argv[3])
dx=Lx/nx
w=cells*dx
c=0.5*Lx
print(f"{c-0.5*w:.17g} {c+0.5*w:.17g}")
PY
)
EOF_GEOM
INTERFACE_WIDTH="${INTERFACE_WIDTH:-0.0}"

if suite_truthy_0434 "$RESTART"; then
  if [[ -z "$RESTART_STATE" || ! -s "$RESTART_STATE" ]]; then
    echo "[0493x16b] ERROR RESTART=1 requires RESTART_STATE=/path/state_step_N.smpcd" >&2
    exit 2
  fi
  RUN_ROOT="$BASE_RUN_ROOT/$RESTART_TAG"
  INPUT_STATE="$RESTART_STATE"
  # Restore the solid DOF from the companion x16a diagnostic at the dump step.
  RESTART_STEP="$(basename "$RESTART_STATE" | sed -n 's/^state_step_0*\([0-9][0-9]*\)\.smpcd$/\1/p')"
  OLD_OUT="$(cd "$(dirname "$RESTART_STATE")" && pwd)"
  OLD_SOLID="$OLD_OUT/chi_solid_dynamics_0493x16a.csv"
  if [[ -z "$RESTART_STEP" || ! -s "$OLD_SOLID" ]]; then
    echo "[0493x16b] ERROR restart requires matching chi_solid_dynamics_0493x16a.csv" >&2
    exit 2
  fi
  read -r CENTER_RESTART SOLID_UX0 <<EOF_RST
$(python3 - "$OLD_SOLID" "$RESTART_STEP" <<'PY'
import csv, sys
path=sys.argv[1]; target=int(sys.argv[2]); row=None
with open(path, newline='') as f:
    for r in csv.DictReader(f):
        if int(float(r['step'])) == target:
            row=r
if row is None:
    raise SystemExit(f"missing solid row for step {target}")
print(row['centerXAfter'], row['velocityXAfter'])
PY
)
EOF_RST
  read -r SLAB_XMIN SLAB_XMAX <<EOF_REBOUNDS
$(python3 - "$CENTER_RESTART" "$Lx" "$NX" "$SLAB_CELLS" <<'PY'
import sys
c=float(sys.argv[1]); Lx=float(sys.argv[2]); nx=int(sys.argv[3]); cells=int(sys.argv[4])
w=cells*Lx/nx
print(f"{c-0.5*w:.17g} {c+0.5*w:.17g}")
PY
)
EOF_REBOUNDS
else
  RUN_ROOT="$BASE_RUN_ROOT/fresh"
  if suite_truthy_0434 "$CLEAN_RUN_ROOT"; then rm -rf "$RUN_ROOT"; fi
fi

suite_prepare_dirs_0434 "$RUN_ROOT"
STATE="$RUN_ROOT/init/${CASE_LABEL}_${NX}x${NY}_g${GAMMA}.smpcd"
PARAMS="$RUN_ROOT/params/${CASE_LABEL}.kv"
OUT="$RUN_ROOT/output"
LOG="$RUN_ROOT/logs/${CASE_LABEL}.log"
TIMEFILE="$RUN_ROOT/logs/${CASE_LABEL}.time"
LIVE_VIS_CONTROL_FILE="$RUN_ROOT/params/${CASE_LABEL}_livevis_control.kv"
mkdir -p "$OUT"

if ! suite_truthy_0434 "$RESTART"; then
  suite_generate_case_0434 "$STATE" "" || exit $?
  INPUT_STATE="$STATE"
fi

cat > "$PARAMS" <<PARAMS
inputState = $INPUT_STATE
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
PARAMS
suite_write_common_params_0434 "$MODE" >> "$PARAMS"
cat >> "$PARAMS" <<PARAMS
darcyBrinkmanEnable = true
darcyChiMode = box
darcyBoxXMin = $SLAB_XMIN
darcyBoxXMax = $SLAB_XMAX
darcyBoxYMin = 0.0
darcyBoxYMax = $Ly
darcyInterfaceWidth = $INTERFACE_WIDTH
darcyAlphaMin = $ALPHA_MIN
darcyAlphaMax = $ALPHA
darcyQ = $DARCY_Q
darcyUSolidX = $SOLID_UX0
darcyUSolidY = 0.0
darcyCostEvery = $DARCY_COST_EVERY
darcyCostFilename = darcy_cost_0343.csv
darcyThreadsPerBlock = $DARCY_THREADS_PER_BLOCK
darcyInitialDeactivateBelowChi = -1
darcyBrinkmanForcingMode = $DARCY_BRINKMAN_FORCING_MODE
darcyChiCollisionVpEnable = $DARCY_CHI_COLLISION_VP_ENABLE
darcyChiCollisionVpMode = $DARCY_CHI_COLLISION_VP_MODE
darcyChiCollisionVpGamma = $DARCY_CHI_COLLISION_VP_GAMMA
darcyChiCollisionVpMass = $DARCY_CHI_COLLISION_VP_MASS
darcyChiCollisionVpLayers = $DARCY_CHI_COLLISION_VP_LAYERS
darcyChiCollisionVpThreshold = $DARCY_CHI_COLLISION_VP_THRESHOLD
darcyChiCollisionVpStrength = $DARCY_CHI_COLLISION_VP_STRENGTH
topoBenchmarkEnable = $TOPO_BENCHMARK_ENABLE
topoBenchmarkEvery = $TOPO_BENCHMARK_EVERY
topoBenchmarkFilename = $TOPO_BENCHMARK_FILENAME
topoBenchmarkForceEnable = $TOPO_BENCHMARK_FORCE_ENABLE
topoBenchmarkDragLiftEnable = $TOPO_BENCHMARK_DRAG_LIFT_ENABLE
chiSolidDynamicsEnable = true
chiSolidModel = rigid_slab_1d
chiSolidMass = $SOLID_MASS
PARAMS

cat > "$LIVE_VIS_CONTROL_FILE" <<LIVEVIS_CONTROL_KV
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
LIVEVIS_CONTROL_KV

suite_export_cuda_flags_0434 "$MODE" "$TOPOLOGY"
# No x15 diagnostic env switch is required: dynamic coupling makes the exact
# impulse accounting part of the physics, not an optional diagnostic.
suite_export_livevis_0434
suite_write_env_file_0434 "$RUN_ROOT/logs/environment_0493x16b.env" "$MODE"

cat > "$RUN_ROOT/run_meta_0493x16b.txt" <<META
case=$CASE_LABEL
architecture=SolidDynamics_to_SolidGeometry_to_MPCD_cell_resolved_exact_impulse_feedback
solidModel=rigid_slab_1d
solidMass=$SOLID_MASS
solidUx0=$SOLID_UX0
slabCells=$SLAB_CELLS
slabXMin0=$SLAB_XMIN
slabXMax0=$SLAB_XMAX
interfaceWidth=$INTERFACE_WIDTH
alpha=$ALPHA
darcyMode=$DARCY_BRINKMAN_FORCING_MODE
chiVpStrength=$DARCY_CHI_COLLISION_VP_STRENGTH
initialDeactivate=-1
bodyAccelerationX=0
restart=$RESTART
inputState=$INPUT_STATE
livevisControl=$LIVE_VIS_CONTROL_FILE
META

printf '\n===== 0493x16b SPATIAL SOLID LOAD / RIGID SLAB 1D =====\n'
printf 'run=%s\n' "$RUN_ROOT"
printf 'grid=%sx%s gamma=%s dt=%s steps=%s\n' "$NX" "$NY" "$GAMMA" "$DT" "$STEPS"
printf 'solid: mass=%s Ux0=%s slab=%s cells alpha=%s\n' "$SOLID_MASS" "$SOLID_UX0" "$SLAB_CELLS" "$ALPHA"
printf 'closure=%s + chiVP(%s), initialDeactivate=-1, bodyAx=0\n' "$DARCY_BRINKMAN_FORCING_MODE" "$DARCY_CHI_COLLISION_VP_STRENGTH"
printf 'LiveVis+recorder control=%s\n' "$LIVE_VIS_CONTROL_FILE"
printf '===============================================================\n\n'

suite_run_binary_0434 "$PARAMS" "$LOG" "$TIMEFILE" "$OUT" || exit $?

if suite_truthy_0434 "$PREFLIGHT_ONLY"; then exit 0; fi
[[ -s "$OUT/chi_solid_dynamics_0493x16a.csv" ]] || { echo "[0493x16b] ERROR missing dynamic solid diagnostic" >&2; exit 2; }
[[ -s "$OUT/chi_solid_impulse_0493x15a.csv" ]] || { echo "[0493x16b] ERROR missing Darcy/bath impulse diagnostic" >&2; exit 2; }
[[ -s "$OUT/chi_vp_impulse_0493x15b.csv" ]] || { echo "[0493x16b] ERROR missing chiVP impulse diagnostic" >&2; exit 2; }
[[ -s "$OUT/summary_runtime.csv" ]] || { echo "[0493x16b] ERROR missing summary_runtime.csv" >&2; exit 2; }

echo "[0493x16b] COMPLETE run=$RUN_ROOT"
echo "[0493x16b] next: MATLAB analyze_0493x16b_spatial_solid_load('../runs/.../fresh')"
