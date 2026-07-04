#pragma once

#include "cell_grid.h"
#include "fluid_domain.h"
#include "particle_state.h"
#include "simulation_params.h"
#include "weighted_resampling.h"

#include <cstdint>
#include <string>

namespace mpcd {

// 0445: experimental in-solver CUDA shadow for the clean resampling pipeline.
// It is non-mutating: the CPU resampling path remains authoritative.  The
// shadow compares a device extraction/insertion + remap+thermal replay against
// the final CPU state.  The CPU path remains authoritative; CUDA only replays
// the clean pipeline on a shadow copy and writes diagnostics.
struct CudaResamplingPipelineShadow0445Diagnostics {
    bool attempted = false;
    bool handled = false;
    bool pass = false;
    bool skipped = false;
    std::string skipReason;

    std::uint64_t step = 0u;
    std::string stage;
    std::string outputCsv;

    std::uint64_t nActive = 0u;
    std::uint64_t planEntries = 0u;
    std::uint64_t passiveOps = 0u;
    std::uint64_t cpuExtractionApplied = 0u;
    std::uint64_t cpuInsertionApplied = 0u;
    std::uint64_t gpuExtractionApplied = 0u;
    std::uint64_t gpuInsertionApplied = 0u;
    std::uint64_t gpuInvalidOperations = 0u;
    std::uint64_t cpuRemapCells = 0u;
    std::uint64_t gpuRemapCells = 0u;
    std::uint64_t cpuThermalCells = 0u;
    std::uint64_t gpuThermalCells = 0u;
    std::uint64_t roleMismatch = 0u;
    std::uint64_t typeMismatch = 0u;
    std::uint64_t badPrefixCpu = 0u;
    std::uint64_t badPrefixGpu = 0u;

    double maxAbsX = 0.0;
    double maxAbsY = 0.0;
    double maxAbsMass = 0.0;
    double maxAbsVx = 0.0;
    double maxAbsVy = 0.0;
    double massCpu = 0.0;
    double massGpu = 0.0;
    double pxCpu = 0.0;
    double pxGpu = 0.0;
    double pyCpu = 0.0;
    double pyGpu = 0.0;
    double keCpu = 0.0;
    double keGpu = 0.0;
    double applyKernelSeconds = 0.0;
    double remapKernelSeconds = 0.0;
    double thermalKernelSeconds = 0.0;
    double totalSeconds = 0.0;
};

#if defined(MPCD_ENABLE_CUDA_RESAMPLING) && defined(MPCD_ENABLE_CUDA_PARTICLE_STATE)

bool cuda_resampling_pipeline_shadow_0445_requested(std::uint64_t step);

CudaResamplingPipelineShadow0445Diagnostics try_run_cuda_resampling_pipeline_shadow_0445(
    const ParticleState& shadowInputState,
    const ParticleState& cpuFinalState,
    const SimulationParams& params,
    const CellGrid& grid,
    const FluidDomainBounds& domain,
    double time,
    std::uint64_t step,
    const char* stage,
    const WeightedRealFluidDepositWorkspace& editWorkspace,
    const WeightedRealFluidDepositWorkspace& remapWorkspace,
    const WeightedResamplingDiagnostics& remapDepositDiagnostics,
    const ResamplingExtractionApplyDiagnostics& cpuExtraction,
    const ResamplingInsertionApplyDiagnostics& cpuInsertion,
    const ResamplingRemapApplyDiagnostics& cpuRemap,
    const ResamplingThermalRenormalizationDiagnostics& cpuThermal);

#else

inline bool cuda_resampling_pipeline_shadow_0445_requested(std::uint64_t) { return false; }

inline CudaResamplingPipelineShadow0445Diagnostics try_run_cuda_resampling_pipeline_shadow_0445(
    const ParticleState&, const ParticleState&, const SimulationParams&, const CellGrid&, const FluidDomainBounds&,
    double, std::uint64_t, const char*, const WeightedRealFluidDepositWorkspace&, const WeightedRealFluidDepositWorkspace&,
    const WeightedResamplingDiagnostics&, const ResamplingExtractionApplyDiagnostics&, const ResamplingInsertionApplyDiagnostics&,
    const ResamplingRemapApplyDiagnostics&, const ResamplingThermalRenormalizationDiagnostics&) {
    return CudaResamplingPipelineShadow0445Diagnostics{};
}

#endif

} // namespace mpcd
