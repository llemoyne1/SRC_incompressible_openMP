#include "cuda_immersed_rectangle_0247.h"

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
#include <initializer_list>
#include <stdexcept>
#include <string>

namespace mpcd {
namespace {

inline void check_cuda_0247(cudaError_t err, const char* what) {
    if (err != cudaSuccess) {
        throw std::runtime_error(std::string("cuda_immersed_rectangle_0247: ") + what + ": " + cudaGetErrorString(err));
    }
}

using Clock = std::chrono::steady_clock;
inline double elapsed_0247(const Clock::time_point& a, const Clock::time_point& b) {
    return std::chrono::duration<double>(b - a).count();
}

bool env_truthy_0247(const char* name) {
    const char* v = std::getenv(name);
    if (v == nullptr || *v == '\0') return false;
    const std::string s(v);
    return !(s == "0" || s == "false" || s == "FALSE" || s == "off" || s == "OFF" || s == "no" || s == "NO");
}

int env_int_0247(const char* name, int defaultValue) {
    const char* v = std::getenv(name);
    if (v == nullptr || *v == '\0') return defaultValue;
    try {
        return std::max(1, std::stoi(std::string(v)));
    } catch (...) {
        return defaultValue;
    }
}

__device__ inline double clamp_device_0247(double x, double lo, double hi) {
    return fmin(fmax(x, lo), hi);
}

struct FaceHitDevice0247 {
    int valid;
    double t;
    double x;
    double y;
    double nx;
    double ny;
};

__device__ inline void consider_face_device_0247(
    FaceHitDevice0247& best,
    const int enabled,
    const double t,
    const double xHit,
    const double yHit,
    const double nx,
    const double ny,
    const double xMin,
    const double xMax,
    const double yMin,
    const double yMax)
{
    if (!enabled) return;
    if (!(t >= -1.0e-12 && t <= 1.0 + 1.0e-12)) return;
    if (xHit < xMin - 1.0e-12 || xHit > xMax + 1.0e-12) return;
    if (yHit < yMin - 1.0e-12 || yHit > yMax + 1.0e-12) return;
    if (!best.valid || t < best.t) {
        best.valid = 1;
        best.t = clamp_device_0247(t, 0.0, 1.0);
        best.x = clamp_device_0247(xHit, xMin, xMax);
        best.y = clamp_device_0247(yHit, yMin, yMax);
        best.nx = nx;
        best.ny = ny;
    }
}

__device__ inline FaceHitDevice0247 rectangle_entry_face_device_0247(
    const double xPrev,
    const double yPrev,
    const double xNow,
    const double yNow,
    const double xMin,
    const double xMax,
    const double yMin,
    const double yMax,
    const int exposeLeft,
    const int exposeRight,
    const int exposeBottom,
    const int exposeTop)
{
    FaceHitDevice0247 best{0, 2.0, 0.0, 0.0, 1.0, 0.0};
    const double dx = xNow - xPrev;
    const double dy = yNow - yPrev;
    constexpr double tiny = 1.0e-14;

    if (fabs(dx) > tiny) {
        if (dx > 0.0) {
            const double t = (xMin - xPrev) / dx;
            consider_face_device_0247(best, exposeLeft, t, xMin, yPrev + t * dy, -1.0, 0.0,
                                      xMin, xMax, yMin, yMax);
        } else {
            const double t = (xMax - xPrev) / dx;
            consider_face_device_0247(best, exposeRight, t, xMax, yPrev + t * dy, 1.0, 0.0,
                                      xMin, xMax, yMin, yMax);
        }
    }
    if (fabs(dy) > tiny) {
        if (dy > 0.0) {
            const double t = (yMin - yPrev) / dy;
            consider_face_device_0247(best, exposeBottom, t, xPrev + t * dx, yMin, 0.0, -1.0,
                                      xMin, xMax, yMin, yMax);
        } else {
            const double t = (yMax - yPrev) / dy;
            consider_face_device_0247(best, exposeTop, t, xPrev + t * dx, yMax, 0.0, 1.0,
                                      xMin, xMax, yMin, yMax);
        }
    }
    return best;
}

__device__ inline void choose_nearest_face_device_0247(
    FaceHitDevice0247& out,
    const int enabled,
    const double dist,
    const double xHit,
    const double yHit,
    const double nx,
    const double ny)
{
    if (!enabled) return;
    if (!out.valid || dist < out.t) {
        out.valid = 1;
        out.t = dist;
        out.x = xHit;
        out.y = yHit;
        out.nx = nx;
        out.ny = ny;
    }
}

__device__ inline FaceHitDevice0247 nearest_rectangle_face_device_0247(
    const double x,
    const double y,
    const double xMin,
    const double xMax,
    const double yMin,
    const double yMax,
    const int exposeLeft,
    const int exposeRight,
    const int exposeBottom,
    const int exposeTop)
{
    FaceHitDevice0247 out{0, 0.0, 0.0, 0.0, 1.0, 0.0};
    choose_nearest_face_device_0247(out, exposeLeft, fabs(x - xMin), xMin, clamp_device_0247(y, yMin, yMax), -1.0, 0.0);
    choose_nearest_face_device_0247(out, exposeRight, fabs(xMax - x), xMax, clamp_device_0247(y, yMin, yMax), 1.0, 0.0);
    choose_nearest_face_device_0247(out, exposeBottom, fabs(y - yMin), clamp_device_0247(x, xMin, xMax), yMin, 0.0, -1.0);
    choose_nearest_face_device_0247(out, exposeTop, fabs(yMax - y), clamp_device_0247(x, xMin, xMax), yMax, 0.0, 1.0);
    return out;
}

__global__ void immersed_rectangle_reflection_kernel_0247(
    const std::uint64_t n,
    double* __restrict__ x,
    double* __restrict__ y,
    double* __restrict__ vx,
    double* __restrict__ vy,
    const unsigned char* __restrict__ role,
    const unsigned char fluidRole,
    const double dt,
    const double xMin,
    const double xMax,
    const double yMin,
    const double yMax,
    const int exposeLeft,
    const int exposeRight,
    const int exposeBottom,
    const int exposeTop,
    const double eps,
    const double wallUx,
    const double wallUy,
    unsigned long long* __restrict__ hits)
{
    const std::uint64_t i = static_cast<std::uint64_t>(blockIdx.x) * static_cast<std::uint64_t>(blockDim.x) +
                            static_cast<std::uint64_t>(threadIdx.x);
    if (i >= n) return;
    if (role[i] != fluidRole) return;

    const double xNow = x[i];
    const double yNow = y[i];
    if (!(xNow >= xMin && xNow <= xMax && yNow >= yMin && yNow <= yMax)) return;

    const double xPrev = xNow - vx[i] * dt;
    const double yPrev = yNow - vy[i] * dt;
    FaceHitDevice0247 face = rectangle_entry_face_device_0247(xPrev, yPrev, xNow, yNow,
                                                              xMin, xMax, yMin, yMax,
                                                              exposeLeft, exposeRight, exposeBottom, exposeTop);
    if (!face.valid) {
        face = nearest_rectangle_face_device_0247(xNow, yNow, xMin, xMax, yMin, yMax,
                                                  exposeLeft, exposeRight, exposeBottom, exposeTop);
    }
    if (!face.valid) return;

    const double dxSeg = xNow - xPrev;
    const double dySeg = yNow - yPrev;
    const double remainX = (1.0 - face.t) * dxSeg;
    const double remainY = (1.0 - face.t) * dySeg;
    const double remainN = remainX * face.nx + remainY * face.ny;
    x[i] = face.x + remainX - 2.0 * remainN * face.nx + eps * face.nx;
    y[i] = face.y + remainY - 2.0 * remainN * face.ny + eps * face.ny;

    const double vrx = vx[i] - wallUx;
    const double vry = vy[i] - wallUy;
    const double vn = vrx * face.nx + vry * face.ny;
    vx[i] = wallUx + vrx - 2.0 * vn * face.nx;
    vy[i] = wallUy + vry - 2.0 * vn * face.ny;
    atomicAdd(hits, 1ULL);
}

CudaParticleState& persistent_immersed_rectangle_state_0247() {
    return cuda_shared_particle_state_0251();
}

} // namespace

bool cuda_immersed_rectangle_0247_requested() {
    return env_truthy_0247("MPCD_CUDA_IMMERSED_RECTANGLE_0247");
}

bool cuda_immersed_rectangle_0247_supported(const SimulationParams& params) {
    if (!immersed_solid_enabled(params)) return false;
    if (immersed_solid_shape(params) != ImmersedSolidShape::Rectangle) return false;
    if (!(params.Lx > 0.0) || !(params.Ly > 0.0) || !(params.dt >= 0.0)) return false;
    // 0247a is deliberately restricted to the static axis-aligned rectangle used
    // by open_rect_obstacle_full. Moving/rotating solid bodies remain CPU until
    // their own validation step.
    if (params.immersedSolidVx != 0.0 || params.immersedSolidVy != 0.0 || params.immersedSolidOmega != 0.0) return false;
    if (params.immersedSolidXMax <= params.immersedSolidXMin || params.immersedSolidYMax <= params.immersedSolidYMin) return false;
    return true;
}

CudaImmersedRectangle0247Diagnostics try_apply_cuda_immersed_rectangle_0247(
    ParticleState& state,
    const SimulationParams& params,
    const FluidDomainBounds& domain,
    double time)
{
    CudaImmersedRectangle0247Diagnostics diag{};
    diag.requested = cuda_immersed_rectangle_0247_requested();
    diag.supported = cuda_immersed_rectangle_0247_supported(params);
    diag.particles = state.Np;
    if (!diag.requested || !diag.supported || state.Np == 0u) {
        return diag;
    }
    if (!cuda_particle_state_available()) {
        return diag;
    }

    double xMin = 0.0, xMax = 0.0, yMin = 0.0, yMax = 0.0;
    immersed_solid_rectangle_bounds(params, time, xMin, xMax, yMin, yMax);
    const int exposeLeft = xMin > domain.xMin + 1.0e-12 ? 1 : 0;
    const int exposeRight = xMax < domain.xMax - 1.0e-12 ? 1 : 0;
    const int exposeBottom = yMin > domain.yMin + 1.0e-12 ? 1 : 0;
    const int exposeTop = yMax < domain.yMax - 1.0e-12 ? 1 : 0;
    const double epsBase = 1.0e-12 * std::max({1.0, domain.xMax - domain.xMin, domain.yMax - domain.yMin});
    const double eps = epsBase;
    const double wallUx = params.immersedSolidVx + params.immersedSolidWallUx;
    const double wallUy = params.immersedSolidVy + params.immersedSolidWallUy;

    const auto t0 = Clock::now();
    CudaParticleStateDiagnostics particleDiag{};
    CudaParticleState& gpuState = persistent_immersed_rectangle_state_0247();
    gpuState.upload_all(state, &particleDiag);
    const auto tAfterUpload = Clock::now();

    unsigned long long* dHits = nullptr;
    check_cuda_0247(cudaMalloc(&dHits, sizeof(unsigned long long)), "allocate hit counter");
    check_cuda_0247(cudaMemset(dHits, 0, sizeof(unsigned long long)), "clear hit counter");

    CudaParticleDeviceView view = gpuState.device_view();
    const int threads = env_int_0247("MPCD_CUDA_IMMERSED_RECTANGLE_0247_THREADS", 256);
    const std::uint64_t blocks64 = (state.Np + static_cast<std::uint64_t>(threads) - 1u) /
                                   static_cast<std::uint64_t>(threads);
    if (blocks64 > static_cast<std::uint64_t>(2147483647)) {
        check_cuda_0247(cudaFree(dHits), "free hit counter after grid-size failure");
        throw std::runtime_error("cuda_immersed_rectangle_0247: grid too large for 1D launch");
    }

    immersed_rectangle_reflection_kernel_0247<<<static_cast<unsigned int>(blocks64), threads>>>(
        view.n, view.x, view.y, view.vx, view.vy, view.role,
        kParticleRoleFluid,
        params.dt,
        xMin, xMax, yMin, yMax,
        exposeLeft, exposeRight, exposeBottom, exposeTop,
        eps,
        wallUx, wallUy,
        dHits);
    check_cuda_0247(cudaGetLastError(), "immersed_rectangle_reflection_kernel_0247 launch");
    check_cuda_0247(cudaDeviceSynchronize(), "immersed_rectangle_reflection_kernel_0247 synchronize");
    const auto tAfterKernel = Clock::now();

    unsigned long long hHits = 0ULL;
    check_cuda_0247(cudaMemcpy(&hHits, dHits, sizeof(unsigned long long), cudaMemcpyDeviceToHost), "copy hit counter");
    check_cuda_0247(cudaFree(dHits), "free hit counter");

    gpuState.download_all(state, &particleDiag);
    cuda_shared_particle_state_0251_mark_fresh("immersed_rectangle_0247");
    const auto tAfterDownload = Clock::now();

    diag.handled = true;
    diag.applied = true;
    diag.hits = static_cast<std::uint64_t>(hHits);
    diag.fluidParticles = 0u;
    for (std::size_t i = 0; i < static_cast<std::size_t>(state.Np); ++i) {
        if (is_fluid_particle(state, i)) ++diag.fluidParticles;
    }
    diag.allocationCalls = particleDiag.allocationCalls;
    diag.uploadCalls = particleDiag.uploadCalls;
    diag.downloadCalls = particleDiag.downloadCalls;
    diag.uploadSeconds = elapsed_0247(t0, tAfterUpload);
    diag.kernelSeconds = elapsed_0247(tAfterUpload, tAfterKernel);
    diag.downloadSeconds = elapsed_0247(tAfterKernel, tAfterDownload);
    diag.totalSeconds = elapsed_0247(t0, tAfterDownload);
    return diag;
}

} // namespace mpcd
