#!/usr/bin/env python3
"""Validate the diagnostic-only 0493x6a phase-interface pressure scaffold."""

from __future__ import annotations

import argparse
import csv
import json
import math
from pathlib import Path


def finite(row: dict[str, str], key: str) -> float:
    value = float(row[key])
    if not math.isfinite(value):
        raise RuntimeError(f"non-finite {key}: {row[key]}")
    return value


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--audit", type=Path, required=True)
    parser.add_argument("--json", type=Path, required=True)
    parser.add_argument("--relative-tolerance", type=float, default=5.0e-12)
    args = parser.parse_args()

    if not args.audit.exists():
        raise RuntimeError(f"missing 0493x6a audit: {args.audit}")
    with args.audit.open(newline="") as stream:
        rows = list(csv.DictReader(stream))
    if not rows:
        raise RuntimeError("empty 0493x6a pressure audit")

    required = {
        "step", "time", "projectedSpeciesIndex", "projectedType", "gasSpeciesCount",
        "projectedLiquidReferenceCellMass", "cellArea", "kBT", "dt",
        "interfaceFaces", "meanGasParticlesPerExteriorFace", "pressureEOSMean",
        "pressureEOSStd", "pressureEOSMax", "pressurePotentialMean",
        "pressurePotentialStd", "pressurePotentialMax", "pressurePotentialDefinition",
    }
    missing = required.difference(rows[0])
    if missing:
        raise RuntimeError(f"audit missing columns: {sorted(missing)}")

    max_relation_error = 0.0
    min_faces = None
    max_faces = 0
    max_gas_per_face = 0.0
    max_pressure = 0.0
    max_phi = 0.0
    all_have_gas_phase = True
    all_definition_ok = True

    for row in rows:
        ref_mass = finite(row, "projectedLiquidReferenceCellMass")
        area = finite(row, "cellArea")
        dt = finite(row, "dt")
        kbt = finite(row, "kBT")
        faces = int(row["interfaceFaces"])
        gas_species = int(row["gasSpeciesCount"])
        mean_ng = finite(row, "meanGasParticlesPerExteriorFace")
        p_mean = finite(row, "pressureEOSMean")
        phi_mean = finite(row, "pressurePotentialMean")
        p_std = finite(row, "pressureEOSStd")
        phi_std = finite(row, "pressurePotentialStd")
        p_max = finite(row, "pressureEOSMax")
        phi_max = finite(row, "pressurePotentialMax")

        if not (ref_mass > 0.0 and area > 0.0 and dt > 0.0):
            raise RuntimeError("invalid positive scale in 0493x6a audit")
        if min(p_mean, p_std, p_max, phi_mean, phi_std, phi_max, mean_ng) < 0.0:
            raise RuntimeError("negative EOS pressure/potential statistic")
        all_have_gas_phase = all_have_gas_phase and gas_species > 0
        all_definition_ok = all_definition_ok and (
            row["pressurePotentialDefinition"] == "phi=dt*p/rho_liquid_ref"
        )
        if faces <= 0:
            raise RuntimeError(f"step {row['step']}: no liquid-exterior interface faces")

        rho_ref = ref_mass / area
        expected_phi = dt * p_mean / rho_ref
        scale = max(1.0e-300, abs(expected_phi), abs(phi_mean))
        max_relation_error = max(max_relation_error, abs(phi_mean - expected_phi) / scale)

        expected_ng = p_mean * area / kbt if kbt > 0.0 else 0.0
        if kbt > 0.0:
            ng_scale = max(1.0, abs(expected_ng), abs(mean_ng))
            max_relation_error = max(
                max_relation_error, abs(mean_ng - expected_ng) / ng_scale
            )

        min_faces = faces if min_faces is None else min(min_faces, faces)
        max_faces = max(max_faces, faces)
        max_gas_per_face = max(max_gas_per_face, mean_ng)
        max_pressure = max(max_pressure, p_max)
        max_phi = max(max_phi, phi_max)

    pass_like = (
        all_have_gas_phase
        and all_definition_ok
        and max_relation_error <= args.relative_tolerance
    )
    first = rows[0]
    last = rows[-1]
    report = {
        "status": "PASS-like" if pass_like else "FAIL-like",
        "rows": len(rows),
        "firstStep": int(first["step"]),
        "lastStep": int(last["step"]),
        "gasSpeciesPresentAllRows": all_have_gas_phase,
        "pressurePotentialDefinitionOK": all_definition_ok,
        "maxPressurePotentialRelationRelativeError": max_relation_error,
        "interfaceFacesMin": min_faces,
        "interfaceFacesMax": max_faces,
        "maxMeanGasParticlesPerExteriorFace": max_gas_per_face,
        "maxPressureEOS": max_pressure,
        "maxPressurePotential": max_phi,
        "firstPressureEOSMean": float(first["pressureEOSMean"]),
        "lastPressureEOSMean": float(last["pressureEOSMean"]),
        "firstPressurePotentialMean": float(first["pressurePotentialMean"]),
        "lastPressurePotentialMean": float(last["pressurePotentialMean"]),
    }
    args.json.parent.mkdir(parents=True, exist_ok=True)
    args.json.write_text(json.dumps(report, indent=2) + "\n")

    print(
        "[0493x6a-analysis] "
        f"status={report['status']} rows={report['rows']} "
        f"steps={report['firstStep']}..{report['lastStep']} "
        f"faces={report['interfaceFacesMin']}..{report['interfaceFacesMax']} "
        f"pMean={report['firstPressureEOSMean']:.6e}->{report['lastPressureEOSMean']:.6e} "
        f"phiMean={report['firstPressurePotentialMean']:.6e}->{report['lastPressurePotentialMean']:.6e} "
        f"relationErr={report['maxPressurePotentialRelationRelativeError']:.3e}"
    )
    return 0 if pass_like else 1


if __name__ == "__main__":
    raise SystemExit(main())
