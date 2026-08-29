#!/usr/bin/env python3
"""0493x13k — offline n=2 oscillating-drop analysis (stdlib only).

Primary observable: signed quadrupolar deformation reconstructed from the
existing x9f second-moment diagnostic.  If e=(a-b)/(a+b) and psi is the major
principal-axis angle, q2=e*cos(2*psi).  This keeps the sign through the 90-degree
axis exchange and avoids the frequency doubling that would occur if |e| were fit.

Fit model:
    q2(t) = exp(-beta*t) [C cos(omega*t) + D sin(omega*t)] + offset
No phase is forced.  The primary frequency reference is the strict 2-D inviscid
Rayleigh law; weak-viscosity Lamb damping is reported as a secondary reference.
No pandas/scipy dependency.
"""
from __future__ import annotations

import argparse
import csv
import math
import statistics
from pathlib import Path


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


def norm_name(s: str) -> str:
    return "".join(ch.lower() for ch in s if ch.isalnum())


def resolve_field(fields, exact=(), contains=()):
    by_norm = {norm_name(k): k for k in fields}
    for x in exact:
        if norm_name(x) in by_norm:
            return by_norm[norm_name(x)]
    for k in fields:
        nk = norm_name(k)
        if all(norm_name(x) in nk for x in contains):
            return k
    return None


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


def fit_damped(t_abs, y, omega0):
    t0 = t_abs[0]
    t = [q - t0 for q in t_abs]
    wlo, whi = 0.35 * omega0, 1.35 * omega0
    blo, bhi = 0.0, min(3.0, 0.8 * omega0)
    best = None
    grids = [(101, 51), (71, 41), (51, 31)]
    for nw, nb in grids:
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
        wlo, whi = max(0.05 * omega0, w - dw), w + dw
        blo, bhi = max(0.0, beta - db), beta + db
    return best


def linreg_slope(x, y):
    if len(x) < 2:
        return math.nan
    mx, my = statistics.fmean(x), statistics.fmean(y)
    den = sum((v - mx) ** 2 for v in x)
    return sum((a - mx) * (b - my) for a, b in zip(x, y)) / den if den else math.nan


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
    half_periods = [crossings[i + 1] - crossings[i] for i in range(len(crossings) - 1)]
    hp = statistics.median(half_periods)
    return math.pi / hp if hp > 0 else math.nan, len(crossings)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--run-root", type=Path, required=True)
    ap.add_argument("--radius-cells", type=float, default=40.0)
    ap.add_argument("--sigma", type=float, default=10000.0)
    ap.add_argument("--gamma", type=float, default=8.0)
    ap.add_argument("--mass", type=float, default=1.0)
    ap.add_argument("--h", type=float, default=1.0 / 256.0)
    ap.add_argument("--nu", type=float, default=5.1e-4)
    ap.add_argument("--mode", type=int, default=2)
    ap.add_argument("--fit-periods", type=float, default=2.5)
    args = ap.parse_args()

    if args.mode != 2:
        raise SystemExit("[0493x13k-analysis] mode must be 2: x9f second moments are a quadrupole diagnostic")

    shape_path = args.run_root / "output/cuda_ellipse_shape_0493x9f.csv"
    rows = read_csv(shape_path)
    if len(rows) < 20:
        raise SystemExit(f"[0493x13k-analysis] need >=20 x9f shape rows, got {len(rows)}: {shape_path}")
    fields = list(rows[0])

    f_step = resolve_field(fields, exact=("step",))
    f_time = resolve_field(fields, exact=("time",))
    f_major = resolve_field(fields, exact=("momentRadiusMajor",), contains=("moment", "radius", "major"))
    f_minor = resolve_field(fields, exact=("momentRadiusMinor",), contains=("moment", "radius", "minor"))
    f_ell = resolve_field(fields, exact=("ellipticity",), contains=("ellipt",))
    f_xcm = resolve_field(fields, exact=("xCM",), contains=("xcm",))
    f_ycm = resolve_field(fields, exact=("yCM",), contains=("ycm",))
    f_angle_deg = resolve_field(
        fields,
        exact=("principalAngleDeg", "momentAngleDeg", "angleDeg", "principalAngleDegrees"),
        contains=("angle", "deg"),
    )
    f_angle_rad = resolve_field(
        fields,
        exact=("principalAngle", "momentAngle", "angle"),
        contains=("angle",),
    )

    required = {"step": f_step, "time": f_time, "major": f_major, "minor": f_minor}
    missing = [k for k, v in required.items() if v is None]
    if missing:
        raise SystemExit(
            "[0493x13k-analysis] x9f CSV misses required field(s) "
            + ",".join(missing)
            + "; available="
            + ",".join(fields)
        )
    if f_angle_deg is None and f_angle_rad is None:
        raise SystemExit(
            "[0493x13k-analysis] x9f CSV has no principal-angle field; cannot reconstruct signed n=2 mode. available="
            + ",".join(fields)
        )

    series = []
    seen = set()
    for r in rows:
        step = int(round(ff(r, f_step)))
        t = ff(r, f_time)
        maj, minu = ff(r, f_major), ff(r, f_minor)
        if step in seen or not all(math.isfinite(v) for v in (t, maj, minu)) or maj <= 0 or minu <= 0:
            continue
        seen.add(step)
        ell = ff(r, f_ell) if f_ell else (maj - minu) / (maj + minu)
        if f_angle_deg is not None:
            ang = math.radians(ff(r, f_angle_deg))
        else:
            ang = ff(r, f_angle_rad)
        if not all(math.isfinite(v) for v in (ell, ang)):
            continue
        q2 = ell * math.cos(2.0 * ang)
        xcm = ff(r, f_xcm) if f_xcm else math.nan
        ycm = ff(r, f_ycm) if f_ycm else math.nan
        series.append((step, t, q2, ell, ang, maj, minu, xcm, ycm))
    series.sort(key=lambda q: (q[1], q[0]))
    if len(series) < 20:
        raise SystemExit(f"[0493x13k-analysis] only {len(series)} usable signed-mode rows")

    R = args.radius_cells * args.h
    rho = args.gamma * args.mass / (args.h * args.h)
    n = args.mode
    omega0 = math.sqrt(n * (n * n - 1.0) * args.sigma / (rho * R ** 3))
    T0 = 2.0 * math.pi / omega0
    beta_lamb = 2.0 * n * (n - 1.0) * args.nu / (R * R)
    omega_lamb = math.sqrt(max(0.0, omega0 * omega0 - beta_lamb * beta_lamb))
    oh = args.nu * math.sqrt(rho / (args.sigma * R))

    t_start = series[0][1]
    t_end_fit = t_start + args.fit_periods * T0
    fit = [q for q in series if q[1] <= t_end_fit + 1e-12]
    if len(fit) < 20:
        fit = series[: max(20, min(len(series), 80))]
    tt = [q[1] for q in fit]
    yy = [q[2] for q in fit]
    best = fit_damped(tt, yy, omega0)
    if best is None:
        raise SystemExit("[0493x13k-analysis] damped fit failed")
    sse, omega, beta, r2, coef, pred = best
    offset = coef[2]
    omega_zc, zc_count = zero_cross_omega(tt, yy, offset)

    x_valid = [(q[1], q[7]) for q in fit if math.isfinite(q[7])]
    y_valid = [(q[1], q[8]) for q in fit if math.isfinite(q[8])]
    drift_vx = linreg_slope([q[0] for q in x_valid], [q[1] for q in x_valid]) if x_valid else math.nan
    drift_vy = linreg_slope([q[0] for q in y_valid], [q[1] for q in y_valid]) if y_valid else math.nan
    drift_speed = math.hypot(drift_vx, drift_vy) if math.isfinite(drift_vx) and math.isfinite(drift_vy) else math.nan

    # Existing ancillary diagnostics only; no new simulation instrumentation.
    pressure = read_csv(args.run_root / "output/cuda_static_drop_pressure_0493x9e.csv")
    pfit = [r for r in pressure if ff(r, "time") <= fit[-1][1] + 1e-12]
    reffs = [ff(r, "effectiveRadius") for r in pfit if math.isfinite(ff(r, "effectiveRadius"))]
    kapps = [ff(r, "curvatureMean") for r in pfit if math.isfinite(ff(r, "curvatureMean"))]
    resultants = [ff(r, "normalizedDiscreteResultant") for r in pfit if math.isfinite(ff(r, "normalizedDiscreteResultant"))]

    limiter = read_csv(args.run_root / "output/cuda_surface_tension_limiter_0493x9r.csv")
    lfit = [r for r in limiter if ff(r, "time") <= fit[-1][1] + 1e-12]
    clips = [ff(r, "clipFraction") for r in lfit if math.isfinite(ff(r, "clipFraction"))]

    velocity = read_csv(args.run_root / "output/cuda_static_drop_velocity_0493x9e.csv")
    vfit = [r for r in velocity if ff(r, "time") <= fit[-1][1] + 1e-12]
    virms = [ff(r, "interfaceSpeedRms") for r in vfit if math.isfinite(ff(r, "interfaceSpeedRms"))]

    summary = read_csv(args.run_root / "output/summary_runtime.csv")
    sfit = [r for r in summary if ff(r, "time") <= fit[-1][1] + 1e-12]
    kbts = [ff(r, "kBT") for r in sfit if math.isfinite(ff(r, "kBT"))]

    outdir = args.run_root / "analysis_0493x13k"
    outdir.mkdir(parents=True, exist_ok=True)
    trace_path = outdir / "oscillating_drop_n2_trace.csv"
    with trace_path.open("w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["step", "time", "mode2Signed", "ellipticityAbs", "principalAngleRad", "momentRadiusMajor", "momentRadiusMinor", "xCM", "yCM"])
        w.writerows(series)

    def mean(xs):
        return statistics.fmean(xs) if xs else math.nan

    def vmax(xs):
        return max(xs) if xs else math.nan

    lines = [
        "===== 0493x13k 2-D OSCILLATING DROP / n=2 =====",
        "status=MEASURED (qualification decision is intentionally external to this smoke analyzer)",
        f"rows={len(series)} fitRows={len(fit)} fitWindow=[{fit[0][1]:.9g},{fit[-1][1]:.9g}] fitPeriodsTheory={args.fit_periods:g}",
        f"R={R:.12g} R/h={args.radius_cells:g} rhoRef={rho:.12g} sigma={args.sigma:.12g} nuRef={args.nu:.12g} Oh={oh:.9g}",
        f"theory2D.inviscid omega0={omega0:.12g} period0={T0:.12g}",
        f"theory2D.Lamb beta={beta_lamb:.12g} omegaDamped={omega_lamb:.12g} periodDamped={(2*math.pi/omega_lamb if omega_lamb>0 else math.nan):.12g}",
        f"fit omega={omega:.12g} beta={beta:.12g} R2={r2:.9g} offset={offset:.9g} C={coef[0]:.9g} D={coef[1]:.9g}",
        f"gain Gomega_inviscid={omega/omega0:.9g} Gomega_Lamb={omega/omega_lamb if omega_lamb>0 else math.nan:.9g} Gbeta_Lamb={beta/beta_lamb if beta_lamb>0 else math.nan:.9g}",
        f"zeroCross omega={omega_zc:.12g} crossings={zc_count} ratioToTheory={omega_zc/omega0 if math.isfinite(omega_zc) else math.nan:.9g}",
        f"mode2 initial={series[0][2]:.9g} minFit={min(yy):.9g} maxFit={max(yy):.9g}",
        f"COM fitDriftVx={drift_vx:.9g} fitDriftVy={drift_vy:.9g} fitDriftSpeed={drift_speed:.9g}",
        f"existingDiagnostics ReffMeanFit={mean(reffs):.9g} curvatureMeanFit={mean(kapps):.9g} normalizedResultantMaxFit={vmax([abs(x) for x in resultants]):.9g}",
        f"existingDiagnostics maxClipFractionFit={vmax(clips):.9g} interfaceSpeedRmsMeanFit={mean(virms):.9g} kBTMeanFit={mean(kbts):.9g}",
        "observable=ellipticity*cos(2*principalAngle); this preserves the sign through major/minor axis exchange.",
        "interpretation=Gomega measures dynamic capillary response; do not fold it into the mechanical Young-Laplace sigma.",
    ]
    report = "\n".join(lines) + "\n"
    report_path = outdir / "oscillating_drop_n2_report.txt"
    report_path.write_text(report)
    print(report, end="")

    try:
        import matplotlib.pyplot as plt
        t0fit = fit[0][1]
        fit_t_rel = [t - t0fit for t in tt]
        fig = plt.figure()
        ax = fig.add_subplot(111)
        ax.plot([q[1] for q in series], [q[2] for q in series], label="signed n=2 moment mode")
        ax.plot(tt, pred, label=f"damped fit, Gomega={omega/omega0:.3f}")
        ax.set_xlabel("time")
        ax.set_ylabel("signed quadrupole deformation")
        ax.legend()
        fig.tight_layout()
        fig.savefig(outdir / "oscillating_drop_n2_fit.png", dpi=170)
        plt.close(fig)
    except Exception as exc:
        print(f"[0493x13k-analysis] plotting skipped: {exc}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
