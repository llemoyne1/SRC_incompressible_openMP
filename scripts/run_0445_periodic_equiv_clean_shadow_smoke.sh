#!/usr/bin/env bash
set -euo pipefail

# 0445 smoke: reuse the validated 0438H clean periodic profile and enable the
# in-solver CUDA remap+thermal shadow hook.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

: "${BIN:=build/src_mpcd_base_cuda_q6_resident_periodic_equiv_0445}"
: "${BASE_SWEEP_ROOT:=runs/0445_periodic_equiv_clean_shadow_smoke}"
: "${CASE:=shear}"
: "${GAMMAS:=40}"
: "${STEPS_LIST:=100}"
: "${SEEDS:=1628638}"
: "${RUN_MODES:=src-resampling src-q6-resampling}"
: "${SUMMARY_EVERY:=50}"
: "${LIVE_VIS_ENABLE:=0}"
: "${FILTERED_RECORDING_ENABLE:=0}"

MPCD_CUDA_RESAMPLING_PIPELINE_SHADOW_0445=1 \
MPCD_CUDA_RESAMPLING_PIPELINE_SHADOW_EVERY_0445=1 \
BIN="$BIN" \
CASE="$CASE" \
BASE_SWEEP_ROOT="$BASE_SWEEP_ROOT" \
GAMMAS="$GAMMAS" \
STEPS_LIST="$STEPS_LIST" \
SEEDS="$SEEDS" \
RUN_MODES="$RUN_MODES" \
SUMMARY_EVERY="$SUMMARY_EVERY" \
LIVE_VIS_ENABLE="$LIVE_VIS_ENABLE" \
FILTERED_RECORDING_ENABLE="$FILTERED_RECORDING_ENABLE" \
bash scripts/run_0438h_periodic_equiv_clean_sweep.sh

python3 - <<'PY'
import csv, pathlib, sys
root = pathlib.Path(__import__('os').environ.get('BASE_SWEEP_ROOT', 'runs/0445_periodic_equiv_clean_shadow_smoke'))
rows = []
for path in sorted(root.glob('**/cuda_resampling_pipeline_shadow_0445.csv')):
    with path.open(newline='') as f:
        for row in csv.DictReader(f):
            row['csv'] = str(path)
            rows.append(row)
print(f"0445 shadow rows: {len(rows)}")
if not rows:
    sys.exit(2)
handled = [r for r in rows if r.get('handled') == '1']
failed = [r for r in rows if r.get('handled') == '1' and r.get('pass') != '1']
skipped = [r for r in rows if r.get('skipped') == '1']
print(f"handled={len(handled)} failed={len(failed)} skipped={len(skipped)}")
for r in failed[:10]:
    print('FAIL', r.get('csv'), 'step', r.get('step'), 'reason', r.get('skipReason'), 'maxV', r.get('maxAbsVx'), r.get('maxAbsVy'))
if failed:
    sys.exit(1)
PY
