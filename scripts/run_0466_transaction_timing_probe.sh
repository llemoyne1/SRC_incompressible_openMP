#!/usr/bin/env bash
set -euo pipefail

: "${BIN:=build/src_mpcd_base_cuda_q6_resident_periodic_equiv_0466a}"
: "${BASE_TX_ROOT:=runs/0466_transaction_timing_probe}"
: "${SCALE_CASES:=64x64x40 96x96x40 128x128x40}"
: "${STEPS:=200}"
: "${SUMMARY_EVERY:=50}"
: "${DEVICE_GATE_EVERY:=50}"
: "${SEEDS:=1628638}"
: "${RUN_MODES:=src-resampling src-q6-resampling}"
: "${LIVE_PROGRESS:=1}"
: "${LIVE_VIS_ENABLE:=0}"
: "${FILTERED_RECORDING_ENABLE:=0}"

mkdir -p "$BASE_TX_ROOT"

SCALING_SCRIPT="scripts/run_0464_scaling_cuda_vs_cpu.sh"
if [[ ! -x "$SCALING_SCRIPT" ]]; then
  SCALING_SCRIPT="scripts/run_0463_scaling_cuda_vs_cpu.sh"
fi
if [[ ! -x "$SCALING_SCRIPT" ]]; then
  echo "[0466] missing scaling runner: scripts/run_0464_scaling_cuda_vs_cpu.sh or scripts/run_0463_scaling_cuda_vs_cpu.sh" >&2
  exit 2
fi

BIN="$BIN" \
BASE_SCALE_ROOT="$BASE_TX_ROOT" \
SCALE_CASES="$SCALE_CASES" \
STEPS="$STEPS" \
SUMMARY_EVERY="$SUMMARY_EVERY" \
DEVICE_GATE_EVERY="$DEVICE_GATE_EVERY" \
SEEDS="$SEEDS" \
LIVE_PROGRESS="$LIVE_PROGRESS" \
RUN_MODES="$RUN_MODES" \
LIVE_VIS_ENABLE="$LIVE_VIS_ENABLE" \
FILTERED_RECORDING_ENABLE="$FILTERED_RECORDING_ENABLE" \
bash "$SCALING_SCRIPT"

python3 - "$BASE_TX_ROOT" "$SCALE_CASES" "$SEEDS" "$STEPS" "$DEVICE_GATE_EVERY" <<'PY'
import csv, statistics, sys
from pathlib import Path
root=Path(sys.argv[1])
scale_cases=sys.argv[2]
seeds=sys.argv[3]
steps=sys.argv[4]
gate_every=sys.argv[5]

def fnum(r,k):
    try: return float(r.get(k,'0') or 0)
    except Exception: return 0.0

def inum(r,k):
    try: return int(float(r.get(k,'0') or 0))
    except Exception: return 0

files=sorted(root.glob('**/cuda_resampling_transaction_0466.csv'))
summary=[]
for p in files:
    rows=list(csv.DictReader(open(p, newline='')))
    if not rows: continue
    parts=p.parts
    case=next((x for x in parts if '_g' in x and 'x' in x), '?')
    mode='src-q6-resampling' if 'src-q6-resampling' in str(p) else 'src-resampling'
    seed=next((x.replace('seed_','') for x in parts if x.startswith('seed_')), '?')
    accepted=sum(inum(r,'accepted') for r in rows)
    n=len(rows)
    def mean(k): return statistics.mean([fnum(r,k) for r in rows]) if rows else 0.0
    total=mean('wrapperTotalSeconds')
    tmp=mean('tmpCopySeconds')
    carrier=mean('deviceCarrierSeconds')
    commit=mean('stateCommitSeconds')
    upload=mean('deviceUploadSeconds')
    gate=mean('deviceGateDownloadSeconds')
    statedl=mean('deviceStateDownloadSeconds')
    mat=mean('deviceMaterializeSeconds')
    apply=mean('deviceApplySeconds')
    summary.append({
        'case':case,'mode':mode,'seed':seed,'rows':n,'accepted':accepted,
        'wrapper_ms':1000*total,'tmp_ms':1000*tmp,'carrier_ms':1000*carrier,
        'commit_ms':1000*commit,'upload_ms':1000*upload,'gate_ms':1000*gate,
        'state_dl_ms':1000*statedl,'materialize_ms':1000*mat,'apply_ms':1000*apply,
        'tmp_frac': tmp/total if total>0 else 0.0,
        'carrier_frac': carrier/total if total>0 else 0.0,
    })

out_csv=root/'transaction_timing_summary_0466.csv'
with open(out_csv,'w',newline='') as f:
    fieldnames=['case','mode','seed','rows','accepted','wrapper_ms','tmp_ms','carrier_ms','commit_ms','upload_ms','gate_ms','state_dl_ms','materialize_ms','apply_ms','tmp_frac','carrier_frac']
    w=csv.DictWriter(f, fieldnames=fieldnames)
    w.writeheader(); w.writerows(summary)

report=root/'transaction_timing_report_0466.md'
with open(report,'w') as f:
    f.write('# 0466A CUDA resampling transaction timing probe\n\n')
    f.write('Scope: timing-only instrumentation of the CPU-authoritative transaction wrapper around the CUDA device-carrier path. The solver behavior is unchanged.\n\n')
    f.write(f'Scale cases: `{scale_cases}`\n')
    f.write(f'Seeds: `{seeds}`\n')
    f.write(f'Steps: `{steps}`, DEVICE_GATE_EVERY: `{gate_every}`\n\n')
    f.write(f'Transaction CSV files: **{len(files)}**\n\n')
    if not summary:
        f.write('No transaction rows found. Check that `MPCD_CUDA_RESAMPLING_DEVICE_CARRIER_0455=1` and the 0466A binary were used.\n')
    else:
        f.write('| case | mode | seed | rows | accepted | wrapper ms | tmp copy ms | carrier ms | commit ms | upload ms | gate dl ms | state dl ms | materialize ms | apply ms | tmp frac | carrier frac |\n')
        f.write('| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |\n')
        for r in sorted(summary, key=lambda x:(x['case'],x['mode'],x['seed'])):
            f.write(f"| {r['case']} | {r['mode']} | {r['seed']} | {r['rows']} | {r['accepted']} | {r['wrapper_ms']:.3f} | {r['tmp_ms']:.3f} | {r['carrier_ms']:.3f} | {r['commit_ms']:.3f} | {r['upload_ms']:.3f} | {r['gate_ms']:.3f} | {r['state_dl_ms']:.3f} | {r['materialize_ms']:.3f} | {r['apply_ms']:.3f} | {r['tmp_frac']:.3f} | {r['carrier_frac']:.3f} |\n")
    f.write(f'\nFlat CSV: `{out_csv}`\n')
PY

echo "[0466] report: $BASE_TX_ROOT/transaction_timing_report_0466.md"
