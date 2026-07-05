#!/usr/bin/env bash
set -euo pipefail

ROOT=${BASE_0475B_ROOT:-runs/0475b_materializer_cell_list_probe}
BIN=${BIN:-build/src_mpcd_base_cuda_q6_resident_periodic_equiv_0475b}
SCALE_CASES=${SCALE_CASES:-128x128x40}
SEEDS=${SEEDS:-1628638}
STEPS=${STEPS:-200}
SUMMARY_EVERY=${SUMMARY_EVERY:-50}
DEVICE_GATE_EVERY=${DEVICE_GATE_EVERY:-50}
UPSTREAM_GATE_EVERY=${UPSTREAM_GATE_EVERY:-50}
# Keep the legacy cadence effectively disabled; 0475b triggers the materializer
# opportunistically when a real transfer plan exists.
MATERIALIZER_EVERY=${MATERIALIZER_EVERY:-1000000000}
RUN_MODES=${RUN_MODES:-"src-resampling src-q6-resampling"}

if [[ ! -x "$BIN" ]]; then
  echo "[0475b] missing executable: $BIN" >&2
  exit 2
fi

SCALING_RUNNER=""
if [[ -x scripts/run_0464_scaling_cuda_vs_cpu.sh ]]; then
  SCALING_RUNNER=scripts/run_0464_scaling_cuda_vs_cpu.sh
elif [[ -x scripts/run_0463_scaling_cuda_vs_cpu.sh ]]; then
  SCALING_RUNNER=scripts/run_0463_scaling_cuda_vs_cpu.sh
else
  echo "[0475b] missing scaling runner 0464/0463" >&2
  exit 2
fi

rm -rf "$ROOT"
mkdir -p "$ROOT"

echo "[0475b] scaling runner: $SCALING_RUNNER"
echo "[0475b] root: $ROOT"
echo "[0475b] cases: $SCALE_CASES"
echo "[0475b] materializer every: $MATERIALIZER_EVERY"
echo "[0475b] on-plan trigger: enabled"
echo "[0475b] cell-list materializer: enabled"

MPCD_INTERNAL_PROFILES=1 \
MPCD_CUDA_RESAMPLING_DIRECT_STATE_COMMIT_0471=1 \
MPCD_CUDA_RESAMPLING_SHARED_STATE_DIRECT_COMMIT_0472=1 \
MPCD_CUDA_RESAMPLING_HOST_PATCHBACK_0473=1 \
MPCD_CUDA_RESAMPLING_UPSTREAM_SHARED_STATE_0474=1 \
MPCD_CUDA_RESAMPLING_MATERIALIZER_SHARED_STATE_0475=1 \
MPCD_CUDA_RESAMPLING_MATERIALIZER_ON_PLAN_0475A=1 \
MPCD_CUDA_RESAMPLING_MATERIALIZER_CELL_LIST_0475B=1 \
MPCD_CUDA_RESAMPLING_THRUST_CELL_LIST_MATERIALIZER_0460=1 \
MPCD_CUDA_RESAMPLING_UPSTREAM_SHADOW_0450=1 \
MPCD_CUDA_RESAMPLING_UPSTREAM_APPLY_0451=1 \
MPCD_CUDA_RESAMPLING_OPERATION_MATERIALIZE_0453=1 \
MPCD_CUDA_RESAMPLING_UPSTREAM_SHADOW_EVERY_0450="$UPSTREAM_GATE_EVERY" \
MPCD_CUDA_RESAMPLING_UPSTREAM_APPLY_EVERY_0451="$UPSTREAM_GATE_EVERY" \
MPCD_CUDA_RESAMPLING_OPERATION_MATERIALIZE_EVERY_0453="$MATERIALIZER_EVERY" \
BIN="$BIN" \
BASE_SCALE_ROOT="$ROOT" \
SCALE_CASES="$SCALE_CASES" \
SEEDS="$SEEDS" \
STEPS="$STEPS" \
SUMMARY_EVERY="$SUMMARY_EVERY" \
DEVICE_GATE_EVERY="$DEVICE_GATE_EVERY" \
RUN_MODES="$RUN_MODES" \
LIVE_PROGRESS="${LIVE_PROGRESS:-1}" \
LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-0}" \
FILTERED_RECORDING_ENABLE="${FILTERED_RECORDING_ENABLE:-0}" \
bash "$SCALING_RUNNER"

python3 - <<'PY' "$ROOT"
import csv
import sys
from pathlib import Path
root = Path(sys.argv[1])

def read_rows(name):
    rows=[]
    for p in root.rglob(name):
        with p.open(newline='') as f:
            for r in csv.DictReader(f):
                r['_path']=str(p.relative_to(root))
                rows.append(r)
    return rows

def i(r,k):
    try: return int(float(r.get(k,'0') or 0))
    except Exception: return 0

def f(r,k):
    try: return float(r.get(k,'0') or 0.0)
    except Exception: return 0.0

scale = read_rows('scaling_cuda_vs_cpu_summary_0463.csv') + read_rows('scaling_cuda_vs_cpu_summary_0464.csv')
mat = read_rows('cuda_resampling_operation_materialize_0453.csv')
carrier = read_rows('cuda_resampling_device_carrier_0455.csv')
up = read_rows('cuda_resampling_upstream_apply_0451.csv') + read_rows('cuda_resampling_upstream_shadow_0450.csv')

keys=[]
for r in scale:
    key=(r.get('case',''), r.get('mode',''), r.get('seed',''))
    if key not in keys: keys.append(key)

def filt(rows, case, mode):
    return [r for r in rows if case in r.get('_path','') and (('/'+mode+'/') in ('/'+r.get('_path','')) or r.get('mode','')==mode)]

out_rows=[]
for case, mode, seed in keys:
    mr=[r for r in filt(mat, case, mode) if i(r,'handled')]
    cr=[r for r in filt(carrier, case, mode) if i(r,'handled')]
    ur=[r for r in filt(up, case, mode) if i(r,'handled')]
    sr=[r for r in scale if r.get('case','')==case and r.get('mode','')==mode and r.get('seed','')==seed]
    s=sr[0] if sr else {}
    out_rows.append({
        'case':case,'mode':mode,'seed':seed,
        'pass':s.get('pass',''), 'cpu_wall_s':s.get('cpu_wall_s',''), 'cuda_wall_s':s.get('cuda_wall_s',''),
        'speedup':s.get('speedup',s.get('CPU/CUDA speedup','')), 'max_summary_delta':s.get('max_summary_delta',''),
        'mat_rows':len(mr), 'mat_pass':sum(i(r,'pass') for r in mr), 'mat_apply':sum(i(r,'applied') for r in mr),
        'mat_shared':sum(i(r,'materializerSharedState0475') for r in mr),
        'mat_upload_skipped':sum(i(r,'materializerUploadSkipped0475') for r in mr),
        'mat_compact_dl':sum(i(r,'materializerCompactDownload0475') for r in mr),
        'mat_max_state_upload_s':max([f(r,'stateUploadSeconds0475') for r in mr] or [0.0]),
        'mat_max_plan_upload_s':max([f(r,'planUploadSeconds0475') for r in mr] or [0.0]),
        'mat_max_download_s':max([f(r,'downloadSeconds') for r in mr] or [0.0]),
        'mat_max_total_s':max([f(r,'totalSeconds') for r in mr] or [0.0]),
        'up_rows':len(ur), 'up_pass':sum(i(r,'pass') for r in ur),
        'up_shared':sum(i(r,'upstreamSharedState0474') for r in ur), 'up_skip':sum(i(r,'upstreamUploadSkipped0474') for r in ur),
        'carrier_rows':len(cr), 'carrier_skip':sum(i(r,'residentSharedUploadSkipped0472') for r in cr),
        'carrier_patch':sum(i(r,'residentHostPatchback0473') for r in cr),
    })

summary = root / 'materializer_cell_list_summary_0475b.csv'
report = root / 'materializer_cell_list_report_0475b.md'
fields=list(out_rows[0].keys()) if out_rows else ['case','mode']
with summary.open('w', newline='') as fcsv:
    w=csv.DictWriter(fcsv, fieldnames=fields)
    w.writeheader(); w.writerows(out_rows)

with report.open('w') as out:
    out.write('# 0475b materializer shared-state cell-list probe\n\n')
    out.write('Scope: keep the 0475a on-plan trigger, but replace the slow serial 0453 shared-state materializer with the 0460-style stable cell-list donor-slice materializer. This keeps shared-state upload skipping and compact nOps download, while avoiding the O(planEntries*nActive) serial kernel.\n\n')
    out.write(f'PASS-like rows: **{sum(1 for r in out_rows if str(r.get("pass")) in ("1","1.0","True","true"))}/{len(out_rows)}**\n\n')
    if out_rows:
        out.write('| ' + ' | '.join(fields) + ' |\n')
        out.write('| ' + ' | '.join(['---']*len(fields)) + ' |\n')
        for r in out_rows:
            out.write('| ' + ' | '.join(str(r.get(k,'')) for k in fields) + ' |\n')
    out.write(f'\nFlat CSV: `{summary}`\n')
print(report.read_text())
PY
