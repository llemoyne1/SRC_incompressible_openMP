#!/usr/bin/env python3
"""0493x14at: dense Sato Stage-A analysis from liquid-filtered recordings.

Standard library only; no pandas/scipy.

Current campaign recording contract (from livevis_control.kv):
  particleTypeFilter = 1 (liquid)
  fields = rho, ux, uy
  recordEvery = 100

The dense liquid rho field is used for the interface/cavity history.  Gas-core
quantities are taken from the sparse particle-state analyzer and aligned to the
dense frames.  Species-resolved rho1/rho2/uy recordings remain supported if a
future control file provides them.

Primary Sato observable:
  h(t) = bathHeightInitial - etaMin(t)
not etaFar(t)-etaMin(t).  The latter is retained as a diagnostic because the
finite 2-D bath can develop a global far-field level shift.
"""
from __future__ import annotations

import argparse
import csv
import math
import statistics
import sys
from array import array
from pathlib import Path


def read_csv(path: Path):
    with path.open(newline="") as f:
        return list(csv.DictReader(f))


def f32(path: Path, n: int):
    a = array("f")
    with path.open("rb") as f:
        a.fromfile(f, n)
    if len(a) != n:
        raise RuntimeError(f"{path}: expected {n} float32 values, got {len(a)}")
    if sys.byteorder == "big":
        a.byteswap()
    return a


def finite_mean(vals):
    q = [float(v) for v in vals if math.isfinite(float(v))]
    return statistics.fmean(q) if q else math.nan


def finite_std(vals):
    q = [float(v) for v in vals if math.isfinite(float(v))]
    return statistics.stdev(q) if len(q) > 1 else (0.0 if q else math.nan)


def median(vals):
    q = [float(v) for v in vals if math.isfinite(float(v))]
    return statistics.median(q) if q else math.nan


def smooth_cross(alpha, nx, ny, lam=0.125):
    out = [0.0] * (nx * ny)
    for iy in range(ny):
        for ix in range(nx):
            i = iy * nx + ix
            c = alpha[i]
            w = alpha[i - 1] if ix > 0 else c
            e = alpha[i + 1] if ix + 1 < nx else c
            s = alpha[i - nx] if iy > 0 else c
            n = alpha[i + nx] if iy + 1 < ny else c
            v = c + lam * ((w-c)+(e-c)+(s-c)+(n-c))
            out[i] = min(1.0, max(0.0, v))
    return out


def surface_from_recorded_liquid_mass(rho, nx, ny, lx, ly, rho_liquid):
    dx, dy = lx / nx, ly / ny
    ref_mass = rho_liquid * dx * dy
    if ref_mass <= 0:
        raise RuntimeError("non-positive nominal liquid mass per recording cell")
    alpha = [min(1.0, max(0.0, float(v) / ref_mass)) for v in rho]
    alpha = smooth_cross(alpha, nx, ny, 0.125)
    eta = [math.nan] * nx
    for ix in range(nx):
        cross = None
        for iy in range(ny - 1):
            a0 = alpha[iy * nx + ix]
            a1 = alpha[(iy + 1) * nx + ix]
            if a0 >= 0.5 and a1 < 0.5:
                y0 = (iy + 0.5) * dy
                y1 = (iy + 1.5) * dy
                cross = y0 + (0.5-a0) * (y1-y0) / (a1-a0) if abs(a1-a0) > 1e-14 else (iy+1)*dy
        if cross is not None:
            eta[ix] = cross
    return eta


def interface_metrics(eta, lx, jet_center, jet_width, bath_height):
    nx = len(eta); dx = lx / nx
    xs = [(i + 0.5) * dx for i in range(nx)]
    far = [v for x, v in zip(xs, eta)
           if 0.08*lx < x < 0.92*lx and abs(x-jet_center) >= 3.0*jet_width]
    eta_far = median(far)
    center = [i for i,x in enumerate(xs)
              if abs(x-jet_center) <= 1.5*jet_width and math.isfinite(eta[i])]
    if not center:
        return dict(etaFar=eta_far, etaMin=math.nan,
                    depthFromInitial=math.nan, depthRelativeFar=math.nan,
                    halfDepthWidth=math.nan, symmetryRmsRel=math.nan)
    imin = min(center, key=lambda i: eta[i])
    eta_min = eta[imin]
    depth_initial = bath_height - eta_min
    depth_far = eta_far - eta_min if math.isfinite(eta_far) else math.nan
    width = math.nan
    if math.isfinite(eta_far) and depth_far > 0:
        level = eta_far - 0.5*depth_far
        mask = [math.isfinite(v) and v <= level for v in eta]
        ic = min(range(nx), key=lambda i: abs(xs[i]-jet_center))
        if mask[ic]:
            il=ir=ic
            while il>0 and mask[il-1]: il-=1
            while ir+1<nx and mask[ir+1]: ir+=1
            width = (ir-il+1)*dx
    diffs=[]
    scale=max(abs(depth_initial) if math.isfinite(depth_initial) else 0.0, dx)
    ic=min(range(nx), key=lambda i: abs(xs[i]-jet_center))
    for d in range(1, min(ic,nx-1-ic)+1):
        vl,vr=eta[ic-d],eta[ic+d]
        if math.isfinite(vl) and math.isfinite(vr) and d*dx <= 4.0*jet_width:
            diffs.append((vl-vr)**2)
    sym=math.sqrt(sum(diffs)/len(diffs))/scale if diffs else math.nan
    return dict(etaFar=eta_far, etaMin=eta_min,
                depthFromInitial=depth_initial, depthRelativeFar=depth_far,
                halfDepthWidth=width, symmetryRmsRel=sym)


def parse_manifest(path: Path):
    out={}
    if not path.exists(): return out
    for line in path.read_text(errors="replace").splitlines():
        if "=" in line:
            k,v=line.split("=",1); out[k.strip()]=v.strip()
    return out


def locate_recording_frames(run_root: Path):
    timelines=sorted((run_root/"output"/"recordings").glob("*/timeline.csv"))
    if not timelines:
        raise RuntimeError(f"{run_root}: no filtered-recording timeline.csv")
    bystep={}; manifests=[]
    for tl in timelines:
        manifests.append(parse_manifest(tl.parent/"manifest.kv"))
        for r in read_csv(tl):
            field=r.get("field","")
            if field not in {"rho","rho1","rho2","ux","uy"}: continue
            step=int(r["step"])
            ent=bystep.setdefault(step,{"step":step,"time":float(r["time"]),
                "nx":int(r["nx"]),"ny":int(r["ny"]),"files":{}})
            if (ent["nx"],ent["ny"]) != (int(r["nx"]),int(r["ny"])):
                raise RuntimeError("recording grid changed within a frame")
            ent["files"][field]=tl.parent/r["file"]
    frames=[]
    for s in sorted(bystep):
        f=bystep[s]["files"]
        if "rho" in f and "uy" in f:
            e=dict(bystep[s]); e["mode"]="liquid_rho"; frames.append(e)
        elif {"rho1","rho2","uy"}.issubset(f):
            e=dict(bystep[s]); e["mode"]="species_resolved"; frames.append(e)
    if not frames:
        raise RuntimeError("no frames containing rho+uy or rho1+rho2+uy")
    return frames, manifests


def read_pressure_history(path: Path):
    rows=read_csv(path); out=[]
    for r in rows:
        def fv(k):
            try:
                x=float(r[k]); return x if math.isfinite(x) else math.nan
            except Exception: return math.nan
        try: step=int(float(r.get("step","nan")))
        except Exception: step=-1
        try: time=float(r.get("time","nan"))
        except Exception: time=math.nan
        pref=fv("pressureReference")
        if not math.isfinite(pref): pref=fv("pressureReferencePa")
        dp=fv("pressureDeltaMean")
        pg=pref+dp if math.isfinite(pref) and math.isfinite(dp) else math.nan
        out.append((step,time,pref,dp,pg))
    p0=out[0][2] if out else math.nan
    return out,p0


def nearest_record(rows, step):
    if not rows: return None
    return min(rows, key=lambda r: abs(int(float(r.get("step",-10**12)))-step))


def nearest_pressure(rows, step, time):
    exact=[r for r in rows if r[0]==step]
    if exact: return exact[0]
    q=[r for r in rows if math.isfinite(r[1]) and math.isfinite(time)]
    return min(q,key=lambda r:abs(r[1]-time)) if q else None


def sparse_gas_history(run_root: Path):
    p=run_root/"analysis"/"indentation_history.csv"
    return read_csv(p) if p.exists() else []


def fv(row, key):
    try:
        x=float(row[key]); return x if math.isfinite(x) else math.nan
    except Exception: return math.nan


def dense_species_gas_metrics(rho1,rho2,uy,nx,ny,lx,ly,eta_far,jet_center,jet_width,
                              incident_height_over_jet,halfwidth_over_jet,thick_cells,rho_liquid):
    dx,dy=lx/nx,ly/ny
    if not math.isfinite(eta_far):
        return dict(incidentGasMassDensity=math.nan,incidentGasMeanVy=math.nan,
                    incidentLiquidMassFraction=math.nan,incidentAdvectiveStress=math.nan)
    ymid=eta_far+incident_height_over_jet*jet_width
    halfw=halfwidth_over_jet*jet_width; halfh=0.5*thick_cells*dy
    ids=[]
    for iy in range(ny):
        y=(iy+0.5)*dy
        if abs(y-ymid)>halfh: continue
        for ix in range(nx):
            x=(ix+0.5)*dx
            if abs(x-jet_center)<=halfw: ids.append(iy*nx+ix)
    if not ids:
        return dict(incidentGasMassDensity=math.nan,incidentGasMeanVy=math.nan,
                    incidentLiquidMassFraction=math.nan,incidentAdvectiveStress=math.nan)
    area=len(ids)*dx*dy
    mg=sum(max(0.0,float(rho2[i])) for i in ids)
    ml=sum(max(0.0,float(rho1[i])) for i in ids)
    vy=sum(max(0.0,float(rho2[i]))*float(uy[i]) for i in ids)/mg if mg>0 else math.nan
    rhog=mg/area if area>0 else math.nan
    frac=ml/(ml+mg) if ml+mg>0 else math.nan
    return dict(incidentGasMassDensity=rhog,incidentGasMeanVy=vy,
                incidentLiquidMassFraction=frac,
                incidentAdvectiveStress=rhog*vy*vy if math.isfinite(rhog) and math.isfinite(vy) else math.nan)


def linear_slope(x,y):
    pts=[(float(a),float(b)) for a,b in zip(x,y) if math.isfinite(float(a)) and math.isfinite(float(b))]
    if len(pts)<2: return math.nan
    xm=statistics.fmean(a for a,_ in pts); ym=statistics.fmean(b for _,b in pts)
    den=sum((a-xm)**2 for a,_ in pts)
    return sum((a-xm)*(b-ym) for a,b in pts)/den if den>0 else math.nan


def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("--run-root",type=Path,required=True)
    ap.add_argument("--Lx",type=float,required=True); ap.add_argument("--Ly",type=float,required=True)
    ap.add_argument("--rho-liquid",type=float,required=True); ap.add_argument("--gravity-abs",type=float,required=True)
    ap.add_argument("--sigma",type=float,required=True); ap.add_argument("--jet-center-x",type=float,required=True)
    ap.add_argument("--jet-width",type=float,required=True); ap.add_argument("--bath-height",type=float,required=True)
    ap.add_argument("--target-frm",type=float,required=True); ap.add_argument("--target-h-over-d",type=float,required=True)
    ap.add_argument("--analysis-start-step",type=int,default=3000)
    ap.add_argument("--analysis-end-step",type=int,default=4000)
    ap.add_argument("--incident-height-over-jet",type=float,required=True)
    ap.add_argument("--incident-half-width-over-jet",type=float,default=0.5)
    ap.add_argument("--incident-band-thickness-cells",type=float,default=4.0)
    ap.add_argument("--stability-rel-tol",type=float,default=0.05)
    a=ap.parse_args()
    if a.analysis_end_step <= a.analysis_start_step:
        raise SystemExit("analysis-end-step must exceed analysis-start-step")
    if min(a.rho_liquid,a.gravity_abs,a.sigma,a.jet_width) <= 0:
        raise SystemExit("rho-liquid, gravity-abs, sigma and jet-width must be positive")

    pressure_path=a.run_root/"output"/"cuda_phase_interface_pressure_0493x6g.csv"
    if not pressure_path.exists(): raise SystemExit(f"missing {pressure_path}")
    pressure,p_ref0=read_pressure_history(pressure_path)
    frames,manifests=locate_recording_frames(a.run_root)
    sparse=sparse_gas_history(a.run_root)
    cfrm=(math.pi/4.0)**2; hydro=a.rho_liquid*a.gravity_abs*a.jet_width; cap=a.sigma/a.jet_width
    rows=[]; modes=set()
    for fr in frames:
        nx,ny=fr["nx"],fr["ny"]; n=nx*ny; mode=fr["mode"]; modes.add(mode)
        if mode=="liquid_rho":
            rho=f32(fr["files"]["rho"],n)
            eta=surface_from_recorded_liquid_mass(rho,nx,ny,a.Lx,a.Ly,a.rho_liquid)
            gm={"incidentGasMassDensity":math.nan,"incidentGasMeanVy":math.nan,
                "incidentLiquidMassFraction":math.nan,"incidentAdvectiveStress":math.nan}
            sr=nearest_record(sparse,fr["step"])
            if sr:
                gm["incidentGasMassDensity"]=fv(sr,"incidentGasMassDensity")
                gm["incidentGasMeanVy"]=fv(sr,"incidentGasMeanVy")
                rh,vy=gm["incidentGasMassDensity"],gm["incidentGasMeanVy"]
                gm["incidentAdvectiveStress"]=rh*vy*vy if math.isfinite(rh) and math.isfinite(vy) else math.nan
        else:
            rho1=f32(fr["files"]["rho1"],n); rho2=f32(fr["files"]["rho2"],n); uy=f32(fr["files"]["uy"],n)
            eta=surface_from_recorded_liquid_mass(rho1,nx,ny,a.Lx,a.Ly,a.rho_liquid)
            # etaFar is needed for the gas probe, compute morphology first below and then gm.
            gm=None
        mm=interface_metrics(eta,a.Lx,a.jet_center_x,a.jet_width,a.bath_height)
        if mode=="species_resolved":
            gm=dense_species_gas_metrics(rho1,rho2,uy,nx,ny,a.Lx,a.Ly,mm["etaFar"],a.jet_center_x,a.jet_width,
                a.incident_height_over_jet,a.incident_half_width_over_jet,a.incident_band_thickness_cells,a.rho_liquid)
        pr=nearest_pressure(pressure,fr["step"],fr["time"]); pg=pr[4] if pr else math.nan
        dp=pg-p_ref0 if math.isfinite(pg) and math.isfinite(p_ref0) else math.nan
        rhog=gm["incidentGasMassDensity"]; vy=gm["incidentGasMeanVy"]
        frm=cfrm*rhog*vy*vy/hydro if hydro>0 and math.isfinite(rhog) and math.isfinite(vy) else math.nan
        hstar=mm["depthFromInitial"]/a.jet_width if math.isfinite(mm["depthFromInitial"]) else math.nan
        hfar=mm["depthRelativeFar"]/a.jet_width if math.isfinite(mm["depthRelativeFar"]) else math.nan
        dpstar=dp/hydro if math.isfinite(dp) else math.nan
        rows.append({
            "step":fr["step"],"time":fr["time"],"recordNx":nx,"recordNy":ny,"recordMode":mode,
            **mm,**gm,"depthOverJetWidth":hstar,"depthRelativeFarOverJetWidth":hfar,
            "targetModifiedFroude":a.target_frm,"measuredModifiedFroude":frm,
            "measuredFrOverTarget":frm/a.target_frm if a.target_frm>0 and math.isfinite(frm) else math.nan,
            "gasPressureMean":pg,"gasPressureOffsetFromInitialReference":dp,
            "gasPressureOffsetOverRhoGd":dpstar,
            "gasPressureOffsetOverSigmaOverD":dp/cap if cap>0 and math.isfinite(dp) else math.nan,
        })
    if not rows: raise SystemExit("no usable dense recording frames")

    outdir=a.run_root/"analysis"; outdir.mkdir(parents=True,exist_ok=True)
    hist=outdir/"sato_stageA_recording_history.csv"
    with hist.open("w",newline="") as f:
        w=csv.DictWriter(f,fieldnames=list(rows[0])); w.writeheader(); w.writerows(rows)

    post=[r for r in rows if a.analysis_start_step <= r["step"] <= a.analysis_end_step]
    if len(post)<5:
        raise SystemExit(f"analysis window [{a.analysis_start_step},{a.analysis_end_step}] has only {len(post)} dense samples")
    def m(k): return finite_mean([r[k] for r in post])
    def s(k): return finite_std([r[k] for r in post])
    slope=linear_slope([r["step"] for r in post],[r["depthOverJetWidth"] for r in post])
    mean_h=m("depthOverJetWidth")
    rel_drift=slope*(a.analysis_end_step-a.analysis_start_step)/mean_h if math.isfinite(slope) and mean_h!=0 else math.nan
    mid=0.5*(a.analysis_start_step+a.analysis_end_step)
    early=[r["depthOverJetWidth"] for r in post if r["step"]<=mid]
    late=[r["depthOverJetWidth"] for r in post if r["step"]>mid]
    me=finite_mean(early); ml=finite_mean(late)
    rel_half=(ml-me)/mean_h if math.isfinite(me) and math.isfinite(ml) and mean_h!=0 else math.nan
    stable=(math.isfinite(rel_drift) and math.isfinite(rel_half)
            and abs(rel_drift)<=a.stability_rel_tol and abs(rel_half)<=a.stability_rel_tol)

    particle_filters=sorted({x.get("particleTypeFilter","") for x in manifests if x.get("particleTypeFilter","")})
    summary={
        "runRoot":str(a.run_root),"analysisSource":"dense_liquid_recording+sparse_gas_alignment",
        "recordModes":"+".join(sorted(modes)),"recordParticleTypeFilter":";".join(particle_filters),
        "targetHOverD":a.target_h_over_d,"targetModifiedFroude":a.target_frm,
        "analysisStartStep":a.analysis_start_step,"analysisEndStep":a.analysis_end_step,"analysisSamples":len(post),
        "bathHeightReference":a.bath_height,
        "meanDepthOverJetWidth":mean_h,"stdDepthOverJetWidth":s("depthOverJetWidth"),
        "meanRelativeFarDepthOverJetWidth":m("depthRelativeFarOverJetWidth"),
        "meanFarFieldLevelShiftOverJetWidth":m("etaFar")/a.jet_width-a.bath_height/a.jet_width,
        "depthSlopePerStep":slope,"relativeDepthDriftAcrossWindow":rel_drift,
        "relativeLateMinusEarlyHalfMean":rel_half,"stabilityRelativeTolerance":a.stability_rel_tol,
        "stabilityStatus":"PASS" if stable else "REVIEW",
        "meanMeasuredModifiedFroude":m("measuredModifiedFroude"),"stdMeasuredModifiedFroude":s("measuredModifiedFroude"),
        "meanMeasuredFrOverTarget":m("measuredFrOverTarget"),
        "meanIncidentGasMassDensity":m("incidentGasMassDensity"),"meanIncidentGasMeanVy":m("incidentGasMeanVy"),
        "meanIncidentAdvectiveStress":m("incidentAdvectiveStress"),
        "meanGasPressureOffsetOverRhoGd":m("gasPressureOffsetOverRhoGd"),"stdGasPressureOffsetOverRhoGd":s("gasPressureOffsetOverRhoGd"),
        "meanSymmetryRmsRel":m("symmetryRmsRel"),
    }
    summary_path=outdir/"sato_stageA_recording_summary.csv"
    with summary_path.open("w",newline="") as f:
        w=csv.DictWriter(f,fieldnames=list(summary)); w.writeheader(); w.writerow(summary)
    rep=outdir/"sato_stageA_recording_report.txt"
    with rep.open("w") as f:
        f.write("0493x14at Sato Stage-A dense recording analysis\n")
        f.write("================================================\n")
        f.write("Primary depth: initial bath level - minimum interface height.\n")
        f.write("etaFar-etaMin is diagnostic only (finite-bath level shift).\n")
        f.write(f"Averaging/stability window: steps [{a.analysis_start_step},{a.analysis_end_step}].\n")
        f.write(f"Local trend diagnostic: |relative drift| and |late-early half mean| <= {a.stability_rel_tol:.6g}.\n")
        f.write("This diagnostic is not by itself a stationarity proof for an oscillatory cavity; the 3000:4000 averaging protocol was selected from three 6000-step sentinels.\n\n")
        for k,v in summary.items(): f.write(f"{k} = {v}\n")
        f.write(f"SatoStageAReference_hOverD_at_target = {1.30*a.target_frm:.12g}\n")
        f.write("SatoStageAReferenceSlope = 1.30\n")
        f.write("Coefficient 1.30 is a 3-D experimental reference, not a strict 2-D pass/fail threshold.\n")
    print(f"[0493x14at-recording] history={hist}")
    print(f"[0493x14at-recording] summary={summary_path}")
    print(f"[0493x14at-recording] window={a.analysis_start_step}:{a.analysis_end_step} n={len(post)} "
          f"h/D={mean_h:.8g} drift={rel_drift:.4g} halfDelta={rel_half:.4g} stability={summary['stabilityStatus']} "
          f"Fr_meas={summary['meanMeasuredModifiedFroude']:.8g}")
    return 0


if __name__=="__main__":
    raise SystemExit(main())
