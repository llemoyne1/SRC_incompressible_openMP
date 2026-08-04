#!/usr/bin/env python3
"""Post-check the closed-box 0493x0 dam-break demonstration runs."""

from __future__ import annotations

import argparse
import csv
import json
import math
from pathlib import Path


OPEN_BOUNDARY_COUNTERS = (
    "inletReservoirDeleted",
    "inletBackflowDeleted",
    "outletParticlesDeleted",
    "inletParticlesInserted",
    "inletNetParticleDelta",
)


def read_rows(path: Path) -> list[dict[str, str]]:
    if not path.is_file():
        raise SystemExit(f"missing CSV: {path}")
    with path.open(newline="") as stream:
        return list(csv.DictReader(stream))


def read_kv(path: Path) -> dict[str, str]:
    if not path.is_file():
        raise SystemExit(f"missing parameter file: {path}")
    values: dict[str, str] = {}
    for raw in path.read_text().splitlines():
        line = raw.split("#", 1)[0].strip()
        if not line or "=" not in line:
            continue
        key, value = line.split("=", 1)
        values[key.strip()] = value.strip()
    return values


def latest_type(rows: list[dict[str, str]], particle_type: int, label: str) -> dict[str, str]:
    matches = [row for row in rows if as_int(row.get("type"), -1) == particle_type]
    if not matches:
        raise SystemExit(f"missing {label} row for particle type {particle_type}")
    return matches[-1]


def as_int(value: str | None, default: int = -1) -> int:
    try:
        return int(value or "")
    except ValueError:
        return default


def as_float(value: str | None, default: float = math.nan) -> float:
    try:
        return float(value or "")
    except ValueError:
        return default


def finite(value: str | None) -> bool:
    return math.isfinite(as_float(value))


def is_zero(value: str | None, tolerance: float = 1.0e-14) -> bool:
    return finite(value) and abs(as_float(value)) <= tolerance


def close_mass(actual: str | None, expected: float) -> bool:
    value = as_float(actual)
    tolerance = max(1.0e-10, 2.0e-12 * abs(expected))
    return math.isfinite(value) and abs(value - expected) <= tolerance


def truthy_text(value: str | None) -> bool:
    return (value or "").strip().lower() in {"1", "true", "yes", "on"}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--run-root", type=Path, required=True)
    parser.add_argument("--state-metadata", type=Path, required=True)
    parser.add_argument("--expected-steps", type=int, required=True)
    parser.add_argument("--modes", nargs="+", required=True)
    args = parser.parse_args()

    metadata = json.loads(args.state_metadata.read_text())
    if metadata.get("profile") != "dam_break":
        raise SystemExit("state metadata does not describe a dam-break profile")

    liquid_type = int(metadata["liquid_type"])
    gas_type = int(metadata["gas_type"])
    liquid_particles_expected = int(metadata["liquid_particles"])
    gas_particles_expected = int(metadata["gas_particles"])
    total_particles_expected = int(metadata["fluid_particles"])
    liquid_mass_expected = liquid_particles_expected * float(metadata["liquid_mass"])
    gas_mass_expected = gas_particles_expected * float(metadata["gas_mass"])
    if min(liquid_particles_expected, gas_particles_expected) <= 0:
        raise SystemExit("initial state must contain both liquid and gas")

    results: list[dict[str, object]] = []
    all_ok = True
    for mode in args.modes:
        output = args.run_root / mode / "output"
        params = read_kv(output / "params_used.kv")
        summary = read_rows(output / "summary_runtime.csv")
        species_rows = read_rows(output / "species_runtime_0493x0.csv")
        final = summary[-1] if summary else {}
        liquid_species = latest_type(species_rows, liquid_type, "species diagnostic")
        gas_species = latest_type(species_rows, gas_type, "species diagnostic")

        step_ok = as_int(final.get("step"), -1) >= args.expected_steps
        params_closed_ok = (
            not truthy_text(params.get("openBoundarySegmentsEnable"))
            and as_int(params.get("openBoundarySegmentCount"), -1) == 0
            and all(
                params.get(key) in {"solid", "specular"}
                for key in ("bcLeft", "bcRight", "bcBottom", "bcTop")
            )
        )
        no_open_mutation = all(
            as_int(row.get("inletHardReservoirEnabled"), 0) == 0
            and all(as_int(row.get(key), 0) == 0 for key in OPEN_BOUNDARY_COUNTERS)
            for row in summary
        )
        total_count_ok = as_int(final.get("nFluidParticles"), -1) == total_particles_expected
        liquid_count_ok = as_int(liquid_species.get("nFluid"), -1) == liquid_particles_expected
        gas_count_ok = as_int(gas_species.get("nFluid"), -1) == gas_particles_expected
        liquid_mass_ok = close_mass(liquid_species.get("totalMass"), liquid_mass_expected)
        gas_mass_ok = close_mass(gas_species.get("totalMass"), gas_mass_expected)
        conservation_ok = (
            total_count_ok and liquid_count_ok and gas_count_ok and
            liquid_mass_ok and gas_mass_ok and no_open_mutation
        )

        q6_expected = "q6" in mode
        q6_ok = True
        active_cells: object = ""
        corrected_particles: object = ""
        applied_ratio: object = ""

        if q6_expected:
            generic_rows = read_rows(output / "cuda_species_q6_0491.csv")
            independent_rows = read_rows(
                output / "cuda_species_q6_independent_masked_0493w5.csv"
            )
            generic = generic_rows[-1] if generic_rows else {}
            liquid = latest_type(independent_rows, liquid_type, "Q6 diagnostic")
            gas = latest_type(independent_rows, gas_type, "Q6 diagnostic")

            resident_ok = (
                generic.get("mode") == "independent_masked"
                and generic.get("boundaryFamily") == "closed_box"
                and generic.get("openBoundaryEnabled") == "0"
                and generic.get("darcyBrinkmanEnable") == "0"
                and generic.get("species_q6_device_resident") == "1"
                and generic.get("species_q6_host_cell_array_entries") == "0"
                and generic.get("species_q6_weight_h2d") == "0"
                and generic.get("species_q6_full_state_download") == "0"
                and generic.get("species_q6_cpu_fallback") == "0"
                and generic.get("species_q6_remaining_cpu_scope") == "none"
                and generic.get("q6Applied") == "1"
                and generic.get("q6Converged") == "1"
            )
            liquid_ok = (
                finite(liquid.get("q6Strength"))
                and as_float(liquid.get("q6Strength")) > 0.0
                and as_int(liquid.get("activeCells"), 0) > 0
                and as_int(liquid.get("correctedParticles"), 0) > 0
                and liquid.get("converged") == "1"
                and all(
                    finite(liquid.get(key))
                    for key in (
                        "residualRel",
                        "divBeforeRms",
                        "divAfterProjectedFaceFluxRms",
                        "divAfterAppliedCellVelocityRms",
                        "correctionMaxAbs",
                    )
                )
            )
            gas_ok = (
                is_zero(gas.get("q6Strength"))
                and as_int(gas.get("activeCells"), -1) == 0
                and as_int(gas.get("correctedParticles"), -1) == 0
                and is_zero(gas.get("correctionMaxAbs"))
                and is_zero(gas.get("momentumX"))
                and is_zero(gas.get("momentumY"))
            )
            q6_ok = resident_ok and liquid_ok and gas_ok
            active_cells = liquid.get("activeCells", "")
            corrected_particles = liquid.get("correctedParticles", "")
            before = as_float(liquid.get("divBeforeRms"), 0.0)
            after = as_float(liquid.get("divAfterAppliedCellVelocityRms"))
            applied_ratio = after / before if before > 0.0 and math.isfinite(after) else ""

        accumulated_side_hits = sum(
            max(0, as_int(row.get("hitsLeft"), 0)) +
            max(0, as_int(row.get("hitsRight"), 0))
            for row in summary
        )
        accumulated_vertical_hits = sum(
            max(0, as_int(row.get("hitsBottom"), 0)) +
            max(0, as_int(row.get("hitsTop"), 0))
            for row in summary
        )

        passed = step_ok and params_closed_ok and conservation_ok and q6_ok
        all_ok = all_ok and passed
        results.append(
            {
                "mode": mode,
                "pass": int(passed),
                "finalStep": final.get("step", ""),
                "closedBoxParams": int(params_closed_ok),
                "noOpenBoundaryMutation": int(no_open_mutation),
                "liquidParticlesExpected": liquid_particles_expected,
                "liquidParticlesFinal": liquid_species.get("nFluid", ""),
                "gasParticlesExpected": gas_particles_expected,
                "gasParticlesFinal": gas_species.get("nFluid", ""),
                "liquidMassExpected": liquid_mass_expected,
                "liquidMassFinal": liquid_species.get("totalMass", ""),
                "gasMassExpected": gas_mass_expected,
                "gasMassFinal": gas_species.get("totalMass", ""),
                "sampledSideWallHits": accumulated_side_hits,
                "sampledBottomTopWallHits": accumulated_vertical_hits,
                "liquidActiveCells": active_cells,
                "liquidCorrectedParticles": corrected_particles,
                "liquidAppliedDivergenceRatio": applied_ratio,
            }
        )
        print(
            f"[0493x0] mode={mode} {'PASS' if passed else 'FAIL'} "
            f"step={final.get('step', '')} closedBox={int(params_closed_ok)} "
            f"openMutation={int(not no_open_mutation)} "
            f"liquidN={liquid_species.get('nFluid', '')}/{liquid_particles_expected} "
            f"gasN={gas_species.get('nFluid', '')}/{gas_particles_expected} "
            f"sideHits={accumulated_side_hits} activeLiquidCells={active_cells} "
            f"correctedLiquid={corrected_particles} appliedRatio={applied_ratio}"
        )

    report = args.run_root / "dam_break_demo_0493x0.csv"
    with report.open("w", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(results[0]))
        writer.writeheader()
        writer.writerows(results)
    print(f"[0493x0] matrix={sum(int(row['pass']) for row in results)}/{len(results)} report={report}")
    return 0 if all_ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
