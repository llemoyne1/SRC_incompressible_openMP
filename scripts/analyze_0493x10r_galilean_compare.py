#!/usr/bin/env python3
import csv
import glob
import math
import os
import re
import struct
import sys
from array import array

TEND = 0.4
LIQUID_TYPE = 1

SETS = [
    ("Q6GF-only", "runs/0493x10_q6gf_only_x10oParams_R8_vy*"),
    ("Q6GF+x10o", "runs/0493x10o_galilean_x10oParams_R8_vy*"),
    ("Q6GF+x10r", "runs/0493x10r_galilean_x10oParams_R8_vy*"),
]

def read_array(f, code, n):
    a = array(code)
    nbytes = a.itemsize * n
    raw = f.read(nbytes)
    if len(raw) != nbytes:
        raise RuntimeError(f"truncated state: need {nbytes}, got {len(raw)}")
    a.frombytes(raw)
    if sys.byteorder == "big":
        a.byteswap()
    return a

def moments(path):
    with open(path, "rb") as f:
        magic = f.read(16)
        if not magic.startswith(b"SRCMPCD_STATE"):
            raise RuntimeError(f"{path}: bad magic")
        raw = f.read(struct.calcsize("<IIIIQIIII"))
        if len(raw) != struct.calcsize("<IIIIQIIII"):
            raise RuntimeError(f"{path}: truncated header")
        version, endian, dim, ns, n, a, b, rsv_n, word = struct.unpack(
            "<IIIIQIIII", raw
        )
        if version != 2:
            raise RuntimeError(f"{path}: expected state v2, got {version}")
        if endian != 0x01020304:
            raise RuntimeError(f"{path}: bad endian marker {endian:#x}")

        reserved = f.read(8 * 8)
        if len(reserved) != 8 * 8:
            raise RuntimeError(f"{path}: truncated reserved header")

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
        raise RuntimeError(f"{path}: no active liquid particles")

    M = sum(mass[i] for i in ids)
    cx = sum(mass[i] * x[i] for i in ids) / M
    cy = sum(mass[i] * y[i] for i in ids) / M
    ux = sum(mass[i] * vx[i] for i in ids) / M
    uy = sum(mass[i] * vy[i] for i in ids) / M
    Krel = 0.5 * sum(
        mass[i] * ((vx[i] - ux) ** 2 + (vy[i] - uy) ** 2)
        for i in ids
    )

    return {
        "N": len(ids),
        "M": M,
        "cx": cx,
        "cy": cy,
        "ux": ux,
        "uy": uy,
        "Py": M * uy,
        "KrelN": Krel / len(ids),
    }

def parse_vy(dirname):
    m = re.search(r"_vy(m?)([0-9]+)p([0-9]+)$", dirname)
    if not m:
        raise RuntimeError(f"cannot parse requested Vy from {dirname}")
    sign = -1.0 if m.group(1) == "m" else 1.0
    return sign * float(m.group(2) + "." + m.group(3))

def reflection_audit(dirname):
    p = os.path.join(
        dirname, "output", "cuda_phase_kinetic_crossing_0493x9z.csv"
    )
    if not os.path.exists(p):
        return float("nan"), float("nan"), 0, 0, 0, 0

    with open(p, newline="") as f:
        rows = list(csv.DictReader(f))

    jx = -sum(float(r["continuousWallImpulseX"]) for r in rows)
    jy = -sum(float(r["continuousWallImpulseY"]) for r in rows)
    nc = sum(int(float(r["continuousWallCollisions"])) for r in rows)

    def isum(name):
        return sum(int(float(r[name])) for r in rows) if rows and name in rows[0] else 0

    rel_out = isum("continuousWallRelativeStillOutward")
    no_seg = isum("continuousWallNoNearbySegment")
    overlap_fail = isum("x10qOverlapResolveFailure")
    return jx, jy, nc, rel_out, no_seg, overlap_fail

results = []

for mode, pattern in SETS:
    for d in glob.glob(pattern):
        try:
            vy_req = parse_vy(d)
        except RuntimeError:
            continue

        p0 = os.path.join(d, "output", "state_step_00000000.smpcd")
        p1 = os.path.join(d, "output", "state_step_00000200.smpcd")
        if not (os.path.exists(p0) and os.path.exists(p1)):
            continue

        s0 = moments(p0)
        s1 = moments(p1)
        jx, jy, nc, rel_out, no_seg, overlap_fail = reflection_audit(d)

        results.append({
            "mode": mode,
            "vy": vy_req,
            "s0": s0,
            "s1": s1,
            "jx": jx,
            "jy": jy,
            "nc": nc,
            "rel_out": rel_out,
            "no_seg": no_seg,
            "overlap_fail": overlap_fail,
        })

print(
    "mode        Vy_req  N200   Vy200       dVy        dY_COM      expected "
    " Krel/N200   JyReflect  collisions  relOut  noSeg  ovFail"
)

for r in sorted(results, key=lambda z: (z["mode"], z["vy"])):
    s0, s1 = r["s0"], r["s1"]
    print(
        f"{r['mode']:11s} "
        f"{r['vy']:+.3f} "
        f"{s1['N']:5d} "
        f"{s1['uy']:+11.6f} "
        f"{s1['uy']-s0['uy']:+11.6f} "
        f"{s1['cy']-s0['cy']:+11.6f} "
        f"{r['vy']*TEND:+11.6f} "
        f"{s1['KrelN']:10.6f} "
        f"{r['jy']:+11.5f} "
        f"{r['nc']:10d} "
        f"{r['rel_out']:7d} "
        f"{r['no_seg']:6d} "
        f"{r['overlap_fail']:7d}"
    )

print()
print("Odd-mode retention:")
for mode, _ in SETS:
    rr = {round(r["vy"], 3): r for r in results if r["mode"] == mode}
    if -0.1 not in rr or 0.1 not in rr:
        continue
    vminus = rr[-0.1]["s1"]["uy"]
    vplus = rr[+0.1]["s1"]["uy"]
    dyminus = rr[-0.1]["s1"]["cy"] - rr[-0.1]["s0"]["cy"]
    dyplus = rr[+0.1]["s1"]["cy"] - rr[+0.1]["s0"]["cy"]
    vodd = 0.5 * (vplus - vminus)
    dyodd = 0.5 * (dyplus - dyminus)

    jyminus = rr[-0.1]["jy"]
    jyplus = rr[+0.1]["jy"]
    jyodd = (
        0.5 * (jyplus - jyminus)
        if math.isfinite(jyminus) and math.isfinite(jyplus)
        else float("nan")
    )

    print(
        f"{mode:11s}: "
        f"Vy_odd={vodd:+.6f} "
        f"retention_V={100.0*vodd/0.1:6.2f}%   "
        f"dY_odd={dyodd:+.6f} "
        f"retention_Y={100.0*dyodd/0.04:6.2f}%   "
        f"JyReflect_odd={jyodd:+.6f}"
    )

print()
print("Reference already measured:")
print("  Q6GF-only : retention_V=91.14%, retention_Y=92.87%")
print("  Q6GF+x10o : retention_V=76.61%, retention_Y=87.50%")
print("x10r target: move materially toward Q6GF-only while keeping retention guards clean.")
