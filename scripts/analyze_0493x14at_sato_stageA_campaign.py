#!/usr/bin/env python3
"""Aggregate a 0493x14at Sato Stage-A campaign.

Standard library only.  The campaign is interpreted as a 2-D planar analogue:
Sato's h/D = 1.30 Fr_m' is retained as an external reference, while measured
incident Fr_m' and measured gas-pressure offset are treated as covariates.
"""
from __future__ import annotations

import argparse
import csv
import math
import statistics
from pathlib import Path


def read_csv(path):
    with Path(path).open(newline="") as f:
        return list(csv.DictReader(f))


def num(r, k, default=math.nan):
    try:
        v = float(r[k])
        return v if math.isfinite(v) else default
    except Exception:
        return default


def solve_linear(A, b):
    n = len(b)
    M = [list(map(float, A[i])) + [float(b[i])] for i in range(n)]
    for i in range(n):
        p = max(range(i, n), key=lambda r: abs(M[r][i]))
        if abs(M[p][i]) < 1e-14:
            return None
        M[i], M[p] = M[p], M[i]
        q = M[i][i]
        for j in range(i, n + 1):
            M[i][j] /= q
        for r in range(n):
            if r == i:
                continue
            q = M[r][i]
            for j in range(i, n + 1):
                M[r][j] -= q * M[i][j]
    return [M[i][n] for i in range(n)]


def fit_linear(x, y, through_origin=False):
    pts = [(a, b) for a, b in zip(x, y) if math.isfinite(a) and math.isfinite(b)]
    if len(pts) < (1 if through_origin else 2):
        return None
    if through_origin:
        den = sum(a*a for a, _ in pts)
        if den <= 0:
            return None
        slope = sum(a*b for a, b in pts) / den
        pred = [slope*a for a, _ in pts]
        intercept = 0.0
    else:
        sx = sum(a for a, _ in pts); sy = sum(b for _, b in pts)
        sxx = sum(a*a for a, _ in pts); sxy = sum(a*b for a, b in pts)
        n = len(pts); den = n*sxx - sx*sx
        if abs(den) < 1e-14:
            return None
        slope = (n*sxy - sx*sy)/den
        intercept = (sy - slope*sx)/n
        pred = [intercept + slope*a for a, _ in pts]
    yy = [b for _, b in pts]
    ym = statistics.fmean(yy)
    sse = sum((b-p)**2 for b,p in zip(yy,pred))
    sst = sum((b-ym)**2 for b in yy)
    r2 = 1.0 - sse/sst if sst > 0 else math.nan
    return dict(n=len(pts), slope=slope, intercept=intercept, r2=r2, sse=sse)


def fit_covariate(x, z, y):
    pts = [(a, c, b) for a,c,b in zip(x,z,y)
           if math.isfinite(a) and math.isfinite(c) and math.isfinite(b)]
    if len(pts) < 4:
        return None
    cols = [(a,c,1.0) for a,c,_ in pts]
    M = [[sum(v[i]*v[j] for v in cols) for j in range(3)] for i in range(3)]
    b = [sum(v[i]*yy for v,(_,_,yy) in zip(cols,pts)) for i in range(3)]
    q = solve_linear(M,b)
    if q is None:
        return None
    pred = [q[0]*a + q[1]*c + q[2] for a,c,_ in pts]
    yy = [v[2] for v in pts]
    ym = statistics.fmean(yy)
    sse = sum((aa-bb)**2 for aa,bb in zip(yy,pred))
    sst = sum((aa-ym)**2 for aa in yy)
    return dict(n=len(pts), slopeFr=q[0], slopePressure=q[1], intercept=q[2],
                r2=1-sse/sst if sst>0 else math.nan, sse=sse)


def fmt(v):
    if isinstance(v, int): return str(v)
    try:
        return f"{float(v):.12g}"
    except Exception:
        return str(v)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--campaign-root", type=Path, required=True)
    ap.add_argument("--post-start-time", type=float, default=3.0,
                    help="legacy/documentary argument; step-window summaries are authoritative")
    ap.add_argument("--analysis-start-step", type=int, default=3000)
    ap.add_argument("--analysis-end-step", type=int, default=4000)
    ap.add_argument("--expected-cases", type=int, default=8)
    a = ap.parse_args()

    summaries = []
    for p in sorted(a.campaign_root.glob("*/analysis/sato_stageA_recording_summary.csv")):
        rr = read_csv(p)
        if not rr:
            continue
        r = rr[0]
        case = p.parents[1]
        summaries.append({
            "case": case.name,
            "runRoot": str(case),
            "targetHOverD": num(r,"targetHOverD"),
            "targetModifiedFroude": num(r,"targetModifiedFroude"),
            "meanDepthOverJetWidth": num(r,"meanDepthOverJetWidth"),
            "stdDepthOverJetWidth": num(r,"stdDepthOverJetWidth"),
            "meanMeasuredModifiedFroude": num(r,"meanMeasuredModifiedFroude"),
            "stdMeasuredModifiedFroude": num(r,"stdMeasuredModifiedFroude"),
            "meanMeasuredFrOverTarget": num(r,"meanMeasuredFrOverTarget"),
            "meanIncidentGasMassDensity": num(r,"meanIncidentGasMassDensity"),
            "meanIncidentGasMeanVy": num(r,"meanIncidentGasMeanVy"),
            "meanIncidentAdvectiveStress": num(r,"meanIncidentAdvectiveStress"),
            "meanGasPressureOffsetOverRhoGd": num(r,"meanGasPressureOffsetOverRhoGd"),
            "stdGasPressureOffsetOverRhoGd": num(r,"stdGasPressureOffsetOverRhoGd"),
            "meanRelativeFarDepthOverJetWidth": num(r,"meanRelativeFarDepthOverJetWidth"),
            "meanFarFieldLevelShiftOverJetWidth": num(r,"meanFarFieldLevelShiftOverJetWidth"),
            "analysisStartStep": int(num(r,"analysisStartStep", a.analysis_start_step)),
            "analysisEndStep": int(num(r,"analysisEndStep", a.analysis_end_step)),
            "analysisSamples": int(num(r,"analysisSamples", 0)),
            "relativeDepthDriftAcrossWindow": num(r,"relativeDepthDriftAcrossWindow"),
            "relativeLateMinusEarlyHalfMean": num(r,"relativeLateMinusEarlyHalfMean"),
            "stabilityStatus": r.get("stabilityStatus", "UNKNOWN"),
            "meanSymmetryRmsRel": num(r,"meanSymmetryRmsRel"),
            "satoReferenceDepthOverD": 1.30*num(r,"targetModifiedFroude"),
        })
    if not summaries:
        raise SystemExit(f"no per-case sato_stageA_recording_summary.csv under {a.campaign_root}")
    if a.expected_cases > 0 and len(summaries) != a.expected_cases:
        raise SystemExit(f"expected {a.expected_cases} analyzed cases, found {len(summaries)}")
    bad_window = [r["case"] for r in summaries
                  if r["analysisStartStep"] != a.analysis_start_step or r["analysisEndStep"] != a.analysis_end_step]
    if bad_window:
        raise SystemExit("inconsistent per-case analysis window: " + ", ".join(bad_window))

    summaries.sort(key=lambda r:(r["targetHOverD"],r["targetModifiedFroude"]))
    outdir = a.campaign_root / "analysis_0493x14at"
    outdir.mkdir(parents=True, exist_ok=True)
    table = outdir / "campaign_summary.csv"
    with table.open("w", newline="") as f:
        w=csv.DictWriter(f, fieldnames=list(summaries[0])); w.writeheader(); w.writerows(summaries)

    groups = sorted({r["targetHOverD"] for r in summaries if math.isfinite(r["targetHOverD"])})
    fit_rows=[]
    for hd in groups + [math.nan]:
        rr = summaries if math.isnan(hd) else [r for r in summaries if r["targetHOverD"] == hd]
        label = "combined" if math.isnan(hd) else f"H/D={hd:g}"
        yt=[r["meanDepthOverJetWidth"] for r in rr]
        xt=[r["targetModifiedFroude"] for r in rr]
        xm=[r["meanMeasuredModifiedFroude"] for r in rr]
        zp=[r["meanGasPressureOffsetOverRhoGd"] for r in rr]
        for coordinate,xx in (("targetFr",xt),("measuredFr",xm)):
            fo=fit_linear(xx,yt,True); ff=fit_linear(xx,yt,False)
            fit_rows.append({"group":label,"model":f"hD=a*{coordinate}",
                             "n":fo["n"] if fo else 0,"slopeFr":fo["slope"] if fo else math.nan,
                             "slopePressure":math.nan,"intercept":0.0,
                             "r2":fo["r2"] if fo else math.nan})
            fit_rows.append({"group":label,"model":f"hD=a*{coordinate}+c",
                             "n":ff["n"] if ff else 0,"slopeFr":ff["slope"] if ff else math.nan,
                             "slopePressure":math.nan,"intercept":ff["intercept"] if ff else math.nan,
                             "r2":ff["r2"] if ff else math.nan})
        fc=fit_covariate(xm,zp,yt)
        fit_rows.append({"group":label,"model":"hD=a*measuredFr+b*dpStar+c",
                         "n":fc["n"] if fc else 0,"slopeFr":fc["slopeFr"] if fc else math.nan,
                         "slopePressure":fc["slopePressure"] if fc else math.nan,
                         "intercept":fc["intercept"] if fc else math.nan,
                         "r2":fc["r2"] if fc else math.nan})

    fits = outdir / "campaign_fits.csv"
    with fits.open("w",newline="") as f:
        w=csv.DictWriter(f,fieldnames=list(fit_rows[0]));w.writeheader();w.writerows(fit_rows)

    # Paired H/D comparison at identical nominal forcing.
    pair_rows=[]
    targets=sorted({r["targetModifiedFroude"] for r in summaries})
    if len(groups)>=2:
        h0,h1=groups[0],groups[1]
        for target in targets:
            a0=next((r for r in summaries if r["targetHOverD"]==h0 and r["targetModifiedFroude"]==target),None)
            a1=next((r for r in summaries if r["targetHOverD"]==h1 and r["targetModifiedFroude"]==target),None)
            if a0 and a1:
                y0=a0["meanDepthOverJetWidth"];y1=a1["meanDepthOverJetWidth"]
                pair_rows.append({"targetModifiedFroude":target,"hOverD0":h0,"hOverD1":h1,
                                  "depthOverD0":y0,"depthOverD1":y1,
                                  "deltaDepthOverD":y1-y0,
                                  "relativeDeltaToMean":(y1-y0)/(0.5*(y1+y0)) if (y1+y0)!=0 else math.nan,
                                  "measuredFr0":a0["meanMeasuredModifiedFroude"],
                                  "measuredFr1":a1["meanMeasuredModifiedFroude"],
                                  "dpStar0":a0["meanGasPressureOffsetOverRhoGd"],
                                  "dpStar1":a1["meanGasPressureOffsetOverRhoGd"]})
    pair_path=outdir/"height_pair_comparison.csv"
    if pair_rows:
        with pair_path.open("w",newline="") as f:
            w=csv.DictWriter(f,fieldnames=list(pair_rows[0]));w.writeheader();w.writerows(pair_rows)

    report=outdir/"campaign_report.txt"
    with report.open("w") as f:
        f.write("0493x14at — Sato Stage-A planar analogue campaign\n")
        f.write("=================================================\n\n")
        f.write("Interpretation contract\n")
        f.write("-----------------------\n")
        f.write("Primary test: linearity of h/D with measured Fr_m' below the Sato critical value 1.17.\n")
        f.write("Primary h is referenced to the INITIAL bath level, as in the Sato plunging-depth definition.\n")
        f.write("etaFar-etaMin is retained only as a finite-bath deformation diagnostic.\n")
        f.write(f"Common averaging window: steps [{a.analysis_start_step},{a.analysis_end_step}].\n")
        f.write("The 3000:4000 protocol is empirically selected from three 6000-step H/D=0.8 sentinels; per-window drift is retained as a local oscillation/trend diagnostic, not a standalone stationarity proof.\n")
        f.write("External 3-D reference: h/D = 1.30 Fr_m'.  The coefficient 1.30 is NOT a strict 2-D pass/fail target.\n")
        f.write("Gas pressure offset is a measured generating covariate; it is not silently subtracted from h/D.\n")
        f.write("A pressure-covariate regression is reported only to diagnose whether pressure drift explains part of the response.\n\n")
        f.write("Per-case means\n")
        f.write("--------------\n")
        for r in summaries:
            f.write(f"{r['case']}: H/D={fmt(r['targetHOverD'])} Fr_target={fmt(r['targetModifiedFroude'])} "
                    f"Fr_meas={fmt(r['meanMeasuredModifiedFroude'])} h/D={fmt(r['meanDepthOverJetWidth'])} "
                    f"dp*={fmt(r['meanGasPressureOffsetOverRhoGd'])} stability={r['stabilityStatus']} "
                    f"drift={fmt(r['relativeDepthDriftAcrossWindow'])} halfDelta={fmt(r['relativeLateMinusEarlyHalfMean'])}\n")
        f.write("\nFits\n----\n")
        for r in fit_rows:
            f.write(f"{r['group']} | {r['model']} | n={r['n']} a={fmt(r['slopeFr'])} "
                    f"b={fmt(r['slopePressure'])} c={fmt(r['intercept'])} R2={fmt(r['r2'])}\n")
        stable = sum(1 for r in summaries if r["stabilityStatus"] == "PASS")
        f.write(f"\nStability: {stable}/{len(summaries)} cases PASS on the common window.\n")
        f.write("\nReference slope = 1.30\n")
        f.write("Reference critical Fr_m' = 1.17\n")
        if pair_rows:
            f.write("\nPaired H/D response\n-------------------\n")
            for r in pair_rows:
                f.write(f"Fr_target={fmt(r['targetModifiedFroude'])}: delta(h/D)={fmt(r['deltaDepthOverD'])}, "
                        f"relative={fmt(r['relativeDeltaToMean'])}\n")

    print(f"[0493x14at-campaign] summary={table}")
    print(f"[0493x14at-campaign] fits={fits}")
    print(f"[0493x14at-campaign] report={report}")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
