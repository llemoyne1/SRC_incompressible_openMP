#!/usr/bin/env python3
"""Compare a baseline resident-remap validation root against a 0483 candidate root."""
from __future__ import annotations

import argparse
import csv
from pathlib import Path
from typing import Dict, List, Tuple


def read_rows(path: Path) -> List[dict]:
    if not path.exists():
        return []
    with path.open(newline="") as stream:
        return list(csv.DictReader(stream))


def find_summary(root: Path) -> Path:
    candidates = list(root.rglob("remap_fusion_cpu_cuda_summary_0483.csv"))
    if candidates:
        return candidates[0]
    # Fallback for older 0476-style roots: fewer columns, but enough for wall/delta/remap timing.
    candidates = list(root.rglob("materializer_authoritative_summary_0476.csv"))
    if candidates:
        return candidates[0]
    candidates = list(root.rglob("scaling_cuda_vs_cpu_summary_0463.csv")) + list(root.rglob("scaling_cuda_vs_cpu_summary_0464.csv"))
    if candidates:
        return candidates[0]
    raise FileNotFoundError(f"no recognized summary CSV under {root}")


def num(row: dict, *keys: str, default: float = 0.0) -> float:
    for key in keys:
        value = row.get(key, "")
        if value not in ("", None):
            try:
                return float(value)
            except ValueError:
                pass
    return default


def key(row: dict) -> Tuple[str, str, str]:
    return (row.get("case", ""), row.get("mode", ""), row.get("seed", ""))


def index_rows(rows: List[dict]) -> Dict[Tuple[str, str, str], dict]:
    out: Dict[Tuple[str, str, str], dict] = {}
    for row in rows:
        k = key(row)
        if k[0] and k[1]:
            out[k] = row
    return out


def ratio(old: float, new: float) -> float:
    return old / new if new > 0 else 0.0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("baseline_root", type=Path)
    parser.add_argument("candidate_root", type=Path)
    parser.add_argument("--out-root", type=Path, default=None)
    args = parser.parse_args()

    out_root = args.out_root or args.candidate_root
    out_root.mkdir(parents=True, exist_ok=True)

    baseline_summary = find_summary(args.baseline_root)
    candidate_summary = find_summary(args.candidate_root)
    base = index_rows(read_rows(baseline_summary))
    cand = index_rows(read_rows(candidate_summary))

    keys = sorted(set(base) & set(cand))
    rows = []
    for k in keys:
        b = base[k]
        c = cand[k]
        b_cuda = num(b, "cuda_wall_s", "cudaWall")
        c_cuda = num(c, "cuda_wall_s", "cudaWall")
        b_remap = num(b, "remap_kernel_s_sum", "remap_kernel_s", "remap_kernel_s_avg")
        c_remap = num(c, "remap_kernel_s_sum", "remap_kernel_s", "remap_kernel_s_avg")
        b_thermal = num(b, "thermal_kernel_s_sum", "thermal_kernel_s", "thermal_kernel_s_avg")
        c_thermal = num(c, "thermal_kernel_s_sum", "thermal_kernel_s", "thermal_kernel_s_avg")
        b_total = num(b, "remap_total_s_sum", "remap_total_s", "remap_total_s_avg")
        c_total = num(c, "remap_total_s_sum", "remap_total_s", "remap_total_s_avg")
        rows.append({
            "case": k[0],
            "mode": k[1],
            "seed": k[2],
            "baseline_pass": int(num(b, "pass") == 1),
            "candidate_pass": int(num(c, "pass") == 1),
            "baseline_cuda_wall_s": b_cuda,
            "candidate_cuda_wall_s": c_cuda,
            "cuda_wall_ratio_baseline_over_candidate": ratio(b_cuda, c_cuda),
            "baseline_max_delta": num(b, "max_summary_delta", "maxSummaryDelta"),
            "candidate_max_delta": num(c, "max_summary_delta", "maxSummaryDelta"),
            "baseline_remap_kernel_s": b_remap,
            "candidate_remap_kernel_s": c_remap,
            "remap_kernel_ratio_baseline_over_candidate": ratio(b_remap, c_remap),
            "baseline_thermal_kernel_s": b_thermal,
            "candidate_thermal_kernel_s": c_thermal,
            "thermal_kernel_ratio_baseline_over_candidate": ratio(b_thermal, c_thermal),
            "baseline_remap_total_s": b_total,
            "candidate_remap_total_s": c_total,
            "remap_total_ratio_baseline_over_candidate": ratio(b_total, c_total),
        })

    csv_out = out_root / "remap_fusion_gain_compare_0483.csv"
    fields = list(rows[0].keys()) if rows else ["case", "mode", "seed"]
    with csv_out.open("w", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)

    report_out = out_root / "remap_fusion_gain_compare_0483.md"
    with report_out.open("w") as stream:
        stream.write("# 0483 remap-fusion gain comparison\n\n")
        stream.write(f"Baseline root: `{args.baseline_root}`  \n")
        stream.write(f"Candidate root: `{args.candidate_root}`  \n")
        stream.write(f"Baseline summary: `{baseline_summary}`  \n")
        stream.write(f"Candidate summary: `{candidate_summary}`  \n\n")
        stream.write(f"Matched rows: **{len(rows)}**\n\n")
        stream.write("| case | mode | seed | candidate pass | CUDA wall ratio | remap kernel ratio | thermal ratio | remap total ratio | candidate max delta |\n")
        stream.write("| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |\n")
        for row in rows:
            stream.write(
                f"| {row['case']} | {row['mode']} | {row['seed']} | {row['candidate_pass']} | "
                f"{row['cuda_wall_ratio_baseline_over_candidate']:.3f} | "
                f"{row['remap_kernel_ratio_baseline_over_candidate']:.3f} | "
                f"{row['thermal_kernel_ratio_baseline_over_candidate']:.3f} | "
                f"{row['remap_total_ratio_baseline_over_candidate']:.3f} | "
                f"{row['candidate_max_delta']:.3e} |\n"
            )
        stream.write(f"\nFlat CSV: `{csv_out}`\n")

    print(report_out)
    print(report_out.read_text())
    if not rows:
        return 1
    if any(row["candidate_pass"] != 1 for row in rows):
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
