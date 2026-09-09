#!/usr/bin/env python3
"""
0493x8r — make openBoundaryOutletMode=neumann a genuine passive pressure outlet
for the resident species/Q6-G-F projection.

Problem isolated by the 0493x8q micro-trace:
  x8l used the current boundary-cell velocity as a *prescribed outlet target*.
  q6_compute_masked_face_correction then produced target-before == 0 on the
  outlet face.  The opposite interior-face correction still changed the
  boundary-cell velocity, and the next step reused that already changed value
  as the new target.  This created the observed outlet-velocity ratchet.

x8r keeps the useful x8l velocity extrapolation only as the BASE outlet face:
  u*_out = u*_boundary-cell      (zero normal velocity gradient)

but changes the pressure/projection boundary condition on the open outlet to:
  phi_out = 0                    (pressure-correction reference)

at the physical face, one half cell from the boundary-cell centre.  Therefore:
  A_out contribution = 2 * phi_c / dx^2
  dU_out             = 2 * phi_c / dx

The inlet remains velocity/flux prescribed.  The particle-level Neumann kinetic
bath introduced by x8q-fix4 is untouched.

The patch covers BOTH Q6-G-F CG implementations:
  - host-driven masked CG fallback;
  - 0493x7j cooperative resident CG.

No new user parameter or outlet mode is introduced.  The existing
openBoundaryOutletMode=neumann acquires the corrected semantics.

This script intentionally has no clean-tree guard.
"""

from pathlib import Path

ROOT = Path.cwd()
CU = ROOT / "src/cuda_q6_resident_0400.cu"
SIM = ROOT / "include/simulation_params.h"
TAG = "0493x8r"
MARKER = "0493x8r passive pressure outlet"

for p in (CU, SIM):
    if not p.is_file():
        raise SystemExit(f"[{TAG}] missing {p}")


def replace_once(text: str, old: str, new: str, label: str) -> str:
    n = text.count(old)
    if n != 1:
        raise SystemExit(f"[{TAG}] {label}: expected one anchor, found {n}")
    return text.replace(old, new, 1)


cu = CU.read_text(encoding="utf-8")
if MARKER in cu:
    raise SystemExit(f"[{TAG}] already applied")

# ---------------------------------------------------------------------------
# 1) Geometry helpers: host nullspace selection + device cell/aperture test.
# ---------------------------------------------------------------------------
host_anchor = """double q6_segmented_flux_integral_0409(const Q6SegmentedIo0409& cfg, int face, double length) {
"""
host_helper = '''bool q6_has_passive_pressure_outlet_right_0493x8r(
    const Q6SegmentedIo0409& cfg) {
    if (!cfg.enabled || !cfg.passiveNeumannRightOutlet0493x8l) return false;
    for (int k = 0; k < cfg.count; ++k) {
        if (cfg.face[k] == 1 && cfg.mode[k] == 2 &&
            cfg.sMax[k] > cfg.sMin[k]) {
            return true;
        }
    }
    return false;
}

'''
if host_anchor not in cu:
    raise SystemExit(f"[{TAG}] host helper insertion anchor not found")
cu = cu.replace(host_anchor, host_helper + host_anchor, 1)

device_anchor = """__device__ double q6_species_boundary_flux_for_cell_0493w7(
"""
device_helper = '''__device__ bool q6_passive_pressure_outlet_right_cell_0493x8r(
    const Q6SegmentedIo0409& cfg,
    int ix,
    int iy,
    int nx,
    int ny) {
    if (!cfg.enabled || !cfg.passiveNeumannRightOutlet0493x8l ||
        ix != nx - 1 || ny <= 0) {
        return false;
    }
    const double tangent =
        (static_cast<double>(iy) + 0.5) / static_cast<double>(ny);
    for (int k = 0; k < cfg.count; ++k) {
        if (cfg.face[k] == 1 && cfg.mode[k] == 2 &&
            tangent >= cfg.sMin[k] && tangent <= cfg.sMax[k]) {
            return true;
        }
    }
    return false;
}

'''
if device_anchor not in cu:
    raise SystemExit(f"[{TAG}] device helper insertion anchor not found")
cu = cu.replace(device_anchor, device_helper + device_anchor, 1)

old_comment = """        // 0493x8l: Zovatto-style passive right outlet.
        // Discrete zero-normal-gradient: copy the current boundary-cell ux
        // to the boundary face. The Q6-G-F boundary correction is therefore
        // target-before = 0 instead of imposing segmentUx.
"""
new_comment = """        // 0493x8l + 0493x8r passive right outlet.
        // Extrapolate the current boundary-cell ux to the BASE outlet face:
        // u*_out = u*_cell, i.e. zero normal gradient of the predictor
        // velocity.  x8r no longer treats this value as a prescribed final
        // flux: the pressure solve uses phi=0 at the outlet face and is free
        // to add the normal pressure correction required by continuity.
"""
cu = replace_once(cu, old_comment, new_comment, "x8l comment")

# ---------------------------------------------------------------------------
# 2) Host-driven masked operator: phi=0 at dx/2 on passive right outlet.
# ---------------------------------------------------------------------------
old_sig = """    const double* preparedFaceCoeffY,
    int usePreparedPhaseStencil,
    double inactiveNeighborFactor) {
"""
new_sig = """    const double* preparedFaceCoeffY,
    int usePreparedPhaseStencil,
    double inactiveNeighborFactor,
    Q6SegmentedIo0409 segmentedIo) {
"""
cu = replace_once(cu, old_sig, new_sig, "masked operator signature")

old_east = """        if (periodicX || ix < nx - 1) {
            const int east = iy * nx +
                (periodicX ? wrap_cell_index_0400(ix + 1, nx) : ix + 1);
            const double factor = usePreparedPhaseStencil
                ? preparedFaceCoeffX[c]
                : q6_masked_face_factor_0493x6d(
                    mask, phaseAlpha, c, east, inactiveNeighborFactor,
                    useCutFaceGeometry, cutFaceThetaMinGuard);
            a += factor * invDx2 *
                 (p[c] - (mask[east] ? p[east] : 0.0));
        }
"""
new_east = """        if (periodicX || ix < nx - 1) {
            const int east = iy * nx +
                (periodicX ? wrap_cell_index_0400(ix + 1, nx) : ix + 1);
            const double factor = usePreparedPhaseStencil
                ? preparedFaceCoeffX[c]
                : q6_masked_face_factor_0493x6d(
                    mask, phaseAlpha, c, east, inactiveNeighborFactor,
                    useCutFaceGeometry, cutFaceThetaMinGuard);
            a += factor * invDx2 *
                 (p[c] - (mask[east] ? p[east] : 0.0));
        } else if (q6_passive_pressure_outlet_right_cell_0493x8r(
                       segmentedIo, ix, iy, nx, ny)) {
            // 0493x8r passive pressure outlet: phi=0 at the physical face,
            // whose distance from this cell centre is dx/2.
            a += 2.0 * invDx2 * p[c];
        }
"""
cu = replace_once(cu, old_east, new_east, "masked operator right outlet")

# ---------------------------------------------------------------------------
# 3) Outlet face correction from pressure gradient instead of target-before.
# ---------------------------------------------------------------------------
old_face = """        } else if (mask[c]) {
            const double target = q6_species_boundary_flux_for_cell_0493w7(
                segmentedIo, 1, ix, iy, nx, ny, xHighFlux, species, speciesIndex,
                speciesType, c, exclusiveProjectedSpecies);
            const double before = q6_species_cell_velocity_component_0493w5(
                species, speciesIndex, c, 0);
            faceDUx[c] = strength * (target - before);
        } else {
"""
new_face = """        } else if (mask[c]) {
            if (q6_passive_pressure_outlet_right_cell_0493x8r(
                    segmentedIo, ix, iy, nx, ny)) {
                // 0493x8r: correction = -grad(phi), phi_out=0 and
                // distance(cell centre, outlet face)=dx/2.
                faceDUx[c] = strength * (2.0 * phi[c] / dx);
            } else {
                const double target = q6_species_boundary_flux_for_cell_0493w7(
                    segmentedIo, 1, ix, iy, nx, ny, xHighFlux, species, speciesIndex,
                    speciesType, c, exclusiveProjectedSpecies);
                const double before = q6_species_cell_velocity_component_0493w5(
                    species, speciesIndex, c, 0);
                faceDUx[c] = strength * (target - before);
            }
        } else {
"""
cu = replace_once(cu, old_face, new_face, "masked face correction right outlet")

# ---------------------------------------------------------------------------
# 4) Resident x7j operators: identical pressure-outlet algebra.
# ---------------------------------------------------------------------------
old_full_sig = """    double invDx2,
    double invDy2,
    int periodicX,
    int periodicY) {
"""
new_full_sig = """    double invDx2,
    double invDy2,
    int periodicX,
    int periodicY,
    Q6SegmentedIo0409 segmentedIo) {
"""
full_start = cu.find("__device__ __forceinline__ double q6_full_operator_cell_0493x7j(")
prep_start = cu.find("__device__ __forceinline__ double q6_prepared_masked_operator_cell_0493x7j(")
if full_start < 0 or prep_start < 0 or prep_start <= full_start:
    raise SystemExit(f"[{TAG}] resident full/prepared operator regions not found")
full_region = cu[full_start:prep_start]
full_region = replace_once(full_region, old_full_sig, new_full_sig,
                           "resident full operator signature")
old_full_east = """    if (periodicX || ix < nx - 1) {
        const int east = iy * nx + (periodicX ? wrap_cell_index_0400(ix + 1, nx) : ix + 1);
        value += (center - p[east]) * invDx2;
    }
"""
new_full_east = """    if (periodicX || ix < nx - 1) {
        const int east = iy * nx + (periodicX ? wrap_cell_index_0400(ix + 1, nx) : ix + 1);
        value += (center - p[east]) * invDx2;
    } else if (q6_passive_pressure_outlet_right_cell_0493x8r(
                   segmentedIo, ix, iy, nx, ny)) {
        value += 2.0 * center * invDx2;
    }
"""
full_region = replace_once(full_region, old_full_east, new_full_east,
                           "resident full operator right outlet")
cu = cu[:full_start] + full_region + cu[prep_start:]

prep_start = cu.find("__device__ __forceinline__ double q6_prepared_masked_operator_cell_0493x7j(")
cg_start = cu.find("__global__ void q6_cg_g_f_resident_0493x7j(", prep_start)
if prep_start < 0 or cg_start < 0:
    raise SystemExit(f"[{TAG}] prepared resident operator region not found")
prep_region = cu[prep_start:cg_start]
prep_region = replace_once(prep_region, old_full_sig, new_full_sig,
                           "resident prepared operator signature")
old_prep_east = """    if (periodicX || ix < nx - 1) {
        const int east = iy * nx + (periodicX ? wrap_cell_index_0400(ix + 1, nx) : ix + 1);
        value += faceCoeffX[c] * invDx2 * (center - (mask[east] ? p[east] : 0.0));
    }
"""
new_prep_east = """    if (periodicX || ix < nx - 1) {
        const int east = iy * nx + (periodicX ? wrap_cell_index_0400(ix + 1, nx) : ix + 1);
        value += faceCoeffX[c] * invDx2 * (center - (mask[east] ? p[east] : 0.0));
    } else if (q6_passive_pressure_outlet_right_cell_0493x8r(
                   segmentedIo, ix, iy, nx, ny)) {
        value += 2.0 * center * invDx2;
    }
"""
prep_region = replace_once(prep_region, old_prep_east, new_prep_east,
                           "resident prepared operator right outlet")
cu = cu[:prep_start] + prep_region + cu[cg_start:]

old_cg_tail = """    double invDy2,
    int periodicX,
    int periodicY,
    int fullDomain) {
"""
new_cg_tail = """    double invDy2,
    int periodicX,
    int periodicY,
    Q6SegmentedIo0409 segmentedIo,
    int pressureOutletDirichlet0493x8r,
    int fullDomain) {
"""
cu = replace_once(cu, old_cg_tail, new_cg_tail, "resident CG signature")

old_rhsmean = """    const double rhsMean = fullDomain
        ? state->rhsSum / static_cast<double>(n)
        : 0.0;
"""
new_rhsmean = """    const bool removeConstantNullspace0493x8r =
        fullDomain && !pressureOutletDirichlet0493x8r;
    const double rhsMean = removeConstantNullspace0493x8r
        ? state->rhsSum / static_cast<double>(n)
        : 0.0;
"""
cu = replace_once(cu, old_rhsmean, new_rhsmean, "resident nullspace rhs mean")

cu = replace_once(
    cu,
    """        const double v = rhs[c] - (fullDomain ? rhsMean : 0.0);
""",
    """        const double v =
            rhs[c] - (removeConstantNullspace0493x8r ? rhsMean : 0.0);
""",
    "resident nullspace init",
)

old_res_calls = """            const double value = fullDomain
                ? q6_full_operator_cell_0493x7j(
                      p, c, nx, ny, invDx2, invDy2, periodicX, periodicY)
                : q6_prepared_masked_operator_cell_0493x7j(
                      p, mask, faceCoeffX, faceCoeffY, c, nx, ny,
                      invDx2, invDy2, periodicX, periodicY);
"""
new_res_calls = """            const double value = fullDomain
                ? q6_full_operator_cell_0493x7j(
                      p, c, nx, ny, invDx2, invDy2, periodicX, periodicY,
                      segmentedIo)
                : q6_prepared_masked_operator_cell_0493x7j(
                      p, mask, faceCoeffX, faceCoeffY, c, nx, ny,
                      invDx2, invDy2, periodicX, periodicY, segmentedIo);
"""
cu = replace_once(cu, old_res_calls, new_res_calls, "resident operator calls")

cu = replace_once(
    cu,
    """        if (fullDomain && ((it + 1) % 25) == 0) {
""",
    """        if (removeConstantNullspace0493x8r && ((it + 1) % 25) == 0) {
""",
    "resident periodic mean removal",
)

old_launch_sig = """    double invDy2,
    int periodicX,
    int periodicY,
    bool fullDomain,
    double& divBeforeSqOut0493x7j,
"""
new_launch_sig = """    double invDy2,
    int periodicX,
    int periodicY,
    Q6SegmentedIo0409 segmentedIo,
    bool pressureOutletDirichlet0493x8r,
    bool fullDomain,
    double& divBeforeSqOut0493x7j,
"""
cu = replace_once(cu, old_launch_sig, new_launch_sig,
                  "resident launch wrapper signature")

cu = replace_once(
    cu,
    """    int full = fullDomain ? 1 : 0;

    void* args[] = {
""",
    """    int pressureOutlet = pressureOutletDirichlet0493x8r ? 1 : 0;
    int full = fullDomain ? 1 : 0;

    void* args[] = {
""",
    "resident launch locals",
)

cu = replace_once(
    cu,
    """        &nx, &ny, &numCells, &maxIterations, &tolerance,
        &invDx2, &invDy2, &periodicX, &periodicY, &full
""",
    """        &nx, &ny, &numCells, &maxIterations, &tolerance,
        &invDx2, &invDy2, &periodicX, &periodicY,
        &segmentedIo, &pressureOutlet, &full
""",
    "resident cooperative args",
)

# ---------------------------------------------------------------------------
# 5) Solve driver: phi=0 outlet removes the full-domain constant nullspace.
# ---------------------------------------------------------------------------
cu = replace_once(
    cu,
    """    bool periodicProjectedMomentumCorrection0493x7dv2fix2 = false;

    for (int s = 0; s < speciesCount; ++s) {
""",
    f"""    bool periodicProjectedMomentumCorrection0493x7dv2fix2 = false;
    // {MARKER}
    // A phi=0 outlet face removes the constant pressure-correction nullspace
    // even when every pressure cell is active.
    const bool pressureOutletDirichlet0493x8r =
        q6_has_passive_pressure_outlet_right_0493x8r(segmentedIo);

    for (int s = 0; s < speciesCount; ++s) {{
""",
    "pressure outlet solve flag",
)

cu = replace_once(
    cu,
    """                params.projectionMaxIterations, tol, invDx2, invDy2,
                periodicX, periodicY, audit.fullDomain, divBeforeSq, audit);
""",
    """                params.projectionMaxIterations, tol, invDx2, invDy2,
                periodicX, periodicY, segmentedIo,
                pressureOutletDirichlet0493x8r,
                audit.fullDomain, divBeforeSq, audit);
""",
    "resident launch call",
)

old_host_mean = """            const double rhsMean = audit.fullDomain
                ? rhsSum / static_cast<double>(grid.numCells)
                : 0.0;
            q6_init_masked_cg_0493w5<<<cellBlocks, threads>>>(
                ws.rhs.data(), ws.phi.data(), ws.r.data(), ws.p.data(),
                q6SolveMask0493x6f, rhsMean, audit.fullDomain ? 1 : 0,
                grid.numCells);
"""
new_host_mean = """            const bool removeConstantNullspace0493x8r =
                audit.fullDomain && !pressureOutletDirichlet0493x8r;
            const double rhsMean = removeConstantNullspace0493x8r
                ? rhsSum / static_cast<double>(grid.numCells)
                : 0.0;
            q6_init_masked_cg_0493w5<<<cellBlocks, threads>>>(
                ws.rhs.data(), ws.phi.data(), ws.r.data(), ws.p.data(),
                q6SolveMask0493x6f, rhsMean,
                removeConstantNullspace0493x8r ? 1 : 0,
                grid.numCells);
"""
cu = replace_once(cu, old_host_mean, new_host_mean, "host nullspace handling")

cu = replace_once(
    cu,
    """                    phaseInterfaceStencilSpecies0493x6f ? 1 : 0,
                    inactiveNeighborFactor0493x5a);
""",
    """                    phaseInterfaceStencilSpecies0493x6f ? 1 : 0,
                    inactiveNeighborFactor0493x5a, segmentedIo);
""",
    "host operator launch",
)

cu = replace_once(
    cu,
    """                if (audit.fullDomain && (it + 1) % 25 == 0) {
""",
    """                if (removeConstantNullspace0493x8r && (it + 1) % 25 == 0) {
""",
    "host periodic mean removal",
)

CU.write_text(cu, encoding="utf-8")

# ---------------------------------------------------------------------------
# 6) Public semantics documentation.  No parser/parameter change.
# ---------------------------------------------------------------------------
sim = SIM.read_text(encoding="utf-8")
old_sim = """    //   neumann       : outlet correction has zero normal gradient in practice:
    //                   the outlet boundary flux used by Q6 is the current
    //                   local base face flux, while the inlet remains prescribed.
    //                   Segmented aperture complements stay impermeable.
"""
new_sim = """    //   neumann       : passive pressure outlet.  Q6-G-F extrapolates the
    //                   current boundary-cell normal velocity to the base
    //                   outlet face (zero normal gradient of predictor velocity),
    //                   while the projection uses phi=0 at that open face and
    //                   is therefore free to adjust the final outlet flux.
    //                   The inlet remains prescribed; segmented aperture
    //                   complements remain impermeable.
"""
sim = replace_once(sim, old_sim, new_sim,
                   "simulation_params Neumann documentation")
SIM.write_text(sim, encoding="utf-8")

print(f"[{TAG}] patched {CU}")
print(f"[{TAG}] patched {SIM}")
print(f"[{TAG}] semantics: velocity extrapolation + phi=0 passive pressure outlet")
print(f"[{TAG}] covered CG paths: host fallback + x7j cooperative resident")
print(f"[{TAG}] x8q-fix4 particle bath unchanged")
