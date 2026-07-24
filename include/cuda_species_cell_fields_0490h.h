#pragma once

#include "cell_grid.h"
#include "cuda_particle_state.h"
#include "particle_state.h"
#include "species_cell_fields_0490b.h"
#include "species_registry.h"

#include <cstdint>
#include <fstream>
#include <string>
#include <vector>

namespace mpcd {

// 0490h: resident CUDA species-cell workspace. Layout is species-major:
//   k = speciesIndex * numCells + cell.
// It is intentionally independent from CudaCellWorkspace so that the legacy
// single-fluid deposit remains byte-for-byte unchanged while later patches can
// attach this workspace to resampling and Q6.
struct CudaSpeciesCellDeviceView0490h {
    int numCells = 0;
    int speciesCount = 0;
    std::uint32_t* speciesTypes = nullptr;
    double* q6Strength = nullptr;
    double* referenceCellMass = nullptr;
    unsigned char* phaseFamily = nullptr;
    unsigned int* count = nullptr;
    double* mass = nullptr;
    double* px = nullptr;
    double* py = nullptr;
    double* totalCellMass = nullptr;
    double* totalOccupancyWeight = nullptr;
    double* massFraction = nullptr;
    double* occupancyFraction = nullptr;
    double* liquidFractionProxy = nullptr;
    double* gasFractionProxy = nullptr;
    unsigned long long* invalidTypeCounter = nullptr;
};

struct CudaSpeciesCellFields0490h {
    int numCells = 0;
    std::vector<std::uint32_t> speciesTypes;
    std::vector<double> q6Strength;
    std::vector<std::uint32_t> count;
    std::vector<double> mass;
    std::vector<double> px;
    std::vector<double> py;
    std::vector<double> totalCellMass;
    std::vector<double> totalOccupancyWeight;
    std::vector<double> massFraction;
    std::vector<double> occupancyFraction;
    std::vector<double> liquidFractionProxy;
    std::vector<double> gasFractionProxy;
    std::uint64_t invalidTypeCount = 0u;
};

struct CudaSpeciesCellDepositDiagnostics0490h {
    std::uint64_t particlesScanned = 0u;
    int numCells = 0;
    int speciesCount = 0;
    std::uint64_t allocatedBytes = 0u;
    std::uint64_t allocationCalls = 0u;
    std::uint64_t metadataUploadBytes = 0u;
    int reusedAllocation = 0;
    std::uint64_t invalidTypeCount = 0u;
    double allocateSeconds = 0.0;
    double resetSeconds = 0.0;
    double metadataUploadSeconds = 0.0;
    double depositSeconds = 0.0;
    double finalizeSeconds = 0.0;
    double downloadSeconds = 0.0;
    double totalSeconds = 0.0;
};

struct SpeciesCellCudaEquivalence0490h {
    int pass = 0;
    int usedSharedResidentState = 0;
    int reusedAllocation = 0;
    std::uint64_t particlesScanned = 0u;
    std::uint64_t invalidTypeCount = 0u;
    std::uint64_t countMismatches = 0u;
    double maxAbsMassError = 0.0;
    double maxAbsPxError = 0.0;
    double maxAbsPyError = 0.0;
    double maxAbsTotalMassError = 0.0;
    double maxAbsTotalOccupancyWeightError = 0.0;
    double maxAbsMassFractionError = 0.0;
    double maxAbsOccupancyFractionError = 0.0;
    double maxAbsLiquidFractionError = 0.0;
    double maxAbsGasFractionError = 0.0;
    CudaSpeciesCellDepositDiagnostics0490h cuda{};
};

bool cuda_species_cell_fields_available_0490h();

class CudaSpeciesCellWorkspace0490h {
public:
    CudaSpeciesCellWorkspace0490h();
    ~CudaSpeciesCellWorkspace0490h();

    CudaSpeciesCellWorkspace0490h(const CudaSpeciesCellWorkspace0490h&) = delete;
    CudaSpeciesCellWorkspace0490h& operator=(const CudaSpeciesCellWorkspace0490h&) = delete;
    CudaSpeciesCellWorkspace0490h(CudaSpeciesCellWorkspace0490h&&) noexcept;
    CudaSpeciesCellWorkspace0490h& operator=(CudaSpeciesCellWorkspace0490h&&) noexcept;

    void release();
    void ensure_capacity(int numCells,
                         int speciesCount,
                         CudaSpeciesCellDepositDiagnostics0490h* diag = nullptr);

    CudaSpeciesCellDeviceView0490h device_view();
    CudaSpeciesCellDeviceView0490h device_view() const;

    int cell_capacity() const;
    int species_capacity() const;
    std::uint64_t allocated_bytes() const;

private:
    struct Impl;
    Impl* impl_ = nullptr;
};

// Production-facing resident path: consumes an already-resident particle view
// and leaves all species-cell fields resident in workspace.
void cuda_deposit_species_cell_fields_resident_0490h(
    const CudaParticleDeviceView& particles,
    const CellGrid& grid,
    const SimulationParams& params,
    const std::vector<SpeciesDefinition>& definitions,
    CudaSpeciesCellWorkspace0490h& workspace,
    CudaSpeciesCellDepositDiagnostics0490h* diagnostics = nullptr,
    int threadsPerBlock = 256);

// Diagnostic download only. Later resampling/Q6 patches should consume
// workspace.device_view() directly instead of calling this function.
CudaSpeciesCellFields0490h cuda_download_species_cell_fields_0490h(
    const CudaSpeciesCellWorkspace0490h& workspace,
    const std::vector<SpeciesDefinition>& definitions,
    CudaSpeciesCellDepositDiagnostics0490h* diagnostics = nullptr);

SpeciesCellCudaEquivalence0490h compare_species_cell_cuda_cpu_0490h(
    const CudaParticleDeviceView& particles,
    const ParticleState& cpuReferenceState,
    const std::vector<SpeciesDefinition>& definitions,
    const CellGrid& grid,
    const SimulationParams& params,
    bool requireRegisteredTypes,
    double tolerance,
    CudaSpeciesCellWorkspace0490h& workspace,
    int usedSharedResidentState,
    int threadsPerBlock = 256);

class SpeciesCellCudaEquivalenceWriter0490h {
public:
    explicit SpeciesCellCudaEquivalenceWriter0490h(const std::string& filepath);

    SpeciesCellCudaEquivalence0490h append(
        const CudaParticleDeviceView& particles,
        const ParticleState& cpuReferenceState,
        const std::vector<SpeciesDefinition>& definitions,
        const CellGrid& grid,
        const SimulationParams& params,
        bool requireRegisteredTypes,
        double tolerance,
        CudaSpeciesCellWorkspace0490h& workspace,
        std::uint64_t step,
        double time,
        int usedSharedResidentState,
        int threadsPerBlock = 256);

private:
    std::ofstream out_;
};

} // namespace mpcd
