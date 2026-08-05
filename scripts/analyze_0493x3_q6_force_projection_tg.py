#!/usr/bin/env python3
"""Compare legacy and prestream-force Q6 Taylor--Green dumps, 0493x3."""
from __future__ import annotations

import argparse
import csv
import hashlib
import math
import re
from pathlib import Path

from analyze_periodic_modes_0438 import FLUID_ROLE, modal_amplitude, read_smpcd


def step_map(case_root: Path) -> dict[int, Path]:
    result: dict[int, Path] = {}
    for path in (case_root / "output").glob("state_step_*.smpcd"):
        match = re.search(r"state_step_(\d+)\.smpcd$", path.name)
        if match:
            result[int(match.group(1))] = path
    return result


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def periodic_delta(a: float, b: float, length: float) -> float:
    d = a - b
    return d - length * round(d / length)


def state_difference(a: dict[str, object], b: dict[str, object], lx: float, ly: float) -> tuple[float, float, float, float]:
    if int(a["n"]) != int(b["n"]):
        raise RuntimeError("particle counts differ")
    n = int(a["n"])
    pos2 = vel2 = 0.0
    max_pos = max_vel = 0.0
    count = 0
    for i in range(n):
        if a["role"][i] != FLUID_ROLE or b["role"][i] != FLUID_ROLE:  # type: ignore[index]
            continue
        dx = periodic_delta(a["x"][i], b["x"][i], lx)  # type: ignore[index]
        dy = periodic_delta(a["y"][i], b["y"][i], ly)  # type: ignore[index]
        dvx = a["vx"][i] - b["vx"][i]  # type: ignore[index]
        dvy = a["vy"][i] - b["vy"][i]  # type: ignore[index]
        dp = math.hypot(dx, dy)
        dv = math.hypot(dvx, dvy)
        pos2 += dp * dp
        vel2 += dv * dv
        max_pos = max(max_pos, dp)
        max_vel = max(max_vel, dv)
        count += 1
    denom = max(1, count)
    return math.sqrt(pos2 / denom), max_pos, math.sqrt(vel2 / denom), max_vel


def compare_pair(root: Path, label: str, legacy_name: str, pre_name: str, lx: float, ly: float) -> list[dict[str, object]]:
    legacy = step_map(root / legacy_name)
    pre = step_map(root / pre_name)
    steps = sorted(set(legacy) & set(pre))
    if not steps:
        raise RuntimeError(f"{label}: no common dumps")
    rows: list[dict[str, object]] = []
    for step in steps:
        legacy_path = legacy[step]
        pre_path = pre[step]
        hash_equal = sha256(legacy_path) == sha256(pre_path)
        state_legacy = read_smpcd(legacy_path)
        state_pre = read_smpcd(pre_path)
        mode_legacy = modal_amplitude(state_legacy, "tg", lx, ly)
        mode_pre = modal_amplitude(state_pre, "tg", lx, ly)
        pos_rms, pos_max, vel_rms, vel_max = state_difference(
            state_legacy, state_pre, lx, ly
        )
        amp_legacy = mode_legacy["amp"]
        amp_pre = mode_pre["amp"]
        amp_rel = (
            (amp_pre - amp_legacy) / max(abs(amp_legacy), 1.0e-300)
            if math.isfinite(amp_legacy) and math.isfinite(amp_pre)
            else float("nan")
        )
        rows.append(
            {
                "pair": label,
                "step": step,
                "hashEqual": int(hash_equal),
                "ampLegacy": amp_legacy,
                "ampPrestream": amp_pre,
                "ampRelativeDifference": amp_rel,
                "positionRmsDifference": pos_rms,
                "positionMaxDifference": pos_max,
                "velocityRmsDifference": vel_rms,
                "velocityMaxDifference": vel_max,
            }
        )
    return rows


def fmt(value: object) -> str:
    if isinstance(value, float):
        return f"{value:.17g}" if math.isfinite(value) else "nan"
    return str(value)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--Lx", type=float, required=True)
    parser.add_argument("--Ly", type=float, required=True)
    parser.add_argument("--csv", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    parser.add_argument("--fail-on-null-mismatch", type=int, default=1)
    args = parser.parse_args()

    null_rows = compare_pair(
        args.root, "null", "null_legacy", "null_prestream", args.Lx, args.Ly
    )
    forced_rows = compare_pair(
        args.root, "forced", "forced_legacy", "forced_prestream", args.Lx, args.Ly
    )
    rows = null_rows + forced_rows
    args.csv.parent.mkdir(parents=True, exist_ok=True)
    fieldnames = list(rows[0])
    with args.csv.open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)

    null_exact = all(int(row["hashEqual"]) == 1 for row in null_rows)
    max_forced_amp = max(abs(float(row["ampRelativeDifference"])) for row in forced_rows)
    max_forced_pos = max(float(row["positionRmsDifference"]) for row in forced_rows)
    max_forced_vel = max(float(row["velocityRmsDifference"]) for row in forced_rows)
    final_forced = forced_rows[-1]
    report = [
        "# 0493x3 Q6 force-projection Taylor–Green comparison",
        "",
        f"- Null-force bitwise identity: **{'PASS' if null_exact else 'FAIL'}**",
        f"- Common null dumps compared: {len(null_rows)}",
        f"- Common forced dumps compared: {len(forced_rows)}",
        f"- Maximum forced modal relative difference: `{max_forced_amp:.6e}`",
        f"- Maximum forced position RMS difference: `{max_forced_pos:.6e}`",
        f"- Maximum forced velocity RMS difference: `{max_forced_vel:.6e}`",
        f"- Final forced legacy amplitude: `{fmt(final_forced['ampLegacy'])}`",
        f"- Final forced prestream amplitude: `{fmt(final_forced['ampPrestream'])}`",
        "",
        "The forced comparison is descriptive: no physical acceptance threshold is imposed by this script.",
    ]
    args.report.write_text("\n".join(report) + "\n", encoding="utf-8")
    print(
        f"[0493x3-analysis] nullExact={int(null_exact)} "
        f"forcedMaxAmpRel={max_forced_amp:.6e} "
        f"forcedMaxPosRms={max_forced_pos:.6e} "
        f"forcedMaxVelRms={max_forced_vel:.6e}"
    )
    if args.fail_on_null_mismatch and not null_exact:
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
