#!/usr/bin/env python3
from __future__ import annotations
import argparse,csv,importlib.util,json,math,re,sys
from pathlib import Path
import numpy as np

def load_module(path,name):
    spec=importlib.util.spec_from_file_location(name,path);mod=importlib.util.module_from_spec(spec);spec.loader.exec_module(mod);return mod

def f(x,default=math.nan):
    try:return float(x)
    except:return default

def i(x,default=0):
    try:return int(float(x))
    except:return default

def write_csv(path,rows):
    path.parent.mkdir(parents=True,exist_ok=True)
    keys=[]
    for r in rows:
        for k in r:
            if k not in keys:keys.append(k)
    with path.open('w',newline='') as fp:
        w=csv.DictWriter(fp,fieldnames=keys,lineterminator='\n');w.writeheader();w.writerows(rows)

def read_manifest(path):
    with path.open(newline='') as fp:return list(csv.DictReader(fp))

def read_time(path):
    try:
        s=path.read_text();m=re.search(r'elapsed=([0-9.eE+-]+)',s);return float(m.group(1)) if m else math.nan
    except:return math.nan

def extract_state_metrics(w1,path,k,mode_max,nx,ny,gamma):
    st=w1.read_state(path);fluid=st['role']==1;x=st['x'][fluid];m=st['mass'][fluid];vx=st['vx'][fluid]
    M=float(np.sum(m));out=[]
    for h in range(1,mode_max+1):
        b=np.exp(-1j*h*k*x)
        rho=2*np.sum(m*b)/M
        ux=2*np.sum(m*vx*b)/M
        out.append((complex(rho),complex(ux)))
    # Eulerian x-column density ratio, averaged over y and normalized by gamma.
    ix=np.floor((x/(2*math.pi/k))*nx).astype(int)%nx
    counts=np.bincount(ix,minlength=nx)
    ratio=counts/(ny*gamma)
    return out,float(np.min(ratio)),float(np.max(ratio))

def prepend_initial(w1,run_dir,dt,k,mode_max,nx,ny,gamma):
    meta_files=list((run_dir/'init').glob('*.meta.json'));state_files=list((run_dir/'init').glob('*.smpcd'))
    if not state_files:raise ValueError(f'no initial state in {run_dir}')
    series=[]
    modes,rmin,rmax=extract_state_metrics(w1,state_files[0],k,mode_max,nx,ny,gamma)
    series.append((0,0.0,modes,rmin,rmax))
    for step,path in w1.list_dumps(run_dir):
        modes,rmin,rmax=extract_state_metrics(w1,path,k,mode_max,nx,ny,gamma)
        series.append((step,step*dt,modes,rmin,rmax))
    # avoid duplicate step0 if solver dumped one
    uniq={}
    for row in series:uniq[row[0]]=row
    return [uniq[s] for s in sorted(uniq)]

def first_zero_time(t,y):
    y=np.asarray(y,float);t=np.asarray(t,float)
    s0=1 if y[0]>=0 else -1
    for j in range(1,len(y)):
        if y[j]==0:return float(t[j])
        if (1 if y[j]>=0 else -1)!=s0:
            a,b=y[j-1],y[j];ta,tb=t[j-1],t[j]
            if b==a:return float(tb)
            return float(ta+(0-a)*(tb-ta)/(b-a))
    return math.nan

def summarize_series(t,modes,rmin,rmax,cs_ref,k,period_ref):
    t=np.asarray(t,float);tau=t/period_ref
    rho=np.asarray([[z[0] for z in row] for row in modes],complex)
    ux=np.asarray([[z[1] for z in row] for row in modes],complex)
    # rotate mode-1 velocity onto its initial phase so u1(0)>0
    ref=ux[0,0];unit=np.conj(ref)/abs(ref) if abs(ref)>0 else 1.0
    uproj=np.real(ux[:,0]*unit)
    tz=first_zero_time(t,uproj)
    cs_quarter=(math.pi/(2*k*tz)) if math.isfinite(tz) and tz>0 else math.nan
    energies=np.abs(ux)**2+(cs_ref*np.abs(rho))**2
    denom=np.sum(energies,axis=1)
    hfrac=np.sum(energies[:,1:],axis=1)/np.maximum(denom,1e-300)
    early=tau<=1.0;half=tau<=0.5
    # fundamental acoustic envelope normalized by initial mode energy
    e1=energies[:,0];e1ratio=e1/max(e1[0],1e-300)
    return {
      'csQuarterCycle':cs_quarter,
      'csQuarterRelToRef':abs(cs_quarter-cs_ref)/cs_ref if math.isfinite(cs_quarter) else math.nan,
      'harmonicFractionPeakCycle1':float(np.max(hfrac[early])) if np.any(early) else math.nan,
      'harmonicFractionMeanCycle1':float(np.mean(hfrac[early])) if np.any(early) else math.nan,
      'harmonicFractionPeakHalfCycle':float(np.max(hfrac[half])) if np.any(half) else math.nan,
      'fundamentalEnergyMinCycle1':float(np.min(e1ratio[early])) if np.any(early) else math.nan,
      'rhoColumnMin':float(np.min(rmin)),'rhoColumnMax':float(np.max(rmax)),
      'samples':len(t),'cyclesObserved':float(t[-1]/period_ref) if len(t)>1 else 0.0,
    }

def stats(vals):
    a=np.asarray([x for x in vals if math.isfinite(x)],float)
    if len(a)==0:return (math.nan,math.nan,math.nan)
    return float(np.mean(a)),float(np.std(a,ddof=1)) if len(a)>1 else 0.0,float(np.std(a,ddof=1)/math.sqrt(len(a))) if len(a)>1 else 0.0

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--campaign-root',default='runs/0493x13h_L072_qualification');ap.add_argument('--repo-root',default='.');ap.add_argument('--cs-ref',type=float,default=.3554482475790296);ap.add_argument('--nuT-ref',type=float,default=.0005328464868639473);ap.add_argument('--mode-max',type=int,default=4);a=ap.parse_args()
    root=Path(a.repo_root).resolve();camp=root/a.campaign_root
    manifest=camp/'C_Mach'/'manifest_0493x13h_C_Mach.csv';rows=read_manifest(manifest)
    w1=load_module(root/'scripts/analyze_0493w1_src_fluid_calibrator.py','w1_x13e')
    run_rows=[];series_rows=[]
    for r in rows:
        run_dir=camp/'C_Mach'/r['runDir'];marker=run_dir/'RUN_COMPLETE_0493x13h_C_Mach';failed=run_dir/'RUN_FAILED_0493x13h_C_Mach'
        status='MISSING'
        if marker.exists():status='COMPLETE'
        elif failed.exists():status='FAILED'
        if status!='COMPLETE':
            run_rows.append({**r,'runStatus':status});continue
        nx=i(r['Nx']);ny=i(r['Ny']);gamma=i(r['gamma']);dt=f(r['dt']);Lx=f(r['Lx']);k=2*math.pi*i(r['modeX'])/Lx
        period_ref=Lx/(a.cs_ref*i(r['modeX']))
        ss=prepend_initial(w1,run_dir,dt,k,a.mode_max,nx,ny,gamma)
        t=[q[1] for q in ss];modes=[q[2] for q in ss];rmin=[q[3] for q in ss];rmax=[q[4] for q in ss]
        met=summarize_series(t,modes,rmin,rmax,a.cs_ref,k,period_ref)
        elapsed=read_time(run_dir/'logs/time_0493x13h_C_Mach.txt')
        run_rows.append({**r,'runStatus':'COMPLETE',**met,'elapsedSeconds':elapsed,'elapsedSecPerPhysicalTime':elapsed/f(r['physicalTime']) if math.isfinite(elapsed) else math.nan})
        for idx,q in enumerate(ss):
            step,time,mm,mn,mx=q;en=[]
            for h,(rho,ux) in enumerate(mm,1):
                en.append(abs(ux)**2+(a.cs_ref*abs(rho))**2)
                series_rows.append({'fluid':r['fluid'],'mach':r['mach'],'Nx':nx,'seed':r['seed'],'step':step,'time':time,'cycles':time/period_ref,'harmonic':h,'rhoReal':rho.real,'rhoImag':rho.imag,'uxReal':ux.real,'uxImag':ux.imag,'acousticEnergy':en[-1],'rhoColumnMin':mn,'rhoColumnMax':mx})
    analysis=camp/'analysis';write_csv(analysis/'C_Mach_runs_0493x13h.csv',run_rows);write_csv(analysis/'C_Mach_mode_series_0493x13h.csv',series_rows)
    # group by Mach/Nx across seeds
    groups=[]
    keys=sorted({(f(r.get('mach')),i(r.get('Nx'))) for r in run_rows if r.get('runStatus')=='COMPLETE'})
    for mach,nx in keys:
        g=[r for r in run_rows if r.get('runStatus')=='COMPLETE' and abs(f(r['mach'])-mach)<1e-12 and i(r['Nx'])==nx]
        csm,css,cssem=stats([f(r.get('csQuarterCycle')) for r in g]);hpm,hps,_=stats([f(r.get('harmonicFractionPeakCycle1')) for r in g]);hhalf,_,_=stats([f(r.get('harmonicFractionPeakHalfCycle')) for r in g]);mn,_,_=stats([f(r.get('rhoColumnMin')) for r in g]);mx,_,_=stats([f(r.get('rhoColumnMax')) for r in g]);wall,_,_=stats([f(r.get('elapsedSecPerPhysicalTime')) for r in g])
        groups.append({'mach':mach,'Nx':nx,'expectedSeeds':i(g[0].get('expectedSeeds'),len(g)) if g else 0,'completedSeeds':len(g),'csQuarterMean':csm,'csQuarterStd':css,'csQuarterSem':cssem,'csQuarterRelToRef':abs(csm-a.cs_ref)/a.cs_ref if math.isfinite(csm) else math.nan,'harmonicFractionPeakCycle1Mean':hpm,'harmonicFractionPeakCycle1Std':hps,'harmonicFractionPeakHalfCycleMean':hhalf,'rhoColumnMinMean':mn,'rhoColumnMaxMean':mx,'elapsedSecPerPhysicalTimeMean':wall})
    write_csv(analysis/'C_Mach_group_summary_0493x13h.csv',groups)
    # compare wavelength 128 vs 256 at each Mach
    quals=[]
    for mach in sorted({f(g['mach']) for g in groups}):
        gg={i(g['Nx']):g for g in groups if abs(f(g['mach'])-mach)<1e-12}
        if 128 not in gg or 256 not in gg:continue
        a128,a256=gg[128],gg[256]
        c1=f(a128['csQuarterMean']);c2=f(a256['csQuarterMean']);h1=f(a128['harmonicFractionPeakCycle1Mean']);h2=f(a256['harmonicFractionPeakCycle1Mean'])
        cwave=abs(c2-c1)/max(abs(c2),1e-30);hwave=abs(h2-h1)/max(max(abs(h1),abs(h2)),1e-6)
        cref=abs(c2-a.cs_ref)/a.cs_ref
        if cref<=.05 and cwave<=.04 and h2<=.10:
            grade='LINEAR_COEFFICIENTS_VALID'
        elif cwave<=.06 and hwave<=.35:
            grade='NONLINEAR_RESOLVED'
        elif cwave<=.10:
            grade='NONLINEAR_REVIEW'
        else:
            grade='UNRESOLVED_OR_KINETIC'
        quals.append({'mach':mach,'cs128':c1,'cs256':c2,'cs256RelToLinear':cref,'csWavelengthRelativeDifference':cwave,'harmonicPeak128':h1,'harmonicPeak256':h2,'harmonicWavelengthRelativeDifference':hwave,'rhoColumnMin256':a256['rhoColumnMinMean'],'rhoColumnMax256':a256['rhoColumnMaxMean'],'compressibleGrade':grade})
    write_csv(analysis/'C_Mach_qualification_0493x13h.csv',quals)
    H=a.cs_ref*f(rows[0]['cellSize'])/a.nuT_ref
    targets=[1000,3000,10000]
    reach=[]
    for q in quals:
        ma=f(q['mach'])
        for R in targets:
            n=math.ceil(R/(ma*H));square_particles=i(rows[0]['gamma'])*n*n
            reach.append({'mach':ma,'compressibleGrade':q['compressibleGrade'],'targetRe':R,'H_h':H,'requiredCharacteristicCells':n,'squareDomainParticlesAtGamma8':square_particles,'ReAtN1024':ma*1024*H,'ReAtN2048':ma*2048*H,'ReAtN4096':ma*4096*H,'ReAtN8192':ma*8192*H})
    write_csv(analysis/'C_Mach_Re_reach_0493x13h.csv',reach)
    print(f'[0493x13h-C-Mach-analysis] runs={len(run_rows)} groups={len(groups)} MachQual={len(quals)} H_h={H:.6g}')
    for q in quals:
        n10=math.ceil(10000/(f(q['mach'])*H));print(f"[0493x13h-C-Mach-analysis] Ma={q['mach']} grade={q['compressibleGrade']} cs256={q['cs256']:.6g} harm256={q['harmonicPeak256']:.4g} Re1e4_cells={n10}")

def self_test():
    cs=.355;L=.5;k=2*math.pi/L;T=L/cs;t=np.linspace(0,2*T,81);U=.1
    modes=[]
    for tt in t:
        ux=U*math.cos(cs*k*tt);rho=(U/cs)*math.sin(cs*k*tt)
        modes.append([(complex(rho,0),complex(ux,0)),(0j,0j),(0j,0j),(0j,0j)])
    r=summarize_series(t,modes,[1]*len(t),[1]*len(t),cs,k,T)
    err=abs(r['csQuarterCycle']-cs)/cs
    print(f'[0493x13h-C-Mach-analysis-selftest] csErr={err:.3e} harmonic={r["harmonicFractionPeakCycle1"]:.3e}')
    if err>2e-3 or r['harmonicFractionPeakCycle1']>1e-12:raise SystemExit(2)

if __name__=='__main__':
    if '--self-test' in sys.argv:self_test()
    else:main()
