#include "particle_state.h"

#include <stdexcept>

namespace mpcd {

void validate_particle_state(const ParticleState& state, const std::string& context) {
    if (state.dim != 2u) {
        throw std::runtime_error(context + ": only dim=2 is supported in this code path");
    }

    const std::size_t n = static_cast<std::size_t>(state.Np);
    if (state.x.size() != n || state.y.size() != n ||
        state.vx.size() != n || state.vy.size() != n ||
        state.type.size() != n || state.mass.size() != n) {
        throw std::runtime_error(context + ": inconsistent SoA array sizes");
    }
}

std::vector<double> make_interleaved_positions(const ParticleState& state) {
    validate_particle_state(state, "make_interleaved_positions");
    const std::size_t n = static_cast<std::size_t>(state.Np);
    std::vector<double> out(2u * n);
    for (std::size_t i = 0; i < n; ++i) {
        out[2u * i] = state.x[i];
        out[2u * i + 1u] = state.y[i];
    }
    return out;
}

std::vector<double> make_interleaved_velocities(const ParticleState& state) {
    validate_particle_state(state, "make_interleaved_velocities");
    const std::size_t n = static_cast<std::size_t>(state.Np);
    std::vector<double> out(2u * n);
    for (std::size_t i = 0; i < n; ++i) {
        out[2u * i] = state.vx[i];
        out[2u * i + 1u] = state.vy[i];
    }
    return out;
}

void update_particle_state_from_interleaved(ParticleState& state,
                                            const std::vector<double>& x_interleaved,
                                            const std::vector<double>& v_interleaved) {
    validate_particle_state(state, "update_particle_state_from_interleaved");
    const std::size_t n = static_cast<std::size_t>(state.Np);
    if (x_interleaved.size() != 2u * n || v_interleaved.size() != 2u * n) {
        throw std::runtime_error("update_particle_state_from_interleaved: unexpected interleaved buffer size");
    }

    for (std::size_t i = 0; i < n; ++i) {
        state.x[i] = x_interleaved[2u * i];
        state.y[i] = x_interleaved[2u * i + 1u];
        state.vx[i] = v_interleaved[2u * i];
        state.vy[i] = v_interleaved[2u * i + 1u];
    }
}

} // namespace mpcd
