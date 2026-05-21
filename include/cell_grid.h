#pragma once

#include <cstdint>
#include <vector>
#include "simulation_params.h"

namespace mpcd {

struct CellGrid {
    int Nx = 0;
    int Ny = 0;
    int numCells = 0;
    double Lx = 1.0;
    double Ly = 1.0;
    double dx = 1.0;
    double dy = 1.0;
};

struct GridShift {
    double sx = 0.0;
    double sy = 0.0;
};

struct CellMoments {
    std::vector<std::uint32_t> count;
    std::vector<double> mass;
    std::vector<double> ux;
    std::vector<double> uy;
};

CellGrid make_cell_grid(const SimulationParams& params);
int cell_index_periodic(double x, double y, const CellGrid& grid, const GridShift& shift);

} // namespace mpcd
