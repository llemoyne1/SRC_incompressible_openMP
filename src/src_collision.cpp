#include "src_collision.h"

#include <cmath>
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

CollisionDiagnostics src_collision_step(ParticleState& state,
                                        const SimulationParams& params,
                                        const CellGrid& grid,
                                        std::uint64_t step) {
    validate_particle_state(state, "src_collision_step");

    const std::size_t n = static_cast<std::size_t>(state.Np);
    const int nc = grid.numCells;
    if (nc <= 0) {
        throw std::runtime_error("src_collision_step: invalid number of cells");
    }

    CollisionDiagnostics diag{};
    diag.shift = sample_grid_shift(params, step);
    diag.cellCount.assign(static_cast<std::size_t>(nc), 0u);
    diag.cellMass.assign(static_cast<std::size_t>(nc), 0.0);
    diag.cellUx.assign(static_cast<std::size_t>(nc), 0.0);
    diag.cellUy.assign(static_cast<std::size_t>(nc), 0.0);

    std::vector<int> cid(n, 0);

    const int nt = thread_count();
    std::vector<std::uint32_t> localCount(static_cast<std::size_t>(nt * nc), 0u);
    std::vector<double> localMass(static_cast<std::size_t>(nt * nc), 0.0);
    std::vector<double> localPx(static_cast<std::size_t>(nt * nc), 0.0);
    std::vector<double> localPy(static_cast<std::size_t>(nt * nc), 0.0);

    #pragma omp parallel
    {
        const int tid = thread_id();
        const std::size_t offset = static_cast<std::size_t>(tid * nc);

        #pragma omp for
        for (std::int64_t ii = 0; ii < static_cast<std::int64_t>(n); ++ii) {
            const std::size_t i = static_cast<std::size_t>(ii);
            const int c = cell_index_periodic(state.x[i], state.y[i], grid, diag.shift);
            cid[i] = c;
            const std::size_t k = offset + static_cast<std::size_t>(c);
            const double m = state.mass[i];
            localCount[k] += 1u;
            localMass[k] += m;
            localPx[k] += m * state.vx[i];
            localPy[k] += m * state.vy[i];
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
            count += localCount[k];
            mass += localMass[k];
            px += localPx[k];
            py += localPy[k];
        }
        diag.cellCount[static_cast<std::size_t>(c)] = count;
        diag.cellMass[static_cast<std::size_t>(c)] = mass;
        if (mass > 0.0) {
            diag.cellUx[static_cast<std::size_t>(c)] = px / mass;
            diag.cellUy[static_cast<std::size_t>(c)] = py / mass;
        }
    }

    std::vector<double> cosA(static_cast<std::size_t>(nc), std::cos(params.rotationAngle));
    std::vector<double> sinA(static_cast<std::size_t>(nc), std::sin(params.rotationAngle));
    if (params.randomRotationSign) {
        #pragma omp parallel for if(nc > 256)
        for (int c = 0; c < nc; ++c) {
            const std::uint64_t h = splitmix64(params.rngSeed ^ (step * 0x9e3779b97f4a7c15ULL) ^ static_cast<std::uint64_t>(c));
            if ((h & 1ULL) == 0ULL) {
                sinA[static_cast<std::size_t>(c)] = -sinA[static_cast<std::size_t>(c)];
            }
        }
    }

    #pragma omp parallel for if(n > 10000)
    for (std::int64_t ii = 0; ii < static_cast<std::int64_t>(n); ++ii) {
        const std::size_t i = static_cast<std::size_t>(ii);
        const int c = cid[i];
        const std::size_t k = static_cast<std::size_t>(c);
        const double ux = diag.cellUx[k];
        const double uy = diag.cellUy[k];
        const double dvx = state.vx[i] - ux;
        const double dvy = state.vy[i] - uy;
        const double ca = cosA[k];
        const double sa = sinA[k];
        state.vx[i] = ux + ca * dvx - sa * dvy;
        state.vy[i] = uy + sa * dvx + ca * dvy;
    }

    return diag;
}

} // namespace mpcd
