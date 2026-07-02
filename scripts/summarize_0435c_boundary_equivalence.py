#!/usr/bin/env python3
from __future__ import annotations

import argparse
import csv
import math
from pathlib import Path
from typing import Dict, List, Tuple, Optional

KEYS_SUMMARY = [
    "step", "time",
    "inletReservoirDeleted", "inletBackflowDeleted", "outletParticlesDeleted",
    "inletParticlesInserted", "inletNetParticleDelta",
    "inletReservoirStdN", "inletReservoirEmptyFraction",
    "inletMeanUx", "inletMeanUy", "inletKBT",
]

KEYS_THERMO = [
    "step", "particlesVisited", "fluidParticles", "particlesRotated", "invalidCellParticles",
    "thermostatAppliedOnGpu", "thermostatCellsRescaled", "thermostatParticlesRescaled",
    "thermostatKBTBefore", "thermostatKBTAfter",
    "thermostatScaleMean", "thermostatScaleMin", "thermostatScaleMax",
    "sharedParticleStateEnabled", "particleStateMetadataCacheHits",
]

def read_csv(path: Path):
    if not path.exists():
        return [], [], 0
    nonfinite = 0
    rows = []
    with path.open(newline="", encoding="utf-8", errors="replace") as f:
        reader = csv.DictReader(f)
        fields = reader.fieldnames or []
        for row in reader:
            rows.append(row)
            for v in row.values():
                if v is None or v == "":
                    continue
                try:
                    x = float(v)
                    if not math.isfinite(x):
                        nonfinite += 1
                except Exception:
                    pass
    return fields, rows, nonfinite

def pick(row, keys):
    return "; ".join(f"{k}={row[k]}" for k in keys if k in row)

def fnum(row, key):
    if key not in row or row[key] == "":
        return None
    try:
        return float(row[key])
    except Exception:
        return None

def summarize_dir(label: str, out: Path):
    print(f"\n=== {label} ===")
    print(f"dir={out}")
    if not out.exists():
        print("MISSING_DIR=1")
        return {}

    files = sorted(p.name for p in out.iterdir() if p.is_file())
    print(f"files={len(files)}")
    print("file_list=" + ",".join(files))

    metrics = {}

    for name, keys, group in [
        ("summary_runtime.csv", KEYS_SUMMARY, "summary"),
        ("cuda_persistent_src_collision_thermostat_0215.csv", KEYS_THERMO, "thermo"),
    ]:
        path = out / name
        fields, rows, nonfinite = read_csv(path)
        print(f"\n--- {name} ---")
        print(f"exists={path.exists()} rows={len(rows)} nonfinite={nonfinite}")
        if rows:
            print("first: " + pick(rows[0], keys))
            print("last : " + pick(rows[-1], keys))
            metrics[group] = {k: fnum(rows[-1], k) for k in keys}
    return metrics

def rel_abs(a, b):
    if a is None or b is None:
        return "NA"
    d = b - a
    denom = max(abs(a), abs(b), 1.0)
    return f"delta={d:.12g} rel={abs(d)/denom:.6g}"

def compare_pair(name, a_lab, a, b_lab, b):
    print(f"\n=== COMPARE {name}: {a_lab} -> {b_lab} ===")
    for group, keys in [
        ("summary", ["inletReservoirDeleted","inletBackflowDeleted","outletParticlesDeleted","inletParticlesInserted","inletNetParticleDelta","inletMeanUx","inletMeanUy","inletKBT"]),
        ("thermo", ["fluidParticles","invalidCellParticles","thermostatKBTBefore","thermostatKBTAfter","thermostatAppliedOnGpu","sharedParticleStateEnabled"]),
    ]:
        print(f"-- {group} --")
        ar = a.get(group, {})
        br = b.get(group, {})
        for k in keys:
            av = ar.get(k)
            bv = br.get(k)
            print(f"{k}: {a_lab}={av} {b_lab}={bv} {rel_abs(av,bv)}")

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", default="runs/0435c_compare")
    ap.add_argument("--cases", nargs="+", default=["injection", "io_box"])
    ap.add_argument("--modes", nargs="+", default=["ref_old_no_shared", "new_no_shared", "new_shared"])
    args = ap.parse_args()

    base = Path(args.base)
    all_metrics = {}

    print("# SRC/MPCD 0435c CUDA IO boundary equivalence report")
    print(f"# base={base.resolve()}")
    print("# ref_old_no_shared vs new_no_shared -> CPU boundary skip effect")
    print("# new_no_shared vs new_shared -> shared_0251 thermostat effect")

    for case in args.cases:
        for mode in args.modes:
            out = base / f"{case}_{mode}" / "src" / "output"
            all_metrics[(case, mode)] = summarize_dir(f"{case}/{mode}", out)

    for case in args.cases:
        compare_pair(case, "ref_old_no_shared", all_metrics[(case,"ref_old_no_shared")],
                     "new_no_shared", all_metrics[(case,"new_no_shared")])
        compare_pair(case, "new_no_shared", all_metrics[(case,"new_no_shared")],
                     "new_shared", all_metrics[(case,"new_shared")])

if __name__ == "__main__":
    main()
