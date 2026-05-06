#pragma once

#include <cstdint>
#include <vector>
#include "types.h"

namespace mpcd {

std::vector<int> srd_cell_id_with_random_shift(const std::vector<double>& x,
                                               const Params& params,
                                               std::uint64_t rng_seed);
void srd_collision_step(std::vector<double>& v,
                        const std::vector<int>& cid,
                        const Params& params,
                        std::uint64_t rng_seed);

} // namespace mpcd
