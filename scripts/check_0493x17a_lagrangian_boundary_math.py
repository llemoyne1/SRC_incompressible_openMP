#!/usr/bin/env python3
import math
import sys

ISO=0.5

def extract(chi,nx,ny,lx,ly,px=True,py=True):
    dx=lx/nx; dy=ly/ny
    owner_nx=nx if px else nx-1
    owner_ny=ny if py else ny-1
    edges=[]; amb=0
    def sample(i,j):
        if px: i%=nx
        if py: j%=ny
        if i<0 or i>=nx or j<0 or j>=ny: return 1.0
        return chi[j][i]
    def shifted(v):
        f=v-ISO
        return 1e-12 if abs(f)<1e-12 else f
    for j in range(owner_ny):
        for i in range(owner_nx):
            vals=[sample(i,j),sample(i+1,j),sample(i+1,j+1),sample(i,j+1)]
            fs=list(map(shifted,vals))
            code=sum((1<<k) for k,f in enumerate(fs) if f>0)
            if code in (0,15): continue
            x0=(i+.5)*dx; y0=(j+.5)*dy; x1=x0+dx; y1=y0+dy
            def pt(e):
                corners=[(fs[0],x0,y0),(fs[1],x1,y0),(fs[2],x1,y1),(fs[3],x0,y1)]
                aa,bb=[(0,1),(1,2),(2,3),(3,0)][e]
                fa,xa,ya=corners[aa]; fb,xb,yb=corners[bb]
                den=fa-fb; t=fa/den if abs(den)>1e-300 else .5
                t=max(0,min(1,t)); return (xa+t*(xb-xa),ya+t*(yb-ya))
            pairs=[]
            one=lambda a,b:pairs.append((a,b))
            if code==1: one(3,0)
            elif code==2: one(0,1)
            elif code==3: one(3,1)
            elif code==4: one(1,2)
            elif code==5:
                amb+=1; q=fs[0]*fs[2]-fs[1]*fs[3]
                pairs += [(0,1),(2,3)] if q>0 else [(3,0),(1,2)]
            elif code==6: one(0,2)
            elif code==7: one(3,2)
            elif code==8: one(2,3)
            elif code==9: one(0,2)
            elif code==10:
                amb+=1; q=fs[0]*fs[2]-fs[1]*fs[3]
                pairs += [(3,0),(1,2)] if q<0 else [(0,1),(2,3)]
            elif code==11: one(1,2)
            elif code==12: one(1,3)
            elif code==13: one(0,1)
            elif code==14: one(3,0)
            for a,b in pairs:
                A=pt(a); B=pt(b); tx=B[0]-A[0]; ty=B[1]-A[1]
                mx=.5*(A[0]+B[0]); my=.5*(A[1]+B[1])
                xi=max(0,min(1,(mx-x0)/dx)); eta=max(0,min(1,(my-y0)/dy))
                v00,v10,v11,v01=vals
                gx=((v10-v00)*(1-eta)+(v11-v01)*eta)/dx
                gy=((v01-v00)*(1-xi)+(v11-v10)*xi)/dy
                sign=1 if (-ty)*gx+tx*gy>=0 else -1
                edges.append((A,B,sign))
    return edges,amb

def cross(ax,ay,bx,by): return ax*by-ay*bx

def hit(P,V,A,B,UA,UB,T,sign=1):
    ex0=B[0]-A[0]; ey0=B[1]-A[1]
    ex1=UB[0]-UA[0]; ey1=UB[1]-UA[1]
    qx0=P[0]-A[0]; qy0=P[1]-A[1]
    qx1=V[0]-UA[0]; qy1=V[1]-UA[1]
    c0=cross(qx0,qy0,ex0,ey0)
    c1=cross(qx1,qy1,ex0,ey0)+cross(qx0,qy0,ex1,ey1)
    c2=cross(qx1,qy1,ex1,ey1)
    roots=[]
    if abs(c2)<1e-14:
        if abs(c1)>1e-14: roots=[-c0/c1]
    else:
        d=c1*c1-4*c2*c0
        if d>=-1e-14:
            d=max(0,d); sd=math.sqrt(d)
            roots=[(-c1-sd)/(2*c2),(-c1+sd)/(2*c2)]
    out=[]
    for t in roots:
        if -1e-12<=t<=T+1e-12:
            t=max(0,min(T,t))
            Ah=(A[0]+t*UA[0],A[1]+t*UA[1]); Bh=(B[0]+t*UB[0],B[1]+t*UB[1])
            Ph=(P[0]+t*V[0],P[1]+t*V[1])
            e=(Bh[0]-Ah[0],Bh[1]-Ah[1]); e2=e[0]*e[0]+e[1]*e[1]
            lam=((Ph[0]-Ah[0])*e[0]+(Ph[1]-Ah[1])*e[1])/e2
            if -1e-10<=lam<=1+1e-10:
                lam=max(0,min(1,lam)); inv=1/math.sqrt(e2)
                n=(-e[1]*inv*sign,e[0]*inv*sign)
                W=((1-lam)*UA[0]+lam*UB[0],(1-lam)*UA[1]+lam*UB[1])
                reln=(V[0]-W[0])*n[0]+(V[1]-W[1])*n[1]
                if reln < -1e-13:
                    V2=(V[0]-2*reln*n[0],V[1]-2*reln*n[1])
                    resid=abs(cross(Ph[0]-Ah[0],Ph[1]-Ah[1],e[0],e[1]))
                    out.append((t,lam,n,W,reln,V2,resid))
    return min(out,key=lambda z:z[0]) if out else None

def check(name,cond,detail=''):
    if not cond:
        print(f'FAIL {name} {detail}'.rstrip()); raise SystemExit(2)
    print(f'PASS {name} {detail}'.rstrip())

# 1. Periodic slab represented by cell-centred chi: two vertical material faces.
nx,ny=128,64; lx,ly=.5,.25; dx=lx/nx
xmin=.25-4*dx; xmax=.25+4*dx
chi=[]
for j in range(ny):
    row=[]
    for i in range(nx):
        x=(i+.5)*dx
        row.append(0.0 if xmin<=x<=xmax else 1.0)
    chi.append(row)
edges,amb=extract(chi,nx,ny,lx,ly,True,True)
check('periodic_slab_edge_count',len(edges)==2*ny,f'edges={len(edges)} expected={2*ny}')
check('periodic_slab_no_ambiguity',amb==0,f'ambiguous={amb}')
left=[e for e in edges if abs(.5*(e[0][0]+e[1][0])-xmin)<1.1*dx]
right=[e for e in edges if abs(.5*(e[0][0]+e[1][0])-xmax)<1.1*dx]
check('periodic_slab_two_faces',len(left)==ny and len(right)==ny,f'left={len(left)} right={len(right)}')
def normal(e):
    A,B,s=e; tx=B[0]-A[0]; ty=B[1]-A[1]; L=math.hypot(tx,ty)
    return (-ty/L*s,tx/L*s)
check('left_face_fluidward',all(normal(e)[0] < -0.999999 for e in left))
check('right_face_fluidward',all(normal(e)[0] > 0.999999 for e in right))

# 2. Static vertical wall: incoming particle reflects at exact crossing.
A=(0.,-1.); B=(0.,1.); UA=(0.,0.); UB=(0.,0.)
h=hit((.1,0.),(-2.,.25),A,B,UA,UB,.1,sign=1) # left normal is (-1,0), fluid on +x needs sign=-1
h=hit((.1,0.),(-2.,.25),A,B,UA,UB,.1,sign=-1)
check('static_segment_hit',h is not None)
check('static_hit_time',abs(h[0]-.05)<1e-12,f't={h[0]:.17g}')
check('static_specular',abs(h[5][0]-2.0)<1e-12 and abs(h[5][1]-.25)<1e-12,f'v2={h[5]}')

# 3. Galilean boost: same relative event and reaction, lab hit point translated.
U=.08
h0=hit((.1,0.),(-2.,.25),A,B,UA,UB,.1,sign=-1)
hb=hit((.1,0.),(-2.+U,.25),(0.,-1.),(0.,1.),(U,0.),(U,0.),.1,sign=-1)
check('galilean_same_hit_time',abs(h0[0]-hb[0])<1e-12,f'rest={h0[0]:.17g} boost={hb[0]:.17g}')
check('galilean_same_reln',abs(h0[4]-hb[4])<1e-12,f'rest={h0[4]:.17g} boost={hb[4]:.17g}')
check('galilean_velocity_shift',abs((hb[5][0]-h0[5][0])-U)<1e-12)

# 4. Temporal capture: moving wall overtakes a stationary particle.
# Wall starts at x=0, fluid to +x, advances right at 1.0; particle x=.05.
ht=hit((.05,0.),(0.,0.),A,B,(1.,0.),(1.,0.),.1,sign=-1)
check('moving_wall_overtake_hit',ht is not None)
check('moving_wall_overtake_time',abs(ht[0]-.05)<1e-12,f't={ht[0]:.17g}')

# 5. Deforming edge: endpoint velocities differ; quadratic root lies on instantaneous segment.
A=(-.1,-.5); B=(.1,.5); UA=(.25,.1); UB=(-.15,-.05)
hd=hit((.30,.02),(-1.2,.0),A,B,UA,UB,.4,sign=-1)
check('deforming_segment_hit',hd is not None)
check('deforming_segment_coplanarity',hd[6]<1e-12,f'residual={hd[6]:.3e}')
check('deforming_segment_lambda',0.0<=hd[1]<=1.0,f'lambda={hd[1]:.17g}')

print('0493x17a Lagrangian-boundary math check: ALL PASS')
