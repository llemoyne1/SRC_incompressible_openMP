#!/usr/bin/env python3
import csv, glob, math, os, re, struct, sys
from array import array
from pathlib import Path

LIQUID_TYPE = 1
ROOT_GLOB = "runs/0493x10y_R*_kBT*_g*"
OUT = Path("0493x10y_size_temperature_law_summary.csv")
RUN_RE = re.compile(r"0493x10y_R(?P<R>[0-9]+)_kBT(?P<kbt>[0-9.]+)_g(?P<g>[0-9mp]+)$")
DT = 0.002
MASS = 1.0
GPAIR = -0.1

def decode_tag(s):
    sign = -1.0 if s.startswith('m') else 1.0
    if s.startswith('m'): s = s[1:]
    return sign * float(s.replace('p','.'))

def read_array(f, code, n):
    a = array(code); need = a.itemsize*n; raw=f.read(need)
    if len(raw)!=need: raise RuntimeError('truncated state array')
    a.frombytes(raw)
    if sys.byteorder=='big': a.byteswap()
    return a

def read_kv(run):
    fs=sorted(glob.glob(os.path.join(run,'params','*.kv')))
    if not fs: raise RuntimeError(f'{run}: no params kv')
    out={}
    with open(fs[-1]) as f:
        for line in f:
            if '=' not in line or line.lstrip().startswith('#'): continue
            k,v=line.split('=',1); out[k.strip()]=v.strip()
    return out

def read_state(path,R_cells,h):
    with open(path,'rb') as f:
        magic=f.read(16)
        if not magic.startswith(b'SRCMPCD_STATE'): raise RuntimeError(f'{path}: bad magic')
        fmt='<IIIIQIIII'; raw=f.read(struct.calcsize(fmt))
        version,endian,dim,ns,n,a,b,rsv_n,word=struct.unpack(fmt,raw)
        f.read(8*8)
        x=read_array(f,'d',n); y=read_array(f,'d',n)
        vx=read_array(f,'d',n); vy=read_array(f,'d',n)
        typ=read_array(f,'I',n); mass=read_array(f,'d',n)
        tail=f.read(); role=tail[:n] if len(tail)>=n else bytes([1])*n
    ids=[i for i in range(n) if typ[i]==LIQUID_TYPE and role[i]==1]
    if not ids: raise RuntimeError(f'{path}: no liquid fluid particles')
    M=sum(mass[i] for i in ids)
    xcm=sum(mass[i]*x[i] for i in ids)/M; ycm=sum(mass[i]*y[i] for i in ids)/M
    vxcm=sum(mass[i]*vx[i] for i in ids)/M; vycm=sum(mass[i]*vy[i] for i in ids)/M
    R=R_cells*h
    rr=sorted(math.hypot(x[i]-xcm,y[i]-ycm) for i in ids)
    r90=rr[min(len(rr)-1,max(0,math.ceil(0.90*len(rr))-1))]
    beyond=sum(1 for r in rr if r>2*R)
    return dict(N=len(ids),M=M,xcm=xcm,ycm=ycm,vxcm=vxcm,vycm=vycm,
                speed=math.hypot(vxcm,vycm),r90_over_R=r90/R,
                frac_beyond_2R=beyond/len(rr))

def read_summary(run):
    p=os.path.join(run,'output','summary_runtime.csv')
    with open(p,newline='') as f: rows=list(csv.DictReader(f))
    if not rows: raise RuntimeError(f'{p}: empty')
    r=rows[-1]
    return dict(step=int(float(r['step'])), time=float(r['time']),
                kBT=float(r.get('kBT','nan') or 'nan'))

def read_interface(run):
    p=os.path.join(run,'output','cuda_phase_kinetic_crossing_0493x9z.csv')
    if not os.path.exists(p): return dict(collisions=0,overlaps=0,mean_delta=float('nan'))
    with open(p,newline='') as f: rows=list(csv.DictReader(f))
    def I(r,k): return int(float(r.get(k,0) or 0))
    def F(r,k): return float(r.get(k,0) or 0)
    ep=sum(I(r,'q6ThermalInterfaceEndpointSamples') for r in rows)
    md=(sum(F(r,'q6ThermalMeanThickness')*I(r,'q6ThermalInterfaceEndpointSamples') for r in rows)/ep) if ep else float('nan')
    return dict(collisions=sum(I(r,'continuousWallCollisions') for r in rows),
                overlaps=sum(I(r,'x10pInitialOverlapResolved') for r in rows), mean_delta=md)

cases={}
for run in glob.glob(ROOT_GLOB):
    m=RUN_RE.search(os.path.basename(run))
    if not m: continue
    R=int(m.group('R')); kbt=float(m.group('kbt')); g=decode_tag(m.group('g'))
    try:
        kv=read_kv(run)
        h=min(float(kv['Lx'])/int(kv['Nx']),float(kv['Ly'])/int(kv['Ny']))
        sm=read_summary(run)
        state=os.path.join(run,'output',f"state_step_{sm['step']:08d}.smpcd")
        if not os.path.exists(state):
            ds=sorted(glob.glob(os.path.join(run,'output','state_step_*.smpcd')))
            if not ds: raise RuntimeError(f'{run}: no state dump')
            state=ds[-1]
        st=read_state(state,R,h); itf=read_interface(run); st['h']=h
    except Exception as e:
        print(f'[0493x10y-analyze] WARN {run}: {e}',file=sys.stderr); continue
    cases[(R,round(kbt,12),round(g,12))]=dict(run=run,**sm,**st,**itf)

rows=[]
for R,kbt in sorted({(k[0],k[1]) for k in cases}):
    z=cases.get((R,kbt,0.0)); q=cases.get((R,kbt,round(GPAIR,12)))
    if not z or not q: continue
    t=min(z['time'],q['time'])
    dy=0.5*GPAIR*t*t; dv=GPAIR*t
    disp=(q['ycm']-z['ycm'])/dy; vel=(q['vycm']-z['vycm'])/dv
    h=0.5*(z['h']+q['h']); Rphys=R*h
    eta=DT*math.sqrt(kbt/MASS)/Rphys
    mean_delta=0.5*(z['mean_delta']+q['mean_delta'])
    rows.append(dict(R_over_h=R,kBT_target=kbt,eta_T=eta,
                     paired_displacement_ratio=disp,paired_velocity_ratio=vel,
                     g0_com_speed=z['speed'],gminus_com_speed=q['speed'],
                     g0_final_kBT=z['kBT'],gminus_final_kBT=q['kBT'],
                     mean_delta_over_h=mean_delta/h,
                     g0_r90_over_R=z['r90_over_R'],gminus_r90_over_R=q['r90_over_R'],
                     g0_frac_beyond_2R=z['frac_beyond_2R'],gminus_frac_beyond_2R=q['frac_beyond_2R'],
                     mean_interface_interventions=0.5*((z['collisions']+z['overlaps'])+(q['collisions']+q['overlaps'])),
                     g0_run=z['run'],gminus_run=q['run']))

if not rows: raise SystemExit('[0493x10y-analyze] no complete g=0/-0.1 pairs found')
with OUT.open('w',newline='') as f:
    w=csv.DictWriter(f,fieldnames=list(rows[0])); w.writeheader(); w.writerows(rows)

print('===== 0493x10y CONSTANT RELATIVE THERMAL EXCURSION =====')
print(' R/h      kBT      eta_T    disp/g     vel/g    g0speed   delta/h      r90-   beyond2R-  interventions')
for r in rows:
    print(f"{r['R_over_h']:4d}  {r['kBT_target']:8.6f}  {100*r['eta_T']:7.4f}%  {r['paired_displacement_ratio']:8.4f}  {r['paired_velocity_ratio']:8.4f}  {r['g0_com_speed']:9.5f}  {r['mean_delta_over_h']:8.4f}  {r['gminus_r90_over_R']:7.4f}  {r['gminus_frac_beyond_2R']:10.3e}  {r['mean_interface_interventions']:12.1f}")
print(f'[0493x10y-analyze] wrote {OUT}')
