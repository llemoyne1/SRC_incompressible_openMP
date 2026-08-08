#!/usr/bin/env python3
"""Particle-level state comparison for x6g zero/gauge validations."""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path

from analyze_periodic_modes_0438 import FLUID_ROLE, read_smpcd


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--reference", type=Path, required=True)
    ap.add_argument("--candidate", type=Path, required=True)
    ap.add_argument("--json", type=Path, required=True)
    ap.add_argument("--max-position", type=float, default=1.0e-12)
    ap.add_argument("--max-velocity", type=float, default=1.0e-12)
    ap.add_argument("--require-hash", type=int, default=0)
    args = ap.parse_args()

    a = read_smpcd(args.reference)
    b = read_smpcd(args.candidate)
    if int(a["n"]) != int(b["n"]):
        raise RuntimeError("particle counts differ")
    n = int(a["n"])
    pos2 = vel2 = 0.0
    pos_max = vel_max = 0.0
    compared = 0
    for i in range(n):
        if a["role"][i] != b["role"][i]:  # type: ignore[index]
            raise RuntimeError(f"particle {i}: role mismatch")
        if a["mass"][i] != b["mass"][i]:  # type: ignore[index]
            raise RuntimeError(f"particle {i}: mass/species mismatch")
        if a["role"][i] != FLUID_ROLE:  # type: ignore[index]
            continue
        dx = a["x"][i] - b["x"][i]  # type: ignore[index]
        dy = a["y"][i] - b["y"][i]  # type: ignore[index]
        dvx = a["vx"][i] - b["vx"][i]  # type: ignore[index]
        dvy = a["vy"][i] - b["vy"][i]  # type: ignore[index]
        dp = math.hypot(dx, dy)
        dv = math.hypot(dvx, dvy)
        pos2 += dp * dp
        vel2 += dv * dv
        pos_max = max(pos_max, dp)
        vel_max = max(vel_max, dv)
        compared += 1
    pos_rms = math.sqrt(pos2 / max(1, compared))
    vel_rms = math.sqrt(vel2 / max(1, compared))
    hash_equal = sha256(args.reference) == sha256(args.candidate)
    passed = (
        pos_max <= args.max_position
        and vel_max <= args.max_velocity
        and (hash_equal or not args.require_hash)
    )
    report = {
        "status": "PASS" if passed else "FAIL",
        "hashEqual": hash_equal,
        "fluidParticlesCompared": compared,
        "positionRmsDifference": pos_rms,
        "positionMaxDifference": pos_max,
        "velocityRmsDifference": vel_rms,
        "velocityMaxDifference": vel_max,
        "positionTolerance": args.max_position,
        "velocityTolerance": args.max_velocity,
        "requireHash": bool(args.require_hash),
    }
    args.json.parent.mkdir(parents=True, exist_ok=True)
    args.json.write_text(json.dumps(report, indent=2) + "\n")
    print(
        "[0493x6g-state-compare] "
        f"status={report['status']} hashEqual={int(hash_equal)} "
        f"posRms={pos_rms:.3e} posMax={pos_max:.3e} "
        f"velRms={vel_rms:.3e} velMax={vel_max:.3e}"
    )
    return 0 if passed else 2


if __name__ == "__main__":
    raise SystemExit(main())
