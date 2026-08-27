#!/usr/bin/env python3
"""Analyze x13d H-Ny256 and compare with x13c Ny64/Ny128.
Campaign tooling only; no pandas; no source-code changes.
"""
from __future__ import annotations
import argparse,csv,importlib.util,math,re
from pathlib import Path
import numpy as np

def load_module(path,name):
    spec=importlib.util.spec_from_file_location(name,path)
    if not spec or not spec.loader: raise RuntimeError(f'cannot import {path}')
    mod=importlib.util.module_from_spec(spec);spec.loader.exec_module(mod);return mod

def read_csv(path):
    if not Path(path).exists(): return []
    with Path(path).open(newline='') as f:return list(csv.DictReader(f))

def write_csv(path,rows):
    path=Path(path);path.parent.mkdir(parents=True,exist_ok=True)
    if not rows:path.write_text('');return
    fields=[]
    for r in rows:
        for k in r:
            if k not in fields:fields.append(k)
    with path.open('w',newline='') as f:
        w=csv.DictWriter(f,fieldnames=fields,lineterminator='\n');w.writeheader();w.writerows(rows)

def ff(r,k,d=math.nan):
    try:return float(r[k])
    except:return d

def elapsed(path):
    p=Path(path)
    if not p.exists():return math.nan
    m=re.search(r'elapsed=([0-9.eE+\-]+)',p.read_text(errors='ignore'));return float(m.group(1)) if m else math.nan

def stats(vals):
    a=np.asarray([x for x in vals if math.isfinite(x)],float)
    if len(a)==0:return dict(n=0,mean=math.nan,std=math.nan,sem=math.nan,cv=math.nan,lo=math.nan,hi=math.nan)
    mean=float(np.mean(a));std=float(np.std(a,ddof=1)) if len(a)>1 else 0.;sem=std/math.sqrt(len(a))
    return dict(n=len(a),mean=mean,std=std,sem=sem,cv=std/abs(mean) if mean else math.nan,lo=mean-1.96*sem,hi=mean+1.96*sem)

def main():
    p=argparse.ArgumentParser();p.add_argument('--campaign-root',type=Path,required=True);p.add_argument('--reference-x13c-root',type=Path,required=True);p.add_argument('--repo-root',type=Path,default=Path('.'));a=p.parse_args()
    root=a.repo_root.resolve();x13b=load_module(root/'scripts'/'analyze_0493x13b_constitutive_transport.py','x13b')
    w1=x13b.load_w1(root);run_root=a.campaign_root/'H_longwave_Ny256';manifest=run_root/'manifest_0493x13d_H256.csv';analysis=a.campaign_root/'analysis';analysis.mkdir(parents=True,exist_ok=True)
    runs=[]
    for row in read_csv(manifest):
        try:
            r=x13b.analyze_shear_run(w1,row,run_root);r['elapsedSeconds']=elapsed(run_root/row['runDir']/'logs'/'time_0493x13d.txt');T=ff(row,'physicalTime');r['elapsedSecPerPhysicalTime']=r['elapsedSeconds']/T if T>0 else math.nan;runs.append(r)
        except Exception as e:runs.append({**row,'shearStatus':'ERROR','error':str(e)})
    write_csv(analysis/'H_longwave_runs_0493x13d.csv',runs)
    by={}
    for r in runs:by.setdefault(r['fluid'],[]).append(r)
    summ=[]
    for fluid,grp in sorted(by.items()):
        valid=[r for r in grp if r.get('shearStatus') in ('PASS','REVIEW') and math.isfinite(ff(r,'nuT'))]
        s=stats([ff(r,'nuT') for r in valid]);ws=stats([ff(r,'elapsedSecPerPhysicalTime') for r in grp]);passf=sum(r.get('shearStatus')=='PASS' for r in grp)/len(grp)
        r2=[ff(r,'shearFitR2') for r in valid];base=grp[0]
        grade='PASS' if len(valid)==len(grp) and passf>=.75 and s['cv']<=.12 and (min(r2) if r2 else 0)>=.98 else ('REVIEW' if len(valid)>=3 and s['cv']<=.22 else 'INVALID_OR_NOISY')
        summ.append({'fluid':fluid,'gamma':base['gamma'],'wavelengthCells':base['wavelengthCells'],'kLambda':base['kLambda'],'expectedSeeds':len(grp),'validSeeds':len(valid),'passFraction':passf,'nuTMean':s['mean'],'nuTStd':s['std'],'nuTSem':s['sem'],'nuTCV':s['cv'],'nuTCI95Low':s['lo'],'nuTCI95High':s['hi'],'shearFitR2Mean':float(np.mean(r2)) if r2 else math.nan,'shearFitR2Min':min(r2) if r2 else math.nan,'elapsedSecPerPhysicalTimeMean':ws['mean'],'wavelengthGrade':grade})
    write_csv(analysis/'H_longwave_summary_0493x13d.csv',summ)

    ref=read_csv(a.reference_x13c_root/'analysis'/'H_gamma_wavelength_summary_0493x13c.csv');refmap={(r['fluid'],int(ff(r,'wavelengthCells',-1))):r for r in ref}
    locality=[]
    for s in summ:
        f=s['fluid'];r64=refmap.get((f,64),{});r128=refmap.get((f,128),{});m128=ff(r128,'nuTMean');se128=ff(r128,'nuTSem');m256=ff(s,'nuTMean');se256=ff(s,'nuTSem')
        rel=abs(m256-m128)/(0.5*(m256+m128)) if m256>0 and m128>0 else math.nan
        z=abs(m256-m128)/math.sqrt(se256*se256+se128*se128) if math.isfinite(se256) and math.isfinite(se128) and (se256>0 or se128>0) else math.nan
        if s['wavelengthGrade']=='PASS' and ((math.isfinite(rel) and rel<=.08) or (math.isfinite(z) and z<=1.5)):grade='LOCAL_PASS'
        elif s['wavelengthGrade'] in ('PASS','REVIEW') and ((math.isfinite(rel) and rel<=.15) or (math.isfinite(z) and z<=2.0)):grade='LOCAL_REVIEW'
        else:grade='NONLOCAL_OR_UNRESOLVED'
        locality.append({'fluid':f,'gamma':s['gamma'],'nuT64Mean':ff(r64,'nuTMean'),'nuT128Mean':m128,'nuT256Mean':m256,'nuT256Std':ff(s,'nuTStd'),'nuT256CV':ff(s,'nuTCV'),'difference128to256Relative':rel,'difference128to256Z':z,'localityGrade':grade,'kLambda256':s['kLambda'],'elapsedSecPerPhysicalTime256':s['elapsedSecPerPhysicalTimeMean']})
    write_csv(analysis/'H_longwave_locality_0493x13d.csv',locality)
    print('[0493x13d-H256-analysis] fluid nuT128 -> nuT256 relDiff z locality')
    for r in locality:print(f"  {r['fluid']:<4s} {ff(r,'nuT128Mean'):.6g} -> {ff(r,'nuT256Mean'):.6g}  rel={ff(r,'difference128to256Relative'):.3f} z={ff(r,'difference128to256Z'):.2f} {r['localityGrade']}")
    print(f'[0493x13d-H256-analysis] output={analysis}')
if __name__=='__main__':main()
