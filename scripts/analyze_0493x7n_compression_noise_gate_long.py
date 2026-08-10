#!/usr/bin/env python3
"""0493x7n long-run compression-vs-noise gate qualification.

Uses:
  * TG tau=0       : noise reference (no x7d density relaxation)
  * TG tau=.25     : known pathological raw-x7d reference
  * dam tau=0      : unrelaxed compression reference, first 500 steps
  * dam tau=.25    : matched first-500-step reference
  * dam tau=.25 long (5000 steps): visually qualified successful Q6-G-F trajectory

Candidate estimator:
  active cell = dN >= theta AND at least K of 4 direct neighbours satisfy dN >= theta

where:
  dN = gamma * (liquidFill - 1)

For every theta and K, the diagnostic measures:
  * active-cell fraction
  * positive density excess captured
  * source RMS if the full raw density error is applied after gating
  * source RMS if a dead-band (dN-theta) is applied after gating
  * temporal evolution in the successful 5000-step dam-break

No solver modification.
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


THRESHOLDS = (2.0, 3.0, 4.0, 5.0, 6.0)
NEIGHBOUR_MIN = (0, 1, 2)
TAU_PROXY = 0.25


def parse_args():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tg-tau0-root", type=Path, required=True)
    ap.add_argument("--tg-tau025-root", type=Path, required=True)
    ap.add_argument("--dam-tau0-root", type=Path, required=True)
    ap.add_argument("--dam-tau025-root", type=Path, required=True)
    ap.add_argument("--dam-long-tau025-root", type=Path, required=True)
    ap.add_argument("--out", type=Path, required=True)

    ap.add_argument("--dam-gamma", type=float, default=10.0)
    ap.add_argument("--dam-liquid-type", type=int, default=1)
    ap.add_argument("--dam-liquid-mass", type=float, default=1000.0)
    ap.add_argument("--bulk-fill-min", type=float, default=0.50)

    ap.add_argument(
        "--long-stride",
        type=int,
        default=5,
        help="read every Nth long-run dump (dump cadence is 10 steps here)",
    )
    ap.add_argument(
        "--window-steps",
        type=int,
        default=500,
        help="temporal aggregation width for the long dam-break",
    )
    return ap.parse_args()


def import_helpers():
    scripts = Path(__file__).resolve().parent
    if str(scripts) not in sys.path:
        sys.path.insert(0, str(scripts))
    comp = importlib.import_module(
        "analyze_0493x7n_compression_estimator_offline"
    )
    return comp, comp.import_base()


def neighbour_count4(active, valid, periodic):
    active = np.asarray(active, bool) & np.asarray(valid, bool)
    if periodic:
        return (
            np.roll(active, 1, axis=0).astype(np.int8)
            + np.roll(active, -1, axis=0).astype(np.int8)
            + np.roll(active, 1, axis=1).astype(np.int8)
            + np.roll(active, -1, axis=1).astype(np.int8)
        )

    n = np.zeros(active.shape, np.int8)
    n[1:, :] += active[:-1, :]
    n[:-1, :] += active[1:, :]
    n[:, 1:] += active[:, :-1]
    n[:, :-1] += active[:, 1:]
    n[~valid] = 0
    return n


def safe_ratio(a, b):
    return float(a / b) if b > 0 else math.nan


def reconstruct_density_frames(root, meta, helper, base, bulk_fill_min, stride):
    dumps = helper.list_case_frames(root, meta, base, stride)
    frames = []

    for step, path in dumps:
        state = base.read_state(path)
        delta, fill, u, v, occupied = helper.reconstruct_fields(state, meta)

        if meta["kind"] == "dam":
            bulk0 = (fill >= bulk_fill_min) & occupied
        else:
            bulk0 = occupied

        bulk = helper.erode_bulk(bulk0, bool(meta["periodic"]))
        dN = float(meta["gamma"]) * delta

        frames.append({
            "step": int(step),
            "time": float(step) * float(meta["dt"]),
            "dN": dN,
            "bulk": bulk,
        })

    if not frames:
        raise ValueError(f"no density frames reconstructed below {root}")
    return frames


def gate_frame(case, fr, meta, theta, kmin, tau_proxy):
    dN = fr["dN"]
    bulk = fr["bulk"]
    gamma = float(meta["gamma"])

    over = bulk & (dN >= theta)
    n4 = neighbour_count4(over, bulk, bool(meta["periodic"]))
    gate = over & (n4 >= kmin)

    vals = dN[bulk]
    gvals = dN[gate]

    positive_total = float(np.sum(np.maximum(vals, 0.0)))
    raw_positive_sq_mean = (
        float(np.mean((np.maximum(vals, 0.0) / gamma / tau_proxy) ** 2))
        if len(vals) else math.nan
    )

    # Option A: the threshold/neighbour test only classifies compression.
    # Once classified, apply the whole positive density error.
    full_source = np.zeros_like(dN, dtype=float)
    full_source[gate] = dN[gate] / gamma / tau_proxy

    # Option B: threshold is also a physical dead-band.
    dead = np.zeros_like(dN, dtype=float)
    dead[gate] = np.maximum(dN[gate] - theta, 0.0)
    dead_source = dead / gamma / tau_proxy

    bulk_count = int(np.count_nonzero(bulk))
    gate_count = int(np.count_nonzero(gate))

    return {
        "case": case,
        "step": fr["step"],
        "time": fr["time"],
        "thetaDN": theta,
        "neighbourMin": kmin,
        "bulkCells": bulk_count,
        "gateCells": gate_count,
        "activationFraction": (
            gate_count / bulk_count if bulk_count else math.nan
        ),
        "positiveExcessCapturedFullFraction": (
            float(np.sum(gvals)) / positive_total
            if positive_total > 0 else math.nan
        ),
        "positiveExcessCapturedDeadbandFraction": (
            float(np.sum(np.maximum(gvals - theta, 0.0))) / positive_total
            if positive_total > 0 else math.nan
        ),
        "fullGateSourceRms": (
            float(np.sqrt(np.mean(full_source[bulk] ** 2)))
            if bulk_count else math.nan
        ),
        "deadbandSourceRms": (
            float(np.sqrt(np.mean(dead_source[bulk] ** 2)))
            if bulk_count else math.nan
        ),
        "rawPositiveSourceRms": (
            math.sqrt(raw_positive_sq_mean)
            if math.isfinite(raw_positive_sq_mean) else math.nan
        ),
        "meanNeighboursAmongOver": (
            float(np.mean(n4[over])) if np.any(over) else 0.0
        ),
        "fractionOverWithAtLeast1Neighbour": (
            float(np.mean(n4[over] >= 1)) if np.any(over) else 0.0
        ),
        "fractionOverWithAtLeast2Neighbours": (
            float(np.mean(n4[over] >= 2)) if np.any(over) else 0.0
        ),
    }


def aggregate(rows, group_keys, value_keys):
    groups = defaultdict(list)
    for r in rows:
        groups[tuple(r[k] for k in group_keys)].append(r)

    out = []
    for key, rs in sorted(
        groups.items(), key=lambda kv: tuple(str(x) for x in kv[0])
    ):
        row = dict(zip(group_keys, key))
        row["frames"] = len(rs)
        for v in value_keys:
            a = np.array([float(r.get(v, math.nan)) for r in rs], float)
            a = a[np.isfinite(a)]
            row[f"mean_{v}"] = float(np.mean(a)) if len(a) else math.nan
            row[f"std_{v}"] = (
                float(np.std(a, ddof=1)) if len(a) > 1 else 0.0
            )
        out.append(row)
    return out


VALUE_KEYS = (
    "bulkCells",
    "activationFraction",
    "positiveExcessCapturedFullFraction",
    "positiveExcessCapturedDeadbandFraction",
    "fullGateSourceRms",
    "deadbandSourceRms",
    "rawPositiveSourceRms",
    "meanNeighboursAmongOver",
    "fractionOverWithAtLeast1Neighbour",
    "fractionOverWithAtLeast2Neighbours",
)


def add_window(rows, window_steps):
    out = []
    for r in rows:
        rr = dict(r)
        step = int(r["step"])
        start = (max(step, 1) - 1) // window_steps * window_steps + 1
        end = start + window_steps - 1
        rr["windowStartStep"] = start
        rr["windowEndStep"] = end
        out.append(rr)
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


def lookup(summary, case, theta, kmin):
    for r in summary:
        if (
            r["case"] == case
            and math.isclose(float(r["thetaDN"]), float(theta))
            and int(r["neighbourMin"]) == int(kmin)
        ):
            return r
    return None


def print_static_comparison(summary):
    print("===== 0493x7n COMPRESSION-vs-NOISE LOCAL GATE =====")
    print("gate: dN>=theta and at least K active 4-neighbours")
    print("source proxy uses tau=0.25")
    print()

    print("Noise/compression discrimination using tau0 references:")
    print(
        f"{'dN':>4s} {'K':>2s} "
        f"{'TG act':>8s} {'DB act':>8s} {'act x':>7s} "
        f"{'TG src':>8s} {'DB src':>8s} "
        f"{'DB cap':>8s} {'DB deadcap':>10s}"
    )
    print("-" * 82)

    for theta in THRESHOLDS:
        for k in NEIGHBOUR_MIN:
            tg = lookup(summary, "tg_tau0", theta, k)
            db = lookup(summary, "dam_tau0", theta, k)
            if tg is None or db is None:
                continue
            ta = float(tg["mean_activationFraction"])
            da = float(db["mean_activationFraction"])
            print(
                f"{theta:4.1f} {k:2d} "
                f"{ta:8.5f} {da:8.5f} {safe_ratio(da, ta):7.2f} "
                f"{tg['mean_fullGateSourceRms']:8.4f} "
                f"{db['mean_fullGateSourceRms']:8.4f} "
                f"{db['mean_positiveExcessCapturedFullFraction']:8.4f} "
                f"{db['mean_positiveExcessCapturedDeadbandFraction']:10.4f}"
            )


def print_long_windows(window_summary):
    print()
    print("Successful dam tau=.25 s5000 — temporal gate evolution")
    print("(focused candidates theta=3,4; K=1,2)")
    print(
        f"{'window':>10s} {'dN':>4s} {'K':>2s} "
        f"{'active':>8s} {'capFull':>8s} {'srcFull':>8s} "
        f"{'capDead':>8s} {'srcDead':>8s}"
    )
    print("-" * 79)

    rows = [
        r for r in window_summary
        if float(r["thetaDN"]) in (3.0, 4.0)
        and int(r["neighbourMin"]) in (1, 2)
    ]
    rows.sort(
        key=lambda r: (
            int(r["windowStartStep"]),
            float(r["thetaDN"]),
            int(r["neighbourMin"]),
        )
    )
    for r in rows:
        win = f"{int(r['windowStartStep'])}-{int(r['windowEndStep'])}"
        print(
            f"{win:>10s} {float(r['thetaDN']):4.1f} "
            f"{int(r['neighbourMin']):2d} "
            f"{r['mean_activationFraction']:8.5f} "
            f"{r['mean_positiveExcessCapturedFullFraction']:8.4f} "
            f"{r['mean_fullGateSourceRms']:8.4f} "
            f"{r['mean_positiveExcessCapturedDeadbandFraction']:8.4f} "
            f"{r['mean_deadbandSourceRms']:8.4f}"
        )


def print_success_vs_noise(summary):
    print()
    print("Successful long dam-break vs TG noise reference:")
    print(
        f"{'dN':>4s} {'K':>2s} "
        f"{'TG act':>8s} {'DBlong act':>10s} {'x':>7s} "
        f"{'TG src':>8s} {'DBlong src':>10s}"
    )
    print("-" * 72)

    for theta in (2.0, 3.0, 4.0, 5.0, 6.0):
        for k in (1, 2):
            tg = lookup(summary, "tg_tau0", theta, k)
            db = lookup(summary, "dam_long_tau025", theta, k)
            if tg is None or db is None:
                continue
            ta = float(tg["mean_activationFraction"])
            da = float(db["mean_activationFraction"])
            print(
                f"{theta:4.1f} {k:2d} "
                f"{ta:8.5f} {da:10.5f} {safe_ratio(da, ta):7.2f} "
                f"{tg['mean_fullGateSourceRms']:8.4f} "
                f"{db['mean_fullGateSourceRms']:10.4f}"
            )


def main():
    a = parse_args()
    if a.long_stride < 1:
        raise ValueError("--long-stride must be >=1")
    if a.window_steps < 1:
        raise ValueError("--window-steps must be >=1")

    helper, base = import_helpers()

    case_defs = [
        (
            "tg_tau0",
            a.tg_tau0_root,
            helper.load_tg_meta(a.tg_tau0_root),
            1,
        ),
        (
            "tg_tau025",
            a.tg_tau025_root,
            helper.load_tg_meta(a.tg_tau025_root),
            1,
        ),
        (
            "dam_tau0",
            a.dam_tau0_root,
            helper.load_dam_meta(a.dam_tau0_root, a),
            1,
        ),
        (
            "dam_tau025",
            a.dam_tau025_root,
            helper.load_dam_meta(a.dam_tau025_root, a),
            1,
        ),
        (
            "dam_long_tau025",
            a.dam_long_tau025_root,
            helper.load_dam_meta(a.dam_long_tau025_root, a),
            a.long_stride,
        ),
    ]

    frame_rows = []
    case_meta = {}

    for case, root, meta, stride in case_defs:
        case_meta[case] = meta
        print(
            f"[0493x7n-local-gate] reading {case} stride={stride} root={root}",
            file=sys.stderr,
        )
        frames = reconstruct_density_frames(
            root, meta, helper, base, a.bulk_fill_min, stride
        )

        for fr in frames:
            for theta in THRESHOLDS:
                for kmin in NEIGHBOUR_MIN:
                    frame_rows.append(
                        gate_frame(
                            case, fr, meta, theta, kmin, TAU_PROXY
                        )
                    )

    summary = aggregate(
        frame_rows,
        ["case", "thetaDN", "neighbourMin"],
        VALUE_KEYS,
    )

    long_rows = [
        r for r in frame_rows if r["case"] == "dam_long_tau025"
    ]
    long_window_rows = add_window(long_rows, a.window_steps)
    window_summary = aggregate(
        long_window_rows,
        [
            "case",
            "windowStartStep",
            "windowEndStep",
            "thetaDN",
            "neighbourMin",
        ],
        VALUE_KEYS,
    )

    a.out.mkdir(parents=True, exist_ok=True)
    write_csv(
        a.out / "compression_noise_local_gate_frames_0493x7n.csv",
        frame_rows,
    )
    write_csv(
        a.out / "compression_noise_local_gate_summary_0493x7n.csv",
        summary,
    )
    write_csv(
        a.out / "compression_noise_local_gate_long_windows_0493x7n.csv",
        window_summary,
    )

    manifest = {
        "schema": "0493x7n-compression-noise-local-gate-v1",
        "variable": "dN = gamma*(liquidFill-1)",
        "thresholdsDN": list(THRESHOLDS),
        "neighbourDefinition": "4 direct neighbours",
        "neighbourMinValues": list(NEIGHBOUR_MIN),
        "tauProxy": TAU_PROXY,
        "fullGate": "if gate is true, apply full positive dN",
        "deadbandGate": "if gate is true, apply max(dN-theta,0)",
        "damBulkFillMin": a.bulk_fill_min,
        "damBulkErosionCells": 1,
        "longStride": a.long_stride,
        "windowSteps": a.window_steps,
        "roots": {
            case: str(root) for case, root, _, _ in case_defs
        },
    }
    (
        a.out / "compression_noise_local_gate_manifest_0493x7n.json"
    ).write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")

    print_static_comparison(summary)
    print_success_vs_noise(summary)
    print_long_windows(window_summary)

    print()
    print(f"[0493x7n-local-gate] out={a.out}")
    print("[0493x7n-local-gate] PASS long-run gate qualification completed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
