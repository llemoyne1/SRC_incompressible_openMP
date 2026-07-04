#!/usr/bin/env bash
set -euo pipefail

# 0449: stress wrapper for the experimental CUDA apply backend introduced in 0448.
# It repeatedly compares CPU-authoritative baseline runs against CUDA-apply runs
# on periodic nonzero-plan synthetic cases. The goal is to validate the first
# production-mutating CUDA resampling backend before extending it beyond the
# clean periodic/nonzero-plan regime.

: "${BIN:=build/src_mpcd_base_cuda_q6_resident_periodic_equiv_0448}"
: "${BASE_STRESS_ROOT:=runs/0449_apply_backend_stress}"
: "${STEPS_LIST:=20 100}"
: "${SEEDS:=1628638 1628639 1628640}"
: "${RUN_MODES:=src-resampling src-q6-resampling}"
: "${SUMMARY_EVERY:=1}"
: "${LIVE_VIS_ENABLE:=0}"
: "${FILTERED_RECORDING_ENABLE:=0}"
: "${MAX_SUMMARY_DELTA_TOL:=1e-9}"

mkdir -p "${BASE_STRESS_ROOT}"

for steps in ${STEPS_LIST}; do
  for seed in ${SEEDS}; do
    run_root="${BASE_STRESS_ROOT}/apply_s${steps}_seed${seed}"
    echo "[0449] running apply stress steps=${steps} seed=${seed} root=${run_root}"
    BIN="${BIN}" \
    BASE_APPLY_ROOT="${run_root}" \
    STEPS="${steps}" \
    SUMMARY_EVERY="${SUMMARY_EVERY}" \
    SEED="${seed}" \
    RUN_MODES="${RUN_MODES}" \
    LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE}" \
    FILTERED_RECORDING_ENABLE="${FILTERED_RECORDING_ENABLE}" \
    bash scripts/run_0448_periodic_nonzero_plan_apply_smoke.sh
  done
done

summary_csv="${BASE_STRESS_ROOT}/apply_stress_summary_0449.csv"
report_md="${BASE_STRESS_ROOT}/apply_stress_report_0449.md"

python3 - <<'PY' "${BASE_STRESS_ROOT}" "${summary_csv}" "${report_md}" "${MAX_SUMMARY_DELTA_TOL}"
import csv, glob, math, os, sys
from pathlib import Path

root = Path(sys.argv[1])
summary_csv = Path(sys.argv[2])
report_md = Path(sys.argv[3])
tol = float(sys.argv[4])
summary_keys = ['nFluidParticles','totalMass','Px','Py','meanKinetic','kBTEstimate','meanN','stdN']


def num(r, k):
    try:
        return float(r.get(k, '0') or 0)
    except Exception:
        return 0.0


def read_last_csv(path):
    with path.open(newline='') as f:
        rows = list(csv.DictReader(f))
    if not rows:
        raise RuntimeError(f'empty CSV: {path}')
    return rows[-1]


def read_rows(path):
    if not path.exists():
        return []
    with path.open(newline='') as f:
        return list(csv.DictReader(f))


def shadow_stats(path):
    rows = read_rows(path)
    handled = [r for r in rows if int(num(r, 'handled')) == 1]
    failed = [r for r in handled if int(num(r, 'pass')) != 1]
    skipped = [r for r in rows if int(num(r, 'skipped')) == 1]
    nonzero = [r for r in handled if num(r, 'passiveOps') > 0]
    def max_abs(col):
        vals = [abs(num(r, col)) for r in handled if col in r]
        return max(vals) if vals else 0.0
    def max_delta(a, b):
        vals = [abs(num(r, a) - num(r, b)) for r in handled if a in r and b in r]
        return max(vals) if vals else 0.0
    return {
        'rows': len(rows),
        'handled': len(handled),
        'passed': sum(1 for r in handled if int(num(r, 'pass')) == 1),
        'failed': len(failed),
        'skipped': len(skipped),
        'nonzeroPassiveRows': len(nonzero),
        'maxPassiveOps': max([num(r, 'passiveOps') for r in nonzero] or [0.0]),
        'maxRoleMismatch': max_abs('roleMismatch'),
        'maxTypeMismatch': max_abs('typeMismatch'),
        'maxBadPrefixCpu': max_abs('badPrefixCpu'),
        'maxBadPrefixGpu': max_abs('badPrefixGpu'),
        'maxAbsX': max_abs('maxAbsX'),
        'maxAbsY': max_abs('maxAbsY'),
        'maxAbsMass': max_abs('maxAbsMass'),
        'maxAbsVx': max_abs('maxAbsVx'),
        'maxAbsVy': max_abs('maxAbsVy'),
        'maxMassDelta': max_delta('massCpu', 'massGpu'),
        'maxPxDelta': max_delta('pxCpu', 'pxGpu'),
        'maxPyDelta': max_delta('pyCpu', 'pyGpu'),
        'maxKeDelta': max_delta('keCpu', 'keGpu'),
    }


def apply_stats(path):
    rows = read_rows(path)
    handled = [r for r in rows if int(num(r, 'handled')) == 1]
    skipped = [r for r in rows if int(num(r, 'skipped')) == 1]
    applied = [r for r in handled if int(num(r, 'applied')) == 1]
    return {
        'rows': len(rows),
        'handled': len(handled),
        'appliedRows': len(applied),
        'skipped': len(skipped),
        'maxPassiveOps': max([num(r, 'passiveOps') for r in handled] or [0.0]),
        'maxInvalidOps': max([num(r, 'gpuInvalidOperations') for r in handled] or [0.0]),
    }

rows_out = []
for cuda_summary_s in sorted(glob.glob(str(root / 'apply_s*_seed*' / 'cuda' / '*' / 'output' / 'summary_runtime.csv'))):
    cuda_summary = Path(cuda_summary_s)
    mode = cuda_summary.parts[-3]
    run_dir_name = cuda_summary.parts[-6] if len(cuda_summary.parts) >= 6 else ''
    # Example: apply_s100_seed1628638
    steps = ''
    seed = ''
    for part in cuda_summary.parts:
        if part.startswith('apply_s') and '_seed' in part:
            head, seed = part.split('_seed', 1)
            steps = head.replace('apply_s', '')
            break
    cpu_summary = root / f'apply_s{steps}_seed{seed}' / 'cpu' / mode / 'output' / 'summary_runtime.csv'
    if not cpu_summary.exists():
        continue
    cpu_last = read_last_csv(cpu_summary)
    cuda_last = read_last_csv(cuda_summary)
    deltas = {k: abs(num(cpu_last, k) - num(cuda_last, k)) for k in summary_keys}
    max_summary_delta = max(deltas.values() or [0.0])
    shadow = shadow_stats(cuda_summary.parent / 'cuda_resampling_pipeline_shadow_0445.csv')
    apply = apply_stats(cuda_summary.parent / 'cuda_resampling_pipeline_apply_0448.csv')
    ok = (
        max_summary_delta <= tol and
        shadow['failed'] == 0 and shadow['skipped'] == 0 and shadow['nonzeroPassiveRows'] > 0 and
        shadow['handled'] == shadow['passed'] and
        apply['handled'] > 0 and apply['appliedRows'] == apply['handled'] and apply['skipped'] == 0 and
        apply['maxInvalidOps'] == 0 and
        shadow['maxRoleMismatch'] == 0 and shadow['maxTypeMismatch'] == 0 and
        shadow['maxBadPrefixCpu'] == 0 and shadow['maxBadPrefixGpu'] == 0 and
        shadow['maxAbsMass'] <= 1e-14 and shadow['maxAbsVx'] <= 1e-12 and shadow['maxAbsVy'] <= 1e-12
    )
    out = {
        'case': 'periodic_nonzero_plan_0446',
        'steps': steps,
        'seed': seed,
        'mode': mode,
        'pass': int(ok),
        'maxSummaryDelta': max_summary_delta,
        'deltaNFluid': deltas['nFluidParticles'],
        'deltaMass': deltas['totalMass'],
        'deltaPx': deltas['Px'],
        'deltaPy': deltas['Py'],
        'deltaKE': deltas['meanKinetic'],
        'deltaKBT': deltas['kBTEstimate'],
        'deltaMeanN': deltas['meanN'],
        'deltaStdN': deltas['stdN'],
        'shadowRows': shadow['rows'],
        'shadowHandled': shadow['handled'],
        'shadowPassed': shadow['passed'],
        'shadowFailed': shadow['failed'],
        'shadowSkipped': shadow['skipped'],
        'nonzeroPassiveRows': shadow['nonzeroPassiveRows'],
        'applyRows': apply['rows'],
        'applyHandled': apply['handled'],
        'applyAppliedRows': apply['appliedRows'],
        'applySkipped': apply['skipped'],
        'maxPassiveOps': max(shadow['maxPassiveOps'], apply['maxPassiveOps']),
        'maxInvalidOps': apply['maxInvalidOps'],
        'maxRoleMismatch': shadow['maxRoleMismatch'],
        'maxTypeMismatch': shadow['maxTypeMismatch'],
        'maxBadPrefixCpu': shadow['maxBadPrefixCpu'],
        'maxBadPrefixGpu': shadow['maxBadPrefixGpu'],
        'maxAbsMass': shadow['maxAbsMass'],
        'maxAbsVx': shadow['maxAbsVx'],
        'maxAbsVy': shadow['maxAbsVy'],
        'cudaSummaryCsv': str(cuda_summary),
    }
    rows_out.append(out)

fieldnames = ['case','steps','seed','mode','pass','maxSummaryDelta','deltaNFluid','deltaMass','deltaPx','deltaPy','deltaKE','deltaKBT','deltaMeanN','deltaStdN','shadowRows','shadowHandled','shadowPassed','shadowFailed','shadowSkipped','nonzeroPassiveRows','applyRows','applyHandled','applyAppliedRows','applySkipped','maxPassiveOps','maxInvalidOps','maxRoleMismatch','maxTypeMismatch','maxBadPrefixCpu','maxBadPrefixGpu','maxAbsMass','maxAbsVx','maxAbsVy','cudaSummaryCsv']
with summary_csv.open('w', newline='') as f:
    w = csv.DictWriter(f, fieldnames=fieldnames)
    w.writeheader()
    for r in rows_out:
        w.writerow(r)

total = len(rows_out)
pass_rows = sum(r['pass'] for r in rows_out)
def max_of(k):
    return max([float(r[k]) for r in rows_out] or [0.0])

with report_md.open('w') as f:
    f.write('# 0449 CUDA resampling apply backend stress\n\n')
    f.write('Scope: periodic nonzero-plan, CPU baseline vs experimental CUDA apply backend. CUDA is authoritative for clean extraction/insertion + remap + thermal; CPU still provides deposit/planner/orchestration.\n\n')
    f.write(f'CSV rows summarized: **{total}**\n\n')
    f.write(f'PASS-like rows: **{pass_rows}/{total}**\n\n')
    f.write('## Global maxima\n\n')
    for key in ['maxSummaryDelta','maxPassiveOps','maxInvalidOps','maxRoleMismatch','maxTypeMismatch','maxBadPrefixCpu','maxBadPrefixGpu','maxAbsMass','maxAbsVx','maxAbsVy']:
        f.write(f'- {key}: `{max_of(key)}`\n')
    f.write('\n## Per run\n\n')
    f.write('| steps | seed | mode | pass | max summary delta | shadow handled/pass | apply handled/applied | nonzero passive rows | max passiveOps | invalidOps | maxAbsMass | maxAbsVx | maxAbsVy |\n')
    f.write('| ---: | ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |\n')
    for r in rows_out:
        f.write(f"| {r['steps']} | {r['seed']} | {r['mode']} | {r['pass']} | {r['maxSummaryDelta']:.17g} | {r['shadowHandled']}/{r['shadowPassed']} | {r['applyHandled']}/{r['applyAppliedRows']} | {r['nonzeroPassiveRows']} | {r['maxPassiveOps']} | {r['maxInvalidOps']} | {r['maxAbsMass']} | {r['maxAbsVx']} | {r['maxAbsVy']} |\n")
    f.write(f"\nFlat CSV: `{summary_csv}`\n")

print(report_md)
print(report_md.read_text())
if pass_rows != total or total == 0:
    sys.exit(1)
PY

cat "${report_md}"
