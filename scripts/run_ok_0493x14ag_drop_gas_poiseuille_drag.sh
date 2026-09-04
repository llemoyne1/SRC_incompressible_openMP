#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$ROOT/scripts/src_mpcd_run_ok_common.sh"
suite_root_cd_0434

GENERATOR="$ROOT/scripts/generate_0493x14ag_drop_gas_poiseuille.py"
ANALYZER="$ROOT/scripts/analyze_0493x14ag_drop_gas_poiseuille.py"
SRC="$ROOT/src/cuda_q6_resident_0400.cu"
for f in "$GENERATOR" "$ANALYZER" "$SRC"; do [[ -f "$f" ]] || { echo "[0493x14ag] missing $f" >&2; exit 2; }; done
grep -q '0493x14ad — local-x6g-face gauge sampling' "$SRC" || { echo '[0493x14ag] x14ad source marker missing' >&2; exit 2; }

# -----------------------------------------------------------------------------
# 0493x14ag — circular liquid drop driven by a real gas Poiseuille through-flow.
# No body force: gas momentum enters only through the gas inlet.  The drop starts
# at rest on the channel centreline and must acquire positive x velocity by drag.
# -----------------------------------------------------------------------------
CASE_LABEL="${CASE_LABEL:-0493x14ag_drop_gas_poiseuille_drag}"
RUN_MODE=src-q6-g-f
TOPOLOGY=segmented
Lx="${Lx:-2.0}"; Ly="${Ly:-1.0}"; NX="${NX:-512}"; NY="${NY:-256}"
GAMMA="${GAMMA:-20}"; DT="${DT:-0.002}"; STEPS="${STEPS:-6000}"; SEED="${SEED:-493190}"
RADIUS_CELLS="${RADIUS_CELLS:-40}"; CENTER_X="${CENTER_X:-1.0}"; CENTER_Y="${CENTER_Y:-0.5}"
LIQUID_TYPE="${LIQUID_TYPE:-1}"; GAS_TYPE="${GAS_TYPE:-2}"
LIQUID_MASS="${LIQUID_MASS:-1.0}"; GAS_MASS="${GAS_MASS:-0.1}"
LIQUID_KBT="${LIQUID_KBT:-0.02}"; GAS_KBT="${GAS_KBT:-0.08}"
GAS_UMEAN="${GAS_UMEAN:-0.05}"; GAS_UMAX="${GAS_UMAX:-0.075}"
DROP_UX0="${DROP_UX0:-0.0}"; DROP_UY0="${DROP_UY0:-0.0}"
SURFACE_TENSION_SIGMA="${SURFACE_TENSION_SIGMA:-2560.0}"
SURFACE_TENSION_MIN_RADIUS_CELLS="${SURFACE_TENSION_MIN_RADIUS_CELLS:-4}"
LIQUID_Q6_STRENGTH=1.0; GAS_Q6_STRENGTH=0.0; SPECIES_Q6_MIN_FILL_FRACTION="${SPECIES_Q6_MIN_FILL_FRACTION:-0.10}"

ROTATION_ANGLE="${ROTATION_ANGLE:-1.5707963267948966}"; RANDOM_ROTATION_SIGN=true; GRID_SHIFT_ENABLE=true
THERMOSTAT_ENABLE=true; THERMOSTAT_MODE=cell_relative_rescale; THERMOSTAT_EVERY=1; THERMOSTAT_TARGET_KBT="$GAS_KBT"; THERMOSTAT_MIN_PARTICLES=3
PROJECTION_BACKEND=cuda; PROJECTION_MAX_ITERATIONS="${PROJECTION_MAX_ITERATIONS:-1200}"; PROJECTION_TOLERANCE="${PROJECTION_TOLERANCE:-1e-5}"; Q6_PROJECTION_STRENGTH=1.0; Q6_STRICT=1
Q6_GF_DENSITY_RELAXATION_TIME="${Q6_GF_DENSITY_RELAXATION_TIME:-0.25}"; Q6_GF_DENSITY_COMPRESSION_GATE_ENABLE=1; Q6_GF_DENSITY_COMPRESSION_THRESHOLD_PARTICLES=3.0; Q6_GF_DENSITY_TRACTION_THRESHOLD_PARTICLES=6.0; Q6_GF_DENSITY_TRACTION_GAIN=1.0; Q6_GF_MIN_FILL_FRACTION="$SPECIES_Q6_MIN_FILL_FRACTION"
Q6_GF_EXTERNAL_SPECIES=1; Q6_GF_HAS_GAS_PHASE=1
SPECIES_RESAMPLING_ENABLE=false; LIQUID_RESAMPLING_ENABLE=false; GAS_RESAMPLING_ENABLE=false; WEIGHTED_RESAMPLING_ENABLE_OVERRIDE=false; CUDA_EMPTY_REFILL_ENABLE_OVERRIDE=false; VIRIAL_DENSITY_KICK_ENABLE=false

SURFACE_TENSION_SIGMA="${SURFACE_TENSION_SIGMA:-2560.0}"
SURFACE_TENSION_MIN_RADIUS_CELLS="${SURFACE_TENSION_MIN_RADIUS_CELLS:-4}"
PHASE_INTERFACE_KINETIC_REFLECTION_FRACTION="${PHASE_INTERFACE_KINETIC_REFLECTION_FRACTION:-1.0}"
PHASE_INTERFACE_EVAPORATION_TARGET_TYPE="${PHASE_INTERFACE_EVAPORATION_TARGET_TYPE:--1}"
PHASE_INTERFACE_CONTACT_ANGLE_DEG="${PHASE_INTERFACE_CONTACT_ANGLE_DEG:--1}"
X12A_LOCAL_THERMAL_RADIUS_CELLS="${X12A_LOCAL_THERMAL_RADIUS_CELLS:-25.298221281347036}"
PHASE_INTERFACE_A_SELECTOR="type:${LIQUID_TYPE}"; PHASE_INTERFACE_B_SELECTOR="type:${GAS_TYPE}"


INLET_PROFILE="${INLET_PROFILE:-poiseuille_y_max}"; OUTLET_MODE="${OUTLET_MODE:-neumann}"; INLET_RESERVOIR_CELLS="${INLET_RESERVOIR_CELLS:-6}"
SUMMARY_EVERY="${SUMMARY_EVERY:-25}"; DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-1000}"
CAMPAIGN_ROOT="${CAMPAIGN_ROOT:-runs/0493x14ag_drop_gas_poiseuille_drag_seed${SEED}}"; CLEAN_RUN_ROOT="${CLEAN_RUN_ROOT:-1}"; PREFLIGHT_ONLY="${PREFLIGHT_ONLY:-0}"
BIN="${BIN:-${SRC_MPCD_DEFAULT_BIN_0434:-build/src_mpcd_base_cuda_q6_resident_livevis_0486}}"

LIVE_PROGRESS=1; LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-1}"; LIVE_VIS_CONTROL_FILE="$ROOT/livevis_control.kv"; LIVE_VIS_FIELD="${LIVE_VIS_FIELD:-mass}"; LIVE_VIS_EVERY="${LIVE_VIS_EVERY:-1}"; LIVE_VIS_NX="${LIVE_VIS_NX:-256}"; LIVE_VIS_NY="${LIVE_VIS_NY:-128}"; LIVE_VIS_COLORMAP="${LIVE_VIS_COLORMAP:-hot}"; LIVE_VIS_CLIP="${LIVE_VIS_CLIP:--1}"; LIVE_VIS_GAIN="${LIVE_VIS_GAIN:-1.0}"; LIVE_VIS_SMOOTH_PASSES="${LIVE_VIS_SMOOTH_PASSES:-1}"; LIVE_VIS_WINDOW_SCALE="${LIVE_VIS_WINDOW_SCALE:-1}"; LIVE_VIS_HOLD_ON_EXIT="${LIVE_VIS_HOLD_ON_EXIT:-1}"
RECORD_ENABLE="${RECORD_ENABLE:-true}"; RECORD_FIELDS="${RECORD_FIELDS:-mass,ux,uy}"; RECORD_EVERY="${RECORD_EVERY:-100}"; FILTER_MODE="${FILTER_MODE:-none}"; FILTER_SAMPLE_EVERY="${FILTER_SAMPLE_EVERY:-100}"; FILTERED_RECORDING_ENABLE="${FILTERED_RECORDING_ENABLE:-1}"; PARTICLE_TYPE_FILTER="${PARTICLE_TYPE_FILTER:--1}"

# x14ad is the current low-cost dynamic candidate. x14af is optional here: the
# drag test should remain representative of production timing by default.
export MPCD_X14V_GAS_KINETIC_EXCESS_KICK="${MPCD_X14V_GAS_KINETIC_EXCESS_KICK:-1}"
export MPCD_X14V_SUBTRACT_X6G_THERMODYNAMIC_TRACTION="${MPCD_X14V_SUBTRACT_X6G_THERMODYNAMIC_TRACTION:-1}"
export MPCD_X14V_X6G_FACE_THERMO_TRACTION=0
export MPCD_X14V_X6G_GAUGE_FACE_THERMO_TRACTION=0
export MPCD_X14V_X6G_GAUGE_RESULTANT_PROJECTION=0
export MPCD_X14V_X6G_LOCAL_FACE_GAUGE_PROJECTION=1
export MPCD_X14V_REFERENCE_PRESSURE_GEOMETRIC_CLOSURE=0
export MPCD_X14V_SCATTER_LOSS_DIAGNOSTIC=0
export MPCD_X14V_GLOBAL_BALANCE_DIAGNOSTIC="${MPCD_X14V_GLOBAL_BALANCE_DIAGNOSTIC:-0}"

PARTICLE_MASS="$GAS_MASS"; KBT="$GAS_KBT"; GEN_CASE=tg; U0=0.0; VELOCITY_MODE=zero; BACKGROUND_TYPE="$GAS_TYPE"; INACTIVE_TYPE="$GAS_TYPE"; TG_HOLE_ENABLE=false
RUN_OK_REFERENCE_PARTICLE_MASS="$LIQUID_MASS"; RUN_OK_GENERATOR_PATH="$GENERATOR"; export RUN_OK_REFERENCE_PARTICLE_MASS RUN_OK_GENERATOR_PATH
suite_defaults_common_0434
suite_compute_derived_0434

read -r H RADIUS AREA RHO_L RHO_G P_REF WE_CENTER MACH_PROXY <<<"$(python3 - "$Lx" "$Ly" "$NX" "$NY" "$RADIUS_CELLS" "$GAMMA" "$LIQUID_MASS" "$GAS_MASS" "$GAS_KBT" "$GAS_UMAX" "$SURFACE_TENSION_SIGMA" <<'PY'
import math,sys
lx,ly=float(sys.argv[1]),float(sys.argv[2]);nx,ny=int(sys.argv[3]),int(sys.argv[4]);rc,g,mL,mG,kbtG,umax,sigma=map(float,sys.argv[5:])
h=lx/nx;hy=ly/ny
if abs(h-hy)>1e-12:raise SystemExit('[0493x14ag] square cells required')
if abs(h-1/256)>1e-12:raise SystemExit(f'[0493x14ag] keeps characterized h=1/256, got {h}')
R=rc*h;A=h*h;rhoL=g*mL/A;rhoG=g*mG/A;pref=g*kbtG/A;We=rhoG*umax*umax*(2*R)/sigma;mach=umax/math.sqrt(kbtG/mG)
print(h,R,A,rhoL,rhoG,pref,We,mach)
PY
)"
python3 - "$GAS_UMEAN" "$GAS_UMAX" "$CENTER_X" "$CENTER_Y" "$Lx" "$Ly" "$RADIUS" "$H" <<'PY'
import math,sys
umean,umax,cx,cy,lx,ly,R,h=map(float,sys.argv[1:])
if not math.isclose(umean,2*umax/3,rel_tol=1e-12,abs_tol=1e-14):raise SystemExit('[0493x14ag] GAS_UMEAN must equal 2/3 GAS_UMAX for poiseuille_y_max')
if abs(cy-0.5*ly)>1e-12:raise SystemExit('[0493x14ag] first drag qualification keeps the drop on the channel centreline')
if not (R+8*h < cx < lx-R-8*h):raise SystemExit('[0493x14ag] insufficient axial clearance')
PY

if suite_truthy_0434 "$CLEAN_RUN_ROOT"; then rm -rf "$CAMPAIGN_ROOT"; fi
suite_prepare_dirs_0434 "$CAMPAIGN_ROOT"
STATE="$CAMPAIGN_ROOT/init/${CASE_LABEL}.smpcd"; OUT="$CAMPAIGN_ROOT/output"; PARAMS="$CAMPAIGN_ROOT/params/${CASE_LABEL}.kv"; LOG="$CAMPAIGN_ROOT/logs/${CASE_LABEL}.log"; TF="$CAMPAIGN_ROOT/logs/${CASE_LABEL}.time"; ANALYSIS_DIR="$CAMPAIGN_ROOT/analysis"; mkdir -p "$OUT" "$ANALYSIS_DIR"

python3 "$GENERATOR" --output "$STATE" --Lx "$Lx" --Ly "$Ly" --nx "$NX" --ny "$NY" --gamma "$GAMMA" --center-x "$CENTER_X" --center-y "$CENTER_Y" --radius-cells "$RADIUS_CELLS" --liquid-type "$LIQUID_TYPE" --gas-type "$GAS_TYPE" --liquid-mass "$LIQUID_MASS" --gas-mass "$GAS_MASS" --liquid-kBT "$LIQUID_KBT" --gas-kBT "$GAS_KBT" --gas-umax "$GAS_UMAX" --drop-ux0 "$DROP_UX0" --drop-uy0 "$DROP_UY0" --seed "$SEED"
LREF="$(awk -v g="$GAMMA" -v m="$LIQUID_MASS" 'BEGIN{printf "%.17g",g*m}')"; GREF="$(awk -v g="$GAMMA" -v m="$GAS_MASS" 'BEGIN{printf "%.17g",g*m}')"
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
bcX = solid
bcY = solid
openBoundarySegmentsEnable = true
openBoundarySegmentCount = 2
openBoundarySegment0 = left inlet 0.0 1.0 $GAS_UMAX 0.0 $GAS_TYPE $GAS_MASS
openBoundarySegment1 = right outlet 0.0 1.0 $GAS_UMEAN 0.0 0 $GAS_MASS
inletVelocityRampEnable = true
inletVelocityRampStartTime = 0.0
inletVelocityRampEndTime = 0.0
inletVelocityRampInitialFactor = 1.0
inletVelocityRampFinalFactor = 1.0
inletVelocityRampProfile = smoothstep
inletVelocitySpatialProfile = $INLET_PROFILE
inletKBT = $GAS_KBT
inletThermalNoise = 0.0
inletInjectionMode = hard_cell_density
inletReservoirMode = hard_cell_density
inletReservoirCells = $INLET_RESERVOIR_CELLS
inletTargetOccupancy = $GAMMA
inletHardCellVelocityMean = true
inletHardCellThermalRescale = true
inletRandomizeTangential = true
inletReinjectBackflow = true
openBoundaryOutletMode = $OUTLET_MODE
openBoundaryOutletHybridBlend = 0.0
openBoundaryOutletFeedbackGain = 0.0
bodyAccelerationX = 0.0
bodyAccelerationY = 0.0
wallAccommodation = 1.0
wallVpGamma = $GAMMA
wallVpMass = $GAS_MASS
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
speciesDiagnosticsFilename = species_runtime_0493x14ag.csv
speciesCellDiagnosticsEnable = false
speciesQ6Sensitivity = 1.0
speciesQ6FallbackMode = common
speciesQ6ComparisonTolerance = 1.0e-11
PARAMS
suite_write_common_params_0434 "$RUN_MODE" >> "$PARAMS"
run_ok_surface_append_params_0493x13zi "$PARAMS" "type:${LIQUID_TYPE}" "type:${GAS_TYPE}"
cat >> "$PARAMS" <<'PARAMS'
phaseInterfaceKineticBilateralRelocation = true
PARAMS

suite_export_cuda_flags_0434 "$RUN_MODE" "$TOPOLOGY"
run_ok_surface_export_off_flags_0493x13zi
export MPCD_Q6_PHASE_GAS_PRESSURE_0493X6G=1
export MPCD_Q6_PHASE_GAS_PRESSURE_MODE_0493X6G=eos_accessible_volume
export MPCD_Q6_PHASE_GAS_PRESSURE_REFERENCE_0493X6G="$P_REF"
export MPCD_Q6_PHASE_GAS_PRESSURE_SCALE_0493X6G=1
export MPCD_X10O_Q6_THERMAL_INTERFACE_WALL=1; export MPCD_X10O_THERMAL_PARTICLE_MASS="$LIQUID_MASS"; export MPCD_X10O_THERMAL_SIGMAS="${X10O_THERMAL_SIGMAS:-3.0}"; export MPCD_X10O_THERMAL_MAX_CELLS="${X10O_THERMAL_MAX_CELLS:-0.75}"
export MPCD_X10_KINETIC_INTERFACE_CIC=1; export MPCD_X10_KINETIC_INTERFACE_QUADRATIC=1; export MPCD_X10P_INITIAL_OVERLAP_RESOLUTION=1; export MPCD_X10_KINETIC_INTERFACE_ONE_FOR_ONE=1; export MPCD_X14L_GAS_SPECULAR_REFLECTION=1; export MPCD_X10_KINETIC_INTERFACE_ONE_FOR_ONE_SWAP=1; export MPCD_X10_KINETIC_INTERFACE_ONE_FOR_ONE_NORMAL_ONLY=0; export MPCD_X10_KINETIC_INTERFACE_THERMAL_PHASE_LIMITER=0; export MPCD_X12A_LOCAL_THERMAL_COOLING=1; export MPCD_X12A_LOCAL_THERMAL_RADIUS_CELLS="${X12A_LOCAL_THERMAL_RADIUS_CELLS:-25.298221281347036}"
export MPCD_Q6_ELLIPSE_DIAGNOSTICS_0493X9F=1; export MPCD_Q6_STATIC_DROP_DIAGNOSTICS_0493X9E=1; export MPCD_Q6_PHASE_CURVATURE_DIAGNOSTICS_0493X9A=0; export MPCD_Q6_PHASE_CURVATURE_DIAGNOSTICS_0493X9B=0; export MPCD_Q6_PHASE_CURVATURE_DIAGNOSTICS_0493X9C=0; export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_WORKSPACE_DOWNLOAD_0272=1

suite_prepare_livevis_control_0434 "$CAMPAIGN_ROOT" "$RUN_MODE"; suite_export_livevis_0434
suite_write_env_file_0434 "$CAMPAIGN_ROOT/logs/environment_0493x14ag.env" "$RUN_MODE"
cat >> "$CAMPAIGN_ROOT/logs/environment_0493x14ag.env" <<META
BENCHMARK=0493x14ag_drop_gas_poiseuille_drag
GAS_UMEAN=$GAS_UMEAN
GAS_UMAX=$GAS_UMAX
DROP_CENTER=$CENTER_X,$CENTER_Y
DROP_RADIUS=$RADIUS
WE_CENTERLINE=$WE_CENTER
THERMAL_MACH_PROXY=$MACH_PROXY
MPCD_X14V_X6G_LOCAL_FACE_GAUGE_PROJECTION=$MPCD_X14V_X6G_LOCAL_FACE_GAUGE_PROJECTION
MPCD_X14V_GLOBAL_BALANCE_DIAGNOSTIC=$MPCD_X14V_GLOBAL_BALANCE_DIAGNOSTIC
META

echo "===== 0493x14ag GAS-POISEUILLE DROP DRAG ====="
echo "PATHS: runner=$ROOT/scripts/run_ok_0493x14ag_drop_gas_poiseuille_drag.sh generator=$GENERATOR analyzer=$ANALYZER"
echo "DOMAIN: ${Lx}x${Ly} grid=${NX}x${NY} h=$H walls=y inlet=left outlet=right"
echo "DROP: center=($CENTER_X,$CENTER_Y) R/h=$RADIUS_CELLS R=$RADIUS U0=($DROP_UX0,$DROP_UY0)"
echo "GAS: Umean=$GAS_UMEAN Umax=$GAS_UMAX profile=$INLET_PROFILE We(centerline)=$WE_CENTER thermalMachProxy=$MACH_PROXY"
echo "CHAIN: x14ad=1 x14afBalanceDiag=$MPCD_X14V_GLOBAL_BALANCE_DIAGNOSTIC x14aeLossDiag=0"
echo "VIS: enable=$LIVE_VIS_ENABLE every=$LIVE_VIS_EVERY recorderBackend=$FILTERED_RECORDING_ENABLE record=$RECORD_ENABLE recordEvery=$RECORD_EVERY"
echo "RUN: steps=$STEPS dt=$DT tEnd=$(awk -v n="$STEPS" -v d="$DT" 'BEGIN{print n*d}') summaryEvery=$SUMMARY_EVERY dumpEvery=$DUMP_STATE_EVERY"
echo "EXPECTATION: xCM must move downstream by gas drag; yCM should stay near Ly/2; We<0.1 keeps first test weakly deforming"

suite_run_binary_0434 "$PARAMS" "$LOG" "$TF" "$OUT"
if suite_truthy_0434 "$PREFLIGHT_ONLY"; then echo '[0493x14ag] PREFLIGHT_ONLY complete'; exit 0; fi
python3 "$ANALYZER" --run-root "$CAMPAIGN_ROOT" --liquid-type "$LIQUID_TYPE" --gas-type "$GAS_TYPE" --channel-center-y "$CENTER_Y" --gas-umean-nominal "$GAS_UMEAN" --radius "$RADIUS"
OUT_TAR="$CAMPAIGN_ROOT/0493x14ag_drop_gas_poiseuille_drag_compact.tar.gz"
FILES=(analysis output/cuda_ellipse_shape_0493x9f.csv output/species_runtime_0493x14ag.csv output/cuda_phase_interface_pressure_0493x6g.csv output/cuda_phase_interface_stencil_0493x6f.csv output/cuda_species_q6_independent_masked_0493w5.csv output/cuda_x14v_global_balance_0493x14af.csv logs/${CASE_LABEL}.log logs/${CASE_LABEL}.time logs/environment_0493x14ag.env params/${CASE_LABEL}.kv init/${CASE_LABEL}.smpcd.json)
PRESENT=(); for f in "${FILES[@]}"; do [[ -e "$CAMPAIGN_ROOT/$f" ]] && PRESENT+=("$f"); done
tar -czf "$OUT_TAR" -C "$CAMPAIGN_ROOT" "${PRESENT[@]}"
echo "[0493x14ag] return: $OUT_TAR"
