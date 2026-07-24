#!/usr/bin/env python3
import argparse
import csv
import math
from pathlib import Path

CASES = (
    "common_no_thermostat",
    "weighted_no_thermostat",
    "common_thermostat",
    "weighted_thermostat",
)

BAD_MARKERS = (
    "fatal error",
    "unsupported",
    "cpu fallback",
    "fallback cpu",
    "non-finite",
    "nonfinite",
)


def finite(value):
    try:
        return math.isfinite(float(value))
    except (TypeError, ValueError):
        return False


def truthy(value):
    return str(value).strip().lower() in {"1", "true", "yes", "on", "enabled"}


def rows(path):
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


def markers_for(run):
    chunks = []
    for path in [run / "logs" / "species_q6_energy_0491f.log"]:
        if path.is_file():
            chunks.append(path.read_text(errors="replace").lower())
    text = "\n".join(chunks)
    return sorted({marker for marker in BAD_MARKERS if marker in text})


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True)
    parser.add_argument("--expected-steps", type=int, required=True)
    parser.add_argument("--csv", required=True)
    parser.add_argument("--markdown", required=True)
    parser.add_argument("--thermostat-tolerance", type=float, default=1.0e-10)
    parser.add_argument("--mean-flow-tolerance", type=float, default=1.0e-12)
    parser.add_argument("--mass-relative-tolerance", type=float, default=1.0e-13)
    args = parser.parse_args()

    root = Path(args.root)
    out_rows = []
    for case in CASES:
        run = root / case
        params = kv(run / "params" / "species_q6_energy_0491f.kv")
        summary = rows(run / "output" / "summary_runtime.csv")
        q6audit = rows(run / "output" / "cuda_species_q6_0491.csv")
        energy = rows(run / "output" / "cuda_species_q6_energy_0491f.csv")
        final = summary[-1] if summary else {}
        first = summary[0] if summary else {}
        q6last = q6audit[-1] if q6audit else {}
        elast = energy[-1] if energy else {}
        markers = markers_for(run)

        thermostat_expected = case in {"common_thermostat", "weighted_thermostat"}
        tol = params.get("speciesQ6ComparisonTolerance", "")
        residual = final.get("q6SpeciesQ6BarycentricResidualMaxAbs", "")
        mass0 = first.get("totalMass", "")
        mass1 = final.get("totalMass", "")
        mass_rel = ""
        if finite(mass0) and finite(mass1) and abs(float(mass0)) > 0.0:
            mass_rel = abs(float(mass1) - float(mass0)) / abs(float(mass0))
        mean_v = ""
        if finite(final.get("meanVx")) and finite(final.get("meanVy")):
            mean_v = math.hypot(float(final["meanVx"]), float(final["meanVy"]))

        q6_ok = (
            bool(summary)
            and bool(q6audit)
            and truthy(final.get("q6Applied", "0"))
            and truthy(q6last.get("q6Applied", "0"))
            and finite(residual)
            and finite(tol)
            and float(residual) <= float(tol)
        )
        numeric_ok = bool(final) and all(
            finite(final.get(key))
            for key in ("kBTEstimate", "maxParticleSpeed", "totalMass", "meanVx", "meanVy")
        )
        step_ok = bool(final) and int(float(final.get("step", "-1"))) >= args.expected_steps
        mass_ok = finite(mass_rel) and float(mass_rel) <= args.mass_relative_tolerance
        mean_flow_ok = finite(mean_v) and float(mean_v) <= args.mean_flow_tolerance

        if thermostat_expected:
            thermostat_ok = (
                bool(energy)
                and truthy(elast.get("thermostat_device_resident", "0"))
                and elast.get("thermostat_cpu_fallback", "") == "0"
                and truthy(elast.get("thermostatApplied", "0"))
                and truthy(final.get("thermostatApplied", "0"))
                and finite(elast.get("thermostatKBTErrorAbs", ""))
                and float(elast["thermostatKBTErrorAbs"]) <= args.thermostat_tolerance
            )
        else:
            thermostat_ok = (
                not energy
                and not truthy(final.get("thermostatApplied", "0"))
            )

        passed = (
            q6_ok
            and numeric_ok
            and step_ok
            and mass_ok
            and mean_flow_ok
            and thermostat_ok
            and not markers
        )
        out_rows.append({
            "case": case,
            "pass": int(passed),
            "step": final.get("step", ""),
            "speciesQ6Mode": params.get("speciesQ6Mode", ""),
            "thermostatExpected": int(thermostat_expected),
            "thermostatApplied": final.get("thermostatApplied", ""),
            "thermostatKBTBefore": elast.get("thermostatKBTBefore", final.get("thermostatKBTBefore", "")),
            "thermostatKBTAfter": elast.get("thermostatKBTAfter", final.get("thermostatKBTAfter", "")),
            "thermostatKBTErrorAbs": elast.get("thermostatKBTErrorAbs", ""),
            "kBTEstimate": final.get("kBTEstimate", ""),
            "meanVNorm": mean_v,
            "massRelativeDrift": mass_rel,
            "q6SpeciesResidualMaxAbs": residual,
            "speciesQ6Tolerance": tol,
            "q6EnergyAuditRows": len(energy),
            "badMarkers": ";".join(markers),
            "summaryPath": str(run / "output" / "summary_runtime.csv"),
        })

    csv_path = Path(args.csv)
    csv_path.parent.mkdir(parents=True, exist_ok=True)
    with csv_path.open("w", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(out_rows[0]))
        writer.writeheader()
        writer.writerows(out_rows)

    passed_count = sum(row["pass"] for row in out_rows)
    lines = [
        "# 0491f species-Q6 energy validation",
        "",
        f"Pass: **{passed_count}/{len(out_rows)}**",
        "",
        "| Case | Result | Thermostat | kBT after | kBT error | mean | mass drift | Q6 residual |",
        "| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |",
    ]
    for row in out_rows:
        lines.append(
            f"| {row['case']} | {'PASS' if row['pass'] else 'FAIL'} | "
            f"{row['thermostatApplied']} | {row['thermostatKBTAfter']} | "
            f"{row['thermostatKBTErrorAbs']} | {row['meanVNorm']} | "
            f"{row['massRelativeDrift']} | {row['q6SpeciesResidualMaxAbs']} |"
        )
    Path(args.markdown).write_text("\n".join(lines) + "\n")
    print(f"[0491f-summary] pass={passed_count}/{len(out_rows)}")
    return 0 if passed_count == len(out_rows) else 1


if __name__ == "__main__":
    raise SystemExit(main())
