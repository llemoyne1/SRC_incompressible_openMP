#!/usr/bin/env bash

# 0493x16g — diagnostic ablation of the mask-capture impulse on RigidSlab1D.
# Keeps x16f historical binary chi + post-stream temporal synchronization, then
# applies the historical outward bath unchanged and removes only the collective
# x-velocity increment of particles in cells newly swallowed by the mask.
# The fluid and solid start with exactly the same prescribed mean x velocity;
# the thermal realization is otherwise generated identically for rest/boost cases.
# Physics: historical mean_outward_bath + chiVP closure, no permanent particle
# deactivation, no external/body force. The slab has only one mechanical DOF
# Xs(t); its shape/thickness are immutable by construction.
#
# Architecture under test:
#   prepare: publish historical binary chi(q^n) on device
#   stream particles to x^{n+1}
#   poststream: drift q^{n+1,*}=q^n+dt*qdot^n and republish SAME binary chi
#   collision + historical Darcy/outward_bath/chiVP
#   x16g: on newly-solid cells only, subtract J_bath,x/M_capture from that
#         captured population after the bath; no transverse correction
#   exact cell load(device) -> kick qdot^{n+1}; no second positional drift

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$ROOT/scripts/src_mpcd_run_common_0434.sh"
suite_root_cd_0434 || exit $?

CASE_LABEL="${CASE_LABEL:-0493x16g_capture_bath_neutralized_galilean_case}"
MODE="src"
TOPOLOGY="periodic"
GEN_CASE="uniform"

Lx="${Lx:-0.5}"
Ly="${Ly:-0.25}"
NX="${NX:-128}"
NY="${NY:-64}"
GAMMA="${GAMMA:-20}"
STEPS="${STEPS:-3000}"
DT="${DT:-0.002}"
KBT="${KBT:-0.125}"
SEED="${SEED:-4931601}"
PARTICLE_MASS="${PARTICLE_MASS:-1.0}"
COMMON_UX="${COMMON_UX:-0.08}"
U0="$COMMON_UX"
VELOCITY_MODE=uniform_x
BACKGROUND_TYPE=0
INACTIVE_TYPE=0
INACTIVE_SLOTS=0
SKIP_SOLID_CELLS=false
SKIP_SOLID_PARTICLES=false

SLAB_CELLS="${SLAB_CELLS:-8}"
SOLID_MASS="${SOLID_MASS:-32768.0}"
SOLID_UX0="$COMMON_UX"
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
TOPO_BENCHMARK_FILENAME=topo_benchmark_0493x16g.csv
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
BASE_RUN_ROOT="${BASE_RUN_ROOT:-runs/0493x16g_capture_bath_neutralized_galilean_case}"
CLEAN_RUN_ROOT="${CLEAN_RUN_ROOT:-1}"
PREFLIGHT_ONLY="${PREFLIGHT_ONLY:-0}"

suite_defaults_common_0434
suite_compute_derived_0434
suite_validate_path_0434 "$MODE" || exit $?

if (( NX < 32 || NY < 16 || SLAB_CELLS < 1 || SLAB_CELLS >= NX/2 )); then
  echo "[0493x16g] ERROR require NX>=32 NY>=16 and 1<=SLAB_CELLS<NX/2" >&2
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
    echo "[0493x16g] ERROR RESTART=1 requires RESTART_STATE=/path/state_step_N.smpcd" >&2
    exit 2
  fi
  RUN_ROOT="$BASE_RUN_ROOT/$RESTART_TAG"
  INPUT_STATE="$RESTART_STATE"
  # Restore the solid DOF from the companion x16a diagnostic at the dump step.
  RESTART_STEP="$(basename "$RESTART_STATE" | sed -n 's/^state_step_0*\([0-9][0-9]*\)\.smpcd$/\1/p')"
  OLD_OUT="$(cd "$(dirname "$RESTART_STATE")" && pwd)"
  OLD_SOLID="$OLD_OUT/chi_solid_dynamics_0493x16a.csv"
  if [[ -z "$RESTART_STEP" || ! -s "$OLD_SOLID" ]]; then
    echo "[0493x16g] ERROR restart requires matching chi_solid_dynamics_0493x16a.csv" >&2
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
# x16g is an explicitly gated diagnostic ablation. Other runs with the same
# binary remain on the x16f path unless this environment variable is set.
export SRC_X16G_CAPTURE_BATH_MEAN_NEUTRALIZE=1
# No x15 diagnostic env switch is required: dynamic coupling makes the exact
# impulse accounting part of the physics, not an optional diagnostic.
suite_export_livevis_0434
suite_write_env_file_0434 "$RUN_ROOT/logs/environment_0493x16g.env" "$MODE"

cat > "$RUN_ROOT/run_meta_0493x16g.txt" <<META
case=$CASE_LABEL
architecture=cuda_resident_historical_binary_poststream_sync_capture_bath_mean_neutralization
solidModel=rigid_slab_1d
solidMass=$SOLID_MASS
solidUx0=$SOLID_UX0
fluidMeanUx0=$U0
commonUx0=$COMMON_UX
velocityMode=$VELOCITY_MODE
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

printf '\n===== 0493x16g CAPTURE-BATH-MEAN-NEUTRALIZATION GALILEAN / RIGID SLAB 1D =====\n'
printf 'run=%s\n' "$RUN_ROOT"
printf 'grid=%sx%s gamma=%s dt=%s steps=%s\n' "$NX" "$NY" "$GAMMA" "$DT" "$STEPS"
printf 'solid: mass=%s Ux0=%s slab=%s cells alpha=%s\n' "$SOLID_MASS" "$SOLID_UX0" "$SLAB_CELLS" "$ALPHA"
printf 'fluid initialization: velocityMode=%s U0=%s (common translation)\n' "$VELOCITY_MODE" "$U0"
printf 'closure=%s + chiVP(%s), initialDeactivate=-1, bodyAx=0\n' "$DARCY_BRINKMAN_FORCING_MODE" "$DARCY_CHI_COLLISION_VP_STRENGTH"
printf 'LiveVis+recorder control=%s\n' "$LIVE_VIS_CONTROL_FILE"
printf '===============================================================\n\n'

suite_run_binary_0434 "$PARAMS" "$LOG" "$TIMEFILE" "$OUT" || exit $?

if suite_truthy_0434 "$PREFLIGHT_ONLY"; then exit 0; fi
[[ -s "$OUT/chi_solid_dynamics_0493x16a.csv" ]] || { echo "[0493x16g] ERROR missing dynamic solid diagnostic" >&2; exit 2; }
[[ -s "$OUT/chi_solid_impulse_0493x15a.csv" ]] || { echo "[0493x16g] ERROR missing Darcy/bath impulse diagnostic" >&2; exit 2; }
[[ -s "$OUT/chi_vp_impulse_0493x15b.csv" ]] || { echo "[0493x16g] ERROR missing chiVP impulse diagnostic" >&2; exit 2; }
[[ -s "$OUT/summary_runtime.csv" ]] || { echo "[0493x16g] ERROR missing summary_runtime.csv" >&2; exit 2; }
head -n 1 "$OUT/chi_solid_impulse_0493x15a.csv" | grep -q 'captureBathMeanNeutralization0493x16g' || {
  echo "[0493x16g] ERROR binary/output does not contain x16g capture-bath diagnostics" >&2
  exit 2
}
python3 - "$OUT/chi_solid_impulse_0493x15a.csv" <<'PY_X16G'
import csv, sys
p=sys.argv[1]
with open(p, newline='') as f:
    rows=list(csv.DictReader(f))
if not rows:
    raise SystemExit('[0493x16g] ERROR empty chi-solid impulse CSV')
key='captureBathMeanNeutralization0493x16g'
if key not in rows[0]:
    raise SystemExit(f'[0493x16g] ERROR missing {key}')
if any(int(float(r[key])) != 1 for r in rows):
    raise SystemExit('[0493x16g] ERROR capture-bath neutralization gate not active on every row')
print('[0493x16g] capture-bath mean-neutralization gate PASS')
PY_X16G
head -n 1 "$OUT/chi_solid_dynamics_0493x16a.csv" | grep -q 'fictitiousFluidDiagnostic0493x16c' || {
  echo "[0493x16g] ERROR binary/output does not contain x16c fictitious-fluid diagnostics" >&2
  exit 2
}

python3 - "$OUT/chi_solid_dynamics_0493x16a.csv" <<'PY_RESIDENT'
import csv, sys
p=sys.argv[1]
with open(p, newline='') as f:
    rows=list(csv.DictReader(f))
if not rows:
    raise SystemExit('[0493x16g] ERROR empty chi-solid dynamics CSV')
required=['cudaResidentSolid0493x16e','subcellRaster0493x16e',
          'sampledSolidVolumeRelativeError0493x16e',
          'hostGeometryFieldUploadBytes0493x16e','hostLoadFieldDownloadBytes0493x16e',
          'historicalBinaryMask0493x16f','poststreamTemporalSync0493x16f','poststreamDriftX0493x16f']
for key in required:
    if key not in rows[0]:
        raise SystemExit(f'[0493x16g] ERROR missing resident column {key}')
if any(int(float(r['cudaResidentSolid0493x16e'])) != 1 for r in rows):
    raise SystemExit('[0493x16g] ERROR non-resident solid row detected')
if any(int(float(r['subcellRaster0493x16e'])) != 0 for r in rows):
    raise SystemExit('[0493x16g] ERROR subcell raster unexpectedly active')
if any(int(float(r['historicalBinaryMask0493x16f'])) != 1 for r in rows):
    raise SystemExit('[0493x16g] ERROR historical binary mask not active')
if any(int(float(r['poststreamTemporalSync0493x16f'])) != 1 for r in rows):
    raise SystemExit('[0493x16g] ERROR poststream temporal sync not active')
if any(int(float(r['hostGeometryFieldUploadBytes0493x16e'])) != 0 or
       int(float(r['hostLoadFieldDownloadBytes0493x16e'])) != 0 for r in rows):
    raise SystemExit('[0493x16g] ERROR full-grid host traffic detected')
print('[0493x16g] resident/historical-binary/poststream-sync/full-grid-transfer checks PASS')
PY_RESIDENT

echo "[0493x16g] COMPLETE run=$RUN_ROOT"
echo "[0493x16g] case complete; run the pair analyzer after both rest and boost cases"
