#pragma once

#include "immersed_solid.h"
#include "particle_state.h"
#include "simulation_params.h"

#include <cstdint>

namespace mpcd {

struct CudaImmersedCircle0284Diagnostics {
    bool requested = false;
    bool supported = false;
    bool handled = false;
    bool applied = false;
    std::uint64_t particles = 0u;
    std::uint64_t fluidParticles = 0u;
    std::uint64_t hits = 0u;
    std::uint64_t allocationCalls = 0u;
    std::uint64_t uploadCalls = 0u;
    std::uint64_t downloadCalls = 0u;
    double uploadSeconds = 0.0;
    double kernelSeconds = 0.0;
    double downloadSeconds = 0.0;
    double totalSeconds = 0.0;
};

#if defined(MPCD_ENABLE_CUDA_IMMERSED_CIRCLE_0284)

bool cuda_immersed_circle_0284_requested();
bool cuda_immersed_circle_0284_supported(const SimulationParams& params);
CudaImmersedCircle0284Diagnostics try_apply_cuda_immersed_circle_0284(
    ParticleState& state,
    const SimulationParams& params,
    const FluidDomainBounds& domain,
    double time);

#else

inline bool cuda_immersed_circle_0284_requested() { return false; }
inline bool cuda_immersed_circle_0284_supported(const SimulationParams&) { return false; }
inline CudaImmersedCircle0284Diagnostics try_apply_cuda_immersed_circle_0284(
    ParticleState&, const SimulationParams&, const FluidDomainBounds&, double) { return {}; }

#endif

} // namespace mpcd
