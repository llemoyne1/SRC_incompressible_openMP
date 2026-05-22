#pragma once

#include <cstdint>
#include <vector>

#include "cell_grid.h"
#include "elliptic_projection.h"
#include "particle_state.h"
#include "simulation_params.h"

namespace mpcd {

// First physical consumer of the generic elliptic projection core.
//
// This adapter performs a periodic Q6 velocity projection on a fixed Eulerian
// grid. It deliberately remains thin: particle velocities are deposited to
// cell-centered mass-weighted velocities, converted to periodic face velocities,
// projected by the generic face-field core with target divergence zero and
// alpha=1, then mapped back to particles as a nearest-cell velocity correction.
//
// Validation scope for this first adapter is documented as fully periodic fixed
// boxes. The code itself does not enforce that scope, keeping the runtime path
// compact and allowing controlled experiments.

struct Q6ProjectionDiagnostics {
    bool applied = false;
    bool converged = false;
    int iterations = 0;
    std::uint64_t emptyCells = 0;

    double residualRel = 0.0;
    double divBeforeRms = 0.0;
    double divBeforeMaxAbs = 0.0;
    double divAfterProjectedFluxRms = 0.0;
    double divAfterProjectedFluxMaxAbs = 0.0;
    double divAfterCellVelocityRms = 0.0;
    double divAfterCellVelocityMaxAbs = 0.0;
    double correctionVelocityRms = 0.0;
    double correctionVelocityMaxAbs = 0.0;
    double momentumCorrectionVx = 0.0;
    double momentumCorrectionVy = 0.0;
    double momentumResidualBeforeCorrection = 0.0;
};

struct Q6ProjectionWorkspace {
    int allocatedCells = 0;
    std::uint64_t allocatedParticles = 0;

    std::vector<int> cellId;
    std::vector<double> cellMass;
    std::vector<double> cellPx;
    std::vector<double> cellPy;
    std::vector<double> cellUx;
    std::vector<double> cellUy;
    std::vector<double> cellDUx;
    std::vector<double> cellDUy;
    std::vector<double> correctedCellUx;
    std::vector<double> correctedCellUy;
    std::vector<double> localMass;
    std::vector<double> localPx;
    std::vector<double> localPy;

    PeriodicFaceField baseFlux;
    PeriodicFaceField alpha;
    PeriodicFaceField correctedCellFlux;
    std::vector<double> targetDivergence;
    EllipticProjectionWorkspace elliptic;
};

bool q6_projection_requested(const SimulationParams& params);

Q6ProjectionDiagnostics apply_q6_periodic_projection(ParticleState& state,
                                                     const SimulationParams& params,
                                                     const CellGrid& grid,
                                                     Q6ProjectionWorkspace& workspace);

} // namespace mpcd
