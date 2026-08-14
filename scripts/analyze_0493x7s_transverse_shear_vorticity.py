#!/usr/bin/env python3
"""Analyze the 0493x7s transverse shear-wave vorticity qualification.

The comparison is intentionally paired:
  src            : unprojected SRC reference
  q6_legacy      : historical Q6 projection
  q6gf_div0      : Q6-g-f/x7j with density-restoration RHS disabled

The coherent observable is the k=(0,m) transverse velocity Fourier mode.  A
low-k 2-D spectral decomposition additionally measures vorticity leakage into
non-target modes and longitudinal/divergence contamination without spatial
filtering of the particle field.
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

import numpy as np

MODE_DIRS = {
    "src": "00_src",
    "q6_legacy": "01_q6_legacy",
    "q6gf_div0": "02_q6gf_div0",
}
PAIRWISE = (
    ("src", "q6_legacy"),
    ("q6_legacy", "q6gf_div0"),
    ("src", "q6gf_div0"),
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
    p.add_argument("--fit-r2-min", type=float, default=0.95)
    p.add_argument("--fit-amplitude-fraction-min", type=float, default=0.15)
    p.add_argument("--expected-nu", type=float, default=9.422644557e-4)
    p.add_argument("--expected-nu-rel-tol", type=float, default=0.18)
    p.add_argument("--pair-nu-rel-tol", type=float, default=0.10)
    p.add_argument("--pair-curve-rms-tol", type=float, default=0.06)
    p.add_argument("--pair-phase-rad-tol", type=float, default=0.15)
    p.add_argument("--pair-vorticity-leakage-tol", type=float, default=0.15)
    p.add_argument("--mean-u-abs-tol", type=float, default=1.0e-8)
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
    role = s["role"]  # type: ignore[assignment]
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
    # Empty cells are rare at gamma=6. Fill them with the same-row barycentric
    # velocity so an occupancy hole does not manufacture an x-dependent vortex.
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
    omega_amp = k * amp

    return Metric(
        step=step, time=step * a.dt, fluidParticles=nfluid, totalMass=M,
        meanUx=mean_ux, meanUy=mean_uy, waveSin=wave_sin, waveCos=wave_cos,
        waveAmplitude=amp, wavePhase=phase, rowResidualRms=row_residual,
        targetUyAmplitude=target_uy_amp, targetVorticityAmplitude=omega_amp,
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


def fit_decay(series: list[Metric], a: argparse.Namespace) -> dict[str, float | int]:
    A0 = series[0].waveAmplitude
    floor = a.fit_amplitude_fraction_min * A0
    usable = [m for m in series if m.step >= a.dump_every and m.waveAmplitude >= floor]
    if len(usable) < 6:
        return {"nu": float("nan"), "slope": float("nan"), "r2": float("nan"), "points": len(usable)}
    x = np.asarray([m.time for m in usable], dtype=float)
    y = np.log(np.asarray([m.waveAmplitude / A0 for m in usable], dtype=float))
    slope, intercept = np.polyfit(x, y, 1)
    pred = intercept + slope * x
    ssr = float(np.sum((y - pred) ** 2))
    sst = float(np.sum((y - np.mean(y)) ** 2))
    r2 = 1.0 - ssr / sst if sst > 0.0 else 1.0
    k = 2.0 * math.pi * a.wave_mode / a.Ly
    return {"nu": float(-slope / (k * k)), "slope": float(slope), "r2": r2,
            "points": len(usable), "fitTimeMax": float(x[-1])}


def relative_difference(a: float, b: float) -> float:
    return abs(a - b) / max(1.0e-300, 0.5 * (abs(a) + abs(b)))


def wrapped_phase_delta(a: float, b: float) -> float:
    return abs(math.atan2(math.sin(a - b), math.cos(a - b)))


def read_csv(path: Path) -> list[dict[str, str]]:
    if not path.is_file():
        return []
    with path.open(newline="") as f:
        return list(csv.DictReader(f))


def finite_float(row: dict[str, str], key: str, default: float = float("nan")) -> float:
    try:
        return float(row.get(key, ""))
    except Exception:
        return default


def main() -> int:
    a = parse_args()
    checks: list[dict[str, str]] = []
    summaries: list[dict[str, float | int | str]] = []
    pair_rows: list[dict[str, float | int | str]] = []
    series_all: dict[int, dict[str, list[Metric]]] = {}
    fits_all: dict[int, dict[str, dict[str, float | int]]] = {}

    def check(name: str, ok: bool, detail: str) -> None:
        status = "PASS" if ok else "FAIL"
        checks.append({"check": name, "status": status, "detail": detail})
        print(f"[0493x7s-audit] {name}={status} {detail}")

    for seed in a.seeds:
        series_all[seed] = {}
        fits_all[seed] = {}
        for mode, dirname in MODE_DIRS.items():
            case = a.root / f"seed_{seed}" / dirname
            series = state_series(case, a)
            fit = fit_decay(series, a)
            series_all[seed][mode] = series
            fits_all[seed][mode] = fit
            initial = series[0]
            mass_drift = max(abs(m.totalMass - initial.totalMass) / initial.totalMass for m in series)
            count_ok = all(m.fluidParticles == initial.fluidParticles for m in series)
            mean_u_max = max(math.hypot(m.meanUx, m.meanUy) for m in series)
            coherent = [m for m in series if m.waveAmplitude >= 0.25 * initial.waveAmplitude]
            leak_mean = float(np.mean([m.lowKVorticityLeakageFraction for m in coherent])) if coherent else float("nan")
            div_mean = float(np.mean([m.lowKDivergenceToVorticity for m in coherent])) if coherent else float("nan")
            uy_rel_mean = float(np.mean([m.targetUyAmplitude / max(m.waveAmplitude, 1e-300) for m in coherent])) if coherent else float("nan")
            nu = float(fit["nu"])
            r2 = float(fit["r2"])
            summaries.append({
                "seed": seed, "mode": mode, "initialAmplitude": initial.waveAmplitude,
                "finalAmplitude": series[-1].waveAmplitude,
                "finalAmplitudeRatio": series[-1].waveAmplitude / initial.waveAmplitude,
                "nuEff": nu, "fitR2": r2, "fitPoints": int(fit["points"]),
                "fitTimeMax": float(fit.get("fitTimeMax", float("nan"))),
                "massDriftMaxRel": mass_drift, "meanUMaxAbs": mean_u_max,
                "vorticityLeakageMeanCoherent": leak_mean,
                "divergenceToVorticityMeanCoherent": div_mean,
                "targetUyOverUxMeanCoherent": uy_rel_mean,
                "emptyCellsMax": max(m.emptyCells for m in series),
            })
            check(f"seed{seed}_{mode}_initial_amplitude",
                  abs(initial.waveAmplitude - a.requested_amplitude) <= 0.015 * a.requested_amplitude,
                  f"measured={initial.waveAmplitude:.8g} requested={a.requested_amplitude:.8g}")
            check(f"seed{seed}_{mode}_particle_count", count_ok,
                  f"initial={initial.fluidParticles} final={series[-1].fluidParticles}")
            check(f"seed{seed}_{mode}_mass", mass_drift <= 2.0e-12, f"maxRel={mass_drift:.3e}")
            check(f"seed{seed}_{mode}_mean_velocity", mean_u_max <= a.mean_u_abs_tol, f"maxAbs={mean_u_max:.3e}")
            check(f"seed{seed}_{mode}_fit", math.isfinite(nu) and nu > 0.0 and math.isfinite(r2) and r2 >= a.fit_r2_min,
                  f"nu={nu:.9g} R2={r2:.7g} points={fit['points']}")
            expected_rel = relative_difference(nu, a.expected_nu)
            check(f"seed{seed}_{mode}_expected_nu", expected_rel <= a.expected_nu_rel_tol,
                  f"rel={expected_rel:.5g} measured={nu:.9g} expected={a.expected_nu:.9g}")

        for left, right in PAIRWISE:
            sl = series_all[seed][left]
            sr = series_all[seed][right]
            fl = fits_all[seed][left]
            fr = fits_all[seed][right]
            by_l = {m.step: m for m in sl}
            by_r = {m.step: m for m in sr}
            common = sorted(set(by_l) & set(by_r))
            A0 = 0.5 * (sl[0].waveAmplitude + sr[0].waveAmplitude)
            coherent_steps = [s for s in common if min(by_l[s].waveAmplitude, by_r[s].waveAmplitude) >= 0.25 * A0]
            curve_rms = math.sqrt(sum(((by_l[s].waveAmplitude - by_r[s].waveAmplitude) / A0) ** 2 for s in common) / len(common))
            phase_max = max((wrapped_phase_delta(by_l[s].wavePhase, by_r[s].wavePhase) for s in coherent_steps), default=0.0)
            leak_delta = float(np.mean([abs(by_l[s].lowKVorticityLeakageFraction - by_r[s].lowKVorticityLeakageFraction) for s in coherent_steps])) if coherent_steps else float("nan")
            nu_rel = relative_difference(float(fl["nu"]), float(fr["nu"]))
            pair_rows.append({"seed": seed, "left": left, "right": right, "nuRelDifference": nu_rel,
                              "curveRmsOverA0": curve_rms, "phaseMaxRadCoherent": phase_max,
                              "vorticityLeakageMeanAbsDifference": leak_delta, "coherentFrames": len(coherent_steps)})
            check(f"seed{seed}_{left}_vs_{right}_nu", nu_rel <= a.pair_nu_rel_tol,
                  f"rel={nu_rel:.5g} {left}={float(fl['nu']):.9g} {right}={float(fr['nu']):.9g}")
            check(f"seed{seed}_{left}_vs_{right}_curve", curve_rms <= a.pair_curve_rms_tol,
                  f"rms/A0={curve_rms:.5g}")
            check(f"seed{seed}_{left}_vs_{right}_phase", phase_max <= a.pair_phase_rad_tol,
                  f"maxRad={phase_max:.5g} coherentFrames={len(coherent_steps)}")
            check(f"seed{seed}_{left}_vs_{right}_vorticity_leakage", math.isfinite(leak_delta) and leak_delta <= a.pair_vorticity_leakage_tol,
                  f"meanAbsDelta={leak_delta:.5g}")

        q6gf_out = a.root / f"seed_{seed}" / MODE_DIRS["q6gf_div0"] / "output"
        q6rows = read_csv(q6gf_out / "cuda_species_q6_independent_masked_0493w5.csv")
        if q6rows:
            converged = all(int(float(r.get("converged", "0") or 0)) == 1 for r in q6rows)
            resident = all(int(float(r.get("residentCg0493x7j", "0") or 0)) == 1 for r in q6rows)
            target_max = max(abs(finite_float(r, "densityRelaxationTargetDivRms", 0.0)) for r in q6rows)
            tau_max = max(abs(finite_float(r, "q6DensityRelaxationTime", 0.0)) for r in q6rows)
            active_fraction_min = min(finite_float(r, "activeCells", 0.0) / (a.nx * a.ny) for r in q6rows)
            check(f"seed{seed}_q6gf_div0_solver", converged and resident,
                  f"rows={len(q6rows)} converged={int(converged)} residentCg={int(resident)}")
            check(f"seed{seed}_q6gf_div0_density_rhs_zero", target_max <= 1.0e-14 and tau_max <= 1.0e-14,
                  f"targetDivMax={target_max:.3e} tauMax={tau_max:.3e}")
            check(f"seed{seed}_q6gf_support_nearly_full", active_fraction_min >= a.q6gf_min_active_fraction,
                  f"minActiveFraction={active_fraction_min:.7g}")
        else:
            check(f"seed{seed}_q6gf_audit_present", False,
                  "missing cuda_species_q6_independent_masked_0493w5.csv")

    # Ensemble means across seeds.
    ensemble: dict[str, dict[str, float]] = {}
    for mode in MODE_DIRS:
        vals = [float(fits_all[s][mode]["nu"]) for s in a.seeds]
        ensemble[mode] = {"nuMean": float(np.mean(vals)), "nuStd": float(np.std(vals))}
    for left, right in PAIRWISE:
        rel = relative_difference(ensemble[left]["nuMean"], ensemble[right]["nuMean"])
        check(f"ensemble_{left}_vs_{right}_nu", rel <= a.pair_nu_rel_tol,
              f"rel={rel:.5g} {left}={ensemble[left]['nuMean']:.9g} {right}={ensemble[right]['nuMean']:.9g}")

    with (a.root / "shear_vorticity_0493x7s_timeseries.csv").open("w", newline="") as f:
        fields = ["seed", "mode"] + list(Metric.__dataclass_fields__)
        w = csv.DictWriter(f, fieldnames=fields)
        w.writeheader()
        for seed in a.seeds:
            for mode in MODE_DIRS:
                for m in series_all[seed][mode]:
                    w.writerow({"seed": seed, "mode": mode, **asdict(m)})
    with (a.root / "shear_vorticity_0493x7s_summary.csv").open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(summaries[0]))
        w.writeheader(); w.writerows(summaries)
    with (a.root / "shear_vorticity_0493x7s_pairwise.csv").open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(pair_rows[0]))
        w.writeheader(); w.writerows(pair_rows)
    with (a.root / "physics_0493x7s_checks.csv").open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=("check", "status", "detail"))
        w.writeheader(); w.writerows(checks)

    status = "PASS" if all(c["status"] == "PASS" for c in checks) else "FAIL"
    report = {
        "status": status,
        "parameters": {**vars(a), "root": str(a.root)},
        "ensemble": ensemble,
        "summaries": summaries,
        "pairwise": pair_rows,
        "failedChecks": [c["check"] for c in checks if c["status"] != "PASS"],
    }
    (a.root / "physics_0493x7s.json").write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")

    md = [
        "# 0493x7s transverse shear / vorticity qualification", "",
        f"**Status: {status}**", "",
        "| mode | mean nu_eff | seed std |", "|---|---:|---:|",
    ]
    for mode in MODE_DIRS:
        md.append(f"| {mode} | {ensemble[mode]['nuMean']:.9g} | {ensemble[mode]['nuStd']:.3g} |")
    md += ["", "## Pairwise", "", "| seed | left | right | dnu/nu | curve RMS/A0 | max phase | vorticity leakage d |",
           "|---:|---|---|---:|---:|---:|---:|"]
    for r in pair_rows:
        md.append(f"| {r['seed']} | {r['left']} | {r['right']} | {r['nuRelDifference']:.5g} | {r['curveRmsOverA0']:.5g} | {r['phaseMaxRadCoherent']:.5g} | {r['vorticityLeakageMeanAbsDifference']:.5g} |")
    if report["failedChecks"]:
        md += ["", "## Failed checks", ""] + [f"- `{x}`" for x in report["failedChecks"]]
    (a.root / "physics_0493x7s.md").write_text("\n".join(md) + "\n")

    print("===== 0493x7s TRANSVERSE SHEAR / VORTICITY =====")
    for mode in MODE_DIRS:
        print(f"{mode}: nuMean={ensemble[mode]['nuMean']:.9g} nuStd={ensemble[mode]['nuStd']:.3g}")
    for r in pair_rows:
        if r["left"] == "q6_legacy" and r["right"] == "q6gf_div0":
            print(f"seed={r['seed']} q6_vs_q6gf_div0 dNuRel={r['nuRelDifference']:.5g} "
                  f"curveRms/A0={r['curveRmsOverA0']:.5g} phaseMax={r['phaseMaxRadCoherent']:.5g} "
                  f"vortLeakDelta={r['vorticityLeakageMeanAbsDifference']:.5g}")
    print(f"status={status}")
    print(f"summary={a.root/'shear_vorticity_0493x7s_summary.csv'}")
    print(f"pairwise={a.root/'shear_vorticity_0493x7s_pairwise.csv'}")
    print(f"report={a.root/'physics_0493x7s.json'}")
    return 0 if status == "PASS" else 2


if __name__ == "__main__":
    raise SystemExit(main())
