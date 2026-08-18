#!/usr/bin/env python3
import math

H=0.005
ANCHOR_Y=4.5*H
ANGLES=(30.0,45.0,60.0,90.0,120.0,135.0,150.0)
ELLIPSES=((0.28,0.20,'wide'),(0.20,0.28,'tall'))


def ellipse_geometry(a,b,theta):
    st,ct=math.sin(theta),math.cos(theta)
    den=math.sqrt(a*a*st*st+b*b*ct*ct)
    cos_t=a*st/den
    sin_t=b*ct/den
    t0=math.atan2(sin_t,cos_t)
    cy=-b*sin_t
    half=a*cos_t
    k=a*b/(a*a*sin_t*sin_t+b*b*cos_t*cos_t)**1.5
    return cy,half,k,t0


def ellipse_secant(a,b,cy,t0):
    s1=(ANCHOR_Y-cy)/b
    if abs(s1)>1: return None
    t1=math.asin(s1)
    if math.cos(t1)<0: t1=math.pi-t1
    def n(t):
        vx=math.cos(t)/a;vy=math.sin(t)/b;g=math.hypot(vx,vy)
        return vx/g,vy/g
    n0,n1=n(t0),n(t1)
    delta=math.atan2(n0[0]*n1[1]-n0[1]*n1[0],n0[0]*n1[0]+n0[1]*n1[1])
    chord=math.hypot(a*math.cos(t1)-a*math.cos(t0),ANCHOR_Y)
    return abs(2*math.sin(0.5*delta)/chord)


def main():
    ok=True
    # Plane normals and zero curvature.
    for deg in ANGLES:
        th=math.radians(deg)
        nx,ny=math.sin(th),math.cos(th)
        wall_dot=-ny
        target=-math.cos(th)
        p=abs(wall_dot-target)<1e-14
        ok &= p
        print(f"[0493x9n-mapcheck] plane theta={deg:g} wallDot={wall_dot:+.12g} target={target:+.12g} exactKappa=0 pass={int(p)}")
    # Circle scaling identities.
    for rc in (20,40,80):
        r=rc*H
        k=1/r
        p=abs(k*rc*H-1.0)<1e-14
        ok &= p
        print(f"[0493x9n-mapcheck] circle R/h={rc} R={r:.12g} exactKappa={k:.12g} pass={int(p)}")
    # Ellipse contact normal and finite-chord bias must be safely below the
    # 10% local-curvature gate before discretization.
    for a,b,name in ELLIPSES:
        for deg in (60.0,90.0,120.0):
            th=math.radians(deg)
            cy,half,k,t0=ellipse_geometry(a,b,th)
            vx=math.cos(t0)/a;vy=math.sin(t0)/b;g=math.hypot(vx,vy)
            nx,ny=vx/g,vy/g
            wall_dot=-ny; target=-math.cos(th)
            ks=ellipse_secant(a,b,cy,t0)
            rel=(ks-k)/k if ks is not None else float('inf')
            p=(abs(wall_dot-target)<1e-14 and ks is not None and abs(rel)<0.07)
            ok &= p
            print(f"[0493x9n-mapcheck] ellipse={name} theta={deg:g} a={a:g} b={b:g} exactKappa={k:.9g} idealSecant={ks:.9g} secantBias={100*rel:+.3f}% pass={int(p)}")
    print(f"[0493x9n-mapcheck] status={'PASS' if ok else 'FAIL'}")
    return 0 if ok else 2

if __name__=='__main__':
    raise SystemExit(main())
