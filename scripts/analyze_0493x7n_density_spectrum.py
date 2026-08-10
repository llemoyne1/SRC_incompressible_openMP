#!/usr/bin/env python3
"""0493x7n — density spectrum diagnostic for TG tau=0 vs tau>0.

Offline only: reconstructs cell mass fill from particle dumps, computes 2-D FFT
power spectra, radial shell averages, cumulative low-q fractions, white-spectrum
reference fractions, and matched-case comparisons.

No simulation physics is modified.
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


CUTS = (1.0, 2.0, 4.0, 8.0, 16.0)


def parse_args():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tau0-root", type=Path, required=True)
    ap.add_argument("--tau025-root", type=Path, required=True)
    ap.add_argument("--out", type=Path, required=True)
    ap.add_argument("--tau-active", type=float, default=0.25)
    ap.add_argument(
        "--include-step0",
        action="store_true",
        help="include the common initial state in time-averaged spectra",
    )
    return ap.parse_args()


def load_meta(root: Path):
    p = root / "analysis" / "tg_calibration_0493x7n.json"
    if not p.exists():
        raise FileNotFoundError(f"missing x7n TG metadata: {p}")
    return json.loads(p.read_text())


def compatible(a, b):
    keys = ("Lx", "Ly", "Nx", "Ny", "gamma", "dt", "kBT", "particleMass")
    bad = []
    for k in keys:
        if k not in a or k not in b:
            bad.append((k, a.get(k), b.get(k), "missing"))
            continue
        va, vb = a[k], b[k]
        if isinstance(va, (int, float)) and isinstance(vb, (int, float)):
            if not math.isclose(float(va), float(vb), rel_tol=1e-12, abs_tol=1e-14):
                bad.append((k, va, vb, "different"))
        elif va != vb:
            bad.append((k, va, vb, "different"))
    if bad:
        lines = ["incompatible calibration metadata:"]
        lines += [f"  {k}: {va!r} vs {vb!r} ({why})" for k, va, vb, why in bad]
        raise ValueError("\n".join(lines))


def import_base():
    scripts_dir = Path(__file__).resolve().parent
    if str(scripts_dir) not in sys.path:
        sys.path.insert(0, str(scripts_dir))
    return importlib.import_module("analyze_0493w1_src_fluid_calibrator")


def mode_geometry(nx: int, ny: int):
    mx = np.fft.fftfreq(nx) * nx
    my = np.fft.fftfreq(ny) * ny
    qx, qy = np.meshgrid(mx, my)
    q = np.sqrt(qx * qx + qy * qy)
    shell = np.floor(q + 0.5).astype(int)
    nonzero = q > 0.0
    return q, shell, nonzero


def reconstruct_fill(state, meta):
    nx = int(meta["Nx"])
    ny = int(meta["Ny"])
    Lx = float(meta["Lx"])
    Ly = float(meta["Ly"])
    gamma = float(meta["gamma"])
    particle_mass = float(meta["particleMass"])

    fluid = state["role"] == 1
    x = np.mod(state["x"][fluid], Lx)
    y = np.mod(state["y"][fluid], Ly)
    mass = state["mass"][fluid]

    ix = np.floor(x * nx / Lx).astype(np.int64)
    iy = np.floor(y * ny / Ly).astype(np.int64)
    np.clip(ix, 0, nx - 1, out=ix)
    np.clip(iy, 0, ny - 1, out=iy)

    linear = iy * nx + ix
    cell_mass = np.bincount(linear, weights=mass, minlength=nx * ny).reshape(ny, nx)
    ref_cell_mass = gamma * particle_mass
    fill = cell_mass / ref_cell_mass
    return fill


def spectrum_from_fill(fill, q, shell, nonzero):
    delta = fill - 1.0
    # Orthonormal FFT: sum |delta|^2 == sum |F|^2.
    F = np.fft.fft2(delta, norm="ortho")
    power = np.abs(F) ** 2

    total_nonzero = float(np.sum(power[nonzero]))
    variance = float(np.mean(delta * delta))
    parseval_variance = float(np.sum(power) / delta.size)

    if total_nonzero <= 0.0:
        summary = {
            "zeroPowerFrame": True,
            "meanFill": float(np.mean(fill)),
            "stdFill": float(np.std(fill)),
            "varianceFill": variance,
            "parsevalVariance": parseval_variance,
            "parsevalRelError": 0.0,
            "maxAbsDelta": float(np.max(np.abs(delta))),
            "qCentroid": math.nan,
            "qRms": math.nan,
            "totalNonzeroPower": 0.0,
        }
        n_nonzero = int(np.count_nonzero(nonzero))
        for cut in CUTS:
            mask = nonzero & (q <= cut)
            mode_fraction = np.count_nonzero(mask) / n_nonzero
            summary[f"frac_q_le_{cut:g}"] = math.nan
            summary[f"white_frac_q_le_{cut:g}"] = mode_fraction
            summary[f"excess_white_q_le_{cut:g}"] = math.nan
        return summary, []

    q_nonzero = q[nonzero]
    p_nonzero = power[nonzero]
    q_centroid = float(np.sum(q_nonzero * p_nonzero) / total_nonzero)
    q_rms = float(math.sqrt(np.sum((q_nonzero ** 2) * p_nonzero) / total_nonzero))

    summary = {
        "zeroPowerFrame": False,
        "meanFill": float(np.mean(fill)),
        "stdFill": float(np.std(fill)),
        "varianceFill": variance,
        "parsevalVariance": parseval_variance,
        "parsevalRelError": abs(parseval_variance - variance) / max(variance, 1e-300),
        "maxAbsDelta": float(np.max(np.abs(delta))),
        "qCentroid": q_centroid,
        "qRms": q_rms,
        "totalNonzeroPower": total_nonzero,
    }

    n_nonzero = int(np.count_nonzero(nonzero))
    for cut in CUTS:
        mask = nonzero & (q <= cut)
        mode_fraction = np.count_nonzero(mask) / n_nonzero
        power_fraction = float(np.sum(power[mask]) / total_nonzero)
        summary[f"frac_q_le_{cut:g}"] = power_fraction
        summary[f"white_frac_q_le_{cut:g}"] = mode_fraction
        summary[f"excess_white_q_le_{cut:g}"] = (
            power_fraction / mode_fraction if mode_fraction > 0 else math.nan
        )

    shell_rows = []
    max_shell = int(np.max(shell))
    global_mean_power = total_nonzero / n_nonzero
    for s in range(1, max_shell + 1):
        mask = nonzero & (shell == s)
        count = int(np.count_nonzero(mask))
        if count == 0:
            continue
        sum_power = float(np.sum(power[mask]))
        mean_power = sum_power / count
        shell_rows.append({
            "qShell": s,
            "modeCount": count,
            "sumPower": sum_power,
            "meanPower": mean_power,
            "fractionNonzeroPower": sum_power / total_nonzero,
            "meanPowerOverWhite": mean_power / global_mean_power,
        })
    return summary, shell_rows


def write_csv(path: Path, rows):
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


def analyze_case(label, root, meta, base, q, shell, nonzero, include_step0=False):
    summaries = []
    radial = []
    dumps = base.list_dumps(root / "tg")
    if not dumps:
        raise ValueError(f"no TG dumps in {root / 'tg'}")

    for step, path in dumps:
        if step == 0 and not include_step0:
            continue
        state = base.read_state(path)
        fill = reconstruct_fill(state, meta)
        summary, shells = spectrum_from_fill(fill, q, shell, nonzero)
        head = {
            "case": label,
            "step": int(step),
            "time": float(step) * float(meta["dt"]),
        }
        summaries.append({**head, **summary})
        radial.extend({**head, **row} for row in shells)
    return summaries, radial


def aggregate_radial(radial, include_step0):
    acc = defaultdict(list)
    for row in radial:
        if not include_step0 and int(row["step"]) == 0:
            continue
        acc[(row["case"], int(row["qShell"]))].append(float(row["meanPower"]))
    rows = []
    for (case, qshell), vals in sorted(acc.items()):
        a = np.asarray(vals, float)
        rows.append({
            "case": case,
            "qShell": qshell,
            "frames": len(a),
            "meanShellPower": float(np.mean(a)),
            "stdShellPower": float(np.std(a, ddof=1)) if len(a) > 1 else 0.0,
        })
    return rows


def aggregate_summary(summaries, include_step0):
    rows = []
    for case in sorted({r["case"] for r in summaries}):
        subset = [
            r for r in summaries
            if r["case"] == case and (include_step0 or int(r["step"]) != 0)
        ]
        if not subset:
            continue
        out = {"case": case, "frames": len(subset)}
        for key in (
            "stdFill", "varianceFill", "qCentroid", "qRms",
            *[f"frac_q_le_{c:g}" for c in CUTS],
            *[f"excess_white_q_le_{c:g}" for c in CUTS],
        ):
            vals = np.array([float(r[key]) for r in subset], float)
            vals = vals[np.isfinite(vals)]
            if len(vals) == 0:
                out[f"mean_{key}"] = math.nan
                out[f"std_{key}"] = math.nan
            else:
                out[f"mean_{key}"] = float(np.mean(vals))
                out[f"std_{key}"] = (
                    float(np.std(vals, ddof=1)) if len(vals) > 1 else 0.0
                )
        rows.append(out)
    return rows


def matched_comparison(summaries):
    by = defaultdict(dict)
    for r in summaries:
        by[int(r["step"])][r["case"]] = r
    rows = []
    for step in sorted(by):
        if "tau0" not in by[step] or "tau025" not in by[step]:
            continue
        a = by[step]["tau0"]
        b = by[step]["tau025"]
        row = {
            "step": step,
            "time": b["time"],
            "stdFill_tau0": a["stdFill"],
            "stdFill_tau025": b["stdFill"],
            "stdFillRatio": b["stdFill"] / max(a["stdFill"], 1e-300),
            "qCentroid_tau0": a["qCentroid"],
            "qCentroid_tau025": b["qCentroid"],
        }
        for c in CUTS:
            k = f"frac_q_le_{c:g}"
            row[f"{k}_tau0"] = a[k]
            row[f"{k}_tau025"] = b[k]
            row[f"{k}_ratio"] = b[k] / max(a[k], 1e-300)
        rows.append(row)
    return rows


def aggregate_ratio(radial_avg):
    by = defaultdict(dict)
    for r in radial_avg:
        by[int(r["qShell"])][r["case"]] = r
    rows = []
    for qshell in sorted(by):
        if "tau0" not in by[qshell] or "tau025" not in by[qshell]:
            continue
        p0 = float(by[qshell]["tau0"]["meanShellPower"])
        p1 = float(by[qshell]["tau025"]["meanShellPower"])
        rows.append({
            "qShell": qshell,
            "meanShellPower_tau0": p0,
            "meanShellPower_tau025": p1,
            "powerRatio_tau025_over_tau0": p1 / max(p0, 1e-300),
        })
    return rows


def print_report(agg_summary, ratio_rows, meta, tau_active):
    print("===== 0493x7n DENSITY SPECTRUM =====")
    print(
        f"grid={meta['Nx']}x{meta['Ny']} L={meta['Lx']}x{meta['Ly']} "
        f"gamma={meta['gamma']} dt={meta['dt']}"
    )
    print("delta = deposited cell mass/(gamma*particleMass) - 1")
    print("q = integer Fourier mode magnitude; q=1 is box-scale")
    print()

    print(
        f"{'case':8s} {'stdFill':>10s} {'qCent':>9s} "
        f"{'F<=2':>9s} {'xwhite2':>9s} {'F<=4':>9s} {'xwhite4':>9s} "
        f"{'F<=8':>9s} {'xwhite8':>9s}"
    )
    print("-" * 92)
    for r in agg_summary:
        print(
            f"{r['case']:8s} "
            f"{r['mean_stdFill']:10.5g} "
            f"{r['mean_qCentroid']:9.4f} "
            f"{r['mean_frac_q_le_2']:9.5f} "
            f"{r['mean_excess_white_q_le_2']:9.3f} "
            f"{r['mean_frac_q_le_4']:9.5f} "
            f"{r['mean_excess_white_q_le_4']:9.3f} "
            f"{r['mean_frac_q_le_8']:9.5f} "
            f"{r['mean_excess_white_q_le_8']:9.3f}"
        )

    active = next((r for r in agg_summary if r["case"] == "tau025"), None)
    if active and tau_active > 0:
        print()
        print(
            f"tau025 sourceRms proxy = mean(stdFill)/tau = "
            f"{active['mean_stdFill']/tau_active:.6g}"
        )

    if ratio_rows:
        strongest = sorted(
            ratio_rows,
            key=lambda r: float(r["powerRatio_tau025_over_tau0"]),
            reverse=True,
        )[:10]
        print()
        print("Largest time-averaged shell power ratios tau025/tau0:")
        for r in strongest:
            print(
                f"  q={int(r['qShell']):2d} "
                f"ratio={float(r['powerRatio_tau025_over_tau0']):.5g}"
            )


def main():
    a = parse_args()
    m0 = load_meta(a.tau0_root)
    m1 = load_meta(a.tau025_root)
    compatible(m0, m1)

    nx = int(m0["Nx"])
    ny = int(m0["Ny"])
    q, shell, nonzero = mode_geometry(nx, ny)
    base = import_base()

    s0, r0 = analyze_case(
        "tau0", a.tau0_root, m0, base, q, shell, nonzero,
        include_step0=a.include_step0,
    )
    s1, r1 = analyze_case(
        "tau025", a.tau025_root, m1, base, q, shell, nonzero,
        include_step0=a.include_step0,
    )
    summaries = s0 + s1
    radial = r0 + r1

    out = a.out
    out.mkdir(parents=True, exist_ok=True)

    radial_avg = aggregate_radial(radial, a.include_step0)
    agg_summary = aggregate_summary(summaries, a.include_step0)
    matched = matched_comparison(summaries)
    ratio = aggregate_ratio(radial_avg)

    write_csv(out / "density_spectrum_frames_0493x7n.csv", summaries)
    write_csv(out / "density_spectrum_radial_frames_0493x7n.csv", radial)
    write_csv(out / "density_spectrum_radial_mean_0493x7n.csv", radial_avg)
    write_csv(out / "density_spectrum_case_summary_0493x7n.csv", agg_summary)
    write_csv(out / "density_spectrum_matched_0493x7n.csv", matched)
    write_csv(out / "density_spectrum_tau025_over_tau0_0493x7n.csv", ratio)

    manifest = {
        "schema": "0493x7n-density-spectrum-v1",
        "tau0Root": str(a.tau0_root),
        "tau025Root": str(a.tau025_root),
        "includeStep0InAverages": bool(a.include_step0),
        "tauActive": a.tau_active,
        "cuts": list(CUTS),
        "field": "deposited cell mass/(gamma*particleMass)-1",
        "fftNormalization": "ortho",
        "qDefinition": "sqrt(mx^2+my^2) in integer box Fourier modes",
        "metadata": {
            k: m0[k]
            for k in ("Lx", "Ly", "Nx", "Ny", "gamma", "dt", "kBT", "particleMass")
        },
    }
    (out / "density_spectrum_manifest_0493x7n.json").write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n"
    )

    print_report(agg_summary, ratio, m0, a.tau_active)
    print()
    print(f"[0493x7n-spectrum] out={out}")
    print("[0493x7n-spectrum] PASS offline analysis completed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
