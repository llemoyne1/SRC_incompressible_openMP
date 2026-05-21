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

#pragma omp parallel for if(nc > 256)
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
        const std::size_t kk = static_cast<std::size_t>(c);
        ws.cellCount[kk] = count;
        ws.cellMass[kk] = mass;
        if (mass > 0.0) {
            ws.cellUx[kk] = px / mass;
            ws.cellUy[kk] = py / mass;
        }
    }

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
