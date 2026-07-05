#!/usr/bin/env bash
set -euo pipefail

: "${BIN:=build/src_mpcd_base_cuda_q6_resident_periodic_equiv_0472}"
: "${BASE_0472_ROOT:=runs/0472_shared_state_fast_sync_probe}"
: "${SCALE_CASES:=64x64x40 96x96x40 128x128x40}"
: "${STEPS:=200}"
: "${SUMMARY_EVERY:=50}"
: "${DEVICE_GATE_EVERY:=50}"
: "${SEEDS:=1628638}"
: "${RUN_MODES:=src-resampling src-q6-resampling}"
: "${LIVE_PROGRESS:=1}"
: "${LIVE_VIS_ENABLE:=0}"
: "${FILTERED_RECORDING_ENABLE:=0}"

export MPCD_CUDA_RESAMPLING_DIRECT_STATE_COMMIT_0471=1
export MPCD_CUDA_RESAMPLING_SHARED_STATE_DIRECT_COMMIT_0472=1
export MPCD_CUDA_RESAMPLING_ACTIVE_PREFIX_DOWNLOAD_0472=1

SCALING_RUNNER="${SCALING_RUNNER:-}"
if [[ -z "$SCALING_RUNNER" ]]; then
  if [[ -x scripts/run_0464_scaling_cuda_vs_cpu.sh ]]; then
    SCALING_RUNNER="scripts/run_0464_scaling_cuda_vs_cpu.sh"
  elif [[ -x scripts/run_0463_scaling_cuda_vs_cpu.sh ]]; then
    SCALING_RUNNER="scripts/run_0463_scaling_cuda_vs_cpu.sh"
  else
    echo "[0472] missing scaling runner: expected scripts/run_0464_scaling_cuda_vs_cpu.sh or scripts/run_0463_scaling_cuda_vs_cpu.sh" >&2
    exit 2
  fi
fi

BASE_SCALE_ROOT="$BASE_0472_ROOT" \
BIN="$BIN" \
SCALE_CASES="$SCALE_CASES" \
STEPS="$STEPS" \
SUMMARY_EVERY="$SUMMARY_EVERY" \
DEVICE_GATE_EVERY="$DEVICE_GATE_EVERY" \
SEEDS="$SEEDS" \
RUN_MODES="$RUN_MODES" \
LIVE_PROGRESS="$LIVE_PROGRESS" \
LIVE_VIS_ENABLE="$LIVE_VIS_ENABLE" \
FILTERED_RECORDING_ENABLE="$FILTERED_RECORDING_ENABLE" \
bash "$SCALING_RUNNER"

python3 - <<'PY'
import csv, glob, os, statistics
from pathlib import Path

root = Path(os.environ.get('BASE_0472_ROOT','runs/0472_shared_state_fast_sync_probe'))
out_csv = root / 'shared_state_fast_sync_summary_0472.csv'
out_md = root / 'shared_state_fast_sync_report_0472.md'

scale_candidates = [root / 'scaling_cuda_vs_cpu_summary_0464.csv', root / 'scaling_cuda_vs_cpu_summary_0463.csv']
scale_csv = next((q for q in scale_candidates if q.exists()), scale_candidates[-1])

def fnum(r, key):
    try:
        return float(r.get(key,'') or 0.0)
    except Exception:
        return 0.0

def inum(r, key):
    try:
        return int(float(r.get(key,'') or 0))
    except Exception:
        return 0

scale = {}
if scale_csv.exists():
    with scale_csv.open(newline='') as f:
        for r in csv.DictReader(f):
            case = r.get('case') or r.get('Case') or ''
            mode = r.get('mode') or r.get('Mode') or ''
            seed = r.get('seed') or r.get('Seed') or ''
            scale[(case,mode,seed)] = r

rows=[]
for p in sorted(root.glob('**/cuda_resampling_device_carrier_0455.csv')):
    with p.open(newline='') as f:
        dr = list(csv.DictReader(f))
    handled = [r for r in dr if inum(r,'handled') == 1]
    if not handled:
        continue
    parts = p.parts
    case = next((x for x in parts if '_g' in x and 'x' in x), '')
    seed = ''
    for x in parts:
        if x.startswith('seed_'):
            seed = x.split('seed_',1)[1]
            break
    mode = 'src-q6-resampling' if any('src-q6-resampling' in x for x in parts) else 'src-resampling'
    sr = scale.get((case,mode,seed), {})
    shared = sum(inum(r,'residentSharedState0472') for r in handled)
    skipped = sum(inum(r,'residentSharedUploadSkipped0472') for r in handled)
    active_dl = sum(inum(r,'residentActivePrefixDownload0472') for r in handled)
    direct = sum(inum(r,'residentDirectCommit0471') for r in handled)
    full_gate = sum(inum(r,'fullGate0461') for r in handled)
    vals_upload=[fnum(r,'uploadSeconds') for r in handled]
    vals_dl=[fnum(r,'stateDownloadSeconds') for r in handled]
    vals_total=[fnum(r,'totalSeconds') for r in handled]
    rows.append({
        'case':case,'mode':mode,'seed':seed,
        'csv_rows':len(handled),
        'shared_rows':shared,
        'upload_skipped_rows':skipped,
        'active_prefix_dl_rows':active_dl,
        'direct_rows':direct,
        'full_gate_rows':full_gate,
        'cpu_wall_s': sr.get('CPU wall s') or sr.get('cpu_wall_s') or sr.get('CPU wall') or '',
        'cuda_wall_s': sr.get('CUDA wall s') or sr.get('cuda_wall_s') or sr.get('CUDA wall') or '',
        'speedup': sr.get('CPU/CUDA speedup') or sr.get('speedup') or '',
        'max_summary_delta': sr.get('max summary delta') or sr.get('max_summary_delta') or '',
        'max_upload_s': max(vals_upload) if vals_upload else 0.0,
        'mean_upload_s': statistics.mean(vals_upload) if vals_upload else 0.0,
        'max_state_dl_s': max(vals_dl) if vals_dl else 0.0,
        'mean_state_dl_s': statistics.mean(vals_dl) if vals_dl else 0.0,
        'max_device_total_s': max(vals_total) if vals_total else 0.0,
    })

rows.sort(key=lambda r:(r['case'], r['mode'], r['seed']))
out_csv.parent.mkdir(parents=True, exist_ok=True)
fields=['case','mode','seed','csv_rows','shared_rows','upload_skipped_rows','active_prefix_dl_rows','direct_rows','full_gate_rows','cpu_wall_s','cuda_wall_s','speedup','max_summary_delta','max_upload_s','mean_upload_s','max_state_dl_s','mean_state_dl_s','max_device_total_s']
with out_csv.open('w', newline='') as f:
    w=csv.DictWriter(f, fieldnames=fields)
    w.writeheader(); w.writerows(rows)

ok = sum(1 for r in rows if r['csv_rows']>0 and r['shared_rows']==r['csv_rows'] and r['active_prefix_dl_rows']==r['csv_rows'] and r['direct_rows']==r['csv_rows'])
with out_md.open('w') as f:
    f.write('# 0472 shared-state fast-sync CUDA resampling probe\n\n')
    f.write('Scope: use the process-local shared `CudaParticleState` in the validated 0471 direct-state commit path. If the shared state is fresh, the resampling carrier skips the per-step upload; after a successful apply, it downloads only the active prefix and marks the shared state fresh again.\n\n')
    f.write(f'Scale cases: `{os.environ.get("SCALE_CASES","")}`\n')
    f.write(f'Seeds: `{os.environ.get("SEEDS","")}`\n')
    f.write(f'Steps: `{os.environ.get("STEPS","")}`, DEVICE_GATE_EVERY: `{os.environ.get("DEVICE_GATE_EVERY","")}`\n\n')
    f.write(f'Shared-state fast-sync rows: **{ok}/{len(rows)}**\n\n')
    f.write('| case | mode | seed | CSV rows | shared rows | upload skipped | active-prefix dl | direct rows | full gate | CPU wall s | CUDA wall s | speedup | max summary delta | max upload s | mean upload s | max state dl s | mean state dl s | max device total s |\n')
    f.write('| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |\n')
    for r in rows:
        f.write(f"| {r['case']} | {r['mode']} | {r['seed']} | {r['csv_rows']} | {r['shared_rows']} | {r['upload_skipped_rows']} | {r['active_prefix_dl_rows']} | {r['direct_rows']} | {r['full_gate_rows']} | {r['cpu_wall_s']} | {r['cuda_wall_s']} | {r['speedup']} | {r['max_summary_delta']} | {r['max_upload_s']:.3e} | {r['mean_upload_s']:.3e} | {r['max_state_dl_s']:.3e} | {r['mean_state_dl_s']:.3e} | {r['max_device_total_s']:.3e} |\n")
    f.write(f"\nFlat CSV: `{out_csv}`\n\n")
    f.write('Interpretation: success means the direct-state commit path uses the caller/process shared CUDA state and active-prefix host synchronization. `upload skipped` indicates the expensive host→device refresh was avoided because the shared state was already fresh at the resampling point.\n')
print(out_md)
PY
