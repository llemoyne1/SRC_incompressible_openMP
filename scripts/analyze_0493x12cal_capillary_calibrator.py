#!/usr/bin/env python3
"""0493x12cal production capillary-property calibrator.

Measures the effective dynamic surface tension from the dispersion of
small-amplitude liquid/vacuum capillary waves:

    omega^2 = (sigma_eff / rho_ref) k^3 tanh(k H)

No pandas/scipy dependency.  FIX2 reconstructs interface displacement from\nlinear column mass (no cellwise clipping) and averages signed equal-mode\nthermal realizations before the production fit.  The fit uses an early,\npre-declared high-SNR window inherited from the validated x11c analysis.
"""
from __future__ import annotations

import argparse
import csv
import json
import math
import statistics
import sys
from array import array
from pathlib import Path


def mean(values):
    return statistics.fmean(values) if values else math.nan


def stdev(values):
    return statistics.stdev(values) if len(values) > 1 else 0.0


def finite_or_none(value):
    if isinstance(value, (str, int, bool)):
        return value
    return value if isinstance(value, float) and math.isfinite(value) else None


def read_csv(path: Path):
    if not path.exists():
        raise SystemExit(f"[0493x12cal] missing {path}")
    with path.open(newline="") as stream:
        rows = list(csv.DictReader(stream))
    if not rows:
        raise SystemExit(f"[0493x12cal] empty {path}")
    return rows


def write_csv(path: Path, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    keys = []
    for row in rows:
        for key in row:
            if key not in keys:
                keys.append(key)
    with path.open("w", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=keys)
        writer.writeheader()
        writer.writerows(rows)


def read_f32(path: Path, count: int):
    values = array("f")
    with path.open("rb") as stream:
        values.fromfile(stream, count)
    if len(values) != count:
        raise RuntimeError(f"{path}: expected {count} f32 values, got {len(values)}")
    if sys.byteorder == "big":
        values.byteswap()
    return values


def locate_frames(case_dir: Path):
    timelines = sorted((case_dir / "output" / "recordings").glob("*/timeline.csv"))
    if not timelines:
        raise RuntimeError(f"{case_dir}: no recording timeline.csv")
    by_step = {}
    for timeline in timelines:
        for row in read_csv(timeline):
            field = row.get("field", "")
            # Current recorder labels the mass field as rho; accept the explicit
            # mass spelling too so the analyzer remains forward-compatible.
            if field not in ("rho", "mass"):
                continue
            step = int(row["step"])
            by_step[step] = (
                float(row["time"]),
                int(row["nx"]),
                int(row["ny"]),
                timeline.parent / row["file"],
            )
    if not by_step:
        raise RuntimeError(f"{case_dir}: no mass/rho frames in recorder timelines")
    return [(step,) + by_step[step] for step in sorted(by_step)]


def column_mass_heights(data, nx, ny, dy, reference_cell_mass):
    """Return the linear mass-equivalent liquid height of every x-column.

    For an incompressible liquid/vacuum calibration,
        H_i = dy/(gamma*m_p) * sum_j m_ij.
    This is intentionally *not* clipped cell-by-cell.  Clipping m/(gamma*m_p)
    to [0,1] biases thermal bulk fluctuations downward and aliases bulk-density
    noise into a false interface displacement.
    """
    if reference_cell_mass <= 0:
        raise RuntimeError("reference_cell_mass must be positive")
    heights = [0.0] * nx
    total_mass = 0.0
    scale = dy / reference_cell_mass
    for iy in range(ny):
        offset = iy * nx
        for ix in range(nx):
            cell_mass = float(data[offset + ix])
            total_mass += cell_mass
            heights[ix] += cell_mass * scale
    return heights, total_mass


def mode_series(case):
    case_dir = Path(case["run_dir"])
    nx = int(case["nx"])
    ny = int(case["ny"])
    lx = float(case["Lx"])
    ly = float(case["Ly"])
    gamma = float(case["gamma"])
    mass = float(case["liquid_mass"])
    mode = int(case["mode"])
    k = 2.0 * math.pi * mode / lx
    dy = ly / ny
    reference_cell_mass = gamma * mass

    result = []
    for step, time, fx, fy, frame_path in locate_frames(case_dir):
        if (fx, fy) != (nx, ny):
            raise RuntimeError(
                f"{frame_path}: recorder grid {(fx, fy)} != simulation {(nx, ny)}"
            )
        data = read_f32(frame_path, nx * ny)
        heights, total_mass = column_mass_heights(
            data, nx, ny, dy, reference_cell_mass
        )

        cosine = 0.0
        sine = 0.0
        for ix, height in enumerate(heights):
            x = (ix + 0.5) * lx / nx
            cosine += height * math.cos(k * x)
            sine += height * math.sin(k * x)
        cosine *= 2.0 / nx
        sine *= 2.0 / nx
        result.append(
            {
                "step": step,
                "time": time,
                "modeCosine": cosine,
                "modeSine": sine,
                "modePrimary": cosine,
                "modeAmplitude": math.hypot(cosine, sine),
                "meanHeight": mean(heights),
                "massEquivalentMeanHeight": total_mass
                * dy
                / (nx * reference_cell_mass),
                "totalRecordedMass": total_mass,
                "heightEstimator": "column_mass_linear_no_clip",
            }
        )
    return result


def ensemble_signed_trace(traces):
    """Average signed Fourier quadratures across synchronized seeds before fit."""
    if not traces:
        raise RuntimeError("cannot ensemble-average zero traces")
    indexed = [{int(row["step"]): row for row in trace} for trace in traces]
    common_steps = sorted(set.intersection(*(set(item) for item in indexed)))
    if len(common_steps) < 12:
        raise RuntimeError("not enough common recorder steps for ensemble fit")

    result = []
    for step in common_steps:
        rows = [item[step] for item in indexed]
        times = [float(row["time"]) for row in rows]
        if max(times) - min(times) > 1e-12 * max(1.0, max(abs(t) for t in times)):
            raise RuntimeError(f"replicate time mismatch at step {step}")
        cosine = mean([float(row["modeCosine"]) for row in rows])
        sine = mean([float(row["modeSine"]) for row in rows])
        result.append(
            {
                "step": step,
                "time": mean(times),
                "modeCosine": cosine,
                "modeSine": sine,
                "modePrimary": cosine,
                "modeAmplitude": math.hypot(cosine, sine),
                "meanHeight": mean([float(row["meanHeight"]) for row in rows]),
                "massEquivalentMeanHeight": mean(
                    [float(row["massEquivalentMeanHeight"]) for row in rows]
                ),
                "totalRecordedMass": mean(
                    [float(row["totalRecordedMass"]) for row in rows]
                ),
                "replicates": len(rows),
                "heightEstimator": "column_mass_linear_no_clip",
            }
        )
    return result


def solve3(matrix, rhs):
    aug = [list(map(float, row)) + [float(b)] for row, b in zip(matrix, rhs)]
    for i in range(3):
        pivot = max(range(i, 3), key=lambda row: abs(aug[row][i]))
        if abs(aug[pivot][i]) < 1e-18:
            return None
        aug[i], aug[pivot] = aug[pivot], aug[i]
        q = aug[i][i]
        for j in range(i, 4):
            aug[i][j] /= q
        for row in range(3):
            if row == i:
                continue
            q = aug[row][i]
            for j in range(i, 4):
                aug[row][j] -= q * aug[i][j]
    return [aug[i][3] for i in range(3)]


def linear_fit(t, y, omega, beta):
    columns = []
    for tt in t:
        decay = math.exp(-beta * tt)
        columns.append(
            (
                decay * math.cos(omega * tt),
                decay * math.sin(omega * tt),
                1.0,
            )
        )
    matrix = [
        [sum(column[i] * column[j] for column in columns) for j in range(3)]
        for i in range(3)
    ]
    rhs = [sum(column[i] * yy for column, yy in zip(columns, y)) for i in range(3)]
    coeff = solve3(matrix, rhs)
    if coeff is None:
        return None
    prediction = [
        coeff[0] * column[0] + coeff[1] * column[1] + coeff[2]
        for column in columns
    ]
    sse = sum((yy - pp) ** 2 for yy, pp in zip(y, prediction))
    ym = mean(y)
    sst = sum((yy - ym) ** 2 for yy in y)
    r2 = 1.0 - sse / sst if sst > 0 else 0.0
    return sse, r2, coeff, prediction


def fit_damped(t_absolute, y, omega0):
    if len(t_absolute) < 12:
        raise RuntimeError("not enough points for damped-wave fit")
    t0 = t_absolute[0]
    t = [value - t0 for value in t_absolute]

    omega_low = 0.60 * omega0
    omega_high = 1.40 * omega0
    beta_low = 0.0
    beta_high = min(2.5 * omega0, 10.0)
    best = None

    for refinement in range(3):
        n_omega = 121 if refinement == 0 else 81
        n_beta = 61 if refinement == 0 else 41
        for iw in range(n_omega):
            omega = omega_low + (omega_high - omega_low) * iw / max(1, n_omega - 1)
            for ib in range(n_beta):
                beta = beta_low + (beta_high - beta_low) * ib / max(1, n_beta - 1)
                fit = linear_fit(t, y, omega, beta)
                if fit is None:
                    continue
                candidate = (fit[0], omega, beta, fit[1], fit[2], fit[3])
                if best is None or candidate[0] < best[0]:
                    best = candidate
        if best is None:
            raise RuntimeError("damped-wave fit failed")
        _, omega, beta, _, _, _ = best
        domega = (omega_high - omega_low) / max(1, n_omega - 1) * 3.0
        dbeta = (beta_high - beta_low) / max(1, n_beta - 1) * 3.0
        omega_low = max(0.10 * omega0, omega - domega)
        omega_high = omega + domega
        beta_low = max(0.0, beta - dbeta)
        beta_high = beta + dbeta

    return best


def sigma_from_omega(rho, omega, k, depth):
    denominator = k ** 3 * math.tanh(k * depth)
    if rho <= 0 or omega <= 0 or denominator <= 0:
        return math.nan
    return rho * omega * omega / denominator


def fit_window(trace, omega0, periods):
    theoretical_period = 2.0 * math.pi / omega0
    t_start = float(trace[0]["time"])
    t_end = t_start + periods * theoretical_period
    selected = [row for row in trace if float(row["time"]) <= t_end + 1e-14]
    if len(selected) < 12:
        raise RuntimeError(
            f"only {len(selected)} frames in {periods:g} theoretical periods"
        )
    times = [float(row["time"]) for row in selected]
    values = [float(row["modePrimary"]) for row in selected]
    sse, omega, beta, r2, coeff, prediction = fit_damped(times, values, omega0)
    amplitude = math.hypot(coeff[0], coeff[1])
    return {
        "omega": omega,
        "beta": beta,
        "r2": r2,
        "frames": len(selected),
        "timeStart": times[0],
        "timeEnd": times[-1],
        "amplitude": amplitude,
        "prediction": prediction,
    }


def slope_through_origin(pairs):
    denominator = sum(x * x for x, _ in pairs)
    return sum(x * y for x, y in pairs) / denominator if denominator else math.nan


def case_status(row):
    r2 = row["fitR2"]
    sensitivity = row["windowGainStd"]
    ratio = row["omegaFitOverTheory"]
    frames = row["fitFrames"]
    if (
        math.isfinite(r2)
        and r2 >= 0.98
        and math.isfinite(sensitivity)
        and sensitivity <= 0.04
        and 0.62 <= ratio <= 1.38
        and frames >= 30
    ):
        return "PASS"
    if (
        math.isfinite(r2)
        and r2 >= 0.90
        and math.isfinite(sensitivity)
        and sensitivity <= 0.10
        and 0.45 <= ratio <= 1.55
        and frames >= 20
    ):
        return "REVIEW"
    return "INVALID"


def parse_transport_viscosity(path_text):
    if not path_text:
        return math.nan
    path = Path(path_text)
    if not path.exists():
        raise SystemExit(f"[0493x12cal] transport calibration not found: {path}")
    if path.suffix.lower() == ".json":
        data = json.loads(path.read_text())
        value = data.get("viscosityKinematic")
        return float(value) if value is not None else math.nan
    rows = read_csv(path)
    value = rows[0].get("viscosityKinematic", "")
    return float(value) if value else math.nan


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--fit-periods", type=float, default=1.0)
    parser.add_argument("--sensitivity-periods", default="0.75,1.0,1.25")
    parser.add_argument("--characteristic-U", type=float, default=-1.0)
    parser.add_argument("--characteristic-D", type=float, default=-1.0)
    parser.add_argument("--kinematic-viscosity", type=float, default=-1.0)
    parser.add_argument("--transport-calibration", default="")
    parser.add_argument("--gravity", type=float, default=0.0)
    args = parser.parse_args()

    if args.fit_periods <= 0:
        raise SystemExit("--fit-periods must be positive")
    sensitivity_periods = [
        float(value)
        for value in args.sensitivity_periods.split(",")
        if value.strip()
    ]
    if not sensitivity_periods or any(value <= 0 for value in sensitivity_periods):
        raise SystemExit("invalid --sensitivity-periods")

    manifest = read_csv(args.manifest)
    args.output_dir.mkdir(parents=True, exist_ok=True)
    trace_dir = args.output_dir / "traces"
    trace_dir.mkdir(parents=True, exist_ok=True)

    declared_sigmas = {float(row["sigma_declared"]) for row in manifest}
    if len(declared_sigmas) != 1:
        raise SystemExit(
            "[0493x12cal] production calibrator expects one SIGMA_DECLARED per manifest"
        )
    sigma_declared = next(iter(declared_sigmas))

    case_rows = []
    traces_by_case = {}
    manifest_by_case = {}

    # Per-case fits remain diagnostic.  The production estimator is built below
    # from signed seed-ensemble traces, matching the transport-calibrator logic.
    for case in manifest:
        lx = float(case["Lx"])
        ly = float(case["Ly"])
        nx = int(case["nx"])
        ny = int(case["ny"])
        h = float(case["h"])
        gamma = float(case["gamma"])
        particle_mass = float(case["liquid_mass"])
        depth = float(case["mean_height"])
        mode = int(case["mode"])
        k = 2.0 * math.pi * mode / lx
        rho = gamma * particle_mass / (h * h)
        omega_theory = math.sqrt(
            (sigma_declared / rho) * k ** 3 * math.tanh(k * depth)
        )

        trace = mode_series(case)
        traces_by_case[case["case"]] = trace
        manifest_by_case[case["case"]] = case
        trace_path = trace_dir / f"{case['case']}_trace.csv"
        write_csv(trace_path, trace)

        primary = fit_window(trace, omega_theory, args.fit_periods)
        gains = []
        for periods in sensitivity_periods:
            try:
                fit = fit_window(trace, omega_theory, periods)
                gains.append((fit["omega"] / omega_theory) ** 2)
            except Exception:
                pass

        gain = (primary["omega"] / omega_theory) ** 2
        sigma_effective = sigma_from_omega(rho, primary["omega"], k, depth)
        late_count = max(8, int(math.ceil(0.25 * len(trace))))
        late = [float(row["modePrimary"]) for row in trace[-late_count:]]
        late_noise_rms = math.sqrt(mean([value * value for value in late]))
        snr_start = (
            primary["amplitude"] / late_noise_rms
            if late_noise_rms > 0
            else math.inf
        )
        mean_height_values = [float(row["meanHeight"]) for row in trace]
        mass_height_values = [
            float(row["massEquivalentMeanHeight"]) for row in trace
        ]

        row = {
            "case": case["case"],
            "mode": mode,
            "seed": int(case["seed"]),
            "sigmaDeclared": sigma_declared,
            "sigmaEffectiveRaw": sigma_effective,
            "surfaceTensionGainRaw": gain,
            "rhoReference": rho,
            "wavenumber": k,
            "wavelength": lx / mode,
            "wavelengthCells": nx / mode,
            "meanDepth": depth,
            "omegaTheoryDeclared": omega_theory,
            "omegaFit": primary["omega"],
            "omegaFitOverTheory": primary["omega"] / omega_theory,
            "betaFit": primary["beta"],
            "fitR2": primary["r2"],
            "fitFrames": primary["frames"],
            "fitPeriods": args.fit_periods,
            "fitAmplitude": primary["amplitude"],
            "lateNoiseRms": late_noise_rms,
            "snrStartProxy": snr_start,
            "windowGainMean": mean(gains),
            "windowGainStd": stdev(gains),
            "windowGainMin": min(gains) if gains else math.nan,
            "windowGainMax": max(gains) if gains else math.nan,
            "sensitivityWindows": len(gains),
            "meanHeightMean": mean(mean_height_values),
            "meanHeightStd": stdev(mean_height_values),
            "massEquivalentMeanHeightMean": mean(mass_height_values),
            "massEquivalentMeanHeightStd": stdev(mass_height_values),
            "heightEstimator": "column_mass_linear_no_clip",
            "minRadiusCells": float(case["min_radius_cells"]),
            "calibrationPath": case["calibration_path"],
            "x12aRadiusCells": float(case["x12a_radius_cells"]),
            "trace": str(trace_path),
        }
        row["status"] = case_status(row)
        case_rows.append(row)
        print(
            f"[0493x12cal] case={row['case']} status={row['status']} "
            f"sigmaEff={sigma_effective:.9g} gain={gain:.6g} "
            f"omega={primary['omega']:.8g} R2={primary['fitR2'] if 'fitR2' in primary else primary['r2']:.6f} "
            f"windowStd={row['windowGainStd']:.4g}"
        )

    write_csv(args.output_dir / "capillary_calibration_cases_0493x12cal.csv", case_rows)

    requested_modes = sorted({row["mode"] for row in case_rows})
    grouped = []

    # Primary production estimator: align equal-mode realizations, average the
    # signed cosine/sine quadratures first, then fit the ensemble signal.
    for mode in requested_modes:
        case_names = [
            case["case"] for case in manifest if int(case["mode"]) == mode
        ]
        mode_traces = [traces_by_case[name] for name in case_names]
        ensemble = ensemble_signed_trace(mode_traces)
        ensemble_path = trace_dir / f"mode_n{mode}_ensemble_trace.csv"
        write_csv(ensemble_path, ensemble)

        representative = manifest_by_case[case_names[0]]
        lx = float(representative["Lx"])
        h = float(representative["h"])
        gamma = float(representative["gamma"])
        particle_mass = float(representative["liquid_mass"])
        depth = float(representative["mean_height"])
        nx = int(representative["nx"])
        rho = gamma * particle_mass / (h * h)
        k = 2.0 * math.pi * mode / lx
        omega_theory = math.sqrt(
            (sigma_declared / rho) * k ** 3 * math.tanh(k * depth)
        )

        primary = fit_window(ensemble, omega_theory, args.fit_periods)
        sensitivity_gains = []
        for periods in sensitivity_periods:
            try:
                fit = fit_window(ensemble, omega_theory, periods)
                sensitivity_gains.append((fit["omega"] / omega_theory) ** 2)
            except Exception:
                pass

        gain = (primary["omega"] / omega_theory) ** 2
        sigma_effective = sigma_from_omega(rho, primary["omega"], k, depth)
        late_count = max(8, int(math.ceil(0.25 * len(ensemble))))
        late = [float(row["modePrimary"]) for row in ensemble[-late_count:]]
        late_noise_rms = math.sqrt(mean([value * value for value in late]))
        snr_start = (
            primary["amplitude"] / late_noise_rms
            if late_noise_rms > 0
            else math.inf
        )

        seed_rows = [row for row in case_rows if row["mode"] == mode]
        seed_gains = [row["surfaceTensionGainRaw"] for row in seed_rows]
        seed_sigmas = [row["sigmaEffectiveRaw"] for row in seed_rows]

        mode_row = {
            "mode": mode,
            "replicates": len(case_names),
            "sigmaDeclared": sigma_declared,
            "sigmaEffectiveEnsemble": sigma_effective,
            "surfaceTensionGainEnsemble": gain,
            "rhoReference": rho,
            "wavenumber": k,
            "wavelength": lx / mode,
            "wavelengthCells": nx / mode,
            "omegaTheoryDeclared": omega_theory,
            "omegaFitEnsemble": primary["omega"],
            "omegaFitOverTheoryEnsemble": primary["omega"] / omega_theory,
            "betaFitEnsemble": primary["beta"],
            "fitR2Ensemble": primary["r2"],
            "fitFramesEnsemble": primary["frames"],
            "fitAmplitudeEnsemble": primary["amplitude"],
            "lateNoiseRmsEnsemble": late_noise_rms,
            "snrStartProxyEnsemble": snr_start,
            "windowGainMean": mean(sensitivity_gains),
            "windowGainStd": stdev(sensitivity_gains),
            "windowGainMin": min(sensitivity_gains)
            if sensitivity_gains
            else math.nan,
            "windowGainMax": max(sensitivity_gains)
            if sensitivity_gains
            else math.nan,
            "seedGainMean": mean(seed_gains),
            "seedGainStd": stdev(seed_gains),
            "seedSigmaMean": mean(seed_sigmas),
            "seedSigmaStd": stdev(seed_sigmas),
            "ensembleMeanHeightMean": mean(
                [float(row["meanHeight"]) for row in ensemble]
            ),
            "ensembleMeanHeightStd": stdev(
                [float(row["meanHeight"]) for row in ensemble]
            ),
            "heightEstimator": "column_mass_linear_no_clip",
            "ensembleTrace": str(ensemble_path),
        }
        status_probe = {
            "fitR2": mode_row["fitR2Ensemble"],
            "windowGainStd": mode_row["windowGainStd"],
            "omegaFitOverTheory": mode_row["omegaFitOverTheoryEnsemble"],
            "fitFrames": mode_row["fitFramesEnsemble"],
        }
        mode_row["status"] = case_status(status_probe)
        grouped.append(mode_row)
        print(
            f"[0493x12cal] ensemble mode={mode} reps={len(case_names)} "
            f"status={mode_row['status']} sigmaEff={sigma_effective:.9g} "
            f"gain={gain:.6g} R2={primary['r2']:.6f} "
            f"windowStd={mode_row['windowGainStd']:.4g}"
        )

    write_csv(args.output_dir / "capillary_calibration_modes_0493x12cal.csv", grouped)

    # Raw cross-mode dispersion uses every requested ensemble-mode point.  It is
    # diagnostic whenever the global status is not PASS.
    finite_mode_rows = [
        row
        for row in grouped
        if math.isfinite(row["omegaFitEnsemble"])
        and math.isfinite(row["omegaTheoryDeclared"])
    ]
    dispersion_pairs = [
        (
            row["omegaTheoryDeclared"] ** 2,
            row["omegaFitEnsemble"] ** 2,
        )
        for row in finite_mode_rows
    ]
    dispersion_gain = slope_through_origin(dispersion_pairs)
    sigma_effective_dispersion = sigma_declared * dispersion_gain

    mode_gains = [row["surfaceTensionGainEnsemble"] for row in finite_mode_rows]
    mode_sigma = [row["sigmaEffectiveEnsemble"] for row in finite_mode_rows]
    mode_relative_std = (
        stdev(mode_gains) / mean(mode_gains)
        if mode_gains and mean(mode_gains) != 0
        else math.nan
    )
    all_modes_present = len(finite_mode_rows) == len(requested_modes)
    all_modes_pass = (
        all_modes_present and all(row["status"] == "PASS" for row in grouped)
    )
    all_modes_usable = (
        all_modes_present and all(row["status"] != "INVALID" for row in grouped)
    )
    mean_fit_r2 = mean([row["fitR2Ensemble"] for row in finite_mode_rows])

    if (
        len(requested_modes) >= 2
        and all_modes_pass
        and math.isfinite(mode_relative_std)
        and mode_relative_std <= 0.05
        and mean_fit_r2 >= 0.98
    ):
        status = "PASS"
    elif (
        len(requested_modes) >= 2
        and all_modes_usable
        and math.isfinite(mode_relative_std)
        and mode_relative_std <= 0.10
        and mean_fit_r2 >= 0.90
    ):
        status = "REVIEW"
    else:
        status = "INVALID"

    published_sigma = (
        sigma_effective_dispersion if status == "PASS" else math.nan
    )

    viscosity = args.kinematic_viscosity
    if not (math.isfinite(viscosity) and viscosity > 0):
        viscosity = parse_transport_viscosity(args.transport_calibration)

    first = manifest[0]
    h = float(first["h"])
    gamma = float(first["gamma"])
    particle_mass = float(first["liquid_mass"])
    rho = gamma * particle_mass / (h * h)

    summary = {
        "status": status,
        "surfaceTensionStatus": status,
        "calibrationPath": first["calibration_path"],
        "sigmaDeclared": sigma_declared,
        "surfaceTensionEffective": published_sigma,
        "surfaceTensionEffectiveRaw": sigma_effective_dispersion,
        "surfaceTensionGain": dispersion_gain,
        "surfaceTensionGainModeMean": mean(mode_gains),
        "surfaceTensionGainModeStd": stdev(mode_gains),
        "surfaceTensionGainModeRelativeStd": mode_relative_std,
        "surfaceTensionEffectiveModeMean": mean(mode_sigma),
        "surfaceTensionEffectiveModeStd": stdev(mode_sigma),
        "dispersionSlopeOmega2": dispersion_gain,
        "meanFitR2": mean_fit_r2,
        "requestedModes": " ".join(map(str, requested_modes)),
        "requestedModeCount": len(requested_modes),
        "usableModeCount": sum(row["status"] != "INVALID" for row in grouped),
        "cases": len(case_rows),
        "usableCases": sum(row["status"] != "INVALID" for row in case_rows),
        "passCases": sum(row["status"] == "PASS" for row in case_rows),
        "reviewCases": sum(row["status"] == "REVIEW" for row in case_rows),
        "invalidCases": sum(row["status"] == "INVALID" for row in case_rows),
        "rhoReference": rho,
        "Lx": float(first["Lx"]),
        "Ly": float(first["Ly"]),
        "Nx": int(first["nx"]),
        "Ny": int(first["ny"]),
        "cellSize": h,
        "gamma": gamma,
        "particleMass": particle_mass,
        "kBT": float(first["kBT"]),
        "meanDepth": float(first["mean_height"]),
        "amplitudeCells": float(first["amplitude_cells"]),
        "minRadiusCells": float(first["min_radius_cells"]),
        "x12aRadiusCells": float(first["x12a_radius_cells"]),
        "fitPeriods": args.fit_periods,
        "sensitivityPeriods": args.sensitivity_periods,
        "kinematicViscosity": viscosity,
        "heightEstimator": "column_mass_linear_no_clip",
        "seedEnsembleBeforeFit": True,
    }

    if args.characteristic_U > 0 and args.characteristic_D > 0:
        velocity = args.characteristic_U
        diameter = args.characteristic_D
        sigma_raw = sigma_effective_dispersion
        summary.update(
            {
                "characteristicU": velocity,
                "characteristicD": diameter,
                "WeberDeclared": rho * velocity * velocity * diameter / sigma_declared,
                "WeberEffectiveRaw": rho * velocity * velocity * diameter / sigma_raw
                if sigma_raw > 0
                else math.nan,
                "WeberEffective": rho * velocity * velocity * diameter / published_sigma
                if math.isfinite(published_sigma) and published_sigma > 0
                else math.nan,
                "capillaryVelocityRaw": math.sqrt(sigma_raw / (rho * diameter))
                if sigma_raw > 0
                else math.nan,
                "capillaryTimeRaw": math.sqrt(rho * diameter ** 3 / sigma_raw)
                if sigma_raw > 0
                else math.nan,
            }
        )
        if math.isfinite(viscosity) and viscosity > 0:
            summary.update(
                {
                    "Reynolds": velocity * diameter / viscosity,
                    "OhnesorgeRaw": viscosity
                    * math.sqrt(rho / (sigma_raw * diameter))
                    if sigma_raw > 0
                    else math.nan,
                }
            )
        if args.gravity > 0:
            summary.update(
                {
                    "BondRaw": rho * args.gravity * diameter * diameter / sigma_raw
                    if sigma_raw > 0
                    else math.nan,
                    "gravityMagnitude": args.gravity,
                }
            )

    clean = {key: finite_or_none(value) for key, value in summary.items()}
    (args.output_dir / "capillary_calibration_0493x12cal.json").write_text(
        json.dumps(clean, indent=2, sort_keys=True) + "\n"
    )
    write_csv(args.output_dir / "capillary_calibration_0493x12cal.csv", [clean])

    report = [
        "# 0493x12cal — capillary-property calibration",
        "",
        f"Status: **{status}**",
        "",
        "## Measured capillary property",
        "",
        f"- declared sigma: `{sigma_declared:.10g}`",
        f"- effective sigma raw: `{sigma_effective_dispersion:.10g}`",
        f"- dynamic gain sigma_eff/sigma_declared: `{dispersion_gain:.10g}`",
        f"- equal-mode gain mean ± std: `{mean(mode_gains):.10g}` ± `{stdev(mode_gains):.4g}`",
        f"- mean fit R²: `{mean_fit_r2:.8g}`",
        f"- usable modes: `{sum(row['status'] != 'INVALID' for row in grouped)}/{len(requested_modes)}`",
        "",
        "## Definition",
        "",
        r"- sigma_eff is inferred from `omega^2=(sigma_eff/rho_ref) k^3 tanh(kH)`.",
        "- interface displacement is reconstructed linearly from column mass; no cellwise clipping is used.",
        "- equal-mode thermal realizations are averaged as signed Fourier quadratures before the production fit.",
        "- the published `surfaceTensionEffective` field is populated only when status is PASS; the raw estimate is always retained.",
        "- the wave field is deliberately resolved and low-curvature, so this calibrates the dynamic capillary coefficient, not the minRadiusCells sub-grid limiter.",
        "",
        "## Numerical context",
        "",
        f"- calibration path: `{first['calibration_path']}`",
        f"- grid: `{first['nx']}x{first['ny']}`, h `{h:.10g}`",
        f"- gamma `{gamma:g}`, particle mass `{particle_mass:g}`, rho_ref `{rho:.10g}`",
        f"- kBT `{float(first['kBT']):.10g}`",
        f"- minRadiusCells `{float(first['min_radius_cells']):.10g}`",
        f"- x12a radiusCells `{float(first['x12a_radius_cells']):.10g}`",
        "",
    ]
    if args.characteristic_U > 0 and args.characteristic_D > 0:
        report += [
            "## Requested impact/flow scale",
            "",
            f"- U: `{args.characteristic_U:.10g}`",
            f"- D: `{args.characteristic_D:.10g}`",
            f"- Weber from declared sigma: `{summary['WeberDeclared']:.10g}`",
            f"- Weber from sigma_eff raw: `{summary['WeberEffectiveRaw']:.10g}`",
        ]
        if "Reynolds" in summary:
            report += [
                f"- kinematic viscosity: `{viscosity:.10g}`",
                f"- Reynolds: `{summary['Reynolds']:.10g}`",
                f"- Ohnesorge raw: `{summary['OhnesorgeRaw']:.10g}`",
            ]
        if "BondRaw" in summary:
            report += [f"- Bond raw: `{summary['BondRaw']:.10g}`"]
        report += [""]

    report += [
        "## Quality policy",
        "",
        "- PASS requires resolved fits on every requested mode, mean fit R² >= 0.98 and <=5% relative spread between mode gains.",
        "- REVIEW retains the raw calibration but does not publish it as the qualified effective property.",
        "- INVALID means the capillary coefficient must not be inferred from this campaign.",
        "",
    ]
    (args.output_dir / "README_0493x12cal_RESULTS.md").write_text(
        "\n".join(report) + "\n"
    )

    try:
        import matplotlib.pyplot as plt

        figure = plt.figure()
        axis = figure.add_subplot(111)
        x = [row["omegaTheoryDeclared"] ** 2 for row in finite_mode_rows]
        y = [row["omegaFitEnsemble"] ** 2 for row in finite_mode_rows]
        high = max(x) * 1.05 if x else 1.0
        axis.scatter(x, y)
        for row, xx, yy in zip(finite_mode_rows, x, y):
            axis.annotate(
                f"n={row['mode']} {row['status']}",
                (xx, yy),
                xytext=(5, 5),
                textcoords="offset points",
            )
        axis.plot([0, high], [0, high], label="unit slope")
        slope_label = (
            f"qualified slope={dispersion_gain:.4f}"
            if status == "PASS"
            else f"raw slope={dispersion_gain:.4f} ({status})"
        )
        axis.plot(
            [0, high],
            [0, dispersion_gain * high],
            label=slope_label,
        )
        axis.set_xlabel("declared-theory omega^2")
        axis.set_ylabel("measured ensemble omega^2")
        axis.legend()
        figure.tight_layout()
        figure.savefig(args.output_dir / "capillary_calibration_dispersion_0493x12cal.png", dpi=170)
        plt.close(figure)
    except Exception as exc:
        print(f"[0493x12cal] plotting skipped: {exc}")

    print("===== 0493x12cal CAPILLARY CALIBRATION =====")
    print(
        f"status={status} sigmaDeclared={sigma_declared:.9g} "
        f"sigmaEffRaw={sigma_effective_dispersion:.9g} gain={dispersion_gain:.9g}"
    )
    print(
        f"modes={sum(row['status'] != 'INVALID' for row in grouped)}/{len(requested_modes)} "
        f"modeRelStd={mode_relative_std:.6g} meanFitR2={mean_fit_r2:.6g}"
    )
    if args.characteristic_U > 0 and args.characteristic_D > 0:
        print(
            f"WeDeclared={summary['WeberDeclared']:.9g} "
            f"WeEffectiveRaw={summary['WeberEffectiveRaw']:.9g}"
        )
        if "Reynolds" in summary:
            print(
                f"Re={summary['Reynolds']:.9g} "
                f"OhRaw={summary['OhnesorgeRaw']:.9g}"
            )
    print(f"result={args.output_dir/'capillary_calibration_0493x12cal.csv'}")


if __name__ == "__main__":
    main()
