#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$ROOT/scripts/src_mpcd_run_common_0434.sh"
suite_root_cd_0434

CASE_LABEL="contact_angle_ghost_0493x9j"
RUN_MODE="${RUN_MODE:-src-q6-g-f}"; TOPOLOGY=closed_box
RUN_ROOT="${RUN_ROOT:-runs/0493x9j_contact_angle_ghost}"
BASELINE_ROOT="${BASELINE_ROOT:-runs/0493x9i_contact_angle}"
ANGLES="${ANGLES:-60 90 120}"
NX="${NX:-320}"; NY="${NY:-200}"; Lx="${Lx:-1.6}"; Ly="${Ly:-1.0}"
GAMMA="${GAMMA:-20}"; DT="${DT:-0.002}"; KBT="${KBT:-0.125}"; STEPS="${STEPS:-1}"; SEED="${SEED:-493930}"
RADIUS_CELLS="${RADIUS_CELLS:-50}"; SIGMA="${SIGMA:-256.0}"
LIQUID_TYPE="${LIQUID_TYPE:-1}"; GAS_TYPE="${GAS_TYPE:-2}"; LIQUID_MASS="${LIQUID_MASS:-1.0}"; GAS_MASS="${GAS_MASS:-1.0}"
LIQUID_Q6_STRENGTH="${LIQUID_Q6_STRENGTH:-1.0}"; GAS_Q6_STRENGTH="${GAS_Q6_STRENGTH:-0.0}"
SPECIES_Q6_MIN_FILL_FRACTION="${SPECIES_Q6_MIN_FILL_FRACTION:-0.10}"
SUMMARY_EVERY="${SUMMARY_EVERY:-1}"; DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-0}"; PREFLIGHT_ONLY="${PREFLIGHT_ONLY:-0}"
LIVE_PROGRESS="${LIVE_PROGRESS:-1}"; LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-1}"; LIVE_VIS_HOLD_ON_EXIT="${LIVE_VIS_HOLD_ON_EXIT:-0}"; FILTERED_RECORDING_ENABLE="${FILTERED_RECORDING_ENABLE:-0}"
LIVE_VIS_FIELD="${LIVE_VIS_FIELD:-curvature_interface}"; LIVE_VIS_EVERY="${LIVE_VIS_EVERY:-1}"; PARTICLE_TYPE_FILTER="$LIQUID_TYPE"
THERMOSTAT_ENABLE="${THERMOSTAT_ENABLE:-true}"; THERMOSTAT_MODE=cell_relative_rescale; THERMOSTAT_EVERY=1; THERMOSTAT_TARGET_KBT="$KBT"; THERMOSTAT_MIN_PARTICLES=3
ROTATION_ANGLE="${ROTATION_ANGLE:-1.5707963267948966}"; RANDOM_ROTATION_SIGN=true; GRID_SHIFT_ENABLE=true
PROJECTION_BACKEND=cuda; PROJECTION_MAX_ITERATIONS="${PROJECTION_MAX_ITERATIONS:-800}"; PROJECTION_TOLERANCE="${PROJECTION_TOLERANCE:-1e-5}"; Q6_PROJECTION_STRENGTH=1.0; Q6_STRICT="${Q6_STRICT:-1}"
Q6_GF_EXTERNAL_SPECIES=1; Q6_GF_HAS_GAS_PHASE=1; Q6_GF_DENSITY_RELAXATION_TIME="${Q6_GF_DENSITY_RELAXATION_TIME:-0.25}"; Q6_GF_MIN_FILL_FRACTION="$SPECIES_Q6_MIN_FILL_FRACTION"
Q6_GF_DENSITY_COMPRESSION_GATE_ENABLE=1; Q6_GF_DENSITY_COMPRESSION_THRESHOLD_PARTICLES=3.0; Q6_GF_DENSITY_TRACTION_THRESHOLD_PARTICLES=6.0; Q6_GF_DENSITY_TRACTION_GAIN=1.0
SPECIES_RESAMPLING_ENABLE=false; LIQUID_RESAMPLING_ENABLE=false; GAS_RESAMPLING_ENABLE=false; VIRIAL_DENSITY_KICK_ENABLE=false; WEIGHTED_RESAMPLING_ENABLE_OVERRIDE=false; CUDA_EMPTY_REFILL_ENABLE_OVERRIDE=false
GEN_CASE=tg; U0=0.0; VELOCITY_MODE=zero; PARTICLE_MASS="$GAS_MASS"; BACKGROUND_TYPE="$GAS_TYPE"; INACTIVE_TYPE="$GAS_TYPE"; TG_HOLE_ENABLE=false
suite_defaults_common_0434; suite_compute_derived_0434

RADIUS="$(awk -v lx="$Lx" -v nx="$NX" -v rc="$RADIUS_CELLS" 'BEGIN{printf "%.17g",lx/nx*rc}')"
python3 - "$Lx" "$Ly" "$NX" "$NY" "$RADIUS" "$SIGMA" <<'PY'
import sys
lx,ly=map(float,sys.argv[1:3]); nx,ny=map(int,sys.argv[3:5]); r,s=map(float,sys.argv[5:7])
if abs(lx/nx-ly/ny)>1e-12: raise SystemExit('[0493x9j] square cells required')
if not (r>0 and s>0): raise SystemExit('[0493x9j] radius and sigma must be positive')
PY
if suite_truthy_0434 "${CLEAN_RUN_ROOT:-1}"; then rm -rf "$RUN_ROOT"; fi
mkdir -p "$RUN_ROOT"
LIQUID_REFERENCE_CELL_MASS="$(awk -v g="$GAMMA" -v m="$LIQUID_MASS" 'BEGIN{printf "%.17g",g*m}')"
GAS_REFERENCE_CELL_MASS="$(awk -v g="$GAMMA" -v m="$GAS_MASS" 'BEGIN{printf "%.17g",g*m}')"

run_one(){
  local theta="$1" dir="$RUN_ROOT/theta${1//./p}"
  mkdir -p "$dir/init" "$dir/params" "$dir/output" "$dir/logs"
  local state="$dir/init/sessile_cap_0493x9j.smpcd" params="$dir/params/contact_angle_ghost_0493x9j.kv" log="$dir/logs/contact_angle_ghost_0493x9j.log" tf="$dir/logs/contact_angle_ghost_0493x9j.time"
  python3 scripts/generate_0493x9i_sessile_cap_state.py --output "$state" --Lx "$Lx" --Ly "$Ly" --nx "$NX" --ny "$NY" --gamma "$GAMMA" --radius "$RADIUS" --contact-angle-deg "$theta" --liquid-type "$LIQUID_TYPE" --gas-type "$GAS_TYPE" --liquid-mass "$LIQUID_MASS" --gas-mass "$GAS_MASS" --kBT "$KBT" --seed "$SEED"
  cat > "$params" <<PARAMS_EOF
inputState = $state
outputDir = $dir/output
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
surfaceTensionSigma = $SIGMA
phaseInterfaceASelector = type:$LIQUID_TYPE
phaseInterfaceBSelector = type:$GAS_TYPE
phaseInterfaceContactAngleDegrees = $theta
speciesRegistryEnable = true
speciesCount = 2
species0 = $LIQUID_TYPE incompressible_liquid liquid $LIQUID_Q6_STRENGTH 1.0 $LIQUID_REFERENCE_CELL_MASS
species0ResamplingEnable = false
species1 = $GAS_TYPE compressible_gas gas $GAS_Q6_STRENGTH 0.0 $GAS_REFERENCE_CELL_MASS
species1ResamplingEnable = false
speciesRequireRegisteredTypes = true
speciesDiagnosticsEnable = true
speciesDiagnosticsFilename = species_runtime_0493x9j.csv
speciesCellDiagnosticsEnable = false
speciesQ6Enable = true
speciesQ6Mode = free_surface_masked
speciesQ6Sensitivity = 1.0
speciesQ6FallbackMode = common
speciesQ6ComparisonTolerance = 1e-11
speciesQ6MinOccupancyFraction = $SPECIES_Q6_MIN_FILL_FRACTION
PARAMS_EOF
  suite_write_common_params_0434 "$RUN_MODE" >> "$params"
  suite_export_cuda_flags_0434 "$RUN_MODE" "$TOPOLOGY"
  export MPCD_Q6_STATIC_DROP_DIAGNOSTICS_0493X9E=1
  export MPCD_Q6_ELLIPSE_DIAGNOSTICS_0493X9F=0
  export MPCD_Q6_PHASE_CURVATURE_DIAGNOSTICS_0493X9A=0
  export MPCD_Q6_PHASE_CURVATURE_DIAGNOSTICS_0493X9B=0
  export MPCD_Q6_PHASE_CURVATURE_DIAGNOSTICS_0493X9C=0
  export MPCD_Q6_CONTACT_ANGLE_HARD_NORMAL_0493X9I=0
  BASE_RUN_ROOT="$dir"; LIVE_VIS_CONTROL_FILE="$dir/livevis_control_0493x9j.kv"; suite_prepare_livevis_control_0434 "$dir" "$RUN_MODE"; suite_export_livevis_0434
  echo "[0493x9j-suite] theta=$theta radius=$RADIUS exactKappa=$(awk -v r="$RADIUS" 'BEGIN{printf "%.8g",1/r}') sigma=$SIGMA closure=ghost_alpha"
  suite_run_binary_0434 "$params" "$log" "$tf" "$dir/output"
}
read -r -a ANGLE_LIST <<< "$ANGLES"
for a in "${ANGLE_LIST[@]}"; do run_one "$a"; done
if ! suite_truthy_0434 "$PREFLIGHT_ONLY"; then
  python3 scripts/analyze_0493x9j_contact_angle_ghost.py --root "$RUN_ROOT" --angles "${ANGLE_LIST[@]}" --radius "$RADIUS" --baseline-root "$BASELINE_ROOT"
fi
