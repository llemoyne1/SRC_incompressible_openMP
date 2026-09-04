#!/usr/bin/env python3
"""0493x14x — offline n=2 two-phase oscillating-drop analysis (stdlib only).

Primary observable is the signed quadrupolar deformation from the existing x9f
ellipse diagnostic:
    q2 = ellipticity * cos(2*principalAngle).

Fit:
    q2(t) = exp(-beta*t) [C cos(omega*t) + D sin(omega*t)] + offset.

Frequency reference for an unbounded 2-D cylindrical interface between two
inviscid fluids is
    omega_n^2 = n(n^2-1) sigma / [(rho_L + rho_G) R^3].
The fitted damping beta is reported as a measured quantity only; this analyzer
does not impose a two-viscous-fluid damping law.
"""
from __future__ import annotations
import argparse,csv,math,statistics,json
from pathlib import Path


def read_csv(path: Path):
    if not path.exists(): return []
    with path.open(newline='') as f: return list(csv.DictReader(f))

def ff(r,k,d=math.nan):
    try:
        v=float(r[k]); return v if math.isfinite(v) else d
    except Exception: return d

def norm(s): return ''.join(ch.lower() for ch in s if ch.isalnum())
def field(fields, exact=(), contains=()):
    bn={norm(k):k for k in fields}
    for e in exact:
        if norm(e) in bn: return bn[norm(e)]
    for k in fields:
        nk=norm(k)
        if all(norm(x) in nk for x in contains): return k
    return None

def solve3(M,b):
    A=[list(map(float,row))+[float(rhs)] for row,rhs in zip(M,b)]
    for i in range(3):
        p=max(range(i,3),key=lambda r:abs(A[r][i]))
        if abs(A[p][i])<1e-20: return None
        A[i],A[p]=A[p],A[i]; q=A[i][i]
        for j in range(i,4): A[i][j]/=q
        for r in range(3):
            if r==i: continue
            q=A[r][i]
            for j in range(i,4): A[r][j]-=q*A[i][j]
    return [A[i][3] for i in range(3)]

def linear_fit(t,y,w,beta):
    cols=[]
    for tt in t:
        e=math.exp(-beta*tt); cols.append((e*math.cos(w*tt),e*math.sin(w*tt),1.0))
    M=[[sum(c[i]*c[j] for c in cols) for j in range(3)] for i in range(3)]
    bb=[sum(c[i]*yy for c,yy in zip(cols,y)) for i in range(3)]
    co=solve3(M,bb)
    if co is None: return None
    pred=[co[0]*c[0]+co[1]*c[1]+co[2] for c in cols]
    sse=sum((a-b)**2 for a,b in zip(y,pred)); ym=statistics.fmean(y); sst=sum((a-ym)**2 for a in y)
    r2=1-sse/sst if sst>0 else math.nan
    return sse,r2,co,pred

def fit_damped(t_abs,y,w0):
    t0=t_abs[0]; t=[x-t0 for x in t_abs]
    wlo,whi=.55*w0,1.35*w0; blo,bhi=0.0,min(2.0,0.8*w0); best=None
    for nw,nb in ((121,61),(81,51),(61,41)):
        for iw in range(nw):
            w=wlo+(whi-wlo)*iw/max(1,nw-1)
            for ib in range(nb):
                b=blo+(bhi-blo)*ib/max(1,nb-1)
                r=linear_fit(t,y,w,b)
                if r is not None and (best is None or r[0]<best[0]): best=(r[0],w,b,r[1],r[2],r[3])
        if best is None: return None
        _,w,b,_,_,_=best
        dw=(whi-wlo)/max(1,nw-1)*3; db=(bhi-blo)/max(1,nb-1)*3
        wlo,whi=max(.2*w0,w-dw),w+dw; blo,bhi=max(0,b-db),b+db
    return best

def zero_cross_omega(t,y,off):
    z=[v-off for v in y]; cr=[]
    for i in range(1,len(z)):
        a,b=z[i-1],z[i]
        if a==0: cr.append(t[i-1])
        elif a*b<0:
            f=abs(a)/(abs(a)+abs(b)); cr.append(t[i-1]+f*(t[i]-t[i-1]))
    if len(cr)<3: return math.nan,len(cr)
    hp=statistics.median(cr[i+1]-cr[i] for i in range(len(cr)-1))
    return (math.pi/hp if hp>0 else math.nan),len(cr)

def linreg(x,y):
    if len(x)<2: return math.nan,math.nan
    mx,my=statistics.fmean(x),statistics.fmean(y); den=sum((v-mx)**2 for v in x)
    if den==0:return math.nan,math.nan
    a=sum((u-mx)*(v-my) for u,v in zip(x,y))/den; b=my-a*mx
    return a,b

def mean(xs): return statistics.fmean(xs) if xs else math.nan

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--run-root',type=Path,required=True)
    ap.add_argument('--radius-cells',type=float,required=True)
    ap.add_argument('--sigma',type=float,required=True)
    ap.add_argument('--gamma',type=float,required=True)
    ap.add_argument('--liquid-mass',type=float,required=True)
    ap.add_argument('--gas-mass',type=float,required=True)
    ap.add_argument('--h',type=float,required=True)
    ap.add_argument('--wall-speed-scale',type=float,default=0.0)
    ap.add_argument('--mode',type=int,default=2)
    ap.add_argument('--fit-periods',type=float,default=2.5)
    ap.add_argument('--liquid-type',type=int,default=1)
    ap.add_argument('--gas-type',type=int,default=2)
    a=ap.parse_args()
    if a.mode!=2: raise SystemExit('[0493x14x-analysis] n=2 analyzer requires mode=2')

    shape=a.run_root/'output/cuda_ellipse_shape_0493x9f.csv'; rows=read_csv(shape)
    if len(rows)<30: raise SystemExit(f'[0493x14x-analysis] need >=30 x9f rows, got {len(rows)}: {shape}')
    fs=list(rows[0]); fstep=field(fs,exact=('step',)); ft=field(fs,exact=('time',)); fmaj=field(fs,exact=('momentRadiusMajor',),contains=('moment','radius','major')); fmin=field(fs,exact=('momentRadiusMinor',),contains=('moment','radius','minor')); fell=field(fs,exact=('ellipticity',),contains=('ellipt',)); fx=field(fs,exact=('xCM',),contains=('xcm',)); fy=field(fs,exact=('yCM',),contains=('ycm',)); fad=field(fs,exact=('principalAngleDeg','momentAngleDeg','angleDeg'),contains=('angle','deg')); far=field(fs,exact=('principalAngle','momentAngle','angle'),contains=('angle',))
    if any(v is None for v in (fstep,ft,fmaj,fmin)) or (fad is None and far is None):
        raise SystemExit('[0493x14x-analysis] x9f fields insufficient: '+','.join(fs))
    ser=[]; seen=set()
    for r in rows:
        st=int(round(ff(r,fstep))); t=ff(r,ft); maj=ff(r,fmaj); mi=ff(r,fmin)
        if st in seen or not all(math.isfinite(v) for v in (t,maj,mi)) or maj<=0 or mi<=0: continue
        seen.add(st); e=ff(r,fell) if fell else (maj-mi)/(maj+mi); ang=math.radians(ff(r,fad)) if fad else ff(r,far)
        if not all(math.isfinite(v) for v in (e,ang)): continue
        ser.append((st,t,e*math.cos(2*ang),e,ang,maj,mi,ff(r,fx) if fx else math.nan,ff(r,fy) if fy else math.nan))
    ser.sort(key=lambda q:(q[1],q[0]))
    if len(ser)<30: raise SystemExit('[0493x14x-analysis] insufficient usable x9f rows')

    R=a.radius_cells*a.h; rhoL=a.gamma*a.liquid_mass/a.h**2; rhoG=a.gamma*a.gas_mass/a.h**2; rhoI=rhoL+rhoG; n=2
    w0=math.sqrt(n*(n*n-1)*a.sigma/(rhoI*R**3)); T0=2*math.pi/w0; wvac=math.sqrt(n*(n*n-1)*a.sigma/(rhoL*R**3))
    tend=ser[0][1]+a.fit_periods*T0; fit=[q for q in ser if q[1]<=tend+1e-12]
    if len(fit)<30: fit=ser[:max(30,min(len(ser),100))]
    tt=[q[1] for q in fit]; yy=[q[2] for q in fit]; best=fit_damped(tt,yy,w0)
    if best is None: raise SystemExit('[0493x14x-analysis] damped fit failed')
    sse,w,beta,r2,coef,pred=best; wz,nzc=zero_cross_omega(tt,yy,coef[2])
    xv=[(q[1],q[7]) for q in fit if math.isfinite(q[7])]; yv=[(q[1],q[8]) for q in fit if math.isfinite(q[8])]
    vx,_=linreg([p[0] for p in xv],[p[1] for p in xv]) if xv else (math.nan,math.nan); vy,_=linreg([p[0] for p in yv],[p[1] for p in yv]) if yv else (math.nan,math.nan)

    # Existing diagnostics: temperature/mass by species and capillary limiter.
    sp=read_csv(a.run_root/'output/species_runtime_0493x14x.csv')
    # Flexible species schema: collect rows by explicit type if available.
    bytype={a.liquid_type:[],a.gas_type:[]}
    if sp:
        fflds=list(sp[0]); ftyp=field(fflds,exact=('type','speciesType'),contains=('type',)); fkbt=field(fflds,exact=('kBT','temperature'),contains=('kbt',)); fn=field(fflds,exact=('Nfluid','count','particleCount'),contains=('nfluid',)); ftime=field(fflds,exact=('time',)); fke=field(fflds,exact=('kineticEnergy',),contains=('kinetic','energy')); fmass=field(fflds,exact=('totalMass',),contains=('total','mass')); fmvx=field(fflds,exact=('meanVx',),contains=('mean','vx')); fmvy=field(fflds,exact=('meanVy',),contains=('mean','vy'))
        for r in sp:
            try: typ=int(round(ff(r,ftyp))) if ftyp else None
            except Exception: typ=None
            if typ in bytype:
                nv=ff(r,fn) if fn else math.nan
                kval=ff(r,fkbt) if fkbt else math.nan
                if not math.isfinite(kval) and fke and fmass and fmvx and fmvy and math.isfinite(nv) and nv>0:
                    ke=ff(r,fke); mt=ff(r,fmass); ux=ff(r,fmvx); uy=ff(r,fmvy)
                    if all(math.isfinite(v) for v in (ke,mt,ux,uy)):
                        # 2-D proxy: K_peculiar/N; unlike the cell thermostat diagnostic,
                        # this also contains unresolved cell-mean hydrodynamic energy.
                        kval=max(0.0, ke-0.5*mt*(ux*ux+uy*uy))/nv
                bytype[typ].append((ff(r,ftime) if ftime else math.nan,kval,nv))
    stats={}
    for typ,name in ((a.liquid_type,'liquid'),(a.gas_type,'gas')):
        vals=bytype[typ]; kb=[v[1] for v in vals if math.isfinite(v[1])]; nn=[v[2] for v in vals if math.isfinite(v[2])]
        stats[name]={'kBTMean':mean(kb),'kBTMin':min(kb) if kb else math.nan,'kBTMax':max(kb) if kb else math.nan,'countMin':min(nn) if nn else math.nan,'countMax':max(nn) if nn else math.nan,'rows':len(vals)}

    lim=read_csv(a.run_root/'output/cuda_surface_tension_limiter_0493x9r.csv'); clips=[ff(r,'clipFraction') for r in lim if math.isfinite(ff(r,'clipFraction'))]
    x6g=read_csv(a.run_root/'output/cuda_phase_interface_pressure_0493x6g.csv')

    out=a.run_root/'analysis'; out.mkdir(parents=True,exist_ok=True)
    with (out/'oscillating_drop_n2_trace_0493x14x.csv').open('w',newline='') as f:
        cw=csv.writer(f); cw.writerow(['step','time','mode2Signed','ellipticityAbs','principalAngleRad','momentRadiusMajor','momentRadiusMinor','xCM','yCM']); cw.writerows(ser)
    with (out/'oscillating_drop_n2_fit_0493x14x.csv').open('w',newline='') as f:
        cw=csv.writer(f); cw.writerow(['time','mode2Signed','fit']); cw.writerows(zip(tt,yy,pred))

    result={
        'benchmark':'0493x14x_two_phase_oscillating_drop_n2','status':'MEASURED',
        'theory':{'model':'2D inviscid two-fluid cylinder, unbounded exterior','rhoLiquid':rhoL,'rhoGas':rhoG,'rhoGasOverLiquid':rhoG/rhoL,'rhoInertialSum':rhoI,'radius':R,'sigma':a.sigma,'omega':w0,'period':T0,'omegaLiquidVacuumReference':wvac,'twoFluidOverVacuum':w0/wvac},
        'fit':{'rows':len(fit),'timeStart':fit[0][1],'timeEnd':fit[-1][1],'omega':w,'betaMeasured':beta,'R2':r2,'Gomega':w/w0,'zeroCrossOmega':wz,'zeroCrossGomega':wz/w0 if math.isfinite(wz) else math.nan,'zeroCrossings':nzc,'offset':coef[2]},
        'geometry':{'comDriftVx':vx,'comDriftVy':vy,'comDriftSpeed':math.hypot(vx,vy) if math.isfinite(vx) and math.isfinite(vy) else math.nan,'mode2Initial':ser[0][2]},
        'speciesRuntime':stats,'limiter':{'maxClipFraction':max(clips) if clips else math.nan},'x6gRows':len(x6g)
    }
    (out/'oscillating_drop_n2_summary_0493x14x.json').write_text(json.dumps(result,indent=2)+'\n')
    lines=[
        '===== 0493x14x TWO-PHASE OSCILLATING DROP n=2 =====',
        'status=MEASURED',
        f"theory2D.twoFluid rhoL={rhoL:.12g} rhoG={rhoG:.12g} rhoG/rhoL={rhoG/rhoL:.9g} omega0={w0:.12g} period0={T0:.12g}",
        f"theory2D.discrimination omegaVacuumLiquidOnly={wvac:.12g} twoFluid/vacuum={w0/wvac:.9g}",
        f"fit rows={len(fit)} window=[{fit[0][1]:.9g},{fit[-1][1]:.9g}] omega={w:.12g} betaMeasured={beta:.12g} R2={r2:.9g}",
        f"gain Gomega={w/w0:.9g} zeroCrossGomega={(wz/w0 if math.isfinite(wz) else math.nan):.9g} crossings={nzc}",
        f"COM driftVx={vx:.9g} driftVy={vy:.9g} speed={(math.hypot(vx,vy) if math.isfinite(vx) and math.isfinite(vy) else math.nan):.9g}",
        f"liquid kBTmean={stats['liquid']['kBTMean']:.9g} countRange=[{stats['liquid']['countMin']:.9g},{stats['liquid']['countMax']:.9g}]",
        f"gas kBTmean={stats['gas']['kBTMean']:.9g} countRange=[{stats['gas']['countMin']:.9g},{stats['gas']['countMax']:.9g}]",
        f"limiter maxClipFraction={(max(clips) if clips else math.nan):.9g} x6gRows={len(x6g)}",
        'dampingInterpretation=beta is measured only; no two-viscous-fluid analytic damping law is imposed.',
        'qualificationInterpretation=Gomega tests the integrated x6g+x9+x14l+x14v+liquid-closure response; do not fold Gomega into mechanical sigma.'
    ]
    report='\n'.join(lines)+'\n'; (out/'oscillating_drop_n2_report_0493x14x.txt').write_text(report); print(report,end='')
    try:
        import matplotlib.pyplot as plt
        fig=plt.figure(); ax=fig.add_subplot(111); ax.plot([q[1] for q in ser],[q[2] for q in ser],label='signed n=2'); ax.plot(tt,pred,label=f'fit Gomega={w/w0:.3f}'); ax.set_xlabel('time'); ax.set_ylabel('signed quadrupole'); ax.legend(); fig.tight_layout(); fig.savefig(out/'oscillating_drop_n2_fit_0493x14x.png',dpi=170); plt.close(fig)
    except Exception as e: print(f'[0493x14x-analysis] plotting skipped: {e}')
    return 0

if __name__=='__main__': raise SystemExit(main())
