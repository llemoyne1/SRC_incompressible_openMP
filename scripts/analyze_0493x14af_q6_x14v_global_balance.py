#!/usr/bin/env python3
from __future__ import annotations
import argparse, csv, json, math
from pathlib import Path


def read_csv(path: Path):
    with path.open(newline='', encoding='utf-8') as f:
        return list(csv.DictReader(f))


def f(row, key):
    return float(row[key])


def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--run-root', type=Path, required=True)
    ap.add_argument('--liquid-type', type=int, default=1)
    a=ap.parse_args()
    out=a.run_root/'output'; ana=a.run_root/'analysis'; ana.mkdir(parents=True, exist_ok=True)
    x14=out/'cuda_x14v_global_balance_0493x14af.csv'
    q6=out/'cuda_species_q6_independent_masked_0493w5.csv'
    sp=out/'species_runtime_0493x14x.csv'
    for p in (x14,q6,sp):
        if not p.is_file(): raise SystemExit(f'missing {p}')

    xr=read_csv(x14)
    qr=[r for r in read_csv(q6) if int(r['type'])==a.liquid_type]
    sr=read_csv(sp)
    qmap={int(r['step']):r for r in qr}
    pmap={}
    for r in sr:
        st=int(r['step']); pmap.setdefault(st,[0.0,0.0]); pmap[st][0]+=f(r,'Px'); pmap[st][1]+=f(r,'Py')

    prev=[0.0]*11; prev_step=0
    rows=[]
    err2=0.0; errn=0; mean_rx=mean_ry=0.0
    id_err_max=0.0
    for r in xr:
        st=int(r['step']); t=f(r,'time')
        cum=[f(r,k) for k in ('cumSegments','cumRawX','cumRawY','cumThermoX','cumThermoY','cumPrefX','cumPrefY','cumGaugeX','cumGaugeY','cumKickX','cumKickY')]
        inc=[cum[i]-prev[i] for i in range(11)]
        if st not in qmap or st not in pmap or prev_step not in pmap:
            prev=cum; prev_step=st; continue
        jqx=f(qmap[st],'momentumX'); jqy=f(qmap[st],'momentumY')
        dpx=pmap[st][0]-pmap[prev_step][0]; dpy=pmap[st][1]-pmap[prev_step][1]
        seg,rawx,rawy,jtx,jty,jpx,jpy,jgx,jgy,jkx,jky=inc
        predx=jqx-jtx; predy=jqy-jty
        rx=dpx-predx; ry=dpy-predy
        id1=math.hypot(jkx-(rawx-jtx), jky-(rawy-jty))
        id2=math.hypot(jtx-(jpx+jgx), jty-(jpy+jgy))
        id_err_max=max(id_err_max,id1,id2)
        rn=math.hypot(rx,ry); err2+=rn*rn; errn+=1; mean_rx+=rx; mean_ry+=ry
        rows.append({
            'step':st,'time':t,'segments':seg,
            'Jq6X':jqx,'Jq6Y':jqy,'JrawX':rawx,'JrawY':rawy,
            'JthermoX':jtx,'JthermoY':jty,'JprefX':jpx,'JprefY':jpy,
            'JgaugeX':jgx,'JgaugeY':jgy,'JkickX':jkx,'JkickY':jky,
            'dPtotX':dpx,'dPtotY':dpy,'predictedX':predx,'predictedY':predy,
            'residualX':rx,'residualY':ry,'residualNorm':rn,
            'identityKickNorm':id1,'identityThermoNorm':id2,
        })
        prev=cum; prev_step=st

    if not rows: raise SystemExit('no aligned step rows')
    outcsv=ana/'q6_x14v_global_balance_trace_0493x14af.csv'
    with outcsv.open('w',newline='',encoding='utf-8') as fobj:
        w=csv.DictWriter(fobj,fieldnames=list(rows[0].keys())); w.writeheader(); w.writerows(rows)
    mean_rx/=errn; mean_ry/=errn
    rms=math.sqrt(err2/errn)
    mean_r=math.hypot(mean_rx,mean_ry)
    q6rms=math.sqrt(sum(r['Jq6X']**2+r['Jq6Y']**2 for r in rows)/len(rows))
    thermorms=math.sqrt(sum(r['JthermoX']**2+r['JthermoY']**2 for r in rows)/len(rows))
    summary={
        'steps':len(rows),'firstStep':rows[0]['step'],'lastStep':rows[-1]['step'],
        'residualMeanX':mean_rx,'residualMeanY':mean_ry,'residualMeanNorm':mean_r,
        'residualRmsNorm':rms,'q6ImpulseRmsNorm':q6rms,'thermoImpulseRmsNorm':thermorms,
        'residualRmsOverQ6Rms':(rms/q6rms if q6rms>0 else None),
        'maxAlgebraicIdentityError':id_err_max,
        'model':'dPtot = Jq6_applied - Jthermo_x14ad + residual',
        'signConvention':'Jraw is gas reaction impulse available to liquid; Jkick=Jraw-Jthermo; gas specular changes gas momentum by -Jraw',
    }
    js=ana/'q6_x14v_global_balance_summary_0493x14af.json'; js.write_text(json.dumps(summary,indent=2)+'\n')
    print('[0493x14af-analysis] steps=%d residualMean=(%.6g,%.6g) |mean|=%.6g residualRms=%.6g q6Rms=%.6g ratio=%.6g identityMax=%.3e' % (
        summary['steps'],mean_rx,mean_ry,mean_r,rms,q6rms,summary['residualRmsOverQ6Rms'],id_err_max))
    print(f'[0493x14af-analysis] trace={outcsv}')
    print(f'[0493x14af-analysis] summary={js}')

if __name__=='__main__': main()
