#!/usr/bin/env python3
"""
0493x24ac — audit velocity / flow recovery across all Sato x24 restart segments.

Purpose
-------
Automatically scan the Sato x24 campaign directories and quantify whether a
restart preserves the established gas jet, or whether the inlet/jet collapses
and rebuilds during the first few hundred/thousand steps.

The analyzer uses the recorded rho/uy fields.  It does NOT modify the solver.

Default discovery
-----------------
Search recursively below --runs-root (default: runs) and retain run roots whose
path contains one of:
    0493x24u, 0493x24v, 0493x24w, 0493x24x, 0493x24z,
    0493x24aa, 0493x24ab

A run root is recognized when it contains:
    output/recordings/**/manifest.kv
and matching:
    step_*_field_uy.f32
(optionally step_*_field_rho.f32)

Main diagnostics
----------------
For every recorded frame:
  - mean downward uy in the nozzle core
  - mean downward uy just below the nozzle exit
  - velocity-flow proxy       integral max(-uy,0) dx
  - mass-flow proxy           integral rho*max(-uy,0) dx
  - advective momentum proxy  integral rho*uy^2 dx

All are evaluated over the nominal jet aperture.

The key restart quantity is:
    nozzle_speed_ratio = < -uy >_nozzle / U_jet

Per segment the script reports:
  - source kind: relaxed_start / forced_continuation / unknown
  - first-frame ratio
  - minimum ratio during an early audit window
  - late median ratio
  - recovery times to 50%, 90%, 95% of the late median
  - integrated restart deficit relative to the late median

No pandas.

Typical use
-----------
cd /mnt/e/SRC_MPCD_DEV/SRC_GPU-SURF

python3 scripts/analyze_0493x24ac_sato_restart_velocity_flux.py \
  --runs-root runs \
  --out analysis/0493x24ac_restart_velocity_flux

If desired, restrict discovery:
  --include-regex '0493x24(z|aa|ab)'

Important geometry defaults for the current short-nozzle Sato branch
--------------------------------------------------------------------
Lx=1.5625, Ly=1.0, Nx=400, Ny=256
jet center x=0.78125
D=0.078125 (20 cells)
nozzle exit y=0.87890625
bath reference y=0.81640625
"""

from __future__ import annotations

import argparse
import csv
import math
import re
from pathlib import Path
from collections import defaultdict

import numpy as np
import matplotlib.pyplot as plt


DEFAULT_INCLUDE = r"0493x24(u|v|w|x|z|aa|ab)"


def fv(x, default=math.nan):
    try:
        y = float(x)
        return y if math.isfinite(y) else default
    except Exception:
        return default


def read_kv(path: Path):
    out = {}
    if not path.exists():
        return out
    for raw in path.read_text(errors="replace").splitlines():
        s = raw.strip()
        if not s or s.startswith("#") or "=" not in s:
            continue
        k, v = s.split("=", 1)
        out[k.strip()] = v.strip()
    return out


def parse_env(run_root: Path):
    out = {}
    for p in sorted((run_root / "logs").glob("environment_*.env")):
        out.update(read_kv(p))
    return out


def parse_params(run_root: Path):
    out = {}
    for p in sorted((run_root / "params").glob("*.kv")):
        out.update(read_kv(p))
    return out


def find_recording_dirs(base: Path):
    out = []
    for man in base.glob("**/manifest.kv"):
        rec = man.parent
        if list(rec.glob("step_*_field_uy.f32")):
            out.append(rec)
    return sorted(set(out))


def infer_run_root_from_recording_dir(rec: Path):
    p = rec
    while p != p.parent:
        if p.name == "recordings" and p.parent.name == "output":
            return p.parent.parent
        p = p.parent
    return None


def parse_grid(manifest, nx_default, ny_default):
    nx = int(float(manifest.get("liveGridNx", manifest.get("recordGridNx", nx_default))))
    ny = int(float(manifest.get("liveGridNy", manifest.get("recordGridNy", ny_default))))
    return nx, ny


def step_from_name(p: Path):
    m = re.match(r"step_(\d+)_field_uy\.f32$", p.name)
    return int(m.group(1)) if m else None


def load_f32(path: Path, n: int):
    a = np.fromfile(path, dtype="<f4")
    if a.size != n:
        raise ValueError(f"{path}: expected {n} floats, got {a.size}")
    return a


def parse_open_boundary_jet_speed(params):
    # openBoundarySegment0 = top inlet smin smax ux uy type mass
    for k, v in params.items():
        if not k.startswith("openBoundarySegment"):
            continue
        if k == "openBoundarySegmentCount":
            continue
        tok = str(v).split()
        if len(tok) >= 6 and tok[1].lower() == "inlet":
            ux = fv(tok[4])
            uy = fv(tok[5])
            if math.isfinite(ux) and math.isfinite(uy):
                return math.hypot(ux, uy)
    return math.nan


def classify_source(env, run_root):
    src = env.get("RESTART_STATE", "")
    s = src.lower()
    if "relax" in s and "forced" not in s:
        return "relaxed_start"
    if "forced" in s or "extend" in s or "restart_" in s:
        return "forced_continuation"
    # path-based fallback
    rp = str(run_root).lower()
    if "extend_" in rp or "restart_extend" in rp:
        return "forced_continuation"
    return "unknown"


def infer_forced_offset(run_root: Path):
    s = str(run_root)
    if "t4_to_t6" in s or "extend_t4_to_t6" in s:
        return 4.0
    if "t2_to_t4" in s or "extend_t2_to_t4" in s:
        return 2.0
    return 0.0


def horizontal_section_metrics(uy2d, rho2d, xs, y_index, aperture, dx):
    u = uy2d[y_index, aperture]
    down = np.maximum(-u, 0.0)
    mean_down = float(np.mean(down)) if down.size else math.nan
    vel_flow = float(np.sum(down) * dx) if down.size else math.nan

    if rho2d is None:
        return mean_down, vel_flow, math.nan, math.nan

    r = rho2d[y_index, aperture]
    mass_flow = float(np.sum(r * down) * dx)
    momentum = float(np.sum(r * down * down) * dx)
    return mean_down, vel_flow, mass_flow, momentum


def band_mean_downward(uy2d, xs, ys, aperture, y0, y1):
    ymask = (ys >= min(y0, y1)) & (ys <= max(y0, y1))
    if not np.any(ymask) or not np.any(aperture):
        return math.nan
    a = np.maximum(-uy2d[np.ix_(ymask, aperture)], 0.0)
    return float(np.mean(a))


def recovery_metrics(t, ratio, early_window):
    t = np.asarray(t, float)
    r = np.asarray(ratio, float)
    m = np.isfinite(t) & np.isfinite(r)
    t = t[m]
    r = r[m]
    if len(r) == 0:
        return {}

    order = np.argsort(t)
    t = t[order]
    r = r[order]

    nlate = max(3, int(math.ceil(0.25 * len(r))))
    late = float(np.median(r[-nlate:]))

    early = r[t <= (t[0] + early_window)]
    early_min = float(np.min(early)) if len(early) else float(np.min(r))
    first = float(r[0])

    def trec(frac):
        target = frac * late
        # require 3 consecutive frames above threshold to avoid a single noisy crossing
        good = r >= target
        for i in range(max(0, len(r) - 2)):
            if good[i:i+3].all():
                return float(t[i] - t[0])
        return math.nan

    deficit = np.maximum(late - r, 0.0)
    if len(t) >= 2:
        deficit_area = float(np.trapz(deficit, t))
    else:
        deficit_area = 0.0

    return {
        "firstRatio": first,
        "earlyMinRatio": early_min,
        "lateMedianRatio": late,
        "recoveryT50": trec(0.50),
        "recoveryT90": trec(0.90),
        "recoveryT95": trec(0.95),
        "deficitArea": deficit_area,
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--runs-root", default="runs")
    ap.add_argument("--include-regex", default=DEFAULT_INCLUDE)
    ap.add_argument("--out", default="analysis/0493x24ac_restart_velocity_flux")

    ap.add_argument("--nx", type=int, default=400)
    ap.add_argument("--ny", type=int, default=256)
    ap.add_argument("--Lx", type=float, default=1.5625)
    ap.add_argument("--Ly", type=float, default=1.0)

    ap.add_argument("--jet-center-x", type=float, default=0.78125)
    ap.add_argument("--jet-width", type=float, default=0.078125)
    ap.add_argument("--nozzle-exit-y", type=float, default=0.87890625)
    ap.add_argument("--bath-height", type=float, default=0.81640625)

    ap.add_argument("--nozzle-band-y0", type=float, default=0.900390625,
                    help="lower y of nozzle-core averaging band")
    ap.add_argument("--nozzle-band-y1", type=float, default=0.970703125,
                    help="upper y of nozzle-core averaging band")
    ap.add_argument("--exit-probe-offset-cells", type=float, default=1.5,
                    help="probe this many cells below nozzle exit")
    ap.add_argument("--incident-height-over-D", type=float, default=0.25,
                    help="probe height above initial bath reference")

    ap.add_argument("--early-window", type=float, default=0.5,
                    help="local physical-time window for minimum restart ratio")
    args = ap.parse_args()

    runs_root = Path(args.runs_root)
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)

    include = re.compile(args.include_regex)

    # Find unique run roots.
    roots = {}
    for man in runs_root.glob("**/output/recordings/**/manifest.kv"):
        rr = infer_run_root_from_recording_dir(man.parent)
        if rr is None:
            continue
        if not include.search(str(rr)):
            continue
        roots[str(rr)] = rr

    if not roots:
        raise SystemExit(
            f"[0493x24ac] no matching recording run roots below {runs_root}; "
            f"include-regex={args.include_regex}"
        )

    frame_rows = []
    segment_meta = []

    for run_root in sorted(roots.values()):
        env = parse_env(run_root)
        params = parse_params(run_root)
        source_kind = classify_source(env, run_root)
        forced_offset = infer_forced_offset(run_root)

        dt = fv(params.get("dt"), fv(env.get("DT"), 0.0004))
        U = parse_open_boundary_jet_speed(params)
        if not math.isfinite(U):
            U = fv(env.get("JET_SPEED"))

        # target Fr metadata, if available
        target_fr = fv(env.get("TARGET_FRM_SATO"))
        if not math.isfinite(target_fr):
            # fallback from directory name
            m = re.search(r"Fr0p([0-9]+(?:p[0-9]+)*)", str(run_root))
            if m:
                target_fr = fv("0." + m.group(1).replace("p", ""))

        rec_dirs = find_recording_dirs(run_root / "output" / "recordings")
        if not rec_dirs:
            continue

        seg_count_before = len(frame_rows)

        for rec in rec_dirs:
            manifest = read_kv(rec / "manifest.kv")
            nx, ny = parse_grid(manifest, args.nx, args.ny)
            if nx <= 0 or ny <= 0:
                continue

            dx = args.Lx / nx
            dy = args.Ly / ny
            xs = (np.arange(nx) + 0.5) * dx
            ys = (np.arange(ny) + 0.5) * dy

            aperture = np.abs(xs - args.jet_center_x) <= 0.5 * args.jet_width

            y_exit = args.nozzle_exit_y - args.exit_probe_offset_cells * dy
            iy_exit = int(np.argmin(np.abs(ys - y_exit)))

            y_inc = args.bath_height + args.incident_height_over_D * args.jet_width
            iy_inc = int(np.argmin(np.abs(ys - y_inc)))

            uy_files = sorted(rec.glob("step_*_field_uy.f32"))
            for up in uy_files:
                st = step_from_name(up)
                if st is None:
                    continue

                uy = load_f32(up, nx * ny).reshape((ny, nx))

                rp = rec / f"step_{st:010d}_field_rho.f32"
                rho = None
                if rp.exists():
                    rho = load_f32(rp, nx * ny).reshape((ny, nx))

                nozzle_mean = band_mean_downward(
                    uy, xs, ys, aperture,
                    args.nozzle_band_y0, args.nozzle_band_y1
                )

                exit_mean, exit_vflow, exit_mflow, exit_mom = horizontal_section_metrics(
                    uy, rho, xs, iy_exit, aperture, dx
                )
                inc_mean, inc_vflow, inc_mflow, inc_mom = horizontal_section_metrics(
                    uy, rho, xs, iy_inc, aperture, dx
                )

                local_t = st * dt

                row = {
                    "runRoot": str(run_root),
                    "recordingDir": str(rec),
                    "sourceKind": source_kind,
                    "targetFr": target_fr,
                    "jetSpeedNominal": U,
                    "dt": dt,
                    "localStep": st,
                    "localTime": local_t,
                    "forcedTimeOffset": forced_offset,
                    "forcedTimeApprox": forced_offset + local_t,
                    "nozzleMeanDownUy": nozzle_mean,
                    "nozzleSpeedRatio": nozzle_mean / U if math.isfinite(U) and U > 0 else math.nan,
                    "exitMeanDownUy": exit_mean,
                    "exitSpeedRatio": exit_mean / U if math.isfinite(U) and U > 0 else math.nan,
                    "exitVelocityFlowProxy": exit_vflow,
                    "exitMassFlowProxy": exit_mflow,
                    "exitMomentumFluxProxy": exit_mom,
                    "incidentMeanDownUy": inc_mean,
                    "incidentSpeedRatio": inc_mean / U if math.isfinite(U) and U > 0 else math.nan,
                    "incidentVelocityFlowProxy": inc_vflow,
                    "incidentMassFlowProxy": inc_mflow,
                    "incidentMomentumFluxProxy": inc_mom,
                    "rhoAvailable": int(rho is not None),
                }
                frame_rows.append(row)

        if len(frame_rows) > seg_count_before:
            segment_meta.append({
                "runRoot": str(run_root),
                "sourceKind": source_kind,
                "targetFr": target_fr,
                "jetSpeedNominal": U,
                "dt": dt,
                "forcedTimeOffset": forced_offset,
                "restartState": env.get("RESTART_STATE", ""),
                "restartFromStep": env.get("RESTART_FROM_STEP", ""),
            })

    if not frame_rows:
        raise SystemExit("[0493x24ac] matching run roots found, but no uy frames were readable")

    frame_rows.sort(key=lambda r: (r["targetFr"], r["runRoot"], r["localTime"]))

    with (out / "velocity_flux_history.csv").open("w", newline="") as h:
        fields = list(frame_rows[0].keys())
        w = csv.DictWriter(h, fieldnames=fields)
        w.writeheader()
        w.writerows(frame_rows)

    # Per-segment restart metrics.
    groups = defaultdict(list)
    for r in frame_rows:
        groups[r["runRoot"]].append(r)

    summary_rows = []
    for root, rr in sorted(groups.items()):
        rr.sort(key=lambda z: z["localTime"])
        t = [z["localTime"] for z in rr]
        ratio = [z["nozzleSpeedRatio"] for z in rr]
        rec = recovery_metrics(t, ratio, args.early_window)

        exit_ratio = [z["exitSpeedRatio"] for z in rr]
        rec_exit = recovery_metrics(t, exit_ratio, args.early_window)

        meta = next((m for m in segment_meta if m["runRoot"] == root), {})
        summary_rows.append({
            **meta,
            **rec,
            "exitFirstRatio": rec_exit.get("firstRatio", math.nan),
            "exitEarlyMinRatio": rec_exit.get("earlyMinRatio", math.nan),
            "exitLateMedianRatio": rec_exit.get("lateMedianRatio", math.nan),
            "exitRecoveryT90": rec_exit.get("recoveryT90", math.nan),
            "frames": len(rr),
            "localTimeStart": rr[0]["localTime"],
            "localTimeEnd": rr[-1]["localTime"],
        })

    with (out / "restart_recovery_summary.csv").open("w", newline="") as h:
        fields = list(summary_rows[0].keys())
        w = csv.DictWriter(h, fieldnames=fields)
        w.writeheader()
        w.writerows(summary_rows)

    # Compact human-readable report.
    with (out / "report.txt").open("w") as h:
        h.write("0493x24ac — Sato restart velocity/flow audit\n")
        h.write("===========================================\n\n")
        h.write(
            "Primary metric: nozzleSpeedRatio = mean(max(-uy,0)) in nozzle band / nominal Ujet\n"
        )
        h.write(
            f"Nozzle band y=[{args.nozzle_band_y0:g},{args.nozzle_band_y1:g}], "
            f"jet aperture width={args.jet_width:g}\n"
        )
        h.write(f"Early audit window = {args.early_window:g} time units\n\n")

        for r in summary_rows:
            h.write(
                f"Fr={r.get('targetFr', math.nan):.9g} "
                f"source={r.get('sourceKind','')} "
                f"root={r.get('runRoot','')}\n"
            )
            h.write(
                f"  nozzle: first={r.get('firstRatio',math.nan):.4g} "
                f"earlyMin={r.get('earlyMinRatio',math.nan):.4g} "
                f"lateMedian={r.get('lateMedianRatio',math.nan):.4g} "
                f"t90={r.get('recoveryT90',math.nan):.4g} "
                f"deficitArea={r.get('deficitArea',math.nan):.4g}\n"
            )
            h.write(
                f"  exit:   first={r.get('exitFirstRatio',math.nan):.4g} "
                f"earlyMin={r.get('exitEarlyMinRatio',math.nan):.4g} "
                f"lateMedian={r.get('exitLateMedianRatio',math.nan):.4g} "
                f"t90={r.get('exitRecoveryT90',math.nan):.4g}\n\n"
            )

    # Figure 1: all segment-local nozzle speed ratios, aligned at restart local t=0.
    fig, ax = plt.subplots(figsize=(10.5, 6.0))
    for root, rr in sorted(groups.items()):
        rr.sort(key=lambda z: z["localTime"])
        meta = next((m for m in segment_meta if m["runRoot"] == root), {})
        fr = meta.get("targetFr", math.nan)
        kind = meta.get("sourceKind", "")
        label = f"Fr={fr:g} | {kind} | {Path(root).name}"
        ax.plot(
            [z["localTime"] for z in rr],
            [z["nozzleSpeedRatio"] for z in rr],
            label=label,
        )
    ax.axhline(1.0, linestyle="--", alpha=0.6)
    ax.set_xlabel("Segment-local physical time")
    ax.set_ylabel("Nozzle mean downward speed / nominal jet speed")
    ax.set_title("Restart audit: nozzle velocity recovery")
    ax.grid(True, alpha=0.25)
    ax.legend(fontsize=7, ncol=1)
    fig.tight_layout()
    fig.savefig(out / "nozzle_speed_ratio_all_segments.png", dpi=180)
    plt.close(fig)

    # Figure 2: zoom early transient.
    fig, ax = plt.subplots(figsize=(10.5, 6.0))
    for root, rr in sorted(groups.items()):
        rr = [z for z in rr if z["localTime"] <= args.early_window]
        if not rr:
            continue
        rr.sort(key=lambda z: z["localTime"])
        meta = next((m for m in segment_meta if m["runRoot"] == root), {})
        fr = meta.get("targetFr", math.nan)
        kind = meta.get("sourceKind", "")
        label = f"Fr={fr:g} | {kind} | {Path(root).name}"
        ax.plot(
            [z["localTime"] for z in rr],
            [z["nozzleSpeedRatio"] for z in rr],
            label=label,
        )
    ax.axhline(1.0, linestyle="--", alpha=0.6)
    ax.set_xlabel("Segment-local physical time")
    ax.set_ylabel("Nozzle mean downward speed / nominal jet speed")
    ax.set_title(f"Restart audit: first {args.early_window:g} time units")
    ax.grid(True, alpha=0.25)
    ax.legend(fontsize=7, ncol=1)
    fig.tight_layout()
    fig.savefig(out / "nozzle_speed_ratio_restart_zoom.png", dpi=180)
    plt.close(fig)

    # Figure 3: exit mass-flow proxy, each segment normalized by its own late median.
    fig, ax = plt.subplots(figsize=(10.5, 6.0))
    for root, rr in sorted(groups.items()):
        rr.sort(key=lambda z: z["localTime"])
        vals = np.array([z["exitMassFlowProxy"] for z in rr], float)
        tt = np.array([z["localTime"] for z in rr], float)
        m = np.isfinite(vals)
        if np.sum(m) < 3:
            continue
        vals = vals[m]
        tt = tt[m]
        nlate = max(3, int(math.ceil(0.25 * len(vals))))
        ref = float(np.median(vals[-nlate:]))
        if not math.isfinite(ref) or ref == 0:
            continue
        meta = next((m0 for m0 in segment_meta if m0["runRoot"] == root), {})
        fr = meta.get("targetFr", math.nan)
        kind = meta.get("sourceKind", "")
        label = f"Fr={fr:g} | {kind} | {Path(root).name}"
        ax.plot(tt, vals / ref, label=label)
    ax.axhline(1.0, linestyle="--", alpha=0.6)
    ax.set_xlabel("Segment-local physical time")
    ax.set_ylabel("Exit mass-flow proxy / late-segment median")
    ax.set_title("Restart audit: exit mass-flow recovery")
    ax.grid(True, alpha=0.25)
    ax.legend(fontsize=7, ncol=1)
    fig.tight_layout()
    fig.savefig(out / "exit_mass_flow_recovery_all_segments.png", dpi=180)
    plt.close(fig)

    print(f"[0493x24ac] discovered {len(groups)} run segments")
    print(f"[0493x24ac] wrote {out/'velocity_flux_history.csv'}")
    print(f"[0493x24ac] wrote {out/'restart_recovery_summary.csv'}")
    print(f"[0493x24ac] wrote {out/'report.txt'}")
    print(f"[0493x24ac] wrote {out/'nozzle_speed_ratio_all_segments.png'}")
    print(f"[0493x24ac] wrote {out/'nozzle_speed_ratio_restart_zoom.png'}")
    print(f"[0493x24ac] wrote {out/'exit_mass_flow_recovery_all_segments.png'}")


if __name__ == "__main__":
    main()
