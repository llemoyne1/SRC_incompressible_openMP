#include "q9_projection_adapter.h"

#include <algorithm>
#include <cctype>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <limits>
#include <stdexcept>
#include <string>

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

void resize_q9_workspace(Q9ProjectionWorkspace& ws,
                         std::uint64_t numParticles,
                         int numCells,
                         int numThreads) {
    if (numCells <= 0) {
        throw std::runtime_error("resize_q9_workspace: invalid number of cells");
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
    ws.cellDUx.assign(nc, 0.0);
    ws.cellDUy.assign(nc, 0.0);
    ws.localMass.assign(nLocal, 0.0);
    ws.localPx.assign(nLocal, 0.0);
    ws.localPy.assign(nLocal, 0.0);
    ws.targetDivergence.assign(nc, 0.0);
    ws.massAfterEstimate.assign(nc, 0.0);
    resize_periodic_face_field(ws.baseMassFlux, numCells);
    resize_periodic_face_field(ws.alpha, numCells);
    resize_periodic_face_field(ws.appliedCorrectionFlux, numCells);
    resize_periodic_face_field(ws.projectedMassFlux, numCells);
    resize_elliptic_projection_workspace(ws.elliptic, numCells);
}

EllipticProjectionBC q9_bc_from_particle_boundaries(const SimulationParams& params) {
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

double q9_open_x_velocity_component(const SimulationParams& params) {
    if (is_inlet_boundary_mode(params.bcLeft) && is_outlet_boundary_mode(params.bcRight)) {
        return params.inletUxLeft;
    }
    if (is_inlet_boundary_mode(params.bcRight) && is_outlet_boundary_mode(params.bcLeft)) {
        return params.inletUxRight;
    }
    return 0.0;
}

double q9_open_y_velocity_component(const SimulationParams& params) {
    if (is_inlet_boundary_mode(params.bcBottom) && is_outlet_boundary_mode(params.bcTop)) {
        return params.inletUyBottom;
    }
    if (is_inlet_boundary_mode(params.bcTop) && is_outlet_boundary_mode(params.bcBottom)) {
        return params.inletUyTop;
    }
    return 0.0;
}

void add_boundary_mass_fluxes_to_q9_bc(EllipticProjectionBC& bc,
                                       const SimulationParams& params,
                                       const FluidDomainBounds& domain,
                                       double meanCellMass,
                                       Q9ProjectionDiagnostics& diag) {
    if (!is_x_periodic(params)) {
        bc.xLowFlux = meanCellMass * domain.vxMin;
        bc.xHighFlux = meanCellMass * domain.vxMax;
    }
    if (!is_y_periodic(params)) {
        bc.yLowFlux = meanCellMass * domain.vyMin;
        bc.yHighFlux = meanCellMass * domain.vyMax;
    }

    // 0063 minimal open-boundary policy for Q9: use the same balanced face
    // flux convention as 0062/Q6, but in mass-flux units.  The prescribed
    // velocity is multiplied by the current mean cell mass, matching the Q9
    // compact face-field convention baseMassFlux = cellMass * cellVelocity.
    if (has_x_io_pair(params)) {
        const double jx = meanCellMass * q9_open_x_velocity_component(params);
        bc.xLowFlux = jx;
        bc.xHighFlux = jx;
        diag.openBoundaryEnabled = true;
    }
    if (has_y_io_pair(params)) {
        const double jy = meanCellMass * q9_open_y_velocity_component(params);
        bc.yLowFlux = jy;
        bc.yHighFlux = jy;
        diag.openBoundaryEnabled = true;
    }

    diag.openBoundaryMassFluxXLow = bc.xLowFlux;
    diag.openBoundaryMassFluxXHigh = bc.xHighFlux;
    diag.openBoundaryMassFluxYLow = bc.yLowFlux;
    diag.openBoundaryMassFluxYHigh = bc.yHighFlux;

    const double width = fluid_domain_width(domain);
    const double height = fluid_domain_height(domain);
    diag.openBoundaryMassFluxBalance = (bc.xHighFlux - bc.xLowFlux) * height +
                                       (bc.yHighFlux - bc.yLowFlux) * width;
    const double area = width * height;
    diag.openBoundaryMeanDivergence = area > 0.0 ? diag.openBoundaryMassFluxBalance / area : 0.0;
}

void deposit_cell_mass_momentum(const ParticleState& state,
                                const SimulationParams& params,
                                const CellGrid& grid,
                                const FluidDomainBounds& domain,
                                Q9ProjectionWorkspace& ws,
                                Q9ProjectionDiagnostics& diag) {
    const std::size_t n = static_cast<std::size_t>(state.Np);
    const int nc = grid.numCells;
    const int nt = std::max(1, thread_count());

    std::fill(ws.cellMass.begin(), ws.cellMass.end(), 0.0);
    std::fill(ws.cellPx.begin(), ws.cellPx.end(), 0.0);
    std::fill(ws.cellPy.begin(), ws.cellPy.end(), 0.0);
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
        if (!(m > 0.0)) {
            ++empty;
        }
    }
    diag.emptyCells = empty;
}

void build_mass_flux_from_cell_momentum(const CellGrid& grid,
                                        const std::vector<double>& px,
                                        const std::vector<double>& py,
                                        PeriodicFaceField& flux) {
    const int nc = grid.numCells;
    if (static_cast<int>(px.size()) != nc || static_cast<int>(py.size()) != nc) {
        throw std::runtime_error("build_mass_flux_from_cell_momentum: invalid array size");
    }
    resize_periodic_face_field(flux, nc);
#pragma omp parallel for if(nc > 4096)
    for (int c = 0; c < nc; ++c) {
        const std::size_t k = static_cast<std::size_t>(c);
        flux.x[k] = px[k];
        flux.y[k] = py[k];
    }
}

void fill_alpha(PeriodicFaceField& alpha, int numCells, double value) {
    resize_periodic_face_field(alpha, numCells);
    std::fill(alpha.x.begin(), alpha.x.end(), value);
    std::fill(alpha.y.begin(), alpha.y.end(), value);
}

int q9_cell_index(int i, int j, int Nx) {
    return i + Nx * j;
}

void initialize_all_active_mask(EllipticProjectionMask& mask, int nc) {
    mask.activeCell.assign(static_cast<std::size_t>(nc), 1u);
    mask.activeCells = static_cast<std::uint64_t>(std::max(0, nc));
    mask.inactiveCells = 0u;
}

bool deactivate_q9_cell(EllipticProjectionMask& mask, int c) {
    const std::size_t k = static_cast<std::size_t>(c);
    if (mask.activeCell[k] == 0u) {
        return false;
    }
    mask.activeCell[k] = 0u;
    return true;
}

void recount_q9_mask(EllipticProjectionMask& mask) {
    std::uint64_t active = 0u;
    for (const std::uint8_t v : mask.activeCell) {
        if (v != 0u) ++active;
    }
    mask.activeCells = active;
    mask.inactiveCells = static_cast<std::uint64_t>(mask.activeCell.size()) - active;
}

bool q9_safety_mask_requested(const SimulationParams& params) {
    return params.q9OpenBoundaryExclusionCells > 0 || params.q9ImmersedSolidHaloCells > 0;
}

void apply_q9_open_boundary_exclusion(const SimulationParams& params,
                                      const CellGrid& grid,
                                      EllipticProjectionMask& mask,
                                      Q9ProjectionDiagnostics& diag) {
    const int n = std::max(0, params.q9OpenBoundaryExclusionCells);
    if (n <= 0) return;

    std::uint64_t changed = 0u;
    if (has_x_io_pair(params)) {
        const int w = std::min(n, grid.Nx);
        for (int j = 0; j < grid.Ny; ++j) {
            for (int i = 0; i < w; ++i) {
                if (deactivate_q9_cell(mask, q9_cell_index(i, j, grid.Nx))) ++changed;
            }
            for (int i = std::max(0, grid.Nx - w); i < grid.Nx; ++i) {
                if (deactivate_q9_cell(mask, q9_cell_index(i, j, grid.Nx))) ++changed;
            }
        }
    }
    if (has_y_io_pair(params)) {
        const int w = std::min(n, grid.Ny);
        for (int j = 0; j < w; ++j) {
            for (int i = 0; i < grid.Nx; ++i) {
                if (deactivate_q9_cell(mask, q9_cell_index(i, j, grid.Nx))) ++changed;
            }
        }
        for (int j = std::max(0, grid.Ny - w); j < grid.Ny; ++j) {
            for (int i = 0; i < grid.Nx; ++i) {
                if (deactivate_q9_cell(mask, q9_cell_index(i, j, grid.Nx))) ++changed;
            }
        }
    }
    diag.openBoundaryExcludedCells = changed;
}

void apply_q9_immersed_halo_exclusion(const SimulationParams& params,
                                      const CellGrid& grid,
                                      Q9ProjectionWorkspace& ws,
                                      Q9ProjectionDiagnostics& diag) {
    const int halo = std::max(0, params.q9ImmersedSolidHaloCells);
    if (halo <= 0 || ws.immersedMask.activeCell.empty()) return;

    const int nc = grid.numCells;
    std::vector<std::uint8_t> blocked(static_cast<std::size_t>(nc), 0u);
    for (int c = 0; c < nc; ++c) {
        const std::size_t k = static_cast<std::size_t>(c);
        blocked[k] = ws.immersedMask.activeCell[k] == 0u ? 1u : 0u;
    }

    std::vector<std::uint8_t> next = blocked;
    for (int pass = 0; pass < halo; ++pass) {
        next = blocked;
        for (int j = 0; j < grid.Ny; ++j) {
            for (int i = 0; i < grid.Nx; ++i) {
                const int c = q9_cell_index(i, j, grid.Nx);
                const std::size_t k = static_cast<std::size_t>(c);
                if (blocked[k] != 0u) continue;
                bool nearBlocked = false;
                if (i > 0 && blocked[static_cast<std::size_t>(q9_cell_index(i - 1, j, grid.Nx))] != 0u) nearBlocked = true;
                if (i + 1 < grid.Nx && blocked[static_cast<std::size_t>(q9_cell_index(i + 1, j, grid.Nx))] != 0u) nearBlocked = true;
                if (j > 0 && blocked[static_cast<std::size_t>(q9_cell_index(i, j - 1, grid.Nx))] != 0u) nearBlocked = true;
                if (j + 1 < grid.Ny && blocked[static_cast<std::size_t>(q9_cell_index(i, j + 1, grid.Nx))] != 0u) nearBlocked = true;
                if (nearBlocked) next[k] = 1u;
            }
        }
        blocked.swap(next);
    }

    std::uint64_t changed = 0u;
    for (int c = 0; c < nc; ++c) {
        const std::size_t k = static_cast<std::size_t>(c);
        if (blocked[k] != 0u && ws.immersedMask.activeCell[k] != 0u) {
            if (deactivate_q9_cell(ws.ellipticMask, c)) ++changed;
        }
    }
    diag.immersedHaloExcludedCells = changed;
}

const EllipticProjectionMask* prepare_q9_projection_mask(const SimulationParams& params,
                                                         const CellGrid& grid,
                                                         const FluidDomainBounds& domain,
                                                         double time,
                                                         Q9ProjectionWorkspace& ws,
                                                         Q9ProjectionDiagnostics& diag) {
    const bool hasImmersedMask = params.immersedSolidEnable && params.projectionImmersedSolidMaskEnable;
    const bool hasSafetyMask = q9_safety_mask_requested(params);
    if (!hasImmersedMask && !hasSafetyMask) {
        return nullptr;
    }

    if (hasImmersedMask) {
        ws.immersedMask = build_immersed_solid_projection_mask(
            params, grid, domain, time, params.projectionImmersedSolidFluidFractionThreshold);
        ws.ellipticMask.activeCell = ws.immersedMask.activeCell;
        ws.ellipticMask.activeCells = ws.immersedMask.fluidCells;
        ws.ellipticMask.inactiveCells = ws.immersedMask.solidCells;
        diag.immersedSolidFluidCells = ws.immersedMask.fluidCells;
        diag.immersedSolidSolidCells = ws.immersedMask.solidCells;
        diag.immersedSolidClosedXFaces = ws.immersedMask.closedXFaces;
        diag.immersedSolidClosedYFaces = ws.immersedMask.closedYFaces;
        diag.immersedSolidCellClosedXFaces = ws.immersedMask.cellClosedXFaces;
        diag.immersedSolidCellClosedYFaces = ws.immersedMask.cellClosedYFaces;
        diag.immersedSolidCutClosedXFaces = ws.immersedMask.cutClosedXFaces;
        diag.immersedSolidCutClosedYFaces = ws.immersedMask.cutClosedYFaces;
    } else {
        initialize_all_active_mask(ws.ellipticMask, grid.numCells);
    }

    apply_q9_open_boundary_exclusion(params, grid, ws.ellipticMask, diag);
    apply_q9_immersed_halo_exclusion(params, grid, ws, diag);
    recount_q9_mask(ws.ellipticMask);
    diag.safetyActiveCells = ws.ellipticMask.activeCells;
    diag.safetyExcludedCells = ws.ellipticMask.inactiveCells;
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

bool mask_active(const EllipticProjectionMask* mask, std::size_t k) {
    return !mask || mask->activeCell[k] != 0u;
}

void compute_q9_solid_leak(const PeriodicFaceField& projectedMassFlux,
                           const ImmersedSolidProjectionMask& mask,
                           Q9ProjectionDiagnostics& diag) {
    if (mask.activeCell.empty()) return;
    const std::size_t n = mask.activeCell.size();
    double sum2 = 0.0;
    double maxAbs = 0.0;
    double sum2Cell = 0.0;
    double maxAbsCell = 0.0;
    double sum2Cut = 0.0;
    double maxAbsCut = 0.0;
    std::uint64_t count = 0u;
    std::uint64_t countCell = 0u;
    std::uint64_t countCut = 0u;
#pragma omp parallel for reduction(+:sum2,count,sum2Cell,countCell,sum2Cut,countCut) reduction(max:maxAbs,maxAbsCell,maxAbsCut) if(n > 4096)
    for (std::int64_t ii = 0; ii < static_cast<std::int64_t>(n); ++ii) {
        const std::size_t k = static_cast<std::size_t>(ii);
        if (mask.faceOpen.x[k] == 0.0) {
            const double a = std::abs(projectedMassFlux.x[k]);
            sum2 += a * a;
            maxAbs = std::max(maxAbs, a);
            count += 1u;
            if (!mask.faceClosedByCutX.empty() && mask.faceClosedByCutX[k] != 0u) {
                sum2Cut += a * a;
                maxAbsCut = std::max(maxAbsCut, a);
                countCut += 1u;
            } else {
                sum2Cell += a * a;
                maxAbsCell = std::max(maxAbsCell, a);
                countCell += 1u;
            }
        }
        if (mask.faceOpen.y[k] == 0.0) {
            const double a = std::abs(projectedMassFlux.y[k]);
            sum2 += a * a;
            maxAbs = std::max(maxAbs, a);
            count += 1u;
            if (!mask.faceClosedByCutY.empty() && mask.faceClosedByCutY[k] != 0u) {
                sum2Cut += a * a;
                maxAbsCut = std::max(maxAbsCut, a);
                countCut += 1u;
            } else {
                sum2Cell += a * a;
                maxAbsCell = std::max(maxAbsCell, a);
                countCell += 1u;
            }
        }
    }
    diag.immersedSolidLeakMassFluxRms = count > 0u ? std::sqrt(sum2 / static_cast<double>(count)) : 0.0;
    diag.immersedSolidLeakMassFluxMaxAbs = maxAbs;
    diag.immersedSolidLeakCellClosedMassFluxRms = countCell > 0u ? std::sqrt(sum2Cell / static_cast<double>(countCell)) : 0.0;
    diag.immersedSolidLeakCellClosedMassFluxMaxAbs = maxAbsCell;
    diag.immersedSolidLeakCutMassFluxRms = countCut > 0u ? std::sqrt(sum2Cut / static_cast<double>(countCut)) : 0.0;
    diag.immersedSolidLeakCutMassFluxMaxAbs = maxAbsCut;
}

std::string canonical_filter_name(std::string s) {
    std::transform(s.begin(), s.end(), s.begin(), [](unsigned char ch) {
        return static_cast<char>(std::tolower(ch));
    });
    std::replace(s.begin(), s.end(), '-', '_');
    return s;
}

bool q9_target_filter_is_none(const SimulationParams& params) {
    const std::string f = canonical_filter_name(params.q9TargetFilter);
    return f == "none" || f == "off" || f == "identity" || f == "raw";
}

bool q9_target_filter_is_elliptic_lowpass(const SimulationParams& params) {
    const std::string f = canonical_filter_name(params.q9TargetFilter);
    return f == "elliptic_lowpass" || f == "operator_lowpass" ||
           f == "lowpass_operator" || f == "lowpass_elliptic" ||
           f == "lowk_elliptic";
}

double vector_mean(const std::vector<double>& v, const EllipticProjectionMask* mask = nullptr) {
    if (v.empty()) return 0.0;
    double sum = 0.0;
    std::uint64_t count = 0u;
    const std::size_t n = v.size();
#pragma omp parallel for reduction(+:sum,count) if(n > 4096)
    for (std::int64_t ii = 0; ii < static_cast<std::int64_t>(n); ++ii) {
        const std::size_t k = static_cast<std::size_t>(ii);
        if (!mask_active(mask, k)) continue;
        sum += v[k];
        count += 1u;
    }
    return count > 0u ? sum / static_cast<double>(count) : 0.0;
}

void subtract_vector_mean(std::vector<double>& v, const EllipticProjectionMask* mask = nullptr) {
    const double m = vector_mean(v, mask);
    const std::size_t n = v.size();
#pragma omp parallel for if(n > 4096)
    for (std::int64_t ii = 0; ii < static_cast<std::int64_t>(n); ++ii) {
        const std::size_t k = static_cast<std::size_t>(ii);
        if (mask_active(mask, k)) v[k] -= m;
        else v[k] = 0.0;
    }
}

double vector_rms(const std::vector<double>& v, const EllipticProjectionMask* mask = nullptr) {
    if (v.empty()) return 0.0;
    double sum2 = 0.0;
    std::uint64_t count = 0u;
    const std::size_t n = v.size();
#pragma omp parallel for reduction(+:sum2,count) if(n > 4096)
    for (std::int64_t ii = 0; ii < static_cast<std::int64_t>(n); ++ii) {
        const std::size_t k = static_cast<std::size_t>(ii);
        if (!mask_active(mask, k)) continue;
        const double a = v[k];
        sum2 += a * a;
        count += 1u;
    }
    return count > 0u ? std::sqrt(sum2 / static_cast<double>(count)) : 0.0;
}


EllipticLowPassParams make_q9_lowpass_params(const SimulationParams& params,
                                             const EllipticProjectionGrid& egrid) {
    const int nc = egrid.numCells;
    const double nApprox = std::sqrt(static_cast<double>(std::max(1, nc)));
    const double denom = std::max(1.0, 2.0 * static_cast<double>(params.q9LowKMaxIndex) + 1.0);
    const double lenCells = params.q9EllipticLowPassLengthCells > 0.0
        ? params.q9EllipticLowPassLengthCells
        : std::max(1.0, nApprox / denom);
    const double ell = lenCells * 0.5 * (egrid.dx + egrid.dy);

    EllipticLowPassParams filterParams{};
    filterParams.passes = std::max(0, params.q9EllipticLowPassPasses);
    filterParams.length = ell;
    filterParams.maxIterations = std::max(1, params.projectionMaxIterations);
    filterParams.tolerance = std::max(0.0, params.projectionTolerance);
    filterParams.removeMeanEachPass = true;
    return filterParams;
}

bool q9_lowk_correction_only(const SimulationParams& params) {
    return !q9_target_filter_is_none(params) && params.q9EllipticLowPassPasses != 0;
}

void apply_q9_target_filter(const SimulationParams& params,
                            const EllipticProjectionGrid& egrid,
                            const EllipticProjectionBC& bc,
                            const PeriodicFaceField& alpha,
                            const EllipticProjectionMask* mask,
                            std::vector<double>& target,
                            Q9ProjectionWorkspace& ws,
                            Q9ProjectionDiagnostics& diag) {
    subtract_vector_mean(target, mask);
    diag.targetDivergenceRawRms = vector_rms(target, mask);
    if (q9_target_filter_is_none(params) || params.q9EllipticLowPassPasses == 0) {
        diag.targetDivergenceRms = diag.targetDivergenceRawRms;
        diag.targetDivergenceFilterRatio = 1.0;
        return;
    }
    if (!q9_target_filter_is_elliptic_lowpass(params)) {
        throw std::runtime_error("Unsupported q9TargetFilter in Q9 adapter: " + params.q9TargetFilter);
    }

    const EllipticLowPassParams filterParams = make_q9_lowpass_params(params, egrid);

    EllipticLowPassDiagnostics filterDiag{};
    target = elliptic_lowpass_cell_field(egrid, target, alpha, filterParams, bc, ws.elliptic, &filterDiag, mask);

    diag.targetDivergenceRms = filterDiag.outputRms;
    diag.targetDivergenceFilterRatio = filterDiag.filterRatio;
}

void build_uniform_density_relaxation_target(const SimulationParams& params,
                                             const FluidDomainBounds& domain,
                                             const std::vector<double>& cellMass,
                                             const EllipticProjectionMask* mask,
                                             std::vector<double>& target,
                                             Q9ProjectionDiagnostics& diag) {
    const int nc = static_cast<int>(cellMass.size());
    target.assign(static_cast<std::size_t>(nc), 0.0);
    if (nc <= 0) {
        return;
    }

    double sum = 0.0;
    double sum2 = 0.0;
    std::uint64_t count = 0u;
#pragma omp parallel for reduction(+:sum,sum2,count) if(nc > 4096)
    for (int c = 0; c < nc; ++c) {
        const std::size_t k = static_cast<std::size_t>(c);
        if (!mask_active(mask, k)) continue;
        const double m = cellMass[k];
        sum += m;
        sum2 += m * m;
        count += 1u;
    }
    const double mean = count > 0u ? sum / static_cast<double>(count) : 0.0;
    const double var = count > 0u ? std::max(0.0, sum2 / static_cast<double>(count) - mean * mean) : 0.0;
    diag.densityMean = mean;
    diag.densityStdBefore = std::sqrt(var);

    const double beta = params.q9DensityRelaxationBeta;
    const double invDt = 1.0 / params.dt;
    const double domainRate = active_domain_divergence_rate(domain);
#pragma omp parallel for if(nc > 4096)
    for (int c = 0; c < nc; ++c) {
        const std::size_t k = static_cast<std::size_t>(c);
        // Positive target divergence lowers cell mass in the continuity estimate
        // M_new = M - dt div(J). The uniform moving-domain term preserves the
        // expected mean compression/expansion induced by moving active-domain walls.
        target[k] = mask_active(mask, k) ? (mean * domainRate + beta * invDt * (cellMass[k] - mean)) : 0.0;
    }
    diag.targetDivergenceRawRms = vector_rms(target, mask);
    diag.targetDivergenceRms = diag.targetDivergenceRawRms;
    diag.targetDivergenceFilterRatio = 1.0;
}

double face_strength_for_q9(double requestedStrength,
                            const ImmersedSolidProjectionMask* immersedMask,
                            bool xFace,
                            std::size_t k) {
    if (immersedMask != nullptr && !immersedMask->faceOpen.x.empty()) {
        const double open = xFace ? immersedMask->faceOpen.x[k] : immersedMask->faceOpen.y[k];
        if (open == 0.0) {
            return 1.0;
        }
    }
    return requestedStrength;
}

void correction_flux_to_velocity_kick(const std::vector<double>& cellMass,
                                      const PeriodicFaceField& correctionFlux,
                                      const EllipticProjectionMask* mask,
                                      const ImmersedSolidProjectionMask* immersedMask,
                                      const SimulationParams& params,
                                      std::vector<double>& dux,
                                      std::vector<double>& duy,
                                      PeriodicFaceField& appliedCorrectionFlux,
                                      Q9ProjectionDiagnostics& diag) {
    const int nc = static_cast<int>(cellMass.size());
    dux.assign(static_cast<std::size_t>(nc), 0.0);
    duy.assign(static_cast<std::size_t>(nc), 0.0);
    resize_periodic_face_field(appliedCorrectionFlux, nc);

    const double strength = params.q9MassFluxProjectionStrength;
    const double minMass = std::max(0.0, params.q9MinCellMassForCorrection);
    const double limiter = std::max(0.0, params.q9CorrectionVelocityLimiter);
    diag.minCellMassForCorrection = minMass;
    diag.correctionVelocityLimiter = limiter;

    double rawSum2 = 0.0;
    double appliedSum2 = 0.0;
    double rawMaxAbs = 0.0;
    double appliedMaxAbs = 0.0;
    std::uint64_t activeCount = 0u;
    std::uint64_t lowMass = 0u;
    std::uint64_t limited = 0u;
#pragma omp parallel for reduction(+:rawSum2,appliedSum2,activeCount,lowMass,limited) reduction(max:rawMaxAbs,appliedMaxAbs) if(nc > 4096)
    for (int c = 0; c < nc; ++c) {
        const std::size_t k = static_cast<std::size_t>(c);
        appliedCorrectionFlux.x[k] = 0.0;
        appliedCorrectionFlux.y[k] = 0.0;
        if (!mask_active(mask, k)) {
            continue;
        }
        activeCount += 1u;

        const double sx = face_strength_for_q9(strength, immersedMask, true, k);
        const double sy = face_strength_for_q9(strength, immersedMask, false, k);
        const double dcx = sx * correctionFlux.x[k];
        const double dcy = sy * correctionFlux.y[k];
        if (!(cellMass[k] > minMass)) {
            lowMass += 1u;
            continue;
        }

        double ux = dcx / cellMass[k];
        double uy = dcy / cellMass[k];
        const double rawMag = std::sqrt(ux * ux + uy * uy);
        rawSum2 += ux * ux + uy * uy;
        rawMaxAbs = std::max(rawMaxAbs, rawMag);

        if (limiter > 0.0 && rawMag > limiter) {
            const double scale = limiter / rawMag;
            ux *= scale;
            uy *= scale;
            limited += 1u;
        }

        dux[k] = ux;
        duy[k] = uy;
        appliedCorrectionFlux.x[k] = ux * cellMass[k];
        appliedCorrectionFlux.y[k] = uy * cellMass[k];

        const double appliedMag = std::sqrt(ux * ux + uy * uy);
        appliedSum2 += ux * ux + uy * uy;
        appliedMaxAbs = std::max(appliedMaxAbs, appliedMag);
    }
    diag.lowMassSuppressedCells = lowMass;
    diag.velocityLimitedCells = limited;
    diag.correctionVelocityRawRms = activeCount > 0u ? std::sqrt(rawSum2 / static_cast<double>(activeCount)) : 0.0;
    diag.correctionVelocityRawMaxAbs = rawMaxAbs;
    diag.correctionVelocityRms = activeCount > 0u ? std::sqrt(appliedSum2 / static_cast<double>(activeCount)) : 0.0;
    diag.correctionVelocityMaxAbs = appliedMaxAbs;
}

std::vector<double> build_q9_projection_target(const SimulationParams& params,
                                                const EllipticProjectionGrid& egrid,
                                                const EllipticProjectionBC& bc,
                                                const PeriodicFaceField& baseFlux,
                                                const PeriodicFaceField& alpha,
                                                const EllipticProjectionMask* mask,
                                                const std::vector<double>& densityTarget,
                                                Q9ProjectionWorkspace& ws) {
    if (!q9_lowk_correction_only(params)) {
        return densityTarget;
    }

    const std::vector<double> divBefore = compute_face_divergence(egrid, baseFlux, bc, mask);
    std::vector<double> rhs(divBefore.size(), 0.0);
    const std::size_t n = divBefore.size();
#pragma omp parallel for if(n > 4096)
    for (std::int64_t ii = 0; ii < static_cast<std::int64_t>(n); ++ii) {
        const std::size_t k = static_cast<std::size_t>(ii);
        rhs[k] = densityTarget[k] - divBefore[k];
    }
    subtract_vector_mean(rhs, mask);

    const EllipticLowPassParams filterParams = make_q9_lowpass_params(params, egrid);
    rhs = elliptic_lowpass_cell_field(egrid, rhs, alpha, filterParams, bc, ws.elliptic, nullptr, mask);
    subtract_vector_mean(rhs, mask);

    std::vector<double> projectionTarget(n, 0.0);
#pragma omp parallel for if(n > 4096)
    for (std::int64_t ii = 0; ii < static_cast<std::int64_t>(n); ++ii) {
        const std::size_t k = static_cast<std::size_t>(ii);
        projectionTarget[k] = mask_active(mask, k) ? (divBefore[k] + rhs[k]) : 0.0;
    }
    return projectionTarget;
}

void compute_estimated_density_after(const SimulationParams& params,
                                     const std::vector<double>& cellMass,
                                     const std::vector<double>& divAfter,
                                     const EllipticProjectionMask* mask,
                                     std::vector<double>& massAfter,
                                     Q9ProjectionDiagnostics& diag) {
    const int nc = static_cast<int>(cellMass.size());
    massAfter.assign(static_cast<std::size_t>(nc), 0.0);
    if (nc <= 0) {
        return;
    }
    double sum = 0.0;
    double sum2 = 0.0;
    std::uint64_t count = 0u;
#pragma omp parallel for reduction(+:sum,sum2,count) if(nc > 4096)
    for (int c = 0; c < nc; ++c) {
        const std::size_t k = static_cast<std::size_t>(c);
        const double m = cellMass[k] - params.dt * divAfter[k];
        massAfter[k] = m;
        if (!mask_active(mask, k)) continue;
        sum += m;
        sum2 += m * m;
        count += 1u;
    }
    const double mean = count > 0u ? sum / static_cast<double>(count) : 0.0;
    const double var = count > 0u ? std::max(0.0, sum2 / static_cast<double>(count) - mean * mean) : 0.0;
    diag.densityStdAfterEstimate = std::sqrt(var);
    diag.densityStdRatioEstimate = diag.densityStdBefore > 0.0
        ? diag.densityStdAfterEstimate / diag.densityStdBefore
        : 0.0;
}

void apply_cell_velocity_kick(ParticleState& state,
                              const Q9ProjectionWorkspace& ws,
                              Q9ProjectionDiagnostics& diag,
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

bool q9_projection_requested(const SimulationParams& params) {
    return params.q9MassFluxProjectionEnable || params.method == "q9" || params.method == "q9_virial";
}

Q9ProjectionDiagnostics apply_q9_mass_flux_projection(ParticleState& state,
                                                      const SimulationParams& params,
                                                      const CellGrid& grid,
                                                      const FluidDomainBounds& domain,
                                                      Q9ProjectionWorkspace& workspace) {
    validate_particle_state(state, "apply_q9_mass_flux_projection");

    Q9ProjectionDiagnostics diag{};
    if (!q9_projection_requested(params)) {
        return diag;
    }

    const int nc = grid.numCells;
    const int nt = std::max(1, thread_count());
    resize_q9_workspace(workspace, state.Np, nc, nt);

    deposit_cell_mass_momentum(state, params, grid, domain, workspace, diag);
    build_mass_flux_from_cell_momentum(grid, workspace.cellPx, workspace.cellPy, workspace.baseMassFlux);
    fill_alpha(workspace.alpha, nc, 1.0);
    const EllipticProjectionMask* mask = prepare_q9_projection_mask(
        params, grid, domain, static_cast<double>(0.0), workspace, diag);
    if (mask != nullptr) {
        apply_immersed_face_alpha(workspace.immersedMask, workspace.alpha);
    }
    build_uniform_density_relaxation_target(params, domain, workspace.cellMass, mask, workspace.targetDivergence, diag);

    const EllipticProjectionGrid egrid = make_elliptic_projection_grid(
        params.Nx, params.Ny, fluid_domain_width(domain), fluid_domain_height(domain));
    EllipticProjectionBC bc = q9_bc_from_particle_boundaries(params);
    add_boundary_mass_fluxes_to_q9_bc(bc, params, domain, diag.densityMean, diag);
    apply_q9_target_filter(params, egrid, bc, workspace.alpha, mask, workspace.targetDivergence, workspace, diag);
    const std::vector<double> projectionTarget = build_q9_projection_target(
        params, egrid, bc, workspace.baseMassFlux, workspace.alpha, mask, workspace.targetDivergence, workspace);

    EllipticProjectionParams eparams{};
    eparams.maxIterations = params.projectionMaxIterations;
    eparams.tolerance = params.projectionTolerance;
    eparams.removeRhsMean = true;
    eparams.removePhiMean = true;

    EllipticProjectionResult result = project_face_field(
        egrid, workspace.baseMassFlux, workspace.alpha, projectionTarget, eparams, bc, workspace.elliptic, mask);

    diag.applied = true;
    diag.converged = result.diagnostics.converged;
    diag.iterations = result.diagnostics.iterations;
    diag.residualRel = result.diagnostics.residualRel;
    diag.massFluxDivBeforeRms = result.diagnostics.divBeforeRms;
    diag.massFluxDivBeforeMaxAbs = result.diagnostics.divBeforeMaxAbs;
    diag.massFluxDivAfterRms = result.diagnostics.divAfterRms;
    diag.massFluxDivAfterMaxAbs = result.diagnostics.divAfterMaxAbs;

    correction_flux_to_velocity_kick(workspace.cellMass,
                                     result.correctionFlux,
                                     mask,
                                     params.immersedSolidEnable ? &workspace.immersedMask : nullptr,
                                     params,
                                     workspace.cellDUx,
                                     workspace.cellDUy,
                                     workspace.appliedCorrectionFlux,
                                     diag);

#pragma omp parallel for if(nc > 4096)
    for (int c = 0; c < nc; ++c) {
        const std::size_t k = static_cast<std::size_t>(c);
        workspace.projectedMassFlux.x[k] = workspace.baseMassFlux.x[k] + workspace.appliedCorrectionFlux.x[k];
        workspace.projectedMassFlux.y[k] = workspace.baseMassFlux.y[k] + workspace.appliedCorrectionFlux.y[k];
    }
    const std::vector<double> divApplied = compute_face_divergence(egrid, workspace.projectedMassFlux, bc, mask);
    double div2 = 0.0;
    double divMax = 0.0;
    std::uint64_t divCount = 0u;
#pragma omp parallel for reduction(+:div2,divCount) reduction(max:divMax) if(nc > 4096)
    for (int c = 0; c < nc; ++c) {
        const std::size_t k = static_cast<std::size_t>(c);
        if (!mask_active(mask, k)) continue;
        const double d = divApplied[k];
        div2 += d * d;
        divMax = std::max(divMax, std::abs(d));
        divCount += 1u;
    }
    diag.massFluxDivAfterRms = divCount > 0u ? std::sqrt(div2 / static_cast<double>(divCount)) : 0.0;
    diag.massFluxDivAfterMaxAbs = divMax;
    compute_estimated_density_after(params, workspace.cellMass, divApplied, mask, workspace.massAfterEstimate, diag);

    if (mask != nullptr) {
        compute_q9_solid_leak(workspace.projectedMassFlux, workspace.immersedMask, diag);
    }

    apply_cell_velocity_kick(state, workspace, diag, params.q9MomentumCorrectionEnable);
    return diag;
}

} // namespace mpcd
