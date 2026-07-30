#!/usr/bin/env python3
"""0492b semantic checks for the injection runners.

The state check proves what is active in the generated initial state. The first
runtime diagnostic may already follow the step-zero boundary-reservoir update,
so the runtime check validates the allowed species and the final injection
contract rather than requiring the first runtime row to reproduce the state
file. It can optionally require a mixed cell in the final species-cell block.
"""

from __future__ import annotations

import argparse
import array
import csv
import math
import os
import struct
import sys
from collections import defaultdict
from pathlib import Path


MAGIC_PREFIX = b"SRCMPCD_STATE"
HEADER_FMT = "<IIIIQIIII"
HEADER_SIZE = struct.calcsize(HEADER_FMT)
RESERVED_SIZE = struct.calcsize("<8Q")


def fail(message: str) -> "NoReturn":
    raise SystemExit(f"[0492b-species-check] FAIL {message}")


def parse_int(value: str, label: str) -> int:
    try:
        return int(float(value))
    except (TypeError, ValueError) as exc:
        fail(f"invalid {label}={value!r}: {exc}")


def parse_float(value: str, label: str) -> float:
    try:
        result = float(value)
    except (TypeError, ValueError) as exc:
        fail(f"invalid {label}={value!r}: {exc}")
    if not math.isfinite(result):
        fail(f"non-finite {label}={value!r}")
    return result


def read_state_counts(path: Path) -> tuple[int, dict[int, int], int, int]:
    if not path.is_file():
        fail(f"missing state {path}")
    with path.open("rb") as stream:
        magic = stream.read(16)
        if not magic.startswith(MAGIC_PREFIX):
            fail(f"invalid state magic in {path}")
        raw_header = stream.read(HEADER_SIZE)
        if len(raw_header) != HEADER_SIZE:
            fail(f"truncated state header in {path}")
        header = struct.unpack(HEADER_FMT, raw_header)
        n_particles = int(header[4])
        if n_particles < 0:
            fail(f"negative particle count in {path}")
        reserved = stream.read(RESERVED_SIZE)
        if len(reserved) != RESERVED_SIZE:
            fail(f"truncated reserved block in {path}")

        # x,y,vx,vy: four double arrays.
        stream.seek(4 * 8 * n_particles, os.SEEK_CUR)
        types = array.array("I")
        try:
            types.fromfile(stream, n_particles)
        except EOFError:
            fail(f"truncated type array in {path}")
        if sys.byteorder != "little":
            types.byteswap()
        # mass: one double array.
        stream.seek(8 * n_particles, os.SEEK_CUR)
        roles = stream.read(n_particles)
        if len(roles) != n_particles:
            fail(f"truncated role array in {path}")

    fluid_by_type: dict[int, int] = defaultdict(int)
    inactive = 0
    latent = 0
    for particle_type, role in zip(types, roles):
        if role == 1:
            fluid_by_type[int(particle_type)] += 1
        elif role == 0:
            inactive += 1
        else:
            latent += 1
    return n_particles, dict(fluid_by_type), inactive, latent


def check_state(args: argparse.Namespace) -> None:
    path = Path(args.state)
    n_particles, counts, inactive, latent = read_state_counts(path)
    inject = counts.get(args.inject_type, 0)
    background = counts.get(args.background_type, 0)
    other = sum(count for typ, count in counts.items() if typ not in {args.inject_type, args.background_type})

    if args.scenario == "empty":
        if inject != 0 or background != 0 or other != 0:
            fail(
                "empty scenario contains active fluid: "
                f"inject={inject} background={background} other={other}"
            )
    elif args.scenario == "two_species":
        if inject != 0:
            fail(f"two_species initial state already contains injected type {args.inject_type}: {inject}")
        if background <= 0:
            fail(f"two_species initial state lacks background type {args.background_type}")
        if other != 0:
            fail(f"two_species initial state contains {other} unrequested active particles")
    else:
        fail(f"unsupported scenario {args.scenario}")

    print(
        "[0492b-species-state] PASS "
        f"scenario={args.scenario} total={n_particles} fluidInject={inject} "
        f"fluidBackground={background} inactive={inactive} latent={latent}"
    )


def read_species_runtime(path: Path) -> tuple[int, int, dict[int, dict[str, str]], dict[int, dict[str, str]]]:
    if not path.is_file():
        fail(f"missing species runtime CSV {path}")
    with path.open(newline="") as stream:
        reader = csv.DictReader(stream)
        required = {
            "step",
            "type",
            "phaseFamily",
            "q6StrengthDeclared",
            "resamplingMassClosureStrengthDeclared",
            "nFluid",
            "totalMass",
        }
        if reader.fieldnames is None or not required.issubset(reader.fieldnames):
            fail(f"species runtime CSV lacks required columns: {path}")
        by_step: dict[int, dict[int, dict[str, str]]] = defaultdict(dict)
        for row in reader:
            step = parse_int(row["step"], "step")
            particle_type = parse_int(row["type"], "type")
            by_step[step][particle_type] = row
    if not by_step:
        fail(f"empty species runtime CSV {path}")
    first_step = min(by_step)
    last_step = max(by_step)
    return first_step, last_step, by_step[first_step], by_step[last_step]


def close_enough(actual: float, expected: float, tolerance: float = 1.0e-12) -> bool:
    scale = max(1.0, abs(actual), abs(expected))
    return abs(actual - expected) <= tolerance * scale


def final_mixed_cells(path: Path, inject_type: int, background_type: int) -> tuple[int, int]:
    if not path.is_file():
        fail(f"missing species-cell CSV {path}")
    last_step: int | None = None
    masses: dict[int, dict[int, float]] = defaultdict(dict)
    with path.open(newline="") as stream:
        reader = csv.DictReader(stream)
        required = {"step", "cell", "type", "mass"}
        if reader.fieldnames is None or not required.issubset(reader.fieldnames):
            fail(f"species-cell CSV lacks required columns: {path}")
        for row in reader:
            step = parse_int(row["step"], "step")
            if last_step is None or step != last_step:
                if last_step is not None and step < last_step:
                    fail(f"species-cell steps are not ordered in {path}")
                masses.clear()
                last_step = step
            particle_type = parse_int(row["type"], "type")
            if particle_type not in {inject_type, background_type}:
                continue
            cell = parse_int(row["cell"], "cell")
            masses[cell][particle_type] = parse_float(row["mass"], "mass")
    if last_step is None:
        fail(f"empty species-cell CSV {path}")
    mixed = 0
    wet = 0
    for cell_masses in masses.values():
        inject_mass = cell_masses.get(inject_type, 0.0)
        background_mass = cell_masses.get(background_type, 0.0)
        if inject_mass > 0.0 or background_mass > 0.0:
            wet += 1
        if inject_mass > 0.0 and background_mass > 0.0:
            mixed += 1
    return last_step, mixed


def check_runtime(args: argparse.Namespace) -> None:
    first_step, last_step, first_rows, last_rows = read_species_runtime(Path(args.csv))
    for particle_type, label in ((args.inject_type, "inject"), (args.background_type, "background")):
        if particle_type not in first_rows or particle_type not in last_rows:
            fail(f"missing registered {label} type {particle_type} in runtime CSV")

    inject_first = parse_int(first_rows[args.inject_type]["nFluid"], "inject nFluid first")
    background_first = parse_int(first_rows[args.background_type]["nFluid"], "background nFluid first")
    inject_last = parse_int(last_rows[args.inject_type]["nFluid"], "inject nFluid last")
    background_last = parse_int(last_rows[args.background_type]["nFluid"], "background nFluid last")
    inject_mass_last = parse_float(last_rows[args.inject_type]["totalMass"], "inject totalMass last")
    background_mass_last = parse_float(last_rows[args.background_type]["totalMass"], "background totalMass last")

    inject_phase = last_rows[args.inject_type]["phaseFamily"].strip().lower()
    background_phase = last_rows[args.background_type]["phaseFamily"].strip().lower()
    inject_q6 = parse_float(
        last_rows[args.inject_type]["q6StrengthDeclared"],
        "inject q6 strength",
    )
    background_q6 = parse_float(
        last_rows[args.background_type]["q6StrengthDeclared"],
        "background q6 strength",
    )
    inject_closure = parse_float(
        last_rows[args.inject_type]["resamplingMassClosureStrengthDeclared"],
        "inject closure",
    )
    background_closure = parse_float(
        last_rows[args.background_type]["resamplingMassClosureStrengthDeclared"],
        "background closure",
    )
    if inject_phase != args.inject_phase:
        fail(f"inject phase {inject_phase} != expected {args.inject_phase}")
    if background_phase != args.background_phase:
        fail(f"background phase {background_phase} != expected {args.background_phase}")
    if not close_enough(inject_q6, args.inject_q6):
        fail(f"inject q6 strength {inject_q6} != expected {args.inject_q6}")
    if not close_enough(background_q6, args.background_q6):
        fail(f"background q6 strength {background_q6} != expected {args.background_q6}")
    if not close_enough(inject_closure, args.inject_closure):
        fail(f"inject closure {inject_closure} != expected {args.inject_closure}")
    if not close_enough(background_closure, args.background_closure):
        fail(f"background closure {background_closure} != expected {args.background_closure}")

    for label, count in (
        ("inject first", inject_first),
        ("background first", background_first),
        ("inject last", inject_last),
        ("background last", background_last),
    ):
        if count < 0:
            fail(f"negative runtime population for {label}: {count}")

    if args.scenario == "empty":
        # The generated state is checked separately and is strictly empty.
        # The first runtime row may already include the step-zero inlet
        # reservoir fill, but it must never activate the background species.
        if background_first != 0:
            fail(
                "empty runtime activated background species at first recorded step: "
                f"n={background_first}"
            )
        if inject_last <= 0 or inject_mass_last <= 0.0:
            fail("empty runtime did not inject type 1")
        if background_last != 0 or background_mass_last != 0.0:
            fail(
                "empty runtime unexpectedly activated background species: "
                f"n={background_last} mass={background_mass_last}"
            )
    elif args.scenario == "two_species":
        # The state check proves that type 1 was absent initially. At the first
        # runtime record, step-zero boundary insertion may already have added it.
        if background_first <= 0:
            fail("two_species runtime first recorded background is empty")
        if inject_last <= 0 or inject_mass_last <= 0.0:
            fail("two_species runtime did not inject type 1")
        if background_last <= 0 or background_mass_last <= 0.0:
            fail("two_species runtime lost all type-2 background gas")
    else:
        fail(f"unsupported scenario {args.scenario}")

    mixed_text = "not_checked"
    if args.require_mixed_cell:
        if not args.cell_csv:
            fail("--require-mixed-cell requires --cell-csv")
        cell_step, mixed = final_mixed_cells(
            Path(args.cell_csv), args.inject_type, args.background_type
        )
        if cell_step != last_step:
            fail(f"species-cell last step {cell_step} != species-runtime last step {last_step}")
        if mixed <= 0:
            fail("no mixed injected/background cell at final step")
        mixed_text = str(mixed)

    print(
        "[0492b-species-runtime] PASS "
        f"scenario={args.scenario} steps={first_step}->{last_step} "
        f"inject={inject_first}->{inject_last} background={background_first}->{background_last} "
        f"phases={inject_phase}/{background_phase} "
        f"massInject={inject_mass_last:.17g} massBackground={background_mass_last:.17g} "
        f"mixedCells={mixed_text}"
    )


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)

    state = subparsers.add_parser("state")
    state.add_argument("--state", required=True)
    state.add_argument("--scenario", choices=("empty", "two_species"), required=True)
    state.add_argument("--inject-type", type=int, required=True)
    state.add_argument("--background-type", type=int, required=True)
    state.set_defaults(func=check_state)

    runtime = subparsers.add_parser("runtime")
    runtime.add_argument("--csv", required=True)
    runtime.add_argument("--scenario", choices=("empty", "two_species"), required=True)
    runtime.add_argument("--inject-type", type=int, required=True)
    runtime.add_argument("--background-type", type=int, required=True)
    runtime.add_argument("--inject-phase", choices=("liquid", "gas"), required=True)
    runtime.add_argument("--background-phase", choices=("liquid", "gas"), required=True)
    runtime.add_argument("--inject-q6", type=float, required=True)
    runtime.add_argument("--background-q6", type=float, required=True)
    runtime.add_argument("--inject-closure", type=float, required=True)
    runtime.add_argument("--background-closure", type=float, required=True)
    runtime.add_argument("--cell-csv")
    runtime.add_argument("--require-mixed-cell", action="store_true")
    runtime.set_defaults(func=check_runtime)
    return parser


def main() -> None:
    args = build_parser().parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
