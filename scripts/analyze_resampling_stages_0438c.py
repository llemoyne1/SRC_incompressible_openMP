#!/usr/bin/env python3
"""
0438c helper: inspect which resampling sub-stages are actually active in
periodic wall-free equivalence runs.

Usage:
  python3 scripts/analyze_resampling_stages_0438c.py \
    --root runs/0438_shear_periodic_equiv_g40_s2000

Outputs:
  <root>/resampling_stage_audit_0438c.csv
  <root>/resampling_stage_audit_0438c.md
"""
from __future__ import annotations

import argparse
import csv
import math
import os
from pathlib import Path
from typing import Dict, List, Optional, Tuple

MODES_DEFAULT = ["src", "src-resampling", "src-q6", "src-q6-resampling"]

STAGE_COLS = {
    "computed": "resampComputed",
    "candidateLists": "resampCandidateListsBuilt",
    "transferPlan": "resampTransferPlanBuilt",
    "transferPairs": "resampTransferPairs",
    "donorSelection": "resampDonorParticleSelectionBuilt",
    "extractionPlan": "resampExtractionPlanBuilt",
    "extractionApply": "resampExtractionApplyApplied",
    "insertionPlan": "resampInsertionPlanBuilt",
    "insertionApply": "resampInsertionApplyApplied",
    "remap": "resampRemapApplied",
    "thermalRenorm": "resampThermalRenormApplied",
    "massGuard": "resampMassGuardApplied",
    "populationGuard": "resampPopulationGuardApplied",
    "latentActivation": "resampLatentActivationApplied",
    "poolBuilt": "resampPoolBuilt",
}

VALUE_COLS = [
    "step", "nFluidParticles", "totalMass", "meanN", "stdN",
    "resampNFluid", "resampNLatent", "resampNInactive",
    "resampPoorCells", "resampRichCells", "resampTransferPairs",
    "resampMRelMaxAbs",
    "resampRemapApplied", "resampRemapCellsRemapped", "resampRemapParticlesRemapped",
    "resampThermalRenormApplied", "resampThermalRenormCellsRenormalized", "resampThermalRenormParticlesRenormalized",
    "resampMassGuardApplied", "resampMassGuardParticlesAdjusted",
    "resampMassGuardParticlesBelowMinBefore", "resampMassGuardParticlesAboveMaxBefore",
    "resampMassGuardParticlesBelowMinAfter", "resampMassGuardParticlesAboveMaxAfter",
    "resampMassGuardParticleMassMinBefore", "resampMassGuardParticleMassMaxBefore",
    "resampMassGuardParticleMassMinAfter", "resampMassGuardParticleMassMaxAfter",
    "resampPopulationGuardApplied", "resampPopulationGuardActiveParticleDelta",
    "resampPopulationGuardCellsSplit", "resampPopulationGuardCellsExtracted",
    "resampPopulationGuardSplitParticlesCreated", "resampPopulationGuardExtractedParticles",
    "resampLatentActivationApplied", "resampLatentActivationParticlesActivated",
    "resampLatentActivationFluidSlotsBefore", "resampLatentActivationFluidSlotsAfter",
    "resampPoolFreeSlots", "resampPoolLatentSlots", "resampPoolFluidSlots",
]


def read_rows(path: Path) -> List[Dict[str, str]]:
    with path.open(newline="") as f:
        return list(csv.DictReader(f))


def as_float(row: Dict[str, str], col: str) -> Optional[float]:
    s = row.get(col, "")
    if s is None or s == "":
        return None
    try:
        return float(s)
    except ValueError:
        return None


def truthy_value(row: Dict[str, str], col: str) -> bool:
    v = as_float(row, col)
    return v is not None and abs(v) > 0.0


def first_last(rows: List[Dict[str, str]], col: str) -> Tuple[Optional[float], Optional[float], Optional[float]]:
    vals = [as_float(r, col) for r in rows]
    vals = [v for v in vals if v is not None]
    if not vals:
        return None, None, None
    return vals[0], vals[-1], vals[-1] - vals[0]


def summarize_mode(root: Path, mode: str) -> Dict[str, object]:
    path = root / mode / "output" / "summary_runtime.csv"
    out: Dict[str, object] = {"mode": mode, "path": str(path), "found": path.is_file()}
    if not path.is_file():
        return out
    rows = read_rows(path)
    out["rows"] = len(rows)
    if not rows:
        return out
    out["firstStep"] = rows[0].get("step", "")
    out["lastStep"] = rows[-1].get("step", "")
    for col in ["nFluidParticles", "totalMass", "meanN", "stdN", "meanKinetic", "kBTEstimate"]:
        first, last, delta = first_last(rows, col)
        out[col + "First"] = first
        out[col + "Last"] = last
        out[col + "Delta"] = delta
    for label, col in STAGE_COLS.items():
        active_rows = [r for r in rows if truthy_value(r, col)]
        out[label + "Rows"] = len(active_rows)
        out[label + "FirstStep"] = active_rows[0].get("step", "") if active_rows else ""
        out[label + "LastStep"] = active_rows[-1].get("step", "") if active_rows else ""
    # compact event rows: any non-trivial resampling sub-stage beyond computed/pool
    event_cols = [c for k, c in STAGE_COLS.items() if k not in {"computed", "poolBuilt"}]
    event_rows = [r for r in rows if any(truthy_value(r, c) for c in event_cols)]
    out["nonTrivialEventRows"] = len(event_rows)
    out["nonTrivialFirstStep"] = event_rows[0].get("step", "") if event_rows else ""
    out["nonTrivialLastStep"] = event_rows[-1].get("step", "") if event_rows else ""
    return out


def write_csv(path: Path, rows: List[Dict[str, object]]) -> None:
    keys: List[str] = []
    for r in rows:
        for k in r.keys():
            if k not in keys:
                keys.append(k)
    with path.open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=keys)
        w.writeheader()
        for r in rows:
            w.writerow(r)


def fmt(v: object) -> str:
    if v is None:
        return ""
    if isinstance(v, float):
        if not math.isfinite(v):
            return str(v)
        return f"{v:.17g}"
    return str(v)


def write_md(path: Path, root: Path, summaries: List[Dict[str, object]], modes: List[str]) -> None:
    lines: List[str] = []
    lines.append("# 0438c resampling stage audit")
    lines.append("")
    lines.append(f"Root: `{root}`")
    lines.append("")
    lines.append("This audit distinguishes resampling being computed from sub-stages that actually mutate or recondition the state.")
    lines.append("")
    header = ["Mode", "rows", "ΔnFluid", "Δmass", "computedRows", "nonTrivialRows", "remapRows", "thermalRows", "massGuardRows", "popGuardRows", "latentRows", "transferPairRows"]
    lines.append("| " + " | ".join(header) + " |")
    lines.append("| " + " | ".join(["---"] + ["---:"] * (len(header) - 1)) + " |")
    for s in summaries:
        row = [
            s.get("mode", ""),
            s.get("rows", ""),
            s.get("nFluidParticlesDelta", ""),
            s.get("totalMassDelta", ""),
            s.get("computedRows", ""),
            s.get("nonTrivialEventRows", ""),
            s.get("remapRows", ""),
            s.get("thermalRenormRows", ""),
            s.get("massGuardRows", ""),
            s.get("populationGuardRows", ""),
            s.get("latentActivationRows", ""),
            s.get("transferPairsRows", ""),
        ]
        lines.append("| " + " | ".join(fmt(x) for x in row) + " |")
    lines.append("")
    lines.append("## Diagnostic commands")
    lines.append("")
    lines.append("To inspect detailed event rows for a mode:")
    lines.append("")
    lines.append("```bash")
    lines.append("python3 scripts/analyze_resampling_stages_0438c.py --root " + str(root))
    lines.append("cat " + str(root / "resampling_stage_audit_0438c.csv"))
    lines.append("```")
    lines.append("")
    path.write_text("\n".join(lines) + "\n")


def dump_event_rows(root: Path, mode: str, max_rows: int) -> None:
    path = root / mode / "output" / "summary_runtime.csv"
    if not path.is_file():
        return
    rows = read_rows(path)
    event_cols = [c for k, c in STAGE_COLS.items() if k not in {"computed", "poolBuilt"}]
    event_rows = [r for r in rows if any(truthy_value(r, c) for c in event_cols)]
    print(f"\n== {mode}: non-trivial resampling stage rows {len(event_rows)} ==")
    for r in event_rows[:max_rows]:
        parts = []
        for c in VALUE_COLS:
            if c in r:
                parts.append(f"{c}={r.get(c, '')}")
        print(", ".join(parts))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", required=True, help="Run root containing mode subdirectories")
    ap.add_argument("--modes", default=" ".join(MODES_DEFAULT), help="Whitespace-separated mode list")
    ap.add_argument("--max-event-rows", type=int, default=30)
    args = ap.parse_args()

    root = Path(args.root)
    modes = args.modes.split()
    summaries = [summarize_mode(root, m) for m in modes]
    csv_path = root / "resampling_stage_audit_0438c.csv"
    md_path = root / "resampling_stage_audit_0438c.md"
    write_csv(csv_path, summaries)
    write_md(md_path, root, summaries, modes)
    print(md_path)
    print(csv_path)
    for m in modes:
        dump_event_rows(root, m, args.max_event_rows)
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
