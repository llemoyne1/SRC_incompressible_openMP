#pragma once

#include "particle_state.h"
#include "simulation_params.h"

#include <cstdint>

namespace mpcd {

struct CudaPistonStreaming0247bDiagnostics {
    bool requested = false;
    bool supported = false;
    bool handled = false;
    bool applied = false;
    std::uint64_t particles = 0u;
    std::uint64_t fluidParticles = 0u;
    std::uint64_t hitsBottom = 0u;
    std::uint64_t hitsTop = 0u;
    int maxYWallReflectionsPerParticle = 0;
    std::uint64_t allocationCalls = 0u;
    std::uint64_t uploadCalls = 0u;
    std::uint64_t downloadCalls = 0u;
    double uploadSeconds = 0.0;
    double kernelSeconds = 0.0;
    double downloadSeconds = 0.0;
    double totalSeconds = 0.0;
};

#if defined(MPCD_ENABLE_CUDA_STREAMING_PISTON_0247B)

bool cuda_piston_streaming_0247b_requested();
bool cuda_piston_streaming_0247b_supported(const SimulationParams& params);
CudaPistonStreaming0247bDiagnostics try_apply_cuda_piston_streaming_0247b(
    ParticleState& state,
    const SimulationParams& params,
    std::uint64_t step);

#else

inline bool cuda_piston_streaming_0247b_requested() { return false; }
inline bool cuda_piston_streaming_0247b_supported(const SimulationParams&) { return false; }
inline CudaPistonStreaming0247bDiagnostics try_apply_cuda_piston_streaming_0247b(
    ParticleState&, const SimulationParams&, std::uint64_t) { return {}; }

#endif

} // namespace mpcd
