#!/usr/bin/env python3
"""Offline local interaction analysis for the 2-D planar gas-jet/liquid-bath test.

Standard library only.

The liquid interface is reconstructed from the liquid particle mass exactly as
in the previous analyzer (cell fill, one 5-point smoothing pass with lambda
0.125, alpha=0.5 crossing).  Gas diagnostics are deliberately LOCAL: they are
computed only in a control column centred on the nozzle and in a thin incident
band above the impact zone.  No whole-domain gas mean velocity is used as a
qualification observable.

Sign convention: +y is upward.  A valid incident jet therefore has meanVy < 0.
"""
from __future__ import annotations

import argparse
import csv
import math
import re
import statistics
import struct
import sys
from array import array
from pathlib import Path

MAGIC_PREFIX = b"SRCMPCD_STATE"
HEADER_FMT = "<IIIIQIIII"


def read_state_particles(path: Path):
    """Read particle arrays needed by the local analyzer."""
    with path.open("rb") as f:
        magic = f.read(16)
        if not magic.startswith(MAGIC_PREFIX):
            raise RuntimeError(f"bad state magic: {path}")
        vals = struct.unpack(HEADER_FMT, f.read(struct.calcsize(HEADER_FMT)))
        n = int(vals[4])
        f.read(8 * 8)  # reserved
        x = array("d"); x.fromfile(f, n)
        y = array("d"); y.fromfile(f, n)
        vx = array("d"); vx.fromfile(f, n)
        vy = array("d"); vy.fromfile(f, n)
        typ = array("I"); typ.fromfile(f, n)
        mass = array("d"); mass.fromfile(f, n)
        role = f.read(n)
    if sys.byteorder == "big":
        x.byteswap(); y.byteswap(); vx.byteswap(); vy.byteswap(); typ.byteswap(); mass.byteswap()
    return n, x, y, vx, vy, typ, mass, role


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
            v = c + lam * ((w - c) + (e - c) + (s - c) + (n - c))
            out[i] = min(1.0, max(0.0, v))
    return out


def surface_from_particles(parts, nx, ny, Lx, Ly, gamma, liquid_type, liquid_mass):
    n, x, y, vx, vy, typ, mass, role = parts
    dx = Lx / nx; dy = Ly / ny
    m = [0.0] * (nx * ny)
    nfluid = 0
    for j in range(n):
        if role[j] != 1 or int(typ[j]) != liquid_type:
            continue
        ix = int(x[j] / dx); iy = int(y[j] / dy)
        if ix < 0: ix = 0
        elif ix >= nx: ix = nx - 1
        if iy < 0: iy = 0
        elif iy >= ny: iy = ny - 1
        # Use the actual stored particle mass when finite/positive; preserve the
        # nominal-mass fallback for compatibility with old states.
        mj = mass[j] if math.isfinite(mass[j]) and mass[j] > 0.0 else liquid_mass
        m[iy * nx + ix] += mj
        nfluid += 1
    ref = gamma * liquid_mass
    alpha = [min(1.0, max(0.0, v / ref)) for v in m]
    alpha = smooth_cross(alpha, nx, ny, 0.125)
    eta = [math.nan] * nx
    for ix in range(nx):
        cross = None
        for iy in range(ny - 1):
            a0 = alpha[iy * nx + ix]; a1 = alpha[(iy + 1) * nx + ix]
            if a0 >= 0.5 and a1 < 0.5:
                y0 = (iy + 0.5) * dy; y1 = (iy + 1.5) * dy
                if abs(a1 - a0) > 1e-14:
                    q = (0.5 - a0) / (a1 - a0)
                    cross = y0 + q * (y1 - y0)
                else:
                    cross = (iy + 1) * dy
        if cross is not None:
            eta[ix] = cross
    return eta, nfluid


def step_of(path: Path):
    m = re.search(r"state_step_(\d+)", path.name)
    return int(m.group(1)) if m else 0


def median(xs):
    q = [v for v in xs if math.isfinite(v)]
    return statistics.median(q) if q else math.nan


def interface_metrics(eta, Lx, jet_center, jet_width):
    nx = len(eta); dx = Lx / nx
    xs = [(i + 0.5) * dx for i in range(nx)]
    far = [v for x, v in zip(xs, eta)
           if 0.08 * Lx < x < 0.92 * Lx and abs(x - jet_center) >= 3.0 * jet_width]
    eta_far = median(far)
    center_idx = [i for i, x in enumerate(xs)
                  if abs(x - jet_center) <= 1.5 * jet_width and math.isfinite(eta[i])]
    if not center_idx or not math.isfinite(eta_far):
        return {"etaFar": eta_far, "etaMin": math.nan, "depth": math.nan,
                "halfDepthWidth": math.nan, "symmetryRmsRel": math.nan}
    imin = min(center_idx, key=lambda i: eta[i])
    eta_min = eta[imin]
    depth = eta_far - eta_min
    width = math.nan
    if depth > 0:
        level = eta_far - 0.5 * depth
        mask = [math.isfinite(v) and v <= level for v in eta]
        ic = min(range(nx), key=lambda i: abs(xs[i] - jet_center))
        if mask[ic]:
            il = ic; ir = ic
            while il > 0 and mask[il - 1]: il -= 1
            while ir + 1 < nx and mask[ir + 1]: ir += 1
            width = (ir - il + 1) * dx
    diffs = []
    scale = max(abs(depth), dx)
    ic = min(range(nx), key=lambda i: abs(xs[i] - jet_center))
    for d in range(1, min(ic, nx - 1 - ic) + 1):
        vl, vr = eta[ic - d], eta[ic + d]
        if math.isfinite(vl) and math.isfinite(vr) and d * dx <= 4 * jet_width:
            diffs.append((vl - vr) ** 2)
    sym = math.sqrt(sum(diffs) / len(diffs)) / scale if diffs else math.nan
    return {"etaFar": eta_far, "etaMin": eta_min, "depth": depth,
            "halfDepthWidth": width, "symmetryRmsRel": sym}


def weighted_gas_stats(parts, indices, area, gas_kbt, cell_area, prefix):
    """Mass-weighted local gas statistics in a 2-D control area."""
    n, x, y, vx, vy, typ, mass, role = parts
    if area <= 0.0 or not indices:
        return {
            f"{prefix}Particles": 0,
            f"{prefix}Area": area,
            f"{prefix}OccupancyPerCell": math.nan,
            f"{prefix}MassDensity": math.nan,
            f"{prefix}MeanVx": math.nan,
            f"{prefix}MeanVy": math.nan,
            f"{prefix}DownwardMassFraction": math.nan,
            f"{prefix}NominalEOSPressure": math.nan,
            f"{prefix}NormalThermalStress": math.nan,
            f"{prefix}NormalAdvectiveStress": math.nan,
            f"{prefix}NormalKineticStress": math.nan,
            f"{prefix}DownwardMomentumFluxProxy": math.nan,
            f"{prefix}UpwardMomentumFluxProxy": math.nan,
            f"{prefix}DirectionalMomentumFluxProxy": math.nan,
        }
    M = sum(mass[j] for j in indices)
    if not (M > 0.0):
        return weighted_gas_stats(parts, [], area, gas_kbt, cell_area, prefix)
    ux = sum(mass[j] * vx[j] for j in indices) / M
    uy = sum(mass[j] * vy[j] for j in indices) / M
    mdown = sum(mass[j] for j in indices if vy[j] < 0.0)
    normal_total = sum(mass[j] * vy[j] * vy[j] for j in indices) / area
    normal_thermal = sum(mass[j] * (vy[j] - uy) ** 2 for j in indices) / area
    rho = M / area
    normal_advective = rho * uy * uy
    down_flux = sum(mass[j] * vy[j] * vy[j] for j in indices if vy[j] < 0.0) / area
    up_flux = sum(mass[j] * vy[j] * vy[j] for j in indices if vy[j] > 0.0) / area
    # Positive means downward-directed transport dominates in this local sample.
    directional = down_flux - up_flux
    number_density = len(indices) / area
    occupancy = number_density * cell_area
    nominal_eos = number_density * gas_kbt if gas_kbt > 0.0 else math.nan
    return {
        f"{prefix}Particles": len(indices),
        f"{prefix}Area": area,
        f"{prefix}OccupancyPerCell": occupancy,
        f"{prefix}MassDensity": rho,
        f"{prefix}MeanVx": ux,
        f"{prefix}MeanVy": uy,
        f"{prefix}DownwardMassFraction": mdown / M,
        f"{prefix}NominalEOSPressure": nominal_eos,
        f"{prefix}NormalThermalStress": normal_thermal,
        f"{prefix}NormalAdvectiveStress": normal_advective,
        f"{prefix}NormalKineticStress": normal_total,
        f"{prefix}DownwardMomentumFluxProxy": down_flux,
        f"{prefix}UpwardMomentumFluxProxy": up_flux,
        f"{prefix}DirectionalMomentumFluxProxy": directional,
    }


def local_gas_metrics(parts, eta, eta_far, nx, ny, Lx, Ly, gas_type, gas_kbt,
                      jet_center, jet_width, control_half_width_over_jet,
                      impact_gap_min_cells, impact_gap_max_over_jet,
                      incident_half_width_over_jet, incident_height_over_jet,
                      incident_band_thickness_cells):
    """Gas observables restricted to the jet/impact neighbourhood.

    impact zone:
      |x-x0| <= control_half_width_over_jet * Wj
      eta(x)+gap_min <= y <= eta(x)+gap_max

    incident band:
      |x-x0| <= incident_half_width_over_jet * Wj
      thin horizontal band centred eta_far + incident_height_over_jet * Wj

    This intentionally excludes the remote gas return flow and outlets.
    """
    n, x, y, vx, vy, typ, mass, role = parts
    dx = Lx / nx; dy = Ly / ny; cell_area = dx * dy
    gap_min = impact_gap_min_cells * dy
    gap_max = impact_gap_max_over_jet * jet_width
    halfw = control_half_width_over_jet * jet_width

    impact_indices = []
    valid_area = 0.0
    for ix in range(nx):
        xc = (ix + 0.5) * dx
        if abs(xc - jet_center) > halfw or not math.isfinite(eta[ix]):
            continue
        yl = max(0.0, eta[ix] + gap_min)
        yh = min(Ly, eta[ix] + gap_max)
        if yh > yl:
            valid_area += dx * (yh - yl)
    for j in range(n):
        if role[j] != 1 or int(typ[j]) != gas_type:
            continue
        if abs(x[j] - jet_center) > halfw:
            continue
        ix = int(x[j] / dx)
        if ix < 0: ix = 0
        elif ix >= nx: ix = nx - 1
        if not math.isfinite(eta[ix]):
            continue
        gap = y[j] - eta[ix]
        if gap_min <= gap <= gap_max:
            impact_indices.append(j)

    result = weighted_gas_stats(parts, impact_indices, valid_area, gas_kbt, cell_area, "impactGas")

    # Incident band: measure the actual downward core before it turns at the bath.
    if math.isfinite(eta_far):
        ymid = eta_far + incident_height_over_jet * jet_width
        band_h = incident_band_thickness_cells * dy
        yl = max(0.0, ymid - 0.5 * band_h)
        yh = min(Ly, ymid + 0.5 * band_h)
        ihw = incident_half_width_over_jet * jet_width
        xl = max(0.0, jet_center - ihw)
        xh = min(Lx, jet_center + ihw)
        incident_area = max(0.0, xh - xl) * max(0.0, yh - yl)
        incident_indices = [j for j in range(n)
                            if role[j] == 1 and int(typ[j]) == gas_type
                            and xl <= x[j] <= xh and yl <= y[j] <= yh]
    else:
        ymid = math.nan
        incident_area = 0.0
        incident_indices = []
    result.update(weighted_gas_stats(parts, incident_indices, incident_area,
                                     gas_kbt, cell_area, "incidentGas"))
    result.update({
        "impactControlHalfWidth": halfw,
        "impactGapMin": gap_min,
        "impactGapMax": gap_max,
        "incidentBandCenterY": ymid,
        "incidentBandThickness": incident_band_thickness_cells * dy,
    })
    return result


def finite_mean(rows, key):
    vals = [float(r[key]) for r in rows if key in r and math.isfinite(float(r[key]))]
    return statistics.fmean(vals) if vals else math.nan


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--run-root", type=Path, required=True)
    ap.add_argument("--nx", type=int, required=True); ap.add_argument("--ny", type=int, required=True)
    ap.add_argument("--Lx", type=float, required=True); ap.add_argument("--Ly", type=float, required=True)
    ap.add_argument("--gamma", type=float, required=True)
    ap.add_argument("--liquid-type", type=int, default=1); ap.add_argument("--liquid-mass", type=float, default=1.0)
    ap.add_argument("--gas-type", type=int, default=2)
    ap.add_argument("--gas-kbt", type=float, default=math.nan,
                    help="nominal gas kBT, used only for a local ideal-gas pressure proxy")
    ap.add_argument("--jet-center-x", type=float, required=True); ap.add_argument("--jet-width", type=float, required=True)
    ap.add_argument("--dt", type=float, required=True)
    ap.add_argument("--jet-ramp-end-time", type=float, default=0.0,
                    help="samples at/after this time are also summarized as post-ramp")
    ap.add_argument("--gas-control-half-width-over-jet", type=float, default=1.5,
                    help="impact control half-width / jet width (default 1.5 => total width 3 Wj)")
    ap.add_argument("--impact-gap-min-cells", type=float, default=1.0,
                    help="exclude this many cells immediately above reconstructed interface")
    ap.add_argument("--impact-gap-max-over-jet", type=float, default=1.5,
                    help="top of impact control zone above local interface, in jet widths")
    ap.add_argument("--incident-half-width-over-jet", type=float, default=0.5,
                    help="incident-core half-width / jet width (default 0.5 => nozzle width)")
    ap.add_argument("--incident-height-over-jet", type=float, default=1.5,
                    help="incident probe height above far-field interface, in jet widths")
    ap.add_argument("--incident-band-thickness-cells", type=float, default=4.0)
    a = ap.parse_args()

    if a.gas_control_half_width_over_jet <= 0 or a.impact_gap_max_over_jet <= 0:
        raise SystemExit("gas control dimensions must be positive")
    if a.impact_gap_min_cells < 0 or a.incident_band_thickness_cells <= 0:
        raise SystemExit("gas probe thickness/gap must be non-negative/positive")

    out = a.run_root / "analysis"; out.mkdir(parents=True, exist_ok=True)
    states = []
    init = sorted((a.run_root / "init").glob("*.smpcd"))
    if init: states.append((0, init[0]))
    for p in sorted((a.run_root / "output").glob("state_step_*.smpcd")):
        states.append((step_of(p), p))
    if not states:
        raise SystemExit("no state files found")

    rows = []; final_profile = None; final_step = -1
    for step, p in states:
        parts = read_state_particles(p)
        eta, nliq = surface_from_particles(parts, a.nx, a.ny, a.Lx, a.Ly,
                                           a.gamma, a.liquid_type, a.liquid_mass)
        mm = interface_metrics(eta, a.Lx, a.jet_center_x, a.jet_width)
        gm = local_gas_metrics(
            parts, eta, mm["etaFar"], a.nx, a.ny, a.Lx, a.Ly,
            a.gas_type, a.gas_kbt, a.jet_center_x, a.jet_width,
            a.gas_control_half_width_over_jet, a.impact_gap_min_cells,
            a.impact_gap_max_over_jet, a.incident_half_width_over_jet,
            a.incident_height_over_jet, a.incident_band_thickness_cells)
        row = {"step": step, "time": step * a.dt, "state": str(p),
               "liquidParticles": nliq, **mm, **gm}
        rows.append(row)
        if step >= final_step:
            final_step = step; final_profile = eta
        print(
            f"[gas-jet-bath-analysis] step={step} depth={mm['depth']:.8g} "
            f"incidentVy={gm['incidentGasMeanVy']:.8g} "
            f"impactVy={gm['impactGasMeanVy']:.8g} "
            f"impactDownFrac={gm['impactGasDownwardMassFraction']:.5g} "
            f"impactDirPi={gm['impactGasDirectionalMomentumFluxProxy']:.8g}"
        )

    hist = out / "indentation_history.csv"
    with hist.open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0])); w.writeheader(); w.writerows(rows)

    gas_hist = out / "gas_local_history.csv"
    gas_keys = [k for k in rows[0] if k in ("step", "time", "state") or k.startswith("impactGas") or k.startswith("incidentGas") or k.startswith("impactControl") or k.startswith("impactGap") or k.startswith("incidentBand")]
    with gas_hist.open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=gas_keys); w.writeheader()
        for r in rows:
            w.writerow({k: r[k] for k in gas_keys})

    prof = out / "surface_profile_final.csv"
    dx = a.Lx / a.nx
    with prof.open("w", newline="") as f:
        w = csv.writer(f); w.writerow(["x", "eta"])
        for i, v in enumerate(final_profile or []):
            w.writerow([(i + 0.5) * dx, v])

    post = [r for r in rows if r["time"] >= a.jet_ramp_end_time]
    if not post:
        post = rows[-1:]
    last = rows[-1]
    dy = a.Ly / a.ny
    report = out / "gas_jet_liquid_bath_report.txt"
    report.write_text(
        "2-D planar gas jet / liquid bath — LOCAL interaction analysis\n"
        "=============================================================\n"
        "Gas qualification observables are restricted to the jet/impact neighbourhood.\n"
        "Whole-domain gas mean velocity is intentionally NOT used.\n\n"
        "Local control definition\n"
        "------------------------\n"
        f"jetCenterX = {a.jet_center_x:.12g}\n"
        f"jetWidth = {a.jet_width:.12g}\n"
        f"impactControlHalfWidth = {a.gas_control_half_width_over_jet:.12g} * jetWidth\n"
        f"impactGap = [{a.impact_gap_min_cells:.12g} cells, {a.impact_gap_max_over_jet:.12g} * jetWidth] above eta(x)\n"
        f"incidentCoreHalfWidth = {a.incident_half_width_over_jet:.12g} * jetWidth\n"
        f"incidentBandCenter = etaFar + {a.incident_height_over_jet:.12g} * jetWidth\n"
        f"incidentBandThickness = {a.incident_band_thickness_cells:.12g} cells\n"
        "Sign convention: meanVy < 0 is downward, i.e. incident toward the bath.\n"
        "DirectionalMomentumFluxProxy = downward m*vy^2/area - upward m*vy^2/area.\n"
        "Positive values therefore mean downward-directed local transport dominates.\n\n"
        "Final interface\n"
        "---------------\n"
        f"finalStep = {last['step']}\n"
        f"finalTime = {last['time']}\n"
        f"farFieldSurfaceHeight = {last['etaFar']:.12g}\n"
        f"minimumSurfaceHeight = {last['etaMin']:.12g}\n"
        f"indentationDepth = {last['depth']:.12g}\n"
        f"indentationDepthCells = {last['depth']/dy:.12g}\n"
        f"halfDepthWidth = {last['halfDepthWidth']:.12g}\n"
        f"halfDepthWidthOverJetWidth = {last['halfDepthWidth']/a.jet_width if math.isfinite(last['halfDepthWidth']) else math.nan:.12g}\n"
        f"symmetryRmsRelativeToDepth = {last['symmetryRmsRel']:.12g}\n\n"
        "Final local gas state\n"
        "---------------------\n"
        f"incidentGasMeanVy = {last['incidentGasMeanVy']:.12g}\n"
        f"incidentGasDownwardMassFraction = {last['incidentGasDownwardMassFraction']:.12g}\n"
        f"incidentGasDirectionalMomentumFluxProxy = {last['incidentGasDirectionalMomentumFluxProxy']:.12g}\n"
        f"impactGasMeanVy = {last['impactGasMeanVy']:.12g}\n"
        f"impactGasDownwardMassFraction = {last['impactGasDownwardMassFraction']:.12g}\n"
        f"impactGasOccupancyPerCell = {last['impactGasOccupancyPerCell']:.12g}\n"
        f"impactGasNominalEOSPressure = {last['impactGasNominalEOSPressure']:.12g}\n"
        f"impactGasNormalThermalStress = {last['impactGasNormalThermalStress']:.12g}\n"
        f"impactGasNormalAdvectiveStress = {last['impactGasNormalAdvectiveStress']:.12g}\n"
        f"impactGasDirectionalMomentumFluxProxy = {last['impactGasDirectionalMomentumFluxProxy']:.12g}\n\n"
        f"Post-ramp local means (t >= {a.jet_ramp_end_time:.12g}, snapshots={len(post)})\n"
        "------------------------------------------------------------\n"
        f"meanIncidentGasMeanVy = {finite_mean(post, 'incidentGasMeanVy'):.12g}\n"
        f"meanIncidentGasDownwardMassFraction = {finite_mean(post, 'incidentGasDownwardMassFraction'):.12g}\n"
        f"meanIncidentGasDirectionalMomentumFluxProxy = {finite_mean(post, 'incidentGasDirectionalMomentumFluxProxy'):.12g}\n"
        f"meanImpactGasMeanVy = {finite_mean(post, 'impactGasMeanVy'):.12g}\n"
        f"meanImpactGasDownwardMassFraction = {finite_mean(post, 'impactGasDownwardMassFraction'):.12g}\n"
        f"meanImpactGasOccupancyPerCell = {finite_mean(post, 'impactGasOccupancyPerCell'):.12g}\n"
        f"meanImpactGasDirectionalMomentumFluxProxy = {finite_mean(post, 'impactGasDirectionalMomentumFluxProxy'):.12g}\n\n"
        "Interpretation\n"
        "--------------\n"
        "The incident band checks that a downward jet actually reaches the bath neighbourhood.\n"
        "The impact control volume intentionally includes both incident and reflected/turning gas;\n"
        "its upward component is therefore physical and must not be confused with far-field return flow.\n"
        "Remote outlet/return-flow gas is excluded from these gas qualification observables.\n"
    )
    print(f"[gas-jet-bath-analysis] gasHistory={gas_hist}")
    print(f"[gas-jet-bath-analysis] report={report}")


if __name__ == "__main__":
    main()
