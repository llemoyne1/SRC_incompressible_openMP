#!/usr/bin/env python3
"""Collect 0493x21c no-code shadow probes without assigning sigma_eff.

This script is deliberately diagnostic-only. It verifies pairing/integrity and
collects the first positive-step x9e observables for each same-checkpoint
sigma=target / sigma=0 restart. It does NOT use curvatureMean to qualify the
surface-tension mechanism and does NOT publish an effective sigma.

Stdlib only; no pandas/scipy.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import math
import statistics
import zipfile
from collections import defaultdict
from pathlib import Path


def rows(path: Path):
    if not path.is_file():
        raise FileNotFoundError(path)
    with path.open(newline="") as f:
        return list(csv.DictReader(f))


def f(row, key, default=math.nan):
    try:
        x = float(row.get(key, ""))
        return x if math.isfinite(x) else default
    except Exception:
        return default


def i(row, key, default=-1):
    try:
        return int(float(row.get(key, "")))
    except Exception:
        return default


def mean(xs):
    q = [x for x in xs if math.isfinite(x)]
    return statistics.fmean(q) if q else math.nan


def stdev(xs):
    q = [x for x in xs if math.isfinite(x)]
    return statistics.stdev(q) if len(q) > 1 else 0.0


def median(xs):
    q = [x for x in xs if math.isfinite(x)]
    return statistics.median(q) if q else math.nan


def sha256(path: Path):
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for b in iter(lambda: fh.read(1024 * 1024), b""):
            h.update(b)
    return h.hexdigest()


def first_positive(rs):
    q = []
    for r in rs:
        s = i(r, "step")
        if s > 0:
            q.append((s, r))
    if not q:
        raise RuntimeError("no_positive_step_x9e_row")
    q.sort(key=lambda x: x[0])
    return q[0]


def same_step_row(path: Path, step: int):
    if not path.is_file():
        return None
    rr = rows(path)
    exact = [r for r in rr if i(r, "step") == step]
    if exact:
        return exact[0]
    positive = [(i(r, "step"), r) for r in rr if i(r, "step") > 0]
    positive.sort(key=lambda z: z[0])
    return positive[0][1] if positive else None


def rel_mismatch(a, b):
    if not (math.isfinite(a) and math.isfinite(b)):
        return math.nan
    return abs(a - b) / max(abs(a), abs(b), 1e-30)


def write_csv(path: Path, data):
    if not data:
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=list(data[0].keys()))
        w.writeheader()
        w.writerows(data)


def zip_add_if(zf, path: Path, arc: str):
    if path.is_file():
        zf.write(path, arc)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--campaign-root", type=Path, required=True)
    ap.add_argument("--manifest", type=Path, required=True)
    ap.add_argument("--selected", type=Path, required=True)
    ap.add_argument("--shadow-root", type=Path, required=True)
    ap.add_argument("--out-dir", type=Path, required=True)
    ap.add_argument("--sigma", type=float, default=945.0)
    ap.add_argument("--expected-replicates", type=int, default=6)
    args = ap.parse_args()

    root = args.campaign_root
    out = args.out_dir
    out.mkdir(parents=True, exist_ok=True)

    selected_rows = rows(args.selected)
    selected = {i(r, "checkpoint_step"): r for r in selected_rows}
    manifest_rows = rows(args.manifest)

    hard = []
    groups = defaultdict(dict)
    for r in manifest_rows:
        cp = i(r, "checkpoint_step")
        rep = i(r, "replicate")
        role = r.get("role", "")
        if role not in ("active", "sigma0"):
            hard.append(f"unexpected_role_cp{cp}_rep{rep}_{role}")
            continue
        if role in groups[(cp, rep)]:
            hard.append(f"duplicate_role_cp{cp}_rep{rep}_{role}")
        groups[(cp, rep)][role] = r

    expected_pairs = len(selected) * args.expected_replicates
    pair_rows = []

    for cp in sorted(selected):
        for rep in range(args.expected_replicates):
            g = groups.get((cp, rep), {})
            if set(g) != {"active", "sigma0"}:
                hard.append(f"missing_pair_cp{cp}_rep{rep}")
                continue
            a, z = g["active"], g["sigma0"]
            if a.get("input_state_sha256") != z.get("input_state_sha256"):
                hard.append(f"manifest_input_hash_mismatch_cp{cp}_rep{rep}")
                continue
            if i(a, "seed") != i(z, "seed"):
                hard.append(f"seed_mismatch_cp{cp}_rep{rep}")
                continue

            state = Path(a["input_state"])
            if not state.is_absolute():
                state = Path.cwd() / state
            if not state.is_file():
                hard.append(f"missing_input_state_cp{cp}_rep{rep}")
                continue
            actual_sha = sha256(state)
            if actual_sha != a["input_state_sha256"]:
                hard.append(f"actual_input_hash_mismatch_cp{cp}_rep{rep}")
                continue
            sel_sha = selected[cp].get("state_sha256", "")
            if sel_sha and actual_sha != sel_sha:
                hard.append(f"selected_manifest_hash_mismatch_cp{cp}_rep{rep}")
                continue

            arun, zrun = Path(a["run_dir"]), Path(z["run_dir"])
            try:
                sa, ra = first_positive(rows(arun / "output/cuda_static_drop_pressure_0493x9e.csv"))
                sz, rz = first_positive(rows(zrun / "output/cuda_static_drop_pressure_0493x9e.csv"))
            except (FileNotFoundError, RuntimeError) as exc:
                hard.append(f"probe_x9e_missing_cp{cp}_rep{rep}_{str(exc).replace(' ','_')}")
                continue
            if sa != sz:
                hard.append(f"first_positive_step_mismatch_cp{cp}_rep{rep}_{sa}_{sz}")

            sigma_a = f(ra, "sigma")
            sigma_z = f(rz, "sigma")
            if not math.isfinite(sigma_a) or abs(sigma_a - args.sigma) > 1e-10 * max(1.0, abs(args.sigma)):
                hard.append(f"active_sigma_mismatch_cp{cp}_rep{rep}_{sigma_a}")
            if not math.isfinite(sigma_z) or abs(sigma_z) > 1e-12:
                hard.append(f"sigma0_mismatch_cp{cp}_rep{rep}_{sigma_z}")

            pa = f(ra, "measuredPressureJump")
            pz = f(rz, "measuredPressureJump")
            dp = pa - pz if math.isfinite(pa) and math.isfinite(pz) else math.nan

            rea, rez = f(ra, "effectiveRadius"), f(rz, "effectiveRadius")
            aa, az = f(ra, "alphaArea"), f(rz, "alphaArea")

            lim = same_step_row(arun / "output/cuda_surface_tension_limiter_0493x9r.csv", sa)
            clip = f(lim, "clipFraction") if lim else math.nan
            rawmax = f(lim, "capillaryKappaRawAbsMax") if lim else math.nan
            effmax = f(lim, "capillaryKappaEffectiveAbsMax") if lim else math.nan

            pair_rows.append({
                "checkpoint_step": cp,
                "replicate": rep,
                "seed": i(a, "seed"),
                "first_probe_step": sa,
                "input_state_sha256": actual_sha,
                "pressure_active": pa,
                "pressure_sigma0": pz,
                "delta_p": dp,
                "effectiveRadius_active": rea,
                "effectiveRadius_sigma0": rez,
                "radius_rel_mismatch": rel_mismatch(rea, rez),
                "alphaArea_active": aa,
                "alphaArea_sigma0": az,
                "area_rel_mismatch": rel_mismatch(aa, az),
                "equivalentCurvature_active": f(ra, "equivalentCurvature"),
                "equivalentCurvature_sigma0": f(rz, "equivalentCurvature"),
                "curvatureMean_active_raw": f(ra, "curvatureMean"),
                "curvatureMean_sigma0_raw": f(rz, "curvatureMean"),
                "curvatureStd_active_raw": f(ra, "curvatureStd"),
                "laplaceTargetCurrent_active_raw": f(ra, "laplaceTargetCurrent"),
                "crossingFaces_active": i(ra, "crossingFaces"),
                "validCurvatureFaces_active": i(ra, "validCurvatureFaces"),
                "clipFraction_active": clip,
                "capillaryKappaRawAbsMax_active": rawmax,
                "capillaryKappaEffectiveAbsMax_active": effmax,
                "run_dir_active": str(arun),
                "run_dir_sigma0": str(zrun),
            })

    if len(pair_rows) != expected_pairs:
        hard.append(f"valid_pair_count_{len(pair_rows)}_expected_{expected_pairs}")

    details_path = out / "shadow_pair_measurements_0493x21c_nocode.csv"
    write_csv(details_path, pair_rows)

    checkpoint_summary = []
    for cp in sorted(selected):
        q = [r for r in pair_rows if r["checkpoint_step"] == cp]
        dps = [r["delta_p"] for r in q]
        dm = mean(dps)
        ds = stdev(dps)
        checkpoint_summary.append({
            "checkpoint_step": cp,
            "pairs": len(q),
            "delta_p_mean": dm,
            "delta_p_std": ds,
            "delta_p_median": median(dps),
            "delta_p_cv_abs": ds / max(abs(dm), 1e-30) if math.isfinite(dm) else math.nan,
            "pressure_active_mean": mean(r["pressure_active"] for r in q),
            "pressure_sigma0_mean": mean(r["pressure_sigma0"] for r in q),
            "effectiveRadius_active_mean": mean(r["effectiveRadius_active"] for r in q),
            "radius_rel_mismatch_max": max((r["radius_rel_mismatch"] for r in q if math.isfinite(r["radius_rel_mismatch"])), default=math.nan),
            "area_rel_mismatch_max": max((r["area_rel_mismatch"] for r in q if math.isfinite(r["area_rel_mismatch"])), default=math.nan),
            "curvatureMean_active_raw_mean": mean(r["curvatureMean_active_raw"] for r in q),
            "clipFraction_active_max": max((r["clipFraction_active"] for r in q if math.isfinite(r["clipFraction_active"])), default=math.nan),
        })
    summary_path = out / "shadow_checkpoint_pressure_summary_0493x21c_nocode.csv"
    write_csv(summary_path, checkpoint_summary)

    all_dps = [r["delta_p"] for r in pair_rows]
    global_mean = mean(all_dps)
    global_std = stdev(all_dps)
    report_lines = [
        "===== 0493x21c NO-CODE SHADOW COLLECTION =====",
        f"integrityStatus={'FAIL' if hard else 'PASS'}",
        "physicsVerdict=NOT_ASSIGNED",
        "sigmaEffective=NOT_COMPUTED",
        "reason=collector intentionally avoids using raw curvatureMean as the qualification denominator",
        f"campaignRoot={root}",
        f"sigmaTarget={args.sigma:.12g}",
        f"checkpoints={len(selected)} expectedPairs={expected_pairs} collectedPairs={len(pair_rows)}",
        f"deltaPGlobalMean={global_mean:.12g}",
        f"deltaPGlobalStd={global_std:.12g}",
        f"deltaPGlobalCVAbs={(global_std/max(abs(global_mean),1e-30)) if math.isfinite(global_mean) else math.nan:.6g}",
        f"integrityFlags={';'.join(hard) if hard else 'NONE'}",
        "note=sigma0 branches are same-checkpoint probes only; no stationary sigma0 interpretation is made.",
        "note=curvatureMean/laplaceTargetCurrent are retained as raw diagnostics only, not used for a pass/fail or sigma_eff.",
    ]
    report_path = out / "shadow_collection_report_0493x21c_nocode.txt"
    report_path.write_text("\n".join(report_lines) + "\n")

    archive = out / "x21c_shadow_results_nocode.zip"
    with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED) as zf:
        zip_add_if(zf, args.selected, "selected_checkpoints_0493x21c.csv")
        zip_add_if(zf, args.manifest, "manifest_shadow_pairs_0493x21c_nocode.csv")
        zip_add_if(zf, details_path, details_path.name)
        zip_add_if(zf, summary_path, summary_path.name)
        zip_add_if(zf, report_path, report_path.name)
        trace = root / "audit/traceability_0493x21c_nocode.txt"
        zip_add_if(zf, trace, "traceability_0493x21c_nocode.txt")
        for m in manifest_rows:
            role = m.get("role", "unknown")
            cp = i(m, "checkpoint_step")
            rep = i(m, "replicate")
            rr = Path(m["run_dir"])
            prefix = f"probes/cp{cp:08d}_rep{rep:02d}_{role}"
            for rel in [
                "output/cuda_static_drop_pressure_0493x9e.csv",
                "output/cuda_surface_tension_limiter_0493x9r.csv",
                "output/cuda_surface_tension_0493x9d.csv",
                "output/summary_runtime.csv",
                "output/params_used.kv",
            ]:
                zip_add_if(zf, rr / rel, f"{prefix}/{Path(rel).name}")
            pdir = rr / "params"
            if pdir.is_dir():
                for p in sorted(pdir.glob("*.kv")):
                    zip_add_if(zf, p, f"{prefix}/params/{p.name}")

    print("\n".join(report_lines))
    print(f"pairCsv={details_path}")
    print(f"checkpointCsv={summary_path}")
    print(f"returnBundle={archive}")
    if hard:
        raise SystemExit(2)


if __name__ == "__main__":
    main()
