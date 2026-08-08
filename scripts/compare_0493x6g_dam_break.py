#!/usr/bin/env python3
"""Compare matched zero-pGamma and EOS-pg dam-break qualification series."""
from __future__ import annotations

import argparse
import csv
import json
import math
import re
from pathlib import Path


def load(path: Path) -> list[dict[str, str]]:
    with path.open(newline="") as stream:
        rows = list(csv.DictReader(stream))
    if not rows:
        raise RuntimeError(f"empty CSV: {path}")
    return rows


def elapsed(root: Path) -> float | None:
    files = list((root / "logs").glob("*.time"))
    if not files:
        return None
    text = files[0].read_text(errors="replace")
    m = re.search(r"elapsed=([0-9.eE+-]+)", text)
    return float(m.group(1)) if m else None


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--zero", type=Path, required=True)
    ap.add_argument("--eos", type=Path, required=True)
    ap.add_argument("--json", type=Path, required=True)
    args = ap.parse_args()
    zr = load(args.zero / "liquid_gas_free_surface_0493x5b.csv")
    er = load(args.eos / "liquid_gas_free_surface_0493x5b.csv")
    zmap = {int(r["step"]): r for r in zr}
    emap = {int(r["step"]): r for r in er}
    steps = sorted(set(zmap) & set(emap))
    if not steps:
        raise RuntimeError("no common dam-break output steps")
    metrics = [
        "liquidCenterOfMassX", "liquidCenterOfMassY", "liquidMeanVx", "liquidMeanVy",
        "liquidVelocityRms", "gasCenterOfMassX", "gasCenterOfMassY", "gasVelocityRms",
        "liquidSupportCellsOffline", "mixedCells", "frontX995", "liquidPopulationMaxOccupied",
        "gasPopulationMaxOccupied",
    ]
    max_abs = {m: 0.0 for m in metrics}
    for step in steps:
        for m in metrics:
            dz = float(emap[step][m]) - float(zmap[step][m])
            if not math.isfinite(dz):
                raise RuntimeError(f"step {step}: non-finite delta for {m}")
            max_abs[m] = max(max_abs[m], abs(dz))
    last = steps[-1]
    final = {
        m: {
            "zero": float(zmap[last][m]),
            "eos": float(emap[last][m]),
            "delta": float(emap[last][m]) - float(zmap[last][m]),
        }
        for m in metrics
    }
    tz = elapsed(args.zero)
    te = elapsed(args.eos)
    report = {
        "status": "PASS-like",
        "commonSteps": len(steps),
        "finalStep": last,
        "zeroElapsedSeconds": tz,
        "eosElapsedSeconds": te,
        "elapsedRatioEosToZero": (te / tz if tz and te else None),
        "maxAbsoluteDifferences": max_abs,
        "final": final,
    }
    args.json.parent.mkdir(parents=True, exist_ok=True)
    args.json.write_text(json.dumps(report, indent=2) + "\n")
    ratio = report["elapsedRatioEosToZero"]
    ratio_text = f"{ratio:.3f}" if isinstance(ratio, float) else "n/a"
    print(
        "[0493x6g-dam-break-compare] "
        f"status=PASS-like steps={len(steps)} final={last} "
        f"elapsedRatio={ratio_text} "
        f"dFront995={final['frontX995']['delta']:.6e} "
        f"dCOM=({final['liquidCenterOfMassX']['delta']:.6e},"
        f"{final['liquidCenterOfMassY']['delta']:.6e})"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
