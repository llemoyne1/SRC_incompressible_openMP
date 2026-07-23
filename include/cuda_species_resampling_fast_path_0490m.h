#pragma once

#include "cell_grid.h"
#include "cuda_species_transfer_plan_0490k.h"
#include "particle_state.h"
#include "simulation_params.h"
#include "weighted_resampling.h"

#include <cstdint>
#include <string>

namespace mpcd {

struct CudaSpeciesResamplingFastPathDiagnostics0490m {
    bool attempted = false;
    bool handled = false;
    bool applied = false;
    bool pass = false;
    bool skipped = false;
    std::string skipReason;

    std::uint64_t step = 0u;
    std::uint64_t particlesScanned = 0u;
    std::uint64_t planEntries = 0u;
    std::uint64_t operations = 0u;
    std::uint64_t invalidOperations = 0u;
    std::uint64_t typeRejectedCandidates = 0u;

    int usedSharedResidentState = 0;
    int particleUploadSkipped = 0;
    int workspaceReused = 0;
    int directDevicePlanHandoff = 0;
    int planArrayDownloadSkipped = 0;
    int planArrayUploadSkipped = 0;
    int operationRoundTripSkipped = 0;
    int fullStateCopySkipped = 0;
    int fullStateDownloadSkipped = 0;

    std::uint64_t allocatedBytes = 0u;
    std::uint64_t allocationCalls = 0u;
    std::uint64_t compactPatchbackBytes = 0u;

    double movedMass = 0.0;
    double movedMomentumX = 0.0;
    double movedMomentumY = 0.0;
    double stateUploadSeconds = 0.0;
    double kernelSeconds = 0.0;
    double scalarDownloadSeconds = 0.0;
    double patchbackDownloadSeconds = 0.0;
    double hostPatchbackSeconds = 0.0;
    double totalSeconds = 0.0;
};

class CudaSpeciesResamplingFastPathWorkspace0490m {
public:
    CudaSpeciesResamplingFastPathWorkspace0490m();
    ~CudaSpeciesResamplingFastPathWorkspace0490m();

    CudaSpeciesResamplingFastPathWorkspace0490m(
        const CudaSpeciesResamplingFastPathWorkspace0490m&) = delete;
    CudaSpeciesResamplingFastPathWorkspace0490m& operator=(
        const CudaSpeciesResamplingFastPathWorkspace0490m&) = delete;
    CudaSpeciesResamplingFastPathWorkspace0490m(
        CudaSpeciesResamplingFastPathWorkspace0490m&&) noexcept;
    CudaSpeciesResamplingFastPathWorkspace0490m& operator=(
        CudaSpeciesResamplingFastPathWorkspace0490m&&) noexcept;

    void release();
    void ensure_capacity(std::uint64_t activeParticles,
                         CudaSpeciesResamplingFastPathDiagnostics0490m* diagnostics = nullptr);
    std::uint64_t capacity() const;
    std::uint64_t allocated_bytes() const;

private:
    struct Impl;
    Impl* impl_ = nullptr;

    friend CudaSpeciesResamplingFastPathDiagnostics0490m
    try_apply_cuda_species_resampling_fast_path_0490m(
        ParticleState&,
        const SimulationParams&,
        const CellGrid&,
        std::uint64_t,
        const CudaSpeciesTransferPlanWorkspace0490k&,
        CudaSpeciesResamplingFastPathWorkspace0490m&,
        ResamplingExtractionApplyDiagnostics&,
        ResamplingInsertionApplyDiagnostics&);
};

bool cuda_species_resampling_fast_path_available_0490m();

// 0490m direct resident handoff. The authoritative 0490k device plan is
// consumed in-place, donor particles are selected by donor cell and exact
// particle type, and the shared CUDA particle state is mutated without any
// host plan/operation vector. A compact patchback of moved particles keeps the
// legacy host state coherent until the remaining resampling orchestration is
// migrated fully to CUDA.
CudaSpeciesResamplingFastPathDiagnostics0490m
try_apply_cuda_species_resampling_fast_path_0490m(
    ParticleState& state,
    const SimulationParams& params,
    const CellGrid& grid,
    std::uint64_t step,
    const CudaSpeciesTransferPlanWorkspace0490k& planWorkspace,
    CudaSpeciesResamplingFastPathWorkspace0490m& fastWorkspace,
    ResamplingExtractionApplyDiagnostics& extractionApply,
    ResamplingInsertionApplyDiagnostics& insertionApply);

} // namespace mpcd
