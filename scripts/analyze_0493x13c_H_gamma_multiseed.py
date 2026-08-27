#!/usr/bin/env python3
"""Analyze 0493x13c-Hgamma multi-seed transverse shear qualification.

Campaign tooling only.  No pandas.  Reuses the validated x13b shear fit so the
only new work here is statistics across seeds, wavelength consistency, and cost.
"""
from __future__ import annotations
import argparse, csv, importlib.util, math, re
from pathlib import Path
import numpy as np


def load_module(path: Path, name: str):
    spec=importlib.util.spec_from_file_location(name,path)
    if not spec or not spec.loader: raise RuntimeError(f'cannot import {path}')
    mod=importlib.util.module_from_spec(spec); spec.loader.exec_module(mod); return mod


def read_csv(path: Path):
    if not path.exists(): return []
    with path.open(newline='') as f: return list(csv.DictReader(f))


def write_csv(path: Path, rows):
    path.parent.mkdir(parents=True,exist_ok=True)
    if not rows: path.write_text(''); return
    fields=[]
    for r in rows:
        for k in r:
            if k not in fields: fields.append(k)
    with path.open('w',newline='') as f:
        w=csv.DictWriter(f,fieldnames=fields,lineterminator='\n'); w.writeheader(); w.writerows(rows)


def ff(r,k,default=math.nan):
    try:return float(r[k])
    except:return default


def elapsed_seconds(path: Path):
    if not path.exists(): return math.nan
    m=re.search(r'elapsed=([0-9.eE+\-]+)',path.read_text(errors='ignore'))
    return float(m.group(1)) if m else math.nan


def sample_stats(vals):
    a=np.asarray([x for x in vals if math.isfinite(x)],float)
    if len(a)==0:
        return dict(n=0,mean=math.nan,std=math.nan,sem=math.nan,cv=math.nan,ci95Low=math.nan,ci95High=math.nan,median=math.nan)
    mean=float(np.mean(a)); std=float(np.std(a,ddof=1)) if len(a)>1 else 0.0; sem=std/math.sqrt(len(a))
    return dict(n=len(a),mean=mean,std=std,sem=sem,cv=std/abs(mean) if mean else math.nan,
                ci95Low=mean-1.96*sem,ci95High=mean+1.96*sem,median=float(np.median(a)))


def main():
    p=argparse.ArgumentParser()
    p.add_argument('--campaign-root',type=Path,required=True)
    p.add_argument('--repo-root',type=Path,default=Path('.'))
    a=p.parse_args(); root=a.repo_root.resolve(); campaign=a.campaign_root
    x13b=load_module(root/'scripts'/'analyze_0493x13b_constitutive_transport.py','x13b_analysis')
    w1=x13b.load_w1(root)
    run_root=campaign/'H_gamma'; manifest=run_root/'manifest_0493x13c_Hgamma.csv'
    rows=[]
    for row in read_csv(manifest):
        marker=run_root/row['runDir']/'RUN_COMPLETE_0493x13c_Hgamma'
        if not marker.exists():
            rows.append({**row,'shearStatus':'MISSING','error':'completion marker absent'})
            continue
        try:
            q=x13b.analyze_shear_run(w1,row,run_root)
            q['elapsedSeconds']=elapsed_seconds(run_root/row['runDir']/'logs'/'time_0493x13c.txt')
            T=ff(row,'physicalTime'); q['elapsedSecPerPhysicalTime']=q['elapsedSeconds']/T if T>0 and math.isfinite(q['elapsedSeconds']) else math.nan
            rows.append(q)
        except Exception as e:
            rows.append({**row,'shearStatus':'ERROR','error':str(e)})

    analysis=campaign/'analysis'; analysis.mkdir(parents=True,exist_ok=True)
    write_csv(analysis/'H_gamma_runs_0493x13c.csv',rows)

    wave=[]
    groups={}
    for r in rows: groups.setdefault((int(ff(r,'gamma',-1)),int(ff(r,'wavelengthCells',-1))),[]).append(r)
    for (gamma,ny),grp in sorted(groups.items()):
        valid=[r for r in grp if r.get('shearStatus') in ('PASS','REVIEW') and math.isfinite(ff(r,'nuT'))]
        pass_rows=[r for r in grp if r.get('shearStatus')=='PASS' and math.isfinite(ff(r,'nuT'))]
        st=sample_stats([ff(r,'nuT') for r in valid]); r2=sample_stats([ff(r,'shearFitR2') for r in valid])
        wall=sample_stats([ff(r,'elapsedSecPerPhysicalTime') for r in valid])
        expected=len(grp); valid_frac=len(valid)/expected if expected else 0; pass_frac=len(pass_rows)/expected if expected else 0
        if expected>=3 and pass_frac>=0.75 and st['cv']<=0.10 and r2['mean']>=0.98:
            grade='PASS'
        elif expected>=3 and valid_frac>=0.75 and st['cv']<=0.20 and r2['mean']>=0.93:
            grade='REVIEW'
        else:
            grade='INVALID_OR_NOISY'
        base=grp[0]
        wave.append(dict(
            fluid=f'G{gamma:02d}',gamma=gamma,wavelengthCells=ny,kLambda=ff(base,'kLambda'),
            expectedSeeds=expected,validSeeds=len(valid),passSeeds=len(pass_rows),validFraction=valid_frac,passFraction=pass_frac,
            nuTMean=st['mean'],nuTStd=st['std'],nuTSem=st['sem'],nuTCV=st['cv'],nuTCI95Low=st['ci95Low'],nuTCI95High=st['ci95High'],
            shearFitR2Mean=r2['mean'],shearFitR2Min=min([ff(r,'shearFitR2') for r in valid],default=math.nan),
            elapsedSecPerPhysicalTimeMean=wall['mean'],elapsedSecPerPhysicalTimeStd=wall['std'],wavelengthGrade=grade,
            rotationAngleDeg=base.get('rotationAngleDeg',''),targetLambdaMeanOverCell=base.get('targetLambdaMeanOverCell',''),dt=base.get('dt',''),
        ))
    write_csv(analysis/'H_gamma_wavelength_summary_0493x13c.csv',wave)

    by_gamma={}
    for r in wave: by_gamma.setdefault(int(r['gamma']),{})[int(r['wavelengthCells'])]=r
    qual=[]
    for gamma,d in sorted(by_gamma.items()):
        r64=d.get(64); r128=d.get(128)
        m64=ff(r64 or {},'nuTMean'); m128=ff(r128 or {},'nuTMean'); se64=ff(r64 or {},'nuTSem'); se128=ff(r128 or {},'nuTSem')
        rel=abs(m128-m64)/(0.5*(m128+m64)) if m64>0 and m128>0 else math.nan
        dz=abs(m128-m64)/math.sqrt(se64*se64+se128*se128) if all(math.isfinite(x) for x in (m64,m128,se64,se128)) and se64*se64+se128*se128>0 else math.nan
        g64=(r64 or {}).get('wavelengthGrade','MISSING'); g128=(r128 or {}).get('wavelengthGrade','MISSING')
        if g64=='PASS' and g128=='PASS' and math.isfinite(rel) and rel<=0.15:
            local='LOCAL_PASS'
        elif g64 in ('PASS','REVIEW') and g128 in ('PASS','REVIEW') and math.isfinite(rel) and rel<=0.25:
            local='LOCAL_REVIEW'
        else:
            local='NONLOCAL_OR_UNRESOLVED'
        nu_long=m128 if m128>0 and g128 in ('PASS','REVIEW') else (m64 if m64>0 and g64 in ('PASS','REVIEW') else math.nan)
        wall64=ff(r64 or {},'elapsedSecPerPhysicalTimeMean')
        particle_proxy=1.0/(gamma*nu_long) if gamma>0 and nu_long>0 else math.nan
        wall_proxy=1.0/(nu_long*wall64) if nu_long>0 and wall64>0 else math.nan
        qual.append(dict(
            fluid=f'G{gamma:02d}',gamma=gamma,nuT64Mean=m64,nuT64Std=ff(r64 or {},'nuTStd'),nuT64CV=ff(r64 or {},'nuTCV'),grade64=g64,
            nuT128Mean=m128,nuT128Std=ff(r128 or {},'nuTStd'),nuT128CV=ff(r128 or {},'nuTCV'),grade128=g128,
            wavelengthRelativeDifference=rel,wavelengthDifferenceZ=dz,localityGrade=local,nuTLongWaveEstimate=nu_long,
            reachPerParticleProxy=particle_proxy,reachPerWallProxy64=wall_proxy,wallSecPerPhysicalTime64=wall64,
        ))
    # Normalize cost/reach proxies to G20 when present.
    ref=next((r for r in qual if int(r['gamma'])==20),None)
    for r in qual:
        rp=ff(r,'reachPerParticleProxy'); rw=ff(r,'reachPerWallProxy64')
        r['reachPerParticleGainVsG20']=rp/ff(ref or {},'reachPerParticleProxy') if ref and rp>0 and ff(ref,'reachPerParticleProxy')>0 else math.nan
        r['reachPerWallGainVsG20']=rw/ff(ref or {},'reachPerWallProxy64') if ref and rw>0 and ff(ref,'reachPerWallProxy64')>0 else math.nan
    write_csv(analysis/'H_gamma_qualification_0493x13c.csv',qual)

    print('[0493x13c-Hgamma-analysis] gamma  nuT64  nuT128  locality  reach/particle vs G20')
    for r in qual:
        print(f"  {int(r['gamma']):>2d}  {ff(r,'nuT64Mean'):.6g}  {ff(r,'nuT128Mean'):.6g}  {r['localityGrade']:<22s}  {ff(r,'reachPerParticleGainVsG20'):.4g}")
    print(f'[0493x13c-Hgamma-analysis] output={analysis}')

if __name__=='__main__': main()
