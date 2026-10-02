#!/usr/bin/env python3
from __future__ import annotations
import argparse, csv, json, math
from pathlib import Path


def f(row, key):
    try:
        v=float(row[key]); return v if math.isfinite(v) else math.nan
    except Exception:
        return math.nan


def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--species-runtime', type=Path, required=True)
    ap.add_argument('--out-dir', type=Path, required=True)
    ap.add_argument('--liquid-type', type=int, default=1)
    ap.add_argument('--gas-type', type=int, default=2)
    a=ap.parse_args()
    if not a.species_runtime.is_file():
        raise SystemExit(f'[0493x22a] missing {a.species_runtime}')
    rows=list(csv.DictReader(a.species_runtime.open(newline='')))
    if not rows:
        raise SystemExit('[0493x22a] empty species runtime CSV')
    required={'step','time','type','nFluid','totalMass','Px','Py','kineticEnergy'}
    missing=required-set(rows[0])
    if missing:
        raise SystemExit('[0493x22a] missing columns: '+','.join(sorted(missing)))

    by_step={}
    for r in rows:
        try: st=int(round(float(r['step']))); typ=int(round(float(r['type'])))
        except Exception: continue
        if typ not in (a.liquid_type,a.gas_type): continue
        by_step.setdefault(st,{})[typ]=r
    steps=sorted(st for st,d in by_step.items() if a.liquid_type in d and a.gas_type in d)
    if len(steps)<2:
        raise SystemExit('[0493x22a] need >=2 complete liquid/gas timestamps')

    out=[]
    for st in steps:
        L=by_step[st][a.liquid_type]; G=by_step[st][a.gas_type]
        t=f(L,'time')
        ML,MG=f(L,'totalMass'),f(G,'totalMass')
        PLx,PLy=f(L,'Px'),f(L,'Py'); PGx,PGy=f(G,'Px'),f(G,'Py')
        NL,NG=f(L,'nFluid'),f(G,'nFluid')
        KEL,KEG=f(L,'kineticEnergy'),f(G,'kineticEnergy')
        PTx,PTy=PLx+PGx,PLy+PGy
        # In 2-D, peculiar kinetic energy per particle equals kBT.
        kL=(KEL-0.5*(PLx*PLx+PLy*PLy)/ML)/NL if ML>0 and NL>0 else math.nan
        kG=(KEG-0.5*(PGx*PGx+PGy*PGy)/MG)/NG if MG>0 and NG>0 else math.nan
        out.append(dict(step=st,time=t,M_L=ML,M_G=MG,P_Lx=PLx,P_Ly=PLy,
                        P_Gx=PGx,P_Gy=PGy,P_tot_x=PTx,P_tot_y=PTy,
                        kBT_L_proxy=kL,kBT_G_proxy=kG,n_L=NL,n_G=NG))
    r0=out[0]; ML0=r0['M_L']; MG0=r0['M_G']; PX0=r0['P_tot_x']; PY0=r0['P_tot_y']
    for r in out:
        r['rel_dM_L']=(r['M_L']-ML0)/ML0
        r['rel_dM_G']=(r['M_G']-MG0)/MG0
        dx=r['P_tot_x']-PX0; dy=r['P_tot_y']-PY0
        r['dP_tot_x']=dx; r['dP_tot_y']=dy; r['dP_tot_norm']=math.hypot(dx,dy)

    max_ml=max(abs(r['rel_dM_L']) for r in out)
    max_mg=max(abs(r['rel_dM_G']) for r in out)
    max_dp=max(r['dP_tot_norm'] for r in out)
    fin=out[-1]
    mean_kL=sum(r['kBT_L_proxy'] for r in out)/len(out)
    mean_kG=sum(r['kBT_G_proxy'] for r in out)/len(out)
    summary={
        'source':str(a.species_runtime), 'rows':len(out),
        'stepStart':out[0]['step'],'stepEnd':fin['step'],'timeStart':out[0]['time'],'timeEnd':fin['time'],
        'massLiquidInitial':ML0,'massGasInitial':MG0,
        'maxRelativeLiquidMassChange':max_ml,'maxRelativeGasMassChange':max_mg,
        'PtotInitial':[PX0,PY0], 'PtotFinal':[fin['P_tot_x'],fin['P_tot_y']],
        'maxTotalMomentumDriftNorm':max_dp,
        'kBTLiquidMeanProxy':mean_kL,'kBTGasMeanProxy':mean_kG,
        'temperatureDefinition':'(K - |P|^2/(2M))/N in 2D; species-global peculiar-energy proxy',
    }
    a.out_dir.mkdir(parents=True,exist_ok=True)
    fields=list(out[0].keys())
    with (a.out_dir/'conservation_timeseries.csv').open('w',newline='') as fh:
        w=csv.DictWriter(fh,fieldnames=fields); w.writeheader(); w.writerows(out)
    (a.out_dir/'conservation_summary.json').write_text(json.dumps(summary,indent=2)+'\n')
    lines=[
        '===== 0493x22a CLOSED LIQUID-GAS CONSERVATION =====',
        f"source={a.species_runtime}",
        f"samples={len(out)} stepRange={out[0]['step']}..{fin['step']} timeRange={out[0]['time']:.12g}..{fin['time']:.12g}",
        f"maxRelativeLiquidMassChange={max_ml:.17g}",
        f"maxRelativeGasMassChange={max_mg:.17g}",
        f"PtotInitial=({PX0:.17g},{PY0:.17g})",
        f"PtotFinal=({fin['P_tot_x']:.17g},{fin['P_tot_y']:.17g})",
        f"maxTotalMomentumDriftNorm={max_dp:.17g}",
        f"kBTLiquidMeanProxy={mean_kL:.17g}",
        f"kBTGasMeanProxy={mean_kG:.17g}",
        'energyConservationTest=NOT_APPLICABLE_THERMOSTATTED',
    ]
    report='\n'.join(lines)+'\n'
    (a.out_dir/'conservation_summary.txt').write_text(report)
    print(report,end='')

if __name__=='__main__': main()
