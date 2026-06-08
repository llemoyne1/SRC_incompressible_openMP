#pragma once

#include "cell_grid.h"
#include "fluid_domain.h"
#include "particle_state.h"
#include "simulation_params.h"

#include <cstdint>
#include <string>

namespace mpcd {

// 0296: conservative post-SRC CUDA mass reconditioning without support change.
// This is not a population guard: no role changes, no activation, no extraction,
// no particle creation and no particle deletion are allowed here.  The operator
// only smooths particle masses inside already wet physical cells, then restores
// the cell momentum by a uniform velocity correction.
struct CudaResamplingMassRecondition0296Diagnostics {
    bool attempted = false;
    bool handled = false;
    bool cudaAvailable = false;
    bool sharedStateFreshBefore = false;
    bool skippedBecauseStateNotFresh = false;
    std::uint64_t step = 0u;
    std::string stage;
    std::string outputCsv;

    std::uint64_t particles = 0u;
    std::uint64_t fluidParticlesBefore = 0u;
    std::uint64_t fluidParticlesAfter = 0u;
    std::uint64_t cells = 0u;
    std::uint64_t wetCellsBefore = 0u;
    std::uint64_t wetCellsAfter = 0u;
    std::uint64_t appliedParticles = 0u;
    std::uint64_t appliedCells = 0u;

    double strength = 0.0;
    double totalMassBefore = 0.0;
    double totalMassAfter = 0.0;
    double totalPxBefore = 0.0;
    double totalPxAfter = 0.0;
    double totalPyBefore = 0.0;
    double totalPyAfter = 0.0;
    double maxAbsCellMassError = 0.0;
    double maxRelCellMassError = 0.0;
    double maxAbsCellMomentumError = 0.0;
    double maxRelCellMomentumError = 0.0;
    double maxParticleMassRelChange = 0.0;

    double depositBeforeSeconds = 0.0;
    double kernelSeconds = 0.0;
    double depositAfterSeconds = 0.0;
    double downloadSeconds = 0.0;
    double totalSeconds = 0.0;
};

#if defined(MPCD_ENABLE_CUDA_RESAMPLING) && \
    defined(MPCD_ENABLE_CUDA_PARTICLE_STATE) && \
    defined(MPCD_ENABLE_CUDA_CELL_WORKSPACE) && \
    defined(MPCD_ENABLE_CUDA_CELL_MOMENTS)

bool cuda_resampling_mass_recondition_0296_requested(std::uint64_t step);

CudaResamplingMassRecondition0296Diagnostics try_apply_cuda_resampling_mass_recondition_0296(
    ParticleState& hostMirror,
    const SimulationParams& params,
    const CellGrid& grid,
    const FluidDomainBounds& domain,
    std::uint64_t step,
    double time,
    const char* stage);

#else

inline bool cuda_resampling_mass_recondition_0296_requested(std::uint64_t) {
    return false;
}

inline CudaResamplingMassRecondition0296Diagnostics try_apply_cuda_resampling_mass_recondition_0296(
    ParticleState&,
    const SimulationParams&,
    const CellGrid&,
    const FluidDomainBounds&,
    std::uint64_t,
    double,
    const char*) {
    return CudaResamplingMassRecondition0296Diagnostics{};
}

#endif

} // namespace mpcd
