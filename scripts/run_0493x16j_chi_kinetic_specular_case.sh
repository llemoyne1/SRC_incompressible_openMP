#!/usr/bin/env bash

# 0493x16j — chi kinetic specular boundary qualification.
# Same resident chi field as historical Darcy, but chi=0.5 is interpreted as a
# material interface by the qualified x10n/Q2/x10p/q crossing engine and x14l
# local-moving-frame specular response. Darcy forcing and chiVP are deliberately
# disabled in this first qualification so impermeability is isolated.

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$ROOT/scripts/src_mpcd_run_common_0434.sh"
suite_root_cd_0434 || exit $?

CASE_LABEL="${CASE_LABEL:-0493x16j_chi_kinetic_specular}"
MODE="${MODE:-src-q6}"
TOPOLOGY="periodic"
GEN_CASE="step"

Lx="${Lx:-0.5}"
Ly="${Ly:-0.25}"
NX="${NX:-128}"
NY="${NY:-64}"
GAMMA="${GAMMA:-20}"
STEPS="${STEPS:-1200}"
DT="${DT:-0.002}"
KBT="${KBT:-0.125}"
SEED="${SEED:-4931610}"
PARTICLE_MASS="${PARTICLE_MASS:-1.0}"
COMMON_UX="${COMMON_UX:-0.0}"
DEFORMABLE="${DEFORMABLE:-0}"
DEFORM_AMPLITUDE_CELLS="${DEFORM_AMPLITUDE_CELLS:-0.75}"
DEFORM_PERIOD_STEPS="${DEFORM_PERIOD_STEPS:-400}"
CHI_SOLID_DYNAMICS_ENABLE="${CHI_SOLID_DYNAMICS_ENABLE:-1}"

SLAB_CELLS="${SLAB_CELLS:-8}"
SOLID_MASS="${SOLID_MASS:-32768.0}"
DARCY_THREADS_PER_BLOCK="${DARCY_THREADS_PER_BLOCK:-256}"
INITIAL_DEACTIVATE_BELOW_CHI="${INITIAL_DEACTIVATE_BELOW_CHI:-0.5}"

VELOCITY_MODE=uniform_x
U0="$COMMON_UX"
BACKGROUND_TYPE=0
INACTIVE_TYPE=0
INACTIVE_SLOTS=0
SKIP_SOLID_CELLS=true
SKIP_SOLID_PARTICLES=true
REMOVE_MEAN_DRIFT=true

ROTATION_ANGLE="${ROTATION_ANGLE:-1.5707963267948966}"
RANDOM_ROTATION_SIGN=true
GRID_SHIFT_ENABLE=true
THERMOSTAT_ENABLE=true
THERMOSTAT_MODE=cell_relative_rescale
THERMOSTAT_EVERY=1
THERMOSTAT_TARGET_KBT="$KBT"
THERMOSTAT_MIN_PARTICLES=3
WEIGHTED_RESAMPLING_ENABLE_OVERRIDE=false
CUDA_EMPTY_REFILL_ENABLE_OVERRIDE=false
SPECIES_RESAMPLING_ENABLE=false
DUMP_ROLE_FILTER=all
SUMMARY_ROLE_FILTER=fluid

SUMMARY_EVERY="${SUMMARY_EVERY:-1}"
DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-1000}"
DARCY_COST_EVERY="${DARCY_COST_EVERY:-1}"
LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-1}"
LIVE_VIS_FIELD="${LIVE_VIS_FIELD:-rho}"
LIVE_VIS_EVERY="${LIVE_VIS_EVERY:-1}"
LIVE_VIS_NX="${LIVE_VIS_NX:-96}"
LIVE_VIS_NY="${LIVE_VIS_NY:-48}"
LIVE_VIS_HOLD_ON_EXIT="${LIVE_VIS_HOLD_ON_EXIT:-0}"
FILTERED_RECORDING_ENABLE="${FILTERED_RECORDING_ENABLE:-1}"
RECORD_ENABLE="${RECORD_ENABLE:-true}"
# 0432 does not support chi recording. Keep geometry diagnostics in CSVs.
RECORD_FIELDS="${RECORD_FIELDS:-rho,ux,uy}"
RECORD_EVERY="${RECORD_EVERY:-50}"
FILTER_MODE="${FILTER_MODE:-none}"
FILTER_SAMPLE_EVERY="${FILTER_SAMPLE_EVERY:-100}"
PARTICLE_TYPE_FILTER="${PARTICLE_TYPE_FILTER:--1}"

BASE_RUN_ROOT="${BASE_RUN_ROOT:-runs/0493x16j_chi_kinetic_specular}"
CLEAN_RUN_ROOT="${CLEAN_RUN_ROOT:-1}"
PREFLIGHT_ONLY="${PREFLIGHT_ONLY:-0}"

suite_defaults_common_0434
suite_compute_derived_0434
suite_validate_path_0434 "$MODE" || exit $?

CHI_SOLID_DYNAMICS_KV=false
if suite_truthy_0434 "$CHI_SOLID_DYNAMICS_ENABLE"; then
  CHI_SOLID_DYNAMICS_KV=true
fi

if (( NX < 32 || NY < 16 || SLAB_CELLS < 2 || SLAB_CELLS >= NX/2 )); then
  echo "[0493x16j] ERROR require NX>=32 NY>=16 and 2<=SLAB_CELLS<NX/2" >&2
  exit 2
fi

read -r SLAB_XMIN SLAB_XMAX <<EOF_GEOM
$(python3 - "$Lx" "$NX" "$SLAB_CELLS" <<'PY'
import sys
Lx=float(sys.argv[1]); nx=int(sys.argv[2]); cells=int(sys.argv[3])
dx=Lx/nx; w=cells*dx; c=0.5*Lx
print(f"{c-0.5*w:.17g} {c+0.5*w:.17g}")
PY
)
EOF_GEOM

# The common step generator is reused only to create the initial impermeable
# slab void. The runtime geometry is then owned by chiSolidDynamics.
STEP_XMIN="$SLAB_XMIN"
STEP_XMAX="$SLAB_XMAX"
STEP_YMIN=0.0
STEP_YMAX="$Ly"

RUN_ROOT="$BASE_RUN_ROOT/fresh"
if suite_truthy_0434 "$CLEAN_RUN_ROOT"; then rm -rf "$RUN_ROOT"; fi
suite_prepare_dirs_0434 "$RUN_ROOT"
STATE="$RUN_ROOT/init/${CASE_LABEL}_${NX}x${NY}_g${GAMMA}.smpcd"
PARAMS="$RUN_ROOT/params/${CASE_LABEL}.kv"
OUT="$RUN_ROOT/output"
LOG="$RUN_ROOT/logs/${CASE_LABEL}.log"
TIMEFILE="$RUN_ROOT/logs/${CASE_LABEL}.time"
LIVE_VIS_CONTROL_FILE="$RUN_ROOT/params/${CASE_LABEL}_livevis_control.kv"
mkdir -p "$OUT"

# The frozen-curved qualification must start from a full fluid state and then
# remove exactly the curved solid volume. Reusing the rectangular generator
# void would leave an artificial empty crescent on the receding side.
X17B_STATIC_CURVED_INIT=0
if suite_truthy_0434 "${SRC_X16I_STATIC_CURVED_0493X16M:-0}"; then
  X17B_STATIC_CURVED_INIT=1
  SKIP_SOLID_CELLS=false
  SKIP_SOLID_PARTICLES=false
fi
INITIAL_DEACTIVATE_EFFECTIVE="$INITIAL_DEACTIVATE_BELOW_CHI"
suite_generate_case_0434 "$STATE" "" || exit $?

# 0493x17b: the material-wall contract requires no active fluid on the solid
# side of the initial chi=0.5 contour. The ordinary box/file path is handled by
# darcyInitialDeactivateBelowChi below. The frozen-curved qualification geometry
# is a diagnostic deformation applied after the rectangular case generator, so
# make that generated initial state consistent with the exact prescribed curve
# before the binary starts. This is initialization only; no run-time remapping.
if [[ "$X17B_STATIC_CURVED_INIT" == 1 ]]; then
  AMP_PHYS=$(python3 - "$DEFORM_AMPLITUDE_CELLS" "$Lx" "$NX" <<'PYX17B'
import sys
print(f"{float(sys.argv[1])*float(sys.argv[2])/int(sys.argv[3]):.17g}")
PYX17B
)
  THICK_PHYS=$(python3 - "$SLAB_CELLS" "$Lx" "$NX" <<'PYX17B'
import sys
print(f"{float(sys.argv[1])*float(sys.argv[2])/int(sys.argv[3]):.17g}")
PYX17B
)
  python3 scripts/prepare_0493x17b_initial_state_curved_slab.py "$STATE" \
    --Lx "$Lx" --Ly "$Ly" --center-x "$(python3 -c "print(0.5*float('$Lx'))")" \
    --thickness "$THICK_PHYS" --amplitude "$AMP_PHYS" || exit $?
  # The exact curved cull above supersedes the cellwise box threshold.
  INITIAL_DEACTIVATE_EFFECTIVE=-1
fi

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
bcBottom = periodic
bcTop = periodic
bcX = periodic
bcY = periodic
openBoundarySegmentsEnable = false
openBoundarySegmentCount = 0
bodyAccelerationX = 0.0
bodyAccelerationY = 0.0
taylorGreenForcingEnable = false
wallAccommodation = 0.0
wallVpEnable = false
phaseInterfaceKineticReflectionFraction = 0.0
PARAMS
suite_write_common_params_0434 "$MODE" >> "$PARAMS"
cat >> "$PARAMS" <<PARAMS
darcyBrinkmanEnable = true
darcyChiMode = box
darcyBoxXMin = $SLAB_XMIN
darcyBoxXMax = $SLAB_XMAX
darcyBoxYMin = 0.0
darcyBoxYMax = $Ly
darcyInterfaceWidth = 0.0
darcyAlphaMin = 0.0
darcyAlphaMax = 0.0
darcyQ = 0.1
darcyUSolidX = $COMMON_UX
darcyUSolidY = 0.0
darcyCostEvery = $DARCY_COST_EVERY
darcyCostFilename = darcy_cost_0343.csv
darcyThreadsPerBlock = $DARCY_THREADS_PER_BLOCK
darcyInitialDeactivateBelowChi = $INITIAL_DEACTIVATE_EFFECTIVE
darcyBrinkmanForcingMode = mean
darcyChiCollisionVpEnable = false
chiKineticBoundaryMode = specular
chiSolidDynamicsEnable = $CHI_SOLID_DYNAMICS_KV
chiSolidModel = rigid_slab_1d
chiSolidMass = $SOLID_MASS
PARAMS

cat > "$LIVE_VIS_CONTROL_FILE" <<LIVEVIS_CONTROL_KV
recordEnable = ${RECORD_ENABLE}
recordSession = ${CASE_LABEL}_${MODE}
recordFields = ${RECORD_FIELDS}
recordFormat = ${RECORD_FORMAT}
recordEvery = ${RECORD_EVERY}
liveGridNx = ${LIVE_VIS_NX}
liveGridNy = ${LIVE_VIS_NY}
field = ${LIVE_VIS_FIELD}
filterMode = ${FILTER_MODE}
filterSampleEvery = ${FILTER_SAMPLE_EVERY}
smoothPasses = 0
particleTypeFilter = ${PARTICLE_TYPE_FILTER}
LIVEVIS_CONTROL_KV

suite_export_cuda_flags_0434 "$MODE" "$TOPOLOGY"
unset SRC_X16G_CAPTURE_BATH_MEAN_NEUTRALIZE
unset SRC_X16H_CAPTURE_SPATIAL_REINJECT
unset SRC_X16I_IMPERMEABLE_EXCLUSION_MODE
if suite_truthy_0434 "$DEFORMABLE"; then
  export SRC_X16I_PRESCRIBED_DEFORMABLE=1
  export SRC_X16I_DEFORM_AMPLITUDE_CELLS="$DEFORM_AMPLITUDE_CELLS"
  export SRC_X16I_DEFORM_PERIOD_STEPS="$DEFORM_PERIOD_STEPS"
else
  unset SRC_X16I_PRESCRIBED_DEFORMABLE
  unset SRC_X16I_DEFORM_AMPLITUDE_CELLS
  unset SRC_X16I_DEFORM_PERIOD_STEPS
fi
suite_export_livevis_0434
suite_write_env_file_0434 "$RUN_ROOT/logs/environment_0493x16j.env" "$MODE"

cat > "$RUN_ROOT/run_meta_0493x16j.txt" <<META
case=$CASE_LABEL
mode=$MODE
chiKineticBoundaryMode=specular
response=x10n_Q2_x10p_q_plus_x14l_local_frame_specular
chiGeometry=continuous_subcell_when_dynamic
DarcyAlphaMax=0
chiVp=off
fluidMeanUx0=$COMMON_UX
solidUx0=$COMMON_UX
chiSolidDynamicsEnable=$CHI_SOLID_DYNAMICS_KV
deformable=$DEFORMABLE
deformAmplitudeCells=$DEFORM_AMPLITUDE_CELLS
deformPeriodSteps=$DEFORM_PERIOD_STEPS
slabCells=$SLAB_CELLS
slabXMin0=$SLAB_XMIN
slabXMax0=$SLAB_XMAX
wallImpulseFeedback=APPLIED_exact_cell_reaction_x16b
initialStatePolicy=x17b-chi0-fluid-exclusion
initialDeactivateBelowChi=$INITIAL_DEACTIVATE_EFFECTIVE
META

printf '\n===== 0493x16j CHI KINETIC SPECULAR =====\n'
printf 'run=%s mode=%s grid=%sx%s gamma=%s steps=%s dt=%s\n' "$RUN_ROOT" "$MODE" "$NX" "$NY" "$GAMMA" "$STEPS" "$DT"
printf 'common Ux=%s solidDynamics=%s deformable=%s slab=%s cells\n' "$COMMON_UX" "$CHI_SOLID_DYNAMICS_KV" "$DEFORMABLE" "$SLAB_CELLS"
printf 'chi response=specular; Darcy alpha=0; chiVP=off; initial chi fluid exclusion requested=%s effective=%s\n' "$INITIAL_DEACTIVATE_BELOW_CHI" "$INITIAL_DEACTIVATE_EFFECTIVE"
printf 'recorder fields=%s (chi intentionally excluded: unsupported by 0432)\n' "$RECORD_FIELDS"
printf '===========================================\n\n'

suite_run_binary_0434 "$PARAMS" "$LOG" "$TIMEFILE" "$OUT" || exit $?
if suite_truthy_0434 "$PREFLIGHT_ONLY"; then exit 0; fi

[[ -s "$OUT/chi_kinetic_boundary_0493x16j.csv" ]] || { echo "[0493x16j] ERROR missing chi kinetic boundary CSV" >&2; exit 2; }
grep -q '\[0493x16j-chi-kinetic\] mode=specular timing=prestream' "$LOG" || { echo "[0493x16j] ERROR x16j prestream specular path marker absent" >&2; exit 2; }
head -n 1 "$OUT/chi_kinetic_boundary_0493x16j.csv" | grep -q 'wallImpulseX' || { echo "[0493x16j] ERROR malformed kinetic CSV" >&2; exit 2; }
if suite_truthy_0434 "$CHI_SOLID_DYNAMICS_ENABLE"; then
  [[ -s "$OUT/chi_solid_dynamics_0493x16a.csv" ]] || { echo "[0493x16j] ERROR missing solid geometry diagnostic" >&2; exit 2; }
  head -n 1 "$OUT/chi_solid_dynamics_0493x16a.csv" | grep -q 'chiKineticFluidImpulseX0493x16j' || { echo "[0493x16j] ERROR missing x16j kinetic impulse feedback column" >&2; exit 2; }
fi

echo "[0493x16j] COMPLETE run=$RUN_ROOT"
