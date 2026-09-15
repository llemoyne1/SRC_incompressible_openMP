#!/usr/bin/env bash
set -u

# 0493x17d membrane publication candidate.
# 0493x17d-fix4 smooth visible membrane tuning.
# Development grid is a physically scaled 2x refinement of the original
# 192x128 case.  The solid has the same order of physical area/mass but a longer
# span and a softer extensional law.  A small rotationally invariant bending
# rigidity suppresses one/two-edge folding modes while leaving smooth global
# curvature inexpensive.  The goal is deliberately a visibly deformed membrane.

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$ROOT/scripts/src_mpcd_run_common_0434.sh"
suite_root_cd_0434 || exit $?

CASE_LABEL="${CASE_LABEL:-0493x17d_visible_membrane_fix4}"
MODE="${MODE:-src-q6}"
TOPOLOGY=periodic
GEN_CASE=uniform

# Geometry / development resolution.  REFINE=2 is the fix3 candidate.
REFINE="${REFINE:-2}"
Lx="${Lx:-0.75}"; Ly="${Ly:-0.5}"
NX="${NX:-384}"; NY="${NY:-256}"
GAMMA="${GAMMA:-20}"
STEPS="${STEPS:-360}"
DT="${DT:-0.0005}"
KBT="${KBT:-0.03125}"
PARTICLE_MASS="${PARTICLE_MASS:-0.25}"
SEED="${SEED:-4931711}"

# Publication loading: same thermal speed as the coarse case, 1.5x mean flow.
FLOW_UX="${FLOW_UX:-0.16}"

H="$(python3 - "$Lx" "$Ly" "$NX" "$NY" <<'PY'
import sys
Lx,Ly=float(sys.argv[1]),float(sys.argv[2]); nx,ny=int(sys.argv[3]),int(sys.argv[4])
hx=Lx/nx; hy=Ly/ny
if abs(hx-hy) > 1e-12*max(hx,hy):
    raise SystemExit(f"0493x17d publication membrane requires square cells: hx={hx} hy={hy}")
print(f"{hx:.17g}")
PY
)"

MEMBRANE_CX="${MEMBRANE_CX:-0.375}"
# Eight cells total thickness at refine=2: restores the physical thickness
# of the original coarse/reference plate while keeping the longer span.
MEMBRANE_HALF_THICKNESS_CELLS="${MEMBRANE_HALF_THICKNESS_CELLS:-4.0}"
MEMBRANE_YMIN="${MEMBRANE_YMIN:-0.075}"
MEMBRANE_YMAX="${MEMBRANE_YMAX:-0.425}"
read -r BOX_XMIN BOX_XMAX < <(python3 - "$MEMBRANE_CX" "$MEMBRANE_HALF_THICKNESS_CELLS" "$H" <<'PY'
import sys
c=float(sys.argv[1]); q=float(sys.argv[2]); h=float(sys.argv[3])
print(f"{c-q*h:.17g} {c+q*h:.17g}")
PY
)

# Smooth visible-membrane tuning: extensional and area stiffness are restored
# enough to suppress local collapse, while angular bending makes one/two-edge
# folds expensive.  The long span and transverse loading still allow global bowing.
SOLID_MASS="${SOLID_MASS:-4096.0}"
MEMBRANE_K_STRETCH="${MEMBRANE_K_STRETCH:-300000.0}"
MEMBRANE_K_AREA="${MEMBRANE_K_AREA:-10000000.0}"
MEMBRANE_DAMPING="${MEMBRANE_DAMPING:-4000.0}"
MEMBRANE_K_BENDING="${MEMBRANE_K_BENDING:-0.002}"
# Same physical anchor-band width as 1.5 cells on the 192x128 reference grid.
MEMBRANE_ANCHOR_BAND_CELLS="${MEMBRANE_ANCHOR_BAND_CELLS:-3.0}"
# One nodal snapshot per integration step: required for topology validation.
MEMBRANE_OUTPUT_EVERY="${MEMBRANE_OUTPUT_EVERY:-1}"
INITIAL_DEACTIVATE_BELOW_CHI="${INITIAL_DEACTIVATE_BELOW_CHI:-0.5}"
DARCY_THREADS_PER_BLOCK="${DARCY_THREADS_PER_BLOCK:-256}"

VELOCITY_MODE=uniform_x; U0="$FLOW_UX"; BACKGROUND_TYPE=0; INACTIVE_TYPE=0; INACTIVE_SLOTS=0
SKIP_SOLID_CELLS=false; SKIP_SOLID_PARTICLES=false; REMOVE_MEAN_DRIFT=true
ROTATION_ANGLE="${ROTATION_ANGLE:-1.5707963267948966}"; RANDOM_ROTATION_SIGN=true; GRID_SHIFT_ENABLE=true
THERMOSTAT_ENABLE=true; THERMOSTAT_MODE=cell_relative_rescale; THERMOSTAT_EVERY=1
THERMOSTAT_TARGET_KBT="$KBT"; THERMOSTAT_MIN_PARTICLES=3
WEIGHTED_RESAMPLING_ENABLE_OVERRIDE=false; CUDA_EMPTY_REFILL_ENABLE_OVERRIDE=false; SPECIES_RESAMPLING_ENABLE=false
DUMP_ROLE_FILTER=all; SUMMARY_ROLE_FILTER=fluid
SUMMARY_EVERY="${SUMMARY_EVERY:-30}"
DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-600}"
DARCY_COST_EVERY="${DARCY_COST_EVERY:-100}"
ALLOW_LARGE_DUMPS="${ALLOW_LARGE_DUMPS:-1}"; export ALLOW_LARGE_DUMPS
LIVE_PROGRESS="${LIVE_PROGRESS:-1}"; LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-1}"; LIVE_VIS_FIELD="${LIVE_VIS_FIELD:-ux}"
LIVE_VIS_EVERY="${LIVE_VIS_EVERY:-1}"; LIVE_VIS_NX="${LIVE_VIS_NX:-256}"; LIVE_VIS_NY="${LIVE_VIS_NY:-171}"; LIVE_VIS_HOLD_ON_EXIT="${LIVE_VIS_HOLD_ON_EXIT:-0}"
FILTERED_RECORDING_ENABLE="${FILTERED_RECORDING_ENABLE:-1}"; RECORD_ENABLE="${RECORD_ENABLE:-true}"
RECORD_FIELDS="${RECORD_FIELDS:-rho,ux,uy}"; RECORD_EVERY="${RECORD_EVERY:-40}"; FILTER_MODE="${FILTER_MODE:-none}"; FILTER_SAMPLE_EVERY="${FILTER_SAMPLE_EVERY:-100}"; PARTICLE_TYPE_FILTER="${PARTICLE_TYPE_FILTER:--1}"

BASE_RUN_ROOT="${BASE_RUN_ROOT:-runs/0493x17d_visible_membrane_fix4}"
CLEAN_RUN_ROOT="${CLEAN_RUN_ROOT:-1}"; PREFLIGHT_ONLY="${PREFLIGHT_ONLY:-0}"; ANALYZE_AFTER_RUN="${ANALYZE_AFTER_RUN:-0}"

suite_defaults_common_0434
suite_compute_derived_0434
suite_validate_path_0434 "$MODE" || exit $?

python3 - "$REFINE" "$Lx" "$Ly" "$NX" "$NY" "$H" "$DT" "$KBT" "$PARTICLE_MASS" \
  "$BOX_XMIN" "$BOX_XMAX" "$MEMBRANE_YMIN" "$MEMBRANE_YMAX" \
  "$MEMBRANE_K_STRETCH" "$MEMBRANE_K_BENDING" "$SOLID_MASS" <<'PY'
import math,sys
(r,Lx,Ly,nx,ny,h,dt,kbt,m,xmin,xmax,ymin,ymax,ks,kb,ms) = map(float,sys.argv[1:])
nx=int(nx); ny=int(ny)
if int(r)!=2 or nx!=384 or ny!=256:
    print("[0493x17d-pub] NOTE non-reference resolution/REFINE override; validate scaling explicitly")
if not (0 < xmin < xmax < Lx and 0 < ymin < ymax < Ly):
    raise SystemExit("0493x17d publication membrane must be internal")
if min(xmin,Lx-xmax,ymin,Ly-ymax) <= 8*h:
    raise SystemExit("0493x17d publication membrane requires >8h periodic-seam margin")
if xmax-xmin < 4*h:
    raise SystemExit("0493x17d publication membrane requires >=4h total thickness")
# Conservative pre-run estimate using perimeter/h nodes. Runtime CSV reports exact S.
perim=2*((xmax-xmin)+(ymax-ymin)); n_est=max(4,perim/h); node_mass=ms/n_est
Sstretch=dt*math.sqrt(ks/node_mass)
Sbend=4.0*dt*math.sqrt(kb/(node_mass*h**3)) if kb>0 else 0.0
S=max(Sstretch,Sbend)
print(f"[0493x17d-pub] h={h:.9g} thickness/h={(xmax-xmin)/h:.6g} span/h={(ymax-ymin)/h:.6g}")
print(f"[0493x17d-pub] estimatedNodes={n_est:.1f} estimatedNodeMass={node_mass:.6g} "
      f"stretchStability={Sstretch:.6g} bendingStability={Sbend:.6g}")
if S >= 0.5:
    raise SystemExit(f"0493x17d publication membrane estimated explicit stability number too large: {S}")
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
chiSolidMembraneBendingStiffness = $MEMBRANE_K_BENDING
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

cat > "$RUN_ROOT/run_meta_0493x17d_membrane_publishable.txt" <<META
case=fixed_deformable_membrane_publishable
purpose=article-demonstrator-visible-validated-flexible-solid
referenceCoarseGrid=192x128
refinementFactor=$REFINE
Lx=$Lx
Ly=$Ly
Nx=$NX
Ny=$NY
h=$H
gamma=$GAMMA
dt=$DT
kBT=$KBT
particleMass=$PARTICLE_MASS
steps=$STEPS
flowUx=$FLOW_UX
userGeometryInput=chi
initialGeometry=thin-box
materialBoundary=initial-chi-0.5-contour
geometryAuthorityAfterInitialization=Lagrangian-nodes
support=y-extrema-clamped
boxXMin=$BOX_XMIN
boxXMax=$BOX_XMAX
boxYMin=$MEMBRANE_YMIN
boxYMax=$MEMBRANE_YMAX
membraneSpan=$(python3 - <<PY
print(${MEMBRANE_YMAX}-${MEMBRANE_YMIN})
PY
)
halfThicknessCells=$MEMBRANE_HALF_THICKNESS_CELLS
anchorBandCells=$MEMBRANE_ANCHOR_BAND_CELLS
solidMass=$SOLID_MASS
kStretch=$MEMBRANE_K_STRETCH
kArea=$MEMBRANE_K_AREA
damping=$MEMBRANE_DAMPING
bendingStiffness=$MEMBRANE_K_BENDING
nodeSnapshotEvery=$MEMBRANE_OUTPUT_EVERY
META

printf '\n===== 0493x17d PUBLISHABLE FIXED MEMBRANE =====\n'
printf 'run=%s grid=%sx%s h=%s steps=%s dt=%s flowUx=%s\n' "$RUN_ROOT" "$NX" "$NY" "$H" "$STEPS" "$DT" "$FLOW_UX"
printf 'box=[%s,%s]x[%s,%s] thickness/h=%s anchorBand/h=%s\n' "$BOX_XMIN" "$BOX_XMAX" "$MEMBRANE_YMIN" "$MEMBRANE_YMAX" "$(python3 - <<PY
print((${BOX_XMAX}-${BOX_XMIN})/${H})
PY
)" "$MEMBRANE_ANCHOR_BAND_CELLS"
printf 'fluid gamma=%s kBT=%s particleMass=%s\n' "$GAMMA" "$KBT" "$PARTICLE_MASS"
printf 'membrane M=%s kS=%s kA=%s damping=%s bending=%s\n\n' "$SOLID_MASS" "$MEMBRANE_K_STRETCH" "$MEMBRANE_K_AREA" "$MEMBRANE_DAMPING" "$MEMBRANE_K_BENDING"

suite_run_binary_0434 "$PARAMS" "$LOG" "$TIMEFILE" "$OUT" || exit $?
if suite_truthy_0434 "$PREFLIGHT_ONLY"; then exit 0; fi
for f in chi_membrane_0493x17c.csv chi_membrane_nodes_0493x17c.csv chi_kinetic_boundary_0493x16j.csv chi_penetration_0493x16l.csv chi_solid_dynamics_0493x16a.csv; do
  [[ -s "$OUT/$f" ]] || { echo "[0493x17d-pub] ERROR missing $OUT/$f" >&2; exit 2; }
done
grep -q 'anchorMode=y_extrema' "$LOG" || { echo "[0493x17d-pub] ERROR anchored membrane runtime marker absent" >&2; exit 2; }
grep -q 'measure=closed-loop-parity+nearest-edge-depth' "$LOG" || { echo "[0493x17d-pub] ERROR corrected Lagrangian penetration marker absent" >&2; exit 2; }

if suite_truthy_0434 "$ANALYZE_AFTER_RUN"; then
  echo "[0493x17d-pub] simulation COMPLETE; running publication validation"
  python3 scripts/analyze_0493x17d_fixed_membrane_publishable.py --root "$BASE_RUN_ROOT"
  python3 scripts/plot_0493x17d_fixed_membrane_publishable.py --root "$BASE_RUN_ROOT"
else
  echo "[0493x17d-pub] simulation COMPLETE; ANALYZE_AFTER_RUN=0"
fi
echo "[0493x17d-pub] COMPLETE run=$RUN_ROOT"
