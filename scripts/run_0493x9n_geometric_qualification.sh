#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$ROOT/scripts/src_mpcd_run_common_0434.sh"
suite_root_cd_0434
 
CASE_LABEL="geometric_qualification_0493x9n"
RUN_MODE="${RUN_MODE:-src-q6-g-f}"; TOPOLOGY=closed_box
RUN_ROOT="${RUN_ROOT:-runs/0493x9n_geometric_qualification}"
NX="${NX:-320}"; NY="${NY:-200}"; Lx="${Lx:-1.6}"; Ly="${Ly:-1.0}"
GAMMA="${GAMMA:-20}"; DT="${DT:-0.002}"; KBT="${KBT:-0.125}"; STEPS="${STEPS:-1}"; SEED="${SEED:-493940}"
SIGMA="${SIGMA:-256.0}"
LIQUID_TYPE="${LIQUID_TYPE:-1}"; GAS_TYPE="${GAS_TYPE:-2}"; LIQUID_MASS="${LIQUID_MASS:-1.0}"; GAS_MASS="${GAS_MASS:-1.0}"
LIQUID_Q6_STRENGTH="${LIQUID_Q6_STRENGTH:-1.0}"; GAS_Q6_STRENGTH="${GAS_Q6_STRENGTH:-0.0}"
SPECIES_Q6_MIN_FILL_FRACTION="${SPECIES_Q6_MIN_FILL_FRACTION:-0.10}"
SUMMARY_EVERY="${SUMMARY_EVERY:-1}"; DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-0}"; PREFLIGHT_ONLY="${PREFLIGHT_ONLY:-0}"
LIVE_PROGRESS="${LIVE_PROGRESS:-1}"; LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-1}"; LIVE_VIS_HOLD_ON_EXIT="${LIVE_VIS_HOLD_ON_EXIT:-0}"; FILTERED_RECORDING_ENABLE="${FILTERED_RECORDING_ENABLE:-0}"
LIVE_VIS_FIELD="${LIVE_VIS_FIELD:-curvature_interface}"; LIVE_VIS_EVERY="${LIVE_VIS_EVERY:-1}"; PARTICLE_TYPE_FILTER="$LIQUID_TYPE"
LIVE_VIS_CONTROL_FILE="${LIVE_VIS_CONTROL_FILE:-./livevis_control.kv}"

THERMOSTAT_ENABLE="${THERMOSTAT_ENABLE:-true}"; THERMOSTAT_MODE=cell_relative_rescale; THERMOSTAT_EVERY=1; THERMOSTAT_TARGET_KBT="$KBT"; THERMOSTAT_MIN_PARTICLES=3
ROTATION_ANGLE="${ROTATION_ANGLE:-1.5707963267948966}"; RANDOM_ROTATION_SIGN=true; GRID_SHIFT_ENABLE=true
PROJECTION_BACKEND=cuda; PROJECTION_MAX_ITERATIONS="${PROJECTION_MAX_ITERATIONS:-800}"; PROJECTION_TOLERANCE="${PROJECTION_TOLERANCE:-1e-5}"; Q6_PROJECTION_STRENGTH=1.0; Q6_STRICT="${Q6_STRICT:-1}"
Q6_GF_EXTERNAL_SPECIES=1; Q6_GF_HAS_GAS_PHASE=1; Q6_GF_DENSITY_RELAXATION_TIME="${Q6_GF_DENSITY_RELAXATION_TIME:-0.25}"; Q6_GF_MIN_FILL_FRACTION="$SPECIES_Q6_MIN_FILL_FRACTION"
Q6_GF_DENSITY_COMPRESSION_GATE_ENABLE=1; Q6_GF_DENSITY_COMPRESSION_THRESHOLD_PARTICLES=3.0; Q6_GF_DENSITY_TRACTION_THRESHOLD_PARTICLES=6.0; Q6_GF_DENSITY_TRACTION_GAIN=1.0
SPECIES_RESAMPLING_ENABLE=false; LIQUID_RESAMPLING_ENABLE=false; GAS_RESAMPLING_ENABLE=false; VIRIAL_DENSITY_KICK_ENABLE=false; WEIGHTED_RESAMPLING_ENABLE_OVERRIDE=false; CUDA_EMPTY_REFILL_ENABLE_OVERRIDE=false
GEN_CASE=tg; U0=0.0; VELOCITY_MODE=zero; PARTICLE_MASS="$GAS_MASS"; BACKGROUND_TYPE="$GAS_TYPE"; INACTIVE_TYPE="$GAS_TYPE"; TG_HOLE_ENABLE=false
suite_defaults_common_0434; suite_compute_derived_0434

H="$(awk -v lx="$Lx" -v nx="$NX" 'BEGIN{printf "%.17g",lx/nx}')"
python3 - "$Lx" "$Ly" "$NX" "$NY" "$SIGMA" <<'PY'
import sys,math
lx,ly=map(float,sys.argv[1:3]); nx,ny=map(int,sys.argv[3:5]); sig=float(sys.argv[5])
if abs(lx/nx-ly/ny)>1e-12: raise SystemExit('[0493x9n] square cells required')
if not (sig>0 and math.isfinite(sig)): raise SystemExit('[0493x9n] sigma must be positive')
PY
python3 scripts/check_0493x9n_geometry.py
if suite_truthy_0434 "${CLEAN_RUN_ROOT:-1}"; then rm -rf "$RUN_ROOT"; fi
mkdir -p "$RUN_ROOT"
LIQUID_REFERENCE_CELL_MASS="$(awk -v g="$GAMMA" -v m="$LIQUID_MASS" 'BEGIN{printf "%.17g",g*m}')"
GAS_REFERENCE_CELL_MASS="$(awk -v g="$GAMMA" -v m="$GAS_MASS" 'BEGIN{printf "%.17g",g*m}')"

write_params(){
  local state="$1" dir="$2" theta="$3" params="$4"
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
speciesDiagnosticsFilename = species_runtime_0493x9n.csv
speciesCellDiagnosticsEnable = false
speciesQ6Enable = true
speciesQ6Mode = free_surface_masked
speciesQ6Sensitivity = 1.0
speciesQ6FallbackMode = common
speciesQ6ComparisonTolerance = 1e-11
speciesQ6MinOccupancyFraction = $SPECIES_Q6_MIN_FILL_FRACTION
PARAMS_EOF
  suite_write_common_params_0434 "$RUN_MODE" >> "$params"
}

run_case(){
  local case_id="$1" theta="$2"; shift 2
  local dir="$RUN_ROOT/$case_id"
  mkdir -p "$dir/init" "$dir/params" "$dir/output" "$dir/logs"
  local state="$dir/init/geometry_0493x9n.smpcd"
  local params="$dir/params/geometric_qualification_0493x9n.kv"
  local log="$dir/logs/geometric_qualification_0493x9n.log"
  local tf="$dir/logs/geometric_qualification_0493x9n.time"
  python3 scripts/generate_0493x9n_geometry_state.py \
    --output "$state" --case-id "$case_id" "$@" \
    --Lx "$Lx" --Ly "$Ly" --nx "$NX" --ny "$NY" --gamma "$GAMMA" \
    --contact-angle-deg "$theta" --liquid-type "$LIQUID_TYPE" --gas-type "$GAS_TYPE" \
    --liquid-mass "$LIQUID_MASS" --gas-mass "$GAS_MASS" --kBT "$KBT" --seed "$SEED"
  write_params "$state" "$dir" "$theta" "$params"
  suite_export_cuda_flags_0434 "$RUN_MODE" "$TOPOLOGY"
  export MPCD_Q6_STATIC_DROP_DIAGNOSTICS_0493X9E=1
  export MPCD_Q6_ELLIPSE_DIAGNOSTICS_0493X9F=0
  export MPCD_Q6_PHASE_CURVATURE_DIAGNOSTICS_0493X9A=0
  export MPCD_Q6_PHASE_CURVATURE_DIAGNOSTICS_0493X9B=0
  export MPCD_Q6_PHASE_CURVATURE_DIAGNOSTICS_0493X9C=0
  export MPCD_Q6_CONTACT_ANGLE_HARD_NORMAL_0493X9I=0
  export MPCD_Q6_CONTACT_ANGLE_WALL_FACE_0493X9L=0
  export MPCD_Q6_CONTACT_ANGLE_OFFSUPPORT_0493X9M=1
  BASE_RUN_ROOT="$dir"; LIVE_VIS_CONTROL_FILE="$dir/livevis_control_0493x9n.kv"; suite_prepare_livevis_control_0434 "$dir" "$RUN_MODE"; suite_export_livevis_0434
  echo "[0493x9n-suite] case=$case_id theta=$theta closure=x9m_offsupport sigma=$SIGMA"
  suite_run_binary_0434 "$params" "$log" "$tf" "$dir/output"
}

# A. Locally planar contact branches.  The remote horizontal cap is 20h away,
# safely outside the x9m anchor and p3+Scharr support.
PLANE_HALF_WIDTH="$(awk -v h="$H" 'BEGIN{printf "%.17g",90*h}')"
PLANE_HEIGHT="$(awk -v h="$H" 'BEGIN{printf "%.17g",20*h}')"
for theta in 30 45 60 90 120 135 150; do
  run_case "plane/theta${theta}" "$theta" \
    --shape plane-wedge --plane-half-width "$PLANE_HALF_WIDTH" --plane-height "$PLANE_HEIGHT"
done

# B. Circular curvature scaling over a factor four in R/h.
for rc in 20 40 80; do
  radius="$(awk -v h="$H" -v r="$rc" 'BEGIN{printf "%.17g",h*r}')"
  for theta in 60 90 120; do
    run_case "circle/r${rc}/theta${theta}" "$theta" --shape circle --radius "$radius"
  done
done

# C. Non-circular variable-curvature contacts.  Two moderate aspect ratios keep
# the exact x9m 4.5h secant-vs-local bias below 6%, leaving room for numerical error.
A_WIDE="$(awk -v h="$H" 'BEGIN{printf "%.17g",56*h}')"   # 0.28 at h=0.005
B_WIDE="$(awk -v h="$H" 'BEGIN{printf "%.17g",40*h}')"   # 0.20
A_TALL="$B_WIDE"
B_TALL="$A_WIDE"
for theta in 60 90 120; do
  run_case "ellipse/wide/theta${theta}" "$theta" --shape ellipse --semi-axis-x "$A_WIDE" --semi-axis-y "$B_WIDE"
  run_case "ellipse/tall/theta${theta}" "$theta" --shape ellipse --semi-axis-x "$A_TALL" --semi-axis-y "$B_TALL"
done

if ! suite_truthy_0434 "$PREFLIGHT_ONLY"; then
  python3 scripts/analyze_0493x9n_geometric_qualification.py --root "$RUN_ROOT"
fi
