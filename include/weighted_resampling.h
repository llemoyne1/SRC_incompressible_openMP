#pragma once

#include <cstdint>
#include <limits>
#include <vector>

#include "cell_grid.h"
#include "fluid_domain.h"
#include "particle_state.h"
#include "simulation_params.h"

namespace mpcd {

constexpr std::uint64_t kInvalidParticleIndex = std::numeric_limits<std::uint64_t>::max();
constexpr std::int32_t kInvalidCellIndex = -1;

struct ResamplingParticlePoolDiagnostics {
    bool built = false;

    std::uint64_t storageSlots = 0;
    std::uint64_t nFluid = 0;
    std::uint64_t nLatent = 0;
    std::uint64_t nInactive = 0;

    std::uint64_t freeSlots = 0;
    std::uint64_t latentSlots = 0;
    std::uint64_t fluidSlots = 0;

    std::uint64_t firstFreeIndex = kInvalidParticleIndex;
    std::uint64_t lastFreeIndex = kInvalidParticleIndex;

    double freeSlotFraction = 0.0;
    double dormantSlotFraction = 0.0;
};

struct ResamplingParticlePoolWorkspace {
    std::uint64_t allocatedParticles = 0;

    // Stack of slots immediately available for future insertion.  The list is
    // rebuilt from role=Inactive and is not yet consumed by this passive patch.
    std::vector<std::uint64_t> freeInactiveSlots;

    // Auxiliary role-index lists used by smoke tests and future wet/dry logic.
    std::vector<std::uint64_t> latentSlots;
    std::vector<std::uint64_t> fluidSlots;

    ResamplingParticlePoolDiagnostics diagnostics;
};

struct ResamplingTransferPlanEntry {
    std::int32_t donorCell = kInvalidCellIndex;
    std::int32_t receiverCell = kInvalidCellIndex;
    double plannedMass = 0.0;
    double cellDistance = 0.0;
    double donorRemainingAfter = 0.0;
    double receiverRemainingAfter = 0.0;
};

// Real-fluid weighted deposit used by the resampling branch.
//
// This deposit is deliberately distinct from CollisionWorkspace:
//   - it includes only true active particles with role=Fluid;
//   - it excludes wall virtual particles and immersed-solid virtual particles;
//   - it is intended for future resampling/pool/wet-dry decisions and for
//     diagnostics of the transported fluid mass.
struct WeightedRealFluidDepositWorkspace {
    std::uint64_t allocatedParticles = 0;
    int allocatedCells = 0;
    int allocatedThreads = 0;

    std::vector<int> cellId;

    std::vector<std::uint32_t> count;
    std::vector<double> mass;
    std::vector<double> px;
    std::vector<double> py;
    std::vector<double> ux;
    std::vector<double> uy;

    std::vector<std::uint32_t> localCount;
    std::vector<double> localMass;
    std::vector<double> localPx;
    std::vector<double> localPy;

    // Passive cell classification prepared by patch 0114.  These masks are
    // diagnostic only at this stage: no particle is moved or reweighted.
    std::vector<std::uint8_t> activeCell;
    std::vector<std::uint8_t> wetCell;
    std::vector<std::uint8_t> dryCell;
    std::vector<std::uint8_t> poorCell;
    std::vector<std::uint8_t> richCell;
    std::vector<std::uint8_t> targetBandCell;

    // Passive receiver/donor lists prepared by patch 0115.  The lists are
    // rebuilt from the 0114 masks but are not consumed yet.
    std::vector<std::int32_t> receiverPoorCells;
    std::vector<std::int32_t> donorRichCells;
    std::vector<std::int32_t> emptyWetReceiverCells;

    // Passive local donor->receiver transfer plan prepared by patch 0116.
    // Entries are diagnostic only: no mass, momentum, role or pool state is
    // changed by this plan builder.
    std::vector<ResamplingTransferPlanEntry> transferPlan;
};

struct WeightedResamplingDiagnostics {
    bool computed = false;

    std::uint64_t nFluid = 0;
    std::uint64_t nLatent = 0;
    std::uint64_t nInactive = 0;
    std::uint64_t nCells = 0;
    std::uint64_t nNonEmptyCells = 0;
    std::uint64_t nEmptyCells = 0;

    std::uint32_t minN = 0;
    std::uint32_t maxN = 0;
    double meanN = 0.0;
    double stdN = 0.0;

    double totalMass = 0.0;
    double totalPx = 0.0;
    double totalPy = 0.0;
    double meanMass = 0.0;
    double stdMass = 0.0;
    double minMass = 0.0;
    double maxMass = 0.0;

    double targetCellMass = 0.0;
    double mRelRms = 0.0;
    double mRelMaxAbs = 0.0;

    double meanUx = 0.0;
    double meanUy = 0.0;
    double cellUxRms = 0.0;
    double cellUyRms = 0.0;

    bool cellClassificationComputed = false;
    std::uint64_t nActiveCells = 0;
    std::uint64_t nWetCells = 0;
    std::uint64_t nDryCells = 0;
    std::uint64_t nPoorCells = 0;
    std::uint64_t nRichCells = 0;
    std::uint64_t nTargetBandCells = 0;
    std::uint64_t nEmptyWetCells = 0;
    std::uint64_t nOccupiedDryCells = 0;
    double wetMassThreshold = 0.0;
    double poorMassThreshold = 0.0;
    double richMassThreshold = 0.0;
    double wetCellFraction = 0.0;
    double dryCellFraction = 0.0;
    double poorCellFraction = 0.0;
    double richCellFraction = 0.0;
    double emptyWetCellFraction = 0.0;

    // Passive donor/receiver candidate lists (patch 0115).  Poor wet cells are
    // receivers; rich wet cells are donors.  These diagnostics quantify the
    // future extraction/insertion problem but do not modify particles.
    bool candidateListsBuilt = false;
    std::uint64_t nReceiverCells = 0;
    std::uint64_t nDonorCells = 0;
    std::uint64_t nEmptyWetReceiverCells = 0;
    std::int32_t firstReceiverCell = kInvalidCellIndex;
    std::int32_t lastReceiverCell = kInvalidCellIndex;
    std::int32_t firstDonorCell = kInvalidCellIndex;
    std::int32_t lastDonorCell = kInvalidCellIndex;
    double receiverMassDeficitToTarget = 0.0;
    double donorMassExcessAboveTarget = 0.0;
    double donorReceiverMassBalance = 0.0;
    double potentialTransferMass = 0.0;
    double receiverFractionOfWetCells = 0.0;
    double donorFractionOfWetCells = 0.0;
    bool poolCanSeedReceivers = false;

    // Passive local donor->receiver transfer plan (patch 0116).  The plan is
    // built by sorting all donor/receiver candidate pairs by grid distance and
    // greedily assigning only the mass permitted by donor excess and receiver
    // deficit.  It is diagnostic only: the particle state is unchanged.
    bool transferPlanBuilt = false;
    std::uint64_t nTransferPairs = 0;
    std::uint64_t nAdjacentTransferPairs = 0;
    std::int32_t firstTransferDonorCell = kInvalidCellIndex;
    std::int32_t firstTransferReceiverCell = kInvalidCellIndex;
    std::int32_t lastTransferDonorCell = kInvalidCellIndex;
    std::int32_t lastTransferReceiverCell = kInvalidCellIndex;
    double plannedTransferMass = 0.0;
    double remainingReceiverDeficitAfterPlan = 0.0;
    double remainingDonorExcessAfterPlan = 0.0;
    double transferMassCoverageFraction = 0.0;
    double transferMeanCellDistance = 0.0;
    double transferMaxCellDistance = 0.0;
    bool transferPlanDonorLimited = false;
    bool transferPlanReceiverLimited = false;

    double particleMassMean = 0.0;
    double particleMassStd = 0.0;
    double particleMassRelStd = 0.0;
    double particleMassMin = 0.0;
    double particleMassMax = 0.0;

    // Passive pool/free-list diagnostics.  These are filled by the 0113 pool
    // builder and are kept with the resampling diagnostics so runtime summaries
    // have one coherent resampling block.
    bool poolBuilt = false;
    std::uint64_t poolStorageSlots = 0;
    std::uint64_t poolFreeSlots = 0;
    std::uint64_t poolLatentSlots = 0;
    std::uint64_t poolFluidSlots = 0;
    std::uint64_t poolFirstFreeIndex = kInvalidParticleIndex;
    std::uint64_t poolLastFreeIndex = kInvalidParticleIndex;
    double poolFreeSlotFraction = 0.0;
    double poolDormantSlotFraction = 0.0;
};

ResamplingParticlePoolDiagnostics rebuild_resampling_particle_pool(
    const ParticleState& state,
    ResamplingParticlePoolWorkspace& pool);

bool resampling_pool_has_free_slot(const ResamplingParticlePoolWorkspace& pool);
std::uint64_t resampling_pool_pop_free_slot(ResamplingParticlePoolWorkspace& pool);
void resampling_pool_push_free_slot(ResamplingParticlePoolWorkspace& pool, std::uint64_t index);

void attach_resampling_pool_diagnostics(WeightedResamplingDiagnostics& diagnostics,
                                        const ResamplingParticlePoolDiagnostics& poolDiagnostics);

void resize_weighted_real_fluid_deposit(WeightedRealFluidDepositWorkspace& ws,
                                        std::uint64_t numParticles,
                                        int numCells,
                                        int numThreads);

WeightedResamplingDiagnostics deposit_weighted_real_fluid(const ParticleState& state,
                                                          const SimulationParams& params,
                                                          const CellGrid& grid,
                                                          const FluidDomainBounds& domain,
                                                          double time,
                                                          const GridShift& shift,
                                                          WeightedRealFluidDepositWorkspace& ws);

} // namespace mpcd
