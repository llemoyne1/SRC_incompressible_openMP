#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"

# 0448 smoke: compare the CPU-authoritative clean pipeline against the
# experimental CUDA-authoritative clean apply backend on the same periodic
# nonzero-plan synthetic case.  CUDA-local auxiliaries and guards remain off via
# the 0446 runner defaults.

BASE_APPLY_ROOT="${BASE_APPLY_ROOT:-runs/0448_periodic_nonzero_plan_apply_smoke}"
BIN="${BIN:-build/src_mpcd_base_cuda_q6_resident_periodic_equiv_0448}"
STEPS="${STEPS:-20}"
SUMMARY_EVERY="${SUMMARY_EVERY:-1}"
SEED="${SEED:-1628638}"
RUN_MODES="${RUN_MODES:-src-resampling src-q6-resampling}"
LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-0}"
FILTERED_RECORDING_ENABLE="${FILTERED_RECORDING_ENABLE:-0}"

run_variant() {
  local variant=$1 apply=$2
  echo "[0448] variant=$variant apply=$apply"
  BIN="$BIN" \
  BASE_RUN_ROOT="$BASE_APPLY_ROOT/$variant" \
  STEPS="$STEPS" \
  SUMMARY_EVERY="$SUMMARY_EVERY" \
  SEED="$SEED" \
  RUN_MODES="$RUN_MODES" \
  LIVE_VIS_ENABLE="$LIVE_VIS_ENABLE" \
  FILTERED_RECORDING_ENABLE="$FILTERED_RECORDING_ENABLE" \
  MPCD_CUDA_RESAMPLING_PIPELINE_APPLY_0448="$apply" \
  MPCD_CUDA_RESAMPLING_PIPELINE_SHADOW_0445=1 \
  MPCD_CUDA_RESAMPLING_PIPELINE_SHADOW_EVERY_0445=1 \
  bash scripts/run_0446_periodic_nonzero_plan_shadow_smoke.sh
}

rm -rf "$BASE_APPLY_ROOT"
mkdir -p "$BASE_APPLY_ROOT"
run_variant cpu 0
run_variant cuda 1

python3 - <<'PY'
import csv, math, os, pathlib, sys
root = pathlib.Path(os.environ.get('BASE_APPLY_ROOT', 'runs/0448_periodic_nonzero_plan_apply_smoke'))
modes = os.environ.get('RUN_MODES', 'src-resampling src-q6-resampling').split()
steps = int(os.environ.get('STEPS', '20'))

def read_summary(path):
    with path.open(newline='') as f:
        rows=list(csv.DictReader(f))
    if not rows:
        raise RuntimeError(f'empty summary {path}')
    return rows[-1]

def f(r,k):
    try: return float(r.get(k,'0') or 0)
    except Exception: return 0.0

def read_shadow_stats(path):
    rows=list(csv.DictReader(path.open(newline='')))
    handled=[r for r in rows if r.get('handled')=='1']
    failed=[r for r in handled if r.get('pass')!='1']
    skipped=[r for r in rows if r.get('skipped')=='1']
    nonzero=[r for r in handled if f(r,'passiveOps')>0]
    return {
        'rows': len(rows),
        'handled': len(handled),
        'failed': len(failed),
        'skipped': len(skipped),
        'nonzero': len(nonzero),
        'maxPassiveOps': max([f(r,'passiveOps') for r in nonzero] or [0.0]),
        'maxAbsMass': max([abs(f(r,'maxAbsMass')) for r in handled] or [0.0]),
        'maxAbsVx': max([abs(f(r,'maxAbsVx')) for r in handled] or [0.0]),
        'maxAbsVy': max([abs(f(r,'maxAbsVy')) for r in handled] or [0.0]),
        'maxRoleMismatch': max([f(r,'roleMismatch') for r in handled] or [0.0]),
        'maxTypeMismatch': max([f(r,'typeMismatch') for r in handled] or [0.0]),
    }

def read_apply_stats(path):
    rows=list(csv.DictReader(path.open(newline=''))) if path.exists() else []
    handled=[r for r in rows if r.get('handled')=='1']
    skipped=[r for r in rows if r.get('skipped')=='1']
    return {
        'rows': len(rows),
        'handled': len(handled),
        'skipped': len(skipped),
        'appliedRows': sum(1 for r in handled if r.get('applied')=='1'),
        'maxPassiveOps': max([f(r,'passiveOps') for r in handled] or [0.0]),
        'maxInvalidOps': max([f(r,'gpuInvalidOperations') for r in handled] or [0.0]),
    }

summary_keys=['nFluidParticles','totalMass','Px','Py','meanKinetic','kBTEstimate','meanN','stdN']
report=[]; passed=True
flat=[]
for mode in modes:
    cpu_dir=root/'cpu'/mode/'output'
    gpu_dir=root/'cuda'/mode/'output'
    cpu=read_summary(cpu_dir/'summary_runtime.csv')
    gpu=read_summary(gpu_dir/'summary_runtime.csv')
    deltas={k: abs(f(cpu,k)-f(gpu,k)) for k in summary_keys}
    max_delta=max(deltas.values() or [0.0])
    shadow=read_shadow_stats(gpu_dir/'cuda_resampling_pipeline_shadow_0445.csv')
    apply=read_apply_stats(gpu_dir/'cuda_resampling_pipeline_apply_0448.csv')
    ok=(shadow['failed']==0 and shadow['skipped']==0 and shadow['nonzero']>0 and
        apply['handled']>0 and apply['skipped']==0 and apply['maxInvalidOps']==0 and
        max_delta <= 1.0e-9)
    passed = passed and ok
    flat.append((mode, ok, max_delta, deltas, shadow, apply))

out=root/'apply_smoke_report_0448.md'
with out.open('w') as w:
    w.write('# 0448 CUDA resampling apply backend smoke\n\n')
    w.write('Scope: periodic nonzero-plan, CPU baseline vs experimental CUDA apply backend.\n\n')
    w.write(f'PASS-like modes: **{sum(1 for _,ok,_,_,_,_ in flat if ok)}/{len(flat)}**\n\n')
    w.write('| mode | pass | max summary delta | shadow handled/passive | apply handled/applied | max passiveOps | max invalidOps | maxAbsMass | maxAbsVx | maxAbsVy |\n')
    w.write('| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |\n')
    for mode,ok,max_delta,deltas,shadow,apply in flat:
        w.write(f"| {mode} | {1 if ok else 0} | {max_delta:.17g} | {shadow['handled']}/{shadow['nonzero']} | {apply['handled']}/{apply['appliedRows']} | {max(shadow['maxPassiveOps'], apply['maxPassiveOps']):.0f} | {apply['maxInvalidOps']:.0f} | {shadow['maxAbsMass']:.3e} | {shadow['maxAbsVx']:.3e} | {shadow['maxAbsVy']:.3e} |\n")
    w.write('\n## Summary deltas CPU baseline vs CUDA apply\n\n')
    for mode,ok,max_delta,deltas,shadow,apply in flat:
        w.write(f'### {mode}\n\n')
        for k,v in deltas.items():
            w.write(f'- {k}: `{v:.17g}`\n')
        w.write('\n')
print(out)
print(out.read_text())
if not passed:
    sys.exit(1)
PY
