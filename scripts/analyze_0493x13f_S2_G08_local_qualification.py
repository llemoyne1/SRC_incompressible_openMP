#!/usr/bin/env python3
from __future__ import annotations
import argparse,csv,importlib.util,math,re
from pathlib import Path
import numpy as np

def load_module(path,name):
    s=importlib.util.spec_from_file_location(name,path)
    if not s or not s.loader:raise RuntimeError(f'cannot import {path}')
    m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m

def read_csv(p):
    p=Path(p)
    if not p.exists():return []
    with p.open(newline='') as f:return list(csv.DictReader(f))

def write_csv(p,rows):
    p=Path(p);p.parent.mkdir(parents=True,exist_ok=True)
    if not rows:p.write_text('');return
    fs=[]
    for r in rows:
        for k in r:
            if k not in fs:fs.append(k)
    with p.open('w',newline='') as f:w=csv.DictWriter(f,fieldnames=fs,lineterminator='\n');w.writeheader();w.writerows(rows)

def ff(r,k,d=math.nan):
    try:return float(r[k])
    except:return d

def elapsed(p):
    p=Path(p)
    if not p.exists():return math.nan
    m=re.search(r'elapsed=([0-9.eE+\-]+)',p.read_text(errors='ignore'));return float(m.group(1)) if m else math.nan

def st(v):
    a=np.asarray([x for x in v if math.isfinite(x)],float)
    if len(a)==0:return dict(n=0,mean=math.nan,std=math.nan,sem=math.nan,cv=math.nan)
    mean=float(a.mean());sd=float(a.std(ddof=1)) if len(a)>1 else 0.;return dict(n=len(a),mean=mean,std=sd,sem=sd/math.sqrt(len(a)),cv=sd/abs(mean) if mean else math.nan)

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--campaign-root',type=Path,required=True);ap.add_argument('--repo-root',type=Path,default=Path('.'));ap.add_argument('--cs-ref',type=float,default=.3554482475790296);a=ap.parse_args()
    root=a.repo_root.resolve();s1=a.campaign_root/'S1_screen_Ny128';s2=a.campaign_root/'S2_qualification';analysis=a.campaign_root/'analysis';analysis.mkdir(parents=True,exist_ok=True)
    x13b=load_module(root/'scripts'/'analyze_0493x13b_constitutive_transport.py','x13b');w1=x13b.load_w1(root);runs=[]
    for row in read_csv(s2/'manifest_0493x13f_S2.csv'):
        reuse=int(ff(row,'reuseFromS1',0))==1;rr=s1 if reuse else s2;marker=rr/row['runDir']/('RUN_COMPLETE_0493x13f_S1' if reuse else 'RUN_COMPLETE_0493x13f_S2')
        if not marker.exists():runs.append({**row,'shearStatus':'MISSING'});continue
        try:
            q=x13b.analyze_shear_run(w1,row,rr);q['sourceRoot']='S1' if reuse else 'S2';q['elapsedSeconds']=elapsed(rr/row['runDir']/'logs'/'time_0493x13f.txt');runs.append(q)
        except Exception as e:runs.append({**row,'shearStatus':'ERROR','error':str(e)})
    write_csv(analysis/'S2_runs_0493x13f.csv',runs)
    groups={}
    for r in runs:groups.setdefault((r['candidate'],int(ff(r,'wavelengthCells',-1))),[]).append(r)
    wave=[]
    for (c,ny),g in sorted(groups.items()):
        valid=[r for r in g if r.get('shearStatus') in ('PASS','REVIEW') and ff(r,'nuT')>0];ss=st([ff(r,'nuT') for r in valid]);r2=[ff(r,'shearFitR2') for r in valid];base=g[0];passf=sum(r.get('shearStatus')=='PASS' for r in g)/len(g)
        grade='PASS' if len(valid)==len(g) and passf>=.75 and ss['cv']<=.12 and min(r2,default=0)>=.98 else ('REVIEW' if len(valid)>=3 and ss['cv']<=.22 and np.mean(r2)>=.95 else 'INVALID_OR_NOISY')
        wave.append(dict(candidate=c,alphaDeg=base['rotationAngleDeg'],lambdaOverH=base['targetLambdaMeanOverCell'],wavelengthCells=ny,kLambda=base['kLambda'],nuSRD=base['viscositySRDKinematic'],validSeeds=len(valid),expectedSeeds=len(g),passFraction=passf,nuTMean=ss['mean'],nuTStd=ss['std'],nuTSem=ss['sem'],nuTCV=ss['cv'],shearFitR2Min=min(r2,default=math.nan),wavelengthGrade=grade))
    write_csv(analysis/'S2_wavelength_summary_0493x13f.csv',wave)
    by={}
    for r in wave:by.setdefault(r['candidate'],{})[int(r['wavelengthCells'])]=r
    anchor='A120_L048';anchor256=ff(by.get(anchor,{}).get(256,{}),'nuTMean');final=[]
    for c,d in sorted(by.items()):
        r128=d.get(128,{});r256=d.get(256,{});m128=ff(r128,'nuTMean');m256=ff(r256,'nuTMean');se128=ff(r128,'nuTSem');se256=ff(r256,'nuTSem')
        rel=abs(m256-m128)/(0.5*(m256+m128)) if m128>0 and m256>0 else math.nan;den=math.sqrt(se128**2+se256**2) if math.isfinite(se128) and math.isfinite(se256) else math.nan;z=abs(m256-m128)/den if den and den>0 else math.nan
        if r256.get('wavelengthGrade')=='PASS' and r128.get('wavelengthGrade') in ('PASS','REVIEW') and ((math.isfinite(rel) and rel<=.08) or (math.isfinite(z) and z<=1.5)):local='LOCAL_PASS'
        elif r256.get('wavelengthGrade') in ('PASS','REVIEW') and r128.get('wavelengthGrade') in ('PASS','REVIEW') and ((math.isfinite(rel) and rel<=.15) or (math.isfinite(z) and z<=2.0)):local='LOCAL_REVIEW'
        else:local='NONLOCAL_OR_UNRESOLVED'
        nu=m256 if m256>0 else math.nan;h=.00390625;H=a.cs_ref*h/nu if nu>0 else math.nan;gain=anchor256/nu if anchor256>0 and nu>0 else math.nan
        row=dict(candidate=c,alphaDeg=r256.get('alphaDeg',r128.get('alphaDeg','')),lambdaOverH=r256.get('lambdaOverH',r128.get('lambdaOverH','')),nuT128Mean=m128,nuT256Mean=m256,nuT256CV=ff(r256,'nuTCV'),difference128to256Relative=rel,difference128to256Z=z,localityGrade=local,nuTOverSRD256=nu/ff(r256,'nuSRD') if nu>0 and ff(r256,'nuSRD')>0 else math.nan,HhProxyUsingCsRef=H,reachGainVsAnchor=gain,csReferenceAssumed=a.cs_ref)
        for ma in (.1,.3,.5,.7,.9):row[f'cellsForRe1e4_Ma{str(ma).replace(".","p")}']=10000/(ma*H) if H>0 else math.nan
        row['finalGrade']='FINAL_PASS' if local=='LOCAL_PASS' and r256.get('wavelengthGrade')=='PASS' else ('FINAL_REVIEW' if local=='LOCAL_REVIEW' else 'FINAL_FAIL')
        final.append(row)
    good=[r for r in final if r['finalGrade']=='FINAL_PASS'];good.sort(key=lambda r:-ff(r,'HhProxyUsingCsRef'))
    for r in final:r['rankAmongFinalPass']=(good.index(r)+1) if r in good else ''
    write_csv(analysis/'S2_final_qualification_0493x13f.csv',final)
    print('[0493x13f-S2-analysis] candidate nu128 -> nu256 locality HhProxy gainVsAnchor')
    for r in sorted(final,key=lambda x:-ff(x,'HhProxyUsingCsRef',-1)):
        print(f"  {r['candidate']} {ff(r,'nuT128Mean'):.6g} -> {ff(r,'nuT256Mean'):.6g} {r['localityGrade']:<12s} Hh={ff(r,'HhProxyUsingCsRef'):.3f} gain={ff(r,'reachGainVsAnchor'):.3f}")
    if good:print('[0493x13f-S2-analysis] best=',good[0]['candidate'],'NOTE: cs is still the G08-anchor x13d reference and must be requalified acoustically for the winning parameter point.')
if __name__=='__main__':main()
