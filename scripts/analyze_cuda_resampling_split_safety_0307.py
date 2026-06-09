#!/usr/bin/env python3
"""Summarize 0307 split-cascade diagnostics.

The analyzer is intentionally dependency-free.  It reads the runner manifest,
extracts the per-call CUDA population-guard CSV, and aggregates the counters
added in 0307 together with the pre-existing 0297/0298/0299 budgets.
"""

from __future__ import annotations

import csv
import math
import sys
from pathlib import Path


def f(row: dict[str, str], key: str, default: float = 0.0) -> float:
    v = row.get(key, "")
    if v is None or v == "":
        return default
    try:
        return float(v)
    except Exception:
        return default


def i(row: dict[str, str], key: str) -> int:
    return int(round(f(row, key, 0.0)))


def read_csv(path: Path) -> list[dict[str, str]]:
    if not path.exists() or path.stat().st_size == 0:
        return []
    with path.open(newline="") as fh:
        return list(csv.DictReader(fh))


def min_positive(rows: list[dict[str, str]], key: str) -> float:
    vals = [f(r, key, 0.0) for r in rows]
    vals = [x for x in vals if x > 0.0 and math.isfinite(x)]
    return min(vals) if vals else 0.0


def max_abs(rows: list[dict[str, str]], key: str) -> float:
    vals = [abs(f(r, key, 0.0)) for r in rows]
    return max(vals) if vals else 0.0


def sum_int(rows: list[dict[str, str]], key: str) -> int:
    return sum(i(r, key) for r in rows)


def main() -> int:
    if len(sys.argv) < 3:
        print("usage: analyze_cuda_resampling_split_safety_0307.py RUN_MANIFEST ART_DIR", file=sys.stderr)
        return 2
    manifest = Path(sys.argv[1])
    art_dir = Path(sys.argv[2])
    out_per = art_dir / "cuda_resampling_split_safety_0307_per_run.csv"

    rows = read_csv(manifest)
    out_rows: list[dict[str, object]] = []
    for m in rows:
        root = Path(m.get("runRoot", ""))
        guard_path = root / "output" / "cuda_resampling_population_guard_0297.csv"
        guard = read_csv(guard_path)
        last = guard[-1] if guard else {}
        out_rows.append({
            "caseName": m.get("caseName", ""),
            "modeName": m.get("modeName", ""),
            "runRoot": str(root),
            "exitCode": m.get("exitCode", ""),
            "accepted": m.get("accepted", ""),
            "guardRows": len(guard),
            "splitSafety0307": i(last, "splitSafety0307") if last else 0,
            "preferMaxMassDonor0307": i(last, "preferMaxMassDonor0307") if last else 0,
            "splitDonorMinMass0307": f(last, "splitDonorMinMass0307"),
            "splitNewParticleMinMass0307": f(last, "splitNewParticleMinMass0307"),
            "solidAdjacentSplitMode0307": i(last, "solidAdjacentSplitMode0307") if last else 0,
            "solidAdjacentDonorMinMass0307": f(last, "solidAdjacentDonorMinMass0307"),
            "sumSplitApplied": sum_int(guard, "splitApplied"),
            "sumMergeApplied": sum_int(guard, "mergeApplied"),
            "sumPoorCells": sum_int(guard, "poorCells"),
            "sumRichCells": sum_int(guard, "richCells"),
            "sumSplitCandidatesSolidAdjacent0307": sum_int(guard, "splitCandidatesSolidAdjacent0307"),
            "sumSplitAppliedSolidAdjacent0307": sum_int(guard, "splitAppliedSolidAdjacent0307"),
            "sumSplitSkippedDonorMass0307": sum_int(guard, "splitSkippedDonorMass0307"),
            "sumSplitSkippedNewMass0307": sum_int(guard, "splitSkippedNewMass0307"),
            "sumSplitSkippedSolidAdjacent0307": sum_int(guard, "splitSkippedSolidAdjacent0307"),
            "sumSplitFromMassBelow0p5_0307": sum_int(guard, "splitFromMassBelow0p5_0307"),
            "sumSplitFromMassBelow0p25_0307": sum_int(guard, "splitFromMassBelow0p25_0307"),
            "sumSplitFromMassBelow0p1_0307": sum_int(guard, "splitFromMassBelow0p1_0307"),
            "minSplitDonorMass0307": min_positive(guard, "minSplitDonorMass0307"),
            "minSplitNewParticleMass0307": min_positive(guard, "minSplitNewParticleMass0307"),
            "minPostSplitDonorMass0307": min_positive(guard, "minPostSplitDonorMass0307"),
            "maxAbsCellMassError": max_abs(guard, "maxAbsCellMassError"),
            "maxAbsCellMomentumError": max_abs(guard, "maxAbsCellMomentumError"),
            "maxAbsCellKrelError0298": max_abs(guard, "maxAbsCellKrelError0298"),
            "lastFluidParticlesAfter": i(last, "fluidParticlesAfter") if last else 0,
            "lastInactiveParticlesAfter": i(last, "inactiveParticlesAfter") if last else 0,
        })

    fieldnames = [
        "caseName", "modeName", "runRoot", "exitCode", "accepted", "guardRows",
        "splitSafety0307", "preferMaxMassDonor0307", "splitDonorMinMass0307",
        "splitNewParticleMinMass0307", "solidAdjacentSplitMode0307", "solidAdjacentDonorMinMass0307",
        "sumSplitApplied", "sumMergeApplied", "sumPoorCells", "sumRichCells",
        "sumSplitCandidatesSolidAdjacent0307", "sumSplitAppliedSolidAdjacent0307",
        "sumSplitSkippedDonorMass0307", "sumSplitSkippedNewMass0307", "sumSplitSkippedSolidAdjacent0307",
        "sumSplitFromMassBelow0p5_0307", "sumSplitFromMassBelow0p25_0307", "sumSplitFromMassBelow0p1_0307",
        "minSplitDonorMass0307", "minSplitNewParticleMass0307", "minPostSplitDonorMass0307",
        "maxAbsCellMassError", "maxAbsCellMomentumError", "maxAbsCellKrelError0298",
        "lastFluidParticlesAfter", "lastInactiveParticlesAfter",
    ]
    art_dir.mkdir(parents=True, exist_ok=True)
    with out_per.open("w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=fieldnames)
        w.writeheader()
        w.writerows(out_rows)

    failures = sum(1 for r in out_rows if str(r.get("accepted")) != "1")
    print(f"[0307-analyze] rows={len(out_rows)} failures={failures} out={out_per}")
    return 0 if failures == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
