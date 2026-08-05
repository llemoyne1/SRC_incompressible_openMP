#!/usr/bin/env python3
"""Compare legacy, two-solve prestream and one-solve prestream_single TG dumps."""
from __future__ import annotations

import argparse
import csv
import math
import re
from pathlib import Path

from analyze_periodic_modes_0438 import FLUID_ROLE, modal_amplitude, read_smpcd


def step_map(case_root: Path) -> dict[int, Path]:
    result: dict[int, Path] = {}
    for path in (case_root / "output").glob("state_step_*.smpcd"):
        match = re.search(r"state_step_(\d+)\.smpcd$", path.name)
        if match:
            result[int(match.group(1))] = path
    return result


def periodic_delta(a: float, b: float, length: float) -> float:
    d = a - b
    return d - length * round(d / length)


def state_difference(
    a: dict[str, object], b: dict[str, object], lx: float, ly: float
) -> tuple[float, float, float, float]:
    if int(a["n"]) != int(b["n"]):
        raise RuntimeError("particle counts differ")
    n = int(a["n"])
    pos2 = vel2 = 0.0
    max_pos = max_vel = 0.0
    count = 0
    for i in range(n):
        if a["role"][i] != FLUID_ROLE or b["role"][i] != FLUID_ROLE:  # type: ignore[index]
            continue
        dx = periodic_delta(a["x"][i], b["x"][i], lx)  # type: ignore[index]
        dy = periodic_delta(a["y"][i], b["y"][i], ly)  # type: ignore[index]
        dvx = a["vx"][i] - b["vx"][i]  # type: ignore[index]
        dvy = a["vy"][i] - b["vy"][i]  # type: ignore[index]
        dp = math.hypot(dx, dy)
        dv = math.hypot(dvx, dvy)
        pos2 += dp * dp
        vel2 += dv * dv
        max_pos = max(max_pos, dp)
        max_vel = max(max_vel, dv)
        count += 1
    denom = max(1, count)
    return math.sqrt(pos2 / denom), max_pos, math.sqrt(vel2 / denom), max_vel


def compare_pair(
    root: Path,
    pair: str,
    reference_name: str,
    candidate_name: str,
    lx: float,
    ly: float,
) -> list[dict[str, object]]:
    reference = step_map(root / reference_name)
    candidate = step_map(root / candidate_name)
    steps = sorted(set(reference) & set(candidate))
    if not steps:
        raise RuntimeError(f"{pair}: no common dumps")
    rows: list[dict[str, object]] = []
    for step in steps:
        state_reference = read_smpcd(reference[step])
        state_candidate = read_smpcd(candidate[step])
        mode_reference = modal_amplitude(state_reference, "tg", lx, ly)
        mode_candidate = modal_amplitude(state_candidate, "tg", lx, ly)
        pos_rms, pos_max, vel_rms, vel_max = state_difference(
            state_reference, state_candidate, lx, ly
        )
        amp_reference = float(mode_reference["amp"])
        amp_candidate = float(mode_candidate["amp"])
        amp_rel = (
            (amp_candidate - amp_reference) / max(abs(amp_reference), 1.0e-300)
            if math.isfinite(amp_reference) and math.isfinite(amp_candidate)
            else float("nan")
        )
        rows.append(
            {
                "pair": pair,
                "reference": reference_name,
                "candidate": candidate_name,
                "step": step,
                "ampReference": amp_reference,
                "ampCandidate": amp_candidate,
                "ampRelativeDifference": amp_rel,
                "positionRmsDifference": pos_rms,
                "positionMaxDifference": pos_max,
                "velocityRmsDifference": vel_rms,
                "velocityMaxDifference": vel_max,
            }
        )
    return rows


def elapsed_seconds(root: Path, case_name: str) -> float:
    paths = list((root / case_name / "logs").glob("*.time"))
    if len(paths) != 1:
        return float("nan")
    match = re.search(r"elapsed=([0-9.eE+-]+)", paths[0].read_text())
    return float(match.group(1)) if match else float("nan")


def maximum(rows: list[dict[str, object]], key: str) -> float:
    return max(abs(float(row[key])) for row in rows)


def fmt(value: float) -> str:
    return f"{value:.6e}" if math.isfinite(value) else "nan"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--Lx", type=float, required=True)
    parser.add_argument("--Ly", type=float, required=True)
    parser.add_argument("--null-tolerance", type=float, default=1.0e-12)
    parser.add_argument("--csv", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()

    comparisons = {
        "null_double_vs_legacy": compare_pair(
            args.root, "null_double_vs_legacy", "null_legacy", "null_prestream", args.Lx, args.Ly
        ),
        "null_single_vs_legacy": compare_pair(
            args.root, "null_single_vs_legacy", "null_legacy", "null_prestream_single", args.Lx, args.Ly
        ),
        "forced_single_vs_double": compare_pair(
            args.root, "forced_single_vs_double", "forced_prestream", "forced_prestream_single", args.Lx, args.Ly
        ),
        "forced_single_vs_legacy": compare_pair(
            args.root, "forced_single_vs_legacy", "forced_legacy", "forced_prestream_single", args.Lx, args.Ly
        ),
    }
    rows = [row for group in comparisons.values() for row in group]
    args.csv.parent.mkdir(parents=True, exist_ok=True)
    with args.csv.open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)

    null_max = max(
        maximum(comparisons[name], key)
        for name in ("null_double_vs_legacy", "null_single_vs_legacy")
        for key in (
            "positionRmsDifference",
            "positionMaxDifference",
            "velocityRmsDifference",
            "velocityMaxDifference",
        )
    )
    null_pass = math.isfinite(null_max) and null_max <= args.null_tolerance
    forced_sd = comparisons["forced_single_vs_double"]
    forced_sl = comparisons["forced_single_vs_legacy"]
    max_amp_sd = maximum(forced_sd, "ampRelativeDifference")
    max_amp_sl = maximum(forced_sl, "ampRelativeDifference")
    max_pos_sd = maximum(forced_sd, "positionRmsDifference")
    max_vel_sd = maximum(forced_sd, "velocityRmsDifference")

    times = {
        name: elapsed_seconds(args.root, name)
        for name in (
            "forced_legacy",
            "forced_prestream",
            "forced_prestream_single",
        )
    }
    single_over_legacy = (
        times["forced_prestream_single"] / times["forced_legacy"]
        if times["forced_legacy"] > 0.0 else float("nan")
    )
    single_over_double = (
        times["forced_prestream_single"] / times["forced_prestream"]
        if times["forced_prestream"] > 0.0 else float("nan")
    )

    final_sd = forced_sd[-1]
    report = [
        "# 0493x4a Q6 force projection: one-solve non-regression",
        "",
        f"- Null-force numerical neutrality: **{'PASS' if null_pass else 'FAIL'}**",
        f"- Null-force maximum particle difference: `{fmt(null_max)}`",
        f"- Null-force tolerance: `{args.null_tolerance:.6e}`",
        f"- Maximum forced modal difference, single vs double: `{fmt(max_amp_sd)}`",
        f"- Maximum forced modal difference, single vs legacy: `{fmt(max_amp_sl)}`",
        f"- Maximum forced position RMS, single vs double: `{fmt(max_pos_sd)}`",
        f"- Maximum forced velocity RMS, single vs double: `{fmt(max_vel_sd)}`",
        f"- Final forced double amplitude: `{float(final_sd['ampReference']):.17g}`",
        f"- Final forced single amplitude: `{float(final_sd['ampCandidate']):.17g}`",
        "",
        "## Timing",
        "",
        f"- forced legacy elapsed: `{fmt(times['forced_legacy'])}` s",
        f"- forced two-solve prestream elapsed: `{fmt(times['forced_prestream'])}` s",
        f"- forced one-solve prestream elapsed: `{fmt(times['forced_prestream_single'])}` s",
        f"- one-solve / legacy: `{fmt(single_over_legacy)}`",
        f"- one-solve / two-solve: `{fmt(single_over_double)}`",
        "",
        "Forced comparisons are descriptive: this first qualification does not impose a physical acceptance threshold.",
    ]
    args.report.write_text("\n".join(report) + "\n", encoding="utf-8")
    print(
        f"[0493x4a-analysis] nullPass={int(null_pass)} nullMax={null_max:.6e} "
        f"forcedSingleVsDoubleMaxAmpRel={max_amp_sd:.6e} "
        f"forcedSingleVsLegacyMaxAmpRel={max_amp_sl:.6e} "
        f"timeSingleOverLegacy={single_over_legacy:.6f} "
        f"timeSingleOverDouble={single_over_double:.6f}"
    )
    return 0 if null_pass else 2


if __name__ == "__main__":
    raise SystemExit(main())
