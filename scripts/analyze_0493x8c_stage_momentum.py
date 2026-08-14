#!/usr/bin/env python3
from pathlib import Path
import argparse, csv, math, statistics

MODES=("src","src-q6","src-q6-g-f")
STAGES=("step_start","after_q6_prestream","after_force_stream","after_boundary",
        "after_collision","after_q6_post","after_thermostat","after_darcy_post")
BUCKETS=("q6","stream_wall","boundary","collision","thermostat","darcy","unassigned","total")

def read_csv(p):
    with p.open(newline="",encoding="utf-8") as f:
        return list(csv.DictReader(f))
def f(r,k): return float(r[k])
def i(r,k): return int(round(float(r[k])))
def parse_kv(p):
    d={}
    for raw in p.read_text(encoding="utf-8",errors="replace").splitlines():
        s=raw.split("#",1)[0].strip()
        if s and "=" in s:
            k,v=s.split("=",1); d[k.strip()]=v.strip()
    return d
def resolve_params(run):
    p=run/"output"/"params_used.kv"
    if p.is_file(): return p
    q=sorted((run/"params").glob("*.kv"))
    if len(q)==1: return q[0]
    raise RuntimeError(f"{run}: cannot resolve params")
def p0_from_summary(run):
    r=read_csv(run/"output"/"summary_runtime.csv")
    r.sort(key=lambda x:i(x,"step"))
    return f(r[0],"Px")
def write_csv(p,rows):
    p.parent.mkdir(parents=True,exist_ok=True)
    with p.open("w",newline="",encoding="utf-8") as h:
        w=csv.DictWriter(h,fieldnames=list(rows[0].keys())); w.writeheader(); w.writerows(rows)

def load_mode(run,mode):
    sp=run/"output"/"momentum_stages_0493x8c.csv"
    dp=run/"output"/"darcy_exact_momentum_0493x8a.csv"
    if not sp.is_file(): raise FileNotFoundError(sp)
    if not dp.is_file(): raise FileNotFoundError(dp)
    P=parse_kv(resolve_params(run)); dt=float(P["dt"]); ax=float(P["bodyAccelerationX"])
    p0=p0_from_summary(run); scale=abs(p0)
    sr=read_csv(sp); stage={(i(r,"step"),r["stage"]):r for r in sr}
    steps=sorted(set(i(r,"step") for r in sr))
    darcy={i(r,"step"):f(r,"meanKickImpulseX") for r in read_csv(dp)}
    out=[]
    for step in steps:
        missing=[s for s in STAGES if (step,s) not in stage]
        if missing: raise RuntimeError(f"{mode} step={step}: missing {missing}")
        if step not in darcy: raise RuntimeError(f"{mode} step={step}: missing x8a Darcy row")
        px={s:f(stage[(step,s)],"Px") for s in STAGES}
        mass=f(stage[(step,"step_start")],"mass")
        body=mass*ax*dt; D=darcy[step]
        pre=px["after_q6_prestream"]-px["step_start"]
        force=px["after_force_stream"]-px["after_q6_prestream"]
        boundary=px["after_boundary"]-px["after_force_stream"]
        collision=px["after_collision"]-px["after_boundary"]
        q6post=px["after_q6_post"]-px["after_collision"]
        thermo=px["after_thermostat"]-px["after_q6_post"]
        post=px["after_darcy_post"]-px["after_thermostat"]
        total=px["after_darcy_post"]-px["step_start"]
        if mode=="src-q6-g-f":
            q6=pre-D-body
            stream_wall=force
            unexpected=q6post
            darcy_stage_error=post
        elif mode=="src-q6":
            q6=q6post
            stream_wall=force-body
            unexpected=0.0
            darcy_stage_error=post-D
        else:
            q6=0.0
            stream_wall=force-body
            unexpected=q6post
            darcy_stage_error=post-D
        assigned=body+D+q6+stream_wall+boundary+collision+thermo
        unassigned=total-assigned
        row={"mode":mode,"step":step,"time":f(stage[(step,"step_start")],"time"),
             "P0":p0,"mass":mass,"body":body,"q6":q6,"stream_wall":stream_wall,
             "boundary":boundary,"collision":collision,"thermostat":thermo,
             "darcy":D,"unassigned":unassigned,"total":total,
             "q6PostUnexpected":unexpected,"darcyStageError":darcy_stage_error}
        for k in ("body",)+BUCKETS:
            row[k+"OverP0"]=row[k]/scale
        out.append(row)
    return out

def pair(data,a,b):
    A={r["step"]:r for r in data[a]}; B={r["step"]:r for r in data[b]}
    rows=[]
    for s in sorted(set(A)&set(B)):
        r={"step":s,"time":A[s]["time"]}
        for k in BUCKETS: r[k]=A[s][k+"OverP0"]-B[s][k+"OverP0"]
        rows.append(r)
    return rows
def win(rows,a,b): return [r for r in rows if a<=r["step"]<=b]
def ssum(rows,k): return sum(r[k] for r in rows)
def mean(rows,k): return statistics.mean(r[k] for r in rows) if rows else math.nan
def print_window(title,rows):
    print("\n"+title)
    print("bucket          sampledSum/P0    meanPerSample/P0")
    for k in BUCKETS:
        print(f"{k:<15s}{ssum(rows,k):>+16.6e}{mean(rows,k):>+19.6e}")

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("--root",type=Path,default=Path("runs/0493x8c_stage_momentum_750"))
    ap.add_argument("--output-dir",type=Path,default=Path("runs/0493x8c_stage_momentum_750/analysis_x8c"))
    a=ap.parse_args(); a.output_dir.mkdir(parents=True,exist_ok=True)
    data={}
    for m in MODES:
        data[m]=load_mode(a.root/m,m)
        write_csv(a.output_dir/f"stage_buckets_{m.replace('-','_')}_0493x8c.csv",data[m])
    gf=pair(data,"src-q6-g-f","src-q6"); qs=pair(data,"src-q6","src")
    write_csv(a.output_dir/"GF_minus_Q6_stage_buckets_0493x8c.csv",gf)
    write_csv(a.output_dir/"Q6_minus_SRC_stage_buckets_0493x8c.csv",qs)

    max_d=max(abs(r["darcyStageError"])/abs(r["P0"]) for m in MODES for r in data[m])
    max_u=max(abs(r["unassignedOverP0"]) for m in MODES for r in data[m])
    max_q=max(abs(r["q6PostUnexpected"])/abs(r["P0"]) for m in MODES for r in data[m])

    print("\n===== 0493x8c STAGE-RESOLVED MOMENTUM =====")
    print("NOTE: sampled-step localization only; x8a remains the cumulative budget authority.")
    print("Sign: positive = +x momentum gain; negative = loss.")
    print("\nPer-mode sampled sums over all x8c samples:")
    print("mode          q6/P0        streamWall/P0 boundary/P0   collision/P0  thermostat/P0 Darcy/P0")
    for m in MODES:
        R=data[m]
        vals=[sum(r[k+"OverP0"] for r in R) for k in ("q6","stream_wall","boundary","collision","thermostat","darcy")]
        print(f"{m:<12s}"+"".join(f"{v:>+14.6e}" for v in vals))

    print_window("GF-Q6 signed excess by stage, sampled steps 20-100:",win(gf,20,100))
    print_window("GF-Q6 signed excess by stage, sampled steps 120-200:",win(gf,120,200))
    print_window("GF-Q6 signed excess by stage, all sampled steps:",gf)

    candidates=("q6","stream_wall","boundary","collision","thermostat","unassigned")
    ranked=sorted(((k,ssum(gf,k)) for k in candidates),key=lambda kv:abs(kv[1]),reverse=True)
    print("\nGF-Q6 non-Darcy ranking by |signed sampled sum|:")
    for k,v in ranked: print(f"  {k:<15s} {v:+.6e} P0")
    print(f"dominant_nonDarcy_stage={ranked[0][0]}")

    print("\nQ6-SRC control, all sampled steps:")
    print("bucket          sampledSum/P0    meanPerSample/P0")
    for k in BUCKETS:
        print(f"{k:<15s}{ssum(qs,k):>+16.6e}{mean(qs,k):>+19.6e}")

    print("\nAudits:")
    print(f"  max |post-Darcy stage - exact x8a Darcy| / P0 = {max_d:.3e}")
    print(f"  max |unassigned| / P0 = {max_u:.3e}")
    print(f"  max unexpected post-Q6 impulse (SRC/GF) / P0 = {max_q:.3e}")
    print("\nDecision:")
    print(f"  Primary localized GF-Q6 non-Darcy difference: {ranked[0][0]} ({ranked[0][1]:+.6e} P0 sampled sum).")
    print("  q6 -> projection/apply momentum path")
    print("  stream_wall -> wall-simple streaming/accommodation")
    print("  collision -> SRC wall-VP/collision exchange")
    print("  thermostat/boundary should be near-neutral here.")
    print("status=COMPLETE")

if __name__=="__main__": main()
