#!/usr/bin/env python3
"""0493x17d publication membrane validation (stdlib only; no pandas)."""
import argparse, csv, math
from collections import defaultdict
from pathlib import Path


def read_rows(path):
    with open(path, newline='') as f:
        return list(csv.DictReader(f))


def fv(r, k, default=0.0):
    v = r.get(k, '')
    return float(v) if v not in ('', None) else default


def iv(r, k, default=0):
    v = r.get(k, '')
    return int(float(v)) if v not in ('', None) else default


def read_meta(path):
    d = {}
    for line in path.read_text().splitlines():
        if '=' in line and not line.lstrip().startswith('#'):
            k,v = line.split('=',1)
            d[k.strip()] = v.strip()
    return d


def seg_intersect(a,b,c,d,eps):
    def orient(p,q,r):
        return (q[0]-p[0])*(r[1]-p[1])-(q[1]-p[1])*(r[0]-p[0])
    def onseg(p,q,r):
        return (min(p[0],r[0])-eps <= q[0] <= max(p[0],r[0])+eps and
                min(p[1],r[1])-eps <= q[1] <= max(p[1],r[1])+eps)
    o1,o2,o3,o4 = orient(a,b,c),orient(a,b,d),orient(c,d,a),orient(c,d,b)
    if ((o1 > eps and o2 < -eps) or (o1 < -eps and o2 > eps)) and \
       ((o3 > eps and o4 < -eps) or (o3 < -eps and o4 > eps)):
        return True
    if abs(o1) <= eps and onseg(a,c,b): return True
    if abs(o2) <= eps and onseg(a,d,b): return True
    if abs(o3) <= eps and onseg(c,a,d): return True
    if abs(o4) <= eps and onseg(c,b,d): return True
    return False


def self_intersections(points, h):
    """Exact candidate test with spatial hashing of segment AABBs."""
    n=len(points)
    if n < 4: return []
    cell=max(4.0*h,1e-15)
    bins=defaultdict(list)
    pairs=set()
    for i in range(n):
        a=points[i]; b=points[(i+1)%n]
        xmin,xmax=sorted((a[0],b[0])); ymin,ymax=sorted((a[1],b[1]))
        ix0=math.floor(xmin/cell); ix1=math.floor(xmax/cell)
        iy0=math.floor(ymin/cell); iy1=math.floor(ymax/cell)
        for ix in range(ix0,ix1+1):
            for iy in range(iy0,iy1+1):
                key=(ix,iy)
                for j in bins[key]:
                    if i==j or abs(i-j)==1 or {i,j}=={0,n-1}: continue
                    pairs.add((min(i,j),max(i,j)))
                bins[key].append(i)
    eps=max(1e-14,1e-10*h*h)
    hits=[]
    for i,j in sorted(pairs):
        if seg_intersect(points[i],points[(i+1)%n],points[j],points[(j+1)%n],eps):
            hits.append((i,j))
    return hits


def max_rel_vector(rows, rx, ry, sx, sy):
    ans=0.0
    for r in rows:
        num=math.hypot(fv(r,rx),fv(r,ry))
        den=max(1e-30,math.hypot(fv(r,sx),fv(r,sy)))
        ans=max(ans,num/den)
    return ans


def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--root',default='runs/0493x17d_fixed_membrane_publishable')
    a=ap.parse_args()
    root=Path(a.root); run=root/'fresh'; out=run/'output'
    meta=read_meta(run/'run_meta_0493x17d_membrane_publishable.txt')
    h=float(meta['h']); dt=float(meta['dt']); span=float(meta['membraneSpan'])

    mem=read_rows(out/'chi_membrane_0493x17c.csv')
    nodes=read_rows(out/'chi_membrane_nodes_0493x17c.csv')
    pen=read_rows(out/'chi_penetration_0493x16l.csv')
    solid=read_rows(out/'chi_solid_dynamics_0493x16a.csv')
    kinetic=read_rows(out/'chi_kinetic_boundary_0493x16j.csv')
    runtime=read_rows(out/'summary_runtime.csv')
    if not mem or not nodes or not pen or not solid or not kinetic or not runtime:
        raise SystemExit('[0493x17d-pub] ERROR empty diagnostic file')

    by_step=defaultdict(list)
    for r in nodes: by_step[iv(r,'step')].append(r)
    steps=sorted(by_step)
    node_counts={len(v) for v in by_step.values()}
    topology_hits=[]
    max_anchor=0.0; max_defl=0.0; max_defl_signed=0.0
    midspan_max=0.0; max_defl_step=steps[0]
    y0_all=[fv(r,'y0') for r in by_step[steps[0]]]
    ymid=0.5*(min(y0_all)+max(y0_all))
    for st in steps:
        rr=sorted(by_step[st],key=lambda r:iv(r,'node'))
        pts=[(fv(r,'x'),fv(r,'y')) for r in rr]
        hits=self_intersections(pts,h)
        if hits: topology_hits.append((st,len(hits),hits[:8]))
        mid=[]
        for r in rr:
            dx=fv(r,'x')-fv(r,'x0'); dy=fv(r,'y')-fv(r,'y0')
            if iv(r,'pinned0493x17d'):
                max_anchor=max(max_anchor,math.hypot(dx,dy)/h)
            else:
                if abs(dx)>max_defl:
                    max_defl=abs(dx); max_defl_signed=dx; max_defl_step=st
                if abs(fv(r,'y0')-ymid)<=1.5*h: mid.append(dx)
        if mid: midspan_max=max(midspan_max,abs(sum(mid)/len(mid)))

    max_strict=max(iv(r,'strictInsideParticles') for r in pen)
    max_raw=max(iv(r,'rawInsideParticles') for r in pen)
    max_pen=max(fv(r,'maxPenetrationCells') for r in pen)
    runtime_fluid={iv(r,'step'):iv(r,'nFluidParticles') for r in runtime}
    coverage_rows=[]
    for r in pen:
        st=iv(r,'step')
        expected=runtime_fluid.get(st,0)
        sampled=iv(r,'sampledParticles')
        coverage_rows.append((st,sampled,expected))
    full_penetration_coverage=bool(coverage_rows) and all(expected>0 and sampled==expected for st,sampled,expected in coverage_rows)
    min_penetration_coverage=min((sampled/max(1,expected) for st,sampled,expected in coverage_rows),default=0.0)
    total_abs_wall_impulse_x=sum(abs(fv(r,'wallImpulseX')) for r in kinetic)
    total_abs_wall_impulse_y=sum(abs(fv(r,'wallImpulseY')) for r in kinetic)
    total_kinetic_collisions=sum(iv(r,'collisions') for r in kinetic)
    max_area=max(abs(fv(r,'areaRelativeChange')) for r in mem)
    max_perim=max(abs(fv(r,'perimeterRelativeChange')) for r in mem)
    max_strain=max(abs(fv(r,'maxAbsEdgeStrain')) for r in mem)
    max_stability=max(fv(r,'stabilityNumber') for r in mem)
    pinned=max(iv(r,'pinnedNodeCount') for r in mem)

    proj=0.0; internal=0.0
    for r in mem:
        reaction=math.hypot(fv(r,'nodeReactionImpulseX'),fv(r,'nodeReactionImpulseY'))
        proj=max(proj,math.hypot(fv(r,'loadProjectionResidualX'),fv(r,'loadProjectionResidualY'))/max(1e-30,reaction))
        internal=max(internal,dt*math.hypot(fv(r,'internalForceSumX'),fv(r,'internalForceSumY'))/max(1e-30,reaction))
    ar=0.0
    for r in solid:
        reaction=math.hypot(fv(r,'solidReactionImpulseX'),fv(r,'solidReactionImpulseY'))
        support=0.0
        # support is already incorporated in actionReactionResidual by x17d.
        ar=max(ar,math.hypot(fv(r,'actionReactionResidualX'),fv(r,'actionReactionResidualY'))/max(1e-30,reaction,abs(support)))

    # Publication-quality criteria: visible but not extreme deformation.
    defl_ratio=max_defl/span
    mid_ratio=midspan_max/span
    checks={
        'node_count_constant': len(node_counts)==1,
        'no_self_intersection': not topology_hits,
        'penetration_full_particle_coverage': full_penetration_coverage,
        'zero_strict_penetration': max_strict==0 and max_pen<=1e-6,
        'hydrodynamic_x_load_present': total_abs_wall_impulse_x>1e-12 and total_kinetic_collisions>0,
        'anchors_fixed': max_anchor<=1e-8,
        'visible_deflection': defl_ratio>=0.05 and mid_ratio>=0.035,
        'not_overdeformed': defl_ratio<=0.30,
        'strain_reasonable': max_strain<=0.30,
        'area_controlled': max_area<=0.05,
        'explicit_stability': max_stability<=0.50,
        'load_projection_closure': proj<=1e-10,
        'internal_force_closure': internal<=1e-10,
        'action_reaction_closure': ar<=1e-10,
        'anchored_nodes_present': pinned>=4,
    }
    status='PASS' if all(checks.values()) else 'REVIEW'

    analysis=root/'analysis'; analysis.mkdir(parents=True,exist_ok=True)
    summary=analysis/'summary_0493x17d_fixed_membrane_publishable.txt'
    lines=[
        '0493x17d fixed membrane publication validation',
        f'status={status}',
        f'grid={meta["Nx"]}x{meta["Ny"]}', f'h={h}', f'dt={dt}', f'flowUx={meta["flowUx"]}',
        f'nodeSnapshots={len(steps)}', f'nodeCountSet={sorted(node_counts)}', f'pinnedNodeCount={pinned}',
        f'maxAnchorDriftCells={max_anchor}',
        f'maxDeflection={max_defl}', f'maxDeflectionCells={max_defl/h}', f'maxDeflectionSpanRatio={defl_ratio}',
        f'maxDeflectionSigned={max_defl_signed}', f'maxDeflectionStep={max_defl_step}',
        f'maxMidspanDeflection={midspan_max}', f'maxMidspanDeflectionSpanRatio={mid_ratio}',
        f'maxAbsEdgeStrain={max_strain}', f'maxAreaRelativeChange={max_area}', f'maxPerimeterRelativeChange={max_perim}',
        f'maxStabilityNumber={max_stability}',
        f'maxRawInsideParticles={max_raw}', f'maxStrictInsideParticles={max_strict}', f'maxPenetrationCells={max_pen}',
        f'minPenetrationParticleCoverage={min_penetration_coverage}',
        f'totalKineticCollisions={total_kinetic_collisions}', f'totalAbsWallImpulseX={total_abs_wall_impulse_x}', f'totalAbsWallImpulseY={total_abs_wall_impulse_y}',
        f'selfIntersectionSnapshots={len(topology_hits)}',
        f'maxLoadProjectionRelative={proj}', f'maxInternalForceRelative={internal}', f'maxActionReactionRelative={ar}',
        '', '[criteria]'
    ]
    lines += [f'{k}={"PASS" if v else "FAIL"}' for k,v in checks.items()]
    if topology_hits:
        lines += ['', '[self_intersections]']+[f'step={st} count={cnt} pairs={pairs}' for st,cnt,pairs in topology_hits[:20]]
    summary.write_text('\n'.join(lines)+'\n')
    print('\n'.join(lines)); print(f'[0493x17d-pub] summary={summary}')
    if status!='PASS':
        raise SystemExit(3)

if __name__=='__main__': main()
