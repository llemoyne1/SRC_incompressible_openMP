#pragma once

#include <cstdint>
#include "boundary_base.h"
#include "cell_grid.h"
#include "particle_state.h"
#include "simulation_params.h"
#include "src_collision.h"
#include "thermostat.h"

namespace mpcd {

struct StepResult {
    BoundaryDiagnostics boundary;
    CollisionDiagnostics collision;
    ThermostatDiagnostics thermostat;
};

struct SrcMpcdBaseWorkspace {
    CollisionWorkspace collision;
    ThermostatWorkspace thermostat;
};

StepResult run_src_mpcd_base_step(ParticleState& state,
                                  const SimulationParams& params,
                                  const CellGrid& grid,
                                  std::uint64_t step,
                                  SrcMpcdBaseWorkspace& workspace);

} // namespace mpcd
