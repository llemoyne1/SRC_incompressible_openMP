#!/usr/bin/env python3
from __future__ import annotations

import argparse
import csv
import json
import math
from pathlib import Path
from statistics import fmean, pstdev


def last_csv(path: Path):
    if not path.exists():
        raise SystemExit(f"[0493x9o-check] missing {path}")
    with path.open(newline='') as f:
        rows=list(csv.DictReader(f))
    if not rows:
        raise SystemExit(f"[0493x9o-check] empty {path}")
    return rows[-1]


def fv(row,key): return float(row[key])
def iv(row,key): return int(float(row[key]))


def baseline_kappa(root: Path|None, family: str):
    if root is None:
        return None
    rel={
        'circle_r80_theta120':'circle/r80/theta120/output/cuda_contact_angle_offsupport_0493x9m.csv',
        'ellipse_tall_theta90':'ellipse/tall/theta90/output/cuda_contact_angle_offsupport_0493x9m.csv',
    }.get(family)
    if not rel:
        return None
    p=root/rel
    if not p.exists():
        return None
    return fv(last_csv(p),'contactCurvatureMean')


def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--root',type=Path,required=True)
    ap.add_argument('--baseline-root',type=Path,default=None)
    args=ap.parse_args()
    metas=sorted(args.root.glob('**/init/geometry_0493x9o.smpcd.json'))
    if not metas:
        raise SystemExit(f"[0493x9o-check] no phase metadata below {args.root}")

    groups={}
    rows_out=[]
    overall=True
    for mp in metas:
        meta=json.loads(mp.read_text())
        case_id=meta.get('caseId') or str(mp.parent.parent.relative_to(args.root))
        parts=case_id.split('/')
        if len(parts)!=2:
            raise SystemExit(f"[0493x9o-check] unexpected caseId={case_id}")
        family,label=parts
        phase={'p000':0.0,'p025':0.25,'p050':0.50,'p075':0.75}.get(label)
        if phase is None:
            raise SystemExit(f"[0493x9o-check] unknown phase label={label}")
        case_dir=mp.parent.parent
        out=last_csv(case_dir/'output'/'cuda_contact_angle_offsupport_0493x9m.csv')
        theta=float(meta['contactAngleDegrees'])
        exact=float(meta['exactContactCurvature'])
        k=fv(out,'contactCurvatureMean'); ks=fv(out,'contactCurvatureStd')
        measured=fv(out,'correctedAngleMean'); angle_rms=fv(out,'correctedAngleErrorRms')
        cand=iv(out,'candidateCells'); corr=iv(out,'correctedCells')
        angle_pass=(cand>0 and corr==cand and abs(measured-theta)<=2.0 and angle_rms<=3.0)
        # Phase qualification is deliberately absolute at low curvature, matching
        # the x9n zero-curvature scale: each phase must stay within |dkappa|<=0.5.
        abs_err=abs(k-exact)
        envelope_pass=abs_err<=0.5
        noise_pass=ks<=0.5
        passed=angle_pass and envelope_pass and noise_pass
        overall &= passed
        rel=(k-exact)/exact
        cx=float(meta['centerX']); h=float(meta['dx']); cx0=0.5*float(meta['Lx'])
        measured_phase=((cx-cx0)/h)%1.0
        print(f"[0493x9o-check] family={family} phase={phase:.2f} measuredPhase={measured_phase:.6f} theta={theta:g} contactMean={measured:.8g} angleRms={angle_rms:.3e} anglePass={int(angle_pass)}")
        print(f"[0493x9o-check]   kappa={k:.8g} exact={exact:.8g} relBias={100*rel:+.3f}% absError={abs_err:.6g} std={ks:.8g} envelopePass={int(envelope_pass)} noisePass={int(noise_pass)} pass={int(passed)}")
        groups.setdefault(family,[]).append((phase,k,ks,exact))
        rows_out.append({'family':family,'phaseCells':phase,'thetaDegrees':theta,'exactCurvature':exact,'measuredCurvature':k,'curvatureStd':ks,'relativeBias':rel,'absoluteError':abs_err,'anglePass':int(angle_pass),'envelopePass':int(envelope_pass),'noisePass':int(noise_pass),'pass':int(passed)})

    expected={'circle_r80_theta120','ellipse_tall_theta90'}
    if set(groups)!=expected:
        raise SystemExit(f"[0493x9o-check] expected families {sorted(expected)}, got {sorted(groups)}")

    family_passes={}
    for family in sorted(groups):
        vals=sorted(groups[family])
        if len(vals)!=4 or [round(v[0],2) for v in vals] != [0.0,0.25,0.5,0.75]:
            raise SystemExit(f"[0493x9o-check] incomplete phase set for {family}")
        ks=[v[1] for v in vals]; exact=vals[0][3]
        mean=fmean(ks); sd=pstdev(ks); lo=min(ks); hi=max(ks); span=hi-lo; halfspan=0.5*span
        mean_err=mean-exact; mean_rel=mean_err/exact
        max_abs=max(abs(k-exact) for k in ks)
        mean_pass=abs(mean_rel)<=0.10
        spread_pass=halfspan<=0.5
        envelope_pass=max_abs<=0.5
        fam_pass=mean_pass and spread_pass and envelope_pass and all(abs(v[1]-exact)<=0.5 and v[2]<=0.5 for v in vals)
        family_passes[family]=fam_pass
        overall &= fam_pass
        base=baseline_kappa(args.baseline_root,family)
        print(f"[0493x9o-phase] family={family} exact={exact:.8g} mean={mean:.8g} meanBias={100*mean_rel:+.3f}% phaseStd={sd:.8g} min={lo:.8g} max={hi:.8g} halfRange={halfspan:.8g} maxAbsError={max_abs:.8g}")
        print(f"[0493x9o-phase]   meanPass={int(mean_pass)} spreadPass={int(spread_pass)} envelopePass={int(envelope_pass)} familyPass={int(fam_pass)}")
        if base is not None:
            print(f"[0493x9o-phase]   baselineX9nPhase0={base:.8g} rerunPhase0={vals[0][1]:.8g} delta={vals[0][1]-base:+.6g}")

    summary=args.root/'x9o_phase_summary.csv'
    with summary.open('w',newline='') as f:
        fields=list(rows_out[0].keys()); w=csv.DictWriter(f,fieldnames=fields); w.writeheader(); w.writerows(rows_out)
    for family in sorted(family_passes):
        print(f"[0493x9o-family] {family}={'PASS' if family_passes[family] else 'FAIL'}")
    print(f"[0493x9o-check] summary={summary}")
    print(f"[0493x9o-check] status={'PASS' if overall else 'FAIL'}")
    return 0 if overall else 2

if __name__=='__main__':
    raise SystemExit(main())
