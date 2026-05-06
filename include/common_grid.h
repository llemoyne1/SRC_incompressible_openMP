#pragma once

#include <vector>
#include "types.h"

namespace mpcd {

int cell_id_from_position(double x, double y, const Params& params);
std::vector<int> build_cell_ids(const std::vector<double>& x, const Params& params);
CellFields compute_cell_fields(const std::vector<double>& x,
                               const std::vector<double>& v,
                               const Params& params,
                               double rhoTargetScalar);

} // namespace mpcd
