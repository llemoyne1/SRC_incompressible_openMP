#!/usr/bin/env python3
"""Static/math checks for 0493x14ba global inlet oscillation."""
from __future__ import annotations

import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def require(path: str, needles: list[str]) -> None:
    text = (ROOT / path).read_text()
    for needle in needles:
        if needle not in text:
            raise SystemExit(f"[0493x14ba-check] ERROR {path}: missing {needle!r}")


def osc(t: float, *, amp: float, period: float, phase: float = 0.0,
        start: float = 0.0, offset: float = 0.0) -> float:
    teff = t + offset
    if teff < start:
        return 1.0
    return 1.0 + amp * math.sin(2.0 * math.pi * (teff - start) / period + phase)


require("include/simulation_params.h", [
    "inletVelocityOscillationEnable",
    "inletVelocityOscillationAmplitude",
    "inletVelocityOscillationPeriod",
    "inletVelocityOscillationPhase",
    "inletVelocityOscillationStartTime",
    "inletVelocityOscillationTimeOffset",
])
require("src/params_io_base.cpp", [
    'key == "inletVelocityOscillationEnable"',
    'key == "inletOscillationEnable"',
    'inletVelocityOscillationAmplitude must be in [0,1]',
    'inletVelocityOscillationPeriod must be > 0',
])
require("src/boundary_base.cpp", [
    "inlet_velocity_oscillation_factor_0493x14ba",
    "inlet_velocity_time_factor_0493x14ba",
])
require("src/q6_projection_adapter.cpp", [
    "inlet_velocity_oscillation_factor_0493x14ba",
    "inlet_velocity_time_factor_0493x14ba",
])
require("src/cuda_q6_resident_0400.cu", [
    "inlet_velocity_oscillation_factor_0493x14ba_0400",
    "inlet_velocity_time_factor_0493x14ba_0400",
])
require("src/cuda_classic_src_io_resident_0263.cu", [
    "oscillationEnable",
    "oscillationAmplitude",
    "oscillationPeriod",
    "oscillationPhase",
    "oscillationStartTime",
    "oscillationTimeOffset",
    "inlet_time_factor_device_0493x14ba",
])
require("scripts/run_0493x14ay_basilisk_atomisation_gamma_refinement.sh", [
    "BASILISK_PULSE_RUNTIME_ENABLE",
    "inletVelocityOscillationEnable = $BASILISK_PULSE_RUNTIME_ENABLE",
    "inletVelocityOscillationPeriod = $PULSE_PERIOD",
    "inletVelocityOscillationTimeOffset = $INLET_OSCILLATION_TIME_OFFSET",
])

A = 0.05
T = 0.4
expected = [1.0, 1.0 + A, 1.0, 1.0 - A, 1.0]
for t, ref in zip([0.0, T/4.0, T/2.0, 3.0*T/4.0, T], expected):
    got = osc(t, amp=A, period=T)
    if not math.isclose(got, ref, rel_tol=0.0, abs_tol=2e-15):
        raise SystemExit(f"[0493x14ba-check] ERROR sine sample t={t}: {got} != {ref}")

# Before start: exactly neutral.
if osc(0.3, amp=A, period=T, start=0.5) != 1.0:
    raise SystemExit("[0493x14ba-check] ERROR pre-start factor is not exactly 1")

# Restart continuity: local time + offset must equal uninterrupted global time.
restart_time = 1.237
for local in [0.0, 0.013, 0.117, 0.401]:
    a = osc(restart_time + local, amp=A, period=T, phase=0.31, start=0.2)
    b = osc(local, amp=A, period=T, phase=0.31, start=0.2, offset=restart_time)
    if not math.isclose(a, b, rel_tol=0.0, abs_tol=2e-15):
        raise SystemExit("[0493x14ba-check] ERROR restart phase continuity")

print("[0493x14ba-check] PASS static propagation + sine samples + restart phase continuity")
