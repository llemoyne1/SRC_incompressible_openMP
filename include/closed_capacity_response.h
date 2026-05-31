#pragma once

#include <cstdint>
#include <vector>

#include "cell_grid.h"
#include "fluid_domain.h"
#include "particle_state.h"
#include "simulation_params.h"

namespace mpcd {

struct ClosedCapacityResponseDiagnostics {
    bool enabled = false;
    bool computed = false;
    bool virialKickApplied = false;

    std::uint64_t referenceCells = 0;
    double referenceCellMass = 0.0;
    double referenceMass = 0.0;
    double totalMass = 0.0;
    double overfillMass = 0.0;
    double overfillRatio = 0.0;

    double q6ProjectionStrengthNominal = 0.0;
    double q6ProjectionFactor = 1.0;
    double q6ProjectionStrengthEffective = 0.0;

    double massRemapFactor = 1.0;

    double virialKBase = 0.0;
    double virialKFactor = 1.0;
    double virialKEffective = 0.0;
    double virialPressureMean = 0.0;
    double virialPressureRms = 0.0;
    double virialPressureMin = 0.0;
    double virialPressureMax = 0.0;

    double virialKickVelocityRms = 0.0;
    double virialKickVelocityMaxAbs = 0.0;
    double virialMomentumResidualBeforeCorrection = 0.0;
    double virialMomentumCorrectionVx = 0.0;
    double virialMomentumCorrectionVy = 0.0;
};

struct ClosedCapacityResponseWorkspace {
    int allocatedCells = 0;
    std::uint64_t allocatedParticles = 0;
    std::vector<int> cellId;
    std::vector<double> cellMass;
    std::vector<double> localMass;
    std::vector<double> pressure;
    std::vector<double> kickVx;
    std::vector<double> kickVy;
};

bool closed_capacity_response_requested(const SimulationParams& params);

double closed_capacity_reference_cell_mass(const SimulationParams& params);

ClosedCapacityResponseDiagnostics compute_closed_capacity_response_from_cell_masses(
    const SimulationParams& params,
    const CellGrid& grid,
    const FluidDomainBounds& domain,
    const std::vector<double>& cellMass,
    const std::vector<std::uint8_t>* activeCellMask = nullptr,
    double q6NominalStrength = 0.0);

ClosedCapacityResponseDiagnostics apply_closed_capacity_virial_kick(
    ParticleState& state,
    const SimulationParams& params,
    const CellGrid& grid,
    const FluidDomainBounds& domain,
    ClosedCapacityResponseWorkspace& workspace);

} // namespace mpcd
