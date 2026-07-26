#!/usr/bin/env python3
"""Analyze the 0493g physically neutral two-species smoke test.

The initial checkerboard varies only the number of numerical particles.  Every
cell has the same total mass, the same mass of each species, the same momentum
of each species, and the same thermal energy of each species.  A valid
resampling operation may change particle counts, but it must not change those
physical fields.
"""

from __future__ import annotations

import argparse
import csv
import json
import math
import struct
import sys
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Iterable


@dataclass
class SpeciesMetrics:
    type_id: int
    particle_count: int
    total_mass: float
    px: float
    py: float
    mean_vx: float
    mean_vy: float
    kinetic: float
    thermal_krel: float
    cell_count_mean: float
    cell_count_variance: float
    cell_count_min: int
    cell_count_max: int
    cell_mass_mean: float
    cell_mass_variance: float
    cell_mass_min: float
    cell_mass_max: float
    cell_px_variance: float
    cell_py_variance: float
    cell_kinetic_variance: float
    cell_krel_variance: float
    checkerboard_count_amplitude: float
    checkerboard_mass_amplitude: float


@dataclass
class StateMetrics:
    path: str
    fluid_particles: int
    inactive_particles: int
    fluid_types: list[int]
    total_mass: float
    px: float
    py: float
    mean_vx: float
    mean_vy: float
    kinetic: float
    thermal_krel: float
    occupancy_mean: float
    occupancy_variance: float
    occupancy_min: int
    occupancy_max: int
    occupancy_outside_band: int
    mass_mean: float
    mass_variance: float
    mass_min: float
    mass_max: float
    mass_off_target_cells: int
    cell_px_variance: float
    cell_py_variance: float
    cell_kinetic_variance: float
    cell_krel_variance: float
    checkerboard_occupancy_amplitude: float
    checkerboard_mass_amplitude: float
    type1_fraction_mean: float
    type1_fraction_variance: float
    type1_fraction_min: float
    type1_fraction_max: float
    species: dict[int, SpeciesMetrics]


@dataclass
class DetailedState:
    metrics: StateMetrics
    cell_counts: list[int]
    cell_mass: list[float]
    cell_px: list[float]
    cell_py: list[float]
    cell_kinetic: list[float]
    cell_krel: list[float]
    species_cell_counts: dict[int, list[int]]
    species_cell_mass: dict[int, list[float]]
    species_cell_px: dict[int, list[float]]
    species_cell_py: dict[int, list[float]]
    species_cell_kinetic: dict[int, list[float]]
    species_cell_krel: dict[int, list[float]]


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser()
    p.add_argument("--root", type=Path, required=True)
    p.add_argument("--nx", type=int, required=True)
    p.add_argument("--ny", type=int, required=True)
    p.add_argument("--gamma", type=int, required=True)
    p.add_argument("--target-cell-mass", type=float, required=True)
    p.add_argument("--species-target-cell-mass", type=float, required=True)
    p.add_argument("--short-step", type=int, default=10)
    p.add_argument("--mass-rel-tol", type=float, default=1.0e-12)
    p.add_argument("--momentum-abs-tol", type=float, default=1.0e-10)
    p.add_argument("--energy-rel-tol", type=float, default=1.0e-6)
    p.add_argument("--cell-mass-abs-tol", type=float, default=1.0e-10)
    p.add_argument("--cell-momentum-abs-tol", type=float, default=1.0e-10)
    p.add_argument("--cell-energy-abs-tol", type=float, default=1.0e-10)
    return p.parse_args()


def read_state(path: Path) -> dict[str, list[float] | list[int]]:
    data = path.read_bytes()
    offset = 0
    if len(data) < 16:
        raise ValueError(f"state too short: {path}")
    magic = data[:16].rstrip(b"\0")
    offset += 16
    if magic != b"SRCMPCD_STATE":
        raise ValueError(f"invalid state magic in {path}: {magic!r}")

    header_fmt = "<IIIIQIIII"
    header_size = struct.calcsize(header_fmt)
    if len(data) < offset + header_size:
        raise ValueError(f"truncated header in {path}")
    version, endian, dimensions, scalar_code, n, type_flag, mass_flag, reserved_count, role_flag = struct.unpack_from(
        header_fmt, data, offset
    )
    offset += header_size
    if version != 2 or endian != 0x01020304 or dimensions != 2:
        raise ValueError(
            f"unsupported state header in {path}: version={version} endian={endian:#x} dimensions={dimensions}"
        )
    if scalar_code != 1 or type_flag != 1 or mass_flag != 1 or role_flag != 4:
        raise ValueError(
            f"unsupported state flags in {path}: scalar={scalar_code} type={type_flag} mass={mass_flag} role={role_flag}"
        )
    offset += 8 * int(reserved_count)

    def read_array(fmt: str, count: int) -> list[float] | list[int]:
        nonlocal offset
        size = struct.calcsize(f"<{count}{fmt}")
        if len(data) < offset + size:
            raise ValueError(f"truncated array in {path}")
        values = list(struct.unpack_from(f"<{count}{fmt}", data, offset))
        offset += size
        return values

    count = int(n)
    return {
        "x": read_array("d", count),
        "y": read_array("d", count),
        "vx": read_array("d", count),
        "vy": read_array("d", count),
        "type": read_array("I", count),
        "mass": read_array("d", count),
        "role": read_array("B", count),
    }


def variance(values: list[float] | list[int]) -> float:
    if not values:
        return 0.0
    mean = math.fsum(float(v) for v in values) / len(values)
    return math.fsum((float(v) - mean) ** 2 for v in values) / len(values)


def checkerboard(values: list[float] | list[int], nx: int, ny: int) -> float:
    mean = math.fsum(float(v) for v in values) / len(values)
    total = 0.0
    for j in range(ny):
        for i in range(nx):
            c = j * nx + i
            sign = 1.0 if ((i + j) & 1) == 0 else -1.0
            total += sign * (float(values[c]) - mean)
    return total / len(values)


def cell_krel(mass: list[float], px: list[float], py: list[float], kinetic: list[float]) -> list[float]:
    out: list[float] = []
    for m, x, y, k in zip(mass, px, py, kinetic):
        if m <= 0.0:
            out.append(0.0)
        else:
            value = k - 0.5 * (x * x + y * y) / m
            out.append(max(0.0, value) if value > -1.0e-14 else value)
    return out


def state_metrics(
    path: Path,
    nx: int,
    ny: int,
    gamma: int,
    target_cell_mass: float,
    cell_mass_abs_tol: float,
) -> DetailedState:
    s = read_state(path)
    x, y = s["x"], s["y"]
    vx, vy = s["vx"], s["vy"]
    typ, mass, role = s["type"], s["mass"], s["role"]
    active = [i for i, r in enumerate(role) if int(r) == 1]
    if not active:
        raise ValueError(f"no fluid particles in {path}")

    cells = nx * ny
    cell_counts = [0] * cells
    cell_mass = [0.0] * cells
    cell_px = [0.0] * cells
    cell_py = [0.0] * cells
    cell_kinetic = [0.0] * cells
    species_cell_counts = {1: [0] * cells, 2: [0] * cells}
    species_cell_mass = {1: [0.0] * cells, 2: [0.0] * cells}
    species_cell_px = {1: [0.0] * cells, 2: [0.0] * cells}
    species_cell_py = {1: [0.0] * cells, 2: [0.0] * cells}
    species_cell_kinetic = {1: [0.0] * cells, 2: [0.0] * cells}

    particle_cell: dict[int, int] = {}
    for p in active:
        t = int(typ[p])
        if t not in species_cell_counts:
            raise ValueError(f"unexpected fluid type {t} in {path}")
        xx = float(x[p]) % 1.0
        yy = float(y[p]) % 1.0
        ci = min(nx - 1, int(math.floor(xx * nx)))
        cj = min(ny - 1, int(math.floor(yy * ny)))
        c = cj * nx + ci
        particle_cell[p] = c
        mp = float(mass[p])
        pxp = mp * float(vx[p])
        pyp = mp * float(vy[p])
        kp = 0.5 * mp * (float(vx[p]) ** 2 + float(vy[p]) ** 2)
        cell_counts[c] += 1
        cell_mass[c] += mp
        cell_px[c] += pxp
        cell_py[c] += pyp
        cell_kinetic[c] += kp
        species_cell_counts[t][c] += 1
        species_cell_mass[t][c] += mp
        species_cell_px[t][c] += pxp
        species_cell_py[t][c] += pyp
        species_cell_kinetic[t][c] += kp

    cell_relative = cell_krel(cell_mass, cell_px, cell_py, cell_kinetic)
    species_cell_relative = {
        t: cell_krel(
            species_cell_mass[t], species_cell_px[t], species_cell_py[t], species_cell_kinetic[t]
        )
        for t in (1, 2)
    }

    total_mass = math.fsum(float(mass[p]) for p in active)
    px = math.fsum(float(mass[p]) * float(vx[p]) for p in active)
    py = math.fsum(float(mass[p]) * float(vy[p]) for p in active)
    mean_vx, mean_vy = px / total_mass, py / total_mass
    kinetic = math.fsum(
        0.5 * float(mass[p]) * (float(vx[p]) ** 2 + float(vy[p]) ** 2) for p in active
    )
    thermal_krel = kinetic - 0.5 * (px * px + py * py) / total_mass

    species: dict[int, SpeciesMetrics] = {}
    for t in (1, 2):
        ids = [p for p in active if int(typ[p]) == t]
        tm = math.fsum(float(mass[p]) for p in ids)
        tpx = math.fsum(float(mass[p]) * float(vx[p]) for p in ids)
        tpy = math.fsum(float(mass[p]) * float(vy[p]) for p in ids)
        tux, tuy = tpx / tm, tpy / tm
        tkin = math.fsum(
            0.5 * float(mass[p]) * (float(vx[p]) ** 2 + float(vy[p]) ** 2) for p in ids
        )
        tkrel = tkin - 0.5 * (tpx * tpx + tpy * tpy) / tm
        counts = species_cell_counts[t]
        masses = species_cell_mass[t]
        species[t] = SpeciesMetrics(
            type_id=t,
            particle_count=len(ids),
            total_mass=tm,
            px=tpx,
            py=tpy,
            mean_vx=tux,
            mean_vy=tuy,
            kinetic=tkin,
            thermal_krel=tkrel,
            cell_count_mean=math.fsum(counts) / cells,
            cell_count_variance=variance(counts),
            cell_count_min=min(counts),
            cell_count_max=max(counts),
            cell_mass_mean=math.fsum(masses) / cells,
            cell_mass_variance=variance(masses),
            cell_mass_min=min(masses),
            cell_mass_max=max(masses),
            cell_px_variance=variance(species_cell_px[t]),
            cell_py_variance=variance(species_cell_py[t]),
            cell_kinetic_variance=variance(species_cell_kinetic[t]),
            cell_krel_variance=variance(species_cell_relative[t]),
            checkerboard_count_amplitude=checkerboard(counts, nx, ny),
            checkerboard_mass_amplitude=checkerboard(masses, nx, ny),
        )

    fractions = [species_cell_mass[1][c] / cell_mass[c] if cell_mass[c] > 0.0 else 0.0 for c in range(cells)]
    nmin, nmax = gamma - 1, gamma + 1
    metrics = StateMetrics(
        path=str(path),
        fluid_particles=len(active),
        inactive_particles=len(role) - len(active),
        fluid_types=sorted({int(typ[p]) for p in active}),
        total_mass=total_mass,
        px=px,
        py=py,
        mean_vx=mean_vx,
        mean_vy=mean_vy,
        kinetic=kinetic,
        thermal_krel=thermal_krel,
        occupancy_mean=math.fsum(cell_counts) / cells,
        occupancy_variance=variance(cell_counts),
        occupancy_min=min(cell_counts),
        occupancy_max=max(cell_counts),
        occupancy_outside_band=sum(v < nmin or v > nmax for v in cell_counts),
        mass_mean=math.fsum(cell_mass) / cells,
        mass_variance=variance(cell_mass),
        mass_min=min(cell_mass),
        mass_max=max(cell_mass),
        mass_off_target_cells=sum(abs(v - target_cell_mass) > cell_mass_abs_tol for v in cell_mass),
        cell_px_variance=variance(cell_px),
        cell_py_variance=variance(cell_py),
        cell_kinetic_variance=variance(cell_kinetic),
        cell_krel_variance=variance(cell_relative),
        checkerboard_occupancy_amplitude=checkerboard(cell_counts, nx, ny),
        checkerboard_mass_amplitude=checkerboard(cell_mass, nx, ny),
        type1_fraction_mean=math.fsum(fractions) / cells,
        type1_fraction_variance=variance(fractions),
        type1_fraction_min=min(fractions),
        type1_fraction_max=max(fractions),
        species=species,
    )
    return DetailedState(
        metrics,
        cell_counts,
        cell_mass,
        cell_px,
        cell_py,
        cell_kinetic,
        cell_relative,
        species_cell_counts,
        species_cell_mass,
        species_cell_px,
        species_cell_py,
        species_cell_kinetic,
        species_cell_relative,
    )


def read_csv(path: Path) -> list[dict[str, str]]:
    if not path.exists():
        return []
    with path.open(newline="") as f:
        return list(csv.DictReader(f))


def max_int(rows: Iterable[dict[str, str]], column: str) -> int:
    return max((int(float(r[column])) for r in rows if r.get(column, "") != ""), default=0)


def sum_int(rows: Iterable[dict[str, str]], column: str) -> int:
    return sum(int(float(r[column])) for r in rows if r.get(column, "") != "")


def max_float(rows: Iterable[dict[str, str]], column: str) -> float:
    return max((abs(float(r[column])) for r in rows if r.get(column, "") != ""), default=0.0)


def rel_error(a: float, b: float) -> float:
    return abs(a - b) / max(abs(a), abs(b), 1.0e-300)


def vectors_equal_int(a: list[int], b: list[int]) -> bool:
    return a == b


def vectors_close(a: list[float], b: list[float], tol: float) -> bool:
    return len(a) == len(b) and all(abs(x - y) <= tol for x, y in zip(a, b))


def max_vector_error(a: list[float], b: list[float]) -> float:
    if len(a) != len(b):
        return math.inf
    return max((abs(x - y) for x, y in zip(a, b)), default=0.0)


def main() -> int:
    args = parse_args()
    root = args.root.resolve()
    initial_path = root / "init" / "two_species_neutral_checkerboard_0493g.smpcd"
    cases = {
        "control": "00_no_resampling",
        "both": "01_both_species",
        "type1": "02_type1_only",
        "type2": "03_type2_only",
        "none": "04_no_species_enabled",
    }

    paths: dict[str, Path] = {"initial": initial_path}
    for key, case in cases.items():
        paths[f"{key}_step1"] = root / case / "output" / "state_step_00000001.smpcd"
        paths[f"{key}_short"] = root / case / "output" / f"state_step_{args.short_step:08d}.smpcd"
    missing = [p for p in paths.values() if not p.exists()]
    if missing:
        print("[0493g-audit] FAIL missing state dumps:", file=sys.stderr)
        for p in missing:
            print(f"  {p}", file=sys.stderr)
        return 2

    states = {
        name: state_metrics(
            path,
            args.nx,
            args.ny,
            args.gamma,
            args.target_cell_mass,
            args.cell_mass_abs_tol,
        )
        for name, path in paths.items()
    }
    checks: list[tuple[str, bool, str]] = []

    def check(name: str, ok: bool, detail: str) -> None:
        checks.append((name, bool(ok), detail))

    initial = states["initial"]
    initial_m = initial.metrics
    target_species_count = args.gamma // 2

    check("initial_types", initial_m.fluid_types == [1, 2], f"types={initial_m.fluid_types}")
    check(
        "initial_count_checkerboard",
        initial_m.occupancy_min == args.gamma - 2 and initial_m.occupancy_max == args.gamma + 2,
        f"total={initial_m.occupancy_min}/{initial_m.occupancy_max}",
    )
    check(
        "initial_species_count_checkerboard",
        all(
            initial_m.species[t].cell_count_min == (args.gamma - 2) // 2
            and initial_m.species[t].cell_count_max == (args.gamma + 2) // 2
            for t in (1, 2)
        ),
        " ".join(
            f"type{t}={initial_m.species[t].cell_count_min}/{initial_m.species[t].cell_count_max}"
            for t in (1, 2)
        ),
    )
    check(
        "initial_total_mass_field_uniform",
        vectors_close(initial.cell_mass, [args.target_cell_mass] * len(initial.cell_mass), args.cell_mass_abs_tol),
        f"min/max={initial_m.mass_min:.17g}/{initial_m.mass_max:.17g}",
    )
    for t in (1, 2):
        sm = initial_m.species[t]
        check(
            f"initial_type{t}_mass_field_uniform",
            vectors_close(
                initial.species_cell_mass[t],
                [args.species_target_cell_mass] * len(initial.species_cell_mass[t]),
                args.cell_mass_abs_tol,
            ),
            f"min/max={sm.cell_mass_min:.17g}/{sm.cell_mass_max:.17g}",
        )
        check(
            f"initial_type{t}_momentum_field_uniform",
            sm.cell_px_variance <= args.cell_momentum_abs_tol**2
            and sm.cell_py_variance <= args.cell_momentum_abs_tol**2,
            f"varPx={sm.cell_px_variance:.3e} varPy={sm.cell_py_variance:.3e}",
        )
        check(
            f"initial_type{t}_energy_field_uniform",
            sm.cell_kinetic_variance <= args.cell_energy_abs_tol**2
            and sm.cell_krel_variance <= args.cell_energy_abs_tol**2,
            f"varK={sm.cell_kinetic_variance:.3e} varKrel={sm.cell_krel_variance:.3e}",
        )
    check(
        "initial_composition_uniform",
        abs(initial_m.type1_fraction_mean - 0.5) <= 1.0e-15
        and initial_m.type1_fraction_variance <= 1.0e-28,
        f"mean={initial_m.type1_fraction_mean:.17g} var={initial_m.type1_fraction_variance:.3e}",
    )

    def conservation(label: str, current: DetailedState) -> None:
        cm = current.metrics
        check(
            f"{label}_total_mass",
            rel_error(cm.total_mass, initial_m.total_mass) <= args.mass_rel_tol,
            f"rel={rel_error(cm.total_mass, initial_m.total_mass):.3e}",
        )
        check(
            f"{label}_total_momentum",
            abs(cm.px - initial_m.px) <= args.momentum_abs_tol
            and abs(cm.py - initial_m.py) <= args.momentum_abs_tol,
            f"dPx={cm.px-initial_m.px:.3e} dPy={cm.py-initial_m.py:.3e}",
        )
        check(
            f"{label}_global_thermal_energy",
            rel_error(cm.thermal_krel, initial_m.thermal_krel) <= args.energy_rel_tol,
            f"rel={rel_error(cm.thermal_krel, initial_m.thermal_krel):.3e}",
        )
        for t in (1, 2):
            ref = initial_m.species[t]
            cur = cm.species[t]
            check(
                f"{label}_type{t}_mass",
                rel_error(cur.total_mass, ref.total_mass) <= args.mass_rel_tol,
                f"rel={rel_error(cur.total_mass, ref.total_mass):.3e}",
            )
            check(
                f"{label}_type{t}_momentum",
                abs(cur.px - ref.px) <= args.momentum_abs_tol
                and abs(cur.py - ref.py) <= args.momentum_abs_tol,
                f"dPx={cur.px-ref.px:.3e} dPy={cur.py-ref.py:.3e}",
            )
            check(
                f"{label}_type{t}_thermal_energy",
                rel_error(cur.thermal_krel, ref.thermal_krel) <= args.energy_rel_tol,
                f"rel={rel_error(cur.thermal_krel, ref.thermal_krel):.3e}",
            )

    def physical_field_invariance(label: str, current: DetailedState) -> None:
        check(
            f"{label}_cell_mass_field",
            vectors_close(current.cell_mass, initial.cell_mass, args.cell_mass_abs_tol),
            f"max={max_vector_error(current.cell_mass, initial.cell_mass):.3e}",
        )
        check(
            f"{label}_cell_momentum_field",
            vectors_close(current.cell_px, initial.cell_px, args.cell_momentum_abs_tol)
            and vectors_close(current.cell_py, initial.cell_py, args.cell_momentum_abs_tol),
            f"maxPx={max_vector_error(current.cell_px, initial.cell_px):.3e} "
            f"maxPy={max_vector_error(current.cell_py, initial.cell_py):.3e}",
        )
        check(
            f"{label}_cell_energy_field",
            vectors_close(current.cell_kinetic, initial.cell_kinetic, args.cell_energy_abs_tol)
            and vectors_close(current.cell_krel, initial.cell_krel, args.cell_energy_abs_tol),
            f"maxK={max_vector_error(current.cell_kinetic, initial.cell_kinetic):.3e} "
            f"maxKrel={max_vector_error(current.cell_krel, initial.cell_krel):.3e}",
        )
        for t in (1, 2):
            check(
                f"{label}_type{t}_cell_mass_field",
                vectors_close(
                    current.species_cell_mass[t], initial.species_cell_mass[t], args.cell_mass_abs_tol
                ),
                f"max={max_vector_error(current.species_cell_mass[t], initial.species_cell_mass[t]):.3e}",
            )
            check(
                f"{label}_type{t}_cell_momentum_field",
                vectors_close(
                    current.species_cell_px[t], initial.species_cell_px[t], args.cell_momentum_abs_tol
                )
                and vectors_close(
                    current.species_cell_py[t], initial.species_cell_py[t], args.cell_momentum_abs_tol
                ),
                f"maxPx={max_vector_error(current.species_cell_px[t], initial.species_cell_px[t]):.3e} "
                f"maxPy={max_vector_error(current.species_cell_py[t], initial.species_cell_py[t]):.3e}",
            )
            check(
                f"{label}_type{t}_cell_energy_field",
                vectors_close(
                    current.species_cell_kinetic[t],
                    initial.species_cell_kinetic[t],
                    args.cell_energy_abs_tol,
                )
                and vectors_close(
                    current.species_cell_krel[t], initial.species_cell_krel[t], args.cell_energy_abs_tol
                ),
                f"maxK={max_vector_error(current.species_cell_kinetic[t], initial.species_cell_kinetic[t]):.3e} "
                f"maxKrel={max_vector_error(current.species_cell_krel[t], initial.species_cell_krel[t]):.3e}",
            )

    for case in cases:
        for suffix in ("step1", "short"):
            label = f"{case}_{suffix}"
            conservation(label, states[label])
            physical_field_invariance(label, states[label])

    # No-resampling controls must retain both the numerical representation and
    # the physical fields exactly.
    for label in ("control_step1", "control_short", "none_step1", "none_short"):
        cur = states[label]
        check(
            f"{label}_total_count_pattern_unchanged",
            vectors_equal_int(cur.cell_counts, initial.cell_counts),
            f"var={cur.metrics.occupancy_variance:.6g}",
        )
        for t in (1, 2):
            check(
                f"{label}_type{t}_count_pattern_unchanged",
                vectors_equal_int(cur.species_cell_counts[t], initial.species_cell_counts[t]),
                f"var={cur.metrics.species[t].cell_count_variance:.6g}",
            )

    both1 = states["both_step1"]
    boths = states["both_short"]

    # One population-guard pass applies at most one split or merge per cell.
    # With two symmetric mutable species, the first pass may therefore correct
    # only one of the two types.  This is convergence behaviour, not a physical
    # failure.  The first-step contract is reduction into the gamma±1 band;
    # the short-run contract is the exact 5/5 target.
    check(
        "both_step1_total_inside_guard_band",
        both1.metrics.occupancy_outside_band == 0
        and both1.metrics.occupancy_variance < initial_m.occupancy_variance,
        f"min/max={both1.metrics.occupancy_min}/{both1.metrics.occupancy_max} "
        f"outside={both1.metrics.occupancy_outside_band} "
        f"var={initial_m.occupancy_variance:.6g}->{both1.metrics.occupancy_variance:.6g}",
    )
    check(
        "both_step1_species_counts_bounded",
        all(
            target_species_count - 1 <= n <= target_species_count + 1
            for t in (1, 2)
            for n in both1.species_cell_counts[t]
        ),
        " ".join(
            f"type{t}={both1.metrics.species[t].cell_count_min}/"
            f"{both1.metrics.species[t].cell_count_max}"
            for t in (1, 2)
        ),
    )
    check(
        "both_step1_composition_preserved",
        abs(both1.metrics.type1_fraction_mean - 0.5) <= 1.0e-12
        and both1.metrics.type1_fraction_variance <= 1.0e-20,
        f"mean={both1.metrics.type1_fraction_mean:.6g} "
        f"var={both1.metrics.type1_fraction_variance:.3e}",
    )
    check(
        "both_short_total_count_target",
        all(n == args.gamma for n in boths.cell_counts),
        f"min/max={boths.metrics.occupancy_min}/{boths.metrics.occupancy_max}",
    )
    for t in (1, 2):
        check(
            f"both_short_type{t}_count_target",
            all(n == target_species_count for n in boths.species_cell_counts[t]),
            f"min/max={boths.metrics.species[t].cell_count_min}/"
            f"{boths.metrics.species[t].cell_count_max}",
        )
    check(
        "both_short_composition_preserved",
        abs(boths.metrics.type1_fraction_mean - 0.5) <= 1.0e-12
        and boths.metrics.type1_fraction_variance <= 1.0e-20,
        f"mean={boths.metrics.type1_fraction_mean:.6g} "
        f"var={boths.metrics.type1_fraction_variance:.3e}",
    )

    # With only one mutable species, the disabled type must retain its exact
    # checkerboard.  The mutable type is not required to remain at gamma/2:
    # after convergence it must be the cellwise complement that brings the
    # total population to gamma.
    for case, enabled, disabled in (("type1", 1, 2), ("type2", 2, 1)):
        step1 = states[f"{case}_step1"]
        short = states[f"{case}_short"]
        for suffix, cur in (("step1", step1), ("short", short)):
            label = f"{case}_{suffix}"
            check(
                f"{label}_disabled_type{disabled}_counts_unchanged",
                vectors_equal_int(
                    cur.species_cell_counts[disabled],
                    initial.species_cell_counts[disabled],
                ),
                f"min/max={cur.metrics.species[disabled].cell_count_min}/"
                f"{cur.metrics.species[disabled].cell_count_max}",
            )
        check(
            f"{case}_step1_total_inside_guard_band",
            step1.metrics.occupancy_outside_band == 0
            and step1.metrics.occupancy_variance < initial_m.occupancy_variance,
            f"min/max={step1.metrics.occupancy_min}/{step1.metrics.occupancy_max} "
            f"outside={step1.metrics.occupancy_outside_band} "
            f"var={initial_m.occupancy_variance:.6g}->{step1.metrics.occupancy_variance:.6g}",
        )
        complement_ok = all(
            short.species_cell_counts[enabled][c]
            + short.species_cell_counts[disabled][c]
            == args.gamma
            for c in range(args.nx * args.ny)
        )
        check(
            f"{case}_short_enabled_type{enabled}_complements_disabled",
            complement_ok,
            f"enabled={short.metrics.species[enabled].cell_count_min}/"
            f"{short.metrics.species[enabled].cell_count_max} "
            f"disabled={short.metrics.species[disabled].cell_count_min}/"
            f"{short.metrics.species[disabled].cell_count_max}",
        )
        check(
            f"{case}_short_total_count_target",
            all(n == args.gamma for n in short.cell_counts),
            f"min/max={short.metrics.occupancy_min}/{short.metrics.occupancy_max}",
        )

    def diagnostics(case_key: str, require_guard_activity: bool) -> dict[str, float | int]:
        output = root / cases[case_key] / "output"
        fast = read_csv(output / "cuda_species_resident_fast_path_0490m.csv")
        plan = read_csv(output / "cuda_species_transfer_plan_0490k.csv")
        closure = read_csv(output / "cuda_species_mass_closure_0490i.csv")
        maintenance = read_csv(output / "cuda_species_resident_maintenance_0490n.csv")
        guard = read_csv(output / "cuda_resampling_population_guard_0297.csv")
        operations = sum_int(fast, "operations")
        entries = sum_int(plan, "gpuPlanEntries")
        splits = sum_int(guard, "speciesDirectedSplits0490j")
        merges = sum_int(guard, "speciesDirectedMerges0490j")
        check(f"{case_key}_fast_rows", bool(fast), f"rows={len(fast)}")
        check(f"{case_key}_plan_rows", bool(plan), f"rows={len(plan)}")
        check(f"{case_key}_guard_rows", bool(guard), f"rows={len(guard)}")
        if require_guard_activity:
            check(f"{case_key}_guard_split_activity", splits > 0, f"splits={splits}")
            check(f"{case_key}_guard_merge_activity", merges > 0, f"merges={merges}")
        else:
            check(f"{case_key}_guard_inactive", splits == 0 and merges == 0, f"splits={splits} merges={merges}")
        # A physically neutral population-only correction must not invoke the
        # inter-cell mass-transfer planner or its direct consumer.
        check(f"{case_key}_mass_transfer_plan_inactive", entries == 0, f"entries={entries}")
        check(f"{case_key}_direct_mass_transfer_inactive", operations == 0, f"operations={operations}")
        check(f"{case_key}_invalid_operations_zero", max_int(fast, "invalidOperations") == 0, f"max={max_int(fast, 'invalidOperations')}")
        check(
            f"{case_key}_disabled_species_mutation_zero",
            max_int(fast, "disabledSpeciesMutationCount") == 0,
            f"max={max_int(fast, 'disabledSpeciesMutationCount')}",
        )
        check(
            f"{case_key}_donor_group_underfills_zero",
            max_int(fast, "donorTypeGroupUnderfills") == 0,
            f"max={max_int(fast, 'donorTypeGroupUnderfills')}",
        )
        check(f"{case_key}_closure_invalid_type_zero", max_int(closure, "invalidTypeCount") == 0, f"max={max_int(closure, 'invalidTypeCount')}")
        check(
            f"{case_key}_species_mass_residual",
            max_float(closure, "maxSpeciesMassRelResidual") <= args.mass_rel_tol,
            f"max={max_float(closure, 'maxSpeciesMassRelResidual'):.3e}",
        )
        check(
            f"{case_key}_pool_integrity",
            all(
                max_int(maintenance, c) == 0
                for c in ("activePrefixViolations", "duplicateFreeSlots", "activeAndFreeSlots", "invalidRoleSlots")
            ),
            " ".join(
                f"{c}={max_int(maintenance, c)}"
                for c in ("activePrefixViolations", "duplicateFreeSlots", "activeAndFreeSlots", "invalidRoleSlots")
            ),
        )
        check(
            f"{case_key}_guard_mass_conservation",
            max_float(guard, "maxAbsCellMassError") <= args.cell_mass_abs_tol,
            f"max={max_float(guard, 'maxAbsCellMassError'):.3e}",
        )
        check(
            f"{case_key}_guard_momentum_conservation",
            max_float(guard, "maxAbsCellMomentumError") <= args.cell_momentum_abs_tol,
            f"max={max_float(guard, 'maxAbsCellMomentumError'):.3e}",
        )
        return {
            "guard_splits": splits,
            "guard_merges": merges,
            "plan_entries": entries,
            "direct_operations": operations,
            "guard_kernel_seconds_max": max_float(guard, "kernelSeconds"),
        }

    diagnostic_summary = {
        "both": diagnostics("both", True),
        "type1": diagnostics("type1", True),
        "type2": diagnostics("type2", True),
        "none": diagnostics("none", False),
    }

    failures = [c for c in checks if not c[1]]
    status = "PASS" if not failures else "FAIL"
    report = {
        "status": status,
        "configuration": {
            "nx": args.nx,
            "ny": args.ny,
            "gamma": args.gamma,
            "target_cell_mass": args.target_cell_mass,
            "species_target_cell_mass": args.species_target_cell_mass,
            "short_step": args.short_step,
            "types": [1, 2],
        },
        "metrics": {name: asdict(state.metrics) for name, state in states.items()},
        "checks": [
            {"name": name, "status": "PASS" if ok else "FAIL", "detail": detail}
            for name, ok, detail in checks
        ],
        "diagnostic_summary": diagnostic_summary,
    }

    json_path = root / "physics_0493g.json"
    csv_path = root / "physics_0493g_checks.csv"
    md_path = root / "physics_0493g.md"
    json_path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    with csv_path.open("w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["check", "status", "detail"])
        for name, ok, detail in checks:
            w.writerow([name, "PASS" if ok else "FAIL", detail])

    lines = [
        "# 0493g physically neutral two-species resampling smoke",
        "",
        f"**Status: {status}**",
        "",
        "## State summary",
        "",
        "| State | total count var | cell mass var | type 1 count var | type 2 count var | mass | Px | Py | Krel |",
        "|---|---:|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for name in (
        "initial",
        "control_step1",
        "both_step1",
        "type1_step1",
        "type2_step1",
        "none_step1",
        "both_short",
    ):
        m = states[name].metrics
        lines.append(
            f"| {name} | {m.occupancy_variance:.9g} | {m.mass_variance:.9g} | "
            f"{m.species[1].cell_count_variance:.9g} | {m.species[2].cell_count_variance:.9g} | "
            f"{m.total_mass:.9g} | {m.px:.9g} | {m.py:.9g} | {m.thermal_krel:.9g} |"
        )
    lines.extend(["", "## Checks", "", "| Check | Status | Detail |", "|---|---|---|"])
    for name, ok, detail in checks:
        lines.append(f"| `{name}` | {'PASS' if ok else 'FAIL'} | {detail} |")
    md_path.write_text("\n".join(lines) + "\n")

    for name, ok, detail in checks:
        print(f"[0493g-audit] {name}={'PASS' if ok else 'FAIL'} {detail}")
    print(
        "[0493g-audit] "
        f"initialCountVar={initial_m.occupancy_variance:.6g} "
        f"initialMassVar={initial_m.mass_variance:.3e} "
        f"bothCountVar={both1.metrics.occupancy_variance:.6g} "
        f"bothMassVar={both1.metrics.mass_variance:.3e} "
        f"status={status}"
    )
    print(f"[0493g-audit] json={json_path}")
    print(f"[0493g-audit] markdown={md_path}")
    return 0 if status == "PASS" else 2


if __name__ == "__main__":
    raise SystemExit(main())
