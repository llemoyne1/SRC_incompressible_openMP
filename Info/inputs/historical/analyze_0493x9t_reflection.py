#!/usr/bin/env python3
import argparse
import csv
import math
from pathlib import Path


def as_float(row, key, default=0.0):
    try:
        return float(row.get(key, default))
    except (TypeError, ValueError):
        return default


def as_int(row, key, default=0):
    try:
        return int(float(row.get(key, default)))
    except (TypeError, ValueError):
        return default


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--csv", required=True)
    args = ap.parse_args()
    path = Path(args.csv)
    if not path.is_file():
        raise SystemExit(f"[0493x9t-check] missing {path}")

    with path.open(newline="") as f:
        rows = list(csv.DictReader(f))
    if not rows:
        raise SystemExit(f"[0493x9t-check] no rows in {path}")

    crossings = sum(as_int(r, "crossings") for r in rows)
    selected = sum(as_int(r, "selectedReflections") for r in rows)
    transmitted = sum(as_int(r, "transmittedCrossings") for r in rows)
    applied = sum(as_int(r, "appliedReflections") for r in rows)
    unsupported = sum(as_int(r, "unsupportedReflections") for r in rows)
    converted = sum(as_int(r, "convertedParticles") for r in rows)
    ref_mass = sum(as_float(r, "reflectedMass") for r in rows)
    tx_mass = sum(as_float(r, "transmittedMass") for r in rows)
    max_dp = max(math.hypot(as_float(r, "deltaPx"), as_float(r, "deltaPy")) for r in rows)
    max_dke = max(abs(as_float(r, "deltaKineticEnergy")) for r in rows)
    rvals = [as_float(r, "reflectionFraction", math.nan) for r in rows]
    target = as_int(rows[-1], "evaporationTargetType", -1)

    finite = all(math.isfinite(x) for x in rvals if not math.isnan(x)) and math.isfinite(max_dp) and math.isfinite(max_dke)
    partition_ok = crossings == selected + transmitted
    r_one = all(abs(x - 1.0) <= 1e-14 for x in rvals if math.isfinite(x))
    r_one_ok = (not r_one) or transmitted == 0
    conversion_ok = target < 0 or converted == transmitted
    status = "PASS-structural" if finite and partition_ok and r_one_ok and conversion_ok else "FAIL"

    print("===== 0493x9t KINETIC REFLECTION AUDIT =====")
    print(f"file={path}")
    print(f"rows={len(rows)} reflectionFractionLast={rvals[-1]:.9g} evaporationTargetType={target}")
    print(f"crossings={crossings} selectedReflections={selected} transmitted={transmitted} partitionOK={int(partition_ok)}")
    print(f"appliedReflections={applied} unsupportedReflections={unsupported} convertedParticles={converted}")
    print(f"reflectedMass={ref_mass:.9g} transmittedMass={tx_mass:.9g}")
    print(f"max|deltaP|={max_dp:.6e} max|deltaKE|={max_dke:.6e}")
    if selected:
        print(f"applied/selected={applied/selected:.9g} unsupported/selected={unsupported/selected:.9g}")
    print(f"status={status}")


if __name__ == "__main__":
    main()
