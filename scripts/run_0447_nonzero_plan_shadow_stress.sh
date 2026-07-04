#!/usr/bin/env bash
set -euo pipefail

# 0447: stress wrapper for the 0446 in-solver CUDA resampling shadow hook.
# This script intentionally does not modify solver physics. It repeatedly runs
# the existing periodic nonzero-plan smoke on several seeds/step counts and
# aggregates cuda_resampling_pipeline_shadow_0445.csv diagnostics.

: "${BIN:=build/src_mpcd_base_cuda_q6_resident_periodic_equiv_0446}"
: "${BASE_STRESS_ROOT:=runs/0447_nonzero_plan_shadow_stress}"
: "${STEPS_LIST:=20 100}"
: "${SEEDS:=1628638 1628639 1628640}"
: "${RUN_MODES:=src-resampling src-q6-resampling}"
: "${SUMMARY_EVERY:=1}"
: "${LIVE_VIS_ENABLE:=0}"
: "${FILTERED_RECORDING_ENABLE:=0}"

mkdir -p "${BASE_STRESS_ROOT}"

summary_csv="${BASE_STRESS_ROOT}/shadow_stress_summary_0447.csv"
report_md="${BASE_STRESS_ROOT}/shadow_stress_report_0447.md"

echo "case,steps,seed,mode,rows,attempted,handled,passed,failed,skipped,nonzeroPassiveRows,maxPassiveOps,maxRoleMismatch,maxTypeMismatch,maxBadPrefixCpu,maxBadPrefixGpu,maxAbsX,maxAbsY,maxAbsMass,maxAbsVx,maxAbsVy,maxMassDelta,maxPxDelta,maxPyDelta,maxKeDelta,csvPath" > "${summary_csv}"

for steps in ${STEPS_LIST}; do
  for seed in ${SEEDS}; do
    run_root="${BASE_STRESS_ROOT}/nonzero_plan_s${steps}_seed${seed}"
    echo "[0447] running steps=${steps} seed=${seed} root=${run_root}"
    BIN="${BIN}" \
    BASE_RUN_ROOT="${run_root}" \
    STEPS="${steps}" \
    SEED="${seed}" \
    SUMMARY_EVERY="${SUMMARY_EVERY}" \
    RUN_MODES="${RUN_MODES}" \
    LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE}" \
    FILTERED_RECORDING_ENABLE="${FILTERED_RECORDING_ENABLE}" \
    bash scripts/run_0446_periodic_nonzero_plan_shadow_smoke.sh
  done
done

python3 - <<'PY' "${BASE_STRESS_ROOT}" "${summary_csv}" "${report_md}"
import csv, glob, os, sys, math
from pathlib import Path

root = Path(sys.argv[1])
summary_csv = Path(sys.argv[2])
report_md = Path(sys.argv[3])

rows_out = []

def num(r, k):
    try:
        return float(r.get(k, "0") or 0)
    except Exception:
        return 0.0

for path_s in sorted(glob.glob(str(root / "**" / "cuda_resampling_pipeline_shadow_0445.csv"), recursive=True)):
    path = Path(path_s)
    rows = list(csv.DictReader(path.open(newline="")))
    if not rows:
        continue
    parts = path.parts
    mode = "unknown"
    seed = ""
    steps = ""
    for p in parts:
        if p in ("src-resampling", "src-q6-resampling"):
            mode = p
        if p.startswith("nonzero_plan_s") and "_seed" in p:
            prefix, seed_part = p.split("_seed", 1)
            steps = prefix.replace("nonzero_plan_s", "")
            seed = seed_part
    handled = [r for r in rows if int(num(r, "handled")) == 1]
    failed = [r for r in handled if int(num(r, "pass")) != 1]
    skipped = [r for r in rows if int(num(r, "skipped")) == 1]
    nonzero = [r for r in handled if num(r, "passiveOps") > 0]
    def max_abs(col):
        vals = [abs(num(r, col)) for r in handled if col in r]
        return max(vals) if vals else 0.0
    def max_delta(a, b):
        vals = [abs(num(r, a) - num(r, b)) for r in handled if a in r and b in r]
        return max(vals) if vals else 0.0
    out = {
        "case": "periodic_nonzero_plan_0446",
        "steps": steps,
        "seed": seed,
        "mode": mode,
        "rows": len(rows),
        "attempted": sum(int(num(r, "attempted")) for r in rows),
        "handled": len(handled),
        "passed": sum(int(num(r, "pass")) for r in handled),
        "failed": len(failed),
        "skipped": len(skipped),
        "nonzeroPassiveRows": len(nonzero),
        "maxPassiveOps": max([num(r, "passiveOps") for r in nonzero] or [0]),
        "maxRoleMismatch": max_abs("roleMismatch"),
        "maxTypeMismatch": max_abs("typeMismatch"),
        "maxBadPrefixCpu": max_abs("badPrefixCpu"),
        "maxBadPrefixGpu": max_abs("badPrefixGpu"),
        "maxAbsX": max_abs("maxAbsX"),
        "maxAbsY": max_abs("maxAbsY"),
        "maxAbsMass": max_abs("maxAbsMass"),
        "maxAbsVx": max_abs("maxAbsVx"),
        "maxAbsVy": max_abs("maxAbsVy"),
        "maxMassDelta": max_delta("massCpu", "massGpu"),
        "maxPxDelta": max_delta("pxCpu", "pxGpu"),
        "maxPyDelta": max_delta("pyCpu", "pyGpu"),
        "maxKeDelta": max_delta("keCpu", "keGpu"),
        "csvPath": str(path),
    }
    rows_out.append(out)

fieldnames = ["case","steps","seed","mode","rows","attempted","handled","passed","failed","skipped","nonzeroPassiveRows","maxPassiveOps","maxRoleMismatch","maxTypeMismatch","maxBadPrefixCpu","maxBadPrefixGpu","maxAbsX","maxAbsY","maxAbsMass","maxAbsVx","maxAbsVy","maxMassDelta","maxPxDelta","maxPyDelta","maxKeDelta","csvPath"]
with summary_csv.open("a", newline="") as f:
    w = csv.DictWriter(f, fieldnames=fieldnames)
    for r in rows_out:
        w.writerow(r)

total = len(rows_out)
pass_rows = sum(1 for r in rows_out if r["failed"] == 0 and r["skipped"] == 0 and r["handled"] == r["passed"] and r["nonzeroPassiveRows"] > 0)
max_passive = max([r["maxPassiveOps"] for r in rows_out] or [0])
max_role = max([r["maxRoleMismatch"] for r in rows_out] or [0])
max_type = max([r["maxTypeMismatch"] for r in rows_out] or [0])
max_bad_cpu = max([r["maxBadPrefixCpu"] for r in rows_out] or [0])
max_bad_gpu = max([r["maxBadPrefixGpu"] for r in rows_out] or [0])
max_mass = max([r["maxAbsMass"] for r in rows_out] or [0])
max_vx = max([r["maxAbsVx"] for r in rows_out] or [0])
max_vy = max([r["maxAbsVy"] for r in rows_out] or [0])

with report_md.open("w") as f:
    f.write("# 0447 nonzero-plan CUDA resampling shadow stress\n\n")
    f.write("Scope: periodic, wall-free, no chi/Darcy, no inlet/outlet. CPU remains authoritative; CUDA is shadow only.\n\n")
    f.write(f"CSV rows summarized: **{total}**\n\n")
    f.write(f"PASS-like rows: **{pass_rows}/{total}**\n\n")
    f.write("## Global maxima\n\n")
    f.write(f"- maxPassiveOps: `{max_passive}`\n")
    f.write(f"- maxRoleMismatch: `{max_role}`\n")
    f.write(f"- maxTypeMismatch: `{max_type}`\n")
    f.write(f"- maxBadPrefixCpu/Gpu: `{max_bad_cpu}` / `{max_bad_gpu}`\n")
    f.write(f"- maxAbsMass: `{max_mass}`\n")
    f.write(f"- maxAbsVx/Vy: `{max_vx}` / `{max_vy}`\n\n")
    f.write("## Per run\n\n")
    f.write("| steps | seed | mode | handled | passed | failed | skipped | nonzeroPassiveRows | maxPassiveOps | maxAbsMass | maxAbsVx | maxAbsVy |\n")
    f.write("| ---: | ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |\n")
    for r in rows_out:
        f.write(f"| {r['steps']} | {r['seed']} | {r['mode']} | {r['handled']} | {r['passed']} | {r['failed']} | {r['skipped']} | {r['nonzeroPassiveRows']} | {r['maxPassiveOps']} | {r['maxAbsMass']} | {r['maxAbsVx']} | {r['maxAbsVy']} |\n")
    f.write(f"\nFlat CSV: `{summary_csv}`\n")

print(report_md)
PY

cat "${report_md}"
