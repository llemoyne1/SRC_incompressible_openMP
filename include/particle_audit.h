#pragma once

#include <atomic>
#include <cstdint>
#include <cstdlib>
#include <fstream>
#include <string>
#include <vector>

#ifdef _OPENMP
#include <omp.h>
#endif

namespace mpcd {

struct alignas(64) ParticleAuditCounters {
    std::uint64_t validateParticleStateCalls = 0u;
    std::uint64_t ensureParticleRolesCalls = 0u;
    std::uint64_t particleRoleValueCalls = 0u;
    std::uint64_t isFluidRoleCalls = 0u;
    std::uint64_t isInactiveRoleCalls = 0u;
    std::uint64_t isLatentRoleCalls = 0u;
    std::uint64_t isFluidParticleCalls = 0u;
    std::uint64_t isInactiveParticleCalls = 0u;
    std::uint64_t isLatentParticleCalls = 0u;
    std::uint64_t setParticleRoleCalls = 0u;
    std::uint64_t countParticleRolesCalls = 0u;
    std::uint64_t countParticleRolesParticles = 0u;
    std::uint64_t buildParticleRoleMasksCalls = 0u;
    std::uint64_t buildParticleRoleMasksParticles = 0u;
    std::uint64_t cellIndexFromPositionCalls = 0u;
    std::uint64_t computeCellCountsCalls = 0u;
    std::uint64_t computeCellCountsParticles = 0u;
};

inline std::atomic<bool>& particle_audit_active_flag() {
    static std::atomic<bool> active{false};
    return active;
}

inline std::vector<ParticleAuditCounters>& particle_audit_thread_counters() {
    static std::vector<ParticleAuditCounters> counters;
    return counters;
}

inline std::uint64_t& particle_audit_current_step() {
    static std::uint64_t step = 0u;
    return step;
}

inline std::uint64_t& particle_audit_current_particles() {
    static std::uint64_t n = 0u;
    return n;
}

inline int& particle_audit_current_cells() {
    static int nc = 0;
    return nc;
}

inline bool& particle_audit_header_written() {
    static bool written = false;
    return written;
}

inline const char* particle_audit_path_env() {
    return std::getenv("MPCD_PARTICLE_AUDIT_CSV");
}

inline bool particle_audit_requested() {
    const char* path = particle_audit_path_env();
    return path != nullptr && *path != '\0';
}

inline std::uint64_t particle_audit_every() {
    const char* env = std::getenv("MPCD_PARTICLE_AUDIT_EVERY");
    if (env == nullptr || *env == '\0') {
        return 1u;
    }
    char* end = nullptr;
    const unsigned long long parsed = std::strtoull(env, &end, 10);
    if (end == env || parsed == 0ull) {
        return 1u;
    }
    return static_cast<std::uint64_t>(parsed);
}

inline int particle_audit_thread_id() {
#ifdef _OPENMP
    return omp_get_thread_num();
#else
    return 0;
#endif
}

inline int particle_audit_max_threads() {
#ifdef _OPENMP
    return omp_get_max_threads();
#else
    return 1;
#endif
}

inline bool particle_audit_active() {
    return particle_audit_active_flag().load(std::memory_order_relaxed);
}

inline ParticleAuditCounters& particle_audit_local() {
    auto& counters = particle_audit_thread_counters();
    const int tid = particle_audit_thread_id();
    return counters[static_cast<std::size_t>(tid >= 0 ? tid : 0)];
}

inline void particle_audit_start_step(std::uint64_t step, std::uint64_t nParticles, int numCells) {
    if (!particle_audit_requested()) {
        particle_audit_active_flag().store(false, std::memory_order_relaxed);
        return;
    }
    const std::uint64_t every = particle_audit_every();
    if (every == 0u || (step % every) != 0u) {
        particle_audit_active_flag().store(false, std::memory_order_relaxed);
        return;
    }

    auto& counters = particle_audit_thread_counters();
    counters.assign(static_cast<std::size_t>(particle_audit_max_threads()), ParticleAuditCounters{});
    particle_audit_current_step() = step;
    particle_audit_current_particles() = nParticles;
    particle_audit_current_cells() = numCells;
    particle_audit_active_flag().store(true, std::memory_order_relaxed);
}

inline ParticleAuditCounters particle_audit_sum_counters() {
    ParticleAuditCounters total{};
    for (const ParticleAuditCounters& c : particle_audit_thread_counters()) {
        total.validateParticleStateCalls += c.validateParticleStateCalls;
        total.ensureParticleRolesCalls += c.ensureParticleRolesCalls;
        total.particleRoleValueCalls += c.particleRoleValueCalls;
        total.isFluidRoleCalls += c.isFluidRoleCalls;
        total.isInactiveRoleCalls += c.isInactiveRoleCalls;
        total.isLatentRoleCalls += c.isLatentRoleCalls;
        total.isFluidParticleCalls += c.isFluidParticleCalls;
        total.isInactiveParticleCalls += c.isInactiveParticleCalls;
        total.isLatentParticleCalls += c.isLatentParticleCalls;
        total.setParticleRoleCalls += c.setParticleRoleCalls;
        total.countParticleRolesCalls += c.countParticleRolesCalls;
        total.countParticleRolesParticles += c.countParticleRolesParticles;
        total.buildParticleRoleMasksCalls += c.buildParticleRoleMasksCalls;
        total.buildParticleRoleMasksParticles += c.buildParticleRoleMasksParticles;
        total.cellIndexFromPositionCalls += c.cellIndexFromPositionCalls;
        total.computeCellCountsCalls += c.computeCellCountsCalls;
        total.computeCellCountsParticles += c.computeCellCountsParticles;
    }
    return total;
}

inline void particle_audit_finish_step() {
    if (!particle_audit_active()) {
        return;
    }
    particle_audit_active_flag().store(false, std::memory_order_relaxed);
    const char* path = particle_audit_path_env();
    if (path == nullptr || *path == '\0') {
        return;
    }
    const ParticleAuditCounters c = particle_audit_sum_counters();

    std::ofstream out;
    if (!particle_audit_header_written()) {
        out.open(path, std::ios::out | std::ios::trunc);
        if (!out) return;
        out << "step,n_particles,n_cells,"
            << "validate_particle_state_calls,ensure_particle_roles_calls,"
            << "particle_role_value_calls,is_fluid_role_calls,is_inactive_role_calls,is_latent_role_calls,"
            << "is_fluid_particle_calls,is_inactive_particle_calls,is_latent_particle_calls,set_particle_role_calls,"
            << "count_particle_roles_calls,count_particle_roles_particles,"
            << "build_particle_role_masks_calls,build_particle_role_masks_particles,"
            << "cell_index_from_position_calls,compute_cell_counts_calls,compute_cell_counts_particles\n";
        particle_audit_header_written() = true;
    } else {
        out.open(path, std::ios::out | std::ios::app);
        if (!out) return;
    }

    out << particle_audit_current_step() << ','
        << particle_audit_current_particles() << ','
        << particle_audit_current_cells() << ','
        << c.validateParticleStateCalls << ','
        << c.ensureParticleRolesCalls << ','
        << c.particleRoleValueCalls << ','
        << c.isFluidRoleCalls << ','
        << c.isInactiveRoleCalls << ','
        << c.isLatentRoleCalls << ','
        << c.isFluidParticleCalls << ','
        << c.isInactiveParticleCalls << ','
        << c.isLatentParticleCalls << ','
        << c.setParticleRoleCalls << ','
        << c.countParticleRolesCalls << ','
        << c.countParticleRolesParticles << ','
        << c.buildParticleRoleMasksCalls << ','
        << c.buildParticleRoleMasksParticles << ','
        << c.cellIndexFromPositionCalls << ','
        << c.computeCellCountsCalls << ','
        << c.computeCellCountsParticles << '\n';
}

inline void particle_audit_validate_particle_state() { if (particle_audit_active()) ++particle_audit_local().validateParticleStateCalls; }
inline void particle_audit_ensure_particle_roles() { if (particle_audit_active()) ++particle_audit_local().ensureParticleRolesCalls; }
inline void particle_audit_particle_role_value() { if (particle_audit_active()) ++particle_audit_local().particleRoleValueCalls; }
inline void particle_audit_is_fluid_role() { if (particle_audit_active()) ++particle_audit_local().isFluidRoleCalls; }
inline void particle_audit_is_inactive_role() { if (particle_audit_active()) ++particle_audit_local().isInactiveRoleCalls; }
inline void particle_audit_is_latent_role() { if (particle_audit_active()) ++particle_audit_local().isLatentRoleCalls; }
inline void particle_audit_is_fluid_particle() { if (particle_audit_active()) ++particle_audit_local().isFluidParticleCalls; }
inline void particle_audit_is_inactive_particle() { if (particle_audit_active()) ++particle_audit_local().isInactiveParticleCalls; }
inline void particle_audit_is_latent_particle() { if (particle_audit_active()) ++particle_audit_local().isLatentParticleCalls; }
inline void particle_audit_set_particle_role() { if (particle_audit_active()) ++particle_audit_local().setParticleRoleCalls; }
inline void particle_audit_count_particle_roles(std::uint64_t n) { if (particle_audit_active()) { auto& c = particle_audit_local(); ++c.countParticleRolesCalls; c.countParticleRolesParticles += n; } }
inline void particle_audit_build_particle_role_masks(std::uint64_t n) { if (particle_audit_active()) { auto& c = particle_audit_local(); ++c.buildParticleRoleMasksCalls; c.buildParticleRoleMasksParticles += n; } }
inline void particle_audit_cell_index_from_position() { if (particle_audit_active()) ++particle_audit_local().cellIndexFromPositionCalls; }
inline void particle_audit_compute_cell_counts(std::uint64_t n) { if (particle_audit_active()) { auto& c = particle_audit_local(); ++c.computeCellCountsCalls; c.computeCellCountsParticles += n; } }

} // namespace mpcd
