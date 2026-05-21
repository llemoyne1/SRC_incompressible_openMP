#include "cell_grid.h"

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

double wrap_periodic(double x, double L) {
    x = std::fmod(x, L);
    if (x < 0.0) {
        x += L;
    }
    // Protect against rare roundoff that maps exactly to L.
    if (x >= L) {
        x -= L;
    }
    return x;
}

int omp_thread_count() {
#ifdef _OPENMP
    return omp_get_max_threads();
#else
    return 1;
#endif
}

int omp_thread_id() {
#ifdef _OPENMP
    return omp_get_thread_num();
#else
    return 0;
#endif
}

} // namespace

CellGrid make_cell_grid(const SimulationParams& params) {
    CellGrid grid{};
    grid.Nx = params.Nx;
    grid.Ny = params.Ny;
    grid.numCells = params.Nx * params.Ny;
    grid.Lx = params.Lx;
    grid.Ly = params.Ly;
    grid.dx = params.Lx / static_cast<double>(params.Nx);
    grid.dy = params.Ly / static_cast<double>(params.Ny);
    if (grid.numCells <= 0 || !(grid.dx > 0.0) || !(grid.dy > 0.0)) {
        throw std::runtime_error("Invalid cell grid");
    }
    return grid;
}

int cell_index_periodic(double x, double y, const CellGrid& grid, const GridShift& shift) {
    const double xs = wrap_periodic(x + shift.sx, grid.Lx);
    const double ys = wrap_periodic(y + shift.sy, grid.Ly);

    int ix = static_cast<int>(std::floor(xs / grid.dx));
    int iy = static_cast<int>(std::floor(ys / grid.dy));

    if (ix < 0) ix = 0;
    if (iy < 0) iy = 0;
    if (ix >= grid.Nx) ix = grid.Nx - 1;
    if (iy >= grid.Ny) iy = grid.Ny - 1;

    return ix + grid.Nx * iy;
}

std::vector<std::uint32_t> compute_cell_counts_periodic(const ParticleState& state,
                                                        const CellGrid& grid,
                                                        const GridShift& shift) {
    validate_particle_state(state, "compute_cell_counts_periodic");
    const std::size_t n = static_cast<std::size_t>(state.Np);
    const int nc = grid.numCells;
    if (nc <= 0) {
        throw std::runtime_error("compute_cell_counts_periodic: invalid number of cells");
    }

    const int nt = std::max(1, omp_thread_count());
    std::vector<std::uint32_t> local(static_cast<std::size_t>(nt * nc), 0u);

#pragma omp parallel
    {
        const int tid = omp_thread_id();
        const std::size_t offset = static_cast<std::size_t>(tid * nc);

#pragma omp for
        for (std::int64_t ii = 0; ii < static_cast<std::int64_t>(n); ++ii) {
            const std::size_t i = static_cast<std::size_t>(ii);
            const int c = cell_index_periodic(state.x[i], state.y[i], grid, shift);
            local[offset + static_cast<std::size_t>(c)] += 1u;
        }
    }

    std::vector<std::uint32_t> count(static_cast<std::size_t>(nc), 0u);
#pragma omp parallel for if(nc > 256)
    for (int c = 0; c < nc; ++c) {
        std::uint32_t sum = 0u;
        for (int t = 0; t < nt; ++t) {
            sum += local[static_cast<std::size_t>(t * nc + c)];
        }
        count[static_cast<std::size_t>(c)] = sum;
    }
    return count;
}

} // namespace mpcd
