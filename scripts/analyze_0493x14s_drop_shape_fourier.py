#!/usr/bin/env python3
"""
Offline shape/Fourier analysis of x14s liquid/gas static-drop states.

No solver/CUDA changes. Standard library only.

For each requested run:
  * read state_step_<step>.smpcd;
  * reconstruct the native-grid Q6 alpha field used by x6f/x6g:
        raw = liquid cell mass / liquidReferenceCellMass
        bounded = clamp(raw,0,1)
        alpha = bounded + 0.125 * 5-point Laplacian(bounded)
  * estimate the alpha=0.5 contour radius along uniformly spaced rays;
  * iteratively shift the shape center to suppress the geometric m=1 mode;
  * measure Fourier modes of R(theta), especially m=2,3,4;
  * write one profile CSV per run plus consolidated summaries.

The important ensemble diagnostic for grid locking is not only <A4/R>, but
also the coherent m=4 vector:
    C4 = <a4_cos/R> + i <a4_sin/R>
If all seeds facet in the same grid orientation, |C4|/<A4/R> approaches 1.
If the residual m=4 has random phase, this coherence ratio is small.
"""
from __future__ import annotations

import argparse
import csv
import math
import re
import struct
import sys
from array import array
from pathlib import Path

MAGIC = b"SRCMPCD_STATE" + b"\0" * (16 - len(b"SRCMPCD_STATE"))
FLUID_ROLE = 1
LAMBDA_Q6 = 0.125


def clamp01(v: float) -> float:
    return 0.0 if v < 0.0 else (1.0 if v > 1.0 else v)


def parse_kv(path: Path) -> dict[str, str]:
    d = {}
    for raw in path.read_text(errors="replace").splitlines():
        s = raw.strip()
        if not s or s.startswith("#") or "=" not in s:
            continue
        k, v = s.split("=", 1)
        d[k.strip()] = v.strip()
    return d


def num_from(d, names, default=None):
    for n in names:
        if n in d:
            try:
                return float(d[n].split()[0])
            except Exception:
                pass
    if default is not None:
        return default
    raise KeyError("/".join(names))


def find_params(run: Path) -> Path:
    q = sorted((run / "params").glob("*.kv")) if (run / "params").is_dir() else []
    if q:
        return q[0]
    for p in (run / "output" / "params_used.kv", run / "params_used.kv"):
        if p.is_file():
            return p
    raise RuntimeError(f"no params file under {run}")


def read_array(f, code: str, n: int):
    a = array(code)
    a.fromfile(f, n)
    if len(a) != n:
        raise RuntimeError("truncated state array")
    if sys.byteorder == "big":
        a.byteswap()
    return a


def read_state(path: Path):
    with path.open("rb") as f:
        if f.read(16) != MAGIC:
            raise RuntimeError(f"{path}: bad magic")
        hs = struct.calcsize("<IIIIQIIII")
        h = f.read(hs)
        if len(h) != hs:
            raise RuntimeError(f"{path}: truncated header")
        version, endian, dim, layout, n, has_type, has_mass, real_size, type_size = struct.unpack(
            "<IIIIQIIII", h
        )
        reserved_raw = f.read(8 * 8)
        if len(reserved_raw) != 64:
            raise RuntimeError(f"{path}: truncated reserved header")
        reserved = struct.unpack("<8Q", reserved_raw)
        if version not in (1, 2) or endian != 0x01020304 or dim != 2 or layout != 1:
            raise RuntimeError(f"{path}: unsupported state header")
        if has_type != 1 or has_mass != 1 or real_size != 8 or type_size != 4:
            raise RuntimeError(f"{path}: unsupported scalar layout")
        n = int(n)
        x = read_array(f, "d", n)
        y = read_array(f, "d", n)
        # Skip vx, vy.
        f.seek(16 * n, 1)
        typ = read_array(f, "I", n)
        mass = read_array(f, "d", n)
        if version == 2:
            role = bytearray(f.read(n))
            if len(role) != n:
                raise RuntimeError(f"{path}: truncated V2 role payload")
        else:
            role = bytearray([FLUID_ROLE]) * n
    return x, y, typ, mass, role


def find_state(run: Path, step: int) -> Path:
    exact = run / "output" / f"state_step_{step:08d}.smpcd"
    if exact.is_file():
        return exact
    candidates = []
    for p in (run / "output").glob("state_step_*.smpcd"):
        m = re.search(r"state_step_(\d+)\.smpcd$", p.name)
        if m and int(m.group(1)) == step:
            candidates.append(p)
    if len(candidates) == 1:
        return candidates[0]
    if not candidates:
        raise RuntimeError(f"{run}: no state dump for step {step}")
    raise RuntimeError(f"{run}: ambiguous state dump for step {step}: {candidates}")


def pressure_reference_mass(run: Path):
    p = run / "output" / "cuda_phase_interface_pressure_0493x6g.csv"
    if not p.is_file():
        return None
    with p.open(newline="") as f:
        rd = csv.DictReader(f)
        row = next(rd, None)
    if not row:
        return None
    try:
        return float(row["liquidReferenceCellMass"])
    except Exception:
        return None


def cell_index(x, y, nx, ny, lx, ly):
    x = min(max(x, 0.0), math.nextafter(lx, 0.0))
    y = min(max(y, 0.0), math.nextafter(ly, 0.0))
    ix = max(0, min(nx - 1, int(x * nx / lx)))
    iy = max(0, min(ny - 1, int(y * ny / ly)))
    return iy * nx + ix


def build_q6_alpha(x, y, typ, mass, role, liquid_type,
                   nx, ny, lx, ly, liquid_ref):
    ncell = nx * ny
    lm = array("d", [0.0]) * ncell
    msum = sx = sy = 0.0
    nliq = 0
    for i in range(len(x)):
        if role[i] != FLUID_ROLE or typ[i] != liquid_type:
            continue
        mi = mass[i]
        c = cell_index(x[i], y[i], nx, ny, lx, ly)
        lm[c] += mi
        msum += mi
        sx += mi * x[i]
        sy += mi * y[i]
        nliq += 1
    if msum <= 0.0:
        raise RuntimeError("no liquid mass found")
    comx, comy = sx / msum, sy / msum

    bounded = array("d", (clamp01(v / liquid_ref) for v in lm))
    alpha = array("d", [0.0]) * ncell
    for iy in range(ny):
        row = iy * nx
        for ix in range(nx):
            c = row + ix
            vc = bounded[c]
            lap = 0.0
            if ix > 0:
                lap += bounded[c - 1] - vc
            if ix + 1 < nx:
                lap += bounded[c + 1] - vc
            if iy > 0:
                lap += bounded[c - nx] - vc
            if iy + 1 < ny:
                lap += bounded[c + nx] - vc
            alpha[c] = vc + LAMBDA_Q6 * lap
    return alpha, comx, comy, msum, nliq


def alpha_bilinear(alpha, x, y, nx, ny, lx, ly):
    dx = lx / nx
    dy = ly / ny
    # Alpha lives on cell centers.
    qx = x / dx - 0.5
    qy = y / dy - 0.5
    ix0 = math.floor(qx)
    iy0 = math.floor(qy)
    fx = qx - ix0
    fy = qy - iy0
    ix0 = int(ix0); iy0 = int(iy0)
    ix1 = ix0 + 1; iy1 = iy0 + 1
    ix0 = max(0, min(nx - 1, ix0)); ix1 = max(0, min(nx - 1, ix1))
    iy0 = max(0, min(ny - 1, iy0)); iy1 = max(0, min(ny - 1, iy1))
    v00 = alpha[iy0 * nx + ix0]
    v10 = alpha[iy0 * nx + ix1]
    v01 = alpha[iy1 * nx + ix0]
    v11 = alpha[iy1 * nx + ix1]
    return (
        (1.0 - fx) * (1.0 - fy) * v00
        + fx * (1.0 - fy) * v10
        + (1.0 - fx) * fy * v01
        + fx * fy * v11
    )


def equivalent_radius(alpha, nx, ny, lx, ly):
    area = sum(clamp01(v) for v in alpha) * (lx / nx) * (ly / ny)
    return math.sqrt(max(0.0, area) / math.pi)


def extract_radii(alpha, cx, cy, req, nx, ny, lx, ly, nangles, samples_per_h):
    h = min(lx / nx, ly / ny)
    dr = h / samples_per_h
    rlo = max(0.0, 0.45 * req)
    rhi = min(1.75 * req, cx, lx - cx, cy, ly - cy)
    if rhi <= rlo:
        raise RuntimeError("invalid radial search interval")

    radii = []
    for j in range(nangles):
        th = 2.0 * math.pi * j / nangles
        ct, st = math.cos(th), math.sin(th)
        prev_r = rlo
        prev_a = alpha_bilinear(alpha, cx + prev_r * ct, cy + prev_r * st,
                                nx, ny, lx, ly)
        crossings = []
        r = rlo + dr
        while r <= rhi + 0.5 * dr:
            a = alpha_bilinear(alpha, cx + r * ct, cy + r * st,
                               nx, ny, lx, ly)
            if prev_a >= 0.5 and a < 0.5:
                # Linear seed then bisection on the bilinear field.
                lo, hi = prev_r, r
                for _ in range(16):
                    mid = 0.5 * (lo + hi)
                    am = alpha_bilinear(alpha, cx + mid * ct, cy + mid * st,
                                        nx, ny, lx, ly)
                    if am >= 0.5:
                        lo = mid
                    else:
                        hi = mid
                crossings.append(0.5 * (lo + hi))
            prev_r, prev_a = r, a
            r += dr
        if not crossings:
            raise RuntimeError(f"no alpha=0.5 crossing at angle index {j}")
        # Choose the crossing closest to the area-equivalent radius. This is
        # robust to isolated noisy internal crossings while preserving the main drop.
        radii.append(min(crossings, key=lambda q: abs(q - req)))
    return radii


def fourier_uniform(radii, max_mode):
    n = len(radii)
    a0 = sum(radii) / n
    modes = {}
    for m in range(1, max_mode + 1):
        ac = 0.0
        ass = 0.0
        for j, r in enumerate(radii):
            th = 2.0 * math.pi * j / n
            ac += r * math.cos(m * th)
            ass += r * math.sin(m * th)
        ac *= 2.0 / n
        ass *= 2.0 / n
        amp = math.hypot(ac, ass)
        orient = math.degrees(math.atan2(ass, ac) / m)
        period = 360.0 / m
        half = 0.5 * period
        while orient >= half:
            orient -= period
        while orient < -half:
            orient += period
        modes[m] = (ac, ass, amp, orient)
    return a0, modes


def recentered_shape(alpha, initial_cx, initial_cy, req,
                     nx, ny, lx, ly, nangles, samples_per_h, max_mode, iterations):
    cx, cy = initial_cx, initial_cy
    radii = None
    for _ in range(iterations):
        radii = extract_radii(alpha, cx, cy, req, nx, ny, lx, ly,
                              nangles, samples_per_h)
        _, modes = fourier_uniform(radii, max_mode)
        # For a circle whose true center is displaced by d relative to the
        # current origin, r(theta) = R + dx cos(theta) + dy sin(theta) + O(d^2).
        dx = modes[1][0]
        dy = modes[1][1]
        cx += dx
        cy += dy
        if math.hypot(dx, dy) < 1.0e-5 * (lx / nx):
            break
    radii = extract_radii(alpha, cx, cy, req, nx, ny, lx, ly,
                          nangles, samples_per_h)
    a0, modes = fourier_uniform(radii, max_mode)
    return cx, cy, radii, a0, modes


def residual_metrics(radii, a0, modes, keep_to):
    n = len(radii)
    residual = []
    for j, r in enumerate(radii):
        th = 2.0 * math.pi * j / n
        fit = a0
        for m in range(1, keep_to + 1):
            ac, ass, _, _ = modes[m]
            fit += ac * math.cos(m * th) + ass * math.sin(m * th)
        residual.append(r - fit)
    rms = math.sqrt(sum(v * v for v in residual) / n)
    return rms, max(radii) - min(radii), residual


def seed_from_run(run: Path):
    m = re.search(r"seed(\d+)", run.name)
    return int(m.group(1)) if m else -1


def mean(v):
    return sum(v) / len(v) if v else math.nan


def std(v):
    if not v:
        return math.nan
    m = mean(v)
    return math.sqrt(sum((x - m) ** 2 for x in v) / len(v))


def write_csv(path, rows):
    if not rows:
        return
    with path.open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        w.writeheader()
        w.writerows(rows)


def analyze_run(run: Path, args, profile_dir: Path):
    params = parse_kv(find_params(run))
    nx = int(round(num_from(params, ("Nx", "NX"))))
    ny = int(round(num_from(params, ("Ny", "NY"))))
    lx = num_from(params, ("Lx", "LX"))
    ly = num_from(params, ("Ly", "LY"))
    liquid_ref = pressure_reference_mass(run)
    if liquid_ref is None:
        gamma = num_from(params, ("gamma", "GAMMA"))
        liquid_mass = num_from(params, ("mass", "MASS"), 1.0)
        liquid_ref = gamma * liquid_mass

    state = find_state(run, args.step)
    print(f"[x14s-shape] reading {state}", flush=True)
    x, y, typ, mass, role = read_state(state)
    alpha, comx, comy, liquid_mass_total, nliq = build_q6_alpha(
        x, y, typ, mass, role, args.liquid_type,
        nx, ny, lx, ly, liquid_ref
    )
    req = equivalent_radius(alpha, nx, ny, lx, ly)
    cx, cy, radii, rmean, modes = recentered_shape(
        alpha, comx, comy, req, nx, ny, lx, ly,
        args.angles, args.samples_per_h, args.max_mode, args.recenter_iterations
    )
    rms, p2p, residual = residual_metrics(radii, rmean, modes, args.fit_modes_to)
    h = min(lx / nx, ly / ny)
    seed = seed_from_run(run)

    row = {
        "seed": seed,
        "step": args.step,
        "run": str(run),
        "liquidParticles": nliq,
        "liquidMass": liquid_mass_total,
        "liquidCOMx": comx,
        "liquidCOMy": comy,
        "shapeCenterX": cx,
        "shapeCenterY": cy,
        "shapeCenterMinusCOM_h": math.hypot(cx - comx, cy - comy) / h,
        "Req_h": req / h,
        "Rmean_h": rmean / h,
        "shapeP2P_h": p2p / h,
        "shapeP2P_over_R": p2p / rmean,
        "residualRms_h": rms / h,
        "residualRms_over_R": rms / rmean,
    }
    for m in range(1, args.max_mode + 1):
        ac, ass, amp, orient = modes[m]
        row[f"a{m}cos_over_R"] = ac / rmean
        row[f"a{m}sin_over_R"] = ass / rmean
        row[f"A{m}_over_R"] = amp / rmean
        row[f"orientation{m}_deg"] = orient

    profile_dir.mkdir(parents=True, exist_ok=True)
    pname = profile_dir / f"shape_profile_seed{seed if seed >= 0 else run.name}_step{args.step}.csv"
    with pname.open("w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["thetaRad", "thetaDeg", "radius_h", "radiusMinusMean_h", "residualAfterModes_h"])
        for j, (r, res) in enumerate(zip(radii, residual)):
            th = 2.0 * math.pi * j / len(radii)
            w.writerow([th, math.degrees(th), r / h, (r - rmean) / h, res / h])

    print(
        f"[x14s-shape] seed={seed} R/h={rmean/h:.5f} "
        f"P2P/h={p2p/h:.4f} A2/R={row['A2_over_R']:.5e} "
        f"A3/R={row['A3_over_R']:.5e} A4/R={row['A4_over_R']:.5e} "
        f"phi4={row['orientation4_deg']:.2f}deg "
        f"center-COM/h={row['shapeCenterMinusCOM_h']:.4f}",
        flush=True
    )
    return row


def ensemble_rows(rows, max_mode):
    out = [{
        "metric": "Rmean_h",
        "mean": mean([r["Rmean_h"] for r in rows]),
        "std": std([r["Rmean_h"] for r in rows]),
        "coherentAmplitude": "",
        "coherenceRatio": "",
        "orientationDeg": "",
    }, {
        "metric": "shapeP2P_h",
        "mean": mean([r["shapeP2P_h"] for r in rows]),
        "std": std([r["shapeP2P_h"] for r in rows]),
        "coherentAmplitude": "",
        "coherenceRatio": "",
        "orientationDeg": "",
    }, {
        "metric": "residualRms_h",
        "mean": mean([r["residualRms_h"] for r in rows]),
        "std": std([r["residualRms_h"] for r in rows]),
        "coherentAmplitude": "",
        "coherenceRatio": "",
        "orientationDeg": "",
    }]
    for m in range(1, max_mode + 1):
        amps = [r[f"A{m}_over_R"] for r in rows]
        mc = mean([r[f"a{m}cos_over_R"] for r in rows])
        ms = mean([r[f"a{m}sin_over_R"] for r in rows])
        coherent = math.hypot(mc, ms)
        ma = mean(amps)
        orient = math.degrees(math.atan2(ms, mc) / m) if coherent > 0 else math.nan
        period = 360.0 / m
        half = period / 2.0
        while orient >= half:
            orient -= period
        while orient < -half:
            orient += period
        out.append({
            "metric": f"A{m}_over_R",
            "mean": ma,
            "std": std(amps),
            "coherentAmplitude": coherent,
            "coherenceRatio": coherent / ma if ma > 0 else math.nan,
            "orientationDeg": orient,
        })
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--run", action="append", type=Path, required=True,
                    help="run root; repeat for several seeds")
    ap.add_argument("--step", type=int, default=1000)
    ap.add_argument("--liquid-type", type=int, default=1)
    ap.add_argument("--angles", type=int, default=720)
    ap.add_argument("--samples-per-h", type=float, default=8.0)
    ap.add_argument("--max-mode", type=int, default=8)
    ap.add_argument("--fit-modes-to", type=int, default=8,
                    help="modes removed before residual RMS")
    ap.add_argument("--recenter-iterations", type=int, default=4)
    ap.add_argument("--outdir", type=Path, required=True)
    args = ap.parse_args()

    if args.angles < 72:
        raise SystemExit("--angles must be >=72")
    if args.max_mode < 4:
        raise SystemExit("--max-mode must be >=4")
    if args.fit_modes_to > args.max_mode:
        raise SystemExit("--fit-modes-to cannot exceed --max-mode")

    args.outdir.mkdir(parents=True, exist_ok=True)
    profiles = args.outdir / "profiles"
    rows = [analyze_run(r.resolve(), args, profiles) for r in args.run]
    rows.sort(key=lambda r: (r["seed"], r["run"]))
    ens = ensemble_rows(rows, args.max_mode)

    summary_path = args.outdir / f"shape_fourier_multiseed_step{args.step}.csv"
    ensemble_path = args.outdir / f"shape_fourier_ensemble_step{args.step}.csv"
    write_csv(summary_path, rows)
    write_csv(ensemble_path, ens)

    print("\n===== x14s SHAPE FOURIER ENSEMBLE =====")
    print(f"runs={len(rows)} step={args.step} angles={args.angles}")
    print(f"Rmean/h={mean([r['Rmean_h'] for r in rows]):.5f} +/- {std([r['Rmean_h'] for r in rows]):.5f}")
    print(f"P2P/h={mean([r['shapeP2P_h'] for r in rows]):.5f} +/- {std([r['shapeP2P_h'] for r in rows]):.5f}")
    for m in (2, 3, 4):
        e = next(q for q in ens if q["metric"] == f"A{m}_over_R")
        print(
            f"m={m}: <A/R>={e['mean']:.6e} +/- {e['std']:.6e} "
            f"coherent={e['coherentAmplitude']:.6e} "
            f"coherence={e['coherenceRatio']:.3f} "
            f"orientation={e['orientationDeg']:.2f}deg"
        )
    print("\nInterpretation:")
    print("  * A4/R measures residual four-lobed deformation per seed.")
    print("  * coherent A4/R and coherence ratio test whether that m=4 is locked to the Cartesian grid.")
    print("  * coherence~1 = common orientation across seeds; coherence<<1 = random-phase residual.")
    print(f"\nsummary={summary_path}")
    print(f"ensemble={ensemble_path}")
    print(f"profiles={profiles}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
