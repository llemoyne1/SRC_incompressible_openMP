#!/usr/bin/env bash
set -euo pipefail

# 0456: stress runner for the CUDA device-carrier path introduced in 0455.
# This script does not modify solver behavior; it repeatedly invokes the 0455 smoke runner
# over several seeds/step counts and aggregates the resulting flat CSV summaries.

ROOT="${BASE_STRESS_ROOT:-runs/0456_device_carrier_stress}"
STEPS_LIST="${STEPS_LIST:-20 100}"
SEEDS="${SEEDS:-1628638 1628639 1628640}"
RUN_MODES="${RUN_MODES:-src-resampling src-q6-resampling}"
SUMMARY_EVERY="${SUMMARY_EVERY:-1}"
BIN="${BIN:-build/src_mpcd_base_cuda_q6_resident_periodic_equiv_0455}"
LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-0}"
FILTERED_RECORDING_ENABLE="${FILTERED_RECORDING_ENABLE:-0}"
RUNNER_0455="${RUNNER_0455:-scripts/run_0455_device_carrier_smoke.sh}"

if [[ ! -x "$RUNNER_0455" ]]; then
  echo "[0456] ERROR: required runner is not executable: $RUNNER_0455" >&2
  echo "[0456] Hint: chmod +x scripts/run_0455_device_carrier_smoke.sh" >&2
  exit 2
fi

if [[ ! -x "$BIN" ]]; then
  echo "[0456] ERROR: binary not executable: $BIN" >&2
  exit 2
fi

rm -rf "$ROOT"
mkdir -p "$ROOT"

for steps in $STEPS_LIST; do
  for seed in $SEEDS; do
    case_root="$ROOT/steps_${steps}_seed_${seed}"
    echo "[0456] steps=$steps seed=$seed root=$case_root"
    BIN="$BIN" \
    BASE_DEVICE_CARRIER_ROOT="$case_root" \
    STEPS="$steps" \
    SEED="$seed" \
    SEEDS="$seed" \
    SUMMARY_EVERY="$SUMMARY_EVERY" \
    RUN_MODES="$RUN_MODES" \
    LIVE_VIS_ENABLE="$LIVE_VIS_ENABLE" \
    FILTERED_RECORDING_ENABLE="$FILTERED_RECORDING_ENABLE" \
    bash "$RUNNER_0455"
  done
done

python3 - "$ROOT" <<'PY'
import csv, re, sys
from pathlib import Path

root = Path(sys.argv[1])
summary_paths = sorted(root.glob("**/device_carrier_summary_0455.csv"))
if not summary_paths:
    raise SystemExit(f"[0456] ERROR: no device_carrier_summary_0455.csv found below {root}")

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
    m = re.search(r"steps_(\d+)_seed_(\d+)", str(path))
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
    raise SystemExit("[0456] ERROR: empty device-carrier summaries")

flat_path = root / "device_carrier_stress_summary_0456.csv"
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

def max_metric(*names):
    return max(abs(num(r, *names)) for r in records)

def max_raw(*names):
    return max(num(r, *names) for r in records)

pass_like = sum(1 for r in records if r["_pass"] == 1)
rows_total = len(records)

max_summary_delta = max_metric("maxSummaryDelta", "summaryDelta", "max_summary_delta")
max_cpu_ops = max_raw("maxCpuOps", "cpuOps", "opsCpu")
max_gpu_ops = max_raw("maxGpuOps", "gpuOps", "opsGpu")
max_invalid_materialize_ops = max_metric("maxInvalidMaterializeOps", "invalidMaterializeOps", "invalidMat")
max_op_mismatch = max_metric("maxOpMismatch", "opMismatch")
max_dup_mismatch = max_metric("maxDuplicateMismatch", "duplicateParticleMismatch", "dupMismatch", "duplicateMismatch")
max_extraction_applied = max_raw("maxExtractionApplied", "extractionApplied")
max_insertion_applied = max_raw("maxInsertionApplied", "insertionApplied")
max_invalid_apply_ops = max_metric("maxInvalidApplyOps", "invalidApplyOps")
max_mass_abs = max_metric("maxMassAbs", "massAbs")
max_px_abs = max_metric("maxPxAbs", "pxAbs")
max_py_abs = max_metric("maxPyAbs", "pyAbs")
max_mass_delta = max_metric("maxMassDelta", "massDelta")
max_px_delta = max_metric("maxPxDelta", "pxDelta")
max_py_delta = max_metric("maxPyDelta", "pyDelta")
max_ke_delta = max_metric("maxKeDelta", "keDelta")
apply_invalid_ops = max_metric("applyInvalidOps", "maxApplyInvalidOps")

per_rows = []
for r in sorted(records, key=lambda x: (x["steps"], x["seed"], x["mode"])):
    handled = int(round(num(r, "handled", default=0)))
    applied = int(round(num(r, "applied", default=0)))
    passed = int(round(num(r, "passed", default=r["_pass"])))
    cpu_ops = int(round(num(r, "maxCpuOps", "cpuOps", "opsCpu", default=0)))
    gpu_ops = int(round(num(r, "maxGpuOps", "gpuOps", "opsGpu", default=0)))
    extraction = int(round(num(r, "maxExtractionApplied", "extractionApplied", default=0)))
    insertion = int(round(num(r, "maxInsertionApplied", "insertionApplied", default=0)))
    op_mismatch = int(round(num(r, "maxOpMismatch", "opMismatch", default=0)))
    invalid_mat = int(round(num(r, "maxInvalidMaterializeOps", "invalidMaterializeOps", default=0)))
    invalid_apply = int(round(num(r, "maxInvalidApplyOps", "invalidApplyOps", default=0)))
    dup = int(round(num(r, "maxDuplicateMismatch", "duplicateParticleMismatch", "dupMismatch", default=0)))
    summary_delta = num(r, "maxSummaryDelta", "summaryDelta", default=0.0)
    apply_handled = int(round(num(r, "applyHandled", default=0)))
    apply_applied = int(round(num(r, "applyApplied", default=0)))
    per_rows.append((r["steps"], r["seed"], r["mode"], r["_pass"], handled, applied, passed, cpu_ops, gpu_ops, extraction, insertion, op_mismatch, invalid_mat, invalid_apply, dup, summary_delta, apply_handled, apply_applied))

report = root / "device_carrier_stress_report_0456.md"
with report.open("w") as f:
    f.write("# 0456 CUDA resampling device-carrier stress\n\n")
    f.write("Scope: periodic nonzero-plan. CUDA upstream apply-gate is enabled; donor-particle passive operations are materialized on device and consumed directly by the device-carrier particle-edit backend. A host mirror download is retained only for strict gate diagnostics.\n\n")
    f.write(f"CSV rows summarized: **{rows_total}**\n\n")
    f.write(f"PASS-like rows: **{pass_like}/{rows_total}**\n\n")
    f.write("## Global maxima\n\n")
    for name, value in [
        ("maxSummaryDelta", max_summary_delta),
        ("maxCpuOps", max_cpu_ops),
        ("maxGpuOps", max_gpu_ops),
        ("maxInvalidMaterializeOps", max_invalid_materialize_ops),
        ("maxOpMismatch", max_op_mismatch),
        ("maxDuplicateMismatch", max_dup_mismatch),
        ("maxExtractionApplied", max_extraction_applied),
        ("maxInsertionApplied", max_insertion_applied),
        ("maxInvalidApplyOps", max_invalid_apply_ops),
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
    f.write("| steps | seed | mode | pass | handled/applied/pass | ops CPU/GPU | extraction/insertion | opMismatch | invalidMat | invalidApply | dupMismatch | apply handled/applied | max summary delta |\n")
    f.write("| ---: | ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |\n")
    for steps, seed, mode, p, handled, applied, passed, cpu_ops, gpu_ops, extraction, insertion, op_mismatch, invalid_mat, invalid_apply, dup, summary_delta, apply_handled, apply_applied in per_rows:
        f.write(f"| {steps} | {seed} | {mode} | {p} | {handled}/{applied}/{passed} | {cpu_ops}/{gpu_ops} | {extraction}/{insertion} | {op_mismatch} | {invalid_mat} | {invalid_apply} | {dup} | {apply_handled}/{apply_applied} | {summary_delta} |\n")
    f.write("\n")
    f.write(f"Flat CSV: `{flat_path}`\n")

print(report.read_text())

failures = []
if pass_like != rows_total:
    failures.append(f"pass_like {pass_like}/{rows_total}")
if max_summary_delta > 1e-9:
    failures.append(f"maxSummaryDelta {max_summary_delta}")
for label, value in [
    ("maxInvalidMaterializeOps", max_invalid_materialize_ops),
    ("maxOpMismatch", max_op_mismatch),
    ("maxDuplicateMismatch", max_dup_mismatch),
    ("maxInvalidApplyOps", max_invalid_apply_ops),
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
if max_cpu_ops <= 0 or max_gpu_ops <= 0:
    failures.append("nonzero op coverage missing")
if abs(max_cpu_ops - max_gpu_ops) > 0:
    failures.append(f"cpu/gpu ops mismatch maxima {max_cpu_ops}/{max_gpu_ops}")
if abs(max_extraction_applied - max_gpu_ops) > 0 or abs(max_insertion_applied - max_gpu_ops) > 0:
    failures.append(f"device apply coverage mismatch extraction/insertion/gpuOps {max_extraction_applied}/{max_insertion_applied}/{max_gpu_ops}")
if failures:
    raise SystemExit("[0456] FAIL: " + "; ".join(failures))
PY
