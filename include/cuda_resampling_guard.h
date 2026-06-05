#pragma once

#include <cstdint>
#include <vector>

namespace mpcd {

struct CudaResamplingGuardParams {
    double targetCellMass = 1.0;
    double poorRelativeThreshold = 0.10;
    double richRelativeThreshold = 0.10;
    std::uint32_t minFluidCount = 1u;
    bool useActiveMask = false;
};

struct CudaResamplingGuardDiagnostics {
    bool attempted = false;
    bool applied = false;
    std::uint64_t cells = 0;
    std::uint64_t activeCells = 0;
    std::uint64_t wetCells = 0;
    std::uint64_t dryCells = 0;
    std::uint64_t poorCells = 0;
    std::uint64_t richCells = 0;
    std::uint64_t targetBandCells = 0;
    double totalMass = 0.0;
    double minMass = 0.0;
    double maxMass = 0.0;
};

// Standalone CUDA cell-classification primitive for the first resampling GPU step.
// It mirrors the CPU-side classification logic used to identify active, wet/dry,
// poor receiver and rich donor cells from an already built cell deposit.
bool cuda_resampling_classify_cells_0227(
    const std::vector<std::uint32_t>& cellCount,
    const std::vector<double>& cellMass,
    const std::vector<std::uint8_t>& activeCell,
    const CudaResamplingGuardParams& params,
    std::vector<std::uint8_t>& wetCell,
    std::vector<std::uint8_t>& dryCell,
    std::vector<std::uint8_t>& poorCell,
    std::vector<std::uint8_t>& richCell,
    std::vector<std::uint8_t>& targetBandCell,
    CudaResamplingGuardDiagnostics* diagnostics = nullptr);

} // namespace mpcd
