#!/usr/bin/env bash
set -euo pipefail

BIN=${BIN:-build/src_mpcd_base_cuda_q6_resident_periodic_equiv_0451}
BASE_STRESS_ROOT=${BASE_STRESS_ROOT:-runs/0452_upstream_apply_gate_stress}
STEPS_LIST=${STEPS_LIST:-"20 100"}
SEEDS=${SEEDS:-"1628638 1628639 1628640"}
RUN_MODES=${RUN_MODES:-"src-resampling src-q6-resampling"}
SUMMARY_EVERY=${SUMMARY_EVERY:-1}
LIVE_VIS_ENABLE=${LIVE_VIS_ENABLE:-0}
FILTERED_RECORDING_ENABLE=${FILTERED_RECORDING_ENABLE:-0}

mkdir -p "$BASE_STRESS_ROOT"

if [[ ! -x "$BIN" ]]; then
  echo "[0452] ERROR: BIN is not executable: $BIN" >&2
  exit 2
fi
if [[ ! -x scripts/run_0451_upstream_apply_backend_smoke.sh ]]; then
  echo "[0452] ERROR: missing executable scripts/run_0451_upstream_apply_backend_smoke.sh" >&2
  exit 2
fi

for steps in $STEPS_LIST; do
  for seed in $SEEDS; do
    run_root="$BASE_STRESS_ROOT/steps_${steps}_seed_${seed}"
    echo "[0452] steps=$steps seed=$seed root=$run_root"
    BIN="$BIN" \
    BASE_UPSTREAM_APPLY_ROOT="$run_root" \
    STEPS="$steps" \
    SEED="$seed" \
    RNG_SEED="$seed" \
    INIT_SEED="$seed" \
    SUMMARY_EVERY="$SUMMARY_EVERY" \
    RUN_MODES="$RUN_MODES" \
    LIVE_VIS_ENABLE="$LIVE_VIS_ENABLE" \
    FILTERED_RECORDING_ENABLE="$FILTERED_RECORDING_ENABLE" \
    bash scripts/run_0451_upstream_apply_backend_smoke.sh
  done
done

python3 - "$BASE_STRESS_ROOT" <<'PY'
import csv, glob, math, os, pathlib, re, sys
root = pathlib.Path(sys.argv[1])
summary_paths = sorted(root.glob("**/upstream_apply_summary_0451.csv"))
if not summary_paths:
    print(f"[0452] ERROR: no upstream_apply_summary_0451.csv below {root}", file=sys.stderr)
    sys.exit(3)

def f(row, *names, default=0.0):
    for name in names:
        if name in row and row[name] not in (None, ""):
            try:
                return float(row[name])
            except Exception:
                pass
    return default

def s(row, *names, default=""):
    for name in names:
        if name in row and row[name] not in (None, ""):
            return str(row[name])
    return default

flat_rows = []
for path in summary_paths:
    text = str(path)
    m_steps = re.search(r"steps_(\d+)", text)
    m_seed = re.search(r"seed_(\d+)", text)
    steps = int(m_steps.group(1)) if m_steps else -1
    seed = int(m_seed.group(1)) if m_seed else -1
    with path.open(newline="") as fh:
        for row in csv.DictReader(fh):
            mode = s(row, "mode", "runMode", default="unknown")
            passed = f(row, "pass", "passed", "passLike")
            rows = f(row, "rows", "nRows")
            handled = f(row, "handled", "handledRows")
            applied = f(row, "applied", "appliedRows")
            pass_rows = f(row, "passRows", "passedRows", "upstreamPassed", "upstreamPass")
            cpu_pairs = f(row, "cpuTransferPairs", "maxCpuTransferPairs", "transferPairsCpu", "cpuPairs")
            gpu_pairs = f(row, "gpuTransferPairs", "maxGpuTransferPairs", "transferPairsGpu", "gpuPairs")
            passive_ops = f(row, "cpuPassiveOps", "maxCpuPassiveOps", "passiveOps", "maxPassiveOps")
            plan_mismatch = f(row, "planMismatch", "maxPlanMismatch")
            cell_mismatch = f(row, "cellIdMismatch", "maxCellIdMismatch")
            count_diff = f(row, "countDiff", "maxCountDiff")
            recv_mismatch = f(row, "receiverListMismatch", "maxReceiverListMismatch")
            donor_mismatch = f(row, "donorListMismatch", "maxDonorListMismatch")
            mass_abs = f(row, "maxMassAbs", "massAbs")
            px_abs = f(row, "maxPxAbs", "pxAbs")
            py_abs = f(row, "maxPyAbs", "pyAbs")
            plan_mass_abs = f(row, "maxPlanMassAbs", "planMassAbs")
            plan_distance_abs = f(row, "maxPlanDistanceAbs", "planDistanceAbs")
            planned_mass_delta = f(row, "maxPlannedMassDelta", "plannedMassDelta")
            summary_delta = f(row, "maxSummaryDelta", "summaryDelta")
            apply_pass = f(row, "applyPass", "apply pass", "apply_pass", default=passed)
            flat_rows.append({
                "steps": steps,
                "seed": seed,
                "mode": mode,
                "pass": int(passed),
                "rows": rows,
                "handled": handled,
                "applied": applied,
                "passRows": pass_rows,
                "cpuTransferPairs": cpu_pairs,
                "gpuTransferPairs": gpu_pairs,
                "cpuPassiveOps": passive_ops,
                "cellIdMismatch": cell_mismatch,
                "countDiff": count_diff,
                "receiverListMismatch": recv_mismatch,
                "donorListMismatch": donor_mismatch,
                "planMismatch": plan_mismatch,
                "maxMassAbs": mass_abs,
                "maxPxAbs": px_abs,
                "maxPyAbs": py_abs,
                "maxPlanMassAbs": plan_mass_abs,
                "maxPlanDistanceAbs": plan_distance_abs,
                "maxPlannedMassDelta": planned_mass_delta,
                "applyPass": int(apply_pass),
                "maxSummaryDelta": summary_delta,
            })

# Stable sort for readable report.
flat_rows.sort(key=lambda r: (r["steps"], r["seed"], r["mode"]))

flat_path = root / "upstream_apply_stress_summary_0452.csv"
fieldnames = [
    "steps", "seed", "mode", "pass", "rows", "handled", "applied", "passRows",
    "cpuTransferPairs", "gpuTransferPairs", "cpuPassiveOps",
    "cellIdMismatch", "countDiff", "receiverListMismatch", "donorListMismatch", "planMismatch",
    "maxMassAbs", "maxPxAbs", "maxPyAbs", "maxPlanMassAbs", "maxPlanDistanceAbs", "maxPlannedMassDelta",
    "applyPass", "maxSummaryDelta",
]
with flat_path.open("w", newline="") as fh:
    wr = csv.DictWriter(fh, fieldnames=fieldnames)
    wr.writeheader()
    wr.writerows(flat_rows)

def mx(name):
    return max((abs(float(r[name])) for r in flat_rows if r.get(name) not in (None, "")), default=0.0)

pass_like = sum(1 for r in flat_rows if int(r["pass"]) == 1 and int(r["applyPass"]) == 1)
total = len(flat_rows)

report = root / "upstream_apply_stress_report_0452.md"
with report.open("w") as out:
    out.write("# 0452 CUDA resampling upstream apply-gate stress\n\n")
    out.write("Scope: periodic nonzero-plan. CUDA upstream apply-gate is enabled for deposit/classification/poor-rich compaction/planner; CUDA apply remains authoritative for clean particle edits/remap/thermal. CPU baseline remains the reference for final summary comparison.\n\n")
    out.write(f"CSV rows summarized: **{total}**\n\n")
    out.write(f"PASS-like rows: **{pass_like}/{total}**\n\n")
    out.write("## Global maxima\n\n")
    maxima = [
        ("maxSummaryDelta", "maxSummaryDelta"),
        ("maxCpuTransferPairs", "cpuTransferPairs"),
        ("maxGpuTransferPairs", "gpuTransferPairs"),
        ("maxCpuPassiveOps", "cpuPassiveOps"),
        ("maxCellIdMismatch", "cellIdMismatch"),
        ("maxCountDiff", "countDiff"),
        ("maxReceiverListMismatch", "receiverListMismatch"),
        ("maxDonorListMismatch", "donorListMismatch"),
        ("maxPlanMismatch", "planMismatch"),
        ("maxMassAbs", "maxMassAbs"),
        ("maxPxAbs", "maxPxAbs"),
        ("maxPyAbs", "maxPyAbs"),
        ("maxPlanMassAbs", "maxPlanMassAbs"),
        ("maxPlanDistanceAbs", "maxPlanDistanceAbs"),
        ("maxPlannedMassDelta", "maxPlannedMassDelta"),
    ]
    for label, key in maxima:
        out.write(f"- {label}: `{mx(key)}`\n")
    out.write("\n## Per run\n\n")
    out.write("| steps | seed | mode | pass | max summary delta | handled/applied/pass | transfer pairs CPU/GPU | passive ops | planMismatch | maxMassAbs | maxPlanMassAbs | apply pass |\n")
    out.write("| ---: | ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |\n")
    for r in flat_rows:
        out.write(
            f"| {r['steps']} | {r['seed']} | {r['mode']} | {r['pass']} | {r['maxSummaryDelta']} | "
            f"{int(r['handled'])}/{int(r['applied'])}/{int(r['passRows']) if r['passRows'] else int(r['pass'])} | "
            f"{int(r['cpuTransferPairs'])}/{int(r['gpuTransferPairs'])} | {int(r['cpuPassiveOps'])} | "
            f"{int(r['planMismatch'])} | {r['maxMassAbs']:.3e} | {r['maxPlanMassAbs']:.3e} | {r['applyPass']} |\n"
        )
    out.write("\n")
    out.write(f"Flat CSV: `{flat_path}`\n")

print(report.read_text())
PY
