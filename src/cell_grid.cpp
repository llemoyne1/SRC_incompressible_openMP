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

double wrap_periodic_legacy(double x, double L) {
    x = std::fmod(x, L);
    if (x < 0.0) {
        x += L;
    }
    if (x >= L) {
        x -= L;
    }
    return x;
}

// Fast path for the normal MPCD use case: particles are already kept in the
// numerical box by boundary handling and the grid shift is bounded by one cell.
// Thus x+shift can cross a periodic boundary by at most one box length.  Keep a
// conservative fmod fallback for unusual restart/debug states.
double wrap_periodic_fast(double x, double L) {
    if (x >= 0.0 && x < L) {
        return x;
    }
    if (x < 0.0 && x >= -L) {
        x += L;
        if (x >= L) x -= L;
        return x;
    }
    if (x >= L && x < 2.0 * L) {
        x -= L;
        if (x < 0.0) x += L;
        return x;
    }
    return wrap_periodic_legacy(x, L);
}

int bounded_cell_index_legacy(double xs, double L, double dx, int N) {
    xs = std::clamp(xs, 0.0, L);
    int i = static_cast<int>(std::floor(xs / dx));
    if (i < 0) i = 0;
    if (i >= N) i = N - 1;
    return i;
}

int periodic_cell_index_legacy(double xs, double L, double dx, int N) {
    xs = wrap_periodic_legacy(xs, L);
    int i = static_cast<int>(std::floor(xs / dx));
    if (i < 0) i = 0;
    if (i >= N) i = N - 1;
    return i;
}

int bounded_cell_index_fast(double xs, double L, double invDx, int N) {
    xs = std::clamp(xs, 0.0, L);
    int i = static_cast<int>(xs * invDx);
    if (i < 0) i = 0;
    if (i >= N) i = N - 1;
    return i;
}

int periodic_cell_index_fast(double xs, double L, double invDx, int N) {
    xs = wrap_periodic_fast(xs, L);
    int i = static_cast<int>(xs * invDx);
    if (i < 0) i = 0;
    if (i >= N) i = N - 1;
    return i;
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
    grid.invDx = 1.0 / grid.dx;
    grid.invDy = 1.0 / grid.dy;
    grid.periodicX = is_x_periodic(params);
    grid.periodicY = is_y_periodic(params);
    return grid;
}

int cell_index_from_position(double x,
                             double y,
                             const CellGrid& grid,
                             const GridShift& shift,
                             const SimulationParams& params) {
    const double xs = x + shift.sx;
    const double ys = y + shift.sy;

#ifdef MPCD_DISABLE_FAST_CELL_INDEX
    const int ix = is_x_periodic(params)
        ? periodic_cell_index_legacy(xs, grid.Lx, grid.dx, grid.Nx)
        : bounded_cell_index_legacy(xs, grid.Lx, grid.dx, grid.Nx);
    const int iy = is_y_periodic(params)
        ? periodic_cell_index_legacy(ys, grid.Ly, grid.dy, grid.Ny)
        : bounded_cell_index_legacy(ys, grid.Ly, grid.dy, grid.Ny);
#else
    (void)params;
    const int ix = grid.periodicX
        ? periodic_cell_index_fast(xs, grid.Lx, grid.invDx, grid.Nx)
        : bounded_cell_index_fast(xs, grid.Lx, grid.invDx, grid.Nx);
    const int iy = grid.periodicY
        ? periodic_cell_index_fast(ys, grid.Ly, grid.invDy, grid.Ny)
        : bounded_cell_index_fast(ys, grid.Ly, grid.invDy, grid.Ny);
#endif

    return ix + grid.Nx * iy;
}

std::vector<std::uint32_t> compute_cell_counts(const ParticleState& state,
                                               const CellGrid& grid,
                                               const GridShift& shift,
                                               const SimulationParams& params) {
    validate_particle_state(state, "compute_cell_counts");
    const std::size_t n = static_cast<std::size_t>(state.Np);
    const int nc = grid.numCells;
    if (nc <= 0) {
        throw std::runtime_error("compute_cell_counts: invalid number of cells");
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
            if (!is_fluid_particle(state, i)) {
                continue;
            }
            const int c = cell_index_from_position(state.x[i], state.y[i], grid, shift, params);
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
