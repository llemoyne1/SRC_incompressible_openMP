#pragma once

#include <cstdint>
#include <vector>

#include "cell_grid.h"
#include "elliptic_projection.h"
#include "fluid_domain.h"
#include "immersed_solid.h"
#include "particle_state.h"
#include "simulation_params.h"

namespace mpcd {

// Q9 mass-flux projection adapter using the generic elliptic face-field core.
//
// This first implementation is deliberately compact and uses the same face-field
// conventions as Q6. It deposits real-particle cell mass and momentum, builds a
// mass-flux-like face field J*=M U, asks the elliptic core to drive div(J) toward
// a uniform-density relaxation target, then converts the correction flux dJ into
// a nearest-cell velocity kick dU=dJ/M. The generic elliptic core remains unaware
// of Q9: it only sees baseFlux, alpha and targetDivergence.

struct Q9ProjectionDiagnostics {
    bool applied = false;
    bool converged = false;
    int iterations = 0;
    std::uint64_t emptyCells = 0;
    std::uint64_t immersedSolidFluidCells = 0;
    std::uint64_t immersedSolidSolidCells = 0;
    std::uint64_t immersedSolidClosedXFaces = 0;
    std::uint64_t immersedSolidClosedYFaces = 0;
    std::uint64_t immersedSolidCellClosedXFaces = 0;
    std::uint64_t immersedSolidCellClosedYFaces = 0;
    std::uint64_t immersedSolidCutClosedXFaces = 0;
    std::uint64_t immersedSolidCutClosedYFaces = 0;

    double residualRel = 0.0;
    double massFluxDivBeforeRms = 0.0;
    double massFluxDivBeforeMaxAbs = 0.0;
    double massFluxDivAfterRms = 0.0;
    double massFluxDivAfterMaxAbs = 0.0;
    double targetDivergenceRms = 0.0;
    double targetDivergenceRawRms = 0.0;
    double targetDivergenceFilterRatio = 1.0;
    double densityMean = 0.0;
    double densityStdBefore = 0.0;
    double densityStdAfterEstimate = 0.0;
    double densityStdRatioEstimate = 0.0;
    double immersedSolidLeakMassFluxRms = 0.0;
    double immersedSolidLeakMassFluxMaxAbs = 0.0;
    double immersedSolidLeakCellClosedMassFluxRms = 0.0;
    double immersedSolidLeakCellClosedMassFluxMaxAbs = 0.0;
    double immersedSolidLeakCutMassFluxRms = 0.0;
    double immersedSolidLeakCutMassFluxMaxAbs = 0.0;
    double correctionVelocityRms = 0.0;
    double correctionVelocityMaxAbs = 0.0;

    // 0066 safety diagnostics.  Raw values are measured before low-mass
    // suppression and velocity limiting; correctionVelocity* above is the
    // actually applied kick after safeguards.
    std::uint64_t safetyActiveCells = 0;
    std::uint64_t safetyExcludedCells = 0;
    std::uint64_t openBoundaryExcludedCells = 0;
    std::uint64_t immersedHaloExcludedCells = 0;
    std::uint64_t lowMassSuppressedCells = 0;
    std::uint64_t velocityLimitedCells = 0;
    double correctionVelocityRawRms = 0.0;
    double correctionVelocityRawMaxAbs = 0.0;
    double correctionVelocityLimiter = 0.0;
    double minCellMassForCorrection = 0.0;

    bool openBoundaryEnabled = false;
    double openBoundaryMassFluxXLow = 0.0;
    double openBoundaryMassFluxXHigh = 0.0;
    double openBoundaryMassFluxYLow = 0.0;
    double openBoundaryMassFluxYHigh = 0.0;
    double openBoundaryMassFluxBalance = 0.0;
    double openBoundaryMeanDivergence = 0.0;

    double momentumCorrectionVx = 0.0;
    double momentumCorrectionVy = 0.0;
    double momentumResidualBeforeCorrection = 0.0;
};

struct Q9ProjectionWorkspace {
    int allocatedCells = 0;
    std::uint64_t allocatedParticles = 0;

    std::vector<int> cellId;
    std::vector<double> cellMass;
    std::vector<double> cellPx;
    std::vector<double> cellPy;
    std::vector<double> cellDUx;
    std::vector<double> cellDUy;
    std::vector<double> localMass;
    std::vector<double> localPx;
    std::vector<double> localPy;
    std::vector<double> targetDivergence;
    std::vector<double> massAfterEstimate;

    PeriodicFaceField baseMassFlux;
    PeriodicFaceField alpha;
    PeriodicFaceField appliedCorrectionFlux;
    PeriodicFaceField projectedMassFlux;
    EllipticProjectionWorkspace elliptic;
    ImmersedSolidProjectionMask immersedMask;
    EllipticProjectionMask ellipticMask;
    std::vector<std::uint8_t> maskScratch;
};

bool q9_projection_requested(const SimulationParams& params);

Q9ProjectionDiagnostics apply_q9_mass_flux_projection(ParticleState& state,
                                                      const SimulationParams& params,
                                                      const CellGrid& grid,
                                                      const FluidDomainBounds& domain,
                                                      Q9ProjectionWorkspace& workspace);

} // namespace mpcd
