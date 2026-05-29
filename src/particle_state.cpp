#include "particle_state.h"

#include <stdexcept>

namespace mpcd {

bool valid_particle_role_value(std::uint8_t value) {
    return value == kParticleRoleInactive || value == kParticleRoleFluid || value == kParticleRoleLatent;
}

const char* particle_role_name(std::uint8_t value) {
    switch (value) {
        case kParticleRoleInactive: return "Inactive";
        case kParticleRoleFluid:    return "Fluid";
        case kParticleRoleLatent:   return "Latent";
        default:                    return "Invalid";
    }
}

void validate_particle_state(const ParticleState& state, const std::string& context) {
    if (state.dim != 2u) {
        throw std::runtime_error(context + ": only dim=2 is supported in this code path");
    }

    const std::size_t n = static_cast<std::size_t>(state.Np);
    if (static_cast<std::uint64_t>(n) != state.Np) {
        throw std::runtime_error(context + ": particle count does not fit in std::size_t on this platform");
    }
    if (state.x.size() != n || state.y.size() != n ||
        state.vx.size() != n || state.vy.size() != n ||
        state.type.size() != n || state.mass.size() != n) {
        throw std::runtime_error(context + ": inconsistent SoA array sizes");
    }
    if (!state.role.empty() && state.role.size() != n) {
        throw std::runtime_error(context + ": inconsistent particle role array size");
    }
    for (std::size_t i = 0; i < state.role.size(); ++i) {
        if (!valid_particle_role_value(state.role[i])) {
            throw std::runtime_error(context + ": invalid particle role value at index " + std::to_string(i));
        }
    }
}

void ensure_particle_roles(ParticleState& state, ParticleRole defaultRole) {
    validate_particle_state(state, "ensure_particle_roles(before)");
    const std::size_t n = static_cast<std::size_t>(state.Np);
    if (state.role.empty()) {
        state.role.assign(n, static_cast<std::uint8_t>(defaultRole));
    }
    validate_particle_state(state, "ensure_particle_roles(after)");
}

std::uint8_t particle_role_value(const ParticleState& state, std::size_t i) {
    if (i >= static_cast<std::size_t>(state.Np)) {
        throw std::runtime_error("particle_role_value: index out of range");
    }
    return state.role.empty() ? kParticleRoleFluid : state.role[i];
}

bool is_fluid_role(std::uint8_t value) {
    return value == kParticleRoleFluid;
}

bool is_inactive_role(std::uint8_t value) {
    return value == kParticleRoleInactive;
}

bool is_latent_role(std::uint8_t value) {
    return value == kParticleRoleLatent;
}

bool is_fluid_particle(const ParticleState& state, std::size_t i) {
    return is_fluid_role(particle_role_value(state, i));
}

bool is_inactive_particle(const ParticleState& state, std::size_t i) {
    return is_inactive_role(particle_role_value(state, i));
}

bool is_latent_particle(const ParticleState& state, std::size_t i) {
    return is_latent_role(particle_role_value(state, i));
}

void set_particle_role(ParticleState& state, std::size_t i, ParticleRole role) {
    ensure_particle_roles(state, ParticleRole::Fluid);
    if (i >= state.role.size()) {
        throw std::runtime_error("set_particle_role: index out of range");
    }
    state.role[i] = static_cast<std::uint8_t>(role);
}

ParticleRoleCounts count_particle_roles(const ParticleState& state) {
    validate_particle_state(state, "count_particle_roles");
    ParticleRoleCounts counts{};
    const std::size_t n = static_cast<std::size_t>(state.Np);
    if (state.role.empty()) {
        counts.fluid = static_cast<std::uint64_t>(n);
        return counts;
    }
    for (std::size_t i = 0; i < n; ++i) {
        const std::uint8_t r = state.role[i];
        if (r == kParticleRoleFluid) ++counts.fluid;
        else if (r == kParticleRoleLatent) ++counts.latent;
        else if (r == kParticleRoleInactive) ++counts.inactive;
        else throw std::runtime_error("count_particle_roles: invalid role value");
    }
    return counts;
}

ParticleRoleMasks build_particle_role_masks(const ParticleState& state) {
    validate_particle_state(state, "build_particle_role_masks");
    const std::size_t n = static_cast<std::size_t>(state.Np);
    ParticleRoleMasks masks{};
    masks.isInactive.assign(n, 0u);
    masks.isFluid.assign(n, 0u);
    masks.isLatent.assign(n, 0u);
    for (std::size_t i = 0; i < n; ++i) {
        const std::uint8_t r = particle_role_value(state, i);
        if (r == kParticleRoleFluid) {
            masks.isFluid[i] = 1u;
            ++masks.counts.fluid;
        } else if (r == kParticleRoleLatent) {
            masks.isLatent[i] = 1u;
            ++masks.counts.latent;
        } else if (r == kParticleRoleInactive) {
            masks.isInactive[i] = 1u;
            ++masks.counts.inactive;
        } else {
            throw std::runtime_error("build_particle_role_masks: invalid role value");
        }
    }
    return masks;
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
