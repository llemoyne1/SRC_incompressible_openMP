#include "cuda_streaming_wall_simple_0246.h"

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

inline void check_cuda_0246(cudaError_t err, const char* what) {
    if (err != cudaSuccess) {
        throw std::runtime_error(std::string("cuda_streaming_wall_simple_0246: ") + what + ": " + cudaGetErrorString(err));
    }
}

using Clock = std::chrono::steady_clock;
inline double elapsed_0246(const Clock::time_point& a, const Clock::time_point& b) {
    return std::chrono::duration<double>(b - a).count();
}

bool env_truthy_0246(const char* name) {
    const char* v = std::getenv(name);
    if (v == nullptr || *v == '\0') return false;
    const std::string s(v);
    return !(s == "0" || s == "false" || s == "FALSE" || s == "off" || s == "OFF" || s == "no" || s == "NO");
}

int env_int_0246(const char* name, int defaultValue) {
    const char* v = std::getenv(name);
    if (v == nullptr || *v == '\0') return defaultValue;
    try {
        return std::max(1, std::stoi(std::string(v)));
    } catch (...) {
        return defaultValue;
    }
}

bool is_periodic_pair_0246(const std::string& a, const std::string& b) {
    return a == "periodic" && b == "periodic";
}

bool is_wall_mode_0246(const std::string& mode) {
    return mode == "solid" || mode == "specular" || mode == "bounceback";
}

bool closed_box_0493x1_requested() {
    return env_truthy_0246("MPCD_CUDA_WALL_SIMPLE_CLOSED_BOX_0493X1");
}

int encode_wall_mode_0246(const std::string& mode) {
    if (mode == "solid" || mode == "specular") return 1;
    if (mode == "bounceback") return 2;
    return 0;
}

__device__ inline double wrap_periodic_device_0246(double x, double L) {
    x = fmod(x, L);
    if (x < 0.0) x += L;
    if (x >= L) x -= L;
    return x;
}

__device__ inline double clamp_device_0246(double x, double lo, double hi) {
    return fmin(fmax(x, lo), hi);
}

__device__ inline void apply_wall_reflection_device_0246(
    const int mode,
    const int normalIsX,
    const double wallUx,
    const double wallUy,
    double& vx,
    double& vy)
{
    if (mode == 2) { // bounceback in the wall frame
        vx = 2.0 * wallUx - vx;
        vy = 2.0 * wallUy - vy;
    } else if (normalIsX) { // solid/specular with x-normal wall
        vx = 2.0 * wallUx - vx;
    } else { // solid/specular with y-normal wall
        vy = 2.0 * wallUy - vy;
    }
}

__global__ void wall_simple_force_stream_kernel_0246(
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
    const int periodicX,
    const double xMin,
    const double xMax,
    const double yMin,
    const double yMax,
    const double bodyAx,
    const double bodyAy,
    const int tgEnable,
    const double tgAmplitude,
    const int tgModeX,
    const int tgModeY,
    const int leftMode,
    const int rightMode,
    const int bottomMode,
    const int topMode,
    const double wallUxLeft,
    const double wallUyLeft,
    const double wallUxRight,
    const double wallUyRight,
    const double wallUxBottom,
    const double wallUyBottom,
    const double wallUxTop,
    const double wallUyTop,
    unsigned long long* __restrict__ leftHits,
    unsigned long long* __restrict__ rightHits,
    unsigned long long* __restrict__ bottomHits,
    unsigned long long* __restrict__ topHits,
    int* __restrict__ maxXReflections,
    int* __restrict__ maxYReflections,
    int* __restrict__ failureFlag)
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

    double vx1 = vx[i] + ax * dt;
    double vy1 = vy[i] + ay * dt;
    double x1 = x0 + vx1 * dt;
    double y1 = y0 + vy1 * dt;

    int guardX = 0;
    if (periodicX) {
        x1 = wrap_periodic_device_0246(x1, Lx);
    } else {
        while (x1 < xMin || x1 > xMax) {
            if (++guardX > 64) {
                if (failureFlag != nullptr) atomicExch(failureFlag, 1);
                return;
            }
            if (x1 < xMin) {
                x1 = 2.0 * xMin - x1;
                if (leftHits != nullptr) atomicAdd(leftHits, 1ULL);
                apply_wall_reflection_device_0246(
                    leftMode, 1, wallUxLeft, wallUyLeft, vx1, vy1);
            } else if (x1 > xMax) {
                x1 = 2.0 * xMax - x1;
                if (rightHits != nullptr) atomicAdd(rightHits, 1ULL);
                apply_wall_reflection_device_0246(
                    rightMode, 1, wallUxRight, wallUyRight, vx1, vy1);
            }
        }
        if (guardX > 0 && maxXReflections != nullptr) {
            atomicMax(maxXReflections, guardX);
        }
    }

    int guardY = 0;
    while (y1 < yMin || y1 > yMax) {
        if (++guardY > 64) {
            if (failureFlag != nullptr) atomicExch(failureFlag, 1);
            return;
        }
        if (y1 < yMin) {
            y1 = 2.0 * yMin - y1;
            if (bottomHits != nullptr) atomicAdd(bottomHits, 1ULL);
            apply_wall_reflection_device_0246(
                bottomMode, 0, wallUxBottom, wallUyBottom, vx1, vy1);
        } else if (y1 > yMax) {
            y1 = 2.0 * yMax - y1;
            if (topHits != nullptr) atomicAdd(topHits, 1ULL);
            apply_wall_reflection_device_0246(
                topMode, 0, wallUxTop, wallUyTop, vx1, vy1);
        }
    }
    if (guardY > 0 && maxYReflections != nullptr) {
        atomicMax(maxYReflections, guardY);
    }

    x[i] = periodicX ? x1 : clamp_device_0246(x1, xMin, xMax);
    y[i] = clamp_device_0246(y1, yMin, yMax);
    vx[i] = vx1;
    vy[i] = vy1;
}

CudaParticleState& persistent_streaming_state_0246() {
    return cuda_shared_particle_state_0251();
}

} // namespace

bool cuda_wall_simple_streaming_0246_requested() {
    return env_truthy_0246("MPCD_CUDA_STREAMING_WALL_SIMPLE_0246");
}

bool cuda_wall_circle_resident_0318_requested() {
    return env_truthy_0246("MPCD_CUDA_CLASSIC_SRC_WALL_CIRCLE_RESIDENT_0318");
}

bool cuda_wall_simple_streaming_0246_resident_0261_requested() {
    return env_truthy_0246("MPCD_CUDA_CLASSIC_SRC_WALL_RESIDENT_0261") ||
           cuda_wall_circle_resident_0318_requested();
}

bool cuda_wall_simple_streaming_0246_download_all_requested_0261() {
    const char* v = std::getenv("MPCD_CUDA_STREAMING_WALL_SIMPLE_0246_DOWNLOAD_ALL");
    if (v == nullptr || *v == '\0') {
        return !cuda_wall_simple_streaming_0246_resident_0261_requested();
    }
    const std::string s(v);
    return !(s == "0" || s == "false" || s == "FALSE" || s == "off" || s == "OFF" || s == "no" || s == "NO");
}

bool cuda_wall_simple_streaming_0271_async_resident_enabled(const bool resident0261, const bool downloadAll) {
    if (!resident0261 || downloadAll) return false;
    return env_truthy_0246("MPCD_CUDA_CLASSIC_SRC_RESIDENT_0271_ASYNC_STREAM") &&
           !env_truthy_0246("MPCD_CUDA_CLASSIC_SRC_RESIDENT_0271_DISABLE_ASYNC_STREAM");
}

bool cuda_wall_simple_streaming_0271_fast_diagnostics_enabled(const bool asyncResident0271) {
    if (!asyncResident0271) return false;
    return env_truthy_0246("MPCD_CUDA_CLASSIC_SRC_WALL_RESIDENT_0271_FAST_DIAGNOSTICS") &&
           !env_truthy_0246("MPCD_CUDA_CLASSIC_SRC_WALL_RESIDENT_0271_DISABLE_FAST_DIAGNOSTICS");
}

bool cuda_wall_simple_streaming_0246_supported(const SimulationParams& params) {
    const bool periodicX = is_periodic_pair_0246(params.bcLeft, params.bcRight);
    const bool boundedX = closed_box_0493x1_requested() &&
        is_wall_mode_0246(params.bcLeft) && is_wall_mode_0246(params.bcRight);
    if (!periodicX && !boundedX) return false;
    if (!is_wall_mode_0246(params.bcBottom) || !is_wall_mode_0246(params.bcTop)) return false;
    // The first closed-box subset deliberately excludes bounceback corners.
    // Solid/specular faces use normal reflection; no-slip is supplied by the
    // existing virtual-particle collision coupling on faces declared solid.
    if (boundedX && (params.bcLeft == "bounceback" || params.bcRight == "bounceback" ||
                     params.bcBottom == "bounceback" || params.bcTop == "bounceback")) return false;
    if (params.openBoundarySegmentsEnable || params.openBoundarySegmentCount != 0) return false;
    // 0246 remains a wall-simple path only.  The wall+immersed-circle
    // coupling through 0318 is quarantined: VK validation showed that
    // 0246+circle changes the momentum evolution even when wall/circle hits
    // are present.  Use the validated non-0318 path for immersed solids.
    if (params.immersedSolidEnable) return false;
    if (!(params.Lx > 0.0) || !(params.Ly > 0.0) || !(params.dt >= 0.0)) return false;
    // 0246 remains a static-domain wall-simple path: the legacy periodic-x
    // channel and the opt-in four-face closed box. Moving pistons and active-
    // domain walls remain on their dedicated paths.
    if (params.fluidXMinVelocity != 0.0 || params.fluidXMaxVelocity != 0.0 ||
        params.fluidYMinVelocity != 0.0 || params.fluidYMaxVelocity != 0.0) return false;
    return true;
}

CudaWallSimpleStreaming0246Diagnostics try_apply_cuda_wall_simple_streaming_0246(
    ParticleState& state,
    const SimulationParams& params,
    std::uint64_t step)
{
    CudaWallSimpleStreaming0246Diagnostics diag{};
    diag.requested = cuda_wall_simple_streaming_0246_requested();
    diag.supported = cuda_wall_simple_streaming_0246_supported(params);
    const std::uint64_t nActiveFluid = active_fluid_count(state);
    diag.particles = state.Np;
    if (!diag.requested || !diag.supported || state.Np == 0u) {
        return diag;
    }
    if (!cuda_particle_state_available()) {
        return diag;
    }

    const double time = static_cast<double>(step) * params.dt;
    const FluidDomainBounds domain = make_fluid_domain_bounds(params, time);

    const auto t0 = Clock::now();
    CudaParticleStateDiagnostics particleDiag{};
    CudaParticleState& gpuState = persistent_streaming_state_0246();
    const bool resident0261 = cuda_wall_simple_streaming_0246_resident_0261_requested();
    const bool downloadAll = cuda_wall_simple_streaming_0246_download_all_requested_0261();
    const bool asyncResident0271 = cuda_wall_simple_streaming_0271_async_resident_enabled(resident0261, downloadAll);
    const bool fastDiagnostics0271 = cuda_wall_simple_streaming_0271_fast_diagnostics_enabled(asyncResident0271);
    const bool canReuseResident = resident0261 && cuda_shared_particle_state_0251_is_fresh();
    if (!canReuseResident) {
        gpuState.upload_all(state, &particleDiag);
    }
    const auto tAfterUpload = Clock::now();

    unsigned long long* dLeftHits = nullptr;
    unsigned long long* dRightHits = nullptr;
    unsigned long long* dBottomHits = nullptr;
    unsigned long long* dTopHits = nullptr;
    int* dMaxX = nullptr;
    int* dMaxY = nullptr;
    int* dFailure = nullptr;
    if (!fastDiagnostics0271) {
        check_cuda_0246(cudaMalloc(&dLeftHits, sizeof(unsigned long long)), "allocate left hits");
        check_cuda_0246(cudaMalloc(&dRightHits, sizeof(unsigned long long)), "allocate right hits");
        check_cuda_0246(cudaMalloc(&dBottomHits, sizeof(unsigned long long)), "allocate bottom hits");
        check_cuda_0246(cudaMalloc(&dTopHits, sizeof(unsigned long long)), "allocate top hits");
        check_cuda_0246(cudaMalloc(&dMaxX, sizeof(int)), "allocate max x reflections");
        check_cuda_0246(cudaMalloc(&dMaxY, sizeof(int)), "allocate max y reflections");
        check_cuda_0246(cudaMalloc(&dFailure, sizeof(int)), "allocate failure flag");
        check_cuda_0246(cudaMemset(dLeftHits, 0, sizeof(unsigned long long)), "clear left hits");
        check_cuda_0246(cudaMemset(dRightHits, 0, sizeof(unsigned long long)), "clear right hits");
        check_cuda_0246(cudaMemset(dBottomHits, 0, sizeof(unsigned long long)), "clear bottom hits");
        check_cuda_0246(cudaMemset(dTopHits, 0, sizeof(unsigned long long)), "clear top hits");
        check_cuda_0246(cudaMemset(dMaxX, 0, sizeof(int)), "clear max x reflections");
        check_cuda_0246(cudaMemset(dMaxY, 0, sizeof(int)), "clear max y reflections");
        check_cuda_0246(cudaMemset(dFailure, 0, sizeof(int)), "clear failure flag");
    }

    CudaParticleDeviceView view = gpuState.device_view();
    const int threads = env_int_0246("MPCD_CUDA_STREAMING_WALL_SIMPLE_0246_THREADS", 256);
    const std::uint64_t blocks64 = (state.Np + static_cast<std::uint64_t>(threads) - 1u) /
                                   static_cast<std::uint64_t>(threads);
    if (blocks64 > static_cast<std::uint64_t>(2147483647)) {
        throw std::runtime_error("cuda_streaming_wall_simple_0246: grid too large for 1D launch");
    }

    const bool periodicX = is_periodic_pair_0246(params.bcLeft, params.bcRight);
    const double wallUxLeft = domain.vxMin + params.wallVpUxLeft;
    const double wallUyLeft = params.wallVpUyLeft;
    const double wallUxRight = domain.vxMax + params.wallVpUxRight;
    const double wallUyRight = params.wallVpUyRight;
    const double wallUxBottom = params.wallVpUxBottom;
    const double wallUyBottom = domain.vyMin + params.wallVpUyBottom;
    const double wallUxTop = params.wallVpUxTop;
    const double wallUyTop = domain.vyMax + params.wallVpUyTop;

    wall_simple_force_stream_kernel_0246<<<static_cast<unsigned int>(blocks64), threads>>>(
        view.n, view.x, view.y, view.vx, view.vy, view.role,
        kParticleRoleFluid,
        params.dt, params.Lx, params.Ly,
        periodicX ? 1 : 0, domain.xMin, domain.xMax, domain.yMin, domain.yMax,
        params.bodyAccelerationX, params.bodyAccelerationY,
        params.taylorGreenForcingEnable ? 1 : 0,
        params.taylorGreenForcingAmplitude,
        params.taylorGreenForcingModeX,
        params.taylorGreenForcingModeY,
        encode_wall_mode_0246(params.bcLeft),
        encode_wall_mode_0246(params.bcRight),
        encode_wall_mode_0246(params.bcBottom),
        encode_wall_mode_0246(params.bcTop),
        wallUxLeft, wallUyLeft, wallUxRight, wallUyRight,
        wallUxBottom, wallUyBottom, wallUxTop, wallUyTop,
        dLeftHits, dRightHits, dBottomHits, dTopHits, dMaxX, dMaxY, dFailure);
    check_cuda_0246(cudaGetLastError(), "wall_simple_force_stream_kernel_0246 launch");
    if (!asyncResident0271) {
        check_cuda_0246(cudaDeviceSynchronize(), "wall_simple_force_stream_kernel_0246 synchronize");
    }
    const auto tAfterKernel = Clock::now();

    unsigned long long hLeftHits = 0ULL;
    unsigned long long hRightHits = 0ULL;
    unsigned long long hBottomHits = 0ULL;
    unsigned long long hTopHits = 0ULL;
    int hMaxX = 0;
    int hMaxY = 0;
    int hFailure = 0;
    if (!fastDiagnostics0271) {
        check_cuda_0246(cudaMemcpy(&hLeftHits, dLeftHits, sizeof(unsigned long long), cudaMemcpyDeviceToHost), "copy left hits");
        check_cuda_0246(cudaMemcpy(&hRightHits, dRightHits, sizeof(unsigned long long), cudaMemcpyDeviceToHost), "copy right hits");
        check_cuda_0246(cudaMemcpy(&hBottomHits, dBottomHits, sizeof(unsigned long long), cudaMemcpyDeviceToHost), "copy bottom hits");
        check_cuda_0246(cudaMemcpy(&hTopHits, dTopHits, sizeof(unsigned long long), cudaMemcpyDeviceToHost), "copy top hits");
        check_cuda_0246(cudaMemcpy(&hMaxX, dMaxX, sizeof(int), cudaMemcpyDeviceToHost), "copy max x reflections");
        check_cuda_0246(cudaMemcpy(&hMaxY, dMaxY, sizeof(int), cudaMemcpyDeviceToHost), "copy max y reflections");
        check_cuda_0246(cudaMemcpy(&hFailure, dFailure, sizeof(int), cudaMemcpyDeviceToHost), "copy failure flag");
        check_cuda_0246(cudaFree(dLeftHits), "free left hits");
        check_cuda_0246(cudaFree(dRightHits), "free right hits");
        check_cuda_0246(cudaFree(dBottomHits), "free bottom hits");
        check_cuda_0246(cudaFree(dTopHits), "free top hits");
        check_cuda_0246(cudaFree(dMaxX), "free max x reflections");
        check_cuda_0246(cudaFree(dMaxY), "free max y reflections");
        check_cuda_0246(cudaFree(dFailure), "free failure flag");
        if (hFailure != 0) {
            throw std::runtime_error("cuda_streaming_wall_simple_0246: too many wall reflections in one step");
        }
    }

    if (downloadAll) {
        // 0315k: the validated nonresident wall-simple path still downloads
        // after streaming so the downstream CPU boundary/collision wrappers see
        // a coherent host state.  With the global active-prefix invariant that
        // mirror only needs [0,NactiveFluid); copying the inactive reservoir is
        // pure overhead and was the dominant Poiseuille scaling term.
        if (env_truthy_0246("MPCD_CUDA_STREAMING_WALL_SIMPLE_DOWNLOAD_ALL_LEGACY_0315K")) {
            gpuState.download_all(state, &particleDiag);
        } else {
            gpuState.download_active_prefix(state, &particleDiag);
        }
    }
    cuda_shared_particle_state_0251_mark_fresh("streaming_wall_simple_0246");
    const auto tAfterDownload = Clock::now();

    diag.handled = true;
    diag.applied = true;
    diag.fluidParticles = nActiveFluid;
    diag.hitsLeft = static_cast<std::uint64_t>(hLeftHits);
    diag.hitsRight = static_cast<std::uint64_t>(hRightHits);
    diag.hitsBottom = static_cast<std::uint64_t>(hBottomHits);
    diag.hitsTop = static_cast<std::uint64_t>(hTopHits);
    diag.maxXWallReflectionsPerParticle = hMaxX;
    diag.maxYWallReflectionsPerParticle = hMaxY;
    diag.allocationCalls = particleDiag.allocationCalls;
    diag.uploadCalls = particleDiag.uploadCalls;
    diag.downloadCalls = particleDiag.downloadCalls;
    diag.uploadSeconds = elapsed_0246(t0, tAfterUpload);
    diag.kernelSeconds = elapsed_0246(tAfterUpload, tAfterKernel);
    diag.downloadSeconds = elapsed_0246(tAfterKernel, tAfterDownload);
    diag.totalSeconds = elapsed_0246(t0, tAfterDownload);
    return diag;
}

} // namespace mpcd
