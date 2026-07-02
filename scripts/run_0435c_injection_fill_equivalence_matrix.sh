#!/usr/bin/env bash
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

SCRIPT=${SCRIPT:-scripts/run_injection_fill_resampling_validation_0342a_livevis.sh}

BASE=${BASE:-runs/0435c_compare_fill}
PRE_BIN=${PRE_BIN:-build/src_mpcd_base_cuda_q6_resident_0400_livevis_pre0435c}
NEW_BIN=${NEW_BIN:-build/src_mpcd_base_cuda_q6_resident_0400_livevis_0435c}

FILL_STEPS=${FILL_STEPS:-100}
RUN_CASES=${RUN_CASES:-src}
LIVE_VIS_ENABLE=${LIVE_VIS_ENABLE:-0}
FILTERED_RECORDING_ENABLE=${FILTERED_RECORDING_ENABLE:-0}

# On force un état initial commun aux trois runs.
INIT_ROOT=${INIT_ROOT:-$BASE/_init}
FILL_INITIAL_STATE=${FILL_INITIAL_STATE:-$INIT_ROOT/initial_state_injection_fill_pool_0431.smpcd}

if [[ ! -x "$PRE_BIN" ]]; then
  echo "ERROR missing PRE_BIN=$PRE_BIN" >&2
  exit 127
fi

if [[ ! -x "$NEW_BIN" ]]; then
  echo "ERROR missing NEW_BIN=$NEW_BIN" >&2
  exit 127
fi

if [[ ! -f "$SCRIPT" ]]; then
  echo "ERROR missing SCRIPT=$SCRIPT" >&2
  exit 127
fi

rm -rf "$BASE"
mkdir -p "$BASE" "$INIT_ROOT"

run_one () {
  local label="$1"
  local bin="$2"
  local shared="$3"

  local dst="$BASE/injection_fill_${label}"
  local run_root="$dst/raw_run"
  local log="$dst/run.log"

  mkdir -p "$dst"

  echo
  echo "============================================================"
  echo "[0435c-fill-eq] label=$label"
  echo "[0435c-fill-eq] bin=$bin"
  echo "[0435c-fill-eq] shared0251=$shared"
  echo "[0435c-fill-eq] script=$SCRIPT"
  echo "[0435c-fill-eq] state=$FILL_INITIAL_STATE"
  echo "[0435c-fill-eq] run_root=$run_root"
  echo "============================================================"

  marker="$(mktemp)"
  touch "$marker"

  env \
    BIN="$bin" \
    RUN_ROOT="$run_root" \
    INIT_ROOT="$INIT_ROOT" \
    FILL_INITIAL_STATE="$FILL_INITIAL_STATE" \
    RUN_CASES="$RUN_CASES" \
    FILL_STEPS="$FILL_STEPS" \
    LIVE_VIS_ENABLE="$LIVE_VIS_ENABLE" \
    FILTERED_RECORDING_ENABLE="$FILTERED_RECORDING_ENABLE" \
    MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_SHARED_0251_0260="$shared" \
    MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_SHARED_0251_0260_STRICT="$shared" \
    MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_CONSUME_STRICT="$shared" \
    bash "$SCRIPT" 2>&1 | tee "$log"

  latest_summary="$(find "$run_root" -type f -name summary_runtime.csv -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -n 1 | cut -d' ' -f2- || true)"

  if [[ -z "$latest_summary" ]]; then
    latest_summary="$(find runs -type f -name summary_runtime.csv -newer "$marker" -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -n 1 | cut -d' ' -f2- || true)"
  fi

  rm -f "$marker"

  if [[ -z "$latest_summary" ]]; then
    echo "ERROR: no summary_runtime.csv found for label=$label" >&2
    exit 3
  fi

  local outdir
  outdir="$(dirname "$latest_summary")"

  echo "[0435c-fill-eq] latest_summary=$latest_summary"
  echo "[0435c-fill-eq] outdir=$outdir"

  mkdir -p "$dst/src"
  rm -rf "$dst/src/output"
  cp -a "$outdir" "$dst/src/output"

  echo "[0435c-fill-eq] copied $outdir -> $dst/src/output"
}

run_one ref_old_no_shared "$PRE_BIN" 0
run_one new_no_shared     "$NEW_BIN" 0
run_one new_shared        "$NEW_BIN" 1

echo
echo "=== copied outputs ==="
find "$BASE" -maxdepth 5 -type f \
  \( -name summary_runtime.csv -o -name cuda_persistent_src_collision_thermostat_0215.csv -o -name params_used.kv -o -name run.log \) \
  -printf '%p\n' | sort
