#include "cuda_resampling_persistent_active_path_0240.h"

namespace mpcd {

CudaResamplingPersistentActivePath0240Diagnostics
try_apply_cuda_resampling_persistent_active_path_0240(
    ParticleState& state,
    ResamplingParticlePoolWorkspace& poolWorkspace,
    WeightedRealFluidDepositWorkspace& depositWorkspace,
    const WeightedResamplingDiagnostics& depositDiagnostics,
    const SimulationParams& params,
    const CellGrid& grid,
    ResamplingExtractionApplyDiagnostics& extractionDiagnostics,
    ResamplingInsertionApplyDiagnostics& insertionDiagnostics) {
    (void)state;
    (void)poolWorkspace;
    (void)depositWorkspace;
    (void)depositDiagnostics;
    (void)params;
    (void)grid;
    (void)extractionDiagnostics;
    (void)insertionDiagnostics;

    CudaResamplingPersistentActivePath0240Diagnostics d{};
    d.attempted = true;

    // Conservative default implementation.  This file is deliberately kept as a
    // CPU-safe fallback so the patch can be compiled before the exact 0239 CUDA
    // backend symbol names are wired here.  Once connected, this function is the
    // only place that should call the 0239 persistent CudaParticleState kernels.
    d.handled = false;
    d.applied = false;
    return d;
}

} // namespace mpcd
