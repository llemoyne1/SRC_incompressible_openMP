#!/usr/bin/env python3
"""Aggregate CUDA resident classic SRC performance artifacts for patch 0273.

The script scans an artifact tree produced by
scripts/run_cuda_classic_src_resident_perf_0273.sh and writes two CSV files:
  * cuda_classic_src_resident_perf_summary_0273.csv — one compact row per run
  * cuda_classic_src_resident_perf_phases_0273.csv — detailed phase rows

It is deliberately tolerant of missing optional files: a suite can still be
summarized from summary_runtime.csv + phase_profile_0163.csv even if a specific
CUDA subphase profile was not emitted by a legacy runner.
"""
from __future__ import annotations

import argparse
import csv
import math
from pathlib import Path
from typing import Dict, Iterable, List, Tuple


def read_csv(path: Path) -> List[Dict[str, str]]:
    try:
        with path.open(newline="") as fh:
            return list(csv.DictReader(fh))
    except FileNotFoundError:
        return []


def as_float(value: str | None, default: float = 0.0) -> float:
    if value is None or value == "":
        return default
    try:
        x = float(value)
        return x if math.isfinite(x) else default
    except ValueError:
        return default


def as_int(value: str | None, default: int = 0) -> int:
    if value is None or value == "":
        return default
    try:
        return int(float(value))
    except ValueError:
        return default


def infer_case_dir(path: Path, root: Path) -> str:
    rel = path.parent.relative_to(root)
    parts = rel.parts
    if len(parts) >= 2:
        return "/".join(parts[-2:])
    return str(rel)


def final_runtime_row(case_dir: Path) -> Dict[str, str]:
    rows = read_csv(case_dir / "summary_runtime.csv")
    if not rows:
        return {}
    return rows[-1]


def aggregate_phase_profile(rows: Iterable[Dict[str, str]]) -> Tuple[float, Dict[str, float]]:
    out: Dict[str, float] = {}
    total = 0.0
    for r in rows:
        phase = r.get("phase", "")
        value = as_float(r.get("total_s"))
        if phase and phase != "total_profiled":
            out[phase] = out.get(phase, 0.0) + value
        if phase == "total_profiled":
            total += value
    if total == 0.0:
        total = sum(out.values())
    return total, out


def aggregate_cuda_resident_rows(rows: Iterable[Dict[str, str]]) -> Tuple[Dict[str, float], Dict[str, int]]:
    times = {
        "resident_stream_total_s": 0.0,
        "resident_stream_kernel_s": 0.0,
        "resident_boundary_total_s": 0.0,
        "resident_boundary_kernel_s": 0.0,
        "resident_immersed_total_s": 0.0,
        "resident_immersed_kernel_s": 0.0,
        "resident_total_s": 0.0,
        "resident_kernel_s": 0.0,
        "resident_upload_s": 0.0,
        "resident_download_s": 0.0,
    }
    counts = {
        "resident_rows": 0,
        "resident_handled_rows": 0,
        "resident_inlet_inserted_total": 0,
        "resident_outlet_deleted_total": 0,
    }
    for r in rows:
        counts["resident_rows"] += 1
        handled = as_int(r.get("handled"))
        counts["resident_handled_rows"] += handled
        phase = r.get("phase", "")
        total = as_float(r.get("totalSeconds"))
        kernel = as_float(r.get("kernelSeconds"))
        upload = as_float(r.get("uploadSeconds"))
        download = as_float(r.get("downloadSeconds"))
        if handled:
            times["resident_total_s"] += total
            times["resident_kernel_s"] += kernel
            times["resident_upload_s"] += upload
            times["resident_download_s"] += download
            if phase == "force_stream":
                times["resident_stream_total_s"] += total
                times["resident_stream_kernel_s"] += kernel
            elif phase == "boundary_conditions":
                times["resident_boundary_total_s"] += total
                times["resident_boundary_kernel_s"] += kernel
            elif phase == "immersed_solid":
                times["resident_immersed_total_s"] += total
                times["resident_immersed_kernel_s"] += kernel
        counts["resident_inlet_inserted_total"] += as_int(r.get("inletParticlesInserted"))
        counts["resident_outlet_deleted_total"] += as_int(r.get("outletParticlesDeleted"))
    return times, counts


def aggregate_collision_rows(rows: Iterable[Dict[str, str]]) -> Dict[str, float | int]:
    out: Dict[str, float | int] = {
        "collision_rows": 0,
        "collision_upload_s": 0.0,
        "collision_kernel_s": 0.0,
        "collision_download_s": 0.0,
        "collision_total_s": 0.0,
        "collision_particles_rotated": 0,
        "collision_invalid_cell_particles": 0,
        "collision_shared_particle_rows": 0,
        "collision_shared_cell_rows": 0,
    }
    for r in rows:
        out["collision_rows"] = int(out["collision_rows"]) + 1
        out["collision_upload_s"] = float(out["collision_upload_s"]) + as_float(r.get("uploadSeconds"))
        out["collision_kernel_s"] = float(out["collision_kernel_s"]) + as_float(r.get("kernelSeconds"))
        out["collision_download_s"] = float(out["collision_download_s"]) + as_float(r.get("downloadSeconds"))
        out["collision_total_s"] = float(out["collision_total_s"]) + as_float(r.get("totalSeconds"))
        out["collision_particles_rotated"] = int(out["collision_particles_rotated"]) + as_int(r.get("particlesRotated"))
        out["collision_invalid_cell_particles"] = int(out["collision_invalid_cell_particles"]) + as_int(r.get("invalidCellParticles"))
        out["collision_shared_particle_rows"] = int(out["collision_shared_particle_rows"]) + as_int(r.get("sharedParticleStateEnabled"))
        out["collision_shared_cell_rows"] = int(out["collision_shared_cell_rows"]) + as_int(r.get("sharedCellWorkspaceEnabled"))
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("artifact_root", type=Path)
    ap.add_argument("--summary-out", type=Path, default=None)
    ap.add_argument("--phases-out", type=Path, default=None)
    ns = ap.parse_args()

    root = ns.artifact_root
    summary_out = ns.summary_out or root / "cuda_classic_src_resident_perf_summary_0273.csv"
    phases_out = ns.phases_out or root / "cuda_classic_src_resident_perf_phases_0273.csv"

    case_dirs = sorted({p.parent for p in root.rglob("summary_runtime.csv")})
    summary_rows: List[Dict[str, object]] = []
    phase_rows: List[Dict[str, object]] = []

    for case_dir in case_dirs:
        case = infer_case_dir(case_dir / "summary_runtime.csv", root)
        runtime = final_runtime_row(case_dir)
        phase_total, phases = aggregate_phase_profile(read_csv(case_dir / "phase_profile_0163.csv"))
        resident_times, resident_counts = aggregate_cuda_resident_rows(read_csv(case_dir / "cuda_resident_phase_profile_0266.csv"))
        collision = aggregate_collision_rows(read_csv(case_dir / "cuda_persistent_src_collision_thermostat_0215.csv"))

        wall_s = as_float(runtime.get("wallSeconds") or runtime.get("wallTime") or runtime.get("elapsedSeconds"))
        step = as_int(runtime.get("step"))
        if wall_s == 0.0:
            wall_s = as_float(runtime.get("wall"))
        row: Dict[str, object] = {
            "case": case,
            "steps": step,
            "wall_s": wall_s,
            "profile_total_s": phase_total,
            "force_stream_s": phases.get("force_stream", 0.0),
            "boundary_s": phases.get("boundary_conditions", 0.0),
            "immersed_s": phases.get("immersed_solid", 0.0),
            "collision_s": phases.get("src_collision", 0.0),
            "q6_s": phases.get("q6_projection", 0.0),
            "resampling_total_s": sum(v for k, v in phases.items() if k.startswith("resampling_")),
        }
        row.update(resident_times)
        row.update(resident_counts)
        row.update(collision)
        summary_rows.append(row)

        for name, value in sorted(phases.items()):
            phase_rows.append({"case": case, "source": "phase_profile_0163", "phase": name, "total_s": value})
        for name, value in sorted(resident_times.items()):
            phase_rows.append({"case": case, "source": "cuda_resident_phase_profile_0266", "phase": name, "total_s": value})
        for name in ["collision_upload_s", "collision_kernel_s", "collision_download_s", "collision_total_s"]:
            phase_rows.append({"case": case, "source": "cuda_persistent_src_collision_thermostat_0215", "phase": name, "total_s": collision.get(name, 0.0)})

    if summary_rows:
        keys = list(summary_rows[0].keys())
        summary_out.parent.mkdir(parents=True, exist_ok=True)
        with summary_out.open("w", newline="") as fh:
            w = csv.DictWriter(fh, fieldnames=keys)
            w.writeheader()
            w.writerows(summary_rows)
    if phase_rows:
        phases_out.parent.mkdir(parents=True, exist_ok=True)
        with phases_out.open("w", newline="") as fh:
            w = csv.DictWriter(fh, fieldnames=["case", "source", "phase", "total_s"])
            w.writeheader()
            w.writerows(phase_rows)

    print(f"[0273-perf-summary] cases={len(summary_rows)} summary={summary_out} phases={phases_out}")
    return 0 if summary_rows else 1


if __name__ == "__main__":
    raise SystemExit(main())
