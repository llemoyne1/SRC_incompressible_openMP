#pragma once

#include <cstdint>
#include <vector>
#include "particle_state.h"
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

    // Hot-loop indexing cache.  These fields are derived once from
    // SimulationParams in make_cell_grid() and are intentionally stored in the
    // grid so that particle-to-cell deposits do not repeatedly query boundary
    // strings or recompute reciprocal cell sizes.
    double invDx = 1.0;
    double invDy = 1.0;
    bool periodicX = false;
    bool periodicY = false;
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

int cell_index_from_position(double x,
                             double y,
                             const CellGrid& grid,
                             const GridShift& shift,
                             const SimulationParams& params);

std::vector<std::uint32_t> compute_cell_counts(const ParticleState& state,
                                               const CellGrid& grid,
                                               const GridShift& shift,
                                               const SimulationParams& params);

} // namespace mpcd
