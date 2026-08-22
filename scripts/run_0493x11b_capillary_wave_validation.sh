#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$ROOT/scripts/src_mpcd_run_common_0434.sh"
suite_root_cd_0434

grep -q '0493x10q-wide-overlap-recovery' src/cuda_q6_resident_0400.cu || {
  echo "[0493x11b] ERROR current source does not contain x10q" >&2; exit 2; }

RUN_MODE="${RUN_MODE:-src-q6-g-f}"
TOPOLOGY=wall
CASE_LABEL="capillary_wave_0493x11b"
BASE="${BASE_RUN_ROOT:-runs/0493x11b_capillary_wave}"
CLEAN_BASE="${CLEAN_BASE:-1}"

NX="${NX:-256}"; NY="${NY:-128}"
Lx="${Lx:-1.0}"; Ly="${Ly:-0.5}"
GAMMA="${GAMMA:-20}"; DT="${DT:-0.002}"; KBT="${KBT:-0.125}"
LIQUID_TYPE="${LIQUID_TYPE:-1}"; LIQUID_MASS="${LIQUID_MASS:-1.0}"
MEAN_HEIGHT="${MEAN_HEIGHT:-0.25}"
AMPLITUDE_CELLS="${AMPLITUDE_CELLS:-2.0}"
SIGMAS="${SIGMAS:-1500 4500}"
MODES="${MODES:-2 3 4}"
SEEDS="${SEEDS:-4931201}"
STEPS="${STEPS:-8000}"
SUMMARY_EVERY="${SUMMARY_EVERY:-100}"
DUMP_STATE_EVERY=0
DUMP_ROLE_FILTER=fluid
SUMMARY_ROLE_FILTER=fluid
INACTIVE_SLOTS=0
RECORD_EVERY="${RECORD_EVERY:-20}"
MIN_RADIUS_CELLS="${SURFACE_TENSION_MIN_RADIUS_CELLS:-3}"
NU_REF="${NU_REF:-6.743265812e-4}"

THERMOSTAT_ENABLE=true
THERMOSTAT_MODE=cell_relative_rescale
THERMOSTAT_EVERY=1
THERMOSTAT_TARGET_KBT="$KBT"
THERMOSTAT_MIN_PARTICLES=3
ROTATION_ANGLE="${ROTATION_ANGLE:-1.5707963267948966}"
RANDOM_ROTATION_SIGN=true
GRID_SHIFT_ENABLE=true
PROJECTION_BACKEND=cuda
PROJECTION_OPERATOR=auto_fv_cg
PROJECTION_MAX_ITERATIONS="${PROJECTION_MAX_ITERATIONS:-800}"
PROJECTION_TOLERANCE="${PROJECTION_TOLERANCE:-1e-5}"
Q6_PROJECTION_STRENGTH=1.0
Q6_STRICT=1

Q6_GF_EXTERNAL_SPECIES=1
Q6_GF_HAS_GAS_PHASE=0
Q6_GF_DENSITY_RELAXATION_TIME="${Q6_GF_DENSITY_RELAXATION_TIME:-0.25}"
Q6_GF_MIN_FILL_FRACTION="${Q6_GF_MIN_FILL_FRACTION:-0.10}"
Q6_GF_DENSITY_COMPRESSION_GATE_ENABLE=1
Q6_GF_DENSITY_COMPRESSION_THRESHOLD_PARTICLES=3.0
Q6_GF_DENSITY_TRACTION_THRESHOLD_PARTICLES=6.0
Q6_GF_DENSITY_TRACTION_GAIN=1.0
SPECIES_RESAMPLING_ENABLE=false
LIQUID_RESAMPLING_ENABLE=false
GAS_RESAMPLING_ENABLE=false
VIRIAL_DENSITY_KICK_ENABLE=false
WEIGHTED_RESAMPLING_ENABLE_OVERRIDE=false
CUDA_EMPTY_REFILL_ENABLE_OVERRIDE=false

GEN_CASE=tg; U0=0.0; VELOCITY_MODE=zero
PARTICLE_MASS="$LIQUID_MASS"; BACKGROUND_TYPE="$LIQUID_TYPE"; INACTIVE_TYPE="$LIQUID_TYPE"
TG_HOLE_ENABLE=false

suite_defaults_common_0434
suite_compute_derived_0434

read -r H <<<"$(python3 - "$Lx" "$Ly" "$NX" "$NY" <<'PY'
import sys
lx,ly=float(sys.argv[1]),float(sys.argv[2]); nx,ny=int(sys.argv[3]),int(sys.argv[4])
dx,dy=lx/nx,ly/ny
if abs(dx-dy)>1e-12*max(1,abs(dx),abs(dy)): raise SystemExit("square cells required")
print(f"{dx:.17g}")
PY
)"

if [[ "$CLEAN_BASE" == 1 ]]; then rm -rf "$BASE"; fi
mkdir -p "$BASE" "$BASE/logs"
MANIFEST="$BASE/manifest.csv"
echo 'case,sigma,mode,seed,run_dir,Lx,Ly,nx,ny,h,gamma,liquid_mass,kBT,mean_height,amplitude_cells,steps,record_every,nu_ref' > "$MANIFEST"

echo '===== 0493x11b CAPILLARY-WAVE QUANTITATIVE CAMPAIGN ====='
echo "[0493x11b] grid=${NX}x${NY} L=(${Lx},${Ly}) h=$H gamma=$GAMMA dt=$DT kBT=$KBT"
echo "[0493x11b] H=$MEAN_HEIGHT amplitude=${AMPLITUDE_CELLS}h sigmas=[$SIGMAS] modes=[$MODES] seeds=[$SEEDS]"
echo "[0493x11b] steps=$STEPS recordEvery=$RECORD_EVERY recorderGrid=${NX}x${NY}"
echo '[0493x11b] theory omega^2=(sigma/rho) k^3 tanh(kH); vacuum above, periodic x, solid bottom/top'

LIQUID_REFERENCE_CELL_MASS="$(awk -v g="$GAMMA" -v m="$LIQUID_MASS" 'BEGIN{printf "%.17g",g*m}')"

for seed in $SEEDS; do
  for sigma in $SIGMAS; do
    for mode in $MODES; do
      tag="s${sigma}_n${mode}_seed${seed}"
      SEED="$seed"
      dir="$BASE/$tag"
      suite_prepare_dirs_0434 "$dir"
      STATE="$dir/init/capillary_wave_0493x11b.smpcd"
      OUT="$dir/output"; PARAMS="$dir/params/capillary_wave_0493x11b.kv"
      LOG="$dir/logs/capillary_wave_0493x11b.log"; TIME_FILE="$dir/logs/capillary_wave_0493x11b.time"
      mkdir -p "$OUT"

      python3 scripts/generate_0493x11b_capillary_wave_state.py \
        --output "$STATE" --Lx "$Lx" --Ly "$Ly" --nx "$NX" --ny "$NY" \
        --gamma "$GAMMA" --mean-height "$MEAN_HEIGHT" \
        --amplitude-cells "$AMPLITUDE_CELLS" --mode "$mode" \
        --liquid-type "$LIQUID_TYPE" --liquid-mass "$LIQUID_MASS" \
        --kBT "$KBT" --seed "$seed"

      cat > "$PARAMS" <<PARAMS
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
wallVpEnable = false
wallAccommodation = 1.0
wallKBT = -1.0
wallThermalNoise = 0.0
surfaceTensionSigma = $sigma
surfaceTensionMinRadiusCells = $MIN_RADIUS_CELLS
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
      suite_write_common_params_0434 "$RUN_MODE" >> "$PARAMS"

      suite_export_cuda_flags_0434 "$RUN_MODE" "$TOPOLOGY"
      export MPCD_Q6_PHASE_CURVATURE_DIAGNOSTICS_0493X9A=0
      export MPCD_Q6_PHASE_CURVATURE_DIAGNOSTICS_0493X9B=0
      export MPCD_Q6_PHASE_CURVATURE_DIAGNOSTICS_0493X9C=0
      export MPCD_Q6_STATIC_DROP_DIAGNOSTICS_0493X9E=0
      export MPCD_Q6_ELLIPSE_DIAGNOSTICS_0493X9F=0
      export MPCD_Q6_CONTACT_ANGLE_HARD_NORMAL_0493X9I=0
      export MPCD_Q6_CONTACT_ANGLE_WALL_FACE_0493X9L=0
      export MPCD_Q6_CONTACT_ANGLE_OFFSUPPORT_0493X9M=0

      # Current production kinetic free-surface path.
      export MPCD_X10J_SIMPLE_SPECULAR_ABLATION=0
      export MPCD_X10K_LOCAL_FRAME_SPECULAR_ABLATION=0
      export MPCD_X10M_MOVING_INTERFACE_WALL=0
      export MPCD_X10N_Q6_CONTINUOUS_INTERFACE_WALL=0
      export MPCD_X10O_Q6_THERMAL_INTERFACE_WALL=1
      export MPCD_X10O_THERMAL_PARTICLE_MASS="$LIQUID_MASS"
      export MPCD_X10O_THERMAL_SIGMAS="${MPCD_X10O_THERMAL_SIGMAS:-3.0}"
      export MPCD_X10O_THERMAL_MAX_CELLS="${MPCD_X10O_THERMAL_MAX_CELLS:-0.75}"
      export MPCD_X10P_INITIAL_OVERLAP_RESOLUTION=1
      export MPCD_X10L_PREWALL_INTERFACE_DIAGNOSTICS=0

      # Recorder only; no GUI window.  Grid equals solver grid so recorded mass
      # is directly converted to alpha by mass/(gamma*m).
      LIVE_VIS_ENABLE=0
      LIVE_VIS_HOLD_ON_EXIT=0
      LIVE_VIS_FIELD=mass
      LIVE_VIS_EVERY="$RECORD_EVERY"
      LIVE_VIS_NX="$NX"; LIVE_VIS_NY="$NY"
      LIVE_VIS_COLORMAP=blue_red; LIVE_VIS_CLIP=-1; LIVE_VIS_GAIN=1
      LIVE_VIS_SMOOTH_PASSES=0
      PARTICLE_TYPE_FILTER="$LIQUID_TYPE"
      FILTERED_RECORDING_ENABLE=1
      FILTER_MODE=none; FILTER_TAU=0
      FILTER_SAMPLE_EVERY="$RECORD_EVERY"
      RECORD_ENABLE=true
      RECORD_EVERY="$RECORD_EVERY"
      RECORD_FIELDS=mass
      RECORD_FORMAT=f32
      RECORD_STRIDE=1
      RECORD_SESSION_PREFIX="capwave_${tag}"
      OVERWRITE_LIVEVIS_CONTROL=1
      LIVE_VIS_CONTROL_FILE="$dir/livevis_control_0493x11b.kv"
      suite_prepare_livevis_control_0434 "$dir" "$RUN_MODE"
      suite_export_livevis_0434
      export SRC_FILTERED_FIELD_RECORD_FIELDS=mass MPCD_FILTERED_FIELD_RECORD_FIELDS=mass
      export SRC_FILTERED_FIELD_RECORD_EVERY="$RECORD_EVERY" MPCD_FILTERED_FIELD_RECORD_EVERY="$RECORD_EVERY"
      export SRC_FILTERED_FIELD_SAMPLE_EVERY="$RECORD_EVERY" MPCD_FILTERED_FIELD_SAMPLE_EVERY="$RECORD_EVERY"
      export LIVE_PROGRESS=1

      suite_write_env_file_0434 "$dir/logs/environment_0493x11b.env" "$RUN_MODE"
      echo
      echo "===== $tag ====="
      python3 - "$sigma" "$mode" "$Lx" "$MEAN_HEIGHT" "$GAMMA" "$LIQUID_MASS" "$H" <<'PY'
import math,sys
s=float(sys.argv[1]); n=int(sys.argv[2]); L=float(sys.argv[3]); H=float(sys.argv[4])
g=float(sys.argv[5]); m=float(sys.argv[6]); h=float(sys.argv[7])
rho=g*m/h**2; k=2*math.pi*n/L
om=math.sqrt(s/rho*k**3*math.tanh(k*H))
print(f"[0493x11b] rhoRef={rho:.9g} k={k:.9g} omegaTheory={om:.9g} period={2*math.pi/om:.9g}")
PY

      suite_run_binary_0434 "$PARAMS" "$LOG" "$TIME_FILE" "$OUT"
      TL_COUNT="$(find "$OUT/recordings" -name timeline.csv -type f 2>/dev/null | wc -l)"
      [[ "$TL_COUNT" -ge 1 ]] || { echo "[0493x11b] ERROR no recorder timeline for $tag" >&2; exit 2; }
      echo "$tag,$sigma,$mode,$seed,$dir,$Lx,$Ly,$NX,$NY,$H,$GAMMA,$LIQUID_MASS,$KBT,$MEAN_HEIGHT,$AMPLITUDE_CELLS,$STEPS,$RECORD_EVERY,$NU_REF" >> "$MANIFEST"
    done
  done
done

python3 scripts/analyze_0493x11b_capillary_wave.py \
  --manifest "$MANIFEST" --output-dir "$BASE/analysis" --skip-time "${FIT_SKIP_TIME:-0.20}"

echo "[0493x11b] COMPLETE analysis=$BASE/analysis"
