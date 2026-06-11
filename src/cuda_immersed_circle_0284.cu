#include "cuda_immersed_circle_0284.h"

#include "cuda_particle_state.h"
#include "cuda_shared_particle_state_0251.h"
#include "fluid_domain.h"
#include "immersed_solid.h"

#include <cuda_runtime.h>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdlib>
#include <cstdint>
#include <stdexcept>
#include <string>

namespace mpcd {
namespace {

inline void check_cuda_0284(cudaError_t err, const char* what) {
    if (err != cudaSuccess) {
        throw std::runtime_error(std::string("cuda_immersed_circle_0284: ") + what + ": " + cudaGetErrorString(err));
    }
}

using Clock = std::chrono::steady_clock;
inline double elapsed_0284(const Clock::time_point& a, const Clock::time_point& b) {
    return std::chrono::duration<double>(b - a).count();
}

bool env_truthy_0284(const char* name) {
    const char* v = std::getenv(name);
    if (v == nullptr || *v == '\0') return false;
    const std::string s(v);
    return !(s == "0" || s == "false" || s == "FALSE" ||
             s == "off" || s == "OFF" || s == "no" || s == "NO");
}

int env_int_0284(const char* name, int defaultValue) {
    const char* v = std::getenv(name);
    if (v == nullptr || *v == '\0') return defaultValue;
    try {
        return std::max(1, std::stoi(std::string(v)));
    } catch (...) {
        return defaultValue;
    }
}

__global__ void immersed_circle_reflection_kernel_0284(
    const std::uint64_t n,
    double* __restrict__ x,
    double* __restrict__ y,
    double* __restrict__ vx,
    double* __restrict__ vy,
    const unsigned char* __restrict__ role,
    const unsigned char fluidRole,
    const double cx,
    const double cy,
    const double R,
    const double eps,
    const double solidVx,
    const double solidVy,
    const double wallUx0,
    const double wallUy0,
    const double omega,
    unsigned long long* __restrict__ hits)
{
    const std::uint64_t i = static_cast<std::uint64_t>(blockIdx.x) * static_cast<std::uint64_t>(blockDim.x) +
                            static_cast<std::uint64_t>(threadIdx.x);
    if (i >= n) return;
    if (role[i] != fluidRole) return;

    const double dx = x[i] - cx;
    const double dy = y[i] - cy;
    const double r2 = dx * dx + dy * dy;
    const double R2 = R * R;
    if (!(r2 < R2)) return;

    double r = sqrt(fmax(r2, 0.0));
    double nx = 1.0;
    double ny = 0.0;
    if (r > 1.0e-14) {
        nx = dx / r;
        ny = dy / r;
    } else {
        r = 0.0;
    }

    // Match the CPU circle path in immersed_solid.cpp: radial mirror of any
    // particle found inside the solid after streaming.  This deliberately does
    // not use a segment/circle intersection, so CPU and CUDA equivalence remains
    // strict for the first validation step.
    const double rMirror = fmax(R + eps, 2.0 * R - r + eps);
    const double xNew = cx + rMirror * nx;
    const double yNew = cy + rMirror * ny;
    x[i] = xNew;
    y[i] = yNew;

    const double relx = xNew - cx;
    const double rely = yNew - cy;
    const double wallUx = solidVx + wallUx0 - omega * rely;
    const double wallUy = solidVy + wallUy0 + omega * relx;
    const double vrx = vx[i] - wallUx;
    const double vry = vy[i] - wallUy;
    const double vn = vrx * nx + vry * ny;
    vx[i] = wallUx + vrx - 2.0 * vn * nx;
    vy[i] = wallUy + vry - 2.0 * vn * ny;
    if (hits != nullptr) {
        atomicAdd(hits, 1ULL);
    }
}

CudaParticleState& persistent_immersed_circle_state_0284() {
    return cuda_shared_particle_state_0251();
}

bool cuda_immersed_circle_0284_resident_requested() {
    return env_truthy_0284("MPCD_CUDA_CLASSIC_SRC_SOLID_RESIDENT_0262") ||
           env_truthy_0284("MPCD_CUDA_CLASSIC_SRC_IO_FULLFACE_RESIDENT_0263") ||
           env_truthy_0284("MPCD_CUDA_CLASSIC_SRC_IO_SEGMENTED_RESIDENT_0264");
}

bool cuda_immersed_circle_0284_download_all_requested() {
    const char* v = std::getenv("MPCD_CUDA_IMMERSED_CIRCLE_0284_DOWNLOAD_ALL");
    if (v == nullptr || *v == '\0') {
        return !cuda_immersed_circle_0284_resident_requested();
    }
    const std::string flag(v);
    return !(flag == "0" || flag == "false" || flag == "FALSE" ||
             flag == "off" || flag == "OFF" || flag == "no" || flag == "NO");
}

bool cuda_immersed_circle_0330_fast_diagnostics_requested() {
    return env_truthy_0284("MPCD_CUDA_IMMERSED_CIRCLE_FAST_DIAGNOSTICS_0330");
}

} // namespace

bool cuda_immersed_circle_0284_requested() {
    return env_truthy_0284("MPCD_CUDA_IMMERSED_CIRCLE_0284");
}

bool cuda_immersed_circle_0284_supported(const SimulationParams& params) {
    if (!immersed_solid_enabled(params)) return false;
    if (immersed_solid_shape(params) != ImmersedSolidShape::Circle) return false;
    if (!(params.Lx > 0.0) || !(params.Ly > 0.0) || !(params.dt >= 0.0)) return false;
    if (!(params.immersedSolidR > 0.0)) return false;
    // 0284 validates the fixed-cylinder subset first. Moving/rotating circles
    // require a separate force/torque and boundary validation step.
    if (params.immersedSolidVx != 0.0 || params.immersedSolidVy != 0.0 || params.immersedSolidOmega != 0.0) return false;
    return true;
}

CudaImmersedCircle0284Diagnostics try_apply_cuda_immersed_circle_0284(
    ParticleState& state,
    const SimulationParams& params,
    const FluidDomainBounds& domain,
    double time)
{
    CudaImmersedCircle0284Diagnostics diag{};
    diag.requested = cuda_immersed_circle_0284_requested();
    diag.supported = cuda_immersed_circle_0284_supported(params);
    const std::uint64_t nActiveFluid = active_fluid_count(state);
    diag.particles = nActiveFluid;
    if (!diag.requested || !diag.supported || nActiveFluid == 0u) {
        return diag;
    }
    if (!cuda_particle_state_available()) {
        return diag;
    }

    double cx = 0.0, cy = 0.0;
    immersed_solid_circle_center(params, time, cx, cy);
    const double R = params.immersedSolidR;
    const double eps = 1.0e-12 * std::max(1.0, R);

    const auto t0 = Clock::now();
    CudaParticleStateDiagnostics particleDiag{};
    CudaParticleState& gpuState = persistent_immersed_circle_state_0284();
    const bool resident = cuda_immersed_circle_0284_resident_requested();
    const bool canReuseResident = resident && cuda_shared_particle_state_0251_is_fresh();
    if (!canReuseResident) {
        gpuState.upload_all(state, &particleDiag);
    }
    const auto tAfterUpload = Clock::now();

    const bool fastDiagnostics0330 = cuda_immersed_circle_0330_fast_diagnostics_requested();
    unsigned long long* dHits = nullptr;
    if (!fastDiagnostics0330) {
        check_cuda_0284(cudaMalloc(&dHits, sizeof(unsigned long long)), "allocate hit counter");
        check_cuda_0284(cudaMemset(dHits, 0, sizeof(unsigned long long)), "clear hit counter");
    }

    CudaParticleDeviceView view = gpuState.device_view();
    const int threads = env_int_0284("MPCD_CUDA_IMMERSED_CIRCLE_0284_THREADS", 256);
    const std::uint64_t blocks64 = (nActiveFluid + static_cast<std::uint64_t>(threads) - 1u) /
                                   static_cast<std::uint64_t>(threads);
    if (blocks64 > static_cast<std::uint64_t>(2147483647)) {
        if (dHits != nullptr) {
            check_cuda_0284(cudaFree(dHits), "free hit counter after grid-size failure");
        }
        throw std::runtime_error("cuda_immersed_circle_0284: grid too large for 1D launch");
    }

    immersed_circle_reflection_kernel_0284<<<static_cast<unsigned int>(blocks64), threads>>>(
        nActiveFluid, view.x, view.y, view.vx, view.vy, view.role,
        kParticleRoleFluid,
        cx, cy, R, eps,
        params.immersedSolidVx, params.immersedSolidVy,
        params.immersedSolidWallUx, params.immersedSolidWallUy,
        params.immersedSolidOmega,
        dHits);
    check_cuda_0284(cudaGetLastError(), "immersed_circle_reflection_kernel_0284 launch");
    check_cuda_0284(cudaDeviceSynchronize(), "immersed_circle_reflection_kernel_0284 synchronize");
    const auto tAfterKernel = Clock::now();

    unsigned long long hHits = 0ULL;
    if (!fastDiagnostics0330 && dHits != nullptr) {
        check_cuda_0284(cudaMemcpy(&hHits, dHits, sizeof(unsigned long long), cudaMemcpyDeviceToHost), "copy hit counter");
        check_cuda_0284(cudaFree(dHits), "free hit counter");
    }

    const bool downloadAll = cuda_immersed_circle_0284_download_all_requested();
    if (downloadAll || !resident) {
        gpuState.download_active_prefix(state, &particleDiag);
    }
    cuda_shared_particle_state_0251_mark_fresh("immersed_circle_0284");
    const auto tAfterDownload = Clock::now();

    diag.handled = true;
    diag.applied = true;
    diag.hits = static_cast<std::uint64_t>(hHits);
    diag.fluidParticles = nActiveFluid;
    diag.allocationCalls = particleDiag.allocationCalls;
    diag.uploadCalls = particleDiag.uploadCalls;
    diag.downloadCalls = particleDiag.downloadCalls;
    diag.uploadSeconds = elapsed_0284(t0, tAfterUpload);
    diag.kernelSeconds = elapsed_0284(tAfterUpload, tAfterKernel);
    diag.downloadSeconds = elapsed_0284(tAfterKernel, tAfterDownload);
    diag.totalSeconds = elapsed_0284(t0, tAfterDownload);
    return diag;
}

} // namespace mpcd
