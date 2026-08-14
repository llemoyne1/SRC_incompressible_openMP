#!/usr/bin/env python3
from __future__ import annotations
import argparse, csv, math
from pathlib import Path

MODES=("src","src-q6","src-q6-g-f")

def fval(r,k,d=math.nan):
    try: return float(r[k])
    except Exception: return d
def ival(r,k,d=0):
    try: return int(round(float(r[k])))
    except Exception: return d
def read_csv(p):
    with p.open(newline="",encoding="utf-8") as f: return list(csv.DictReader(f))
def write_csv(p,rows):
    p.parent.mkdir(parents=True,exist_ok=True)
    if not rows: p.write_text("",encoding="utf-8"); return
    fields=[]; seen=set()
    for r in rows:
        for k in r:
            if k not in seen: fields.append(k); seen.add(k)
    with p.open("w",newline="",encoding="utf-8") as f:
        w=csv.DictWriter(f,fieldnames=fields); w.writeheader(); w.writerows(rows)
def parse_kv(p):
    out={}
    for raw in p.read_text(encoding="utf-8",errors="replace").splitlines():
        line=raw.split("#",1)[0].strip()
        if line and "=" in line:
            k,v=line.split("=",1); out[k.strip()]=v.strip()
    return out
def resolve_params(run):
    p=run/"output"/"params_used.kv"
    if p.is_file(): return p
    c=sorted((run/"params").glob("*.kv"))
    if len(c)==1: return c[0]
    raise RuntimeError(f"{run}: cannot resolve a unique params file")
def sort_unique(rows):
    d={}
    for r in rows:
        if "step" in r: d[ival(r,"step")]=r
    return [d[k] for k in sorted(d)]
def load_run(run,mode):
    sp=run/"output"/"summary_runtime.csv"
    dp=run/"output"/"darcy_exact_momentum_0493x8a.csv"
    pp=resolve_params(run)
    if not sp.is_file(): raise FileNotFoundError(sp)
    if not dp.is_file(): raise FileNotFoundError(dp)
    S=sort_unique(read_csv(sp)); D=sort_unique(read_csv(dp))
    if len(S)<2 or len(D)<1: raise RuntimeError(f"{mode}: insufficient rows")
    for c in ("step","time","totalMass","Px"):
        if c not in S[0]: raise RuntimeError(f"{mode}: summary missing {c}")
    for c in ("step","time","meanKickApplied","wholeDarcyApply","cumulativeMeanKickImpulseX","cumulativeCalls"):
        if c not in D[0]: raise RuntimeError(f"{mode}: Darcy CSV missing {c}")
    for r in D:
        if ival(r,"meanKickApplied")!=1 or ival(r,"wholeDarcyApply")!=1:
            raise RuntimeError(f"{mode}: x8a contract failed at step {r.get('step')}")
    P=parse_kv(pp); dt=float(P["dt"]); ax=float(P["bodyAccelerationX"])
    db={ival(r,"step"):r for r in D}
    if ival(S[0],"step")==0 and 0 not in db:
        db[0]={"step":"0","time":str(fval(S[0],"time",0.0)),
               "meanKickApplied":"1","wholeDarcyApply":"1",
               "cumulativeMeanKickImpulseX":"0","cumulativeCalls":"0"}
    sb={ival(r,"step"):r for r in S}
    steps=sorted(set(sb)&set(db))
    if len(steps)<2: raise RuntimeError(f"{mode}: <2 common steps")
    if steps[-1]!=max(db): raise RuntimeError(f"{mode}: final summary/Darcy steps misaligned")
    rows=[]
    for st in steps:
        s,d=sb[st],db[st]
        rows.append({"mode":mode,"step":st,"time":fval(s,"time"),
                     "mass":fval(s,"totalMass"),"Px":fval(s,"Px"),
                     "cumulativeDarcyImpulseX":fval(d,"cumulativeMeanKickImpulseX"),
                     "cumulativeCalls":ival(d,"cumulativeCalls")})
    p0=rows[0]["Px"]; scale=abs(p0)
    if not math.isfinite(p0) or scale==0: raise RuntimeError(f"{mode}: invalid P0")
    prev=None; cum_body=0.0; maxc=0.0; maxcalls=0.0
    for r in rows:
        r["UglobalX"]=r["Px"]/r["mass"]
        r["deltaPx"]=r["Px"]-p0
        r["cumNetSink"]=-r["deltaPx"]/scale
        if prev is None:
            ib=0.0; idp=math.nan; idd=math.nan; irr=math.nan
        else:
            ib=ax*0.5*(r["mass"]+prev["mass"])*(r["time"]-prev["time"])
            idp=r["Px"]-prev["Px"]
            idd=r["cumulativeDarcyImpulseX"]-prev["cumulativeDarcyImpulseX"]
            irr=idp-ib-idd
        cum_body+=ib
        r["intervalBodyImpulseX"]=ib; r["cumBodyImpulseX"]=cum_body
        r["cumBodyInput"]=cum_body/scale
        r["cumDarcySink"]=-r["cumulativeDarcyImpulseX"]/scale
        cr=r["deltaPx"]-cum_body-r["cumulativeDarcyImpulseX"]
        r["cumResidualImpulseX"]=cr; r["cumResidualSink"]=-cr/scale
        if prev is None:
            for k in ("intervalDeltaPx","intervalDarcyImpulseX","intervalResidualImpulseX",
                      "intervalNetSink","intervalBodyInput","intervalDarcySink","intervalResidualSink"):
                r[k]=math.nan
        else:
            r["intervalDeltaPx"]=idp; r["intervalDarcyImpulseX"]=idd; r["intervalResidualImpulseX"]=irr
            r["intervalNetSink"]=-idp/scale; r["intervalBodyInput"]=ib/scale
            r["intervalDarcySink"]=-idd/scale; r["intervalResidualSink"]=-irr/scale
        cl=r["cumNetSink"]-(r["cumDarcySink"]+r["cumResidualSink"]-r["cumBodyInput"])
        r["budgetClosure"]=cl; r["callMinusStep"]=r["cumulativeCalls"]-r["step"]
        maxc=max(maxc,abs(cl)); maxcalls=max(maxcalls,abs(r["callMinusStep"]))
        prev=r
    return rows,{"dt":dt,"ax":ax,"P0":p0,"maxAbsBudgetClosure":maxc,
                 "maxAbsCallMinusStep":maxcalls,"paramsPath":str(pp)}
def idx(rows): return {int(r["step"]):r for r in rows}
def pairwise(a,b,an,bn):
    A,B=idx(a),idx(b); out=[]
    cols=("UglobalX","cumNetSink","cumBodyInput","cumDarcySink","cumResidualSink",
          "intervalNetSink","intervalBodyInput","intervalDarcySink","intervalResidualSink")
    for st in sorted(set(A)&set(B)):
        x,y=A[st],B[st]; r={"step":st,"time":x["time"],"timeMismatch":x["time"]-y["time"]}
        for c in cols:
            va,vb=x[c],y[c]; r[f"{c}_{an}"]=va; r[f"{c}_{bn}"]=vb
            r[f"delta_{c}"]=va-vb if math.isfinite(va) and math.isfinite(vb) else math.nan
        r["delta_cumClosure"]=r["delta_cumNetSink"]-(r["delta_cumDarcySink"]+r["delta_cumResidualSink"]-r["delta_cumBodyInput"])
        out.append(r)
    return out
def crossing(rows,col,frac,sustain):
    final=rows[-1][col]
    if not math.isfinite(final) or abs(final)<1e-15: return math.nan,math.nan
    sign=1.0 if final>0 else -1.0; th=frac*abs(final); n=len(rows)
    for i in range(n):
        if i+sustain>n: break
        ok=True
        for j in range(i,i+sustain):
            v=rows[j][col]
            if not math.isfinite(v) or sign*v<th: ok=False; break
        if ok: return float(rows[i]["step"]),float(rows[i]["time"])
    return math.nan,math.nan
def crossing_table(rows,pair,sustain):
    out=[]
    for comp,col in (("net","delta_cumNetSink"),("darcy","delta_cumDarcySink"),("residual","delta_cumResidualSink")):
        final=rows[-1][col]
        for frac in (0.10,0.25,0.50,0.75,0.90):
            st,t=crossing(rows,col,frac,sustain)
            out.append({"pair":pair,"component":comp,"fractionOfOwnFinalExcess":frac,
                        "finalSignedExcess":final,"crossStep":st,"crossTime":t,"sustainPoints":sustain})
    return out
def at_or_before(rows,step,col):
    q=[r for r in rows if int(r["step"])<=step]
    return float(q[-1][col]) if q else math.nan
def windows(rows,pair,final_step):
    edges=sorted(set(max(0,min(final_step,int(x))) for x in (0,100,250,500,750,final_step)))
    out=[]
    for a,b in zip(edges[:-1],edges[1:]):
        if b<=a: continue
        r={"pair":pair,"stepStart":a,"stepEnd":b}
        for label,col in (("Net","delta_cumNetSink"),("Darcy","delta_cumDarcySink"),
                          ("Residual","delta_cumResidualSink"),("Body","delta_cumBodyInput")):
            va,vb=at_or_before(rows,a,col),at_or_before(rows,b,col)
            r[f"windowExcess{label}"]=vb-va if math.isfinite(va) and math.isfinite(vb) else math.nan
        out.append(r)
    return out
def lookup(cross,pair,comp,frac):
    for r in cross:
        if r["pair"]==pair and r["component"]==comp and abs(r["fractionOfOwnFinalExcess"]-frac)<1e-12:
            return float(r["crossStep"])
    return math.nan
def lead(cross,frac):
    d=lookup(cross,"GF-Q6","darcy",frac); r=lookup(cross,"GF-Q6","residual",frac); p=int(round(frac*100))
    if not math.isfinite(d) or not math.isfinite(r): return f"{p}%: unresolved crossing"
    if d<r: return f"{p}%: Darcy leads residual by {r-d:.0f} steps"
    if r<d: return f"{p}%: residual leads Darcy by {d-r:.0f} steps"
    return f"{p}%: Darcy and residual cross together at step {d:.0f}"
def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("--root",type=Path,default=Path("runs/0493x8a_vk_momentum_750"))
    ap.add_argument("--output-dir",type=Path,default=Path("runs/0493x8b_vk_momentum_divergence"))
    ap.add_argument("--sustain-points",type=int,default=3)
    a=ap.parse_args(); a.output_dir.mkdir(parents=True,exist_ok=True)
    runs={}; meta={}
    for m in MODES:
        runs[m],meta[m]=load_run(a.root/m,m)
        write_csv(a.output_dir/f"vk_momentum_timeseries_{m.replace('-','_')}_0493x8b.csv",runs[m])
    gf=pairwise(runs["src-q6-g-f"],runs["src-q6"],"gf","q6")
    qs=pairwise(runs["src-q6"],runs["src"],"q6","src")
    write_csv(a.output_dir/"vk_momentum_GF_minus_Q6_timeseries_0493x8b.csv",gf)
    write_csv(a.output_dir/"vk_momentum_Q6_minus_SRC_timeseries_0493x8b.csv",qs)
    cross=crossing_table(gf,"GF-Q6",a.sustain_points)+crossing_table(qs,"Q6-SRC",a.sustain_points)
    write_csv(a.output_dir/"vk_momentum_crossing_times_0493x8b.csv",cross)
    fs=min(int(runs[m][-1]["step"]) for m in MODES)
    win=windows(gf,"GF-Q6",fs)+windows(qs,"Q6-SRC",fs)
    write_csv(a.output_dir/"vk_momentum_window_contributions_0493x8b.csv",win)
    summary=[]
    for m in MODES:
        r0,r1=runs[m][0],runs[m][-1]
        summary.append({"mode":m,"finalStep":r1["step"],"UglobalStart":r0["UglobalX"],"UglobalEnd":r1["UglobalX"],
                        "cumNetSink":r1["cumNetSink"],"cumDarcySink":r1["cumDarcySink"],
                        "cumResidualSink":r1["cumResidualSink"],"cumBodyInput":r1["cumBodyInput"],
                        "maxAbsBudgetClosure":meta[m]["maxAbsBudgetClosure"],
                        "maxAbsCallMinusStep":meta[m]["maxAbsCallMinusStep"]})
    write_csv(a.output_dir/"vk_momentum_summary_0493x8b.csv",summary)
    attribution=[]
    for name,P in (("GF-Q6",gf),("Q6-SRC",qs)):
        r=P[-1]; net=r["delta_cumNetSink"]; dar=r["delta_cumDarcySink"]; res=r["delta_cumResidualSink"]; body=r["delta_cumBodyInput"]
        attribution.append({"pair":name,"finalNetExcess":net,"finalDarcyExcess":dar,"finalResidualExcess":res,
                            "finalBodyInputDifference":body,
                            "darcyFractionOfNetExcess":dar/net if abs(net)>1e-15 else math.nan,
                            "residualFractionOfNetExcess":res/net if abs(net)>1e-15 else math.nan,
                            "pairClosure":net-(dar+res-body)})
    write_csv(a.output_dir/"vk_momentum_final_attribution_0493x8b.csv",attribution)
    print("\n===== 0493x8b TIME-RESOLVED MOMENTUM DIVERGENCE =====")
    print("\nFinal per-mode budget:")
    print("mode          Ustart       Uend         netSink      DarcySink    residSink    bodyInput")
    for r in summary:
        print(f"{r['mode']:<12s}{r['UglobalStart']:>12.6f}{r['UglobalEnd']:>12.6f}{r['cumNetSink']:>13.6f}{r['cumDarcySink']:>13.6f}{r['cumResidualSink']:>13.6f}{r['cumBodyInput']:>13.6e}")
    print("\nFinal pairwise attribution:")
    print("pair      netExcess     DarcyExcess   residualExcess   Darcy/net   residual/net")
    for r in attribution:
        print(f"{r['pair']:<9s}{r['finalNetExcess']:>13.6f}{r['finalDarcyExcess']:>14.6f}{r['finalResidualExcess']:>17.6f}{r['darcyFractionOfNetExcess']:>12.6f}{r['residualFractionOfNetExcess']:>15.6f}")
    print(f"\nGF-Q6 sustained progress timing (sustain={a.sustain_points} sampled points):")
    print("component  fraction   crossStep   crossTime")
    for r in cross:
        if r["pair"]!="GF-Q6": continue
        cs="NaN" if not math.isfinite(r["crossStep"]) else f"{r['crossStep']:.0f}"
        ct="NaN" if not math.isfinite(r["crossTime"]) else f"{r['crossTime']:.9g}"
        print(f"{r['component']:<10s}{r['fractionOfOwnFinalExcess']:>8.2f}{cs:>12s}{ct:>12s}")
    print("\nGF-Q6 lead test:")
    for frac in (0.10,0.25,0.50): print("  "+lead(cross,frac))
    print("\nGF-Q6 window contributions:")
    print("steps         netExcess      DarcyExcess    residualExcess    bodyDiff")
    for r in win:
        if r["pair"]=="GF-Q6":
            print(f"{int(r['stepStart']):4d}-{int(r['stepEnd']):<4d}{r['windowExcessNet']:>15.6e}{r['windowExcessDarcy']:>15.6e}{r['windowExcessResidual']:>18.6e}{r['windowExcessBody']:>13.6e}")
    nz=[r for r in gf if int(r["step"])>0]
    if nz:
        r=nz[0]
        print("\nFirst common nonzero sample:")
        print(f"  step={int(r['step'])} time={r['time']:.9g} GF-Q6 net={r['delta_cumNetSink']:+.6e} Darcy={r['delta_cumDarcySink']:+.6e} residual={r['delta_cumResidualSink']:+.6e}")
    mt=max(abs(r["timeMismatch"]) for P in (gf,qs) for r in P)
    mc=max(abs(r["delta_cumClosure"]) for P in (gf,qs) for r in P)
    print("\nAudits:")
    print(f"  max time mismatch={mt:.3e}")
    print(f"  max pair cumulative closure={mc:.3e}")
    for m in MODES:
        print(f"  {m}: max budget closure={meta[m]['maxAbsBudgetClosure']:.3e} max |cumulativeCalls-step|={meta[m]['maxAbsCallMinusStep']:.3e}")
    print("\nInterpretation rule:")
    print("  - earlier Darcy crossings => extra GF loss begins preferentially in Darcy;")
    print("  - earlier residual crossings => extra GF loss begins preferentially outside Darcy;")
    print("  - similar timings/proportional growth => coupled/global splitting effect;")
    print("  - non-Darcy residual remains aggregate; do not label it Q6 yet.")
    print("\nOutputs:")
    for p in sorted(a.output_dir.glob("*0493x8b.csv")): print(f"  {p}")
    print("status=COMPLETE")
if __name__=="__main__": main()
