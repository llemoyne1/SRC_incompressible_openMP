#!/usr/bin/env bash
set -euo pipefail

# One short livevis smoke using the livevis-enabled resident binary.
# Expected solveur runs: 1.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BIN=${BIN:-build/src_mpcd_base_cuda_q6_resident_livevis_0486}
if [[ ! -x "$BIN" ]]; then
  echo "[0486-livevis-smoke] ERROR: missing executable: $BIN" >&2
  echo "Build it first with: bash scripts/build_src_mpcd_cuda_q6_resident_livevis_0486.sh" >&2
  exit 2
fi

RUN_ROOT=${RUN_ROOT:-runs/0486_livevis_tg_smoke}
rm -rf "$RUN_ROOT"

BIN="$BIN" \
BASE_RUN_ROOT="$RUN_ROOT" \
RUN_MODES="${RUN_MODES:-src-resampling}" \
LIVE_VIS_ENABLE=1 \
LIVE_VIS_FIELD="${LIVE_VIS_FIELD:-speed}" \
LIVE_VIS_EVERY="${LIVE_VIS_EVERY:-5}" \
LIVE_VIS_NX="${LIVE_VIS_NX:-256}" \
LIVE_VIS_NY="${LIVE_VIS_NY:-256}" \
LIVE_VIS_WINDOW_SCALE="${LIVE_VIS_WINDOW_SCALE:-2}" \
LIVE_VIS_HOLD_ON_EXIT="${LIVE_VIS_HOLD_ON_EXIT:-0}" \
LIVE_VIS_CONTROL_LOG="${LIVE_VIS_CONTROL_LOG:-1}" \
LIVE_PROGRESS="${LIVE_PROGRESS:-1}" \
LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-1}" \
LIVE_VIS_COLORMAP="${LIVE_VIS_COLORMAP:-blue_red}" \
LIVE_VIS_CLIP="${LIVE_VIS_CLIP:--1}" \
LIVE_VIS_GAIN="${LIVE_VIS_GAIN:-1}" \
LIVE_VIS_SMOOTH_PASSES="${LIVE_VIS_SMOOTH_PASSES:-1}" \
LIVE_VIS_CUDA_FIELD="${LIVE_VIS_CUDA_FIELD:-1}" \
LIVE_VIS_CUDA_SNAPSHOT="${LIVE_VIS_CUDA_SNAPSHOT:-1}" \
LIVE_VIS_LOG_SOURCE="${LIVE_VIS_LOG_SOURCE:-1}" \
LIVE_VIS_CONTROL_FILE="${LIVE_VIS_CONTROL_FILE:-$RUN_ROOT/livevis_control.kv}" \
NX="${NX:-64}" NY="${NY:-64}" GAMMA="${GAMMA:-40}" \
STEPS="${STEPS:-100}" SUMMARY_EVERY="${SUMMARY_EVERY:-20}" \
FILTERED_RECORDING_ENABLE="${FILTERED_RECORDING_ENABLE:-0}" \
AUTO_BUILD=0 BUILD_IF_STALE=0 FORCE_BUILD=0 \
bash scripts/run_ok_tg.sh
