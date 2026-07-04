#!/usr/bin/env bash
set -euo pipefail

: "${BIN:=build/src_mpcd_base_cuda_q6_resident_periodic_equiv_0467a}"
: "${BASE_0467_ROOT:=runs/0467_resident_core_refactor_probe}"
: "${SCALE_CASES:=64x64x40 96x96x40 128x128x40}"
: "${STEPS:=200}"
: "${SUMMARY_EVERY:=50}"
: "${DEVICE_GATE_EVERY:=50}"
: "${SEEDS:=1628638}"
: "${RUN_MODES:=src-resampling src-q6-resampling}"
: "${LIVE_PROGRESS:=1}"
: "${LIVE_VIS_ENABLE:=0}"
: "${FILTERED_RECORDING_ENABLE:=0}"

mkdir -p "$BASE_0467_ROOT"
RAW_ROOT="$BASE_0467_ROOT/raw_scaling"

BIN="$BIN" \
BASE_SCALE_ROOT="$RAW_ROOT" \
SCALE_CASES="$SCALE_CASES" \
STEPS="$STEPS" \
SUMMARY_EVERY="$SUMMARY_EVERY" \
DEVICE_GATE_EVERY="$DEVICE_GATE_EVERY" \
SEEDS="$SEEDS" \
RUN_MODES="$RUN_MODES" \
LIVE_PROGRESS="$LIVE_PROGRESS" \
LIVE_VIS_ENABLE="$LIVE_VIS_ENABLE" \
FILTERED_RECORDING_ENABLE="$FILTERED_RECORDING_ENABLE" \
bash scripts/run_0464_scaling_cuda_vs_cpu.sh

python3 - <<'PY' "$BASE_0467_ROOT" "$RAW_ROOT" "$SCALE_CASES" "$SEEDS" "$STEPS" "$DEVICE_GATE_EVERY"
import csv, glob, os, sys, statistics
from pathlib import Path

out_root = Path(sys.argv[1])
raw_root = Path(sys.argv[2])
scale_cases = sys.argv[3]
seeds = sys.argv[4]
steps = sys.argv[5]
gate_every = sys.argv[6]

summary_candidates = list(raw_root.glob('scaling_cuda_vs_cpu_summary_0463.csv')) + list(raw_root.glob('scaling_cuda_vs_cpu_summary_0464.csv'))
scale_rows = []
if summary_candidates:
    with summary_candidates[0].open(newline='') as f:
        scale_rows = list(csv.DictReader(f))

# Map by (case, mode, seed) where possible.
def norm_case_from_path(p):
    for part in Path(p).parts:
        if '_g' in part and 'x' in part:
            return part
    return '?'

def norm_mode_from_path(p):
    s = str(p)
    if 'src-q6-resampling' in s:
        return 'src-q6-resampling'
    if 'src-resampling' in s:
        return 'src-resampling'
    return '?'

def norm_seed_from_path(p):
    for part in Path(p).parts:
        if part.startswith('seed_'):
            return part.replace('seed_', '')
    return ''

def fnum(row, key):
    try:
        return float(row.get(key, '') or 0.0)
    except Exception:
        return 0.0

def inum(row, key):
    try:
        return int(float(row.get(key, '') or 0))
    except Exception:
        return 0

records = []
for p in sorted(raw_root.glob('**/cuda_resampling_device_carrier_0455.csv')):
    with p.open(newline='') as f:
        rows = list(csv.DictReader(f))
    if not rows:
        continue
    handled = [r for r in rows if inum(r, 'handled') == 1]
    if not handled:
        continue
    resident_vals = [inum(r, 'residentCore0467') for r in handled]
    full_gate_vals = [inum(r, 'fullGate0461') for r in handled if 'fullGate0461' in r]
    records.append({
        'case': norm_case_from_path(p),
        'mode': norm_mode_from_path(p),
        'seed': norm_seed_from_path(p),
        'rows': len(rows),
        'handled': len(handled),
        'resident_rows': sum(1 for v in resident_vals if v == 1),
        'resident_min': min(resident_vals) if resident_vals else 0,
        'resident_max': max(resident_vals) if resident_vals else 0,
        'full_gate_rows': sum(1 for v in full_gate_vals if v == 1) if full_gate_vals else 0,
        'max_delta': None,
        'speedup': None,
        'cuda_wall': None,
        'cpu_wall': None,
    })

# Join optional scaling summary.
for rec in records:
    for sr in scale_rows:
        if sr.get('case') == rec['case'] and sr.get('mode') == rec['mode'] and str(sr.get('seed','')) == str(rec['seed']):
            rec['max_delta'] = sr.get('max summary delta') or sr.get('maxSummaryDelta') or sr.get('max_delta')
            rec['speedup'] = sr.get('CPU/CUDA speedup') or sr.get('speedup')
            rec['cuda_wall'] = sr.get('CUDA wall s') or sr.get('cuda wall s')
            rec['cpu_wall'] = sr.get('CPU wall s') or sr.get('cpu wall s')
            break

pass_rows = sum(1 for r in records if r['handled'] > 0 and r['resident_rows'] == r['handled'] and r['resident_min'] == 1)
total_rows = len(records)

flat = out_root / 'resident_core_refactor_summary_0467.csv'
with flat.open('w', newline='') as f:
    fieldnames = ['case','mode','seed','rows','handled','resident_rows','full_gate_rows','cpu_wall_s','cuda_wall_s','speedup','max_summary_delta']
    w = csv.DictWriter(f, fieldnames=fieldnames)
    w.writeheader()
    for r in records:
        w.writerow({
            'case': r['case'], 'mode': r['mode'], 'seed': r['seed'],
            'rows': r['rows'], 'handled': r['handled'], 'resident_rows': r['resident_rows'],
            'full_gate_rows': r['full_gate_rows'], 'cpu_wall_s': r['cpu_wall'], 'cuda_wall_s': r['cuda_wall'],
            'speedup': r['speedup'], 'max_summary_delta': r['max_delta'],
        })

md = out_root / 'resident_core_refactor_report_0467.md'
with md.open('w') as f:
    f.write('# 0467A resident-core refactor probe\n\n')
    f.write('Scope: validate the minimal architectural refactor that extracts a resident CUDA device-carrier core. The legacy transaction wrapper is still used, but it now calls a core routine operating on a supplied `CudaParticleState&`; the core itself does not allocate a local `CudaParticleState` or perform `upload_all`.\n\n')
    f.write(f'Scale cases: `{scale_cases}`\n')
    f.write(f'Seeds: `{seeds}`\n')
    f.write(f'Steps: `{steps}`, DEVICE_GATE_EVERY: `{gate_every}`\n\n')
    f.write(f'Resident-core rows: **{pass_rows}/{total_rows}**\n\n')
    f.write('| case | mode | seed | rows | handled | resident rows | full gate rows | CPU wall s | CUDA wall s | speedup | max summary delta |\n')
    f.write('| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |\n')
    for r in records:
        f.write(f"| {r['case']} | {r['mode']} | {r['seed']} | {r['rows']} | {r['handled']} | {r['resident_rows']} | {r['full_gate_rows']} | {r['cpu_wall'] or ''} | {r['cuda_wall'] or ''} | {r['speedup'] or ''} | {r['max_delta'] or ''} |\n")
    f.write('\nFlat CSV: `resident_core_refactor_summary_0467.csv`\n')
    f.write('\nInterpretation: this probe is not expected to speed up the solver yet. It proves that the carrier logic has been split so a later patch can keep `CudaParticleState` resident across calls and remove the wrapper upload/download.\n')

print(md)
PY
