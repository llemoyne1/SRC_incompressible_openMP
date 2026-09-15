#!/usr/bin/env python3
import argparse,csv,math
from pathlib import Path

def rows(p):
    with open(p,newline='') as f:return list(csv.DictReader(f))
def fv(r,k): return float(r.get(k,'0') or 0.0)
def iv(r,k): return int(float(r.get(k,'0') or 0))
def rms(vals): return math.sqrt(sum(v*v for v in vals)/len(vals)) if vals else 0.0

def analyze_mem(root):
    out=root/'fresh'/'output'; m=rows(out/'chi_membrane_0493x17c.csv'); n=rows(out/'chi_membrane_nodes_0493x17c.csv'); p=rows(out/'chi_penetration_0493x16l.csv')
    pinned=[r for r in n if iv(r,'pinned0493x17d')]
    free=[r for r in n if not iv(r,'pinned0493x17d')]
    h=0.75/192.0
    max_anchor=max((math.hypot(fv(r,'x')-fv(r,'x0'),fv(r,'y')-fv(r,'y0'))/h for r in pinned),default=0.0)
    max_defl=max((abs(fv(r,'x')-fv(r,'x0'))/h for r in free),default=0.0)
    max_strict=max((iv(r,'strictInsideParticles') for r in p),default=0); max_pen=max((fv(r,'maxPenetrationCells') for r in p),default=0.0)
    max_area=max((abs(fv(r,'areaRelativeChange')) for r in m),default=0.0); max_strain=max((abs(fv(r,'maxAbsEdgeStrain')) for r in m),default=0.0)
    pin_count=max((iv(r,'pinnedNodeCount') for r in m),default=0)
    support_rms=rms([math.hypot(fv(r,'supportConstraintImpulseX'),fv(r,'supportConstraintImpulseY')) for r in m])
    proj=max((math.hypot(fv(r,'loadProjectionResidualX'),fv(r,'loadProjectionResidualY')) for r in m),default=0.0)
    scale=max(1e-30,max((math.hypot(fv(r,'nodeReactionImpulseX'),fv(r,'nodeReactionImpulseY')) for r in m),default=0.0))
    return dict(maxStrictInside=max_strict,maxPenetrationCells=max_pen,maxAnchorDriftCells=max_anchor,maxDeflectionCells=max_defl,maxAreaRel=max_area,maxStrain=max_strain,pinnedNodeCount=pin_count,supportReactionRms=support_rms,maxProjectionRel=proj/scale)

def analyze_piston(root):
    out=root/'fresh'/'output'; s=rows(out/'chi_solid_dynamics_0493x16a.csv'); p=rows(out/'chi_penetration_0493x16l.csv')
    x0=fv(s[0],'centerXBefore') if s else 0.0; xf=fv(s[-1],'centerXAfter') if s else 0.0
    vf=fv(s[-1],'velocityXAfter') if s else 0.0
    max_strict=max((iv(r,'strictInsideParticles') for r in p),default=0); max_pen=max((fv(r,'maxPenetrationCells') for r in p),default=0.0)
    ar=max((math.hypot(fv(r,'actionReactionResidualX'),fv(r,'actionReactionResidualY')) for r in s),default=0.0)
    reaction=max((math.hypot(fv(r,'solidReactionImpulseX'),fv(r,'solidReactionImpulseY')) for r in s),default=0.0)
    return dict(centerX0=x0,centerXFinal=xf,displacement=xf-x0,velocityFinal=vf,maxStrictInside=max_strict,maxPenetrationCells=max_pen,maxActionReactionRel=ar/max(1e-30,reaction))

def main():
    ap=argparse.ArgumentParser(); ap.add_argument('--root',default='runs/0493x17d_article_solids'); a=ap.parse_args(); root=Path(a.root)
    mem=analyze_mem(root/'fixed_membrane'); pis=analyze_piston(root/'pressure_piston')
    mem_pass=(mem['maxStrictInside']==0 and mem['maxPenetrationCells']<=1e-6 and mem['maxAnchorDriftCells']<=1e-8 and mem['maxDeflectionCells']>=0.25 and mem['pinnedNodeCount']>=2 and mem['maxProjectionRel']<=1e-10)
    piston_pass=(pis['maxStrictInside']==0 and pis['maxPenetrationCells']<=1e-6 and pis['displacement']>0 and abs(pis['velocityFinal'])>1e-5 and pis['maxActionReactionRel']<=1e-10)
    status='PASS' if mem_pass and piston_pass else 'REVIEW'
    text=['0493x17d article solid-dynamics demonstrators',f'status={status}','penetrationDiagnostic=current_lagrangian_geometry','fixedMembrane='+('PASS' if mem_pass else 'REVIEW'),'pressureDrivenPiston='+('PASS' if piston_pass else 'REVIEW'),'','[fixed_membrane]']
    text += [f'{k}={v}' for k,v in mem.items()]; text += ['','[pressure_piston]']; text += [f'{k}={v}' for k,v in pis.items()]
    out=root/'analysis'/'summary_0493x17d.txt'; out.parent.mkdir(parents=True,exist_ok=True); out.write_text('\n'.join(text)+'\n'); print('\n'.join(text)); print(f'[0493x17d] summary={out}')
if __name__=='__main__':main()
