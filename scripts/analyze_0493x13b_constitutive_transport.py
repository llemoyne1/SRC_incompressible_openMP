#!/usr/bin/env python3
"""Analyze x13b transverse and longitudinal linear-response campaigns.
No pandas. Reuses the 0493w1 state parser and longitudinal regression where available.
"""
from __future__ import annotations
import argparse,csv,importlib.util,json,math,re
from pathlib import Path
import numpy as np

def load_w1(root:Path):
    path=root/'scripts'/'analyze_0493w1_src_fluid_calibrator.py'
    spec=importlib.util.spec_from_file_location('w1analysis',path)
    if not spec or not spec.loader: raise RuntimeError(f'cannot import {path}')
    mod=importlib.util.module_from_spec(spec); spec.loader.exec_module(mod); return mod

def read_csv(path):
    if not path.exists(): return []
    with path.open(newline='') as f: return list(csv.DictReader(f))
def ffloat(row,k,default=math.nan):
    try:return float(row[k])
    except:return default
def write_csv(path,rows):
    path.parent.mkdir(parents=True,exist_ok=True)
    if not rows:
        path.write_text(''); return
    fields=[]
    for r in rows:
        for k in r:
            if k not in fields: fields.append(k)
    with path.open('w',newline='') as f:
        w=csv.DictWriter(f,fieldnames=fields);w.writeheader();w.writerows(rows)

def linear_fit(x,y):
    x=np.asarray(x,float);y=np.asarray(y,float); mask=np.isfinite(x)&np.isfinite(y);x=x[mask];y=y[mask]
    if len(x)<3: raise ValueError('not enough points')
    A=np.column_stack((x,np.ones_like(x))); coef,*_=np.linalg.lstsq(A,y,rcond=None); slope,intercept=coef
    pred=A@coef; sse=float(np.sum((y-pred)**2)); sst=float(np.sum((y-y.mean())**2)); r2=1-sse/sst if sst>0 else 1.0
    return slope,intercept,r2,len(x)

def analyze_shear_run(w1,row,campaign):
    run=campaign/row['runDir']; dt=ffloat(row,'dt'); Ly=ffloat(row,'Ly'); mode=int(row['modeY']); k=2*math.pi*mode/Ly
    series=[]
    for step,path in w1.list_dumps(run):
        st=w1.read_state(path); mask=st['role']==1; y=st['y'][mask];m=st['mass'][mask];vx=st['vx'][mask]
        b=np.sin(k*y); den=np.sum(m*b*b); amp=float(np.sum(m*vx*b)/den)
        series.append((step,step*dt,amp,abs(amp)))
    if len(series)<8: raise ValueError('not enough shear dumps')
    t=np.array([q[1] for q in series]); a=np.array([q[3] for q in series]); ratio=a/max(a[0],1e-300); n=len(t)
    cand=[]
    for sf in (0.0,0.03,0.06,0.10):
        start=max(1,int(round(sf*(n-1))))
        for ef in (0.35,0.50,0.65,0.80,1.0):
            end=max(start+7,min(n,int(round(ef*n)))); mask=np.zeros(n,bool);mask[start:end]=True;mask&=a>0;mask&=ratio>0.04
            if np.count_nonzero(mask)<7: continue
            slope,inter,r2,pts=linear_fit(t[mask],np.log(a[mask])); nu=-slope/(k*k); span=float(np.ptp(np.log(a[mask])))
            if nu>0 and span>=0.20: cand.append((r2,min(span,3.0),pts,nu,start,end,span))
    if not cand:
        mask=(t>0)&(a>0);slope,inter,r2,pts=linear_fit(t[mask],np.log(a[mask]));nu=-slope/(k*k); chosen=(r2,math.nan,pts,nu,1,n,math.nan)
    else: chosen=max(cand,key=lambda q:(q[0],q[1],q[2]))
    r2,_,pts,nu,start,end,span=chosen
    status='PASS' if nu>0 and r2>=0.98 and (math.isnan(span) or span>=0.35) else ('REVIEW' if nu>0 and r2>=0.93 and (math.isnan(span) or span>=0.20) else 'INVALID')
    return {**row,'shearStatus':status,'nuT':nu,'shearFitR2':r2,'shearFitPoints':pts,'shearLogSpan':span,'shearInitialAmplitudeMeasured':a[0],'shearFinalRatio':ratio[-1],'k':k,'kLambda':k*ffloat(row,'lambdaPhysical')}

def analyze_sound_group(w1,row,campaign):
    group=campaign/row['runDir']; reps=sorted(p for p in group.glob('rep*') if p.is_dir()); k=2*math.pi*int(row['modeX'])/ffloat(row,'Lx')
    if not reps: raise ValueError(f'no sound reps in {group}')
    stacks=[]; stimulus=[]
    for rep in reps:
        q=w1._sound_series_from_case(rep,ffloat(row,'dt'),k); stacks.append(q)
        meta=rep/'init'/'sound_0493x13b.meta.json'
        if meta.exists():
            try:
                m=json.loads(meta.read_text())
                stimulus.append((float(m['realizedCosDensityAmplitude']),float(m['realizedSinDensityAmplitude']),str(m.get('method',''))))
            except Exception:
                pass
    steps=[x[0] for x in stacks[0]]
    if any([x[0] for x in q]!=steps for q in stacks[1:]): raise ValueError('replicate step mismatch')
    t=np.array([x[1] for x in stacks[0]],float); rho=np.mean(np.array([[x[2] for x in q] for q in stacks],complex),axis=0); vel=np.mean(np.array([[x[3] for x in q] for q in stacks],complex),axis=0)
    fit=w1.fit_longitudinal_hydrodynamics(t,rho,vel,k)
    cs=fit['soundSpeed']; nul=fit['nuL']; mom=fit['momentumRelativeRms']; cont=fit['continuityRelativeRms']; cond=fit['conditionNumber']; active=fit['activeConstraints']; pts=fit['fitPoints']
    passed=cs>0 and pts>=30 and mom<=0.35 and cont<=0.25 and cond<=1e8 and active=='none'
    review=cs>0 and pts>=20 and mom<=0.65 and cont<=0.45 and cond<=1e10 and 'cs2=0' not in active
    status='PASS' if passed else ('REVIEW' if review else 'INVALID')
    target=ffloat(row,'amplitude'); stim_cos=math.nan; stim_sin_rms=math.nan; stim_relerr=math.nan; stim_method=''
    if stimulus:
        stim_cos=float(np.mean([q[0] for q in stimulus])); stim_sin_rms=float(math.sqrt(np.mean(np.square([q[1] for q in stimulus]))));
        stim_relerr=(stim_cos-target)/target if target>0 else math.nan; stim_method=stimulus[0][2]
    return {**row,'soundStatus':status,'soundReplicatesActual':len(reps),'soundStimulusMetadataCount':len(stimulus),'soundStimulusMethod':stim_method,'soundStimulusRealizedCosMean':stim_cos,'soundStimulusSinRms':stim_sin_rms,'soundStimulusRelativeError':stim_relerr,'soundSpeed':cs,'nuL':nul,'nuLoverCsH':nul/(cs*ffloat(row,'cellSize')) if cs>0 else math.nan,'soundMomentumRelativeRms':mom,'soundContinuityRelativeRms':cont,'soundConditionNumber':cond,'soundActiveConstraints':active,'soundFitPoints':pts,'soundDampingRatio':fit['dampingRatio'],'k':k,'kLambda':k*ffloat(row,'lambdaPhysical')}

def group_summary(rows,kind):
    out=[]
    by={}
    for r in rows: by.setdefault((r['fluid'],r.get('wavelengthCells','')),[]).append(r)
    for (fluid,wc),grp in by.items():
        requested_low=min(grp,key=lambda r:ffloat(r,'amplitude'))
        if kind=='shear':
            valid=[r for r in grp if r.get('shearStatus') in ('PASS','REVIEW') and math.isfinite(ffloat(r,'nuT'))]
            vals=[ffloat(r,'nuT') for r in valid]; key='nuT'
        else:
            valid=[r for r in grp if r.get('soundStatus') in ('PASS','REVIEW') and math.isfinite(ffloat(r,'soundSpeed'))]
            vals=[ffloat(r,'soundSpeed') for r in valid]; key='soundSpeed'
        base=min(valid,key=lambda r:ffloat(r,'amplitude')) if valid else requested_low
        spread=(max(vals)-min(vals))/np.median(vals) if len(vals)>=2 and np.median(vals)!=0 else math.nan
        o={'fluid':fluid,'wavelengthCells':wc,'gamma':base['gamma'],'rotationAngleDeg':base['rotationAngleDeg'],'targetLambdaMeanOverCell':base['targetLambdaMeanOverCell'],'dt':base['dt'],'requestedLowestAmplitude':requested_low['amplitude'],'lowestUsableAmplitude':base['amplitude'],'amplitudeRelativeSpread':spread}
        if kind=='shear': o.update(nuTLowAmplitude=base.get('nuT',''),lowAmplitudeStatus=base.get('shearStatus',''),lowAmplitudeFitR2=base.get('shearFitR2',''),kLambda=base.get('kLambda',''))
        else:o.update(soundSpeedLowAmplitude=base.get('soundSpeed',''),nuLLowAmplitude=base.get('nuL',''),lowAmplitudeStatus=base.get('soundStatus',''),momentumRms=base.get('soundMomentumRelativeRms',''),continuityRms=base.get('soundContinuityRelativeRms',''),stimulusRealizedCosMean=base.get('soundStimulusRealizedCosMean',''),stimulusRelativeError=base.get('soundStimulusRelativeError',''),kLambda=base.get('kLambda',''))
        out.append(o)
    return out

def main():
    p=argparse.ArgumentParser(); p.add_argument('--campaign-root',type=Path,required=True); p.add_argument('--repo-root',type=Path,default=Path('.')); a=p.parse_args(); w1=load_w1(a.repo_root.resolve())
    analysis=a.campaign_root/'analysis';analysis.mkdir(parents=True,exist_ok=True)
    shear=[]; sm=a.campaign_root/'H_shear'/'manifest_0493x13b_H.csv'
    for row in read_csv(sm):
        try:shear.append(analyze_shear_run(w1,row,a.campaign_root/'H_shear'))
        except Exception as e:shear.append({**row,'shearStatus':'ERROR','error':str(e)})
    sound=[]; cm=a.campaign_root/'C_longitudinal'/'manifest_0493x13b_C.csv'
    for row in read_csv(cm):
        try:sound.append(analyze_sound_group(w1,row,a.campaign_root/'C_longitudinal'))
        except Exception as e:sound.append({**row,'soundStatus':'ERROR','error':str(e)})
    write_csv(analysis/'shear_runs_0493x13b.csv',shear);write_csv(analysis/'shear_summary_0493x13b.csv',group_summary(shear,'shear'))
    write_csv(analysis/'longitudinal_runs_0493x13b.csv',sound);write_csv(analysis/'longitudinal_summary_0493x13b.csv',group_summary(sound,'sound'))
    # Join lowest-amplitude, shortest-wavelength measurements for a constitutive map.
    s0={}; c0={}
    for r in shear:
        if r.get('shearStatus') not in ('PASS','REVIEW'): continue
        key=r['fluid']; q=(int(float(r['wavelengthCells'])),ffloat(r,'amplitude'))
        if key not in s0 or q<(int(float(s0[key]['wavelengthCells'])),ffloat(s0[key],'amplitude')): s0[key]=r
    for r in sound:
        if r.get('soundStatus') not in ('PASS','REVIEW'): continue
        key=r['fluid']; q=(int(float(r['wavelengthCells'])),ffloat(r,'amplitude'))
        if key not in c0 or q<(int(float(c0[key]['wavelengthCells'])),ffloat(c0[key],'amplitude')): c0[key]=r
    combined=[]
    for key in sorted(set(s0)|set(c0)):
        s=s0.get(key,{});c=c0.get(key,{});base=s or c;nu=ffloat(s,'nuT');cs=ffloat(c,'soundSpeed');nul=ffloat(c,'nuL');h=ffloat(base,'cellSize')
        combined.append({'fluid':key,'gamma':base.get('gamma',''),'rotationAngleDeg':base.get('rotationAngleDeg',''),'targetLambdaMeanOverCell':base.get('targetLambdaMeanOverCell',''),'dt':base.get('dt',''),'nuT':nu,'nuTStatus':s.get('shearStatus',''),'cs':cs,'soundStatus':c.get('soundStatus',''),'nuL':nul,'nuL_over_nuT':nul/nu if nu>0 and math.isfinite(nul) else math.nan,'H_h':cs*h/nu if nu>0 and cs>0 else math.nan,'RePerCell_Ma0p1':0.1*cs*h/nu if nu>0 and cs>0 else math.nan,'soundRequestedAmplitude':c.get('amplitude',''),'soundStimulusRealizedCosMean':c.get('soundStimulusRealizedCosMean',''),'soundStimulusRelativeError':c.get('soundStimulusRelativeError',''),'shear_kLambda':s.get('kLambda',''),'sound_kLambda':c.get('kLambda','')})
    write_csv(analysis/'constitutive_transport_map_0493x13b.csv',combined)
    print(f'[0493x13b-analysis] shear={len(shear)} sound={len(sound)} combined={len(combined)} output={analysis}')
if __name__=='__main__':main()
