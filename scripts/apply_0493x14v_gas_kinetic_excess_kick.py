#!/usr/bin/env python3
from pathlib import Path
import re
import sys

PATH = Path("src/cuda_q6_resident_0400.cu")
MARK = "0493x14v — GAS KINETIC EXCESS KICK"


def fail(msg: str) -> None:
    raise SystemExit(f"[0493x14v] ERROR: {msg}")


def replace_once(text: str, old: str, new: str, label: str) -> str:
    n = text.count(old)
    if n != 1:
        fail(f"{label}: expected exactly one anchor, found {n}")
    return text.replace(old, new, 1)


def find_matching(text: str, start: int, op: str, cl: str) -> int:
    depth = 0
    state = "code"
    i = start
    while i < len(text):
        c = text[i]
        n = text[i + 1] if i + 1 < len(text) else ""
        if state == "line":
            if c == "\n":
                state = "code"
            i += 1
            continue
        if state == "block":
            if c == "*" and n == "/":
                state = "code"
                i += 2
            else:
                i += 1
            continue
        if state == "string":
            if c == "\\":
                i += 2
            elif c == '"':
                state = "code"
                i += 1
            else:
                i += 1
            continue
        if state == "char":
            if c == "\\":
                i += 2
            elif c == "'":
                state = "code"
                i += 1
            else:
                i += 1
            continue
        if c == "/" and n == "/":
            state = "line"
            i += 2
            continue
        if c == "/" and n == "*":
            state = "block"
            i += 2
            continue
        if c == '"':
            state = "string"
            i += 1
            continue
        if c == "'":
            state = "char"
            i += 1
            continue
        if c == op:
            depth += 1
        elif c == cl:
            depth -= 1
            if depth == 0:
                return i
        i += 1
    fail(f"unmatched {op}{cl}")


def find_function(text: str, name: str):
    for m in re.finditer(r"\b" + re.escape(name) + r"\s*\(", text):
        p0 = text.find("(", m.start())
        p1 = find_matching(text, p0, "(", ")")
        j = p1 + 1
        while j < len(text) and text[j].isspace():
            j += 1
        if j < len(text) and text[j] == "{":
            b0 = j
            b1 = find_matching(text, b0, "{", "}")
            return p0, p1, b0, b1
    fail(f"function definition not found: {name}")


def replace_function_region(text: str, name: str, transform):
    p0, p1, b0, b1 = find_function(text, name)
    start = text.rfind("\n", 0, p0) + 1
    region = text[start:b1 + 1]
    new_region = transform(region)
    return text[:start] + new_region + text[b1 + 1:]


def validate(text: str) -> None:
    checks = {
        "marker": MARK in text,
        "gate": "MPCD_X14V_GAS_KINETIC_EXCESS_KICK" in text,
        "owner impulse aggregate": "gasRawImpulseOwnerX0493x14v" in text,
        "post-relocation CIC mass delta": "q6_x14v_deposit_signed_phase_mass_cic" in text,
        "x6g equilibrium subtraction": "q6_x14v_prepare_excess_and_reset_candidates" in text,
        "fused final kick/redeposit": "q6_x14v_apply_cic_kick_and_deposit_moments" in text,
        "no new resident x14v buffer": "DeviceBuffer0400" not in text[text.index(MARK):text.index(MARK)+1400],
        "legacy final redeposit retained": "q6_thermostat_deposit_moments_from_cell_ids_0400<<<particleBlocks, threads>>>" in text,
        "x10v candidate build retained": "q6_x10v_build_velocity_swap_candidates<<<particleBlocks, threads>>>" in text,
        "x14s helper retained": "q6_x14s_correct_gas_pressure_potential_0493x6g" in text,
    }
    bad = [k for k, v in checks.items() if not v]
    for k, v in checks.items():
        print(f"[0493x14v] {'PASS' if v else 'FAIL'} {k}")
    if bad:
        fail("static validation failed: " + ", ".join(bad))


def main() -> int:
    if not PATH.is_file():
        fail(f"missing {PATH}; run from repository root")
    orig = PATH.read_text()
    if MARK in orig:
        print("[0493x14v] already applied; validating current source")
        validate(orig)
        return 0

    for req in (
        "0493x14l-gas-specular",
        "0493x14s-x6g-accessible-volume",
        "q6_x10n_apply_continuous_moving_interface",
        "q6_x10cic_filter_phase_alpha",
        "q6_x10v_build_velocity_swap_candidates",
        "q6_x10v_apply_local_velocity_swaps",
        "q6_thermostat_deposit_moments_from_cell_ids_0400",
        "kineticMovingWallVn0493x10m",
        "kineticRefPx0493x9t",
        "kineticTxPx0493x9t",
    ):
        if req not in orig:
            fail(f"missing prerequisite: {req}")

    text = orig

    # ------------------------------------------------------------------
    # 1) Forward declaration needed by the earlier x10n particle kernel.
    #    Definition comes later beside the existing kinetic-CIC helpers.
    # ------------------------------------------------------------------
    anchor = '''    return j * nx + i;\n}\n\n// =============================================================================\n// 0493x10u-oneforone — CONSERVATIVE ONE-PARTICLE SUPPORT RELOCATION\n'''
    add = '''    return j * nx + i;\n}\n\n// 0493x14v forward declaration.  The implementation is placed beside the\n// existing x10cic helpers so both paths use exactly the same CIC convention.\n__device__ __forceinline__ void q6_x14v_deposit_signed_phase_mass_cic(\n    double x, double y, double massDelta,\n    int nx, int ny, double lx, double ly,\n    int periodicX, int periodicY,\n    double* massCIC);\n\n// =============================================================================\n// 0493x10u-oneforone — CONSERVATIVE ONE-PARTICLE SUPPORT RELOCATION\n'''
    text = replace_once(text, anchor, add, "x14v CIC mass forward declaration")

    # ------------------------------------------------------------------
    # 2) Thread x14v scratch aliases through the existing continuous-wall
    #    particle kernel.  No new pointer/buffer is allocated.
    # ------------------------------------------------------------------
    def patch_x10n(region: str) -> str:
        old = '''    int gasSpecularReflection0493x14l,\n    int nx, int ny,\n'''
        new = '''    int gasSpecularReflection0493x14l,\n    int gasKineticExcessKick0493x14v,\n    double* gasRawImpulseOwnerX0493x14v,\n    double* gasRawImpulseOwnerY0493x14v,\n    double* liquidMassCIC0493x14v,\n    int nx, int ny,\n'''
        region = replace_once(region, old, new, "x10n x14v kernel arguments")

        old = '''            if (!(localThermalCooling0493x12a &&\n                  gasSpecularThisParticle0493x14l)) {\n                atomic_add_double_0400(\n                    &wallImpulseX[bestSeg.ownerCell], best.impulseWallX);\n                atomic_add_double_0400(\n                    &wallImpulseY[bestSeg.ownerCell], best.impulseWallY);\n            }\n\n            if (audit) {\n'''
        new = '''            if (!(localThermalCooling0493x12a &&\n                  gasSpecularThisParticle0493x14l)) {\n                atomic_add_double_0400(\n                    &wallImpulseX[bestSeg.ownerCell], best.impulseWallX);\n                atomic_add_double_0400(\n                    &wallImpulseY[bestSeg.ownerCell], best.impulseWallY);\n            }\n\n            // 0493x14v: x14l already computed the exact reaction impulse of\n            // each gas reflection.  Aggregate it by the already-known branch\n            // owner (two FP64 atomics/hit).  Do NOT touch x12a's impulse-scale\n            // scratch; kineticRefPx/Py are dead on the x10o simple-wall path.\n            if (gasKineticExcessKick0493x14v &&\n                gasSpecularThisParticle0493x14l &&\n                bestSeg.ownerCell >= 0 && bestSeg.ownerCell < cells.numCells) {\n                atomic_add_double_0400(\n                    &gasRawImpulseOwnerX0493x14v[bestSeg.ownerCell],\n                    best.impulseWallX);\n                atomic_add_double_0400(\n                    &gasRawImpulseOwnerY0493x14v[bestSeg.ownerCell],\n                    best.impulseWallY);\n            }\n\n            if (audit) {\n'''
        region = replace_once(region, old, new, "x10n gas owner impulse aggregate")

        old = '''        particles.x[p] = x0 + corrX;\n        particles.y[p] = y0 + corrY;\n        // 0493x10u-oneforone leaves particles.mass untouched.  In relocation\n'''
        new = '''        particles.x[p] = x0 + corrX;\n        particles.y[p] = y0 + corrY;\n\n        // 0493x14v keeps an exact post-x10u liquid CIC mass without a second\n        // O(Nparticle) deposit: start from the already-computed pre-wall CIC\n        // mass and update only particles whose support position actually moved.\n        // x10v changes velocities only, so this mass stays valid through the\n        // later collective kick.\n        if (gasKineticExcessKick0493x14v && phaseSense0493x14k > 0 &&\n            liquidMassCIC0493x14v != nullptr &&\n            (fabs(corrX) > 0.0 || fabs(corrY) > 0.0)) {\n            q6_x14v_deposit_signed_phase_mass_cic(\n                x0, y0, -mass, nx, ny, lx, ly, periodicX, periodicY,\n                liquidMassCIC0493x14v);\n            q6_x14v_deposit_signed_phase_mass_cic(\n                particles.x[p], particles.y[p], mass,\n                nx, ny, lx, ly, periodicX, periodicY,\n                liquidMassCIC0493x14v);\n        }\n        // 0493x10u-oneforone leaves particles.mass untouched.  In relocation\n'''
        region = replace_once(region, old, new, "x10n post-relocation CIC mass update")
        return region

    text = replace_function_region(text, "q6_x10n_apply_continuous_moving_interface", patch_x10n)

    # ------------------------------------------------------------------
    # 3) Implement signed CIC mass update beside the exact x10cic convention.
    # ------------------------------------------------------------------
    anchor = '''    if (w11 > 0.0) atomic_add_double_0400(&rawCIC[iy1 * nx + ix1], normalizedMass * w11);\n}\n\n// Fuse CIC into the total-A moment pass already mandatory in x9x.  Therefore\n'''
    add = r'''    if (w11 > 0.0) atomic_add_double_0400(&rawCIC[iy1 * nx + ix1], normalizedMass * w11);
}

// =============================================================================
// 0493x14v — GAS KINETIC EXCESS KICK
// =============================================================================
// x14t qualified the thermodynamic normal pressure already supplied by x6g.
// x14u then showed that the directed normal momentum lost by x14l specular
// gas reflection is not transferred instantaneously to the liquid.  x14v
// adds ONLY that missing non-equilibrium part:
//
//   J_excess = sum(J_gas->wall, actual reflections) - J_pressure_already_x6g
//
// The reaction is aggregated on the interface, then distributed collectively
// to phase A through the already-qualified kinetic CIC geometry.  Scratch-only
// implementation: no new resident buffer, no host transfer, no new particle
// pass.  The final kick is fused into the cell-moment redeposit already present
// after x10v.  x10u/x10v/x12a laws themselves are unchanged.

__device__ __forceinline__ void q6_x14v_deposit_signed_phase_mass_cic(
    double x, double y, double massDelta,
    int nx, int ny, double lx, double ly,
    int periodicX, int periodicY,
    double* massCIC) {
    if (massCIC == nullptr || massDelta == 0.0 || !isfinite(massDelta) ||
        nx <= 0 || ny <= 0 || !(lx > 0.0) || !(ly > 0.0)) return;
    const double invDx = static_cast<double>(nx) / lx;
    const double invDy = static_cast<double>(ny) / ly;
    if (periodicX) x -= floor(x / lx) * lx;
    else x = fmin(fmax(x, 0.0), nextafter(lx, 0.0));
    if (periodicY) y -= floor(y / ly) * ly;
    else y = fmin(fmax(y, 0.0), nextafter(ly, 0.0));
    const double qx = x * invDx - 0.5;
    const double qy = y * invDy - 0.5;
    int ix0=0, ix1=0, iy0=0, iy1=0;
    double wx0=0.0, wx1=0.0, wy0=0.0, wy1=0.0;
    q6_x10cic_axis_pair(qx, nx, periodicX, &ix0, &ix1, &wx0, &wx1);
    q6_x10cic_axis_pair(qy, ny, periodicY, &iy0, &iy1, &wy0, &wy1);
    const double w00=wx0*wy0, w10=wx1*wy0, w01=wx0*wy1, w11=wx1*wy1;
    if (w00 > 0.0) atomic_add_double_0400(&massCIC[iy0*nx+ix0], massDelta*w00);
    if (w10 > 0.0) atomic_add_double_0400(&massCIC[iy0*nx+ix1], massDelta*w10);
    if (w01 > 0.0) atomic_add_double_0400(&massCIC[iy1*nx+ix0], massDelta*w01);
    if (w11 > 0.0) atomic_add_double_0400(&massCIC[iy1*nx+ix1], massDelta*w11);
}

// Fuse CIC into the total-A moment pass already mandatory in x9x.  Therefore
'''
    text = replace_once(text, anchor, add, "x14v signed CIC mass helper")

    # ------------------------------------------------------------------
    # 4) Preserve the raw (unfiltered) liquid CIC mass in x10m wallVn scratch.
    #    The extra write is fused into the existing CIC filter cell kernel.
    # ------------------------------------------------------------------
    def patch_filter(region: str) -> str:
        old = '''    int periodicY,\n    double lambda) {\n'''
        new = '''    int periodicY,\n    double lambda,\n    double phaseAReferenceCellMass0493x14v,\n    double* liquidMassCIC0493x14v) {\n'''
        region = replace_once(region, old, new, "x10cic filter x14v args")
        old = '''        const double center = rawCIC[c];\n        double lap = 0.0;\n'''
        new = '''        const double center = rawCIC[c];\n        if (liquidMassCIC0493x14v != nullptr) {\n            liquidMassCIC0493x14v[c] =\n                center * phaseAReferenceCellMass0493x14v;\n        }\n        double lap = 0.0;\n'''
        region = replace_once(region, old, new, "x10cic raw mass save")
        return region

    text = replace_function_region(text, "q6_x10cic_filter_phase_alpha", patch_filter)

    # ------------------------------------------------------------------
    # 5) Insert the O(Ninterface) equilibrium subtraction + supported CIC
    #    scatter and the fused final particle kick/redeposit after the x14s
    #    pressure helper, where both x10cic and x14s helpers are available.
    # ------------------------------------------------------------------
    anchor = '''    return (rawGaugePotential0493x6g + referencePotential0493x6g) /\n               fraction0493x14s -\n           referencePotential0493x6g;\n}\n\n__global__ void q6_build_phase_fill_resident_0493x6c(\n'''
    add = r'''    return (rawGaugePotential0493x6g + referencePotential0493x6g) /
               fraction0493x14s -
           referencePotential0493x6g;
}

__device__ __forceinline__ bool q6_x14v_cic_stencil(
    double x, double y,
    int nx, int ny, double lx, double ly,
    int periodicX, int periodicY,
    int ids[4], double w[4]) {
    if (nx <= 0 || ny <= 0 || !(lx > 0.0) || !(ly > 0.0)) return false;
    if (periodicX) x -= floor(x / lx) * lx;
    else x = fmin(fmax(x, 0.0), nextafter(lx, 0.0));
    if (periodicY) y -= floor(y / ly) * ly;
    else y = fmin(fmax(y, 0.0), nextafter(ly, 0.0));
    const double qx = x * static_cast<double>(nx) / lx - 0.5;
    const double qy = y * static_cast<double>(ny) / ly - 0.5;
    int ix0=0, ix1=0, iy0=0, iy1=0;
    double wx0=0.0, wx1=0.0, wy0=0.0, wy1=0.0;
    q6_x10cic_axis_pair(qx, nx, periodicX, &ix0, &ix1, &wx0, &wx1);
    q6_x10cic_axis_pair(qy, ny, periodicY, &iy0, &iy1, &wy0, &wy1);
    ids[0]=iy0*nx+ix0; w[0]=wx0*wy0;
    ids[1]=iy0*nx+ix1; w[1]=wx1*wy0;
    ids[2]=iy1*nx+ix0; w[2]=wx0*wy1;
    ids[3]=iy1*nx+ix1; w[3]=wx1*wy1;
    return true;
}

__device__ __forceinline__ void q6_x14v_scatter_supported_impulse(
    double x, double y, double jx, double jy,
    const double* liquidMassCIC, double massFloor,
    int nx, int ny, double lx, double ly,
    int periodicX, int periodicY,
    double* kickX, double* kickY) {
    if ((jx == 0.0 && jy == 0.0) || !isfinite(jx) || !isfinite(jy) ||
        liquidMassCIC == nullptr || kickX == nullptr || kickY == nullptr) return;
    int ids[4]; double w[4];
    if (!q6_x14v_cic_stencil(
            x, y, nx, ny, lx, ly, periodicX, periodicY, ids, w)) return;
    double supported = 0.0;
    for (int k=0; k<4; ++k) {
        const double m = liquidMassCIC[ids[k]];
        if (w[k] > 0.0 && isfinite(m) && m > massFloor) supported += w[k];
    }
    if (supported > 1.0e-14 && isfinite(supported)) {
        const double inv = 1.0 / supported;
        for (int k=0; k<4; ++k) {
            const double m = liquidMassCIC[ids[k]];
            if (!(w[k] > 0.0) || !isfinite(m) || !(m > massFloor)) continue;
            const double wk = w[k] * inv;
            atomic_add_double_0400(&kickX[ids[k]], jx * wk);
            atomic_add_double_0400(&kickY[ids[k]], jy * wk);
        }
        return;
    }

    // Defensive support fallback: only O(Ninterface), never a particle search.
    // Deposit the whole owner impulse on the nearest ring containing any
    // positive liquid-CIC mass.  This preserves total momentum even if the
    // thermal wall is locally farther out than the four immediate CIC nodes.
    const int pc = q6_x10n_position_cell(x, y, nx, ny, lx, ly, periodicX, periodicY);
    if (pc < 0) return;
    const int pi = pc % nx, pj = pc / nx;
    for (int radius=0; radius<=2; ++radius) {
        int best = -1;
        double bestMass = massFloor;
        for (int dj=-radius; dj<=radius; ++dj) {
            for (int di=-radius; di<=radius; ++di) {
                if (radius > 0 && di != -radius && di != radius &&
                    dj != -radius && dj != radius) continue;
                const int c = q6_x10n_cell_index(
                    pi+di, pj+dj, nx, ny, periodicX, periodicY);
                if (c < 0) continue;
                const double m = liquidMassCIC[c];
                if (isfinite(m) && m > bestMass) {
                    bestMass = m;
                    best = c;
                }
            }
        }
        if (best >= 0) {
            atomic_add_double_0400(&kickX[best], jx);
            atomic_add_double_0400(&kickY[best], jy);
            return;
        }
    }
}

__device__ __forceinline__ int q6_x14v_nearest_q6_gas_cell(
    double mx, double my, double nxOut, double nyOut,
    const double* alphaQ6,
    int nx, int ny, double lx, double ly,
    int periodicX, int periodicY) {
    if (!alphaQ6) return -1;
    const double h = fmin(lx/static_cast<double>(nx), ly/static_cast<double>(ny));
    constexpr double offsets[5] = {0.0, 0.35, 0.75, 1.25, 1.75};
    for (int k=0; k<5; ++k) {
        const int c = q6_x10n_position_cell(
            mx + offsets[k]*h*nxOut,
            my + offsets[k]*h*nyOut,
            nx, ny, lx, ly, periodicX, periodicY);
        if (c >= 0) {
            const double a = alphaQ6[c];
            if (isfinite(a) && a < 0.5) return c;
        }
    }
    const int pc = q6_x10n_position_cell(mx, my, nx, ny, lx, ly, periodicX, periodicY);
    if (pc < 0) return -1;
    const int pi = pc % nx, pj = pc / nx;
    int best = -1;
    double bestAlpha = -1.0e300;
    for (int radius=1; radius<=2; ++radius) {
        for (int dj=-radius; dj<=radius; ++dj) {
            for (int di=-radius; di<=radius; ++di) {
                const int c = q6_x10n_cell_index(
                    pi+di, pj+dj, nx, ny, periodicX, periodicY);
                if (c < 0) continue;
                const double a = alphaQ6[c];
                if (isfinite(a) && a < 0.5 && a > bestAlpha) {
                    bestAlpha = a;
                    best = c;
                }
            }
        }
        if (best >= 0) break;
    }
    return best;
}

__device__ __forceinline__ double q6_x14v_x6g_represented_pressure(
    double mx, double my, double nxOut, double nyOut,
    const double* alphaQ6,
    const double* gasPressurePotential,
    int gasPressureMode,
    double pressureReference,
    double constantPressure,
    double pressureScale,
    double referencePotential,
    double potentialToPressure,
    int nx, int ny, double lx, double ly,
    int periodicX, int periodicY) {
    if (gasPressureMode == static_cast<int>(PhaseGasPressureMode0493x6g::Constant)) {
        const double p = pressureReference +
            pressureScale * (constantPressure - pressureReference);
        return isfinite(p) ? fmax(0.0, p) : fmax(0.0, pressureReference);
    }
    const int c = q6_x14v_nearest_q6_gas_cell(
        mx, my, nxOut, nyOut, alphaQ6,
        nx, ny, lx, ly, periodicX, periodicY);
    if (c < 0 || gasPressurePotential == nullptr)
        return fmax(0.0, pressureReference);
    double gauge = gasPressurePotential[c];
    if (gasPressureMode ==
        static_cast<int>(PhaseGasPressureMode0493x6g::EosAccessibleVolume)) {
        gauge = q6_x14s_correct_gas_pressure_potential_0493x6g(
            gauge, alphaQ6[c], referencePotential);
    }
    const double p = pressureReference + gauge * potentialToPressure;
    return isfinite(p) ? fmax(0.0, p) : fmax(0.0, pressureReference);
}

// One cell kernel replaces the two x10v candidate-sentinel memsets when x14v
// is active.  It also subtracts the pressure traction already represented by
// x6g and scatters only the residual kinetic impulse onto supported liquid CIC
// nodes.  The raw gas impulse is already aggregated by owner in q6_x10n.
__global__ void q6_x14v_prepare_excess_and_reset_candidates(
    int numCells,
    int nx, int ny, double lx, double ly, double dt,
    int periodicX, int periodicY,
    const unsigned char* segCount,
    const double* segAx, const double* segAy,
    const double* segBx, const double* segBy,
    const double* segUax, const double* segUay,
    const double* segUbx, const double* segUby,
    const double* alphaQ6,
    const double* gasPressurePotential,
    int gasPressureMode,
    double pressureReference,
    double constantPressure,
    double pressureScale,
    double referencePotential,
    double potentialToPressure,
    const double* rawOwnerX,
    const double* rawOwnerY,
    const double* liquidMassCIC,
    double massFloor,
    double* kickX,
    double* kickY,
    unsigned long long* candidate0,
    unsigned long long* candidate1) {
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    const int stride = blockDim.x * gridDim.x;
    const unsigned long long empty = ~0ull;
    for (int owner=idx; owner<numCells; owner+=stride) {
        candidate0[owner] = empty;
        candidate1[owner] = empty;
        const int ns = segCount ? min(2, static_cast<int>(segCount[owner])) : 0;
        if (ns <= 0) continue;
        const double rawX = rawOwnerX ? rawOwnerX[owner] : 0.0;
        const double rawY = rawOwnerY ? rawOwnerY[owner] : 0.0;

        double len[2] = {0.0,0.0};
        double tx[2] = {0.0,0.0};
        double ty[2] = {0.0,0.0};
        double mx[2] = {0.0,0.0};
        double my[2] = {0.0,0.0};
        double totalLen = 0.0;
        for (int slot=0; slot<ns; ++slot) {
            const int s = 2*owner + slot;
            double dxs = q6_x10m_minimum_image(segBx[s]-segAx[s], lx, periodicX);
            double dys = q6_x10m_minimum_image(segBy[s]-segAy[s], ly, periodicY);
            dxs += 0.5*dt*(segUbx[s]-segUax[s]);
            dys += 0.5*dt*(segUby[s]-segUay[s]);
            const double L = sqrt(dxs*dxs + dys*dys);
            if (!(L > 1.0e-14*fmin(lx/static_cast<double>(nx),
                                  ly/static_cast<double>(ny))) || !isfinite(L))
                continue;
            tx[slot]=dxs; ty[slot]=dys; len[slot]=L; totalLen += L;
            const double axm = segAx[s] + 0.5*dt*segUax[s];
            const double aym = segAy[s] + 0.5*dt*segUay[s];
            mx[slot] = axm + 0.5*dxs;
            my[slot] = aym + 0.5*dys;
        }
        if (!(totalLen > 0.0) || !isfinite(totalLen)) continue;

        for (int slot=0; slot<ns; ++slot) {
            if (!(len[slot] > 0.0)) continue;
            const double frac = len[slot] / totalLen;
            const double nxOut = ty[slot] / len[slot];
            const double nyOut = -tx[slot] / len[slot];
            const double pGas = q6_x14v_x6g_represented_pressure(
                mx[slot], my[slot], nxOut, nyOut,
                alphaQ6, gasPressurePotential, gasPressureMode,
                pressureReference, constantPressure, pressureScale,
                referencePotential, potentialToPressure,
                nx, ny, lx, ly, periodicX, periodicY);

            // Right normal of oriented A->B is liquid->gas.  Gas pressure on
            // the liquid is -p*n, and n*dL=(dy,-dx), hence
            // J_eq = p*dt*(-dy,+dx).  Mid-step tangent integrates exactly for
            // linearly moving endpoints.
            const double jeqX = pGas * dt * (-ty[slot]);
            const double jeqY = pGas * dt * ( tx[slot]);
            const double jexX = rawX * frac - jeqX;
            const double jexY = rawY * frac - jeqY;
            q6_x14v_scatter_supported_impulse(
                mx[slot], my[slot], jexX, jexY,
                liquidMassCIC, massFloor,
                nx, ny, lx, ly, periodicX, periodicY,
                kickX, kickY);
        }
    }
}

// Replace the ordinary post-kinetic moment redeposit, so x14v adds no new
// O(Nparticle) traversal.  The CIC denominator is the exact post-x10u phase-A
// mass: pre-wall mass saved by the x10cic filter plus signed relocation deltas.
__global__ void q6_x14v_apply_cic_kick_and_deposit_moments(
    CudaParticleDeviceView particles,
    CudaCellWorkspaceDeviceView cells,
    std::uint64_t nParticles,
    std::uint32_t phaseAType,
    const double* liquidMassCIC,
    const double* kickX,
    const double* kickY,
    double massFloor,
    int nx, int ny, double lx, double ly,
    int periodicX, int periodicY) {
    const std::uint64_t idx =
        static_cast<std::uint64_t>(blockIdx.x)*blockDim.x + threadIdx.x;
    const std::uint64_t stride =
        static_cast<std::uint64_t>(blockDim.x)*gridDim.x;
    for (std::uint64_t i=idx; i<nParticles; i+=stride) {
        if (particles.role && particles.role[i] != kParticleRoleFluid) continue;
        const int c = cells.cellId[i];
        if (c < 0 || c >= cells.numCells) continue;
        const double m = particles.mass ? particles.mass[i] : 1.0;
        if (!(m > 0.0) || !isfinite(m)) continue;

        if (particles.type && particles.type[i] == phaseAType &&
            liquidMassCIC && kickX && kickY) {
            int ids[4]; double w[4];
            if (q6_x14v_cic_stencil(
                    particles.x[i], particles.y[i],
                    nx, ny, lx, ly, periodicX, periodicY, ids, w)) {
                double dvx=0.0, dvy=0.0;
                for (int k=0; k<4; ++k) {
                    if (!(w[k] > 0.0)) continue;
                    const double mg = liquidMassCIC[ids[k]];
                    if (!isfinite(mg) || !(mg > massFloor)) continue;
                    dvx += w[k] * kickX[ids[k]] / mg;
                    dvy += w[k] * kickY[ids[k]] / mg;
                }
                if (isfinite(dvx) && isfinite(dvy)) {
                    particles.vx[i] += dvx;
                    particles.vy[i] += dvy;
                }
            }
        }

        atomicAdd(&cells.count[c], 1u);
        atomic_add_double_0400(&cells.cellMass[c], m);
        atomic_add_double_0400(&cells.cellPx[c], m * particles.vx[i]);
        atomic_add_double_0400(&cells.cellPy[c], m * particles.vy[i]);
    }
}

__global__ void q6_build_phase_fill_resident_0493x6c(
'''
    text = replace_once(text, anchor, add, "x14v prep and fused kick kernels")

    # ------------------------------------------------------------------
    # 6) Pass x6g state into the kinetic stage from the already-resolved host
    #    variables.  Do not reparse environment or alter x6g itself.
    # ------------------------------------------------------------------
    def patch_apply(region: str) -> str:
        old = '''    const double* phaseAlphaQ60493x6c,\n    bool geometryValid0493x6c) {\n'''
        new = '''    const double* phaseAlphaQ60493x6c,\n    bool geometryValid0493x6c,\n    bool phaseGasPressureEnabled0493x14v,\n    PhaseGasPressureMode0493x6g phaseGasPressureMode0493x14v,\n    double phaseGasPressureReference0493x14v,\n    double phaseGasPressureConstant0493x14v,\n    double phaseGasPressureScale0493x14v) {\n'''
        region = replace_once(region, old, new, "apply kinetic x6g arguments")

        old = '''    const bool oneForOneNormalOnly0493x13o =\n        oneForOneVelocitySwap0493x10v && oneForOneNormalOnlyRequested0493x13o;\n    const bool thermalPhaseLimiterRequested0493x10w =\n'''
        new = '''    const bool oneForOneNormalOnly0493x13o =\n        oneForOneVelocitySwap0493x10v && oneForOneNormalOnlyRequested0493x13o;\n\n    const bool gasKineticExcessKickRequested0493x14v =\n        env_int_0400("MPCD_X14V_GAS_KINETIC_EXCESS_KICK", 0) != 0;\n    if (gasKineticExcessKickRequested0493x14v &&\n        (!q6ThermalInterfaceWall0493x10o ||\n         !kineticInterfaceCIC0493x10cic ||\n         !quadraticInterface0493x10poly ||\n         !oneForOneRelocation0493x10u ||\n         !oneForOneVelocitySwap0493x10v ||\n         !bilateralRelocation0493x14k ||\n         !gasSpecularReflection0493x14l)) {\n        throw std::runtime_error(\n            "0493x14v kinetic excess kick requires x10o+CIC+Q2+x10u+x10v + bilateral x14l gas-specular closure");\n    }\n    if (gasKineticExcessKickRequested0493x14v &&\n        !phaseGasPressureEnabled0493x14v) {\n        throw std::runtime_error(\n            "0493x14v kinetic excess kick requires x6g gas pressure so the already-represented thermodynamic traction can be subtracted");\n    }\n    if (gasKineticExcessKickRequested0493x14v &&\n        phaseAUniqueProjectedType0493x10cic != 1) {\n        throw std::runtime_error(\n            "0493x14v optimized CIC kick currently requires phase A to be the unique projected liquid type");\n    }\n    const bool gasKineticExcessKick0493x14v =\n        gasKineticExcessKickRequested0493x14v;\n    static bool gasKineticExcessKickReported0493x14v = false;\n    if (gasKineticExcessKick0493x14v &&\n        !gasKineticExcessKickReported0493x14v) {\n        std::cout\n            << "[0493x14v-gas-kinetic-excess] enabled=1"\n               " raw=gas-specular-owner-aggregate"\n               " subtract=x6g-thermodynamic-traction"\n               " transfer=collective-liquid-CIC"\n               " storage=reused-x9t/x10m"\n               " newParticlePass=0"\n               " liquidLaws=UNCHANGED"\n            << std::endl;\n        gasKineticExcessKickReported0493x14v = true;\n    }\n\n    const bool thermalPhaseLimiterRequested0493x10w =\n'''
        region = replace_once(region, old, new, "x14v host gate")

        old = '''        q6_x10cic_filter_phase_alpha<<<cellBlocks, threads>>>(\n            ws.kineticMovingWallImpulseX0493x10m.data(),\n            ws.kineticPhaseAlphaCIC0493x10cic.data(),\n            grid.Nx, grid.Ny, periodicX, periodicY,\n            kPhaseGeometryFilterLambda0493x6c);\n'''
        new = '''        q6_x10cic_filter_phase_alpha<<<cellBlocks, threads>>>(\n            ws.kineticMovingWallImpulseX0493x10m.data(),\n            ws.kineticPhaseAlphaCIC0493x10cic.data(),\n            grid.Nx, grid.Ny, periodicX, periodicY,\n            kPhaseGeometryFilterLambda0493x6c,\n            phaseAReferenceCellMass0493x10cic,\n            gasKineticExcessKick0493x14v\n                ? ws.kineticMovingWallVn0493x10m.data()\n                : nullptr);\n'''
        region = replace_once(region, old, new, "x10cic filter mass scratch launch")

        old = '''            phaseAType, phaseBType0493x14k,\n            bilateralRelocation0493x14k ? 1 : 0,\n            gasSpecularReflection0493x14l ? 1 : 0,\n            grid.Nx, grid.Ny, params.Lx, params.Ly, params.dt,\n'''
        new = '''            phaseAType, phaseBType0493x14k,\n            bilateralRelocation0493x14k ? 1 : 0,\n            gasSpecularReflection0493x14l ? 1 : 0,\n            gasKineticExcessKick0493x14v ? 1 : 0,\n            gasKineticExcessKick0493x14v\n                ? ws.kineticRefPx0493x9t.data() : nullptr,\n            gasKineticExcessKick0493x14v\n                ? ws.kineticRefPy0493x9t.data() : nullptr,\n            gasKineticExcessKick0493x14v\n                ? ws.kineticMovingWallVn0493x10m.data() : nullptr,\n            grid.Nx, grid.Ny, params.Lx, params.Ly, params.dt,\n'''
        region = replace_once(region, old, new, "x10n x14v launch args")

        old = '''            check_cuda_0400(cudaMemset(\n                ws.kineticMovingWallImpulseX0493x10m.data(), 0xff,\n                candidateBytes0493x10v),\n                "0493x10v candidate0 sentinel fill");\n            check_cuda_0400(cudaMemset(\n                ws.kineticMovingWallImpulseY0493x10m.data(), 0xff,\n                candidateBytes0493x10v),\n                "0493x10v candidate1 sentinel fill");\n\n            auto* candidate00493x10v = reinterpret_cast<unsigned long long*>(\n                ws.kineticMovingWallImpulseX0493x10m.data());\n            auto* candidate10493x10v = reinterpret_cast<unsigned long long*>(\n                ws.kineticMovingWallImpulseY0493x10m.data());\n'''
        new = '''            auto* candidate00493x10v = reinterpret_cast<unsigned long long*>(\n                ws.kineticMovingWallImpulseX0493x10m.data());\n            auto* candidate10493x10v = reinterpret_cast<unsigned long long*>(\n                ws.kineticMovingWallImpulseY0493x10m.data());\n            if (gasKineticExcessKick0493x14v) {\n                const double dx0493x14v = params.Lx / static_cast<double>(grid.Nx);\n                const double dy0493x14v = params.Ly / static_cast<double>(grid.Ny);\n                const double cellArea0493x14v = dx0493x14v * dy0493x14v;\n                const double referencePotential0493x14v =\n                    phaseAReferenceCellMass0493x10cic > 0.0\n                        ? params.dt * phaseGasPressureScale0493x14v *\n                              phaseGasPressureReference0493x14v *\n                              cellArea0493x14v /\n                              phaseAReferenceCellMass0493x10cic\n                        : 0.0;\n                const double potentialToPressure0493x14v =\n                    (params.dt > 0.0 && cellArea0493x14v > 0.0)\n                        ? phaseAReferenceCellMass0493x10cic /\n                              (params.dt * cellArea0493x14v)\n                        : 0.0;\n                const double massFloor0493x14v =\n                    1.0e-14 * fmax(1.0, phaseAReferenceCellMass0493x10cic);\n                q6_x14v_prepare_excess_and_reset_candidates<<<cellBlocks, threads>>>(\n                    grid.numCells, grid.Nx, grid.Ny,\n                    params.Lx, params.Ly, params.dt,\n                    periodicX, periodicY,\n                    ws.kineticContinuousSegCount0493x10n.data(),\n                    ws.kineticContinuousSegAx0493x10n.data(),\n                    ws.kineticContinuousSegAy0493x10n.data(),\n                    ws.kineticContinuousSegBx0493x10n.data(),\n                    ws.kineticContinuousSegBy0493x10n.data(),\n                    ws.kineticContinuousSegUax0493x10n.data(),\n                    ws.kineticContinuousSegUay0493x10n.data(),\n                    ws.kineticContinuousSegUbx0493x10n.data(),\n                    ws.kineticContinuousSegUby0493x10n.data(),\n                    phaseAlphaQ60493x6c,\n                    ws.phaseGasPressurePotential0493x6a.data(),\n                    static_cast<int>(phaseGasPressureMode0493x14v),\n                    phaseGasPressureReference0493x14v,\n                    phaseGasPressureConstant0493x14v,\n                    phaseGasPressureScale0493x14v,\n                    referencePotential0493x14v,\n                    potentialToPressure0493x14v,\n                    ws.kineticRefPx0493x9t.data(),\n                    ws.kineticRefPy0493x9t.data(),\n                    ws.kineticMovingWallVn0493x10m.data(),\n                    massFloor0493x14v,\n                    ws.kineticTxPx0493x9t.data(),\n                    ws.kineticTxPy0493x9t.data(),\n                    candidate00493x10v, candidate10493x10v);\n                check_cuda_0400(\n                    cudaGetLastError(),\n                    "0493x14v excess-traction prepare + x10v candidate reset launch");\n            } else {\n                check_cuda_0400(cudaMemset(\n                    ws.kineticMovingWallImpulseX0493x10m.data(), 0xff,\n                    candidateBytes0493x10v),\n                    "0493x10v candidate0 sentinel fill");\n                check_cuda_0400(cudaMemset(\n                    ws.kineticMovingWallImpulseY0493x10m.data(), 0xff,\n                    candidateBytes0493x10v),\n                    "0493x10v candidate1 sentinel fill");\n            }\n\n'''
        region = replace_once(region, old, new, "x14v prepare fused with candidate reset")

        old = '''    q6_thermostat_deposit_moments_from_cell_ids_0400<<<particleBlocks, threads>>>(particles, cells, nParticles, 0, 0u);\n    check_cuda_0400(cudaGetLastError(), "0493x9x cell moments redeposit launch");\n'''
        new = '''    if (gasKineticExcessKick0493x14v) {\n        const double massFloor0493x14v =\n            1.0e-14 * fmax(1.0, phaseAReferenceCellMass0493x10cic);\n        q6_x14v_apply_cic_kick_and_deposit_moments<<<particleBlocks, threads>>>(\n            particles, cells, nParticles, phaseAType,\n            ws.kineticMovingWallVn0493x10m.data(),\n            ws.kineticTxPx0493x9t.data(),\n            ws.kineticTxPy0493x9t.data(),\n            massFloor0493x14v,\n            grid.Nx, grid.Ny, params.Lx, params.Ly, periodicX, periodicY);\n        check_cuda_0400(\n            cudaGetLastError(),\n            "0493x14v collective kinetic kick + cell moments redeposit launch");\n    } else {\n        q6_thermostat_deposit_moments_from_cell_ids_0400<<<particleBlocks, threads>>>(\n            particles, cells, nParticles, 0, 0u);\n        check_cuda_0400(cudaGetLastError(), "0493x9x cell moments redeposit launch");\n    }\n'''
        region = replace_once(region, old, new, "final x14v kick/redeposit fusion")
        return region

    text = replace_function_region(text, "apply_kinetic_interface_reflection_0493x9x", patch_apply)

    # ------------------------------------------------------------------
    # 7) Pass already-resolved x6g host state at the unique caller.
    # ------------------------------------------------------------------
    old = '''            geometryValid0493x9x ? ws.phaseAlphaFiltered0493x6c.data() : nullptr,\n            geometryValid0493x9x);\n'''
    new = '''            geometryValid0493x9x ? ws.phaseAlphaFiltered0493x6c.data() : nullptr,\n            geometryValid0493x9x,\n            phaseGasPressure0493x6g,\n            phaseGasPressureMode0493x6g,\n            phaseGasPressureReference0493x6g,\n            phaseGasPressureConstant0493x6g,\n            phaseGasPressureScale0493x6g);\n'''
    text = replace_once(text, old, new, "x14v x6g caller state")

    validate(text)
    PATH.write_text(text)
    print(f"[0493x14v] modified {PATH}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
