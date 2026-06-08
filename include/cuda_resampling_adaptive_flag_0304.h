#pragma once

#include "cell_grid.h"
#include "fluid_domain.h"
#include "particle_state.h"
#include "simulation_params.h"

#include <cstdint>
#include <string>

namespace mpcd {

// 0304: passive post-SRC support-trigger diagnostic.
//
// This module does not run a guard and does not mutate particle state.  It
// deposits the post-SRC/post-thermostat particle state on the physical,
// non-shifted grid and emits a compact device-side flag/counter packet that can
// later be used to trigger an adaptive population guard or empty-cell refill.
struct CudaResamplingAdaptiveFlag0304Diagnostics {
    bool attempted = false;
    bool handled = false;
    bool cudaAvailable = false;
    bool sharedStateFreshBefore = false;
    bool uploadedHostState = false;
    bool authoritativeDeviceState = false;
    bool triggerFlag = false;
    bool triggeredByLowN = false;
    bool triggeredByEmpty = false;

    std::uint64_t step = 0u;
    std::string stage;
    std::string outputCsv;

    std::uint64_t particles = 0u;
    std::uint64_t cells = 0u;
    std::uint64_t activeCells = 0u;
    std::uint64_t wetCells = 0u;
    std::uint64_t emptyWetCells = 0u;
    std::uint64_t lowNCells = 0u;
    std::uint64_t fluidParticles = 0u;

    int triggerNMin = 0;
    int triggerEmpty = 1;
    int minNWet = 0;
    int maxNWet = 0;

    double totalMass = 0.0;
    double totalPx = 0.0;
    double totalPy = 0.0;

    double uploadSeconds = 0.0;
    double depositKernelSeconds = 0.0;
    double flagKernelSeconds = 0.0;
    double downloadSeconds = 0.0;
    double totalSeconds = 0.0;
};

#if defined(MPCD_ENABLE_CUDA_RESAMPLING) && defined(MPCD_ENABLE_CUDA_PARTICLE_STATE)

bool cuda_resampling_adaptive_flag_0304_requested(std::uint64_t step);

CudaResamplingAdaptiveFlag0304Diagnostics try_run_cuda_resampling_adaptive_flag_0304(
    const ParticleState& hostMirror,
    const SimulationParams& params,
    const CellGrid& grid,
    const FluidDomainBounds& domain,
    std::uint64_t step,
    double time,
    const char* stage);

#else

inline bool cuda_resampling_adaptive_flag_0304_requested(std::uint64_t) {
    return false;
}

inline CudaResamplingAdaptiveFlag0304Diagnostics try_run_cuda_resampling_adaptive_flag_0304(
    const ParticleState&,
    const SimulationParams&,
    const CellGrid&,
    const FluidDomainBounds&,
    std::uint64_t,
    double,
    const char*) {
    return CudaResamplingAdaptiveFlag0304Diagnostics{};
}

#endif

} // namespace mpcd
