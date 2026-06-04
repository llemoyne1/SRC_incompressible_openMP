#!/usr/bin/env bash
set -euo pipefail

# 0064b fast Q9+virial inlet/outlet sweep.
# Run from the repository root.

EXE="${EXE:-./build/src_mpcd_base}"
TEMPLATE="${TEMPLATE:-examples/params_open_channel_q9_virial_inlet_outlet_keepmean_64x32.kv}"
SWEEP_ROOT="${SWEEP_ROOT:-runs/open_channel_q9_virial_inlet_outlet_fast_sweep}"
SWEEP_STEPS="${SWEEP_STEPS:-300}"
SUMMARY_EVERY="${SUMMARY_EVERY:-100}"
NUM_THREADS="${NUM_THREADS:-4}"
RUN_NOVIRIAL_REF="${RUN_NOVIRIAL_REF:-0}"

if [[ ! -x "$EXE" ]]; then
  echo "ERROR: executable not found or not executable: $EXE" >&2
  echo "Build first, e.g.: ./scripts/build_src_mpcd_base.sh" >&2
  exit 1
fi

if [[ ! -f "$TEMPLATE" ]]; then
  echo "ERROR: template params file not found: $TEMPLATE" >&2
  exit 1
fi

mkdir -p "$SWEEP_ROOT/params" "$SWEEP_ROOT/logs"

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
  local virial_enable="$2"
  local virial_k="$3"
  local virial_beta="$4"
  local exclusion_cells="$5"

  local params="$SWEEP_ROOT/params/${case_label}.kv"
  cp "$TEMPLATE" "$params"

  set_kv "$params" outputDir "$SWEEP_ROOT/${case_label}"
  set_kv "$params" nSteps "$SWEEP_STEPS"
  set_kv "$params" summaryEvery "$SUMMARY_EVERY"
  set_kv "$params" dumpStateEvery "$SWEEP_STEPS"
  set_kv "$params" numThreads "$NUM_THREADS"

  # Keep the validated 0064 open-channel liquid-closure path.
  set_kv "$params" method q9_virial
  set_kv "$params" keepMeanFlowEnable true
  set_kv "$params" targetMeanUx 0.05
  set_kv "$params" targetMeanUy 0.0
  set_kv "$params" projectionEnable true
  set_kv "$params" q6ProjectionStrength 0.50
  set_kv "$params" q9MassFluxProjectionEnable true
  set_kv "$params" q9MassFluxProjectionStrength 1.00
  set_kv "$params" q9DensityRelaxationBeta 0.001
  set_kv "$params" immersedSolidEnable false

  if [[ "$virial_enable" == "true" ]]; then
    set_kv "$params" virialDiagnosticsEnable true
    set_kv "$params" virialKickEnable true
    set_kv "$params" virialK "$virial_k"
    set_kv "$params" virialBeta "$virial_beta"
    set_kv "$params" virialOpenBoundaryExclusionCells "$exclusion_cells"
  else
    set_kv "$params" method q9
    set_kv "$params" virialDiagnosticsEnable false
    set_kv "$params" virialKickEnable false
  fi

  echo "$params"
}

run_case() {
  local params="$1"
  local case_label
  case_label="$(basename "$params" .kv)"
  local log="$SWEEP_ROOT/logs/${case_label}.log"
  echo "=== 0064b running ${case_label} ==="
  echo "params: $params"
  "$EXE" "$params" | tee "$log"
}

cases=()

if [[ "$RUN_NOVIRIAL_REF" == "1" ]]; then
  cases+=("$(make_case q9_novirial_ref false 0.0 0.0 0)")
fi

cases+=("$(make_case virial_K0p50_b0p05_ex3 true 0.50 0.05 3)")
cases+=("$(make_case virial_K1p00_b0p05_ex3 true 1.00 0.05 3)")
cases+=("$(make_case virial_K0p50_b0p10_ex3 true 0.50 0.10 3)")
cases+=("$(make_case virial_K0p50_b0p05_ex5 true 0.50 0.05 5)")

for params in "${cases[@]}"; do
  run_case "$params"
done

cat <<MSG

0064b fast virial sweep completed.
Output root:
  $SWEEP_ROOT

MATLAB summary:
  cd matlab
  S = analyze_open_channel_q9_virial_inlet_outlet_fast_sweep('root','..');
  cd ..
MSG
