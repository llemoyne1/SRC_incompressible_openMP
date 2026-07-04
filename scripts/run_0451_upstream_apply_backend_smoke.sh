#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"

# 0451: CUDA upstream apply-gate smoke.
# CUDA recomputes deposit/classification/poor-rich compaction/planner inside the
# real solver and the solver accepts the CUDA upstream only through a strict
# CPU/GPU equivalence gate. The current host mirror workspace remains available
# for the legacy donor-particle operation materializer; 0448 remains the CUDA
# mutating backend for extraction/insertion + remap + thermal.

: "${BIN:=build/src_mpcd_base_cuda_q6_resident_periodic_equiv_0451}"
: "${BASE_UPSTREAM_APPLY_ROOT:=runs/0451_upstream_apply_backend_smoke}"
: "${STEPS:=20}"
: "${SUMMARY_EVERY:=1}"
: "${SEED:=1628638}"
: "${RUN_MODES:=src-resampling src-q6-resampling}"
: "${LIVE_VIS_ENABLE:=0}"
: "${FILTERED_RECORDING_ENABLE:=0}"
: "${MAX_SUMMARY_DELTA_TOL:=1e-9}"

rm -rf "$BASE_UPSTREAM_APPLY_ROOT"
mkdir -p "$BASE_UPSTREAM_APPLY_ROOT"

export MPCD_CUDA_RESAMPLING_UPSTREAM_SHADOW_0450=1
export MPCD_CUDA_RESAMPLING_UPSTREAM_SHADOW_EVERY_0450=1
export MPCD_CUDA_RESAMPLING_UPSTREAM_APPLY_0451=1
export MPCD_CUDA_RESAMPLING_UPSTREAM_APPLY_EVERY_0451=1

BIN="$BIN" \
BASE_APPLY_ROOT="$BASE_UPSTREAM_APPLY_ROOT" \
STEPS="$STEPS" \
SUMMARY_EVERY="$SUMMARY_EVERY" \
SEED="$SEED" \
RUN_MODES="$RUN_MODES" \
LIVE_VIS_ENABLE="$LIVE_VIS_ENABLE" \
FILTERED_RECORDING_ENABLE="$FILTERED_RECORDING_ENABLE" \
MAX_SUMMARY_DELTA_TOL="$MAX_SUMMARY_DELTA_TOL" \
bash scripts/run_0448_periodic_nonzero_plan_apply_smoke.sh

python3 - <<'PY' "$BASE_UPSTREAM_APPLY_ROOT" "$MAX_SUMMARY_DELTA_TOL"
import csv, pathlib, sys
root=pathlib.Path(sys.argv[1])
tol=float(sys.argv[2])
report=root/'upstream_apply_report_0451.md'
summary_csv=root/'upstream_apply_summary_0451.csv'

def rows(path):
    if not path.exists(): return []
    with path.open(newline='') as f: return list(csv.DictReader(f))

def num(r,k):
    try: return float(r.get(k,'0') or 0)
    except Exception: return 0.0

def max_col(rs,k):
    return max([abs(num(r,k)) for r in rs] or [0.0])

def read_last_summary(path):
    rs=rows(path)
    return rs[-1] if rs else {}

summary_keys=['nFluidParticles','totalMass','Px','Py','meanKinetic','kBTEstimate','meanN','stdN']

out=[]
for p in sorted(root.glob('cuda/*/output/cuda_resampling_upstream_apply_0451.csv')):
    mode=p.parts[-3]
    rs=rows(p)
    handled=[r for r in rs if int(num(r,'handled'))==1]
    applied=[r for r in handled if int(num(r,'applied'))==1]
    passed=[r for r in handled if int(num(r,'pass'))==1]
    failed=[r for r in handled if int(num(r,'pass'))!=1]
    skipped=[r for r in rs if int(num(r,'skipped'))==1]
    row={
        'mode':mode,
        'rows':len(rs),
        'handled':len(handled),
        'applied':len(applied),
        'passed':len(passed),
        'failed':len(failed),
        'skipped':len(skipped),
        'maxCpuTransferPairs':max([num(r,'cpuTransferPairs') for r in handled] or [0.0]),
        'maxGpuTransferPairs':max([num(r,'gpuTransferPairs') for r in handled] or [0.0]),
        'maxCpuPassiveOps':max([num(r,'cpuPassiveOps') for r in handled] or [0.0]),
        'maxCellIdMismatch':max_col(handled,'cellIdMismatch'),
        'maxCountDiff':max_col(handled,'maxCountDiff'),
        'maxMassAbs':max_col(handled,'maxMassAbs'),
        'maxPxAbs':max_col(handled,'maxPxAbs'),
        'maxPyAbs':max_col(handled,'maxPyAbs'),
        'maxReceiverListMismatch':max_col(handled,'receiverListMismatch'),
        'maxDonorListMismatch':max_col(handled,'donorListMismatch'),
        'maxPlanMismatch':max_col(handled,'planMismatch'),
        'maxPlanMassAbs':max_col(handled,'maxPlanMassAbs'),
        'maxPlanDistanceAbs':max_col(handled,'maxPlanDistanceAbs'),
        'maxPlannedMassDelta':max([abs(num(r,'cpuPlannedMass')-num(r,'gpuPlannedMass')) for r in handled] or [0.0]),
        'csv':str(p),
    }
    ok=(row['rows']>0 and row['handled']==row['applied']==row['passed'] and row['failed']==0 and row['skipped']==0 and
        row['maxCpuTransferPairs']>0 and row['maxCpuPassiveOps']>0 and row['maxCpuTransferPairs']==row['maxGpuTransferPairs'] and
        row['maxCellIdMismatch']==0 and row['maxCountDiff']==0 and
        row['maxReceiverListMismatch']==0 and row['maxDonorListMismatch']==0 and row['maxPlanMismatch']==0 and
        row['maxMassAbs']<=2e-10 and row['maxPxAbs']<=2e-10 and row['maxPyAbs']<=2e-10 and
        row['maxPlanMassAbs']<=2e-10 and row['maxPlanDistanceAbs']<=2e-10 and row['maxPlannedMassDelta']<=2e-10)
    row['pass']=1 if ok else 0
    out.append(row)

# Recompute the 0448 CPU-baseline vs CUDA-apply check from generated outputs.
for r in out:
    mode=r['mode']
    cpu_dir=root/'cpu'/mode/'output'
    gpu_dir=root/'cuda'/mode/'output'
    cpu=read_last_summary(cpu_dir/'summary_runtime.csv')
    gpu=read_last_summary(gpu_dir/'summary_runtime.csv')
    deltas=[abs(num(cpu,k)-num(gpu,k)) for k in summary_keys]
    r['maxSummaryDelta']=max(deltas or [0.0])
    apply_rows=rows(gpu_dir/'cuda_resampling_pipeline_apply_0448.csv')
    handled=[x for x in apply_rows if int(num(x,'handled'))==1]
    applied=[x for x in handled if int(num(x,'applied'))==1]
    skipped=[x for x in apply_rows if int(num(x,'skipped'))==1]
    invalid=max([num(x,'gpuInvalidOperations') for x in handled] or [0.0])
    r['applyHandled']=len(handled)
    r['applyApplied']=len(applied)
    r['applyPass']=1 if handled and len(skipped)==0 and invalid==0.0 and r['maxSummaryDelta']<=tol else 0
    if r['applyPass'] != 1:
        r['pass']=0

fields=['mode','pass','rows','handled','applied','passed','failed','skipped','maxCpuTransferPairs','maxGpuTransferPairs','maxCpuPassiveOps','maxCellIdMismatch','maxCountDiff','maxMassAbs','maxPxAbs','maxPyAbs','maxReceiverListMismatch','maxDonorListMismatch','maxPlanMismatch','maxPlanMassAbs','maxPlanDistanceAbs','maxPlannedMassDelta','applyPass','maxSummaryDelta','applyHandled','applyApplied','csv']
with summary_csv.open('w', newline='') as f:
    w=csv.DictWriter(f, fieldnames=fields); w.writeheader(); w.writerows(out)

pass_count=sum(r['pass'] for r in out)
with report.open('w') as f:
    f.write('# 0451 CUDA resampling upstream apply-gate smoke\n\n')
    f.write('Scope: periodic nonzero-plan. CUDA recomputes deposit/classification/poor-rich compaction/planner and accepts the upstream through a strict CPU/GPU equivalence gate. 0448 remains authoritative for clean particle edits/remap/thermal in the CUDA variant.\n\n')
    f.write('Note: 0451A is an upstream authority gate, not the final host-free donor-particle materializer. The host workspace remains as mirror for legacy operation materialization.\n\n')
    f.write(f'PASS-like modes: **{pass_count}/{len(out)}**\n\n')
    f.write('## Global maxima\n\n')
    for key in ['maxCpuTransferPairs','maxCpuPassiveOps','maxCellIdMismatch','maxCountDiff','maxMassAbs','maxPxAbs','maxPyAbs','maxReceiverListMismatch','maxDonorListMismatch','maxPlanMismatch','maxPlanMassAbs','maxPlanDistanceAbs','maxPlannedMassDelta','maxSummaryDelta']:
        f.write(f'- {key}: `{max([r[key] for r in out] or [0.0])}`\n')
    f.write('\n## Per mode\n\n')
    f.write('| mode | pass | rows | handled/applied/pass | transfer pairs CPU/GPU | passive ops | planMismatch | maxMassAbs | maxPlanMassAbs | apply pass | max summary delta |\n')
    f.write('| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |\n')
    for r in out:
        f.write(f"| {r['mode']} | {r['pass']} | {r['rows']} | {r['handled']}/{r['applied']}/{r['passed']} | {r['maxCpuTransferPairs']:.0f}/{r['maxGpuTransferPairs']:.0f} | {r['maxCpuPassiveOps']:.0f} | {r['maxPlanMismatch']:.0f} | {r['maxMassAbs']:.3e} | {r['maxPlanMassAbs']:.3e} | {r['applyPass']} | {r['maxSummaryDelta']:.3e} |\n")
    f.write(f"\nFlat CSV: `{summary_csv}`\n")
print(report)
print(report.read_text())
if pass_count != len(out) or not out:
    sys.exit(1)
PY

cat "$BASE_UPSTREAM_APPLY_ROOT/upstream_apply_report_0451.md"
