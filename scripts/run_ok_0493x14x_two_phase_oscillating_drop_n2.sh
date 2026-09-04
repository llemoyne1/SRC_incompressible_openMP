#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$ROOT/scripts/src_mpcd_run_ok_common.sh"
suite_root_cd_0434

GENERATOR="$ROOT/scripts/generate_0493x14x_oscillating_drop_two_phase.py"
ANALYZER="$ROOT/scripts/analyze_0493x14x_oscillating_drop_n2.py"
SRC14V="$ROOT/src/cuda_q6_resident_0400.cu"
for f in "$GENERATOR" "$ANALYZER" "$SRC14V"; do
  [[ -f "$f" ]] || { echo "[0493x14x] ERROR missing $f" >&2; exit 2; }
done
grep -q '0493x14v-gas-kinetic-excess' "$SRC14V" || {
  echo "[0493x14x] ERROR x14v source marker not found" >&2; exit 2;
}
grep -q 'eos_accessible_volume' "$SRC14V" || {
  echo "[0493x14x] ERROR x6g eos_accessible_volume marker not found" >&2; exit 2;
}
grep -q '0493x14z — reference-pressure geometric closure' "$SRC14V" || {
  echo "[0493x14x] ERROR x14z geometric-closure source marker not found" >&2; exit 2;
}
grep -q '0493x14ad — local-x6g-face gauge sampling with residual resultant projection' "$SRC14V" || {
  echo "[0493x14x] ERROR x14ad local-face gauge projection source marker not found" >&2; exit 2;
}

# =============================================================================
# 0493x14x — TWO-PHASE OSCILLATING DROP n=2
# Runner/tooling only. No C++/CUDA change and no new runtime diagnostic.
#
# Integrated chain under test:
#   x6g eos_accessible_volume + x9 Laplace + x14l gas specular + x14v normal
#   kinetic excess + qualified liquid x10o+CIC+Q2+x10p/q+x10u+x10v+x12a.
#
# The external box is periodic to remove physical-wall effects.  The existing
# x9f signed quadrupole diagnostic supplies the n=2 observable.
# =============================================================================

CASE_LABEL="${CASE_LABEL:-0493x14x_two_phase_oscillating_drop_n2}"
RUN_MODE="src-q6-g-f"
TOPOLOGY="periodic"

# Physical/numerical parameters — visible by design.
Lx="${Lx:-1.5625}"; Ly="${Ly:-1.5625}"; NX="${NX:-400}"; NY="${NY:-400}"
GAMMA="${GAMMA:-20}"
DT="${DT:-0.002}"
STEPS="${STEPS:-6000}"
SEED="${SEED:-493180}"

RADIUS_CELLS="${RADIUS_CELLS:-40}"
MODE="${MODE:-2}"
EPSILON="${EPSILON:-0.04}"
PHASE="${PHASE:-0.0}"
CENTER_X="${CENTER_X:-0.78125}"; CENTER_Y="${CENTER_Y:-0.78125}"

LIQUID_TYPE="${LIQUID_TYPE:-1}"; GAS_TYPE="${GAS_TYPE:-2}"
LIQUID_MASS="${LIQUID_MASS:-1.0}"; GAS_MASS="${GAS_MASS:-0.1}"
LIQUID_KBT="${LIQUID_KBT:-0.02}"; GAS_KBT="${GAS_KBT:-0.08}"
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

# Diagnostics / restart / visualization.
SUMMARY_EVERY="${SUMMARY_EVERY:-10}"
# 3.2 M particles: 2000 is an intentional adaptation of the usual 1000-step
# restart cadence to limit state volume while retaining three restart anchors.
DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-2000}"
FIT_PERIODS="${FIT_PERIODS:-2.5}"
LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
PREFLIGHT_ONLY="${PREFLIGHT_ONLY:-0}"
CLEAN_RUN_ROOT="${CLEAN_RUN_ROOT:-1}"
LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-1}"
LIVE_VIS_CONTROL_FILE="$ROOT/livevis_control.kv"
LIVE_VIS_FIELD="${LIVE_VIS_FIELD:-density}"
LIVE_VIS_EVERY="${LIVE_VIS_EVERY:-1}"
LIVE_VIS_NX="${LIVE_VIS_NX:-200}"; LIVE_VIS_NY="${LIVE_VIS_NY:-200}"
LIVE_VIS_COLORMAP="${LIVE_VIS_COLORMAP:-hot}"
LIVE_VIS_CLIP="${LIVE_VIS_CLIP:--1}"; LIVE_VIS_GAIN="${LIVE_VIS_GAIN:-1.0}"
LIVE_VIS_SMOOTH_PASSES="${LIVE_VIS_SMOOTH_PASSES:-1}"
LIVE_VIS_WINDOW_SCALE="${LIVE_VIS_WINDOW_SCALE:-1}"
LIVE_VIS_HOLD_ON_EXIT="${LIVE_VIS_HOLD_ON_EXIT:-1}"
# LiveVis recording for film reconstruction; filtered particle recording stays off.
RECORD_ENABLE="${RECORD_ENABLE:-true}"
RECORD_FIELDS="${RECORD_FIELDS:-mass,ux,uy}"
RECORD_EVERY="${RECORD_EVERY:-100}"
FILTER_MODE="${FILTER_MODE:-none}"
FILTER_SAMPLE_EVERY="${FILTER_SAMPLE_EVERY:-100}"
FILTERED_RECORDING_ENABLE="${FILTERED_RECORDING_ENABLE:-1}"
PARTICLE_TYPE_FILTER="${PARTICLE_TYPE_FILTER:-1}"

# Lightweight runner-level restart hook.  A restart is written as a separate
# segment so existing diagnostics are never overwritten.  For the nominal short
# qualification run RESTART=0.
RESTART="${RESTART:-0}"
RESTART_STATE="${RESTART_STATE:-}"
RESTART_TAG="${RESTART_TAG:-segment}"

BIN="${BIN:-${SRC_MPCD_DEFAULT_BIN_0434:-build/src_mpcd_base_cuda_q6_resident_livevis_0486}}"
CAMPAIGN_ROOT="${CAMPAIGN_ROOT:-runs/0493x14x_two_phase_oscillating_drop_n2}"

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

read -r H RADIUS AREA RHO_L RHO_G OMEGA0 PERIOD0 STEPS_PER_PERIOD P_REF <<<"$(python3 - \
 "$Lx" "$Ly" "$NX" "$NY" "$RADIUS_CELLS" "$GAMMA" "$LIQUID_MASS" "$GAS_MASS" \
 "$SURFACE_TENSION_SIGMA" "$MODE" "$EPSILON" "$DT" "$ROTATION_ANGLE" <<'PY'
import math,sys
lx,ly=float(sys.argv[1]),float(sys.argv[2]); nx,ny=int(sys.argv[3]),int(sys.argv[4])
rc,g,mL,mG,sigma=float(sys.argv[5]),float(sys.argv[6]),float(sys.argv[7]),float(sys.argv[8]),float(sys.argv[9])
n=int(sys.argv[10]); eps,dt,ang=float(sys.argv[11]),float(sys.argv[12]),float(sys.argv[13])
hx=lx/nx; hy=ly/ny
if abs(hx-hy)>1e-12*max(1.0,abs(hx),abs(hy)): raise SystemExit('[0493x14x] square cells required')
if abs(hx-1/256)>1e-12: raise SystemExit(f'[0493x14x] benchmark keeps characterized h=1/256, got {hx:.17g}')
if n!=2: raise SystemExit('[0493x14x] first integrated qualification is intentionally MODE=2')
if not (0<eps<=0.05): raise SystemExit('[0493x14x] require 0<epsilon<=0.05')
if abs(ang-math.pi/2)>1e-12: raise SystemExit('[0493x14x] current x14 fluid uses rotationAngle=90deg')
R=rc*hx; A=hx*hy; rhoL=g*mL/A; rhoG=g*mG/A
w=math.sqrt(n*(n*n-1)*sigma/((rhoL+rhoG)*R**3)); T=2*math.pi/w
# x6g thermodynamic reference uses gas kBT; shell computes pRef separately below.
print(f'{hx:.17g} {R:.17g} {A:.17g} {rhoL:.17g} {rhoG:.17g} {w:.17g} {T:.17g} {T/dt:.17g} 0')
PY
)"
P_REF="$(awk -v g="$GAMMA" -v tg="$GAS_KBT" -v a="$AREA" 'BEGIN{printf "%.17g",g*tg/a}')"

if [[ "$RESTART" == "1" ]]; then
  [[ -n "$RESTART_STATE" && -s "$RESTART_STATE" ]] || { echo '[0493x14x] ERROR RESTART=1 requires RESTART_STATE=/path/state_step_N.smpcd' >&2; exit 2; }
  RUN_ROOT="$CAMPAIGN_ROOT/restart_${RESTART_TAG}"
  STATE="$RESTART_STATE"
  CLEAN_RUN_ROOT=1
else
  RUN_ROOT="$CAMPAIGN_ROOT"
  STATE="$RUN_ROOT/init/${CASE_LABEL}.smpcd"
fi
if suite_truthy_0434 "$CLEAN_RUN_ROOT"; then rm -rf "$RUN_ROOT"; fi
suite_prepare_dirs_0434 "$RUN_ROOT"
OUT="$RUN_ROOT/output"; PARAMS="$RUN_ROOT/params/${CASE_LABEL}.kv"; LOG="$RUN_ROOT/logs/${CASE_LABEL}.log"; TF="$RUN_ROOT/logs/${CASE_LABEL}.time"; ANALYSIS_DIR="$RUN_ROOT/analysis"
mkdir -p "$OUT" "$ANALYSIS_DIR"

if [[ "$RESTART" != "1" ]]; then
  python3 "$GENERATOR" \
    --output "$STATE" --Lx "$Lx" --Ly "$Ly" --nx "$NX" --ny "$NY" --gamma "$GAMMA" \
    --center-x "$CENTER_X" --center-y "$CENTER_Y" --radius-cells "$RADIUS_CELLS" \
    --mode "$MODE" --epsilon "$EPSILON" --phase "$PHASE" \
    --liquid-type "$LIQUID_TYPE" --gas-type "$GAS_TYPE" \
    --liquid-mass "$LIQUID_MASS" --gas-mass "$GAS_MASS" \
    --liquid-kBT "$LIQUID_KBT" --gas-kBT "$GAS_KBT" --seed "$SEED"
fi

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
bcBottom = periodic
bcTop = periodic
bcX = periodic
bcY = periodic
openBoundarySegmentsEnable = false
openBoundarySegmentCount = 0
bodyAccelerationX = 0.0
bodyAccelerationY = 0.0
taylorGreenForcingEnable = false
wallVpEnable = false
wallAccommodation = 1.0
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
speciesDiagnosticsFilename = species_runtime_0493x14x.csv
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

# Complete qualified liquid chain unchanged + gas-side x14l/x14v.
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
export MPCD_X14V_GAS_KINETIC_EXCESS_KICK="${MPCD_X14V_GAS_KINETIC_EXCESS_KICK:-1}"
export MPCD_X14V_SUBTRACT_X6G_THERMODYNAMIC_TRACTION="${MPCD_X14V_SUBTRACT_X6G_THERMODYNAMIC_TRACTION:-1}"
export MPCD_X14V_X6G_FACE_THERMO_TRACTION="${MPCD_X14V_X6G_FACE_THERMO_TRACTION:-0}"
export MPCD_X14V_X6G_GAUGE_FACE_THERMO_TRACTION="${MPCD_X14V_X6G_GAUGE_FACE_THERMO_TRACTION:-0}"
export MPCD_X14V_X6G_GAUGE_RESULTANT_PROJECTION="${MPCD_X14V_X6G_GAUGE_RESULTANT_PROJECTION:-0}"
export MPCD_X14V_X6G_LOCAL_FACE_GAUGE_PROJECTION="${MPCD_X14V_X6G_LOCAL_FACE_GAUGE_PROJECTION:-0}"
export MPCD_X14V_SCATTER_LOSS_DIAGNOSTIC="${MPCD_X14V_SCATTER_LOSS_DIAGNOSTIC:-0}"
export MPCD_X14V_REFERENCE_PRESSURE_GEOMETRIC_CLOSURE="${MPCD_X14V_REFERENCE_PRESSURE_GEOMETRIC_CLOSURE:-0}"

# Existing diagnostics only: x9f supplies the signed n=2 observable.
export MPCD_Q6_ELLIPSE_DIAGNOSTICS_0493X9F=1
export MPCD_Q6_STATIC_DROP_DIAGNOSTICS_0493X9E=1
export MPCD_Q6_PHASE_CURVATURE_DIAGNOSTICS_0493X9A=0
export MPCD_Q6_PHASE_CURVATURE_DIAGNOSTICS_0493X9B=0
export MPCD_Q6_PHASE_CURVATURE_DIAGNOSTICS_0493X9C=0
export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_WORKSPACE_DOWNLOAD_0272=1

suite_prepare_livevis_control_0434 "$RUN_ROOT" "$RUN_MODE"
suite_export_livevis_0434
suite_write_env_file_0434 "$RUN_ROOT/logs/environment_0493x14x.env" "$RUN_MODE"
cat >> "$RUN_ROOT/logs/environment_0493x14x.env" <<META
BENCHMARK=0493x14x_two_phase_oscillating_drop_n2
MODE=$MODE
EPSILON=$EPSILON
RADIUS_CELLS=$RADIUS_CELLS
RADIUS=$RADIUS
RHO_L=$RHO_L
RHO_G=$RHO_G
RHO_G_OVER_RHO_L=$(awk -v a="$RHO_G" -v b="$RHO_L" 'BEGIN{printf "%.17g",a/b}')
OMEGA_2D_TWO_FLUID=$OMEGA0
PERIOD_2D_TWO_FLUID=$PERIOD0
STEPS_PER_PERIOD=$STEPS_PER_PERIOD
SURFACE_TENSION_SIGMA=$SURFACE_TENSION_SIGMA
MPCD_Q6_PHASE_GAS_PRESSURE_MODE_0493X6G=eos_accessible_volume
MPCD_X14L_GAS_SPECULAR_REFLECTION=1
MPCD_X14V_GAS_KINETIC_EXCESS_KICK=$MPCD_X14V_GAS_KINETIC_EXCESS_KICK
MPCD_X14V_SUBTRACT_X6G_THERMODYNAMIC_TRACTION=$MPCD_X14V_SUBTRACT_X6G_THERMODYNAMIC_TRACTION
MPCD_X14V_X6G_FACE_THERMO_TRACTION=$MPCD_X14V_X6G_FACE_THERMO_TRACTION
MPCD_X14V_X6G_GAUGE_FACE_THERMO_TRACTION=$MPCD_X14V_X6G_GAUGE_FACE_THERMO_TRACTION
MPCD_X14V_X6G_GAUGE_RESULTANT_PROJECTION=$MPCD_X14V_X6G_GAUGE_RESULTANT_PROJECTION
MPCD_X14V_X6G_LOCAL_FACE_GAUGE_PROJECTION=$MPCD_X14V_X6G_LOCAL_FACE_GAUGE_PROJECTION
MPCD_X14V_SCATTER_LOSS_DIAGNOSTIC=$MPCD_X14V_SCATTER_LOSS_DIAGNOSTIC
MPCD_X14V_REFERENCE_PRESSURE_GEOMETRIC_CLOSURE=$MPCD_X14V_REFERENCE_PRESSURE_GEOMETRIC_CLOSURE
RESTART=$RESTART
RESTART_STATE=$RESTART_STATE
META

echo
echo "===== 0493x14x TWO-PHASE OSCILLATING DROP n=2 ====="
echo "PATHS: runner=$ROOT/scripts/run_ok_0493x14x_two_phase_oscillating_drop_n2.sh"
echo "       generator=$GENERATOR analyzer=$ANALYZER"
echo "       state=$STATE params=$PARAMS output=$OUT"
echo "GEOM:  periodic ${NX}x${NY}, h=$H, R/h=$RADIUS_CELLS, n=$MODE, eps=$EPSILON"
echo "PHASE: liquid(type=$LIQUID_TYPE,m=$LIQUID_MASS,kBT=$LIQUID_KBT,q6=$LIQUID_Q6_STRENGTH)"
echo "       gas(type=$GAS_TYPE,m=$GAS_MASS,kBT=$GAS_KBT,q6=$GAS_Q6_STRENGTH)"
echo "CHAIN: x6g accessible-volume + x9 + x14l + x14v=${MPCD_X14V_GAS_KINETIC_EXCESS_KICK} subtract_pG=${MPCD_X14V_SUBTRACT_X6G_THERMODYNAMIC_TRACTION} thermoAbsX6gFaces=${MPCD_X14V_X6G_FACE_THERMO_TRACTION} thermoHybridGaugeX6gFaces=${MPCD_X14V_X6G_GAUGE_FACE_THERMO_TRACTION} thermoGaugeResultantProjection=${MPCD_X14V_X6G_GAUGE_RESULTANT_PROJECTION} thermoLocalFaceGaugeProjection=${MPCD_X14V_X6G_LOCAL_FACE_GAUGE_PROJECTION} scatterLossDiag=${MPCD_X14V_SCATTER_LOSS_DIAGNOSTIC} refPressureClosure=${MPCD_X14V_REFERENCE_PRESSURE_GEOMETRIC_CLOSURE}"
echo "       liquid x10o/CIC/Q2/x10p/q/x10u/x10v/x12a UNCHANGED"
echo "THEORY: rhoL=$RHO_L rhoG=$RHO_G omega2D=$OMEGA0 period=$PERIOD0 steps/period=$STEPS_PER_PERIOD"
echo "RUN:   steps=$STEPS dt=$DT tEnd=$(awk -v n="$STEPS" -v d="$DT" 'BEGIN{printf "%.9g",n*d}') summaryEvery=$SUMMARY_EVERY dumpEvery=$DUMP_STATE_EVERY"
echo "VIS:   enable=$LIVE_VIS_ENABLE every=$LIVE_VIS_EVERY record=$RECORD_ENABLE recordEvery=$RECORD_EVERY"
echo "NOTE:  ./livevis_control.kv is user-owned/read-only; filtered particle recording is OFF"
echo "===================================================="

suite_run_binary_0434 "$PARAMS" "$LOG" "$TF" "$OUT"
if suite_truthy_0434 "$PREFLIGHT_ONLY"; then echo '[0493x14x] PREFLIGHT_ONLY complete'; exit 0; fi

SHAPE="$OUT/cuda_ellipse_shape_0493x9f.csv"
[[ -s "$SHAPE" ]] || { echo "[0493x14x] ERROR missing x9f shape CSV: $SHAPE" >&2; exit 2; }
python3 "$ANALYZER" \
  --run-root "$RUN_ROOT" --radius-cells "$RADIUS_CELLS" --sigma "$SURFACE_TENSION_SIGMA" \
  --gamma "$GAMMA" --liquid-mass "$LIQUID_MASS" --gas-mass "$GAS_MASS" --h "$H" \
  --mode "$MODE" --fit-periods "$FIT_PERIODS" --liquid-type "$LIQUID_TYPE" --gas-type "$GAS_TYPE"

if [[ -s "$OUT/cuda_phase_interface_pressure_0493x6g.csv" && -s "$OUT/cuda_phase_interface_stencil_0493x6f.csv" ]]; then
  python3 "$ROOT/scripts/analyze_0493x6g_phase_gas_pressure.py" \
    --pressure "$OUT/cuda_phase_interface_pressure_0493x6g.csv" \
    --stencil "$OUT/cuda_phase_interface_stencil_0493x6f.csv" \
    --json "$ANALYSIS_DIR/phase_interface_gas_pressure_0493x14x.json" || true
fi

OUT_TAR="$RUN_ROOT/0493x14x_two_phase_oscillating_drop_n2_compact.tar.gz"
FILES=(analysis "output/cuda_ellipse_shape_0493x9f.csv" "output/species_runtime_0493x14x.csv" \
 "output/cuda_phase_interface_pressure_0493x6g.csv" "output/cuda_phase_interface_stencil_0493x6f.csv" \
 "output/cuda_surface_tension_limiter_0493x9r.csv" "logs/${CASE_LABEL}.log" \
 "logs/${CASE_LABEL}.time" "logs/environment_0493x14x.env" "params/${CASE_LABEL}.kv")
EXIST=(); for f in "${FILES[@]}"; do [[ -e "$RUN_ROOT/$f" ]] && EXIST+=("$f"); done
tar -czf "$OUT_TAR" -C "$RUN_ROOT" "${EXIST[@]}"

echo
echo "[0493x14x] DONE"
echo "[0493x14x] summary: $ANALYSIS_DIR/oscillating_drop_n2_summary_0493x14x.json"
echo "[0493x14x] return:  $OUT_TAR"
