#include "boundary_base.h"

#include <cmath>
#include <cstddef>
#include <cstdint>
#include <stdexcept>

namespace mpcd {
namespace {

double wrap_periodic(double x, double L) {
    x = std::fmod(x, L);
    if (x < 0.0) {
        x += L;
    }
    if (x >= L) {
        x -= L;
    }
    return x;
}

} // namespace

void apply_periodic_boundaries(ParticleState& state, const SimulationParams& params) {
    if (params.bcX != "periodic" || params.bcY != "periodic") {
        throw std::runtime_error("apply_periodic_boundaries called with non-periodic boundary parameters");
    }

    validate_particle_state(state, "apply_periodic_boundaries");
    const std::size_t n = static_cast<std::size_t>(state.Np);

    #pragma omp parallel for if(n > 10000)
    for (std::int64_t ii = 0; ii < static_cast<std::int64_t>(n); ++ii) {
        const std::size_t i = static_cast<std::size_t>(ii);
        state.x[i] = wrap_periodic(state.x[i], params.Lx);
        state.y[i] = wrap_periodic(state.y[i], params.Ly);
    }
}

} // namespace mpcd
