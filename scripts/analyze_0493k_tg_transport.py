#!/usr/bin/env python3
"""Analyze the 0493k Taylor--Green transport and interdiffusion matrix.

Only Python's standard library is used.  The analyzer reads active-fluid state
snapshots and produces:

* Taylor--Green modal decay and effective kinematic viscosity;
* binary composition-mode decay and interdiffusion coefficient;
* Schmidt number;
* total and species invariants;
* cell-field divergence, vorticity and enstrophy;
* species temperature proxies, velocity skewness/kurtosis and barycentric slip;
* comparisons across SRC/Q6/resampling and legacy/resident mono paths;
* explicit verification that empty-refill did not perform any refill.
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
from dataclasses import asdict, dataclass, fields
from pathlib import Path
from typing import Iterable

FLUID_ROLE = 1
MODES = ("src", "src-resampling", "src-q6", "src-q6-resampling")
SCENARIOS = ("mono_legacy", "mono_species", "binary_species")


def finite(value: object, default: float = float("nan")) -> float:
    try:
        x = float(value)  # type: ignore[arg-type]
        return x if math.isfinite(x) else default
    except Exception:
        return default


def rel_diff(a: float, b: float) -> float:
    if not math.isfinite(a) or not math.isfinite(b):
        return float("nan")
    return abs(a - b) / max(1.0e-300, 0.5 * (abs(a) + abs(b)))


def variance(values: Iterable[float]) -> float:
    vals = list(values)
    if not vals:
        return float("nan")
    mean = math.fsum(vals) / len(vals)
    return math.fsum((v - mean) ** 2 for v in vals) / len(vals)


def read_array(stream, typecode: str, n: int) -> array:
    out = array(typecode)
    out.fromfile(stream, n)
    if sys.byteorder != "little":
        out.byteswap()
    return out


def read_state(path: Path) -> dict[str, object]:
    with path.open("rb") as stream:
        magic = stream.read(16)
        if not magic.startswith(b"SRCMPCD_STATE"):
            raise ValueError(f"{path}: unsupported magic {magic!r}")
        header = struct.unpack("<IIIIQIIII", stream.read(40))
        n = int(header[4])
        stream.read(8 * 8)
        x = read_array(stream, "d", n)
        y = read_array(stream, "d", n)
        vx = read_array(stream, "d", n)
        vy = read_array(stream, "d", n)
        typ = read_array(stream, "I", n)
        mass = read_array(stream, "d", n)
        role = stream.read(n)
        if len(role) != n:
            raise ValueError(f"{path}: truncated role array")
    return {
        "n": n,
        "x": x,
        "y": y,
        "vx": vx,
        "vy": vy,
        "type": typ,
        "mass": mass,
        "role": role,
    }


def read_csv(path: Path) -> list[dict[str, str]]:
    if not path.is_file():
        return []
    with path.open(newline="", encoding="utf-8") as stream:
        return list(csv.DictReader(stream))


def sum_int(rows: list[dict[str, str]], key: str) -> int:
    total = 0
    for row in rows:
        try:
            total += int(float(row.get(key, "0") or 0))
        except Exception:
            pass
    return total


def max_int(rows: list[dict[str, str]], key: str) -> int:
    values: list[int] = []
    for row in rows:
        try:
            values.append(int(float(row.get(key, "0") or 0)))
        except Exception:
            pass
    return max(values, default=0)


def max_float(rows: list[dict[str, str]], key: str) -> float:
    values: list[float] = []
    for row in rows:
        try:
            x = abs(float(row.get(key, "0") or 0))
            if math.isfinite(x):
                values.append(x)
        except Exception:
            pass
    return max(values, default=0.0)


def last_csv(path: Path) -> dict[str, str]:
    rows = read_csv(path)
    return rows[-1] if rows else {}


def elapsed_seconds(path: Path) -> float:
    if not path.is_file():
        return float("nan")
    match = re.search(r"elapsed=([0-9.eE+-]+)", path.read_text(errors="replace"))
    return finite(match.group(1)) if match else float("nan")


def cell_index(x: float, y: float, nx: int, ny: int) -> int:
    ix = min(nx - 1, max(0, int(math.floor((x % 1.0) * nx))))
    iy = min(ny - 1, max(0, int(math.floor((y % 1.0) * ny))))
    return ix + nx * iy


def safe_standardized_moments(m2: float, m3: float, m4: float, weight: float) -> tuple[float, float]:
    if not weight > 0.0:
        return float("nan"), float("nan")
    var = m2 / weight
    if not var > 1.0e-30:
        return 0.0, 0.0
    skew = (m3 / weight) / (var ** 1.5)
    kurt = (m4 / weight) / (var * var) - 3.0
    return skew, kurt


@dataclass
class Metric:
    step: int
    time: float
    fluid_particles: int
    total_mass: float
    px: float
    py: float
    kinetic: float
    mean_vx: float
    mean_vy: float
    tg_amp_x: float
    tg_amp_y: float
    tg_amplitude: float
    tg_quadrature: float
    tg_cell_residual_rms: float
    tg_cell_correlation: float
    occupancy_mean: float
    occupancy_variance: float
    occupancy_min: int
    occupancy_max: int
    empty_cells: int
    divergence_rms: float
    vorticity_rms: float
    enstrophy: float
    species1_mass: float
    species2_mass: float
    species1_px: float
    species1_py: float
    species2_px: float
    species2_py: float
    species1_kinetic: float
    species2_kinetic: float
    composition_mean: float
    composition_target_amp: float
    composition_mode_amp: float
    composition_leakage: float
    species_slip_rms: float
    species1_thermal_variance: float
    species2_thermal_variance: float
    species1_skew_abs_max: float
    species2_skew_abs_max: float
    species1_kurtosis_excess_mean: float
    species2_kurtosis_excess_mean: float


def metric(path: Path, step: int, scenario: str, a: argparse.Namespace) -> Metric:
    state = read_state(path)
    n = int(state["n"])
    x = state["x"]
    y = state["y"]
    vx = state["vx"]
    vy = state["vy"]
    typ = state["type"]
    mass = state["mass"]
    role = state["role"]
    nc = a.nx * a.ny
    cell_count = [0] * nc
    cell_mass = [0.0] * nc
    cell_px = [0.0] * nc
    cell_py = [0.0] * nc
    species_mass = [[0.0] * nc for _ in range(2)]
    species_px = [[0.0] * nc for _ in range(2)]
    species_py = [[0.0] * nc for _ in range(2)]

    k = 2.0 * math.pi * a.tg_mode
    total_mass = px_total = py_total = kinetic = 0.0
    fluid_particles = 0
    ax_num = ax_den = ay_num = ay_den = 0.0
    qx_num = qx_den = qy_num = qy_den = 0.0
    global_species_mass = [0.0, 0.0]
    global_species_px = [0.0, 0.0]
    global_species_py = [0.0, 0.0]
    global_species_kinetic = [0.0, 0.0]

    for p in range(n):
        if role[p] != FLUID_ROLE:
            continue
        fluid_particles += 1
        m = mass[p]
        xp = x[p] % 1.0
        yp = y[p] % 1.0
        up = vx[p]
        vp = vy[p]
        c = cell_index(xp, yp, a.nx, a.ny)
        cell_count[c] += 1
        cell_mass[c] += m
        cell_px[c] += m * up
        cell_py[c] += m * vp
        total_mass += m
        px_total += m * up
        py_total += m * vp
        kinetic += 0.5 * m * (up * up + vp * vp)

        bx = math.sin(k * xp) * math.cos(k * yp)
        by = -math.cos(k * xp) * math.sin(k * yp)
        qx = math.cos(k * xp) * math.cos(k * yp)
        qy = math.sin(k * xp) * math.sin(k * yp)
        ax_num += m * up * bx
        ax_den += m * bx * bx
        ay_num += m * vp * by
        ay_den += m * by * by
        qx_num += m * up * qx
        qx_den += m * qx * qx
        qy_num += m * vp * qy
        qy_den += m * qy * qy

        t = int(typ[p])
        if t in (1, 2):
            s = t - 1
            species_mass[s][c] += m
            species_px[s][c] += m * up
            species_py[s][c] += m * vp
            global_species_mass[s] += m
            global_species_px[s] += m * up
            global_species_py[s] += m * vp
            global_species_kinetic[s] += 0.5 * m * (up * up + vp * vp)

    amp_x = ax_num / ax_den if ax_den > 0.0 else float("nan")
    amp_y = ay_num / ay_den if ay_den > 0.0 else float("nan")
    tg_amp = 0.5 * (amp_x + amp_y)
    q_amp_x = qx_num / qx_den if qx_den > 0.0 else float("nan")
    q_amp_y = qy_num / qy_den if qy_den > 0.0 else float("nan")
    tg_quad = math.hypot(q_amp_x, q_amp_y)

    cell_ux = [0.0] * nc
    cell_uy = [0.0] * nc
    species_ux = [[0.0] * nc for _ in range(2)]
    species_uy = [[0.0] * nc for _ in range(2)]
    for c in range(nc):
        if cell_mass[c] > 0.0:
            cell_ux[c] = cell_px[c] / cell_mass[c]
            cell_uy[c] = cell_py[c] / cell_mass[c]
        for s in range(2):
            if species_mass[s][c] > 0.0:
                species_ux[s][c] = species_px[s][c] / species_mass[s][c]
                species_uy[s][c] = species_py[s][c] / species_mass[s][c]

    dx = 1.0 / a.nx
    dy = 1.0 / a.ny
    div2 = vort2 = 0.0
    residual2 = observed2 = predicted2 = dot = residual_weight = 0.0
    for j in range(a.ny):
        jm = (j - 1) % a.ny
        jp = (j + 1) % a.ny
        yc = (j + 0.5) / a.ny
        for i in range(a.nx):
            im = (i - 1) % a.nx
            ip = (i + 1) % a.nx
            c = i + a.nx * j
            cxm = im + a.nx * j
            cxp = ip + a.nx * j
            cym = i + a.nx * jm
            cyp = i + a.nx * jp
            dux_dx = (cell_ux[cxp] - cell_ux[cxm]) / (2.0 * dx)
            duy_dy = (cell_uy[cyp] - cell_uy[cym]) / (2.0 * dy)
            duy_dx = (cell_uy[cxp] - cell_uy[cxm]) / (2.0 * dx)
            dux_dy = (cell_ux[cyp] - cell_ux[cym]) / (2.0 * dy)
            div = dux_dx + duy_dy
            vort = duy_dx - dux_dy
            div2 += div * div
            vort2 += vort * vort

            if cell_mass[c] > 0.0:
                xc = (i + 0.5) / a.nx
                pred_x = amp_x * math.sin(k * xc) * math.cos(k * yc)
                pred_y = -amp_y * math.cos(k * xc) * math.sin(k * yc)
                obs_x = cell_ux[c]
                obs_y = cell_uy[c]
                w = cell_mass[c]
                residual2 += w * ((obs_x - pred_x) ** 2 + (obs_y - pred_y) ** 2)
                observed2 += w * (obs_x * obs_x + obs_y * obs_y)
                predicted2 += w * (pred_x * pred_x + pred_y * pred_y)
                dot += w * (obs_x * pred_x + obs_y * pred_y)
                residual_weight += w

    divergence_rms = math.sqrt(div2 / nc)
    vorticity_rms = math.sqrt(vort2 / nc)
    enstrophy = 0.5 * vort2 / nc
    tg_residual = math.sqrt(residual2 / residual_weight) if residual_weight > 0.0 else float("nan")
    tg_corr = dot / math.sqrt(observed2 * predicted2) if observed2 > 0.0 and predicted2 > 0.0 else float("nan")

    composition_mean = composition_target = composition_mode = composition_leak = float("nan")
    if scenario == "binary_species":
        concentrations: list[tuple[int, float]] = []
        for c in range(nc):
            ms = species_mass[0][c] + species_mass[1][c]
            if ms > 0.0:
                concentrations.append((c, species_mass[0][c] / ms))
        composition_mean = math.fsum(v for _, v in concentrations) / len(concentrations)
        nums = [0.0, 0.0, 0.0, 0.0]
        dens = [0.0, 0.0, 0.0, 0.0]
        for c, value in concentrations:
            i = c % a.nx
            j = c // a.nx
            xc = (i + 0.5) / a.nx
            yc = (j + 0.5) / a.ny
            sx, cx = math.sin(k * xc), math.cos(k * xc)
            sy, cy = math.sin(k * yc), math.cos(k * yc)
            bases = (sx * sy, cx * sy, sx * cy, cx * cy)
            centered = value - composition_mean
            for q, basis in enumerate(bases):
                nums[q] += centered * basis
                dens[q] += basis * basis
        coeff = [nums[q] / dens[q] if dens[q] > 0.0 else float("nan") for q in range(4)]
        composition_target = coeff[0]
        composition_mode = math.sqrt(math.fsum(v * v for v in coeff if math.isfinite(v)))
        composition_leak = math.sqrt(math.fsum(v * v for v in coeff[1:] if math.isfinite(v)))

    slip_num = slip_den = 0.0
    for c in range(nc):
        m1 = species_mass[0][c]
        m2 = species_mass[1][c]
        if m1 > 0.0 and m2 > 0.0:
            dux = species_ux[0][c] - species_ux[1][c]
            duy = species_uy[0][c] - species_uy[1][c]
            w = 2.0 * m1 * m2 / (m1 + m2)
            slip_num += w * (dux * dux + duy * duy)
            slip_den += w
    species_slip = math.sqrt(slip_num / slip_den) if slip_den > 0.0 else float("nan")

    m2x = [0.0, 0.0]
    m2y = [0.0, 0.0]
    m3x = [0.0, 0.0]
    m3y = [0.0, 0.0]
    m4x = [0.0, 0.0]
    m4y = [0.0, 0.0]
    for p in range(n):
        if role[p] != FLUID_ROLE:
            continue
        t = int(typ[p])
        if t not in (1, 2):
            continue
        s = t - 1
        c = cell_index(x[p], y[p], a.nx, a.ny)
        du = vx[p] - species_ux[s][c]
        dv = vy[p] - species_uy[s][c]
        m = mass[p]
        du2 = du * du
        dv2 = dv * dv
        m2x[s] += m * du2
        m2y[s] += m * dv2
        m3x[s] += m * du2 * du
        m3y[s] += m * dv2 * dv
        m4x[s] += m * du2 * du2
        m4y[s] += m * dv2 * dv2

    thermal_var = [float("nan"), float("nan")]
    skew_abs = [float("nan"), float("nan")]
    kurt_mean = [float("nan"), float("nan")]
    for s in range(2):
        w = global_species_mass[s]
        if w > 0.0:
            thermal_var[s] = (m2x[s] + m2y[s]) / w
            skew_x, kurt_x = safe_standardized_moments(m2x[s], m3x[s], m4x[s], w)
            skew_y, kurt_y = safe_standardized_moments(m2y[s], m3y[s], m4y[s], w)
            skew_abs[s] = max(abs(skew_x), abs(skew_y))
            kurt_mean[s] = 0.5 * (kurt_x + kurt_y)

    mean_vx = px_total / total_mass if total_mass > 0.0 else float("nan")
    mean_vy = py_total / total_mass if total_mass > 0.0 else float("nan")
    empty = sum(1 for count in cell_count if count == 0)
    return Metric(
        step=step,
        time=step * a.dt,
        fluid_particles=fluid_particles,
        total_mass=total_mass,
        px=px_total,
        py=py_total,
        kinetic=kinetic,
        mean_vx=mean_vx,
        mean_vy=mean_vy,
        tg_amp_x=amp_x,
        tg_amp_y=amp_y,
        tg_amplitude=tg_amp,
        tg_quadrature=tg_quad,
        tg_cell_residual_rms=tg_residual,
        tg_cell_correlation=tg_corr,
        occupancy_mean=math.fsum(cell_count) / nc,
        occupancy_variance=variance(cell_count),
        occupancy_min=min(cell_count),
        occupancy_max=max(cell_count),
        empty_cells=empty,
        divergence_rms=divergence_rms,
        vorticity_rms=vorticity_rms,
        enstrophy=enstrophy,
        species1_mass=global_species_mass[0],
        species2_mass=global_species_mass[1],
        species1_px=global_species_px[0],
        species1_py=global_species_py[0],
        species2_px=global_species_px[1],
        species2_py=global_species_py[1],
        species1_kinetic=global_species_kinetic[0],
        species2_kinetic=global_species_kinetic[1],
        composition_mean=composition_mean,
        composition_target_amp=composition_target,
        composition_mode_amp=composition_mode,
        composition_leakage=composition_leak,
        species_slip_rms=species_slip,
        species1_thermal_variance=thermal_var[0],
        species2_thermal_variance=thermal_var[1],
        species1_skew_abs_max=skew_abs[0],
        species2_skew_abs_max=skew_abs[1],
        species1_kurtosis_excess_mean=kurt_mean[0],
        species2_kurtosis_excess_mean=kurt_mean[1],
    )


def state_series(case: Path, scenario: str, a: argparse.Namespace) -> list[Metric]:
    pattern = re.compile(r"state_step_(\d+)\.smpcd$")
    result: list[Metric] = []
    for path in sorted((case / "output").glob("state_step_*.smpcd")):
        match = pattern.search(path.name)
        if match:
            result.append(metric(path, int(match.group(1)), scenario, a))
    result.sort(key=lambda row: row.step)
    expected = set(range(0, a.steps + 1, a.dump_every))
    got = {row.step for row in result}
    missing = sorted(expected - got)
    if missing:
        raise ValueError(f"missing state dumps in {case}: {missing[:12]}")
    return result


def fit_decay(series: list[Metric], field: str, k2: float, min_fraction: float = 0.08) -> dict[str, float]:
    initial = abs(finite(getattr(series[0], field)))
    usable: list[tuple[float, float]] = []
    for row in series[1:]:
        value = abs(finite(getattr(row, field)))
        if initial > 0.0 and value > max(1.0e-14, min_fraction * initial):
            usable.append((row.time, math.log(value / initial)))
    if len(usable) < 5:
        return {"slope": float("nan"), "coefficient": float("nan"), "r2": float("nan"), "points": len(usable)}
    xs = [p[0] for p in usable]
    ys = [p[1] for p in usable]
    xm = math.fsum(xs) / len(xs)
    ym = math.fsum(ys) / len(ys)
    sxx = math.fsum((x - xm) ** 2 for x in xs)
    sxy = math.fsum((x - xm) * (y - ym) for x, y in zip(xs, ys))
    slope = sxy / sxx
    intercept = ym - slope * xm
    ssr = math.fsum((y - (intercept + slope * x)) ** 2 for x, y in zip(xs, ys))
    sst = math.fsum((y - ym) ** 2 for y in ys)
    r2 = 1.0 - ssr / sst if sst > 0.0 else 1.0
    return {
        "slope": slope,
        "coefficient": -slope / k2,
        "r2": r2,
        "points": len(usable),
        "intercept": intercept,
    }


def normalized_curve_rms(a_rows: list[Metric], b_rows: list[Metric], field: str) -> float:
    aa = {row.step: finite(getattr(row, field)) for row in a_rows}
    bb = {row.step: finite(getattr(row, field)) for row in b_rows}
    common = sorted(set(aa) & set(bb))
    scale = max(1.0e-14, abs(aa[min(common)]))
    return math.sqrt(math.fsum(((aa[s] - bb[s]) / scale) ** 2 for s in common) / len(common))


def parse_args() -> argparse.Namespace:
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", type=Path, required=True)
    ap.add_argument("--nx", type=int, required=True)
    ap.add_argument("--ny", type=int, required=True)
    ap.add_argument("--dt", type=float, required=True)
    ap.add_argument("--steps", type=int, required=True)
    ap.add_argument("--dump-every", type=int, required=True)
    ap.add_argument("--tg-mode", type=int, required=True)
    ap.add_argument("--tg-amplitude", type=float, required=True)
    ap.add_argument("--composition-amplitude", type=float, required=True)
    ap.add_argument("--seeds", nargs="+", type=int, required=True)
    ap.add_argument("--scenarios", nargs="+", choices=SCENARIOS, required=True)
    ap.add_argument("--modes", nargs="+", choices=MODES, required=True)
    ap.add_argument("--mass-rel-tol", type=float, default=1.0e-10)
    ap.add_argument("--momentum-abs-tol", type=float, default=1.0e-9)
    ap.add_argument("--energy-rel-tol", type=float, default=1.0e-9)
    ap.add_argument("--q6-energy-rel-tol", type=float, default=5.0e-2)
    ap.add_argument("--fit-r2-min", type=float, default=0.95)
    ap.add_argument("--diffusion-fit-r2-min", type=float, default=0.90)
    ap.add_argument("--diffusion-min-decay-rel", type=float, default=1.0e-2)
    ap.add_argument("--nu-pair-rel-tol", type=float, default=0.20)
    ap.add_argument("--diffusion-pair-rel-tol", type=float, default=0.25)
    ap.add_argument("--mono-nonreg-nu-rel-tol", type=float, default=0.15)
    ap.add_argument("--curve-rms-tol", type=float, default=0.06)
    ap.add_argument("--thermal-pair-rel-tol", type=float, default=0.20)
    ap.add_argument("--q6-energy-curve-rms-tol", type=float, default=3.0e-2)
    ap.add_argument("--q6-energy-endpoint-rel-tol", type=float, default=3.0e-2)
    ap.add_argument("--q6-divergence-ratio-max", type=float, default=1.50)
    return ap.parse_args()


def main() -> int:
    a = parse_args()
    checks: list[dict[str, object]] = []
    summaries: list[dict[str, object]] = []
    series_map: dict[tuple[int, str, str], list[Metric]] = {}
    summary_map: dict[tuple[int, str, str], dict[str, object]] = {}
    k2 = 2.0 * (2.0 * math.pi * a.tg_mode) ** 2

    def emit(name: str, status: str, detail: str, category: str = "qualification") -> None:
        checks.append({"check": name, "status": status, "category": category, "detail": detail})
        print(f"[0493k-audit] {name}={status} {detail}")

    def check(name: str, ok: bool, detail: str, category: str = "qualification") -> None:
        emit(name, "PASS" if ok else "FAIL", detail, category)

    def observe(name: str, detail: str, category: str = "observation") -> None:
        emit(name, "INFO", detail, category)

    def inconclusive(name: str, detail: str, category: str = "qualification") -> None:
        emit(name, "INCONCLUSIVE", detail, category)

    for seed in a.seeds:
        for scenario in a.scenarios:
            for mode in a.modes:
                key = (seed, scenario, mode)
                case = a.root / f"seed_{seed}" / scenario / mode
                try:
                    rows = state_series(case, scenario, a)
                except Exception as exc:
                    check(f"seed{seed}_{scenario}_{mode}_state_series", False, str(exc), "integrity")
                    continue
                series_map[key] = rows
                first = rows[0]
                last = rows[-1]
                nu_fit = fit_decay(rows, "tg_amplitude", k2)
                d_fit = fit_decay(rows, "composition_mode_amp", k2) if scenario == "binary_species" else {
                    "coefficient": float("nan"), "r2": float("nan"), "points": 0, "slope": float("nan")
                }
                nu = finite(nu_fit.get("coefficient"))
                diff = finite(d_fit.get("coefficient"))
                schmidt = nu / diff if nu > 0.0 and diff > 0.0 else float("nan")
                composition_decay_rel = (
                    1.0 - abs(last.composition_mode_amp) / max(1.0e-300, abs(first.composition_mode_amp))
                    if scenario == "binary_species" and math.isfinite(first.composition_mode_amp)
                    else float("nan")
                )
                mass_drift = max(abs(row.total_mass - first.total_mass) / max(1.0, abs(first.total_mass)) for row in rows)
                px_drift = max(abs(row.px - first.px) for row in rows)
                py_drift = max(abs(row.py - first.py) for row in rows)
                energy_drift = max(abs(row.kinetic - first.kinetic) / max(1.0, abs(first.kinetic)) for row in rows)
                s1_mass_drift = max(abs(row.species1_mass - first.species1_mass) / max(1.0, abs(first.species1_mass)) for row in rows)
                s2_mass_drift = (
                    max(abs(row.species2_mass - first.species2_mass) / max(1.0, abs(first.species2_mass)) for row in rows)
                    if first.species2_mass > 0.0 else 0.0
                )
                s1_kinetic_change = (last.species1_kinetic - first.species1_kinetic) / max(1.0, abs(first.species1_kinetic))
                s2_kinetic_change = (
                    (last.species2_kinetic - first.species2_kinetic) / max(1.0, abs(first.species2_kinetic))
                    if first.species2_kinetic > 0.0 else float("nan")
                )

                output = case / "output"
                guard = read_csv(output / "cuda_resampling_population_guard_0297.csv")
                plan = read_csv(output / "cuda_species_transfer_plan_0490k.csv")
                fast = read_csv(output / "cuda_species_resident_fast_path_0490m.csv")
                closure = read_csv(output / "cuda_species_mass_closure_0490i.csv")
                maintenance = read_csv(output / "cuda_species_resident_maintenance_0490n.csv")
                runtime = last_csv(output / "summary_runtime.csv")
                time_file = case / "logs" / "time_0493k.txt"
                resampling = "resampling" in mode
                q6 = "q6" in mode
                species_path = resampling and scenario in ("mono_species", "binary_species")
                activity = (
                    sum_int(guard, "splitApplied")
                    + sum_int(guard, "mergeApplied")
                    + sum_int(guard, "speciesDirectedSplits0490j")
                    + sum_int(guard, "speciesDirectedMerges0490j")
                    + sum_int(plan, "gpuPlanEntries")
                    + sum_int(fast, "operations")
                )
                refill_cells = sum_int(guard, "emptyRefillCells0319")
                refill_particles = sum_int(guard, "emptyRefillParticles0319")
                q6_applied = int(finite(runtime.get("q6Applied"), 0.0))
                closure_residual = max_float(closure, "maxKineticEnergyRelResidual")
                closure_infeasible = max_int(closure, "infeasibleKineticCells")
                closure_active = max_int(closure, "speciesKineticConservativeBalance")

                summary: dict[str, object] = {
                    "seed": seed,
                    "scenario": scenario,
                    "mode": mode,
                    "elapsed_s": elapsed_seconds(time_file),
                    "nu_eff": nu,
                    "nu_fit_r2": finite(nu_fit.get("r2")),
                    "nu_fit_points": int(nu_fit.get("points", 0)),
                    "diffusion_eff": diff,
                    "diffusion_fit_r2": finite(d_fit.get("r2")),
                    "diffusion_fit_points": int(d_fit.get("points", 0)),
                    "schmidt": schmidt,
                    "tg_initial_amplitude": first.tg_amplitude,
                    "tg_final_amplitude": last.tg_amplitude,
                    "tg_final_ratio": last.tg_amplitude / first.tg_amplitude,
                    "composition_initial_amplitude": first.composition_mode_amp,
                    "composition_final_amplitude": last.composition_mode_amp,
                    "composition_final_ratio": (
                        last.composition_mode_amp / first.composition_mode_amp
                        if math.isfinite(first.composition_mode_amp) and first.composition_mode_amp != 0.0 else float("nan")
                    ),
                    "composition_decay_rel": composition_decay_rel,
                    "kinetic_initial": first.kinetic,
                    "kinetic_final": last.kinetic,
                    "mass_drift_max_rel": mass_drift,
                    "px_drift_max_abs": px_drift,
                    "py_drift_max_abs": py_drift,
                    "kinetic_drift_max_rel": energy_drift,
                    "species1_mass_drift_max_rel": s1_mass_drift,
                    "species2_mass_drift_max_rel": s2_mass_drift,
                    "species1_kinetic_change_rel": s1_kinetic_change,
                    "species2_kinetic_change_rel": s2_kinetic_change,
                    "final_divergence_rms": last.divergence_rms,
                    "final_vorticity_rms": last.vorticity_rms,
                    "final_enstrophy": last.enstrophy,
                    "final_tg_residual_rms": last.tg_cell_residual_rms,
                    "final_tg_correlation": last.tg_cell_correlation,
                    "final_species_slip_rms": last.species_slip_rms,
                    "final_species1_thermal_variance": last.species1_thermal_variance,
                    "final_species2_thermal_variance": last.species2_thermal_variance,
                    "final_species1_skew_abs_max": last.species1_skew_abs_max,
                    "final_species2_skew_abs_max": last.species2_skew_abs_max,
                    "final_species1_kurtosis_excess_mean": last.species1_kurtosis_excess_mean,
                    "final_species2_kurtosis_excess_mean": last.species2_kurtosis_excess_mean,
                    "resampling_activity": activity,
                    "empty_refill_cells": refill_cells,
                    "empty_refill_particles": refill_particles,
                    "q6_applied": q6_applied,
                    "closure_active": closure_active,
                    "closure_infeasible_cells": closure_infeasible,
                    "closure_kinetic_residual": closure_residual,
                }
                summaries.append(summary)
                summary_map[key] = summary

                check(f"seed{seed}_{scenario}_{mode}_mass", mass_drift <= a.mass_rel_tol, f"maxRel={mass_drift:.3e}", "integrity")
                legacy_resampling = resampling and scenario == "mono_legacy"
                if legacy_resampling:
                    observe(
                        f"seed{seed}_{scenario}_{mode}_legacy_momentum_drift",
                        f"maxPx={px_drift:.3e} maxPy={py_drift:.3e}; historical baseline, not a resident-path gate",
                        "legacy-baseline",
                    )
                else:
                    check(
                        f"seed{seed}_{scenario}_{mode}_momentum",
                        max(px_drift, py_drift) <= a.momentum_abs_tol,
                        f"maxPx={px_drift:.3e} maxPy={py_drift:.3e}",
                        "integrity",
                    )
                if q6:
                    observe(
                        f"seed{seed}_{scenario}_{mode}_q6_kinetic_change",
                        f"maxRel={energy_drift:.3e}; Q6 is assessed by paired energy response, not raw conservation",
                        "q6-response",
                    )
                elif legacy_resampling:
                    observe(
                        f"seed{seed}_{scenario}_{mode}_legacy_kinetic_drift",
                        f"maxRel={energy_drift:.3e}; historical baseline, not a resident-path gate",
                        "legacy-baseline",
                    )
                else:
                    check(
                        f"seed{seed}_{scenario}_{mode}_kinetic",
                        energy_drift <= a.energy_rel_tol,
                        f"maxRel={energy_drift:.3e} tol={a.energy_rel_tol:.3e}",
                    )
                check(
                    f"seed{seed}_{scenario}_{mode}_initial_tg",
                    abs(first.tg_amplitude - a.tg_amplitude) <= 0.06 * a.tg_amplitude,
                    f"measured={first.tg_amplitude:.8g} requested={a.tg_amplitude:.8g}",
                )
                check(f"seed{seed}_{scenario}_{mode}_nu_positive", nu > 0.0, f"nu={nu:.8g}")
                check(
                    f"seed{seed}_{scenario}_{mode}_nu_fit",
                    finite(nu_fit.get("r2")) >= a.fit_r2_min,
                    f"r2={finite(nu_fit.get('r2')):.6g} points={int(nu_fit.get('points', 0))}",
                )
                check(
                    f"seed{seed}_{scenario}_{mode}_no_empty_cells",
                    max(row.empty_cells for row in rows) == 0,
                    f"maxEmpty={max(row.empty_cells for row in rows)}",
                    "integrity",
                )
                check(
                    f"seed{seed}_{scenario}_{mode}_species_mass",
                    max(s1_mass_drift, s2_mass_drift) <= a.mass_rel_tol,
                    f"type1={s1_mass_drift:.3e} type2={s2_mass_drift:.3e}",
                    "integrity",
                )
                if scenario == "binary_species":
                    check(
                        f"seed{seed}_{scenario}_{mode}_initial_composition",
                        abs(first.composition_target_amp - a.composition_amplitude) <= 0.05 * a.composition_amplitude,
                        f"target={first.composition_target_amp:.8g} requested={a.composition_amplitude:.8g} leakage={first.composition_leakage:.3e}",
                    )
                    measurable_diffusion = composition_decay_rel >= a.diffusion_min_decay_rel
                    if measurable_diffusion:
                        check(f"seed{seed}_{scenario}_{mode}_diffusion_positive", diff > 0.0, f"D={diff:.8g}")
                        check(
                            f"seed{seed}_{scenario}_{mode}_diffusion_fit",
                            finite(d_fit.get("r2")) >= a.diffusion_fit_r2_min,
                            f"r2={finite(d_fit.get('r2')):.6g} points={int(d_fit.get('points', 0))} decay={composition_decay_rel:.3e}",
                        )
                    else:
                        inconclusive(
                            f"seed{seed}_{scenario}_{mode}_diffusion_fit",
                            f"decay={composition_decay_rel:.3e} < {a.diffusion_min_decay_rel:.3e}; provisional D={diff:.8g} r2={finite(d_fit.get('r2')):.6g}",
                        )
                if resampling:
                    check(f"seed{seed}_{scenario}_{mode}_resampling_activity", activity > 0, f"activity={activity}", "integrity")
                    check(
                        f"seed{seed}_{scenario}_{mode}_empty_refill_inactive",
                        refill_cells == 0 and refill_particles == 0,
                        f"cells={refill_cells} particles={refill_particles}",
                        "integrity",
                    )
                    check(
                        f"seed{seed}_{scenario}_{mode}_invalid_operations_zero",
                        max_int(fast, "invalidOperations") == 0 and max_int(fast, "donorTypeGroupUnderfills") == 0,
                        f"invalid={max_int(fast, 'invalidOperations')} underfills={max_int(fast, 'donorTypeGroupUnderfills')}",
                        "integrity",
                    )
                if species_path:
                    check(
                        f"seed{seed}_{scenario}_{mode}_species_kinetic_closure",
                        closure_active == 1 and closure_infeasible == 0 and closure_residual <= a.mass_rel_tol,
                        f"active={closure_active} infeasible={closure_infeasible} residual={closure_residual:.3e}",
                        "integrity",
                    )
                    pool_columns = ("activePrefixViolations", "duplicateFreeSlots", "activeAndFreeSlots", "invalidRoleSlots")
                    check(
                        f"seed{seed}_{scenario}_{mode}_pool_integrity",
                        all(max_int(maintenance, col) == 0 for col in pool_columns),
                        " ".join(f"{col}={max_int(maintenance, col)}" for col in pool_columns),
                        "integrity",
                    )
                if q6:
                    check(f"seed{seed}_{scenario}_{mode}_q6_applied", q6_applied > 0, f"q6Applied={q6_applied}", "integrity")

    # Paired resampling comparisons within each scenario and projection family.
    for seed in a.seeds:
        for scenario in a.scenarios:
            for ref_mode, rsp_mode in (("src", "src-resampling"), ("src-q6", "src-q6-resampling")):
                kr = (seed, scenario, ref_mode)
                kp = (seed, scenario, rsp_mode)
                if kr not in summary_map or kp not in summary_map:
                    continue
                sr, sp = summary_map[kr], summary_map[kp]
                nu_rel = rel_diff(finite(sr["nu_eff"]), finite(sp["nu_eff"]))
                curve = normalized_curve_rms(series_map[kr], series_map[kp], "tg_amplitude")
                temp_rel = rel_diff(
                    finite(sr["final_species1_thermal_variance"]),
                    finite(sp["final_species1_thermal_variance"]),
                )
                check(
                    f"seed{seed}_{scenario}_{rsp_mode}_nu_agreement",
                    nu_rel <= a.nu_pair_rel_tol,
                    f"rel={nu_rel:.6g} ref={finite(sr['nu_eff']):.8g} resamp={finite(sp['nu_eff']):.8g}",
                )
                check(
                    f"seed{seed}_{scenario}_{rsp_mode}_tg_curve",
                    curve <= a.curve_rms_tol,
                    f"rms/A0={curve:.6g}",
                )
                check(
                    f"seed{seed}_{scenario}_{rsp_mode}_thermal_agreement",
                    temp_rel <= a.thermal_pair_rel_tol,
                    f"rel={temp_rel:.6g}",
                )
                if ref_mode == "src-q6":
                    kinetic_curve = normalized_curve_rms(series_map[kr], series_map[kp], "kinetic")
                    kinetic_initial_scale = max(
                        1.0e-14,
                        abs(finite(sr["kinetic_initial"])),
                        abs(finite(sp["kinetic_initial"])),
                    )
                    kinetic_endpoint = abs(
                        finite(sr["kinetic_final"]) - finite(sp["kinetic_final"])
                    ) / kinetic_initial_scale
                    check(
                        f"seed{seed}_{scenario}_{rsp_mode}_q6_kinetic_curve",
                        kinetic_curve <= a.q6_energy_curve_rms_tol,
                        f"rms/K0={kinetic_curve:.6g}",
                    )
                    check(
                        f"seed{seed}_{scenario}_{rsp_mode}_q6_kinetic_endpoint",
                        kinetic_endpoint <= a.q6_energy_endpoint_rel_tol,
                        f"absDelta/K0={kinetic_endpoint:.6g}",
                    )
                if scenario == "binary_species":
                    d_rel = rel_diff(finite(sr["diffusion_eff"]), finite(sp["diffusion_eff"]))
                    comp_curve = normalized_curve_rms(series_map[kr], series_map[kp], "composition_mode_amp")
                    diffusion_measurable = (
                        finite(sr["composition_decay_rel"], -1.0) >= a.diffusion_min_decay_rel
                        and finite(sp["composition_decay_rel"], -1.0) >= a.diffusion_min_decay_rel
                        and finite(sr["diffusion_fit_r2"], -1.0) >= a.diffusion_fit_r2_min
                        and finite(sp["diffusion_fit_r2"], -1.0) >= a.diffusion_fit_r2_min
                    )
                    if diffusion_measurable:
                        check(
                            f"seed{seed}_{scenario}_{rsp_mode}_diffusion_agreement",
                            d_rel <= a.diffusion_pair_rel_tol,
                            f"rel={d_rel:.6g} ref={finite(sr['diffusion_eff']):.8g} resamp={finite(sp['diffusion_eff']):.8g}",
                        )
                    else:
                        inconclusive(
                            f"seed{seed}_{scenario}_{rsp_mode}_diffusion_agreement",
                            f"insufficient resolved decay; provisional rel={d_rel:.6g} ref={finite(sr['diffusion_eff']):.8g} resamp={finite(sp['diffusion_eff']):.8g}",
                        )
                    check(
                        f"seed{seed}_{scenario}_{rsp_mode}_composition_curve",
                        comp_curve <= a.curve_rms_tol,
                        f"rms/A0={comp_curve:.6g}",
                    )

        # Legacy mono versus resident speciesCount=1 non-regression.
        for mode in ("src-resampling", "src-q6-resampling"):
            kl = (seed, "mono_legacy", mode)
            ks = (seed, "mono_species", mode)
            if kl not in summary_map or ks not in summary_map:
                continue
            sl, ss = summary_map[kl], summary_map[ks]
            nu_rel = rel_diff(finite(sl["nu_eff"]), finite(ss["nu_eff"]))
            curve = normalized_curve_rms(series_map[kl], series_map[ks], "tg_amplitude")
            temp_rel = rel_diff(
                finite(sl["final_species1_thermal_variance"]),
                finite(ss["final_species1_thermal_variance"]),
            )
            check(
                f"seed{seed}_{mode}_legacy_vs_species_mono_nu",
                nu_rel <= a.mono_nonreg_nu_rel_tol,
                f"rel={nu_rel:.6g} legacy={finite(sl['nu_eff']):.8g} species={finite(ss['nu_eff']):.8g}",
            )
            check(
                f"seed{seed}_{mode}_legacy_vs_species_mono_curve",
                curve <= a.curve_rms_tol,
                f"rms/A0={curve:.6g}",
            )
            check(
                f"seed{seed}_{mode}_legacy_vs_species_mono_thermal",
                temp_rel <= a.thermal_pair_rel_tol,
                f"rel={temp_rel:.6g}",
            )

        # Q6 should not increase the final raw cell-divergence diagnostic grossly.
        for scenario in a.scenarios:
            for src_mode, q6_mode in (("src", "src-q6"), ("src-resampling", "src-q6-resampling")):
                ks = (seed, scenario, src_mode)
                kq = (seed, scenario, q6_mode)
                if ks not in summary_map or kq not in summary_map:
                    continue
                src_div = finite(summary_map[ks]["final_divergence_rms"])
                q6_div = finite(summary_map[kq]["final_divergence_rms"])
                ratio = q6_div / max(src_div, 1.0e-14)
                check(
                    f"seed{seed}_{scenario}_{q6_mode}_divergence_not_regressed",
                    ratio <= a.q6_divergence_ratio_max,
                    f"ratio={ratio:.6g} src={src_div:.6g} q6={q6_div:.6g}",
                )

    a.root.mkdir(parents=True, exist_ok=True)
    metric_names = [field.name for field in fields(Metric)]
    with (a.root / "tg_0493k_timeseries.csv").open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=["seed", "scenario", "mode"] + metric_names)
        writer.writeheader()
        for key in sorted(series_map):
            seed, scenario, mode = key
            for row in series_map[key]:
                writer.writerow({"seed": seed, "scenario": scenario, "mode": mode, **asdict(row)})

    if summaries:
        with (a.root / "tg_0493k_summary.csv").open("w", newline="", encoding="utf-8") as stream:
            writer = csv.DictWriter(stream, fieldnames=list(summaries[0]))
            writer.writeheader()
            writer.writerows(summaries)
    with (a.root / "physics_0493k_checks.csv").open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=("check", "status", "category", "detail"))
        writer.writeheader()
        writer.writerows(checks)

    failed = [row for row in checks if row["status"] == "FAIL"]
    unresolved = [row for row in checks if row["status"] == "INCONCLUSIVE"]
    observations = [row for row in checks if row["status"] == "INFO"]
    status = "FAIL" if failed else ("PASS_WITH_INCONCLUSIVE" if unresolved else "PASS")
    report = {
        "status": status,
        "parameters": {**vars(a), "root": str(a.root)},
        "summaries": summaries,
        "failed_checks": failed,
        "inconclusive_checks": unresolved,
        "observations": observations,
    }
    (a.root / "physics_0493k.json").write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")

    md = [
        "# 0493k Taylor--Green transport qualification",
        "",
        f"**Status: {status}**",
        "",
        "| seed | scenario | mode | nu | D | Sc | R2(nu) | R2(D) | div(end) | refill cells |",
        "|---:|---|---|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for row in summaries:
        md.append(
            f"| {row['seed']} | {row['scenario']} | {row['mode']} | "
            f"{finite(row['nu_eff']):.6g} | {finite(row['diffusion_eff']):.6g} | "
            f"{finite(row['schmidt']):.6g} | {finite(row['nu_fit_r2']):.6g} | "
            f"{finite(row['diffusion_fit_r2']):.6g} | {finite(row['final_divergence_rms']):.6g} | "
            f"{int(row['empty_refill_cells'])} |"
        )
    if failed:
        md.extend(("", "## Failed checks", ""))
        md.extend(f"- `{row['check']}` — {row['detail']}" for row in failed)
    if unresolved:
        md.extend(("", "## Inconclusive checks", ""))
        md.extend(f"- `{row['check']}` — {row['detail']}" for row in unresolved)
    if observations:
        md.extend(("", "## Observations", ""))
        md.extend(f"- `{row['check']}` — {row['detail']}" for row in observations)
    (a.root / "physics_0493k.md").write_text("\n".join(md) + "\n", encoding="utf-8")

    print(
        f"[0493k-audit] status={status} checks={len(checks)} "
        f"failed={len(failed)} inconclusive={len(unresolved)} info={len(observations)}"
    )
    print(f"[0493k-audit] summary={a.root / 'tg_0493k_summary.csv'}")
    print(f"[0493k-audit] report={a.root / 'physics_0493k.md'}")
    return 2 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
