#pragma once

#include <cstdint>
#include <vector>

#include "cell_grid.h"
#include "particle_state.h"
#include "simulation_params.h"

namespace mpcd {

struct ThermostatDiagnostics {
    bool applied = false;
    std::uint64_t cellsRescaled = 0;
    std::uint64_t particlesRescaled = 0;
    double kBTBefore = 0.0;
    double kBTAfter = 0.0;
    double scaleMean = 0.0;
    double scaleMin = 0.0;
    double scaleMax = 0.0;
};

struct ThermostatWorkspace {
    std::uint64_t allocatedParticles = 0;
    int allocatedCells = 0;
    int allocatedThreads = 0;

    std::vector<std::uint32_t> cellCount;
    std::vector<double> cellMass;
    std::vector<double> cellUx;
    std::vector<double> cellUy;
    std::vector<double> cellKinetic;
    std::vector<double> cellScale;

    std::vector<std::uint32_t> localCount;
    std::vector<double> localMass;
    std::vector<double> localPx;
    std::vector<double> localPy;
    std::vector<double> localKinetic;
};

void resize_thermostat_workspace(ThermostatWorkspace& ws,
                                 std::uint64_t numParticles,
                                 int numCells,
                                 int numThreads);

ThermostatDiagnostics apply_cell_relative_rescale_thermostat(ParticleState& state,
                                                              const SimulationParams& params,
                                                              const CellGrid& grid,
                                                              const std::vector<int>& cellId,
                                                              std::uint64_t step,
                                                              ThermostatWorkspace& ws,
                                                              const std::vector<std::uint64_t>* fluidSlots = nullptr);

} // namespace mpcd
