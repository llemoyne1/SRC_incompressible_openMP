#pragma once

#include <array>
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


constexpr std::size_t ResamplingPopulationGuardProfilePhaseCount = 25u;
constexpr std::size_t ResamplingMassGuardProfilePhaseCount = 4u;
constexpr std::size_t ResamplingDepositProfilePhaseCount = 12u;

const char* resampling_population_guard_profile_phase_name(std::size_t phaseIndex);
const char* resampling_mass_guard_profile_phase_name(std::size_t phaseIndex);
const char* resampling_deposit_profile_phase_name(std::size_t phaseIndex);

// Profiling-only context labels for deposit_weighted_real_fluid.  They do not
// alter the deposit semantics; they only classify calls in deposit_profile_0171.csv.
enum class ResamplingDepositProfileContext : std::uint8_t {
    Generic = 0,
    Initial = 1,
    PostGuard = 2,
    PostEdit = 3,
    PostRemap = 4,
    PostThermal = 5,
    MainInitial = 6,
    Count = 7
};

const char* resampling_deposit_profile_context_name(ResamplingDepositProfileContext context);

struct ResamplingPopulationGuardProfile {
    std::array<double, ResamplingPopulationGuardProfilePhaseCount> seconds{};
};

struct ResamplingMassGuardProfile {
    std::array<double, ResamplingMassGuardProfilePhaseCount> seconds{};
};

struct ResamplingDepositProfile {
    std::array<double, ResamplingDepositProfilePhaseCount> seconds{};
};

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

    // Stack of slots immediately available for future insertion.
    std::vector<std::uint64_t> freeInactiveSlots;

    // Inverse index for O(1) membership checks and removal of an explicitly
    // selected inactive slot. kInvalidParticleIndex means that the slot is not
    // currently present in freeInactiveSlots.
    std::vector<std::uint64_t> freeInactiveSlotPosition;
    std::uint64_t freeInactiveCount = 0;
    std::uint64_t freeInactiveFirstPosition = 0;

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

struct ResamplingSelectedDonorParticle {
    std::uint64_t particleIndex = kInvalidParticleIndex;
    std::int32_t donorCell = kInvalidCellIndex;
    std::int32_t receiverCell = kInvalidCellIndex;
    double particleMass = 0.0;
    double planEntryMass = 0.0;
    double selectedMassForEntryAfter = 0.0;
};

struct ResamplingPassiveExtractionOperation {
    std::uint64_t particleIndex = kInvalidParticleIndex;
    std::int32_t donorCell = kInvalidCellIndex;
    std::int32_t receiverCell = kInvalidCellIndex;
    std::uint32_t particleType = 0u;
    double particleMass = 0.0;
    double momentumX = 0.0;
    double momentumY = 0.0;
    double kineticEnergy = 0.0;
    std::uint8_t currentRole = static_cast<std::uint8_t>(ParticleRole::Fluid);
    std::uint8_t plannedRoleAfterExtraction = static_cast<std::uint8_t>(ParticleRole::Inactive);
};

struct ResamplingLatentActivationDiagnostics {
    bool attempted = false;
    bool applied = false;

    std::uint64_t receiverCellsConsidered = 0;
    std::uint64_t cellsActivated = 0;
    std::uint64_t particlesActivated = 0;
    std::uint64_t roleChanges = 0;
    std::uint64_t skippedNoLatentSlots = 0;
    std::uint64_t skippedInvalidReceiverCells = 0;
    std::uint64_t skippedReceiverNotWet = 0;
    std::uint64_t skippedReceiverNotPoor = 0;
    std::uint64_t skippedMaxPerCell = 0;

    std::uint64_t latentSlotsBefore = 0;
    std::uint64_t latentSlotsAfter = 0;
    std::uint64_t fluidSlotsBefore = 0;
    std::uint64_t fluidSlotsAfter = 0;

    double targetCellMass = 0.0;
    double activationParticleMass = 0.0;
    double activatedMass = 0.0;
    double activatedMomentumX = 0.0;
    double activatedMomentumY = 0.0;
    double activatedKineticEnergy = 0.0;

    std::uint64_t firstActivatedParticle = kInvalidParticleIndex;
    std::uint64_t lastActivatedParticle = kInvalidParticleIndex;
    std::int32_t firstActivatedCell = kInvalidCellIndex;
    std::int32_t lastActivatedCell = kInvalidCellIndex;
    bool allSourcesWereLatent = true;
    bool noDryCellsActivated = true;
};

struct ResamplingInsertionApplyDiagnostics {
    bool attempted = false;
    bool applied = false;

    std::uint64_t operationsConsidered = 0;
    std::uint64_t operationsApplied = 0;
    std::uint64_t roleChanges = 0;
    std::uint64_t skippedInvalidSourceParticles = 0;
    std::uint64_t skippedSourceNotInactive = 0;
    std::uint64_t skippedInvalidReceiverCells = 0;
    std::uint64_t skippedNoFreeSlots = 0;
    std::uint64_t skippedInvalidMass = 0;

    std::uint64_t poolFreeSlotsBefore = 0;
    std::uint64_t poolFreeSlotsAfter = 0;
    std::uint64_t poolFreeSlotDelta = 0;

    double insertedMass = 0.0;
    double insertedMomentumX = 0.0;
    double insertedMomentumY = 0.0;
    double insertedKineticEnergy = 0.0;
    double plannedInsertionMass = 0.0;
    double massResidualVsPlan = 0.0;

    std::uint64_t firstInsertedParticle = kInvalidParticleIndex;
    std::uint64_t lastInsertedParticle = kInvalidParticleIndex;
    std::int32_t firstInsertionReceiverCell = kInvalidCellIndex;
    std::int32_t lastInsertionReceiverCell = kInvalidCellIndex;
    bool noInvalidReceiverCells = true;
    bool allSourcesWereInactive = true;
};

struct ResamplingRemapApplyDiagnostics {
    bool attempted = false;
    bool applied = false;

    std::uint64_t cellsConsidered = 0;
    std::uint64_t cellsRemapped = 0;
    std::uint64_t particlesRemapped = 0;
    std::uint64_t skippedDryCells = 0;
    std::uint64_t skippedEmptyCells = 0;
    std::uint64_t skippedInvalidMassCells = 0;

    double targetCellMass = 0.0;
    double massCorrectionStrength = 1.0;

    // 0490d phase-aware local closure diagnostics. The legacy scalar fields
    // above remain the nominal/global inputs; these ranges describe the actual
    // cell-local targets and strengths used when the opt-in policy is active.
    bool speciesMassClosureActive = false;
    std::uint64_t speciesMassClosureCells = 0;
    double speciesTargetCellMassMin = 0.0;
    double speciesTargetCellMassMax = 0.0;
    double speciesClosureStrengthMin = 0.0;
    double speciesClosureStrengthMax = 0.0;
    double massBefore = 0.0;
    double massAfter = 0.0;
    double massTargetSum = 0.0;
    double massDelta = 0.0;

    double momentumXBefore = 0.0;
    double momentumYBefore = 0.0;
    double momentumXAfter = 0.0;
    double momentumYAfter = 0.0;
    double momentumXTarget = 0.0;
    double momentumYTarget = 0.0;
    double momentumResidualRms = 0.0;
    double momentumResidualMaxAbs = 0.0;

    double maxCellMassRelResidual = 0.0;
    double scaleMin = 1.0;
    double scaleMax = 1.0;
    std::int32_t firstRemappedCell = kInvalidCellIndex;
    std::int32_t lastRemappedCell = kInvalidCellIndex;
    bool allRemappedCellsNonEmpty = true;
};

struct ResamplingThermalRenormalizationDiagnostics {
    bool attempted = false;
    bool applied = false;

    std::uint64_t cellsConsidered = 0;
    std::uint64_t cellsRenormalized = 0;
    std::uint64_t particlesRenormalized = 0;
    std::uint64_t skippedDryCells = 0;
    std::uint64_t skippedEmptyCells = 0;
    std::uint64_t skippedInvalidEnergyCells = 0;

    double targetThermalEnergy = 0.0;
    double thermalEnergyBefore = 0.0;
    double thermalEnergyAfter = 0.0;
    double thermalEnergyResidualRms = 0.0;
    double thermalEnergyResidualMaxAbs = 0.0;
    double velocityScaleMin = 1.0;
    double velocityScaleMax = 1.0;

    double momentumResidualRms = 0.0;
    double momentumResidualMaxAbs = 0.0;
    std::int32_t firstRenormalizedCell = kInvalidCellIndex;
    std::int32_t lastRenormalizedCell = kInvalidCellIndex;
    bool allRenormalizedCellsNonEmpty = true;
};


struct ResamplingMassGuardDiagnostics {
    bool attempted = false;
    ResamplingMassGuardProfile profile{};
    bool applied = false;

    std::uint64_t cellsConsidered = 0;
    std::uint64_t cellsGuarded = 0;
    std::uint64_t particlesConsidered = 0;
    std::uint64_t particlesAdjusted = 0;
    std::uint64_t skippedDryCells = 0;
    std::uint64_t skippedEmptyCells = 0;
    std::uint64_t skippedInfeasibleCells = 0;
    std::uint64_t skippedInvalidMassCells = 0;

    double massMinBound = 0.0;
    double massMaxBound = 0.0;
    double targetCellMass = 0.0;
    double massCorrectionStrength = 1.0;
    double massBefore = 0.0;
    double massAfter = 0.0;
    double massTargetSum = 0.0;
    double massResidualRms = 0.0;
    double massResidualMaxAbs = 0.0;

    double particleMassMinBefore = 0.0;
    double particleMassMaxBefore = 0.0;
    double particleMassMinAfter = 0.0;
    double particleMassMaxAfter = 0.0;
    std::uint64_t particlesBelowMinBefore = 0;
    std::uint64_t particlesAboveMaxBefore = 0;
    std::uint64_t particlesBelowMinAfter = 0;
    std::uint64_t particlesAboveMaxAfter = 0;
    std::uint64_t particlesAtMinAfter = 0;
    std::uint64_t particlesAtMaxAfter = 0;

    double thermalEnergyTarget = 0.0;
    double thermalEnergyBefore = 0.0;
    double thermalEnergyAfter = 0.0;
    double thermalEnergyResidualRms = 0.0;
    double thermalEnergyResidualMaxAbs = 0.0;
    double velocityScaleMin = 1.0;
    double velocityScaleMax = 1.0;

    double momentumResidualRms = 0.0;
    double momentumResidualMaxAbs = 0.0;
    std::int32_t firstGuardedCell = kInvalidCellIndex;
    std::int32_t lastGuardedCell = kInvalidCellIndex;
    bool allGuardedCellsFeasible = true;
};

struct ResamplingExtractionApplyDiagnostics {
    bool attempted = false;
    bool applied = false;

    std::uint64_t operationsConsidered = 0;
    std::uint64_t operationsApplied = 0;
    std::uint64_t roleChanges = 0;
    std::uint64_t skippedInvalidParticles = 0;
    std::uint64_t skippedNonFluidParticles = 0;
    std::uint64_t skippedDuplicateParticles = 0;

    std::uint64_t poolFreeSlotsBefore = 0;
    std::uint64_t poolFreeSlotsAfter = 0;
    std::uint64_t poolFreeSlotDelta = 0;

    double appliedMass = 0.0;
    double appliedMomentumX = 0.0;
    double appliedMomentumY = 0.0;
    double appliedKineticEnergy = 0.0;
    double plannedExtractionMass = 0.0;
    double massResidualVsPlan = 0.0;

    std::uint64_t firstAppliedParticle = kInvalidParticleIndex;
    std::uint64_t lastAppliedParticle = kInvalidParticleIndex;
    bool noDuplicateParticles = true;
    bool allAppliedWereFluid = true;
};


struct ResamplingPopulationGuardDiagnostics {
    bool attempted = false;
    ResamplingPopulationGuardProfile profile{};
    bool applied = false;

    int nMin = 0;
    int nTarget = 0;
    int nMax = 0;

    std::uint64_t wetCellsConsidered = 0;
    std::uint64_t underfullCells = 0;
    std::uint64_t emptyUnderfullCells = 0;
    std::uint64_t overfullCells = 0;
    std::uint64_t cellsSplit = 0;
    std::uint64_t cellsExtracted = 0;

    // 0166 profiling/optimization counters: candidates are the cells selected
    // by the light pre-scan before the mutating overfull/underfull loops;
    // edited cells are the subset on which an actual extract/split occurred.
    std::uint64_t overfullCandidateCells = 0;
    std::uint64_t underfullCandidateCells = 0;
    std::uint64_t overfullEditedCells = 0;
    std::uint64_t underfullEditedCells = 0;

    // 0168 deep population-guard profiling counters.  Candidate particle refs
    // count the particles present in cells selected by the pre-scan; scan passes
    // count repeated selection passes inside the same candidate cell; scanned
    // refs and eligible refs quantify the exact amount of per-particle work.
    std::uint64_t overfullCandidateParticleRefs = 0;
    std::uint64_t underfullCandidateParticleRefs = 0;
    std::uint64_t overfullScanPasses = 0;
    std::uint64_t underfullScanPasses = 0;
    std::uint64_t overfullParticleRefsScanned = 0;
    std::uint64_t underfullParticleRefsScanned = 0;
    std::uint64_t overfullEligibleParticleRefs = 0;
    std::uint64_t underfullEligibleParticleRefs = 0;
    std::uint32_t overfullCandidatePopulationMax = 0;
    std::uint32_t underfullCandidatePopulationMax = 0;

    std::uint64_t splitParticlesCreated = 0;
    std::uint64_t extractedParticles = 0;
    std::uint64_t skippedNoFreeSlots = 0;
    std::uint64_t skippedEmptyCells = 0;
    std::uint64_t skippedSplitLimit = 0;
    std::uint64_t skippedExtractionLimit = 0;

    std::uint64_t freeSlotsBefore = 0;
    std::uint64_t freeSlotsAfter = 0;
    std::int64_t activeParticleDelta = 0;

    double splitMass = 0.0;
    double extractedMass = 0.0;
    double splitMomentumX = 0.0;
    double splitMomentumY = 0.0;
    double extractedMomentumX = 0.0;
    double extractedMomentumY = 0.0;

    std::uint32_t wetNMinBefore = 0;
    std::uint32_t wetNMinAfter = 0;
    double wetNMeanBefore = 0.0;
    double wetNMeanAfter = 0.0;
    double wetNStdBefore = 0.0;
    double wetNStdAfter = 0.0;
    double wetLowNFractionBefore = 0.0;
    double wetLowNFractionAfter = 0.0;
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

    // Passive donor particle selections prepared by patch 0117.  These are
    // candidate particle indices that could be extracted from rich donor cells
    // to realize the transfer plan.  The selection is deterministic and does
    // not change role, mass, position or velocity.
    std::vector<ResamplingSelectedDonorParticle> selectedDonorParticles;

    // Passive extraction operations prepared by patch 0118.  They state which
    // selected Fluid particles would be converted to Inactive by the first
    // mutating extraction patch.  They are diagnostics only and leave all
    // roles, masses, positions and velocities unchanged.
    std::vector<ResamplingPassiveExtractionOperation> passiveExtractionOperations;

    std::vector<std::uint32_t> donorSelectedParticleCount;
    std::vector<double> donorSelectedMass;

    // Fast per-cell particle index used by the mutating resampling planner.
    // This avoids scanning all particles for every donor->receiver transfer
    // entry. It is built only when the caller requests a mutation plan.
    std::vector<std::uint64_t> cellParticleOffsets;
    std::vector<std::uint64_t> cellParticleCursor;
    std::vector<std::uint64_t> cellParticleIndices;

    // 0166 population-guard candidate lists.  They are rebuilt from the current
    // per-cell counts before the mutating guard loops, so the hot overfull and
    // underfull stages traverse only candidate cells while preserving increasing
    // cell-index order.
    std::vector<int> populationGuardOverfullCells;
    std::vector<int> populationGuardUnderfullCells;

    // Filled by the 0121 mass remap before particle masses are scaled.  Patch
    // 0122 uses this per-cell target to restore the local relative thermal
    // energy after mass scaling while preserving the remapped cell velocity.
    std::vector<double> remapThermalEnergyTarget;
    std::vector<std::uint8_t> remapThermalCell;
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

    // Passive donor-particle selection (patch 0117).  Particle indices are
    // selected deterministically from rich donor cells, following the passive
    // transfer plan.  The selected mass may overshoot the planned continuous
    // mass because individual particles are indivisible at this stage.
    bool donorParticleSelectionBuilt = false;
    std::uint64_t nSelectedDonorParticles = 0;
    std::uint64_t nDonorCellsWithSelectedParticles = 0;
    std::uint64_t maxSelectedParticlesForTransferEntry = 0;
    std::uint64_t maxSelectedParticlesPerDonorCell = 0;
    std::uint64_t firstSelectedDonorParticle = kInvalidParticleIndex;
    std::uint64_t lastSelectedDonorParticle = kInvalidParticleIndex;
    std::int32_t firstSelectedDonorCell = kInvalidCellIndex;
    std::int32_t lastSelectedDonorCell = kInvalidCellIndex;
    std::int32_t firstSelectedReceiverCell = kInvalidCellIndex;
    std::int32_t lastSelectedReceiverCell = kInvalidCellIndex;
    double selectedDonorParticleMass = 0.0;
    double selectedDonorMassOvershoot = 0.0;
    double selectedDonorMassCoverageFraction = 0.0;
    double selectedDonorMeanParticleMass = 0.0;
    double selectedDonorMaxParticleMass = 0.0;
    bool donorParticleSelectionExactOrOvershoot = false;
    bool donorParticleSelectionUnderfilled = false;

    // Passive extraction operation plan (patch 0118).  This is the last
    // non-mutating staging level before changing selected donor particles from
    // Fluid to Inactive in a future patch.
    bool extractionPlanBuilt = false;
    std::uint64_t nExtractionOperations = 0;
    std::uint64_t nExtractionParticles = 0;
    std::uint64_t nExtractionDonorCells = 0;
    std::uint64_t nExtractionReceiverCells = 0;
    std::uint64_t firstExtractionParticle = kInvalidParticleIndex;
    std::uint64_t lastExtractionParticle = kInvalidParticleIndex;
    std::int32_t firstExtractionDonorCell = kInvalidCellIndex;
    std::int32_t lastExtractionDonorCell = kInvalidCellIndex;
    std::int32_t firstExtractionReceiverCell = kInvalidCellIndex;
    std::int32_t lastExtractionReceiverCell = kInvalidCellIndex;
    double extractionMass = 0.0;
    double extractionMomentumX = 0.0;
    double extractionMomentumY = 0.0;
    double extractionKineticEnergy = 0.0;
    double extractionMeanParticleMass = 0.0;
    double extractionMaxParticleMass = 0.0;
    double extractionMassOvershoot = 0.0;
    double extractionMassCoverageFraction = 0.0;
    std::uint64_t hypotheticalPoolFreeSlotsAfterExtraction = 0;
    bool extractionAllSelectedAreFluid = false;
    bool extractionNoDuplicateParticles = false;

    // First mutating extraction application (patch 0119).  These diagnostics
    // report the actual Fluid->Inactive role changes applied from the passive
    // extraction plan.
    bool extractionApplyAttempted = false;
    bool extractionApplied = false;
    std::uint64_t extractionApplyOpsConsidered = 0;
    std::uint64_t extractionApplyOpsApplied = 0;
    std::uint64_t extractionApplyRoleChanges = 0;
    std::uint64_t extractionApplySkippedInvalidParticles = 0;
    std::uint64_t extractionApplySkippedNonFluidParticles = 0;
    std::uint64_t extractionApplySkippedDuplicateParticles = 0;
    std::uint64_t extractionApplyPoolFreeSlotsBefore = 0;
    std::uint64_t extractionApplyPoolFreeSlotsAfter = 0;
    std::uint64_t extractionApplyPoolFreeSlotDelta = 0;
    double extractionApplyMass = 0.0;
    double extractionApplyMomentumX = 0.0;
    double extractionApplyMomentumY = 0.0;
    double extractionApplyKineticEnergy = 0.0;
    double extractionApplyPlannedMass = 0.0;
    double extractionApplyMassResidualVsPlan = 0.0;
    std::uint64_t firstAppliedExtractionParticle = kInvalidParticleIndex;
    std::uint64_t lastAppliedExtractionParticle = kInvalidParticleIndex;
    bool extractionApplyNoDuplicateParticles = true;
    bool extractionApplyAllAppliedWereFluid = true;

    // First mutating insertion application (patch 0120).  These diagnostics
    // report the controlled Inactive->Fluid activation of free-list slots into
    // receiver cells, driven by the 0118 extraction operations.  It preserves
    // each extracted particle's mass, momentum and type, but still performs no
    // local remap/renormalisation.
    bool insertionApplyAttempted = false;
    bool insertionApplied = false;
    std::uint64_t insertionApplyOpsConsidered = 0;
    std::uint64_t insertionApplyOpsApplied = 0;
    std::uint64_t insertionApplyRoleChanges = 0;
    std::uint64_t insertionApplySkippedInvalidSourceParticles = 0;
    std::uint64_t insertionApplySkippedSourceNotInactive = 0;
    std::uint64_t insertionApplySkippedInvalidReceiverCells = 0;
    std::uint64_t insertionApplySkippedNoFreeSlots = 0;
    std::uint64_t insertionApplySkippedInvalidMass = 0;
    std::uint64_t insertionApplyPoolFreeSlotsBefore = 0;
    std::uint64_t insertionApplyPoolFreeSlotsAfter = 0;
    std::uint64_t insertionApplyPoolFreeSlotDelta = 0;
    double insertionApplyMass = 0.0;
    double insertionApplyMomentumX = 0.0;
    double insertionApplyMomentumY = 0.0;
    double insertionApplyKineticEnergy = 0.0;
    double insertionApplyPlannedMass = 0.0;
    double insertionApplyMassResidualVsPlan = 0.0;
    std::uint64_t firstAppliedInsertionParticle = kInvalidParticleIndex;
    std::uint64_t lastAppliedInsertionParticle = kInvalidParticleIndex;
    std::int32_t firstAppliedInsertionReceiverCell = kInvalidCellIndex;
    std::int32_t lastAppliedInsertionReceiverCell = kInvalidCellIndex;
    bool insertionApplyNoInvalidReceiverCells = true;
    bool insertionApplyAllSourcesWereInactive = true;

    // First local mass/momentum remap (patch 0121).  The remap scales masses
    // inside non-empty wet cells to target M_c while preserving cell velocity.
    bool remapApplyAttempted = false;
    bool remapApplied = false;
    std::uint64_t remapCellsConsidered = 0;
    std::uint64_t remapCellsRemapped = 0;
    std::uint64_t remapParticlesRemapped = 0;
    std::uint64_t remapSkippedDryCells = 0;
    std::uint64_t remapSkippedEmptyCells = 0;
    std::uint64_t remapSkippedInvalidMassCells = 0;
    double remapTargetCellMass = 0.0;
    double remapMassCorrectionStrength = 1.0;
    double remapMassBefore = 0.0;
    double remapMassAfter = 0.0;
    double remapMassTargetSum = 0.0;
    double remapMassDelta = 0.0;
    double remapMomentumXBefore = 0.0;
    double remapMomentumYBefore = 0.0;
    double remapMomentumXAfter = 0.0;
    double remapMomentumYAfter = 0.0;
    double remapMomentumXTarget = 0.0;
    double remapMomentumYTarget = 0.0;
    double remapMomentumResidualRms = 0.0;
    double remapMomentumResidualMaxAbs = 0.0;
    double remapMaxCellMassRelResidual = 0.0;
    double remapScaleMin = 1.0;
    double remapScaleMax = 1.0;
    std::int32_t firstRemappedCell = kInvalidCellIndex;
    std::int32_t lastRemappedCell = kInvalidCellIndex;
    bool remapAllRemappedCellsNonEmpty = true;

    // Local thermal renormalisation (patch 0122).  After mass scaling, relative
    // velocities are scaled about the remapped cell velocity so E_th,c matches
    // the pre-mass-remap target recorded in the workspace.
    bool thermalRenormAttempted = false;
    bool thermalRenormApplied = false;
    std::uint64_t thermalRenormCellsConsidered = 0;
    std::uint64_t thermalRenormCellsRenormalized = 0;
    std::uint64_t thermalRenormParticlesRenormalized = 0;
    std::uint64_t thermalRenormSkippedDryCells = 0;
    std::uint64_t thermalRenormSkippedEmptyCells = 0;
    std::uint64_t thermalRenormSkippedInvalidEnergyCells = 0;
    double thermalRenormTargetEnergy = 0.0;
    double thermalRenormEnergyBefore = 0.0;
    double thermalRenormEnergyAfter = 0.0;
    double thermalRenormEnergyResidualRms = 0.0;
    double thermalRenormEnergyResidualMaxAbs = 0.0;
    double thermalRenormVelocityScaleMin = 1.0;
    double thermalRenormVelocityScaleMax = 1.0;
    double thermalRenormMomentumResidualRms = 0.0;
    double thermalRenormMomentumResidualMaxAbs = 0.0;
    std::int32_t firstThermalRenormCell = kInvalidCellIndex;
    std::int32_t lastThermalRenormCell = kInvalidCellIndex;
    bool thermalRenormAllCellsNonEmpty = true;

    // Particle-mass guard and bounded local renormalisation (patch 0123).
    // After extraction/insertion/remap/thermalisation, masses are projected
    // inside [m_min,m_max] while preserving M_c; velocities are then recentered
    // and rescaled so U_c and E_th,c are restored.
    bool massGuardAttempted = false;
    bool massGuardApplied = false;
    std::uint64_t massGuardCellsConsidered = 0;
    std::uint64_t massGuardCellsGuarded = 0;
    std::uint64_t massGuardParticlesConsidered = 0;
    std::uint64_t massGuardParticlesAdjusted = 0;
    std::uint64_t massGuardSkippedDryCells = 0;
    std::uint64_t massGuardSkippedEmptyCells = 0;
    std::uint64_t massGuardSkippedInfeasibleCells = 0;
    std::uint64_t massGuardSkippedInvalidMassCells = 0;
    double massGuardMinBound = 0.0;
    double massGuardMaxBound = 0.0;
    double massGuardTargetCellMass = 0.0;
    double massGuardMassBefore = 0.0;
    double massGuardMassAfter = 0.0;
    double massGuardMassTargetSum = 0.0;
    double massGuardMassResidualRms = 0.0;
    double massGuardMassResidualMaxAbs = 0.0;
    double massGuardParticleMassMinBefore = 0.0;
    double massGuardParticleMassMaxBefore = 0.0;
    double massGuardParticleMassMinAfter = 0.0;
    double massGuardParticleMassMaxAfter = 0.0;
    std::uint64_t massGuardParticlesBelowMinBefore = 0;
    std::uint64_t massGuardParticlesAboveMaxBefore = 0;
    std::uint64_t massGuardParticlesBelowMinAfter = 0;
    std::uint64_t massGuardParticlesAboveMaxAfter = 0;
    std::uint64_t massGuardParticlesAtMinAfter = 0;
    std::uint64_t massGuardParticlesAtMaxAfter = 0;
    double massGuardThermalEnergyTarget = 0.0;
    double massGuardThermalEnergyBefore = 0.0;
    double massGuardThermalEnergyAfter = 0.0;
    double massGuardThermalEnergyResidualRms = 0.0;
    double massGuardThermalEnergyResidualMaxAbs = 0.0;
    double massGuardVelocityScaleMin = 1.0;
    double massGuardVelocityScaleMax = 1.0;
    double massGuardMomentumResidualRms = 0.0;
    double massGuardMomentumResidualMaxAbs = 0.0;
    std::int32_t firstMassGuardedCell = kInvalidCellIndex;
    std::int32_t lastMassGuardedCell = kInvalidCellIndex;
    bool massGuardAllCellsFeasible = true;
    std::array<double, ResamplingMassGuardProfilePhaseCount> massGuardProfileSeconds{};

    // 0171 fine-grained profile for the last weighted real-fluid deposit call
    // represented by this diagnostics object.  Aggregated per-context profiles
    // are written by the deposit profiler at process exit.
    std::array<double, ResamplingDepositProfilePhaseCount> depositProfileSeconds{};
    std::uint64_t depositProfileParticlesVisited = 0;
    std::uint64_t depositProfileFluidParticles = 0;
    std::uint64_t depositProfileCells = 0;
    bool depositProfileBuildMutationPlan = false;

    // Latent -> Fluid wet/dry activation (patch 0124).  This optional stage
    // consumes only role=Latent particles and seeds poor/empty wet receiver
    // cells.  It is separated from the Inactive pool so extraction/insertion
    // recycling remains conservative when latent activation is disabled.
    bool latentActivationAttempted = false;
    bool latentActivationApplied = false;
    std::uint64_t latentActivationReceiverCellsConsidered = 0;
    std::uint64_t latentActivationCellsActivated = 0;
    std::uint64_t latentActivationParticlesActivated = 0;
    std::uint64_t latentActivationRoleChanges = 0;
    std::uint64_t latentActivationSkippedNoLatentSlots = 0;
    std::uint64_t latentActivationSkippedInvalidReceiverCells = 0;
    std::uint64_t latentActivationSkippedReceiverNotWet = 0;
    std::uint64_t latentActivationSkippedReceiverNotPoor = 0;
    std::uint64_t latentActivationSkippedMaxPerCell = 0;
    std::uint64_t latentActivationLatentSlotsBefore = 0;
    std::uint64_t latentActivationLatentSlotsAfter = 0;
    std::uint64_t latentActivationFluidSlotsBefore = 0;
    std::uint64_t latentActivationFluidSlotsAfter = 0;
    double latentActivationTargetCellMass = 0.0;
    double latentActivationParticleMass = 0.0;
    double latentActivationMass = 0.0;
    double latentActivationMomentumX = 0.0;
    double latentActivationMomentumY = 0.0;
    double latentActivationKineticEnergy = 0.0;
    std::uint64_t firstLatentActivatedParticle = kInvalidParticleIndex;
    std::uint64_t lastLatentActivatedParticle = kInvalidParticleIndex;
    std::int32_t firstLatentActivatedCell = kInvalidCellIndex;
    std::int32_t lastLatentActivatedCell = kInvalidCellIndex;
    bool latentActivationAllSourcesWereLatent = true;
    bool latentActivationNoDryCellsActivated = true;

    // Population-support guard diagnostics (patch 0140).  This is the
    // MATLAB-compatible Nmin/Ntarget/Nmax discrete resampling stage.
    bool populationGuardAttempted = false;
    bool populationGuardApplied = false;
    int populationGuardNMin = 0;
    int populationGuardNTarget = 0;
    int populationGuardNMax = 0;
    std::uint64_t populationGuardWetCellsConsidered = 0;
    std::uint64_t populationGuardUnderfullCells = 0;
    std::uint64_t populationGuardEmptyUnderfullCells = 0;
    std::uint64_t populationGuardOverfullCells = 0;
    std::uint64_t populationGuardCellsSplit = 0;
    std::uint64_t populationGuardCellsExtracted = 0;
    std::uint64_t populationGuardOverfullCandidateCells = 0;
    std::uint64_t populationGuardUnderfullCandidateCells = 0;
    std::uint64_t populationGuardOverfullEditedCells = 0;
    std::uint64_t populationGuardUnderfullEditedCells = 0;
    std::uint64_t populationGuardOverfullCandidateParticleRefs = 0;
    std::uint64_t populationGuardUnderfullCandidateParticleRefs = 0;
    std::uint64_t populationGuardOverfullScanPasses = 0;
    std::uint64_t populationGuardUnderfullScanPasses = 0;
    std::uint64_t populationGuardOverfullParticleRefsScanned = 0;
    std::uint64_t populationGuardUnderfullParticleRefsScanned = 0;
    std::uint64_t populationGuardOverfullEligibleParticleRefs = 0;
    std::uint64_t populationGuardUnderfullEligibleParticleRefs = 0;
    std::uint32_t populationGuardOverfullCandidatePopulationMax = 0;
    std::uint32_t populationGuardUnderfullCandidatePopulationMax = 0;
    std::uint64_t populationGuardSplitParticlesCreated = 0;
    std::uint64_t populationGuardExtractedParticles = 0;
    std::uint64_t populationGuardSkippedNoFreeSlots = 0;
    std::uint64_t populationGuardSkippedEmptyCells = 0;
    std::uint64_t populationGuardSkippedSplitLimit = 0;
    std::uint64_t populationGuardSkippedExtractionLimit = 0;
    std::uint64_t populationGuardFreeSlotsBefore = 0;
    std::uint64_t populationGuardFreeSlotsAfter = 0;
    std::int64_t populationGuardActiveParticleDelta = 0;
    double populationGuardSplitMass = 0.0;
    double populationGuardExtractedMass = 0.0;
    double populationGuardWetNMeanBefore = 0.0;
    double populationGuardWetNMeanAfter = 0.0;
    double populationGuardWetNStdBefore = 0.0;
    double populationGuardWetNStdAfter = 0.0;
    std::uint32_t populationGuardWetNMinBefore = 0;
    std::uint32_t populationGuardWetNMinAfter = 0;
    double populationGuardWetLowNFractionBefore = 0.0;
    double populationGuardWetLowNFractionAfter = 0.0;
    std::array<double, ResamplingPopulationGuardProfilePhaseCount> populationGuardProfileSeconds{};

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
std::uint64_t resampling_pool_free_slot_count(const ResamplingParticlePoolWorkspace& pool);
std::uint64_t resampling_pool_pop_free_slot(ResamplingParticlePoolWorkspace& pool);
void resampling_pool_push_free_slot(ResamplingParticlePoolWorkspace& pool, std::uint64_t index);
bool resampling_pool_remove_free_slot(ResamplingParticlePoolWorkspace& pool, std::uint64_t index);

void attach_resampling_pool_diagnostics(WeightedResamplingDiagnostics& diagnostics,
                                        const ResamplingParticlePoolDiagnostics& poolDiagnostics);

ResamplingLatentActivationDiagnostics apply_resampling_latent_activation(
    ParticleState& state,
    ResamplingParticlePoolWorkspace& pool,
    const WeightedRealFluidDepositWorkspace& depositWorkspace,
    const WeightedResamplingDiagnostics& depositDiagnostics,
    const SimulationParams& params,
    const CellGrid& grid);

void attach_resampling_latent_activation_diagnostics(
    WeightedResamplingDiagnostics& diagnostics,
    const ResamplingLatentActivationDiagnostics& activationDiagnostics);

ResamplingExtractionApplyDiagnostics apply_resampling_extraction_operations(
    ParticleState& state,
    ResamplingParticlePoolWorkspace& pool,
    const WeightedRealFluidDepositWorkspace& depositWorkspace);

void attach_resampling_extraction_apply_diagnostics(
    WeightedResamplingDiagnostics& diagnostics,
    const ResamplingExtractionApplyDiagnostics& extractionDiagnostics);

ResamplingInsertionApplyDiagnostics apply_resampling_insertion_operations(
    ParticleState& state,
    ResamplingParticlePoolWorkspace& pool,
    const WeightedRealFluidDepositWorkspace& depositWorkspace,
    const CellGrid& grid);

void attach_resampling_insertion_apply_diagnostics(
    WeightedResamplingDiagnostics& diagnostics,
    const ResamplingInsertionApplyDiagnostics& insertionDiagnostics);

ResamplingPopulationGuardDiagnostics apply_resampling_population_support_guard(
    ParticleState& state,
    ResamplingParticlePoolWorkspace& pool,
    WeightedRealFluidDepositWorkspace& depositWorkspace,
    const WeightedResamplingDiagnostics& depositDiagnostics,
    const SimulationParams& params,
    const CellGrid& grid);

void attach_resampling_population_guard_diagnostics(
    WeightedResamplingDiagnostics& diagnostics,
    const ResamplingPopulationGuardDiagnostics& populationDiagnostics);

ResamplingRemapApplyDiagnostics apply_resampling_local_mass_momentum_remap(
    ParticleState& state,
    WeightedRealFluidDepositWorkspace& depositWorkspace,
    const WeightedResamplingDiagnostics& depositDiagnostics,
    double massCorrectionStrength = 1.0,
    double targetCellMassOverride = -1.0,
    const SimulationParams* speciesPolicyParams = nullptr);

void attach_resampling_remap_apply_diagnostics(
    WeightedResamplingDiagnostics& diagnostics,
    const ResamplingRemapApplyDiagnostics& remapDiagnostics);

ResamplingThermalRenormalizationDiagnostics apply_resampling_local_thermal_renormalization(
    ParticleState& state,
    const WeightedRealFluidDepositWorkspace& depositWorkspace,
    const ResamplingRemapApplyDiagnostics& remapDiagnostics);

void attach_resampling_thermal_renormalization_diagnostics(
    WeightedResamplingDiagnostics& diagnostics,
    const ResamplingThermalRenormalizationDiagnostics& thermalDiagnostics);

ResamplingMassGuardDiagnostics apply_resampling_particle_mass_guards(
    ParticleState& state,
    const SimulationParams& params,
    const WeightedRealFluidDepositWorkspace& depositWorkspace,
    const WeightedResamplingDiagnostics& depositDiagnostics,
    double targetCellMassOverride = -1.0);

void attach_resampling_mass_guard_diagnostics(
    WeightedResamplingDiagnostics& diagnostics,
    const ResamplingMassGuardDiagnostics& massGuardDiagnostics);

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
                                                          WeightedRealFluidDepositWorkspace& ws,
                                                          bool buildMutationPlan = true,
                                                          ResamplingDepositProfileContext profileContext = ResamplingDepositProfileContext::Generic,
                                                          bool reuseExistingCellIds = false);

// 0172 post-thermal refresh: after thermal renormalization, positions, roles,
// masses, cellId, and classification masks are unchanged.  This routine updates
// only momentum/mean-velocity fields and the corresponding diagnostics, avoiding
// a full particle->cell deposit and mutation-plan rebuild.
WeightedResamplingDiagnostics refresh_weighted_real_fluid_velocity_deposit(
    const ParticleState& state,
    const SimulationParams& params,
    const CellGrid& grid,
    const FluidDomainBounds& domain,
    double time,
    const GridShift& shift,
    WeightedRealFluidDepositWorkspace& ws,
    const WeightedResamplingDiagnostics& previousDiagnostics,
    ResamplingDepositProfileContext profileContext = ResamplingDepositProfileContext::PostThermal);

} // namespace mpcd
