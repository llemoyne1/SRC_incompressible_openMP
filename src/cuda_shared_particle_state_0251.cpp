#include "cuda_shared_particle_state_0251.h"

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
#endif

} // namespace mpcd
