#include "cuda_particle_state.h"

#include <cuda_runtime.h>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstddef>
#include <cstdint>
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
    constexpr std::uint64_t offset = 1469598103934665603ULL;
    std::uint64_t h = offset;
    const std::uint64_t n = state.Np;
    h = fnv1a_bytes(h, &n, sizeof(n));
    const std::size_t nn = static_cast<std::size_t>(n);
    if (n > 0u) {
        h = fnv1a_bytes(h, state.mass.data(), nn * sizeof(double));
        const bool hasType = !state.type.empty();
        const bool hasRole = !state.role.empty();
        h = fnv1a_bytes(h, &hasType, sizeof(hasType));
        h = fnv1a_bytes(h, &hasRole, sizeof(hasRole));
        if (hasType) {
            h = fnv1a_bytes(h, state.type.data(), nn * sizeof(std::uint32_t));
        }
        if (hasRole) {
            h = fnv1a_bytes(h, state.role.data(), nn * sizeof(unsigned char));
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
    std::uint64_t allocatedBytes = 0u;
    std::uint64_t metadataSignature = 0u;
    std::uint64_t metadataParticles = 0u;
    bool metadataUploaded = false;

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
        allocatedBytes = 0u;
        metadataSignature = 0u;
        metadataParticles = 0u;
        metadataUploaded = false;
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
    validate_particle_state(state, "CudaParticleState::upload_positions");
    ensure_capacity(state.Np, diag);
    const std::size_t n = static_cast<std::size_t>(state.Np);
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
        diag->particles = state.Np;
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
    validate_particle_state(state, "CudaParticleState::upload_velocities");
    ensure_capacity(state.Np, diag);
    const std::size_t n = static_cast<std::size_t>(state.Np);
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
        diag->particles = state.Np;
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
    validate_particle_state(state, "CudaParticleState::upload_roles");
    ensure_capacity(state.Np, diag);
    const std::size_t n = static_cast<std::size_t>(state.Np);
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
        diag->particles = state.Np;
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
    validate_particle_state(state, "CudaParticleState::upload_masses_and_roles");
    ensure_capacity(state.Np, diag);
    const std::size_t n = static_cast<std::size_t>(state.Np);
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
        diag->particles = state.Np;
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
    validate_particle_state(state, "CudaParticleState::upload_all");
    ensure_capacity(state.Np, diag);
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
    if (diag != nullptr) {
        diag->uploadCalls += 1u;
        diag->hostToDeviceBytes += 5u * bytesD + bytesU + bytesR;
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
    validate_particle_state(state, "CudaParticleState::upload_kinematics_with_cached_metadata");
    ensure_capacity(state.Np, diag);
    const std::size_t n = static_cast<std::size_t>(state.Np);
    const std::size_t bytesD = n * sizeof(double);
    const std::size_t bytesU = n * sizeof(std::uint32_t);
    const std::size_t bytesR = n * sizeof(unsigned char);
    const unsigned char* roleHost = role_upload_ptr_or_null(state);
    const std::uint32_t* typeHost = type_upload_ptr_or_null(state);
    const std::uint64_t sig = cuda_particle_metadata_signature(state);
    const bool mustUploadMetadata =
        !impl_->metadataUploaded || impl_->metadataParticles != state.Np || impl_->metadataSignature != sig;

    const auto t0 = Clock::now();
    if (n > 0u) {
        // CPU transport still owns positions and velocities before this
        // substep, so x/y/vx/vy must be refreshed every call.
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
        }
    } else {
        impl_->metadataSignature = sig;
        impl_->metadataParticles = state.Np;
        impl_->metadataUploaded = true;
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
        diag->particles = state.Np;
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
    validate_particle_state(state, "CudaParticleState::download_velocities");
    const std::size_t n = static_cast<std::size_t>(state.Np);
    const std::size_t bytesD = n * sizeof(double);
    const auto t0 = Clock::now();
    if (n > 0u) {
        MPCD_CUDA_CHECK(cudaMemcpy(state.vx.data(), impl_->vx, bytesD, cudaMemcpyDeviceToHost));
        MPCD_CUDA_CHECK(cudaMemcpy(state.vy.data(), impl_->vy, bytesD, cudaMemcpyDeviceToHost));
    }
    if (diag != nullptr) {
        diag->downloadCalls += 1u;
        diag->deviceToHostBytes += 2u * bytesD;
        diag->downloadSeconds += elapsed_seconds(t0);
        diag->particles = state.Np;
        diag->capacity = impl_->capacity;
        diag->allocatedBytes = impl_->allocatedBytes;
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

CudaParticleDeviceView CudaParticleState::device_view() {
    if (impl_ == nullptr) return {};
    return CudaParticleDeviceView{impl_->n, impl_->x, impl_->y, impl_->vx, impl_->vy, impl_->mass, impl_->type, impl_->role};
}

CudaParticleDeviceView CudaParticleState::device_view() const {
    if (impl_ == nullptr) return {};
    return CudaParticleDeviceView{impl_->n, impl_->x, impl_->y, impl_->vx, impl_->vy, impl_->mass, impl_->type, impl_->role};
}

std::uint64_t CudaParticleState::size() const { return impl_ ? impl_->n : 0u; }
std::uint64_t CudaParticleState::capacity() const { return impl_ ? impl_->capacity : 0u; }
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
