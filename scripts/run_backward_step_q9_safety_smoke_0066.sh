#!/usr/bin/env bash
set -euo pipefail

# 0066c conservative guarded backward-step Q9 tuning smoke.
# The script keeps the Q6 reference and runs a very-soft Q9 setting by default.
# Older 0066b soft/medium cases remain available via explicit flags.

EXE="${EXE:-./build/src_mpcd_base}"
RUN_ROOT="${RUN_ROOT:-runs/backward_step_q9_safety_smoke_0066}"
INPUT_STATE="${INPUT_STATE:-initial_state_backward_step_96x48_g20_kbt0p0025.smpcd}"
CASE_STEPS="${CASE_STEPS:-1000}"
SUMMARY_EVERY="${SUMMARY_EVERY:-100}"
DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-$CASE_STEPS}"
NUM_THREADS="${NUM_THREADS:-4}"
AUTO_BUILD="${AUTO_BUILD:-1}"

# Default 0066c cases.
RUN_VSOFT_Q9="${RUN_VSOFT_Q9:-1}"
RUN_VSOFT_VIRIAL="${RUN_VSOFT_VIRIAL:-1}"
RUN_ULTRA_Q9="${RUN_ULTRA_Q9:-0}"

# Optional legacy 0066b comparison cases.  These are off by default because the
# previous run showed they were still too aggressive for validation.
RUN_0066B_SOFT="${RUN_0066B_SOFT:-0}"
RUN_0066B_MEDIUM="${RUN_0066B_MEDIUM:-0}"
RUN_0066B_SOFT_VIRIAL="${RUN_0066B_SOFT_VIRIAL:-0}"

# Tunable conservative defaults.
Q9_VSOFT_STRENGTH="${Q9_VSOFT_STRENGTH:-0.05}"
Q9_VSOFT_LIMITER="${Q9_VSOFT_LIMITER:-0.003}"
Q9_ULTRA_LIMITER="${Q9_ULTRA_LIMITER:-0.0025}"
Q9_VSOFT_OPEN_EXCL="${Q9_VSOFT_OPEN_EXCL:-5}"
Q9_VSOFT_HALO="${Q9_VSOFT_HALO:-5}"
Q9_VSOFT_MIN_MASS="${Q9_VSOFT_MIN_MASS:-8.0}"

if [[ "$AUTO_BUILD" == "1" ]]; then
  ./scripts/build_src_mpcd_base.sh
fi

if [[ ! -x "$EXE" ]]; then
  echo "ERROR: executable not found or not executable: $EXE" >&2
  exit 1
fi

if [[ ! -f "$INPUT_STATE" ]]; then
  cat >&2 <<MSG
ERROR: missing $INPUT_STATE
Generate it from MATLAB with:
  cd matlab
  generate_backward_step_state('output','../$INPUT_STATE','kBT',0.0025);
  cd ..
MSG
  exit 2
fi

mkdir -p "$RUN_ROOT/params" "$RUN_ROOT/logs"

write_common_params() {
  local file="$1"
  local label="$2"
  cat > "$file" <<KV
inputState = $INPUT_STATE
outputDir = $RUN_ROOT/$label

Lx = 2.0
Ly = 1.0
Nx = 96
Ny = 48
dt = 0.001
nSteps = $CASE_STEPS
summaryEvery = $SUMMARY_EVERY
dumpStateEvery = $DUMP_STATE_EVERY
numThreads = $NUM_THREADS
rngSeed = 12345

kBT = 0.0025
rotationAngle = 2.0943951023931953
randomRotationSign = true
gridShiftEnable = true
bodyAccelerationX = 0.0
bodyAccelerationY = 0.0

bcLeft = inlet
bcRight = outlet
bcBottom = solid
bcTop = solid
inletUxLeft = 0.05
inletUyLeft = 0.0
inletThermalNoise = 0.0
inletInjectionMode = cuda_recycle
inletSlabCells = 1.0
inletRandomizeTangential = true
inletReinjectBackflow = true

keepMeanFlowEnable = true
targetMeanUx = 0.05
targetMeanUy = 0.0

wallAccommodation = 1.0
wallKBT = 0.0025
wallThermalNoise = 1.0
thermostatEnable = true
thermostatMode = cell_relative_rescale
thermostatEvery = 1
thermostatTargetKBT = 0.0025
thermostatMinParticles = 3

immersedSolidEnable = true
immersedSolidShape = rectangle
immersedSolidXMin = 0.25
immersedSolidXMax = 0.65
immersedSolidYMin = 0.0
immersedSolidYMax = 0.50
immersedSolidVx = 0.0
immersedSolidVy = 0.0
immersedSolidOmega = 0.0
immersedSolidFractionSamples = 4

projectionEnable = true
projectionOperator = elliptic_fv_cg
projectionMaxIterations = 300
projectionTolerance = 1e-10
projectionMomentumCorrectionEnable = true
q6ProjectionStrength = 0.50
projectionImmersedSolidMaskEnable = true
projectionAllowUnmaskedImmersedSolid = false
projectionImmersedSolidFluidFractionThreshold = 0.50
projectionImmersedSolidCloseCutFaces = true
KV
}

append_q9_safety() {
  local file="$1"
  local strength="$2"
  local limiter="$3"
  local open_excl="$4"
  local halo="$5"
  local min_mass="$6"
  cat >> "$file" <<KV
q9MassFluxProjectionEnable = true
q9MassFluxProjectionStrength = $strength
q9DensityRelaxationBeta = 0.001
q9TargetFilter = elliptic_lowpass
q9LowKMaxIndex = 4
q9EllipticLowPassPasses = 1
q9MomentumCorrectionEnable = true
q9OpenBoundaryExclusionCells = $open_excl
q9ImmersedSolidHaloCells = $halo
q9MinCellMassForCorrection = $min_mass
q9CorrectionVelocityLimiter = $limiter
KV
}

make_q6() {
  local label="backstep_q6_keepmean_s050"
  local f="$RUN_ROOT/params/${label}.kv"
  write_common_params "$f" "$label"
  cat >> "$f" <<KV
method = q6
q9MassFluxProjectionEnable = false
virialDiagnosticsEnable = false
virialKickEnable = false
KV
  echo "$f"
}

make_q9_vsoft() {
  local label="backstep_q9_safe_vsoft_s005_lim003_h5_e5_m8"
  local f="$RUN_ROOT/params/${label}.kv"
  write_common_params "$f" "$label"
  cat >> "$f" <<KV
method = q9
KV
  append_q9_safety "$f" "$Q9_VSOFT_STRENGTH" "$Q9_VSOFT_LIMITER" "$Q9_VSOFT_OPEN_EXCL" "$Q9_VSOFT_HALO" "$Q9_VSOFT_MIN_MASS"
  cat >> "$f" <<KV
virialDiagnosticsEnable = false
virialKickEnable = false
KV
  echo "$f"
}

make_q9_ultra() {
  local label="backstep_q9_safe_ultra_s005_lim0025_h5_e5_m8"
  local f="$RUN_ROOT/params/${label}.kv"
  write_common_params "$f" "$label"
  cat >> "$f" <<KV
method = q9
KV
  append_q9_safety "$f" "$Q9_VSOFT_STRENGTH" "$Q9_ULTRA_LIMITER" "$Q9_VSOFT_OPEN_EXCL" "$Q9_VSOFT_HALO" "$Q9_VSOFT_MIN_MASS"
  cat >> "$f" <<KV
virialDiagnosticsEnable = false
virialKickEnable = false
KV
  echo "$f"
}

make_q9_virial_vsoft() {
  local label="backstep_q9_virial_safe_vsoft_s005_lim003_h5_e5_m8"
  local f="$RUN_ROOT/params/${label}.kv"
  write_common_params "$f" "$label"
  cat >> "$f" <<KV
method = q9_virial
KV
  append_q9_safety "$f" "$Q9_VSOFT_STRENGTH" "$Q9_VSOFT_LIMITER" "$Q9_VSOFT_OPEN_EXCL" "$Q9_VSOFT_HALO" "$Q9_VSOFT_MIN_MASS"
  cat >> "$f" <<KV
virialDiagnosticsEnable = true
virialKickEnable = true
virialK = 0.50
virialBeta = 0.05
virialOpenBoundaryExclusionCells = $Q9_VSOFT_OPEN_EXCL
virialMomentumCorrectionEnable = true
KV
  echo "$f"
}

make_q9_0066b_soft() {
  local label="backstep_q9_safe_soft_s010_lim005_h4_e4"
  local f="$RUN_ROOT/params/${label}.kv"
  write_common_params "$f" "$label"
  cat >> "$f" <<KV
method = q9
KV
  append_q9_safety "$f" "0.10" "0.005" "4" "4" "6.0"
  cat >> "$f" <<KV
virialDiagnosticsEnable = false
virialKickEnable = false
KV
  echo "$f"
}

make_q9_0066b_medium() {
  local label="backstep_q9_safe_medium_s025_lim010_h3_e3"
  local f="$RUN_ROOT/params/${label}.kv"
  write_common_params "$f" "$label"
  cat >> "$f" <<KV
method = q9
KV
  append_q9_safety "$f" "0.25" "0.01" "3" "3" "6.0"
  cat >> "$f" <<KV
virialDiagnosticsEnable = false
virialKickEnable = false
KV
  echo "$f"
}

make_q9_virial_0066b_soft() {
  local label="backstep_q9_virial_safe_soft_s010_lim005_h4_e4"
  local f="$RUN_ROOT/params/${label}.kv"
  write_common_params "$f" "$label"
  cat >> "$f" <<KV
method = q9_virial
KV
  append_q9_safety "$f" "0.10" "0.005" "4" "4" "6.0"
  cat >> "$f" <<KV
virialDiagnosticsEnable = true
virialKickEnable = true
virialK = 0.50
virialBeta = 0.05
virialOpenBoundaryExclusionCells = 4
virialMomentumCorrectionEnable = true
KV
  echo "$f"
}

run_case() {
  local params="$1"
  local label
  label="$(basename "$params" .kv)"
  echo "=== 0066c running $label ==="
  "$EXE" "$params" | tee "$RUN_ROOT/logs/${label}.log"
}

cases=("$(make_q6)")
if [[ "$RUN_VSOFT_Q9" == "1" ]]; then
  cases+=("$(make_q9_vsoft)")
fi
if [[ "$RUN_ULTRA_Q9" == "1" ]]; then
  cases+=("$(make_q9_ultra)")
fi
if [[ "$RUN_VSOFT_VIRIAL" == "1" ]]; then
  cases+=("$(make_q9_virial_vsoft)")
fi
if [[ "$RUN_0066B_SOFT" == "1" ]]; then
  cases+=("$(make_q9_0066b_soft)")
fi
if [[ "$RUN_0066B_MEDIUM" == "1" ]]; then
  cases+=("$(make_q9_0066b_medium)")
fi
if [[ "$RUN_0066B_SOFT_VIRIAL" == "1" ]]; then
  cases+=("$(make_q9_virial_0066b_soft)")
fi

for p in "${cases[@]}"; do
  run_case "$p"
done

cat <<MSG
[0066c] Done.
Analyze with:
  cd matlab
  S = analyze_backward_step_q9_safety_smoke_0066('root','..');
  cd ..
Summary will be written to:
  $RUN_ROOT/summary_q9_safety_smoke_0066.csv
MSG
