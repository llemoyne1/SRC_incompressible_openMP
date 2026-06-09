#!/usr/bin/env python3
import csv
import sys
from pathlib import Path


def fnum(row, key, default=0.0):
    try:
        return float(row.get(key, default) or default)
    except Exception:
        return float(default)


def inum(row, key, default=0):
    try:
        return int(float(row.get(key, default) or default))
    except Exception:
        return int(default)


def read_csv(path):
    if not path.exists():
        return []
    with path.open(newline="") as fh:
        return list(csv.DictReader(fh))


def write_csv(path, rows, fields):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=fields)
        w.writeheader()
        for row in rows:
            w.writerow(row)


def main():
    if len(sys.argv) != 3:
        print("usage: analyze_cuda_resampling_outlier_diagnostics_0306.py manifest.csv artifact_dir", file=sys.stderr)
        return 2
    manifest_path = Path(sys.argv[1])
    art_dir = Path(sys.argv[2])
    manifest = read_csv(manifest_path)
    per_rows = []
    ts_rows = []
    worst_rows = []

    for mr in manifest:
        run_root = Path(mr["runRoot"])
        flag_csv = run_root / "output" / "cuda_resampling_adaptive_flag_0304.csv"
        rows = read_csv(flag_csv)
        if not rows:
            per_rows.append({
                "caseName": mr.get("caseName", ""),
                "modeName": mr.get("modeName", ""),
                "runRoot": str(run_root),
                "exitCode": mr.get("exitCode", ""),
                "rows": 0,
            })
            continue
        for r in rows:
            r2 = dict(r)
            r2["caseName"] = mr.get("caseName", "")
            r2["modeName"] = mr.get("modeName", "")
            r2["runRoot"] = str(run_root)
            ts_rows.append(r2)
            worst_rows.append({
                "caseName": mr.get("caseName", ""),
                "modeName": mr.get("modeName", ""),
                "step": r.get("step", ""),
                "worstCellI0306": r.get("worstCellI0306", ""),
                "worstCellJ0306": r.get("worstCellJ0306", ""),
                "worstCellN0306": r.get("worstCellN0306", ""),
                "worstCellMass0306": r.get("worstCellMass0306", ""),
                "worstCellUx0306": r.get("worstCellUx0306", ""),
                "worstCellUy0306": r.get("worstCellUy0306", ""),
                "worstCellAbsU0306": r.get("worstCellAbsU0306", ""),
                "worstCellKrel0306": r.get("worstCellKrel0306", ""),
                "worstCellKBT0306": r.get("worstCellKBT0306", ""),
                "worstCellBulk0306": r.get("worstCellBulk0306", ""),
                "worstCellWallAdjacent0306": r.get("worstCellWallAdjacent0306", ""),
                "worstCellSolidAdjacent0306": r.get("worstCellSolidAdjacent0306", ""),
                "worstCellOpenAdjacent0306": r.get("worstCellOpenAdjacent0306", ""),
                "worstCellCornerAdjacent0306": r.get("worstCellCornerAdjacent0306", ""),
            })

        last = rows[-1]
        def maxcol(key): return max(fnum(r, key) for r in rows)
        def sumcol(key): return sum(fnum(r, key) for r in rows)
        per_rows.append({
            "caseName": mr.get("caseName", ""),
            "modeName": mr.get("modeName", ""),
            "runRoot": str(run_root),
            "exitCode": mr.get("exitCode", ""),
            "rows": len(rows),
            "finalEmptyWetCells": last.get("emptyWetCells", ""),
            "maxEmptyWetCells": maxcol("emptyWetCells"),
            "finalLowNCells": last.get("lowNCells", ""),
            "maxLowNCells": maxcol("lowNCells"),
            "finalCellsN1": last.get("cellsN1_0306", ""),
            "maxCellsN1": maxcol("cellsN1_0306"),
            "finalCellsN2": last.get("cellsN2_0306", ""),
            "maxCellsN2": maxcol("cellsN2_0306"),
            "finalHighUN1": last.get("highUN1_0306", ""),
            "maxHighUN1": maxcol("highUN1_0306"),
            "finalHighUNgeNmin": last.get("highUNgeNmin_0306", ""),
            "maxHighUNgeNmin": maxcol("highUNgeNmin_0306"),
            "finalMaxAbsUN1": last.get("maxAbsUN1_0306", ""),
            "maxMaxAbsUN1": maxcol("maxAbsUN1_0306"),
            "finalMaxAbsUNgeNmin": last.get("maxAbsUNgeNmin_0306", ""),
            "maxMaxAbsUNgeNmin": maxcol("maxAbsUNgeNmin_0306"),
            "finalWorstAbsU": last.get("worstCellAbsU0306", ""),
            "maxWorstAbsU": maxcol("worstCellAbsU0306"),
            "finalWorstN": last.get("worstCellN0306", ""),
            "finalWorstWallAdjacent": last.get("worstCellWallAdjacent0306", ""),
            "finalWorstSolidAdjacent": last.get("worstCellSolidAdjacent0306", ""),
            "finalWorstBulk": last.get("worstCellBulk0306", ""),
            "maxKBTBulk": maxcol("maxKBTBulk0306"),
            "maxKBTWallAdjacent": maxcol("maxKBTWallAdjacent0306"),
            "maxKBTSolidAdjacent": maxcol("maxKBTSolidAdjacent0306"),
            "sumHighUN1": sumcol("highUN1_0306"),
            "sumHighUNgeNmin": sumcol("highUNgeNmin_0306"),
        })

    per_fields = sorted({k for row in per_rows for k in row.keys()})
    # keep a few fields first
    first = ["caseName", "modeName", "exitCode", "rows", "runRoot"]
    per_fields = first + [k for k in per_fields if k not in first]
    write_csv(art_dir / "cuda_resampling_outlier_diagnostics_0306_per_run.csv", per_rows, per_fields)

    if ts_rows:
        ts_fields = ["caseName", "modeName", "runRoot"] + [k for k in ts_rows[0].keys() if k not in ("caseName", "modeName", "runRoot")]
        write_csv(art_dir / "cuda_resampling_outlier_diagnostics_0306_timeseries.csv", ts_rows, ts_fields)
    if worst_rows:
        worst_fields = list(worst_rows[0].keys())
        write_csv(art_dir / "cuda_resampling_outlier_diagnostics_0306_worst_cells.csv", worst_rows, worst_fields)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
