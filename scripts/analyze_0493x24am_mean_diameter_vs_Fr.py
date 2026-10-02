#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
0493x24am — Mean-diameter cavity analysis for article figure

Definition used here:
    d_mean = 0.5 * (d_mouth + d_50%)

with
    d_mouth  = mouthWidthOverD * D
    d_50%    = width50DepthOverD * D

The plotted quantity is:
    y = d_mean / h

and the final figure is:
    y versus target modified Froude number Fr'

The figure is intentionally kept simple:
- x-axis : target modified Froude number Fr'
- y-axis : d/h
- vertical error bars only (time variability over retained frames)

No pandas.
"""

from __future__ import annotations

import argparse
import csv
import math
from collections import defaultdict
from pathlib import Path

import numpy as np
import matplotlib.pyplot as plt


def ffloat(x, default=math.nan):
    try:
        y = float(x)
        return y if math.isfinite(y) else default
    except Exception:
        return default


def fint(x, default=0):
    try:
        return int(float(x))
    except Exception:
        return default


def read_csv(path: Path):
    if not path.exists():
        raise SystemExit(f"[x24am] ERROR missing input: {path}")
    if path.stat().st_size == 0:
        raise SystemExit(f"[x24am] ERROR empty input: {path}")
    with path.open("r", newline="") as h:
        rows = list(csv.DictReader(h))
    if not rows:
        raise SystemExit(f"[x24am] ERROR no data rows in: {path}")
    return rows


def require_columns(rows, cols, path):
    got = set(rows[0].keys())
    missing = [c for c in cols if c not in got]
    if missing:
        raise SystemExit(
            f"[x24am] ERROR {path} missing columns: {', '.join(missing)}"
        )


def mean_std(vals):
    a = np.asarray([v for v in vals if math.isfinite(v)], float)
    if len(a) == 0:
        return math.nan, math.nan, 0
    return (
        float(np.mean(a)),
        float(np.std(a, ddof=1)) if len(a) > 1 else 0.0,
        int(len(a)),
    )


def publication_style():
    plt.rcParams.update({
        "font.family": "DejaVu Sans",
        "font.size": 10,
        "axes.labelsize": 11,
        "legend.fontsize": 9,
        "xtick.labelsize": 10,
        "ytick.labelsize": 10,
        "pdf.fonttype": 42,
        "ps.fonttype": 42,
        "lines.linewidth": 1.7,
        "lines.markersize": 6.0,
    })


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument(
        "--history",
        default="analysis/0493x24ae_article_interface_extended/frame_interface_history.csv",
        help="frame_interface_history.csv",
    )
    ap.add_argument(
        "--out",
        default="analysis/0493x24am_mean_diameter_vs_Fr",
        help="output directory",
    )
    ap.add_argument(
        "--max-fr",
        type=float,
        default=1.17,
        help="maximum Fr' to include in the quantitative figure (default: 1.17)",
    )
    ap.add_argument(
        "--min-h-over-D",
        type=float,
        default=0.05,
        help="reject frames with h/D below this threshold",
    )
    ap.add_argument(
        "--min-mouth-over-D",
        type=float,
        default=0.02,
        help="reject frames with mouth width/D below this threshold",
    )
    ap.add_argument(
        "--min-width50-over-D",
        type=float,
        default=0.02,
        help="reject frames with 50%%-depth width/D below this threshold",
    )
    ap.add_argument(
        "--annotate-fr",
        action="store_true",
        default=False,
        help="annotate each point with its Fr' value",
    )
    args = ap.parse_args()

    history_path = Path(args.history)
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)

    rows = read_csv(history_path)
    require_columns(
        rows,
        [
            "targetFr",
            "time",
            "includeForArticle",
            "hOverD_initialRef",
            "mouthWidthOverD",
            "width50DepthOverD",
        ],
        history_path,
    )

    frame_rows = []
    rejected = defaultdict(int)

    for r in rows:
        fr = ffloat(r.get("targetFr"))
        t = ffloat(r.get("time"))
        include = fint(r.get("includeForArticle"))
        hD = ffloat(r.get("hOverD_initialRef"))
        dMouth = ffloat(r.get("mouthWidthOverD"))
        d50 = ffloat(r.get("width50DepthOverD"))

        if not math.isfinite(fr) or fr > args.max_fr + 1e-12:
            continue
        if include != 1:
            rejected[(fr, "transient")] += 1
            continue
        if not math.isfinite(hD) or hD < args.min_h_over_D:
            rejected[(fr, "bad_h")] += 1
            continue
        if not math.isfinite(dMouth) or dMouth < args.min_mouth_over_D:
            rejected[(fr, "bad_mouth")] += 1
            continue
        if not math.isfinite(d50) or d50 < args.min_width50_over_D:
            rejected[(fr, "bad_width50")] += 1
            continue

        dMean = 0.5 * (dMouth + d50)
        y = dMean / hD if hD > 0 else math.nan

        if not math.isfinite(dMean) or not math.isfinite(y):
            rejected[(fr, "nonfinite")] += 1
            continue

        frame_rows.append({
            "targetFr": fr,
            "time": t,
            "hOverD": hD,
            "mouthWidthOverD": dMouth,
            "width50DepthOverD": d50,
            "meanDiameterOverD": dMean,
            "dOverH": y,
            "runRoot": r.get("runRoot", ""),
        })

    if not frame_rows:
        raise SystemExit("[x24am] ERROR no valid article frames after filtering")

    frame_rows.sort(key=lambda r: (r["targetFr"], r["time"]))

    frame_csv = out / "mean_diameter_frame_history.csv"
    with frame_csv.open("w", newline="") as h:
        fields = list(frame_rows[0].keys())
        w = csv.DictWriter(h, fieldnames=fields)
        w.writeheader()
        w.writerows(frame_rows)

    groups = defaultdict(list)
    for r in frame_rows:
        groups[round(r["targetFr"], 9)].append(r)

    summary = []
    for frkey in sorted(groups):
        rr = groups[frkey]
        fr = float(np.mean([r["targetFr"] for r in rr]))

        hmean, hstd, n = mean_std([r["hOverD"] for r in rr])
        dmouth_mean, dmouth_std, _ = mean_std([r["mouthWidthOverD"] for r in rr])
        d50_mean, d50_std, _ = mean_std([r["width50DepthOverD"] for r in rr])
        dmean_mean, dmean_std, _ = mean_std([r["meanDiameterOverD"] for r in rr])
        ymean, ystd, _ = mean_std([r["dOverH"] for r in rr])

        summary.append({
            "targetFr": fr,
            "frames": n,
            "timeStart": min(r["time"] for r in rr),
            "timeEnd": max(r["time"] for r in rr),
            "meanHOverD": hmean,
            "stdHOverD": hstd,
            "meanMouthWidthOverD": dmouth_mean,
            "stdMouthWidthOverD": dmouth_std,
            "meanWidth50DepthOverD": d50_mean,
            "stdWidth50DepthOverD": d50_std,
            "meanMeanDiameterOverD": dmean_mean,
            "stdMeanDiameterOverD": dmean_std,
            "mean_dOverH": ymean,
            "std_dOverH": ystd,
        })

    summary_csv = out / "mean_diameter_summary.csv"
    with summary_csv.open("w", newline="") as h:
        fields = list(summary[0].keys())
        w = csv.DictWriter(h, fieldnames=fields)
        w.writeheader()
        w.writerows(summary)

    publication_style()

    frs = np.array([r["targetFr"] for r in summary], float)
    ys = np.array([r["mean_dOverH"] for r in summary], float)
    yerr = np.array([r["std_dOverH"] for r in summary], float)

    fig, ax = plt.subplots(figsize=(6.2, 4.6))
    ax.errorbar(
        frs,
        ys,
        yerr=yerr,
        fmt="o-",
        capsize=3.0,
        label="SRC/MPCD",
    )

    if args.annotate_fr:
        for x, y in zip(frs, ys):
            ax.annotate(
                f"{x:g}",
                (x, y),
                xytext=(4, 4),
                textcoords="offset points",
                fontsize=8,
            )

    ax.set_xlabel(r"Target modified Froude number $Fr'$")
    ax.set_ylabel(r"$d/h$")
    ax.set_xlim(left=0.0)
    ax.set_ylim(bottom=0.0)
    ax.grid(True, alpha=0.25)
    ax.legend(loc="best")
    fig.tight_layout()
    fig.savefig(
        out / "fig_mean_diameter_over_h_vs_target_Fr.pdf",
        format="pdf",
        bbox_inches="tight",
    )
    plt.close(fig)

    report = out / "report.txt"
    with report.open("w") as h:
        h.write("0493x24am — Mean-diameter analysis\n")
        h.write("==================================\n\n")
        h.write("Definition used:\n")
        h.write("  d_mean = 0.5 * (d_mouth + d_50%)\n")
        h.write("  plotted quantity = d_mean / h\n\n")
        h.write("Figure:\n")
        h.write("  y-axis: d/h\n")
        h.write("  x-axis: target modified Froude number Fr'\n\n")
        h.write("Case summary\n")
        h.write("------------\n")
        for r in summary:
            h.write(
                f"Fr'={r['targetFr']:.9g}  N={r['frames']}  "
                f"d/h={r['mean_dOverH']:.6g} +/- {r['std_dOverH']:.4g}  "
                f"d_mean/D={r['meanMeanDiameterOverD']:.6g} +/- {r['stdMeanDiameterOverD']:.4g}  "
                f"h/D={r['meanHOverD']:.6g} +/- {r['stdHOverD']:.4g}\n"
            )

        h.write("\nRejected frames\n")
        h.write("---------------\n")
        if rejected:
            for (fr, reason), count in sorted(rejected.items()):
                h.write(f"Fr'={fr:g} {reason}: {count}\n")
        else:
            h.write("none\n")

    print("[x24am] input :", history_path)
    print("[x24am] valid frames:", len(frame_rows))
    print("[x24am] cases:", len(summary))
    print("[x24am] wrote:")
    print(" ", frame_csv)
    print(" ", summary_csv)
    print(" ", out / "fig_mean_diameter_over_h_vs_target_Fr.pdf")
    print(" ", report)


if __name__ == "__main__":
    main()