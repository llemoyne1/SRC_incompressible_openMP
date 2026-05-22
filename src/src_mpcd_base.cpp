#include "src_mpcd_base.h"

#include <cstddef>
#include <cstdint>

namespace mpcd {

StepResult run_src_mpcd_base_step(ParticleState& state,
                                  const SimulationParams& params,
                                  const CellGrid& grid,
                                  std::uint64_t step,
                                  SrcMpcdBaseWorkspace& workspace) {
    validate_particle_state(state, "run_src_mpcd_base_step");
    const std::size_t n = static_cast<std::size_t>(state.Np);

    // Uniform body acceleration, then free streaming in the fixed numerical box.
#pragma omp parallel for if(n > 10000)
    for (std::int64_t ii = 0; ii < static_cast<std::int64_t>(n); ++ii) {
        const std::size_t i = static_cast<std::size_t>(ii);
        state.vx[i] += params.bodyAccelerationX * params.dt;
        state.vy[i] += params.bodyAccelerationY * params.dt;
        state.x[i] += state.vx[i] * params.dt;
        state.y[i] += state.vy[i] * params.dt;
    }

    StepResult result{};
    const double time = static_cast<double>(step) * params.dt;
    result.domain = make_fluid_domain_bounds(params, time);
    result.boundary = apply_boundary_conditions(state, params, result.domain, step, time);
    result.immersed = apply_immersed_circle_reflection(state, params, result.domain, time);
    result.collision = src_collision_step(state, params, grid, result.domain, step, workspace.collision);
    result.q6 = apply_q6_periodic_projection(state, params, grid, result.domain, workspace.q6);
    result.q9 = apply_q9_mass_flux_projection(state, params, grid, result.domain, workspace.q9);
    result.thermostat = apply_cell_relative_rescale_thermostat(
        state, params, grid, workspace.collision.cellId, step, workspace.thermostat);
    return result;
}

} // namespace mpcd
