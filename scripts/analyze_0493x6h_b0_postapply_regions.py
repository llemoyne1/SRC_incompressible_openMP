#!/usr/bin/env python3
"""Summarize 0493x6h-B0 post-application Q6 residual localization."""
from __future__ import annotations

import argparse
import csv
import math
from collections import defaultdict
from pathlib import Path

REGIONS = ("bulk", "interface", "wall", "wall_interface", "corner", "corner_interface")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--csv", type=Path, required=True)
    ap.add_argument("--species-index", type=int, default=0)
    args = ap.parse_args()

    with args.csv.open(newline="") as f:
        rows = [r for r in csv.DictReader(f) if int(r["speciesIndex"]) == args.species_index]
    if not rows:
        raise SystemExit(f"no B0 rows for species {args.species_index}: {args.csv}")

    by_step: dict[int, dict[str, dict[str, str]]] = defaultdict(dict)
    for r in rows:
        by_step[int(r["step"])][r["region"]] = r

    print(" step | q6Applied   bulk%  iface%   wall% wallIf% corner% cornIf% | "
          "bulkRms ifaceRms wallRms | cells carrier/pressure")
    print("-" * 132)
    mean_fraction = {name: 0.0 for name in REGIONS}
    nsteps = 0
    diag_seconds = []
    for step in sorted(by_step):
        rs = by_step[step]
        missing = [name for name in REGIONS if name not in rs]
        if missing:
            raise SystemExit(f"step {step}: missing regions {missing}")
        q6a = float(rs["bulk"]["q6AppliedRms"])
        q6r = float(rs["bulk"]["q6AppliedRmsReconstructed"])
        if not math.isclose(q6a, q6r, rel_tol=2e-10, abs_tol=2e-12):
            raise SystemExit(f"step {step}: B0 reconstruction mismatch q6A={q6a} B0={q6r}")
        frac = {name: float(rs[name]["divSqFraction"]) for name in REGIONS}
        if abs(sum(frac.values()) - 1.0) > 2e-10 and q6a > 0.0:
            raise SystemExit(f"step {step}: divSq fractions sum to {sum(frac.values())}")
        for name in REGIONS:
            mean_fraction[name] += frac[name]
        nsteps += 1
        diag_seconds.append(float(rs["bulk"]["diagnosticSeconds"]))
        rms = {name: float(rs[name]["divRms"]) for name in REGIONS}
        carrier = int(rs["bulk"]["carrierCells"])
        pressure = int(rs["bulk"]["q6ReportedActiveCells"])
        cells = sum(int(rs[name]["regionCells"]) for name in REGIONS)
        print(
            f"{step:5d} | {q6a:9.3e} "
            f"{100*frac['bulk']:6.1f} {100*frac['interface']:7.1f} "
            f"{100*frac['wall']:7.1f} {100*frac['wall_interface']:7.1f} "
            f"{100*frac['corner']:7.1f} {100*frac['corner_interface']:7.1f} | "
            f"{rms['bulk']:7.2e} {rms['interface']:8.2e} {rms['wall']:7.2e} | "
            f"{cells:5d} {carrier:5d}/{pressure:5d}"
        )

    print("\n[0493x6h-B0] mean div^2 contribution over sampled steps:")
    print("  " + "  ".join(
        f"{name}={100*mean_fraction[name]/nsteps:.2f}%" for name in REGIONS
    ))
    print(
        "[0493x6h-B0] diagnostic cost: "
        f"mean={sum(diag_seconds)/len(diag_seconds):.3e}s "
        f"max={max(diag_seconds):.3e}s samples={len(diag_seconds)}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
