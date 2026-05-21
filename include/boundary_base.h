#pragma once

#include "particle_state.h"
#include "simulation_params.h"

namespace mpcd {

void apply_periodic_boundaries(ParticleState& state, const SimulationParams& params);

} // namespace mpcd
