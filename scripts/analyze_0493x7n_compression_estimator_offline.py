#!/usr/bin/env python3
"""0493x7n offline compression-estimator sizing diagnostic.

Uses existing TG and dam-break particle dumps. It reconstructs:
  * liquid / fluid cell fill deviation delta = fill - 1
  * cell-mean velocity
  * Eulerian compression c = -div(u)
  * density/compression sign and correlation metrics
  * temporal autocorrelation of delta and c
  * EMA compression memories for candidate physical times Tc
  * TG-derived compression thresholds and their activation in dam-break

This is an offline diagnostic only. It does not modify Q6 or any run.
"""
from __future__ import annotations

import argparse
import csv
import importlib
import json
import math
import re
import sys
from collections import defaultdict
from pathlib import Path

import numpy as np


MEMORY_TIMES = (0.0, 0.05, 0.10, 0.25, 0.50)
AUTOCORR_LAGS = (1, 2, 3, 5, 8)
TG_THRESHOLD_QUANTILES = (0.95, 0.99, 0.999)


def parse_args():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tg-tau0-root", type=Path, required=True)
    ap.add_argument("--tg-tau025-root", type=Path, required=True)
    ap.add_argument("--dam-tau0-root", type=Path, required=True)
    ap.add_argument("--dam-tau025-root", type=Path, required=True)
    ap.add_argument("--out", type=Path, required=True)

    ap.add_argument("--dam-gamma", type=float, default=10.0)
    ap.add_argument("--dam-liquid-type", type=int, default=1)
    ap.add_argument("--dam-liquid-mass", type=float, default=1000.0)
    ap.add_argument(
        "--bulk-fill-min",
        type=float,
        default=0.50,
        help="minimum liquid fill for dam-break bulk mask before one-cell erosion",
    )
    ap.add_argument(
        "--stride",
        type=int,
        default=1,
        help="analyze every Nth dump after step 0",
    )
    return ap.parse_args()


def import_base():
    scripts_dir = Path(__file__).resolve().parent
    if str(scripts_dir) not in sys.path:
        sys.path.insert(0, str(scripts_dir))
    return importlib.import_module("analyze_0493w1_src_fluid_calibrator")


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


def find_params_used(root: Path):
    candidates = [
        root / "output" / "params_used.kv",
        root / "params" / "dambreak.kv",
    ]
    for p in candidates:
        if p.exists():
            return p
    found = list(root.glob("**/params_used.kv"))
    if len(found) == 1:
        return found[0]
    raise FileNotFoundError(f"cannot uniquely locate params_used.kv below {root}")


def load_tg_meta(root: Path):
    p = root / "analysis" / "tg_calibration_0493x7n.json"
    if not p.exists():
        raise FileNotFoundError(f"missing TG metadata: {p}")
    m = json.loads(p.read_text())
    return {
        "kind": "tg",
        "Lx": float(m["Lx"]),
        "Ly": float(m["Ly"]),
        "Nx": int(m["Nx"]),
        "Ny": int(m["Ny"]),
        "dt": float(m["dt"]),
        "gamma": float(m["gamma"]),
        "particleMass": float(m["particleMass"]),
        "liquidType": None,
        "periodic": True,
    }


def load_dam_meta(root: Path, args):
    kv = read_kv(find_params_used(root))
    required = ("Lx", "Ly", "Nx", "Ny", "dt")
    missing = [k for k in required if k not in kv]
    if missing:
        raise ValueError(f"dam-break params missing {missing} below {root}")
    return {
        "kind": "dam",
        "Lx": float(kv["Lx"]),
        "Ly": float(kv["Ly"]),
        "Nx": int(float(kv["Nx"])),
        "Ny": int(float(kv["Ny"])),
        "dt": float(kv["dt"]),
        "gamma": float(args.dam_gamma),
        "particleMass": float(args.dam_liquid_mass),
        "liquidType": int(args.dam_liquid_type),
        "periodic": False,
    }


def resolve_dump_dir(root: Path, kind: str):
    candidates = []
    if kind == "tg":
        candidates += [root / "tg", root / "output"]
    else:
        candidates += [root / "output", root]
    for p in candidates:
        if p.exists():
            return p
    raise FileNotFoundError(f"no dump directory below {root}")


def state_key(state, names, required=True):
    for n in names:
        if n in state:
            return n
    if required:
        raise KeyError(
            f"none of keys {names!r} found; available keys={sorted(state.keys())}"
        )
    return None


def select_particles(state, meta):
    role_key = state_key(state, ("role",), required=False)
    if role_key is None:
        mask = np.ones(len(state["x"]), dtype=bool)
    else:
        mask = np.asarray(state[role_key]) == 1

    if meta["kind"] == "dam":
        type_key = state_key(
            state,
            ("type", "ptype", "particleType", "particle_type"),
            required=True,
        )
        mask &= np.asarray(state[type_key]) == int(meta["liquidType"])
    return mask


def reconstruct_fields(state, meta):
    nx, ny = meta["Nx"], meta["Ny"]
    lx, ly = meta["Lx"], meta["Ly"]
    gamma, mp = meta["gamma"], meta["particleMass"]

    xk = state_key(state, ("x",))
    yk = state_key(state, ("y",))
    vxk = state_key(state, ("vx", "ux"))
    vyk = state_key(state, ("vy", "uy"))
    mk = state_key(state, ("mass", "m"))

    sel = select_particles(state, meta)

    x = np.asarray(state[xk], float)[sel]
    y = np.asarray(state[yk], float)[sel]
    vx = np.asarray(state[vxk], float)[sel]
    vy = np.asarray(state[vyk], float)[sel]
    mass = np.asarray(state[mk], float)[sel]

    # TG is periodic. Dam-break coordinates should already be in-box; clipping
    # makes the histogram robust to round-off at a wall.
    if meta["periodic"]:
        x = np.mod(x, lx)
        y = np.mod(y, ly)
    else:
        x = np.clip(x, 0.0, np.nextafter(lx, 0.0))
        y = np.clip(y, 0.0, np.nextafter(ly, 0.0))

    ix = np.floor(x * nx / lx).astype(np.int64)
    iy = np.floor(y * ny / ly).astype(np.int64)
    np.clip(ix, 0, nx - 1, out=ix)
    np.clip(iy, 0, ny - 1, out=iy)
    ind = iy * nx + ix

    shape = (ny, nx)
    cell_mass = np.bincount(
        ind, weights=mass, minlength=nx * ny
    ).reshape(shape)
    px = np.bincount(
        ind, weights=mass * vx, minlength=nx * ny
    ).reshape(shape)
    py = np.bincount(
        ind, weights=mass * vy, minlength=nx * ny
    ).reshape(shape)

    u = np.zeros(shape, float)
    v = np.zeros(shape, float)
    occupied = cell_mass > 0
    u[occupied] = px[occupied] / cell_mass[occupied]
    v[occupied] = py[occupied] / cell_mass[occupied]

    fill = cell_mass / (gamma * mp)
    delta = fill - 1.0
    return delta, fill, u, v, occupied


def erode_bulk(mask, periodic):
    if periodic:
        return (
            mask
            & np.roll(mask, 1, axis=0)
            & np.roll(mask, -1, axis=0)
            & np.roll(mask, 1, axis=1)
            & np.roll(mask, -1, axis=1)
        )

    out = np.zeros_like(mask, bool)
    out[1:-1, 1:-1] = (
        mask[1:-1, 1:-1]
        & mask[:-2, 1:-1]
        & mask[2:, 1:-1]
        & mask[1:-1, :-2]
        & mask[1:-1, 2:]
    )
    return out


def divergence(u, v, meta):
    dx = meta["Lx"] / meta["Nx"]
    dy = meta["Ly"] / meta["Ny"]

    if meta["periodic"]:
        du_dx = (np.roll(u, -1, axis=1) - np.roll(u, 1, axis=1)) / (2.0 * dx)
        dv_dy = (np.roll(v, -1, axis=0) - np.roll(v, 1, axis=0)) / (2.0 * dy)
        return du_dx + dv_dy

    out = np.full_like(u, np.nan, dtype=float)
    out[1:-1, 1:-1] = (
        (u[1:-1, 2:] - u[1:-1, :-2]) / (2.0 * dx)
        + (v[2:, 1:-1] - v[:-2, 1:-1]) / (2.0 * dy)
    )
    return out


def pearson(a, b):
    a = np.asarray(a, float)
    b = np.asarray(b, float)
    ok = np.isfinite(a) & np.isfinite(b)
    a, b = a[ok], b[ok]
    if len(a) < 3:
        return math.nan
    a = a - np.mean(a)
    b = b - np.mean(b)
    sa = float(np.sqrt(np.mean(a * a)))
    sb = float(np.sqrt(np.mean(b * b)))
    if sa == 0 or sb == 0:
        return math.nan
    return float(np.mean(a * b) / (sa * sb))


def cosine_corr(a, b):
    a = np.asarray(a, float)
    b = np.asarray(b, float)
    ok = np.isfinite(a) & np.isfinite(b)
    a, b = a[ok], b[ok]
    if len(a) == 0:
        return math.nan
    na = float(np.sqrt(np.mean(a * a)))
    nb = float(np.sqrt(np.mean(b * b)))
    if na == 0 or nb == 0:
        return math.nan
    return float(np.mean(a * b) / (na * nb))


def sign_agreement(delta, comp, top_fraction=None):
    delta = np.asarray(delta, float)
    comp = np.asarray(comp, float)
    ok = np.isfinite(delta) & np.isfinite(comp)
    delta, comp = delta[ok], comp[ok]
    if len(delta) == 0:
        return math.nan

    if top_fraction is not None:
        cut = np.quantile(np.abs(delta), 1.0 - top_fraction)
        keep = np.abs(delta) >= cut
        delta, comp = delta[keep], comp[keep]
        if len(delta) == 0:
            return math.nan

    # Exact zero contributes neither coherent nor incoherent information.
    nz = (delta != 0.0) & (comp != 0.0)
    if not np.any(nz):
        return math.nan
    return float(np.mean((delta[nz] * comp[nz]) > 0.0))


def rms(a):
    a = np.asarray(a, float)
    a = a[np.isfinite(a)]
    return float(np.sqrt(np.mean(a * a))) if len(a) else math.nan


def percentile(a, q):
    a = np.asarray(a, float)
    a = a[np.isfinite(a)]
    return float(np.quantile(a, q)) if len(a) else math.nan


def list_case_frames(root, meta, base, stride):
    dump_dir = resolve_dump_dir(root, meta["kind"])

    # First keep compatibility with the canonical 0493w1 calibrator naming.
    dumps = base.list_dumps(dump_dir)

    # run_ok_dambreak.sh writes states as:
    #   state_step_00000010.smpcd
    # which the 0493w1 list_dumps() helper does not recognize.
    # Fall back to this explicit public-runner format without changing the
    # canonical state reader.
    if not dumps:
        rx = re.compile(r"^state_step_(\d+)\.smpcd$")
        fallback = []
        for path in sorted(dump_dir.glob("state_step_*.smpcd")):
            m = rx.match(path.name)
            if m:
                fallback.append((int(m.group(1)), path))
        dumps = fallback

    dumps = sorted(
        [(int(s), Path(p)) for s, p in dumps if int(s) > 0],
        key=lambda item: item[0],
    )

    if stride > 1:
        dumps = dumps[::stride]

    if not dumps:
        sample = sorted(p.name for p in dump_dir.glob("*.smpcd"))[:10]
        raise ValueError(
            f"no nonzero dumps recognized in {dump_dir}; "
            f"sample smpcd files={sample}"
        )

    return dumps


def analyze_case(label, root, meta, base, args):
    dumps = list_case_frames(root, meta, base, args.stride)

    raw_frames = []
    for step, path in dumps:
        state = base.read_state(path)
        delta, fill, u, v, occupied = reconstruct_fields(state, meta)
        div = divergence(u, v, meta)
        comp = -div  # positive = compression

        if meta["kind"] == "dam":
            base_bulk = (fill >= args.bulk_fill_min) & occupied
        else:
            base_bulk = occupied
        bulk = erode_bulk(base_bulk, meta["periodic"])
        bulk &= np.isfinite(comp)

        raw_frames.append({
            "step": int(step),
            "time": float(step) * meta["dt"],
            "delta": delta,
            "comp": comp,
            "bulk": bulk,
        })

    # Determine actual dump spacing from data, not assumed cadence.
    times = np.array([f["time"] for f in raw_frames], float)
    dt_dump = float(np.median(np.diff(times))) if len(times) > 1 else math.nan

    frame_rows = []
    memory_samples = {T: {"comp": [], "delta": []} for T in MEMORY_TIMES}
    memory_state = {T: np.zeros((meta["Ny"], meta["Nx"]), float) for T in MEMORY_TIMES if T > 0}
    memory_valid = {T: np.zeros((meta["Ny"], meta["Nx"]), bool) for T in MEMORY_TIMES if T > 0}

    prev_time = None
    prev_delta = None
    prev_comp = None
    prev_bulk = None

    # Store fields for autocorrelation.
    series_delta = []
    series_comp = []
    series_bulk = []

    for fr in raw_frames:
        delta = fr["delta"]
        comp = fr["comp"]
        bulk = fr["bulk"]
        d = delta[bulk]
        c = comp[bulk]

        row = {
            "case": label,
            "kind": meta["kind"],
            "step": fr["step"],
            "time": fr["time"],
            "bulkCells": int(np.count_nonzero(bulk)),
            "deltaRms": rms(d),
            "compressionRms": rms(c),
            "compressionAbsQ50": percentile(np.abs(c), 0.50),
            "compressionAbsQ90": percentile(np.abs(c), 0.90),
            "compressionAbsQ95": percentile(np.abs(c), 0.95),
            "compressionAbsQ99": percentile(np.abs(c), 0.99),
            "corrDeltaCompression": pearson(d, c),
            "cosDeltaCompression": cosine_corr(d, c),
            "signAgreeAll": sign_agreement(d, c),
            "signAgreeTop25Delta": sign_agreement(d, c, 0.25),
            "signAgreeTop10Delta": sign_agreement(d, c, 0.10),
        }

        if prev_time is not None:
            common = bulk & prev_bulk
            dtf = fr["time"] - prev_time
            if dtf > 0 and np.any(common):
                d_rate = (delta[common] - prev_delta[common]) / dtf
                # Continuity near rho~rho0 suggests D(delta)/Dt ~ compression.
                row["corrDensityRateCompressionPrev"] = pearson(
                    d_rate, prev_comp[common]
                )
                row["cosDensityRateCompressionPrev"] = cosine_corr(
                    d_rate, prev_comp[common]
                )
                row["densityLag1Corr"] = pearson(
                    delta[common], prev_delta[common]
                )
                row["compressionLag1Corr"] = pearson(
                    comp[common], prev_comp[common]
                )
            else:
                row["corrDensityRateCompressionPrev"] = math.nan
                row["cosDensityRateCompressionPrev"] = math.nan
                row["densityLag1Corr"] = math.nan
                row["compressionLag1Corr"] = math.nan
        else:
            row["corrDensityRateCompressionPrev"] = math.nan
            row["cosDensityRateCompressionPrev"] = math.nan
            row["densityLag1Corr"] = math.nan
            row["compressionLag1Corr"] = math.nan

        # Candidate EMA memories.
        for T in MEMORY_TIMES:
            if T == 0.0:
                mem = comp
            else:
                if prev_time is None:
                    alpha = 1.0
                else:
                    dtf = fr["time"] - prev_time
                    alpha = 1.0 - math.exp(-dtf / T)

                # Reset memory outside current bulk. This mirrors a local
                # carrier-aware estimator more closely than retaining stale
                # interface history.
                st = memory_state[T]
                st[~bulk] = 0.0
                st[bulk] = (1.0 - alpha) * st[bulk] + alpha * comp[bulk]
                memory_valid[T][~bulk] = False
                memory_valid[T][bulk] = True
                mem = st

            md = delta[bulk]
            mm = mem[bulk]
            tag = f"T{T:g}"
            row[f"memoryRms_{tag}"] = rms(mm)
            row[f"memoryCorr_{tag}"] = pearson(md, mm)
            row[f"memoryCos_{tag}"] = cosine_corr(md, mm)
            row[f"memorySignAgree_{tag}"] = sign_agreement(md, mm)
            row[f"memorySignAgreeTop25_{tag}"] = sign_agreement(md, mm, 0.25)

            memory_samples[T]["comp"].append(np.asarray(mm, float).copy())
            memory_samples[T]["delta"].append(np.asarray(md, float).copy())

        frame_rows.append(row)
        series_delta.append(delta.copy())
        series_comp.append(comp.copy())
        series_bulk.append(bulk.copy())

        prev_time = fr["time"]
        prev_delta = delta
        prev_comp = comp
        prev_bulk = bulk

    # Autocorrelation at several dump lags.
    autocorr_rows = []
    for lag in AUTOCORR_LAGS:
        if lag >= len(raw_frames):
            continue
        dcorr = []
        ccorr = []
        for i in range(lag, len(raw_frames)):
            common = series_bulk[i] & series_bulk[i - lag]
            if np.count_nonzero(common) < 10:
                continue
            dcorr.append(pearson(
                series_delta[i][common], series_delta[i - lag][common]
            ))
            ccorr.append(pearson(
                series_comp[i][common], series_comp[i - lag][common]
            ))
        dcorr = np.asarray(dcorr, float)
        ccorr = np.asarray(ccorr, float)
        autocorr_rows.append({
            "case": label,
            "lagDumps": lag,
            "lagTime": lag * dt_dump if math.isfinite(dt_dump) else math.nan,
            "densityCorrMean": float(np.nanmean(dcorr)) if len(dcorr) else math.nan,
            "compressionCorrMean": float(np.nanmean(ccorr)) if len(ccorr) else math.nan,
            "pairs": int(max(len(dcorr), len(ccorr))),
        })

    # Flatten memory samples for threshold sizing.
    packed = {}
    for T in MEMORY_TIMES:
        packed[T] = {
            "comp": np.concatenate(memory_samples[T]["comp"]) if memory_samples[T]["comp"] else np.empty(0),
            "delta": np.concatenate(memory_samples[T]["delta"]) if memory_samples[T]["delta"] else np.empty(0),
        }

    return frame_rows, autocorr_rows, packed, dt_dump


def aggregate_frames(rows):
    groups = defaultdict(list)
    for r in rows:
        groups[r["case"]].append(r)

    out = []
    keys = [
        "bulkCells",
        "deltaRms",
        "compressionRms",
        "compressionAbsQ95",
        "compressionAbsQ99",
        "corrDeltaCompression",
        "cosDeltaCompression",
        "signAgreeAll",
        "signAgreeTop25Delta",
        "signAgreeTop10Delta",
        "corrDensityRateCompressionPrev",
        "densityLag1Corr",
        "compressionLag1Corr",
    ]
    for T in MEMORY_TIMES:
        tag = f"T{T:g}"
        keys += [
            f"memoryRms_{tag}",
            f"memoryCorr_{tag}",
            f"memoryCos_{tag}",
            f"memorySignAgree_{tag}",
            f"memorySignAgreeTop25_{tag}",
        ]

    for case, rs in sorted(groups.items()):
        row = {"case": case, "frames": len(rs)}
        for k in keys:
            vals = np.array([float(r.get(k, math.nan)) for r in rs], float)
            vals = vals[np.isfinite(vals)]
            row[f"mean_{k}"] = float(np.mean(vals)) if len(vals) else math.nan
            row[f"std_{k}"] = float(np.std(vals, ddof=1)) if len(vals) > 1 else 0.0
        out.append(row)
    return out


def build_threshold_rows(samples_by_case):
    # TG pooled baseline at fixed false-positive quantiles.
    rows = []
    for T in MEMORY_TIMES:
        tg_abs = []
        for case in ("tg_tau0", "tg_tau025"):
            if case in samples_by_case:
                tg_abs.append(np.abs(samples_by_case[case][T]["comp"]))
        if not tg_abs:
            continue
        tg_abs = np.concatenate(tg_abs)
        tg_abs = tg_abs[np.isfinite(tg_abs)]

        for q in TG_THRESHOLD_QUANTILES:
            theta = float(np.quantile(tg_abs, q))
            for case, byT in sorted(samples_by_case.items()):
                c = np.asarray(byT[T]["comp"], float)
                d = np.asarray(byT[T]["delta"], float)
                ok = np.isfinite(c) & np.isfinite(d)
                c, d = c[ok], d[ok]
                if len(c) == 0:
                    continue
                active = np.abs(c) > theta
                coherent = active & ((d * c) > 0.0)
                delta_abs = np.abs(d)
                total_delta = float(np.sum(delta_abs))
                rows.append({
                    "memoryTime": T,
                    "tgBaselineQuantile": q,
                    "thresholdAbsCompression": theta,
                    "case": case,
                    "cells": len(c),
                    "activationFraction": float(np.mean(active)),
                    "coherentAmongActive": (
                        float(np.mean((d[active] * c[active]) > 0.0))
                        if np.any(active) else math.nan
                    ),
                    "coherentActivationFraction": float(np.mean(coherent)),
                    "deltaAbsCapturedCoherentFraction": (
                        float(np.sum(delta_abs[coherent]) / total_delta)
                        if total_delta > 0 else math.nan
                    ),
                })
    return rows


def write_csv(path, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    if not rows:
        path.write_text("")
        return
    fields, seen = [], set()
    for r in rows:
        for k in r:
            if k not in seen:
                fields.append(k)
                seen.add(k)
    with path.open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=fields)
        w.writeheader()
        w.writerows(rows)


def print_summary(summary, autocorr, thresholds, dt_dump_by_case):
    print("===== 0493x7n COMPRESSION ESTIMATOR SIZING =====")
    print("compression = -div(cell-mean velocity); positive means compression")
    print("dam bulk = liquid fill >= threshold, then one-cell erosion")
    print()

    print(
        f"{'case':12s} {'dRMS':>9s} {'cRMS':>9s} {'|c|q99':>9s} "
        f"{'corr(d,c)':>10s} {'agree25':>9s} {'rhoLag1':>9s} {'cLag1':>9s}"
    )
    print("-" * 91)
    for r in summary:
        print(
            f"{r['case']:12s} "
            f"{r['mean_deltaRms']:9.4g} "
            f"{r['mean_compressionRms']:9.4g} "
            f"{r['mean_compressionAbsQ99']:9.4g} "
            f"{r['mean_corrDeltaCompression']:10.4f} "
            f"{r['mean_signAgreeTop25Delta']:9.4f} "
            f"{r['mean_densityLag1Corr']:9.4f} "
            f"{r['mean_compressionLag1Corr']:9.4f}"
        )

    print()
    print("EMA memory coherence with density (top-25% |delta| sign agreement):")
    print(f"{'case':12s}" + "".join(f" {'T='+format(T,'g'):>11s}" for T in MEMORY_TIMES))
    print("-" * (12 + 12 * len(MEMORY_TIMES)))
    for r in summary:
        vals = []
        for T in MEMORY_TIMES:
            vals.append(r[f"mean_memorySignAgreeTop25_T{T:g}"])
        print(f"{r['case']:12s}" + "".join(f" {v:11.4f}" for v in vals))

    print()
    print("Dump cadence:")
    for case, dt in dt_dump_by_case.items():
        print(f"  {case:12s} dt_dump={dt:.6g}")

    print()
    print("TG-q99 threshold transfer to dam-break:")
    chosen = [
        r for r in thresholds
        if math.isclose(float(r["tgBaselineQuantile"]), 0.99)
        and r["case"] in ("dam_tau0", "dam_tau025")
    ]
    print(
        f"{'T':>6s} {'case':12s} {'theta99':>10s} "
        f"{'active':>9s} {'coh|act':>9s} {'|d|capture':>11s}"
    )
    print("-" * 63)
    for r in chosen:
        print(
            f"{r['memoryTime']:6.2f} {r['case']:12s} "
            f"{r['thresholdAbsCompression']:10.4g} "
            f"{r['activationFraction']:9.4f} "
            f"{r['coherentAmongActive']:9.4f} "
            f"{r['deltaAbsCapturedCoherentFraction']:11.4f}"
        )

    print()
    print("Temporal autocorrelation:")
    for r in autocorr:
        if r["lagDumps"] in (1, 2, 3, 5):
            print(
                f"  {r['case']:12s} lag={r['lagDumps']:2d} "
                f"dt={r['lagTime']:.4g} "
                f"rhoCorr={r['densityCorrMean']:.4f} "
                f"compCorr={r['compressionCorrMean']:.4f}"
            )


def main():
    a = parse_args()
    if a.stride < 1:
        raise ValueError("--stride must be >=1")
    if not (0.0 < a.bulk_fill_min <= 1.5):
        raise ValueError("--bulk-fill-min must be in (0,1.5]")

    base = import_base()

    cases = [
        ("tg_tau0", a.tg_tau0_root, load_tg_meta(a.tg_tau0_root)),
        ("tg_tau025", a.tg_tau025_root, load_tg_meta(a.tg_tau025_root)),
        ("dam_tau0", a.dam_tau0_root, load_dam_meta(a.dam_tau0_root, a)),
        ("dam_tau025", a.dam_tau025_root, load_dam_meta(a.dam_tau025_root, a)),
    ]

    all_frames = []
    all_autocorr = []
    samples = {}
    dt_dump_by_case = {}

    for label, root, meta in cases:
        print(f"[0493x7n-compression] analyzing {label} root={root}", file=sys.stderr)
        frames, autocorr, packed, dt_dump = analyze_case(
            label, root, meta, base, a
        )
        all_frames += frames
        all_autocorr += autocorr
        samples[label] = packed
        dt_dump_by_case[label] = dt_dump

    summary = aggregate_frames(all_frames)
    thresholds = build_threshold_rows(samples)

    a.out.mkdir(parents=True, exist_ok=True)
    write_csv(a.out / "compression_estimator_frames_0493x7n.csv", all_frames)
    write_csv(a.out / "compression_estimator_summary_0493x7n.csv", summary)
    write_csv(a.out / "compression_estimator_autocorr_0493x7n.csv", all_autocorr)
    write_csv(a.out / "compression_estimator_thresholds_0493x7n.csv", thresholds)

    manifest = {
        "schema": "0493x7n-compression-estimator-sizing-v1",
        "memoryTimes": list(MEMORY_TIMES),
        "autocorrLags": list(AUTOCORR_LAGS),
        "tgThresholdQuantiles": list(TG_THRESHOLD_QUANTILES),
        "damBulkFillMin": a.bulk_fill_min,
        "damBulkErosionCells": 1,
        "stride": a.stride,
        "compressionDefinition": "-div(cell-mean velocity reconstructed from particle dumps)",
        "importantLimitation": (
            "dumped velocity is not guaranteed to be the exact pre-Q6 predictor "
            "velocity/divBefore used internally by the projection"
        ),
        "roots": {label: str(root) for label, root, _ in cases},
    }
    (a.out / "compression_estimator_manifest_0493x7n.json").write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n"
    )

    print_summary(summary, all_autocorr, thresholds, dt_dump_by_case)
    print()
    print(f"[0493x7n-compression] out={a.out}")
    print("[0493x7n-compression] PASS offline estimator sizing completed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
