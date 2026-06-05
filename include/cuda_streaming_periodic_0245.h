#pragma once

#include "particle_state.h"
#include "simulation_params.h"

#include <cstdint>

namespace mpcd {

struct CudaPeriodicStreaming0245Diagnostics {
    bool requested = false;
    bool supported = false;
    bool handled = false;
    bool applied = false;
    std::uint64_t particles = 0u;
    std::uint64_t fluidParticles = 0u;
    std::uint64_t allocationCalls = 0u;
    std::uint64_t uploadCalls = 0u;
    std::uint64_t downloadCalls = 0u;
    double uploadSeconds = 0.0;
    double kernelSeconds = 0.0;
    double downloadSeconds = 0.0;
    double totalSeconds = 0.0;
};

#if defined(MPCD_ENABLE_CUDA_STREAMING_0245)

bool cuda_periodic_streaming_0245_requested();
bool cuda_periodic_streaming_0245_supported(const SimulationParams& params);
CudaPeriodicStreaming0245Diagnostics try_apply_cuda_periodic_streaming_0245(
    ParticleState& state,
    const SimulationParams& params,
    std::uint64_t step);

#else

inline bool cuda_periodic_streaming_0245_requested() { return false; }
inline bool cuda_periodic_streaming_0245_supported(const SimulationParams&) { return false; }
inline CudaPeriodicStreaming0245Diagnostics try_apply_cuda_periodic_streaming_0245(
    ParticleState&, const SimulationParams&, std::uint64_t) { return {}; }

#endif

} // namespace mpcd
