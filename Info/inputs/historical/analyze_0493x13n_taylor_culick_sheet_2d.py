#!/usr/bin/env python3
"""0493x13n — offline Taylor-Culick sheet-retraction analysis.

The two free edges are measured from the x-integrated liquid line-mass profile.
For each particle state, mass is binned by x cell and lightly smoothed.  The left
and right outer crossings of a fixed fraction of the nominal flat-sheet line
mass define the two rim positions.  Their mean inward speed is compared with

    U_TC = sqrt(2 sigma / (rho H)).

Using two symmetric rims suppresses global translation: the left rim should move
+U_TC and the right rim -U_TC, while the centre of mass remains nearly fixed.
Thresholds 0.35, 0.50 and 0.65 and several fit windows are reported so that the
result does not depend on one arbitrary edge definition or time interval.

No source diagnostic and no pandas/scipy dependency are required.
"""
from __future__ import annotations

import argparse
import csv
import math
import re
import statistics
import struct
from array import array
from pathlib import Path

MAGIC = b"SRCMPCD_STATE" + b"\0" * (16 - len("SRCMPCD_STATE"))
STEP_RE = re.compile(r"state_step_(\d+)\.smpcd$")


def read_array(f, code: str, n: int):
    a = array(code)
    a.fromfile(f, n)
    if len(a) != n:
        raise RuntimeError("truncated state array")
    return a


def read_state(path: Path):
    with path.open("rb") as f:
        if f.read(16) != MAGIC:
            raise RuntimeError(f"{path}: bad state magic")
        version, endian, dim, layout, n, has_type, has_mass, reserved_count, type_bytes = struct.unpack(
            "<IIIIQIIII", f.read(40)
        )
        if version != 2 or endian != 0x01020304 or dim != 2 or layout != 1:
            raise RuntimeError(f"{path}: unsupported state header")
        if reserved_count:
            f.read(8*reserved_count)
        x = read_array(f, "d", n)
        y = read_array(f, "d", n)
        vx = read_array(f, "d", n)
        vy = read_array(f, "d", n)
        _typ = read_array(f, "I", n) if has_type else None
        mass = read_array(f, "d", n) if has_mass else None
        if has_type and type_bytes != 4:
            raise RuntimeError(f"{path}: unsupported type width {type_bytes}")
        role = read_array(f, "B", n)
    return x, y, vx, vy, mass, role


def smooth5(v):
    n = len(v)
    if n < 5:
        return list(v)
    out = [0.0]*n
    # Symmetric [1,2,3,2,1]/9 kernel.  Zero padding is harmless because the
    # sheet stays far from the external walls.
    for i in range(n):
        s = 3.0*v[i]
        if i >= 1: s += 2.0*v[i-1]
        if i+1 < n: s += 2.0*v[i+1]
        if i >= 2: s += v[i-2]
        if i+2 < n: s += v[i+2]
        out[i] = s/9.0
    return out


def interp_cross(x0, y0, x1, y1, target):
    d = y1-y0
    if abs(d) < 1e-30:
        return 0.5*(x0+x1)
    q = (target-y0)/d
    q = min(1.0, max(0.0, q))
    return x0 + q*(x1-x0)


def extract_edges(profile, h, split_x, threshold):
    n = len(profile)
    split = min(n-2, max(1, int(split_x/h)))
    left_candidates = []
    right_candidates = []
    for i in range(n-1):
        a, b = profile[i], profile[i+1]
        x0, x1 = (i+0.5)*h, (i+1.5)*h
        if a < threshold <= b and i < split:
            left_candidates.append(interp_cross(x0, a, x1, b, threshold))
        if a >= threshold > b and i >= split-1:
            right_candidates.append(interp_cross(x0, a, x1, b, threshold))
    if not left_candidates or not right_candidates:
        raise RuntimeError(
            f"cannot locate both sheet edges at threshold={threshold:.6g}; "
            f"left crossings={len(left_candidates)} right crossings={len(right_candidates)}"
        )
    # Outer crossings; any internal modulation/rim shoulder is ignored.
    return min(left_candidates), max(right_candidates)


def state_metrics(path: Path, nx: int, h: float, center_x: float,
                  nominal_line_mass: float, threshold_fracs, core_half_width: float):
    x, y, vx, vy, mass, role = read_state(path)
    idx = [i for i in range(len(x)) if role[i] == 1]
    if not idx:
        raise RuntimeError(f"{path}: no active fluid particles")
    line = [0.0]*nx
    M = 0.0; sx = sy = spx = spy = 0.0
    coreM = corePx = corePy = 0.0
    xmin = math.inf; xmax = -math.inf; ymin = math.inf; ymax = -math.inf
    for i in idx:
        w = 1.0 if mass is None else mass[i]
        M += w; sx += w*x[i]; sy += w*y[i]; spx += w*vx[i]; spy += w*vy[i]
        xmin = min(xmin, x[i]); xmax = max(xmax, x[i]); ymin = min(ymin, y[i]); ymax = max(ymax, y[i])
        ix = int(math.floor(x[i]/h))
        if 0 <= ix < nx:
            line[ix] += w
        if abs(x[i]-center_x) <= core_half_width:
            coreM += w; corePx += w*vx[i]; corePy += w*vy[i]
    cx = sx/M; cy = sy/M
    prof = smooth5(line)
    out = {
        "particles": len(idx), "mass": M, "xCM": cx, "yCM": cy,
        "meanVx": spx/M, "meanVy": spy/M,
        "coreMeanVx": corePx/coreM if coreM > 0 else math.nan,
        "coreMeanVy": corePy/coreM if coreM > 0 else math.nan,
        "xMinRaw": xmin, "xMaxRaw": xmax, "yMinRaw": ymin, "yMaxRaw": ymax,
    }
    for q in threshold_fracs:
        xl, xr = extract_edges(prof, h, cx, q*nominal_line_mass)
        key = f"q{int(round(100*q)):02d}"
        out[f"xLeft_{key}"] = xl
        out[f"xRight_{key}"] = xr
        out[f"halfSpan_{key}"] = 0.5*(xr-xl)
        out[f"edgeCenter_{key}"] = 0.5*(xr+xl)
    return out


def line_fit(xs, ys):
    if len(xs) < 3:
        return None
    xm = statistics.fmean(xs); ym = statistics.fmean(ys)
    sxx = sum((x-xm)**2 for x in xs)
    if sxx <= 0:
        return None
    slope = sum((x-xm)*(y-ym) for x, y in zip(xs, ys))/sxx
    intercept = ym-slope*xm
    pred = [intercept+slope*x for x in xs]
    sse = sum((y-p)**2 for y, p in zip(ys, pred))
    sst = sum((y-ym)**2 for y in ys)
    r2 = 1.0-sse/sst if sst > 0 else math.nan
    rms = math.sqrt(sse/len(xs))
    return intercept, slope, r2, rms


def csv_rows(path: Path):
    if not path.exists():
        return []
    with path.open(newline="") as f:
        return list(csv.DictReader(f))


def fv(row, key, default=math.nan):
    try:
        x = float(row[key])
        return x if math.isfinite(x) else default
    except Exception:
        return default


def mean_finite(vals):
    z = [v for v in vals if math.isfinite(v)]
    return statistics.fmean(z) if z else math.nan


def max_finite(vals):
    z = [v for v in vals if math.isfinite(v)]
    return max(z) if z else math.nan


def fit_window(series, qkey, tau, tmin_tau, tmax_tau, utc):
    rows = [r for r in series if tmin_tau*tau <= r["time"] <= tmax_tau*tau]
    if len(rows) < 5:
        return None
    t = [r["time"] for r in rows]
    xl = [r[f"xLeft_{qkey}"] for r in rows]
    xr = [r[f"xRight_{qkey}"] for r in rows]
    hs = [r[f"halfSpan_{qkey}"] for r in rows]
    fl = line_fit(t, xl); fr = line_fit(t, xr); fh = line_fit(t, hs)
    if not (fl and fr and fh):
        return None
    uL = fl[1]
    uR = -fr[1]
    uHalf = -fh[1]
    uMean = 0.5*(uL+uR)
    sym = (uL-uR)/uMean if abs(uMean) > 1e-30 else math.nan
    return {
        "n": len(rows), "tMin": rows[0]["time"], "tMax": rows[-1]["time"],
        "uLeft": uL, "uRight": uR, "uMean": uMean, "uHalfSpan": uHalf,
        "Gtc": uMean/utc, "GtcHalf": uHalf/utc,
        "symmetryRelative": sym,
        "r2Left": fl[2], "r2Right": fr[2], "r2Half": fh[2],
        "rmsLeft": fl[3], "rmsRight": fr[3], "rmsHalf": fh[3],
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--run-root", type=Path, required=True)
    ap.add_argument("--Lx", type=float, default=2.5)
    ap.add_argument("--Ly", type=float, default=1.0)
    ap.add_argument("--nx", type=int, default=640)
    ap.add_argument("--ny", type=int, default=256)
    ap.add_argument("--gamma", type=float, default=8.0)
    ap.add_argument("--mass", type=float, default=1.0)
    ap.add_argument("--sigma", type=float, default=10000.0)
    ap.add_argument("--thickness-cells", type=float, default=64.0)
    ap.add_argument("--sheet-length-cells", type=float, default=512.0)
    ap.add_argument("--edge-round-cells", type=float, default=8.0)
    ap.add_argument("--center-x", type=float, default=1.25)
    ap.add_argument("--center-y", type=float, default=0.5)
    ap.add_argument("--dt", type=float, default=0.0063471328149122585)
    ap.add_argument("--nu", type=float, default=5.1e-4)
    ap.add_argument("--fit-tau-min", type=float, default=0.5)
    ap.add_argument("--fit-tau-max", type=float, default=1.75)
    args = ap.parse_args()

    h = args.Lx/args.nx
    if abs(h-args.Ly/args.ny) > 1e-12*max(1.0, abs(h)):
        raise SystemExit("[0493x13n-analysis] square cells required")
    H = args.thickness_cells*h
    rho = args.gamma*args.mass/(h*h)
    utc = math.sqrt(2.0*args.sigma/(rho*H))
    tau = H/utc
    mu = rho*args.nu
    oh = mu/math.sqrt(rho*args.sigma*H)
    re = utc*H/args.nu
    ca = mu*utc/args.sigma
    nominal_line_mass = args.gamma*args.mass*args.thickness_cells
    core_half_width = 0.125*(args.sheet_length_cells*h)
    thresholds = (0.35, 0.50, 0.65)

    init_candidates = sorted((args.run_root/"init").glob("*.smpcd"))
    if not init_candidates:
        raise SystemExit("[0493x13n-analysis] missing initial state")
    states = [(0, init_candidates[0])]
    for p in sorted((args.run_root/"output").glob("state_step_*.smpcd")):
        m = STEP_RE.search(p.name)
        if m:
            states.append((int(m.group(1)), p))
    # De-duplicate step zero defensively.
    uniq = {}
    for step, p in states:
        uniq[step] = p
    states = sorted(uniq.items())
    if len(states) < 10:
        raise SystemExit(f"[0493x13n-analysis] need >=10 states including init, got {len(states)}")

    series = []
    for step, p in states:
        m = state_metrics(p, args.nx, h, args.center_x, nominal_line_mass, thresholds, core_half_width)
        series.append({"step": step, "time": step*args.dt, **m})

    # Retraction relative to each threshold's own t=0 position.
    for q in thresholds:
        key = f"q{int(round(100*q)):02d}"
        hs0 = series[0][f"halfSpan_{key}"]
        for r in series:
            r[f"retraction_{key}"] = hs0-r[f"halfSpan_{key}"]
            r[f"retractionOverH_{key}"] = (hs0-r[f"halfSpan_{key}"])/H

    windows = [
        ("early", 0.25, 1.25),
        ("main", args.fit_tau_min, args.fit_tau_max),
        ("late", 1.0, 2.0),
    ]
    fits = {}
    for q in thresholds:
        qkey = f"q{int(round(100*q)):02d}"
        for name, a, b in windows:
            fits[(qkey, name)] = fit_window(series, qkey, tau, a, b, utc)

    outdir = args.run_root/"analysis_0493x13n"
    outdir.mkdir(parents=True, exist_ok=True)
    trace_path = outdir/"taylor_culick_trace.csv"
    fields = ["step", "time", "particles", "mass", "xCM", "yCM", "meanVx", "meanVy", "coreMeanVx", "coreMeanVy",
              "xMinRaw", "xMaxRaw", "yMinRaw", "yMaxRaw"]
    for q in thresholds:
        k = f"q{int(round(100*q)):02d}"
        fields += [f"xLeft_{k}", f"xRight_{k}", f"halfSpan_{k}", f"edgeCenter_{k}", f"retraction_{k}", f"retractionOverH_{k}"]
    with trace_path.open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fields)
        w.writeheader()
        for r in series:
            w.writerow({k: r.get(k, "") for k in fields})

    summary = csv_rows(args.run_root/"output"/"summary_runtime.csv")
    kbt_mean = mean_finite([fv(r, "kBTEstimate") for r in summary])
    q6_bad = sum(1 for r in summary if fv(r, "q6Applied", 0.0) > 0.5 and fv(r, "q6Converged", 0.0) < 0.5)
    q6_resmax = max_finite([fv(r, "q6ResidualRel") for r in summary if fv(r, "q6Applied", 0.0) > 0.5])
    wall_hits = 0.0
    if summary:
        rr = summary[-1]
        wall_hits = sum(max(0.0, fv(rr, k, 0.0)) for k in ("hitsLeft","hitsRight","hitsBottom","hitsTop"))

    limiter = csv_rows(args.run_root/"output"/"cuda_surface_tension_limiter_0493x9r.csv")
    clip_all_mean = mean_finite([fv(r, "clipFraction") for r in limiter])
    clip_all_max = max_finite([fv(r, "clipFraction") for r in limiter])
    tlo, thi = args.fit_tau_min*tau, args.fit_tau_max*tau
    clip_main = [fv(r, "clipFraction") for r in limiter if tlo <= fv(r, "time", -1.0) <= thi]
    clip_main_mean = mean_finite(clip_main)
    clip_main_max = max_finite(clip_main)

    masses = [r["mass"] for r in series]
    com_dx = series[-1]["xCM"]-series[0]["xCM"]
    com_dy = series[-1]["yCM"]-series[0]["yCM"]
    core_vx_rms = math.sqrt(mean_finite([r["coreMeanVx"]**2 for r in series if math.isfinite(r["coreMeanVx"])]))

    main50 = fits[("q50", "main")]
    if main50 is None:
        raise SystemExit("[0493x13n-analysis] main q50 fit unavailable")

    report = outdir/"taylor_culick_report.txt"
    lines = []
    add = lines.append
    add("0493x13n — 2-D Taylor-Culick sheet retraction")
    add("================================================")
    add(f"runRoot={args.run_root}")
    add(f"grid={args.nx}x{args.ny} L={args.Lx}x{args.Ly} h={h:.12g}")
    add(f"rho={rho:.12g} gamma={args.gamma:.12g} particleMass={args.mass:.12g}")
    add(f"sheetThicknessH={H:.12g} H/h={args.thickness_cells:.12g}")
    add(f"sheetLength={args.sheet_length_cells*h:.12g} Lsheet/h={args.sheet_length_cells:.12g}")
    add(f"edgeRoundRadius={args.edge_round_cells*h:.12g} edgeRound/h={args.edge_round_cells:.12g}")
    add(f"sigma={args.sigma:.12g} nuRef={args.nu:.12g} dt={args.dt:.12g}")
    add(f"U_TC=sqrt(2sigma/(rho H))={utc:.12g}")
    add(f"tau_TC=H/U_TC={tau:.12g} stepsPerTau={tau/args.dt:.12g}")
    add(f"Oh_H={oh:.12g} Re_TC={re:.12g} Ca={ca:.12g} We_H=2")
    add("")
    add("MAIN FIT — q50 integrated-line-mass edge")
    add(f"windowTau=[{args.fit_tau_min:.6g},{args.fit_tau_max:.6g}] n={main50['n']} t=[{main50['tMin']:.12g},{main50['tMax']:.12g}]")
    add(f"U_left={main50['uLeft']:.12g} U_right={main50['uRight']:.12g} U_mean={main50['uMean']:.12g}")
    add(f"U_halfSpan={main50['uHalfSpan']:.12g}")
    add(f"G_TC=U_mean/U_TC={main50['Gtc']:.12g}")
    add(f"G_TC_halfSpan={main50['GtcHalf']:.12g}")
    add(f"leftRightSymmetryRelative={main50['symmetryRelative']:.12g}")
    add(f"R2_left={main50['r2Left']:.12g} R2_right={main50['r2Right']:.12g} R2_halfSpan={main50['r2Half']:.12g}")
    add("")
    add("WINDOW / EDGE-DEFINITION SENSITIVITY")
    for q in thresholds:
        qkey = f"q{int(round(100*q)):02d}"
        for name, _, _ in windows:
            z = fits[(qkey, name)]
            if z:
                add(f"{qkey} {name}: G_TC={z['Gtc']:.12g} U={z['uMean']:.12g} symmetry={z['symmetryRelative']:.12g} R2half={z['r2Half']:.12g} n={z['n']}")
    add("")
    add("AUXILIARY AUDITS")
    add(f"states={len(series)} massMin={min(masses):.12g} massMax={max(masses):.12g} massRelSpan={(max(masses)-min(masses))/statistics.fmean(masses):.3e}")
    add(f"COMdrift=({com_dx:.12g},{com_dy:.12g}) coreMeanVxRms={core_vx_rms:.12g} coreVxRms/U_TC={core_vx_rms/utc:.12g}")
    add(f"kBTMeanSummary={kbt_mean:.12g}")
    add(f"Q6nonConvergedSamples={q6_bad} Q6residualRelMax={q6_resmax:.12g}")
    add(f"limiterClipMeanAll={clip_all_mean:.12g} limiterClipMaxAll={clip_all_max:.12g}")
    add(f"limiterClipMeanMain={clip_main_mean:.12g} limiterClipMaxMain={clip_main_max:.12g}")
    add(f"externalWallHitsCumulativeFinal={wall_hits:.12g}")
    add("")
    add("Interpretation contract: MEASURED only. Qualification is decided after inspecting")
    add("G_TC, linearity, left/right symmetry, threshold/window sensitivity and auxiliary audits.")
    report.write_text("\n".join(lines)+"\n")

    print(f"[0493x13n-analysis] U_TC={utc:.8g} tau={tau:.8g} Re={re:.6g} Oh={oh:.6g}")
    print(f"[0493x13n-analysis] MAIN U={main50['uMean']:.8g} G_TC={main50['Gtc']:.8g} symmetry={main50['symmetryRelative']:.3e} R2half={main50['r2Half']:.8g}")
    print(f"[0493x13n-analysis] report={report}")
    print(f"[0493x13n-analysis] trace={trace_path}")


if __name__ == "__main__":
    main()
