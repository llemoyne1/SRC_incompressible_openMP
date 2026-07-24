#!/usr/bin/env bash
set -uo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"

BIN="${BIN:-build/src_mpcd_base_cuda_q6_resident_0400}"
MATRIX_ROOT="${MATRIX_ROOT:-runs/0491d_species_q6_path_matrix}"
STEPS="${STEPS:-1}"
SUMMARY_EVERY="${SUMMARY_EVERY:-1}"
NX="${NX:-8}"
NY="${NY:-4}"
GAMMA="${GAMMA:-4}"
SEED="${SEED:-1628431}"
SPECIES_Q6_COMPARISON_TOLERANCE="${SPECIES_Q6_COMPARISON_TOLERANCE:-1.0e-11}"
read -r -a MODES <<< "${MODES_LIST:-src src-resampling src-q6 src-q6-resampling}"

mkdir -p "$MATRIX_ROOT/launcher_logs"
STATUS="$MATRIX_ROOT/launch_status.csv"
printf 'mode,exit_code,log\n' > "$STATUS"

failures=0
for mode in "${MODES[@]}"; do
  log="$MATRIX_ROOT/launcher_logs/${mode}.log"
  livevis_control="$MATRIX_ROOT/livevis_control.kv"
  echo "[0491d] mode=$mode grid=${NX}x${NY} gamma=$GAMMA steps=$STEPS"
  rc=0
  env \
    BIN="$BIN" AUTO_BUILD=0 BUILD_IF_STALE=0 FORCE_BUILD=0 \
    BASE_RUN_ROOT="$MATRIX_ROOT" RUN_MODES="$mode" \
    NX="$NX" NY="$NY" GAMMA="$GAMMA" SEED="$SEED" STEPS="$STEPS" \
    SUMMARY_EVERY="$SUMMARY_EVERY" DUMP_STATE_EVERY=0 \
    CLEAN_RUN_ROOT=1 LIVE_VIS_ENABLE=0 LIVE_VIS_HOLD_ON_EXIT=0 \
    FILTERED_RECORDING_ENABLE=0 LIVE_VIS_CONTROL_FILE="$livevis_control" \
    OVERWRITE_LIVEVIS_CONTROL=1 Q6_STRICT=1 \
    SPECIES_Q6_ENABLE=true SPECIES_Q6_MODE=weighted \
    SPECIES_Q6_SENSITIVITY=1.0 SPECIES_Q6_FALLBACK_MODE=common \
    SPECIES_Q6_COMPARISON_TOLERANCE="$SPECIES_Q6_COMPARISON_TOLERANCE" \
    LIQUID_TO_GAS_MASS_RATIO=10.0 \
    bash scripts/run_ok_injection_type1_into_type2_empty.sh >"$log" 2>&1 || rc=$?
  printf '%s,%s,%s\n' "$mode" "$rc" "$log" >> "$STATUS"
  if [[ "$rc" != 0 ]]; then
    failures=$((failures + 1))
    echo "[0491d] FAIL mode=$mode rc=$rc"
    tail -40 "$log"
  fi
done

python3 scripts/summarize_0491d_species_q6_path_matrix.py \
  --root "$MATRIX_ROOT" \
  --status "$STATUS" \
  --expected-steps "$STEPS" \
  --csv "$MATRIX_ROOT/species_q6_path_matrix_0491d.csv" \
  --markdown "$MATRIX_ROOT/species_q6_path_matrix_0491d.md"
summary_rc=$?
if [[ "$summary_rc" != 0 ]]; then
  failures=$((failures + summary_rc))
fi

echo "[0491d] launch_failures=$failures"
echo "[0491d] audit=$MATRIX_ROOT/species_q6_path_matrix_0491d.csv"
echo "[0491d] report=$MATRIX_ROOT/species_q6_path_matrix_0491d.md"
exit "$failures"
