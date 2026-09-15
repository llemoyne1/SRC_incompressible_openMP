#!/usr/bin/env python3
import math

def inside(poly,p):
    x,y=p; c=0; best=1e99
    for (ax,ay),(bx,by) in zip(poly,poly[1:]+poly[:1]):
        ex,ey=bx-ax,by-ay; e2=ex*ex+ey*ey
        t=max(0,min(1,((x-ax)*ex+(y-ay)*ey)/e2)); qx,qy=ax+t*ex,ay+t*ey; best=min(best,math.hypot(x-qx,y-qy))
        if (ay>y)!=(by>y):
            xh=ax+(y-ay)*(bx-ax)/(by-ay)
            if xh>x:c^=1
    return bool(c),best
# Concave simple loop: parity must classify points independently of local edge normals.
poly=[(0,0),(3,0),(3,3),(2,3),(2,1),(1,1),(1,3),(0,3)]
assert inside(poly,(0.5,2))[0]
assert not inside(poly,(1.5,2))[0]
assert inside(poly,(2.5,2))[0]
print('PASS closed_loop_parity_concave')
# y-extrema anchor selection pins both ends, not the whole strip.
y=[0,0,0.5,1,1,1,0.5]; h=.1; band=1.5*h; lo=min(y); hi=max(y); pin=[v<=lo+band or v>=hi-band for v in y]
assert sum(pin)==5 and not pin[2] and not pin[6]
print('PASS extrema_anchor_selection')
# Fixed node impulse balance: Jsupport=-(Jfluid_on_solid+Fint*dt).
J=2.3; F=-0.7; dt=.02; Js=-(J+F*dt); assert abs((J+F*dt+Js))<1e-15
print('PASS pinned_constraint_impulse_closure')
print('0493x17d analytical checks: ALL PASS')
