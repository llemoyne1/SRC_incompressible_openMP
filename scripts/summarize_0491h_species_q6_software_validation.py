#!/usr/bin/env python3
import argparse
import csv
import math
from collections import defaultdict
from pathlib import Path

BAD_MARKERS = (
    "fatal error",
    "strict path was requested but not handled",
    "cpu fallback",
    "fallback cpu",
    "non-finite",
    "nonfinite",
    "unregistered fluid particle types",
)


def finite(value):
    try:
        return math.isfinite(float(value))
    except (TypeError, ValueError):
        return False


def fnum(value, default=0.0):
    return float(value) if finite(value) else default


def inum(value, default=0):
    try:
        return int(float(value))
    except (TypeError, ValueError):
        return default


def csv_rows(path):
    if not path.is_file():
        return []
    with path.open(newline="") as stream:
        return list(csv.DictReader(stream))


def kv(path):
    out = {}
    if not path.is_file():
        return out
    for line in path.read_text(errors="replace").splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#") or "=" not in stripped:
            continue
        key, value = stripped.split("=", 1)
        out[key.strip()] = value.strip()
    return out


def truthy(value):
    return str(value).strip().lower() in {"1", "true", "yes", "on", "enabled"}


def params_for_output(output_dir):
    run = output_dir.parent
    params_dir = run / "params"
    if not params_dir.is_dir():
        return {}
    candidates = sorted(params_dir.glob("*.kv"))
    return kv(candidates[0]) if candidates else {}


def is_open_case(params):
    bcs = [
        params.get("bcLeft", ""),
        params.get("bcRight", ""),
        params.get("bcBottom", ""),
        params.get("bcTop", ""),
    ]
    return truthy(params.get("openBoundarySegmentsEnable", "false")) or any(
        bc in {"inlet", "outlet"} for bc in bcs
    )


def log_markers(root):
    markers = set()
    for path in root.glob("**/*.log"):
        text = path.read_text(errors="replace").lower()
        markers.update(marker for marker in BAD_MARKERS if marker in text)
    return sorted(markers)


def summarize_q6_audits(root):
    audit_paths = sorted(root.glob("**/cuda_species_q6_0491.csv"))
    rows_total = 0
    max_residual = 0.0
    max_tolerance = 0.0
    max_after_first_allocations = 0
    max_host_entries = 0
    max_weight_h2d = 0
    max_full_download = 0
    max_cpu_fallback = 0
    max_metadata_h2d = 0
    max_memory_per_cell_species = 0.0
    nonfinite_perf = 0
    common_total = []
    weighted_total = []
    species_count_perf = defaultdict(lambda: {"rows": 0, "deposit": 0.0, "weight": 0.0, "apply": 0.0})

    for path in audit_paths:
        rows = csv_rows(path)
        params = params_for_output(path.parent)
        nx = inum(params.get("Nx", 0))
        ny = inum(params.get("Ny", 0))
        cells = max(0, nx * ny)
        for idx, row in enumerate(rows):
            rows_total += 1
            max_residual = max(max_residual, fnum(row.get("barycentricResidualMaxAbs", 0.0)))
            max_tolerance = max(max_tolerance, fnum(params.get("speciesQ6ComparisonTolerance", 0.0)))
            max_host_entries = max(max_host_entries, inum(row.get("species_q6_host_cell_array_entries", 0)))
            max_weight_h2d = max(max_weight_h2d, inum(row.get("species_q6_weight_h2d", 0)))
            max_full_download = max(max_full_download, inum(row.get("species_q6_full_state_download", 0)))
            max_cpu_fallback = max(max_cpu_fallback, inum(row.get("species_q6_cpu_fallback", 0)))
            max_metadata_h2d = max(max_metadata_h2d, inum(row.get("species_q6_metadata_h2d_bytes", 0)))
            if idx > 0:
                max_after_first_allocations = max(
                    max_after_first_allocations,
                    inum(row.get("species_q6_allocation_calls", 0)),
                )
            species_count = inum(row.get("speciesCount", params.get("speciesCount", 0)))
            allocated = fnum(row.get("species_q6_allocated_bytes", 0.0))
            if cells > 0 and species_count > 0:
                max_memory_per_cell_species = max(
                    max_memory_per_cell_species,
                    allocated / float(cells * species_count),
                )
            perf_keys = [
                "depositSeconds",
                "solveSeconds",
                "applySeconds",
                "totalSeconds",
                "species_q6_deposit_seconds",
                "species_q6_weight_seconds",
                "species_q6_particle_apply_seconds",
            ]
            if not all(finite(row.get(key, "0")) for key in perf_keys if key in row):
                nonfinite_perf += 1
            mode = row.get("mode", "").strip('"')
            total = fnum(row.get("totalSeconds", 0.0))
            if mode == "common":
                common_total.append(total)
            if mode == "weighted":
                weighted_total.append(total)
            bucket = species_count_perf[species_count]
            bucket["rows"] += 1
            bucket["deposit"] += fnum(row.get("species_q6_deposit_seconds", 0.0))
            bucket["weight"] += fnum(row.get("species_q6_weight_seconds", 0.0))
            bucket["apply"] += fnum(row.get("species_q6_particle_apply_seconds", 0.0))

    avg_common = sum(common_total) / len(common_total) if common_total else 0.0
    avg_weighted = sum(weighted_total) / len(weighted_total) if weighted_total else 0.0
    overhead = (avg_weighted / avg_common - 1.0) if avg_common > 0.0 and avg_weighted > 0.0 else 0.0
    per_species_cost = []
    for species_count, bucket in sorted(species_count_perf.items()):
        rows = max(1, bucket["rows"])
        per_species_cost.append(
            f"ns={species_count}:deposit={bucket['deposit']/rows:.6g},"
            f"weight={bucket['weight']/rows:.6g},apply={bucket['apply']/rows:.6g}"
        )
    return {
        "auditFiles": len(audit_paths),
        "q6AuditRows": rows_total,
        "maxResidual": max_residual,
        "maxTolerance": max_tolerance,
        "maxAfterFirstAllocations": max_after_first_allocations,
        "maxHostCellArrayEntries": max_host_entries,
        "maxWeightH2D": max_weight_h2d,
        "maxFullStateDownload": max_full_download,
        "maxCpuFallback": max_cpu_fallback,
        "maxMetadataH2DBytes": max_metadata_h2d,
        "maxMemoryBytesPerCellSpecies": max_memory_per_cell_species,
        "nonfinitePerformanceRows": nonfinite_perf,
        "avgCommonQ6TotalSeconds": avg_common,
        "avgWeightedQ6TotalSeconds": avg_weighted,
        "weightedVsCommonTotalOverhead": overhead,
        "speciesCountCost": ";".join(per_species_cost),
    }


def summarize_species_mass(root, rel_tol):
    max_rel = 0.0
    checked_files = 0
    registered_failures = 0
    finite_failures = 0
    for path in sorted(root.glob("**/species_runtime*.csv")):
        params = params_for_output(path.parent)
        rows = csv_rows(path)
        if not rows:
            continue
        if any(row.get("registered", "1") != "1" for row in rows):
            registered_failures += 1
        if any(not finite(row.get("totalMass", "")) for row in rows):
            finite_failures += 1
        if is_open_case(params):
            continue
        by_type = defaultdict(list)
        for row in rows:
            by_type[row.get("type", "")].append(row)
        checked_files += 1
        for type_rows in by_type.values():
            initial = fnum(type_rows[0].get("totalMass", 0.0))
            final = fnum(type_rows[-1].get("totalMass", 0.0))
            if abs(initial) == 0.0 and abs(final) == 0.0:
                continue
            denom = max(abs(initial), 1.0e-300)
            max_rel = max(max_rel, abs(final - initial) / denom)
    return {
        "speciesRuntimeFilesChecked": checked_files,
        "maxClosedSpeciesMassRelativeDrift": max_rel,
        "speciesMassDriftPass": int(max_rel <= rel_tol),
        "registeredFailures": registered_failures,
        "speciesFiniteFailures": finite_failures,
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True)
    parser.add_argument("--status", required=True)
    parser.add_argument("--profile", required=True)
    parser.add_argument("--csv", required=True)
    parser.add_argument("--markdown", required=True)
    parser.add_argument("--mass-relative-tolerance", type=float, default=1.0e-10)
    args = parser.parse_args()

    root = Path(args.root)
    stages = csv_rows(Path(args.status))
    stage_failures = [row for row in stages if row.get("exit_code") != "0"]
    markers = log_markers(root)
    q6 = summarize_q6_audits(root)
    mass = summarize_species_mass(root, args.mass_relative_tolerance)
    required_custom = {"persistent_interface", "trace_species"}
    seen_stages = {row.get("stage") for row in stages}

    pass_checks = {
        "stagesExitZero": int(not stage_failures),
        "q6AuditsPresent": int(q6["q6AuditRows"] > 0),
        "q6ResidualWithinTolerance": int(q6["maxResidual"] <= max(q6["maxTolerance"], 1.0e-300)),
        "noAllocationsAfterWarmup": int(q6["maxAfterFirstAllocations"] == 0),
        "noHostCellSpeciesArray": int(q6["maxHostCellArrayEntries"] == 0),
        "noWeightH2D": int(q6["maxWeightH2D"] == 0),
        "noFullStateDownload": int(q6["maxFullStateDownload"] == 0),
        "noCpuFallback": int(q6["maxCpuFallback"] == 0),
        "performanceFinite": int(q6["nonfinitePerformanceRows"] == 0),
        "speciesMassConservedClosedCases": mass["speciesMassDriftPass"],
        "speciesRegistered": int(mass["registeredFailures"] == 0),
        "speciesMassFinite": int(mass["speciesFiniteFailures"] == 0),
        "interfaceAndTraceCovered": int(required_custom.issubset(seen_stages)),
        "noBadLogMarkers": int(not markers),
    }
    passed = all(value == 1 for value in pass_checks.values())

    row = {
        "pass": int(passed),
        "profile": args.profile,
        "stageCount": len(stages),
        "stageFailures": ";".join(row.get("stage", "") for row in stage_failures),
        "badMarkers": ";".join(markers),
        **pass_checks,
        **q6,
        **mass,
        "massRelativeTolerance": args.mass_relative_tolerance,
        "fullCampaignLengthsRequested": int(args.profile == "full"),
    }

    csv_path = Path(args.csv)
    csv_path.parent.mkdir(parents=True, exist_ok=True)
    with csv_path.open("w", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(row))
        writer.writeheader()
        writer.writerow(row)

    lines = [
        "# 0491h species-Q6 software validation",
        "",
        f"Result: **{'PASS' if passed else 'FAIL'}**",
        f"Profile: `{args.profile}`",
        "",
        "| Check | Value |",
        "| --- | ---: |",
    ]
    for key, value in pass_checks.items():
        lines.append(f"| {key} | {value} |")
    lines.extend([
        "",
        "| Metric | Value |",
        "| --- | ---: |",
        f"| Q6 audit rows | {q6['q6AuditRows']} |",
        f"| Max barycentric residual | {q6['maxResidual']} |",
        f"| Max tolerance | {q6['maxTolerance']} |",
        f"| Max allocations after warmup | {q6['maxAfterFirstAllocations']} |",
        f"| Max metadata H2D bytes/step | {q6['maxMetadataH2DBytes']} |",
        f"| Max memory bytes/cell/species | {q6['maxMemoryBytesPerCellSpecies']} |",
        f"| Weighted/common total overhead | {q6['weightedVsCommonTotalOverhead']} |",
        f"| Closed species mass relative drift | {mass['maxClosedSpeciesMassRelativeDrift']} |",
        f"| Species-count costs | {q6['speciesCountCost']} |",
    ])
    Path(args.markdown).write_text("\n".join(lines) + "\n")
    print(f"[0491h-summary] {'PASS' if passed else 'FAIL'} profile={args.profile}")
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
