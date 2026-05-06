#pragma once

#include <string>
#include "types.h"

namespace mpcd {

void write_cell_fields_bin(const std::string& filepath, const CellFields& G);

} // namespace mpcd
