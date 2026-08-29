#!/usr/bin/env python3
from __future__ import annotations
import argparse, csv, json, math, re, struct, sys, time
from array import array
from pathlib import Path

MAGIC=b"SRCMPCD_STATE"+b"\0"*(16-len("SRCMPCD_STATE"))
STEP_RE=re.compile(r"state_step_(\d+)\.smpcd$")

def parse_kv(path:Path):
    d={}
    for raw in path.read_text(errors='replace').splitlines():
        s=raw.strip()
        if not s or s.startswith('#') or '=' not in s: continue
        k,v=s.split('=',1); d[k.strip()]=v.strip()
    return d

def as_float(d,k,default=None):
    if k not in d:
        if default is None: raise KeyError(k)
        return default
    return float(d[k])
def as_int(d,k,default=None): return int(round(as_float(d,k,default)))
def truthy(s): return str(s).strip().lower() in ('1','true','yes','on')

def find_params(root:Path):
    for p in (root/'output'/'params_used.kv', root/'params_used.kv'):
        if p.exists(): return p
    q=list((root/'params').glob('*.kv')) if (root/'params').exists() else []
    if len(q)==1:return q[0]
    raise SystemExit(f"no params_used.kv / unique params under {root}")

def read_arr(f,code,n):
    a=array(code); a.fromfile(f,n)
    if len(a)!=n: raise RuntimeError('truncated state')
    return a

def read_state(path:Path):
    with path.open('rb') as f:
        if f.read(16)!=MAGIC: raise RuntimeError(f'{path}: bad magic')
        version,endian,dim,layout,n,has_type,has_mass,reserved_count,type_bytes=struct.unpack('<IIIIQIIII',f.read(40))
        if (version,endian,dim,layout)!=(2,0x01020304,2,1): raise RuntimeError(f'{path}: unsupported header')
        if reserved_count: f.read(8*reserved_count)
        x=read_arr(f,'d',n); y=read_arr(f,'d',n); vx=read_arr(f,'d',n); vy=read_arr(f,'d',n)
        typ=read_arr(f,'I',n) if has_type else None
        mass=read_arr(f,'d',n) if has_mass else None
        if has_type and type_bytes!=4: raise RuntimeError('unsupported type width')
        role=read_arr(f,'B',n)
    return x,y,typ,mass,role

def zeros_d(n): return array('d',[0.0])*n
def zeros_b(n): return array('B',[0])*n

def clamp01(x): return 0.0 if x<0 else (1.0 if x>1 else x)

def deposit_fill(path,nx,ny,Lx,Ly,liquid_type,ref_mass):
    x,y,typ,mass,role=read_state(path)
    dx=Lx/nx;dy=Ly/ny;n=nx*ny
    cellmass=zeros_d(n); active_mass=0.0; active_count=0; sx=0.0
    for i in range(len(x)):
        if role[i]!=1: continue
        if typ is not None and typ[i]!=liquid_type: continue
        w=1.0 if mass is None else mass[i]
        ix=int(math.floor(x[i]/dx)); iy=int(math.floor(y[i]/dy))
        if ix<0: ix=0
        elif ix>=nx: ix=nx-1
        if iy<0: iy=0
        elif iy>=ny: iy=ny-1
        cellmass[iy*nx+ix]+=w
        active_mass+=w; active_count+=1; sx+=w*x[i]
    fill=zeros_d(n)
    inv=1.0/ref_mass
    for c in range(n): fill[c]=cellmass[c]*inv
    return fill,active_mass,active_count,sx/active_mass

def physical_alpha(raw,nx,ny,lmbda=.125,periodicX=False,periodicY=False):
    n=nx*ny; g=zeros_d(n)
    for c in range(n): g[c]=clamp01(raw[c])
    out=zeros_d(n)
    for iy in range(ny):
        row=iy*nx
        for ix in range(nx):
            c=row+ix; cen=g[c]; s=0.0
            if periodicX or ix>0:
                w=row+((ix-1)%nx); s+=g[w]-cen
            if periodicX or ix<nx-1:
                e=row+((ix+1)%nx); s+=g[e]-cen
            if periodicY or iy>0:
                ss=((iy-1)%ny)*nx+ix; s+=g[ss]-cen
            if periodicY or iy<ny-1:
                nn=((iy+1)%ny)*nx+ix; s+=g[nn]-cen
            out[c]=cen+lmbda*s
    return g,out

def sample_clamp(a,ix,iy,nx,ny,periodicX=False,periodicY=False):
    if periodicX: ix%=nx
    else: ix=0 if ix<0 else (nx-1 if ix>=nx else ix)
    if periodicY: iy%=ny
    else: iy=0 if iy<0 else (ny-1 if iy>=ny else iy)
    return a[iy*nx+ix]

def binomial_pass(a,nx,ny,periodicX=False,periodicY=False):
    # exact separable version of 3x3 [1 2 1]^T[1 2 1]/16, constant extension on non-periodic edges
    tmp=zeros_d(nx*ny); out=zeros_d(nx*ny)
    for iy in range(ny):
        r=iy*nx
        for ix in range(nx):
            l=a[r+(ix-1 if ix>0 else (nx-1 if periodicX else 0))]
            c=a[r+ix]
            rr=a[r+(ix+1 if ix<nx-1 else (0 if periodicX else nx-1))]
            tmp[r+ix]=(l+2*c+rr)*0.25
    for iy in range(ny):
        sm=(iy-1 if iy>0 else (ny-1 if periodicY else 0))*nx
        r=iy*nx
        nm=(iy+1 if iy<ny-1 else (0 if periodicY else ny-1))*nx
        for ix in range(nx): out[r+ix]=(tmp[sm+ix]+2*tmp[r+ix]+tmp[nm+ix])*0.25
    return out

def p3_curvature(alpha,nx,ny,dx,dy,periodicX=False,periodicY=False):
    a=alpha
    for _ in range(3): a=binomial_pass(a,nx,ny,periodicX,periodicY)
    nxv=zeros_d(nx*ny); nyv=zeros_d(nx*ny)
    for iy in range(ny):
        for ix in range(nx):
            nw=sample_clamp(a,ix-1,iy+1,nx,ny,periodicX,periodicY)
            nn=sample_clamp(a,ix,iy+1,nx,ny,periodicX,periodicY)
            ne=sample_clamp(a,ix+1,iy+1,nx,ny,periodicX,periodicY)
            ww=sample_clamp(a,ix-1,iy,nx,ny,periodicX,periodicY)
            ee=sample_clamp(a,ix+1,iy,nx,ny,periodicX,periodicY)
            sw=sample_clamp(a,ix-1,iy-1,nx,ny,periodicX,periodicY)
            ss=sample_clamp(a,ix,iy-1,nx,ny,periodicX,periodicY)
            se=sample_clamp(a,ix+1,iy-1,nx,ny,periodicX,periodicY)
            gx=(3*(ne-nw)+10*(ee-ww)+3*(se-sw))/(32*dx)
            gy=(3*(nw-sw)+10*(nn-ss)+3*(ne-se))/(32*dy)
            g=math.hypot(gx,gy); c=iy*nx+ix
            if g*min(dx,dy)>1e-12: nxv[c]=-gx/g; nyv[c]=-gy/g
    cur=zeros_d(nx*ny)
    for iy in range(ny):
        for ix in range(nx):
            nxNW=sample_clamp(nxv,ix-1,iy+1,nx,ny,periodicX,periodicY)
            nxNE=sample_clamp(nxv,ix+1,iy+1,nx,ny,periodicX,periodicY)
            nxW=sample_clamp(nxv,ix-1,iy,nx,ny,periodicX,periodicY)
            nxE=sample_clamp(nxv,ix+1,iy,nx,ny,periodicX,periodicY)
            nxSW=sample_clamp(nxv,ix-1,iy-1,nx,ny,periodicX,periodicY)
            nxSE=sample_clamp(nxv,ix+1,iy-1,nx,ny,periodicX,periodicY)
            nyNW=sample_clamp(nyv,ix-1,iy+1,nx,ny,periodicX,periodicY)
            nyN=sample_clamp(nyv,ix,iy+1,nx,ny,periodicX,periodicY)
            nyNE=sample_clamp(nyv,ix+1,iy+1,nx,ny,periodicX,periodicY)
            nySW=sample_clamp(nyv,ix-1,iy-1,nx,ny,periodicX,periodicY)
            nyS=sample_clamp(nyv,ix,iy-1,nx,ny,periodicX,periodicY)
            nySE=sample_clamp(nyv,ix+1,iy-1,nx,ny,periodicX,periodicY)
            dnx=(3*(nxNE-nxNW)+10*(nxE-nxW)+3*(nxSE-nxSW))/(32*dx)
            dny=(3*(nyNW-nySW)+10*(nyN-nyS)+3*(nyNE-nySE))/(32*dy)
            cur[iy*nx+ix]=dnx+dny
    return cur

def carrier_mask(raw,nx,ny,minfill,periodicX=False,periodicY=False):
    n=nx*ny; rawm=zeros_b(n)
    for c in range(n): rawm[c]=1 if raw[c]>0.0 and raw[c]>=minfill else 0
    reg=zeros_b(n)
    for iy in range(ny):
        for ix in range(nx):
            c=iy*nx+ix; active=bool(rawm[c])
            if not active:
                enclosed=True; cnt=0
                if periodicX or ix>0:
                    q=iy*nx+((ix-1)%nx); enclosed &= bool(rawm[q]); cnt+=1
                if periodicX or ix<nx-1:
                    q=iy*nx+((ix+1)%nx); enclosed &= bool(rawm[q]); cnt+=1
                if periodicY or iy>0:
                    q=((iy-1)%ny)*nx+ix; enclosed &= bool(rawm[q]); cnt+=1
                if periodicY or iy<ny-1:
                    q=((iy+1)%ny)*nx+ix; enclosed &= bool(rawm[q]); cnt+=1
                active=enclosed and cnt>=2
            reg[c]=1 if active else 0
    return reg

def crossings_and_traction(alpha,curv,carrier,nx,ny,dx,dy,kmax,xcm,H,periodicX=False,periodicY=False):
    pressure=zeros_b(nx*ny)
    for c in range(nx*ny): pressure[c]=1 if carrier[c] and alpha[c]>=.5 else 0
    stats={'interfaceFaces':0,'represented':0,'uncovered':0,'truncation':0,'clipped':0,'rawMax':0.0,'effMax':0.0,'pressureCells':sum(pressure),'carrierCells':sum(carrier)}
    accum={}
    for side in ('L','R'):
        for key in ('rawX','effX','rawXclip','effXclip','rawXunclip','effXunclip'):
            accum[f'{side}_{key}']=0.0
        accum[f'{side}_xFaces']=0;accum[f'{side}_xClipped']=0
    faces=[]
    def proc(c,q,axis,ix,iy):
        ac=alpha[c]; aq=alpha[q]
        cHigh=ac>=.5 and aq<.5; qHigh=aq>=.5 and ac<.5; crossing=cHigh or qHigh
        pc=bool(pressure[c]);pq=bool(pressure[q])
        if crossing: stats['interfaceFaces']+=1
        if pc and pq: return
        if pc or pq:
            if not crossing:
                stats['truncation']+=1; return
            ah=ac if cHigh else aq; al=aq if cHigh else ac; den=ah-al
            if den<=1e-14:return
            theta=(ah-.5)/den
            high=c if cHigh else q; low=q if cHigh else c
            kr=(1-theta)*curv[high]+theta*curv[low]
            if not math.isfinite(kr): return
            ke=max(-kmax,min(kmax,kr)) if kmax>0 else kr
            clip=kmax>0 and abs(kr)>kmax
            stats['represented']+=1; stats['clipped']+=int(clip);stats['rawMax']=max(stats['rawMax'],abs(kr));stats['effMax']=max(stats['effMax'],abs(ke))
            if axis=='x':
                # c is west, q east; outward A->B axis sign is + if liquid/high is c, else -.
                sign=1.0 if cHigh else -1.0; xm=(ix+1)*dx; ym=(iy+.5)*dy
                side='L' if xm<xcm else 'R'; contribR=kr*sign*dy;contribE=ke*sign*dy
                accum[f'{side}_rawX']+=contribR;accum[f'{side}_effX']+=contribE;accum[f'{side}_xFaces']+=1
                if clip:
                    accum[f'{side}_rawXclip']+=contribR;accum[f'{side}_effXclip']+=contribE;accum[f'{side}_xClipped']+=1
                else:
                    accum[f'{side}_rawXunclip']+=contribR;accum[f'{side}_effXunclip']+=contribE
                faces.append((side,xm,ym,kr,ke,int(clip),sign,theta,contribR,contribE))
            return
        if crossing: stats['uncovered']+=1
    for iy in range(ny):
        for ix in range(nx):
            c=iy*nx+ix
            if periodicX or ix<nx-1:
                q=iy*nx+((ix+1)%nx); proc(c,q,'x',ix,iy)
            if periodicY or iy<ny-1:
                q=((iy+1)%ny)*nx+ix; proc(c,q,'y',ix,iy)
    for side in ('L','R'):
        # inward force proxy is - integral kappa*n for left? Magnitude is enough.
        pass
    rawratio=(abs(accum['L_rawX'])+abs(accum['R_rawX']))/4.0
    effratio=(abs(accum['L_effX'])+abs(accum['R_effX']))/4.0
    accum['rawRatioTo2Sigma']=rawratio;accum['effRatioTo2Sigma']=effratio;accum['clipRetention']=effratio/rawratio if rawratio>0 else math.nan
    return stats,accum,faces

def infer_thickness_cells(root:Path):
    cands = sorted((root/'init').glob('*.smpcd.json')) if (root/'init').exists() else []
    for p in cands:
        try:
            j=json.loads(p.read_text())
            v=float(j.get('thicknessCells', math.nan))
            if math.isfinite(v) and v>0:return v
        except Exception:
            pass
    return math.nan

def q50_edges_from_raw(raw,nx,ny,dx,ref_mass,xcm,thickness_cells):
    line=[0.0]*nx
    # raw fill * ref mass is cell mass; sum over y.
    for iy in range(ny):
        r=iy*nx
        for ix in range(nx): line[ix]+=raw[r+ix]*ref_mass
    sm=[0.0]*nx
    for i in range(nx):
        s=3*line[i]
        if i>=1:s+=2*line[i-1]
        if i+1<nx:s+=2*line[i+1]
        if i>=2:s+=line[i-2]
        if i+2<nx:s+=line[i+2]
        sm[i]=s/9
    if not (math.isfinite(thickness_cells) and thickness_cells>0):
        return math.nan,math.nan
    nominal=ref_mass*thickness_cells
    target=.5*nominal; split=min(nx-2,max(1,int(xcm/dx)))
    le=[];ri=[]
    for i in range(nx-1):
        a,b=sm[i],sm[i+1];x0=(i+.5)*dx;x1=(i+1.5)*dx
        if a<target<=b and i<split:
            q=.5 if b==a else (target-a)/(b-a);le.append(x0+q*(x1-x0))
        if a>=target>b and i>=split-1:
            q=.5 if b==a else (target-a)/(b-a);ri.append(x0+q*(x1-x0))
    return (min(le),max(ri)) if le and ri else (math.nan,math.nan)

def read_csv_steps(path):
    if not path.exists(): return {}
    out={}
    with path.open(newline='') as f:
        for r in csv.DictReader(f):
            try: out[int(float(r['step']))]=r
            except: pass
    return out

def fget(r,k,default=math.nan):
    try:return float(r[k])
    except:return default

def iget(r,k,default=-1):
    try:return int(round(float(r[k])))
    except:return default

def relerr(a,b): return abs(a-b)/max(1e-30,abs(b))

def validation(recon,geom,stencil,lim):
    checks=[]
    def add(name,a,b,tol,kind='rel'):
        e=abs(a-b) if kind=='abs' else relerr(a,b);checks.append((name,a,b,e,tol,e<=tol))
    if geom:
        add('rawFillSum',recon['rawFillSum'],fget(geom,'rawFillSum'),2e-5)
        add('boundedGeometrySourceSum',recon['boundedSum'],fget(geom,'boundedGeometrySourceSum'),2e-5)
        add('filteredFillSum',recon['filteredSum'],fget(geom,'filteredFillSum'),2e-5)
        add('interfaceFaces',recon['interfaceFaces'],iget(geom,'interfaceFaces'),0.02)
    if stencil:
        add('carrierActiveCells',recon['carrierCells'],iget(stencil,'carrierActiveCells'),0.02)
        add('pressureActiveCells',recon['pressureCells'],iget(stencil,'pressureActiveCells'),0.02)
        add('representedInterfaceFaces',recon['represented'],iget(stencil,'representedInterfaceFaces'),0.02)
        add('uncoveredInterfaceFaces',recon['uncovered'],iget(stencil,'uncoveredInterfaceFaces'),3,'abs')
        add('carrierTruncationFaces',recon['truncation'],iget(stencil,'carrierTruncationFaces'),5,'abs')
    if lim:
        add('capillaryFaces',recon['represented'],iget(lim,'capillaryFaces'),0.02)
        # clipped can be small: allow max(3 faces, 10% relative)
        b=iget(lim,'clippedFaces'); a=recon['clipped']; e=abs(a-b)/max(1,b); ok=abs(a-b)<=3 or e<=.10; checks.append(('clippedFaces',a,b,e,.10,ok))
        add('rawKappaAbsMax',recon['rawMax'],fget(lim,'capillaryKappaRawAbsMax'),0.10)
        add('effectiveKappaAbsMax',recon['effMax'],fget(lim,'capillaryKappaEffectiveAbsMax'),0.03)
    if not checks:return 'NO_REFERENCE',checks
    bad=sum(not z[5] for z in checks)
    if bad==0:return 'PASS',checks
    # REVIEW if geometry and represented counts are within 10%, otherwise INVALID.
    severe=[]
    for z in checks:
        if z[0] in ('interfaceFaces','representedInterfaceFaces','capillaryFaces') and z[3]>.10: severe.append(z)
        if z[0] in ('rawFillSum','boundedGeometrySourceSum','filteredFillSum') and z[3]>.01: severe.append(z)
    return ('INVALID' if severe else 'REVIEW'),checks

def write_csv(path,rows):
    if not rows:return
    keys=[]
    for r in rows:
        for k in r:
            if k not in keys:keys.append(k)
    with path.open('w',newline='') as f:
        w=csv.DictWriter(f,fieldnames=keys);w.writeheader();w.writerows(rows)

def main():
    ap=argparse.ArgumentParser(description='0493x13n offline reconstruction of x6c/x9 p3/x9r rim traction from existing SMPD dumps')
    ap.add_argument('--run-root',type=Path,required=True)
    ap.add_argument('--steps',default='',help='comma/space separated exact dump steps; default: all dumps')
    ap.add_argument('--outdir',type=Path,default=None)
    a=ap.parse_args(); root=a.run_root
    kv=parse_kv(find_params(root))
    Lx=as_float(kv,'Lx');Ly=as_float(kv,'Ly');nx=as_int(kv,'Nx');ny=as_int(kv,'Ny');dx=Lx/nx;dy=Ly/ny
    if abs(dx-dy)>1e-12:raise SystemExit('square cells required for this audit')
    sigma=as_float(kv,'surfaceTensionSigma');rmin=as_float(kv,'surfaceTensionMinRadiusCells');kmax=1/(rmin*min(dx,dy)) if rmin>0 else 0
    contact=as_float(kv,'phaseInterfaceContactAngleDegrees',-1)
    if contact>=0:raise SystemExit('this offline audit intentionally supports contactAngle=-1 only')
    sel=kv.get('phaseInterfaceASelector','')
    m=re.fullmatch(r'type:(\d+)',sel); liquid_type=int(m.group(1)) if m else 1
    ref=None
    for key,val in kv.items():
        if key.startswith('species') and key[7:].isdigit():
            tok=val.split()
            if tok and int(tok[0])==liquid_type: ref=float(tok[-1]);break
    if ref is None:raise SystemExit('cannot infer phase-A reference cell mass from species definitions')
    minfill=as_float(kv,'speciesQ6MinOccupancyFraction')
    thickness_cells=infer_thickness_cells(root)
    periodicX=kv.get('bcX','').strip().lower()=='periodic';periodicY=kv.get('bcY','').strip().lower()=='periodic'
    dumps={}
    for p in (root/'output').glob('state_step_*.smpcd'):
        mm=STEP_RE.fullmatch(p.name)
        if mm:dumps[int(mm.group(1))]=p
    if a.steps.strip():
        req=[int(x) for x in re.split(r'[ ,;]+',a.steps.strip()) if x]
    else:req=sorted(dumps)
    missing=[s for s in req if s not in dumps]
    if missing:raise SystemExit(f'missing exact dumps: {missing}')
    geomrows=read_csv_steps(root/'output'/'cuda_phase_geometry_resident_0493x6c.csv')
    strows=read_csv_steps(root/'output'/'cuda_phase_interface_stencil_0493x6f.csv')
    limrows=read_csv_steps(root/'output'/'cuda_surface_tension_limiter_0493x9r.csv')
    out=a.outdir or root/'analysis_rim_traction_0493x13n';out.mkdir(parents=True,exist_ok=True)
    summaries=[]; face_rows=[]; report=[]
    report += ['0493x13n — offline x9r rim-traction reconstruction','===================================================',f'runRoot={root}',f'grid={nx}x{ny} L=({Lx},{Ly}) h={dx} liquidType={liquid_type} refCellMass={ref}',f'sigma={sigma} RminCells={rmin} kappaLimit={kmax} minFill={minfill} periodic=({int(periodicX)},{int(periodicY)}) thicknessCells={thickness_cells}','Contract: reconstruct x6f2-bounded x6c alpha, x9d p3 curvature, x5a carrier mask, represented x6f crossings, then x9r face clipping.','Traction interpretation is allowed only when the validation gate is PASS/REVIEW with no major geometry mismatch.','']
    for step in req:
        t0=time.time();p=dumps[step]; print(f'[rim-traction] step={step} read/deposit {p.name}',flush=True)
        raw,M,N,xcm=deposit_fill(p,nx,ny,Lx,Ly,liquid_type,ref)
        rawsum=sum(raw); g,alpha=physical_alpha(raw,nx,ny,.125,periodicX,periodicY);bounded=sum(g);filtered=sum(alpha)
        carrier=carrier_mask(raw,nx,ny,minfill,periodicX,periodicY)
        print(f'[rim-traction] step={step} p3 curvature...',flush=True)
        curv=p3_curvature(alpha,nx,ny,dx,dy,periodicX,periodicY)
        stats,acc,faces=crossings_and_traction(alpha,curv,carrier,nx,ny,dx,dy,kmax,xcm,64*dx,periodicX,periodicY)
        recon={**stats,'rawFillSum':rawsum,'boundedSum':bounded,'filteredSum':filtered}
        status,checks=validation(recon,geomrows.get(step),strows.get(step),limrows.get(step))
        xl,xr=q50_edges_from_raw(raw,nx,ny,dx,ref,xcm,thickness_cells)
        row={'step':step,'stateFile':p.name,'validation':status,'mass':M,'activeParticles':N,'xCM':xcm,'xLeft_q50':xl,'xRight_q50':xr,
             **recon,**acc,'elapsedSeconds':time.time()-t0}
        # solver refs
        if limrows.get(step):
            lr=limrows[step];row.update(solverCapillaryFaces=iget(lr,'capillaryFaces'),solverClippedFaces=iget(lr,'clippedFaces'),solverClipFraction=fget(lr,'clipFraction'),solverRawKappaAbsMax=fget(lr,'capillaryKappaRawAbsMax'))
        if strows.get(step):
            sr=strows[step];row.update(solverRepresentedFaces=iget(sr,'representedInterfaceFaces'),solverUncoveredFaces=iget(sr,'uncoveredInterfaceFaces'),solverTruncationFaces=iget(sr,'carrierTruncationFaces'))
        summaries.append(row)
        for side,xm,ym,kr,ke,clip,sign,theta,cr,ce in faces:
            face_rows.append({'step':step,'side':side,'x':xm,'y':ym,'kappaRaw':kr,'kappaEffective':ke,'clipped':clip,'axisNormalX':sign,'theta':theta,'rawGeomContributionX':cr,'effectiveGeomContributionX':ce})
        report += [f'[step {step}] validation={status} elapsed={row["elapsedSeconds"]:.1f}s',f'  geometry: interfaceFaces={stats["interfaceFaces"]} represented={stats["represented"]} uncovered={stats["uncovered"]} truncation={stats["truncation"]}',f'  limiter: clipped={stats["clipped"]}/{stats["represented"]} ({stats["clipped"]/max(1,stats["represented"]):.6g}) rawMax={stats["rawMax"]:.9g} effMax={stats["effMax"]:.9g}',f'  x-resultant raw: L={acc["L_rawX"]:.12g} R={acc["R_rawX"]:.12g}; mean |Rkappa_x|/2={acc["rawRatioTo2Sigma"]:.12g}',f'  x-resultant eff: L={acc["L_effX"]:.12g} R={acc["R_effX"]:.12g}; mean |Rkappa_x|/2={acc["effRatioTo2Sigma"]:.12g}; retention={acc["clipRetention"]:.12g}']
        for name,aa,bb,e,tol,ok in checks: report.append(f'    validate {name}: recon={aa:.12g} solver={bb:.12g} err={e:.6g} tol={tol:.6g} {"PASS" if ok else "FAIL"}')
        report.append('')
    write_csv(out/'rim_traction_summary.csv',summaries);write_csv(out/'rim_traction_xfaces.csv',face_rows)
    rank={'PASS':0,'REVIEW':1,'NO_REFERENCE':2,'INVALID':3}
    overall=max((r['validation'] for r in summaries), key=lambda s: rank.get(s,99)) if summaries else 'INVALID'
    report += [f'OVERALL_VALIDATION={overall}',
               'If INVALID: do not interpret the reconstructed traction as solver-equivalent; return the report so the mismatch can be diagnosed before any new run.']
    (out/'rim_traction_report.txt').write_text('\n'.join(report)+'\n')
    print(f'[rim-traction] OVERALL_VALIDATION={overall}')
    print(out/'rim_traction_report.txt')
    return 0
if __name__=='__main__': raise SystemExit(main())
