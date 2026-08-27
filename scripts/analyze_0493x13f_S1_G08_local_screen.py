#!/usr/bin/env python3
from __future__ import annotations
import argparse,csv,importlib.util,math,re
from pathlib import Path
import numpy as np

def load_module(path,name):
    spec=importlib.util.spec_from_file_location(name,path)
    if not spec or not spec.loader: raise RuntimeError(f'cannot import {path}')
    m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m

def read_csv(p):
    p=Path(p)
    if not p.exists(): return []
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

def stats(v):
    a=np.asarray([x for x in v if math.isfinite(x)],float)
    if len(a)==0:return (0,math.nan,math.nan,math.nan)
    mean=float(a.mean());sd=float(a.std(ddof=1)) if len(a)>1 else 0.0;cv=sd/abs(mean) if mean else math.nan
    return len(a),mean,sd,cv

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--campaign-root',type=Path,required=True);ap.add_argument('--repo-root',type=Path,default=Path('.'));ap.add_argument('--shortlist-n',type=int,default=3);ap.add_argument('--cs-ref',type=float,default=.3554482475790296);a=ap.parse_args()
    root=a.repo_root.resolve();run_root=a.campaign_root/'S1_screen_Ny128';analysis=a.campaign_root/'analysis';analysis.mkdir(parents=True,exist_ok=True)
    x13b=load_module(root/'scripts'/'analyze_0493x13b_constitutive_transport.py','x13b');w1=x13b.load_w1(root)
    runs=[]
    for row in read_csv(run_root/'manifest_0493x13f_S1.csv'):
        marker=run_root/row['runDir']/'RUN_COMPLETE_0493x13f_S1'
        if not marker.exists():runs.append({**row,'shearStatus':'MISSING'});continue
        try:
            q=x13b.analyze_shear_run(w1,row,run_root);q['elapsedSeconds']=elapsed(run_root/row['runDir']/'logs'/'time_0493x13f.txt');runs.append(q)
        except Exception as e:runs.append({**row,'shearStatus':'ERROR','error':str(e)})
    write_csv(analysis/'S1_runs_0493x13f.csv',runs)
    groups={}
    for r in runs:groups.setdefault(r['candidate'],[]).append(r)
    anchor_key='A120_L048';anchor=groups.get(anchor_key,[]);anchor_by_seed={int(ff(r,'seed',-1)):ff(r,'nuT') for r in anchor if r.get('shearStatus') in ('PASS','REVIEW') and ff(r,'nuT')>0}
    summary=[]
    for key,grp in sorted(groups.items()):
        valid=[r for r in grp if r.get('shearStatus') in ('PASS','REVIEW') and ff(r,'nuT')>0]
        n,mean,sd,cv=stats([ff(r,'nuT') for r in valid]);r2=[ff(r,'shearFitR2') for r in valid];base=grp[0];srd=ff(base,'viscositySRDKinematic')
        paired=[]
        for r in valid:
            s=int(ff(r,'seed',-1));av=anchor_by_seed.get(s,math.nan);v=ff(r,'nuT')
            if av>0 and v>0:paired.append((av-v)/av)
        _,pgain,_,_=stats(paired);pwin=sum(x>0 for x in paired)/len(paired) if paired else math.nan
        if key==anchor_key:grade='CONTROL'
        elif n==len(grp) and min(r2,default=0)>=.98 and cv<=.20 and .60<=mean/srd<=1.60:grade='SCREEN_PASS'
        elif n>=1 and np.mean(r2) >= .95 and (not math.isfinite(cv) or cv<=.30):grade='SCREEN_REVIEW'
        else:grade='SCREEN_FAIL'
        H=a.cs_ref*ff(base,'cellSize')/mean if mean>0 else math.nan
        summary.append(dict(candidate=key,alphaDeg=base['rotationAngleDeg'],lambdaOverH=base['targetLambdaMeanOverCell'],dt=base['dt'],nuSRD=srd,validSeeds=n,expectedSeeds=len(grp),passSeeds=sum(r.get('shearStatus')=='PASS' for r in grp),nuTMean=mean,nuTStd=sd,nuTCV=cv,nuTOverSRD=mean/srd if mean>0 and srd>0 else math.nan,shearFitR2Min=min(r2,default=math.nan),pairedGainVsAnchorMean=pgain,pairedWinFraction=pwin,HhProxyUsingCsRef=H,kLambda=base['kLambda'],screenGrade=grade))
    write_csv(analysis/'S1_screen_summary_0493x13f.csv',summary)
    anchor_row=next((r for r in summary if r['candidate']==anchor_key),None);anchor_nu=ff(anchor_row or {},'nuTMean')
    eligible=[r for r in summary if r['candidate']!=anchor_key and r['screenGrade']=='SCREEN_PASS' and ff(r,'nuTMean')>0 and ff(r,'nuTMean')<.98*anchor_nu and ff(r,'pairedWinFraction',0)>=.5]
    eligible.sort(key=lambda r:(ff(r,'nuTMean'),ff(r,'nuTCV')))
    if len(eligible)<a.shortlist_n:
        supplement=[r for r in summary if r['candidate']!=anchor_key and r not in eligible and r['screenGrade'] in ('SCREEN_PASS','SCREEN_REVIEW') and ff(r,'nuTMean')>0]
        supplement.sort(key=lambda r:(ff(r,'nuTMean'),ff(r,'nuTCV')));eligible.extend(supplement[:max(0,a.shortlist_n-len(eligible))])
    selected=[dict(rank=0,selected=1,selectionReason='anchor_control',**anchor_row)] if anchor_row else []
    for i,r in enumerate(eligible[:a.shortlist_n],1):selected.append(dict(rank=i,selected=1,selectionReason='lowest_clean_nuT',**r))
    write_csv(analysis/'S1_shortlist_0493x13f.csv',selected)
    print('[0493x13f-S1-analysis] candidate alpha lambda nuT gainVsAnchor grade')
    for r in sorted(summary,key=lambda x:ff(x,'nuTMean')):
        print(f"  {r['candidate']} {ff(r,'alphaDeg'):5.0f} {ff(r,'lambdaOverH'):.2f} {ff(r,'nuTMean'):.6g} {100*ff(r,'pairedGainVsAnchorMean',0):+6.1f}% {r['screenGrade']}")
    print('[0493x13f-S1-analysis] shortlist:',','.join(r['candidate'] for r in selected))
if __name__=='__main__':main()
