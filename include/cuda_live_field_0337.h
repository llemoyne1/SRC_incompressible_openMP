#pragma once

#include "src_mpcd_base.h"

#include <cstdint>
#include <string>
#include <vector>

namespace mpcd {

struct CudaLiveQuiver0337 {
    int enabled = 0;
    int rendered = 0;
    int nx = 0;
    int ny = 0;
    std::vector<float> ux;
    std::vector<float> uy;
};

struct CudaLiveField0337Diagnostics {
    int attempted = 0;
    int supported = 0;
    int rendered = 0;
    std::uint64_t particles = 0u;
    std::uint64_t activeFluid = 0u;
    int nx = 0;
    int ny = 0;
    double resetSeconds = 0.0;
    double depositSeconds = 0.0;
    double finalizeSeconds = 0.0;
    double minMaxSeconds = 0.0;
    double downloadSeconds = 0.0;
    double totalSeconds = 0.0;
    int minMaxComputed = 0;
    double fieldMin = 0.0;
    double fieldMax = 0.0;
    double fieldScale = 0.0;
};

bool cuda_live_field_render_shared_0337(std::vector<unsigned char>& rgba,
                                        int nx,
                                        int ny,
                                        const SimulationParams& params,
                                        const std::string& field,
                                        double clip,
                                        double gain,
                                        int smoothPasses,
                                        CudaLiveField0337Diagnostics* diag = nullptr,
                                        CudaLiveQuiver0337* quiver = nullptr);

} // namespace mpcd
