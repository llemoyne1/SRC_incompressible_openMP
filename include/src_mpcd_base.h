#pragma once

#include <cstddef>
#include <cstdint>
#include "boundary_base.h"
#include "cell_grid.h"
#include "closed_capacity_response.h"
#include "fluid_domain.h"
#include "immersed_solid.h"
#include "particle_state.h"
#include "q6_projection_adapter.h"
#include "simulation_params.h"
#include "src_collision.h"
#include "thermostat.h"
#include "weighted_resampling.h"

namespace mpcd {


struct StepResult {
    FluidDomainBounds domain;
    BoundaryDiagnostics boundary;
    ImmersedSolidDiagnostics immersed;
    CollisionDiagnostics collision;
    Q6ProjectionDiagnostics q6;
    ThermostatDiagnostics thermostat;
    ClosedCapacityResponseDiagnostics capacity;
    WeightedResamplingDiagnostics resampling;
    ResamplingParticlePoolDiagnostics resamplingPool;
};

struct SrcMpcdBaseWorkspace {
    CollisionWorkspace collision;
    Q6ProjectionWorkspace q6;
    ThermostatWorkspace thermostat;
    ClosedCapacityResponseWorkspace capacity;
    WeightedRealFluidDepositWorkspace resampling;
    ResamplingParticlePoolWorkspace resamplingPool;
};

StepResult run_src_mpcd_base_step(ParticleState& state,
                                  const SimulationParams& params,
                                  const CellGrid& grid,
                                  std::uint64_t step,
                                  SrcMpcdBaseWorkspace& workspace,
                                  bool collectResamplingDiagnosticsWhenDisabled = true);

} // namespace mpcd
