#!/usr/bin/env bash
set -euo pipefail

# 0493w2 -- calibrated SRC/SRC+Q6 segmented-Darcy cylinder reference.
#
# Purpose:
#   - replay the segmented inlet/outlet + Darcy/chi cylinder on the physically
#     calibrated SRC fluid a256_dt002_k125;
#   - compare the native SRC dynamics with the optional Q6 incompressible
#     projection, while keeping resampling, empty refill, mass reconditioning
#     and support repair strictly inactive;
#   - retain passive support/population diagnostics so cell depletion can be
#     quantified before selecting any repair strategy.
#
# Reference fluid (0493w1, 128^2 multi-seed ensemble at a=1/256):
#   nu = 5.9751e-4, cs = 0.35459, Dself = 1.6588e-4, Sc ~= 3.60.
# With U0=0.1064 and cylinder diameter D=0.24:
#   Re ~= 42.74, Ma ~= 0.3001.
#
# The 1x1 obstacle domain therefore uses 256x256 cells to preserve a=1/256.
# The historical severe topology is retained: a short upper-left inlet,
# a short lower-right outlet and a centered Darcy/chi cylinder.

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$ROOT/scripts/src_mpcd_run_common_0434.sh"
suite_root_cd_0434

CASE_LABEL="0493w2_src_calibrated_segmented_darcy_reference"
GEN_CASE="vk"
TOPOLOGY="segmented"
MODE="${MODE:-src}"

case "$MODE" in
  src)
    Q6_STATE=off
    ;;
  src-q6)
    Q6_STATE=on
    ;;
  *)
    printf '[0493w2] ERROR unsupported MODE=%s; expected src or src-q6\n' \
      "$MODE" >&2
    exit 2
    ;;
esac

# Calibrated SRC fluid and target obstacle regime.
Lx="${Lx:-1.0}"
Ly="${Ly:-1.0}"
NX="${NX:-256}"
NY="${NY:-256}"
GAMMA="${GAMMA:-20}"
STEPS="${STEPS:-12000}"
DT="${DT:-0.002}"
KBT="${KBT:-0.125}"
U0="${U0:-0.1064}"
SEED="${SEED:-493202}"
PARTICLE_MASS="${PARTICLE_MASS:-1.0}"
VELOCITY_MODE="${VELOCITY_MODE:-uniform_x}"
ROTATION_ANGLE="${ROTATION_ANGLE:-1.5707963267948966}"
RANDOM_ROTATION_SIGN="${RANDOM_ROTATION_SIGN:-true}"
GRID_SHIFT_ENABLE="${GRID_SHIFT_ENABLE:-true}"
THERMOSTAT_ENABLE="${THERMOSTAT_ENABLE:-true}"
THERMOSTAT_MODE="${THERMOSTAT_MODE:-cell_relative_rescale}"
THERMOSTAT_EVERY="${THERMOSTAT_EVERY:-1}"
THERMOSTAT_TARGET_KBT="${THERMOSTAT_TARGET_KBT:-$KBT}"
THERMOSTAT_MIN_PARTICLES="${THERMOSTAT_MIN_PARTICLES:-3}"

# 0493w1 measured reference properties, used only for reporting and audit.
REFERENCE_NU="${REFERENCE_NU:-0.00059751}"
REFERENCE_CS="${REFERENCE_CS:-0.35459}"
REFERENCE_DSELF="${REFERENCE_DSELF:-0.00016588}"
REFERENCE_SC="${REFERENCE_SC:-3.60}"
CHARACTERISTIC_L="${CHARACTERISTIC_L:-0.24}"
STAT_WARMUP_STEPS="${STAT_WARMUP_STEPS:-5000}"

# Cylinder geometry retained from the 0493o reference.
CYLINDER_CX="${CYLINDER_CX:-0.50}"
CYLINDER_CY="${CYLINDER_CY:-0.50}"
CYLINDER_R="${CYLINDER_R:-0.12}"
SKIP_SOLID_CELLS="${SKIP_SOLID_CELLS:-true}"
SKIP_SOLID_PARTICLES="${SKIP_SOLID_PARTICLES:-true}"

# Historical staggered segmented openings used by the reference case:
# high left inlet [0.70,1.00] and low right outlet [0.00,0.30].
INLET_FACE="${INLET_FACE:-left}"
INLET_SMIN="${INLET_SMIN:-0.70}"
INLET_SMAX="${INLET_SMAX:-1.00}"
OUTLET_FACE="${OUTLET_FACE:-right}"
OUTLET_SMIN="${OUTLET_SMIN:-0.00}"
OUTLET_SMAX="${OUTLET_SMAX:-0.30}"
OUTLET_MODE="${OUTLET_MODE:-neumann}"
INLET_RAMP_END_TIME="${INLET_RAMP_END_TIME:-0.25}"
INLET_RAMP_INITIAL_FACTOR="${INLET_RAMP_INITIAL_FACTOR:-1.0}"

# Six cells preserve approximately the former physical reservoir thickness
# (3 cells at a=1/128) after refinement to a=1/256.
INLET_RESERVOIR_CELLS="${INLET_RESERVOIR_CELLS:-6}"

# Preserve the former dimensionless Darcy damping alpha*dt = 8:
# old alpha=8000 at dt=0.001 -> new alpha=4000 at dt=0.002.
ALPHA="${ALPHA:-4000.0}"
ALPHA_MIN="${ALPHA_MIN:-0.0}"
DARCY_Q="${DARCY_Q:-0.1}"
DARCY_INITIAL_DEACTIVATE_BELOW_CHI="${DARCY_INITIAL_DEACTIVATE_BELOW_CHI:-0.05}"
DARCY_BRINKMAN_FORCING_MODE="${DARCY_BRINKMAN_FORCING_MODE:-mean_outward_bath}"
DARCY_CHI_COLLISION_VP_ENABLE="${DARCY_CHI_COLLISION_VP_ENABLE:-true}"
DARCY_CHI_COLLISION_VP_MODE="${DARCY_CHI_COLLISION_VP_MODE:-interface_band}"
DARCY_CHI_COLLISION_VP_GAMMA="${DARCY_CHI_COLLISION_VP_GAMMA:-$GAMMA}"
DARCY_CHI_COLLISION_VP_LAYERS="${DARCY_CHI_COLLISION_VP_LAYERS:-2}"
TOPO_BENCHMARK_ENABLE="${TOPO_BENCHMARK_ENABLE:-true}"
TOPO_BENCHMARK_FORCE_ENABLE="${TOPO_BENCHMARK_FORCE_ENABLE:-true}"
TOPO_BENCHMARK_DRAG_LIFT_ENABLE="${TOPO_BENCHMARK_DRAG_LIFT_ENABLE:-true}"

# Regular scalar/field outputs, but only sparse full particle dumps.
SUMMARY_EVERY="${SUMMARY_EVERY:-50}"
DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-2000}"
DARCY_COST_EVERY="${DARCY_COST_EVERY:-$SUMMARY_EVERY}"
TOPO_BENCHMARK_EVERY="${TOPO_BENCHMARK_EVERY:-$SUMMARY_EVERY}"
THREADS="${THREADS:-8}"
INACTIVE_SLOTS_PER_CELL="${INACTIVE_SLOTS_PER_CELL:-8}"
INACTIVE_SLOTS="${INACTIVE_SLOTS:-$((NX * NY * INACTIVE_SLOTS_PER_CELL))}"
BASE_RUN_ROOT="${BASE_RUN_ROOT:-runs/0493w2_src_calibrated_segmented_darcy_reference}"
RUN_ROOT="${RUN_ROOT:-$BASE_RUN_ROOT}"
CLEAN_RUN_ROOT="${CLEAN_RUN_ROOT:-1}"

# The repository-root control file remains mandatory.
LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-1}"
LIVE_VIS_CONTROL_FILE="$ROOT/livevis_control.kv"
LIVE_VIS_FIELD="${LIVE_VIS_FIELD:-ux}"
LIVE_VIS_EVERY="${LIVE_VIS_EVERY:-20}"
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
RECORD_SESSION_PREFIX="${RECORD_SESSION_PREFIX:-0493w2_src_calibrated_segmented_darcy}"
RECORD_FIELDS="${RECORD_FIELDS:-rho,ux,uy}"
RECORD_EVERY="${RECORD_EVERY:-100}"
RECORD_STRIDE="${RECORD_STRIDE:-1}"

# Passive depletion diagnostics.  Nmin=ceil(0.60*gamma)=12 by default is a
# classification threshold only; no mutation is allowed in this runner.
RESAMPLING_SURVEY_EVERY="${RESAMPLING_SURVEY_EVERY:-$SUMMARY_EVERY}"
FLAG_EVERY="${FLAG_EVERY:-25}"
SUPPORT_TRIGGER_NMIN="${SUPPORT_TRIGGER_NMIN:-$(( (3 * GAMMA + 4) / 5 ))}"
OUTLIER_U_THRESHOLD="${OUTLIER_U_THRESHOLD:-1.0}"

# Chi-aware diagnostics: exclude the nominal Darcy-solid interior from
# support statistics even though no resampling mutation is active.
CUDA_RESAMPLING_CHI_FILTER_ENABLE="${CUDA_RESAMPLING_CHI_FILTER_ENABLE:-true}"
CUDA_RESAMPLING_CHI_MIN="${CUDA_RESAMPLING_CHI_MIN:-0.05}"

# Belt-and-braces resampling opt-outs, independent of SRC/Q6 mode.
SPECIES_RESAMPLING_ENABLE=false
WEIGHTED_RESAMPLING_ENABLE_OVERRIDE=false
CUDA_EMPTY_REFILL_ENABLE_OVERRIDE=false

# Validate the physical contract before creating or deleting a run directory.
python3 - \
  "$Lx" "$Ly" "$NX" "$NY" "$DT" "$KBT" "$U0" \
  "$CYLINDER_R" "$INLET_SMIN" "$INLET_SMAX" \
  "$OUTLET_SMIN" "$OUTLET_SMAX" \
  "$REFERENCE_NU" "$REFERENCE_CS" "$REFERENCE_DSELF" \
  "$CHARACTERISTIC_L" "$STEPS" "$STAT_WARMUP_STEPS" <<'PY'
import math
import sys

(
    lx, ly, nx, ny, dt, kbt, u0, radius,
    inlet_smin, inlet_smax, outlet_smin, outlet_smax,
    nu, cs, dself, length, steps, warmup,
) = sys.argv[1:]

lx = float(lx)
ly = float(ly)
nx = int(nx)
ny = int(ny)
dt = float(dt)
kbt = float(kbt)
u0 = float(u0)
radius = float(radius)
inlet_smin = float(inlet_smin)
inlet_smax = float(inlet_smax)
outlet_smin = float(outlet_smin)
outlet_smax = float(outlet_smax)
nu = float(nu)
cs = float(cs)
dself = float(dself)
length = float(length)
steps = int(steps)
warmup = int(warmup)

if min(lx, ly, dt, kbt, nu, cs, dself, length) <= 0.0:
    raise SystemExit("[0493w2-preflight] positive physical parameters required")
if min(nx, ny, steps) <= 0:
    raise SystemExit("[0493w2-preflight] positive grid and step counts required")
if not (0 <= warmup < steps):
    raise SystemExit(
        f"[0493w2-preflight] STAT_WARMUP_STEPS={warmup} must satisfy 0 <= warmup < STEPS={steps}"
    )
for name, lo, hi in (
    ("inlet", inlet_smin, inlet_smax),
    ("outlet", outlet_smin, outlet_smax),
):
    if not (0.0 <= lo < hi <= 1.0):
        raise SystemExit(f"[0493w2-preflight] invalid {name} segment [{lo},{hi}]")

dx = lx / nx
dy = ly / ny
if abs(dx - dy) > 1.0e-12 * max(dx, dy):
    raise SystemExit(
        f"[0493w2-preflight] collision cells must be square: dx={dx:.12g}, dy={dy:.12g}"
    )

expected_a = 1.0 / 256.0
if abs(dx - expected_a) > 1.0e-10:
    print(
        f"[0493w2-preflight] WARNING a={dx:.12g}, calibrated reference uses 1/256={expected_a:.12g}",
        file=sys.stderr,
    )

diameter = 2.0 * radius
reynolds = u0 * length / nu
mach = u0 / cs
schmidt = nu / dself
flow_steps = lx / (u0 * dt)
diameter_cells = diameter / dx
total_time = steps * dt
warmup_time = warmup * dt
post_warmup_flow_times = max(0.0, total_time - warmup_time) * u0 / lx

if abs(diameter - length) > 1.0e-12:
    print(
        f"[0493w2-preflight] WARNING characteristic L={length:.8g} differs from cylinder diameter={diameter:.8g}",
        file=sys.stderr,
    )

print(
    "[0493w2-preflight] "
    f"a={dx:.8g} D/a={diameter_cells:.3f} "
    f"Re={reynolds:.4f} Ma={mach:.4f} Sc={schmidt:.4f}"
)
print(
    "[0493w2-preflight] "
    f"steps={steps} tEnd={total_time:.6g} flowThroughSteps={flow_steps:.1f} "
    f"warmup={warmup} postWarmupFlowTimes={post_warmup_flow_times:.3f}"
)
PY

suite_defaults_common_0434
suite_compute_derived_0434
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
openBoundarySegment0 = ${INLET_FACE} inlet ${INLET_SMIN} ${INLET_SMAX} ${U0} 0.0 0 ${PARTICLE_MASS}
openBoundarySegment1 = ${OUTLET_FACE} outlet ${OUTLET_SMIN} ${OUTLET_SMAX} ${U0} 0.0 0 ${PARTICLE_MASS}
inletVelocityRampEnable = true
inletVelocityRampStartTime = 0.0
inletVelocityRampEndTime = ${INLET_RAMP_END_TIME}
inletVelocityRampInitialFactor = ${INLET_RAMP_INITIAL_FACTOR}
inletVelocityRampFinalFactor = 1.0
inletVelocityRampProfile = smoothstep
inletVelocitySpatialProfile = uniform
inletKBT = ${KBT}
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
wallVpKBT = ${KBT}
wallKBT = ${KBT}
wallThermalNoise = 0.0
bodyAccelerationX = 0.0
bodyAccelerationY = 0.0
$(suite_write_common_params_0434 "$MODE")
$(suite_write_darcy_params_0434 "$CHI")
PARAMS

suite_export_cuda_flags_0434 "$MODE" "$TOPOLOGY"

# Passive support and geometry diagnostics, with every mutating brick off.
export MPCD_CUDA_RESAMPLING_SUPPORT_SURVEY_0295=1
export MPCD_CUDA_RESAMPLING_SUPPORT_SURVEY_0295_EVERY="$RESAMPLING_SURVEY_EVERY"
export MPCD_CUDA_RESAMPLING_SUPPORT_SURVEY_0295_MODE=full
export MPCD_CUDA_RESAMPLING_ADAPTIVE_FLAG_0304=1
export MPCD_CUDA_RESAMPLING_ADAPTIVE_FLAG_0304_EVERY="$FLAG_EVERY"
export MPCD_CUDA_RESAMPLING_ADAPTIVE_FLAG_0304_TRIGGER_NMIN="$SUPPORT_TRIGGER_NMIN"
export MPCD_CUDA_RESAMPLING_ADAPTIVE_FLAG_0304_TRIGGER_EMPTY=1
export MPCD_CUDA_RESAMPLING_GEOMETRY_DIAG_0305_HIGH_U="$OUTLIER_U_THRESHOLD"
export MPCD_CUDA_RESAMPLING_OUTLIER_0306_U_THRESHOLD="$OUTLIER_U_THRESHOLD"

# Production-like timing by default: keep functional diagnostics, drop detailed
# phase-event profiling unless explicitly requested for a separate cost study.
export MPCD_INTERNAL_PROFILES="${MPCD_INTERNAL_PROFILES:-0}"
export MPCD_CUDA_RESIDENT_PROFILE_0266="${MPCD_CUDA_RESIDENT_PROFILE_0266:-0}"

export MPCD_CUDA_RESAMPLING_MASS_RECONDITION_0296=0
export MPCD_CUDA_RESAMPLING_EMPTY_REFILL_0319=0
export MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297=0
export MPCD_CUDA_RESAMPLING_PIPELINE_APPLY_0448=0

suite_prepare_livevis_control_0434 "$RUN_ROOT" "$MODE"
[[ "$LIVE_VIS_CONTROL_FILE" == "$ROOT/livevis_control.kv" ]] || {
  echo "[0493w2] ERROR livevis control escaped repository root: $LIVE_VIS_CONTROL_FILE" >&2
  exit 2
}
suite_export_livevis_0434

ENV_FILE="$RUN_ROOT/logs/environment_0493w2.env"
suite_write_env_file_0434 "$ENV_FILE" "$MODE"
cat >> "$ENV_FILE" <<META
REFERENCE_NU=${REFERENCE_NU}
REFERENCE_CS=${REFERENCE_CS}
REFERENCE_DSELF=${REFERENCE_DSELF}
REFERENCE_SC=${REFERENCE_SC}
CHARACTERISTIC_L=${CHARACTERISTIC_L}
STAT_WARMUP_STEPS=${STAT_WARMUP_STEPS}
MPCD_INTERNAL_PROFILES=${MPCD_INTERNAL_PROFILES}
MPCD_CUDA_RESIDENT_PROFILE_0266=${MPCD_CUDA_RESIDENT_PROFILE_0266}
RESAMPLING_SURVEY_EVERY=${RESAMPLING_SURVEY_EVERY}
FLAG_EVERY=${FLAG_EVERY}
SUPPORT_TRIGGER_NMIN=${SUPPORT_TRIGGER_NMIN}
INLET_SEGMENT=${INLET_FACE}:${INLET_SMIN}:${INLET_SMAX}
OUTLET_SEGMENT=${OUTLET_FACE}:${OUTLET_SMIN}:${OUTLET_SMAX}
META

printf '[0493w2] calibrated mode=%s segmented inlet/outlet + walls + Darcy/chi cylinder\n' "$MODE"
printf '[0493w2] grid=%sx%s L=(%s,%s) gamma=%s active~%s inactive=%s steps=%s dt=%s kBT=%s\n' \
  "$NX" "$NY" "$Lx" "$Ly" "$GAMMA" "$((NX * NY * GAMMA))" \
  "$INACTIVE_SLOTS" "$STEPS" "$DT" "$KBT"
printf '[0493w2] segments=%s:[%s,%s] -> %s:[%s,%s] U0=%s rampEnd=%s\n' \
  "$INLET_FACE" "$INLET_SMIN" "$INLET_SMAX" \
  "$OUTLET_FACE" "$OUTLET_SMIN" "$OUTLET_SMAX" "$U0" "$INLET_RAMP_END_TIME"
printf '[0493w2] cylinder=(%s,%s,r=%s) alpha=%s alpha*dt=' \
  "$CYLINDER_CX" "$CYLINDER_CY" "$CYLINDER_R" "$ALPHA"
python3 - "$ALPHA" "$DT" <<'PY'
import sys
print(f"{float(sys.argv[1]) * float(sys.argv[2]):.8g}")
PY
printf '[0493w2] reference nu=%s cs=%s Dself=%s Sc=%s Lchar=%s\n' \
  "$REFERENCE_NU" "$REFERENCE_CS" "$REFERENCE_DSELF" "$REFERENCE_SC" "$CHARACTERISTIC_L"
printf '[0493w2] liveProgress=%s livevis=%s control=%s every=%s\n' \
  "$LIVE_PROGRESS" "$LIVE_VIS_ENABLE" "$LIVE_VIS_CONTROL_FILE" "$LIVE_VIS_EVERY"
printf '[0493w2] summaryEvery=%s dumpEvery=%s recordEvery=%s surveyEvery=%s flagEvery=%s warmup=%s\n' \
  "$SUMMARY_EVERY" "$DUMP_STATE_EVERY" "$RECORD_EVERY" \
  "$RESAMPLING_SURVEY_EVERY" "$FLAG_EVERY" "$STAT_WARMUP_STEPS"
printf '[0493w2] Q6=%s resampling=off supportRepair=off passiveSurvey=on\n' "$Q6_STATE"

suite_run_binary_0434 "$PARAMS" "$LOG" "$TIME" "$OUT"
