#!/usr/bin/env python3
"""
0493x24ai — audit of gas momentum-flux calculation for the Sato article runs.

Why this audit exists
---------------------
The first gas-loading analyzer found a suspicious outlier at Fr'=0.25:
the incident/nozzle axial momentum proxy was ~0.21, versus ~0.74 for
Fr'=0.40, 0.55 and 0.6603645.

This analyzer tests whether that outlier is caused by the diagnostic
definition itself (probe height / integration width / lateral spreading)
rather than by the underlying SRC/MPCD interaction.

It does NOT modify the solver and requires no new simulation.

Recorded fields required
------------------------
rho2, ux, uy

For each case it evaluates:
  J_y(W,y) = integral rho2 * max(-uy,0)^2 dx
  M(W,y)   = integral rho2 * max(-uy,0) dx

and diagnostic proxies:
  Kvec(W,y) = integral rho2 * (ux^2 + uy^2) dx
  Klat(W,y) = integral rho2 * ux^2 dx

at several gas-gap heights and several integration widths.

Default probe heights above the initial bath:
  0.10 D, 0.25 D, 0.50 D

Default transverse widths:
  1.0 D, 1.5 D, 2.0 D, 3.0 D, 4.0 D

The nozzle reference is always evaluated inside the nozzle over width D.

Interpretation
--------------
If Fr'=0.25 recovers toward the other cases when W increases, the original
D-wide incident probe was under-capturing a broadened weak jet.

If it recovers when the probe is moved upward toward the nozzle, the original
probe was too close to the deforming interface / recirculation zone.

If neither happens, but Kvec remains much larger than J_y, the weak jet is
strongly redirected laterally.

If none of those happens, the weak case genuinely carries much less downward
momentum into the interface-side region and the physics/run setup itself needs
further inspection.

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
    out = {}
    for p in sorted((root / "logs").glob("environment_*.env")):
        out.update(read_kv(p))
    return out


def parse_params(root: Path):
    out = {}
    for p in sorted((root / "params").glob("*.kv")):
        out.update(read_kv(p))
    return out


def find_manifest(root: Path):
    cands = list((root / "output" / "recordings").glob("**/manifest.kv"))
    return cands[0] if cands else None


def detect_grid(root: Path, nx_default, ny_default):
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


def parse_jet_speed(params, env):
    for k, v in params.items():
        if k.startswith("openBoundarySegment") and k != "openBoundarySegmentCount":
            tok = str(v).split()
            if len(tok) >= 6 and tok[1].lower() == "inlet":
                ux = fv(tok[4])
                uy = fv(tok[5])
                if math.isfinite(ux) and math.isfinite(uy):
                    return math.hypot(ux, uy)
    return fv(env.get("JET_SPEED"))


def step_from_name(path: Path):
    m = re.search(r"step_(\d+)_field_rho2\.f32$", path.name)
    return int(m.group(1)) if m else None


def load_f32(path: Path, nx, ny):
    a = np.fromfile(path, dtype="<f4")
    if a.size != nx * ny:
        raise ValueError(f"{path}: expected {nx*ny} floats, got {a.size}")
    return a.reshape((ny, nx))


def mean_std(vals):
    a = np.asarray([v for v in vals if math.isfinite(v)], float)
    if len(a) == 0:
        return math.nan, math.nan
    return float(np.mean(a)), float(np.std(a, ddof=1)) if len(a) > 1 else 0.0


def section_metrics(rho, ux, uy, xs, iy, center_x, width, dx):
    mask = np.abs(xs - center_x) <= 0.5 * width

    r = np.asarray(rho[iy, mask], float)
    u = np.asarray(ux[iy, mask], float)
    v = np.asarray(uy[iy, mask], float)

    good = np.isfinite(r) & np.isfinite(u) & np.isfinite(v) & (r >= 0)
    r = r[good]
    u = u[good]
    v = v[good]

    if len(r) == 0:
        return {
            "rhoMean": math.nan,
            "downVelocityRhoWeighted": math.nan,
            "massFluxDown": math.nan,
            "axialMomentumDown": math.nan,
            "axialMomentumSigned": math.nan,
            "vectorSpeedSqProxy": math.nan,
            "lateralSpeedSqProxy": math.nan,
            "lateralFraction": math.nan,
            "cells": 0,
        }

    down = np.maximum(-v, 0.0)
    wr = float(np.sum(r))
    vdown = float(np.sum(r * down) / wr) if wr > 0 else math.nan

    jdown = float(np.sum(r * down * down) * dx)

    # Signed vertical momentum-flux proxy through a horizontal section.
    # Downward velocities contribute positively; upward backflow negatively.
    jsigned = float(np.sum(r * (-v) * np.abs(v)) * dx)

    kvec = float(np.sum(r * (u * u + v * v)) * dx)
    klat = float(np.sum(r * u * u) * dx)
    latfrac = klat / kvec if kvec > 0 else math.nan

    return {
        "rhoMean": float(np.mean(r)),
        "downVelocityRhoWeighted": vdown,
        "massFluxDown": float(np.sum(r * down) * dx),
        "axialMomentumDown": jdown,
        "axialMomentumSigned": jsigned,
        "vectorSpeedSqProxy": kvec,
        "lateralSpeedSqProxy": klat,
        "lateralFraction": latfrac,
        "cells": int(len(r)),
    }


def fit_origin(x, y):
    x = np.asarray(x, float)
    y = np.asarray(y, float)
    m = np.isfinite(x) & np.isfinite(y)
    x = x[m]
    y = y[m]
    if len(x) < 2 or np.dot(x, x) <= 0:
        return math.nan, math.nan
    a = float(np.dot(x, y) / np.dot(x, x))
    yp = a * x
    ssr = float(np.sum((y - yp) ** 2))
    sst = float(np.sum((y - np.mean(y)) ** 2))
    r2 = 1.0 - ssr / sst if sst > 0 else math.nan
    return a, r2


ap = argparse.ArgumentParser()
ap.add_argument("--case", action="append", required=True,
                help="TARGET_FR:RUN_ROOT; repeat for each case")
ap.add_argument("--out", default="analysis/0493x24ai_momentum_audit")

ap.add_argument("--nx", type=int, default=400)
ap.add_argument("--ny", type=int, default=256)
ap.add_argument("--Lx", type=float, default=1.5625)
ap.add_argument("--Ly", type=float, default=1.0)

ap.add_argument("--jet-center-x", type=float, default=0.78125)
ap.add_argument("--D", type=float, default=0.078125)
ap.add_argument("--bath-height", type=float, default=0.81640625)
ap.add_argument("--nozzle-exit-y", type=float, default=0.87890625)

ap.add_argument("--initial-cutoff", type=float, default=1.0)

ap.add_argument("--heights-over-D", default="0.10,0.25,0.50",
                help="comma-separated incident probe heights above initial bath")
ap.add_argument("--widths-over-D", default="1.0,1.5,2.0,3.0,4.0",
                help="comma-separated transverse integration widths")

ap.add_argument("--nozzle-height-over-D", type=float, default=0.55,
                help="nozzle reference section: nozzleExit + value*D")
ap.add_argument("--nozzle-width-over-D", type=float, default=1.0)

args = ap.parse_args()

heights = [float(x) for x in args.heights_over_D.split(",") if x.strip()]
widths = [float(x) for x in args.widths_over_D.split(",") if x.strip()]

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
    params = parse_params(root)
    dt = fv(env.get("DT"), 0.0004)
    nx, ny, _ = detect_grid(root, args.nx, args.ny)
    U = parse_jet_speed(params, env)

    cases.append({
        "fr": fr,
        "root": root,
        "env": env,
        "params": params,
        "dt": dt,
        "nx": nx,
        "ny": ny,
        "U": U,
    })

history = []

for case in cases:
    root = case["root"]

    rho_files = sorted(
        (root / "output" / "recordings").glob("**/step_*_field_rho2.f32")
    )
    if not rho_files:
        print(f"[0493x24ai] WARNING no rho2 frames under {root}")
        continue

    nx, ny = case["nx"], case["ny"]
    dx = args.Lx / nx
    dy = args.Ly / ny
    xs = (np.arange(nx) + 0.5) * dx
    ys = (np.arange(ny) + 0.5) * dy

    y_nozzle = args.nozzle_exit_y + args.nozzle_height_over_D * args.D
    iy_nozzle = int(np.argmin(np.abs(ys - y_nozzle)))

    for rp in rho_files:
        step = step_from_name(rp)
        if step is None:
            continue

        up = rp.with_name(f"step_{step:010d}_field_uy.f32")
        xp = rp.with_name(f"step_{step:010d}_field_ux.f32")
        if not up.exists() or not xp.exists():
            continue

        t = step * case["dt"]
        if t < args.initial_cutoff:
            continue

        rho = load_f32(rp, nx, ny)
        ux = load_f32(xp, nx, ny)
        uy = load_f32(up, nx, ny)

        noz = section_metrics(
            rho, ux, uy, xs, iy_nozzle,
            args.jet_center_x,
            args.nozzle_width_over_D * args.D,
            dx,
        )

        for hD in heights:
            y_inc = args.bath_height + hD * args.D
            iy_inc = int(np.argmin(np.abs(ys - y_inc)))

            for wD in widths:
                inc = section_metrics(
                    rho, ux, uy, xs, iy_inc,
                    args.jet_center_x,
                    wD * args.D,
                    dx,
                )

                history.append({
                    "targetFr": case["fr"],
                    "runRoot": str(root),
                    "step": step,
                    "time": t,
                    "nominalJetSpeed": case["U"],
                    "probeHeightOverD": hD,
                    "probeY": ys[iy_inc],
                    "widthOverD": wD,

                    "incidentRhoMean": inc["rhoMean"],
                    "incidentDownVelocity": inc["downVelocityRhoWeighted"],
                    "incidentMassFluxDown": inc["massFluxDown"],
                    "incidentAxialMomentumDown": inc["axialMomentumDown"],
                    "incidentAxialMomentumSigned": inc["axialMomentumSigned"],
                    "incidentVectorSpeedSqProxy": inc["vectorSpeedSqProxy"],
                    "incidentLateralSpeedSqProxy": inc["lateralSpeedSqProxy"],
                    "incidentLateralFraction": inc["lateralFraction"],

                    "nozzleAxialMomentumDown": noz["axialMomentumDown"],
                    "nozzleAxialMomentumSigned": noz["axialMomentumSigned"],
                    "nozzleVectorSpeedSqProxy": noz["vectorSpeedSqProxy"],

                    "incidentToNozzleAxialRatio": (
                        inc["axialMomentumDown"] / noz["axialMomentumDown"]
                        if math.isfinite(inc["axialMomentumDown"])
                        and math.isfinite(noz["axialMomentumDown"])
                        and noz["axialMomentumDown"] > 0
                        else math.nan
                    ),
                    "incidentToNozzleSignedRatio": (
                        inc["axialMomentumSigned"] / noz["axialMomentumSigned"]
                        if math.isfinite(inc["axialMomentumSigned"])
                        and math.isfinite(noz["axialMomentumSigned"])
                        and abs(noz["axialMomentumSigned"]) > 0
                        else math.nan
                    ),
                })

if not history:
    raise SystemExit("[0493x24ai] no complete rho2/ux/uy frame triplets found")

history.sort(key=lambda r: (
    r["targetFr"], r["probeHeightOverD"], r["widthOverD"], r["time"]
))

with (out / "momentum_audit_history.csv").open("w", newline="") as h:
    fields = list(history[0].keys())
    w = csv.DictWriter(h, fieldnames=fields)
    w.writeheader()
    w.writerows(history)

groups = defaultdict(list)
for r in history:
    key = (r["targetFr"], r["probeHeightOverD"], r["widthOverD"])
    groups[key].append(r)

summary = []

# Need max-width references for capture fraction.
max_w = max(widths)

for (fr, hD, wD), rr in sorted(groups.items()):
    jmean, jstd = mean_std([r["incidentAxialMomentumDown"] for r in rr])
    jsmean, jsstd = mean_std([r["incidentAxialMomentumSigned"] for r in rr])
    km, ks = mean_std([r["incidentVectorSpeedSqProxy"] for r in rr])
    lm, ls = mean_std([r["incidentLateralSpeedSqProxy"] for r in rr])
    lf, lfs = mean_std([r["incidentLateralFraction"] for r in rr])
    vm, vs = mean_std([r["incidentDownVelocity"] for r in rr])
    mm, ms = mean_std([r["incidentMassFluxDown"] for r in rr])
    ratio, ratiostd = mean_std([r["incidentToNozzleAxialRatio"] for r in rr])
    sratio, sratiostd = mean_std([r["incidentToNozzleSignedRatio"] for r in rr])
    noz, nozstd = mean_std([r["nozzleAxialMomentumDown"] for r in rr])

    rrmax = groups.get((fr, hD, max_w), [])
    jmax, _ = mean_std([r["incidentAxialMomentumDown"] for r in rrmax])
    capture = jmean / jmax if math.isfinite(jmean) and math.isfinite(jmax) and jmax > 0 else math.nan

    summary.append({
        "targetFr": fr,
        "probeHeightOverD": hD,
        "widthOverD": wD,
        "frames": len(rr),

        "meanIncidentAxialMomentumDown": jmean,
        "stdIncidentAxialMomentumDown": jstd,
        "meanIncidentAxialMomentumSigned": jsmean,
        "stdIncidentAxialMomentumSigned": jsstd,

        "meanIncidentVectorSpeedSqProxy": km,
        "stdIncidentVectorSpeedSqProxy": ks,
        "meanIncidentLateralSpeedSqProxy": lm,
        "stdIncidentLateralSpeedSqProxy": ls,
        "meanIncidentLateralFraction": lf,
        "stdIncidentLateralFraction": lfs,

        "meanIncidentDownVelocity": vm,
        "stdIncidentDownVelocity": vs,
        "meanIncidentMassFluxDown": mm,
        "stdIncidentMassFluxDown": ms,

        "meanNozzleAxialMomentumDown": noz,
        "stdNozzleAxialMomentumDown": nozstd,

        "meanIncidentToNozzleAxialRatio": ratio,
        "stdIncidentToNozzleAxialRatio": ratiostd,
        "meanIncidentToNozzleSignedRatio": sratio,
        "stdIncidentToNozzleSignedRatio": sratiostd,

        "captureFractionRelativeToMaxWidth": capture,
    })

with (out / "momentum_audit_summary.csv").open("w", newline="") as h:
    fields = list(summary[0].keys())
    w = csv.DictWriter(h, fieldnames=fields)
    w.writeheader()
    w.writerows(summary)

# Compact diagnostic table for default/most relevant combinations.
default_h = min(heights, key=lambda x: abs(x - 0.25))
default_w = min(widths, key=lambda x: abs(x - 1.0))

baseline = [
    r for r in summary
    if abs(r["probeHeightOverD"] - default_h) < 1e-12
    and abs(r["widthOverD"] - default_w) < 1e-12
]

# Nozzle scaling diagnostic.
frs = [r["targetFr"] for r in baseline]
jnoz = [r["meanNozzleAxialMomentumDown"] for r in baseline]
anoz, r2noz = fit_origin(frs, jnoz)

# Incident scaling for each width at the default height.
width_fit_rows = []
for wD in widths:
    rr = [
        r for r in summary
        if abs(r["probeHeightOverD"] - default_h) < 1e-12
        and abs(r["widthOverD"] - wD) < 1e-12
    ]
    a, r2 = fit_origin(
        [r["targetFr"] for r in rr],
        [r["meanIncidentAxialMomentumDown"] for r in rr],
    )
    width_fit_rows.append((wD, a, r2))

with (out / "report.txt").open("w") as h:
    h.write("0493x24ai — gas momentum-flux diagnostic audit\n")
    h.write("================================================\n\n")

    h.write(f"analysis starts at t={args.initial_cutoff:g}\n")
    h.write(f"incident heights/D = {heights}\n")
    h.write(f"integration widths/D = {widths}\n")
    h.write(
        f"nozzle reference: y = exit + {args.nozzle_height_over_D:g}D, "
        f"width={args.nozzle_width_over_D:g}D\n\n"
    )

    h.write("Original-definition baseline (height=0.25D, width=D)\n")
    h.write("----------------------------------------------------\n")
    for r in baseline:
        h.write(
            f"Fr'={r['targetFr']:.9g} "
            f"Jinc={r['meanIncidentAxialMomentumDown']:.7g} "
            f"Jnoz={r['meanNozzleAxialMomentumDown']:.7g} "
            f"Jinc/Jnoz={r['meanIncidentToNozzleAxialRatio']:.5g} "
            f"lateralFraction={r['meanIncidentLateralFraction']:.5g}\n"
        )

    h.write(
        f"\nNozzle momentum scaling: Jnoz={anoz:.8g} Fr', R2={r2noz:.6g}\n\n"
    )

    h.write("Incident momentum linearity at height=0.25D vs integration width\n")
    h.write("----------------------------------------------------------------\n")
    for wD, a, r2 in width_fit_rows:
        h.write(f"W={wD:g}D: Jinc={a:.8g} Fr', R2={r2:.6g}\n")

    h.write("\nCapture fraction J(W)/J(Wmax)\n")
    h.write("--------------------------------\n")
    for fr in sorted(set(r["targetFr"] for r in summary)):
        h.write(f"Fr'={fr:.9g}\n")
        for hD in heights:
            rr = [
                r for r in summary
                if r["targetFr"] == fr
                and abs(r["probeHeightOverD"] - hD) < 1e-12
            ]
            vals = ", ".join(
                f"{r['widthOverD']:g}D:{r['captureFractionRelativeToMaxWidth']:.3f}"
                for r in rr
            )
            h.write(f"  y=bath+{hD:g}D -> {vals}\n")

    h.write("\nAutomatic interpretation guide\n")
    h.write("------------------------------\n")
    h.write(
        "1) If Fr'=0.25 capture at W=D is much lower than at W=3-4D, "
        "the original probe was too narrow.\n"
    )
    h.write(
        "2) If Fr'=0.25 improves strongly at y=bath+0.5D, the original "
        "probe was too close to the interface / recirculation region.\n"
    )
    h.write(
        "3) If lateralFraction is much higher at Fr'=0.25, the weak jet "
        "is redirected/spread laterally and Jy alone under-represents its kinetic loading.\n"
    )
    h.write(
        "4) If Jnoz/Fr' is already anomalous at Fr'=0.25, inspect inlet/nozzle "
        "delivery before interpreting any incident ratio.\n"
    )

# --- Figures ---

# 1. Capture fraction vs width, default height.
fig, ax = plt.subplots(figsize=(7.4, 5.2))
for fr in sorted(set(r["targetFr"] for r in summary)):
    rr = sorted(
        [
            r for r in summary
            if r["targetFr"] == fr
            and abs(r["probeHeightOverD"] - default_h) < 1e-12
        ],
        key=lambda r: r["widthOverD"],
    )
    ax.plot(
        [r["widthOverD"] for r in rr],
        [r["captureFractionRelativeToMaxWidth"] for r in rr],
        marker="o",
        label=f"Fr'={fr:g}",
    )
ax.set_xlabel("Integration width / D")
ax.set_ylabel("Captured axial momentum / value at maximum width")
ax.set_ylim(0, 1.08)
ax.grid(True, alpha=0.25)
ax.legend()
fig.tight_layout()
fig.savefig(out / "momentum_capture_vs_width.pdf", bbox_inches="tight")
fig.savefig(out / "momentum_capture_vs_width.png", dpi=180, bbox_inches="tight")
plt.close(fig)

# 2. Incident/nozzle ratio vs Fr for all widths at default height.
fig, ax = plt.subplots(figsize=(7.4, 5.2))
for wD in widths:
    rr = sorted(
        [
            r for r in summary
            if abs(r["probeHeightOverD"] - default_h) < 1e-12
            and abs(r["widthOverD"] - wD) < 1e-12
        ],
        key=lambda r: r["targetFr"],
    )
    ax.plot(
        [r["targetFr"] for r in rr],
        [r["meanIncidentToNozzleAxialRatio"] for r in rr],
        marker="o",
        label=f"W={wD:g}D",
    )
ax.set_xlabel("Target modified Froude number Fr'")
ax.set_ylabel("Incident / nozzle axial-momentum proxy")
ax.grid(True, alpha=0.25)
ax.legend()
fig.tight_layout()
fig.savefig(out / "incident_to_nozzle_ratio_width_sweep.pdf", bbox_inches="tight")
fig.savefig(out / "incident_to_nozzle_ratio_width_sweep.png", dpi=180, bbox_inches="tight")
plt.close(fig)

# 3. Height sensitivity for W=3D.
w_ref = min(widths, key=lambda x: abs(x - 3.0))
fig, ax = plt.subplots(figsize=(7.4, 5.2))
for hD in heights:
    rr = sorted(
        [
            r for r in summary
            if abs(r["probeHeightOverD"] - hD) < 1e-12
            and abs(r["widthOverD"] - w_ref) < 1e-12
        ],
        key=lambda r: r["targetFr"],
    )
    ax.plot(
        [r["targetFr"] for r in rr],
        [r["meanIncidentToNozzleAxialRatio"] for r in rr],
        marker="o",
        label=f"y=bath+{hD:g}D",
    )
ax.set_xlabel("Target modified Froude number Fr'")
ax.set_ylabel(f"Incident / nozzle axial-momentum proxy (W={w_ref:g}D)")
ax.grid(True, alpha=0.25)
ax.legend()
fig.tight_layout()
fig.savefig(out / "incident_to_nozzle_ratio_height_sweep.pdf", bbox_inches="tight")
fig.savefig(out / "incident_to_nozzle_ratio_height_sweep.png", dpi=180, bbox_inches="tight")
plt.close(fig)

# 4. Lateral fraction at W=3D.
fig, ax = plt.subplots(figsize=(7.4, 5.2))
for hD in heights:
    rr = sorted(
        [
            r for r in summary
            if abs(r["probeHeightOverD"] - hD) < 1e-12
            and abs(r["widthOverD"] - w_ref) < 1e-12
        ],
        key=lambda r: r["targetFr"],
    )
    ax.plot(
        [r["targetFr"] for r in rr],
        [r["meanIncidentLateralFraction"] for r in rr],
        marker="o",
        label=f"y=bath+{hD:g}D",
    )
ax.set_xlabel("Target modified Froude number Fr'")
ax.set_ylabel(r"Lateral fraction $\int\rho_2u_x^2 dx / \int\rho_2(u_x^2+u_y^2) dx$")
ax.grid(True, alpha=0.25)
ax.legend()
fig.tight_layout()
fig.savefig(out / "lateral_fraction_vs_Fr.pdf", bbox_inches="tight")
fig.savefig(out / "lateral_fraction_vs_Fr.png", dpi=180, bbox_inches="tight")
plt.close(fig)

# 5. Nozzle momentum scaling itself.
fig, ax = plt.subplots(figsize=(7.4, 5.2))
ax.plot(frs, jnoz, "o", label="nozzle momentum proxy")
if math.isfinite(anoz):
    xx = np.linspace(0, max(frs) * 1.08, 200)
    ax.plot(xx, anoz * xx, "--", label=f"fit through origin, R²={r2noz:.3f}")
ax.set_xlabel("Target modified Froude number Fr'")
ax.set_ylabel("Nozzle axial-momentum proxy")
ax.grid(True, alpha=0.25)
ax.legend()
fig.tight_layout()
fig.savefig(out / "nozzle_momentum_vs_target_Fr.pdf", bbox_inches="tight")
fig.savefig(out / "nozzle_momentum_vs_target_Fr.png", dpi=180, bbox_inches="tight")
plt.close(fig)

print(f"[0493x24ai] wrote {out/'momentum_audit_summary.csv'}")
print(f"[0493x24ai] wrote {out/'report.txt'}")
print(f"[0493x24ai] wrote PDF audit figures under {out}")
