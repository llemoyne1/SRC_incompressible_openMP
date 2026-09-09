#!/usr/bin/env python3
import csv
import glob
import math
import os
import re
import struct
import sys
from array import array
from pathlib import Path

LIQUID_TYPE = 1
ROOT_GLOB = "runs/0493x10x_C*_R*_g*"
OUT = Path("0493x10x_thermal_sigmas_summary.csv")
RUN_RE = re.compile(r"0493x10x_C(?P<C>[0-9mp]+)_R(?P<R>[0-9]+)_g(?P<g>[0-9mp]+)$")


def decode_tag(s):
    sign = -1.0 if s.startswith("m") else 1.0
    if s.startswith("m"):
        s = s[1:]
    return sign * float(s.replace("p", "."))


def read_array(f, code, n):
    a = array(code)
    need = a.itemsize * n
    raw = f.read(need)
    if len(raw) != need:
        raise RuntimeError("truncated state array")
    a.frombytes(raw)
    if sys.byteorder == "big":
        a.byteswap()
    return a


def read_kv(run):
    files = sorted(glob.glob(os.path.join(run, "params", "*.kv")))
    if not files:
        raise RuntimeError(f"{run}: no params kv")
    out = {}
    with open(files[-1]) as f:
        for line in f:
            if "=" not in line or line.lstrip().startswith("#"):
                continue
            k, v = line.split("=", 1)
            out[k.strip()] = v.strip()
    return out


def read_state(path, R_cells, h):
    with open(path, "rb") as f:
        magic = f.read(16)
        if not magic.startswith(b"SRCMPCD_STATE"):
            raise RuntimeError(f"{path}: bad magic")
        fmt = "<IIIIQIIII"
        raw = f.read(struct.calcsize(fmt))
        version, endian, dim, ns, n, a, b, rsv_n, word = struct.unpack(fmt, raw)
        meta = struct.unpack("<8d", f.read(8 * 8))
        x = read_array(f, "d", n)
        y = read_array(f, "d", n)
        vx = read_array(f, "d", n)
        vy = read_array(f, "d", n)
        typ = read_array(f, "I", n)
        mass = read_array(f, "d", n)
        tail = f.read()
        role = tail[:n] if len(tail) >= n else bytes([1]) * n

    ids = [i for i in range(n) if typ[i] == LIQUID_TYPE and role[i] == 1]
    if not ids:
        raise RuntimeError(f"{path}: no liquid fluid particles")
    M = sum(mass[i] for i in ids)
    xcm = sum(mass[i] * x[i] for i in ids) / M
    ycm = sum(mass[i] * y[i] for i in ids) / M
    vxcm = sum(mass[i] * vx[i] for i in ids) / M
    vycm = sum(mass[i] * vy[i] for i in ids) / M

    R = R_cells * h
    rr = sorted(math.hypot(x[i] - xcm, y[i] - ycm) for i in ids)
    r90 = rr[min(len(rr)-1, max(0, math.ceil(0.90 * len(rr)) - 1))]
    beyond = sum(1 for r in rr if r > 2.0 * R)
    return {
        "N": len(ids), "M": M,
        "xcm": xcm, "ycm": ycm, "vxcm": vxcm, "vycm": vycm,
        "speed": math.hypot(vxcm, vycm),
        "r90_over_R": r90 / R if R > 0 else float("nan"),
        "frac_beyond_2R": beyond / len(rr),
    }


def read_summary(run):
    p = os.path.join(run, "output", "summary_runtime.csv")
    with open(p, newline="") as f:
        rows = list(csv.DictReader(f))
    if not rows:
        raise RuntimeError(f"{p}: empty")
    r = rows[-1]
    return {
        "step": int(float(r["step"])),
        "time": float(r["time"]),
        "kBT": float(r.get("kBT", "nan") or "nan"),
        "meanVx": float(r.get("meanVx", "nan") or "nan"),
        "meanVy": float(r.get("meanVy", "nan") or "nan"),
        "Nsummary": int(float(r.get("nFluidParticles", 0) or 0)),
    }


def read_interface(run):
    p = os.path.join(run, "output", "cuda_phase_kinetic_crossing_0493x9z.csv")
    if not os.path.exists(p):
        return {"collisions": 0, "overlaps": 0, "mean_delta": float("nan"), "rel_out": 0, "no_seg": 0}
    with open(p, newline="") as f:
        rows = list(csv.DictReader(f))
    def I(r, k): return int(float(r.get(k, 0) or 0))
    def F(r, k): return float(r.get(k, 0) or 0)
    endpoints = sum(I(r, "q6ThermalInterfaceEndpointSamples") for r in rows)
    mean_delta = (sum(F(r, "q6ThermalMeanThickness") * I(r, "q6ThermalInterfaceEndpointSamples") for r in rows) / endpoints) if endpoints else float("nan")
    return {
        "collisions": sum(I(r, "continuousWallCollisions") for r in rows),
        "overlaps": sum(I(r, "x10pInitialOverlapResolved") for r in rows),
        "mean_delta": mean_delta,
        "rel_out": sum(I(r, "continuousWallRelativeStillOutward") for r in rows),
        "no_seg": sum(I(r, "continuousWallNoNearbySegment") for r in rows),
    }


cases = {}
for run in glob.glob(ROOT_GLOB):
    m = RUN_RE.search(os.path.basename(run))
    if not m:
        continue
    C = decode_tag(m.group("C"))
    R = int(m.group("R"))
    g = decode_tag(m.group("g"))
    try:
        kv = read_kv(run)
        h = min(float(kv["Lx"]) / int(kv["Nx"]), float(kv["Ly"]) / int(kv["Ny"]))
        sm = read_summary(run)
        state_path = os.path.join(run, "output", f"state_step_{sm['step']:08d}.smpcd")
        if not os.path.exists(state_path):
            dumps = sorted(glob.glob(os.path.join(run, "output", "state_step_*.smpcd")))
            if not dumps:
                raise RuntimeError(f"{run}: no state dump")
            state_path = dumps[-1]
        st = read_state(state_path, R, h)
        itf = read_interface(run)
        st["h"] = h
    except Exception as e:
        print(f"[0493x10x-analyze] WARN {run}: {e}", file=sys.stderr)
        continue
    cases[(R, round(C, 12), round(g, 12))] = {"run": run, **sm, **st, **itf}

rows = []
for R, C in sorted({(k[0], k[1]) for k in cases}):
    z = cases.get((R, C, 0.0))
    q = cases.get((R, C, -0.1))
    if not z or not q:
        continue
    t = min(z["time"], q["time"])
    g = -0.1
    denom_y = 0.5 * g * t * t
    denom_v = g * t
    disp = (q["ycm"] - z["ycm"]) / denom_y if denom_y else float("nan")
    vel = (q["vycm"] - z["vycm"]) / denom_v if denom_v else float("nan")
    h_pair = 0.5 * (z["h"] + q["h"])
    delta_h = 0.5 * (z["mean_delta"] + q["mean_delta"]) / h_pair
    rows.append({
        "R_over_h": R,
        "C": C,
        "mean_delta_over_h": delta_h,
        "mean_delta_over_R": delta_h / R,
        "paired_displacement_ratio": disp,
        "paired_velocity_ratio": vel,
        "g0_com_speed": z["speed"],
        "gminus_com_speed": q["speed"],
        "g0_final_kBT": z["kBT"],
        "gminus_final_kBT": q["kBT"],
        "g0_r90_over_R": z["r90_over_R"],
        "gminus_r90_over_R": q["r90_over_R"],
        "g0_frac_beyond_2R": z["frac_beyond_2R"],
        "gminus_frac_beyond_2R": q["frac_beyond_2R"],
        "mean_interface_interventions": 0.5 * ((z["collisions"] + z["overlaps"]) + (q["collisions"] + q["overlaps"])),
        "relative_still_outward_total": z["rel_out"] + q["rel_out"],
        "no_nearby_segment_total": z["no_seg"] + q["no_seg"],
        "g0_run": z["run"],
        "gminus_run": q["run"],
    })

if not rows:
    raise SystemExit("[0493x10x-analyze] no complete g=0/-0.1 pairs found")

fields = list(rows[0].keys())
with OUT.open("w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=fields)
    w.writeheader(); w.writerows(rows)

print("===== 0493x10x THERMAL SIGMAS PAIRED RESPONSE =====")
print(" R/h      C  delta/h  delta/R    disp/g     vel/g    g0speed      r90-   beyond2R-  interventions")
for r in rows:
    print(f"{r['R_over_h']:4d}  {r['C']:5.2f}  {r['mean_delta_over_h']:7.4f}  {r['mean_delta_over_R']:7.4f}  "
          f"{r['paired_displacement_ratio']:8.4f}  {r['paired_velocity_ratio']:8.4f}  {r['g0_com_speed']:9.5f}  "
          f"{r['gminus_r90_over_R']:7.4f}  {r['gminus_frac_beyond_2R']:10.3e}  {r['mean_interface_interventions']:12.1f}")
print(f"[0493x10x-analyze] wrote {OUT}")
