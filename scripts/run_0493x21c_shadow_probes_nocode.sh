#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$ROOT/scripts/src_mpcd_run_common_0434.sh"
suite_root_cd_0434

# 0493x21c — no-code shadow probes from already-qualified active checkpoints.
#
# IMPORTANT:
#   - NO C++/CUDA source modification
#   - NO rebuild
#   - NO new long active run
#   - NO long sigma=0 baseline
#   - this script only restarts the existing selected checkpoints for 2-step
#     paired sigma=945 / sigma=0 probes, then collects raw diagnostics.
#
# Protocol:
#   1. Run ONE resolved active circular drop at sigma>0 until its geometry is stable.
#   2. Keep periodic state dumps from that active trajectory.
#   3. Select three checkpoints inside the stable interval.
#   4. From each exact same checkpoint, launch paired short branches with
#      sigma=sigmaTarget and sigma=0, same RNG seed and same numerical settings.
#   5. Use only the first post-restart diagnostic sample for the primary paired
#      Young–Laplace increment.  The sigma=0 branch is never used as a long-lived drop.
#
# No C++/CUDA modification. No resampling. No virial kick.

CASE_LABEL="capillary_shadow_yl_0493x21c"
RUN_MODE="src-q6-g-f"
TOPOLOGY="closed_box"

COLLECTOR="$ROOT/scripts/collect_0493x21c_shadow_probes_nocode.py"
BIN="${BIN:-${SRC_MPCD_DEFAULT_BIN_0434:-build/src_mpcd_base_cuda_q6_resident_livevis_0486}}"
for f in "$COLLECTOR" "$ROOT/scripts/src_mpcd_run_common_0434.sh" "$BIN"; do
  [[ -f "$f" ]] || { echo "[0493x21c] ERROR missing $f" >&2; exit 2; }
done

MODE="${1:---run}"
case "$MODE" in
  --preflight|--shadows|--collect|--run) ;;
  *) echo "usage: $0 [--preflight|--shadows|--collect|--run]" >&2; exit 2 ;;
esac

# -----------------------------------------------------------------------------
# Locked nominal x13h fluid and deliberately resolved geometry.
# -----------------------------------------------------------------------------
NX="${NX:-256}"; NY="${NY:-256}"
Lx="${Lx:-1.0}"; Ly="${Ly:-1.0}"
GAMMA="${GAMMA:-8}"
DT="${DT:-0.0063471328149122585}"
KBT="${KBT:-0.125}"
LIQUID_TYPE="${LIQUID_TYPE:-1}"
LIQUID_MASS="${LIQUID_MASS:-1.0}"
ROTATION_ANGLE="${ROTATION_ANGLE:-2.0943951023931953}"
RANDOM_ROTATION_SIGN="${RANDOM_ROTATION_SIGN:-true}"
GRID_SHIFT_ENABLE="${GRID_SHIFT_ENABLE:-true}"
THERMOSTAT_ENABLE="${THERMOSTAT_ENABLE:-true}"
THERMOSTAT_MODE="${THERMOSTAT_MODE:-cell_relative_rescale}"
THERMOSTAT_EVERY="${THERMOSTAT_EVERY:-1}"
THERMOSTAT_TARGET_KBT="${THERMOSTAT_TARGET_KBT:-$KBT}"
THERMOSTAT_MIN_PARTICLES="${THERMOSTAT_MIN_PARTICLES:-3}"

RADIUS_CELLS="${RADIUS_CELLS:-64}"
CENTER_X="${CENTER_X:-0.5}"; CENTER_Y="${CENTER_Y:-0.5}"
SIGMA_TARGET="${SIGMA_TARGET:-945}"
SURFACE_TENSION_MIN_RADIUS_CELLS="${SURFACE_TENSION_MIN_RADIUS_CELLS:-4}"
MPCD_X12A_LOCAL_THERMAL_RADIUS_CELLS="${MPCD_X12A_LOCAL_THERMAL_RADIUS_CELLS:-25.298221281347036}"
ACTIVE_SEED="${ACTIVE_SEED:-4932301}"
PROBE_SEED_BASE="${PROBE_SEED_BASE:-4932311}"

# The active trajectory is long enough for visual/statistical stabilization.
ACTIVE_STEPS="${ACTIVE_STEPS:-1000}"
ACTIVE_SUMMARY_EVERY="${ACTIVE_SUMMARY_EVERY:-5}"
ACTIVE_DUMP_EVERY="${ACTIVE_DUMP_EVERY:-100}"
CHECKPOINT_COUNT="${CHECKPOINT_COUNT:-3}"
PROBE_REPLICATES="${PROBE_REPLICATES:-6}"
# Two steps guarantee a first positive-step diagnostic row while keeping the
# sigma=0 shadow far too short to develop geometric dispersion.
PROBE_STEPS="${PROBE_STEPS:-2}"

CAMPAIGN_ROOT="${CAMPAIGN_ROOT:-runs/0493x21c_fix1_capillary_shadow_R${RADIUS_CELLS}_s${SIGMA_TARGET}}"
ACTIVE_ROOT="$CAMPAIGN_ROOT/active"
SHADOW_ROOT="$CAMPAIGN_ROOT/shadows_nocode"
SELECTED="$CAMPAIGN_ROOT/analysis/selected_checkpoints_0493x21c.csv"
MANIFEST="$CAMPAIGN_ROOT/manifest_shadow_pairs_0493x21c_nocode.csv"
COLLECT_ROOT="$CAMPAIGN_ROOT/analysis_nocode"
CLEAN_SHADOWS="${CLEAN_SHADOWS:-1}"

LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
LIVE_VIS_ENABLE_ACTIVE="${LIVE_VIS_ENABLE_ACTIVE:-1}"
LIVE_VIS_EVERY_ACTIVE="${LIVE_VIS_EVERY_ACTIVE:-1}"
LIVE_VIS_ENABLE_PROBE="${LIVE_VIS_ENABLE_PROBE:-0}"
THREADS="${THREADS:-8}"
export OMP_NUM_THREADS="$THREADS"

# -----------------------------------------------------------------------------
# Exact production-chain controls, matching the qualified x13h free-surface path.
# -----------------------------------------------------------------------------
PROJECTION_BACKEND="${PROJECTION_BACKEND:-cuda}"
PROJECTION_OPERATOR="${PROJECTION_OPERATOR:-auto_fv_cg}"
PROJECTION_MAX_ITERATIONS="${PROJECTION_MAX_ITERATIONS:-2000}"
PROJECTION_TOLERANCE="${PROJECTION_TOLERANCE:-1.0e-5}"
PROJECTION_MOMENTUM_CORRECTION_ENABLE=false
Q6_PROJECTION_STRENGTH=1.0
Q6_STRICT=1
Q6_FORCE_PROJECTION_MODE=prestream_single_fused
Q6_GF_EXTERNAL_SPECIES=1
Q6_GF_HAS_GAS_PHASE=0
Q6_GF_DENSITY_RELAXATION_TIME="${Q6_GF_DENSITY_RELAXATION_TIME:-0.25}"
Q6_GF_MIN_FILL_FRACTION="${Q6_GF_MIN_FILL_FRACTION:-0.10}"
Q6_GF_DENSITY_COMPRESSION_GATE_ENABLE=1
Q6_GF_DENSITY_COMPRESSION_THRESHOLD_PARTICLES="${Q6_GF_DENSITY_COMPRESSION_THRESHOLD_PARTICLES:-3.0}"
Q6_GF_DENSITY_TRACTION_THRESHOLD_PARTICLES="${Q6_GF_DENSITY_TRACTION_THRESHOLD_PARTICLES:-6.0}"
Q6_GF_DENSITY_TRACTION_GAIN="${Q6_GF_DENSITY_TRACTION_GAIN:-1.0}"
SPECIES_RESAMPLING_ENABLE=false
LIQUID_RESAMPLING_ENABLE=false
GAS_RESAMPLING_ENABLE=false
VIRIAL_DENSITY_KICK_ENABLE=false
WEIGHTED_RESAMPLING_ENABLE_OVERRIDE=false
CUDA_EMPTY_REFILL_ENABLE_OVERRIDE=false

GEN_CASE=tg
U0=0.0
VELOCITY_MODE=zero
PARTICLE_MASS="$LIQUID_MASS"
BACKGROUND_TYPE="$LIQUID_TYPE"
INACTIVE_TYPE="$LIQUID_TYPE"
TG_HOLE_ENABLE=false

export NX NY Lx Ly GAMMA DT KBT LIQUID_TYPE LIQUID_MASS
export ROTATION_ANGLE RANDOM_ROTATION_SIGN GRID_SHIFT_ENABLE
export THERMOSTAT_ENABLE THERMOSTAT_MODE THERMOSTAT_EVERY THERMOSTAT_TARGET_KBT THERMOSTAT_MIN_PARTICLES
export PROJECTION_BACKEND PROJECTION_OPERATOR PROJECTION_MAX_ITERATIONS PROJECTION_TOLERANCE
export PROJECTION_MOMENTUM_CORRECTION_ENABLE Q6_PROJECTION_STRENGTH Q6_STRICT Q6_FORCE_PROJECTION_MODE
export Q6_GF_EXTERNAL_SPECIES Q6_GF_HAS_GAS_PHASE Q6_GF_DENSITY_RELAXATION_TIME Q6_GF_MIN_FILL_FRACTION
export Q6_GF_DENSITY_COMPRESSION_GATE_ENABLE Q6_GF_DENSITY_COMPRESSION_THRESHOLD_PARTICLES
export Q6_GF_DENSITY_TRACTION_THRESHOLD_PARTICLES Q6_GF_DENSITY_TRACTION_GAIN
export SPECIES_RESAMPLING_ENABLE LIQUID_RESAMPLING_ENABLE GAS_RESAMPLING_ENABLE VIRIAL_DENSITY_KICK_ENABLE
export WEIGHTED_RESAMPLING_ENABLE_OVERRIDE CUDA_EMPTY_REFILL_ENABLE_OVERRIDE
export MPCD_X12A_LOCAL_THERMAL_RADIUS_CELLS

suite_defaults_common_0434
suite_compute_derived_0434

# Physics flags: Q6-g-f + x9 capillary + x10o/CIC/Q2/x10u/x10v + x12a.
suite_export_cuda_flags_0434 "$RUN_MODE" "$TOPOLOGY"
export MPCD_Q6_PHASE_GEOMETRY_RESIDENT_0493X6C=1
export MPCD_Q6_PHASE_GEOMETRY_CUTFACE_0493X6D=0
export MPCD_Q6_PHASE_INTERFACE_TOPOLOGY_0493X6E=1
export MPCD_Q6_PHASE_INTERFACE_STENCIL_0493X6F=1
export MPCD_Q6_PHASE_GAS_PRESSURE_0493X6G=0
export MPCD_Q6_PHASE_GAS_PRESSURE_CONSTANT_0493X6G=0
export MPCD_Q6_PHASE_GAS_PRESSURE_REFERENCE_0493X6G=0
export MPCD_Q6_PHASE_GAS_PRESSURE_SCALE_0493X6G=0
export MPCD_Q6_PHASE_PRESSURE_DIAGNOSTICS_0493X6A=0
export MPCD_Q6_PHASE_GEOMETRY_DIAGNOSTICS_0493X6B=0
export MPCD_Q6_POSTAPPLY_REGION_DIAGNOSTICS_0493X6H_B0=0
export MPCD_Q6_FACE_TO_PARTICLE_RT0_0493X6H_B1=1

export MPCD_Q6_STATIC_DROP_DIAGNOSTICS_0493X9E=1
export MPCD_Q6_ELLIPSE_DIAGNOSTICS_0493X9F=1
export MPCD_Q6_PHASE_CURVATURE_DIAGNOSTICS_0493X9A=0
export MPCD_Q6_PHASE_CURVATURE_DIAGNOSTICS_0493X9B=1
export MPCD_Q6_PHASE_CURVATURE_DIAGNOSTICS_0493X9C=1
export MPCD_Q6_CONTACT_ANGLE_HARD_NORMAL_0493X9I=0
export MPCD_Q6_CONTACT_ANGLE_WALL_FACE_0493X9L=0
export MPCD_Q6_CONTACT_ANGLE_OFFSUPPORT_0493X9M=0

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
export MPCD_X10_KINETIC_INTERFACE_CIC=1
export MPCD_X10_KINETIC_INTERFACE_QUADRATIC=1
export MPCD_X10_KINETIC_INTERFACE_ONE_FOR_ONE=1
export MPCD_X10_KINETIC_INTERFACE_ONE_FOR_ONE_SWAP=1
export MPCD_X10R_Q6_THERMAL_FULL_VECTOR_ENDPOINT_VELOCITY=0
export MPCD_X10S_Q6_THERMAL_SEGMENT_NORMAL_KINEMATICS=0
export MPCD_X10T_Q6_THERMAL_RIGID_TANGENTIAL_KINEMATICS=0
export MPCD_X10_KINETIC_INTERFACE_THERMAL_PHASE_LIMITER=0
export MPCD_X12A_LOCAL_THERMAL_COOLING=1

H="$(awk -v lx="$Lx" -v nx="$NX" 'BEGIN{printf "%.17g",lx/nx}')"
R_PHYS="$(awk -v r="$RADIUS_CELLS" -v h="$H" 'BEGIN{printf "%.17g",r*h}')"
LIQUID_REFERENCE_CELL_MASS="$(awk -v g="$GAMMA" -v m="$LIQUID_MASS" 'BEGIN{printf "%.17g",g*m}')"

preflight() {
  python3 - "$H" "$RADIUS_CELLS" "$SIGMA_TARGET" "$GAMMA" "$KBT" "$LIQUID_MASS" \
              "$MPCD_X12A_LOCAL_THERMAL_RADIUS_CELLS" "$SURFACE_TENSION_MIN_RADIUS_CELLS" \
              "$ACTIVE_STEPS" "$ACTIVE_DUMP_EVERY" "$CHECKPOINT_COUNT" "$PROBE_REPLICATES" "$PROBE_STEPS" <<'PY'
import math,sys
h=float(sys.argv[1]); rc=float(sys.argv[2]); sig=float(sys.argv[3]); gamma=float(sys.argv[4]); kbt=float(sys.argv[5]); m=float(sys.argv[6])
rcool=float(sys.argv[7]); rmin=float(sys.argv[8]); n=int(sys.argv[9]); dump=int(sys.argv[10]); nc=int(sys.argv[11]); nr=int(sys.argv[12]); ps=int(sys.argv[13])
R=rc*h; rho=gamma*m/h**2; pth=gamma*kbt/h**2; dp=sig/R
if rc <= rcool+8: raise SystemExit('[0493x21c] ERROR radius not sufficiently separated from x12a regime')
if rc <= 4*rmin: raise SystemExit('[0493x21c] ERROR radius not sufficiently separated from curvature cutoff')
if dump<=0 or n<3*dump: raise SystemExit('[0493x21c] ERROR active dump cadence/horizon insufficient')
if nc<2 or nr<2 or ps<1 or ps>3: raise SystemExit('[0493x21c] ERROR invalid checkpoint/probe configuration')
print('===== 0493x21c CAPILLARY SHADOW YOUNG-LAPLACE PREFLIGHT =====')
print(f'h={h:.12g} R/h={rc:g} R={R:.12g} wallClearance/h={128-rc:.9g}')
print(f'fluid gamma={gamma:g} alphaSRC=120deg dt=0.0063471328149122585 kBT={kbt:g} mass={m:g}')
print(f'sigmaTarget={sig:g} kappaTheory={1/R:.9g} dpTheory={dp:.9g} pThermal={pth:.9g} dp/pThermal={dp/pth:.6%}')
print(f'R/Rc_x12a={rc/rcool:.6g} R/Rmin={rc/rmin:.6g}')
print(f'activeSteps={n} dumpEvery={dump} checkpoints={nc}')
print(f'shadow protocol={nc} checkpoints x {nr} RNG replicates x 2 sigmas x {ps} steps max')
print('IMPORTANT: sigma=0 exists ONLY as short same-checkpoint shadow; no free sigma=0 baseline is evolved.')
PY
  echo "[0493x21c-nocode] checking existing selected checkpoints and binary identity"
  [[ -s "$SELECTED" ]] || { echo "[0493x21c-nocode] ERROR missing $SELECTED" >&2; exit 2; }
  python3 - "$SELECTED" "$ROOT" <<'PYCHK'
import csv,hashlib,sys
from pathlib import Path
p=Path(sys.argv[1]); root=Path(sys.argv[2])
rows=list(csv.DictReader(p.open(newline='')))
if len(rows)<2: raise SystemExit('[0493x21c-nocode] ERROR need at least 2 selected checkpoints')
for r in rows:
    if int(float(r.get('plateau_found','0'))) != 1:
        raise SystemExit(f"[0493x21c-nocode] ERROR checkpoint {r.get('checkpoint_step')} was not selected from a valid plateau")
    sp=Path(r['state_path'])
    if not sp.is_absolute(): sp=root/sp
    if not sp.is_file(): raise SystemExit(f'[0493x21c-nocode] ERROR missing state {sp}')
    h=hashlib.sha256(sp.read_bytes()).hexdigest()
    if h != r['state_sha256']:
        raise SystemExit(f"[0493x21c-nocode] ERROR state SHA mismatch step={r['checkpoint_step']} expected={r['state_sha256']} got={h}")
print('[0493x21c-nocode] checkpoint hashes PASS: '+' '.join(r['checkpoint_step'] for r in rows))
PYCHK
  local current_sha expected_sha trace_file
  current_sha="$(sha256sum "$BIN" | awk '{print $1}')"
  trace_file="$CAMPAIGN_ROOT/audit/traceability_0493x21c.txt"
  expected_sha=""
  if [[ -s "$trace_file" ]]; then
    expected_sha="$(awk -v b="$BIN" '$2==b {print $1; exit}' "$trace_file" 2>/dev/null || true)"
  fi
  echo "[0493x21c-nocode] binary=$BIN sha256=$current_sha"
  if [[ -n "$expected_sha" ]]; then
    echo "[0493x21c-nocode] active-run binary sha256=$expected_sha"
    [[ "$current_sha" == "$expected_sha" ]] || {
      echo '[0493x21c-nocode] ERROR current binary differs from binary archived by active run' >&2; exit 2;
    }
    echo '[0493x21c-nocode] binary identity with active run: PASS'
  else
    echo '[0493x21c-nocode] WARNING active trace does not expose a binary hash; current hash printed above for archival' >&2
  fi
  echo '[0493x21c-nocode] NO CODE CHANGE / NO BUILD required'
}

prepare_dirs() {
  local r="$1"
  mkdir -p "$r/init" "$r/output" "$r/params" "$r/logs"
}

write_params() {
  local state="$1" out="$2" params="$3" sigma="$4" steps="$5" dump="$6" summary="$7" seed="$8"
  # x21c-fix1: suite_write_common_params_0434 is authoritative for the
  # common cadence keys.  Synchronize the per-run values before calling it;
  # otherwise its default DUMP_STATE_EVERY can silently overwrite the explicit
  # shadow/active cadence written above.
  SEED="$seed"
  SUMMARY_EVERY="$summary"
  DUMP_STATE_EVERY="$dump"
  SUMMARY_ROLE_FILTER=fluid
  DUMP_ROLE_FILTER=fluid
  export SEED SUMMARY_EVERY DUMP_STATE_EVERY SUMMARY_ROLE_FILTER DUMP_ROLE_FILTER
  cat > "$params" <<PARAMS
inputState = $state
outputDir = $out
Lx = $Lx
Ly = $Ly
Nx = $NX
Ny = $NY
dt = $DT
nSteps = $steps
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
wallVpEnable = false
wallAccommodation = 1.0
wallKBT = -1.0
wallThermalNoise = 0.0
surfaceTensionSigma = $sigma
surfaceTensionMinRadiusCells = $SURFACE_TENSION_MIN_RADIUS_CELLS
phaseInterfaceKineticReflectionFraction = 1.0
phaseInterfaceEvaporationTargetType = -1
phaseInterfaceASelector = type:$LIQUID_TYPE
phaseInterfaceBSelector = vacuum
phaseInterfaceContactAngleDegrees = -1
speciesRegistryEnable = true
speciesCount = 1
species0 = $LIQUID_TYPE q6_g_f_liquid liquid 1.0 1.0 $LIQUID_REFERENCE_CELL_MASS
species0ResamplingEnable = false
speciesRequireRegisteredTypes = true
speciesDiagnosticsEnable = false
speciesCellDiagnosticsEnable = false
speciesQ6Enable = true
speciesQ6Mode = free_surface_masked
speciesQ6Sensitivity = 1.0
speciesQ6FallbackMode = common
speciesQ6ComparisonTolerance = 1.0e-11
speciesQ6MinOccupancyFraction = $Q6_GF_MIN_FILL_FRACTION
PARAMS
  suite_write_common_params_0434 "$RUN_MODE" >> "$params"
}

set_livevis() {
  local root="$1" enabled="$2" every="$3"
  LIVE_VIS_ENABLE="$enabled"
  LIVE_VIS_EVERY="$every"
  LIVE_VIS_FIELD="${LIVE_VIS_FIELD:-mass}"
  LIVE_VIS_HOLD_ON_EXIT=0
  LIVE_VIS_RECORD_ENABLE=0
  FILTERED_RECORDING_ENABLE=0
  PARTICLE_TYPE_FILTER="$LIQUID_TYPE"
  OVERWRITE_LIVEVIS_CONTROL=1
  LIVE_VIS_CONTROL_FILE="$root/livevis_control_0493x21c.kv"
  export LIVE_VIS_ENABLE LIVE_VIS_EVERY LIVE_VIS_FIELD LIVE_VIS_HOLD_ON_EXIT LIVE_VIS_RECORD_ENABLE FILTERED_RECORDING_ENABLE PARTICLE_TYPE_FILTER OVERWRITE_LIVEVIS_CONTROL LIVE_VIS_CONTROL_FILE
  suite_prepare_livevis_control_0434 "$root" "$RUN_MODE"
  suite_export_livevis_0434
}

run_probe() {
  local cp_step="$1" state="$2" rep="$3" role="$4" sigma="$5" seed="$6"
  local tag="cp$(printf '%08d' "$cp_step")_rep$(printf '%02d' "$rep")_${role}"
  local root="$SHADOW_ROOT/$tag"
  prepare_dirs "$root"
  local out="$root/output" params="$root/params/${CASE_LABEL}_${tag}.kv" log="$root/logs/${CASE_LABEL}_${tag}.log" tf="$root/logs/${CASE_LABEL}_${tag}.time"

  write_params "$state" "$out" "$params" "$sigma" "$PROBE_STEPS" 0 1 "$seed"
  if [[ "$role" == sigma0 ]]; then export MPCD_X11C_FORCE_X9E_SIGMA0=1; else export MPCD_X11C_FORCE_X9E_SIGMA0=0; fi
  set_livevis "$root" "$LIVE_VIS_ENABLE_PROBE" 1000
  suite_write_env_file_0434 "$root/logs/environment_0493x21c_probe.env" "$RUN_MODE"
  echo "[0493x21c-nocode] PROBE checkpoint=$cp_step rep=$rep role=$role sigma=$sigma seed=$seed state=$state"
  suite_run_binary_0434 "$params" "$log" "$tf" "$out"
  [[ -s "$out/cuda_static_drop_pressure_0493x9e.csv" ]] || { echo "[0493x21c] ERROR missing x9e probe CSV $root" >&2; exit 2; }
  local sha; sha="$(sha256sum "$state" | awk '{print $1}')"
  echo "$cp_step,$rep,$role,$sigma,$seed,$state,$sha,$root" >> "$MANIFEST"
}

run_shadows() {
  [[ -s "$SELECTED" ]] || { echo "[0493x21c-nocode] ERROR selected checkpoints missing" >&2; exit 2; }
  if [[ "$CLEAN_SHADOWS" == 1 ]]; then rm -rf "$SHADOW_ROOT"; fi
  mkdir -p "$SHADOW_ROOT"
  echo 'checkpoint_step,replicate,role,sigma,seed,input_state,input_state_sha256,run_dir' > "$MANIFEST"

  while IFS=, read -r cp_step state _rest; do
    [[ "$cp_step" == checkpoint_step ]] && continue
    [[ -s "$state" ]] || { echo "[0493x21c] ERROR checkpoint state missing: $state" >&2; exit 2; }
    for ((rep=0; rep<PROBE_REPLICATES; ++rep)); do
      seed=$((PROBE_SEED_BASE + 100000 * cp_step + rep))
      run_probe "$cp_step" "$state" "$rep" active "$SIGMA_TARGET" "$seed"
      run_probe "$cp_step" "$state" "$rep" sigma0 0 "$seed"
    done
  done < "$SELECTED"
}

trace() {
  mkdir -p "$CAMPAIGN_ROOT/audit"
  {
    echo campaign=0493x21c_capillary_shadow_young_laplace_nocode
    echo date="$(date -Iseconds 2>/dev/null || true)"
    echo gitHead="$(git rev-parse HEAD 2>/dev/null || echo UNKNOWN)"
    echo gitBranch="$(git branch --show-current 2>/dev/null || echo UNKNOWN)"
    echo gamma="$GAMMA"; echo dt="$DT"; echo kBT="$KBT"; echo liquidMass="$LIQUID_MASS"
    echo rotationAngleRad="$ROTATION_ANGLE"; echo radiusCells="$RADIUS_CELLS"; echo sigmaTarget="$SIGMA_TARGET"
    echo surfaceTensionMinRadiusCells="$SURFACE_TENSION_MIN_RADIUS_CELLS"
    echo x12aRadiusCells="$MPCD_X12A_LOCAL_THERMAL_RADIUS_CELLS"
    echo activeSteps="$ACTIVE_STEPS"; echo activeDumpEvery="$ACTIVE_DUMP_EVERY"
    echo checkpointCount="$CHECKPOINT_COUNT"; echo probeReplicates="$PROBE_REPLICATES"; echo probeSteps="$PROBE_STEPS"
    echo protocol='existing stable checkpoints + same-checkpoint twin restarts; sigma0 never evolved as a long baseline; no source modification; no rebuild'
    echo selectedFile="$SELECTED"
    echo manifest="$MANIFEST"
    for f in "$COLLECTOR" "$ROOT/scripts/src_mpcd_run_common_0434.sh" "$BIN"; do [[ -f "$f" ]] && sha256sum "$f"; done
  } > "$CAMPAIGN_ROOT/audit/traceability_0493x21c_nocode.txt"
}

collect() {
  [[ -s "$MANIFEST" ]] || { echo '[0493x21c-nocode] ERROR shadow manifest missing' >&2; exit 2; }
  python3 "$COLLECTOR" \
    --campaign-root "$CAMPAIGN_ROOT" \
    --manifest "$MANIFEST" \
    --selected "$SELECTED" \
    --shadow-root "$SHADOW_ROOT" \
    --out-dir "$COLLECT_ROOT" \
    --sigma "$SIGMA_TARGET" \
    --expected-replicates "$PROBE_REPLICATES"
  trace
}

case "$MODE" in
  --preflight) preflight ;;
  --shadows) preflight; run_shadows; trace ;;
  --collect) collect ;;
  --run) preflight; run_shadows; collect ;;
esac
