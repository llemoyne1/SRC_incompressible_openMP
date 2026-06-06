#pragma once

#include "boundary_base.h"
#include "fluid_domain.h"
#include "particle_state.h"
#include "simulation_params.h"

#include <cstdint>

namespace mpcd {

struct CudaInletOutletFullface0249aDiagnostics {
    bool requested = false;
    bool supported = false;
    bool handled = false;
    bool applied = false;
    std::uint64_t particles = 0u;
    std::uint64_t fluidParticles = 0u;
    std::uint64_t roleChanges = 0u;
    std::uint64_t hitsLeft = 0u;
    std::uint64_t hitsRight = 0u;
    std::uint64_t hitsBottom = 0u;
    std::uint64_t hitsTop = 0u;
    std::uint64_t inletBackflowDeleted = 0u;
    std::uint64_t outletParticlesDeleted = 0u;
    std::uint64_t allocationCalls = 0u;
    std::uint64_t uploadCalls = 0u;
    std::uint64_t downloadCalls = 0u;
    double uploadSeconds = 0.0;
    double kernelSeconds = 0.0;
    double downloadSeconds = 0.0;
    double totalSeconds = 0.0;
};

#if defined(MPCD_ENABLE_CUDA_INLET_OUTLET_FULLFACE_0249A)

bool cuda_inlet_outlet_fullface_0249a_requested();
bool cuda_inlet_outlet_fullface_0249a_supported(const SimulationParams& params);
CudaInletOutletFullface0249aDiagnostics try_apply_cuda_inlet_outlet_fullface_0249a(
    ParticleState& state,
    const SimulationParams& params,
    const FluidDomainBounds& domain,
    std::uint64_t step,
    double time);

#else

inline bool cuda_inlet_outlet_fullface_0249a_requested() { return false; }
inline bool cuda_inlet_outlet_fullface_0249a_supported(const SimulationParams&) { return false; }
inline CudaInletOutletFullface0249aDiagnostics try_apply_cuda_inlet_outlet_fullface_0249a(
    ParticleState&, const SimulationParams&, const FluidDomainBounds&, std::uint64_t, double) { return {}; }

#endif

inline void merge_cuda_inlet_outlet_fullface_0249a_diagnostics(
    BoundaryDiagnostics& boundary,
    const CudaInletOutletFullface0249aDiagnostics& cudaIo)
{
    if (!cudaIo.handled) return;
    boundary.hitsLeft += cudaIo.hitsLeft;
    boundary.hitsRight += cudaIo.hitsRight;
    boundary.hitsBottom += cudaIo.hitsBottom;
    boundary.hitsTop += cudaIo.hitsTop;
    boundary.inletBackflowDeleted += cudaIo.inletBackflowDeleted;
    boundary.outletParticlesDeleted += cudaIo.outletParticlesDeleted;
    const std::int64_t deleted = static_cast<std::int64_t>(cudaIo.inletBackflowDeleted +
                                                           cudaIo.outletParticlesDeleted);
    boundary.inletNetParticleDelta -= deleted;
}

} // namespace mpcd
