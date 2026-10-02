#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
0493x24al — Li-style framewise cavity-shape analysis using width at 50% depth.

This is the direct variant requested for the article comparison:
- X is unchanged:
      X_k = sqrt[(4/pi) Fr' / (h_k/D)^3]
- d is now the instantaneous cavity width measured at 50% of the
  instantaneous cavity depth:
      d_k/D = width50DepthOverD
- Y becomes:
      Y_k = (d_k/D) / (h_k/D)

Then the plotted article point is:
      Xbar = mean(X_k)
      Ybar = mean(Y_k)

The article figure has no uncertainty whiskers, but the temporal standard
deviations are retained in the CSV/report.

Theoretical reference lines:
    parabola : d/h = sqrt(16/pi) X
    ellipse  : d/h = sqrt(12/pi) X

Input:
    frame_interface_history.csv from x24ae

Required columns:
    targetFr
    time
    includeForArticle
    hOverD_initialRef
    width50DepthOverD

Usage:
python3 scripts/analyze_0493x24al_li_framewise_width50.py \
  --history analysis/0493x24ae_article_interface_extended/frame_interface_history.csv \
  --out analysis/0493x24al_li_framewise_width50

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
        raise SystemExit(f"[x24al] ERROR missing input: {path}")
    if path.stat().st_size == 0:
        raise SystemExit(f"[x24al] ERROR empty input: {path}")
    with path.open("r", newline="") as h:
        rows = list(csv.DictReader(h))
    if not rows:
        raise SystemExit(f"[x24al] ERROR no data rows in: {path}")
    return rows


def require_columns(rows, cols, path):
    got = set(rows[0].keys())
    missing = [c for c in cols if c not in got]
    if missing:
        raise SystemExit(
            f"[x24al] ERROR {path} missing columns: {', '.join(missing)}"
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
    r2 = 1.0 - ssr / sst if sst > 0 else math.nan
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
        default="analysis/0493x24al_li_framewise_width50",
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
        "--min-width50-over-D",
        type=float,
        default=0.05,
        help="reject frames with undefined/negligible width at 50% depth",
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
        dD = ffloat(r.get("width50DepthOverD"))

        if not math.isfinite(fr) or fr > args.max_fr + 1e-12:
            continue
        if include != 1:
            rejected[(fr, "transient")] += 1
            continue
        if not math.isfinite(hD) or hD < args.min_h_over_D:
            rejected[(fr, "bad_h")] += 1
            continue
        if not math.isfinite(dD) or dD < args.min_width50_over_D:
            rejected[(fr, "bad_width50")] += 1
            continue

        X = math.sqrt((4.0 / math.pi) * fr / (hD ** 3))
        Y = dD / hD

        if not (math.isfinite(X) and math.isfinite(Y)):
            rejected[(fr, "nonfinite_XY")] += 1
            continue

        frame_rows.append({
            "targetFr": fr,
            "time": t,
            "hOverD": hD,
            "width50DepthOverD": dD,
            "X": X,
            "Y_dOverh": Y,
            "runRoot": r.get("runRoot", ""),
        })

    if not frame_rows:
        raise SystemExit("[x24al] ERROR no valid article frames after filtering")

    frame_rows.sort(key=lambda r: (r["targetFr"], r["time"]))

    frame_csv = out / "li_framewise_width50_history.csv"
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

        Xmean, Xstd, n = mean_std([r["X"] for r in rr])
        Ymean, Ystd, _ = mean_std([r["Y_dOverh"] for r in rr])

        hmean, hstd, _ = mean_std([r["hOverD"] for r in rr])
        dmean, dstd, _ = mean_std([r["width50DepthOverD"] for r in rr])

        X_old = (
            math.sqrt((4.0 / math.pi) * fr / (hmean ** 3))
            if math.isfinite(hmean) and hmean > 0
            else math.nan
        )
        Y_old = dmean / hmean if math.isfinite(hmean) and hmean > 0 else math.nan

        para = A_PARABOLA * Xmean
        ell = A_ELLIPSE * Xmean

        summary.append({
            "targetFr": fr,
            "frames": n,
            "timeStart": min(r["time"] for r in rr),
            "timeEnd": max(r["time"] for r in rr),

            "meanHOverD": hmean,
            "stdHOverD": hstd,
            "meanWidth50DepthOverD": dmean,
            "stdWidth50DepthOverD": dstd,

            "meanFramewiseX": Xmean,
            "stdFramewiseX": Xstd,
            "meanFramewiseY_dOverh": Ymean,
            "stdFramewiseY_dOverh": Ystd,

            "aggregateMeansX_old": X_old,
            "aggregateMeansY_old": Y_old,

            "deltaX_framewise_minus_old": Xmean - X_old,
            "relativeDeltaX": (
                (Xmean - X_old) / X_old
                if math.isfinite(X_old) and X_old != 0
                else math.nan
            ),
            "deltaY_framewise_minus_old": Ymean - Y_old,
            "relativeDeltaY": (
                (Ymean - Y_old) / Y_old
                if math.isfinite(Y_old) and Y_old != 0
                else math.nan
            ),

            "parabolaPredictionAtMeanX": para,
            "ellipsePredictionAtMeanX": ell,
            "YoverParabola": Ymean / para if para > 0 else math.nan,
            "YoverEllipse": Ymean / ell if ell > 0 else math.nan,
        })

    summary_csv = out / "li_framewise_width50_summary.csv"
    with summary_csv.open("w", newline="") as h:
        fields = list(summary[0].keys())
        w = csv.DictWriter(h, fieldnames=fields)
        w.writeheader()
        w.writerows(summary)

    xs = np.array([r["meanFramewiseX"] for r in summary])
    ys = np.array([r["meanFramewiseY_dOverh"] for r in summary])
    frs = np.array([r["targetFr"] for r in summary])

    slope, r2 = fit_origin(xs, ys)

    publication_style()

    xmax = 1.12 * float(np.nanmax(xs))
    xx = np.linspace(0.0, xmax, 300)

    fig, ax = plt.subplots(figsize=(6.5, 5.0))
    ax.plot(
        xx, A_PARABOLA * xx, "--",
        label=rf"Parabola: $d/h=\sqrt{{16/\pi}}\,X$"
    )
    ax.plot(
        xx, A_ELLIPSE * xx, "-.",
        label=rf"Ellipse: $d/h=\sqrt{{12/\pi}}\,X$"
    )
    ax.plot(
        xx, slope * xx, ":",
        label=f"SRC fit: d/h = {slope:.3f} X"
    )
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

    ax.set_xlabel(r"$X=\left(M/(\rho_l g h^3)\right)^{1/2}$")
    ax.set_ylabel(r"Cavity aspect ratio $d_{50}/h$")
    ax.set_xlim(left=0.0)
    ax.set_ylim(bottom=0.0)
    ax.grid(True, alpha=0.25)
    ax.legend(loc="best")
    fig.tight_layout()
    fig.savefig(out / "fig_li_framewise_width50_shape_map.pdf",
                format="pdf", bbox_inches="tight")
    plt.close(fig)

    # Diagnostic comparison against old mouth-width definition, if available.
    if "mouthWidthOverD" in rows[0]:
        mouth_groups = defaultdict(list)
        for r in rows:
            fr = ffloat(r.get("targetFr"))
            include = fint(r.get("includeForArticle"))
            hD = ffloat(r.get("hOverD_initialRef"))
            dM = ffloat(r.get("mouthWidthOverD"))
            if (
                math.isfinite(fr)
                and fr <= args.max_fr + 1e-12
                and include == 1
                and math.isfinite(hD)
                and hD >= args.min_h_over_D
                and math.isfinite(dM)
                and dM > 0
            ):
                X = math.sqrt((4.0 / math.pi) * fr / (hD ** 3))
                Y = dM / hD
                mouth_groups[round(fr, 9)].append((X, Y))

        old_x = []
        old_y = []
        old_fr = []
        for frkey in sorted(mouth_groups):
            aa = mouth_groups[frkey]
            old_x.append(float(np.mean([v[0] for v in aa])))
            old_y.append(float(np.mean([v[1] for v in aa])))
            old_fr.append(frkey)

        fig, ax = plt.subplots(figsize=(6.5, 5.0))
        ax.plot(xx, A_PARABOLA * xx, "--", label="Parabola")
        ax.plot(xx, A_ELLIPSE * xx, "-.", label="Ellipse")
        ax.plot(old_x, old_y, "s", label="Mouth width")
        ax.plot(xs, ys, "o", label="Width at 50% depth")

        for xo, yo, xn, yn, fr in zip(old_x, old_y, xs, ys, frs):
            ax.plot([xo, xn], [yo, yn], linewidth=0.8, alpha=0.7)

        ax.set_xlabel(r"$X=\left(M/(\rho_l g h^3)\right)^{1/2}$")
        ax.set_ylabel(r"Cavity aspect ratio $d/h$")
        ax.set_xlim(left=0.0)
        ax.set_ylim(bottom=0.0)
        ax.grid(True, alpha=0.25)
        ax.legend(loc="best")
        fig.tight_layout()
        fig.savefig(out / "fig_width50_vs_mouth_definition_diagnostic.pdf",
                    format="pdf", bbox_inches="tight")
        plt.close(fig)

    report = out / "report.txt"
    with report.open("w") as h:
        h.write("0493x24al — Li framewise analysis with d = width at 50% depth\n")
        h.write("================================================================\n\n")
        h.write(
            "Per retained frame:\n"
            "  X_k = sqrt((4/pi) * Fr' / (h_k/D)^3)\n"
            "  d_k/D = width50DepthOverD\n"
            "  Y_k = (d_k/D)/(h_k/D)\n\n"
            "Article point:\n"
            "  X = mean(X_k)\n"
            "  Y = mean(Y_k)\n\n"
        )
        h.write(
            f"Parabola slope sqrt(16/pi) = {A_PARABOLA:.8f}\n"
            f"Ellipse slope  sqrt(12/pi) = {A_ELLIPSE:.8f}\n"
            f"SRC width50 fit through origin = {slope:.8f}, R2={r2:.8f}\n\n"
        )

        h.write("Case summary\n")
        h.write("------------\n")
        for r in summary:
            h.write(
                f"Fr'={r['targetFr']:.9g}  N={r['frames']}  "
                f"Xbar={r['meanFramewiseX']:.6g} +/- {r['stdFramewiseX']:.4g}  "
                f"Ybar={r['meanFramewiseY_dOverh']:.6g} +/- {r['stdFramewiseY_dOverh']:.4g}  "
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

    print("[x24al] input :", history_path)
    print("[x24al] valid frames:", len(frame_rows))
    print("[x24al] cases:", len(summary))
    print(f"[x24al] SRC width50 fit: d50/h = {slope:.6f} X, R2={r2:.6f}")
    print("[x24al] wrote:")
    print(" ", frame_csv)
    print(" ", summary_csv)
    print(" ", out / "fig_li_framewise_width50_shape_map.pdf")
    if "mouthWidthOverD" in rows[0]:
        print(" ", out / "fig_width50_vs_mouth_definition_diagnostic.pdf")
    print(" ", report)


if __name__ == "__main__":
    main()
