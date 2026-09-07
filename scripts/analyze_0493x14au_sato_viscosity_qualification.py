#!/usr/bin/env python3
"""0493x14au — consolidate Sato liquid/gas Taylor–Green viscosity qualification.

Pure-Python replacement for the MATLAB consolidation script.  No pandas.
Reads the four authoritative fluid_characterization.json files written by the
existing 0493w1 standalone calibrator and writes the same core CSV/report
outputs expected by the x14au workflow.
"""
from __future__ import annotations

import csv
import json
import math
import sys
from pathlib import Path

HERE = Path(__file__).resolve()
ROOT = HERE.parent.parent
RUN_ROOT = ROOT / "runs" / "0493x14au_sato_viscosity"
OUT = RUN_ROOT / "analysis_0493x14au"

CASES = [
    ("liquid_lambda64h", "liquid", 64.0),
    ("liquid_lambda21p333h", "liquid", 64.0 / 3.0),
    ("gas_lambda64h", "gas", 64.0),
    ("gas_lambda21p333h", "gas", 64.0 / 3.0),
]


def num(d: dict, key: str) -> float:
    v = d.get(key, None)
    if v is None or v == "":
        return float("nan")
    return float(v)


def read_case(name: str, phase: str, wavelength_h: float) -> dict:
    p = RUN_ROOT / name / "analysis" / "fluid_characterization.json"
    if not p.is_file():
        raise FileNotFoundError(f"Missing {p}")
    with p.open("r", encoding="utf-8") as f:
        s = json.load(f)
    return {
        "caseName": name,
        "phase": phase,
        "path": str(s.get("path", "")),
        "wavelengthOverH": wavelength_h,
        "wavelengthOverD": wavelength_h / 20.0,
        "status": str(s.get("status", "")),
        "viscosityStatus": str(s.get("viscosityStatus", "")),
        "nu": num(s, "viscosityKinematic"),
        "nuStd": num(s, "viscosityStd"),
        "nuCV": num(s, "viscosityCV"),
        "gamma": num(s, "gamma"),
        "dt": num(s, "dt"),
        "kBT": num(s, "kBT"),
        "mass": num(s, "particleMass"),
        "cellSize": num(s, "cellSize"),
        "lambdaMeanOverH": num(s, "lambdaMeanOverCell"),
    }


def scale_comparison(a: dict, b: dict) -> dict:
    rel = (b["nu"] - a["nu"]) / a["nu"]
    sig = math.hypot(a["nuStd"], b["nuStd"])
    if math.isfinite(sig) and sig > 0:
        z = abs(b["nu"] - a["nu"]) / sig
        status = "CONSISTENT_2SIGMA" if z <= 2.0 else "SCALE_DEPENDENCE_REVIEW"
    else:
        z = float("nan")
        status = "UNCERTAINTY_UNRESOLVED"
    return {"relDiff": rel, "z": z, "scaleStatus": status}


def write_csv(path: Path, fieldnames: list[str], rows: list[dict]) -> None:
    with path.open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=fieldnames)
        w.writeheader()
        for r in rows:
            w.writerow({k: r.get(k, "") for k in fieldnames})


def maybe_plot(a: dict, b: dict, label: str, outfile: Path) -> None:
    try:
        import matplotlib.pyplot as plt
    except Exception as exc:
        print(f"[0493x14au] plot skipped ({outfile.name}): {exc}", file=sys.stderr)
        return
    x = [a["wavelengthOverH"], b["wavelengthOverH"]]
    y = [a["nu"], b["nu"]]
    e = [a["nuStd"], b["nuStd"]]
    fig = plt.figure()
    ax = fig.add_subplot(111)
    ax.errorbar(x, y, yerr=e, marker="o")
    ax.set_xlabel("Taylor-Green wavelength / h")
    ax.set_ylabel("Kinematic viscosity nu")
    ax.set_title(f"0493x14au - {label}")
    ax.grid(True)
    ax.invert_xaxis()
    fig.tight_layout()
    fig.savefig(outfile, dpi=160)
    plt.close(fig)


def fmt(x: float, spec: str = ".10g") -> str:
    return format(x, spec)


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    rows = [read_case(*c) for c in CASES]
    L0, La, G0, Ga = rows
    liq = scale_comparison(L0, La)
    gas = scale_comparison(G0, Ga)

    case_fields = [
        "caseName", "phase", "path", "wavelengthOverH", "wavelengthOverD",
        "status", "viscosityStatus", "nu", "nuStd", "nuCV", "gamma", "dt",
        "kBT", "mass", "cellSize", "lambdaMeanOverH",
    ]
    write_csv(OUT / "viscosity_cases.csv", case_fields, rows)

    comp_rows = []
    for phase, p0, pa, q in [("liquid", L0, La, liq), ("gas", G0, Ga, gas)]:
        comp_rows.append({
            "phase": phase,
            "nuPrimary": p0["nu"],
            "nuPrimaryStd": p0["nuStd"],
            "nuPrimaryCV": p0["nuCV"],
            "nuApplicationScale": pa["nu"],
            "nuApplicationScaleStd": pa["nuStd"],
            "nuApplicationScaleCV": pa["nuCV"],
            "relativeScaleDifference": q["relDiff"],
            "scaleDifferenceZ": q["z"],
            "scaleConsistency": q["scaleStatus"],
        })
    comp_fields = list(comp_rows[0].keys())
    write_csv(OUT / "viscosity_scale_comparison.csv", comp_fields, comp_rows)

    h = 1.0 / 256.0
    gamma = 20.0
    mL, mG = 1.0, 0.1
    rhoL = gamma * mL / h**2
    rhoG = gamma * mG / h**2
    D = 20.0 * h
    gabs = 0.5
    sigma = 294.461365748622
    Frs = [0.20, 0.40, 0.660364520158346, 0.90]
    c = (math.pi / 4.0) ** 2
    nuL, nuG = L0["nu"], G0["nu"]
    muL, muG = rhoL * nuL, rhoG * nuG
    Bo = (rhoL - rhoG) * gabs * D**2 / sigma
    OhL = nuL * math.sqrt(rhoL / (sigma * D))

    dim_rows = []
    for Fr in Frs:
        U = math.sqrt(Fr * (rhoL / rhoG) * gabs * D / c)
        dim_rows.append({
            "FrModifiedTarget": Fr,
            "UJetNominal": U,
            "ReLiquid": U * D / nuL,
            "ReGas": U * D / nuG,
            "WeGas": rhoG * U**2 * D / sigma,
            "BoDensityDifference": Bo,
            "OhLiquid": OhL,
            "CaLiquid": muL * U / sigma,
        })
    dim_fields = list(dim_rows[0].keys())
    write_csv(OUT / "sato_stageA_dimensionless_with_calibrated_nu.csv", dim_fields, dim_rows)

    maybe_plot(L0, La, "Liquid Q6-G-F", OUT / "viscosity_scale_liquid.png")
    maybe_plot(G0, Ga, "Gas SRC", OUT / "viscosity_scale_gas.png")

    report = OUT / "viscosity_qualification_report.txt"
    with report.open("w", encoding="utf-8") as f:
        f.write("0493x14au Sato viscosity qualification\n")
        f.write("====================================\n\n")
        f.write("Primary metrology: existing 0493w1 standalone Taylor-Green ensemble.\n")
        f.write(f"Primary wavelength = 64 h; application check = 64/3 h = {64/3:.6f} h = {(64/3)/20:.6f} D.\n\n")
        for label, a, b, q in [("LIQUID", L0, La, liq), ("GAS", G0, Ga, gas)]:
            f.write(f"{label}\n")
            f.write(f"  primary path={a['path']} status={a['status']} viscosityStatus={a['viscosityStatus']}\n")
            f.write(f"  nu(64h)={a['nu']:.12g}  std={a['nuStd']:.6g}  CV={100*a['nuCV']:.4f}%\n")
            f.write(f"  app-scale status={b['status']} viscosityStatus={b['viscosityStatus']}\n")
            f.write(f"  nu(64/3h)={b['nu']:.12g}  std={b['nuStd']:.6g}  CV={100*b['nuCV']:.4f}%\n")
            f.write(f"  delta_app/primary={100*q['relDiff']:+.5f}%  z={q['z']:.5g}  scale={q['scaleStatus']}\n\n")
        f.write(f"Dynamic viscosity ratio mu_G/mu_L (primary nu) = {muG/muL:.10g}\n")
        f.write(f"Kinematic viscosity ratio nu_G/nu_L = {nuG/nuL:.10g}\n")
        f.write(f"rho_G/rho_L = {rhoG/rhoL:.10g}\n\n")
        f.write(f"Sato campaign propagation uses D=20h, |g|=0.5 and sigma={sigma:.15g}.\n")
        f.write("The 3-D experimental coefficient is not used as a viscosity acceptance criterion.\n")
        f.write("Scale consistency is diagnostic: CONSISTENT_2SIGMA means |nu_app-nu_primary| <= 2*sqrt(sd_primary^2+sd_app^2).\n")

    print("===== 0493x14au VISCOSITY QUALIFICATION =====")
    print(f"liquid nu={L0['nu']:.10g} std={L0['nuStd']:.4g} CV={100*L0['nuCV']:.3f}% scaleDelta={100*liq['relDiff']:+.3f}% {liq['scaleStatus']}")
    print(f"gas    nu={G0['nu']:.10g} std={G0['nuStd']:.4g} CV={100*G0['nuCV']:.3f}% scaleDelta={100*gas['relDiff']:+.3f}% {gas['scaleStatus']}")
    print(f"muG/muL={muG/muL:.10g} nuG/nuL={nuG/nuL:.10g}")
    print(f"results={OUT}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"[0493x14au] ERROR: {exc}", file=sys.stderr)
        raise
