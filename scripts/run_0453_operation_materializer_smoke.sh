#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"

# 0453 smoke: CUDA materializes donor-particle passive operations from the
# accepted transfer plan. CPU still builds the reference list; CUDA replaces the
# compact operation vector only after a strict CPU/GPU gate. The 0448 backend
# remains authoritative for applying extraction/insertion + remap + thermal.

: "${BIN:=build/src_mpcd_base_cuda_q6_resident_periodic_equiv_0453}"
: "${BASE_MATERIALIZE_ROOT:=runs/0453_operation_materializer_smoke}"
: "${STEPS:=20}"
: "${SUMMARY_EVERY:=1}"
: "${SEED:=1628638}"
: "${RUN_MODES:=src-resampling src-q6-resampling}"
: "${LIVE_VIS_ENABLE:=0}"
: "${FILTERED_RECORDING_ENABLE:=0}"
: "${MAX_SUMMARY_DELTA_TOL:=1e-9}"

rm -rf "$BASE_MATERIALIZE_ROOT"
mkdir -p "$BASE_MATERIALIZE_ROOT"

export MPCD_CUDA_RESAMPLING_UPSTREAM_SHADOW_0450=1
export MPCD_CUDA_RESAMPLING_UPSTREAM_SHADOW_EVERY_0450=1
export MPCD_CUDA_RESAMPLING_UPSTREAM_APPLY_0451=1
export MPCD_CUDA_RESAMPLING_UPSTREAM_APPLY_EVERY_0451=1
export MPCD_CUDA_RESAMPLING_OPERATION_MATERIALIZE_0453=1
export MPCD_CUDA_RESAMPLING_OPERATION_MATERIALIZE_EVERY_0453=1

BIN="$BIN" \
BASE_APPLY_ROOT="$BASE_MATERIALIZE_ROOT" \
STEPS="$STEPS" \
SUMMARY_EVERY="$SUMMARY_EVERY" \
SEED="$SEED" \
RUN_MODES="$RUN_MODES" \
LIVE_VIS_ENABLE="$LIVE_VIS_ENABLE" \
FILTERED_RECORDING_ENABLE="$FILTERED_RECORDING_ENABLE" \
MAX_SUMMARY_DELTA_TOL="$MAX_SUMMARY_DELTA_TOL" \
bash scripts/run_0448_periodic_nonzero_plan_apply_smoke.sh

python3 - <<'PY' "$BASE_MATERIALIZE_ROOT" "$MAX_SUMMARY_DELTA_TOL"
import csv, pathlib, sys
root=pathlib.Path(sys.argv[1])
tol=float(sys.argv[2])
report=root/'operation_materializer_report_0453.md'
summary_csv=root/'operation_materializer_summary_0453.csv'

summary_keys=['nFluidParticles','totalMass','Px','Py','meanKinetic','kBTEstimate','meanN','stdN']

def rows(path):
    if not path.exists(): return []
    with path.open(newline='') as f: return list(csv.DictReader(f))

def num(r,k):
    try: return float(r.get(k,'0') or 0)
    except Exception: return 0.0

def last_summary(path):
    rs=rows(path)
    return rs[-1] if rs else {}

def max_col(rs,k):
    return max([abs(num(r,k)) for r in rs] or [0.0])

out=[]
for p in sorted(root.glob('cuda/*/output/cuda_resampling_operation_materialize_0453.csv')):
    mode=p.parts[-3]
    rs=rows(p)
    handled=[r for r in rs if int(num(r,'handled'))==1]
    applied=[r for r in handled if int(num(r,'applied'))==1]
    passed=[r for r in handled if int(num(r,'pass'))==1]
    failed=[r for r in handled if int(num(r,'pass'))!=1]
    skipped=[r for r in rs if int(num(r,'skipped'))==1]
    cpu_dir=root/'cpu'/mode/'output'
    gpu_dir=root/'cuda'/mode/'output'
    cpu=last_summary(cpu_dir/'summary_runtime.csv')
    gpu=last_summary(gpu_dir/'summary_runtime.csv')
    deltas=[abs(num(cpu,k)-num(gpu,k)) for k in summary_keys]
    max_summary_delta=max(deltas or [0.0])
    apply_rows=rows(gpu_dir/'cuda_resampling_pipeline_apply_0448.csv')
    apply_handled=[r for r in apply_rows if int(num(r,'handled'))==1]
    apply_applied=[r for r in apply_handled if int(num(r,'applied'))==1]
    apply_skipped=[r for r in apply_rows if int(num(r,'skipped'))==1]
    invalid_apply=max([num(r,'gpuInvalidOperations') for r in apply_handled] or [0.0])
    row={
        'mode':mode,
        'rows':len(rs),
        'handled':len(handled),
        'applied':len(applied),
        'passed':len(passed),
        'failed':len(failed),
        'skipped':len(skipped),
        'maxPlanEntries':max([num(r,'planEntries') for r in handled] or [0.0]),
        'maxCpuOps':max([num(r,'cpuOps') for r in handled] or [0.0]),
        'maxGpuOps':max([num(r,'gpuOps') for r in handled] or [0.0]),
        'maxInvalidOps':max_col(handled,'invalidOps'),
        'maxOpMismatch':max_col(handled,'opMismatch'),
        'maxDuplicateMismatch':max_col(handled,'duplicateParticleMismatch'),
        'maxMassAbs':max_col(handled,'maxMassAbs'),
        'maxPxAbs':max_col(handled,'maxPxAbs'),
        'maxPyAbs':max_col(handled,'maxPyAbs'),
        'maxMassDelta':max([abs(num(r,'cpuMass')-num(r,'gpuMass')) for r in handled] or [0.0]),
        'maxPxDelta':max([abs(num(r,'cpuPx')-num(r,'gpuPx')) for r in handled] or [0.0]),
        'maxPyDelta':max([abs(num(r,'cpuPy')-num(r,'gpuPy')) for r in handled] or [0.0]),
        'maxKeDelta':max([abs(num(r,'cpuKe')-num(r,'gpuKe')) for r in handled] or [0.0]),
        'applyHandled':len(apply_handled),
        'applyApplied':len(apply_applied),
        'applySkipped':len(apply_skipped),
        'applyInvalidOps':invalid_apply,
        'maxSummaryDelta':max_summary_delta,
    }
    ok=(row['rows']>0 and row['handled']==row['applied']==row['passed'] and row['failed']==0 and row['skipped']==0 and
        row['maxPlanEntries']>0 and row['maxCpuOps']>0 and row['maxCpuOps']==row['maxGpuOps'] and
        row['maxInvalidOps']==0 and row['maxOpMismatch']==0 and row['maxDuplicateMismatch']==0 and
        row['maxMassAbs']<=2e-10 and row['maxPxAbs']<=2e-10 and row['maxPyAbs']<=2e-10 and
        row['maxMassDelta']<=2e-10 and row['maxPxDelta']<=2e-10 and row['maxPyDelta']<=2e-10 and row['maxKeDelta']<=2e-10 and
        row['applyHandled']>0 and row['applySkipped']==0 and row['applyInvalidOps']==0 and row['maxSummaryDelta']<=tol)
    row['pass']=1 if ok else 0
    out.append(row)

fields=['mode','pass','rows','handled','applied','passed','failed','skipped','maxPlanEntries','maxCpuOps','maxGpuOps','maxInvalidOps','maxOpMismatch','maxDuplicateMismatch','maxMassAbs','maxPxAbs','maxPyAbs','maxMassDelta','maxPxDelta','maxPyDelta','maxKeDelta','applyHandled','applyApplied','applySkipped','applyInvalidOps','maxSummaryDelta']
with summary_csv.open('w', newline='') as f:
    w=csv.DictWriter(f, fieldnames=fields); w.writeheader(); w.writerows(out)

pass_count=sum(r['pass'] for r in out)
with report.open('w') as f:
    f.write('# 0453 CUDA resampling operation materializer smoke\n\n')
    f.write('Scope: periodic nonzero-plan. CUDA materializes donor-particle passive extraction/insertion operations from the accepted transfer plan. CPU remains the strict reference gate; on PASS, the compact operation vector consumed by the 0448 CUDA apply backend is replaced by the CUDA-materialized vector.\n\n')
    f.write(f'PASS-like modes: **{pass_count}/{len(out)}**\n\n')
    f.write('## Global maxima\n\n')
    for key in ['maxPlanEntries','maxCpuOps','maxGpuOps','maxInvalidOps','maxOpMismatch','maxDuplicateMismatch','maxMassAbs','maxPxAbs','maxPyAbs','maxMassDelta','maxPxDelta','maxPyDelta','maxKeDelta','applyInvalidOps','maxSummaryDelta']:
        f.write(f'- {key}: `{max([r[key] for r in out] or [0.0])}`\n')
    f.write('\n## Per mode\n\n')
    f.write('| mode | pass | rows | handled/applied/pass | plan entries | ops CPU/GPU | opMismatch | invalidOps | dupMismatch | maxMassAbs | maxPxAbs | maxPyAbs | apply handled/applied | max summary delta |\n')
    f.write('| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |\n')
    for r in out:
        f.write(f"| {r['mode']} | {r['pass']} | {r['rows']} | {r['handled']}/{r['applied']}/{r['passed']} | {r['maxPlanEntries']:.0f} | {r['maxCpuOps']:.0f}/{r['maxGpuOps']:.0f} | {r['maxOpMismatch']:.0f} | {r['maxInvalidOps']:.0f} | {r['maxDuplicateMismatch']:.0f} | {r['maxMassAbs']:.3e} | {r['maxPxAbs']:.3e} | {r['maxPyAbs']:.3e} | {r['applyHandled']}/{r['applyApplied']} | {r['maxSummaryDelta']:.3e} |\n")
    f.write(f"\nFlat CSV: `{summary_csv}`\n")
print(report)
print(report.read_text())
if pass_count != len(out) or not out:
    sys.exit(1)
PY

cat "$BASE_MATERIALIZE_ROOT/operation_materializer_report_0453.md"
