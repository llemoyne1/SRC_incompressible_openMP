#!/usr/bin/env python3
"""Statistical longitudinal-response analysis for 0493x13c-Cstat.

Uses the existing 0493w1 longitudinal hydrodynamic regression, but adds:
- individual replicate fits,
- pooled fits,
- deterministic replicate bootstrap confidence intervals,
- explicit frequency of the nuL=0 active constraint,
- amplitude-consistency qualification between epsilon=0.04 and 0.08.
No pandas.
"""
from __future__ import annotations
import argparse,csv,importlib.util,json,math,re
from pathlib import Path
import numpy as np


def load_w1(root:Path):
    path=root/'scripts'/'analyze_0493w1_src_fluid_calibrator.py'
    spec=importlib.util.spec_from_file_location('w1analysis_x13c',path)
    if not spec or not spec.loader: raise RuntimeError(f'cannot import {path}')
    mod=importlib.util.module_from_spec(spec);spec.loader.exec_module(mod);return mod


def read_csv(path):
    if not path.exists(): return []
    with path.open(newline='') as f:return list(csv.DictReader(f))


def write_csv(path,rows):
    path.parent.mkdir(parents=True,exist_ok=True)
    if not rows:path.write_text('');return
    fields=[]
    for r in rows:
        for k in r:
            if k not in fields:fields.append(k)
    with path.open('w',newline='') as f:
        w=csv.DictWriter(f,fieldnames=fields,lineterminator='\n');w.writeheader();w.writerows(rows)


def ff(r,k,default=math.nan):
    try:return float(r[k])
    except:return default


def sound_status(fit):
    cs=fit['soundSpeed']; mom=fit['momentumRelativeRms']; cont=fit['continuityRelativeRms']; cond=fit['conditionNumber']; active=fit['activeConstraints'];pts=fit['fitPoints']
    passed=cs>0 and pts>=30 and mom<=0.35 and cont<=0.25 and cond<=1e8 and active=='none'
    review=cs>0 and pts>=20 and mom<=0.65 and cont<=0.45 and cond<=1e10 and 'cs2=0' not in active
    return 'PASS' if passed else ('REVIEW' if review else 'INVALID')


def elapsed_seconds(path):
    if not path.exists():return math.nan
    m=re.search(r'elapsed=([0-9.eE+\-]+)',path.read_text(errors='ignore'))
    return float(m.group(1)) if m else math.nan


def qstats(vals):
    a=np.asarray([x for x in vals if math.isfinite(x)],float)
    if len(a)==0:return dict(n=0,mean=math.nan,std=math.nan,cv=math.nan,p025=math.nan,p50=math.nan,p975=math.nan)
    mean=float(np.mean(a));std=float(np.std(a,ddof=1)) if len(a)>1 else 0.0
    p=np.quantile(a,[.025,.5,.975])
    return dict(n=len(a),mean=mean,std=std,cv=std/abs(mean) if mean else math.nan,p025=float(p[0]),p50=float(p[1]),p975=float(p[2]))


def fit_arrays(w1,t,rho,vel,k):
    fit=w1.fit_longitudinal_hydrodynamics(t,rho,vel,k)
    return fit,sound_status(fit)


def load_group(w1,row,run_root):
    group=run_root/row['runDir']; reps=sorted(p for p in group.glob('rep*') if p.is_dir() and (p/'RUN_COMPLETE_0493x13c_Cstat').exists())
    if not reps: raise ValueError(f'no completed reps in {group}')
    k=2*math.pi*int(row['modeX'])/ff(row,'Lx'); stacks=[]; metas=[]; wall=[]
    steps_ref=None;t_ref=None
    for rep in reps:
        q=w1._sound_series_from_case(rep,ff(row,'dt'),k)
        steps=[x[0] for x in q]; t=np.asarray([x[1] for x in q],float)
        if steps_ref is None:steps_ref=steps;t_ref=t
        elif steps!=steps_ref:raise ValueError('replicate step mismatch')
        stacks.append((np.asarray([x[2] for x in q],complex),np.asarray([x[3] for x in q],complex)))
        meta=rep/'init'/'sound_0493x13c.meta.json'
        if meta.exists():
            try:metas.append(json.loads(meta.read_text()))
            except Exception:pass
        wall.append(elapsed_seconds(rep/'logs'/'time_0493x13c.txt'))
    return reps,t_ref,np.asarray([q[0] for q in stacks]),np.asarray([q[1] for q in stacks]),k,metas,wall


def main():
    p=argparse.ArgumentParser();p.add_argument('--campaign-root',type=Path,required=True);p.add_argument('--repo-root',type=Path,default=Path('.'));p.add_argument('--bootstrap',type=int,default=300);p.add_argument('--bootstrap-seed',type=int,default=4931591)
    a=p.parse_args();root=a.repo_root.resolve();w1=load_w1(root);campaign=a.campaign_root;run_root=campaign/'C_statistics';manifest=run_root/'manifest_0493x13c_Cstat.csv';analysis=campaign/'analysis';analysis.mkdir(parents=True,exist_ok=True)
    individual=[]; groups=[]
    rng_master=np.random.default_rng(a.bootstrap_seed)
    for gi,row in enumerate(read_csv(manifest)):
        try:
            reps,t,rho_stack,vel_stack,k,metas,wall=load_group(w1,row,run_root);nrep=len(reps)
            # Individual replicate fits are diagnostic statistics, not constitutive estimates.
            for ri,rep in enumerate(reps):
                try:
                    fit,status=fit_arrays(w1,t,rho_stack[ri],vel_stack[ri],k)
                    individual.append({**row,'replicate':rep.name,'soundStatus':status,'soundSpeed':fit['soundSpeed'],'nuL':fit['nuL'],'momentumRms':fit['momentumRelativeRms'],'continuityRms':fit['continuityRelativeRms'],'conditionNumber':fit['conditionNumber'],'activeConstraints':fit['activeConstraints'],'fitPoints':fit['fitPoints']})
                except Exception as e:individual.append({**row,'replicate':rep.name,'soundStatus':'ERROR','error':str(e)})
            rho=np.mean(rho_stack,axis=0);vel=np.mean(vel_stack,axis=0);fit,status=fit_arrays(w1,t,rho,vel,k)
            # Bootstrap replicates with replacement; each draw refits the averaged hydrodynamic mode.
            csb=[];nulb=[];boot_status=[];boot_active=[]
            local_rng=np.random.default_rng(int(rng_master.integers(0,2**63-1)))
            for _ in range(a.bootstrap):
                idx=local_rng.integers(0,nrep,size=nrep)
                try:
                    bf,bs=fit_arrays(w1,t,np.mean(rho_stack[idx],axis=0),np.mean(vel_stack[idx],axis=0),k)
                    csb.append(float(bf['soundSpeed']));nulb.append(float(bf['nuL']));boot_status.append(bs);boot_active.append(str(bf['activeConstraints']))
                except Exception:
                    continue
            css=qstats(csb);nuls=qstats(nulb); valid_boot=len(csb); pass_frac=sum(s=='PASS' for s in boot_status)/valid_boot if valid_boot else 0; usable_frac=sum(s in ('PASS','REVIEW') for s in boot_status)/valid_boot if valid_boot else 0
            zero_frac=sum(('nuL=0' in ac) or (v<=0) for ac,v in zip(boot_active,nulb))/valid_boot if valid_boot else math.nan
            stim=np.asarray([float(m.get('realizedCosDensityAmplitude',math.nan)) for m in metas],float);stim=stim[np.isfinite(stim)]
            target=ff(row,'amplitude');stim_mean=float(np.mean(stim)) if len(stim) else math.nan;stim_rel=(stim_mean-target)/target if target>0 and math.isfinite(stim_mean) else math.nan
            wall_s=qstats(wall);T=ff(row,'physicalTime')
            groups.append({**row,'replicatesCompleted':nrep,'pooledStatus':status,'soundSpeedPooled':fit['soundSpeed'],'nuLPooled':fit['nuL'],'momentumRmsPooled':fit['momentumRelativeRms'],'continuityRmsPooled':fit['continuityRelativeRms'],'conditionNumberPooled':fit['conditionNumber'],'activeConstraintsPooled':fit['activeConstraints'],'fitPointsPooled':fit['fitPoints'],
                'stimulusMetadataCount':len(metas),'stimulusRealizedCosMean':stim_mean,'stimulusRelativeError':stim_rel,
                'bootstrapRequested':a.bootstrap,'bootstrapCompleted':valid_boot,'bootstrapPassFraction':pass_frac,'bootstrapUsableFraction':usable_frac,
                'csBootstrapMean':css['mean'],'csBootstrapStd':css['std'],'csBootstrapCV':css['cv'],'csBootstrapP025':css['p025'],'csBootstrapMedian':css['p50'],'csBootstrapP975':css['p975'],
                'nuLBootstrapMean':nuls['mean'],'nuLBootstrapStd':nuls['std'],'nuLBootstrapCV':nuls['cv'],'nuLBootstrapP025':nuls['p025'],'nuLBootstrapMedian':nuls['p50'],'nuLBootstrapP975':nuls['p975'],'nuLBoundaryFraction':zero_frac,
                'elapsedSecondsMeanPerRep':wall_s['mean'],'elapsedSecondsStdPerRep':wall_s['std'],'elapsedSecondsTotal':float(np.nansum(wall)),'elapsedSecPerPhysicalTimeMean':wall_s['mean']/T if T>0 else math.nan,'k':k})
        except Exception as e:
            groups.append({**row,'pooledStatus':'ERROR','error':str(e)})
    write_csv(analysis/'Cstat_individual_replicates_0493x13c.csv',individual);write_csv(analysis/'Cstat_group_statistics_0493x13c.csv',groups)

    # Amplitude consistency / qualification per fluid and wavelength.
    by={}
    for r in groups:by.setdefault((r['fluid'],int(ff(r,'wavelengthCells',-1))),[]).append(r)
    qual=[]
    for (fluid,nx),grp in sorted(by.items()):
        good=sorted([r for r in grp if r.get('pooledStatus')!='ERROR'],key=lambda r:ff(r,'amplitude'))
        if len(good)<2:
            base=good[0] if good else grp[0];qual.append({'fluid':fluid,'gamma':base.get('gamma',''),'wavelengthCells':nx,'csQualification':'UNRESOLVED','nuLQualification':'UNRESOLVED','error':'need >=2 amplitudes'});continue
        lo,hi=good[0],good[-1];cslo=ff(lo,'soundSpeedPooled');cshi=ff(hi,'soundSpeedPooled');nulo=ff(lo,'nuLPooled');nuhi=ff(hi,'nuLPooled')
        csrel=abs(cshi-cslo)/(0.5*(cshi+cslo)) if cslo>0 and cshi>0 else math.nan
        nurel=abs(nuhi-nulo)/(0.5*(nuhi+nulo)) if nulo>0 and nuhi>0 else math.inf
        cs_cvs=[ff(lo,'csBootstrapCV'),ff(hi,'csBootstrapCV')];nu_cvs=[ff(lo,'nuLBootstrapCV'),ff(hi,'nuLBootstrapCV')];zero=[ff(lo,'nuLBoundaryFraction'),ff(hi,'nuLBoundaryFraction')];usable=[ff(lo,'bootstrapUsableFraction'),ff(hi,'bootstrapUsableFraction')]
        statuses=[lo.get('pooledStatus'),hi.get('pooledStatus')]
        if all(s=='PASS' for s in statuses) and csrel<=0.05 and max(cs_cvs)<=0.05 and min(usable)>=0.90:csgrade='PASS'
        elif all(s in ('PASS','REVIEW') for s in statuses) and csrel<=0.10 and max(cs_cvs)<=0.10 and min(usable)>=0.75:csgrade='REVIEW'
        else:csgrade='UNRESOLVED'
        if all(s=='PASS' for s in statuses) and nurel<=0.35 and max(nu_cvs)<=0.35 and max(zero)<=0.10 and min(usable)>=0.90:nugrade='PASS'
        elif all(s in ('PASS','REVIEW') for s in statuses) and nurel<=0.75 and max(nu_cvs)<=0.60 and max(zero)<=0.30 and min(usable)>=0.75:nugrade='REVIEW'
        else:nugrade='UNRESOLVED'
        cs_est=0.5*(cslo+cshi) if csgrade in ('PASS','REVIEW') else math.nan;nu_est=0.5*(nulo+nuhi) if nugrade in ('PASS','REVIEW') else math.nan
        qual.append({'fluid':fluid,'gamma':lo.get('gamma',''),'wavelengthCells':nx,'amplitudeLow':lo.get('amplitude',''),'amplitudeHigh':hi.get('amplitude',''),'csLow':cslo,'csHigh':cshi,'csRelativeDifference':csrel,'csMaxBootstrapCV':max(cs_cvs),'csQualification':csgrade,'csEstimate':cs_est,'nuLLow':nulo,'nuLHigh':nuhi,'nuLRelativeDifference':nurel,'nuLMaxBootstrapCV':max(nu_cvs),'nuLMaxBoundaryFraction':max(zero),'nuLQualification':nugrade,'nuLEstimate':nu_est,'bootstrapUsableFractionMin':min(usable)})
    write_csv(analysis/'Cstat_fluid_qualification_0493x13c.csv',qual)
    print('[0493x13c-Cstat-analysis] fluid  csGrade  nuLGrade  cs(.04/.08)  nuL(.04/.08)')
    for r in qual:
        print(f"  {r['fluid']:<4s}  {r['csQualification']:<10s} {r['nuLQualification']:<10s}  {ff(r,'csLow'):.6g}/{ff(r,'csHigh'):.6g}  {ff(r,'nuLLow'):.6g}/{ff(r,'nuLHigh'):.6g}")
    print(f'[0493x13c-Cstat-analysis] output={analysis}')

if __name__=='__main__':main()
