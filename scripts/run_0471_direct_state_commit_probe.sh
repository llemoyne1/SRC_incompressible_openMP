#!/usr/bin/env bash
set -euo pipefail

: "${BIN:=build/src_mpcd_base_cuda_q6_resident_periodic_equiv_0471}"
: "${BASE_0471_ROOT:=runs/0471_direct_state_commit_probe}"
: "${SCALE_CASES:=64x64x40 96x96x40 128x128x40}"
: "${STEPS:=200}"
: "${SUMMARY_EVERY:=50}"
: "${DEVICE_GATE_EVERY:=50}"
: "${SEEDS:=1628638}"
: "${RUN_MODES:=src-resampling src-q6-resampling}"
: "${LIVE_PROGRESS:=1}"
: "${LIVE_VIS_ENABLE:=0}"
: "${FILTERED_RECORDING_ENABLE:=0}"

mkdir -p "$BASE_0471_ROOT"
RAW_ROOT="$BASE_0471_ROOT/raw_scaling"

MPCD_CUDA_RESAMPLING_RESIDENT_EXTERNAL_CARRIER_0467B=1 \
MPCD_CUDA_RESAMPLING_DEFER_RESIDENT_DOWNLOAD_0468=1 \
MPCD_CUDA_RESAMPLING_DIRECT_STATE_COMMIT_0471=1 \
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

python3 - <<'PY' "$BASE_0471_ROOT" "$RAW_ROOT" "$SCALE_CASES" "$SEEDS" "$STEPS" "$DEVICE_GATE_EVERY"
import csv, sys, statistics
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

def find_scale(rec):
    for sr in scale_rows:
        if sr.get('case') == rec['case'] and sr.get('mode') == rec['mode'] and str(sr.get('seed','')) == str(rec['seed']):
            rec['max_delta'] = sr.get('maxSummaryDelta') or sr.get('max summary delta') or ''
            rec['cpu_wall'] = sr.get('cpuWall') or sr.get('CPU wall s') or ''
            rec['cuda_wall'] = sr.get('cudaWall') or sr.get('CUDA wall s') or ''
            rec['speedup'] = sr.get('speedupCpuOverCuda') or sr.get('CPU/CUDA speedup') or ''
            return

records = []
for p in sorted(raw_root.glob('**/cuda_resampling_device_carrier_0455.csv')):
    with p.open(newline='') as f:
        rows = list(csv.DictReader(f))
    if not rows:
        continue
    direct_rows = [r for r in rows if inum(r, 'residentDirectCommit0471') == 1]
    handled_rows = [r for r in rows if inum(r, 'handled') == 1]
    case = case_from_path(p)
    mode = mode_from_path(p)
    seed = seed_from_path(p)
    tx_path = p.parent / 'cuda_resampling_transaction_0466.csv'
    tx_rows = []
    if tx_path.exists():
        with tx_path.open(newline='') as f:
            tx_rows = list(csv.DictReader(f))
    tx_accepted = [r for r in tx_rows if inum(r, 'accepted') == 1]
    tmp_vals = [fnum(r, 'tmpCopySeconds') for r in tx_accepted]
    rec = {
        'case': case,
        'mode': mode,
        'seed': seed,
        'csv_rows': len(rows),
        'handled_rows': len(handled_rows),
        'direct_rows': len(direct_rows),
        'resident_rows': sum(1 for r in rows if inum(r, 'residentCore0467') == 1),
        'external_rows': sum(1 for r in rows if inum(r, 'residentExternal0467B') == 1),
        'deferred_rows': sum(1 for r in rows if inum(r, 'residentDeferredDownload0468') == 1),
        'full_gate_rows': sum(1 for r in rows if inum(r, 'fullGate0461') == 1),
        'tx_rows': len(tx_rows),
        'tx_accepted': len(tx_accepted),
        'max_tmp_copy': max(tmp_vals or [0.0]),
        'mean_tmp_copy': statistics.mean(tmp_vals) if tmp_vals else 0.0,
        'max_upload': max([fnum(r, 'uploadSeconds') for r in rows] or [0.0]),
        'max_state_dl': max([fnum(r, 'stateDownloadSeconds') for r in rows] or [0.0]),
        'max_total': max([fnum(r, 'totalSeconds') for r in rows] or [0.0]),
        'max_delta': '', 'cpu_wall': '', 'cuda_wall': '', 'speedup': '',
    }
    find_scale(rec)
    records.append(rec)

pass_rows = sum(1 for r in records if r['csv_rows'] > 0 and r['direct_rows'] == r['csv_rows'] and r['resident_rows'] == r['csv_rows'] and r['external_rows'] == r['csv_rows'] and r['deferred_rows'] == r['csv_rows'] and r['max_tmp_copy'] == 0.0)

flat = out_root / 'direct_state_commit_summary_0471.csv'
with flat.open('w', newline='') as f:
    fields = ['case','mode','seed','csv_rows','handled_rows','direct_rows','resident_rows','external_rows','deferred_rows','full_gate_rows','tx_rows','tx_accepted','max_tmp_copy_s','mean_tmp_copy_s','cpu_wall_s','cuda_wall_s','speedup','max_summary_delta','max_upload_s','max_state_download_s','max_device_total_s']
    w = csv.DictWriter(f, fieldnames=fields)
    w.writeheader()
    for r in records:
        w.writerow({
            'case': r['case'], 'mode': r['mode'], 'seed': r['seed'],
            'csv_rows': r['csv_rows'], 'handled_rows': r['handled_rows'], 'direct_rows': r['direct_rows'],
            'resident_rows': r['resident_rows'], 'external_rows': r['external_rows'], 'deferred_rows': r['deferred_rows'],
            'full_gate_rows': r['full_gate_rows'], 'tx_rows': r['tx_rows'], 'tx_accepted': r['tx_accepted'],
            'max_tmp_copy_s': r['max_tmp_copy'], 'mean_tmp_copy_s': r['mean_tmp_copy'],
            'cpu_wall_s': r['cpu_wall'], 'cuda_wall_s': r['cuda_wall'], 'speedup': r['speedup'],
            'max_summary_delta': r['max_delta'], 'max_upload_s': r['max_upload'],
            'max_state_download_s': r['max_state_dl'], 'max_device_total_s': r['max_total'],
        })

md = out_root / 'direct_state_commit_report_0471.md'
with md.open('w') as f:
    f.write('# 0471 direct-state commit CUDA resampling probe\n\n')
    f.write('Scope: remove the CPU rollback copy `ParticleState tmp = state` from the validated CUDA resident-carrier path. The host state remains unchanged while the resident core mutates a caller-owned `CudaParticleState`; the mutated state is downloaded directly into the authoritative `ParticleState` only after the gate/apply status is successful.\n\n')
    f.write(f'Scale cases: `{scale_cases}`\n')
    f.write(f'Seeds: `{seeds}`\n')
    f.write(f'Steps: `{steps}`, DEVICE_GATE_EVERY: `{gate_every}`\n\n')
    f.write(f'Direct-state commit rows: **{pass_rows}/{len(records)}**\n\n')
    f.write('| case | mode | seed | CSV rows | direct rows | resident | external | deferred | full gate | tx rows | tx accepted | max tmp copy s | CPU wall s | CUDA wall s | speedup | max summary delta | max upload s | max state dl s | max device total s |\n')
    f.write('| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |\n')
    def fmt(x):
        try: return f'{float(x):.3e}'
        except Exception: return str(x or '')
    def fmt3(x):
        try: return f'{float(x):.3f}'
        except Exception: return str(x or '')
    for r in records:
        f.write(f"| {r['case']} | {r['mode']} | {r['seed']} | {r['csv_rows']} | {r['direct_rows']} | {r['resident_rows']} | {r['external_rows']} | {r['deferred_rows']} | {r['full_gate_rows']} | {r['tx_rows']} | {r['tx_accepted']} | {r['max_tmp_copy']:.3e} | {fmt3(r['cpu_wall'])} | {fmt3(r['cuda_wall'])} | {fmt3(r['speedup'])} | {fmt(r['max_delta'])} | {r['max_upload']:.3e} | {r['max_state_dl']:.3e} | {r['max_total']:.3e} |\n")
    f.write(f'\nFlat CSV: `{flat}`\n')
    f.write('\nInterpretation: success means the transaction-safe CUDA path no longer pays the CPU `ParticleState tmp = state` copy. This still performs one upload and one final successful download per handled step, so it is an acceleration patch, not yet a fully resident multi-step path.\n')

print(md)
PY
