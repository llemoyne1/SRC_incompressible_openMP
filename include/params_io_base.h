#pragma once

#include <string>
#include "simulation_params.h"

namespace mpcd {

// Read a small key-value parameter file for the generic periodic SRC/MPCD base executable.
// Supported syntaxes are:
//   key = value
//   key value
// Lines starting with # and empty lines are ignored. Inline comments after # are removed.
SimulationParams read_simulation_params_kv(const std::string& filepath);

} // namespace mpcd
