#pragma once

#include "cell_grid.h"
#include "cuda_species_cell_fields_0490h.h"
#include "particle_state.h"
#include "simulation_params.h"
#include "weighted_resampling.h"

#include <cstdint>
#include <string>
#include <vector>

namespace mpcd {

struct CudaSpeciesMassClosure0490iDiagnostics {
    int attempted = 0;
    int handled = 0;
    int applied = 0;
    int usedSharedResidentState = 0;
    int particleUploadSkipped = 0;
    int speciesWorkspaceReused = 0;
    int closureWorkspaceReused = 0;
    int sharedStatePreserved = 0;
    int productionFastPath = 0;
    int diagnosticCellDownloadSkipped = 0;
    int cpuDepositComparisonSkipped = 0;
    int speciesConservativeBalance = 0;
    int balanceIterations = 0;
    std::uint64_t step = 0u;
    std::uint64_t particlesScanned = 0u;
    std::uint64_t particlesScaled = 0u;
    std::uint64_t cellsConsidered = 0u;
    std::uint64_t cellsRemapped = 0u;
    std::uint64_t invalidTypeCount = 0u;
    std::uint64_t allocatedBytes = 0u;
    double maxAbsDepositMassError = 0.0;
    double scaleMin = 1.0;
    double scaleMax = 1.0;
    double targetCellMassMin = 0.0;
    double targetCellMassMax = 0.0;
    double closureStrengthMin = 0.0;
    double closureStrengthMax = 0.0;
    double massBefore = 0.0;
    double massAfter = 0.0;
    double massDelta = 0.0;
    double maxSpeciesMassRelResidual = 0.0;
    double maxCellMassRelResidual = 0.0;
    double maxVelocityShift = 0.0;
    double particleUploadSeconds = 0.0;
    double speciesDepositSeconds = 0.0;
    double metadataUploadSeconds = 0.0;
    double scaleKernelSeconds = 0.0;
    double applyKernelSeconds = 0.0;
    double diagnosticDownloadSeconds = 0.0;
    double particleDownloadSeconds = 0.0;
    double totalSeconds = 0.0;
    std::string diagnosticsCsv;
};

struct CudaSpeciesMassClosureDeviceView0490i {
    int numCells = 0;
    int speciesCount = 0;
    double* speciesClosureStrength = nullptr;
    double* targetCellMass = nullptr;
    double* localClosureStrength = nullptr;
    double* scale = nullptr;
    unsigned char* remapCell = nullptr;
    double* speciesCellScale = nullptr;
    double* targetSpeciesMass = nullptr;
    double* currentSpeciesMass = nullptr;
    double* currentCellMass = nullptr;
    double* velocityShiftX = nullptr;
    double* velocityShiftY = nullptr;
    double* maxSpeciesMassRelResidual = nullptr;
    double* maxCellMassRelResidual = nullptr;
    double* maxVelocityShift = nullptr;
    unsigned long long* particlesScaled = nullptr;
};

class CudaSpeciesMassClosureWorkspace0490i {
public:
    CudaSpeciesMassClosureWorkspace0490i();
    ~CudaSpeciesMassClosureWorkspace0490i();

    CudaSpeciesMassClosureWorkspace0490i(
        const CudaSpeciesMassClosureWorkspace0490i&) = delete;
    CudaSpeciesMassClosureWorkspace0490i& operator=(
        const CudaSpeciesMassClosureWorkspace0490i&) = delete;
    CudaSpeciesMassClosureWorkspace0490i(
        CudaSpeciesMassClosureWorkspace0490i&&) noexcept;
    CudaSpeciesMassClosureWorkspace0490i& operator=(
        CudaSpeciesMassClosureWorkspace0490i&&) noexcept;

    void release();
    void ensure_capacity(int numCells, int speciesCount, int* reused = nullptr);
    CudaSpeciesMassClosureDeviceView0490i device_view();
    CudaSpeciesMassClosureDeviceView0490i device_view() const;
    std::uint64_t allocated_bytes() const;

private:
    struct Impl;
    Impl* impl_ = nullptr;
};

bool cuda_species_mass_closure_available_0490i();

// 0490i production path. The physical closure is computed and applied on the
// resident GPU particle state. In 0490m production-fast mode, a resident
// species-conservative matrix balance preserves every global species mass while
// approaching the requested cell-mass closure and restoring each cell mean
// velocity. Dense per-cell diagnostic downloads and the CPU deposit equivalence
// loop are skipped. With 0490n resident deposits enabled, the active
// mass/velocity prefix also remains resident and the post-remap deposit consumes
// the shared CUDA state directly.
CudaSpeciesMassClosure0490iDiagnostics apply_cuda_species_mass_closure_0490i(
    ParticleState& state,
    const SimulationParams& params,
    const CellGrid& grid,
    const WeightedRealFluidDepositWorkspace& cpuDepositWorkspace,
    const WeightedResamplingDiagnostics& cpuDepositDiagnostics,
    double massCorrectionStrength,
    double targetCellMassOverride,
    std::uint64_t step,
    CudaSpeciesCellWorkspace0490h& speciesWorkspace,
    CudaSpeciesMassClosureWorkspace0490i& closureWorkspace,
    ResamplingRemapApplyDiagnostics& remapApply,
    int threadsPerBlock = 256);

} // namespace mpcd
