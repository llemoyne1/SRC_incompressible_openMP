#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# The current shared helper reads SEED while being sourced under set -u.
SEED="${SEED:-493205}"
source "$ROOT/scripts/src_mpcd_run_ok_common.sh"
suite_root_cd_0434

GENERATOR="$ROOT/scripts/generate_gas_jet_liquid_bath_2d.py"
ANALYZER="$ROOT/scripts/analyze_gas_jet_liquid_bath_2d.py"
SRC="$ROOT/src/cuda_q6_resident_0400.cu"
for f in "$GENERATOR" "$ANALYZER" "$SRC"; do
  [[ -f "$f" ]] || { echo "[gas-jet-bath] ERROR missing $f" >&2; exit 2; }
done
grep -q '0493x14ad — local-x6g-face gauge sampling' "$SRC" || {
  echo '[gas-jet-bath] ERROR current local gas-traction projection source marker not found' >&2; exit 2;
}

# =============================================================================
# 0493x14an — PLANAR GAS JET NORMAL TO A LIQUID BATH (2-D)
#
# Purpose: first application-scale qualification of gas -> liquid interaction.
# The central top segment injects a downward gas jet; two side segments on the
# same top face remove the returned gas.  The observable is the stationary or
# slowly varying indentation eta(x) of an initially flat liquid bath.
#
# Coupling under test, with meanings written explicitly:
#   x6g   : thermodynamic gas pressure in the liquid pressure boundary condition;
#   x9    : Laplace surface-tension pressure jump sigma*kappa;
#   x10o + CIC + Q2 + x10u/x10v + x12a:
#           qualified liquid-side kinetic support/relocalization closure;
#   x14l  : specular NORMAL reflection of gas particles at the moving interface;
#   x14v  : transfer to liquid of gas normal kinetic impulse in excess of the
#           thermodynamic pressure already represented by x6g;
#   x14ad : local mapping of x6g gauge traction to the interface segments.
#
# x14ai (global Q6-resultant closure) is FORCED OFF: this bath touches walls and
# the domain has external inlet/outlet segments, outside x14ai's valid scope.
#
# No C++/CUDA change.  ./livevis_control.kv remains user-owned/read-only.
# =============================================================================
CASE_LABEL="${CASE_LABEL:-0493x14an_planar_gas_jet_liquid_bath}"
RUN_MODE="src-q6-g-f"
TOPOLOGY="segmented"

# ---- Physical/numerical parameters: visible by design ------------------------
Lx="${Lx:-2.0}"; Ly="${Ly:-1.0}"; NX="${NX:-512}"; NY="${NY:-256}"
GAMMA="${GAMMA:-20}"
DT="${DT:-0.002}"
STEPS="${STEPS:-3000}"
BATH_HEIGHT="${BATH_HEIGHT:-0.75}"
GRAVITY_Y="${GRAVITY_Y:--0.5}"

LIQUID_TYPE="${LIQUID_TYPE:-1}"; GAS_TYPE="${GAS_TYPE:-2}"
LIQUID_MASS="${LIQUID_MASS:-1.0}"; GAS_MASS="${GAS_MASS:-0.1}"
LIQUID_KBT="${LIQUID_KBT:-0.02}"; GAS_KBT="${GAS_KBT:-0.08}"
KBT="$GAS_KBT"                     # x6g gas EOS reads the global kBT.
PARTICLE_MASS="$GAS_MASS"
RUN_OK_REFERENCE_PARTICLE_MASS="$LIQUID_MASS"

ROTATION_ANGLE="${ROTATION_ANGLE:-1.5707963267948966}" # 90 deg, same resolved liquid/gas fluid as multi-radius qualification
RANDOM_ROTATION_SIGN="${RANDOM_ROTATION_SIGN:-true}"
GRID_SHIFT_ENABLE="${GRID_SHIFT_ENABLE:-true}"
THERMOSTAT_ENABLE=true
THERMOSTAT_MODE="cell_relative_rescale"
THERMOSTAT_EVERY=1
THERMOSTAT_TARGET_KBT="$GAS_KBT"
THERMOSTAT_MIN_PARTICLES="${THERMOSTAT_MIN_PARTICLES:-3}"

SURFACE_TENSION_SIGMA="${SURFACE_TENSION_SIGMA:-2560.0}"
SURFACE_TENSION_MIN_RADIUS_CELLS="${SURFACE_TENSION_MIN_RADIUS_CELLS:-4}"
PHASE_INTERFACE_KINETIC_REFLECTION_FRACTION="${PHASE_INTERFACE_KINETIC_REFLECTION_FRACTION:-1.0}"
PHASE_INTERFACE_EVAPORATION_TARGET_TYPE="${PHASE_INTERFACE_EVAPORATION_TARGET_TYPE:--1}"
PHASE_INTERFACE_CONTACT_ANGLE_DEG="${PHASE_INTERFACE_CONTACT_ANGLE_DEG:--1}"
X10O_THERMAL_SIGMAS="${X10O_THERMAL_SIGMAS:-3.0}"
X10O_THERMAL_MAX_CELLS="${X10O_THERMAL_MAX_CELLS:-0.75}"
X12A_LOCAL_THERMAL_RADIUS_CELLS="${X12A_LOCAL_THERMAL_RADIUS_CELLS:-25.298221281347036}"
PHASE_INTERFACE_A_SELECTOR="type:${LIQUID_TYPE}"
PHASE_INTERFACE_B_SELECTOR="type:${GAS_TYPE}"

LIQUID_Q6_STRENGTH="${LIQUID_Q6_STRENGTH:-1.0}"
GAS_Q6_STRENGTH="${GAS_Q6_STRENGTH:-0.0}"
SPECIES_Q6_MIN_FILL_FRACTION="${SPECIES_Q6_MIN_FILL_FRACTION:-0.10}"

# Jet: 32 cells wide, centered at x=Lx/2, weak/moderate initial indentation.
JET_CENTER_X="${JET_CENTER_X:-1.0}"
JET_WIDTH_CELLS="${JET_WIDTH_CELLS:-32}"
JET_SPEED="${JET_SPEED:-0.5}"
JET_RAMP_START_TIME="${JET_RAMP_START_TIME:-0.0}"
JET_RAMP_END_TIME="${JET_RAMP_END_TIME:-0.20}"
JET_RAMP_INITIAL_FACTOR="${JET_RAMP_INITIAL_FACTOR:-0.0}"
JET_RAMP_FINAL_FACTOR="${JET_RAMP_FINAL_FACTOR:-1.0}"
# The current top same-face segmented resident path is exercised with HYBRID
# outlets in the existing Q6-g-f/dripping runners.  Keep this first benchmark
# on that already-exercised topology instead of using the right-outlet-specific
# Neumann qualification.
OUTLET_MODE="${OUTLET_MODE:-hybrid}"
OUTLET_FEEDBACK_GAIN="${OUTLET_FEEDBACK_GAIN:-0.0}"
if [[ "$OUTLET_MODE" != "hybrid" ]]; then
  echo "[gas-jet-bath] ERROR first top-same-face qualification requires OUTLET_MODE=hybrid; got $OUTLET_MODE" >&2
  exit 2
fi
INLET_RESERVOIR_CELLS="${INLET_RESERVOIR_CELLS:-2}"
# The CUDA resident segmented 0264 path requires inletThermalNoise==0.
# Gas temperature is maintained by the species thermostat after injection.
INLET_THERMAL_NOISE="${INLET_THERMAL_NOISE:-0.0}"
if ! awk -v x="$INLET_THERMAL_NOISE" 'BEGIN{exit !(x==0)}'; then
  echo "[gas-jet-bath] ERROR resident segmented inlet requires INLET_THERMAL_NOISE=0" >&2
  exit 2
fi
# Four solid faces are structurally required by the resident segmented collision
# subset.  Zero accommodation makes their collision coupling slip/specular-like,
# avoiding an arbitrary single virtual-particle mass for a two-species box.
WALL_ACCOMMODATION="${WALL_ACCOMMODATION:-0.0}"
if ! awk -v x="$WALL_ACCOMMODATION" 'BEGIN{exit !(x==0)}'; then
  echo "[gas-jet-bath] ERROR first gas/liquid jet qualification fixes WALL_ACCOMMODATION=0" >&2
  exit 2
fi

# Q6-g-f projected liquid: standard signed density restoration profile.
PROJECTION_BACKEND="${PROJECTION_BACKEND:-cuda}"
PROJECTION_MAX_ITERATIONS="${PROJECTION_MAX_ITERATIONS:-1600}"
PROJECTION_TOLERANCE="${PROJECTION_TOLERANCE:-1.0e-5}"
Q6_PROJECTION_STRENGTH="${Q6_PROJECTION_STRENGTH:-1.0}"
Q6_STRICT="${Q6_STRICT:-1}"
Q6_GF_DENSITY_RELAXATION_TIME="${Q6_GF_DENSITY_RELAXATION_TIME:-0.25}"
Q6_GF_DENSITY_COMPRESSION_GATE_ENABLE="${Q6_GF_DENSITY_COMPRESSION_GATE_ENABLE:-1}"
Q6_GF_DENSITY_COMPRESSION_THRESHOLD_PARTICLES="${Q6_GF_DENSITY_COMPRESSION_THRESHOLD_PARTICLES:-3.0}"
Q6_GF_DENSITY_TRACTION_THRESHOLD_PARTICLES="${Q6_GF_DENSITY_TRACTION_THRESHOLD_PARTICLES:-6.0}"
Q6_GF_DENSITY_TRACTION_GAIN="${Q6_GF_DENSITY_TRACTION_GAIN:-1.0}"
Q6_GF_MIN_FILL_FRACTION="$SPECIES_Q6_MIN_FILL_FRACTION"
Q6_GF_EXTERNAL_SPECIES=1
Q6_GF_HAS_GAS_PHASE=1

SPECIES_RESAMPLING_ENABLE=false
LIQUID_RESAMPLING_ENABLE=false
GAS_RESAMPLING_ENABLE=false
WEIGHTED_RESAMPLING_ENABLE_OVERRIDE=false
CUDA_EMPTY_REFILL_ENABLE_OVERRIDE=false
VIRIAL_DENSITY_KICK_ENABLE=false

SUMMARY_EVERY="${SUMMARY_EVERY:-25}"
DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-1000}"  # restart/analysis anchors; compact archive excludes .smpcd files
INACTIVE_SLOTS_CELL_FRACTION="${INACTIVE_SLOTS_CELL_FRACTION:-1.0}"
CAMPAIGN_ROOT="${CAMPAIGN_ROOT:-runs/0493x14an_planar_gas_jet_liquid_bath_seed${SEED}}"
CLEAN_RUN_ROOT="${CLEAN_RUN_ROOT:-1}"
PREFLIGHT_ONLY="${PREFLIGHT_ONLY:-0}"
BIN="${BIN:-${SRC_MPCD_DEFAULT_BIN_0434:-build/src_mpcd_base_cuda_q6_resident_livevis_0486}}"
THREADS="${THREADS:-8}"

LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-1}"
LIVE_VIS_CONTROL_FILE="$ROOT/livevis_control.kv"
LIVE_VIS_FIELD="${LIVE_VIS_FIELD:-mass}"
LIVE_VIS_EVERY="${LIVE_VIS_EVERY:-25}"
LIVE_VIS_NX="${LIVE_VIS_NX:-256}"; LIVE_VIS_NY="${LIVE_VIS_NY:-128}"
LIVE_VIS_COLORMAP="${LIVE_VIS_COLORMAP:-hot}"; LIVE_VIS_CLIP="${LIVE_VIS_CLIP:--1}"; LIVE_VIS_GAIN="${LIVE_VIS_GAIN:-1.0}"
LIVE_VIS_SMOOTH_PASSES="${LIVE_VIS_SMOOTH_PASSES:-1}"; LIVE_VIS_WINDOW_SCALE="${LIVE_VIS_WINDOW_SCALE:-1}"; LIVE_VIS_HOLD_ON_EXIT="${LIVE_VIS_HOLD_ON_EXIT:-1}"
PARTICLE_TYPE_FILTER="${PARTICLE_TYPE_FILTER:--1}"
FILTERED_RECORDING_ENABLE="${FILTERED_RECORDING_ENABLE:-0}"

GEN_CASE=tg; U0=0.0; VELOCITY_MODE=zero; BACKGROUND_TYPE="$GAS_TYPE"; INACTIVE_TYPE="$GAS_TYPE"; TG_HOLE_ENABLE=false
RUN_OK_GENERATOR_PATH="$GENERATOR"
export RUN_OK_REFERENCE_PARTICLE_MASS RUN_OK_GENERATOR_PATH
suite_defaults_common_0434
suite_compute_derived_0434

# ---- Derived physical controls and rejection of obviously unresolved cases ---
read -r H CELL_AREA JET_WIDTH JET_SMIN JET_SMAX GAS_P_REF GAS_RHO LIQUID_RHO CTH CJET CCOMB HBAR BARO_RATIO WE_G BO_W FR_W INLET_OCC <<<"$(python3 - \
  "$Lx" "$Ly" "$NX" "$NY" "$GAMMA" "$JET_CENTER_X" "$JET_WIDTH_CELLS" "$JET_SPEED" "$DT" \
  "$GAS_MASS" "$GAS_KBT" "$LIQUID_MASS" "$SURFACE_TENSION_SIGMA" "$GRAVITY_Y" "$BATH_HEIGHT" <<'PY'
import math,sys
lx,ly=float(sys.argv[1]),float(sys.argv[2]); nx,ny=int(sys.argv[3]),int(sys.argv[4]); gam=float(sys.argv[5])
xc=float(sys.argv[6]); wc=float(sys.argv[7]); uj=float(sys.argv[8]); dt=float(sys.argv[9]); mg=float(sys.argv[10]); kg=float(sys.argv[11]); ml=float(sys.argv[12]); sig=float(sys.argv[13]); gy=float(sys.argv[14]); bh=float(sys.argv[15])
hx=lx/nx; hy=ly/ny
if abs(hx-hy)>1e-12*max(1,abs(hx),abs(hy)): raise SystemExit('[gas-jet-bath] square cells required')
if abs(hx-1/256)>1e-12: raise SystemExit(f'[gas-jet-bath] first qualification keeps h=1/256, got {hx:.17g}')
if abs(bh/hy-round(bh/hy))>1e-10: raise SystemExit('[gas-jet-bath] BATH_HEIGHT must lie on a cell boundary')
W=wc*hx; smin=(xc-.5*W)/lx; smax=(xc+.5*W)/lx
if not (0.02<smin<smax<0.98): raise SystemExit('[gas-jet-bath] jet segment too close to top corners')
A=hx*hy; pref=gam*kg/A; rhoG=gam*mg/A; rhoL=gam*ml/A
cth=math.sqrt(kg/mg)*dt/hx; cjet=abs(uj)*dt/hx; ccomb=cth+cjet
if ccomb>0.80: raise SystemExit(f'[gas-jet-bath] unresolved gas flight: Cthermal+Cjet={ccomb:.6g} > 0.80 cell/step')
gabs=abs(gy)
if gy>1e-15: raise SystemExit('[gas-jet-bath] default geometry expects GRAVITY_Y <= 0')
if gabs>0:
    H=kg/(mg*gabs); gh=ly-bh; ratio=math.exp(-gh/H)
    mf=(H/gh)*(1-math.exp(-gh/H)); n0=gam/mf; ntop=n0*math.exp(-(gh-.5*hy)/H)
else:
    H=float('inf'); ratio=1.0; ntop=gam
We=rhoG*uj*uj*W/sig
Bo=rhoL*gabs*W*W/sig if sig>0 else float('inf')
Fr=abs(uj)/math.sqrt(gabs*W) if gabs>0 else float('inf')
print(hx,A,W,smin,smax,pref,rhoG,rhoL,cth,cjet,ccomb,H,ratio,We,Bo,Fr,max(2,int(round(ntop))))
PY
)"

LEFT_OUTLET_SMIN="${LEFT_OUTLET_SMIN:-0.01}"
LEFT_OUTLET_SMAX="${LEFT_OUTLET_SMAX:-$JET_SMIN}"
RIGHT_OUTLET_SMIN="${RIGHT_OUTLET_SMIN:-$JET_SMAX}"
RIGHT_OUTLET_SMAX="${RIGHT_OUTLET_SMAX:-0.99}"

if suite_truthy_0434 "$CLEAN_RUN_ROOT"; then rm -rf "$CAMPAIGN_ROOT"; fi
suite_prepare_dirs_0434 "$CAMPAIGN_ROOT"
STATE="$CAMPAIGN_ROOT/init/${CASE_LABEL}.smpcd"
OUT="$CAMPAIGN_ROOT/output"
PARAMS="$CAMPAIGN_ROOT/params/${CASE_LABEL}.kv"
LOG="$CAMPAIGN_ROOT/logs/${CASE_LABEL}.log"
TF="$CAMPAIGN_ROOT/logs/${CASE_LABEL}.time"
ANALYSIS_DIR="$CAMPAIGN_ROOT/analysis"
mkdir -p "$OUT" "$ANALYSIS_DIR"

python3 "$GENERATOR" \
  --output "$STATE" --Lx "$Lx" --Ly "$Ly" --nx "$NX" --ny "$NY" --gamma "$GAMMA" \
  --bath-height "$BATH_HEIGHT" --gravity-y "$GRAVITY_Y" \
  --liquid-type "$LIQUID_TYPE" --gas-type "$GAS_TYPE" \
  --liquid-mass "$LIQUID_MASS" --gas-mass "$GAS_MASS" \
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
openBoundarySegmentsEnable = true
openBoundarySegmentCount = 3
openBoundarySegment0 = top inlet $JET_SMIN $JET_SMAX 0.0 -$JET_SPEED $GAS_TYPE $GAS_MASS
openBoundarySegment1 = top outlet $LEFT_OUTLET_SMIN $LEFT_OUTLET_SMAX 0.0 0.0 0 $GAS_MASS
openBoundarySegment2 = top outlet $RIGHT_OUTLET_SMIN $RIGHT_OUTLET_SMAX 0.0 0.0 0 $GAS_MASS
inletVelocityRampEnable = true
inletVelocityRampStartTime = $JET_RAMP_START_TIME
inletVelocityRampEndTime = $JET_RAMP_END_TIME
inletVelocityRampInitialFactor = $JET_RAMP_INITIAL_FACTOR
inletVelocityRampFinalFactor = $JET_RAMP_FINAL_FACTOR
inletVelocityRampProfile = smoothstep
inletVelocitySpatialProfile = uniform
inletKBT = $GAS_KBT
inletThermalNoise = $INLET_THERMAL_NOISE
inletInjectionMode = hard_cell_density
inletReservoirMode = hard_cell_density
inletReservoirCells = $INLET_RESERVOIR_CELLS
inletTargetOccupancy = $INLET_OCC
inletHardCellVelocityMean = true
inletHardCellThermalRescale = true
inletRandomizeTangential = true
inletReinjectBackflow = true
openBoundaryOutletMode = $OUTLET_MODE
openBoundaryOutletHybridBlend = 0.0
openBoundaryOutletFeedbackGain = $OUTLET_FEEDBACK_GAIN
bodyAccelerationX = 0.0
bodyAccelerationY = $GRAVITY_Y
taylorGreenForcingEnable = false
wallVpEnable = false
wallAccommodation = $WALL_ACCOMMODATION
wallVpGamma = $GAMMA
wallVpMass = $LIQUID_MASS
wallKBT = -1.0
wallThermalNoise = 0.0
speciesRegistryEnable = true
speciesCount = 2
species0 = $LIQUID_TYPE incompressible_liquid liquid $LIQUID_Q6_STRENGTH 1.0 $LREF
species0ResamplingEnable = false
species0ThermostatTargetKBT = $LIQUID_KBT
species1 = $GAS_TYPE compressible_gas gas $GAS_Q6_STRENGTH 0.0 $GREF
species1ResamplingEnable = false
species1ThermostatTargetKBT = $GAS_KBT
speciesRequireRegisteredTypes = true
speciesThermostatEnable = true
speciesDiagnosticsEnable = true
speciesDiagnosticsFilename = species_runtime_0493x14an.csv
speciesCellDiagnosticsEnable = false
speciesQ6Sensitivity = 1.0
speciesQ6FallbackMode = common
speciesQ6ComparisonTolerance = 1.0e-11
PARAMS
suite_write_common_params_0434 "$RUN_MODE" >> "$PARAMS"
run_ok_surface_append_params_0493x13zi "$PARAMS" "$PHASE_INTERFACE_A_SELECTOR" "$PHASE_INTERFACE_B_SELECTOR"
cat >> "$PARAMS" <<'PARAMS'
phaseInterfaceKineticBilateralRelocation = true
PARAMS

suite_export_cuda_flags_0434 "$RUN_MODE" "$TOPOLOGY"
# Current Q6-g-f cooperative resident CG.
export MPCD_Q6_G_F_RESIDENT_CG_0493X7J=1
export MPCD_CUDA_Q6_RESIDENT_SINGLE_BLOCK_CG_0407=0

# Start from all optional surface-kinetic branches OFF, then enable exactly the
# integrated liquid/gas coupling under test.
run_ok_surface_export_off_flags_0493x13zi
export MPCD_Q6_PHASE_GAS_PRESSURE_0493X6G=1
export MPCD_Q6_PHASE_GAS_PRESSURE_MODE_0493X6G=eos_accessible_volume
export MPCD_Q6_PHASE_GAS_PRESSURE_CONSTANT_0493X6G=0
export MPCD_Q6_PHASE_GAS_PRESSURE_REFERENCE_0493X6G="$GAS_P_REF"
export MPCD_Q6_PHASE_GAS_PRESSURE_SCALE_0493X6G=1

# Liquid-side kinetic support/relocalization closure.
export MPCD_X10O_Q6_THERMAL_INTERFACE_WALL=1
export MPCD_X10O_THERMAL_PARTICLE_MASS="$LIQUID_MASS"
export MPCD_X10O_THERMAL_SIGMAS="$X10O_THERMAL_SIGMAS"
export MPCD_X10O_THERMAL_MAX_CELLS="$X10O_THERMAL_MAX_CELLS"
export MPCD_X10_KINETIC_INTERFACE_CIC=1
export MPCD_X10_KINETIC_INTERFACE_QUADRATIC=1
export MPCD_X10P_INITIAL_OVERLAP_RESOLUTION=1
export MPCD_X10_KINETIC_INTERFACE_ONE_FOR_ONE=1
export MPCD_X10_KINETIC_INTERFACE_ONE_FOR_ONE_SWAP=1
export MPCD_X10_KINETIC_INTERFACE_ONE_FOR_ONE_NORMAL_ONLY=0
export MPCD_X10_KINETIC_INTERFACE_THERMAL_PHASE_LIMITER=0
export MPCD_X12A_LOCAL_THERMAL_COOLING=1
export MPCD_X12A_LOCAL_THERMAL_RADIUS_CELLS="$X12A_LOCAL_THERMAL_RADIUS_CELLS"

# Gas-liquid interaction closure.
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
# Global Q6-resultant closure deliberately OFF: wall/open-boundary-connected bath.
export MPCD_X14V_DEVICE_APPLIED_Q6_RESULTANT_CLOSURE=0

export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_WORKSPACE_DOWNLOAD_0272=1

suite_prepare_livevis_control_0434 "$CAMPAIGN_ROOT" "$RUN_MODE"
suite_export_livevis_0434
suite_write_env_file_0434 "$CAMPAIGN_ROOT/logs/environment_${CASE_LABEL}.env" "$RUN_MODE"
cat >> "$CAMPAIGN_ROOT/logs/environment_${CASE_LABEL}.env" <<META
BENCHMARK=planar_gas_jet_normal_to_liquid_bath_2d
GAS_THERMAL_FLIGHT_CELLS=$CTH
GAS_DIRECTED_JET_FLIGHT_CELLS=$CJET
GAS_THERMAL_PLUS_DIRECTED_FLIGHT_CELLS=$CCOMB
GAS_BAROMETRIC_SCALE_HEIGHT=$HBAR
GAS_TOP_TO_BATH_DENSITY_RATIO=$BARO_RATIO
GAS_INLET_TARGET_OCCUPANCY=$INLET_OCC
JET_WIDTH=$JET_WIDTH
JET_SPEED=$JET_SPEED
GAS_WEBER_JET_WIDTH=$WE_G
LIQUID_BOND_JET_WIDTH=$BO_W
JET_FROUDE_JET_WIDTH=$FR_W
MPCD_X14L_GAS_SPECULAR_REFLECTION=1
MPCD_X14V_GAS_KINETIC_EXCESS_KICK=1
MPCD_X14V_X6G_LOCAL_FACE_GAUGE_PROJECTION=1
MPCD_X14V_DEVICE_APPLIED_Q6_RESULTANT_CLOSURE=0
META

run_ok_surface_print_0493x13zi "gas pressure + Laplace tension + liquid kinetic support + gas specular reflection + gas excess normal impulse + local gas traction"
echo "===== PLANAR GAS JET -> LIQUID BATH, 2-D ====="
echo "PATHS: runner=$ROOT/scripts/run_0493x14an_planar_gas_jet_liquid_bath.sh"
echo "       generator=$GENERATOR analyzer=$ANALYZER binary=$BIN"
echo "       state=$STATE params=$PARAMS output=$OUT"
echo "DOMAIN: L=${Lx}x${Ly} grid=${NX}x${NY} h=$H bathHeight=$BATH_HEIGHT gravityY=$GRAVITY_Y"
echo "PHASE: liquid(type=$LIQUID_TYPE,m=$LIQUID_MASS,kBT=$LIQUID_KBT,rhoNom=$LIQUID_RHO)"
echo "       gas(type=$GAS_TYPE,m=$GAS_MASS,kBT=$GAS_KBT,rhoNom=$GAS_RHO) baroH=$HBAR nTop/nBath=$BARO_RATIO"
echo "JET:   top, centerX=$JET_CENTER_X widthCells=$JET_WIDTH_CELLS width=$JET_WIDTH U=$JET_SPEED inletN=$INLET_OCC"
echo "       ramp t=[$JET_RAMP_START_TIME,$JET_RAMP_END_TIME] factor=[$JET_RAMP_INITIAL_FACTOR,$JET_RAMP_FINAL_FACTOR]"
echo "RESOLUTION: gas thermal flight=$CTH h/step; directed jet flight=$CJET h/step; sum=$CCOMB h/step"
echo "DIMENSIONLESS: We_g(W)=$WE_G  Bo_l(W)=$BO_W  Fr(W)=$FR_W"
echo "BOUNDARIES: four solid geometric faces; top central gas inlet + two top side outlets(mode=$OUTLET_MODE)"
echo "WALL COLLISION: accommodation=$WALL_ACCOMMODATION (0 = slip/specular-like; no virtual-wall momentum coupling)"
echo "INLET: thermalNoise=$INLET_THERMAL_NOISE; species thermostat restores gas target kBT=$GAS_KBT"
echo "COUPLING: thermodynamic gas pressure + surface tension + gas specular reflection + gas excess normal impulse + local traction projection"
echo "GLOBAL RESULTANT CLOSURE: OFF (required: bath is wall/open-boundary connected)"
echo "RUN: steps=$STEPS dt=$DT tEnd=$(awk -v n="$STEPS" -v d="$DT" 'BEGIN{printf "%.9g",n*d}') summaryEvery=$SUMMARY_EVERY dumpEvery=$DUMP_STATE_EVERY"
echo "NOTE: ./livevis_control.kv is user-owned/read-only and is not modified"
echo "================================================"

suite_run_binary_0434 "$PARAMS" "$LOG" "$TF" "$OUT"
if suite_truthy_0434 "$PREFLIGHT_ONLY"; then
  echo '[gas-jet-bath] PREFLIGHT_ONLY complete'
  exit 0
fi

python3 "$ANALYZER" \
  --run-root "$CAMPAIGN_ROOT" --nx "$NX" --ny "$NY" --Lx "$Lx" --Ly "$Ly" \
  --gamma "$GAMMA" --liquid-type "$LIQUID_TYPE" --liquid-mass "$LIQUID_MASS" \
  --jet-center-x "$JET_CENTER_X" --jet-width "$JET_WIDTH" --dt "$DT"

OUT_TAR="$CAMPAIGN_ROOT/0493x14an_planar_gas_jet_liquid_bath_compact.tar.gz"
FILES=(
  analysis
  "output/species_runtime_0493x14an.csv"
  "output/cuda_phase_interface_pressure_0493x6g.csv"
  "output/cuda_phase_interface_stencil_0493x6f.csv"
  "output/cuda_species_q6_independent_masked_0493w5.csv"
  "logs/${CASE_LABEL}.log"
  "logs/${CASE_LABEL}.time"
  "logs/environment_${CASE_LABEL}.env"
  "params/${CASE_LABEL}.kv"
  "init/${CASE_LABEL}.smpcd.json"
)
PRESENT=(); for f in "${FILES[@]}"; do [[ -e "$CAMPAIGN_ROOT/$f" ]] && PRESENT+=("$f"); done
tar -czf "$OUT_TAR" -C "$CAMPAIGN_ROOT" "${PRESENT[@]}"
echo "[gas-jet-bath] COMPLETE"
echo "[gas-jet-bath] compact=$OUT_TAR"
