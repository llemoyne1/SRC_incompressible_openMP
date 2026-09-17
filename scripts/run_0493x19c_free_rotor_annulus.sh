#!/usr/bin/env bash
# 0493x19c — dynamically free inner rotor in a concentric annulus.
# The outer material circle is fixed. The inner circle has one rotational DOF:
# I dOmega/dt = T_hydro + T_ext - C Omega.
# T_ext is calibrated independently from the late prescribed x19b-fix4 inner
# TOTAL wall-reaction torque at Omega=0.20, so this run isolates and validates
# the solid action-reaction/inertia feedback without re-fitting inside x19c.

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$ROOT/scripts/src_mpcd_run_common_0434.sh"
suite_root_cd_0434 || exit $?

CASE_LABEL="${CASE_LABEL:-0493x19c_free_rotor_omega020}"
BASE_RUN_ROOT="${BASE_RUN_ROOT:-runs/0493x19c_free_rotor_annulus}"
MODE="${MODE:-src-q6}"
TOPOLOGY="periodic"
GEN_CASE="uniform"

Lx="${Lx:-1.0}"
Ly="${Ly:-1.0}"
NX="${NX:-256}"
NY="${NY:-256}"
GAMMA="${GAMMA:-12}"
STEPS="${STEPS:-5000}"
DT="${DT:-0.006}"
KBT="${KBT:-0.05}"
SEED="${SEED:-4931950}"
PARTICLE_MASS="${PARTICLE_MASS:-1.0}"
CENTER_X="${CENTER_X:-0.5}"
CENTER_Y="${CENTER_Y:-0.5}"
INNER_RADIUS="${INNER_RADIUS:-0.20}"
OUTER_RADIUS="${OUTER_RADIUS:-0.35}"
TARGET_OMEGA_Z="${TARGET_OMEGA_Z:-0.20}"
ROTOR_ANGULAR_DAMPING="${ROTOR_ANGULAR_DAMPING:-0.0}"
ROTOR_OUTPUT_EVERY="${ROTOR_OUTPUT_EVERY:-1}"
REFERENCE_START_STEP="${REFERENCE_START_STEP:-500}"
CHI_INTERFACE_CELLS="${CHI_INTERFACE_CELLS:-1.0}"
INITIAL_DEACTIVATE_BELOW_CHI="${INITIAL_DEACTIVATE_BELOW_CHI:-0.5}"
DARCY_THREADS_PER_BLOCK="${DARCY_THREADS_PER_BLOCK:-256}"

SUMMARY_EVERY="${SUMMARY_EVERY:-1}"
DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-1000}"
LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-1}"
LIVE_VIS_FIELD="${LIVE_VIS_FIELD:-vorticity}"
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
RESTART_OMEGA_Z="${RESTART_OMEGA_Z:-}"

# Independent prescribed-run reference.
REFERENCE_RUN_ROOT="${REFERENCE_RUN_ROOT:-runs/0493x19b_fix4_highsnr_omega020/bounceback/fresh}"
REFERENCE_OUTPUT="$REFERENCE_RUN_ROOT/output"
REFERENCE_CSV="$REFERENCE_OUTPUT/chi_kinetic_boundary_0493x16j.csv"
REFERENCE_PARAMS="${REFERENCE_PARAMS:-$REFERENCE_RUN_ROOT/params/0493x19b_fix4_bounceback_omega020.kv}"
if [[ ! -s "$REFERENCE_CSV" ]]; then
  echo "[0493x19c] ERROR missing prescribed x19b-fix4 torque CSV: $REFERENCE_CSV" >&2
  exit 2
fi
if [[ ! -s "$REFERENCE_PARAMS" ]]; then
  # Accept a renamed params file but fail if the source is ambiguous.
  mapfile -t ref_params < <(find "$REFERENCE_RUN_ROOT/params" -maxdepth 1 -type f -name '*.kv' -print | sort)
  if [[ "${#ref_params[@]}" -ne 1 ]]; then
    echo "[0493x19c] ERROR cannot resolve unique x19b-fix4 params file" >&2
    exit 2
  fi
  REFERENCE_PARAMS="${ref_params[0]}"
fi

# Source state: by default the established Omega=0.20 fix4 fluid field. For an
# interrupted x19c continuation, provide RESTART_STATE and RESTART_OMEGA_Z.
if [[ -z "$RESTART_STATE" ]]; then
  SOURCE_STATE="$(find "$REFERENCE_OUTPUT" -maxdepth 1 -type f -name 'state_step_*.smpcd' -print | sort -V | tail -n 1)"
  if [[ -z "$SOURCE_STATE" || ! -s "$SOURCE_STATE" ]]; then
    echo "[0493x19c] ERROR no restart state in $REFERENCE_OUTPUT" >&2
    exit 2
  fi
  ROTOR_INITIAL_OMEGA_Z="$TARGET_OMEGA_Z"
  SOURCE_STEP="$(basename "$SOURCE_STATE" | sed -n 's/^state_step_0*\([0-9][0-9]*\)\.smpcd$/\1/p')"
  [[ -n "$SOURCE_STEP" ]] || SOURCE_STEP=0
else
  if [[ ! -s "$RESTART_STATE" ]]; then
    echo "[0493x19c] ERROR RESTART_STATE not found: $RESTART_STATE" >&2
    exit 2
  fi
  if [[ -z "$RESTART_OMEGA_Z" ]]; then
    echo "[0493x19c] ERROR a free-rotor restart requires RESTART_OMEGA_Z from chi_free_rotor_0493x19c.csv" >&2
    exit 2
  fi
  SOURCE_STATE="$RESTART_STATE"
  ROTOR_INITIAL_OMEGA_Z="$RESTART_OMEGA_Z"
  SOURCE_STEP="$RESTART_FROM_STEP"
fi

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

python3 - "$Lx" "$Ly" "$NX" "$NY" "$CENTER_X" "$CENTER_Y" "$INNER_RADIUS" "$OUTER_RADIUS" "$TARGET_OMEGA_Z" <<'PY'
import sys,math
Lx,Ly=float(sys.argv[1]),float(sys.argv[2]); nx,ny=int(sys.argv[3]),int(sys.argv[4])
cx,cy=float(sys.argv[5]),float(sys.argv[6]); ri,ro=float(sys.argv[7]),float(sys.argv[8]); om=float(sys.argv[9])
h=min(Lx/nx,Ly/ny)
if nx<64 or ny<64: raise SystemExit('[0493x19c] require NX,NY>=64')
if abs(Lx-Ly)>1e-12*max(Lx,Ly): raise SystemExit('[0493x19c] qualification requires Lx=Ly')
clearance=min(cx,Lx-cx,cy,Ly-cy)
if not (ri>12*h and ro-ri>16*h and clearance>ro+6*h):
    raise SystemExit('[0493x19c] require Ri>12h, gap>16h and outer circle >6h from box edge')
if not (math.isfinite(om) and om>0): raise SystemExit('[0493x19c] TARGET_OMEGA_Z must be positive finite')
PY

RUN_ROOT="$BASE_RUN_ROOT/fresh"
# Keep a restart source safe if it resides under the destination being cleaned.
STAGED_RESTART=""
if [[ -n "$RESTART_STATE" && "$CLEAN_RUN_ROOT" != "0" && "$CLEAN_RUN_ROOT" != "false" ]]; then
  STAGED_RESTART="$ROOT/runs/0493x19c_restart_stage_$(date +%Y%m%d_%H%M%S).smpcd"
  cp "$SOURCE_STATE" "$STAGED_RESTART" || exit 2
  SOURCE_STATE="$STAGED_RESTART"
fi
if suite_truthy_0434 "$CLEAN_RUN_ROOT"; then rm -rf "$RUN_ROOT"; fi
suite_prepare_dirs_0434 "$RUN_ROOT"
OUT="$RUN_ROOT/output"
PARAMS="$RUN_ROOT/params/${CASE_LABEL}.kv"
CHI_FILE="$RUN_ROOT/init/${CASE_LABEL}_annulus_chi_f32.bin"
LOG="$RUN_ROOT/logs/${CASE_LABEL}.log"
TIMEFILE="$RUN_ROOT/logs/${CASE_LABEL}.time"
LIVE_VIS_CONTROL_FILE="$RUN_ROOT/params/${CASE_LABEL}_livevis_control.kv"
REFERENCE_FILE="$RUN_ROOT/params/0493x19c_reference_from_x19b_fix4.kv"
mkdir -p "$OUT"

python3 "$ROOT/tools/prepare_0493x19c_free_rotor_reference.py" \
  --csv "$REFERENCE_CSV" --params "$REFERENCE_PARAMS" \
  --start-step "$REFERENCE_START_STEP" --target-omega "$TARGET_OMEGA_Z" \
  --output "$REFERENCE_FILE" || exit 2
EXTERNAL_TORQUE_Z="$(sed -n 's/^externalTorqueZ=//p' "$REFERENCE_FILE" | tail -n 1)"
[[ -n "$EXTERNAL_TORQUE_Z" ]] || { echo "[0493x19c] ERROR external torque reference missing" >&2; exit 2; }

# Natural qualification inertia: a neutrally-buoyant solid disk with the
# nominal MPCD surface density rho=gamma/(dx*dy). It is deliberately explicit
# in the params, so the mechanics benchmark does not infer mass from chi.
ROTOR_INERTIA="${ROTOR_INERTIA:-$(python3 - "$GAMMA" "$Lx" "$Ly" "$NX" "$NY" "$INNER_RADIUS" <<'PY'
import sys,math
g,Lx,Ly,nx,ny,R=float(sys.argv[1]),float(sys.argv[2]),float(sys.argv[3]),int(sys.argv[4]),int(sys.argv[5]),float(sys.argv[6])
rho=g/((Lx/nx)*(Ly/ny))
print('%.17g'%(0.5*rho*math.pi*R**4))
PY
)}"

# Continuous signed-distance-like annulus chi, identical in construction to x19b.
python3 - "$CHI_FILE" "$Lx" "$Ly" "$NX" "$NY" "$CENTER_X" "$CENTER_Y" "$INNER_RADIUS" "$OUTER_RADIUS" "$CHI_INTERFACE_CELLS" <<'PY'
import sys,math,struct
path=sys.argv[1]; Lx,Ly=float(sys.argv[2]),float(sys.argv[3]); nx,ny=int(sys.argv[4]),int(sys.argv[5])
cx,cy=float(sys.argv[6]),float(sys.argv[7]); ri,ro=float(sys.argv[8]),float(sys.argv[9]); width=float(sys.argv[10])
h=min(Lx/nx,Ly/ny); w=max(0.25,width)*h; vals=[]
for j in range(ny):
    y=(j+0.5)*Ly/ny
    for i in range(nx):
        x=(i+0.5)*Lx/nx; r=math.hypot(x-cx,y-cy); d=min(r-ri,ro-r)
        vals.append(max(0.0,min(1.0,0.5+d/w)))
with open(path,'wb') as f: f.write(struct.pack('<%df'%len(vals),*vals))
print(f'[0493x19c] wrote chi={path} cells={len(vals)}')
PY

cat > "$PARAMS" <<PARAMS
inputState = $SOURCE_STATE
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
darcyInitialDeactivateBelowChi = -1
darcyBrinkmanForcingMode = mean
darcyChiCollisionVpEnable = false
chiKineticBoundaryMode = bounceback
chiSolidDynamicsEnable = false
chiSolidModel = none
chiSolidQualificationDiagnosticsEnable = true
chiSolidPrescribedInnerOmegaZ = 0.0
chiSolidPrescribedRotationCenterX = $CENTER_X
chiSolidPrescribedRotationCenterY = $CENTER_Y
chiSolidFreeRotorEnable = true
chiSolidFreeRotorInertia = $ROTOR_INERTIA
chiSolidFreeRotorInitialOmegaZ = $ROTOR_INITIAL_OMEGA_Z
chiSolidFreeRotorExternalTorqueZ = $EXTERNAL_TORQUE_Z
chiSolidFreeRotorAngularDamping = $ROTOR_ANGULAR_DAMPING
chiSolidFreeRotorOutputEvery = $ROTOR_OUTPUT_EVERY
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
# Full x19b-fix3 operator audit is no longer needed; x19c records the exact
# generalized solid impulse itself at every step.
export MPCD_X19B_FIX3_FULL_ANGULAR_AUDIT=0
export MPCD_X19B_FIX2_SRC_ANGULAR_AUDIT=0
suite_write_env_file_0434 "$RUN_ROOT/logs/environment_0493x19c.env" "$MODE"

cat > "$RUN_ROOT/run_meta_0493x19c.txt" <<META
case=$CASE_LABEL
purpose=free-inner-rotor-end-to-end-solid-fsi-validation
mode=$MODE
kineticMode=bounceback
Lx=$Lx
Ly=$Ly
Nx=$NX
Ny=$NY
dt=$DT
steps=$STEPS
gamma=$GAMMA
kBT=$KBT
centerX=$CENTER_X
centerY=$CENTER_Y
innerRadiusNominal=$INNER_RADIUS
outerRadiusNominal=$OUTER_RADIUS
targetOmega=$TARGET_OMEGA_Z
initialOmega=$ROTOR_INITIAL_OMEGA_Z
rotorInertia=$ROTOR_INERTIA
externalTorqueZ=$EXTERNAL_TORQUE_Z
angularDamping=$ROTOR_ANGULAR_DAMPING
referenceRun=$REFERENCE_RUN_ROOT
referenceStartStep=$REFERENCE_START_STEP
sourceState=$SOURCE_STATE
restartFromStep=$SOURCE_STEP
META

printf '\n===== 0493x19c FREE ROTOR ANNULUS =====\n'
printf 'source=%s\n' "$SOURCE_STATE"
printf 'Omega0=%s target=%s inertia=%s T_ext=%s damping=%s\n' "$ROTOR_INITIAL_OMEGA_Z" "$TARGET_OMEGA_Z" "$ROTOR_INERTIA" "$EXTERNAL_TORQUE_Z" "$ROTOR_ANGULAR_DAMPING"
printf 'steps=%s dt=%s summaryEvery=%s dumpEvery=%s\n' "$STEPS" "$DT" "$SUMMARY_EVERY" "$DUMP_STATE_EVERY"
printf 'livevis=%s every=%s record=%s every=%s grid=%sx%s\n' "$LIVE_VIS_ENABLE" "$LIVE_VIS_EVERY" "$RECORD_ENABLE" "$RECORD_EVERY" "$LIVE_VIS_NX" "$LIVE_VIS_NY"
printf '=========================================\n\n'

suite_run_binary_0434 "$PARAMS" "$LOG" "$TIMEFILE" "$OUT" || exit $?
if suite_truthy_0434 "$PREFLIGHT_ONLY"; then exit 0; fi

ROTORCSV="$OUT/chi_free_rotor_0493x19c.csv"
WALLCSV="$OUT/chi_kinetic_boundary_0493x16j.csv"
[[ -s "$ROTORCSV" ]] || { echo "[0493x19c] ERROR missing free-rotor CSV" >&2; exit 2; }
[[ -s "$WALLCSV" ]] || { echo "[0493x19c] ERROR missing kinetic-boundary CSV" >&2; exit 2; }
grep -q "freeRotor=1" "$LOG" || { echo "[0493x19c] ERROR free rotor was not activated" >&2; exit 2; }
grep -q "geometryMoving=0" "$LOG" || { echo "[0493x19c] ERROR circular free rotor must keep geometry stationary" >&2; exit 2; }
head -n 1 "$ROTORCSV" | grep -q "mechanicsResidual" || { echo "[0493x19c] ERROR mechanics closure column missing" >&2; exit 2; }

sha256sum "$SOURCE_STATE" "$REFERENCE_CSV" > "$RUN_ROOT/references_sha256_0493x19c.txt"
[[ -n "$STAGED_RESTART" ]] && rm -f "$STAGED_RESTART"
echo "[0493x19c] COMPLETE output=$OUT"
echo "[0493x19c] MATLAB: cd matlab; results = analyze_0493x19c_free_rotor_annulus;"
