#!/usr/bin/env python3
"""Cross-audit the 0493x7g Q6-g-f + deterministic Darcy/chi qualification."""

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
    "prestream q6 failed",
    "prestream darcy/chi was requested but not handled",
    "non-finite",
    "nonfinite",
)


def rows(path: Path) -> list[dict[str, str]]:
    if not path.is_file():
        return []
    with path.open(newline="") as stream:
        return list(csv.DictReader(stream))


def f(value: object, default: float = math.nan) -> float:
    try:
        x = float(value)
        return x if math.isfinite(x) else default
    except (TypeError, ValueError):
        return default


def finite(value: object) -> bool:
    return math.isfinite(f(value))


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


def bad_markers(log: Path) -> list[str]:
    if not log.is_file():
        return ["missing log"]
    text = log.read_text(errors="replace").lower()
    return [marker for marker in BAD_MARKERS if marker in text]


def wall_seconds(log: Path) -> float:
    if not log.is_file():
        return math.nan
    rx = re.compile(r"^real\s+([0-9eE+\-.]+)\s*$")
    value = math.nan
    for line in log.read_text(errors="replace").splitlines():
        m = rx.match(line.strip())
        if m:
            value = f(m.group(1))
    return value


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", required=True, type=Path)
    ap.add_argument("--expected-steps", required=True, type=int)
    ap.add_argument("--tau", required=True, type=float)
    ap.add_argument("--dt", required=True, type=float)
    ap.add_argument("--liquid-type", default=1, type=int)
    ap.add_argument("--gas-type", default=2, type=int)
    args = ap.parse_args()

    launches = rows(args.root / "launch_status_0493x7g.csv")
    if not launches:
        raise SystemExit("[0493x7g] missing/empty launch_status_0493x7g.csv")

    expected_beta = args.dt / args.tau
    summary: list[dict[str, object]] = []

    for launch in launches:
        case = launch["case"]
        case_root = args.root / case
        out = case_root / "output"
        log = case_root / "logs/q6_g_f_darcy_0493x7g.log"
        params_path = case_root / "params/q6_g_f_darcy_0493x7g.kv"

        resident = rows(out / "cuda_species_q6_0491.csv")
        masked = rows(out / "cuda_species_q6_independent_masked_0493w5.csv")
        geometry = rows(out / "cuda_phase_geometry_resident_0493x6c.csv")
        stencil = rows(out / "cuda_phase_interface_stencil_0493x6f.csv")
        pressure = rows(out / "cuda_phase_interface_pressure_0493x6g.csv")
        darcy_rows = rows(out / "darcy_cost_0343.csv")

        q6 = resident[-1] if resident else {}
        liquid = latest_type(masked, args.liquid_type)
        gas = latest_type(masked, args.gas_type)
        geom = geometry[-1] if geometry else {}
        st = stencil[-1] if stencil else {}
        pg = pressure[-1] if pressure else {}
        darcy = darcy_rows[-1] if darcy_rows else {}
        markers = bad_markers(log)
        params_text = params_path.read_text(errors="replace") if params_path.is_file() else ""

        launch_ok = launch.get("exit_code") == "0"
        step_ok = (
            i(q6.get("step")) == args.expected_steps
            and i(liquid.get("step")) == args.expected_steps
            and i(darcy.get("step")) == args.expected_steps
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
        )
        liquid_ok = (
            bool(liquid)
            and f(liquid.get("q6Strength"), 0.0) > 0.0
            and i(liquid.get("activeCells"), 0) > 0
            and i(liquid.get("correctedParticles"), 0) > 0
            and liquid.get("converged") == "1"
            and close(liquid.get("q6DensityRelaxationTime"), args.tau)
            and close(liquid.get("q6DensityRelaxationBeta"), expected_beta)
            and finite(liquid.get("divAfterProjectedFaceFluxRms"))
            and finite(liquid.get("divAfterAppliedCellVelocityRms"))
        )
        gas_ok = (
            bool(gas)
            and close(gas.get("q6Strength"), 0.0)
            and i(gas.get("activeCells"), -1) == 0
            and i(gas.get("correctedParticles"), -1) == 0
        )
        geometry_ok = (
            bool(geom)
            and i(geom.get("projectedType")) == args.liquid_type
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
        )
        pressure_ok = (
            bool(pg)
            and i(pg.get("projectedType")) == args.liquid_type
            and i(pg.get("gasSpeciesCount"), 0) >= 1
            and pg.get("sourceMode") == "eos"
            and close(pg.get("pressureScale"), 1.0)
            and i(pg.get("representedInterfaceFaces"), 0) > 0
        )

        # x7g's decisive ordering audit.  q6ResidentInputFresh is intentionally
        # not required: Darcy is upstream of Q6-g-f now.  What matters is that
        # Darcy itself consumes the resident state without a host upload and the
        # CSV identifies the pre-Q6 call explicitly.
        darcy_ok = (
            bool(darcy)
            and darcy.get("speciesQ6Enable") == "1"
            and darcy.get("q6GfPrestream") == "1"
            and darcy.get("particleUploadSkipped") == "1"
            and darcy.get("chiMode") == "file"
            and 0.0 < f(darcy.get("meanChi")) < 1.0
            and f(darcy.get("meanAlpha"), 0.0) > 0.0
            and all(finite(darcy.get(k)) for k in ("darcyPower", "meanSpeedRms", "solidLeakRms"))
        )
        if len(darcy_rows) > 1:
            resident_after_first = all(r.get("particleUploadSkipped") == "1" for r in darcy_rows[1:])
            prestream_all = all(r.get("q6GfPrestream") == "1" for r in darcy_rows)
            darcy_ok = darcy_ok and resident_after_first and prestream_all

        expect_chivp = launch.get("expected_chivp") == "1"
        chivp_ok = (
            ("darcyChiCollisionVpEnable = true" in params_text)
            if expect_chivp
            else ("darcyChiCollisionVpEnable = false" in params_text)
        )

        passed = all((
            launch_ok, step_ok, family_ok, resident_ok, liquid_ok, gas_ok,
            geometry_ok, stencil_ok, pressure_ok, darcy_ok, chivp_ok, not markers,
        ))

        item = {
            "case": case,
            "pass": int(passed),
            "family": q6.get("boundaryFamily", ""),
            "q6AppliedDiv": f(liquid.get("divAfterAppliedCellVelocityRms")),
            "meanChi": f(darcy.get("meanChi")),
            "meanAlpha": f(darcy.get("meanAlpha")),
            "solidLeakRms": f(darcy.get("solidLeakRms")),
            "darcyPrestream": darcy.get("q6GfPrestream", ""),
            "uploadSkipped": darcy.get("particleUploadSkipped", ""),
            "chiVP": int(expect_chivp),
            "wallSeconds": wall_seconds(log),
        }
        summary.append(item)

        verdict = "PASS" if passed else "FAIL"
        print(
            f"[0493x7g] {case}: {verdict} family={item['family']} "
            f"darcyPre={item['darcyPrestream']} uploadSkipped={item['uploadSkipped']} "
            f"chi={item['meanChi']:.6g} alpha={item['meanAlpha']:.6g} "
            f"leak={item['solidLeakRms']:.6g} q6A={item['q6AppliedDiv']:.6g} "
            f"chiVP={item['chiVP']} wall={item['wallSeconds']:.3g}s"
        )
        if not passed:
            print(
                "[0493x7g]   checks="
                f"launch:{launch_ok} step:{step_ok} family:{family_ok} resident:{resident_ok} "
                f"liquid:{liquid_ok} gas:{gas_ok} geometry:{geometry_ok} stencil:{stencil_ok} "
                f"pressure:{pressure_ok} darcy:{darcy_ok} chiVP:{chivp_ok} markers:{markers}"
            )

    out_csv = args.root / "q6_g_f_darcy_0493x7g.csv"
    with out_csv.open("w", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(summary[0].keys()))
        writer.writeheader()
        writer.writerows(summary)

    passed_count = sum(int(r["pass"]) for r in summary)
    print(f"[0493x7g] matrix={passed_count}/{len(summary)} csv={out_csv}")
    return 0 if passed_count == len(summary) else 1


if __name__ == "__main__":
    raise SystemExit(main())
