#!/usr/bin/env python3
"""Qualification summary for 0493x7f Q6-g-f static multi-BC runs."""

from __future__ import annotations

import argparse
import csv
import math
import re
from pathlib import Path


BAD_MARKERS = (
    "fatal error",
    "cpu fallback",
    "fallback cpu",
    "strict path was requested but not handled",
    "unsupported boundary condition",
    "moving or truncated fluid domain",
    "prestream q6 failed",
    "free_surface_masked 0493x5a is restricted to a static closed box",
    "non-finite",
    "nonfinite",
)


def rows(path: Path) -> list[dict[str, str]]:
    if not path.is_file():
        return []
    with path.open(newline="") as stream:
        return list(csv.DictReader(stream))


def finite(value: object) -> bool:
    try:
        return math.isfinite(float(value))
    except (TypeError, ValueError):
        return False


def f(value: object, default: float = math.nan) -> float:
    try:
        x = float(value)
        return x if math.isfinite(x) else default
    except (TypeError, ValueError):
        return default


def i(value: object, default: int = -1) -> int:
    try:
        return int(float(value))
    except (TypeError, ValueError):
        return default


def close(a: object, b: float, rel: float = 1.0e-10, abs_: float = 1.0e-12) -> bool:
    x = f(a)
    return math.isfinite(x) and abs(x - b) <= max(abs_, rel * max(abs(x), abs(b), 1.0))


def latest_type(audit: list[dict[str, str]], particle_type: int) -> dict[str, str]:
    selected = [r for r in audit if i(r.get("type")) == particle_type]
    return selected[-1] if selected else {}


def read_wall_seconds(log: Path) -> float:
    if not log.is_file():
        return math.nan
    value = math.nan
    rx = re.compile(r"^real\s+([0-9eE+\-.]+)\s*$")
    for line in log.read_text(errors="replace").splitlines():
        m = rx.match(line.strip())
        if m:
            value = f(m.group(1))
    return value


def bad_markers(log: Path) -> list[str]:
    if not log.is_file():
        return ["missing log"]
    text = log.read_text(errors="replace").lower()
    return [marker for marker in BAD_MARKERS if marker in text]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", required=True, type=Path)
    ap.add_argument("--expected-steps", required=True, type=int)
    ap.add_argument("--tau", required=True, type=float)
    ap.add_argument("--dt", required=True, type=float)
    ap.add_argument("--liquid-type", default=1, type=int)
    ap.add_argument("--gas-type", default=2, type=int)
    args = ap.parse_args()

    launches = rows(args.root / "launch_status_0493x7f.csv")
    if not launches:
        raise SystemExit("[0493x7f] missing/empty launch_status_0493x7f.csv")

    expected_beta = args.dt / args.tau
    results: list[dict[str, object]] = []

    for launch in launches:
        case = launch["case"]
        case_root = args.root / case
        out = case_root / "output"
        log = case_root / "logs/q6_g_f_multibc_0493x7f.log"

        resident = rows(out / "cuda_species_q6_0491.csv")
        masked = rows(out / "cuda_species_q6_independent_masked_0493w5.csv")
        geometry = rows(out / "cuda_phase_geometry_resident_0493x6c.csv")
        stencil = rows(out / "cuda_phase_interface_stencil_0493x6f.csv")
        pressure = rows(out / "cuda_phase_interface_pressure_0493x6g.csv")

        q6 = resident[-1] if resident else {}
        liquid = latest_type(masked, args.liquid_type)
        gas = latest_type(masked, args.gas_type)
        geom = geometry[-1] if geometry else {}
        st = stencil[-1] if stencil else {}
        pg = pressure[-1] if pressure else {}
        markers = bad_markers(log)

        launch_ok = launch.get("exit_code") == "0"
        step_ok = (
            i(q6.get("step")) == args.expected_steps
            and i(liquid.get("step")) == args.expected_steps
        )
        family_ok = (
            bool(q6)
            and q6.get("boundaryFamily") == launch.get("expected_boundary_family")
            and i(q6.get("openBoundaryEnabled"), -1) == i(launch.get("expected_open"), -2)
        )
        resident_ok = (
            bool(q6)
            and q6.get("mode") == "free_surface_masked"
            and q6.get("species_q6_device_resident") == "1"
            and q6.get("species_q6_host_cell_array_entries") == "0"
            and q6.get("species_q6_weight_h2d") == "0"
            and q6.get("species_q6_full_state_download") == "0"
            and q6.get("species_q6_cpu_fallback") == "0"
            and q6.get("species_q6_remaining_cpu_scope") == "none"
            and q6.get("q6Applied") == "1"
            and q6.get("q6Converged") == "1"
            and all(finite(q6.get(k)) for k in ("solveSeconds", "applySeconds", "totalSeconds"))
        )
        liquid_ok = (
            bool(liquid)
            and f(liquid.get("q6Strength"), 0.0) > 0.0
            and i(liquid.get("activeCells"), 0) > 0
            and i(liquid.get("correctedParticles"), 0) > 0
            and liquid.get("converged") == "1"
            and close(liquid.get("q6DensityRelaxationTime"), args.tau)
            and close(liquid.get("q6DensityRelaxationBeta"), expected_beta)
            and all(
                finite(liquid.get(k))
                for k in (
                    "residualRel",
                    "divBeforeRms",
                    "divAfterProjectedFaceFluxRms",
                    "divAfterAppliedCellVelocityRms",
                    "densityRelaxationTargetDivRms",
                )
            )
        )
        gas_ok = (
            bool(gas)
            and close(gas.get("q6Strength"), 0.0)
            and i(gas.get("activeCells"), -1) == 0
            and i(gas.get("correctedParticles"), -1) == 0
            and close(gas.get("correctionMaxAbs"), 0.0, abs_=1.0e-14)
        )
        geometry_ok = (
            bool(geom)
            and i(geom.get("projectedType")) == args.liquid_type
            and i(geom.get("liquidPhaseSpeciesCount"), 0) >= 1
            and f(geom.get("rawFillSum"), 0.0) > 0.0
            and finite(geom.get("boundedGeometrySourceSum"))
            and finite(geom.get("conservationRelativeError"))
        )
        stencil_ok = (
            bool(st)
            and i(st.get("projectedType")) == args.liquid_type
            and i(st.get("pressureActiveCells"), 0) > 0
            and i(st.get("representedInterfaceFaces"), 0) > 0
            and i(st.get("uncoveredInterfaceFaces"), -1) == 0
            and i(st.get("carrierTruncationFaces"), -1) == 0
            and finite(st.get("prepareSeconds"))
        )
        pressure_ok = (
            bool(pg)
            and i(pg.get("projectedType")) == args.liquid_type
            and i(pg.get("gasSpeciesCount"), 0) >= 1
            and pg.get("sourceMode") == "eos"
            and close(pg.get("pressureScale"), 1.0)
            and i(pg.get("representedInterfaceFaces"), 0) > 0
            and finite(pg.get("pressureDeltaMean"))
            and finite(pg.get("pressureDeltaStd"))
        )

        passed = all(
            (
                launch_ok,
                step_ok,
                family_ok,
                resident_ok,
                liquid_ok,
                gas_ok,
                geometry_ok,
                stencil_ok,
                pressure_ok,
                not markers,
            )
        )

        result = {
            "case": case,
            "pass": int(passed),
            "exitCode": launch.get("exit_code", ""),
            "boundaryFamily": q6.get("boundaryFamily", ""),
            "openBoundaryEnabled": q6.get("openBoundaryEnabled", ""),
            "zeroBodyForce": launch.get("zero_body_force", ""),
            "step": q6.get("step", ""),
            "liquidActiveCells": liquid.get("activeCells", ""),
            "liquidCorrectedParticles": liquid.get("correctedParticles", ""),
            "q6Iterations": q6.get("q6Iterations", ""),
            "q6ResidualRel": liquid.get("residualRel", ""),
            "densityRelaxationTargetDivRms": liquid.get("densityRelaxationTargetDivRms", ""),
            "q6ProjectedConstraintResidualRms": liquid.get("divAfterProjectedFaceFluxRms", ""),
            "q6AppliedRms": liquid.get("divAfterAppliedCellVelocityRms", ""),
            "representedInterfaceFaces": st.get("representedInterfaceFaces", ""),
            "uncoveredInterfaceFaces": st.get("uncoveredInterfaceFaces", ""),
            "carrierTruncationFaces": st.get("carrierTruncationFaces", ""),
            "x6gNonzeroPressureFaces": pg.get("nonzeroPressureFaces", ""),
            "x6gPressureDeltaStd": pg.get("pressureDeltaStd", ""),
            "depositSeconds": q6.get("depositSeconds", ""),
            "solveSeconds": q6.get("solveSeconds", ""),
            "applySeconds": q6.get("applySeconds", ""),
            "totalSeconds": q6.get("totalSeconds", ""),
            "wallSeconds": read_wall_seconds(log),
            "badMarkers": ";".join(markers),
        }
        results.append(result)

        print(
            f"[0493x7f] {case}: {'PASS' if passed else 'FAIL'} "
            f"family={result['boundaryFamily']} active={result['liquidActiveCells']} "
            f"iface={result['representedInterfaceFaces']} "
            f"q6A={result['q6AppliedRms']} total={result['totalSeconds']}s "
            f"wall={result['wallSeconds']:.6g}s"
        )
        if not passed:
            flags = {
                "launch": launch_ok,
                "step": step_ok,
                "family": family_ok,
                "resident": resident_ok,
                "liquid": liquid_ok,
                "gas": gas_ok,
                "geometry": geometry_ok,
                "stencil": stencil_ok,
                "pressure": pressure_ok,
                "markers": not markers,
            }
            print(f"[0493x7f]   checks={flags} badMarkers={markers}")

    csv_path = args.root / "q6_g_f_multibc_0493x7f.csv"
    with csv_path.open("w", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(results[0]))
        writer.writeheader()
        writer.writerows(results)

    n_pass = sum(int(r["pass"]) for r in results)
    print(f"[0493x7f] matrix={n_pass}/{len(results)} csv={csv_path}")
    return 0 if n_pass == len(results) else 1


if __name__ == "__main__":
    raise SystemExit(main())
