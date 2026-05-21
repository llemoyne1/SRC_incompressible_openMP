#include "src_collision.h"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <random>
#include <stdexcept>

#ifdef _OPENMP
#include <omp.h>
#endif

namespace mpcd {
namespace {

std::uint64_t splitmix64(std::uint64_t x) {
    x += 0x9e3779b97f4a7c15ULL;
    x = (x ^ (x >> 30U)) * 0xbf58476d1ce4e5b9ULL;
    x = (x ^ (x >> 27U)) * 0x94d049bb133111ebULL;
    return x ^ (x >> 31U);
}

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

double overlap_length(double a0, double a1, double b0, double b1) {
    const double lo = std::max(a0, b0);
    const double hi = std::min(a1, b1);
    return hi > lo ? hi - lo : 0.0;
}

double face_area_left(int ix, int iy, const CellGrid& grid, const GridShift& shift, const SimulationParams& params) {
    if (is_x_periodic(params)) return 0.0;
    const double x0 = static_cast<double>(ix) * grid.dx - shift.sx;
    const double x1 = x0 + grid.dx;
    const double y0 = static_cast<double>(iy) * grid.dy - shift.sy;
    const double y1 = y0 + grid.dy;
    const double outsideX = overlap_length(x0, x1, -grid.dx, 0.0);
    const double insideY = is_y_periodic(params) ? grid.dy : overlap_length(y0, y1, 0.0, grid.Ly);
    return outsideX * insideY;
}

double face_area_right(int ix, int iy, const CellGrid& grid, const GridShift& shift, const SimulationParams& params) {
    if (is_x_periodic(params)) return 0.0;
    const double x0 = static_cast<double>(ix) * grid.dx - shift.sx;
    const double x1 = x0 + grid.dx;
    const double y0 = static_cast<double>(iy) * grid.dy - shift.sy;
    const double y1 = y0 + grid.dy;
    const double outsideX = overlap_length(x0, x1, grid.Lx, grid.Lx + grid.dx);
    const double insideY = is_y_periodic(params) ? grid.dy : overlap_length(y0, y1, 0.0, grid.Ly);
    return outsideX * insideY;
}

double face_area_bottom(int ix, int iy, const CellGrid& grid, const GridShift& shift, const SimulationParams& params) {
    if (is_y_periodic(params)) return 0.0;
    const double x0 = static_cast<double>(ix) * grid.dx - shift.sx;
    const double x1 = x0 + grid.dx;
    const double y0 = static_cast<double>(iy) * grid.dy - shift.sy;
    const double y1 = y0 + grid.dy;
    const double insideX = is_x_periodic(params) ? grid.dx : overlap_length(x0, x1, 0.0, grid.Lx);
    const double outsideY = overlap_length(y0, y1, -grid.dy, 0.0);
    return insideX * outsideY;
}

double face_area_top(int ix, int iy, const CellGrid& grid, const GridShift& shift, const SimulationParams& params) {
    if (is_y_periodic(params)) return 0.0;
    const double x0 = static_cast<double>(ix) * grid.dx - shift.sx;
    const double x1 = x0 + grid.dx;
    const double y0 = static_cast<double>(iy) * grid.dy - shift.sy;
    const double y1 = y0 + grid.dy;
    const double insideX = is_x_periodic(params) ? grid.dx : overlap_length(x0, x1, 0.0, grid.Lx);
    const double outsideY = overlap_length(y0, y1, grid.Ly, grid.Ly + grid.dy);
    return insideX * outsideY;
}

void add_virtual_face_momentum(double faceArea,
                               double fullCellArea,
                               double gamma,
                               double vpMass,
                               double kBT,
                               double wallUx,
                               double wallUy,
                               std::uint64_t seed,
                               double& mass,
                               double& px,
                               double& py,
                               std::uint64_t& vpCount,
                               double& vpMassTotal) {
    if (!(faceArea > 0.0)) return;
    const double lambda = gamma * faceArea / fullCellArea;
    if (!(lambda > 0.0)) return;

    std::mt19937_64 rng(seed);
    std::poisson_distribution<int> poisson(lambda);
    const int nv = poisson(rng);
    if (nv <= 0) return;

    const double nvD = static_cast<double>(nv);
    const double mTot = nvD * vpMass;
    const double sigmaP = std::sqrt(nvD * vpMass * kBT);
    std::normal_distribution<double> normal(0.0, 1.0);

    mass += mTot;
    px += mTot * wallUx + sigmaP * normal(rng);
    py += mTot * wallUy + sigmaP * normal(rng);
    vpCount += static_cast<std::uint64_t>(nv);
    vpMassTotal += mTot;
}

} // namespace

GridShift sample_grid_shift(const SimulationParams& params, std::uint64_t step) {
    GridShift shift{};
    if (!params.gridShiftEnable) {
        return shift;
    }

    std::mt19937_64 rng(params.rngSeed ^ splitmix64(step));
    std::uniform_real_distribution<double> ux(-0.5 * params.Lx / static_cast<double>(params.Nx),
                                               0.5 * params.Lx / static_cast<double>(params.Nx));
    std::uniform_real_distribution<double> uy(-0.5 * params.Ly / static_cast<double>(params.Ny),
                                               0.5 * params.Ly / static_cast<double>(params.Ny));
    shift.sx = ux(rng);
    shift.sy = uy(rng);
    return shift;
}

void resize_collision_workspace(CollisionWorkspace& ws,
                                std::uint64_t numParticles,
                                int numCells,
                                int numThreads) {
    if (numCells <= 0) {
        throw std::runtime_error("resize_collision_workspace: invalid number of cells");
    }
    if (numThreads <= 0) {
        numThreads = 1;
    }

    const bool sameSize = ws.allocatedParticles == numParticles &&
                          ws.allocatedCells == numCells &&
                          ws.allocatedThreads == numThreads;
    if (!sameSize) {
        ws.allocatedParticles = numParticles;
        ws.allocatedCells = numCells;
        ws.allocatedThreads = numThreads;

        ws.cellId.assign(static_cast<std::size_t>(numParticles), 0);

        ws.cellCount.assign(static_cast<std::size_t>(numCells), 0u);
        ws.cellMass.assign(static_cast<std::size_t>(numCells), 0.0);
        ws.cellUx.assign(static_cast<std::size_t>(numCells), 0.0);
        ws.cellUy.assign(static_cast<std::size_t>(numCells), 0.0);

        const std::size_t localSize = static_cast<std::size_t>(numThreads * numCells);
        ws.localCount.assign(localSize, 0u);
        ws.localMass.assign(localSize, 0.0);
        ws.localPx.assign(localSize, 0.0);
        ws.localPy.assign(localSize, 0.0);

        ws.cosA.assign(static_cast<std::size_t>(numCells), 1.0);
        ws.sinA.assign(static_cast<std::size_t>(numCells), 0.0);
    }
}

CollisionDiagnostics src_collision_step(ParticleState& state,
                                        const SimulationParams& params,
                                        const CellGrid& grid,
                                        std::uint64_t step,
                                        CollisionWorkspace& ws) {
    validate_particle_state(state, "src_collision_step");

    const std::size_t n = static_cast<std::size_t>(state.Np);
    const int nc = grid.numCells;
    if (nc <= 0) {
        throw std::runtime_error("src_collision_step: invalid number of cells");
    }

    const int nt = std::max(1, thread_count());
    resize_collision_workspace(ws, state.Np, nc, nt);

    CollisionDiagnostics diag{};
    diag.shift = sample_grid_shift(params, step);

    std::fill(ws.cellCount.begin(), ws.cellCount.end(), 0u);
    std::fill(ws.cellMass.begin(), ws.cellMass.end(), 0.0);
    std::fill(ws.cellUx.begin(), ws.cellUx.end(), 0.0);
    std::fill(ws.cellUy.begin(), ws.cellUy.end(), 0.0);
    std::fill(ws.localCount.begin(), ws.localCount.end(), 0u);
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
            const int c = cell_index_from_position(state.x[i], state.y[i], grid, diag.shift, params);
            ws.cellId[i] = c;
            const std::size_t k = offset + static_cast<std::size_t>(c);
            const double m = state.mass[i];
            ws.localCount[k] += 1u;
            ws.localMass[k] += m;
            ws.localPx[k] += m * state.vx[i];
            ws.localPy[k] += m * state.vy[i];
        }
    }

    const double inferredGamma = static_cast<double>(n) / static_cast<double>(nc);
    const double wallVpGamma = params.wallVpGamma > 0.0 ? params.wallVpGamma : inferredGamma;
    const double wallVpKBT = params.wallVpKBT > 0.0 ? params.wallVpKBT : params.kBT;
    const double fullCellArea = grid.dx * grid.dy;
    std::uint64_t vpCountSum = 0u;
    double vpMassSum = 0.0;

#pragma omp parallel for reduction(+:vpCountSum,vpMassSum) if(nc > 256)
    for (int c = 0; c < nc; ++c) {
        std::uint32_t count = 0u;
        double mass = 0.0;
        double px = 0.0;
        double py = 0.0;
        for (int t = 0; t < nt; ++t) {
            const std::size_t k = static_cast<std::size_t>(t * nc + c);
            count += ws.localCount[k];
            mass += ws.localMass[k];
            px += ws.localPx[k];
            py += ws.localPy[k];
        }

        if (params.wallVpEnable) {
            const int ix = c % grid.Nx;
            const int iy = c / grid.Nx;
            std::uint64_t cellVpCount = 0u;
            double cellVpMass = 0.0;

            add_virtual_face_momentum(face_area_left(ix, iy, grid, diag.shift, params),
                                      fullCellArea,
                                      wallVpGamma,
                                      params.wallVpMass,
                                      wallVpKBT,
                                      params.wallVpUxLeft,
                                      params.wallVpUyLeft,
                                      splitmix64(params.rngSeed ^ (step * 0x9e3779b97f4a7c15ULL) ^
                                                 (static_cast<std::uint64_t>(c) * 0xbf58476d1ce4e5b9ULL) ^
                                                 0x4c454654ULL),
                                      mass,
                                      px,
                                      py,
                                      cellVpCount,
                                      cellVpMass);
            add_virtual_face_momentum(face_area_right(ix, iy, grid, diag.shift, params),
                                      fullCellArea,
                                      wallVpGamma,
                                      params.wallVpMass,
                                      wallVpKBT,
                                      params.wallVpUxRight,
                                      params.wallVpUyRight,
                                      splitmix64(params.rngSeed ^ (step * 0x9e3779b97f4a7c15ULL) ^
                                                 (static_cast<std::uint64_t>(c) * 0xbf58476d1ce4e5b9ULL) ^
                                                 0x5249474854ULL),
                                      mass,
                                      px,
                                      py,
                                      cellVpCount,
                                      cellVpMass);
            add_virtual_face_momentum(face_area_bottom(ix, iy, grid, diag.shift, params),
                                      fullCellArea,
                                      wallVpGamma,
                                      params.wallVpMass,
                                      wallVpKBT,
                                      params.wallVpUxBottom,
                                      params.wallVpUyBottom,
                                      splitmix64(params.rngSeed ^ (step * 0x9e3779b97f4a7c15ULL) ^
                                                 (static_cast<std::uint64_t>(c) * 0xbf58476d1ce4e5b9ULL) ^
                                                 0x424f54544f4dULL),
                                      mass,
                                      px,
                                      py,
                                      cellVpCount,
                                      cellVpMass);
            add_virtual_face_momentum(face_area_top(ix, iy, grid, diag.shift, params),
                                      fullCellArea,
                                      wallVpGamma,
                                      params.wallVpMass,
                                      wallVpKBT,
                                      params.wallVpUxTop,
                                      params.wallVpUyTop,
                                      splitmix64(params.rngSeed ^ (step * 0x9e3779b97f4a7c15ULL) ^
                                                 (static_cast<std::uint64_t>(c) * 0xbf58476d1ce4e5b9ULL) ^
                                                 0x544f50ULL),
                                      mass,
                                      px,
                                      py,
                                      cellVpCount,
                                      cellVpMass);
            vpCountSum += cellVpCount;
            vpMassSum += cellVpMass;
        }

        const std::size_t kk = static_cast<std::size_t>(c);
        ws.cellCount[kk] = count; // real-particle occupancy only; VP diagnostics are separate.
        ws.cellMass[kk] = mass;
        if (mass > 0.0) {
            ws.cellUx[kk] = px / mass;
            ws.cellUy[kk] = py / mass;
        }
    }
    diag.virtualParticleCount = vpCountSum;
    diag.virtualMass = vpMassSum;

    const double ca0 = std::cos(params.rotationAngle);
    const double sa0 = std::sin(params.rotationAngle);
#pragma omp parallel for if(nc > 256)
    for (int c = 0; c < nc; ++c) {
        const std::size_t k = static_cast<std::size_t>(c);
        ws.cosA[k] = ca0;
        double sa = sa0;
        if (params.randomRotationSign) {
            const std::uint64_t h = splitmix64(params.rngSeed ^
                                               (step * 0x9e3779b97f4a7c15ULL) ^
                                               static_cast<std::uint64_t>(c));
            if ((h & 1ULL) == 0ULL) {
                sa = -sa;
            }
        }
        ws.sinA[k] = sa;
    }

#pragma omp parallel for if(n > 10000)
    for (std::int64_t ii = 0; ii < static_cast<std::int64_t>(n); ++ii) {
        const std::size_t i = static_cast<std::size_t>(ii);
        const int c = ws.cellId[i];
        const std::size_t k = static_cast<std::size_t>(c);
        const double ux = ws.cellUx[k];
        const double uy = ws.cellUy[k];
        const double dvx = state.vx[i] - ux;
        const double dvy = state.vy[i] - uy;
        const double ca = ws.cosA[k];
        const double sa = ws.sinA[k];
        state.vx[i] = ux + ca * dvx - sa * dvy;
        state.vy[i] = uy + sa * dvx + ca * dvy;
    }

    return diag;
}

} // namespace mpcd
