#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"

# 0450: in-solver CUDA upstream shadow smoke.
# This validates CUDA deposit/classification/poor-rich compaction and transfer
# planner against the CPU authoritative workspace, while optionally keeping the
# 0448 CUDA apply backend active for the mutating clean phases.

: "${BIN:=build/src_mpcd_base_cuda_q6_resident_periodic_equiv_0450}"
: "${BASE_UPSTREAM_ROOT:=runs/0450_upstream_shadow_apply_smoke}"
: "${STEPS:=20}"
: "${SUMMARY_EVERY:=1}"
: "${SEED:=1628638}"
: "${RUN_MODES:=src-resampling src-q6-resampling}"
: "${LIVE_VIS_ENABLE:=0}"
: "${FILTERED_RECORDING_ENABLE:=0}"
: "${MAX_SUMMARY_DELTA_TOL:=1e-9}"

rm -rf "$BASE_UPSTREAM_ROOT"
mkdir -p "$BASE_UPSTREAM_ROOT"

export MPCD_CUDA_RESAMPLING_UPSTREAM_SHADOW_0450=1
export MPCD_CUDA_RESAMPLING_UPSTREAM_SHADOW_EVERY_0450=1

BIN="$BIN" \
BASE_APPLY_ROOT="$BASE_UPSTREAM_ROOT" \
STEPS="$STEPS" \
SUMMARY_EVERY="$SUMMARY_EVERY" \
SEED="$SEED" \
RUN_MODES="$RUN_MODES" \
LIVE_VIS_ENABLE="$LIVE_VIS_ENABLE" \
FILTERED_RECORDING_ENABLE="$FILTERED_RECORDING_ENABLE" \
bash scripts/run_0448_periodic_nonzero_plan_apply_smoke.sh

python3 - <<'PY' "$BASE_UPSTREAM_ROOT" "$MAX_SUMMARY_DELTA_TOL"
import csv, os, pathlib, sys
root=pathlib.Path(sys.argv[1])
tol=float(sys.argv[2])
report=root/'upstream_shadow_report_0450.md'
summary_csv=root/'upstream_shadow_summary_0450.csv'

def num(r,k):
    try: return float(r.get(k,'0') or 0)
    except Exception: return 0.0

def rows(path):
    if not path.exists(): return []
    with path.open(newline='') as f: return list(csv.DictReader(f))

def max_col(rs,k):
    return max([abs(num(r,k)) for r in rs] or [0.0])

out=[]
for p in sorted(root.glob('cuda/*/output/cuda_resampling_upstream_shadow_0450.csv')):
    mode=p.parts[-3]
    rs=rows(p)
    handled=[r for r in rs if int(num(r,'handled'))==1]
    passed=[r for r in handled if int(num(r,'pass'))==1]
    skipped=[r for r in rs if int(num(r,'skipped'))==1]
    failed=[r for r in handled if int(num(r,'pass'))!=1]
    row={
        'mode':mode,
        'rows':len(rs),
        'handled':len(handled),
        'passed':len(passed),
        'failed':len(failed),
        'skipped':len(skipped),
        'maxCellIdMismatch':max_col(handled,'cellIdMismatch'),
        'maxCountDiff':max_col(handled,'maxCountDiff'),
        'maxMassAbs':max_col(handled,'maxMassAbs'),
        'maxPxAbs':max_col(handled,'maxPxAbs'),
        'maxPyAbs':max_col(handled,'maxPyAbs'),
        'maxUxAbs':max_col(handled,'maxUxAbs'),
        'maxUyAbs':max_col(handled,'maxUyAbs'),
        'maxReceiverListMismatch':max_col(handled,'receiverListMismatch'),
        'maxDonorListMismatch':max_col(handled,'donorListMismatch'),
        'maxPlanMismatch':max_col(handled,'planMismatch'),
        'maxPlanMassAbs':max_col(handled,'maxPlanMassAbs'),
        'maxPlanDistanceAbs':max_col(handled,'maxPlanDistanceAbs'),
        'maxCpuTransferPairs':max([num(r,'cpuTransferPairs') for r in handled] or [0.0]),
        'maxGpuTransferPairs':max([num(r,'gpuTransferPairs') for r in handled] or [0.0]),
        'maxCpuPassiveOps':max([num(r,'cpuPassiveOps') for r in handled] or [0.0]),
        'maxTotalMassDelta':max([abs(num(r,'cpuTotalMass')-num(r,'gpuTotalMass')) for r in handled] or [0.0]),
        'maxTotalPxDelta':max([abs(num(r,'cpuTotalPx')-num(r,'gpuTotalPx')) for r in handled] or [0.0]),
        'maxTotalPyDelta':max([abs(num(r,'cpuTotalPy')-num(r,'gpuTotalPy')) for r in handled] or [0.0]),
        'csv':str(p),
    }
    ok=(row['rows']>0 and row['handled']==row['passed'] and row['failed']==0 and row['skipped']==0 and
        row['maxCpuTransferPairs']>0 and row['maxCpuPassiveOps']>0 and
        row['maxCellIdMismatch']==0 and row['maxCountDiff']==0 and
        row['maxReceiverListMismatch']==0 and row['maxDonorListMismatch']==0 and row['maxPlanMismatch']==0 and
        row['maxMassAbs']<=2e-10 and row['maxPxAbs']<=2e-10 and row['maxPyAbs']<=2e-10 and
        row['maxPlanMassAbs']<=2e-10 and row['maxPlanDistanceAbs']<=2e-10 and
        row['maxTotalMassDelta']<=2e-10 and row['maxTotalPxDelta']<=2e-10 and row['maxTotalPyDelta']<=2e-10)
    row['pass']=1 if ok else 0
    out.append(row)

fields=['mode','pass','rows','handled','passed','failed','skipped','maxCpuTransferPairs','maxGpuTransferPairs','maxCpuPassiveOps','maxCellIdMismatch','maxCountDiff','maxMassAbs','maxPxAbs','maxPyAbs','maxUxAbs','maxUyAbs','maxReceiverListMismatch','maxDonorListMismatch','maxPlanMismatch','maxPlanMassAbs','maxPlanDistanceAbs','maxTotalMassDelta','maxTotalPxDelta','maxTotalPyDelta','csv']
with summary_csv.open('w', newline='') as f:
    w=csv.DictWriter(f, fieldnames=fields); w.writeheader(); w.writerows(out)

pass_count=sum(r['pass'] for r in out)
with report.open('w') as f:
    f.write('# 0450 CUDA resampling upstream shadow smoke\n\n')
    f.write('Scope: periodic nonzero-plan. CUDA shadows deposit/classification/poor-rich compaction and transfer planner inside the real solver. CPU remains authoritative for upstream; 0448 apply backend may still mutate clean particle edits/remap/thermal in the CUDA variant.\n\n')
    f.write(f'PASS-like modes: **{pass_count}/{len(out)}**\n\n')
    f.write('## Global maxima\n\n')
    for key in ['maxCpuTransferPairs','maxCpuPassiveOps','maxCellIdMismatch','maxCountDiff','maxMassAbs','maxPxAbs','maxPyAbs','maxReceiverListMismatch','maxDonorListMismatch','maxPlanMismatch','maxPlanMassAbs','maxPlanDistanceAbs','maxTotalMassDelta','maxTotalPxDelta','maxTotalPyDelta']:
        f.write(f'- {key}: `{max([r[key] for r in out] or [0.0])}`\n')
    f.write('\n## Per mode\n\n')
    f.write('| mode | pass | rows | handled/pass | transfer pairs CPU/GPU | passive ops | cellIdMismatch | list mismatch R/D | planMismatch | maxMassAbs | maxPlanMassAbs | maxTotalMassDelta |\n')
    f.write('| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |\n')
    for r in out:
        f.write(f"| {r['mode']} | {r['pass']} | {r['rows']} | {r['handled']}/{r['passed']} | {r['maxCpuTransferPairs']:.0f}/{r['maxGpuTransferPairs']:.0f} | {r['maxCpuPassiveOps']:.0f} | {r['maxCellIdMismatch']:.0f} | {r['maxReceiverListMismatch']:.0f}/{r['maxDonorListMismatch']:.0f} | {r['maxPlanMismatch']:.0f} | {r['maxMassAbs']:.3e} | {r['maxPlanMassAbs']:.3e} | {r['maxTotalMassDelta']:.3e} |\n")
    f.write(f"\nFlat CSV: `{summary_csv}`\n")
print(report)
print(report.read_text())
if pass_count != len(out) or not out:
    sys.exit(1)
PY

cat "$BASE_UPSTREAM_ROOT/upstream_shadow_report_0450.md"
