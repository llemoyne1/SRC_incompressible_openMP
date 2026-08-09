#!/usr/bin/env python3
import argparse
import math


def metrics(Lx, Ly, nx, ny, dt, K, beta):
    dx=Lx/nx; dy=Ly/ny
    c=math.sqrt(beta*K)
    return dx,dy,c,c*dt/dx,c*dt/dy

def main():
    ap=argparse.ArgumentParser(description="0493x7b continuum virial grid-scaling check")
    ap.add_argument("--Lx",type=float,default=2.0); ap.add_argument("--Ly",type=float,default=1.0)
    ap.add_argument("--nx-a",type=int,default=300); ap.add_argument("--ny-a",type=int,default=150); ap.add_argument("--dt-a",type=float,default=0.005)
    ap.add_argument("--nx-b",type=int,default=600); ap.add_argument("--ny-b",type=int,default=300); ap.add_argument("--dt-b",type=float,default=0.0025)
    ap.add_argument("--k-virial",type=float,default=0.10666666666666667); ap.add_argument("--beta-eos",type=float,default=0.05)
    args=ap.parse_args()
    if min(args.Lx,args.Ly,args.dt_a,args.dt_b,args.k_virial,args.beta_eos) <= 0 or min(args.nx_a,args.ny_a,args.nx_b,args.ny_b) <= 0:
        raise SystemExit("[0493x7b] all dimensions, timesteps, K, beta and grid counts must be positive")
    A=metrics(args.Lx,args.Ly,args.nx_a,args.ny_a,args.dt_a,args.k_virial,args.beta_eos)
    B=metrics(args.Lx,args.Ly,args.nx_b,args.ny_b,args.dt_b,args.k_virial,args.beta_eos)
    print(f"[0493x7b] K={args.k_virial:.12g} [code velocity^2] beta={args.beta_eos:.12g} cVir={A[2]:.12g}")
    print(f"[0493x7b] A grid={args.nx_a}x{args.ny_a} dt={args.dt_a:.12g} d=({A[0]:.12g},{A[1]:.12g}) CFL=({A[3]:.12g},{A[4]:.12g})")
    print(f"[0493x7b] B grid={args.nx_b}x{args.ny_b} dt={args.dt_b:.12g} d=({B[0]:.12g},{B[1]:.12g}) CFL=({B[3]:.12g},{B[4]:.12g})")
    rx=abs(B[3]-A[3])/max(abs(A[3]),1e-300); ry=abs(B[4]-A[4])/max(abs(A[4]),1e-300)
    ok=rx <= 1e-12 and ry <= 1e-12
    print(f"[0493x7b] CFL relative difference x={rx:.3e} y={ry:.3e} status={'PASS' if ok else 'REVIEW'}")
    raise SystemExit(0 if ok else 1)

if __name__ == '__main__': main()
