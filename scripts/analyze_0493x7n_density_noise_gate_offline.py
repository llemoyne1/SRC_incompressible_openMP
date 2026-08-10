#!/usr/bin/env python3
"""0493x7n offline density-noise gate sizing.

Purpose:
  Test whether x7d can distinguish occupancy noise from coherent compression
  using a very cheap local statistic rather than a spatial convolution.

Key variable:
    dN = gamma * (liquidFill - 1)
which is the local density error expressed as an equivalent number of reference
particles per cell.

Measures:
  * positive/negative dN tails
  * TG-tau0-derived positive noise thresholds (95%, 99%, 99.9%)
  * transfer of those thresholds to TG tau=.25 and dam-break
  * 4-neighbour spatial clustering of over-dense cells
  * fraction of positive density excess captured by each gate

No solver modification; existing dumps only.
"""
from __future__ import annotations

import argparse
import csv
import importlib
import json
import math
import sys
from collections import defaultdict, deque
from pathlib import Path

import numpy as np


FIXED_THRESHOLDS_DN = (2.0, 3.0, 4.0, 5.0, 6.0)
TG_QUANTILES = (0.95, 0.99, 0.999)
CLUSTER_SIZES = (2, 4, 8)


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
    ap.add_argument("--bulk-fill-min", type=float, default=0.50)
    ap.add_argument("--stride", type=int, default=1)
    return ap.parse_args()


def import_compression_module():
    scripts_dir = Path(__file__).resolve().parent
    if str(scripts_dir) not in sys.path:
        sys.path.insert(0, str(scripts_dir))
    return importlib.import_module(
        "analyze_0493x7n_compression_estimator_offline"
    )


def finite(a):
    a = np.asarray(a, float)
    return a[np.isfinite(a)]


def quant(a, q):
    a = finite(a)
    return float(np.quantile(a, q)) if len(a) else math.nan


def skewness(a):
    a = finite(a)
    if len(a) < 3:
        return math.nan
    m = float(np.mean(a))
    s = float(np.std(a))
    if s == 0:
        return 0.0
    z = (a - m) / s
    return float(np.mean(z ** 3))


def connected_cluster_sizes(active, valid, periodic):
    """4-neighbour cluster sizes inside valid mask."""
    active = np.asarray(active, bool) & np.asarray(valid, bool)
    ny, nx = active.shape
    seen = np.zeros_like(active, bool)
    sizes = []

    ys, xs = np.nonzero(active)
    for y0, x0 in zip(ys.tolist(), xs.tolist()):
        if seen[y0, x0]:
            continue
        q = [(y0, x0)]
        seen[y0, x0] = True
        n = 0
        while q:
            y, x = q.pop()
            n += 1
            for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1)):
                yy, xx = y + dy, x + dx
                if periodic:
                    yy %= ny
                    xx %= nx
                elif yy < 0 or yy >= ny or xx < 0 or xx >= nx:
                    continue
                if active[yy, xx] and not seen[yy, xx]:
                    seen[yy, xx] = True
                    q.append((yy, xx))
        sizes.append(n)
    return sizes


def frame_density(root, meta, base, helper, args):
    dumps = helper.list_case_frames(root, meta, base, args.stride)
    frames = []
    for step, path in dumps:
        state = base.read_state(path)
        delta, fill, u, v, occupied = helper.reconstruct_fields(state, meta)

        if meta["kind"] == "dam":
            bulk0 = (fill >= args.bulk_fill_min) & occupied
        else:
            bulk0 = occupied
        bulk = helper.erode_bulk(bulk0, meta["periodic"])

        dN = float(meta["gamma"]) * delta
        frames.append({
            "step": int(step),
            "time": float(step) * float(meta["dt"]),
            "dN": dN,
            "bulk": bulk,
        })
    return frames


def basic_frame_row(case, fr):
    vals = finite(fr["dN"][fr["bulk"]])
    pos = vals[vals > 0]
    neg = -vals[vals < 0]
    return {
        "case": case,
        "step": fr["step"],
        "time": fr["time"],
        "bulkCells": len(vals),
        "meanDN": float(np.mean(vals)) if len(vals) else math.nan,
        "rmsDN": float(np.sqrt(np.mean(vals * vals))) if len(vals) else math.nan,
        "stdDN": float(np.std(vals)) if len(vals) else math.nan,
        "skewDN": skewness(vals),
        "positiveFraction": float(np.mean(vals > 0)) if len(vals) else math.nan,
        "positiveQ50": quant(pos, 0.50),
        "positiveQ90": quant(pos, 0.90),
        "positiveQ95": quant(pos, 0.95),
        "positiveQ99": quant(pos, 0.99),
        "negativeAbsQ95": quant(neg, 0.95),
        "negativeAbsQ99": quant(neg, 0.99),
    }


def gate_metrics(case, fr, threshold, threshold_label, periodic):
    dN = fr["dN"]
    bulk = fr["bulk"]
    vals = dN[bulk]
    positive_excess = np.maximum(vals, 0.0)
    total_positive = float(np.sum(positive_excess))

    active = bulk & (dN >= threshold)
    n_active = int(np.count_nonzero(active))
    n_bulk = int(np.count_nonzero(bulk))
    active_vals = dN[active]

    sizes = connected_cluster_sizes(active, bulk, periodic)
    active_cluster_cells = sum(sizes)
    assert active_cluster_cells == n_active

    out = {
        "case": case,
        "step": fr["step"],
        "time": fr["time"],
        "thresholdLabel": threshold_label,
        "thresholdDN": float(threshold),
        "bulkCells": n_bulk,
        "activeCells": n_active,
        "activationFraction": n_active / n_bulk if n_bulk else math.nan,
        "positiveExcessCapturedFraction": (
            float(np.sum(active_vals)) / total_positive
            if total_positive > 0 else math.nan
        ),
        "deadbandResidualPerBulkCell": (
            float(np.sum(np.maximum(active_vals - threshold, 0.0))) / n_bulk
            if n_bulk else math.nan
        ),
        "clusterCount": len(sizes),
        "maxClusterSize": max(sizes) if sizes else 0,
        "meanClusterSize": (
            float(np.mean(sizes)) if sizes else 0.0
        ),
    }

    for nmin in CLUSTER_SIZES:
        cells = sum(s for s in sizes if s >= nmin)
        out[f"activeCellsInClusterGE{nmin}Fraction"] = (
            cells / n_active if n_active else 0.0
        )
        out[f"bulkCellsInClusterGE{nmin}Fraction"] = (
            cells / n_bulk if n_bulk else 0.0
        )
    return out


def aggregate(rows, group_keys, numeric_keys):
    groups = defaultdict(list)
    for r in rows:
        groups[tuple(r[k] for k in group_keys)].append(r)
    out = []
    for keyvals, rs in sorted(groups.items(), key=lambda kv: tuple(map(str, kv[0]))):
        row = dict(zip(group_keys, keyvals))
        row["frames"] = len(rs)
        for k in numeric_keys:
            vals = np.array([float(r.get(k, math.nan)) for r in rs], float)
            vals = vals[np.isfinite(vals)]
            row[f"mean_{k}"] = float(np.mean(vals)) if len(vals) else math.nan
            row[f"std_{k}"] = (
                float(np.std(vals, ddof=1)) if len(vals) > 1 else 0.0
            )
        out.append(row)
    return out


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


def main():
    a = parse_args()
    helper = import_compression_module()
    base = helper.import_base()

    cases = [
        ("tg_tau0", a.tg_tau0_root, helper.load_tg_meta(a.tg_tau0_root)),
        ("tg_tau025", a.tg_tau025_root, helper.load_tg_meta(a.tg_tau025_root)),
        ("dam_tau0", a.dam_tau0_root, helper.load_dam_meta(a.dam_tau0_root, a)),
        ("dam_tau025", a.dam_tau025_root, helper.load_dam_meta(a.dam_tau025_root, a)),
    ]

    frames_by_case = {}
    basic_rows = []
    for case, root, meta in cases:
        print(f"[0493x7n-density-gate] reading {case} root={root}", file=sys.stderr)
        frames = frame_density(root, meta, base, helper, a)
        frames_by_case[case] = (frames, meta)
        basic_rows.extend(basic_frame_row(case, fr) for fr in frames)

    # Noise thresholds are learned from the unrelaxed TG reference only,
    # in particle-equivalent units dN = gamma*(fill-1).
    tg0_positive = []
    for fr in frames_by_case["tg_tau0"][0]:
        vals = fr["dN"][fr["bulk"]]
        vals = vals[np.isfinite(vals) & (vals > 0)]
        tg0_positive.append(vals)
    tg0_positive = np.concatenate(tg0_positive)
    learned = {
        f"tg_tau0_q{int(q*1000):03d}": float(np.quantile(tg0_positive, q))
        for q in TG_QUANTILES
    }

    thresholds = [(f"fixed_{v:g}", v) for v in FIXED_THRESHOLDS_DN]
    thresholds += list(learned.items())

    gate_rows = []
    for case, (frames, meta) in frames_by_case.items():
        for fr in frames:
            for label, theta in thresholds:
                gate_rows.append(
                    gate_metrics(
                        case, fr, theta, label, bool(meta["periodic"])
                    )
                )

    basic_summary = aggregate(
        basic_rows,
        ["case"],
        [
            "bulkCells", "meanDN", "rmsDN", "stdDN", "skewDN",
            "positiveFraction", "positiveQ50", "positiveQ90",
            "positiveQ95", "positiveQ99",
            "negativeAbsQ95", "negativeAbsQ99",
        ],
    )

    gate_summary = aggregate(
        gate_rows,
        ["case", "thresholdLabel", "thresholdDN"],
        [
            "activationFraction", "positiveExcessCapturedFraction",
            "deadbandResidualPerBulkCell", "clusterCount",
            "maxClusterSize", "meanClusterSize",
            *[f"activeCellsInClusterGE{n}Fraction" for n in CLUSTER_SIZES],
            *[f"bulkCellsInClusterGE{n}Fraction" for n in CLUSTER_SIZES],
        ],
    )

    a.out.mkdir(parents=True, exist_ok=True)
    write_csv(a.out / "density_noise_gate_frames_0493x7n.csv", basic_rows)
    write_csv(a.out / "density_noise_gate_summary_0493x7n.csv", basic_summary)
    write_csv(a.out / "density_noise_gate_threshold_frames_0493x7n.csv", gate_rows)
    write_csv(a.out / "density_noise_gate_threshold_summary_0493x7n.csv", gate_summary)

    manifest = {
        "schema": "0493x7n-density-noise-gate-v1",
        "variable": "dN = gamma*(liquidFill-1), equivalent reference particles per cell",
        "fixedThresholdsDN": list(FIXED_THRESHOLDS_DN),
        "tgTau0LearnedPositiveThresholds": learned,
        "clusterConnectivity": 4,
        "clusterSizes": list(CLUSTER_SIZES),
        "damBulkFillMin": a.bulk_fill_min,
        "damBulkErosionCells": 1,
        "roots": {case: str(root) for case, root, _ in cases},
    }
    (a.out / "density_noise_gate_manifest_0493x7n.json").write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n"
    )

    print("===== 0493x7n DENSITY-NOISE GATE SIZING =====")
    print("dN = gamma*(fill-1), in equivalent particles per cell")
    print()
    print("TG tau0 learned positive thresholds:")
    for k, v in learned.items():
        print(f"  {k:18s} dN={v:.6g}")

    print()
    print(
        f"{'case':12s} {'rmsDN':>8s} {'meanDN':>8s} {'skew':>8s} "
        f"{'+q95':>8s} {'+q99':>8s} {'-q99':>8s}"
    )
    print("-" * 66)
    for r in basic_summary:
        print(
            f"{r['case']:12s} "
            f"{r['mean_rmsDN']:8.4f} "
            f"{r['mean_meanDN']:8.4f} "
            f"{r['mean_skewDN']:8.4f} "
            f"{r['mean_positiveQ95']:8.3f} "
            f"{r['mean_positiveQ99']:8.3f} "
            f"{r['mean_negativeAbsQ99']:8.3f}"
        )

    print()
    print("Transfer of TG-tau0 q99 positive-noise threshold:")
    q99_label = "tg_tau0_q990"
    chosen = [r for r in gate_summary if r["thresholdLabel"] == q99_label]
    print(
        f"{'case':12s} {'theta':>7s} {'active':>8s} {'capture+':>9s} "
        f"{'cl>=2':>8s} {'cl>=4':>8s} {'cl>=8':>8s} {'maxCl':>8s}"
    )
    print("-" * 80)
    for r in chosen:
        print(
            f"{r['case']:12s} "
            f"{r['thresholdDN']:7.3f} "
            f"{r['mean_activationFraction']:8.4f} "
            f"{r['mean_positiveExcessCapturedFraction']:9.4f} "
            f"{r['mean_activeCellsInClusterGE2Fraction']:8.4f} "
            f"{r['mean_activeCellsInClusterGE4Fraction']:8.4f} "
            f"{r['mean_activeCellsInClusterGE8Fraction']:8.4f} "
            f"{r['mean_maxClusterSize']:8.2f}"
        )

    print()
    print("Fixed-threshold comparison (tau0 references):")
    chosen_cases = {"tg_tau0", "dam_tau0"}
    chosen_rows = [
        r for r in gate_summary
        if r["case"] in chosen_cases and r["thresholdLabel"].startswith("fixed_")
    ]
    print(
        f"{'dN':>5s} {'case':12s} {'active':>8s} {'capture+':>9s} "
        f"{'cl>=2':>8s} {'cl>=4':>8s} {'maxCl':>8s}"
    )
    print("-" * 68)
    for r in sorted(chosen_rows, key=lambda x: (float(x["thresholdDN"]), x["case"])):
        print(
            f"{r['thresholdDN']:5.1f} {r['case']:12s} "
            f"{r['mean_activationFraction']:8.4f} "
            f"{r['mean_positiveExcessCapturedFraction']:9.4f} "
            f"{r['mean_activeCellsInClusterGE2Fraction']:8.4f} "
            f"{r['mean_activeCellsInClusterGE4Fraction']:8.4f} "
            f"{r['mean_maxClusterSize']:8.2f}"
        )

    print()
    print(f"[0493x7n-density-gate] out={a.out}")
    print("[0493x7n-density-gate] PASS offline noise-gate sizing completed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
