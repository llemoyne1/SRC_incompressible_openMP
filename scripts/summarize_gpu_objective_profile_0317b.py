#!/usr/bin/env python3
"""Summarize 0317b objective GPU profiling artifacts.

Inputs are intentionally external to the solver: manifest rows, GNU time files,
Nsight Systems CSV exports when available, and existing stdout/stderr logs.
The parser is defensive because nsys CSV column names vary across versions.
"""
from __future__ import annotations

import csv
import glob
import math
import os
import re
import sys
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Tuple


def read_manifest(path: Path) -> List[dict]:
    with path.open(newline="") as f:
        return list(csv.DictReader(f))


def read_time_file(path: str) -> Dict[str, float]:
    out: Dict[str, float] = {}
    if not path or not os.path.exists(path):
        return out
    with open(path, newline="") as f:
        for row in csv.reader(f):
            if len(row) >= 2:
                try:
                    out[row[0]] = float(row[1])
                except ValueError:
                    pass
    return out


def norm(s: str) -> str:
    return re.sub(r"[^a-z0-9]+", "", (s or "").lower())


def find_col(fieldnames: Iterable[str], candidates: Iterable[str]) -> Optional[str]:
    fields = list(fieldnames or [])
    nf = {norm(f): f for f in fields}
    for c in candidates:
        nc = norm(c)
        if nc in nf:
            return nf[nc]
    # relaxed contains search
    for f in fields:
        n = norm(f)
        for c in candidates:
            nc = norm(c)
            if nc and nc in n:
                return f
    return None


def parse_float(x: object) -> float:
    if x is None:
        return 0.0
    s = str(x).strip().replace(",", "")
    if not s:
        return 0.0
    # nsys sometimes prints units in a separate column, but keep this robust.
    m = re.search(r"[-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?", s)
    if not m:
        return 0.0
    try:
        return float(m.group(0))
    except ValueError:
        return 0.0


def unit_to_seconds(value: float, unit: str | None, header: str | None = None) -> float:
    u = (unit or header or "").lower()
    if "ns" in u or "nanosecond" in u:
        return value * 1e-9
    if "us" in u or "µs" in u or "microsecond" in u:
        return value * 1e-6
    if "ms" in u or "millisecond" in u:
        return value * 1e-3
    return value


def csv_rows(path: Path) -> Tuple[List[str], List[dict]]:
    try:
        with path.open(newline="", errors="replace") as f:
            sample = f.read(4096)
            f.seek(0)
            # Skip preamble lines until a plausible CSV header appears.
            lines = f.readlines()
        header_idx = 0
        for i, line in enumerate(lines):
            low = line.lower()
            if ("," in line) and ("time" in low or "name" in low or "operation" in low or "instances" in low):
                header_idx = i
                break
        text = "".join(lines[header_idx:])
        rdr = csv.DictReader(text.splitlines())
        return list(rdr.fieldnames or []), list(rdr)
    except Exception:
        return [], []


def stats_files(art_dir: Path, target: str, rep: str) -> List[Path]:
    base = art_dir / "nsys_stats"
    pats = [
        f"{target}_rep_{rep}*.csv",
        f"{target}_rep_{rep}*.txt",
    ]
    files: List[Path] = []
    for pat in pats:
        files.extend(Path(p) for p in glob.glob(str(base / pat)))
    return sorted(set(files))


def classify_stats_file(path: Path, fields: List[str], rows: List[dict]) -> str:
    name = path.name.lower()
    if "cuda_gpu_kern_sum" in name or "gpukern" in name or "kernel" in name:
        return "kern"
    if "cuda_api_sum" in name or "api" in name:
        return "api"
    if "mem_time" in name or "memtime" in name or "memcpy" in name or "memset" in name:
        return "mem"
    joined = " ".join(fields).lower()
    sample = " ".join(str(v).lower() for r in rows[:5] for v in r.values())
    if "kernel" in joined or "demangled" in joined or "grid" in joined:
        return "kern"
    if "cuda" in sample and ("memcpy" in sample or "memset" in sample):
        return "mem"
    if "api" in joined or "operation" in joined and "cuda" in sample:
        return "api"
    return "unknown"


def time_seconds_from_row(row: dict, fields: List[str]) -> float:
    total_col = find_col(fields, [
        "Total Time (ns)", "Total Time", "Time (ns)", "Time", "Duration", "Total",
    ])
    if not total_col:
        return 0.0
    unit_col = find_col(fields, ["Time Unit", "Unit"])
    return unit_to_seconds(parse_float(row.get(total_col)), row.get(unit_col) if unit_col else None, total_col)


def count_from_row(row: dict, fields: List[str]) -> float:
    col = find_col(fields, ["Instances", "Calls", "Count", "Num Calls", "Operations"])
    return parse_float(row.get(col)) if col else 0.0


def name_from_row(row: dict, fields: List[str]) -> str:
    col = find_col(fields, ["Name", "Operation", "API Name", "Kernel Name", "Demangled Name"])
    return str(row.get(col, "")).strip() if col else ""


def parse_nsys(art_dir: Path, target: str, rep: str) -> Tuple[dict, List[dict], List[dict]]:
    totals = {
        "kernelTime": 0.0,
        "kernelCount": 0.0,
        "cudaApiTime": 0.0,
        "cudaApiCalls": 0.0,
        "cudaMemcpyHtoDTime": 0.0,
        "cudaMemcpyDtoHTime": 0.0,
        "cudaMemcpyOtherTime": 0.0,
        "cudaMemsetTime": 0.0,
    }
    kernel_rows: List[dict] = []
    api_rows: List[dict] = []
    for path in stats_files(art_dir, target, rep):
        fields, rows = csv_rows(path)
        if not fields or not rows:
            continue
        kind = classify_stats_file(path, fields, rows)
        for r in rows:
            t = time_seconds_from_row(r, fields)
            c = count_from_row(r, fields)
            nm = name_from_row(r, fields)
            low = nm.lower()
            if kind == "kern":
                totals["kernelTime"] += t
                totals["kernelCount"] += c
                if nm:
                    kernel_rows.append({"target": target, "repeat": rep, "name": nm, "time": t, "count": c, "source": path.name})
            elif kind == "api":
                totals["cudaApiTime"] += t
                totals["cudaApiCalls"] += c
                if nm:
                    api_rows.append({"target": target, "repeat": rep, "name": nm, "time": t, "count": c, "source": path.name})
            elif kind == "mem":
                if "memset" in low:
                    totals["cudaMemsetTime"] += t
                elif "htod" in low or "h2d" in low or "host to device" in low:
                    totals["cudaMemcpyHtoDTime"] += t
                elif "dtoh" in low or "d2h" in low or "device to host" in low:
                    totals["cudaMemcpyDtoHTime"] += t
                elif "memcpy" in low or "mem" in low:
                    totals["cudaMemcpyOtherTime"] += t
    return totals, kernel_rows, api_rows


def aggregate_top(rows: List[dict], total_key: str = "time") -> List[dict]:
    agg: Dict[Tuple[str, str], dict] = {}
    for r in rows:
        key = (r["target"], r["name"])
        a = agg.setdefault(key, {"target": r["target"], "name": r["name"], "time": 0.0, "count": 0.0, "sources": set()})
        a["time"] += float(r.get("time") or 0.0)
        a["count"] += float(r.get("count") or 0.0)
        a["sources"].add(r.get("source", ""))
    out = []
    for a in agg.values():
        a = dict(a)
        a["sources"] = ";".join(sorted(x for x in a["sources"] if x))
        out.append(a)
    out.sort(key=lambda x: x["time"], reverse=True)
    return out


def write_csv(path: Path, rows: List[dict], fields: List[str]) -> None:
    with path.open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fields, extrasaction="ignore")
        w.writeheader()
        for r in rows:
            w.writerow(r)


def main(argv: List[str]) -> int:
    if len(argv) != 3:
        print("usage: summarize_gpu_objective_profile_0317b.py MANIFEST ART_DIR", file=sys.stderr)
        return 2
    manifest = Path(argv[1])
    art_dir = Path(argv[2])
    rows = read_manifest(manifest)
    summary: List[dict] = []
    all_kernels: List[dict] = []
    all_apis: List[dict] = []
    for r in rows:
        target = r.get("target", "")
        rep = r.get("repeat", "")
        steps = parse_float(r.get("steps"))
        tf = read_time_file(r.get("timeFile", ""))
        total = tf.get("elapsed_seconds", 0.0)
        nsys_totals, kernels, apis = parse_nsys(art_dir, target, rep)
        all_kernels.extend(kernels)
        all_apis.extend(apis)
        kernel_count = nsys_totals["kernelCount"]
        summary.append({
            "target": target,
            "repeat": rep,
            "profiler": r.get("profiler", ""),
            "exitCode": r.get("exitCode", ""),
            "steps": int(steps) if steps else "",
            "totalTime_s": f"{total:.9g}" if total else "",
            "timePerStep_s": f"{(total/steps):.9g}" if total and steps else "",
            "kernelTime_s": f"{nsys_totals['kernelTime']:.9g}" if nsys_totals["kernelTime"] else "",
            "cudaMemcpyHtoDTime_s": f"{nsys_totals['cudaMemcpyHtoDTime']:.9g}" if nsys_totals["cudaMemcpyHtoDTime"] else "",
            "cudaMemcpyDtoHTime_s": f"{nsys_totals['cudaMemcpyDtoHTime']:.9g}" if nsys_totals["cudaMemcpyDtoHTime"] else "",
            "cudaMemcpyOtherTime_s": f"{nsys_totals['cudaMemcpyOtherTime']:.9g}" if nsys_totals["cudaMemcpyOtherTime"] else "",
            "cudaMemsetTime_s": f"{nsys_totals['cudaMemsetTime']:.9g}" if nsys_totals["cudaMemsetTime"] else "",
            "cudaApiTime_s": f"{nsys_totals['cudaApiTime']:.9g}" if nsys_totals["cudaApiTime"] else "",
            "kernelCount": int(kernel_count) if kernel_count else "",
            "kernelsPerStep": f"{(kernel_count/steps):.9g}" if kernel_count and steps else "",
            "cudaApiCalls": int(nsys_totals["cudaApiCalls"]) if nsys_totals["cudaApiCalls"] else "",
            "binary": r.get("binary", ""),
            "stdoutFile": r.get("stdoutFile", ""),
            "stderrFile": r.get("stderrFile", ""),
            "note": r.get("note", ""),
        })
    fields = [
        "target", "repeat", "profiler", "exitCode", "steps", "totalTime_s", "timePerStep_s",
        "kernelTime_s", "cudaMemcpyHtoDTime_s", "cudaMemcpyDtoHTime_s", "cudaMemcpyOtherTime_s",
        "cudaMemsetTime_s", "cudaApiTime_s", "kernelCount", "kernelsPerStep", "cudaApiCalls",
        "binary", "stdoutFile", "stderrFile", "note",
    ]
    write_csv(art_dir / "gpu_objective_profile_0317b_summary.csv", summary, fields)
    top_k = aggregate_top(all_kernels)[:40]
    top_a = aggregate_top(all_apis)[:40]
    # Add per-target percentages against aggregate kernel/API time.
    ktot: Dict[str, float] = {}
    atot: Dict[str, float] = {}
    for x in top_k:
        ktot[x["target"]] = ktot.get(x["target"], 0.0) + x["time"]
    for x in aggregate_top(all_kernels):
        ktot[x["target"]] = max(ktot.get(x["target"], 0.0), 0.0)
    full_ktot: Dict[str, float] = {}
    for x in aggregate_top(all_kernels):
        full_ktot[x["target"]] = full_ktot.get(x["target"], 0.0) + x["time"]
    full_atot: Dict[str, float] = {}
    for x in aggregate_top(all_apis):
        full_atot[x["target"]] = full_atot.get(x["target"], 0.0) + x["time"]
    for x in top_k:
        den = full_ktot.get(x["target"], 0.0)
        x["percentOfKernelTime"] = f"{100*x['time']/den:.6g}" if den else ""
        x["time_s"] = f"{x['time']:.9g}"
        x["count"] = int(x["count"]) if x["count"] else ""
    for x in top_a:
        den = full_atot.get(x["target"], 0.0)
        x["percentOfCudaApiTime"] = f"{100*x['time']/den:.6g}" if den else ""
        x["time_s"] = f"{x['time']:.9g}"
        x["count"] = int(x["count"]) if x["count"] else ""
    write_csv(art_dir / "gpu_objective_profile_0317b_top_kernels.csv", top_k,
              ["target", "name", "time_s", "count", "percentOfKernelTime", "sources"])
    write_csv(art_dir / "gpu_objective_profile_0317b_top_cuda_api.csv", top_a,
              ["target", "name", "time_s", "count", "percentOfCudaApiTime", "sources"])
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
