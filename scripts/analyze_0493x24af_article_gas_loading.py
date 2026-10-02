#!/usr/bin/env python3
"""
0493x24af — gas-side loading / transfer audit for uninterrupted Sato article runs.

Purpose
-------
This is NOT a separate cavity-physics study.  It checks that the gas loading
actually delivered to the liquid increases coherently with the imposed Fr',
which strengthens the interpretation of the Sato comparison as validation of
the SRC/MPCD gas-liquid interaction closure.

Using rho2, ux, uy recordings, the analyzer measures at two horizontal sections:
  * nozzle probe: inside the nozzle, above its exit;
  * incident probe: in the gas gap, above the initial liquid level.

For each section it reports:
  - rho2-weighted downward velocity;
  - mass-flux proxy       integral rho2 * max(-uy,0) dx;
  - normal momentum proxy integral rho2 * max(-uy,0)^2 dx.

The most useful closure-oriented diagnostic is:
  incidentMomentum / nozzleMomentum,
which measures how much of the imposed gas momentum reaches the interface-side
probe without invoking a cavity-specific theoretical model.

Input
-----
  --case TARGET_FR:RUN_ROOT

Outputs
-------
  gas_loading_history.csv
  gas_loading_summary.csv
  report.txt
  incident_momentum_vs_target_Fr.pdf
  incident_to_nozzle_momentum_ratio_vs_Fr.pdf
  incident_downward_velocity_time_series.pdf

PNG previews are also written.
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
    env = {}
    for p in sorted((root / "logs").glob("environment_*.env")):
        env.update(read_kv(p))
    return env


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
    # Prefer the explicit top inlet velocity in the generated params.
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


def weighted_section_metrics(rho, ux, uy, xs, iy, xmask, dx):
    r = np.asarray(rho[iy, xmask], float)
    vx = np.asarray(ux[iy, xmask], float)
    vy = np.asarray(uy[iy, xmask], float)

    good = np.isfinite(r) & np.isfinite(vx) & np.isfinite(vy) & (r >= 0)
    r = r[good]
    vx = vx[good]
    vy = vy[good]
    if len(r) == 0:
        return dict(
            rhoMean=math.nan,
            downVelocityRhoWeighted=math.nan,
            massFluxProxy=math.nan,
            normalMomentumProxy=math.nan,
            lateralMomentumProxy=math.nan,
        )

    down = np.maximum(-vy, 0.0)
    wr = float(np.sum(r))
    vdown = float(np.sum(r * down) / wr) if wr > 0 else math.nan

    return dict(
        rhoMean=float(np.mean(r)),
        downVelocityRhoWeighted=vdown,
        massFluxProxy=float(np.sum(r * down) * dx),
        normalMomentumProxy=float(np.sum(r * down * down) * dx),
        lateralMomentumProxy=float(np.sum(r * vx * vx) * dx),
    )


def mean_std(vals):
    a = np.asarray([x for x in vals if math.isfinite(x)], float)
    if len(a) == 0:
        return math.nan, math.nan
    return float(np.mean(a)), float(np.std(a, ddof=1)) if len(a) > 1 else 0.0


def linfit_origin(x, y):
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
                help="TARGET_FR:RUN_ROOT; repeat for each uninterrupted case")
ap.add_argument("--out", default="analysis/0493x24af_article_gas_loading")
ap.add_argument("--nx", type=int, default=400)
ap.add_argument("--ny", type=int, default=256)
ap.add_argument("--Lx", type=float, default=1.5625)
ap.add_argument("--Ly", type=float, default=1.0)
ap.add_argument("--jet-center-x", type=float, default=0.78125)
ap.add_argument("--D", type=float, default=0.078125)
ap.add_argument("--bath-height", type=float, default=0.81640625)
ap.add_argument("--nozzle-exit-y", type=float, default=0.87890625)
ap.add_argument("--initial-cutoff", type=float, default=1.0)
ap.add_argument("--incident-height-over-D", type=float, default=0.25,
                help="incident probe y = bathHeight + this*D")
ap.add_argument("--nozzle-height-over-D", type=float, default=0.55,
                help="nozzle probe y = nozzleExit + this*D")
ap.add_argument("--aperture-width-over-D", type=float, default=1.0,
                help="horizontal integration width centred on jet axis")
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
    params = parse_params(root)
    dt = fv(env.get("DT"), 0.0004)
    nx, ny, man = detect_grid(root, args.nx, args.ny)
    U = parse_jet_speed(params, env)
    cases.append(dict(fr=fr, root=root, env=env, params=params, dt=dt, nx=nx, ny=ny, U=U))

rows = []

for case in cases:
    root = case["root"]
    rho_files = sorted((root / "output" / "recordings").glob("**/step_*_field_rho2.f32"))
    if not rho_files:
        print(f"[0493x24af] WARNING no rho2 recordings under {root}")
        continue

    nx, ny = case["nx"], case["ny"]
    dx = args.Lx / nx
    dy = args.Ly / ny
    xs = (np.arange(nx) + 0.5) * dx
    ys = (np.arange(ny) + 0.5) * dy

    halfw = 0.5 * args.aperture_width_over_D * args.D
    xmask = np.abs(xs - args.jet_center_x) <= halfw

    y_inc = args.bath_height + args.incident_height_over_D * args.D
    y_noz = args.nozzle_exit_y + args.nozzle_height_over_D * args.D
    iy_inc = int(np.argmin(np.abs(ys - y_inc)))
    iy_noz = int(np.argmin(np.abs(ys - y_noz)))

    for rp in rho_files:
        step = step_from_name(rp)
        if step is None:
            continue

        up = rp.with_name(f"step_{step:010d}_field_uy.f32")
        xp = rp.with_name(f"step_{step:010d}_field_ux.f32")
        if not up.exists() or not xp.exists():
            print(f"[0493x24af] WARNING missing ux/uy matching {rp}")
            continue

        rho = load_f32(rp, nx, ny)
        ux = load_f32(xp, nx, ny)
        uy = load_f32(up, nx, ny)

        inc = weighted_section_metrics(rho, ux, uy, xs, iy_inc, xmask, dx)
        noz = weighted_section_metrics(rho, ux, uy, xs, iy_noz, xmask, dx)

        t = step * case["dt"]
        rows.append({
            "targetFr": case["fr"],
            "runRoot": str(root),
            "localStep": step,
            "time": t,
            "includeForArticle": int(t >= args.initial_cutoff),
            "nominalJetSpeed": case["U"],
            "incidentProbeY": ys[iy_inc],
            "nozzleProbeY": ys[iy_noz],
            "incidentRho2Mean": inc["rhoMean"],
            "incidentDownVelocity": inc["downVelocityRhoWeighted"],
            "incidentSpeedRatioToNominal": (
                inc["downVelocityRhoWeighted"] / case["U"]
                if math.isfinite(case["U"]) and case["U"] > 0
                else math.nan
            ),
            "incidentMassFluxProxy": inc["massFluxProxy"],
            "incidentNormalMomentumProxy": inc["normalMomentumProxy"],
            "incidentLateralMomentumProxy": inc["lateralMomentumProxy"],
            "nozzleRho2Mean": noz["rhoMean"],
            "nozzleDownVelocity": noz["downVelocityRhoWeighted"],
            "nozzleSpeedRatioToNominal": (
                noz["downVelocityRhoWeighted"] / case["U"]
                if math.isfinite(case["U"]) and case["U"] > 0
                else math.nan
            ),
            "nozzleMassFluxProxy": noz["massFluxProxy"],
            "nozzleNormalMomentumProxy": noz["normalMomentumProxy"],
            "incidentToNozzleMomentumRatio": (
                inc["normalMomentumProxy"] / noz["normalMomentumProxy"]
                if math.isfinite(inc["normalMomentumProxy"])
                and math.isfinite(noz["normalMomentumProxy"])
                and noz["normalMomentumProxy"] > 0
                else math.nan
            ),
        })

if not rows:
    raise SystemExit("[0493x24af] no complete rho2/ux/uy frame triplets found")

rows.sort(key=lambda r: (r["targetFr"], r["time"]))

with (out / "gas_loading_history.csv").open("w", newline="") as h:
    fields = list(rows[0].keys())
    w = csv.DictWriter(h, fieldnames=fields)
    w.writeheader()
    w.writerows(rows)

groups = defaultdict(list)
for r in rows:
    if r["includeForArticle"]:
        groups[r["targetFr"]].append(r)

summary = []
for fr in sorted(groups):
    rr = groups[fr]
    ivm, ivs = mean_std([r["incidentDownVelocity"] for r in rr])
    irm, irs = mean_std([r["incidentSpeedRatioToNominal"] for r in rr])
    ijm, ijs = mean_std([r["incidentNormalMomentumProxy"] for r in rr])
    njm, njs = mean_std([r["nozzleNormalMomentumProxy"] for r in rr])
    trm, trs = mean_std([r["incidentToNozzleMomentumRatio"] for r in rr])
    rhom, rhos = mean_std([r["incidentRho2Mean"] for r in rr])

    summary.append({
        "targetFr": fr,
        "frames": len(rr),
        "timeStart": min(r["time"] for r in rr),
        "timeEnd": max(r["time"] for r in rr),
        "meanIncidentDownVelocity": ivm,
        "stdIncidentDownVelocity": ivs,
        "meanIncidentSpeedRatioToNominal": irm,
        "stdIncidentSpeedRatioToNominal": irs,
        "meanIncidentRho2": rhom,
        "stdIncidentRho2": rhos,
        "meanIncidentMomentumProxy": ijm,
        "stdIncidentMomentumProxy": ijs,
        "meanNozzleMomentumProxy": njm,
        "stdNozzleMomentumProxy": njs,
        "meanIncidentToNozzleMomentumRatio": trm,
        "stdIncidentToNozzleMomentumRatio": trs,
    })

with (out / "gas_loading_summary.csv").open("w", newline="") as h:
    fields = list(summary[0].keys())
    w = csv.DictWriter(h, fieldnames=fields)
    w.writeheader()
    w.writerows(summary)

frs = [r["targetFr"] for r in summary]
J = [r["meanIncidentMomentumProxy"] for r in summary]
aJ, r2J = linfit_origin(frs, J)

with (out / "report.txt").open("w") as h:
    h.write("0493x24af — article gas-side loading / transfer audit\n")
    h.write("===================================================\n\n")
    h.write(f"Initial transient excluded: t < {args.initial_cutoff:g}\n")
    h.write(f"Incident probe y = bathHeight + {args.incident_height_over_D:g} D\n")
    h.write(f"Nozzle probe y = nozzleExit + {args.nozzle_height_over_D:g} D\n")
    h.write(f"Integration width = {args.aperture_width_over_D:g} D\n\n")
    for r in summary:
        h.write(
            f"Fr'={r['targetFr']:.9g}  "
            f"<Vdown_inc>={r['meanIncidentDownVelocity']:.6g} +/- {r['stdIncidentDownVelocity']:.4g}  "
            f"<Vdown_inc/Uj>={r['meanIncidentSpeedRatioToNominal']:.6g}  "
            f"<Jinc>={r['meanIncidentMomentumProxy']:.6g} +/- {r['stdIncidentMomentumProxy']:.4g}  "
            f"<Jinc/Jnoz>={r['meanIncidentToNozzleMomentumRatio']:.6g} +/- "
            f"{r['stdIncidentToNozzleMomentumRatio']:.4g}\n"
        )
    h.write(
        f"\nIncident normal momentum proxy fit through origin: "
        f"J_inc={aJ:.8g} Fr' (R2={r2J:.8g})\n"
    )
    h.write(
        "\nInterpretation: this analyzer checks coherence of the delivered gas loading. "
        "It does not define or fit a cavity-specific energy-efficiency parameter.\n"
    )

# Figure 1: incident momentum vs Fr
fig, ax = plt.subplots(figsize=(7.2, 5.2))
ax.errorbar(
    frs, J,
    yerr=[r["stdIncidentMomentumProxy"] for r in summary],
    fmt="o", capsize=4,
    label="incident gas momentum proxy",
)
if math.isfinite(aJ):
    xx = np.linspace(0, max(frs) * 1.1, 300)
    ax.plot(xx, aJ * xx, "--", label=f"fit through origin, R²={r2J:.3f}")
ax.set_xlabel("Target modified Froude number Fr'")
ax.set_ylabel(r"Incident normal momentum proxy $\int \rho_2 u_y^2\,dx$")
ax.grid(True, alpha=0.25)
ax.legend()
fig.tight_layout()
fig.savefig(out / "incident_momentum_vs_target_Fr.pdf", bbox_inches="tight")
fig.savefig(out / "incident_momentum_vs_target_Fr.png", dpi=180, bbox_inches="tight")
plt.close(fig)

# Figure 2: transfer ratio
fig, ax = plt.subplots(figsize=(7.2, 5.2))
ax.errorbar(
    frs,
    [r["meanIncidentToNozzleMomentumRatio"] for r in summary],
    yerr=[r["stdIncidentToNozzleMomentumRatio"] for r in summary],
    fmt="o-", capsize=4,
)
ax.set_xlabel("Target modified Froude number Fr'")
ax.set_ylabel("Incident / nozzle normal-momentum proxy")
ax.grid(True, alpha=0.25)
fig.tight_layout()
fig.savefig(out / "incident_to_nozzle_momentum_ratio_vs_Fr.pdf", bbox_inches="tight")
fig.savefig(out / "incident_to_nozzle_momentum_ratio_vs_Fr.png", dpi=180, bbox_inches="tight")
plt.close(fig)

# Figure 3: incident velocity histories
fig, ax = plt.subplots(figsize=(8.6, 5.2))
for fr in sorted(groups):
    rr = sorted(groups[fr], key=lambda r: r["time"])
    ax.plot(
        [r["time"] for r in rr],
        [r["incidentSpeedRatioToNominal"] for r in rr],
        label=f"Fr'={fr:g}",
    )
ax.axvline(args.initial_cutoff, linestyle="--", alpha=0.6, label="analysis start")
ax.set_xlabel("Forced physical time")
ax.set_ylabel("Incident downward gas speed / nominal jet speed")
ax.grid(True, alpha=0.25)
ax.legend()
fig.tight_layout()
fig.savefig(out / "incident_downward_velocity_time_series.pdf", bbox_inches="tight")
fig.savefig(out / "incident_downward_velocity_time_series.png", dpi=180, bbox_inches="tight")
plt.close(fig)

print(f"[0493x24af] wrote {out/'gas_loading_summary.csv'}")
print(f"[0493x24af] wrote PDF article/diagnostic figures under {out}")
