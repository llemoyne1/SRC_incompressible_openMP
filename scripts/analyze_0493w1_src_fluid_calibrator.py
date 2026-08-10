#!/usr/bin/env python3
"""Analyze 0493w1 SRC fluid calibration: nu, c_s and D_self."""
from __future__ import annotations

import argparse
import csv
import json
import math
import re
import struct
from pathlib import Path

import numpy as np


def parse_args():
    p = argparse.ArgumentParser()
    p.add_argument("--root", type=Path, required=True)
    for name, typ in (
        ("Lx", float),
        ("Ly", float),
        ("Nx", int),
        ("Ny", int),
        ("gamma", int),
        ("dt", float),
        ("kBT", float),
        ("mass", float),
    ):
        p.add_argument("--" + name, type=typ, required=True)
    p.add_argument("--rotation-angle", type=float, required=True)
    p.add_argument("--random-rotation-sign", required=True)
    p.add_argument("--grid-shift-enable", required=True)
    p.add_argument("--thermostat-enable", required=True)
    p.add_argument("--thermostat-mode", required=True)
    p.add_argument("--thermostat-every", type=int, required=True)
    p.add_argument("--thermostat-target-kBT", type=float, required=True)
    p.add_argument("--thermostat-min-particles", type=int, required=True)
    p.add_argument("--tg-mode-x", type=int, required=True)
    p.add_argument("--tg-mode-y", type=int, required=True)
    p.add_argument("--tg-amplitude", type=float, required=True)
    p.add_argument("--sound-mode-x", type=int, required=True)
    p.add_argument("--sound-density-amplitude", type=float, required=True)
    p.add_argument("--sound-replicates", type=int, default=1)
    p.add_argument("--msd-Lx", type=float, required=True)
    p.add_argument("--msd-Ly", type=float, required=True)
    p.add_argument("--msd-Nx", type=int, required=True)
    p.add_argument("--msd-Ny", type=int, required=True)
    p.add_argument("--msd-sample-particles", type=int, default=20000)
    p.add_argument("--characteristic-U", type=float, default=-1)
    p.add_argument("--characteristic-L", type=float, default=-1)
    return p.parse_args()


def parse_bool(text):
    value = str(text).strip().lower()
    if value in ("true", "1", "yes", "on"):
        return True
    if value in ("false", "0", "no", "off"):
        return False
    raise ValueError(f"invalid boolean value: {text}")


def read_state(path: Path):
    with path.open("rb") as stream:
        magic = stream.read(16)
        if not magic.startswith(b"SRCMPCD_STATE"):
            raise ValueError(f"bad magic {path}")
        version, endian, dim, layout, n, has_type, has_mass, real_size, type_size = struct.unpack(
            "<IIIIQIIII", stream.read(40)
        )
        stream.read(64)
        if (
            version not in (1, 2)
            or endian != 0x01020304
            or dim != 2
            or layout != 1
            or real_size != 8
            or not has_type
            or not has_mass
        ):
            raise ValueError(f"unsupported state {path}")
        x = np.fromfile(stream, dtype="<f8", count=n)
        y = np.fromfile(stream, dtype="<f8", count=n)
        vx = np.fromfile(stream, dtype="<f8", count=n)
        vy = np.fromfile(stream, dtype="<f8", count=n)
        typ = np.fromfile(stream, dtype="<u4", count=n)
        mass = np.fromfile(stream, dtype="<f8", count=n)
        role = (
            np.fromfile(stream, dtype="u1", count=n)
            if version == 2
            else np.ones(n, dtype=np.uint8)
        )
    if min(len(x), len(y), len(vx), len(vy), len(typ), len(mass), len(role)) != n:
        raise ValueError(f"truncated state {path}")
    return {
        "n": int(n),
        "x": x,
        "y": y,
        "vx": vx,
        "vy": vy,
        "type": typ,
        "mass": mass,
        "role": role,
    }


def list_dumps(case: Path):
    rows = []
    for path in (case / "output").glob("state_step_*.smpcd"):
        match = re.search(r"(\d+)\.smpcd$", path.name)
        if match:
            rows.append((int(match.group(1)), path))
    return sorted(rows)


def linear_fit(x, y):
    x = np.asarray(x, float)
    y = np.asarray(y, float)
    mask = np.isfinite(x) & np.isfinite(y)
    x = x[mask]
    y = y[mask]
    if len(x) < 3:
        return {
            "slope": math.nan,
            "intercept": math.nan,
            "r2": math.nan,
            "points": len(x),
        }
    slope, intercept = np.polyfit(x, y, 1)
    predicted = slope * x + intercept
    residual = float(np.sum((y - predicted) ** 2))
    total = float(np.sum((y - np.mean(y)) ** 2))
    return {
        "slope": float(slope),
        "intercept": float(intercept),
        "r2": 1 - residual / total if total > 0 else math.nan,
        "points": len(x),
    }


def write_csv(path, rows):
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


def fit_damped_cosine(t, y, omega_min, omega_max):
    """Fit offset + exp(-beta*t)*(C*cos(omega*t)+S*sin(omega*t)).

    The frequency and damping are selected by deterministic coarse-to-fine grid
    search. For each (omega,beta), offset/C/S are solved linearly. This avoids a
    scipy dependency and does not assume a prior sound speed.
    """
    t = np.asarray(t, float)
    y = np.asarray(y, float)
    mask = np.isfinite(t) & np.isfinite(y)
    t = t[mask]
    y = y[mask]
    if len(t) < 12:
        raise ValueError("not enough points for damped-cosine sound fit")
    order = np.argsort(t)
    t = t[order]
    y = y[order]
    t = t - t[0]
    span = float(t[-1])
    if span <= 0:
        raise ValueError("zero sound fit time span")
    dt_sample = float(np.median(np.diff(t)))
    nyquist = math.pi / dt_sample
    omega_min = max(float(omega_min), 0.35 * 2 * math.pi / span)
    omega_max = min(float(omega_max), 0.92 * nyquist)
    if not (0 < omega_min < omega_max):
        raise ValueError(
            f"invalid sound frequency search window [{omega_min},{omega_max}]"
        )

    total_variance = float(np.sum((y - np.mean(y)) ** 2))
    if total_variance <= 0:
        raise ValueError("zero sound-mode variance")

    def solve(omega, beta):
        decay = np.exp(-beta * t)
        matrix = np.column_stack(
            (
                np.ones_like(t),
                decay * np.cos(omega * t),
                decay * np.sin(omega * t),
            )
        )
        coeff, _, _, _ = np.linalg.lstsq(matrix, y, rcond=None)
        model = matrix @ coeff
        sse = float(np.sum((y - model) ** 2))
        return sse, coeff, model

    beta_lo = 0.0
    beta_hi = 12.0 / span
    best = None
    omega_lo = omega_min
    omega_hi = omega_max

    schedules = ((240, 44), (100, 38), (100, 38))
    for level, (n_omega, n_beta) in enumerate(schedules):
        omegas = np.linspace(omega_lo, omega_hi, n_omega)
        betas = np.linspace(beta_lo, beta_hi, n_beta)
        local_best = None
        for omega in omegas:
            for beta in betas:
                sse, coeff, model = solve(float(omega), float(beta))
                item = (sse, float(omega), float(beta), coeff, model)
                if local_best is None or item[0] < local_best[0]:
                    local_best = item
        best = local_best
        _, omega_c, beta_c, _, _ = best
        if level + 1 < len(schedules):
            omega_step = (omega_hi - omega_lo) / max(1, n_omega - 1)
            beta_step = (beta_hi - beta_lo) / max(1, n_beta - 1)
            omega_lo = max(omega_min, omega_c - 3.0 * omega_step)
            omega_hi = min(omega_max, omega_c + 3.0 * omega_step)
            beta_lo = max(0.0, beta_c - 3.0 * beta_step)
            beta_hi = min(12.0 / span, beta_c + 3.0 * beta_step)

    sse, omega, beta, coeff, model = best
    offset, cosine_coeff, sine_coeff = map(float, coeff)
    amplitude = math.hypot(cosine_coeff, sine_coeff)
    phase = math.atan2(-sine_coeff, cosine_coeff)
    r2 = 1.0 - sse / total_variance
    omega_tolerance = max(1e-12, 0.015 * (omega_max - omega_min))
    beta_tolerance = max(1e-12, 0.02 * (12.0 / span))
    return {
        "omega": omega,
        "beta": beta,
        "offset": offset,
        "cosineCoeff": cosine_coeff,
        "sineCoeff": sine_coeff,
        "amplitude": amplitude,
        "phase": phase,
        "r2": r2,
        "points": len(t),
        "cycles": omega * span / (2 * math.pi),
        "timeSpan": span,
        "omegaSearchMin": omega_min,
        "omegaSearchMax": omega_max,
        "betaSearchMax": 12.0 / span,
        "omegaAtBoundary": (
            abs(omega - omega_min) <= omega_tolerance
            or abs(omega - omega_max) <= omega_tolerance
        ),
        "betaAtBoundary": beta >= 12.0 / span - beta_tolerance,
        "model": model,
    }



def _complex_relative_rms(residual, reference):
    numerator = float(np.sum(np.abs(residual) ** 2))
    denominator = float(np.sum(np.abs(reference) ** 2))
    if denominator <= 0:
        return math.inf
    return math.sqrt(numerator / denominator)


def _nnls_two_parameters(matrix, target):
    """Small deterministic non-negative least-squares solver for two columns."""
    matrix = np.asarray(matrix, float)
    target = np.asarray(target, float)
    if matrix.ndim != 2 or matrix.shape[1] != 2:
        raise ValueError("two-column matrix required")

    candidates = []

    unconstrained, _, _, _ = np.linalg.lstsq(matrix, target, rcond=None)
    if np.all(unconstrained >= 0):
        candidates.append((unconstrained, "none"))

    for free_column, label in ((0, "nuL=0"), (1, "cs2=0")):
        column = matrix[:, free_column]
        denominator = float(np.dot(column, column))
        value = max(0.0, float(np.dot(column, target) / denominator)) if denominator > 0 else 0.0
        coeff = np.zeros(2)
        coeff[free_column] = value
        candidates.append((coeff, label))

    candidates.append((np.zeros(2), "cs2=0,nuL=0"))
    best = min(
        candidates,
        key=lambda item: float(np.sum((target - matrix @ item[0]) ** 2)),
    )
    return best


def fit_longitudinal_hydrodynamics(t, rho, velocity, k):
    """Fit cumulative linear longitudinal balances.

    With Fourier convention exp(-ikx):

        rho(t)-rho(0) = -i k int_0^t u(s) ds
        u(t)-u(0) = -i k c_s^2 int_0^t rho(s) ds
                    - nu_L k^2 int_0^t u(s) ds.

    Cumulative integration makes the deterministic pressure response grow with
    time while zero-mean collision noise averages out. This is substantially
    more robust than fitting every noisy dump interval independently.
    """
    t = np.asarray(t, float)
    rho = np.asarray(rho, complex)
    velocity = np.asarray(velocity, complex)
    if not (len(t) == len(rho) == len(velocity)) or len(t) < 20:
        raise ValueError("at least 20 synchronized sound samples are required")
    if not np.all(np.diff(t) > 0):
        raise ValueError("sound times must be strictly increasing")
    if not math.isfinite(k) or k <= 0:
        raise ValueError("positive longitudinal wavenumber required")

    dt = np.diff(t)
    rho_mid = 0.5 * (rho[:-1] + rho[1:])
    velocity_mid = 0.5 * (velocity[:-1] + velocity[1:])
    int_rho = np.concatenate(([0j], np.cumsum(rho_mid * dt)))
    int_velocity = np.concatenate(([0j], np.cumsum(velocity_mid * dt)))
    delta_rho = rho - rho[0]
    delta_velocity = velocity - velocity[0]

    point_count = len(t) - 1
    minimum_points = min(point_count, max(20, min(50, point_count // 3)))
    endings = sorted({
        point_count,
        *(max(minimum_points, min(point_count, int(round(f * point_count))))
          for f in (0.35, 0.50, 0.65, 0.80, 0.90)),
    })

    candidates = []
    for end in endings:
        sl = slice(1, end + 1)
        cs_column = -1j * k * int_rho[sl]
        nu_column = -(k * k) * int_velocity[sl]
        complex_matrix = np.column_stack((cs_column, nu_column))
        real_matrix = np.vstack((complex_matrix.real, complex_matrix.imag))
        real_target = np.concatenate((delta_velocity[sl].real, delta_velocity[sl].imag))
        coeff, active_constraints = _nnls_two_parameters(real_matrix, real_target)
        cs2, nu_l = map(float, coeff)
        momentum_model = complex_matrix @ coeff
        momentum_residual = delta_velocity[sl] - momentum_model
        continuity_model = -1j * k * int_velocity[sl]
        continuity_residual = delta_rho[sl] - continuity_model
        momentum_relative_rms = _complex_relative_rms(momentum_residual, delta_velocity[sl])
        continuity_reference = delta_rho[sl]
        continuity_relative_rms = _complex_relative_rms(continuity_residual, continuity_reference)
        condition = float(np.linalg.cond(real_matrix))
        candidates.append({
            "end": end,
            "cs2": cs2,
            "nuL": nu_l,
            "activeConstraints": active_constraints,
            "momentumModel": momentum_model,
            "momentumResidual": momentum_residual,
            "continuityModel": continuity_model,
            "continuityResidual": continuity_residual,
            "momentumRelativeRms": momentum_relative_rms,
            "continuityRelativeRms": continuity_relative_rms,
            "conditionNumber": condition,
        })

    def score(item):
        constraint_penalty = 1.0 if item["activeConstraints"] != "none" else 0.0
        condition_penalty = max(0.0, math.log10(max(item["conditionNumber"], 1.0)) - 8.0)
        # Prefer physical fits and, secondarily, longer observation windows.
        return (
            item["momentumRelativeRms"]
            + 0.35 * item["continuityRelativeRms"]
            + constraint_penalty
            + 0.1 * condition_penalty
            - 0.03 * item["end"] / point_count
        )

    fit = min(candidates, key=score)
    cs2 = fit["cs2"]
    nu_l = fit["nuL"]
    sound_speed = math.sqrt(cs2) if cs2 > 0 else 0.0
    beta = 0.5 * nu_l * k * k
    natural_omega = sound_speed * k
    discriminant = beta * beta - natural_omega * natural_omega
    tolerance = 1e-10 * max(beta * beta, natural_omega * natural_omega, 1.0)
    if discriminant < -tolerance:
        regime = "underdamped"
        damped_omega = math.sqrt(-discriminant)
        eigenvalue_1 = complex(-beta, damped_omega)
        eigenvalue_2 = complex(-beta, -damped_omega)
    elif discriminant > tolerance:
        regime = "overdamped"
        root = math.sqrt(discriminant)
        damped_omega = 0.0
        eigenvalue_1 = complex(-beta + root, 0.0)
        eigenvalue_2 = complex(-beta - root, 0.0)
    else:
        regime = "critical"
        damped_omega = 0.0
        eigenvalue_1 = eigenvalue_2 = complex(-beta, 0.0)
    damping_ratio = beta / natural_omega if natural_omega > 0 else math.inf
    fit_span = float(t[fit["end"]] - t[0])

    return {
        **fit,
        "soundSpeed": sound_speed,
        "dampingRate": beta,
        "naturalOmega": natural_omega,
        "dampedOmega": damped_omega,
        "dampedCyclesInFit": damped_omega * fit_span / (2 * math.pi),
        "dampingRatio": damping_ratio,
        "regime": regime,
        "eigenvalue1": eigenvalue_1,
        "eigenvalue2": eigenvalue_2,
        "fitPoints": fit["end"],
        "fitIntervals": fit["end"],
        "fitTimeSpan": fit_span,
        "momentumFitScore": 1.0 - fit["momentumRelativeRms"] ** 2,
        "continuityFitScore": 1.0 - fit["continuityRelativeRms"] ** 2,
        "acousticAttenuation": 0.5 * nu_l,
    }


def analyze_tg(a):
    kx = 2 * math.pi * a.tg_mode_x / a.Lx
    ky = 2 * math.pi * a.tg_mode_y / a.Ly
    k2 = kx * kx + ky * ky
    series = []
    for step, path in list_dumps(a.root / "tg"):
        state = read_state(path)
        fluid = state["role"] == 1
        x = state["x"][fluid]
        y = state["y"][fluid]
        mass = state["mass"][fluid]
        vx = state["vx"][fluid]
        vy = state["vy"][fluid]
        bx = np.sin(kx * x) * np.cos(ky * y)
        by = -np.cos(kx * x) * np.sin(ky * y)
        amplitude = float(np.sum(mass * (vx * bx + vy * by)) / np.sum(mass * (bx * bx + by * by)))
        series.append({"step": step, "time": step * a.dt, "amplitude": amplitude, "absAmplitude": abs(amplitude)})
    if len(series) < 8:
        raise ValueError("not enough TG dumps")
    t = np.array([row["time"] for row in series])
    amplitude = np.array([row["absAmplitude"] for row in series])
    ratio = amplitude / max(amplitude[0], 1e-300)

    candidates = []
    n = len(t)
    for start_fraction in (0.0, 0.03, 0.06, 0.10):
        start = max(1, int(round(start_fraction * (n - 1))))
        for end_fraction in (0.35, 0.50, 0.65, 0.80, 1.0):
            end = max(start + 7, min(n, int(round(end_fraction * n))))
            mask = np.zeros(n, dtype=bool)
            mask[start:end] = True
            mask &= amplitude > 0
            # Do not fit deep into the stochastic floor.
            mask &= ratio > 0.025
            if np.count_nonzero(mask) < 7:
                continue
            fit = linear_fit(t[mask], np.log(amplitude[mask]))
            nu = -fit["slope"] / k2
            log_span = float(np.max(np.log(amplitude[mask])) - np.min(np.log(amplitude[mask])))
            if nu > 0 and fit["points"] >= 7 and log_span >= 0.55:
                candidates.append({"fit": fit, "nu": nu, "start": start, "end": end, "logSpan": log_span})
    if not candidates:
        mask = (t > 0) & (amplitude > 0)
        fit = linear_fit(t[mask], np.log(amplitude[mask]))
        chosen = {"fit": fit, "nu": -fit["slope"] / k2, "start": 1, "end": n, "logSpan": math.nan}
        stable = [chosen]
    else:
        # Excellent linearity dominates, then prefer a long log-amplitude span.
        chosen = max(candidates, key=lambda c: (c["fit"]["r2"], min(c["logSpan"], 3.0), c["fit"]["points"]))
        stable = [c for c in candidates if c["fit"]["r2"] >= max(0.97, chosen["fit"]["r2"] - 0.01)]

        # 0493x7n-fix4c: candidates may exist while none reaches the
        # strict R2>=0.97 stable-window floor. Preserve that diagnostic,
        # but use chosen only for range statistics so analysis cannot crash.
        stable_window_count = len(stable)
        stable_window_fallback = stable_window_count == 0
        stats_windows = stable if stable else [chosen]
        nus = np.array([c["nu"] for c in stats_windows], float)
    for index, row in enumerate(series):
        row["fitWindow"] = bool(chosen["start"] <= index < chosen["end"] and ratio[index] > 0.025)
    return series, {
        "nu": float(chosen["nu"]),
        "fitR2": chosen["fit"]["r2"],
        "fitPoints": chosen["fit"]["points"],
        "fitStartIndex": chosen["start"],
        "fitEndIndex": chosen["end"],
        "fitWindowCandidates": len(candidates),
        "fitStableWindows": stable_window_count,
        "fitStableFallback": stable_window_fallback,
        "nuWindowStd": float(np.std(nus, ddof=1)) if len(nus) > 1 else 0.0,
        "nuWindowMin": float(np.min(nus)),
        "nuWindowMax": float(np.max(nus)),
        "k2": k2,
        "initialAmplitude": float(amplitude[0]),
        "finalAmplitude": float(amplitude[-1]),
        "finalRatio": float(ratio[-1]),
    }


def _sound_series_from_case(case, dt, k):
    rows = []
    for step, path in list_dumps(case):
        state = read_state(path)
        fluid = state["role"] == 1
        x = state["x"][fluid]
        mass = state["mass"][fluid]
        vx = state["vx"][fluid]
        basis = np.exp(-1j * k * x)
        total_mass = np.sum(mass)
        rho = 2 * np.sum(mass * basis) / total_mass
        ux = 2 * np.sum(mass * vx * basis) / total_mass
        rows.append((step, step * dt, rho, ux))
    if len(rows) < 20:
        raise ValueError(f"not enough sound dumps in {case}")
    return rows


def analyze_sound(a):
    k = 2 * math.pi * a.sound_mode_x / a.Lx
    cases = sorted(path for path in a.root.glob("sound_rep*") if path.is_dir())
    if not cases and (a.root / "sound").is_dir():
        cases = [a.root / "sound"]
    if not cases:
        raise ValueError("no sound realization directories found")
    if a.sound_replicates > 0 and len(cases) != a.sound_replicates:
        raise ValueError(f"sound replicate count mismatch expected={a.sound_replicates} found={len(cases)}")

    replicas = [_sound_series_from_case(case, a.dt, k) for case in cases]
    reference_steps = [row[0] for row in replicas[0]]
    for rows in replicas[1:]:
        if [row[0] for row in rows] != reference_steps:
            raise ValueError("sound replicate dump steps are not synchronized")
    t = np.array([row[1] for row in replicas[0]], float)
    rho_stack = np.array([[row[2] for row in rows] for rows in replicas], complex)
    velocity_stack = np.array([[row[3] for row in rows] for rows in replicas], complex)
    rho = np.mean(rho_stack, axis=0)
    velocity = np.mean(velocity_stack, axis=0)
    rho_sem = np.std(rho_stack, axis=0, ddof=1) / math.sqrt(len(cases)) if len(cases) > 1 else np.zeros_like(t)
    velocity_sem = np.std(velocity_stack, axis=0, ddof=1) / math.sqrt(len(cases)) if len(cases) > 1 else np.zeros_like(t)
    hydro = fit_longitudinal_hydrodynamics(t, rho, velocity, k)

    # Leave-one-out uncertainty quantifies realization sensitivity.
    jackknife = []
    if len(cases) >= 3:
        for omitted in range(len(cases)):
            keep = [i for i in range(len(cases)) if i != omitted]
            try:
                item = fit_longitudinal_hydrodynamics(t, np.mean(rho_stack[keep], axis=0), np.mean(velocity_stack[keep], axis=0), k)
                if item["soundSpeed"] > 0:
                    jackknife.append(item)
            except ValueError:
                pass
    cs_values = np.array([item["soundSpeed"] for item in jackknife], float)
    nul_values = np.array([item["nuL"] for item in jackknife], float)

    reference = rho[0]
    unit_reference = np.conj(reference) / abs(reference) if abs(reference) > 0 else 1.0
    projected = np.real(rho * unit_reference)
    oscillation = None
    if hydro["regime"] == "underdamped" and hydro["dampedCyclesInFit"] >= 0.5:
        end = hydro["fitIntervals"]
        omega = hydro["dampedOmega"]
        try:
            oscillation = fit_damped_cosine(t[: end + 1], projected[: end + 1], max(0.35 * omega, 1e-12), 1.8 * omega)
        except ValueError:
            oscillation = None

    series = []
    for index, step in enumerate(reference_steps):
        series.append({
            "step": step,
            "time": t[index],
            "replicates": len(cases),
            "rhoReal": float(rho[index].real),
            "rhoImag": float(rho[index].imag),
            "rhoAmplitude": float(abs(rho[index])),
            "rhoSem": float(rho_sem[index]),
            "uxReal": float(velocity[index].real),
            "uxImag": float(velocity[index].imag),
            "uxAmplitude": float(abs(velocity[index])),
            "uxSem": float(velocity_sem[index]),
            "rhoProjectedStanding": float(projected[index]),
        })
    secondary = {
        "available": oscillation is not None,
        "r2": oscillation["r2"] if oscillation else math.nan,
        "omega": oscillation["omega"] if oscillation else math.nan,
        "beta": oscillation["beta"] if oscillation else math.nan,
        "cycles": oscillation["cycles"] if oscillation else math.nan,
    }
    return series, {
        "soundReplicates": len(cases),
        "soundSpeed": hydro["soundSpeed"],
        "soundSpeedSquared": hydro["cs2"],
        "soundSpeedJackknifeStd": float(np.std(cs_values, ddof=1)) if len(cs_values) > 1 else math.nan,
        "longitudinalViscosity": hydro["nuL"],
        "longitudinalViscosityJackknifeStd": float(np.std(nul_values, ddof=1)) if len(nul_values) > 1 else math.nan,
        "dampingRate": hydro["dampingRate"],
        "acousticAttenuation": hydro["acousticAttenuation"],
        "dampingRatio": hydro["dampingRatio"],
        "dampingRegime": hydro["regime"],
        "naturalOmega": hydro["naturalOmega"],
        "dampedOmega": hydro["dampedOmega"],
        "dampedCyclesInFit": hydro["dampedCyclesInFit"],
        "eigenvalue1Real": hydro["eigenvalue1"].real,
        "eigenvalue1Imag": hydro["eigenvalue1"].imag,
        "eigenvalue2Real": hydro["eigenvalue2"].real,
        "eigenvalue2Imag": hydro["eigenvalue2"].imag,
        "fitIntervals": hydro["fitIntervals"],
        "fitPoints": hydro["fitPoints"],
        "fitTimeSpan": hydro["fitTimeSpan"],
        "momentumFitScore": hydro["momentumFitScore"],
        "momentumRelativeRms": hydro["momentumRelativeRms"],
        "continuityFitScore": hydro["continuityFitScore"],
        "continuityRelativeRms": hydro["continuityRelativeRms"],
        "conditionNumber": hydro["conditionNumber"],
        "activeConstraints": hydro["activeConstraints"],
        "oscillationValidationAvailable": secondary["available"],
        "oscillationFitR2": secondary["r2"],
        "oscillationOmega": secondary["omega"],
        "oscillationBeta": secondary["beta"],
        "oscillationCycles": secondary["cycles"],
        "initialProjectedAmplitude": float(projected[0]),
        "finalProjectedAmplitude": float(projected[-1]),
        "k": k,
    }

def analyze_msd(a):
    frames = list_dumps(a.root / "msd")
    if len(frames) < 6:
        raise ValueError("not enough MSD dumps")
    initial = read_state(frames[0][1])
    fluid = np.flatnonzero(initial["role"] == 1)
    count = min(a.msd_sample_particles, len(fluid))
    indices = fluid[np.linspace(0, len(fluid) - 1, count, dtype=int)]
    prev_x = initial["x"][indices].copy()
    prev_y = initial["y"][indices].copy()
    unwrap_x = np.zeros(count)
    unwrap_y = np.zeros(count)
    masses = initial["mass"][indices]
    series = []
    max_jump_ratio = 0.0
    for step, path in frames:
        state = read_state(path)
        x = state["x"][indices]
        y = state["y"][indices]
        if step != frames[0][0]:
            dx = (x - prev_x + 0.5 * a.msd_Lx) % a.msd_Lx - 0.5 * a.msd_Lx
            dy = (y - prev_y + 0.5 * a.msd_Ly) % a.msd_Ly - 0.5 * a.msd_Ly
            max_jump_ratio = max(
                max_jump_ratio,
                float(np.max(np.abs(dx)) / a.msd_Lx),
                float(np.max(np.abs(dy)) / a.msd_Ly),
            )
            unwrap_x += dx
            unwrap_y += dy
        prev_x = x.copy()
        prev_y = y.copy()
        weight = np.sum(masses)
        com_x = np.sum(masses * unwrap_x) / weight
        com_y = np.sum(masses * unwrap_y) / weight
        drx = unwrap_x - com_x
        dry = unwrap_y - com_y
        r2 = drx * drx + dry * dry
        msd = float(np.sum(masses * r2) / weight)
        r4 = float(np.sum(masses * r2 * r2) / weight)
        alpha2 = r4 / (2 * msd * msd) - 1 if msd > 0 else math.nan
        series.append(
            {
                "step": step,
                "time": step * a.dt,
                "msd": msd,
                "msdX": float(np.sum(masses * drx * drx) / weight),
                "msdY": float(np.sum(masses * dry * dry) / weight),
                "alpha2": alpha2,
                "sampleParticles": count,
            }
        )
    t = np.array([row["time"] for row in series])
    msd = np.array([row["msd"] for row in series])
    candidates = []
    for fraction in (0.20, 0.30, 0.40, 0.50):
        fit = linear_fit(t[t >= fraction * t[-1]], msd[t >= fraction * t[-1]])
        if fit["slope"] > 0 and fit["points"] >= 6:
            candidates.append((fit["r2"], -fraction, fit, fraction))
    if candidates:
        _, _, fit, fraction = max(candidates, key=lambda item: (item[0], item[1]))
    else:
        fit = linear_fit(t[1:], msd[1:])
        fraction = 0.0
    return series, {
        "selfDiffusion": fit["slope"] / 4.0,
        "fitR2": fit["r2"],
        "fitPoints": fit["points"],
        "fitStartFraction": fraction,
        "fitIntercept": fit["intercept"],
        "sampleParticles": count,
        "maxIncrementBoxFraction": max_jump_ratio,
        "finalMsd": float(msd[-1]),
        "finalAlpha2": series[-1]["alpha2"],
    }


def finite(value):
    if isinstance(value, (int, str, bool)):
        return value
    return value if isinstance(value, float) and math.isfinite(value) else None


def _property_status(value, r2, pass_r2=0.98, review_r2=0.90):
    if not math.isfinite(value) or value <= 0 or not math.isfinite(r2):
        return "INVALID"
    if r2 >= pass_r2:
        return "PASS"
    if r2 >= review_r2:
        return "REVIEW"
    return "INVALID"


def main():
    a = parse_args()
    analysis = a.root / "analysis"
    analysis.mkdir(parents=True, exist_ok=True)

    tg, tg_result = analyze_tg(a)
    sound, sound_result = analyze_sound(a)
    msd, msd_result = analyze_msd(a)
    write_csv(analysis / "tg_decay_0493w1.csv", tg)
    write_csv(analysis / "sound_mode_0493w1.csv", sound)
    write_csv(analysis / "msd_0493w1.csv", msd)

    ax = a.Lx / a.Nx
    ay = a.Ly / a.Ny
    cell = math.sqrt(ax * ay)
    number_density = a.gamma / (ax * ay)
    mass_density = number_density * a.mass
    sigma1 = math.sqrt(a.kBT / a.mass)
    vrms = math.sqrt(2 * a.kBT / a.mass)
    vmean = math.sqrt(math.pi * a.kBT / (2 * a.mass))
    nu = tg_result["nu"]
    diffusion = msd_result["selfDiffusion"]
    raw_sound_speed = sound_result["soundSpeed"]
    cs_iso = math.sqrt(a.kBT / a.mass)
    cs_ad_2d = math.sqrt(2 * a.kBT / a.mass)
    thermostat_enabled = parse_bool(a.thermostat_enable)
    fluid_variant = "thermostatted_src" if thermostat_enabled else "raw_src"

    viscosity_status = _property_status(nu, tg_result["fitR2"], 0.98, 0.93)
    diffusion_status = _property_status(diffusion, msd_result["fitR2"], 0.995, 0.98)
    sound_pass = (
        raw_sound_speed > 0
        and sound_result["fitPoints"] >= 30
        and sound_result["momentumRelativeRms"] <= 0.35
        and sound_result["continuityRelativeRms"] <= 0.25
        and sound_result["conditionNumber"] <= 1.0e8
        and sound_result["activeConstraints"] == "none"
        and 0.40 * cs_iso <= raw_sound_speed <= 2.5 * cs_ad_2d
    )
    sound_review = (
        raw_sound_speed > 0
        and sound_result["fitPoints"] >= 20
        and sound_result["momentumRelativeRms"] <= 0.65
        and sound_result["continuityRelativeRms"] <= 0.45
        and sound_result["conditionNumber"] <= 1.0e10
        and "cs2=0" not in sound_result["activeConstraints"]
    )
    sound_status = "PASS" if sound_pass else ("REVIEW" if sound_review else "INVALID")
    sound_speed = raw_sound_speed if sound_status == "PASS" else math.nan
    statuses = (viscosity_status, diffusion_status, sound_status)
    status = "PASS" if all(x == "PASS" for x in statuses) else ("REVIEW" if all(x != "INVALID" for x in statuses) else "INVALID")

    summary = {
        "status": status,
        "viscosityStatus": viscosity_status,
        "soundStatus": sound_status,
        "diffusionStatus": diffusion_status,
        "fluidVariant": fluid_variant,
        "Lx": a.Lx, "Ly": a.Ly, "Nx": a.Nx, "Ny": a.Ny,
        "cellSizeX": ax, "cellSizeY": ay, "cellSizeGeom": cell,
        "gamma": a.gamma, "dt": a.dt, "kBT": a.kBT, "particleMass": a.mass,
        "rotationAngle": a.rotation_angle,
        "rotationAngleDeg": a.rotation_angle * 180.0 / math.pi,
        "randomRotationSign": parse_bool(a.random_rotation_sign),
        "gridShiftEnable": parse_bool(a.grid_shift_enable),
        "thermostatEnable": thermostat_enabled,
        "thermostatMode": a.thermostat_mode,
        "thermostatEvery": a.thermostat_every,
        "thermostatTargetKBT": a.thermostat_target_kBT,
        "thermostatMinParticles": a.thermostat_min_particles,
        "q6Enable": False, "resamplingEnable": False,
        "numberDensity2D": number_density, "massDensity2D": mass_density,
        "thermalSigma1D": sigma1, "thermalSpeedRms2D": vrms,
        "thermalSpeedMean2D": vmean,
        "thermalBallisticStepSigma1D": sigma1 * a.dt,
        "thermalBallisticStepRms2D": vrms * a.dt,
        "thermalBallisticStepMean2D": vmean * a.dt,
        "meanFreePathProxyMean2D": vmean * a.dt,
        "lambdaMeanOverCell": vmean * a.dt / cell,
        "lambdaRmsOverCell": vrms * a.dt / cell,
        "collisionFrequency": 1.0 / a.dt,
        "viscosityKinematic": nu,
        "viscosityDynamic2D": mass_density * nu,
        "viscosityFitR2": tg_result["fitR2"],
        "viscosityFitPoints": tg_result["fitPoints"],
        "viscosityWindowStd": tg_result["nuWindowStd"],
        "viscosityWindowMin": tg_result["nuWindowMin"],
        "viscosityWindowMax": tg_result["nuWindowMax"],
        "viscosityFitWindowCandidates": tg_result["fitWindowCandidates"],
        "tgModeX": a.tg_mode_x, "tgModeY": a.tg_mode_y,
        "tgInitialAmplitudeRequested": a.tg_amplitude,
        "tgInitialAmplitudeMeasured": tg_result["initialAmplitude"],
        "tgFinalAmplitudeRatio": tg_result["finalRatio"],
        "soundInitialization": "standing_density_zero_velocity",
        "soundEstimator": "ensemble_cumulative_hydrodynamic_regression",
        "soundReplicates": sound_result["soundReplicates"],
        "soundModeX": a.sound_mode_x,
        "soundWavelength": a.Lx / a.sound_mode_x,
        "soundWavelengthCells": a.Nx / a.sound_mode_x,
        "soundDensityAmplitudeRequested": a.sound_density_amplitude,
        "soundSpeed": sound_speed,
        "soundSpeedRawFit": raw_sound_speed,
        "soundSpeedJackknifeStd": sound_result["soundSpeedJackknifeStd"],
        "soundSpeedSquaredRawFit": sound_result["soundSpeedSquared"],
        "soundSpeedIsothermalProxy": cs_iso,
        "soundSpeedAdiabatic2DProxy": cs_ad_2d,
        "longitudinalViscosityRawFit": sound_result["longitudinalViscosity"],
        "longitudinalViscosityJackknifeStd": sound_result["longitudinalViscosityJackknifeStd"],
        "soundHydrodynamicFitIntervals": sound_result["fitIntervals"],
        "soundHydrodynamicFitPoints": sound_result["fitPoints"],
        "soundHydrodynamicFitTimeSpan": sound_result["fitTimeSpan"],
        "soundMomentumFitScore": sound_result["momentumFitScore"],
        "soundMomentumRelativeRms": sound_result["momentumRelativeRms"],
        "soundContinuityFitScore": sound_result["continuityFitScore"],
        "soundContinuityRelativeRms": sound_result["continuityRelativeRms"],
        "soundRegressionConditionNumber": sound_result["conditionNumber"],
        "soundRegressionActiveConstraints": sound_result["activeConstraints"],
        "acousticDampingRegimeRawFit": sound_result["dampingRegime"],
        "acousticDampingRatioRawFit": sound_result["dampingRatio"],
        "selfDiffusion": diffusion,
        "diffusionFitR2": msd_result["fitR2"],
        "diffusionFitPoints": msd_result["fitPoints"],
        "diffusionFitStartFraction": msd_result["fitStartFraction"],
        "msdSampleParticles": msd_result["sampleParticles"],
        "msdMaxIncrementBoxFraction": msd_result["maxIncrementBoxFraction"],
        "msdFinalAlpha2": msd_result["finalAlpha2"],
        "Schmidt": nu / diffusion if nu > 0 and diffusion > 0 else math.nan,
        "viscousCFLCell": nu * a.dt / (cell * cell),
        "diffusiveCFLCell": diffusion * a.dt / (cell * cell),
        "soundCFLCell": sound_speed * a.dt / cell if math.isfinite(sound_speed) else math.nan,
    }

    if a.characteristic_U > 0 and a.characteristic_L > 0:
        velocity = a.characteristic_U
        length = a.characteristic_L
        summary.update({
            "characteristicU": velocity,
            "characteristicL": length,
            "Reynolds": velocity * length / nu if nu > 0 else math.nan,
            "Mach": velocity / sound_speed if math.isfinite(sound_speed) and sound_speed > 0 else math.nan,
            "MachProxyIsothermal": velocity / cs_iso,
            "MachProxyAdiabatic2D": velocity / cs_ad_2d,
            "PecletMass": velocity * length / diffusion if diffusion > 0 else math.nan,
            "KnudsenMeanProxy": vmean * a.dt / length,
            "convectiveTime": length / velocity,
            "viscousTime": length * length / nu if nu > 0 else math.nan,
            "diffusiveTime": length * length / diffusion if diffusion > 0 else math.nan,
            "acousticTime": length / sound_speed if math.isfinite(sound_speed) and sound_speed > 0 else math.nan,
            "hydrodynamicReachReOverMa": sound_speed * length / nu if math.isfinite(sound_speed) and nu > 0 else math.nan,
            "velocityAtMach0p3": 0.3 * sound_speed if math.isfinite(sound_speed) else math.nan,
            "reynoldsAtMach0p3": 0.3 * sound_speed * length / nu if math.isfinite(sound_speed) and nu > 0 else math.nan,
            "velocityAtRe50": 50.0 * nu / length if nu > 0 else math.nan,
            "machAtRe50": 50.0 * nu / (length * sound_speed) if math.isfinite(sound_speed) and sound_speed > 0 else math.nan,
            "reynoldsAtMach0p3ProxyIso": 0.3 * cs_iso * length / nu if nu > 0 else math.nan,
            "reynoldsAtMach0p3ProxyAd2D": 0.3 * cs_ad_2d * length / nu if nu > 0 else math.nan,
        })

    clean = {key: finite(value) for key, value in summary.items()}
    (analysis / "fluid_calibration_0493w1.json").write_text(json.dumps(clean, indent=2, sort_keys=True) + "\n")
    write_csv(analysis / "fluid_calibration_0493w1.csv", [clean])

    cs_display = f"{raw_sound_speed:.10g}" if sound_status != "INVALID" else "INVALID"
    report = [
        "# 0493w1 — SRC fluid calibration", "",
        f"Status: **{status}**", "",
        f"Property status: viscosity `{viscosity_status}`, sound `{sound_status}`, diffusion `{diffusion_status}`", "",
        f"Fluid variant: `{fluid_variant}`", "",
        "## Measured transport properties", "",
        f"- kinematic viscosity: `{nu:.10g}` (R² `{tg_result['fitR2']:.6g}`, window spread `{tg_result['nuWindowStd']:.4g}`)",
        f"- sound speed raw fit: `{cs_display}` from `{sound_result['soundReplicates']}` thermal realizations",
        f"- self-diffusion coefficient: `{diffusion:.10g}` (R² `{msd_result['fitR2']:.6g}`)",
        f"- Schmidt number: `{summary['Schmidt']:.10g}`", "",
        "## Longitudinal regression quality", "",
        f"- momentum relative RMS: `{sound_result['momentumRelativeRms']:.10g}`; score `{sound_result['momentumFitScore']:.10g}`",
        f"- continuity relative RMS: `{sound_result['continuityRelativeRms']:.10g}`; score `{sound_result['continuityFitScore']:.10g}`",
        f"- cumulative fit points/time span: `{sound_result['fitPoints']}` / `{sound_result['fitTimeSpan']:.10g}`",
        f"- regression condition number: `{sound_result['conditionNumber']:.10g}`; constraints `{sound_result['activeConstraints']}`",
        f"- sound jackknife std: `{sound_result['soundSpeedJackknifeStd']:.10g}`", "",
        "## Acoustic references", "",
        f"- isothermal ideal proxy: `{cs_iso:.10g}`",
        f"- adiabatic ideal-2D proxy: `{cs_ad_2d:.10g}`",
        f"- wavelength resolution: `{summary['soundWavelengthCells']:.10g}` cells", "",
        "## Kinetic scales", "",
        f"- mean thermal speed: `{vmean:.10g}`",
        f"- ballistic thermal displacement per collision step: `{vmean*a.dt:.10g}`",
        f"- mean-free-path proxy λ/a: `{summary['lambdaMeanOverCell']:.10g}`", "",
    ]
    if "Reynolds" in summary:
        report += ["## Requested flow scale", "", f"- Re: `{summary['Reynolds']:.10g}`"]
        if math.isfinite(summary.get("Mach", math.nan)):
            report.append(f"- measured Ma: `{summary['Mach']:.10g}`")
        else:
            report.append(f"- measured Ma: unavailable because sound status is `{sound_status}`")
        report += [
            f"- Ma proxy interval: `{summary['MachProxyAdiabatic2D']:.10g}` to `{summary['MachProxyIsothermal']:.10g}`",
            f"- Re attainable at Ma=0.3: `{summary.get('reynoldsAtMach0p3', math.nan)}`",
            f"- proxy Re at Ma=0.3: `{summary['reynoldsAtMach0p3ProxyIso']:.10g}` to `{summary['reynoldsAtMach0p3ProxyAd2D']:.10g}`",
            f"- Pe_mass: `{summary['PecletMass']:.10g}`", "",
        ]
    report += [
        "## Interpretation constraints", "",
        "- each property has its own PASS/REVIEW/INVALID status; an invalid sound fit never publishes a measured Mach number.",
        "- sound modes are averaged across independent thermal realizations before cumulative continuity/momentum regression.",
        "- the mean-free-path value is a ballistic displacement proxy over one SRC collision interval.",
        "- Q6 and resampling are disabled; thermostat settings are part of the effective-fluid definition.", "",
    ]
    (analysis / "README_0493w1_RESULTS.md").write_text("\n".join(report) + "\n")

    print("===== 0493w1 SRC FLUID CALIBRATION =====")
    print(f"status={status} viscosityStatus={viscosity_status} soundStatus={sound_status} diffusionStatus={diffusion_status}")
    print(f"fluidVariant={fluid_variant} nu={nu:.9g} csRaw={raw_sound_speed:.9g} Dself={diffusion:.9g} Sc={summary['Schmidt']:.9g}")
    print(f"soundReplicates={sound_result['soundReplicates']} momentumRelRms={sound_result['momentumRelativeRms']:.6g} continuityRelRms={sound_result['continuityRelativeRms']:.6g} condition={sound_result['conditionNumber']:.6g}")
    print(f"lambdaMean/a={summary['lambdaMeanOverCell']:.9g} csIso={cs_iso:.9g} csAd2D={cs_ad_2d:.9g}")
    if "Reynolds" in summary:
        ma_text = f"{summary['Mach']:.9g}" if math.isfinite(summary.get("Mach", math.nan)) else "unavailable"
        print(f"Re={summary['Reynolds']:.9g} Ma={ma_text} MaProxy={summary['MachProxyAdiabatic2D']:.6g}..{summary['MachProxyIsothermal']:.6g} ReAtMa0p3={summary.get('reynoldsAtMach0p3')}")
    print(f"result={analysis/'fluid_calibration_0493w1.csv'}")


if __name__ == "__main__":
    main()
