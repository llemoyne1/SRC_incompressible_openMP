#!/usr/bin/env python3
"""Independent deep qualification for the 0491h species-sensitive Q6 campaign."""

from __future__ import annotations

import argparse
import csv
import hashlib
import math
import re
import struct
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
    "cuda error",
)


def rows(path: Path):
    if not path.is_file():
        return []
    with path.open(newline="") as stream:
        return list(csv.DictReader(stream))


def finite(value) -> bool:
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


def boolish(value) -> bool:
    return str(value).strip().lower() in {"1", "true", "yes", "on", "enabled"}


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def read_state(path: Path):
    data = path.read_bytes()
    if len(data) < 16 + 40 + 64:
        raise ValueError(f"truncated state: {path}")
    if not data[:16].startswith(b"SRCMPCD_STATE"):
        raise ValueError(f"invalid state magic: {path}")
    offset = 16
    version, endian, dim, scalar, n, has_type, has_mass, role_bytes, type_bytes = struct.unpack_from(
        "<IIIIQIIII", data, offset
    )
    offset += struct.calcsize("<IIIIQIIII")
    reserved = struct.unpack_from("<8Q", data, offset)
    offset += struct.calcsize("<8Q")
    if endian != 0x01020304 or dim != 2 or scalar != 1 or role_bytes != 8 or type_bytes != 4:
        raise ValueError(f"unsupported state format in {path}")

    def take(fmt, count):
        nonlocal offset
        size = struct.calcsize(f"<{count}{fmt}")
        values = struct.unpack_from(f"<{count}{fmt}", data, offset)
        offset += size
        return values

    state = {
        "version": version,
        "n": n,
        "reserved": reserved,
        "x": take("d", n),
        "y": take("d", n),
        "vx": take("d", n),
        "vy": take("d", n),
        "type": take("I", n) if has_type else tuple(0 for _ in range(n)),
        "mass": take("d", n) if has_mass else tuple(1.0 for _ in range(n)),
        "role": take("B", n),
    }
    if offset != len(data):
        raise ValueError(f"unexpected trailing bytes in {path}: {len(data)-offset}")
    return state


def compare_states(a_path: Path, b_path: Path, tolerance: float):
    a = read_state(a_path)
    b = read_state(b_path)
    result = {
        "stateShaExact": int(sha256(a_path) == sha256(b_path)),
        "stateParticleCountEqual": int(a["n"] == b["n"]),
        "stateTypeExact": 0,
        "stateRoleExact": 0,
        "stateMassExact": 0,
        "stateMaxPositionError": math.inf,
        "stateMaxVelocityError": math.inf,
        "stateEquivalent": 0,
    }
    if a["n"] != b["n"]:
        return result
    result["stateTypeExact"] = int(a["type"] == b["type"])
    result["stateRoleExact"] = int(a["role"] == b["role"])
    result["stateMassExact"] = int(a["mass"] == b["mass"])
    result["stateMaxPositionError"] = max(
        [0.0]
        + [abs(x - y) for x, y in zip(a["x"], b["x"])]
        + [abs(x - y) for x, y in zip(a["y"], b["y"])]
    )
    result["stateMaxVelocityError"] = max(
        [0.0]
        + [abs(x - y) for x, y in zip(a["vx"], b["vx"])]
        + [abs(x - y) for x, y in zip(a["vy"], b["vy"])]
    )
    result["stateStructureExact"] = int(
        result["stateParticleCountEqual"] == 1
        and result["stateTypeExact"] == 1
        and result["stateRoleExact"] == 1
        and result["stateMassExact"] == 1
    )
    result["statePositionPass"] = int(result["stateMaxPositionError"] <= tolerance)
    result["stateVelocityPass"] = int(result["stateMaxVelocityError"] <= tolerance)
    result["stateTrajectoryEquivalent"] = int(
        result["statePositionPass"] == 1 and result["stateVelocityPass"] == 1
    )
    result["stateEquivalenceTolerance"] = tolerance
    result["statePositionErrorOverTolerance"] = (
        result["stateMaxPositionError"] / tolerance if tolerance > 0.0 else math.inf
    )
    result["stateVelocityErrorOverTolerance"] = (
        result["stateMaxVelocityError"] / tolerance if tolerance > 0.0 else math.inf
    )
    result["stateEquivalent"] = int(
        result["stateStructureExact"] == 1
        and result["stateTrajectoryEquivalent"] == 1
    )
    return result


def final_step_from_summary(output: Path):
    data = rows(output / "summary_runtime.csv")
    return max((inum(row.get("step")) for row in data), default=-1)


def thermostat_audit(output: Path, expected_steps: int, enabled: bool, target: float, tolerance: float):
    data = [row for row in rows(output / "summary_runtime.csv") if inum(row.get("step"), -1) >= 1]
    if not enabled:
        return {
            "pass": int(bool(data) and all(inum(row.get("thermostatApplied"), 0) == 0 for row in data)),
            "maxError": 0.0,
            "maxKBT": max((fnum(row.get("kBTEstimate"), 0.0) for row in data), default=0.0),
        }
    observed_steps = [inum(row.get("step"), -1) for row in data]
    exact = bool(observed_steps) and observed_steps[-1] == expected_steps
    applied = bool(data) and all(inum(row.get("thermostatApplied"), 0) == 1 for row in data)
    after = [fnum(row.get("thermostatKBTAfter"), math.inf) for row in data]
    errors = [abs(value - target) for value in after]
    finite_values = bool(data) and all(finite(value) for value in after)
    return {
        "pass": int(exact and applied and finite_values and max(errors, default=math.inf) <= tolerance),
        "maxError": max(errors, default=math.inf),
        "maxKBT": max((fnum(row.get("kBTEstimate"), math.inf) for row in data), default=math.inf),
    }


def q6_audit(output: Path, expected_steps: int, tolerance: float):
    path = output / "cuda_species_q6_0491.csv"
    data = rows(path)
    step_values = [inum(row.get("step"), -1) for row in data]
    exact_steps = step_values == list(range(1, expected_steps + 1))
    residuals_abs = [fnum(row.get("barycentricResidualMaxAbs"), math.inf) for row in data]
    residuals_scaled = [
        fnum(row.get("barycentricResidualMaxScaled", row.get("barycentricResidualMaxAbs")), math.inf)
        for row in data
    ]
    totals = [fnum(row.get("totalSeconds"), math.nan) for row in data]
    max_residual_abs = max(residuals_abs, default=math.inf)
    max_residual_scaled = max(residuals_scaled, default=math.inf)
    return {
        "present": int(path.is_file()),
        "rows": len(data),
        "exactSteps": int(exact_steps),
        "allApplied": int(bool(data) and all(inum(row.get("q6Applied")) == 1 for row in data)),
        "allConverged": int(bool(data) and all(inum(row.get("q6Converged")) == 1 for row in data)),
        "allFinite": int(bool(data) and all(finite(v) for v in residuals_abs + residuals_scaled + totals)),
        "maxResidualAbs": max_residual_abs,
        "maxResidualScaled": max_residual_scaled,
        "residualPass": int(max_residual_scaled <= tolerance),
        "residentPass": int(
            bool(data)
            and all(inum(row.get("species_q6_device_resident", 1)) == 1 for row in data)
            and all(inum(row.get("species_q6_host_cell_array_entries", 0)) == 0 for row in data)
            and all(inum(row.get("species_q6_weight_h2d", 0)) == 0 for row in data)
            and all(inum(row.get("species_q6_full_state_download", 0)) == 0 for row in data)
            and all(inum(row.get("species_q6_cpu_fallback", 0)) == 0 for row in data)
        ),
        "mode": data[0].get("mode", "").strip('"') if data else "",
        "avgTotalAfterWarmup": average_after_warmup(totals),
    }


def average_after_warmup(values):
    finite_values = [float(v) for v in values if finite(v)]
    if not finite_values:
        return math.nan
    skip = max(1, min(20, len(finite_values) // 10)) if len(finite_values) > 1 else 0
    sample = finite_values[skip:] or finite_values
    return sum(sample) / len(sample)


def species_mass_audit(output: Path, rel_tolerance: float):
    data = rows(output / "species_runtime_0491h_fix1.csv")
    grouped = defaultdict(list)
    for row in data:
        grouped[inum(row.get("type"), -1)].append(row)
    max_rel = 0.0
    all_finite = bool(data)
    all_registered = bool(data)
    min_counts = {}
    q6_strengths = {}
    for ptype, type_rows in grouped.items():
        initial = fnum(type_rows[0].get("totalMass"), math.nan)
        denom = max(abs(initial), 1.0e-300)
        values = [fnum(row.get("totalMass"), math.nan) for row in type_rows]
        all_finite = all_finite and all(finite(value) for value in values)
        all_registered = all_registered and all(inum(row.get("registered"), 0) == 1 for row in type_rows)
        if finite(initial):
            max_rel = max(max_rel, max((abs(value - initial) / denom for value in values), default=0.0))
        min_counts[ptype] = min((inum(row.get("nFluid"), 0) for row in type_rows), default=0)
        q6_strengths[ptype] = fnum(type_rows[0].get("q6StrengthDeclared"), 0.0)
    return {
        "rows": len(data),
        "types": grouped,
        "maxRelativeDriftAllSamples": max_rel,
        "massPass": int(bool(data) and all_finite and max_rel <= rel_tolerance),
        "registeredPass": int(all_registered),
        "minCounts": min_counts,
        "q6Strengths": q6_strengths,
    }


def cell_composition_audit(output: Path, nx: int, final_step: int, alpha_epsilon: float = 1.0e-14):
    data = rows(output / "species_cell_runtime_0491h_fix1.csv")
    species = species_mass_audit(output, 1.0)
    strengths = species["q6Strengths"]
    by_step_cell = defaultdict(list)
    for row in data:
        by_step_cell[(inum(row.get("step")), inum(row.get("cell")))].append(row)

    steps = sorted({key[0] for key in by_step_cell})
    first_step = steps[0] if steps else -1
    actual_final = final_step if any(step == final_step for step in steps) else (steps[-1] if steps else -1)

    def metrics(step):
        liquid_fraction = {}
        purity = []
        alpha_bars = []
        weights = []
        fallback_cells = 0
        trace_weights = []
        for (row_step, cell), cell_rows in by_step_cell.items():
            if row_step != step:
                continue
            total = max((fnum(row.get("totalCellMass"), 0.0) for row in cell_rows), default=0.0)
            if total <= 0.0:
                continue
            masses = {inum(row.get("type")): fnum(row.get("mass"), 0.0) for row in cell_rows}
            liquid_fraction[cell] = masses.get(1, 0.0) / total
            purity.append(max(masses.values(), default=0.0) / total)
            alpha_bar = sum((mass / total) * strengths.get(ptype, 0.0) for ptype, mass in masses.items())
            alpha_bars.append(alpha_bar)
            if alpha_bar <= alpha_epsilon:
                fallback_cells += 1
                continue
            for ptype, mass in masses.items():
                if mass <= 0.0:
                    continue
                weight = strengths.get(ptype, 0.0) / alpha_bar
                weights.append(weight)
                if ptype == 3:
                    trace_weights.append(weight)
        left = [fraction for cell, fraction in liquid_fraction.items() if cell % nx < nx // 2]
        right = [fraction for cell, fraction in liquid_fraction.items() if cell % nx >= nx // 2]
        left_mean = sum(left) / len(left) if left else math.nan
        right_mean = sum(right) / len(right) if right else math.nan
        return {
            "leftMean": left_mean,
            "rightMean": right_mean,
            "contrast": abs(left_mean - right_mean) if finite(left_mean) and finite(right_mean) else math.nan,
            "meanPurity": sum(purity) / len(purity) if purity else math.nan,
            "alphaBarMin": min(alpha_bars, default=math.nan),
            "alphaBarMax": max(alpha_bars, default=math.nan),
            "weightMin": min(weights, default=math.nan),
            "weightMax": max(weights, default=math.nan),
            "traceWeightMax": max(trace_weights, default=math.nan),
            "fallbackCells": fallback_cells,
        }

    return {
        "rows": len(data),
        "firstStep": first_step,
        "finalStep": actual_final,
        "initial": metrics(first_step),
        "final": metrics(actual_final),
    }


def startup_flags(log_path: Path):
    first = ""
    if log_path.is_file():
        for line in log_path.read_text(errors="replace").splitlines():
            if "[src_mpcd_base] Np=" in line:
                first = line
                break
    required_on = (
        "speciesMassClosure=on",
        "speciesMassClosureCuda=on",
        "speciesPopulationGuard=on",
        "speciesPopulationGuardCuda=on",
        "speciesMixedRefill=on",
        "speciesTransfer=on",
        "speciesTransferCuda=on",
        "speciesCudaResidentFastPath=on",
        "speciesCudaResidentDeposits=on",
        "speciesCudaResidentPool=on",
        "speciesCudaResidentMaintenanceStrict=on",
    )
    return first, int(bool(first) and all(token in first for token in required_on))


def maintenance_audit(output: Path):
    path = output / "cuda_species_resident_maintenance_0490n.csv"
    data = rows(path)
    policy_pass = bool(data) and all(
        inum(row.get("policyHostArrayEntries", 0)) == 0
        and inum(row.get("cellMirrorDownloadBytes", 0)) == 0
        and inum(row.get("cellPolicyDeviceResident", 1)) == 1
        for row in data
    )
    operations = 0
    fast_path = rows(output / "cuda_species_resident_fast_path_0490m.csv")
    for row in fast_path:
        operations += inum(row.get("operations", 0))
    guards = rows(output / "cuda_resampling_population_guard_0297.csv")
    for row in guards:
        operations += inum(row.get("mergeApplied", 0)) + inum(row.get("splitApplied", 0))
    return {
        "maintenanceRows": len(data),
        "devicePolicyPass": int(policy_pass),
        "resamplingOperations": operations,
        "operationsPass": int(operations > 0),
    }


def environment_value(case_dir: Path, key: str) -> str:
    path = case_dir / "logs" / "environment.env"
    if not path.is_file():
        return ""
    prefix = key + "="
    for line in path.read_text(errors="replace").splitlines():
        if line.startswith(prefix):
            return line[len(prefix):].strip()
    return ""


def generic_0296_disabled(case_dir: Path) -> int:
    return int(environment_value(
        case_dir, "MPCD_CUDA_RESAMPLING_MASS_RECONDITION_0296"
    ).lower() in {"0", "false", "off", "no"})


def compatibility_guard_audit(
    case_dir: Path, expected_steps: int, rel_tolerance: float
):
    log_path = case_dir / "logs" / "run.log"
    log_text = log_path.read_text(errors="replace") if log_path.is_file() else ""
    marker = (
        "[0491h-fix1b] suppressed cuda_resampling_mass_recondition_0296: "
        "incompatible with species-aware mass closure (0490d/0490i)"
    )
    output = case_dir / "output"
    mass = species_mass_audit(output, rel_tolerance)
    maintenance = maintenance_audit(output)
    recondition_rows = rows(output / "cuda_resampling_mass_recondition_0296.csv")
    return {
        "requested": int(environment_value(
            case_dir, "MPCD_CUDA_RESAMPLING_MASS_RECONDITION_0296"
        ).lower() in {"1", "true", "on", "yes"}),
        "markerPresent": int(marker in log_text),
        "notApplied": int(len(recondition_rows) == 0),
        "exactStepCount": int(final_step_from_summary(output) == expected_steps),
        "speciesMassPass": mass["massPass"],
        "devicePolicyPass": maintenance["devicePolicyPass"],
        "operationsPass": maintenance["operationsPass"],
        "speciesMassDrift": mass["maxRelativeDriftAllSamples"],
        "resamplingOperations": maintenance["resamplingOperations"],
        "reconditionRows": len(recondition_rows),
    }


def log_bad_markers(root: Path):
    found = []
    for path in root.glob("**/*.log"):
        text = path.read_text(errors="replace").lower()
        for marker in BAD_MARKERS:
            if marker in text:
                found.append(f"{path.relative_to(root)}:{marker}")
        if re.search(r"(^|[^a-z])(?:nan|inf)([^a-z]|$)", text):
            found.append(f"{path.relative_to(root)}:nonfinite_token")
    return sorted(set(found))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True)
    parser.add_argument("--status", required=True)
    parser.add_argument("--profile", required=True)
    parser.add_argument("--matrix-seeds", required=True)
    parser.add_argument("--nx", type=int, required=True)
    parser.add_argument("--matrix-steps", type=int, required=True)
    parser.add_argument("--equivalence-steps", type=int, required=True)
    parser.add_argument("--interface-steps", type=int, required=True)
    parser.add_argument("--trace-steps", type=int, required=True)
    parser.add_argument("--closed-long-steps", type=int, required=True)
    parser.add_argument("--guard-probe-steps", type=int, required=True)
    parser.add_argument("--q6-tolerance", type=float, required=True)
    parser.add_argument("--thermostat-enabled", required=True)
    parser.add_argument("--thermostat-target", type=float, required=True)
    parser.add_argument("--thermostat-tolerance", type=float, required=True)
    parser.add_argument("--state-equivalence-tolerance", type=float, required=True)
    parser.add_argument("--mass-relative-tolerance", type=float, required=True)
    parser.add_argument("--interface-contrast-retention-min", type=float, required=True)
    parser.add_argument("--weighted-overhead-max", type=float, required=True)
    parser.add_argument("--csv", required=True)
    parser.add_argument("--markdown", required=True)
    args = parser.parse_args()

    root = Path(args.root)
    thermostat_enabled = boolish(args.thermostat_enabled)
    status = rows(Path(args.status))
    status_by_case = {row.get("case", ""): row for row in status}
    stage_failures = [row.get("case", "") for row in status if row.get("exit_code") != "0"]
    checks = {"stagesExitZero": int(not stage_failures)}
    metrics = {"stageCount": len(status), "stageFailures": ";".join(stage_failures)}

    # Four paths x requested seeds, with exact lengths and explicit 0490p startup.
    matrix_missing = []
    matrix_length_failures = []
    matrix_q6_failures = []
    matrix_resampling_startup_failures = []
    matrix_maintenance_failures = []
    matrix_generic_0296_failures = []
    matrix_thermostat_failures = []
    matrix_max_q6_residual_abs = 0.0
    matrix_max_q6_residual_scaled = 0.0
    matrix_max_thermostat_error = 0.0
    matrix_modes = ("src", "src-resampling", "src-q6", "src-q6-resampling")
    seeds = [seed for seed in args.matrix_seeds.split() if seed]
    total_matrix_q6_rows = 0
    total_matrix_resampling_operations = 0
    for seed in seeds:
        for mode in matrix_modes:
            case = f"matrix_seed_{seed}_{mode.replace('-', '_')}"
            case_dir = root / case
            output = case_dir / "output"
            if case not in status_by_case or not output.is_dir():
                matrix_missing.append(case)
                continue
            final_step = final_step_from_summary(output)
            if final_step != args.matrix_steps:
                matrix_length_failures.append(f"{case}:{final_step}")
            thermal = thermostat_audit(
                output, args.matrix_steps, thermostat_enabled,
                args.thermostat_target, args.thermostat_tolerance
            )
            matrix_max_thermostat_error = max(matrix_max_thermostat_error, thermal["maxError"])
            if thermal["pass"] != 1:
                matrix_thermostat_failures.append(case)
            if "q6" in mode:
                audit = q6_audit(output, args.matrix_steps, args.q6_tolerance)
                total_matrix_q6_rows += audit["rows"]
                matrix_max_q6_residual_abs = max(matrix_max_q6_residual_abs, audit["maxResidualAbs"])
                matrix_max_q6_residual_scaled = max(matrix_max_q6_residual_scaled, audit["maxResidualScaled"])
                if not all(
                    audit[key] == 1
                    for key in ("present", "exactSteps", "allApplied", "allConverged", "allFinite", "residualPass", "residentPass")
                ) or audit["mode"] != "weighted":
                    matrix_q6_failures.append(case)
            else:
                if (output / "cuda_species_q6_0491.csv").exists():
                    matrix_q6_failures.append(f"{case}:unexpected_q6_audit")
            if "resampling" in mode:
                _, startup_pass = startup_flags(case_dir / "logs" / "run.log")
                maintenance = maintenance_audit(output)
                total_matrix_resampling_operations += maintenance["resamplingOperations"]
                if startup_pass != 1:
                    matrix_resampling_startup_failures.append(case)
                if maintenance["devicePolicyPass"] != 1:
                    matrix_maintenance_failures.append(case)
                if generic_0296_disabled(case_dir) != 1:
                    matrix_generic_0296_failures.append(case)

    checks.update({
        "matrixCasesPresent": int(not matrix_missing),
        "matrixExactStepCounts": int(not matrix_length_failures),
        "matrixQ6AuditsStrict": int(not matrix_q6_failures),
        "matrixSpeciesResampling0490pEnabled": int(not matrix_resampling_startup_failures),
        "matrixDeviceCellPolicyStrict": int(not matrix_maintenance_failures),
        "matrixGeneric0296Disabled": int(not matrix_generic_0296_failures),
        "matrixThermostatStrict": int(not matrix_thermostat_failures),
        "matrixResamplingExercised": int(total_matrix_resampling_operations > 0),
    })
    metrics.update({
        "matrixExpectedCases": len(seeds) * len(matrix_modes),
        "matrixMissing": ";".join(matrix_missing),
        "matrixLengthFailures": ";".join(matrix_length_failures),
        "matrixQ6Failures": ";".join(matrix_q6_failures),
        "matrixResamplingStartupFailures": ";".join(matrix_resampling_startup_failures),
        "matrixMaintenanceFailures": ";".join(matrix_maintenance_failures),
        "matrixGeneric0296Failures": ";".join(matrix_generic_0296_failures),
        "matrixThermostatFailures": ";".join(matrix_thermostat_failures),
        "matrixQ6Rows": total_matrix_q6_rows,
        "matrixMaxQ6ResidualAbs": matrix_max_q6_residual_abs,
        "matrixMaxQ6ResidualScaled": matrix_max_q6_residual_scaled,
        "matrixMaxThermostatError": matrix_max_thermostat_error,
        "matrixResamplingOperations": total_matrix_resampling_operations,
    })

    # Deliberate compatibility probe: request legacy 0296 with 0490i.
    # The runtime guard must suppress 0296 rather than allowing type-to-type mass
    # transfer or aborting an existing production runner.
    guard_case = root / "mass_recondition_compatibility_guard"
    guard_audit = compatibility_guard_audit(
        guard_case, args.guard_probe_steps, args.mass_relative_tolerance
    )
    checks.update({
        "generic0296GuardRequested": guard_audit["requested"],
        "generic0296GuardMarkerPresent": guard_audit["markerPresent"],
        "generic0296GuardNotApplied": guard_audit["notApplied"],
        "generic0296GuardExactStepCount": guard_audit["exactStepCount"],
        "generic0296GuardSpeciesMassConserved": guard_audit["speciesMassPass"],
        "generic0296GuardDevicePolicyStrict": guard_audit["devicePolicyPass"],
        "generic0296GuardResamplingExercised": guard_audit["operationsPass"],
    })
    metrics.update({
        "generic0296GuardSpeciesMassDrift": guard_audit["speciesMassDrift"],
        "generic0296GuardResamplingOperations": guard_audit["resamplingOperations"],
        "generic0296GuardDiagnosticRows": guard_audit["reconditionRows"],
    })

    # Historical/common trajectory equivalence.
    legacy_state = root / "legacy_q6" / "output" / f"state_step_{args.equivalence_steps:08d}.smpcd"
    common_state = root / "common_q6" / "output" / f"state_step_{args.equivalence_steps:08d}.smpcd"
    try:
        equivalence = compare_states(legacy_state, common_state, args.state_equivalence_tolerance)
    except Exception as exc:  # Preserve a useful failure report.
        equivalence = {
            "stateShaExact": 0, "stateParticleCountEqual": 0, "stateTypeExact": 0,
            "stateRoleExact": 0, "stateMassExact": 0, "stateStructureExact": 0,
            "stateMaxPositionError": math.inf, "stateMaxVelocityError": math.inf,
            "statePositionPass": 0, "stateVelocityPass": 0,
            "stateTrajectoryEquivalent": 0,
            "stateEquivalenceTolerance": args.state_equivalence_tolerance,
            "statePositionErrorOverTolerance": math.inf,
            "stateVelocityErrorOverTolerance": math.inf,
            "stateEquivalent": 0, "stateCompareError": str(exc),
        }
    checks["legacyCommonStructureExact"] = equivalence["stateStructureExact"]
    checks["legacyCommonTrajectoryEquivalent"] = equivalence["stateTrajectoryEquivalent"]
    checks["legacyCommonStateEquivalent"] = equivalence["stateEquivalent"]
    metrics.update(equivalence)

    common_audit = q6_audit(root / "common_q6" / "output", args.equivalence_steps, args.q6_tolerance)
    weighted_audit = q6_audit(root / "weighted_q6" / "output", args.equivalence_steps, args.q6_tolerance)
    common_thermal = thermostat_audit(
        root / "common_q6" / "output", args.equivalence_steps, thermostat_enabled,
        args.thermostat_target, args.thermostat_tolerance
    )
    weighted_thermal = thermostat_audit(
        root / "weighted_q6" / "output", args.equivalence_steps, thermostat_enabled,
        args.thermostat_target, args.thermostat_tolerance
    )
    checks["commonExactQ6Length"] = int(common_audit["exactSteps"] == 1 and common_audit["mode"] == "common")
    checks["weightedExactQ6Length"] = int(weighted_audit["exactSteps"] == 1 and weighted_audit["mode"] == "weighted")
    checks["pairedThermostatStrict"] = int(common_thermal["pass"] == 1 and weighted_thermal["pass"] == 1)
    overhead = (
        weighted_audit["avgTotalAfterWarmup"] / common_audit["avgTotalAfterWarmup"] - 1.0
        if finite(common_audit["avgTotalAfterWarmup"])
        and common_audit["avgTotalAfterWarmup"] > 0.0
        and finite(weighted_audit["avgTotalAfterWarmup"])
        else math.inf
    )
    checks["pairedWeightedOverheadBounded"] = int(finite(overhead) and overhead <= args.weighted_overhead_max)
    metrics.update({
        "commonAvgQ6Seconds": common_audit["avgTotalAfterWarmup"],
        "weightedAvgQ6Seconds": weighted_audit["avgTotalAfterWarmup"],
        "pairedWeightedOverhead": overhead,
        "pairedWeightedOverheadLimit": args.weighted_overhead_max,
        "commonMaxQ6ResidualAbs": common_audit["maxResidualAbs"],
        "commonMaxQ6ResidualScaled": common_audit["maxResidualScaled"],
        "weightedMaxQ6ResidualAbs": weighted_audit["maxResidualAbs"],
        "weightedMaxQ6ResidualScaled": weighted_audit["maxResidualScaled"],
        "pairedMaxThermostatError": max(common_thermal["maxError"], weighted_thermal["maxError"]),
    })

    # Interface contrast and reconstructed alpha-bar/weights.
    interface_output = root / "persistent_interface" / "output"
    interface_cells = cell_composition_audit(interface_output, nx=args.nx, final_step=args.interface_steps)
    initial_contrast = interface_cells["initial"]["contrast"]
    final_contrast = interface_cells["final"]["contrast"]
    contrast_retention = final_contrast / initial_contrast if finite(initial_contrast) and initial_contrast > 0.0 else 0.0
    interface_thermal = thermostat_audit(
        interface_output, args.interface_steps, thermostat_enabled,
        args.thermostat_target, args.thermostat_tolerance
    )
    checks["interfaceCellDiagnosticsPresent"] = int(interface_cells["rows"] > 0)
    checks["interfaceFinalStepObserved"] = int(interface_cells["finalStep"] == args.interface_steps)
    checks["interfaceContrastRetained"] = int(contrast_retention >= args.interface_contrast_retention_min)
    checks["interfaceThermostatStrict"] = interface_thermal["pass"]
    metrics.update({
        "interfaceInitialContrast": initial_contrast,
        "interfaceFinalContrast": final_contrast,
        "interfaceContrastRetention": contrast_retention,
        "interfaceContrastRetentionMin": args.interface_contrast_retention_min,
        "interfaceFinalMeanPurity": interface_cells["final"]["meanPurity"],
        "interfaceAlphaBarMin": interface_cells["final"]["alphaBarMin"],
        "interfaceAlphaBarMax": interface_cells["final"]["alphaBarMax"],
        "interfaceWeightMin": interface_cells["final"]["weightMin"],
        "interfaceWeightMax": interface_cells["final"]["weightMax"],
        "interfaceFallbackCells": interface_cells["final"]["fallbackCells"],
        "interfaceMaxThermostatError": interface_thermal["maxError"],
    })

    # True trace species with nonzero Q6 strength.
    trace_output = root / "trace_species" / "output"
    trace_mass = species_mass_audit(trace_output, args.mass_relative_tolerance)
    trace_rows = trace_mass["types"].get(3, [])
    if trace_rows:
        step0 = min(inum(row.get("step")) for row in trace_rows)
        total_by_step = defaultdict(float)
        for ptype_rows in trace_mass["types"].values():
            for row in ptype_rows:
                total_by_step[inum(row.get("step"))] += fnum(row.get("totalMass"), 0.0)
        trace_initial = next(row for row in trace_rows if inum(row.get("step")) == step0)
        trace_fraction = fnum(trace_initial.get("totalMass"), 0.0) / max(total_by_step[step0], 1.0e-300)
        trace_count_min = min(inum(row.get("nFluid"), 0) for row in trace_rows)
        trace_strength = fnum(trace_initial.get("q6StrengthDeclared"), 0.0)
    else:
        trace_fraction, trace_count_min, trace_strength = math.inf, 0, 0.0
    trace_cells = cell_composition_audit(trace_output, nx=args.nx, final_step=args.trace_steps)
    trace_weight_max = trace_cells["final"]["traceWeightMax"]
    trace_thermal = thermostat_audit(
        trace_output, args.trace_steps, thermostat_enabled,
        args.thermostat_target, args.thermostat_tolerance
    )
    checks.update({
        "traceMassFractionAtMost1e6": int(0.0 < trace_fraction <= 1.0e-6),
        "traceMassConservedAllSamples": trace_mass["massPass"],
        "traceParticleRetained": int(trace_count_min == 1),
        "traceQ6StrengthNonzero": int(trace_strength > 0.0),
        "traceWeightedCorrectionExercised": int(finite(trace_weight_max) and trace_weight_max > 1.0),
        "traceThermostatStrict": trace_thermal["pass"],
    })
    metrics.update({
        "traceInitialMassFraction": trace_fraction,
        "traceCountMin": trace_count_min,
        "traceQ6Strength": trace_strength,
        "traceWeightMax": trace_weight_max,
        "traceAlphaBarMin": trace_cells["final"]["alphaBarMin"],
        "traceAlphaBarMax": trace_cells["final"]["alphaBarMax"],
        "traceMassMaxRelativeDrift": trace_mass["maxRelativeDriftAllSamples"],
        "traceMaxThermostatError": trace_thermal["maxError"],
    })

    # Closed 10k combined path with full 0490p and exact per-species mass audit.
    closed_dir = root / "closed_long_src_resampling_q6"
    closed_output = closed_dir / "output"
    closed_q6 = q6_audit(closed_output, args.closed_long_steps, args.q6_tolerance)
    closed_mass = species_mass_audit(closed_output, args.mass_relative_tolerance)
    _, closed_startup = startup_flags(closed_dir / "logs" / "run.log")
    closed_maintenance = maintenance_audit(closed_output)
    closed_thermal = thermostat_audit(
        closed_output, args.closed_long_steps, thermostat_enabled,
        args.thermostat_target, args.thermostat_tolerance
    )
    checks.update({
        "closedLongExactStepCount": int(final_step_from_summary(closed_output) == args.closed_long_steps),
        "closedLongQ6Strict": int(all(
            closed_q6[key] == 1
            for key in ("present", "exactSteps", "allApplied", "allConverged", "allFinite", "residualPass", "residentPass")
        )),
        "closedLongSpeciesMassConserved": closed_mass["massPass"],
        "closedLong0490pEnabled": closed_startup,
        "closedLongDevicePolicyStrict": closed_maintenance["devicePolicyPass"],
        "closedLongGeneric0296Disabled": generic_0296_disabled(closed_dir),
        "closedLongThermostatStrict": closed_thermal["pass"],
        "closedLongResamplingExercised": closed_maintenance["operationsPass"],
    })
    metrics.update({
        "closedLongQ6Rows": closed_q6["rows"],
        "closedLongMaxQ6ResidualAbs": closed_q6["maxResidualAbs"],
        "closedLongMaxQ6ResidualScaled": closed_q6["maxResidualScaled"],
        "closedLongMaxThermostatError": closed_thermal["maxError"],
        "closedLongSpeciesMassMaxRelativeDrift": closed_mass["maxRelativeDriftAllSamples"],
        "closedLongMaintenanceRows": closed_maintenance["maintenanceRows"],
        "closedLongResamplingOperations": closed_maintenance["resamplingOperations"],
    })

    bad_markers = log_bad_markers(root)
    checks["noBadLogMarkers"] = int(not bad_markers)
    metrics["badLogMarkers"] = ";".join(bad_markers)

    passed = all(value == 1 for value in checks.values())
    result = {"pass": int(passed), "profile": args.profile, **checks, **metrics}

    csv_path = Path(args.csv)
    csv_path.parent.mkdir(parents=True, exist_ok=True)
    with csv_path.open("w", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(result))
        writer.writeheader()
        writer.writerow(result)

    lines = [
        "# 0491h-fix1 deep species-Q6 qualification",
        "",
        f"Result: **{'PASS' if passed else 'FAIL'}**",
        f"Profile: `{args.profile}`",
        "",
        "## Qualification checks",
        "",
        "| Check | Value |",
        "| --- | ---: |",
    ]
    for key, value in checks.items():
        lines.append(f"| {key} | {value} |")
    lines.extend([
        "",
        "## Key metrics",
        "",
        "| Metric | Value |",
        "| --- | ---: |",
        f"| Matrix cases | {metrics['matrixExpectedCases']} |",
        f"| Matrix Q6 rows | {metrics['matrixQ6Rows']} |",
        f"| Matrix max Q6 residual (absolute) | {metrics['matrixMaxQ6ResidualAbs']} |",
        f"| Matrix max Q6 residual (scaled) | {metrics['matrixMaxQ6ResidualScaled']} |",
        f"| Matrix max thermostat error | {metrics['matrixMaxThermostatError']} |",
        f"| Matrix resampling operations | {metrics['matrixResamplingOperations']} |",
        f"| 0296 guard resampling operations | {metrics['generic0296GuardResamplingOperations']} |",
        f"| 0296 guard diagnostic rows | {metrics['generic0296GuardDiagnosticRows']} |",
        f"| 0296 guard species mass drift | {metrics['generic0296GuardSpeciesMassDrift']} |",
        f"| Legacy/common state SHA exact | {metrics['stateShaExact']} |",
        f"| Legacy/common structure exact | {metrics['stateStructureExact']} |",
        f"| Legacy/common equivalence tolerance | {metrics['stateEquivalenceTolerance']} |",
        f"| Legacy/common max position error | {metrics['stateMaxPositionError']} |",
        f"| Legacy/common position error / tolerance | {metrics['statePositionErrorOverTolerance']} |",
        f"| Legacy/common max velocity error | {metrics['stateMaxVelocityError']} |",
        f"| Legacy/common velocity error / tolerance | {metrics['stateVelocityErrorOverTolerance']} |",
        f"| Paired weighted overhead | {metrics['pairedWeightedOverhead']} |",
        f"| Common max Q6 residual (scaled) | {metrics['commonMaxQ6ResidualScaled']} |",
        f"| Weighted max Q6 residual (scaled) | {metrics['weightedMaxQ6ResidualScaled']} |",
        f"| Paired max thermostat error | {metrics['pairedMaxThermostatError']} |",
        f"| Interface contrast retention | {metrics['interfaceContrastRetention']} |",
        f"| Interface final mean purity | {metrics['interfaceFinalMeanPurity']} |",
        f"| Trace initial mass fraction | {metrics['traceInitialMassFraction']} |",
        f"| Trace maximum reconstructed weight | {metrics['traceWeightMax']} |",
        f"| Closed-long Q6 rows | {metrics['closedLongQ6Rows']} |",
        f"| Closed-long max Q6 residual (absolute) | {metrics['closedLongMaxQ6ResidualAbs']} |",
        f"| Closed-long max Q6 residual (scaled) | {metrics['closedLongMaxQ6ResidualScaled']} |",
        f"| Closed-long max thermostat error | {metrics['closedLongMaxThermostatError']} |",
        f"| Closed-long species mass drift | {metrics['closedLongSpeciesMassMaxRelativeDrift']} |",
        f"| Closed-long resampling operations | {metrics['closedLongResamplingOperations']} |",
    ])
    Path(args.markdown).write_text("\n".join(lines) + "\n")

    print(
        f"[0491h-fix1-summary] {'PASS' if passed else 'FAIL'} "
        f"matrix={metrics['matrixExpectedCases']} closed_steps={args.closed_long_steps} "
        f"trace_fraction={metrics['traceInitialMassFraction']:.6g} "
        f"interface_retention={metrics['interfaceContrastRetention']:.6g}"
    )
    if not passed:
        failed = [key for key, value in checks.items() if value != 1]
        print("[0491h-fix1-summary] failed_checks=" + ",".join(failed))
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
