#!/usr/bin/env python3
"""Radial audit for the x14j diffuse liquid/gas drop.

The analysis deliberately does not classify every alpha<0.5 particle as a
failure. It measures whether a finite mesoscopic mixed halo develops and whether
that halo broadens indefinitely.

Outputs:
  radial_metrics_0493x14j.csv  one row per dump
  radial_profiles_0493x14j.csv radial alpha_L/alpha_G profiles
"""
from __future__ import annotations

import argparse
import csv
import math
import re
import struct
import sys
from array import array
from pathlib import Path

MAGIC_PREFIX = b"SRCMPCD_STATE"


def read_array(f, typecode: str, n: int, itemsize: int):
    a = array(typecode)
    a.fromfile(f, n)
    if len(a) != n:
        raise RuntimeError("truncated state")
    if sys.byteorder == "big" and itemsize > 1:
        a.byteswap()
    return a


def read_state(path: Path):
    with path.open("rb") as f:
        magic = f.read(16)
        if not magic.startswith(MAGIC_PREFIX):
            raise RuntimeError(f"bad state magic in {path}")
        hfmt = "<IIIIQIIII"
        raw = f.read(struct.calcsize(hfmt))
        version, endian, dim, layout, n, has_type, has_mass, real_size, type_size = struct.unpack(hfmt, raw)
        reserved = struct.unpack("<8Q", f.read(64))
        if endian != 0x01020304 or dim != 2 or layout != 1:
            raise RuntimeError(f"unsupported state header in {path}")
        if not has_type or not has_mass or real_size != 8 or type_size != 4:
            raise RuntimeError(f"unsupported particle layout in {path}")
        n = int(n)
        x = read_array(f, "d", n, 8)
        y = read_array(f, "d", n, 8)
        vx = read_array(f, "d", n, 8)
        vy = read_array(f, "d", n, 8)
        typ = read_array(f, "I", n, 4)
        mass = read_array(f, "d", n, 8)
        if version >= 2:
            role_size = int(reserved[1]) if reserved[1] else 1
            if role_size != 1:
                raise RuntimeError(f"unsupported role size={role_size}")
            role = read_array(f, "B", n, 1)
        else:
            role = array("B", [1]) * n
    return x, y, vx, vy, typ, mass, role


def smooth3(v):
    if len(v) < 3:
        return list(v)
    out = [v[0]]
    for i in range(1, len(v)-1):
        out.append((v[i-1] + 2.0*v[i] + v[i+1]) / 4.0)
    out.append(v[-1])
    return out


def first_downcross(r, a, level, start_index=1):
    for i in range(max(1, start_index), len(a)):
        y0, y1 = a[i-1], a[i]
        if y0 >= level and y1 < level:
            if y0 == y1:
                return 0.5*(r[i-1]+r[i])
            q = (level-y0)/(y1-y0)
            return r[i-1] + q*(r[i]-r[i-1])
    return math.nan


def finite_or_nan(x):
    return x if math.isfinite(x) else math.nan


def parse_step(path: Path):
    m = re.search(r"state_step_(\d+)\.smpcd$", path.name)
    return int(m.group(1)) if m else 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--initial", type=Path, required=True)
    ap.add_argument("--output-dir", type=Path, required=True)
    ap.add_argument("--analysis-dir", type=Path, required=True)
    ap.add_argument("--Lx", type=float, required=True)
    ap.add_argument("--Ly", type=float, required=True)
    ap.add_argument("--nx", type=int, required=True)
    ap.add_argument("--ny", type=int, required=True)
    ap.add_argument("--gamma", type=float, required=True)
    ap.add_argument("--dt", type=float, required=True)
    ap.add_argument("--center-x", type=float, required=True)
    ap.add_argument("--center-y", type=float, required=True)
    ap.add_argument("--initial-radius", type=float, required=True)
    ap.add_argument("--liquid-type", type=int, default=1)
    ap.add_argument("--gas-type", type=int, default=2)
    ap.add_argument("--bin-cells", type=float, default=1.0)
    args = ap.parse_args()

    h = args.Lx / args.nx
    if abs(h - args.Ly/args.ny) > 1e-12*max(1.0,h):
        raise SystemExit("[0493x14j-analysis] square cells required")
    dr = args.bin_cells*h
    max_full_r = min(args.center_x, args.Lx-args.center_x,
                     args.center_y, args.Ly-args.center_y)
    nb = max(4, int(math.floor(max_full_r/dr)))
    rho_num_nom = args.gamma / (h*h)

    states = [(0, args.initial)]
    for p in sorted(args.output_dir.glob("state_step_*.smpcd")):
        states.append((parse_step(p), p))
    # De-duplicate if a state name happened to map to step 0.
    uniq = {}
    for step,p in states:
        uniq[step] = p
    states = sorted(uniq.items())
    if len(states) < 2:
        print("[0493x14j-analysis] WARNING only initial state/no runtime dump found")

    args.analysis_dir.mkdir(parents=True, exist_ok=True)
    metrics_path = args.analysis_dir / "radial_metrics_0493x14j.csv"
    profiles_path = args.analysis_dir / "radial_profiles_0493x14j.csv"

    metric_fields = [
        "step","time","Nliquid","Ngas","R50","R90","R10","width10_90","R50_over_h",
        "liquidOutsideR50_p1h","liquidOutsideR50_p2h","liquidOutsideR50_p4h","liquidOutsideR50_p8h",
        "gasInsideR50_m1h","gasInsideR50_m2h","gasInsideR50_m4h","gasInsideR50_m8h",
        "liquidOutsideR0_p8h","gasInsideR0_m8h","liquidMeanRadius","gasMeanRadius"
    ]
    profile_fields = ["step","time","r","r_over_h","alphaLiquid","alphaGas","alphaTotal","nLiquid","nGas"]

    with metrics_path.open("w", newline="") as fm, profiles_path.open("w", newline="") as fp:
        mw = csv.DictWriter(fm, fieldnames=metric_fields); mw.writeheader()
        pw = csv.DictWriter(fp, fieldnames=profile_fields); pw.writeheader()

        for step, path in states:
            x,y,vx,vy,typ,mass,role = read_state(path)
            nl = [0]*nb; ng = [0]*nb
            nL=nG=0
            sumrL=sumrG=0.0
            radiiL=[]
            radiiG=[]
            for i in range(len(x)):
                if role[i] != 1:
                    continue
                t = int(typ[i])
                if t != args.liquid_type and t != args.gas_type:
                    continue
                rr = math.hypot(x[i]-args.center_x, y[i]-args.center_y)
                if t == args.liquid_type:
                    nL += 1; sumrL += rr; radiiL.append(rr)
                else:
                    nG += 1; sumrG += rr; radiiG.append(rr)
                b = int(rr/dr)
                if 0 <= b < nb:
                    if t == args.liquid_type: nl[b] += 1
                    else: ng[b] += 1

            rc=[]; aL=[]; aG=[]
            for b in range(nb):
                r0=b*dr; r1=(b+1)*dr
                area=math.pi*(r1*r1-r0*r0)
                norm=max(1e-300, rho_num_nom*area)
                rmid=0.5*(r0+r1)
                rc.append(rmid)
                aL.append(nl[b]/norm)
                aG.append(ng[b]/norm)
            aLs=smooth3(aL)
            # Ignore the very first bins for crossing detection; the drop core
            # should be liquid and a noisy centre bin must not define R50.
            start=max(1, int(0.2*args.initial_radius/dr))
            r90=first_downcross(rc,aLs,0.9,start)
            r50=first_downcross(rc,aLs,0.5,start)
            r10=first_downcross(rc,aLs,0.1,start)
            width=r10-r90 if math.isfinite(r10) and math.isfinite(r90) else math.nan

            def frac_out(vals, threshold):
                if not vals: return math.nan
                return sum(r > threshold for r in vals)/len(vals)
            def frac_in(vals, threshold):
                if not vals: return math.nan
                return sum(r < threshold for r in vals)/len(vals)

            row = {
                "step":step, "time":step*args.dt, "Nliquid":nL, "Ngas":nG,
                "R50":finite_or_nan(r50), "R90":finite_or_nan(r90), "R10":finite_or_nan(r10),
                "width10_90":finite_or_nan(width),
                "R50_over_h":r50/h if math.isfinite(r50) else math.nan,
                "liquidMeanRadius":sumrL/nL if nL else math.nan,
                "gasMeanRadius":sumrG/nG if nG else math.nan,
            }
            for k in (1,2,4,8):
                row[f"liquidOutsideR50_p{k}h"] = frac_out(radiiL, r50+k*h) if math.isfinite(r50) else math.nan
                row[f"gasInsideR50_m{k}h"] = frac_in(radiiG, max(0.0,r50-k*h)) if math.isfinite(r50) else math.nan
            row["liquidOutsideR0_p8h"] = frac_out(radiiL, args.initial_radius+8*h)
            row["gasInsideR0_m8h"] = frac_in(radiiG, max(0.0,args.initial_radius-8*h))
            mw.writerow(row)

            tnow=step*args.dt
            for b in range(nb):
                pw.writerow({
                    "step":step,"time":tnow,"r":rc[b],"r_over_h":rc[b]/h,
                    "alphaLiquid":aL[b],"alphaGas":aG[b],"alphaTotal":aL[b]+aG[b],
                    "nLiquid":nl[b],"nGas":ng[b]
                })

            print(
                "[0493x14j-analysis] "
                f"step={step:6d} t={tnow:.6g} N_L={nL} N_G={nG} "
                f"R50/h={(r50/h if math.isfinite(r50) else math.nan):.4f} "
                f"w10-90/h={(width/h if math.isfinite(width) else math.nan):.4f} "
                f"Lout(R50+4h)={row['liquidOutsideR50_p4h']:.6e} "
                f"Lout(R50+8h)={row['liquidOutsideR50_p8h']:.6e} "
                f"Gin(R50-4h)={row['gasInsideR50_m4h']:.6e}"
            )

    print(f"[0493x14j-analysis] metrics={metrics_path}")
    print(f"[0493x14j-analysis] profiles={profiles_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
