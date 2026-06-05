#pragma once

#include "cell_grid.h"
#include "particle_state.h"
#include "simulation_params.h"
#include "weighted_resampling.h"

#include <cstdint>

namespace mpcd {

// Patch 0240 bridge object for the active resampling edit phase.
//
// The active SRC/MPCD loop already builds the extraction/insertion plans on the
// host.  The purpose of this bridge is to let a CUDA implementation consume the
// same plans and apply the corresponding particle role/mass/velocity edits on a
// persistent CudaParticleState, avoiding the old host-wrapper push/pull pattern.
//
// handled=false means: no CUDA backend accepted the operation; call the CPU path.
// handled=true and applied=false means: CUDA backend accepted the operation but
// the current plan had nothing to do.
struct CudaResamplingPersistentActivePath0240Diagnostics {
    bool attempted = false;
    bool handled = false;
    bool applied = false;
    std::uint64_t extractionApplied = 0;
    std::uint64_t insertionApplied = 0;
    std::uint64_t allocationCalls = 0;

    // 0242 transfer accounting for the active-path bridge.  These counters are
    // deliberately diagnostic-only: the CPU fallback and validation comparisons
    // still determine correctness.
    std::uint64_t uploadCalls = 0;
    std::uint64_t downloadCalls = 0;
    std::uint64_t metadataUploadCalls = 0;
    std::uint64_t metadataCacheHits = 0;
    std::uint64_t hostToDeviceBytes = 0;
    std::uint64_t deviceToHostBytes = 0;
    std::uint64_t metadataBytesSkipped = 0;
    bool hostShadowAuthoritative = false;
    bool downloadSkipped = false;
    double uploadSeconds = 0.0;
    double downloadSeconds = 0.0;
};

CudaResamplingPersistentActivePath0240Diagnostics
try_apply_cuda_resampling_persistent_active_path_0240(
    ParticleState& state,
    ResamplingParticlePoolWorkspace& poolWorkspace,
    WeightedRealFluidDepositWorkspace& depositWorkspace,
    const WeightedResamplingDiagnostics& depositDiagnostics,
    const SimulationParams& params,
    const CellGrid& grid,
    ResamplingExtractionApplyDiagnostics& extractionDiagnostics,
    ResamplingInsertionApplyDiagnostics& insertionDiagnostics);

} // namespace mpcd
