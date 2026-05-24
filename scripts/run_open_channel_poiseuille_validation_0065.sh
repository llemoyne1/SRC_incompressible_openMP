#!/usr/bin/env bash
set -euo pipefail

# 0065 structured open-channel / Poiseuille-style inlet/outlet validation.
# Run from the repository root.

EXE="${EXE:-./build/src_mpcd_base}"
TEMPLATE="${TEMPLATE:-examples/params_open_channel_q9_virial_inlet_outlet_keepmean_64x32.kv}"
RUN_ROOT="${RUN_ROOT:-runs/open_channel_poiseuille_validation_0065}"
CASE_STEPS="${CASE_STEPS:-3000}"
SUMMARY_EVERY="${SUMMARY_EVERY:-100}"
DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-$CASE_STEPS}"
NUM_THREADS="${NUM_THREADS:-4}"
AUTO_BUILD="${AUTO_BUILD:-1}"
RUN_NO_KEEPMEAN="${RUN_NO_KEEPMEAN:-0}"
Q9_BETA="${Q9_BETA:-0.001}"

if [[ "$AUTO_BUILD" == "1" ]]; then
  ./scripts/build_src_mpcd_base.sh
fi

if [[ ! -x "$EXE" ]]; then
  echo "ERROR: executable not found or not executable: $EXE" >&2
  echo "Build first, e.g.: ./scripts/build_src_mpcd_base.sh" >&2
  exit 1
fi

if [[ ! -f "$TEMPLATE" ]]; then
  echo "ERROR: template params file not found: $TEMPLATE" >&2
  exit 1
fi

if [[ ! -f initial_state_open_channel_64x32_g20_kbt0p01.smpcd ]]; then
  cat >&2 <<'MSG'
ERROR: missing initial_state_open_channel_64x32_g20_kbt0p01.smpcd
Generate it from MATLAB with:
  cd matlab
  generate_open_channel_classic_state('output','../initial_state_open_channel_64x32_g20_kbt0p01.smpcd');
  cd ..
MSG
  exit 2
fi

mkdir -p "$RUN_ROOT/params" "$RUN_ROOT/logs"

set_kv() {
  local file="$1"
  local key="$2"
  local value="$3"
  if grep -Eq "^[[:space:]]*${key}[[:space:]]*=" "$file"; then
    sed -i -E "s|^[[:space:]]*${key}[[:space:]]*=.*|${key} = ${value}|" "$file"
  else
    printf '\n%s = %s\n' "$key" "$value" >> "$file"
  fi
}

make_case() {
  local case_label="$1"
  local method="$2"
  local q9_enable="$3"
  local virial_enable="$4"
  local keep_mean="$5"

  local params="$RUN_ROOT/params/${case_label}.kv"
  cp "$TEMPLATE" "$params"

  set_kv "$params" outputDir "$RUN_ROOT/${case_label}"
  set_kv "$params" nSteps "$CASE_STEPS"
  set_kv "$params" summaryEvery "$SUMMARY_EVERY"
  set_kv "$params" dumpStateEvery "$DUMP_STATE_EVERY"
  set_kv "$params" numThreads "$NUM_THREADS"
  set_kv "$params" rngSeed 12345

  # Common open-channel geometry and inlet.
  set_kv "$params" bcLeft inlet
  set_kv "$params" bcRight outlet
  set_kv "$params" bcBottom solid
  set_kv "$params" bcTop solid
  set_kv "$params" inletUxLeft 0.05
  set_kv "$params" inletUyLeft 0.0
  set_kv "$params" inletThermalNoise 0.0
  set_kv "$params" inletInjectionMode cuda_recycle
  set_kv "$params" inletSlabCells 1.0
  set_kv "$params" inletRandomizeTangential true
  set_kv "$params" inletReinjectBackflow true

  # Controlled Poiseuille-style/open-channel reference.
  set_kv "$params" keepMeanFlowEnable "$keep_mean"
  set_kv "$params" targetMeanUx 0.05
  set_kv "$params" targetMeanUy 0.0
  set_kv "$params" bodyAccelerationX 0.0
  set_kv "$params" bodyAccelerationY 0.0

  set_kv "$params" method "$method"
  set_kv "$params" projectionEnable true
  set_kv "$params" q6ProjectionStrength 0.50
  set_kv "$params" projectionMomentumCorrectionEnable true
  set_kv "$params" projectionImmersedSolidMaskEnable false
  set_kv "$params" immersedSolidEnable false

  if [[ "$q9_enable" == "true" ]]; then
    set_kv "$params" q9MassFluxProjectionEnable true
    set_kv "$params" q9MassFluxProjectionStrength 1.00
    set_kv "$params" q9DensityRelaxationBeta "$Q9_BETA"
    set_kv "$params" q9TargetFilter elliptic_lowpass
    set_kv "$params" q9LowKMaxIndex 4
    set_kv "$params" q9EllipticLowPassPasses 1
    set_kv "$params" q9MomentumCorrectionEnable true
  else
    set_kv "$params" q9MassFluxProjectionEnable false
  fi

  if [[ "$virial_enable" == "true" ]]; then
    set_kv "$params" virialDiagnosticsEnable true
    set_kv "$params" virialKickEnable true
    set_kv "$params" virialK 0.50
    set_kv "$params" virialBeta 0.05
    set_kv "$params" virialOpenBoundaryExclusionCells 3
    set_kv "$params" virialMomentumCorrectionEnable true
  else
    set_kv "$params" virialDiagnosticsEnable false
    set_kv "$params" virialKickEnable false
  fi

  echo "$params"
}

run_case() {
  local params="$1"
  local case_label
  case_label="$(basename "$params" .kv)"
  local log="$RUN_ROOT/logs/${case_label}.log"
  echo "=== 0065 running ${case_label} ==="
  echo "params: $params"
  "$EXE" "$params" | tee "$log"
}

cases=()
cases+=("$(make_case q6_keepmean_s050 q6 false false true)")
cases+=("$(make_case q9_keepmean_b0001 q9 true false true)")
cases+=("$(make_case q9_virial_keepmean_K0p50_b0p05_ex3 q9_virial true true true)")

if [[ "$RUN_NO_KEEPMEAN" == "1" ]]; then
  cases+=("$(make_case q9_virial_nokeep_K0p50_b0p05_ex3 q9_virial true true false)")
fi

for params in "${cases[@]}"; do
  run_case "$params"
done

cat <<MSG

0065 open-channel / Poiseuille-style validation completed.
Output root:
  $RUN_ROOT

MATLAB analysis:
  cd matlab
  S = analyze_open_channel_poiseuille_validation_0065('root','..');
  cd ..
MSG
