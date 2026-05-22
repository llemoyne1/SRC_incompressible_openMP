#pragma once

#include <cstdint>
#include "fluid_domain.h"
#include "particle_state.h"
#include "simulation_params.h"

namespace mpcd {

struct BoundaryDiagnostics {
    std::uint64_t hitsLeft = 0;
    std::uint64_t hitsRight = 0;
    std::uint64_t hitsBottom = 0;
    std::uint64_t hitsTop = 0;

    // Maximum number of geometric wall reflections needed by a single
    // particle during one boundary-condition application. These diagnostics
    // are useful for identifying rare high-velocity particles near walls.
    int maxXWallReflectionsPerParticle = 0;
    int maxYWallReflectionsPerParticle = 0;
};

BoundaryDiagnostics apply_boundary_conditions(ParticleState& state,
                                              const SimulationParams& params,
                                              const FluidDomainBounds& domain,
                                              std::uint64_t step = 0u,
                                              double time = 0.0);

} // namespace mpcd
