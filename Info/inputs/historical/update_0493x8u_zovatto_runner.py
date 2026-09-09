#!/usr/bin/env python3
"""0493x8u: align the restartable Zovatto runner with the validated x8t BCs.

Temporary semantic updater. Standard library only. No Git working-tree guard.
"""
from pathlib import Path
import sys

ROOT = Path.cwd()
TARGET = ROOT / "scripts" / "run_0493x8m_zovatto_re280_restart.sh"

if not TARGET.is_file():
    raise SystemExit(f"[0493x8u] missing target: {TARGET}")

text = TARGET.read_text()
original = text

replacements = [
    (
        "#   outlet: passive segmented Neumann from 0493x8l\n",
        "#   outlet: passive segmented Neumann kinetic-pressure closure from 0493x8q-x8t\n",
    ),
    (
        'RUN_MODES="src-q6-g-f"\n',
        'RUN_MODES="${RUN_MODES:-src-q6-g-f}"\n',
    ),
    (
        'INLET_RESERVOIR_CELLS="${INLET_RESERVOIR_CELLS:-6}"\n',
        'INLET_RESERVOIR_CELLS="${INLET_RESERVOIR_CELLS:-6}"\n'
        'INLET_THERMAL_NOISE="${INLET_THERMAL_NOISE:-1.0}"\n',
    ),
    (
        'print("BC inlet=local Poiseuille full-height; outlet=0493x8l passive right Neumann")\n',
        'print("BC inlet=local Poiseuille full-height; outlet=0493x8q-x8t passive kinetic-pressure Neumann")\n',
    ),
    (
        '# x8l ignores this nominal outlet velocity as a physical Q6-G-F target when\n'
        '# OUTLET_MODE=neumann; keep Umean only for legacy metadata/diagnostic balance.\n',
        '# x8q-x8t ignores this nominal outlet velocity as a physical final target when\n'
        '# OUTLET_MODE=neumann; keep Umean only for legacy metadata/diagnostic balance.\n',
    ),
    (
        'inletThermalNoise = 0.0\n',
        'inletThermalNoise = ${INLET_THERMAL_NOISE}\n',
    ),
    (
        '  local mode="src-q6-g-f"\n',
        '  local mode="${RUN_MODES:-src-q6-g-f}"\n',
    ),
    (
        'X8M_INLET_PROFILE=${INLET_PROFILE}\n'
        'X8M_OUTLET=${OUTLET_FACE}:${OUTLET_SMIN}:${OUTLET_SMAX}:${OUTLET_MODE}:passive_x8l\n',
        'X8M_INLET_PROFILE=${INLET_PROFILE}\n'
        'X8M_INLET_THERMAL_NOISE=${INLET_THERMAL_NOISE}\n'
        'X8M_OUTLET=${OUTLET_FACE}:${OUTLET_SMIN}:${OUTLET_SMAX}:${OUTLET_MODE}:kinetic_pressure_x8t\n',
    ),
    (
        '  echo "[0493x8m] inlet Poiseuille Umax=$UMAX Umean=$UMEAN -> passive right Neumann"\n',
        '  echo "[0493x8m] inlet Poiseuille Umax=$UMAX Umean=$UMEAN thermalNoise=$INLET_THERMAL_NOISE -> passive kinetic-pressure Neumann"\n',
    ),
]

for old, new in replacements:
    if old in text:
        text = text.replace(old, new, 1)
    elif new in text:
        # Idempotent re-run: this replacement is already present.
        pass
    else:
        raise SystemExit(
            "[0493x8u] target does not match expected current runner; missing marker:\n"
            + old
        )

if text == original:
    print(f"[0493x8u] already applied: {TARGET}")
    raise SystemExit(0)

TARGET.write_text(text)
print(f"[0493x8u] updated: {TARGET}")
print("[0493x8u] changes: RUN_MODES override, thermal inlet default=1.0, x8t outlet metadata/comments")
