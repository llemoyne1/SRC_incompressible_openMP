#!/usr/bin/env python3
import argparse
import csv
import math
from pathlib import Path

BAD_MARKERS = (
    "fatal error",
    "unsupported",
    "cpu fallback",
    "fallback cpu",
    "non-finite",
    "nonfinite",
    "strict path was requested but not handled",
    "independent_masked 0493w5 initially supports periodic",
)


def rows(path: Path):
    if not path.is_file():
        return []
    with path.open(newline="") as stream:
        return list(csv.DictReader(stream))


def finite(value):
    try:
        return math.isfinite(float(value))
    except (TypeError, ValueError):
        return False


def as_int(value, default=-1):
    try:
        return int(float(value))
    except (TypeError, ValueError):
        return default


def is_zero(value, tol=1.0e-15):
    return finite(value) and abs(float(value)) <= tol


def latest_type(audit_rows, particle_type):
    selected = [r for r in audit_rows if as_int(r.get("type")) == particle_type]
    return selected[-1] if selected else {}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True)
    parser.add_argument("--expected-steps", type=int, required=True)
    args = parser.parse_args()

    root = Path(args.root)
    launches = rows(root / "launch_status_0493w7.csv")
    if not launches:
        raise SystemExit("[0493w7-check] no launch rows")

    results = []
    for launch in launches:
        case = launch["case"]
        run = root / case
        log_path = run / "logs" / "independent_masked_multibc_0493w7.log"
        log_text = log_path.read_text(errors="replace").lower() if log_path.is_file() else ""
        markers = sorted({m for m in BAD_MARKERS if m in log_text})
        summary = rows(run / "output" / "summary_runtime.csv")
        generic = rows(run / "output" / "cuda_species_q6_0491.csv")
        independent = rows(
            run / "output" / "cuda_species_q6_independent_masked_0493w5.csv"
        )
        darcy = rows(run / "output" / "darcy_cost_0343.csv")
        final = summary[-1] if summary else {}
        q6 = generic[-1] if generic else {}
        liquid = latest_type(independent, 1)
        gas = latest_type(independent, 2)

        launch_ok = launch.get("exit_code") == "0"
        step_ok = bool(final) and as_int(final.get("step")) >= args.expected_steps
        resident_ok = (
            bool(q6)
            and q6.get("mode") == "independent_masked"
            and q6.get("boundaryFamily") == launch["expected_boundary_family"]
            and q6.get("openBoundaryEnabled") == launch["expected_open"]
            and q6.get("darcyBrinkmanEnable") == launch["expected_darcy"]
            and q6.get("species_q6_device_resident") == "1"
            and q6.get("species_q6_host_cell_array_entries") == "0"
            and q6.get("species_q6_weight_h2d") == "0"
            and q6.get("species_q6_full_state_download") == "0"
            and q6.get("species_q6_cpu_fallback") == "0"
            and q6.get("species_q6_remaining_cpu_scope") == "none"
            and q6.get("q6Applied") == "1"
            and q6.get("q6Converged") == "1"
        )
        liquid_ok = (
            bool(liquid)
            and finite(liquid.get("q6Strength"))
            and float(liquid["q6Strength"]) > 0.0
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
            bool(gas)
            and is_zero(gas.get("q6Strength"))
            and as_int(gas.get("activeCells"), -1) == 0
            and as_int(gas.get("correctedParticles"), -1) == 0
            and is_zero(gas.get("correctionMaxAbs"))
            and is_zero(gas.get("momentumX"))
            and is_zero(gas.get("momentumY"))
        )
        darcy_ok = True
        if launch["expected_darcy"] == "1":
            d = darcy[-1] if darcy else {}
            darcy_ok = (
                bool(d)
                and d.get("speciesQ6Enable") == "1"
                and d.get("q6ResidentInputFresh") == "1"
                and d.get("particleUploadSkipped") == "1"
                and finite(d.get("meanAlpha"))
                and float(d.get("meanAlpha")) > 0.0
            )
        else:
            darcy_ok = not darcy

        passed = (
            launch_ok
            and step_ok
            and resident_ok
            and liquid_ok
            and gas_ok
            and darcy_ok
            and not markers
        )
        results.append(
            {
                "case": case,
                "pass": int(passed),
                "exitCode": launch.get("exit_code", ""),
                "step": final.get("step", ""),
                "boundaryFamily": q6.get("boundaryFamily", ""),
                "openBoundaryEnabled": q6.get("openBoundaryEnabled", ""),
                "darcyBrinkmanEnable": q6.get("darcyBrinkmanEnable", ""),
                "liquidActiveCells": liquid.get("activeCells", ""),
                "liquidCorrectedParticles": liquid.get("correctedParticles", ""),
                "liquidProjectedRatio": (
                    float(liquid["divAfterProjectedFaceFluxRms"])
                    / max(float(liquid["divBeforeRms"]), 1.0e-300)
                    if finite(liquid.get("divAfterProjectedFaceFluxRms"))
                    and finite(liquid.get("divBeforeRms"))
                    else ""
                ),
                "liquidAppliedRatio": (
                    float(liquid["divAfterAppliedCellVelocityRms"])
                    / max(float(liquid["divBeforeRms"]), 1.0e-300)
                    if finite(liquid.get("divAfterAppliedCellVelocityRms"))
                    and finite(liquid.get("divBeforeRms"))
                    else ""
                ),
                "gasActiveCells": gas.get("activeCells", ""),
                "gasCorrectedParticles": gas.get("correctedParticles", ""),
                "darcyQ6ResidentInputFresh": (
                    darcy[-1].get("q6ResidentInputFresh", "") if darcy else ""
                ),
                "darcyParticleUploadSkipped": (
                    darcy[-1].get("particleUploadSkipped", "") if darcy else ""
                ),
                "badMarkers": ";".join(markers),
            }
        )

    csv_path = root / "independent_masked_multibc_0493w7.csv"
    with csv_path.open("w", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(results[0]))
        writer.writeheader()
        writer.writerows(results)

    passed_count = sum(r["pass"] for r in results)
    for r in results:
        print(
            f"[0493w7] {r['case']}: {'PASS' if r['pass'] else 'FAIL'} "
            f"family={r['boundaryFamily']} liquidAppliedRatio={r['liquidAppliedRatio']} "
            f"gasCorrected={r['gasCorrectedParticles']} "
            f"darcyFresh={r['darcyQ6ResidentInputFresh']}"
        )
    print(f"[0493w7] matrix={passed_count}/{len(results)} csv={csv_path}")
    return 0 if passed_count == len(results) else 1


if __name__ == "__main__":
    raise SystemExit(main())
