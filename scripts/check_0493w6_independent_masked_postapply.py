#!/usr/bin/env python3
"""Validate the 0493w6 resident post-application species-Q6 diagnostics."""

from __future__ import annotations

import argparse
import csv
import math
from pathlib import Path
from typing import Dict


AUDIT_NAME = "cuda_species_q6_independent_masked_0493w5.csv"
PROFILES = ("full", "islands", "mixed60", "mixed40")
REQUIRED_COLUMNS = {
    "type",
    "q6Strength",
    "activeCells",
    "correctedParticles",
    "divBeforeRms",
    "divAfterRms",
    "divAfterProjectedFaceFluxRms",
    "divAfterAppliedCellVelocityRms",
    "divAfterProjectedFaceFluxMaxAbs",
    "divAfterAppliedCellVelocityMaxAbs",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--run-root",
        type=Path,
        default=Path("runs/0493w6_independent_masked_postapply_diagnostic"),
    )
    return parser.parse_args()


def last_rows_by_type(path: Path) -> Dict[int, dict[str, str]]:
    if not path.is_file():
        raise SystemExit(f"missing audit CSV: {path}")
    with path.open(newline="") as stream:
        reader = csv.DictReader(stream)
        if reader.fieldnames is None:
            raise SystemExit(f"missing CSV header: {path}")
        missing = REQUIRED_COLUMNS.difference(reader.fieldnames)
        if missing:
            raise SystemExit(f"{path}: missing 0493w6 columns: {sorted(missing)}")
        rows: Dict[int, dict[str, str]] = {}
        for row in reader:
            rows[int(row["type"])] = row
    if set(rows) != {1, 2}:
        raise SystemExit(f"{path}: expected final rows for types 1 and 2, got {sorted(rows)}")
    return rows


def finite_nonnegative(value: str, label: str) -> float:
    result = float(value)
    if not math.isfinite(result) or result < 0.0:
        raise SystemExit(f"{label}: expected finite non-negative value, got {value}")
    return result


def close(a: float, b: float) -> bool:
    return math.isclose(a, b, rel_tol=1.0e-13, abs_tol=1.0e-15)


def main() -> None:
    args = parse_args()
    summaries: list[str] = []

    for profile in PROFILES:
        rows = last_rows_by_type(args.run_root / profile / "output" / AUDIT_NAME)
        liquid = rows[1]
        gas = rows[2]

        before = finite_nonnegative(liquid["divBeforeRms"], f"{profile} liquid before")
        projected = finite_nonnegative(
            liquid["divAfterProjectedFaceFluxRms"], f"{profile} liquid projected"
        )
        applied = finite_nonnegative(
            liquid["divAfterAppliedCellVelocityRms"], f"{profile} liquid applied"
        )
        legacy_after = finite_nonnegative(liquid["divAfterRms"], f"{profile} legacy after")
        if not close(legacy_after, projected):
            raise SystemExit(
                f"{profile}: legacy divAfterRms={legacy_after} no longer aliases "
                f"projected-face divergence={projected}"
            )

        gas_applied = finite_nonnegative(
            gas["divAfterAppliedCellVelocityRms"], f"{profile} gas applied"
        )
        if int(gas["activeCells"]) != 0 or int(gas["correctedParticles"]) != 0:
            raise SystemExit(f"{profile}: disabled gas received Q6 support/correction")
        if gas_applied != 0.0:
            raise SystemExit(f"{profile}: disabled gas post-apply divergence must remain zero")

        active = int(liquid["activeCells"])
        if profile == "mixed40":
            if active != 0 or projected != 0.0 or applied != 0.0:
                raise SystemExit(
                    "mixed40: below-threshold liquid must have zero support and diagnostics"
                )
            summaries.append("mixed40: inactive")
            continue

        if active <= 0 or not before > 0.0:
            raise SystemExit(f"{profile}: expected non-empty divergent liquid support")
        if projected > max(1.0e-8, 1.0e-5 * before):
            raise SystemExit(
                f"{profile}: projected face flux was not strongly corrected: "
                f"before={before:.6e} projected={projected:.6e}"
            )

        # Full support maps the solved face correction directly to the cell field;
        # it is the strict post-application reference.  The disconnected islands
        # case is deliberately reported without a severe PASS threshold because
        # 0493w6 is intended to expose the face-to-cell mismatch at the mask edge.
        if profile in {"full", "mixed60"} and applied > max(1.0e-8, 1.0e-5 * before):
            raise SystemExit(
                f"{profile}: post-application cell velocity was not strongly corrected: "
                f"before={before:.6e} applied={applied:.6e}"
            )

        projected_ratio = projected / before
        applied_ratio = applied / before
        summaries.append(
            f"{profile}: projected/before={projected_ratio:.3e} "
            f"applied/before={applied_ratio:.3e}"
        )

    print("[0493w6] PASS resident post-application diagnostics")
    for summary in summaries:
        print(f"[0493w6] {summary}")


if __name__ == "__main__":
    main()
