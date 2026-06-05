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
