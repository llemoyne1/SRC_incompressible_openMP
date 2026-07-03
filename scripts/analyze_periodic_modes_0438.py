#!/usr/bin/env python3
"""Post-process periodic wall-free SRC/MPCD path-equivalence runs, 0438.

The analyzer intentionally stays outside the solver.  It reads the initial and
final .smpcd dumps produced by the 0438 runners and estimates modal amplitudes
for two periodic validation cases:

  shear : u_x(y) = A sin(2 pi y / Ly), u_y = 0
  tg    : u_x = A sin(2 pi x / Lx) cos(2 pi y / Ly)
          u_y =-A cos(2 pi x / Lx) sin(2 pi y / Ly)

It also copies the last runtime-summary row and compares resampling paths to
matching non-resampling references:

  src-resampling     -> src
  src-q6-resampling  -> src-q6
"""
from __future__ import annotations

import argparse
import csv
import math
import os
import re
import sys
from array import array
from pathlib import Path
from typing import Dict, Iterable, List, Tuple

FLUID_ROLE = 1


def finite_float(value: object, default: float = float("nan")) -> float:
    try:
        x = float(value)  # type: ignore[arg-type]
        return x if math.isfinite(x) else default
    except Exception:
        return default


def read_last_csv(path: Path) -> Dict[str, str]:
    if not path.is_file():
        return {}
    with path.open(newline="", encoding="utf-8") as stream:
        rows = list(csv.DictReader(stream))
    return rows[-1] if rows else {}


def read_elapsed(path: Path) -> float:
    if not path.is_file():
        return float("nan")
    text = path.read_text(errors="replace")
    m = re.search(r"elapsed=([0-9.eE+-]+)", text)
    return finite_float(m.group(1)) if m else float("nan")


def read_array(stream, typecode: str, n: int) -> array:
    arr = array(typecode)
    arr.fromfile(stream, n)
    if sys.byteorder != "little":
        arr.byteswap()
    return arr


def read_smpcd(path: Path) -> Dict[str, object]:
    with path.open("rb") as stream:
        magic = stream.read(16)
        if not magic.startswith(b"SRCMPCD_STATE"):
            raise ValueError(f"{path}: unsupported magic {magic!r}")
        import struct
        header = struct.unpack("<IIIIQIIII", stream.read(40))
        n = int(header[4])
        stream.read(8 * 8)  # reserved
        x = read_array(stream, "d", n)
        y = read_array(stream, "d", n)
        vx = read_array(stream, "d", n)
        vy = read_array(stream, "d", n)
        typ = read_array(stream, "I", n)  # noqa: F841, retained for layout validation
        mass = read_array(stream, "d", n)
        role_bytes = stream.read(n)
        if len(role_bytes) != n:
            raise ValueError(f"{path}: truncated role array")
    return {"n": n, "x": x, "y": y, "vx": vx, "vy": vy, "mass": mass, "role": role_bytes}


def modal_amplitude(state: Dict[str, object], case: str, lx: float, ly: float) -> Dict[str, float]:
    x = state["x"]  # type: ignore[assignment]
    y = state["y"]  # type: ignore[assignment]
    vx = state["vx"]  # type: ignore[assignment]
    vy = state["vy"]  # type: ignore[assignment]
    mass = state["mass"]  # type: ignore[assignment]
    role = state["role"]  # type: ignore[assignment]
    n = int(state["n"])
    kx = 2.0 * math.pi / lx
    ky = 2.0 * math.pi / ly
    sx_num = 0.0
    sx_den = 0.0
    sy_num = 0.0
    sy_den = 0.0
    uy_leak_num = 0.0
    ux_orth_num = 0.0
    m_sum = 0.0
    vx_sum = 0.0
    vy_sum = 0.0
    for i in range(n):
        if role[i] != FLUID_ROLE:
            continue
        mi = mass[i]
        xi = x[i]
        yi = y[i]
        vxi = vx[i]
        vyi = vy[i]
        m_sum += mi
        vx_sum += mi * vxi
        vy_sum += mi * vyi
        if case == "shear":
            phi = math.sin(ky * yi)
            psi = math.cos(ky * yi)
            sx_num += mi * vxi * phi
            sx_den += mi * phi * phi
            ux_orth_num += mi * vxi * psi
            uy_leak_num += mi * vyi * vyi
        elif case == "tg":
            phix = math.sin(kx * xi) * math.cos(ky * yi)
            phiy = -math.cos(kx * xi) * math.sin(ky * yi)
            sx_num += mi * vxi * phix
            sx_den += mi * phix * phix
            sy_num += mi * vyi * phiy
            sy_den += mi * phiy * phiy
            ux_orth_num += mi * (vxi * vxi + vyi * vyi)
        else:
            raise ValueError(f"unsupported case={case}")
    ax = sx_num / sx_den if sx_den > 0.0 else float("nan")
    if case == "shear":
        amp = ax
        ay = float("nan")
        orth = ux_orth_num / sx_den if sx_den > 0.0 else float("nan")
        uy_leak_rms = math.sqrt(uy_leak_num / m_sum) if m_sum > 0.0 else float("nan")
    else:
        ay = sy_num / sy_den if sy_den > 0.0 else float("nan")
        amp = 0.5 * (ax + ay) if math.isfinite(ax) and math.isfinite(ay) else float("nan")
        orth = math.sqrt(ux_orth_num / m_sum) if m_sum > 0.0 else float("nan")
        uy_leak_rms = float("nan")
    return {
        "amp": amp,
        "amp_x": ax,
        "amp_y": ay,
        "orth_metric": orth,
        "uy_leak_rms": uy_leak_rms,
        "mass_fluid": m_sum,
        "mean_vx_modal_reader": vx_sum / m_sum if m_sum > 0.0 else float("nan"),
        "mean_vy_modal_reader": vy_sum / m_sum if m_sum > 0.0 else float("nan"),
    }


def latest_final_state(run: Path) -> Path | None:
    states = sorted((run / "output").glob("state_step_*.smpcd"))
    if not states:
        return None
    def step_of(p: Path) -> int:
        m = re.search(r"state_step_(\d+)\.smpcd$", p.name)
        return int(m.group(1)) if m else -1
    return max(states, key=step_of)


def rel_delta(value: float, ref: float) -> float:
    if not math.isfinite(value) or not math.isfinite(ref):
        return float("nan")
    den = max(abs(ref), 1.0e-300)
    return (value - ref) / den


def fmt(x: float) -> str:
    return "" if not math.isfinite(x) else f"{x:.17g}"


def analyze_mode(root: Path, mode: str, case: str, lx: float, ly: float) -> Dict[str, str]:
    run = root / mode
    init_states = sorted((run / "init").glob("*.smpcd"))
    final_state = latest_final_state(run)
    summary = read_last_csv(run / "output" / "summary_runtime.csv")
    status = read_last_csv(root / "launch_status.csv")  # not per-mode; overwritten below from status map
    del status
    time_files = sorted((run / "logs").glob("*.time"))
    elapsed = read_elapsed(time_files[0]) if time_files else float("nan")

    amp0 = amp1 = ax0 = ax1 = ay0 = ay1 = orth1 = uy_leak = float("nan")
    state_error = ""
    try:
        if init_states and final_state:
            m0 = modal_amplitude(read_smpcd(init_states[0]), case, lx, ly)
            m1 = modal_amplitude(read_smpcd(final_state), case, lx, ly)
            amp0, amp1 = m0["amp"], m1["amp"]
            ax0, ax1 = m0["amp_x"], m1["amp_x"]
            ay0, ay1 = m0["amp_y"], m1["amp_y"]
            orth1 = m1["orth_metric"]
            uy_leak = m1["uy_leak_rms"]
        else:
            state_error = "missing_state_dump"
    except Exception as exc:  # keep matrix readable on failures
        state_error = type(exc).__name__ + ":" + str(exc)

    step = finite_float(summary.get("step"))
    time = finite_float(summary.get("time"))
    k2 = (2.0 * math.pi / ly) ** 2 if case == "shear" else (2.0 * math.pi / lx) ** 2 + (2.0 * math.pi / ly) ** 2
    if math.isfinite(amp0) and math.isfinite(amp1) and abs(amp0) > 0.0 and abs(amp1 / amp0) > 0.0 and time > 0.0:
        nu_eff = -math.log(abs(amp1 / amp0)) / (k2 * time)
    else:
        nu_eff = float("nan")
    ratio = amp1 / amp0 if math.isfinite(amp0) and amp0 != 0.0 and math.isfinite(amp1) else float("nan")

    return {
        "mode": mode,
        "runDir": str(run),
        "summaryFound": "1" if summary else "0",
        "stateError": state_error,
        "elapsed_s": fmt(elapsed),
        "step": summary.get("step", ""),
        "time": summary.get("time", ""),
        "nFluidParticles": summary.get("nFluidParticles", ""),
        "totalMass": summary.get("totalMass", ""),
        "Px": summary.get("Px", ""),
        "Py": summary.get("Py", ""),
        "meanVx": summary.get("meanVx", ""),
        "meanVy": summary.get("meanVy", ""),
        "meanKinetic": summary.get("meanKinetic", ""),
        "kBTEstimate": summary.get("kBTEstimate", ""),
        "meanN": summary.get("meanN", ""),
        "stdN": summary.get("stdN", ""),
        "minN": summary.get("minN", ""),
        "maxN": summary.get("maxN", ""),
        "q6Applied": summary.get("q6Applied", ""),
        "q6Converged": summary.get("q6Converged", ""),
        "q6ResidualRel": summary.get("q6ResidualRel", ""),
        "resampComputed": summary.get("resampComputed", ""),
        "resampPoorCells": summary.get("resampPoorCells", ""),
        "resampRichCells": summary.get("resampRichCells", ""),
        "resampTransferPairs": summary.get("resampTransferPairs", ""),
        "resampMRelMaxAbs": summary.get("resampMRelMaxAbs", ""),
        "resampPopulationGuardApplied": summary.get("resampPopulationGuardApplied", ""),
        "resampPopulationGuardCellsSplit": summary.get("resampPopulationGuardCellsSplit", ""),
        "resampPopulationGuardCellsExtracted": summary.get("resampPopulationGuardCellsExtracted", ""),
        "amp0": fmt(amp0),
        "ampFinal": fmt(amp1),
        "ampRatio": fmt(ratio),
        "ampX0": fmt(ax0),
        "ampXFinal": fmt(ax1),
        "ampY0": fmt(ay0),
        "ampYFinal": fmt(ay1),
        "nuEffEstimate": fmt(nu_eff),
        "orthMetricFinal": fmt(orth1),
        "uyLeakRmsFinal": fmt(uy_leak),
    }


def load_status(path: Path) -> Dict[str, str]:
    out: Dict[str, str] = {}
    if not path.is_file():
        return out
    with path.open(newline="", encoding="utf-8") as stream:
        for row in csv.DictReader(stream):
            out[row.get("mode", "")] = row.get("exit_code", "")
    return out


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", required=True)
    ap.add_argument("--case", required=True, choices=["shear", "tg"])
    ap.add_argument("--modes", nargs="+", required=True)
    ap.add_argument("--Lx", type=float, required=True)
    ap.add_argument("--Ly", type=float, required=True)
    ap.add_argument("--csv", required=True)
    ap.add_argument("--markdown", required=True)
    args = ap.parse_args()

    root = Path(args.root)
    rows = [analyze_mode(root, mode, args.case, args.Lx, args.Ly) for mode in args.modes]
    status = load_status(root / "launch_status.csv")
    for row in rows:
        row["exit_code"] = status.get(row["mode"], "")

    by_mode = {r["mode"]: r for r in rows}
    ref_map = {"src-resampling": "src", "src-q6-resampling": "src-q6"}
    for row in rows:
        ref = by_mode.get(ref_map.get(row["mode"], ""))
        if ref:
            for key in ["ampFinal", "ampRatio", "nuEffEstimate", "kBTEstimate", "totalMass", "meanN", "stdN"]:
                row[key + "RelDeltaVsRef"] = fmt(rel_delta(finite_float(row.get(key)), finite_float(ref.get(key))))
        else:
            for key in ["ampFinal", "ampRatio", "nuEffEstimate", "kBTEstimate", "totalMass", "meanN", "stdN"]:
                row[key + "RelDeltaVsRef"] = ""
        basic_pass = (
            row.get("exit_code", "0") in {"0", ""}
            and row.get("summaryFound") == "1"
            and row.get("stateError") == ""
            and math.isfinite(finite_float(row.get("kBTEstimate")))
            and math.isfinite(finite_float(row.get("ampFinal")))
        )
        row["passBasic"] = "1" if basic_pass else "0"

    fields: List[str] = []
    for row in rows:
        for key in row:
            if key not in fields:
                fields.append(key)
    Path(args.csv).parent.mkdir(parents=True, exist_ok=True)
    with open(args.csv, "w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)

    passed = sum(1 for r in rows if r.get("passBasic") == "1")
    title = "periodic shear wave" if args.case == "shear" else "periodic Taylor-Green"
    lines = [
        f"# 0438 {title} path matrix", "",
        "Scope: periodic, wall-free, no chi/Darcy, no inlet/outlet.", "",
        f"Basic run/postprocess pass: **{passed}/{len(rows)}**", "",
        "| Mode | Basic | step | ampFinal | ampRatio | nuEff | kBT | meanN | stdN | Δamp vs ref | Δnu vs ref |",
        "| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |",
    ]
    for r in rows:
        lines.append(
            f"| {r['mode']} | {r['passBasic']} | {r.get('step','')} | {r.get('ampFinal','')} | "
            f"{r.get('ampRatio','')} | {r.get('nuEffEstimate','')} | {r.get('kBTEstimate','')} | "
            f"{r.get('meanN','')} | {r.get('stdN','')} | {r.get('ampFinalRelDeltaVsRef','')} | "
            f"{r.get('nuEffEstimateRelDeltaVsRef','')} |"
        )
    lines += ["", f"CSV: `{args.csv}`", ""]
    Path(args.markdown).write_text("\n".join(lines), encoding="utf-8")
    print(f"[0438-analyze] {title}: pass={passed}/{len(rows)} csv={args.csv} md={args.markdown}")


if __name__ == "__main__":
    main()
