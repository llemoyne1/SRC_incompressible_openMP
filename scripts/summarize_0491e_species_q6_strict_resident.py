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
    "full-state rollback",
    "non-finite",
    "nonfinite",
)

STRICT_COLUMNS = {
    "species_q6_device_resident": "1",
    "species_q6_host_cell_array_entries": "0",
    "species_q6_weight_h2d": "0",
    "species_q6_full_state_download": "0",
    "species_q6_cpu_fallback": "0",
    "species_q6_remaining_cpu_scope": "none",
}


def finite(value):
    try:
        return math.isfinite(float(value))
    except (TypeError, ValueError):
        return False


def truthy(value):
    return str(value).strip().lower() in {"1", "true", "yes", "on", "enabled"}


def read_rows(path):
    if not path.is_file():
        return []
    with path.open(newline="") as stream:
        return list(csv.DictReader(stream))


def read_kv(path):
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


def marker_text(paths):
    chunks = []
    for path in paths:
        if path.is_file():
            chunks.append(path.read_text(errors="replace").lower())
    return "\n".join(chunks)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--run-root", required=True)
    parser.add_argument("--expected-steps", type=int, required=True)
    parser.add_argument("--csv", required=True)
    parser.add_argument("--markdown", required=True)
    args = parser.parse_args()

    run = Path(args.run_root)
    output = run / "output"
    params = read_kv(run / "params" / "species_q6_strict_resident_0491e.kv")
    env = read_kv(run / "logs" / "environment_0491e.env")
    audit_rows = read_rows(output / "cuda_species_q6_0491.csv")
    summary_rows = read_rows(output / "summary_runtime.csv")
    text = marker_text([run / "logs" / "species_q6_strict_resident_0491e.log"])
    markers = sorted({marker for marker in BAD_MARKERS if marker in text})

    audit_last = audit_rows[-1] if audit_rows else {}
    summary_last = summary_rows[-1] if summary_rows else {}
    strict_ok = bool(audit_rows)
    strict_failures = []
    for key, expected in STRICT_COLUMNS.items():
        got = audit_last.get(key, "")
        if str(got).strip() != expected:
            strict_ok = False
            strict_failures.append(f"{key}={got!r} expected {expected!r}")

    step_ok = bool(audit_last) and int(float(audit_last.get("step", "-1"))) >= args.expected_steps
    q6_ok = truthy(audit_last.get("q6Applied", "0")) and truthy(summary_last.get("q6Applied", "0"))
    residual = audit_last.get("barycentricResidualMaxAbs", "")
    tol = params.get("speciesQ6ComparisonTolerance", "")
    residual_ok = finite(residual) and finite(tol) and float(residual) <= float(tol)
    summary_ok = bool(summary_last) and all(
        finite(summary_last.get(key)) for key in ("kBTEstimate", "maxParticleSpeed", "totalMass")
    )
    env_ok = (
        env.get("MPCD_CUDA_Q6_RESIDENT_0400") == "1"
        and env.get("MPCD_CUDA_Q6_RESIDENT_STRICT_0400") == "1"
        and env.get("MPCD_CUDA_Q6_RESIDENT_SRC_STEP_0401") == "1"
    )
    params_ok = (
        truthy(params.get("speciesQ6Enable", "false"))
        and params.get("speciesQ6Mode", "") == "weighted"
        and finite(params.get("speciesQ6Sensitivity", ""))
        and float(params["speciesQ6Sensitivity"]) > 0.0
    )
    passed = (
        strict_ok
        and step_ok
        and q6_ok
        and residual_ok
        and summary_ok
        and env_ok
        and params_ok
        and not markers
    )

    row = {
        "pass": int(passed),
        "step": audit_last.get("step", ""),
        "auditRows": len(audit_rows),
        "q6Applied": int(q6_ok),
        "species_q6_device_resident": audit_last.get("species_q6_device_resident", ""),
        "species_q6_host_cell_array_entries": audit_last.get("species_q6_host_cell_array_entries", ""),
        "species_q6_weight_h2d": audit_last.get("species_q6_weight_h2d", ""),
        "species_q6_full_state_download": audit_last.get("species_q6_full_state_download", ""),
        "species_q6_cpu_fallback": audit_last.get("species_q6_cpu_fallback", ""),
        "species_q6_remaining_cpu_scope": audit_last.get("species_q6_remaining_cpu_scope", ""),
        "barycentricResidualMaxAbs": residual,
        "speciesQ6Tolerance": tol,
        "kBTEstimate": summary_last.get("kBTEstimate", ""),
        "maxParticleSpeed": summary_last.get("maxParticleSpeed", ""),
        "totalMass": summary_last.get("totalMass", ""),
        "badMarkers": ";".join(markers),
        "strictFailures": ";".join(strict_failures),
        "auditPath": str(output / "cuda_species_q6_0491.csv"),
    }

    csv_path = Path(args.csv)
    csv_path.parent.mkdir(parents=True, exist_ok=True)
    with csv_path.open("w", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(row))
        writer.writeheader()
        writer.writerow(row)

    lines = [
        "# 0491e strict resident species-Q6 audit",
        "",
        f"Result: **{'PASS' if passed else 'FAIL'}**",
        "",
        "| Check | Value |",
        "| --- | --- |",
        f"| step | {row['step']} |",
        f"| species_q6_device_resident | {row['species_q6_device_resident']} |",
        f"| species_q6_host_cell_array_entries | {row['species_q6_host_cell_array_entries']} |",
        f"| species_q6_weight_h2d | {row['species_q6_weight_h2d']} |",
        f"| species_q6_full_state_download | {row['species_q6_full_state_download']} |",
        f"| species_q6_cpu_fallback | {row['species_q6_cpu_fallback']} |",
        f"| species_q6_remaining_cpu_scope | {row['species_q6_remaining_cpu_scope']} |",
        f"| barycentric residual | {row['barycentricResidualMaxAbs']} / {row['speciesQ6Tolerance']} |",
        f"| bad markers | {row['badMarkers']} |",
        f"| strict failures | {row['strictFailures']} |",
    ]
    Path(args.markdown).write_text("\n".join(lines) + "\n")
    print(f"[0491e-summary] {'PASS' if passed else 'FAIL'}")
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
