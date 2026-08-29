#!/usr/bin/env python3
"""0493x13m — offline mode-n modal-drop analysis from particle state dumps.

No source diagnostic is required.  For each state, the liquid COM is removed and
we evaluate the complex mass moment

    M_n = <(x-xCM + i(y-yCM))^n>_m .

For the initialized boundary r=R[c0+eps cos(n theta+phase)], Re(M_n)/R^n = eps
at first order, so its signed projection on the initial phase is a direct modal
observable.  The imaginary component is retained as a quadrature/rotation audit.

Fit model:
    q_n(t) = exp(-beta*t) [C cos(omega*t) + D sin(omega*t)] + offset
with signed beta allowed.  Stdlib only; no pandas/scipy.
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


def read_csv(path: Path):
    if not path.exists():
        return []
    with path.open(newline="") as f:
        return list(csv.DictReader(f))


def ff(row, key, default=math.nan):
    try:
        v = float(row[key])
        return v if math.isfinite(v) else default
    except Exception:
        return default


def read_array(f, code: str, n: int):
    a = array(code)
    a.fromfile(f, n)
    if len(a) != n:
        raise RuntimeError("truncated state array")
    return a


def modal_state(path: Path, mode: int, R: float, phase: float):
    with path.open("rb") as f:
        if f.read(16) != MAGIC:
            raise RuntimeError(f"{path}: bad state magic")
        version, endian, dim, layout, n, has_type, has_mass, reserved_count, type_bytes = struct.unpack(
            "<IIIIQIIII", f.read(40)
        )
        if version != 2 or endian != 0x01020304 or dim != 2 or layout != 1:
            raise RuntimeError(f"{path}: unsupported state header")
        if reserved_count:
            f.read(8 * reserved_count)
        x = read_array(f, "d", n)
        y = read_array(f, "d", n)
        _vx = read_array(f, "d", n)
        _vy = read_array(f, "d", n)
        typ = read_array(f, "I", n) if has_type else None
        mass = read_array(f, "d", n) if has_mass else None
        if has_type and type_bytes != 4:
            raise RuntimeError(f"{path}: unsupported type width {type_bytes}")
        role = read_array(f, "B", n)

    # Role 1 is active fluid in the state files used by this campaign.  If a
    # filtered dump contains only fluid particles this simply retains all rows.
    idx = [i for i in range(n) if role[i] == 1]
    if not idx:
        raise RuntimeError(f"{path}: no role=fluid particles")
    if mass is None:
        weights = None
        M = float(len(idx))
        cx = sum(x[i] for i in idx) / M
        cy = sum(y[i] for i in idx) / M
    else:
        M = sum(mass[i] for i in idx)
        if not (M > 0.0):
            raise RuntimeError(f"{path}: non-positive fluid mass")
        cx = sum(mass[i] * x[i] for i in idx) / M
        cy = sum(mass[i] * y[i] for i in idx) / M

    re_m = 0.0
    im_m = 0.0
    rpow = 0.0
    # Explicit n=4 path is both faster and numerically transparent.
    # Keep a generic complex-power fallback for defensive reuse.
    if mode == 4:
        for i in idx:
            w = 1.0 if mass is None else mass[i]
            dx = x[i] - cx
            dy = y[i] - cy
            dx2 = dx * dx
            dy2 = dy * dy
            re_m += w * (dx2 * dx2 - 6.0 * dx2 * dy2 + dy2 * dy2)
            im_m += w * (4.0 * dx * dy * (dx2 - dy2))
            r2 = dx2 + dy2
            rpow += w * r2 * r2
    else:
        for i in idx:
            w = 1.0 if mass is None else mass[i]
            dx = x[i] - cx
            dy = y[i] - cy
            z = complex(dx, dy) ** mode
            re_m += w * z.real
            im_m += w * z.imag
            rpow += w * math.hypot(dx, dy) ** mode
    re_m /= M
    im_m /= M
    rpow /= M

    # Projection on the initialized harmonic phase.  The generator uses
    # cos(n theta + phase), hence the corresponding complex moment has phase
    # approximately -phase.
    cp, sp = math.cos(phase), math.sin(phase)
    q_parallel = (re_m * cp - im_m * sp) / (R ** mode)
    q_quadrature = (re_m * sp + im_m * cp) / (R ** mode)
    q_abs = math.hypot(re_m, im_m) / (R ** mode)
    return {
        "particles": len(idx), "mass": M, "xCM": cx, "yCM": cy,
        "qParallel": q_parallel, "qQuadrature": q_quadrature, "qAbs": q_abs,
        "momentReal": re_m, "momentImag": im_m, "radialMoment": rpow,
    }


def solve3(M, b):
    A = [list(map(float, row)) + [float(rhs)] for row, rhs in zip(M, b)]
    for i in range(3):
        piv = max(range(i, 3), key=lambda r: abs(A[r][i]))
        if abs(A[piv][i]) < 1.0e-20:
            return None
        A[i], A[piv] = A[piv], A[i]
        q = A[i][i]
        for j in range(i, 4):
            A[i][j] /= q
        for r in range(3):
            if r == i:
                continue
            q = A[r][i]
            for j in range(i, 4):
                A[r][j] -= q * A[i][j]
    return [A[i][3] for i in range(3)]


def linear_fit_for(t, y, omega, beta):
    cols = []
    for tt in t:
        e = math.exp(-beta * tt)
        cols.append((e * math.cos(omega * tt), e * math.sin(omega * tt), 1.0))
    M = [[sum(c[i] * c[j] for c in cols) for j in range(3)] for i in range(3)]
    b = [sum(c[i] * yy for c, yy in zip(cols, y)) for i in range(3)]
    coef = solve3(M, b)
    if coef is None:
        return None
    pred = [coef[0] * c[0] + coef[1] * c[1] + coef[2] for c in cols]
    sse = sum((yy - pp) ** 2 for yy, pp in zip(y, pred))
    ym = statistics.fmean(y)
    sst = sum((yy - ym) ** 2 for yy in y)
    r2 = 1.0 - sse / sst if sst > 0.0 else math.nan
    return sse, r2, coef, pred


def fit_damped_signed(t_abs, y, omega0, beta_ref):
    t0 = t_abs[0]
    t = [v - t0 for v in t_abs]
    wlo, whi = 0.65 * omega0, 1.25 * omega0
    blo, bhi = -3.0 * beta_ref, 6.0 * beta_ref
    best = None
    for nw, nb in ((121, 91), (81, 61), (61, 41)):
        for iw in range(nw):
            w = wlo + (whi - wlo) * iw / max(1, nw - 1)
            for ib in range(nb):
                beta = blo + (bhi - blo) * ib / max(1, nb - 1)
                r = linear_fit_for(t, y, w, beta)
                if r is not None and (best is None or r[0] < best[0]):
                    best = (r[0], w, beta, r[1], r[2], r[3])
        if best is None:
            return None
        _, w, beta, _, _, _ = best
        dw = (whi - wlo) / max(1, nw - 1) * 3.0
        db = (bhi - blo) / max(1, nb - 1) * 3.0
        wlo, whi = max(0.2 * omega0, w - dw), w + dw
        blo, bhi = beta - db, beta + db
    return best


def zero_cross_omega(t, y, offset):
    z = [v - offset for v in y]
    crossings = []
    for i in range(1, len(z)):
        a, b = z[i - 1], z[i]
        if a == 0.0:
            crossings.append(t[i - 1])
        elif a * b < 0.0:
            frac = abs(a) / (abs(a) + abs(b))
            crossings.append(t[i - 1] + frac * (t[i] - t[i - 1]))
    if len(crossings) < 3:
        return math.nan, len(crossings)
    hp = statistics.median(crossings[i + 1] - crossings[i] for i in range(len(crossings) - 1))
    return (math.pi / hp if hp > 0.0 else math.nan), len(crossings)


def mean(xs):
    return statistics.fmean(xs) if xs else math.nan


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--run-root", type=Path, required=True)
    ap.add_argument("--radius-cells", type=float, default=40.0)
    ap.add_argument("--sigma", type=float, default=10000.0)
    ap.add_argument("--gamma", type=float, default=8.0)
    ap.add_argument("--mass", type=float, default=1.0)
    ap.add_argument("--h", type=float, default=1.0 / 256.0)
    ap.add_argument("--nu", type=float, default=5.1e-4)
    ap.add_argument("--dt", type=float, default=0.0063471328149122585)
    ap.add_argument("--mode", type=int, default=4)
    ap.add_argument("--phase", type=float, default=0.0)
    ap.add_argument("--fit-periods", type=float, default=2.5)
    args = ap.parse_args()
    if args.mode != 4:
        raise SystemExit("[0493x13m-analysis] this analyzer is locked to mode=4")

    out = args.run_root / "output"
    states = []
    for p in sorted(out.glob("state_step_*.smpcd")):
        m = STEP_RE.search(p.name)
        if m:
            states.append((int(m.group(1)), p))
    if len(states) < 20:
        raise SystemExit(f"[0493x13m-analysis] need >=20 state dumps, got {len(states)}")

    R = args.radius_cells * args.h
    rho = args.gamma * args.mass / (args.h * args.h)
    n = args.mode
    omega0 = math.sqrt(n * (n * n - 1.0) * args.sigma / (rho * R ** 3))
    T0 = 2.0 * math.pi / omega0
    beta_ref = 2.0 * n * (n - 1.0) * args.nu / (R * R)
    omega_ref = math.sqrt(max(0.0, omega0 * omega0 - beta_ref * beta_ref))

    series = []
    for step, p in states:
        q = modal_state(p, n, R, args.phase)
        series.append({"step": step, "time": step * args.dt, **q})
    series.sort(key=lambda r: r["step"])

    fit_end = series[0]["time"] + args.fit_periods * T0
    fit = [r for r in series if r["time"] <= fit_end + 1.0e-12]
    if len(fit) < 16:
        raise SystemExit(f"[0493x13m-analysis] only {len(fit)} states in fit window")
    tt = [r["time"] for r in fit]
    yy = [r["qParallel"] for r in fit]
    best = fit_damped_signed(tt, yy, omega0, beta_ref)
    if best is None:
        raise SystemExit("[0493x13m-analysis] damped fit failed")
    _sse, omega, beta, r2, coef, pred = best
    offset = coef[2]
    omega_zc, zc_count = zero_cross_omega(tt, yy, offset)

    analysis = args.run_root / "analysis_0493x13m"
    analysis.mkdir(parents=True, exist_ok=True)
    trace = analysis / "oscillating_drop_n4_state_moment_trace.csv"
    with trace.open("w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["step", "time", "q4Parallel", "q4Quadrature", "q4Abs", "xCM", "yCM", "particles", "mass", "momentReal", "momentImag", "radialMoment"])
        for r in series:
            w.writerow([r[k] for k in ("step", "time", "qParallel", "qQuadrature", "qAbs", "xCM", "yCM", "particles", "mass", "momentReal", "momentImag", "radialMoment")])

    # Existing ancillary diagnostics, sampled by the simulation itself.
    pressure = read_csv(out / "cuda_static_drop_pressure_0493x9e.csv")
    pfit = [r for r in pressure if ff(r, "time") <= fit[-1]["time"] + 1e-12]
    reffs = [ff(r, "effectiveRadius") for r in pfit if math.isfinite(ff(r, "effectiveRadius"))]
    resultants = [abs(ff(r, "normalizedDiscreteResultant")) for r in pfit if math.isfinite(ff(r, "normalizedDiscreteResultant"))]
    limiter = read_csv(out / "cuda_surface_tension_limiter_0493x9r.csv")
    lfit = [r for r in limiter if ff(r, "time") <= fit[-1]["time"] + 1e-12]
    clips = [ff(r, "clipFraction") for r in lfit if math.isfinite(ff(r, "clipFraction"))]
    velocity = read_csv(out / "cuda_static_drop_velocity_0493x9e.csv")
    vfit = [r for r in velocity if ff(r, "time") <= fit[-1]["time"] + 1e-12]
    virms = [ff(r, "interfaceSpeedRms") for r in vfit if math.isfinite(ff(r, "interfaceSpeedRms"))]
    summary = read_csv(out / "summary_runtime.csv")
    kbts = []
    masses = []
    for r in summary:
        if ff(r, "time") > fit[-1]["time"] + 1e-12:
            continue
        kval = ff(r, "kBTEstimate")
        if not math.isfinite(kval):
            kval = ff(r, "kBT")
        if math.isfinite(kval):
            kbts.append(kval)
        mval = ff(r, "totalMass")
        if math.isfinite(mval):
            masses.append(mval)

    q0 = series[0]["qParallel"]
    qquad_rms = math.sqrt(mean([r["qQuadrature"] ** 2 for r in fit]))
    lines = [
        "===== 0493x13m 2-D OSCILLATING DROP / n=4 =====",
        "status=MEASURED (campaign/ensemble decision remains external)",
        f"stateRows={len(series)} fitRows={len(fit)} dumpStep={series[1]['step']-series[0]['step'] if len(series)>1 else -1} fitWindow=[{fit[0]['time']:.9g},{fit[-1]['time']:.9g}]",
        f"R={R:.12g} R/h={args.radius_cells:g} rhoRef={rho:.12g} sigma={args.sigma:.12g} nuRef={args.nu:.12g}",
        f"theory2D.inviscid omega0={omega0:.12g} period0={T0:.12g}",
        f"theory2D.weakVisc beta={beta_ref:.12g} omegaDamped={omega_ref:.12g}",
        f"fit omega={omega:.12g} beta={beta:.12g} R2={r2:.9g} offset={offset:.9g} C={coef[0]:.9g} D={coef[1]:.9g}",
        f"gain Gomega={omega/omega0:.9g} Gbeta={beta/beta_ref:.9g}",
        f"zeroCross omega={omega_zc:.12g} crossings={zc_count} ratioToTheory={omega_zc/omega0 if math.isfinite(omega_zc) else math.nan:.9g}",
        f"modal q4Initial={q0:.9g} q4MinFit={min(yy):.9g} q4MaxFit={max(yy):.9g} quadratureRmsFit={qquad_rms:.9g}",
        f"state massMin={min(r['mass'] for r in series):.12g} massMax={max(r['mass'] for r in series):.12g} particlesMin={min(r['particles'] for r in series)} particlesMax={max(r['particles'] for r in series)}",
        f"existingDiagnostics ReffMeanFit={mean(reffs):.9g} normalizedResultantMaxFit={max(resultants) if resultants else math.nan:.9g}",
        f"existingDiagnostics clipMeanFit={mean(clips):.9g} clipMaxFit={max(clips) if clips else math.nan:.9g} interfaceSpeedRmsMeanFit={mean(virms):.9g} kBTMeanFit={mean(kbts):.9g}",
        "observable=q4=Re(<(z-zCM)^4> exp(+i*phase))/R^4; quadrature is audited separately.",
        "interpretation=frequency/damping characterize dynamic capillary response only; mechanical sigma remains the Young-Laplace quantity.",
    ]
    report = "\n".join(lines) + "\n"
    (analysis / "oscillating_drop_n4_state_moment_report.txt").write_text(report)
    print(report, end="")


if __name__ == "__main__":
    main()
