#!/usr/bin/env python3
import argparse
import csv
import math
from pathlib import Path


def finite(x):
    try:
        v=float(x)
        return v if math.isfinite(v) else math.nan
    except Exception:
        return math.nan


def main():
    ap=argparse.ArgumentParser(description="Summarize 0493x7c Q6 density-RHS relaxation")
    ap.add_argument("--q6", required=True)
    ap.add_argument("--geometry", required=True)
    args=ap.parse_args()

    with Path(args.q6).open(newline="") as f:
        qrows=list(csv.DictReader(f))
    # projected liquid only
    qrows=[r for r in qrows if finite(r.get("q6Strength",0))>0 and int(float(r.get("activeCells",0)))>0]
    if not qrows:
        raise SystemExit("[0493x7c] no active projected-species rows")

    with Path(args.geometry).open(newline="") as f:
        grows=list(csv.DictReader(f))
    if not grows:
        raise SystemExit("[0493x7c] no geometry rows")

    beta=finite(qrows[-1].get("q6DensityRelaxationBeta",0))
    tau=finite(qrows[-1].get("q6DensityRelaxationTime",0))
    target=[finite(r.get("densityRelaxationTargetDivRms",0)) for r in qrows]
    resid=[finite(r.get("divAfterProjectedFaceFluxRms",0)) for r in qrows]
    applied=[finite(r.get("divAfterAppliedCellVelocityRms",0)) for r in qrows]
    target=[v for v in target if math.isfinite(v)]
    resid=[v for v in resid if math.isfinite(v)]
    applied=[v for v in applied if math.isfinite(v)]

    g=grows[-1]
    raw=finite(g.get("rawFillSum", math.nan))
    bounded=finite(g.get("boundedGeometrySourceSum", math.nan))
    excess=raw-bounded if math.isfinite(raw) and math.isfinite(bounded) else math.nan
    final=qrows[-1]
    tau_text=f" tau={tau:.9g}" if math.isfinite(tau) and tau > 0 else ""
    print(f"[0493x7c] beta={beta:.9g}{tau_text} rows={len(qrows)} finalStep={final.get('step','?')}")
    print(f"[0493x7c] targetDivRms final={target[-1]:.6e} mean={sum(target)/len(target):.6e}")
    print(f"[0493x7c] constraintResidualRms final={resid[-1]:.6e} mean={sum(resid)/len(resid):.6e}")
    if applied:
        print(f"[0493x7c] q6AppliedActualDivRms final={applied[-1]:.6e} mean={sum(applied)/len(applied):.6e}")
    print(f"[0493x7c] geometry final raw={raw:.6f} bounded={bounded:.6f} excess={excess:.6f}")


if __name__ == "__main__":
    main()
