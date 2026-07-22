#pragma once

#include <array>
#include <cstddef>
#include <cstdint>
#include "boundary_base.h"
#include "cell_grid.h"
#include "closed_capacity_response.h"
#include "cuda_darcy_brinkman_0343.h"
#include "fluid_domain.h"
#include "immersed_solid.h"
#include "particle_state.h"
#include "q6_projection_adapter.h"
#include "simulation_params.h"
#include "src_collision.h"
#include "thermostat.h"
#include "weighted_resampling.h"
#if defined(MPCD_ENABLE_CUDA_PARTICLE_STATE) && defined(MPCD_ENABLE_CUDA_CELL_WORKSPACE)
#include "cuda_species_cell_fields_0490h.h"
#include "cuda_species_mass_closure_0490i.h"
#endif

namespace mpcd {


constexpr std::size_t StepProfilePhaseCount = 31u;

const char* step_profile_phase_name(std::size_t phaseIndex);

struct StepProfile {
    std::array<double, StepProfilePhaseCount> seconds{};
};

struct StepResult {
    FluidDomainBounds domain;
    BoundaryDiagnostics boundary;
    ImmersedSolidDiagnostics immersed;
    CollisionDiagnostics collision;
    Q6ProjectionDiagnostics q6;
    ThermostatDiagnostics thermostat;
    ClosedCapacityResponseDiagnostics capacity;
    CudaDarcyBrinkman0343Diagnostics darcy;
    WeightedResamplingDiagnostics resampling;
    ResamplingParticlePoolDiagnostics resamplingPool;
    StepProfile profile;
};

struct SrcMpcdBaseWorkspace {
    CollisionWorkspace collision;
    Q6ProjectionWorkspace q6;
    ThermostatWorkspace thermostat;
    ClosedCapacityResponseWorkspace capacity;
    WeightedRealFluidDepositWorkspace resampling;
    ResamplingParticlePoolWorkspace resamplingPool;
#if defined(MPCD_ENABLE_CUDA_PARTICLE_STATE) && defined(MPCD_ENABLE_CUDA_CELL_WORKSPACE)
    CudaSpeciesCellWorkspace0490h speciesCellCuda0490h;
    CudaSpeciesMassClosureWorkspace0490i speciesMassClosureCuda0490i;
#endif
};

StepResult run_src_mpcd_base_step(ParticleState& state,
                                  const SimulationParams& params,
                                  const CellGrid& grid,
                                  std::uint64_t step,
                                  SrcMpcdBaseWorkspace& workspace,
                                  bool collectResamplingDiagnosticsWhenDisabled = true);

} // namespace mpcd
