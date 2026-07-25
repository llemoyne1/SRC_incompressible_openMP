#pragma once

#include <cstdint>
#include <fstream>
#include <string>
#include <vector>
#include "boundary_base.h"
#include "closed_capacity_response.h"
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
    double q6ProjectionStrengthNominal = 1.0;
    double q6CapacityReferenceMass = 0.0;
    double q6CapacityTotalMass = 0.0;
    double q6CapacityOverfillRatio = 0.0;
    double q6CapacityQ6Factor = 1.0;
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
    double q6SpeciesQ6BarycentricResidualMaxAbs = 0.0;
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

    int capacityResponseEnabled = 0;
    int capacityResponseComputed = 0;
    int capacityVirialKickApplied = 0;
    std::uint64_t capacityReferenceCells = 0;
    double capacityReferenceCellMass = 0.0;
    double capacityReferenceMass = 0.0;
    double capacityTotalMass = 0.0;
    double capacityOverfillMass = 0.0;
    double capacityOverfillRatio = 0.0;
    double capacityQ6ProjectionFactor = 1.0;
    double capacityQ6ProjectionStrengthEffective = 0.0;
    double capacityMassRemapFactor = 1.0;
    double capacityMassRemapTargetCellMassNominal = 0.0;
    double capacityMassRemapOverfillPerCell = 0.0;
    double capacityMassRemapTargetCellMassEffective = 0.0;
    double capacityVirialKBase = 0.0;
    double capacityVirialKFactor = 1.0;
    double capacityVirialKEffective = 0.0;
    double capacityVirialPressureMean = 0.0;
    double capacityVirialPressureRms = 0.0;
    double capacityVirialPressureMin = 0.0;
    double capacityVirialPressureMax = 0.0;
    double capacityVirialKickVelocityRms = 0.0;
    double capacityVirialKickVelocityMaxAbs = 0.0;
    double capacityVirialMomentumResidualBeforeCorrection = 0.0;
    double capacityVirialMomentumCorrectionVx = 0.0;
    double capacityVirialMomentumCorrectionVy = 0.0;
    int capacityWallLoadComputed = 0;
    double capacityWallKineticKBT = 0.0;
    double capacityWallSolidLengthLeft = 0.0;
    double capacityWallSolidLengthRight = 0.0;
    double capacityWallSolidLengthBottom = 0.0;
    double capacityWallSolidLengthTop = 0.0;
    double capacityWallSolidLengthTotal = 0.0;
    double capacityWallPressureKineticMeanLeft = 0.0;
    double capacityWallPressureKineticMeanRight = 0.0;
    double capacityWallPressureKineticMeanBottom = 0.0;
    double capacityWallPressureKineticMeanTop = 0.0;
    double capacityWallPressureVirialMeanLeft = 0.0;
    double capacityWallPressureVirialMeanRight = 0.0;
    double capacityWallPressureVirialMeanBottom = 0.0;
    double capacityWallPressureVirialMeanTop = 0.0;
    double capacityWallPressureTotalMeanLeft = 0.0;
    double capacityWallPressureTotalMeanRight = 0.0;
    double capacityWallPressureTotalMeanBottom = 0.0;
    double capacityWallPressureTotalMeanTop = 0.0;
    double capacityWallPressureKineticMeanAll = 0.0;
    double capacityWallPressureVirialMeanAll = 0.0;
    double capacityWallPressureTotalMeanAll = 0.0;
    double capacityWallForceKineticX = 0.0;
    double capacityWallForceKineticY = 0.0;
    double capacityWallForceVirialX = 0.0;
    double capacityWallForceVirialY = 0.0;
    double capacityWallForceTotalX = 0.0;
    double capacityWallForceTotalY = 0.0;

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

    int resampExtractionPlanBuilt = 0;
    std::uint64_t resampExtractionOps = 0;
    std::uint64_t resampExtractionParticles = 0;
    std::uint64_t resampExtractionDonorCells = 0;
    std::uint64_t resampExtractionReceiverCells = 0;
    std::int64_t resampFirstExtractionParticle = -1;
    std::int64_t resampLastExtractionParticle = -1;
    std::int32_t resampFirstExtractionDonorCell = -1;
    std::int32_t resampLastExtractionDonorCell = -1;
    std::int32_t resampFirstExtractionReceiverCell = -1;
    std::int32_t resampLastExtractionReceiverCell = -1;
    double resampExtractionMass = 0.0;
    double resampExtractionMomentumX = 0.0;
    double resampExtractionMomentumY = 0.0;
    double resampExtractionKineticEnergy = 0.0;
    double resampExtractionMeanParticleMass = 0.0;
    double resampExtractionMaxParticleMass = 0.0;
    double resampExtractionMassOvershoot = 0.0;
    double resampExtractionMassCoverageFraction = 0.0;
    std::uint64_t resampHypotheticalPoolFreeSlotsAfterExtraction = 0;
    int resampExtractionAllSelectedAreFluid = 0;
    int resampExtractionNoDuplicateParticles = 0;

    int resampExtractionApplyAttempted = 0;
    int resampExtractionApplied = 0;
    std::uint64_t resampExtractionApplyOpsConsidered = 0;
    std::uint64_t resampExtractionApplyOpsApplied = 0;
    std::uint64_t resampExtractionApplyRoleChanges = 0;
    std::uint64_t resampExtractionApplySkippedInvalidParticles = 0;
    std::uint64_t resampExtractionApplySkippedNonFluidParticles = 0;
    std::uint64_t resampExtractionApplySkippedDuplicateParticles = 0;
    std::uint64_t resampExtractionApplyPoolFreeSlotsBefore = 0;
    std::uint64_t resampExtractionApplyPoolFreeSlotsAfter = 0;
    std::uint64_t resampExtractionApplyPoolFreeSlotDelta = 0;
    double resampExtractionApplyMass = 0.0;
    double resampExtractionApplyMomentumX = 0.0;
    double resampExtractionApplyMomentumY = 0.0;
    double resampExtractionApplyKineticEnergy = 0.0;
    double resampExtractionApplyPlannedMass = 0.0;
    double resampExtractionApplyMassResidualVsPlan = 0.0;
    std::int64_t resampFirstAppliedExtractionParticle = -1;
    std::int64_t resampLastAppliedExtractionParticle = -1;
    int resampExtractionApplyNoDuplicateParticles = 1;
    int resampExtractionApplyAllAppliedWereFluid = 1;

    int resampInsertionApplyAttempted = 0;
    int resampInsertionApplied = 0;
    std::uint64_t resampInsertionApplyOpsConsidered = 0;
    std::uint64_t resampInsertionApplyOpsApplied = 0;
    std::uint64_t resampInsertionApplyRoleChanges = 0;
    std::uint64_t resampInsertionApplySkippedInvalidSourceParticles = 0;
    std::uint64_t resampInsertionApplySkippedSourceNotInactive = 0;
    std::uint64_t resampInsertionApplySkippedInvalidReceiverCells = 0;
    std::uint64_t resampInsertionApplySkippedNoFreeSlots = 0;
    std::uint64_t resampInsertionApplySkippedInvalidMass = 0;
    std::uint64_t resampInsertionApplyPoolFreeSlotsBefore = 0;
    std::uint64_t resampInsertionApplyPoolFreeSlotsAfter = 0;
    std::uint64_t resampInsertionApplyPoolFreeSlotDelta = 0;
    double resampInsertionApplyMass = 0.0;
    double resampInsertionApplyMomentumX = 0.0;
    double resampInsertionApplyMomentumY = 0.0;
    double resampInsertionApplyKineticEnergy = 0.0;
    double resampInsertionApplyPlannedMass = 0.0;
    double resampInsertionApplyMassResidualVsPlan = 0.0;
    std::int64_t resampFirstAppliedInsertionParticle = -1;
    std::int64_t resampLastAppliedInsertionParticle = -1;
    std::int32_t resampFirstAppliedInsertionReceiverCell = -1;
    std::int32_t resampLastAppliedInsertionReceiverCell = -1;
    int resampInsertionApplyNoInvalidReceiverCells = 1;
    int resampInsertionApplyAllSourcesWereInactive = 1;

    int resampRemapApplyAttempted = 0;
    int resampRemapApplied = 0;
    std::uint64_t resampRemapCellsConsidered = 0;
    std::uint64_t resampRemapCellsRemapped = 0;
    std::uint64_t resampRemapParticlesRemapped = 0;
    std::uint64_t resampRemapSkippedDryCells = 0;
    std::uint64_t resampRemapSkippedEmptyCells = 0;
    std::uint64_t resampRemapSkippedInvalidMassCells = 0;
    double resampRemapTargetCellMass = 0.0;
    double resampRemapMassCorrectionStrength = 1.0;
    double resampRemapMassBefore = 0.0;
    double resampRemapMassAfter = 0.0;
    double resampRemapMassTargetSum = 0.0;
    double resampRemapMassDelta = 0.0;
    double resampRemapMomentumXBefore = 0.0;
    double resampRemapMomentumYBefore = 0.0;
    double resampRemapMomentumXAfter = 0.0;
    double resampRemapMomentumYAfter = 0.0;
    double resampRemapMomentumXTarget = 0.0;
    double resampRemapMomentumYTarget = 0.0;
    double resampRemapMomentumResidualRms = 0.0;
    double resampRemapMomentumResidualMaxAbs = 0.0;
    double resampRemapMaxCellMassRelResidual = 0.0;
    double resampRemapScaleMin = 1.0;
    double resampRemapScaleMax = 1.0;
    std::int32_t resampFirstRemappedCell = -1;
    std::int32_t resampLastRemappedCell = -1;
    int resampRemapAllRemappedCellsNonEmpty = 1;

    int resampThermalRenormAttempted = 0;
    int resampThermalRenormApplied = 0;
    std::uint64_t resampThermalRenormCellsConsidered = 0;
    std::uint64_t resampThermalRenormCellsRenormalized = 0;
    std::uint64_t resampThermalRenormParticlesRenormalized = 0;
    std::uint64_t resampThermalRenormSkippedDryCells = 0;
    std::uint64_t resampThermalRenormSkippedEmptyCells = 0;
    std::uint64_t resampThermalRenormSkippedInvalidEnergyCells = 0;
    double resampThermalRenormTargetEnergy = 0.0;
    double resampThermalRenormEnergyBefore = 0.0;
    double resampThermalRenormEnergyAfter = 0.0;
    double resampThermalRenormEnergyResidualRms = 0.0;
    double resampThermalRenormEnergyResidualMaxAbs = 0.0;
    double resampThermalRenormVelocityScaleMin = 1.0;
    double resampThermalRenormVelocityScaleMax = 1.0;
    double resampThermalRenormMomentumResidualRms = 0.0;
    double resampThermalRenormMomentumResidualMaxAbs = 0.0;
    std::int32_t resampFirstThermalRenormCell = -1;
    std::int32_t resampLastThermalRenormCell = -1;
    int resampThermalRenormAllCellsNonEmpty = 1;

    int resampMassGuardAttempted = 0;
    int resampMassGuardApplied = 0;
    std::uint64_t resampMassGuardCellsConsidered = 0;
    std::uint64_t resampMassGuardCellsGuarded = 0;
    std::uint64_t resampMassGuardParticlesConsidered = 0;
    std::uint64_t resampMassGuardParticlesAdjusted = 0;
    std::uint64_t resampMassGuardSkippedDryCells = 0;
    std::uint64_t resampMassGuardSkippedEmptyCells = 0;
    std::uint64_t resampMassGuardSkippedInfeasibleCells = 0;
    std::uint64_t resampMassGuardSkippedInvalidMassCells = 0;
    double resampMassGuardMinBound = 0.0;
    double resampMassGuardMaxBound = 0.0;
    double resampMassGuardTargetCellMass = 0.0;
    double resampMassGuardMassBefore = 0.0;
    double resampMassGuardMassAfter = 0.0;
    double resampMassGuardMassTargetSum = 0.0;
    double resampMassGuardMassResidualRms = 0.0;
    double resampMassGuardMassResidualMaxAbs = 0.0;
    double resampMassGuardParticleMassMinBefore = 0.0;
    double resampMassGuardParticleMassMaxBefore = 0.0;
    double resampMassGuardParticleMassMinAfter = 0.0;
    double resampMassGuardParticleMassMaxAfter = 0.0;
    std::uint64_t resampMassGuardParticlesBelowMinBefore = 0;
    std::uint64_t resampMassGuardParticlesAboveMaxBefore = 0;
    std::uint64_t resampMassGuardParticlesBelowMinAfter = 0;
    std::uint64_t resampMassGuardParticlesAboveMaxAfter = 0;
    std::uint64_t resampMassGuardParticlesAtMinAfter = 0;
    std::uint64_t resampMassGuardParticlesAtMaxAfter = 0;
    double resampMassGuardThermalEnergyTarget = 0.0;
    double resampMassGuardThermalEnergyBefore = 0.0;
    double resampMassGuardThermalEnergyAfter = 0.0;
    double resampMassGuardThermalEnergyResidualRms = 0.0;
    double resampMassGuardThermalEnergyResidualMaxAbs = 0.0;
    double resampMassGuardVelocityScaleMin = 1.0;
    double resampMassGuardVelocityScaleMax = 1.0;
    double resampMassGuardMomentumResidualRms = 0.0;
    double resampMassGuardMomentumResidualMaxAbs = 0.0;
    std::int32_t resampFirstMassGuardedCell = -1;
    std::int32_t resampLastMassGuardedCell = -1;
    int resampMassGuardAllCellsFeasible = 1;

    int resampPopulationGuardAttempted = 0;
    int resampPopulationGuardApplied = 0;
    int resampPopulationGuardNMin = 0;
    int resampPopulationGuardNTarget = 0;
    int resampPopulationGuardNMax = 0;
    std::uint64_t resampPopulationGuardWetCellsConsidered = 0;
    std::uint64_t resampPopulationGuardUnderfullCells = 0;
    std::uint64_t resampPopulationGuardEmptyUnderfullCells = 0;
    std::uint64_t resampPopulationGuardOverfullCells = 0;
    std::uint64_t resampPopulationGuardCellsSplit = 0;
    std::uint64_t resampPopulationGuardCellsExtracted = 0;
    std::uint64_t resampPopulationGuardSplitParticlesCreated = 0;
    std::uint64_t resampPopulationGuardExtractedParticles = 0;
    std::uint64_t resampPopulationGuardSkippedNoFreeSlots = 0;
    std::uint64_t resampPopulationGuardSkippedEmptyCells = 0;
    std::uint64_t resampPopulationGuardSkippedSplitLimit = 0;
    std::uint64_t resampPopulationGuardSkippedExtractionLimit = 0;
    std::uint64_t resampPopulationGuardFreeSlotsBefore = 0;
    std::uint64_t resampPopulationGuardFreeSlotsAfter = 0;
    std::int64_t resampPopulationGuardActiveParticleDelta = 0;
    double resampPopulationGuardSplitMass = 0.0;
    double resampPopulationGuardExtractedMass = 0.0;
    double resampPopulationGuardWetNMeanBefore = 0.0;
    double resampPopulationGuardWetNMeanAfter = 0.0;
    double resampPopulationGuardWetNStdBefore = 0.0;
    double resampPopulationGuardWetNStdAfter = 0.0;
    std::uint32_t resampPopulationGuardWetNMinBefore = 0;
    std::uint32_t resampPopulationGuardWetNMinAfter = 0;
    double resampPopulationGuardWetLowNFractionBefore = 0.0;
    double resampPopulationGuardWetLowNFractionAfter = 0.0;

    int resampLatentActivationAttempted = 0;
    int resampLatentActivationApplied = 0;
    std::uint64_t resampLatentActivationReceiverCellsConsidered = 0;
    std::uint64_t resampLatentActivationCellsActivated = 0;
    std::uint64_t resampLatentActivationParticlesActivated = 0;
    std::uint64_t resampLatentActivationRoleChanges = 0;
    std::uint64_t resampLatentActivationSkippedNoLatentSlots = 0;
    std::uint64_t resampLatentActivationSkippedInvalidReceiverCells = 0;
    std::uint64_t resampLatentActivationSkippedReceiverNotWet = 0;
    std::uint64_t resampLatentActivationSkippedReceiverNotPoor = 0;
    std::uint64_t resampLatentActivationSkippedMaxPerCell = 0;
    std::uint64_t resampLatentActivationLatentSlotsBefore = 0;
    std::uint64_t resampLatentActivationLatentSlotsAfter = 0;
    std::uint64_t resampLatentActivationFluidSlotsBefore = 0;
    std::uint64_t resampLatentActivationFluidSlotsAfter = 0;
    double resampLatentActivationTargetCellMass = 0.0;
    double resampLatentActivationParticleMass = 0.0;
    double resampLatentActivationMass = 0.0;
    double resampLatentActivationMomentumX = 0.0;
    double resampLatentActivationMomentumY = 0.0;
    double resampLatentActivationKineticEnergy = 0.0;
    std::int64_t resampFirstLatentActivatedParticle = -1;
    std::int64_t resampLastLatentActivatedParticle = -1;
    std::int32_t resampFirstLatentActivatedCell = -1;
    std::int32_t resampLastLatentActivatedCell = -1;
    int resampLatentActivationAllSourcesWereLatent = 1;
    int resampLatentActivationNoDryCellsActivated = 1;

    int resampPoolBuilt = 0;
    std::uint64_t resampPoolStorageSlots = 0;
    std::uint64_t resampPoolFreeSlots = 0;
    std::uint64_t resampPoolLatentSlots = 0;
    std::uint64_t resampPoolFluidSlots = 0;
    std::int64_t resampPoolFirstFreeIndex = -1;
    std::int64_t resampPoolLastFreeIndex = -1;
    double resampPoolFreeSlotFraction = 0.0;
    double resampPoolDormantSlotFraction = 0.0;
    std::uint64_t resampDisabledSpeciesMutationCount = 0;
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
                                       const ClosedCapacityResponseDiagnostics* capacity = nullptr,
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
