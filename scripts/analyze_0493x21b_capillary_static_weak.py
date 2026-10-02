#!/usr/bin/env python3
from __future__ import annotations
import argparse,csv,math,statistics
from pathlib import Path

def read(p):
    if not p.is_file(): raise SystemExit(f'[x21b] missing {p}')
    with p.open(newline='') as f: r=list(csv.DictReader(f))
    if not r: raise SystemExit(f'[x21b] empty {p}')
    return r

def fv(r,k,d=math.nan):
    try:
        x=float(r[k]); return x if math.isfinite(x) else d
    except: return d

def mean(v):
    q=[x for x in v if math.isfinite(x)]; return statistics.fmean(q) if q else math.nan

def sd(v):
    q=[x for x in v if math.isfinite(x)]; return statistics.stdev(q) if len(q)>1 else 0.

def stepmap(rr):
    o={}
    for r in rr:
        try:o[int(float(r['step']))]=r
        except:pass
    return o

def drift(t,y):
    q=[(a,b) for a,b in zip(t,y) if math.isfinite(a) and math.isfinite(b)]
    if len(q)<8:return math.inf
    t=[a for a,b in q]; y=[b for a,b in q]; ym=mean(y); s=max(abs(ym),1e-30)
    tm=mean(t); den=sum((x-tm)**2 for x in t); slope=sum((x-tm)*(z-ym) for x,z in zip(t,y))/den if den else 0
    n=max(2,len(y)//3); edge=abs(mean(y[:n])-mean(y[-n:]))/s
    return max(abs(slope)*(t[-1]-t[0])/s,edge)

def window(pa,pb):
    a=stepmap(pa); b=stepmap(pb); ss=sorted(set(a)&set(b)); out=[]
    for s in ss:
        ar,br=a[s],b[s]
        out.append(dict(step=s,time=fv(ar,'time'),Ra=fv(ar,'effectiveRadius'),Rb=fv(br,'effectiveRadius'),Aa=fv(ar,'alphaArea'),Ab=fv(br,'alphaArea'),ka=fv(ar,'curvatureMean'),ks=fv(ar,'curvatureStd'),pa=fv(ar,'measuredPressureJump'),pb=fv(br,'measuredPressureJump')))
    if len(out)<40: raise SystemExit(f'[x21b] too few common samples {len(out)}')
    # Search earliest tail with stable geometry in BOTH runs. Pressure is not used to define the plateau at weak sigma.
    best=None
    for frac in (.30,.40,.50,.60):
        q=out[int(frac*len(out)):]
        if len(q)<30: continue
        t=[r['time'] for r in q]
        m=dict(Ra=drift(t,[r['Ra'] for r in q]),Rb=drift(t,[r['Rb'] for r in q]),Aa=drift(t,[r['Aa'] for r in q]),Ab=drift(t,[r['Ab'] for r in q]),ka=drift(t,[r['ka'] for r in q]))
        best=(q,m)
        if max(m['Ra'],m['Rb'])<=.01 and max(m['Aa'],m['Ab'])<=.02 and m['ka']<=.05: return True,q,m
    return False,*best

def limiter(run,s0,s1):
    p=run/'output/cuda_surface_tension_limiter_0493x9r.csv'
    if not p.is_file(): return math.nan
    vals=[]
    for r in read(p):
        try:s=int(float(r['step']))
        except:continue
        if s0<=s<=s1: vals.append(fv(r,'clipFraction',0))
    return max(vals) if vals else math.nan

def vel(run,s0,s1):
    p=run/'output/cuda_static_drop_velocity_0493x9e.csv'; vals=[]
    if not p.is_file(): return {}
    for r in read(p):
        try:s=int(float(r['step']))
        except:continue
        if s0<=s<=s1: vals.append(r)
    if not vals:return {}
    return dict(interfaceSpeedRms=mean(fv(r,'interfaceSpeedRms') for r in vals),interfaceFluctuationRms=mean(fv(r,'interfaceFluctuationRms') for r in vals),interfaceSpeedMax=max(fv(r,'interfaceSpeedMax') for r in vals),liquidMeanVx=mean(fv(r,'liquidMeanVx') for r in vals),liquidMeanVy=mean(fv(r,'liquidMeanVy') for r in vals))

def main():
    ap=argparse.ArgumentParser(); ap.add_argument('--campaign-root',type=Path); ap.add_argument('--self-test',action='store_true'); a=ap.parse_args()
    if a.self_test:
        assert drift(list(range(100)),[2+1e-5*math.sin(i) for i in range(100)])<1e-3; print('[x21b] self-test PASS'); return
    root=a.campaign_root; man=read(root/'manifest_0493x12yl.csv'); act=[r for r in man if float(r['sigma'])>0]; bas=[r for r in man if abs(float(r['sigma']))<1e-12]
    if len(act)!=1 or len(bas)!=1: raise SystemExit('[x21b] need one active and one baseline')
    ar,br=act[0],bas[0]; sig=float(ar['sigma_declared']); rc=float(ar['r_cells']);
    if abs(sig-120)>1e-9 or abs(rc-64)>1e-9: raise SystemExit(f'[x21b] unexpected sigma={sig} R/h={rc}')
    ra=Path(ar['run_dir']); rb=Path(br['run_dir']); pa=read(ra/'output/cuda_static_drop_pressure_0493x9e.csv'); pb=read(rb/'output/cuda_static_drop_pressure_0493x9e.csv')
    ok,q,d=window(pa,pb); s0=q[0]['step']; s1=q[-1]['step']; n=len(q)
    Rea=mean(r['Ra'] for r in q); Reb=mean(r['Rb'] for r in q); k=mean(r['ka'] for r in q); kth=1/Rea; kerr=abs(abs(k)-kth)/kth
    pA=[r['pa'] for r in q]; pB=[r['pb'] for r in q]; dp=mean(pA)-mean(pB); sem=math.sqrt(sd(pA)**2/n+sd(pB)**2/n); snr=abs(dp)/sem if sem>0 else math.inf
    sigma_eff=dp/k if abs(k)>0 else math.nan; ratio=sigma_eff/sig if sig else math.nan
    geom_mismatch=abs(Rea-Reb)/max(Rea,1e-30); clip=limiter(ra,s0,s1); v=vel(ra,s0,s1)
    hard=[]; review=[]
    if not ok: hard.append('no_geometry_plateau')
    if kerr>.20: hard.append('curvature_error_gt20pct')
    elif kerr>.10: review.append('curvature_error_gt10pct')
    if geom_mismatch>.03: hard.append('active_baseline_radius_mismatch_gt3pct')
    elif geom_mismatch>.015: review.append('active_baseline_radius_mismatch_gt1p5pct')
    if math.isfinite(clip) and clip>.01: hard.append('curvature_limiter_gt1pct')
    elif math.isfinite(clip) and clip>.001: review.append('curvature_limiter_gt0p1pct')
    if snr<3: hard.append('pressure_increment_snr_lt3')
    elif snr<5: review.append('pressure_increment_snr_lt5')
    if math.isfinite(ratio):
        er=abs(ratio-1)
        if er>.30: hard.append('sigma_eff_error_gt30pct')
        elif er>.15: review.append('sigma_eff_error_gt15pct')
    else: hard.append('sigma_eff_nonfinite')
    status='INVALID' if hard else ('REVIEW' if review else 'PASS'); decision='READY_FOR_RESOLVED_RADIUS_SWEEP' if status=='PASS' else ('REVIEW_BEFORE_SWEEP' if status=='REVIEW' else 'STOP_DO_NOT_SWEEP')
    out=root/'pilot_analysis'; out.mkdir(parents=True,exist_ok=True)
    fields=dict(status=status,decision=decision,sigma_target=sig,R_cells=rc,R_eff_active=Rea,R_eff_baseline=Reb,active_baseline_radius_rel_mismatch=geom_mismatch,kappa_num=k,kappa_theory=kth,kappa_rel_error=kerr,delta_p_capillary=dp,delta_p_sem=sem,delta_p_snr=snr,sigma_eff=sigma_eff,sigma_eff_over_sigma=ratio,max_clip_fraction=clip,plateau_found=int(ok),plateau_start_step=s0,plateau_end_step=s1,plateau_samples=n,drift_R_active=d['Ra'],drift_R_baseline=d['Rb'],drift_area_active=d['Aa'],drift_area_baseline=d['Ab'],drift_kappa=d['ka'],hard_flags=';'.join(hard),review_flags=';'.join(review),**v)
    with (out/'capillary_pilot_weak_0493x21b.csv').open('w',newline='') as f: w=csv.DictWriter(f,fieldnames=fields); w.writeheader(); w.writerow(fields)
    lines=['===== 0493x21b WEAK STATIC CAPILLARY PILOT =====',f'status={status}',f'decision={decision}',f'plateau={ok} steps={s0}..{s1} samples={n}',f'R_eff_active={Rea:.12g} R_eff_baseline={Reb:.12g} radiusMismatch={geom_mismatch:.6g}',f'kappa_num={k:.12g} kappa_th={kth:.12g} E_kappa={kerr:.6g}',f'deltaP={dp:.12g} SEM={sem:.12g} SNR={snr:.6g}',f'sigma_target={sig:.12g} sigma_eff={sigma_eff:.12g} sigma_eff/sigma={ratio:.9g}',f'curvatureLimiterMaxClip={clip:.6g}',f'hardFlags={";".join(hard) if hard else "NONE"}',f'reviewFlags={";".join(review) if review else "NONE"}','note=instantaneous interface velocity RMS is reported but NOT gated because thermal MPCD fluctuations contaminate the usual spurious-current metric.']
    (out/'capillary_pilot_weak_decision_0493x21b.txt').write_text('\n'.join(lines)+'\n'); print('\n'.join(lines))
if __name__=='__main__': main()
