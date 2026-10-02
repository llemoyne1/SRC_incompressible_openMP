#!/usr/bin/env python3
"""
0493x24ae — article gas/liquid interface validation from uninterrupted Sato runs.

Scope
-----
This analyzer is intentionally centered on validation of the SRC/MPCD gas-liquid
interaction model, not on a detailed cavity-physics study.

It uses rho1 recordings to extract:
  1) Sato primary observable: cavity depth h/D.
  2) A global morphology check: cavity width proxies versus target Fr'.
  3) Mean interface profiles, with simple parabola/ellipse family fits as a
     compact sanity check that the correct depth is not obtained with an
     obviously pathological interface shape.

The runs are assumed to be uninterrupted forced runs.  A single initial
transient cutoff is applied (default t=1).  No restart stitching is performed.

Input syntax
------------
  --case TARGET_FR:RUN_ROOT

Example
-------
python3 scripts/analyze_0493x24ae_article_interface_validation.py \
  --case 0.25:runs/.../Fr0p25/restart_common_relaxed_start \
  --case 0.40:runs/.../Fr0p40/restart_common_relaxed_start \
  --case 0.55:runs/.../Fr0p55/restart_common_relaxed_start \
  --case 0.660364520158346:runs/.../Fr0p660364520158346/restart_common_relaxed_start \
  --out analysis/0493x24ae_article_interface

Outputs
-------
  frame_interface_history.csv
  article_interface_summary.csv
  mean_profiles.csv
  shape_fit_summary.csv
  report.txt
  h_over_D_time_series.pdf
  h_over_D_vs_target_Fr.pdf
  cavity_width_vs_target_Fr.pdf
  mean_cavity_profiles.pdf

PNG previews are also written, but PDF is the article reference format.

No pandas.
"""

from __future__ import annotations

import argparse
import csv
import math
import re
from collections import defaultdict
from pathlib import Path

import numpy as np
import matplotlib.pyplot as plt

SATO_SLOPE = 1.30


def fv(x, default=math.nan):
    try:
        y = float(x)
        return y if math.isfinite(y) else default
    except Exception:
        return default


def read_kv(path: Path):
    out = {}
    if not path.exists():
        return out
    for raw in path.read_text(errors="replace").splitlines():
        s = raw.strip()
        if not s or s.startswith("#") or "=" not in s:
            continue
        k, v = s.split("=", 1)
        out[k.strip()] = v.strip()
    return out


def parse_env(root: Path):
    env = {}
    for p in sorted((root / "logs").glob("environment_*.env")):
        env.update(read_kv(p))
    return env


def find_manifest(root: Path):
    cands = list((root / "output" / "recordings").glob("**/manifest.kv"))
    return cands[0] if cands else None


def detect_grid(root: Path, nx_default: int, ny_default: int):
    man = find_manifest(root)
    if man:
        kv = read_kv(man)
        for kx, ky in [
            ("liveGridNx", "liveGridNy"),
            ("recordGridNx", "recordGridNy"),
            ("Nx", "Ny"),
            ("nx", "ny"),
        ]:
            if kx in kv and ky in kv:
                try:
                    return int(float(kv[kx])), int(float(kv[ky])), kv
                except Exception:
                    pass
    return nx_default, ny_default, {}


def step_from_name(path: Path):
    m = re.search(r"step_(\d+)_field_rho1\.f32$", path.name)
    return int(m.group(1)) if m else None


def load_f32(path: Path, nx: int, ny: int):
    a = np.fromfile(path, dtype="<f4")
    if a.size != nx * ny:
        raise ValueError(f"{path}: expected {nx*ny} floats, got {a.size}")
    return a.reshape((ny, nx))


def interface_profile_from_rho1(arr, Ly: float, threshold: float):
    ny, nx = arr.shape
    dy = Ly / ny
    eta = np.full(nx, np.nan, float)
    mask = arr >= threshold
    for i in range(nx):
        js = np.flatnonzero(mask[:, i])
        if len(js):
            eta[i] = (js[-1] + 0.5) * dy
    return eta


def connected_width(xs, condition, center_x):
    """Width of the connected True interval containing the jet centre."""
    if not np.any(condition):
        return math.nan
    ic = int(np.argmin(np.abs(xs - center_x)))
    if not condition[ic]:
        # Find nearest True cell to the centre, but reject remote structures.
        inds = np.flatnonzero(condition)
        if len(inds) == 0:
            return math.nan
        j = inds[np.argmin(np.abs(xs[inds] - center_x))]
        if abs(xs[j] - center_x) > 1.5 * (xs[1] - xs[0]):
            return math.nan
        ic = int(j)

    il = ic
    ir = ic
    while il > 0 and condition[il - 1]:
        il -= 1
    while ir + 1 < len(condition) and condition[ir + 1]:
        ir += 1
    dx = xs[1] - xs[0]
    return (ir - il + 1) * dx


def profile_metrics(
    eta,
    Lx,
    jet_center,
    D,
    bath_height,
    mouth_eps_D,
):
    nx = len(eta)
    dx = Lx / nx
    xs = (np.arange(nx) + 0.5) * dx
    valid = np.isfinite(eta)

    far_mask = (
        valid
        & (xs > 0.08 * Lx)
        & (xs < 0.92 * Lx)
        & (np.abs(xs - jet_center) >= 3.0 * D)
    )
    far = eta[far_mask]
    eta_far = float(np.median(far)) if len(far) else math.nan

    center = valid & (np.abs(xs - jet_center) <= 1.5 * D)
    eta_min = float(np.min(eta[center])) if np.any(center) else math.nan

    h_initial = (
        (bath_height - eta_min) / D
        if math.isfinite(eta_min)
        else math.nan
    )
    h_far = (
        (eta_far - eta_min) / D
        if math.isfinite(eta_far) and math.isfinite(eta_min)
        else math.nan
    )

    mouth_width = math.nan
    width10 = math.nan
    width50 = math.nan
    area_far = math.nan

    if math.isfinite(eta_far) and math.isfinite(eta_min) and eta_far > eta_min:
        depth = eta_far - eta_min

        cond10 = valid & (eta <= eta_far - 0.10 * depth)
        cond50 = valid & (eta <= eta_far - 0.50 * depth)
        width10 = connected_width(xs, cond10, jet_center)
        width50 = connected_width(xs, cond50, jet_center)

        # A conservative mouth-width proxy relative to the fixed initial bath
        # level. The epsilon avoids counting grid/noise-scale deviations.
        condmouth = valid & (eta <= bath_height - mouth_eps_D * D)
        mouth_width = connected_width(xs, condmouth, jet_center)

        # Global depression area relative to the instantaneous far-field level,
        # restricted to the connected central cavity at 5% depth.
        cond05 = valid & (eta <= eta_far - 0.05 * depth)
        if np.any(cond05):
            ic = int(np.argmin(np.abs(xs - jet_center)))
            if cond05[ic]:
                il = ic
                ir = ic
                while il > 0 and cond05[il - 1]:
                    il -= 1
                while ir + 1 < nx and cond05[ir + 1]:
                    ir += 1
                dep = np.maximum(eta_far - eta[il:ir + 1], 0.0)
                area_far = float(np.sum(dep) * dx)

    return {
        "etaFar": eta_far,
        "etaMin": eta_min,
        "hOverD_initialRef": h_initial,
        "hOverD_farRef": h_far,
        "mouthWidthOverD": mouth_width / D if math.isfinite(mouth_width) else math.nan,
        "width10DepthOverD": width10 / D if math.isfinite(width10) else math.nan,
        "width50DepthOverD": width50 / D if math.isfinite(width50) else math.nan,
        "depressionAreaOverD2": area_far / (D * D) if math.isfinite(area_far) else math.nan,
    }


def mean_std(vals):
    a = np.asarray([x for x in vals if math.isfinite(x)], float)
    if len(a) == 0:
        return math.nan, math.nan, 0
    return (
        float(np.mean(a)),
        float(np.std(a, ddof=1)) if len(a) > 1 else 0.0,
        int(len(a)),
    )


def linfit_origin(x, y):
    x = np.asarray(x, float)
    y = np.asarray(y, float)
    m = np.isfinite(x) & np.isfinite(y)
    x = x[m]
    y = y[m]
    if len(x) < 2 or np.dot(x, x) == 0:
        return math.nan, math.nan
    a = float(np.dot(x, y) / np.dot(x, x))
    yp = a * x
    ssr = float(np.sum((y - yp) ** 2))
    sst = float(np.sum((y - np.mean(y)) ** 2))
    r2 = 1.0 - ssr / sst if sst > 0 else math.nan
    return a, r2


def fit_shape_family(xD, dD, family):
    """
    Fit d/D = hD * phi(xD/aD) with a grid search over half-width aD and
    analytical least-squares amplitude hD.

    family='parabola': phi = max(0, 1-z^2)
    family='ellipse' : phi = sqrt(max(0, 1-z^2))
    """
    xD = np.asarray(xD, float)
    dD = np.asarray(dD, float)
    m = np.isfinite(xD) & np.isfinite(dD) & (dD >= 0)
    xD = xD[m]
    dD = dD[m]
    if len(xD) < 8 or np.max(dD) <= 0:
        return dict(aD=math.nan, hD=math.nan, rmse=math.nan, r2=math.nan)

    best = None
    for aD in np.linspace(0.5, 8.0, 600):
        z = xD / aD
        inside = np.abs(z) <= 1.0
        phi = np.zeros_like(z)
        if family == "parabola":
            phi[inside] = 1.0 - z[inside] ** 2
        elif family == "ellipse":
            phi[inside] = np.sqrt(np.maximum(0.0, 1.0 - z[inside] ** 2))
        else:
            raise ValueError(family)

        den = float(np.dot(phi, phi))
        if den <= 0:
            continue
        hD = max(0.0, float(np.dot(phi, dD) / den))
        pred = hD * phi
        rmse = float(np.sqrt(np.mean((dD - pred) ** 2)))
        sst = float(np.sum((dD - np.mean(dD)) ** 2))
        ssr = float(np.sum((dD - pred) ** 2))
        r2 = 1.0 - ssr / sst if sst > 0 else math.nan
        cand = (rmse, aD, hD, r2)
        if best is None or cand[0] < best[0]:
            best = cand

    if best is None:
        return dict(aD=math.nan, hD=math.nan, rmse=math.nan, r2=math.nan)
    return dict(aD=best[1], hD=best[2], rmse=best[0], r2=best[3])


ap = argparse.ArgumentParser()
ap.add_argument("--case", action="append", required=True,
                help="TARGET_FR:RUN_ROOT; repeat for each uninterrupted case")
ap.add_argument("--out", default="analysis/0493x24ae_article_interface_validation")
ap.add_argument("--nx", type=int, default=400)
ap.add_argument("--ny", type=int, default=256)
ap.add_argument("--Lx", type=float, default=1.5625)
ap.add_argument("--Ly", type=float, default=1.0)
ap.add_argument("--jet-center-x", type=float, default=0.78125)
ap.add_argument("--D", type=float, default=0.078125)
ap.add_argument("--bath-height", type=float, default=0.81640625)
ap.add_argument("--rho-threshold", type=float, default=10.0)
ap.add_argument("--initial-cutoff", type=float, default=1.0)
ap.add_argument("--mouth-eps-D", type=float, default=0.05)
ap.add_argument("--sato-band", type=float, default=0.20)
args = ap.parse_args()

out = Path(args.out)
out.mkdir(parents=True, exist_ok=True)

cases = []
for spec in args.case:
    parts = spec.split(":", 1)
    if len(parts) != 2:
        raise SystemExit(f"bad --case '{spec}', expected TARGET_FR:RUN_ROOT")
    fr = float(parts[0])
    root = Path(parts[1])
    if not root.exists():
        raise SystemExit(f"missing run root: {root}")

    env = parse_env(root)
    dt = fv(env.get("DT"), 0.0004)
    nx, ny, manifest = detect_grid(root, args.nx, args.ny)
    cases.append(dict(fr=fr, root=root, env=env, dt=dt, nx=nx, ny=ny, manifest=manifest))

frame_rows = []
profiles_by_fr = defaultdict(list)

for case in cases:
    root = case["root"]
    files = sorted((root / "output" / "recordings").glob("**/step_*_field_rho1.f32"))
    if not files:
        print(f"[0493x24ae] WARNING no rho1 recordings under {root}")
        continue

    for p in files:
        step = step_from_name(p)
        if step is None:
            continue
        t = step * case["dt"]
        arr = load_f32(p, case["nx"], case["ny"])
        eta = interface_profile_from_rho1(arr, args.Ly, args.rho_threshold)
        metrics = profile_metrics(
            eta,
            args.Lx,
            args.jet_center_x,
            args.D,
            args.bath_height,
            args.mouth_eps_D,
        )

        include = t >= args.initial_cutoff
        frame_rows.append({
            "targetFr": case["fr"],
            "runRoot": str(root),
            "localStep": step,
            "time": t,
            "includeForArticle": int(include),
            **metrics,
        })

        if include:
            nx = len(eta)
            dx = args.Lx / nx
            xs = (np.arange(nx) + 0.5) * dx
            eta_far = metrics["etaFar"]
            if math.isfinite(eta_far):
                dD = (eta_far - eta) / args.D
                xD = (xs - args.jet_center_x) / args.D
                profiles_by_fr[case["fr"]].append((xD, dD))

if not frame_rows:
    raise SystemExit("[0493x24ae] no rho1 frames found")

frame_rows.sort(key=lambda r: (r["targetFr"], r["time"]))

with (out / "frame_interface_history.csv").open("w", newline="") as h:
    fields = list(frame_rows[0].keys())
    w = csv.DictWriter(h, fieldnames=fields)
    w.writeheader()
    w.writerows(frame_rows)

groups = defaultdict(list)
for r in frame_rows:
    if r["includeForArticle"]:
        groups[r["targetFr"]].append(r)

summary = []
for fr in sorted(groups):
    rr = groups[fr]
    hm, hs, hn = mean_std([r["hOverD_initialRef"] for r in rr])
    wm, ws, wn = mean_std([r["mouthWidthOverD"] for r in rr])
    w10m, w10s, _ = mean_std([r["width10DepthOverD"] for r in rr])
    w50m, w50s, _ = mean_std([r["width50DepthOverD"] for r in rr])
    am, astd, _ = mean_std([r["depressionAreaOverD2"] for r in rr])

    summary.append({
        "targetFr": fr,
        "frames": hn,
        "timeStart": min(r["time"] for r in rr),
        "timeEnd": max(r["time"] for r in rr),
        "meanHOverD": hm,
        "stdHOverD": hs,
        "satoHOverD": SATO_SLOPE * fr,
        "relativeErrorToSato": (hm - SATO_SLOPE * fr) / (SATO_SLOPE * fr),
        "meanMouthWidthOverD": wm,
        "stdMouthWidthOverD": ws,
        "meanWidth10DepthOverD": w10m,
        "stdWidth10DepthOverD": w10s,
        "meanWidth50DepthOverD": w50m,
        "stdWidth50DepthOverD": w50s,
        "meanDepressionAreaOverD2": am,
        "stdDepressionAreaOverD2": astd,
    })

with (out / "article_interface_summary.csv").open("w", newline="") as h:
    fields = list(summary[0].keys())
    w = csv.DictWriter(h, fieldnames=fields)
    w.writeheader()
    w.writerows(summary)

# Mean profiles and simple shape-family fits.
profile_rows = []
shape_rows = []

for fr in sorted(profiles_by_fr):
    profs = profiles_by_fr[fr]
    if not profs:
        continue
    xD = profs[0][0]
    stack = np.vstack([p[1] for p in profs])
    mean_dD = np.nanmean(stack, axis=0)
    std_dD = np.nanstd(stack, axis=0, ddof=1) if stack.shape[0] > 1 else np.zeros_like(mean_dD)

    for x, m, s in zip(xD, mean_dD, std_dD):
        profile_rows.append({
            "targetFr": fr,
            "xOverD": x,
            "meanDepressionOverD": m,
            "stdDepressionOverD": s,
        })

    # Fit only the central connected depression where the mean depth exceeds 5%
    # of its maximum; this prevents remote surface fluctuations from dominating.
    hmax = float(np.nanmax(mean_dD))
    mask = np.isfinite(mean_dD) & (mean_dD >= 0.05 * hmax)
    ic = int(np.argmin(np.abs(xD)))
    if mask[ic]:
        il = ic
        ir = ic
        while il > 0 and mask[il - 1]:
            il -= 1
        while ir + 1 < len(mask) and mask[ir + 1]:
            ir += 1
        xf = xD[il:ir + 1]
        yf = mean_dD[il:ir + 1]
    else:
        xf = xD[mask]
        yf = mean_dD[mask]

    pfit = fit_shape_family(xf, yf, "parabola")
    efit = fit_shape_family(xf, yf, "ellipse")
    shape_rows.append({
        "targetFr": fr,
        "parabolaHalfWidthOverD": pfit["aD"],
        "parabolaDepthOverD": pfit["hD"],
        "parabolaRMSEOverD": pfit["rmse"],
        "parabolaR2": pfit["r2"],
        "ellipseHalfWidthOverD": efit["aD"],
        "ellipseDepthOverD": efit["hD"],
        "ellipseRMSEOverD": efit["rmse"],
        "ellipseR2": efit["r2"],
        "rmseRatioParabolaOverEllipse": (
            pfit["rmse"] / efit["rmse"]
            if math.isfinite(pfit["rmse"]) and math.isfinite(efit["rmse"]) and efit["rmse"] > 0
            else math.nan
        ),
    })

with (out / "mean_profiles.csv").open("w", newline="") as h:
    fields = list(profile_rows[0].keys())
    w = csv.DictWriter(h, fieldnames=fields)
    w.writeheader()
    w.writerows(profile_rows)

with (out / "shape_fit_summary.csv").open("w", newline="") as h:
    fields = list(shape_rows[0].keys())
    w = csv.DictWriter(h, fieldnames=fields)
    w.writeheader()
    w.writerows(shape_rows)

# Fits.
frs = [r["targetFr"] for r in summary]
hs = [r["meanHOverD"] for r in summary]
widths = [r["meanWidth10DepthOverD"] for r in summary]
depth_fit, depth_r2 = linfit_origin(frs, hs)
width_fit, width_r2 = linfit_origin(frs, widths)

with (out / "report.txt").open("w") as h:
    h.write("0493x24ae — article SRC/MPCD gas-liquid interface validation\n")
    h.write("===========================================================\n\n")
    h.write(f"Initial transient excluded: t < {args.initial_cutoff:g}\n")
    h.write(f"rho1 threshold: {args.rho_threshold:g}\n")
    h.write(f"Reference bath height: {args.bath_height:.9g}\n")
    h.write(f"D: {args.D:.9g}\n\n")
    h.write("Primary validation: Sato h/D vs target Fr'\n")
    h.write("------------------------------------------\n")
    for r in summary:
        h.write(
            f"Fr'={r['targetFr']:.9g}  "
            f"h/D={r['meanHOverD']:.6g} +/- {r['stdHOverD']:.4g}  "
            f"Sato={r['satoHOverD']:.6g}  "
            f"error={100*r['relativeErrorToSato']:+.2f}%\n"
        )
    h.write(
        f"\nSRC fit through origin: h/D={depth_fit:.8g} Fr' "
        f"(R2={depth_r2:.8g}); Sato slope={SATO_SLOPE:g}\n\n"
    )

    h.write("Global morphology check\n")
    h.write("-----------------------\n")
    for r in summary:
        h.write(
            f"Fr'={r['targetFr']:.9g}  "
            f"mouthWidth/D={r['meanMouthWidthOverD']:.6g} +/- {r['stdMouthWidthOverD']:.4g}  "
            f"width10%/D={r['meanWidth10DepthOverD']:.6g} +/- {r['stdWidth10DepthOverD']:.4g}  "
            f"width50%/D={r['meanWidth50DepthOverD']:.6g} +/- {r['stdWidth50DepthOverD']:.4g}\n"
        )
    h.write(
        f"\nWidth10% fit through origin: w10/D={width_fit:.8g} Fr' "
        f"(R2={width_r2:.8g})\n\n"
    )

    h.write("Mean-profile geometric family check\n")
    h.write("-----------------------------------\n")
    h.write("RMSE values are normalized by D; this is a morphology sanity check, not a new validation target.\n")
    for r in shape_rows:
        h.write(
            f"Fr'={r['targetFr']:.9g}  "
            f"parabola RMSE/D={r['parabolaRMSEOverD']:.5g}, R2={r['parabolaR2']:.5g}; "
            f"ellipse RMSE/D={r['ellipseRMSEOverD']:.5g}, R2={r['ellipseR2']:.5g}\n"
        )

# -------- figures: PDF reference + PNG preview --------

# 1. h/D time histories
fig, ax = plt.subplots(figsize=(8.6, 5.2))
for fr in sorted(groups):
    rr = sorted(groups[fr], key=lambda r: r["time"])
    ax.plot([r["time"] for r in rr], [r["hOverD_initialRef"] for r in rr], label=f"Fr'={fr:g}")
ax.axvline(args.initial_cutoff, linestyle="--", alpha=0.6, label="analysis start")
ax.set_xlabel("Forced physical time")
ax.set_ylabel("Cavity depth h/D")
ax.grid(True, alpha=0.25)
ax.legend()
fig.tight_layout()
fig.savefig(out / "h_over_D_time_series.pdf", bbox_inches="tight")
fig.savefig(out / "h_over_D_time_series.png", dpi=180, bbox_inches="tight")
plt.close(fig)

# 2. Sato relation
fig, ax = plt.subplots(figsize=(7.2, 5.2))
xx = np.linspace(0, max(frs) * 1.10, 300)
ax.fill_between(
    xx,
    SATO_SLOPE * xx * (1 - args.sato_band),
    SATO_SLOPE * xx * (1 + args.sato_band),
    alpha=0.18,
    label=f"Sato ±{int(args.sato_band*100)}%",
)
ax.plot(xx, SATO_SLOPE * xx, label="Sato: h/D = 1.30 Fr'")
ax.errorbar(
    frs, hs,
    yerr=[r["stdHOverD"] for r in summary],
    fmt="o", capsize=4,
    label="SRC/MPCD",
)
if math.isfinite(depth_fit):
    ax.plot(xx, depth_fit * xx, "--", label=f"SRC fit: {depth_fit:.3f} Fr'")
ax.set_xlabel("Target modified Froude number Fr'")
ax.set_ylabel("Cavity depth h/D")
ax.grid(True, alpha=0.25)
ax.legend()
fig.tight_layout()
fig.savefig(out / "h_over_D_vs_target_Fr.pdf", bbox_inches="tight")
fig.savefig(out / "h_over_D_vs_target_Fr.png", dpi=180, bbox_inches="tight")
plt.close(fig)

# 3. Width trend
fig, ax = plt.subplots(figsize=(7.2, 5.2))
ax.errorbar(
    frs,
    [r["meanWidth10DepthOverD"] for r in summary],
    yerr=[r["stdWidth10DepthOverD"] for r in summary],
    fmt="o-", capsize=4,
    label="width at 10% cavity depth",
)
ax.errorbar(
    frs,
    [r["meanWidth50DepthOverD"] for r in summary],
    yerr=[r["stdWidth50DepthOverD"] for r in summary],
    fmt="s-", capsize=4,
    label="width at 50% cavity depth",
)
ax.set_xlabel("Target modified Froude number Fr'")
ax.set_ylabel("Cavity width / D")
ax.grid(True, alpha=0.25)
ax.legend()
fig.tight_layout()
fig.savefig(out / "cavity_width_vs_target_Fr.pdf", bbox_inches="tight")
fig.savefig(out / "cavity_width_vs_target_Fr.png", dpi=180, bbox_inches="tight")
plt.close(fig)

# 4. Mean profiles
fig, ax = plt.subplots(figsize=(7.2, 5.2))
for fr in sorted(profiles_by_fr):
    rows = [r for r in profile_rows if r["targetFr"] == fr]
    x = np.array([r["xOverD"] for r in rows])
    y = np.array([r["meanDepressionOverD"] for r in rows])
    m = np.isfinite(y) & (np.abs(x) <= 5.0)
    ax.plot(x[m], y[m], label=f"Fr'={fr:g}")
ax.set_xlabel("(x - x_j) / D")
ax.set_ylabel("Mean interface depression / D")
ax.grid(True, alpha=0.25)
ax.legend()
fig.tight_layout()
fig.savefig(out / "mean_cavity_profiles.pdf", bbox_inches="tight")
fig.savefig(out / "mean_cavity_profiles.png", dpi=180, bbox_inches="tight")
plt.close(fig)

print(f"[0493x24ae] wrote {out/'article_interface_summary.csv'}")
print(f"[0493x24ae] wrote {out/'shape_fit_summary.csv'}")
print(f"[0493x24ae] wrote PDF article figures under {out}")
