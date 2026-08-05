#!/usr/bin/env python3
"""Compare the 0493x4a separate kick with the 0493x4b fused CUDA path."""
from __future__ import annotations

import argparse
import csv
import math
from pathlib import Path

from analyze_0493x4a_q6_force_single_tg import (
    compare_pair,
    elapsed_seconds,
    fmt,
    maximum,
)


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
        "null_fused_vs_separate": compare_pair(
            args.root,
            "null_fused_vs_separate",
            "null_single",
            "null_fused",
            args.Lx,
            args.Ly,
        ),
        "forced_fused_vs_separate": compare_pair(
            args.root,
            "forced_fused_vs_separate",
            "forced_single",
            "forced_fused",
            args.Lx,
            args.Ly,
        ),
    }
    rows = [row for group in comparisons.values() for row in group]
    args.csv.parent.mkdir(parents=True, exist_ok=True)
    with args.csv.open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)

    null_rows = comparisons["null_fused_vs_separate"]
    forced_rows = comparisons["forced_fused_vs_separate"]
    null_max = max(
        maximum(null_rows, key)
        for key in (
            "positionRmsDifference",
            "positionMaxDifference",
            "velocityRmsDifference",
            "velocityMaxDifference",
        )
    )
    null_pass = math.isfinite(null_max) and null_max <= args.null_tolerance
    max_amp = maximum(forced_rows, "ampRelativeDifference")
    max_pos_rms = maximum(forced_rows, "positionRmsDifference")
    max_pos = maximum(forced_rows, "positionMaxDifference")
    max_vel_rms = maximum(forced_rows, "velocityRmsDifference")
    max_vel = maximum(forced_rows, "velocityMaxDifference")

    separate_time = elapsed_seconds(args.root, "forced_single")
    fused_time = elapsed_seconds(args.root, "forced_fused")
    fused_over_separate = (
        fused_time / separate_time if separate_time > 0.0 else float("nan")
    )
    final = forced_rows[-1]

    report = [
        "# 0493x4b Q6-g CUDA force fusion qualification",
        "",
        f"- Null-force numerical neutrality: **{'PASS' if null_pass else 'FAIL'}**",
        f"- Null-force maximum particle difference: `{fmt(null_max)}`",
        f"- Null-force tolerance: `{args.null_tolerance:.6e}`",
        f"- Maximum forced modal difference, fused vs separate: `{fmt(max_amp)}`",
        f"- Maximum forced position RMS: `{fmt(max_pos_rms)}`",
        f"- Maximum forced position difference: `{fmt(max_pos)}`",
        f"- Maximum forced velocity RMS: `{fmt(max_vel_rms)}`",
        f"- Maximum forced velocity difference: `{fmt(max_vel)}`",
        f"- Final separate amplitude: `{float(final['ampReference']):.17g}`",
        f"- Final fused amplitude: `{float(final['ampCandidate']):.17g}`",
        "",
        "## Timing",
        "",
        f"- separate-kick one-solve elapsed: `{fmt(separate_time)}` s",
        f"- fused one-solve elapsed: `{fmt(fused_time)}` s",
        f"- fused / separate: `{fmt(fused_over_separate)}`",
        "",
        "The forced comparison is descriptive. Only null-force neutrality is a hard acceptance criterion in this first fusion test.",
    ]
    args.report.write_text("\n".join(report) + "\n", encoding="utf-8")
    print(
        f"[0493x4b-analysis] nullPass={int(null_pass)} nullMax={null_max:.6e} "
        f"forcedFusedVsSeparateMaxAmpRel={max_amp:.6e} "
        f"forcedMaxPosRms={max_pos_rms:.6e} "
        f"forcedMaxVelRms={max_vel_rms:.6e} "
        f"timeFusedOverSeparate={fused_over_separate:.6f}"
    )
    return 0 if null_pass else 2


if __name__ == "__main__":
    raise SystemExit(main())
