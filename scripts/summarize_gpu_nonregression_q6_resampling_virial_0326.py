#!/usr/bin/env python3
"""Summarize 0326 Q6/resampling/virial non-regression smoke results."""
from __future__ import annotations

import csv
import math
import os
import sys
from pathlib import Path


def read_csv_rows(path: Path) -> list[dict[str, str]]:
    if not path.exists() or path.stat().st_size == 0:
        return []
    with path.open(newline="", encoding="utf-8", errors="replace") as f:
        return list(csv.DictReader(f))


def f(row: dict[str, str], key: str, default: float = math.nan) -> float:
    try:
        v = row.get(key, "")
        if v is None or v == "":
            return default
        return float(v)
    except Exception:
        return default


def i(row: dict[str, str], key: str, default: int = 0) -> int:
    try:
        v = row.get(key, "")
        if v is None or v == "":
            return default
        return int(round(float(v)))
    except Exception:
        return default


def parse_time_file(path: Path) -> dict[str, str]:
    out: dict[str, str] = {}
    if not path.exists():
        return out
    for raw in path.read_text(encoding="utf-8", errors="replace").splitlines():
        if "," in raw:
            k, v = raw.split(",", 1)
            out[k.strip()] = v.strip()
        elif raw.startswith("elapsed="):
            for token in raw.split():
                if "=" in token:
                    k, v = token.split("=", 1)
                    out[k.strip()] = v.strip()
    return out


def verdict_from_row(exit_code: int, row: dict[str, str]) -> tuple[str, str]:
    reasons: list[str] = []
    if exit_code != 0:
        reasons.append(f"exitCode={exit_code}")

    q6_applied = i(row, "q6Applied")
    resamp = i(row, "resampComputed")
    capacity = i(row, "capacityResponseEnabled")
    cap_kick = i(row, "capacityVirialKickApplied")
    q6_conv = i(row, "q6Converged", 1)
    q6_div = f(row, "q6DivAfterProjectedFluxRms")

    if q6_applied and not q6_conv:
        reasons.append("q6AppliedButNotConverged")
    if q6_applied and math.isfinite(q6_div) and q6_div > 1e-6:
        reasons.append(f"q6DivAfterProjectedFluxRms={q6_div:g}")

    # Guard only hard contradictions.  Some cases intentionally disable Q6 or resampling.
    if capacity and not cap_kick:
        reasons.append("capacityEnabledButNoVirialKick")

    if not reasons:
        return "PASS", ""
    return "FAIL", ";".join(reasons)


def main() -> int:
    manifest_path = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("dev_history/artifacts/gpu_nonregression_q6_resampling_virial_0326/gpu_nonregression_q6_resampling_virial_0326_manifest.csv")
    art_dir = Path(sys.argv[2]) if len(sys.argv) > 2 else manifest_path.parent
    rows = read_csv_rows(manifest_path)
    summary_rows: list[dict[str, object]] = []
    for m in rows:
        target = m.get("target", "")
        run_root = Path(m.get("runRoot", ""))
        exit_code = i(m, "exitCode")
        time_data = parse_time_file(Path(m.get("timeFile", "")))
        val_summary = run_root / "validation_summary_0162.csv"
        val_rows = read_csv_rows(val_summary)
        if not val_rows:
            summary_rows.append({
                "target": target,
                "case": "",
                "exitCode": exit_code,
                "verdict": "FAIL" if exit_code else "UNKNOWN",
                "reason": "missing validation_summary_0162.csv",
                "elapsed_s": time_data.get("elapsed_seconds", ""),
                "wallTime": "",
                "q6Applied": "",
                "q6Converged": "",
                "q6Iterations": "",
                "q6DivAfterProjectedFluxRms": "",
                "resampComputed": "",
                "resampPopulationGuardApplied": "",
                "resampPopulationGuardCellsSplit": "",
                "resampExtractionApplyRoleChanges": "",
                "resampInsertionApplyRoleChanges": "",
                "capacityResponseEnabled": "",
                "capacityVirialKickApplied": "",
                "capacityOverfillRatio": "",
                "capacityVirialKEffective": "",
                "runRoot": str(run_root),
            })
            continue
        for vr in val_rows:
            verdict, reason = verdict_from_row(exit_code, vr)
            summary_rows.append({
                "target": target,
                "case": vr.get("case", ""),
                "exitCode": exit_code,
                "verdict": verdict,
                "reason": reason,
                "elapsed_s": time_data.get("elapsed_seconds", vr.get("elapsed_s", "")),
                "wallTime": vr.get("wallTime", ""),
                "q6Applied": vr.get("q6Applied", ""),
                "q6Converged": vr.get("q6Converged", ""),
                "q6Iterations": vr.get("q6Iterations", ""),
                "q6DivAfterProjectedFluxRms": vr.get("q6DivAfterProjectedFluxRms", ""),
                "resampComputed": vr.get("resampComputed", ""),
                "resampPopulationGuardApplied": vr.get("resampPopulationGuardApplied", ""),
                "resampPopulationGuardCellsSplit": vr.get("resampPopulationGuardCellsSplit", ""),
                "resampExtractionApplyRoleChanges": vr.get("resampExtractionApplyRoleChanges", ""),
                "resampInsertionApplyRoleChanges": vr.get("resampInsertionApplyRoleChanges", ""),
                "capacityResponseEnabled": vr.get("capacityResponseEnabled", ""),
                "capacityVirialKickApplied": vr.get("capacityVirialKickApplied", ""),
                "capacityOverfillRatio": vr.get("capacityOverfillRatio", ""),
                "capacityVirialKEffective": vr.get("capacityVirialKEffective", ""),
                "runRoot": str(run_root),
            })

    out_path = art_dir / "gpu_nonregression_q6_resampling_virial_0326_summary.csv"
    fieldnames = [
        "target", "case", "exitCode", "verdict", "reason", "elapsed_s", "wallTime",
        "q6Applied", "q6Converged", "q6Iterations", "q6DivAfterProjectedFluxRms",
        "resampComputed", "resampPopulationGuardApplied", "resampPopulationGuardCellsSplit",
        "resampExtractionApplyRoleChanges", "resampInsertionApplyRoleChanges",
        "capacityResponseEnabled", "capacityVirialKickApplied", "capacityOverfillRatio",
        "capacityVirialKEffective", "runRoot",
    ]
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with out_path.open("w", newline="", encoding="utf-8") as fcsv:
        writer = csv.DictWriter(fcsv, fieldnames=fieldnames)
        writer.writeheader()
        for r in summary_rows:
            writer.writerow(r)

    fail_count = sum(1 for r in summary_rows if r.get("verdict") != "PASS")
    print(f"[0326-summary] wrote {out_path}")
    print(f"[0326-summary] rows={len(summary_rows)} fail_or_unknown={fail_count}")
    return 0 if fail_count == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
