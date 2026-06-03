#pragma once

#include <string>
#include "particle_state.h"

namespace mpcd {

// Read/write the project binary particle-state format.
//
// V1 legacy payload:
//   x, y, vx, vy, type, mass
//
// V2 resampling-ready payload:
//   x, y, vx, vy, type, mass, role
//
// The reader accepts both versions.  V1 states are normalized by assigning all
// particles the Fluid role.  The writer emits V2 so latent/inactive slots can be
// preserved once the resampling pool is introduced.
ParticleState read_smpcd_state(const std::string& filepath);
void write_smpcd_state(const std::string& filepath, const ParticleState& state);

} // namespace mpcd
