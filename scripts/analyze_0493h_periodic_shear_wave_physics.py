#!/usr/bin/env python3
"""0493h periodic shear-wave physical comparison: SRC versus SRC+resampling."""
from __future__ import annotations
import argparse, csv, json, math, re, struct, sys
from dataclasses import dataclass, asdict
from pathlib import Path

@dataclass
class Metric:
    step:int; time:float; fluid_particles:int; total_mass:float; px:float; py:float
    mean_vx:float; mean_vy:float; kinetic:float; wave_sin:float; wave_cos:float
    amplitude:float; phase:float; residual_energy:float; occupancy_mean:float
    occupancy_variance:float; occupancy_min:int; occupancy_max:int
    particle_mass_min:float; particle_mass_max:float

def args_parse():
    p=argparse.ArgumentParser()
    p.add_argument('--root',type=Path,required=True); p.add_argument('--nx',type=int,required=True); p.add_argument('--ny',type=int,required=True)
    p.add_argument('--gamma',type=int,required=True); p.add_argument('--dt',type=float,required=True); p.add_argument('--steps',type=int,required=True)
    p.add_argument('--dump-every',type=int,required=True); p.add_argument('--wave-mode',type=int,required=True); p.add_argument('--requested-amplitude',type=float,required=True)
    p.add_argument('--thermal-amplitude',type=float,required=True); p.add_argument('--seeds',type=int,nargs='+',required=True)
    p.add_argument('--mass-rel-tol',type=float,default=2e-10); p.add_argument('--momentum-abs-tol',type=float,default=2e-9)
    p.add_argument('--energy-rel-tol',type=float,default=2e-7); p.add_argument('--fit-r2-min',type=float,default=0.80)
    p.add_argument('--per-seed-nu-rel-tol',type=float,default=0.25); p.add_argument('--mean-nu-rel-tol',type=float,default=0.18)
    p.add_argument('--curve-rms-tol',type=float,default=0.12); p.add_argument('--endpoint-rel-tol',type=float,default=0.18)
    p.add_argument('--phase-difference-tol',type=float,default=0.20)
    return p.parse_args()

def read_state(path:Path):
    data=path.read_bytes(); off=0
    magic=data[:16].rstrip(b'\0'); off=16
    if magic!=b'SRCMPCD_STATE': raise ValueError(f'invalid state magic: {path}')
    fmt='<IIIIQIIII'; size=struct.calcsize(fmt)
    version,endian,dim,scalar,n,typeflag,massflag,reserved,roleflag=struct.unpack_from(fmt,data,off); off+=size
    if (version,endian,dim,scalar,typeflag,massflag,roleflag)!=(2,0x01020304,2,1,1,1,4):
        raise ValueError(f'unsupported header in {path}')
    off+=8*int(reserved); n=int(n)
    def arr(code):
        nonlocal off
        s=struct.calcsize(f'<{n}{code}'); out=list(struct.unpack_from(f'<{n}{code}',data,off)); off+=s; return out
    return {'x':arr('d'),'y':arr('d'),'vx':arr('d'),'vy':arr('d'),'type':arr('I'),'mass':arr('d'),'role':arr('B')}

def variance(v):
    if not v:return 0.0
    m=math.fsum(v)/len(v); return math.fsum((x-m)**2 for x in v)/len(v)

def metric(path:Path,step:int,a):
    s=read_state(path); ids=[i for i,r in enumerate(s['role']) if int(r)==1]
    if not ids: raise ValueError(f'no fluid particles in {path}')
    if any(int(s['type'][i])!=1 for i in ids): raise ValueError(f'non-type1 fluid particle in {path}')
    M=math.fsum(s['mass'][i] for i in ids)
    px=math.fsum(s['mass'][i]*s['vx'][i] for i in ids); py=math.fsum(s['mass'][i]*s['vy'][i] for i in ids)
    ux=px/M; uy=py/M; k=2.0*math.pi*a.wave_mode
    asin=2.0*math.fsum(s['mass'][i]*(s['vx'][i]-ux)*math.sin(k*s['y'][i]) for i in ids)/M
    acos=2.0*math.fsum(s['mass'][i]*(s['vx'][i]-ux)*math.cos(k*s['y'][i]) for i in ids)/M
    amp=math.hypot(asin,acos); phase=math.atan2(acos,asin)
    kinetic=0.5*math.fsum(s['mass'][i]*(s['vx'][i]**2+s['vy'][i]**2) for i in ids)
    residual=0.5*math.fsum(s['mass'][i]*((s['vx'][i]-ux-asin*math.sin(k*s['y'][i])-acos*math.cos(k*s['y'][i]))**2+(s['vy'][i]-uy)**2) for i in ids)
    counts=[0]*(a.nx*a.ny)
    for i in ids:
        ix=min(a.nx-1,max(0,int(math.floor((s['x'][i]%1.0)*a.nx))))
        iy=min(a.ny-1,max(0,int(math.floor((s['y'][i]%1.0)*a.ny))))
        counts[iy*a.nx+ix]+=1
    masses=[s['mass'][i] for i in ids]
    return Metric(step,step*a.dt,len(ids),M,px,py,ux,uy,kinetic,asin,acos,amp,phase,residual,
                  math.fsum(counts)/len(counts),variance(counts),min(counts),max(counts),min(masses),max(masses))

def state_series(case:Path,a):
    pat=re.compile(r'state_step_(\d+)\.smpcd$'); found=[]
    for p in sorted((case/'output').glob('state_step_*.smpcd')):
        m=pat.search(p.name)
        if m: found.append(metric(p,int(m.group(1)),a))
    expected=set(range(0,a.steps+1,a.dump_every)); got={m.step for m in found}
    missing=sorted(expected-got)
    if missing: raise ValueError(f'missing state dumps in {case}: {missing[:10]}')
    return found

def fit_decay(series,a):
    init=series[0].amplitude
    usable=[m for m in series if m.step>=a.dump_every and m.amplitude>max(1e-12,0.08*init)]
    if len(usable)<5: return {'slope':float('nan'),'nu':float('nan'),'r2':float('nan'),'points':len(usable)}
    xs=[m.time for m in usable]; ys=[math.log(m.amplitude/init) for m in usable]
    xm=math.fsum(xs)/len(xs); ym=math.fsum(ys)/len(ys)
    sxx=math.fsum((x-xm)**2 for x in xs); sxy=math.fsum((x-xm)*(y-ym) for x,y in zip(xs,ys))
    slope=sxy/sxx; intercept=ym-slope*xm
    ssr=math.fsum((y-(intercept+slope*x))**2 for x,y in zip(xs,ys)); sst=math.fsum((y-ym)**2 for y in ys)
    r2=1.0-ssr/sst if sst>0 else 1.0
    nu=-slope/(2.0*math.pi*a.wave_mode)**2
    return {'slope':slope,'nu':nu,'r2':r2,'points':len(usable),'intercept':intercept}

def read_csv(path):
    if not path.is_file(): return []
    with path.open(newline='') as f:return list(csv.DictReader(f))
def sumi(rows,key):
    total=0
    for r in rows:
        try: total+=int(float(r.get(key,'0') or 0))
        except: pass
    return total
def maxi(rows,key):
    vals=[]
    for r in rows:
        try: vals.append(int(float(r.get(key,'0') or 0)))
        except: pass
    return max(vals,default=0)
def maxf(rows,key):
    vals=[]
    for r in rows:
        try: vals.append(abs(float(r.get(key,'0') or 0)))
        except: pass
    return max(vals,default=0.0)

def main():
    a=args_parse(); checks=[]; summaries=[]; all_series={}
    def check(name,ok,detail):
        checks.append((name,bool(ok),detail)); print(f'[0493h-audit] {name}={"PASS" if ok else "FAIL"} {detail}')
    for seed in a.seeds:
        key=str(seed); all_series[key]={}
        for label,dirname in [('src','00_src'),('resampling','01_src_resampling')]:
            case=a.root/f'seed_{seed}'/dirname; series=state_series(case,a); fit=fit_decay(series,a); all_series[key][label]=series
            initial=series[0]; max_mass=max(abs(m.total_mass-initial.total_mass)/max(1.0,abs(initial.total_mass)) for m in series)
            max_px=max(abs(m.px-initial.px) for m in series); max_py=max(abs(m.py-initial.py) for m in series)
            max_energy=max(abs(m.kinetic-initial.kinetic)/max(1.0,abs(initial.kinetic)) for m in series)
            check(f'seed{seed}_{label}_initial_amplitude',abs(initial.amplitude-a.requested_amplitude)<=0.02*a.requested_amplitude,
                  f'measured={initial.amplitude:.8g} requested={a.requested_amplitude:.8g}')
            check(f'seed{seed}_{label}_mass',max_mass<=a.mass_rel_tol,f'maxRel={max_mass:.3e}')
            check(f'seed{seed}_{label}_momentum',max(max_px,max_py)<=a.momentum_abs_tol,f'maxPx={max_px:.3e} maxPy={max_py:.3e}')
            check(f'seed{seed}_{label}_kinetic_energy',max_energy<=a.energy_rel_tol,f'maxRel={max_energy:.3e}')
            check(f'seed{seed}_{label}_decay_positive',math.isfinite(fit['nu']) and fit['nu']>0,f"nu={fit['nu']:.6g} slope={fit['slope']:.6g}")
            check(f'seed{seed}_{label}_fit_quality',math.isfinite(fit['r2']) and fit['r2']>=a.fit_r2_min,f"r2={fit['r2']:.6g} points={fit['points']}")
            summaries.append({'seed':seed,'mode':label,'initial_amplitude':initial.amplitude,'final_amplitude':series[-1].amplitude,
                              'final_ratio':series[-1].amplitude/initial.amplitude,'nu_eff':fit['nu'],'fit_r2':fit['r2'],
                              'mass_drift_max_rel':max_mass,'px_drift_max_abs':max_px,'py_drift_max_abs':max_py,
                              'kinetic_drift_max_rel':max_energy,'initial_particles':initial.fluid_particles,'final_particles':series[-1].fluid_particles,
                              'initial_occ_var':initial.occupancy_variance,'final_occ_var':series[-1].occupancy_variance})
        src=all_series[key]['src']; rsp=all_series[key]['resampling']; fs=fit_decay(src,a); fr=fit_decay(rsp,a)
        bys={m.step:m for m in src}; byr={m.step:m for m in rsp}; common=sorted(set(bys)&set(byr)); A0=src[0].amplitude
        rms=math.sqrt(math.fsum(((byr[s].amplitude-bys[s].amplitude)/A0)**2 for s in common)/len(common))
        endrel=abs(rsp[-1].amplitude-src[-1].amplitude)/max(1e-12,0.5*(rsp[-1].amplitude+src[-1].amplitude))
        nurel=abs(fr['nu']-fs['nu'])/max(1e-12,0.5*(abs(fr['nu'])+abs(fs['nu'])))
        phased=max(abs(math.atan2(math.sin(byr[s].phase-bys[s].phase),math.cos(byr[s].phase-bys[s].phase))) for s in common)
        check(f'seed{seed}_curve_rms',rms<=a.curve_rms_tol,f'rms/A0={rms:.6g}')
        check(f'seed{seed}_endpoint_amplitude',endrel<=a.endpoint_rel_tol,f'rel={endrel:.6g} src={src[-1].amplitude:.6g} resamp={rsp[-1].amplitude:.6g}')
        check(f'seed{seed}_nu_agreement',nurel<=a.per_seed_nu_rel_tol,f'rel={nurel:.6g} src={fs["nu"]:.6g} resamp={fr["nu"]:.6g}')
        check(f'seed{seed}_phase_agreement',phased<=a.phase_difference_tol,f'maxRad={phased:.6g}')
        out=a.root/f'seed_{seed}'/'01_src_resampling'/'output'
        guard=read_csv(out/'cuda_resampling_population_guard_0297.csv'); plan=read_csv(out/'cuda_species_transfer_plan_0490k.csv')
        fast=read_csv(out/'cuda_species_resident_fast_path_0490m.csv'); close=read_csv(out/'cuda_species_mass_closure_0490i.csv')
        maint=read_csv(out/'cuda_species_resident_maintenance_0490n.csv')
        splits=sumi(guard,'speciesDirectedSplits0490j'); merges=sumi(guard,'speciesDirectedMerges0490j'); entries=sumi(plan,'gpuPlanEntries'); ops=sumi(fast,'operations')
        check(f'seed{seed}_resampling_diagnostics',bool(guard) and bool(plan) and bool(fast),f'guardRows={len(guard)} planRows={len(plan)} fastRows={len(fast)}')
        check(f'seed{seed}_resampling_activity',(splits+merges+entries+ops)>0,f'splits={splits} merges={merges} entries={entries} operations={ops}')
        check(f'seed{seed}_resampling_invalid_zero',maxi(fast,'invalidOperations')==0 and maxi(fast,'donorTypeGroupUnderfills')==0,
              f"invalid={maxi(fast,'invalidOperations')} underfills={maxi(fast,'donorTypeGroupUnderfills')}")
        check(f'seed{seed}_species_closure',maxi(close,'invalidTypeCount')==0 and maxf(close,'maxSpeciesMassRelResidual')<=a.mass_rel_tol,
              f"invalidType={maxi(close,'invalidTypeCount')} residual={maxf(close,'maxSpeciesMassRelResidual'):.3e}")
        check(f'seed{seed}_species_kinetic_closure',
              maxi(close,'speciesKineticConservativeBalance')==1 and
              maxi(close,'infeasibleKineticCells')==0 and
              maxf(close,'maxKineticEnergyRelResidual')<=a.mass_rel_tol,
              f"active={maxi(close,'speciesKineticConservativeBalance')} "
              f"infeasible={maxi(close,'infeasibleKineticCells')} "
              f"residual={maxf(close,'maxKineticEnergyRelResidual'):.3e}")
        check(f'seed{seed}_pool_integrity',all(maxi(maint,c)==0 for c in ('activePrefixViolations','duplicateFreeSlots','activeAndFreeSlots','invalidRoleSlots')),
              ' '.join(f'{c}={maxi(maint,c)}' for c in ('activePrefixViolations','duplicateFreeSlots','activeAndFreeSlots','invalidRoleSlots')))
    nus={mode:[s['nu_eff'] for s in summaries if s['mode']==mode] for mode in ('src','resampling')}
    mean_src=math.fsum(nus['src'])/len(nus['src']); mean_rsp=math.fsum(nus['resampling'])/len(nus['resampling'])
    mean_rel=abs(mean_rsp-mean_src)/max(1e-12,0.5*(abs(mean_rsp)+abs(mean_src)))
    check('ensemble_mean_nu_agreement',mean_rel<=a.mean_nu_rel_tol,f'rel={mean_rel:.6g} src={mean_src:.6g} resamp={mean_rsp:.6g}')
    # Write time series and summaries.
    with (a.root/'shear_wave_0493h_timeseries.csv').open('w',newline='') as f:
        fields=['seed','mode']+list(Metric.__dataclass_fields__); w=csv.DictWriter(f,fieldnames=fields); w.writeheader()
        for seed in a.seeds:
            for mode in ('src','resampling'):
                for m in all_series[str(seed)][mode]: w.writerow({'seed':seed,'mode':mode,**asdict(m)})
    with (a.root/'shear_wave_0493h_summary.csv').open('w',newline='') as f:
        w=csv.DictWriter(f,fieldnames=list(summaries[0])); w.writeheader(); w.writerows(summaries)
    with (a.root/'physics_0493h_checks.csv').open('w',newline='') as f:
        w=csv.writer(f); w.writerow(['check','status','detail']); w.writerows((n,'PASS' if ok else 'FAIL',d) for n,ok,d in checks)
    status='PASS' if all(ok for _,ok,_ in checks) else 'FAIL'
    report={'status':status,'parameters':vars(a)|{'root':str(a.root)},'summaries':summaries,'ensemble':{'src_mean_nu':mean_src,'resampling_mean_nu':mean_rsp,'relative_difference':mean_rel},
            'failed_checks':[n for n,ok,_ in checks if not ok]}
    (a.root/'physics_0493h.json').write_text(json.dumps(report,indent=2,sort_keys=True)+'\n')
    md=['# 0493h periodic shear-wave physics','',f'**Status: {status}**','',f'- SRC mean effective viscosity: `{mean_src:.9g}`',f'- resampling mean effective viscosity: `{mean_rsp:.9g}`',f'- relative difference: `{mean_rel:.6g}`','', '## Runs','', '| seed | mode | A(0) | A(end)/A(0) | nu_eff | R2 |', '|---:|---|---:|---:|---:|---:|']
    for s in summaries: md.append(f"| {s['seed']} | {s['mode']} | {s['initial_amplitude']:.6g} | {s['final_ratio']:.6g} | {s['nu_eff']:.6g} | {s['fit_r2']:.6g} |")
    if report['failed_checks']: md+=['','## Failed checks','']+[f'- `{x}`' for x in report['failed_checks']]
    (a.root/'physics_0493h.md').write_text('\n'.join(md)+'\n')
    print(f'[0493h-audit] ensemble srcNu={mean_src:.6g} resamplingNu={mean_rsp:.6g} relative={mean_rel:.6g} status={status}')
    print(f'[0493h-audit] json={a.root/"physics_0493h.json"}')
    print(f'[0493h-audit] markdown={a.root/"physics_0493h.md"}')
    return 0 if status=='PASS' else 2
if __name__=='__main__': raise SystemExit(main())
