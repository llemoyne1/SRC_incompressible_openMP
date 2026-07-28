#!/usr/bin/env python3
"""Analyze the 0493w0 Darcy kinetic-regime sweep.

The script combines:
- input dimensionless groups;
- final global runtime diagnostics;
- final support/geometry diagnostics;
- direct particle deposits from the final .smpcd dump;
- spatial metrics in the cylinder interface, wake, upstream control, inlet lip,
  and external-wall halo.

The Reynolds number is reported with a standard 2-D SRD/MPCD random-grid-shift
viscosity estimate. It is deliberately labelled an estimate: a Poiseuille
calibration remains the preferred source for quantitative hydrodynamic use.
The Mach number is an ideal-gas 2-D proxy, c_s=sqrt(2 kBT/m).
"""

from __future__ import annotations

import argparse
import csv
import math
import re
import struct
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, Iterable, List, Mapping, MutableMapping, Optional, Sequence, Tuple

import numpy as np


MAGIC = b"SRCMPCD_STATE\x00\x00\x00"
ROLE_FLUID = 1


@dataclass(frozen=True)
class Case:
    case_id: str
    nx: int
    ny: int
    dt: float
    kbt: float
    alpha: float
    steps: int
    t_end: float
    run_root: Path
    note: str


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--sweep-root", required=True, type=Path)
    parser.add_argument("--manifest", type=Path)
    parser.add_argument("--lx", type=float, default=1.0)
    parser.add_argument("--ly", type=float, default=1.0)
    parser.add_argument("--gamma", type=float, default=20.0)
    parser.add_argument("--particle-mass", type=float, default=1.0)
    parser.add_argument("--u0", type=float, default=0.15)
    parser.add_argument("--rotation-angle", type=float, default=math.pi / 2.0)
    parser.add_argument("--cylinder-cx", type=float, default=0.50)
    parser.add_argument("--cylinder-cy", type=float, default=0.50)
    parser.add_argument("--cylinder-r", type=float, default=0.12)
    parser.add_argument("--chi-fluid-threshold", type=float, default=0.05)
    parser.add_argument("--support-nmin", type=int, default=12)
    parser.add_argument("--inlet-smin", type=float, default=0.70)
    parser.add_argument("--strict", action="store_true")
    parser.add_argument("--preflight-only", action="store_true")
    return parser.parse_args()


def read_manifest(path: Path) -> List[Case]:
    cases: List[Case] = []
    with path.open(newline="") as stream:
        reader = csv.DictReader(stream)
        required = {
            "case_id", "nx", "ny", "dt", "kbt", "alpha", "steps",
            "t_end", "run_root", "note",
        }
        missing = required.difference(reader.fieldnames or [])
        if missing:
            raise RuntimeError(f"manifest missing columns: {sorted(missing)}")
        for row in reader:
            cases.append(
                Case(
                    case_id=row["case_id"],
                    nx=int(row["nx"]),
                    ny=int(row["ny"]),
                    dt=float(row["dt"]),
                    kbt=float(row["kbt"]),
                    alpha=float(row["alpha"]),
                    steps=int(row["steps"]),
                    t_end=float(row["t_end"]),
                    run_root=Path(row["run_root"]),
                    note=row["note"],
                )
            )
    return cases


def find_single(root: Path, patterns: Sequence[str], required: bool = True) -> Optional[Path]:
    matches: List[Path] = []
    for pattern in patterns:
        matches.extend(root.glob(pattern))
    unique = sorted(set(matches))
    if not unique:
        if required:
            raise FileNotFoundError(f"no file under {root} for patterns {patterns}")
        return None
    if len(unique) > 1:
        # Final state is selected by highest step when several dumps exist.
        if any("state_step_" in item.name for item in unique):
            def step_key(item: Path) -> int:
                match = re.search(r"state_step_(\d+)", item.name)
                return int(match.group(1)) if match else -1
            return max(unique, key=step_key)
        raise RuntimeError(f"multiple files under {root} for patterns {patterns}: {unique}")
    return unique[0]


def read_last_csv_row(path: Optional[Path]) -> Dict[str, str]:
    if path is None or not path.is_file():
        return {}
    last: Dict[str, str] = {}
    with path.open(newline="") as stream:
        for row in csv.DictReader(stream):
            last = row
    return last


def f(row: Mapping[str, str], key: str, default: float = math.nan) -> float:
    try:
        raw = row.get(key, "")
        return float(raw) if raw not in ("", None) else default
    except (TypeError, ValueError):
        return default


def read_smpcd(path: Path) -> Dict[str, np.ndarray]:
    with path.open("rb") as stream:
        magic = stream.read(16)
        if magic != MAGIC:
            raise RuntimeError(f"invalid .smpcd magic: {path}")
        header = stream.read(4 * 4 + 8 + 4 * 4 + 8 * 8)
        if len(header) != 104:
            raise RuntimeError(f"truncated .smpcd header: {path}")
        offset = 0
        version, endian, dim, layout = struct.unpack_from("<IIII", header, offset)
        offset += 16
        (np_count,) = struct.unpack_from("<Q", header, offset)
        offset += 8
        has_type, has_mass, real_size, type_size = struct.unpack_from("<IIII", header, offset)
        offset += 16
        reserved = struct.unpack_from("<8Q", header, offset)
        if version not in (1, 2):
            raise RuntimeError(f"unsupported .smpcd version={version}: {path}")
        if endian != 0x01020304 or dim != 2 or layout != 1:
            raise RuntimeError(f"unsupported .smpcd header values: {path}")
        if has_type != 1 or has_mass != 1 or real_size != 8 or type_size != 4:
            raise RuntimeError(f"unsupported .smpcd payload layout: {path}")
        n = int(np_count)
        x = np.fromfile(stream, dtype="<f8", count=n)
        y = np.fromfile(stream, dtype="<f8", count=n)
        vx = np.fromfile(stream, dtype="<f8", count=n)
        vy = np.fromfile(stream, dtype="<f8", count=n)
        ptype = np.fromfile(stream, dtype="<u4", count=n)
        mass = np.fromfile(stream, dtype="<f8", count=n)
        if version == 2:
            if reserved[0] != 1:
                raise RuntimeError(f"unsupported V2 role flag: {path}")
            role = np.fromfile(stream, dtype="u1", count=n)
        else:
            role = np.full(n, ROLE_FLUID, dtype=np.uint8)
    arrays = (x, y, vx, vy, ptype, mass, role)
    if any(array.size != n for array in arrays):
        raise RuntimeError(f"truncated .smpcd payload: {path}")
    return {
        "x": x,
        "y": y,
        "vx": vx,
        "vy": vy,
        "type": ptype,
        "mass": mass,
        "role": role,
    }


def read_chi(path: Path, nx: int, ny: int) -> np.ndarray:
    chi = np.fromfile(path, dtype="<f4")
    expected = nx * ny
    if chi.size != expected:
        raise RuntimeError(f"chi size mismatch {chi.size} != {expected}: {path}")
    return chi.reshape((ny, nx)).astype(np.float64)


def viscosity_srd_2d(
    *, cell_size: float, dt: float, kbt: float, particle_mass: float,
    gamma: float, rotation_angle: float,
) -> Tuple[float, float, float]:
    """Return (total, kinetic, collisional) 2-D SRD estimates.

    This is a regime-positioning estimate for random grid shift and Poisson cell
    occupancy. The measured Poiseuille viscosity should supersede it whenever
    available.
    """
    occupancy_factor = (gamma - 1.0 + math.exp(-gamma)) / gamma
    angle_factor = 1.0 - math.cos(rotation_angle)
    if occupancy_factor <= 0.0 or angle_factor <= 0.0 or dt <= 0.0:
        return (math.nan, math.nan, math.nan)
    nu_kin = (kbt * dt / particle_mass) * (
        1.0 / (occupancy_factor * angle_factor) - 0.5
    )
    nu_col = (
        cell_size * cell_size / (12.0 * dt)
        * occupancy_factor * angle_factor
    )
    return (nu_kin + nu_col, nu_kin, nu_col)


def mach_class(value: float) -> str:
    if not math.isfinite(value):
        return "unknown"
    if value < 0.30:
        return "low_Mach"
    if value < 0.80:
        return "moderately_compressible"
    return "strongly_compressible_proxy"


def reynolds_class(value: float) -> str:
    if not math.isfinite(value):
        return "unknown"
    if value < 1.0:
        return "creeping"
    if value < 40.0:
        return "laminar_steady_wake_range"
    if value < 200.0:
        return "2D_unsteady_wake_plausible"
    return "beyond_low_Re_2D_reference"


def streaming_class(value: float) -> str:
    if not math.isfinite(value):
        return "unknown"
    if value < 0.02:
        return "very_short_per_step"
    if value < 0.10:
        return "short_to_moderate"
    return "substantial_cell_crossing"


def dimensionless(case: Case, args: argparse.Namespace, kbt_for_model: Optional[float] = None,
                  velocity_for_model: Optional[float] = None) -> Dict[str, float | str]:
    a = min(args.lx / case.nx, args.ly / case.ny)
    diameter = 2.0 * args.cylinder_r
    kbt = case.kbt if kbt_for_model is None or not math.isfinite(kbt_for_model) else kbt_for_model
    velocity = args.u0 if velocity_for_model is None or not math.isfinite(velocity_for_model) else abs(velocity_for_model)
    nu, nu_kin, nu_col = viscosity_srd_2d(
        cell_size=a,
        dt=case.dt,
        kbt=kbt,
        particle_mass=args.particle_mass,
        gamma=args.gamma,
        rotation_angle=args.rotation_angle,
    )
    vth_1d = math.sqrt(max(kbt, 0.0) / args.particle_mass)
    vth_2d_rms = math.sqrt(2.0) * vth_1d
    cs_ideal_2d = vth_2d_rms
    ma = velocity / cs_ideal_2d if cs_ideal_2d > 0.0 else math.inf
    re_d = velocity * diameter / nu if nu > 0.0 else math.inf
    lambda_1d = vth_1d * case.dt
    lambda_2d = vth_2d_rms * case.dt
    dynamic_to_ideal_pressure = (
        0.5 * args.particle_mass * velocity * velocity / kbt
        if kbt > 0.0 else math.inf
    )
    darcy_relaxation = case.alpha * case.dt
    darcy_number = nu / (case.alpha * diameter * diameter) if case.alpha > 0.0 else math.inf
    return {
        "cellSize": a,
        "cylinderDiameter": diameter,
        "cylinderCells": diameter / a,
        "nuSrd2dEstimate": nu,
        "nuSrd2dKinetic": nu_kin,
        "nuSrd2dCollisional": nu_col,
        "kineticViscosityFraction": nu_kin / nu if nu > 0.0 else math.nan,
        "ReCylinderEstimate": re_d,
        "ReClass": reynolds_class(re_d),
        "soundSpeedIdeal2dProxy": cs_ideal_2d,
        "MachIdeal2dProxy": ma,
        "MachClass": mach_class(ma),
        "flowToThermal1dRatio": velocity / vth_1d if vth_1d > 0.0 else math.inf,
        "dynamicToIdealPressureProxy": dynamic_to_ideal_pressure,
        "thermalMeanFreePath1d": lambda_1d,
        "thermalMeanFreePath1dOverCell": lambda_1d / a,
        "thermalDisplacement2dRmsOverCell": lambda_2d / a,
        "streamingClass": streaming_class(lambda_2d / a),
        "advectiveCFLCell": velocity * case.dt / a,
        "thermalKnudsenCylinderProxy": lambda_1d / diameter,
        "convectiveTimeUnits": case.t_end * args.u0 / diameter,
        "stepsPerCylinderTransit": diameter / (args.u0 * case.dt),
        "darcyAlphaDt": darcy_relaxation,
        "darcyRelaxationSteps": 1.0 / darcy_relaxation if darcy_relaxation > 0.0 else math.inf,
        "darcyNumberEstimate": darcy_number,
    }


def deposit_state(
    state: Mapping[str, np.ndarray], nx: int, ny: int, lx: float, ly: float,
) -> Dict[str, np.ndarray]:
    fluid = state["role"] == ROLE_FLUID
    x = state["x"][fluid]
    y = state["y"][fluid]
    vx = state["vx"][fluid]
    vy = state["vy"][fluid]
    mass = state["mass"][fluid]
    ix = np.floor(x / lx * nx).astype(np.int64)
    iy = np.floor(y / ly * ny).astype(np.int64)
    ix = np.clip(ix, 0, nx - 1)
    iy = np.clip(iy, 0, ny - 1)
    cell = iy * nx + ix
    ncell = nx * ny
    count = np.bincount(cell, minlength=ncell).astype(np.int64)
    cell_mass = np.bincount(cell, weights=mass, minlength=ncell)
    px = np.bincount(cell, weights=mass * vx, minlength=ncell)
    py = np.bincount(cell, weights=mass * vy, minlength=ncell)
    ux = np.divide(px, cell_mass, out=np.zeros_like(px), where=cell_mass > 0.0)
    uy = np.divide(py, cell_mass, out=np.zeros_like(py), where=cell_mass > 0.0)
    dvx = vx - ux[cell]
    dvy = vy - uy[cell]
    thermal_x = np.bincount(cell, weights=mass * dvx * dvx, minlength=ncell)
    thermal_y = np.bincount(cell, weights=mass * dvy * dvy, minlength=ncell)
    return {
        "fluid_mask_particles": fluid,
        "particle_x": x,
        "particle_y": y,
        "particle_vx": vx,
        "particle_vy": vy,
        "particle_mass": mass,
        "particle_cell": cell,
        "count": count.reshape((ny, nx)),
        "mass": cell_mass.reshape((ny, nx)),
        "px": px.reshape((ny, nx)),
        "py": py.reshape((ny, nx)),
        "ux": ux.reshape((ny, nx)),
        "uy": uy.reshape((ny, nx)),
        "thermal_x": thermal_x.reshape((ny, nx)),
        "thermal_y": thermal_y.reshape((ny, nx)),
    }


def zone_masks(case: Case, args: argparse.Namespace, chi: np.ndarray) -> Dict[str, np.ndarray]:
    dx = args.lx / case.nx
    dy = args.ly / case.ny
    a = max(dx, dy)
    xc = (np.arange(case.nx) + 0.5) * dx
    yc = (np.arange(case.ny) + 0.5) * dy
    xg, yg = np.meshgrid(xc, yc)
    r = np.hypot(xg - args.cylinder_cx, yg - args.cylinder_cy)
    diameter = 2.0 * args.cylinder_r
    fluid = chi >= args.chi_fluid_threshold
    interface = fluid & (r >= args.cylinder_r) & (r < args.cylinder_r + 2.0 * a)
    solid_halo = fluid & (r >= args.cylinder_r) & (r < args.cylinder_r + 4.0 * a)
    wake_near = (
        fluid
        & (xg >= args.cylinder_cx + args.cylinder_r)
        & (xg < args.cylinder_cx + args.cylinder_r + diameter)
        & (np.abs(yg - args.cylinder_cy) <= args.cylinder_r)
    )
    wake_long = (
        fluid
        & (xg >= args.cylinder_cx + args.cylinder_r)
        & (xg < min(args.lx, args.cylinder_cx + args.cylinder_r + 2.0 * diameter))
        & (np.abs(yg - args.cylinder_cy) <= args.cylinder_r)
    )
    upstream = (
        fluid
        & (xg >= max(0.0, args.cylinder_cx - 2.0 * diameter))
        & (xg < args.cylinder_cx - args.cylinder_r)
        & (np.abs(yg - args.cylinder_cy) <= args.cylinder_r)
    )
    wake_side_control = (
        fluid
        & (xg >= args.cylinder_cx + args.cylinder_r)
        & (xg < min(args.lx, args.cylinder_cx + args.cylinder_r + 2.0 * diameter))
        & (np.abs(yg - args.cylinder_cy) > args.cylinder_r)
        & (np.abs(yg - args.cylinder_cy) <= 2.0 * args.cylinder_r)
    )
    cylinder_shoulders = (
        fluid
        & (xg >= args.cylinder_cx - args.cylinder_r)
        & (xg <= args.cylinder_cx + args.cylinder_r)
        & (np.abs(yg - args.cylinder_cy) > args.cylinder_r)
        & (np.abs(yg - args.cylinder_cy) <= 2.0 * args.cylinder_r)
    )
    inlet_lip_width = max(2.0 * a, 0.02 * args.ly)
    inlet_lip = (
        fluid
        & (xg < 0.20 * args.lx)
        & (np.abs(yg - args.inlet_smin) <= inlet_lip_width)
    )
    outer_wall_halo = fluid & (
        (yg < 2.0 * a) | (yg > args.ly - 2.0 * a)
        | (xg < 2.0 * a) | (xg > args.lx - 2.0 * a)
    )
    far_bulk = (
        fluid
        & (r >= args.cylinder_r + 5.0 * a)
        & (xg >= 0.20 * args.lx)
        & (xg <= 0.85 * args.lx)
        & (yg >= 3.0 * a)
        & (yg <= args.ly - 3.0 * a)
    )
    return {
        "all_fluid": fluid,
        "cylinder_interface_2cells": interface,
        "cylinder_halo_4cells": solid_halo,
        "wake_near_1D": wake_near,
        "wake_long_2D": wake_long,
        "upstream_control": upstream,
        "wake_side_control": wake_side_control,
        "cylinder_shoulders": cylinder_shoulders,
        "inlet_lower_lip": inlet_lip,
        "outer_wall_halo": outer_wall_halo,
        "far_bulk": far_bulk,
    }


def zone_metric(
    name: str,
    mask: np.ndarray,
    fields: Mapping[str, np.ndarray],
    chi: np.ndarray,
    args: argparse.Namespace,
) -> Dict[str, float | int | str]:
    count = fields["count"]
    mass = fields["mass"]
    ux = fields["ux"]
    uy = fields["uy"]
    thermal_x = fields["thermal_x"]
    thermal_y = fields["thermal_y"]
    n_cells = int(mask.sum())
    if n_cells == 0:
        return {"zone": name, "cells": 0}
    occupied = mask & (count > 0)
    zone_mass = float(mass[mask].sum())
    px = float(fields["px"][mask].sum())
    py = float(fields["py"][mask].sum())
    tx = float(thermal_x[mask].sum())
    ty = float(thermal_y[mask].sum())
    total_count = int(count[mask].sum())
    cell_area = args.lx * args.ly / (count.shape[0] * count.shape[1])
    phi = np.clip(chi[mask], args.chi_fluid_threshold, 1.0)
    density_phi = mass[mask] / (phi * cell_area)
    occupied_count = int(occupied.sum())
    cell_speed = np.hypot(ux[mask], uy[mask])
    mean_abs_ux = float(np.mean(np.abs(ux[mask])))
    mean_abs_uy = float(np.mean(np.abs(uy[mask])))
    result: Dict[str, float | int | str] = {
        "zone": name,
        "cells": n_cells,
        "occupiedCells": occupied_count,
        "emptyCells": n_cells - occupied_count,
        "emptyFraction": (n_cells - occupied_count) / n_cells,
        "poorCells": int(np.count_nonzero(mask & (count < args.support_nmin))),
        "poorFraction": float(np.count_nonzero(mask & (count < args.support_nmin))) / n_cells,
        "particleCount": total_count,
        "meanNAllCells": float(np.mean(count[mask])),
        "minN": int(np.min(count[mask])),
        "maxN": int(np.max(count[mask])),
        "totalMass": zone_mass,
        "meanMassAllCells": float(np.mean(mass[mask])),
        "meanDensityPhiCorrected": float(np.mean(density_phi)),
        "massWeightedUx": px / zone_mass if zone_mass > 0.0 else math.nan,
        "massWeightedUy": py / zone_mass if zone_mass > 0.0 else math.nan,
        "meanCellSpeed": float(np.mean(cell_speed)),
        "meanAbsCellUx": mean_abs_ux,
        "meanAbsCellUy": mean_abs_uy,
        "crossStreamToStreamCellRatio": mean_abs_uy / mean_abs_ux if mean_abs_ux > 0.0 else math.nan,
        "thermalVarXMassWeighted": tx / zone_mass if zone_mass > 0.0 else math.nan,
        "thermalVarYMassWeighted": ty / zone_mass if zone_mass > 0.0 else math.nan,
        "thermalAnisotropy": (tx - ty) / (tx + ty) if tx + ty > 0.0 else math.nan,
        "kBTFromRelativeEnergyPerParticle": 0.5 * (tx + ty) / total_count if total_count > 0 else math.nan,
    }
    return result


def wake_flux_proxies(
    case: Case, args: argparse.Namespace, fields: Mapping[str, np.ndarray], chi: np.ndarray,
) -> Dict[str, float]:
    dx = args.lx / case.nx
    dy = args.ly / case.ny
    band = max(dx, dy)
    diameter = 2.0 * args.cylinder_r
    x = fields["particle_x"]
    y = fields["particle_y"]
    vy = fields["particle_vy"]
    mass = fields["particle_mass"]
    xmask = (
        (x >= args.cylinder_cx + args.cylinder_r)
        & (x < min(args.lx, args.cylinder_cx + args.cylinder_r + 2.0 * diameter))
    )
    top = xmask & (y >= args.cylinder_cy + args.cylinder_r) & (y < args.cylinder_cy + args.cylinder_r + band)
    bottom = xmask & (y <= args.cylinder_cy - args.cylinder_r) & (y > args.cylinder_cy - args.cylinder_r - band)
    inward = float(np.sum(mass[top] * np.maximum(-vy[top], 0.0)))
    inward += float(np.sum(mass[bottom] * np.maximum(vy[bottom], 0.0)))
    outward = float(np.sum(mass[top] * np.maximum(vy[top], 0.0)))
    outward += float(np.sum(mass[bottom] * np.maximum(-vy[bottom], 0.0)))
    return {
        "wakeInwardCrossStreamFluxProxy": inward,
        "wakeOutwardCrossStreamFluxProxy": outward,
        "wakeNetInwardCrossStreamFluxProxy": inward - outward,
        "wakeInwardToOutwardFluxRatio": inward / outward if outward > 0.0 else math.inf,
    }


def write_csv(path: Path, rows: Sequence[Mapping[str, object]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if not rows:
        path.write_text("")
        return
    fieldnames: List[str] = []
    seen = set()
    for row in rows:
        for key in row:
            if key not in seen:
                seen.add(key)
                fieldnames.append(key)
    with path.open("w", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=fieldnames, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)


def ratio(numerator: float, denominator: float) -> float:
    return numerator / denominator if math.isfinite(numerator) and math.isfinite(denominator) and denominator != 0.0 else math.nan


def main() -> int:
    args = parse_args()
    sweep_root = args.sweep_root.resolve()
    manifest = args.manifest.resolve() if args.manifest else sweep_root / "sweep_manifest.csv"
    cases = read_manifest(manifest)
    dimension_rows: List[Dict[str, object]] = []
    if args.preflight_only:
        for case in cases:
            row: Dict[str, object] = {
                "case_id": case.case_id,
                "nx": case.nx,
                "ny": case.ny,
                "dt": case.dt,
                "kbtInput": case.kbt,
                "alpha": case.alpha,
                "steps": case.steps,
                "tEnd": case.t_end,
                "note": case.note,
                "runRoot": str(case.run_root),
            }
            row.update({f"input_{key}": value for key, value in dimensionless(case, args).items()})
            dimension_rows.append(row)
        analysis_root = sweep_root / "analysis"
        write_csv(analysis_root / "dimensionless_preflight.csv", dimension_rows)
        print("===== 0493w0 PREFLIGHT DIMENSIONLESS =====")
        print("case              Nx    dt       kBT      steps   Re_est  Ma_proxy  lambda2D/a  CFL_adv  alpha*dt")
        for row in dimension_rows:
            print(
                f"{str(row['case_id']):<17} {int(row['nx']):4d} "
                f"{float(row['dt']):8.6f} {float(row['kbtInput']):8.4g} "
                f"{int(row['steps']):6d} {float(row['input_ReCylinderEstimate']):8.2f} "
                f"{float(row['input_MachIdeal2dProxy']):9.3f} "
                f"{float(row['input_thermalDisplacement2dRmsOverCell']):11.4f} "
                f"{float(row['input_advectiveCFLCell']):8.4f} "
                f"{float(row['input_darcyAlphaDt']):9.3f}"
            )
        print(f"preflightCsv={analysis_root / 'dimensionless_preflight.csv'}")
        return 0
    dimension_rows = []
    global_rows: List[Dict[str, object]] = []
    zone_rows: List[Dict[str, object]] = []
    summary_rows: List[Dict[str, object]] = []
    failures: List[str] = []

    for case in cases:
        root = case.run_root
        if not root.is_absolute():
            root = (Path.cwd() / root).resolve()
        try:
            output = root / "output"
            summary_path = output / "summary_runtime.csv"
            survey_path = output / "cuda_resampling_support_survey_0295.csv"
            flag_path = output / "cuda_resampling_adaptive_flag_0304.csv"
            topo_path = output / "topo_benchmark_0348.csv"
            darcy_path = output / "darcy_cost_0343.csv"
            state_path = find_single(output, ["state_step_*.smpcd"])
            chi_path = find_single(root / "chi", ["*.f32"])
            summary = read_last_csv_row(summary_path)
            survey = read_last_csv_row(survey_path)
            flag = read_last_csv_row(flag_path)
            topo = read_last_csv_row(topo_path)
            darcy = read_last_csv_row(darcy_path)
            state = read_smpcd(state_path)
            chi = read_chi(chi_path, case.nx, case.ny)
            fields = deposit_state(state, case.nx, case.ny, args.lx, args.ly)
            masks = zone_masks(case, args, chi)
            metrics_by_zone: Dict[str, Dict[str, object]] = {}
            for zone_name, mask in masks.items():
                metric = zone_metric(zone_name, mask, fields, chi, args)
                metric.update({
                    "case_id": case.case_id,
                    "nx": case.nx,
                    "ny": case.ny,
                    "dt": case.dt,
                    "kbtInput": case.kbt,
                    "alpha": case.alpha,
                    "steps": case.steps,
                    "tEnd": case.t_end,
                    "runRoot": str(root),
                })
                zone_rows.append(metric)
                metrics_by_zone[zone_name] = metric

            input_dim = dimensionless(case, args)
            final_kbt = f(summary, "kBTEstimate")
            final_mean_vx = f(summary, "meanVx")
            observed_dim = dimensionless(
                case, args, kbt_for_model=final_kbt, velocity_for_model=final_mean_vx
            )
            dim_row: Dict[str, object] = {
                "case_id": case.case_id,
                "nx": case.nx,
                "ny": case.ny,
                "dt": case.dt,
                "kbtInput": case.kbt,
                "alpha": case.alpha,
                "steps": case.steps,
                "tEnd": case.t_end,
                "note": case.note,
                "runRoot": str(root),
            }
            dim_row.update({f"input_{key}": value for key, value in input_dim.items()})
            dim_row.update({f"final_{key}": value for key, value in observed_dim.items()})
            dimension_rows.append(dim_row)

            global_row: Dict[str, object] = {
                "case_id": case.case_id,
                "wallTime": f(summary, "wallTime"),
                "finalStep": f(summary, "step"),
                "finalTime": f(summary, "time"),
                "nFluidParticles": f(summary, "nFluidParticles"),
                "nInactiveParticles": f(summary, "nInactiveParticles"),
                "totalMass": f(summary, "totalMass"),
                "meanVx": final_mean_vx,
                "meanVy": f(summary, "meanVy"),
                "kBTEstimate": final_kbt,
                "meanParticleSpeed": f(summary, "meanParticleSpeed"),
                "maxParticleSpeed": f(summary, "maxParticleSpeed"),
                "inletReservoirMeanN": f(summary, "inletReservoirMeanN"),
                "inletReservoirStdN": f(summary, "inletReservoirStdN"),
                "inletMeanUx": f(summary, "inletMeanUx"),
                "inletMeanUy": f(summary, "inletMeanUy"),
                "inletKBT": f(summary, "inletKBT"),
                "virtualParticleEquivalent": f(summary, "virtualParticleEquivalent"),
                "thermostatKBTBefore": f(summary, "thermostatKBTBefore"),
                "thermostatKBTAfter": f(summary, "thermostatKBTAfter"),
                "surveyEmptyCells": f(survey, "emptyCells"),
                "surveyPoorCells": f(survey, "poorCells"),
                "surveyMeanNActive": f(survey, "meanNActive"),
                "surveyStdNActive": f(survey, "stdNActive"),
                "surveyMinNWet": f(survey, "minNWet"),
                "surveyMaxNWet": f(survey, "maxNWet"),
                "surveyMassRelRmsWet": f(survey, "massRelRmsWet"),
                "surveyKBTWeighted": f(survey, "kBTWeighted"),
                "emptyBulkCells": f(flag, "emptyBulkCells0305"),
                "emptyWallAdjacentCells": f(flag, "emptyWallAdjacentCells0305"),
                "emptySolidAdjacentCells": f(flag, "emptySolidAdjacentCells0305"),
                "emptyOpenAdjacentCells": f(flag, "emptyOpenAdjacentCells0305"),
                "lowNBulkCells": f(flag, "lowNBulkCells0305"),
                "lowNWallAdjacentCells": f(flag, "lowNWallAdjacentCells0305"),
                "lowNSolidAdjacentCells": f(flag, "lowNSolidAdjacentCells0305"),
                "lowNOpenAdjacentCells": f(flag, "lowNOpenAdjacentCells0305"),
                "maxAbsUBulk": f(flag, "maxAbsUBulk0305"),
                "maxAbsUWallAdjacent": f(flag, "maxAbsUWallAdjacent0305"),
                "maxAbsUSolidAdjacent": f(flag, "maxAbsUSolidAdjacent0305"),
                "darcyPower": f(topo, "darcyPower", f(darcy, "darcyPower")),
                "darcyPowerPerMass": f(topo, "darcyPowerPerMass", f(darcy, "darcyPowerPerMass")),
                "solidLeakRms": f(topo, "solidLeakRms", f(darcy, "solidLeakRms")),
                "dragProxy": f(topo, "dragProxy"),
                "liftProxy": f(topo, "liftProxy"),
            }
            global_rows.append(global_row)

            wake_near = metrics_by_zone["wake_near_1D"]
            wake_long = metrics_by_zone["wake_long_2D"]
            upstream = metrics_by_zone["upstream_control"]
            wake_side = metrics_by_zone["wake_side_control"]
            shoulders = metrics_by_zone["cylinder_shoulders"]
            interface = metrics_by_zone["cylinder_interface_2cells"]
            inlet_lip = metrics_by_zone["inlet_lower_lip"]
            flux = wake_flux_proxies(case, args, fields, chi)
            summary_row: Dict[str, object] = {
                "case_id": case.case_id,
                "nx": case.nx,
                "dt": case.dt,
                "kbtInput": case.kbt,
                "alpha": case.alpha,
                "steps": case.steps,
                "tEnd": case.t_end,
                "wallTime": global_row["wallTime"],
                "ReCylinderEstimate": input_dim["ReCylinderEstimate"],
                "ReClass": input_dim["ReClass"],
                "MachIdeal2dProxy": input_dim["MachIdeal2dProxy"],
                "MachClass": input_dim["MachClass"],
                "thermalDisplacement2dRmsOverCell": input_dim["thermalDisplacement2dRmsOverCell"],
                "advectiveCFLCell": input_dim["advectiveCFLCell"],
                "darcyAlphaDt": input_dim["darcyAlphaDt"],
                "cylinderCells": input_dim["cylinderCells"],
                "finalKBT": final_kbt,
                "finalMeanVx": final_mean_vx,
                "finalMachIdeal2dProxy": observed_dim["MachIdeal2dProxy"],
                "finalReCylinderEstimate": observed_dim["ReCylinderEstimate"],
                "wakeNearEmptyFraction": wake_near.get("emptyFraction", math.nan),
                "wakeNearPoorFraction": wake_near.get("poorFraction", math.nan),
                "wakeNearMeanN": wake_near.get("meanNAllCells", math.nan),
                "wakeNearMeanMass": wake_near.get("meanMassAllCells", math.nan),
                "wakeNearMassWeightedUx": wake_near.get("massWeightedUx", math.nan),
                "wakeNearMassWeightedUy": wake_near.get("massWeightedUy", math.nan),
                "wakeNearCrossStreamRatio": wake_near.get("crossStreamToStreamCellRatio", math.nan),
                "wakeLongEmptyFraction": wake_long.get("emptyFraction", math.nan),
                "wakeLongPoorFraction": wake_long.get("poorFraction", math.nan),
                "wakeLongMeanN": wake_long.get("meanNAllCells", math.nan),
                "upstreamMeanN": upstream.get("meanNAllCells", math.nan),
                "wakeToUpstreamMeanNRatio": ratio(
                    float(wake_long.get("meanNAllCells", math.nan)),
                    float(upstream.get("meanNAllCells", math.nan)),
                ),
                "wakeToUpstreamMassRatio": ratio(
                    float(wake_long.get("meanMassAllCells", math.nan)),
                    float(upstream.get("meanMassAllCells", math.nan)),
                ),
                "wakeToSideMeanNRatio": ratio(
                    float(wake_long.get("meanNAllCells", math.nan)),
                    float(wake_side.get("meanNAllCells", math.nan)),
                ),
                "wakeToSideMassRatio": ratio(
                    float(wake_long.get("meanMassAllCells", math.nan)),
                    float(wake_side.get("meanMassAllCells", math.nan)),
                ),
                "wakeToShoulderMassRatio": ratio(
                    float(wake_long.get("meanMassAllCells", math.nan)),
                    float(shoulders.get("meanMassAllCells", math.nan)),
                ),
                "interfaceEmptyFraction": interface.get("emptyFraction", math.nan),
                "interfacePoorFraction": interface.get("poorFraction", math.nan),
                "interfaceMeanN": interface.get("meanNAllCells", math.nan),
                "inletLipMeanN": inlet_lip.get("meanNAllCells", math.nan),
                "inletLipMeanMass": inlet_lip.get("meanMassAllCells", math.nan),
                "inletLipToUpstreamMassRatio": ratio(
                    float(inlet_lip.get("meanMassAllCells", math.nan)),
                    float(upstream.get("meanMassAllCells", math.nan)),
                ),
                "emptySolidAdjacentCells": global_row["emptySolidAdjacentCells"],
                "lowNSolidAdjacentCells": global_row["lowNSolidAdjacentCells"],
                "solidLeakRms": global_row["solidLeakRms"],
                "dragProxy": global_row["dragProxy"],
                "liftProxy": global_row["liftProxy"],
                "note": case.note,
            }
            summary_row.update(flux)
            summary_rows.append(summary_row)
        except Exception as exc:  # retain other cases in non-strict mode
            message = f"{case.case_id}: {exc}"
            failures.append(message)
            print(f"[0493w0-analysis] ERROR {message}", file=sys.stderr)
            if args.strict:
                raise

    analysis_root = sweep_root / "analysis"
    write_csv(analysis_root / "dimensionless_groups.csv", dimension_rows)
    write_csv(analysis_root / "final_global_metrics.csv", global_rows)
    write_csv(analysis_root / "zone_metrics.csv", zone_rows)
    write_csv(analysis_root / "sweep_summary.csv", summary_rows)

    print("===== 0493w0 DARCY KINETIC-REGIME SWEEP =====")
    print(f"casesInManifest={len(cases)} analyzed={len(summary_rows)} failures={len(failures)}")
    print(f"summary={analysis_root / 'sweep_summary.csv'}")
    print(f"zones={analysis_root / 'zone_metrics.csv'}")
    print(f"dimensionless={analysis_root / 'dimensionless_groups.csv'}")
    print()
    print("case              Re_est   Ma_proxy  lambda2D/a  wakeN/side wakeEmpty  interfacePoor  wall[s]")
    for row in summary_rows:
        print(
            f"{str(row['case_id']):<17} "
            f"{float(row['ReCylinderEstimate']):7.2f} "
            f"{float(row['MachIdeal2dProxy']):9.3f} "
            f"{float(row['thermalDisplacement2dRmsOverCell']):10.4f} "
            f"{float(row['wakeToSideMeanNRatio']):10.3f} "
            f"{float(row['wakeLongEmptyFraction']):10.3f} "
            f"{float(row['interfacePoorFraction']):13.3f} "
            f"{float(row['wallTime']):8.1f}"
        )
    if failures:
        print("\nFailures:")
        for failure in failures:
            print(f"  - {failure}")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
