#pragma once

#include <cstdint>
#include "particle_state.h"
#include "simulation_params.h"

namespace mpcd {

struct BoundaryDiagnostics {
    std::uint64_t hitsLeft = 0;
    std::uint64_t hitsRight = 0;
    std::uint64_t hitsBottom = 0;
    std::uint64_t hitsTop = 0;
};

BoundaryDiagnostics apply_boundary_conditions(ParticleState& state,
                                              const SimulationParams& params);

} // namespace mpcd
