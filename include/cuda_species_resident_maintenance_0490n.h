#pragma once

#include "cell_grid.h"
#include "cuda_species_cell_fields_0490h.h"
#include "fluid_domain.h"
#include "particle_state.h"
#include "simulation_params.h"
#include "weighted_resampling.h"

#include <cstdint>
#include <string>

namespace mpcd {

struct CudaSpeciesResidentMaintenanceDiagnostics0490n {
    bool attempted = false;
    bool handled = false;
    bool pass = false;
    bool skipped = false;
    std::string skipReason;
    std::string context;
    std::uint64_t step = 0u;

    int depositRequested = 0;
    int poolRequested = 0;
    int strictMode = 0;
    int usedSharedResidentState = 0;
    int particleUploadSkipped = 0;
    int speciesWorkspaceReused = 0;
    int maintenanceWorkspaceReused = 0;

    std::uint64_t storageSlots = 0u;
    std::uint64_t fluidSlots = 0u;
    std::uint64_t latentSlots = 0u;
    std::uint64_t inactiveSlots = 0u;
    std::uint64_t firstFluidSlot = kInvalidParticleIndex;
    std::uint64_t lastFluidSlot = kInvalidParticleIndex;
    std::uint64_t firstInactiveSlot = kInvalidParticleIndex;
    std::uint64_t lastInactiveSlot = kInvalidParticleIndex;
    std::uint64_t activePrefixViolations = 0u;
    std::uint64_t duplicateFreeSlots = 0u;
    std::uint64_t activeAndFreeSlots = 0u;
    std::uint64_t invalidRoleSlots = 0u;

    std::uint64_t cells = 0u;
    std::uint64_t species = 0u;
    std::uint64_t nonEmptyCells = 0u;
    std::uint64_t wetCells = 0u;
    std::uint64_t poorCells = 0u;
    std::uint64_t richCells = 0u;
    std::uint64_t receiverCells = 0u;
    std::uint64_t donorCells = 0u;
    std::uint64_t cellMirrorDownloadBytes = 0u;
    std::uint64_t poolScalarDownloadBytes = 0u;
    std::uint64_t allocatedBytes = 0u;

    double totalMass = 0.0;
    double totalPx = 0.0;
    double totalPy = 0.0;
    double targetCellMass = 0.0;
    double maxCellMassMirrorError = 0.0;
    double particleUploadSeconds = 0.0;
    double speciesDepositSeconds = 0.0;
    double poolBuildSeconds = 0.0;
    double compactDownloadSeconds = 0.0;
    double hostCellMirrorSeconds = 0.0;
    double totalSeconds = 0.0;
};

struct CudaSpeciesResidentPoolDeviceView0490n {
    std::uint64_t capacity = 0u;
    const unsigned int* fluidSlots = nullptr;
    const unsigned int* latentSlots = nullptr;
    const unsigned int* inactiveSlots = nullptr;
    const unsigned int* fluidCount = nullptr;
    const unsigned int* latentCount = nullptr;
    const unsigned int* inactiveCount = nullptr;
};

class CudaSpeciesResidentMaintenanceWorkspace0490n {
public:
    CudaSpeciesResidentMaintenanceWorkspace0490n();
    ~CudaSpeciesResidentMaintenanceWorkspace0490n();

    CudaSpeciesResidentMaintenanceWorkspace0490n(
        const CudaSpeciesResidentMaintenanceWorkspace0490n&) = delete;
    CudaSpeciesResidentMaintenanceWorkspace0490n& operator=(
        const CudaSpeciesResidentMaintenanceWorkspace0490n&) = delete;
    CudaSpeciesResidentMaintenanceWorkspace0490n(
        CudaSpeciesResidentMaintenanceWorkspace0490n&&) noexcept;
    CudaSpeciesResidentMaintenanceWorkspace0490n& operator=(
        CudaSpeciesResidentMaintenanceWorkspace0490n&&) noexcept;

    void release();
    void ensure_capacity(std::uint64_t particles,
                         CudaSpeciesResidentMaintenanceDiagnostics0490n* diagnostics = nullptr);
    std::uint64_t capacity() const;
    std::uint64_t allocated_bytes() const;
    CudaSpeciesResidentPoolDeviceView0490n pool_device_view() const;

private:
    struct Impl;
    Impl* impl_ = nullptr;

    friend CudaSpeciesResidentMaintenanceDiagnostics0490n
    refresh_cuda_species_resident_maintenance_0490n(
        ParticleState&,
        const SimulationParams&,
        const CellGrid&,
        const FluidDomainBounds&,
        double,
        std::uint64_t,
        const char*,
        bool,
        bool,
        CudaSpeciesCellWorkspace0490h&,
        CudaSpeciesResidentMaintenanceWorkspace0490n&,
        WeightedRealFluidDepositWorkspace&,
        WeightedResamplingDiagnostics&,
        ResamplingParticlePoolWorkspace&,
        ResamplingParticlePoolDiagnostics&);
};

bool cuda_species_resident_maintenance_available_0490n();

// 0490n integrated resident maintenance gate. The expensive particle scans for
// the legacy weighted deposit and pool rebuild execute on the shared CUDA state.
// Only compact per-cell mirrors and pool scalar diagnostics are downloaded for
// the still-host-orchestrated resampling policy. The resident free-list remains
// on device and is exposed through pool_device_view().
CudaSpeciesResidentMaintenanceDiagnostics0490n
refresh_cuda_species_resident_maintenance_0490n(
    ParticleState& state,
    const SimulationParams& params,
    const CellGrid& grid,
    const FluidDomainBounds& domain,
    double time,
    std::uint64_t step,
    const char* context,
    bool refreshDeposit,
    bool refreshPool,
    CudaSpeciesCellWorkspace0490h& speciesWorkspace,
    CudaSpeciesResidentMaintenanceWorkspace0490n& maintenanceWorkspace,
    WeightedRealFluidDepositWorkspace& depositMirror,
    WeightedResamplingDiagnostics& depositDiagnostics,
    ResamplingParticlePoolWorkspace& poolMirror,
    ResamplingParticlePoolDiagnostics& poolDiagnostics);

} // namespace mpcd
