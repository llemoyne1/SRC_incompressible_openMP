#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$ROOT/scripts/src_mpcd_run_ok_common.sh"
suite_root_cd_0434

GENERATOR="$ROOT/scripts/generate_0493x14t_normal_pressure_piston.py"
ANALYZER="$ROOT/scripts/analyze_0493x14w_two_phase_couette.py"
SRC14V="$ROOT/src/cuda_q6_resident_0400.cu"
for f in "$GENERATOR" "$ANALYZER" "$SRC14V"; do
  [[ -f "$f" ]] || { echo "[0493x14w] ERROR missing $f" >&2; exit 2; }
done
grep -q '0493x14v-gas-kinetic-excess' "$SRC14V" || {
  echo "[0493x14w] ERROR x14v source marker not found; apply x14v first" >&2
  exit 2
}

# =============================================================================
# 0493x14w — TWO-PHASE PLANAR COUETTE / TANGENTIAL TRANSFER
#
# Reuses only already-existing physics:
#   * qualified resident wall family: x periodic, y physical solid walls;
#   * same generic thermal wall coupling as characterized Poiseuille, with
#     moving tangential virtual-particle velocity;
#   * x14s gas-pressure/free-surface chain;
#   * x14v normal kinetic excess kick;
#   * no new C++/CUDA, no new runtime diagnostic.
#
# Geometry: G | L | G, so BOTH physical walls contact gas.  This is deliberate:
# one global wallVpMass/kBT can therefore be physically consistent on both walls.
# Bottom wall -Uw, top wall +Uw.  The centered geometry gives an antisymmetric
# profile and removes common drift in the offline analysis.
# =============================================================================

CASE_LABEL="${CASE_LABEL:-0493x14w_two_phase_couette}"
RUN_MODE="src-q6-g-f"
TOPOLOGY="wall"

Lx="${Lx:-0.5}"; Ly="${Ly:-0.5}"; NX="${NX:-128}"; NY="${NY:-128}"
GAMMA="${GAMMA:-20}"; GAS_COUNT="${GAS_COUNT:-20}"; LIQUID_COUNT="${LIQUID_COUNT:-20}"
SLAB_WIDTH_CELLS="${SLAB_WIDTH_CELLS:-64}"; SLAB_CENTER_CELL="${SLAB_CENTER_CELL:-64}"

LIQUID_TYPE="${LIQUID_TYPE:-1}"; GAS_TYPE="${GAS_TYPE:-2}"
LIQUID_MASS="${LIQUID_MASS:-1.0}"; GAS_MASS="${GAS_MASS:-0.1}"
LIQUID_KBT="${LIQUID_KBT:-0.02}"; GAS_KBT="${GAS_KBT:-0.08}"
KBT="${KBT:-$GAS_KBT}"; THERMOSTAT_TARGET_KBT="${THERMOSTAT_TARGET_KBT:-$GAS_KBT}"

DT="${DT:-0.002}"
WALL_SPEED="${WALL_SPEED:-0.02}"
STEPS="${STEPS:-18000}"
SUMMARY_EVERY="${SUMMARY_EVERY:-1000}"
DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-3000}"
SEED="${SEED:-493170}"
INTERFACE_EXCLUDE_CELLS="${INTERFACE_EXCLUDE_CELLS:-4}"
WALL_EXCLUDE_CELLS="${WALL_EXCLUDE_CELLS:-4}"

ROTATION_ANGLE="${ROTATION_ANGLE:-1.5707963267948966}"
RANDOM_ROTATION_SIGN="${RANDOM_ROTATION_SIGN:-true}"
GRID_SHIFT_ENABLE="${GRID_SHIFT_ENABLE:-true}"
THERMOSTAT_ENABLE="${THERMOSTAT_ENABLE:-true}"
THERMOSTAT_MODE="${THERMOSTAT_MODE:-cell_relative_rescale}"
THERMOSTAT_EVERY="${THERMOSTAT_EVERY:-1}"
THERMOSTAT_MIN_PARTICLES="${THERMOSTAT_MIN_PARTICLES:-3}"

# Strong sigma is deliberate: a perfectly planar interface has kappa=0, so this
# does not create the tangential traction being tested, but suppresses accidental
# shear-driven corrugation while we isolate tangential transfer.
SURFACE_TENSION_SIGMA="${SURFACE_TENSION_SIGMA:-2560}"
SURFACE_TENSION_MIN_RADIUS_CELLS="${SURFACE_TENSION_MIN_RADIUS_CELLS:-4}"
PHASE_INTERFACE_KINETIC_REFLECTION_FRACTION="${PHASE_INTERFACE_KINETIC_REFLECTION_FRACTION:-1.0}"
PHASE_INTERFACE_EVAPORATION_TARGET_TYPE="${PHASE_INTERFACE_EVAPORATION_TARGET_TYPE:--1}"
PHASE_INTERFACE_CONTACT_ANGLE_DEG="${PHASE_INTERFACE_CONTACT_ANGLE_DEG:--1}"
X12A_LOCAL_THERMAL_RADIUS_CELLS="${X12A_LOCAL_THERMAL_RADIUS_CELLS:-25.298221281347036}"
PHASE_INTERFACE_A_SELECTOR="type:${LIQUID_TYPE}"; PHASE_INTERFACE_B_SELECTOR="type:${GAS_TYPE}"

LIQUID_Q6_STRENGTH="${LIQUID_Q6_STRENGTH:-1.0}"; GAS_Q6_STRENGTH="${GAS_Q6_STRENGTH:-0.0}"
SPECIES_Q6_MIN_FILL_FRACTION="${SPECIES_Q6_MIN_FILL_FRACTION:-0.10}"
Q6_GF_DENSITY_RELAXATION_TIME="${Q6_GF_DENSITY_RELAXATION_TIME:-0.25}"
Q6_GF_DENSITY_COMPRESSION_GATE_ENABLE="${Q6_GF_DENSITY_COMPRESSION_GATE_ENABLE:-1}"
Q6_GF_DENSITY_COMPRESSION_THRESHOLD_PARTICLES="${Q6_GF_DENSITY_COMPRESSION_THRESHOLD_PARTICLES:-3.0}"
Q6_GF_DENSITY_TRACTION_THRESHOLD_PARTICLES="${Q6_GF_DENSITY_TRACTION_THRESHOLD_PARTICLES:-6.0}"
Q6_GF_DENSITY_TRACTION_GAIN="${Q6_GF_DENSITY_TRACTION_GAIN:-1.0}"

PROJECTION_BACKEND="${PROJECTION_BACKEND:-cuda}"
PROJECTION_MAX_ITERATIONS="${PROJECTION_MAX_ITERATIONS:-800}"
PROJECTION_TOLERANCE="${PROJECTION_TOLERANCE:-1.0e-5}"
Q6_PROJECTION_STRENGTH="${Q6_PROJECTION_STRENGTH:-1.0}"; Q6_STRICT="${Q6_STRICT:-1}"

LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
PREFLIGHT_ONLY="${PREFLIGHT_ONLY:-0}"
CLEAN_RUN_ROOT="${CLEAN_RUN_ROOT:-1}"
LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-0}"
LIVE_VIS_CONTROL_FILE="$ROOT/livevis_control.kv"
LIVE_VIS_FIELD="${LIVE_VIS_FIELD:-ux}"
LIVE_VIS_EVERY="${LIVE_VIS_EVERY:-250}"
LIVE_VIS_NX="${LIVE_VIS_NX:-128}"; LIVE_VIS_NY="${LIVE_VIS_NY:-128}"
LIVE_VIS_COLORMAP="${LIVE_VIS_COLORMAP:-blue_red}"
LIVE_VIS_CLIP="${LIVE_VIS_CLIP:--1}"; LIVE_VIS_GAIN="${LIVE_VIS_GAIN:-1.0}"
LIVE_VIS_SMOOTH_PASSES="${LIVE_VIS_SMOOTH_PASSES:-1}"
LIVE_VIS_WINDOW_SCALE="${LIVE_VIS_WINDOW_SCALE:-1}"
LIVE_VIS_HOLD_ON_EXIT="${LIVE_VIS_HOLD_ON_EXIT:-0}"
# Recording is intentionally OFF: x14v timing showed that filtered recording,
# not the physics, dominates runtime when enabled at high resolution.
RECORD_ENABLE="${RECORD_ENABLE:-false}"
RECORD_FIELDS="${RECORD_FIELDS:-mass,ux,uy}"
RECORD_EVERY="${RECORD_EVERY:-1000}"
FILTER_MODE="${FILTER_MODE:-none}"
FILTER_SAMPLE_EVERY="${FILTER_SAMPLE_EVERY:-1000}"
FILTERED_RECORDING_ENABLE="${FILTERED_RECORDING_ENABLE:-0}"
PARTICLE_TYPE_FILTER="${PARTICLE_TYPE_FILTER:--1}"

BIN="${BIN:-${SRC_MPCD_DEFAULT_BIN_0434:-build/src_mpcd_base_cuda_q6_resident_livevis_0486}}"
CAMPAIGN_ROOT="${CAMPAIGN_ROOT:-runs/0493x14w_two_phase_couette}"

GEN_CASE="tg"; U0=0.0; VELOCITY_MODE="zero"; PARTICLE_MASS="$GAS_MASS"
BACKGROUND_TYPE="$GAS_TYPE"; INACTIVE_TYPE="$GAS_TYPE"; TG_HOLE_ENABLE=false
SPECIES_RESAMPLING_ENABLE=false; SPECIES_RESIDENT_MODE=off
RESAMPLING_HOST_PATCHBACK_ENABLE=0; MASS_RECONDITION_ENABLE=0
RESAMPLING_THERMAL_RENORMALIZATION_ENABLE=false; RESAMPLING_MASS_GUARD_ENABLE=false
VIRIAL_DENSITY_KICK_ENABLE=false
Q6_GF_EXTERNAL_SPECIES=1; Q6_GF_HAS_GAS_PHASE=1
Q6_GF_MIN_FILL_FRACTION="$SPECIES_Q6_MIN_FILL_FRACTION"
RUN_OK_REFERENCE_PARTICLE_MASS="$LIQUID_MASS"
RUN_OK_GENERATOR_PATH="$GENERATOR"
export RUN_OK_REFERENCE_PARTICLE_MASS RUN_OK_GENERATOR_PATH

suite_defaults_common_0434
suite_compute_derived_0434

read -r H CELL_AREA SLAB_START SLAB_END P_REF RHO_L GAS_WALL_H LIQ_HALF_H <<<"$(python3 - \
  "$Lx" "$Ly" "$NX" "$NY" "$SLAB_WIDTH_CELLS" "$SLAB_CENTER_CELL" \
  "$GAMMA" "$LIQUID_MASS" "$GAS_KBT" "$WALL_SPEED" <<'PY'
import sys,math
lx,ly=float(sys.argv[1]),float(sys.argv[2]); nx,ny=int(sys.argv[3]),int(sys.argv[4])
sw=int(sys.argv[5]); sc=float(sys.argv[6]); g=float(sys.argv[7]); ml=float(sys.argv[8])
tg=float(sys.argv[9]); uw=float(sys.argv[10])
hx=lx/nx; hy=ly/ny
if abs(hx-hy)>1e-12*max(1.0,abs(hx),abs(hy)):
    raise SystemExit("[0493x14w] square cells required")
if abs(hx-1/256)>1e-12:
    raise SystemExit(f"[0493x14w] h={hx:.17g}; benchmark keeps characterized h=1/256")
j0=sc-sw/2; j1=sc+sw/2
if abs(j0-round(j0))>1e-12 or abs(j1-round(j1))>1e-12:
    raise SystemExit("[0493x14w] slab interfaces must be native-cell aligned")
j0=int(round(j0)); j1=int(round(j1))
if not (0<j0<j1<ny) or j0 != ny-j1:
    raise SystemExit("[0493x14w] centered G|L|G geometry required")
if sw < 2*26:
    raise SystemExit("[0493x14w] liquid slab too thin for x12a Rc/h~25.3 to be inactive in its core")
if abs(uw) <= 0:
    raise SystemExit("[0493x14w] WALL_SPEED must be nonzero")
A=hx*hy
print(f"{hy:.17g} {A:.17g} {j0} {j1} {g*tg/A:.17g} {g*ml/A:.17g} {j0*hy:.17g} {0.5*sw*hy:.17g}")
PY
)"

if suite_truthy_0434 "$CLEAN_RUN_ROOT"; then rm -rf "$CAMPAIGN_ROOT"; fi
mkdir -p "$CAMPAIGN_ROOT"/{analysis,logs,init}

STATE="$CAMPAIGN_ROOT/init/${CASE_LABEL}.smpcd"
PARAMS="$CAMPAIGN_ROOT/params/${CASE_LABEL}.kv"
OUT="$CAMPAIGN_ROOT/output"
LOG="$CAMPAIGN_ROOT/logs/${CASE_LABEL}.log"
TF="$CAMPAIGN_ROOT/logs/${CASE_LABEL}.time"
mkdir -p "$CAMPAIGN_ROOT/params" "$OUT"

python3 "$GENERATOR" \
  --output "$STATE" --Lx "$Lx" --Ly "$Ly" --nx "$NX" --ny "$NY" \
  --liquid-count "$LIQUID_COUNT" --gas-bottom-count "$GAS_COUNT" --gas-top-count "$GAS_COUNT" \
  --slab-width-cells "$SLAB_WIDTH_CELLS" --slab-center-cell "$SLAB_CENTER_CELL" \
  --liquid-type "$LIQUID_TYPE" --gas-type "$GAS_TYPE" \
  --liquid-mass "$LIQUID_MASS" --gas-mass "$GAS_MASS" \
  --liquid-kBT "$LIQUID_KBT" --gas-kBT "$GAS_KBT" --seed "$SEED"

LREF="$(awk -v g="$GAMMA" -v m="$LIQUID_MASS" 'BEGIN{printf "%.17g",g*m}')"
GREF="$(awk -v g="$GAMMA" -v m="$GAS_MASS" 'BEGIN{printf "%.17g",g*m}')"

cat > "$PARAMS" <<PARAMS_EOF
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
bcBottom = solid
bcTop = solid
bcX = periodic
bcY = solid
openBoundarySegmentsEnable = false
openBoundarySegmentCount = 0
bodyAccelerationX = 0.0
bodyAccelerationY = 0.0
taylorGreenForcingEnable = false

# Same generic thermal-wall mechanism as the characterized solid-wall
# Poiseuille path. Both walls touch gas in this G|L|G geometry.
wallVpEnable = false
wallAccommodation = 1.0
wallVpGamma = $GAMMA
wallVpMass = $GAS_MASS
wallKBT = $GAS_KBT
wallThermalNoise = 0.0
wallUxBottom = -$WALL_SPEED
wallUyBottom = 0.0
wallUxTop = $WALL_SPEED
wallUyTop = 0.0

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
speciesDiagnosticsFilename = species_runtime_0493x14w.csv
speciesCellDiagnosticsEnable = false
speciesQ6Sensitivity = 1.0
speciesQ6FallbackMode = common
speciesQ6ComparisonTolerance = 1.0e-11
PARAMS_EOF

suite_write_common_params_0434 "$RUN_MODE" >> "$PARAMS"
run_ok_surface_append_params_0493x13zi "$PARAMS" "$PHASE_INTERFACE_A_SELECTOR" "$PHASE_INTERFACE_B_SELECTOR"
cat >> "$PARAMS" <<'PARAMS_EOF'
phaseInterfaceKineticBilateralRelocation = true
PARAMS_EOF

suite_export_cuda_flags_0434 "$RUN_MODE" "$TOPOLOGY"
run_ok_surface_export_off_flags_0493x13zi
export MPCD_Q6_PHASE_GAS_PRESSURE_0493X6G=1
export MPCD_Q6_PHASE_GAS_PRESSURE_MODE_0493X6G=eos_accessible_volume
export MPCD_Q6_PHASE_GAS_PRESSURE_REFERENCE_0493X6G="$P_REF"
export MPCD_Q6_PHASE_GAS_PRESSURE_SCALE_0493X6G=1

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
export MPCD_X14V_GAS_KINETIC_EXCESS_KICK=1

export MPCD_Q6_PHASE_CURVATURE_DIAGNOSTICS_0493X9A=0
export MPCD_Q6_PHASE_CURVATURE_DIAGNOSTICS_0493X9B=0
export MPCD_Q6_PHASE_CURVATURE_DIAGNOSTICS_0493X9C=0
export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_WORKSPACE_DOWNLOAD_0272=1

suite_prepare_livevis_control_0434 "$CAMPAIGN_ROOT" "$RUN_MODE"
suite_export_livevis_0434
suite_write_env_file_0434 "$CAMPAIGN_ROOT/logs/environment_0493x14w.env" "$RUN_MODE"
cat >> "$CAMPAIGN_ROOT/logs/environment_0493x14w.env" <<META
BENCHMARK=0493x14w_two_phase_couette
GEOMETRY=G_bottom|L|G_top
H=$H
SLAB_START_CELL=$SLAB_START
SLAB_END_CELL=$SLAB_END
GAS_WALL_LAYER_HEIGHT=$GAS_WALL_H
LIQUID_HALF_HEIGHT=$LIQ_HALF_H
WALL_UX_BOTTOM=-$WALL_SPEED
WALL_UX_TOP=$WALL_SPEED
WALL_COUPLING=solid+thermal_virtual_particles
WALL_VP_GAMMA=$GAMMA
WALL_VP_MASS=$GAS_MASS
WALL_KBT=$GAS_KBT
SURFACE_TENSION_SIGMA=$SURFACE_TENSION_SIGMA
MPCD_Q6_PHASE_GAS_PRESSURE_MODE_0493X6G=eos_accessible_volume
MPCD_X14L_GAS_SPECULAR_REFLECTION=1
MPCD_X14V_GAS_KINETIC_EXCESS_KICK=1
META

echo
echo "===== 0493x14w TWO-PHASE COUETTE ====="
echo "PATHS: runner=$ROOT/scripts/run_ok_0493x14w_two_phase_couette.sh"
echo "       generator=$GENERATOR analyzer=$ANALYZER"
echo "       state=$STATE params=$PARAMS output=$OUT"
echo "GEOM:  G|L|G, x periodic, y solid thermal walls; grid=${NX}x${NY}, h=$H"
echo "       gasWallLayer/h=$SLAB_START liquidSlab/h=$SLAB_WIDTH_CELLS interfaces=[$SLAB_START,$SLAB_END]"
echo "WALL:  UxBottom=-$WALL_SPEED UxTop=+$WALL_SPEED"
echo "       VP gamma=$GAMMA mass=$GAS_MASS kBT=$GAS_KBT accommodation=1 noise=0"
echo "PHASE: liquid(type=$LIQUID_TYPE,m=$LIQUID_MASS,kBT=$LIQUID_KBT,q6=$LIQUID_Q6_STRENGTH)"
echo "       gas(type=$GAS_TYPE,m=$GAS_MASS,kBT=$GAS_KBT,q6=$GAS_Q6_STRENGTH)"
echo "CHAIN: x6g accessible-volume + x14l gas specular + x14v kinetic-excess"
echo "       liquid x10o/CIC/Q2/x10p/q/x10u/x10v/x12a UNCHANGED"
echo "CAP:   sigma=$SURFACE_TENSION_SIGMA (planar kappa=0 target; stabilizes corrugation)"
echo "RUN:   steps=$STEPS dt=$DT summaryEvery=$SUMMARY_EVERY dumpEvery=$DUMP_STATE_EVERY"
echo "FIT:   exclude interface=${INTERFACE_EXCLUDE_CELLS}h wall=${WALL_EXCLUDE_CELLS}h"
echo "NOTE:  recording OFF by default; ./livevis_control.kv is user-owned/read-only"
echo "========================================"

suite_run_binary_0434 "$PARAMS" "$LOG" "$TF" "$OUT"
if suite_truthy_0434 "$PREFLIGHT_ONLY"; then
  echo "[0493x14w] PREFLIGHT_ONLY complete"
  exit 0
fi

python3 "$ANALYZER" \
  --initial "$STATE" --output-dir "$OUT" --analysis-dir "$CAMPAIGN_ROOT/analysis" \
  --Lx "$Lx" --Ly "$Ly" --nx "$NX" --ny "$NY" --dt "$DT" \
  --slab-start-cell "$SLAB_START" --slab-end-cell "$SLAB_END" \
  --liquid-type "$LIQUID_TYPE" --gas-type "$GAS_TYPE" --wall-speed "$WALL_SPEED" \
  --interface-exclude-cells "$INTERFACE_EXCLUDE_CELLS" \
  --wall-exclude-cells "$WALL_EXCLUDE_CELLS"

if [[ -s "$OUT/cuda_phase_interface_pressure_0493x6g.csv" && -s "$OUT/cuda_phase_interface_stencil_0493x6f.csv" ]]; then
  python3 "$ROOT/scripts/analyze_0493x6g_phase_gas_pressure.py" \
    --pressure "$OUT/cuda_phase_interface_pressure_0493x6g.csv" \
    --stencil "$OUT/cuda_phase_interface_stencil_0493x6f.csv" \
    --json "$CAMPAIGN_ROOT/analysis/phase_interface_gas_pressure_0493x14w.json"
fi

OUT_TAR="$CAMPAIGN_ROOT/0493x14w_two_phase_couette_compact.tar.gz"
FILES=(
  analysis
  "output/species_runtime_0493x14w.csv"
  "output/cuda_phase_interface_pressure_0493x6g.csv"
  "output/cuda_phase_interface_stencil_0493x6f.csv"
  "logs/${CASE_LABEL}.log"
  "logs/environment_0493x14w.env"
  "params/${CASE_LABEL}.kv"
)
EXIST=()
for f in "${FILES[@]}"; do [[ -e "$CAMPAIGN_ROOT/$f" ]] && EXIST+=("$f"); done
tar -czf "$OUT_TAR" -C "$CAMPAIGN_ROOT" "${EXIST[@]}"

echo
echo "[0493x14w] DONE"
echo "[0493x14w] summary: $CAMPAIGN_ROOT/analysis/couette_summary_0493x14w.json"
echo "[0493x14w] return:  $OUT_TAR"
