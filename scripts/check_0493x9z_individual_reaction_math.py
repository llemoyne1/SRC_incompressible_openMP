#!/usr/bin/env python3
import math, random

rng = random.Random(493990)
max_dp = 0.0
max_de = 0.0
max_g = 0.0
feasible_cases = 0

for _ in range(10000):
    # Receiver bath with thermal spread.
    nr = rng.randint(8, 40)
    masses = [0.5 + rng.random()*1.5 for _ in range(nr)]
    urx = rng.uniform(-0.25,0.25)
    ury = rng.uniform(-0.25,0.25)
    rv=[]
    for m in masses:
        rv.append((urx+rng.gauss(0,0.7), ury+rng.gauss(0,0.7)))
    Mr=sum(masses)
    Prx=sum(m*v[0] for m,v in zip(masses,rv))
    Pry=sum(m*v[1] for m,v in zip(masses,rv))
    Kr=sum(0.5*m*(v[0]**2+v[1]**2) for m,v in zip(masses,rv))
    urx=Prx/Mr; ury=Pry/Mr

    # A few crossing donors, individually reflected around bath velocity.
    nd=rng.randint(1,4)
    dp_x=dp_y=dED=0.0
    donor_records=[]
    for _d in range(nd):
        m=0.5+rng.random()*1.5
        a=rng.uniform(0,2*math.pi)
        nx,ny=math.cos(a),math.sin(a)
        gn=rng.uniform(0.02,0.45)
        tang=rng.uniform(-0.4,0.4)
        vx=urx + gn*nx - tang*ny
        vy=ury + gn*ny + tang*nx
        vrx=vx-2*gn*nx; vry=vy-2*gn*ny
        post=(vrx-urx)*nx+(vry-ury)*ny
        max_g=max(max_g,abs(post+gn))
        dpx=m*(vrx-vx); dpy=m*(vry-vy)
        de=0.5*m*((vrx*vrx+vry*vry)-(vx*vx+vy*vy))
        dp_x+=dpx; dp_y+=dpy; dED+=de
        donor_records.append((m,vx,vy,vrx,vry))

    Jx,Jy=-dp_x,-dp_y
    meanDelta=urx*Jx+ury*Jy+0.5*(Jx*Jx+Jy*Jy)/Mr
    Krel=Kr-0.5*Mr*(urx*urx+ury*ury)
    target=Krel-dED-meanDelta
    if Krel <= 1e-12 or target < 0:
        continue
    lam=math.sqrt(target/Krel)
    dux,duy=Jx/Mr,Jy/Mr

    P0x=Prx+sum(m*vx for m,vx,vy,vrx,vry in donor_records)
    P0y=Pry+sum(m*vy for m,vx,vy,vrx,vry in donor_records)
    E0=Kr+sum(0.5*m*(vx*vx+vy*vy) for m,vx,vy,vrx,vry in donor_records)

    P1x=sum(m*(urx+dux+lam*(vx-urx)) for m,(vx,vy) in zip(masses,rv))
    P1y=sum(m*(ury+duy+lam*(vy-ury)) for m,(vx,vy) in zip(masses,rv))
    E1=sum(0.5*m*((urx+dux+lam*(vx-urx))**2+(ury+duy+lam*(vy-ury))**2)
           for m,(vx,vy) in zip(masses,rv))
    P1x+=sum(m*vrx for m,vx,vy,vrx,vry in donor_records)
    P1y+=sum(m*vry for m,vx,vy,vrx,vry in donor_records)
    E1+=sum(0.5*m*(vrx*vrx+vry*vry) for m,vx,vy,vrx,vry in donor_records)

    max_dp=max(max_dp,abs(P1x-P0x),abs(P1y-P0y))
    max_de=max(max_de,abs(E1-E0))
    feasible_cases+=1

print(f"feasibleCases={feasible_cases}")
print(f"maxIndividualNormalIdentityError={max_g:.3e}")
print(f"maxDeltaP={max_dp:.3e}")
print(f"maxDeltaKE={max_de:.3e}")
print("status=" + ("PASS" if feasible_cases>9000 and max_g<1e-12 and max_dp<1e-11 and max_de<1e-11 else "FAIL"))
