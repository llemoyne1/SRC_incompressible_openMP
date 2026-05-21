#pragma once

#include <cstdint>
#include <vector>
#include "cell_grid.h"
#include "particle_state.h"
#include "simulation_params.h"

namespace mpcd {

struct CollisionDiagnostics {
    GridShift shift;
    std::vector<std::uint32_t> cellCount;
    std::vector<double> cellMass;
    std::vector<double> cellUx;
    std::vector<double> cellUy;
};

GridShift sample_grid_shift(const SimulationParams& params, std::uint64_t step);

CollisionDiagnostics src_collision_step(ParticleState& state,
                                        const SimulationParams& params,
                                        const CellGrid& grid,
                                        std::uint64_t step);

} // namespace mpcd
