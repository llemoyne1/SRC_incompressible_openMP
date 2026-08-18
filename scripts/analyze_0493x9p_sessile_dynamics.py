#!/usr/bin/env python3
"""0493x9p dynamic sessile-drop qualification (stdlib only).

Uses existing x9e/x9f/x9m diagnostics.  The *physical* apparent angle is not the
x9m prescribed wall normal.  Instead two independent global circular-cap
estimators are reconstructed from the evolving liquid distribution:
  - thetaCOM from liquid y-COM and conserved liquid mass area;
  - thetaMOM from the covariance ratio Mxx/Myy.
Agreement of the two is used as a circular-cap consistency diagnostic.
"""
from __future__ import annotations
import argparse, csv, math
from pathlib import Path

PI=math.pi

def rows(path: Path):
    if not path.exists():
        raise SystemExit(f"[0493x9p-check] missing {path}")
    with path.open(newline='') as f:
        out=list(csv.DictReader(f))
    if not out:
        raise SystemExit(f"[0493x9p-check] empty {path}")
    return out

def mean(v): return sum(v)/len(v) if v else float('nan')
def stdev(v):
    if len(v)<2: return 0.0
    m=mean(v); return math.sqrt(sum((x-m)*(x-m) for x in v)/(len(v)-1))

def lin_slope(xs,ys):
    if len(xs)<2: return 0.0
    xm,ym=mean(xs),mean(ys)
    den=sum((x-xm)*(x-xm) for x in xs)
    return 0.0 if den<=0 else sum((x-xm)*(y-ym) for x,y in zip(xs,ys))/den

def cap_D(th): return th-math.sin(th)*math.cos(th)

def cap_wall_centroid_over_sqrt_area(th):
    d=cap_D(th)
    return (-math.cos(th)+(2.0/3.0)*math.sin(th)**3/d)/math.sqrt(d)

def cap_cov_ratio(th):
    d=cap_D(th)
    m1=(2.0/3.0)*math.sin(th)**3
    x2=th/4.0-math.sin(2.0*th)/6.0+math.sin(4.0*th)/48.0
    y2=th/4.0-math.sin(4.0*th)/16.0
    vx=x2/d
    vy=y2/d-(m1/d)**2
    return vx/vy

def invert_monotone(value, fn, increasing=True, lo_deg=5.0, hi_deg=175.0):
    lo=math.radians(lo_deg); hi=math.radians(hi_deg)
    flo=fn(lo); fhi=fn(hi)
    if increasing:
        if value<=flo: return lo_deg, True
        if value>=fhi: return hi_deg, True
    else:
        if value>=flo: return lo_deg, True
        if value<=fhi: return hi_deg, True
    for _ in range(80):
        mid=0.5*(lo+hi); fm=fn(mid)
        if (fm<value) == increasing: lo=mid
        else: hi=mid
    return math.degrees(0.5*(lo+hi)), False

def theta_from_com(ycm, area):
    if not (area>0 and math.isfinite(ycm)): return float('nan'), True
    return invert_monotone(ycm/math.sqrt(area), cap_wall_centroid_over_sqrt_area, True)

def theta_from_mom(mxx,myy):
    if not (mxx>0 and myy>0): return float('nan'), True
    return invert_monotone(mxx/myy, cap_cov_ratio, False)

def target_geometry(area,theta_deg):
    th=math.radians(theta_deg); d=cap_D(th)
    r=math.sqrt(area/d)
    ycm=r*(-math.cos(th)+(2.0/3.0)*math.sin(th)**3/d)
    return dict(radius=r,curvature=1.0/r,footprint=2*r*math.sin(th),height=r*(1-math.cos(th)),ycm=ycm)

def tail_slice(seq, frac):
    n=max(3,int(math.ceil(len(seq)*frac)))
    return seq[-n:]

def read_manifest(path):
    with open(path,newline='') as f: return list(csv.DictReader(f))

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--root',type=Path,required=True)
    ap.add_argument('--manifest',type=Path,required=True)
    ap.add_argument('--Lx',type=float,required=True); ap.add_argument('--Ly',type=float,required=True)
    ap.add_argument('--nx',type=int,required=True); ap.add_argument('--ny',type=int,required=True)
    ap.add_argument('--gamma',type=float,required=True); ap.add_argument('--liquid-mass',type=float,default=1.0)
    ap.add_argument('--tail-fraction',type=float,default=0.25)
    ap.add_argument('--target-tol-deg',type=float,default=10.0)
    ap.add_argument('--agreement-tol-deg',type=float,default=8.0)
    ap.add_argument('--area-drift-tol',type=float,default=0.03)
    ap.add_argument('--xcm-drift-tol',type=float,default=0.01)
    ap.add_argument('--settle-std-deg',type=float,default=5.0)
    ap.add_argument('--settle-slope-deg-per-time',type=float,default=5.0)
    ap.add_argument('--curvature-rel-tol',type=float,default=0.20)
    args=ap.parse_args()
    cell_area=(args.Lx/args.nx)*(args.Ly/args.ny)
    manifest=read_manifest(args.manifest)
    summary=[]; case_metrics={}
    integrity_all=True; direction_all=True; target_all=True; settled_all=True; curvature_all=True
    for c in manifest:
        name=c['case']; init=float(c['initAngle']); target=float(c['targetAngle']); sigma=float(c['sigma'])
        active=int(c['contactActive'])!=0
        out=args.root/name/'output'
        S=rows(out/'cuda_ellipse_shape_0493x9f.csv')
        P=rows(out/'cuda_static_drop_pressure_0493x9e.csv')
        V=rows(out/'cuda_static_drop_velocity_0493x9e.csv')
        sd={int(float(r['step'])):r for r in S}; pd={int(float(r['step'])):r for r in P}; vd={int(float(r['step'])):r for r in V}
        common=sorted(set(sd)&set(pd)&set(vd))
        if len(common)<4: raise SystemExit(f"[0493x9p-check] too few common diagnostic rows for {name}")
        series=[]
        clipped=0
        for st in common:
            s,p,v=sd[st],pd[st],vd[st]
            liquid_mass=float(s['liquidMass'])
            area_mass=liquid_mass*cell_area/(args.gamma*args.liquid_mass)
            tc,cl1=theta_from_com(float(s['yCM']),area_mass)
            tm,cl2=theta_from_mom(float(s['Mxx']),float(s['Myy']))
            clipped += int(cl1 or cl2)
            tg=0.5*(tc+tm)
            series.append(dict(step=st,time=float(s['time']),thetaCOM=tc,thetaMOM=tm,theta=tg,
                               agree=abs(tc-tm),xCM=float(s['xCM']),yCM=float(s['yCM']),
                               alphaArea=float(p['alphaArea']),areaMass=area_mass,
                               uInt=float(v['interfaceSpeedRms']),
                               bulkKappa=float(p['curvatureMean']),
                               pJump=float(p['measuredPressureJump'])))
        tail=tail_slice(series,args.tail_fraction)
        first=series[0]
        area0=first['areaMass']
        geom=target_geometry(area0,target if active else init)
        theta0=mean([r['theta'] for r in series[:min(3,len(series))]])
        theta_tail=mean([r['theta'] for r in tail]); tc_tail=mean([r['thetaCOM'] for r in tail]); tm_tail=mean([r['thetaMOM'] for r in tail])
        theta_std=stdev([r['theta'] for r in tail]); agree_tail=mean([r['agree'] for r in tail])
        slope=lin_slope([r['time'] for r in tail],[r['theta'] for r in tail])
        xcm0=first['xCM']; xcm_tail=mean([r['xCM'] for r in tail]); xdrift=xcm_tail-xcm0
        alpha0=first['alphaArea']; alpha_tail=mean([r['alphaArea'] for r in tail]); area_drift=(alpha_tail-alpha0)/alpha0 if alpha0 else float('inf')
        uint_tail=mean([r['uInt'] for r in tail]); uint_peak=max(r['uInt'] for r in series)
        integrity=(abs(area_drift)<=args.area_drift_tol and abs(xdrift)<=args.xcm_drift_tol and agree_tail<=args.agreement_tol_deg and clipped==0)
        if active:
            target_pass=abs(theta_tail-target)<=args.target_tol_deg
            if target<init: direction=(theta_tail < init-5.0)
            elif target>init: direction=(theta_tail > init+5.0)
            else: direction=abs(theta_tail-init)<=args.target_tol_deg
            settled=(theta_std<=args.settle_std_deg and abs(slope)<=args.settle_slope_deg_per_time)
            C=rows(out/'cuda_contact_angle_offsupport_0493x9m.csv')
            ktail=tail_slice([float(r['contactCurvatureMean']) for r in C],args.tail_fraction)
            kmean=mean(ktail); krel=(kmean-geom['curvature'])/geom['curvature']
            curvature=abs(krel)<=args.curvature_rel_tol
        else:
            target_pass=abs(theta_tail-init)<=args.target_tol_deg
            direction=target_pass
            settled=(theta_std<=args.settle_std_deg and abs(slope)<=args.settle_slope_deg_per_time)
            kmean=float('nan'); krel=float('nan'); curvature=True
        integrity_all &= integrity; direction_all &= direction; target_all &= target_pass; settled_all &= settled; curvature_all &= curvature
        case_metrics[name]=dict(theta=theta_tail,init=init,target=target,active=active)
        print(f"[0493x9p-check] case={name} init={init:g} target={'off' if not active else f'{target:g}'} sigma={sigma:g} rows={len(series)} tail={len(tail)}")
        print(f"[0493x9p-check]   thetaCOM={tc_tail:.4f} thetaMOM={tm_tail:.4f} thetaGlobal={theta_tail:.4f} targetErr={(theta_tail-(target if active else init)):+.3f}deg agree={agree_tail:.3f}deg std={theta_std:.3f} slope={slope:+.3f}deg/time")
        print(f"[0493x9p-check]   alphaAreaDrift={100*area_drift:+.3f}% xCMdrift={xdrift:+.4e} uIntTail={uint_tail:.5g} uIntPeak={uint_peak:.5g} integrityPass={int(integrity)} directionPass={int(direction)} targetPass={int(target_pass)} settledPass={int(settled)}")
        if active:
            print(f"[0493x9p-check]   targetGeometry R={geom['radius']:.6g} kappa={geom['curvature']:.6g} footprint={geom['footprint']:.6g} height={geom['height']:.6g} yCM={geom['ycm']:.6g}")
            print(f"[0493x9p-check]   contactKappaTail={kmean:.6g} relTarget={100*krel:+.2f}% curvaturePass={int(curvature)}")
        passed=integrity and direction and target_pass and settled and curvature
        print(f"[0493x9p-check]   pass={int(passed)}")
        summary.append(dict(case=name,initAngle=init,targetAngle=(target if active else ''),sigma=sigma,
            thetaCOMTail=tc_tail,thetaMOMTail=tm_tail,thetaGlobalTail=theta_tail,targetErrorDeg=theta_tail-(target if active else init),
            thetaAgreementDeg=agree_tail,thetaTailStdDeg=theta_std,thetaTailSlopeDegPerTime=slope,
            alphaAreaDrift=area_drift,xCMDrift=xdrift,uIntTail=uint_tail,uIntPeak=uint_peak,
            targetRadius=(geom['radius'] if active else ''),targetCurvature=(geom['curvature'] if active else ''),
            contactCurvatureTail=(kmean if active else ''),contactCurvatureRelError=(krel if active else ''),
            integrityPass=int(integrity),directionPass=int(direction),targetPass=int(target_pass),settledPass=int(settled),curvaturePass=int(curvature),passCase=int(passed)))
    # Paired no-capillary control: both active 90->60 and 90->120 must separate from it.
    paired_pass=True
    if all(k in case_metrics for k in ('wet90to60','dewet90to120','control90')):
        wet=case_metrics['wet90to60']['theta']; dry=case_metrics['dewet90to120']['theta']; ctrl=case_metrics['control90']['theta']
        wet_sep=ctrl-wet; dry_sep=dry-ctrl
        paired_pass=wet_sep>=10.0 and dry_sep>=10.0
        print(f"[0493x9p-paired] control90={ctrl:.4f} wet90to60={wet:.4f} dewet90to120={dry:.4f} wetSeparation={wet_sep:.3f}deg dewetSeparation={dry_sep:.3f}deg pass={int(paired_pass)}")
    else:
        print('[0493x9p-paired] INFO canonical paired cases not all present; paired gate skipped')
    out=args.root/'x9p_dynamic_summary.csv'
    fields=list(summary[0].keys())
    with out.open('w',newline='') as f:
        w=csv.DictWriter(f,fieldnames=fields); w.writeheader(); w.writerows(summary)
    hard_ok=integrity_all and direction_all and paired_pass
    finish_ok=target_all and settled_all and curvature_all
    if hard_ok and finish_ok: status='PASS'; rc=0
    elif hard_ok: status='EXTEND_OR_REVIEW'; rc=2
    else: status='FAIL'; rc=2
    print(f"[0493x9p-family] integrity={'PASS' if integrity_all else 'FAIL'} direction={'PASS' if direction_all else 'FAIL'} paired={'PASS' if paired_pass else 'FAIL'} target={'PASS' if target_all else 'FAIL'} settled={'PASS' if settled_all else 'FAIL'} curvature={'PASS' if curvature_all else 'FAIL'}")
    print(f"[0493x9p-check] summary={out}")
    print(f"[0493x9p-check] status={status}")
    return rc
if __name__=='__main__': raise SystemExit(main())
