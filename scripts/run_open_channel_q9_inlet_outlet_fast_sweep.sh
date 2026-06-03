#!/usr/bin/env bash
set -euo pipefail

# 0063b fast Q6/Q9 inlet/outlet sweep.
# Run from the repository root.

EXE="${EXE:-./build/src_mpcd_base}"
TEMPLATE="${TEMPLATE:-examples/params_open_channel_q9_inlet_outlet_keepmean_64x32.kv}"
SWEEP_ROOT="${SWEEP_ROOT:-runs/open_channel_q9_inlet_outlet_fast_sweep}"
SWEEP_STEPS="${SWEEP_STEPS:-600}"
SUMMARY_EVERY="${SUMMARY_EVERY:-100}"
NUM_THREADS="${NUM_THREADS:-4}"
RUN_NO_KEEPMEAN="${RUN_NO_KEEPMEAN:-0}"
RUN_Q6_STRONG="${RUN_Q6_STRONG:-0}"

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
  local method="$2"
  local keep_mean="$3"
  local q6_strength="$4"
  local q9_enable="$5"
  local q9_beta="$6"
  local q9_strength="$7"

  local params="$SWEEP_ROOT/params/${case_label}.kv"
  cp "$TEMPLATE" "$params"

  set_kv "$params" outputDir "$SWEEP_ROOT/${case_label}"
  set_kv "$params" nSteps "$SWEEP_STEPS"
  set_kv "$params" summaryEvery "$SUMMARY_EVERY"
  set_kv "$params" dumpStateEvery "$SWEEP_STEPS"
  set_kv "$params" numThreads "$NUM_THREADS"

  set_kv "$params" method "$method"
  set_kv "$params" keepMeanFlowEnable "$keep_mean"
  set_kv "$params" q6ProjectionStrength "$q6_strength"
  set_kv "$params" q9MassFluxProjectionEnable "$q9_enable"
  set_kv "$params" q9DensityRelaxationBeta "$q9_beta"
  set_kv "$params" q9MassFluxProjectionStrength "$q9_strength"

  # Keep 0063b virial-free and immersed-solid-free.
  set_kv "$params" virialDiagnosticsEnable false
  set_kv "$params" virialKickEnable false
  set_kv "$params" immersedSolidEnable false

  echo "$params"
}

run_case() {
  local params="$1"
  local case_label
  case_label="$(basename "$params" .kv)"
  local log="$SWEEP_ROOT/logs/${case_label}.log"
  echo "=== 0063b running ${case_label} ==="
  echo "params: $params"
  "$EXE" "$params" | tee "$log"
}

cases=()

cases+=("$(make_case q6_keepmean_s050 q6 true 0.50 false 0.0 0.0)")

if [[ "$RUN_Q6_STRONG" == "1" ]]; then
  cases+=("$(make_case q6_keepmean_s100 q6 true 1.00 false 0.0 0.0)")
fi

cases+=("$(make_case q9_keepmean_b0001 q9 true 0.50 true 0.001 1.00)")
cases+=("$(make_case q9_keepmean_b0005 q9 true 0.50 true 0.005 1.00)")
cases+=("$(make_case q9_keepmean_b0010 q9 true 0.50 true 0.010 1.00)")

if [[ "$RUN_NO_KEEPMEAN" == "1" ]]; then
  cases+=("$(make_case q6_nokeep_s050 q6 false 0.50 false 0.0 0.0)")
  cases+=("$(make_case q9_nokeep_b0005 q9 false 0.50 true 0.005 1.00)")
fi

for params in "${cases[@]}"; do
  run_case "$params"
done

cat <<MSG

0063b fast sweep completed.
Output root:
  $SWEEP_ROOT

MATLAB summary:
  cd matlab
  S = analyze_open_channel_q9_inlet_outlet_fast_sweep('root','..');
  cd ..
MSG
