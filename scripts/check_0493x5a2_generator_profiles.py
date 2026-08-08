#!/usr/bin/env python3
"""Small deterministic regression check for 0493x0 generator profiles."""

from __future__ import annotations

import argparse
import json
import subprocess
import tempfile
from pathlib import Path


def run_case(root: Path, work: Path, name: str, extra: list[str]) -> dict[str, object]:
    state = work / f"{name}.smpcd"
    cmd = [
        "python3", str(root / "scripts/generate_0493x0_dam_break_state.py"),
        "--output", str(state), "--Lx", "1", "--Ly", "1",
        "--nx", "8", "--ny", "4", "--gamma", "4",
        "--column-width", "0.5", "--column-height", "0.5",
        "--liquid-mass", "10", "--gas-mass", "1", "--kBT", "0.01",
        "--seed", "493952",
        *extra,
    ]
    subprocess.run(cmd, check=True, cwd=root, stdout=subprocess.DEVNULL)
    return json.loads(state.with_suffix(".smpcd.json").read_text())


def expect(meta: dict[str, object], **values: object) -> None:
    for key, expected in values.items():
        actual = meta.get(key)
        if actual != expected:
            raise RuntimeError(f"{meta.get('profile')}: {key}={actual!r}, expected {expected!r}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    args = parser.parse_args()
    root = args.root.resolve()
    with tempfile.TemporaryDirectory(prefix="0493x5a2-generator-") as tmp:
        work = Path(tmp)
        normal = run_case(root, work, "normal", [])
        liquid = run_case(root, work, "liquid", ["--liquid-only"])
        partial = run_case(root, work, "partial", ["--liquid-only", "--liquid-fill-height", "0.5"])
        empty_column = run_case(root, work, "empty_column", ["--empty-outside-column"])

    # 8x4 cells, gamma=4. The 0.5x0.5 column occupies 4x2=8 cells.
    expect(normal, profile="dam_break", fluid_particles=128, liquid_particles=32,
           gas_particles=96, empty_cells=0)
    expect(liquid, profile="liquid_only", fluid_particles=128, liquid_particles=128,
           gas_particles=0, empty_cells=0)
    expect(partial, profile="partial_liquid", fluid_particles=64, liquid_particles=64,
           gas_particles=0, empty_cells=16)
    expect(empty_column, profile="dam_break_empty", fluid_particles=32, liquid_particles=32,
           gas_particles=0, empty_cells=24)
    for meta in (normal, liquid, partial, empty_column):
        if abs(float(meta["total_momentum_x"])) > 1.0e-12 or abs(float(meta["total_momentum_y"])) > 1.0e-12:
            raise RuntimeError(f"{meta['profile']}: nonzero generated momentum")
    print("[0493x5a2-generator] PASS profiles=4")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
