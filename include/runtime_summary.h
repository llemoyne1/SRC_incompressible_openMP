#pragma once

#include <cstdint>
#include <fstream>
#include <string>
#include <vector>
#include "boundary_base.h"
#include "fluid_domain.h"
#include "immersed_solid.h"
#include "particle_state.h"
#include "q6_projection_adapter.h"
#include "simulation_params.h"
#include "src_collision.h"
#include "thermostat.h"
#include "weighted_resampling.h"

namespace mpcd {

struct RuntimeSummary {
    int step = 0;
    double time = 0.0;
    double wallTime = 0.0;
    int numThreadsUsed = 1;

    std::uint64_t Np = 0;
    std::uint64_t nFluidParticles = 0;
    std::uint64_t nInactiveParticles = 0;
    std::uint64_t nLatentParticles = 0;
    double totalMass = 0.0;
    double Px = 0.0;
    double Py = 0.0;
    double meanVx = 0.0;
    double meanVy = 0.0;
    double meanKinetic = 0.0;
    double kBTEstimate = 0.0;
    double meanParticleSpeed = 0.0;
    double maxParticleSpeed = 0.0;
    double maxParticleAbsVx = 0.0;
    double maxParticleAbsVy = 0.0;

    double fluidXMin = 0.0;
    double fluidXMax = 0.0;
    double fluidYMin = 0.0;
    double fluidYMax = 0.0;
    double fluidArea = 0.0;
    double meanPhysicalDensity = 0.0;

    double meanN = 0.0;
    double stdN = 0.0;
    std::uint32_t minN = 0;
    std::uint32_t maxN = 0;

    std::uint64_t hitsLeft = 0;
    std::uint64_t hitsRight = 0;
    std::uint64_t hitsBottom = 0;
    std::uint64_t hitsTop = 0;
    int maxXWallReflectionsPerParticle = 0;
    int maxYWallReflectionsPerParticle = 0;
    std::uint64_t hitsImmersed = 0;

    int inletHardReservoirEnabled = 0;
    std::uint64_t inletReservoirCells = 0;
    std::uint64_t inletReservoirTargetParticles = 0;
    std::uint64_t inletReservoirDeleted = 0;
    std::uint64_t inletBackflowDeleted = 0;
    std::uint64_t outletParticlesDeleted = 0;
    std::uint64_t inletParticlesInserted = 0;
    std::int64_t inletNetParticleDelta = 0;
    double inletReservoirMeanN = 0.0;
    double inletReservoirStdN = 0.0;
    std::uint32_t inletReservoirMinN = 0;
    std::uint32_t inletReservoirMaxN = 0;
    double inletReservoirEmptyFraction = 0.0;
    double inletMeanUx = 0.0;
    double inletMeanUy = 0.0;
    double inletKBT = 0.0;

    std::uint64_t virtualParticleCount = 0;
    double virtualParticleEquivalent = 0.0;
    double virtualMass = 0.0;
    double virtualMassLeft = 0.0;
    double virtualMassRight = 0.0;
    double virtualMassBottom = 0.0;
    double virtualMassTop = 0.0;
    double virtualMassImmersed = 0.0;
    double virtualMomentumX = 0.0;
    double virtualMomentumY = 0.0;

    int thermostatApplied = 0;
    std::uint64_t thermostatCells = 0;
    std::uint64_t thermostatParticles = 0;
    double thermostatKBTBefore = 0.0;
    double thermostatKBTAfter = 0.0;
    double thermostatScaleMean = 1.0;
    double thermostatScaleMin = 1.0;
    double thermostatScaleMax = 1.0;

    int q6Applied = 0;
    double q6ProjectionStrength = 1.0;
    int q6Converged = 0;
    int q6Iterations = 0;
    std::uint64_t q6EmptyCells = 0;
    std::uint64_t q6ImmersedSolidFluidCells = 0;
    std::uint64_t q6ImmersedSolidSolidCells = 0;
    std::uint64_t q6ImmersedSolidCutCells = 0;
    std::uint64_t q6ImmersedSolidActiveCutCells = 0;
    std::uint64_t q6ImmersedSolidActiveAdjacentCells = 0;
    std::uint64_t q6ImmersedSolidClosedXFaces = 0;
    std::uint64_t q6ImmersedSolidClosedYFaces = 0;
    std::uint64_t q6ImmersedSolidCellClosedXFaces = 0;
    std::uint64_t q6ImmersedSolidCellClosedYFaces = 0;
    std::uint64_t q6ImmersedSolidCutClosedXFaces = 0;
    std::uint64_t q6ImmersedSolidCutClosedYFaces = 0;
    double q6ResidualRel = 0.0;
    double q6DivBeforeRms = 0.0;
    double q6DivBeforeMaxAbs = 0.0;
    double q6DivAfterProjectedFluxRms = 0.0;
    double q6DivAfterProjectedFluxMaxAbs = 0.0;
    double q6DivAfterCellVelocityRms = 0.0;
    double q6DivAfterCellVelocityMaxAbs = 0.0;
    double q6ImmersedSolidLeakProjectedFluxRms = 0.0;
    double q6ImmersedSolidLeakProjectedFluxMaxAbs = 0.0;
    double q6ImmersedSolidLeakCellClosedProjectedFluxRms = 0.0;
    double q6ImmersedSolidLeakCellClosedProjectedFluxMaxAbs = 0.0;
    double q6ImmersedSolidLeakCutProjectedFluxRms = 0.0;
    double q6ImmersedSolidLeakCutProjectedFluxMaxAbs = 0.0;
    std::uint64_t q6ImmersedSolidLeakFaceCount = 0;
    double q6ImmersedSolidAppliedLeakBeforeClosureRms = 0.0;
    double q6ImmersedSolidAppliedLeakBeforeClosureMaxAbs = 0.0;
    std::uint64_t q6ImmersedSolidClosedFaceFluxEnforcedFaces = 0;
    double q6ImmersedSolidClosedFaceFluxEnforcedRms = 0.0;
    double q6ImmersedSolidClosedFaceFluxEnforcedMaxAbs = 0.0;
    double q6CorrectionVelocityRms = 0.0;
    double q6CorrectionVelocityMaxAbs = 0.0;
    int q6OpenBoundaryEnabled = 0;
    double q6OpenBoundaryFluxXLow = 0.0;
    double q6OpenBoundaryFluxXHigh = 0.0;
    double q6OpenBoundaryFluxYLow = 0.0;
    double q6OpenBoundaryFluxYHigh = 0.0;
    double q6OpenBoundaryFluxBalance = 0.0;
    double q6OpenBoundaryMeanDivergence = 0.0;
    double q6MomentumCorrectionVx = 0.0;
    double q6MomentumCorrectionVy = 0.0;
    double q6MomentumResidualBeforeCorrection = 0.0;

    int resampComputed = 0;
    std::uint64_t resampNFluid = 0;
    std::uint64_t resampNLatent = 0;
    std::uint64_t resampNInactive = 0;
    std::uint64_t resampNonEmptyCells = 0;
    std::uint64_t resampEmptyCells = 0;
    double resampMeanN = 0.0;
    double resampStdN = 0.0;
    std::uint32_t resampMinN = 0;
    std::uint32_t resampMaxN = 0;
    double resampTotalMass = 0.0;
    double resampMeanMass = 0.0;
    double resampStdMass = 0.0;
    double resampMinMass = 0.0;
    double resampMaxMass = 0.0;
    double resampTargetCellMass = 0.0;
    double resampMRelRms = 0.0;
    double resampMRelMaxAbs = 0.0;
    double resampParticleMassMean = 0.0;
    double resampParticleMassStd = 0.0;
    double resampParticleMassRelStd = 0.0;
    double resampParticleMassMin = 0.0;
    double resampParticleMassMax = 0.0;
    double resampMeanUx = 0.0;
    double resampMeanUy = 0.0;
    double resampCellUxRms = 0.0;
    double resampCellUyRms = 0.0;

    int resampCellClassificationComputed = 0;
    std::uint64_t resampActiveCells = 0;
    std::uint64_t resampWetCells = 0;
    std::uint64_t resampDryCells = 0;
    std::uint64_t resampPoorCells = 0;
    std::uint64_t resampRichCells = 0;
    std::uint64_t resampTargetBandCells = 0;
    std::uint64_t resampEmptyWetCells = 0;
    std::uint64_t resampOccupiedDryCells = 0;
    double resampWetMassThreshold = 0.0;
    double resampPoorMassThreshold = 0.0;
    double resampRichMassThreshold = 0.0;
    double resampWetCellFraction = 0.0;
    double resampDryCellFraction = 0.0;
    double resampPoorCellFraction = 0.0;
    double resampRichCellFraction = 0.0;
    double resampEmptyWetCellFraction = 0.0;

    int resampCandidateListsBuilt = 0;
    std::uint64_t resampReceiverCells = 0;
    std::uint64_t resampDonorCells = 0;
    std::uint64_t resampEmptyWetReceiverCells = 0;
    std::int32_t resampFirstReceiverCell = -1;
    std::int32_t resampLastReceiverCell = -1;
    std::int32_t resampFirstDonorCell = -1;
    std::int32_t resampLastDonorCell = -1;
    double resampReceiverMassDeficitToTarget = 0.0;
    double resampDonorMassExcessAboveTarget = 0.0;
    double resampDonorReceiverMassBalance = 0.0;
    double resampPotentialTransferMass = 0.0;
    double resampReceiverFractionOfWetCells = 0.0;
    double resampDonorFractionOfWetCells = 0.0;
    int resampPoolCanSeedReceivers = 0;

    int resampTransferPlanBuilt = 0;
    std::uint64_t resampTransferPairs = 0;
    std::uint64_t resampAdjacentTransferPairs = 0;
    std::int32_t resampFirstTransferDonorCell = -1;
    std::int32_t resampFirstTransferReceiverCell = -1;
    std::int32_t resampLastTransferDonorCell = -1;
    std::int32_t resampLastTransferReceiverCell = -1;
    double resampPlannedTransferMass = 0.0;
    double resampRemainingReceiverDeficitAfterPlan = 0.0;
    double resampRemainingDonorExcessAfterPlan = 0.0;
    double resampTransferMassCoverageFraction = 0.0;
    double resampTransferMeanCellDistance = 0.0;
    double resampTransferMaxCellDistance = 0.0;
    int resampTransferPlanDonorLimited = 0;
    int resampTransferPlanReceiverLimited = 0;

    int resampDonorParticleSelectionBuilt = 0;
    std::uint64_t resampSelectedDonorParticles = 0;
    std::uint64_t resampDonorCellsWithSelectedParticles = 0;
    std::uint64_t resampMaxSelectedParticlesForTransferEntry = 0;
    std::uint64_t resampMaxSelectedParticlesPerDonorCell = 0;
    std::int64_t resampFirstSelectedDonorParticle = -1;
    std::int64_t resampLastSelectedDonorParticle = -1;
    std::int32_t resampFirstSelectedDonorCell = -1;
    std::int32_t resampLastSelectedDonorCell = -1;
    std::int32_t resampFirstSelectedReceiverCell = -1;
    std::int32_t resampLastSelectedReceiverCell = -1;
    double resampSelectedDonorParticleMass = 0.0;
    double resampSelectedDonorMassOvershoot = 0.0;
    double resampSelectedDonorMassCoverageFraction = 0.0;
    double resampSelectedDonorMeanParticleMass = 0.0;
    double resampSelectedDonorMaxParticleMass = 0.0;
    int resampDonorParticleSelectionExactOrOvershoot = 0;
    int resampDonorParticleSelectionUnderfilled = 0;

    int resampPoolBuilt = 0;
    std::uint64_t resampPoolStorageSlots = 0;
    std::uint64_t resampPoolFreeSlots = 0;
    std::uint64_t resampPoolLatentSlots = 0;
    std::uint64_t resampPoolFluidSlots = 0;
    std::int64_t resampPoolFirstFreeIndex = -1;
    std::int64_t resampPoolLastFreeIndex = -1;
    double resampPoolFreeSlotFraction = 0.0;
    double resampPoolDormantSlotFraction = 0.0;
};

RuntimeSummary compute_runtime_summary(const ParticleState& state,
                                       const SimulationParams& params,
                                       int step,
                                       double wallTime,
                                       const std::vector<std::uint32_t>* cellCount = nullptr,
                                       const BoundaryDiagnostics* boundary = nullptr,
                                       const ImmersedSolidDiagnostics* immersed = nullptr,
                                       const CollisionDiagnostics* collision = nullptr,
                                       const Q6ProjectionDiagnostics* q6 = nullptr,
                                       const ThermostatDiagnostics* thermostat = nullptr,
                                       const WeightedResamplingDiagnostics* resampling = nullptr,
                                       int numThreadsUsed = 1);

class RuntimeSummaryWriter {
public:
    explicit RuntimeSummaryWriter(const std::string& filepath);
    void append(const RuntimeSummary& s);

private:
    std::ofstream out_;
};

} // namespace mpcd
