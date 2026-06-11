#!/usr/bin/env python3
import argparse
import csv
import re
from collections import defaultdict, OrderedDict
from pathlib import Path


def parse_rep(path: Path) -> str:
    m = re.search(r"/rep_(\d+)/", str(path))
    return m.group(1) if m else ""


def read_breakdown_csv(path: Path):
    with path.open(newline="") as f:
        reader = csv.DictReader(f)
        step_order = defaultdict(int)
        for row in reader:
            if not row or row.get("kernel") in (None, "", "kernel"):
                continue
            try:
                step = int(float(row.get("step", "0")))
                ms = float(row.get("ms", "0"))
            except ValueError:
                continue
            step_order[step] += 1
            row["_path"] = str(path)
            row["_rep"] = parse_rep(path)
            row["_step"] = step
            row["_ms"] = ms
            row["_launch_index"] = step_order[step]
            yield row


def main():
    ap = argparse.ArgumentParser(description="Summarize 0328 appended CUDA-event kernel breakdown over many steps/repeats.")
    ap.add_argument("artifact_dir", nargs="?", default="dev_history/artifacts/gpu_kernel_breakdown_0328",
                    help="Artifact directory containing runs/**/cuda_persistent_kernel_breakdown_0324.csv")
    ap.add_argument("--pattern", default="runs/src_cuda_v2_0315m_periodic/rep_*/output/cuda_persistent_kernel_breakdown_0324.csv")
    args = ap.parse_args()

    artifact_dir = Path(args.artifact_dir)
    files = sorted(artifact_dir.glob(args.pattern))
    if not files:
        raise SystemExit(f"No kernel breakdown CSV files found under {artifact_dir} with pattern {args.pattern}")

    rows = []
    for path in files:
        rows.extend(read_breakdown_csv(path))
    if not rows:
        raise SystemExit("No valid rows parsed from kernel breakdown CSV files")

    by_kernel = defaultdict(lambda: {"total_ms": 0.0, "count": 0, "max_ms": 0.0, "steps": set(), "reps": set(), "nActiveFluid": "", "numCells": ""})
    by_rep_kernel = defaultdict(lambda: {"total_ms": 0.0, "count": 0, "max_ms": 0.0, "steps": set()})
    by_launch = defaultdict(lambda: {"kernel": "", "total_ms": 0.0, "count": 0, "max_ms": 0.0, "steps": set(), "reps": set()})
    by_rep = defaultdict(lambda: {"total_ms": 0.0, "count": 0, "steps": set()})

    for r in rows:
        k = r["kernel"]
        rep = r["_rep"]
        step = r["_step"]
        ms = r["_ms"]
        idx = r["_launch_index"]

        g = by_kernel[k]
        g["total_ms"] += ms
        g["count"] += 1
        g["max_ms"] = max(g["max_ms"], ms)
        g["steps"].add((rep, step))
        g["reps"].add(rep)
        g["nActiveFluid"] = r.get("nActiveFluid", "")
        g["numCells"] = r.get("numCells", "")

        rg = by_rep_kernel[(rep, k)]
        rg["total_ms"] += ms
        rg["count"] += 1
        rg["max_ms"] = max(rg["max_ms"], ms)
        rg["steps"].add(step)

        lg = by_launch[(idx, k)]
        lg["kernel"] = k
        lg["total_ms"] += ms
        lg["count"] += 1
        lg["max_ms"] = max(lg["max_ms"], ms)
        lg["steps"].add((rep, step))
        lg["reps"].add(rep)

        rr = by_rep[rep]
        rr["total_ms"] += ms
        rr["count"] += 1
        rr["steps"].add(step)

    out_top = artifact_dir / "gpu_kernel_breakdown_0328_top_kernels.csv"
    out_rep = artifact_dir / "gpu_kernel_breakdown_0328_rep_kernel_breakdown.csv"
    out_seq = artifact_dir / "gpu_kernel_breakdown_0328_launch_sequence.csv"
    out_manifest = artifact_dir / "gpu_kernel_breakdown_0328_manifest.csv"
    artifact_dir.mkdir(parents=True, exist_ok=True)

    total_ms = sum(v["total_ms"] for v in by_kernel.values())
    with out_top.open("w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["kernel", "total_ms", "total_s", "percent", "rows", "sampled_steps", "launches_per_step", "mean_us", "max_us", "repeats", "nActiveFluid", "numCells"])
        for k, v in sorted(by_kernel.items(), key=lambda kv: kv[1]["total_ms"], reverse=True):
            sampled_steps = len(v["steps"])
            launches_per_step = v["count"] / sampled_steps if sampled_steps else 0.0
            percent = 100.0 * v["total_ms"] / total_ms if total_ms > 0 else 0.0
            mean_us = 1000.0 * v["total_ms"] / v["count"] if v["count"] else 0.0
            w.writerow([k, f"{v['total_ms']:.9g}", f"{v['total_ms']/1000.0:.9g}", f"{percent:.6f}", v["count"], sampled_steps,
                        f"{launches_per_step:.6f}", f"{mean_us:.9g}", f"{1000.0*v['max_ms']:.9g}",
                        ";".join(sorted(v["reps"])), v["nActiveFluid"], v["numCells"]])

    with out_rep.open("w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["repeat", "kernel", "total_ms", "total_s", "percent_in_repeat", "rows", "sampled_steps", "mean_us", "max_us"])
        rep_totals = {rep: v["total_ms"] for rep, v in by_rep.items()}
        for (rep, k), v in sorted(by_rep_kernel.items(), key=lambda kv: (kv[0][0], -kv[1]["total_ms"])):
            pct = 100.0 * v["total_ms"] / rep_totals.get(rep, 0.0) if rep_totals.get(rep, 0.0) > 0 else 0.0
            mean_us = 1000.0 * v["total_ms"] / v["count"] if v["count"] else 0.0
            w.writerow([rep, k, f"{v['total_ms']:.9g}", f"{v['total_ms']/1000.0:.9g}", f"{pct:.6f}", v["count"], len(v["steps"]),
                        f"{mean_us:.9g}", f"{1000.0*v['max_ms']:.9g}"])

    with out_seq.open("w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["launch_index", "kernel", "total_ms", "total_s", "percent", "rows", "sampled_steps", "mean_us", "max_us", "repeats"])
        for (idx, k), v in sorted(by_launch.items(), key=lambda kv: kv[0][0]):
            pct = 100.0 * v["total_ms"] / total_ms if total_ms > 0 else 0.0
            mean_us = 1000.0 * v["total_ms"] / v["count"] if v["count"] else 0.0
            w.writerow([idx, k, f"{v['total_ms']:.9g}", f"{v['total_ms']/1000.0:.9g}", f"{pct:.6f}", v["count"], len(v["steps"]),
                        f"{mean_us:.9g}", f"{1000.0*v['max_ms']:.9g}", ";".join(sorted(v["reps"]))])

    with out_manifest.open("w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["file", "repeat", "rows", "sampled_steps", "first_step", "last_step"])
        for path in files:
            frows = list(read_breakdown_csv(path))
            steps = sorted({r["_step"] for r in frows})
            w.writerow([str(path), parse_rep(path), len(frows), len(steps), steps[0] if steps else "", steps[-1] if steps else ""])

    print(f"[0328-summary] files={len(files)} rows={len(rows)} total_kernel_ms={total_ms:.9g}")
    print(f"[0328-summary] top={out_top}")
    print(f"[0328-summary] per_rep={out_rep}")
    print(f"[0328-summary] sequence={out_seq}")
    print(f"[0328-summary] manifest={out_manifest}")
    for k, v in sorted(by_kernel.items(), key=lambda kv: kv[1]["total_ms"], reverse=True)[:12]:
        pct = 100.0 * v["total_ms"] / total_ms if total_ms > 0 else 0.0
        print(f"{k},{v['total_ms']/1000.0:.9g}s,{pct:.3f}%,rows={v['count']},steps={len(v['steps'])}")

if __name__ == "__main__":
    main()
