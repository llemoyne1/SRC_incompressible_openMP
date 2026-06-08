#!/usr/bin/env python3
"""Print a compact Markdown summary for the 0302 nominal backward-step run.

The script uses only the Python standard library.  It expects the output folder
created by scripts/run_cuda_resampling_backward_step_nominal_0302.sh or the 0301
long runner.
"""
from __future__ import annotations

import csv
import sys
from pathlib import Path


def read_csv(path: Path):
    if not path.exists():
        return []
    with path.open(newline="") as fh:
        return list(csv.DictReader(fh))


def as_float(value, default=0.0):
    try:
        return float(value)
    except Exception:
        return default


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print("usage: summarize_cuda_resampling_backward_step_0302.py <artifact_dir>", file=sys.stderr)
        return 2

    art = Path(argv[1])
    per = read_csv(art / "cuda_resampling_backward_step_long_0301_per_run.csv")
    vs = read_csv(art / "cuda_resampling_backward_step_long_0301_vs_classic.csv")
    out = art / "cuda_resampling_backward_step_nominal_0302_summary.md"

    if not per:
        print(f"[0302-summary] missing per-run csv under {art}", file=sys.stderr)
        return 1

    lines = []
    lines.append("# 0302 nominal backward-step summary")
    lines.append("")
    lines.append("| case | mode | exit | empty | poor | stdNActive | maxNWet | split | merge | mass | Px | kBT |")
    lines.append("| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |")
    for r in per:
        lines.append(
            "| {case} | {mode} | {exit} | {empty} | {poor} | {std:.6g} | {maxn} | {split:.0f} | {merge:.0f} | {mass:.6g} | {px:.6g} | {kbt:.6g} |".format(
                case=r.get("caseName", ""),
                mode=r.get("modeName", ""),
                exit=r.get("exitCode", ""),
                empty=r.get("survey_final_emptyCells", ""),
                poor=r.get("survey_final_poorCells", ""),
                std=as_float(r.get("survey_final_stdNActive")),
                maxn=r.get("survey_final_maxNWet", ""),
                split=as_float(r.get("guard_sum_splitApplied")),
                merge=as_float(r.get("guard_sum_mergeApplied")),
                mass=as_float(r.get("final_totalMass")),
                px=as_float(r.get("final_Px")),
                kbt=as_float(r.get("final_kBTEstimate")),
            )
        )

    if vs:
        lines.append("")
        lines.append("## Delta versus classic")
        lines.append("")
        lines.append("| case | mode | delta empty | delta poor | delta stdNActive | delta mass | delta Px | delta kBT | max mass err | max momentum err | max Krel err |")
        lines.append("| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |")
        for r in vs:
            if r.get("modeName") == "classic":
                continue
            lines.append(
                "| {case} | {mode} | {de:.0f} | {dp:.0f} | {ds:.6g} | {dm:.6g} | {dpx:.6g} | {dkbt:.6g} | {me:.3g} | {pe:.3g} | {ke:.3g} |".format(
                    case=r.get("caseName", ""),
                    mode=r.get("modeName", ""),
                    de=as_float(r.get("delta_survey_final_emptyCells")),
                    dp=as_float(r.get("delta_survey_final_poorCells")),
                    ds=as_float(r.get("delta_survey_final_stdNActive")),
                    dm=as_float(r.get("delta_final_totalMass")),
                    dpx=as_float(r.get("delta_final_Px")),
                    dkbt=as_float(r.get("delta_final_kBTEstimate")),
                    me=as_float(r.get("guard_maxMassError")),
                    pe=as_float(r.get("guard_maxMomentumError")),
                    ke=as_float(r.get("guard_maxKrelError0298")),
                )
            )

    out.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"[0302-summary] wrote {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
