#!/usr/bin/env python3
import argparse
import csv
import math
from pathlib import Path

CASES = ["tg", "poiseuille", "step", "io_box_same_face",
         "injection_type1_into_type2", "bend_pipe", "naca", "vk"]
MODES = ["src", "src-resampling", "src-q6", "src-q6-resampling"]
BAD_MARKERS = ("fatal error", "stale", "unsupported", "cpu fallback",
               "non-finite", "nonfinite")


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


def env_map(path):
    out = {}
    if path.is_file():
        for line in path.read_text(errors="replace").splitlines():
            if "=" in line:
                key, value = line.split("=", 1)
                out[key] = value
    return out


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True)
    parser.add_argument("--status", required=True)
    parser.add_argument("--csv", required=True)
    parser.add_argument("--markdown", required=True)
    args = parser.parse_args()
    root = Path(args.root)
    with open(args.status, newline="") as stream:
        launches = {(r["case"], r["mode"]): r for r in csv.DictReader(stream)}

    rows = []
    for case in CASES:
        for mode in MODES:
            launch = launches.get((case, mode), {})
            run = root / case / mode
            summary = read_last_csv(run / "output" / "summary_runtime.csv")
            env = env_map(run / "logs" / "environment_0434.env")
            text = ""
            for candidate in [Path(launch.get("log", "")), *sorted((run / "logs").glob("*.log"))]:
                if candidate.is_file():
                    text += candidate.read_text(errors="replace").lower() + "\n"
            markers = sorted({m for m in BAD_MARKERS if m in text})
            numeric_keys = ["kBTEstimate", "maxParticleSpeed", "totalMass"]
            finite_summary = bool(summary) and all(finite(summary.get(k)) for k in numeric_keys)
            resampling = "resampling" in mode
            q6 = "q6" in mode
            resampling_flags = (not resampling) or all(env.get(k) == "1" for k in (
                "MPCD_CUDA_RESAMPLING_MASS_RECONDITION_0296",
                "MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297",
                "MPCD_CUDA_RESAMPLING_EMPTY_REFILL_0319"))
            q6_flag = (not q6) or env.get("MPCD_CUDA_Q6_RESIDENT_0400") == "1"
            exit_code = int(launch.get("exit_code", 999))
            passed = exit_code == 0 and finite_summary and not markers and resampling_flags and q6_flag
            rows.append({
                "case": case, "mode": mode, "pass": int(passed), "exit_code": exit_code,
                "step": summary.get("step", ""), "fluidParticles": summary.get("nFluidParticles", ""),
                "kBTEstimate": summary.get("kBTEstimate", ""),
                "maxParticleSpeed": summary.get("maxParticleSpeed", ""),
                "q6ResidualRel": summary.get("q6ResidualRel", ""),
                "resampMRelMaxAbs": summary.get("resampMRelMaxAbs", ""),
                "inletParticlesInserted": summary.get("inletParticlesInserted", ""),
                "inletKBT": summary.get("inletKBT", ""),
                "resamplingFlags": int(resampling_flags), "q6ResidentFlag": int(q6_flag),
                "badMarkers": ";".join(markers),
            })

    fields = list(rows[0])
    Path(args.csv).parent.mkdir(parents=True, exist_ok=True)
    with open(args.csv, "w", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)

    passed = sum(int(r["pass"]) for r in rows)
    lines = ["# 0435e algorithmic matrix", "", f"Pass: **{passed}/{len(rows)}**", "",
             "| Case | Mode | Result | Step | Fluid | kBT | Q6 residual | Markers |",
             "| --- | --- | --- | ---: | ---: | ---: | ---: | --- |"]
    for row in rows:
        lines.append(f"| {row['case']} | {row['mode']} | {'PASS' if row['pass'] else 'FAIL'} | "
                     f"{row['step']} | {row['fluidParticles']} | {row['kBTEstimate']} | "
                     f"{row['q6ResidualRel']} | {row['badMarkers']} |")
    Path(args.markdown).write_text("\n".join(lines) + "\n")
    print(f"[0435e-summary] pass={passed}/{len(rows)}")


if __name__ == "__main__":
    main()
