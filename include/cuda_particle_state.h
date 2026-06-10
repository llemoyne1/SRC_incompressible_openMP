#pragma once

#include "particle_state.h"

#include <cstddef>
#include <cstdint>

namespace mpcd {

// 0218: shared persistent GPU particle state manager.
//
// This is intentionally a small reusable ownership layer, not a new physics
// path. The goal is to stop every CUDA brick from allocating/uploading its own
// x/y/vx/vy/mass/role buffers. Later patches can pass device_view() to deposit,
// collision, thermostat and projection boundary adapters.
struct CudaParticleDeviceView {
    // n/capacity keep the historical full storage size.  nActiveFluid is the
    // 0315a logical particle count that later kernels should use for physical
    // operators once migrated away from scanning inactive slots.
    std::uint64_t n = 0u;
    std::uint64_t capacity = 0u;
    std::uint64_t nActiveFluid = 0u;
    double* x = nullptr;
    double* y = nullptr;
    double* vx = nullptr;
    double* vy = nullptr;
    double* mass = nullptr;
    std::uint32_t* type = nullptr;
    unsigned char* role = nullptr;
};

struct CudaParticleStateDiagnostics {
    std::uint64_t particles = 0u;
    std::uint64_t capacity = 0u;
    std::uint64_t allocatedBytes = 0u;
    std::uint64_t hostToDeviceBytes = 0u;
    std::uint64_t deviceToHostBytes = 0u;
    std::uint64_t allocationCalls = 0u;
    std::uint64_t uploadCalls = 0u;
    std::uint64_t downloadCalls = 0u;
    std::uint64_t metadataUploadCalls = 0u;
    std::uint64_t metadataCacheHits = 0u;
    std::uint64_t metadataBytesSkipped = 0u;
    int reusedAllocation = 0;
    double allocateSeconds = 0.0;
    double uploadSeconds = 0.0;
    double kernelSeconds = 0.0;
    double downloadSeconds = 0.0;
    double totalSeconds = 0.0;
};

struct CudaParticleStateSmokeResult {
    int pass = 0;
    std::uint64_t particles = 0u;
    std::uint64_t fluidParticles = 0u;
    std::uint64_t latentParticles = 0u;
    std::uint64_t inactiveParticles = 0u;
    int cycles = 0;
    double dvx = 0.0;
    double dvy = 0.0;
    double maxAbsX = 0.0;
    double maxAbsY = 0.0;
    double maxAbsVx = 0.0;
    double maxAbsVy = 0.0;
    double rmsV = 0.0;
    std::uint64_t velocityMismatches = 0u;
    CudaParticleStateDiagnostics diagnostics{};
};

bool cuda_particle_state_available();

class CudaParticleState {
public:
    CudaParticleState();
    ~CudaParticleState();

    CudaParticleState(const CudaParticleState&) = delete;
    CudaParticleState& operator=(const CudaParticleState&) = delete;
    CudaParticleState(CudaParticleState&&) noexcept;
    CudaParticleState& operator=(CudaParticleState&&) noexcept;

    void release();
    void ensure_capacity(std::uint64_t n, CudaParticleStateDiagnostics* diag = nullptr);

    void upload_all(const ParticleState& state, CudaParticleStateDiagnostics* diag = nullptr);
    // 0223: upload x/y/vx/vy every call but reuse cached mass/type/role
    // metadata when a safe host-side signature proves it has not changed.
    // This is intended for the persistent SRC+thermostat path where CPU
    // transport still updates positions/velocities every step, while metadata
    // changes less frequently. It is exact: changed metadata is reuploaded.
    void upload_kinematics_with_cached_metadata(const ParticleState& state,
                                                CudaParticleStateDiagnostics* diag = nullptr);
    void upload_positions(const ParticleState& state, CudaParticleStateDiagnostics* diag = nullptr);
    void upload_velocities(const ParticleState& state, CudaParticleStateDiagnostics* diag = nullptr);
    // 0243: role-only upload for the active resampling shadow benchmark.
    // It allocates the full device particle state but refreshes only role[].
    // This is safe only for paths that do not subsequently treat the whole
    // CudaParticleState as authoritative; non-touched x/y/v/m/type entries may
    // remain stale.
    void upload_roles(const ParticleState& state, CudaParticleStateDiagnostics* diag = nullptr);
    void upload_masses_and_roles(const ParticleState& state, CudaParticleStateDiagnostics* diag = nullptr);

    void download_velocities(ParticleState& state, CudaParticleStateDiagnostics* diag = nullptr) const;
    void download_all(ParticleState& state, CudaParticleStateDiagnostics* diag = nullptr) const;

    // 0314: compact host download for visualization/summary paths when the
    // device particle state contains a large inactive reservoir.  The role
    // array is scanned on the host, then only contiguous selected ranges are
    // copied for x/y/vx/vy/mass/type.  The optional roleCounts reports counts
    // over the full resident state.
    void download_role_filtered(ParticleState& state,
                                unsigned char keepRole,
                                ParticleRoleCounts* roleCounts = nullptr,
                                CudaParticleStateDiagnostics* diag = nullptr) const;

    CudaParticleDeviceView device_view();
    CudaParticleDeviceView device_view() const;

    std::uint64_t size() const;
    std::uint64_t capacity() const;
    std::uint64_t active_fluid_size() const;
    std::uint64_t allocated_bytes() const;

private:
    struct Impl;
    Impl* impl_ = nullptr;
};

// Smoke-only helper used by the 0218 validator. It deliberately mutates only
// fluid-particle velocities on device, so the host can check that role handling,
// upload-once, repeated device operations and final download are all coherent.
void cuda_particle_state_smoke_increment_fluid_velocities(CudaParticleState& gpuState,
                                                          int cycles,
                                                          double dvx,
                                                          double dvy,
                                                          int threadsPerBlock,
                                                          CudaParticleStateDiagnostics* diag = nullptr);

CudaParticleStateSmokeResult cuda_particle_state_smoke_roundtrip(const ParticleState& input,
                                                                 int cycles,
                                                                 double dvx,
                                                                 double dvy,
                                                                 int threadsPerBlock = 256,
                                                                 double tolerance = 1.0e-12);

} // namespace mpcd
