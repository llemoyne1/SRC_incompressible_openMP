#pragma once

#include <cstdint>
#include <vector>

#include "cell_grid.h"
#include "fluid_domain.h"
#include "immersed_solid.h"
#include "particle_state.h"
#include "simulation_params.h"

namespace mpcd {

// Optional MATLAB-like virial EOS diagnostic/kick module.
//
// The diagnostic pressure is
//   PtotEOS = Pkin + PvirEOS,
//   PvirEOS = Kvirial * (rho - rhoEOSRef).
//
// The optional active kick uses
//   du = - virialBeta * dt / rhoKick * grad(Pdrive),
//   Pdrive = Pkin + Kvirial * (rho - rhoDriveRef),
// followed by an exact global momentum correction.  The module is deliberately
// independent from Q6/Q9; it is usually called after Q6/Q9 and before the final
// thermostat, matching the validated MATLAB workflow.

struct VirialPressureDiagnostics {
    bool enabled = false;
    bool diagnosticsEnabled = false;
    bool kickEnabled = false;
    bool kickApplied = false;

    double Kvirial = 0.0;
    double betaVirial = 0.0;

    std::uint64_t immersedSolidFluidCells = 0;
    std::uint64_t immersedSolidSolidCells = 0;

    double rhoMean = 0.0;
    double rhoEOSRef = 0.0;
    double rhoUniformNow = 0.0;
    double rhoDriveRef = 0.0;
    double rhoDefectRms = 0.0;
    double rhoDefectRelRms = 0.0;
    double rhoMin = 0.0;
    double rhoMax = 0.0;

    double PkinMean = 0.0;
    double PvirMean = 0.0;
    double PtotMean = 0.0;
    double PdriveMean = 0.0;
    double PkinMin = 0.0;
    double PkinMax = 0.0;
    double PvirMin = 0.0;
    double PvirMax = 0.0;
    double PtotMin = 0.0;
    double PtotMax = 0.0;

    double gradPdriveRms = 0.0;
    double gradPdriveMaxAbs = 0.0;
    double duVirialRawRms = 0.0;
    double duVirialAppliedRms = 0.0;
    double duVirialAppliedMaxAbs = 0.0;
    double duVirialOverThermalRms = 0.0;

    double momentumCorrectionVx = 0.0;
    double momentumCorrectionVy = 0.0;
    double momentumResidualBeforeCorrection = 0.0;
    double momentumResidualAfterCorrection = 0.0;
};

struct VirialPressureWorkspace {
    int allocatedCells = 0;
    std::uint64_t allocatedParticles = 0;

    std::vector<int> cellId;
    std::vector<double> cellMass;
    std::vector<double> cellCount;
    std::vector<double> cellPx;
    std::vector<double> cellPy;
    std::vector<double> cellRelKinetic;
    std::vector<double> cellRho;
    std::vector<double> cellTemperature;
    std::vector<double> Pkin;
    std::vector<double> PvirEOS;
    std::vector<double> PtotEOS;
    std::vector<double> Pdrive;
    std::vector<double> gradPx;
    std::vector<double> gradPy;
    std::vector<double> dux;
    std::vector<double> duy;

    std::vector<double> localMass;
    std::vector<double> localCount;
    std::vector<double> localPx;
    std::vector<double> localPy;
    std::vector<double> localRelKinetic;

    ImmersedSolidProjectionMask immersedMask;
};

bool virial_pressure_requested(const SimulationParams& params);

VirialPressureDiagnostics apply_virial_pressure_kick(ParticleState& state,
                                                     const SimulationParams& params,
                                                     const CellGrid& grid,
                                                     const FluidDomainBounds& domain,
                                                     VirialPressureWorkspace& workspace);

} // namespace mpcd
