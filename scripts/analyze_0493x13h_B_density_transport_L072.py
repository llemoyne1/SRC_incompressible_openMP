#!/usr/bin/env python3
from __future__ import annotations
import argparse,csv,importlib.util,math,re
from pathlib import Path
import numpy as np

def load_module(path,name):
    s=importlib.util.spec_from_file_location(name,path)
    if not s or not s.loader: raise RuntimeError(f'cannot import {path}')
    m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m

def read_csv(p):
    p=Path(p)
    if not p.exists(): return []
    with p.open(newline='') as f:return list(csv.DictReader(f))

def write_csv(p,rows):
    p=Path(p);p.parent.mkdir(parents=True,exist_ok=True)
    if not rows:p.write_text('');return
    fields=[]
    for r in rows:
        for k in r:
            if k not in fields:fields.append(k)
    with p.open('w',newline='') as f:
        w=csv.DictWriter(f,fieldnames=fields,lineterminator='\n');w.writeheader();w.writerows(rows)

def ff(r,k,d=math.nan):
    try:return float(r[k])
    except:return d

def stats(v):
    a=np.asarray([x for x in v if math.isfinite(x)],float)
    if len(a)==0:return dict(n=0,mean=math.nan,std=math.nan,sem=math.nan,cv=math.nan)
    mean=float(a.mean());sd=float(a.std(ddof=1)) if len(a)>1 else 0.;return dict(n=len(a),mean=mean,std=sd,sem=sd/math.sqrt(len(a)),cv=sd/abs(mean) if mean else math.nan)

def elapsed(p):
    try:
        m=re.search(r'elapsed=([0-9.eE+\-]+)',Path(p).read_text(errors='ignore'));return float(m.group(1)) if m else math.nan
    except:return math.nan

def linear_fit(x,y):
    x=np.asarray(x,float);y=np.asarray(y,float);mask=np.isfinite(x)&np.isfinite(y);x=x[mask];y=y[mask]
    A=np.column_stack((x,np.ones_like(x)));coef,*_=np.linalg.lstsq(A,y,rcond=None);pred=A@coef;sse=float(np.sum((y-pred)**2));sst=float(np.sum((y-y.mean())**2));r2=1-sse/sst if sst>0 else 1.0
    return float(coef[0]),r2,len(x)

def fit_series(t,amp,k):
    t=np.asarray(t,float);a=np.abs(np.asarray(amp,float));ratio=a/max(a[0],1e-300);n=len(t);cand=[]
    for sf in (0.0,.03,.06,.10):
        start=max(1,int(round(sf*(n-1))))
        for ef in (.35,.50,.65,.80,1.0):
            end=max(start+7,min(n,int(round(ef*n))));mask=np.zeros(n,bool);mask[start:end]=True;mask&=a>0;mask&=ratio>.04
            if np.count_nonzero(mask)<7:continue
            slope,r2,pts=linear_fit(t[mask],np.log(a[mask]));nu=-slope/(k*k);span=float(np.ptp(np.log(a[mask])))
            if nu>0 and span>=.20:cand.append((r2,min(span,3.0),pts,nu,span))
    if not cand:return dict(status='INVALID',nuT=math.nan,r2=math.nan,points=0,span=math.nan)
    r2,_,pts,nu,span=max(cand,key=lambda q:(q[0],q[1],q[2]))
    status='PASS' if r2>=.98 and span>=.35 else ('REVIEW' if r2>=.93 else 'INVALID')
    return dict(status=status,nuT=nu,r2=r2,points=pts,span=span)

def shear_series(w1,row,runroot):
    run=runroot/row['runDir'];dt=ff(row,'dt');Ly=ff(row,'Ly');mode=int(float(row['modeY']));k=2*math.pi*mode/Ly;ser=[]
    for step,path in w1.list_dumps(run):
        st=w1.read_state(path);mask=st['role']==1;y=st['y'][mask];m=st['mass'][mask];vx=st['vx'][mask];b=np.sin(k*y);den=np.sum(m*b*b);amp=float(np.sum(m*vx*b)/den);ser.append((step,step*dt,amp))
    return ser,k

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--campaign-root',type=Path,default=Path('runs/0493x13h_L072_qualification'));ap.add_argument('--repo-root',type=Path,default=Path('.'));a=ap.parse_args()
    root=a.repo_root.resolve();rr=a.campaign_root/'B_density';analysis=a.campaign_root/'analysis';analysis.mkdir(parents=True,exist_ok=True)
    x13b=load_module(root/'scripts/analyze_0493x13b_constitutive_transport.py','x13b_h');w1=x13b.load_w1(root)
    manifest=read_csv(rr/'manifest_0493x13h_B_density.csv');runs=[];series={}
    for row in manifest:
        marker=rr/row['runDir']/'RUN_COMPLETE_0493x13h_B_density'
        if not marker.exists():runs.append({**row,'shearStatus':'MISSING'});continue
        try:
            q=x13b.analyze_shear_run(w1,row,rr);q['elapsedSeconds']=elapsed(rr/row['runDir']/'logs/time_0493x13h_B.txt');ser,k=shear_series(w1,row,rr);series[(int(ff(row,'gamma')),int(ff(row,'wavelengthCells')),int(ff(row,'seed')))]=(ser,k);runs.append(q)
        except Exception as e:runs.append({**row,'shearStatus':'ERROR','error':str(e)})
    write_csv(analysis/'B_density_runs_0493x13h.csv',runs)
    summary=[]
    for gamma,ny in sorted({(int(ff(r,'gamma')) ,int(ff(r,'wavelengthCells'))) for r in runs}):
        g=[r for r in runs if int(ff(r,'gamma'))==gamma and int(ff(r,'wavelengthCells'))==ny and r.get('shearStatus') in ('PASS','REVIEW')]
        s=stats([ff(r,'nuT') for r in g]);r2=[ff(r,'shearFitR2') for r in g];stack=[];tref=None;kref=math.nan
        for r in g:
            key=(gamma,ny,int(ff(r,'seed')))
            if key not in series:continue
            ser,k=series[key];t=np.asarray([z[1] for z in ser]);amp=np.asarray([z[2] for z in ser])
            if tref is None:tref=t;kref=k
            if len(t)==len(tref) and np.allclose(t,tref,rtol=0,atol=1e-12):stack.append(amp)
        ens=fit_series(tref,np.mean(np.vstack(stack),axis=0),kref) if stack else dict(status='MISSING',nuT=math.nan,r2=math.nan,points=0,span=math.nan)
        base=next(r for r in runs if int(ff(r,'gamma'))==gamma and int(ff(r,'wavelengthCells'))==ny)
        passf=sum(r.get('shearStatus')=='PASS' for r in g)/max(1,len([r for r in runs if int(ff(r,'gamma'))==gamma and int(ff(r,'wavelengthCells'))==ny]))
        grade='PASS' if len(g)>=5 and passf>=.75 and ens['status']=='PASS' and ens['r2']>=.98 and s['cv']<=.22 else ('REVIEW' if len(g)>=4 and ens['status'] in ('PASS','REVIEW') and s['cv']<=.30 else 'UNRESOLVED')
        summary.append(dict(gamma=gamma,wavelengthCells=ny,kLambda=ff(base,'kLambda'),nuSRD=ff(base,'viscositySRDKinematic'),expectedSeeds=int(ff(base,'expectedSeeds')),validSeeds=len(g),passFraction=passf,nuTIndividualMean=s['mean'],nuTIndividualStd=s['std'],nuTIndividualSem=s['sem'],nuTIndividualCV=s['cv'],nuTEnsembleFit=ens['nuT'],ensembleFitR2=ens['r2'],ensembleFitStatus=ens['status'],nuTEnsembleOverSRD=ens['nuT']/ff(base,'viscositySRDKinematic') if ff(base,'viscositySRDKinematic')>0 and math.isfinite(ens['nuT']) else math.nan,grade=grade))
    write_csv(analysis/'B_density_summary_0493x13h.csv',summary)
    qual=[]
    by={}
    for r in summary:by.setdefault(int(r['gamma']),{})[int(r['wavelengthCells'])]=r
    for gamma,d in sorted(by.items()):
        r128=d.get(128);r256=d.get(256);n128=ff(r128 or {},'nuTEnsembleFit');n256=ff(r256 or {},'nuTEnsembleFit')
        rel=abs(n256-n128)/(0.5*(n256+n128)) if n128>0 and n256>0 else math.nan
        if r256:
            if r128.get('grade')=='PASS' and r256.get('grade')=='PASS' and rel<=.15:grade='LOCAL_PASS'
            elif r128.get('grade') in ('PASS','REVIEW') and r256.get('grade') in ('PASS','REVIEW') and rel<=.25:grade='LOCAL_REVIEW'
            else:grade='UNRESOLVED'
            nu=n256
        else:
            grade='SCREEN_PASS' if r128 and r128.get('grade')=='PASS' else ('SCREEN_REVIEW' if r128 and r128.get('grade')=='REVIEW' else 'UNRESOLVED');nu=n128
        qual.append(dict(gamma=gamma,nuT128Ensemble=n128,nuT256Ensemble=n256,wavelengthRelativeDifference=rel,densityTransportGrade=grade,nuTReference=nu,nuTRatioVsGamma8=math.nan))
    ref=next((r for r in qual if r['gamma']==8),None);refnu=ff(ref or {},'nuTReference')
    for r in qual:
        r['nuTRatioVsGamma8']=ff(r,'nuTReference')/refnu if refnu>0 and ff(r,'nuTReference')>0 else math.nan
    write_csv(analysis/'B_density_qualification_0493x13h.csv',qual)
    print('[0493x13h-B-analysis] gamma nu128_ens nu256_ens grade ratio_vs_g8')
    for r in qual:print(f"  {r['gamma']:>2d} {ff(r,'nuT128Ensemble'):.6g} {ff(r,'nuT256Ensemble'):.6g} {r['densityTransportGrade']:<14s} {ff(r,'nuTRatioVsGamma8'):.4g}")
if __name__=='__main__':main()
