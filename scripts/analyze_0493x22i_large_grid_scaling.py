#!/usr/bin/env python3
import csv
import math
import statistics
import sys
from pathlib import Path

root = Path(sys.argv[1])
out_txt = Path(sys.argv[2])
out_csv = Path(sys.argv[3])


def profile_total(path):
    rows = list(csv.DictReader(path.open()))
    for r in rows:
        if r.get("phase") == "total_profiled":
            return float(r["ms_per_step"])
    raise RuntimeError(f"total_profiled missing in {path}")


def q6_value(path, group, phase):
    rows = list(csv.DictReader(path.open()))
    for r in rows:
        if r.get("group") == group and r.get("phase") == phase:
            return float(r["ms_per_q6_step"])
    return float("nan")


def final_summary(path):
    rows = list(csv.DictReader(path.open()))
    if not rows:
        raise RuntimeError(f"empty summary {path}")
    r = rows[-1]
    def f(name, default="nan"):
        try: return float(r.get(name, default))
        except Exception: return float("nan")
    return {
        "q6_converged": f("q6Converged", "0"),
        "q6_iterations": f("q6Iterations", "0"),
        "q6_residual": f("q6ResidualRel"),
        "wall_final_s": f("wallTime"),
    }


def read_elapsed(path):
    try:
        return float(path.read_text().strip())
    except Exception:
        return float("nan")

records = []
for ndir in sorted(root.glob("outputs/N*")):
    # output directory naming: N{N}_{variant}
    name = ndir.name
    if not name.startswith("N") or "_" not in name:
        continue
    nstr, variant = name[1:].split("_", 1)
    try: n = int(nstr)
    except ValueError: continue
    phase = ndir / "phase_profile_0163.csv"
    summary = ndir / "summary_runtime.csv"
    if not phase.exists() or not summary.exists():
        continue
    rec = {
        "N": n,
        "cells": n*n,
        "variant": variant,
        "profile_ms_per_step": profile_total(phase),
    }
    rec.update(final_summary(summary))
    if variant == "Q6GF_PROD_X7J":
        q6p = ndir / "q6_cg_profile_0163.csv"
        rec["q6_adapter_ms_per_step"] = q6_value(q6p, "q6_adapter", "total_q6_adapter") if q6p.exists() else float("nan")
        rec["elliptic_profile_ms_per_step"] = q6_value(q6p, "elliptic_cg", "total_elliptic_cg") if q6p.exists() else float("nan")
    else:
        rec["q6_adapter_ms_per_step"] = 0.0
        rec["elliptic_profile_ms_per_step"] = 0.0
    tf = root / "logs" / f"N{n}_{variant}.time"
    rec["process_elapsed_s"] = read_elapsed(tf)
    records.append(rec)

by = {}
for r in records:
    by.setdefault(r["N"], {})[r["variant"]] = r

out = []
for n in sorted(by):
    d = by[n]
    if "SRC_PROD" not in d or "Q6GF_PROD_X7J" not in d:
        continue
    s = d["SRC_PROD"]
    q = d["Q6GF_PROD_X7J"]
    ratio = q["profile_ms_per_step"] / s["profile_ms_per_step"]
    out.append({
        "N": n,
        "cells": n*n,
        "SRC_profile_ms_per_step": s["profile_ms_per_step"],
        "Q6GF_profile_ms_per_step": q["profile_ms_per_step"],
        "increment_profile_ms_per_step": q["profile_ms_per_step"] - s["profile_ms_per_step"],
        "profile_ratio": ratio,
        "profile_overhead_percent": (ratio - 1.0) * 100.0,
        "Q6_adapter_ms_per_step": q["q6_adapter_ms_per_step"],
        "elliptic_profile_ms_per_step": q["elliptic_profile_ms_per_step"],
        "Q6_converged_final": int(round(q["q6_converged"])),
        "Q6_iterations_final": int(round(q["q6_iterations"])),
        "Q6_residual_final": q["q6_residual"],
        "SRC_process_elapsed_s": s["process_elapsed_s"],
        "Q6GF_process_elapsed_s": q["process_elapsed_s"],
    })

if not out:
    raise SystemExit("[0493x22i] no complete SRC/Q6GF large-grid pair found")

with out_csv.open("w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=list(out[0]))
    w.writeheader(); w.writerows(out)


def log_slope(key):
    pts = [(math.log(float(r["N"])), math.log(float(r[key]))) for r in out if float(r[key]) > 0]
    if len(pts) < 2: return float("nan")
    xm = statistics.mean(x for x,_ in pts); ym = statistics.mean(y for _,y in pts)
    den = sum((x-xm)**2 for x,_ in pts)
    return sum((x-xm)*(y-ym) for x,y in pts)/den if den else float("nan")

lines = ["===== 0493x22i LARGE-GRID SRC vs Q6-G-F SCALING ====="]
for r in out:
    lines.append(
        f"N={r['N']} cells={r['cells']} "
        f"SRC_profile_ms_per_step={r['SRC_profile_ms_per_step']:.9g} "
        f"Q6GF_profile_ms_per_step={r['Q6GF_profile_ms_per_step']:.9g} "
        f"ratio={r['profile_ratio']:.9g} overhead_percent={r['profile_overhead_percent']:.6g} "
        f"increment_ms_per_step={r['increment_profile_ms_per_step']:.9g} "
        f"Q6_adapter_ms_per_step={r['Q6_adapter_ms_per_step']:.9g} "
        f"elliptic_profile_ms_per_step={r['elliptic_profile_ms_per_step']:.9g} "
        f"q6Converged={r['Q6_converged_final']} q6Iterations={r['Q6_iterations_final']} "
        f"q6ResidualRel={r['Q6_residual_final']:.9g}"
    )
lines.append(f"scaling_exponent_vs_linear_N_SRC_profile={log_slope('SRC_profile_ms_per_step'):.6g}")
lines.append(f"scaling_exponent_vs_linear_N_Q6GF_profile={log_slope('Q6GF_profile_ms_per_step'):.6g}")
lines.append(f"scaling_exponent_vs_linear_N_increment_profile={log_slope('increment_profile_ms_per_step'):.6g}")
lines.append("timing_note=primary comparison uses internal phase-profile ms/step; process elapsed is recorded only as ancillary because short huge-state runs include startup/state-I/O costs")
lines.append("interpretation=diagnostic extension of x22g/x22h; constant gamma,h,dt,kBT and periodic production paths; one pair per grid by default")
out_txt.write_text("\n".join(lines) + "\n")
print("\n".join(lines))
