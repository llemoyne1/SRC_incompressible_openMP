#!/usr/bin/env python3
"""0493x14p - offline alpha/gas-volume audit for x14 liquid/gas drop runs.

Purpose
-------
Test whether the gas-count deficit seen by x6g on alpha<0.5 trace cells is
explained by the gas-accessible fraction inferred from the already-existing
phase fields.

No solver/source modification. Standard library only (no numpy/pandas/scipy).

For each existing state_step_*.smpcd dump this script reconstructs:
  1) x6g gas count N_g on the fixed Q6 cell grid;
  2) Q6/x6c-x6f2 alpha:
       raw = liquid cell mass / liquid reference cell mass
       g   = clamp(raw,0,1)
       alpha_q6 = five-point filter(g, lambda=0.125)
  3) x10 CIC kinetic alpha:
       raw_cic = CIC deposit(liquid normalized mass)
       alpha_cic = clamp(five-point filter(raw_cic, lambda=0.125),0,1)
  4) every Q6 alpha=0.5 crossing face and its alpha<0.5 gas-side cell.

On those face-weighted trace samples it evaluates:
  raw EOS count              N_g
  Q6-volume correction       N_g / (1-alpha_q6)
  kinetic-CIC-volume corr.   N_g / (1-alpha_cic)
  global multiplicative corr target/<N_g> (control)

It also reports regressions
    N_g/N_target ~ intercept + slope*(1-alpha)
and relative m=4 amplitudes before/after correction.

The x6g pressure CSV is used to infer liquidReferenceCellMass, cellArea, kBT,
pressureReference and therefore N_target = p_ref*A_cell/kBT. Its same-step
pressure mean/std are printed next to the offline reconstruction as a timing /
cell-deposit sanity check. Dumps are end-of-step states whereas x6g acts within
the step, so exact equality is not required.
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

MAGIC = b"SRCMPCD_STATE" + b"\0" * (16 - len(b"SRCMPCD_STATE"))
STEP_RE = re.compile(r"state_step_(\d+)\.smpcd$")
LAMBDA = 0.125


def clamp01(v: float) -> float:
    if v < 0.0:
        return 0.0
    if v > 1.0:
        return 1.0
    return v


def parse_kv(path: Path) -> dict[str, str]:
    d: dict[str, str] = {}
    for raw in path.read_text(errors="replace").splitlines():
        s = raw.strip()
        if not s or s.startswith("#") or "=" not in s:
            continue
        k, v = s.split("=", 1)
        d[k.strip()] = v.strip()
    return d


def first_num(d: dict[str, str], names, default=None):
    for k in names:
        if k in d:
            try:
                return float(d[k].split()[0])
            except Exception:
                pass
    if default is not None:
        return default
    raise KeyError("/".join(names))


def find_params(run: Path) -> Path:
    for p in (run / "output" / "params_used.kv", run / "params_used.kv"):
        if p.is_file():
            return p
    q = sorted((run / "params").glob("*.kv")) if (run / "params").is_dir() else []
    if len(q) == 1:
        return q[0]
    if q:
        return q[0]
    raise RuntimeError(f"cannot find params file under {run}")


def read_array(f, code: str, n: int):
    a = array(code)
    a.fromfile(f, n)
    if len(a) != n:
        raise RuntimeError("truncated state array")
    if sys.byteorder == "big":
        a.byteswap()
    return a


def read_state(path: Path):
    with path.open("rb") as f:
        if f.read(16) != MAGIC:
            raise RuntimeError(f"{path}: bad magic")
        h = f.read(struct.calcsize("<IIIIQIIII"))
        if len(h) != struct.calcsize("<IIIIQIIII"):
            raise RuntimeError(f"{path}: truncated header")
        version, endian, dim, layout, n, has_type, has_mass, real_size, type_size = struct.unpack(
            "<IIIIQIIII", h
        )
        reserved_raw = f.read(8 * 8)
        if len(reserved_raw) != 8 * 8:
            raise RuntimeError(f"{path}: truncated reserved header")
        reserved = struct.unpack("<8Q", reserved_raw)
        if version not in (1, 2) or endian != 0x01020304 or dim != 2 or layout != 1:
            raise RuntimeError(f"{path}: unsupported state header")
        if has_type != 1 or has_mass != 1 or real_size != 8 or type_size != 4:
            raise RuntimeError(f"{path}: unsupported scalar layout")
        n = int(n)
        x = read_array(f, "d", n)
        y = read_array(f, "d", n)
        # velocities are not needed here
        f.seek(16 * n, 1)
        typ = read_array(f, "I", n)
        mass = read_array(f, "d", n)
        if version == 2:
            if reserved[0] != 1:
                # Some historical V2 writers still carry a role payload with a
                # different reserved convention. Read it if present.
                role = bytearray(f.read(n))
                if len(role) != n:
                    raise RuntimeError(f"{path}: V2 role payload missing")
            else:
                role = bytearray(f.read(n))
                if len(role) != n:
                    raise RuntimeError(f"{path}: truncated role payload")
        else:
            role = bytearray([1]) * n
    return x, y, typ, mass, role


def dump_step(path: Path) -> int:
    m = STEP_RE.search(path.name)
    return int(m.group(1)) if m else -1


def load_pressure_audit(path: Path):
    rows = {}
    first = None
    with path.open(newline="") as f:
        for r in csv.DictReader(f):
            if first is None:
                first = r
            rows[int(float(r["step"]))] = r
    if first is None:
        raise RuntimeError(f"empty pressure audit: {path}")
    return first, rows


def periodic_from_params(p: dict[str, str]):
    bx = p.get("bcX", "").lower()
    by = p.get("bcY", "").lower()
    px = "periodic" in bx
    py = "periodic" in by
    # explicit paired face periodic settings if present
    if p.get("bcLeft", "").lower() == "periodic" and p.get("bcRight", "").lower() == "periodic":
        px = True
    if p.get("bcBottom", "").lower() == "periodic" and p.get("bcTop", "").lower() == "periodic":
        py = True
    return px, py


def cell_index(x: float, y: float, nx: int, ny: int, lx: float, ly: float, px: bool, py: bool):
    if px:
        x %= lx
    else:
        if x < 0.0:
            x = 0.0
        elif x >= lx:
            x = math.nextafter(lx, 0.0)
    if py:
        y %= ly
    else:
        if y < 0.0:
            y = 0.0
        elif y >= ly:
            y = math.nextafter(ly, 0.0)
    ix = int(x * nx / lx)
    iy = int(y * ny / ly)
    ix = max(0, min(nx - 1, ix))
    iy = max(0, min(ny - 1, iy))
    return iy * nx + ix


def cic_axis_pair(q: float, n: int, periodic: bool):
    fq = math.floor(q)
    a = int(fq)
    b = a + 1
    f = q - fq
    wa = 1.0 - f
    wb = f
    if periodic:
        a %= n
        b %= n
    else:
        a = max(0, min(n - 1, a))
        b = max(0, min(n - 1, b))
    if a == b:
        wa += wb
        wb = 0.0
    return a, b, wa, wb


def deposit_cic(raw, x: float, y: float, value: float, nx: int, ny: int, lx: float, ly: float, px: bool, py: bool):
    if px:
        x %= lx
    else:
        x = min(max(x, 0.0), math.nextafter(lx, 0.0))
    if py:
        y %= ly
    else:
        y = min(max(y, 0.0), math.nextafter(ly, 0.0))
    qx = x * nx / lx - 0.5
    qy = y * ny / ly - 0.5
    ix0, ix1, wx0, wx1 = cic_axis_pair(qx, nx, px)
    iy0, iy1, wy0, wy1 = cic_axis_pair(qy, ny, py)
    w00 = wx0 * wy0
    w10 = wx1 * wy0
    w01 = wx0 * wy1
    w11 = wx1 * wy1
    if w00 > 0.0:
        raw[iy0 * nx + ix0] += value * w00
    if w10 > 0.0:
        raw[iy0 * nx + ix1] += value * w10
    if w01 > 0.0:
        raw[iy1 * nx + ix0] += value * w01
    if w11 > 0.0:
        raw[iy1 * nx + ix1] += value * w11


def filter5(src, nx: int, ny: int, px: bool, py: bool, preclip: bool, postclip: bool):
    out = array("d", [0.0]) * (nx * ny)
    for iy in range(ny):
        row = iy * nx
        for ix in range(nx):
            c = row + ix
            center = clamp01(src[c]) if preclip else src[c]
            lap = 0.0
            if px or ix > 0:
                nb = row + ((ix - 1) % nx)
                v = clamp01(src[nb]) if preclip else src[nb]
                lap += v - center
            if px or ix < nx - 1:
                nb = row + ((ix + 1) % nx)
                v = clamp01(src[nb]) if preclip else src[nb]
                lap += v - center
            if py or iy > 0:
                nb = ((iy - 1) % ny) * nx + ix
                v = clamp01(src[nb]) if preclip else src[nb]
                lap += v - center
            if py or iy < ny - 1:
                nb = ((iy + 1) % ny) * nx + ix
                v = clamp01(src[nb]) if preclip else src[nb]
                lap += v - center
            v = center + LAMBDA * lap
            out[c] = clamp01(v) if postclip else v
    return out


def mean_std(vals):
    n = len(vals)
    if n == 0:
        return math.nan, math.nan
    m = sum(vals) / n
    v = sum((x - m) ** 2 for x in vals) / n
    return m, math.sqrt(max(0.0, v))


def rms_error(vals, target):
    if not vals:
        return math.nan
    return math.sqrt(sum((x - target) ** 2 for x in vals) / len(vals))


def regression(x, y):
    n = len(x)
    if n < 2:
        return (math.nan,) * 5
    mx = sum(x) / n
    my = sum(y) / n
    sxx = sum((v - mx) ** 2 for v in x)
    sxy = sum((a - mx) * (b - my) for a, b in zip(x, y))
    slope = sxy / sxx if sxx > 1e-30 else math.nan
    intercept = my - slope * mx if math.isfinite(slope) else math.nan
    ss_tot = sum((v - my) ** 2 for v in y)
    ss_res = sum((b - (intercept + slope * a)) ** 2 for a, b in zip(x, y)) if math.isfinite(slope) else math.nan
    r2 = 1.0 - ss_res / ss_tot if ss_tot > 1e-30 and math.isfinite(ss_res) else math.nan
    sxx0 = sum(a * a for a in x)
    slope0 = sum(a * b for a, b in zip(x, y)) / sxx0 if sxx0 > 1e-30 else math.nan
    rms0 = math.sqrt(sum((b - slope0 * a) ** 2 for a, b in zip(x, y)) / n) if math.isfinite(slope0) else math.nan
    return intercept, slope, r2, slope0, rms0


def solve3(a, b):
    # Gaussian elimination, 3x3.
    m = [list(a[i]) + [b[i]] for i in range(3)]
    for col in range(3):
        piv = max(range(col, 3), key=lambda r: abs(m[r][col]))
        if abs(m[piv][col]) < 1e-20:
            return None
        m[col], m[piv] = m[piv], m[col]
        q = m[col][col]
        for j in range(col, 4):
            m[col][j] /= q
        for r in range(3):
            if r == col:
                continue
            q = m[r][col]
            for j in range(col, 4):
                m[r][j] -= q * m[col][j]
    return [m[i][3] for i in range(3)]


def mode4_relative(theta, vals):
    if len(vals) < 6:
        return math.nan
    s0 = float(len(vals))
    sc = ss = scc = sss = scs = 0.0
    sy = syc = sys_ = 0.0
    for th, y in zip(theta, vals):
        c = math.cos(4.0 * th)
        s = math.sin(4.0 * th)
        sc += c; ss += s; scc += c*c; sss += s*s; scs += c*s
        sy += y; syc += y*c; sys_ += y*s
    sol = solve3(((s0, sc, ss), (sc, scc, scs), (ss, scs, sss)), (sy, syc, sys_))
    if sol is None or abs(sol[0]) < 1e-30:
        return math.nan
    a0, ac, ass = sol
    return math.hypot(ac, ass) / abs(a0)


def face_samples(alpha_q6, alpha_cic, gas_count, nx, ny, lx, ly, px, py, comx, comy):
    recs = []
    dx = lx / nx
    dy = ly / ny
    for iy in range(ny):
        for ix in range(nx):
            c = iy * nx + ix
            # East face
            if px or ix < nx - 1:
                jx = (ix + 1) % nx
                nb = iy * nx + jx
                a0, a1 = alpha_q6[c], alpha_q6[nb]
                if (a0 >= 0.5 and a1 < 0.5) or (a1 >= 0.5 and a0 < 0.5):
                    gasc = nb if a0 >= 0.5 else c
                    den = abs(a0 - a1)
                    # Interface position from linear alpha interpolation between cell centers.
                    t = (0.5 - a0) / (a1 - a0) if den > 1e-14 else 0.5
                    x0 = (ix + 0.5) * dx
                    x1 = (jx + 0.5) * dx
                    if px and jx == 0 and ix == nx - 1:
                        x1 = lx + 0.5 * dx
                    xf = x0 + t * (x1 - x0)
                    if px:
                        xf %= lx
                    yf = (iy + 0.5) * dy
                    th = math.atan2(yf - comy, xf - comx)
                    recs.append(("x", c, nb, gasc, xf, yf, th))
            # North face
            if py or iy < ny - 1:
                jy = (iy + 1) % ny
                nb = jy * nx + ix
                a0, a1 = alpha_q6[c], alpha_q6[nb]
                if (a0 >= 0.5 and a1 < 0.5) or (a1 >= 0.5 and a0 < 0.5):
                    gasc = nb if a0 >= 0.5 else c
                    den = abs(a0 - a1)
                    t = (0.5 - a0) / (a1 - a0) if den > 1e-14 else 0.5
                    y0 = (iy + 0.5) * dy
                    y1 = (jy + 0.5) * dy
                    if py and jy == 0 and iy == ny - 1:
                        y1 = ly + 0.5 * dy
                    yf = y0 + t * (y1 - y0)
                    if py:
                        yf %= ly
                    xf = (ix + 0.5) * dx
                    th = math.atan2(yf - comy, xf - comx)
                    recs.append(("y", c, nb, gasc, xf, yf, th))
    return recs


def fmt(v):
    if isinstance(v, int):
        return str(v)
    if not isinstance(v, float):
        return str(v)
    if not math.isfinite(v):
        return "nan"
    return f"{v:.8g}"


def analyze_dump(path: Path, cfg, audit_rows, face_writer):
    step = dump_step(path)
    x, y, typ, mass, role = read_state(path)
    ncell = cfg["nx"] * cfg["ny"]
    liq_mass = array("d", [0.0]) * ncell
    gas_count = array("I", [0]) * ncell
    raw_cic = array("d", [0.0]) * ncell
    ml = sx = sy = 0.0

    inv_ref = 1.0 / cfg["liquid_ref_mass"]
    for i in range(len(x)):
        if role[i] != 1:
            continue
        ti = typ[i]
        if ti == cfg["liquid_type"]:
            mi = mass[i]
            c = cell_index(x[i], y[i], cfg["nx"], cfg["ny"], cfg["lx"], cfg["ly"], cfg["px"], cfg["py"])
            liq_mass[c] += mi
            deposit_cic(raw_cic, x[i], y[i], mi * inv_ref,
                        cfg["nx"], cfg["ny"], cfg["lx"], cfg["ly"], cfg["px"], cfg["py"])
            ml += mi; sx += mi * x[i]; sy += mi * y[i]
        elif ti == cfg["gas_type"]:
            c = cell_index(x[i], y[i], cfg["nx"], cfg["ny"], cfg["lx"], cfg["ly"], cfg["px"], cfg["py"])
            gas_count[c] += 1

    comx = sx / ml if ml > 0 else 0.5 * cfg["lx"]
    comy = sy / ml if ml > 0 else 0.5 * cfg["ly"]
    raw_q6 = array("d", (v * inv_ref for v in liq_mass))
    # Current x6f2 geometry: clamp raw before conservative filter.
    alpha_q6 = filter5(raw_q6, cfg["nx"], cfg["ny"], cfg["px"], cfg["py"], preclip=True, postclip=False)
    # Qualified kinetic CIC: CIC -> filter unbounded raw -> final clamp.
    alpha_cic = filter5(raw_cic, cfg["nx"], cfg["ny"], cfg["px"], cfg["py"], preclip=False, postclip=True)

    faces = face_samples(alpha_q6, alpha_cic, gas_count,
                         cfg["nx"], cfg["ny"], cfg["lx"], cfg["ly"], cfg["px"], cfg["py"], comx, comy)
    ng = []
    fq = []
    fk = []
    cq = []
    ck = []
    th = []
    cic_bad = 0
    minf = cfg["min_fraction"]
    for axis, c0, c1, gc, xf, yf, theta in faces:
        n_g = float(gas_count[gc])
        f_q = 1.0 - alpha_q6[gc]
        f_k = 1.0 - alpha_cic[gc]
        c_q = n_g / max(f_q, minf)
        c_k = n_g / max(f_k, minf)
        if f_k < minf:
            cic_bad += 1
        ng.append(n_g); fq.append(f_q); fk.append(f_k); cq.append(c_q); ck.append(c_k); th.append(theta)
        if face_writer is not None:
            face_writer.writerow({
                "step": step, "axis": axis, "gasCell": gc,
                "xFace": xf, "yFace": yf, "theta": theta,
                "Ng": n_g, "alphaQ6": alpha_q6[gc], "gasFracQ6": f_q,
                "alphaCIC": alpha_cic[gc], "gasFracCIC": f_k,
                "NgCorrQ6": c_q, "NgCorrCIC": c_k,
            })

    target = cfg["target_count"]
    ngm, ngs = mean_std(ng)
    fqm, fqs = mean_std(fq)
    fkm, fks = mean_std(fk)
    cqm, cqs = mean_std(cq)
    ckm, cks = mean_std(ck)
    global_factor = target / ngm if ngm > 0 else math.nan
    cg = [v * global_factor for v in ng] if math.isfinite(global_factor) else []
    cgm, cgs = mean_std(cg)

    yrel = [v / target for v in ng]
    regq = regression(fq, yrel)
    regk = regression(fk, yrel)

    raw_m4 = mode4_relative(th, ng)
    fq_m4 = mode4_relative(th, fq)
    fk_m4 = mode4_relative(th, fk)
    q_m4 = mode4_relative(th, cq)
    k_m4 = mode4_relative(th, ck)
    g_m4 = mode4_relative(th, cg)

    aud = audit_rows.get(step)
    rec_mean = rec_std = math.nan
    off_dp_mean = off_dp_std = math.nan
    if ng:
        unitp = cfg["kbt"] / cfg["cell_area"]
        off_dp = [v * unitp - cfg["p_ref"] for v in ng]
        off_dp_mean, off_dp_std = mean_std(off_dp)
    if aud is not None:
        rec_mean = float(aud.get("pressureDeltaMean", "nan"))
        rec_std = float(aud.get("pressureDeltaStd", "nan"))

    return {
        "step": step,
        "faces": len(faces),
        "liquidCOMx": comx, "liquidCOMy": comy,
        "targetGasCount": target,
        "NgMean": ngm, "NgStd": ngs, "NgRmsErr": rms_error(ng, target),
        "globalFactor": global_factor, "globalCorrStd": cgs, "globalCorrRmsErr": rms_error(cg, target),
        "gasFracQ6Mean": fqm, "gasFracQ6Std": fqs,
        "q6CorrMean": cqm, "q6CorrStd": cqs, "q6CorrRmsErr": rms_error(cq, target),
        "q6RegIntercept": regq[0], "q6RegSlope": regq[1], "q6RegR2": regq[2],
        "q6RegSlope0": regq[3], "q6RegRms0": regq[4],
        "gasFracCICMean": fkm, "gasFracCICStd": fks, "cicFractionClampedFaces": cic_bad,
        "cicCorrMean": ckm, "cicCorrStd": cks, "cicCorrRmsErr": rms_error(ck, target),
        "cicRegIntercept": regk[0], "cicRegSlope": regk[1], "cicRegR2": regk[2],
        "cicRegSlope0": regk[3], "cicRegRms0": regk[4],
        "m4RawNgRel": raw_m4, "m4GasFracQ6Rel": fq_m4, "m4Q6CorrRel": q_m4,
        "m4GasFracCICRel": fk_m4, "m4CICCorrRel": k_m4, "m4GlobalCorrRel": g_m4,
        "offlineDeltaPMean": off_dp_mean, "offlineDeltaPStd": off_dp_std,
        "recordedDeltaPMean": rec_mean, "recordedDeltaPStd": rec_std,
        "deltaPMeanMismatch": off_dp_mean - rec_mean if math.isfinite(rec_mean) else math.nan,
        "deltaPStdMismatch": off_dp_std - rec_std if math.isfinite(rec_std) else math.nan,
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--run", type=Path, required=True, help="run root containing output/state_step_*.smpcd")
    ap.add_argument("--liquid-type", type=int, default=1)
    ap.add_argument("--gas-type", type=int, default=2)
    ap.add_argument("--steps", default="all", help="all or comma-separated dump steps, e.g. 100,300,500,700,1000")
    ap.add_argument("--min-fraction", type=float, default=0.10, help="denominator floor for candidate volume correction")
    ap.add_argument("--output-prefix", default="alpha_gas_volume_0493x14p")
    args = ap.parse_args()

    run = args.run.resolve()
    params_path = find_params(run)
    p = parse_kv(params_path)
    nx = int(round(first_num(p, ("Nx", "NX"))))
    ny = int(round(first_num(p, ("Ny", "NY"))))
    lx = first_num(p, ("Lx", "LX"))
    ly = first_num(p, ("Ly", "LY"))
    px, py = periodic_from_params(p)

    pressure_path = run / "output" / "cuda_phase_interface_pressure_0493x6g.csv"
    if not pressure_path.is_file():
        raise SystemExit(f"missing {pressure_path}")
    first, audit_rows = load_pressure_audit(pressure_path)
    liquid_ref = float(first["liquidReferenceCellMass"])
    cell_area = float(first["cellArea"])
    kbt = float(first["kBT"])
    p_ref = float(first["pressureReference"])
    target = p_ref * cell_area / kbt if kbt > 0 else math.nan

    cfg = dict(nx=nx, ny=ny, lx=lx, ly=ly, px=px, py=py,
               liquid_type=args.liquid_type, gas_type=args.gas_type,
               liquid_ref_mass=liquid_ref, cell_area=cell_area, kbt=kbt, p_ref=p_ref,
               target_count=target, min_fraction=args.min_fraction)

    dumps = sorted((run / "output").glob("state_step_*.smpcd"), key=dump_step)
    if args.steps != "all":
        wanted = {int(s.strip()) for s in args.steps.split(",") if s.strip()}
        dumps = [d for d in dumps if dump_step(d) in wanted]
    if not dumps:
        raise SystemExit("no matching state dumps")

    analysis = run / "analysis"
    analysis.mkdir(parents=True, exist_ok=True)
    summary_path = analysis / f"{args.output_prefix}_summary.csv"
    faces_path = analysis / f"{args.output_prefix}_faces.csv"

    face_fields = ["step", "axis", "gasCell", "xFace", "yFace", "theta", "Ng",
                   "alphaQ6", "gasFracQ6", "alphaCIC", "gasFracCIC", "NgCorrQ6", "NgCorrCIC"]
    rows = []
    with faces_path.open("w", newline="") as ff:
        fw = csv.DictWriter(ff, fieldnames=face_fields)
        fw.writeheader()
        for d in dumps:
            print(f"[0493x14p] reading {d.name} ...", flush=True)
            r = analyze_dump(d, cfg, audit_rows, fw)
            rows.append(r)
            print(
                "[0493x14p] step={step} faces={faces} "
                "Ng={NgMean:.3f}+/-{NgStd:.3f} target={targetGasCount:.3f} "
                "Q6corr={q6CorrMean:.3f}+/-{q6CorrStd:.3f} R2={q6RegR2:.3f} m4={m4Q6CorrRel:.4f} "
                "CICcorr={cicCorrMean:.3f}+/-{cicCorrStd:.3f} R2={cicRegR2:.3f} m4={m4CICCorrRel:.4f} "
                "rawm4={m4RawNgRel:.4f}".format(**r),
                flush=True,
            )

    fields = list(rows[0].keys())
    with summary_path.open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fields)
        w.writeheader(); w.writerows(rows)

    print("\n===== 0493x14p ALPHA / GAS-VOLUME OFFLINE AUDIT =====")
    print(f"run={run}")
    print(f"grid={nx}x{ny} L={lx}x{ly} periodic=({int(px)},{int(py)})")
    print(f"liquidRefCellMass={liquid_ref:.9g} targetGasCount={target:.9g} kBT={kbt:.9g} cellArea={cell_area:.9g}")
    print("Q6 geometry reconstructed as x6f2: clamp(raw)->5pt(lambda=.125), no post-clamp needed")
    print("CIC geometry reconstructed as qualified x10: CIC->5pt(lambda=.125)->clamp")
    print("\nstep faces  NgMean  fQmean Q6corr  R2_Q6  m4raw m4Qcorr  fKmean CICcorr R2_CIC m4Ccorr  dPoff-dPrec")
    for r in rows:
        vals = [r["step"], r["faces"], r["NgMean"], r["gasFracQ6Mean"], r["q6CorrMean"], r["q6RegR2"],
                r["m4RawNgRel"], r["m4Q6CorrRel"], r["gasFracCICMean"], r["cicCorrMean"], r["cicRegR2"],
                r["m4CICCorrRel"], r["deltaPMeanMismatch"]]
        print(" ".join(fmt(v) for v in vals))

    print("\nInterpretation targets:")
    print("  * useful alpha-volume correction: corrected mean -> target, RMS/std fall, regression R2 rises,")
    print("    and especially m4(corrected) << m4(raw Ng).")
    print("  * global scalar factor fixes only the mean; relative m4 is mathematically unchanged.")
    print("  * Q6 alpha is the cheap candidate already resident in x6g; CIC alpha is diagnostic because")
    print("    it is closer to the actual kinetic wall used by the gas reflection.")
    print(f"summary={summary_path}")
    print(f"faces={faces_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
