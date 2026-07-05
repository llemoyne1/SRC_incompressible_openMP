#include "cuda_particle_state.h"

#include <cuda_runtime.h>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

namespace mpcd {
namespace {

#define MPCD_CUDA_CHECK(call) do { \
    cudaError_t err__ = (call); \
    if (err__ != cudaSuccess) { \
        throw std::runtime_error(std::string("CUDA error in ") + #call + ": " + cudaGetErrorString(err__)); \
    } \
} while (0)

using Clock = std::chrono::steady_clock;

double elapsed_seconds(const Clock::time_point& t0) {
    return std::chrono::duration<double>(Clock::now() - t0).count();
}

bool env_truthy_0315d(const char* name) {
    const char* v = std::getenv(name);
    if (v == nullptr || *v == '\0') return false;
    const std::string s(v);
    return !(s == "0" || s == "false" || s == "FALSE" ||
             s == "off" || s == "OFF" || s == "no" || s == "NO");
}


void validate_particle_state_shape_only_0315j(const ParticleState& state, const char* context) {
    if (state.dim != 2u) {
        throw std::runtime_error(std::string(context) + ": only dim=2 is supported");
    }
    const std::size_t n = static_cast<std::size_t>(state.Np);
    if (static_cast<std::uint64_t>(n) != state.Np) {
        throw std::runtime_error(std::string(context) + ": particle count does not fit in std::size_t");
    }
    if (state.NactiveFluid > state.Np) {
        throw std::runtime_error(std::string(context) + ": NactiveFluid exceeds Np");
    }
    if (state.x.size() != n || state.y.size() != n ||
        state.vx.size() != n || state.vy.size() != n ||
        state.mass.size() != n || state.type.size() != n ||
        (!state.role.empty() && state.role.size() != n)) {
        throw std::runtime_error(std::string(context) + ": inconsistent host SoA sizes");
    }
}

bool active_prefix_upload_all_enabled_0315j(const ParticleState& state) {
    if (env_truthy_0315d("MPCD_CUDA_ACTIVE_PREFIX_UPLOAD_ALL_LEGACY_0315J")) return false;
    if (env_truthy_0315d("MPCD_CUDA_ACTIVE_PREFIX_UPLOAD_ALL_FULL_VALIDATE_0315J")) return false;
    if (state.Np == 0u) return true;
    if (state.role.empty()) return state.NactiveFluid == 0u || state.NactiveFluid == state.Np;
    // Avoid the legacy active_fluid_count() fallback here: if NactiveFluid is
    // stale/zero for a state with an inactive reservoir, falling back to a full
    // role scan would reintroduce the O(Np_total) cost that 0315j removes.
    return state.NactiveFluid > 0u && state.NactiveFluid <= state.Np;
}

std::uint64_t active_prefix_count_no_fullscan_0315l(const ParticleState& state, const char* context) {
    validate_particle_state_shape_only_0315j(state, context);
    if (state.Np == 0u) return 0u;
    if (state.role.empty()) return state.Np;
    if (state.NactiveFluid == 0u) {
        throw std::runtime_error(std::string(context) +
            ": NactiveFluid is zero with explicit roles; compact/refresh active prefix before hot CUDA upload");
    }
    if (state.NactiveFluid > state.Np) {
        throw std::runtime_error(std::string(context) + ": active prefix exceeds capacity");
    }
    return state.NactiveFluid;
}

template <typename T>
void cuda_free_ptr(T*& ptr) {
    if (ptr != nullptr) {
        cudaFree(ptr);
        ptr = nullptr;
    }
}

// 0222 upload fast path: avoid rebuilding temporary host vectors on every
// particle-state upload when role/type arrays are already explicitly stored in
// ParticleState. The old implementation copied state.role/state.type into
// temporary std::vectors before cudaMemcpy, which became visible once the
// CudaParticleState path was called every step. For missing optional arrays we
// keep the previous semantics using cudaMemset instead of allocating/filling
// temporary vectors on the host.
const unsigned char* role_upload_ptr_or_null(const ParticleState& state) {
    return state.role.empty() ? nullptr : state.role.data();
}

const std::uint32_t* type_upload_ptr_or_null(const ParticleState& state) {
    return state.type.empty() ? nullptr : state.type.data();
}

// 0223 exact metadata signature. This is deliberately conservative and
// byte-based: if mass/type/role host contents change, the signature changes and
// metadata is reuploaded. Collisions are theoretically possible for a 64-bit
// hash, but in this diagnostic/performance path it is a practical guard; users
// can disable the cache by calling upload_all() instead.
std::uint64_t fnv1a_bytes(std::uint64_t h, const void* data, std::size_t nbytes) {
    const unsigned char* p = static_cast<const unsigned char*>(data);
    constexpr std::uint64_t prime = 1099511628211ULL;
    for (std::size_t i = 0; i < nbytes; ++i) {
        h ^= static_cast<std::uint64_t>(p[i]);
        h *= prime;
    }
    return h;
}

std::uint64_t cuda_particle_metadata_signature(const ParticleState& state) {
    // 0315l: metadata signatures are evaluated in the hot
    // upload_kinematics_with_cached_metadata() path.  Hashing mass/type/role
    // over the full storage capacity kept the runtime proportional to the
    // inactive reservoir.  Under the active-prefix invariant, inactive tail
    // payload is free storage; only the active prefix and the logical
    // [Fluid prefix][Inactive tail] layout must enter the cache key.
    constexpr std::uint64_t offset = 1469598103934665603ULL;
    std::uint64_t h = offset;
    const std::uint64_t n = state.Np;
    const std::uint64_t nActive = active_prefix_count_no_fullscan_0315l(state,
        "cuda_particle_metadata_signature(0315l)");
    h = fnv1a_bytes(h, &n, sizeof(n));
    h = fnv1a_bytes(h, &nActive, sizeof(nActive));
    const std::size_t na = static_cast<std::size_t>(nActive);
    if (nActive > 0u) {
        h = fnv1a_bytes(h, state.mass.data(), na * sizeof(double));
        const bool hasType = !state.type.empty();
        const bool hasRole = !state.role.empty();
        h = fnv1a_bytes(h, &hasType, sizeof(hasType));
        h = fnv1a_bytes(h, &hasRole, sizeof(hasRole));
        if (hasType) {
            h = fnv1a_bytes(h, state.type.data(), na * sizeof(std::uint32_t));
        }
        if (hasRole) {
            h = fnv1a_bytes(h, state.role.data(), na * sizeof(unsigned char));
        }
    }
    return h;
}

__global__ void smoke_increment_fluid_velocities_kernel(int n,
                                                        const unsigned char* role,
                                                        double* vx,
                                                        double* vy,
                                                        double dvx,
                                                        double dvy,
                                                        unsigned char fluidRole) {
    const int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= n) return;
    if (role[i] != fluidRole) return;
    vx[i] += dvx;
    vy[i] += dvy;
}

} // namespace

struct CudaParticleState::Impl {
    double* x = nullptr;
    double* y = nullptr;
    double* vx = nullptr;
    double* vy = nullptr;
    double* mass = nullptr;
    std::uint32_t* type = nullptr;
    unsigned char* role = nullptr;
    std::uint64_t n = 0u;
    std::uint64_t capacity = 0u;
    std::uint64_t nActiveFluid = 0u;
    std::uint64_t allocatedBytes = 0u;
    std::uint64_t metadataSignature = 0u;
    std::uint64_t metadataParticles = 0u;
    bool metadataUploaded = false;
    bool activePrefixRoleLayoutInitialized0315k = false;
    std::uint64_t activePrefixRoleLayoutActive0315k = 0u;
    std::uint64_t activePrefixRoleLayoutCapacity0315k = 0u;

    void release() {
        cuda_free_ptr(x);
        cuda_free_ptr(y);
        cuda_free_ptr(vx);
        cuda_free_ptr(vy);
        cuda_free_ptr(mass);
        cuda_free_ptr(type);
        cuda_free_ptr(role);
        n = 0u;
        capacity = 0u;
        nActiveFluid = 0u;
        allocatedBytes = 0u;
        metadataSignature = 0u;
        metadataParticles = 0u;
        metadataUploaded = false;
        activePrefixRoleLayoutInitialized0315k = false;
        activePrefixRoleLayoutActive0315k = 0u;
        activePrefixRoleLayoutCapacity0315k = 0u;
    }
};

bool cuda_particle_state_available() {
#ifdef MPCD_ENABLE_CUDA_PARTICLE_STATE
    int count = 0;
    const cudaError_t err = cudaGetDeviceCount(&count);
    if (err != cudaSuccess) {
        cudaGetLastError();
        return false;
    }
    return count > 0;
#else
    return false;
#endif
}

CudaParticleState::CudaParticleState() : impl_(new Impl()) {}

CudaParticleState::~CudaParticleState() {
    release();
    delete impl_;
    impl_ = nullptr;
}

CudaParticleState::CudaParticleState(CudaParticleState&& other) noexcept : impl_(other.impl_) {
    other.impl_ = new Impl();
}

CudaParticleState& CudaParticleState::operator=(CudaParticleState&& other) noexcept {
    if (this != &other) {
        release();
        delete impl_;
        impl_ = other.impl_;
        other.impl_ = new Impl();
    }
    return *this;
}

void CudaParticleState::release() {
#ifdef MPCD_ENABLE_CUDA_PARTICLE_STATE
    if (impl_ != nullptr) impl_->release();
#else
    if (impl_ != nullptr) {
        impl_->n = 0u;
        impl_->capacity = 0u;
        impl_->nActiveFluid = 0u;
        impl_->allocatedBytes = 0u;
    }
#endif
}

void CudaParticleState::ensure_capacity(std::uint64_t n, CudaParticleStateDiagnostics* diag) {
#ifndef MPCD_ENABLE_CUDA_PARTICLE_STATE
    (void)n; (void)diag;
    throw std::runtime_error("CudaParticleState::ensure_capacity called without MPCD_ENABLE_CUDA_PARTICLE_STATE");
#else
    if (impl_ == nullptr) throw std::runtime_error("CudaParticleState::ensure_capacity: null impl");
    if (diag != nullptr) {
        diag->particles = n;
        diag->capacity = impl_->capacity;
        diag->allocatedBytes = impl_->allocatedBytes;
    }
    if (n <= impl_->capacity && impl_->x != nullptr) {
        impl_->n = n;
        if (impl_->nActiveFluid > n) impl_->nActiveFluid = n;
        if (diag != nullptr) {
            diag->reusedAllocation = 1;
            diag->capacity = impl_->capacity;
            diag->allocatedBytes = impl_->allocatedBytes;
        }
        return;
    }

    const auto t0 = Clock::now();
    impl_->release();

    if (n == 0u) {
        if (diag != nullptr) diag->allocateSeconds += elapsed_seconds(t0);
        return;
    }
    const std::size_t nn = static_cast<std::size_t>(n);
    if (static_cast<std::uint64_t>(nn) != n) {
        throw std::runtime_error("CudaParticleState::ensure_capacity: particle count does not fit in size_t");
    }

    const std::size_t bytesD = nn * sizeof(double);
    const std::size_t bytesU = nn * sizeof(std::uint32_t);
    const std::size_t bytesR = nn * sizeof(unsigned char);
    MPCD_CUDA_CHECK(cudaMalloc(&impl_->x, bytesD));
    MPCD_CUDA_CHECK(cudaMalloc(&impl_->y, bytesD));
    MPCD_CUDA_CHECK(cudaMalloc(&impl_->vx, bytesD));
    MPCD_CUDA_CHECK(cudaMalloc(&impl_->vy, bytesD));
    MPCD_CUDA_CHECK(cudaMalloc(&impl_->mass, bytesD));
    MPCD_CUDA_CHECK(cudaMalloc(&impl_->type, bytesU));
    MPCD_CUDA_CHECK(cudaMalloc(&impl_->role, bytesR));
    impl_->n = n;
    impl_->capacity = n;
    impl_->nActiveFluid = n;
    impl_->allocatedBytes = 5u * bytesD + bytesU + bytesR;
    impl_->metadataSignature = 0u;
    impl_->metadataParticles = 0u;
    impl_->metadataUploaded = false;
    if (diag != nullptr) {
        diag->allocationCalls += 1u;
        diag->reusedAllocation = 0;
        diag->capacity = impl_->capacity;
        diag->allocatedBytes = impl_->allocatedBytes;
        diag->allocateSeconds += elapsed_seconds(t0);
    }
#endif
}

void CudaParticleState::upload_positions(const ParticleState& state, CudaParticleStateDiagnostics* diag) {
#ifndef MPCD_ENABLE_CUDA_PARTICLE_STATE
    (void)state; (void)diag;
    throw std::runtime_error("CudaParticleState::upload_positions called without MPCD_ENABLE_CUDA_PARTICLE_STATE");
#else
    const std::uint64_t nActive64 = active_prefix_count_no_fullscan_0315l(state,
        "CudaParticleState::upload_positions(0315l)");
    ensure_capacity(state.Np, diag);
    impl_->nActiveFluid = nActive64;
    const std::size_t n = static_cast<std::size_t>(nActive64);
    const std::size_t bytesD = n * sizeof(double);
    const auto t0 = Clock::now();
    if (n > 0u) {
        MPCD_CUDA_CHECK(cudaMemcpy(impl_->x, state.x.data(), bytesD, cudaMemcpyHostToDevice));
        MPCD_CUDA_CHECK(cudaMemcpy(impl_->y, state.y.data(), bytesD, cudaMemcpyHostToDevice));
    }
    if (diag != nullptr) {
        diag->uploadCalls += 1u;
        diag->hostToDeviceBytes += 2u * bytesD;
        diag->uploadSeconds += elapsed_seconds(t0);
        diag->particles = nActive64;
        diag->capacity = impl_->capacity;
        diag->allocatedBytes = impl_->allocatedBytes;
    }
#endif
}

void CudaParticleState::upload_velocities(const ParticleState& state, CudaParticleStateDiagnostics* diag) {
#ifndef MPCD_ENABLE_CUDA_PARTICLE_STATE
    (void)state; (void)diag;
    throw std::runtime_error("CudaParticleState::upload_velocities called without MPCD_ENABLE_CUDA_PARTICLE_STATE");
#else
    const std::uint64_t nActive64 = active_prefix_count_no_fullscan_0315l(state,
        "CudaParticleState::upload_velocities(0315l)");
    ensure_capacity(state.Np, diag);
    impl_->nActiveFluid = nActive64;
    const std::size_t n = static_cast<std::size_t>(nActive64);
    const std::size_t bytesD = n * sizeof(double);
    const auto t0 = Clock::now();
    if (n > 0u) {
        MPCD_CUDA_CHECK(cudaMemcpy(impl_->vx, state.vx.data(), bytesD, cudaMemcpyHostToDevice));
        MPCD_CUDA_CHECK(cudaMemcpy(impl_->vy, state.vy.data(), bytesD, cudaMemcpyHostToDevice));
    }
    if (diag != nullptr) {
        diag->uploadCalls += 1u;
        diag->hostToDeviceBytes += 2u * bytesD;
        diag->uploadSeconds += elapsed_seconds(t0);
        diag->particles = nActive64;
        diag->capacity = impl_->capacity;
        diag->allocatedBytes = impl_->allocatedBytes;
    }
#endif
}

void CudaParticleState::upload_roles(const ParticleState& state, CudaParticleStateDiagnostics* diag) {
#ifndef MPCD_ENABLE_CUDA_PARTICLE_STATE
    (void)state; (void)diag;
    throw std::runtime_error("CudaParticleState::upload_roles called without MPCD_ENABLE_CUDA_PARTICLE_STATE");
#else
    const std::uint64_t nActive64 = active_prefix_count_no_fullscan_0315l(state,
        "CudaParticleState::upload_roles(0315l)");
    ensure_capacity(state.Np, diag);
    impl_->nActiveFluid = nActive64;
    const std::size_t n = static_cast<std::size_t>(nActive64);
    const std::size_t bytesR = n * sizeof(unsigned char);
    const unsigned char* roleHost = role_upload_ptr_or_null(state);
    const auto t0 = Clock::now();
    if (n > 0u) {
        if (roleHost != nullptr) {
            MPCD_CUDA_CHECK(cudaMemcpy(impl_->role, roleHost, bytesR, cudaMemcpyHostToDevice));
        } else {
            MPCD_CUDA_CHECK(cudaMemset(impl_->role, kParticleRoleFluid, bytesR));
        }
    }
    // Do not mark the mass/type/role metadata cache as fully valid here: this
    // fast path intentionally uploads only role[]. A later
    // upload_kinematics_with_cached_metadata() must still refresh mass/type.
    if (diag != nullptr) {
        diag->uploadCalls += 1u;
        diag->hostToDeviceBytes += bytesR;
        diag->uploadSeconds += elapsed_seconds(t0);
        diag->particles = nActive64;
        diag->capacity = impl_->capacity;
        diag->allocatedBytes = impl_->allocatedBytes;
    }
#endif
}

void CudaParticleState::upload_masses_and_roles(const ParticleState& state, CudaParticleStateDiagnostics* diag) {
#ifndef MPCD_ENABLE_CUDA_PARTICLE_STATE
    (void)state; (void)diag;
    throw std::runtime_error("CudaParticleState::upload_masses_and_roles called without MPCD_ENABLE_CUDA_PARTICLE_STATE");
#else
    const std::uint64_t nActive64 = active_prefix_count_no_fullscan_0315l(state,
        "CudaParticleState::upload_masses_and_roles(0315l)");
    ensure_capacity(state.Np, diag);
    impl_->nActiveFluid = nActive64;
    const std::size_t n = static_cast<std::size_t>(nActive64);
    const std::size_t bytesD = n * sizeof(double);
    const std::size_t bytesU = n * sizeof(std::uint32_t);
    const std::size_t bytesR = n * sizeof(unsigned char);
    const unsigned char* roleHost = role_upload_ptr_or_null(state);
    const std::uint32_t* typeHost = type_upload_ptr_or_null(state);
    const auto t0 = Clock::now();
    if (n > 0u) {
        MPCD_CUDA_CHECK(cudaMemcpy(impl_->mass, state.mass.data(), bytesD, cudaMemcpyHostToDevice));
        if (typeHost != nullptr) {
            MPCD_CUDA_CHECK(cudaMemcpy(impl_->type, typeHost, bytesU, cudaMemcpyHostToDevice));
        } else {
            MPCD_CUDA_CHECK(cudaMemset(impl_->type, 0, bytesU));
        }
        if (roleHost != nullptr) {
            MPCD_CUDA_CHECK(cudaMemcpy(impl_->role, roleHost, bytesR, cudaMemcpyHostToDevice));
        } else {
            MPCD_CUDA_CHECK(cudaMemset(impl_->role, kParticleRoleFluid, bytesR));
        }
    }
    if (diag != nullptr) {
        diag->uploadCalls += 1u;
        diag->hostToDeviceBytes += bytesD + bytesU + bytesR;
        diag->uploadSeconds += elapsed_seconds(t0);
        diag->particles = nActive64;
        diag->capacity = impl_->capacity;
        diag->allocatedBytes = impl_->allocatedBytes;
    }
#endif
}

void CudaParticleState::upload_all(const ParticleState& state, CudaParticleStateDiagnostics* diag) {
#ifndef MPCD_ENABLE_CUDA_PARTICLE_STATE
    (void)state; (void)diag;
    throw std::runtime_error("CudaParticleState::upload_all called without MPCD_ENABLE_CUDA_PARTICLE_STATE");
#else
    // 0315j: upload_all is still the first resident-CUDA entry point in many
    // classic runs.  The legacy implementation copied x/y/vx/vy/mass/type/role
    // over the full storage capacity, so short runs still scaled with the
    // inactive reservoir even after all physical kernels were migrated to
    // NactiveFluid.  In the active-prefix layout, inactive tail slots are free
    // storage and their x/y/v/m/type payload is irrelevant until an insertion
    // kernel overwrites it.  Upload only [0,NactiveFluid) and initialise role[]
    // as [Fluid prefix][Inactive tail].
    const bool legacyFullValidate0315j =
        env_truthy_0315d("MPCD_CUDA_ACTIVE_PREFIX_UPLOAD_ALL_FULL_VALIDATE_0315J");
    if (legacyFullValidate0315j) {
        validate_particle_state(state, "CudaParticleState::upload_all(legacy full validate 0315j)");
    } else {
        validate_particle_state_shape_only_0315j(state, "CudaParticleState::upload_all(0315j)");
    }

    ensure_capacity(state.Np, diag);

    if (!active_prefix_upload_all_enabled_0315j(state)) {
        // Legacy exact path for old/non-normalised states or debugging.
        impl_->nActiveFluid = active_fluid_count(state);
        const std::size_t n = static_cast<std::size_t>(state.Np);
        const std::size_t bytesD = n * sizeof(double);
        const std::size_t bytesU = n * sizeof(std::uint32_t);
        const std::size_t bytesR = n * sizeof(unsigned char);
        const unsigned char* roleHost = role_upload_ptr_or_null(state);
        const std::uint32_t* typeHost = type_upload_ptr_or_null(state);
        const auto t0 = Clock::now();
        if (n > 0u) {
            MPCD_CUDA_CHECK(cudaMemcpy(impl_->x, state.x.data(), bytesD, cudaMemcpyHostToDevice));
            MPCD_CUDA_CHECK(cudaMemcpy(impl_->y, state.y.data(), bytesD, cudaMemcpyHostToDevice));
            MPCD_CUDA_CHECK(cudaMemcpy(impl_->vx, state.vx.data(), bytesD, cudaMemcpyHostToDevice));
            MPCD_CUDA_CHECK(cudaMemcpy(impl_->vy, state.vy.data(), bytesD, cudaMemcpyHostToDevice));
            MPCD_CUDA_CHECK(cudaMemcpy(impl_->mass, state.mass.data(), bytesD, cudaMemcpyHostToDevice));
            if (typeHost != nullptr) {
                MPCD_CUDA_CHECK(cudaMemcpy(impl_->type, typeHost, bytesU, cudaMemcpyHostToDevice));
            } else {
                MPCD_CUDA_CHECK(cudaMemset(impl_->type, 0, bytesU));
            }
            if (roleHost != nullptr) {
                MPCD_CUDA_CHECK(cudaMemcpy(impl_->role, roleHost, bytesR, cudaMemcpyHostToDevice));
            } else {
                MPCD_CUDA_CHECK(cudaMemset(impl_->role, kParticleRoleFluid, bytesR));
            }
        }
        impl_->metadataUploaded = false;
        impl_->activePrefixRoleLayoutInitialized0315k = false;
        impl_->activePrefixRoleLayoutActive0315k = 0u;
        impl_->activePrefixRoleLayoutCapacity0315k = 0u;
        if (diag != nullptr) {
            diag->uploadCalls += 1u;
            diag->hostToDeviceBytes += 5u * bytesD + bytesU + bytesR;
            diag->uploadSeconds += elapsed_seconds(t0);
            diag->particles = state.Np;
            diag->capacity = impl_->capacity;
            diag->allocatedBytes = impl_->allocatedBytes;
        }
        return;
    }

    const std::uint64_t nActive64 = state.role.empty() ? state.Np : state.NactiveFluid;
    if (nActive64 > state.Np) {
        throw std::runtime_error("CudaParticleState::upload_all(0315j): active prefix exceeds capacity");
    }
    impl_->nActiveFluid = nActive64;

    const std::size_t nTotal = static_cast<std::size_t>(state.Np);
    const std::size_t nActive = static_cast<std::size_t>(nActive64);
    const std::size_t bytesD = nActive * sizeof(double);
    const std::size_t bytesU = nActive * sizeof(std::uint32_t);
    const std::size_t bytesRolePrefix = nActive * sizeof(unsigned char);
    const bool forceFullRoleTail0315k =
        env_truthy_0315d("MPCD_CUDA_ACTIVE_PREFIX_UPLOAD_FULL_ROLE_TAIL_0315K");
    const bool needFullRoleTail0315k =
        forceFullRoleTail0315k ||
        !impl_->activePrefixRoleLayoutInitialized0315k ||
        impl_->activePrefixRoleLayoutCapacity0315k != state.Np;
    const std::uint64_t oldRoleActive0315k = impl_->activePrefixRoleLayoutActive0315k;
    std::uint64_t roleBytesTouched0315k = 0u;
    const auto t0 = Clock::now();
    if (nTotal > 0u) {
        if (nActive > 0u) {
            MPCD_CUDA_CHECK(cudaMemcpy(impl_->x, state.x.data(), bytesD, cudaMemcpyHostToDevice));
            MPCD_CUDA_CHECK(cudaMemcpy(impl_->y, state.y.data(), bytesD, cudaMemcpyHostToDevice));
            MPCD_CUDA_CHECK(cudaMemcpy(impl_->vx, state.vx.data(), bytesD, cudaMemcpyHostToDevice));
            MPCD_CUDA_CHECK(cudaMemcpy(impl_->vy, state.vy.data(), bytesD, cudaMemcpyHostToDevice));
            MPCD_CUDA_CHECK(cudaMemcpy(impl_->mass, state.mass.data(), bytesD, cudaMemcpyHostToDevice));
            MPCD_CUDA_CHECK(cudaMemcpy(impl_->type, state.type.data(), bytesU, cudaMemcpyHostToDevice));
        }
        // 0315k: the initial active-prefix upload must initialise role[] over
        // the inactive tail when pool scans may later consume it, but doing a
        // full-capacity cudaMemset on every wall/nonresident streaming step
        // reintroduced O(Np_total) scaling.  After the layout is known on this
        // allocation, refresh only the active prefix and, if Nactive shrank,
        // the crossed tail slice.  A full repair remains available through
        // MPCD_CUDA_ACTIVE_PREFIX_UPLOAD_FULL_ROLE_TAIL_0315K=1.
        if (needFullRoleTail0315k) {
            const std::size_t bytesRoleTotal = nTotal * sizeof(unsigned char);
            MPCD_CUDA_CHECK(cudaMemset(impl_->role, kParticleRoleInactive, bytesRoleTotal));
            roleBytesTouched0315k += static_cast<std::uint64_t>(bytesRoleTotal);
        } else if (oldRoleActive0315k > nActive64) {
            const std::uint64_t delta = oldRoleActive0315k - nActive64;
            MPCD_CUDA_CHECK(cudaMemset(impl_->role + nActive, kParticleRoleInactive,
                                       static_cast<std::size_t>(delta) * sizeof(unsigned char)));
            roleBytesTouched0315k += delta * sizeof(unsigned char);
        }
        if (nActive > 0u) {
            MPCD_CUDA_CHECK(cudaMemset(impl_->role, kParticleRoleFluid, bytesRolePrefix));
            roleBytesTouched0315k += static_cast<std::uint64_t>(bytesRolePrefix);
        }
        impl_->activePrefixRoleLayoutInitialized0315k = true;
        impl_->activePrefixRoleLayoutActive0315k = nActive64;
        impl_->activePrefixRoleLayoutCapacity0315k = state.Np;
    }

    // The full metadata cache is deliberately invalidated: only the active
    // prefix payload was uploaded.  Legacy CPU-owned kinematic paths that call
    // upload_kinematics_with_cached_metadata() must refresh their own metadata.
    impl_->metadataUploaded = false;
    impl_->metadataSignature = 0u;
    impl_->metadataParticles = 0u;

    if (diag != nullptr) {
        diag->uploadCalls += 1u;
        diag->hostToDeviceBytes += static_cast<std::uint64_t>(5u * bytesD + bytesU) + roleBytesTouched0315k;
        diag->uploadSeconds += elapsed_seconds(t0);
        diag->particles = state.Np;
        diag->capacity = impl_->capacity;
        diag->allocatedBytes = impl_->allocatedBytes;
    }
#endif
}


void CudaParticleState::upload_kinematics_with_cached_metadata(const ParticleState& state,
                                                               CudaParticleStateDiagnostics* diag) {
#ifndef MPCD_ENABLE_CUDA_PARTICLE_STATE
    (void)state; (void)diag;
    throw std::runtime_error("CudaParticleState::upload_kinematics_with_cached_metadata called without MPCD_ENABLE_CUDA_PARTICLE_STATE");
#else
    const std::uint64_t nActive64 = active_prefix_count_no_fullscan_0315l(state,
        "CudaParticleState::upload_kinematics_with_cached_metadata(0315l)");
    ensure_capacity(state.Np, diag);
    impl_->nActiveFluid = nActive64;
    const std::size_t n = static_cast<std::size_t>(nActive64);
    const std::size_t bytesD = n * sizeof(double);
    const std::size_t bytesU = n * sizeof(std::uint32_t);
    const std::size_t bytesR = n * sizeof(unsigned char);
    const unsigned char* roleHost = role_upload_ptr_or_null(state);
    const std::uint32_t* typeHost = type_upload_ptr_or_null(state);
    const std::uint64_t sig = cuda_particle_metadata_signature(state);
    const bool mustUploadMetadata =
        !impl_->metadataUploaded || impl_->metadataParticles != state.Np ||
        impl_->nActiveFluid != nActive64 || impl_->metadataSignature != sig;

    const auto t0 = Clock::now();
    if (n > 0u) {
        // 0315l: CPU transport owns only the active prefix.  Inactive tail
        // payloads are uninitialised free slots and must not be uploaded every
        // step.
        MPCD_CUDA_CHECK(cudaMemcpy(impl_->x, state.x.data(), bytesD, cudaMemcpyHostToDevice));
        MPCD_CUDA_CHECK(cudaMemcpy(impl_->y, state.y.data(), bytesD, cudaMemcpyHostToDevice));
        MPCD_CUDA_CHECK(cudaMemcpy(impl_->vx, state.vx.data(), bytesD, cudaMemcpyHostToDevice));
        MPCD_CUDA_CHECK(cudaMemcpy(impl_->vy, state.vy.data(), bytesD, cudaMemcpyHostToDevice));

        if (mustUploadMetadata) {
            MPCD_CUDA_CHECK(cudaMemcpy(impl_->mass, state.mass.data(), bytesD, cudaMemcpyHostToDevice));
            if (typeHost != nullptr) {
                MPCD_CUDA_CHECK(cudaMemcpy(impl_->type, typeHost, bytesU, cudaMemcpyHostToDevice));
            } else {
                MPCD_CUDA_CHECK(cudaMemset(impl_->type, 0, bytesU));
            }
            if (roleHost != nullptr) {
                MPCD_CUDA_CHECK(cudaMemcpy(impl_->role, roleHost, bytesR, cudaMemcpyHostToDevice));
            } else {
                MPCD_CUDA_CHECK(cudaMemset(impl_->role, kParticleRoleFluid, bytesR));
            }
            impl_->metadataSignature = sig;
            impl_->metadataParticles = state.Np;
            impl_->metadataUploaded = true;
            impl_->activePrefixRoleLayoutActive0315k = nActive64;
            impl_->activePrefixRoleLayoutCapacity0315k = state.Np;
            impl_->activePrefixRoleLayoutInitialized0315k = true;
        }
    } else {
        impl_->metadataSignature = sig;
        impl_->metadataParticles = state.Np;
        impl_->metadataUploaded = true;
        impl_->activePrefixRoleLayoutActive0315k = 0u;
        impl_->activePrefixRoleLayoutCapacity0315k = state.Np;
        impl_->activePrefixRoleLayoutInitialized0315k = true;
    }

    if (diag != nullptr) {
        diag->uploadCalls += 1u;
        diag->hostToDeviceBytes += 4u * bytesD + (mustUploadMetadata ? (bytesD + bytesU + bytesR) : 0u);
        if (mustUploadMetadata) {
            diag->metadataUploadCalls += 1u;
        } else {
            diag->metadataCacheHits += 1u;
            diag->metadataBytesSkipped += bytesD + bytesU + bytesR;
        }
        diag->uploadSeconds += elapsed_seconds(t0);
        diag->particles = nActive64;
        diag->capacity = impl_->capacity;
        diag->allocatedBytes = impl_->allocatedBytes;
    }
#endif
}


void CudaParticleState::download_velocities(ParticleState& state, CudaParticleStateDiagnostics* diag) const {
#ifndef MPCD_ENABLE_CUDA_PARTICLE_STATE
    (void)state; (void)diag;
    throw std::runtime_error("CudaParticleState::download_velocities called without MPCD_ENABLE_CUDA_PARTICLE_STATE");
#else
    if (impl_ == nullptr) throw std::runtime_error("CudaParticleState::download_velocities: null impl");
    if (state.Np != impl_->n) throw std::runtime_error("CudaParticleState::download_velocities: host particle count mismatch");
    validate_particle_state_shape_only_0315j(state, "CudaParticleState::download_velocities(0315l)");
    const std::uint64_t nActive64 = impl_->nActiveFluid;
    if (nActive64 > impl_->n) throw std::runtime_error("CudaParticleState::download_velocities: active count exceeds capacity");
    const std::size_t n = static_cast<std::size_t>(nActive64);
    const std::size_t bytesD = n * sizeof(double);
    const auto t0 = Clock::now();
    if (n > 0u) {
        MPCD_CUDA_CHECK(cudaMemcpy(state.vx.data(), impl_->vx, bytesD, cudaMemcpyDeviceToHost));
        MPCD_CUDA_CHECK(cudaMemcpy(state.vy.data(), impl_->vy, bytesD, cudaMemcpyDeviceToHost));
    }
    state.NactiveFluid = impl_->nActiveFluid;
    if (diag != nullptr) {
        diag->downloadCalls += 1u;
        diag->deviceToHostBytes += 2u * bytesD;
        diag->downloadSeconds += elapsed_seconds(t0);
        diag->particles = nActive64;
        diag->capacity = impl_->capacity;
        diag->allocatedBytes = impl_->allocatedBytes;
    }
#endif
}

void CudaParticleState::download_masses_and_velocities(ParticleState& state,
                                                       CudaParticleStateDiagnostics* diag) const {
#ifndef MPCD_ENABLE_CUDA_PARTICLE_STATE
    (void)state; (void)diag;
    throw std::runtime_error("CudaParticleState::download_masses_and_velocities called without MPCD_ENABLE_CUDA_PARTICLE_STATE");
#else
    if (impl_ == nullptr) throw std::runtime_error("CudaParticleState::download_masses_and_velocities: null impl");
    if (state.Np != impl_->n) throw std::runtime_error("CudaParticleState::download_masses_and_velocities: host particle count mismatch");
    validate_particle_state_shape_only_0315j(state, "CudaParticleState::download_masses_and_velocities");
    const std::uint64_t nActive64 = impl_->nActiveFluid;
    if (nActive64 > impl_->n) throw std::runtime_error("CudaParticleState::download_masses_and_velocities: active count exceeds capacity");
    const std::size_t n = static_cast<std::size_t>(nActive64);
    const std::size_t bytesD = n * sizeof(double);
    const auto t0 = Clock::now();
    if (n > 0u) {
        MPCD_CUDA_CHECK(cudaMemcpy(state.mass.data(), impl_->mass, bytesD, cudaMemcpyDeviceToHost));
        MPCD_CUDA_CHECK(cudaMemcpy(state.vx.data(), impl_->vx, bytesD, cudaMemcpyDeviceToHost));
        MPCD_CUDA_CHECK(cudaMemcpy(state.vy.data(), impl_->vy, bytesD, cudaMemcpyDeviceToHost));
    }
    state.NactiveFluid = impl_->nActiveFluid;
    if (diag != nullptr) {
        diag->downloadCalls += 1u;
        diag->deviceToHostBytes += 3u * bytesD;
        diag->downloadSeconds += elapsed_seconds(t0);
        diag->particles = nActive64;
        diag->capacity = impl_->capacity;
        diag->allocatedBytes = impl_->allocatedBytes;
    }
#endif
}


void CudaParticleState::download_active_prefix(ParticleState& state, CudaParticleStateDiagnostics* diag) const {
#ifndef MPCD_ENABLE_CUDA_PARTICLE_STATE
    (void)state; (void)diag;
    throw std::runtime_error("CudaParticleState::download_active_prefix called without MPCD_ENABLE_CUDA_PARTICLE_STATE");
#else
    if (impl_ == nullptr) throw std::runtime_error("CudaParticleState::download_active_prefix: null impl");
    if (state.Np != impl_->n) throw std::runtime_error("CudaParticleState::download_active_prefix: host particle count mismatch");

    // 0315h: this routine is now on the hot path for remaining mixed
    // host/device consumers after a CUDA inlet/outlet active-prefix mutation.
    // The previous 0315c-fix06 implementation copied only the active prefix,
    // but still performed two O(Np_total) host operations on every call:
    //   - validate_particle_state()/validate_active_fluid_prefix() scanned role[];
    //   - std::fill([Nactive,Np), Inactive) rewrote the entire inactive reservoir.
    // With 1e6 reserved inactive slots this erased much of the active-prefix
    // benefit.  Keep the production path O(Nactive + |delta Nactive|).  Full
    // tail repair / full validation remain available for debugging.
    const bool fullValidate0315h = env_truthy_0315d("MPCD_CUDA_ACTIVE_PREFIX_HOST_FULL_VALIDATE_0315H");
    const bool fullTailRepair0315h = env_truthy_0315d("MPCD_CUDA_ACTIVE_PREFIX_HOST_TAIL_FULL_REPAIR_0315H");

    if (fullValidate0315h) {
        validate_particle_state(state, "CudaParticleState::download_active_prefix(before 0315h)");
    } else {
        const std::size_t nCheck = static_cast<std::size_t>(state.Np);
        if (static_cast<std::uint64_t>(nCheck) != state.Np) {
            throw std::runtime_error("CudaParticleState::download_active_prefix: host particle count does not fit size_t");
        }
        if (state.dim != 2u ||
            state.x.size() != nCheck || state.y.size() != nCheck ||
            state.vx.size() != nCheck || state.vy.size() != nCheck ||
            state.mass.size() != nCheck || state.type.size() != nCheck ||
            (!state.role.empty() && state.role.size() != nCheck) ||
            state.NactiveFluid > state.Np) {
            throw std::runtime_error("CudaParticleState::download_active_prefix: inconsistent host SoA sizes");
        }
    }

    const std::uint64_t nActive64 = impl_->nActiveFluid;
    if (nActive64 > impl_->n) throw std::runtime_error("CudaParticleState::download_active_prefix: active count exceeds capacity");
    const std::size_t nTotal = static_cast<std::size_t>(state.Np);
    const std::size_t nActive = static_cast<std::size_t>(nActive64);
    if (static_cast<std::uint64_t>(nActive) != nActive64) {
        throw std::runtime_error("CudaParticleState::download_active_prefix: active count does not fit size_t");
    }

    std::size_t oldActive = 0u;
    if (!state.role.empty()) {
        if (state.NactiveFluid <= state.Np) {
            oldActive = static_cast<std::size_t>(state.NactiveFluid);
        }
    } else {
        state.role.assign(nTotal, kParticleRoleInactive);
    }

    const std::size_t bytesD = nActive * sizeof(double);
    const std::size_t bytesU = nActive * sizeof(std::uint32_t);
    const auto t0 = Clock::now();
    if (nActive > 0u) {
        MPCD_CUDA_CHECK(cudaMemcpy(state.x.data(), impl_->x, bytesD, cudaMemcpyDeviceToHost));
        MPCD_CUDA_CHECK(cudaMemcpy(state.y.data(), impl_->y, bytesD, cudaMemcpyDeviceToHost));
        MPCD_CUDA_CHECK(cudaMemcpy(state.vx.data(), impl_->vx, bytesD, cudaMemcpyDeviceToHost));
        MPCD_CUDA_CHECK(cudaMemcpy(state.vy.data(), impl_->vy, bytesD, cudaMemcpyDeviceToHost));
        MPCD_CUDA_CHECK(cudaMemcpy(state.mass.data(), impl_->mass, bytesD, cudaMemcpyDeviceToHost));
        MPCD_CUDA_CHECK(cudaMemcpy(state.type.data(), impl_->type, bytesU, cudaMemcpyDeviceToHost));
    }

    if (fullTailRepair0315h) {
        std::fill(state.role.begin(), state.role.begin() + static_cast<std::ptrdiff_t>(nActive), kParticleRoleFluid);
        std::fill(state.role.begin() + static_cast<std::ptrdiff_t>(nActive), state.role.end(), kParticleRoleInactive);
    } else {
        // 0315h-fix10: always repair the complete active prefix role mirror.
        // The previous incremental-only update was too optimistic: after a
        // CUDA IO/solid compaction, the active count may be unchanged while the
        // host-side role pattern in [0,nActive) is stale.  Several CPU wrappers
        // still use role[] as a guard even though they loop only on Nactive, so
        // stale holes in the prefix changed the trajectory.  Repairing the
        // prefix is O(Nactive), which is acceptable and still removes the
        // catastrophic O(Np_total) inactive-tail scan/fill.
        if (nActive > 0u) {
            std::fill(state.role.begin(),
                      state.role.begin() + static_cast<std::ptrdiff_t>(nActive),
                      kParticleRoleFluid);
        }

        // Only repair the tail slice crossed since the previous host mirror.
        // This preserves the 0315h objective: no full inactive reservoir sweep.
        if (oldActive > nActive) {
            std::fill(state.role.begin() + static_cast<std::ptrdiff_t>(nActive),
                      state.role.begin() + static_cast<std::ptrdiff_t>(oldActive),
                      kParticleRoleInactive);
        }
    }
    state.NactiveFluid = nActive64;

    if (diag != nullptr) {
        diag->downloadCalls += 1u;
        diag->deviceToHostBytes += 5u * bytesD + bytesU;
        diag->downloadSeconds += elapsed_seconds(t0);
        diag->particles = state.Np;
        diag->capacity = impl_->capacity;
        diag->allocatedBytes = impl_->allocatedBytes;
    }
    if (fullValidate0315h) {
        validate_active_fluid_prefix(state, "CudaParticleState::download_active_prefix(after 0315h)");
    }
#endif
}

void CudaParticleState::download_all(ParticleState& state, CudaParticleStateDiagnostics* diag) const {
#ifndef MPCD_ENABLE_CUDA_PARTICLE_STATE
    (void)state; (void)diag;
    throw std::runtime_error("CudaParticleState::download_all called without MPCD_ENABLE_CUDA_PARTICLE_STATE");
#else
    if (impl_ == nullptr) throw std::runtime_error("CudaParticleState::download_all: null impl");
    if (state.Np != impl_->n) throw std::runtime_error("CudaParticleState::download_all: host particle count mismatch");
    validate_particle_state(state, "CudaParticleState::download_all(before)");
    const std::size_t n = static_cast<std::size_t>(state.Np);
    const std::size_t bytesD = n * sizeof(double);
    const std::size_t bytesU = n * sizeof(std::uint32_t);
    const std::size_t bytesR = n * sizeof(unsigned char);
    if (state.role.empty()) state.role.assign(n, kParticleRoleFluid);
    const auto t0 = Clock::now();
    if (n > 0u) {
        MPCD_CUDA_CHECK(cudaMemcpy(state.x.data(), impl_->x, bytesD, cudaMemcpyDeviceToHost));
        MPCD_CUDA_CHECK(cudaMemcpy(state.y.data(), impl_->y, bytesD, cudaMemcpyDeviceToHost));
        MPCD_CUDA_CHECK(cudaMemcpy(state.vx.data(), impl_->vx, bytesD, cudaMemcpyDeviceToHost));
        MPCD_CUDA_CHECK(cudaMemcpy(state.vy.data(), impl_->vy, bytesD, cudaMemcpyDeviceToHost));
        MPCD_CUDA_CHECK(cudaMemcpy(state.mass.data(), impl_->mass, bytesD, cudaMemcpyDeviceToHost));
        MPCD_CUDA_CHECK(cudaMemcpy(state.type.data(), impl_->type, bytesU, cudaMemcpyDeviceToHost));
        MPCD_CUDA_CHECK(cudaMemcpy(state.role.data(), impl_->role, bytesR, cudaMemcpyDeviceToHost));
    }
    refresh_active_fluid_count(state);
    if (diag != nullptr) {
        diag->downloadCalls += 1u;
        diag->deviceToHostBytes += 5u * bytesD + bytesU + bytesR;
        diag->downloadSeconds += elapsed_seconds(t0);
        diag->particles = state.Np;
        diag->capacity = impl_->capacity;
        diag->allocatedBytes = impl_->allocatedBytes;
    }
    validate_particle_state(state, "CudaParticleState::download_all(after)");
#endif
}


void CudaParticleState::download_role_filtered(ParticleState& state,
                                               unsigned char keepRole,
                                               ParticleRoleCounts* roleCounts,
                                               CudaParticleStateDiagnostics* diag) const {
#ifndef MPCD_ENABLE_CUDA_PARTICLE_STATE
    (void)state; (void)keepRole; (void)roleCounts; (void)diag;
    throw std::runtime_error("CudaParticleState::download_role_filtered called without MPCD_ENABLE_CUDA_PARTICLE_STATE");
#else
    if (impl_ == nullptr) throw std::runtime_error("CudaParticleState::download_role_filtered: null impl");
    const std::size_t n = static_cast<std::size_t>(impl_->n);
    if (static_cast<std::uint64_t>(n) != impl_->n) {
        throw std::runtime_error("CudaParticleState::download_role_filtered: particle count does not fit size_t");
    }

    const auto t0 = Clock::now();

    // 0315d: with the active-prefix invariant, the overwhelmingly common
    // production consumer is a fluid-only summary/dump.  Avoid downloading and
    // scanning the full role array of the reserved inactive capacity; copy only
    // [0, nActiveFluid).  A legacy full role scan remains available for
    // debugging mixed latent tails.
    if (keepRole == kParticleRoleFluid &&
        !env_truthy_0315d("MPCD_CUDA_ROLE_FILTER_FULL_ROLE_SCAN_0315D")) {
        const std::uint64_t nActive64 = impl_->nActiveFluid;
        if (nActive64 > impl_->n) {
            throw std::runtime_error("CudaParticleState::download_role_filtered: active count exceeds storage size");
        }
        const std::size_t nActive = static_cast<std::size_t>(nActive64);
        if (static_cast<std::uint64_t>(nActive) != nActive64) {
            throw std::runtime_error("CudaParticleState::download_role_filtered: active count does not fit size_t");
        }

        ParticleState out{};
        out.dim = 2u;
        out.Np = nActive64;
        out.NactiveFluid = nActive64;
        out.x.resize(nActive);
        out.y.resize(nActive);
        out.vx.resize(nActive);
        out.vy.resize(nActive);
        out.mass.resize(nActive);
        out.type.resize(nActive);
        out.role.assign(nActive, kParticleRoleFluid);

        const std::size_t bytesD = nActive * sizeof(double);
        const std::size_t bytesU = nActive * sizeof(std::uint32_t);
        if (nActive > 0u) {
            MPCD_CUDA_CHECK(cudaMemcpy(out.x.data(), impl_->x, bytesD, cudaMemcpyDeviceToHost));
            MPCD_CUDA_CHECK(cudaMemcpy(out.y.data(), impl_->y, bytesD, cudaMemcpyDeviceToHost));
            MPCD_CUDA_CHECK(cudaMemcpy(out.vx.data(), impl_->vx, bytesD, cudaMemcpyDeviceToHost));
            MPCD_CUDA_CHECK(cudaMemcpy(out.vy.data(), impl_->vy, bytesD, cudaMemcpyDeviceToHost));
            MPCD_CUDA_CHECK(cudaMemcpy(out.mass.data(), impl_->mass, bytesD, cudaMemcpyDeviceToHost));
            MPCD_CUDA_CHECK(cudaMemcpy(out.type.data(), impl_->type, bytesU, cudaMemcpyDeviceToHost));
        }
        validate_particle_state(out, "CudaParticleState::download_role_filtered(active-prefix 0315d)");
        state = std::move(out);

        if (roleCounts != nullptr) {
            roleCounts->fluid = nActive64;
            roleCounts->inactive = impl_->n - nActive64;
            roleCounts->latent = 0u;
        }
        if (diag != nullptr) {
            diag->downloadCalls += 1u;
            diag->deviceToHostBytes += static_cast<std::uint64_t>(5u * bytesD + bytesU);
            diag->downloadSeconds += elapsed_seconds(t0);
            diag->particles = nActive64;
            diag->capacity = impl_->capacity;
            diag->allocatedBytes = impl_->allocatedBytes;
        }
        return;
    }

    std::vector<unsigned char> roles(n, kParticleRoleFluid);
    if (n > 0u) {
        MPCD_CUDA_CHECK(cudaMemcpy(roles.data(), impl_->role, n * sizeof(unsigned char), cudaMemcpyDeviceToHost));
    }

    ParticleRoleCounts counts{};
    std::size_t selected = 0u;
    std::vector<std::pair<std::size_t, std::size_t>> runs;
    std::size_t i = 0u;
    while (i < n) {
        const unsigned char r = roles[i];
        if (r == kParticleRoleFluid) ++counts.fluid;
        else if (r == kParticleRoleInactive) ++counts.inactive;
        else if (r == kParticleRoleLatent) ++counts.latent;

        if (r != keepRole) {
            ++i;
            continue;
        }
        const std::size_t start = i;
        while (i < n && roles[i] == keepRole) {
            ++i;
        }
        const std::size_t len = i - start;
        runs.emplace_back(start, len);
        selected += len;
    }
    // Finish role counts for non-selected runs skipped by the inner loop above.
    // The loop above counted only the first element of each selected run before
    // consuming it, so recount exactly once here for clarity and robustness.
    counts = {};
    for (unsigned char r : roles) {
        if (r == kParticleRoleFluid) ++counts.fluid;
        else if (r == kParticleRoleInactive) ++counts.inactive;
        else if (r == kParticleRoleLatent) ++counts.latent;
    }
    if (roleCounts != nullptr) {
        *roleCounts = counts;
    }

    ParticleState out{};
    out.dim = 2u;
    out.Np = static_cast<std::uint64_t>(selected);
    out.NactiveFluid = (keepRole == kParticleRoleFluid) ? out.Np : 0u;
    out.x.resize(selected);
    out.y.resize(selected);
    out.vx.resize(selected);
    out.vy.resize(selected);
    out.mass.resize(selected);
    out.type.resize(selected);
    out.role.assign(selected, keepRole);

    std::size_t dst = 0u;
    std::uint64_t copiedBytes = static_cast<std::uint64_t>(n * sizeof(unsigned char));
    for (const auto& run : runs) {
        const std::size_t start = run.first;
        const std::size_t len = run.second;
        const std::size_t bytesD = len * sizeof(double);
        const std::size_t bytesU = len * sizeof(std::uint32_t);
        if (len == 0u) continue;
        MPCD_CUDA_CHECK(cudaMemcpy(out.x.data() + dst, impl_->x + start, bytesD, cudaMemcpyDeviceToHost));
        MPCD_CUDA_CHECK(cudaMemcpy(out.y.data() + dst, impl_->y + start, bytesD, cudaMemcpyDeviceToHost));
        MPCD_CUDA_CHECK(cudaMemcpy(out.vx.data() + dst, impl_->vx + start, bytesD, cudaMemcpyDeviceToHost));
        MPCD_CUDA_CHECK(cudaMemcpy(out.vy.data() + dst, impl_->vy + start, bytesD, cudaMemcpyDeviceToHost));
        MPCD_CUDA_CHECK(cudaMemcpy(out.mass.data() + dst, impl_->mass + start, bytesD, cudaMemcpyDeviceToHost));
        MPCD_CUDA_CHECK(cudaMemcpy(out.type.data() + dst, impl_->type + start, bytesU, cudaMemcpyDeviceToHost));
        copiedBytes += static_cast<std::uint64_t>(5u * bytesD + bytesU);
        dst += len;
    }
    validate_particle_state(out, "CudaParticleState::download_role_filtered(after)");
    state = std::move(out);

    if (diag != nullptr) {
        diag->downloadCalls += 1u;
        diag->deviceToHostBytes += copiedBytes;
        diag->downloadSeconds += elapsed_seconds(t0);
        diag->particles = static_cast<std::uint64_t>(selected);
        diag->capacity = impl_->capacity;
        diag->allocatedBytes = impl_->allocatedBytes;
    }
#endif
}

CudaParticleDeviceView CudaParticleState::device_view() {
    if (impl_ == nullptr) return {};
    return CudaParticleDeviceView{impl_->n, impl_->capacity, impl_->nActiveFluid,
                                  impl_->x, impl_->y, impl_->vx, impl_->vy,
                                  impl_->mass, impl_->type, impl_->role};
}

CudaParticleDeviceView CudaParticleState::device_view() const {
    if (impl_ == nullptr) return {};
    return CudaParticleDeviceView{impl_->n, impl_->capacity, impl_->nActiveFluid,
                                  impl_->x, impl_->y, impl_->vx, impl_->vy,
                                  impl_->mass, impl_->type, impl_->role};
}

std::uint64_t CudaParticleState::size() const { return impl_ ? impl_->n : 0u; }
std::uint64_t CudaParticleState::capacity() const { return impl_ ? impl_->capacity : 0u; }
std::uint64_t CudaParticleState::active_fluid_size() const { return impl_ ? impl_->nActiveFluid : 0u; }

void CudaParticleState::set_active_fluid_size(std::uint64_t nActiveFluid) {
#ifdef MPCD_ENABLE_CUDA_PARTICLE_STATE
    if (impl_ == nullptr) throw std::runtime_error("CudaParticleState::set_active_fluid_size: null impl");
    if (nActiveFluid > impl_->n) {
        throw std::runtime_error("CudaParticleState::set_active_fluid_size: active count exceeds storage size");
    }
    impl_->nActiveFluid = nActiveFluid;
#else
    (void)nActiveFluid;
    throw std::runtime_error("CudaParticleState::set_active_fluid_size called without MPCD_ENABLE_CUDA_PARTICLE_STATE");
#endif
}

std::uint64_t CudaParticleState::allocated_bytes() const { return impl_ ? impl_->allocatedBytes : 0u; }

void cuda_particle_state_smoke_increment_fluid_velocities(CudaParticleState& gpuState,
                                                          int cycles,
                                                          double dvx,
                                                          double dvy,
                                                          int threadsPerBlock,
                                                          CudaParticleStateDiagnostics* diag) {
#ifndef MPCD_ENABLE_CUDA_PARTICLE_STATE
    (void)gpuState; (void)cycles; (void)dvx; (void)dvy; (void)threadsPerBlock; (void)diag;
    throw std::runtime_error("cuda_particle_state_smoke_increment_fluid_velocities called without MPCD_ENABLE_CUDA_PARTICLE_STATE");
#else
    const CudaParticleDeviceView v = gpuState.device_view();
    const std::size_t n = static_cast<std::size_t>(v.n);
    if (static_cast<std::uint64_t>(n) != v.n) throw std::runtime_error("cuda_particle_state_smoke_increment: n too large");
    const int nInt = static_cast<int>(n);
    if (static_cast<std::size_t>(nInt) != n) throw std::runtime_error("cuda_particle_state_smoke_increment: n does not fit int kernels");
    const int threads = std::max(32, threadsPerBlock);
    const int blocks = std::max(1, (nInt + threads - 1) / threads);
    const auto t0 = Clock::now();
    for (int c = 0; c < std::max(0, cycles); ++c) {
        smoke_increment_fluid_velocities_kernel<<<blocks, threads>>>(nInt, v.role, v.vx, v.vy,
                                                                     dvx, dvy,
                                                                     static_cast<unsigned char>(kParticleRoleFluid));
        MPCD_CUDA_CHECK(cudaGetLastError());
    }
    MPCD_CUDA_CHECK(cudaDeviceSynchronize());
    if (diag != nullptr) diag->kernelSeconds += elapsed_seconds(t0);
#endif
}

CudaParticleStateSmokeResult cuda_particle_state_smoke_roundtrip(const ParticleState& input,
                                                                 int cycles,
                                                                 double dvx,
                                                                 double dvy,
                                                                 int threadsPerBlock,
                                                                 double tolerance) {
    validate_particle_state(input, "cuda_particle_state_smoke_roundtrip(input)");
    const auto tTotal0 = Clock::now();
    ParticleState out = input;
    CudaParticleStateSmokeResult result{};
    result.particles = input.Np;
    result.cycles = cycles;
    result.dvx = dvx;
    result.dvy = dvy;

    const ParticleRoleCounts counts = count_particle_roles(input);
    result.fluidParticles = counts.fluid;
    result.latentParticles = counts.latent;
    result.inactiveParticles = counts.inactive;

    CudaParticleState gpu;
    CudaParticleStateDiagnostics diag{};
    gpu.upload_all(input, &diag);

    // Exercise allocation reuse and partial velocity upload without changing
    // semantics. This is intentionally a no-op reupload of vx/vy that should not
    // allocate again when the capacity is already sufficient.
    CudaParticleStateDiagnostics reuseDiag{};
    gpu.upload_velocities(input, &reuseDiag);
    diag.allocationCalls += reuseDiag.allocationCalls;
    diag.uploadCalls += reuseDiag.uploadCalls;
    diag.hostToDeviceBytes += reuseDiag.hostToDeviceBytes;
    diag.uploadSeconds += reuseDiag.uploadSeconds;
    if (reuseDiag.reusedAllocation) diag.reusedAllocation = 1;

    cuda_particle_state_smoke_increment_fluid_velocities(gpu, cycles, dvx, dvy, threadsPerBlock, &diag);
    gpu.download_velocities(out, &diag);

    double sumSq = 0.0;
    const std::size_t n = static_cast<std::size_t>(input.Np);
    const double dvxTot = static_cast<double>(std::max(0, cycles)) * dvx;
    const double dvyTot = static_cast<double>(std::max(0, cycles)) * dvy;
    for (std::size_t i = 0; i < n; ++i) {
        const double ex = input.x[i];
        const double ey = input.y[i];
        const bool fluid = particle_role_value(input, i) == kParticleRoleFluid;
        const double evx = input.vx[i] + (fluid ? dvxTot : 0.0);
        const double evy = input.vy[i] + (fluid ? dvyTot : 0.0);
        const double dx = std::abs(out.x[i] - ex);
        const double dy = std::abs(out.y[i] - ey);
        const double dvxx = std::abs(out.vx[i] - evx);
        const double dvyy = std::abs(out.vy[i] - evy);
        result.maxAbsX = std::max(result.maxAbsX, dx);
        result.maxAbsY = std::max(result.maxAbsY, dy);
        result.maxAbsVx = std::max(result.maxAbsVx, dvxx);
        result.maxAbsVy = std::max(result.maxAbsVy, dvyy);
        sumSq += dvxx * dvxx + dvyy * dvyy;
        if (dvxx > tolerance || dvyy > tolerance || dx > tolerance || dy > tolerance) {
            ++result.velocityMismatches;
        }
    }
    result.rmsV = n > 0u ? std::sqrt(sumSq / static_cast<double>(2u * n)) : 0.0;
    diag.totalSeconds = elapsed_seconds(tTotal0);
    result.diagnostics = diag;
    result.pass = (result.velocityMismatches == 0u) ? 1 : 0;
    return result;
}

} // namespace mpcd
