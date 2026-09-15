#!/usr/bin/env python3
"""0493x17d membrane strain-localization diagnostic.

Read-only post-processing of an existing membrane run. Standard library only.
Reconstructs edge strains from the Lagrangian node history and separates
free, pinned and anchor-interface edges.
"""
import argparse
import csv
import math
from collections import defaultdict
from pathlib import Path


def fv(row, key, default=0.0):
    value = row.get(key, "")
    return float(value) if value not in ("", None) else default


def iv(row, key, default=0):
    value = row.get(key, "")
    return int(float(value)) if value not in ("", None) else default


def read_rows(path):
    with path.open(newline="") as handle:
        return list(csv.DictReader(handle))


def percentile(values, q):
    if not values:
        return float("nan")
    values = sorted(values)
    if len(values) == 1:
        return values[0]
    pos = (len(values) - 1) * q
    lo = int(math.floor(pos))
    hi = int(math.ceil(pos))
    if lo == hi:
        return values[lo]
    w = pos - lo
    return values[lo] * (1.0 - w) + values[hi] * w


def edge_class(pin_i, pin_j):
    if pin_i and pin_j:
        return "pinned"
    if pin_i or pin_j:
        return "interface"
    return "free"


def reconstruct_edges(rows):
    rows = sorted(rows, key=lambda r: iv(r, "node"))
    n = len(rows)
    edges = []
    for k in range(n):
        a = rows[k]
        b = rows[(k + 1) % n]
        i = iv(a, "node")
        j = iv(b, "node")
        x0a, y0a = fv(a, "x0"), fv(a, "y0")
        x0b, y0b = fv(b, "x0"), fv(b, "y0")
        xa, ya = fv(a, "x"), fv(a, "y")
        xb, yb = fv(b, "x"), fv(b, "y")
        l0 = math.hypot(x0b - x0a, y0b - y0a)
        length = math.hypot(xb - xa, yb - ya)
        if l0 <= 0.0:
            raise RuntimeError(f"zero rest length on edge {i}-{j}")
        strain = (length - l0) / l0
        cls = edge_class(iv(a, "pinned0493x17d") != 0,
                         iv(b, "pinned0493x17d") != 0)
        edges.append({
            "edge": k,
            "nodeI": i,
            "nodeJ": j,
            "class": cls,
            "strain": strain,
            "absStrain": abs(strain),
            "restLength": l0,
            "length": length,
            "xMid0": 0.5 * (x0a + x0b),
            "yMid0": 0.5 * (y0a + y0b),
            "xMid": 0.5 * (xa + xb),
            "yMid": 0.5 * (ya + yb),
        })
    return edges


def max_record(records, cls=None):
    candidates = records if cls is None else [r for r in records if r["class"] == cls]
    return max(candidates, key=lambda r: r["absStrain"]) if candidates else None


def fmt_record(prefix, r):
    if r is None:
        return [f"{prefix}=NONE"]
    return [
        f"{prefix}Abs={r['absStrain']}",
        f"{prefix}Signed={r['strain']}",
        f"{prefix}Step={r['step']}",
        f"{prefix}Time={r['time']}",
        f"{prefix}Edge={r['nodeI']}-{r['nodeJ']}",
        f"{prefix}Class={r['class']}",
        f"{prefix}XMid0={r['xMid0']}",
        f"{prefix}YMid0={r['yMid0']}",
        f"{prefix}XMid={r['xMid']}",
        f"{prefix}YMid={r['yMid']}",
    ]


def write_edge_csv(path, records):
    fields = ["step", "time", "edge", "nodeI", "nodeJ", "class", "strain", "absStrain",
              "restLength", "length", "xMid0", "yMid0", "xMid", "yMid"]
    with path.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        for r in records:
            writer.writerow({k: r[k] for k in fields})


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", default="runs/0493x17d_fixed_membrane_publishable")
    args = parser.parse_args()

    root = Path(args.root)
    run = root / "fresh"
    output = run / "output"
    path = output / "chi_membrane_nodes_0493x17c.csv"
    if not path.is_file():
        raise SystemExit(f"[0493x17d-strain] ERROR missing {path}")

    rows = read_rows(path)
    if not rows:
        raise SystemExit("[0493x17d-strain] ERROR empty node history")

    by_step = defaultdict(list)
    for row in rows:
        by_step[iv(row, "step")].append(row)
    steps = sorted(by_step)

    all_edges = []
    edges_by_step = {}
    max_deflection = -1.0
    max_deflection_step = steps[0]
    for step in steps:
        step_rows = by_step[step]
        time = fv(step_rows[0], "time")
        edges = reconstruct_edges(step_rows)
        for e in edges:
            e["step"] = step
            e["time"] = time
        edges_by_step[step] = edges
        all_edges.extend(edges)

        step_deflection = max(abs(fv(r, "x") - fv(r, "x0"))
                              for r in step_rows if iv(r, "pinned0493x17d") == 0)
        if step_deflection > max_deflection:
            max_deflection = step_deflection
            max_deflection_step = step

    first_edges = edges_by_step[steps[0]]
    class_counts = {cls: sum(e["class"] == cls for e in first_edges)
                    for cls in ("free", "interface", "pinned")}

    global_max = max_record(all_edges)
    free_max = max_record(all_edges, "free")
    interface_max = max_record(all_edges, "interface")
    pinned_max = max_record(all_edges, "pinned")

    free_all = [e["absStrain"] for e in all_edges if e["class"] == "free"]
    interface_all = [e["absStrain"] for e in all_edges if e["class"] == "interface"]
    defl_edges = edges_by_step[max_deflection_step]
    free_defl = [e["absStrain"] for e in defl_edges if e["class"] == "free"]
    interface_defl = [e["absStrain"] for e in defl_edges if e["class"] == "interface"]

    # Concentration indicator: a large interface/free ratio points to an anchor-transition hotspot.
    interface_to_free = (interface_max["absStrain"] / max(1e-30, free_max["absStrain"])) \
        if interface_max and free_max else float("nan")

    lines = [
        "0493x17d membrane strain localization",
        f"nodeSnapshots={len(steps)}",
        f"edgeCount={len(first_edges)}",
        f"freeEdges={class_counts['free']}",
        f"interfaceEdges={class_counts['interface']}",
        f"pinnedEdges={class_counts['pinned']}",
        f"maxDeflection={max_deflection}",
        f"maxDeflectionStep={max_deflection_step}",
        f"freeAbsStrainP95AllSnapshots={percentile(free_all, 0.95)}",
        f"freeAbsStrainP99AllSnapshots={percentile(free_all, 0.99)}",
        f"interfaceAbsStrainP95AllSnapshots={percentile(interface_all, 0.95)}",
        f"interfaceAbsStrainP99AllSnapshots={percentile(interface_all, 0.99)}",
        f"freeAbsStrainP95AtMaxDeflection={percentile(free_defl, 0.95)}",
        f"freeAbsStrainP99AtMaxDeflection={percentile(free_defl, 0.99)}",
        f"interfaceAbsStrainP95AtMaxDeflection={percentile(interface_defl, 0.95)}",
        f"interfaceAbsStrainP99AtMaxDeflection={percentile(interface_defl, 0.99)}",
        f"maxInterfaceToMaxFreeStrainRatio={interface_to_free}",
    ]
    lines.extend(fmt_record("globalMax", global_max))
    lines.extend(fmt_record("freeMax", free_max))
    lines.extend(fmt_record("interfaceMax", interface_max))
    lines.extend(fmt_record("pinnedMax", pinned_max))

    analysis = root / "analysis"
    analysis.mkdir(parents=True, exist_ok=True)
    summary = analysis / "strain_localization_0493x17d.txt"
    summary.write_text("\n".join(lines) + "\n")

    global_step = global_max["step"]
    write_edge_csv(analysis / "strain_edges_global_max_step_0493x17d.csv",
                   edges_by_step[global_step])
    write_edge_csv(analysis / "strain_edges_max_deflection_step_0493x17d.csv",
                   edges_by_step[max_deflection_step])

    print("\n".join(lines))
    print(f"[0493x17d-strain] summary={summary}")
    print(f"[0493x17d-strain] globalMaxProfile={analysis/'strain_edges_global_max_step_0493x17d.csv'}")
    print(f"[0493x17d-strain] maxDeflectionProfile={analysis/'strain_edges_max_deflection_step_0493x17d.csv'}")


if __name__ == "__main__":
    main()
