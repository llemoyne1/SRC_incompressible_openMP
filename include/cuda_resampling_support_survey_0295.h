#pragma once

#include "cell_grid.h"
#include "fluid_domain.h"
#include "particle_state.h"
#include "simulation_params.h"

#include <cstdint>
#include <string>

namespace mpcd {

// 0295: passive, non-mutating post-SRC CUDA survey of the particle support.
// This is not a resampling operator.  It observes the state produced by the
// validated SRC classic step (and by any CPU Q6/virial stage that may be
// re-enabled later), on the physical non-shifted grid used by the CPU
// resampling method.
struct CudaResamplingSupportSurvey0295Diagnostics {
    bool attempted = false;
    bool handled = false;
    bool cudaAvailable = false;
    bool sharedStateFreshBefore = false;
    bool uploadedHostState = false;
    std::uint64_t step = 0u;
    std::string stage;
    std::string outputCsv;

    std::uint64_t particles = 0u;
    std::uint64_t fluidParticles = 0u;
    std::uint64_t cells = 0u;
    std::uint64_t activeCells = 0u;
    std::uint64_t solidCells = 0u;
    std::uint64_t wetCells = 0u;
    std::uint64_t emptyCells = 0u;
    std::uint64_t poorCells = 0u;
    std::uint64_t richCells = 0u;
    std::uint64_t targetBandCells = 0u;

    double totalMass = 0.0;
    double totalPx = 0.0;
    double totalPy = 0.0;
    double meanNActive = 0.0;
    double stdNActive = 0.0;
    double minNWet = 0.0;
    double maxNWet = 0.0;
    double meanMassWet = 0.0;
    double minMassWet = 0.0;
    double maxMassWet = 0.0;
    double massRelRmsWet = 0.0;
    double relativeKineticEnergy = 0.0;
    double kBTWeighted = 0.0;

    double depositUploadSeconds = 0.0;
    double depositKernelSeconds = 0.0;
    double depositDownloadSeconds = 0.0;
    double surveyKernelSeconds = 0.0;
    double surveyDownloadSeconds = 0.0;
    double totalSeconds = 0.0;
};

#if defined(MPCD_ENABLE_CUDA_RESAMPLING) && \
    defined(MPCD_ENABLE_CUDA_PARTICLE_STATE) && \
    defined(MPCD_ENABLE_CUDA_CELL_WORKSPACE) && \
    defined(MPCD_ENABLE_CUDA_CELL_MOMENTS)

bool cuda_resampling_support_survey_0295_requested(std::uint64_t step);

CudaResamplingSupportSurvey0295Diagnostics try_run_cuda_resampling_support_survey_0295(
    const ParticleState& hostMirror,
    const SimulationParams& params,
    const CellGrid& grid,
    const FluidDomainBounds& domain,
    std::uint64_t step,
    double time,
    const char* stage);

#else

inline bool cuda_resampling_support_survey_0295_requested(std::uint64_t) {
    return false;
}

inline CudaResamplingSupportSurvey0295Diagnostics try_run_cuda_resampling_support_survey_0295(
    const ParticleState&,
    const SimulationParams&,
    const CellGrid&,
    const FluidDomainBounds&,
    std::uint64_t,
    double,
    const char*) {
    return CudaResamplingSupportSurvey0295Diagnostics{};
}

#endif

} // namespace mpcd
