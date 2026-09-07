#!/usr/bin/env python3
from __future__ import annotations
import argparse, json, math, random, struct, sys
from array import array
from pathlib import Path

MAGIC = b"SRCMPCD_STATE" + b"\0" * (16-len("SRCMPCD_STATE"))

def pint(x):
    v=int(x)
    if v<=0: raise argparse.ArgumentTypeError('expected positive integer')
    return v

def nint(x):
    v=int(x)
    if v<0: raise argparse.ArgumentTypeError('expected non-negative integer')
    return v

def pfloat(x):
    v=float(x)
    if not math.isfinite(v) or v<=0: raise argparse.ArgumentTypeError('expected finite positive number')
    return v

def nnfloat(x):
    v=float(x)
    if not math.isfinite(v) or v<0: raise argparse.ArgumentTypeError('expected finite non-negative number')
    return v

def paired(rng,n,m,kbt,ux,uy):
    if n<=0: return []
    if kbt<=0 or n==1: return [(ux,uy)]*n
    q=[]
    for _ in range(n//2):
        a,b=rng.gauss(0,1),rng.gauss(0,1); q.extend(((a,b),(-a,-b)))
    if n%2: q.append((0.0,0.0))
    s=sum(a*a+b*b for a,b in q)
    c=math.sqrt(2*n*kbt/(m*s)) if s>0 else 0.0
    return [(ux+c*a,uy+c*b) for a,b in q]

def positions(ix,iy,n,h):
    def cp(start,avoid=-1):
        for off in range(max(1,n)):
            c=1+((start+off-1)%max(1,n))
            if c!=avoid and math.gcd(c,n)==1: return c
        return 1
    ax=cp(3); ay=cp(7,ax)
    return [((ix+(((ax*k)%n)+.5)/n)*h,(iy+(((ay*k)%n)+.5)/n)*h) for k in range(n)]

def write_state(path,x,y,vx,vy,typ,mass,role):
    n=len(x); path.parent.mkdir(parents=True,exist_ok=True)
    reserved=[0]*8; reserved[0]=1; reserved[1]=1
    if sys.byteorder=='big':
        for a in (x,y,vx,vy,typ,mass): a.byteswap()
    try:
        with path.open('wb') as f:
            f.write(MAGIC); f.write(struct.pack('<IIIIQIIII',2,0x01020304,2,1,n,1,1,8,4)); f.write(struct.pack('<8Q',*reserved))
            for a in (x,y,vx,vy,typ,mass): a.tofile(f)
            f.write(role)
    finally:
        if sys.byteorder=='big':
            for a in (x,y,vx,vy,typ,mass): a.byteswap()

def aligned(v,h,name):
    if abs(v/h-round(v/h))>1e-9: raise ValueError(f'{name}={v:.17g} not cell-face aligned')

def inside(x,y,x0,y0,x1,y1): return x0<=x<x1 and y0<=y<y1

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--output',type=Path,required=True); ap.add_argument('--chi-output',type=Path,required=True); ap.add_argument('--geometry-svg',type=Path)
    ap.add_argument('--chi-only',action='store_true')
    ap.add_argument('--Lx',type=pfloat,default=2.0); ap.add_argument('--Ly',type=pfloat,default=1.0); ap.add_argument('--nx',type=pint,default=512); ap.add_argument('--ny',type=pint,default=256); ap.add_argument('--gamma',type=pint,default=20)
    ap.add_argument('--liquid-type',type=pint,default=1); ap.add_argument('--gas-type',type=pint,default=2); ap.add_argument('--liquid-mass',type=pfloat,default=1.0); ap.add_argument('--gas-mass',type=pfloat,default=.1); ap.add_argument('--liquid-kBT',type=nnfloat,default=.02); ap.add_argument('--gas-kBT',type=nnfloat,default=.08); ap.add_argument('--seed',type=int,default=493215)
    ap.add_argument('--liquid-center-y',type=float,default=.5); ap.add_argument('--liquid-diameter-cells',type=pint,default=12); ap.add_argument('--liquid-length-cells',type=pint,default=64); ap.add_argument('--liquid-wall-cells',type=pint,default=4); ap.add_argument('--liquid-prime-extra-cells',type=nint,default=4); ap.add_argument('--liquid-initial-ux',type=float,default=0.0)
    ap.add_argument('--air-center-x-cells',type=pint,default=88); ap.add_argument('--air-top-diameter-cells',type=pint,default=12); ap.add_argument('--air-bottom-diameter-cells',type=pint,default=12); ap.add_argument('--air-top-length-cells',type=pint,default=80); ap.add_argument('--air-bottom-length-cells',type=pint,default=80); ap.add_argument('--air-wall-cells',type=pint,default=4); ap.add_argument('--air-feed-clearance-cells',type=nint,default=4)
    a=ap.parse_args()
    if a.gamma<2: ap.error('gamma must be >=2')
    if a.liquid_type==a.gas_type: ap.error('liquid and gas types must differ')
    hx=a.Lx/a.nx; hy=a.Ly/a.ny
    if abs(hx-hy)>1e-12*max(1,abs(hx),abs(hy)): ap.error('square cells required')
    h=hx
    lc=a.liquid_center_y; ld=a.liquid_diameter_cells*h; lw=a.liquid_wall_cells*h; lx=a.liquid_length_cells*h
    ly0,ly1=lc-ld/2,lc+ld/2; loy0,loy1=ly0-lw,ly1+lw
    cx=a.air_center_x_cells*h; td=a.air_top_diameter_cells*h; bd=a.air_bottom_diameter_cells*h; aw=a.air_wall_cells*h; clear=a.air_feed_clearance_cells*h
    tfy=a.Ly-clear-aw-td/2; bfy=clear+aw+bd/2
    tex=tfy-a.air_top_length_cells*h; bex=bfy+a.air_bottom_length_cells*h
    tx0,tx1=cx-td/2,cx+td/2; bx0,bx1=cx-bd/2,cx+bd/2
    tf0,tf1=tfy-td/2,tfy+td/2; bf0,bf1=bfy-bd/2,bfy+bd/2
    try:
        for n,v in [('ly0',ly0),('ly1',ly1),('loy0',loy0),('loy1',loy1),('lx',lx),('cx',cx),('tx0',tx0),('tx1',tx1),('bx0',bx0),('bx1',bx1),('tf0',tf0),('tf1',tf1),('bf0',bf0),('bf1',bf1),('tex',tex),('bex',bex)]: aligned(v,h,n)
    except ValueError as e: ap.error(str(e))
    if not (0<loy0<ly0<ly1<loy1<a.Ly): ap.error('liquid nozzle does not fit')
    if not (0<lx<cx-2*h<a.Lx): ap.error('air turn must be downstream of liquid exit')
    if not (0<bf0<bf1<bex<lc<tex<tf0<tf1<a.Ly): ap.error('air feed/nozzle geometry does not bracket liquid center')
    # Build chi as outer envelope minus L-shaped fluid corridor.
    chi=array('f'); counts={'liquid_nozzle':0,'air_top_L':0,'air_bottom_L':0}; solid=0
    for j in range(a.ny):
        y=(j+.5)*h
        for i in range(a.nx):
            x=(i+.5)*h
            liq=(inside(x,y,0,loy0,lx,loy1) and not inside(x,y,0,ly0,lx,ly1))
            ti_h=inside(x,y,0,tf0,cx+td/2,tf1); ti_v=inside(x,y,tx0,tex,tx1,tfy+td/2)
            to_h=inside(x,y,0,tf0-aw,cx+td/2+aw,tf1+aw); to_v=inside(x,y,tx0-aw,tex,tx1+aw,tfy+td/2+aw)
            top=(to_h or to_v) and not (ti_h or ti_v)
            bi_h=inside(x,y,0,bf0,cx+bd/2,bf1); bi_v=inside(x,y,bx0,bfy-bd/2,bx1,bex)
            bo_h=inside(x,y,0,bf0-aw,cx+bd/2+aw,bf1+aw); bo_v=inside(x,y,bx0-aw,bfy-bd/2-aw,bx1+aw,bex)
            bot=(bo_h or bo_v) and not (bi_h or bi_v)
            flags=(liq,top,bot); n=sum(map(int,flags))
            if n>1: ap.error(f'chi nozzle wall overlap at cell {i},{j}')
            chi.append(0.0 if n else 1.0); solid+=int(n>0)
            for k,f in zip(counts,flags): counts[k]+=int(f)
    a.chi_output.parent.mkdir(parents=True,exist_ok=True)
    if sys.byteorder=='big': chi.byteswap()
    try:
        with a.chi_output.open('wb') as f: chi.tofile(f)
    finally:
        if sys.byteorder=='big': chi.byteswap()
    prime=min(a.Lx,lx+a.liquid_prime_extra_cells*h)
    npart=nl=ng=0
    if not a.chi_only:
        rl=random.Random(a.seed^0x14A711); rg=random.Random(a.seed^0x14A722)
        X=array('d');Y=array('d');VX=array('d');VY=array('d');T=array('I');M=array('d');R=bytearray()
        for j in range(a.ny):
            yc=(j+.5)*h
            for i in range(a.nx):
                xc=(i+.5)*h; isl=xc<prime and ly0<=yc<ly1
                if isl: typ,m,k,u,v,r=a.liquid_type,a.liquid_mass,a.liquid_kBT,a.liquid_initial_ux,0.0,rl; nl+=a.gamma
                else: typ,m,k,u,v,r=a.gas_type,a.gas_mass,a.gas_kBT,0.0,0.0,rg; ng+=a.gamma
                for (px,py),(ux,uy) in zip(positions(i,j,a.gamma,h),paired(r,a.gamma,m,k,u,v)):
                    X.append(px);Y.append(py);VX.append(ux);VY.append(uy);T.append(typ);M.append(m);R.append(1)
        npart=len(X); write_state(a.output,X,Y,VX,VY,T,M,R)
    meta={'profile':'0493x14av_fix1_air_assisted_atomizer_2d','openBoundaryContract':'x-axis only; three segmented left inlets + right outlet','grid':{'Lx':a.Lx,'Ly':a.Ly,'Nx':a.nx,'Ny':a.ny,'h':h},'gamma':a.gamma,
          'liquid':{'type':a.liquid_type,'mass':a.liquid_mass,'kBT':a.liquid_kBT,'centerY':lc,'diameterCells':a.liquid_diameter_cells,'diameter':ld,'lengthCells':a.liquid_length_cells,'length':lx,'wallCells':a.liquid_wall_cells,'innerY':[ly0,ly1],'outerY':[loy0,loy1],'primeX':prime},
          'air':{'type':a.gas_type,'mass':a.gas_mass,'kBT':a.gas_kBT,'turnX':cx,'wallCells':a.air_wall_cells,'feedClearanceCells':a.air_feed_clearance_cells,'top':{'feedCenterY':tfy,'feedInnerY':[tf0,tf1],'diameter':td,'length':a.air_top_length_cells*h,'exitY':tex,'direction':'down'},'bottom':{'feedCenterY':bfy,'feedInnerY':[bf0,bf1],'diameter':bd,'length':a.air_bottom_length_cells*h,'exitY':bex,'direction':'up'}},
          'chi':{'fluid':1.0,'solid':0.0,'solidCells':solid,'solidByPart':counts},'initialState':{'particles':npart,'liquidParticles':nl,'gasParticles':ng,'chiOnly':a.chi_only}}
    if not a.chi_only: a.output.with_suffix(a.output.suffix+'.json').write_text(json.dumps(meta,indent=2)+'\n')
    a.chi_output.with_suffix(a.chi_output.suffix+'.json').write_text(json.dumps(meta,indent=2)+'\n')
    if a.geometry_svg:
        a.geometry_svg.parent.mkdir(parents=True,exist_ok=True); W,H=1000.,500.; sx,sy=W/a.Lx,H/a.Ly
        def rect(x0,y0,x1,y1,fill): return f'<rect x="{x0*sx:.2f}" y="{H-y1*sy:.2f}" width="{(x1-x0)*sx:.2f}" height="{(y1-y0)*sy:.2f}" fill="{fill}"/>'
        bg='#eef6ff'; wall='#555'; liq='#2a78c4'
        pieces=[rect(0,loy0,lx,loy1,wall),rect(0,ly0,prime,ly1,liq),rect(0,tf0-aw,cx+td/2+aw,tf1+aw,wall),rect(tx0-aw,tex,tx1+aw,tfy+td/2+aw,wall),rect(0,tf0,cx+td/2,tf1,bg),rect(tx0,tex,tx1,tfy+td/2,bg),rect(0,bf0-aw,cx+bd/2+aw,bf1+aw,wall),rect(bx0-aw,bfy-bd/2-aw,bx1+aw,bex,wall),rect(0,bf0,cx+bd/2,bf1,bg),rect(bx0,bfy-bd/2,bx1,bex,bg)]
        svg='<svg xmlns="http://www.w3.org/2000/svg" width="1000" height="500" viewBox="0 0 1000 500">\n'+f'<rect width="1000" height="500" fill="{bg}" stroke="#111" stroke-width="2"/>\n'+''.join(pieces)+'\n<text x="12" y="24" font-family="sans-serif" font-size="18">0493x14av-fix1: x-open only; L-shaped gas feeds</text>\n</svg>\n'
        a.geometry_svg.write_text(svg)
    print(f'[0493x14av-fix1-generate] grid={a.nx}x{a.ny} h={h:.9g} gamma={a.gamma} N={npart} chiOnly={int(a.chi_only)}')
    print(f'[0493x14av-fix1-generate] liquid D={ld:.9g} L={lx:.9g} exitX={lx:.9g}')
    print(f'[0493x14av-fix1-generate] top gas leftFeedY={tfy:.9g} D={td:.9g} terminalL={a.air_top_length_cells*h:.9g} exitY={tex:.9g}')
    print(f'[0493x14av-fix1-generate] bottom gas leftFeedY={bfy:.9g} D={bd:.9g} terminalL={a.air_bottom_length_cells*h:.9g} exitY={bex:.9g}')
    print(f'[0493x14av-fix1-generate] openAxis=x only turnX={cx:.9g} gap={tex-bex:.9g} chiSolidCells={solid}')
    return 0
if __name__=='__main__': raise SystemExit(main())
