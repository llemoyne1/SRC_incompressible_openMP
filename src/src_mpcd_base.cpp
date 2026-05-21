#include "src_mpcd_base.h"

#include "boundary_base.h"
#include <cstddef>
#include <cstdint>

namespace mpcd {

StepResult run_src_mpcd_base_step(ParticleState& state,
                                  const SimulationParams& params,
                                  const CellGrid& grid,
                                  std::uint64_t step) {
    validate_particle_state(state, "run_src_mpcd_base_step");
    const std::size_t n = static_cast<std::size_t>(state.Np);

    // Uniform body acceleration, then free streaming.
    #pragma omp parallel for if(n > 10000)
    for (std::int64_t ii = 0; ii < static_cast<std::int64_t>(n); ++ii) {
        const std::size_t i = static_cast<std::size_t>(ii);
        state.vx[i] += params.bodyAccelerationX * params.dt;
        state.vy[i] += params.bodyAccelerationY * params.dt;
        state.x[i] += state.vx[i] * params.dt;
        state.y[i] += state.vy[i] * params.dt;
    }

    apply_periodic_boundaries(state, params);

    StepResult result{};
    result.collision = src_collision_step(state, params, grid, step);
    return result;
}

} // namespace mpcd
