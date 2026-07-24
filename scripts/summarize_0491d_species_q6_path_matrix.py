#!/usr/bin/env python3
import argparse
import csv
import math
from pathlib import Path

MODES = ["src", "src-resampling", "src-q6", "src-q6-resampling"]
BAD_MARKERS = (
    "fatal error",
    "stale",
    "unsupported",
    "cpu fallback",
    "non-finite",
    "nonfinite",
)


def finite(value):
    try:
        return math.isfinite(float(value))
    except (TypeError, ValueError):
        return False


def read_last_csv(path):
    if not path.is_file():
        return {}
    with path.open(newline="") as stream:
        rows = list(csv.DictReader(stream))
    return rows[-1] if rows else {}


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


def truthy(value):
    return str(value).lower() in {"1", "true", "yes", "on", "enable", "enabled"}


def has_q6(mode):
    return "q6" in mode


def marker_text(log_path, run):
    chunks = []
    candidates = [log_path, *sorted((run / "logs").glob("*.log"))]
    for candidate in candidates:
        if candidate.is_file():
            chunks.append(candidate.read_text(errors="replace").lower())
    return "\n".join(chunks)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True)
    parser.add_argument("--status", required=True)
    parser.add_argument("--expected-steps", type=int, required=True)
    parser.add_argument("--csv", required=True)
    parser.add_argument("--markdown", required=True)
    args = parser.parse_args()

    root = Path(args.root)
    with open(args.status, newline="") as stream:
        launches = {row["mode"]: row for row in csv.DictReader(stream)}

    rows = []
    for mode in MODES:
        launch = launches.get(mode, {})
        run = root / mode
        summary = read_last_csv(run / "output" / "summary_runtime.csv")
        params = read_kv(run / "params" / "injection_type1_into_type2.kv")
        env = read_kv(run / "logs" / "environment_0434.env")
        text = marker_text(Path(launch.get("log", "")), run)
        markers = sorted({marker for marker in BAD_MARKERS if marker in text})
        exit_code = int(launch.get("exit_code", 999))

        q6_mode = has_q6(mode)
        species_q6_enable = truthy(params.get("speciesQ6Enable", "false"))
        q6_applied = truthy(summary.get("q6Applied", "0"))
        resident_flag = env.get("MPCD_CUDA_Q6_RESIDENT_0400", "0") == "1"
        numeric_keys = ["kBTEstimate", "maxParticleSpeed", "totalMass"]
        finite_summary = bool(summary) and all(finite(summary.get(key)) for key in numeric_keys)
        step_ok = summary.get("step", "") != "" and int(float(summary["step"])) >= args.expected_steps
        residual_value = summary.get("q6SpeciesQ6BarycentricResidualMaxAbs", "")
        tol_value = params.get("speciesQ6ComparisonTolerance", "")
        residual_ok = (not q6_mode) or (
            finite(residual_value)
            and finite(tol_value)
            and float(residual_value) <= float(tol_value)
        )
        q6_contract_ok = (
            (q6_mode and q6_applied and resident_flag and species_q6_enable)
            or ((not q6_mode) and (not q6_applied) and (not species_q6_enable))
        )
        passed = (
            exit_code == 0
            and finite_summary
            and step_ok
            and not markers
            and q6_contract_ok
            and residual_ok
        )
        rows.append({
            "mode": mode,
            "pass": int(passed),
            "exit_code": exit_code,
            "step": summary.get("step", ""),
            "q6Applied": int(q6_applied),
            "q6ResidentFlag": int(resident_flag),
            "speciesQ6Enable": int(species_q6_enable),
            "speciesQ6Mode": params.get("speciesQ6Mode", ""),
            "speciesQ6Sensitivity": params.get("speciesQ6Sensitivity", ""),
            "speciesQ6FallbackMode": params.get("speciesQ6FallbackMode", ""),
            "speciesQ6ResidualMaxAbs": residual_value,
            "speciesQ6Tolerance": tol_value,
            "kBTEstimate": summary.get("kBTEstimate", ""),
            "maxParticleSpeed": summary.get("maxParticleSpeed", ""),
            "totalMass": summary.get("totalMass", ""),
            "inletParticlesInserted": summary.get("inletParticlesInserted", ""),
            "badMarkers": ";".join(markers),
            "summaryPath": str(run / "output" / "summary_runtime.csv"),
        })

    Path(args.csv).parent.mkdir(parents=True, exist_ok=True)
    fields = list(rows[0])
    with open(args.csv, "w", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)

    passed_count = sum(row["pass"] for row in rows)
    lines = [
        "# 0491d species-Q6 path matrix",
        "",
        f"Pass: **{passed_count}/{len(rows)}**",
        "",
        "| Mode | Result | Step | Q6 applied | speciesQ6 | Residual | Tol | Markers |",
        "| --- | --- | ---: | ---: | ---: | ---: | ---: | --- |",
    ]
    for row in rows:
        lines.append(
            f"| {row['mode']} | {'PASS' if row['pass'] else 'FAIL'} | "
            f"{row['step']} | {row['q6Applied']} | {row['speciesQ6Enable']} | "
            f"{row['speciesQ6ResidualMaxAbs']} | {row['speciesQ6Tolerance']} | "
            f"{row['badMarkers']} |"
        )
    Path(args.markdown).write_text("\n".join(lines) + "\n")
    print(f"[0491d-summary] pass={passed_count}/{len(rows)}")
    return 0 if passed_count == len(rows) else 1


if __name__ == "__main__":
    raise SystemExit(main())
