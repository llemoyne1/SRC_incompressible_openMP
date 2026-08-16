#!/usr/bin/env bash
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
RUNNER="${RUNNER:-tools/run_0493x8p_zovatto_outlet_compare_tmp.sh}"
[[ -f "$RUNNER" ]] || { echo "[0493x8q] missing $RUNNER" >&2; exit 2; }
STEPS="${STEPS:-100}"
SUMMARY_EVERY="${SUMMARY_EVERY:-1}"
KBT="${KBT:-0.125}"
RUN_MODES="${RUN_MODES:-src}"
SEED="${SEED:-493920}"
ROOT_TAG="${ROOT_TAG:-runs/0493x8q_neumann_smoke_${RUN_MODES}_kbt${KBT}}"
echo "[0493x8q] mode=$RUN_MODES kBT=$KBT steps=$STEPS"
ROOT="$PWD" RUN_MODES="$RUN_MODES" OUTLET_MODE=neumann KBT="$KBT" \
BASE_RUN_ROOT="$ROOT_TAG" CLEAN_RUN_ROOT=1 SEED="$SEED" \
STEPS="$STEPS" SUMMARY_EVERY="$SUMMARY_EVERY" DUMP_STATE_EVERY=1000000 \
PROJECTION_MAX_ITERATIONS=2500 LIVE_PROGRESS=1 LIVE_VIS_ENABLE=0 \
LIVE_VIS_HOLD_ON_EXIT=0 FILTERED_RECORDING_ENABLE=0 TOPO_BENCHMARK_ENABLE=false \
DARCY_COST_EVERY=1000000 bash "$RUNNER"
SUMMARY="$ROOT_TAG/$RUN_MODES/output/summary_runtime.csv"
python3 tools/check_0493x8q_neumann_smoke.py "$SUMMARY" --expected-n0 9600000
