#!/usr/bin/env python3
"""
Static GPU-candidate audit helper for the clean/openmp-light SRC/MPCD tree.

The script is intentionally read-only. It records the main hot-loop candidates
for a first GPU prototype, checks that the expected source anchors are present,
and writes compact CSV files for review.
"""
from __future__ import annotations

import argparse
import csv
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable


@dataclass(frozen=True)
class Candidate:
    rank: int
    operation: str
    primary_files: str
    anchors: tuple[str, ...]
    probable_cost: str
    parallelism: str
    memory_difficulty: str
    numerical_risk: str
    cpu_gpu_comparison: str
    physical_interest: str
    first_gpu_priority: str
    notes: str


CANDIDATES: tuple[Candidate, ...] = (
    Candidate(
        1,
        "Q6 elliptic projection / CG on cell and face fields",
        "src/q6_projection_adapter.cpp; src/elliptic_projection.cpp",
        (
            "apply_q6_periodic_projection",
            "project_face_field",
            "solve_cg",
            "apply_elliptic_operator_plan_and_dot",
        ),
        "high when projectionEnable=true; historical profiling identified q6_projection as dominant after cleanup",
        "high: regular cell/face arrays, stencil operator, vector AXPY, dot reductions",
        "moderate: iterative global reductions and persistent device arrays, but no particle scatter",
        "moderate: floating-point reduction order may alter residual trajectory; compare tolerances not bitwise identity",
        "very good: divergence residuals, CG iterations, velocity correction, mass/momentum summaries",
        "very high for TG, Poiseuille, obstacle/step, piston whenever Q6 is active",
        "recommended first real GPU target",
        "Start with a grid-only backend for the elliptic CG path; keep CPU OpenMP as default reference.",
    ),
    Candidate(
        2,
        "Particle-to-cell deposits for collision, Q6, thermostat, resampling, capacity",
        "src/src_collision.cpp; src/q6_projection_adapter.cpp; src/thermostat.cpp; src/weighted_resampling.cpp; src/closed_capacity_response.cpp",
        (
            "localMass",
            "localPx",
            "localPy",
            "deposit_cell_velocity",
            "deposit_weighted_real_fluid",
            "deposit_cell_mass_for_capacity",
        ),
        "high and repeated; resampling may call full deposits several times per step",
        "high over particles, then over cells",
        "high: scatter/reduction to cells; CPU currently avoids atomics through per-thread local arrays",
        "moderate to high: reduction order and cell-id conventions affect downstream Q6/resampling",
        "good but requires invariant checks on mass, momentum, population and per-cell diagnostics",
        "very high for all validation cases, especially resampling and piston/capacity",
        "second target after grid-only Q6, or first target only for a CPU/device-resident architecture",
        "A GPU implementation should choose between atomics, sort/bin-by-cell, or two-level block reductions.",
    ),
    Candidate(
        3,
        "SRC collision update by particle after cell moments",
        "src/src_collision.cpp",
        (
            "src_collision_step",
            "cosA",
            "sinA",
            "state.vx[i] = ux + ca * dvx - sa * dvy",
        ),
        "medium to high; one main particle pass plus wall virtual-particle cell pass",
        "high once cell moments are known",
        "moderate: cell moment arrays are read-only during velocity rotation; deposit remains the hard part",
        "low to moderate: random rotation sign must remain deterministic; wallVP random thermal noise must be controlled",
        "good: kBT, momentum, wallVP counters, velocity statistics",
        "high for every case; wallVP makes Poiseuille/piston sensitive",
        "good follow-up if deposits are also on device",
        "The rotation pass itself is GPU-friendly, but moving only this pass would be transfer dominated.",
    ),
    Candidate(
        4,
        "Cell-relative thermostat",
        "src/thermostat.cpp",
        (
            "apply_cell_relative_rescale_thermostat",
            "localKinetic",
            "cellScale",
            "state.vx[i] = ux + scale * (state.vx[i] - ux)",
        ),
        "medium; active in validated thermal wall/channel cases",
        "high but multi-pass: moments, kinetic, scales, particle rescale",
        "moderate to high: same scatter/reduction pattern as collision plus extra kinetic reduction",
        "moderate: thermostat affects kBT and viscosity; reduction order affects scales weakly",
        "very good: kBTBefore/kBTAfter, scale extrema, particlesRescaled",
        "high for Poiseuille, piston, wallVP; lower for pure TG if thermostat disabled",
        "not first unless deposit infrastructure exists",
        "Useful once collision/deposit arrays are device-resident; otherwise CPU/GPU transfer overhead dominates.",
    ),
    Candidate(
        5,
        "Weighted resampling, population guard, remap, thermal renormalization, mass guard",
        "src/weighted_resampling.cpp; src/src_mpcd_base.cpp",
        (
            "apply_resampling_population_support_guard",
            "apply_resampling_local_mass_momentum_remap",
            "apply_resampling_local_thermal_renormalization",
            "apply_resampling_particle_mass_guards",
            "receiverPoorCells",
            "donorRichCells",
        ),
        "high in Q6+resampling; repeated deposits and role mutations can dominate",
        "mixed: deposits are parallel; candidate lists, pool edits, transfer plans are irregular",
        "very high: dynamic lists, particle role changes, pool free slots, conservative remap",
        "high: this is physically delicate and protects poor cells; trajectory equality is fragile",
        "moderate: many diagnostics exist, but exact CPU/GPU path equivalence is difficult",
        "very high physically, but too risky for first GPU kernel",
        "defer",
        "Keep on CPU until the field/deposit backbone is stable on GPU.",
    ),
    Candidate(
        6,
        "Closed-capacity virial pressure/kick",
        "src/closed_capacity_response.cpp",
        (
            "apply_closed_capacity_virial_kick",
            "virialKEffective",
            "kickVx",
            "kickVy",
        ),
        "low to medium except piston/capacity studies",
        "high over cells and particles",
        "moderate: deposit mass plus grid gradient and particle velocity update",
        "moderate to high in piston/capacity because pressure response is physically central",
        "good: virial pressure, wall loads, momentum correction residuals",
        "high for piston only; secondary for TG/Poiseuille/obstacle",
        "defer after Q6/deposit",
        "Good GPU candidate once cell mass deposit and particle update infrastructure is already available.",
    ),
    Candidate(
        7,
        "Runtime summaries and diagnostics reductions",
        "src/runtime_summary.cpp; src/src_mpcd_base.cpp",
        (
            "RuntimeSummaryWriter::append",
            "compute_runtime_summary",
            "compute_runtime_summary",
        ),
        "low in light mode; diagnostics are not the target bottleneck",
        "high reductions, but summary cadence is sparse",
        "low to moderate",
        "low, but diagnostics must remain CPU-visible",
        "excellent, but not worth first acceleration",
        "diagnostic value high; acceleration value low",
        "keep CPU",
        "Preserve as validation oracle; do not offload first.",
    ),
)


def source_text(root: Path, relative_files: Iterable[str]) -> str:
    parts: list[str] = []
    for rel in relative_files:
        path = root / rel.strip()
        if path.exists():
            try:
                parts.append(path.read_text(encoding="utf-8", errors="replace"))
            except OSError:
                pass
    return "\n".join(parts)


def anchor_status(root: Path, candidate: Candidate) -> tuple[int, int, str]:
    files = [p.strip() for p in candidate.primary_files.split(";")]
    text = source_text(root, files)
    found = [a for a in candidate.anchors if a in text]
    missing = [a for a in candidate.anchors if a not in text]
    return len(found), len(candidate.anchors), "; ".join(missing)


def write_csv(path: Path, rows: list[dict[str, object]], fieldnames: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


def main() -> int:
    parser = argparse.ArgumentParser(description="Audit GPU candidates in clean/openmp-light")
    parser.add_argument("--root", default=".", help="Repository root")
    parser.add_argument("--out", default="gpu_audit_0183", help="Output directory")
    args = parser.parse_args()

    root = Path(args.root).resolve()
    out = Path(args.out)
    rows: list[dict[str, object]] = []
    summary = {"ok": 0, "partial": 0, "missing": 0}

    for c in CANDIDATES:
        found, total, missing = anchor_status(root, c)
        if found == total:
            status = "ok"
        elif found > 0:
            status = "partial"
        else:
            status = "missing"
        summary[status] += 1
        rows.append({
            "rank": c.rank,
            "operation": c.operation,
            "primary_files": c.primary_files,
            "anchor_status": status,
            "anchors_found": found,
            "anchors_total": total,
            "missing_anchors": missing,
            "probable_cost": c.probable_cost,
            "parallelism": c.parallelism,
            "memory_difficulty": c.memory_difficulty,
            "numerical_risk": c.numerical_risk,
            "cpu_gpu_comparison": c.cpu_gpu_comparison,
            "physical_interest": c.physical_interest,
            "first_gpu_priority": c.first_gpu_priority,
            "notes": c.notes,
        })

    fields = [
        "rank", "operation", "primary_files", "anchor_status", "anchors_found", "anchors_total",
        "missing_anchors", "probable_cost", "parallelism", "memory_difficulty", "numerical_risk",
        "cpu_gpu_comparison", "physical_interest", "first_gpu_priority", "notes",
    ]
    write_csv(out / "gpu_candidate_inventory_0183.csv", rows, fields)
    write_csv(
        out / "gpu_candidate_summary_0183.csv",
        [{"status": k, "count": v} for k, v in summary.items()],
        ["status", "count"],
    )
    print(f"Wrote {out / 'gpu_candidate_inventory_0183.csv'}")
    print(f"Wrote {out / 'gpu_candidate_summary_0183.csv'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
