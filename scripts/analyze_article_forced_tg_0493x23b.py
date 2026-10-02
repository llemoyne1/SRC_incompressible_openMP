#!/usr/bin/env python3
"""JCP Sec. 4.1 forced Taylor--Green validation, 0493x23b.

Reads the shared initial .smpcd state and all particle-state dumps for exactly
SRC and SRC + particle/field closure.  It reconstructs cell population and
velocity on the solver grid and writes the article time series, tail summary,
two-panel figure, and paired late-time inspection snapshots.

No pandas is used.
"""
from __future__ import annotations

import argparse
import csv
import math
import re
import struct
from pathlib import Path
from typing import Dict, List, Tuple

import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

FLUID_ROLE = 1
DUMP_RE = re.compile(r"state_step_(\d+)\.smpcd$")


def parse_kv(path: Path) -> Dict[str, str]:
    out: Dict[str, str] = {}
    for raw in path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        out[k.strip()] = v.strip()
    return out


def ff(d: Dict[str, str], key: str, default=float("nan")) -> float:
    try:
        v = float(d.get(key, ""))
        return v if math.isfinite(v) else default
    except Exception:
        return default


def read_smpcd(path: Path) -> Dict[str, np.ndarray]:
    with path.open("rb") as f:
        magic = f.read(16)
        if not magic.startswith(b"SRCMPCD_STATE"):
            raise ValueError(f"{path}: unsupported magic {magic!r}")
        raw = f.read(40)
        if len(raw) != 40:
            raise ValueError(f"{path}: truncated header")
        version, endian, dim, layout, n, has_type, has_mass, real_bytes, type_bytes = struct.unpack("<IIIIQIIII", raw)
        reserved = struct.unpack("<8Q", f.read(64))
        del version, endian, layout, reserved
        if dim != 2 or real_bytes != 8:
            raise ValueError(f"{path}: unsupported dim/real size dim={dim} real={real_bytes}")
        n = int(n)
        x = np.fromfile(f, dtype="<f8", count=n)
        y = np.fromfile(f, dtype="<f8", count=n)
        vx = np.fromfile(f, dtype="<f8", count=n)
        vy = np.fromfile(f, dtype="<f8", count=n)
        if min(len(x), len(y), len(vx), len(vy)) != n:
            raise ValueError(f"{path}: truncated particle arrays")
        if has_type:
            tdtype = "<u4" if type_bytes == 4 else "<u8"
            typ = np.fromfile(f, dtype=tdtype, count=n)
        else:
            typ = np.zeros(n, dtype=np.uint32)
        if has_mass:
            mass = np.fromfile(f, dtype="<f8", count=n)
        else:
            mass = np.ones(n, dtype=np.float64)
        # Current state format stores a role byte array after mass/type arrays.
        role = np.fromfile(f, dtype=np.uint8, count=n)
        if len(role) != n:
            # Older states can omit roles; all particles are fluid in this test.
            role = np.full(n, FLUID_ROLE, dtype=np.uint8)
    return {"x": x, "y": y, "vx": vx, "vy": vy, "type": typ, "mass": mass, "role": role}


def grid_reconstruct(state: Dict[str, np.ndarray], lx: float, ly: float, nx: int, ny: int):
    role = state["role"]
    keep = role == FLUID_ROLE
    x = np.mod(state["x"][keep], lx)
    y = np.mod(state["y"][keep], ly)
    vx = state["vx"][keep]
    vy = state["vy"][keep]
    mass = state["mass"][keep]
    dx, dy = lx / nx, ly / ny
    ix = np.floor(x / dx).astype(np.int64)
    iy = np.floor(y / dy).astype(np.int64)
    np.clip(ix, 0, nx - 1, out=ix)
    np.clip(iy, 0, ny - 1, out=iy)
    flat = iy * nx + ix
    nc = nx * ny
    count = np.bincount(flat, minlength=nc).astype(np.float64)
    mcell = np.bincount(flat, weights=mass, minlength=nc)
    px = np.bincount(flat, weights=mass * vx, minlength=nc)
    py = np.bincount(flat, weights=mass * vy, minlength=nc)
    ux = np.zeros(nc, dtype=np.float64)
    uy = np.zeros(nc, dtype=np.float64)
    supported = mcell > 0.0
    ux[supported] = px[supported] / mcell[supported]
    uy[supported] = py[supported] / mcell[supported]
    return {
        "keep": keep, "flat": flat, "count": count.reshape(ny, nx),
        "mcell": mcell.reshape(ny, nx), "ux": ux.reshape(ny, nx), "uy": uy.reshape(ny, nx),
        "supported": supported.reshape(ny, nx), "mass": mass, "vx": vx, "vy": vy,
        "dx": dx, "dy": dy,
    }


def metrics_for_state(state: Dict[str, np.ndarray], params: Dict[str, str]) -> Tuple[Dict[str, float], Dict[str, np.ndarray]]:
    lx, ly = float(params["Lx"]), float(params["Ly"])
    nx, ny = int(params["Nx"]), int(params["Ny"])
    mx, my = int(params.get("taylorGreenForcingModeX", "1")), int(params.get("taylorGreenForcingModeY", "1"))
    g = grid_reconstruct(state, lx, ly, nx, ny)
    count = g["count"]
    ux = g["ux"].copy(); uy = g["uy"].copy(); supported = g["supported"]
    mass = g["mass"]; vx = g["vx"]; vy = g["vy"]

    total_mass = float(np.sum(mass))
    px = float(np.sum(mass * vx)); py = float(np.sum(mass * vy))
    mean_vx = px / total_mass if total_mass > 0 else float("nan")
    mean_vy = py / total_mass if total_mass > 0 else float("nan")
    # Remove global translation only where velocity is resolved; unsupported cells
    # retain zero contribution so empty cores are not silently discarded.
    ux[supported] -= mean_vx
    uy[supported] -= mean_vy

    xc = (np.arange(nx) + 0.5) * g["dx"]
    yc = (np.arange(ny) + 0.5) * g["dy"]
    X, Y = np.meshgrid(xc, yc)
    kx = 2.0 * math.pi * mx / lx
    ky = 2.0 * math.pi * my / ly
    phix = np.sin(kx * X) * np.cos(ky * Y)
    phiy = -(kx / ky) * np.cos(kx * X) * np.sin(ky * Y)
    num = float(np.sum(ux * phix + uy * phiy))
    den_u = float(np.sum(ux * ux + uy * uy))
    den_phi = float(np.sum(phix * phix + phiy * phiy))
    corr = num / math.sqrt(den_u * den_phi) if den_u > 0 and den_phi > 0 else float("nan")
    amp = num / den_phi if den_phi > 0 else float("nan")

    domain_mean_n = float(np.mean(count))
    rel_rms = float(np.std(count) / domain_mean_n) if domain_mean_n > 0 else float("nan")
    unsupported = float(np.mean(~supported))

    centers = [(0.25*lx,0.25*ly),(0.75*lx,0.25*ly),(0.25*lx,0.75*ly),(0.75*lx,0.75*ly)]
    radius = 2.0 * max(g["dx"], g["dy"])
    core_n: List[float] = []
    center_n: List[float] = []
    for cx, cy in centers:
        ddx = np.minimum(np.abs(X-cx), lx-np.abs(X-cx))
        ddy = np.minimum(np.abs(Y-cy), ly-np.abs(Y-cy))
        mask = np.hypot(ddx, ddy) <= radius
        core_n.append(float(np.mean(count[mask])))
        ix0 = int(np.argmin(np.abs(xc-cx))); iy0 = int(np.argmin(np.abs(yc-cy)))
        center_n.append(float(count[iy0, ix0]))
    core_mean = float(np.mean(core_n))
    core_std = float(np.std(core_n, ddof=0))
    density_ratio = core_mean / domain_mean_n if domain_mean_n > 0 else float("nan")

    # Cell-relative thermal proxy, consistent with subtracting one 2-D COM per
    # occupied cell: KE_th = (Nfluid - Noccupied) kBT.
    flat = g["flat"]
    ux_flat = g["ux"].ravel()[flat]
    uy_flat = g["uy"].ravel()[flat]
    thermal_ke = float(np.sum(0.5 * mass * ((vx-ux_flat)**2 + (vy-uy_flat)**2)))
    nfluid = int(mass.size); nocc = int(np.count_nonzero(supported))
    dof_pairs = nfluid - nocc
    kbt_proxy = thermal_ke / dof_pairs if dof_pairs > 0 else float("nan")

    m = {
        "domainMeanN": domain_mean_n,
        "coreN1": core_n[0], "coreN2": core_n[1], "coreN3": core_n[2], "coreN4": core_n[3],
        "coreMeanN": core_mean, "coreStdN": core_std,
        "densityRatioCore": density_ratio, "densityRelDefectCore": density_ratio - 1.0,
        "centerCellN1": center_n[0], "centerCellN2": center_n[1], "centerCellN3": center_n[2], "centerCellN4": center_n[3],
        "velocityModeCorrelation": corr, "velocityModeAmplitude": amp,
        "relativePopulationRMS": rel_rms, "emptyOrUnsupportedCellFraction": unsupported,
        "totalMass": total_mass, "Px": px, "Py": py, "meanVx": mean_vx, "meanVy": mean_vy,
        "kBTCellRelativeProxy": kbt_proxy,
    }
    fields = {"count": count, "ux": ux, "uy": uy, "speed": np.hypot(ux,uy), "X": X, "Y": Y}
    return m, fields


def dump_map(out_dir: Path) -> Dict[int, Path]:
    d: Dict[int, Path] = {}
    for p in out_dir.glob("state_step_*.smpcd"):
        m = DUMP_RE.search(p.name)
        if m: d[int(m.group(1))] = p
    return d


def read_summary(path: Path) -> List[Dict[str,str]]:
    if not path.is_file(): return []
    with path.open(newline="",encoding="utf-8",errors="replace") as f:
        return list(csv.DictReader(f))


def summary_diag(rows: List[Dict[str,str]], closure: bool):
    def vals(*keys):
        out=[]
        for r in rows:
            for k in keys:
                if k in r and r[k] not in (None,""):
                    try:
                        x=float(r[k])
                        if math.isfinite(x): out.append(x)
                    except Exception: pass
                    break
        return out
    kbt=vals("kBTEstimate","kBTEstimate","kBT")
    result = {
        "runtimeKBTMean": float(np.mean(kbt)) if kbt else float("nan"),
        "runtimeKBTMin": min(kbt) if kbt else float("nan"),
        "runtimeKBTMax": max(kbt) if kbt else float("nan"),
        "q6ResidualRelMax": float("nan"),
        "q6NonConvergedSamples": 0,
    }
    if not closure:
        return result
    # Count convergence only on samples where Q6 was actually applied.
    applied_rows=[]
    for r in rows:
        try:
            if float(r.get("q6Applied", "0") or 0.0) >= 0.5:
                applied_rows.append(r)
        except Exception:
            pass
    qres=[]; qconv=[]
    for r in applied_rows:
        try:
            x=float(r.get("q6ResidualRel", "nan"));
            if math.isfinite(x): qres.append(x)
        except Exception: pass
        try:
            x=float(r.get("q6Converged", "nan"));
            if math.isfinite(x): qconv.append(x)
        except Exception: pass
    result["q6ResidualRelMax"] = max(qres) if qres else float("nan")
    result["q6NonConvergedSamples"] = int(sum(1 for x in qconv if x < 0.5))
    return result


def fmt(x):
    if isinstance(x, str): return x
    if isinstance(x, (int,np.integer)): return str(int(x))
    try:
        return "" if not math.isfinite(float(x)) else f"{float(x):.17g}"
    except Exception: return str(x)


def write_rows(path: Path, rows: List[Dict[str,object]]):
    path.parent.mkdir(parents=True,exist_ok=True)
    if not rows: return
    fields=list(rows[0].keys())
    with path.open("w",newline="",encoding="utf-8") as f:
        w=csv.DictWriter(f,fieldnames=fields,lineterminator="\n"); w.writeheader()
        for r in rows: w.writerow({k:fmt(v) for k,v in r.items()})


def plot_main(root: Path, rows: List[Dict[str,object]]):
    fig, axes = plt.subplots(1,2,figsize=(10.5,4.2))
    labels=["SRC","SRC + particle/field closure"]
    for label in labels:
        rr=[r for r in rows if r["mode"]==label]
        rr.sort(key=lambda x:int(x["step"]))
        t=[float(r["time"]) for r in rr]
        axes[0].plot(t,[float(r["densityRatioCore"]) for r in rr],label=label)
        axes[1].plot(t,[float(r["velocityModeCorrelation"]) for r in rr],label=label)
    axes[0].axhline(1.0,linestyle="--",linewidth=0.8,alpha=0.6)
    axes[1].axhline(1.0,linestyle="--",linewidth=0.8,alpha=0.6)
    axes[0].set_xlabel("time"); axes[0].set_ylabel("vortex-core population ratio $R_\\rho$")
    axes[1].set_xlabel("time"); axes[1].set_ylabel("Taylor–Green mode correlation $C_{TG}$")
    axes[0].set_title("(a)"); axes[1].set_title("(b)")
    axes[0].legend(); axes[1].legend()
    for ax in axes: ax.grid(True,alpha=0.2)
    fig.tight_layout()
    fig.savefig(root/"figures"/"fig_10_forced_taylor_green_validation.pdf",bbox_inches="tight")
    fig.savefig(root/"figures"/"fig_10_forced_taylor_green_validation.png",dpi=240,bbox_inches="tight")
    plt.close(fig)


def plot_checks(root: Path, fields_by_mode: Dict[str,Dict[str,np.ndarray]]):
    A=fields_by_mode["SRC"]; B=fields_by_mode["SRC + particle/field closure"]
    dmin=min(float(np.min(A["count"])),float(np.min(B["count"])))
    dmax=max(float(np.max(A["count"])),float(np.max(B["count"])))
    smin=0.0; smax=max(float(np.max(A["speed"])),float(np.max(B["speed"])))
    for label,tag,F in [("SRC","src",A),("SRC + particle/field closure","closure",B)]:
        fig,ax=plt.subplots(figsize=(5.2,4.5)); im=ax.imshow(F["count"],origin="lower",vmin=dmin,vmax=dmax,aspect="equal")
        ax.set_title(f"{label}: population"); ax.set_xlabel("cell x"); ax.set_ylabel("cell y"); fig.colorbar(im,ax=ax,label="particles/cell")
        fig.tight_layout(); fig.savefig(root/"figures"/f"check_density_{tag}.png",dpi=220,bbox_inches="tight"); plt.close(fig)
        fig,ax=plt.subplots(figsize=(5.2,4.5)); im=ax.imshow(F["speed"],origin="lower",vmin=smin,vmax=smax,aspect="equal")
        stride=max(1,F["speed"].shape[0]//24)
        yy,xx=np.mgrid[0:F["speed"].shape[0]:stride,0:F["speed"].shape[1]:stride]
        ax.quiver(xx,yy,F["ux"][::stride,::stride],F["uy"][::stride,::stride])
        ax.set_title(f"{label}: resolved velocity"); ax.set_xlabel("cell x"); ax.set_ylabel("cell y"); fig.colorbar(im,ax=ax,label="speed")
        fig.tight_layout(); fig.savefig(root/"figures"/f"check_velocity_{tag}.png",dpi=220,bbox_inches="tight"); plt.close(fig)


def main():
    ap=argparse.ArgumentParser(); ap.add_argument('--root',type=Path,default=Path('article_forced_tg_validation_x23b')); a=ap.parse_args()
    root=a.root
    srcp=parse_kv(root/"params"/"src_params_used.kv"); clp=parse_kv(root/"params"/"closure_params_used.kv")
    if srcp.get("inputState") != clp.get("inputState"): raise SystemExit("initial-state paths differ")
    init=Path(srcp["inputState"])
    if not init.is_file(): raise SystemExit(f"missing shared initial state: {init}")
    dt=float(srcp["dt"]); nsteps=int(srcp["nSteps"])
    modes=[("SRC","src",srcp),("SRC + particle/field closure","closure",clp)]
    rows: List[Dict[str,object]]=[]; final_fields={}; mode_diags={}
    init_state=read_smpcd(init)
    for label,sub,params in modes:
        dm=dump_map(root/"runs"/sub/"output")
        if not dm: raise SystemExit(f"no state dumps for {label}")
        # step 0 is the exact common initial state; replace if the solver also dumped step 0.
        steps=[0]+sorted(s for s in dm if s!=0)
        for step in steps:
            state=init_state if step==0 else read_smpcd(dm[step])
            m,_=metrics_for_state(state,params)
            row={"mode":label,"internalMode":"src" if sub=="src" else "src-q6-g-f","step":step,"time":step*dt}
            row.update(m); rows.append(row)
        last=max(dm); _,F=metrics_for_state(read_smpcd(dm[last]),params); final_fields[label]=F
        mode_diags[label]=summary_diag(read_summary(root/"runs"/sub/"output"/"summary_runtime.csv"), closure=(sub=="closure"))

    rows.sort(key=lambda r:(str(r["mode"]),int(r["step"])))
    write_rows(root/"data"/"forced_tg_timeseries.csv",rows)

    sums=[]
    by={lab:[r for r in rows if r["mode"]==lab] for lab,_,_ in modes}
    for label,_,_ in modes:
        rr=by[label]; tail=[r for r in rr if int(r["step"]) >= nsteps/2]
        def arr(k): return np.asarray([float(r[k]) for r in tail],dtype=float)
        mass_all=np.asarray([float(r["totalMass"]) for r in rr]); m0=mass_all[0]
        d=mode_diags[label]
        sums.append({
            "mode":label,"tailStartStep":math.ceil(nsteps/2),"tailSamples":len(tail),
            "meanDensityRatioCore":float(np.mean(arr("densityRatioCore"))),"stdDensityRatioCore":float(np.std(arr("densityRatioCore"))),"minDensityRatioCore":float(np.min(arr("densityRatioCore"))),
            "meanVelocityModeCorrelation":float(np.mean(arr("velocityModeCorrelation"))),"stdVelocityModeCorrelation":float(np.std(arr("velocityModeCorrelation"))),"minVelocityModeCorrelation":float(np.min(arr("velocityModeCorrelation"))),
            "meanVelocityModeAmplitude":float(np.mean(arr("velocityModeAmplitude"))),
            "meanRelativePopulationRMS":float(np.mean(arr("relativePopulationRMS"))),
            "meanUnsupportedCellFraction":float(np.mean(arr("emptyOrUnsupportedCellFraction"))),
            "maxRelativeMassDrift":float(np.max(np.abs(mass_all-m0))/max(abs(m0),1e-300)),
            "meanKBTCellRelativeProxy":float(np.mean(arr("kBTCellRelativeProxy"))),
            **d,
        })
    # Pairwise deltas closure - SRC.
    sums[0]["deltaMeanDensityRatioCoreClosureMinusSRC"]=""
    sums[0]["deltaMeanVelocityModeCorrelationClosureMinusSRC"]=""
    sums[1]["deltaMeanDensityRatioCoreClosureMinusSRC"]=sums[1]["meanDensityRatioCore"]-sums[0]["meanDensityRatioCore"]
    sums[1]["deltaMeanVelocityModeCorrelationClosureMinusSRC"]=sums[1]["meanVelocityModeCorrelation"]-sums[0]["meanVelocityModeCorrelation"]
    write_rows(root/"data"/"forced_tg_summary.csv",sums)

    plot_main(root,rows); plot_checks(root,final_fields)

    with (root/"forced_tg_validation_summary.txt").open("w",encoding="utf-8") as f:
        f.write("===== 0493x23b JCP SECTION 4.1 FORCED TAYLOR--GREEN VALIDATION =====\n")
        f.write(f"sharedInitialState={init}\n")
        f.write(f"grid={srcp['Nx']}x{srcp['Ny']} L={srcp['Lx']}x{srcp['Ly']} dt={srcp['dt']} kBT={srcp['kBT']} steps={srcp['nSteps']}\n")
        f.write(f"forcingEnable={srcp['taylorGreenForcingEnable']} amplitude={srcp['taylorGreenForcingAmplitude']} mode=({srcp['taylorGreenForcingModeX']},{srcp['taylorGreenForcingModeY']})\n")
        for s in sums:
            f.write("\n"+s["mode"]+"\n")
            for k,v in s.items():
                if k!="mode": f.write(f"  {k}={fmt(v)}\n")
        f.write("\nInterpretation policy: descriptive only; no a-priori PASS/FAIL threshold.\n")
        f.write("Primary observables: R_rho(t)=N_core/<N>domain and C_TG(t).\n")
        f.write("Energy conservation is not asserted because the runs are thermostatted and continuously forced.\n")

    print(f"[0493x23b-analysis] PASS root={root}")
    print(f"[0493x23b-analysis] timeseries={root/'data'/'forced_tg_timeseries.csv'}")
    print(f"[0493x23b-analysis] summary={root/'data'/'forced_tg_summary.csv'}")
    print(f"[0493x23b-analysis] figure={root/'figures'/'fig_10_forced_taylor_green_validation.pdf'}")
    for s in sums:
        print(f"[0493x23b-analysis] {s['mode']}: meanRrho={s['meanDensityRatioCore']:.6g} meanCTG={s['meanVelocityModeCorrelation']:.6g} massDriftMax={s['maxRelativeMassDrift']:.3e}")

if __name__=='__main__': main()
