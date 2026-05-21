#pragma once

#include <cstdint>
#include <vector>
#include "cell_grid.h"
#include "particle_state.h"
#include "simulation_params.h"

namespace mpcd {

struct CollisionDiagnostics {
    GridShift shift;
    std::uint64_t virtualParticleCount = 0;
    double virtualMass = 0.0;
};

struct CollisionWorkspace {
    std::uint64_t allocatedParticles = 0;
    int allocatedCells = 0;
    int allocatedThreads = 0;

    std::vector<int> cellId;

    std::vector<std::uint32_t> cellCount;
    std::vector<double> cellMass;
    std::vector<double> cellUx;
    std::vector<double> cellUy;

    std::vector<std::uint32_t> localCount;
    std::vector<double> localMass;
    std::vector<double> localPx;
    std::vector<double> localPy;

    std::vector<double> cosA;
    std::vector<double> sinA;
};

GridShift sample_grid_shift(const SimulationParams& params, std::uint64_t step);

void resize_collision_workspace(CollisionWorkspace& ws,
                                std::uint64_t numParticles,
                                int numCells,
                                int numThreads);

CollisionDiagnostics src_collision_step(ParticleState& state,
                                        const SimulationParams& params,
                                        const CellGrid& grid,
                                        std::uint64_t step,
                                        CollisionWorkspace& ws);

} // namespace mpcd
