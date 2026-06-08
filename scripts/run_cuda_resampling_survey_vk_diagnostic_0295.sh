#!/usr/bin/env bash
set -euo pipefail

# 0295 diagnostic bisection for the schedule-sensitive Von Karman circle+IO case.
# This is not a production validator.  It runs the same OFF/ON comparison with
# progressively more intrusive read-only survey modes so we can identify whether
# a divergence is caused by CSV I/O only, CUDA synchronization, allocation,
# persistent-state deposit, or the full support survey.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

ART_ROOT=${ART_ROOT:-dev_history/artifacts/gpu_cuda_resampling_survey_0295_vk_diagnostic}
BIN=${BIN:-build/src_mpcd_base_cuda_0295}
NX=${NX:-64}
NY=${NY:-64}
STEPS=${STEPS:-80}
SURVEY_EVERY=${SURVEY_EVERY:-$STEPS}
MODES=${MODES:-csv_only sync_only alloc_only deposit_only full}
STRICT_SYNC=${STRICT_SYNC:-0}
CUDA_LAUNCH_BLOCKING=${CUDA_LAUNCH_BLOCKING:-0}
STOP_ON_FAIL=${STOP_ON_FAIL:-0}
mkdir -p "$ART_ROOT"

OUT_CSV="$ART_ROOT/vk_survey_mode_bisect_0295.csv"
printf 'mode,strictSync,cudaLaunchBlocking,runnerExit,caseVerdict,failedMetrics,surveyRowsOn,manifest\n' > "$OUT_CSV"

run_one_mode() {
  local mode=$1
  local art="$ART_ROOT/mode_${mode}_strict${STRICT_SYNC}_blocking${CUDA_LAUNCH_BLOCKING}"
  rm -rf "$art"
  mkdir -p "$art"
  echo "[0295-vkdiag] mode=$mode strictSync=$STRICT_SYNC launchBlocking=$CUDA_LAUNCH_BLOCKING art=$art"
  local rc=0
  set +e
  env \
    BIN="$BIN" FORCE_REBUILD=0 RUN_TG=0 RUN_POISEUILLE=0 RUN_STEP=0 RUN_SEGMENTED=0 RUN_VK=1 \
    NX="$NX" NY="$NY" STEPS="$STEPS" SURVEY_EVERY="$SURVEY_EVERY" VK_SURVEY_EVERY="$SURVEY_EVERY" \
    STOP_ON_FAIL=0 ART_DIR="$art" \
    CUDA_DIAG_STRICT_SYNC_0295="$STRICT_SYNC" CUDA_LAUNCH_BLOCKING="$CUDA_LAUNCH_BLOCKING" \
    MPCD_CUDA_RESAMPLING_SUPPORT_SURVEY_0295_MODE="$mode" \
    bash scripts/run_cuda_resampling_survey_0295.sh >"$art/runner.stdout.log" 2>"$art/runner.stderr.log"
  rc=$?
  set -e
  local manifest="$art/cuda_resampling_survey_0295_manifest.csv"
  python3 - "$OUT_CSV" "$mode" "$STRICT_SYNC" "$CUDA_LAUNCH_BLOCKING" "$rc" "$manifest" <<'PY'
import csv, os, sys
out, mode, strict, blocking, rc, manifest = sys.argv[1:]
verdict='NO_MANIFEST'; failed=''; rows_on=''
if os.path.exists(manifest):
    with open(manifest, newline='') as fh:
        rows=list(csv.DictReader(fh))
    if rows:
        r=rows[-1]
        verdict=r.get('verdict','')
        failed=r.get('failedMetrics','')
        rows_on=r.get('surveyOnRows','')
with open(out, 'a', newline='') as fh:
    csv.writer(fh).writerow([mode, strict, blocking, rc, verdict, failed, rows_on, manifest])
print(f'[0295-vkdiag] mode={mode} rc={rc} verdict={verdict} failed={failed} surveyRowsOn={rows_on}')
PY
}

for mode in $MODES; do
  run_one_mode "$mode"
done

echo "[0295-vkdiag] wrote $OUT_CSV"
