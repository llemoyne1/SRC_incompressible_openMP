#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
0493x24am-v2 — Mean-diameter Li-style cavity-shape analysis.

Definition of cavity diameter
-----------------------------
For every retained frame:

    d_mean = 0.5 * (d_mouth + d_50%)

where:
    d_mouth / D = mouthWidthOverD
    d_50%   / D = width50DepthOverD

The plotted ordinate is:

    Y_k = d_mean,k / h_k

The Li-style abscissa is:

    X_k = sqrt[(4/pi) Fr' / (h_k/D)^3]

which is the single-jet form of:

    X = sqrt[M / (rho_l g h^3)]

for the Sato modified-Froude definition used in the campaign.

The final article point for each Fr' is obtained frame-by-frame:

    Xbar = mean(X_k)
    Ybar = mean(Y_k)

This preserves the effect of cavity oscillations instead of reconstructing the
coordinates from separate time-averaged h and d.

Reference lines
---------------
    parabola : d/h = sqrt(16/pi) X
    ellipse  : d/h = sqrt(12/pi) X

The final PDF is intentionally light:
- no uncertainty whiskers,
- y-axis label simply "d/h",
- x-axis in Li et al. form,
- theoretical ellipse/parabola lines,
- SRC/MPCD points and SRC fit.

Input
-----
frame_interface_history.csv from x24ae

Required columns:
    targetFr
    time
    includeForArticle
    hOverD_initialRef
    mouthWidthOverD
    width50DepthOverD

Usage
-----
python3 scripts/analyze_0493x24am_v2_mean_diameter_li.py \
  --history analysis/0493x24ae_article_interface_extended/frame_interface_history.csv \
  --out analysis/0493x24am_v2_mean_diameter_li

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


A_PARABOLA = math.sqrt(16.0 / math.pi)
A_ELLIPSE = math.sqrt(12.0 / math.pi)


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
        raise SystemExit(f"[x24am-v2] ERROR missing input: {path}")
    if path.stat().st_size == 0:
        raise SystemExit(f"[x24am-v2] ERROR empty input: {path}")
    with path.open("r", newline="") as h:
        rows = list(csv.DictReader(h))
    if not rows:
        raise SystemExit(f"[x24am-v2] ERROR no data rows in: {path}")
    return rows


def require_columns(rows, cols, path):
    got = set(rows[0].keys())
    missing = [c for c in cols if c not in got]
    if missing:
        raise SystemExit(
            f"[x24am-v2] ERROR {path} missing columns: {', '.join(missing)}"
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


def fit_origin(x, y):
    x = np.asarray(x, float)
    y = np.asarray(y, float)
    mask = np.isfinite(x) & np.isfinite(y)
    x = x[mask]
    y = y[mask]
    if len(x) < 2 or np.dot(x, x) <= 0.0:
        return math.nan, math.nan
    slope = float(np.dot(x, y) / np.dot(x, x))
    pred = slope * x
    ssr = float(np.sum((y - pred) ** 2))
    sst = float(np.sum((y - np.mean(y)) ** 2))
    r2 = 1.0 - ssr / sst if sst > 0.0 else math.nan
    return slope, r2


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
        help="x24ae frame_interface_history.csv",
    )
    ap.add_argument(
        "--out",
        default="analysis/0493x24am_v2_mean_diameter_li",
        help="output directory",
    )
    ap.add_argument(
        "--max-fr",
        type=float,
        default=1.17,
        help="maximum Fr' included in the quantitative plot",
    )
    ap.add_argument(
        "--min-h-over-D",
        type=float,
        default=0.05,
        help="reject pathological frames with h/D below this value",
    )
    ap.add_argument(
        "--min-mouth-over-D",
        type=float,
        default=0.02,
        help="reject frames with undefined/negligible mouth width",
    )
    ap.add_argument(
        "--min-width50-over-D",
        type=float,
        default=0.02,
        help="reject frames with undefined/negligible width at 50%% depth",
    )
    ap.add_argument(
        "--annotate-fr",
        action="store_true",
        default=True,
        help="annotate points with Fr' values (default: on)",
    )
    ap.add_argument(
        "--no-annotate-fr",
        action="store_false",
        dest="annotate_fr",
        help="disable Fr' point labels",
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
        d_mouth_D = ffloat(r.get("mouthWidthOverD"))
        d50_D = ffloat(r.get("width50DepthOverD"))

        if not math.isfinite(fr) or fr > args.max_fr + 1e-12:
            continue
        if include != 1:
            rejected[(fr, "transient")] += 1
            continue
        if not math.isfinite(hD) or hD < args.min_h_over_D:
            rejected[(fr, "bad_h")] += 1
            continue
        if not math.isfinite(d_mouth_D) or d_mouth_D < args.min_mouth_over_D:
            rejected[(fr, "bad_mouth")] += 1
            continue
        if not math.isfinite(d50_D) or d50_D < args.min_width50_over_D:
            rejected[(fr, "bad_width50")] += 1
            continue

        dmean_D = 0.5 * (d_mouth_D + d50_D)

        X = math.sqrt((4.0 / math.pi) * fr / (hD ** 3))
        Y = dmean_D / hD

        if not (math.isfinite(X) and math.isfinite(Y)):
            rejected[(fr, "nonfinite_XY")] += 1
            continue

        frame_rows.append({
            "targetFr": fr,
            "time": t,
            "hOverD": hD,
            "mouthWidthOverD": d_mouth_D,
            "width50DepthOverD": d50_D,
            "meanDiameterOverD": dmean_D,
            "X_Li": X,
            "Y_dOverh": Y,
            "runRoot": r.get("runRoot", ""),
        })

    if not frame_rows:
        raise SystemExit("[x24am-v2] ERROR no valid article frames after filtering")

    frame_rows.sort(key=lambda r: (r["targetFr"], r["time"]))

    frame_csv = out / "li_mean_diameter_frame_history.csv"
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

        Xmean, Xstd, n = mean_std([r["X_Li"] for r in rr])
        Ymean, Ystd, _ = mean_std([r["Y_dOverh"] for r in rr])

        hmean, hstd, _ = mean_std([r["hOverD"] for r in rr])
        dmouth_mean, dmouth_std, _ = mean_std([r["mouthWidthOverD"] for r in rr])
        d50_mean, d50_std, _ = mean_std([r["width50DepthOverD"] for r in rr])
        dmean_mean, dmean_std, _ = mean_std([r["meanDiameterOverD"] for r in rr])

        para = A_PARABOLA * Xmean
        ell = A_ELLIPSE * Xmean

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

            "meanFramewiseX_Li": Xmean,
            "stdFramewiseX_Li": Xstd,

            "meanFramewiseY_dOverh": Ymean,
            "stdFramewiseY_dOverh": Ystd,

            "parabolaPredictionAtMeanX": para,
            "ellipsePredictionAtMeanX": ell,
            "YoverParabola": Ymean / para if para > 0 else math.nan,
            "YoverEllipse": Ymean / ell if ell > 0 else math.nan,
        })

    summary_csv = out / "li_mean_diameter_summary.csv"
    with summary_csv.open("w", newline="") as h:
        fields = list(summary[0].keys())
        w = csv.DictWriter(h, fieldnames=fields)
        w.writeheader()
        w.writerows(summary)

    xs = np.array([r["meanFramewiseX_Li"] for r in summary], float)
    ys = np.array([r["meanFramewiseY_dOverh"] for r in summary], float)
    frs = np.array([r["targetFr"] for r in summary], float)

    slope, r2 = fit_origin(xs, ys)

    publication_style()

    xmax = 1.12 * float(np.nanmax(xs))
    xx = np.linspace(0.0, xmax, 300)

    fig, ax = plt.subplots(figsize=(6.5, 5.0))

    ax.plot(
        xx,
        A_PARABOLA * xx,
        "--",
        label=rf"Parabola: $d/h=\sqrt{{16/\pi}}\,X$",
    )
    ax.plot(
        xx,
        A_ELLIPSE * xx,
        "-.",
        label=rf"Ellipse: $d/h=\sqrt{{12/\pi}}\,X$",
    )
    ax.plot(
        xx,
        slope * xx,
        ":",
        label=f"SRC fit: d/h = {slope:.3f} X",
    )

    # Final article points: no uncertainty whiskers.
    ax.plot(xs, ys, "o", label="SRC/MPCD points")

    if args.annotate_fr:
        for x, y, fr in zip(xs, ys, frs):
            ax.annotate(
                f"{fr:g}",
                (x, y),
                xytext=(4, 4),
                textcoords="offset points",
                fontsize=8,
            )

    ax.set_xlabel(r"$\left(M/(\rho_l g h^3)\right)^{1/2}$")
    ax.set_ylabel(r"$d/h$")
    ax.set_xlim(left=0.0)
    ax.set_ylim(bottom=0.0)
    ax.grid(True, alpha=0.25)
    ax.legend(loc="best")

    fig.tight_layout()
    fig.savefig(
        out / "fig_li_mean_diameter_shape_map.pdf",
        format="pdf",
        bbox_inches="tight",
    )
    plt.close(fig)

    report = out / "report.txt"
    with report.open("w") as h:
        h.write("0493x24am-v2 — Li analysis with mean cavity diameter\n")
        h.write("===================================================\n\n")
        h.write(
            "Framewise definitions:\n"
            "  d_mean/D = 0.5 * (mouthWidthOverD + width50DepthOverD)\n"
            "  X = sqrt((4/pi) * Fr' / (h/D)^3)\n"
            "  Y = d_mean/h\n\n"
        )
        h.write(
            f"Parabola slope sqrt(16/pi) = {A_PARABOLA:.8f}\n"
            f"Ellipse slope  sqrt(12/pi) = {A_ELLIPSE:.8f}\n"
            f"SRC mean-diameter fit through origin = {slope:.8f}, R2={r2:.8f}\n\n"
        )

        h.write("Case summary\n")
        h.write("------------\n")
        for r in summary:
            h.write(
                f"Fr'={r['targetFr']:.9g}  N={r['frames']}  "
                f"Xbar={r['meanFramewiseX_Li']:.6g} +/- {r['stdFramewiseX_Li']:.4g}  "
                f"d/h={r['meanFramewiseY_dOverh']:.6g} +/- {r['stdFramewiseY_dOverh']:.4g}  "
                f"dmean/D={r['meanMeanDiameterOverD']:.6g}  "
                f"Y/parabola={r['YoverParabola']:.4f}  "
                f"Y/ellipse={r['YoverEllipse']:.4f}\n"
            )

        h.write("\nRejected frames\n")
        h.write("---------------\n")
        if rejected:
            for (fr, reason), count in sorted(rejected.items()):
                h.write(f"Fr'={fr:g} {reason}: {count}\n")
        else:
            h.write("none\n")

    print("[x24am-v2] input :", history_path)
    print("[x24am-v2] valid frames:", len(frame_rows))
    print("[x24am-v2] cases:", len(summary))
    print(
        f"[x24am-v2] SRC mean-diameter fit: d/h = {slope:.6f} X, "
        f"R2={r2:.6f}"
    )
    print("[x24am-v2] wrote:")
    print(" ", frame_csv)
    print(" ", summary_csv)
    print(" ", out / "fig_li_mean_diameter_shape_map.pdf")
    print(" ", report)


if __name__ == "__main__":
    main()
