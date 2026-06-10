#include "cuda_streaming_piston_0247b.h"

#include "cuda_particle_state.h"
#include "cuda_shared_particle_state_0251.h"
#include "fluid_domain.h"

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

inline void check_cuda_0247b(cudaError_t err, const char* what) {
    if (err != cudaSuccess) {
        throw std::runtime_error(std::string("cuda_streaming_piston_0247b: ") + what + ": " + cudaGetErrorString(err));
    }
}

using Clock = std::chrono::steady_clock;
inline double elapsed_0247b(const Clock::time_point& a, const Clock::time_point& b) {
    return std::chrono::duration<double>(b - a).count();
}

bool env_truthy_0247b(const char* name) {
    const char* v = std::getenv(name);
    if (v == nullptr || *v == '\0') return false;
    const std::string s(v);
    return !(s == "0" || s == "false" || s == "FALSE" || s == "off" || s == "OFF" || s == "no" || s == "NO");
}

int env_int_0247b(const char* name, int defaultValue) {
    const char* v = std::getenv(name);
    if (v == nullptr || *v == '\0') return defaultValue;
    try {
        return std::max(1, std::stoi(std::string(v)));
    } catch (...) {
        return defaultValue;
    }
}

int encode_wall_mode_0247b(const std::string& mode) {
    if (mode == "solid" || mode == "specular") return 1;
    if (mode == "bounceback") return 2;
    return 0;
}

__device__ inline double wrap_periodic_device_0247b(double x, double L) {
    x = fmod(x, L);
    if (x < 0.0) x += L;
    if (x >= L) x -= L;
    return x;
}

__device__ inline double clamp_device_0247b(double x, double lo, double hi) {
    return fmin(fmax(x, lo), hi);
}

__device__ inline void apply_wall_reflection_device_0247b(
    const int mode,
    const double wallUx,
    const double wallUy,
    double& vx,
    double& vy)
{
    if (mode == 2) { // bounceback in the moving-wall frame
        vx = 2.0 * wallUx - vx;
        vy = 2.0 * wallUy - vy;
    } else { // solid/specular with y-normal wall
        (void)wallUx;
        vy = 2.0 * wallUy - vy;
    }
}

__global__ void piston_force_stream_kernel_0247b(
    const std::uint64_t n,
    double* __restrict__ x,
    double* __restrict__ y,
    double* __restrict__ vx,
    double* __restrict__ vy,
    const unsigned char* __restrict__ role,
    const unsigned char fluidRole,
    const double dt,
    const double Lx,
    const double yMin,
    const double yMax,
    const double bodyAx,
    const double bodyAy,
    const int bottomMode,
    const int topMode,
    const double wallUxBottom,
    const double wallUyBottom,
    const double wallUxTop,
    const double wallUyTop,
    unsigned long long* __restrict__ bottomHits,
    unsigned long long* __restrict__ topHits,
    int* __restrict__ maxYReflections,
    int* __restrict__ failureFlag)
{
    const std::uint64_t i = static_cast<std::uint64_t>(blockIdx.x) * static_cast<std::uint64_t>(blockDim.x) +
                            static_cast<std::uint64_t>(threadIdx.x);
    if (i >= n) return;
    if (role[i] != fluidRole) return;

    double vx1 = vx[i] + bodyAx * dt;
    double vy1 = vy[i] + bodyAy * dt;
    const double x1 = wrap_periodic_device_0247b(x[i] + vx1 * dt, Lx);
    double y1 = y[i] + vy1 * dt;

    int guard = 0;
    while (y1 < yMin || y1 > yMax) {
        if (++guard > 64) {
            atomicExch(failureFlag, 1);
            return;
        }
        if (y1 < yMin) {
            y1 = 2.0 * yMin - y1;
            atomicAdd(bottomHits, 1ULL);
            apply_wall_reflection_device_0247b(bottomMode, wallUxBottom, wallUyBottom, vx1, vy1);
        } else if (y1 > yMax) {
            y1 = 2.0 * yMax - y1;
            atomicAdd(topHits, 1ULL);
            apply_wall_reflection_device_0247b(topMode, wallUxTop, wallUyTop, vx1, vy1);
        }
    }
    if (guard > 0) {
        atomicMax(maxYReflections, guard);
    }

    x[i] = x1;
    y[i] = clamp_device_0247b(y1, yMin, yMax);
    vx[i] = vx1;
    vy[i] = vy1;
}

CudaParticleState& persistent_piston_streaming_state_0247b() {
    return cuda_shared_particle_state_0251();
}

} // namespace

bool cuda_piston_streaming_0247b_requested() {
    return env_truthy_0247b("MPCD_CUDA_STREAMING_PISTON_0247B");
}

bool cuda_piston_streaming_0247b_supported(const SimulationParams& params) {
    if (params.bcLeft != "periodic" || params.bcRight != "periodic") return false;
    if (encode_wall_mode_0247b(params.bcBottom) == 0 || encode_wall_mode_0247b(params.bcTop) == 0) return false;
    if (params.openBoundarySegmentsEnable || params.openBoundarySegmentCount != 0) return false;
    if (params.immersedSolidEnable) return false;
    if (!(params.Lx > 0.0) || !(params.Ly > 0.0) || !(params.dt >= 0.0)) return false;
    // 0247b is deliberately the moving-y-wall/piston subset. Keep x-domain
    // motion and y-bottom motion on CPU until they receive separate validation.
    if (params.fluidXMinVelocity != 0.0 || params.fluidXMaxVelocity != 0.0) return false;
    if (params.fluidYMinVelocity != 0.0) return false;
    if (params.taylorGreenForcingEnable) return false;
    return params.fluidYMaxVelocity != 0.0;
}

CudaPistonStreaming0247bDiagnostics try_apply_cuda_piston_streaming_0247b(
    ParticleState& state,
    const SimulationParams& params,
    std::uint64_t step)
{
    CudaPistonStreaming0247bDiagnostics diag{};
    diag.requested = cuda_piston_streaming_0247b_requested();
    diag.supported = cuda_piston_streaming_0247b_supported(params);
    const std::uint64_t nActiveFluid = active_fluid_count(state);
    diag.particles = nActiveFluid;
    if (!diag.requested || !diag.supported || nActiveFluid == 0u) {
        return diag;
    }
    if (!cuda_particle_state_available()) {
        return diag;
    }

    const double time = static_cast<double>(step) * params.dt;
    const FluidDomainBounds domain = make_fluid_domain_bounds(params, time);

    const auto t0 = Clock::now();
    CudaParticleStateDiagnostics particleDiag{};
    CudaParticleState& gpuState = persistent_piston_streaming_state_0247b();
    gpuState.upload_all(state, &particleDiag);
    const auto tAfterUpload = Clock::now();

    unsigned long long* dBottomHits = nullptr;
    unsigned long long* dTopHits = nullptr;
    int* dMaxY = nullptr;
    int* dFailure = nullptr;
    check_cuda_0247b(cudaMalloc(&dBottomHits, sizeof(unsigned long long)), "allocate bottom hits");
    check_cuda_0247b(cudaMalloc(&dTopHits, sizeof(unsigned long long)), "allocate top hits");
    check_cuda_0247b(cudaMalloc(&dMaxY, sizeof(int)), "allocate max y reflections");
    check_cuda_0247b(cudaMalloc(&dFailure, sizeof(int)), "allocate failure flag");
    check_cuda_0247b(cudaMemset(dBottomHits, 0, sizeof(unsigned long long)), "clear bottom hits");
    check_cuda_0247b(cudaMemset(dTopHits, 0, sizeof(unsigned long long)), "clear top hits");
    check_cuda_0247b(cudaMemset(dMaxY, 0, sizeof(int)), "clear max y reflections");
    check_cuda_0247b(cudaMemset(dFailure, 0, sizeof(int)), "clear failure flag");

    CudaParticleDeviceView view = gpuState.device_view();
    const int threads = env_int_0247b("MPCD_CUDA_STREAMING_PISTON_0247B_THREADS", 256);
    const std::uint64_t blocks64 = (nActiveFluid + static_cast<std::uint64_t>(threads) - 1u) /
                                   static_cast<std::uint64_t>(threads);
    if (blocks64 > static_cast<std::uint64_t>(2147483647)) {
        check_cuda_0247b(cudaFree(dBottomHits), "free bottom hits after grid-size failure");
        check_cuda_0247b(cudaFree(dTopHits), "free top hits after grid-size failure");
        check_cuda_0247b(cudaFree(dMaxY), "free max y after grid-size failure");
        check_cuda_0247b(cudaFree(dFailure), "free failure flag after grid-size failure");
        throw std::runtime_error("cuda_streaming_piston_0247b: grid too large for 1D launch");
    }

    const double wallUxBottom = params.wallVpUxBottom;
    const double wallUyBottom = domain.vyMin + params.wallVpUyBottom;
    const double wallUxTop = params.wallVpUxTop;
    const double wallUyTop = domain.vyMax + params.wallVpUyTop;

    piston_force_stream_kernel_0247b<<<static_cast<unsigned int>(blocks64), threads>>>(
        nActiveFluid, view.x, view.y, view.vx, view.vy, view.role,
        kParticleRoleFluid,
        params.dt, params.Lx,
        domain.yMin, domain.yMax,
        params.bodyAccelerationX, params.bodyAccelerationY,
        encode_wall_mode_0247b(params.bcBottom),
        encode_wall_mode_0247b(params.bcTop),
        wallUxBottom, wallUyBottom, wallUxTop, wallUyTop,
        dBottomHits, dTopHits, dMaxY, dFailure);
    check_cuda_0247b(cudaGetLastError(), "piston_force_stream_kernel_0247b launch");
    check_cuda_0247b(cudaDeviceSynchronize(), "piston_force_stream_kernel_0247b synchronize");
    const auto tAfterKernel = Clock::now();

    unsigned long long hBottomHits = 0ULL;
    unsigned long long hTopHits = 0ULL;
    int hMaxY = 0;
    int hFailure = 0;
    check_cuda_0247b(cudaMemcpy(&hBottomHits, dBottomHits, sizeof(unsigned long long), cudaMemcpyDeviceToHost), "copy bottom hits");
    check_cuda_0247b(cudaMemcpy(&hTopHits, dTopHits, sizeof(unsigned long long), cudaMemcpyDeviceToHost), "copy top hits");
    check_cuda_0247b(cudaMemcpy(&hMaxY, dMaxY, sizeof(int), cudaMemcpyDeviceToHost), "copy max y reflections");
    check_cuda_0247b(cudaMemcpy(&hFailure, dFailure, sizeof(int), cudaMemcpyDeviceToHost), "copy failure flag");
    check_cuda_0247b(cudaFree(dBottomHits), "free bottom hits");
    check_cuda_0247b(cudaFree(dTopHits), "free top hits");
    check_cuda_0247b(cudaFree(dMaxY), "free max y reflections");
    check_cuda_0247b(cudaFree(dFailure), "free failure flag");
    if (hFailure != 0) {
        throw std::runtime_error("cuda_streaming_piston_0247b: too many y-wall reflections in one step");
    }

    gpuState.download_all(state, &particleDiag);
    cuda_shared_particle_state_0251_mark_fresh("streaming_piston_0247b");
    const auto tAfterDownload = Clock::now();

    diag.handled = true;
    diag.applied = true;
    diag.fluidParticles = nActiveFluid;
    diag.hitsBottom = static_cast<std::uint64_t>(hBottomHits);
    diag.hitsTop = static_cast<std::uint64_t>(hTopHits);
    diag.maxYWallReflectionsPerParticle = hMaxY;
    diag.allocationCalls = particleDiag.allocationCalls;
    diag.uploadCalls = particleDiag.uploadCalls;
    diag.downloadCalls = particleDiag.downloadCalls;
    diag.uploadSeconds = elapsed_0247b(t0, tAfterUpload);
    diag.kernelSeconds = elapsed_0247b(tAfterUpload, tAfterKernel);
    diag.downloadSeconds = elapsed_0247b(tAfterKernel, tAfterDownload);
    diag.totalSeconds = elapsed_0247b(t0, tAfterDownload);
    return diag;
}

} // namespace mpcd
