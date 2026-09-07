#!/usr/bin/env python3
"""0493x14ak — Taylor-Culick analysis from liquid-only filtered mass recordings.

No pandas/scipy.  The recorder is expected to be filtered on LIQUID_TYPE.  The
left/right edges are extracted from the x-integrated liquid mass at q35/q50/q65
of the nominal flat-sheet line mass.  The primary reference is the current
Taylor-Culick theory; the historical qualified x13h gain G_TC=0.79457172 is
reported explicitly as a contextual (not constitutively matched) benchmark.
"""
from __future__ import annotations
import argparse,csv,json,math,statistics,sys
from array import array
from pathlib import Path

def read_csv(p):
    if not p.exists(): return []
    with p.open(newline='') as f:return list(csv.DictReader(f))

def f32(path,n):
    a=array('f')
    with path.open('rb') as f:a.fromfile(f,n)
    if len(a)!=n: raise RuntimeError(f'{path}: expected {n} f32, got {len(a)}')
    if sys.byteorder=='big':a.byteswap()
    return a

def locate_frames(run_root):
    timelines=sorted((run_root/'output'/'recordings').glob('*/timeline.csv'))
    if not timelines: raise RuntimeError(f'{run_root}: no recording timeline.csv')
    by={}
    for tl in timelines:
        for r in read_csv(tl):
            if r.get('field') not in ('rho','mass'): continue
            s=int(r['step']); by[s]=(float(r['time']),int(r['nx']),int(r['ny']),tl.parent/r['file'])
    if not by: raise RuntimeError('no mass/rho frames in recorder')
    return [(s,)+by[s] for s in sorted(by)]

def smooth3(v):
    if len(v)<3:return list(v)
    out=[0.0]*len(v)
    for i,x in enumerate(v):
        s=2*x; w=2
        if i>0:s+=v[i-1];w+=1
        if i+1<len(v):s+=v[i+1];w+=1
        out[i]=s/w
    return out

def interp(x0,y0,x1,y1,target):
    d=y1-y0
    if abs(d)<1e-30:return 0.5*(x0+x1)
    q=min(1.0,max(0.0,(target-y0)/d)); return x0+q*(x1-x0)

def edges(profile,dx,split_x,threshold):
    split=min(len(profile)-2,max(1,int(split_x/dx)))
    left=[];right=[]
    for i in range(len(profile)-1):
        a,b=profile[i],profile[i+1];x0=(i+0.5)*dx;x1=(i+1.5)*dx
        if a<threshold<=b and i<split:left.append(interp(x0,a,x1,b,threshold))
        if a>=threshold>b and i>=split-1:right.append(interp(x0,a,x1,b,threshold))
    if not left or not right: raise RuntimeError(f'cannot locate both edges threshold={threshold:g} left={len(left)} right={len(right)}')
    return min(left),max(right)

def line_fit(xs,ys):
    if len(xs)<3:return None
    xm=statistics.fmean(xs);ym=statistics.fmean(ys);sxx=sum((x-xm)**2 for x in xs)
    if sxx<=0:return None
    sl=sum((x-xm)*(y-ym) for x,y in zip(xs,ys))/sxx;it=ym-sl*xm
    pred=[it+sl*x for x in xs];sse=sum((y-p)**2 for y,p in zip(ys,pred));sst=sum((y-ym)**2 for y in ys)
    return it,sl,1-sse/sst if sst>0 else math.nan,math.sqrt(sse/len(xs))

def fit_window(series,key,tau,a,b,utc):
    rr=[r for r in series if a*tau<=r['time']<=b*tau]
    if len(rr)<5:return None
    t=[r['time'] for r in rr];xl=[r[f'xLeft_{key}'] for r in rr];xr=[r[f'xRight_{key}'] for r in rr];hs=[r[f'halfSpan_{key}'] for r in rr]
    fl,fr,fh=line_fit(t,xl),line_fit(t,xr),line_fit(t,hs)
    if not(fl and fr and fh):return None
    ul=fl[1];ur=-fr[1];uh=-fh[1];um=.5*(ul+ur)
    return {'n':len(rr),'tMin':rr[0]['time'],'tMax':rr[-1]['time'],'uLeft':ul,'uRight':ur,'uMean':um,'uHalfSpan':uh,
            'Gtc':um/utc,'GtcHalf':uh/utc,'symmetryRelative':(ul-ur)/um if abs(um)>1e-30 else math.nan,
            'r2Left':fl[2],'r2Right':fr[2],'r2Half':fh[2]}

def fv(r,k,default=math.nan):
    try:
        v=float(r[k]);return v if math.isfinite(v) else default
    except:return default

def finite_mean(v):
    z=[x for x in v if math.isfinite(x)];return statistics.fmean(z) if z else math.nan

def finite_max(v):
    z=[x for x in v if math.isfinite(x)];return max(z) if z else math.nan

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--run-root',type=Path,required=True)
    ap.add_argument('--Lx',type=float,default=3.5);ap.add_argument('--Ly',type=float,default=1.0)
    ap.add_argument('--nx',type=int,default=896);ap.add_argument('--ny',type=int,default=256)
    ap.add_argument('--gamma',type=float,default=20);ap.add_argument('--liquid-mass',type=float,default=1.0);ap.add_argument('--gas-mass',type=float,default=0.1)
    ap.add_argument('--liquid-type',type=int,default=1);ap.add_argument('--sigma',type=float,default=10000)
    ap.add_argument('--thickness-cells',type=float,default=64);ap.add_argument('--sheet-length-cells',type=float,default=768)
    ap.add_argument('--center-x',type=float,default=1.75);ap.add_argument('--center-y',type=float,default=.5)
    ap.add_argument('--dt',type=float,default=.002);ap.add_argument('--fit-tau-min',type=float,default=.5);ap.add_argument('--fit-tau-max',type=float,default=1.75)
    ap.add_argument('--historical-g-tc',type=float,default=.79457172)
    a=ap.parse_args()
    h=a.Lx/a.nx
    if abs(h-a.Ly/a.ny)>1e-12*max(1.0,abs(h)):raise SystemExit('[0493x14ak-analysis] square cells required')
    H=a.thickness_cells*h;rho=a.gamma*a.liquid_mass/h**2;rhoG=a.gamma*a.gas_mass/h**2;utc=math.sqrt(2*a.sigma/(rho*H));tau=H/utc
    histG=a.historical_g_tc;histCurrentU=histG*utc;histX13hUth=.390625;histX13hU=histG*histX13hUth
    thresholds=(.35,.50,.65);series=[]
    frames=locate_frames(a.run_root)
    for step,time,nxR,nyR,path in frames:
        d=f32(path,nxR*nyR);dxR=a.Lx/nxR;dyR=a.Ly/nyR
        line=[0.0]*nxR;M=sx=sy=0.0
        for iy in range(nyR):
            off=iy*nxR;yc=(iy+.5)*dyR
            for ix in range(nxR):
                m=float(d[off+ix]);line[ix]+=m;M+=m;sx+=m*(ix+.5)*dxR;sy+=m*yc
        if M<=0:raise RuntimeError(f'{path}: zero recorded liquid mass')
        xcm=sx/M;ycm=sy/M;prof=smooth3(line)
        # Recorder bin spans NX/nxR simulation columns. Flat-sheet nominal mass per recorder x-bin:
        nominal=a.gamma*a.liquid_mass*a.thickness_cells*(a.nx/nxR)
        row={'step':step,'time':time,'recNx':nxR,'recNy':nyR,'mass':M,'xCM':xcm,'yCM':ycm,'nominalLineMass':nominal}
        for q in thresholds:
            k=f'q{int(round(100*q)):02d}';xl,xr=edges(prof,dxR,xcm,q*nominal)
            row[f'xLeft_{k}']=xl;row[f'xRight_{k}']=xr;row[f'halfSpan_{k}']=.5*(xr-xl);row[f'edgeCenter_{k}']=.5*(xl+xr)
        series.append(row)
    if len(series)<10:raise SystemExit(f'[0493x14ak-analysis] too few recorder frames: {len(series)}')
    for q in thresholds:
        k=f'q{int(round(100*q)):02d}';hs0=series[0][f'halfSpan_{k}']
        for r in series:r[f'retraction_{k}']=hs0-r[f'halfSpan_{k}'];r[f'retractionOverH_{k}']=r[f'retraction_{k}']/H
    windows=[('early',.25,1.25),('main',a.fit_tau_min,a.fit_tau_max),('late',1.0,2.0)]
    fits={}
    for q in thresholds:
        k=f'q{int(round(100*q)):02d}'
        for name,lo,hi in windows:fits[(k,name)]=fit_window(series,k,tau,lo,hi,utc)
    main=fits[('q50','main')]
    if main is None:raise SystemExit('[0493x14ak-analysis] main q50 fit unavailable')

    out=a.run_root/'analysis_0493x14ak';out.mkdir(parents=True,exist_ok=True)
    fields=['step','time','recNx','recNy','mass','xCM','yCM','nominalLineMass']
    for q in thresholds:
        k=f'q{int(round(100*q)):02d}';fields += [f'xLeft_{k}',f'xRight_{k}',f'halfSpan_{k}',f'edgeCenter_{k}',f'retraction_{k}',f'retractionOverH_{k}']
    with (out/'taylor_culick_two_phase_trace.csv').open('w',newline='') as f:
        w=csv.DictWriter(f,fieldnames=fields);w.writeheader();w.writerows([{k:r.get(k,'') for k in fields} for r in series])

    species=read_csv(a.run_root/'output'/'species_runtime_0493x14ak.csv')
    kL=[fv(r,'kBT') for r in species if str(r.get('type',''))==str(a.liquid_type)]
    kG=[fv(r,'kBT') for r in species if str(r.get('type',''))!=str(a.liquid_type)]
    limiter=read_csv(a.run_root/'output'/'cuda_surface_tension_limiter_0493x9r.csv')
    clip=[fv(r,'clipFraction') for r in limiter]
    q6=read_csv(a.run_root/'output'/'cuda_species_q6_independent_masked_0493w5.csv')
    q6bad=sum(1 for r in q6 if fv(r,'converged',1.0)<.5)
    q6res=finite_max([fv(r,'residualRel') for r in q6])
    masses=[r['mass'] for r in series];dxcm=series[-1]['xCM']-series[0]['xCM'];dycm=series[-1]['yCM']-series[0]['yCM']

    comparison={
      'GtcMeasured':main['Gtc'],'UTcCurrentTheory':utc,'Umeasured':main['uMean'],'historicalQualifiedGainX13h':histG,
      'GtcOverHistoricalGain':main['Gtc']/histG,'relativeToHistoricalGainPercent':100*(main['Gtc']/histG-1),
      'historicalGainAppliedToCurrentTheorySpeed':histCurrentU,'historicalX13hTheorySpeed':histX13hUth,'historicalX13hMeasuredSpeed':histX13hU,
      'comparisonStatus':'CONTEXT_ONLY_NOT_CONSTITUTIVELY_MATCHED: historical x13h uses gamma=8,kBT=0.125,dt=0.0063471328149; current x14 uses gamma=20,kBT_L=0.02,kBT_G=0.08,dt=0.002'
    }
    summary={
      'benchmark':'0493x14ak_two_phase_taylor_culick','rhoLiquid':rho,'rhoGas':rhoG,'rhoGasOverLiquid':rhoG/rho,'H':H,'sigma':a.sigma,'UTcTheory':utc,'tauTc':tau,
      'fitWindowTau':[a.fit_tau_min,a.fit_tau_max],'mainQ50':main,'historicalComparison':comparison,'frames':len(series),
      'liquidMassRelativeSpan':(max(masses)-min(masses))/statistics.fmean(masses),'liquidCOMDrift':[dxcm,dycm],
      'liquidKBTMean':finite_mean(kL),'gasKBTMean':finite_mean(kG),'limiterClipMax':finite_max(clip),'q6NonConvergedSamples':q6bad,'q6ResidualRelMax':q6res
    }
    (out/'taylor_culick_two_phase_summary.json').write_text(json.dumps(summary,indent=2)+'\n')
    lines=[];add=lines.append
    add('0493x14ak — TWO-PHASE TAYLOR-CULICK / x14ad+x14ai-fix1');add('='*67)
    add(f'grid={a.nx}x{a.ny} h={h:.12g} gamma={a.gamma:g} rhoL={rho:.12g} rhoG={rhoG:.12g} rhoG/rhoL={rhoG/rho:.12g}')
    add(f'H={H:.12g} H/h={a.thickness_cells:g} sigma={a.sigma:.12g} dt={a.dt:.12g}')
    add(f'U_TC_current_theory={utc:.12g} tau_TC={tau:.12g} stepsPerTau={tau/a.dt:.12g}')
    add('');add('MAIN FIT — q50 liquid filtered mass')
    add(f"windowTau=[{a.fit_tau_min:g},{a.fit_tau_max:g}] n={main['n']} t=[{main['tMin']:.12g},{main['tMax']:.12g}]")
    add(f"U_left={main['uLeft']:.12g} U_right={main['uRight']:.12g} U_mean={main['uMean']:.12g}")
    add(f"G_TC={main['Gtc']:.12g} symmetry={main['symmetryRelative']:.12g} R2half={main['r2Half']:.12g}")
    add('');add('HISTORICAL x13h REFERENCE — contextual, not constitutively matched')
    add(f'historical_G_TC={histG:.12g} historical_x13h_U_TC=0.390625 historical_x13h_U_measured={histX13hU:.12g}')
    add(f'historical_G_applied_to_current_U_TC={histCurrentU:.12g}')
    add(f"G_TC/current_vs_historical_gain={main['Gtc']/histG:.12g} delta={100*(main['Gtc']/histG-1):+.6g}%")
    add('reason: historical x13h gamma=8,kBT=0.125,dt=0.0063471328149; current x14 gamma=20,kBT_L=0.02,kBT_G=0.08,dt=0.002.')
    add('');add('WINDOW / EDGE SENSITIVITY')
    for q in thresholds:
        k=f'q{int(round(100*q)):02d}'
        for name,_,_ in windows:
            z=fits[(k,name)]
            if z:add(f"{k} {name}: G_TC={z['Gtc']:.12g} U={z['uMean']:.12g} symmetry={z['symmetryRelative']:.12g} R2half={z['r2Half']:.12g} n={z['n']}")
    add('');add('AUXILIARY AUDITS')
    add(f'frames={len(series)} liquidMassRelSpan={(max(masses)-min(masses))/statistics.fmean(masses):.3e} liquidCOMdrift=({dxcm:.12g},{dycm:.12g})')
    add(f'kBT_L_mean={finite_mean(kL):.12g} kBT_G_mean={finite_mean(kG):.12g}')
    add(f'limiterClipMax={finite_max(clip):.12g} Q6nonConvergedSamples={q6bad} Q6residualRelMax={q6res:.12g}')
    add('');add('Interpretation: compare first to the current two-phase U_TC theory, then explicitly to historical G_TC=0.79457172. The historical comparison is contextual because the constitutive fluid differs.')
    (out/'taylor_culick_two_phase_report.txt').write_text('\n'.join(lines)+'\n')
    print(f"[0493x14ak-analysis] U_TC={utc:.8g} tau={tau:.8g} MAIN U={main['uMean']:.8g} G_TC={main['Gtc']:.8g} symmetry={main['symmetryRelative']:.3e} R2half={main['r2Half']:.8g}")
    print(f"[0493x14ak-analysis] historical G_TC={histG:.8g} ratio={main['Gtc']/histG:.8g} delta={100*(main['Gtc']/histG-1):+.3f}%")
    print(f'[0493x14ak-analysis] report={out/"taylor_culick_two_phase_report.txt"}')

if __name__=='__main__':main()
