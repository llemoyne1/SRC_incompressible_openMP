#!/usr/bin/env python3
"""
Analyze Taylor--Green vortex-core particle occupancy from recorded LiveVis n fields.

For each common recorded frame in SRC and SRC+closure:
  1. read step_<step>_field_n.f32 on the LiveVis grid,
  2. conservatively remap particle COUNTS to the actual MPCD collision grid,
  3. compute the mean occupancy <N> over the whole periodic domain,
  4. compute N_core over circular disks centered on all Taylor--Green vortex cores,
  5. report R_core = N_core / <N>.

Default core radius: 2 MPCD cells (historical TG-core definition).
The radius can be changed with --core-radius-cells.

Outputs:
  tg_core_population_metrics.csv
  tg_core_population_summary.txt
  fig_tg_core_population_ratio_vs_tau.png/.pdf

Dependencies: numpy, matplotlib. No pandas/scipy.
"""

from __future__ import annotations

import argparse
import csv
import math
import os
import re
from pathlib import Path
from typing import Dict, List, Optional, Sequence, Tuple

import numpy as np

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt


FIELD_RE = re.compile(r"^step_(\d+)_field_([A-Za-z0-9_]+)\.f32$")


def _rebase_to_current_repo(path: Path) -> Path:
    """Preserve the exact WSL/DrvFS spelling/case of the current repository."""
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
    return cwd.joinpath(*parts[repo_idx + 1:])


def normalize_path(text: str) -> Path:
    s = os.path.expandvars(os.path.expanduser(str(text).strip()))
    m = re.match(r"^([A-Za-z]):[\\/](.*)$", s)
    if m and os.name != "nt":
        p = Path(f"/mnt/{m.group(1).lower()}/{m.group(2).replace(chr(92), '/')}")
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
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.split("#", 1)[0].strip()
        if key:
            out[key] = value
    return out


def first_number(dicts: Sequence[Dict[str, str]], keys: Sequence[str], default: float) -> float:
    for d in dicts:
        for key in keys:
            if key in d:
                try:
                    return float(d[key])
                except ValueError:
                    pass
    return float(default)


def first_int(dicts: Sequence[Dict[str, str]], keys: Sequence[str], default: int) -> int:
    return int(round(first_number(dicts, keys, float(default))))


def list_field_steps(session: Path, field: str) -> List[int]:
    out: List[int] = []
    for p in session.iterdir():
        if not p.is_file():
            continue
        m = FIELD_RE.match(p.name)
        if m and m.group(2).lower() == field.lower():
            out.append(int(m.group(1)))
    return sorted(set(out))


def field_path(session: Path, step: int, field: str) -> Path:
    return session / f"step_{step:010d}_field_{field}.f32"


def find_article_root(session: Path) -> Optional[Path]:
    for p in [session] + list(session.parents):
        if (p / "traceability.txt").is_file():
            return p
        if (p / "params").is_dir() and (p / "runs").is_dir():
            return p
    return None


def load_context(session: Path) -> Tuple[Dict[str, str], Dict[str, str], Dict[str, str], Optional[Path]]:
    manifest = parse_kv(session / "manifest.kv")
    root = find_article_root(session)
    trace = parse_kv(root / "traceability.txt") if root else {}
    params: Dict[str, str] = {}
    if root:
        if "closure" in session.parts:
            params = parse_kv(root / "params" / "closure_params_used.kv")
        elif "src" in session.parts:
            params = parse_kv(root / "params" / "src_params_used.kv")
    return manifest, trace, params, root


def latest_recording_session(recordings_dir: Path) -> Optional[Path]:
    if not recordings_dir.is_dir():
        return None
    candidates = []
    for p in recordings_dir.iterdir():
        if p.is_dir() and list_field_steps(p, "n"):
            candidates.append(p)
    if not candidates:
        return None
    return max(candidates, key=lambda p: p.stat().st_mtime)


def discover_latest_article_root(repo: Path) -> Optional[Path]:
    candidates = []
    for p in repo.glob("article_forced_tg*"):
        if not p.is_dir():
            continue
        s = latest_recording_session(p / "runs" / "src" / "output" / "recordings")
        c = latest_recording_session(p / "runs" / "closure" / "output" / "recordings")
        if s is not None and c is not None:
            candidates.append(p)
    if not candidates:
        return None
    return max(candidates, key=lambda p: p.stat().st_mtime)


def resolve_sessions(args) -> Tuple[Path, Path, Path]:
    if args.src or args.closure:
        if not (args.src and args.closure):
            raise SystemExit("Use --src and --closure together.")
        src = normalize_path(args.src).resolve()
        clo = normalize_path(args.closure).resolve()
        if not src.is_dir() or not clo.is_dir():
            raise SystemExit(f"Recording session missing: src={src}, closure={clo}")
        root = find_article_root(src)
        if root is None:
            root = Path(os.path.commonpath([str(src), str(clo)]))
        return src, clo, root

    if args.root:
        root = normalize_path(args.root).resolve()
    else:
        repo = Path.cwd().resolve()
        root = discover_latest_article_root(repo)
        if root is None:
            raise SystemExit(
                "Could not auto-discover a recent article_forced_tg* run with n recordings. "
                "Supply --root or --src/--closure."
            )
        print(f"[tg-core] auto-selected article root: {root}")

    src = latest_recording_session(root / "runs" / "src" / "output" / "recordings")
    clo = latest_recording_session(root / "runs" / "closure" / "output" / "recordings")
    if src is None or clo is None:
        raise SystemExit(f"Could not find n-recording sessions under {root}")
    return src.resolve(), clo.resolve(), root.resolve()


def infer_square_shape(path: Path) -> Tuple[int, int]:
    n = path.stat().st_size // 4
    q = int(round(math.sqrt(n)))
    if q * q != n:
        raise RuntimeError(
            f"Cannot infer recording grid from {path}: {n} float32 values. "
            "Provide --nx/--ny."
        )
    return q, q


def resolve_live_grid(
    session: Path, manifest: Dict[str, str], params: Dict[str, str], nx_arg: int, ny_arg: int
) -> Tuple[int, int]:
    nx = nx_arg if nx_arg > 0 else first_int(
        [manifest, params], ["liveGridNx", "recordGridNx", "gridNx"], -1
    )
    ny = ny_arg if ny_arg > 0 else first_int(
        [manifest, params], ["liveGridNy", "recordGridNy", "gridNy"], -1
    )
    if nx > 0 and ny > 0:
        return nx, ny
    steps = list_field_steps(session, "n")
    if not steps:
        raise RuntimeError(f"No n fields in {session}")
    return infer_square_shape(field_path(session, steps[0], "n"))


def read_field(path: Path, nx: int, ny: int) -> np.ndarray:
    a = np.fromfile(path, dtype=np.float32)
    if a.size != nx * ny:
        raise RuntimeError(
            f"Wrong field size for {path}: got {a.size}, expected {nx*ny} ({nx}x{ny})"
        )
    a = a.reshape((ny, nx)).astype(np.float64, copy=False)
    if not np.all(np.isfinite(a)):
        bad = int(a.size - np.count_nonzero(np.isfinite(a)))
        raise RuntimeError(f"{path} contains {bad} non-finite values.")
    return a


def _conservative_rebin_counts_axis(a: np.ndarray, new_n: int, axis: int) -> np.ndarray:
    """Conservative remap of cell counts along one uniform-grid axis."""
    a = np.asarray(a, dtype=np.float64)
    old_n = a.shape[axis]
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


def conservative_rebin_counts_2d(
    n_live: np.ndarray, solver_nx: int, solver_ny: int
) -> np.ndarray:
    """LiveVis count cells -> MPCD collision-cell counts, conserving particle number."""
    a = np.maximum(np.asarray(n_live, dtype=np.float64), 0.0)
    tmp = _conservative_rebin_counts_axis(a, solver_nx, axis=1)
    out = _conservative_rebin_counts_axis(tmp, solver_ny, axis=0)
    s0 = float(np.sum(a))
    s1 = float(np.sum(out))
    tol = max(1e-9 * max(abs(s0), 1.0), 1e-7)
    if not math.isfinite(s1) or abs(s1 - s0) > tol:
        raise RuntimeError(
            f"Population remap is not conservative: live={s0:.17g}, solver={s1:.17g}"
        )
    return out


def characteristic_wavenumber(lx: float, ly: float, mx: int, my: int) -> float:
    kx = 2.0 * math.pi * mx / lx
    ky = 2.0 * math.pi * my / ly
    return math.sqrt(0.5 * (kx * kx + ky * ky))


def tg_core_centers(lx: float, ly: float, mx: int, my: int) -> List[Tuple[float, float]]:
    """Vorticity-center locations for the TG mode used by the solver."""
    centers: List[Tuple[float, float]] = []
    for ix in range(2 * mx):
        x = (2 * ix + 1) * lx / (4.0 * mx)
        for iy in range(2 * my):
            y = (2 * iy + 1) * ly / (4.0 * my)
            centers.append((x, y))
    return centers


def periodic_delta(coord: np.ndarray, center: float, length: float) -> np.ndarray:
    return (coord - center + 0.5 * length) % length - 0.5 * length


def core_masks(
    nx: int,
    ny: int,
    lx: float,
    ly: float,
    mx: int,
    my: int,
    radius_cells: float,
) -> Tuple[List[np.ndarray], np.ndarray, List[Tuple[float, float]], float]:
    hx = lx / nx
    hy = ly / ny
    if abs(hx - hy) > 1e-12 * max(hx, hy):
        h = math.sqrt(hx * hy)
        print(
            f"[tg-core] WARNING anisotropic solver cells hx={hx:.9g}, hy={hy:.9g}; "
            f"using h=sqrt(hx*hy)={h:.9g} for core radius."
        )
    else:
        h = hx
    radius = radius_cells * h

    x = (np.arange(nx) + 0.5) * hx
    y = (np.arange(ny) + 0.5) * hy
    X, Y = np.meshgrid(x, y)

    centers = tg_core_centers(lx, ly, mx, my)
    masks: List[np.ndarray] = []
    union = np.zeros((ny, nx), dtype=bool)
    for xc, yc in centers:
        dx = periodic_delta(X, xc, lx)
        dy = periodic_delta(Y, yc, ly)
        mask = dx * dx + dy * dy <= radius * radius
        if not np.any(mask):
            raise RuntimeError(
                f"Empty core mask at ({xc},{yc}); increase --core-radius-cells."
            )
        masks.append(mask)
        union |= mask
    return masks, union, centers, radius


def analyze_one(
    session: Path,
    mode: str,
    steps: Sequence[int],
    live_nx: int,
    live_ny: int,
    solver_nx: int,
    solver_ny: int,
    masks: Sequence[np.ndarray],
    union_mask: np.ndarray,
    dt: float,
    k_char: float,
    u0: float,
) -> List[Dict[str, object]]:
    rows: List[Dict[str, object]] = []
    for step in steps:
        n_live = read_field(field_path(session, step, "n"), live_nx, live_ny)
        n_solver = conservative_rebin_counts_2d(n_live, solver_nx, solver_ny)

        n_mean = float(np.mean(n_solver))
        # Pooled core average: every solver cell in every core has equal weight.
        n_core = float(np.mean(n_solver[union_mask]))
        r_core = n_core / n_mean if n_mean != 0.0 else float("nan")

        row: Dict[str, object] = {
            "mode": mode,
            "step": int(step),
            "time": float(step) * dt,
            "tau": float(step) * dt * k_char * abs(u0),
            "Nmean": n_mean,
            "Ncore": n_core,
            "Rcore": r_core,
            "coreCellCountTotal": int(np.count_nonzero(union_mask)),
            "totalParticles": float(np.sum(n_solver)),
        }
        for i, mask in enumerate(masks, start=1):
            ni = float(np.mean(n_solver[mask]))
            row[f"Ncore{i}"] = ni
            row[f"Rcore{i}"] = ni / n_mean if n_mean != 0.0 else float("nan")
            row[f"coreCells{i}"] = int(np.count_nonzero(mask))
        rows.append(row)
    return rows


def write_csv(path: Path, rows: Sequence[Dict[str, object]]) -> None:
    if not rows:
        return
    keys = list(rows[0].keys())
    with path.open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=keys)
        w.writeheader()
        w.writerows(rows)


def make_plot(path_png: Path, path_pdf: Path, rows: Sequence[Dict[str, object]]) -> None:
    fig, ax = plt.subplots(figsize=(8.4, 5.2), constrained_layout=True)
    modes = []
    for r in rows:
        mode = str(r["mode"])
        if mode not in modes:
            modes.append(mode)
    for mode in modes:
        rr = sorted((r for r in rows if str(r["mode"]) == mode), key=lambda r: int(r["step"]))
        tau = np.array([float(r["tau"]) for r in rr])
        rc = np.array([float(r["Rcore"]) for r in rr])
        ax.plot(tau, rc, marker="o", linewidth=1.8, markersize=4.5, label=mode)

    ax.axhline(1.0, linestyle="--", linewidth=1.0, color="0.5")
    ax.set_xlabel(r"nondimensional time  $\tau=k_{\rm char}U_0t$")
    ax.set_ylabel(r"vortex-core population ratio  $R_{\rm core}=N_{\rm core}/\langle N\rangle$")
    ax.grid(alpha=0.25)
    ax.legend(loc="best")
    fig.savefig(path_png, dpi=240, bbox_inches="tight")
    fig.savefig(path_pdf, bbox_inches="tight")
    plt.close(fig)


def main() -> int:
    ap = argparse.ArgumentParser(
        description="Compute Taylor--Green vortex-core particle occupancy ratio from LiveVis n fields."
    )
    ap.add_argument("--root", default="", help="article run root; default auto-selects latest article_forced_tg* run")
    ap.add_argument("--src", default="", help="explicit SRC recording session")
    ap.add_argument("--closure", default="", help="explicit closure recording session")
    ap.add_argument("--output", default="", help="output directory; default <article-root>/analysis_livevis_tg_core")
    ap.add_argument("--nx", type=int, default=-1, help="LiveVis Nx override")
    ap.add_argument("--ny", type=int, default=-1, help="LiveVis Ny override")
    ap.add_argument("--solver-nx", type=int, default=-1, help="MPCD collision-grid Nx override")
    ap.add_argument("--solver-ny", type=int, default=-1, help="MPCD collision-grid Ny override")
    ap.add_argument("--lx", type=float, default=float("nan"))
    ap.add_argument("--ly", type=float, default=float("nan"))
    ap.add_argument("--dt", type=float, default=float("nan"))
    ap.add_argument("--u0", type=float, default=float("nan"), help="TG initial amplitude; auto from run metadata")
    ap.add_argument("--mode-x", type=int, default=-1)
    ap.add_argument("--mode-y", type=int, default=-1)
    ap.add_argument(
        "--core-radius-cells", type=float, default=2.0,
        help="core-disk radius in MPCD collision-cell widths; default 2 (historical TG-core definition)",
    )
    args = ap.parse_args()

    src, clo, root = resolve_sessions(args)
    print(f"[tg-core] SRC session:     {src}")
    print(f"[tg-core] closure session: {clo}")

    sm, st, sp, _ = load_context(src)
    cm, ct, cp, _ = load_context(clo)

    snx, sny = resolve_live_grid(src, sm, sp, args.nx, args.ny)
    cnx, cny = resolve_live_grid(clo, cm, cp, args.nx, args.ny)
    if (snx, sny) != (cnx, cny):
        raise SystemExit(f"LiveVis grid mismatch: SRC={snx}x{sny}, closure={cnx}x{cny}")
    live_nx, live_ny = snx, sny

    # Prefer actual solver params over manifest values so LiveVis grid cannot shadow Nx/Ny.
    solver_dicts = [cp, sp, ct, st, cm, sm]
    solver_nx = args.solver_nx if args.solver_nx > 0 else first_int(
        solver_dicts, ["Nx", "NX", "solverNx"], -1
    )
    solver_ny = args.solver_ny if args.solver_ny > 0 else first_int(
        solver_dicts, ["Ny", "NY", "solverNy"], -1
    )
    if solver_nx <= 0 or solver_ny <= 0:
        raise SystemExit("Could not resolve MPCD collision grid; supply --solver-nx/--solver-ny.")

    dicts = [cm, ct, cp, sm, st, sp]
    lx = args.lx if math.isfinite(args.lx) else first_number(dicts, ["Lx", "lx"], 1.0)
    ly = args.ly if math.isfinite(args.ly) else first_number(dicts, ["Ly", "ly"], 1.0)
    dt = args.dt if math.isfinite(args.dt) else first_number(dicts, ["dt", "DT"], float("nan"))
    if not math.isfinite(dt) or dt <= 0.0:
        raise SystemExit("Could not resolve dt; supply --dt.")

    mx = args.mode_x if args.mode_x > 0 else first_int(
        dicts, ["taylorGreenForcingModeX", "TG_FORCING_MODE_X"], 1
    )
    my = args.mode_y if args.mode_y > 0 else first_int(
        dicts, ["taylorGreenForcingModeY", "TG_FORCING_MODE_Y"], 1
    )
    u0 = args.u0 if math.isfinite(args.u0) and args.u0 != 0.0 else first_number(
        dicts, ["U0", "u0"], float("nan")
    )
    if not math.isfinite(u0) or u0 == 0.0:
        raise SystemExit("Could not resolve U0; supply --u0.")

    src_steps = set(list_field_steps(src, "n"))
    clo_steps = set(list_field_steps(clo, "n"))
    steps = sorted(src_steps & clo_steps)
    if not steps:
        raise SystemExit("No common recorded n frames.")

    masks, union_mask, centers, radius = core_masks(
        solver_nx, solver_ny, lx, ly, mx, my, args.core_radius_cells
    )
    k_char = characteristic_wavenumber(lx, ly, mx, my)

    rows: List[Dict[str, object]] = []
    rows.extend(
        analyze_one(
            src, "SRC", steps, live_nx, live_ny, solver_nx, solver_ny,
            masks, union_mask, dt, k_char, u0
        )
    )
    rows.extend(
        analyze_one(
            clo, "SRC + particle/field closure", steps, live_nx, live_ny,
            solver_nx, solver_ny, masks, union_mask, dt, k_char, u0
        )
    )

    if args.output:
        outdir = normalize_path(args.output).resolve()
    else:
        outdir = _rebase_to_current_repo(root / "analysis_livevis_tg_core")
    outdir.mkdir(parents=True, exist_ok=True)

    csv_path = outdir / "tg_core_population_metrics.csv"
    write_csv(csv_path, rows)

    png = outdir / "fig_tg_core_population_ratio_vs_tau.png"
    pdf = outdir / "fig_tg_core_population_ratio_vs_tau.pdf"
    make_plot(png, pdf, rows)

    summary = outdir / "tg_core_population_summary.txt"
    with summary.open("w", encoding="utf-8") as f:
        f.write("===== TAYLOR--GREEN CORE POPULATION FROM LIVEVIS n =====\n")
        f.write(f"srcSession={src}\nclosureSession={clo}\n")
        f.write(f"liveGrid={live_nx}x{live_ny}\n")
        f.write(f"solverGrid={solver_nx}x{solver_ny}\n")
        f.write(f"L={lx}x{ly} dt={dt:.17g} U0={u0:.17g} mode=({mx},{my})\n")
        f.write(f"kChar={k_char:.17g}\n")
        f.write(f"coreRadiusCells={args.core_radius_cells:.17g}\n")
        f.write(f"coreRadiusPhysical={radius:.17g}\n")
        f.write(f"coreCellCountTotal={np.count_nonzero(union_mask)}\n")
        for i, ((xc, yc), mask) in enumerate(zip(centers, masks), start=1):
            f.write(
                f"core{i}: center=({xc:.17g},{yc:.17g}) cells={np.count_nonzero(mask)}\n"
            )
        f.write("\nDefinition: Rcore=Ncore/<N>; Ncore is pooled mean over all core-mask cells.\n")
        f.write("LiveVis n is conservatively remapped to the MPCD collision grid before averaging.\n\n")
        for mode in ["SRC", "SRC + particle/field closure"]:
            rr = sorted(
                (r for r in rows if str(r["mode"]) == mode),
                key=lambda r: int(r["step"])
            )
            first = rr[0]
            last = rr[-1]
            f.write(mode + "\n")
            f.write(
                f"  first: step={first['step']} tau={float(first['tau']):.17g} "
                f"Nmean={float(first['Nmean']):.17g} "
                f"Ncore={float(first['Ncore']):.17g} "
                f"Rcore={float(first['Rcore']):.17g}\n"
            )
            f.write(
                f"  last:  step={last['step']} tau={float(last['tau']):.17g} "
                f"Nmean={float(last['Nmean']):.17g} "
                f"Ncore={float(last['Ncore']):.17g} "
                f"Rcore={float(last['Rcore']):.17g}\n\n"
            )

    print("[tg-core] PASS")
    print(
        f"[tg-core] live={live_nx}x{live_ny} -> solver={solver_nx}x{solver_ny}, "
        f"U0={u0:.9g}, core radius={args.core_radius_cells:g} h"
    )
    print(
        "[tg-core] centers="
        + ", ".join(f"({x:.3g},{y:.3g})" for x, y in centers)
    )
    for mode in ["SRC", "SRC + particle/field closure"]:
        rr = sorted(
            (r for r in rows if str(r["mode"]) == mode),
            key=lambda r: int(r["step"])
        )
        last = rr[-1]
        print(
            f"[tg-core] {mode}: final step={last['step']} "
            f"tau={float(last['tau']):.6g} "
            f"<N>={float(last['Nmean']):.6g} "
            f"Ncore={float(last['Ncore']):.6g} "
            f"Rcore={float(last['Rcore']):.6g}"
        )
    print(f"[tg-core] csv={csv_path}")
    print(f"[tg-core] plot={png}")
    print(f"[tg-core] summary={summary}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
