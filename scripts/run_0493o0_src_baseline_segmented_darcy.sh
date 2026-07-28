#!/usr/bin/env bash
set -euo pipefail

# 0493o0 -- SRC-only general-capability baseline.
# Segmented inlet/outlet, external solid walls, and a file-driven Darcy/chi
# obstacle. No Q6. Mutating resampling is disabled by default; setting
# SUPPORT_REPAIR_ENABLE=true activates the current 0493o1/0493o3 split-only
# target-driven Neff support repair. Passive support, geometry, Darcy and
# topology diagnostics remain enabled in both modes.

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$ROOT/scripts/src_mpcd_run_common_0434.sh"
suite_root_cd_0434

CASE_LABEL="0493o0_src_baseline_segmented_darcy"
GEN_CASE="vk"
TOPOLOGY="segmented"
MODE="src"

# One runner-level switch only.  The enabled path is deliberately constrained
# to the validated local split-only support repair: no refill, extraction,
# remap, mass guard, thermal renormalization or legacy population mutation.
SUPPORT_REPAIR_ENABLE="${SUPPORT_REPAIR_ENABLE:-false}"
if suite_truthy_0434 "$SUPPORT_REPAIR_ENABLE"; then
  SUPPORT_REPAIR_ENABLE=true
else
  SUPPORT_REPAIR_ENABLE=false
fi

Lx="${Lx:-1.0}"
Ly="${Ly:-1.0}"
NX="${NX:-128}"
NY="${NY:-128}"
GAMMA="${GAMMA:-20}"
STEPS="${STEPS:-5000}"
DT="${DT:-0.001}"
KBT="${KBT:-0.001}"
U0="${U0:-0.15}"
SEED="${SEED:-493002}"
VELOCITY_MODE="${VELOCITY_MODE:-zero}"
ROTATION_ANGLE="${ROTATION_ANGLE:-1.5707963267948966}"
THERMOSTAT_ENABLE="${THERMOSTAT_ENABLE:-true}"
THERMOSTAT_MODE="${THERMOSTAT_MODE:-cell_relative_rescale}"
THERMOSTAT_EVERY="${THERMOSTAT_EVERY:-1}"
THERMOSTAT_TARGET_KBT="${THERMOSTAT_TARGET_KBT:--1.0}"

CYLINDER_CX="${CYLINDER_CX:-0.50}"
CYLINDER_CY="${CYLINDER_CY:-0.50}"
CYLINDER_R="${CYLINDER_R:-0.12}"
SKIP_SOLID_CELLS="${SKIP_SOLID_CELLS:-true}"
SKIP_SOLID_PARTICLES="${SKIP_SOLID_PARTICLES:-true}"

INLET_FACE="${INLET_FACE:-left}"
INLET_SMIN="${INLET_SMIN:-0.70}"
INLET_SMAX="${INLET_SMAX:-1.00}"
OUTLET_FACE="${OUTLET_FACE:-right}"
OUTLET_SMIN="${OUTLET_SMIN:-0.00}"
OUTLET_SMAX="${OUTLET_SMAX:-0.30}"
OUTLET_MODE="${OUTLET_MODE:-neumann}"
INLET_RAMP_END_TIME="${INLET_RAMP_END_TIME:-0.25}"
INLET_RAMP_INITIAL_FACTOR="${INLET_RAMP_INITIAL_FACTOR:-0.2}"
INLET_RESERVOIR_CELLS="${INLET_RESERVOIR_CELLS:-3}"

ALPHA="${ALPHA:-8000.0}"
ALPHA_MIN="${ALPHA_MIN:-0.0}"
DARCY_Q="${DARCY_Q:-0.1}"
DARCY_INITIAL_DEACTIVATE_BELOW_CHI="${DARCY_INITIAL_DEACTIVATE_BELOW_CHI:-0.05}"
DARCY_BRINKMAN_FORCING_MODE="${DARCY_BRINKMAN_FORCING_MODE:-mean_outward_bath}"
DARCY_CHI_COLLISION_VP_ENABLE="${DARCY_CHI_COLLISION_VP_ENABLE:-true}"
DARCY_CHI_COLLISION_VP_MODE="${DARCY_CHI_COLLISION_VP_MODE:-interface_band}"
TOPO_BENCHMARK_ENABLE="${TOPO_BENCHMARK_ENABLE:-true}"
TOPO_BENCHMARK_FORCE_ENABLE="${TOPO_BENCHMARK_FORCE_ENABLE:-true}"
TOPO_BENCHMARK_DRAG_LIFT_ENABLE="${TOPO_BENCHMARK_DRAG_LIFT_ENABLE:-true}"

SUMMARY_EVERY="${SUMMARY_EVERY:-50}"
DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-100}"
DARCY_COST_EVERY="${DARCY_COST_EVERY:-$SUMMARY_EVERY}"
TOPO_BENCHMARK_EVERY="${TOPO_BENCHMARK_EVERY:-$SUMMARY_EVERY}"
THREADS="${THREADS:-8}"
INACTIVE_SLOTS_PER_CELL="${INACTIVE_SLOTS_PER_CELL:-8}"
INACTIVE_SLOTS="${INACTIVE_SLOTS:-$((NX * NY * INACTIVE_SLOTS_PER_CELL))}"
if [[ "$SUPPORT_REPAIR_ENABLE" == true ]]; then
  DEFAULT_BASE_RUN_ROOT="runs/0493o0_src_support_repair/segmented_darcy"
else
  DEFAULT_BASE_RUN_ROOT="runs/0493o0_src_baseline_dual_bench/segmented_darcy"
fi
BASE_RUN_ROOT="${BASE_RUN_ROOT:-$DEFAULT_BASE_RUN_ROOT}"
RUN_ROOT="${RUN_ROOT:-$BASE_RUN_ROOT}"
CLEAN_RUN_ROOT="${CLEAN_RUN_ROOT:-1}"

# The repository-root control file is mandatory for every runner.
LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-1}"
LIVE_VIS_CONTROL_FILE="$ROOT/livevis_control.kv"
LIVE_VIS_FIELD="${LIVE_VIS_FIELD:-ux}"
LIVE_VIS_EVERY="${LIVE_VIS_EVERY:-10}"
LIVE_VIS_NX="${LIVE_VIS_NX:-$NX}"
LIVE_VIS_NY="${LIVE_VIS_NY:-$NY}"
LIVE_VIS_COLORMAP="${LIVE_VIS_COLORMAP:-thermal}"
LIVE_VIS_CLIP="${LIVE_VIS_CLIP:--1}"
LIVE_VIS_GAIN="${LIVE_VIS_GAIN:-1.0}"
LIVE_VIS_SMOOTH_PASSES="${LIVE_VIS_SMOOTH_PASSES:-1}"
LIVE_VIS_HOLD_ON_EXIT="${LIVE_VIS_HOLD_ON_EXIT:-1}"
OVERWRITE_LIVEVIS_CONTROL="${OVERWRITE_LIVEVIS_CONTROL:-0}"
FILTERED_RECORDING_ENABLE="${FILTERED_RECORDING_ENABLE:-1}"
RECORD_ENABLE="${RECORD_ENABLE:-true}"
if [[ "$SUPPORT_REPAIR_ENABLE" == true ]]; then
  DEFAULT_RECORD_SESSION_PREFIX="0493o0_src_support_repair"
else
  DEFAULT_RECORD_SESSION_PREFIX="0493o0_src_baseline"
fi
RECORD_SESSION_PREFIX="${RECORD_SESSION_PREFIX:-$DEFAULT_RECORD_SESSION_PREFIX}"
RECORD_FIELDS="${RECORD_FIELDS:-rho,ux,uy}"
RECORD_EVERY="${RECORD_EVERY:-$DUMP_STATE_EVERY}"
RECORD_STRIDE="${RECORD_STRIDE:-1}"

RESAMPLING_SURVEY_EVERY="${RESAMPLING_SURVEY_EVERY:-$SUMMARY_EVERY}"
FLAG_EVERY="${FLAG_EVERY:-25}"
SUPPORT_TRIGGER_NMIN="${SUPPORT_TRIGGER_NMIN:-$(( (3 * GAMMA + 4) / 5 ))}"
OUTLIER_U_THRESHOLD="${OUTLIER_U_THRESHOLD:-1.0}"

# Reuse the already-established population parameters.  These defaults match
# the validated mono-species TG support-repair configuration; callers may still
# override the existing GUARD_N* variables.
if [[ "$SUPPORT_REPAIR_ENABLE" == true ]]; then
  GUARD_NMIN="${GUARD_NMIN:-10}"
  GUARD_NTARGET="${GUARD_NTARGET:-12}"
  GUARD_NMAX="${GUARD_NMAX:-32}"
fi

suite_defaults_common_0434
suite_compute_derived_0434

TARGET_CELL_MASS="$(python3 - "$GAMMA" "$PARTICLE_MASS" <<'PY_MASS'
import sys
gamma = float(sys.argv[1])
particle_mass = float(sys.argv[2])
print(gamma * particle_mass)
PY_MASS
)"

# Resolve the exact current support-repair path before writing params.  The χ
# filter reuses the Darcy deactivation threshold, so no new physical threshold
# is introduced.
if [[ "$SUPPORT_REPAIR_ENABLE" == true ]]; then
  WEIGHTED_RESAMPLING_ENABLE_OVERRIDE=true
  CUDA_EMPTY_REFILL_ENABLE_OVERRIDE=false
  RESAMPLING_INSERTION_ENABLE=true
  RESAMPLING_EXTRACTION_ENABLE=false
  RESAMPLING_REMAP_ENABLE=false
  RESAMPLING_MASS_GUARD_ENABLE=false
  RESAMPLING_THERMAL_RENORMALIZATION_ENABLE=false
  CUDA_RESAMPLING_CHI_FILTER_ENABLE=true
  CUDA_RESAMPLING_CHI_MIN="${CUDA_RESAMPLING_CHI_MIN:-$DARCY_INITIAL_DEACTIVATE_BELOW_CHI}"
  SPECIES0_RESAMPLING_ENABLE=true
else
  WEIGHTED_RESAMPLING_ENABLE_OVERRIDE=false
  CUDA_EMPTY_REFILL_ENABLE_OVERRIDE=false
  RESAMPLING_INSERTION_ENABLE=false
  RESAMPLING_EXTRACTION_ENABLE=false
  RESAMPLING_REMAP_ENABLE=false
  RESAMPLING_MASS_GUARD_ENABLE=false
  RESAMPLING_THERMAL_RENORMALIZATION_ENABLE=false
  CUDA_RESAMPLING_CHI_FILTER_ENABLE=false
  SPECIES0_RESAMPLING_ENABLE=false
fi

suite_prepare_dirs_0434 "$RUN_ROOT"

STATE="$RUN_ROOT/init/${CASE_LABEL}_${NX}x${NY}_g${GAMMA}.smpcd"
CHI="$RUN_ROOT/chi/${CASE_LABEL}_${NX}x${NY}_chi_f32.f32"
PARAMS="$RUN_ROOT/params/${CASE_LABEL}.kv"
OUT="$RUN_ROOT/output"
LOG="$RUN_ROOT/logs/${CASE_LABEL}.log"
TIME="$RUN_ROOT/logs/${CASE_LABEL}.time"
mkdir -p "$OUT"

suite_generate_case_0434 "$STATE" "$CHI"

cat > "$PARAMS" <<PARAMS
inputState = ${STATE}
outputDir = ${OUT}
Lx = ${Lx}
Ly = ${Ly}
Nx = ${NX}
Ny = ${NY}
dt = ${DT}
nSteps = ${STEPS}
bcLeft = solid
bcRight = solid
bcBottom = solid
bcTop = solid
bcX = solid
bcY = solid
openBoundarySegmentsEnable = true
openBoundarySegmentCount = 2
openBoundarySegment0 = ${INLET_FACE} inlet ${INLET_SMIN} ${INLET_SMAX} ${U0} 0.0 ${BACKGROUND_TYPE} ${PARTICLE_MASS}
openBoundarySegment1 = ${OUTLET_FACE} outlet ${OUTLET_SMIN} ${OUTLET_SMAX} ${U0} 0.0 ${BACKGROUND_TYPE} ${PARTICLE_MASS}
inletVelocityRampEnable = true
inletVelocityRampStartTime = 0.0
inletVelocityRampEndTime = ${INLET_RAMP_END_TIME}
inletVelocityRampInitialFactor = ${INLET_RAMP_INITIAL_FACTOR}
inletVelocityRampFinalFactor = 1.0
inletVelocityRampProfile = smoothstep
inletVelocitySpatialProfile = uniform
inletKBT = -1.0
inletThermalNoise = 0.0
inletInjectionMode = hard_cell_density
inletReservoirMode = hard_cell_density
inletReservoirCells = ${INLET_RESERVOIR_CELLS}
inletTargetOccupancy = ${GAMMA}
inletHardCellVelocityMean = true
inletHardCellThermalRescale = true
inletRandomizeTangential = true
inletReinjectBackflow = true
openBoundaryOutletMode = ${OUTLET_MODE}
openBoundaryOutletHybridBlend = 0.0
openBoundaryOutletFeedbackGain = 0.0
wallAccommodation = 1.0
wallVpEnable = true
wallVpMode = stochastic_fraction
wallVpGamma = ${GAMMA}
wallVpMass = ${PARTICLE_MASS}
wallVpKBT = -1.0
wallKBT = -1.0
wallThermalNoise = 0.0
bodyAccelerationX = 0.0
bodyAccelerationY = 0.0

# The current local support repair always deposits by cell and registered
# species, including mono-species cases.  Keeping the registry present in the
# baseline makes paired off/on comparisons differ only by the repair switch.
speciesRegistryEnable = true
speciesCount = 1
species0 = ${BACKGROUND_TYPE} segmented_darcy_mono unspecified 1.0 1.0 ${TARGET_CELL_MASS}
species0ResamplingEnable = ${SPECIES0_RESAMPLING_ENABLE}
speciesRequireRegisteredTypes = true
speciesDiagnosticsEnable = false
speciesCellDiagnosticsEnable = false

$(suite_write_common_params_0434 "$MODE")
$(suite_write_darcy_params_0434 "$CHI")
PARAMS

suite_export_cuda_flags_0434 "$MODE" "$TOPOLOGY"

# Passive support and geometry diagnostics.  Legacy/competing mutating bricks
# remain off even when the local split-only support repair is enabled.
export MPCD_CUDA_RESAMPLING_SUPPORT_SURVEY_0295=1
export MPCD_CUDA_RESAMPLING_SUPPORT_SURVEY_0295_EVERY="$RESAMPLING_SURVEY_EVERY"
export MPCD_CUDA_RESAMPLING_SUPPORT_SURVEY_0295_MODE=full
export MPCD_CUDA_RESAMPLING_ADAPTIVE_FLAG_0304=1
export MPCD_CUDA_RESAMPLING_ADAPTIVE_FLAG_0304_EVERY="$FLAG_EVERY"
export MPCD_CUDA_RESAMPLING_ADAPTIVE_FLAG_0304_TRIGGER_NMIN="$SUPPORT_TRIGGER_NMIN"
export MPCD_CUDA_RESAMPLING_ADAPTIVE_FLAG_0304_TRIGGER_EMPTY=1
export MPCD_CUDA_RESAMPLING_GEOMETRY_DIAG_0305_HIGH_U="$OUTLIER_U_THRESHOLD"
export MPCD_CUDA_RESAMPLING_OUTLIER_0306_U_THRESHOLD="$OUTLIER_U_THRESHOLD"
export MPCD_INTERNAL_PROFILES="${MPCD_INTERNAL_PROFILES:-1}"
export MPCD_CUDA_RESIDENT_PROFILE_0266="${MPCD_CUDA_RESIDENT_PROFILE_0266:-1}"
export MPCD_CUDA_RESAMPLING_MASS_RECONDITION_0296=0
export MPCD_CUDA_RESAMPLING_EMPTY_REFILL_0319=0
export MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297=0
export MPCD_CUDA_RESAMPLING_PIPELINE_APPLY_0448=0

suite_prepare_livevis_control_0434 "$RUN_ROOT" "$MODE"
[[ "$LIVE_VIS_CONTROL_FILE" == "$ROOT/livevis_control.kv" ]] || {
  echo "[0493o0-general] ERROR livevis control escaped repository root: $LIVE_VIS_CONTROL_FILE" >&2
  exit 2
}
suite_export_livevis_0434
suite_write_env_file_0434 "$RUN_ROOT/logs/environment_0493o0.env" "$MODE"
cat >> "$RUN_ROOT/logs/environment_0493o0.env" <<META
MPCD_INTERNAL_PROFILES=${MPCD_INTERNAL_PROFILES}
MPCD_CUDA_RESIDENT_PROFILE_0266=${MPCD_CUDA_RESIDENT_PROFILE_0266}
SUPPORT_REPAIR_ENABLE=${SUPPORT_REPAIR_ENABLE}
WEIGHTED_RESAMPLING_ENABLE_OVERRIDE=${WEIGHTED_RESAMPLING_ENABLE_OVERRIDE}
RESAMPLING_INSERTION_ENABLE=${RESAMPLING_INSERTION_ENABLE}
RESAMPLING_EXTRACTION_ENABLE=${RESAMPLING_EXTRACTION_ENABLE}
RESAMPLING_REMAP_ENABLE=${RESAMPLING_REMAP_ENABLE}
CUDA_RESAMPLING_CHI_FILTER_ENABLE=${CUDA_RESAMPLING_CHI_FILTER_ENABLE}
CUDA_RESAMPLING_CHI_MIN=${CUDA_RESAMPLING_CHI_MIN}
GUARD_NMIN=${GUARD_NMIN}
GUARD_NTARGET=${GUARD_NTARGET}
GUARD_NMAX=${GUARD_NMAX}
RESAMPLING_SURVEY_EVERY=${RESAMPLING_SURVEY_EVERY}
FLAG_EVERY=${FLAG_EVERY}
SUPPORT_TRIGGER_NMIN=${SUPPORT_TRIGGER_NMIN}
INLET_SEGMENT=${INLET_FACE}:${INLET_SMIN}:${INLET_SMAX}
OUTLET_SEGMENT=${OUTLET_FACE}:${OUTLET_SMIN}:${OUTLET_SMAX}
META

printf '[0493o0-general] SRC-only segmented inlet/outlet + walls + Darcy/chi\n'
printf '[0493o0-general] supportRepair=%s speciesType=%s targetCellMass=%s Nmin=%s Ntarget=%s Nmax=%s chiFilter=%s chiMin=%s\n' \
  "$SUPPORT_REPAIR_ENABLE" "$BACKGROUND_TYPE" "$TARGET_CELL_MASS" \
  "$GUARD_NMIN" "$GUARD_NTARGET" "$GUARD_NMAX" \
  "$CUDA_RESAMPLING_CHI_FILTER_ENABLE" "$CUDA_RESAMPLING_CHI_MIN"
printf '[0493o0-general] grid=%sx%s gamma=%s active~%s inactive=%s steps=%s dt=%s\n' \
  "$NX" "$NY" "$GAMMA" "$((NX * NY * GAMMA))" "$INACTIVE_SLOTS" "$STEPS" "$DT"
printf '[0493o0-general] segments=%s:[%s,%s] -> %s:[%s,%s] U0=%s\n' \
  "$INLET_FACE" "$INLET_SMIN" "$INLET_SMAX" "$OUTLET_FACE" "$OUTLET_SMIN" "$OUTLET_SMAX" "$U0"
printf '[0493o0-general] chi=%s cylinder=(%s,%s,r=%s) alpha=%s mode=%s\n' \
  "$CHI" "$CYLINDER_CX" "$CYLINDER_CY" "$CYLINDER_R" "$ALPHA" "$DARCY_BRINKMAN_FORCING_MODE"
printf '[0493o0-general] live_progress=%s livevis=%s control=%s every=%s\n' \
  "$LIVE_PROGRESS" "$LIVE_VIS_ENABLE" "$LIVE_VIS_CONTROL_FILE" "$LIVE_VIS_EVERY"
printf '[0493o0-general] summaryEvery=%s dumpEvery=%s surveyEvery=%s flagEvery=%s\n' \
  "$SUMMARY_EVERY" "$DUMP_STATE_EVERY" "$RESAMPLING_SURVEY_EVERY" "$FLAG_EVERY"

suite_run_binary_0434 "$PARAMS" "$LOG" "$TIME" "$OUT"
