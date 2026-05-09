#pragma once

#include <string>
#include "types.h"

namespace mpcd {

bool is_periodic_pair(const Params& params, const std::string& axis_name);

// Projection/reflection fallback for particles found inside an active cylinder.
// This is a discrete end-position correction.
void apply_cylinder_specular_position_bc(std::vector<double>& x,
                                         std::vector<double>& v,
                                         const Params& params);

// Swept specular reflection for segment/circle crossing during streaming.
// xOld is the particle position before streaming; x is the position after streaming.
void apply_cylinder_specular_swept_bc(std::vector<double>& x,
                                      std::vector<double>& v,
                                      const std::vector<double>& xOld,
                                      const Params& params);

void apply_bc_general(std::vector<double>& x,
                      std::vector<double>& v,
                      const Params& params,
                      WallInfo& info,
                      std::uint64_t rng_seed);

} // namespace mpcd
