#!/usr/bin/env python3
import argparse
import csv
from pathlib import Path
from statistics import mean


def f(row, key):
    return float(row[key])


def main():
    ap = argparse.ArgumentParser(description="Summarize 0493x7a CUDA-resident virial density audit")
    ap.add_argument("--csv", required=True, type=Path)
    ap.add_argument("--geometry", type=Path, default=None,
                    help="optional x6c geometry CSV for overfill summary")
    args = ap.parse_args()
    with args.csv.open(newline="") as fh:
        rows = list(csv.DictReader(fh))
    if not rows:
        raise SystemExit("[0493x7a] empty audit")

    # 0493x7b adds continuum-grid diagnostics while retaining backward
    # compatibility with x7a CSVs produced before these columns existed.
    if all(k in rows[0] for k in ("effectiveVirialSpeed", "dx", "dy", "virialCFLx", "virialCFLy")):
        r0 = rows[0]
        print(
            "[0493x7b] continuum EOS: "
            f"K={f(r0,'kVirial'):.9g} [code velocity^2] "
            f"beta={f(r0,'betaEOS'):.9g} "
            f"cEff={f(r0,'effectiveVirialSpeed'):.9g} "
            f"dx={f(r0,'dx'):.9g} dy={f(r0,'dy'):.9g} "
            f"CFL=({f(r0,'virialCFLx'):.6g},{f(r0,'virialCFLy'):.6g}) "
            "gradient=physical"
        )
    print(" step | bulk/pressure | fillRms   pVirRms   kickRaw   kickCorr  |dP|before   corr=(vx,vy)")
    print("-" * 108)
    for r in rows:
        step = int(r["step"])
        pc = int(r["pressureCells"])
        bc = int(r["activeBulkCells"])
        print(
            f"{step:5d} | {bc:5d}/{pc:5d} | "
            f"{f(r,'fillDefectRms'):8.3e} {f(r,'virialPressureRms'):8.3e} "
            f"{f(r,'rawKickMassWeightedRms'):8.3e} {f(r,'correctedKickMassWeightedRms'):8.3e} "
            f"{f(r,'momentumResidualBefore'):11.3e}   "
            f"({f(r,'momentumCorrectionVx'):+.3e},{f(r,'momentumCorrectionVy'):+.3e})"
        )

    developed = rows[1:] if len(rows) > 1 else rows
    mean_fill = mean(f(r, "fillDefectRms") for r in developed)
    mean_kick = mean(f(r, "correctedKickMassWeightedRms") for r in developed)
    mean_bulk_fraction = mean(
        int(r["activeBulkCells"]) / max(1, int(r["pressureCells"])) for r in developed
    )
    print()
    print(
        "[0493x7a] developed means: "
        f"fillRms={mean_fill:.6e} correctedKickRms={mean_kick:.6e} "
        f"bulk/pressure={100.0*mean_bulk_fraction:.2f}%"
    )
    last = rows[-1]
    print(
        "[0493x7a] final: "
        f"step={last['step']} fillRms={f(last,'fillDefectRms'):.6e} "
        f"correctedKickRms={f(last,'correctedKickMassWeightedRms'):.6e}"
    )

    if args.geometry is not None:
        with args.geometry.open(newline="") as fh:
            geom = list(csv.DictReader(fh))
        if not geom:
            raise SystemExit("[0493x7a] empty geometry audit")
        glast = geom[-1]
        raw = f(glast, "rawFillSum")
        bounded = f(glast, "boundedGeometrySourceSum")
        clipped = int(glast["boundedGeometryClippedCells"])
        excess = raw - bounded
        print(
            "[0493x7a] geometry final: "
            f"step={glast['step']} raw={raw:.6f} bounded={bounded:.6f} "
            f"excess={excess:.6f} clippedCells={clipped}"
        )


if __name__ == "__main__":
    main()
