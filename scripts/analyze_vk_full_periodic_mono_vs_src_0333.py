#!/usr/bin/env python3
import csv
import math
import re
import statistics
import sys
from pathlib import Path
from collections import defaultdict

if len(sys.argv) != 2:
    raise SystemExit("usage: analyze_vk_full_periodic_mono_vs_src_0333.py ART_DIR")
art = Path(sys.argv[1])
mono_tsv = art / "mono_runs_0333.tsv"
src_tsv = art / "src_runs_0333.tsv"
summary_tsv = art / "vk_mono_vs_src_0333_summary.tsv"
ratio_tsv = art / "vk_mono_vs_src_0333_ratios.tsv"

float_re = re.compile(r"([-+]?\d+(?:\.\d*)?(?:[eE][-+]?\d+)?)")

def parse_time_file(path: Path):
    if not path.exists():
        return math.nan
    txt = path.read_text(errors="replace")
    m = re.search(r"elapsed=([-+0-9.eE]+)", txt)
    if m:
        return float(m.group(1))
    m = float_re.search(txt)
    return float(m.group(1)) if m else math.nan

def parse_mono_stdout(path: Path):
    out = {"bench_steps": math.nan, "bench_loop_s": math.nan, "bench_ms_step": math.nan}
    if not path.exists():
        return out
    for line in path.read_text(errors="replace").splitlines():
        if line.startswith("BENCH_STEPS"):
            out["bench_steps"] = float(line.split()[1])
        elif line.startswith("BENCH_LOOP_SECONDS"):
            out["bench_loop_s"] = float(line.split()[1])
        elif line.startswith("BENCH_MS_PER_STEP"):
            out["bench_ms_step"] = float(line.split()[1])
    return out

def read_summary_runtime(path: Path):
    if not path.exists():
        return {}
    with path.open(newline="") as f:
        rows = list(csv.DictReader(f))
    if not rows:
        return {}
    r = rows[-1]
    def fnum(k):
        try:
            return float(r.get(k,""))
        except Exception:
            return math.nan
    step = fnum("step")
    wall = fnum("wallTime")
    ms = 1000.0 * wall / step if step and not math.isnan(step) and not math.isnan(wall) else math.nan
    return {
        "step": step,
        "wallTime_s": wall,
        "ms_per_step_internal": ms,
        "meanVx": fnum("meanVx"),
        "meanVy": fnum("meanVy"),
        "kBTEstimate": fnum("kBTEstimate"),
        "nFluidParticles": fnum("nFluidParticles"),
        "nInactiveParticles": fnum("nInactiveParticles"),
        "hitsImmersed": fnum("hitsImmersed"),
    }

def mean(xs):
    xs=[x for x in xs if x is not None and not math.isnan(float(x))]
    return statistics.mean(xs) if xs else math.nan

def stdev(xs):
    xs=[x for x in xs if x is not None and not math.isnan(float(x))]
    return statistics.stdev(xs) if len(xs) >= 2 else 0.0

records=[]
if mono_tsv.exists():
    with mono_tsv.open(newline="") as f:
        for r in csv.DictReader(f, delimiter="\t"):
            if r.get("case") == "case" or r.get("rep") == "rep":
                continue
            stdout=Path(r["stdout"])
            timefile=Path(r["timefile"])
            b=parse_mono_stdout(stdout)
            elapsed=parse_time_file(timefile)
            steps=b["bench_steps"]
            ext_ms=1000.0*elapsed/steps if steps and not math.isnan(elapsed) else math.nan
            records.append({
                "case": r["case"], "kind":"mono", "rep": int(r["rep"]), "status": int(r["status"]),
                "elapsed_s": elapsed,
                "loop_s": b["bench_loop_s"],
                "ms_per_step_internal": b["bench_ms_step"],
                "ms_per_step_external": ext_ms,
                "step": steps,
                "meanVx": math.nan, "kBTEstimate": math.nan,
                "nFluidParticles": math.nan, "nInactiveParticles": 0.0, "hitsImmersed": math.nan,
            })
if src_tsv.exists():
    with src_tsv.open(newline="") as f:
        for r in csv.DictReader(f, delimiter="\t"):
            if r.get("case") == "case" or r.get("rep") == "rep":
                continue
            summary=Path(r["run_root"]) / "output" / "summary_runtime.csv"
            s=read_summary_runtime(summary)
            elapsed=parse_time_file(Path(r["timefile"]))
            step=s.get("step", math.nan)
            ext_ms=1000.0*elapsed/step if step and not math.isnan(elapsed) else math.nan
            records.append({
                "case": r["case"], "kind":"src", "rep": int(r["rep"]), "status": int(r["status"]),
                "elapsed_s": elapsed,
                "loop_s": s.get("wallTime_s", math.nan),
                "ms_per_step_internal": s.get("ms_per_step_internal", math.nan),
                "ms_per_step_external": ext_ms,
                "step": step,
                "meanVx": s.get("meanVx", math.nan),
                "kBTEstimate": s.get("kBTEstimate", math.nan),
                "nFluidParticles": s.get("nFluidParticles", math.nan),
                "nInactiveParticles": s.get("nInactiveParticles", math.nan),
                "hitsImmersed": s.get("hitsImmersed", math.nan),
            })

fields=["case","kind","n","status_ok","step_mean","elapsed_s_mean","elapsed_s_std","loop_s_mean","loop_s_std","ms_per_step_internal_mean","ms_per_step_internal_std","ms_per_step_external_mean","ms_per_step_external_std","meanVx_mean","kBT_mean","nFluid_mean","nInactive_mean","hitsImmersed_mean"]
groups=defaultdict(list)
for r in records:
    groups[(r["case"],r["kind"])].append(r)
with summary_tsv.open("w", newline="") as f:
    w=csv.writer(f, delimiter="\t")
    w.writerow(fields)
    for (case,kind),rs in sorted(groups.items()):
        ok=sum(1 for r in rs if r["status"]==0)
        w.writerow([
            case, kind, len(rs), ok,
            mean([r["step"] for r in rs]),
            mean([r["elapsed_s"] for r in rs]), stdev([r["elapsed_s"] for r in rs]),
            mean([r["loop_s"] for r in rs]), stdev([r["loop_s"] for r in rs]),
            mean([r["ms_per_step_internal"] for r in rs]), stdev([r["ms_per_step_internal"] for r in rs]),
            mean([r["ms_per_step_external"] for r in rs]), stdev([r["ms_per_step_external"] for r in rs]),
            mean([r["meanVx"] for r in rs]), mean([r["kBTEstimate"] for r in rs]),
            mean([r["nFluidParticles"] for r in rs]), mean([r["nInactiveParticles"] for r in rs]),
            mean([r["hitsImmersed"] for r in rs]),
        ])

# Build ratio table versus monolithic internal ms/step.
mono_cases=[k for k in groups if k[1]=="mono"]
mono_key=sorted(mono_cases)[0] if mono_cases else None
mono_internal=math.nan
mono_external=math.nan
if mono_key:
    mono_internal=mean([r["ms_per_step_internal"] for r in groups[mono_key]])
    mono_external=mean([r["ms_per_step_external"] for r in groups[mono_key]])
with ratio_tsv.open("w", newline="") as f:
    w=csv.writer(f, delimiter="\t")
    w.writerow(["case","kind","ms_per_step_internal_mean","ratio_internal_vs_mono","ms_per_step_external_mean","ratio_external_vs_mono"])
    for (case,kind),rs in sorted(groups.items()):
        mi=mean([r["ms_per_step_internal"] for r in rs])
        me=mean([r["ms_per_step_external"] for r in rs])
        ri=mi/mono_internal if mono_internal and not math.isnan(mono_internal) else math.nan
        re=me/mono_external if mono_external and not math.isnan(mono_external) else math.nan
        w.writerow([case,kind,mi,ri,me,re])

print(f"summary={summary_tsv}")
print(f"ratios={ratio_tsv}")
if mono_key:
    print(f"mono_reference={mono_key[0]} internal_ms_per_step={mono_internal:.9g} external_ms_per_step={mono_external:.9g}")
for (case,kind),rs in sorted(groups.items()):
    mi=mean([r["ms_per_step_internal"] for r in rs])
    if mono_internal and not math.isnan(mono_internal):
        print(f"{case}: kind={kind} internal_ms_per_step={mi:.9g} ratio={mi/mono_internal:.6g}")
