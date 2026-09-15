#pragma once

#include "cell_grid.h"
#include "fluid_domain.h"
#include "particle_state.h"
#include "q6_projection_adapter.h"
#include "simulation_params.h"
#include "thermostat.h"

namespace mpcd {

class CudaSpeciesCellWorkspace0490h;

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

// 0493x14ax: read-only view of the physical x6c phase field for
// observation-only diagnostics/recording.  The pointer stays owned by the
// resident Q6 workspace and consumers must never write or free it.
struct CudaQ6PhaseAlphaView0493x6c {
    const double* deviceAlpha = nullptr;
    int nx = 0;
    int ny = 0;
    int step = -1;
    bool valid = false;
};

// 0493x9b: read-only resident view for diagnostics/LiveVis.  The pointer
// remains owned by the Q6 workspace and must never be freed or written by the
// consumer.  valid is true only after the passive x9b curvature stage ran.
struct CudaQ6PhaseCurvatureView0493x9b {
    const double* deviceCurvature = nullptr;
    int nx = 0;
    int ny = 0;
    int step = -1;
    bool valid = false;
};

// 0493x9d production-selected curvature view: three binomial 3x3 passes
// followed by the validated Scharr normal/divergence operator (x9c p3).
struct CudaQ6PhaseCurvatureView0493x9d {
    const double* deviceCurvature = nullptr;
    // 0493x9e: physical x6c alpha, exposed read-only so LiveVis can mask the
    // bulk without recomputing or smoothing the interface geometry.
    const double* deviceAlpha = nullptr;
    int nx = 0;
    int ny = 0;
    int step = -1;
    bool valid = false;
};

struct CudaChiMembraneDiagnostics0493x17c {
    bool available = false;
    bool initialized = false;
    bool advanced = false;
    int nodeCount = 0;
    int edgeCount = 0;
    double mass = 0.0;
    double nodeMass = 0.0;
    double centerX = 0.0;
    double centerY = 0.0;
    double meanVelocityXBefore = 0.0;
    double meanVelocityYBefore = 0.0;
    double meanVelocityXAfter = 0.0;
    double meanVelocityYAfter = 0.0;
    double momentumBeforeX = 0.0;
    double momentumBeforeY = 0.0;
    double momentumAfterX = 0.0;
    double momentumAfterY = 0.0;
    double nodeReactionImpulseX = 0.0;
    double nodeReactionImpulseY = 0.0;
    double cellReactionImpulseX = 0.0;
    double cellReactionImpulseY = 0.0;
    double loadProjectionResidualX = 0.0;
    double loadProjectionResidualY = 0.0;
    int pinnedNodeCount = 0;
    double supportConstraintImpulseX = 0.0;
    double supportConstraintImpulseY = 0.0;
    double internalForceSumX = 0.0;
    double internalForceSumY = 0.0;
    double signedArea0 = 0.0;
    double signedArea = 0.0;
    double areaRelativeChange = 0.0;
    double perimeter0 = 0.0;
    double perimeter = 0.0;
    double perimeterRelativeChange = 0.0;
    double maxAbsEdgeStrain = 0.0;
    double stretchEnergy = 0.0;
    double bendingEnergy = 0.0;
    double maxAbsAngleChange = 0.0;
    double areaEnergy = 0.0;
    double kineticEnergyBefore = 0.0;
    double kineticEnergyAfter = 0.0;
    double stabilityNumber = 0.0;
};

struct CudaChiHingedPlateDiagnostics0493x18a {
    bool available = false;
    bool initialized = false;
    bool advanced = false;
    int nodeCount = 0;
    int edgeCount = 0;
    double mass = 0.0;
    double inertia = 0.0;
    double pivotX = 0.0;
    double pivotY = 0.0;
    double centerX = 0.0;
    double centerY = 0.0;
    double theta = 0.0;
    double omegaBefore = 0.0;
    double omegaAfter = 0.0;
    double momentumBeforeX = 0.0;
    double momentumBeforeY = 0.0;
    double momentumAfterX = 0.0;
    double momentumAfterY = 0.0;
    double nodeReactionImpulseX = 0.0;
    double nodeReactionImpulseY = 0.0;
    double cellReactionImpulseX = 0.0;
    double cellReactionImpulseY = 0.0;
    double loadProjectionResidualX = 0.0;
    double loadProjectionResidualY = 0.0;
    double hydroTorqueImpulse = 0.0;
    double gravityTorque = 0.0;
    double dampingTorque = 0.0;
    double gravityImpulseY = 0.0;
    double hingeReactionImpulseX = 0.0;
    double hingeReactionImpulseY = 0.0;
    double angularBalanceResidual = 0.0;
    // 0493x18e: normal-path local FSI subcycling diagnostics.
    bool fsiSubcycled = false;
    int fsiSubsteps = 1;
    double maxAbsOmegaSubstep = 0.0;
    double maxAngularIncrement = 0.0;
    double maxTipDisplacementCells = 0.0;
};

struct CudaQ6ForceKick0493x3Diagnostics {
    bool requested = false;
    bool handled = false;
    bool applied = false;
    std::uint64_t particles = 0u;
    int blocks = 0;
    int threads = 0;
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
    double speciesQ6BarycentricResidualMaxAbs = 0.0;
    double speciesQ6BarycentricResidualMaxScaled = 0.0;
    bool speciesQ6IndependentMasked = false;
    std::uint64_t speciesQ6IndependentSolves = 0u;
    std::uint64_t speciesQ6IndependentActiveCells = 0u;
    std::uint64_t speciesQ6IndependentCorrectedParticles = 0u;
    double speciesQ6IndependentDisabledCorrectionMaxAbs = 0.0;
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
    std::uint64_t speciesQ6AllocatedBytes = 0u;
    std::uint64_t speciesQ6AllocationCalls = 0u;
    std::uint64_t speciesQ6MetadataH2DBytes = 0u;
    double speciesQ6DepositSeconds = 0.0;
    double speciesQ6WeightSeconds = 0.0;
    double speciesQ6ParticleApplySeconds = 0.0;
    bool fusedForceKick0493x4b = false;
    const char* reason = "";
};

#if defined(MPCD_ENABLE_CUDA_Q6_RESIDENT_0400)
CudaQ6PhaseAlphaView0493x6c cuda_q6_phase_alpha_view_0493x6c();
CudaQ6PhaseCurvatureView0493x9b cuda_q6_phase_curvature_view_0493x9b();
CudaQ6PhaseCurvatureView0493x9d cuda_q6_phase_curvature_view_0493x9d();

// 0493x16j-fix1: run the chi material-wall crossing at the actual pre-stream
// time level, independently of the selected species-Q6 branch.  The routine
// reuses the resident x10n/Q2/x10p/q engine and leaves the shared particle
// state resident for the CUDA streaming stage that follows.
bool cuda_q6_apply_chi_kinetic_boundary_prestream_0493x16j(
    ParticleState& state,
    const SimulationParams& params,
    const CellGrid& grid,
    int step,
    double time);

// Exact cell-resolved reaction impulse exerted on the chi material wall by
// the latest x16j pre-stream crossing pass.
bool cuda_q6_chi_kinetic_wall_reaction_device_0493x16j(
    const double** deviceReactionX, const double** deviceReactionY, int* nx, int* ny);

// 0493x17c: kick the true nodal membrane after the x17a space-time
// collision/drift step.  The persistent Lagrangian loop remains authoritative;
// chi is not re-extracted.  Internal spring/area/dashpot forces are exactly
// momentum-conserving up to roundoff and the kinetic wall impulse is already
// distributed to impact-edge nodes by the collision kernel.
bool cuda_q6_advance_chi_membrane_0493x17c(
    const SimulationParams& params,
    const CellGrid& grid,
    int step,
    double time,
    CudaChiMembraneDiagnostics0493x17c* diagnostics);

// 0493x18a: one-DOF rigid finite-thickness plate hinged about a fixed z axis.
// The current material contour is a rigid transform of the initial chi loop;
// fluid impacts supply the exact generalized angular impulse, while gravity
// and viscous hinge damping provide the external restoring/loading torques.
bool cuda_q6_advance_chi_hinged_plate_0493x18a(
    const SimulationParams& params,
    const CellGrid& grid,
    int step,
    double time,
    CudaChiHingedPlateDiagnostics0493x18a* diagnostics);

// 0493x16l: observation-only post-stream penetration diagnostic.  It samples
// the same resident chi geometry with the x10 Q2 convention after the solid
// has been synchronized to t+dt.  No particle state, force, or geometry is
// modified.  Rows are written only on normal summary/audit steps.
bool cuda_q6_record_chi_penetration_poststream_0493x16l(
    ParticleState& state,
    const SimulationParams& params,
    const CellGrid& grid,
    int step,
    double timePoststream);

CudaQ6ForceKick0493x3Diagnostics try_apply_cuda_q6_force_kick_0493x3(
    ParticleState& state,
    const SimulationParams& params);

CudaQ6Resident0400Diagnostics try_apply_cuda_q6_resident_0400(ParticleState& state,
                                                              const SimulationParams& params,
                                                              const CellGrid& grid,
                                                              const FluidDomainBounds& domain,
                                                              int step,
                                                              double time,
                                                              CudaSpeciesCellWorkspace0490h* speciesWorkspace0491c = nullptr,
                                                              bool fuseForceKick0493x4b = false);

CudaQ6ResidentThermostat0400Diagnostics try_apply_cuda_q6_resident_thermostat_0400(
    ParticleState& state,
    const SimulationParams& params,
    const CellGrid& grid,
    const std::vector<int>& collisionCellId,
    std::uint64_t step);
#else
inline CudaQ6PhaseAlphaView0493x6c cuda_q6_phase_alpha_view_0493x6c() {
    return {};
}
inline CudaQ6PhaseCurvatureView0493x9b cuda_q6_phase_curvature_view_0493x9b() {
    return {};
}
inline CudaQ6PhaseCurvatureView0493x9d cuda_q6_phase_curvature_view_0493x9d() {
    return {};
}
inline bool cuda_q6_apply_chi_kinetic_boundary_prestream_0493x16j(
    ParticleState&, const SimulationParams&, const CellGrid&, int, double) {
    return false;
}
inline bool cuda_q6_chi_kinetic_wall_reaction_device_0493x16j(
    const double** x, const double** y, int* nx, int* ny) {
    if (x) *x = nullptr; if (y) *y = nullptr; if (nx) *nx = 0; if (ny) *ny = 0;
    return false;
}
inline bool cuda_q6_advance_chi_membrane_0493x17c(
    const SimulationParams&, const CellGrid&, int, double,
    CudaChiMembraneDiagnostics0493x17c*) {
    return false;
}
inline bool cuda_q6_advance_chi_hinged_plate_0493x18a(
    const SimulationParams&, const CellGrid&, int, double,
    CudaChiHingedPlateDiagnostics0493x18a*) {
    return false;
}
inline bool cuda_q6_record_chi_penetration_poststream_0493x16l(
    ParticleState&, const SimulationParams&, const CellGrid&, int, double) {
    return false;
}
inline CudaQ6ForceKick0493x3Diagnostics try_apply_cuda_q6_force_kick_0493x3(
    ParticleState&, const SimulationParams&) {
    return {};
}
inline CudaQ6Resident0400Diagnostics try_apply_cuda_q6_resident_0400(ParticleState&,
                                                                     const SimulationParams&,
                                                                     const CellGrid&,
                                                                     const FluidDomainBounds&,
                                                                     int,
                                                                     double,
                                                                     CudaSpeciesCellWorkspace0490h* = nullptr,
                                                                     bool = false) {
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
    q6.speciesQ6BarycentricResidualMaxAbs = cudaDiag.speciesQ6BarycentricResidualMaxAbs;
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
