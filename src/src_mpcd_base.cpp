#include "src_mpcd_base.h"

#include <cstddef>
#include <cstdint>

namespace mpcd {
namespace {

void apply_keep_mean_flow(ParticleState& state, const SimulationParams& params) {
    if (!params.keepMeanFlowEnable) {
        return;
    }
    validate_particle_state(state, "apply_keep_mean_flow");
    const std::size_t n = static_cast<std::size_t>(state.Np);

    double mass = 0.0;
    double px = 0.0;
    double py = 0.0;
#pragma omp parallel for reduction(+:mass,px,py) if(n > 10000)
    for (std::int64_t ii = 0; ii < static_cast<std::int64_t>(n); ++ii) {
        const std::size_t i = static_cast<std::size_t>(ii);
        if (!is_fluid_particle(state, i)) {
            continue;
        }
        const double m = state.mass[i];
        mass += m;
        px += m * state.vx[i];
        py += m * state.vy[i];
    }
    if (!(mass > 0.0)) {
        return;
    }

    const double dvx = params.targetMeanUx - px / mass;
    const double dvy = params.targetMeanUy - py / mass;
#pragma omp parallel for if(n > 10000)
    for (std::int64_t ii = 0; ii < static_cast<std::int64_t>(n); ++ii) {
        const std::size_t i = static_cast<std::size_t>(ii);
        if (!is_fluid_particle(state, i)) {
            continue;
        }
        state.vx[i] += dvx;
        state.vy[i] += dvy;
    }
}

} // namespace

StepResult run_src_mpcd_base_step(ParticleState& state,
                                  const SimulationParams& params,
                                  const CellGrid& grid,
                                  std::uint64_t step,
                                  SrcMpcdBaseWorkspace& workspace) {
    validate_particle_state(state, "run_src_mpcd_base_step");
    ensure_particle_roles(state, ParticleRole::Fluid);
    const std::size_t n = static_cast<std::size_t>(state.Np);

    // Uniform body acceleration, then free streaming in the fixed numerical box.
#pragma omp parallel for if(n > 10000)
    for (std::int64_t ii = 0; ii < static_cast<std::int64_t>(n); ++ii) {
        const std::size_t i = static_cast<std::size_t>(ii);
        if (!is_fluid_particle(state, i)) {
            continue;
        }
        state.vx[i] += params.bodyAccelerationX * params.dt;
        state.vy[i] += params.bodyAccelerationY * params.dt;
        state.x[i] += state.vx[i] * params.dt;
        state.y[i] += state.vy[i] * params.dt;
    }

    StepResult result{};
    const double time = static_cast<double>(step) * params.dt;
    result.domain = make_fluid_domain_bounds(params, time);
    result.boundary = apply_boundary_conditions(state, params, result.domain, step, time);
    result.immersed = apply_immersed_solid_reflection(state, params, result.domain, time);
    result.collision = src_collision_step(state, params, grid, result.domain, step, workspace.collision);
    result.q6 = apply_q6_periodic_projection(state, params, grid, result.domain, time, workspace.q6);
    result.thermostat = apply_cell_relative_rescale_thermostat(
        state, params, grid, workspace.collision.cellId, step, workspace.thermostat);
    apply_keep_mean_flow(state, params);
    result.resamplingPool = rebuild_resampling_particle_pool(state, workspace.resamplingPool);
    result.resampling = deposit_weighted_real_fluid(
        state, params, grid, GridShift{}, workspace.resampling);
    attach_resampling_pool_diagnostics(result.resampling, result.resamplingPool);
    return result;
}

} // namespace mpcd
