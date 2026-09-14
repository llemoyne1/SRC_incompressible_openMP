#!/usr/bin/env python3
import argparse, array, math, struct
from pathlib import Path

MAGIC=b'SRCMPCD_STATE\0\0\0'
HDR_FMT='<16sIIIIQIIII8Q'
HDR_SIZE=struct.calcsize(HDR_FMT)
ROLE_INACTIVE=0
ROLE_FLUID=1

def periodic_delta(x,c,L):
    d=x-c
    return d-round(d/L)*L

def read_state(path):
    with open(path,'rb') as f:
        h=f.read(HDR_SIZE)
        if len(h)!=HDR_SIZE: raise SystemExit('short smpcd header')
        vals=struct.unpack(HDR_FMT,h)
        magic,version,endian,dim,layout,N,hasType,hasMass,realSize,typeSize,*reserved=vals
        if magic!=MAGIC or version!=2 or dim!=2 or layout!=1 or realSize!=8 or typeSize!=4 or reserved[0]!=1:
            raise SystemExit('0493x17b requires SMPD V2 SoA state with role array')
        n=int(N)
        def arr(code,count):
            a=array.array(code); a.fromfile(f,count); return a
        x=arr('d',n); y=arr('d',n); vx=arr('d',n); vy=arr('d',n)
        typ=arr('I',n) if hasType else array.array('I',[0])*n
        mass=arr('d',n) if hasMass else array.array('d',[1.0])*n
        role=array.array('B'); role.fromfile(f,n)
        if f.read(1): raise SystemExit('unexpected trailing bytes in smpcd state')
    return h,(x,y,vx,vy,typ,mass,role)

def write_state(path,h,fields):
    with open(path,'wb') as f:
        f.write(h)
        for a in fields: a.tofile(f)

def main():
    ap=argparse.ArgumentParser(description='0493x17b one-time exact initial fluid exclusion for the frozen curved-slab qualification geometry')
    ap.add_argument('state')
    ap.add_argument('--Lx',type=float,required=True); ap.add_argument('--Ly',type=float,required=True)
    ap.add_argument('--center-x',type=float,required=True); ap.add_argument('--thickness',type=float,required=True)
    ap.add_argument('--amplitude',type=float,required=True)
    a=ap.parse_args()
    h,F=read_state(a.state); x,y,vx,vy,typ,mass,role=F; n=len(x)
    half=0.5*a.thickness; ky=2.0*math.pi/a.Ly
    culled=[]; kept=[]; other=[]
    for i in range(n):
        if role[i]!=ROLE_FLUID:
            other.append(i); continue
        yc=y[i]-math.floor(y[i]/a.Ly)*a.Ly
        c=a.center_x+a.amplitude*math.sin(ky*yc)
        inside=abs(periodic_delta(x[i],c,a.Lx)) < half
        (culled if inside else kept).append(i)
    order=kept+other+culled
    out=[]
    for arr0 in (x,y,vx,vy,typ,mass):
        z=array.array(arr0.typecode,(arr0[i] for i in order)); out.append(z)
    rr=array.array('B',(role[i] for i in order))
    for j in range(len(kept)+len(other),n): rr[j]=ROLE_INACTIVE
    out.append(rr)
    write_state(a.state,h,out)
    print(f'[0493x17b-init] state={a.state} fluidBefore={sum(1 for r in role if r==ROLE_FLUID)} deactivated={len(culled)} fluidAfter={len(kept)}')

if __name__=='__main__': main()
