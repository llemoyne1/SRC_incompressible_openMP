#include "runtime_summary.h"

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
                                       const ImmersedCircleDiagnostics* immersed,
                                       const CollisionDiagnostics* collision,
                                       const Q6ProjectionDiagnostics* q6,
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

    #pragma omp parallel for reduction(+:mass,px,py,kinetic) if(n > 10000)
    for (std::int64_t ii = 0; ii < static_cast<std::int64_t>(n); ++ii) {
        const std::size_t i = static_cast<std::size_t>(ii);
        const double m = state.mass[i];
        mass += m;
        px += m * state.vx[i];
        py += m * state.vy[i];
        kinetic += 0.5 * m * (state.vx[i] * state.vx[i] + state.vy[i] * state.vy[i]);
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
        s.q6Converged = q6->converged ? 1 : 0;
        s.q6Iterations = q6->iterations;
        s.q6EmptyCells = q6->emptyCells;
        s.q6ResidualRel = q6->residualRel;
        s.q6DivBeforeRms = q6->divBeforeRms;
        s.q6DivBeforeMaxAbs = q6->divBeforeMaxAbs;
        s.q6DivAfterProjectedFluxRms = q6->divAfterProjectedFluxRms;
        s.q6DivAfterProjectedFluxMaxAbs = q6->divAfterProjectedFluxMaxAbs;
        s.q6DivAfterCellVelocityRms = q6->divAfterCellVelocityRms;
        s.q6DivAfterCellVelocityMaxAbs = q6->divAfterCellVelocityMaxAbs;
        s.q6CorrectionVelocityRms = q6->correctionVelocityRms;
        s.q6CorrectionVelocityMaxAbs = q6->correctionVelocityMaxAbs;
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
    out_ << "step,time,wallTime,numThreadsUsed,Np,totalMass,Px,Py,meanVx,meanVy,meanKinetic,kBTEstimate,fluidXMin,fluidXMax,fluidYMin,fluidYMax,fluidArea,meanPhysicalDensity,meanN,stdN,minN,maxN,hitsLeft,hitsRight,hitsBottom,hitsTop,hitsImmersed,virtualParticleCount,virtualParticleEquivalent,virtualMass,virtualMassLeft,virtualMassRight,virtualMassBottom,virtualMassTop,virtualMassImmersed,virtualMomentumX,virtualMomentumY,thermostatApplied,thermostatCells,thermostatParticles,thermostatKBTBefore,thermostatKBTAfter,thermostatScaleMean,thermostatScaleMin,thermostatScaleMax,q6Applied,q6Converged,q6Iterations,q6EmptyCells,q6ResidualRel,q6DivBeforeRms,q6DivBeforeMaxAbs,q6DivAfterProjectedFluxRms,q6DivAfterProjectedFluxMaxAbs,q6DivAfterCellVelocityRms,q6DivAfterCellVelocityMaxAbs,q6CorrectionVelocityRms,q6CorrectionVelocityMaxAbs,q6MomentumCorrectionVx,q6MomentumCorrectionVy,q6MomentumResidualBeforeCorrection\n";
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
         << s.q6Converged << ','
         << s.q6Iterations << ','
         << s.q6EmptyCells << ','
         << s.q6ResidualRel << ','
         << s.q6DivBeforeRms << ','
         << s.q6DivBeforeMaxAbs << ','
         << s.q6DivAfterProjectedFluxRms << ','
         << s.q6DivAfterProjectedFluxMaxAbs << ','
         << s.q6DivAfterCellVelocityRms << ','
         << s.q6DivAfterCellVelocityMaxAbs << ','
         << s.q6CorrectionVelocityRms << ','
         << s.q6CorrectionVelocityMaxAbs << ','
         << s.q6MomentumCorrectionVx << ','
         << s.q6MomentumCorrectionVy << ','
         << s.q6MomentumResidualBeforeCorrection << '\n';
}

} // namespace mpcd
