#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$ROOT/scripts/src_mpcd_run_common_0434.sh"
suite_root_cd_0434

# 0493x13n — 2-D Taylor-Culick sheet-retraction qualification, x13h path.
# Runner/generator/offline analysis only: no C++/CUDA modification and no new
# source diagnostic.  Two symmetric free edges provide two independent estimates
# of the retraction speed while cancelling global translation.

CASE_LABEL="taylor_culick_sheet_2d_0493x13n"
RUN_MODE="${RUN_MODE:-src-q6-g-f}"
TOPOLOGY="closed_box"

GENERATOR="$ROOT/scripts/generate_0493x13n_taylor_culick_sheet_2d.py"
ANALYZER="$ROOT/scripts/analyze_0493x13n_taylor_culick_sheet_2d.py"
[[ -f "$GENERATOR" ]] || { echo "[0493x13n] ERROR missing $GENERATOR" >&2; exit 2; }
[[ -f "$ANALYZER" ]] || { echo "[0493x13n] ERROR missing $ANALYZER" >&2; exit 2; }

# x13h reference fluid.  Same h=1/256 as x13k-m, elongated x-domain only.
NX="${NX:-640}"; NY="${NY:-256}"
Lx="${Lx:-2.5}"; Ly="${Ly:-1.0}"
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

# Resolved Taylor-Culick sheet.  H/h=64 is deliberate: the flat film's
# opposite-interface half-distance H/2=32h exceeds the current x12a cutoff
# Rc/h=25.298..., so local cooling is inactive on the resolved planar sheet.
SHEET_LENGTH_CELLS="${SHEET_LENGTH_CELLS:-512}"
THICKNESS_CELLS="${THICKNESS_CELLS:-64}"
EDGE_ROUND_CELLS="${EDGE_ROUND_CELLS:-8}"
CENTER_X="${CENTER_X:-1.25}"
CENTER_Y="${CENTER_Y:-0.5}"
SIGMA_DECLARED="${SIGMA_DECLARED:-10000}"
SURFACE_TENSION_MIN_RADIUS_CELLS="${SURFACE_TENSION_MIN_RADIUS_CELLS:-4}"
SEED="${SEED:-4931501}"
NU_REF="${NU_REF:-0.00051}"

# About 2.18 Taylor-Culick thickness times.  Sparse state dumps are sufficient
# because a rim moves ~6.35 cells between 10-step dumps at the default point.
STEPS="${STEPS:-220}"
SUMMARY_EVERY="${SUMMARY_EVERY:-5}"
DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-10}"
FIT_TAU_MIN="${FIT_TAU_MIN:-0.5}"
FIT_TAU_MAX="${FIT_TAU_MAX:-1.75}"

RUN_ROOT="${RUN_ROOT:-runs/0493x13n_taylor_culick_sheet_2d_x13h_s${SIGMA_DECLARED}_H${THICKNESS_CELLS}_L${SHEET_LENGTH_CELLS}_seed${SEED}}"
CLEAN_RUN_ROOT="${CLEAN_RUN_ROOT:-1}"
PREFLIGHT_ONLY="${PREFLIGHT_ONLY:-0}"

LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
# 0493x13n-fix1 LiveVis contract: render every active step, record mass every
# 100 steps.  Keep both the current aliases and the 0434 canonical recorder
# names coherent so the generated livevis_control_0493x13n.kv contains the
# requested liveEvery/recordEvery values.
LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-1}"
LIVE_VIS_FIELD="${LIVE_VIS_FIELD:-mass}"
LIVE_VIS_EVERY="${LIVE_VIS_EVERY:-1}"
LIVE_VIS_HOLD_ON_EXIT="${LIVE_VIS_HOLD_ON_EXIT:-0}"
LIVE_VIS_RECORD_ENABLE="${LIVE_VIS_RECORD_ENABLE:-1}"
LIVE_VIS_RECORD_EVERY="${LIVE_VIS_RECORD_EVERY:-20}"
LIVE_VIS_RECORD_FIELDS="${LIVE_VIS_RECORD_FIELDS:-mass}"
FILTERED_RECORDING_ENABLE="${FILTERED_RECORDING_ENABLE:-1}"
FILTER_SAMPLE_EVERY="${FILTER_SAMPLE_EVERY:-20}"
PARTICLE_TYPE_FILTER="$LIQUID_TYPE"
OVERWRITE_LIVEVIS_CONTROL="${OVERWRITE_LIVEVIS_CONTROL:-1}"
if [[ "$LIVE_VIS_RECORD_ENABLE" == 1 || "$LIVE_VIS_RECORD_ENABLE" == true ]]; then
  RECORD_ENABLE=true
else
  RECORD_ENABLE=false
fi
RECORD_EVERY="$LIVE_VIS_RECORD_EVERY"
RECORD_FIELDS="$LIVE_VIS_RECORD_FIELDS"
export LIVE_VIS_ENABLE LIVE_VIS_FIELD LIVE_VIS_EVERY LIVE_VIS_HOLD_ON_EXIT
export LIVE_VIS_RECORD_ENABLE LIVE_VIS_RECORD_EVERY LIVE_VIS_RECORD_FIELDS
export FILTERED_RECORDING_ENABLE FILTER_SAMPLE_EVERY PARTICLE_TYPE_FILTER OVERWRITE_LIVEVIS_CONTROL
export RECORD_ENABLE RECORD_EVERY RECORD_FIELDS

# Same Q6-g-f/current no-resampling contract as x13j-m.
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
INACTIVE_SLOTS="${INACTIVE_SLOTS:-16384}"

GEN_CASE=tg
U0=0.0
VELOCITY_MODE=zero
PARTICLE_MASS="$LIQUID_MASS"
BACKGROUND_TYPE="$LIQUID_TYPE"
INACTIVE_TYPE="$LIQUID_TYPE"
TG_HOLE_ENABLE=false

suite_defaults_common_0434
suite_compute_derived_0434

read -r H SHEET_H SHEET_L EDGE_R RHO UTC TAUTC OH RE CA STEP_DISP LLOC_RC XCLR YCLR <<<"$(
python3 - "$Lx" "$Ly" "$NX" "$NY" "$GAMMA" "$LIQUID_MASS" \
          "$SHEET_LENGTH_CELLS" "$THICKNESS_CELLS" "$EDGE_ROUND_CELLS" \
          "$CENTER_X" "$CENTER_Y" "$SIGMA_DECLARED" "$NU_REF" "$DT" \
          "$ROTATION_ANGLE" "$SURFACE_TENSION_MIN_RADIUS_CELLS" <<'PY'
import math,sys
lx,ly=float(sys.argv[1]),float(sys.argv[2]); nx,ny=int(sys.argv[3]),int(sys.argv[4])
gamma,mass=float(sys.argv[5]),float(sys.argv[6]); Lc,Hc,Rc=map(float,sys.argv[7:10])
cx,cy,sigma,nu,dt,angle,rmin=map(float,sys.argv[10:17])
hx,hy=lx/nx,ly/ny
if abs(hx-hy)>1e-12*max(1.0,abs(hx),abs(hy)): raise SystemExit('[0493x13n] ERROR square cells required')
if abs(hx-1/256)>1e-12: raise SystemExit(f'[0493x13n] ERROR x13h qualification keeps h=1/256, got {hx}')
if abs(angle-2.0943951023931953)>1e-12: raise SystemExit(f'[0493x13n] ERROR x13h requires rotationAngle=120deg, got {angle}')
if rmin not in (3.0,4.0): raise SystemExit(f'[0493x13n] ERROR qualification/ablation supports minRadiusCells in {{3,4}}, got {rmin}')
if not (sigma>0 and nu>0 and dt>0 and Lc>0 and Hc>0 and Rc>0): raise SystemExit('[0493x13n] ERROR positive sigma,nu,dt and geometry required')
if Rc < 2*rmin: raise SystemExit(f'[0493x13n] ERROR edge-round radius should be >=2*Rmin for a clean initial cut; got {Rc}h')
if Rc >= Hc/2: raise SystemExit('[0493x13n] ERROR edge-round radius must be < H/2')
h=hx; H=Hc*h; L=Lc*h; rr=Rc*h; rho=gamma*mass/h**2
xclr=min(cx-L/2,lx-(cx+L/2)); yclr=min(cy-H/2,ly-(cy+H/2))
if min(xclr,yclr)<=16*h: raise SystemExit(f'[0493x13n] ERROR require >16h initial wall clearance, got x={xclr/h:.4g}h y={yclr/h:.4g}h')
utc=math.sqrt(2*sigma/(rho*H)); tau=H/utc; mu=rho*nu
oh=mu/math.sqrt(rho*sigma*H); Re=utc*H/nu; ca=mu*utc/sigma
stepdisp=utc*dt/h
rcool=25.298221281347036*h; lloc_rc=(H/2)/rcool
if lloc_rc <= 1.0: raise SystemExit(f'[0493x13n] ERROR qualification requires flat-sheet x12a cooling inactive: (H/2)/Rc={lloc_rc:.6g} <=1')
print(f'{h:.17g} {H:.17g} {L:.17g} {rr:.17g} {rho:.17g} {utc:.17g} {tau:.17g} {oh:.17g} {Re:.17g} {ca:.17g} {stepdisp:.17g} {lloc_rc:.17g} {xclr/h:.17g} {yclr/h:.17g}')
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
  --sheet-length-cells "$SHEET_LENGTH_CELLS" --thickness-cells "$THICKNESS_CELLS" \
  --edge-round-cells "$EDGE_ROUND_CELLS" \
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

# Q6-g-f free-surface path, identical contract to the qualified oscillating-drop runners.
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

# Existing x9 curvature/capillary path.  x9e/x9f drop-only diagnostics are off.
export MPCD_Q6_STATIC_DROP_DIAGNOSTICS_0493X9E=0
export MPCD_Q6_ELLIPSE_DIAGNOSTICS_0493X9F=0
export MPCD_Q6_PHASE_CURVATURE_DIAGNOSTICS_0493X9A=0
export MPCD_Q6_PHASE_CURVATURE_DIAGNOSTICS_0493X9B=1
export MPCD_Q6_PHASE_CURVATURE_DIAGNOSTICS_0493X9C=1
export MPCD_Q6_CONTACT_ANGLE_HARD_NORMAL_0493X9I=0
export MPCD_Q6_CONTACT_ANGLE_WALL_FACE_0493X9L=0
export MPCD_Q6_CONTACT_ANGLE_OFFSUPPORT_0493X9M=0

# Current x12 kinetic free-surface chain, unchanged.
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
export MPCD_X10_KINETIC_INTERFACE_ONE_FOR_ONE=0
export MPCD_X10_KINETIC_INTERFACE_ONE_FOR_ONE_SWAP=0
export MPCD_X10R_Q6_THERMAL_FULL_VECTOR_ENDPOINT_VELOCITY=0
export MPCD_X10S_Q6_THERMAL_SEGMENT_NORMAL_KINEMATICS=0
export MPCD_X10T_Q6_THERMAL_RIGID_TANGENTIAL_KINEMATICS=0
export MPCD_X10_KINETIC_INTERFACE_THERMAL_PHASE_LIMITER=0
# x12a remains ON by default (production contract) but is now explicitly
# overridable for the Taylor-Culick causal ablation.  This changes runner
# orchestration only; no C++/CUDA source path is modified.
MPCD_X12A_LOCAL_THERMAL_COOLING="${MPCD_X12A_LOCAL_THERMAL_COOLING:-1}"
case "$MPCD_X12A_LOCAL_THERMAL_COOLING" in
  0|1|true|false|TRUE|FALSE) ;;
  *) echo "[0493x13n] ERROR MPCD_X12A_LOCAL_THERMAL_COOLING must be 0/1/true/false, got '$MPCD_X12A_LOCAL_THERMAL_COOLING'" >&2; exit 2 ;;
esac
export MPCD_X12A_LOCAL_THERMAL_COOLING
export MPCD_X12A_LOCAL_THERMAL_RADIUS_CELLS="${MPCD_X12A_LOCAL_THERMAL_RADIUS_CELLS:-25.298221281347036}"

LIVE_VIS_CONTROL_FILE="$RUN_ROOT/livevis_control_0493x13n.kv"
export LIVE_VIS_CONTROL_FILE
suite_prepare_livevis_control_0434 "$RUN_ROOT" "$RUN_MODE"
suite_export_livevis_0434
suite_write_env_file_0434 "$RUN_ROOT/logs/environment_0493x13n.env" "$RUN_MODE"
cat >> "$RUN_ROOT/logs/environment_0493x13n.env" <<META
X13N_SHEET_LENGTH_CELLS=$SHEET_LENGTH_CELLS
X13N_THICKNESS_CELLS=$THICKNESS_CELLS
X13N_EDGE_ROUND_CELLS=$EDGE_ROUND_CELLS
X13N_SIGMA=$SIGMA_DECLARED
X13N_NU_REF=$NU_REF
X13N_U_TC=$UTC
X13N_TAU_TC=$TAUTC
X13N_OH=$OH
X13N_RE_TC=$RE
X13N_CA=$CA
X13N_U_DT_OVER_H=$STEP_DISP
X13N_HHALF_OVER_X12A_RC=$LLOC_RC
X13N_FIT_TAU_MIN=$FIT_TAU_MIN
X13N_FIT_TAU_MAX=$FIT_TAU_MAX
X13N_RMIN_CELLS=$SURFACE_TENSION_MIN_RADIUS_CELLS
X13N_X12A_LOCAL_THERMAL_COOLING=$MPCD_X12A_LOCAL_THERMAL_COOLING
X13N_LIVE_VIS_ENABLE=$LIVE_VIS_ENABLE
X13N_LIVE_VIS_EVERY=$LIVE_VIS_EVERY
X13N_LIVE_VIS_RECORD_ENABLE=$LIVE_VIS_RECORD_ENABLE
X13N_LIVE_VIS_RECORD_EVERY=$LIVE_VIS_RECORD_EVERY
X13N_LIVE_VIS_RECORD_FIELDS=$LIVE_VIS_RECORD_FIELDS
META

printf '%s\n' \
  '===== 0493x13n 2-D TAYLOR-CULICK SHEET / x13h =====' \
  '[0493x13n] objective=nonlinear free-sheet retraction speed; no source modification' \
  "[0493x13n] grid=${NX}x${NY} L=${Lx}x${Ly} h=$H gamma=$GAMMA dt=$DT kBT=$KBT" \
  "[0493x13n] sheet L/h=$SHEET_LENGTH_CELLS H/h=$THICKNESS_CELLS edgeRound/h=$EDGE_ROUND_CELLS xClear/h=$XCLR yClear/h=$YCLR" \
  "[0493x13n] sigma=$SIGMA_DECLARED rho=$RHO U_TC=$UTC tau_TC=$TAUTC Re_TC=$RE Oh=$OH Ca=$CA Udt/h=$STEP_DISP" \
  "[0493x13n] x12a=$MPCD_X12A_LOCAL_THERMAL_COOLING flat-sheet (H/2)/Rc=$LLOC_RC > 1; when x12a=1 cooling is initially inactive on planar core" \
  "[0493x13n] LiveVis enable=$LIVE_VIS_ENABLE every=$LIVE_VIS_EVERY record=$LIVE_VIS_RECORD_ENABLE recordEvery=$LIVE_VIS_RECORD_EVERY fields=$LIVE_VIS_RECORD_FIELDS" \
  "[0493x13n] fit window t/tau=[$FIT_TAU_MIN,$FIT_TAU_MAX]; edge thresholds 0.35/0.50/0.65 audited offline" \
  "[0493x13n] steps=$STEPS tEnd=$(awk -v n="$STEPS" -v d="$DT" 'BEGIN{printf "%.9g",n*d}') summaryEvery=$SUMMARY_EVERY dumpStateEvery=$DUMP_STATE_EVERY"

suite_run_binary_0434 "$PARAMS" "$LOG" "$TIME_FILE" "$OUT"

if ! suite_truthy_0434 "$PREFLIGHT_ONLY"; then
  shopt -s nullglob
  STATES=("$OUT"/state_step_*.smpcd)
  shopt -u nullglob
  (( ${#STATES[@]} >= 10 )) || { echo "[0493x13n] ERROR need >=10 state dumps, got ${#STATES[@]}" >&2; exit 2; }
  python3 "$ANALYZER" \
    --run-root "$RUN_ROOT" --Lx "$Lx" --Ly "$Ly" --nx "$NX" --ny "$NY" \
    --gamma "$GAMMA" --mass "$LIQUID_MASS" --sigma "$SIGMA_DECLARED" \
    --thickness-cells "$THICKNESS_CELLS" --sheet-length-cells "$SHEET_LENGTH_CELLS" \
    --edge-round-cells "$EDGE_ROUND_CELLS" --center-x "$CENTER_X" --center-y "$CENTER_Y" \
    --dt "$DT" --nu "$NU_REF" --fit-tau-min "$FIT_TAU_MIN" --fit-tau-max "$FIT_TAU_MAX"
  echo "[0493x13n] COMPLETE run=$RUN_ROOT analysis=$RUN_ROOT/analysis_0493x13n"
fi
