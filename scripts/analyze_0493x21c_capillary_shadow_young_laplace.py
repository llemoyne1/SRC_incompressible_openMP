#!/usr/bin/env python3
from __future__ import annotations
import argparse,csv,hashlib,math,re,statistics
from collections import defaultdict
from pathlib import Path


def read_csv(path:Path):
    if not path.is_file(): raise SystemExit(f'[x21c] missing {path}')
    with path.open(newline='') as f: rows=list(csv.DictReader(f))
    if not rows: raise SystemExit(f'[x21c] empty {path}')
    return rows

def f(row,key,default=math.nan):
    try:
        v=float(row[key]); return v if math.isfinite(v) else default
    except Exception:return default

def avg(xs):
    q=[x for x in xs if math.isfinite(x)]; return statistics.fmean(q) if q else math.nan

def sd(xs):
    q=[x for x in xs if math.isfinite(x)]; return statistics.stdev(q) if len(q)>1 else 0.0

def rel_drift(rows,key):
    q=[(f(r,'time'),f(r,key)) for r in rows]
    q=[z for z in q if math.isfinite(z[0]) and math.isfinite(z[1])]
    if len(q)<12:return math.inf
    t=[z[0] for z in q]; y=[z[1] for z in q]; ym=avg(y); scale=max(abs(ym),1e-30)
    tm=avg(t); den=sum((x-tm)**2 for x in t)
    slope=sum((x-tm)*(v-ym) for x,v in zip(t,y))/den if den else 0.0
    n=max(3,len(y)//4)
    edge=abs(avg(y[:n])-avg(y[-n:]))/scale
    return max(abs(slope)*(t[-1]-t[0])/scale,edge)

def parse_state_step(path:Path):
    m=re.search(r'state_step_(\d+)\.smpcd$',path.name)
    return int(m.group(1)) if m else None

def closest_row(rows,step):
    candidates=[]
    for r in rows:
        try:s=int(float(r['step']))
        except Exception:continue
        candidates.append((abs(s-step),s,r))
    if not candidates:return None
    candidates.sort(key=lambda z:(z[0],z[1])); return candidates[0][2]

def detect_active_plateau(rows):
    # Geometry only. Pressure is deliberately not used to define the plateau.
    best=None
    for frac in (0.35,0.45,0.55,0.65,0.75):
        q=rows[int(frac*len(rows)):]
        if len(q)<30:continue
        dR=rel_drift(q,'effectiveRadius'); dA=rel_drift(q,'alphaArea')
        best=(q,dR,dA)
        if dR<=0.01 and dA<=0.02:return True,q,dR,dA
    if best is None:raise SystemExit('[x21c] insufficient active x9e rows')
    return False,*best

def select_checkpoints(root:Path,count:int):
    active=root/'active'; x9e=read_csv(active/'output/cuda_static_drop_pressure_0493x9e.csv')
    ok,q,dR,dA=detect_active_plateau(x9e)
    start=int(float(q[0]['step'])); end=int(float(q[-1]['step']))
    states=[]
    for p in sorted((active/'output').glob('state_step_*.smpcd')):
        s=parse_state_step(p)
        if s is not None and start<=s<=end:states.append((s,p))
    if len(states)<count:
        raise SystemExit(f'[x21c] only {len(states)} state dumps inside plateau {start}..{end}; need {count}')
    # Spread checkpoint selection across the accepted plateau, including its late end.
    idx=[]
    if count==1:idx=[len(states)-1]
    else:
        for j in range(count): idx.append(round(j*(len(states)-1)/(count-1)))
    chosen=[]; seen=set()
    for i in idx:
        if i not in seen:chosen.append(states[i]); seen.add(i)
    while len(chosen)<count:
        for item in reversed(states):
            if item not in chosen:chosen.append(item)
            if len(chosen)==count:break
    chosen=sorted(chosen[:count])
    out=root/'analysis'; out.mkdir(parents=True,exist_ok=True)
    path=out/'selected_checkpoints_0493x21c.csv'
    fields=['checkpoint_step','state_path','state_sha256','effectiveRadius','alphaArea','curvatureMean','measuredPressureJump','plateau_start_step','plateau_end_step','plateau_found','drift_R','drift_area']
    with path.open('w',newline='') as fh:
        w=csv.DictWriter(fh,fieldnames=fields); w.writeheader()
        for s,p in chosen:
            r=closest_row(x9e,s)
            sha=hashlib.sha256(p.read_bytes()).hexdigest()
            w.writerow(dict(checkpoint_step=s,state_path=str(p),state_sha256=sha,effectiveRadius=f(r,'effectiveRadius'),alphaArea=f(r,'alphaArea'),curvatureMean=f(r,'curvatureMean'),measuredPressureJump=f(r,'measuredPressureJump'),plateau_start_step=start,plateau_end_step=end,plateau_found=int(ok),drift_R=dR,drift_area=dA))
    print('===== 0493x21c ACTIVE CHECKPOINT SELECTION =====')
    print(f'plateauFound={ok} steps={start}..{end} driftR={dR:.6g} driftArea={dA:.6g}')
    print('selected='+' '.join(str(s) for s,_ in chosen))
    print(f'file={path}')
    if not ok:
        raise SystemExit('[x21c] active geometry did not satisfy plateau gate; shadows not justified')

def first_post(rows):
    vals=[]
    for r in rows:
        try:s=int(float(r['step']))
        except Exception:continue
        if s>0:vals.append((s,r))
    if not vals:
        # Some builds may emit only final row with step zero after restart; reject rather than guess.
        raise RuntimeError('no positive-step x9e diagnostic row')
    vals.sort(key=lambda z:z[0]); return vals[0]

def max_clip(run:Path):
    p=run/'output/cuda_surface_tension_limiter_0493x9r.csv'
    if not p.is_file():return math.nan
    vals=[]
    for r in read_csv(p): vals.append(f(r,'clipFraction'))
    return max((x for x in vals if math.isfinite(x)),default=math.nan)

def final_analysis(root:Path,sigma:float,radius_cells:float,expected_reps:int):
    sel=read_csv(root/'analysis/selected_checkpoints_0493x21c.csv')
    manifest=read_csv(root/'manifest_shadow_pairs_0493x21c.csv')
    selected={int(float(r['checkpoint_step'])):r for r in sel}
    groups=defaultdict(dict)
    for r in manifest:
        cp=int(float(r['checkpoint_step'])); rep=int(float(r['replicate'])); role=r['role']
        groups[(cp,rep)][role]=r
    details=[]; hard=[]; review=[]
    for cp in sorted(selected):
        reps=[k for k in groups if k[0]==cp]
        if len(reps)!=expected_reps:hard.append(f'checkpoint_{cp}_replicate_count_{len(reps)}_expected_{expected_reps}')
        for key in sorted(reps):
            g=groups[key]
            if set(g)!={'active','sigma0'}:
                hard.append(f'checkpoint_{cp}_rep_{key[1]}_missing_role'); continue
            a,z=g['active'],g['sigma0']
            if a['input_state_sha256']!=z['input_state_sha256']:
                hard.append(f'checkpoint_{cp}_rep_{key[1]}_input_hash_mismatch'); continue
            if int(float(a['seed']))!=int(float(z['seed'])):
                hard.append(f'checkpoint_{cp}_rep_{key[1]}_seed_mismatch'); continue
            arun=Path(a['run_dir']); zrun=Path(z['run_dir'])
            try:
                sa,ra=first_post(read_csv(arun/'output/cuda_static_drop_pressure_0493x9e.csv'))
                sz,rz=first_post(read_csv(zrun/'output/cuda_static_drop_pressure_0493x9e.csv'))
            except RuntimeError as e:
                hard.append(f'checkpoint_{cp}_rep_{key[1]}_{e}'); continue
            if sa!=sz:hard.append(f'checkpoint_{cp}_rep_{key[1]}_first_step_mismatch_{sa}_{sz}')
            pa=f(ra,'measuredPressureJump'); p0=f(rz,'measuredPressureJump'); k=f(ra,'curvatureMean')
            Rea=f(ra,'effectiveRadius'); Rez=f(rz,'effectiveRadius'); Aa=f(ra,'alphaArea'); Az=f(rz,'alphaArea')
            dp=pa-p0; gain=dp/(sigma*k) if math.isfinite(k) and abs(k)>1e-30 else math.nan
            kth=1.0/Rea if Rea>0 else math.nan
            kerr=abs(abs(k)-kth)/kth if kth>0 else math.nan
            rmis=abs(Rea-Rez)/max(abs(Rea),1e-30)
            amis=abs(Aa-Az)/max(abs(Aa),1e-30)
            details.append(dict(checkpoint_step=cp,replicate=key[1],seed=int(float(a['seed'])),first_probe_step=sa,input_state_sha256=a['input_state_sha256'],pressure_active=pa,pressure_sigma0=p0,delta_p=dp,kappa_active=k,kappa_theory=kth,kappa_rel_error=kerr,effectiveRadius_active=Rea,effectiveRadius_sigma0=Rez,radius_rel_mismatch=rmis,alphaArea_active=Aa,alphaArea_sigma0=Az,area_rel_mismatch=amis,gain= gain,sigma_eff=sigma*gain if math.isfinite(gain) else math.nan,active_clip_fraction=max_clip(arun)))
    if not details:raise SystemExit('[x21c] no valid shadow pairs')
    out=root/'analysis'; out.mkdir(parents=True,exist_ok=True)
    dfields=list(details[0])
    with (out/'shadow_pair_realizations_0493x21c.csv').open('w',newline='') as fh:
        w=csv.DictWriter(fh,fieldnames=dfields); w.writeheader(); w.writerows(details)

    checkpoint_rows=[]
    for cp in sorted(selected):
        q=[r for r in details if r['checkpoint_step']==cp]
        gains=[r['gain'] for r in q]; dps=[r['delta_p'] for r in q]
        gm=avg(gains); gs=sd(gains); gcv=gs/max(abs(gm),1e-30) if math.isfinite(gm) else math.nan
        checkpoint_rows.append(dict(checkpoint_step=cp,pairs=len(q),gain_mean=gm,gain_std=gs,gain_cv=gcv,sigma_eff_mean=sigma*gm,delta_p_mean=avg(dps),delta_p_std=sd(dps),kappa_mean=avg(r['kappa_active'] for r in q),kappa_rel_error_mean=avg(r['kappa_rel_error'] for r in q),radius_mismatch_max=max(r['radius_rel_mismatch'] for r in q),area_mismatch_max=max(r['area_rel_mismatch'] for r in q),clip_fraction_max=max((r['active_clip_fraction'] for r in q if math.isfinite(r['active_clip_fraction'])),default=math.nan)))
    cfields=list(checkpoint_rows[0])
    with (out/'shadow_checkpoint_summary_0493x21c.csv').open('w',newline='') as fh:
        w=csv.DictWriter(fh,fieldnames=cfields); w.writeheader(); w.writerows(checkpoint_rows)

    gains=[r['gain'] for r in details]; gm=avg(gains); gs=sd(gains); gcv=gs/max(abs(gm),1e-30)
    cpmeans=[r['gain_mean'] for r in checkpoint_rows]; cpspread=sd(cpmeans)/max(abs(avg(cpmeans)),1e-30) if len(cpmeans)>1 else 0.0
    kerr=avg(r['kappa_rel_error'] for r in details); rmis=max(r['radius_rel_mismatch'] for r in details); amis=max(r['area_rel_mismatch'] for r in details)
    maxclip=max((r['active_clip_fraction'] for r in details if math.isfinite(r['active_clip_fraction'])),default=math.nan)
    plateau_ok=all(int(float(r['plateau_found']))==1 for r in sel)
    expected_pairs=len(selected)*expected_reps
    if len(details)!=expected_pairs:hard.append(f'valid_pair_count_{len(details)}_expected_{expected_pairs}')
    if not plateau_ok:hard.append('active_plateau_not_found')
    if rmis>0.005:hard.append('one_step_radius_mismatch_gt0p5pct')
    if amis>0.010:hard.append('one_step_area_mismatch_gt1pct')
    if math.isfinite(kerr):
        if kerr>0.25:hard.append('mean_curvature_error_gt25pct')
        elif kerr>0.15:review.append('mean_curvature_error_gt15pct')
    else:hard.append('curvature_error_nonfinite')
    if not math.isfinite(gm):hard.append('gain_nonfinite')
    else:
        e=abs(gm-1.0)
        if e>0.25:hard.append('mean_gain_error_gt25pct')
        elif e>0.10:review.append('mean_gain_error_gt10pct')
    if gcv>0.30:hard.append('paired_gain_cv_gt30pct')
    elif gcv>0.15:review.append('paired_gain_cv_gt15pct')
    if cpspread>0.20:hard.append('checkpoint_gain_spread_gt20pct')
    elif cpspread>0.10:review.append('checkpoint_gain_spread_gt10pct')
    # Clipping is diagnostic only unless it becomes grossly dominant. The project
    # history shows that local |kappa| noise/limiting cannot by itself define sigma_eff.
    if math.isfinite(maxclip) and maxclip>0.10:hard.append('curvature_limiter_gt10pct')
    elif math.isfinite(maxclip) and maxclip>0.03:review.append('curvature_limiter_gt3pct_diagnostic')

    status='INVALID' if hard else ('REVIEW' if review else 'PASS')
    decision={'PASS':'READY_FOR_RESOLVED_RADIUS_SWEEP','REVIEW':'REVIEW_BEFORE_SWEEP','INVALID':'STOP_DO_NOT_SWEEP'}[status]
    lines=[
      '===== 0493x21c CAPILLARY SHADOW YOUNG-LAPLACE =====',
      f'status={status}',f'decision={decision}',
      f'protocol=active stable drop + same-checkpoint paired {sigma:g}/0 shadows; primary observable is first post-restart sample',
      f'sigmaTarget={sigma:.12g} radiusCells={radius_cells:.12g}',
      f'checkpoints={len(selected)} pairs={len(details)} expectedPairs={expected_pairs}',
      f'gainMean={gm:.12g} gainStd={gs:.12g} gainCV={gcv:.6g}',
      f'sigmaEff={sigma*gm:.12g} checkpointGainRelSpread={cpspread:.6g}',
      f'meanCurvatureRelError={kerr:.6g} maxOneStepRadiusMismatch={rmis:.6g} maxOneStepAreaMismatch={amis:.6g}',
      f'maxActiveClipFraction={maxclip:.6g}',
      f'hardFlags={";".join(hard) if hard else "NONE"}',
      f'reviewFlags={";".join(review) if review else "NONE"}',
      'note=sigma0 is never interpreted as a stationary free drop and is never evolved beyond the short paired probe.',
      'note=instantaneous interfaceSpeedRms is not used as a stability gate because it contains thermal MPCD fluctuations.'
    ]
    (out/'capillary_shadow_decision_0493x21c.txt').write_text('\n'.join(lines)+'\n')
    print('\n'.join(lines))

def self_test():
    sig=945.0; k=-4.0; p0=50.0; pa=p0+sig*k
    gain=(pa-p0)/(sig*k)
    assert abs(gain-1)<1e-14
    rows=[]
    for i in range(100):rows.append({'time':str(i),'effectiveRadius':str(.25*(1+1e-5*math.sin(i))),'alphaArea':str(.2*(1+1e-5*math.cos(i)))})
    ok,q,dR,dA=detect_active_plateau(rows)
    assert ok and dR<1e-3 and dA<1e-3
    print('[x21c] self-test PASS')

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--campaign-root',type=Path)
    ap.add_argument('--select-checkpoints',action='store_true')
    ap.add_argument('--final',action='store_true')
    ap.add_argument('--self-test',action='store_true')
    ap.add_argument('--checkpoint-count',type=int,default=3)
    ap.add_argument('--expected-replicates',type=int,default=6)
    ap.add_argument('--sigma',type=float,default=945.0)
    ap.add_argument('--radius-cells',type=float,default=64.0)
    a=ap.parse_args()
    if a.self_test:return self_test()
    if a.campaign_root is None:raise SystemExit('--campaign-root required')
    if a.select_checkpoints:return select_checkpoints(a.campaign_root,a.checkpoint_count)
    if a.final:return final_analysis(a.campaign_root,a.sigma,a.radius_cells,a.expected_replicates)
    raise SystemExit('choose --select-checkpoints, --final, or --self-test')

if __name__=='__main__':main()
