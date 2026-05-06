#pragma once

#include <string>
#include "types.h"

namespace mpcd {

bool is_periodic_pair(const Params& params, const std::string& axis_name);
void apply_bc_general(std::vector<double>& x,
                      std::vector<double>& v,
                      const Params& params,
                      WallInfo& info,
                      std::uint64_t rng_seed);

} // namespace mpcd
