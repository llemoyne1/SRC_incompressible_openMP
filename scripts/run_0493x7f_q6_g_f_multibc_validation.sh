#!/usr/bin/env bash
set -uo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$ROOT/scripts/src_mpcd_run_common_0434.sh"
suite_root_cd_0434

CASE_LABEL="q6_g_f_multibc_0493x7f"
RUN_MODE="src-q6"
RUN_ROOT="${RUN_ROOT:-runs/0493x7f_q6_g_f_multibc}"
CASES="${CASES:-periodic_zero_force channel_wall_zero_force closed_box_zero_force closed_box_gravity io_fullface_x io_fullface_y io_segmented_lr io_segmented_sameface}"
NX="${NX:-32}"
NY="${NY:-24}"
GAMMA="${GAMMA:-8}"
STEPS="${STEPS:-5}"
DT="${DT:-0.005}"
KBT="${KBT:-0.02}"
SEED="${SEED:-493970}"
LIQUID_TYPE="${LIQUID_TYPE:-1}"
GAS_TYPE="${GAS_TYPE:-2}"
LIQUID_MASS="${LIQUID_MASS:-100.0}"
GAS_MASS="${GAS_MASS:-1.0}"
UIN="${UIN:-0.005}"
GRAVITY_Y="${GRAVITY_Y:--0.1}"
DENSITY_RELAXATION_TIME="${DENSITY_RELAXATION_TIME:-0.25}"
SPECIES_Q6_MIN_FILL_FRACTION="${SPECIES_Q6_MIN_FILL_FRACTION:-0.10}"
SUMMARY_EVERY="${SUMMARY_EVERY:-1}"
DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-0}"
INACTIVE_SLOTS="${INACTIVE_SLOTS:-4096}"
PREFLIGHT_ONLY="${PREFLIGHT_ONLY:-0}"
LIVE_PROGRESS="${LIVE_PROGRESS:-1}"

PROJECTION_BACKEND="cuda"
PROJECTION_OPERATOR="auto_fv_cg"
PROJECTION_MAX_ITERATIONS="${PROJECTION_MAX_ITERATIONS:-1600}"
PROJECTION_TOLERANCE="${PROJECTION_TOLERANCE:-1e-7}"
PROJECTION_MOMENTUM_CORRECTION_ENABLE="false"
Q6_PROJECTION_STRENGTH="1.0"
WEIGHTED_RESAMPLING_ENABLE_OVERRIDE="false"
CUDA_EMPTY_REFILL_ENABLE_OVERRIDE="false"
SPECIES_RESAMPLING_ENABLE="false"
THERMOSTAT_ENABLE="false"
THERMOSTAT_MODE="cell_relative_rescale"
THERMOSTAT_EVERY="1"
THERMOSTAT_TARGET_KBT="$KBT"
THERMOSTAT_MIN_PARTICLES="3"
ROTATION_ANGLE="${ROTATION_ANGLE:-1.5}"
RANDOM_ROTATION_SIGN="true"
GRID_SHIFT_ENABLE="true"
THREADS="${THREADS:-8}"
LIVE_VIS_ENABLE=0
FILTERED_RECORDING_ENABLE=0
RECORD_ENABLE=false

suite_defaults_common_0434
suite_compute_derived_0434

if (( NX < 8 || NY < 8 || GAMMA < 2 || STEPS < 1 )); then
  echo "[0493x7f] ERROR require NX>=8 NY>=8 GAMMA>=2 STEPS>=1" >&2
  exit 2
fi

if suite_truthy_0434 "${CLEAN_RUN_ROOT:-1}"; then
  rm -rf "$RUN_ROOT"
fi
mkdir -p "$RUN_ROOT/init" "$RUN_ROOT/logs"

if ! suite_truthy_0434 "$PREFLIGHT_ONLY"; then
  suite_ensure_binary_0434
  # x7f-fix1: the common environment writer records LIVE_VIS_CONTROL_FILE even
  # when live visualization is disabled.  Initialize the canonical 0434
  # livevis environment once for the whole qualification matrix so set -u
  # cannot observe an unset control-file variable.  LIVE_VIS_ENABLE=0 keeps
  # this strictly diagnostic/runtime plumbing; no visualization is launched.
  suite_prepare_livevis_control_0434 "$RUN_ROOT" "$RUN_MODE"
  suite_export_livevis_0434
fi

# Horizontal free surface: liquid fills the lower half and reaches both x faces.
STATE_H="$RUN_ROOT/init/q6_g_f_horizontal_interface_0493x7f.smpcd"
python3 scripts/generate_0493x0_dam_break_state.py \
  --output "$STATE_H" --Lx 1.0 --Ly 1.0 --nx "$NX" --ny "$NY" --gamma "$GAMMA" \
  --column-width 0.999999 --column-height 0.5 \
  --liquid-type "$LIQUID_TYPE" --gas-type "$GAS_TYPE" \
  --liquid-mass "$LIQUID_MASS" --gas-mass "$GAS_MASS" \
  --kBT "$KBT" --seed "$SEED"

# Vertical free surface: liquid fills the left half and reaches both y faces.
STATE_V="$RUN_ROOT/init/q6_g_f_vertical_interface_0493x7f.smpcd"
python3 scripts/generate_0493x0_dam_break_state.py \
  --output "$STATE_V" --Lx 1.0 --Ly 1.0 --nx "$NX" --ny "$NY" --gamma "$GAMMA" \
  --column-width 0.5 --column-height 0.999999 \
  --liquid-type "$LIQUID_TYPE" --gas-type "$GAS_TYPE" \
  --liquid-mass "$LIQUID_MASS" --gas-mass "$GAS_MASS" \
  --kBT "$KBT" --seed "$((SEED + 1))"

LIQUID_REFERENCE_CELL_MASS="$(awk -v g="$GAMMA" -v m="$LIQUID_MASS" 'BEGIN{printf "%.17g",g*m}')"
GAS_REFERENCE_CELL_MASS="$(awk -v g="$GAMMA" -v m="$GAS_MASS" 'BEGIN{printf "%.17g",g*m}')"
CELL_AREA="$(awk -v nx="$NX" -v ny="$NY" 'BEGIN{printf "%.17g",(1.0/nx)*(1.0/ny)}')"
GAS_PRESSURE_REFERENCE="$(awk -v g="$GAMMA" -v t="$KBT" -v a="$CELL_AREA" 'BEGIN{printf "%.17g",g*t/a}')"

contains_case() {
  local wanted="$1" item
  for item in $CASES; do
    [[ "$item" == "$wanted" ]] && return 0
  done
  return 1
}

write_base_params() {
  local case_name="$1" state="$2" body_ay="$3"
  local case_dir="$RUN_ROOT/$case_name"
  local params="$case_dir/params/q6_g_f_multibc_0493x7f.kv"
  mkdir -p "$case_dir/params" "$case_dir/output" "$case_dir/logs"

  cat > "$params" <<PARAMS
inputState = $state
outputDir = $case_dir/output
Lx = 1.0
Ly = 1.0
Nx = $NX
Ny = $NY
dt = $DT
nSteps = $STEPS
bodyAccelerationX = 0.0
bodyAccelerationY = $body_ay
q6ForceProjectionMode = prestream_single_fused
virialDensityKickEnable = false
kVirial = 0.0
betaEOS = 0.0
virialMomentumCorrectionEnable = false
q6DensityRelaxationBeta = 0.0
q6DensityRelaxationTime = $DENSITY_RELAXATION_TIME
keepMeanFlowEnable = false
wallVpEnable = false
wallAccommodation = 1.0
wallVpGamma = $GAMMA
wallVpMass = $LIQUID_MASS
wallKBT = -1.0
wallThermalNoise = 0.0
darcyBrinkmanEnable = false
speciesRegistryEnable = true
speciesCount = 2
species0 = $LIQUID_TYPE incompressible_liquid liquid 1.0 1.0 $LIQUID_REFERENCE_CELL_MASS
species0ResamplingEnable = false
species1 = $GAS_TYPE compressible_gas gas 0.0 0.0 $GAS_REFERENCE_CELL_MASS
species1ResamplingEnable = false
speciesRequireRegisteredTypes = true
speciesDiagnosticsEnable = true
speciesDiagnosticsFilename = species_runtime_0493x7f.csv
speciesCellDiagnosticsEnable = false
speciesQ6Enable = true
speciesQ6Mode = free_surface_masked
speciesQ6Sensitivity = 1.0
speciesQ6FallbackMode = common
speciesQ6ComparisonTolerance = 1.0e-11
speciesQ6MinOccupancyFraction = $SPECIES_Q6_MIN_FILL_FRACTION
PARAMS
  suite_write_common_params_0434 "$RUN_MODE" >> "$params"
}

write_case_params() {
  local case_name="$1"
  local state="$STATE_H" body_ay="0.0"
  [[ "$case_name" == "io_fullface_y" ]] && state="$STATE_V"
  [[ "$case_name" == "closed_box_gravity" ]] && body_ay="$GRAVITY_Y"
  write_base_params "$case_name" "$state" "$body_ay"
  local params="$RUN_ROOT/$case_name/params/q6_g_f_multibc_0493x7f.kv"

  case "$case_name" in
    periodic_zero_force)
      cat >> "$params" <<'PARAMS'
bcLeft = periodic
bcRight = periodic
bcBottom = periodic
bcTop = periodic
bcX = periodic
bcY = periodic
openBoundarySegmentsEnable = false
openBoundarySegmentCount = 0
PARAMS
      ;;
    channel_wall_zero_force)
      cat >> "$params" <<'PARAMS'
bcLeft = periodic
bcRight = periodic
bcBottom = solid
bcTop = specular
bcX = periodic
bcY = wall
openBoundarySegmentsEnable = false
openBoundarySegmentCount = 0
PARAMS
      ;;
    closed_box_zero_force|closed_box_gravity)
      cat >> "$params" <<'PARAMS'
bcLeft = specular
bcRight = specular
bcBottom = solid
bcTop = specular
bcX = wall
bcY = wall
openBoundarySegmentsEnable = false
openBoundarySegmentCount = 0
PARAMS
      ;;
    io_fullface_x)
      cat >> "$params" <<PARAMS
bcLeft = inlet
bcRight = outlet
bcBottom = solid
bcTop = solid
bcX = open
bcY = wall
openBoundarySegmentsEnable = false
openBoundarySegmentCount = 0
inletUxLeft = $UIN
inletUyLeft = 0.0
inletReservoirMode = hard_cell_density
inletInjectionMode = hard_cell_density
inletReservoirCells = 1
inletTargetOccupancy = $GAMMA
inletVelocitySpatialProfile = uniform
inletThermalNoise = 0.0
inletKBT = -1.0
openBoundaryOutletMode = balanced_flux
PARAMS
      ;;
    io_fullface_y)
      cat >> "$params" <<PARAMS
bcLeft = solid
bcRight = solid
bcBottom = inlet
bcTop = outlet
bcX = wall
bcY = open
openBoundarySegmentsEnable = false
openBoundarySegmentCount = 0
inletUxBottom = 0.0
inletUyBottom = $UIN
inletReservoirMode = hard_cell_density
inletInjectionMode = hard_cell_density
inletReservoirCells = 1
inletTargetOccupancy = $GAMMA
inletVelocitySpatialProfile = uniform
inletThermalNoise = 0.0
inletKBT = -1.0
openBoundaryOutletMode = balanced_flux
PARAMS
      ;;
    io_segmented_lr)
      cat >> "$params" <<PARAMS
bcLeft = solid
bcRight = solid
bcBottom = solid
bcTop = solid
bcX = wall
bcY = wall
openBoundarySegmentsEnable = true
openBoundarySegmentCount = 2
openBoundarySegment0 = left inlet 0.10 0.40 $UIN 0.0 $LIQUID_TYPE $LIQUID_MASS
openBoundarySegment1 = right outlet 0.10 0.40 $UIN 0.0 $LIQUID_TYPE $LIQUID_MASS
inletReservoirMode = hard_cell_density
inletInjectionMode = hard_cell_density
inletReservoirCells = 1
inletTargetOccupancy = $GAMMA
inletVelocitySpatialProfile = uniform
inletThermalNoise = 0.0
inletKBT = -1.0
openBoundaryOutletMode = hybrid
openBoundaryOutletHybridBlend = 0.0
openBoundaryOutletFeedbackGain = 0.0
PARAMS
      ;;
    io_segmented_sameface)
      cat >> "$params" <<PARAMS
bcLeft = solid
bcRight = solid
bcBottom = solid
bcTop = solid
bcX = wall
bcY = wall
openBoundarySegmentsEnable = true
openBoundarySegmentCount = 2
openBoundarySegment0 = left inlet 0.08 0.23 $UIN 0.0 $LIQUID_TYPE $LIQUID_MASS
openBoundarySegment1 = left outlet 0.30 0.45 -$UIN 0.0 $LIQUID_TYPE $LIQUID_MASS
inletReservoirMode = hard_cell_density
inletInjectionMode = hard_cell_density
inletReservoirCells = 1
inletTargetOccupancy = $GAMMA
inletVelocitySpatialProfile = uniform
inletThermalNoise = 0.0
inletKBT = -1.0
openBoundaryOutletMode = hybrid
openBoundaryOutletHybridBlend = 0.0
openBoundaryOutletFeedbackGain = 0.0
PARAMS
      ;;
    *)
      echo "[0493x7f] ERROR unknown case=$case_name" >&2
      return 2
      ;;
  esac
}

case_metadata() {
  case "$1" in
    periodic_zero_force) echo "periodic,periodic,0,1" ;;
    channel_wall_zero_force) echo "wall,channel_wall,0,1" ;;
    closed_box_zero_force) echo "closed_box,closed_box,0,1" ;;
    closed_box_gravity) echo "closed_box,closed_box,0,0" ;;
    io_fullface_x|io_fullface_y) echo "io_fullface,open_fullface,1,1" ;;
    io_segmented_lr|io_segmented_sameface) echo "segmented,open_segmented,1,1" ;;
    *) return 2 ;;
  esac
}

configure_q6_g_f_env() {
  local topology="$1"
  suite_export_cuda_flags_0434 "$RUN_MODE" "$topology"
  export MPCD_Q6_PHASE_GEOMETRY_RESIDENT_0493X6C=1
  export MPCD_Q6_PHASE_GEOMETRY_CUTFACE_0493X6D=0
  export MPCD_Q6_PHASE_INTERFACE_TOPOLOGY_0493X6E=1
  export MPCD_Q6_PHASE_INTERFACE_STENCIL_0493X6F=1
  export MPCD_Q6_PHASE_GAS_PRESSURE_0493X6G=1
  export MPCD_Q6_PHASE_GAS_PRESSURE_MODE_0493X6G=eos
  export MPCD_Q6_PHASE_GAS_PRESSURE_REFERENCE_0493X6G="$GAS_PRESSURE_REFERENCE"
  export MPCD_Q6_PHASE_GAS_PRESSURE_CONSTANT_0493X6G="$GAS_PRESSURE_REFERENCE"
  export MPCD_Q6_PHASE_GAS_PRESSURE_SCALE_0493X6G=1
  export MPCD_Q6_PHASE_PRESSURE_DIAGNOSTICS_0493X6A=0
  export MPCD_Q6_PHASE_GEOMETRY_DIAGNOSTICS_0493X6B=0
  export MPCD_Q6_POSTAPPLY_REGION_DIAGNOSTICS_0493X6H_B0=0
  export MPCD_Q6_FACE_TO_PARTICLE_RT0_0493X6H_B1=1
  export SRC_LIVE_VIS_ENABLE=0
  export MPCD_LIVE_VIS_ENABLE=0
  export LIVE_PROGRESS
}

printf '%s\n' \
  "[0493x7f] Q6-g-f resident static multi-BC qualification" \
  "[0493x7f] grid=${NX}x${NY} gamma=$GAMMA steps=$STEPS dt=$DT tau=$DENSITY_RELAXATION_TIME" \
  "[0493x7f] x6g EOS pRef=$GAS_PRESSURE_REFERENCE B1=on virial=off resampling=off Darcy=off" \
  "[0493x7f] cases=$CASES"

echo "case,exit_code,expected_boundary_family,expected_open,zero_body_force,topology" > "$RUN_ROOT/launch_status_0493x7f.csv"

for case_name in $CASES; do
  meta="$(case_metadata "$case_name")" || { echo "[0493x7f] ERROR invalid case=$case_name" >&2; exit 2; }
  IFS=',' read -r topology family open zero_force <<< "$meta"
  write_case_params "$case_name" || exit $?
  params="$RUN_ROOT/$case_name/params/q6_g_f_multibc_0493x7f.kv"
  log="$RUN_ROOT/$case_name/logs/q6_g_f_multibc_0493x7f.log"

  if suite_truthy_0434 "$PREFLIGHT_ONLY"; then
    echo "[0493x7f] preflight case=$case_name topology=$topology family=$family params=$params"
    echo "$case_name,SKIP,$family,$open,$zero_force,$topology" >> "$RUN_ROOT/launch_status_0493x7f.csv"
    continue
  fi

  configure_q6_g_f_env "$topology"
  suite_write_env_file_0434 "$RUN_ROOT/$case_name/logs/environment_0493x7f.env" "$RUN_MODE"
  cat >> "$RUN_ROOT/$case_name/logs/environment_0493x7f.env" <<META
MPCD_Q6_PHASE_GEOMETRY_RESIDENT_0493X6C=1
MPCD_Q6_PHASE_INTERFACE_STENCIL_0493X6F=1
MPCD_Q6_PHASE_GAS_PRESSURE_0493X6G=1
MPCD_Q6_PHASE_GAS_PRESSURE_MODE_0493X6G=eos
MPCD_Q6_PHASE_GAS_PRESSURE_REFERENCE_0493X6G=$GAS_PRESSURE_REFERENCE
MPCD_Q6_PHASE_GAS_PRESSURE_SCALE_0493X6G=1
MPCD_Q6_FACE_TO_PARTICLE_RT0_0493X6H_B1=1
Q6_DENSITY_RELAXATION_TIME=$DENSITY_RELAXATION_TIME
META

  echo
  echo "============================================================"
  echo "[0493x7f] case=$case_name topology=$topology expectedFamily=$family zeroBodyForce=$zero_force"
  echo "============================================================"
  set +e
  /usr/bin/time -p "$BIN" "$params" > "$log" 2>&1
  rc=$?
  set -e
  echo "$case_name,$rc,$family,$open,$zero_force,$topology" >> "$RUN_ROOT/launch_status_0493x7f.csv"
  tail -n 8 "$log" || true
done

if suite_truthy_0434 "$PREFLIGHT_ONLY"; then
  echo "[0493x7f] preflight complete; no simulation launched"
else
  python3 scripts/check_0493x7f_q6_g_f_multibc.py \
    --root "$RUN_ROOT" --expected-steps "$STEPS" \
    --tau "$DENSITY_RELAXATION_TIME" --dt "$DT" \
    --liquid-type "$LIQUID_TYPE" --gas-type "$GAS_TYPE"
fi
