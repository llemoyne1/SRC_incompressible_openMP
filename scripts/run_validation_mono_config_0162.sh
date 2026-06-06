#!/usr/bin/env bash
set -euo pipefail

# 0162 — mono-configuration discriminant validation campaign.
# Runs only the complete incompressible chain (Q6 + weighted resampling) for
# non-virial cases, with one OpenMP thread count.  The virial/capacity term is
# exercised only in the piston case.

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT_DIR"

BIN=${BIN:-build/src_mpcd_base}
RUN_ROOT=${RUN_ROOT:-runs/validation_mono_0162}
RUN_TAG=${RUN_TAG:-unknown}
NX=${NX:-64}
NY=${NY:-64}
GAMMA=${GAMMA:-20}
STEPS=${STEPS:-1000}
SUMMARY_EVERY=${SUMMARY_EVERY:-100}
THREADS=${THREADS:-8}
DT=${DT:-0.001}
KBT=${KBT:-0.001}
PROJECTION_BACKEND=${PROJECTION_BACKEND:-cpu}
SEED=${SEED:-1620162}
CASE_LIST=${CASE_LIST:-tg_periodic_full poiseuille_wall_full open_rect_obstacle_full piston_virial_full}
DUMP_STATE_EVERY=${DUMP_STATE_EVERY:-0}
BUILD_IF_MISSING=${BUILD_IF_MISSING:-1}

export OMP_NUM_THREADS=${OMP_NUM_THREADS:-$THREADS}
export OMP_PROC_BIND=${OMP_PROC_BIND:-close}
export OMP_PLACES=${OMP_PLACES:-cores}
export OMP_DYNAMIC=${OMP_DYNAMIC:-false}

if [[ -f "$BIN" && ! -x "$BIN" ]]; then
  chmod +x "$BIN" 2>/dev/null || true
fi
if [[ ! -x "$BIN" ]]; then
  if [[ "$BUILD_IF_MISSING" == "1" ]]; then
    if [[ -f scripts/build_src_mpcd_base_optimized_0156.sh ]]; then
      BUILD_PROFILE=${BUILD_PROFILE:-native} bash scripts/build_src_mpcd_base_optimized_0156.sh
    elif [[ -f scripts/build_src_mpcd_base.sh ]]; then
      bash scripts/build_src_mpcd_base.sh
    else
      echo "Binary '$BIN' not found and no known build script is executable." >&2
      exit 127
    fi
  fi
fi
if [[ ! -x "$BIN" ]]; then
  echo "Binary '$BIN' not found or not executable. Build first." >&2
  exit 127
fi

rm -rf "$RUN_ROOT"
mkdir -p "$RUN_ROOT/init"
SUMMARY_CSV="$RUN_ROOT/validation_summary_0162.csv"
MANIFEST_CSV="$RUN_ROOT/validation_manifest_0162.csv"

# Keep the summary intentionally compact: these are the discriminating final-row
# diagnostics used for origin-vs-optimized comparison.  The complete
# summary_runtime.csv is preserved in each case directory.
METRICS=(
  wallTime numThreadsUsed Np nFluidParticles nInactiveParticles nLatentParticles totalMass Px Py
  meanVx meanVy meanKinetic kBTEstimate meanPhysicalDensity meanN stdN minN maxN
  hitsImmersed inletReservoirDeleted inletBackflowDeleted outletParticlesDeleted inletParticlesInserted inletNetParticleDelta
  q6Applied q6Converged q6Iterations q6ResidualRel q6DivBeforeRms q6DivAfterProjectedFluxRms
  q6DivAfterCellVelocityRms q6CorrectionVelocityRms q6OpenBoundaryEnabled q6OpenBoundaryFluxBalance q6OpenBoundaryMeanDivergence
  q6ImmersedSolidFluidCells q6ImmersedSolidSolidCells q6ImmersedSolidCutCells q6ImmersedSolidActiveCutCells
  q6ImmersedSolidLeakProjectedFluxRms q6ImmersedSolidLeakCellClosedProjectedFluxRms q6ImmersedSolidLeakCutProjectedFluxRms
  resampComputed resampTotalMass resampMeanN resampStdN resampMRelRms resampMRelMaxAbs
  resampParticleMassMean resampParticleMassRelStd resampTransferPairs resampSelectedDonorParticles
  resampExtractionApplyRoleChanges resampInsertionApplyRoleChanges resampRemapApplied resampRemapCellsRemapped
  resampRemapMassCorrectionStrength resampMassGuardApplied resampMassGuardCellsGuarded resampPopulationGuardApplied
  resampPopulationGuardCellsSplit resampPopulationGuardCellsExtracted resampPopulationGuardSplitParticlesCreated resampPopulationGuardExtractedParticles
  capacityResponseEnabled capacityResponseComputed capacityVirialKickApplied capacityOverfillRatio capacityQ6ProjectionFactor
  capacityMassRemapFactor capacityVirialKEffective capacityVirialPressureMean capacityVirialPressureRms capacityVirialKickVelocityRms
  capacityVirialMomentumResidualBeforeCorrection capacityVirialMomentumCorrectionVx capacityVirialMomentumCorrectionVy
)

{
  printf 'runTag,case,elapsed_s,user_s,sys_s'
  for m in "${METRICS[@]}"; do printf ',%s' "$m"; done
  printf '\n'
} > "$SUMMARY_CSV"
printf 'runTag,case,paramsFile,outputDir,initialState,description\n' > "$MANIFEST_CSV"

state_path() { echo "$RUN_ROOT/init/$1.smpcd"; }

make_state() {
  local name=$1; shift
  local state
  state=$(state_path "$name")
  if [[ ! -f "$state" ]]; then
    python3 scripts/generate_validation_state_0162.py --output "$state" "$@" >&2
  fi
  echo "$state"
}

write_resampling_block() {
  cat <<PARAMS
resamplingEnable = ${RESAMPLING_ENABLE:-true}
resamplingPopulationNMin = ${RESAMP_N_MIN:-14}
resamplingPopulationNTarget = ${RESAMP_N_TARGET:-20}
resamplingPopulationNMax = ${RESAMP_N_MAX:-26}
resamplingPopulationMaxSplitsPerCell = ${RESAMP_POP_MAX_SPLITS_PER_CELL:-16}
resamplingPopulationMaxSplitsPerStep = ${RESAMP_POP_MAX_SPLITS_PER_STEP:-200000}
resamplingPopulationMaxExtractionsPerCell = ${RESAMP_POP_MAX_EXTRACT_PER_CELL:-64}
resamplingPopulationMaxExtractionsPerStep = ${RESAMP_POP_MAX_EXTRACT_PER_STEP:-200000}
resamplingTargetCellMass = $GAMMA
resamplingWetMaskMode = active_domain
resamplingWetCellMassThreshold = 0.0
resamplingPoorCellMassFraction = ${RESAMP_POOR_FRACTION:-0.90}
resamplingRichCellMassFraction = ${RESAMP_RICH_FRACTION:-1.10}
resamplingActiveFluidFractionThreshold = 0.5
resamplingExtractionEnable = true
resamplingInsertionEnable = true
resamplingRemapEnable = true
resamplingMassRenormalizationPeriod = ${RESAMP_MASS_RENORM_PERIOD:-10}
resamplingThermalRenormalizationEnable = true
resamplingMassGuardEnable = true
resamplingParticleMassMin = ${RESAMP_MASS_MIN:-0.5}
resamplingParticleMassMax = ${RESAMP_MASS_MAX:-2.0}
resamplingLatentActivationEnable = false
PARAMS
}

write_common_runtime_block() {
  cat <<PARAMS
rotationAngle = 2.0943951023931953
randomRotationSign = true
gridShiftEnable = true
rngSeed = $SEED

srcClassicCudaModeEnable = ${SRC_CLASSIC_CUDA_MODE_ENABLE:-false}
projectionEnable = ${PROJECTION_ENABLE:-true}
projectionBackend = $PROJECTION_BACKEND
projectionMaxIterations = 800
projectionTolerance = 1.0e-10
projectionMomentumCorrectionEnable = true
q6ProjectionStrength = 1.0

thermostatEnable = ${THERMOSTAT_ENABLE:-true}
thermostatMode = cell_relative_rescale
thermostatEvery = 1
thermostatTargetKBT = -1.0
thermostatMinParticles = 3
kBT = $KBT

summaryEvery = $SUMMARY_EVERY
dumpStateEvery = $DUMP_STATE_EVERY
numThreads = $THREADS
PARAMS
}

write_params_tg() {
  local label=$1 out_dir=$2 params=$3 state=$4
  cat > "$params" <<PARAMS
inputState = $state
outputDir = $out_dir

Lx = 1.0
Ly = 1.0
Nx = $NX
Ny = $NY

dt = $DT
nSteps = $STEPS

bodyAccelerationX = 0.0
bodyAccelerationY = 0.0
taylorGreenForcingEnable = false

bcX = periodic
bcY = periodic

projectionOperator = periodic_fv_cg
$(write_common_runtime_block)
$(write_resampling_block)
PARAMS
}

write_params_poiseuille() {
  local label=$1 out_dir=$2 params=$3 state=$4
  cat > "$params" <<PARAMS
inputState = $state
outputDir = $out_dir

Lx = 2.0
Ly = 1.0
Nx = $NX
Ny = $NY

dt = $DT
nSteps = $STEPS

bodyAccelerationX = ${POIS_BODY_ACCEL:-0.01}
bodyAccelerationY = 0.0

bcX = periodic
bcY = solid

wallVpEnable = true
wallAccommodation = 1.0
wallVpGamma = $GAMMA
wallVpMass = 1.0
wallKBT = $KBT
wallThermalNoise = ${WALL_THERMAL_NOISE:-1.0}
wallUxBottom = 0.0
wallUyBottom = 0.0
wallUxTop = 0.0
wallUyTop = 0.0

projectionOperator = channel_fv_cg
$(write_common_runtime_block)
$(write_resampling_block)
PARAMS
}

write_params_open_rect() {
  local label=$1 out_dir=$2 params=$3 state=$4
  cat > "$params" <<PARAMS
inputState = $state
outputDir = $out_dir

Lx = 2.0
Ly = 1.0
Nx = $NX
Ny = $NY

fluidXMin0 = 0.0
fluidXMax0 = -1.0
fluidYMin0 = 0.0
fluidYMax0 = -1.0

dt = $DT
nSteps = $STEPS

bodyAccelerationX = 0.0
bodyAccelerationY = 0.0

bcLeft = inlet
bcRight = outlet
bcBottom = solid
bcTop = solid

inletUxLeft = ${ORECT_INLET_UX:-0.08}
inletUyLeft = 0.0
inletVelocityRampEnable = true
inletVelocityRampStartTime = 0.0
inletVelocityRampEndTime = ${ORECT_RAMP_END_TIME:-0.25}
inletVelocityRampInitialFactor = 0.2
inletVelocityRampFinalFactor = 1.0
inletVelocityRampProfile = smoothstep
inletVelocitySpatialProfile = flat_taper_y
inletVelocityWallTaperCells = 2.0
inletKBT = -1.0
inletThermalNoise = 1.0
inletInjectionMode = hard_cell_density
inletReservoirMode = hard_cell_density
inletReservoirCells = 3
inletTargetOccupancy = $GAMMA
inletHardCellVelocityMean = true
inletHardCellThermalRescale = true
inletRandomizeTangential = true
inletReinjectBackflow = true

openBoundaryOutletMode = hybrid
openBoundaryOutletHybridBlend = 0.5
openBoundaryOutletFeedbackGain = 0.0

projectionOperator = elliptic_fv_cg
projectionImmersedSolidMaskEnable = true
projectionImmersedSolidCloseCutFaces = true
projectionImmersedSolidFluidFractionThreshold = 0.5
projectionAllowUnmaskedImmersedSolid = false

immersedSolidEnable = true
immersedSolidShape = rectangle
immersedSolidXMin = 0.25
immersedSolidXMax = 0.50
immersedSolidYMin = 0.35
immersedSolidYMax = 0.60
immersedSolidFractionSamples = 4
immersedSolidVx = 0.0
immersedSolidVy = 0.0
immersedSolidWallUx = 0.0
immersedSolidWallUy = 0.0
immersedSolidOmega = 0.0

wallAccommodation = 1.0
wallVpGamma = $GAMMA
wallVpMass = 1.0
wallKBT = -1.0
wallThermalNoise = ${WALL_THERMAL_NOISE:-1.0}

$(write_common_runtime_block)
$(write_resampling_block)
PARAMS
}

write_params_segmented_u_turn() {
  local label=$1 out_dir=$2 params=$3 state=$4
  cat > "$params" <<PARAMS
inputState = $state
outputDir = $out_dir

Lx = 1.0
Ly = 1.0
Nx = $NX
Ny = $NY

fluidXMin0 = 0.0
fluidXMax0 = -1.0
fluidYMin0 = 0.0
fluidYMax0 = -1.0

dt = $DT
nSteps = $STEPS

bodyAccelerationX = 0.0
bodyAccelerationY = 0.0

bcLeft = solid
bcRight = solid
bcBottom = solid
bcTop = solid

openBoundarySegmentsEnable = true
openBoundarySegmentCount = 2
openBoundarySegment0 = left inlet ${UIN_SMIN:-0.10} ${UIN_SMAX:-0.35} ${UTURN_INLET_UX:-0.08} 0.0 0 1.0
openBoundarySegment1 = left outlet ${UOUT_SMIN:-0.65} ${UOUT_SMAX:-0.90} ${UTURN_OUTLET_UX:--0.08} 0.0 0 1.0

inletVelocityRampEnable = true
inletVelocityRampStartTime = 0.0
inletVelocityRampEndTime = ${UTURN_RAMP_END_TIME:-0.25}
inletVelocityRampInitialFactor = 0.2
inletVelocityRampFinalFactor = 1.0
inletVelocityRampProfile = smoothstep
inletVelocitySpatialProfile = uniform
inletKBT = -1.0
inletThermalNoise = 1.0
inletInjectionMode = hard_cell_density
inletReservoirMode = hard_cell_density
inletReservoirCells = 3
inletTargetOccupancy = $GAMMA
inletHardCellVelocityMean = true
inletHardCellThermalRescale = true
inletRandomizeTangential = true
inletReinjectBackflow = true

openBoundaryOutletMode = hybrid
openBoundaryOutletHybridBlend = 0.0
openBoundaryOutletFeedbackGain = 0.0

projectionOperator = elliptic_fv_cg
projectionImmersedSolidMaskEnable = false
projectionImmersedSolidCloseCutFaces = false
projectionAllowUnmaskedImmersedSolid = true

wallAccommodation = 1.0
wallVpGamma = $GAMMA
wallVpMass = 1.0
wallKBT = -1.0
wallThermalNoise = ${WALL_THERMAL_NOISE:-1.0}
wallUxLeft = 0.0
wallUyLeft = 0.0
wallUxRight = 0.0
wallUyRight = 0.0
wallUxBottom = 0.0
wallUyBottom = 0.0
wallUxTop = 0.0
wallUyTop = 0.0

$(write_common_runtime_block)
$(write_resampling_block)
PARAMS
}

write_params_piston_virial() {
  local label=$1 out_dir=$2 params=$3 state=$4
  cat > "$params" <<PARAMS
inputState = $state
outputDir = $out_dir

Lx = 1.0
Ly = 1.0
Nx = $NX
Ny = $NY

fluidYTop0 = ${PISTON_YTOP0:-0.95}
fluidYTopVelocity = ${PISTON_YTOP_VELOCITY:--0.01}

dt = $DT
nSteps = $STEPS

bodyAccelerationX = 0.0
bodyAccelerationY = 0.0

bcLeft = periodic
bcRight = periodic
bcBottom = solid
bcTop = solid

wallAccommodation = 1.0
wallVpGamma = $GAMMA
wallVpMass = 1.0
wallKBT = -1.0
wallThermalNoise = ${WALL_THERMAL_NOISE:-1.0}
wallUxBottom = 0.0
wallUyBottom = 0.0
wallUxTop = 0.0
wallUyTop = ${PISTON_YTOP_VELOCITY:--0.01}

projectionOperator = elliptic_fv_cg
projectionImmersedSolidMaskEnable = false
projectionImmersedSolidCloseCutFaces = false
projectionAllowUnmaskedImmersedSolid = true

closedCapacityResponseEnable = true
closedCapacityReferenceCellMass = $GAMMA
closedCapacityQ6Eta = ${CAP_Q6_ETA:-0.005}
closedCapacityQ6Power = ${CAP_Q6_POWER:-2.0}
closedCapacityMassRemapEta = ${CAP_REMAP_ETA:-0.005}
closedCapacityMassRemapPower = ${CAP_REMAP_POWER:-2.0}
closedCapacityMassGuardDisableOnOverfill = true
closedCapacityVirialKickEnable = true
closedCapacityVirialBaseK = ${CAP_VIRIAL_K:-10.0}
closedCapacityVirialGain = ${CAP_VIRIAL_GAIN:-20.0}
closedCapacityVirialEta = ${CAP_VIRIAL_ETA:-0.005}
closedCapacityVirialPower = ${CAP_VIRIAL_POWER:-2.0}
closedCapacityVirialKickStrength = ${CAP_VIRIAL_KICK_STRENGTH:-0.2}
closedCapacityVirialMomentumCorrectionEnable = true
closedCapacityInletMassFluxEnable = false
closedCapacityInletMassFluxMultiplier = 0.0

$(write_common_runtime_block)
$(write_resampling_block)
PARAMS
}

prepare_case() {
  local case_name=$1
  local state params out_dir desc
  out_dir="$RUN_ROOT/$case_name"
  params="$RUN_ROOT/params_${case_name}.kv"
  mkdir -p "$out_dir"
  case "$case_name" in
    tg_periodic_full)
      state=$(make_state "$case_name" --Lx 1.0 --Ly 1.0 --Nx "$NX" --Ny "$NY" --gamma "$GAMMA" --kBT "$KBT" --seed "$SEED" --flow-mode taylor_green --flow-amplitude ${TG_U0:-0.08})
      write_params_tg "$case_name" "$out_dir" "$params" "$state"
      desc="periodic Taylor-Green, complete Q6+resampling"
      ;;
    poiseuille_wall_full)
      state=$(make_state "$case_name" --Lx 2.0 --Ly 1.0 --Nx "$NX" --Ny "$NY" --gamma "$GAMMA" --kBT "$KBT" --seed $((SEED+11)) --flow-mode zero)
      write_params_poiseuille "$case_name" "$out_dir" "$params" "$state"
      desc="periodic-x solid-wall Poiseuille, complete Q6+resampling"
      ;;
    open_rect_obstacle_full)
      state=$(make_state "$case_name" --Lx 2.0 --Ly 1.0 --Nx "$NX" --Ny "$NY" --gamma "$GAMMA" --kBT "$KBT" --seed $((SEED+22)) --flow-mode uniform --mean-ux ${ORECT_INITIAL_UX:-0.03} --solid-rect 0.25,0.50,0.35,0.60)
      write_params_open_rect "$case_name" "$out_dir" "$params" "$state"
      desc="inlet/outlet channel with rectangular solid obstacle, complete Q6+resampling"
      ;;
    segmented_u_turn_full)
      state=$(make_state "$case_name" --Lx 1.0 --Ly 1.0 --Nx "$NX" --Ny "$NY" --gamma "$GAMMA" --kBT "$KBT" --seed $((SEED+44)) --flow-mode zero)
      write_params_segmented_u_turn "$case_name" "$out_dir" "$params" "$state"
      desc="closed box with same-face segmented inlet/outlet on x=0, U-turn validation, complete Q6+resampling"
      ;;
    piston_virial_full)
      state=$(make_state "$case_name" --Lx 1.0 --Ly 1.0 --Nx "$NX" --Ny "$NY" --gamma "$GAMMA" --kBT "$KBT" --seed $((SEED+33)) --flow-mode zero --active-y-max ${PISTON_YTOP0:-0.95})
      write_params_piston_virial "$case_name" "$out_dir" "$params" "$state"
      desc="closed piston compression, complete Q6+resampling plus closed-capacity virial"
      ;;
    *)
      echo "Unknown validation case '$case_name'" >&2
      exit 2
      ;;
  esac
  printf '%s,%s,%s,%s,%s,%q\n' "$RUN_TAG" "$case_name" "$params" "$out_dir" "$state" "$desc" >> "$MANIFEST_CSV"
  echo "$params"
}

append_summary_row() {
  local case_name=$1 elapsed=$2 user=$3 sys=$4 summary_file=$5
  python3 - "$SUMMARY_CSV" "$RUN_TAG" "$case_name" "$elapsed" "$user" "$sys" "$summary_file" "${METRICS[@]}" <<'PY'
import csv
import sys
out_csv, run_tag, case_name, elapsed, user, sy, summary_file, *metrics = sys.argv[1:]
with open(summary_file, newline='') as f:
    rows = list(csv.DictReader(f))
if not rows:
    raise SystemExit(f"empty summary file: {summary_file}")
row = rows[-1]
out = {"runTag": run_tag, "case": case_name, "elapsed_s": elapsed, "user_s": user, "sys_s": sy}
for m in metrics:
    out[m] = row.get(m, "")
with open(out_csv, "a", newline="") as f:
    writer = csv.DictWriter(f, fieldnames=["runTag", "case", "elapsed_s", "user_s", "sys_s"] + metrics)
    writer.writerow(out)
PY
}

cat <<INFO
[0162-validation] root       : $ROOT_DIR
[0162-validation] binary     : $BIN
[0162-validation] run root   : $RUN_ROOT
[0162-validation] run tag    : $RUN_TAG
[0162-validation] grid/gamma : ${NX}x${NY} / $GAMMA
[0162-validation] steps      : $STEPS
[0162-validation] threads    : $THREADS
[0162-validation] projection backend : $PROJECTION_BACKEND
[0162-validation] cases      : $CASE_LIST
INFO

for case_name in $CASE_LIST; do
  params=$(prepare_case "$case_name")
  log="$RUN_ROOT/${case_name}.log"
  timelog="$RUN_ROOT/${case_name}.time"
  echo "[0162-validation] running $case_name"
  /usr/bin/time -f 'elapsed=%e user=%U sys=%S' "$BIN" "$params" > "$log" 2> "$timelog"
  elapsed=$(awk -F'[ =]' '/elapsed=/{print $2}' "$timelog")
  user=$(awk -F'[ =]' '/elapsed=/{print $4}' "$timelog")
  sys=$(awk -F'[ =]' '/elapsed=/{print $6}' "$timelog")
  append_summary_row "$case_name" "$elapsed" "$user" "$sys" "$RUN_ROOT/$case_name/summary_runtime.csv"
done

echo "[0162-validation] wrote $SUMMARY_CSV"
echo "[0162-validation] wrote $MANIFEST_CSV"
