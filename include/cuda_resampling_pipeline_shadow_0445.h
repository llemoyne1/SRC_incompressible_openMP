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


// 0448: experimental production apply backend for the clean resampling
// pipeline.  Unlike the 0445/0446 hook, this mutates the supplied ParticleState
// after validating the CUDA operation on a temporary copy.  It is intentionally
// limited to extraction/insertion + remap + thermal; mass/population guards and
// CUDA-local auxiliaries remain outside this backend.
struct CudaResamplingPipelineApply0448Diagnostics {
    bool attempted = false;
    bool handled = false;
    bool applied = false;
    bool skipped = false;
    std::string skipReason;

    std::uint64_t step = 0u;
    std::string stage;

    std::uint64_t nActive = 0u;
    std::uint64_t passiveOps = 0u;
    std::uint64_t gpuExtractionApplied = 0u;
    std::uint64_t gpuInsertionApplied = 0u;
    std::uint64_t gpuInvalidOperations = 0u;
    std::uint64_t gpuRemapCells = 0u;
    std::uint64_t gpuThermalCells = 0u;
    double applyKernelSeconds = 0.0;
    double remapKernelSeconds = 0.0;
    double thermalKernelSeconds = 0.0;
    double totalSeconds = 0.0;
};

// 0450: in-solver CUDA upstream shadow.  This validates the CUDA-derived
// deposit/classification/poor-rich compaction and transfer planner against the
// CPU workspace that still remains authoritative for 0448/0449 apply runs.
struct CudaResamplingUpstreamShadow0450Diagnostics {
    bool attempted = false;
    bool handled = false;
    bool pass = false;
    bool skipped = false;
    std::string skipReason;

    std::uint64_t step = 0u;
    std::string outputCsv;

    std::uint64_t nActive = 0u;
    std::uint64_t nCells = 0u;

    std::uint64_t cellIdMismatch = 0u;
    double maxCountDiff = 0.0;
    double maxMassAbs = 0.0;
    double maxPxAbs = 0.0;
    double maxPyAbs = 0.0;
    double maxUxAbs = 0.0;
    double maxUyAbs = 0.0;
    double cpuTotalMass = 0.0;
    double gpuTotalMass = 0.0;
    double cpuTotalPx = 0.0;
    double gpuTotalPx = 0.0;
    double cpuTotalPy = 0.0;
    double gpuTotalPy = 0.0;

    std::uint64_t cpuReceiverCells = 0u;
    std::uint64_t gpuReceiverCells = 0u;
    std::uint64_t cpuDonorCells = 0u;
    std::uint64_t gpuDonorCells = 0u;
    std::uint64_t receiverListMismatch = 0u;
    std::uint64_t donorListMismatch = 0u;

    std::uint64_t cpuTransferPairs = 0u;
    std::uint64_t gpuTransferPairs = 0u;
    std::uint64_t planMismatch = 0u;
    double maxPlanMassAbs = 0.0;
    double maxPlanDistanceAbs = 0.0;
    double cpuPlannedMass = 0.0;
    double gpuPlannedMass = 0.0;
    std::uint64_t cpuPassiveOps = 0u;

    // 0474: upstream CUDA gate may reuse the process-local shared CudaParticleState.
    // This keeps 0450/0451 validation from reintroducing a full H2D upload
    // when the resident/shared state is already authoritative.
    std::uint64_t upstreamSharedState0474 = 0u;
    std::uint64_t upstreamUploadSkipped0474 = 0u;
    double uploadSeconds = 0.0;

    double depositKernelSeconds = 0.0;
    double depositDownloadSeconds = 0.0;
    double compactKernelSeconds = 0.0;
    double plannerKernelSeconds = 0.0;
    double totalSeconds = 0.0;
};


// 0451: experimental CUDA upstream apply gate.  CUDA recomputes the
// deposit/classification/poor-rich compaction and planner and the solver accepts
// the CUDA upstream only when it is bitwise/roundoff-equivalent to the CPU
// workspace.  The legacy CPU workspace is kept as a mirror to feed the existing
// deterministic donor-particle operation materialization; 0448 may then mutate
// particle edits/remap/thermal on CUDA.
struct CudaResamplingUpstreamApply0451Diagnostics {
    bool attempted = false;
    bool handled = false;
    bool applied = false;
    bool pass = false;
    bool skipped = false;
    std::string skipReason;

    std::uint64_t step = 0u;
    std::string outputCsv;

    std::uint64_t nActive = 0u;
    std::uint64_t nCells = 0u;
    std::uint64_t cpuTransferPairs = 0u;
    std::uint64_t gpuTransferPairs = 0u;
    std::uint64_t cpuPassiveOps = 0u;

    std::uint64_t cellIdMismatch = 0u;
    double maxCountDiff = 0.0;
    double maxMassAbs = 0.0;
    double maxPxAbs = 0.0;
    double maxPyAbs = 0.0;
    std::uint64_t receiverListMismatch = 0u;
    std::uint64_t donorListMismatch = 0u;
    std::uint64_t planMismatch = 0u;
    double maxPlanMassAbs = 0.0;
    double maxPlanDistanceAbs = 0.0;
    double cpuPlannedMass = 0.0;
    double gpuPlannedMass = 0.0;

    double upstreamShadowSeconds = 0.0;
    double totalSeconds = 0.0;
};


// 0453: experimental CUDA donor-particle operation materializer.  CUDA scans
// active fluid particles and materializes the passive extraction/insertion
// operation list from the accepted transfer plan.  A strict CPU/GPU operation
// gate is kept; when it passes, the solver may replace the legacy CPU-built
// operation vector by the CUDA-materialized one before the 0448 apply backend.
struct CudaResamplingOperationMaterialize0453Diagnostics {
    bool attempted = false;
    bool handled = false;
    bool applied = false;
    bool pass = false;
    bool skipped = false;
    std::string skipReason;

    std::uint64_t step = 0u;
    std::string outputCsv;

    std::uint64_t nActive = 0u;
    std::uint64_t planEntries = 0u;
    std::uint64_t cpuOps = 0u;
    std::uint64_t gpuOps = 0u;
    std::uint64_t invalidOps = 0u;
    std::uint64_t opMismatch = 0u;
    std::uint64_t duplicateParticleMismatch = 0u;

    double maxMassAbs = 0.0;
    double maxPxAbs = 0.0;
    double maxPyAbs = 0.0;
    double cpuMass = 0.0;
    double gpuMass = 0.0;
    double cpuPx = 0.0;
    double gpuPx = 0.0;
    double cpuPy = 0.0;
    double gpuPy = 0.0;
    double cpuKe = 0.0;
    double gpuKe = 0.0;

    double uploadSeconds = 0.0;
    double kernelSeconds = 0.0;
    double downloadSeconds = 0.0;
    double totalSeconds = 0.0;
};


#if defined(MPCD_ENABLE_CUDA_RESAMPLING) && defined(MPCD_ENABLE_CUDA_PARTICLE_STATE)

bool cuda_resampling_pipeline_shadow_0445_requested(std::uint64_t step);
bool cuda_resampling_pipeline_apply_0448_requested();
bool cuda_resampling_upstream_shadow_0450_requested(std::uint64_t step);
bool cuda_resampling_upstream_apply_0451_requested(std::uint64_t step);
bool cuda_resampling_operation_materialize_0453_requested(std::uint64_t step);

CudaResamplingUpstreamShadow0450Diagnostics try_run_cuda_resampling_upstream_shadow_0450(
    const ParticleState& state,
    const SimulationParams& params,
    const CellGrid& grid,
    std::uint64_t step,
    const WeightedRealFluidDepositWorkspace& cpuWorkspace,
    const WeightedResamplingDiagnostics& cpuDiagnostics);

CudaResamplingUpstreamApply0451Diagnostics try_apply_cuda_resampling_upstream_plan_0451(
    const ParticleState& state,
    const SimulationParams& params,
    const CellGrid& grid,
    std::uint64_t step,
    WeightedRealFluidDepositWorkspace& upstreamWorkspace,
    WeightedResamplingDiagnostics& upstreamDiagnostics);


CudaResamplingOperationMaterialize0453Diagnostics try_apply_cuda_resampling_operation_materializer_0453(
    const ParticleState& state,
    const SimulationParams& params,
    const CellGrid& grid,
    std::uint64_t step,
    WeightedRealFluidDepositWorkspace& operationWorkspace);

CudaResamplingPipelineApply0448Diagnostics try_apply_cuda_resampling_pipeline_particle_edits_0448(
    ParticleState& state,
    const SimulationParams& params,
    const CellGrid& grid,
    std::uint64_t step,
    const WeightedRealFluidDepositWorkspace& editWorkspace,
    ResamplingExtractionApplyDiagnostics& extractionApply,
    ResamplingInsertionApplyDiagnostics& insertionApply);

CudaResamplingPipelineApply0448Diagnostics try_apply_cuda_resampling_pipeline_remap_thermal_0448(
    ParticleState& state,
    const SimulationParams& params,
    const WeightedRealFluidDepositWorkspace& remapWorkspace,
    const WeightedResamplingDiagnostics& remapDepositDiagnostics,
    double massCorrectionStrength,
    double targetCellMassOverride,
    std::uint64_t step,
    ResamplingRemapApplyDiagnostics& remapApply,
    ResamplingThermalRenormalizationDiagnostics& thermalApply);

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
inline bool cuda_resampling_pipeline_apply_0448_requested() { return false; }
inline bool cuda_resampling_upstream_shadow_0450_requested(std::uint64_t) { return false; }
inline bool cuda_resampling_upstream_apply_0451_requested(std::uint64_t) { return false; }
inline bool cuda_resampling_operation_materialize_0453_requested(std::uint64_t) { return false; }

inline CudaResamplingUpstreamShadow0450Diagnostics try_run_cuda_resampling_upstream_shadow_0450(
    const ParticleState&, const SimulationParams&, const CellGrid&, std::uint64_t,
    const WeightedRealFluidDepositWorkspace&, const WeightedResamplingDiagnostics&) {
    return CudaResamplingUpstreamShadow0450Diagnostics{};
}

inline CudaResamplingUpstreamApply0451Diagnostics try_apply_cuda_resampling_upstream_plan_0451(
    const ParticleState&, const SimulationParams&, const CellGrid&, std::uint64_t,
    WeightedRealFluidDepositWorkspace&, WeightedResamplingDiagnostics&) {
    return CudaResamplingUpstreamApply0451Diagnostics{};
}

inline CudaResamplingOperationMaterialize0453Diagnostics try_apply_cuda_resampling_operation_materializer_0453(
    const ParticleState&, const SimulationParams&, const CellGrid&, std::uint64_t,
    WeightedRealFluidDepositWorkspace&) {
    return CudaResamplingOperationMaterialize0453Diagnostics{};
}

inline CudaResamplingPipelineApply0448Diagnostics try_apply_cuda_resampling_pipeline_particle_edits_0448(
    ParticleState&, const SimulationParams&, const CellGrid&, std::uint64_t, const WeightedRealFluidDepositWorkspace&,
    ResamplingExtractionApplyDiagnostics&, ResamplingInsertionApplyDiagnostics&) {
    return CudaResamplingPipelineApply0448Diagnostics{};
}

inline CudaResamplingPipelineApply0448Diagnostics try_apply_cuda_resampling_pipeline_remap_thermal_0448(
    ParticleState&, const SimulationParams&, const WeightedRealFluidDepositWorkspace&, const WeightedResamplingDiagnostics&,
    double, double, std::uint64_t, ResamplingRemapApplyDiagnostics&, ResamplingThermalRenormalizationDiagnostics&) {
    return CudaResamplingPipelineApply0448Diagnostics{};
}

inline CudaResamplingPipelineShadow0445Diagnostics try_run_cuda_resampling_pipeline_shadow_0445(
    const ParticleState&, const ParticleState&, const SimulationParams&, const CellGrid&, const FluidDomainBounds&,
    double, std::uint64_t, const char*, const WeightedRealFluidDepositWorkspace&, const WeightedRealFluidDepositWorkspace&,
    const WeightedResamplingDiagnostics&, const ResamplingExtractionApplyDiagnostics&, const ResamplingInsertionApplyDiagnostics&,
    const ResamplingRemapApplyDiagnostics&, const ResamplingThermalRenormalizationDiagnostics&) {
    return CudaResamplingPipelineShadow0445Diagnostics{};
}

#endif

} // namespace mpcd
