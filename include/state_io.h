#pragma once

#include <string>
#include "types.h"

namespace mpcd {

State read_state(const std::string& x_path,
                 const std::string& v_path,
                 const std::string& type_path,
                 const std::string& r0_path,
                 bool has_type,
                 bool has_r0,
                 int n_expected);

void write_xy_interleaved(const std::string& filepath, const std::vector<double>& data, int n_expected);
void write_u8(const std::string& filepath, const std::vector<std::uint8_t>& data, int n_expected);

} // namespace mpcd
