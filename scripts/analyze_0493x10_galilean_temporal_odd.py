#!/usr/bin/env python3
import csv
import glob
import math
import os
import re
import struct
import sys
from array import array

LIQUID_TYPE = 1
VREF = 0.1

SETS = [
    ("Q6GF-only", "runs/0493x10_q6gf_only_x10oParams_R8_vy*"),
    ("Q6GF+x10o", "runs/0493x10o_galilean_x10oParams_R8_vy*"),
    ("Q6GF+x10r", "runs/0493x10r_galilean_x10oParams_R8_vy*"),
    ("Q6GF+x10s", "runs/0493x10s_galilean_x10oParams_R8_vy*"),
]

CHECKPOINTS = [0, 10, 25, 50, 75, 100, 125, 150, 175, 200]

def parse_vy(dirname):
    m = re.search(r"_vy(m?)([0-9]+)p([0-9]+)$", dirname)
    if not m:
        return None
    sign = -1.0 if m.group(1) == "m" else 1.0
    return sign * float(m.group(2) + "." + m.group(3))

def find_runs(pattern):
    out = {}
    for d in glob.glob(pattern):
        vy = parse_vy(d)
        if vy is not None:
            out[round(vy, 3)] = d
    return out

def read_velocity_series(dirname):
    """
    Preferred source: summary_runtime.csv.

    For the Galilean static-drop runs the background is vacuum, so all active
    fluid particles are liquid. Hence summary meanVy/Py are exactly the liquid
    COM velocity/momentum needed for the odd-mode test.

    Fallback: species_runtime_0493x9s.csv when present in older runs.
    """
    summary = os.path.join(dirname, "output", "summary_runtime.csv")
    if os.path.exists(summary):
        rows = {}
        with open(summary, newline="") as f:
            rd = csv.DictReader(f)
            required = {"step", "time", "nFluidParticles", "totalMass", "Py", "meanVy"}
            missing = required.difference(rd.fieldnames or [])
            if missing:
                raise RuntimeError(
                    f"{summary}: missing columns {sorted(missing)}"
                )
            for r in rd:
                step = int(float(r["step"]))
                rows[step] = {
                    "time": float(r["time"]),
                    "n": int(float(r["nFluidParticles"])),
                    "mass": float(r["totalMass"]),
                    "py": float(r["Py"]),
                    "vy": float(r["meanVy"]),
                }
        if rows:
            return rows, "summary_runtime.csv"

    species = os.path.join(dirname, "output", "species_runtime_0493x9s.csv")
    if os.path.exists(species):
        rows = {}
        with open(species, newline="") as f:
            rd = csv.DictReader(f)
            required = {"step", "time", "type", "nFluid", "totalMass", "Py", "meanVy"}
            missing = required.difference(rd.fieldnames or [])
            if missing:
                raise RuntimeError(
                    f"{species}: missing columns {sorted(missing)}"
                )
            for r in rd:
                if int(float(r["type"])) != LIQUID_TYPE:
                    continue
                step = int(float(r["step"]))
                rows[step] = {
                    "time": float(r["time"]),
                    "n": int(float(r["nFluid"])),
                    "mass": float(r["totalMass"]),
                    "py": float(r["Py"]),
                    "vy": float(r["meanVy"]),
                }
        if rows:
            return rows, "species_runtime_0493x9s.csv"

    q6 = os.path.join(dirname, "output", "cuda_species_q6_0491.csv")
    q6_note = (
        f"; {q6} exists but does not contain particle meanVy/Py"
        if os.path.exists(q6) else ""
    )
    raise RuntimeError(
        f"{dirname}: neither output/summary_runtime.csv nor "
        f"output/species_runtime_0493x9s.csv is available{q6_note}"
    )

def read_reflection_series(dirname):
    p = os.path.join(dirname, "output", "cuda_phase_kinetic_crossing_0493x9z.csv")
    if not os.path.exists(p):
        return {}
    rows = {}
    cumulative_jy = 0.0
    cumulative_coll = 0
    with open(p, newline="") as f:
        rd = csv.DictReader(f)
        if not rd.fieldnames:
            return {}
        for r in rd:
            step = int(float(r["step"]))
            # Sign convention used by the existing x10r analyzer:
            # particle impulse = -continuousWallImpulseY
            cumulative_jy += -float(r.get("continuousWallImpulseY", 0.0) or 0.0)
            cumulative_coll += int(float(r.get("continuousWallCollisions", 0) or 0))
            rows[step] = {
                "cumJyParticle": cumulative_jy,
                "cumCollisions": cumulative_coll,
            }
    return rows

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

def state_com_y(dirname, step):
    p = os.path.join(dirname, "output", f"state_step_{step:08d}.smpcd")
    if not os.path.exists(p):
        return None
    with open(p, "rb") as f:
        magic = f.read(16)
        if not magic.startswith(b"SRCMPCD_STATE"):
            raise RuntimeError(f"{p}: bad magic")
        fmt = "<IIIIQIIII"
        raw = f.read(struct.calcsize(fmt))
        version, endian, dim, ns, n, a, b, rsv_n, word = struct.unpack(fmt, raw)
        f.read(8 * 8)
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
        return None
    M = sum(mass[i] for i in ids)
    return sum(mass[i] * y[i] for i in ids) / M

def closest_step(steps, target):
    if not steps:
        return None
    return min(steps, key=lambda s: (abs(s-target), s))

def first_crossing(series, threshold):
    for step in sorted(series):
        if series[step]["retV"] < threshold:
            return step
    return None

all_modes = {}
for mode, pattern in SETS:
    runs = find_runs(pattern)
    if -0.1 not in runs or 0.1 not in runs:
        print(f"[temporal] skip {mode}: need vy=-0.1 and +0.1 ({pattern})", file=sys.stderr)
        continue

    minus_dir = runs[-0.1]
    plus_dir = runs[0.1]
    zero_dir = runs.get(0.0)

    sm, src_m = read_velocity_series(minus_dir)
    sp, src_p = read_velocity_series(plus_dir)
    if zero_dir:
        sz, src_z = read_velocity_series(zero_dir)
    else:
        sz, src_z = {}, "none"
    print(
        f"[temporal] {mode}: velocity source "
        f"-V={src_m} zero={src_z} +V={src_p}",
        file=sys.stderr,
    )
    jm = read_reflection_series(minus_dir)
    jp = read_reflection_series(plus_dir)

    steps = sorted(set(sm).intersection(sp))
    if not steps:
        raise RuntimeError(f"{mode}: no common runtime-summary steps")

    # Explicit initial point. The dump initialization is exactly +/- VREF.
    temporal = {
        0: {
            "time": 0.0,
            "vodd": VREF,
            "veven": 0.0,
            "vzero": 0.0 if zero_dir else float("nan"),
            "retV": 100.0,
            "yoddInt": 0.0,
            "retYInt": 100.0,
            "jyodd": 0.0,
            "jyoddNorm": 0.0,
        }
    }

    # Use initial liquid mass for normalizing odd reflection impulse.
    first = steps[0]
    M0 = 0.5 * (sm[first]["mass"] + sp[first]["mass"])
    prev_t = 0.0
    prev_vodd = VREF
    yodd_int = 0.0

    for step in steps:
        t = 0.5 * (sm[step]["time"] + sp[step]["time"])
        vm = sm[step]["vy"]
        vp = sp[step]["vy"]
        vodd = 0.5 * (vp - vm)
        veven = 0.5 * (vp + vm)
        vzero = sz[step]["vy"] if step in sz else float("nan")

        dt = t - prev_t
        if dt < -1e-14:
            raise RuntimeError(f"{mode}: non-monotonic time at step {step}")
        if dt > 0:
            yodd_int += 0.5 * (prev_vodd + vodd) * dt

        jminus = jm.get(step, {}).get("cumJyParticle", float("nan"))
        jplus = jp.get(step, {}).get("cumJyParticle", float("nan"))
        jyodd = (
            0.5 * (jplus - jminus)
            if math.isfinite(jminus) and math.isfinite(jplus)
            else float("nan")
        )
        jyodd_norm = (
            100.0 * jyodd / (M0 * VREF)
            if math.isfinite(jyodd) and M0 > 0
            else float("nan")
        )

        temporal[step] = {
            "time": t,
            "vodd": vodd,
            "veven": veven,
            "vzero": vzero,
            "retV": 100.0 * vodd / VREF,
            "yoddInt": yodd_int,
            "retYInt": 100.0 * yodd_int / (VREF * t) if t > 0 else 100.0,
            "jyodd": jyodd,
            "jyoddNorm": jyodd_norm,
        }
        prev_t = t
        prev_vodd = vodd

    # Exact final COM displacement from state dumps, when available.
    last_step = max(steps)
    y0m = state_com_y(minus_dir, 0)
    y1m = state_com_y(minus_dir, last_step)
    y0p = state_com_y(plus_dir, 0)
    y1p = state_com_y(plus_dir, last_step)
    exact_dyodd = float("nan")
    exact_retY = float("nan")
    if None not in (y0m, y1m, y0p, y1p):
        exact_dyodd = 0.5 * ((y1p-y0p) - (y1m-y0m))
        tlast = temporal[last_step]["time"]
        exact_retY = 100.0 * exact_dyodd / (VREF * tlast) if tlast > 0 else float("nan")

    all_modes[mode] = {
        "series": temporal,
        "last_step": last_step,
        "exact_dyodd": exact_dyodd,
        "exact_retY": exact_retY,
    }

print()
print("===== TEMPORAL ODD-MODE GALILEAN DIAGNOSTIC =====")
print("retV = 100 * (Vy_plus - Vy_minus)/(2*0.1)")
print("jyOdd = 0.5*(cumulative particle reflection impulse +V - -V)")
print()

for mode, data in all_modes.items():
    s = data["series"]
    print(f"--- {mode} ---")
    print(" step    time     Vodd       retV%    Veven      Vzero      Yodd_int   retYint%    JyOdd      JyOdd/(M V0)%")
    available = sorted(s)
    for target in CHECKPOINTS:
        step = target if target in s else closest_step(available, target)
        if step is None:
            continue
        r = s[step]
        print(
            f"{step:5d} {r['time']:7.4f} "
            f"{r['vodd']:+10.6f} {r['retV']:8.2f} "
            f"{r['veven']:+10.6f} {r['vzero']:+10.6f} "
            f"{r['yoddInt']:+10.6f} {r['retYInt']:9.2f} "
            f"{r['jyodd']:+10.4f} {r['jyoddNorm']:+13.2f}"
        )

    last = data["last_step"]
    r = s[last]
    print(
        f"final: step={last} retV={r['retV']:.2f}% "
        f"retY_integrated={r['retYInt']:.2f}% "
        f"retY_exact_dump={data['exact_retY']:.2f}% "
        f"JyOdd={r['jyodd']:+.6f}"
    )
    print(
        "first retV below: "
        f"95%={first_crossing(s,95.0)}  "
        f"90%={first_crossing(s,90.0)}  "
        f"85%={first_crossing(s,85.0)}"
    )
    print()

# Common comparison CSV for optional plotting.
out_csv = "runs/0493x10_galilean_temporal_odd_compare.csv"
os.makedirs(os.path.dirname(out_csv), exist_ok=True)
with open(out_csv, "w", newline="") as f:
    wr = csv.writer(f)
    wr.writerow([
        "mode","step","time","Vodd","retentionVPercent",
        "Veven","Vzero","YoddIntegrated","retentionYIntegratedPercent",
        "JyReflectOddCumulative","JyReflectOddOverInitialOddMomentumPercent"
    ])
    for mode, data in all_modes.items():
        for step in sorted(data["series"]):
            r = data["series"][step]
            wr.writerow([
                mode, step, f"{r['time']:.17g}", f"{r['vodd']:.17g}",
                f"{r['retV']:.17g}", f"{r['veven']:.17g}",
                f"{r['vzero']:.17g}", f"{r['yoddInt']:.17g}",
                f"{r['retYInt']:.17g}", f"{r['jyodd']:.17g}",
                f"{r['jyoddNorm']:.17g}",
            ])
print(f"[temporal] wrote {out_csv}")
