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
                                       const Q9ProjectionDiagnostics* q9,
                                       const VirialPressureDiagnostics* virial,
                                       const ThermostatDiagnostics* thermostat,
                                       int numThreadsUsed) {
    validate_particle_state(state, "compute_runtime_summary");
    RuntimeSummary s{};
    s.step = step;
    s.time = static_cast<double>(step) * params.dt;
    s.wallTime = wallTime;
    s.numThreadsUsed = numThreadsUsed > 0 ? numThreadsUsed : 1;
    s.Np = state.Np;

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
        const double m = state.mass[i];
        mass += m;
        const double vx = state.vx[i];
        const double vy = state.vy[i];
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
    if (n > 0u) {
        s.meanKinetic = kinetic / static_cast<double>(n);
        s.meanParticleSpeed = speedSum / static_cast<double>(n);
        s.maxParticleSpeed = maxSpeed;
        s.maxParticleAbsVx = maxAbsVx;
        s.maxParticleAbsVy = maxAbsVy;
    }

    double thermal = 0.0;
    #pragma omp parallel for reduction(+:thermal) if(n > 10000)
    for (std::int64_t ii = 0; ii < static_cast<std::int64_t>(n); ++ii) {
        const std::size_t i = static_cast<std::size_t>(ii);
        const double dvx = state.vx[i] - s.meanVx;
        const double dvy = state.vy[i] - s.meanVy;
        thermal += state.mass[i] * (dvx * dvx + dvy * dvy);
    }
    if (n > 0u) {
        s.kBTEstimate = thermal / (2.0 * static_cast<double>(n));
    }

    if (boundary != nullptr) {
        s.hitsLeft = boundary->hitsLeft;
        s.hitsRight = boundary->hitsRight;
        s.hitsBottom = boundary->hitsBottom;
        s.hitsTop = boundary->hitsTop;
        s.maxXWallReflectionsPerParticle = boundary->maxXWallReflectionsPerParticle;
        s.maxYWallReflectionsPerParticle = boundary->maxYWallReflectionsPerParticle;
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
        s.q6ImmersedSolidClosedXFaces = q6->immersedSolidClosedXFaces;
        s.q6ImmersedSolidClosedYFaces = q6->immersedSolidClosedYFaces;
        s.q6ResidualRel = q6->residualRel;
        s.q6DivBeforeRms = q6->divBeforeRms;
        s.q6DivBeforeMaxAbs = q6->divBeforeMaxAbs;
        s.q6DivAfterProjectedFluxRms = q6->divAfterProjectedFluxRms;
        s.q6DivAfterProjectedFluxMaxAbs = q6->divAfterProjectedFluxMaxAbs;
        s.q6DivAfterCellVelocityRms = q6->divAfterCellVelocityRms;
        s.q6DivAfterCellVelocityMaxAbs = q6->divAfterCellVelocityMaxAbs;
        s.q6ImmersedSolidLeakProjectedFluxRms = q6->immersedSolidLeakProjectedFluxRms;
        s.q6ImmersedSolidLeakProjectedFluxMaxAbs = q6->immersedSolidLeakProjectedFluxMaxAbs;
        s.q6CorrectionVelocityRms = q6->correctionVelocityRms;
        s.q6CorrectionVelocityMaxAbs = q6->correctionVelocityMaxAbs;
        s.q6MomentumCorrectionVx = q6->momentumCorrectionVx;
        s.q6MomentumCorrectionVy = q6->momentumCorrectionVy;
        s.q6MomentumResidualBeforeCorrection = q6->momentumResidualBeforeCorrection;
    }

    if (q9 != nullptr) {
        s.q9Applied = q9->applied ? 1 : 0;
        s.q9Converged = q9->converged ? 1 : 0;
        s.q9Iterations = q9->iterations;
        s.q9EmptyCells = q9->emptyCells;
        s.q9ImmersedSolidFluidCells = q9->immersedSolidFluidCells;
        s.q9ImmersedSolidSolidCells = q9->immersedSolidSolidCells;
        s.q9ImmersedSolidClosedXFaces = q9->immersedSolidClosedXFaces;
        s.q9ImmersedSolidClosedYFaces = q9->immersedSolidClosedYFaces;
        s.q9ResidualRel = q9->residualRel;
        s.q9MassFluxDivBeforeRms = q9->massFluxDivBeforeRms;
        s.q9MassFluxDivBeforeMaxAbs = q9->massFluxDivBeforeMaxAbs;
        s.q9MassFluxDivAfterRms = q9->massFluxDivAfterRms;
        s.q9MassFluxDivAfterMaxAbs = q9->massFluxDivAfterMaxAbs;
        s.q9TargetDivergenceRms = q9->targetDivergenceRms;
        s.q9TargetDivergenceRawRms = q9->targetDivergenceRawRms;
        s.q9TargetDivergenceFilterRatio = q9->targetDivergenceFilterRatio;
        s.q9DensityMean = q9->densityMean;
        s.q9DensityStdBefore = q9->densityStdBefore;
        s.q9DensityStdAfterEstimate = q9->densityStdAfterEstimate;
        s.q9DensityStdRatioEstimate = q9->densityStdRatioEstimate;
        s.q9ImmersedSolidLeakMassFluxRms = q9->immersedSolidLeakMassFluxRms;
        s.q9ImmersedSolidLeakMassFluxMaxAbs = q9->immersedSolidLeakMassFluxMaxAbs;
        s.q9CorrectionVelocityRms = q9->correctionVelocityRms;
        s.q9CorrectionVelocityMaxAbs = q9->correctionVelocityMaxAbs;
        s.q9MomentumCorrectionVx = q9->momentumCorrectionVx;
        s.q9MomentumCorrectionVy = q9->momentumCorrectionVy;
        s.q9MomentumResidualBeforeCorrection = q9->momentumResidualBeforeCorrection;
    }

    if (virial != nullptr) {
        s.virialEnabled = virial->enabled ? 1 : 0;
        s.virialDiagnosticsEnabled = virial->diagnosticsEnabled ? 1 : 0;
        s.virialKickEnabled = virial->kickEnabled ? 1 : 0;
        s.virialKickApplied = virial->kickApplied ? 1 : 0;
        s.virialK = virial->Kvirial;
        s.virialBeta = virial->betaVirial;
        s.virialRhoMean = virial->rhoMean;
        s.virialRhoEOSRef = virial->rhoEOSRef;
        s.virialRhoUniformNow = virial->rhoUniformNow;
        s.virialRhoDriveRef = virial->rhoDriveRef;
        s.virialRhoDefectRms = virial->rhoDefectRms;
        s.virialRhoDefectRelRms = virial->rhoDefectRelRms;
        s.PkinMean = virial->PkinMean;
        s.PvirMean = virial->PvirMean;
        s.PtotMean = virial->PtotMean;
        s.PdriveMean = virial->PdriveMean;
        s.gradPdriveRms = virial->gradPdriveRms;
        s.gradPdriveMaxAbs = virial->gradPdriveMaxAbs;
        s.virialDuRawRms = virial->duVirialRawRms;
        s.virialDuAppliedRms = virial->duVirialAppliedRms;
        s.virialDuAppliedMaxAbs = virial->duVirialAppliedMaxAbs;
        s.virialDuOverThermalRms = virial->duVirialOverThermalRms;
        s.virialMomentumCorrectionVx = virial->momentumCorrectionVx;
        s.virialMomentumCorrectionVy = virial->momentumCorrectionVy;
        s.virialMomentumResidualBeforeCorrection = virial->momentumResidualBeforeCorrection;
        s.virialMomentumResidualAfterCorrection = virial->momentumResidualAfterCorrection;
    }
    if (thermostat != nullptr) {        s.thermostatApplied = thermostat->applied ? 1 : 0;
        s.thermostatCells = thermostat->cellsRescaled;
        s.thermostatParticles = thermostat->particlesRescaled;
        s.thermostatKBTBefore = thermostat->kBTBefore;
        s.thermostatKBTAfter = thermostat->kBTAfter;
        s.thermostatScaleMean = thermostat->scaleMean;
        s.thermostatScaleMin = thermostat->scaleMin;
        s.thermostatScaleMax = thermostat->scaleMax;
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
        s.meanN = nc > 0.0 ? static_cast<double>(n) / nc : 0.0;
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
    out_ << "step,time,wallTime,numThreadsUsed,Np,totalMass,Px,Py,meanVx,meanVy,meanKinetic,kBTEstimate,meanParticleSpeed,maxParticleSpeed,maxParticleAbsVx,maxParticleAbsVy,fluidXMin,fluidXMax,fluidYMin,fluidYMax,fluidArea,meanPhysicalDensity,meanN,stdN,minN,maxN,hitsLeft,hitsRight,hitsBottom,hitsTop,maxXWallReflectionsPerParticle,maxYWallReflectionsPerParticle,hitsImmersed,virtualParticleCount,virtualParticleEquivalent,virtualMass,virtualMassLeft,virtualMassRight,virtualMassBottom,virtualMassTop,virtualMassImmersed,virtualMomentumX,virtualMomentumY,thermostatApplied,thermostatCells,thermostatParticles,thermostatKBTBefore,thermostatKBTAfter,thermostatScaleMean,thermostatScaleMin,thermostatScaleMax,q6Applied,q6ProjectionStrength,q6Converged,q6Iterations,q6EmptyCells,q6ImmersedSolidFluidCells,q6ImmersedSolidSolidCells,q6ImmersedSolidClosedXFaces,q6ImmersedSolidClosedYFaces,q6ResidualRel,q6DivBeforeRms,q6DivBeforeMaxAbs,q6DivAfterProjectedFluxRms,q6DivAfterProjectedFluxMaxAbs,q6DivAfterCellVelocityRms,q6DivAfterCellVelocityMaxAbs,q6ImmersedSolidLeakProjectedFluxRms,q6ImmersedSolidLeakProjectedFluxMaxAbs,q6CorrectionVelocityRms,q6CorrectionVelocityMaxAbs,q6MomentumCorrectionVx,q6MomentumCorrectionVy,q6MomentumResidualBeforeCorrection,q9Applied,q9Converged,q9Iterations,q9EmptyCells,q9ImmersedSolidFluidCells,q9ImmersedSolidSolidCells,q9ImmersedSolidClosedXFaces,q9ImmersedSolidClosedYFaces,q9ResidualRel,q9MassFluxDivBeforeRms,q9MassFluxDivBeforeMaxAbs,q9MassFluxDivAfterRms,q9MassFluxDivAfterMaxAbs,q9TargetDivergenceRms,q9TargetDivergenceRawRms,q9TargetDivergenceFilterRatio,q9DensityMean,q9DensityStdBefore,q9DensityStdAfterEstimate,q9DensityStdRatioEstimate,q9ImmersedSolidLeakMassFluxRms,q9ImmersedSolidLeakMassFluxMaxAbs,q9CorrectionVelocityRms,q9CorrectionVelocityMaxAbs,q9MomentumCorrectionVx,q9MomentumCorrectionVy,q9MomentumResidualBeforeCorrection,virialEnabled,virialDiagnosticsEnabled,virialKickEnabled,virialKickApplied,virialK,virialBeta,virialRhoMean,virialRhoEOSRef,virialRhoUniformNow,virialRhoDriveRef,virialRhoDefectRms,virialRhoDefectRelRms,PkinMean,PvirMean,PtotMean,PdriveMean,gradPdriveRms,gradPdriveMaxAbs,virialDuRawRms,virialDuAppliedRms,virialDuAppliedMaxAbs,virialDuOverThermalRms,virialMomentumCorrectionVx,virialMomentumCorrectionVy,virialMomentumResidualBeforeCorrection,virialMomentumResidualAfterCorrection\n";
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
         << s.q6ImmersedSolidClosedXFaces << ','
         << s.q6ImmersedSolidClosedYFaces << ','
         << s.q6ResidualRel << ','
         << s.q6DivBeforeRms << ','
         << s.q6DivBeforeMaxAbs << ','
         << s.q6DivAfterProjectedFluxRms << ','
         << s.q6DivAfterProjectedFluxMaxAbs << ','
         << s.q6DivAfterCellVelocityRms << ','
         << s.q6DivAfterCellVelocityMaxAbs << ','
         << s.q6ImmersedSolidLeakProjectedFluxRms << ','
         << s.q6ImmersedSolidLeakProjectedFluxMaxAbs << ','
         << s.q6CorrectionVelocityRms << ','
         << s.q6CorrectionVelocityMaxAbs << ','
         << s.q6MomentumCorrectionVx << ','
         << s.q6MomentumCorrectionVy << ','
         << s.q6MomentumResidualBeforeCorrection << ','
         << s.q9Applied << ','
         << s.q9Converged << ','
         << s.q9Iterations << ','
         << s.q9EmptyCells << ','
         << s.q9ImmersedSolidFluidCells << ','
         << s.q9ImmersedSolidSolidCells << ','
         << s.q9ImmersedSolidClosedXFaces << ','
         << s.q9ImmersedSolidClosedYFaces << ','
         << s.q9ResidualRel << ','
         << s.q9MassFluxDivBeforeRms << ','
         << s.q9MassFluxDivBeforeMaxAbs << ','
         << s.q9MassFluxDivAfterRms << ','
         << s.q9MassFluxDivAfterMaxAbs << ','
         << s.q9TargetDivergenceRms << ','
         << s.q9TargetDivergenceRawRms << ','
         << s.q9TargetDivergenceFilterRatio << ','
         << s.q9DensityMean << ','
         << s.q9DensityStdBefore << ','
         << s.q9DensityStdAfterEstimate << ','
         << s.q9DensityStdRatioEstimate << ','
         << s.q9ImmersedSolidLeakMassFluxRms << ','
         << s.q9ImmersedSolidLeakMassFluxMaxAbs << ','
         << s.q9CorrectionVelocityRms << ','
         << s.q9CorrectionVelocityMaxAbs << ','
         << s.q9MomentumCorrectionVx << ','
         << s.q9MomentumCorrectionVy << ','
         << s.q9MomentumResidualBeforeCorrection << ','
         << s.virialEnabled << ','
         << s.virialDiagnosticsEnabled << ','
         << s.virialKickEnabled << ','
         << s.virialKickApplied << ','
         << s.virialK << ','
         << s.virialBeta << ','
         << s.virialRhoMean << ','
         << s.virialRhoEOSRef << ','
         << s.virialRhoUniformNow << ','
         << s.virialRhoDriveRef << ','
         << s.virialRhoDefectRms << ','
         << s.virialRhoDefectRelRms << ','
         << s.PkinMean << ','
         << s.PvirMean << ','
         << s.PtotMean << ','
         << s.PdriveMean << ','
         << s.gradPdriveRms << ','
         << s.gradPdriveMaxAbs << ','
         << s.virialDuRawRms << ','
         << s.virialDuAppliedRms << ','
         << s.virialDuAppliedMaxAbs << ','
         << s.virialDuOverThermalRms << ','
         << s.virialMomentumCorrectionVx << ','
         << s.virialMomentumCorrectionVy << ','
         << s.virialMomentumResidualBeforeCorrection << ','
         << s.virialMomentumResidualAfterCorrection << '\n';
}

} // namespace mpcd
