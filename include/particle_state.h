#pragma once

#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>

namespace mpcd {

// Role is deliberately separated from type/species:
//   - type is a physical/material species identifier;
//   - role is the algorithmic state used by the weighted-resampling core.
enum class ParticleRole : std::uint8_t {
    Inactive = 0u, // free pool slot; ignored by fluid operators
    Fluid    = 1u, // true active fluid particle
    Latent   = 2u  // allocated particle not yet activated/wetted
};

constexpr std::uint8_t kParticleRoleInactive = static_cast<std::uint8_t>(ParticleRole::Inactive);
constexpr std::uint8_t kParticleRoleFluid    = static_cast<std::uint8_t>(ParticleRole::Fluid);
constexpr std::uint8_t kParticleRoleLatent   = static_cast<std::uint8_t>(ParticleRole::Latent);

struct ParticleRoleCounts {
    std::uint64_t inactive = 0u;
    std::uint64_t fluid = 0u;
    std::uint64_t latent = 0u;
};

struct ParticleRoleMasks {
    std::vector<std::uint8_t> isInactive;
    std::vector<std::uint8_t> isFluid;
    std::vector<std::uint8_t> isLatent;
    ParticleRoleCounts counts;
};

// Particle state used by the new generic SRC/MPCD core.
// Storage is structure-of-arrays (SoA) to keep the in-memory layout close to
// the .smpcd binary state format and to prepare OpenMP/MPI/GPU backends.
struct ParticleState {
    std::uint64_t Np = 0;
    std::uint32_t dim = 2;

    std::vector<double> x;
    std::vector<double> y;
    std::vector<double> vx;
    std::vector<double> vy;

    // Physical/material species identifier.  This remains available for future
    // mixtures and must not be overloaded with the resampling role.
    std::vector<std::uint32_t> type;

    std::vector<double> mass;

    // Algorithmic role. Empty is accepted as a legacy in-memory convention and
    // means that all particles are active Fluid; read_smpcd_state() normalizes
    // legacy V1 files by filling this array explicitly.
    std::vector<std::uint8_t> role;
};

bool valid_particle_role_value(std::uint8_t value);
const char* particle_role_name(std::uint8_t value);

void validate_particle_state(const ParticleState& state, const std::string& context = "ParticleState");
void ensure_particle_roles(ParticleState& state, ParticleRole defaultRole = ParticleRole::Fluid);

std::uint8_t particle_role_value(const ParticleState& state, std::size_t i);
bool is_fluid_role(std::uint8_t value);
bool is_inactive_role(std::uint8_t value);
bool is_latent_role(std::uint8_t value);
bool is_fluid_particle(const ParticleState& state, std::size_t i);
bool is_inactive_particle(const ParticleState& state, std::size_t i);
bool is_latent_particle(const ParticleState& state, std::size_t i);
void set_particle_role(ParticleState& state, std::size_t i, ParticleRole role);

ParticleRoleCounts count_particle_roles(const ParticleState& state);
ParticleRoleMasks build_particle_role_masks(const ParticleState& state);

// Compatibility helpers for the legacy interleaved arrays used by the existing
// SRC/SRD kernels in the current repository. These helpers should disappear once
// the core kernels are migrated to ParticleState/SoA directly. The helpers keep
// all slots, including latent/inactive slots, because they are storage-format
// compatibility tools rather than fluid-operator deposits.
std::vector<double> make_interleaved_positions(const ParticleState& state);
std::vector<double> make_interleaved_velocities(const ParticleState& state);
void update_particle_state_from_interleaved(ParticleState& state,
                                            const std::vector<double>& x_interleaved,
                                            const std::vector<double>& v_interleaved);

} // namespace mpcd
