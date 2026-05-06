#pragma once

#include <string>
#include "types.h"

namespace mpcd {

Params read_params_kv(const std::string& filepath);
void write_runout_kv(const std::string& filepath, const RunOutStep& runout);

} // namespace mpcd
