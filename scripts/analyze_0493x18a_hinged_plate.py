#!/usr/bin/env python3
import argparse
import csv
import math
from pathlib import Path
from statistics import mean, pstdev


def f(row, key, default=0.0):
    try:
        return float(row.get(key, default))
    except (TypeError, ValueError):
        return float(default)


def parse_meta(path):
    out = {}
    if not path.exists():
        return out
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        if "=" in line:
            k, v = line.split("=", 1)
            out[k.strip()] = v.strip()
    return out


def resolve(root):
    root = root.resolve()
    candidates = [root, root / "fresh"]
    for run in candidates:
        csv_path = run / "output" / "chi_hinged_plate_0493x18a.csv"
        if csv_path.exists():
            return run, csv_path
    raise FileNotFoundError(
        f"cannot find output/chi_hinged_plate_0493x18a.csv under {root} or {root/'fresh'}"
    )


def main():
    ap = argparse.ArgumentParser(description="Analyze 0493x18a one-DOF hinged plate FSI")
    ap.add_argument("--root", required=True, help="run root, with or without /fresh")
    ap.add_argument("--late-fraction", type=float, default=0.25,
                    help="fraction of final samples used for late-time averages (default 0.25)")
    args = ap.parse_args()

    if not (0.05 <= args.late_fraction <= 0.8):
        raise SystemExit("--late-fraction must be in [0.05,0.8]")

    run, path = resolve(Path(args.root))
    with path.open(newline="", encoding="utf-8") as fh:
        rows = list(csv.DictReader(fh))
    if len(rows) < 2:
        raise SystemExit(f"not enough hinged-plate rows in {path}")

    # 0493x18 penetration audit (observation only; does not change the legacy
    # one-DOF qualification status below).
    pen_path = run / "output" / "chi_penetration_0493x16l.csv"
    kin_path = run / "output" / "chi_kinetic_boundary_0493x16j.csv"
    pen_rows = []
    kin_rows = []
    if pen_path.exists():
        with pen_path.open(newline="", encoding="utf-8") as fh:
            pen_rows = list(csv.DictReader(fh))
    if kin_path.exists():
        with kin_path.open(newline="", encoding="utf-8") as fh:
            kin_rows = list(csv.DictReader(fh))

    meta = parse_meta(run / "run_meta_0493x18a_hinged_plate.txt")
    dt = float(meta.get("dt", f(rows[-1], "time") - f(rows[-2], "time")))
    flow_u = float(meta.get("flowUx", "nan"))
    nlate = max(2, int(math.ceil(args.late_fraction * len(rows))))
    late = rows[-nlate:]

    theta = [f(r, "theta") for r in rows]
    theta_deg = [f(r, "thetaDeg", t * 180.0 / math.pi) for r, t in zip(rows, theta)]
    omega = [f(r, "omegaAfter") for r in rows]
    hydro_torque = [f(r, "hydroTorqueImpulse") / dt for r in rows]
    gravity_torque = [f(r, "gravityTorque") for r in rows]
    damping_torque = [f(r, "dampingTorque") for r in rows]
    torque_balance = [a+b+c for a, b, c in zip(hydro_torque, gravity_torque, damping_torque)]
    angular_residual = [abs(f(r, "angularBalanceResidual")) for r in rows]
    projection_abs = [math.hypot(f(r, "loadProjectionResidualX"), f(r, "loadProjectionResidualY")) for r in rows]
    reaction_scale = [1.0 + math.hypot(f(r, "hydroImpulseX"), f(r, "hydroImpulseY")) for r in rows]
    projection_rel = [a/s for a, s in zip(projection_abs, reaction_scale)]

    late_theta = theta_deg[-nlate:]
    late_omega = omega[-nlate:]
    late_hydro = hydro_torque[-nlate:]
    late_gravity = gravity_torque[-nlate:]
    late_damping = damping_torque[-nlate:]
    late_balance = torque_balance[-nlate:]

    half = max(1, nlate // 2)
    late_a = late_theta[:half]
    late_b = late_theta[-half:]
    drift_deg = mean(late_b) - mean(late_a)
    theta_mean = mean(late_theta)
    theta_std = pstdev(late_theta) if len(late_theta) > 1 else 0.0
    omega_rms = math.sqrt(mean([x*x for x in late_omega]))
    balance_rms = math.sqrt(mean([x*x for x in late_balance]))
    torque_scale = 1.0 + mean([abs(a)+abs(b)+abs(c) for a,b,c in zip(late_hydro,late_gravity,late_damping)])
    balance_rel = balance_rms / torque_scale

    finite = all(math.isfinite(x) for seq in [theta_deg, omega, hydro_torque, gravity_torque, damping_torque] for x in seq)
    node_set = sorted({int(float(r.get("nodeCount", 0))) for r in rows})
    edge_set = sorted({int(float(r.get("edgeCount", 0))) for r in rows})
    load_projection_pass = max(projection_rel) < 1.0e-9
    angular_balance_pass = max(angular_residual) < 1.0e-10 * (1.0 + max(abs(x) for x in [f(r,"hydroTorqueImpulse") for r in rows]))
    angle_response = (not math.isfinite(flow_u)) or abs(flow_u) < 1.0e-12 or abs(theta_mean) >= 0.5
    structure_pass = finite and len(node_set) == 1 and len(edge_set) == 1 and load_projection_pass and angular_balance_pass
    status = "PASS" if structure_pass and angle_response else "REVIEW"

    # Penetration is reported descriptively, not added as a new qualification
    # gate here.  Use analyze_0493x18_penetration.py for the detailed event list.
    if pen_rows:
        p_sampled = [int(float(r.get("sampledParticles", 0) or 0)) for r in pen_rows]
        p_raw = [int(float(r.get("rawInsideParticles", 0) or 0)) for r in pen_rows]
        p_strict = [int(float(r.get("strictInsideParticles", 0) or 0)) for r in pen_rows]
        p_depth = [f(r, "maxPenetrationCells") for r in pen_rows]
        p_frac = [s/max(1,n) for s,n in zip(p_strict,p_sampled)]
        pen_max_strict=max(p_strict); pen_max_raw=max(p_raw); pen_max_depth=max(p_depth)
        pen_steps=sum(1 for x in p_strict if x>0)
        pen_sum=sum(p_strict); pen_cov_min=min(p_sampled); pen_cov_max=max(p_sampled)
        pen_max_frac=max(p_frac)
        if pen_max_strict==0 and pen_max_depth<=1e-6:
            pen_class="CLEAN"
        elif pen_max_strict<=10 and pen_max_frac<=1e-5 and pen_max_depth<=0.25 and pen_steps<=max(1,int(math.ceil(0.10*len(pen_rows)))):
            pen_class="SPARSE_FEW_PARTICLES"
        else:
            pen_class="PENETRATION_PRESENT"
    else:
        pen_max_strict=pen_max_raw=pen_steps=pen_sum=pen_cov_min=pen_cov_max=0
        pen_max_depth=pen_max_frac=float("nan")
        pen_class="NOT_AVAILABLE"
    kin_second=sum(int(float(r.get("secondCollisions",0) or 0)) for r in kin_rows)
    kin_third=sum(int(float(r.get("thirdCollisions",0) or 0)) for r in kin_rows)

    # A deliberately descriptive settling flag, not a hard qualification gate.
    if abs(drift_deg) < max(0.2, 0.02 * max(1.0, abs(theta_mean))) and omega_rms < 0.2:
        equilibrium = "SETTLED"
    else:
        equilibrium = "TRANSIENT"

    values = {
        "status": status,
        "equilibriumStatus": equilibrium,
        "samples": len(rows),
        "lateSamples": nlate,
        "flowUx": flow_u,
        "dt": dt,
        "nodeCountSet": node_set,
        "edgeCountSet": edge_set,
        "finalThetaDeg": theta_deg[-1],
        "lateMeanThetaDeg": theta_mean,
        "lateStdThetaDeg": theta_std,
        "lateDriftThetaDeg": drift_deg,
        "maxAbsThetaDeg": max(abs(x) for x in theta_deg),
        "finalOmega": omega[-1],
        "lateOmegaRms": omega_rms,
        "lateMeanHydroTorque": mean(late_hydro),
        "lateMeanGravityTorque": mean(late_gravity),
        "lateMeanDampingTorque": mean(late_damping),
        "lateTorqueBalanceRms": balance_rms,
        "lateTorqueBalanceRelative": balance_rel,
        "maxAngularBalanceResidual": max(angular_residual),
        "maxLoadProjectionRelative": max(projection_rel),
        "penetrationStatus": pen_class,
        "penetrationSamples": len(pen_rows),
        "penetrationMinSampledParticles": pen_cov_min,
        "penetrationMaxSampledParticles": pen_cov_max,
        "maxRawInsideParticles": pen_max_raw,
        "maxStrictInsideParticles": pen_max_strict,
        "maxStrictInsideFraction": pen_max_frac,
        "samplesWithStrictInside": pen_steps,
        "sumStrictParticleSamples": pen_sum,
        "maxPenetrationCells": pen_max_depth,
        "totalSecondCollisionsAtAuditSamples": kin_second,
        "totalThirdCollisionsAtAuditSamples": kin_third,
    }

    lines = ["0493x18a hinged plate one-DOF validation"]
    for k, v in values.items():
        lines.append(f"{k}={v}")
    lines += [
        "",
        "[criteria]",
        f"finite_state={'PASS' if finite else 'FAIL'}",
        f"node_count_constant={'PASS' if len(node_set)==1 else 'FAIL'}",
        f"edge_count_constant={'PASS' if len(edge_set)==1 else 'FAIL'}",
        f"load_projection_closure={'PASS' if load_projection_pass else 'FAIL'}",
        f"angular_balance_closure={'PASS' if angular_balance_pass else 'FAIL'}",
        f"angle_response_present={'PASS' if angle_response else 'FAIL'}",
        "",
        "[penetration_observation]",
        f"penetration_diagnostic_present={'PASS' if pen_rows else 'FAIL'}",
        f"particle_coverage_constant={'PASS' if (pen_rows and pen_cov_min==pen_cov_max and pen_cov_min>0) else 'FAIL'}",
        f"zero_strict_penetration={'PASS' if (pen_rows and pen_max_strict==0 and pen_max_depth<=1e-6) else 'FAIL'}",
        "direct_through_crossing_counter=NOT_AVAILABLE",
    ]

    text = "\n".join(lines) + "\n"
    print(text, end="")
    outdir = run.parent / "analysis" if run.name == "fresh" else run / "analysis"
    outdir.mkdir(parents=True, exist_ok=True)
    summary = outdir / "summary_0493x18a_hinged_plate.txt"
    summary.write_text(text, encoding="utf-8")
    print(f"[0493x18a] summary={summary}")


if __name__ == "__main__":
    main()
