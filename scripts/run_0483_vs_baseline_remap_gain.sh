#!/usr/bin/env bash
set -euo pipefail

# Optional A/B run: compare an already-built baseline binary against the 0483 candidate.
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"

: "${BASELINE_BIN:?Set BASELINE_BIN to the 0482/0477 resident baseline binary}"
: "${CANDIDATE_BIN:?Set CANDIDATE_BIN to the 0483 candidate binary}"

GAIN_ROOT="${GAIN_ROOT:-runs/0483_remap_fusion_gain_ab}"
BASELINE_ROOT="$GAIN_ROOT/baseline"
CANDIDATE_ROOT="$GAIN_ROOT/candidate"
SCALE_CASES="${SCALE_CASES:-64x64x40 96x96x40 128x128x40}"
RUN_MODES="${RUN_MODES:-src-resampling src-q6-resampling}"
SEEDS="${SEEDS:-1628638}"
STEPS="${STEPS:-200}"
SUMMARY_EVERY="${SUMMARY_EVERY:-50}"
DEVICE_GATE_EVERY="${DEVICE_GATE_EVERY:-50}"
MAX_SUMMARY_DELTA_TOL="${MAX_SUMMARY_DELTA_TOL:-1e-9}"
LIVE_PROGRESS="${LIVE_PROGRESS:-1}"

rm -rf "$GAIN_ROOT"
mkdir -p "$GAIN_ROOT"

echo "[0483-AB] baseline=$BASELINE_BIN"
BIN="$BASELINE_BIN" \
BASE_0483_ROOT="$BASELINE_ROOT" \
SCALE_CASES="$SCALE_CASES" \
RUN_MODES="$RUN_MODES" \
SEEDS="$SEEDS" \
STEPS="$STEPS" \
SUMMARY_EVERY="$SUMMARY_EVERY" \
DEVICE_GATE_EVERY="$DEVICE_GATE_EVERY" \
MAX_SUMMARY_DELTA_TOL="$MAX_SUMMARY_DELTA_TOL" \
LIVE_PROGRESS="$LIVE_PROGRESS" \
bash scripts/run_0483_remap_fusion_cpu_cuda_matrix.sh

echo "[0483-AB] candidate=$CANDIDATE_BIN"
BIN="$CANDIDATE_BIN" \
BASE_0483_ROOT="$CANDIDATE_ROOT" \
SCALE_CASES="$SCALE_CASES" \
RUN_MODES="$RUN_MODES" \
SEEDS="$SEEDS" \
STEPS="$STEPS" \
SUMMARY_EVERY="$SUMMARY_EVERY" \
DEVICE_GATE_EVERY="$DEVICE_GATE_EVERY" \
MAX_SUMMARY_DELTA_TOL="$MAX_SUMMARY_DELTA_TOL" \
LIVE_PROGRESS="$LIVE_PROGRESS" \
bash scripts/run_0483_remap_fusion_cpu_cuda_matrix.sh

python3 scripts/compare_0483_remap_fusion_roots.py "$BASELINE_ROOT" "$CANDIDATE_ROOT" --out-root "$GAIN_ROOT"
