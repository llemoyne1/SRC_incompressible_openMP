#pragma once

#include <cstdint>
#include <string>
#include <vector>

namespace mpcd {

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

    std::vector<std::uint32_t> type;
    std::vector<double> mass;
};

void validate_particle_state(const ParticleState& state, const std::string& context = "ParticleState");

// Compatibility helpers for the legacy interleaved arrays used by the existing
// SRC/SRD kernels in the current repository. These helpers should disappear once
// the core kernels are migrated to ParticleState/SoA directly.
std::vector<double> make_interleaved_positions(const ParticleState& state);
std::vector<double> make_interleaved_velocities(const ParticleState& state);
void update_particle_state_from_interleaved(ParticleState& state,
                                            const std::vector<double>& x_interleaved,
                                            const std::vector<double>& v_interleaved);

} // namespace mpcd
