#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
SEED="${SEED:-493215}"
source "$ROOT/scripts/src_mpcd_run_ok_common.sh"
suite_root_cd_0434

# Stand-alone support: the state/chi generator and the descriptive analyzer are
# embedded below and materialized only in /tmp for this process.  The only
# repository helper dependency intentionally retained is src_mpcd_run_ok_common.sh,
# which carries the qualified x14/Q6 parameter/export contract.
TMP_WORK="${TMPDIR:-/tmp}/src_mpcd_0493x14av_$$"
mkdir -p "$TMP_WORK"
GENERATOR="$TMP_WORK/generate_0493x14av_air_assisted_atomizer_state.py"
ANALYZER="$TMP_WORK/analyze_0493x14av_air_assisted_atomizer.py"
trap 'rm -rf "$TMP_WORK"' EXIT
cat > "$GENERATOR" <<'PYGEN'
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
PYGEN
cat > "$ANALYZER" <<'PYANA'
"""Offline diagnostics for the 0493x14av air-assisted atomizer demo.

The analysis is deliberately descriptive rather than a PASS/FAIL qualification:
it tracks liquid penetration, downstream spray width and connected liquid
components on the MPCD cell grid.  No pandas is used.
"""
from __future__ import annotations

import argparse
import csv
import json
import math
import re
import struct
from collections import deque
from pathlib import Path

import numpy as np

MAGIC = b"SRCMPCD_STATE" + b"\0" * (16 - len("SRCMPCD_STATE"))
STEP_RE = re.compile(r"state_step_(\d+)\.smpcd$")


def read_state(path: Path):
    with path.open("rb") as f:
        if f.read(16) != MAGIC:
            raise RuntimeError(f"{path}: invalid state magic")
        version, endian, dim, layout, n, has_type, _, real_bytes, type_bytes = struct.unpack("<IIIIQIIII", f.read(40))
        reserved = struct.unpack("<8Q", f.read(64))
        if endian != 0x01020304 or dim != 2 or layout != 1 or real_bytes != 8 or type_bytes != 4 or not has_type:
            raise RuntimeError(f"{path}: unsupported state format")
        def arr(dtype, count):
            a = np.fromfile(f, dtype=dtype, count=count)
            if a.size != count:
                raise RuntimeError(f"{path}: truncated array")
            return a
        x = arr("<f8", n); y = arr("<f8", n); vx = arr("<f8", n); vy = arr("<f8", n)
        typ = arr("<u4", n)
        mass = arr("<f8", n) if reserved[0] else np.ones(n, dtype=np.float64)
        role = np.fromfile(f, dtype=np.uint8, count=n) if reserved[1] else np.ones(n, dtype=np.uint8)
        if role.size != n:
            raise RuntimeError(f"{path}: truncated role")
    return x, y, vx, vy, typ, mass, role


def components_from_occupancy(occ: np.ndarray, threshold: int):
    wet = occ >= threshold
    ny, nx = wet.shape
    seen = np.zeros_like(wet, dtype=np.uint8)
    comps = []
    for iy in range(ny):
        for ix in range(nx):
            if not wet[iy, ix] or seen[iy, ix]:
                continue
            q = deque([(iy, ix)]); seen[iy, ix] = 1
            cells = 0; particles = 0; touches_left = False
            minx = nx; maxx = -1; miny = ny; maxy = -1
            while q:
                cy, cx = q.popleft()
                cells += 1; particles += int(occ[cy, cx])
                touches_left = touches_left or cx == 0
                minx = min(minx, cx); maxx = max(maxx, cx); miny = min(miny, cy); maxy = max(maxy, cy)
                for dy, dx in ((-1,0),(1,0),(0,-1),(0,1)):
                    yy, xx = cy+dy, cx+dx
                    if 0 <= yy < ny and 0 <= xx < nx and wet[yy,xx] and not seen[yy,xx]:
                        seen[yy,xx] = 1; q.append((yy,xx))
            comps.append((cells, particles, touches_left, minx, maxx, miny, maxy))
    return comps


def q(values: np.ndarray, p: float) -> float:
    return float(np.quantile(values, p)) if values.size else math.nan


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--run-root", type=Path, required=True)
    ap.add_argument("--Lx", type=float, required=True)
    ap.add_argument("--Ly", type=float, required=True)
    ap.add_argument("--nx", type=int, required=True)
    ap.add_argument("--ny", type=int, required=True)
    ap.add_argument("--gamma", type=float, required=True)
    ap.add_argument("--liquid-type", type=int, required=True)
    ap.add_argument("--liquid-nozzle-exit-x", type=float, required=True)
    ap.add_argument("--air-center-x", type=float, required=True)
    ap.add_argument("--air-diameter", type=float, required=True)
    ap.add_argument("--component-threshold-fraction", type=float, default=0.25)
    ap.add_argument("--min-detached-cells", type=int, default=2)
    args = ap.parse_args()

    dumps = []
    for path in sorted((args.run_root / "output").glob("state_step_*.smpcd")):
        m = STEP_RE.search(path.name)
        if m:
            dumps.append((int(m.group(1)), path))
    if not dumps:
        raise RuntimeError(f"no state_step_*.smpcd in {args.run_root/'output'}")

    hx, hy = args.Lx/args.nx, args.Ly/args.ny
    if abs(hx-hy) > 1e-12*max(1.0, abs(hx), abs(hy)):
        raise RuntimeError("square cells required")
    threshold = max(1, int(round(args.component_threshold_fraction * args.gamma)))
    downstream_x = args.air_center_x + 2.0 * args.air_diameter

    rows = []
    for step, path in dumps:
        x,y,vx,vy,typ,mass,role = read_state(path)
        mask = (role == 1) & (typ == args.liquid_type)
        xl = x[mask]; yl = y[mask]; vxl = vx[mask]; vyl = vy[mask]; ml = mass[mask]
        if xl.size == 0:
            continue
        ix = np.clip((xl/hx).astype(np.int64), 0, args.nx-1)
        iy = np.clip((yl/hy).astype(np.int64), 0, args.ny-1)
        occ = np.zeros((args.ny,args.nx), dtype=np.int32)
        np.add.at(occ, (iy,ix), 1)
        comps = components_from_occupancy(occ, threshold)
        detached = [c for c in comps if not c[2] and c[0] >= args.min_detached_cells]
        core = [c for c in comps if c[2]]
        downstream = xl >= downstream_x
        ydown = yl[downstream]
        mass_total = float(ml.sum())
        px_total = float(np.dot(ml, vxl))
        py_total = float(np.dot(ml, vyl))
        row = {
            "step": step,
            "liquidParticles": int(xl.size),
            "liquidMass": mass_total,
            "liquidX50": q(xl,0.50), "liquidX90": q(xl,0.90), "liquidX99": q(xl,0.99), "liquidXMax": float(xl.max()),
            "liquidY10": q(yl,0.10), "liquidY50": q(yl,0.50), "liquidY90": q(yl,0.90),
            "downstreamParticles": int(downstream.sum()),
            "downstreamY10": q(ydown,0.10), "downstreamY90": q(ydown,0.90),
            "downstreamWidth80": (q(ydown,0.90)-q(ydown,0.10)) if ydown.size else math.nan,
            "wetComponents": len(comps), "coreComponents": len(core), "detachedComponents": len(detached),
            "largestDetachedCells": max((c[0] for c in detached), default=0),
            "largestDetachedParticles": max((c[1] for c in detached), default=0),
            "meanLiquidVx": px_total/mass_total if mass_total>0 else math.nan,
            "meanLiquidVy": py_total/mass_total if mass_total>0 else math.nan,
        }
        rows.append(row)
        print(
            f"[0493x14av-analysis] step={step} Nliq={row['liquidParticles']} "
            f"x99={row['liquidX99']:.6g} width80={row['downstreamWidth80']:.6g} "
            f"components={row['wetComponents']} detached={row['detachedComponents']}"
        )

    outdir = args.run_root / "analysis"
    outdir.mkdir(parents=True, exist_ok=True)
    csv_path = outdir / "atomizer_history.csv"
    fields = list(rows[0].keys())
    with csv_path.open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fields)
        w.writeheader(); w.writerows(rows)

    last = rows[-1]
    report = {
        "status": "DEMONSTRATION_DIAGNOSTIC_ONLY",
        "runRoot": str(args.run_root),
        "componentThresholdParticles": threshold,
        "downstreamProbeX": downstream_x,
        "latest": last,
        "interpretation": {
            "detachedComponents": "number of >=min-detached-cells liquid components not connected to the left boundary",
            "downstreamWidth80": "y90-y10 of liquid particles downstream of airCenterX+2*airDiameter",
        },
    }
    (outdir / "atomizer_report.json").write_text(json.dumps(report, indent=2, allow_nan=True)+"\n")
    (outdir / "atomizer_report.txt").write_text(
        "0493x14av air-assisted atomizer demo\n"
        "=====================================\n"
        "Status: DEMONSTRATION_DIAGNOSTIC_ONLY\n"
        f"latest step={last['step']} liquidX99={last['liquidX99']:.9g} "
        f"downstreamWidth80={last['downstreamWidth80']:.9g} detachedComponents={last['detachedComponents']}\n"
        "No physical atomization PASS/FAIL criterion is asserted by this analyzer.\n"
    )
    print(f"[0493x14av-analysis] history={csv_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
PYANA
chmod +x "$GENERATOR" "$ANALYZER"

# No source-marker dependency: like run_ok_*, this runner relies on the common
# helper preflight plus the selected binary.  Generator/analyzer remain embedded.

# =============================================================================
# 0493x14av-s2 — AIR-ASSISTED ATOMIZER DEMONSTRATION (2-D, run_ok-homogeneous standalone runner)
#
# Geometry (chi-Darcy nozzle walls):
#
# LEFT FACE ONLY (current 0142 open-boundary contract):
#
#     gas inlet --->========\
#                           ||
#                           ||  top air nozzle
#                           \/
# liquid inlet --->===========> liquid jet ==================> RIGHT OUTLET
#                           /\
#                           ||  bottom air nozzle
#                           ||
#     gas inlet --->========/
#
# All THREE inlet reservoirs are segmented on the LEFT face.  Chi-Darcy
# L-shaped feed ducts turn the two gas streams through 90 degrees so that their
# terminal nozzle legs are perpendicular to the horizontal liquid nozzle.  This
# respects the current 0142 solver contract: open boundaries may occupy only one
# Cartesian axis at a time.  The full right face is the passive Neumann outlet.
#
# This is a DEMONSTRATION runner, not a physical atomizer qualification.  It
# integrates the currently qualified compatible pieces of the x14 liquid/gas
# chain: multi-species SRC, liquid Q6-g-f, x9 surface tension, x6g gas pressure,
# x10o/CIC/Q2/x10u/x10v/x12a liquid interface support, x14l gas specular normal
# reflection, x14v gas excess normal impulse, x14ad local gas traction, chi-Darcy
# nozzle shaping, three same-face segmented inlets and a passive right outlet.
#
# x14ai global-resultant closure remains OFF because the liquid is connected to
# an external inlet and the domain has open boundaries.  Resampling and virial
# closures remain OFF: they are not silently added to the qualified x14 chain.
#
# No C++/CUDA modification. ./livevis_control.kv is read-only/user-owned.
# Runtime conventions follow the 0434/run_ok_* suite wherever the two-phase x14
# physics does not require an explicit specialization.
# =============================================================================

CASE_LABEL="${CASE_LABEL:-0493x14av_air_assisted_atomizer_demo}"
RUN_MODE="src-q6-g-f"
TOPOLOGY="segmented"

# =============================================================================
# USER CONFIGURATION — EDIT VALUES IN THIS SECTION
# Environment variables with the same names may still override these defaults.
# No geometry/inlet value is hidden in the embedded generator.
# =============================================================================

# ---- Domain / resolved fluids ------------------------------------------------
Lx="${Lx:-3.125}"; Ly="${Ly:-1.5625}"; NX="${NX:-800}"; NY="${NY:-400}"
GAMMA="${GAMMA:-8}"
DT="${DT:-0.00635}"
STEPS="${STEPS:-3500}"
GRAVITY_Y="${GRAVITY_Y:-0.0}"

LIQUID_TYPE="${LIQUID_TYPE:-1}"; GAS_TYPE="${GAS_TYPE:-2}"
LIQUID_MASS="${LIQUID_MASS:-1.0}"; GAS_MASS="${GAS_MASS:-0.1}"
LIQUID_KBT="${LIQUID_KBT:-0.125}"; GAS_KBT="${GAS_KBT:-0.004}"
KBT="$GAS_KBT"                     # x6g EOS reads global kBT; gas is species B.
PARTICLE_MASS="$GAS_MASS"
RUN_OK_REFERENCE_PARTICLE_MASS="$LIQUID_MASS"

ROTATION_ANGLE="${ROTATION_ANGLE:-1.5707963267948966}"
RANDOM_ROTATION_SIGN="${RANDOM_ROTATION_SIGN:-true}"
GRID_SHIFT_ENABLE="${GRID_SHIFT_ENABLE:-true}"
THERMOSTAT_ENABLE=true
THERMOSTAT_MODE="cell_relative_rescale"
THERMOSTAT_EVERY=1
THERMOSTAT_TARGET_KBT="$GAS_KBT"
THERMOSTAT_MIN_PARTICLES="${THERMOSTAT_MIN_PARTICLES:-3}"

# Viscosity values are documentary defaults from x14au and are used only for
# dimensionless numbers printed by this demo; they do not alter the solver.
LIQUID_NU_REFERENCE="${LIQUID_NU_REFERENCE:-0.001247}"
GAS_NU_REFERENCE="${GAS_NU_REFERENCE:-0.001340}"

SURFACE_TENSION_SIGMA="${SURFACE_TENSION_SIGMA:-35}"
SURFACE_TENSION_MIN_RADIUS_CELLS="${SURFACE_TENSION_MIN_RADIUS_CELLS:-4}"
PHASE_INTERFACE_KINETIC_REFLECTION_FRACTION="${PHASE_INTERFACE_KINETIC_REFLECTION_FRACTION:-1.0}"
PHASE_INTERFACE_EVAPORATION_TARGET_TYPE="${PHASE_INTERFACE_EVAPORATION_TARGET_TYPE:--1}"
PHASE_INTERFACE_CONTACT_ANGLE_DEG="${PHASE_INTERFACE_CONTACT_ANGLE_DEG:--1}"
X10O_THERMAL_SIGMAS="${X10O_THERMAL_SIGMAS:-3.0}"
X10O_THERMAL_MAX_CELLS="${X10O_THERMAL_MAX_CELLS:-0.75}"
X12A_LOCAL_THERMAL_RADIUS_CELLS="${X12A_LOCAL_THERMAL_RADIUS_CELLS:-25.298221281347036}"
PHASE_INTERFACE_A_SELECTOR="type:${LIQUID_TYPE}"
PHASE_INTERFACE_B_SELECTOR="type:${GAS_TYPE}"
LIQUID_Q6_STRENGTH="${LIQUID_Q6_STRENGTH:-1.0}"
GAS_Q6_STRENGTH="${GAS_Q6_STRENGTH:-0.0}"
SPECIES_Q6_MIN_FILL_FRACTION="${SPECIES_Q6_MIN_FILL_FRACTION:-0.10}"

# ---- Three parameterized nozzles --------------------------------------------
# In 2-D, "diameter" means slit aperture width. Cell counts ensure exact chi
# alignment; physical D and L are derived as cells*h and printed by preflight.
LIQUID_NOZZLE_CENTER_Y="${LIQUID_NOZZLE_CENTER_Y:-0.78125}"
LIQUID_NOZZLE_DIAMETER_CELLS="${LIQUID_NOZZLE_DIAMETER_CELLS:-12}"
LIQUID_NOZZLE_LENGTH_CELLS="${LIQUID_NOZZLE_LENGTH_CELLS:-32}"
LIQUID_NOZZLE_WALL_CELLS="${LIQUID_NOZZLE_WALL_CELLS:-24}"
LIQUID_PRIME_EXTRA_CELLS="${LIQUID_PRIME_EXTRA_CELLS:-4}"
LIQUID_SPEED="${LIQUID_SPEED:-0.15}"

# The air-nozzle center is specified as a cell coordinate from the left face.
# It must lie downstream of the liquid nozzle exit. Top and bottom dimensions
# can be varied independently; the common AIR_NOZZLE_* aliases set both.
AIR_NOZZLE_CENTER_X_CELLS="${AIR_NOZZLE_CENTER_X_CELLS:-88}"
AIR_NOZZLE_DIAMETER_CELLS="${AIR_NOZZLE_DIAMETER_CELLS:-12}"
AIR_TOP_NOZZLE_DIAMETER_CELLS="${AIR_TOP_NOZZLE_DIAMETER_CELLS:-$AIR_NOZZLE_DIAMETER_CELLS}"
AIR_BOTTOM_NOZZLE_DIAMETER_CELLS="${AIR_BOTTOM_NOZZLE_DIAMETER_CELLS:-$AIR_NOZZLE_DIAMETER_CELLS}"
AIR_NOZZLE_LENGTH_CELLS="${AIR_NOZZLE_LENGTH_CELLS:-140}"
AIR_TOP_NOZZLE_LENGTH_CELLS="${AIR_TOP_NOZZLE_LENGTH_CELLS:-$AIR_NOZZLE_LENGTH_CELLS}"
AIR_BOTTOM_NOZZLE_LENGTH_CELLS="${AIR_BOTTOM_NOZZLE_LENGTH_CELLS:-$AIR_NOZZLE_LENGTH_CELLS}"
AIR_NOZZLE_WALL_CELLS="${AIR_NOZZLE_WALL_CELLS:-14}"
AIR_FEED_CLEARANCE_CELLS="${AIR_FEED_CLEARANCE_CELLS:-4}"
AIR_TOP_SPEED="${AIR_TOP_SPEED:-0.0}"
AIR_BOTTOM_SPEED="${AIR_BOTTOM_SPEED:-0.0}" #$AIR_TOP_SPEED}"

# One common ramp is a current segmented-IO property; speeds remain independent.
INLET_RAMP_START_TIME="${INLET_RAMP_START_TIME:-0.0}"
INLET_RAMP_END_TIME="${INLET_RAMP_END_TIME:-0.040}"
INLET_RAMP_INITIAL_FACTOR="${INLET_RAMP_INITIAL_FACTOR:-0.0}"
INLET_RAMP_FINAL_FACTOR="${INLET_RAMP_FINAL_FACTOR:-1.0}"
INLET_RESERVOIR_CELLS="${INLET_RESERVOIR_CELLS:-2}"
INLET_THERMAL_NOISE="${INLET_THERMAL_NOISE:-0.0}"
# Injected particles are deterministic at the boundary; the species thermostat
# subsequently establishes liquidKBT and gasKBT separately.
INLET_HARD_CELL_THERMAL_RESCALE="${INLET_HARD_CELL_THERMAL_RESCALE:-false}"

# Full right passive pressure outlet.  Neumann is the qualified right-outlet
# continuation of the segmented Q6-g-f path.
OUTLET_MODE="${OUTLET_MODE:-neumann}"
OUTLET_SMIN="${OUTLET_SMIN:-0.0}"
OUTLET_SMAX="${OUTLET_SMAX:-1.0}"
OUTLET_FEEDBACK_GAIN="${OUTLET_FEEDBACK_GAIN:-0.0}"

# ---- chi-Darcy walls: 0434/run_ok_* common profile ---------------------------
# Use exactly the variable names consumed by suite_write_darcy_params_0434.
# Common run_ok defaults (used by STEP unless explicitly overridden):
#   ALPHA=8e5, ALPHA_MIN=0, q=0.1, mean_outward_bath, chi-VP=true.
# BEND intentionally overrides forcing to mean; VK intentionally uses
# ALPHA=4000, forcing=mean and chi-VP=false.  This demo starts from the common
# wall-like profile; every value remains directly editable/overridable here.
ALPHA="${ALPHA:-800000.0}"
ALPHA_MIN="${ALPHA_MIN:-0.0}"
DARCY_Q="${DARCY_Q:-0.1}"
DARCY_USOLID_X="${DARCY_USOLID_X:-0.0}"
DARCY_USOLID_Y="${DARCY_USOLID_Y:-0.0}"
DARCY_BRINKMAN_FORCING_MODE="${DARCY_BRINKMAN_FORCING_MODE:-mean_outward_bath}"
DARCY_THREADS_PER_BLOCK="${DARCY_THREADS_PER_BLOCK:-256}"
DARCY_INITIAL_DEACTIVATE_BELOW_CHI="${DARCY_INITIAL_DEACTIVATE_BELOW_CHI:--1}"
DARCY_CHI_COLLISION_VP_ENABLE="${DARCY_CHI_COLLISION_VP_ENABLE:-true}"
DARCY_CHI_COLLISION_VP_MODE="${DARCY_CHI_COLLISION_VP_MODE:-interface_band}"
DARCY_CHI_COLLISION_VP_GAMMA="${DARCY_CHI_COLLISION_VP_GAMMA:--1}"
DARCY_CHI_COLLISION_VP_MASS="${DARCY_CHI_COLLISION_VP_MASS:-1.0}"
DARCY_CHI_COLLISION_VP_LAYERS="${DARCY_CHI_COLLISION_VP_LAYERS:-1}"
DARCY_CHI_COLLISION_VP_THRESHOLD="${DARCY_CHI_COLLISION_VP_THRESHOLD:-0.5}"
DARCY_CHI_COLLISION_VP_STRENGTH="${DARCY_CHI_COLLISION_VP_STRENGTH:-0.25}"
RUN_OK_DARCY_COMMON_FILLED_STATE="${RUN_OK_DARCY_COMMON_FILLED_STATE:-1}"
# The demo does not use topology-force benchmarking, but the common Darcy writer
# also emits these keys, so freeze them explicitly rather than inheriting a shell.
TOPO_BENCHMARK_ENABLE=false
TOPO_BENCHMARK_FORCE_ENABLE=false
TOPO_BENCHMARK_DRAG_LIFT_ENABLE=false
case "$DARCY_BRINKMAN_FORCING_MODE" in
  mean|classic|cell_mean|mean_outward_bath|mean_oriented_bath|brinkman_outward_bath) ;;
  *) echo "[0493x14av] ERROR unsupported Darcy mode=$DARCY_BRINKMAN_FORCING_MODE" >&2; exit 2 ;;
esac
if ! awk -v x="$INLET_THERMAL_NOISE" 'BEGIN{exit !(x==0)}'; then
  echo '[0493x14av] ERROR resident segmented inlet requires INLET_THERMAL_NOISE=0' >&2; exit 2
fi
if [[ "$OUTLET_MODE" != "neumann" ]]; then
  echo '[0493x14av] ERROR demonstration freezes the full-right outlet on OUTLET_MODE=neumann' >&2; exit 2
fi

# Wall collisions are slip/specular-like.  Using one virtual-wall particle mass
# for both physical species would introduce an arbitrary cross-species choice.
WALL_ACCOMMODATION="${WALL_ACCOMMODATION:-0.0}"
if ! awk -v x="$WALL_ACCOMMODATION" 'BEGIN{exit !(x==0)}'; then
  echo '[0493x14av] ERROR demonstration fixes WALL_ACCOMMODATION=0' >&2; exit 2
fi

# ---- Q6-g-f: same standalone override pattern as run_ok_TG/STEP/BEND ---------
# Dedicated RUN_OK_* knobs define the intended profile.  Generic PROJECTION_*
# variables are overwritten below so stale values from an interactive shell cannot
# silently alter the demonstration.
RUN_OK_PROJECTION_BACKEND="${RUN_OK_PROJECTION_BACKEND:-cuda}"
RUN_OK_PROJECTION_OPERATOR="${RUN_OK_PROJECTION_OPERATOR:-auto_fv_cg}"
RUN_OK_PROJECTION_MAX_ITERATIONS="${RUN_OK_PROJECTION_MAX_ITERATIONS:-1600}"
RUN_OK_PROJECTION_TOLERANCE="${RUN_OK_PROJECTION_TOLERANCE:-1.0e-5}"
RUN_OK_Q6_STRICT="${RUN_OK_Q6_STRICT:-1}"
RUN_OK_Q6_GF_DENSITY_RELAXATION_TIME="${RUN_OK_Q6_GF_DENSITY_RELAXATION_TIME:-0.25}"
RUN_OK_Q6_GF_DENSITY_COMPRESSION_GATE_ENABLE="${RUN_OK_Q6_GF_DENSITY_COMPRESSION_GATE_ENABLE:-1}"
RUN_OK_Q6_GF_DENSITY_COMPRESSION_THRESHOLD_PARTICLES="${RUN_OK_Q6_GF_DENSITY_COMPRESSION_THRESHOLD_PARTICLES:-3.0}"
RUN_OK_Q6_GF_DENSITY_TRACTION_THRESHOLD_PARTICLES="${RUN_OK_Q6_GF_DENSITY_TRACTION_THRESHOLD_PARTICLES:-6.0}"
RUN_OK_Q6_GF_DENSITY_TRACTION_GAIN="${RUN_OK_Q6_GF_DENSITY_TRACTION_GAIN:-1.0}"
RUN_OK_Q6_GF_MIN_FILL_FRACTION="${RUN_OK_Q6_GF_MIN_FILL_FRACTION:-$SPECIES_Q6_MIN_FILL_FRACTION}"

PROJECTION_BACKEND="$RUN_OK_PROJECTION_BACKEND"
PROJECTION_OPERATOR="$RUN_OK_PROJECTION_OPERATOR"
PROJECTION_MAX_ITERATIONS="$RUN_OK_PROJECTION_MAX_ITERATIONS"
PROJECTION_TOLERANCE="$RUN_OK_PROJECTION_TOLERANCE"
Q6_PROJECTION_STRENGTH="${Q6_PROJECTION_STRENGTH:-1.0}"
Q6_STRICT="$RUN_OK_Q6_STRICT"
Q6_GF_DENSITY_RELAXATION_TIME="$RUN_OK_Q6_GF_DENSITY_RELAXATION_TIME"
Q6_GF_DENSITY_COMPRESSION_GATE_ENABLE="$RUN_OK_Q6_GF_DENSITY_COMPRESSION_GATE_ENABLE"
Q6_GF_DENSITY_COMPRESSION_THRESHOLD_PARTICLES="$RUN_OK_Q6_GF_DENSITY_COMPRESSION_THRESHOLD_PARTICLES"
Q6_GF_DENSITY_TRACTION_THRESHOLD_PARTICLES="$RUN_OK_Q6_GF_DENSITY_TRACTION_THRESHOLD_PARTICLES"
Q6_GF_DENSITY_TRACTION_GAIN="$RUN_OK_Q6_GF_DENSITY_TRACTION_GAIN"
Q6_GF_MIN_FILL_FRACTION="$RUN_OK_Q6_GF_MIN_FILL_FRACTION"
Q6_GF_EXTERNAL_SPECIES=1
Q6_GF_HAS_GAS_PHASE=1
SPECIES_RESAMPLING_ENABLE=false
LIQUID_RESAMPLING_ENABLE=false
GAS_RESAMPLING_ENABLE=false
WEIGHTED_RESAMPLING_ENABLE_OVERRIDE=false
CUDA_EMPTY_REFILL_ENABLE_OVERRIDE=false
VIRIAL_DENSITY_KICK_ENABLE=false

SUMMARY_EVERY="${SUMMARY_EVERY:-25}"
DARCY_COST_EVERY="${DARCY_COST_EVERY:-$SUMMARY_EVERY}"
DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-1000}"
INACTIVE_SLOTS_CELL_FRACTION="${INACTIVE_SLOTS_CELL_FRACTION:-5.0}"
PREFLIGHT_ONLY="${PREFLIGHT_ONLY:-0}"
CLEAN_RUN_ROOT="${CLEAN_RUN_ROOT:-1}"
BIN="${BIN:-${SRC_MPCD_DEFAULT_BIN_0434:-build/src_mpcd_base_cuda_q6_resident_livevis_0486}}"
THREADS="${THREADS:-8}"
RESTART="${RESTART:-0}"
RESTART_STATE="${RESTART_STATE:-}"
RESTART_TAG="${RESTART_TAG:-segment}"
ANALYZE_ENABLE="${ANALYZE_ENABLE:-1}"
# Diagnostic only: the runner reports cell-flight size.  Set STRICT_FLIGHT_GUARD=1
# to turn FLIGHT_WARN_CELLS into a hard preflight limit.
FLIGHT_WARN_CELLS="${FLIGHT_WARN_CELLS:-0.80}"
STRICT_FLIGHT_GUARD="${STRICT_FLIGHT_GUARD:-0}"

LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-1}"
LIVE_VIS_CONTROL_FILE="$ROOT/livevis_control_AA.kv"
LIVE_VIS_FIELD="${LIVE_VIS_FIELD:-mass}"
LIVE_VIS_EVERY="${LIVE_VIS_EVERY:-1}"
LIVE_VIS_NX="${LIVE_VIS_NX:-256}"; LIVE_VIS_NY="${LIVE_VIS_NY:-128}"
LIVE_VIS_COLORMAP="${LIVE_VIS_COLORMAP:-hot}"; LIVE_VIS_CLIP="${LIVE_VIS_CLIP:--1}"; LIVE_VIS_GAIN="${LIVE_VIS_GAIN:-1.0}"
LIVE_VIS_SMOOTH_PASSES="${LIVE_VIS_SMOOTH_PASSES:-1}"; LIVE_VIS_WINDOW_SCALE="${LIVE_VIS_WINDOW_SCALE:-1}"; LIVE_VIS_HOLD_ON_EXIT="${LIVE_VIS_HOLD_ON_EXIT:-1}"
PARTICLE_TYPE_FILTER="${PARTICLE_TYPE_FILTER:--1}"
FILTERED_RECORDING_ENABLE="${FILTERED_RECORDING_ENABLE:-1}"
RECORD_ENABLE="${RECORD_ENABLE:-true}"
RECORD_EVERY="${RECORD_EVERY:-100}"
RECORD_FIELDS="${RECORD_FIELDS:-mass,ux,uy}"
FILTER_SAMPLE_EVERY="${FILTER_SAMPLE_EVERY:-100}"

BASE_RUN_ROOT="${BASE_RUN_ROOT:-${CAMPAIGN_ROOT:-runs/0493x14av_air_assisted_atomizer_seed_noair${SEED}}}"
if [[ "$RESTART" == "1" ]]; then
  [[ -n "$RESTART_STATE" && -s "$RESTART_STATE" ]] || { echo '[0493x14av] ERROR RESTART=1 requires RESTART_STATE=/path/state_step_N.smpcd' >&2; exit 2; }
  RUN_ROOT="$BASE_RUN_ROOT/restart_${RESTART_TAG}"
  INLET_RAMP_START_TIME=0.0; INLET_RAMP_END_TIME=0.0; INLET_RAMP_INITIAL_FACTOR=1.0; INLET_RAMP_FINAL_FACTOR=1.0
else
  RUN_ROOT="$BASE_RUN_ROOT"
fi

# Keep helper assumptions explicit.  Our custom generator is used directly,
# while GEN_CASE=tg only prevents the common helper from inferring another case.
GEN_CASE=tg; U0=0.0; VELOCITY_MODE=zero; BACKGROUND_TYPE="$GAS_TYPE"; INACTIVE_TYPE="$GAS_TYPE"; TG_HOLE_ENABLE=false
RUN_OK_GENERATOR_PATH="$GENERATOR"
export RUN_OK_REFERENCE_PARTICLE_MASS RUN_OK_GENERATOR_PATH
suite_defaults_common_0434
suite_compute_derived_0434

# ---- Geometry and dimensionless preflight -----------------------------------
DERIVED_LINE="$(python3 - \
  "$Lx" "$Ly" "$NX" "$NY" "$GAMMA" "$LIQUID_NOZZLE_CENTER_Y" "$LIQUID_NOZZLE_DIAMETER_CELLS" \
  "$LIQUID_NOZZLE_LENGTH_CELLS" "$AIR_NOZZLE_CENTER_X_CELLS" "$AIR_TOP_NOZZLE_DIAMETER_CELLS" \
  "$AIR_BOTTOM_NOZZLE_DIAMETER_CELLS" "$AIR_TOP_NOZZLE_LENGTH_CELLS" "$AIR_BOTTOM_NOZZLE_LENGTH_CELLS" \
  "$AIR_NOZZLE_WALL_CELLS" "$AIR_FEED_CLEARANCE_CELLS" "$LIQUID_SPEED" "$AIR_TOP_SPEED" "$AIR_BOTTOM_SPEED" "$DT" \
  "$GAS_MASS" "$GAS_KBT" "$LIQUID_MASS" "$LIQUID_KBT" "$SURFACE_TENSION_SIGMA" \
  "$LIQUID_NU_REFERENCE" "$GAS_NU_REFERENCE" "$ALPHA" <<'PY'
import math,sys
lx,ly=map(float,sys.argv[1:3]); nx,ny=map(int,sys.argv[3:5]); gam=float(sys.argv[5]); lcy=float(sys.argv[6]); ldc=int(sys.argv[7]); llc=int(sys.argv[8]); acell=int(sys.argv[9]); atdc=int(sys.argv[10]); abdc=int(sys.argv[11]); atlc=int(sys.argv[12]); ablc=int(sys.argv[13]); awc=int(sys.argv[14]); clearc=int(sys.argv[15]); ul=float(sys.argv[16]); uat=float(sys.argv[17]); uab=float(sys.argv[18]); dt=float(sys.argv[19]); mg=float(sys.argv[20]); kg=float(sys.argv[21]); ml=float(sys.argv[22]); kl=float(sys.argv[23]); sig=float(sys.argv[24]); nul=float(sys.argv[25]); nug=float(sys.argv[26]); alpha=float(sys.argv[27])
hx=lx/nx; hy=ly/ny
if abs(hx-hy)>1e-12*max(1,abs(hx),abs(hy)): raise SystemExit('[0493x14av-fix1] square cells required')
if min(ldc,llc,acell,atdc,abdc,atlc,ablc,awc)<=0 or clearc<0: raise SystemExit('[0493x14av-fix1] invalid cell parameter')
ld=ldc*hx; ll=llc*hx; y0=lcy-.5*ld; y1=lcy+.5*ld; ac=acell*hx; atd=atdc*hx; abd=abdc*hx; aw=awc*hx; clear=clearc*hx
# Horizontal feed-channel centerlines are placed inside top/bottom walls; the
# vertical terminal leg length is the user AIR_*_NOZZLE_LENGTH_CELLS.
atfy=ly-clear-aw-.5*atd
abfy=clear+aw+.5*abd
ate=atfy-atlc*hy
abe=abfy+ablc*hy
if not (0<y0<y1<ly): raise SystemExit('[0493x14av-fix1] liquid aperture outside domain')
if not (0<ll<ac-2*hx<lx): raise SystemExit('[0493x14av-fix1] air center must be downstream of liquid exit')
if not (0<abfy<abe<lcy<ate<atfy<ly): raise SystemExit('[0493x14av-fix1] air terminal exits/feed channels do not bracket liquid centerline')
ls0=y0/ly; ls1=y1/ly
ats0=(atfy-.5*atd)/ly; ats1=(atfy+.5*atd)/ly
abs0=(abfy-.5*abd)/ly; abs1=(abfy+.5*abd)/ly
for a,b,n in ((ls0,ls1,'liquid'),(ats0,ats1,'top gas'),(abs0,abs1,'bottom gas')):
    if not (0<=a<b<=1): raise SystemExit(f'[0493x14av-fix1] invalid left-face segment {n}')
# Segments must be disjoint on the single supported open axis.
segs=sorted([(ls0,ls1,'liquid'),(ats0,ats1,'top'),(abs0,abs1,'bottom')])
for (_,b,n1),(c,_,n2) in zip(segs,segs[1:]):
    if b>c+1e-12: raise SystemExit(f'[0493x14av-fix1] overlapping left inlet segments {n1}/{n2}')
A=hx*hy; rhoG=gam*mg/A; rhoL=gam*ml/A; pref=gam*kg/A
cthg=math.sqrt(kg/mg)*dt/hx; cthl=math.sqrt(kl/ml)*dt/hx
cgt=cthg+abs(uat)*dt/hx; cgb=cthg+abs(uab)*dt/hx; cl=cthl+abs(ul)*dt/hx
wegt=rhoG*uat*uat*atd/sig; wegb=rhoG*uab*uab*abd/sig; wel=rhoL*ul*ul*ld/sig
regt=abs(uat)*atd/nug; regb=abs(uab)*abd/nug; rel=abs(ul)*ld/nul
mrt=(rhoG*uat*uat)/(rhoL*ul*ul) if ul else float('inf'); mrb=(rhoG*uab*uab)/(rhoL*ul*ul) if ul else float('inf')
lam=1-math.exp(-alpha*dt)
print(hx,A,ld,ll,y0,y1,ac,atd,abd,ate,abe,ls0,ls1,ats0,ats1,abs0,abs1,atfy,abfy,pref,rhoG,rhoL,cthg,cthl,cgt,cgb,cl,wegt,wegb,wel,regt,regb,rel,mrt,mrb,lam)
PY
)" || { echo '[0493x14av] ERROR geometry/derived-parameter preflight failed' >&2; exit 2; }

read -r H CELL_AREA LIQ_D LIQ_L LIQ_Y0 LIQ_Y1 AIR_CX AIR_TOP_D AIR_BOT_D AIR_TOP_EXIT AIR_BOT_EXIT \
  LIQ_SMIN LIQ_SMAX AIR_TOP_SMIN AIR_TOP_SMAX AIR_BOT_SMIN AIR_BOT_SMAX \
  AIR_TOP_FEED_Y AIR_BOT_FEED_Y GAS_P_REF GAS_RHO LIQUID_RHO CTH_G CTH_L CFL_G_TOP CFL_G_BOT CFL_L \
  WE_G_TOP WE_G_BOT WE_L RE_G_TOP RE_G_BOT RE_L MOM_RATIO_TOP MOM_RATIO_BOT DARCY_LAMBDA <<<"$DERIVED_LINE"

for v in H LIQ_D LIQ_L AIR_CX LIQ_SMIN LIQ_SMAX AIR_TOP_SMIN AIR_TOP_SMAX AIR_BOT_SMIN AIR_BOT_SMAX; do
  [[ -n "${!v:-}" ]] || { echo "[0493x14av] ERROR derived variable $v is empty" >&2; exit 2; }
done

MAX_FLIGHT="$(python3 - "$CFL_G_TOP" "$CFL_G_BOT" "$CFL_L" <<'PYF'
import sys
print(max(map(float,sys.argv[1:])))
PYF
)"
if awk -v x="$MAX_FLIGHT" -v w="$FLIGHT_WARN_CELLS" 'BEGIN{exit !(x>w)}'; then
  echo "[0493x14av] WARNING max flight=$MAX_FLIGHT cells/step > diagnostic threshold $FLIGHT_WARN_CELLS" >&2
  if suite_truthy_0434 "$STRICT_FLIGHT_GUARD"; then
    echo '[0493x14av] ERROR STRICT_FLIGHT_GUARD=1' >&2; exit 2
  fi
fi

if suite_truthy_0434 "$CLEAN_RUN_ROOT"; then rm -rf "$RUN_ROOT"; fi
suite_prepare_dirs_0434 "$RUN_ROOT"
mkdir -p "$RUN_ROOT/chi" "$RUN_ROOT/analysis"
STATE="$RUN_ROOT/init/${CASE_LABEL}.smpcd"
CHI_FILE="$RUN_ROOT/chi/${CASE_LABEL}_${NX}x${NY}.f32"
GEOM_SVG="$RUN_ROOT/chi/${CASE_LABEL}_geometry.svg"
OUT="$RUN_ROOT/output"
PARAMS="$RUN_ROOT/params/${CASE_LABEL}.kv"
LOG="$RUN_ROOT/logs/${CASE_LABEL}.log"
TF="$RUN_ROOT/logs/${CASE_LABEL}.time"
mkdir -p "$OUT"

GEN_ARGS=(
  --output "$STATE" --chi-output "$CHI_FILE" --geometry-svg "$GEOM_SVG"
  --Lx "$Lx" --Ly "$Ly" --nx "$NX" --ny "$NY" --gamma "$GAMMA"
  --liquid-type "$LIQUID_TYPE" --gas-type "$GAS_TYPE"
  --liquid-mass "$LIQUID_MASS" --gas-mass "$GAS_MASS"
  --liquid-kBT "$LIQUID_KBT" --gas-kBT "$GAS_KBT" --seed "$SEED"
  --liquid-center-y "$LIQUID_NOZZLE_CENTER_Y"
  --liquid-diameter-cells "$LIQUID_NOZZLE_DIAMETER_CELLS"
  --liquid-length-cells "$LIQUID_NOZZLE_LENGTH_CELLS"
  --liquid-wall-cells "$LIQUID_NOZZLE_WALL_CELLS"
  --liquid-prime-extra-cells "$LIQUID_PRIME_EXTRA_CELLS"
  --air-center-x-cells "$AIR_NOZZLE_CENTER_X_CELLS"
  --air-top-diameter-cells "$AIR_TOP_NOZZLE_DIAMETER_CELLS"
  --air-bottom-diameter-cells "$AIR_BOTTOM_NOZZLE_DIAMETER_CELLS"
  --air-top-length-cells "$AIR_TOP_NOZZLE_LENGTH_CELLS"
  --air-bottom-length-cells "$AIR_BOTTOM_NOZZLE_LENGTH_CELLS"
  --air-wall-cells "$AIR_NOZZLE_WALL_CELLS"
  --air-feed-clearance-cells "$AIR_FEED_CLEARANCE_CELLS"
)
if [[ "$RESTART" == "1" ]]; then
  cp -f "$RESTART_STATE" "$STATE"
  python3 "$GENERATOR" "${GEN_ARGS[@]}" --chi-only
else
  python3 "$GENERATOR" "${GEN_ARGS[@]}"
fi

LREF="$(awk -v g="$GAMMA" -v m="$LIQUID_MASS" 'BEGIN{printf "%.17g",g*m}')"
GREF="$(awk -v g="$GAMMA" -v m="$GAS_MASS" 'BEGIN{printf "%.17g",g*m}')"

SEG0="left inlet $AIR_BOT_SMIN $AIR_BOT_SMAX $AIR_BOTTOM_SPEED 0.0 $GAS_TYPE $GAS_MASS"
SEG1="left inlet $LIQ_SMIN $LIQ_SMAX $LIQUID_SPEED 0.0 $LIQUID_TYPE $LIQUID_MASS"
SEG2="left inlet $AIR_TOP_SMIN $AIR_TOP_SMAX $AIR_TOP_SPEED 0.0 $GAS_TYPE $GAS_MASS"
SEG3="right outlet $OUTLET_SMIN $OUTLET_SMAX 0.0 0.0 0 $GAS_MASS"

validate_segment_0493x14av() {
  local name="$1" text="$2"
  python3 - "$name" "$text" <<'PYSEG'
import math,sys
name,text=sys.argv[1],sys.argv[2]
t=text.split()
if len(t)!=8:
    raise SystemExit(f'[0493x14av] ERROR {name}: expected 8 fields, got {len(t)}: {text!r}')
face,mode=t[0],t[1]
if face not in {'left','right','bottom','top'} or mode not in {'inlet','outlet'}:
    raise SystemExit(f'[0493x14av] ERROR {name}: bad face/mode: {text!r}')
try:
    s0,s1,ux,uy,mass=map(float,(t[2],t[3],t[4],t[5],t[7])); typ=int(t[6])
except Exception as e:
    raise SystemExit(f'[0493x14av] ERROR {name}: non-numeric field in {text!r}: {e}')
if not (0 <= s0 < s1 <= 1): raise SystemExit(f'[0493x14av] ERROR {name}: bad s-range {s0},{s1}')
if not all(map(math.isfinite,(s0,s1,ux,uy,mass))) or mass<=0 or typ<0:
    raise SystemExit(f'[0493x14av] ERROR {name}: invalid finite/type/mass fields')
print(f'[0493x14av] {name} = {text}')
PYSEG
}
for k in 0 1 2 3; do var="SEG$k"; validate_segment_0493x14av "openBoundarySegment$k" "${!var}"; done

cat > "$PARAMS" <<PARAMS
inputState = $STATE
outputDir = $OUT
Lx = $Lx
Ly = $Ly
Nx = $NX
Ny = $NY
dt = $DT
nSteps = $STEPS
bcLeft = solid
bcRight = solid
bcBottom = solid
bcTop = solid
bcX = wall
bcY = wall

openBoundarySegmentsEnable = true
openBoundarySegmentCount = 4
openBoundarySegment0 = $SEG0
openBoundarySegment1 = $SEG1
openBoundarySegment2 = $SEG2
openBoundarySegment3 = $SEG3

inletVelocityRampEnable = true
inletVelocityRampStartTime = $INLET_RAMP_START_TIME
inletVelocityRampEndTime = $INLET_RAMP_END_TIME
inletVelocityRampInitialFactor = $INLET_RAMP_INITIAL_FACTOR
inletVelocityRampFinalFactor = $INLET_RAMP_FINAL_FACTOR
inletVelocityRampProfile = smoothstep
inletVelocitySpatialProfile = uniform
inletKBT = $GAS_KBT
inletThermalNoise = $INLET_THERMAL_NOISE
inletInjectionMode = hard_cell_density
inletReservoirMode = hard_cell_density
inletReservoirCells = $INLET_RESERVOIR_CELLS
inletTargetOccupancy = $GAMMA
inletHardCellVelocityMean = true
inletHardCellThermalRescale = $INLET_HARD_CELL_THERMAL_RESCALE
inletRandomizeTangential = false
inletReinjectBackflow = true

openBoundaryOutletMode = $OUTLET_MODE
openBoundaryOutletHybridBlend = 0.0
openBoundaryOutletFeedbackGain = $OUTLET_FEEDBACK_GAIN

bodyAccelerationX = 0.0
bodyAccelerationY = $GRAVITY_Y
taylorGreenForcingEnable = false
wallVpEnable = false
wallAccommodation = $WALL_ACCOMMODATION
wallVpGamma = $GAMMA
wallVpMass = $LIQUID_MASS
wallKBT = -1.0
wallThermalNoise = 0.0

# Darcy/chi parameters are appended by suite_write_darcy_params_0434 below.
speciesRegistryEnable = true
speciesCount = 2
species0 = $LIQUID_TYPE incompressible_liquid liquid $LIQUID_Q6_STRENGTH 1.0 $LREF
species0ResamplingEnable = false
species0ThermostatTargetKBT = $LIQUID_KBT
species1 = $GAS_TYPE compressible_gas gas $GAS_Q6_STRENGTH 0.0 $GREF
species1ResamplingEnable = false
species1ThermostatTargetKBT = $GAS_KBT
speciesRequireRegisteredTypes = true
speciesThermostatEnable = true
speciesDiagnosticsEnable = true
speciesDiagnosticsFilename = species_runtime_0493x14av.csv
speciesCellDiagnosticsEnable = false
speciesQ6Sensitivity = 1.0
speciesQ6FallbackMode = common
speciesQ6ComparisonTolerance = 1.0e-11
PARAMS
suite_write_common_params_0434 "$RUN_MODE" >> "$PARAMS"
suite_write_darcy_params_0434 "$CHI_FILE" "$RUN_MODE" >> "$PARAMS"
run_ok_surface_append_params_0493x13zi "$PARAMS" "$PHASE_INTERFACE_A_SELECTOR" "$PHASE_INTERFACE_B_SELECTOR"
cat >> "$PARAMS" <<'PARAMS'
phaseInterfaceKineticBilateralRelocation = true
PARAMS

suite_export_cuda_flags_0434 "$RUN_MODE" "$TOPOLOGY"
export MPCD_Q6_G_F_RESIDENT_CG_0493X7J=1
export MPCD_CUDA_Q6_RESIDENT_SINGLE_BLOCK_CG_0407=0
run_ok_surface_export_off_flags_0493x13zi
export MPCD_Q6_PHASE_GAS_PRESSURE_0493X6G=1
export MPCD_Q6_PHASE_GAS_PRESSURE_MODE_0493X6G=eos_accessible_volume
export MPCD_Q6_PHASE_GAS_PRESSURE_CONSTANT_0493X6G=0
export MPCD_Q6_PHASE_GAS_PRESSURE_REFERENCE_0493X6G="$GAS_P_REF"
export MPCD_Q6_PHASE_GAS_PRESSURE_SCALE_0493X6G=1

export MPCD_X10O_Q6_THERMAL_INTERFACE_WALL=1
export MPCD_X10O_THERMAL_PARTICLE_MASS="$LIQUID_MASS"
export MPCD_X10O_THERMAL_SIGMAS="$X10O_THERMAL_SIGMAS"
export MPCD_X10O_THERMAL_MAX_CELLS="$X10O_THERMAL_MAX_CELLS"
export MPCD_X10_KINETIC_INTERFACE_CIC=1
export MPCD_X10_KINETIC_INTERFACE_QUADRATIC=1
export MPCD_X10P_INITIAL_OVERLAP_RESOLUTION=1
export MPCD_X10_KINETIC_INTERFACE_ONE_FOR_ONE=1
export MPCD_X10_KINETIC_INTERFACE_ONE_FOR_ONE_SWAP=1
export MPCD_X10_KINETIC_INTERFACE_ONE_FOR_ONE_NORMAL_ONLY=0
export MPCD_X10_KINETIC_INTERFACE_THERMAL_PHASE_LIMITER=0
export MPCD_X12A_LOCAL_THERMAL_COOLING=1
export MPCD_X12A_LOCAL_THERMAL_RADIUS_CELLS="$X12A_LOCAL_THERMAL_RADIUS_CELLS"

export MPCD_X14L_GAS_SPECULAR_REFLECTION=1
export MPCD_X14V_GAS_KINETIC_EXCESS_KICK=1
export MPCD_X14V_SUBTRACT_X6G_THERMODYNAMIC_TRACTION=1
export MPCD_X14V_X6G_FACE_THERMO_TRACTION=0
export MPCD_X14V_X6G_GAUGE_FACE_THERMO_TRACTION=0
export MPCD_X14V_X6G_GAUGE_RESULTANT_PROJECTION=0
export MPCD_X14V_X6G_LOCAL_FACE_GAUGE_PROJECTION=1
export MPCD_X14V_REFERENCE_PRESSURE_GEOMETRIC_CLOSURE=0
export MPCD_X14V_SCATTER_LOSS_DIAGNOSTIC=0
export MPCD_X14V_GLOBAL_BALANCE_DIAGNOSTIC=0
export MPCD_X14V_DEVICE_APPLIED_Q6_RESULTANT_CLOSURE=0
export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_WORKSPACE_DOWNLOAD_0272=1

suite_prepare_livevis_control_0434 "$RUN_ROOT" "$RUN_MODE"
suite_export_livevis_0434
suite_write_env_file_0434 "$RUN_ROOT/logs/environment_${CASE_LABEL}.env" "$RUN_MODE"
cat >> "$RUN_ROOT/logs/environment_${CASE_LABEL}.env" <<META
BENCHMARK=air_assisted_atomizer_2d_demo
LIQUID_NOZZLE_DIAMETER_CELLS=$LIQUID_NOZZLE_DIAMETER_CELLS
LIQUID_NOZZLE_LENGTH_CELLS=$LIQUID_NOZZLE_LENGTH_CELLS
LIQUID_NOZZLE_DIAMETER=$LIQ_D
LIQUID_NOZZLE_LENGTH=$LIQ_L
LIQUID_SPEED=$LIQUID_SPEED
AIR_NOZZLE_CENTER_X_CELLS=$AIR_NOZZLE_CENTER_X_CELLS
AIR_NOZZLE_CENTER_X=$AIR_CX
AIR_TOP_NOZZLE_DIAMETER_CELLS=$AIR_TOP_NOZZLE_DIAMETER_CELLS
AIR_BOTTOM_NOZZLE_DIAMETER_CELLS=$AIR_BOTTOM_NOZZLE_DIAMETER_CELLS
AIR_TOP_NOZZLE_LENGTH_CELLS=$AIR_TOP_NOZZLE_LENGTH_CELLS
AIR_BOTTOM_NOZZLE_LENGTH_CELLS=$AIR_BOTTOM_NOZZLE_LENGTH_CELLS
AIR_TOP_SPEED=$AIR_TOP_SPEED
AIR_BOTTOM_SPEED=$AIR_BOTTOM_SPEED
RIGHT_OUTLET_MODE=$OUTLET_MODE
RUN_OK_PROFILE=0493x14av_s2_run_ok_homogeneous
RUN_OK_DARCY_PROFILE=0434_common
ALPHA=$ALPHA
ALPHA_MIN=$ALPHA_MIN
DARCY_BRINKMAN_FORCING_MODE=$DARCY_BRINKMAN_FORCING_MODE
DARCY_CHI_COLLISION_VP_ENABLE=$DARCY_CHI_COLLISION_VP_ENABLE
DARCY_INITIAL_DEACTIVATE_BELOW_CHI_EFFECTIVE=-1
DARCY_LAMBDA_PER_STEP=$DARCY_LAMBDA
RUN_OK_PROJECTION_OPERATOR=$PROJECTION_OPERATOR
RUN_OK_PROJECTION_MAX_ITERATIONS=$PROJECTION_MAX_ITERATIONS
RUN_OK_PROJECTION_TOLERANCE=$PROJECTION_TOLERANCE
MPCD_X14V_DEVICE_APPLIED_Q6_RESULTANT_CLOSURE=0
RESTART=$RESTART
RESTART_STATE=$RESTART_STATE
META

run_ok_surface_print_0493x13zi "air-assisted atomizer: gas pressure + Laplace tension + liquid interface support + gas specular/excess impulse + local traction"
echo "===== 0493x14av-s2 AIR-ASSISTED ATOMIZER DEMO ====="
echo "PATHS: runner=scripts/run_0493x14av_air_assisted_atomizer_demo.sh"
echo "       generator=embedded analyzer=embedded binary=$BIN"
echo "       state=$STATE chi=$CHI_FILE geometry=$GEOM_SVG"
echo "DOMAIN: ${Lx}x${Ly} grid=${NX}x${NY} h=$H gamma=$GAMMA dt=$DT steps=$STEPS"
echo "LIQUID NOZZLE: left -> right centerY=$LIQUID_NOZZLE_CENTER_Y Dcells=$LIQUID_NOZZLE_DIAMETER_CELLS D=$LIQ_D Lcells=$LIQUID_NOZZLE_LENGTH_CELLS L=$LIQ_L U=$LIQUID_SPEED"
echo "AIR TOP: left-feedY=$AIR_TOP_FEED_Y -> 90deg turn at x=$AIR_CX; Dcells=$AIR_TOP_NOZZLE_DIAMETER_CELLS D=$AIR_TOP_D verticalLcells=$AIR_TOP_NOZZLE_LENGTH_CELLS exitY=$AIR_TOP_EXIT nominalU=$AIR_TOP_SPEED"
echo "AIR BOTTOM: left-feedY=$AIR_BOT_FEED_Y -> 90deg turn at x=$AIR_CX; Dcells=$AIR_BOTTOM_NOZZLE_DIAMETER_CELLS D=$AIR_BOT_D verticalLcells=$AIR_BOTTOM_NOZZLE_LENGTH_CELLS exitY=$AIR_BOT_EXIT nominalU=$AIR_BOTTOM_SPEED"
echo "BOUNDARIES: THREE segmented inlets on LEFT (gas/liquid/gas) + full RIGHT Neumann outlet; y-axis CLOSED (0142 one-open-axis contract)"
echo "DARCY(run_ok common): alpha=[$ALPHA_MIN,$ALPHA] lambdaSolidPerStep=$DARCY_LAMBDA forcing=$DARCY_BRINKMAN_FORCING_MODE chiCollisionVP=$DARCY_CHI_COLLISION_VP_ENABLE"
echo "                    q=$DARCY_Q initialDeactivateEffective=-1 commonFilled=$RUN_OK_DARCY_COMMON_FILLED_STATE VPmode=$DARCY_CHI_COLLISION_VP_MODE VPgamma=$DARCY_CHI_COLLISION_VP_GAMMA VPmass=$DARCY_CHI_COLLISION_VP_MASS"
echo "Q6(run_ok profile): projection=$PROJECTION_OPERATOR tol=$PROJECTION_TOLERANCE maxIt=$PROJECTION_MAX_ITERATIONS strict=$Q6_STRICT tau=$Q6_GF_DENSITY_RELAXATION_TIME minFill=$Q6_GF_MIN_FILL_FRACTION"
echo "RESOLUTION: gasThermal=$CTH_G h/step gasTopTotal=$CFL_G_TOP gasBottomTotal=$CFL_G_BOT liquidTotal=$CFL_L"
echo "DIMENSIONLESS(ref nu): WeGtop=$WE_G_TOP WeGbottom=$WE_G_BOT WeL=$WE_L ReGtop=$RE_G_TOP ReGbottom=$RE_G_BOT ReL=$RE_L"
echo "ASSIST momentum ratio rhoG*Ug^2/(rhoL*Ul^2): top=$MOM_RATIO_TOP bottom=$MOM_RATIO_BOT"
echo "PHYSICS: x6g+x9+x10o/CIC/Q2/x10u/x10v/x12a+x14l+x14v+x14ad; x14ai OFF; resampling OFF; virial OFF"
echo "OUTPUT: LiveVis every=$LIVE_VIS_EVERY; recording every=$RECORD_EVERY; restart dumps every=$DUMP_STATE_EVERY"
echo "NOTE: ./livevis_control.kv is authoritative/read-only and is not modified"
echo "RESTART: active=$RESTART state=${RESTART_STATE:-none}; STEPS is segment length on a restart"
echo "PARAMETERS: fully resolved solver file=$PARAMS"
echo "====================================================="

# 0493x14av-fix1: explicit runner-side guard for the core 0142 contract.
# PRELIGHT_ONLY skips the binary, so the runner itself must reject any accidental
# reintroduction of y-axis open segments.
if grep -Eq "^openBoundarySegment[0-9]+[[:space:]]*=[[:space:]]*(top|bottom)[[:space:]]" "$PARAMS"; then
  echo "[0493x14av-fix1] ERROR y-axis open segment generated; 0142 permits one open axis only" >&2
  exit 2
fi
echo "[0493x14av-fix1] open-boundary contract: x-axis only (3 left inlets + 1 right outlet) PASS"

# Ensure the resolved params really use the same Darcy contract as the common
# run_ok writer.  This catches stale/duplicate manual keys before binary launch.
for kv in \
  "darcyAlphaMin = $ALPHA_MIN" \
  "darcyAlphaMax = $ALPHA" \
  "darcyQ = $DARCY_Q" \
  "darcyBrinkmanForcingMode = $DARCY_BRINKMAN_FORCING_MODE" \
  "darcyChiCollisionVpEnable = $DARCY_CHI_COLLISION_VP_ENABLE" \
  "darcyInitialDeactivateBelowChi = -1"
do
  grep -Fqx "$kv" "$PARAMS" || { echo "[0493x14av-s2] ERROR missing/effective Darcy key: $kv" >&2; exit 2; }
done
[[ "$(grep -c '^darcyAlphaMax[[:space:]]*=' "$PARAMS")" == "1" ]] || { echo '[0493x14av-s2] ERROR duplicate darcyAlphaMax key' >&2; exit 2; }
echo '[0493x14av-s2] Darcy contract: suite_write_darcy_params_0434 PASS'

suite_run_binary_0434 "$PARAMS" "$LOG" "$TF" "$OUT"
if suite_truthy_0434 "$PREFLIGHT_ONLY"; then
  echo '[0493x14av-s2] PREFLIGHT_ONLY complete'
  exit 0
fi

if suite_truthy_0434 "$ANALYZE_ENABLE"; then
  python3 "$ANALYZER" \
    --run-root "$RUN_ROOT" --Lx "$Lx" --Ly "$Ly" --nx "$NX" --ny "$NY" --gamma "$GAMMA" \
    --liquid-type "$LIQUID_TYPE" --liquid-nozzle-exit-x "$LIQ_L" \
    --air-center-x "$AIR_CX" --air-diameter "$AIR_TOP_D"
fi

OUT_TAR="$RUN_ROOT/0493x14av_air_assisted_atomizer_compact.tar.gz"
FILES=(
  analysis
  "chi/${CASE_LABEL}_${NX}x${NY}.f32" "chi/${CASE_LABEL}_${NX}x${NY}.f32.json" "chi/${CASE_LABEL}_geometry.svg"
  "output/recordings" "output/darcy_cost_0343.csv" "output/species_runtime_0493x14av.csv"
  "output/cuda_phase_interface_pressure_0493x6g.csv" "output/cuda_phase_interface_stencil_0493x6f.csv"
  "logs/${CASE_LABEL}.log" "logs/${CASE_LABEL}.time" "logs/environment_${CASE_LABEL}.env"
  "params/${CASE_LABEL}.kv" "init/${CASE_LABEL}.smpcd.json"
)
PRESENT=(); for f in "${FILES[@]}"; do [[ -e "$RUN_ROOT/$f" ]] && PRESENT+=("$f"); done
tar -czf "$OUT_TAR" -C "$RUN_ROOT" "${PRESENT[@]}"
echo "[0493x14av-s2] COMPLETE root=$RUN_ROOT"
echo "[0493x14av-s2] compact=$OUT_TAR"
