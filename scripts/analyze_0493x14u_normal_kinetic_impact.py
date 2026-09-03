#!/usr/bin/env python3
"""Analyze x14u normal kinetic impact using existing species diagnostics.

Primary question
----------------
When the gas loses directed normal momentum at the specular interface, how
much of that momentum appears in the liquid?

For the mirror pair bottom_impact/top_impact:
  P_L^a = (P_L,bottom - P_L,top)/2
  P_G^a = (P_G,bottom - P_G,top)/2

The initial gas antisymmetric momentum P_G^a(0)>0 is known exactly from the
generator.  Define
  loss_G(t) = P_G^a(0) - P_G^a(t)
  G_mom(t)  = P_L^a(t) / loss_G(t)

G_mom~1 means the kinetic gas momentum lost at the interface is transferred
to the liquid.  G_mom~0 means reflection changes gas momentum without a
corresponding liquid impulse.

The constant-x6g ablation is the primary isolation: thermodynamic gas pressure
contribution is identically zero there.  The accessible-volume production mode
is a secondary comparison showing any later indirect x6g density feedback.
"""
from __future__ import annotations
import argparse, csv, json, math
from pathlib import Path

def read_manifest(path):
    with path.open(newline="") as f:
        return list(csv.DictReader(f))

def species_series(path, liquid_type, gas_type):
    by = {liquid_type: {}, gas_type: {}}
    with path.open(newline="") as f:
        for r in csv.DictReader(f):
            try:
                typ = int(float(r["type"]))
                if typ not in by:
                    continue
                step = int(float(r["step"]))
                by[typ][step] = {
                    "step": step,
                    "time": float(r["time"]),
                    "mass": float(r["totalMass"]),
                    "vx": float(r["meanVx"]),
                    "vy": float(r["meanVy"]),
                }
            except Exception:
                continue
    if not by[liquid_type] or not by[gas_type]:
        raise RuntimeError(f"incomplete species CSV: {path}")
    return by

def ols(points, through_origin=False):
    if len(points) < 3:
        raise RuntimeError("need >=3 fit points")
    if through_origin:
        sxx = sum(t*t for t,v in points)
        slope = sum(t*v for t,v in points)/sxx
        rms = math.sqrt(sum((v-slope*t)**2 for t,v in points)/len(points))
        return slope, 0.0, rms
    mt = sum(t for t,v in points)/len(points)
    mv = sum(v for t,v in points)/len(points)
    sxx = sum((t-mt)**2 for t,v in points)
    slope = sum((t-mt)*(v-mv) for t,v in points)/sxx
    intercept = mv-slope*mt
    rms = math.sqrt(sum((v-(intercept+slope*t))**2 for t,v in points)/len(points))
    return slope, intercept, rms

def fnum(x):
    try: return float(x)
    except: return math.nan

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--campaign-root", type=Path, required=True)
    ap.add_argument("--manifest", type=Path, default=None)
    ap.add_argument("--liquid-type", type=int, default=1)
    ap.add_argument("--gas-type", type=int, default=2)
    ap.add_argument("--fit-step-min", type=int, default=1)
    ap.add_argument("--fit-step-max", type=int, default=20)
    args = ap.parse_args()

    manifest = args.manifest or args.campaign_root/"manifest_0493x14u.csv"
    rows = read_manifest(manifest)

    data = {}
    for r in rows:
        key = (r["x6gMode"], r["case"])
        data[key] = {
            "meta": r,
            "series": species_series(Path(r["speciesCsv"]), args.liquid_type, args.gas_type)
        }

    summary = {"benchmark": "0493x14u_normal_kinetic_impact",
               "fitStepMin": args.fit_step_min, "fitStepMax": args.fit_step_max,
               "modes": {}}
    table_rows = []

    for mode in sorted({r["x6gMode"] for r in rows}):
        needed = [(mode,"bottom_impact"), (mode,"top_impact"), (mode,"static")]
        if any(k not in data for k in needed):
            print(f"[0493x14u-analysis] mode={mode}: incomplete matrix, skip paired analysis")
            continue

        b = data[(mode,"bottom_impact")]
        t = data[(mode,"top_impact")]
        s = data[(mode,"static")]
        common_steps = sorted(
            set(b["series"][args.liquid_type]) &
            set(t["series"][args.liquid_type]) &
            set(b["series"][args.gas_type]) &
            set(t["series"][args.gas_type])
        )
        if not common_steps:
            raise RuntimeError(f"no common steps for mode={mode}")

        p0b = fnum(b["meta"]["initialGasPy"])
        p0t = fnum(t["meta"]["initialGasPy"])
        pga0 = 0.5*(p0b-p0t)
        a_theory_emp = 0.5*(abs(fnum(b["meta"]["aTheoryEmpirical"])) +
                            abs(fnum(t["meta"]["aTheoryEmpirical"])))
        a_theory_max = 0.5*(abs(fnum(b["meta"]["aTheoryMaxwell"])) +
                            abs(fnum(t["meta"]["aTheoryMaxwell"])))

        timeseries = []
        fit_v = []
        for step in common_steps:
            lb = b["series"][args.liquid_type][step]
            lt = t["series"][args.liquid_type][step]
            gb = b["series"][args.gas_type][step]
            gt = t["series"][args.gas_type][step]
            plb = lb["mass"]*lb["vy"]
            plt = lt["mass"]*lt["vy"]
            pgb = gb["mass"]*gb["vy"]
            pgt = gt["mass"]*gt["vy"]
            pla = 0.5*(plb-plt)
            pga = 0.5*(pgb-pgt)
            loss = pga0-pga
            gmom = pla/loss if abs(loss) > 1e-14 else math.nan
            va = 0.5*(lb["vy"]-lt["vy"])
            if args.fit_step_min <= step <= args.fit_step_max:
                fit_v.append((lb["time"], va))
            timeseries.append({
                "mode": mode, "step": step, "time": lb["time"],
                "liquidVyAntisym": va,
                "liquidPyAntisym": pla,
                "gasPyAntisym": pga,
                "gasPyInitialAntisym": pga0,
                "gasMomentumLoss": loss,
                "momentumTransferGain": gmom,
                "totalMomentumDefect": pla+pga-pga0,
            })

        a_fit0, _, rms0 = ols(fit_v, through_origin=True)
        a_fit, intercept, rms = ols(fit_v, through_origin=False)

        static_liq = s["series"][args.liquid_type]
        static_max_vy = max(abs(q["vy"]) for q in static_liq.values())
        static_final_step = max(static_liq)
        static_final_vy = static_liq[static_final_step]["vy"]

        mode_summary = {
            "initialGasPyAntisym": pga0,
            "aTheoryEmpirical": a_theory_emp,
            "aTheoryMaxwell": a_theory_max,
            "aFitThroughOrigin": a_fit0,
            "aFitFreeIntercept": a_fit,
            "fitIntercept": intercept,
            "fitRmsThroughOrigin": rms0,
            "fitRmsFreeIntercept": rms,
            "kineticAccelerationGainEmpirical": a_fit0/a_theory_emp if a_theory_emp else math.nan,
            "kineticAccelerationGainMaxwell": a_fit0/a_theory_max if a_theory_max else math.nan,
            "staticMaxAbsLiquidVy": static_max_vy,
            "staticFinalLiquidVy": static_final_vy,
            "timeseries": timeseries,
        }
        summary["modes"][mode] = mode_summary

        print(f"\n===== 0493x14u mode={mode} =====")
        print(f"aTheory(empirical)={a_theory_emp:.8g}  aTheory(Maxwell)={a_theory_max:.8g}")
        print(f"aFit[steps {args.fit_step_min}..{args.fit_step_max}]={a_fit0:.8g} "
              f"G_acc(emp)={mode_summary['kineticAccelerationGainEmpirical']:.5f}")
        print(f"static max|Vy_L|={static_max_vy:.4e}")
        for wanted in (1, 5, 10, 20, 40, 60):
            q = next((q for q in timeseries if q["step"] == wanted), None)
            if q:
                print(f"step={wanted:3d} t={q['time']:.4f} "
                      f"PLa={q['liquidPyAntisym']:+.6g} "
                      f"lossG={q['gasMomentumLoss']:+.6g} "
                      f"G_mom={q['momentumTransferGain']:+.5f} "
                      f"defect={q['totalMomentumDefect']:+.6g}")
        table_rows.extend(timeseries)

    ad = args.campaign_root/"analysis"
    ad.mkdir(parents=True, exist_ok=True)
    ts_csv = ad/"kinetic_momentum_timeseries_0493x14u.csv"
    if table_rows:
        with ts_csv.open("w", newline="") as f:
            w = csv.DictWriter(f, fieldnames=list(table_rows[0].keys()))
            w.writeheader(); w.writerows(table_rows)
    js = ad/"normal_kinetic_impact_summary_0493x14u.json"
    js.write_text(json.dumps(summary, indent=2, allow_nan=True)+"\n")
    print(f"\ntimeseries={ts_csv}")
    print(f"summary={js}")

if __name__ == "__main__":
    main()
