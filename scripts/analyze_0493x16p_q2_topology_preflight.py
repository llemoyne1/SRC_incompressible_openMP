#!/usr/bin/env python3
import argparse, csv, math, sys
from pathlib import Path
try:
    import numpy as np
except Exception as e:
    raise SystemExit(f"ERROR: numpy required for x16p offline preflight: {e}")

CASES = [
    ("static_rest",   "static_curved/rest/fresh/output/chi_solid_dynamics_0493x16a.csv", True),
    ("static_boost",  "static_curved/boost/fresh/output/chi_solid_dynamics_0493x16a.csv", True),
    ("rigid_rest",    "full_mobile/rigid/rest/fresh/output/chi_solid_dynamics_0493x16a.csv", False),
    ("rigid_boost",   "full_mobile/rigid/boost/fresh/output/chi_solid_dynamics_0493x16a.csv", False),
    ("deform_rest",   "full_mobile/deformable/rest/fresh/output/chi_solid_dynamics_0493x16a.csv", False),
    ("deform_boost",  "full_mobile/deformable/boost/fresh/output/chi_solid_dynamics_0493x16a.csv", False),
]

TOL_COEF = 1e-13
TOL_ROOT = 2e-10
TOL_TANGENT_DISC = 1e-12


def wrap_delta(x, c, L):
    d = x - c
    return d - np.rint(d / L) * L


def alpha_grid(nx, ny, lx, ly, center, thickness, amplitude, omega, tgeom, static_curve):
    dx = lx / nx
    dy = ly / ny
    x = (np.arange(nx, dtype=np.float64) + 0.5) * dx
    y = (np.arange(ny, dtype=np.float64) + 0.5) * dy
    if amplitude != 0.0:
        shape = np.sin((2.0 * math.pi / ly) * y)
        if static_curve and abs(omega) <= 1e-30:
            local = center + amplitude * shape
        elif omega != 0.0:
            local = center + amplitude * shape * math.sin(omega * tgeom)
        else:
            local = np.full_like(y, center)
    else:
        local = np.full_like(y, center)
    d = wrap_delta(x[None, :], local[:, None], lx)
    sd = np.abs(d) - 0.5 * thickness
    # x16k: S=1-chi = clamp(0.5 - sd/(4 dx), 0, 1)
    S = np.clip(0.5 - sd / (4.0 * dx), 0.0, 1.0)
    return S


def root_count_arrays(fm, f0, fp):
    # p(t)-.5 = a t^2 + b t + c, t in [0,1]
    a = 0.5 * (fp - 2.0*f0 + fm)
    b = 0.5 * (fp - fm)
    c = f0 - 0.5
    count = np.zeros_like(f0, dtype=np.int8)
    deg = (np.abs(a) <= TOL_COEF) & (np.abs(b) <= TOL_COEF) & (np.abs(c) <= TOL_COEF)
    lin = (np.abs(a) <= TOL_COEF) & (~deg) & (np.abs(b) > TOL_COEF)
    r = np.zeros_like(f0)
    r[lin] = -c[lin] / b[lin]
    count[lin & (r >= -TOL_ROOT) & (r <= 1.0 + TOL_ROOT)] = 1
    quad = np.abs(a) > TOL_COEF
    disc = b*b - 4.0*a*c
    pos = quad & (disc > TOL_TANGENT_DISC)
    sq = np.zeros_like(f0)
    sq[pos] = np.sqrt(disc[pos])
    r1 = np.zeros_like(f0); r2 = np.zeros_like(f0)
    r1[pos] = (-b[pos] - sq[pos]) / (2.0*a[pos])
    r2[pos] = (-b[pos] + sq[pos]) / (2.0*a[pos])
    v1 = pos & (r1 >= -TOL_ROOT) & (r1 <= 1.0 + TOL_ROOT)
    v2 = pos & (r2 >= -TOL_ROOT) & (r2 <= 1.0 + TOL_ROOT)
    count[v1] += 1; count[v2] += 1
    tan = quad & (np.abs(disc) <= TOL_TANGENT_DISC)
    rt = np.zeros_like(f0)
    rt[tan] = -b[tan] / (2.0*a[tan])
    vt = tan & (rt >= -TOL_ROOT) & (rt <= 1.0 + TOL_ROOT)
    count[vt] = np.maximum(count[vt], 1)
    return count, deg, vt


def exact_roots(fm, f0, fp):
    a = 0.5*(fp - 2.0*f0 + fm)
    b = 0.5*(fp - fm)
    c = f0 - 0.5
    if abs(a) <= TOL_COEF:
        if abs(b) <= TOL_COEF:
            return [], abs(c) <= TOL_COEF, False
        r = -c/b
        return ([min(1.0,max(0.0,r))] if -TOL_ROOT <= r <= 1+TOL_ROOT else []), False, False
    d = b*b - 4*a*c
    if d < -TOL_TANGENT_DISC:
        return [], False, False
    if abs(d) <= TOL_TANGENT_DISC:
        r = -b/(2*a)
        return ([min(1.0,max(0.0,r))] if -TOL_ROOT <= r <= 1+TOL_ROOT else []), False, True
    sd = math.sqrt(max(0.0,d))
    rs = [(-b-sd)/(2*a), (-b+sd)/(2*a)]
    out=[]
    for r in rs:
        if -TOL_ROOT <= r <= 1+TOL_ROOT:
            rr=min(1.0,max(0.0,r))
            if not out or abs(rr-out[-1]) > 1e-9:
                out.append(rr)
    return out, False, False


def boundary_unique_points(S, j, i):
    ny,nx=S.shape
    im=(i-1)%nx; ip=(i+1)%nx
    jm=(j-1)%ny; jp=(j+1)%ny
    # bottom, right, top, left in canonical directions
    triples=[
        (S[j,im],S[j,i],S[j,ip],0),
        (S[jm,ip],S[j,ip],S[jp,ip],1),
        (S[jp,im],S[jp,i],S[jp,ip],2),
        (S[jm,i],S[j,i],S[jp,i],3),
    ]
    pts=[]; degen=False; tangent=False; peredge=[]
    for fm,f0,fp,e in triples:
        roots,dg,tg=exact_roots(float(fm),float(f0),float(fp))
        degen |= dg; tangent |= tg; peredge.append(len(roots))
        for r in roots:
            if e==0: p=(r,0.0)
            elif e==1: p=(1.0,r)
            elif e==2: p=(r,1.0)
            else: p=(0.0,r)
            if not any((p[0]-q[0])**2+(p[1]-q[1])**2 < 1e-16 for q in pts):
                pts.append(p)
    return pts,degen,tangent,peredge


def bernstein_controls(S,j,i):
    ny,nx=S.shape
    rows=[(j-1)%ny,j,(j+1)%ny]
    cols=[(i-1)%nx,i,(i+1)%nx]
    F=S[np.ix_(rows,cols)].astype(float)-0.5
    # transform Lagrange samples at -1,0,+1 to quadratic Bernstein controls on [0,1]
    T=np.array([[0.0,1.0,0.0],[-0.25,1.0,0.25],[0.0,0.0,1.0]])
    return T @ F @ T.T


def split1(ctrl):
    b0,b1,b2=ctrl
    m01=0.5*(b0+b1); m12=0.5*(b1+b2); mid=0.5*(m01+m12)
    return np.array([b0,m01,mid]), np.array([mid,m12,b2])


def split_net_x(B):
    L=np.empty_like(B); R=np.empty_like(B)
    for r in range(3):
        L[r,:],R[r,:]=split1(B[r,:])
    return L,R


def split_net_y(B):
    Lo=np.empty_like(B); Hi=np.empty_like(B)
    for c in range(3):
        Lo[:,c],Hi[:,c]=split1(B[:,c])
    return Lo,Hi


def hidden_zero_possible(B, depth=0, maxdepth=10, tol=5e-13):
    mn=float(B.min()); mx=float(B.max())
    if mn > tol or mx < -tol:
        return False
    if depth >= maxdepth:
        return True
    L,R=split_net_x(B)
    LL,LH=split_net_y(L); RL,RH=split_net_y(R)
    return any(hidden_zero_possible(C,depth+1,maxdepth,tol) for C in (LL,LH,RL,RH))


def pre_center(row,lx):
    c=float(row['centerXBefore'])
    drift=float(row.get('poststreamDriftX0493x16f','0') or 0.0)
    return (c-drift) % lx


def f(row,key,default=0.0):
    try: return float(row.get(key,default) or default)
    except Exception: return float(default)


def analyze_case(label,path,static_curve,nx,ny,lx,ly):
    with path.open(newline='') as fh:
        rows=list(csv.DictReader(fh))
    if not rows: raise RuntimeError(f'empty CSV: {path}')
    dt=f(rows[0],'time')/max(1,int(float(rows[0]['step'])))
    stats=dict(label=label,rows=len(rows),maxUniqueRoots=0,maxRawRoots=0,maxPerEdge=0,
               gt4=0,degenerate=0,tangent=0,hidden=0,ownersPotential=0,
               worst=None, hidden_examples=[], gt4_examples=[])
    for ir,row in enumerate(rows):
        step=int(float(row['step'])); gv=int(float(row.get('geometryVersion',step) or step))
        center=pre_center(row,lx)
        amp=f(row,'deformAmplitude0493x16i')
        omega=f(row,'deformOmega0493x16i')
        expected=f(row,'expectedSolidVolume0493x16e')
        thickness=expected/ly if expected>0 else 8.0*(lx/nx)
        tgeom=(gv-1)*dt
        S=alpha_grid(nx,ny,lx,ly,center,thickness,amp,omega,tgeom,static_curve)
        # periodic stencil arrays for all owners
        fm0=np.roll(S,1,axis=1); f00=S; fp0=np.roll(S,-1,axis=1)
        f0m=np.roll(S,1,axis=0); f0p=np.roll(S,-1,axis=0)
        fpm=np.roll(fp0,1,axis=0); fpp=np.roll(fp0,-1,axis=0)
        fmp=np.roll(fm0,-1,axis=0)
        cb,dgb,tgb=root_count_arrays(fm0,f00,fp0)
        cr,dgr,tgr=root_count_arrays(fpm,fp0,fpp)
        ct,dgt,tgt=root_count_arrays(fmp,f0p,fpp)
        cl,dgl,tgl=root_count_arrays(f0m,f00,f0p)
        raw=(cb+cr+ct+cl).astype(np.int16)
        maxraw=int(raw.max()); maxedge=int(max(cb.max(),cr.max(),ct.max(),cl.max()))
        stats['maxRawRoots']=max(stats['maxRawRoots'],maxraw); stats['maxPerEdge']=max(stats['maxPerEdge'],maxedge)
        degmask=dgb|dgr|dgt|dgl; tanmask=tgb|tgr|tgt|tgl
        stats['degenerate'] += int(degmask.sum()); stats['tangent'] += int(tanmask.sum())
        # owners requiring exact dedupe / risk analysis: raw roots or Bernstein possibility near interface
        idx=np.argwhere(raw>0)
        for j,i in idx:
            pts,dg,tg,per=boundary_unique_points(S,int(j),int(i))
            nu=len(pts)
            if nu>stats['maxUniqueRoots']:
                stats['maxUniqueRoots']=nu; stats['worst']=(step,int(i),int(j),nu,per)
            if nu>4:
                stats['gt4']+=1
                if len(stats['gt4_examples'])<8: stats['gt4_examples'].append((step,int(i),int(j),nu,per))
        # Closed contour screen: no boundary root, but Bernstein subdivision cannot prove sign-definite.
        # Build a cheap candidate mask from 3x3 stencil min/max and modest overshoot margin.
        st=[np.roll(np.roll(S,dy,axis=0),dx,axis=1) for dy in (-1,0,1) for dx in (-1,0,1)]
        smin=np.minimum.reduce(st); smax=np.maximum.reduce(st)
        cand=(raw==0) & (smin < 0.56) & (smax > 0.44)
        cidx=np.argwhere(cand)
        stats['ownersPotential'] += len(cidx)
        for j,i in cidx:
            B=bernstein_controls(S,int(j),int(i))
            if B.min() <= 0.0 <= B.max() and hidden_zero_possible(B):
                stats['hidden'] += 1
                if len(stats['hidden_examples'])<8:
                    stats['hidden_examples'].append((step,int(i),int(j),float(B.min()),float(B.max())))
    return stats


def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('base',nargs='?',default='runs/0493x16o_q2_edge_endpoint_qualification')
    ap.add_argument('--nx',type=int,default=128); ap.add_argument('--ny',type=int,default=64)
    ap.add_argument('--lx',type=float,default=0.5); ap.add_argument('--ly',type=float,default=0.25)
    args=ap.parse_args(); base=Path(args.base)
    missing=[]; allstats=[]
    for label,rel,static_curve in CASES:
        p=base/rel
        if not p.is_file(): missing.append(str(p)); continue
        print(f'[x16p-preflight] analyze {label}: {p}',flush=True)
        allstats.append(analyze_case(label,p,static_curve,args.nx,args.ny,args.lx,args.ly))
    if missing:
        print('ERROR missing required x16o qualification files:',file=sys.stderr)
        for p in missing: print('  '+p,file=sys.stderr)
        return 2
    maxuniq=max(s['maxUniqueRoots'] for s in allstats)
    maxraw=max(s['maxRawRoots'] for s in allstats)
    maxedge=max(s['maxPerEdge'] for s in allstats)
    gt4=sum(s['gt4'] for s in allstats); degen=sum(s['degenerate'] for s in allstats)
    tangent=sum(s['tangent'] for s in allstats); hidden=sum(s['hidden'] for s in allstats)
    PASS=(maxuniq<=4 and maxedge<=2 and gt4==0 and degen==0 and tangent==0 and hidden==0)
    outdir=base/'analysis'; outdir.mkdir(parents=True,exist_ok=True)
    out=outdir/'summary_0493x16p_q2_topology_preflight.txt'
    lines=[
      '0493x16p Q2 topology capacity preflight',
      f'status={"PASS" if PASS else "REVIEW"}',
      'physicsModified=NO',
      'sourceModified=NO',
      'criterion=maxUniqueBoundaryRoots<=4; maxRootsPerEdge<=2; noDegenerateEdge; noTangentEdge; noHiddenInteriorContour',
      f'grid={args.nx}x{args.ny}',f'domain={args.lx}x{args.ly}',
      f'maxRawBoundaryRootsPerOwner={maxraw}',f'maxUniqueBoundaryRootsPerOwner={maxuniq}',
      f'maxRootsOnSingleEdge={maxedge}',f'ownersWithUniqueRootsGt4={gt4}',
      f'degenerateEdgeOccurrences={degen}',f'tangentEdgeOccurrences={tangent}',
      f'hiddenInteriorContourCandidates={hidden}',
      f'bufferTwoSegmentsCapacity={"PASS" if PASS else "REVIEW"}',
    ]
    for s in allstats:
      lines += ['',f'[{s["label"]}]',f'rows={s["rows"]}',f'maxRawBoundaryRoots={s["maxRawRoots"]}',
                f'maxUniqueBoundaryRoots={s["maxUniqueRoots"]}',f'maxRootsPerEdge={s["maxPerEdge"]}',
                f'ownersWithUniqueRootsGt4={s["gt4"]}',f'degenerateEdges={s["degenerate"]}',
                f'tangentEdges={s["tangent"]}',f'hiddenInteriorContourCandidates={s["hidden"]}',
                f'worst={s["worst"]}']
      if s['gt4_examples']: lines.append('gt4Examples='+repr(s['gt4_examples']))
      if s['hidden_examples']: lines.append('hiddenExamples='+repr(s['hidden_examples']))
    out.write_text('\n'.join(lines)+'\n')
    print('\n'.join(lines))
    print(f'\n[x16p-preflight] summary={out}')
    return 0 if PASS else 3

if __name__=='__main__':
    raise SystemExit(main())
