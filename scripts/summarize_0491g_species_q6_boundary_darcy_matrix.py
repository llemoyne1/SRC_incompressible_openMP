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
)


def finite(value):
    try:
        return math.isfinite(float(value))
    except (TypeError, ValueError):
        return False


def truthy(value):
    return str(value).strip().lower() in {"1", "true", "yes", "on", "enabled"}


def csv_rows(path):
    if not path.is_file():
        return []
    with path.open(newline="") as stream:
        return list(csv.DictReader(stream))


def kv(path):
    out = {}
    if not path.is_file():
        return out
    for line in path.read_text(errors="replace").splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#") or "=" not in stripped:
            continue
        key, value = stripped.split("=", 1)
        out[key.strip()] = value.strip()
    return out


def log_markers(run):
    text = ""
    path = run / "logs" / "species_q6_boundary_darcy_0491g.log"
    if path.is_file():
        text = path.read_text(errors="replace").lower()
    return sorted({marker for marker in BAD_MARKERS if marker in text})


def launch_rows(root):
    path = root / "launch_status_0491g.csv"
    if not path.is_file():
        return []
    return csv_rows(path)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True)
    parser.add_argument("--expected-steps", type=int, required=True)
    parser.add_argument("--csv", required=True)
    parser.add_argument("--markdown", required=True)
    args = parser.parse_args()

    root = Path(args.root)
    out_rows = []
    for launch in launch_rows(root):
        case = launch["case"]
        run = root / case
        params = kv(run / "params" / "species_q6_boundary_darcy_0491g.kv")
        summary = csv_rows(run / "output" / "summary_runtime.csv")
        q6audit = csv_rows(run / "output" / "cuda_species_q6_0491.csv")
        darcy = csv_rows(run / "output" / "darcy_cost_0343.csv")
        final = summary[-1] if summary else {}
        q6last = q6audit[-1] if q6audit else {}
        dlast = darcy[-1] if darcy else {}
        markers = log_markers(run)

        expected_family = launch["expected_boundary_family"]
        expected_open = launch["expected_open"]
        expected_darcy = launch["expected_darcy"]
        expected_injection_type = launch["expected_injection_type"]
        residual = final.get("q6SpeciesQ6BarycentricResidualMaxAbs", "")
        tol = params.get("speciesQ6ComparisonTolerance", "")

        launch_ok = launch.get("exit_code", "") == "0"
        step_ok = bool(final) and int(float(final.get("step", "-1"))) >= args.expected_steps
        numeric_ok = bool(final) and all(
            finite(final.get(key))
            for key in ("kBTEstimate", "maxParticleSpeed", "totalMass", "meanVx", "meanVy")
        )
        q6_ok = (
            bool(q6audit)
            and truthy(final.get("q6Applied", "0"))
            and truthy(q6last.get("q6Applied", "0"))
            and q6last.get("boundaryFamily", "") == expected_family
            and q6last.get("openBoundaryEnabled", "") == expected_open
            and q6last.get("darcyBrinkmanEnable", "") == expected_darcy
            and q6last.get("species_q6_device_resident", "") == "1"
            and q6last.get("species_q6_host_cell_array_entries", "") == "0"
            and q6last.get("species_q6_full_state_download", "") == "0"
            and q6last.get("species_q6_cpu_fallback", "") == "0"
            and q6last.get("species_q6_remaining_cpu_scope", "") == "none"
            and finite(residual)
            and finite(tol)
            and float(residual) <= float(tol)
        )

        open_ok = True
        if expected_open == "1":
            open_ok = truthy(final.get("q6OpenBoundaryEnabled", q6last.get("openBoundaryEnabled", "0")))

        injection_ok = True
        if expected_injection_type != "none":
            seg0 = params.get("openBoundarySegment0", "")
            injection_ok = (
                bool(seg0)
                and " inlet " in f" {seg0} "
                and seg0.split()[-2] == expected_injection_type
            )

        darcy_ok = True
        if expected_darcy == "1":
            darcy_ok = (
                bool(darcy)
                and dlast.get("speciesQ6Enable", "") == "1"
                and dlast.get("q6ResidentInputFresh", "") == "1"
                and dlast.get("particleUploadSkipped", "") == "1"
                and all(finite(dlast.get(key)) for key in ("mass", "meanChi", "meanAlpha", "darcyPower"))
                and float(dlast.get("meanAlpha", "0")) > 0.0
            )
        else:
            darcy_ok = not darcy

        passed = (
            launch_ok
            and step_ok
            and numeric_ok
            and q6_ok
            and open_ok
            and injection_ok
            and darcy_ok
            and not markers
        )
        out_rows.append({
            "case": case,
            "pass": int(passed),
            "exitCode": launch.get("exit_code", ""),
            "step": final.get("step", ""),
            "expectedBoundaryFamily": expected_family,
            "boundaryFamily": q6last.get("boundaryFamily", ""),
            "expectedOpen": expected_open,
            "openBoundaryEnabled": q6last.get("openBoundaryEnabled", ""),
            "expectedDarcy": expected_darcy,
            "darcyBrinkmanEnable": q6last.get("darcyBrinkmanEnable", ""),
            "expectedInjectionType": expected_injection_type,
            "segmentedInletType": params.get("openBoundarySegment0", "").split()[-2] if params.get("openBoundarySegment0", "") else "",
            "q6Applied": final.get("q6Applied", ""),
            "q6SpeciesResidualMaxAbs": residual,
            "speciesQ6Tolerance": tol,
            "darcyRows": len(darcy),
            "darcyMeanAlpha": dlast.get("meanAlpha", ""),
            "darcyPower": dlast.get("darcyPower", ""),
            "darcyQ6ResidentInputFresh": dlast.get("q6ResidentInputFresh", ""),
            "darcyParticleUploadSkipped": dlast.get("particleUploadSkipped", ""),
            "kBTEstimate": final.get("kBTEstimate", ""),
            "totalMass": final.get("totalMass", ""),
            "maxParticleSpeed": final.get("maxParticleSpeed", ""),
            "badMarkers": ";".join(markers),
            "summaryPath": str(run / "output" / "summary_runtime.csv"),
        })

    if not out_rows:
        raise SystemExit("[0491g-summary] no launch rows found")

    csv_path = Path(args.csv)
    csv_path.parent.mkdir(parents=True, exist_ok=True)
    with csv_path.open("w", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(out_rows[0]))
        writer.writeheader()
        writer.writerows(out_rows)

    passed_count = sum(row["pass"] for row in out_rows)
    lines = [
        "# 0491g species-Q6 boundary/Darcy matrix",
        "",
        f"Pass: **{passed_count}/{len(out_rows)}**",
        "",
        "| Case | Result | Boundary | Open | Darcy | alpha | Darcy fresh | Injected type | Q6 residual |",
        "| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |",
    ]
    for row in out_rows:
        lines.append(
            f"| {row['case']} | {'PASS' if row['pass'] else 'FAIL'} | "
            f"{row['boundaryFamily']} | {row['openBoundaryEnabled']} | "
            f"{row['darcyBrinkmanEnable']} | {row['darcyMeanAlpha']} | "
            f"{row['darcyQ6ResidentInputFresh']} | "
            f"{row['segmentedInletType']} | {row['q6SpeciesResidualMaxAbs']} |"
        )
    Path(args.markdown).write_text("\n".join(lines) + "\n")
    print(f"[0491g-summary] pass={passed_count}/{len(out_rows)}")
    return 0 if passed_count == len(out_rows) else 1


if __name__ == "__main__":
    raise SystemExit(main())
