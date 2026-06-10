#include "cuda_shared_particle_state_0251.h"

#include <cstdlib>
#include <string>

namespace mpcd {

#if defined(MPCD_ENABLE_CUDA_PARTICLE_STATE)
namespace {

struct SharedParticleState0251Registry {
    CudaParticleState state;
    bool fresh = false;
    const char* lastWriter = "none";
    const char* lastInvalidator = "initial";
};

SharedParticleState0251Registry& registry_0251() {
    static SharedParticleState0251Registry r;
    return r;
}

bool env_truthy_0315d(const char* name) {
    const char* v = std::getenv(name);
    if (v == nullptr || *v == '\0') return false;
    const std::string s(v);
    return !(s == "0" || s == "false" || s == "FALSE" ||
             s == "off" || s == "OFF" || s == "no" || s == "NO");
}

} // namespace

CudaParticleState& cuda_shared_particle_state_0251() {
    return registry_0251().state;
}

void cuda_shared_particle_state_0251_mark_fresh(const char* writer) {
    auto& r = registry_0251();
    r.fresh = true;
    r.lastWriter = writer != nullptr ? writer : "unknown";
}

void cuda_shared_particle_state_0251_invalidate(const char* reason) {
    auto& r = registry_0251();
    r.fresh = false;
    r.lastInvalidator = reason != nullptr ? reason : "unknown";
}

bool cuda_shared_particle_state_0251_is_fresh() {
    return registry_0251().fresh;
}

const char* cuda_shared_particle_state_0251_last_writer() {
    return registry_0251().lastWriter;
}

const char* cuda_shared_particle_state_0251_last_invalidator() {
    return registry_0251().lastInvalidator;
}

bool cuda_shared_particle_state_0251_download_if_fresh(ParticleState& state) {
    auto& r = registry_0251();
    if (!r.fresh) {
        return false;
    }
    // 0315d: the shared CUDA state is authoritative in resident runs.  Host
    // synchronization is now a lazy consumer operation for summaries/dumps,
    // and inactive slots are storage only.  Download only the active fluid
    // prefix by default instead of the full reserved capacity; retain the full
    // download behind an explicit compatibility flag for legacy debugging.
    if (env_truthy_0315d("MPCD_CUDA_SHARED_STATE_DOWNLOAD_ALL_LEGACY_0315D")) {
        r.state.download_all(state, nullptr);
    } else {
        r.state.download_active_prefix(state, nullptr);
    }
    return true;
}

bool cuda_shared_particle_state_0251_download_role_filtered_if_fresh(ParticleState& state,
                                                                    std::uint8_t keepRole,
                                                                    ParticleRoleCounts* roleCounts) {
    auto& r = registry_0251();
    if (!r.fresh) {
        return false;
    }
    r.state.download_role_filtered(state, keepRole, roleCounts, nullptr);
    return true;
}
#endif

} // namespace mpcd
