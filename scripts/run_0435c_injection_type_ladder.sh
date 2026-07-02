#!/usr/bin/env bash
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

BASE=${BASE:-runs/0435c_compare_type_ladder}
SCRIPT=${SCRIPT:-scripts/run_0434_injection_type1_into_type2.sh}

PRE_BIN=${PRE_BIN:-build/src_mpcd_base_cuda_q6_resident_0400_livevis_pre0435c}
NEW_BIN=${NEW_BIN:-build/src_mpcd_base_cuda_q6_resident_0400_livevis_0435c}

NX=${NX:-120}
NY=${NY:-30}
GAMMA=${GAMMA:-4}
STEPS=${STEPS:-100}

rm -rf "$BASE"
mkdir -p "$BASE"

run_one () {
  local variant="$1"
  local label="$2"
  local bin="$3"
  local shared="$4"
  local background_type="$5"
  local inject_type="$6"

  local dst="$BASE/${variant}_${label}"
  local log="$dst/run.log"

  mkdir -p "$dst"

  echo
  echo "============================================================"
  echo "[0435c-type-ladder] variant=$variant label=$label"
  echo "[0435c-type-ladder] background_type=$background_type inject_type=$inject_type"
  echo "[0435c-type-ladder] bin=$bin shared=$shared"
  echo "============================================================"

  marker="$(mktemp)"
  touch "$marker"

  env \
    BIN="$bin" \
    BACKGROUND_TYPE="$background_type" \
    INJECT_TYPE="$inject_type" \
    MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_SHARED_0251_0260="$shared" \
    MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_SHARED_0251_0260_STRICT="$shared" \
    MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_CONSUME_STRICT="$shared" \
    RUN_MODES=src \
    NX="$NX" NY="$NY" GAMMA="$GAMMA" STEPS="$STEPS" \
    LIVE_VIS_ENABLE=0 \
    FILTERED_RECORDING_ENABLE=0 \
    bash "$SCRIPT" 2>&1 | tee "$log"

  latest_summary="$(find runs -type f -name summary_runtime.csv -newer "$marker" \
    -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -n 1 | cut -d' ' -f2- || true)"

  rm -f "$marker"

  if [[ -z "$latest_summary" ]]; then
    echo "ERROR: no summary_runtime.csv found for $variant/$label" >&2
    exit 3
  fi

  outdir="$(dirname "$latest_summary")"
  srcroot="$(dirname "$outdir")"

  echo "[0435c-type-ladder] latest_summary=$latest_summary"
  echo "[0435c-type-ladder] srcroot=$srcroot"

  mkdir -p "$dst/src"
  rm -rf "$dst/src/output"
  cp -a "$outdir" "$dst/src/output"
}

run_variant () {
  local variant="$1"
  local background_type="$2"
  local inject_type="$3"

  run_one "$variant" ref_old_no_shared "$PRE_BIN" 0 "$background_type" "$inject_type"
  run_one "$variant" new_no_shared     "$NEW_BIN" 0 "$background_type" "$inject_type"
  run_one "$variant" new_shared        "$NEW_BIN" 1 "$background_type" "$inject_type"
}

run_variant mono_type1 1 1
run_variant mono_type2 2 2
run_variant type1_into_type2 2 1

echo
echo "=== copied outputs ==="
find "$BASE" -maxdepth 5 -type f \
  \( -name summary_runtime.csv -o -name cuda_persistent_src_collision_thermostat_0215.csv -o -name params_used.kv -o -name run.log \) \
  -printf '%p\n' | sort
