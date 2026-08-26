#!/usr/bin/env python3
import csv
import glob
import math
import os
import re
from collections import defaultdict

VREF = 0.1
MASS = 1.0
TRACE_PREFIX = "[0493x10micro] step="

pair_re = re.compile(
    r"(?P<key>[A-Za-z0-9_]+)=(?P<value>[^\s]+)"
)

def parse_trace(path):
    events = []
    with open(path, errors="replace") as f:
        for line in f:
            if TRACE_PREFIX not in line:
                continue
            d = {}
            for m in pair_re.finditer(line):
                d[m.group("key")] = m.group("value")
            required = [
                "step","p","event","init","tau","lambda","owner",
                "x","y","vx0","vy0",
                "ax","ay","bx","by",
                "uax","uay","ubx","uby",
                "wallVx","wallVy","nx","ny","reln",
                "vx1","vy1","dPx","dPy",
            ]
            miss = [k for k in required if k not in d]
            if miss:
                raise RuntimeError(f"{path}: malformed trace, missing {miss}: {line.strip()}")
            e = {}
            for k in required:
                if k in ("step","p","event","init","owner"):
                    e[k] = int(d[k])
                else:
                    e[k] = float(d[k])
            nx, ny = e["nx"], e["ny"]
            tx, ty = -ny, nx
            e["vpN"] = e["vx0"]*nx + e["vy0"]*ny
            e["vpT"] = e["vx0"]*tx + e["vy0"]*ty
            e["wallVN"] = e["wallVx"]*nx + e["wallVy"]*ny
            e["wallVT"] = e["wallVx"]*tx + e["wallVy"]*ty
            e["uAN"] = e["uax"]*nx + e["uay"]*ny
            e["uBN"] = e["ubx"]*nx + e["uby"]*ny
            e["uAT"] = e["uax"]*tx + e["uay"]*ty
            e["uBT"] = e["ubx"]*tx + e["uby"]*ty
            e["relCalc"] = e["vpN"] - e["wallVN"]
            e["relResidual"] = e["reln"] - e["relCalc"]
            e["dPyFormula"] = -2.0*MASS*e["reln"]*ny
            e["dPxFormula"] = -2.0*MASS*e["reln"]*nx
            e["dPyResidual"] = e["dPy"] - e["dPyFormula"]
            e["dPxResidual"] = e["dPx"] - e["dPxFormula"]
            events.append(e)
    return events

def log_identity(path):
    b = os.path.basename(path)
    m = re.match(r"(x10o|x10r)_vy(m?)([0-9]+)p([0-9]+)\.console\.log$", b)
    if not m:
        return None
    mode = m.group(1)
    sign = -1.0 if m.group(2) == "m" else 1.0
    vy = sign * float(m.group(3) + "." + m.group(4))
    return mode, round(vy, 6)

def write_event_csv(path, events):
    fields = [
        "step","p","event","init","owner","tau","lambda",
        "x","y","vx0","vy0","vx1","vy1",
        "nx","ny","vpN","wallVN","reln","relCalc","relResidual",
        "wallVx","wallVy","wallVT",
        "uAN","uBN","uAT","uBT",
        "dPx","dPy","dPxFormula","dPyFormula","dPxResidual","dPyResidual",
        "ax","ay","bx","by","uax","uay","ubx","uby",
    ]
    with open(path, "w", newline="") as f:
        wr = csv.DictWriter(f, fieldnames=fields)
        wr.writeheader()
        for e in events:
            wr.writerow({k:e[k] for k in fields})

def print_run_summary(mode, vy, events):
    bystep = defaultdict(list)
    for e in events:
        bystep[e["step"]].append(e)
    print(f"\n--- {mode} Vy={vy:+.3f} ---")
    print("step  events initOverlap  sum_dPy_particle   max|dPy|  mean_wallVN  mean_reln")
    for s in sorted(bystep):
        es = bystep[s]
        print(
            f"{s:4d} {len(es):7d} "
            f"{sum(e['init'] for e in es):11d} "
            f"{sum(e['dPy'] for e in es):+17.8f} "
            f"{max(abs(e['dPy']) for e in es):10.6f} "
            f"{sum(e['wallVN'] for e in es)/len(es):+12.6f} "
            f"{sum(e['reln'] for e in es)/len(es):+10.6f}"
        )
    if events:
        print(
            "formula checks: "
            f"max|reln-(vpN-wallVN)|={max(abs(e['relResidual']) for e in events):.3e} "
            f"max|dPy+2*m*reln*ny|={max(abs(e['dPyResidual']) for e in events):.3e}"
        )

def key(e):
    return (e["step"], e["p"], e["event"])

def paired_odd(mode, minus, plus, out_dir):
    dm = {key(e):e for e in minus}
    dp = {key(e):e for e in plus}
    common = sorted(set(dm).intersection(dp))
    allkeys = set(dm).union(dp)

    print(f"\n===== {mode} +/-0.1 MATCHED EVENT ODD ANALYSIS =====")
    print(f"matched={len(common)} union={len(allkeys)} fraction={len(common)/max(1,len(allkeys)):.3f}")
    print(
        "step match union  sum_dPyOdd_all  sum_dPyOdd_matched  "
        "mean(vpNodd-wallVNodd)  mean_wallVNodd_error"
    )

    rows = []
    for k in common:
        em, ep = dm[k], dp[k]
        # Quantities in each event's own collision normal. This is the right
        # operational comparison of the accepted reflection law.
        row = {
            "step": k[0], "p": k[1], "event": k[2],
            "dPyOdd": 0.5*(ep["dPy"] - em["dPy"]),
            "vpNOdd": 0.5*(ep["vpN"] - em["vpN"]),
            "wallVNOdd": 0.5*(ep["wallVN"] - em["wallVN"]),
            "relnOdd": 0.5*(ep["reln"] - em["reln"]),
            "nyMean": 0.5*(ep["ny"] + em["ny"]),
            "nxMean": 0.5*(ep["nx"] + em["nx"]),
            "wallVNExpectedOdd": VREF * 0.5*(ep["ny"] + em["ny"]),
            "uATOdd": 0.5*(ep["uAT"] - em["uAT"]),
            "uBTOdd": 0.5*(ep["uBT"] - em["uBT"]),
            "initMinus": em["init"], "initPlus": ep["init"],
        }
        row["wallVNOddError"] = row["wallVNOdd"] - row["wallVNExpectedOdd"]
        rows.append(row)

    bm = defaultdict(float)
    bp = defaultdict(float)
    for e in minus: bm[e["step"]] += e["dPy"]
    for e in plus:  bp[e["step"]] += e["dPy"]
    by_common = defaultdict(list)
    for r in rows: by_common[r["step"]].append(r)

    steps = sorted(set(bm).union(bp))
    for s in steps:
        rs = by_common.get(s, [])
        n_union = len({key(e) for e in minus if e["step"]==s}.union(
                      {key(e) for e in plus if e["step"]==s}))
        odd_all = 0.5*(bp[s]-bm[s])
        odd_matched = sum(r["dPyOdd"] for r in rs)
        relodd = sum((r["vpNOdd"]-r["wallVNOdd"]) for r in rs)/len(rs) if rs else float("nan")
        werr = sum(r["wallVNOddError"] for r in rs)/len(rs) if rs else float("nan")
        print(
            f"{s:4d} {len(rs):5d} {n_union:5d} "
            f"{odd_all:+15.8f} {odd_matched:+18.8f} "
            f"{relodd:+22.8e} {werr:+22.8e}"
        )

    out = os.path.join(out_dir, f"{mode}_matched_odd_events.csv")
    fields = [
        "step","p","event","dPyOdd","vpNOdd","wallVNOdd","relnOdd",
        "nyMean","nxMean","wallVNExpectedOdd","wallVNOddError",
        "uATOdd","uBTOdd","initMinus","initPlus",
    ]
    with open(out, "w", newline="") as f:
        wr = csv.DictWriter(f, fieldnames=fields)
        wr.writeheader()
        wr.writerows(rows)

    print("\nTop matched events by |dPyOdd|:")
    for r in sorted(rows, key=lambda x: abs(x["dPyOdd"]), reverse=True)[:20]:
        print(
            f"step={r['step']:2d} p={r['p']:3d} ev={r['event']} "
            f"dPyOdd={r['dPyOdd']:+.6f} "
            f"vpNOdd={r['vpNOdd']:+.6f} "
            f"wallVNOdd={r['wallVNOdd']:+.6f} "
            f"expectedWallOdd={r['wallVNExpectedOdd']:+.6f} "
            f"wallErr={r['wallVNOddError']:+.6f}"
        )
    print(f"[micro] wrote {out}")

def main():
    log_root = "runs/0493x10micro_logs"
    logs = sorted(glob.glob(os.path.join(log_root, "*.console.log")))
    if not logs:
        raise SystemExit(f"no logs found under {log_root}")

    data = {}
    event_out = os.path.join(log_root, "events")
    os.makedirs(event_out, exist_ok=True)

    for p in logs:
        ident = log_identity(p)
        if ident is None:
            continue
        mode, vy = ident
        es = parse_trace(p)
        data[(mode,vy)] = es
        out = os.path.join(event_out, f"{mode}_vy{str(vy).replace('-','m').replace('.','p')}.csv")
        write_event_csv(out, es)
        print_run_summary(mode, vy, es)
        print(f"[micro] wrote {out}")

    for mode in ("x10o","x10r"):
        if (mode,-0.1) in data and (mode,0.1) in data:
            paired_odd(mode, data[(mode,-0.1)], data[(mode,0.1)], event_out)

if __name__ == "__main__":
    main()
