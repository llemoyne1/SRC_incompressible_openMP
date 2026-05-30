#include "q6_projection_adapter.h"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <stdexcept>
#include <string>
#include <numeric>
#include <vector>

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
    std::fill(ws.cellId.begin(), ws.cellId.end(), -1);
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
            if (!is_fluid_particle(state, i)) {
                continue;
            }
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
    diag.immersedSolidCutCells = ws.immersedMask.cutCells;
    diag.immersedSolidActiveCutCells = ws.immersedMask.activeCutCells;
    diag.immersedSolidActiveAdjacentCells = ws.immersedMask.activeSolidAdjacentCells;
    diag.immersedSolidClosedXFaces = ws.immersedMask.closedXFaces;
    diag.immersedSolidClosedYFaces = ws.immersedMask.closedYFaces;
    diag.immersedSolidCellClosedXFaces = ws.immersedMask.cellClosedXFaces;
    diag.immersedSolidCellClosedYFaces = ws.immersedMask.cellClosedYFaces;
    diag.immersedSolidCutClosedXFaces = ws.immersedMask.cutClosedXFaces;
    diag.immersedSolidCutClosedYFaces = ws.immersedMask.cutClosedYFaces;
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

struct Q6SolidLeakStats {
    std::uint64_t faceCount = 0u;
    double sum2 = 0.0;
    double maxAbs = 0.0;
    std::uint64_t cellFaceCount = 0u;
    double cellSum2 = 0.0;
    double cellMaxAbs = 0.0;
    std::uint64_t cutFaceCount = 0u;
    double cutSum2 = 0.0;
    double cutMaxAbs = 0.0;
};

inline int q6_cell_index(int i, int j, int Nx) {
    return i + Nx * j;
}

inline bool q6_face_is_immersed_boundary(const ImmersedSolidProjectionMask& mask,
                                         int owner,
                                         int neighbour,
                                         bool xFace) {
    const std::size_t k = static_cast<std::size_t>(owner);
    const bool cutClosed = xFace ? (!mask.faceClosedByCutX.empty() && mask.faceClosedByCutX[k] != 0u)
                                 : (!mask.faceClosedByCutY.empty() && mask.faceClosedByCutY[k] != 0u);
    if (cutClosed) {
        return true;
    }
    const bool cellClosed = xFace ? (!mask.faceClosedByCellX.empty() && mask.faceClosedByCellX[k] != 0u)
                                  : (!mask.faceClosedByCellY.empty() && mask.faceClosedByCellY[k] != 0u);
    if (!cellClosed) {
        return false;
    }
    const bool a = mask.activeCell[static_cast<std::size_t>(owner)] != 0u;
    const bool b = mask.activeCell[static_cast<std::size_t>(neighbour)] != 0u;
    return a != b;
}

Q6SolidLeakStats measure_q6_solid_boundary_leak(const PeriodicFaceField& projectedFlux,
                                                const ImmersedSolidProjectionMask& mask,
                                                const SimulationParams& params) {
    Q6SolidLeakStats stats{};
    if (mask.activeCell.empty()) return stats;
    const int Nx = std::max(1, params.Nx);
    const int Ny = std::max(1, params.Ny);
    const bool periodicX = is_x_periodic(params);
    const bool periodicY = is_y_periodic(params);

    double sum2 = 0.0;
    double maxAbs = 0.0;
    double cellSum2 = 0.0;
    double cellMaxAbs = 0.0;
    double cutSum2 = 0.0;
    double cutMaxAbs = 0.0;
    std::uint64_t count = 0u;
    std::uint64_t cellCount = 0u;
    std::uint64_t cutCount = 0u;
#pragma omp parallel for reduction(+:sum2,count,cellSum2,cellCount,cutSum2,cutCount) reduction(max:maxAbs,cellMaxAbs,cutMaxAbs) if(Nx * Ny > 4096)
    for (int j = 0; j < Ny; ++j) {
        for (int i = 0; i < Nx; ++i) {
            const int c = q6_cell_index(i, j, Nx);
            const std::size_t k = static_cast<std::size_t>(c);

            if (periodicX || i < Nx - 1) {
                const int ip = periodicX ? ((i + 1) % Nx) : (i + 1);
                const int e = q6_cell_index(ip, j, Nx);
                if (q6_face_is_immersed_boundary(mask, c, e, true)) {
                    const bool cutClosed = !mask.faceClosedByCutX.empty() && mask.faceClosedByCutX[k] != 0u;
                    const double a = std::abs(projectedFlux.x[k]);
                    sum2 += a * a;
                    maxAbs = std::max(maxAbs, a);
                    count += 1u;
                    if (cutClosed) {
                        cutSum2 += a * a;
                        cutMaxAbs = std::max(cutMaxAbs, a);
                        cutCount += 1u;
                    } else {
                        cellSum2 += a * a;
                        cellMaxAbs = std::max(cellMaxAbs, a);
                        cellCount += 1u;
                    }
                }
            }

            if (periodicY || j < Ny - 1) {
                const int jp = periodicY ? ((j + 1) % Ny) : (j + 1);
                const int n = q6_cell_index(i, jp, Nx);
                if (q6_face_is_immersed_boundary(mask, c, n, false)) {
                    const bool cutClosed = !mask.faceClosedByCutY.empty() && mask.faceClosedByCutY[k] != 0u;
                    const double a = std::abs(projectedFlux.y[k]);
                    sum2 += a * a;
                    maxAbs = std::max(maxAbs, a);
                    count += 1u;
                    if (cutClosed) {
                        cutSum2 += a * a;
                        cutMaxAbs = std::max(cutMaxAbs, a);
                        cutCount += 1u;
                    } else {
                        cellSum2 += a * a;
                        cellMaxAbs = std::max(cellMaxAbs, a);
                        cellCount += 1u;
                    }
                }
            }
        }
    }
    stats.faceCount = count;
    stats.sum2 = sum2;
    stats.maxAbs = maxAbs;
    stats.cellFaceCount = cellCount;
    stats.cellSum2 = cellSum2;
    stats.cellMaxAbs = cellMaxAbs;
    stats.cutFaceCount = cutCount;
    stats.cutSum2 = cutSum2;
    stats.cutMaxAbs = cutMaxAbs;
    return stats;
}

void store_q6_solid_leak_stats(const Q6SolidLeakStats& stats,
                               Q6ProjectionDiagnostics& diag) {
    diag.immersedSolidLeakFaceCount = stats.faceCount;
    diag.immersedSolidLeakProjectedFluxRms = stats.faceCount > 0u ?
        std::sqrt(stats.sum2 / static_cast<double>(stats.faceCount)) : 0.0;
    diag.immersedSolidLeakProjectedFluxMaxAbs = stats.maxAbs;
    diag.immersedSolidLeakCellClosedProjectedFluxRms = stats.cellFaceCount > 0u ?
        std::sqrt(stats.cellSum2 / static_cast<double>(stats.cellFaceCount)) : 0.0;
    diag.immersedSolidLeakCellClosedProjectedFluxMaxAbs = stats.cellMaxAbs;
    diag.immersedSolidLeakCutProjectedFluxRms = stats.cutFaceCount > 0u ?
        std::sqrt(stats.cutSum2 / static_cast<double>(stats.cutFaceCount)) : 0.0;
    diag.immersedSolidLeakCutProjectedFluxMaxAbs = stats.cutMaxAbs;
}

void compute_q6_solid_leak(const PeriodicFaceField& projectedFlux,
                           const ImmersedSolidProjectionMask& mask,
                           const SimulationParams& params,
                           Q6ProjectionDiagnostics& diag) {
    store_q6_solid_leak_stats(measure_q6_solid_boundary_leak(projectedFlux, mask, params), diag);
}

void enforce_q6_immersed_closed_face_flux(const SimulationParams& params,
                                          const PeriodicFaceField& baseFlux,
                                          PeriodicFaceField& appliedCorrectionFlux,
                                          PeriodicFaceField& appliedProjectedFlux,
                                          const ImmersedSolidProjectionMask& mask,
                                          Q6ProjectionDiagnostics& diag) {
    if (mask.activeCell.empty()) return;
    const int Nx = std::max(1, params.Nx);
    const int Ny = std::max(1, params.Ny);
    const bool periodicX = is_x_periodic(params);
    const bool periodicY = is_y_periodic(params);

    const Q6SolidLeakStats before = measure_q6_solid_boundary_leak(appliedProjectedFlux, mask, params);
    diag.immersedSolidAppliedLeakBeforeClosureRms = before.faceCount > 0u ?
        std::sqrt(before.sum2 / static_cast<double>(before.faceCount)) : 0.0;
    diag.immersedSolidAppliedLeakBeforeClosureMaxAbs = before.maxAbs;

    double sum2 = 0.0;
    double maxAbs = 0.0;
    std::uint64_t count = 0u;
#pragma omp parallel for reduction(+:sum2,count) reduction(max:maxAbs) if(Nx * Ny > 4096)
    for (int j = 0; j < Ny; ++j) {
        for (int i = 0; i < Nx; ++i) {
            const int c = q6_cell_index(i, j, Nx);
            const std::size_t k = static_cast<std::size_t>(c);
            if (periodicX || i < Nx - 1) {
                const int ip = periodicX ? ((i + 1) % Nx) : (i + 1);
                const int e = q6_cell_index(ip, j, Nx);
                if (q6_face_is_immersed_boundary(mask, c, e, true)) {
                    const double a = std::abs(appliedProjectedFlux.x[k]);
                    sum2 += a * a;
                    maxAbs = std::max(maxAbs, a);
                    count += 1u;
                    appliedCorrectionFlux.x[k] = -baseFlux.x[k];
                    appliedProjectedFlux.x[k] = 0.0;
                }
            }
            if (periodicY || j < Ny - 1) {
                const int jp = periodicY ? ((j + 1) % Ny) : (j + 1);
                const int n = q6_cell_index(i, jp, Nx);
                if (q6_face_is_immersed_boundary(mask, c, n, false)) {
                    const double a = std::abs(appliedProjectedFlux.y[k]);
                    sum2 += a * a;
                    maxAbs = std::max(maxAbs, a);
                    count += 1u;
                    appliedCorrectionFlux.y[k] = -baseFlux.y[k];
                    appliedProjectedFlux.y[k] = 0.0;
                }
            }
        }
    }
    diag.immersedSolidClosedFaceFluxEnforcedFaces = count;
    diag.immersedSolidClosedFaceFluxEnforcedRms = count > 0u ?
        std::sqrt(sum2 / static_cast<double>(count)) : 0.0;
    diag.immersedSolidClosedFaceFluxEnforcedMaxAbs = maxAbs;
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

bool has_x_io_pair(const SimulationParams& params) {
    return (is_inlet_boundary_mode(params.bcLeft) && is_outlet_boundary_mode(params.bcRight)) ||
           (is_outlet_boundary_mode(params.bcLeft) && is_inlet_boundary_mode(params.bcRight));
}

bool has_y_io_pair(const SimulationParams& params) {
    return (is_inlet_boundary_mode(params.bcBottom) && is_outlet_boundary_mode(params.bcTop)) ||
           (is_outlet_boundary_mode(params.bcBottom) && is_inlet_boundary_mode(params.bcTop));
}

double inlet_velocity_ramp_factor(const SimulationParams& params, double time) {
    if (!params.inletVelocityRampEnable) return 1.0;
    const double t0 = params.inletVelocityRampStartTime;
    const double t1 = params.inletVelocityRampEndTime;
    if (!(t1 > t0)) return params.inletVelocityRampFinalFactor;
    double a = 0.0;
    if (time <= t0) a = 0.0;
    else if (time >= t1) a = 1.0;
    else a = (time - t0) / (t1 - t0);
    if (params.inletVelocityRampProfile == "smoothstep") {
        a = a * a * (3.0 - 2.0 * a);
    }
    return (1.0 - a) * params.inletVelocityRampInitialFactor +
           a * params.inletVelocityRampFinalFactor;
}

double q6_open_x_flux_component(const SimulationParams& params, double time) {
    const double f = inlet_velocity_ramp_factor(params, time);
    if (is_inlet_boundary_mode(params.bcLeft) && is_outlet_boundary_mode(params.bcRight)) {
        return f * params.inletUxLeft;
    }
    if (is_inlet_boundary_mode(params.bcRight) && is_outlet_boundary_mode(params.bcLeft)) {
        return f * params.inletUxRight;
    }
    return 0.0;
}

double q6_open_y_flux_component(const SimulationParams& params, double time) {
    const double f = inlet_velocity_ramp_factor(params, time);
    if (is_inlet_boundary_mode(params.bcBottom) && is_outlet_boundary_mode(params.bcTop)) {
        return f * params.inletUyBottom;
    }
    if (is_inlet_boundary_mode(params.bcTop) && is_outlet_boundary_mode(params.bcBottom)) {
        return f * params.inletUyTop;
    }
    return 0.0;
}

double smoothstep01(double x) {
    x = std::clamp(x, 0.0, 1.0);
    return x * x * (3.0 - 2.0 * x);
}

double flat_taper_y_base_factor(const SimulationParams& params,
                                const FluidDomainBounds& domain,
                                double y) {
    if (!(params.inletVelocityWallTaperCells > 0.0)) return 1.0;
    const double h = domain.yMax - domain.yMin;
    if (!(h > 0.0)) return 1.0;
    const double dy = h / static_cast<double>(std::max(1, params.Ny));
    const double taperWidth = params.inletVelocityWallTaperCells * dy;
    if (!(taperWidth > 0.0)) return 1.0;
    const double dist = std::min(y - domain.yMin, domain.yMax - y);
    return smoothstep01(dist / taperWidth);
}

double flat_taper_y_mean_factor(const SimulationParams& params,
                                const FluidDomainBounds& domain,
                                double y) {
    const double base = flat_taper_y_base_factor(params, domain, y);
    const int Ny = std::max(1, params.Ny);
    const double h = domain.yMax - domain.yMin;
    if (!(h > 0.0)) return base;
    const double dy = h / static_cast<double>(Ny);
    double meanBase = 0.0;
    for (int j = 0; j < Ny; ++j) {
        const double yc = domain.yMin + (static_cast<double>(j) + 0.5) * dy;
        meanBase += flat_taper_y_base_factor(params, domain, yc);
    }
    meanBase /= static_cast<double>(Ny);
    if (!(meanBase > 0.0)) return base;
    return base / meanBase;
}

double inlet_y_profile_factor(const SimulationParams& params,
                              const FluidDomainBounds& domain,
                              double y) {
    const std::string profile = params.inletVelocitySpatialProfile;
    const double h = domain.yMax - domain.yMin;
    if (!(h > 0.0)) return 1.0;
    if (profile == "poiseuille_y" || profile == "poiseuille_y_mean" || profile == "poiseuille_y_max") {
        const double eta = std::clamp((y - domain.yMin) / h, 0.0, 1.0);
        const double shape = eta * (1.0 - eta);
        return profile == "poiseuille_y_max" ? 4.0 * shape : 6.0 * shape;
    }
    if (profile == "flat_taper_y" || profile == "flat_taper_y_mean") {
        return flat_taper_y_mean_factor(params, domain, y);
    }
    return 1.0;
}

struct ApertureInterval { double lo = 0.0; double hi = 0.0; };

ApertureInterval normalize_aperture_interval(double requestedLo, double requestedHi, double domainLo, double domainHi) {
    ApertureInterval a{};
    a.lo = std::clamp(requestedLo, domainLo, domainHi);
    const double hiRaw = requestedHi < 0.0 ? domainHi : requestedHi;
    a.hi = std::clamp(hiRaw, domainLo, domainHi);
    if (a.hi < a.lo) a.hi = a.lo;
    return a;
}

ApertureInterval x_face_aperture_y(const SimulationParams& params, const FluidDomainBounds& domain, const char* face) {
    if (!params.openBoundaryApertureEnable) return {domain.yMin, domain.yMax};
    const std::string f(face);
    if (f == "left") return normalize_aperture_interval(params.leftOpenYMin, params.leftOpenYMax, domain.yMin, domain.yMax);
    if (f == "right") return normalize_aperture_interval(params.rightOpenYMin, params.rightOpenYMax, domain.yMin, domain.yMax);
    return {domain.yMin, domain.yMax};
}

ApertureInterval y_face_aperture_x(const SimulationParams& params, const FluidDomainBounds& domain, const char* face) {
    if (!params.openBoundaryApertureEnable) return {domain.xMin, domain.xMax};
    const std::string f(face);
    if (f == "bottom") return normalize_aperture_interval(params.bottomOpenXMin, params.bottomOpenXMax, domain.xMin, domain.xMax);
    if (f == "top") return normalize_aperture_interval(params.topOpenXMin, params.topOpenXMax, domain.xMin, domain.xMax);
    return {domain.xMin, domain.xMax};
}

bool cell_center_in_interval(double center, const ApertureInterval& a) {
    return center >= a.lo && center <= a.hi;
}

void set_x_boundary_flux_profile(std::vector<double>& profile,
                                 const SimulationParams& params,
                                 const FluidDomainBounds& domain,
                                 double value,
                                 const ApertureInterval& a) {
    profile.assign(static_cast<std::size_t>(params.Ny), 0.0);
    const double dy = (domain.yMax - domain.yMin) / static_cast<double>(std::max(1, params.Ny));
    for (int j = 0; j < params.Ny; ++j) {
        const double yc = domain.yMin + (static_cast<double>(j) + 0.5) * dy;
        if (cell_center_in_interval(yc, a)) {
            profile[static_cast<std::size_t>(j)] = value * inlet_y_profile_factor(params, domain, yc);
        }
    }
}

void set_y_boundary_flux_profile(std::vector<double>& profile,
                                 int Nx,
                                 double xMin,
                                 double xMax,
                                 double value,
                                 const ApertureInterval& a) {
    profile.assign(static_cast<std::size_t>(Nx), 0.0);
    const double dx = (xMax - xMin) / static_cast<double>(std::max(1, Nx));
    for (int i = 0; i < Nx; ++i) {
        const double xc = xMin + (static_cast<double>(i) + 0.5) * dx;
        if (cell_center_in_interval(xc, a)) profile[static_cast<std::size_t>(i)] = value;
    }
}

double mean_profile_value(const std::vector<double>& v, double fallback) {
    if (v.empty()) return fallback;
    double s = 0.0;
    for (const double x : v) s += x;
    return s / static_cast<double>(v.size());
}

std::string normalized_open_boundary_outlet_mode(const SimulationParams& params) {
    std::string m = params.openBoundaryOutletMode;
    std::replace(m.begin(), m.end(), '-', '_');
    return m;
}

bool open_boundary_outlet_mode_is_neumann(const SimulationParams& params) {
    const std::string m = normalized_open_boundary_outlet_mode(params);
    return m == "neumann" || m == "free" ||
           m == "zero_gradient" || m == "zero_normal_gradient";
}

bool open_boundary_outlet_mode_is_hybrid(const SimulationParams& params) {
    const std::string m = normalized_open_boundary_outlet_mode(params);
    return m == "hybrid" || m == "neumann_feedback" || m == "hybrid_feedback";
}

bool open_boundary_outlet_uses_local_base(const SimulationParams& params) {
    return open_boundary_outlet_mode_is_neumann(params) || open_boundary_outlet_mode_is_hybrid(params);
}

double outlet_hybrid_blend(const SimulationParams& params) {
    if (!open_boundary_outlet_mode_is_hybrid(params)) return 0.0;
    return std::max(0.0, std::min(1.0, params.openBoundaryOutletHybridBlend));
}

double outlet_feedback_gain(const SimulationParams& params) {
    if (!open_boundary_outlet_mode_is_hybrid(params)) return 0.0;
    return std::max(0.0, std::min(1.0, params.openBoundaryOutletFeedbackGain));
}

void blend_boundary_profiles(std::vector<double>& localProfile,
                             const std::vector<double>& balancedProfile,
                             double blend) {
    if (blend <= 0.0 || localProfile.empty() || balancedProfile.size() != localProfile.size()) return;
    const double a = std::max(0.0, std::min(1.0, blend));
    for (std::size_t i = 0; i < localProfile.size(); ++i) {
        localProfile[i] = (1.0 - a) * localProfile[i] + a * balancedProfile[i];
    }
}

double x_profile_integral(const std::vector<double>& profile, const SimulationParams& params, const FluidDomainBounds& domain, double fallback) {
    const double height = fluid_domain_height(domain);
    if (profile.empty()) return fallback * height;
    const double dy = height / static_cast<double>(std::max(1, params.Ny));
    return std::accumulate(profile.begin(), profile.end(), 0.0) * dy;
}

double y_profile_integral(const std::vector<double>& profile, const SimulationParams& params, const FluidDomainBounds& domain, double fallback) {
    const double width = fluid_domain_width(domain);
    if (profile.empty()) return fallback * width;
    const double dx = width / static_cast<double>(std::max(1, params.Nx));
    return std::accumulate(profile.begin(), profile.end(), 0.0) * dx;
}

double x_aperture_length(const SimulationParams& params, const FluidDomainBounds& domain, const ApertureInterval& a) {
    const double dy = fluid_domain_height(domain) / static_cast<double>(std::max(1, params.Ny));
    double length = 0.0;
    for (int j = 0; j < params.Ny; ++j) {
        const double yc = domain.yMin + (static_cast<double>(j) + 0.5) * dy;
        if (cell_center_in_interval(yc, a)) length += dy;
    }
    return length;
}

double y_aperture_length(const SimulationParams& params, const FluidDomainBounds& domain, const ApertureInterval& a) {
    const double dx = fluid_domain_width(domain) / static_cast<double>(std::max(1, params.Nx));
    double length = 0.0;
    for (int i = 0; i < params.Nx; ++i) {
        const double xc = domain.xMin + (static_cast<double>(i) + 0.5) * dx;
        if (cell_center_in_interval(xc, a)) length += dx;
    }
    return length;
}

void add_uniform_to_x_aperture_profile(std::vector<double>& profile,
                                       const SimulationParams& params,
                                       const FluidDomainBounds& domain,
                                       const ApertureInterval& a,
                                       double delta) {
    if (profile.empty() || delta == 0.0) return;
    const double dy = fluid_domain_height(domain) / static_cast<double>(std::max(1, params.Ny));
    for (int j = 0; j < params.Ny; ++j) {
        const double yc = domain.yMin + (static_cast<double>(j) + 0.5) * dy;
        if (cell_center_in_interval(yc, a)) profile[static_cast<std::size_t>(j)] += delta;
    }
}

void add_uniform_to_y_aperture_profile(std::vector<double>& profile,
                                       const SimulationParams& params,
                                       const FluidDomainBounds& domain,
                                       const ApertureInterval& a,
                                       double delta) {
    if (profile.empty() || delta == 0.0) return;
    const double dx = fluid_domain_width(domain) / static_cast<double>(std::max(1, params.Nx));
    for (int i = 0; i < params.Nx; ++i) {
        const double xc = domain.xMin + (static_cast<double>(i) + 0.5) * dx;
        if (cell_center_in_interval(xc, a)) profile[static_cast<std::size_t>(i)] += delta;
    }
}

void set_x_boundary_flux_profile_from_base(std::vector<double>& profile,
                                           const SimulationParams& params,
                                           const FluidDomainBounds& domain,
                                           const PeriodicFaceField& baseFlux,
                                           bool highFace,
                                           const ApertureInterval& a) {
    profile.assign(static_cast<std::size_t>(params.Ny), 0.0);
    const int i = highFace ? (params.Nx - 1) : 0;
    const double dy = (domain.yMax - domain.yMin) / static_cast<double>(std::max(1, params.Ny));
    for (int j = 0; j < params.Ny; ++j) {
        const double yc = domain.yMin + (static_cast<double>(j) + 0.5) * dy;
        if (cell_center_in_interval(yc, a)) {
            const int c = i + params.Nx * j;
            profile[static_cast<std::size_t>(j)] = baseFlux.x[static_cast<std::size_t>(c)];
        }
    }
}

void set_y_boundary_flux_profile_from_base(std::vector<double>& profile,
                                           const SimulationParams& params,
                                           const FluidDomainBounds& domain,
                                           const PeriodicFaceField& baseFlux,
                                           bool highFace,
                                           const ApertureInterval& a) {
    profile.assign(static_cast<std::size_t>(params.Nx), 0.0);
    const int j = highFace ? (params.Ny - 1) : 0;
    const double dx = (domain.xMax - domain.xMin) / static_cast<double>(std::max(1, params.Nx));
    for (int i = 0; i < params.Nx; ++i) {
        const double xc = domain.xMin + (static_cast<double>(i) + 0.5) * dx;
        if (cell_center_in_interval(xc, a)) {
            const int c = i + params.Nx * j;
            profile[static_cast<std::size_t>(i)] = baseFlux.y[static_cast<std::size_t>(c)];
        }
    }
}

void apply_hybrid_feedback_to_q6_open_boundaries(EllipticProjectionBC& bc,
                                                  const SimulationParams& params,
                                                  const FluidDomainBounds& domain,
                                                  const ApertureInterval& leftA,
                                                  const ApertureInterval& rightA,
                                                  const ApertureInterval& bottomA,
                                                  const ApertureInterval& topA) {
    const double gain = outlet_feedback_gain(params);
    if (gain <= 0.0) return;

    const bool leftOutlet = is_outlet_boundary_mode(params.bcLeft);
    const bool rightOutlet = is_outlet_boundary_mode(params.bcRight);
    const bool bottomOutlet = is_outlet_boundary_mode(params.bcBottom);
    const bool topOutlet = is_outlet_boundary_mode(params.bcTop);

    const double xLowIntegral = x_profile_integral(bc.xLowFluxProfile, params, domain, bc.xLowFlux);
    const double xHighIntegral = x_profile_integral(bc.xHighFluxProfile, params, domain, bc.xHighFlux);
    const double yLowIntegral = y_profile_integral(bc.yLowFluxProfile, params, domain, bc.yLowFlux);
    const double yHighIntegral = y_profile_integral(bc.yHighFluxProfile, params, domain, bc.yHighFlux);
    const double balance = (xHighIntegral - xLowIntegral) + (yHighIntegral - yLowIntegral);
    if (balance == 0.0) return;

    double outletLength = 0.0;
    if (leftOutlet) outletLength += x_aperture_length(params, domain, leftA);
    if (rightOutlet) outletLength += x_aperture_length(params, domain, rightA);
    if (bottomOutlet) outletLength += y_aperture_length(params, domain, bottomA);
    if (topOutlet) outletLength += y_aperture_length(params, domain, topA);
    if (outletLength <= 0.0) return;

    // Positive balance means net flux is leaving the domain in the elliptic
    // sign convention.  The outlet-only correction below reduces this balance
    // by gain*balance while preserving the local Neumann profile up to a weak
    // uniform feedback over all open outlet cells.
    const double perLength = gain * balance / outletLength;
    if (leftOutlet) add_uniform_to_x_aperture_profile(bc.xLowFluxProfile, params, domain, leftA, +perLength);
    if (rightOutlet) add_uniform_to_x_aperture_profile(bc.xHighFluxProfile, params, domain, rightA, -perLength);
    if (bottomOutlet) add_uniform_to_y_aperture_profile(bc.yLowFluxProfile, params, domain, bottomA, +perLength);
    if (topOutlet) add_uniform_to_y_aperture_profile(bc.yHighFluxProfile, params, domain, topA, -perLength);

    bc.xLowFlux = mean_profile_value(bc.xLowFluxProfile, bc.xLowFlux);
    bc.xHighFlux = mean_profile_value(bc.xHighFluxProfile, bc.xHighFlux);
    bc.yLowFlux = mean_profile_value(bc.yLowFluxProfile, bc.yLowFlux);
    bc.yHighFlux = mean_profile_value(bc.yHighFluxProfile, bc.yHighFlux);
}

void add_boundary_fluxes_to_q6_bc(EllipticProjectionBC& bc,
                                  const PeriodicFaceField& baseFlux,
                                  const SimulationParams& params,
                                  const FluidDomainBounds& domain,
                                  double time,
                                  Q6ProjectionDiagnostics& diag) {
    if (!is_x_periodic(params)) {
        bc.xLowFlux = domain.vxMin;
        bc.xHighFlux = domain.vxMax;
    }
    if (!is_y_periodic(params)) {
        bc.yLowFlux = domain.vyMin;
        bc.yHighFlux = domain.vyMax;
    }

    // Open-boundary projection policy.  The validated default
    // openBoundaryOutletMode=balanced_flux prescribes the same ramped inlet
    // velocity flux on both open faces.  Neumann samples the outlet flux from
    // the current base face field.  Hybrid starts from Neumann, optionally
    // blends toward balanced_flux, then applies an outlet-only weak feedback
    // that reduces the global open-boundary flux imbalance.
    ApertureInterval leftA{0.0, 0.0};
    ApertureInterval rightA{0.0, 0.0};
    ApertureInterval bottomA{0.0, 0.0};
    ApertureInterval topA{0.0, 0.0};

    if (has_x_io_pair(params)) {
        const double ux = q6_open_x_flux_component(params, time);
        const bool localOutlet = open_boundary_outlet_uses_local_base(params);
        const bool hybridOutlet = open_boundary_outlet_mode_is_hybrid(params);
        const double blend = outlet_hybrid_blend(params);
        const bool leftInlet = is_inlet_boundary_mode(params.bcLeft);
        const bool rightInlet = is_inlet_boundary_mode(params.bcRight);
        leftA = x_face_aperture_y(params, domain, "left");
        rightA = x_face_aperture_y(params, domain, "right");

        if (leftInlet || !localOutlet) {
            bc.xLowFlux = ux;
            if (params.openBoundaryApertureEnable || params.inletVelocitySpatialProfile != "uniform") {
                set_x_boundary_flux_profile(bc.xLowFluxProfile, params, domain, ux, leftA);
                bc.xLowFlux = mean_profile_value(bc.xLowFluxProfile, ux);
            }
        } else {
            set_x_boundary_flux_profile_from_base(bc.xLowFluxProfile, params, domain, baseFlux, false, leftA);
            if (hybridOutlet && blend > 0.0) {
                std::vector<double> balanced;
                set_x_boundary_flux_profile(balanced, params, domain, ux, leftA);
                blend_boundary_profiles(bc.xLowFluxProfile, balanced, blend);
            }
            bc.xLowFlux = mean_profile_value(bc.xLowFluxProfile, 0.0);
        }

        if (rightInlet || !localOutlet) {
            bc.xHighFlux = ux;
            if (params.openBoundaryApertureEnable || params.inletVelocitySpatialProfile != "uniform") {
                set_x_boundary_flux_profile(bc.xHighFluxProfile, params, domain, ux, rightA);
                bc.xHighFlux = mean_profile_value(bc.xHighFluxProfile, ux);
            }
        } else {
            set_x_boundary_flux_profile_from_base(bc.xHighFluxProfile, params, domain, baseFlux, true, rightA);
            if (hybridOutlet && blend > 0.0) {
                std::vector<double> balanced;
                set_x_boundary_flux_profile(balanced, params, domain, ux, rightA);
                blend_boundary_profiles(bc.xHighFluxProfile, balanced, blend);
            }
            bc.xHighFlux = mean_profile_value(bc.xHighFluxProfile, 0.0);
        }

        diag.openBoundaryEnabled = true;
    }
    if (has_y_io_pair(params)) {
        const double uy = q6_open_y_flux_component(params, time);
        const bool localOutlet = open_boundary_outlet_uses_local_base(params);
        const bool hybridOutlet = open_boundary_outlet_mode_is_hybrid(params);
        const double blend = outlet_hybrid_blend(params);
        const bool bottomInlet = is_inlet_boundary_mode(params.bcBottom);
        const bool topInlet = is_inlet_boundary_mode(params.bcTop);
        bottomA = y_face_aperture_x(params, domain, "bottom");
        topA = y_face_aperture_x(params, domain, "top");

        if (bottomInlet || !localOutlet) {
            bc.yLowFlux = uy;
            if (params.openBoundaryApertureEnable) {
                set_y_boundary_flux_profile(bc.yLowFluxProfile, params.Nx, domain.xMin, domain.xMax, uy, bottomA);
                bc.yLowFlux = mean_profile_value(bc.yLowFluxProfile, uy);
            }
        } else {
            set_y_boundary_flux_profile_from_base(bc.yLowFluxProfile, params, domain, baseFlux, false, bottomA);
            if (hybridOutlet && blend > 0.0) {
                std::vector<double> balanced;
                set_y_boundary_flux_profile(balanced, params.Nx, domain.xMin, domain.xMax, uy, bottomA);
                blend_boundary_profiles(bc.yLowFluxProfile, balanced, blend);
            }
            bc.yLowFlux = mean_profile_value(bc.yLowFluxProfile, 0.0);
        }

        if (topInlet || !localOutlet) {
            bc.yHighFlux = uy;
            if (params.openBoundaryApertureEnable) {
                set_y_boundary_flux_profile(bc.yHighFluxProfile, params.Nx, domain.xMin, domain.xMax, uy, topA);
                bc.yHighFlux = mean_profile_value(bc.yHighFluxProfile, uy);
            }
        } else {
            set_y_boundary_flux_profile_from_base(bc.yHighFluxProfile, params, domain, baseFlux, true, topA);
            if (hybridOutlet && blend > 0.0) {
                std::vector<double> balanced;
                set_y_boundary_flux_profile(balanced, params.Nx, domain.xMin, domain.xMax, uy, topA);
                blend_boundary_profiles(bc.yHighFluxProfile, balanced, blend);
            }
            bc.yHighFlux = mean_profile_value(bc.yHighFluxProfile, 0.0);
        }

        diag.openBoundaryEnabled = true;
    }

    if (open_boundary_outlet_mode_is_hybrid(params)) {
        apply_hybrid_feedback_to_q6_open_boundaries(bc, params, domain, leftA, rightA, bottomA, topA);
    }

    diag.openBoundaryFluxXLow = bc.xLowFlux;
    diag.openBoundaryFluxXHigh = bc.xHighFlux;
    diag.openBoundaryFluxYLow = bc.yLowFlux;
    diag.openBoundaryFluxYHigh = bc.yHighFlux;

    const double width = fluid_domain_width(domain);
    const double height = fluid_domain_height(domain);
    const double xLowIntegral = bc.xLowFluxProfile.empty() ? bc.xLowFlux * height :
        std::accumulate(bc.xLowFluxProfile.begin(), bc.xLowFluxProfile.end(), 0.0) * (height / static_cast<double>(params.Ny));
    const double xHighIntegral = bc.xHighFluxProfile.empty() ? bc.xHighFlux * height :
        std::accumulate(bc.xHighFluxProfile.begin(), bc.xHighFluxProfile.end(), 0.0) * (height / static_cast<double>(params.Ny));
    const double yLowIntegral = bc.yLowFluxProfile.empty() ? bc.yLowFlux * width :
        std::accumulate(bc.yLowFluxProfile.begin(), bc.yLowFluxProfile.end(), 0.0) * (width / static_cast<double>(params.Nx));
    const double yHighIntegral = bc.yHighFluxProfile.empty() ? bc.yHighFlux * width :
        std::accumulate(bc.yHighFluxProfile.begin(), bc.yHighFluxProfile.end(), 0.0) * (width / static_cast<double>(params.Nx));
    diag.openBoundaryFluxBalance = (xHighIntegral - xLowIntegral) + (yHighIntegral - yLowIntegral);
    const double area = width * height;
    diag.openBoundaryMeanDivergence = area > 0.0 ? diag.openBoundaryFluxBalance / area : 0.0;
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
        if (!is_fluid_particle(state, i)) {
            continue;
        }
        const int c = ws.cellId[i];
        if (c < 0) {
            continue;
        }
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
            if (!is_fluid_particle(state, i)) {
                continue;
            }
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
                                                     double time,
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
    eparams.warmStartFromWorkspace = params.q6WarmStartEnable;

    EllipticProjectionBC bc = q6_bc_from_particle_boundaries(params);
    add_boundary_fluxes_to_q6_bc(bc, workspace.baseFlux, params, domain, time, diag);
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
    if (mask != nullptr && params.immersedSolidEnable) {
        enforce_q6_immersed_closed_face_flux(params,
                                             workspace.baseFlux,
                                             workspace.appliedCorrectionFlux,
                                             workspace.appliedProjectedFlux,
                                             workspace.immersedMask,
                                             diag);
    }

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
        compute_q6_solid_leak(workspace.appliedProjectedFlux, workspace.immersedMask, params, diag);
    }
    face_correction_to_cell_velocity(grid, workspace.appliedCorrectionFlux, workspace.cellDUx, workspace.cellDUy, diag);

    // In this Q6 adapter convention, the corrected cell-centered velocity is
    // represented by the same stored east/north face values as
    // appliedProjectedFlux: U_corrected = U_cell + DU_cell, with DU_cell equal
    // to the applied correction flux component.  Rebuilding a second face field
    // and recomputing its divergence costs a full grid pass every Q6 step while
    // yielding the same diagnostic.  Keep the historical columns but reuse the
    // projected-flux divergence by default; the old explicit reconstruction can
    // be restored with q6ReuseProjectedDivergenceDiagnostics=false.
    if (params.q6ReuseProjectedDivergenceDiagnostics) {
        diag.divAfterCellVelocityRms = diag.divAfterProjectedFluxRms;
        diag.divAfterCellVelocityMaxAbs = diag.divAfterProjectedFluxMaxAbs;
    } else {
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
    }

    apply_cell_velocity_correction(state, workspace, diag, params.projectionMomentumCorrectionEnable);
    return diag;
}

} // namespace mpcd
