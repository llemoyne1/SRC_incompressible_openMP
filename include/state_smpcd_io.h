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

// 0314: compact visualization/diagnostic dumps.  This deliberately writes a
// normal .smpcd V2 file containing only the requested role.  Such dumps are
// useful for analysis and visualization with huge inactive pools, but they are
// not a full restart image of the original particle-capacity reservoir.
void write_smpcd_state_role_filtered(const std::string& filepath,
                                     const ParticleState& state,
                                     std::uint8_t keepRole);

} // namespace mpcd
