#!/usr/bin/env python3
"""Collate the generic 0493x13a SRC-only A0-A6 high-Re presweep.

No application-specific U or L is assumed.  The main capability metric is

    H_h = c_s h / nu,

so that for a characteristic length spanning N=L/h collision cells,

    Re = Ma * N * H_h.

Only Python's standard library is used.
"""
from __future__ import annotations

import argparse
import csv
import json
import math
import re
from pathlib import Path


def read_csv_one(path: Path) -> dict[str, str]:
    with path.open(newline="") as f:
        return next(csv.DictReader(f))


def read_csv_all(path: Path) -> list[dict[str, str]]:
    with path.open(newline="") as f:
        return list(csv.DictReader(f))


def num(row: dict[str, object], key: str) -> float:
    try:
        value = row.get(key, "")
        if value is None or value == "":
            return math.nan
        return float(value)
    except (TypeError, ValueError):
        return math.nan


def finite(x: float) -> bool:
    return math.isfinite(x)


def ratio(a: float, b: float) -> float:
    return a / b if finite(a) and finite(b) and b != 0 else math.nan


def elapsed_seconds(case_root: Path) -> tuple[float, int]:
    total = 0.0
    count = 0
    rx = re.compile(r"(?:^|\s)elapsed=([0-9.eE+-]+)")
    for path in sorted(case_root.glob("*/logs/time_0493w1.txt")):
        text = path.read_text(errors="replace")
        m = rx.search(text)
        if m:
            try:
                total += float(m.group(1))
                count += 1
            except ValueError:
                pass
    return total, count


def lambda_band(x: float) -> str:
    if not finite(x):
        return "UNKNOWN"
    if x < 0.5:
        return "LT_0P5"
    if x < 1.0:
        return "0P5_TO_1"
    if x < 2.0:
        return "1_TO_2"
    if x < 3.0:
        return "2_TO_3"
    return "GE_3"


def sc_band(x: float) -> str:
    if not finite(x):
        return "UNKNOWN"
    if x >= 5.0:
        return "GE_5"
    if x >= 3.0:
        return "3_TO_5"
    if x >= 2.0:
        return "2_TO_3"
    return "LT_2"


def property_grade(row: dict[str, str]) -> str:
    statuses = [row.get("viscosityStatus", ""), row.get("soundStatus", ""), row.get("diffusionStatus", "")]
    if any(s == "INVALID" or not s for s in statuses):
        return "INVALID"
    if all(s == "PASS" for s in statuses):
        return "PASS"
    return "REVIEW"


def write_csv(path: Path, rows: list[dict[str, object]]) -> None:
    keys: list[str] = []
    for row in rows:
        for key in row:
            if key not in keys:
                keys.append(key)
    with path.open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=keys)
        w.writeheader()
        w.writerows(rows)


def fmt(x: object, sig: int = 5) -> str:
    try:
        v = float(x)
    except (TypeError, ValueError):
        return "—"
    return f"{v:.{sig}g}" if math.isfinite(v) else "—"


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--root", type=Path, required=True)
    args = p.parse_args()

    manifest_path = args.root / "manifest_0493x13a.csv"
    if not manifest_path.is_file():
        raise SystemExit(f"[0493x13a] missing manifest: {manifest_path}")
    manifest = {r["case"]: r for r in read_csv_all(manifest_path)}

    raw: list[dict[str, object]] = []
    for case in ("A0", "A1", "A2", "A3", "A4", "A5", "A6"):
        result = args.root / case / "analysis" / "fluid_calibration_0493w1.csv"
        if not result.is_file():
            continue
        src = read_csv_one(result)
        m = manifest[case]

        nu = num(src, "viscosityKinematic")
        nu_srd = num(m, "viscositySRDKinematic")
        diff = num(src, "selfDiffusion")
        sc = num(src, "Schmidt")
        cs = num(src, "soundSpeed")
        cs_raw = num(src, "soundSpeedRawFit")
        h = num(src, "cellSizeGeom")
        lam = num(src, "lambdaMeanOverCell")
        dt = num(src, "dt")
        hydro = cs * h / nu if finite(cs) and finite(h) and nu > 0 else math.nan
        hydro_raw = cs_raw * h / nu if finite(cs_raw) and finite(h) and nu > 0 else math.nan
        elapsed, elapsed_files = elapsed_seconds(args.root / case)
        particle_steps = num(m, "estimatedParticleSteps")
        elapsed_per_1e9 = elapsed / (particle_steps / 1e9) if elapsed > 0 and particle_steps > 0 else math.nan

        raw.append({
            "case": case,
            "role": m.get("role", ""),
            "propertyGrade": property_grade(src),
            "status0493w1": src.get("status", ""),
            "viscosityStatus": src.get("viscosityStatus", ""),
            "soundStatus": src.get("soundStatus", ""),
            "diffusionStatus": src.get("diffusionStatus", ""),
            "gamma": src.get("gamma", m.get("gamma", "")),
            "rotationAngleDeg": src.get("rotationAngleDeg", m.get("rotationAngleDeg", "")),
            "dt": dt,
            "cellSize": h,
            "targetLambdaMeanOverCell": num(m, "targetLambdaMeanOverCell"),
            "lambdaMeanOverCell": lam,
            "lambdaBand": lambda_band(lam),
            "viscosityKinematic": nu,
            "viscositySRDKinematic": nu_srd,
            "measuredNuOverSRD": ratio(nu, nu_srd),
            "viscosityFitR2": num(src, "viscosityFitR2"),
            "viscosityWindowStd": num(src, "viscosityWindowStd"),
            "soundSpeed": cs,
            "soundSpeedRawFit": cs_raw,
            "soundMomentumRelativeRms": num(src, "soundMomentumRelativeRms"),
            "soundContinuityRelativeRms": num(src, "soundContinuityRelativeRms"),
            "soundRegressionConditionNumber": num(src, "soundRegressionConditionNumber"),
            "soundCFLCell": num(src, "soundCFLCell"),
            "selfDiffusion": diff,
            "diffusionFitR2": num(src, "diffusionFitR2"),
            "msdFinalAlpha2": num(src, "msdFinalAlpha2"),
            "Schmidt": sc,
            "SchmidtBand": sc_band(sc),
            "hydrodynamicReachPerCell": hydro,
            "hydrodynamicReachPerCellRawSound": hydro_raw,
            "RePerCellAtMa0p1": 0.1 * hydro if finite(hydro) else math.nan,
            "RePerCellAtMa0p2": 0.2 * hydro if finite(hydro) else math.nan,
            "RePerCellAtMa0p3": 0.3 * hydro if finite(hydro) else math.nan,
            "collisionFrequency": 1.0 / dt if dt > 0 else math.nan,
            "estimatedParticleSteps": particle_steps,
            "elapsedSecondsTotal": elapsed if elapsed_files else math.nan,
            "elapsedTimingFiles": elapsed_files,
            "elapsedSecPer1e9ParticleSteps": elapsed_per_1e9,
            "resultPath": str(result),
        })

    if not raw:
        raise SystemExit("[0493x13a] no A0-A6 calibration results found")

    ref = next((r for r in raw if r["case"] == "A0"), None)
    ref_nu = num(ref, "viscosityKinematic") if ref else math.nan
    ref_hydro = num(ref, "hydrodynamicReachPerCell") if ref else math.nan
    ref_elapsed = num(ref, "elapsedSecondsTotal") if ref else math.nan
    for row in raw:
        nu = num(row, "viscosityKinematic")
        hydro = num(row, "hydrodynamicReachPerCell")
        elapsed = num(row, "elapsedSecondsTotal")
        row["viscosityReductionVsA0"] = ratio(ref_nu, nu)
        row["hydrodynamicReachGainVsA0"] = ratio(hydro, ref_hydro)
        row["wallSpeedupVsA0"] = ratio(ref_elapsed, elapsed)

    # Ranking is descriptive, not a physical accept/reject rule: fit validity first, then intrinsic H_h.
    grade_order = {"PASS": 0, "REVIEW": 1, "INVALID": 2}
    ranked = sorted(
        raw,
        key=lambda r: (
            grade_order.get(str(r["propertyGrade"]), 3),
            -(num(r, "hydrodynamicReachPerCell") if finite(num(r, "hydrodynamicReachPerCell")) else -1.0),
        ),
    )
    for i, row in enumerate(ranked, 1):
        row["hydrodynamicReachRank"] = i

    analysis = args.root / "analysis"
    analysis.mkdir(parents=True, exist_ok=True)
    csv_path = analysis / "high_re_presweep_0493x13a.csv"
    json_path = analysis / "high_re_presweep_0493x13a.json"
    md_path = analysis / "README_0493X13A_HIGH_RE_PRESWEEP.md"
    write_csv(csv_path, ranked)
    json_path.write_text(json.dumps(ranked, indent=2, allow_nan=True) + "\n")

    lines = [
        "# 0493x13a — SRC-only high-Re presweep A0-A6",
        "",
        "This report is deliberately application-independent.  For a characteristic length spanning `N=L/h` collision cells,",
        "",
        "`Re = Ma * N * H_h`, with `H_h = c_s h / nu`.",
        "",
        "`propertyGrade` only summarizes the existing 0493w1 TG/sound/MSD fit statuses.  `lambdaBand` and `SchmidtBand` are descriptors, not automatic rejection criteria.",
        "",
        "|rank|case|grade|angle|lambda/h|nu|nu gain/A0|cs|Dself|Sc|H_h|Re/cell @ Ma=.1|wall speedup/A0|",
        "|---:|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for r in ranked:
        lines.append(
            f"|{r['hydrodynamicReachRank']}|{r['case']}|{r['propertyGrade']}|{fmt(r['rotationAngleDeg'])}|"
            f"{fmt(r['lambdaMeanOverCell'])}|{fmt(r['viscosityKinematic'])}|{fmt(r['viscosityReductionVsA0'])}|"
            f"{fmt(r['soundSpeed'])}|{fmt(r['selfDiffusion'])}|{fmt(r['Schmidt'])}|"
            f"{fmt(r['hydrodynamicReachPerCell'])}|{fmt(r['RePerCellAtMa0p1'])}|{fmt(r['wallSpeedupVsA0'])}|"
        )
    lines += [
        "",
        "Interpretation rule: do not select a production fluid from this table alone.  A0-A6 identify the useful bulk transport envelope.  Finite-size/grid, boundary, Q6 and application-specific qualifications come later.",
        "",
    ]
    md_path.write_text("\n".join(lines))

    print("===== 0493x13a SRC HIGH-Re PRESWEEP =====")
    print("formula: Re = Ma * (L/h) * H_h ; H_h = cs*h/nu")
    for r in ranked:
        print(
            f"rank={r['hydrodynamicReachRank']} case={r['case']} grade={r['propertyGrade']} "
            f"angle={fmt(r['rotationAngleDeg'])} lambda/h={fmt(r['lambdaMeanOverCell'])} "
            f"nu={fmt(r['viscosityKinematic'])} nuGainA0={fmt(r['viscosityReductionVsA0'])} "
            f"cs={fmt(r['soundSpeed'])} D={fmt(r['selfDiffusion'])} Sc={fmt(r['Schmidt'])} "
            f"H_h={fmt(r['hydrodynamicReachPerCell'])} wallSpeedupA0={fmt(r['wallSpeedupVsA0'])}"
        )
    print(f"result={csv_path}")
    print(f"report={md_path}")


if __name__ == "__main__":
    main()
