#!/usr/bin/env bash
set -u

# 0493x18a — rigid finite-thickness hinged plate, one DOF theta_z.
# Initial plate hangs vertically from a fixed top-center hinge. Gravity acts on
# the solid only (y), while the fluid is initialized with a uniform x crossflow.
# The plate angle is NOT prescribed: it follows from hydrodynamic torque,
# gravity and viscous hinge damping.

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$ROOT/scripts/src_mpcd_run_common_0434.sh"
suite_root_cd_0434 || exit $?

CASE_LABEL="${CASE_LABEL:-0493x18a_hinged_plate}"
MODE="${MODE:-src-q6}"
# x18f: default to a non-recycling streamwise boundary.  The historical
# periodic-x channel remains available as an explicit comparison mode.
HINGED_X_BOUNDARY_MODE="${HINGED_X_BOUNDARY_MODE:-inlet_neumann}"
case "$HINGED_X_BOUNDARY_MODE" in
  inlet_neumann|double_neumann) TOPOLOGY=segmented ;;
  periodic|periodic_channel) TOPOLOGY=wall ;;
  *)
    echo "[0493x18f] ERROR HINGED_X_BOUNDARY_MODE must be inlet_neumann, double_neumann, or periodic" >&2
    exit 2
    ;;
esac
if [[ "$HINGED_X_BOUNDARY_MODE" == double_neumann ]] && ! suite_path_has_q6_0434 "$MODE"; then
  echo "[0493x18f] ERROR double_neumann is supported only on the resident Q6 path" >&2
  exit 2
fi
GEN_CASE=uniform

Lx="${Lx:-0.75}"; Ly="${Ly:-0.5}"
NX="${NX:-288}"; NY="${NY:-192}"
GAMMA="${GAMMA:-20}"
STEPS="${STEPS:-2000}"
DT="${DT:-0.006}"
KBT="${KBT:-0.05555555555555556}"
PARTICLE_MASS="${PARTICLE_MASS:-0.4444444444444444}"
SEED="${SEED:-4931801}"
FLOW_UX="${FLOW_UX:-0.0352}"

H="$(python3 - "$Lx" "$Ly" "$NX" "$NY" <<'PY'
import sys
Lx,Ly=float(sys.argv[1]),float(sys.argv[2]); nx,ny=int(sys.argv[3]),int(sys.argv[4])
hx=Lx/nx; hy=Ly/ny
if abs(hx-hy)>1e-12*max(hx,hy):
    raise SystemExit(f"0493x18a requires square cells: hx={hx} hy={hy}")
print(f"{hx:.17g}")
PY
)"

PLATE_CX="${PLATE_CX:-0.375}"
PLATE_LENGTH="${PLATE_LENGTH:-0.40}"
PLATE_TOP_Y="${PLATE_TOP_Y:-0.45}"
PLATE_HALF_THICKNESS_CELLS="${PLATE_HALF_THICKNESS_CELLS:-3.0}"
read -r BOX_XMIN BOX_XMAX BOX_YMIN BOX_YMAX < <(python3 - "$PLATE_CX" "$PLATE_LENGTH" "$PLATE_TOP_Y" "$PLATE_HALF_THICKNESS_CELLS" "$H" <<'PY'
import sys
cx,L,yt,q,h=map(float,sys.argv[1:])
print(f"{cx-q*h:.17g} {cx+q*h:.17g} {yt-L:.17g} {yt:.17g}")
PY
)

SOLID_MASS="${SOLID_MASS:-105.0}"
HINGED_GRAVITY_Y="${HINGED_GRAVITY_Y:--5.0}"
HINGED_ANGULAR_DAMPING="${HINGED_ANGULAR_DAMPING:-80.0}"
HINGED_INITIAL_ANGLE="${HINGED_INITIAL_ANGLE:-0.0}"
HINGED_INITIAL_OMEGA="${HINGED_INITIAL_OMEGA:-0.0}"
HINGED_OUTPUT_EVERY="${HINGED_OUTPUT_EVERY:-1}"
INITIAL_DEACTIVATE_BELOW_CHI="${INITIAL_DEACTIVATE_BELOW_CHI:-0.5}"
# x18a-fix2 integrated permanently: for a non-zero initial angle the material
# wall is rotated after extracting the vertical reference chi.  Excise the
# fluid in the same rotated geometry and disable the obsolete vertical chi hole.
HINGED_INITIAL_FLUID_GEOMETRY="${HINGED_INITIAL_FLUID_GEOMETRY:-auto}"
case "$HINGED_INITIAL_FLUID_GEOMETRY" in
  auto)
    HINGED_ROTATED_INITIAL_EXCLUSION="$(python3 - "$HINGED_INITIAL_ANGLE" <<'PYANGLE'
import math,sys
v=float(sys.argv[1])
print(1 if math.isfinite(v) and abs(v)>1.0e-14 else 0)
PYANGLE
)"
    ;;
  1|true|TRUE|yes|YES|on|ON) HINGED_ROTATED_INITIAL_EXCLUSION=1 ;;
  0|false|FALSE|no|NO|off|OFF) HINGED_ROTATED_INITIAL_EXCLUSION=0 ;;
  *) echo "[0493x18f] ERROR HINGED_INITIAL_FLUID_GEOMETRY must be auto/on/off" >&2; exit 2 ;;
esac
if [[ "$HINGED_ROTATED_INITIAL_EXCLUSION" == 1 ]]; then
  INITIAL_DEACTIVATE_BELOW_CHI=-1.0
fi
DARCY_THREADS_PER_BLOCK="${DARCY_THREADS_PER_BLOCK:-256}"

# Full-height hard-density inlet used by inlet_neumann.  These settings are
# harmless in double_neumann mode (there is no inlet segment); the Neumann
# kinetic bath remains the exterior continuation on both outlet faces.
INLET_RESERVOIR_CELLS="${INLET_RESERVOIR_CELLS:-6}"
INLET_THERMAL_NOISE="${INLET_THERMAL_NOISE:-1.0}"
SOLID_QUALIFICATION_DIAGNOSTICS="${SOLID_QUALIFICATION_DIAGNOSTICS:-false}"

VELOCITY_MODE=uniform_x; U0="$FLOW_UX"; BACKGROUND_TYPE=0; INACTIVE_TYPE=0
if [[ "$TOPOLOGY" == segmented ]]; then
  # Neumann kinetic continuation and hard-density inlet insertion need a tail
  # pool.  Match the established open-boundary production runners rather than
  # the zero-slot periodic demonstrator.
  INACTIVE_SLOTS_CELL_FRACTION="${INACTIVE_SLOTS_CELL_FRACTION:-1.0}"
  INACTIVE_SLOTS="${INACTIVE_SLOTS:-}"
else
  INACTIVE_SLOTS="${INACTIVE_SLOTS:-0}"
fi
SKIP_SOLID_CELLS=false; SKIP_SOLID_PARTICLES=false; REMOVE_MEAN_DRIFT=true
ROTATION_ANGLE="${ROTATION_ANGLE:-1.5707963267948966}"; RANDOM_ROTATION_SIGN=true; GRID_SHIFT_ENABLE=true
THERMOSTAT_ENABLE=true; THERMOSTAT_MODE=cell_relative_rescale; THERMOSTAT_EVERY=1
THERMOSTAT_TARGET_KBT="$KBT"; THERMOSTAT_MIN_PARTICLES=3
WEIGHTED_RESAMPLING_ENABLE_OVERRIDE=false; CUDA_EMPTY_REFILL_ENABLE_OVERRIDE=false; SPECIES_RESAMPLING_ENABLE=false
DUMP_ROLE_FILTER=all; SUMMARY_ROLE_FILTER=fluid
SUMMARY_EVERY="${SUMMARY_EVERY:-50}"
DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-0}"
DARCY_COST_EVERY="${DARCY_COST_EVERY:-100}"
ALLOW_LARGE_DUMPS="${ALLOW_LARGE_DUMPS:-1}"; export ALLOW_LARGE_DUMPS
LIVE_PROGRESS="${LIVE_PROGRESS:-1}"; LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-1}"; LIVE_VIS_FIELD="${LIVE_VIS_FIELD:-ux}"
LIVE_VIS_EVERY="${LIVE_VIS_EVERY:-1}"; LIVE_VIS_NX="${LIVE_VIS_NX:-288}"; LIVE_VIS_NY="${LIVE_VIS_NY:-192}"; LIVE_VIS_HOLD_ON_EXIT="${LIVE_VIS_HOLD_ON_EXIT:-0}"
FILTERED_RECORDING_ENABLE="${FILTERED_RECORDING_ENABLE:-1}"; RECORD_ENABLE="${RECORD_ENABLE:-true}"
RECORD_FIELDS="${RECORD_FIELDS:-rho,ux,uy,n}"; RECORD_EVERY="${RECORD_EVERY:-5}"; FILTER_MODE="${FILTER_MODE:-none}"; FILTER_SAMPLE_EVERY="${FILTER_SAMPLE_EVERY:-100}"; PARTICLE_TYPE_FILTER="${PARTICLE_TYPE_FILTER:--1}"

BASE_RUN_ROOT="${BASE_RUN_ROOT:-runs/0493x18a_hinged_plate}"
CLEAN_RUN_ROOT="${CLEAN_RUN_ROOT:-1}"; PREFLIGHT_ONLY="${PREFLIGHT_ONLY:-0}"

suite_defaults_common_0434
suite_compute_derived_0434
suite_validate_path_0434 "$MODE" || exit $?

python3 - "$Lx" "$Ly" "$H" "$DT" "$BOX_XMIN" "$BOX_XMAX" "$BOX_YMIN" "$BOX_YMAX" "$SOLID_MASS" "$HINGED_GRAVITY_Y" "$HINGED_ANGULAR_DAMPING" <<'PY'
import math,sys
Lx,Ly,h,dt,x0,x1,y0,y1,m,g,c=map(float,sys.argv[1:])
L=y1-y0; t=x1-x0
if not (0<x0<x1<Lx and 0<y0<y1<Ly): raise SystemExit("0493x18a plate must be internal")
if L<=t: raise SystemExit("0493x18a plate must be longer than it is thick")
if min(x0,Lx-x1,y0,Ly-y1)<=8*h: raise SystemExit("0493x18a requires >8h domain-boundary margin")
I=m*(L*L/3.0+t*t/12.0)
kgrav=m*abs(g)*L/2.0
wn=math.sqrt(kgrav/I) if kgrav>0 else 0.0
zeta=c/(2*math.sqrt(kgrav*I)) if kgrav>0 else 0.0
print(f"[0493x18a] h={h:.9g} length/h={L/h:.3f} thickness/h={t/h:.3f}")
print(f"[0493x18a] analytic rectangle inertia={I:.9g} gravityLinearStiffness={kgrav:.9g} omega_n={wn:.6g} dampingRatio={zeta:.4g} dt*omega_n={dt*wn:.5g}")
PY

RUN_ROOT="$BASE_RUN_ROOT/fresh"
if suite_truthy_0434 "$CLEAN_RUN_ROOT"; then rm -rf "$RUN_ROOT"; fi
suite_prepare_dirs_0434 "$RUN_ROOT"
STATE="$RUN_ROOT/init/${CASE_LABEL}_${NX}x${NY}_g${GAMMA}.smpcd"
PARAMS="$RUN_ROOT/params/${CASE_LABEL}.kv"; OUT="$RUN_ROOT/output"; LOG="$RUN_ROOT/logs/${CASE_LABEL}.log"; TIMEFILE="$RUN_ROOT/logs/${CASE_LABEL}.time"
LIVE_VIS_CONTROL_FILE="$RUN_ROOT/params/${CASE_LABEL}_livevis_control.kv"; mkdir -p "$OUT"
suite_generate_case_0434 "$STATE" "" || exit $?
if [[ "$HINGED_ROTATED_INITIAL_EXCLUSION" == 1 ]]; then
  if [[ ! -f "$ROOT/scripts/prepare_0493x18a_initial_fluid.py" ]]; then
    echo "[0493x18f] ERROR missing scripts/prepare_0493x18a_initial_fluid.py" >&2
    exit 2
  fi
  python3 "$ROOT/scripts/prepare_0493x18a_initial_fluid.py" \
    --state "$STATE" --Lx "$Lx" --Ly "$Ly" --Nx "$NX" --Ny "$NY" \
    --box-xmin "$BOX_XMIN" --box-xmax "$BOX_XMAX" \
    --box-ymin "$BOX_YMIN" --box-ymax "$BOX_YMAX" \
    --angle "$HINGED_INITIAL_ANGLE" || exit $?
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
# x18f boundary block is appended immediately below according to
# HINGED_X_BOUNDARY_MODE.
bodyAccelerationX = 0.0
bodyAccelerationY = 0.0
taylorGreenForcingEnable = false
wallAccommodation = 0.0
wallVpEnable = false
phaseInterfaceKineticReflectionFraction = 0.0
PARAMS

case "$HINGED_X_BOUNDARY_MODE" in
  inlet_neumann)
    cat >> "$PARAMS" <<PARAMS
bcLeft = solid
bcRight = solid
bcBottom = solid
bcTop = solid
bcX = solid
bcY = solid
wallThermalNoise = 0
openBoundarySegmentsEnable = true
openBoundarySegmentCount = 2
openBoundarySegment0 = left inlet 0.0 1.0 $FLOW_UX 0.0 0 $PARTICLE_MASS
openBoundarySegment1 = right outlet 0.0 1.0 $FLOW_UX 0.0 0 $PARTICLE_MASS
inletVelocityRampEnable = true
inletVelocityRampStartTime = 0.0
inletVelocityRampEndTime = 0.0
inletVelocityRampInitialFactor = 1.0
inletVelocityRampFinalFactor = 1.0
inletVelocityRampProfile = smoothstep
inletVelocitySpatialProfile = uniform
inletKBT = $KBT
inletThermalNoise = $INLET_THERMAL_NOISE
inletInjectionMode = hard_cell_density
inletReservoirMode = hard_cell_density
inletReservoirCells = $INLET_RESERVOIR_CELLS
inletTargetOccupancy = $GAMMA
inletHardCellVelocityMean = true
inletHardCellThermalRescale = true
inletRandomizeTangential = true
inletReinjectBackflow = true
openBoundaryOutletMode = neumann
openBoundaryOutletHybridBlend = 0.0
openBoundaryOutletFeedbackGain = 0.0
PARAMS
    ;;
  double_neumann)
    cat >> "$PARAMS" <<PARAMS
bcLeft = solid
bcRight = solid
bcBottom = solid
bcTop = solid
bcX = solid
bcY = solid
wallThermalNoise = 0
openBoundarySegmentsEnable = true
openBoundarySegmentCount = 2
openBoundarySegment0 = left outlet 0.0 1.0 0.0 0.0 0 $PARTICLE_MASS
openBoundarySegment1 = right outlet 0.0 1.0 0.0 0.0 0 $PARTICLE_MASS
inletVelocitySpatialProfile = uniform
inletKBT = $KBT
inletThermalNoise = $INLET_THERMAL_NOISE
inletInjectionMode = hard_cell_density
inletReservoirMode = hard_cell_density
inletReservoirCells = $INLET_RESERVOIR_CELLS
inletTargetOccupancy = $GAMMA
inletHardCellVelocityMean = true
inletHardCellThermalRescale = true
inletRandomizeTangential = true
inletReinjectBackflow = true
openBoundaryOutletMode = neumann
openBoundaryOutletHybridBlend = 0.0
openBoundaryOutletFeedbackGain = 0.0
PARAMS
    ;;
  periodic|periodic_channel)
    cat >> "$PARAMS" <<PARAMS
bcLeft = periodic
bcRight = periodic
bcBottom = solid
bcTop = solid
bcX = periodic
bcY = solid
wallThermalNoise = 0
openBoundarySegmentsEnable = false
openBoundarySegmentCount = 0
PARAMS
    ;;
esac

suite_write_common_params_0434 "$MODE" >> "$PARAMS"
cat >> "$PARAMS" <<PARAMS
darcyBrinkmanEnable = true
darcyChiMode = box
darcyBoxXMin = $BOX_XMIN
darcyBoxXMax = $BOX_XMAX
darcyBoxYMin = $BOX_YMIN
darcyBoxYMax = $BOX_YMAX
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
chiSolidModel = hinged_plate_2d
chiSolidMass = $SOLID_MASS
chiSolidHingedGravityY = $HINGED_GRAVITY_Y
chiSolidHingedAngularDamping = $HINGED_ANGULAR_DAMPING
chiSolidHingedInitialAngle = $HINGED_INITIAL_ANGLE
chiSolidHingedInitialOmega = $HINGED_INITIAL_OMEGA
chiSolidHingedOutputEvery = $HINGED_OUTPUT_EVERY
chiSolidQualificationDiagnosticsEnable = $SOLID_QUALIFICATION_DIAGNOSTICS
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
suite_write_env_file_0434 "$RUN_ROOT/logs/environment_0493x18a.env" "$MODE"

cat > "$RUN_ROOT/run_meta_0493x18a_hinged_plate.txt" <<META
case=hinged_plate_2d
purpose=one-dof-fluid-solid-interaction-angle-vs-crossflow
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
boxXMin=$BOX_XMIN
boxXMax=$BOX_XMAX
boxYMin=$BOX_YMIN
boxYMax=$BOX_YMAX
pivotMode=top-center
solidMass=$SOLID_MASS
gravityY=$HINGED_GRAVITY_Y
angularDamping=$HINGED_ANGULAR_DAMPING
initialAngle=$HINGED_INITIAL_ANGLE
initialOmega=$HINGED_INITIAL_OMEGA
xBoundaryMode=$HINGED_X_BOUNDARY_MODE
inletReservoirCells=$INLET_RESERVOIR_CELLS
inletThermalNoise=$INLET_THERMAL_NOISE
initialFluidGeometry=$HINGED_INITIAL_FLUID_GEOMETRY
rotatedInitialExclusion=$HINGED_ROTATED_INITIAL_EXCLUSION
initialDeactivateBelowChi=$INITIAL_DEACTIVATE_BELOW_CHI
qualificationDiagnostics=$SOLID_QUALIFICATION_DIAGNOSTICS
inactiveSlots=$INACTIVE_SLOTS
META

printf '\n===== 0493x18a HINGED PLATE 1-DOF =====\n'
printf 'run=%s grid=%sx%s h=%s steps=%s dt=%s flowUx=%s xBoundary=%s\n' "$RUN_ROOT" "$NX" "$NY" "$H" "$STEPS" "$DT" "$FLOW_UX" "$HINGED_X_BOUNDARY_MODE"
printf 'plate=[%s,%s]x[%s,%s] mass=%s gravityY=%s angularDamping=%s\n' "$BOX_XMIN" "$BOX_XMAX" "$BOX_YMIN" "$BOX_YMAX" "$SOLID_MASS" "$HINGED_GRAVITY_Y" "$HINGED_ANGULAR_DAMPING"

suite_run_binary_0434 "$PARAMS" "$LOG" "$TIMEFILE" "$OUT" || exit $?
if suite_truthy_0434 "$PREFLIGHT_ONLY"; then
  echo "[0493x18a] PREFLIGHT_ONLY=1 complete"
  exit 0
fi

if [ ! -s "$OUT/chi_hinged_plate_0493x18a.csv" ]; then
  echo "[0493x18f] ERROR missing/empty $OUT/chi_hinged_plate_0493x18a.csv" >&2
  exit 2
fi
if suite_truthy_0434 "$SOLID_QUALIFICATION_DIAGNOSTICS"; then
  for f in chi_hinged_plate_nodes_0493x18a.csv chi_kinetic_boundary_0493x16j.csv; do
    if [ ! -s "$OUT/$f" ]; then
      echo "[0493x18f] ERROR qualification diagnostics requested but missing/empty $OUT/$f" >&2
      exit 2
    fi
  done
fi

echo "[0493x18a] COMPLETE run=$RUN_ROOT"
