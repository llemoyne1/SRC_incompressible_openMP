#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$ROOT/scripts/src_mpcd_run_common_0434.sh"
suite_root_cd_0434

# 0493x13m — 2-D oscillating-drop qualification of the x13h fluid.
# Tooling/initial-condition only: no C++/CUDA physics change and no new source diagnostic.
# Mode n=4 requires a fourth-order observable.  No source diagnostic is added:
# q3 is reconstructed offline from COM-centred particle-state dumps.

CASE_LABEL="oscillating_drop_n4_0493x13m"
RUN_MODE="${RUN_MODE:-src-q6-g-f}"
TOPOLOGY="closed_box"

GENERATOR="$ROOT/scripts/generate_0493x13k_oscillating_drop_2d.py"
ANALYZER="$ROOT/scripts/analyze_0493x13m_oscillating_drop_n4_state.py"
[[ -f "$GENERATOR" ]] || { echo "[0493x13m] ERROR missing $GENERATOR" >&2; exit 2; }
[[ -f "$ANALYZER" ]] || { echo "[0493x13m] ERROR missing $ANALYZER" >&2; exit 2; }

# x13h reference point.
NX="${NX:-256}"; NY="${NY:-256}"
Lx="${Lx:-1.0}"; Ly="${Ly:-1.0}"
GAMMA="${GAMMA:-8}"
DT="${DT:-0.0063471328149122585}"
KBT="${KBT:-0.125}"
LIQUID_TYPE="${LIQUID_TYPE:-1}"
LIQUID_MASS="${LIQUID_MASS:-1.0}"
ROTATION_ANGLE="${ROTATION_ANGLE:-2.0943951023931953}"
RANDOM_ROTATION_SIGN="${RANDOM_ROTATION_SIGN:-true}"
GRID_SHIFT_ENABLE="${GRID_SHIFT_ENABLE:-true}"
THERMOSTAT_ENABLE="${THERMOSTAT_ENABLE:-true}"
THERMOSTAT_MODE="${THERMOSTAT_MODE:-cell_relative_rescale}"
THERMOSTAT_EVERY="${THERMOSTAT_EVERY:-1}"
THERMOSTAT_TARGET_KBT="${THERMOSTAT_TARGET_KBT:-$KBT}"
THERMOSTAT_MIN_PARTICLES="${THERMOSTAT_MIN_PARTICLES:-3}"

# Qualified-amplitude mode-4 point.
RADIUS_CELLS="${RADIUS_CELLS:-40}"
MODE="${MODE:-4}"
EPSILON="${EPSILON:-0.04}"
PHASE="${PHASE:-0.0}"
CENTER_X="${CENTER_X:-0.5}"
CENTER_Y="${CENTER_Y:-0.5}"
SIGMA_DECLARED="${SIGMA_DECLARED:-10000}"
SURFACE_TENSION_MIN_RADIUS_CELLS="${SURFACE_TENSION_MIN_RADIUS_CELLS:-4}"
SEED="${SEED:-4931401}"

# ~3.5 inviscid periods for n=4. State dumps every 5 steps give ~11 samples/period;
# this resolves the shorter n=4 period while keeping I/O moderate.
STEPS="${STEPS:-200}"
SUMMARY_EVERY="${SUMMARY_EVERY:-5}"
DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-5}"
FIT_PERIODS="${FIT_PERIODS:-2.5}"
NU_REF="${NU_REF:-0.00051}"

RUN_ROOT="${RUN_ROOT:-runs/0493x13m_oscillating_drop_n4_x13h_s${SIGMA_DECLARED}_n${MODE}_r${RADIUS_CELLS}_eps${EPSILON}_seed${SEED}}"
CLEAN_RUN_ROOT="${CLEAN_RUN_ROOT:-1}"
PREFLIGHT_ONLY="${PREFLIGHT_ONLY:-0}"

# No heavy field recording path.  The n=3 observable is reconstructed offline
# from sparse fluid state dumps; x9e/x9r remain ancillary diagnostics.
LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-0}"
LIVE_VIS_EVERY="${LIVE_VIS_EVERY:-100}"
LIVE_VIS_HOLD_ON_EXIT="${LIVE_VIS_HOLD_ON_EXIT:-0}"
LIVE_VIS_RECORD_ENABLE="${LIVE_VIS_RECORD_ENABLE:-0}"
LIVE_VIS_RECORD_EVERY="${LIVE_VIS_RECORD_EVERY:-100}"
LIVE_VIS_RECORD_FIELDS="${LIVE_VIS_RECORD_FIELDS:-mass}"
FILTERED_RECORDING_ENABLE="${FILTERED_RECORDING_ENABLE:-0}"
FILTER_SAMPLE_EVERY="${FILTER_SAMPLE_EVERY:-100}"
PARTICLE_TYPE_FILTER="$LIQUID_TYPE"
OVERWRITE_LIVEVIS_CONTROL=1

# Q6-g-f/current no-resampling contract.
PROJECTION_BACKEND="${PROJECTION_BACKEND:-cuda}"
PROJECTION_OPERATOR="${PROJECTION_OPERATOR:-auto_fv_cg}"
PROJECTION_MAX_ITERATIONS="${PROJECTION_MAX_ITERATIONS:-2000}"
PROJECTION_TOLERANCE="${PROJECTION_TOLERANCE:-1.0e-5}"
PROJECTION_MOMENTUM_CORRECTION_ENABLE="false"
Q6_PROJECTION_STRENGTH="1.0"
Q6_STRICT=1
Q6_FORCE_PROJECTION_MODE="prestream_single_fused"
Q6_GF_EXTERNAL_SPECIES=1
Q6_GF_HAS_GAS_PHASE=0
Q6_GF_DENSITY_RELAXATION_TIME="${Q6_GF_DENSITY_RELAXATION_TIME:-0.25}"
Q6_GF_MIN_FILL_FRACTION="${Q6_GF_MIN_FILL_FRACTION:-0.10}"
Q6_GF_DENSITY_COMPRESSION_GATE_ENABLE=1
Q6_GF_DENSITY_COMPRESSION_THRESHOLD_PARTICLES="${Q6_GF_DENSITY_COMPRESSION_THRESHOLD_PARTICLES:-3.0}"
Q6_GF_DENSITY_TRACTION_THRESHOLD_PARTICLES="${Q6_GF_DENSITY_TRACTION_THRESHOLD_PARTICLES:-6.0}"
Q6_GF_DENSITY_TRACTION_GAIN="${Q6_GF_DENSITY_TRACTION_GAIN:-1.0}"
SPECIES_RESAMPLING_ENABLE=false
LIQUID_RESAMPLING_ENABLE=false
GAS_RESAMPLING_ENABLE=false
VIRIAL_DENSITY_KICK_ENABLE=false
WEIGHTED_RESAMPLING_ENABLE_OVERRIDE=false
CUDA_EMPTY_REFILL_ENABLE_OVERRIDE=false

# Preserve the same inactive reserve as the x13j R40 static-drop runs; it remains unused
# by resampling because resampling/refill are disabled.
INACTIVE_SLOTS="${INACTIVE_SLOTS:-16384}"

# Canonical variables required by the shared 0434 helper.
GEN_CASE=tg
U0=0.0
VELOCITY_MODE=zero
PARTICLE_MASS="$LIQUID_MASS"
BACKGROUND_TYPE="$LIQUID_TYPE"
INACTIVE_TYPE="$LIQUID_TYPE"
TG_HOLE_ENABLE=false

suite_defaults_common_0434
suite_compute_derived_0434

# Tight preflight: this runner is intentionally locked to n=4.  The modal
# observable comes from offline fourth mass moments, not the x9f quadrupole.
read -r H R RHO OMEGA0 PERIOD0 BETA_LAMB OMEGA_LAMB PERIOD_LAMB RCUT_RATIO <<<"$(
python3 - "$Lx" "$Ly" "$NX" "$NY" "$GAMMA" "$LIQUID_MASS" "$RADIUS_CELLS" \
          "$MODE" "$EPSILON" "$SIGMA_DECLARED" "$NU_REF" "$DT" \
          "$ROTATION_ANGLE" "$SURFACE_TENSION_MIN_RADIUS_CELLS" <<'PY'
import math,sys
lx,ly=float(sys.argv[1]),float(sys.argv[2]); nx,ny=int(sys.argv[3]),int(sys.argv[4])
gamma,mass=float(sys.argv[5]),float(sys.argv[6]); rc=float(sys.argv[7]); mode=int(sys.argv[8])
eps,sigma,nu,dt,angle,rmin=map(float,sys.argv[9:15])
hx,hy=lx/nx,ly/ny
if abs(hx-hy)>1e-12*max(1.0,abs(hx),abs(hy)): raise SystemExit('[0493x13m] ERROR square cells required')
if mode != 4: raise SystemExit('[0493x13m] ERROR this runner is intentionally MODE=4')
if not (0 < eps <= 0.05): raise SystemExit(f'[0493x13m] ERROR modal qualification requires 0<epsilon<=0.05, got {eps}')
if sigma <= 0 or rc <= 0 or nu <= 0 or dt <= 0: raise SystemExit('[0493x13m] ERROR sigma,R,nu,dt must be positive')
if rmin != 4: raise SystemExit(f'[0493x13m] ERROR current x12 dynamic drop uses minRadiusCells=4 here, got {rmin}')
if abs(angle-2.0943951023931953)>1e-12: raise SystemExit(f'[0493x13m] ERROR x13h requires rotationAngle=120deg, got {angle}')
h=hx; R=rc*h; rho=gamma*mass/(h*h)
omega0=math.sqrt(mode*(mode*mode-1)*sigma/(rho*R**3)); period0=2*math.pi/omega0
beta=2*mode*(mode-1)*nu/(R*R); omegad=math.sqrt(max(0.0,omega0*omega0-beta*beta)); periodd=2*math.pi/omegad
Rc=25.298221281347036*h
print(f'{h:.17g} {R:.17g} {rho:.17g} {omega0:.17g} {period0:.17g} {beta:.17g} {omegad:.17g} {periodd:.17g} {R/Rc:.17g}')
PY
)"

if suite_truthy_0434 "$CLEAN_RUN_ROOT"; then rm -rf "$RUN_ROOT"; fi
suite_prepare_dirs_0434 "$RUN_ROOT"
STATE="$RUN_ROOT/init/${CASE_LABEL}.smpcd"
OUT="$RUN_ROOT/output"
PARAMS="$RUN_ROOT/params/${CASE_LABEL}.kv"
LOG="$RUN_ROOT/logs/${CASE_LABEL}.log"
TIME_FILE="$RUN_ROOT/logs/${CASE_LABEL}.time"
mkdir -p "$OUT"

python3 "$GENERATOR" \
  --output "$STATE" --Lx "$Lx" --Ly "$Ly" --nx "$NX" --ny "$NY" \
  --gamma "$GAMMA" --center-x "$CENTER_X" --center-y "$CENTER_Y" \
  --radius-cells "$RADIUS_CELLS" --mode "$MODE" --epsilon "$EPSILON" --phase "$PHASE" \
  --liquid-type "$LIQUID_TYPE" --liquid-mass "$LIQUID_MASS" --kBT "$KBT" --seed "$SEED"

LIQUID_REFERENCE_CELL_MASS="$(awk -v g="$GAMMA" -v m="$LIQUID_MASS" 'BEGIN{printf "%.17g",g*m}')"

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
bcBottom = solid
bcTop = solid
bcX = wall
bcY = wall
openBoundarySegmentsEnable = false
openBoundarySegmentCount = 0
bodyAccelerationX = 0.0
bodyAccelerationY = 0.0
wallVpEnable = false
wallAccommodation = 1.0
wallKBT = -1.0
wallThermalNoise = 0.0
surfaceTensionSigma = $SIGMA_DECLARED
surfaceTensionMinRadiusCells = $SURFACE_TENSION_MIN_RADIUS_CELLS
phaseInterfaceKineticReflectionFraction = 1.0
phaseInterfaceEvaporationTargetType = -1
phaseInterfaceASelector = type:$LIQUID_TYPE
phaseInterfaceBSelector = vacuum
phaseInterfaceContactAngleDegrees = -1
speciesRegistryEnable = true
speciesCount = 1
species0 = $LIQUID_TYPE q6_g_f_liquid liquid 1.0 1.0 $LIQUID_REFERENCE_CELL_MASS
species0ResamplingEnable = false
speciesRequireRegisteredTypes = true
speciesDiagnosticsEnable = false
speciesCellDiagnosticsEnable = false
speciesQ6Enable = true
speciesQ6Mode = free_surface_masked
speciesQ6Sensitivity = 1.0
speciesQ6FallbackMode = common
speciesQ6ComparisonTolerance = 1.0e-11
speciesQ6MinOccupancyFraction = $Q6_GF_MIN_FILL_FRACTION
dumpStateEvery = $DUMP_STATE_EVERY
dumpRoleFilter = fluid
summaryRoleFilter = fluid
PARAMS
suite_write_common_params_0434 "$RUN_MODE" >> "$PARAMS"

suite_export_cuda_flags_0434 "$RUN_MODE" "$TOPOLOGY"

# Q6-g-f free-surface geometry/stencil/B1, locked to the same liquid-vacuum path
# used by x13j.  No gas-pressure provider is active for B=vacuum.
export MPCD_Q6_PHASE_GEOMETRY_RESIDENT_0493X6C=1
export MPCD_Q6_PHASE_GEOMETRY_CUTFACE_0493X6D=0
export MPCD_Q6_PHASE_INTERFACE_TOPOLOGY_0493X6E=1
export MPCD_Q6_PHASE_INTERFACE_STENCIL_0493X6F=1
export MPCD_Q6_PHASE_GAS_PRESSURE_0493X6G=0
export MPCD_Q6_PHASE_GAS_PRESSURE_CONSTANT_0493X6G=0
export MPCD_Q6_PHASE_GAS_PRESSURE_REFERENCE_0493X6G=0
export MPCD_Q6_PHASE_GAS_PRESSURE_SCALE_0493X6G=0
export MPCD_Q6_PHASE_PRESSURE_DIAGNOSTICS_0493X6A=0
export MPCD_Q6_PHASE_GEOMETRY_DIAGNOSTICS_0493X6B=0
export MPCD_Q6_POSTAPPLY_REGION_DIAGNOSTICS_0493X6H_B0=0
export MPCD_Q6_FACE_TO_PARTICLE_RT0_0493X6H_B1=1

# Existing x9 diagnostics only. x9f is observational; no new source instrumentation.
export MPCD_Q6_STATIC_DROP_DIAGNOSTICS_0493X9E=1
export MPCD_Q6_ELLIPSE_DIAGNOSTICS_0493X9F=0
export MPCD_Q6_PHASE_CURVATURE_DIAGNOSTICS_0493X9A=0
export MPCD_Q6_PHASE_CURVATURE_DIAGNOSTICS_0493X9B=1
export MPCD_Q6_PHASE_CURVATURE_DIAGNOSTICS_0493X9C=1
export MPCD_Q6_CONTACT_ANGLE_HARD_NORMAL_0493X9I=0
export MPCD_Q6_CONTACT_ANGLE_WALL_FACE_0493X9L=0
export MPCD_Q6_CONTACT_ANGLE_OFFSUPPORT_0493X9M=0
export MPCD_Q6_PHASE_GAS_PRESSURE_0493X6G=0

# Current x12 production kinetic free-surface chain.
export MPCD_X10J_SIMPLE_SPECULAR_ABLATION=0
export MPCD_X10K_LOCAL_FRAME_SPECULAR_ABLATION=0
export MPCD_X10M_MOVING_INTERFACE_WALL=0
export MPCD_X10N_Q6_CONTINUOUS_INTERFACE_WALL=0
export MPCD_X10O_Q6_THERMAL_INTERFACE_WALL=1
export MPCD_X10O_THERMAL_PARTICLE_MASS="$LIQUID_MASS"
export MPCD_X10O_THERMAL_SIGMAS="${MPCD_X10O_THERMAL_SIGMAS:-3.0}"
export MPCD_X10O_THERMAL_MAX_CELLS="${MPCD_X10O_THERMAL_MAX_CELLS:-0.75}"
export MPCD_X10P_INITIAL_OVERLAP_RESOLUTION=1
export MPCD_X10L_PREWALL_INTERFACE_DIAGNOSTICS=0
export MPCD_X10_KINETIC_INTERFACE_CIC=1
export MPCD_X10_KINETIC_INTERFACE_QUADRATIC=1
export MPCD_X10_KINETIC_INTERFACE_ONE_FOR_ONE=1
export MPCD_X10_KINETIC_INTERFACE_ONE_FOR_ONE_SWAP=1
export MPCD_X10R_Q6_THERMAL_FULL_VECTOR_ENDPOINT_VELOCITY=0
export MPCD_X10S_Q6_THERMAL_SEGMENT_NORMAL_KINEMATICS=0
export MPCD_X10T_Q6_THERMAL_RIGID_TANGENTIAL_KINEMATICS=0
export MPCD_X10_KINETIC_INTERFACE_THERMAL_PHASE_LIMITER=0
export MPCD_X12A_LOCAL_THERMAL_COOLING=1
export MPCD_X12A_LOCAL_THERMAL_RADIUS_CELLS="${MPCD_X12A_LOCAL_THERMAL_RADIUS_CELLS:-25.298221281347036}"

LIVE_VIS_CONTROL_FILE="$RUN_ROOT/livevis_control_0493x13m.kv"
export LIVE_VIS_CONTROL_FILE
suite_prepare_livevis_control_0434 "$RUN_ROOT" "$RUN_MODE"
suite_export_livevis_0434
suite_write_env_file_0434 "$RUN_ROOT/logs/environment_0493x13m.env" "$RUN_MODE"
cat >> "$RUN_ROOT/logs/environment_0493x13m.env" <<META
X13M_MODE=$MODE
X13M_RADIUS_CELLS=$RADIUS_CELLS
X13M_EPSILON=$EPSILON
X13M_PHASE=$PHASE
X13M_SIGMA=$SIGMA_DECLARED
X13M_NU_REF=$NU_REF
X13M_OMEGA0_2D=$OMEGA0
X13M_PERIOD0_2D=$PERIOD0
X13M_BETA_LAMB=$BETA_LAMB
X13M_OMEGA_LAMB=$OMEGA_LAMB
X13M_PERIOD_LAMB=$PERIOD_LAMB
X13M_R_OVER_X12A_RC=$RCUT_RATIO
META

printf '%s\n' \
  '===== 0493x13m 2-D OSCILLATING DROP n=4 / x13h =====' \
  "[0493x13m] objective=dynamic capillary qualification n=4; no Young-Laplace sigma0 baseline" \
  "[0493x13m] initial r(theta)=R*[sqrt(1-eps^2/2)+eps*cos(4theta)]; exact continuous area=pi*R^2" \
  "[0493x13m] grid=${NX}x${NY} h=$H gamma=$GAMMA dt=$DT kBT=$KBT R/h=$RADIUS_CELLS eps=$EPSILON sigma=$SIGMA_DECLARED" \
  "[0493x13m] theory2D omega0=$OMEGA0 period0=$PERIOD0 LambBeta=$BETA_LAMB omegaDamped=$OMEGA_LAMB periodDamped=$PERIOD_LAMB" \
  "[0493x13m] x12a initial resolved-size ratio R/Rc=$RCUT_RATIO (target >1)" \
  "[0493x13m] steps=$STEPS tEnd=$(awk -v n="$STEPS" -v d="$DT" 'BEGIN{printf "%.9g",n*d}') summaryEvery=$SUMMARY_EVERY fitPeriods=$FIT_PERIODS" \
  "[0493x13m] diagnostics=offline COM-centred fourth mass moment from state dumps; x9e/x9r ancillary"

suite_run_binary_0434 "$PARAMS" "$LOG" "$TIME_FILE" "$OUT"

if ! suite_truthy_0434 "$PREFLIGHT_ONLY"; then
  shopt -s nullglob
  STATES=("$OUT"/state_step_*.smpcd)
  shopt -u nullglob
  (( ${#STATES[@]} >= 20 )) || { echo "[0493x13m] ERROR need >=20 state dumps, got ${#STATES[@]} in $OUT" >&2; exit 2; }
  python3 "$ANALYZER" \
    --run-root "$RUN_ROOT" --radius-cells "$RADIUS_CELLS" --sigma "$SIGMA_DECLARED" \
    --gamma "$GAMMA" --mass "$LIQUID_MASS" --h "$H" --nu "$NU_REF" \
    --dt "$DT" --mode "$MODE" --fit-periods "$FIT_PERIODS"
  echo "[0493x13m] COMPLETE run=$RUN_ROOT analysis=$RUN_ROOT/analysis_0493x13m"
fi
