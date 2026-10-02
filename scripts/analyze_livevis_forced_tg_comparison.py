#!/usr/bin/env python3
"""
Compare two SRC/MPCD LiveVis filtered-recording sessions for forced Taylor--Green.

Inputs are recording-session directories containing manifest.kv and files named
    step_<step>_field_ux.f32
    step_<step>_field_uy.f32
(optionally n as well).

Outputs:
  - tg_livevis_metrics.csv
  - tg_livevis_summary.txt
  - fig_livevis_vorticity_quiver_2x2_tau.png/.pdf
  - fig_livevis_tg_modal_metrics_vs_tau.png/.pdf
  - fig_livevis_population_2x2_tau.png/.pdf

The script uses the recorded ux/uy fields directly. It does NOT reconstruct
fields from particle dumps and does NOT add temporal filtering. Publication
figures use the nondimensional time tau = k_char U0 t and normalize the modal
amplitude by the first recorded frame of each run.  The amplitude panel also
shows the parameter-free linear forced-Taylor--Green prediction
A(t)=A_inf+[A(0)-A_inf] exp(-2 nu k_char^2 t), using the supplied/measured
closure viscosity and forcing amplitude.

Dependencies: numpy, matplotlib. No pandas/scipy.
"""

from __future__ import annotations

import argparse
import csv
import math
import os
import re
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Sequence, Tuple

import numpy as np

# Non-interactive and safe over WSL/SSH.
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.colors import TwoSlopeNorm


DEFAULT_SRC = r"E:\SRC_MPCD_dev\SRC_GPU-SURF\article_forced_tg_gamma20_highamp_x23d_s5000_20260921_183019\runs\src\output\recordings\record_step_0000000001"
DEFAULT_CLOSURE = r"E:\SRC_MPCD_dev\SRC_GPU-SURF\article_forced_tg_gamma20_highamp_x23d_s5000_20260921_183019\runs\closure\output\recordings\record_step_0000000001"
DEFAULT_SRC = r"E:\SRC_MPCD_DEV\SRC_GPU-SURF\article_forced_tg_gamma20_highamp_x23d_s5000_20260921_213949\runs\src\output\recordings\record_step_0000000001"
DEFAULT_CLOSURE = r"E:\SRC_MPCD_DEV\SRC_GPU-SURF\article_forced_tg_gamma20_highamp_x23d_s5000_20260921_213949\runs\closure\output\recordings\record_step_0000000001"

FIELD_RE = re.compile(r"^step_(\d+)_field_([A-Za-z0-9_]+)\.f32$")


def _rebase_to_current_repo(path: Path) -> Path:
    """
    Under WSL/DrvFS, a Windows path may reach the repository with a different
    spelling/case (e.g. SRC_MPCD_dev vs SRC_MPCD_DEV).  Reads may still work
    on NTFS while some writers (notably PIL/Matplotlib) can fail with EINVAL.

    When the script is launched from the SRC_GPU-SURF repository, rebuild any
    path that points inside that repository from the *actual current working
    directory*.  This preserves the exact mounted-path spelling for writes.
    """
    if os.name == "nt":
        return path
    try:
        cwd = Path.cwd()
    except OSError:
        return path
    if cwd.name.casefold() != "src_gpu-surf".casefold():
        return path

    parts = path.parts
    repo_idx = None
    for i, part in enumerate(parts):
        if part.casefold() == cwd.name.casefold():
            repo_idx = i
    if repo_idx is None:
        return path
    suffix = parts[repo_idx + 1:]
    return cwd.joinpath(*suffix)


def normalize_path(text: str) -> Path:
    """Accept native paths and Windows drive paths when executed under WSL/Linux."""
    s = os.path.expandvars(os.path.expanduser(str(text).strip()))
    m = re.match(r"^([A-Za-z]):[\\/](.*)$", s)
    if m and os.name != "nt":
        drive = m.group(1).lower()
        tail = m.group(2).replace("\\", "/")
        p = Path(f"/mnt/{drive}/{tail}")
    else:
        p = Path(s)
    return _rebase_to_current_repo(p)


def parse_kv(path: Path) -> Dict[str, str]:
    out: Dict[str, str] = {}
    if not path.is_file():
        return out
    for raw in path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        # Recorder/control files use unquoted scalar values; strip trailing comment.
        key, val = line.split("=", 1)
        key = key.strip()
        val = val.split("#", 1)[0].strip()
        if key:
            out[key] = val
    return out


def first_number(dicts: Sequence[Dict[str, str]], keys: Sequence[str], default: float) -> float:
    for d in dicts:
        for k in keys:
            if k in d:
                try:
                    return float(d[k])
                except ValueError:
                    pass
    return float(default)


def first_int(dicts: Sequence[Dict[str, str]], keys: Sequence[str], default: int) -> int:
    v = first_number(dicts, keys, float(default))
    return int(round(v))


def find_article_root(session: Path) -> Optional[Path]:
    """Find an ancestor that looks like the article run root."""
    for p in [session] + list(session.parents):
        if (p / "traceability.txt").is_file() or (p / "params").is_dir() and (p / "runs").is_dir():
            return p
    return None


def load_context(session: Path) -> Tuple[Dict[str, str], Dict[str, str], Dict[str, str], Optional[Path]]:
    manifest = parse_kv(session / "manifest.kv")
    article_root = find_article_root(session)
    trace = parse_kv(article_root / "traceability.txt") if article_root else {}
    # Params are not needed for field loading, but they provide dt/L if absent in manifest.
    params: Dict[str, str] = {}
    if article_root:
        if "closure" in session.parts:
            params = parse_kv(article_root / "params" / "closure_params_used.kv")
        elif "src" in session.parts:
            params = parse_kv(article_root / "params" / "src_params_used.kv")
    return manifest, trace, params, article_root


def list_field_steps(session: Path, field: str) -> List[int]:
    steps: List[int] = []
    for p in session.iterdir():
        if not p.is_file():
            continue
        m = FIELD_RE.match(p.name)
        if m and m.group(2).lower() == field.lower():
            steps.append(int(m.group(1)))
    return sorted(set(steps))


def field_path(session: Path, step: int, field: str) -> Path:
    return session / f"step_{step:010d}_field_{field}.f32"


def infer_shape_from_file(path: Path) -> Tuple[int, int]:
    n = path.stat().st_size // 4
    q = int(round(math.sqrt(n)))
    if q * q == n:
        return q, q
    raise RuntimeError(
        f"Cannot infer a rectangular grid from {path} ({n} float32 values). "
        "Provide --nx and --ny or ensure manifest.kv contains liveGridNx/liveGridNy."
    )


def resolve_grid(session: Path, manifest: Dict[str, str], params: Dict[str, str], nx_arg: int, ny_arg: int) -> Tuple[int, int]:
    dicts = [manifest, params]
    nx = nx_arg if nx_arg > 0 else first_int(dicts, ["liveGridNx", "recordGridNx", "gridNx", "Nx", "nx"], -1)
    ny = ny_arg if ny_arg > 0 else first_int(dicts, ["liveGridNy", "recordGridNy", "gridNy", "Ny", "ny"], -1)
    if nx > 0 and ny > 0:
        return nx, ny
    ux_steps = list_field_steps(session, "ux")
    if not ux_steps:
        raise RuntimeError(f"No ux recordings found in {session}")
    return infer_shape_from_file(field_path(session, ux_steps[0], "ux"))


def read_field(path: Path, nx: int, ny: int) -> np.ndarray:
    a = np.fromfile(path, dtype=np.float32)
    expected = nx * ny
    if a.size != expected:
        raise RuntimeError(f"Wrong field size: {path}: got {a.size} floats, expected {expected} ({nx}x{ny})")
    # Recorder convention: x varies fastest -> row-major reshape [Ny,Nx].
    return a.reshape((ny, nx)).astype(np.float64, copy=False)


def periodic_vorticity(ux: np.ndarray, uy: np.ndarray, dx: float, dy: float) -> np.ndarray:
    duy_dx = (np.roll(uy, -1, axis=1) - np.roll(uy, 1, axis=1)) / (2.0 * dx)
    dux_dy = (np.roll(ux, -1, axis=0) - np.roll(ux, 1, axis=0)) / (2.0 * dy)
    return duy_dx - dux_dy


def tg_reference(nx: int, ny: int, lx: float, ly: float, mx: int, my: int) -> Tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray]:
    dx, dy = lx / nx, ly / ny
    x = (np.arange(nx) + 0.5) * dx
    y = (np.arange(ny) + 0.5) * dy
    X, Y = np.meshgrid(x, y)
    kx = 2.0 * np.pi * mx / lx
    ky = 2.0 * np.pi * my / ly
    # Same convention as the solver forcing/generator.
    rx = np.sin(kx * X) * np.cos(ky * Y)
    ry = -np.cos(kx * X) * np.sin(ky * Y)
    return X, Y, rx, ry


def modal_metrics(ux: np.ndarray, uy: np.ndarray, rx: np.ndarray, ry: np.ndarray) -> Dict[str, float]:
    # Remove residual global drift before comparing with the zero-mean TG mode.
    uxc = ux - np.mean(ux)
    uyc = uy - np.mean(uy)
    ref2 = float(np.sum(rx * rx + ry * ry))
    u2 = float(np.sum(uxc * uxc + uyc * uyc))
    dot = float(np.sum(uxc * rx + uyc * ry))
    amp = dot / ref2 if ref2 > 0.0 else float("nan")
    coh = dot / math.sqrt(ref2 * u2) if ref2 > 0.0 and u2 > 0.0 else float("nan")
    resx = uxc - amp * rx
    resy = uyc - amp * ry
    res_rms = math.sqrt(float(np.mean(resx * resx + resy * resy)))
    coherent_rms = abs(amp) * math.sqrt(float(np.mean(rx * rx + ry * ry)))
    snr = coherent_rms / res_rms if res_rms > 0.0 else float("inf")
    speed_rms = math.sqrt(float(np.mean(uxc * uxc + uyc * uyc)))
    return {
        "A_TG": amp,
        "C_TG": coh,
        "coherentRms": coherent_rms,
        "residualRms": res_rms,
        "modalSNR": snr,
        "speedRms": speed_rms,
        "meanUx": float(np.mean(ux)),
        "meanUy": float(np.mean(uy)),
    }


def common_complete_steps(src: Path, closure: Path) -> List[int]:
    sets = []
    for session in [src, closure]:
        sets.append(set(list_field_steps(session, "ux")) & set(list_field_steps(session, "uy")))
    steps = sorted(sets[0] & sets[1])
    return steps


def common_field_steps(src: Path, closure: Path, field: str) -> List[int]:
    """Common recorded steps for one scalar field in both sessions."""
    return sorted(set(list_field_steps(src, field)) & set(list_field_steps(closure, field)))


def nearest_step(steps: Sequence[int], requested: Optional[int]) -> int:
    if not steps:
        raise RuntimeError("No common ux/uy frames.")
    if requested is None:
        return steps[-1]
    return min(steps, key=lambda s: abs(s - requested))


def block_quiver(ux: np.ndarray, uy: np.ndarray, lx: float, ly: float, qnx: int, qny: int):
    ny, nx = ux.shape
    x_edges = np.linspace(0, nx, qnx + 1, dtype=int)
    y_edges = np.linspace(0, ny, qny + 1, dtype=int)
    Xq = np.empty((qny, qnx), float)
    Yq = np.empty((qny, qnx), float)
    Uq = np.empty((qny, qnx), float)
    Vq = np.empty((qny, qnx), float)
    for j in range(qny):
        y0, y1 = y_edges[j], y_edges[j + 1]
        for i in range(qnx):
            x0, x1 = x_edges[i], x_edges[i + 1]
            Uq[j, i] = float(np.mean(ux[y0:y1, x0:x1]))
            Vq[j, i] = float(np.mean(uy[y0:y1, x0:x1]))
            Xq[j, i] = 0.5 * (x0 + x1) / nx * lx
            Yq[j, i] = 0.5 * (y0 + y1) / ny * ly
    return Xq, Yq, Uq, Vq


def characteristic_wavenumber(lx: float, ly: float, mx: int, my: int) -> float:
    """Characteristic TG wavenumber. For square (1,1), this is exactly 2*pi/L."""
    kx = 2.0 * math.pi * mx / lx
    ky = 2.0 * math.pi * my / ly
    return math.sqrt(0.5 * (kx * kx + ky * ky))


def tau_from_step(step: int, dt: float, k_char: float, u0: float) -> float:
    return float(step) * dt * k_char * abs(u0)


def nearest_step_for_tau(
    steps: Sequence[int], target_tau: float, dt: float, k_char: float, u0: float
) -> int:
    if not steps:
        raise RuntimeError("No common ux/uy frames.")
    return min(steps, key=lambda s: abs(tau_from_step(s, dt, k_char, u0) - target_tau))


def save_snapshot_grid(
    outdir: Path,
    src_session: Path,
    clo_session: Path,
    initial_step: int,
    evolved_step: int,
    nx: int,
    ny: int,
    lx: float,
    ly: float,
    dt: float,
    k_char: float,
    u0: float,
    qnx: int,
    qny: int,
    vort_percentile: float,
    vort_clip: float,
    quiver_scale: float,
) -> Tuple[Path, Path]:
    # Four panels: columns are formulations, rows are first/evolved recorded times.
    specs = [
        (0, 0, "SRC", src_session, initial_step),
        (0, 1, "SRC + particle/field closure", clo_session, initial_step),
        (1, 0, "SRC", src_session, evolved_step),
        (1, 1, "SRC + particle/field closure", clo_session, evolved_step),
    ]
    records = []
    for row, col, label, session, step in specs:
        ux = read_field(field_path(session, step, "ux"), nx, ny)
        uy = read_field(field_path(session, step, "uy"), nx, ny)
        w = periodic_vorticity(ux, uy, lx / nx, ly / ny)
        records.append((row, col, label, step, ux, uy, w))

    if vort_clip > 0.0:
        clip = vort_clip
    else:
        all_abs = np.concatenate([np.abs(r[6]).ravel() for r in records])
        finite = all_abs[np.isfinite(all_abs)]
        clip = float(np.percentile(finite, vort_percentile)) if finite.size else 1.0
        if not np.isfinite(clip) or clip <= 0.0:
            clip = 1.0

    fig, axes = plt.subplots(2, 2, figsize=(12.0, 10.2), constrained_layout=True)
    im = None
    panel_letters = {(0,0): "(a)", (0,1): "(b)", (1,0): "(c)", (1,1): "(d)"}
    for row, col, label, step, ux, uy, w in records:
        ax = axes[row, col]
        im = ax.imshow(
            w, origin="lower", extent=(0.0, lx, 0.0, ly), cmap="RdBu_r",
            vmin=-clip, vmax=clip, interpolation="nearest", aspect="equal",
        )
        Xq, Yq, Uq, Vq = block_quiver(ux, uy, lx, ly, qnx, qny)
        ax.quiver(
            Xq, Yq, Uq, Vq, color="black", angles="xy", scale_units="xy",
            scale=quiver_scale, width=0.0022, headwidth=3.2, headlength=4.2,
            headaxislength=3.8,
        )
        tau = tau_from_step(step, dt, k_char, u0)
        tau_label = r"$\tau\simeq 0$" if row == 0 else rf"$\tau={tau:.2f}$"
        ax.set_title(f"{panel_letters[(row,col)]}  {label} — {tau_label}")
        ax.set_xlabel("x/L")
        ax.set_ylabel("y/L")
        ax.set_xlim(0.0, lx)
        ax.set_ylim(0.0, ly)
        # Display physical coordinates normalized by L when square/unit-box assumptions do not hold.
        if lx != 1.0:
            ticks = ax.get_xticks()
            ax.set_xticklabels([f"{v/lx:.1f}" for v in ticks])
        if ly != 1.0:
            ticks = ax.get_yticks()
            ax.set_yticklabels([f"{v/ly:.1f}" for v in ticks])

    assert im is not None
    cbar = fig.colorbar(im, ax=axes.ravel().tolist(), shrink=0.88, pad=0.02)
    cbar.set_label(r"vorticity $\omega_z=\partial_xu_y-\partial_yu_x$")
    fig.suptitle(
        r"Recorded LiveVis fields: common initial state and evolved Taylor--Green response"
        + "\n" + rf"$\tau=k_{{\rm char}}U_0 t$,  $k_{{\rm char}}={k_char:.4g}$",
        fontsize=14,
    )
    png = outdir / "fig_livevis_vorticity_quiver_2x2_tau.png"
    pdf = outdir / "fig_livevis_vorticity_quiver_2x2_tau.pdf"
    fig.savefig(png, dpi=240, bbox_inches="tight")
    fig.savefig(pdf, bbox_inches="tight")
    plt.close(fig)
    return png, pdf



def _conservative_rebin_counts_axis(a: np.ndarray, new_n: int, axis: int) -> np.ndarray:
    """Conservatively remap cell particle COUNTS along one axis."""
    a = np.asarray(a, dtype=np.float64)
    old_n = a.shape[axis]
    if new_n <= 0:
        raise ValueError("new_n must be positive")
    if old_n == new_n:
        return a.copy()
    moved = np.moveaxis(a, axis, -1)
    out = np.zeros(moved.shape[:-1] + (new_n,), dtype=np.float64)
    scale = float(old_n) / float(new_n)
    for j in range(new_n):
        a0 = j * scale
        a1 = (j + 1) * scale
        i0 = max(0, int(math.floor(a0)))
        i1 = min(old_n - 1, int(math.ceil(a1) - 1))
        for i in range(i0, i1 + 1):
            overlap = max(0.0, min(a1, i + 1.0) - max(a0, float(i)))
            if overlap > 0.0:
                out[..., j] += moved[..., i] * overlap
    return np.moveaxis(out, -1, axis)


def conservative_rebin_counts_2d(n_live: np.ndarray, solver_nx: int, solver_ny: int) -> np.ndarray:
    """Remap LiveVis count cells to MPCD collision cells with particle-number conservation."""
    a = np.asarray(n_live, dtype=np.float64)
    if a.ndim != 2:
        raise ValueError("n_live must be 2-D")
    if not np.all(np.isfinite(a)):
        bad = int(a.size - np.count_nonzero(np.isfinite(a)))
        raise RuntimeError(f"Recorded n field contains {bad} non-finite values")
    if float(np.min(a)) < -1.0e-6:
        raise RuntimeError(f"Recorded n field contains negative counts: min={np.min(a):.9g}")
    a = np.maximum(a, 0.0)
    tmp = _conservative_rebin_counts_axis(a, solver_nx, axis=1)
    out = _conservative_rebin_counts_axis(tmp, solver_ny, axis=0)
    s0=float(np.sum(a)); s1=float(np.sum(out))
    tol=max(1e-9*max(abs(s0),1.0),1e-7)
    if not math.isfinite(s1) or abs(s1-s0)>tol:
        raise RuntimeError(f"Non-conservative population remap: live={s0:.17g} solver={s1:.17g}")
    return out

def save_population_grid(
    outdir: Path,
    src_session: Path,
    clo_session: Path,
    initial_step: int,
    final_step: int,
    nx: int,
    ny: int,
    solver_nx: int,
    solver_ny: int,
    gamma: float,
    lx: float,
    ly: float,
    dt: float,
    k_char: float,
    u0: float,
    n_percentile: float,
    n_clip: float,
) -> Tuple[Path, Path, Dict[str, float]]:
    """Four-panel solver-cell occupancy reconstructed from recorded LiveVis n counts."""
    if solver_nx <= 0 or solver_ny <= 0:
        raise RuntimeError("Solver grid is required to reconstruct solver-cell occupancy")

    specs = [
        (0, 0, "SRC", src_session, initial_step),
        (0, 1, "SRC + particle/field closure", clo_session, initial_step),
        (1, 0, "SRC", src_session, final_step),
        (1, 1, "SRC + particle/field closure", clo_session, final_step),
    ]
    records=[]
    stats: Dict[str,float] = {
        "populationMeanScaleLiveToSolver": (float(nx)*float(ny))/(float(solver_nx)*float(solver_ny))
    }
    for row,col,label,session,step in specs:
        n_live=read_field(field_path(session,step,"n"),nx,ny)
        n_eq=conservative_rebin_counts_2d(n_live,solver_nx,solver_ny)
        records.append((row,col,label,step,n_eq))
        key=("src" if label=="SRC" else "closure")+("Initial" if row==0 else "Final")
        stats[key+"MeanNeq"]=float(np.mean(n_eq))
        stats[key+"StdNeq"]=float(np.std(n_eq))
        stats[key+"MinNeq"]=float(np.min(n_eq))
        stats[key+"MaxNeq"]=float(np.max(n_eq))
        stats[key+"TotalParticles"]=float(np.sum(n_eq))

    if n_clip>0.0:
        delta=float(n_clip)
    else:
        dev=np.concatenate([np.abs(r[4]-gamma).ravel() for r in records])
        dev=dev[np.isfinite(dev)]
        p=min(100.0,max(0.0,float(n_percentile)))
        delta=float(np.percentile(dev,p)) if dev.size else float('nan')
        if not math.isfinite(delta) or delta<=1e-12:
            vals=np.concatenate([r[4].ravel() for r in records])
            vals=vals[np.isfinite(vals)]
            if vals.size:
                delta=max(gamma-float(np.min(vals)),float(np.max(vals))-gamma)
        if not math.isfinite(delta) or delta<=1e-12:
            delta=max(1.0,0.25*abs(gamma))

    # Symmetric linear limits around gamma: midpoint is exactly gamma without TwoSlopeNorm.
    vmin=gamma-delta
    vmax=gamma+delta
    if not (math.isfinite(vmin) and math.isfinite(vmax) and vmin<gamma<vmax):
        raise RuntimeError(f"Invalid population color range: {vmin}, {gamma}, {vmax}")
    stats["populationColorDeltaAroundGamma"]=delta
    stats["populationColorMin"]=vmin
    stats["populationColorMax"]=vmax

    fig,axes=plt.subplots(2,2,figsize=(12.0,10.0),constrained_layout=True)
    letters={(0,0):"(a)",(0,1):"(b)",(1,0):"(c)",(1,1):"(d)"}
    im=None
    for row,col,label,step,n_eq in records:
        ax=axes[row,col]
        im=ax.imshow(
            n_eq, origin="lower", extent=(0.0,lx,0.0,ly), cmap="RdBu_r",
            vmin=vmin, vmax=vmax, interpolation="nearest", aspect="equal"
        )
        tau=tau_from_step(step,dt,k_char,u0)
        tlab=r"$\tau\simeq0$" if row==0 else rf"$\tau={tau:.2f}$"
        ax.set_title(f"{letters[(row,col)]}  {label} — {tlab}\n"+rf"$\langle N\rangle={np.mean(n_eq):.3f}$")
        ax.set_xlabel("x/L"); ax.set_ylabel("y/L")
        ax.set_xlim(0.0,lx); ax.set_ylim(0.0,ly)
        if lx!=1.0:
            ticks=ax.get_xticks(); ax.set_xticklabels([f"{v/lx:.1f}" for v in ticks])
        if ly!=1.0:
            ticks=ax.get_yticks(); ax.set_yticklabels([f"{v/ly:.1f}" for v in ticks])

    assert im is not None
    cbar=fig.colorbar(im,ax=axes.ravel().tolist(),shrink=0.86,pad=0.025,fraction=0.045)
    cbar.set_label(r"MPCD solver-cell occupancy  $N$")
    ticks=np.linspace(vmin,vmax,5)
    cbar.set_ticks(ticks)
    cbar.set_ticklabels([f"{x:.2f}" for x in ticks])
    fig.suptitle(
        "Recorded LiveVis particle population conservatively remapped to the MPCD collision grid\n"
        +rf"$\langle N\rangle\simeq\gamma$, nominal $\gamma={gamma:g}$; "
         rf"LiveVis ${nx}\times{ny}\rightarrow$ solver ${solver_nx}\times{solver_ny}$",
        fontsize=14,
    )
    png=outdir/"fig_livevis_population_2x2_tau.png"
    pdf=outdir/"fig_livevis_population_2x2_tau.pdf"
    fig.savefig(png,dpi=240,bbox_inches="tight")
    fig.savefig(pdf,bbox_inches="tight")
    plt.close(fig)
    return png,pdf,stats


def write_metrics_csv(path: Path, rows: Sequence[Dict[str, object]]) -> None:
    if not rows:
        return
    keys = list(rows[0].keys())
    with path.open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=keys)
        w.writeheader()
        w.writerows(rows)


def forced_tg_theory_amplitude(
    time: np.ndarray | float, a_initial: float, forcing: float, nu: float, k_char: float
) -> np.ndarray:
    """Linear forced TG amplitude: dA/dt = F - 2*nu*k_char^2*A."""
    t = np.asarray(time, dtype=float)
    decay = 2.0 * nu * k_char * k_char
    if not np.isfinite(decay) or decay <= 0.0:
        return np.full_like(t, np.nan, dtype=float)
    a_inf = forcing / decay
    return a_inf + (a_initial - a_inf) * np.exp(-decay * t)


def save_metric_plot(
    outdir: Path,
    rows: Sequence[Dict[str, object]],
    first_amp_by_mode: Dict[str, float],
    theory_nu: float,
    theory_force: float,
    theory_a0: float,
    k_char: float,
    u0: float,
) -> Tuple[Path, Path]:
    by_mode: Dict[str, List[Dict[str, object]]] = {}
    for r in rows:
        by_mode.setdefault(str(r["mode"]), []).append(r)

    fig, axes = plt.subplots(2, 1, figsize=(9.4, 7.2), sharex=True, constrained_layout=True)
    for mode, rr in by_mode.items():
        rr = sorted(rr, key=lambda x: int(x["step"]))
        tau = np.array([float(x["tau"]) for x in rr])
        a = np.array([float(x["A_TG"]) for x in rr])
        c = np.array([float(x["C_TG"]) for x in rr])
        a0 = float(first_amp_by_mode[mode])
        an = a / a0
        axes[0].plot(tau, an, marker="o", markersize=3.3, linewidth=1.6, label=mode)
        axes[1].plot(tau, c, marker="o", markersize=3.3, linewidth=1.6, label=mode)

    # Parameter-free linear forced-TG prediction for the closure viscosity.
    # Normalize by the theory value at the first recorded time, exactly as the
    # numerical curves are normalized by their first recorded frame.
    all_tau = np.array(sorted(set(float(r["tau"]) for r in rows)), dtype=float)
    if (all_tau.size and np.isfinite(theory_nu) and theory_nu > 0.0
            and np.isfinite(theory_force) and np.isfinite(theory_a0)
            and np.isfinite(u0) and abs(u0) > 0.0):
        tau_dense = np.linspace(float(all_tau[0]), float(all_tau[-1]), 500)
        t_dense = tau_dense / (k_char * abs(u0))
        t0 = float(all_tau[0]) / (k_char * abs(u0))
        a_theory = forced_tg_theory_amplitude(t_dense, theory_a0, theory_force, theory_nu, k_char)
        a_theory0 = float(forced_tg_theory_amplitude(np.array([t0]), theory_a0, theory_force, theory_nu, k_char)[0])
        if np.isfinite(a_theory0) and abs(a_theory0) > 1e-15:
            axes[0].plot(
                tau_dense, a_theory / a_theory0, linestyle="--", linewidth=2.0,
                color="black", label=rf"forced-TG theory ($\nu={theory_nu:.3g}$)",
            )

    axes[0].axhline(1.0, linestyle=":", linewidth=1.0, color="0.45")
    axes[0].set_ylabel(r"normalized TG amplitude  $A_{TG}(\tau)/A_{TG}(\tau_0)$")
    axes[0].grid(alpha=0.25)
    axes[0].legend(loc="best")

    axes[1].axhline(1.0, linestyle="--", linewidth=0.9, color="0.55")
    axes[1].axhline(0.0, linestyle=":", linewidth=0.8, color="0.65")
    axes[1].set_ylabel(r"TG velocity correlation  $C_{TG}$")
    axes[1].set_xlabel(r"nondimensional time  $\tau=k_{\rm char}U_0t$")
    axes[1].grid(alpha=0.25)
    axes[1].legend(loc="best")

    png = outdir / "fig_livevis_tg_modal_metrics_vs_tau.png"
    pdf = outdir / "fig_livevis_tg_modal_metrics_vs_tau.pdf"
    fig.savefig(png, dpi=240, bbox_inches="tight")
    fig.savefig(pdf, bbox_inches="tight")
    plt.close(fig)
    return png, pdf


def summarize(
    rows: Sequence[Dict[str, object]], first_amp_by_mode: Dict[str, float], tail_fraction: float
) -> Dict[str, Dict[str, float]]:
    out: Dict[str, Dict[str, float]] = {}
    modes = sorted(set(str(r["mode"]) for r in rows))
    for mode in modes:
        rr = [r for r in rows if str(r["mode"]) == mode]
        rr.sort(key=lambda x: int(x["step"]))
        n_tail = max(1, int(math.ceil(len(rr) * tail_fraction)))
        tail = rr[-n_tail:]
        vals = lambda key: np.array([float(x[key]) for x in tail], dtype=float)
        a0 = float(first_amp_by_mode[mode])
        out[mode] = {
            "tailFrames": float(n_tail),
            "tailStartTau": float(tail[0]["tau"]),
            "meanA_TG": float(np.mean(vals("A_TG"))),
            "stdA_TG": float(np.std(vals("A_TG"), ddof=1)) if n_tail > 1 else 0.0,
            "meanANormalizedToFirstFrame": float(np.mean(vals("A_TG")) / a0),
            "meanC_TG": float(np.mean(vals("C_TG"))),
            "stdC_TG": float(np.std(vals("C_TG"), ddof=1)) if n_tail > 1 else 0.0,
            "meanModalSNR": float(np.mean(vals("modalSNR"))),
        }
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description="Analyze SRC vs liquid-closure LiveVis TG recordings.")
    ap.add_argument("--src", default=DEFAULT_SRC, help="SRC recording session directory")
    ap.add_argument("--closure", default=DEFAULT_CLOSURE, help="closure recording session directory")
    ap.add_argument("--output", default="", help="output directory; default: <common article root>/analysis_livevis_tg")
    ap.add_argument(
        "--snapshot-tau", type=float, default=float("nan"),
        help="target nondimensional time for evolved snapshot; if omitted, use the last common recorded ux/uy frame",
    )
    ap.add_argument("--snapshot-step", type=int, default=None, help="expert override: evolved snapshot solver step; takes precedence over --snapshot-tau")
    ap.add_argument("--nx", type=int, default=-1, help="override recorded Nx")
    ap.add_argument("--ny", type=int, default=-1, help="override recorded Ny")
    ap.add_argument("--lx", type=float, default=float("nan"), help="override Lx")
    ap.add_argument("--ly", type=float, default=float("nan"), help="override Ly")
    ap.add_argument("--dt", type=float, default=float("nan"), help="override dt")
    ap.add_argument(
        "--u0", type=float, default=float("nan"),
        help="TG reference amplitude; auto from run metadata (U0), fallback first closure modal amplitude; use --u0 only as an explicit override",
    )
    ap.add_argument("--mode-x", type=int, default=-1, help="TG mode x; auto/fallback 1")
    ap.add_argument("--mode-y", type=int, default=-1, help="TG mode y; auto/fallback 1")
    ap.add_argument("--quiver-nx", type=int, default=25)
    ap.add_argument("--quiver-ny", type=int, default=25)
    ap.add_argument("--quiver-scale", type=float, default=5.0, help="shared matplotlib quiver scale; larger means shorter arrows")
    ap.add_argument("--vort-percentile", type=float, default=99.0, help="shared symmetric vorticity clip percentile")
    ap.add_argument("--vort-clip", type=float, default=-1.0, help="explicit symmetric vorticity clip; <=0 uses percentile")
    ap.add_argument("--gamma", type=float, default=float("nan"), help="mean solver-cell occupancy; auto from run metadata")
    ap.add_argument("--solver-nx", type=int, default=-1, help="original solver Nx for n-field rescaling; auto from params")
    ap.add_argument("--solver-ny", type=int, default=-1, help="original solver Ny for n-field rescaling; auto from params")
    ap.add_argument("--n-percentile", type=float, default=99.0, help="percentile of |N_eq-gamma| used for the common population color scale")
    ap.add_argument("--n-clip", type=float, default=-1.0, help="explicit half-width of population color scale around gamma; <=0 uses percentile")
    ap.add_argument("--tail-fraction", type=float, default=0.5, help="late-time fraction used in text summary")
    ap.add_argument(
        "--theory-nu", type=float, default=0.0005101978801036144,
        help="kinematic viscosity for the linear forced-TG theory; default is the measured closure viscosity",
    )
    ap.add_argument(
        "--theory-force", type=float, default=float("nan"),
        help="TG forcing amplitude for theory; auto from run metadata, fallback 0.041",
    )
    ap.add_argument(
        "--theory-a0", type=float, default=float("nan"),
        help="physical TG amplitude at t=0 for theory; default uses U0",
    )
    args = ap.parse_args()

    src = normalize_path(args.src).resolve()
    clo = normalize_path(args.closure).resolve()
    if not src.is_dir():
        raise SystemExit(f"SRC recording directory not found: {src}")
    if not clo.is_dir():
        raise SystemExit(f"Closure recording directory not found: {clo}")

    sm, st, sp, sroot = load_context(src)
    cm, ct, cp, croot = load_context(clo)

    snx, sny = resolve_grid(src, sm, sp, args.nx, args.ny)
    cnx, cny = resolve_grid(clo, cm, cp, args.nx, args.ny)
    if (snx, sny) != (cnx, cny):
        raise SystemExit(f"Recorded grid mismatch: SRC={snx}x{sny}, closure={cnx}x{cny}")
    nx, ny = snx, sny

    dicts = [cm, ct, cp, sm, st, sp]
    lx = args.lx if math.isfinite(args.lx) else first_number(dicts, ["Lx", "lx"], 1.0)
    ly = args.ly if math.isfinite(args.ly) else first_number(dicts, ["Ly", "ly"], 1.0)
    dt = args.dt if math.isfinite(args.dt) else first_number(dicts, ["dt", "DT"], 1.0)
    mx = args.mode_x if args.mode_x > 0 else first_int(dicts, ["taylorGreenForcingModeX", "TG_FORCING_MODE_X"], 1)
    my = args.mode_y if args.mode_y > 0 else first_int(dicts, ["taylorGreenForcingModeY", "TG_FORCING_MODE_Y"], 1)

    # Original MPCD grid and mean occupancy are distinct from the LiveVis grid.
    # Prefer params/traceability so liveGridNx/liveGridNy can never shadow Nx/Ny.
    solver_dicts = [cp, sp, ct, st, cm, sm]
    solver_nx = args.solver_nx if args.solver_nx > 0 else first_int(solver_dicts, ["Nx", "NX", "solverNx"], -1)
    solver_ny = args.solver_ny if args.solver_ny > 0 else first_int(solver_dicts, ["Ny", "NY", "solverNy"], -1)
    gamma = args.gamma if math.isfinite(args.gamma) and args.gamma > 0.0 else first_number(
        solver_dicts, ["gamma", "GAMMA", "resamplingTargetCellMass"], float("nan")
    )

    steps = common_complete_steps(src, clo)
    if not steps:
        raise SystemExit("No common complete ux/uy frames between SRC and closure sessions.")

    # U0: explicit CLI override > run metadata > first closure modal coefficient.
    # Do NOT hard-code a campaign-specific U0 here: tau = k_char*U0*t, so a
    # stale U0 directly corrupts every nondimensional-time label.
    if math.isfinite(args.u0) and args.u0 != 0.0:
        u0 = float(args.u0)
        u0_source = "CLI --u0"
    else:
        u0 = first_number(dicts, ["U0", "u0"], float("nan"))
        u0_source = "run metadata"

    X, Y, rx, ry = tg_reference(nx, ny, lx, ly, mx, my)
    k_char = characteristic_wavenumber(lx, ly, mx, my)

    rows: List[Dict[str, object]] = []
    first_closure_amp = float("nan")
    for label, session in [("SRC", src), ("SRC + particle/field closure", clo)]:
        for step in steps:
            ux = read_field(field_path(session, step, "ux"), nx, ny)
            uy = read_field(field_path(session, step, "uy"), nx, ny)
            m = modal_metrics(ux, uy, rx, ry)
            if label.startswith("SRC +") and not math.isfinite(first_closure_amp):
                first_closure_amp = abs(m["A_TG"])
            rows.append({
                "mode": label,
                "step": step,
                "time": step * dt,
                **m,
            })

    if not math.isfinite(u0) or u0 == 0.0:
        u0 = first_closure_amp
        u0_source = "first closure modal amplitude fallback"
        if not math.isfinite(u0) or u0 == 0.0:
            raise SystemExit("Cannot resolve U0. Supply --u0 explicitly.")
        print(f"[livevis-tg] WARNING U0 unavailable in metadata; using first closure modal amplitude U0={u0:.9g}")

    if math.isfinite(first_closure_amp) and abs(u0) > 0.0:
        ratio=abs(first_closure_amp)/abs(u0)
        if ratio < 0.5 or ratio > 1.5:
            print(
                "[livevis-tg] WARNING U0 differs strongly from first closure modal amplitude: "
                f"U0={u0:.9g}, A_TG(first closure)={first_closure_amp:.9g}, ratio={ratio:.3f}. "
                "Check --u0 if this campaign uses another initial amplitude."
            )

    theory_nu = float(args.theory_nu)
    theory_force = (
        float(args.theory_force)
        if math.isfinite(args.theory_force)
        else first_number(dicts, ["taylorGreenForcingAmplitude", "TG_FORCING_AMPLITUDE"], 0.0410)
    )
    theory_a0 = float(args.theory_a0) if math.isfinite(args.theory_a0) else float(u0)
    theory_decay = 2.0 * theory_nu * k_char * k_char
    theory_ainf = theory_force / theory_decay if theory_decay > 0.0 else float("nan")

    # Publication time coordinate and per-run amplitude normalization.
    for r in rows:
        r["tau"] = float(r["time"]) * k_char * abs(u0)
    first_amp_by_mode: Dict[str, float] = {}
    for mode in sorted(set(str(r["mode"]) for r in rows)):
        rr = sorted((r for r in rows if str(r["mode"]) == mode), key=lambda x: int(x["step"]))
        a0 = float(rr[0]["A_TG"])
        if not math.isfinite(a0) or abs(a0) < 1e-15:
            raise SystemExit(f"First recorded A_TG is unusable for normalization in mode {mode}: {a0}")
        first_amp_by_mode[mode] = a0
        for r in rr:
            r["A_TG_over_A0"] = float(r["A_TG"]) / a0

    if args.output:
        outdir = normalize_path(args.output).resolve()
    else:
        roots = [p for p in [sroot, croot] if p is not None]
        if len(roots) == 2 and roots[0] == roots[1]:
            outdir = roots[0] / "analysis_livevis_tg"
        else:
            common = Path(os.path.commonpath([str(src), str(clo)]))
            outdir = common / "analysis_livevis_tg"
    outdir = _rebase_to_current_repo(outdir)
    outdir.mkdir(parents=True, exist_ok=True)
    print(f"[livevis-tg] output directory={outdir}")

    # Probe the exact destination now, before Matplotlib/PIL tries to create a PNG.
    # This turns opaque WSL/DrvFS EINVAL failures into an immediate path diagnostic.
    probe = outdir / ".livevis_tg_write_probe"
    try:
        with probe.open("wb") as f:
            f.write(b"ok\n")
        probe.unlink()
    except OSError as exc:
        raise SystemExit(
            f"Cannot write to analysis output directory {outdir}: {exc}. "
            "If running under WSL, launch the script from the real SRC_GPU-SURF "
            "repository directory or pass --output to a writable native path."
        ) from exc

    metrics_path = outdir / "tg_livevis_metrics.csv"
    write_metrics_csv(metrics_path, rows)

    initial_step = steps[0]
    if args.snapshot_step is not None:
        evolved_step = nearest_step(steps, args.snapshot_step)
    elif math.isfinite(args.snapshot_tau):
        evolved_step = nearest_step_for_tau(steps, args.snapshot_tau, dt, k_char, u0)
    else:
        # Publication default: compare the common initial state with the last
        # common recorded velocity field, independent of the campaign's U0.
        evolved_step = steps[-1]
    snap_png, snap_pdf = save_snapshot_grid(
        outdir, src, clo, initial_step, evolved_step, nx, ny, lx, ly, dt, k_char, u0,
        max(2, args.quiver_nx), max(2, args.quiver_ny),
        args.vort_percentile, args.vort_clip, args.quiver_scale,
    )
    met_png, met_pdf = save_metric_plot(
        outdir, rows, first_amp_by_mode, theory_nu, theory_force, theory_a0, k_char, u0
    )

    # Population migration diagnostic: first and last common recorded n field.
    n_steps = common_field_steps(src, clo, "n")
    pop_png = pop_pdf = None
    pop_stats: Dict[str, float] = {}
    if n_steps:
        if solver_nx <= 0 or solver_ny <= 0:
            raise SystemExit(
                "Recorded n fields were found but original solver Nx/Ny could not be resolved. "
                "Supply --solver-nx and --solver-ny."
            )
        if not math.isfinite(gamma) or gamma <= 0.0:
            raise SystemExit(
                "Recorded n fields were found but gamma could not be resolved. Supply --gamma."
            )
        pop_initial_step = n_steps[0]
        pop_final_step = n_steps[-1]
        pop_png, pop_pdf, pop_stats = save_population_grid(
            outdir, src, clo, pop_initial_step, pop_final_step, nx, ny,
            solver_nx, solver_ny, gamma, lx, ly, dt, k_char, u0,
            args.n_percentile, args.n_clip,
        )
    else:
        print("[livevis-tg] WARNING no common recorded n fields; population figure not produced")

    summ = summarize(rows, first_amp_by_mode, max(1e-6, min(1.0, args.tail_fraction)))
    summary_path = outdir / "tg_livevis_summary.txt"
    with summary_path.open("w", encoding="utf-8") as f:
        f.write("===== LIVEVIS FORCED TAYLOR--GREEN COMPARISON =====\n")
        f.write(f"srcSession={src}\n")
        f.write(f"closureSession={clo}\n")
        f.write(f"grid={nx}x{ny} L={lx}x{ly} dt={dt:.17g}\n")
        f.write(f"TGmode=({mx},{my}) U0={u0:.17g} kChar={k_char:.17g}\n")
        f.write(f"U0source={u0_source}\n")
        f.write(f"tauDefinition=kChar*abs(U0)*t; for square (1,1), kChar=2*pi/L\n")
        f.write(
            f"theory: dA/dt=F-2*nu*kChar^2*A; nu={theory_nu:.17g} "
            f"F={theory_force:.17g} A0={theory_a0:.17g} "
            f"decay={theory_decay:.17g} Ainf={theory_ainf:.17g}\n"
        )
        f.write(f"commonFrames={len(steps)} firstTau={tau_from_step(steps[0],dt,k_char,u0):.17g} lastTau={tau_from_step(steps[-1],dt,k_char,u0):.17g} evolvedSnapshotTau={tau_from_step(evolved_step,dt,k_char,u0):.17g}\n")
        f.write(f"initialSnapshotStep={initial_step} evolvedSnapshotStep={evolved_step}\n")
        theory_t0 = steps[0] * dt
        theory_te = evolved_step * dt
        theory_a_first = float(forced_tg_theory_amplitude(np.array([theory_t0]), theory_a0, theory_force, theory_nu, k_char)[0])
        theory_a_evolved = float(forced_tg_theory_amplitude(np.array([theory_te]), theory_a0, theory_force, theory_nu, k_char)[0])
        theory_norm_evolved = theory_a_evolved / theory_a_first if abs(theory_a_first) > 1e-15 else float("nan")
        f.write(f"theoryNormalizedAtEvolvedSnapshot={theory_norm_evolved:.17g}\n")
        if pop_stats:
            f.write(
                f"populationRemap: liveGrid={nx}x{ny} solverGrid={solver_nx}x{solver_ny} "
                f"gamma={gamma:.17g} scale={pop_stats['populationMeanScaleLiveToSolver']:.17g}\n"
            )
            f.write(
                f"populationFrames: initialStep={n_steps[0]} initialTau={tau_from_step(n_steps[0],dt,k_char,u0):.17g} "
                f"finalStep={n_steps[-1]} finalTau={tau_from_step(n_steps[-1],dt,k_char,u0):.17g}\n"
            )
            for key in sorted(pop_stats):
                f.write(f"population_{key}={pop_stats[key]:.17g}\n")
        f.write("metricDefinition: A_TG=<u.u_TG>/<u_TG.u_TG>; normalized amplitude=A_TG/A_TG(first recorded frame of same run); C_TG=<u.u_TG>/sqrt(<u.u><u_TG.u_TG>) after removing global mean velocity\n")
        f.write("vorticityDefinition: omega_z=d(uy)/dx-d(ux)/dy, periodic centered differences\n\n")
        for mode, ss in summ.items():
            f.write(mode + "\n")
            for k, v in ss.items():
                f.write(f"  {k}={v:.17g}\n")
            f.write("\n")

    print("[livevis-tg] PASS")
    print(f"[livevis-tg] grid={nx}x{ny} L={lx}x{ly} dt={dt:.9g} mode=({mx},{my}) U0={u0:.9g} kChar={k_char:.9g}")
    print(f"[livevis-tg] U0 source={u0_source}")
    print(f"[livevis-tg] common frames={len(steps)} tau range={tau_from_step(steps[0],dt,k_char,u0):.6g}..{tau_from_step(steps[-1],dt,k_char,u0):.6g} evolved snapshot tau={tau_from_step(evolved_step,dt,k_char,u0):.6g}")
    print(f"[livevis-tg] theory nu={theory_nu:.9g} F={theory_force:.9g} A0={theory_a0:.9g} Ainf={theory_ainf:.9g}")
    print(f"[livevis-tg] metrics={metrics_path}")
    print(f"[livevis-tg] snapshot={snap_png}")
    print(f"[livevis-tg] modal plot={met_png}")
    if pop_png is not None:
        print(f"[livevis-tg] population={pop_png}")
        print(
            f"[livevis-tg] population conservative remap live={nx}x{ny} -> solver={solver_nx}x{solver_ny} "
            f"gamma={gamma:.9g} scale={pop_stats['populationMeanScaleLiveToSolver']:.9g}"
        )
    print(f"[livevis-tg] summary={summary_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
