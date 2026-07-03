#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"

# 0438b aggregate runner.  It does not change solver semantics and introduces
# no solver parameter.  It only orchestrates the 0438 periodic wall-free runners.
CASE="${CASE:-shear}"                 # shear | tg
GAMMAS="${GAMMAS:-40}"
STEPS_LIST="${STEPS_LIST:-2000}"
SEEDS="${SEEDS:-1628638 1628639 1628640}"
RUN_MODES="${RUN_MODES:-src src-resampling src-q6 src-q6-resampling}"
BASE_SWEEP_ROOT="${BASE_SWEEP_ROOT:-runs/0438b_${CASE}_periodic_equiv_sweep}"
SUMMARY_EVERY="${SUMMARY_EVERY:-100}"
DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-}"
LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-0}"
FILTERED_RECORDING_ENABLE="${FILTERED_RECORDING_ENABLE:-0}"
FAIL_ON_ANY="${FAIL_ON_ANY:-1}"

case "$CASE" in
  shear) RUNNER="scripts/run_0438_periodic_shear_wave_path_matrix.sh" ;;
  tg)    RUNNER="scripts/run_0438_periodic_taylor_green_path_matrix.sh" ;;
  *) echo "[0438b] ERROR unsupported CASE=$CASE; expected shear or tg" >&2; exit 2 ;;
esac
[[ -x "$RUNNER" ]] || { echo "[0438b] ERROR missing or non-executable runner: $RUNNER" >&2; exit 127; }

mkdir -p "$BASE_SWEEP_ROOT"
MANIFEST="$BASE_SWEEP_ROOT/manifest.csv"
echo "case,gamma,steps,seed,root,exit_code" > "$MANIFEST"
failures=0

for gamma in $GAMMAS; do
  for steps in $STEPS_LIST; do
    for seed in $SEEDS; do
      root="$BASE_SWEEP_ROOT/${CASE}_g${gamma}_s${steps}_seed${seed}"
      echo "[0438b] case=$CASE gamma=$gamma steps=$steps seed=$seed root=$root"
      set +e
      if [[ -n "$DUMP_STATE_EVERY" ]]; then
        BIN="${BIN:-}" BASE_RUN_ROOT="$root" GAMMA="$gamma" STEPS="$steps" SEED="$seed" \
        SUMMARY_EVERY="$SUMMARY_EVERY" DUMP_STATE_EVERY="$DUMP_STATE_EVERY" RUN_MODES="$RUN_MODES" \
        LIVE_VIS_ENABLE="$LIVE_VIS_ENABLE" FILTERED_RECORDING_ENABLE="$FILTERED_RECORDING_ENABLE" \
        FAIL_ON_ANY="$FAIL_ON_ANY" bash "$RUNNER"
      else
        BIN="${BIN:-}" BASE_RUN_ROOT="$root" GAMMA="$gamma" STEPS="$steps" SEED="$seed" \
        SUMMARY_EVERY="$SUMMARY_EVERY" RUN_MODES="$RUN_MODES" \
        LIVE_VIS_ENABLE="$LIVE_VIS_ENABLE" FILTERED_RECORDING_ENABLE="$FILTERED_RECORDING_ENABLE" \
        FAIL_ON_ANY="$FAIL_ON_ANY" bash "$RUNNER"
      fi
      rc=$?
      set -e
      echo "$CASE,$gamma,$steps,$seed,$root,$rc" >> "$MANIFEST"
      if [[ "$rc" != 0 ]]; then failures=$((failures+1)); fi
    done
  done
done

python3 scripts/analyze_0438b_periodic_equiv_sweep.py \
  --manifest "$MANIFEST" \
  --csv "$BASE_SWEEP_ROOT/periodic_equiv_sweep_summary_0438b.csv" \
  --markdown "$BASE_SWEEP_ROOT/periodic_equiv_sweep_report_0438b.md"

echo "[0438b] manifest=$MANIFEST"
echo "[0438b] report=$BASE_SWEEP_ROOT/periodic_equiv_sweep_report_0438b.md"
echo "[0438b] csv=$BASE_SWEEP_ROOT/periodic_equiv_sweep_summary_0438b.csv"
if [[ "$failures" != 0 && "$FAIL_ON_ANY" == 1 ]]; then
  echo "[0438b] FAIL: failures=$failures" >&2
  exit 1
fi
