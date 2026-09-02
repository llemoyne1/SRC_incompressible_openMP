#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$ROOT/scripts/src_mpcd_run_ok_common.sh"
suite_root_cd_0434

for required in \
  "$ROOT/scripts/generate_0493x14j_drop_two_temperature.py" \
  "$ROOT/scripts/analyze_0493x14j_drop_radial.py" \
  "$ROOT/scripts/analyze_0493x6g_phase_gas_pressure.py"; do
  if [[ ! -f "$required" ]]; then
    echo "[0493x14s] ERROR missing prerequisite $required" >&2
    exit 2
  fi
done

# =============================================================================
# 0493x14s — x6g accessible-volume EOS + qualified liquid chain + gas specular
#
# Purpose:
#   Test ONLY the x6g pressure-provider correction established offline in x14r.
#   The complete x14m liquid and gas kinetic chain is retained unchanged:
#   liquid=x10o+CIC+Q2+x10p/q+x10u+x10v(full-vector)+x12a;
#   gas=x14l local-moving-frame specular reflection, no impulse feedback.
#   x6g uses the already-resident filtered Q6 alpha on the gas-side trace cell.
#   No extra O(Ncells) pass, particle pass or resident buffer is introduced.
#
# ./livevis_control.kv is only read and is never modified.
# =============================================================================

# -----------------------------------------------------------------------------
# USER EDIT ZONE — physical/numerical parameters are intentionally visible here.
# -----------------------------------------------------------------------------
CASE_LABEL="${CASE_LABEL:-0493x14s_x6g_accessible_volume_drop}"
TOPOLOGY="closed_box"
RUN_MODE="src-q6-g-f"

Lx="${Lx:-1.5625}"
Ly="${Ly:-1.5625}"
NX="${NX:-400}"
NY="${NY:-400}"
GAMMA="${GAMMA:-20}"
DT="${DT:-0.002}"
STEPS="${STEPS:-1000}"
SEED="${SEED:-493150}"

R_CELLS="${R_CELLS:-40}"
CENTER_X="${CENTER_X:-0.78125}"
CENTER_Y="${CENTER_Y:-0.78125}"

LIQUID_TYPE="${LIQUID_TYPE:-1}"
GAS_TYPE="${GAS_TYPE:-2}"
LIQUID_MASS="${LIQUID_MASS:-1.0}"
GAS_MASS="${GAS_MASS:-0.1}"
LIQUID_KBT="${LIQUID_KBT:-0.02}"
GAS_KBT="${GAS_KBT:-0.08}"

# x6g currently consumes the global kBT in its gas EOS. Keep it equal to the
# gas thermostat target until x6g is explicitly generalized to species kBT.
KBT="${KBT:-$GAS_KBT}"
THERMOSTAT_TARGET_KBT="${THERMOSTAT_TARGET_KBT:-$GAS_KBT}"
THERMOSTAT_ENABLE="${THERMOSTAT_ENABLE:-true}"
THERMOSTAT_MODE="${THERMOSTAT_MODE:-cell_relative_rescale}"
THERMOSTAT_EVERY="${THERMOSTAT_EVERY:-1}"
THERMOSTAT_MIN_PARTICLES="${THERMOSTAT_MIN_PARTICLES:-3}"

ROTATION_ANGLE="${ROTATION_ANGLE:-1.5707963267948966}"
RANDOM_ROTATION_SIGN="${RANDOM_ROTATION_SIGN:-true}"
GRID_SHIFT_ENABLE="${GRID_SHIFT_ENABLE:-true}"

SURFACE_TENSION_SIGMA="${SURFACE_TENSION_SIGMA:-2560.0}"
SURFACE_TENSION_MIN_RADIUS_CELLS="${SURFACE_TENSION_MIN_RADIUS_CELLS:-4}"
PHASE_INTERFACE_KINETIC_REFLECTION_FRACTION="${PHASE_INTERFACE_KINETIC_REFLECTION_FRACTION:-1.0}"
PHASE_INTERFACE_EVAPORATION_TARGET_TYPE="${PHASE_INTERFACE_EVAPORATION_TARGET_TYPE:--1}"
PHASE_INTERFACE_CONTACT_ANGLE_DEG="${PHASE_INTERFACE_CONTACT_ANGLE_DEG:--1}"
X12A_LOCAL_THERMAL_RADIUS_CELLS="${X12A_LOCAL_THERMAL_RADIUS_CELLS:-25.298221281347036}"
PHASE_INTERFACE_A_SELECTOR="type:${LIQUID_TYPE}"
PHASE_INTERFACE_B_SELECTOR="type:${GAS_TYPE}"

LIQUID_Q6_STRENGTH="${LIQUID_Q6_STRENGTH:-1.0}"
GAS_Q6_STRENGTH="${GAS_Q6_STRENGTH:-0.0}"
SPECIES_Q6_MIN_FILL_FRACTION="${SPECIES_Q6_MIN_FILL_FRACTION:-0.10}"
Q6_GF_DENSITY_RELAXATION_TIME="${Q6_GF_DENSITY_RELAXATION_TIME:-0.25}"
Q6_GF_DENSITY_COMPRESSION_GATE_ENABLE="${Q6_GF_DENSITY_COMPRESSION_GATE_ENABLE:-1}"
Q6_GF_DENSITY_COMPRESSION_THRESHOLD_PARTICLES="${Q6_GF_DENSITY_COMPRESSION_THRESHOLD_PARTICLES:-3.0}"
Q6_GF_DENSITY_TRACTION_THRESHOLD_PARTICLES="${Q6_GF_DENSITY_TRACTION_THRESHOLD_PARTICLES:-6.0}"
Q6_GF_DENSITY_TRACTION_GAIN="${Q6_GF_DENSITY_TRACTION_GAIN:-1.0}"

PROJECTION_BACKEND="${PROJECTION_BACKEND:-cuda}"
PROJECTION_MAX_ITERATIONS="${PROJECTION_MAX_ITERATIONS:-800}"
PROJECTION_TOLERANCE="${PROJECTION_TOLERANCE:-1.0e-5}"
Q6_PROJECTION_STRENGTH="${Q6_PROJECTION_STRENGTH:-1.0}"
Q6_STRICT="${Q6_STRICT:-1}"

SUMMARY_EVERY="${SUMMARY_EVERY:-100}"
DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-100}"
LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
PREFLIGHT_ONLY="${PREFLIGHT_ONLY:-0}"
CLEAN_RUN_ROOT="${CLEAN_RUN_ROOT:-1}"

# LiveVis control remains user-owned. These are fallbacks only; the effective
# values are read from ./livevis_control.kv and printed by run_ok-common.
LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-1}"
LIVE_VIS_CONTROL_FILE="$ROOT/livevis_control.kv"
LIVE_VIS_FIELD="${LIVE_VIS_FIELD:-density}"
LIVE_VIS_EVERY="${LIVE_VIS_EVERY:-100}"
LIVE_VIS_NX="${LIVE_VIS_NX:-200}"
LIVE_VIS_NY="${LIVE_VIS_NY:-200}"
LIVE_VIS_COLORMAP="${LIVE_VIS_COLORMAP:-hot}"
LIVE_VIS_CLIP="${LIVE_VIS_CLIP:--1}"
LIVE_VIS_GAIN="${LIVE_VIS_GAIN:-1.0}"
LIVE_VIS_SMOOTH_PASSES="${LIVE_VIS_SMOOTH_PASSES:-1}"
LIVE_VIS_WINDOW_SCALE="${LIVE_VIS_WINDOW_SCALE:-1}"
LIVE_VIS_HOLD_ON_EXIT="${LIVE_VIS_HOLD_ON_EXIT:-1}"
RECORD_ENABLE="${RECORD_ENABLE:-true}"
RECORD_FIELDS="${RECORD_FIELDS:-mass}"
RECORD_EVERY="${RECORD_EVERY:-100}"
FILTER_MODE="${FILTER_MODE:-none}"
FILTER_SAMPLE_EVERY="${FILTER_SAMPLE_EVERY:-100}"
FILTERED_RECORDING_ENABLE="${FILTERED_RECORDING_ENABLE:-1}"
PARTICLE_TYPE_FILTER="${PARTICLE_TYPE_FILTER:--1}"

BIN="${BIN:-${SRC_MPCD_DEFAULT_BIN_0434:-build/src_mpcd_base_cuda_q6_resident_livevis_0486}}"
# -----------------------------------------------------------------------------

# Common run machinery inputs; no resampling/refill or virial density kick.
GEN_CASE="tg"
U0=0.0
VELOCITY_MODE="zero"
PARTICLE_MASS="$GAS_MASS"
BACKGROUND_TYPE="$GAS_TYPE"
INACTIVE_TYPE="$GAS_TYPE"
TG_HOLE_ENABLE=false
SPECIES_RESAMPLING_ENABLE=false
SPECIES_RESIDENT_MODE=off
RESAMPLING_HOST_PATCHBACK_ENABLE=0
MASS_RECONDITION_ENABLE=0
RESAMPLING_THERMAL_RENORMALIZATION_ENABLE=false
RESAMPLING_MASS_GUARD_ENABLE=false
VIRIAL_DENSITY_KICK_ENABLE=false
Q6_GF_EXTERNAL_SPECIES=1
Q6_GF_HAS_GAS_PHASE=1
Q6_GF_MIN_FILL_FRACTION="$SPECIES_Q6_MIN_FILL_FRACTION"
RUN_OK_REFERENCE_PARTICLE_MASS="$LIQUID_MASS"
RUN_OK_GENERATOR_PATH="$ROOT/scripts/generate_0493x14j_drop_two_temperature.py"
export RUN_OK_REFERENCE_PARTICLE_MASS RUN_OK_GENERATOR_PATH

suite_defaults_common_0434
suite_compute_derived_0434

read -r H RADIUS CELL_AREA GAS_THERMAL_PRESSURE LAPLACE_PRESSURE <<<"$(python3 - "$Lx" "$Ly" "$NX" "$NY" "$R_CELLS" "$GAMMA" "$GAS_KBT" "$SURFACE_TENSION_SIGMA" <<'PY'
import sys
lx,ly=float(sys.argv[1]),float(sys.argv[2]); nx,ny=int(sys.argv[3]),int(sys.argv[4])
rc,g,kbtg,sigma=float(sys.argv[5]),float(sys.argv[6]),float(sys.argv[7]),float(sys.argv[8])
hx,hy=lx/nx,ly/ny
if abs(hx-hy)>1e-12*max(1.0,abs(hx),abs(hy)):
    raise SystemExit('[0493x14s] square cells required')
r=rc*hx
area=hx*hy
pg=g*kbtg/area
lap=sigma/r
print(f'{hx:.17g} {r:.17g} {area:.17g} {pg:.17g} {lap:.17g}')
PY
)"

python3 - "$LIQUID_MASS" "$GAS_MASS" "$LIQUID_KBT" "$GAS_KBT" "$RADIUS" "$Lx" "$Ly" "$CENTER_X" "$CENTER_Y" <<'PY'
import math,sys
mL,mG,tL,tG,R,Lx,Ly,cx,cy=map(float,sys.argv[1:])
for n,v in [('mL',mL),('mG',mG),('R',R)]:
    if not (math.isfinite(v) and v>0): raise SystemExit(f'[0493x14s] {n} must be finite >0')
for n,v in [('kBT_L',tL),('kBT_G',tG)]:
    if not (math.isfinite(v) and v>=0): raise SystemExit(f'[0493x14s] {n} must be finite >=0')
if R >= min(cx,Lx-cx,cy,Ly-cy): raise SystemExit('[0493x14s] drop touches/overlaps a wall')
PY

BASE_RUN_ROOT="${BASE_RUN_ROOT:-runs/0493x14s_x6g_accessible_volume_drop_${NX}x${NY}_g${GAMMA}_rc${R_CELLS}_TL${LIQUID_KBT}_TG${GAS_KBT}_s${SURFACE_TENSION_SIGMA}}"
if suite_truthy_0434 "$CLEAN_RUN_ROOT"; then rm -rf "$BASE_RUN_ROOT"; fi
suite_prepare_dirs_0434 "$BASE_RUN_ROOT"
STATE="$BASE_RUN_ROOT/init/${CASE_LABEL}.smpcd"
OUT="$BASE_RUN_ROOT/output"
PARAMS="$BASE_RUN_ROOT/params/${CASE_LABEL}.kv"
LOG="$BASE_RUN_ROOT/logs/${CASE_LABEL}.log"
TIME_FILE="$BASE_RUN_ROOT/logs/${CASE_LABEL}.time"
ANALYSIS_DIR="$BASE_RUN_ROOT/analysis"
mkdir -p "$OUT" "$ANALYSIS_DIR"

python3 "$RUN_OK_GENERATOR_PATH" \
  --output "$STATE" --Lx "$Lx" --Ly "$Ly" --nx "$NX" --ny "$NY" \
  --gamma "$GAMMA" --center-x "$CENTER_X" --center-y "$CENTER_Y" --radius "$RADIUS" \
  --liquid-type "$LIQUID_TYPE" --gas-type "$GAS_TYPE" \
  --liquid-mass "$LIQUID_MASS" --gas-mass "$GAS_MASS" \
  --liquid-kBT "$LIQUID_KBT" --gas-kBT "$GAS_KBT" --seed "$SEED"

LIQUID_REFERENCE_CELL_MASS="$(awk -v g="$GAMMA" -v m="$LIQUID_MASS" 'BEGIN{printf "%.17g",g*m}')"
GAS_REFERENCE_CELL_MASS="$(awk -v g="$GAMMA" -v m="$GAS_MASS" 'BEGIN{printf "%.17g",g*m}')"

cat > "$PARAMS" <<PARAMS_EOF
inputState = $STATE
outputDir = $OUT
Lx = $Lx
Ly = $Ly
Nx = $NX
Ny = $NY
dt = $DT
nSteps = $STEPS
bcLeft = specular
bcRight = specular
bcBottom = specular
bcTop = specular
bcX = wall
bcY = wall
openBoundarySegmentsEnable = false
openBoundarySegmentCount = 0
bodyAccelerationX = 0.0
bodyAccelerationY = 0.0
wallVpEnable = false
wallAccommodation = 1.0
wallThermalNoise = 0.0
speciesRegistryEnable = true
speciesCount = 2
species0 = $LIQUID_TYPE incompressible_liquid liquid $LIQUID_Q6_STRENGTH 1.0 $LIQUID_REFERENCE_CELL_MASS
species0ResamplingEnable = false
species0ThermostatTargetKBT = $LIQUID_KBT
species1 = $GAS_TYPE compressible_gas gas $GAS_Q6_STRENGTH 0.0 $GAS_REFERENCE_CELL_MASS
species1ResamplingEnable = false
species1ThermostatTargetKBT = $GAS_KBT
speciesRequireRegisteredTypes = true
speciesThermostatEnable = true
speciesDiagnosticsEnable = true
speciesDiagnosticsFilename = species_runtime_0493x14s.csv
speciesCellDiagnosticsEnable = false
speciesQ6Sensitivity = 1.0
speciesQ6FallbackMode = common
speciesQ6ComparisonTolerance = 1.0e-11
PARAMS_EOF
suite_write_common_params_0434 "$RUN_MODE" >> "$PARAMS"
run_ok_surface_append_params_0493x13zi "$PARAMS" "$PHASE_INTERFACE_A_SELECTOR" "$PHASE_INTERFACE_B_SELECTOR"
cat >> "$PARAMS" <<'PARAMS_X14M'
phaseInterfaceKineticBilateralRelocation = true
PARAMS_X14M

# Production path and x14g resident cellId bridge remain enabled.
export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_WORKSPACE_DOWNLOAD_0272=1
suite_export_cuda_flags_0434 "$RUN_MODE" "$TOPOLOGY"
run_ok_surface_export_off_flags_0493x13zi
# 0493x14s: ONLY physics delta versus x14m.  Keep the complete liquid/gas
# closure identical and replace x6g raw cut-cell EOS by the Q6-alpha
# accessible-volume correction fitted offline in x14r.  The common helper
# exports the historical x6g mode; override it only after the helper/off-flags.
export MPCD_Q6_PHASE_GAS_PRESSURE_0493X6G=1
export MPCD_Q6_PHASE_GAS_PRESSURE_MODE_0493X6G=eos_accessible_volume
# 0493x14m: restore the complete qualified liquid closure unchanged.  The
# same existing x10o/Q2 particle pass handles A and B: A uses historical x10u;
# only A relocations are marked for historical equal-mass x10v full-vector
# swaps; B keeps x14l specular response.  x12a remains a phase-A closure.
export MPCD_X10O_Q6_THERMAL_INTERFACE_WALL=1
export MPCD_X10O_THERMAL_PARTICLE_MASS="$LIQUID_MASS"
export MPCD_X10O_THERMAL_SIGMAS="${X10O_THERMAL_SIGMAS:-3.0}"
export MPCD_X10O_THERMAL_MAX_CELLS="${X10O_THERMAL_MAX_CELLS:-0.75}"
export MPCD_X10_KINETIC_INTERFACE_CIC=1
export MPCD_X10_KINETIC_INTERFACE_QUADRATIC=1
export MPCD_X10P_INITIAL_OVERLAP_RESOLUTION=1
export MPCD_X10_KINETIC_INTERFACE_ONE_FOR_ONE=1
export MPCD_X14L_GAS_SPECULAR_REFLECTION=1
export MPCD_X10_KINETIC_INTERFACE_ONE_FOR_ONE_SWAP=1
export MPCD_X10_KINETIC_INTERFACE_ONE_FOR_ONE_NORMAL_ONLY=0
export MPCD_X10_KINETIC_INTERFACE_THERMAL_PHASE_LIMITER=0
export MPCD_X12A_LOCAL_THERMAL_COOLING=1
export MPCD_X12A_LOCAL_THERMAL_RADIUS_CELLS="$X12A_LOCAL_THERMAL_RADIUS_CELLS"

# x9 p3 is the active capillary field when sigma>0. Avoid duplicate passive
# curvature diagnostics; the production x9 audit CSV remains available.
export MPCD_Q6_PHASE_CURVATURE_DIAGNOSTICS_0493X9A=0
export MPCD_Q6_PHASE_CURVATURE_DIAGNOSTICS_0493X9B=0
export MPCD_Q6_PHASE_CURVATURE_DIAGNOSTICS_0493X9C=0

suite_prepare_livevis_control_0434 "$BASE_RUN_ROOT" "$RUN_MODE"
suite_export_livevis_0434
suite_write_env_file_0434 "$BASE_RUN_ROOT/logs/environment_0493x14s.env" "$RUN_MODE"
cat >> "$BASE_RUN_ROOT/logs/environment_0493x14s.env" <<META
CASE_LABEL=$CASE_LABEL
R_CELLS=$R_CELLS
RADIUS=$RADIUS
LIQUID_TYPE=$LIQUID_TYPE
GAS_TYPE=$GAS_TYPE
LIQUID_MASS=$LIQUID_MASS
GAS_MASS=$GAS_MASS
LIQUID_KBT=$LIQUID_KBT
GAS_KBT=$GAS_KBT
GLOBAL_KBT_X6G=$KBT
SURFACE_TENSION_SIGMA=$SURFACE_TENSION_SIGMA
GAS_THERMAL_PRESSURE=$GAS_THERMAL_PRESSURE
LAPLACE_PRESSURE=$LAPLACE_PRESSURE
PHASE_INTERFACE_KINETIC_BILATERAL_RELOCATION=true
MPCD_X14L_GAS_SPECULAR_REFLECTION=1
MPCD_X10_KINETIC_INTERFACE_ONE_FOR_ONE_SWAP=1
MPCD_X12A_LOCAL_THERMAL_COOLING=1
MPCD_X12A_LOCAL_THERMAL_RADIUS_CELLS=$MPCD_X12A_LOCAL_THERMAL_RADIUS_CELLS
MPCD_X10O_THERMAL_PARTICLE_MASS=$MPCD_X10O_THERMAL_PARTICLE_MASS
MPCD_X10O_THERMAL_SIGMAS=$MPCD_X10O_THERMAL_SIGMAS
MPCD_X10O_THERMAL_MAX_CELLS=$MPCD_X10O_THERMAL_MAX_CELLS
MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_WORKSPACE_DOWNLOAD_0272=$MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_WORKSPACE_DOWNLOAD_0272
MPCD_Q6_PHASE_GAS_PRESSURE_MODE_0493X6G=$MPCD_Q6_PHASE_GAS_PRESSURE_MODE_0493X6G
X14S_ACCESSIBLE_VOLUME_ALPHA=Q6_FILTERED_GAS_SIDE_CELL
X14S_ACCESSIBLE_VOLUME_G0=0.37396789550781245
X14S_ACCESSIBLE_VOLUME_G1=0.9153533203125
X14S_ACCESSIBLE_VOLUME_FLOOR=0.05
META

run_ok_surface_print_0493x13zi "x9+x6g-accessible-volume-Q6alpha-liquid-qualified-full-x10uv-x12a-gas-specular"
echo "===== 0493x14s X6G ACCESSIBLE-VOLUME + FULL LIQUID CHAIN + GAS SPECULAR ====="
echo "PATHS: runner=$ROOT/scripts/run_ok_0493x14s_x6g_accessible_volume_drop.sh"
echo "       generator=$RUN_OK_GENERATOR_PATH analyzer=$ROOT/scripts/analyze_0493x14j_drop_radial.py"
echo "       state=$STATE params=$PARAMS output=$OUT analysis=$ANALYSIS_DIR"
echo "DROP:  grid=${NX}x${NY} h=$H gamma=$GAMMA R/h=$R_CELLS R=$RADIUS center=($CENTER_X,$CENTER_Y)"
echo "PHASE: liquid(type=$LIQUID_TYPE,m=$LIQUID_MASS,kBT=$LIQUID_KBT,q6=$LIQUID_Q6_STRENGTH)"
echo "       gas(type=$GAS_TYPE,m=$GAS_MASS,kBT=$GAS_KBT,q6=$GAS_Q6_STRENGTH)"
echo "CAP:   sigma=$SURFACE_TENSION_SIGMA dP_Laplace=$LAPLACE_PRESSURE pGasRef=$GAS_THERMAL_PRESSURE"
echo "PATH:  src-q6-g-f + x6g + x9 ; common SRC collisions ; per-type thermostat ; gridShift=$GRID_SHIFT_ENABLE"
echo "X6G:  mode=$MPCD_Q6_PHASE_GAS_PRESSURE_MODE_0493X6G alpha=Q6 gas-side trace"
echo "       f=clamp(((1-alpha)-0.37396789550781245)/(0.9153533203125-0.37396789550781245),0.05,1)"
echo "       pGas=(Ng*kBT/Acell)/f ; no extra grid/particle pass or resident buffer"
echo "KIN-L: x10o+CIC+Q2+x10p/q+x10u+x10v full-vector+x12a ; LIQUID LAWS UNCHANGED"
echo "       x12a Rc/h=$X12A_LOCAL_THERMAL_RADIUS_CELLS; species thermostat factor applied to A/liquid only"
echo "KIN-G: B=specular normal reflection in moving-interface frame; tangential unchanged"
echo "       gas wall impulse diagnostic only / NOT applied; x10w=OFF; no orphan guard"
echo "RUN:   steps=$STEPS dt=$DT summaryEvery=$SUMMARY_EVERY dumpEvery=$DUMP_STATE_EVERY 0272=1 bilateralGeometry=true gasSpecular=true liquidX10v=true liquidX12a=true"
echo "NOTE:  ./livevis_control.kv is user-owned and not modified"
echo "================================="

suite_run_binary_0434 "$PARAMS" "$LOG" "$TIME_FILE" "$OUT"

if suite_truthy_0434 "$PREFLIGHT_ONLY"; then
  exit 0
fi

# Reuse existing x6f/x6g audits: no new runtime diagnostic or CUDA counter.
PRESSURE="$OUT/cuda_phase_interface_pressure_0493x6g.csv"
STENCIL="$OUT/cuda_phase_interface_stencil_0493x6f.csv"
if [[ -s "$PRESSURE" && -s "$STENCIL" ]]; then
  python3 "$ROOT/scripts/analyze_0493x6g_phase_gas_pressure.py" \
    --pressure "$PRESSURE" --stencil "$STENCIL" \
    --json "$ANALYSIS_DIR/phase_interface_gas_pressure_0493x14s.json"
else
  echo "[0493x14s] WARNING x6g/x6f audit inputs missing"
fi

CAP="$OUT/cuda_surface_tension_0493x9d.csv"
SPEC="$OUT/species_runtime_0493x14s.csv"
if [[ -s "$CAP" && -s "$SPEC" ]]; then
  python3 "$ROOT/scripts/analyze_0493x9d_static_drop.py" \
    --capillary "$CAP" --species "$SPEC" \
    --json "$ANALYSIS_DIR/laplace_static_drop_0493x14s.json" \
    --liquid-type "$LIQUID_TYPE" --sigma "$SURFACE_TENSION_SIGMA" \
    --radius "$RADIUS" --thermal-pressure "$GAS_THERMAL_PRESSURE" || true
else
  echo "[0493x14s] WARNING x9d Laplace audit inputs missing; radial analysis still runs"
fi

python3 "$ROOT/scripts/analyze_0493x14j_drop_radial.py" \
  --initial "$STATE" --output-dir "$OUT" --analysis-dir "$ANALYSIS_DIR" \
  --Lx "$Lx" --Ly "$Ly" --nx "$NX" --ny "$NY" --gamma "$GAMMA" --dt "$DT" \
  --center-x "$CENTER_X" --center-y "$CENTER_Y" --initial-radius "$RADIUS" \
  --liquid-type "$LIQUID_TYPE" --gas-type "$GAS_TYPE" --bin-cells 1.0

# Keep the existing x14j analyzer untouched, but publish x14s-named copies.
cp -f "$ANALYSIS_DIR/radial_metrics_0493x14j.csv" \
      "$ANALYSIS_DIR/radial_metrics_0493x14s.csv"
cp -f "$ANALYSIS_DIR/radial_profiles_0493x14j.csv" \
      "$ANALYSIS_DIR/radial_profiles_0493x14s.csv"

echo "[0493x14s] DONE"
echo "[0493x14s] return: $ANALYSIS_DIR/radial_metrics_0493x14s.csv"
echo "[0493x14s] return: $ANALYSIS_DIR/radial_profiles_0493x14s.csv"
echo "[0493x14s] return: $ANALYSIS_DIR/laplace_static_drop_0493x14s.json (if produced)"
