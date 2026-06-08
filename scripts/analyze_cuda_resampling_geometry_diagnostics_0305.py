#!/usr/bin/env python3
import csv
import sys
from pathlib import Path

COLUMNS = [
    "triggerFlag","emptyWetCells","lowNCells","minNWet","maxNWet",
    "emptyBulkCells0305","emptyWallAdjacentCells0305","emptySolidAdjacentCells0305","emptyOpenAdjacentCells0305","emptyCornerAdjacentCells0305",
    "lowNBulkCells0305","lowNWallAdjacentCells0305","lowNSolidAdjacentCells0305","lowNOpenAdjacentCells0305","lowNCornerAdjacentCells0305",
    "wetBulkCells0305","wetWallAdjacentCells0305","wetSolidAdjacentCells0305","wetOpenAdjacentCells0305","wetCornerAdjacentCells0305",
    "highUBulkCells0305","highUWallAdjacentCells0305","highUSolidAdjacentCells0305","highUOpenAdjacentCells0305","highUCornerAdjacentCells0305",
    "maxAbsUBulk0305","maxAbsUWallAdjacent0305","maxAbsUSolidAdjacent0305","maxAbsUOpenAdjacent0305","maxAbsUCornerAdjacent0305",
    "depositKernelSeconds","flagKernelSeconds","downloadSeconds","totalSeconds",
]

def read_csv(path):
    if not path.exists() or path.stat().st_size == 0:
        return []
    with path.open(newline="") as fh:
        return list(csv.DictReader(fh))

def f(row, key, default=0.0):
    try:
        return float(row.get(key, default) or default)
    except Exception:
        return default

def i(row, key, default=0):
    try:
        return int(float(row.get(key, default) or default))
    except Exception:
        return default

def find_diag(run_root):
    p = Path(run_root) / "output" / "cuda_resampling_adaptive_flag_0304.csv"
    return p if p.exists() else None

def main():
    if len(sys.argv) != 3:
        print("usage: analyze_cuda_resampling_geometry_diagnostics_0305.py RUN_MANIFEST ART_DIR", file=sys.stderr)
        return 2
    manifest = Path(sys.argv[1])
    art = Path(sys.argv[2])
    runs = read_csv(manifest)
    per_rows = []
    ts_rows = []
    for run in runs:
        run_root = run.get("runRoot", "")
        diag = find_diag(run_root)
        rows = read_csv(diag) if diag else []
        out = dict(run)
        out["diagCsv"] = str(diag) if diag else ""
        out["diagRows"] = len(rows)
        if rows:
            last = rows[-1]
            out["firstStep"] = rows[0].get("step", "")
            out["lastStep"] = last.get("step", "")
            for key in COLUMNS:
                out["final_" + key] = last.get(key, "")
                vals = [f(r, key) for r in rows]
                out["max_" + key] = max(vals) if vals else ""
                out["sum_" + key] = sum(vals) if vals else ""
            for r in rows:
                tr = {
                    "caseName": run.get("caseName", ""),
                    "modeName": run.get("modeName", ""),
                    "runRoot": run_root,
                    "step": r.get("step", ""),
                }
                for key in COLUMNS:
                    if key in r:
                        tr[key] = r[key]
                ts_rows.append(tr)
        per_rows.append(out)
    art.mkdir(parents=True, exist_ok=True)
    per_path = art / "cuda_resampling_geometry_diagnostics_0305_per_run.csv"
    ts_path = art / "cuda_resampling_geometry_diagnostics_0305_timeseries.csv"
    if per_rows:
        keys = []
        for row in per_rows:
            for k in row.keys():
                if k not in keys:
                    keys.append(k)
        with per_path.open("w", newline="") as out_fh:
            w = csv.DictWriter(out_fh, fieldnames=keys)
            w.writeheader(); w.writerows(per_rows)
    if ts_rows:
        keys = []
        for row in ts_rows:
            for k in row.keys():
                if k not in keys:
                    keys.append(k)
        with ts_path.open("w", newline="") as out_fh:
            w = csv.DictWriter(out_fh, fieldnames=keys)
            w.writeheader(); w.writerows(ts_rows)
    print(f"[0305-geom-analyze] wrote {per_path}")
    print(f"[0305-geom-analyze] wrote {ts_path}")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
