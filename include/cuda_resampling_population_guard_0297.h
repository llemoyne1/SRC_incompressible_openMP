#pragma once

#include "cell_grid.h"
#include "fluid_domain.h"
#include "particle_state.h"
#include "simulation_params.h"

#include <cstdint>
#include <string>

namespace mpcd {

// 0297: minimal local post-SRC CUDA population guard.
//
// This is the first support-changing CUDA resampling brick.  It is deliberately
// local and conservative:
//   - poor wet cells can receive at most one local split per application;
//   - rich cells can undergo at most one local merge per application;
//   - no long-distance transfer plan is built;
//   - no Q6 CUDA is introduced;
//   - mass and momentum are conserved by construction for each local split/merge
//     up to floating-point roundoff.
struct CudaResamplingPopulationGuard0297Diagnostics {
    bool attempted = false;
    bool handled = false;
    bool cudaAvailable = false;
    bool sharedStateFreshBefore = false;
    bool skippedBecauseStateNotFresh = false;
    std::uint64_t step = 0u;
    std::string stage;
    std::string outputCsv;

    std::uint64_t particles = 0u;
    std::uint64_t cells = 0u;
    std::uint64_t fluidParticlesBefore = 0u;
    std::uint64_t fluidParticlesAfter = 0u;
    std::uint64_t inactiveParticlesBefore = 0u;
    std::uint64_t inactiveParticlesAfter = 0u;
    std::uint64_t wetCellsBefore = 0u;
    std::uint64_t wetCellsAfter = 0u;
    std::uint64_t poorCells = 0u;
    std::uint64_t richCells = 0u;
    std::uint64_t mergeApplied = 0u;
    std::uint64_t splitApplied = 0u;
    std::uint64_t splitSkippedNoInactive = 0u;
    std::uint64_t splitSkippedNoDonor = 0u;
    std::uint64_t mergeSkippedNoPair = 0u;

    int nMin = 0;
    int nTarget = 0;
    int nMax = 0;
    double splitFraction = 0.5;
    double minDonorMassAfterSplit = 1.0e-12;

    // 0307: split-cascade diagnostics and optional prevention.  The default
    // behavior is diagnostic-only unless MPCD_CUDA_RESAMPLING_SPLIT_SAFETY_0307
    // is enabled.  The goal is to detect and optionally prevent repeated local
    // splitting from generating nearly massless representative particles,
    // especially in solid-adjacent cells.
    bool splitSafety0307 = false;
    bool preferMaxMassDonor0307 = false;
    double splitDonorMinMass0307 = 0.0;
    double splitNewParticleMinMass0307 = 0.0;
    double solidAdjacentDonorMinMass0307 = 0.0;
    int solidAdjacentSplitMode0307 = 0; // 0 normal, 1 cautious, 2 off.
    int solidAdjacentHaloCells0307 = 1;
    double tinyMassThreshold0307 = 0.25;

    bool chiFilterEnable = false;
    double chiMin = 0.0;
    std::uint64_t excludedChiCells = 0u;

    std::uint64_t splitCandidatesSolidAdjacent0307 = 0u;
    std::uint64_t splitAppliedSolidAdjacent0307 = 0u;
    std::uint64_t splitSkippedDonorMass0307 = 0u;
    std::uint64_t splitSkippedNewMass0307 = 0u;
    std::uint64_t splitSkippedSolidAdjacent0307 = 0u;
    std::uint64_t splitFromMassBelow0p5_0307 = 0u;
    std::uint64_t splitFromMassBelow0p25_0307 = 0u;
    std::uint64_t splitFromMassBelow0p1_0307 = 0u;
    double minSplitDonorMass0307 = 0.0;
    double minSplitNewParticleMass0307 = 0.0;
    double minPostSplitDonorMass0307 = 0.0;

    bool emptyRefillEnable0319 = false;
    int emptyRefillTarget0319 = 0;
    double emptyRefillTargetFraction0319 = 0.0;
    std::string emptyRefillReference0319;
    int emptyRefillMemoryMaxAge0319 = 0;
    std::uint64_t emptyRefillMemoryUpdates0319 = 0u;
    std::uint64_t emptyRefillCandidates0319 = 0u;
    std::uint64_t emptyRefillCells0319 = 0u;
    std::uint64_t emptyRefillParticles0319 = 0u;
    std::uint64_t emptyRefillSkippedNoMemory0319 = 0u;
    std::uint64_t emptyRefillSkippedNoCapacity0319 = 0u;
    double emptyRefillAddedMass0319 = 0.0;
    double emptyRefillAddedPx0319 = 0.0;
    double emptyRefillAddedPy0319 = 0.0;
    double emptyRefillMassScale0319 = 1.0;
    double emptyRefillVelocityShiftX0319 = 0.0;
    double emptyRefillVelocityShiftY0319 = 0.0;

    double totalMassBefore = 0.0;
    double totalMassAfter = 0.0;
    double totalPxBefore = 0.0;
    double totalPxAfter = 0.0;
    double totalPyBefore = 0.0;
    double totalPyAfter = 0.0;

    // 0298: cell-relative kinetic energy diagnostics/restoration after support mutation.
    bool momentRestoreRequested0298 = false;
    bool energyRestoreApplied0298 = false;
    std::uint64_t energyRestoreParticleUpdates0298 = 0u;
    std::uint64_t energyRestoreSkippedParticles0298 = 0u;
    double energyRestoreMaxScale0298 = 4.0;
    double totalKrelBefore0298 = 0.0;
    double totalKrelAfterPreRestore0298 = 0.0;
    double totalKrelAfter0298 = 0.0;
    double maxAbsCellKrelErrorPreRestore0298 = 0.0;
    double maxRelCellKrelErrorPreRestore0298 = 0.0;
    double maxAbsCellKrelError0298 = 0.0;
    double maxRelCellKrelError0298 = 0.0;

    double maxAbsCellMassError = 0.0;
    double maxRelCellMassError = 0.0;
    double maxAbsCellMomentumError = 0.0;
    double maxRelCellMomentumError = 0.0;

    // 0299: boundary-aware candidate filtering for the local guard.  These
    // counters describe cells that would otherwise be considered for split/merge
    // but are intentionally excluded from the local mutating guard because they
    // lie in a configurable wall/open-boundary/solid halo.
    bool boundaryAware0299 = false;
    int boundaryHaloCells0299 = 0;
    int openBoundaryHaloCells0299 = 0;
    int solidHaloCells0299 = 0;
    std::uint64_t excludedBoundaryCells0299 = 0u;
    std::uint64_t excludedOpenBoundaryCells0299 = 0u;
    std::uint64_t excludedSolidHaloCells0299 = 0u;

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

bool cuda_resampling_population_guard_0297_requested(const SimulationParams& params, std::uint64_t step);

CudaResamplingPopulationGuard0297Diagnostics try_apply_cuda_resampling_population_guard_0297(
    ParticleState& hostMirror,
    const SimulationParams& params,
    const CellGrid& grid,
    const FluidDomainBounds& domain,
    std::uint64_t step,
    double time,
    const char* stage);

#else

inline bool cuda_resampling_population_guard_0297_requested(const SimulationParams&, std::uint64_t) {
    return false;
}

inline CudaResamplingPopulationGuard0297Diagnostics try_apply_cuda_resampling_population_guard_0297(
    ParticleState&,
    const SimulationParams&,
    const CellGrid&,
    const FluidDomainBounds&,
    std::uint64_t,
    double,
    const char*) {
    return CudaResamplingPopulationGuard0297Diagnostics{};
}

#endif

} // namespace mpcd
