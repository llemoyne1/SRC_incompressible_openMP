#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$ROOT/scripts/src_mpcd_run_common_0434.sh"
suite_root_cd_0434

CASE_LABEL="sessile_dynamics_0493x9p"
RUN_MODE="${RUN_MODE:-src-q6-g-f}"; TOPOLOGY=closed_box
RUN_ROOT="${RUN_ROOT:-runs/0493x9p_sessile_dynamics}"
CASES="${CASES:-hold60:60:60:active hold90:90:90:active hold120:120:120:active wet90to60:90:60:active dewet90to120:90:120:active control90:90:-1:control}"
NX="${NX:-320}"; NY="${NY:-200}"; Lx="${Lx:-1.6}"; Ly="${Ly:-1.0}"
GAMMA="${GAMMA:-20}"; DT="${DT:-0.002}"; KBT="${KBT:-0.125}"; STEPS="${STEPS:-2000}"; SEED="${SEED:-493930}"
RADIUS_CELLS="${RADIUS_CELLS:-50}"; SIGMA_ACTIVE="${SIGMA_ACTIVE:-5120.0}"
LIQUID_TYPE="${LIQUID_TYPE:-1}"; GAS_TYPE="${GAS_TYPE:-2}"; LIQUID_MASS="${LIQUID_MASS:-1.0}"; GAS_MASS="${GAS_MASS:-1.0}"
LIQUID_Q6_STRENGTH="${LIQUID_Q6_STRENGTH:-1.0}"; GAS_Q6_STRENGTH="${GAS_Q6_STRENGTH:-0.0}"; SPECIES_Q6_MIN_FILL_FRACTION="${SPECIES_Q6_MIN_FILL_FRACTION:-0.10}"
SUMMARY_EVERY="${SUMMARY_EVERY:-20}"; DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-0}"; PREFLIGHT_ONLY="${PREFLIGHT_ONLY:-0}"
LIVE_PROGRESS="${LIVE_PROGRESS:-1}"; LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-1}"; LIVE_VIS_HOLD_ON_EXIT="${LIVE_VIS_HOLD_ON_EXIT:-0}"; FILTERED_RECORDING_ENABLE="${FILTERED_RECORDING_ENABLE:-0}"
LIVE_VIS_FIELD="${LIVE_VIS_FIELD:-curvature_interface}"; LIVE_VIS_EVERY="${LIVE_VIS_EVERY:-20}"; LIVE_VIS_COLORMAP="${LIVE_VIS_COLORMAP:-blue_red}"; LIVE_VIS_CLIP="${LIVE_VIS_CLIP:-20.0}"; PARTICLE_TYPE_FILTER="$LIQUID_TYPE"
THERMOSTAT_ENABLE="${THERMOSTAT_ENABLE:-true}"; THERMOSTAT_MODE=cell_relative_rescale; THERMOSTAT_EVERY=1; THERMOSTAT_TARGET_KBT="$KBT"; THERMOSTAT_MIN_PARTICLES=3
ROTATION_ANGLE="${ROTATION_ANGLE:-1.5707963267948966}"; RANDOM_ROTATION_SIGN=true; GRID_SHIFT_ENABLE=true
PROJECTION_BACKEND=cuda; PROJECTION_MAX_ITERATIONS="${PROJECTION_MAX_ITERATIONS:-800}"; PROJECTION_TOLERANCE="${PROJECTION_TOLERANCE:-1e-5}"; Q6_PROJECTION_STRENGTH=1.0; Q6_STRICT="${Q6_STRICT:-1}"
Q6_GF_EXTERNAL_SPECIES=1; Q6_GF_HAS_GAS_PHASE=1; Q6_GF_DENSITY_RELAXATION_TIME="${Q6_GF_DENSITY_RELAXATION_TIME:-0.25}"; Q6_GF_MIN_FILL_FRACTION="$SPECIES_Q6_MIN_FILL_FRACTION"
Q6_GF_DENSITY_COMPRESSION_GATE_ENABLE=1; Q6_GF_DENSITY_COMPRESSION_THRESHOLD_PARTICLES=3.0; Q6_GF_DENSITY_TRACTION_THRESHOLD_PARTICLES=6.0; Q6_GF_DENSITY_TRACTION_GAIN=1.0
SPECIES_RESAMPLING_ENABLE=false; LIQUID_RESAMPLING_ENABLE=false; GAS_RESAMPLING_ENABLE=false; VIRIAL_DENSITY_KICK_ENABLE=false; WEIGHTED_RESAMPLING_ENABLE_OVERRIDE=false; CUDA_EMPTY_REFILL_ENABLE_OVERRIDE=false
GEN_CASE=tg; U0=0.0; VELOCITY_MODE=zero; PARTICLE_MASS="$GAS_MASS"; BACKGROUND_TYPE="$GAS_TYPE"; INACTIVE_TYPE="$GAS_TYPE"; TG_HOLE_ENABLE=false
suite_defaults_common_0434; suite_compute_derived_0434

RADIUS="$(awk -v lx="$Lx" -v nx="$NX" -v rc="$RADIUS_CELLS" 'BEGIN{printf "%.17g",lx/nx*rc}')"
python3 - "$Lx" "$Ly" "$NX" "$NY" "$RADIUS" "$SIGMA_ACTIVE" "$STEPS" <<'PY'
import math,sys
lx,ly=map(float,sys.argv[1:3]); nx,ny=map(int,sys.argv[3:5]); r,s,steps=float(sys.argv[5]),float(sys.argv[6]),int(sys.argv[7])
if abs(lx/nx-ly/ny)>1e-12: raise SystemExit('[0493x9p] square cells required')
if not (r>0 and s>0 and steps>0): raise SystemExit('[0493x9p] radius, active sigma and steps must be positive')
PY
python3 scripts/check_0493x9p_cap_geometry.py
if suite_truthy_0434 "${CLEAN_RUN_ROOT:-1}"; then rm -rf "$RUN_ROOT"; fi
mkdir -p "$RUN_ROOT/shared_init" "$RUN_ROOT/logs"
LIQUID_REFERENCE_CELL_MASS="$(awk -v g="$GAMMA" -v m="$LIQUID_MASS" 'BEGIN{printf "%.17g",g*m}')"
GAS_REFERENCE_CELL_MASS="$(awk -v g="$GAMMA" -v m="$GAS_MASS" 'BEGIN{printf "%.17g",g*m}')"

# Shared deterministic initial states.  The three 90-degree cases consume the
# exact same file, making the active wetting/dewetting runs paired to sigma=0.
for theta in 60 90 120; do
  d="$RUN_ROOT/shared_init/theta$theta"; mkdir -p "$d"
  state="$d/sessile_cap_theta${theta}_0493x9p.smpcd"
  python3 scripts/generate_0493x9i_sessile_cap_state.py --output "$state" --Lx "$Lx" --Ly "$Ly" --nx "$NX" --ny "$NY" --gamma "$GAMMA" --radius "$RADIUS" --contact-angle-deg "$theta" --liquid-type "$LIQUID_TYPE" --gas-type "$GAS_TYPE" --liquid-mass "$LIQUID_MASS" --gas-mass "$GAS_MASS" --kBT "$KBT" --seed "$SEED"
done
sha256sum "$RUN_ROOT/shared_init/theta90/sessile_cap_theta90_0493x9p.smpcd" | sed 's/^/[0493x9p-init] theta90 sha256=/'

MANIFEST="$RUN_ROOT/case_manifest_0493x9p.csv"
echo 'case,initAngle,targetAngle,sigma,contactActive,state' > "$MANIFEST"

run_one(){
  local name="$1" init_theta="$2" target_theta="$3" kind="$4"
  local sigma contact_active contact_param
  if [[ "$kind" == active ]]; then sigma="$SIGMA_ACTIVE"; contact_active=1; contact_param="$target_theta"; else sigma=0.0; contact_active=0; contact_param=-1.0; fi
  local dir="$RUN_ROOT/$name"; mkdir -p "$dir/params" "$dir/output" "$dir/logs"
  local state="$RUN_ROOT/shared_init/theta${init_theta}/sessile_cap_theta${init_theta}_0493x9p.smpcd"
  local params="$dir/params/${CASE_LABEL}.kv" log="$dir/logs/${CASE_LABEL}.log" tf="$dir/logs/${CASE_LABEL}.time"
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
surfaceTensionSigma = $sigma
phaseInterfaceASelector = type:$LIQUID_TYPE
phaseInterfaceBSelector = type:$GAS_TYPE
phaseInterfaceContactAngleDegrees = $contact_param
speciesRegistryEnable = true
speciesCount = 2
species0 = $LIQUID_TYPE incompressible_liquid liquid $LIQUID_Q6_STRENGTH 1.0 $LIQUID_REFERENCE_CELL_MASS
species0ResamplingEnable = false
species1 = $GAS_TYPE compressible_gas gas $GAS_Q6_STRENGTH 0.0 $GAS_REFERENCE_CELL_MASS
species1ResamplingEnable = false
speciesRequireRegisteredTypes = true
speciesDiagnosticsEnable = true
speciesDiagnosticsFilename = species_runtime_0493x9p.csv
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
  export MPCD_Q6_ELLIPSE_DIAGNOSTICS_0493X9F=1
  export MPCD_Q6_PHASE_CURVATURE_DIAGNOSTICS_0493X9A=0
  if [[ "$contact_active" == 1 ]]; then
    export MPCD_Q6_PHASE_CURVATURE_DIAGNOSTICS_0493X9B=0
    export MPCD_Q6_PHASE_CURVATURE_DIAGNOSTICS_0493X9C=0
    export MPCD_Q6_CONTACT_ANGLE_OFFSUPPORT_0493X9M=1
  else
    # sigma=0/contact-off is the strict no-capillary paired control.  Passive
    # p3 is retained only so LiveVis/x9e/x9f geometry diagnostics remain valid.
    export MPCD_Q6_PHASE_CURVATURE_DIAGNOSTICS_0493X9B=1
    export MPCD_Q6_PHASE_CURVATURE_DIAGNOSTICS_0493X9C=1
    export MPCD_Q6_CONTACT_ANGLE_OFFSUPPORT_0493X9M=0
  fi
  export MPCD_Q6_CONTACT_ANGLE_HARD_NORMAL_0493X9I=0
  export MPCD_Q6_CONTACT_ANGLE_WALL_FACE_0493X9L=0
  BASE_RUN_ROOT="$dir"; LIVE_VIS_CONTROL_FILE="$dir/livevis_control_0493x9p.kv"; suite_prepare_livevis_control_0434 "$dir" "$RUN_MODE"; suite_export_livevis_0434
  suite_write_env_file_0434 "$dir/logs/environment_0493x9p.env" "$RUN_MODE"
  printf '%s\n' "[0493x9p-suite] case=$name initTheta=$init_theta targetTheta=$target_theta contactActive=$contact_active sigma=$sigma R0=$RADIUS steps=$STEPS dt=$DT" \
    "[0493x9p-suite] physical-angle observables = particle COM + covariance; prescribed x9m wall normal is NOT used as convergence angle"
  suite_run_binary_0434 "$params" "$log" "$tf" "$dir/output"
  echo "$name,$init_theta,$target_theta,$sigma,$contact_active,$state" >> "$MANIFEST"
}

for token in $CASES; do
  IFS=: read -r name init_theta target_theta kind <<< "$token"
  if [[ -z "${name:-}" || -z "${init_theta:-}" || -z "${target_theta:-}" || -z "${kind:-}" ]]; then echo "[0493x9p] malformed case token: $token" >&2; exit 2; fi
  run_one "$name" "$init_theta" "$target_theta" "$kind"
done

if ! suite_truthy_0434 "$PREFLIGHT_ONLY"; then
  python3 scripts/analyze_0493x9p_sessile_dynamics.py --root "$RUN_ROOT" --manifest "$MANIFEST" --Lx "$Lx" --Ly "$Ly" --nx "$NX" --ny "$NY" --gamma "$GAMMA" --liquid-mass "$LIQUID_MASS"
fi
