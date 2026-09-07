#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$ROOT/scripts/src_mpcd_run_ok_common.sh"
suite_root_cd_0434

# 0493x14ak — two-phase Taylor-Culick qualification of x14ad+x14ai-fix1.
# Tooling only: no C++/CUDA modification and no new runtime diagnostic.
# The historical x13h benchmark G_TC=0.79457172 is retained explicitly as a
# contextual reference; current x14 constitutive parameters are not identical.

GENERATOR="$ROOT/scripts/generate_0493x14ak_taylor_culick_two_phase.py"
ANALYZER="$ROOT/scripts/analyze_0493x14ak_taylor_culick_two_phase.py"
SRC14V="$ROOT/src/cuda_q6_resident_0400.cu"
for f in "$GENERATOR" "$ANALYZER" "$SRC14V"; do
  [[ -f "$f" ]] || { echo "[0493x14ak] ERROR missing $f" >&2; exit 2; }
done
grep -q '0493x14ai — production-candidate device-side Q6 resultant closure' "$SRC14V" || {
  echo '[0493x14ak] ERROR x14ai source marker missing' >&2; exit 2;
}
grep -q 'B1-exact-post-periodic-device-target' "$SRC14V" || {
  echo '[0493x14ak] ERROR x14ai-fix1 marker missing' >&2; exit 2;
}

CASE_LABEL="${CASE_LABEL:-0493x14ak_two_phase_taylor_culick_device_closure}"
RUN_MODE="src-q6-g-f"
TOPOLOGY="closed_box"

# -----------------------------------------------------------------------------
# Physical/numerical parameters — deliberately visible.
# Geometry and sigma are the historical L/H=12 Taylor-Culick qualification.
# Fluid/species parameters are the current x14 liquid/gas point.
# -----------------------------------------------------------------------------
Lx="${Lx:-3.5}"; Ly="${Ly:-1.0}"; NX="${NX:-896}"; NY="${NY:-256}"
GAMMA="${GAMMA:-20}"
DT="${DT:-0.002}"
STEPS="${STEPS:-1200}"                  # 2.37 current Taylor-Culick times
SEED="${SEED:-4931501}"

SHEET_LENGTH_CELLS="${SHEET_LENGTH_CELLS:-768}"
THICKNESS_CELLS="${THICKNESS_CELLS:-64}"
EDGE_ROUND_CELLS="${EDGE_ROUND_CELLS:-8}"
CENTER_X="${CENTER_X:-1.75}"; CENTER_Y="${CENTER_Y:-0.5}"

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

SURFACE_TENSION_SIGMA="${SURFACE_TENSION_SIGMA:-10000.0}"
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

# Historical qualified liquid-only reference, retained exactly.
HISTORICAL_G_TC_X13H="${HISTORICAL_G_TC_X13H:-0.79457172}"
FIT_TAU_MIN="${FIT_TAU_MIN:-0.5}"; FIT_TAU_MAX="${FIT_TAU_MAX:-1.75}"

# -----------------------------------------------------------------------------
# Diagnostics / restart / visualization.
# Retraction is measured from liquid-only filtered mass recordings, not from
# frequent 4.6M-particle dumps. Full states only at 600 and 1200 for restart.
# -----------------------------------------------------------------------------
SUMMARY_EVERY="${SUMMARY_EVERY:-10}"
DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-600}"
LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
PREFLIGHT_ONLY="${PREFLIGHT_ONLY:-0}"
CLEAN_RUN_ROOT="${CLEAN_RUN_ROOT:-1}"

LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-1}"
LIVE_VIS_CONTROL_FILE="$ROOT/livevis_control.kv"
LIVE_VIS_FIELD="${LIVE_VIS_FIELD:-density}"
LIVE_VIS_EVERY="${LIVE_VIS_EVERY:-1}"
LIVE_VIS_NX="${LIVE_VIS_NX:-448}"; LIVE_VIS_NY="${LIVE_VIS_NY:-128}"
LIVE_VIS_COLORMAP="${LIVE_VIS_COLORMAP:-hot}"
LIVE_VIS_CLIP="${LIVE_VIS_CLIP:--1}"; LIVE_VIS_GAIN="${LIVE_VIS_GAIN:-1.0}"
LIVE_VIS_SMOOTH_PASSES="${LIVE_VIS_SMOOTH_PASSES:-0}"
LIVE_VIS_WINDOW_SCALE="${LIVE_VIS_WINDOW_SCALE:-1}"
LIVE_VIS_HOLD_ON_EXIT="${LIVE_VIS_HOLD_ON_EXIT:-1}"
RECORD_ENABLE="${RECORD_ENABLE:-true}"
RECORD_FIELDS="${RECORD_FIELDS:-mass}"
RECORD_EVERY="${RECORD_EVERY:-20}"
FILTER_MODE="${FILTER_MODE:-none}"
FILTER_SAMPLE_EVERY="${FILTER_SAMPLE_EVERY:-20}"
FILTERED_RECORDING_ENABLE="${FILTERED_RECORDING_ENABLE:-1}"
PARTICLE_TYPE_FILTER="${PARTICLE_TYPE_FILTER:-$LIQUID_TYPE}"

RESTART="${RESTART:-0}"
RESTART_STATE="${RESTART_STATE:-}"
RESTART_TAG="${RESTART_TAG:-segment}"

BIN="${BIN:-${SRC_MPCD_DEFAULT_BIN_0434:-build/src_mpcd_base_cuda_q6_resident_livevis_0486}}"
CAMPAIGN_ROOT="${CAMPAIGN_ROOT:-runs/0493x14ak_two_phase_taylor_culick_s10000_seed${SEED}}"

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

read -r H SHEET_H SHEET_L EDGE_R AREA RHO_L RHO_G UTC TAUTC U_HIST UDT XCLR YCLR P_REF <<<"$(python3 - \
 "$Lx" "$Ly" "$NX" "$NY" "$GAMMA" "$LIQUID_MASS" "$GAS_MASS" \
 "$SHEET_LENGTH_CELLS" "$THICKNESS_CELLS" "$EDGE_ROUND_CELLS" "$CENTER_X" "$CENTER_Y" \
 "$SURFACE_TENSION_SIGMA" "$DT" "$ROTATION_ANGLE" "$HISTORICAL_G_TC_X13H" "$GAS_KBT" <<'PY'
import math,sys
lx,ly=float(sys.argv[1]),float(sys.argv[2]);nx,ny=int(sys.argv[3]),int(sys.argv[4])
g,mL,mG=float(sys.argv[5]),float(sys.argv[6]),float(sys.argv[7]);Lc,Hc,Rc=map(float,sys.argv[8:11])
cx,cy,sigma,dt,angle,histG,tg=map(float,sys.argv[11:18])
hx,hy=lx/nx,ly/ny
if abs(hx-hy)>1e-12*max(1.0,abs(hx),abs(hy)):raise SystemExit('[0493x14ak] square cells required')
if abs(hx-1/256)>1e-12:raise SystemExit(f'[0493x14ak] benchmark keeps h=1/256, got {hx:.17g}')
if abs(angle-math.pi/2)>1e-12:raise SystemExit('[0493x14ak] current x14 fluid requires rotationAngle=90deg')
if Rc<8 or Hc!=64 or Lc!=768:raise SystemExit('[0493x14ak] default qualification geometry is L/h=768 H/h=64 edgeRound/h>=8')
h=hx;H=Hc*h;L=Lc*h;rr=Rc*h;A=h*h;rhoL=g*mL/A;rhoG=g*mG/A
xclr=min(cx-L/2,lx-(cx+L/2));yclr=min(cy-H/2,ly-(cy+H/2))
if min(xclr,yclr)<=16*h:raise SystemExit('[0493x14ak] require >16h initial wall clearance')
utc=math.sqrt(2*sigma/(rhoL*H));tau=H/utc;uh=histG*utc;udt=utc*dt/h;pref=g*tg/A
print(f'{h:.17g} {H:.17g} {L:.17g} {rr:.17g} {A:.17g} {rhoL:.17g} {rhoG:.17g} {utc:.17g} {tau:.17g} {uh:.17g} {udt:.17g} {xclr/h:.17g} {yclr/h:.17g} {pref:.17g}')
PY
)"

if [[ "$RESTART" == "1" ]]; then
  [[ -n "$RESTART_STATE" && -s "$RESTART_STATE" ]] || { echo '[0493x14ak] ERROR RESTART=1 requires RESTART_STATE=/path/state_step_N.smpcd' >&2; exit 2; }
  RUN_ROOT="$CAMPAIGN_ROOT/restart_${RESTART_TAG}"
  STATE="$RESTART_STATE"
  CLEAN_RUN_ROOT=1
else
  RUN_ROOT="$CAMPAIGN_ROOT"
  STATE="$RUN_ROOT/init/${CASE_LABEL}.smpcd"
fi
if suite_truthy_0434 "$CLEAN_RUN_ROOT"; then rm -rf "$RUN_ROOT"; fi
suite_prepare_dirs_0434 "$RUN_ROOT"
OUT="$RUN_ROOT/output"; PARAMS="$RUN_ROOT/params/${CASE_LABEL}.kv"; LOG="$RUN_ROOT/logs/${CASE_LABEL}.log"; TF="$RUN_ROOT/logs/${CASE_LABEL}.time"; ANALYSIS_DIR="$RUN_ROOT/analysis_0493x14ak"
mkdir -p "$OUT" "$ANALYSIS_DIR"

if [[ "$RESTART" != "1" ]]; then
  python3 "$GENERATOR" \
    --output "$STATE" --Lx "$Lx" --Ly "$Ly" --nx "$NX" --ny "$NY" --gamma "$GAMMA" \
    --center-x "$CENTER_X" --center-y "$CENTER_Y" --sheet-length-cells "$SHEET_LENGTH_CELLS" \
    --thickness-cells "$THICKNESS_CELLS" --edge-round-cells "$EDGE_ROUND_CELLS" \
    --liquid-type "$LIQUID_TYPE" --gas-type "$GAS_TYPE" --liquid-mass "$LIQUID_MASS" --gas-mass "$GAS_MASS" \
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
speciesDiagnosticsFilename = species_runtime_0493x14ak.csv
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

# Qualified liquid free-surface chain, unchanged.
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

# Current gas/liquid closure under qualification: x14ad + x14ai-fix1.
export MPCD_X14V_GAS_KINETIC_EXCESS_KICK=1
export MPCD_X14V_SUBTRACT_X6G_THERMODYNAMIC_TRACTION=1
export MPCD_X14V_X6G_FACE_THERMO_TRACTION=0
export MPCD_X14V_X6G_GAUGE_FACE_THERMO_TRACTION=0
export MPCD_X14V_X6G_GAUGE_RESULTANT_PROJECTION=0
export MPCD_X14V_X6G_LOCAL_FACE_GAUGE_PROJECTION=1
export MPCD_X14V_REFERENCE_PRESSURE_GEOMETRIC_CLOSURE=0
export MPCD_X14V_SCATTER_LOSS_DIAGNOSTIC=0
export MPCD_X14V_GLOBAL_BALANCE_DIAGNOSTIC="${MPCD_X14V_GLOBAL_BALANCE_DIAGNOSTIC:-0}"
export MPCD_X14V_DEVICE_APPLIED_Q6_RESULTANT_CLOSURE=1

# Existing diagnostics only.
export MPCD_Q6_ELLIPSE_DIAGNOSTICS_0493X9F=0
export MPCD_Q6_STATIC_DROP_DIAGNOSTICS_0493X9E=0
export MPCD_Q6_PHASE_CURVATURE_DIAGNOSTICS_0493X9A=0
export MPCD_Q6_PHASE_CURVATURE_DIAGNOSTICS_0493X9B=0
export MPCD_Q6_PHASE_CURVATURE_DIAGNOSTICS_0493X9C=0
export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_WORKSPACE_DOWNLOAD_0272=1

suite_prepare_livevis_control_0434 "$RUN_ROOT" "$RUN_MODE"
suite_export_livevis_0434
suite_write_env_file_0434 "$RUN_ROOT/logs/environment_0493x14ak.env" "$RUN_MODE"
cat >> "$RUN_ROOT/logs/environment_0493x14ak.env" <<META
BENCHMARK=0493x14ak_two_phase_taylor_culick
SHEET_LENGTH_CELLS=$SHEET_LENGTH_CELLS
THICKNESS_CELLS=$THICKNESS_CELLS
EDGE_ROUND_CELLS=$EDGE_ROUND_CELLS
RHO_L=$RHO_L
RHO_G=$RHO_G
U_TC_CURRENT_THEORY=$UTC
TAU_TC_CURRENT=$TAUTC
HISTORICAL_G_TC_X13H=$HISTORICAL_G_TC_X13H
HISTORICAL_GAIN_APPLIED_CURRENT_U_TC=$U_HIST
MPCD_X14V_X6G_LOCAL_FACE_GAUGE_PROJECTION=1
MPCD_X14V_DEVICE_APPLIED_Q6_RESULTANT_CLOSURE=1
RESTART=$RESTART
RESTART_STATE=$RESTART_STATE
META

echo
echo "===== 0493x14ak TWO-PHASE TAYLOR-CULICK ====="
echo "PATHS: runner=$ROOT/scripts/run_0493x14ak_taylor_culick_two_phase_device_closure.sh"
echo "       generator=$GENERATOR analyzer=$ANALYZER"
echo "       state=$STATE params=$PARAMS output=$OUT"
echo "GEOM:  closed_box ${NX}x${NY}, h=$H, sheet L/h=$SHEET_LENGTH_CELLS H/h=$THICKNESS_CELLS edgeRound/h=$EDGE_ROUND_CELLS"
echo "       clearance x/h=$XCLR y/h=$YCLR"
echo "PHASE: liquid(type=$LIQUID_TYPE,m=$LIQUID_MASS,kBT=$LIQUID_KBT,q6=$LIQUID_Q6_STRENGTH)"
echo "       gas(type=$GAS_TYPE,m=$GAS_MASS,kBT=$GAS_KBT,q6=$GAS_Q6_STRENGTH) rhoG/rhoL=$(awk -v g="$RHO_G" -v l="$RHO_L" 'BEGIN{printf "%.9g",g/l}')"
echo "CHAIN: x6g + x9 + x14l + x14v + x14ad local traction + x14ai-fix1 resultant"
echo "       liquid x10o/CIC/Q2/x10p/q/x10u/x10v/x12a UNCHANGED"
echo "THEORY: sigma=$SURFACE_TENSION_SIGMA rhoL=$RHO_L U_TC=$UTC tau_TC=$TAUTC Udt/h=$UDT"
echo "HIST:  historical x13h G_TC=$HISTORICAL_G_TC_X13H => same-gain current-speed=$U_HIST"
echo "       historical constitutive point differs; comparison is contextual, not paired"
echo "RUN:   steps=$STEPS dt=$DT tEnd=$(awk -v n="$STEPS" -v d="$DT" 'BEGIN{printf "%.9g",n*d}') summaryEvery=$SUMMARY_EVERY dumpEvery=$DUMP_STATE_EVERY"
echo "VIS:   enable=$LIVE_VIS_ENABLE every=$LIVE_VIS_EVERY grid=${LIVE_VIS_NX}x${LIVE_VIS_NY} liquid-only record=$RECORD_ENABLE every=$RECORD_EVERY fields=$RECORD_FIELDS"
echo "NOTE:  ./livevis_control.kv is user-owned/read-only and is not modified"
echo "==================================================="

suite_run_binary_0434 "$PARAMS" "$LOG" "$TF" "$OUT"
if suite_truthy_0434 "$PREFLIGHT_ONLY"; then echo '[0493x14ak] PREFLIGHT_ONLY complete'; exit 0; fi

grep -q 'deviceAppliedQ6ResultantClosure=B1-exact-post-periodic-device-target' "$LOG" || {
  echo '[0493x14ak] ERROR expected x14ai-fix1 runtime marker absent' >&2; exit 2;
}

python3 "$ANALYZER" \
  --run-root "$RUN_ROOT" --Lx "$Lx" --Ly "$Ly" --nx "$NX" --ny "$NY" \
  --gamma "$GAMMA" --liquid-mass "$LIQUID_MASS" --gas-mass "$GAS_MASS" --liquid-type "$LIQUID_TYPE" \
  --sigma "$SURFACE_TENSION_SIGMA" --thickness-cells "$THICKNESS_CELLS" --sheet-length-cells "$SHEET_LENGTH_CELLS" \
  --center-x "$CENTER_X" --center-y "$CENTER_Y" --dt "$DT" \
  --fit-tau-min "$FIT_TAU_MIN" --fit-tau-max "$FIT_TAU_MAX" --historical-g-tc "$HISTORICAL_G_TC_X13H"

OUT_TAR="$RUN_ROOT/0493x14ak_two_phase_taylor_culick_compact.tar.gz"
FILES=("analysis_0493x14ak" "output/recordings" "output/species_runtime_0493x14ak.csv" \
 "output/cuda_phase_interface_pressure_0493x6g.csv" "output/cuda_phase_interface_stencil_0493x6f.csv" \
 "output/cuda_surface_tension_limiter_0493x9r.csv" "output/cuda_phase_kinetic_crossing_0493x9z.csv" \
 "output/cuda_species_q6_independent_masked_0493w5.csv" "output/cuda_species_q6_0491.csv" \
 "logs/${CASE_LABEL}.log" "logs/${CASE_LABEL}.time" "logs/environment_0493x14ak.env" \
 "params/${CASE_LABEL}.kv" "init/${CASE_LABEL}.smpcd.json")
EXIST=(); for f in "${FILES[@]}"; do [[ -e "$RUN_ROOT/$f" ]] && EXIST+=("$f"); done
tar -czf "$OUT_TAR" -C "$RUN_ROOT" "${EXIST[@]}"

echo
echo "[0493x14ak] DONE"
echo "[0493x14ak] report: $RUN_ROOT/analysis_0493x14ak/taylor_culick_two_phase_report.txt"
echo "[0493x14ak] return: $OUT_TAR"
