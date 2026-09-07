#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$ROOT/scripts/src_mpcd_run_ok_common.sh"
suite_root_cd_0434

# 0493x14al — STRICTLY PAIRED historical-x13h Taylor-Culick A/B.
# CASE=liquid      : current code, historical qualified liquid/vacuum physics.
# CASE=liquid_gas  : same liquid point + current x14 gas/coupling.
# Tooling only: no C++/CUDA modification and no new runtime diagnostic.

CASE="${CASE:-}"
case "$CASE" in
  liquid|liquid_gas) ;;
  *) echo "[0493x14al] ERROR set CASE=liquid or CASE=liquid_gas" >&2; exit 2 ;;
esac

GENERATOR="$ROOT/scripts/generate_0493x14al_taylor_culick_historical_ab.py"
ANALYZER="$ROOT/scripts/analyze_0493x14al_taylor_culick_recording.py"
HIST_ANALYZER="$ROOT/scripts/analyze_0493x13n_taylor_culick_sheet_2d.py"
SRC14V="$ROOT/src/cuda_q6_resident_0400.cu"
for f in "$GENERATOR" "$ANALYZER" "$SRC14V"; do
  [[ -f "$f" ]] || { echo "[0493x14al] ERROR missing $f" >&2; exit 2; }
done
if [[ "$CASE" == liquid ]]; then
  [[ -f "$HIST_ANALYZER" ]] || { echo "[0493x14al] ERROR historical analyzer missing: $HIST_ANALYZER" >&2; exit 2; }
else
  grep -q '0493x14ai — production-candidate device-side Q6 resultant closure' "$SRC14V" || {
    echo '[0493x14al] ERROR x14ai source marker missing' >&2; exit 2;
  }
  grep -q 'B1-exact-post-periodic-device-target' "$SRC14V" || {
    echo '[0493x14al] ERROR x14ai-fix1 source marker missing' >&2; exit 2;
  }
fi

# -----------------------------------------------------------------------------
# HISTORICAL x13h POINT — visible and intentionally immutable by default.
# These are the physical/numerical parameters of the qualified TC campaign.
# -----------------------------------------------------------------------------
Lx="${Lx:-3.5}"; Ly="${Ly:-1.0}"; NX="${NX:-896}"; NY="${NY:-256}"
GAMMA="${GAMMA:-8}"
DT="${DT:-0.0063471328149122585}"
LIQUID_KBT="${LIQUID_KBT:-0.125}"
LIQUID_MASS="${LIQUID_MASS:-1.0}"
LIQUID_TYPE="${LIQUID_TYPE:-1}"
ROTATION_ANGLE="${ROTATION_ANGLE:-2.0943951023931953}"  # 120 deg
RANDOM_ROTATION_SIGN="${RANDOM_ROTATION_SIGN:-true}"
GRID_SHIFT_ENABLE="${GRID_SHIFT_ENABLE:-true}"
THERMOSTAT_ENABLE="${THERMOSTAT_ENABLE:-true}"
THERMOSTAT_MODE="${THERMOSTAT_MODE:-cell_relative_rescale}"
THERMOSTAT_EVERY="${THERMOSTAT_EVERY:-1}"
THERMOSTAT_TARGET_KBT="${THERMOSTAT_TARGET_KBT:-$LIQUID_KBT}"
THERMOSTAT_MIN_PARTICLES="${THERMOSTAT_MIN_PARTICLES:-3}"
KBT="$LIQUID_KBT"

SHEET_LENGTH_CELLS="${SHEET_LENGTH_CELLS:-768}"
THICKNESS_CELLS="${THICKNESS_CELLS:-64}"
EDGE_ROUND_CELLS="${EDGE_ROUND_CELLS:-8}"
CENTER_X="${CENTER_X:-1.75}"; CENTER_Y="${CENTER_Y:-0.5}"
SURFACE_TENSION_SIGMA="${SURFACE_TENSION_SIGMA:-10000.0}"
SURFACE_TENSION_MIN_RADIUS_CELLS="${SURFACE_TENSION_MIN_RADIUS_CELLS:-4}"
SEED="${SEED:-4931501}"
NU_REF="${NU_REF:-0.00051}"
HISTORICAL_G_TC_X13H="${HISTORICAL_G_TC_X13H:-0.79457172}"
FIT_TAU_MIN="${FIT_TAU_MIN:-0.5}"; FIT_TAU_MAX="${FIT_TAU_MAX:-1.75}"
STEPS="${STEPS:-220}"
SUMMARY_EVERY="${SUMMARY_EVERY:-5}"

# Gas exists only in case B.  These are the current x14 gas properties; they do
# not alter the historical liquid point.  Exterior occupancy uses the same
# gamma=8 so rhoG/rhoL = GAS_MASS/LIQUID_MASS = 0.1.
GAS_TYPE="${GAS_TYPE:-2}"
GAS_MASS="${GAS_MASS:-0.1}"
GAS_KBT="${GAS_KBT:-0.08}"
LIQUID_Q6_STRENGTH="${LIQUID_Q6_STRENGTH:-1.0}"
GAS_Q6_STRENGTH="${GAS_Q6_STRENGTH:-0.0}"

PHASE_INTERFACE_KINETIC_REFLECTION_FRACTION="${PHASE_INTERFACE_KINETIC_REFLECTION_FRACTION:-1.0}"
PHASE_INTERFACE_EVAPORATION_TARGET_TYPE="${PHASE_INTERFACE_EVAPORATION_TARGET_TYPE:--1}"
PHASE_INTERFACE_CONTACT_ANGLE_DEG="${PHASE_INTERFACE_CONTACT_ANGLE_DEG:--1}"
X10O_THERMAL_SIGMAS="${X10O_THERMAL_SIGMAS:-3.0}"
X10O_THERMAL_MAX_CELLS="${X10O_THERMAL_MAX_CELLS:-0.75}"
X12A_LOCAL_THERMAL_RADIUS_CELLS="${X12A_LOCAL_THERMAL_RADIUS_CELLS:-25.298221281347036}"

# Historical Q6-g-f contract.
RUN_MODE="src-q6-g-f"
TOPOLOGY="closed_box"
PROJECTION_BACKEND="${PROJECTION_BACKEND:-cuda}"
PROJECTION_OPERATOR="${PROJECTION_OPERATOR:-auto_fv_cg}"
PROJECTION_MAX_ITERATIONS="${PROJECTION_MAX_ITERATIONS:-2000}"
PROJECTION_TOLERANCE="${PROJECTION_TOLERANCE:-1.0e-5}"
PROJECTION_MOMENTUM_CORRECTION_ENABLE=false
Q6_PROJECTION_STRENGTH=1.0
Q6_STRICT=1
Q6_FORCE_PROJECTION_MODE=prestream_single_fused
Q6_GF_EXTERNAL_SPECIES=1
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

# Output-only differences are intentional: A keeps historical 10-step states so
# the original x13n analyzer can be replayed; B avoids ~2 GB of full-state dumps.
if [[ "$CASE" == liquid ]]; then
  DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-10}"
else
  DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-110}"
fi

# Common A/B metrology: full simulation-grid liquid mass every 10 steps.
LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-1}"
LIVE_VIS_FIELD="${LIVE_VIS_FIELD:-mass}"
LIVE_VIS_EVERY="${LIVE_VIS_EVERY:-1}"
LIVE_VIS_NX="${LIVE_VIS_NX:-896}"; LIVE_VIS_NY="${LIVE_VIS_NY:-256}"
LIVE_VIS_HOLD_ON_EXIT="${LIVE_VIS_HOLD_ON_EXIT:-1}"
LIVE_VIS_RECORD_ENABLE="${LIVE_VIS_RECORD_ENABLE:-1}"
LIVE_VIS_RECORD_EVERY="${LIVE_VIS_RECORD_EVERY:-10}"
LIVE_VIS_RECORD_FIELDS="${LIVE_VIS_RECORD_FIELDS:-mass}"
FILTERED_RECORDING_ENABLE="${FILTERED_RECORDING_ENABLE:-1}"
FILTER_SAMPLE_EVERY="${FILTER_SAMPLE_EVERY:-10}"
PARTICLE_TYPE_FILTER="$LIQUID_TYPE"
OVERWRITE_LIVEVIS_CONTROL=1
RECORD_ENABLE=true
RECORD_EVERY="$LIVE_VIS_RECORD_EVERY"
RECORD_FIELDS="$LIVE_VIS_RECORD_FIELDS"
FILTER_MODE=none

CLEAN_RUN_ROOT="${CLEAN_RUN_ROOT:-1}"
PREFLIGHT_ONLY="${PREFLIGHT_ONLY:-0}"
BIN="${BIN:-${SRC_MPCD_DEFAULT_BIN_0434:-build/src_mpcd_base_cuda_q6_resident_livevis_0486}}"
CAMPAIGN_BASE="${CAMPAIGN_BASE:-runs/0493x14al_tc_historical_x13h}"
RUN_ROOT="${RUN_ROOT:-${CAMPAIGN_BASE}_${CASE}_seed${SEED}}"
CASE_LABEL="0493x14al_tc_historical_${CASE}"

GEN_CASE=tg; U0=0.0; VELOCITY_MODE=zero
PARTICLE_MASS="$LIQUID_MASS"
BACKGROUND_TYPE="$LIQUID_TYPE"; INACTIVE_TYPE="$LIQUID_TYPE"; TG_HOLE_ENABLE=false
SPECIES_RESIDENT_MODE=off
RESAMPLING_HOST_PATCHBACK_ENABLE=0; MASS_RECONDITION_ENABLE=0
RESAMPLING_THERMAL_RENORMALIZATION_ENABLE=false; RESAMPLING_MASS_GUARD_ENABLE=false
RUN_OK_REFERENCE_PARTICLE_MASS="$LIQUID_MASS"
RUN_OK_GENERATOR_PATH="$GENERATOR"
export RUN_OK_REFERENCE_PARTICLE_MASS RUN_OK_GENERATOR_PATH

if [[ "$CASE" == liquid_gas ]]; then
  Q6_GF_HAS_GAS_PHASE=1
  PHASE_INTERFACE_A_SELECTOR="type:${LIQUID_TYPE}"
  PHASE_INTERFACE_B_SELECTOR="type:${GAS_TYPE}"
else
  Q6_GF_HAS_GAS_PHASE=0
  PHASE_INTERFACE_A_SELECTOR="type:${LIQUID_TYPE}"
  PHASE_INTERFACE_B_SELECTOR="vacuum"
fi

suite_defaults_common_0434
suite_compute_derived_0434

read -r H SHEET_H RHO_L RHO_G UTC TAUTC UDT LAMBDA_PROXY XCLR YCLR P_REF <<<"$(python3 - \
 "$Lx" "$Ly" "$NX" "$NY" "$GAMMA" "$LIQUID_MASS" "$GAS_MASS" "$LIQUID_KBT" "$GAS_KBT" \
 "$THICKNESS_CELLS" "$SHEET_LENGTH_CELLS" "$CENTER_X" "$CENTER_Y" "$SURFACE_TENSION_SIGMA" "$DT" "$ROTATION_ANGLE" <<'PY'
import math,sys
lx,ly=float(sys.argv[1]),float(sys.argv[2]); nx,ny=int(sys.argv[3]),int(sys.argv[4])
g,mL,mG,kL,kG,Hc,Lc,cx,cy,sigma,dt,ang=map(float,sys.argv[5:17])
hx,hy=lx/nx,ly/ny
if abs(hx-hy)>1e-12*max(1.0,abs(hx),abs(hy)): raise SystemExit('[0493x14al] square cells required')
if abs(hx-1/256)>1e-12: raise SystemExit(f'[0493x14al] historical h=1/256 required, got {hx:.17g}')
if abs(ang-2.0943951023931953)>1e-12: raise SystemExit('[0493x14al] historical rotationAngle=120deg required')
if int(g)!=8: raise SystemExit('[0493x14al] historical gamma=8 required')
if abs(kL-.125)>1e-14: raise SystemExit('[0493x14al] historical liquid kBT=0.125 required')
if abs(dt-0.0063471328149122585)>1e-15: raise SystemExit('[0493x14al] historical dt mismatch')
h=hx; H=Hc*h; L=Lc*h; A=h*h; rhoL=g*mL/A; rhoG=g*mG/A
utc=math.sqrt(2*sigma/(rhoL*H)); tau=H/utc; udt=utc*dt/h
# Printed only: simple thermal flight proxy, not used as a constraint.
lproxy=math.sqrt(kL/mL)*dt/h
xclr=min(cx-L/2,lx-(cx+L/2)); yclr=min(cy-H/2,ly-(cy+H/2)); pref=g*kG/A
print(f'{h:.17g} {H:.17g} {rhoL:.17g} {rhoG:.17g} {utc:.17g} {tau:.17g} {udt:.17g} {lproxy:.17g} {xclr/h:.17g} {yclr/h:.17g} {pref:.17g}')
PY
)"

if suite_truthy_0434 "$CLEAN_RUN_ROOT"; then rm -rf "$RUN_ROOT"; fi
suite_prepare_dirs_0434 "$RUN_ROOT"
STATE="$RUN_ROOT/init/${CASE_LABEL}.smpcd"
OUT="$RUN_ROOT/output"
PARAMS="$RUN_ROOT/params/${CASE_LABEL}.kv"
LOG="$RUN_ROOT/logs/${CASE_LABEL}.log"
TF="$RUN_ROOT/logs/${CASE_LABEL}.time"
ANALYSIS_DIR="$RUN_ROOT/analysis_0493x14al"
mkdir -p "$OUT" "$ANALYSIS_DIR"

python3 "$GENERATOR" \
  --case "$CASE" --output "$STATE" --Lx "$Lx" --Ly "$Ly" --nx "$NX" --ny "$NY" --gamma "$GAMMA" \
  --center-x "$CENTER_X" --center-y "$CENTER_Y" --sheet-length-cells "$SHEET_LENGTH_CELLS" \
  --thickness-cells "$THICKNESS_CELLS" --edge-round-cells "$EDGE_ROUND_CELLS" \
  --liquid-type "$LIQUID_TYPE" --gas-type "$GAS_TYPE" --liquid-mass "$LIQUID_MASS" --gas-mass "$GAS_MASS" \
  --liquid-kBT "$LIQUID_KBT" --gas-kBT "$GAS_KBT" --seed "$SEED"

LREF="$(awk -v g="$GAMMA" -v m="$LIQUID_MASS" 'BEGIN{printf "%.17g",g*m}')"
GREF="$(awk -v g="$GAMMA" -v m="$GAS_MASS" 'BEGIN{printf "%.17g",g*m}')"
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
taylorGreenForcingEnable = false
wallVpEnable = false
wallAccommodation = 1.0
wallKBT = -1.0
wallThermalNoise = 0.0
surfaceTensionSigma = $SURFACE_TENSION_SIGMA
surfaceTensionMinRadiusCells = $SURFACE_TENSION_MIN_RADIUS_CELLS
phaseInterfaceKineticReflectionFraction = $PHASE_INTERFACE_KINETIC_REFLECTION_FRACTION
phaseInterfaceEvaporationTargetType = $PHASE_INTERFACE_EVAPORATION_TARGET_TYPE
phaseInterfaceASelector = $PHASE_INTERFACE_A_SELECTOR
phaseInterfaceBSelector = $PHASE_INTERFACE_B_SELECTOR
phaseInterfaceContactAngleDegrees = $PHASE_INTERFACE_CONTACT_ANGLE_DEG
speciesRegistryEnable = true
PARAMS

if [[ "$CASE" == liquid ]]; then
cat >> "$PARAMS" <<PARAMS
speciesCount = 1
species0 = $LIQUID_TYPE q6_g_f_liquid liquid $LIQUID_Q6_STRENGTH 1.0 $LREF
species0ResamplingEnable = false
speciesRequireRegisteredTypes = true
speciesThermostatEnable = false
speciesDiagnosticsEnable = true
speciesDiagnosticsFilename = species_runtime_0493x14al.csv
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
else
cat >> "$PARAMS" <<PARAMS
speciesCount = 2
species0 = $LIQUID_TYPE q6_g_f_liquid liquid $LIQUID_Q6_STRENGTH 1.0 $LREF
species0ResamplingEnable = false
species0ThermostatTargetKBT = $LIQUID_KBT
species1 = $GAS_TYPE compressible_gas gas $GAS_Q6_STRENGTH 0.0 $GREF
species1ResamplingEnable = false
species1ThermostatTargetKBT = $GAS_KBT
speciesRequireRegisteredTypes = true
speciesThermostatEnable = true
speciesDiagnosticsEnable = true
speciesDiagnosticsFilename = species_runtime_0493x14al.csv
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
phaseInterfaceKineticBilateralRelocation = true
PARAMS
fi
suite_write_common_params_0434 "$RUN_MODE" >> "$PARAMS"

suite_export_cuda_flags_0434 "$RUN_MODE" "$TOPOLOGY"

# Historical x13h free-surface Q6/capillary path — identical in A and B except x6g.
export MPCD_Q6_PHASE_GEOMETRY_RESIDENT_0493X6C=1
export MPCD_Q6_PHASE_GEOMETRY_CUTFACE_0493X6D=0
export MPCD_Q6_PHASE_INTERFACE_TOPOLOGY_0493X6E=1
export MPCD_Q6_PHASE_INTERFACE_STENCIL_0493X6F=1
export MPCD_Q6_PHASE_PRESSURE_DIAGNOSTICS_0493X6A=0
export MPCD_Q6_PHASE_GEOMETRY_DIAGNOSTICS_0493X6B=0
export MPCD_Q6_POSTAPPLY_REGION_DIAGNOSTICS_0493X6H_B0=0
export MPCD_Q6_FACE_TO_PARTICLE_RT0_0493X6H_B1=1
export MPCD_Q6_STATIC_DROP_DIAGNOSTICS_0493X9E=0
export MPCD_Q6_ELLIPSE_DIAGNOSTICS_0493X9F=0
export MPCD_Q6_PHASE_CURVATURE_DIAGNOSTICS_0493X9A=0
export MPCD_Q6_PHASE_CURVATURE_DIAGNOSTICS_0493X9B=1
export MPCD_Q6_PHASE_CURVATURE_DIAGNOSTICS_0493X9C=1
export MPCD_Q6_CONTACT_ANGLE_HARD_NORMAL_0493X9I=0
export MPCD_Q6_CONTACT_ANGLE_WALL_FACE_0493X9L=0
export MPCD_Q6_CONTACT_ANGLE_OFFSUPPORT_0493X9M=0

# Qualified liquid chain — identical historical settings in both cases.
export MPCD_X10J_SIMPLE_SPECULAR_ABLATION=0
export MPCD_X10K_LOCAL_FRAME_SPECULAR_ABLATION=0
export MPCD_X10M_MOVING_INTERFACE_WALL=0
export MPCD_X10N_Q6_CONTINUOUS_INTERFACE_WALL=0
export MPCD_X10O_Q6_THERMAL_INTERFACE_WALL=1
export MPCD_X10O_THERMAL_PARTICLE_MASS="$LIQUID_MASS"
export MPCD_X10O_THERMAL_SIGMAS="$X10O_THERMAL_SIGMAS"
export MPCD_X10O_THERMAL_MAX_CELLS="$X10O_THERMAL_MAX_CELLS"
export MPCD_X10P_INITIAL_OVERLAP_RESOLUTION=1
export MPCD_X10L_PREWALL_INTERFACE_DIAGNOSTICS=0
export MPCD_X10_KINETIC_INTERFACE_CIC=1
export MPCD_X10_KINETIC_INTERFACE_QUADRATIC=1
export MPCD_X10_KINETIC_INTERFACE_ONE_FOR_ONE=1
export MPCD_X10_KINETIC_INTERFACE_ONE_FOR_ONE_SWAP=1
export MPCD_X10_KINETIC_INTERFACE_ONE_FOR_ONE_NORMAL_ONLY=0
export MPCD_X10R_Q6_THERMAL_FULL_VECTOR_ENDPOINT_VELOCITY=0
export MPCD_X10S_Q6_THERMAL_SEGMENT_NORMAL_KINEMATICS=0
export MPCD_X10T_Q6_THERMAL_RIGID_TANGENTIAL_KINEMATICS=0
export MPCD_X10_KINETIC_INTERFACE_THERMAL_PHASE_LIMITER=0
export MPCD_X12A_LOCAL_THERMAL_COOLING=1
export MPCD_X12A_LOCAL_THERMAL_RADIUS_CELLS="$X12A_LOCAL_THERMAL_RADIUS_CELLS"

# Case-specific gas/x14 branch.  Every x14 gate is explicit to avoid shell leakage.
if [[ "$CASE" == liquid_gas ]]; then
  export MPCD_Q6_PHASE_GAS_PRESSURE_0493X6G=1
  export MPCD_Q6_PHASE_GAS_PRESSURE_MODE_0493X6G=eos_accessible_volume
  export MPCD_Q6_PHASE_GAS_PRESSURE_CONSTANT_0493X6G=0
  export MPCD_Q6_PHASE_GAS_PRESSURE_REFERENCE_0493X6G="$P_REF"
  export MPCD_Q6_PHASE_GAS_PRESSURE_SCALE_0493X6G=1
  export MPCD_X14L_GAS_SPECULAR_REFLECTION=1
  export MPCD_X14V_GAS_KINETIC_EXCESS_KICK=1
  export MPCD_X14V_SUBTRACT_X6G_THERMODYNAMIC_TRACTION=1
  export MPCD_X14V_X6G_FACE_THERMO_TRACTION=0
  export MPCD_X14V_X6G_GAUGE_FACE_THERMO_TRACTION=0
  export MPCD_X14V_X6G_GAUGE_RESULTANT_PROJECTION=0
  export MPCD_X14V_X6G_LOCAL_FACE_GAUGE_PROJECTION=1
  export MPCD_X14V_REFERENCE_PRESSURE_GEOMETRIC_CLOSURE=0
  export MPCD_X14V_SCATTER_LOSS_DIAGNOSTIC=0
  export MPCD_X14V_GLOBAL_BALANCE_DIAGNOSTIC=0
  export MPCD_X14V_DEVICE_APPLIED_Q6_RESULTANT_CLOSURE=1
else
  export MPCD_Q6_PHASE_GAS_PRESSURE_0493X6G=0
  export MPCD_Q6_PHASE_GAS_PRESSURE_CONSTANT_0493X6G=0
  export MPCD_Q6_PHASE_GAS_PRESSURE_REFERENCE_0493X6G=0
  export MPCD_Q6_PHASE_GAS_PRESSURE_SCALE_0493X6G=0
  export MPCD_X14L_GAS_SPECULAR_REFLECTION=0
  export MPCD_X14V_GAS_KINETIC_EXCESS_KICK=0
  export MPCD_X14V_SUBTRACT_X6G_THERMODYNAMIC_TRACTION=0
  export MPCD_X14V_X6G_FACE_THERMO_TRACTION=0
  export MPCD_X14V_X6G_GAUGE_FACE_THERMO_TRACTION=0
  export MPCD_X14V_X6G_GAUGE_RESULTANT_PROJECTION=0
  export MPCD_X14V_X6G_LOCAL_FACE_GAUGE_PROJECTION=0
  export MPCD_X14V_REFERENCE_PRESSURE_GEOMETRIC_CLOSURE=0
  export MPCD_X14V_SCATTER_LOSS_DIAGNOSTIC=0
  export MPCD_X14V_GLOBAL_BALANCE_DIAGNOSTIC=0
  export MPCD_X14V_DEVICE_APPLIED_Q6_RESULTANT_CLOSURE=0
fi

# Run-specific control file only.  Never touch ./livevis_control.kv.
LIVE_VIS_CONTROL_FILE="$RUN_ROOT/livevis_control_0493x14al_${CASE}.kv"
export LIVE_VIS_CONTROL_FILE LIVE_VIS_ENABLE LIVE_VIS_FIELD LIVE_VIS_EVERY LIVE_VIS_NX LIVE_VIS_NY LIVE_VIS_HOLD_ON_EXIT
export LIVE_VIS_RECORD_ENABLE LIVE_VIS_RECORD_EVERY LIVE_VIS_RECORD_FIELDS FILTERED_RECORDING_ENABLE FILTER_SAMPLE_EVERY
export PARTICLE_TYPE_FILTER OVERWRITE_LIVEVIS_CONTROL RECORD_ENABLE RECORD_EVERY RECORD_FIELDS FILTER_MODE
suite_prepare_livevis_control_0434 "$RUN_ROOT" "$RUN_MODE"
suite_export_livevis_0434
suite_write_env_file_0434 "$RUN_ROOT/logs/environment_0493x14al.env" "$RUN_MODE"
cat >> "$RUN_ROOT/logs/environment_0493x14al.env" <<META
BENCHMARK=0493x14al_historical_x13h_taylor_culick_ab
CASE=$CASE
NX=$NX
NY=$NY
LX=$Lx
LY=$Ly
GAMMA=$GAMMA
LIQUID_KBT=$LIQUID_KBT
DT=$DT
ROTATION_ANGLE=$ROTATION_ANGLE
SHEET_LENGTH_CELLS=$SHEET_LENGTH_CELLS
THICKNESS_CELLS=$THICKNESS_CELLS
EDGE_ROUND_CELLS=$EDGE_ROUND_CELLS
SIGMA=$SURFACE_TENSION_SIGMA
SEED=$SEED
U_TC=$UTC
TAU_TC=$TAUTC
HISTORICAL_G_TC=$HISTORICAL_G_TC_X13H
GAS_MASS=$GAS_MASS
GAS_KBT=$GAS_KBT
LIVE_VIS_CONTROL_FILE=$LIVE_VIS_CONTROL_FILE
META

LIQ_SHA="$(python3 - "$STATE.json" <<'PY'
import json,sys
print(json.load(open(sys.argv[1]))['liquidInitialCanonicalSHA256'])
PY
)"

echo
echo "===== 0493x14al HISTORICAL-x13h TC A/B : $CASE ====="
echo "PATHS: runner=$ROOT/scripts/run_0493x14al_taylor_culick_historical_ab.sh"
echo "       generator=$GENERATOR analyzer=$ANALYZER"
echo "       state=$STATE params=$PARAMS output=$OUT"
echo "PAIR:  liquidInitialSHA256=$LIQ_SHA"
echo "HIST:  grid=${NX}x${NY} L=${Lx}x${Ly} h=$H gamma=$GAMMA angle=120deg"
echo "       kBT_L=$LIQUID_KBT dt=$DT sheet L/h=$SHEET_LENGTH_CELLS H/h=$THICKNESS_CELLS edge/h=$EDGE_ROUND_CELLS"
echo "       sigma=$SURFACE_TENSION_SIGMA seed=$SEED U_TC=$UTC tau_TC=$TAUTC historicalG=$HISTORICAL_G_TC_X13H"
echo "       thermalFlightProxy=sqrt(kBT/m)*dt/h=$LAMBDA_PROXY (documented x13h lambda/h=0.72 uses campaign convention)"
if [[ "$CASE" == liquid_gas ]]; then
  echo "GAS:   type=$GAS_TYPE mG=$GAS_MASS kBT_G=$GAS_KBT rhoG/rhoL=$(awk -v g="$RHO_G" -v l="$RHO_L" 'BEGIN{printf "%.9g",g/l}')"
  echo "CHAIN: historical liquid x10o+CIC+Q2+x10p/q+x10u+x10v+x12a + x6g+x14l+x14v+x14ad+x14ai-fix1"
else
  echo "GAS:   absent / vacuum reference"
  echo "CHAIN: historical qualified liquid x10o+CIC+Q2+x10p/q+x10u+x10v+x12a; all x14 gates OFF"
fi
echo "RUN:   steps=$STEPS summaryEvery=$SUMMARY_EVERY dumpEvery=$DUMP_STATE_EVERY"
echo "METRO: liquid mass recording ${LIVE_VIS_NX}x${LIVE_VIS_NY} every=$LIVE_VIS_RECORD_EVERY; q35/q50/q65 common A/B analyzer"
echo "VIS:   enable=$LIVE_VIS_ENABLE every=$LIVE_VIS_EVERY control=$LIVE_VIS_CONTROL_FILE"
echo "NOTE:  ./livevis_control.kv is NOT modified"
echo "=========================================================="

suite_run_binary_0434 "$PARAMS" "$LOG" "$TF" "$OUT"
if suite_truthy_0434 "$PREFLIGHT_ONLY"; then echo '[0493x14al] PREFLIGHT_ONLY complete'; exit 0; fi

if [[ "$CASE" == liquid_gas ]]; then
  grep -q 'deviceAppliedQ6ResultantClosure=B1-exact-post-periodic-device-target' "$LOG" || {
    echo '[0493x14al] ERROR expected x14ai-fix1 runtime marker absent' >&2; exit 2;
  }
fi

python3 "$ANALYZER" \
  --case "$CASE" --run-root "$RUN_ROOT" --Lx "$Lx" --Ly "$Ly" --nx "$NX" --ny "$NY" \
  --gamma "$GAMMA" --liquid-mass "$LIQUID_MASS" --sigma "$SURFACE_TENSION_SIGMA" \
  --thickness-cells "$THICKNESS_CELLS" --dt "$DT" --fit-tau-min "$FIT_TAU_MIN" --fit-tau-max "$FIT_TAU_MAX" \
  --historical-g-tc "$HISTORICAL_G_TC_X13H"

# A additionally replays the exact historical state-dump analyzer as an anchor.
if [[ "$CASE" == liquid ]]; then
  python3 "$HIST_ANALYZER" \
    --run-root "$RUN_ROOT" --Lx "$Lx" --Ly "$Ly" --nx "$NX" --ny "$NY" \
    --gamma "$GAMMA" --mass "$LIQUID_MASS" --sigma "$SURFACE_TENSION_SIGMA" \
    --thickness-cells "$THICKNESS_CELLS" --sheet-length-cells "$SHEET_LENGTH_CELLS" \
    --edge-round-cells "$EDGE_ROUND_CELLS" --center-x "$CENTER_X" --center-y "$CENTER_Y" \
    --dt "$DT" --nu "$NU_REF" --fit-tau-min "$FIT_TAU_MIN" --fit-tau-max "$FIT_TAU_MAX"
fi

OUT_TAR="$RUN_ROOT/0493x14al_tc_historical_${CASE}_compact.tar.gz"
FILES=("analysis_0493x14al" "output/recordings" "recordings" "output/species_runtime_0493x14al.csv" \
       "output/cuda_phase_interface_pressure_0493x6g.csv" "output/cuda_phase_interface_stencil_0493x6f.csv" \
       "output/cuda_surface_tension_limiter_0493x9r.csv" "output/cuda_phase_kinetic_crossing_0493x9z.csv" \
       "output/cuda_species_q6_independent_masked_0493w5.csv" "output/cuda_species_q6_0491.csv" \
       "logs/${CASE_LABEL}.log" "logs/${CASE_LABEL}.time" "logs/environment_0493x14al.env" \
       "params/${CASE_LABEL}.kv" "init/${CASE_LABEL}.smpcd.json" "livevis_control_0493x14al_${CASE}.kv")
if [[ "$CASE" == liquid ]]; then FILES+=("analysis_0493x13n"); fi
EXIST=(); for f in "${FILES[@]}"; do [[ -e "$RUN_ROOT/$f" ]] && EXIST+=("$f"); done
tar -czf "$OUT_TAR" -C "$RUN_ROOT" "${EXIST[@]}"

echo
echo "[0493x14al] DONE case=$CASE"
echo "[0493x14al] report=$RUN_ROOT/analysis_0493x14al/taylor_culick_report.txt"
echo "[0493x14al] compact=$OUT_TAR"
