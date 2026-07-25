#!/usr/bin/env python3
"""0493c: audit scalar CUDA-resident species-resampling qualification outputs."""
from __future__ import annotations

import argparse
import csv
import math
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Iterable


CLOSED_CASE_TOKENS = ("periodic", "walls", "06_darcy")
EXPECTED_ACTIVITY_EXCEPTIONS = {"10_periodic_none", "12_periodic_darcy_none"}


@dataclass
class CaseAudit:
    name: str
    status: str = "PASS"
    reasons: list[str] = field(default_factory=list)
    rows: int = 0
    final_step: int = -1
    max_disabled_mutations: int = 0
    max_invalid_operations: int = 0
    max_plan_overflow: int = 0
    max_pool_corruption: int = 0
    mutation_activity: int = 0
    population_guard_applied_rows: int = 0
    direct_plan_entries: int = 0
    direct_transfer_operations: int = 0
    direct_moved_mass: float = 0.0
    mass_drift_rel: float = 0.0
    q6_applied_rows: int = 0
    q6_nonconverged_rows: int = 0
    q6_barycentric_residual_max: float = 0.0
    max_species_mass_residual: float = 0.0
    summary_path: str = ""
    maintenance_path: str = ""
    fast_path: str = ""
    plan_path: str = ""
    closure_path: str = ""

    def fail(self, reason: str) -> None:
        self.status = "FAIL"
        if reason not in self.reasons:
            self.reasons.append(reason)


def read_rows(path: Path) -> list[dict[str, str]]:
    if not path.is_file():
        return []
    with path.open(newline="", encoding="utf-8") as handle:
        return list(csv.DictReader(handle))


def number(row: dict[str, str], key: str, default: float = 0.0) -> float:
    raw = row.get(key, "")
    if raw is None or raw.strip() == "":
        return default
    try:
        value = float(raw)
    except ValueError:
        return math.nan
    return value


def integer(row: dict[str, str], key: str, default: int = 0) -> int:
    value = number(row, key, float(default))
    if not math.isfinite(value):
        return default
    return int(round(value))


def max_int(rows: Iterable[dict[str, str]], keys: Iterable[str]) -> int:
    result = 0
    for row in rows:
        result = max(result, sum(max(0, integer(row, key)) for key in keys))
    return result


def require_finite(audit: CaseAudit, rows: list[dict[str, str]], keys: Iterable[str]) -> None:
    for row in rows:
        for key in keys:
            if key in row and not math.isfinite(number(row, key, math.nan)):
                audit.fail(f"non-finite:{key}")
                return


def find_status(root: Path) -> Path | None:
    for name in ("status_0493c.csv", "status_0493b.csv"):
        path = root / name
        if path.is_file():
            return path
    candidates = sorted(root.glob("status_*.csv"))
    return candidates[0] if candidates else None


def audit_case(case_dir: Path, case_name: str, args: argparse.Namespace) -> CaseAudit:
    audit = CaseAudit(name=case_name)
    out = case_dir / "output"
    summary_path = out / "summary_runtime.csv"
    maint_path = out / "cuda_species_resident_maintenance_0490n.csv"
    fast_path = out / "cuda_species_resident_fast_path_0490m.csv"
    plan_path = out / "cuda_species_transfer_plan_0490k.csv"
    closure_path = out / "cuda_species_mass_closure_0490i.csv"
    audit.summary_path = str(summary_path)
    audit.maintenance_path = str(maint_path)
    audit.fast_path = str(fast_path)
    audit.plan_path = str(plan_path)
    audit.closure_path = str(closure_path)

    summary = read_rows(summary_path)
    maint = read_rows(maint_path)
    fast = read_rows(fast_path)
    plan = read_rows(plan_path)
    closure = read_rows(closure_path)
    if not summary:
        audit.fail("missing-summary")
        return audit
    if not maint:
        audit.fail("missing-0490n-diagnostics")
    if not fast:
        audit.fail("missing-0490m-diagnostics")
    if not plan:
        audit.fail("missing-0490k-diagnostics")
    if not closure:
        audit.fail("missing-0490i-diagnostics")

    audit.rows = len(summary)
    audit.final_step = integer(summary[-1], "step", -1)
    active_rows = [r for r in summary if integer(r, "resampComputed") != 0]
    if not active_rows:
        audit.fail("resampling-never-computed")
        active_rows = summary

    require_finite(
        audit,
        summary,
        (
            "totalMass", "Px", "Py", "meanKinetic", "kBTEstimate",
            "resampTotalMass", "resampMRelRms", "resampMRelMaxAbs",
            "resampParticleMassMin", "resampParticleMassMax",
            "q6ResidualRel", "q6SpeciesQ6BarycentricResidualMaxAbs",
        ),
    )

    for row in summary:
        np = integer(row, "Np")
        roles = integer(row, "nFluidParticles") + integer(row, "nInactiveParticles") + integer(row, "nLatentParticles")
        if np != roles:
            audit.fail("role-capacity-incoherent")
            break
        if number(row, "totalMass") < 0.0 or number(row, "resampParticleMassMin") < 0.0:
            audit.fail("negative-mass")
            break

    audit.max_disabled_mutations = max_int(summary, ("resampDisabledSpeciesMutationCount",))
    audit.max_disabled_mutations = max(
        audit.max_disabled_mutations,
        max_int(fast, ("disabledSpeciesMutationCount",)),
        max_int(closure, ("disabledSpeciesMutationCount",)),
    )
    if audit.max_disabled_mutations != 0:
        audit.fail("disabled-species-mutation")

    audit.max_invalid_operations = max_int(
        fast,
        ("invalidOperations",),
    )
    audit.max_invalid_operations = max(
        audit.max_invalid_operations,
        max_int(
            summary,
            (
                "resampExtractionApplySkippedInvalidParticles",
                "resampExtractionApplySkippedDuplicateParticles",
                "resampInsertionApplySkippedInvalidSourceParticles",
                "resampInsertionApplySkippedInvalidReceiverCells",
                "resampInsertionApplySkippedInvalidMass",
                "resampRemapSkippedInvalidMassCells",
                "resampThermalRenormSkippedInvalidEnergyCells",
                "resampMassGuardSkippedInvalidMassCells",
            ),
        ),
    )
    if audit.max_invalid_operations != 0:
        audit.fail("invalid-resampling-operation")

    audit.max_plan_overflow = max_int(plan, ("overflowCount", "planMismatch", "typeMismatch"))
    if audit.max_plan_overflow != 0:
        audit.fail("plan-corruption")

    for row in maint:
        if integer(row, "attempted") != 0 and integer(row, "strictMode") != 0:
            if integer(row, "handled") != 1 or integer(row, "pass") != 1 or integer(row, "skipped") != 0:
                audit.fail("0490n-not-handled-pass")
                break

    for row in fast:
        if integer(row, "attempted") != 0:
            if integer(row, "handled") != 1 or integer(row, "pass") != 1 or integer(row, "skipped") != 0:
                audit.fail("0490m-not-handled-pass")
                break

    for row in plan:
        if integer(row, "handled") != 1 or integer(row, "pass") != 1 or integer(row, "accepted") != 1:
            audit.fail("0490k-not-accepted-pass")
            break

    for row in closure:
        if integer(row, "attempted") != 0:
            if integer(row, "handled") != 1 or integer(row, "productionFastPath") != 1:
                audit.fail("0490i-not-resident-production")
                break
            for key, expected in (
                ("diagnosticCellDownloadSkipped", 1),
                ("cpuDepositComparisonSkipped", 1),
                ("sharedStatePreserved", 1),
            ):
                if key in row and integer(row, key) != expected:
                    audit.fail(f"0490i-residency:{key}")
            if integer(row, "invalidTypeCount") != 0:
                audit.fail("0490i-invalid-type")
            if abs(number(row, "particleDownloadSeconds")) > 0.0:
                audit.fail("0490i-particle-download")
    audit.max_species_mass_residual = max(
        (abs(number(row, "maxSpeciesMassRelResidual")) for row in closure),
        default=0.0,
    )

    audit.max_pool_corruption = max_int(
        maint,
        ("activePrefixViolations", "duplicateFreeSlots", "activeAndFreeSlots", "invalidRoleSlots"),
    )
    if audit.max_pool_corruption != 0:
        audit.fail("pool-corruption")

    for row in maint:
        storage = integer(row, "storageSlots")
        role_sum = integer(row, "fluidSlots") + integer(row, "latentSlots") + integer(row, "inactiveSlots")
        if storage != role_sum:
            audit.fail("maintenance-slot-balance")
            break
        if integer(row, "depositRequested") != 0:
            for key, expected in (
                ("cellMirrorDownloadBytes", 0),
                ("policyHostArrayEntries", 0),
                ("cellPolicyDeviceResident", 1),
            ):
                if key in row and integer(row, key) != expected:
                    audit.fail(f"resident-policy:{key}")
                    break

    for row in fast:
        for key, expected in (
            ("fullStateCopySkipped", 1),
            ("fullStateDownloadSkipped", 1),
            ("compactPatchbackBytes", 0),
            ("planArrayDownloadSkipped", 1),
            ("planArrayUploadSkipped", 1),
            ("operationRoundTripSkipped", 1),
        ):
            if key in row and integer(row, key) != expected:
                audit.fail(f"resident-fast-path:{key}")
                break

    summary_mutation_activity = max_int(
        active_rows,
        (
            "resampTransferPairs",
            "resampExtractionApplyOpsApplied",
            "resampInsertionApplyOpsApplied",
            "resampPopulationGuardSplitParticlesCreated",
            "resampPopulationGuardExtractedParticles",
        ),
    )
    # The resident 0490j adapter currently exposes the authoritative applied
    # bit even when its detailed split/merge counters are not copied into the
    # generic WeightedResamplingDiagnostics fields. Count that bit as real
    # support mutation rather than reporting a false no-activity failure.
    audit.population_guard_applied_rows = sum(
        1 for row in active_rows if integer(row, "resampPopulationGuardApplied") != 0
    )
    audit.direct_plan_entries = max_int(plan, ("gpuPlanEntries",))
    audit.direct_transfer_operations = max_int(fast, ("operations",))
    audit.direct_moved_mass = max(
        (abs(number(row, "movedMass")) for row in fast),
        default=0.0,
    )
    audit.mutation_activity = max(
        summary_mutation_activity,
        1 if audit.population_guard_applied_rows > 0 else 0,
        audit.direct_transfer_operations,
    )

    all_disabled = case_name in EXPECTED_ACTIVITY_EXCEPTIONS
    if all_disabled:
        if audit.mutation_activity != 0 or audit.direct_plan_entries != 0 or audit.direct_moved_mass > 0.0:
            audit.fail("all-disabled-case-mutated")
        for key in ("nFluidParticles", "nInactiveParticles", "nLatentParticles"):
            if integer(summary[0], key) != integer(summary[-1], key):
                audit.fail(f"all-disabled-role-change:{key}")
        m0 = number(summary[0], "totalMass", math.nan)
        m1 = number(summary[-1], "totalMass", math.nan)
        if not (math.isfinite(m0) and math.isfinite(m1)) or abs(m1 - m0) > args.closed_mass_rel_tol * max(abs(m0), 1.0):
            audit.fail("all-disabled-mass-change")
    else:
        if args.require_activity and audit.mutation_activity == 0:
            audit.fail("no-resampling-mutation")
        if args.require_direct_transfer:
            if audit.direct_plan_entries == 0:
                audit.fail("no-0490k-plan-entry")
            if audit.direct_transfer_operations == 0 or not (audit.direct_moved_mass > 0.0):
                audit.fail("no-0490m-direct-transfer")

    expected_type = 0
    if "solvent_only" in case_name:
        expected_type = 1
    elif "colloid_only" in case_name:
        expected_type = 2
    if expected_type != 0:
        for row in plan:
            if integer(row, "gpuPlanEntries") <= 0:
                continue
            for key in ("firstParticleType", "lastParticleType"):
                value = integer(row, key)
                if value != expected_type:
                    audit.fail(f"disabled-species-plan-type:{key}={value}")
                    break

    masses = [number(r, "totalMass", math.nan) for r in summary]
    masses = [m for m in masses if math.isfinite(m)]
    if masses:
        scale = max(abs(masses[0]), 1.0)
        audit.mass_drift_rel = (max(masses) - min(masses)) / scale
        closed = any(token in case_name for token in CLOSED_CASE_TOKENS) and "fullface" not in case_name and "segmented" not in case_name
        if closed and audit.mass_drift_rel > args.closed_mass_rel_tol:
            audit.fail("closed-mass-drift")

    q6_rows = [r for r in summary if integer(r, "q6Applied") != 0]
    audit.q6_applied_rows = len(q6_rows)
    audit.q6_nonconverged_rows = sum(1 for r in q6_rows if integer(r, "q6Converged") != 1)
    audit.q6_barycentric_residual_max = max(
        (abs(number(r, "q6SpeciesQ6BarycentricResidualMaxAbs")) for r in q6_rows),
        default=0.0,
    )
    if q6_rows and audit.q6_nonconverged_rows:
        audit.fail("q6-not-converged")
    if q6_rows and audit.q6_barycentric_residual_max > args.q6_bary_tol:
        audit.fail("q6-barycentric-residual")

    return audit


def write_csv(path: Path, audits: list[CaseAudit]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fields = [
        "case", "status", "reasons", "rows", "finalStep",
        "maxDisabledSpeciesMutations", "maxInvalidOperations", "maxPlanCorruption",
        "maxPoolCorruption", "mutationActivity", "populationGuardAppliedRows",
        "directPlanEntries", "directTransferOperations", "directMovedMass",
        "massDriftRel", "q6AppliedRows",
        "q6NonconvergedRows", "q6BarycentricResidualMax", "maxSpeciesMassResidual", "summaryPath",
        "maintenancePath", "fastPath", "planPath", "closurePath",
    ]
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        for a in audits:
            writer.writerow({
                "case": a.name,
                "status": a.status,
                "reasons": ";".join(a.reasons) if a.reasons else "ok",
                "rows": a.rows,
                "finalStep": a.final_step,
                "maxDisabledSpeciesMutations": a.max_disabled_mutations,
                "maxInvalidOperations": a.max_invalid_operations,
                "maxPlanCorruption": a.max_plan_overflow,
                "maxPoolCorruption": a.max_pool_corruption,
                "mutationActivity": a.mutation_activity,
                "populationGuardAppliedRows": a.population_guard_applied_rows,
                "directPlanEntries": a.direct_plan_entries,
                "directTransferOperations": a.direct_transfer_operations,
                "directMovedMass": f"{a.direct_moved_mass:.17g}",
                "massDriftRel": f"{a.mass_drift_rel:.17g}",
                "q6AppliedRows": a.q6_applied_rows,
                "q6NonconvergedRows": a.q6_nonconverged_rows,
                "q6BarycentricResidualMax": f"{a.q6_barycentric_residual_max:.17g}",
                "maxSpeciesMassResidual": f"{a.max_species_mass_residual:.17g}",
                "summaryPath": a.summary_path,
                "maintenancePath": a.maintenance_path,
                "fastPath": a.fast_path,
                "planPath": a.plan_path,
                "closurePath": a.closure_path,
            })


def write_markdown(path: Path, root: Path, audits: list[CaseAudit]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    passed = sum(a.status == "PASS" for a in audits)
    with path.open("w", encoding="utf-8") as handle:
        handle.write("# 0493c resident species-resampling qualification\n\n")
        handle.write(f"Run root: `{root}`\n\n")
        handle.write(f"Result: **{passed}/{len(audits)} PASS**\n\n")
        handle.write("| Case | Status | Activity | Guard rows | 0490k entries | 0490m ops | Moved mass | Disabled mutations | Invalid ops | Pool errors | Mass drift rel. | Species mass residual | Q6 bary. max | Reason |\n")
        handle.write("|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|\n")
        for a in audits:
            handle.write(
                f"| {a.name} | {a.status} | {a.mutation_activity} | {a.population_guard_applied_rows} | "
                f"{a.direct_plan_entries} | {a.direct_transfer_operations} | {a.direct_moved_mass:.6g} | "
                f"{a.max_disabled_mutations} | {a.max_invalid_operations + a.max_plan_overflow} | {a.max_pool_corruption} | "
                f"{a.mass_drift_rel:.3e} | {a.max_species_mass_residual:.3e} | {a.q6_barycentric_residual_max:.3e} | "
                f"{'; '.join(a.reasons) if a.reasons else 'ok'} |\n"
            )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--csv", type=Path)
    parser.add_argument("--markdown", type=Path)
    parser.add_argument("--closed-mass-rel-tol", type=float, default=1.0e-9)
    parser.add_argument("--q6-bary-tol", type=float, default=1.0e-8)
    parser.add_argument("--require-activity", action="store_true")
    parser.add_argument(
        "--require-direct-transfer",
        action="store_true",
        help="require nonzero 0490k plan entries and 0490m moved mass except for the all-disabled case",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    root = args.root.resolve()
    status_path = find_status(root)
    if status_path is None:
        print(f"[0493c-audit] ERROR no status CSV below {root}", file=sys.stderr)
        return 2
    status_rows = read_rows(status_path)
    if not status_rows:
        print(f"[0493c-audit] ERROR empty status CSV: {status_path}", file=sys.stderr)
        return 2

    audits: list[CaseAudit] = []
    for status in status_rows:
        case_name = (status.get("case") or "").strip()
        if not case_name:
            continue
        if (status.get("status") or "").strip() != "PASS":
            a = CaseAudit(name=case_name)
            a.fail(f"runner-status:{status.get('reason', 'unknown')}")
            audits.append(a)
            continue
        if (status.get("reason") or "").strip() == "preflight-only":
            continue
        audits.append(audit_case(root / case_name, case_name, args))

    if not audits:
        print("[0493c-audit] ERROR no executed cases to audit", file=sys.stderr)
        return 2

    csv_path = args.csv or root / "qualification_0493c.csv"
    md_path = args.markdown or root / "qualification_0493c.md"
    write_csv(csv_path, audits)
    write_markdown(md_path, root, audits)
    failed = [a for a in audits if a.status != "PASS"]
    for a in audits:
        print(
            f"[0493c-audit] case={a.name} status={a.status} activity={a.mutation_activity} "
            f"guardRows={a.population_guard_applied_rows} planEntries={a.direct_plan_entries} "
            f"directOps={a.direct_transfer_operations} movedMass={a.direct_moved_mass:.6g} "
            f"disabled={a.max_disabled_mutations} invalid={a.max_invalid_operations + a.max_plan_overflow} "
            f"pool={a.max_pool_corruption} massDrift={a.mass_drift_rel:.3e} "
            f"speciesMassResidual={a.max_species_mass_residual:.3e} q6Bary={a.q6_barycentric_residual_max:.3e} "
            f"reason={';'.join(a.reasons) if a.reasons else 'ok'}"
        )
    print(f"[0493c-audit] csv={csv_path}")
    print(f"[0493c-audit] markdown={md_path}")
    if failed:
        print(f"[0493c-audit] FAIL {len(failed)}/{len(audits)}", file=sys.stderr)
        return 2
    print(f"[0493c-audit] PASS {len(audits)}/{len(audits)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
