#pragma once

#include "cell_grid.h"
#include "fluid_domain.h"
#include "particle_state.h"
#include "q6_projection_adapter.h"
#include "simulation_params.h"
#include "thermostat.h"

namespace mpcd {


struct CudaQ6ResidentThermostat0400Diagnostics {
    bool requested = false;
    bool handled = false;
    bool supported = false;
    ThermostatDiagnostics thermostat;
    double totalSeconds = 0.0;
    double kineticSeconds = 0.0;
    double scaleSeconds = 0.0;
    double applySeconds = 0.0;
    double diagnosticsDownloadSeconds = 0.0;
    const char* reason = "";
};

struct CudaQ6Resident0400Diagnostics {
    bool requested = false;
    bool handled = false;
    bool supported = false;
    bool applied = false;
    bool converged = false;
    int iterations = 0;
    int blocks = 0;
    int threads = 0;
    std::uint64_t particles = 0u;
    std::uint64_t cells = 0u;
    std::uint64_t emptyCells = 0u;
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
    bool openBoundaryEnabled = false;
    double openBoundaryFluxXLow = 0.0;
    double openBoundaryFluxXHigh = 0.0;
    double openBoundaryFluxYLow = 0.0;
    double openBoundaryFluxYHigh = 0.0;
    double openBoundaryFluxBalance = 0.0;
    double openBoundaryMeanDivergence = 0.0;
    double totalSeconds = 0.0;
    double depositSeconds = 0.0;
    double solveSeconds = 0.0;
    double applySeconds = 0.0;
    const char* reason = "";
};

#if defined(MPCD_ENABLE_CUDA_Q6_RESIDENT_0400)
CudaQ6Resident0400Diagnostics try_apply_cuda_q6_resident_0400(ParticleState& state,
                                                              const SimulationParams& params,
                                                              const CellGrid& grid,
                                                              const FluidDomainBounds& domain,
                                                              int step,
                                                              double time);

CudaQ6ResidentThermostat0400Diagnostics try_apply_cuda_q6_resident_thermostat_0400(
    ParticleState& state,
    const SimulationParams& params,
    const CellGrid& grid,
    const std::vector<int>& collisionCellId,
    std::uint64_t step);
#else
inline CudaQ6Resident0400Diagnostics try_apply_cuda_q6_resident_0400(ParticleState&,
                                                                     const SimulationParams&,
                                                                     const CellGrid&,
                                                                     const FluidDomainBounds&,
                                                                     int,
                                                                     double) {
    return {};
}
inline CudaQ6ResidentThermostat0400Diagnostics try_apply_cuda_q6_resident_thermostat_0400(
    ParticleState&,
    const SimulationParams&,
    const CellGrid&,
    const std::vector<int>&,
    std::uint64_t) {
    return {};
}
#endif

inline Q6ProjectionDiagnostics q6_projection_diagnostics_from_cuda_resident_0400(
    const CudaQ6Resident0400Diagnostics& cudaDiag,
    const SimulationParams& params) {
    Q6ProjectionDiagnostics q6;
    q6.applied = cudaDiag.applied;
    q6.converged = cudaDiag.converged;
    q6.iterations = cudaDiag.iterations;
    q6.emptyCells = cudaDiag.emptyCells;
    q6.projectionStrength = params.q6ProjectionStrength;
    q6.projectionStrengthNominal = params.q6ProjectionStrength;
    q6.residualRel = cudaDiag.residualRel;
    q6.divBeforeRms = cudaDiag.divBeforeRms;
    q6.divBeforeMaxAbs = cudaDiag.divBeforeMaxAbs;
    q6.divAfterProjectedFluxRms = cudaDiag.divAfterProjectedFluxRms;
    q6.divAfterProjectedFluxMaxAbs = cudaDiag.divAfterProjectedFluxMaxAbs;
    q6.divAfterCellVelocityRms = cudaDiag.divAfterCellVelocityRms;
    q6.divAfterCellVelocityMaxAbs = cudaDiag.divAfterCellVelocityMaxAbs;
    q6.correctionVelocityRms = cudaDiag.correctionVelocityRms;
    q6.correctionVelocityMaxAbs = cudaDiag.correctionVelocityMaxAbs;
    q6.momentumCorrectionVx = cudaDiag.momentumCorrectionVx;
    q6.momentumCorrectionVy = cudaDiag.momentumCorrectionVy;
    q6.momentumResidualBeforeCorrection = cudaDiag.momentumResidualBeforeCorrection;
    q6.openBoundaryEnabled = cudaDiag.openBoundaryEnabled;
    q6.openBoundaryFluxXLow = cudaDiag.openBoundaryFluxXLow;
    q6.openBoundaryFluxXHigh = cudaDiag.openBoundaryFluxXHigh;
    q6.openBoundaryFluxYLow = cudaDiag.openBoundaryFluxYLow;
    q6.openBoundaryFluxYHigh = cudaDiag.openBoundaryFluxYHigh;
    q6.openBoundaryFluxBalance = cudaDiag.openBoundaryFluxBalance;
    q6.openBoundaryMeanDivergence = cudaDiag.openBoundaryMeanDivergence;
    // Map CUDA resident timing buckets onto the generic Q6 profile phase names.
    q6.profile.seconds[1] = cudaDiag.depositSeconds;   // q6_deposit_cell_velocity
    q6.profile.seconds[8] = cudaDiag.solveSeconds;     // q6_project_face_field / CG solve
    q6.profile.seconds[17] = cudaDiag.applySeconds;    // q6_apply_particle_velocity_correction
    return q6;
}

} // namespace mpcd
