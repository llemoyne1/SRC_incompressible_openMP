#include "cuda_streaming_periodic_0245.h"

#include "cuda_particle_state.h"
#include "cuda_shared_particle_state_0251.h"

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

inline void check_cuda_0245(cudaError_t err, const char* what) {
    if (err != cudaSuccess) {
        throw std::runtime_error(std::string("cuda_streaming_periodic_0245: ") + what + ": " + cudaGetErrorString(err));
    }
}

using Clock = std::chrono::steady_clock;
inline double elapsed_0245(const Clock::time_point& a, const Clock::time_point& b) {
    return std::chrono::duration<double>(b - a).count();
}

bool env_truthy_0245(const char* name) {
    const char* v = std::getenv(name);
    if (v == nullptr || *v == '\0') return false;
    const std::string s(v);
    return !(s == "0" || s == "false" || s == "FALSE" || s == "off" || s == "OFF" || s == "no" || s == "NO");
}

int env_int_0245(const char* name, int defaultValue) {
    const char* v = std::getenv(name);
    if (v == nullptr || *v == '\0') return defaultValue;
    try {
        return std::max(1, std::stoi(std::string(v)));
    } catch (...) {
        return defaultValue;
    }
}

bool is_periodic_pair_0245(const std::string& a, const std::string& b) {
    return a == "periodic" && b == "periodic";
}

__device__ inline double wrap_periodic_device_0245(double x, double L) {
    x = fmod(x, L);
    if (x < 0.0) x += L;
    if (x >= L) x -= L;
    return x;
}

__global__ void periodic_force_stream_kernel_0245(
    const std::uint64_t n,
    double* __restrict__ x,
    double* __restrict__ y,
    double* __restrict__ vx,
    double* __restrict__ vy,
    const unsigned char* __restrict__ role,
    const unsigned char fluidRole,
    const double dt,
    const double Lx,
    const double Ly,
    const double bodyAx,
    const double bodyAy,
    const int tgEnable,
    const double tgAmplitude,
    const int tgModeX,
    const int tgModeY)
{
    const std::uint64_t i = static_cast<std::uint64_t>(blockIdx.x) * static_cast<std::uint64_t>(blockDim.x) +
                            static_cast<std::uint64_t>(threadIdx.x);
    if (i >= n) return;
    if (role[i] != fluidRole) return;

    const double x0 = x[i];
    const double y0 = y[i];
    double ax = bodyAx;
    double ay = bodyAy;
    if (tgEnable && tgAmplitude > 0.0) {
        constexpr double pi = 3.141592653589793238462643383279502884;
        const double kx = 2.0 * pi * static_cast<double>(tgModeX) / Lx;
        const double ky = 2.0 * pi * static_cast<double>(tgModeY) / Ly;
        const double sx = sin(kx * x0);
        const double cx = cos(kx * x0);
        const double sy = sin(ky * y0);
        const double cy = cos(ky * y0);
        ax += tgAmplitude * sx * cy;
        ay += -tgAmplitude * cx * sy;
    }

    const double vx1 = vx[i] + ax * dt;
    const double vy1 = vy[i] + ay * dt;
    vx[i] = vx1;
    vy[i] = vy1;
    // 0245 keeps the CPU boundary operator active downstream.  For the strictly
    // periodic validation subset, wrapping here is exact and leaves the boundary
    // pass idempotent; it also avoids exposing downstream CPU code to stale
    // out-of-box positions if later diagnostics inspect the state between phases.
    x[i] = wrap_periodic_device_0245(x0 + vx1 * dt, Lx);
    y[i] = wrap_periodic_device_0245(y0 + vy1 * dt, Ly);
}

CudaParticleState& persistent_streaming_state_0245() {
    return cuda_shared_particle_state_0251();
}

} // namespace

bool cuda_periodic_streaming_0245_requested() {
    return env_truthy_0245("MPCD_CUDA_STREAMING_PERIODIC_0245");
}

bool cuda_periodic_streaming_0245_supported(const SimulationParams& params) {
    if (!is_periodic_pair_0245(params.bcLeft, params.bcRight)) return false;
    if (!is_periodic_pair_0245(params.bcBottom, params.bcTop)) return false;
    if (params.openBoundarySegmentsEnable || params.openBoundarySegmentCount != 0) return false;
    if (params.immersedSolidEnable) return false;
    if (!(params.Lx > 0.0) || !(params.Ly > 0.0) || !(params.dt >= 0.0)) return false;
    return true;
}

CudaPeriodicStreaming0245Diagnostics try_apply_cuda_periodic_streaming_0245(
    ParticleState& state,
    const SimulationParams& params,
    std::uint64_t step)
{
    (void)step;
    CudaPeriodicStreaming0245Diagnostics diag{};
    diag.requested = cuda_periodic_streaming_0245_requested();
    diag.supported = cuda_periodic_streaming_0245_supported(params);
    diag.particles = state.Np;
    if (!diag.requested || !diag.supported || state.Np == 0u) {
        return diag;
    }
    if (!cuda_particle_state_available()) {
        return diag;
    }

    const auto t0 = Clock::now();
    CudaParticleStateDiagnostics particleDiag{};
    CudaParticleState& gpuState = persistent_streaming_state_0245();
    gpuState.upload_all(state, &particleDiag);
    const auto tAfterUpload = Clock::now();

    CudaParticleDeviceView view = gpuState.device_view();
    const int threads = env_int_0245("MPCD_CUDA_STREAMING_PERIODIC_0245_THREADS", 256);
    const std::uint64_t blocks64 = (state.Np + static_cast<std::uint64_t>(threads) - 1u) /
                                   static_cast<std::uint64_t>(threads);
    if (blocks64 > static_cast<std::uint64_t>(2147483647)) {
        throw std::runtime_error("cuda_streaming_periodic_0245: grid too large for 1D launch");
    }
    periodic_force_stream_kernel_0245<<<static_cast<unsigned int>(blocks64), threads>>>(
        view.n, view.x, view.y, view.vx, view.vy, view.role,
        kParticleRoleFluid,
        params.dt, params.Lx, params.Ly,
        params.bodyAccelerationX, params.bodyAccelerationY,
        params.taylorGreenForcingEnable ? 1 : 0,
        params.taylorGreenForcingAmplitude,
        params.taylorGreenForcingModeX,
        params.taylorGreenForcingModeY);
    check_cuda_0245(cudaGetLastError(), "periodic_force_stream_kernel_0245 launch");
    check_cuda_0245(cudaDeviceSynchronize(), "periodic_force_stream_kernel_0245 synchronize");
    const auto tAfterKernel = Clock::now();

    gpuState.download_all(state, &particleDiag);
    cuda_shared_particle_state_0251_mark_fresh("streaming_periodic_0245");
    const auto tAfterDownload = Clock::now();

    diag.handled = true;
    diag.applied = true;
    diag.fluidParticles = 0u;
    for (std::size_t i = 0; i < static_cast<std::size_t>(state.Np); ++i) {
        if (is_fluid_particle(state, i)) ++diag.fluidParticles;
    }
    diag.allocationCalls = particleDiag.allocationCalls;
    diag.uploadCalls = particleDiag.uploadCalls;
    diag.downloadCalls = particleDiag.downloadCalls;
    diag.uploadSeconds = elapsed_0245(t0, tAfterUpload);
    diag.kernelSeconds = elapsed_0245(tAfterUpload, tAfterKernel);
    diag.downloadSeconds = elapsed_0245(tAfterKernel, tAfterDownload);
    diag.totalSeconds = elapsed_0245(t0, tAfterDownload);
    return diag;
}

} // namespace mpcd
