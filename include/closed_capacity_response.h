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
    // Effective mass target used by the local mass-remap stage when the
    // closed-capacity response is enabled.  It keeps the nominal target at
    // referenceCellMass below capacity, then adds the global overfill mass
    // uniformly per reference wet/active cell so the remap homogenizes the
    // compression instead of erasing it.
    double massRemapTargetCellMassNominal = 0.0;
    double massRemapOverfillPerCell = 0.0;
    double massRemapTargetCellMassEffective = 0.0;

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

    // Wall-load diagnostics for closed, pressurized domains.  These are not
    // yet coupled back to a deformable solid; they expose the normal load that
    // a later structural module should receive.  Sign convention for forces:
    // force exerted by the fluid on the wall, with outward normals left=-x,
    // right=+x, bottom=-y, top=+y.  Pressure means are length-weighted over
    // the solid portions of each boundary face; segmented inlet/outlet
    // apertures are excluded.
    bool wallLoadComputed = false;
    double wallKineticKBT = 0.0;
    double wallSolidLengthLeft = 0.0;
    double wallSolidLengthRight = 0.0;
    double wallSolidLengthBottom = 0.0;
    double wallSolidLengthTop = 0.0;
    double wallSolidLengthTotal = 0.0;
    double wallPressureKineticMeanLeft = 0.0;
    double wallPressureKineticMeanRight = 0.0;
    double wallPressureKineticMeanBottom = 0.0;
    double wallPressureKineticMeanTop = 0.0;
    double wallPressureVirialMeanLeft = 0.0;
    double wallPressureVirialMeanRight = 0.0;
    double wallPressureVirialMeanBottom = 0.0;
    double wallPressureVirialMeanTop = 0.0;
    double wallPressureTotalMeanLeft = 0.0;
    double wallPressureTotalMeanRight = 0.0;
    double wallPressureTotalMeanBottom = 0.0;
    double wallPressureTotalMeanTop = 0.0;
    double wallPressureKineticMeanAll = 0.0;
    double wallPressureVirialMeanAll = 0.0;
    double wallPressureTotalMeanAll = 0.0;
    double wallForceKineticX = 0.0;
    double wallForceKineticY = 0.0;
    double wallForceVirialX = 0.0;
    double wallForceVirialY = 0.0;
    double wallForceTotalX = 0.0;
    double wallForceTotalY = 0.0;
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
    ClosedCapacityResponseWorkspace& workspace,
    const std::vector<std::uint64_t>* fluidSlots = nullptr);

} // namespace mpcd
