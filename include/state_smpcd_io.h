#pragma once

#include <string>
#include "particle_state.h"

namespace mpcd {

// Read/write the project binary particle-state format SRCMPCD_STATE_BIN_V1.
// The file contains only the microscopic particle state: x, y, vx, vy, type,
// mass. It intentionally does not contain domain, grid, time-step, boundary,
// thermostat, projection, EOS, or diagnostic parameters.
ParticleState read_smpcd_state(const std::string& filepath);
void write_smpcd_state(const std::string& filepath, const ParticleState& state);

} // namespace mpcd
