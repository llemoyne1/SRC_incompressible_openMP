#include "cell_grid.h"

#include <cmath>
#include <stdexcept>

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

} // namespace mpcd
