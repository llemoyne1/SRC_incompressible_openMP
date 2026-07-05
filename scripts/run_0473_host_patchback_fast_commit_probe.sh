#!/usr/bin/env bash
set -euo pipefail

: "${BIN:=build/src_mpcd_base_cuda_q6_resident_periodic_equiv_0473}"
: "${BASE_0473_ROOT:=runs/0473_host_patchback_fast_commit_probe}"
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
export MPCD_CUDA_RESAMPLING_ACTIVE_PREFIX_DOWNLOAD_0472=0
export MPCD_CUDA_RESAMPLING_HOST_PATCHBACK_0473=1

SCALING_RUNNER="${SCALING_RUNNER:-}"
if [[ -z "$SCALING_RUNNER" ]]; then
  if [[ -x scripts/run_0464_scaling_cuda_vs_cpu.sh ]]; then
    SCALING_RUNNER="scripts/run_0464_scaling_cuda_vs_cpu.sh"
  elif [[ -x scripts/run_0463_scaling_cuda_vs_cpu.sh ]]; then
    SCALING_RUNNER="scripts/run_0463_scaling_cuda_vs_cpu.sh"
  else
    echo "[0473] missing scaling runner: expected scripts/run_0464_scaling_cuda_vs_cpu.sh or scripts/run_0463_scaling_cuda_vs_cpu.sh" >&2
    exit 2
  fi
fi

BASE_SCALE_ROOT="$BASE_0473_ROOT" \
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
import csv, os, statistics
from pathlib import Path

root = Path(os.environ.get('BASE_0473_ROOT','runs/0473_host_patchback_fast_commit_probe'))
out_csv = root / 'host_patchback_fast_commit_summary_0473.csv'
out_md = root / 'host_patchback_fast_commit_report_0473.md'
scale_csv = root / 'scaling_cuda_vs_cpu_summary_0464.csv'
if not scale_csv.exists():
    scale_csv = root / 'scaling_cuda_vs_cpu_summary_0463.csv'

def fnum(r,k):
    try: return float(r.get(k,'') or 0.0)
    except Exception: return 0.0

def inum(r,k):
    try: return int(float(r.get(k,'') or 0))
    except Exception: return 0

scale = {}
if scale_csv.exists():
    with scale_csv.open(newline='') as f:
        for r in csv.DictReader(f):
            scale[(r.get('case',''), r.get('mode',''), r.get('seed',''))] = r

rows = []
for p in sorted(root.glob('**/cuda_resampling_device_carrier_0455.csv')):
    with p.open(newline='') as f:
        dr = list(csv.DictReader(f))
    handled = [r for r in dr if inum(r,'handled') == 1]
    if not handled:
        continue
    parts = p.parts
    case = next((x for x in parts if '_g' in x and 'x' in x), '')
    seed = next((x.split('seed_',1)[1] for x in parts if x.startswith('seed_')), '')
    mode = 'src-q6-resampling' if any('src-q6-resampling' in x for x in parts) else 'src-resampling'
    sr = scale.get((case,mode,seed), {})
    def s(key): return sum(inum(r,key) for r in handled)
    maxv = lambda key: max([fnum(r,key) for r in handled] or [0.0])
    meanv = lambda key: statistics.mean([fnum(r,key) for r in handled] or [0.0])
    rows.append({
        'case':case,'mode':mode,'seed':seed,
        'csv_rows':len(handled),
        'pass': sr.get('pass',''),
        'cpu_wall_s': sr.get('CPU wall s') or sr.get('cpu_wall_s') or '',
        'cuda_wall_s': sr.get('CUDA wall s') or sr.get('cuda_wall_s') or '',
        'speedup': sr.get('CPU/CUDA speedup') or sr.get('speedup') or '',
        'max_summary_delta': sr.get('max summary delta') or sr.get('max_summary_delta') or '',
        'ops': sr.get('ops CPU/GPU') or sr.get('ops_cpu_gpu') or '',
        'invalid': sr.get('invalid mat/apply') or '',
        'mismatch': sr.get('mismatch op/dup') or '',
        'shared_rows': s('residentSharedState0472'),
        'upload_skipped_rows': s('residentSharedUploadSkipped0472'),
        'active_prefix_dl_rows': s('residentActivePrefixDownload0472'),
        'host_patchback_rows': s('residentHostPatchback0473'),
        'host_patchback_ops_max': max([inum(r,'hostPatchbackOps0473') for r in handled] or [0]),
        'direct_rows': s('residentDirectCommit0471'),
        'full_gate_rows': s('fullGate0461'),
        'max_upload_s': maxv('uploadSeconds'),
        'mean_upload_s': meanv('uploadSeconds'),
        'max_state_dl_s': maxv('stateDownloadSeconds'),
        'mean_state_dl_s': meanv('stateDownloadSeconds'),
        'max_patch_s': maxv('hostPatchbackSeconds'),
        'mean_patch_s': meanv('hostPatchbackSeconds'),
        'max_device_total_s': maxv('totalSeconds'),
    })
rows.sort(key=lambda r:(r['case'], r['mode'], r['seed']))
out_csv.parent.mkdir(parents=True, exist_ok=True)
fields = ['case','mode','seed','csv_rows','pass','cpu_wall_s','cuda_wall_s','speedup','max_summary_delta','ops','invalid','mismatch','shared_rows','upload_skipped_rows','active_prefix_dl_rows','host_patchback_rows','host_patchback_ops_max','direct_rows','full_gate_rows','max_upload_s','mean_upload_s','max_state_dl_s','mean_state_dl_s','max_patch_s','mean_patch_s','max_device_total_s']
with out_csv.open('w', newline='') as f:
    w = csv.DictWriter(f, fieldnames=fields)
    w.writeheader(); w.writerows(rows)

ok = sum(1 for r in rows if r['pass'] in ('1','1.0') and r['host_patchback_rows'] == r['csv_rows'] and r['shared_rows'] == r['csv_rows'] and r['upload_skipped_rows'] == r['csv_rows'] and r['max_upload_s'] == 0.0 and r['max_state_dl_s'] == 0.0)
with out_md.open('w') as f:
    f.write('# 0473 host-patchback fast-commit CUDA resampling probe\n\n')
    f.write('Scope: combine performance validation with a faster synchronization path. The validated 0472 shared CUDA state path is kept, but the final host synchronization no longer downloads the active prefix. Instead, the resident core downloads only the compact operation payload and the caller patches the authoritative host `ParticleState` at the changed particle indices.\n\n')
    f.write(f'Scale cases: `{os.environ.get("SCALE_CASES","")}`\n')
    f.write(f'Seeds: `{os.environ.get("SEEDS","")}`\n')
    f.write(f'Steps: `{os.environ.get("STEPS","")}`, DEVICE_GATE_EVERY: `{os.environ.get("DEVICE_GATE_EVERY","")}`\n\n')
    f.write(f'Host-patchback fast-commit rows: **{ok}/{len(rows)}**\n\n')
    f.write('| case | mode | seed | pass | CPU wall s | CUDA wall s | speedup | max summary delta | CSV rows | shared | upload skipped | active-prefix dl | host patchback | max patch ops | full gate | max upload s | max state dl s | max patch s | max device total s |\n')
    f.write('| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |\n')
    for r in rows:
        f.write(f"| {r['case']} | {r['mode']} | {r['seed']} | {r['pass']} | {r['cpu_wall_s']} | {r['cuda_wall_s']} | {r['speedup']} | {r['max_summary_delta']} | {r['csv_rows']} | {r['shared_rows']} | {r['upload_skipped_rows']} | {r['active_prefix_dl_rows']} | {r['host_patchback_rows']} | {r['host_patchback_ops_max']} | {r['full_gate_rows']} | {r['max_upload_s']:.3e} | {r['max_state_dl_s']:.3e} | {r['max_patch_s']:.3e} | {r['max_device_total_s']:.3e} |\n")
    f.write(f"\nFlat CSV: `{out_csv}`\n\n")
    f.write('Interpretation: success means the solver remains PASS-like while the CUDA resampling commit avoids both the per-step host→device upload and the active-prefix/full-state download. Only the compact changed-particle operation payload is downloaded for host patchback.\n')
print(out_md)
PY
