#pragma once

#include <cstdint>
#include <vector>
#include "cell_grid.h"
#include "fluid_domain.h"
#include "particle_state.h"
#include "simulation_params.h"

namespace mpcd {

struct CollisionDiagnostics {
    GridShift shift;

    // virtualParticleCount is an integer-equivalent diagnostic retained for
    // compatibility. virtualParticleEquivalent is the exact aggregate count
    // used by the deterministic thermal wall model and can be non-integer.
    std::uint64_t virtualParticleCount = 0;
    double virtualParticleEquivalent = 0.0;
    double virtualMass = 0.0;
    double virtualMassLeft = 0.0;
    double virtualMassRight = 0.0;
    double virtualMassBottom = 0.0;
    double virtualMassTop = 0.0;
    double virtualMassImmersed = 0.0;
    double virtualMomentumX = 0.0;
    double virtualMomentumY = 0.0;
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
                                        const FluidDomainBounds& domain,
                                        std::uint64_t step,
                                        CollisionWorkspace& ws);

// 0493x14g: expose the device-resident cellId produced by the most recent
// persistent SRC collision on this thread. The pointer is valid only when the
// requested step and active-particle count match the recorded collision.
// Consumers must treat the pointed array as read-only.
const int* cuda_persistent_src_collision_device_cell_ids_0493x14g(
    std::uint64_t step, std::uint64_t expectedActiveParticles);

} // namespace mpcd
