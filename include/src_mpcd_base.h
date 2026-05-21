#pragma once

#include <cstdint>
#include "cell_grid.h"
#include "particle_state.h"
#include "simulation_params.h"
#include "src_collision.h"

namespace mpcd {

struct StepResult {
    CollisionDiagnostics collision;
};

struct SrcMpcdBaseWorkspace {
    CollisionWorkspace collision;
};

StepResult run_src_mpcd_base_step(ParticleState& state,
                                  const SimulationParams& params,
                                  const CellGrid& grid,
                                  std::uint64_t step,
                                  SrcMpcdBaseWorkspace& workspace);

} // namespace mpcd
