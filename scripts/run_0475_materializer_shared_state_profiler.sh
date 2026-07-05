#!/usr/bin/env bash
set -euo pipefail

ROOT=${BASE_0475_ROOT:-runs/0475_materializer_shared_state_profiler}
BIN=${BIN:-build/src_mpcd_base_cuda_q6_resident_periodic_equiv_0475}
SCALE_CASES=${SCALE_CASES:-"128x128x40"}
SEEDS=${SEEDS:-"1628638"}
STEPS=${STEPS:-200}
SUMMARY_EVERY=${SUMMARY_EVERY:-50}
DEVICE_GATE_EVERY=${DEVICE_GATE_EVERY:-50}
UPSTREAM_GATE_EVERY=${UPSTREAM_GATE_EVERY:-$DEVICE_GATE_EVERY}
MATERIALIZER_EVERY=${MATERIALIZER_EVERY:-$DEVICE_GATE_EVERY}
RUN_MODES=${RUN_MODES:-"src-resampling src-q6-resampling"}

if [[ ! -x "$BIN" ]]; then
  echo "[0475] missing executable: $BIN" >&2
  exit 2
fi

SCALING_RUNNER=""
if [[ -x scripts/run_0464_scaling_cuda_vs_cpu.sh ]]; then
  SCALING_RUNNER=scripts/run_0464_scaling_cuda_vs_cpu.sh
elif [[ -x scripts/run_0463_scaling_cuda_vs_cpu.sh ]]; then
  SCALING_RUNNER=scripts/run_0463_scaling_cuda_vs_cpu.sh
else
  echo "[0475] missing scaling runner 0464/0463" >&2
  exit 2
fi

rm -rf "$ROOT"
mkdir -p "$ROOT"

echo "[0475] scaling runner: $SCALING_RUNNER"
echo "[0475] root: $ROOT"
echo "[0475] cases: $SCALE_CASES"
echo "[0475] upstream gate every: $UPSTREAM_GATE_EVERY"
echo "[0475] materializer every: $MATERIALIZER_EVERY"

MPCD_INTERNAL_PROFILES=1 \
MPCD_CUDA_RESAMPLING_DIRECT_STATE_COMMIT_0471=1 \
MPCD_CUDA_RESAMPLING_SHARED_STATE_DIRECT_COMMIT_0472=1 \
MPCD_CUDA_RESAMPLING_HOST_PATCHBACK_0473=1 \
MPCD_CUDA_RESAMPLING_UPSTREAM_SHARED_STATE_0474=1 \
MPCD_CUDA_RESAMPLING_MATERIALIZER_SHARED_STATE_0475=1 \
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

python3 - "$ROOT" <<'PY'
import csv
import sys
from pathlib import Path
from collections import defaultdict

root = Path(sys.argv[1])

def read_rows(path):
    if not path or not path.exists(): return []
    with path.open(newline='') as f:
        return list(csv.DictReader(f))

def f(row, key, default=0.0):
    try:
        v = row.get(key, '')
        return float(v) if v not in ('', None) else default
    except Exception:
        return default

def i(row, key, default=0):
    return int(round(f(row, key, default)))

def infer_key(path):
    parts = path.relative_to(root).parts
    case = parts[0] if parts else ''
    seed = ''
    mode = ''
    for p in parts:
        if p.startswith('seed_'):
            seed = p.replace('seed_', '')
    for idx, p in enumerate(parts):
        if p == 'sparse_gate' and idx + 1 < len(parts):
            mode = parts[idx + 1]
            break
    if not mode:
        for p in parts:
            if p in ('src-resampling', 'src-q6-resampling'):
                mode = p
                break
    return case, mode, seed

scale_file = None
for name in ('scaling_cuda_vs_cpu_summary_0464.csv', 'scaling_cuda_vs_cpu_summary_0463.csv'):
    hits = sorted(root.rglob(name))
    if hits:
        scale_file = hits[0]
        break
scale_rows = read_rows(scale_file)
scale_by_key = {}
for r in scale_rows:
    key = (r.get('case',''), r.get('mode',''), str(r.get('seed','')))
    scale_by_key[key] = r

mat = defaultdict(list)
for p in root.rglob('cuda_resampling_operation_materialize_0453.csv'):
    mat[infer_key(p)].extend(read_rows(p))

carrier = defaultdict(list)
for p in root.rglob('cuda_resampling_device_carrier_0455.csv'):
    carrier[infer_key(p)].extend(read_rows(p))

upstream = defaultdict(list)
for p in root.rglob('cuda_resampling_upstream_shadow_0450.csv'):
    upstream[infer_key(p)].extend(read_rows(p))

profiles = defaultdict(list)
for p in root.rglob('phase_profile_0163.csv'):
    profiles[infer_key(p)].extend(read_rows(p))

keys = sorted(set(scale_by_key) | set(mat) | set(carrier) | set(upstream))
summary_path = root / 'materializer_shared_state_profiler_summary_0475.csv'
report_path = root / 'materializer_shared_state_profiler_report_0475.md'

header = [
    'case','mode','seed','pass','cpu_wall_s','cuda_wall_s','speedup','max_summary_delta',
    'mat_rows','mat_pass','mat_apply','mat_shared','mat_upload_skipped','mat_compact_dl',
    'mat_max_state_upload_s','mat_max_plan_upload_s','mat_max_upload_s','mat_max_download_s','mat_max_total_s',
    'up_rows','up_pass','up_shared','up_skip','up_max_upload_s',
    'carrier_rows','carrier_skip','carrier_patch','carrier_max_up_s','carrier_max_dl_s','carrier_max_total_s',
    'profile_total_ms','profile_top1','profile_top1_ms','profile_top2','profile_top2_ms','profile_top3','profile_top3_ms'
]

rows_out = []
for key in keys:
    case, mode, seed = key
    sr = scale_by_key.get(key, {})
    mr = mat.get(key, [])
    cr = carrier.get(key, [])
    ur = upstream.get(key, [])
    pr = profiles.get(key, [])
    handled_m = [r for r in mr if i(r,'handled') == 1]
    handled_c = [r for r in cr if i(r,'handled') == 1]
    handled_u = [r for r in ur if i(r,'handled') == 1]
    prof = [(r.get('phase',''), f(r,'ms_per_step')) for r in pr if r.get('phase','') != 'total_profiled']
    prof_sorted = sorted(prof, key=lambda x: x[1], reverse=True)
    total_ms = 0.0
    for r in pr:
        if r.get('phase','') == 'total_profiled': total_ms = max(total_ms, f(r,'ms_per_step'))
    top = prof_sorted[:3] + [('',0.0)]*3
    row = {
        'case': case, 'mode': mode, 'seed': seed,
        'pass': sr.get('pass', sr.get('pass_like','')),
        'cpu_wall_s': sr.get('cpu_wall_s',''),
        'cuda_wall_s': sr.get('cuda_wall_s',''),
        'speedup': sr.get('speedup', sr.get('cpu_cuda_speedup','')),
        'max_summary_delta': sr.get('max_summary_delta',''),
        'mat_rows': len(mr),
        'mat_pass': sum(i(r,'pass') for r in handled_m),
        'mat_apply': sum(i(r,'applied') for r in handled_m),
        'mat_shared': sum(i(r,'materializerSharedState0475') for r in handled_m),
        'mat_upload_skipped': sum(i(r,'materializerUploadSkipped0475') for r in handled_m),
        'mat_compact_dl': sum(i(r,'materializerCompactDownload0475') for r in handled_m),
        'mat_max_state_upload_s': max([f(r,'stateUploadSeconds0475') for r in handled_m] or [0.0]),
        'mat_max_plan_upload_s': max([f(r,'planUploadSeconds0475') for r in handled_m] or [0.0]),
        'mat_max_upload_s': max([f(r,'uploadSeconds') for r in handled_m] or [0.0]),
        'mat_max_download_s': max([f(r,'downloadSeconds') for r in handled_m] or [0.0]),
        'mat_max_total_s': max([f(r,'totalSeconds') for r in handled_m] or [0.0]),
        'up_rows': len(ur),
        'up_pass': sum(i(r,'pass') for r in handled_u),
        'up_shared': sum(i(r,'upstreamSharedState0474') for r in handled_u),
        'up_skip': sum(i(r,'upstreamUploadSkipped0474') for r in handled_u),
        'up_max_upload_s': max([f(r,'uploadSeconds') for r in handled_u] or [0.0]),
        'carrier_rows': len(cr),
        'carrier_skip': sum(i(r,'residentSharedUploadSkipped0472') for r in handled_c),
        'carrier_patch': sum(i(r,'residentHostPatchback0473') for r in handled_c),
        'carrier_max_up_s': max([f(r,'uploadSeconds') for r in handled_c] or [0.0]),
        'carrier_max_dl_s': max([f(r,'stateDownloadSeconds') for r in handled_c] or [0.0]),
        'carrier_max_total_s': max([f(r,'totalSeconds') for r in handled_c] or [0.0]),
        'profile_total_ms': total_ms,
        'profile_top1': top[0][0], 'profile_top1_ms': top[0][1],
        'profile_top2': top[1][0], 'profile_top2_ms': top[1][1],
        'profile_top3': top[2][0], 'profile_top3_ms': top[2][1],
    }
    rows_out.append(row)

with summary_path.open('w', newline='') as fcsv:
    w = csv.DictWriter(fcsv, fieldnames=header)
    w.writeheader(); w.writerows(rows_out)

pass_rows = sum(1 for r in rows_out if str(r.get('pass','')) in ('1','1.0','true','True'))
with report_path.open('w') as out:
    out.write('# 0475 materializer shared-state / phase profiler probe\n\n')
    out.write('Scope: keep 0473 fast commit and 0474 shared upstream gate, then make the 0453 operation materializer consume the shared CUDA particle state. The materializer should skip its own full particle upload and download only the compact nOps payload. `MPCD_INTERNAL_PROFILES=1` is also enabled for phase attribution.\n\n')
    out.write(f'PASS-like rows: **{pass_rows}/{len(rows_out)}**\n\n')
    cols = ['case','mode','seed','pass','cpu_wall_s','cuda_wall_s','speedup','max_summary_delta','mat_rows','mat_pass','mat_apply','mat_shared','mat_upload_skipped','mat_compact_dl','mat_max_state_upload_s','mat_max_plan_upload_s','mat_max_download_s','mat_max_total_s','up_rows','up_pass','up_shared','up_skip','carrier_rows','carrier_skip','carrier_patch','profile_top1','profile_top1_ms','profile_top2','profile_top2_ms','profile_top3','profile_top3_ms']
    out.write('| ' + ' | '.join(cols) + ' |\n')
    out.write('| ' + ' | '.join(['---']*len(cols)) + ' |\n')
    def fmt(v):
        if isinstance(v, float): return f'{v:.3e}'
        return str(v)
    for r in rows_out:
        out.write('| ' + ' | '.join(fmt(r.get(c,'')) for c in cols) + ' |\n')
    out.write(f'\nFlat CSV: `{summary_path}`\n')
    if scale_file:
        out.write(f'\nScaling CSV: `{scale_file}`\n')

print(report_path)
PY

cat "$ROOT/materializer_shared_state_profiler_report_0475.md"
