#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$ROOT/scripts/src_mpcd_run_common_0434.sh"
suite_root_cd_0434

# 0493x12cal — production capillary-property calibrator.
#
# Primary observable:
#   omega^2 = (sigma_eff/rho_ref) k^3 tanh(k H)
#
# The calibrated quantity is therefore sigma_eff, measured dynamically from
# small-amplitude free-surface waves.  This is intentionally distinct from the
# sub-grid curvature cutoff: the calibration waves remain in the resolved,
# low-curvature regime.
#
# Usage examples:
#   PREFLIGHT_ONLY=1 SIGMA_DECLARED=945 bash scripts/run_0493x12cal_capillary_calibrator.sh
#   SIGMA_DECLARED=945 PROFILE=production bash scripts/run_0493x12cal_capillary_calibrator.sh
#   ANALYZE_ONLY=1 RUN_ROOT=runs/... bash scripts/run_0493x12cal_capillary_calibrator.sh

CASE_LABEL=capillary_calibrator_0493x12cal
CALIBRATION_PATH="${CALIBRATION_PATH:-src-q6-g-f}"
suite_validate_path_0434 "$CALIBRATION_PATH"
if ! suite_path_has_q6_g_f_0493x7h "$CALIBRATION_PATH"; then
  echo "[0493x12cal] ERROR capillary calibration currently requires src-q6-g-f" >&2
  exit 2
fi

PROFILE="${PROFILE:-production}"
case "$PROFILE" in
  quick)
    MODES="${MODES:-2 3 4}"
    REPLICATES="${REPLICATES:-1}"
    RUN_PERIODS="${RUN_PERIODS:-1.5}"
    SAMPLES_PER_PERIOD="${SAMPLES_PER_PERIOD:-60}"
    ;;
  production)
    MODES="${MODES:-2 3 4}"
    REPLICATES="${REPLICATES:-3}"
    RUN_PERIODS="${RUN_PERIODS:-2.0}"
    SAMPLES_PER_PERIOD="${SAMPLES_PER_PERIOD:-80}"
    ;;
  *)
    echo "[0493x12cal] ERROR PROFILE must be quick or production" >&2
    exit 2
    ;;
esac

RUN_ROOT="${RUN_ROOT:-runs/0493x12cal_capillary_calibrator}"
CLEAN_RUN_ROOT="${CLEAN_RUN_ROOT:-1}"
PREFLIGHT_ONLY="${PREFLIGHT_ONLY:-0}"
ANALYZE_ONLY="${ANALYZE_ONLY:-0}"
THREADS="${THREADS:-8}"
LIVE_PROGRESS="${LIVE_PROGRESS:-1}"

NX="${NX:-256}"
NY="${NY:-128}"
Lx="${Lx:-1.0}"
Ly="${Ly:-0.5}"
GAMMA="${GAMMA:-20}"
DT="${DT:-0.002}"
KBT="${KBT:-0.125}"
LIQUID_TYPE="${LIQUID_TYPE:-1}"
LIQUID_MASS="${LIQUID_MASS:-1.0}"
SIGMA_DECLARED="${SIGMA_DECLARED:-1500}"
MEAN_HEIGHT="${MEAN_HEIGHT:-0.25}"
AMPLITUDE_CELLS="${AMPLITUDE_CELLS:-2.0}"

BASE_SEED="${BASE_SEED:-4931201}"
SEED_STRIDE="${SEED_STRIDE:-1009}"
STEPS_OVERRIDE="${STEPS_OVERRIDE:-0}"
RECORD_EVERY_OVERRIDE="${RECORD_EVERY_OVERRIDE:-0}"
SUMMARY_EVERY="${SUMMARY_EVERY:-100}"

FIT_PERIODS="${FIT_PERIODS:-1.0}"
SENSITIVITY_PERIODS="${SENSITIVITY_PERIODS:-0.75,1.0,1.25}"
MAX_RECORD_GB="${MAX_RECORD_GB:-2.0}"
ALLOW_LARGE_RECORDINGS="${ALLOW_LARGE_RECORDINGS:-0}"

SURFACE_TENSION_MIN_RADIUS_CELLS="${SURFACE_TENSION_MIN_RADIUS_CELLS:-3}"
MPCD_X12A_LOCAL_THERMAL_RADIUS_CELLS="${MPCD_X12A_LOCAL_THERMAL_RADIUS_CELLS:-25.298221281347036}"

ROTATION_ANGLE="${ROTATION_ANGLE:-1.5707963267948966}"
RANDOM_ROTATION_SIGN="${RANDOM_ROTATION_SIGN:-true}"
GRID_SHIFT_ENABLE="${GRID_SHIFT_ENABLE:-true}"
THERMOSTAT_ENABLE="${THERMOSTAT_ENABLE:-true}"
THERMOSTAT_MODE="${THERMOSTAT_MODE:-cell_relative_rescale}"
THERMOSTAT_EVERY="${THERMOSTAT_EVERY:-1}"
THERMOSTAT_TARGET_KBT="${THERMOSTAT_TARGET_KBT:-$KBT}"
THERMOSTAT_MIN_PARTICLES="${THERMOSTAT_MIN_PARTICLES:-3}"

PROJECTION_MAX_ITERATIONS="${PROJECTION_MAX_ITERATIONS:-800}"
PROJECTION_TOLERANCE="${PROJECTION_TOLERANCE:-1e-5}"
Q6_GF_DENSITY_RELAXATION_TIME="${Q6_GF_DENSITY_RELAXATION_TIME:-0.25}"
Q6_GF_MIN_FILL_FRACTION="${Q6_GF_MIN_FILL_FRACTION:-0.10}"

CHARACTERISTIC_U="${CHARACTERISTIC_U:--1}"
CHARACTERISTIC_D="${CHARACTERISTIC_D:--1}"
KINEMATIC_VISCOSITY="${KINEMATIC_VISCOSITY:--1}"
TRANSPORT_CALIBRATION="${TRANSPORT_CALIBRATION:-}"
GRAVITY_MAGNITUDE="${GRAVITY_MAGNITUDE:-0}"

# Recorder only by default.  Users may opt into the window for visual review.
LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-0}"
LIVE_VIS_EVERY="${LIVE_VIS_EVERY:-1}"
LIVE_VIS_HOLD_ON_EXIT=0

export OMP_NUM_THREADS="$THREADS" LIVE_PROGRESS

PARTICLE_MASS="$LIQUID_MASS"
BACKGROUND_TYPE="$LIQUID_TYPE"
INACTIVE_TYPE="$LIQUID_TYPE"
INACTIVE_SLOTS=0
SUMMARY_ROLE_FILTER=fluid
DUMP_ROLE_FILTER=fluid

THERMOSTAT_TARGET_KBT="$THERMOSTAT_TARGET_KBT"
PROJECTION_BACKEND=cuda
PROJECTION_OPERATOR=auto_fv_cg
PROJECTION_MOMENTUM_CORRECTION_ENABLE=true
Q6_PROJECTION_STRENGTH=1.0
Q6_STRICT=1

Q6_GF_EXTERNAL_SPECIES=1
Q6_GF_HAS_GAS_PHASE=0
Q6_GF_DENSITY_COMPRESSION_GATE_ENABLE=1
Q6_GF_DENSITY_COMPRESSION_THRESHOLD_PARTICLES=3.0
Q6_GF_DENSITY_TRACTION_THRESHOLD_PARTICLES=6.0
Q6_GF_DENSITY_TRACTION_GAIN=1.0

SPECIES_RESAMPLING_ENABLE=false
LIQUID_RESAMPLING_ENABLE=false
GAS_RESAMPLING_ENABLE=false
WEIGHTED_RESAMPLING_ENABLE_OVERRIDE=false
CUDA_EMPTY_REFILL_ENABLE_OVERRIDE=false
VIRIAL_DENSITY_KICK_ENABLE=false

GEN_CASE=tg
U0=0.0
VELOCITY_MODE=zero
TG_HOLE_ENABLE=false

suite_defaults_common_0434
suite_compute_derived_0434

read -r H RHO_REF <<<"$(python3 - "$Lx" "$Ly" "$NX" "$NY" "$GAMMA" "$LIQUID_MASS" <<'PY'
import sys
lx,ly=float(sys.argv[1]),float(sys.argv[2])
nx,ny=int(sys.argv[3]),int(sys.argv[4])
gamma=float(sys.argv[5]); mass=float(sys.argv[6])
dx,dy=lx/nx,ly/ny
if abs(dx-dy)>1e-12*max(1.0,abs(dx),abs(dy)):
    raise SystemExit("[0493x12cal] square cells required")
if min(lx,ly,nx,ny,gamma,mass)>0:
    print(f"{dx:.17g} {gamma*mass/(dx*dy):.17g}")
else:
    raise SystemExit("[0493x12cal] invalid geometry/density inputs")
PY
)"

python3 - \
  "$PROFILE" "$Lx" "$Ly" "$NX" "$NY" "$H" "$GAMMA" "$DT" "$KBT" "$LIQUID_MASS" \
  "$SIGMA_DECLARED" "$MEAN_HEIGHT" "$AMPLITUDE_CELLS" "$MODES" "$REPLICATES" \
  "$RUN_PERIODS" "$SAMPLES_PER_PERIOD" "$STEPS_OVERRIDE" "$RECORD_EVERY_OVERRIDE" \
  "$SURFACE_TENSION_MIN_RADIUS_CELLS" "$MAX_RECORD_GB" "$ALLOW_LARGE_RECORDINGS" <<'PY_PREFLIGHT'
import math,sys
(profile,lx,ly,nx,ny,h,gamma,dt,kbt,mass,sigma,H,amp,modes,reps,
 run_periods,spp,steps_override,record_override,rmin,max_gb,allow)=sys.argv[1:]
lx,ly,h,dt,kbt,mass,sigma,H,amp=map(float,(lx,ly,h,dt,kbt,mass,sigma,H,amp))
nx,ny,gamma,reps=int(nx),int(ny),int(gamma),int(reps)
run_periods=float(run_periods); spp=int(spp)
steps_override=int(steps_override); record_override=int(record_override)
rmin=float(rmin); max_gb=float(max_gb); allow=int(allow)
modes=[int(x) for x in modes.split()]
if sigma<=0 or H<=0 or amp<=0 or reps<1 or not modes:
    raise SystemExit("[0493x12cal] invalid sigma/wave campaign")
if H-amp*h <= 4*h or H+amp*h >= ly-4*h:
    raise SystemExit("[0493x12cal] interface must stay at least four cells from top/bottom")
if any(m<1 or nx/m<16 for m in modes):
    raise SystemExit("[0493x12cal] each wavelength must have at least 16 cells")
rho=gamma*mass/h**2
total_bytes=0
total_steps=0
print("===== 0493x12cal CAPILLARY CALIBRATOR PREFLIGHT =====")
print(f"profile={profile} calibrationPath=src-q6-g-f")
print(f"grid={nx}x{ny} L=({lx:.9g},{ly:.9g}) h={h:.9g} gamma={gamma} rhoRef={rho:.9g}")
print(f"fluid dt={dt:.9g} kBT={kbt:.9g} mass={mass:.9g}")
print(f"sigmaDeclared={sigma:.9g} meanHeight={H:.9g} amplitude={amp:.6g}h minRadiusCells={rmin:.6g}")
print(f"modes={modes} replicates={reps} runPeriods={run_periods:g} samplesPerPeriod={spp}")
for mode in modes:
    k=2*math.pi*mode/lx
    omega=math.sqrt((sigma/rho)*k**3*math.tanh(k*H))
    period=2*math.pi/omega
    steps=steps_override if steps_override>0 else max(1,math.ceil(run_periods*period/dt))
    rec=record_override if record_override>0 else max(1,int(math.floor(period/dt/spp)))
    frames=1+steps//rec
    total_steps += reps*steps
    total_bytes += reps*frames*nx*ny*4
    print(f"mode={mode} lambda/h={nx/mode:.6g} omegaTheory={omega:.9g} T={period:.9g} steps={steps} recordEvery={rec} frames~{frames}")
gb=total_bytes/1e9
print(f"totalRuns={len(modes)*reps} totalSolverSteps={total_steps} estimatedRecorderVolume={gb:.3f}GB limit={max_gb:.3f}GB")
print("observable=dynamic surface tension from omega^2=(sigma_eff/rho)k^3*tanh(kH)")
print("note=resolved waves calibrate sigma_eff; they do not calibrate the sub-grid curvature cutoff itself")
if gb>max_gb and not allow:
    raise SystemExit("[0493x12cal] estimated recording volume exceeds MAX_RECORD_GB; set ALLOW_LARGE_RECORDINGS=1 to override")
PY_PREFLIGHT

if [[ "$PREFLIGHT_ONLY" == 1 ]]; then
  echo "[0493x12cal] PREFLIGHT_ONLY=1; no simulation launched"
  exit 0
fi

MANIFEST="$RUN_ROOT/manifest_0493x12cal.csv"

if [[ "$ANALYZE_ONLY" != 1 ]]; then
  [[ "$CLEAN_RUN_ROOT" == 1 ]] && rm -rf "$RUN_ROOT"
  mkdir -p "$RUN_ROOT"/{logs,analysis}
  suite_ensure_binary_0434
  echo 'case,sigma_declared,mode,seed,run_dir,Lx,Ly,nx,ny,h,gamma,liquid_mass,kBT,mean_height,amplitude_cells,steps,record_every,min_radius_cells,calibration_path,x12a_radius_cells' > "$MANIFEST"
else
  [[ -s "$MANIFEST" ]] || { echo "[0493x12cal] ERROR ANALYZE_ONLY but manifest missing: $MANIFEST" >&2; exit 2; }
fi

LIQUID_REFERENCE_CELL_MASS="$(awk -v g="$GAMMA" -v m="$LIQUID_MASS" 'BEGIN{printf "%.17g",g*m}')"

run_case() {
  local mode="$1" rep="$2" seed="$3"
  # src_mpcd_run_common_0434.sh writes rngSeed=${SEED} in the common
  # parameter block. Keep it synchronized with this case's calibration seed.
  local SEED="$seed"
  local derived omega period steps rec
  derived="$(python3 - "$SIGMA_DECLARED" "$RHO_REF" "$mode" "$Lx" "$MEAN_HEIGHT" "$DT" \
    "$RUN_PERIODS" "$SAMPLES_PER_PERIOD" "$STEPS_OVERRIDE" "$RECORD_EVERY_OVERRIDE" <<'PY'
import math,sys
sigma,rho=float(sys.argv[1]),float(sys.argv[2])
mode=int(sys.argv[3]); lx,H,dt=float(sys.argv[4]),float(sys.argv[5]),float(sys.argv[6])
periods=float(sys.argv[7]); spp=int(sys.argv[8]); so=int(sys.argv[9]); ro=int(sys.argv[10])
k=2*math.pi*mode/lx
omega=math.sqrt((sigma/rho)*k**3*math.tanh(k*H))
T=2*math.pi/omega
steps=so if so>0 else max(1,math.ceil(periods*T/dt))
rec=ro if ro>0 else max(1,int(math.floor(T/dt/spp)))
print(f"{omega:.17g} {T:.17g} {steps:d} {rec:d}")
PY
)"
  read -r omega period steps rec <<<"$derived"

  local sigma_tag="${SIGMA_DECLARED//./p}"
  sigma_tag="${sigma_tag//-/m}"
  local tag="sigma${sigma_tag}_n${mode}_rep${rep}_seed${seed}"
  local dir="$RUN_ROOT/$tag"
  suite_prepare_dirs_0434 "$dir"
  local state="$dir/init/capillary_wave_0493x12cal.smpcd"
  local out="$dir/output"
  local params="$dir/params/capillary_wave_0493x12cal.kv"
  local log="$dir/logs/capillary_wave_0493x12cal.log"
  local time_file="$dir/logs/capillary_wave_0493x12cal.time"

  python3 scripts/generate_0493x11b_capillary_wave_state.py \
    --output "$state" --Lx "$Lx" --Ly "$Ly" --nx "$NX" --ny "$NY" \
    --gamma "$GAMMA" --mean-height "$MEAN_HEIGHT" \
    --amplitude-cells "$AMPLITUDE_CELLS" --mode "$mode" \
    --liquid-type "$LIQUID_TYPE" --liquid-mass "$LIQUID_MASS" \
    --kBT "$KBT" --seed "$seed"

  cat > "$params" <<PARAMS
inputState = $state
outputDir = $out
Lx = $Lx
Ly = $Ly
Nx = $NX
Ny = $NY
dt = $DT
nSteps = $steps
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
wallVpEnable = false
wallAccommodation = 1.0
wallKBT = -1.0
wallThermalNoise = 0.0
surfaceTensionSigma = $SIGMA_DECLARED
surfaceTensionMinRadiusCells = $SURFACE_TENSION_MIN_RADIUS_CELLS
phaseInterfaceASelector = type:$LIQUID_TYPE
phaseInterfaceBSelector = vacuum
phaseInterfaceKineticReflectionFraction = 1.0
phaseInterfaceEvaporationTargetType = -1
phaseInterfaceContactAngleDegrees = -1
speciesRegistryEnable = true
speciesCount = 1
species0 = $LIQUID_TYPE incompressible_liquid liquid 1.0 1.0 $LIQUID_REFERENCE_CELL_MASS
species0ResamplingEnable = false
speciesRequireRegisteredTypes = true
speciesDiagnosticsEnable = false
speciesCellDiagnosticsEnable = false
speciesQ6Enable = true
speciesQ6Mode = free_surface_masked
speciesQ6Sensitivity = 1.0
speciesQ6FallbackMode = common
speciesQ6ComparisonTolerance = 1e-11
speciesQ6MinOccupancyFraction = $Q6_GF_MIN_FILL_FRACTION
dumpStateEvery = 0
dumpRoleFilter = fluid
summaryRoleFilter = fluid
PARAMS
  suite_write_common_params_0434 "$CALIBRATION_PATH" >> "$params"

  suite_export_cuda_flags_0434 "$CALIBRATION_PATH" wall

  export MPCD_Q6_PHASE_CURVATURE_DIAGNOSTICS_0493X9A=0
  export MPCD_Q6_PHASE_CURVATURE_DIAGNOSTICS_0493X9B=0
  export MPCD_Q6_PHASE_CURVATURE_DIAGNOSTICS_0493X9C=0
  export MPCD_Q6_STATIC_DROP_DIAGNOSTICS_0493X9E=0
  export MPCD_Q6_ELLIPSE_DIAGNOSTICS_0493X9F=0
  export MPCD_Q6_CONTACT_ANGLE_HARD_NORMAL_0493X9I=0
  export MPCD_Q6_CONTACT_ANGLE_WALL_FACE_0493X9L=0
  export MPCD_Q6_CONTACT_ANGLE_OFFSUPPORT_0493X9M=0

  # Exact current production kinetic free-surface chain.
  export MPCD_X10J_SIMPLE_SPECULAR_ABLATION=0
  export MPCD_X10K_LOCAL_FRAME_SPECULAR_ABLATION=0
  export MPCD_X10M_MOVING_INTERFACE_WALL=0
  export MPCD_X10N_Q6_CONTINUOUS_INTERFACE_WALL=0
  export MPCD_X10O_Q6_THERMAL_INTERFACE_WALL=1
  export MPCD_X10O_THERMAL_PARTICLE_MASS="$LIQUID_MASS"
  export MPCD_X10O_THERMAL_SIGMAS="${MPCD_X10O_THERMAL_SIGMAS:-3.0}"
  export MPCD_X10O_THERMAL_MAX_CELLS="${MPCD_X10O_THERMAL_MAX_CELLS:-0.75}"
  export MPCD_X10L_PREWALL_INTERFACE_DIAGNOSTICS=0
  export MPCD_X10_KINETIC_INTERFACE_CIC=1
  export MPCD_X10_KINETIC_INTERFACE_QUADRATIC=1
  export MPCD_X10_KINETIC_INTERFACE_ONE_FOR_ONE=1
  export MPCD_X10_KINETIC_INTERFACE_ONE_FOR_ONE_SWAP=1
  export MPCD_X10P_INITIAL_OVERLAP_RESOLUTION=1
  export MPCD_X10R_Q6_THERMAL_FULL_VECTOR_ENDPOINT_VELOCITY=0
  export MPCD_X10S_Q6_THERMAL_SEGMENT_NORMAL_KINEMATICS=0
  export MPCD_X10T_Q6_THERMAL_RIGID_TANGENTIAL_KINEMATICS=0
  export MPCD_X10_KINETIC_INTERFACE_THERMAL_PHASE_LIMITER=0
  export MPCD_X12A_LOCAL_THERMAL_COOLING=1
  export MPCD_X12A_LOCAL_THERMAL_RADIUS_CELLS

  # Mass recorder at solver resolution.  GUI remains optional.
  LIVE_VIS_FIELD=mass
  LIVE_VIS_NX="$NX"
  LIVE_VIS_NY="$NY"
  LIVE_VIS_COLORMAP=blue_red
  LIVE_VIS_CLIP=-1
  LIVE_VIS_GAIN=1
  LIVE_VIS_SMOOTH_PASSES=0
  LIVE_VIS_HOLD_ON_EXIT=0
  PARTICLE_TYPE_FILTER="$LIQUID_TYPE"

  FILTERED_RECORDING_ENABLE=1
  FILTER_MODE=none
  FILTER_TAU=0
  FILTER_SAMPLE_EVERY="$rec"
  RECORD_ENABLE=true
  RECORD_EVERY="$rec"
  RECORD_FIELDS=mass
  RECORD_FORMAT=f32
  RECORD_STRIDE=1
  RECORD_SESSION_PREFIX="capcal_${tag}"
  OVERWRITE_LIVEVIS_CONTROL=1
  LIVE_VIS_CONTROL_FILE="$dir/livevis_control_0493x12cal.kv"
  suite_prepare_livevis_control_0434 "$dir" "$CALIBRATION_PATH"
  suite_export_livevis_0434
  export SRC_FILTERED_FIELD_RECORD_FIELDS=mass
  export MPCD_FILTERED_FIELD_RECORD_FIELDS=mass
  export SRC_FILTERED_FIELD_RECORD_EVERY="$rec"
  export MPCD_FILTERED_FIELD_RECORD_EVERY="$rec"
  export SRC_FILTERED_FIELD_SAMPLE_EVERY="$rec"
  export MPCD_FILTERED_FIELD_SAMPLE_EVERY="$rec"

  suite_write_env_file_0434 "$dir/logs/environment_0493x12cal.env" "$CALIBRATION_PATH"

  echo
  echo "===== 0493x12cal $tag ====="
  echo "[0493x12cal] mode=$mode rep=$rep seed=$seed sigmaDeclared=$SIGMA_DECLARED omegaTheory=$omega period=$period steps=$steps recordEvery=$rec"
  suite_run_binary_0434 "$params" "$log" "$time_file" "$out"

  local timelines
  timelines="$(find "$out/recordings" -name timeline.csv -type f 2>/dev/null | wc -l)"
  [[ "$timelines" -ge 1 ]] || { echo "[0493x12cal] ERROR no recorder timeline for $tag" >&2; exit 2; }

  echo "$tag,$SIGMA_DECLARED,$mode,$seed,$dir,$Lx,$Ly,$NX,$NY,$H,$GAMMA,$LIQUID_MASS,$KBT,$MEAN_HEIGHT,$AMPLITUDE_CELLS,$steps,$rec,$SURFACE_TENSION_MIN_RADIUS_CELLS,$CALIBRATION_PATH,$MPCD_X12A_LOCAL_THERMAL_RADIUS_CELLS" >> "$MANIFEST"
}

if [[ "$ANALYZE_ONLY" != 1 ]]; then
  for ((rep=0; rep<REPLICATES; ++rep)); do
    seed=$((BASE_SEED + rep * SEED_STRIDE))
    for mode in $MODES; do
      run_case "$mode" "$rep" "$seed"
    done
  done
fi

python3 scripts/analyze_0493x12cal_capillary_calibrator.py \
  --manifest "$MANIFEST" \
  --output-dir "$RUN_ROOT/analysis" \
  --fit-periods "$FIT_PERIODS" \
  --sensitivity-periods "$SENSITIVITY_PERIODS" \
  --characteristic-U "$CHARACTERISTIC_U" \
  --characteristic-D "$CHARACTERISTIC_D" \
  --kinematic-viscosity "$KINEMATIC_VISCOSITY" \
  --transport-calibration "$TRANSPORT_CALIBRATION" \
  --gravity "$GRAVITY_MAGNITUDE"

echo "[0493x12cal] COMPLETE result=$RUN_ROOT/analysis/capillary_calibration_0493x12cal.csv"
