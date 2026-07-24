#pragma once

#include "cell_grid.h"
#include "cuda_species_cell_fields_0490h.h"
#include "cuda_species_cell_policy_0490p.h"
#include "particle_state.h"
#include "simulation_params.h"
#include "weighted_resampling.h"

#include <cstdint>
#include <string>

namespace mpcd {

struct CudaSpeciesTransferPlanDiagnostics0490k {
    bool attempted = false;
    bool handled = false;
    bool pass = false;
    bool accepted = false;
    bool strictResidentMode = false;
    bool productionFastPath = false;
    bool cpuReferenceSkipped = false;
    bool planArrayDownloadSkipped = false;
    bool directDeviceHandoffReady = false;
    bool residentPolicyDeviceHandoff = false;
    bool policyMaskUploadSkipped = false;

    std::uint64_t step = 0u;
    std::string outputCsv;

    std::uint64_t particlesScanned = 0u;
    std::uint64_t receiverCells = 0u;
    std::uint64_t donorCells = 0u;
    std::uint64_t cpuPlanEntries = 0u;
    std::uint64_t gpuPlanEntries = 0u;
    std::uint64_t planMismatch = 0u;
    std::uint64_t typeMismatch = 0u;
    std::uint64_t overflowCount = 0u;

    int usedSharedResidentState = 0;
    int particleUploadSkipped = 0;
    int speciesWorkspaceReused = 0;
    int planWorkspaceReused = 0;

    double cpuPlannedMass = 0.0;
    double gpuPlannedMass = 0.0;
    double maxPlanMassError = 0.0;
    double maxPlanDistanceError = 0.0;
    double maxDonorRemainingError = 0.0;
    double maxReceiverRemainingError = 0.0;

    std::int32_t firstDonorCell = kInvalidCellIndex;
    std::int32_t firstReceiverCell = kInvalidCellIndex;
    std::uint32_t firstParticleType = 0u;
    std::int32_t lastDonorCell = kInvalidCellIndex;
    std::int32_t lastReceiverCell = kInvalidCellIndex;
    std::uint32_t lastParticleType = 0u;

    std::uint64_t allocatedBytes = 0u;
    std::uint64_t allocationCalls = 0u;
    double stateUploadSeconds = 0.0;
    double speciesDepositSeconds = 0.0;
    double metadataUploadSeconds = 0.0;
    double plannerKernelSeconds = 0.0;
    double compactDownloadSeconds = 0.0;
    double totalSeconds = 0.0;
};


struct CudaSpeciesTransferPlanDeviceView0490m {
    int capacity = 0;
    const int* donorCell = nullptr;
    const int* receiverCell = nullptr;
    const std::uint32_t* particleType = nullptr;
    const double* plannedMass = nullptr;
    const unsigned int* count = nullptr;
    const unsigned int* overflow = nullptr;
};

class CudaSpeciesTransferPlanWorkspace0490k {
public:
    CudaSpeciesTransferPlanWorkspace0490k();
    ~CudaSpeciesTransferPlanWorkspace0490k();

    CudaSpeciesTransferPlanWorkspace0490k(const CudaSpeciesTransferPlanWorkspace0490k&) = delete;
    CudaSpeciesTransferPlanWorkspace0490k& operator=(const CudaSpeciesTransferPlanWorkspace0490k&) = delete;
    CudaSpeciesTransferPlanWorkspace0490k(CudaSpeciesTransferPlanWorkspace0490k&&) noexcept;
    CudaSpeciesTransferPlanWorkspace0490k& operator=(CudaSpeciesTransferPlanWorkspace0490k&&) noexcept;

    void release();
    void ensure_capacity(int numCells,
                         int speciesCount,
                         int maxPlanEntries,
                         CudaSpeciesTransferPlanDiagnostics0490k* diagnostics = nullptr);

    int cell_capacity() const;
    int species_capacity() const;
    int plan_capacity() const;
    std::uint64_t allocated_bytes() const;
    CudaSpeciesTransferPlanDeviceView0490m device_view_0490m() const;

private:
    struct Impl;
    Impl* impl_ = nullptr;

    friend CudaSpeciesTransferPlanDiagnostics0490k
    try_apply_cuda_species_transfer_plan_0490k(
        const ParticleState&,
        const SimulationParams&,
        const CellGrid&,
        std::uint64_t,
        CudaSpeciesCellWorkspace0490h&,
        CudaSpeciesTransferPlanWorkspace0490k&,
        const CudaSpeciesCellPolicyDeviceView0490p&,
        WeightedRealFluidDepositWorkspace&,
        WeightedResamplingDiagnostics&);
};

bool cuda_species_transfer_plan_available_0490k();

// 0490k correctness-first native CUDA planner. The GPU constructs the complete
// species-constrained donor/receiver plan from the resident 0490h composition
// fields. In 0490l validation mode the CPU reference is skipped but a compact
// host mirror remains available to the legacy CUDA materializer. In 0490m fast
// mode, plan arrays remain device-resident and device_view_0490m() is consumed
// directly by the production materialize+apply backend. 0490p also consumes
// the resident wet-cell policy mask directly, eliminating its host round-trip.
CudaSpeciesTransferPlanDiagnostics0490k try_apply_cuda_species_transfer_plan_0490k(
    const ParticleState& state,
    const SimulationParams& params,
    const CellGrid& grid,
    std::uint64_t step,
    CudaSpeciesCellWorkspace0490h& speciesWorkspace,
    CudaSpeciesTransferPlanWorkspace0490k& planWorkspace,
    const CudaSpeciesCellPolicyDeviceView0490p& residentPolicy0490p,
    WeightedRealFluidDepositWorkspace& resamplingWorkspace,
    WeightedResamplingDiagnostics& resamplingDiagnostics);

} // namespace mpcd
