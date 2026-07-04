#!/usr/bin/env bash
set -euo pipefail

# 0454: stress runner for the CUDA donor-particle operation materializer introduced in 0453.
# This script does not modify solver behavior; it repeatedly invokes the 0453 smoke runner
# over several seeds/step counts and aggregates the resulting flat CSV summaries.

ROOT="${BASE_STRESS_ROOT:-runs/0454_operation_materializer_stress}"
STEPS_LIST="${STEPS_LIST:-20 100}"
SEEDS="${SEEDS:-1628638 1628639 1628640}"
RUN_MODES="${RUN_MODES:-src-resampling src-q6-resampling}"
SUMMARY_EVERY="${SUMMARY_EVERY:-1}"
BIN="${BIN:-build/src_mpcd_base_cuda_q6_resident_periodic_equiv_0453}"
LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-0}"
FILTERED_RECORDING_ENABLE="${FILTERED_RECORDING_ENABLE:-0}"
RUNNER_0453="${RUNNER_0453:-scripts/run_0453_operation_materializer_smoke.sh}"

if [[ ! -x "$RUNNER_0453" ]]; then
  echo "[0454] ERROR: required runner is not executable: $RUNNER_0453" >&2
  echo "[0454] Hint: chmod +x scripts/run_0453_operation_materializer_smoke.sh" >&2
  exit 2
fi

if [[ ! -x "$BIN" ]]; then
  echo "[0454] ERROR: binary not executable: $BIN" >&2
  exit 2
fi

rm -rf "$ROOT"
mkdir -p "$ROOT"

for steps in $STEPS_LIST; do
  for seed in $SEEDS; do
    case_root="$ROOT/steps_${steps}_seed_${seed}"
    echo "[0454] steps=$steps seed=$seed root=$case_root"
    BIN="$BIN" \
    BASE_MATERIALIZE_ROOT="$case_root" \
    STEPS="$steps" \
    SEED="$seed" \
    SEEDS="$seed" \
    SUMMARY_EVERY="$SUMMARY_EVERY" \
    RUN_MODES="$RUN_MODES" \
    LIVE_VIS_ENABLE="$LIVE_VIS_ENABLE" \
    FILTERED_RECORDING_ENABLE="$FILTERED_RECORDING_ENABLE" \
    bash "$RUNNER_0453"
  done
done

python3 - "$ROOT" <<'PY'
import csv, glob, math, os, re, sys
from pathlib import Path

root = Path(sys.argv[1])
summary_paths = sorted(root.glob("**/operation_materializer_summary_0453.csv"))
if not summary_paths:
    raise SystemExit(f"[0454] ERROR: no operation_materializer_summary_0453.csv found below {root}")

def first(row, names, default=""):
    for n in names:
        if n in row and row[n] not in (None, ""):
            return row[n]
    return default

def num(row, *names, default=0.0):
    v = first(row, names, "")
    try:
        return float(v)
    except Exception:
        return default

def infer_steps_seed(path: Path):
    s = str(path)
    m = re.search(r"steps_(\d+)_seed_(\d+)", s)
    if m:
        return int(m.group(1)), int(m.group(2))
    return -1, -1

records = []
for p in summary_paths:
    steps, seed = infer_steps_seed(p)
    with p.open(newline="") as f:
        for row in csv.DictReader(f):
            mode = first(row, ["mode", "runMode", "caseMode"], "unknown")
            pass_value = int(round(num(row, "pass", "passed", "modePass", "ok", default=0.0)))
            records.append({"path": str(p), "steps": steps, "seed": seed, "mode": mode, **row, "_pass": pass_value})

if not records:
    raise SystemExit("[0454] ERROR: empty materializer summaries")

flat_path = root / "operation_materializer_stress_summary_0454.csv"
base_fields = ["steps", "seed", "mode", "source_csv"]
all_fields = []
for r in records:
    for k in r.keys():
        if k.startswith("_") or k in ("path", "steps", "seed", "mode"):
            continue
        if k not in all_fields:
            all_fields.append(k)
with flat_path.open("w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=base_fields + all_fields)
    w.writeheader()
    for r in records:
        out = {"steps": r["steps"], "seed": r["seed"], "mode": r["mode"], "source_csv": r["path"]}
        out.update({k: r.get(k, "") for k in all_fields})
        w.writerow(out)

# Robust metric extraction across plausible 0453 summary schemas.
def max_metric(*names):
    return max(abs(num(r, *names)) for r in records)

def min_metric(*names):
    return min(num(r, *names) for r in records)

pass_like = sum(1 for r in records if r["_pass"] == 1)
rows_total = len(records)

max_summary_delta = max_metric("maxSummaryDelta", "summaryDelta", "max_summary_delta")
max_plan_entries = max_metric("planEntries", "maxPlanEntries", "plan entries")
max_cpu_ops = max_metric("cpuOps", "maxCpuOps", "opsCpu", "cpuPassiveOps")
max_gpu_ops = max_metric("gpuOps", "maxGpuOps", "opsGpu", "gpuPassiveOps")
max_invalid_ops = max_metric("invalidOps", "maxInvalidOps")
max_op_mismatch = max_metric("opMismatch", "maxOpMismatch")
max_dup_mismatch = max_metric("duplicateMismatch", "dupMismatch", "maxDuplicateMismatch")
max_mass_abs = max_metric("maxMassAbs", "massAbs")
max_px_abs = max_metric("maxPxAbs", "pxAbs")
max_py_abs = max_metric("maxPyAbs", "pyAbs")
max_mass_delta = max_metric("maxMassDelta", "massDelta")
max_px_delta = max_metric("maxPxDelta", "pxDelta")
max_py_delta = max_metric("maxPyDelta", "pyDelta")
max_ke_delta = max_metric("maxKeDelta", "keDelta")
apply_invalid_ops = max_metric("applyInvalidOps", "maxApplyInvalidOps")

# Per-run compact rows.
per_rows = []
for r in sorted(records, key=lambda x: (x["steps"], x["seed"], x["mode"])):
    handled = int(round(num(r, "handled", "materializerHandled", "rows", default=0)))
    applied = int(round(num(r, "applied", "materializerApplied", default=0)))
    passed = int(round(num(r, "passed", "passRows", "materializerPassed", "pass", default=r["_pass"])))
    plan = int(round(num(r, "planEntries", "maxPlanEntries", default=0)))
    cpu_ops = int(round(num(r, "cpuOps", "maxCpuOps", "opsCpu", default=0)))
    gpu_ops = int(round(num(r, "gpuOps", "maxGpuOps", "opsGpu", default=0)))
    op_mismatch = int(round(num(r, "opMismatch", "maxOpMismatch", default=0)))
    invalid = int(round(num(r, "invalidOps", "maxInvalidOps", default=0)))
    dup = int(round(num(r, "duplicateMismatch", "dupMismatch", "maxDuplicateMismatch", default=0)))
    summary_delta = num(r, "maxSummaryDelta", "summaryDelta", default=0.0)
    apply_handled = int(round(num(r, "applyHandled", "apply handled", default=0)))
    apply_applied = int(round(num(r, "applyApplied", "apply applied", default=0)))
    per_rows.append((r["steps"], r["seed"], r["mode"], r["_pass"], handled, applied, passed, plan, cpu_ops, gpu_ops, op_mismatch, invalid, dup, summary_delta, apply_handled, apply_applied))

report = root / "operation_materializer_stress_report_0454.md"
with report.open("w") as f:
    f.write("# 0454 CUDA resampling operation materializer stress\n\n")
    f.write("Scope: periodic nonzero-plan. CUDA materializes donor-particle passive extraction/insertion operations from the accepted transfer plan. CPU remains the strict reference gate; on PASS, the compact operation vector consumed by the 0448 CUDA apply backend is replaced by the CUDA-materialized vector.\n\n")
    f.write(f"CSV rows summarized: **{rows_total}**\n\n")
    f.write(f"PASS-like rows: **{pass_like}/{rows_total}**\n\n")
    f.write("## Global maxima\n\n")
    for name, value in [
        ("maxSummaryDelta", max_summary_delta),
        ("maxPlanEntries", max_plan_entries),
        ("maxCpuOps", max_cpu_ops),
        ("maxGpuOps", max_gpu_ops),
        ("maxInvalidOps", max_invalid_ops),
        ("maxOpMismatch", max_op_mismatch),
        ("maxDuplicateMismatch", max_dup_mismatch),
        ("maxMassAbs", max_mass_abs),
        ("maxPxAbs", max_px_abs),
        ("maxPyAbs", max_py_abs),
        ("maxMassDelta", max_mass_delta),
        ("maxPxDelta", max_px_delta),
        ("maxPyDelta", max_py_delta),
        ("maxKeDelta", max_ke_delta),
        ("applyInvalidOps", apply_invalid_ops),
    ]:
        f.write(f"- {name}: `{value}`\n")
    f.write("\n## Per run\n\n")
    f.write("| steps | seed | mode | pass | handled/applied/pass | plan entries | ops CPU/GPU | opMismatch | invalidOps | dupMismatch | apply handled/applied | max summary delta |\n")
    f.write("| ---: | ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |\n")
    for steps, seed, mode, p, handled, applied, passed, plan, cpu_ops, gpu_ops, op_mismatch, invalid, dup, summary_delta, apply_handled, apply_applied in per_rows:
        f.write(f"| {steps} | {seed} | {mode} | {p} | {handled}/{applied}/{passed} | {plan} | {cpu_ops}/{gpu_ops} | {op_mismatch} | {invalid} | {dup} | {apply_handled}/{apply_applied} | {summary_delta} |\n")
    f.write("\n")
    f.write(f"Flat CSV: `{flat_path}`\n")

print(report.read_text())

# Strict pass gate matching the report criteria.
failures = []
if pass_like != rows_total:
    failures.append(f"pass_like {pass_like}/{rows_total}")
if max_summary_delta > 1e-9:
    failures.append(f"maxSummaryDelta {max_summary_delta}")
for label, value in [
    ("maxInvalidOps", max_invalid_ops),
    ("maxOpMismatch", max_op_mismatch),
    ("maxDuplicateMismatch", max_dup_mismatch),
    ("maxMassAbs", max_mass_abs),
    ("maxPxAbs", max_px_abs),
    ("maxPyAbs", max_py_abs),
    ("maxMassDelta", max_mass_delta),
    ("maxPxDelta", max_px_delta),
    ("maxPyDelta", max_py_delta),
    ("applyInvalidOps", apply_invalid_ops),
]:
    if value != 0.0:
        failures.append(f"{label} {value}")
if max_cpu_ops <= 0 or max_gpu_ops <= 0 or max_plan_entries <= 0:
    failures.append("nonzero plan/op coverage missing")
if abs(max_cpu_ops - max_gpu_ops) > 0:
    failures.append(f"cpu/gpu ops mismatch maxima {max_cpu_ops}/{max_gpu_ops}")
if failures:
    raise SystemExit("[0454] FAIL: " + "; ".join(failures))
PY
