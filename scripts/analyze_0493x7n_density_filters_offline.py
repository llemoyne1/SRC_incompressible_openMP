#!/usr/bin/env python3
"""0493x7n offline density-filter study.

Reconstructs the cell-fill field from existing TG particle dumps and compares
candidate spatial low-pass filters without modifying the solver.

Candidate filters:
  - raw
  - binomial 3x3, 1 / 2 / 4 passes
  - binomial 5x5, 1 pass
  - ideal spectral cutoffs q<=4 / 8 / 12 (reference only)

Outputs quantify:
  * residual density RMS and equivalent x7d source RMS = std(delta)/tau
  * exact mean conservation
  * retained total power
  * retained low-q power (q<=2,4,8)
  * retained high-q power (q>=16)
  * radial transfer P_filtered(q)/P_raw(q)
"""
from __future__ import annotations

import argparse
import csv
import importlib
import json
import math
import sys
from collections import defaultdict
from pathlib import Path

import numpy as np


LOW_CUTS = (2.0, 4.0, 8.0)
HIGH_Q = 16.0


def parse_args():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tau0-root", type=Path, required=True)
    ap.add_argument("--tau025-root", type=Path, required=True)
    ap.add_argument("--tau-active", type=float, default=0.25)
    ap.add_argument("--out", type=Path, required=True)
    ap.add_argument("--include-step0", action="store_true")
    return ap.parse_args()


def import_base():
    scripts_dir = Path(__file__).resolve().parent
    if str(scripts_dir) not in sys.path:
        sys.path.insert(0, str(scripts_dir))
    return importlib.import_module("analyze_0493w1_src_fluid_calibrator")


def load_meta(root: Path):
    p = root / "analysis" / "tg_calibration_0493x7n.json"
    if not p.exists():
        raise FileNotFoundError(f"missing TG metadata: {p}")
    return json.loads(p.read_text())


def validate_compatible(a, b):
    keys = ("Lx", "Ly", "Nx", "Ny", "gamma", "dt", "kBT", "particleMass")
    bad = []
    for k in keys:
        va, vb = a.get(k), b.get(k)
        if va is None or vb is None:
            bad.append((k, va, vb))
        elif isinstance(va, (int, float)) and isinstance(vb, (int, float)):
            if not math.isclose(float(va), float(vb), rel_tol=1e-12, abs_tol=1e-14):
                bad.append((k, va, vb))
        elif va != vb:
            bad.append((k, va, vb))
    if bad:
        detail = "\n".join(f"  {k}: {va!r} vs {vb!r}" for k, va, vb in bad)
        raise ValueError(f"incompatible calibration metadata:\n{detail}")


def reconstruct_delta(state, meta):
    nx = int(meta["Nx"])
    ny = int(meta["Ny"])
    Lx = float(meta["Lx"])
    Ly = float(meta["Ly"])
    gamma = float(meta["gamma"])
    mp = float(meta["particleMass"])

    fluid = state["role"] == 1
    x = np.mod(state["x"][fluid], Lx)
    y = np.mod(state["y"][fluid], Ly)
    mass = state["mass"][fluid]

    ix = np.floor(x * nx / Lx).astype(np.int64)
    iy = np.floor(y * ny / Ly).astype(np.int64)
    np.clip(ix, 0, nx - 1, out=ix)
    np.clip(iy, 0, ny - 1, out=iy)

    linear = iy * nx + ix
    cell_mass = np.bincount(
        linear, weights=mass, minlength=nx * ny
    ).reshape(ny, nx)
    fill = cell_mass / (gamma * mp)
    return fill - 1.0


def mode_geometry(nx, ny):
    mx = np.fft.fftfreq(nx) * nx
    my = np.fft.fftfreq(ny) * ny
    qx, qy = np.meshgrid(mx, my)
    q = np.sqrt(qx * qx + qy * qy)
    shell = np.floor(q + 0.5).astype(int)
    nonzero = q > 0
    return q, shell, nonzero


def periodic_separable(field, weights):
    """Periodic separable convolution; weights must be odd-length, normalized."""
    weights = np.asarray(weights, float)
    if len(weights) % 2 != 1:
        raise ValueError("odd filter length required")
    weights = weights / np.sum(weights)
    radius = len(weights) // 2

    tmp = np.zeros_like(field, dtype=float)
    for j, w in enumerate(weights):
        shift = j - radius
        tmp += w * np.roll(field, shift=shift, axis=1)

    out = np.zeros_like(field, dtype=float)
    for j, w in enumerate(weights):
        shift = j - radius
        out += w * np.roll(tmp, shift=shift, axis=0)
    return out


def binomial3(field, passes):
    out = np.asarray(field, float)
    for _ in range(passes):
        out = periodic_separable(out, [1, 2, 1])
    return out


def binomial5(field):
    return periodic_separable(field, [1, 4, 6, 4, 1])


def ideal_cut(field, q, cutoff):
    F = np.fft.fft2(field, norm="ortho")
    F = np.where(q <= cutoff, F, 0.0)
    return np.fft.ifft2(F, norm="ortho").real


FILTERS = (
    ("raw", lambda d, q: d),
    ("bin3_p1", lambda d, q: binomial3(d, 1)),
    ("bin3_p2", lambda d, q: binomial3(d, 2)),
    ("bin3_p4", lambda d, q: binomial3(d, 4)),
    ("bin5_p1", lambda d, q: binomial5(d)),
    ("ideal_q4", lambda d, q: ideal_cut(d, q, 4.0)),
    ("ideal_q8", lambda d, q: ideal_cut(d, q, 8.0)),
    ("ideal_q12", lambda d, q: ideal_cut(d, q, 12.0)),
)


def power(field):
    F = np.fft.fft2(field, norm="ortho")
    return np.abs(F) ** 2


def safe_ratio(num, den):
    return float(num / den) if den > 0 else math.nan


def characterize(filtered, raw, q, shell, nonzero, tau_for_source):
    pf = power(filtered)
    pr = power(raw)

    raw_total = float(np.sum(pr[nonzero]))
    filt_total = float(np.sum(pf[nonzero]))
    out = {
        "meanDelta": float(np.mean(filtered)),
        "stdDelta": float(np.std(filtered)),
        "sourceRms": (
            float(np.std(filtered)) / tau_for_source
            if tau_for_source is not None and tau_for_source > 0
            else math.nan
        ),
        "totalPowerRetention": safe_ratio(filt_total, raw_total),
    }

    qn = q[nonzero]
    pfn = pf[nonzero]
    if filt_total > 0:
        out["qCentroid"] = float(np.sum(qn * pfn) / filt_total)
    else:
        out["qCentroid"] = math.nan

    for cut in LOW_CUTS:
        mask = nonzero & (q <= cut)
        raw_band = float(np.sum(pr[mask]))
        filt_band = float(np.sum(pf[mask]))
        out[f"lowPowerRetention_q_le_{cut:g}"] = safe_ratio(filt_band, raw_band)

    hmask = nonzero & (q >= HIGH_Q)
    raw_high = float(np.sum(pr[hmask]))
    filt_high = float(np.sum(pf[hmask]))
    out[f"highPowerRetention_q_ge_{HIGH_Q:g}"] = safe_ratio(filt_high, raw_high)

    return out, pr, pf


def write_csv(path, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    if not rows:
        path.write_text("")
        return
    fields = []
    seen = set()
    for row in rows:
        for k in row:
            if k not in seen:
                fields.append(k)
                seen.add(k)
    with path.open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=fields)
        w.writeheader()
        w.writerows(rows)


def analyze_case(label, root, meta, base, q, shell, nonzero, tau_source, include_step0):
    frame_rows = []
    radial_acc = defaultdict(lambda: {"raw": [], "filtered": []})

    dumps = base.list_dumps(root / "tg")
    if not dumps:
        raise ValueError(f"no TG dumps found under {root / 'tg'}")

    for step, path in dumps:
        if step == 0 and not include_step0:
            continue

        state = base.read_state(path)
        raw = reconstruct_delta(state, meta)

        if float(np.std(raw)) == 0.0:
            continue

        for name, func in FILTERS:
            filtered = func(raw, q)
            stats, pr, pf = characterize(
                filtered, raw, q, shell, nonzero, tau_source
            )

            row = {
                "case": label,
                "filter": name,
                "step": int(step),
                "time": float(step) * float(meta["dt"]),
                **stats,
            }
            frame_rows.append(row)

            max_shell = int(np.max(shell))
            for s in range(1, max_shell + 1):
                mask = nonzero & (shell == s)
                count = int(np.count_nonzero(mask))
                if count == 0:
                    continue
                radial_acc[(label, name, s)]["raw"].append(
                    float(np.mean(pr[mask]))
                )
                radial_acc[(label, name, s)]["filtered"].append(
                    float(np.mean(pf[mask]))
                )

    radial_rows = []
    for (case, name, s), vals in sorted(radial_acc.items()):
        raw_mean = float(np.mean(vals["raw"]))
        filt_mean = float(np.mean(vals["filtered"]))
        radial_rows.append({
            "case": case,
            "filter": name,
            "qShell": s,
            "frames": len(vals["raw"]),
            "rawMeanPower": raw_mean,
            "filteredMeanPower": filt_mean,
            "transferPower": safe_ratio(filt_mean, raw_mean),
            "transferAmplitudeProxy": (
                math.sqrt(filt_mean / raw_mean) if raw_mean > 0 else math.nan
            ),
        })
    return frame_rows, radial_rows


def aggregate_frames(frame_rows):
    groups = defaultdict(list)
    for r in frame_rows:
        groups[(r["case"], r["filter"])].append(r)

    fields = [
        "stdDelta",
        "sourceRms",
        "qCentroid",
        "totalPowerRetention",
        *[f"lowPowerRetention_q_le_{c:g}" for c in LOW_CUTS],
        f"highPowerRetention_q_ge_{HIGH_Q:g}",
        "meanDelta",
    ]

    out = []
    for (case, filt), rows in sorted(groups.items()):
        agg = {"case": case, "filter": filt, "frames": len(rows)}
        for key in fields:
            vals = np.array([float(r[key]) for r in rows], float)
            vals = vals[np.isfinite(vals)]
            agg[f"mean_{key}"] = (
                float(np.mean(vals)) if len(vals) else math.nan
            )
            agg[f"std_{key}"] = (
                float(np.std(vals, ddof=1)) if len(vals) > 1 else 0.0
            )
        out.append(agg)
    return out


def add_raw_relative(summary_rows):
    by_case = defaultdict(dict)
    for r in summary_rows:
        by_case[r["case"]][r["filter"]] = r

    for case, rows in by_case.items():
        raw = rows.get("raw")
        if raw is None:
            continue
        raw_std = float(raw["mean_stdDelta"])
        for r in rows.values():
            r["stdRatioToRaw"] = safe_ratio(float(r["mean_stdDelta"]), raw_std)
    return summary_rows


def print_case_table(case, rows, tau_active):
    rows = [r for r in rows if r["case"] == case]
    if not rows:
        return

    print()
    print(f"--- case={case} ---")
    print(
        f"{'filter':12s} {'RMS':>9s} {'RMS/raw':>9s} {'srcRMS':>9s} "
        f"{'Ret<=4':>9s} {'Ret<=8':>9s} {'Ret>=16':>9s} {'qCent':>8s}"
    )
    print("-" * 86)
    for r in rows:
        print(
            f"{r['filter']:12s} "
            f"{r['mean_stdDelta']:9.5f} "
            f"{r.get('stdRatioToRaw', math.nan):9.4f} "
            f"{r['mean_sourceRms']:9.5f} "
            f"{r['mean_lowPowerRetention_q_le_4']:9.4f} "
            f"{r['mean_lowPowerRetention_q_le_8']:9.4f} "
            f"{r['mean_highPowerRetention_q_ge_16']:9.4f} "
            f"{r['mean_qCentroid']:8.3f}"
        )


def main():
    a = parse_args()
    if a.tau_active <= 0:
        raise ValueError("--tau-active must be > 0")

    m0 = load_meta(a.tau0_root)
    m1 = load_meta(a.tau025_root)
    validate_compatible(m0, m1)

    nx, ny = int(m0["Nx"]), int(m0["Ny"])
    q, shell, nonzero = mode_geometry(nx, ny)
    base = import_base()

    # Use the same tau denominator for both cases only as an offline "what if"
    # source-strength comparison. tau0 is not actually applying x7d.
    f0, r0 = analyze_case(
        "tau0", a.tau0_root, m0, base, q, shell, nonzero,
        tau_source=a.tau_active,
        include_step0=a.include_step0,
    )
    f1, r1 = analyze_case(
        "tau025", a.tau025_root, m1, base, q, shell, nonzero,
        tau_source=a.tau_active,
        include_step0=a.include_step0,
    )

    frames = f0 + f1
    radial = r0 + r1
    summary = add_raw_relative(aggregate_frames(frames))

    a.out.mkdir(parents=True, exist_ok=True)
    write_csv(a.out / "density_filter_frames_0493x7n.csv", frames)
    write_csv(a.out / "density_filter_summary_0493x7n.csv", summary)
    write_csv(a.out / "density_filter_radial_transfer_0493x7n.csv", radial)

    manifest = {
        "schema": "0493x7n-density-filter-study-v1",
        "tau0Root": str(a.tau0_root),
        "tau025Root": str(a.tau025_root),
        "tauActiveForSourceProxy": a.tau_active,
        "includeStep0": bool(a.include_step0),
        "field": "deposited cell mass/(gamma*particleMass)-1",
        "boundaryForOfflineFilters": "periodic",
        "filters": [
            "raw",
            "bin3_p1",
            "bin3_p2",
            "bin3_p4",
            "bin5_p1",
            "ideal_q4",
            "ideal_q8",
            "ideal_q12",
        ],
        "binomial3Kernel1D": [0.25, 0.5, 0.25],
        "binomial5Kernel1D": [1/16, 4/16, 6/16, 4/16, 1/16],
        "lowQRetentionCuts": list(LOW_CUTS),
        "highQThreshold": HIGH_Q,
        "metadata": {
            k: m0[k]
            for k in ("Lx", "Ly", "Nx", "Ny", "gamma", "dt", "kBT", "particleMass")
        },
    }
    (a.out / "density_filter_manifest_0493x7n.json").write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n"
    )

    print("===== 0493x7n OFFLINE DENSITY FILTER STUDY =====")
    print(
        f"grid={nx}x{ny} L={m0['Lx']}x{m0['Ly']} "
        f"gamma={m0['gamma']} tauProxy={a.tau_active}"
    )
    print(
        "Ret<=q = retained raw low-q power; Ret>=16 = retained raw high-q power."
    )
    print(
        "Ideal q-cuts are references only; binomial filters are local-stencil candidates."
    )

    print_case_table("tau0", summary, a.tau_active)
    print_case_table("tau025", summary, a.tau_active)

    # Compact ranking for the active case: preserve q<=4, then minimize high-q,
    # but do not silently choose a production filter.
    active = [r for r in summary if r["case"] == "tau025" and r["filter"] != "raw"]
    ranked = sorted(
        active,
        key=lambda r: (
            -float(r["mean_lowPowerRetention_q_le_4"]),
            float(r["mean_highPowerRetention_q_ge_16"]),
        ),
    )
    print()
    print("tau025 candidate ordering by q<=4 preservation, then high-q suppression:")
    for r in ranked:
        print(
            f"  {r['filter']:12s} "
            f"Ret<=4={r['mean_lowPowerRetention_q_le_4']:.5f} "
            f"Ret>=16={r['mean_highPowerRetention_q_ge_16']:.5f} "
            f"RMS/raw={r['stdRatioToRaw']:.5f} "
            f"sourceRMS={r['mean_sourceRms']:.5f}"
        )

    print()
    print(f"[0493x7n-filter] out={a.out}")
    print("[0493x7n-filter] PASS offline filter study completed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
