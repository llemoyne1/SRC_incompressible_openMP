#!/usr/bin/env python3
"""0493x21a — strict one-radius static capillary pilot analysis (stdlib only).

This analyzer does not alter or reinterpret solver physics.  It consumes the
existing x9e/x9r diagnostics produced through the x12yl static Young-Laplace
calibrator and answers whether one well-resolved R/h=64 paired drop is stable
enough to justify a multi-radius campaign.
"""
from __future__ import annotations
import argparse, csv, math, statistics
from pathlib import Path


def rows(path: Path):
    if not path.is_file():
        raise SystemExit(f"[0493x21a-analysis] missing {path}")
    with path.open(newline="") as f:
        out=list(csv.DictReader(f))
    if not out:
        raise SystemExit(f"[0493x21a-analysis] empty {path}")
    return out


def fval(r,k,default=math.nan):
    try:
        x=float(r[k]); return x if math.isfinite(x) else default
    except Exception: return default


def mean(v):
    q=[x for x in v if math.isfinite(x)]
    return statistics.fmean(q) if q else math.nan


def stdev(v):
    q=[x for x in v if math.isfinite(x)]
    return statistics.stdev(q) if len(q)>1 else 0.0


def lin_slope(t,y):
    q=[(a,b) for a,b in zip(t,y) if math.isfinite(a) and math.isfinite(b)]
    if len(q)<2: return math.nan
    tm=statistics.fmean(a for a,_ in q); ym=statistics.fmean(b for _,b in q)
    den=sum((a-tm)**2 for a,_ in q)
    return sum((a-tm)*(b-ym) for a,b in q)/den if den>0 else 0.0


def drift_metric(t,y):
    q=[(a,b) for a,b in zip(t,y) if math.isfinite(a) and math.isfinite(b)]
    if len(q)<6: return math.inf
    tt=[a for a,_ in q]; yy=[b for _,b in q]
    ym=statistics.fmean(yy); scale=max(abs(ym),1e-30)
    slope=lin_slope(tt,yy)
    linear=abs(slope)*(tt[-1]-tt[0])/scale if math.isfinite(slope) else math.inf
    n=max(2,len(yy)//3)
    edge=abs(statistics.fmean(yy[:n])-statistics.fmean(yy[-n:]))/scale
    return max(linear,edge)


def by_step(rr):
    out={}
    for r in rr:
        try:s=int(float(r["step"]))
        except Exception: continue
        out[s]=r
    return out


def common_pressure(active,base):
    a=by_step(active); b=by_step(base); ss=sorted(set(a)&set(b))
    out=[]
    for s in ss:
        ar,br=a[s],b[s]
        out.append({
            "step":s, "time":fval(ar,"time"),
            "r_eff":fval(ar,"effectiveRadius"),
            "alpha_area":fval(ar,"alphaArea"),
            "kappa":fval(ar,"curvatureMean"),
            "kappa_std":fval(ar,"curvatureStd"),
            "p_jump_active":fval(ar,"measuredPressureJump"),
            "p_jump_base":fval(br,"measuredPressureJump"),
            "dp_cap":fval(ar,"measuredPressureJump")-fval(br,"measuredPressureJump"),
            "pL":fval(ar,"liquidProjectionPressureGaugeMean"),
            "pG":fval(ar,"gasEosPressureGaugeMean"),
        })
    if len(out)<20:
        raise SystemExit(f"[0493x21a-analysis] too few common pressure samples: {len(out)}")
    return out


def detect_plateau(series):
    n=len(series)
    # Earliest acceptable tail is preferred; no arbitrary fixed tail is forced.
    limits=(0.30,0.40,0.50,0.60,0.70)
    last=None
    for frac in limits:
        i=min(n-1,max(0,int(math.floor(frac*n))))
        q=series[i:]
        if len(q)<20: continue
        t=[r["time"] for r in q]
        metrics={
            "r_eff":drift_metric(t,[r["r_eff"] for r in q]),
            "kappa":drift_metric(t,[r["kappa"] for r in q]),
            "dp_cap":drift_metric(t,[r["dp_cap"] for r in q]),
            "alpha_area":drift_metric(t,[r["alpha_area"] for r in q]),
        }
        last=(i,q,metrics)
        if metrics["r_eff"]<=0.01 and metrics["kappa"]<=0.05 and metrics["dp_cap"]<=0.10 and metrics["alpha_area"]<=0.02:
            return True,i,q,metrics
    if last is None:
        i=max(0,n-20); q=series[i:]
        t=[r["time"] for r in q]
        last=(i,q,{k:math.inf for k in ("r_eff","kappa","dp_cap","alpha_area")})
    i,q,m=last
    return False,i,q,m


def select_step_window(rr,s0,s1):
    out=[]
    for r in rr:
        try:s=int(float(r["step"]))
        except Exception: continue
        if s0<=s<=s1: out.append(r)
    return out


def find_mass_series(run: Path):
    # Prefer a true total-mass column. Static x12yl drops contain liquid plus
    # inactive/vacuum gas, so system total mass is a valid liquid-mass guard.
    preferred=[run/"output/summary_runtime.csv"]
    preferred += sorted((run/"output").glob("*species*runtime*.csv"))
    preferred += sorted((run/"output").glob("*.csv"))
    seen=set()
    keys=("totalMass","fluidMass","liquidMass","totalFluidMass")
    for p in preferred:
        if p in seen or not p.is_file(): continue
        seen.add(p)
        try: rr=rows(p)
        except SystemExit: continue
        if not rr: continue
        header=rr[0].keys()
        key=next((k for k in keys if k in header),None)
        if not key: continue
        vals=[]
        for r in rr:
            x=fval(r,key)
            if math.isfinite(x): vals.append(x)
        if len(vals)>=2 and abs(vals[0])>0:
            return str(p),key,vals[0],vals[-1],(vals[-1]-vals[0])/vals[0]
    return "","",math.nan,math.nan,math.nan


def limiter_max(run: Path, s0, s1):
    p=run/"output/cuda_surface_tension_limiter_0493x9r.csv"
    if not p.is_file(): return math.nan
    q=select_step_window(rows(p),s0,s1)
    vals=[fval(r,"clipFraction",0.0) for r in q]
    return max(vals) if vals else math.nan


def velocity_metrics(run: Path,s0,s1):
    p=run/"output/cuda_static_drop_velocity_0493x9e.csv"
    rr=select_step_window(rows(p),s0,s1)
    if not rr: raise SystemExit(f"[0493x21a-analysis] no velocity rows in plateau: {p}")
    return {
        "U_sp_rms":mean(fval(r,"interfaceSpeedRms") for r in rr),
        "U_sp_fluct_rms":mean(fval(r,"interfaceFluctuationRms") for r in rr),
        "U_sp_max":max(fval(r,"interfaceSpeedMax") for r in rr),
        "liquid_speed_rms":mean(fval(r,"liquidSpeedRms") for r in rr),
        "liquid_mean_vx":mean(fval(r,"liquidMeanVx") for r in rr),
        "liquid_mean_vy":mean(fval(r,"liquidMeanVy") for r in rr),
    }


def write_csv(path,d):
    with path.open("w",newline="") as f:
        w=csv.DictWriter(f,fieldnames=list(d.keys())); w.writeheader(); w.writerow(d)


def self_test():
    t=[float(i) for i in range(100)]
    y=[2.0+1e-5*math.sin(i) for i in range(100)]
    assert drift_metric(t,y)<1e-3
    y2=[2.0+0.01*i for i in range(100)]
    assert drift_metric(t,y2)>0.2
    print("[0493x21a-analysis] self-test PASS")


def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("--campaign-root",type=Path)
    ap.add_argument("--self-test",action="store_true")
    a=ap.parse_args()
    if a.self_test:
        self_test(); return
    if a.campaign_root is None: raise SystemExit("--campaign-root required")
    root=a.campaign_root
    manifest=rows(root/"manifest_0493x12yl.csv")
    if len(manifest)!=2:
        raise SystemExit(f"[0493x21a-analysis] expected exactly 2 manifest rows, got {len(manifest)}")
    act=[r for r in manifest if float(r["sigma"])>0]
    bas=[r for r in manifest if abs(float(r["sigma"]))<1e-15]
    if len(act)!=1 or len(bas)!=1: raise SystemExit("[0493x21a-analysis] expected one active + one baseline")
    ar,br=act[0],bas[0]
    if ar["seed"]!=br["seed"] or ar["r_cells"]!=br["r_cells"]:
        raise SystemExit("[0493x21a-analysis] active/baseline pair mismatch")
    rc=float(ar["r_cells"]); sigma=float(ar["sigma_declared"]); seed=int(ar["seed"])
    if abs(rc-64.0)>1e-12 or abs(sigma-10000.0)>1e-9:
        raise SystemExit(f"[0493x21a-analysis] unexpected pilot rc={rc} sigma={sigma}")
    active_run=Path(ar["run_dir"]); base_run=Path(br["run_dir"])
    pa=rows(active_run/"output/cuda_static_drop_pressure_0493x9e.csv")
    pb=rows(base_run/"output/cuda_static_drop_pressure_0493x9e.csv")
    series=common_pressure(pa,pb)
    plateau_ok,i,q,dr=detect_plateau(series)
    s0=q[0]["step"]; s1=q[-1]["step"]; t0=q[0]["time"]; t1=q[-1]["time"]

    h=float(ar["h"]); gamma=float(ar["gamma"]); mass=float(ar["liquid_mass"])
    r_eff=mean(r["r_eff"] for r in q); r_eff_std=stdev(r["r_eff"] for r in q)
    kappa=mean(r["kappa"] for r in q); kappa_time_std=stdev(r["kappa"] for r in q)
    kappa_spatial_std=mean(r["kappa_std"] for r in q)
    kappa_th=1.0/r_eff
    kappa_err=abs(abs(kappa)-kappa_th)/abs(kappa_th)
    cv_kappa=kappa_spatial_std/max(abs(kappa),1e-30)
    dp=mean(r["dp_cap"] for r in q); dp_std=stdev(r["dp_cap"] for r in q)
    sigma_eff=dp/kappa if abs(kappa)>0 else math.nan
    sigma_ratio=sigma_eff/sigma if sigma else math.nan
    sigma_rel=abs(sigma_ratio-1.0) if math.isfinite(sigma_ratio) else math.inf
    pL=mean(r["pL"] for r in q); pG=mean(r["pG"] for r in q)
    area=mean(r["alpha_area"] for r in q)
    area_std=stdev(r["alpha_area"] for r in q)
    clip=limiter_max(active_run,s0,s1)
    vm=velocity_metrics(active_run,s0,s1)
    rho=gamma*mass/(h*h)
    U_sigma=math.sqrt(sigma/(rho*r_eff))
    usp_r=vm["U_sp_rms"]/U_sigma
    usp_m=vm["U_sp_max"]/U_sigma
    drift=math.hypot(vm["liquid_mean_vx"],vm["liquid_mean_vy"])
    msrc,mkey,m0,m1,mdrift=find_mass_series(active_run)

    # Working pilot policy: deliberately permissive enough for one-seed screening,
    # but strong enough to block a large campaign after gross geometric/mechanical failure.
    hard=[]; review=[]
    if not plateau_ok: hard.append("no_quasistationary_plateau")
    if kappa_err>0.20: hard.append("curvature_error_gt20pct")
    elif kappa_err>0.10: review.append("curvature_error_gt10pct")
    if sigma_rel>0.30: hard.append("sigma_eff_error_gt30pct")
    elif sigma_rel>0.15: review.append("sigma_eff_error_gt15pct")
    if math.isfinite(clip) and clip>0.01: hard.append("curvature_limiter_clip_gt1pct")
    elif math.isfinite(clip) and clip>1e-3: review.append("curvature_limiter_clip_gt0p1pct")
    if dr["r_eff"]>0.03 or dr["alpha_area"]>0.05: hard.append("geometry_drift_large")
    if usp_r>0.25 or usp_m>0.75: hard.append("spurious_velocity_large")
    elif usp_r>0.10 or usp_m>0.30: review.append("spurious_velocity_review")
    if math.isfinite(mdrift):
        if abs(mdrift)>0.01: hard.append("mass_drift_gt1pct")
        elif abs(mdrift)>1e-3: review.append("mass_drift_gt0p1pct")
    else:
        review.append("mass_series_not_found")

    status="INVALID" if hard else ("REVIEW" if review else "PASS")
    decision=("PILOT_READY_FOR_RESOLVED_RADIUS_SWEEP" if status=="PASS" else
              "PILOT_REVIEW_BEFORE_SWEEP" if status=="REVIEW" else
              "PILOT_STOP_DO_NOT_SWEEP")

    result={
        "case_id":"R64_sigma10000_seed4932101",
        "status":status,"decision":decision,"seed":seed,
        "h":h,"gamma":gamma,"particle_mass":mass,"sigma_target":sigma,
        "R_init":rc*h,"R_init_over_h":rc,"R_eff":r_eff,"R_eff_std_time":r_eff_std,
        "R_eff_over_h":r_eff/h,"alpha_area_mean":area,"alpha_area_std_time":area_std,
        "kappa_th":kappa_th,"kappa_num_mean":kappa,"kappa_num_time_std":kappa_time_std,
        "kappa_num_spatial_std_mean":kappa_spatial_std,"kappa_relative_error":kappa_err,
        "CV_kappa_spatial":cv_kappa,"p_L_active_gauge":pL,"p_G_active_gauge":pG,
        "delta_p_capillary_paired":dp,"delta_p_time_std":dp_std,
        "sigma_eff_local":sigma_eff,"sigma_eff_over_sigma":sigma_ratio,"sigma_relative_error":sigma_rel,
        "delta_p_over_sigma_kappa":dp/(sigma*kappa) if sigma*kappa else math.nan,
        "U_sigma":U_sigma,"U_sp_rms_interface":vm["U_sp_rms"],
        "U_sp_fluct_rms_interface":vm["U_sp_fluct_rms"],"U_sp_max_interface":vm["U_sp_max"],
        "U_sp_rms_over_U_sigma":usp_r,"U_sp_max_over_U_sigma":usp_m,
        "liquid_mean_drift_speed":drift,"max_tail_clip_fraction":clip,
        "mass_source":msrc,"mass_column":mkey,"mass_initial":m0,"mass_final":m1,"mass_drift":mdrift,
        "plateau_found":int(plateau_ok),"plateau_start_step":s0,"plateau_end_step":s1,
        "plateau_start_time":t0,"plateau_end_time":t1,"plateau_samples":len(q),
        "plateau_R_eff_drift":dr["r_eff"],"plateau_kappa_drift":dr["kappa"],
        "plateau_delta_p_drift":dr["dp_cap"],"plateau_alpha_area_drift":dr["alpha_area"],
        "hard_flags":";".join(hard),"review_flags":";".join(review),
        "active_run_dir":str(active_run),"baseline_run_dir":str(base_run),
    }
    out=root/"pilot_analysis"; out.mkdir(parents=True,exist_ok=True)
    write_csv(out/"capillary_pilot_realization_0493x21a.csv",result)
    with (out/"capillary_pilot_timeseries_0493x21a.csv").open("w",newline="") as f:
        fields=list(series[0].keys())+ ["in_plateau"]
        w=csv.DictWriter(f,fieldnames=fields); w.writeheader()
        for r in series:
            z=dict(r); z["in_plateau"]=int(s0<=r["step"]<=s1); w.writerow(z)
    lines=[
        "===== 0493x21a STATIC CAPILLARY PILOT =====",
        f"status={status}",f"decision={decision}",
        f"R_init/h={rc:.6g} R_eff/h={r_eff/h:.9g} x12a_Rc/h=25.2982212813 cutoff_Rmin/h=4",
        f"plateau={plateau_ok} steps={s0}..{s1} samples={len(q)} Rdrift={dr['r_eff']:.6g} kappadrift={dr['kappa']:.6g} dpdrift={dr['dp_cap']:.6g} areaDrift={dr['alpha_area']:.6g}",
        f"kappa_th={kappa_th:.12g} kappa_num={kappa:.12g} E_kappa={kappa_err:.6g} CV_kappa_spatial={cv_kappa:.6g}",
        f"delta_p_paired={dp:.12g} sigma_target={sigma:.12g} sigma_eff={sigma_eff:.12g} sigma_eff/sigma={sigma_ratio:.9g}",
        f"U_sigma={U_sigma:.12g} UspRms={vm['U_sp_rms']:.12g} UspMax={vm['U_sp_max']:.12g} UspRms/U_sigma={usp_r:.6g} UspMax/U_sigma={usp_m:.6g}",
        f"curvatureLimiterMaxClip={clip:.6g}",
        f"massSource={msrc or 'NOT_FOUND'} massDrift={mdrift if math.isfinite(mdrift) else 'NA'}",
        f"hardFlags={';'.join(hard) if hard else 'NONE'}",
        f"reviewFlags={';'.join(review) if review else 'NONE'}",
        "interpretation=paired pressure increment uses solved-Q6 pressure diagnostic; kappa is production p3 curvature; spurious velocity is x9e interface-cell velocity.",
    ]
    (out/"capillary_pilot_decision_0493x21a.txt").write_text("\n".join(lines)+"\n")
    print("\n".join(lines))
    print(f"[0493x21a-analysis] outputs={out}")

if __name__=="__main__": main()
