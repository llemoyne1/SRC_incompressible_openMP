#!/usr/bin/env bash
set -euo pipefail

ROOT=${BASE_0474_ROOT:-runs/0474_cuda_plan_timing_shared_gate}
BIN=${BIN:-build/src_mpcd_base_cuda_q6_resident_periodic_equiv_0474}
SCALE_CASES=${SCALE_CASES:-"64x64x40 96x96x40 128x128x40"}
SEEDS=${SEEDS:-"1628638"}
STEPS=${STEPS:-200}
SUMMARY_EVERY=${SUMMARY_EVERY:-50}
DEVICE_GATE_EVERY=${DEVICE_GATE_EVERY:-50}
UPSTREAM_GATE_EVERY=${UPSTREAM_GATE_EVERY:-$DEVICE_GATE_EVERY}
RUN_MODES=${RUN_MODES:-"src-resampling src-q6-resampling"}

if [[ ! -x "$BIN" ]]; then
  echo "[0474] missing executable: $BIN" >&2
  exit 2
fi

SCALING_RUNNER=""
if [[ -x scripts/run_0464_scaling_cuda_vs_cpu.sh ]]; then
  SCALING_RUNNER=scripts/run_0464_scaling_cuda_vs_cpu.sh
elif [[ -x scripts/run_0463_scaling_cuda_vs_cpu.sh ]]; then
  SCALING_RUNNER=scripts/run_0463_scaling_cuda_vs_cpu.sh
else
  echo "[0474] missing scaling runner 0464/0463" >&2
  exit 2
fi

rm -rf "$ROOT"
mkdir -p "$ROOT"

echo "[0474] scaling runner: $SCALING_RUNNER"
echo "[0474] root: $ROOT"
echo "[0474] upstream gate every: $UPSTREAM_GATE_EVERY"

MPCD_INTERNAL_PROFILES=1 \
MPCD_CUDA_RESAMPLING_DIRECT_STATE_COMMIT_0471=1 \
MPCD_CUDA_RESAMPLING_SHARED_STATE_DIRECT_COMMIT_0472=1 \
MPCD_CUDA_RESAMPLING_HOST_PATCHBACK_0473=1 \
MPCD_CUDA_RESAMPLING_UPSTREAM_SHARED_STATE_0474=1 \
MPCD_CUDA_RESAMPLING_UPSTREAM_SHADOW_0450=1 \
MPCD_CUDA_RESAMPLING_UPSTREAM_APPLY_0451=1 \
MPCD_CUDA_RESAMPLING_OPERATION_MATERIALIZE_0453=1 \
MPCD_CUDA_RESAMPLING_UPSTREAM_SHADOW_EVERY_0450="$UPSTREAM_GATE_EVERY" \
MPCD_CUDA_RESAMPLING_UPSTREAM_APPLY_EVERY_0451="$UPSTREAM_GATE_EVERY" \
MPCD_CUDA_RESAMPLING_OPERATION_MATERIALIZE_EVERY_0453="$UPSTREAM_GATE_EVERY" \
MPCD_CUDA_RESAMPLING_DIRECT_STATE_COMMIT_0471=1 \
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
import math
import sys
from pathlib import Path

root = Path(sys.argv[1])

def read_rows(path):
    if not path.exists():
        return []
    with path.open(newline='') as f:
        return list(csv.DictReader(f))

def f(row, key, default=0.0):
    try:
        v = row.get(key, '')
        return float(v) if v not in ('', None) else default
    except Exception:
        return default

def i(row, key, default=0):
    try:
        v = row.get(key, '')
        return int(float(v)) if v not in ('', None) else default
    except Exception:
        return default

def rel_case_mode(p):
    parts = p.relative_to(root).parts
    case = parts[0] if len(parts) > 0 else ''
    mode = ''
    for m in ('src-resampling', 'src-q6-resampling'):
        if m in parts:
            mode = m
            break
    seed = ''
    for part in parts:
        if part.startswith('seed_'):
            seed = part.replace('seed_', '')
    return case, mode, seed

summary = None
for name in ('scaling_cuda_vs_cpu_summary_0464.csv', 'scaling_cuda_vs_cpu_summary_0463.csv'):
    p = root / name
    if p.exists():
        summary = p
        break
summary_rows = read_rows(summary) if summary else []

upstream = {}
for p in root.rglob('cuda_resampling_upstream_shadow_0450.csv'):
    case, mode, seed = rel_case_mode(p)
    rows = read_rows(p)
    handled = [r for r in rows if i(r, 'handled') == 1]
    passed = [r for r in handled if i(r, 'pass') == 1]
    upstream[(case, mode, seed)] = {
        'rows': len(rows),
        'handled': len(handled),
        'pass': len(passed),
        'shared': sum(i(r, 'upstreamSharedState0474') for r in handled),
        'skipped': sum(i(r, 'upstreamUploadSkipped0474') for r in handled),
        'max_upload': max([f(r, 'uploadSeconds') for r in handled] or [0.0]),
        'max_deposit_dl': max([f(r, 'depositDownloadSeconds') for r in handled] or [0.0]),
        'max_total': max([f(r, 'totalSeconds') for r in handled] or [0.0]),
    }

mat = {}
for p in root.rglob('cuda_resampling_operation_materialize_0453.csv'):
    case, mode, seed = rel_case_mode(p)
    rows = read_rows(p)
    handled = [r for r in rows if i(r, 'handled') == 1]
    passed = [r for r in handled if i(r, 'pass') == 1]
    applied = [r for r in handled if i(r, 'applied') == 1]
    mat[(case, mode, seed)] = {
        'rows': len(rows),
        'handled': len(handled),
        'pass': len(passed),
        'applied': len(applied),
        'max_upload': max([f(r, 'uploadSeconds') for r in handled] or [0.0]),
        'max_kernel': max([f(r, 'kernelSeconds') for r in handled] or [0.0]),
        'max_download': max([f(r, 'downloadSeconds') for r in handled] or [0.0]),
        'max_total': max([f(r, 'totalSeconds') for r in handled] or [0.0]),
    }

carrier = {}
for p in root.rglob('cuda_resampling_device_carrier_0455.csv'):
    case, mode, seed = rel_case_mode(p)
    rows = read_rows(p)
    handled = [r for r in rows if i(r, 'handled') == 1]
    carrier[(case, mode, seed)] = {
        'rows': len(rows),
        'shared': sum(i(r, 'residentSharedState0472') for r in handled),
        'upload_skipped': sum(i(r, 'residentSharedUploadSkipped0472') for r in handled),
        'patchback': sum(i(r, 'residentHostPatchback0473') for r in handled),
        'full_gate': sum(i(r, 'fullGate0461') for r in handled),
        'max_upload': max([f(r, 'uploadSeconds') for r in handled] or [0.0]),
        'max_state_dl': max([f(r, 'stateDownloadSeconds') for r in handled] or [0.0]),
        'max_total': max([f(r, 'totalSeconds') for r in handled] or [0.0]),
    }

deposit = {}
interesting = {'particle_loop_cell_accum', 'reduce_cells_finalize', 'active_wet_classification', 'poor_rich_classification', 'candidate_lists', 'mutation_plan_cell_index', 'transfer_plan_build', 'donor_particle_selection', 'passive_extraction_plan', 'total_deposit'}
for p in root.rglob('deposit_profile_0172.csv'):
    case, mode, seed = rel_case_mode(p)
    rows = [r for r in read_rows(p) if r.get('context') == 'post_guard' and r.get('phase') in interesting]
    d = {r['phase']: f(r, 'ms_per_call') for r in rows}
    if d:
        deposit[(case, mode, seed)] = d

# Summary table rows keyed by summary CSV.
out_rows = []
for r in summary_rows:
    key = (r.get('case',''), r.get('mode',''), r.get('seed',''))
    u = upstream.get(key, {})
    m = mat.get(key, {})
    c = carrier.get(key, {})
    d = deposit.get(key, {})
    out_rows.append({
        'case': key[0], 'mode': key[1], 'seed': key[2],
        'pass': r.get('pass',''),
        'cpu_wall_s': r.get('cpu_wall_s',''),
        'cuda_wall_s': r.get('cuda_wall_s',''),
        'speedup': r.get('speedup','') or r.get('CPU/CUDA speedup',''),
        'max_summary_delta': r.get('max_summary_delta',''),
        'up_rows': u.get('rows',0), 'up_pass': u.get('pass',0),
        'up_shared': u.get('shared',0), 'up_skip': u.get('skipped',0),
        'up_max_upload': u.get('max_upload',0.0), 'up_max_total': u.get('max_total',0.0),
        'mat_rows': m.get('rows',0), 'mat_pass': m.get('pass',0), 'mat_applied': m.get('applied',0),
        'carrier_rows': c.get('rows',0), 'carrier_skip': c.get('upload_skipped',0), 'carrier_patch': c.get('patchback',0),
        'carrier_max_upload': c.get('max_upload',0.0), 'carrier_max_state_dl': c.get('max_state_dl',0.0), 'carrier_max_total': c.get('max_total',0.0),
        'post_guard_total_ms': d.get('total_deposit',0.0),
        'plan_ms': d.get('transfer_plan_build',0.0),
        'select_ms': d.get('donor_particle_selection',0.0),
        'extract_plan_ms': d.get('passive_extraction_plan',0.0),
    })

csv_path = root / 'cuda_plan_timing_shared_gate_summary_0474.csv'
fields = ['case','mode','seed','pass','cpu_wall_s','cuda_wall_s','speedup','max_summary_delta',
          'up_rows','up_pass','up_shared','up_skip','up_max_upload','up_max_total',
          'mat_rows','mat_pass','mat_applied',
          'carrier_rows','carrier_skip','carrier_patch','carrier_max_upload','carrier_max_state_dl','carrier_max_total',
          'post_guard_total_ms','plan_ms','select_ms','extract_plan_ms']
with csv_path.open('w', newline='') as fcsv:
    w = csv.DictWriter(fcsv, fieldnames=fields)
    w.writeheader()
    for r in out_rows:
        w.writerow(r)

pass_like = sum(1 for r in out_rows if str(r.get('pass')) in ('1','true','True'))
report = root / 'cuda_plan_timing_shared_gate_report_0474.md'
with report.open('w') as out:
    out.write('# 0474 CUDA plan timing/shared-state upstream gate probe\n\n')
    out.write('Scope: keep the 0473 fast commit path, reuse the process-local shared CUDA particle state inside the 0450/0451 upstream CUDA gate, enable the 0453 operation materializer gate, and collect CPU deposit/plan timing split with `MPCD_INTERNAL_PROFILES=1`.\n\n')
    out.write(f'PASS-like rows: **{pass_like}/{len(out_rows)}**\n\n')
    out.write('| case | mode | seed | pass | CPU wall s | CUDA wall s | speedup | max summary delta | upstream rows/pass | shared/skip | up max upload s | materializer rows/pass/apply | carrier rows/skip/patch | carrier max up/dl s | post-guard total ms | transfer plan ms | donor select ms | extraction plan ms |\n')
    out.write('| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |\n')
    for r in out_rows:
        def fmt(x):
            try:
                return f'{float(x):.3f}'
            except Exception:
                return str(x)
        def sci(x):
            try:
                return f'{float(x):.3e}'
            except Exception:
                return str(x)
        out.write(f"| {r['case']} | {r['mode']} | {r['seed']} | {r['pass']} | {fmt(r['cpu_wall_s'])} | {fmt(r['cuda_wall_s'])} | {fmt(r['speedup'])} | {sci(r['max_summary_delta'])} | "
                  f"{r['up_rows']}/{r['up_pass']} | {r['up_shared']}/{r['up_skip']} | {sci(r['up_max_upload'])} | "
                  f"{r['mat_rows']}/{r['mat_pass']}/{r['mat_applied']} | {r['carrier_rows']}/{r['carrier_skip']}/{r['carrier_patch']} | "
                  f"{sci(r['carrier_max_upload'])}/{sci(r['carrier_max_state_dl'])} | {fmt(r['post_guard_total_ms'])} | {fmt(r['plan_ms'])} | {fmt(r['select_ms'])} | {fmt(r['extract_plan_ms'])} |\n")
    out.write(f'\nFlat CSV: `{csv_path}`\n')
    out.write('\nInterpretation: 0474 is PASS when the wall-time summary remains PASS-like, upstream CUDA gate rows pass, shared/skip counters show that the upstream gate did not reintroduce H2D upload, and 0453 materializer rows pass/apply. The post-guard timing columns identify the remaining CPU-authoritative plan cost.\n')

print(report)
PY

cat "$ROOT/cuda_plan_timing_shared_gate_report_0474.md"
