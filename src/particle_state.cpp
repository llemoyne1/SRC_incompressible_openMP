#include "particle_state.h"

#include <algorithm>
#include <cstdlib>
#include <stdexcept>
#include <string>
#include <utility>

namespace mpcd {

namespace {

bool env_truthy_0315l(const char* name) {
    const char* v = std::getenv(name);
    if (v == nullptr || *v == '\0') return false;
    const std::string s(v);
    return !(s == "0" || s == "false" || s == "FALSE" ||
             s == "off" || s == "OFF" || s == "no" || s == "NO");
}

} // namespace

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
    if (state.NactiveFluid > state.Np) {
        throw std::runtime_error(context + ": NactiveFluid exceeds total particle storage capacity Np");
    }
    // 0315l: this validator is used in hot CUDA wrappers.  Scanning
    // role[0:Np_total] on every upload/summary made even TG scale with the
    // inactive reservoir.  Keep the default validation structural; full role
    // value validation remains available for debugging corrupted states.
    if (env_truthy_0315l("MPCD_VALIDATE_PARTICLE_ROLES_FULLSCAN_0315L")) {
        for (std::size_t i = 0; i < state.role.size(); ++i) {
            if (!valid_particle_role_value(state.role[i])) {
                throw std::runtime_error(context + ": invalid particle role value at index " + std::to_string(i));
            }
        }
    }
}

void ensure_particle_roles(ParticleState& state, ParticleRole defaultRole) {
    validate_particle_state(state, "ensure_particle_roles(before)");
    const std::size_t n = static_cast<std::size_t>(state.Np);
    const std::uint8_t defaultValue = static_cast<std::uint8_t>(defaultRole);
    if (state.role.empty()) {
        state.role.assign(n, defaultValue);
        state.NactiveFluid = (defaultValue == kParticleRoleFluid) ? state.Np : 0u;
        validate_particle_state(state, "ensure_particle_roles(after)");
        return;
    }

    // 0315m: ensure_particle_roles() is called at the beginning of every SRC
    // step and by several wrappers.  The previous 0315a implementation always
    // called refresh_active_fluid_count(), which scans role[0:Np_total].  That
    // single hidden O(Np_total) pass was enough to keep TG/Poiseuille/step/box
    // scaling with the inactive reservoir even after the physical kernels had
    // been migrated to NactiveFluid.  Treat role[] as storage metadata here:
    // when an explicit role array already exists and NactiveFluid is within
    // capacity, do not rescan it.  Full refresh remains available for debug or
    // legacy construction paths that have not installed active-prefix metadata.
    if (env_truthy_0315l("MPCD_ENSURE_PARTICLE_ROLES_FULL_REFRESH_0315M")) {
        refresh_active_fluid_count(state);
        validate_particle_state(state, "ensure_particle_roles(after full-refresh 0315m)");
        return;
    }

    if (state.NactiveFluid > state.Np) {
        throw std::runtime_error("ensure_particle_roles: NactiveFluid exceeds Np");
    }

    // If the caller supplied explicit roles but no active-prefix count, leave
    // this as a lazy legacy state.  active_fluid_count()/compaction paths still
    // compute the exact count when they really need it.  Hot normalized states
    // loaded by read_smpcd_state() or maintained by CUDA active-prefix logic
    // always have NactiveFluid installed.
    validate_particle_state(state, "ensure_particle_roles(after metadata-only 0315m)");
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
    const std::uint8_t oldRole = state.role[i];
    const std::uint8_t newRole = static_cast<std::uint8_t>(role);
    state.role[i] = newRole;
    if (oldRole != newRole) {
        if (oldRole == kParticleRoleFluid && state.NactiveFluid > 0u) {
            --state.NactiveFluid;
        } else if (newRole == kParticleRoleFluid && state.NactiveFluid < state.Np) {
            ++state.NactiveFluid;
        }
    }
}

namespace {

void swap_particle_slots(ParticleState& state, std::size_t a, std::size_t b) {
    if (a == b) return;
    using std::swap;
    swap(state.x[a], state.x[b]);
    swap(state.y[a], state.y[b]);
    swap(state.vx[a], state.vx[b]);
    swap(state.vy[a], state.vy[b]);
    swap(state.type[a], state.type[b]);
    swap(state.mass[a], state.mass[b]);
    swap(state.role[a], state.role[b]);
}

} // namespace

std::uint64_t compute_active_fluid_count(const ParticleState& state) {
    validate_particle_state(state, "compute_active_fluid_count");
    const std::size_t n = static_cast<std::size_t>(state.Np);
    if (state.role.empty()) {
        return static_cast<std::uint64_t>(n);
    }
    std::uint64_t count = 0u;
    for (std::size_t i = 0; i < n; ++i) {
        if (state.role[i] == kParticleRoleFluid) ++count;
    }
    return count;
}

std::uint64_t active_fluid_count(const ParticleState& state) {
    validate_particle_state(state, "active_fluid_count");
    if (state.Np == 0u) return 0u;
    // Backward-compatible fallback for old construction paths that have not yet
    // refreshed the 0315a metadata.  Hot physical loops should call this only
    // after states are normalized/compacted by read_smpcd_state() or explicit
    // pool-transition code.
    if (state.NactiveFluid == 0u) {
        return compute_active_fluid_count(state);
    }
    return state.NactiveFluid;
}

void refresh_active_fluid_count(ParticleState& state) {
    state.NactiveFluid = compute_active_fluid_count(state);
}

bool has_active_fluid_prefix(const ParticleState& state) {
    validate_particle_state(state, "has_active_fluid_prefix");
    const std::size_t n = static_cast<std::size_t>(state.Np);
    const std::size_t nf = static_cast<std::size_t>(active_fluid_count(state));
    if (nf > n) return false;
    if (state.role.empty()) {
        return nf == n;
    }
    for (std::size_t i = 0; i < nf; ++i) {
        if (state.role[i] != kParticleRoleFluid) return false;
    }
    for (std::size_t i = nf; i < n; ++i) {
        if (state.role[i] == kParticleRoleFluid) return false;
    }
    return true;
}

void validate_active_fluid_prefix(const ParticleState& state, const std::string& context) {
    if (!has_active_fluid_prefix(state)) {
        throw std::runtime_error(context + ": active fluid particles are not stored as a compact prefix");
    }
}

void compact_active_fluid_prefix(ParticleState& state) {
    ensure_particle_roles(state, ParticleRole::Fluid);
    validate_particle_state(state, "compact_active_fluid_prefix(before)");
    const std::size_t n = static_cast<std::size_t>(state.Np);
    if (n == 0u) {
        state.NactiveFluid = 0u;
        return;
    }

    std::size_t left = 0u;
    std::size_t right = n;
    while (left < right) {
        while (left < right && state.role[left] == kParticleRoleFluid) {
            ++left;
        }
        while (left < right && state.role[right - 1u] != kParticleRoleFluid) {
            --right;
        }
        if (left < right) {
            swap_particle_slots(state, left, right - 1u);
            ++left;
            --right;
        }
    }
    state.NactiveFluid = compute_active_fluid_count(state);
    validate_active_fluid_prefix(state, "compact_active_fluid_prefix(after)");
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
