#!/usr/bin/env python3
"""0493x13j autonomous transport-calibrator analysis.

Campaign-side only: no solver/source modification.  Reuses the qualified state
parser, transverse-shear observable, direct damped longitudinal estimator and
MSD observable already present in SRC_GPU-SURF.  No pandas; NumPy only.
"""
from __future__ import annotations
import argparse, csv, importlib.util, json, math, os
from pathlib import Path
from types import SimpleNamespace
import numpy as np

TAG = "0493x13j"


def load_module(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    if not spec or not spec.loader:
        raise RuntimeError(f"cannot import {path}")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def read_csv(path: Path):
    if not path.exists(): return []
    with path.open(newline="") as f: return list(csv.DictReader(f))


def write_csv(path: Path, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    if not rows:
        path.write_text("")
        return
    fields=[]
    for r in rows:
        for k in r:
            if k not in fields: fields.append(k)
    with path.open("w", newline="") as f:
        w=csv.DictWriter(f, fieldnames=fields, lineterminator="\n")
        w.writeheader(); w.writerows(rows)


def ff(r,k,d=math.nan):
    try: return float(r[k])
    except Exception: return d


def stats(vals):
    a=np.asarray([float(x) for x in vals if math.isfinite(float(x))],float)
    if len(a)==0: return dict(n=0,mean=math.nan,std=math.nan,sem=math.nan,cv=math.nan,p025=math.nan,p50=math.nan,p975=math.nan)
    mean=float(np.mean(a)); std=float(np.std(a,ddof=1)) if len(a)>1 else 0.0
    q=np.quantile(a,[.025,.5,.975])
    return dict(n=len(a),mean=mean,std=std,sem=std/math.sqrt(len(a)) if len(a) else math.nan,
                cv=std/abs(mean) if mean else math.nan,p025=float(q[0]),p50=float(q[1]),p975=float(q[2]))


def linear_fit(x,y):
    x=np.asarray(x,float); y=np.asarray(y,float); m=np.isfinite(x)&np.isfinite(y)
    x=x[m]; y=y[m]
    if len(x)<6: raise ValueError("not enough fit points")
    A=np.column_stack((x,np.ones_like(x))); c,*_=np.linalg.lstsq(A,y,rcond=None)
    pred=A@c; sse=float(np.sum((y-pred)**2)); sst=float(np.sum((y-y.mean())**2))
    return float(c[0]),float(c[1]),1-sse/sst if sst>0 else 1.0,len(x)


def fit_shear_series(t,a,k):
    t=np.asarray(t,float); a=np.asarray(a,float)
    ab=np.abs(a); ratio=ab/max(ab[0],1e-300); n=len(t); cand=[]
    for sf in (0.0,.03,.06,.10):
        start=max(1,int(round(sf*(n-1))))
        for ef in (.35,.50,.65,.80,1.0):
            end=max(start+7,min(n,int(round(ef*n))))
            m=np.zeros(n,bool); m[start:end]=True; m&=(ab>0)&(ratio>.04)
            if np.count_nonzero(m)<7: continue
            slope,inter,r2,pts=linear_fit(t[m],np.log(ab[m])); nu=-slope/(k*k); span=float(np.ptp(np.log(ab[m])))
            if nu>0 and span>=.20: cand.append((r2,min(span,3.0),pts,nu,start,end,span))
    if not cand:
        m=(t>0)&(ab>0); slope,inter,r2,pts=linear_fit(t[m],np.log(ab[m])); nu=-slope/(k*k)
        chosen=(r2,math.nan,pts,nu,1,n,math.nan)
    else: chosen=max(cand,key=lambda q:(q[0],q[1],q[2]))
    r2,_,pts,nu,start,end,span=chosen
    status='PASS' if nu>0 and r2>=.98 and (math.isnan(span) or span>=.35) else ('REVIEW' if nu>0 and r2>=.93 and (math.isnan(span) or span>=.20) else 'INVALID')
    return dict(status=status,nuT=nu,r2=r2,points=pts,logSpan=span,start=start,end=end,initialAmplitude=float(a[0]),finalRatio=float(ratio[-1]))


def shear_amplitude_series(w1, case:Path, dt:float, Ly:float, mode:int):
    k=2*math.pi*mode/Ly; out=[]
    for step,path in w1.list_dumps(case):
        st=w1.read_state(path); msk=st['role']==1; y=st['y'][msk]; mass=st['mass'][msk]; vx=st['vx'][msk]
        b=np.sin(k*y); den=np.sum(mass*b*b); amp=float(np.sum(mass*vx*b)/den)
        out.append((int(step),float(step)*dt,amp))
    if len(out)<8: raise ValueError(f"not enough shear dumps in {case}")
    return out,k


def bootstrap_shear(rng, stacks, t, k, nboot):
    vals=[]; statuses=[]
    stack=np.asarray(stacks,float); n=stack.shape[0]
    for _ in range(nboot):
        idx=rng.integers(0,n,size=n)
        try:
            f=fit_shear_series(t,np.mean(stack[idx],axis=0),k); vals.append(f['nuT']); statuses.append(f['status'])
        except Exception: pass
    s=stats(vals); s['completed']=len(vals); s['passFraction']=statuses.count('PASS')/len(statuses) if statuses else 0.0
    return s


def analyze_shear(w1, root:Path, bootstrap:int, rng):
    manifest=read_csv(root/'manifest_shear_0493x13j.csv'); runs=[]; summaries=[]
    groups={}
    for row in manifest:
        case=root/row['runDir']; marker=case/'RUN_COMPLETE_0493x13j_shear'
        if not marker.exists():
            runs.append({**row,'status':'MISSING'}); continue
        try:
            ser,k=shear_amplitude_series(w1,case,ff(row,'dt'),ff(row,'Ly'),int(ff(row,'modeY')))
            t=np.asarray([q[1] for q in ser]); a=np.asarray([q[2] for q in ser]); fit=fit_shear_series(t,a,k)
            q={**row,**fit,'k':k}; runs.append(q)
            groups.setdefault(int(ff(row,'Ny')),[]).append((row,t,a,k,fit))
        except Exception as e: runs.append({**row,'status':'ERROR','error':str(e)})
    write_csv(root.parent/'analysis'/'shear_runs_0493x13j.csv',runs)
    for ny,grp in sorted(groups.items()):
        t0=grp[0][1]; good=[]
        for row,t,a,k,fit in grp:
            if len(t)==len(t0) and np.allclose(t,t0,rtol=0,atol=1e-12) and fit['status'] in ('PASS','REVIEW'): good.append((row,a,k,fit))
        if not good: continue
        stack=np.vstack([q[1] for q in good]); k=good[0][2]; ens=fit_shear_series(t0,np.mean(stack,axis=0),k); b=bootstrap_shear(rng,stack,t0,k,bootstrap)
        si=stats([q[3]['nuT'] for q in good]); passfrac=sum(q[3]['status']=='PASS' for q in good)/len(grp)
        grade='PASS' if len(good)>=5 and passfrac>=.75 and ens['status']=='PASS' and si['cv']<=.15 else ('REVIEW' if len(good)>=4 and ens['status'] in ('PASS','REVIEW') and si['cv']<=.25 else 'UNRESOLVED')
        base=good[0][0]
        summaries.append({'Ny':ny,'wavelengthCells':ny/int(ff(base,'modeY',1)),'expectedRuns':len(grp),'validRuns':len(good),'passFraction':passfrac,
            'nuTEnsemble':ens['nuT'],'ensembleR2':ens['r2'],'ensembleStatus':ens['status'],
            'nuTIndividualMean':si['mean'],'nuTIndividualStd':si['std'],'nuTIndividualCV':si['cv'],
            'bootstrapCompleted':b['completed'],'nuTBootstrapMean':b['mean'],'nuTBootstrapStd':b['std'],'nuTBootstrapP025':b['p025'],'nuTBootstrapMedian':b['p50'],'nuTBootstrapP975':b['p975'],
            'grade':grade,'dt':ff(base,'dt'),'cellSize':ff(base,'cellSize'),'kBT':ff(base,'kBT'),'gamma':ff(base,'gamma'),'amplitude':ff(base,'amplitude')})
    write_csv(root.parent/'analysis'/'shear_summary_0493x13j.csv',summaries)
    return summaries


def analyze_sound(w1,damp,root:Path,bootstrap:int,rng,cs_min:float,cs_max:float):
    manifest=read_csv(root/'manifest_sound_0493x13j.csv'); groups=[]; individual=[]
    for row in manifest:
        reps=sorted(p for p in (root/row['runDir']).glob('rep*') if p.is_dir() and (p/'RUN_COMPLETE_0493x13j_sound').exists())
        if not reps:
            groups.append({**row,'status':'MISSING'}); continue
        try:
            k=2*math.pi*int(ff(row,'modeX'))/ff(row,'Lx'); t0=None; rho=[]
            for rep in reps:
                q=w1._sound_series_from_case(rep,ff(row,'dt'),k); t=np.asarray([z[1] for z in q],float); rr=np.asarray([z[2] for z in q],complex)
                if t0 is None: t0=t
                elif len(t)!=len(t0) or np.max(np.abs(t-t0))>1e-12: raise ValueError('replicate time mismatch')
                rho.append(rr)
            stack=np.asarray(rho); pooled,center=damp.direct_fit_global(w1,t0,np.mean(stack,axis=0),k,cs_min,cs_max)
            for i,rep in enumerate(reps):
                try: f,_=damp.direct_fit_local(w1,t0,stack[i],k,cs_min,cs_max,center,allow_fallback=True); individual.append({**row,'replicate':rep.name,**f})
                except Exception as e: individual.append({**row,'replicate':rep.name,'status':'ERROR','error':str(e)})
            csb=[]; nub=[]; status=[]
            for _ in range(bootstrap):
                idx=rng.integers(0,len(stack),size=len(stack))
                try:
                    f,_=damp.direct_fit_local(w1,t0,np.mean(stack[idx],axis=0),k,cs_min,cs_max,center,allow_fallback=True)
                    csb.append(f['cs']); nub.append(f['nuL']); status.append(f['status'])
                except Exception: pass
            cs=stats(csb); nu=stats(nub); ip=[r for r in individual if r.get('status') in ('PASS','REVIEW') and r.get('replicate','') in {p.name for p in reps}]
            passfrac=sum(r.get('status')=='PASS' for r in ip)/len(reps)
            grade='PASS' if len(reps)>=5 and pooled['status']=='PASS' and passfrac>=.70 and cs['cv']<=.03 else ('REVIEW' if len(reps)>=4 and pooled['status'] in ('PASS','REVIEW') and cs['cv']<=.08 else 'UNRESOLVED')
            groups.append({**row,'status':pooled['status'],'grade':grade,'replicatesCompleted':len(reps),'individualPassFraction':passfrac,
                'cs':pooled['cs'],'nuL':pooled['nuL'],'fitR2':pooled['r2'],'fitCycles':pooled['cycles'],
                'csBootstrapMean':cs['mean'],'csBootstrapStd':cs['std'],'csBootstrapP025':cs['p025'],'csBootstrapP975':cs['p975'],
                'nuLBootstrapMean':nu['mean'],'nuLBootstrapStd':nu['std'],'nuLBootstrapP025':nu['p025'],'nuLBootstrapP975':nu['p975'],'bootstrapCompleted':min(len(csb),len(nub))})
        except Exception as e: groups.append({**row,'status':'ERROR','grade':'UNRESOLVED','error':str(e)})
    write_csv(root.parent/'analysis'/'sound_runs_0493x13j.csv',individual); write_csv(root.parent/'analysis'/'sound_summary_0493x13j.csv',groups)
    return groups


def analyze_msd(w1, root:Path, bootstrap:int,rng):
    manifest=read_csv(root/'manifest_msd_0493x13j.csv'); runs=[]; curves=[]; t0=None
    for row in manifest:
        case=root/row['runDir']; marker=case/'RUN_COMPLETE_0493x13j_msd'
        if not marker.exists(): runs.append({**row,'status':'MISSING'}); continue
        try:
            ns=SimpleNamespace(root=case.parent,dt=ff(row,'dt'),msd_sample_particles=int(ff(row,'sampleParticles')),msd_Lx=ff(row,'Lx'),msd_Ly=ff(row,'Ly'))
            # w1 expects root/msd.  Present this case through a temporary namespace path convention:
            # each runDir is seed.../msd, hence case.parent is the 0493w1-style root.
            series,res=w1.analyze_msd(ns); status='PASS' if res['selfDiffusion']>0 and res['fitR2']>=.995 else ('REVIEW' if res['selfDiffusion']>0 and res['fitR2']>=.98 else 'INVALID')
            runs.append({**row,'status':status,**res})
            t=np.asarray([ff(z,'time') for z in series]); y=np.asarray([ff(z,'msd') for z in series])
            if t0 is None: t0=t
            if len(t)==len(t0) and np.allclose(t,t0,rtol=0,atol=1e-12): curves.append(y)
        except Exception as e: runs.append({**row,'status':'ERROR','error':str(e)})
    write_csv(root.parent/'analysis'/'msd_runs_0493x13j.csv',runs)
    good=[r for r in runs if r.get('status') in ('PASS','REVIEW') and ff(r,'selfDiffusion')>0]; si=stats([ff(r,'selfDiffusion') for r in good])
    # Ensemble mean curve: same candidate late-time windows as the 0493w1 MSD estimator.
    def fit_curve(t,y):
        cand=[]
        for frac in (.20,.30,.40,.50):
            m=t>=frac*t[-1]
            if np.count_nonzero(m)<6: continue
            slope,inter,r2,pts=linear_fit(t[m],y[m])
            if slope>0: cand.append((r2,-frac,slope,pts,frac))
        if not cand:
            slope,inter,r2,pts=linear_fit(t[1:],y[1:]); return dict(D=slope/4.0,r2=r2,points=pts,startFraction=0.0)
        r2,negf,slope,pts,frac=max(cand,key=lambda q:(q[0],q[1])); return dict(D=slope/4.0,r2=r2,points=pts,startFraction=frac)
    ens=fit_curve(t0,np.mean(np.vstack(curves),axis=0)) if curves else dict(D=math.nan,r2=math.nan,points=0,startFraction=math.nan)
    vals=[]
    if curves:
        arr=np.asarray(curves); n=len(arr)
        for _ in range(bootstrap):
            try:
                idx=rng.integers(0,n,size=n); vals.append(fit_curve(t0,np.mean(arr[idx],axis=0))['D'])
            except Exception: pass
    bs=stats(vals); passfrac=sum(r.get('status')=='PASS' for r in runs)/max(1,len(runs))
    grade='PASS' if len(good)>=5 and passfrac>=.75 and ens['D']>0 and ens['r2']>=.995 and si['cv']<=.15 else ('REVIEW' if len(good)>=4 and ens['D']>0 and ens['r2']>=.98 and si['cv']<=.25 else 'UNRESOLVED')
    summary={'expectedRuns':len(runs),'validRuns':len(good),'passFraction':passfrac,'DselfEnsemble':ens['D'],'ensembleR2':ens['r2'],'ensembleFitPoints':ens['points'],
             'DselfIndividualMean':si['mean'],'DselfIndividualStd':si['std'],'DselfIndividualCV':si['cv'],
             'bootstrapCompleted':len(vals),'DselfBootstrapMean':bs['mean'],'DselfBootstrapStd':bs['std'],'DselfBootstrapP025':bs['p025'],'DselfBootstrapMedian':bs['p50'],'DselfBootstrapP975':bs['p975'],'grade':grade}
    write_csv(root.parent/'analysis'/'msd_summary_0493x13j.csv',[summary]); return summary


def finite(x): return isinstance(x,(int,float)) and math.isfinite(x)
def fmt(x,sig=6):
    if not finite(x): return 'N/A'
    if x==0: return '0'
    return f"{x:.{sig}g}"

def pct(x): return 'N/A' if not finite(x) else f"{100*x:.2f}%"


def main():
    p=argparse.ArgumentParser(); p.add_argument('--campaign-root',type=Path,required=True); p.add_argument('--repo-root',type=Path,default=Path('.'))
    p.add_argument('--bootstrap',type=int,default=500); p.add_argument('--self-test',action='store_true'); a=p.parse_args()
    repo=a.repo_root.resolve(); w1=load_module(repo/'scripts'/'analyze_0493w1_src_fluid_calibrator.py','w1x13j'); damp=load_module(repo/'scripts'/'analyze_0493x13h_A_Cdamp_L072.py','dampx13j')
    if a.self_test:
        damp.self_test(w1,benchmark=False); print(f'[{TAG}-analysis] PASS self-test'); return
    root=a.campaign_root.resolve(); analysis=root/'analysis'; analysis.mkdir(parents=True,exist_ok=True)
    cfg=json.loads((root/'manifest_0493x13j.json').read_text()); rng=np.random.default_rng(int(cfg['analysisBootstrapSeed']))
    shear=analyze_shear(w1,root/'shear',a.bootstrap,rng)
    sound=[]
    if (root/'sound'/'manifest_sound_0493x13j.csv').exists():
        sound=analyze_sound(w1,damp,root/'sound',a.bootstrap,rng,float(cfg['soundCsMin']),float(cfg['soundCsMax']))
    msd=analyze_msd(w1,root/'msd',a.bootstrap,rng) if (root/'msd'/'manifest_msd_0493x13j.csv').exists() else {}
    main_ny=int(cfg['shearNyMain']); local_ny=int(cfg['shearNyLocal']); sm={int(ff(r,'Ny')):r for r in shear}
    s=sm.get(main_ny,{}); sl=sm.get(local_ny,{})
    nu=ff(s,'nuTEnsemble'); nu_lo=ff(s,'nuTBootstrapP025'); nu_hi=ff(s,'nuTBootstrapP975')
    locality=abs(nu-ff(sl,'nuTEnsemble'))/(.5*(nu+ff(sl,'nuTEnsemble'))) if nu>0 and ff(sl,'nuTEnsemble')>0 else math.nan
    locality_grade='PASS' if finite(locality) and locality<=.05 else ('REVIEW' if finite(locality) and locality<=.15 else 'UNRESOLVED')
    snd=sound[0] if sound else {}; cs=ff(snd,'cs'); nul=ff(snd,'nuL'); D=ff(msd,'DselfEnsemble'); h=float(cfg['cellSize'])
    Hh=cs*h/nu if cs>0 and nu>0 else math.nan; Sc=nu/D if nu>0 and D>0 else math.nan
    U=float(cfg['characteristicU']); L=float(cfg['characteristicL'])
    Re=U*L/nu if U>0 and L>0 and nu>0 else math.nan; Ma=U/cs if U>0 and cs>0 else math.nan; Pe=U*L/D if U>0 and L>0 and D>0 else math.nan
    essential=[s.get('grade','UNRESOLVED'),locality_grade]
    if cfg['calibrationPath']=='src': essential += [snd.get('grade','UNRESOLVED'),msd.get('grade','UNRESOLVED')]
    else: essential += [msd.get('grade','UNRESOLVED')]
    overall='PASS' if all(x=='PASS' for x in essential) else ('REVIEW' if all(x in ('PASS','REVIEW') for x in essential) else 'UNRESOLVED')
    summary={'schema':'0493x13j-v1','overallStatus':overall,'calibrationPath':cfg['calibrationPath'],'physics':{k:cfg[k] for k in ('gamma','alphaDeg','lambdaOverH','dt','kBT','mass','cellSize','thermostatEnable','thermostatMode','thermostatEvery')},
      'pathEffective':{'nuT':nu,'nuT95CI':[nu_lo,nu_hi],'nuTGrade':s.get('grade',''),'localityRelativeDifference':locality,'localityGrade':locality_grade,'Dself':D,'Dself95CI':[ff(msd,'DselfBootstrapP025'),ff(msd,'DselfBootstrapP975')],'diffusionGrade':msd.get('grade','')},
      'baseSrcAcoustics':{'status':snd.get('grade','NOT_RUN') if sound else 'NOT_RUN','cs':cs,'cs95CI':[ff(snd,'csBootstrapP025'),ff(snd,'csBootstrapP975')],'nuL':nul,'nuL95CI':[ff(snd,'nuLBootstrapP025'),ff(snd,'nuLBootstrapP975')]},
      'derived':{'HhUsingBaseSrcCs':Hh,'ScPathEffective':Sc,'Re':Re,'MaUsingBaseSrcCs':Ma,'Pe':Pe}}
    if cfg['calibrationPath']!='src': summary['pathEffective']['soundSpeedStatus']='NOT_APPLICABLE_Q6'; summary['pathEffective']['nuLStatus']='NOT_APPLICABLE_Q6'
    (analysis/'summary_0493x13j.json').write_text(json.dumps(summary,indent=2,sort_keys=True)+"\n")
    flat={'overallStatus':overall,'calibrationPath':cfg['calibrationPath'],'gamma':cfg['gamma'],'alphaDeg':cfg['alphaDeg'],'lambdaOverH':cfg['lambdaOverH'],'dt':cfg['dt'],'kBT':cfg['kBT'],'cellSize':cfg['cellSize'],
          'nuT':nu,'nuT95Low':nu_lo,'nuT95High':nu_hi,'nuTGrade':s.get('grade',''),'localityRelativeDifference':locality,'localityGrade':locality_grade,
          'baseSrcCs':cs,'baseSrcNuL':nul,'Dself':D,'HhUsingBaseSrcCs':Hh,'ScPathEffective':Sc,'Re':Re,'MaUsingBaseSrcCs':Ma,'Pe':Pe}
    write_csv(analysis/'summary_0493x13j.csv',[flat])
    report=[]; add=report.append
    add('# SRC transport calibration — 0493x13j')
    add(''); add(f'**Overall: {overall}**  '); add(f"Path calibrated: `{cfg['calibrationPath']}`  ")
    add(f"Binary: `{cfg.get('binary','')}`  "); add(f"Git HEAD: `{cfg.get('gitHead','UNKNOWN')}`")
    add(''); add('## Fluid point')
    add(''); add('| parameter | value |'); add('|---|---:|')
    for label,key in [('gamma','gamma'),('alpha [deg]','alphaDeg'),('lambda/h','lambdaOverH'),('h','cellSize'),('dt','dt'),('kBT','kBT'),('mass','mass')]: add(f"| {label} | {fmt(float(cfg[key]))} |")
    add(''); add('## Recommended transport values')
    add(''); add('| quantity | result | 95% bootstrap | status |'); add('|---|---:|---:|---|')
    add(f"| path-effective nu_T | {fmt(nu)} | [{fmt(nu_lo)}, {fmt(nu_hi)}] | {s.get('grade','N/A')} |")
    add(f"| wavelength locality 128/256 | {pct(locality)} | — | {locality_grade} |")
    if sound:
        add(f"| base-SRC c_s | {fmt(cs)} | [{fmt(ff(snd,'csBootstrapP025'))}, {fmt(ff(snd,'csBootstrapP975'))}] | {snd.get('grade','N/A')} |")
        add(f"| base-SRC nu_L | {fmt(nul)} | [{fmt(ff(snd,'nuLBootstrapP025'))}, {fmt(ff(snd,'nuLBootstrapP975'))}] | {snd.get('grade','N/A')} |")
    else:
        add('| base-SRC acoustics | N/A | — | NOT_RUN |')
    add(f"| path-effective D_self | {fmt(D)} | [{fmt(ff(msd,'DselfBootstrapP025'))}, {fmt(ff(msd,'DselfBootstrapP975'))}] | {msd.get('grade','N/A')} |")
    add(''); add('## Derived quantities')
    add(''); add('| quantity | value |'); add('|---|---:|'); add(f'| H_h = c_s h / nu_T | {fmt(Hh)} |'); add(f'| Sc = nu_T / D_self | {fmt(Sc)} |')
    if finite(Re): add(f'| Re(U,L) | {fmt(Re)} |')
    if finite(Ma): add(f'| Ma(U) | {fmt(Ma)} |')
    if finite(Pe): add(f'| Pe(U,L) | {fmt(Pe)} |')
    add(''); add('## Interpretation')
    if overall=='PASS': add('The requested transport calibration is qualified at the configured statistical/locality thresholds. The values above are the recommended design values for this binary and path.')
    elif overall=='REVIEW': add('The calibration is usable, but at least one statistical or wavelength-locality check is in REVIEW. Use the reported uncertainty when propagating Reynolds/transport quantities.')
    else: add('At least one essential observable is unresolved. Do not use this calibration as a precision design value without inspecting the detailed CSV files.')
    if cfg['calibrationPath']!='src':
        add(''); add('**Projected-path acoustics:** the standard longitudinal acoustic estimator is not applied to the Q6/Q6-G-F path. `c_s` and `nu_L` shown here are measured on the underlying SRC fluid; path-effective sound is reported as `NOT_APPLICABLE_Q6`.')
    add(''); add('## Reproducibility / audit')
    add(''); add('The campaign records the Git HEAD, binary SHA-256, generated parameter files, per-run environment files, seed list and machine-readable JSON/CSV summaries. Completed runs are skipped only when their stored signature matches the current state, parameters, binary and selected Q6 environment.')
    add(''); add('Detailed files: `shear_runs_0493x13j.csv`, `shear_summary_0493x13j.csv`, `sound_summary_0493x13j.csv`, `msd_summary_0493x13j.csv`.')
    (analysis/'README_RESULTS_0493x13j.md').write_text('\n'.join(report)+'\n')
    print(f'[{TAG}-analysis] overall={overall} nuT={fmt(nu)} locality={pct(locality)} cs={fmt(cs)} Dself={fmt(D)}')
    print(f'[{TAG}-analysis] report={analysis/"README_RESULTS_0493x13j.md"}')

if __name__=='__main__': main()
