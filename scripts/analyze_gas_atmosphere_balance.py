#!/usr/bin/env python3
import argparse, csv, math
from pathlib import Path

def read_csv(path):
    with path.open(newline="") as f:
        return list(csv.DictReader(f))

def f(row, key, default=float("nan")):
    try:
        return float(row[key])
    except Exception:
        return default

def i(row, key, default=0):
    try:
        return int(float(row[key]))
    except Exception:
        return default

ap=argparse.ArgumentParser(description="Atmospheric-reservoir balance diagnostics for planar gas-jet/bath runs.")
ap.add_argument("--run-root", required=True)
ap.add_argument("--bath-height", type=float, required=True)
ap.add_argument("--nozzle-exit-y", type=float, required=True)
ap.add_argument("--jet-width", type=float, required=True)
ap.add_argument("--cell-size", type=float, required=True)
ap.add_argument("--inlet-target-occupancy", type=float, required=True)
ap.add_argument("--post-start-time", type=float, default=2.0)
args=ap.parse_args()

root=Path(args.run_root)
summary_path=root/"output"/"summary_runtime.csv"
pressure_path=root/"output"/"cuda_phase_interface_pressure_0493x6g.csv"
indent_path=root/"analysis"/"indentation_history.csv"
for p in (summary_path, pressure_path, indent_path):
    if not p.exists():
        raise SystemExit(f"[atmosphere-balance] missing {p}")

summary=read_csv(summary_path)
pressure=read_csv(pressure_path)
indent=read_csv(indent_path)
if not summary or not indent:
    raise SystemExit("[atmosphere-balance] empty summary/indentation input")

# Liquid particle count is directly reported by the interface analyzer and is
# exactly conserved in the intended campaign. Use the first finite value.
liq0=None
for r in indent:
    v=i(r,"liquidParticles",-1)
    if v >= 0:
        liq0=v; break
if liq0 is None:
    raise SystemExit("[atmosphere-balance] cannot determine liquid particle count")

s_by_step={i(r,"step") : r for r in summary}
p_by_step={i(r,"step") : r for r in pressure}
ind_by_step={}
for r in indent:
    st=i(r,"step")
    # indentation_history may contain both init and state_step_0; keep the later
    # row, then one row per subsequent dump.
    ind_by_step[st]=r

s0=s_by_step[min(s_by_step)]
gas0=i(s0,"nFluidParticles")-liq0
if gas0 <= 0:
    raise SystemExit(f"[atmosphere-balance] invalid initial active gas count {gas0}")

p0row=pressure[0]
p0=f(p0row,"pressureReference")+f(p0row,"pressureDeltaMean")

history=[]
for st in sorted(ind_by_step):
    if st not in s_by_step:
        continue
    sr=s_by_step[st]
    ir=ind_by_step[st]
    pr=p_by_step.get(st)
    gas=i(sr,"nFluidParticles")-liq0
    frac=gas/gas0
    eta=f(ir,"etaFar")
    heff=(args.nozzle_exit_y-eta)/args.jet_width
    row={
        "step":st,
        "time":f(sr,"time"),
        "activeGasParticles":gas,
        "activeGasFractionVsInitial":frac,
        "nInactiveParticles":i(sr,"nInactiveParticles"),
        "inletReservoirTargetParticles":i(sr,"inletReservoirTargetParticles"),
        "inletReservoirTargetCells":(
            f(sr,"inletReservoirTargetParticles")/args.inlet_target_occupancy
            if args.inlet_target_occupancy>0 else float("nan")
        ),
        "inletReservoirDeleted":i(sr,"inletReservoirDeleted"),
        "inletBackflowDeleted":i(sr,"inletBackflowDeleted"),
        "outletParticlesDeleted":i(sr,"outletParticlesDeleted"),
        "inletParticlesInserted":i(sr,"inletParticlesInserted"),
        "inletNetParticleDelta":i(sr,"inletNetParticleDelta"),
        "inletReservoirMeanN":f(sr,"inletReservoirMeanN"),
        "inletReservoirStdN":f(sr,"inletReservoirStdN"),
        "inletMeanUx":f(sr,"inletMeanUx"),
        "inletMeanUy":f(sr,"inletMeanUy"),
        "inletKBTDiagnostic":f(sr,"inletKBT"),
        "etaFar":eta,
        "etaFarDrift":eta-args.bath_height,
        "indentationDepth":f(ir,"depth"),
        "effectiveStandoffOverJetWidth":heff,
        "x6gPressureReference":float("nan"),
        "x6gPressureDeltaMean":float("nan"),
        "x6gInterfacePressureMean":float("nan"),
        "x6gInterfacePressureRatioVsInitial":float("nan"),
    }
    if pr is not None:
        pref=f(pr,"pressureReference")
        dp=f(pr,"pressureDeltaMean")
        pg=pref+dp
        row.update({
            "x6gPressureReference":pref,
            "x6gPressureDeltaMean":dp,
            "x6gInterfacePressureMean":pg,
            "x6gInterfacePressureRatioVsInitial":pg/p0 if p0!=0 else float("nan"),
        })
    history.append(row)

outdir=root/"analysis"
outdir.mkdir(exist_ok=True)
hist_path=outdir/"ambient_balance_history.csv"
if history:
    with hist_path.open("w",newline="") as fcsv:
        w=csv.DictWriter(fcsv,fieldnames=list(history[0]))
        w.writeheader(); w.writerows(history)

post=[r for r in history if r["time"] >= args.post_start_time]
if not post:
    post=history

def finite(vals):
    return [x for x in vals if isinstance(x,(int,float)) and math.isfinite(x)]

gasfr=finite([r["activeGasFractionVsInitial"] for r in post])
drift=finite([r["etaFarDrift"] for r in post])
heff=finite([r["effectiveStandoffOverJetWidth"] for r in post])
prat=finite([r["x6gInterfacePressureRatioVsInitial"] for r in post])
outdel=[r["outletParticlesDeleted"] for r in history]
resmean=finite([r["inletReservoirMeanN"] for r in post])

min_gas=min(gasfr) if gasfr else float("nan")
mean_gas=sum(gasfr)/len(gasfr) if gasfr else float("nan")
max_abs_drift=max(abs(x) for x in drift) if drift else float("nan")
mean_heff=sum(heff)/len(heff) if heff else float("nan")
mean_prat=sum(prat)/len(prat) if prat else float("nan")
max_out=max(outdel) if outdel else 0
mean_res=sum(resmean)/len(resmean) if resmean else float("nan")

# Screening criteria, not a qualification claim.
gas_ok=math.isfinite(min_gas) and min_gas >= 0.80
level_ok=math.isfinite(max_abs_drift) and max_abs_drift <= 2.0*args.cell_size
outlet_ok=(max_out == 0)
reservoir_ok=math.isfinite(mean_res) and abs(mean_res-args.inlet_target_occupancy) <= 1e-9
screen_ok=gas_ok and level_ok and outlet_ok and reservoir_ok

report=outdir/"ambient_balance_report.txt"
with report.open("w") as fp:
    fp.write("Planar gas jet / liquid bath — atmospheric reservoir balance\n")
    fp.write("=============================================================\n")
    fp.write("This report screens whether the gas boundary behaves as an ambient bath.\n")
    fp.write("The thresholds below are campaign screening targets, not a physics qualification.\n\n")
    fp.write(f"initialActiveGasParticles = {gas0}\n")
    fp.write(f"postStartTime = {args.post_start_time:.12g}\n")
    fp.write(f"postMinActiveGasFractionVsInitial = {min_gas:.12g}\n")
    fp.write(f"postMeanActiveGasFractionVsInitial = {mean_gas:.12g}\n")
    fp.write(f"postMaxAbsFarFieldLevelDrift = {max_abs_drift:.12g}\n")
    fp.write(f"postMaxAbsFarFieldLevelDriftCells = {max_abs_drift/args.cell_size:.12g}\n")
    fp.write(f"postMeanEffectiveStandoffOverJetWidth = {mean_heff:.12g}\n")
    fp.write(f"postMeanX6gInterfacePressureRatioVsInitial = {mean_prat:.12g}\n")
    fp.write(f"postMeanReservoirOccupancy = {mean_res:.12g}\n")
    fp.write(f"maxOutletParticlesDeleted = {max_out}\n\n")
    fp.write("Screening targets\n")
    fp.write("-----------------\n")
    fp.write(f"active gas fraction >= 0.80 : {'PASS' if gas_ok else 'REVIEW'}\n")
    fp.write(f"|etaFar-bathHeight| <= 2 cells : {'PASS' if level_ok else 'REVIEW'}\n")
    fp.write(f"no passive-outlet deletions : {'PASS' if outlet_ok else 'REVIEW'}\n")
    fp.write(f"hard reservoir occupancy exactly target : {'PASS' if reservoir_ok else 'REVIEW'}\n")
    fp.write(f"ATMOSPHERE_SCREEN = {'PASS' if screen_ok else 'REVIEW'}\n")
print(f"[atmosphere-balance] history={hist_path}")
print(f"[atmosphere-balance] report={report}")
print(f"[atmosphere-balance] ATMOSPHERE_SCREEN={'PASS' if screen_ok else 'REVIEW'}")
