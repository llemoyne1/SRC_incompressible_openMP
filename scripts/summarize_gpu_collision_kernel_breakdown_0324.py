#!/usr/bin/env python3
import argparse
import csv
import os
from collections import defaultdict

def read_rows(path):
    with open(path, newline="") as f:
        for row in csv.DictReader(f):
            yield row

def main():
    ap = argparse.ArgumentParser(description="Summarize 0324 internal CUDA kernel breakdown CSV.")
    ap.add_argument("input", nargs="?", default="dev_history/artifacts/gpu_phase_profile_0317d/runs/src_cuda_v2_0315m_periodic/rep_1/output/cuda_persistent_kernel_breakdown_0324.csv")
    ap.add_argument("--out", default="dev_history/artifacts/gpu_phase_profile_0317d/gpu_collision_kernel_breakdown_0324_top_kernels.csv")
    args = ap.parse_args()

    sums = defaultdict(float)
    counts = defaultdict(int)
    max_ms = defaultdict(float)
    nactive = {}
    numcells = {}
    for row in read_rows(args.input):
        k = row["kernel"]
        ms = float(row["ms"])
        sums[k] += ms
        counts[k] += 1
        if ms > max_ms[k]:
            max_ms[k] = ms
        nactive[k] = row.get("nActiveFluid", "")
        numcells[k] = row.get("numCells", "")

    os.makedirs(os.path.dirname(args.out) or ".", exist_ok=True)
    total_ms = sum(sums.values())
    with open(args.out, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["kernel", "total_ms", "total_s", "percent", "count", "mean_us", "max_us", "nActiveFluid", "numCells"])
        for k, total in sorted(sums.items(), key=lambda kv: kv[1], reverse=True):
            c = counts[k]
            pct = (100.0 * total / total_ms) if total_ms > 0 else 0.0
            w.writerow([k, f"{total:.9g}", f"{total/1000.0:.9g}", f"{pct:.6f}", c,
                        f"{(1000.0*total/c) if c else 0.0:.9g}", f"{1000.0*max_ms[k]:.9g}",
                        nactive.get(k, ""), numcells.get(k, "")])

    print(f"[0324-summary] input={args.input}")
    print(f"[0324-summary] output={args.out}")
    print(f"[0324-summary] total_kernel_ms={total_ms:.9g} kernels={len(sums)} rows={sum(counts.values())}")
    for k, total in sorted(sums.items(), key=lambda kv: kv[1], reverse=True)[:12]:
        pct = (100.0 * total / total_ms) if total_ms > 0 else 0.0
        print(f"{k},{total/1000.0:.9g}s,{pct:.3f}%,count={counts[k]}")

if __name__ == "__main__":
    main()
