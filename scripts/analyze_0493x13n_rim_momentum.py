#!/usr/bin/env python3
"""Offline momentum audit for 0493x13n Taylor-Culick sheet runs.

Reads existing .smpcd dumps only. No pandas/scipy and no solver/source changes.
The audit reports:
  * q50 edge speeds (same integrated line-mass definition as x13n),
  * inward x-momentum stored in each half-sheet,
  * inward x-momentum stored in moving near-rim control volumes of width H, 1.5H, 2H,
  * corresponding linear fits on main and late Taylor-Culick windows.

Important: dP/dt of a moving control volume is a momentum-storage rate, NOT by itself
an external-force measurement; flux and stress terms across its inner boundary are not
available from particle states alone. The width sensitivity is therefore diagnostic.
"""
from __future__ import annotations
import argparse, csv, math, re, statistics, struct
from array import array
from pathlib import Path

MAGIC = b"SRCMPCD_STATE" + b"\0"*(16-len("SRCMPCD_STATE"))
STEP_RE = re.compile(r"state_step_(\d+)\.smpcd$")

def read_array(f, code, n):
    a=array(code); a.fromfile(f,n)
    if len(a)!=n: raise RuntimeError("truncated state")
    return a

def read_state(path):
    with path.open('rb') as f:
        if f.read(16)!=MAGIC: raise RuntimeError(f"{path}: bad magic")
        version,endian,dim,layout,n,has_type,has_mass,reserved_count,type_bytes=struct.unpack('<IIIIQIIII',f.read(40))
        if (version,endian,dim,layout)!=(2,0x01020304,2,1): raise RuntimeError(f"{path}: unsupported header")
        if reserved_count: f.read(8*reserved_count)
        x=read_array(f,'d',n); y=read_array(f,'d',n); vx=read_array(f,'d',n); vy=read_array(f,'d',n)
        _typ=read_array(f,'I',n) if has_type else None
        mass=read_array(f,'d',n) if has_mass else None
        if has_type and type_bytes!=4: raise RuntimeError(f"{path}: unsupported type width")
        role=read_array(f,'B',n)
    return x,y,vx,vy,mass,role

def smooth5(v):
    out=[0.0]*len(v)
    for i in range(len(v)):
        s=3*v[i]
        if i>=1:s+=2*v[i-1]
        if i+1<len(v):s+=2*v[i+1]
        if i>=2:s+=v[i-2]
        if i+2<len(v):s+=v[i+2]
        out[i]=s/9.0
    return out

def interp(x0,y0,x1,y1,target):
    d=y1-y0
    q=.5 if abs(d)<1e-30 else (target-y0)/d
    q=max(0.0,min(1.0,q))
    return x0+q*(x1-x0)

def q50_edges(profile,h,split_x,nominal):
    target=.5*nominal; split=min(len(profile)-2,max(1,int(split_x/h)))
    left=[]; right=[]
    for i in range(len(profile)-1):
        a,b=profile[i],profile[i+1]; x0=(i+.5)*h; x1=(i+1.5)*h
        if a<target<=b and i<split: left.append(interp(x0,a,x1,b,target))
        if a>=target>b and i>=split-1: right.append(interp(x0,a,x1,b,target))
    if not left or not right: raise RuntimeError("cannot locate q50 edges")
    return min(left),max(right)

def fit(xs,ys):
    if len(xs)<3:return None
    xm=statistics.fmean(xs); ym=statistics.fmean(ys)
    sxx=sum((x-xm)**2 for x in xs)
    if sxx<=0:return None
    slope=sum((x-xm)*(y-ym) for x,y in zip(xs,ys))/sxx
    intercept=ym-slope*xm
    pred=[intercept+slope*x for x in xs]
    sse=sum((y-p)**2 for y,p in zip(ys,pred)); sst=sum((y-ym)**2 for y in ys)
    r2=1-sse/sst if sst>0 else math.nan
    return slope,intercept,r2,math.sqrt(sse/len(xs))

def state_metrics(path,step,dt,nx,h,nominal,H):
    x,y,vx,vy,mass,role=read_state(path)
    ids=[i for i in range(len(x)) if role[i]==1]
    if not ids: raise RuntimeError(f"{path}: no active fluid")
    line=[0.0]*nx; M=sx=sy=spx=spy=0.0
    for i in ids:
        w=1.0 if mass is None else mass[i]
        M+=w; sx+=w*x[i]; sy+=w*y[i]; spx+=w*vx[i]; spy+=w*vy[i]
        ix=int(math.floor(x[i]/h))
        if 0<=ix<nx: line[ix]+=w
    xcm=sx/M; ycm=sy/M
    xl,xr=q50_edges(smooth5(line),h,xcm,nominal)
    row={'step':step,'time':step*dt,'mass':M,'xCM':xcm,'yCM':ycm,'xLeft_q50':xl,'xRight_q50':xr,
         'halfSpan_q50':.5*(xr-xl),'globalMeanVx':spx/M,'globalMeanVy':spy/M}
    # half-sheet momentum, split at instantaneous xCM. Inward sign is positive.
    for side in ('L','R'):
        js=[i for i in ids if (x[i]<xcm if side=='L' else x[i]>=xcm)]
        mm=sum((1.0 if mass is None else mass[i]) for i in js)
        pp=sum((1.0 if mass is None else mass[i])*vx[i] for i in js)
        inward=pp if side=='L' else -pp
        row[f'halfMass_{side}']=mm; row[f'halfPxIn_{side}']=inward; row[f'halfMeanVxIn_{side}']=inward/mm
    # Moving near-rim CVs: [edge, edge+W] and [edge-W, edge].
    for mult in (1.0,1.5,2.0):
        W=mult*H; tag=str(mult).replace('.','p')+'H'
        for side in ('L','R'):
            if side=='L': lo,hi=xl,min(xcm,xl+W)
            else: lo,hi=max(xcm,xr-W),xr
            js=[i for i in ids if lo<=x[i]<=hi]
            mm=sum((1.0 if mass is None else mass[i]) for i in js)
            pp=sum((1.0 if mass is None else mass[i])*vx[i] for i in js)
            inward=pp if side=='L' else -pp
            row[f'cvMass_{tag}_{side}']=mm; row[f'cvPxIn_{tag}_{side}']=inward; row[f'cvMeanVxIn_{tag}_{side}']=inward/mm if mm else math.nan
    return row

def window_fit(rows,tau,utc,rho,H,sigma,t0,t1,label):
    rr=[r for r in rows if t0*tau<=r['time']<=t1*tau]
    if len(rr)<3:return {'window':label,'n':len(rr),'status':'INSUFFICIENT'}
    t=[r['time'] for r in rr]
    fl=fit(t,[r['xLeft_q50'] for r in rr]); fr=fit(t,[r['xRight_q50'] for r in rr]); fh=fit(t,[r['halfSpan_q50'] for r in rr])
    uL=fl[0];uR=-fr[0];u=.5*(uL+uR); g=u/utc
    out={'window':label,'n':len(rr),'status':'OK','tMin':rr[0]['time'],'tMax':rr[-1]['time'],
         'uLeft':uL,'uRight':uR,'uMean':u,'Gtc':g,'edgeR2Mean':.5*(fl[2]+fr[2]),
         'idealMomentumRateFromMeasuredU':rho*H*u*u,'idealMomentumRatioFromMeasuredU':rho*H*u*u/(2*sigma)}
    for name,keyL,keyR in [('half','halfPxIn_L','halfPxIn_R')]:
        a=fit(t,[r[keyL] for r in rr]);b=fit(t,[r[keyR] for r in rr]);s=.5*(a[0]+b[0])
        out[f'{name}PdotMean']=s;out[f'{name}Pdot_over_2sigma']=s/(2*sigma);out[f'{name}PdotR2Mean']=.5*(a[2]+b[2])
    for mult in (1.0,1.5,2.0):
        tag=str(mult).replace('.','p')+'H';kL=f'cvPxIn_{tag}_L';kR=f'cvPxIn_{tag}_R';mL=f'cvMass_{tag}_L';mR=f'cvMass_{tag}_R'
        a=fit(t,[r[kL] for r in rr]);b=fit(t,[r[kR] for r in rr]);s=.5*(a[0]+b[0])
        ma=fit(t,[r[mL] for r in rr]);mb=fit(t,[r[mR] for r in rr]);ms=.5*(ma[0]+mb[0])
        out[f'cvPdot_{tag}']=s;out[f'cvPdot_{tag}_over_2sigma']=s/(2*sigma);out[f'cvPdot_{tag}_over_rhoHU2']=s/(rho*H*u*u) if u else math.nan
        out[f'cvPdotR2_{tag}']=.5*(a[2]+b[2]);out[f'cvMdot_{tag}']=ms
    return out

def write_csv(path,rows):
    path.parent.mkdir(parents=True,exist_ok=True)
    keys=[]
    for r in rows:
        for k in r:
            if k not in keys:keys.append(k)
    with path.open('w',newline='') as f:
        w=csv.DictWriter(f,fieldnames=keys);w.writeheader();w.writerows(rows)

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--run-root',type=Path,required=True);ap.add_argument('--sigma',type=float,required=True)
    ap.add_argument('--Lx',type=float,default=2.5);ap.add_argument('--Ly',type=float,default=1.0);ap.add_argument('--nx',type=int,default=640);ap.add_argument('--ny',type=int,default=256)
    ap.add_argument('--gamma',type=float,default=8);ap.add_argument('--mass',type=float,default=1.0);ap.add_argument('--dt',type=float,default=0.0063471328149122585)
    ap.add_argument('--thickness-cells',type=float,default=64);ap.add_argument('--outdir',type=Path,default=None)
    a=ap.parse_args();h=a.Lx/a.nx
    if abs(h-a.Ly/a.ny)>1e-12:raise SystemExit('square cells required')
    H=a.thickness_cells*h;rho=a.gamma*a.mass/(h*h);utc=math.sqrt(2*a.sigma/(rho*H));tau=H/utc;nominal=a.gamma*a.mass*a.thickness_cells
    states=[]
    init=sorted((a.run_root/'init').glob('*.smpcd'))
    if init:states.append((0,init[0]))
    for p in sorted((a.run_root/'output').glob('state_step_*.smpcd')):
        m=STEP_RE.search(p.name)
        if m:states.append((int(m.group(1)),p))
    # de-duplicate step 0 if needed
    d={s:p for s,p in states};states=sorted(d.items())
    if len(states)<4:raise SystemExit(f'need >=4 states, found {len(states)}')
    rows=[state_metrics(p,s,a.dt,a.nx,h,nominal,H) for s,p in states]
    fits=[window_fit(rows,tau,utc,rho,H,a.sigma,.5,1.75,'main_0p5_1p75tau'),window_fit(rows,tau,utc,rho,H,a.sigma,1.0,2.0,'late_1_2tau')]
    out=a.outdir or (a.run_root/'analysis_momentum_0493x13n');out.mkdir(parents=True,exist_ok=True)
    write_csv(out/'rim_momentum_trace.csv',rows);write_csv(out/'rim_momentum_fits.csv',fits)
    with (out/'rim_momentum_report.txt').open('w') as f:
        f.write('0493x13n — offline rim momentum audit\n')
        f.write('=====================================\n')
        f.write(f'runRoot={a.run_root}\n sigma={a.sigma:.12g} rho={rho:.12g} H={H:.12g} U_TC={utc:.12g} tau_TC={tau:.12g} states={len(rows)}\n')
        f.write('Contract: moving-CV dP/dt is momentum storage, not external force by itself; inner-boundary flux/stress are not measured.\n\n')
        for z in fits:
            f.write(f"[{z['window']}] status={z['status']} n={z['n']}\n")
            if z['status']!='OK':continue
            f.write(f"  Umean={z['uMean']:.12g} G_TC={z['Gtc']:.12g} edgeR2Mean={z['edgeR2Mean']:.9g}\n")
            f.write(f"  rho*H*U^2={z['idealMomentumRateFromMeasuredU']:.12g} ratio_to_2sigma={z['idealMomentumRatioFromMeasuredU']:.12g}\n")
            f.write(f"  half-sheet Pdot={z['halfPdotMean']:.12g} ratio_to_2sigma={z['halfPdot_over_2sigma']:.12g} R2mean={z['halfPdotR2Mean']:.9g}\n")
            for tag in ('1p0H','1p5H','2p0H'):
                f.write(f"  CV {tag}: Pdot={z['cvPdot_'+tag]:.12g} ratio_to_2sigma={z['cvPdot_'+tag+'_over_2sigma']:.12g} ratio_to_rhoHU2={z['cvPdot_'+tag+'_over_rhoHU2']:.12g} PdotR2={z['cvPdotR2_'+tag]:.9g} Mdot={z['cvMdot_'+tag]:.12g}\n")
            f.write('\n')
    print(out/'rim_momentum_report.txt')
if __name__=='__main__': main()
