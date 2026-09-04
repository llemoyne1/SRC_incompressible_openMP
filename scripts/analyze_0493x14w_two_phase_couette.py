#!/usr/bin/env python3
"""Offline profile analysis for 0493x14w two-phase Couette.

Geometry:
    gas | liquid | gas
with x periodic and y walls moving at -Uw / +Uw.

The analysis reads only existing state dumps.  No runtime diagnostic is added.
It exploits the exact mirror geometry by decomposing each profile into

    u_odd(z)  = [u_top(z)-u_bottom(z)]/2
    u_even(z) = [u_top(z)+u_bottom(z)]/2.

The odd part carries the Couette shear and is exactly insensitive to a spatially
uniform common x drift.  The even part is retained explicitly to diagnose that
common mode instead of hiding it.

0493x14w-analysis-v2 additionally:
  * reconstructs the production x6c alpha field offline from each dump
    (liquid fixed-grid cell mass / inferred reference cell mass, clamp [0,1],
    conservative five-point filter lambda=0.125);
  * locates the actual alpha=0.5 bottom/top crossings and evaluates interfacial
    slip at the measured interface rather than at the initial slab boundary;
  * moves the bulk fit windows with the measured interface;
  * constructs a late-time averaged profile across all available dumps, so the
    quantitative result is not controlled by one noisy gas snapshot;
  * measures the even/common spatial gradient and the k=0 barycentric drift;
  * if species_runtime_0493x14w.csv is present, uses its finer time cadence for
    an independent drift regression.

Primary observables:
  * dynamic alpha=0.5 interfacial slip uG^Gamma-uL^Gamma;
  * legacy/fixed-boundary slip for comparison only;
  * linearity (R^2) of each phase away from interface/walls;
  * slope ratio aL/aG = muG/muL if tangential stress is continuous;
  * gas-wall slip from the fitted gas profile;
  * common-mode spatial gradients relative to Couette gradients;
  * temporal acceleration and R^2 of the common k=0 x drift;
  * late-time averaged metrics and temporal spread.

Standard library only: no numpy/pandas/scipy.
"""
from __future__ import annotations

import argparse
import csv
import json
import math
import re
import struct
import sys
from array import array
from pathlib import Path

MAGIC_PREFIX = b"SRCMPCD_STATE"
X6C_FILTER_LAMBDA = 0.125


def read_array(f, typecode, n, itemsize):
    a = array(typecode)
    a.fromfile(f, n)
    if len(a) != n:
        raise RuntimeError("truncated state")
    if sys.byteorder == "big" and itemsize > 1:
        a.byteswap()
    return a


def read_state(path: Path):
    with path.open("rb") as f:
        magic = f.read(16)
        if not magic.startswith(MAGIC_PREFIX):
            raise RuntimeError(f"bad state magic: {path}")
        fmt = "<IIIIQIIII"
        version, endian, dim, layout, n, has_type, has_mass, real_size, type_size = \
            struct.unpack(fmt, f.read(struct.calcsize(fmt)))
        reserved = struct.unpack("<8Q", f.read(64))
        if endian != 0x01020304 or dim != 2 or layout != 1:
            raise RuntimeError(f"unsupported state header: {path}")
        if not has_type or not has_mass or real_size != 8 or type_size != 4:
            raise RuntimeError(f"unsupported particle layout: {path}")
        n = int(n)
        x = read_array(f, "d", n, 8)
        y = read_array(f, "d", n, 8)
        vx = read_array(f, "d", n, 8)
        vy = read_array(f, "d", n, 8)
        typ = read_array(f, "I", n, 4)
        mass = read_array(f, "d", n, 8)
        if version >= 2:
            role_size = int(reserved[1]) if reserved[1] else 1
            if role_size != 1:
                raise RuntimeError(f"unsupported role size={role_size}")
            role = read_array(f, "B", n, 1)
        else:
            role = array("B", [1]) * n
    return x, y, vx, vy, typ, mass, role


def parse_step(path: Path):
    m = re.search(r"state_step_(\d+)\.smpcd$", path.name)
    return int(m.group(1)) if m else 0


def clamp01(v):
    if v < 0.0:
        return 0.0
    if v > 1.0:
        return 1.0
    return v


def mean(vals):
    return sum(vals) / len(vals) if vals else math.nan


def std(vals, center=None):
    if not vals:
        return math.nan
    m = mean(vals) if center is None else center
    return math.sqrt(max(0.0, sum((v - m) ** 2 for v in vals) / len(vals)))


def rms(vals):
    return math.sqrt(sum(v * v for v in vals) / len(vals)) if vals else math.nan


def ols(points):
    if len(points) < 3:
        return math.nan, math.nan, math.nan, math.nan
    xs = [p[0] for p in points]
    ys = [p[1] for p in points]
    mx = sum(xs) / len(xs)
    my = sum(ys) / len(ys)
    sxx = sum((x - mx) ** 2 for x in xs)
    if not (sxx > 0):
        return math.nan, math.nan, math.nan, math.nan
    a = sum((x - mx) * (y - my) for x, y in points) / sxx
    b = my - a * mx
    sse = sum((y - (a * x + b)) ** 2 for x, y in points)
    sst = sum((y - my) ** 2 for y in ys)
    r2 = 1.0 - sse / sst if sst > 0 else (1.0 if sse < 1e-30 else math.nan)
    fit_rms = math.sqrt(sse / len(points))
    return a, b, r2, fit_rms


def linear_time_fit(rows, key, min_step=1):
    pts = []
    for r in rows:
        if r.get("step", 0) < min_step:
            continue
        t = r.get("time", math.nan)
        v = r.get(key, math.nan)
        if math.isfinite(t) and math.isfinite(v):
            pts.append((t, v))
    a, b, r2, fit_rms = ols(pts)
    return {
        "samples": len(pts),
        "acceleration": a,
        "intercept": b,
        "r2": r2,
        "fitRms": fit_rms,
    }


def rel_change(a, b):
    if not (math.isfinite(a) and math.isfinite(b)):
        return math.nan
    den = max(abs(a), abs(b), 1e-30)
    return abs(a - b) / den


def fixed_cell_index(x, y, nx, ny, lx, ly):
    # x is periodic in x14w; y is a bounded physical wall direction.
    x %= lx
    if y < 0.0:
        y = 0.0
    elif y >= ly:
        y = math.nextafter(ly, 0.0)
    ix = int(math.floor(x * nx / lx))
    iy = int(math.floor(y * ny / ly))
    ix %= nx
    iy = max(0, min(ny - 1, iy))
    return iy * nx + ix


def x6c_filter(raw_fill, nx, ny):
    """Production x6c five-point filter for periodic x / non-periodic y."""
    alpha = array("d", [0.0]) * (nx * ny)
    lam = X6C_FILTER_LAMBDA
    for iy in range(ny):
        row = iy * nx
        for ix in range(nx):
            c = row + ix
            center = clamp01(raw_fill[c])
            lap = 0.0
            west = row + ((ix - 1) % nx)
            east = row + ((ix + 1) % nx)
            lap += clamp01(raw_fill[west]) - center
            lap += clamp01(raw_fill[east]) - center
            if iy > 0:
                lap += clamp01(raw_fill[(iy - 1) * nx + ix]) - center
            if iy < ny - 1:
                lap += clamp01(raw_fill[(iy + 1) * nx + ix]) - center
            alpha[c] = center + lam * lap
    return alpha


def infer_liquid_reference_mass(initial_state, liquid_type, nx, slab_start, slab_end):
    x, y, vx, vy, typ, mass, role = initial_state
    total = 0.0
    count = 0
    for i in range(len(typ)):
        if role[i] == 1 and int(typ[i]) == liquid_type:
            total += mass[i]
            count += 1
    nominal_cells = nx * (slab_end - slab_start)
    if nominal_cells <= 0 or not (total > 0.0):
        raise RuntimeError("cannot infer liquid reference cell mass from initial state")
    ref = total / nominal_cells
    return ref, total, count


def reconstruct_x6c_interface(x, y, typ, mass, role, liquid_type,
                              liquid_ref_mass, nx, ny, lx, ly, yc,
                              initial_z_interface):
    raw_mass = array("d", [0.0]) * (nx * ny)
    liquid_mass = 0.0
    for i in range(len(y)):
        if role[i] != 1 or int(typ[i]) != liquid_type:
            continue
        c = fixed_cell_index(x[i], y[i], nx, ny, lx, ly)
        raw_mass[c] += mass[i]
        liquid_mass += mass[i]

    raw_fill = array("d", (m / liquid_ref_mass for m in raw_mass))
    alpha = x6c_filter(raw_fill, nx, ny)
    h = ly / ny

    bottom = []
    top = []
    extra_crossings = 0
    columns_with_any = 0
    columns_with_pair = 0

    # For each x column, locate all alpha=.5 y-face crossings.  In the intended
    # G|L|G topology the bottom crossing is low->high and the top crossing is
    # high->low.  If stochastic geometry creates more candidates, choose the
    # candidates closest to the expected central liquid slab and report extras.
    for ix in range(nx):
        lows = []
        highs = []
        allc = []
        for iy in range(ny - 1):
            c0 = iy * nx + ix
            c1 = (iy + 1) * nx + ix
            a0 = alpha[c0]
            a1 = alpha[c1]
            low_to_high = a0 < 0.5 <= a1
            high_to_low = a0 >= 0.5 > a1
            if not (low_to_high or high_to_low):
                continue
            den = a1 - a0
            theta = (0.5 - a0) / den if abs(den) > 1e-14 else 0.5
            theta = min(1.0, max(0.0, theta))
            yy = (iy + 0.5 + theta) * h
            allc.append(yy)
            if low_to_high and yy < yc:
                lows.append(yy)
            elif high_to_low and yy > yc:
                highs.append(yy)
        if allc:
            columns_with_any += 1
        # Expected positions are yc +/- initial_z_interface.  Nearest-candidate
        # selection is robust against rare secondary alpha pockets.
        yb0 = yc - initial_z_interface
        yt0 = yc + initial_z_interface
        yb = min(lows, key=lambda q: abs(q - yb0)) if lows else None
        yt = min(highs, key=lambda q: abs(q - yt0)) if highs else None
        if yb is not None:
            bottom.append(yb)
        if yt is not None:
            top.append(yt)
        if yb is not None and yt is not None:
            columns_with_pair += 1
        extra_crossings += max(0, len(allc) - (1 if yb is not None else 0) - (1 if yt is not None else 0))

    bottom_mean = mean(bottom)
    top_mean = mean(top)
    bottom_std = std(bottom, bottom_mean) if bottom else math.nan
    top_std = std(top, top_mean) if top else math.nan

    if math.isfinite(bottom_mean) and math.isfinite(top_mean):
        center_y = 0.5 * (bottom_mean + top_mean)
        z_half = 0.5 * (top_mean - bottom_mean)
    else:
        center_y = yc
        z_half = initial_z_interface

    paired_half = []
    paired_center = []
    if len(bottom) == nx and len(top) == nx:
        for yb, yt in zip(bottom, top):
            paired_half.append(0.5 * (yt - yb))
            paired_center.append(0.5 * (yt + yb))

    return {
        "alpha": alpha,
        "liquidMass": liquid_mass,
        "alphaHalfCells": sum(1 for a in alpha if a >= 0.5),
        "bottomMeanY": bottom_mean,
        "bottomStdY": bottom_std,
        "topMeanY": top_mean,
        "topStdY": top_std,
        "centerY": center_y,
        "centerShift": center_y - yc,
        "zInterface": z_half,
        "zInterfaceStd": std(paired_half) if paired_half else 0.5 * math.sqrt(
            (bottom_std if math.isfinite(bottom_std) else 0.0) ** 2 +
            (top_std if math.isfinite(top_std) else 0.0) ** 2
        ),
        "centerStd": std(paired_center) if paired_center else 0.5 * math.sqrt(
            (bottom_std if math.isfinite(bottom_std) else 0.0) ** 2 +
            (top_std if math.isfinite(top_std) else 0.0) ** 2
        ),
        "crossingBottomColumns": len(bottom),
        "crossingTopColumns": len(top),
        "crossingPairColumns": columns_with_pair,
        "crossingAnyColumns": columns_with_any,
        "extraCrossings": extra_crossings,
    }


def fit_phase_profiles(paired, liquid_type, gas_type, z_interface, z_wall,
                       h, interface_exclude_cells, wall_exclude_cells):
    z_liq_max = z_interface - interface_exclude_cells * h
    z_gas_min = z_interface + interface_exclude_cells * h
    z_gas_max = z_wall - wall_exclude_cells * h
    if not (z_liq_max > 2 * h and z_gas_max > z_gas_min + 2 * h):
        return None

    lp = [(z, ua) for z, ua, uc, va, vc in paired[liquid_type]
          if 0.0 < z <= z_liq_max]
    gp = [(z, ua) for z, ua, uc, va, vc in paired[gas_type]
          if z_gas_min <= z <= z_gas_max]
    lc = [(z, uc) for z, ua, uc, va, vc in paired[liquid_type]
          if 0.0 < z <= z_liq_max]
    gc = [(z, uc) for z, ua, uc, va, vc in paired[gas_type]
          if z_gas_min <= z <= z_gas_max]

    aL, bL, r2L, rmsL = ols(lp)
    aG, bG, r2G, rmsG = ols(gp)
    cLs, cLi, cLr2, cLrms = ols(lc)
    cGs, cGi, cGr2, cGrms = ols(gc)

    return {
        "liquidSlope": aL,
        "liquidIntercept": bL,
        "liquidR2": r2L,
        "liquidFitRms": rmsL,
        "gasSlope": aG,
        "gasIntercept": bG,
        "gasR2": r2G,
        "gasFitRms": rmsG,
        "liquidCommonSlope": cLs,
        "liquidCommonIntercept": cLi,
        "liquidCommonR2": cLr2,
        "liquidCommonFitRms": cLrms,
        "gasCommonSlope": cGs,
        "gasCommonIntercept": cGi,
        "gasCommonR2": cGr2,
        "gasCommonFitRms": cGrms,
        "liquidCommonMean": mean([v for z, v in lc]),
        "gasCommonMean": mean([v for z, v in gc]),
        "liquidCommonSpatialStd": std([v for z, v in lc]),
        "gasCommonSpatialStd": std([v for z, v in gc]),
        "liquidFitPoints": len(lp),
        "gasFitPoints": len(gp),
        "zLiquidFitMax": z_liq_max,
        "zGasFitMin": z_gas_min,
        "zGasFitMax": z_gas_max,
    }


def add_slip_metrics(fit, z_interface_dynamic, z_interface_fixed, z_wall, wall_speed):
    aL = fit["liquidSlope"]
    bL = fit["liquidIntercept"]
    aG = fit["gasSlope"]
    bG = fit["gasIntercept"]

    def at(a, b, z):
        return a * z + b if math.isfinite(a) and math.isfinite(b) else math.nan

    uLd = at(aL, bL, z_interface_dynamic)
    uGd = at(aG, bG, z_interface_dynamic)
    slip_d = uGd - uLd if math.isfinite(uLd) and math.isfinite(uGd) else math.nan
    uLf = at(aL, bL, z_interface_fixed)
    uGf = at(aG, bG, z_interface_fixed)
    slip_f = uGf - uLf if math.isfinite(uLf) and math.isfinite(uGf) else math.nan
    uwall = at(aG, bG, z_wall)
    wall_slip = wall_speed - uwall if math.isfinite(uwall) else math.nan
    ratio = aL / aG if math.isfinite(aL) and math.isfinite(aG) and abs(aG) > 1e-30 else math.nan
    cLrel = abs(fit["liquidCommonSlope"]) / max(abs(aL), 1e-30) \
        if math.isfinite(fit["liquidCommonSlope"]) and math.isfinite(aL) else math.nan
    cGrel = abs(fit["gasCommonSlope"]) / max(abs(aG), 1e-30) \
        if math.isfinite(fit["gasCommonSlope"]) and math.isfinite(aG) else math.nan

    fit.update({
        # Primary/current definition = measured dynamic alpha=.5 interface.
        "uGammaLiquid": uLd,
        "uGammaGas": uGd,
        "interfaceSlip": slip_d,
        "interfaceSlipOverUw": slip_d / wall_speed if wall_speed else math.nan,
        # Legacy comparison = initial slab boundary.
        "uGammaLiquidFixed": uLf,
        "uGammaGasFixed": uGf,
        "interfaceSlipFixed": slip_f,
        "interfaceSlipFixedOverUw": slip_f / wall_speed if wall_speed else math.nan,
        "muGasOverMuLiquidFromSlopes": ratio,
        "gasWallExtrapolated": uwall,
        "gasWallSlip": wall_slip,
        "gasWallSlipOverUw": wall_slip / wall_speed if wall_speed else math.nan,
        "liquidCommonSlopeOverCouetteSlope": cLrel,
        "gasCommonSlopeOverCouetteSlope": cGrel,
    })
    return fit


def read_species_runtime(path, liquid_type, gas_type):
    if not path.is_file():
        return []
    grouped = {}
    with path.open(newline="") as f:
        for r in csv.DictReader(f):
            try:
                step = int(float(r["step"]))
                t = int(float(r["type"]))
                tm = float(r["time"])
                mm = float(r["totalMass"])
                ux = float(r["meanVx"])
            except Exception:
                continue
            if t not in (liquid_type, gas_type):
                continue
            q = grouped.setdefault(step, {"step": step, "time": tm})
            prefix = "liquid" if t == liquid_type else "gas"
            q[prefix + "Mass"] = mm
            q[prefix + "MeanUx"] = ux
    rows = []
    for step in sorted(grouped):
        q = grouped[step]
        ml = q.get("liquidMass", math.nan)
        mg = q.get("gasMass", math.nan)
        ul = q.get("liquidMeanUx", math.nan)
        ug = q.get("gasMeanUx", math.nan)
        if all(math.isfinite(v) for v in (ml, mg, ul, ug)) and ml + mg > 0:
            q["totalMeanUx"] = (ml * ul + mg * ug) / (ml + mg)
        else:
            q["totalMeanUx"] = math.nan
        rows.append(q)
    return rows


def average_profiles(profile_samples, selected_steps):
    out = {}
    for step in selected_steps:
        for species, vals in profile_samples.get(step, {}).items():
            for z, ua, uc, va, vc in vals:
                key = (species, z)
                q = out.setdefault(key, {"ua": [], "uc": [], "va": [], "vc": []})
                if math.isfinite(ua):
                    q["ua"].append(ua)
                if math.isfinite(uc):
                    q["uc"].append(uc)
                if math.isfinite(va):
                    q["va"].append(va)
                if math.isfinite(vc):
                    q["vc"].append(vc)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--initial", type=Path, required=True)
    ap.add_argument("--output-dir", type=Path, required=True)
    ap.add_argument("--analysis-dir", type=Path, required=True)
    ap.add_argument("--Lx", type=float, required=True)
    ap.add_argument("--Ly", type=float, required=True)
    ap.add_argument("--nx", type=int, required=True)
    ap.add_argument("--ny", type=int, required=True)
    ap.add_argument("--dt", type=float, required=True)
    ap.add_argument("--slab-start-cell", type=int, required=True)
    ap.add_argument("--slab-end-cell", type=int, required=True)
    ap.add_argument("--liquid-type", type=int, default=1)
    ap.add_argument("--gas-type", type=int, default=2)
    ap.add_argument("--wall-speed", type=float, required=True)
    ap.add_argument("--interface-exclude-cells", type=int, default=4)
    ap.add_argument("--wall-exclude-cells", type=int, default=4)
    ap.add_argument(
        "--late-start-fraction", type=float, default=1.0 / 3.0,
        help="late averaging starts at this fraction of the final dump step (default 1/3)",
    )
    args = ap.parse_args()

    hx = args.Lx / args.nx
    hy = args.Ly / args.ny
    if abs(hx - hy) > 1e-12 * max(1.0, abs(hx), abs(hy)):
        raise SystemExit("[0493x14w-analysis] square cells required")
    h = hy
    if args.ny % 2:
        raise SystemExit("[0493x14w-analysis] even ny required for mirror pairing")
    if args.slab_start_cell != args.ny - args.slab_end_cell:
        raise SystemExit("[0493x14w-analysis] liquid slab must be centered")
    if not (0 < args.slab_start_cell < args.slab_end_cell < args.ny):
        raise SystemExit("[0493x14w-analysis] invalid slab bounds")
    if not (0.0 <= args.late_start_fraction < 1.0):
        raise SystemExit("[0493x14w-analysis] late-start-fraction must be in [0,1)")

    yc = 0.5 * args.Ly
    z_interface_fixed = 0.5 * (args.slab_end_cell - args.slab_start_cell) * h
    z_wall = 0.5 * args.Ly

    initial_state = read_state(args.initial)
    liquid_ref_mass, initial_liquid_mass, initial_liquid_count = infer_liquid_reference_mass(
        initial_state, args.liquid_type, args.nx,
        args.slab_start_cell, args.slab_end_cell,
    )

    states = {0: args.initial}
    for p in args.output_dir.glob("state_step_*.smpcd"):
        states[parse_step(p)] = p
    states = sorted(states.items())
    if not states:
        raise SystemExit("[0493x14w-analysis] no states found")

    args.analysis_dir.mkdir(parents=True, exist_ok=True)
    raw_csv = args.analysis_dir / "couette_profiles_0493x14w.csv"
    asym_csv = args.analysis_dir / "couette_antisymmetric_profiles_0493x14w.csv"
    metrics_csv = args.analysis_dir / "couette_metrics_0493x14w.csv"
    interface_csv = args.analysis_dir / "couette_interface_0493x14w.csv"
    late_profiles_csv = args.analysis_dir / "couette_late_averaged_profiles_0493x14w.csv"
    late_metrics_csv = args.analysis_dir / "couette_late_metrics_0493x14w.csv"
    summary_json = args.analysis_dir / "couette_summary_0493x14w.json"

    raw_fields = ["step", "time", "j", "y", "z", "species", "count", "mass", "meanUx", "meanUy"]
    asym_fields = ["step", "time", "pair", "z", "species", "uAntisym", "uCommon", "vyAntisym", "vyCommon"]
    interface_fields = [
        "step", "time", "liquidReferenceCellMass", "alphaHalfCells",
        "bottomMeanY", "bottomStdY", "topMeanY", "topStdY",
        "interfaceCenterY", "interfaceCenterShift", "interfaceCenterShiftOverH",
        "zInterfaceDynamic", "zInterfaceDynamicOverH", "zInterfaceChangeOverH",
        "zInterfaceStd", "crossingBottomColumns", "crossingTopColumns",
        "crossingPairColumns", "crossingCoverage", "extraCrossings",
    ]
    metric_fields = [
        "step", "time",
        "zInterfaceDynamic", "zInterfaceDynamicOverH", "interfaceCenterShiftOverH",
        "liquidSlope", "liquidIntercept", "liquidR2", "liquidFitRms",
        "gasSlope", "gasIntercept", "gasR2", "gasFitRms",
        "uGammaLiquid", "uGammaGas", "interfaceSlip", "interfaceSlipOverUw",
        "uGammaLiquidFixed", "uGammaGasFixed", "interfaceSlipFixed", "interfaceSlipFixedOverUw",
        "muGasOverMuLiquidFromSlopes",
        "gasWallExtrapolated", "gasWallSlip", "gasWallSlipOverUw",
        "liquidCommonMean", "gasCommonMean", "liquidCommonSlope", "gasCommonSlope",
        "liquidCommonSlopeOverCouetteSlope", "gasCommonSlopeOverCouetteSlope",
        "liquidCommonSpatialStd", "gasCommonSpatialStd",
        "liquidGlobalMeanUx", "gasGlobalMeanUx", "totalGlobalMeanUx",
        "liquidCommonRms", "gasCommonRms", "normalVelocityRms",
        "crossingCoverage", "extraCrossings",
    ]

    metric_rows = []
    interface_rows = []
    profile_samples = {}

    with raw_csv.open("w", newline="") as fr, asym_csv.open("w", newline="") as fa, \
            interface_csv.open("w", newline="") as fi:
        rw = csv.DictWriter(fr, fieldnames=raw_fields)
        rw.writeheader()
        aw = csv.DictWriter(fa, fieldnames=asym_fields)
        aw.writeheader()
        iw = csv.DictWriter(fi, fieldnames=interface_fields)
        iw.writeheader()

        for step, path in states:
            state = initial_state if step == 0 and path == args.initial else read_state(path)
            x, y, vx, vy, typ, mass, role = state

            geom = reconstruct_x6c_interface(
                x, y, typ, mass, role, args.liquid_type, liquid_ref_mass,
                args.nx, args.ny, args.Lx, args.Ly, yc, z_interface_fixed,
            )
            z_interface = geom["zInterface"]
            crossing_coverage = geom["crossingPairColumns"] / args.nx
            irow = {
                "step": step,
                "time": step * args.dt,
                "liquidReferenceCellMass": liquid_ref_mass,
                "alphaHalfCells": geom["alphaHalfCells"],
                "bottomMeanY": geom["bottomMeanY"],
                "bottomStdY": geom["bottomStdY"],
                "topMeanY": geom["topMeanY"],
                "topStdY": geom["topStdY"],
                "interfaceCenterY": geom["centerY"],
                "interfaceCenterShift": geom["centerShift"],
                "interfaceCenterShiftOverH": geom["centerShift"] / h,
                "zInterfaceDynamic": z_interface,
                "zInterfaceDynamicOverH": z_interface / h,
                "zInterfaceChangeOverH": (z_interface - z_interface_fixed) / h,
                "zInterfaceStd": geom["zInterfaceStd"],
                "crossingBottomColumns": geom["crossingBottomColumns"],
                "crossingTopColumns": geom["crossingTopColumns"],
                "crossingPairColumns": geom["crossingPairColumns"],
                "crossingCoverage": crossing_coverage,
                "extraCrossings": geom["extraCrossings"],
            }
            interface_rows.append(irow)
            iw.writerow(irow)

            # per species / y cell: [count,mass,px,py]
            bins = {
                args.liquid_type: [[0, 0.0, 0.0, 0.0] for _ in range(args.ny)],
                args.gas_type: [[0, 0.0, 0.0, 0.0] for _ in range(args.ny)],
            }
            global_m = {args.liquid_type: 0.0, args.gas_type: 0.0}
            global_px = {args.liquid_type: 0.0, args.gas_type: 0.0}
            for i in range(len(y)):
                if role[i] != 1:
                    continue
                t = int(typ[i])
                if t not in bins:
                    continue
                j = int(math.floor(y[i] / h))
                if j < 0:
                    j = 0
                elif j >= args.ny:
                    j = args.ny - 1
                q = bins[t][j]
                q[0] += 1
                q[1] += mass[i]
                q[2] += mass[i] * vx[i]
                q[3] += mass[i] * vy[i]
                global_m[t] += mass[i]
                global_px[t] += mass[i] * vx[i]

            means = {}
            for t, name in ((args.liquid_type, "liquid"), (args.gas_type, "gas")):
                arr = []
                for j, q in enumerate(bins[t]):
                    cnt, mm, px, py = q
                    ux = px / mm if mm > 0 else math.nan
                    uy = py / mm if mm > 0 else math.nan
                    yy = (j + 0.5) * h
                    arr.append((ux, uy, cnt, mm))
                    rw.writerow({
                        "step": step, "time": step * args.dt, "j": j, "y": yy, "z": yy - yc,
                        "species": name, "count": cnt, "mass": mm, "meanUx": ux, "meanUy": uy,
                    })
                means[t] = arr

            paired = {}
            for t, name in ((args.liquid_type, "liquid"), (args.gas_type, "gas")):
                vals = []
                for jb in range(args.ny // 2):
                    jt = args.ny - 1 - jb
                    ub, vb, cb, mb = means[t][jb]
                    ut, vt, ct, mt = means[t][jt]
                    if not (math.isfinite(ub) and math.isfinite(ut)):
                        continue
                    z = (jt + 0.5) * h - yc
                    ua = 0.5 * (ut - ub)
                    uc = 0.5 * (ut + ub)
                    va = 0.5 * (vt - vb) if math.isfinite(vb) and math.isfinite(vt) else math.nan
                    vc = 0.5 * (vt + vb) if math.isfinite(vb) and math.isfinite(vt) else math.nan
                    vals.append((z, ua, uc, va, vc))
                    aw.writerow({
                        "step": step, "time": step * args.dt, "pair": jb, "z": z,
                        "species": name, "uAntisym": ua, "uCommon": uc,
                        "vyAntisym": va, "vyCommon": vc,
                    })
                paired[t] = vals
            profile_samples[step] = paired

            fit = fit_phase_profiles(
                paired, args.liquid_type, args.gas_type, z_interface, z_wall, h,
                args.interface_exclude_cells, args.wall_exclude_cells,
            )
            if fit is None:
                raise RuntimeError(
                    f"step {step}: dynamic interface leaves insufficient bulk fit window; "
                    f"zGamma/h={z_interface / h:.6g}"
                )
            add_slip_metrics(fit, z_interface, z_interface_fixed, z_wall, args.wall_speed)

            lcommon = [uc for z, ua, uc, va, vc in paired[args.liquid_type]
                       if 0.0 < z <= fit["zLiquidFitMax"]]
            gcommon = [uc for z, ua, uc, va, vc in paired[args.gas_type]
                       if fit["zGasFitMin"] <= z <= fit["zGasFitMax"]]
            allvy = []
            for t in (args.liquid_type, args.gas_type):
                for z, ua, uc, va, vc in paired[t]:
                    if math.isfinite(va):
                        allvy.append(va)
                    if math.isfinite(vc):
                        allvy.append(vc)

            ul = global_px[args.liquid_type] / global_m[args.liquid_type] \
                if global_m[args.liquid_type] > 0 else math.nan
            ug = global_px[args.gas_type] / global_m[args.gas_type] \
                if global_m[args.gas_type] > 0 else math.nan
            mt = global_m[args.liquid_type] + global_m[args.gas_type]
            ut = (global_px[args.liquid_type] + global_px[args.gas_type]) / mt if mt > 0 else math.nan

            row = {
                "step": step,
                "time": step * args.dt,
                "zInterfaceDynamic": z_interface,
                "zInterfaceDynamicOverH": z_interface / h,
                "interfaceCenterShiftOverH": geom["centerShift"] / h,
                "liquidSlope": fit["liquidSlope"],
                "liquidIntercept": fit["liquidIntercept"],
                "liquidR2": fit["liquidR2"],
                "liquidFitRms": fit["liquidFitRms"],
                "gasSlope": fit["gasSlope"],
                "gasIntercept": fit["gasIntercept"],
                "gasR2": fit["gasR2"],
                "gasFitRms": fit["gasFitRms"],
                "uGammaLiquid": fit["uGammaLiquid"],
                "uGammaGas": fit["uGammaGas"],
                "interfaceSlip": fit["interfaceSlip"],
                "interfaceSlipOverUw": fit["interfaceSlipOverUw"],
                "uGammaLiquidFixed": fit["uGammaLiquidFixed"],
                "uGammaGasFixed": fit["uGammaGasFixed"],
                "interfaceSlipFixed": fit["interfaceSlipFixed"],
                "interfaceSlipFixedOverUw": fit["interfaceSlipFixedOverUw"],
                "muGasOverMuLiquidFromSlopes": fit["muGasOverMuLiquidFromSlopes"],
                "gasWallExtrapolated": fit["gasWallExtrapolated"],
                "gasWallSlip": fit["gasWallSlip"],
                "gasWallSlipOverUw": fit["gasWallSlipOverUw"],
                "liquidCommonMean": fit["liquidCommonMean"],
                "gasCommonMean": fit["gasCommonMean"],
                "liquidCommonSlope": fit["liquidCommonSlope"],
                "gasCommonSlope": fit["gasCommonSlope"],
                "liquidCommonSlopeOverCouetteSlope": fit["liquidCommonSlopeOverCouetteSlope"],
                "gasCommonSlopeOverCouetteSlope": fit["gasCommonSlopeOverCouetteSlope"],
                "liquidCommonSpatialStd": fit["liquidCommonSpatialStd"],
                "gasCommonSpatialStd": fit["gasCommonSpatialStd"],
                "liquidGlobalMeanUx": ul,
                "gasGlobalMeanUx": ug,
                "totalGlobalMeanUx": ut,
                "liquidCommonRms": rms(lcommon),
                "gasCommonRms": rms(gcommon),
                "normalVelocityRms": rms(allvy),
                "crossingCoverage": crossing_coverage,
                "extraCrossings": geom["extraCrossings"],
            }
            metric_rows.append(row)

            print(
                "[0493x14w-analysis] "
                f"step={step:6d} t={step * args.dt:.6g} "
                f"zG/h={z_interface / h:.4f} dzG/h={(z_interface-z_interface_fixed)/h:+.3f} "
                f"aL={fit['liquidSlope']:+.6g} R2L={fit['liquidR2']:.5f} "
                f"aG={fit['gasSlope']:+.6g} R2G={fit['gasR2']:.5f} "
                f"slipDyn/Uw={fit['interfaceSlipOverUw']:+.4%} "
                f"slipFixed/Uw={fit['interfaceSlipFixedOverUw']:+.4%} "
                f"muG/muL|slope={fit['muGasOverMuLiquidFromSlopes']:.6g} "
                f"u0={ut:+.6g} commonGrad/Couette="
                f"{max(fit['liquidCommonSlopeOverCouetteSlope'], fit['gasCommonSlopeOverCouetteSlope']):.3g}"
            )

    with metrics_csv.open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=metric_fields)
        w.writeheader()
        w.writerows(metric_rows)

    final = metric_rows[-1]
    final_step = final["step"]
    late_start_step = args.late_start_fraction * final_step
    selected_steps = [r["step"] for r in metric_rows
                      if r["step"] > 0 and r["step"] >= late_start_step]
    if len(selected_steps) < 2:
        selected_steps = [r["step"] for r in metric_rows if r["step"] > 0][-min(3, max(0, len(metric_rows)-1)):]
    if not selected_steps:
        selected_steps = [final_step]

    late_profile_data = average_profiles(profile_samples, selected_steps)
    late_interface_rows = [r for r in interface_rows if r["step"] in selected_steps]
    z_interface_late = mean([r["zInterfaceDynamic"] for r in late_interface_rows])
    center_shift_late = mean([r["interfaceCenterShift"] for r in late_interface_rows])
    coverage_late = mean([r["crossingCoverage"] for r in late_interface_rows])
    z_interface_late_std_time = std([r["zInterfaceDynamic"] for r in late_interface_rows])

    late_paired = {args.liquid_type: [], args.gas_type: []}
    species_name_to_type = {"liquid": args.liquid_type, "gas": args.gas_type}
    with late_profiles_csv.open("w", newline="") as f:
        fields = [
            "species", "z", "samples", "uAntisymMean", "uAntisymStd",
            "uCommonMean", "uCommonStd", "vyAntisymMean", "vyCommonMean",
        ]
        w = csv.DictWriter(f, fieldnames=fields)
        w.writeheader()
        for species_name in ("liquid", "gas"):
            t = species_name_to_type[species_name]
            keys = sorted((k for k in late_profile_data if k[0] == t), key=lambda q: q[1])
            for key in keys:
                q = late_profile_data[key]
                ua = mean(q["ua"])
                uc = mean(q["uc"])
                va = mean(q["va"])
                vc = mean(q["vc"])
                z = key[1]
                late_paired[t].append((z, ua, uc, va, vc))
                w.writerow({
                    "species": species_name,
                    "z": z,
                    "samples": len(q["ua"]),
                    "uAntisymMean": ua,
                    "uAntisymStd": std(q["ua"]),
                    "uCommonMean": uc,
                    "uCommonStd": std(q["uc"]),
                    "vyAntisymMean": va,
                    "vyCommonMean": vc,
                })

    late_fit = fit_phase_profiles(
        late_paired, args.liquid_type, args.gas_type, z_interface_late, z_wall, h,
        args.interface_exclude_cells, args.wall_exclude_cells,
    )
    if late_fit is None:
        raise RuntimeError("late averaged profile has insufficient fit window")
    add_slip_metrics(late_fit, z_interface_late, z_interface_fixed, z_wall, args.wall_speed)

    late_metric_rows = [r for r in metric_rows if r["step"] in selected_steps]
    late_fit.update({
        "lateStartStep": min(selected_steps),
        "lateEndStep": max(selected_steps),
        "lateSamples": len(selected_steps),
        "zInterfaceDynamic": z_interface_late,
        "zInterfaceDynamicOverH": z_interface_late / h,
        "zInterfaceTemporalStdOverH": z_interface_late_std_time / h,
        "interfaceCenterShiftOverH": center_shift_late / h,
        "crossingCoverage": coverage_late,
        "liquidSlopeTemporalMean": mean([r["liquidSlope"] for r in late_metric_rows]),
        "liquidSlopeTemporalStd": std([r["liquidSlope"] for r in late_metric_rows]),
        "gasSlopeTemporalMean": mean([r["gasSlope"] for r in late_metric_rows]),
        "gasSlopeTemporalStd": std([r["gasSlope"] for r in late_metric_rows]),
        "interfaceSlipOverUwTemporalMean": mean([r["interfaceSlipOverUw"] for r in late_metric_rows]),
        "interfaceSlipOverUwTemporalStd": std([r["interfaceSlipOverUw"] for r in late_metric_rows]),
        "interfaceSlipFixedOverUwTemporalMean": mean([r["interfaceSlipFixedOverUw"] for r in late_metric_rows]),
        "interfaceSlipFixedOverUwTemporalStd": std([r["interfaceSlipFixedOverUw"] for r in late_metric_rows]),
        "gasWallSlipOverUwTemporalMean": mean([r["gasWallSlipOverUw"] for r in late_metric_rows]),
        "gasWallSlipOverUwTemporalStd": std([r["gasWallSlipOverUw"] for r in late_metric_rows]),
        "totalGlobalMeanUxLateMean": mean([r["totalGlobalMeanUx"] for r in late_metric_rows]),
    })

    late_fields = list(late_fit.keys())
    with late_metrics_csv.open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=late_fields)
        w.writeheader()
        w.writerow(late_fit)

    prev = metric_rows[-2] if len(metric_rows) >= 2 else None
    conv = {}
    if prev:
        conv = {
            "liquidSlopeRelativeChange": rel_change(final["liquidSlope"], prev["liquidSlope"]),
            "gasSlopeRelativeChange": rel_change(final["gasSlope"], prev["gasSlope"]),
            "interfaceSlipAbsoluteChangeOverUw":
                abs(final["interfaceSlipOverUw"] - prev["interfaceSlipOverUw"])
                if math.isfinite(final["interfaceSlipOverUw"]) and math.isfinite(prev["interfaceSlipOverUw"])
                else math.nan,
        }

    # Coarse dump-cadence k=0 drift regressions.
    dump_drift = {
        "liquid": linear_time_fit(metric_rows, "liquidGlobalMeanUx", min_step=1),
        "gas": linear_time_fit(metric_rows, "gasGlobalMeanUx", min_step=1),
        "total": linear_time_fit(metric_rows, "totalGlobalMeanUx", min_step=1),
    }

    # Prefer existing species_runtime for a finer independent time regression.
    species_runtime_path = args.output_dir / "species_runtime_0493x14w.csv"
    runtime_rows = read_species_runtime(species_runtime_path, args.liquid_type, args.gas_type)
    runtime_drift = None
    if runtime_rows:
        runtime_drift = {
            "path": str(species_runtime_path),
            "liquid": linear_time_fit(runtime_rows, "liquidMeanUx", min_step=1),
            "gas": linear_time_fit(runtime_rows, "gasMeanUx", min_step=1),
            "total": linear_time_fit(runtime_rows, "totalMeanUx", min_step=1),
        }

    common_grad_ratio = max(
        late_fit["liquidCommonSlopeOverCouetteSlope"],
        late_fit["gasCommonSlopeOverCouetteSlope"],
    )
    drift_fit = runtime_drift["total"] if runtime_drift else dump_drift["total"]
    common_mode_uniform = math.isfinite(common_grad_ratio) and common_grad_ratio < 0.10
    drift_coherent = math.isfinite(drift_fit["r2"]) and drift_fit["r2"] >= 0.95

    # Structural qualification is now based on the late averaged profile, not
    # the final stochastic snapshot.  It deliberately does not hard-code an
    # expected viscosity ratio; that comparison belongs to the physical report.
    structural = (
        math.isfinite(late_fit["liquidR2"]) and late_fit["liquidR2"] > 0.95 and
        math.isfinite(late_fit["gasR2"]) and late_fit["gasR2"] > 0.90 and
        math.isfinite(late_fit["interfaceSlipOverUw"]) and
        abs(late_fit["interfaceSlipOverUw"]) < 0.10 and
        coverage_late > 0.95
    )

    summary = {
        "benchmark": "0493x14w_two_phase_couette",
        "analysisVersion": "0493x14w-analysis-v2-dynamic-alpha-common-mode",
        "status": "PASS-like-structural" if structural else "REVIEW",
        "geometry": {
            "Lx": args.Lx, "Ly": args.Ly, "nx": args.nx, "ny": args.ny, "h": h,
            "slabStartCell": args.slab_start_cell,
            "slabEndCell": args.slab_end_cell,
            "zInterfaceInitial": z_interface_fixed,
            "interfaceExcludeCells": args.interface_exclude_cells,
            "wallExcludeCells": args.wall_exclude_cells,
            "x6cFilterLambda": X6C_FILTER_LAMBDA,
            "liquidReferenceCellMassInferred": liquid_ref_mass,
            "initialLiquidMass": initial_liquid_mass,
            "initialLiquidParticleCount": initial_liquid_count,
        },
        "wallSpeedMagnitude": args.wall_speed,
        "finalInstantaneous": final,
        "lateAverage": late_fit,
        "lateWindow": {
            "startFraction": args.late_start_fraction,
            "steps": selected_steps,
        },
        "convergenceFromPreviousDump": conv,
        "commonMode": {
            "dumpCadenceDrift": dump_drift,
            "speciesRuntimeDrift": runtime_drift,
            "lateCommonGradientMaxRelativeToCouette": common_grad_ratio,
            "spatiallyUniformTo10Percent": common_mode_uniform,
            "temporallyCoherentLinearDriftR2Ge095": drift_coherent,
            "interpretation": (
                "common x motion is predominantly an even/k=0 mode and is separated exactly "
                "from the odd Couette profile by top-bottom antisymmetrization"
                if common_mode_uniform else
                "common x motion has a measurable spatial gradient; inspect even-mode profile before "
                "treating antisymmetric Couette as fully isolated"
            ),
        },
        "interpretation": {
            "interfaceSlip": (
                "primary slip is evaluated at the offline reconstructed production x6c alpha=0.5 "
                "interface; fixed initial-slab slip is retained only as a legacy comparison"
            ),
            "slopeRatio": "muGas/muLiquid = liquidSlope/gasSlope if tangential stress is continuous",
            "wallSlip": "diagnostic of the already-characterized thermal moving-wall coupling",
            "lateAverage": "qualification uses the time-averaged odd profile to suppress MPCD thermal noise",
            "commonMode": (
                "the analyzer characterizes, but does not explain, any uniform k=0 acceleration; "
                "its contamination of the odd Couette profile is quantified by the even-mode spatial gradient"
            ),
        },
        "files": {
            "rawProfiles": str(raw_csv),
            "antisymmetricProfiles": str(asym_csv),
            "interface": str(interface_csv),
            "metrics": str(metrics_csv),
            "lateAveragedProfiles": str(late_profiles_csv),
            "lateMetrics": str(late_metrics_csv),
        },
    }
    summary_json.write_text(json.dumps(summary, indent=2, allow_nan=True) + "\n")

    print("[0493x14w-analysis] ---- late averaged qualification ----")
    print(
        "[0493x14w-analysis] "
        f"window={min(selected_steps)}..{max(selected_steps)} n={len(selected_steps)} "
        f"zG/h={z_interface_late / h:.5f} "
        f"aL={late_fit['liquidSlope']:+.7g} R2L={late_fit['liquidR2']:.5f} "
        f"aG={late_fit['gasSlope']:+.7g} R2G={late_fit['gasR2']:.5f} "
        f"aL/aG={late_fit['muGasOverMuLiquidFromSlopes']:.7g}"
    )
    print(
        "[0493x14w-analysis] "
        f"slipDynamic/Uw={late_fit['interfaceSlipOverUw']:+.4%} "
        f"slipFixed/Uw={late_fit['interfaceSlipFixedOverUw']:+.4%} "
        f"wallSlip/Uw={late_fit['gasWallSlipOverUw']:+.4%}"
    )
    print(
        "[0493x14w-analysis] common-mode "
        f"max|d u_even/dz|/|d u_odd/dz|={common_grad_ratio:.3%} "
        f"driftAcceleration={drift_fit['acceleration']:+.6g} R2={drift_fit['r2']:.5f} "
        f"source={'species_runtime' if runtime_drift else 'state_dumps'}"
    )
    print(f"[0493x14w-analysis] status={summary['status']}")
    print(f"[0493x14w-analysis] metrics={metrics_csv}")
    print(f"[0493x14w-analysis] interface={interface_csv}")
    print(f"[0493x14w-analysis] lateMetrics={late_metrics_csv}")
    print(f"[0493x14w-analysis] summary={summary_json}")


if __name__ == "__main__":
    main()
