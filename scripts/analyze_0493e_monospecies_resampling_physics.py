#!/usr/bin/env python3
"""Analyze the 0493e mono-species resampling physics smoke test.

The test is intentionally macroscopic/statistical.  It does not require two
runs to follow the same particle trajectory bit-for-bit.  It verifies the
one-species specialization of the current CUDA-resident species-resampling
path against a no-resampling control initialized from the same state.
"""

from __future__ import annotations

import argparse
import csv
import json
import math
import struct
import sys
from dataclasses import dataclass, asdict
from pathlib import Path
from typing import Iterable


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
    mass_outside_band: int
    checkerboard_occupancy_amplitude: float
    checkerboard_mass_amplitude: float


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser()
    p.add_argument("--root", type=Path, required=True)
    p.add_argument("--nx", type=int, required=True)
    p.add_argument("--ny", type=int, required=True)
    p.add_argument("--gamma", type=int, required=True)
    p.add_argument("--mass", type=float, default=1.0)
    p.add_argument("--short-step", type=int, default=10)
    p.add_argument("--mass-rel-tol", type=float, default=1.0e-12)
    p.add_argument("--momentum-abs-tol", type=float, default=1.0e-10)
    p.add_argument("--energy-rel-tol", type=float, default=1.0e-6)
    p.add_argument("--baseline-rel-tol", type=float, default=1.0e-12)
    p.add_argument("--variance-ratio-max", type=float, default=0.95)
    p.add_argument("--short-variance-ratio-max", type=float, default=1.05)
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

    reserved_bytes = 8 * int(reserved_count)
    if len(data) < offset + reserved_bytes:
        raise ValueError(f"truncated reserved header in {path}")
    offset += reserved_bytes

    def read_array(fmt: str, count: int) -> list[float] | list[int]:
        nonlocal offset
        size = struct.calcsize(f"<{count}{fmt}")
        if len(data) < offset + size:
            raise ValueError(f"truncated array in {path}")
        values = list(struct.unpack_from(f"<{count}{fmt}", data, offset))
        offset += size
        return values

    count = int(n)
    result = {
        "x": read_array("d", count),
        "y": read_array("d", count),
        "vx": read_array("d", count),
        "vy": read_array("d", count),
        "type": read_array("I", count),
        "mass": read_array("d", count),
        "role": read_array("B", count),
    }
    return result


def state_metrics(path: Path, nx: int, ny: int, gamma: int, particle_mass: float) -> StateMetrics:
    s = read_state(path)
    x = s["x"]
    y = s["y"]
    vx = s["vx"]
    vy = s["vy"]
    typ = s["type"]
    mass = s["mass"]
    role = s["role"]

    active = [i for i, r in enumerate(role) if int(r) == 1]
    inactive = len(role) - len(active)
    if not active:
        raise ValueError(f"no fluid particles in {path}")

    total_mass = math.fsum(float(mass[i]) for i in active)
    px = math.fsum(float(mass[i]) * float(vx[i]) for i in active)
    py = math.fsum(float(mass[i]) * float(vy[i]) for i in active)
    mean_vx = px / total_mass
    mean_vy = py / total_mass
    kinetic = math.fsum(
        0.5 * float(mass[i]) * (float(vx[i]) ** 2 + float(vy[i]) ** 2)
        for i in active
    )
    thermal_krel = math.fsum(
        0.5
        * float(mass[i])
        * ((float(vx[i]) - mean_vx) ** 2 + (float(vy[i]) - mean_vy) ** 2)
        for i in active
    )

    cells = nx * ny
    counts = [0] * cells
    cell_mass = [0.0] * cells
    for i in active:
        # Periodic cell assignment.  fmod protects against rare roundoff at L=1.
        xx = float(x[i]) % 1.0
        yy = float(y[i]) % 1.0
        ci = min(nx - 1, int(math.floor(xx * nx)))
        cj = min(ny - 1, int(math.floor(yy * ny)))
        c = cj * nx + ci
        counts[c] += 1
        cell_mass[c] += float(mass[i])

    count_mean = math.fsum(counts) / cells
    mass_mean = math.fsum(cell_mass) / cells
    count_var = math.fsum((v - count_mean) ** 2 for v in counts) / cells
    mass_var = math.fsum((v - mass_mean) ** 2 for v in cell_mass) / cells
    nmin, nmax = gamma - 1, gamma + 1
    mass_min_band = nmin * particle_mass
    mass_max_band = nmax * particle_mass

    checker_count = 0.0
    checker_mass = 0.0
    for j in range(ny):
        for i in range(nx):
            c = j * nx + i
            sign = -1.0 if ((i + j) & 1) else 1.0
            checker_count += sign * (counts[c] - count_mean)
            checker_mass += sign * (cell_mass[c] - mass_mean)
    checker_count /= cells
    checker_mass /= cells

    return StateMetrics(
        path=str(path),
        fluid_particles=len(active),
        inactive_particles=inactive,
        fluid_types=sorted({int(typ[i]) for i in active}),
        total_mass=total_mass,
        px=px,
        py=py,
        mean_vx=mean_vx,
        mean_vy=mean_vy,
        kinetic=kinetic,
        thermal_krel=thermal_krel,
        occupancy_mean=count_mean,
        occupancy_variance=count_var,
        occupancy_min=min(counts),
        occupancy_max=max(counts),
        occupancy_outside_band=sum(v < nmin or v > nmax for v in counts),
        mass_mean=mass_mean,
        mass_variance=mass_var,
        mass_min=min(cell_mass),
        mass_max=max(cell_mass),
        mass_outside_band=sum(v < mass_min_band or v > mass_max_band for v in cell_mass),
        checkerboard_occupancy_amplitude=checker_count,
        checkerboard_mass_amplitude=checker_mass,
    )


def read_csv(path: Path) -> list[dict[str, str]]:
    if not path.exists():
        return []
    with path.open(newline="") as f:
        return list(csv.DictReader(f))


def max_int(rows: Iterable[dict[str, str]], column: str) -> int:
    values: list[int] = []
    for row in rows:
        raw = row.get(column, "")
        if raw == "":
            continue
        values.append(int(float(raw)))
    return max(values, default=0)


def sum_int(rows: Iterable[dict[str, str]], column: str) -> int:
    total = 0
    for row in rows:
        raw = row.get(column, "")
        if raw != "":
            total += int(float(raw))
    return total


def max_float(rows: Iterable[dict[str, str]], column: str) -> float:
    values: list[float] = []
    for row in rows:
        raw = row.get(column, "")
        if raw == "":
            continue
        values.append(abs(float(raw)))
    return max(values, default=0.0)


def rel_error(a: float, b: float) -> float:
    return abs(a - b) / max(abs(a), abs(b), 1.0e-300)


def ratio(value: float, reference: float) -> float:
    if reference == 0.0:
        return 0.0 if value == 0.0 else math.inf
    return value / reference


def main() -> int:
    args = parse_args()
    root = args.root.resolve()
    initial_path = root / "init" / "mono_checkerboard_0493e.smpcd"
    off_path = root / "00_no_resampling" / "output" / "state_step_00000001.smpcd"
    on1_path = root / "01_resampling_on" / "output" / "state_step_00000001.smpcd"
    on_short_path = root / "01_resampling_on" / "output" / f"state_step_{args.short_step:08d}.smpcd"

    required = [initial_path, off_path, on1_path, on_short_path]
    missing = [p for p in required if not p.exists()]
    if missing:
        print("[0493e-audit] FAIL missing state dumps:", file=sys.stderr)
        for path in missing:
            print(f"  {path}", file=sys.stderr)
        return 2

    metrics = {
        "initial": state_metrics(initial_path, args.nx, args.ny, args.gamma, args.mass),
        "off_step1": state_metrics(off_path, args.nx, args.ny, args.gamma, args.mass),
        "on_step1": state_metrics(on1_path, args.nx, args.ny, args.gamma, args.mass),
        "on_short": state_metrics(on_short_path, args.nx, args.ny, args.gamma, args.mass),
    }

    checks: list[tuple[str, bool, str]] = []

    def check(name: str, ok: bool, detail: str) -> None:
        checks.append((name, bool(ok), detail))

    initial = metrics["initial"]
    off = metrics["off_step1"]
    on1 = metrics["on_step1"]
    short = metrics["on_short"]

    # Construction/control case: no resampling must not alter the designed cell pattern.
    check("initial_single_type", initial.fluid_types == [1], f"types={initial.fluid_types}")
    check("off_single_type", off.fluid_types == [1], f"types={off.fluid_types}")
    check("on_step1_single_type", on1.fluid_types == [1], f"types={on1.fluid_types}")
    check("on_short_single_type", short.fluid_types == [1], f"types={short.fluid_types}")
    check(
        "off_mass_conservation",
        rel_error(off.total_mass, initial.total_mass) <= args.mass_rel_tol,
        f"initial={initial.total_mass:.17g} off={off.total_mass:.17g}",
    )
    check(
        "off_momentum_conservation",
        abs(off.px - initial.px) <= args.momentum_abs_tol
        and abs(off.py - initial.py) <= args.momentum_abs_tol,
        f"dPx={off.px-initial.px:.3e} dPy={off.py-initial.py:.3e}",
    )
    check(
        "off_thermal_energy_conservation",
        rel_error(off.thermal_krel, initial.thermal_krel) <= args.baseline_rel_tol,
        f"rel={rel_error(off.thermal_krel, initial.thermal_krel):.3e}",
    )
    check(
        "off_occupancy_pattern_unchanged",
        abs(off.occupancy_variance - initial.occupancy_variance) <= args.baseline_rel_tol
        and off.occupancy_outside_band == initial.occupancy_outside_band,
        (
            f"variance={initial.occupancy_variance:.6g}->{off.occupancy_variance:.6g} "
            f"outside={initial.occupancy_outside_band}->{off.occupancy_outside_band}"
        ),
    )

    for label, current in (("on_step1", on1), ("on_short", short)):
        check(
            f"{label}_mass_conservation",
            rel_error(current.total_mass, initial.total_mass) <= args.mass_rel_tol,
            f"rel={rel_error(current.total_mass, initial.total_mass):.3e}",
        )
        check(
            f"{label}_momentum_conservation",
            abs(current.px - initial.px) <= args.momentum_abs_tol
            and abs(current.py - initial.py) <= args.momentum_abs_tol,
            f"dPx={current.px-initial.px:.3e} dPy={current.py-initial.py:.3e}",
        )
        check(
            f"{label}_thermal_energy_conservation",
            rel_error(current.thermal_krel, initial.thermal_krel) <= args.energy_rel_tol,
            f"rel={rel_error(current.thermal_krel, initial.thermal_krel):.3e}",
        )
        check(
            f"{label}_mean_velocity",
            abs(current.mean_vx - initial.mean_vx) <= args.momentum_abs_tol
            and abs(current.mean_vy - initial.mean_vy) <= args.momentum_abs_tol,
            f"dUx={current.mean_vx-initial.mean_vx:.3e} dUy={current.mean_vy-initial.mean_vy:.3e}",
        )

    check(
        "step1_occupancy_variance_reduced",
        ratio(on1.occupancy_variance, initial.occupancy_variance) <= args.variance_ratio_max,
        f"ratio={ratio(on1.occupancy_variance, initial.occupancy_variance):.6g}",
    )
    check(
        "step1_mass_variance_reduced",
        ratio(on1.mass_variance, initial.mass_variance) <= args.variance_ratio_max,
        f"ratio={ratio(on1.mass_variance, initial.mass_variance):.6g}",
    )
    check(
        "step1_outside_band_reduced",
        on1.occupancy_outside_band < initial.occupancy_outside_band
        and on1.mass_outside_band < initial.mass_outside_band,
        (
            f"occupancy={initial.occupancy_outside_band}->{on1.occupancy_outside_band} "
            f"mass={initial.mass_outside_band}->{on1.mass_outside_band}"
        ),
    )
    check(
        "step1_checkerboard_reduced",
        abs(on1.checkerboard_mass_amplitude) < abs(initial.checkerboard_mass_amplitude),
        (
            f"massAmplitude={initial.checkerboard_mass_amplitude:.6g}"
            f"->{on1.checkerboard_mass_amplitude:.6g}"
        ),
    )
    check(
        "short_no_variance_blowup",
        ratio(short.mass_variance, initial.mass_variance) <= args.short_variance_ratio_max
        and ratio(short.occupancy_variance, initial.occupancy_variance) <= args.short_variance_ratio_max,
        (
            f"massRatio={ratio(short.mass_variance, initial.mass_variance):.6g} "
            f"occupancyRatio={ratio(short.occupancy_variance, initial.occupancy_variance):.6g}"
        ),
    )

    output = root / "01_resampling_on" / "output"
    fast = read_csv(output / "cuda_species_resident_fast_path_0490m.csv")
    plan = read_csv(output / "cuda_species_transfer_plan_0490k.csv")
    closure = read_csv(output / "cuda_species_mass_closure_0490i.csv")
    maintenance = read_csv(output / "cuda_species_resident_maintenance_0490n.csv")
    guard = read_csv(output / "cuda_resampling_population_guard_0297.csv")

    check("direct_fast_path_rows", bool(fast), f"rows={len(fast)}")
    check("transfer_plan_rows", bool(plan), f"rows={len(plan)}")
    check("population_guard_rows", bool(guard), f"rows={len(guard)}")
    check("direct_activity", sum_int(fast, "operations") > 0, f"operations={sum_int(fast, 'operations')}")
    check("plan_activity", sum_int(plan, "gpuPlanEntries") > 0, f"entries={sum_int(plan, 'gpuPlanEntries')}")
    check("moved_mass_activity", max_float(fast, "movedMass") > 0.0, f"maxMovedMass={max_float(fast, 'movedMass'):.6g}")
    check("invalid_operations_zero", max_int(fast, "invalidOperations") == 0, f"max={max_int(fast, 'invalidOperations')}")
    check(
        "disabled_species_mutation_zero",
        max_int(fast, "disabledSpeciesMutationCount") == 0,
        f"max={max_int(fast, 'disabledSpeciesMutationCount')}",
    )
    check(
        "donor_group_underfills_zero",
        max_int(fast, "donorTypeGroupUnderfills") == 0,
        f"max={max_int(fast, 'donorTypeGroupUnderfills')}",
    )
    check("closure_invalid_type_zero", max_int(closure, "invalidTypeCount") == 0, f"max={max_int(closure, 'invalidTypeCount')}")
    check(
        "species_mass_residual",
        max_float(closure, "maxSpeciesMassRelResidual") <= args.mass_rel_tol,
        f"max={max_float(closure, 'maxSpeciesMassRelResidual'):.3e}",
    )
    check(
        "pool_integrity",
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
        "guard_mass_conservation",
        max_float(guard, "maxAbsCellMassError") <= 1.0e-8,
        f"maxCellMassError={max_float(guard, 'maxAbsCellMassError'):.3e}",
    )
    check(
        "guard_momentum_conservation",
        max_float(guard, "maxAbsCellMomentumError") <= 1.0e-8,
        f"maxCellMomentumError={max_float(guard, 'maxAbsCellMomentumError'):.3e}",
    )

    failures = [item for item in checks if not item[1]]
    status = "PASS" if not failures else "FAIL"

    report = {
        "status": status,
        "configuration": {
            "nx": args.nx,
            "ny": args.ny,
            "gamma": args.gamma,
            "particle_mass": args.mass,
            "short_step": args.short_step,
        },
        "metrics": {name: asdict(value) for name, value in metrics.items()},
        "checks": [
            {"name": name, "status": "PASS" if ok else "FAIL", "detail": detail}
            for name, ok, detail in checks
        ],
        "diagnostic_summary": {
            "plan_entries_sum": sum_int(plan, "gpuPlanEntries"),
            "operations_sum": sum_int(fast, "operations"),
            "entry_mass_shortfalls_sum": sum_int(fast, "entryMassShortfalls"),
            "moved_mass_max_abs": max_float(fast, "movedMass"),
            "kernel_seconds_max": max_float(fast, "kernelSeconds"),
        },
    }

    json_path = root / "physics_0493e.json"
    csv_path = root / "physics_0493e_checks.csv"
    md_path = root / "physics_0493e.md"
    json_path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    with csv_path.open("w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["check", "status", "detail"])
        for name, ok, detail in checks:
            w.writerow([name, "PASS" if ok else "FAIL", detail])

    lines = [
        "# 0493e mono-species resampling physics smoke",
        "",
        f"**Status: {status}**",
        "",
        "## Macroscopic metrics",
        "",
        "| State | mass | Px | Py | Krel | occupancy variance | mass variance | outside band |",
        "|---|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for name in ("initial", "off_step1", "on_step1", "on_short"):
        m = metrics[name]
        lines.append(
            f"| {name} | {m.total_mass:.9g} | {m.px:.9g} | {m.py:.9g} | "
            f"{m.thermal_krel:.9g} | {m.occupancy_variance:.9g} | "
            f"{m.mass_variance:.9g} | {m.occupancy_outside_band} |"
        )
    lines.extend(["", "## Checks", "", "| Check | Status | Detail |", "|---|---|---|"])
    for name, ok, detail in checks:
        lines.append(f"| `{name}` | {'PASS' if ok else 'FAIL'} | {detail} |")
    md_path.write_text("\n".join(lines) + "\n")

    for name, ok, detail in checks:
        print(f"[0493e-audit] {name}={'PASS' if ok else 'FAIL'} {detail}")
    print(
        "[0493e-audit] "
        f"initialVar={initial.mass_variance:.6g} step1Var={on1.mass_variance:.6g} "
        f"shortVar={short.mass_variance:.6g} operations={sum_int(fast, 'operations')} "
        f"status={status}"
    )
    print(f"[0493e-audit] json={json_path}")
    print(f"[0493e-audit] markdown={md_path}")

    return 0 if status == "PASS" else 2


if __name__ == "__main__":
    raise SystemExit(main())
