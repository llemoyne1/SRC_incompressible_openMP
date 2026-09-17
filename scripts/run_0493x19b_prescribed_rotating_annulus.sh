#!/usr/bin/env bash
# 0493x19b — prescribed rotating inner cylinder in a concentric annulus.
# The x17 geometry is stationary; only the material velocity of the inner
# Lagrangian branch is prescribed as Omega ez x r.  The outer branch is fixed.
# specular is the zero-tangential-traction control; bounceback is the x19a
# deterministic full-accommodation response.

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$ROOT/scripts/src_mpcd_run_common_0434.sh"
suite_root_cd_0434 || exit $?

KINETIC_MODE="${KINETIC_MODE:-bounceback}"
CASE_LABEL="${CASE_LABEL:-0493x19b_${KINETIC_MODE}}"
BASE_RUN_ROOT="${BASE_RUN_ROOT:-runs/0493x19b_prescribed_rotating_annulus_pair/${KINETIC_MODE}}"
MODE="${MODE:-src-q6}"
TOPOLOGY="periodic"
GEN_CASE="uniform"

Lx="${Lx:-1.0}"
Ly="${Ly:-1.0}"
NX="${NX:-256}"
NY="${NY:-256}"
GAMMA="${GAMMA:-12}"
STEPS="${STEPS:-15000}"
DT="${DT:-0.006}"
KBT="${KBT:-0.05}"
SEED="${SEED:-4931902}"
PARTICLE_MASS="${PARTICLE_MASS:-1.0}"
CENTER_X="${CENTER_X:-0.5}"
CENTER_Y="${CENTER_Y:-0.5}"
INNER_RADIUS="${INNER_RADIUS:-0.20}"
OUTER_RADIUS="${OUTER_RADIUS:-0.35}"
OMEGA_Z="${OMEGA_Z:-0.05}"
CHI_INTERFACE_CELLS="${CHI_INTERFACE_CELLS:-1.0}"
INITIAL_DEACTIVATE_BELOW_CHI="${INITIAL_DEACTIVATE_BELOW_CHI:-0.5}"
DARCY_THREADS_PER_BLOCK="${DARCY_THREADS_PER_BLOCK:-256}"

SUMMARY_EVERY="${SUMMARY_EVERY:-10}"
DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-1000}"
LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-1}"
LIVE_VIS_FIELD="${LIVE_VIS_FIELD:-vorticity}"
LIVE_VIS_EVERY="${LIVE_VIS_EVERY:-1}"
LIVE_VIS_NX="${LIVE_VIS_NX:-96}"
LIVE_VIS_NY="${LIVE_VIS_NY:-96}"
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
SKIP_SOLID_CELLS=false
SKIP_SOLID_PARTICLES=false
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
  *) echo "[0493x19b] ERROR KINETIC_MODE must be specular or bounceback" >&2; exit 2 ;;
esac

python3 - "$Lx" "$Ly" "$NX" "$NY" "$CENTER_X" "$CENTER_Y" "$INNER_RADIUS" "$OUTER_RADIUS" "$OMEGA_Z" <<'PY'
import sys, math
Lx,Ly=float(sys.argv[1]),float(sys.argv[2])
nx,ny=int(sys.argv[3]),int(sys.argv[4])
cx,cy=float(sys.argv[5]),float(sys.argv[6])
ri,ro,om=float(sys.argv[7]),float(sys.argv[8]),float(sys.argv[9])
h=min(Lx/nx,Ly/ny)
if nx < 64 or ny < 64:
    raise SystemExit('[0493x19b] require NX,NY >= 64')
if abs(Lx-Ly) > 1e-12*max(Lx,Ly):
    raise SystemExit('[0493x19b] first annulus qualification requires Lx=Ly')
clearance=min(cx,Lx-cx,cy,Ly-cy)
if not (ri > 12*h and ro-ri > 16*h and clearance > ro+6*h):
    raise SystemExit('[0493x19b] require Ri>12h, gap>16h, and the full outer circle at least 6h from the periodic box edge')
if not math.isfinite(om) or om == 0.0:
    raise SystemExit('[0493x19b] OMEGA_Z must be finite and non-zero')
PY

RUN_ROOT="$BASE_RUN_ROOT/fresh"
if suite_truthy_0434 "$CLEAN_RUN_ROOT"; then rm -rf "$RUN_ROOT"; fi
suite_prepare_dirs_0434 "$RUN_ROOT"
STATE="$RUN_ROOT/init/${CASE_LABEL}_${NX}x${NY}_g${GAMMA}.smpcd"
CHI_FILE="$RUN_ROOT/init/${CASE_LABEL}_annulus_chi_f32.bin"
PARAMS="$RUN_ROOT/params/${CASE_LABEL}.kv"
OUT="$RUN_ROOT/output"
LOG="$RUN_ROOT/logs/${CASE_LABEL}.log"
TIMEFILE="$RUN_ROOT/logs/${CASE_LABEL}.time"
LIVE_VIS_CONTROL_FILE="$RUN_ROOT/params/${CASE_LABEL}_livevis_control.kv"
mkdir -p "$OUT"

# Continuous signed-distance-like chi: chi=1 in the annular fluid and chi=0 in
# the inner disk / exterior solid.  The 0.5 level is exactly at Ri and Ro in
# the underlying radial field, avoiding a deliberately binary staircase input.
python3 - "$CHI_FILE" "$Lx" "$Ly" "$NX" "$NY" "$CENTER_X" "$CENTER_Y" "$INNER_RADIUS" "$OUTER_RADIUS" "$CHI_INTERFACE_CELLS" <<'PY'
import sys, math, struct
path=sys.argv[1]
Lx,Ly=float(sys.argv[2]),float(sys.argv[3])
nx,ny=int(sys.argv[4]),int(sys.argv[5])
cx,cy=float(sys.argv[6]),float(sys.argv[7])
ri,ro=float(sys.argv[8]),float(sys.argv[9])
width_cells=float(sys.argv[10])
h=min(Lx/nx,Ly/ny)
w=max(0.25,width_cells)*h
vals=[]
for j in range(ny):
    y=(j+0.5)*Ly/ny
    for i in range(nx):
        x=(i+0.5)*Lx/nx
        r=math.hypot(x-cx,y-cy)
        d=min(r-ri,ro-r)  # positive in annular fluid
        chi=max(0.0,min(1.0,0.5+d/w))
        vals.append(chi)
with open(path,'wb') as f:
    f.write(struct.pack('<%df'%len(vals),*vals))
print('[0493x19b] wrote chi=%s cells=%d fluid-cell-fraction~%.6g' %
      (path,len(vals),sum(v>=0.5 for v in vals)/len(vals)))
PY

INITIAL_DEACTIVATE_EFFECTIVE="$INITIAL_DEACTIVATE_BELOW_CHI"
if [[ -n "$RESTART_STATE" ]]; then
  if [[ ! -f "$RESTART_STATE" ]]; then
    echo "[0493x19b] ERROR restart state not found: $RESTART_STATE" >&2
    exit 2
  fi
  STATE="$RESTART_STATE"
  INITIAL_DEACTIVATE_EFFECTIVE=-1
  echo "[0493x19b] RESTART state=$STATE fromStep=$RESTART_FROM_STEP"
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
darcyChiMode = file
darcyChiFile = $CHI_FILE
darcyChiNx = $NX
darcyChiNy = $NY
darcyChiFileFormat = float32
darcyInterfaceWidth = 0.0
darcyAlphaMin = 0.0
darcyAlphaMax = 0.0
darcyQ = 0.1
darcyUSolidX = 0.0
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
chiSolidPrescribedInnerOmegaZ = $OMEGA_Z
chiSolidPrescribedRotationCenterX = $CENTER_X
chiSolidPrescribedRotationCenterY = $CENTER_Y
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
suite_write_env_file_0434 "$RUN_ROOT/logs/environment_0493x19b.env" "$MODE"
cat >> "$RUN_ROOT/logs/environment_0493x19b.env" <<META_ENV
X19B_KINETIC_MODE=$KINETIC_MODE
X19B_OMEGA_Z=$OMEGA_Z
X19B_CENTER_X=$CENTER_X
X19B_CENTER_Y=$CENTER_Y
X19B_INNER_RADIUS=$INNER_RADIUS
X19B_OUTER_RADIUS=$OUTER_RADIUS
X19B_RESTART_STATE=${RESTART_STATE:-NONE}
X19B_RESTART_FROM_STEP=$RESTART_FROM_STEP
META_ENV

cat > "$RUN_ROOT/run_meta_0493x19b.txt" <<META
case=$CASE_LABEL
purpose=prescribed-inner-cylinder-rotation-concentric-annular-couette
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
particleMass=$PARTICLE_MASS
centerX=$CENTER_X
centerY=$CENTER_Y
innerRadiusNominal=$INNER_RADIUS
outerRadiusNominal=$OUTER_RADIUS
omegaZ=$OMEGA_Z
innerWallSpeedNominal=$(python3 -c "print(float('$OMEGA_Z')*float('$INNER_RADIUS'))")
chiInterfaceCells=$CHI_INTERFACE_CELLS
geometry=stationary-concentric-x17-lagrangian-annulus
materialKinematics=inner-rigid-rotation-tangent-projected-to-local-facet;outer-fixed
topology=fully-periodic-box-isolated-by-outer-material-circle
restartState=${RESTART_STATE:-NONE}
restartFromStep=$RESTART_FROM_STEP
META

printf '\n===== 0493x19b PRESCRIBED ROTATING ANNULUS =====\n'
printf 'run=%s mode=%s kinetic=%s grid=%sx%s steps=%s dt=%s\n' "$RUN_ROOT" "$MODE" "$KINETIC_MODE" "$NX" "$NY" "$STEPS" "$DT"
printf 'center=(%s,%s) Ri=%s Ro=%s Omega=%s Ui=%s\n' "$CENTER_X" "$CENTER_Y" "$INNER_RADIUS" "$OUTER_RADIUS" "$OMEGA_Z" "$(python3 -c "print(float('$OMEGA_Z')*float('$INNER_RADIUS'))")"
printf 'dumps every %s; livevis=%s every=%s; record every=%s\n' "$DUMP_STATE_EVERY" "$LIVE_VIS_ENABLE" "$LIVE_VIS_EVERY" "$RECORD_EVERY"
printf '==================================================\n\n'

suite_run_binary_0434 "$PARAMS" "$LOG" "$TIMEFILE" "$OUT" || exit $?
if suite_truthy_0434 "$PREFLIGHT_ONLY"; then exit 0; fi

[[ -s "$OUT/chi_kinetic_boundary_0493x16j.csv" ]] || { echo "[0493x19b] ERROR missing kinetic-boundary CSV" >&2; exit 2; }
[[ -s "$OUT/chi_lagrangian_mesh_0493x17a.csv" ]] || { echo "[0493x19b] ERROR missing x17 mesh CSV" >&2; exit 2; }
[[ -s "$OUT/chi_prescribed_rotation_0493x19b.txt" ]] || { echo "[0493x19b] ERROR missing x19b geometry summary" >&2; exit 2; }
grep -q "\[0493x16j-chi-kinetic\] mode=$KINETIC_MODE timing=prestream" "$LOG" || {
  echo "[0493x19b] ERROR requested x17 kinetic mode not reported" >&2; exit 2; }
grep -q "movingSolid=1" "$LOG" || {
  echo "[0493x19b] ERROR prescribed rotation did not activate material-wall motion" >&2; exit 2; }
grep -q "geometryMoving=0" "$LOG" || {
  echo "[0493x19b] ERROR prescribed circular rotation must not drift the Lagrangian geometry" >&2; exit 2; }
head -n 1 "$OUT/chi_kinetic_boundary_0493x16j.csv" | grep -q "x19bInnerTorqueImpulse" || {
  echo "[0493x19b] ERROR x19b torque diagnostics missing from kinetic CSV" >&2; exit 2; }

echo "[0493x19b] COMPLETE run=$RUN_ROOT"
