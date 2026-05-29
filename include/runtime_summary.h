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
                                       int numThreadsUsed = 1);

class RuntimeSummaryWriter {
public:
    explicit RuntimeSummaryWriter(const std::string& filepath);
    void append(const RuntimeSummary& s);

private:
    std::ofstream out_;
};

} // namespace mpcd
