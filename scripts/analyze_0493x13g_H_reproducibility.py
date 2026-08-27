#!/usr/bin/env python3
from __future__ import annotations
import argparse,csv,hashlib,importlib.util,math,re
from pathlib import Path
import numpy as np

def load_module(path,name):
    s=importlib.util.spec_from_file_location(name,path)
    if not s or not s.loader: raise RuntimeError(f'cannot import {path}')
    m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m

def read_csv(p):
    p=Path(p)
    if not p.exists():return []
    with p.open(newline='') as f:return list(csv.DictReader(f))

def write_csv(p,rows):
    p=Path(p);p.parent.mkdir(parents=True,exist_ok=True)
    if not rows:p.write_text('');return
    fields=[]
    for r in rows:
        for k in r:
            if k not in fields:fields.append(k)
    with p.open('w',newline='') as f:w=csv.DictWriter(f,fieldnames=fields,lineterminator='\n');w.writeheader();w.writerows(rows)

def ff(r,k,d=math.nan):
    try:return float(r[k])
    except:return d

def elapsed(p):
    p=Path(p)
    if not p.exists():return math.nan
    m=re.search(r'elapsed=([0-9.eE+\-]+)',p.read_text(errors='ignore'));return float(m.group(1)) if m else math.nan

def sha256(p):
    h=hashlib.sha256()
    with open(p,'rb') as f:
        while True:
            b=f.read(1<<20)
            if not b:break
            h.update(b)
    return h.hexdigest()

def stats(v):
    a=np.asarray([x for x in v if math.isfinite(x)],float)
    if len(a)==0:return dict(n=0,mean=math.nan,std=math.nan,sem=math.nan,cv=math.nan,min=math.nan,max=math.nan,rangeRel=math.nan)
    mean=float(a.mean());sd=float(a.std(ddof=1)) if len(a)>1 else 0.;sem=sd/math.sqrt(len(a));rr=(float(a.max()-a.min())/abs(mean)) if mean else math.nan
    return dict(n=len(a),mean=mean,std=sd,sem=sem,cv=sd/abs(mean) if mean else math.nan,min=float(a.min()),max=float(a.max()),rangeRel=rr)

def linear_fit(x,y):
    x=np.asarray(x,float);y=np.asarray(y,float);mask=np.isfinite(x)&np.isfinite(y);x=x[mask];y=y[mask]
    A=np.column_stack((x,np.ones_like(x)));coef,*_=np.linalg.lstsq(A,y,rcond=None);pred=A@coef;sse=float(np.sum((y-pred)**2));sst=float(np.sum((y-y.mean())**2));r2=1-sse/sst if sst>0 else 1.0
    return float(coef[0]),float(coef[1]),r2,len(x)

def fit_series(t,amp,k):
    t=np.asarray(t,float);a=np.abs(np.asarray(amp,float));ratio=a/max(a[0],1e-300);n=len(t);cand=[]
    for sf in (0.0,0.03,0.06,0.10):
        start=max(1,int(round(sf*(n-1))))
        for ef in (0.35,0.50,0.65,0.80,1.0):
            end=max(start+7,min(n,int(round(ef*n))));mask=np.zeros(n,bool);mask[start:end]=True;mask&=a>0;mask&=ratio>0.04
            if np.count_nonzero(mask)<7:continue
            slope,inter,r2,pts=linear_fit(t[mask],np.log(a[mask]));nu=-slope/(k*k);span=float(np.ptp(np.log(a[mask])))
            if nu>0 and span>=.20:cand.append((r2,min(span,3.0),pts,nu,start,end,span))
    if not cand:
        mask=(t>0)&(a>0);slope,inter,r2,pts=linear_fit(t[mask],np.log(a[mask]));nu=-slope/(k*k);chosen=(r2,math.nan,pts,nu,1,n,math.nan)
    else:chosen=max(cand,key=lambda q:(q[0],q[1],q[2]))
    r2,_,pts,nu,start,end,span=chosen
    status='PASS' if nu>0 and r2>=.98 and (math.isnan(span) or span>=.35) else ('REVIEW' if nu>0 and r2>=.93 and (math.isnan(span) or span>=.20) else 'INVALID')
    return dict(status=status,nuT=nu,r2=r2,points=pts,span=span,start=start,end=end)

def shear_series(w1,row,runroot):
    run=runroot/row['runDir'];dt=ff(row,'dt');Ly=ff(row,'Ly');mode=int(float(row['modeY']));k=2*math.pi*mode/Ly;ser=[]
    dumps=w1.list_dumps(run)
    for step,path in dumps:
        st=w1.read_state(path);mask=st['role']==1;y=st['y'][mask];m=st['mass'][mask];vx=st['vx'][mask];b=np.sin(k*y);den=np.sum(m*b*b);amp=float(np.sum(m*vx*b)/den);ser.append((step,step*dt,amp))
    return ser,k,dumps[-1][1] if dumps else None

def bootstrap_paired(reductions,nboot=20000,seed=4931701):
    a=np.asarray(reductions,float);a=a[np.isfinite(a)]
    if len(a)==0:return dict(mean=math.nan,lo=math.nan,hi=math.nan,probPositive=math.nan)
    rng=np.random.default_rng(seed);means=np.empty(nboot)
    for i in range(nboot):means[i]=rng.choice(a,size=len(a),replace=True).mean()
    return dict(mean=float(a.mean()),lo=float(np.quantile(means,.025)),hi=float(np.quantile(means,.975)),probPositive=float(np.mean(means>0)))

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--campaign-root',type=Path,required=True);ap.add_argument('--repo-root',type=Path,default=Path('.'));ap.add_argument('--bootstrap',type=int,default=20000);a=ap.parse_args()
    root=a.repo_root.resolve();rr=a.campaign_root/'H_reproducibility';analysis=a.campaign_root/'analysis';analysis.mkdir(parents=True,exist_ok=True)
    x13b=load_module(root/'scripts'/'analyze_0493x13b_constitutive_transport.py','x13b');w1=x13b.load_w1(root)
    rows=read_csv(rr/'manifest_0493x13g_Hrepro.csv');runs=[];series={}
    for row in rows:
        marker=rr/row['runDir']/'RUN_COMPLETE_0493x13g_Hrepro'
        if not marker.exists():runs.append({**row,'shearStatus':'MISSING'});continue
        try:
            q=x13b.analyze_shear_run(w1,row,rr);q['elapsedSeconds']=elapsed(rr/row['runDir']/'logs/time_0493x13g.txt');ser,k,last=shear_series(w1,row,rr);q['finalDumpSha256']=sha256(last) if last else '';runs.append(q);series[(row['candidate'],row['track'],int(float(row['replicateIndex'])))] = (ser,k)
        except Exception as e:runs.append({**row,'shearStatus':'ERROR','error':str(e)})
    write_csv(analysis/'H_repro_runs_0493x13g.csv',runs)
    # Repeat groups and independent groups. Independent includes repeat_same rep0 as seed 4931411.
    candidates=sorted({r['candidate'] for r in runs});group=[]
    for c in candidates:
        rep=[r for r in runs if r['candidate']==c and r['track']=='repeat_same' and r.get('shearStatus') in ('PASS','REVIEW')]
        indep=[r for r in runs if r['candidate']==c and r['track']=='independent' and r.get('shearStatus') in ('PASS','REVIEW')]
        if rep: indep=[rep[0]]+indep
        for name,g in [('repeat_same',rep),('independent8',indep)]:
            s=stats([ff(r,'nuT') for r in g]);r2=[ff(r,'shearFitR2') for r in g];passf=sum(r.get('shearStatus')=='PASS' for r in g)/len(g) if g else 0
            # Ensemble-average signed amplitude, same time grid within each group/candidate.
            stack=[];tref=None;kref=math.nan
            for r in g:
                key=(c,r['track'],int(float(r['replicateIndex'])))
                if key not in series:continue
                ser,k=series[key];t=np.asarray([z[1] for z in ser]);amp=np.asarray([z[2] for z in ser])
                if tref is None:tref=t;kref=k
                if len(t)==len(tref) and np.allclose(t,tref,rtol=0,atol=1e-12):stack.append(amp)
            ens=fit_series(tref,np.mean(np.vstack(stack),axis=0),kref) if stack else dict(status='MISSING',nuT=math.nan,r2=math.nan,points=0,span=math.nan)
            trajcv=math.nan
            if name=='repeat_same' and len(stack)>=2:
                aa=np.vstack(stack);mean=np.mean(aa,axis=0);sd=np.std(aa,axis=0,ddof=1);mask=np.abs(mean)>.1*abs(mean[0]);rel=np.divide(sd,np.abs(mean),out=np.zeros_like(sd),where=np.abs(mean)>0);trajcv=float(np.sqrt(np.mean(rel[mask]**2))) if np.any(mask) else math.nan
            hashes={r.get('finalDumpSha256','') for r in g if r.get('finalDumpSha256','')}
            if name=='repeat_same':execgrade='EXEC_PASS' if s['cv']<=.02 and s['rangeRel']<=.05 else ('EXEC_REVIEW' if s['cv']<=.05 and s['rangeRel']<=.12 else 'EXEC_UNSTABLE')
            else:execgrade='ENSEMBLE_PASS' if len(g)>=7 and passf>=.75 and s['cv']<=.12 and min(r2,default=0)>=.98 else ('ENSEMBLE_REVIEW' if len(g)>=6 and s['cv']<=.20 and np.mean(r2)>=.95 else 'ENSEMBLE_UNRESOLVED')
            base=(g[0] if g else next(r for r in runs if r['candidate']==c))
            group.append(dict(candidate=c,track=name,lambdaOverH=base['targetLambdaMeanOverCell'],runs=len(g),passFraction=passf,nuTMean=s['mean'],nuTStd=s['std'],nuTSem=s['sem'],nuTCV=s['cv'],nuTRangeRelative=s['rangeRel'],shearFitR2Min=min(r2,default=math.nan),ensembleFitStatus=ens['status'],nuTEnsembleFit=ens['nuT'],ensembleFitR2=ens['r2'],repeatTrajectoryRelativeSpreadRms=trajcv,uniqueFinalDumpHashes=len(hashes),groupGrade=execgrade))
    write_csv(analysis/'H_repro_group_summary_0493x13g.csv',group)
    # Paired comparisons by repeat index and by independent seed. For independent, seed 4931411 is rep0.
    pairrows=[]
    by={(r['candidate'],r['track'],int(float(r['replicateIndex']))):r for r in runs if r.get('shearStatus') in ('PASS','REVIEW')}
    # repeat pairs
    reductions=[]
    nrep=max([int(float(r['replicateIndex'])) for r in runs if r['track']=='repeat_same'],default=-1)+1
    for i in range(nrep):
        a0=by.get(('A120_L048','repeat_same',i));a1=by.get(('A120_L072','repeat_same',i))
        if a0 and a1:
            red=(ff(a0,'nuT')-ff(a1,'nuT'))/ff(a0,'nuT');reductions.append(red);pairrows.append(dict(track='repeat_same',pair=str(i),nuT048=ff(a0,'nuT'),nuT072=ff(a1,'nuT'),relativeReduction072Vs048=red,ratio072Over048=ff(a1,'nuT')/ff(a0,'nuT')))
    b=bootstrap_paired(reductions,a.bootstrap,4931702);pairsummary=[dict(track='repeat_same',pairs=len(reductions),meanRelativeReduction=b['mean'],bootstrapCI95Low=b['lo'],bootstrapCI95High=b['hi'],bootstrapProbabilityReductionPositive=b['probPositive'])]
    # independent paired seeds: rep0 supplies 4931411; new independent rows supply the rest.
    indep_by={}
    for c in ('A120_L048','A120_L072'):
        rep0=by.get((c,'repeat_same',0))
        if rep0:indep_by[(c,int(float(rep0['runtimeSeed'])))]=rep0
        for r in runs:
            if r['candidate']==c and r['track']=='independent' and r.get('shearStatus') in ('PASS','REVIEW'):indep_by[(c,int(float(r['runtimeSeed'])))]=r
    seeds=sorted({s for c,s in indep_by if c=='A120_L048'} & {s for c,s in indep_by if c=='A120_L072'});reductions=[]
    for seed in seeds:
        a0=indep_by[('A120_L048',seed)];a1=indep_by[('A120_L072',seed)];red=(ff(a0,'nuT')-ff(a1,'nuT'))/ff(a0,'nuT');reductions.append(red);pairrows.append(dict(track='independent8',pair=str(seed),nuT048=ff(a0,'nuT'),nuT072=ff(a1,'nuT'),relativeReduction072Vs048=red,ratio072Over048=ff(a1,'nuT')/ff(a0,'nuT')))
    b=bootstrap_paired(reductions,a.bootstrap,4931703);pairsummary.append(dict(track='independent8',pairs=len(reductions),meanRelativeReduction=b['mean'],bootstrapCI95Low=b['lo'],bootstrapCI95High=b['hi'],bootstrapProbabilityReductionPositive=b['probPositive']))
    write_csv(analysis/'H_repro_pairs_0493x13g.csv',pairrows);write_csv(analysis/'H_repro_pair_summary_0493x13g.csv',pairsummary)
    # Decision: execution reproducibility first, then paired independent evidence.
    gmap={(r['candidate'],r['track']):r for r in group};ps={r['track']:r for r in pairsummary};r48=gmap.get(('A120_L048','independent8'),{});r72=gmap.get(('A120_L072','independent8'),{});rep48=gmap.get(('A120_L048','repeat_same'),{});rep72=gmap.get(('A120_L072','repeat_same'),{});p=ps.get('independent8',{})
    if rep48.get('groupGrade')=='EXEC_UNSTABLE' or rep72.get('groupGrade')=='EXEC_UNSTABLE':decision='EXECUTION_REPRODUCIBILITY_UNRESOLVED'
    elif r48.get('groupGrade')=='ENSEMBLE_UNRESOLVED' or r72.get('groupGrade')=='ENSEMBLE_UNRESOLVED':decision='INTERREALIZATION_VARIANCE_UNRESOLVED'
    elif ff(p,'bootstrapCI95Low')>0 and ff(p,'bootstrapProbabilityReductionPositive')>=.95:decision='L072_VISCOSITY_GAIN_CONFIRMED'
    elif ff(p,'bootstrapCI95Low')>-0.05 and ff(p,'bootstrapProbabilityReductionPositive')>=.80:decision='L072_COST_PREFERRED_VISCOSITY_NOT_WORSE_BY_5PCT'
    elif ff(p,'meanRelativeReduction')>0:decision='L072_GAIN_SUGGESTED_NOT_CONFIRMED'
    else:decision='L048_PREFERRED_OR_INCONCLUSIVE'
    dt48=.004231421876608172;dt72=.0063471328149122585
    decisionrow=dict(decision=decision,nuT048IndependentMean=ff(r48,'nuTMean'),nuT072IndependentMean=ff(r72,'nuTMean'),nuT048EnsembleFit=ff(r48,'nuTEnsembleFit'),nuT072EnsembleFit=ff(r72,'nuTEnsembleFit'),pairedMeanRelativeReduction=ff(p,'meanRelativeReduction'),pairedCI95Low=ff(p,'bootstrapCI95Low'),pairedCI95High=ff(p,'bootstrapCI95High'),pairedProbabilityReductionPositive=ff(p,'bootstrapProbabilityReductionPositive'),repeatGrade048=rep48.get('groupGrade',''),repeatGrade072=rep72.get('groupGrade',''),repeatCV048=ff(rep48,'nuTCV'),repeatCV072=ff(rep72,'nuTCV'),independentCV048=ff(r48,'nuTCV'),independentCV072=ff(r72,'nuTCV'),dt048=dt48,dt072=dt72,dtRatio072Over048=dt72/dt48,stepsPerPhysicalTimeGain048Over072=dt72/dt48)
    write_csv(analysis/'H_repro_decision_0493x13g.csv',[decisionrow])
    # Historical comparison if prior campaign CSVs are present.
    hist=[]
    for label,path in [('x13d',Path('runs/0493x13d_transport_followup/analysis/H_longwave_runs_0493x13d.csv')),('x13f',Path('runs/0493x13f_G08_local_transport_optimization/analysis/S2_runs_0493x13f.csv'))]:
        if not path.exists():continue
        for r in read_csv(path):
            if int(ff(r,'wavelengthCells',-1))!=256:continue
            if label=='x13d' and r.get('fluid')!='G08':continue
            if label=='x13f' and r.get('candidate') not in ('A120_L048','A120_L072'):continue
            hist.append(dict(source=label,candidate=('A120_L048' if label=='x13d' else r.get('candidate')),seed=r.get('seed',''),nuT=r.get('nuT',''),shearFitR2=r.get('shearFitR2','')))
    write_csv(analysis/'H_repro_historical_runs_0493x13g.csv',hist)
    print('[0493x13g-analysis] group summaries')
    for r in group:print(f"  {r['candidate']} {r['track']:<12s} n={r['runs']} nu={ff(r,'nuTMean'):.6g} CV={ff(r,'nuTCV'):.3f} ens={ff(r,'nuTEnsembleFit'):.6g} {r['groupGrade']} hashes={r['uniqueFinalDumpHashes']}")
    print(f"[0493x13g-analysis] paired independent reduction={(100*ff(p,'meanRelativeReduction')):.2f}% CI95=[{100*ff(p,'bootstrapCI95Low'):.2f},{100*ff(p,'bootstrapCI95High'):.2f}]% P(gain)={ff(p,'bootstrapProbabilityReductionPositive'):.3f}")
    print('[0493x13g-analysis] decision',decision)
if __name__=='__main__':main()
