#include "q6_projection_adapter.h"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <stdexcept>

#ifdef _OPENMP
#include <omp.h>
#endif

namespace mpcd {
namespace {

int thread_count() {
#ifdef _OPENMP
    return omp_get_max_threads();
#else
    return 1;
#endif
}

int thread_id() {
#ifdef _OPENMP
    return omp_get_thread_num();
#else
    return 0;
#endif
}


void resize_q6_workspace(Q6ProjectionWorkspace& ws,
                         std::uint64_t numParticles,
                         int numCells,
                         int numThreads) {
    if (numCells <= 0) {
        throw std::runtime_error("resize_q6_workspace: invalid number of cells");
    }
    if (numThreads <= 0) {
        numThreads = 1;
    }

    const bool sameSize = ws.allocatedCells == numCells &&
                          ws.allocatedParticles == numParticles &&
                          static_cast<int>(ws.localMass.size()) == numThreads * numCells;
    if (sameSize) {
        return;
    }

    ws.allocatedCells = numCells;
    ws.allocatedParticles = numParticles;
    const std::size_t np = static_cast<std::size_t>(numParticles);
    const std::size_t nc = static_cast<std::size_t>(numCells);
    const std::size_t nLocal = static_cast<std::size_t>(numThreads * numCells);

    ws.cellId.assign(np, 0);
    ws.cellMass.assign(nc, 0.0);
    ws.cellPx.assign(nc, 0.0);
    ws.cellPy.assign(nc, 0.0);
    ws.cellUx.assign(nc, 0.0);
    ws.cellUy.assign(nc, 0.0);
    ws.cellDUx.assign(nc, 0.0);
    ws.cellDUy.assign(nc, 0.0);
    ws.correctedCellUx.assign(nc, 0.0);
    ws.correctedCellUy.assign(nc, 0.0);
    ws.localMass.assign(nLocal, 0.0);
    ws.localPx.assign(nLocal, 0.0);
    ws.localPy.assign(nLocal, 0.0);
    resize_periodic_face_field(ws.baseFlux, numCells);
    resize_periodic_face_field(ws.alpha, numCells);
    resize_periodic_face_field(ws.appliedCorrectionFlux, numCells);
    resize_periodic_face_field(ws.appliedProjectedFlux, numCells);
    resize_periodic_face_field(ws.correctedCellFlux, numCells);
    ws.targetDivergence.assign(nc, 0.0);
    resize_elliptic_projection_workspace(ws.elliptic, numCells);
}

int active_domain_cell_index(double x, double y, const FluidDomainBounds& domain, const SimulationParams& params);
double active_domain_divergence_rate(const FluidDomainBounds& domain);

void deposit_cell_velocity(const ParticleState& state,
                           const SimulationParams& params,
                           const CellGrid& grid,
                           const FluidDomainBounds& domain,
                           Q6ProjectionWorkspace& ws,
                           Q6ProjectionDiagnostics& diag) {
    const std::size_t n = static_cast<std::size_t>(state.Np);
    const int nc = grid.numCells;
    const int nt = std::max(1, thread_count());

    std::fill(ws.cellMass.begin(), ws.cellMass.end(), 0.0);
    std::fill(ws.cellPx.begin(), ws.cellPx.end(), 0.0);
    std::fill(ws.cellPy.begin(), ws.cellPy.end(), 0.0);
    std::fill(ws.cellUx.begin(), ws.cellUx.end(), 0.0);
    std::fill(ws.cellUy.begin(), ws.cellUy.end(), 0.0);
    std::fill(ws.localMass.begin(), ws.localMass.end(), 0.0);
    std::fill(ws.localPx.begin(), ws.localPx.end(), 0.0);
    std::fill(ws.localPy.begin(), ws.localPy.end(), 0.0);

#pragma omp parallel
    {
        const int tid = thread_id();
        const std::size_t offset = static_cast<std::size_t>(tid * nc);

#pragma omp for
        for (std::int64_t ii = 0; ii < static_cast<std::int64_t>(n); ++ii) {
            const std::size_t i = static_cast<std::size_t>(ii);
            const int c = active_domain_cell_index(state.x[i], state.y[i], domain, params);
            ws.cellId[i] = c;
            const std::size_t k = offset + static_cast<std::size_t>(c);
            const double m = state.mass[i];
            ws.localMass[k] += m;
            ws.localPx[k] += m * state.vx[i];
            ws.localPy[k] += m * state.vy[i];
        }
    }

    std::uint64_t empty = 0u;
#pragma omp parallel for reduction(+:empty) if(nc > 256)
    for (int c = 0; c < nc; ++c) {
        double m = 0.0;
        double px = 0.0;
        double py = 0.0;
        for (int t = 0; t < nt; ++t) {
            const std::size_t k = static_cast<std::size_t>(t * nc + c);
            m += ws.localMass[k];
            px += ws.localPx[k];
            py += ws.localPy[k];
        }
        const std::size_t kk = static_cast<std::size_t>(c);
        ws.cellMass[kk] = m;
        ws.cellPx[kk] = px;
        ws.cellPy[kk] = py;
        if (m > 0.0) {
            ws.cellUx[kk] = px / m;
            ws.cellUy[kk] = py / m;
        } else {
            ++empty;
        }
    }
    diag.emptyCells = empty;
}

void build_face_velocity_from_cells(const CellGrid& grid,
                                    const std::vector<double>& ux,
                                    const std::vector<double>& uy,
                                    PeriodicFaceField& flux) {
    const int nc = grid.numCells;
    if (static_cast<int>(ux.size()) != nc || static_cast<int>(uy.size()) != nc) {
        throw std::runtime_error("build_face_velocity_from_cells: invalid cell velocity size");
    }
    resize_periodic_face_field(flux, nc);

    // First Q6 adapter convention: the cell-centered x and y velocity
    // components are interpreted as the stored east/north face values of the
    // same cell. This keeps the Q6 adapter algebraically consistent with the
    // generic face-field projection: the face correction maps directly back to
    // the particle velocity component in the owning cell. More elaborate
    // staggered/centered reconstructions can be introduced later without
    // changing the elliptic core.
#pragma omp parallel for if(nc > 4096)
    for (int c = 0; c < nc; ++c) {
        const std::size_t k = static_cast<std::size_t>(c);
        flux.x[k] = ux[k];
        flux.y[k] = uy[k];
    }
}

void fill_unit_alpha(PeriodicFaceField& alpha, int numCells) {
    resize_periodic_face_field(alpha, numCells);
    std::fill(alpha.x.begin(), alpha.x.end(), 1.0);
    std::fill(alpha.y.begin(), alpha.y.end(), 1.0);
}

const EllipticProjectionMask* prepare_immersed_projection_mask(const SimulationParams& params,
                                                               const CellGrid& grid,
                                                               const FluidDomainBounds& domain,
                                                               double time,
                                                               Q6ProjectionWorkspace& ws,
                                                               Q6ProjectionDiagnostics& diag) {
    if (!params.immersedSolidEnable || !params.projectionImmersedSolidMaskEnable) {
        return nullptr;
    }
    ws.immersedMask = build_immersed_solid_projection_mask(
        params, grid, domain, time, params.projectionImmersedSolidFluidFractionThreshold);
    ws.ellipticMask.activeCell = ws.immersedMask.activeCell;
    ws.ellipticMask.activeCells = ws.immersedMask.fluidCells;
    ws.ellipticMask.inactiveCells = ws.immersedMask.solidCells;
    diag.immersedSolidFluidCells = ws.immersedMask.fluidCells;
    diag.immersedSolidSolidCells = ws.immersedMask.solidCells;
    diag.immersedSolidClosedXFaces = ws.immersedMask.closedXFaces;
    diag.immersedSolidClosedYFaces = ws.immersedMask.closedYFaces;
    return &ws.ellipticMask;
}

void apply_immersed_face_alpha(const ImmersedSolidProjectionMask& mask,
                               PeriodicFaceField& alpha) {
    if (mask.activeCell.empty()) return;
    const std::size_t n = mask.activeCell.size();
#pragma omp parallel for if(n > 4096)
    for (std::int64_t ii = 0; ii < static_cast<std::int64_t>(n); ++ii) {
        const std::size_t k = static_cast<std::size_t>(ii);
        alpha.x[k] *= mask.faceOpen.x[k];
        alpha.y[k] *= mask.faceOpen.y[k];
    }
}

void masked_target_divergence(std::vector<double>& target,
                              double value,
                              const EllipticProjectionMask* mask) {
    const std::size_t n = target.size();
#pragma omp parallel for if(n > 4096)
    for (std::int64_t ii = 0; ii < static_cast<std::int64_t>(n); ++ii) {
        const std::size_t k = static_cast<std::size_t>(ii);
        target[k] = (!mask || mask->activeCell[k] != 0u) ? value : 0.0;
    }
}

void compute_q6_solid_leak(const PeriodicFaceField& projectedFlux,
                           const ImmersedSolidProjectionMask& mask,
                           Q6ProjectionDiagnostics& diag) {
    if (mask.activeCell.empty()) return;
    const std::size_t n = mask.activeCell.size();
    double sum2 = 0.0;
    double maxAbs = 0.0;
    std::uint64_t count = 0u;
#pragma omp parallel for reduction(+:sum2,count) reduction(max:maxAbs) if(n > 4096)
    for (std::int64_t ii = 0; ii < static_cast<std::int64_t>(n); ++ii) {
        const std::size_t k = static_cast<std::size_t>(ii);
        if (mask.faceOpen.x[k] == 0.0) {
            const double a = std::abs(projectedFlux.x[k]);
            sum2 += a * a;
            maxAbs = std::max(maxAbs, a);
            count += 1u;
        }
        if (mask.faceOpen.y[k] == 0.0) {
            const double a = std::abs(projectedFlux.y[k]);
            sum2 += a * a;
            maxAbs = std::max(maxAbs, a);
            count += 1u;
        }
    }
    diag.immersedSolidLeakProjectedFluxRms = count > 0u ? std::sqrt(sum2 / static_cast<double>(count)) : 0.0;
    diag.immersedSolidLeakProjectedFluxMaxAbs = maxAbs;
}

EllipticProjectionBC q6_bc_from_particle_boundaries(const SimulationParams& params) {
    EllipticProjectionBC bc{};
    bc.x = is_x_periodic(params) ? EllipticBoundaryType::Periodic
                                 : EllipticBoundaryType::WallNoNormalFlux;
    bc.y = is_y_periodic(params) ? EllipticBoundaryType::Periodic
                                 : EllipticBoundaryType::WallNoNormalFlux;
    return bc;
}


int active_domain_cell_index(double x,
                             double y,
                             const FluidDomainBounds& domain,
                             const SimulationParams& params) {
    const double width = fluid_domain_width(domain);
    const double height = fluid_domain_height(domain);
    double xr = x - domain.xMin;
    double yr = y - domain.yMin;
    if (is_x_periodic(params)) {
        xr = std::fmod(xr, width);
        if (xr < 0.0) xr += width;
    } else {
        xr = std::clamp(xr, 0.0, width);
    }
    if (is_y_periodic(params)) {
        yr = std::fmod(yr, height);
        if (yr < 0.0) yr += height;
    } else {
        yr = std::clamp(yr, 0.0, height);
    }
    int ix = static_cast<int>(std::floor(xr / (width / static_cast<double>(params.Nx))));
    int iy = static_cast<int>(std::floor(yr / (height / static_cast<double>(params.Ny))));
    ix = std::clamp(ix, 0, params.Nx - 1);
    iy = std::clamp(iy, 0, params.Ny - 1);
    return ix + params.Nx * iy;
}

double active_domain_divergence_rate(const FluidDomainBounds& domain) {
    const double width = fluid_domain_width(domain);
    const double height = fluid_domain_height(domain);
    double rate = 0.0;
    if (width > 0.0) {
        rate += (domain.vxMax - domain.vxMin) / width;
    }
    if (height > 0.0) {
        rate += (domain.vyMax - domain.vyMin) / height;
    }
    return rate;
}

void add_moving_wall_fluxes_to_q6_bc(EllipticProjectionBC& bc,
                                     const SimulationParams& params,
                                     const FluidDomainBounds& domain) {
    if (!is_x_periodic(params)) {
        bc.xLowFlux = domain.vxMin;
        bc.xHighFlux = domain.vxMax;
    }
    if (!is_y_periodic(params)) {
        bc.yLowFlux = domain.vyMin;
        bc.yHighFlux = domain.vyMax;
    }
}

double face_strength_for_q6(double requestedStrength,
                            const ImmersedSolidProjectionMask* immersedMask,
                            bool xFace,
                            std::size_t k) {
    if (immersedMask != nullptr && !immersedMask->faceOpen.x.empty()) {
        const double open = xFace ? immersedMask->faceOpen.x[k] : immersedMask->faceOpen.y[k];
        // A sub-relaxed Q6 projection is useful for tuning the interior
        // incompressibility/structure compromise, but an immersed solid wall
        // must remain impermeable.  Closed immersed-solid faces therefore keep
        // the full raw correction, which is -baseFlux on such faces in the
        // elliptic core.  Open fluid-fluid faces use the requested strength.
        if (open == 0.0) {
            return 1.0;
        }
    }
    return requestedStrength;
}

void build_scaled_q6_fluxes(const PeriodicFaceField& baseFlux,
                            const PeriodicFaceField& rawCorrectionFlux,
                            double strength,
                            const ImmersedSolidProjectionMask* immersedMask,
                            PeriodicFaceField& appliedCorrectionFlux,
                            PeriodicFaceField& appliedProjectedFlux) {
    const std::size_t n = baseFlux.x.size();
    if (baseFlux.y.size() != n || rawCorrectionFlux.x.size() != n || rawCorrectionFlux.y.size() != n) {
        throw std::runtime_error("build_scaled_q6_fluxes: inconsistent face-field sizes");
    }
    resize_periodic_face_field(appliedCorrectionFlux, static_cast<int>(n));
    resize_periodic_face_field(appliedProjectedFlux, static_cast<int>(n));
#pragma omp parallel for if(n > 4096)
    for (std::int64_t ii = 0; ii < static_cast<std::int64_t>(n); ++ii) {
        const std::size_t k = static_cast<std::size_t>(ii);
        const double sx = face_strength_for_q6(strength, immersedMask, true, k);
        const double sy = face_strength_for_q6(strength, immersedMask, false, k);
        appliedCorrectionFlux.x[k] = sx * rawCorrectionFlux.x[k];
        appliedCorrectionFlux.y[k] = sy * rawCorrectionFlux.y[k];
        appliedProjectedFlux.x[k] = baseFlux.x[k] + appliedCorrectionFlux.x[k];
        appliedProjectedFlux.y[k] = baseFlux.y[k] + appliedCorrectionFlux.y[k];
    }
}

void face_correction_to_cell_velocity(const CellGrid& grid,
                                      const PeriodicFaceField& correctionFlux,
                                      std::vector<double>& dux,
                                      std::vector<double>& duy,
                                      Q6ProjectionDiagnostics& diag) {
    const int nc = grid.numCells;
    dux.assign(static_cast<std::size_t>(nc), 0.0);
    duy.assign(static_cast<std::size_t>(nc), 0.0);

    double sum2 = 0.0;
    double maxAbs = 0.0;
#pragma omp parallel for reduction(+:sum2) reduction(max:maxAbs) if(nc > 4096)
    for (int c = 0; c < nc; ++c) {
        const std::size_t k = static_cast<std::size_t>(c);
        dux[k] = correctionFlux.x[k];
        duy[k] = correctionFlux.y[k];
        sum2 += dux[k] * dux[k] + duy[k] * duy[k];
        maxAbs = std::max(maxAbs, std::sqrt(dux[k] * dux[k] + duy[k] * duy[k]));
    }
    diag.correctionVelocityRms = nc > 0 ? std::sqrt(sum2 / static_cast<double>(nc)) : 0.0;
    diag.correctionVelocityMaxAbs = maxAbs;
}

void apply_cell_velocity_correction(ParticleState& state,
                                    const Q6ProjectionWorkspace& ws,
                                    Q6ProjectionDiagnostics& diag,
                                    bool momentumCorrectionEnable) {
    const std::size_t n = static_cast<std::size_t>(state.Np);
    double mass = 0.0;
    double dpx = 0.0;
    double dpy = 0.0;

#pragma omp parallel for reduction(+:mass,dpx,dpy) if(n > 10000)
    for (std::int64_t ii = 0; ii < static_cast<std::int64_t>(n); ++ii) {
        const std::size_t i = static_cast<std::size_t>(ii);
        const int c = ws.cellId[i];
        const std::size_t k = static_cast<std::size_t>(c);
        const double m = state.mass[i];
        mass += m;
        dpx += m * ws.cellDUx[k];
        dpy += m * ws.cellDUy[k];
        state.vx[i] += ws.cellDUx[k];
        state.vy[i] += ws.cellDUy[k];
    }

    diag.momentumResidualBeforeCorrection = std::sqrt(dpx * dpx + dpy * dpy);
    if (momentumCorrectionEnable && mass > 0.0) {
        const double cvx = dpx / mass;
        const double cvy = dpy / mass;
        diag.momentumCorrectionVx = cvx;
        diag.momentumCorrectionVy = cvy;
#pragma omp parallel for if(n > 10000)
        for (std::int64_t ii = 0; ii < static_cast<std::int64_t>(n); ++ii) {
            const std::size_t i = static_cast<std::size_t>(ii);
            state.vx[i] -= cvx;
            state.vy[i] -= cvy;
        }
    }
}

} // namespace

bool q6_projection_requested(const SimulationParams& params) {
    return params.projectionEnable || params.method == "q6";
}

Q6ProjectionDiagnostics apply_q6_periodic_projection(ParticleState& state,
                                                     const SimulationParams& params,
                                                     const CellGrid& grid,
                                                     const FluidDomainBounds& domain,
                                                     Q6ProjectionWorkspace& workspace) {
    validate_particle_state(state, "apply_q6_periodic_projection");

    Q6ProjectionDiagnostics diag{};
    if (!q6_projection_requested(params)) {
        return diag;
    }

    const int nc = grid.numCells;
    const int nt = std::max(1, thread_count());
    resize_q6_workspace(workspace, state.Np, nc, nt);

    deposit_cell_velocity(state, params, grid, domain, workspace, diag);
    build_face_velocity_from_cells(grid, workspace.cellUx, workspace.cellUy, workspace.baseFlux);
    fill_unit_alpha(workspace.alpha, nc);
    const EllipticProjectionMask* mask = prepare_immersed_projection_mask(
        params, grid, domain, static_cast<double>(0.0), workspace, diag);
    if (mask != nullptr) {
        apply_immersed_face_alpha(workspace.immersedMask, workspace.alpha);
    }
    masked_target_divergence(workspace.targetDivergence, active_domain_divergence_rate(domain), mask);

    const EllipticProjectionGrid egrid = make_elliptic_projection_grid(
        params.Nx, params.Ny, fluid_domain_width(domain), fluid_domain_height(domain));
    EllipticProjectionParams eparams{};
    eparams.maxIterations = params.projectionMaxIterations;
    eparams.tolerance = params.projectionTolerance;
    eparams.removeRhsMean = true;
    eparams.removePhiMean = true;

    EllipticProjectionBC bc = q6_bc_from_particle_boundaries(params);
    add_moving_wall_fluxes_to_q6_bc(bc, params, domain);
    EllipticProjectionResult result = project_face_field(
        egrid, workspace.baseFlux, workspace.alpha, workspace.targetDivergence, eparams, bc, workspace.elliptic, mask);

    diag.applied = true;
    diag.projectionStrength = params.q6ProjectionStrength;
    diag.converged = result.diagnostics.converged;
    diag.iterations = result.diagnostics.iterations;
    diag.residualRel = result.diagnostics.residualRel;
    diag.divBeforeRms = result.diagnostics.divBeforeRms;
    diag.divBeforeMaxAbs = result.diagnostics.divBeforeMaxAbs;

    build_scaled_q6_fluxes(workspace.baseFlux,
                           result.correctionFlux,
                           params.q6ProjectionStrength,
                           mask != nullptr ? &workspace.immersedMask : nullptr,
                           workspace.appliedCorrectionFlux,
                           workspace.appliedProjectedFlux);

    std::vector<double> divProjectedAfter = compute_face_divergence(egrid, workspace.appliedProjectedFlux, bc, mask);
    double projectedDiv2 = 0.0;
    double projectedDivMax = 0.0;
    std::uint64_t projectedDivCount = 0u;
#pragma omp parallel for reduction(+:projectedDiv2,projectedDivCount) reduction(max:projectedDivMax) if(nc > 4096)
    for (int c = 0; c < nc; ++c) {
        const std::size_t k = static_cast<std::size_t>(c);
        if (mask != nullptr && mask->activeCell[k] == 0u) continue;
        const double d = divProjectedAfter[k];
        projectedDiv2 += d * d;
        projectedDivMax = std::max(projectedDivMax, std::abs(d));
        projectedDivCount += 1u;
    }
    diag.divAfterProjectedFluxRms = projectedDivCount > 0u ? std::sqrt(projectedDiv2 / static_cast<double>(projectedDivCount)) : 0.0;
    diag.divAfterProjectedFluxMaxAbs = projectedDivMax;

    if (mask != nullptr) {
        compute_q6_solid_leak(workspace.appliedProjectedFlux, workspace.immersedMask, diag);
    }
    face_correction_to_cell_velocity(grid, workspace.appliedCorrectionFlux, workspace.cellDUx, workspace.cellDUy, diag);

#pragma omp parallel for if(nc > 4096)
    for (int c = 0; c < nc; ++c) {
        const std::size_t k = static_cast<std::size_t>(c);
        workspace.correctedCellUx[k] = workspace.cellUx[k] + workspace.cellDUx[k];
        workspace.correctedCellUy[k] = workspace.cellUy[k] + workspace.cellDUy[k];
    }
    build_face_velocity_from_cells(grid, workspace.correctedCellUx, workspace.correctedCellUy, workspace.correctedCellFlux);
    std::vector<double> divCellAfter = compute_face_divergence(egrid, workspace.correctedCellFlux, bc, mask);
    double div2 = 0.0;
    double divMax = 0.0;
    std::uint64_t divCount = 0u;
#pragma omp parallel for reduction(+:div2,divCount) reduction(max:divMax) if(nc > 4096)
    for (int c = 0; c < nc; ++c) {
        if (mask != nullptr && mask->activeCell[static_cast<std::size_t>(c)] == 0u) continue;
        const double d = divCellAfter[static_cast<std::size_t>(c)];
        div2 += d * d;
        divMax = std::max(divMax, std::abs(d));
        divCount += 1u;
    }
    diag.divAfterCellVelocityRms = divCount > 0u ? std::sqrt(div2 / static_cast<double>(divCount)) : 0.0;
    diag.divAfterCellVelocityMaxAbs = divMax;

    apply_cell_velocity_correction(state, workspace, diag, params.projectionMomentumCorrectionEnable);
    return diag;
}

} // namespace mpcd
