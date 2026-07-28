#!/usr/bin/env python3
from __future__ import annotations

import argparse
import csv
import math
import tempfile
from pathlib import Path


def load_csv(path: Path) -> list[dict[str, str]]:
    if not path.is_file():
        raise SystemExit(f"missing CSV: {path}")
    with path.open(newline="") as stream:
        return list(csv.DictReader(stream))


def number(row: dict[str, str], key: str, default: float = 0.0) -> float:
    raw = row.get(key, "")
    try:
        return float(raw) if raw not in (None, "") else default
    except ValueError:
        return default


def integer(row: dict[str, str], key: str, default: int = 0) -> int:
    return int(number(row, key, float(default)))


def mean(rows: list[dict[str, str]], key: str) -> float:
    return sum(number(row, key) for row in rows) / len(rows) if rows else math.nan


def analyze(run_root: Path) -> int:
    output = run_root / "output"
    core_path = output / "cuda_resampling_population_guard_0297.csv"
    caller_path = output / "cuda_resampling_population_guard_caller_0493o3.csv"
    core = load_csv(core_path)
    caller = load_csv(caller_path)

    required_core = {
        "step", "poorNonEmptyPairs0493o1", "appliedSplits0493o1",
        "noPoorEarlyExit0493o3", "localSupportCandidateBuildSeconds0493o3",
        "localSupportPlanSeconds0493o3", "localSupportApplySeconds0493o3",
        "depositAfterSeconds", "krelBeforeSeconds0493o3",
        "postMutationValidationSeconds0493o3", "totalSeconds",
    }
    missing = required_core.difference(core[0].keys() if core else set())
    if missing:
        raise SystemExit(f"missing 0493o3 core columns: {sorted(missing)}")

    by_step = {integer(row, "step"): row for row in caller}
    errors: list[str] = []
    early = [row for row in core if integer(row, "noPoorEarlyExit0493o3") == 1]
    active = [row for row in core if integer(row, "appliedSplits0493o1") > 0]

    for row in early:
        step = integer(row, "step")
        if integer(row, "poorNonEmptyPairs0493o1") != 0:
            errors.append(f"step {step}: early exit with poor pairs")
        if integer(row, "appliedSplits0493o1") != 0:
            errors.append(f"step {step}: early exit with applied splits")
        for key in (
            "localSupportCandidateBuildSeconds0493o3",
            "localSupportPlanSeconds0493o3",
            "localSupportApplySeconds0493o3",
            "depositAfterSeconds",
            "krelBeforeSeconds0493o3",
            "postMutationValidationSeconds0493o3",
        ):
            if abs(number(row, key)) > 1.0e-15:
                errors.append(f"step {step}: {key}={number(row, key):.6e} on early exit")

    for row in active:
        step = integer(row, "step")
        if integer(row, "noPoorEarlyExit0493o3") != 0:
            errors.append(f"step {step}: active mutation marked as early exit")
        if integer(row, "poorNonEmptyPairs0493o1") <= 0:
            errors.append(f"step {step}: applied splits without poor pair")

    core_steps = {integer(row, "step") for row in core}
    caller_steps = set(by_step)
    if core_steps != caller_steps:
        errors.append(
            f"caller/core step mismatch: core-only={sorted(core_steps-caller_steps)[:5]} "
            f"caller-only={sorted(caller_steps-core_steps)[:5]}"
        )

    print("===== 0493o3 — NO-POOR EARLY EXIT =====")
    print(f"runRoot={run_root}")
    print(f"rows={len(core)}")
    print(f"earlyExitRows={len(early)}")
    print(f"activeRows={len(active)}")
    print(f"earlyExitFraction={len(early)/len(core):.6%}" if core else "earlyExitFraction=nan")
    print(f"meanCoreSecondsEarly={mean(early, 'totalSeconds'):.9g}")
    print(f"meanCoreSecondsActive={mean(active, 'totalSeconds'):.9g}")
    print(f"meanCallerSecondsEarly={mean([by_step[integer(r, 'step')] for r in early if integer(r, 'step') in by_step], 'totalCallerSeconds0493o3'):.9g}")
    print(f"meanCallerInitialMaintenanceEarly={mean([by_step[integer(r, 'step')] for r in early if integer(r, 'step') in by_step], 'initialMaintenanceSeconds0493o3'):.9g}")
    print(f"meanCallerStateSyncEarly={mean([by_step[integer(r, 'step')] for r in early if integer(r, 'step') in by_step], 'stateSyncSeconds0493o3'):.9g}")
    print(f"totalAppliedSplits={sum(integer(r, 'appliedSplits0493o1') for r in core)}")

    if errors:
        print("[0493o3-analysis] FAIL")
        for error in errors:
            print(f"  - {error}")
        return 1
    print("[0493o3-analysis] PASS")
    return 0


def self_test() -> int:
    with tempfile.TemporaryDirectory(prefix="0493o3-analysis-") as tmp:
        root = Path(tmp)
        out = root / "output"
        out.mkdir()
        with (out / "cuda_resampling_population_guard_0297.csv").open("w", newline="") as stream:
            writer = csv.DictWriter(stream, fieldnames=[
                "step", "poorNonEmptyPairs0493o1", "appliedSplits0493o1",
                "noPoorEarlyExit0493o3", "localSupportCandidateBuildSeconds0493o3",
                "localSupportPlanSeconds0493o3", "localSupportApplySeconds0493o3",
                "depositAfterSeconds", "krelBeforeSeconds0493o3",
                "postMutationValidationSeconds0493o3", "totalSeconds",
            ])
            writer.writeheader()
            writer.writerow({
                "step": 1, "poorNonEmptyPairs0493o1": 0, "appliedSplits0493o1": 0,
                "noPoorEarlyExit0493o3": 1, "localSupportCandidateBuildSeconds0493o3": 0,
                "localSupportPlanSeconds0493o3": 0, "localSupportApplySeconds0493o3": 0,
                "depositAfterSeconds": 0, "krelBeforeSeconds0493o3": 0,
                "postMutationValidationSeconds0493o3": 0, "totalSeconds": 0.001,
            })
            writer.writerow({
                "step": 2, "poorNonEmptyPairs0493o1": 1, "appliedSplits0493o1": 5,
                "noPoorEarlyExit0493o3": 0, "localSupportCandidateBuildSeconds0493o3": 0.001,
                "localSupportPlanSeconds0493o3": 0.001, "localSupportApplySeconds0493o3": 0.001,
                "depositAfterSeconds": 0.001, "krelBeforeSeconds0493o3": 0.001,
                "postMutationValidationSeconds0493o3": 0.001, "totalSeconds": 0.01,
            })
        with (out / "cuda_resampling_population_guard_caller_0493o3.csv").open("w", newline="") as stream:
            writer = csv.DictWriter(stream, fieldnames=[
                "step", "noPoorEarlyExit0493o3", "poorNonEmptyPairs0493o1",
                "appliedSplits0493o1", "stateSyncSeconds0493o3",
                "initialMaintenanceSeconds0493o3", "authoritySeconds0493o3",
                "postGuardMaintenanceSeconds0493o3", "remainingPipelineSeconds0493o3",
                "totalCallerSeconds0493o3",
            ])
            writer.writeheader()
            for step, early, poor, splits in ((1, 1, 0, 0), (2, 0, 1, 5)):
                writer.writerow({
                    "step": step, "noPoorEarlyExit0493o3": early,
                    "poorNonEmptyPairs0493o1": poor, "appliedSplits0493o1": splits,
                    "stateSyncSeconds0493o3": 0.001,
                    "initialMaintenanceSeconds0493o3": 0.001,
                    "authoritySeconds0493o3": 0.0,
                    "postGuardMaintenanceSeconds0493o3": 0.0,
                    "remainingPipelineSeconds0493o3": 0.0,
                    "totalCallerSeconds0493o3": 0.002,
                })
        return analyze(root)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("run_root", nargs="?", type=Path)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        return self_test()
    if args.run_root is None:
        parser.error("run_root is required unless --self-test is used")
    return analyze(args.run_root)


if __name__ == "__main__":
    raise SystemExit(main())
