#!/usr/bin/env bash
set -euo pipefail

# 0348b/topo: run the 0348a diagonal benchmark and compute final-window
# statistics from topo_benchmark_0348.csv.  Set RUN_FIRST=0 to only analyze an
# existing run directory.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

TAG="${TAG:-topo_darcy_diagonal_benchmark_0348b}"
RUN_FIRST="${RUN_FIRST:-1}"
TAIL_FRACTION="${TAIL_FRACTION:-0.5}"
STEP_MIN="${STEP_MIN:-}"
TIME_MIN="${TIME_MIN:-}"

if [[ "$RUN_FIRST" == "1" || "$RUN_FIRST" == "true" || "$RUN_FIRST" == "TRUE" ]]; then
  TAG="$TAG" \
  BIN="${BIN:-build/src_mpcd_base_cuda_topo_0348a}" \
  LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-0}" \
  STEPS="${STEPS:-3000}" \
  TOPO_BENCHMARK_EVERY="${TOPO_BENCHMARK_EVERY:-20}" \
  FORCE_REBUILD="${FORCE_REBUILD:-0}" \
    bash scripts/run_topo_darcy_diagonal_benchmark_0348a.sh
fi

csv="runs/${TAG}/output/${TOPO_BENCHMARK_FILENAME:-topo_benchmark_0348.csv}"
out="runs/${TAG}/topo_benchmark_window_stats_0348b.csv"

args=(--csv "$csv" --out "$out" --tail-fraction "$TAIL_FRACTION")
if [[ -n "$STEP_MIN" ]]; then args+=(--step-min "$STEP_MIN"); fi
if [[ -n "$TIME_MIN" ]]; then args+=(--time-min "$TIME_MIN"); fi

python3 scripts/analyze_topo_benchmark_window_0348b.py "${args[@]}"

summary="runs/${TAG}/diagonal_benchmark_window_0348b_summary.csv"
echo "tag,benchmarkCsv,windowStatsCsv" > "$summary"
printf '%s,%s,%s\n' "$TAG" "$csv" "$out" >> "$summary"

echo "[0348b-window] summary=$summary"
cat "$summary"
