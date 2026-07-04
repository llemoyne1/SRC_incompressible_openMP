#!/usr/bin/env bash
set -euo pipefail

: "${BIN:=build/src_mpcd_base_cuda_q6_resident_periodic_equiv_0468}"
: "${BASE_0468_ROOT:=runs/0468_deferred_resident_download_probe}"
: "${SCALE_CASES:=64x64x40 96x96x40 128x128x40}"
: "${STEPS:=200}"
: "${SUMMARY_EVERY:=50}"
: "${DEVICE_GATE_EVERY:=50}"
: "${SEEDS:=1628638}"
: "${RUN_MODES:=src-resampling src-q6-resampling}"
: "${LIVE_PROGRESS:=1}"
: "${LIVE_VIS_ENABLE:=0}"
: "${FILTERED_RECORDING_ENABLE:=0}"

mkdir -p "$BASE_0468_ROOT"
RAW_ROOT="$BASE_0468_ROOT/raw_scaling"

MPCD_CUDA_RESAMPLING_RESIDENT_EXTERNAL_CARRIER_0467B=1 \
MPCD_CUDA_RESAMPLING_DEFER_RESIDENT_DOWNLOAD_0468=1 \
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

python3 - <<'PY' "$BASE_0468_ROOT" "$RAW_ROOT" "$SCALE_CASES" "$SEEDS" "$STEPS" "$DEVICE_GATE_EVERY"
import csv, sys
from pathlib import Path

out_root = Path(sys.argv[1])
raw_root = Path(sys.argv[2])
scale_cases = sys.argv[3]
seeds = sys.argv[4]
steps = sys.argv[5]
gate_every = sys.argv[6]

def inum(row, key):
    try: return int(float(row.get(key, '') or 0))
    except Exception: return 0

def fnum(row, key):
    try: return float(row.get(key, '') or 0.0)
    except Exception: return 0.0

def case_from_path(p):
    for part in Path(p).parts:
        if '_g' in part and 'x' in part:
            return part
    return '?'

def mode_from_path(p):
    s = str(p)
    if 'src-q6-resampling' in s: return 'src-q6-resampling'
    if 'src-resampling' in s: return 'src-resampling'
    return '?'

def seed_from_path(p):
    for part in Path(p).parts:
        if part.startswith('seed_'):
            return part.replace('seed_', '')
    return ''

scale_rows = []
for cand in [raw_root / 'scaling_cuda_vs_cpu_summary_0464.csv', raw_root / 'scaling_cuda_vs_cpu_summary_0463.csv']:
    if cand.exists():
        with cand.open(newline='') as f:
            scale_rows = list(csv.DictReader(f))
        break

records = []
for p in sorted(raw_root.glob('**/cuda_resampling_device_carrier_0455.csv')):
    with p.open(newline='') as f:
        rows = list(csv.DictReader(f))
    handled = [r for r in rows if inum(r, 'handled') == 1]
    if not handled:
        continue
    external = [inum(r, 'residentExternal0467B') for r in handled]
    resident = [inum(r, 'residentCore0467') for r in handled]
    deferred = [inum(r, 'residentDeferredDownload0468') for r in handled]
    full = [inum(r, 'fullGate0461') for r in handled]
    rec = {
        'case': case_from_path(p),
        'mode': mode_from_path(p),
        'seed': seed_from_path(p),
        'rows': len(rows),
        'handled': len(handled),
        'resident_rows': sum(1 for v in resident if v == 1),
        'external_rows': sum(1 for v in external if v == 1),
        'deferred_rows': sum(1 for v in deferred if v == 1),
        'external_min': min(external) if external else 0,
        'deferred_min': min(deferred) if deferred else 0,
        'full_gate_rows': sum(1 for v in full if v == 1),
        'max_upload': max([fnum(r, 'uploadSeconds') for r in handled] or [0.0]),
        'max_state_dl': max([fnum(r, 'stateDownloadSeconds') for r in handled] or [0.0]),
        'max_total': max([fnum(r, 'totalSeconds') for r in handled] or [0.0]),
        'max_delta': '', 'cpu_wall': '', 'cuda_wall': '', 'speedup': '',
    }
    for sr in scale_rows:
        if sr.get('case') == rec['case'] and sr.get('mode') == rec['mode'] and str(sr.get('seed','')) == str(rec['seed']):
            rec['max_delta'] = sr.get('maxSummaryDelta') or sr.get('max summary delta') or ''
            rec['cpu_wall'] = sr.get('cpuWall') or sr.get('CPU wall s') or ''
            rec['cuda_wall'] = sr.get('cudaWall') or sr.get('CUDA wall s') or ''
            rec['speedup'] = sr.get('speedupCpuOverCuda') or sr.get('CPU/CUDA speedup') or ''
            break
    records.append(rec)

pass_rows = sum(1 for r in records if r['handled'] > 0 and r['resident_rows'] == r['handled'] and r['external_rows'] == r['handled'] and r['deferred_rows'] == r['handled'] and r['external_min'] == 1 and r['deferred_min'] == 1)

flat = out_root / 'deferred_resident_download_summary_0468.csv'
with flat.open('w', newline='') as f:
    fields = ['case','mode','seed','rows','handled','resident_rows','external_rows','deferred_rows','full_gate_rows','cpu_wall_s','cuda_wall_s','speedup','max_summary_delta','max_upload_s','max_state_download_s','max_device_total_s']
    w = csv.DictWriter(f, fieldnames=fields)
    w.writeheader()
    for r in records:
        w.writerow({
            'case': r['case'], 'mode': r['mode'], 'seed': r['seed'], 'rows': r['rows'],
            'handled': r['handled'], 'resident_rows': r['resident_rows'], 'external_rows': r['external_rows'],
            'deferred_rows': r['deferred_rows'], 'full_gate_rows': r['full_gate_rows'],
            'cpu_wall_s': r['cpu_wall'], 'cuda_wall_s': r['cuda_wall'], 'speedup': r['speedup'],
            'max_summary_delta': r['max_delta'], 'max_upload_s': r['max_upload'],
            'max_state_download_s': r['max_state_dl'], 'max_device_total_s': r['max_total'],
        })

md = out_root / 'deferred_resident_download_report_0468.md'
with md.open('w') as f:
    f.write('# 0468 deferred resident-download probe\n\n')
    f.write('Scope: call the 0467 resident CUDA carrier core from a caller-owned `CudaParticleState` with `downloadState=false`, then perform the final state download explicitly in the caller after the gate/apply status is known. Solver behavior remains transaction-safe.\n\n')
    f.write(f'Scale cases: `{scale_cases}`\n')
    f.write(f'Seeds: `{seeds}`\n')
    f.write(f'Steps: `{steps}`, DEVICE_GATE_EVERY: `{gate_every}`\n\n')
    f.write(f'Deferred resident-download rows: **{pass_rows}/{len(records)}**\n\n')
    f.write('| case | mode | seed | rows | handled | resident rows | external rows | deferred rows | full gate rows | CPU wall s | CUDA wall s | speedup | max summary delta | max upload s | max state dl s | max device total s |\n')
    f.write('| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |\n')
    for r in records:
        def fmt(x):
            try: return f'{float(x):.3e}'
            except Exception: return str(x or '')
        def fmt3(x):
            try: return f'{float(x):.3f}'
            except Exception: return str(x or '')
        f.write(f"| {r['case']} | {r['mode']} | {r['seed']} | {r['rows']} | {r['handled']} | {r['resident_rows']} | {r['external_rows']} | {r['deferred_rows']} | {r['full_gate_rows']} | {fmt3(r['cpu_wall'])} | {fmt3(r['cuda_wall'])} | {fmt3(r['speedup'])} | {fmt(r['max_delta'])} | {r['max_upload']:.3e} | {r['max_state_dl']:.3e} | {r['max_total']:.3e} |\n")
    f.write(f'\nFlat CSV: `{flat}`\n')
    f.write('\nInterpretation: 0468 is still not expected to remove the final host download globally. Success means every handled CUDA carrier row has `residentCore0467=1`, `residentExternal0467B=1`, and `residentDeferredDownload0468=1`, proving that the resident core can be run without an internal state download and that the caller can control when the final download happens.\n')

print(md)
PY
