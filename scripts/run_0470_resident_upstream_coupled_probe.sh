#!/usr/bin/env bash
set -euo pipefail

: "${BIN:=build/src_mpcd_base_cuda_q6_resident_periodic_equiv_0470}"
: "${BASE_0470_ROOT:=runs/0470_resident_upstream_coupled_probe}"
: "${SCALE_CASES:=64x64x40 96x96x40 128x128x40}"
: "${STEPS:=200}"
: "${SUMMARY_EVERY:=50}"
: "${DEVICE_GATE_EVERY:=50}"
: "${SEEDS:=1628638}"
: "${RUN_MODES:=src-resampling src-q6-resampling}"
: "${LIVE_PROGRESS:=1}"
: "${LIVE_VIS_ENABLE:=0}"
: "${FILTERED_RECORDING_ENABLE:=0}"

mkdir -p "$BASE_0470_ROOT"
RAW_ROOT="$BASE_0470_ROOT/raw_scaling"

MPCD_CUDA_RESAMPLING_RESIDENT_EXTERNAL_CARRIER_0467B=1 \
MPCD_CUDA_RESAMPLING_DEFER_RESIDENT_DOWNLOAD_0468=1 \
MPCD_CUDA_RESAMPLING_RESIDENT_UPSTREAM_COUPLED_PROBE_0470=1 \
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

python3 - <<'PY' "$BASE_0470_ROOT" "$RAW_ROOT" "$SCALE_CASES" "$SEEDS" "$STEPS" "$DEVICE_GATE_EVERY"
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
for p in sorted(raw_root.glob('**/cuda_resampling_resident_upstream_0470.csv')):
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
        'upstream_ok_rows': sum(1 for r in rows if inum(r, 'upstreamOk') == 1),
        'carrier_ok_rows': sum(1 for r in rows if inum(r, 'carrierOk') == 1),
        'zero_state_dl_rows': sum(1 for r in rows if abs(fnum(r, 'stateDownloadSeconds')) == 0.0),
        'resident_rows': sum(1 for r in rows if inum(r, 'residentCore0467') == 1),
        'external_rows': sum(1 for r in rows if inum(r, 'residentExternal0467B') == 1),
        'deferred_rows': sum(1 for r in rows if inum(r, 'residentDeferredDownload0468') == 1),
        'max_count_diff': max([fnum(r, 'maxCountDiff') for r in rows] or [0.0]),
        'max_mass_abs': max([fnum(r, 'maxMassAbs') for r in rows] or [0.0]),
        'max_px_abs': max([fnum(r, 'maxPxAbs') for r in rows] or [0.0]),
        'max_py_abs': max([fnum(r, 'maxPyAbs') for r in rows] or [0.0]),
        'max_deposit_kernel': max([fnum(r, 'depositKernelSeconds') for r in rows] or [0.0]),
        'max_deposit_download': max([fnum(r, 'depositDownloadSeconds') for r in rows] or [0.0]),
        'max_upload': max([fnum(r, 'probeUploadSeconds') for r in rows] or [0.0]),
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

pass_rows = sum(1 for r in records if r['rows'] > 0 and r['ok_rows'] == r['rows'] and r['upstream_ok_rows'] == r['rows'] and r['carrier_ok_rows'] == r['rows'] and r['zero_state_dl_rows'] == r['rows'] and r['resident_rows'] == r['rows'] and r['external_rows'] == r['rows'] and r['deferred_rows'] == r['rows'])

flat = out_root / 'resident_upstream_coupled_summary_0470.csv'
with flat.open('w', newline='') as f:
    fields = ['case','mode','seed','rows','ok_rows','upstream_ok_rows','carrier_ok_rows','zero_state_dl_rows','resident_rows','external_rows','deferred_rows','cpu_wall_s','cuda_wall_s','speedup','max_summary_delta','max_count_diff','max_mass_abs','max_px_abs','max_py_abs','max_deposit_kernel_s','max_deposit_download_s','max_upload_s','max_state_download_s','max_device_total_s','max_probe_wrapper_s']
    w = csv.DictWriter(f, fieldnames=fields)
    w.writeheader()
    for r in records:
        w.writerow({
            'case': r['case'], 'mode': r['mode'], 'seed': r['seed'], 'rows': r['rows'],
            'ok_rows': r['ok_rows'], 'upstream_ok_rows': r['upstream_ok_rows'], 'carrier_ok_rows': r['carrier_ok_rows'],
            'zero_state_dl_rows': r['zero_state_dl_rows'], 'resident_rows': r['resident_rows'],
            'external_rows': r['external_rows'], 'deferred_rows': r['deferred_rows'],
            'cpu_wall_s': r['cpu_wall'], 'cuda_wall_s': r['cuda_wall'], 'speedup': r['speedup'],
            'max_summary_delta': r['max_delta'], 'max_count_diff': r['max_count_diff'],
            'max_mass_abs': r['max_mass_abs'], 'max_px_abs': r['max_px_abs'], 'max_py_abs': r['max_py_abs'],
            'max_deposit_kernel_s': r['max_deposit_kernel'], 'max_deposit_download_s': r['max_deposit_download'],
            'max_upload_s': r['max_upload'], 'max_state_download_s': r['max_state_dl'],
            'max_device_total_s': r['max_total'], 'max_probe_wrapper_s': r['max_probe_wrapper'],
        })

md = out_root / 'resident_upstream_coupled_report_0470.md'
with md.open('w') as f:
    f.write('# 0470 resident upstream-coupled diagnostic probe\n\n')
    f.write('Scope: run a diagnostic shadow in which a single caller-owned `CudaParticleState` is uploaded once, then used both for CUDA upstream deposit and for the 0467 resident carrier core with `downloadState=false`. The normal 0468 transaction path still performs the actual solver mutation and commit.\n\n')
    f.write(f'Scale cases: `{scale_cases}`\n')
    f.write(f'Seeds: `{seeds}`\n')
    f.write(f'Steps: `{steps}`, DEVICE_GATE_EVERY: `{gate_every}`\n\n')
    f.write(f'Resident upstream-coupled probe rows: **{pass_rows}/{len(records)}**\n\n')
    f.write('| case | mode | seed | rows | ok rows | upstream ok | carrier ok | zero state-dl | resident | external | deferred | CPU wall s | CUDA wall s | speedup | max summary delta | max count diff | max mass abs | max px abs | max py abs | max deposit kernel s | max deposit dl s | max upload s | max state dl s | max device total s | max probe wrapper s |\n')
    f.write('| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |\n')
    def fmt(x):
        try: return f'{float(x):.3e}'
        except Exception: return str(x or '')
    def fmt3(x):
        try: return f'{float(x):.3f}'
        except Exception: return str(x or '')
    for r in records:
        f.write(f"| {r['case']} | {r['mode']} | {r['seed']} | {r['rows']} | {r['ok_rows']} | {r['upstream_ok_rows']} | {r['carrier_ok_rows']} | {r['zero_state_dl_rows']} | {r['resident_rows']} | {r['external_rows']} | {r['deferred_rows']} | {fmt3(r['cpu_wall'])} | {fmt3(r['cuda_wall'])} | {fmt3(r['speedup'])} | {fmt(r['max_delta'])} | {r['max_count_diff']:.3e} | {r['max_mass_abs']:.3e} | {r['max_px_abs']:.3e} | {r['max_py_abs']:.3e} | {r['max_deposit_kernel']:.3e} | {r['max_deposit_download']:.3e} | {r['max_upload']:.3e} | {r['max_state_dl']:.3e} | {r['max_total']:.3e} | {r['max_probe_wrapper']:.3e} |\n")
    f.write(f'\nFlat CSV: `{flat}`\n')
    f.write('\nInterpretation: success means the same resident CUDA particle state can feed the upstream CUDA deposit and the resident carrier core without a final particle-state download. This still leaves the CPU transfer-plan workspace authoritative for the normal solver path; it is a coupling feasibility probe, not a full resident upstream replacement.\n')

print(md)
PY
