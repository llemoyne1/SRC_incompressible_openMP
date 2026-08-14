#!/usr/bin/env python3
"""Four-way transverse-shear/vorticity diagnostic for 0493x7t.

Reads the existing 0493x7s cases plus the 03_q6gf_signed1 extension:

  src
  q6_legacy
  q6gf_div0
  q6gf_signed1

The main viscosity estimate is an ensemble, in-phase Fourier decay.  This avoids
the positive-amplitude (Rice) bias and remains usable when an individual seed
loses coherent SNR.  Individual-seed fits are still reported as diagnostics.

This script intentionally quantifies physical differences rather than declaring
different projection models "wrong" because they do not coincide.
"""
from __future__ import annotations

import argparse
import csv
import json
import math
import re
import struct
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Iterable

import numpy as np

MODE_DIRS = {
    "src": "00_src",
    "q6_legacy": "01_q6_legacy",
    "q6gf_div0": "02_q6gf_div0",
    "q6gf_signed1": "03_q6gf_signed1",
}
PAIRS = (
    ("src", "q6_legacy"),
    ("src", "q6gf_div0"),
    ("src", "q6gf_signed1"),
    ("q6_legacy", "q6gf_div0"),
    ("q6_legacy", "q6gf_signed1"),
    ("q6gf_div0", "q6gf_signed1"),
)


@dataclass
class Metric:
    step: int
    time: float
    fluidParticles: int
    totalMass: float
    meanUx: float
    meanUy: float
    waveSin: float
    waveCos: float
    waveAmplitude: float
    wavePhase: float
    rowResidualRms: float
    targetUyAmplitude: float
    targetVorticityAmplitude: float
    lowKEnstrophy: float
    lowKTargetEnstrophyFraction: float
    lowKVorticityLeakageFraction: float
    lowKDivergenceToVorticity: float
    emptyCells: int
    occupancyMin: int
    occupancyMax: int


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser()
    p.add_argument("--root", type=Path, required=True)
    p.add_argument("--Lx", type=float, required=True)
    p.add_argument("--Ly", type=float, required=True)
    p.add_argument("--nx", type=int, required=True)
    p.add_argument("--ny", type=int, required=True)
    p.add_argument("--gamma", type=int, required=True)
    p.add_argument("--dt", type=float, required=True)
    p.add_argument("--steps", type=int, required=True)
    p.add_argument("--dump-every", type=int, required=True)
    p.add_argument("--wave-mode", type=int, required=True)
    p.add_argument("--requested-amplitude", type=float, required=True)
    p.add_argument("--seeds", type=int, nargs="+", required=True)
    p.add_argument("--spectral-max-mode", type=int, default=4)
    p.add_argument("--fit-fraction-min", type=float, default=0.12)
    p.add_argument("--fit-min-points", type=int, default=6)
    p.add_argument("--expected-nu", type=float, default=9.422644557e-4)
    p.add_argument("--signed1-tau", type=float, default=0.25)
    p.add_argument("--q6gf-min-active-fraction", type=float, default=0.995)
    return p.parse_args()


def read_state(path: Path) -> dict[str, np.ndarray | int]:
    data = path.read_bytes()
    if data[:16].rstrip(b"\0") != b"SRCMPCD_STATE":
        raise ValueError(f"invalid state magic: {path}")
    off = 16
    fmt = "<IIIIQIIII"
    size = struct.calcsize(fmt)
    version, endian, dim, scalar, n, typeflag, massflag, reserved, roleflag = struct.unpack_from(fmt, data, off)
    off += size
    if (version, endian, dim, scalar, typeflag, massflag, roleflag) != (2, 0x01020304, 2, 1, 1, 1, 4):
        raise ValueError(f"unsupported state header: {path}")
    off += 8 * int(reserved)
    n = int(n)

    def arr(dtype: str, count: int = n) -> np.ndarray:
        nonlocal off
        dt = np.dtype(dtype)
        out = np.frombuffer(data, dtype=dt, count=count, offset=off).copy()
        off += dt.itemsize * count
        return out

    return {
        "n": n,
        "x": arr("<f8"), "y": arr("<f8"),
        "vx": arr("<f8"), "vy": arr("<f8"),
        "type": arr("<u4"), "mass": arr("<f8"), "role": arr("u1"),
    }


def signed_modes(n: int) -> np.ndarray:
    return np.fft.fftfreq(n) * n


def metric(path: Path, step: int, a: argparse.Namespace) -> Metric:
    s = read_state(path)
    role = np.asarray(s["role"])
    fluid = role == 1
    x = np.asarray(s["x"])[fluid] % a.Lx
    y = np.asarray(s["y"])[fluid] % a.Ly
    vx = np.asarray(s["vx"])[fluid]
    vy = np.asarray(s["vy"])[fluid]
    mass = np.asarray(s["mass"])[fluid]
    nfluid = int(fluid.sum())
    M = float(mass.sum())
    if nfluid == 0 or not (M > 0.0):
        raise ValueError(f"no fluid mass in {path}")
    mean_ux = float(np.sum(mass * vx) / M)
    mean_uy = float(np.sum(mass * vy) / M)

    iy = np.floor(y * a.ny / a.Ly).astype(np.int64)
    ix = np.floor(x * a.nx / a.Lx).astype(np.int64)
    np.clip(iy, 0, a.ny - 1, out=iy)
    np.clip(ix, 0, a.nx - 1, out=ix)

    row_mass = np.bincount(iy, weights=mass, minlength=a.ny)
    row_px = np.bincount(iy, weights=mass * vx, minlength=a.ny)
    row_py = np.bincount(iy, weights=mass * vy, minlength=a.ny)
    if np.any(row_mass <= 0.0):
        raise ValueError(f"empty complete y-row in {path}")
    row_ux = row_px / row_mass
    row_uy = row_py / row_mass
    yc = (np.arange(a.ny) + 0.5) * a.Ly / a.ny
    theta = 2.0 * math.pi * a.wave_mode * yc / a.Ly
    sn = np.sin(theta)
    cs = np.cos(theta)
    wave_sin = float(2.0 * np.mean((row_ux - mean_ux) * sn))
    wave_cos = float(2.0 * np.mean((row_ux - mean_ux) * cs))
    amp = math.hypot(wave_sin, wave_cos)
    phase = math.atan2(wave_cos, wave_sin)
    fit_row = mean_ux + wave_sin * sn + wave_cos * cs
    row_residual = float(np.sqrt(np.mean((row_ux - fit_row) ** 2 + (row_uy - mean_uy) ** 2)))
    uy_sin = float(2.0 * np.mean((row_uy - mean_uy) * sn))
    uy_cos = float(2.0 * np.mean((row_uy - mean_uy) * cs))
    target_uy_amp = math.hypot(uy_sin, uy_cos)

    cell = iy * a.nx + ix
    nc = a.nx * a.ny
    cell_mass = np.bincount(cell, weights=mass, minlength=nc).reshape(a.ny, a.nx)
    cell_px = np.bincount(cell, weights=mass * vx, minlength=nc).reshape(a.ny, a.nx)
    cell_py = np.bincount(cell, weights=mass * vy, minlength=nc).reshape(a.ny, a.nx)
    counts = np.bincount(cell, minlength=nc).reshape(a.ny, a.nx)
    occupied = cell_mass > 0.0
    ux = np.empty_like(cell_mass)
    uy = np.empty_like(cell_mass)
    ux[occupied] = cell_px[occupied] / cell_mass[occupied]
    uy[occupied] = cell_py[occupied] / cell_mass[occupied]
    ux[~occupied] = np.broadcast_to(row_ux[:, None], ux.shape)[~occupied]
    uy[~occupied] = np.broadcast_to(row_uy[:, None], uy.shape)[~occupied]

    uxhat = np.fft.fft2(ux) / nc
    uyhat = np.fft.fft2(uy) / nc
    mx = signed_modes(a.nx)
    my = signed_modes(a.ny)
    kx = 2.0 * math.pi * mx / a.Lx
    ky = 2.0 * math.pi * my / a.Ly
    KX, KY = np.meshgrid(kx, ky)
    MX, MY = np.meshgrid(mx, my)
    omega = 1j * (KX * uyhat - KY * uxhat)
    div = 1j * (KX * uxhat + KY * uyhat)
    low = ((np.abs(MX) <= a.spectral_max_mode) &
           (np.abs(MY) <= a.spectral_max_mode) &
           ~((MX == 0) & (MY == 0)))
    target = (MX == 0) & (np.abs(MY) == a.wave_mode)
    low_enstrophy = float(np.sum(np.abs(omega[low]) ** 2))
    target_enstrophy = float(np.sum(np.abs(omega[target]) ** 2))
    target_fraction = target_enstrophy / low_enstrophy if low_enstrophy > 0.0 else 1.0
    leakage = max(0.0, 1.0 - target_fraction)
    low_div = float(np.sum(np.abs(div[low]) ** 2))
    div_to_vort = math.sqrt(low_div / low_enstrophy) if low_enstrophy > 0.0 else 0.0
    k = 2.0 * math.pi * a.wave_mode / a.Ly

    return Metric(
        step=step, time=step * a.dt, fluidParticles=nfluid, totalMass=M,
        meanUx=mean_ux, meanUy=mean_uy, waveSin=wave_sin, waveCos=wave_cos,
        waveAmplitude=amp, wavePhase=phase, rowResidualRms=row_residual,
        targetUyAmplitude=target_uy_amp, targetVorticityAmplitude=k * amp,
        lowKEnstrophy=low_enstrophy, lowKTargetEnstrophyFraction=target_fraction,
        lowKVorticityLeakageFraction=leakage, lowKDivergenceToVorticity=div_to_vort,
        emptyCells=int(np.sum(~occupied)), occupancyMin=int(counts.min()), occupancyMax=int(counts.max()),
    )


def state_series(case: Path, a: argparse.Namespace) -> list[Metric]:
    pattern = re.compile(r"state_step_(\d+)\.smpcd$")
    out: list[Metric] = []
    for path in sorted((case / "output").glob("state_step_*.smpcd")):
        m = pattern.search(path.name)
        if m:
            out.append(metric(path, int(m.group(1)), a))
    out.sort(key=lambda m: m.step)
    expected = set(range(0, a.steps + 1, a.dump_every))
    got = {m.step for m in out}
    missing = sorted(expected - got)
    if missing:
        raise ValueError(f"missing dumps in {case}: {missing[:10]}")
    return out


def individual_fit(series: list[Metric], a: argparse.Namespace) -> dict[str, float | int]:
    z0 = complex(series[0].waveSin, series[0].waveCos)
    den = abs(z0) ** 2
    rows = []
    for m in series[1:]:
        z = complex(m.waveSin, m.waveCos)
        q = (z * z0.conjugate()).real / den
        if q >= a.fit_fraction_min:
            rows.append((m.time, q))
    if len(rows) < a.fit_min_points:
        return {"nu": float("nan"), "r2": float("nan"), "points": len(rows)}
    x = np.asarray([r[0] for r in rows])
    y = np.log(np.asarray([r[1] for r in rows]))
    slope, intercept = np.polyfit(x, y, 1)
    pred = intercept + slope * x
    ssr = float(np.sum((y - pred) ** 2))
    sst = float(np.sum((y - np.mean(y)) ** 2))
    r2 = 1.0 - ssr / sst if sst > 0 else 1.0
    k = 2.0 * math.pi * a.wave_mode / a.Ly
    nu = -float(slope) / (k * k)
    if not (math.isfinite(nu) and nu > 0):
        nu = float("nan")
    return {"nu": nu, "r2": r2, "points": len(rows)}


def ensemble_curve(series_by_seed: dict[int, list[Metric]], seeds: list[int]) -> list[dict[str, float]]:
    steps = [m.step for m in series_by_seed[seeds[0]]]
    out = []
    z0 = {s: complex(series_by_seed[s][0].waveSin, series_by_seed[s][0].waveCos) for s in seeds}
    for idx, step in enumerate(steps):
        qvals = []
        cvals = []
        leak = []
        divvort = []
        for s in seeds:
            m = series_by_seed[s][idx]
            z = complex(m.waveSin, m.waveCos)
            ratio = z / z0[s]
            qvals.append(ratio.real)
            cvals.append(ratio)
            leak.append(m.lowKVorticityLeakageFraction)
            divvort.append(m.lowKDivergenceToVorticity)
        cmean = sum(cvals) / len(cvals)
        out.append({
            "step": float(step),
            "time": series_by_seed[seeds[0]][idx].time,
            "inPhaseMean": float(np.mean(qvals)),
            "inPhaseStd": float(np.std(qvals)),
            "complexRealMean": float(cmean.real),
            "complexImagMean": float(cmean.imag),
            "complexAmplitude": float(abs(cmean)),
            "phase": float(math.atan2(cmean.imag, cmean.real)),
            "vorticityLeakageMean": float(np.mean(leak)),
            "divergenceToVorticityMean": float(np.mean(divvort)),
        })
    return out


def fit_ensemble(curve: list[dict[str, float]], a: argparse.Namespace) -> dict[str, float | int]:
    rows = [(r["time"], r["inPhaseMean"]) for r in curve[1:] if r["inPhaseMean"] >= a.fit_fraction_min]
    if len(rows) < a.fit_min_points:
        return {"nu": float("nan"), "r2": float("nan"), "points": len(rows), "timeMax": float("nan")}
    x = np.asarray([r[0] for r in rows])
    y = np.log(np.asarray([r[1] for r in rows]))
    slope, intercept = np.polyfit(x, y, 1)
    pred = intercept + slope * x
    ssr = float(np.sum((y - pred) ** 2))
    sst = float(np.sum((y - np.mean(y)) ** 2))
    r2 = 1.0 - ssr / sst if sst > 0 else 1.0
    k = 2.0 * math.pi * a.wave_mode / a.Ly
    nu = -float(slope) / (k * k)
    if not (math.isfinite(nu) and nu > 0):
        nu = float("nan")
    return {"nu": nu, "r2": r2, "points": len(rows), "timeMax": float(x[-1])}


def rel_diff(x: float, y: float) -> float:
    if not (math.isfinite(x) and math.isfinite(y)):
        return float("nan")
    return abs(x - y) / max(1e-300, 0.5 * (abs(x) + abs(y)))


def read_csv(path: Path) -> list[dict[str, str]]:
    if not path.is_file():
        return []
    with path.open(newline="") as f:
        return list(csv.DictReader(f))


def fval(row: dict[str, str], key: str, default: float = float("nan")) -> float:
    try:
        return float(row.get(key, ""))
    except Exception:
        return default


def q6gf_audit(root: Path, seed: int, mode: str, a: argparse.Namespace) -> dict[str, object]:
    rows = read_csv(root / f"seed_{seed}" / MODE_DIRS[mode] / "output" /
                    "cuda_species_q6_independent_masked_0493w5.csv")
    if not rows:
        return {"present": False}
    converged = all(int(float(r.get("converged", "0") or 0)) == 1 for r in rows)
    resident = all(int(float(r.get("residentCg0493x7j", "0") or 0)) == 1 for r in rows)
    tau_vals = [fval(r, "q6DensityRelaxationTime", float("nan")) for r in rows]
    target_vals = [abs(fval(r, "densityRelaxationTargetDivRms", 0.0)) for r in rows]
    active = [fval(r, "activeCells", 0.0) / (a.nx * a.ny) for r in rows]
    return {
        "present": True,
        "rows": len(rows),
        "converged": converged,
        "residentCg": resident,
        "tauMin": float(np.nanmin(tau_vals)),
        "tauMax": float(np.nanmax(tau_vals)),
        "targetDivRmsMean": float(np.mean(target_vals)),
        "targetDivRmsMax": float(np.max(target_vals)),
        "activeFractionMin": float(np.min(active)),
    }


def main() -> int:
    a = parse_args()
    seeds = list(a.seeds)
    all_series: dict[str, dict[int, list[Metric]]] = {m: {} for m in MODE_DIRS}
    individual_rows: list[dict[str, object]] = []
    integrity: list[dict[str, object]] = []

    for mode, dirname in MODE_DIRS.items():
        for seed in seeds:
            case = a.root / f"seed_{seed}" / dirname
            series = state_series(case, a)
            all_series[mode][seed] = series
            fit = individual_fit(series, a)
            initial = series[0]
            mass_drift = max(abs(m.totalMass - initial.totalMass) / initial.totalMass for m in series)
            individual_rows.append({
                "seed": seed, "mode": mode,
                "nuIndividual": fit["nu"], "fitR2": fit["r2"], "fitPoints": fit["points"],
                "initialAmplitude": initial.waveAmplitude,
                "finalAmplitudeRatio": series[-1].waveAmplitude / initial.waveAmplitude,
                "massDriftMaxRel": mass_drift,
                "meanUMaxAbs": max(math.hypot(m.meanUx, m.meanUy) for m in series),
                "vorticityLeakageMean": float(np.mean([m.lowKVorticityLeakageFraction for m in series])),
                "divergenceToVorticityMean": float(np.mean([m.lowKDivergenceToVorticity for m in series])),
            })

    ensemble_curves: dict[str, list[dict[str, float]]] = {}
    ensemble_fits: dict[str, dict[str, float | int]] = {}
    for mode in MODE_DIRS:
        curve = ensemble_curve(all_series[mode], seeds)
        ensemble_curves[mode] = curve
        ensemble_fits[mode] = fit_ensemble(curve, a)

    pair_rows: list[dict[str, object]] = []
    for left, right in PAIRS:
        cl = ensemble_curves[left]
        cr = ensemble_curves[right]
        if len(cl) != len(cr):
            raise ValueError(f"curve length mismatch {left}/{right}")
        rms = math.sqrt(float(np.mean([(x["inPhaseMean"] - y["inPhaseMean"]) ** 2 for x, y in zip(cl, cr)])))
        coherent = [(x, y) for x, y in zip(cl, cr) if min(x["inPhaseMean"], y["inPhaseMean"]) >= 0.20]
        phase_max = max((abs(math.atan2(math.sin(x["phase"] - y["phase"]),
                                        math.cos(x["phase"] - y["phase"]))) for x, y in coherent), default=0.0)
        leak_delta = float(np.mean([abs(x["vorticityLeakageMean"] - y["vorticityLeakageMean"])
                                    for x, y in coherent])) if coherent else float("nan")
        pair_rows.append({
            "left": left, "right": right,
            "nuRelDifferenceEnsemble": rel_diff(float(ensemble_fits[left]["nu"]),
                                                float(ensemble_fits[right]["nu"])),
            "ensembleInPhaseCurveRms": rms,
            "phaseMaxRadCoherent": phase_max,
            "vorticityLeakageMeanAbsDifference": leak_delta,
            "coherentFrames": len(coherent),
        })

    # Solver-integrity audits are hard checks; physical differences are reported,
    # not thresholded into PASS/FAIL.
    for seed in seeds:
        for mode in ("q6gf_div0", "q6gf_signed1"):
            au = q6gf_audit(a.root, seed, mode, a)
            ok = bool(au.get("present")) and bool(au.get("converged")) and bool(au.get("residentCg"))
            if ok:
                ok = float(au.get("activeFractionMin", 0.0)) >= a.q6gf_min_active_fraction
            if mode == "q6gf_div0" and ok:
                ok = abs(float(au.get("tauMax", 1.0))) <= 1e-14 and float(au.get("targetDivRmsMax", 1.0)) <= 1e-14
            if mode == "q6gf_signed1" and ok:
                ok = abs(float(au.get("tauMin", 0.0)) - a.signed1_tau) <= 1e-12
                ok = ok and abs(float(au.get("tauMax", 0.0)) - a.signed1_tau) <= 1e-12
            integrity.append({"seed": seed, "mode": mode, "status": "PASS" if ok else "FAIL", **au})

    # Persist data.
    with (a.root / "shear_vorticity_0493x7t_individual.csv").open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(individual_rows[0]))
        w.writeheader(); w.writerows(individual_rows)

    curve_rows = []
    for mode, curve in ensemble_curves.items():
        for row in curve:
            curve_rows.append({"mode": mode, **row})
    with (a.root / "shear_vorticity_0493x7t_ensemble_timeseries.csv").open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(curve_rows[0]))
        w.writeheader(); w.writerows(curve_rows)

    with (a.root / "shear_vorticity_0493x7t_pairwise.csv").open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(pair_rows[0]))
        w.writeheader(); w.writerows(pair_rows)

    with (a.root / "shear_vorticity_0493x7t_integrity.csv").open("w", newline="") as f:
        fields = sorted({k for r in integrity for k in r})
        w = csv.DictWriter(f, fieldnames=fields)
        w.writeheader(); w.writerows(integrity)

    integrity_ok = all(r["status"] == "PASS" for r in integrity)
    report = {
        "status": "COMPLETE" if integrity_ok else "INTEGRITY_FAIL",
        "parameters": {**vars(a), "root": str(a.root)},
        "ensembleFits": ensemble_fits,
        "individual": individual_rows,
        "pairwise": pair_rows,
        "integrity": integrity,
        "note": "Physical differences are diagnostic and are not thresholded into PASS/FAIL.",
    }
    (a.root / "physics_0493x7t.json").write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")

    print("===== 0493x7t FOUR-WAY TRANSVERSE SHEAR / VORTICITY =====")
    for mode in MODE_DIRS:
        ef = ensemble_fits[mode]
        vals = [float(r["nuIndividual"]) for r in individual_rows
                if r["mode"] == mode and math.isfinite(float(r["nuIndividual"]))]
        ind = f"{np.mean(vals):.9g}" if vals else "unavailable"
        print(f"{mode}: nuEnsemble={float(ef['nu']):.9g} R2={float(ef['r2']):.6g} points={int(ef['points'])} "
              f"nuIndividualMean={ind}")
    print("--- pairwise ensemble ---")
    for r in pair_rows:
        print(f"{r['left']}_vs_{r['right']}: dNuRel={float(r['nuRelDifferenceEnsemble']):.5g} "
              f"curveRms={float(r['ensembleInPhaseCurveRms']):.5g} "
              f"phaseMax={float(r['phaseMaxRadCoherent']):.5g} "
              f"vortLeakDelta={float(r['vorticityLeakageMeanAbsDifference']):.5g}")
    print("--- Q6-g-f integrity ---")
    for r in integrity:
        print(f"seed={r['seed']} {r['mode']} status={r['status']} "
              f"tau=[{r.get('tauMin','?')},{r.get('tauMax','?')}] "
              f"targetMean={r.get('targetDivRmsMean','?')} activeMin={r.get('activeFractionMin','?')}")
    print(f"status={report['status']}")
    print(f"individual={a.root/'shear_vorticity_0493x7t_individual.csv'}")
    print(f"ensemble={a.root/'shear_vorticity_0493x7t_ensemble_timeseries.csv'}")
    print(f"pairwise={a.root/'shear_vorticity_0493x7t_pairwise.csv'}")
    print(f"report={a.root/'physics_0493x7t.json'}")
    return 0 if integrity_ok else 2


if __name__ == "__main__":
    raise SystemExit(main())
