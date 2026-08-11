#!/usr/bin/env python3
"""Offline signed/asymmetric x7d density-relaxation scan.

Purpose
-------
Keep the qualified x7d-v2 positive compression gate unchanged and add an
OFFLINE candidate traction branch for coherent negative density defects:

    S+ =  dN/(gamma*tau)       if dN >= +theta+ and K+ neighbours agree
    S- = g- dN/(gamma*tau)     if dN <= -theta- and K- neighbours agree
    S  = S+ + S-

No solver/code modification is performed.

The scan asks whether there is a negative-side threshold theta- and gain g-
that (i) removes the positive source bias in full-domain Poiseuille while
(ii) leaving the successful dam-break primarily compression-driven.

For the dam-break, the x6f pressure-domain reconstruction is necessarily
approximate from particle dumps: liquid fill >= bulk_fill_min followed by the
same existing-neighbour bulk condition used by x7d.  Poiseuille fullDomain is
reconstructed exactly from the dump geometry.
"""
from __future__ import annotations

import argparse
import csv
import importlib
import math
import re
import sys
from collections import defaultdict
from pathlib import Path

import numpy as np

THETA_MINUS_DEFAULT = (2.0, 3.0, 4.0, 5.0, 6.0)
GAIN_MINUS_DEFAULT = (0.25, 0.50, 0.75, 1.00, 1.25, 1.50)


def parse_args():
    ap = argparse.ArgumentParser()
    ap.add_argument("--poiseuille-root", type=Path, required=True)
    ap.add_argument("--dam-root", type=Path, required=True)
    ap.add_argument("--out", type=Path, required=True)
    ap.add_argument("--theta-plus", type=float, default=3.0)
    ap.add_argument("--theta-minus", type=float, nargs="*", default=list(THETA_MINUS_DEFAULT))
    ap.add_argument("--gain-minus", type=float, nargs="*", default=list(GAIN_MINUS_DEFAULT))
    ap.add_argument("--k-plus", type=int, default=1)
    ap.add_argument("--k-minus", type=int, default=1)
    ap.add_argument("--tau", type=float, default=0.25)
    ap.add_argument("--poiseuille-gamma", type=float, default=20.0)
    ap.add_argument("--dam-gamma", type=float, default=10.0)
    ap.add_argument("--dam-liquid-type", type=int, default=1)
    ap.add_argument("--dam-bulk-fill-min", type=float, default=0.50)
    ap.add_argument("--dam-stride", type=int, default=1)
    return ap.parse_args()


def import_reader():
    scripts = Path("scripts").resolve()
    if str(scripts) not in sys.path:
        sys.path.insert(0, str(scripts))
    return importlib.import_module("analyze_0493w1_src_fluid_calibrator")


def output_dir(root: Path) -> Path:
    if (root / "output").is_dir():
        return root / "output"
    if root.is_dir() and list(root.glob("state_step_*.smpcd")):
        return root
    hits = sorted(root.glob("**/output"))
    hits = [p for p in hits if list(p.glob("state_step_*.smpcd"))]
    if len(hits) == 1:
        return hits[0]
    raise FileNotFoundError(f"cannot uniquely locate output dumps below {root}")


def read_kv(path: Path):
    out = {}
    if not path.exists():
        return out
    for line in path.read_text(errors="replace").splitlines():
        line = line.split("#", 1)[0].strip()
        if not line or "=" not in line:
            continue
        k, v = line.split("=", 1)
        out[k.strip()] = v.strip()
    return out


def fkv(kv, names, fallback):
    lower = {k.lower(): v for k, v in kv.items()}
    for n in names:
        if n.lower() in lower:
            try:
                return float(lower[n.lower()])
            except Exception:
                pass
    return float(fallback)


def ikv(kv, names, fallback):
    return int(round(fkv(kv, names, fallback)))


def infer_meta(out: Path, kind: str, gamma: float):
    kv = read_kv(out / "params_used.kv")
    if kind == "poiseuille":
        defaults = dict(Lx=2.0, Ly=1.0, Nx=192, Ny=96, dt=0.001)
    else:
        defaults = dict(Lx=2.0, Ly=1.0, Nx=300, Ny=150, dt=0.005)
    return {
        "kind": kind,
        "Lx": fkv(kv, ("Lx", "lx"), defaults["Lx"]),
        "Ly": fkv(kv, ("Ly", "ly"), defaults["Ly"]),
        "Nx": ikv(kv, ("Nx", "nx"), defaults["Nx"]),
        "Ny": ikv(kv, ("Ny", "ny"), defaults["Ny"]),
        "dt": fkv(kv, ("dt", "DT"), defaults["dt"]),
        "gamma": float(gamma),
    }


def list_dumps(out: Path, stride: int):
    rx = re.compile(r"^state_step_(\d+)\.smpcd$")
    rows = []
    for p in sorted(out.glob("state_step_*.smpcd")):
        m = rx.match(p.name)
        if m and int(m.group(1)) > 0:
            rows.append((int(m.group(1)), p))
    rows.sort()
    if stride > 1:
        rows = rows[::stride]
    if not rows:
        raise FileNotFoundError(f"no nonzero state_step dumps in {out}")
    return rows


def state_key(state, names, required=True):
    for n in names:
        if n in state:
            return n
    if required:
        raise KeyError(f"none of {names} in state keys={sorted(state)}")
    return None


def select(state, kind: str, liquid_type: int):
    n = len(state[state_key(state, ("x",))])
    role_key = state_key(state, ("role",), required=False)
    if role_key is None:
        m = np.ones(n, bool)
    else:
        m = np.asarray(state[role_key]) == 1
    if kind == "dam":
        tk = state_key(state, ("type", "ptype", "particleType", "particle_type"))
        m &= np.asarray(state[tk]) == int(liquid_type)
    return m


def reconstruct(state, meta, liquid_type):
    sel = select(state, meta["kind"], liquid_type)
    x = np.asarray(state[state_key(state, ("x",))], float)[sel]
    y = np.asarray(state[state_key(state, ("y",))], float)[sel]
    mass = np.asarray(state[state_key(state, ("mass", "m"))], float)[sel]

    nx, ny = meta["Nx"], meta["Ny"]
    lx, ly = meta["Lx"], meta["Ly"]

    if meta["kind"] == "poiseuille":
        x = np.mod(x, lx)
        y = np.clip(y, 0.0, np.nextafter(ly, 0.0))
    else:
        x = np.clip(x, 0.0, np.nextafter(lx, 0.0))
        y = np.clip(y, 0.0, np.nextafter(ly, 0.0))

    ix = np.floor(x * nx / lx).astype(np.int64)
    iy = np.floor(y * ny / ly).astype(np.int64)
    np.clip(ix, 0, nx - 1, out=ix)
    np.clip(iy, 0, ny - 1, out=iy)
    cid = iy * nx + ix

    cell_mass = np.bincount(cid, weights=mass, minlength=nx * ny).reshape(ny, nx)

    # Species have fixed particle mass in the two qualification cases.  Infer
    # it from the dump instead of hard-coding 1 / 1000.
    positive_mass = mass[mass > 0.0]
    if len(positive_mass) == 0:
        raise ValueError("no positive selected particle masses")
    mp = float(np.median(positive_mass))
    ref = float(meta["gamma"]) * mp
    fill = cell_mass / ref
    dN = float(meta["gamma"]) * (fill - 1.0)
    occupied = cell_mass > 0.0
    return dN, fill, occupied, mp


def existing_neighbour_bulk(mask: np.ndarray, periodic_x: bool, periodic_y: bool):
    """x7d bulk rule: all EXISTING face neighbours must be in pressure mask."""
    mask = np.asarray(mask, bool)
    ny, nx = mask.shape
    out = mask.copy()

    if periodic_x:
        out &= np.roll(mask, 1, axis=1) & np.roll(mask, -1, axis=1)
    else:
        tmp = np.ones_like(mask)
        tmp[:, 1:] &= mask[:, :-1]
        tmp[:, :-1] &= mask[:, 1:]
        out &= tmp

    if periodic_y:
        out &= np.roll(mask, 1, axis=0) & np.roll(mask, -1, axis=0)
    else:
        tmp = np.ones_like(mask)
        tmp[1:, :] &= mask[:-1, :]
        tmp[:-1, :] &= mask[1:, :]
        out &= tmp

    return out


def neighbour_count4(active: np.ndarray, periodic_x: bool, periodic_y: bool):
    a = np.asarray(active, bool)
    n = np.zeros(a.shape, np.int8)
    if periodic_x:
        n += np.roll(a, 1, axis=1).astype(np.int8)
        n += np.roll(a, -1, axis=1).astype(np.int8)
    else:
        n[:, 1:] += a[:, :-1]
        n[:, :-1] += a[:, 1:]
    if periodic_y:
        n += np.roll(a, 1, axis=0).astype(np.int8)
        n += np.roll(a, -1, axis=0).astype(np.int8)
    else:
        n[1:, :] += a[:-1, :]
        n[:-1, :] += a[1:, :]
    return n


def read_cuda_target(out: Path):
    p = out / "cuda_species_q6_independent_masked_0493w5.csv"
    if not p.exists():
        return {}
    with p.open() as f:
        return {
            int(float(r["step"])): float(r["densityRelaxationTargetDivRms"])
            for r in csv.DictReader(f)
            if r.get("densityRelaxationTargetDivRms", "") != ""
        }


def frame_components(dN, fill, occupied, kind, theta_plus, theta_minus_values,
                     kplus, kminus, tau, bulk_fill_min):
    if kind == "poiseuille":
        periodic_x, periodic_y = True, False
        pressure = np.ones_like(dN, bool)  # fullDomain=1
    else:
        periodic_x, periodic_y = False, False
        # Offline proxy already used in the qualified x7n studies.
        pressure = occupied & (fill >= bulk_fill_min)

    bulk = existing_neighbour_bulk(pressure, periodic_x, periodic_y)
    norm_count = int(np.count_nonzero(pressure))
    if norm_count == 0:
        raise ValueError("empty reconstructed pressure domain")

    over = bulk & (dN >= theta_plus)
    nplus = neighbour_count4(over, periodic_x, periodic_y)
    gate_plus = over & (nplus >= kplus)
    splus = np.zeros_like(dN, float)
    splus[gate_plus] = dN[gate_plus] / (float(tau) * 1.0)  # divide gamma below
    # dN = gamma*defect
    # source = defect/tau = dN/(gamma*tau)

    result = {
        "pressureCells": norm_count,
        "bulkCells": int(np.count_nonzero(bulk)),
        "gatePlus": gate_plus,
        "splus": splus,
        "periodicX": periodic_x,
        "periodicY": periodic_y,
    }

    negatives = {}
    for tm in theta_minus_values:
        under = bulk & (dN <= -float(tm))
        nminus = neighbour_count4(under, periodic_x, periodic_y)
        gate_minus = under & (nminus >= kminus)
        sminus_base = np.zeros_like(dN, float)
        sminus_base[gate_minus] = dN[gate_minus] / float(tau)
        negatives[float(tm)] = (gate_minus, sminus_base)
    result["negative"] = negatives
    return result


def metrics_from_sources(comp, gamma, gain, theta_minus):
    denom = comp["pressureCells"]
    gp = comp["gatePlus"]
    gm, smbase = comp["negative"][float(theta_minus)]
    sp = comp["splus"] / float(gamma)
    sm = (float(gain) * smbase) / float(gamma)
    st = sp + sm

    # Source is zero outside x7d bulk but the full-domain Poiseuille compatibility
    # mean is over the whole pressure mask, so normalize over pressure cells.
    mean_p = float(np.sum(sp) / denom)
    mean_m = float(np.sum(sm) / denom)
    mean_t = mean_p + mean_m
    rms_p = float(np.sqrt(np.sum(sp * sp) / denom))
    rms_m = float(np.sqrt(np.sum(sm * sm) / denom))
    rms_t = float(np.sqrt(np.sum(st * st) / denom))
    rms_centered = float(np.sqrt(max(0.0, rms_t * rms_t - mean_t * mean_t)))

    return {
        "gatePlusFraction": float(np.count_nonzero(gp) / denom),
        "gateMinusFraction": float(np.count_nonzero(gm) / denom),
        "meanPlus": mean_p,
        "meanMinus": mean_m,
        "meanSigned": mean_t,
        "rmsPlus": rms_p,
        "rmsMinus": rms_m,
        "rmsSigned": rms_t,
        "rmsSignedCentered": rms_centered,
        "meanCancellationFraction": (
            1.0 - abs(mean_t) / mean_p if mean_p > 0.0 else math.nan
        ),
        "tractionToCompressionMeanRatio": (
            abs(mean_m) / mean_p if mean_p > 0.0 else math.nan
        ),
    }


def write_csv(path: Path, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    if not rows:
        path.write_text("")
        return
    fields = []
    seen = set()
    for r in rows:
        for k in r:
            if k not in seen:
                fields.append(k); seen.add(k)
    with path.open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=fields)
        w.writeheader(); w.writerows(rows)


def mean_rows(rows, pred):
    rr = [r for r in rows if pred(r)]
    if not rr:
        return None
    keys = [k for k, v in rr[0].items() if isinstance(v, (int, float))]
    out = {"frames": len(rr)}
    for k in keys:
        a = np.array([float(r[k]) for r in rr if math.isfinite(float(r[k]))], float)
        if len(a): out[k] = float(np.mean(a))
    return out


def main():
    a = parse_args()
    if a.tau <= 0 or a.poiseuille_gamma <= 0 or a.dam_gamma <= 0:
        raise ValueError("tau/gamma must be >0")
    if a.k_plus < 0 or a.k_minus < 0:
        raise ValueError("K must be >=0")

    base = import_reader()
    pout = output_dir(a.poiseuille_root)
    dout = output_dir(a.dam_root)
    pmeta = infer_meta(pout, "poiseuille", a.poiseuille_gamma)
    dmeta = infer_meta(dout, "dam", a.dam_gamma)

    print("=== 0493x7d SIGNED / ASYMMETRIC TRACTION SCAN ===")
    print(f"Poiseuille output: {pout}")
    print(f"Dam-break output : {dout}")
    print(f"Poiseuille meta  : {pmeta}")
    print(f"Dam-break meta   : {dmeta}")
    print(f"positive branch  : theta+={a.theta_plus:g} dN, K+={a.k_plus}, gain+=1")
    print(f"negative theta   : {list(map(float,a.theta_minus))}")
    print(f"negative gains   : {list(map(float,a.gain_minus))}")
    print(f"tau proxy        : {a.tau:g}")
    print()

    all_rows = []
    validation = []
    cuda_p = read_cuda_target(pout)

    for case, out, meta, stride in (
        ("poiseuille", pout, pmeta, 1),
        ("dam", dout, dmeta, max(1, a.dam_stride)),
    ):
        print(f"[scan] reading {case} dumps...", file=sys.stderr)
        for step, path in list_dumps(out, stride):
            st = base.read_state(path)
            dN, fill, occupied, mp = reconstruct(st, meta, a.dam_liquid_type)
            comp = frame_components(
                dN, fill, occupied, case,
                a.theta_plus, a.theta_minus, a.k_plus, a.k_minus,
                a.tau, a.dam_bulk_fill_min,
            )

            # Positive-only validation/reference.
            ref = metrics_from_sources(comp, meta["gamma"], 0.0, float(a.theta_minus[0]))
            if case == "poiseuille" and step in cuda_p and cuda_p[step] > 0:
                rel = abs(ref["rmsPlus"] - cuda_p[step]) / cuda_p[step]
                validation.append((step, ref["rmsPlus"], cuda_p[step], rel))

            for tm in map(float, a.theta_minus):
                for gm in map(float, a.gain_minus):
                    mm = metrics_from_sources(comp, meta["gamma"], gm, tm)
                    all_rows.append({
                        "case": case,
                        "step": int(step),
                        "time": float(step) * meta["dt"],
                        "particleMassInferred": mp,
                        "thetaPlusDN": float(a.theta_plus),
                        "thetaMinusDN": tm,
                        "gainMinus": gm,
                        "kPlus": int(a.k_plus),
                        "kMinus": int(a.k_minus),
                        **mm,
                    })

    # Validation must be good before interpreting the signed scan.
    if validation:
        med = float(np.median([x[3] for x in validation]))
        mx = float(np.max([x[3] for x in validation]))
        print("=== Poiseuille positive-only reconstruction vs CUDA ===")
        print(f"matched frames={len(validation)} medianRelErr={med:.5f} maxRelErr={mx:.5f}")
        for step, off, cu, rel in validation:
            if step in (500, 3000, 5000, 7000, 8000, 9000, 10000, 11000, 12000):
                print(f"{step:5d} offline={off:.9f} cuda={cu:.9f} rel={rel:.4f}")
        print()
        if med > 0.05:
            raise SystemExit(
                "ERROR: positive-only reconstruction differs by >5% median from CUDA; "
                "do not interpret signed scan"
            )

    write_csv(a.out / "signed_traction_scan_frames_0493x7d.csv", all_rows)

    # Aggregate candidate table over the physically discriminating windows.
    agg_rows = []
    theta_vals = list(map(float, a.theta_minus))
    gain_vals = list(map(float, a.gain_minus))
    for tm in theta_vals:
        for gm in gain_vals:
            sub = [r for r in all_rows if r["thetaMinusDN"] == tm and r["gainMinus"] == gm]
            windows = (
                ("pois_early", lambda r: r["case"] == "poiseuille" and 500 <= r["step"] <= 7000),
                ("pois_onset", lambda r: r["case"] == "poiseuille" and 7500 <= r["step"] <= 10000),
                ("pois_late", lambda r: r["case"] == "poiseuille" and 10000 <= r["step"] <= 12000),
                ("dam_early", lambda r: r["case"] == "dam" and 1 <= r["step"] <= 500),
                ("dam_mid", lambda r: r["case"] == "dam" and 501 <= r["step"] <= 2500),
                ("dam_late", lambda r: r["case"] == "dam" and 2501 <= r["step"] <= 5000),
                ("dam_all", lambda r: r["case"] == "dam"),
            )
            for wname, pred in windows:
                m = mean_rows(sub, pred)
                if m is None:
                    continue
                agg_rows.append({
                    "thetaMinusDN": tm,
                    "gainMinus": gm,
                    "window": wname,
                    "frames": int(m["frames"]),
                    **{k: m[k] for k in (
                        "gatePlusFraction", "gateMinusFraction", "meanPlus", "meanMinus",
                        "meanSigned", "rmsPlus", "rmsMinus", "rmsSigned",
                        "rmsSignedCentered", "meanCancellationFraction",
                        "tractionToCompressionMeanRatio",
                    ) if k in m},
                })
    write_csv(a.out / "signed_traction_scan_windows_0493x7d.csv", agg_rows)

    # Analytic balance gain g* = <S+> / |<S-_base>| is independent of the
    # sampled gain grid. Recover base from any nonzero gain candidate.
    print("=== balance-gain discriminator ===")
    print("g* makes mean signed source ~= 0 in the selected window.")
    print("Large g*_dam / g*_pois means room to balance Poiseuille without cancelling dam compression.")
    print()
    print(" theta-   g*_pois_onset  g*_pois_late   g*_dam_early   g*_dam_all   separation(damEarly/poisOnset)")
    print("-" * 103)

    balance_rows = []
    probe_gain = next((g for g in gain_vals if g > 0), 1.0)
    for tm in theta_vals:
        vals = {}
        for wname in ("pois_onset", "pois_late", "dam_early", "dam_all"):
            row = next((r for r in agg_rows if r["thetaMinusDN"] == tm and r["gainMinus"] == probe_gain and r["window"] == wname), None)
            if row is None:
                vals[wname] = math.nan
                continue
            p = float(row["meanPlus"])
            neg_base_abs = abs(float(row["meanMinus"])) / probe_gain
            vals[wname] = p / neg_base_abs if neg_base_abs > 0 else math.inf
        sep = vals["dam_early"] / vals["pois_onset"] if vals["pois_onset"] > 0 and math.isfinite(vals["dam_early"]) else math.nan
        balance_rows.append({"thetaMinusDN": tm, **{f"balanceGain_{k}": v for k,v in vals.items()}, "separationDamEarlyOverPoisOnset": sep})
        print(f" {tm:6.2f} {vals['pois_onset']:15.4f} {vals['pois_late']:14.4f} {vals['dam_early']:14.4f} {vals['dam_all']:12.4f} {sep:29.4f}")
    write_csv(a.out / "signed_traction_balance_gain_0493x7d.csv", balance_rows)

    print()
    print("=== sampled candidates: Poiseuille onset vs dam early ===")
    print("Lower |Pois meanSigned| is better for fullDomain bias; dam traction ratio <<1 preserves compression-dominated dam response.")
    print()
    print(" th-  g-   PoisMean   PoisCancel  PoisCtrRMS  DamMean   DamTraction/Compression  DamSignedRMS/PosRMS")
    print("-" * 108)

    candidate_rows = []
    for tm in theta_vals:
        for gm in gain_vals:
            po = next((r for r in agg_rows if r["thetaMinusDN"] == tm and r["gainMinus"] == gm and r["window"] == "pois_onset"), None)
            da = next((r for r in agg_rows if r["thetaMinusDN"] == tm and r["gainMinus"] == gm and r["window"] == "dam_early"), None)
            if po is None or da is None:
                continue
            dam_rms_ratio = float(da["rmsSigned"]) / float(da["rmsPlus"]) if float(da["rmsPlus"]) > 0 else math.nan
            row = {
                "thetaMinusDN": tm,
                "gainMinus": gm,
                "poisMeanSigned": float(po["meanSigned"]),
                "poisCancellation": float(po["meanCancellationFraction"]),
                "poisCenteredRms": float(po["rmsSignedCentered"]),
                "damMeanSigned": float(da["meanSigned"]),
                "damTractionCompressionRatio": float(da["tractionToCompressionMeanRatio"]),
                "damSignedRmsOverPositiveRms": dam_rms_ratio,
            }
            candidate_rows.append(row)
            print(
                f"{tm:4.1f} {gm:4.2f} "
                f"{row['poisMeanSigned']:10.5f} {row['poisCancellation']:11.4f} "
                f"{row['poisCenteredRms']:11.5f} {row['damMeanSigned']:9.5f} "
                f"{row['damTractionCompressionRatio']:23.4f} {dam_rms_ratio:22.4f}"
            )
    write_csv(a.out / "signed_traction_candidates_0493x7d.csv", candidate_rows)

    print()
    print(f"[signed-scan] output={a.out}")
    print("[signed-scan] PASS offline scan completed; no solver state modified")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
