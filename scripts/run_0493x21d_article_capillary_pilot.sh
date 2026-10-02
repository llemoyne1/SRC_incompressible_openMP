#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$ROOT/scripts/src_mpcd_run_common_0434.sh"
suite_root_cd_0434

# 0493x21d — Section 3.4 article pilot.
# One well-resolved static droplet, one seed, nominal x13h fluid.
# Purpose: validate the ARTICLE measurement pipeline (curvature, pL/pG,
# capillary pressure jump, spurious currents, plateau selection) before any
# multi-radius campaign.  No solver modification, no build, no sigma=0 baseline.

CASE_LABEL=article_capillary_pilot_0493x21d
RUN_MODE=src-q6-g-f
TOPOLOGY=closed_box
BIN="${BIN:-build/src_mpcd_base_cuda_q6_resident_livevis_0486}"
GENERATOR="$ROOT/scripts/generate_0493x9s_splash_state.py"
ANALYZER="$ROOT/scripts/analyze_0493x21d_article_capillary_pilot.py"
EXPECTED_BIN_SHA256="${EXPECTED_BIN_SHA256:-ab718f8f61b67959c157b78c05a37a8c7efa3dec7740d862ed12eecacd27090f}"

# Hard no-build policy.  suite_run_binary_0434 may call suite_ensure_binary_0434;
# these values make a stale source irrelevant and forbid compilation.
export FORCE_BUILD=0 AUTO_BUILD=0 BUILD_IF_STALE=0

for f in "$BIN" "$GENERATOR" "$ANALYZER" "$ROOT/scripts/src_mpcd_run_common_0434.sh"; do
  [[ -f "$f" ]] || { echo "[0493x21d] ERROR missing $f" >&2; exit 2; }
done
[[ -x "$BIN" ]] || { echo "[0493x21d] ERROR binary not executable: $BIN" >&2; exit 2; }
ACTUAL_BIN_SHA256="$(sha256sum "$BIN" | awk '{print $1}')"
[[ "$ACTUAL_BIN_SHA256" == "$EXPECTED_BIN_SHA256" ]] || {
  echo "[0493x21d] ERROR qualified binary hash mismatch" >&2
  echo " expected=$EXPECTED_BIN_SHA256" >&2
  echo " actual  =$ACTUAL_BIN_SHA256" >&2
  exit 2
}

# Nominal article fluid / exact qualified x13h chain.
NX="${NX:-256}"; NY="${NY:-256}"; Lx="${Lx:-1.0}"; Ly="${Ly:-1.0}"
GAMMA="${GAMMA:-8}"; DT="${DT:-0.0063471328149122585}"; KBT="${KBT:-0.125}"
LIQUID_TYPE=1; LIQUID_MASS=1.0
ROTATION_ANGLE="${ROTATION_ANGLE:-2.0943951023931953}"
RANDOM_ROTATION_SIGN=true; GRID_SHIFT_ENABLE=true
THERMOSTAT_ENABLE=true; THERMOSTAT_MODE=cell_relative_rescale
THERMOSTAT_EVERY=1; THERMOSTAT_TARGET_KBT="$KBT"; THERMOSTAT_MIN_PARTICLES=3

# Pilot regime: deliberately strong/resolved capillarity, chosen from the
# visually regular R/h=64 regime.  The later sigma sweep will map dependence.
RADIUS_CELLS="${RADIUS_CELLS:-64}"
SIGMA_TARGET="${SIGMA_TARGET:-10000}"
SEED="${SEED:-4932401}"
SURFACE_TENSION_MIN_RADIUS_CELLS="${SURFACE_TENSION_MIN_RADIUS_CELLS:-4}"
MPCD_X12A_LOCAL_THERMAL_RADIUS_CELLS="${MPCD_X12A_LOCAL_THERMAL_RADIUS_CELLS:-25.298221281347036}"
STEPS="${STEPS:-1500}"
SUMMARY_EVERY="${SUMMARY_EVERY:-5}"
DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-100}"
RUN_ROOT="${RUN_ROOT:-runs/0493x21d_article_capillary_pilot_R${RADIUS_CELLS}_s${SIGMA_TARGET}_seed${SEED}}"
CLEAN_RUN_ROOT="${CLEAN_RUN_ROOT:-1}"
LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-1}"
LIVE_VIS_EVERY="${LIVE_VIS_EVERY:-1}"
LIVE_VIS_FIELD="${LIVE_VIS_FIELD:-mass}"
LIVE_VIS_HOLD_ON_EXIT=0
LIVE_VIS_RECORD_ENABLE=0
FILTERED_RECORDING_ENABLE=0
PARTICLE_TYPE_FILTER="$LIQUID_TYPE"
OVERWRITE_LIVEVIS_CONTROL=1
THREADS="${THREADS:-8}"; export OMP_NUM_THREADS="$THREADS"

# Q6-g-f production controls.
PROJECTION_BACKEND=cuda; PROJECTION_OPERATOR=auto_fv_cg
PROJECTION_MAX_ITERATIONS=2000; PROJECTION_TOLERANCE=1.0e-5
PROJECTION_MOMENTUM_CORRECTION_ENABLE=false
Q6_PROJECTION_STRENGTH=1.0; Q6_STRICT=1; Q6_FORCE_PROJECTION_MODE=prestream_single_fused
Q6_GF_EXTERNAL_SPECIES=1; Q6_GF_HAS_GAS_PHASE=0
Q6_GF_DENSITY_RELAXATION_TIME=0.25; Q6_GF_MIN_FILL_FRACTION=0.10
Q6_GF_DENSITY_COMPRESSION_GATE_ENABLE=1
Q6_GF_DENSITY_COMPRESSION_THRESHOLD_PARTICLES=3.0
Q6_GF_DENSITY_TRACTION_THRESHOLD_PARTICLES=6.0
Q6_GF_DENSITY_TRACTION_GAIN=1.0
SPECIES_RESAMPLING_ENABLE=false; LIQUID_RESAMPLING_ENABLE=false; GAS_RESAMPLING_ENABLE=false
VIRIAL_DENSITY_KICK_ENABLE=false; WEIGHTED_RESAMPLING_ENABLE_OVERRIDE=false; CUDA_EMPTY_REFILL_ENABLE_OVERRIDE=false

PARTICLE_MASS="$LIQUID_MASS"; BACKGROUND_TYPE="$LIQUID_TYPE"; INACTIVE_TYPE="$LIQUID_TYPE"
GEN_CASE=tg; U0=0.0; VELOCITY_MODE=zero; TG_HOLE_ENABLE=false

export NX NY Lx Ly GAMMA DT KBT LIQUID_TYPE LIQUID_MASS PARTICLE_MASS BACKGROUND_TYPE INACTIVE_TYPE
export ROTATION_ANGLE RANDOM_ROTATION_SIGN GRID_SHIFT_ENABLE THERMOSTAT_ENABLE THERMOSTAT_MODE THERMOSTAT_EVERY THERMOSTAT_TARGET_KBT THERMOSTAT_MIN_PARTICLES
export PROJECTION_BACKEND PROJECTION_OPERATOR PROJECTION_MAX_ITERATIONS PROJECTION_TOLERANCE PROJECTION_MOMENTUM_CORRECTION_ENABLE
export Q6_PROJECTION_STRENGTH Q6_STRICT Q6_FORCE_PROJECTION_MODE Q6_GF_EXTERNAL_SPECIES Q6_GF_HAS_GAS_PHASE
export Q6_GF_DENSITY_RELAXATION_TIME Q6_GF_MIN_FILL_FRACTION Q6_GF_DENSITY_COMPRESSION_GATE_ENABLE
export Q6_GF_DENSITY_COMPRESSION_THRESHOLD_PARTICLES Q6_GF_DENSITY_TRACTION_THRESHOLD_PARTICLES Q6_GF_DENSITY_TRACTION_GAIN
export SPECIES_RESAMPLING_ENABLE LIQUID_RESAMPLING_ENABLE GAS_RESAMPLING_ENABLE VIRIAL_DENSITY_KICK_ENABLE WEIGHTED_RESAMPLING_ENABLE_OVERRIDE CUDA_EMPTY_REFILL_ENABLE_OVERRIDE
export MPCD_X12A_LOCAL_THERMAL_RADIUS_CELLS
export SUMMARY_EVERY DUMP_STATE_EVERY LIVE_PROGRESS LIVE_VIS_ENABLE LIVE_VIS_EVERY LIVE_VIS_FIELD LIVE_VIS_HOLD_ON_EXIT LIVE_VIS_RECORD_ENABLE FILTERED_RECORDING_ENABLE PARTICLE_TYPE_FILTER OVERWRITE_LIVEVIS_CONTROL

suite_defaults_common_0434
suite_compute_derived_0434
suite_export_cuda_flags_0434 "$RUN_MODE" "$TOPOLOGY"

# Exact free-surface/capillary diagnostic + kinetic closure chain.
export MPCD_Q6_PHASE_GEOMETRY_RESIDENT_0493X6C=1
export MPCD_Q6_PHASE_GEOMETRY_CUTFACE_0493X6D=0
export MPCD_Q6_PHASE_INTERFACE_TOPOLOGY_0493X6E=1
export MPCD_Q6_PHASE_INTERFACE_STENCIL_0493X6F=1
export MPCD_Q6_PHASE_GAS_PRESSURE_0493X6G=0
export MPCD_Q6_PHASE_GAS_PRESSURE_CONSTANT_0493X6G=0
export MPCD_Q6_PHASE_GAS_PRESSURE_REFERENCE_0493X6G=0
export MPCD_Q6_PHASE_GAS_PRESSURE_SCALE_0493X6G=0
export MPCD_Q6_FACE_TO_PARTICLE_RT0_0493X6H_B1=1
export MPCD_Q6_STATIC_DROP_DIAGNOSTICS_0493X9E=1
export MPCD_Q6_ELLIPSE_DIAGNOSTICS_0493X9F=1
export MPCD_Q6_PHASE_CURVATURE_DIAGNOSTICS_0493X9A=0
export MPCD_Q6_PHASE_CURVATURE_DIAGNOSTICS_0493X9B=1
export MPCD_Q6_PHASE_CURVATURE_DIAGNOSTICS_0493X9C=1
export MPCD_Q6_CONTACT_ANGLE_HARD_NORMAL_0493X9I=0
export MPCD_Q6_CONTACT_ANGLE_WALL_FACE_0493X9L=0
export MPCD_Q6_CONTACT_ANGLE_OFFSUPPORT_0493X9M=0
export MPCD_X10J_SIMPLE_SPECULAR_ABLATION=0 MPCD_X10K_LOCAL_FRAME_SPECULAR_ABLATION=0 MPCD_X10M_MOVING_INTERFACE_WALL=0 MPCD_X10N_Q6_CONTINUOUS_INTERFACE_WALL=0
export MPCD_X10O_Q6_THERMAL_INTERFACE_WALL=1 MPCD_X10O_THERMAL_PARTICLE_MASS="$LIQUID_MASS" MPCD_X10O_THERMAL_SIGMAS=3.0 MPCD_X10O_THERMAL_MAX_CELLS=0.75
export MPCD_X10P_INITIAL_OVERLAP_RESOLUTION=1 MPCD_X10_KINETIC_INTERFACE_CIC=1 MPCD_X10_KINETIC_INTERFACE_QUADRATIC=1
export MPCD_X10_KINETIC_INTERFACE_ONE_FOR_ONE=1 MPCD_X10_KINETIC_INTERFACE_ONE_FOR_ONE_SWAP=1
export MPCD_X10R_Q6_THERMAL_FULL_VECTOR_ENDPOINT_VELOCITY=0 MPCD_X10S_Q6_THERMAL_SEGMENT_NORMAL_KINEMATICS=0 MPCD_X10T_Q6_THERMAL_RIGID_TANGENTIAL_KINEMATICS=0
export MPCD_X10_KINETIC_INTERFACE_THERMAL_PHASE_LIMITER=0 MPCD_X12A_LOCAL_THERMAL_COOLING=1
export MPCD_X11C_FORCE_X9E_SIGMA0=0

H="$(awk -v lx="$Lx" -v nx="$NX" 'BEGIN{printf "%.17g",lx/nx}')"
R_PHYS="$(awk -v r="$RADIUS_CELLS" -v h="$H" 'BEGIN{printf "%.17g",r*h}')"
LIQUID_REFERENCE_CELL_MASS="$(awk -v g="$GAMMA" -v m="$LIQUID_MASS" 'BEGIN{printf "%.17g",g*m}')"

python3 - "$H" "$RADIUS_CELLS" "$SIGMA_TARGET" "$GAMMA" "$KBT" <<'PY'
import sys,math
h,rc,sig,g,k=map(float,sys.argv[1:])
R=rc*h; pth=g*k/h**2; dp=sig/R
print('===== 0493x21d SECTION 3.4 PILOT PREFLIGHT =====')
print(f'R/h={rc:g} R={R:.9g} sigma={sig:g} kappa_th={1/R:.9g}')
print(f'dp_Laplace={dp:.9g} pThermal={pth:.9g} dp/pThermal={dp/pth:.3%}')
print('fluid=nominal x13h: gamma=8, alphaSRC=120deg, kBT=0.125, lambda/h=0.72')
print('outputs=x9e pressure+velocity, x9f shape, x9r limiter, state dumps')
print('buildPolicy=HARD_NO_BUILD')
PY

if [[ "$CLEAN_RUN_ROOT" == 1 ]]; then rm -rf "$RUN_ROOT"; fi
mkdir -p "$RUN_ROOT"/{init,output,params,logs,analysis,audit}
STATE="$RUN_ROOT/init/${CASE_LABEL}.smpcd"
PARAMS="$RUN_ROOT/params/${CASE_LABEL}.kv"
LOG="$RUN_ROOT/logs/${CASE_LABEL}.log"
TF="$RUN_ROOT/logs/${CASE_LABEL}.time"

python3 "$GENERATOR" --output "$STATE" --target wall --Lx "$Lx" --Ly "$Ly" --nx "$NX" --ny "$NY" \
  --gamma "$GAMMA" --drop-center-x 0.5 --drop-center-y 0.5 --drop-radius "$R_PHYS" \
  --drop-vx 0 --drop-vy 0 --puddle-depth 0 --liquid-type "$LIQUID_TYPE" --liquid-mass "$LIQUID_MASS" --kBT "$KBT" --seed "$SEED"

cat > "$PARAMS" <<PARAMS
inputState = $STATE
outputDir = $RUN_ROOT/output
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
wallVpEnable = false
wallAccommodation = 1.0
wallKBT = -1.0
wallThermalNoise = 0.0
surfaceTensionSigma = $SIGMA_TARGET
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
suite_write_common_params_0434 "$RUN_MODE" >> "$PARAMS"

LIVE_VIS_CONTROL_FILE="$RUN_ROOT/livevis_control_0493x21d.kv"; export LIVE_VIS_CONTROL_FILE
suite_prepare_livevis_control_0434 "$RUN_ROOT" "$RUN_MODE"
suite_export_livevis_0434
suite_write_env_file_0434 "$RUN_ROOT/logs/environment_0493x21d.env" "$RUN_MODE"

echo "[0493x21d] RUN root=$RUN_ROOT"
echo "[0493x21d] binary=$BIN sha256=$ACTUAL_BIN_SHA256"
suite_run_binary_0434 "$PARAMS" "$LOG" "$TF" "$RUN_ROOT/output"

for f in cuda_static_drop_pressure_0493x9e.csv cuda_static_drop_velocity_0493x9e.csv cuda_surface_tension_limiter_0493x9r.csv; do
  [[ -s "$RUN_ROOT/output/$f" ]] || { echo "[0493x21d] ERROR missing $f" >&2; exit 2; }
done
python3 "$ANALYZER" "$RUN_ROOT"

{
  echo campaign=0493x21d_article_capillary_pilot
  echo date="$(date -Iseconds 2>/dev/null || true)"
  echo gitHead="$(git rev-parse HEAD 2>/dev/null || echo UNKNOWN)"
  echo gitBranch="$(git branch --show-current 2>/dev/null || echo UNKNOWN)"
  echo binary="$BIN"
  echo binarySha256="$ACTUAL_BIN_SHA256"
  echo radiusCells="$RADIUS_CELLS"
  echo sigmaTarget="$SIGMA_TARGET"
  echo seed="$SEED"
  echo steps="$STEPS"
  echo summaryEvery="$SUMMARY_EVERY"
  echo dumpStateEvery="$DUMP_STATE_EVERY"
  echo buildPolicy=FORCE_BUILD0_AUTO_BUILD0_BUILD_IF_STALE0
  sha256sum "$ANALYZER" "$GENERATOR" "$ROOT/scripts/src_mpcd_run_common_0434.sh" "$BIN"
} > "$RUN_ROOT/audit/capillary_pilot_traceability_0493x21d.txt"

echo "[0493x21d] DONE"
echo "[0493x21d] return: $RUN_ROOT/analysis/capillary_pilot_report_0493x21d.txt"
echo "[0493x21d]         $RUN_ROOT/analysis/capillary_pilot_realization_0493x21d.csv"
