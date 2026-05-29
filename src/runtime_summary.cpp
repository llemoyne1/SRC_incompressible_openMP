#include "runtime_summary.h"

#include <algorithm>
#include <cmath>
#include <iomanip>
#include <limits>
#include <stdexcept>

namespace mpcd {

RuntimeSummary compute_runtime_summary(const ParticleState& state,
                                       const SimulationParams& params,
                                       int step,
                                       double wallTime,
                                       const std::vector<std::uint32_t>* cellCount,
                                       const BoundaryDiagnostics* boundary,
                                       const ImmersedSolidDiagnostics* immersed,
                                       const CollisionDiagnostics* collision,
                                       const Q6ProjectionDiagnostics* q6,
                                       const ThermostatDiagnostics* thermostat,
                                       const WeightedResamplingDiagnostics* resampling,
                                       int numThreadsUsed) {
    validate_particle_state(state, "compute_runtime_summary");
    RuntimeSummary s{};
    s.step = step;
    s.time = static_cast<double>(step) * params.dt;
    s.wallTime = wallTime;
    s.numThreadsUsed = numThreadsUsed > 0 ? numThreadsUsed : 1;
    s.Np = state.Np;
    const ParticleRoleCounts roleCounts = count_particle_roles(state);
    s.nFluidParticles = roleCounts.fluid;
    s.nInactiveParticles = roleCounts.inactive;
    s.nLatentParticles = roleCounts.latent;

    const std::size_t n = static_cast<std::size_t>(state.Np);
    double mass = 0.0;
    double px = 0.0;
    double py = 0.0;
    double kinetic = 0.0;
    double speedSum = 0.0;
    double maxSpeed = 0.0;
    double maxAbsVx = 0.0;
    double maxAbsVy = 0.0;

#pragma omp parallel for reduction(+:mass,px,py,kinetic,speedSum) reduction(max:maxSpeed,maxAbsVx,maxAbsVy) if(n > 10000)
    for (std::int64_t ii = 0; ii < static_cast<std::int64_t>(n); ++ii) {
        const std::size_t i = static_cast<std::size_t>(ii);
        if (!is_fluid_particle(state, i)) {
            continue;
        }
        const double m = state.mass[i];
        const double vx = state.vx[i];
        const double vy = state.vy[i];
        mass += m;
        px += m * vx;
        py += m * vy;
        kinetic += 0.5 * m * (vx * vx + vy * vy);
        const double speed = std::sqrt(vx * vx + vy * vy);
        speedSum += speed;
        maxSpeed = std::max(maxSpeed, speed);
        maxAbsVx = std::max(maxAbsVx, std::abs(vx));
        maxAbsVy = std::max(maxAbsVy, std::abs(vy));
    }

    s.totalMass = mass;
    s.Px = px;
    s.Py = py;

    const FluidDomainBounds domain = make_fluid_domain_bounds(params, s.time);
    s.fluidXMin = domain.xMin;
    s.fluidXMax = domain.xMax;
    s.fluidYMin = domain.yMin;
    s.fluidYMax = domain.yMax;
    s.fluidArea = fluid_domain_area(domain);
    s.meanPhysicalDensity = s.fluidArea > 0.0 ? mass / s.fluidArea : 0.0;

    if (mass > 0.0) {
        s.meanVx = px / mass;
        s.meanVy = py / mass;
    }
    if (roleCounts.fluid > 0u) {
        const double nf = static_cast<double>(roleCounts.fluid);
        s.meanKinetic = kinetic / nf;
        s.meanParticleSpeed = speedSum / nf;
        s.maxParticleSpeed = maxSpeed;
        s.maxParticleAbsVx = maxAbsVx;
        s.maxParticleAbsVy = maxAbsVy;
    }

    double thermal = 0.0;
#pragma omp parallel for reduction(+:thermal) if(n > 10000)
    for (std::int64_t ii = 0; ii < static_cast<std::int64_t>(n); ++ii) {
        const std::size_t i = static_cast<std::size_t>(ii);
        if (!is_fluid_particle(state, i)) {
            continue;
        }
        const double dvx = state.vx[i] - s.meanVx;
        const double dvy = state.vy[i] - s.meanVy;
        thermal += state.mass[i] * (dvx * dvx + dvy * dvy);
    }
    if (roleCounts.fluid > 0u) {
        s.kBTEstimate = thermal / (2.0 * static_cast<double>(roleCounts.fluid));
    }

    if (boundary != nullptr) {
        s.hitsLeft = boundary->hitsLeft;
        s.hitsRight = boundary->hitsRight;
        s.hitsBottom = boundary->hitsBottom;
        s.hitsTop = boundary->hitsTop;
        s.maxXWallReflectionsPerParticle = boundary->maxXWallReflectionsPerParticle;
        s.maxYWallReflectionsPerParticle = boundary->maxYWallReflectionsPerParticle;
        s.inletHardReservoirEnabled = boundary->inletHardReservoirEnabled;
        s.inletReservoirCells = boundary->inletReservoirCells;
        s.inletReservoirTargetParticles = boundary->inletReservoirTargetParticles;
        s.inletReservoirDeleted = boundary->inletReservoirDeleted;
        s.inletBackflowDeleted = boundary->inletBackflowDeleted;
        s.outletParticlesDeleted = boundary->outletParticlesDeleted;
        s.inletParticlesInserted = boundary->inletParticlesInserted;
        s.inletNetParticleDelta = boundary->inletNetParticleDelta;
        s.inletReservoirMeanN = boundary->inletReservoirMeanN;
        s.inletReservoirStdN = boundary->inletReservoirStdN;
        s.inletReservoirMinN = boundary->inletReservoirMinN;
        s.inletReservoirMaxN = boundary->inletReservoirMaxN;
        s.inletReservoirEmptyFraction = boundary->inletReservoirEmptyFraction;
        s.inletMeanUx = boundary->inletMeanUx;
        s.inletMeanUy = boundary->inletMeanUy;
        s.inletKBT = boundary->inletKBT;
    }
    if (immersed != nullptr) {
        s.hitsImmersed = immersed->hits;
    }
    if (collision != nullptr) {
        s.virtualParticleCount = collision->virtualParticleCount;
        s.virtualParticleEquivalent = collision->virtualParticleEquivalent;
        s.virtualMass = collision->virtualMass;
        s.virtualMassLeft = collision->virtualMassLeft;
        s.virtualMassRight = collision->virtualMassRight;
        s.virtualMassBottom = collision->virtualMassBottom;
        s.virtualMassTop = collision->virtualMassTop;
        s.virtualMassImmersed = collision->virtualMassImmersed;
        s.virtualMomentumX = collision->virtualMomentumX;
        s.virtualMomentumY = collision->virtualMomentumY;
    }
    if (q6 != nullptr) {
        s.q6Applied = q6->applied ? 1 : 0;
        s.q6ProjectionStrength = q6->projectionStrength;
        s.q6Converged = q6->converged ? 1 : 0;
        s.q6Iterations = q6->iterations;
        s.q6EmptyCells = q6->emptyCells;
        s.q6ImmersedSolidFluidCells = q6->immersedSolidFluidCells;
        s.q6ImmersedSolidSolidCells = q6->immersedSolidSolidCells;
        s.q6ImmersedSolidCutCells = q6->immersedSolidCutCells;
        s.q6ImmersedSolidActiveCutCells = q6->immersedSolidActiveCutCells;
        s.q6ImmersedSolidActiveAdjacentCells = q6->immersedSolidActiveAdjacentCells;
        s.q6ImmersedSolidClosedXFaces = q6->immersedSolidClosedXFaces;
        s.q6ImmersedSolidClosedYFaces = q6->immersedSolidClosedYFaces;
        s.q6ImmersedSolidCellClosedXFaces = q6->immersedSolidCellClosedXFaces;
        s.q6ImmersedSolidCellClosedYFaces = q6->immersedSolidCellClosedYFaces;
        s.q6ImmersedSolidCutClosedXFaces = q6->immersedSolidCutClosedXFaces;
        s.q6ImmersedSolidCutClosedYFaces = q6->immersedSolidCutClosedYFaces;
        s.q6ResidualRel = q6->residualRel;
        s.q6DivBeforeRms = q6->divBeforeRms;
        s.q6DivBeforeMaxAbs = q6->divBeforeMaxAbs;
        s.q6DivAfterProjectedFluxRms = q6->divAfterProjectedFluxRms;
        s.q6DivAfterProjectedFluxMaxAbs = q6->divAfterProjectedFluxMaxAbs;
        s.q6DivAfterCellVelocityRms = q6->divAfterCellVelocityRms;
        s.q6DivAfterCellVelocityMaxAbs = q6->divAfterCellVelocityMaxAbs;
        s.q6ImmersedSolidLeakProjectedFluxRms = q6->immersedSolidLeakProjectedFluxRms;
        s.q6ImmersedSolidLeakProjectedFluxMaxAbs = q6->immersedSolidLeakProjectedFluxMaxAbs;
        s.q6ImmersedSolidLeakCellClosedProjectedFluxRms = q6->immersedSolidLeakCellClosedProjectedFluxRms;
        s.q6ImmersedSolidLeakCellClosedProjectedFluxMaxAbs = q6->immersedSolidLeakCellClosedProjectedFluxMaxAbs;
        s.q6ImmersedSolidLeakCutProjectedFluxRms = q6->immersedSolidLeakCutProjectedFluxRms;
        s.q6ImmersedSolidLeakCutProjectedFluxMaxAbs = q6->immersedSolidLeakCutProjectedFluxMaxAbs;
        s.q6ImmersedSolidLeakFaceCount = q6->immersedSolidLeakFaceCount;
        s.q6ImmersedSolidAppliedLeakBeforeClosureRms = q6->immersedSolidAppliedLeakBeforeClosureRms;
        s.q6ImmersedSolidAppliedLeakBeforeClosureMaxAbs = q6->immersedSolidAppliedLeakBeforeClosureMaxAbs;
        s.q6ImmersedSolidClosedFaceFluxEnforcedFaces = q6->immersedSolidClosedFaceFluxEnforcedFaces;
        s.q6ImmersedSolidClosedFaceFluxEnforcedRms = q6->immersedSolidClosedFaceFluxEnforcedRms;
        s.q6ImmersedSolidClosedFaceFluxEnforcedMaxAbs = q6->immersedSolidClosedFaceFluxEnforcedMaxAbs;
        s.q6CorrectionVelocityRms = q6->correctionVelocityRms;
        s.q6CorrectionVelocityMaxAbs = q6->correctionVelocityMaxAbs;
        s.q6OpenBoundaryEnabled = q6->openBoundaryEnabled ? 1 : 0;
        s.q6OpenBoundaryFluxXLow = q6->openBoundaryFluxXLow;
        s.q6OpenBoundaryFluxXHigh = q6->openBoundaryFluxXHigh;
        s.q6OpenBoundaryFluxYLow = q6->openBoundaryFluxYLow;
        s.q6OpenBoundaryFluxYHigh = q6->openBoundaryFluxYHigh;
        s.q6OpenBoundaryFluxBalance = q6->openBoundaryFluxBalance;
        s.q6OpenBoundaryMeanDivergence = q6->openBoundaryMeanDivergence;
        s.q6MomentumCorrectionVx = q6->momentumCorrectionVx;
        s.q6MomentumCorrectionVy = q6->momentumCorrectionVy;
        s.q6MomentumResidualBeforeCorrection = q6->momentumResidualBeforeCorrection;
    }
    if (thermostat != nullptr) {
        s.thermostatApplied = thermostat->applied ? 1 : 0;
        s.thermostatCells = thermostat->cellsRescaled;
        s.thermostatParticles = thermostat->particlesRescaled;
        s.thermostatKBTBefore = thermostat->kBTBefore;
        s.thermostatKBTAfter = thermostat->kBTAfter;
        s.thermostatScaleMean = thermostat->scaleMean;
        s.thermostatScaleMin = thermostat->scaleMin;
        s.thermostatScaleMax = thermostat->scaleMax;
    }


    if (resampling != nullptr && resampling->computed) {
        s.resampComputed = 1;
        s.resampNFluid = resampling->nFluid;
        s.resampNLatent = resampling->nLatent;
        s.resampNInactive = resampling->nInactive;
        s.resampNonEmptyCells = resampling->nNonEmptyCells;
        s.resampEmptyCells = resampling->nEmptyCells;
        s.resampMeanN = resampling->meanN;
        s.resampStdN = resampling->stdN;
        s.resampMinN = resampling->minN;
        s.resampMaxN = resampling->maxN;
        s.resampTotalMass = resampling->totalMass;
        s.resampMeanMass = resampling->meanMass;
        s.resampStdMass = resampling->stdMass;
        s.resampMinMass = resampling->minMass;
        s.resampMaxMass = resampling->maxMass;
        s.resampTargetCellMass = resampling->targetCellMass;
        s.resampMRelRms = resampling->mRelRms;
        s.resampMRelMaxAbs = resampling->mRelMaxAbs;
        s.resampParticleMassMean = resampling->particleMassMean;
        s.resampParticleMassStd = resampling->particleMassStd;
        s.resampParticleMassRelStd = resampling->particleMassRelStd;
        s.resampParticleMassMin = resampling->particleMassMin;
        s.resampParticleMassMax = resampling->particleMassMax;
        s.resampMeanUx = resampling->meanUx;
        s.resampMeanUy = resampling->meanUy;
        s.resampCellUxRms = resampling->cellUxRms;
        s.resampCellUyRms = resampling->cellUyRms;
        s.resampCellClassificationComputed = resampling->cellClassificationComputed ? 1 : 0;
        s.resampActiveCells = resampling->nActiveCells;
        s.resampWetCells = resampling->nWetCells;
        s.resampDryCells = resampling->nDryCells;
        s.resampPoorCells = resampling->nPoorCells;
        s.resampRichCells = resampling->nRichCells;
        s.resampTargetBandCells = resampling->nTargetBandCells;
        s.resampEmptyWetCells = resampling->nEmptyWetCells;
        s.resampOccupiedDryCells = resampling->nOccupiedDryCells;
        s.resampWetMassThreshold = resampling->wetMassThreshold;
        s.resampPoorMassThreshold = resampling->poorMassThreshold;
        s.resampRichMassThreshold = resampling->richMassThreshold;
        s.resampWetCellFraction = resampling->wetCellFraction;
        s.resampDryCellFraction = resampling->dryCellFraction;
        s.resampPoorCellFraction = resampling->poorCellFraction;
        s.resampRichCellFraction = resampling->richCellFraction;
        s.resampEmptyWetCellFraction = resampling->emptyWetCellFraction;
        s.resampCandidateListsBuilt = resampling->candidateListsBuilt ? 1 : 0;
        s.resampReceiverCells = resampling->nReceiverCells;
        s.resampDonorCells = resampling->nDonorCells;
        s.resampEmptyWetReceiverCells = resampling->nEmptyWetReceiverCells;
        s.resampFirstReceiverCell = resampling->firstReceiverCell;
        s.resampLastReceiverCell = resampling->lastReceiverCell;
        s.resampFirstDonorCell = resampling->firstDonorCell;
        s.resampLastDonorCell = resampling->lastDonorCell;
        s.resampReceiverMassDeficitToTarget = resampling->receiverMassDeficitToTarget;
        s.resampDonorMassExcessAboveTarget = resampling->donorMassExcessAboveTarget;
        s.resampDonorReceiverMassBalance = resampling->donorReceiverMassBalance;
        s.resampPotentialTransferMass = resampling->potentialTransferMass;
        s.resampReceiverFractionOfWetCells = resampling->receiverFractionOfWetCells;
        s.resampDonorFractionOfWetCells = resampling->donorFractionOfWetCells;
        s.resampPoolCanSeedReceivers = resampling->poolCanSeedReceivers ? 1 : 0;
        s.resampPoolBuilt = resampling->poolBuilt ? 1 : 0;
        s.resampPoolStorageSlots = resampling->poolStorageSlots;
        s.resampPoolFreeSlots = resampling->poolFreeSlots;
        s.resampPoolLatentSlots = resampling->poolLatentSlots;
        s.resampPoolFluidSlots = resampling->poolFluidSlots;
        s.resampPoolFirstFreeIndex = resampling->poolFirstFreeIndex == kInvalidParticleIndex
            ? -1 : static_cast<std::int64_t>(resampling->poolFirstFreeIndex);
        s.resampPoolLastFreeIndex = resampling->poolLastFreeIndex == kInvalidParticleIndex
            ? -1 : static_cast<std::int64_t>(resampling->poolLastFreeIndex);
        s.resampPoolFreeSlotFraction = resampling->poolFreeSlotFraction;
        s.resampPoolDormantSlotFraction = resampling->poolDormantSlotFraction;
    }

    if (cellCount != nullptr && !cellCount->empty()) {
        const auto& count = *cellCount;
        const std::size_t nc = count.size();
        double sum = 0.0;
        double sum2 = 0.0;
        std::uint32_t minN = std::numeric_limits<std::uint32_t>::max();
        std::uint32_t maxN = 0u;
        for (const std::uint32_t c : count) {
            const double d = static_cast<double>(c);
            sum += d;
            sum2 += d * d;
            if (c < minN) minN = c;
            if (c > maxN) maxN = c;
        }
        if (nc > 0u) {
            s.meanN = sum / static_cast<double>(nc);
            const double var = sum2 / static_cast<double>(nc) - s.meanN * s.meanN;
            s.stdN = std::sqrt(var > 0.0 ? var : 0.0);
            s.minN = minN;
            s.maxN = maxN;
        }
    } else {
        const double nc = static_cast<double>(params.Nx * params.Ny);
        s.meanN = nc > 0.0 ? static_cast<double>(roleCounts.fluid) / nc : 0.0;
        s.stdN = 0.0;
        s.minN = 0u;
        s.maxN = 0u;
    }

    return s;
}

RuntimeSummaryWriter::RuntimeSummaryWriter(const std::string& filepath) : out_(filepath) {
    if (!out_) {
        throw std::runtime_error("Cannot open runtime summary file for writing: " + filepath);
    }
    out_ << "step,time,wallTime,numThreadsUsed,Np,nFluidParticles,nInactiveParticles,nLatentParticles,totalMass,Px,Py,meanVx,meanVy,meanKinetic,kBTEstimate,meanParticleSpeed,maxParticleSpeed,maxParticleAbsVx,maxParticleAbsVy,fluidXMin,fluidXMax,fluidYMin,fluidYMax,fluidArea,meanPhysicalDensity,meanN,stdN,minN,maxN,hitsLeft,hitsRight,hitsBottom,hitsTop,maxXWallReflectionsPerParticle,maxYWallReflectionsPerParticle,hitsImmersed,inletHardReservoirEnabled,inletReservoirCells,inletReservoirTargetParticles,inletReservoirDeleted,inletBackflowDeleted,outletParticlesDeleted,inletParticlesInserted,inletNetParticleDelta,inletReservoirMeanN,inletReservoirStdN,inletReservoirMinN,inletReservoirMaxN,inletReservoirEmptyFraction,inletMeanUx,inletMeanUy,inletKBT,virtualParticleCount,virtualParticleEquivalent,virtualMass,virtualMassLeft,virtualMassRight,virtualMassBottom,virtualMassTop,virtualMassImmersed,virtualMomentumX,virtualMomentumY,thermostatApplied,thermostatCells,thermostatParticles,thermostatKBTBefore,thermostatKBTAfter,thermostatScaleMean,thermostatScaleMin,thermostatScaleMax,q6Applied,q6ProjectionStrength,q6Converged,q6Iterations,q6EmptyCells,q6ImmersedSolidFluidCells,q6ImmersedSolidSolidCells,q6ImmersedSolidCutCells,q6ImmersedSolidActiveCutCells,q6ImmersedSolidActiveAdjacentCells,q6ImmersedSolidClosedXFaces,q6ImmersedSolidClosedYFaces,q6ImmersedSolidCellClosedXFaces,q6ImmersedSolidCellClosedYFaces,q6ImmersedSolidCutClosedXFaces,q6ImmersedSolidCutClosedYFaces,q6ResidualRel,q6DivBeforeRms,q6DivBeforeMaxAbs,q6DivAfterProjectedFluxRms,q6DivAfterProjectedFluxMaxAbs,q6DivAfterCellVelocityRms,q6DivAfterCellVelocityMaxAbs,q6ImmersedSolidLeakProjectedFluxRms,q6ImmersedSolidLeakProjectedFluxMaxAbs,q6ImmersedSolidLeakCellClosedProjectedFluxRms,q6ImmersedSolidLeakCellClosedProjectedFluxMaxAbs,q6ImmersedSolidLeakCutProjectedFluxRms,q6ImmersedSolidLeakCutProjectedFluxMaxAbs,q6ImmersedSolidLeakFaceCount,q6ImmersedSolidAppliedLeakBeforeClosureRms,q6ImmersedSolidAppliedLeakBeforeClosureMaxAbs,q6ImmersedSolidClosedFaceFluxEnforcedFaces,q6ImmersedSolidClosedFaceFluxEnforcedRms,q6ImmersedSolidClosedFaceFluxEnforcedMaxAbs,q6CorrectionVelocityRms,q6CorrectionVelocityMaxAbs,q6OpenBoundaryEnabled,q6OpenBoundaryFluxXLow,q6OpenBoundaryFluxXHigh,q6OpenBoundaryFluxYLow,q6OpenBoundaryFluxYHigh,q6OpenBoundaryFluxBalance,q6OpenBoundaryMeanDivergence,q6MomentumCorrectionVx,q6MomentumCorrectionVy,q6MomentumResidualBeforeCorrection,resampComputed,resampNFluid,resampNLatent,resampNInactive,resampNonEmptyCells,resampEmptyCells,resampMeanN,resampStdN,resampMinN,resampMaxN,resampTotalMass,resampMeanMass,resampStdMass,resampMinMass,resampMaxMass,resampTargetCellMass,resampMRelRms,resampMRelMaxAbs,resampParticleMassMean,resampParticleMassStd,resampParticleMassRelStd,resampParticleMassMin,resampParticleMassMax,resampMeanUx,resampMeanUy,resampCellUxRms,resampCellUyRms,resampCellClassificationComputed,resampActiveCells,resampWetCells,resampDryCells,resampPoorCells,resampRichCells,resampTargetBandCells,resampEmptyWetCells,resampOccupiedDryCells,resampWetMassThreshold,resampPoorMassThreshold,resampRichMassThreshold,resampWetCellFraction,resampDryCellFraction,resampPoorCellFraction,resampRichCellFraction,resampEmptyWetCellFraction,resampCandidateListsBuilt,resampReceiverCells,resampDonorCells,resampEmptyWetReceiverCells,resampFirstReceiverCell,resampLastReceiverCell,resampFirstDonorCell,resampLastDonorCell,resampReceiverMassDeficitToTarget,resampDonorMassExcessAboveTarget,resampDonorReceiverMassBalance,resampPotentialTransferMass,resampReceiverFractionOfWetCells,resampDonorFractionOfWetCells,resampPoolCanSeedReceivers,resampPoolBuilt,resampPoolStorageSlots,resampPoolFreeSlots,resampPoolLatentSlots,resampPoolFluidSlots,resampPoolFirstFreeIndex,resampPoolLastFreeIndex,resampPoolFreeSlotFraction,resampPoolDormantSlotFraction\n";
}

void RuntimeSummaryWriter::append(const RuntimeSummary& s) {
    if (!out_) {
        throw std::runtime_error("Runtime summary file is not writable");
    }
    out_ << s.step << ','
         << std::setprecision(17) << s.time << ','
         << s.wallTime << ','
         << s.numThreadsUsed << ','
         << s.Np << ','
         << s.nFluidParticles << ','
         << s.nInactiveParticles << ','
         << s.nLatentParticles << ','
         << s.totalMass << ','
         << s.Px << ','
         << s.Py << ','
         << s.meanVx << ','
         << s.meanVy << ','
         << s.meanKinetic << ','
         << s.kBTEstimate << ','
         << s.meanParticleSpeed << ','
         << s.maxParticleSpeed << ','
         << s.maxParticleAbsVx << ','
         << s.maxParticleAbsVy << ','
         << s.fluidXMin << ','
         << s.fluidXMax << ','
         << s.fluidYMin << ','
         << s.fluidYMax << ','
         << s.fluidArea << ','
         << s.meanPhysicalDensity << ','
         << s.meanN << ','
         << s.stdN << ','
         << s.minN << ','
         << s.maxN << ','
         << s.hitsLeft << ','
         << s.hitsRight << ','
         << s.hitsBottom << ','
         << s.hitsTop << ','
         << s.maxXWallReflectionsPerParticle << ','
         << s.maxYWallReflectionsPerParticle << ','
         << s.hitsImmersed << ','
         << s.inletHardReservoirEnabled << ','
         << s.inletReservoirCells << ','
         << s.inletReservoirTargetParticles << ','
         << s.inletReservoirDeleted << ','
         << s.inletBackflowDeleted << ','
         << s.outletParticlesDeleted << ','
         << s.inletParticlesInserted << ','
         << s.inletNetParticleDelta << ','
         << s.inletReservoirMeanN << ','
         << s.inletReservoirStdN << ','
         << s.inletReservoirMinN << ','
         << s.inletReservoirMaxN << ','
         << s.inletReservoirEmptyFraction << ','
         << s.inletMeanUx << ','
         << s.inletMeanUy << ','
         << s.inletKBT << ','
         << s.virtualParticleCount << ','
         << s.virtualParticleEquivalent << ','
         << s.virtualMass << ','
         << s.virtualMassLeft << ','
         << s.virtualMassRight << ','
         << s.virtualMassBottom << ','
         << s.virtualMassTop << ','
         << s.virtualMassImmersed << ','
         << s.virtualMomentumX << ','
         << s.virtualMomentumY << ','
         << s.thermostatApplied << ','
         << s.thermostatCells << ','
         << s.thermostatParticles << ','
         << s.thermostatKBTBefore << ','
         << s.thermostatKBTAfter << ','
         << s.thermostatScaleMean << ','
         << s.thermostatScaleMin << ','
         << s.thermostatScaleMax << ','
         << s.q6Applied << ','
         << s.q6ProjectionStrength << ','
         << s.q6Converged << ','
         << s.q6Iterations << ','
         << s.q6EmptyCells << ','
         << s.q6ImmersedSolidFluidCells << ','
         << s.q6ImmersedSolidSolidCells << ','
         << s.q6ImmersedSolidCutCells << ','
         << s.q6ImmersedSolidActiveCutCells << ','
         << s.q6ImmersedSolidActiveAdjacentCells << ','
         << s.q6ImmersedSolidClosedXFaces << ','
         << s.q6ImmersedSolidClosedYFaces << ','
         << s.q6ImmersedSolidCellClosedXFaces << ','
         << s.q6ImmersedSolidCellClosedYFaces << ','
         << s.q6ImmersedSolidCutClosedXFaces << ','
         << s.q6ImmersedSolidCutClosedYFaces << ','
         << s.q6ResidualRel << ','
         << s.q6DivBeforeRms << ','
         << s.q6DivBeforeMaxAbs << ','
         << s.q6DivAfterProjectedFluxRms << ','
         << s.q6DivAfterProjectedFluxMaxAbs << ','
         << s.q6DivAfterCellVelocityRms << ','
         << s.q6DivAfterCellVelocityMaxAbs << ','
         << s.q6ImmersedSolidLeakProjectedFluxRms << ','
         << s.q6ImmersedSolidLeakProjectedFluxMaxAbs << ','
         << s.q6ImmersedSolidLeakCellClosedProjectedFluxRms << ','
         << s.q6ImmersedSolidLeakCellClosedProjectedFluxMaxAbs << ','
         << s.q6ImmersedSolidLeakCutProjectedFluxRms << ','
         << s.q6ImmersedSolidLeakCutProjectedFluxMaxAbs << ','
         << s.q6ImmersedSolidLeakFaceCount << ','
         << s.q6ImmersedSolidAppliedLeakBeforeClosureRms << ','
         << s.q6ImmersedSolidAppliedLeakBeforeClosureMaxAbs << ','
         << s.q6ImmersedSolidClosedFaceFluxEnforcedFaces << ','
         << s.q6ImmersedSolidClosedFaceFluxEnforcedRms << ','
         << s.q6ImmersedSolidClosedFaceFluxEnforcedMaxAbs << ','
         << s.q6CorrectionVelocityRms << ','
         << s.q6CorrectionVelocityMaxAbs << ','
         << s.q6OpenBoundaryEnabled << ','
         << s.q6OpenBoundaryFluxXLow << ','
         << s.q6OpenBoundaryFluxXHigh << ','
         << s.q6OpenBoundaryFluxYLow << ','
         << s.q6OpenBoundaryFluxYHigh << ','
         << s.q6OpenBoundaryFluxBalance << ','
         << s.q6OpenBoundaryMeanDivergence << ','
         << s.q6MomentumCorrectionVx << ','
         << s.q6MomentumCorrectionVy << ','
         << s.q6MomentumResidualBeforeCorrection << ','
         << s.resampComputed << ','
         << s.resampNFluid << ','
         << s.resampNLatent << ','
         << s.resampNInactive << ','
         << s.resampNonEmptyCells << ','
         << s.resampEmptyCells << ','
         << s.resampMeanN << ','
         << s.resampStdN << ','
         << s.resampMinN << ','
         << s.resampMaxN << ','
         << s.resampTotalMass << ','
         << s.resampMeanMass << ','
         << s.resampStdMass << ','
         << s.resampMinMass << ','
         << s.resampMaxMass << ','
         << s.resampTargetCellMass << ','
         << s.resampMRelRms << ','
         << s.resampMRelMaxAbs << ','
         << s.resampParticleMassMean << ','
         << s.resampParticleMassStd << ','
         << s.resampParticleMassRelStd << ','
         << s.resampParticleMassMin << ','
         << s.resampParticleMassMax << ','
         << s.resampMeanUx << ','
         << s.resampMeanUy << ','
         << s.resampCellUxRms << ','
         << s.resampCellUyRms << ','
         << s.resampCellClassificationComputed << ','
         << s.resampActiveCells << ','
         << s.resampWetCells << ','
         << s.resampDryCells << ','
         << s.resampPoorCells << ','
         << s.resampRichCells << ','
         << s.resampTargetBandCells << ','
         << s.resampEmptyWetCells << ','
         << s.resampOccupiedDryCells << ','
         << s.resampWetMassThreshold << ','
         << s.resampPoorMassThreshold << ','
         << s.resampRichMassThreshold << ','
         << s.resampWetCellFraction << ','
         << s.resampDryCellFraction << ','
         << s.resampPoorCellFraction << ','
         << s.resampRichCellFraction << ','
         << s.resampEmptyWetCellFraction << ','
         << s.resampCandidateListsBuilt << ','
         << s.resampReceiverCells << ','
         << s.resampDonorCells << ','
         << s.resampEmptyWetReceiverCells << ','
         << s.resampFirstReceiverCell << ','
         << s.resampLastReceiverCell << ','
         << s.resampFirstDonorCell << ','
         << s.resampLastDonorCell << ','
         << s.resampReceiverMassDeficitToTarget << ','
         << s.resampDonorMassExcessAboveTarget << ','
         << s.resampDonorReceiverMassBalance << ','
         << s.resampPotentialTransferMass << ','
         << s.resampReceiverFractionOfWetCells << ','
         << s.resampDonorFractionOfWetCells << ','
         << s.resampPoolCanSeedReceivers << ','
         << s.resampPoolBuilt << ','
         << s.resampPoolStorageSlots << ','
         << s.resampPoolFreeSlots << ','
         << s.resampPoolLatentSlots << ','
         << s.resampPoolFluidSlots << ','
         << s.resampPoolFirstFreeIndex << ','
         << s.resampPoolLastFreeIndex << ','
         << s.resampPoolFreeSlotFraction << ','
         << s.resampPoolDormantSlotFraction << '\n';
}

} // namespace mpcd
