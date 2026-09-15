#!/usr/bin/env python3
"""0493x17c article-oriented elastic-membrane FSI qualification.

Uses only the solver's native CSV diagnostics.  No pandas dependency.
"""
from __future__ import annotations

import argparse
import csv
import math
from pathlib import Path
from typing import Dict, List, Tuple


def rows(path: Path) -> List[dict]:
    if not path.is_file():
        raise FileNotFoundError(path)
    with path.open(newline="") as f:
        return list(csv.DictReader(f))


def f(row: dict, key: str) -> float:
    return float(row[key])


def rms(vals: List[float]) -> float:
    return math.sqrt(sum(v*v for v in vals) / len(vals)) if vals else 0.0


def rel_diff(a: float, b: float, floor: float = 1.0e-300) -> float:
    return abs(a-b) / max(abs(a), abs(b), floor)


def case_metrics(run: Path) -> dict:
    out = run / "fresh" / "output"
    m = rows(out / "chi_membrane_0493x17c.csv")
    p = rows(out / "chi_penetration_0493x16l.csv")
    k = rows(out / "chi_kinetic_boundary_0493x16j.csv")
    s = rows(out / "chi_solid_dynamics_0493x16a.csv")
    nodes = rows(out / "chi_membrane_nodes_0493x17c.csv")

    finite_fields = [
        "areaRelativeChange", "perimeterRelativeChange", "maxAbsEdgeStrain",
        "stretchEnergy", "areaEnergy", "kineticEnergyBefore", "kineticEnergyAfter",
        "stabilityNumber", "loadProjectionResidualX", "loadProjectionResidualY",
        "internalForceSumX", "internalForceSumY",
    ]
    finite = all(math.isfinite(f(r, key)) for r in m for key in finite_fields)
    max_strain = max((abs(f(r, "maxAbsEdgeStrain")) for r in m), default=0.0)
    max_area = max((abs(f(r, "areaRelativeChange")) for r in m), default=0.0)
    max_perim = max((abs(f(r, "perimeterRelativeChange")) for r in m), default=0.0)
    max_stability = max((abs(f(r, "stabilityNumber")) for r in m), default=0.0)
    max_projection_rel = 0.0
    max_internal_rel = 0.0
    times = [f(r, "time") for r in m]
    dt_guess = min((b-a for a,b in zip(times,times[1:]) if b>a), default=1.0)
    for r in m:
        rr = math.hypot(f(r, "nodeReactionImpulseX"), f(r, "nodeReactionImpulseY"))
        proj = math.hypot(f(r, "loadProjectionResidualX"), f(r, "loadProjectionResidualY"))
        max_projection_rel = max(max_projection_rel, proj / max(1.0, rr))
        fint = math.hypot(f(r, "internalForceSumX"), f(r, "internalForceSumY"))
        # Compare net internal force to the external force scale from this step.
        dt_force_scale = max(1.0, rr / max(dt_guess, 1.0e-300))
        max_internal_rel = max(max_internal_rel, fint / dt_force_scale)

    max_action_rel = 0.0
    for r in s:
        res = math.hypot(f(r, "actionReactionResidualX"), f(r, "actionReactionResidualY"))
        ext = math.hypot(f(r, "totalFluidImpulseX"), f(r, "totalFluidImpulseY"))
        max_action_rel = max(max_action_rel, res / max(1.0, ext))

    max_strict = max((int(float(r["strictInsideParticles"])) for r in p), default=0)
    max_depth = max((f(r, "maxPenetrationCells") for r in p), default=0.0)
    collisions = [f(r, "collisions") for r in k]
    reaction_mag = [math.hypot(f(r, "nodeReactionImpulseX"), f(r, "nodeReactionImpulseY")) for r in m]

    snapshots: Dict[int, List[Tuple[int,float,float,float,float,float,float]]] = {}
    for r in nodes:
        st = int(r["step"])
        snapshots.setdefault(st, []).append((
            int(r["node"]), f(r,"x"), f(r,"y"), f(r,"vx"), f(r,"vy"), f(r,"x0"), f(r,"y0")
        ))
    for st in snapshots:
        snapshots[st].sort(key=lambda z: z[0])

    return {
        "rows": len(m),
        "nodes": int(m[0]["nodeCount"]) if m else 0,
        "finite": finite,
        "maxStrain": max_strain,
        "maxAreaRel": max_area,
        "maxPerimeterRel": max_perim,
        "maxStability": max_stability,
        "maxProjectionRel": max_projection_rel,
        "maxInternalForceRel": max_internal_rel,
        "maxActionReactionRel": max_action_rel,
        "maxStrictInside": max_strict,
        "maxPenetrationCells": max_depth,
        "collisionMean": sum(collisions)/len(collisions) if collisions else 0.0,
        "reactionRms": rms(reaction_mag),
        "areaHistory": {int(r["step"]): f(r,"areaRelativeChange") for r in m},
        "perimeterHistory": {int(r["step"]): f(r,"perimeterRelativeChange") for r in m},
        "strainHistory": {int(r["step"]): f(r,"maxAbsEdgeStrain") for r in m},
        "snapshots": snapshots,
    }


def max_common_abs_diff(a: Dict[int,float], b: Dict[int,float]) -> float:
    ks = sorted(set(a) & set(b))
    return max((abs(a[k]-b[k]) for k in ks), default=float("inf"))


def centered_shape_rms(a, b) -> float:
    if not a or not b or len(a) != len(b):
        return float("inf")
    if [z[0] for z in a] != [z[0] for z in b]:
        return float("inf")
    ax = sum(z[1] for z in a)/len(a); ay = sum(z[2] for z in a)/len(a)
    bx = sum(z[1] for z in b)/len(b); by = sum(z[2] for z in b)/len(b)
    scale = math.sqrt(sum((z[5]-sum(q[5] for q in a)/len(a))**2 +
                          (z[6]-sum(q[6] for q in a)/len(a))**2 for z in a)/len(a))
    d2 = sum(((za[1]-ax)-(zb[1]-bx))**2 + ((za[2]-ay)-(zb[2]-by))**2
             for za,zb in zip(a,b))/len(a)
    return math.sqrt(d2)/max(scale,1.0e-12)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default="runs/0493x17c_membrane_fsi_qualification")
    ap.add_argument("--output", default="")
    args = ap.parse_args()
    root = Path(args.root)
    rest = case_metrics(root / "rest")
    boost = case_metrics(root / "boost")

    common_snaps = sorted(set(rest["snapshots"]) & set(boost["snapshots"]))
    final_shape = centered_shape_rms(
        rest["snapshots"].get(common_snaps[-1], []) if common_snaps else [],
        boost["snapshots"].get(common_snaps[-1], []) if common_snaps else [])
    area_diff = max_common_abs_diff(rest["areaHistory"], boost["areaHistory"])
    perim_diff = max_common_abs_diff(rest["perimeterHistory"], boost["perimeterHistory"])
    strain_diff = max_common_abs_diff(rest["strainHistory"], boost["strainHistory"])
    collision_rel = rel_diff(rest["collisionMean"], boost["collisionMean"], 1.0)
    reaction_rel = rel_diff(rest["reactionRms"], boost["reactionRms"], 1.0)

    penetration_pass = all(c["maxStrictInside"] == 0 and c["maxPenetrationCells"] <= 1.0e-6
                           for c in (rest, boost))
    mechanics_pass = all(c["finite"] and c["maxStability"] <= 0.35 and
                         c["maxStrain"] <= 0.50 and c["maxAreaRel"] <= 0.25
                         for c in (rest, boost))
    closure_pass = all(c["maxProjectionRel"] <= 1.0e-12 and
                       c["maxActionReactionRel"] <= 1.0e-10 and
                       c["maxInternalForceRel"] <= 1.0e-10 for c in (rest, boost))
    galilean_pass = (area_diff <= 0.01 and perim_diff <= 0.01 and strain_diff <= 0.02 and
                     final_shape <= 0.02 and collision_rel <= 0.03 and reaction_rel <= 0.10)
    # An article demonstrator should actually deform; otherwise numerical PASS
    # is not enough to demonstrate the capability.
    deformation = max(rest["maxStrain"], boost["maxStrain"])
    demo_pass = deformation >= 5.0e-4

    status = "PASS" if penetration_pass and mechanics_pass and closure_pass and galilean_pass and demo_pass else "REVIEW"
    text = []
    text.append("0493x17c elastic-Lagrangian-membrane FSI qualification")
    text.append(f"status={status}")
    text.append("purpose=scientific-article-capability-demonstrator")
    text.append("userGeometryInput=chi")
    text.append("materialBoundary=initial_chi_0.5_contour")
    text.append("geometryAuthorityAfterInitialization=Lagrangian_nodes")
    text.append("mechanics=edge_spring+area_penalty+edge_dashpot")
    text.append("fluidSolidCoupling=direct_impact_linear_edge_shape_functions")
    text.append(f"zeroPenetration={ 'PASS' if penetration_pass else 'FAIL' }")
    text.append(f"mechanicalStability={ 'PASS' if mechanics_pass else 'REVIEW' }")
    text.append(f"loadAndMomentumClosure={ 'PASS' if closure_pass else 'FAIL' }")
    text.append(f"galileanCoupledResponse={ 'PASS' if galilean_pass else 'REVIEW' }")
    text.append(f"nontrivialDeformationDemo={ 'PASS' if demo_pass else 'REVIEW' }")
    text.append(f"galileanAreaHistoryMaxAbsDifference={area_diff:.17g}")
    text.append(f"galileanPerimeterHistoryMaxAbsDifference={perim_diff:.17g}")
    text.append(f"galileanStrainHistoryMaxAbsDifference={strain_diff:.17g}")
    text.append(f"galileanFinalCenteredShapeRmsRelative={final_shape:.17g}")
    text.append(f"galileanCollisionRateRelativeDifference={collision_rel:.17g}")
    text.append(f"galileanReactionRmsRelativeDifference={reaction_rel:.17g}")
    for name,c in (("rest",rest),("boost",boost)):
        text.append("")
        text.append(f"[{name}]")
        for key in ("rows","nodes","maxStrictInside","maxPenetrationCells","maxStrain",
                    "maxAreaRel","maxPerimeterRel","maxStability","maxProjectionRel",
                    "maxInternalForceRel","maxActionReactionRel","collisionMean","reactionRms"):
            text.append(f"{key}={c[key]}")

    output = Path(args.output) if args.output else root / "analysis" / "summary_0493x17c.txt"
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text("\n".join(text)+"\n", encoding="utf-8")
    print("\n".join(text))
    return 0 if status == "PASS" else 3


if __name__ == "__main__":
    raise SystemExit(main())
