#!/usr/bin/env bash
set -euo pipefail

: "${BIN:=build/src_mpcd_base_cuda_q6_resident_periodic_equiv_0469}"
: "${BASE_0469_ROOT:=runs/0469_resident_no_final_download_probe}"
: "${SCALE_CASES:=64x64x40 96x96x40 128x128x40}"
: "${STEPS:=200}"
: "${SUMMARY_EVERY:=50}"
: "${DEVICE_GATE_EVERY:=50}"
: "${SEEDS:=1628638}"
: "${RUN_MODES:=src-resampling src-q6-resampling}"
: "${LIVE_PROGRESS:=1}"
: "${LIVE_VIS_ENABLE:=0}"
: "${FILTERED_RECORDING_ENABLE:=0}"

mkdir -p "$BASE_0469_ROOT"
RAW_ROOT="$BASE_0469_ROOT/raw_scaling"

MPCD_CUDA_RESAMPLING_RESIDENT_EXTERNAL_CARRIER_0467B=1 \
MPCD_CUDA_RESAMPLING_DEFER_RESIDENT_DOWNLOAD_0468=1 \
MPCD_CUDA_RESAMPLING_RESIDENT_NO_FINAL_DOWNLOAD_PROBE_0469=1 \
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

python3 - <<'PY' "$BASE_0469_ROOT" "$RAW_ROOT" "$SCALE_CASES" "$SEEDS" "$STEPS" "$DEVICE_GATE_EVERY"
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
for p in sorted(raw_root.glob('**/cuda_resampling_resident_nodownload_0469.csv')):
    with p.open(newline='') as f:
        rows = list(csv.DictReader(f))
    if not rows:
        continue
    rec = {
        'case': case_from_path(p),
        'mode': mode_from_path(p),
        'seed': seed_from_path(p),
        'rows': len(rows),
        'ok_rows': sum(1 for r in rows if inum(r, 'ok') == 1),
        'zero_state_dl_rows': sum(1 for r in rows if abs(fnum(r, 'stateDownloadSeconds')) == 0.0),
        'resident_rows': sum(1 for r in rows if inum(r, 'residentCore0467') == 1),
        'external_rows': sum(1 for r in rows if inum(r, 'residentExternal0467B') == 1),
        'deferred_rows': sum(1 for r in rows if inum(r, 'residentDeferredDownload0468') == 1),
        'max_upload': max([fnum(r, 'uploadSeconds') for r in rows] or [0.0]),
        'max_state_dl': max([fnum(r, 'stateDownloadSeconds') for r in rows] or [0.0]),
        'max_total': max([fnum(r, 'totalSeconds') for r in rows] or [0.0]),
        'max_probe_wrapper': max([fnum(r, 'probeWrapperSeconds') for r in rows] or [0.0]),
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

pass_rows = sum(1 for r in records if r['rows'] > 0 and r['ok_rows'] == r['rows'] and r['zero_state_dl_rows'] == r['rows'] and r['resident_rows'] == r['rows'] and r['external_rows'] == r['rows'] and r['deferred_rows'] == r['rows'])

flat = out_root / 'resident_no_final_download_summary_0469.csv'
with flat.open('w', newline='') as f:
    fields = ['case','mode','seed','rows','ok_rows','zero_state_dl_rows','resident_rows','external_rows','deferred_rows','cpu_wall_s','cuda_wall_s','speedup','max_summary_delta','max_upload_s','max_state_download_s','max_device_total_s','max_probe_wrapper_s']
    w = csv.DictWriter(f, fieldnames=fields)
    w.writeheader()
    for r in records:
        w.writerow({
            'case': r['case'], 'mode': r['mode'], 'seed': r['seed'], 'rows': r['rows'],
            'ok_rows': r['ok_rows'], 'zero_state_dl_rows': r['zero_state_dl_rows'],
            'resident_rows': r['resident_rows'], 'external_rows': r['external_rows'], 'deferred_rows': r['deferred_rows'],
            'cpu_wall_s': r['cpu_wall'], 'cuda_wall_s': r['cuda_wall'], 'speedup': r['speedup'],
            'max_summary_delta': r['max_delta'], 'max_upload_s': r['max_upload'],
            'max_state_download_s': r['max_state_dl'], 'max_device_total_s': r['max_total'],
            'max_probe_wrapper_s': r['max_probe_wrapper'],
        })

md = out_root / 'resident_no_final_download_report_0469.md'
with md.open('w') as f:
    f.write('# 0469 resident no-final-download diagnostic probe\n\n')
    f.write('Scope: run a diagnostic shadow call to the 0467 resident CUDA carrier core on a caller-owned `CudaParticleState` with `downloadState=false`, and intentionally do not download the mutated shadow state. The normal 0468 transaction path still performs the actual solver mutation and commit.\n\n')
    f.write(f'Scale cases: `{scale_cases}`\n')
    f.write(f'Seeds: `{seeds}`\n')
    f.write(f'Steps: `{steps}`, DEVICE_GATE_EVERY: `{gate_every}`\n\n')
    f.write(f'No-final-download probe rows: **{pass_rows}/{len(records)}**\n\n')
    f.write('| case | mode | seed | rows | ok rows | zero state-dl rows | resident rows | external rows | deferred rows | CPU wall s | CUDA wall s | speedup | max summary delta | max upload s | max state dl s | max device total s | max probe wrapper s |\n')
    f.write('| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |\n')
    def fmt(x):
        try: return f'{float(x):.3e}'
        except Exception: return str(x or '')
    def fmt3(x):
        try: return f'{float(x):.3f}'
        except Exception: return str(x or '')
    for r in records:
        f.write(f"| {r['case']} | {r['mode']} | {r['seed']} | {r['rows']} | {r['ok_rows']} | {r['zero_state_dl_rows']} | {r['resident_rows']} | {r['external_rows']} | {r['deferred_rows']} | {fmt3(r['cpu_wall'])} | {fmt3(r['cuda_wall'])} | {fmt3(r['speedup'])} | {fmt(r['max_delta'])} | {r['max_upload']:.3e} | {r['max_state_dl']:.3e} | {r['max_total']:.3e} | {r['max_probe_wrapper']:.3e} |\n")
    f.write(f'\nFlat CSV: `{flat}`\n')
    f.write('\nInterpretation: success means the resident carrier core can materialize, gate, and apply operations while leaving the updated particle state on device only (`stateDownloadSeconds=0`). This is still a diagnostic shadow: CPU upstream remains authoritative and the normal 0468 path still downloads/commits host state.\n')

print(md)
PY
