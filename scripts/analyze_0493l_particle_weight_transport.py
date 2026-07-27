#!/usr/bin/env python3
"""Analyze particle-weight transport in binary Taylor--Green runs.

0493l is diagnostic only.  It does not modify the solver and does not apply
PASS/FAIL gates to physical observables.  It measures whether resampling turns
particle mass into a broad, spatially correlated macro-particle weight.

Outputs:
  weight_transport_0493l_summary.csv
  weight_transport_0493l_pairs.csv
  weight_transport_0493l_radial_profiles.csv
  weight_transport_0493l_cells.csv
  weight_transport_0493l.md
"""
from __future__ import annotations

import argparse
import csv
import math
import re
import struct
import sys
from array import array
from dataclasses import dataclass, asdict
from pathlib import Path
from typing import Iterable, Sequence

FLUID_ROLE = 1
SPECIES = (1, 2)


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
    return {"n": n, "x": x, "y": y, "vx": vx, "vy": vy, "type": typ, "mass": mass, "role": role}


def finite(x: float, default: float = float("nan")) -> float:
    return x if math.isfinite(x) else default


def quantile(sorted_values: Sequence[float], q: float) -> float:
    if not sorted_values:
        return float("nan")
    if len(sorted_values) == 1:
        return float(sorted_values[0])
    pos = min(1.0, max(0.0, q)) * (len(sorted_values) - 1)
    lo = int(math.floor(pos))
    hi = min(len(sorted_values) - 1, lo + 1)
    f = pos - lo
    return (1.0 - f) * sorted_values[lo] + f * sorted_values[hi]


def pearson(xs: Sequence[float], ys: Sequence[float]) -> float:
    if len(xs) != len(ys) or len(xs) < 2:
        return float("nan")
    xm = math.fsum(xs) / len(xs)
    ym = math.fsum(ys) / len(ys)
    xx = math.fsum((x - xm) ** 2 for x in xs)
    yy = math.fsum((y - ym) ** 2 for y in ys)
    if xx <= 0.0 or yy <= 0.0:
        return 0.0
    xy = math.fsum((x - xm) * (y - ym) for x, y in zip(xs, ys))
    return xy / math.sqrt(xx * yy)


def weighted_pearson(xs: Sequence[float], ys: Sequence[float], weights: Sequence[float]) -> float:
    if len(xs) != len(ys) or len(xs) != len(weights) or len(xs) < 2:
        return float("nan")
    sw = math.fsum(weights)
    if sw <= 0.0:
        return float("nan")
    xm = math.fsum(w * x for x, w in zip(xs, weights)) / sw
    ym = math.fsum(w * y for y, w in zip(ys, weights)) / sw
    xx = math.fsum(w * (x - xm) ** 2 for x, w in zip(xs, weights))
    yy = math.fsum(w * (y - ym) ** 2 for y, w in zip(ys, weights))
    if xx <= 0.0 or yy <= 0.0:
        return 0.0
    xy = math.fsum(w * (x - xm) * (y - ym) for x, y, w in zip(xs, ys, weights))
    return xy / math.sqrt(xx * yy)


def gini(values: Sequence[float]) -> float:
    vals = sorted(v for v in values if v >= 0.0 and math.isfinite(v))
    if not vals:
        return float("nan")
    total = math.fsum(vals)
    if total <= 0.0:
        return 0.0
    weighted_sum = math.fsum((i + 1) * v for i, v in enumerate(vals))
    n = len(vals)
    return (2.0 * weighted_sum) / (n * total) - (n + 1.0) / n


def top_mass_fraction(values: Sequence[float], fraction: float) -> float:
    vals = sorted((v for v in values if v > 0.0 and math.isfinite(v)), reverse=True)
    if not vals:
        return float("nan")
    n_top = max(1, int(math.ceil(fraction * len(vals))))
    return math.fsum(vals[:n_top]) / math.fsum(vals)


def periodic_delta(a: float, b: float) -> float:
    d = abs(a - b)
    return min(d, 1.0 - d)


def vortex_centers(mode: int) -> list[tuple[float, float]]:
    # For psi ~ sin(2*pi*m*x) sin(2*pi*m*y), centers satisfy cos(...)=0.
    return [
        ((2 * i + 1) / (4.0 * mode), (2 * j + 1) / (4.0 * mode))
        for i in range(2 * mode)
        for j in range(2 * mode)
    ]


def signed_periodic_delta(a: float, b: float) -> float:
    # Signed shortest displacement from b to a on the unit torus.
    return ((a - b + 0.5) % 1.0) - 0.5


def nearest_vortex(x: float, y: float, mode: int) -> tuple[float, float, float, float, float]:
    best = (float("inf"), float("nan"), float("nan"), float("nan"), float("nan"))
    for cx, cy in vortex_centers(mode):
        dx = signed_periodic_delta(x, cx)
        dy = signed_periodic_delta(y, cy)
        d = math.hypot(dx, dy)
        if d < best[0]:
            best = (d, cx, cy, dx, dy)
    max_voronoi_radius = math.sqrt(2.0) / (4.0 * mode)
    return best[0] / max_voronoi_radius, best[1], best[2], best[3], best[4]


def cell_index(x: float, y: float, nx: int, ny: int) -> int:
    ix = min(nx - 1, max(0, int(math.floor((x % 1.0) * nx))))
    iy = min(ny - 1, max(0, int(math.floor((y % 1.0) * ny))))
    return ix + nx * iy


def weight_stats(
    values: Sequence[float],
    radii: Sequence[float],
    basis: Sequence[float],
    radial_velocity: Sequence[float],
    initial_min: float,
    initial_max: float,
) -> dict[str, float | int]:
    if not values:
        return {
            "particles": 0,
            "weight_sum": 0.0,
            "weight_mean": float("nan"),
            "weight_min": float("nan"),
            "weight_p01": float("nan"),
            "weight_p05": float("nan"),
            "weight_median": float("nan"),
            "weight_p95": float("nan"),
            "weight_p99": float("nan"),
            "weight_max": float("nan"),
            "weight_cv2": float("nan"),
            "weight_gini": float("nan"),
            "effective_particles": float("nan"),
            "effective_fraction": float("nan"),
            "top1_mass_fraction": float("nan"),
            "top5_mass_fraction": float("nan"),
            "below_initial_min_fraction": float("nan"),
            "above_initial_max_fraction": float("nan"),
            "outside_initial_range_mass_fraction": float("nan"),
            "corr_weight_radius": float("nan"),
            "corr_weight_radius_mass_weighted": float("nan"),
            "corr_weight_composition_basis": float("nan"),
            "corr_weight_abs_composition_basis": float("nan"),
            "corr_weight_radial_velocity": float("nan"),
            "corr_weight_abs_radial_velocity": float("nan"),
            "radial_velocity_mean": float("nan"),
            "radial_velocity_mass_weighted_mean": float("nan"),
            "light10_radial_velocity_mean": float("nan"),
            "heavy10_radial_velocity_mean": float("nan"),
            "heavy_minus_light_radial_velocity": float("nan"),
        }
    ordered = sorted(values)
    n = len(values)
    sw = math.fsum(values)
    sw2 = math.fsum(v * v for v in values)
    mean = sw / n
    var = math.fsum((v - mean) ** 2 for v in values) / n
    cv2 = var / (mean * mean) if mean > 0.0 else float("nan")
    ess = sw * sw / sw2 if sw2 > 0.0 else float("nan")
    outside_mass = math.fsum(
        v for v in values if v < initial_min - 1.0e-12 or v > initial_max + 1.0e-12
    )
    ranked = sorted(zip(values, radial_velocity), key=lambda pair: pair[0])
    n_tail = max(1, int(math.ceil(0.10 * n)))
    light_vr = math.fsum(vr for _, vr in ranked[:n_tail]) / n_tail
    heavy_vr = math.fsum(vr for _, vr in ranked[-n_tail:]) / n_tail
    return {
        "particles": n,
        "weight_sum": sw,
        "weight_mean": mean,
        "weight_min": ordered[0],
        "weight_p01": quantile(ordered, 0.01),
        "weight_p05": quantile(ordered, 0.05),
        "weight_median": quantile(ordered, 0.50),
        "weight_p95": quantile(ordered, 0.95),
        "weight_p99": quantile(ordered, 0.99),
        "weight_max": ordered[-1],
        "weight_cv2": cv2,
        "weight_gini": gini(values),
        "effective_particles": ess,
        "effective_fraction": ess / n if n else float("nan"),
        "top1_mass_fraction": top_mass_fraction(values, 0.01),
        "top5_mass_fraction": top_mass_fraction(values, 0.05),
        "below_initial_min_fraction": sum(v < initial_min - 1.0e-12 for v in values) / n,
        "above_initial_max_fraction": sum(v > initial_max + 1.0e-12 for v in values) / n,
        "outside_initial_range_mass_fraction": outside_mass / sw if sw > 0.0 else float("nan"),
        "corr_weight_radius": pearson(values, radii),
        "corr_weight_radius_mass_weighted": weighted_pearson(values, radii, values),
        "corr_weight_composition_basis": pearson(values, basis),
        "corr_weight_abs_composition_basis": pearson(values, [abs(v) for v in basis]),
        "corr_weight_radial_velocity": pearson(values, radial_velocity),
        "corr_weight_abs_radial_velocity": pearson(values, [abs(v) for v in radial_velocity]),
        "radial_velocity_mean": math.fsum(radial_velocity) / n,
        "radial_velocity_mass_weighted_mean": (
            math.fsum(w * vr for w, vr in zip(values, radial_velocity)) / sw if sw > 0.0 else float("nan")
        ),
        "light10_radial_velocity_mean": light_vr,
        "heavy10_radial_velocity_mean": heavy_vr,
        "heavy_minus_light_radial_velocity": heavy_vr - light_vr,
    }


def group_stats(weights: Sequence[float]) -> dict[str, float | int]:
    if not weights:
        return {
            "count": 0,
            "mass": 0.0,
            "weight_mean": float("nan"),
            "weight_min": float("nan"),
            "weight_max": float("nan"),
            "weight_cv2": float("nan"),
            "effective_particles": 0.0,
            "effective_fraction": float("nan"),
        }
    sw = math.fsum(weights)
    sw2 = math.fsum(w * w for w in weights)
    mean = sw / len(weights)
    var = math.fsum((w - mean) ** 2 for w in weights) / len(weights)
    ess = sw * sw / sw2 if sw2 > 0.0 else 0.0
    return {
        "count": len(weights),
        "mass": sw,
        "weight_mean": mean,
        "weight_min": min(weights),
        "weight_max": max(weights),
        "weight_cv2": var / (mean * mean) if mean > 0.0 else float("nan"),
        "effective_particles": ess,
        "effective_fraction": ess / len(weights),
    }


@dataclass
class ParticleRecord:
    weight: float
    radius: float
    basis: float
    radial_velocity: float
    cell: int
    species: int


def analyze_state(
    path: Path,
    mode_name: str,
    step: int,
    nx: int,
    ny: int,
    tg_mode: int,
    radial_bins: int,
    initial_ranges: dict[tuple[str, int], tuple[float, float]],
) -> tuple[list[dict[str, object]], list[dict[str, object]], list[dict[str, object]]]:
    state = read_state(path)
    n = int(state["n"])
    x = state["x"]
    y = state["y"]
    typ = state["type"]
    mass = state["mass"]
    vx = state["vx"]
    vy = state["vy"]
    role = state["role"]
    k = 2.0 * math.pi * tg_mode
    records: list[ParticleRecord] = []
    by_species: dict[int, list[ParticleRecord]] = {0: [], 1: [], 2: []}
    nc = nx * ny
    cell_weights: list[dict[int, list[float]]] = [{0: [], 1: [], 2: []} for _ in range(nc)]

    for p in range(n):
        if role[p] != FLUID_ROLE:
            continue
        t = int(typ[p])
        if t not in SPECIES:
            continue
        xp = x[p] % 1.0
        yp = y[p] % 1.0
        w = float(mass[p])
        radius, _, _, dx_vortex, dy_vortex = nearest_vortex(xp, yp, tg_mode)
        physical_radius = math.hypot(dx_vortex, dy_vortex)
        if physical_radius > 1.0e-15:
            radial_velocity = (float(vx[p]) * dx_vortex + float(vy[p]) * dy_vortex) / physical_radius
        else:
            radial_velocity = 0.0
        basis = math.sin(k * xp) * math.sin(k * yp)
        c = cell_index(xp, yp, nx, ny)
        rec = ParticleRecord(w, radius, basis, radial_velocity, c, t)
        records.append(rec)
        by_species[0].append(rec)
        by_species[t].append(rec)
        cell_weights[c][0].append(w)
        cell_weights[c][t].append(w)

    summary_rows: list[dict[str, object]] = []
    for species in (0, 1, 2):
        rows = by_species[species]
        values = [r.weight for r in rows]
        radii = [r.radius for r in rows]
        bases = [r.basis for r in rows]
        radial_velocity = [r.radial_velocity for r in rows]
        initial_min, initial_max = initial_ranges[(mode_name, species)]
        stats = weight_stats(values, radii, bases, radial_velocity, initial_min, initial_max)
        summary_rows.append({
            "mode": mode_name,
            "step": step,
            "species": species,
            "initial_weight_min": initial_min,
            "initial_weight_max": initial_max,
            **stats,
        })

    cell_rows: list[dict[str, object]] = []
    for c in range(nc):
        ix = c % nx
        iy = c // nx
        xc = (ix + 0.5) / nx
        yc = (iy + 0.5) / ny
        rnorm, vcx, vcy, _, _ = nearest_vortex(xc, yc, tg_mode)
        all_stats = group_stats(cell_weights[c][0])
        s1_stats = group_stats(cell_weights[c][1])
        s2_stats = group_stats(cell_weights[c][2])
        total_mass = float(all_stats["mass"])
        concentration = float(s1_stats["mass"]) / total_mass if total_mass > 0.0 else float("nan")
        row: dict[str, object] = {
            "mode": mode_name,
            "step": step,
            "cell": c,
            "ix": ix,
            "iy": iy,
            "x": xc,
            "y": yc,
            "vortex_center_x": vcx,
            "vortex_center_y": vcy,
            "radius_normalized": rnorm,
            "composition_basis": math.sin(k * xc) * math.sin(k * yc),
            "species1_concentration_mass": concentration,
        }
        for prefix, stats in (("all", all_stats), ("species1", s1_stats), ("species2", s2_stats)):
            for key, value in stats.items():
                row[f"{prefix}_{key}"] = value
        cell_rows.append(row)

    radial_rows: list[dict[str, object]] = []
    for species in (0, 1, 2):
        bins: list[list[ParticleRecord]] = [[] for _ in range(radial_bins)]
        for rec in by_species[species]:
            b = min(radial_bins - 1, max(0, int(rec.radius * radial_bins)))
            bins[b].append(rec)
        for b, rows in enumerate(bins):
            values = [r.weight for r in rows]
            stats = group_stats(values)
            mean_vr = math.fsum(r.radial_velocity for r in rows) / len(rows) if rows else float("nan")
            mass_vr = (
                math.fsum(r.weight * r.radial_velocity for r in rows) / math.fsum(values)
                if values and math.fsum(values) > 0.0 else float("nan")
            )
            radial_rows.append({
                "mode": mode_name,
                "step": step,
                "species": species,
                "radial_bin": b,
                "radius_min": b / radial_bins,
                "radius_max": (b + 1) / radial_bins,
                "radius_mean": math.fsum(r.radius for r in rows) / len(rows) if rows else float("nan"),
                "radial_velocity_mean": mean_vr,
                "radial_velocity_mass_weighted_mean": mass_vr,
                **stats,
            })

    return summary_rows, radial_rows, cell_rows


def write_csv(path: Path, rows: list[dict[str, object]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if not rows:
        path.write_text("", encoding="utf-8")
        return
    fields = list(rows[0].keys())
    with path.open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)


def parse_steps(text: str) -> list[int]:
    values = []
    for token in re.split(r"[ ,;:]+", text.strip()):
        if token:
            values.append(int(token))
    return sorted(set(values))


def safe_ratio(a: object, b: object) -> float:
    aa = float(a)
    bb = float(b)
    return aa / bb if math.isfinite(aa) and math.isfinite(bb) and abs(bb) > 1.0e-300 else float("nan")


def make_report(
    path: Path,
    root: Path,
    summary: list[dict[str, object]],
    pairs: list[dict[str, object]],
    modes: list[str],
    steps: list[int],
) -> None:
    final_step = max(steps)
    lines = [
        "# 0493l — Particle-weight transport diagnostic",
        "",
        f"Run root: `{root}`",
        "",
        "Diagnostic only: no solver physics or qualification thresholds are changed.",
        "",
        "## Final-step weight statistics",
        "",
        "| Mode | Species | N | min | p01 | median | p99 | max | CV² | ESS/N | top 1% mass | corr(w,r) | corr(w,vr) | heavy-light vr |",
        "|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for mode in modes:
        for species in (0, 1, 2):
            row = next((r for r in summary if r["mode"] == mode and r["step"] == final_step and r["species"] == species), None)
            if row is None:
                continue
            label = "all" if species == 0 else str(species)
            lines.append(
                f"| {mode} | {label} | {int(row['particles'])} | {float(row['weight_min']):.6g} | "
                f"{float(row['weight_p01']):.6g} | {float(row['weight_median']):.6g} | "
                f"{float(row['weight_p99']):.6g} | {float(row['weight_max']):.6g} | "
                f"{float(row['weight_cv2']):.6g} | {float(row['effective_fraction']):.6g} | "
                f"{float(row['top1_mass_fraction']):.6g} | {float(row['corr_weight_radius']):.6g} | "
                f"{float(row['corr_weight_radial_velocity']):.6g} | "
                f"{float(row['heavy_minus_light_radial_velocity']):.6g} |"
            )
    lines.extend([
        "",
        "## Paired resampling / reference ratios",
        "",
        "| Step | Species | CV² ratio | ESS-fraction ratio | top-1%-mass ratio | radial-correlation delta | outside-initial-range mass fraction (resampling) |",
        "|---:|---:|---:|---:|---:|---:|---:|",
    ])
    for row in pairs:
        species = int(row["species"])
        label = "all" if species == 0 else str(species)
        lines.append(
            f"| {int(row['step'])} | {label} | {float(row['weight_cv2_ratio']):.6g} | "
            f"{float(row['effective_fraction_ratio']):.6g} | {float(row['top1_mass_fraction_ratio']):.6g} | "
            f"{float(row['corr_weight_radius_delta']):.6g} | "
            f"{float(row['resampling_outside_initial_range_mass_fraction']):.6g} |"
        )
    lines.extend([
        "",
        "## Interpretation guide",
        "",
        "- `CV²` measures dispersion of particle weights; zero means equal weights.",
        "- `ESS/N = 1/(1+CV²)` for a weight sample and measures the number of independent equal-weight carriers represented by the weighted sample.",
        "- `top 1% mass` is the fraction of species mass carried by the heaviest 1% of particles.",
        "- `corr(w,r)` detects whether heavy or light carriers preferentially occupy vortex cores or peripheries.",
        "- `corr(w,vr)` and `heavy-light vr` test directly whether heavy and light carriers have different radial motion.",
        "- `outside initial range mass fraction` measures mass carried by weights created beyond the initial particle-mass interval.",
        "- Cell and radial CSV files must be used to determine whether weight broadening is spatially structured rather than globally random.",
        "",
    ])
    path.write_text("\n".join(lines), encoding="utf-8")


def parse_args() -> argparse.Namespace:
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", type=Path, required=True)
    ap.add_argument("--seed", type=int, required=True)
    ap.add_argument("--scenario", default="binary_species")
    ap.add_argument("--modes", nargs="+", default=["src", "src-resampling"])
    ap.add_argument("--steps", default="0 200 400 800 1500")
    ap.add_argument("--nx", type=int, required=True)
    ap.add_argument("--ny", type=int, required=True)
    ap.add_argument("--tg-mode", type=int, required=True)
    ap.add_argument("--radial-bins", type=int, default=12)
    ap.add_argument("--output-dir", type=Path)
    return ap.parse_args()


def main() -> int:
    a = parse_args()
    steps = parse_steps(a.steps)
    out = a.output_dir or a.root
    case_root = a.root / f"seed_{a.seed}" / a.scenario

    initial_ranges: dict[tuple[str, int], tuple[float, float]] = {}
    for mode in a.modes:
        path = case_root / mode / "output" / "state_step_00000000.smpcd"
        if not path.is_file():
            raise SystemExit(f"[0493l] ERROR missing initial state {path}")
        state = read_state(path)
        n = int(state["n"])
        values: dict[int, list[float]] = {0: [], 1: [], 2: []}
        for p in range(n):
            if state["role"][p] != FLUID_ROLE:
                continue
            t = int(state["type"][p])
            if t not in SPECIES:
                continue
            w = float(state["mass"][p])
            values[0].append(w)
            values[t].append(w)
        for species in (0, 1, 2):
            initial_ranges[(mode, species)] = (min(values[species]), max(values[species]))

    summary_rows: list[dict[str, object]] = []
    radial_rows: list[dict[str, object]] = []
    cell_rows: list[dict[str, object]] = []
    for mode in a.modes:
        for step in steps:
            path = case_root / mode / "output" / f"state_step_{step:08d}.smpcd"
            if not path.is_file():
                raise SystemExit(f"[0493l] ERROR missing state {path}")
            summary, radial, cells = analyze_state(
                path, mode, step, a.nx, a.ny, a.tg_mode, a.radial_bins, initial_ranges
            )
            summary_rows.extend(summary)
            radial_rows.extend(radial)
            cell_rows.extend(cells)
            all_row = next(r for r in summary if r["species"] == 0)
            print(
                f"[0493l] mode={mode} step={step} particles={all_row['particles']} "
                f"weightMinMax={float(all_row['weight_min']):.8g}/{float(all_row['weight_max']):.8g} "
                f"cv2={float(all_row['weight_cv2']):.6g} essFraction={float(all_row['effective_fraction']):.6g} "
                f"top1Mass={float(all_row['top1_mass_fraction']):.6g} corrWeightRadius={float(all_row['corr_weight_radius']):.6g}"
            )

    indexed = {(str(r["mode"]), int(r["step"]), int(r["species"])): r for r in summary_rows}
    pair_rows: list[dict[str, object]] = []
    if "src" in a.modes and "src-resampling" in a.modes:
        for step in steps:
            for species in (0, 1, 2):
                ref = indexed[("src", step, species)]
                rsp = indexed[("src-resampling", step, species)]
                pair_rows.append({
                    "step": step,
                    "species": species,
                    "weight_cv2_ratio": safe_ratio(rsp["weight_cv2"], ref["weight_cv2"]),
                    "weight_cv2_delta": float(rsp["weight_cv2"]) - float(ref["weight_cv2"]),
                    "effective_fraction_ratio": safe_ratio(rsp["effective_fraction"], ref["effective_fraction"]),
                    "top1_mass_fraction_ratio": safe_ratio(rsp["top1_mass_fraction"], ref["top1_mass_fraction"]),
                    "weight_range_ratio": safe_ratio(
                        float(rsp["weight_max"]) - float(rsp["weight_min"]),
                        float(ref["weight_max"]) - float(ref["weight_min"]),
                    ),
                    "corr_weight_radius_delta": float(rsp["corr_weight_radius"]) - float(ref["corr_weight_radius"]),
                    "corr_weight_composition_basis_delta": (
                        float(rsp["corr_weight_composition_basis"]) - float(ref["corr_weight_composition_basis"])
                    ),
                    "resampling_outside_initial_range_mass_fraction": rsp["outside_initial_range_mass_fraction"],
                    "resampling_below_initial_min_fraction": rsp["below_initial_min_fraction"],
                    "resampling_above_initial_max_fraction": rsp["above_initial_max_fraction"],
                })

    write_csv(out / "weight_transport_0493l_summary.csv", summary_rows)
    write_csv(out / "weight_transport_0493l_pairs.csv", pair_rows)
    write_csv(out / "weight_transport_0493l_radial_profiles.csv", radial_rows)
    write_csv(out / "weight_transport_0493l_cells.csv", cell_rows)
    make_report(out / "weight_transport_0493l.md", a.root, summary_rows, pair_rows, list(a.modes), steps)
    print(f"[0493l] summary={out / 'weight_transport_0493l_summary.csv'}")
    print(f"[0493l] pairs={out / 'weight_transport_0493l_pairs.csv'}")
    print(f"[0493l] radial={out / 'weight_transport_0493l_radial_profiles.csv'}")
    print(f"[0493l] cells={out / 'weight_transport_0493l_cells.csv'}")
    print(f"[0493l] report={out / 'weight_transport_0493l.md'}")
    print("[0493l] status=PASS diagnostic-only")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
