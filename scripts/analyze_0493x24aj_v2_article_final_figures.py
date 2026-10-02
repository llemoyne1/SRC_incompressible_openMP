#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
0493x24aj-v2 — final article figures for Sato / SRC-MPCD validation.

This version fixes the v1 failure mode: it does NOT look for data in /mnt/data.
By default it searches the project-local analysis/ tree.

Expected analysis products
--------------------------
Interface analysis (x24ae):
  article_interface_summary.csv
  shape_fit_summary.csv
  mean_profiles.csv

Momentum audit (x24ai):
  momentum_audit_summary.csv

Typical project layout:
  analysis/0493x24ae_article_interface_extended/
  analysis/0493x24ai_momentum_audit_8Fr/

Usage
-----
From the repository root:

python3 scripts/analyze_0493x24aj_v2_article_final_figures.py

or explicitly:

python3 scripts/analyze_0493x24aj_v2_article_final_figures.py \
  --interface-dir analysis/0493x24ae_article_interface_extended \
  --momentum-dir analysis/0493x24ai_momentum_audit_8Fr \
  --out analysis/0493x24aj_article_final

The script fails loudly if required input files are missing or empty.

Article policy
--------------
- Quantitative Sato figures use Fr' <= 1.17.
- Fr'=3 is excluded from the quantitative Sato fit by default.
- The momentum figure uses the audited definition:
      probe height = bath + 0.5 D
      integration width = 3 D
- Parabola/ellipse comparison uses shape_fit_summary.csv.
- All article figures are written as vector PDF.
- No pandas.
"""

from __future__ import annotations

import argparse
import csv
import math
import os
from pathlib import Path
from typing import Dict, List

import numpy as np
import matplotlib.pyplot as plt


SATO_SLOPE = 1.30


def ffloat(x, default=math.nan):
    try:
        y = float(x)
        return y if math.isfinite(y) else default
    except Exception:
        return default


def read_csv(path: Path) -> List[Dict[str, str]]:
    if not path.exists():
        raise SystemExit(f"[x24aj-v2] ERROR missing input: {path}")
    if path.stat().st_size == 0:
        raise SystemExit(f"[x24aj-v2] ERROR empty input: {path}")
    with path.open("r", newline="") as h:
        rows = list(csv.DictReader(h))
    if not rows:
        raise SystemExit(f"[x24aj-v2] ERROR no data rows in: {path}")
    return rows


def require_columns(rows, cols, path):
    got = set(rows[0].keys())
    missing = [c for c in cols if c not in got]
    if missing:
        raise SystemExit(
            f"[x24aj-v2] ERROR {path} missing columns: {', '.join(missing)}"
        )


def publication_style():
    plt.rcParams.update({
        "font.family": "DejaVu Sans",
        "font.size": 10,
        "axes.labelsize": 11,
        "axes.titlesize": 11,
        "legend.fontsize": 9,
        "xtick.labelsize": 10,
        "ytick.labelsize": 10,
        "pdf.fonttype": 42,
        "ps.fonttype": 42,
        "lines.linewidth": 1.7,
        "lines.markersize": 5.5,
    })


def save_pdf(fig, path: Path):
    fig.tight_layout()
    fig.savefig(path, format="pdf", bbox_inches="tight")
    plt.close(fig)


def filter_fr(rows, max_fr=1.17):
    out = []
    for r in rows:
        fr = ffloat(r.get("targetFr"))
        if math.isfinite(fr) and fr <= max_fr + 1e-10:
            out.append(r)
    out.sort(key=lambda r: ffloat(r["targetFr"]))
    return out


def mean_std(values):
    a = np.asarray([v for v in values if math.isfinite(v)], float)
    if len(a) == 0:
        return math.nan, math.nan
    return (
        float(np.mean(a)),
        float(np.std(a, ddof=1)) if len(a) > 1 else 0.0,
    )


def fit_origin(x, y):
    x = np.asarray(x, float)
    y = np.asarray(y, float)
    mask = np.isfinite(x) & np.isfinite(y)
    x = x[mask]
    y = y[mask]
    if len(x) < 2 or np.dot(x, x) <= 0:
        return math.nan, math.nan
    a = float(np.dot(x, y) / np.dot(x, x))
    pred = a * x
    ssr = float(np.sum((y - pred) ** 2))
    sst = float(np.sum((y - np.mean(y)) ** 2))
    r2 = 1.0 - ssr / sst if sst > 0 else math.nan
    return a, r2


def load_interface(path: Path):
    rows = read_csv(path)
    require_columns(
        rows,
        [
            "targetFr",
            "meanHOverD", "stdHOverD",
            "meanMouthWidthOverD", "stdMouthWidthOverD",
            "meanWidth10DepthOverD", "stdWidth10DepthOverD",
            "meanWidth50DepthOverD", "stdWidth50DepthOverD",
        ],
        path,
    )
    return filter_fr(rows)


def load_shape(path: Path):
    rows = read_csv(path)
    require_columns(
        rows,
        [
            "targetFr",
            "parabolaRMSEOverD", "parabolaR2",
            "ellipseRMSEOverD", "ellipseR2",
            "rmseRatioParabolaOverEllipse",
        ],
        path,
    )
    return filter_fr(rows)


def load_profiles(path: Path):
    rows = read_csv(path)
    require_columns(
        rows,
        ["targetFr", "xOverD", "meanDepressionOverD", "stdDepressionOverD"],
        path,
    )
    return [r for r in rows if ffloat(r.get("targetFr")) <= 1.17 + 1e-10]


def load_momentum_audit(path: Path, hD=0.5, wD=3.0):
    rows = read_csv(path)
    require_columns(
        rows,
        [
            "targetFr",
            "probeHeightOverD",
            "widthOverD",
            "meanIncidentAxialMomentumDown",
            "stdIncidentAxialMomentumDown",
            "meanNozzleAxialMomentumDown",
            "stdNozzleAxialMomentumDown",
            "meanIncidentToNozzleAxialRatio",
            "stdIncidentToNozzleAxialRatio",
            "meanIncidentLateralFraction",
            "stdIncidentLateralFraction",
        ],
        path,
    )

    selected = []
    for r in rows:
        fr = ffloat(r.get("targetFr"))
        hh = ffloat(r.get("probeHeightOverD"))
        ww = ffloat(r.get("widthOverD"))
        if (
            math.isfinite(fr)
            and fr <= 1.17 + 1e-10
            and abs(hh - hD) < 1e-9
            and abs(ww - wD) < 1e-9
        ):
            selected.append(r)

    selected.sort(key=lambda r: ffloat(r["targetFr"]))
    if not selected:
        raise SystemExit(
            f"[x24aj-v2] ERROR no momentum rows found for h/D={hD}, W/D={wD} in {path}"
        )
    return selected


def fig_depth(interface, out):
    fr = np.array([ffloat(r["targetFr"]) for r in interface])
    h = np.array([ffloat(r["meanHOverD"]) for r in interface])
    hs = np.array([ffloat(r["stdHOverD"]) for r in interface])

    slope, r2 = fit_origin(fr, h)
    xx = np.linspace(0.0, max(fr) * 1.10, 300)

    fig, ax = plt.subplots(figsize=(6.4, 4.8))
    ax.fill_between(
        xx, 0.8 * SATO_SLOPE * xx, 1.2 * SATO_SLOPE * xx,
        alpha=0.18, label="Sato ±20%"
    )
    ax.plot(xx, SATO_SLOPE * xx, label="Sato: h/D = 1.30 Fr'")
    ax.plot(xx, slope * xx, "--", label=f"SRC fit: h/D = {slope:.3f} Fr'")
    ax.errorbar(fr, h, yerr=hs, fmt="o", capsize=3.5, label="SRC/MPCD")
    ax.set_xlabel("Target modified Froude number Fr'")
    ax.set_ylabel("Cavity depth h/D")
    ax.set_xlim(0, max(fr) * 1.08)
    ax.set_ylim(bottom=0)
    ax.grid(True, alpha=0.25)
    ax.legend(loc="upper left")
    save_pdf(fig, out / "fig01_depth_vs_froude.pdf")
    return slope, r2


def fig_profiles(profiles, out):
    groups = {}
    for r in profiles:
        fr = round(ffloat(r["targetFr"]), 9)
        groups.setdefault(fr, []).append(r)

    fig, ax = plt.subplots(figsize=(6.4, 4.8))
    for fr in sorted(groups):
        rr = sorted(groups[fr], key=lambda r: ffloat(r["xOverD"]))
        x = np.array([ffloat(r["xOverD"]) for r in rr])
        y = np.array([ffloat(r["meanDepressionOverD"]) for r in rr])
        mask = np.isfinite(x) & np.isfinite(y) & (np.abs(x) <= 4.0)
        ax.plot(x[mask], y[mask], label=f"Fr'={fr:g}")
    ax.set_xlabel("(x - x_j) / D")
    ax.set_ylabel("Mean interface depression / D")
    ax.grid(True, alpha=0.25)
    ax.legend(ncol=2)
    save_pdf(fig, out / "fig02_mean_interface_profiles.pdf")


def fig_widths(interface, out):
    fr = np.array([ffloat(r["targetFr"]) for r in interface])

    fig, ax = plt.subplots(figsize=(6.4, 4.8))
    ax.errorbar(
        fr,
        [ffloat(r["meanMouthWidthOverD"]) for r in interface],
        yerr=[ffloat(r["stdMouthWidthOverD"]) for r in interface],
        fmt="o-", capsize=3, label="Mouth width",
    )
    ax.errorbar(
        fr,
        [ffloat(r["meanWidth50DepthOverD"]) for r in interface],
        yerr=[ffloat(r["stdWidth50DepthOverD"]) for r in interface],
        fmt="s-", capsize=3, label="Width at 50% depth",
    )
    ax.errorbar(
        fr,
        [ffloat(r["meanWidth10DepthOverD"]) for r in interface],
        yerr=[ffloat(r["stdWidth10DepthOverD"]) for r in interface],
        fmt="^-", capsize=3, alpha=0.75, label="Width at 10% depth",
    )
    ax.set_xlabel("Target modified Froude number Fr'")
    ax.set_ylabel("Characteristic width / D")
    ax.set_ylim(bottom=0)
    ax.grid(True, alpha=0.25)
    ax.legend()
    save_pdf(fig, out / "fig03_interface_widths_vs_froude.pdf")


def fig_momentum(momentum, out):
    fr = np.array([ffloat(r["targetFr"]) for r in momentum])
    ratio = np.array([ffloat(r["meanIncidentToNozzleAxialRatio"]) for r in momentum])
    ratio_std = np.array([ffloat(r["stdIncidentToNozzleAxialRatio"]) for r in momentum])

    fig, ax = plt.subplots(figsize=(6.4, 4.8))
    ax.errorbar(fr, ratio, yerr=ratio_std, fmt="o-", capsize=3.5)
    ax.set_xlabel("Target modified Froude number Fr'")
    ax.set_ylabel("Incident / nozzle axial-momentum proxy")
    ax.set_ylim(0, 1.05)
    ax.grid(True, alpha=0.25)
    save_pdf(fig, out / "fig04_incident_nozzle_momentum_ratio.pdf")

    jn = np.array([ffloat(r["meanNozzleAxialMomentumDown"]) for r in momentum])
    jn_std = np.array([ffloat(r["stdNozzleAxialMomentumDown"]) for r in momentum])
    slope, r2 = fit_origin(fr, jn)
    xx = np.linspace(0, max(fr) * 1.08, 200)

    fig, ax = plt.subplots(figsize=(6.4, 4.8))
    ax.errorbar(fr, jn, yerr=jn_std, fmt="o", capsize=3.5, label="Nozzle momentum proxy")
    ax.plot(xx, slope * xx, "--", label=f"Fit through 0, R²={r2:.3f}")
    ax.set_xlabel("Target modified Froude number Fr'")
    ax.set_ylabel("Nozzle axial-momentum proxy")
    ax.set_ylim(bottom=0)
    ax.grid(True, alpha=0.25)
    ax.legend()
    save_pdf(fig, out / "fig05_nozzle_momentum_vs_froude.pdf")

    lateral = np.array([ffloat(r["meanIncidentLateralFraction"]) for r in momentum])
    lateral_std = np.array([ffloat(r["stdIncidentLateralFraction"]) for r in momentum])

    fig, ax = plt.subplots(figsize=(6.4, 4.8))
    ax.errorbar(fr, lateral, yerr=lateral_std, fmt="o-", capsize=3.5)
    ax.set_xlabel("Target modified Froude number Fr'")
    ax.set_ylabel("Lateral kinetic fraction at y = bath + 0.5D")
    ax.set_ylim(0, 1.0)
    ax.grid(True, alpha=0.25)
    save_pdf(fig, out / "fig06_lateral_fraction_vs_froude.pdf")


def fig_shape(shape, out):
    fr = np.array([ffloat(r["targetFr"]) for r in shape])
    rp = np.array([ffloat(r["parabolaRMSEOverD"]) for r in shape])
    re = np.array([ffloat(r["ellipseRMSEOverD"]) for r in shape])
    r2p = np.array([ffloat(r["parabolaR2"]) for r in shape])
    r2e = np.array([ffloat(r["ellipseR2"]) for r in shape])
    ratio = np.array([ffloat(r["rmseRatioParabolaOverEllipse"]) for r in shape])

    fig, ax = plt.subplots(figsize=(6.4, 4.8))
    ax.plot(fr, rp, "o-", label="Parabola")
    ax.plot(fr, re, "s-", label="Ellipse")
    ax.set_xlabel("Target modified Froude number Fr'")
    ax.set_ylabel("Profile-fit RMSE / D")
    ax.set_ylim(bottom=0)
    ax.grid(True, alpha=0.25)
    ax.legend()
    save_pdf(fig, out / "fig07_shape_fit_rmse.pdf")

    fig, ax = plt.subplots(figsize=(6.4, 4.8))
    ax.plot(fr, r2p, "o-", label="Parabola")
    ax.plot(fr, r2e, "s-", label="Ellipse")
    ax.set_xlabel("Target modified Froude number Fr'")
    ax.set_ylabel("Profile-fit R²")
    ax.set_ylim(0.0, 1.02)
    ax.grid(True, alpha=0.25)
    ax.legend()
    save_pdf(fig, out / "fig08_shape_fit_r2.pdf")

    fig, ax = plt.subplots(figsize=(6.4, 4.8))
    ax.plot(fr, ratio, "o-")
    ax.axhline(1.0, linestyle="--", linewidth=1.2)
    ax.set_xlabel("Target modified Froude number Fr'")
    ax.set_ylabel("RMSE(parabola) / RMSE(ellipse)")
    ax.grid(True, alpha=0.25)
    save_pdf(fig, out / "fig09_shape_fit_rmse_ratio.pdf")


def write_summary(interface, momentum, shape, slope, r2, out):
    p = out / "article_final_summary.txt"
    with p.open("w") as h:
        h.write("0493x24aj-v2 — final article figure summary\n")
        h.write("==========================================\n\n")
        h.write(f"Sato depth fit through origin: h/D = {slope:.6f} Fr', R2={r2:.6f}\n\n")

        h.write("Interface cases\n")
        h.write("---------------\n")
        for r in interface:
            fr = ffloat(r["targetFr"])
            hm = ffloat(r["meanHOverD"])
            hs = ffloat(r["stdHOverD"])
            target = SATO_SLOPE * fr
            err = 100.0 * (hm - target) / target
            h.write(f"Fr'={fr:.6g}: h/D={hm:.5f} ± {hs:.5f}; Sato={target:.5f}; err={err:+.2f}%\n")

        h.write("\nMomentum audit used in article\n")
        h.write("------------------------------\n")
        h.write("Probe: y = bath + 0.5D; integration width W = 3D\n")
        for r in momentum:
            fr = ffloat(r["targetFr"])
            ratio = ffloat(r["meanIncidentToNozzleAxialRatio"])
            lat = ffloat(r["meanIncidentLateralFraction"])
            h.write(f"Fr'={fr:.6g}: Jinc/Jnoz={ratio:.5f}; lateral fraction={lat:.5f}\n")

        h.write("\nParabola / ellipse comparison\n")
        h.write("-----------------------------\n")
        for r in shape:
            fr = ffloat(r["targetFr"])
            q = ffloat(r["rmseRatioParabolaOverEllipse"])
            h.write(
                f"Fr'={fr:.6g}: RMSEp={ffloat(r['parabolaRMSEOverD']):.5f}; "
                f"RMSEe={ffloat(r['ellipseRMSEOverD']):.5f}; "
                f"RMSEp/RMSEe={q:.4f}; "
                f"{'parabola better' if q < 1 else 'ellipse better'}\n"
            )


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument(
        "--interface-dir",
        default="analysis/0493x24ae_article_interface_extended",
        help="directory containing article_interface_summary.csv, shape_fit_summary.csv, mean_profiles.csv",
    )
    ap.add_argument(
        "--momentum-dir",
        default="analysis/0493x24ai_momentum_audit_8Fr",
        help="directory containing momentum_audit_summary.csv",
    )
    ap.add_argument(
        "--out",
        default="analysis/0493x24aj_article_final",
        help="output directory",
    )
    ap.add_argument("--momentum-height-over-D", type=float, default=0.5)
    ap.add_argument("--momentum-width-over-D", type=float, default=3.0)
    args = ap.parse_args()

    interface_dir = Path(args.interface_dir)
    momentum_dir = Path(args.momentum_dir)
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)

    interface_csv = interface_dir / "article_interface_summary.csv"
    shape_csv = interface_dir / "shape_fit_summary.csv"
    profiles_csv = interface_dir / "mean_profiles.csv"
    momentum_csv = momentum_dir / "momentum_audit_summary.csv"

    print("[x24aj-v2] inputs:")
    print("  interface :", interface_csv)
    print("  shape     :", shape_csv)
    print("  profiles  :", profiles_csv)
    print("  momentum  :", momentum_csv)

    publication_style()

    interface = load_interface(interface_csv)
    shape = load_shape(shape_csv)
    profiles = load_profiles(profiles_csv)
    momentum = load_momentum_audit(
        momentum_csv,
        hD=args.momentum_height_over_D,
        wD=args.momentum_width_over_D,
    )

    print(f"[x24aj-v2] interface cases: {len(interface)}")
    print(f"[x24aj-v2] shape cases:     {len(shape)}")
    print(f"[x24aj-v2] momentum cases:  {len(momentum)}")
    print(f"[x24aj-v2] profile rows:    {len(profiles)}")

    slope, r2 = fig_depth(interface, out)
    fig_profiles(profiles, out)
    fig_widths(interface, out)
    fig_momentum(momentum, out)
    fig_shape(shape, out)
    write_summary(interface, momentum, shape, slope, r2, out)

    generated = sorted(out.glob("*.pdf"))
    if not generated:
        raise SystemExit("[x24aj-v2] ERROR no PDF generated")

    print("[x24aj-v2] generated:")
    for p in generated:
        print("  ", p)
    print("  ", out / "article_final_summary.txt")


if __name__ == "__main__":
    main()
