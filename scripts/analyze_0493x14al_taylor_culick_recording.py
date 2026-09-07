#!/usr/bin/env python3
"""0493x14al — common A/B Taylor-Culick analysis from liquid mass recordings.

Both cases use exactly the same edge extraction and fit, so the paired ratio is
not contaminated by different post-processing.  The historical x13h reference
G_TC=0.79457172 is reported separately.
"""
from __future__ import annotations
import argparse, csv, json, math, statistics, sys
from array import array
from pathlib import Path


def read_csv(p):
    if not p.exists():
        return []
    with p.open(newline="") as f:
        return list(csv.DictReader(f))


def f32(path, n):
    a = array("f")
    with path.open("rb") as f:
        a.fromfile(f, n)
    if len(a) != n:
        raise RuntimeError(f"{path}: expected {n} float32, got {len(a)}")
    if sys.byteorder == "big":
        a.byteswap()
    return a


def locate_frames(root):
    # 0434 recorder has historically appeared below output/recordings; keep a
    # second root-level probe for compatibility without guessing filenames.
    tls = sorted((root/"output"/"recordings").glob("*/timeline.csv"))
    tls += sorted((root/"recordings").glob("*/timeline.csv"))
    by = {}
    for tl in tls:
        for r in read_csv(tl):
            if r.get("field") not in ("rho", "mass"):
                continue
            step = int(r["step"])
            by[step] = (float(r["time"]), int(r["nx"]), int(r["ny"]), tl.parent/r["file"])
    if not by:
        raise RuntimeError(f"{root}: no mass/rho recorder timeline found")
    return [(s,) + by[s] for s in sorted(by)]


def smooth5(v):
    n = len(v)
    if n < 5:
        return list(v)
    out = [0.0]*n
    for i in range(n):
        s = 3.0*v[i]
        if i >= 1: s += 2.0*v[i-1]
        if i+1 < n: s += 2.0*v[i+1]
        if i >= 2: s += v[i-2]
        if i+2 < n: s += v[i+2]
        out[i] = s/9.0
    return out


def interp(x0, y0, x1, y1, target):
    d = y1-y0
    if abs(d) < 1e-30:
        return 0.5*(x0+x1)
    q = min(1.0, max(0.0, (target-y0)/d))
    return x0 + q*(x1-x0)


def edges(profile, dx, split_x, threshold):
    split = min(len(profile)-2, max(1, int(split_x/dx)))
    left, right = [], []
    for i in range(len(profile)-1):
        a, b = profile[i], profile[i+1]
        x0, x1 = (i+0.5)*dx, (i+1.5)*dx
        if a < threshold <= b and i < split:
            left.append(interp(x0, a, x1, b, threshold))
        if a >= threshold > b and i >= split-1:
            right.append(interp(x0, a, x1, b, threshold))
    if not left or not right:
        raise RuntimeError(f"cannot locate both edges threshold={threshold:g}")
    return min(left), max(right)


def line_fit(xs, ys):
    if len(xs) < 3:
        return None
    xm, ym = statistics.fmean(xs), statistics.fmean(ys)
    sxx = sum((x-xm)**2 for x in xs)
    if sxx <= 0:
        return None
    slope = sum((x-xm)*(y-ym) for x, y in zip(xs, ys))/sxx
    intercept = ym - slope*xm
    pred = [intercept+slope*x for x in xs]
    sse = sum((y-p)**2 for y, p in zip(ys, pred))
    sst = sum((y-ym)**2 for y in ys)
    return intercept, slope, (1-sse/sst if sst > 0 else math.nan), math.sqrt(sse/len(xs))


def fit_window(series, key, tau, lo, hi, utc):
    rows = [r for r in series if lo*tau <= r["time"] <= hi*tau]
    if len(rows) < 5:
        return None
    t = [r["time"] for r in rows]
    xl = [r[f"xLeft_{key}"] for r in rows]
    xr = [r[f"xRight_{key}"] for r in rows]
    hs = [r[f"halfSpan_{key}"] for r in rows]
    fl, fr, fh = line_fit(t, xl), line_fit(t, xr), line_fit(t, hs)
    if not (fl and fr and fh):
        return None
    ul, ur, uh = fl[1], -fr[1], -fh[1]
    um = 0.5*(ul+ur)
    return {
        "n": len(rows), "tMin": rows[0]["time"], "tMax": rows[-1]["time"],
        "uLeft": ul, "uRight": ur, "uMean": um, "uHalfSpan": uh,
        "Gtc": um/utc, "GtcHalf": uh/utc,
        "symmetryRelative": (ul-ur)/um if abs(um) > 1e-30 else math.nan,
        "r2Left": fl[2], "r2Right": fr[2], "r2Half": fh[2],
        "rmsHalf": fh[3],
    }


def fv(r, k, default=math.nan):
    try:
        v = float(r[k])
        return v if math.isfinite(v) else default
    except Exception:
        return default


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--case", choices=("liquid", "liquid_gas"), required=True)
    ap.add_argument("--run-root", type=Path, required=True)
    ap.add_argument("--Lx", type=float, default=3.5)
    ap.add_argument("--Ly", type=float, default=1.0)
    ap.add_argument("--nx", type=int, default=896)
    ap.add_argument("--ny", type=int, default=256)
    ap.add_argument("--gamma", type=float, default=8)
    ap.add_argument("--liquid-mass", type=float, default=1.0)
    ap.add_argument("--sigma", type=float, default=10000)
    ap.add_argument("--thickness-cells", type=float, default=64)
    ap.add_argument("--dt", type=float, default=0.0063471328149122585)
    ap.add_argument("--fit-tau-min", type=float, default=0.5)
    ap.add_argument("--fit-tau-max", type=float, default=1.75)
    ap.add_argument("--historical-g-tc", type=float, default=0.79457172)
    a = ap.parse_args()
    h = a.Lx/a.nx
    if abs(h-a.Ly/a.ny) > 1e-12*max(1.0, abs(h)):
        raise SystemExit("[0493x14al-analysis] square cells required")
    H = a.thickness_cells*h
    rho = a.gamma*a.liquid_mass/(h*h)
    utc = math.sqrt(2*a.sigma/(rho*H))
    tau = H/utc
    thresholds = (0.35, 0.50, 0.65)
    frames = locate_frames(a.run_root)
    series = []
    for step, time, nxr, nyr, p in frames:
        d = f32(p, nxr*nyr)
        dxr, dyr = a.Lx/nxr, a.Ly/nyr
        line = [0.0]*nxr
        M = sx = sy = 0.0
        for iy in range(nyr):
            off = iy*nxr
            yc = (iy+0.5)*dyr
            for ix in range(nxr):
                m = float(d[off+ix])
                line[ix] += m
                M += m
                sx += m*(ix+0.5)*dxr
                sy += m*yc
        if M <= 0:
            raise RuntimeError(f"{p}: zero recorded liquid mass")
        xcm, ycm = sx/M, sy/M
        prof = smooth5(line)
        nominal = a.gamma*a.liquid_mass*a.thickness_cells*(a.nx/nxr)
        row = {"step": step, "time": time, "recNx": nxr, "recNy": nyr,
               "mass": M, "xCM": xcm, "yCM": ycm, "nominalLineMass": nominal}
        for q in thresholds:
            k = f"q{int(round(100*q)):02d}"
            xl, xr = edges(prof, dxr, xcm, q*nominal)
            row[f"xLeft_{k}"] = xl
            row[f"xRight_{k}"] = xr
            row[f"halfSpan_{k}"] = 0.5*(xr-xl)
            row[f"edgeCenter_{k}"] = 0.5*(xl+xr)
        series.append(row)
    if len(series) < 10:
        raise SystemExit(f"[0493x14al-analysis] too few recorder frames: {len(series)}")

    fits = {}
    windows = (("early", 0.25, 1.25), ("main", a.fit_tau_min, a.fit_tau_max), ("late", 1.0, 2.0))
    for q in thresholds:
        k = f"q{int(round(100*q)):02d}"
        for name, lo, hi in windows:
            fits[(k, name)] = fit_window(series, k, tau, lo, hi, utc)
    mainfit = fits[("q50", "main")]
    if mainfit is None:
        raise SystemExit("[0493x14al-analysis] q50 main fit unavailable")

    out = a.run_root/"analysis_0493x14al"
    out.mkdir(parents=True, exist_ok=True)
    fields = ["step", "time", "recNx", "recNy", "mass", "xCM", "yCM", "nominalLineMass"]
    for q in thresholds:
        k = f"q{int(round(100*q)):02d}"
        fields += [f"xLeft_{k}", f"xRight_{k}", f"halfSpan_{k}", f"edgeCenter_{k}"]
    with (out/"taylor_culick_trace.csv").open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fields)
        w.writeheader()
        w.writerows([{k: r.get(k, "") for k in fields} for r in series])

    species = read_csv(a.run_root/"output"/"species_runtime_0493x14al.csv")
    ptot = []
    for r in species:
        try:
            step = int(float(r.get("step", "nan")))
            typ = int(float(r.get("type", "nan")))
            px, py = fv(r, "momentumX"), fv(r, "momentumY")
            if math.isfinite(px) and math.isfinite(py):
                ptot.append((step, typ, px, py))
        except Exception:
            pass
    # Aggregate by step when available.
    mom_by_step = {}
    for step, typ, px, py in ptot:
        a0 = mom_by_step.setdefault(step, [0.0, 0.0])
        a0[0] += px; a0[1] += py
    pnorm_span = math.nan
    if mom_by_step:
        p0 = mom_by_step[min(mom_by_step)]
        pnorm_span = max(math.hypot(v[0]-p0[0], v[1]-p0[1]) for v in mom_by_step.values())

    masses = [r["mass"] for r in series]
    summary = {
        "benchmark": "0493x14al_historical_x13h_tc_ab",
        "case": a.case,
        "grid": [a.nx, a.ny], "h": h, "gamma": a.gamma,
        "rhoLiquid": rho, "H": H, "sigma": a.sigma, "dt": a.dt,
        "UTcTheory": utc, "tauTc": tau,
        "historicalQualifiedGtc": a.historical_g_tc,
        "mainQ50": mainfit,
        "GtcOverHistorical": mainfit["Gtc"]/a.historical_g_tc,
        "frames": len(series),
        "liquidMassRelativeSpan": (max(masses)-min(masses))/statistics.fmean(masses),
        "liquidCOMDrift": [series[-1]["xCM"]-series[0]["xCM"], series[-1]["yCM"]-series[0]["yCM"]],
        "totalMomentumMaxDriftFromFirstSample": pnorm_span,
    }
    (out/"taylor_culick_summary.json").write_text(json.dumps(summary, indent=2)+"\n")
    lines = []
    add = lines.append
    add(f"0493x14al — HISTORICAL x13h TAYLOR-CULICK / case={a.case}")
    add("="*72)
    add(f"grid={a.nx}x{a.ny} h={h:.12g} gamma={a.gamma:g} rhoL={rho:.12g}")
    add(f"H={H:.12g} sigma={a.sigma:.12g} dt={a.dt:.16g}")
    add(f"U_TC_theory={utc:.12g} tau_TC={tau:.12g} stepsPerTau={tau/a.dt:.12g}")
    add("")
    add("MAIN FIT — common liquid mass recorder q50")
    add(f"windowTau=[{a.fit_tau_min:g},{a.fit_tau_max:g}] n={mainfit['n']} t=[{mainfit['tMin']:.12g},{mainfit['tMax']:.12g}]")
    add(f"U_left={mainfit['uLeft']:.12g} U_right={mainfit['uRight']:.12g} U_mean={mainfit['uMean']:.12g}")
    add(f"G_TC={mainfit['Gtc']:.12g} symmetry={mainfit['symmetryRelative']:.12g} R2half={mainfit['r2Half']:.12g}")
    add(f"historicalQualifiedG_TC={a.historical_g_tc:.12g} ratio={mainfit['Gtc']/a.historical_g_tc:.12g}")
    add("")
    add("WINDOW / EDGE SENSITIVITY")
    for q in thresholds:
        k = f"q{int(round(100*q)):02d}"
        for name, _, _ in windows:
            z = fits[(k, name)]
            if z:
                add(f"{k} {name}: G_TC={z['Gtc']:.12g} U={z['uMean']:.12g} symmetry={z['symmetryRelative']:.12g} R2half={z['r2Half']:.12g} n={z['n']}")
    add("")
    add(f"frames={len(series)} liquidMassRelSpan={summary['liquidMassRelativeSpan']:.3e}")
    add(f"liquidCOMdrift=({summary['liquidCOMDrift'][0]:.12g},{summary['liquidCOMDrift'][1]:.12g})")
    add(f"totalMomentumMaxDriftFromFirstSample={pnorm_span:.12g}")
    (out/"taylor_culick_report.txt").write_text("\n".join(lines)+"\n")
    print(f"[0493x14al-analysis] case={a.case} U_TC={utc:.8g} U={mainfit['uMean']:.8g} G_TC={mainfit['Gtc']:.8g} R2={mainfit['r2Half']:.8g} sym={mainfit['symmetryRelative']:.3e}")
    print(f"[0493x14al-analysis] historical G={a.historical_g_tc:.8g} ratio={mainfit['Gtc']/a.historical_g_tc:.8g}")


if __name__ == "__main__":
    main()
