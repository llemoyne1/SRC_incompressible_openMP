#pragma once

#include "boundary_base.h"
#include "fluid_domain.h"
#include "particle_state.h"
#include "simulation_params.h"

#include <cstdint>

namespace mpcd {

struct CudaClassicSrcIoResident0263Diagnostics {
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
    BoundaryDiagnostics boundary{};
};

#if defined(MPCD_ENABLE_CUDA_CLASSIC_SRC_IO_RESIDENT_0263)

bool cuda_classic_src_io_fullface_resident_0263_requested();
bool cuda_classic_src_io_fullface_resident_0263_supported(const SimulationParams& params);
bool cuda_classic_src_io_segmented_resident_0264_requested();
bool cuda_classic_src_io_segmented_resident_0264_supported(const SimulationParams& params);
CudaClassicSrcIoResident0263Diagnostics try_apply_cuda_classic_src_io_fullface_stream_0263(
    ParticleState& state,
    const SimulationParams& params,
    const FluidDomainBounds& domain,
    std::uint64_t step);
CudaClassicSrcIoResident0263Diagnostics try_apply_cuda_classic_src_io_fullface_boundary_0263(
    ParticleState& state,
    const SimulationParams& params,
    const FluidDomainBounds& domain,
    std::uint64_t step,
    double time);
CudaClassicSrcIoResident0263Diagnostics try_apply_cuda_classic_src_io_segmented_stream_0264(
    ParticleState& state,
    const SimulationParams& params,
    const FluidDomainBounds& domain,
    std::uint64_t step);
CudaClassicSrcIoResident0263Diagnostics try_apply_cuda_classic_src_io_segmented_boundary_0264(
    ParticleState& state,
    const SimulationParams& params,
    const FluidDomainBounds& domain,
    std::uint64_t step,
    double time);

#else

inline bool cuda_classic_src_io_fullface_resident_0263_requested() { return false; }
inline bool cuda_classic_src_io_fullface_resident_0263_supported(const SimulationParams&) { return false; }
inline bool cuda_classic_src_io_segmented_resident_0264_requested() { return false; }
inline bool cuda_classic_src_io_segmented_resident_0264_supported(const SimulationParams&) { return false; }
inline CudaClassicSrcIoResident0263Diagnostics try_apply_cuda_classic_src_io_fullface_stream_0263(
    ParticleState&, const SimulationParams&, const FluidDomainBounds&, std::uint64_t) { return {}; }
inline CudaClassicSrcIoResident0263Diagnostics try_apply_cuda_classic_src_io_fullface_boundary_0263(
    ParticleState&, const SimulationParams&, const FluidDomainBounds&, std::uint64_t, double) { return {}; }
inline CudaClassicSrcIoResident0263Diagnostics try_apply_cuda_classic_src_io_segmented_stream_0264(
    ParticleState&, const SimulationParams&, const FluidDomainBounds&, std::uint64_t) { return {}; }
inline CudaClassicSrcIoResident0263Diagnostics try_apply_cuda_classic_src_io_segmented_boundary_0264(
    ParticleState&, const SimulationParams&, const FluidDomainBounds&, std::uint64_t, double) { return {}; }

#endif

} // namespace mpcd
