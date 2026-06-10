#include "cuda_inlet_outlet_fullface_0249a.h"

#include "cuda_particle_state.h"
#include "cuda_shared_particle_state_0251.h"

#include <cuda_runtime.h>

#include <algorithm>
#include <chrono>
#include <cstdlib>
#include <cstdint>
#include <stdexcept>
#include <string>

namespace mpcd {
namespace {

inline void check_cuda_0249a(cudaError_t err, const char* what) {
    if (err != cudaSuccess) {
        throw std::runtime_error(std::string("cuda_inlet_outlet_fullface_0249a: ") + what + ": " + cudaGetErrorString(err));
    }
}

using Clock = std::chrono::steady_clock;
inline double elapsed_0249a(const Clock::time_point& a, const Clock::time_point& b) {
    return std::chrono::duration<double>(b - a).count();
}

bool env_truthy_0249a(const char* name) {
    const char* v = std::getenv(name);
    if (v == nullptr || *v == '\0') return false;
    const std::string s(v);
    return !(s == "0" || s == "false" || s == "FALSE" || s == "off" || s == "OFF" || s == "no" || s == "NO");
}

int env_int_0249a(const char* name, int defaultValue) {
    const char* v = std::getenv(name);
    if (v == nullptr || *v == '\0') return defaultValue;
    try {
        return std::max(1, std::stoi(std::string(v)));
    } catch (...) {
        return defaultValue;
    }
}

std::string normalized_inlet_reservoir_mode_0249a(const SimulationParams& params) {
    std::string mode = params.inletReservoirMode;
    std::replace(mode.begin(), mode.end(), '-', '_');
    if (mode.empty() || mode == "default") {
        mode = params.inletInjectionMode;
        std::replace(mode.begin(), mode.end(), '-', '_');
    }
    if (mode == "cuda_recycle" || mode == "thin_slab") return "recycle";
    return mode;
}

bool hard_inlet_reservoir_enabled_0249a(const SimulationParams& params) {
    const std::string mode = normalized_inlet_reservoir_mode_0249a(params);
    return mode == "hard_cell_density" || mode == "hard_density" || mode == "hard" || mode == "cell_density";
}

int io_mode_code_0249a(const std::string& mode) {
    if (is_inlet_boundary_mode(mode)) return 1;
    if (is_outlet_boundary_mode(mode)) return 2;
    return 0;
}

__device__ inline double clamp_device_0249a(double x, double lo, double hi) {
    return fmin(fmax(x, lo), hi);
}

__global__ void inlet_outlet_fullface_mark_exits_kernel_0249a(
    const std::uint64_t n,
    double* __restrict__ x,
    double* __restrict__ y,
    const unsigned char* __restrict__ roleIn,
    unsigned char* __restrict__ roleOut,
    const unsigned char fluidRole,
    const unsigned char inactiveRole,
    const double xMin,
    const double xMax,
    const double yMin,
    const double yMax,
    const int leftMode,
    const int rightMode,
    const int bottomMode,
    const int topMode,
    unsigned long long* __restrict__ hitsLeft,
    unsigned long long* __restrict__ hitsRight,
    unsigned long long* __restrict__ hitsBottom,
    unsigned long long* __restrict__ hitsTop,
    unsigned long long* __restrict__ inletBackflowDeleted,
    unsigned long long* __restrict__ outletParticlesDeleted,
    unsigned long long* __restrict__ roleChanges)
{
    const std::uint64_t i = static_cast<std::uint64_t>(blockIdx.x) * static_cast<std::uint64_t>(blockDim.x) +
                            static_cast<std::uint64_t>(threadIdx.x);
    if (i >= n) return;
    if (roleIn[i] != fluidRole) return;

    bool remove = false;
    int removeMode = 0;
    double xi = x[i];
    double yi = y[i];

    // Match CPU hard-reservoir ordering for unsegmented full-face I/O:
    // x face processing first, then y face processing if still active.
    if (leftMode != 0 || rightMode != 0) {
        if (xi < xMin) {
            atomicAdd(hitsLeft, 1ULL);
            if (leftMode != 0) {
                remove = true;
                removeMode = leftMode;
            }
        } else if (xi > xMax) {
            atomicAdd(hitsRight, 1ULL);
            if (rightMode != 0) {
                remove = true;
                removeMode = rightMode;
            }
        }
    }

    if (!remove && (bottomMode != 0 || topMode != 0)) {
        if (yi < yMin) {
            atomicAdd(hitsBottom, 1ULL);
            if (bottomMode != 0) {
                remove = true;
                removeMode = bottomMode;
            }
        } else if (yi > yMax) {
            atomicAdd(hitsTop, 1ULL);
            if (topMode != 0) {
                remove = true;
                removeMode = topMode;
            }
        }
    }

    if (!remove) return;

    x[i] = clamp_device_0249a(xi, xMin, xMax);
    y[i] = clamp_device_0249a(yi, yMin, yMax);
    roleOut[i] = inactiveRole;
    atomicAdd(roleChanges, 1ULL);
    if (removeMode == 1) {
        atomicAdd(inletBackflowDeleted, 1ULL);
    } else if (removeMode == 2) {
        atomicAdd(outletParticlesDeleted, 1ULL);
    }
}

CudaParticleState& persistent_inlet_outlet_state_0249a() {
    return cuda_shared_particle_state_0251();
}

} // namespace

bool cuda_inlet_outlet_fullface_0249a_requested() {
    return env_truthy_0249a("MPCD_CUDA_INLET_OUTLET_FULLFACE_0249A");
}

bool cuda_inlet_outlet_fullface_0249a_supported(const SimulationParams& params) {
    if (!hard_inlet_reservoir_enabled_0249a(params)) return false;
    if (params.openBoundarySegmentsEnable || params.openBoundarySegmentCount != 0) return false;
    if (!(params.Lx > 0.0) || !(params.Ly > 0.0)) return false;
    if (!(params.dt >= 0.0)) return false;

    const int left = io_mode_code_0249a(params.bcLeft);
    const int right = io_mode_code_0249a(params.bcRight);
    const int bottom = io_mode_code_0249a(params.bcBottom);
    const int top = io_mode_code_0249a(params.bcTop);

    const bool xPair = (left != 0 && right != 0 && left != right && bottom == 0 && top == 0);
    const bool yPair = (bottom != 0 && top != 0 && bottom != top && left == 0 && right == 0);
    // 0249a is deliberately limited to one unsegmented full-face inlet/outlet
    // pair. Mixed x/y I/O or standalone hard reservoirs remain CPU until their
    // own validation patch.
    return xPair || yPair;
}

CudaInletOutletFullface0249aDiagnostics try_apply_cuda_inlet_outlet_fullface_0249a(
    ParticleState& state,
    const SimulationParams& params,
    const FluidDomainBounds& domain,
    std::uint64_t step,
    double time)
{
    (void)step;
    (void)time;
    CudaInletOutletFullface0249aDiagnostics diag{};
    diag.requested = cuda_inlet_outlet_fullface_0249a_requested();
    diag.supported = cuda_inlet_outlet_fullface_0249a_supported(params);
    const std::uint64_t nActiveFluid = active_fluid_count(state);
    diag.particles = nActiveFluid;
    if (!diag.requested || !diag.supported || nActiveFluid == 0u) {
        return diag;
    }
    if (!cuda_particle_state_available()) {
        return diag;
    }

    const auto t0 = Clock::now();
    CudaParticleStateDiagnostics particleDiag{};
    CudaParticleState& gpuState = persistent_inlet_outlet_state_0249a();
    gpuState.upload_all(state, &particleDiag);
    const auto tAfterUpload = Clock::now();

    unsigned long long* dHitsLeft = nullptr;
    unsigned long long* dHitsRight = nullptr;
    unsigned long long* dHitsBottom = nullptr;
    unsigned long long* dHitsTop = nullptr;
    unsigned long long* dInletBackflowDeleted = nullptr;
    unsigned long long* dOutletParticlesDeleted = nullptr;
    unsigned long long* dRoleChanges = nullptr;
    check_cuda_0249a(cudaMalloc(&dHitsLeft, sizeof(unsigned long long)), "allocate hitsLeft");
    check_cuda_0249a(cudaMalloc(&dHitsRight, sizeof(unsigned long long)), "allocate hitsRight");
    check_cuda_0249a(cudaMalloc(&dHitsBottom, sizeof(unsigned long long)), "allocate hitsBottom");
    check_cuda_0249a(cudaMalloc(&dHitsTop, sizeof(unsigned long long)), "allocate hitsTop");
    check_cuda_0249a(cudaMalloc(&dInletBackflowDeleted, sizeof(unsigned long long)), "allocate inletBackflowDeleted");
    check_cuda_0249a(cudaMalloc(&dOutletParticlesDeleted, sizeof(unsigned long long)), "allocate outletParticlesDeleted");
    check_cuda_0249a(cudaMalloc(&dRoleChanges, sizeof(unsigned long long)), "allocate roleChanges");
    check_cuda_0249a(cudaMemset(dHitsLeft, 0, sizeof(unsigned long long)), "clear hitsLeft");
    check_cuda_0249a(cudaMemset(dHitsRight, 0, sizeof(unsigned long long)), "clear hitsRight");
    check_cuda_0249a(cudaMemset(dHitsBottom, 0, sizeof(unsigned long long)), "clear hitsBottom");
    check_cuda_0249a(cudaMemset(dHitsTop, 0, sizeof(unsigned long long)), "clear hitsTop");
    check_cuda_0249a(cudaMemset(dInletBackflowDeleted, 0, sizeof(unsigned long long)), "clear inletBackflowDeleted");
    check_cuda_0249a(cudaMemset(dOutletParticlesDeleted, 0, sizeof(unsigned long long)), "clear outletParticlesDeleted");
    check_cuda_0249a(cudaMemset(dRoleChanges, 0, sizeof(unsigned long long)), "clear roleChanges");

    CudaParticleDeviceView view = gpuState.device_view();
    const int threads = env_int_0249a("MPCD_CUDA_INLET_OUTLET_FULLFACE_0249A_THREADS", 256);
    const std::uint64_t blocks64 = (nActiveFluid + static_cast<std::uint64_t>(threads) - 1u) /
                                   static_cast<std::uint64_t>(threads);
    if (blocks64 > static_cast<std::uint64_t>(2147483647)) {
        throw std::runtime_error("cuda_inlet_outlet_fullface_0249a: grid too large for 1D launch");
    }

    inlet_outlet_fullface_mark_exits_kernel_0249a<<<static_cast<unsigned int>(blocks64), threads>>>(
        nActiveFluid,
        view.x, view.y, view.role, view.role,
        kParticleRoleFluid, kParticleRoleInactive,
        domain.xMin, domain.xMax, domain.yMin, domain.yMax,
        io_mode_code_0249a(params.bcLeft),
        io_mode_code_0249a(params.bcRight),
        io_mode_code_0249a(params.bcBottom),
        io_mode_code_0249a(params.bcTop),
        dHitsLeft, dHitsRight, dHitsBottom, dHitsTop,
        dInletBackflowDeleted, dOutletParticlesDeleted, dRoleChanges);
    check_cuda_0249a(cudaGetLastError(), "inlet_outlet_fullface_mark_exits_kernel_0249a launch");
    check_cuda_0249a(cudaDeviceSynchronize(), "inlet_outlet_fullface_mark_exits_kernel_0249a synchronize");
    const auto tAfterKernel = Clock::now();

    unsigned long long hHitsLeft = 0ULL;
    unsigned long long hHitsRight = 0ULL;
    unsigned long long hHitsBottom = 0ULL;
    unsigned long long hHitsTop = 0ULL;
    unsigned long long hInletBackflowDeleted = 0ULL;
    unsigned long long hOutletParticlesDeleted = 0ULL;
    unsigned long long hRoleChanges = 0ULL;
    check_cuda_0249a(cudaMemcpy(&hHitsLeft, dHitsLeft, sizeof(unsigned long long), cudaMemcpyDeviceToHost), "copy hitsLeft");
    check_cuda_0249a(cudaMemcpy(&hHitsRight, dHitsRight, sizeof(unsigned long long), cudaMemcpyDeviceToHost), "copy hitsRight");
    check_cuda_0249a(cudaMemcpy(&hHitsBottom, dHitsBottom, sizeof(unsigned long long), cudaMemcpyDeviceToHost), "copy hitsBottom");
    check_cuda_0249a(cudaMemcpy(&hHitsTop, dHitsTop, sizeof(unsigned long long), cudaMemcpyDeviceToHost), "copy hitsTop");
    check_cuda_0249a(cudaMemcpy(&hInletBackflowDeleted, dInletBackflowDeleted, sizeof(unsigned long long), cudaMemcpyDeviceToHost), "copy inletBackflowDeleted");
    check_cuda_0249a(cudaMemcpy(&hOutletParticlesDeleted, dOutletParticlesDeleted, sizeof(unsigned long long), cudaMemcpyDeviceToHost), "copy outletParticlesDeleted");
    check_cuda_0249a(cudaMemcpy(&hRoleChanges, dRoleChanges, sizeof(unsigned long long), cudaMemcpyDeviceToHost), "copy roleChanges");
    check_cuda_0249a(cudaFree(dHitsLeft), "free hitsLeft");
    check_cuda_0249a(cudaFree(dHitsRight), "free hitsRight");
    check_cuda_0249a(cudaFree(dHitsBottom), "free hitsBottom");
    check_cuda_0249a(cudaFree(dHitsTop), "free hitsTop");
    check_cuda_0249a(cudaFree(dInletBackflowDeleted), "free inletBackflowDeleted");
    check_cuda_0249a(cudaFree(dOutletParticlesDeleted), "free outletParticlesDeleted");
    check_cuda_0249a(cudaFree(dRoleChanges), "free roleChanges");

    gpuState.download_active_prefix(state, &particleDiag);
    cuda_shared_particle_state_0251_mark_fresh("inlet_outlet_fullface_0249a");
    const auto tAfterDownload = Clock::now();

    diag.handled = true;
    diag.applied = hRoleChanges > 0ULL;
    diag.roleChanges = static_cast<std::uint64_t>(hRoleChanges);
    diag.hitsLeft = static_cast<std::uint64_t>(hHitsLeft);
    diag.hitsRight = static_cast<std::uint64_t>(hHitsRight);
    diag.hitsBottom = static_cast<std::uint64_t>(hHitsBottom);
    diag.hitsTop = static_cast<std::uint64_t>(hHitsTop);
    diag.inletBackflowDeleted = static_cast<std::uint64_t>(hInletBackflowDeleted);
    diag.outletParticlesDeleted = static_cast<std::uint64_t>(hOutletParticlesDeleted);
    diag.fluidParticles = nActiveFluid;
    diag.allocationCalls = particleDiag.allocationCalls;
    diag.uploadCalls = particleDiag.uploadCalls;
    diag.downloadCalls = particleDiag.downloadCalls;
    diag.uploadSeconds = elapsed_0249a(t0, tAfterUpload);
    diag.kernelSeconds = elapsed_0249a(tAfterUpload, tAfterKernel);
    diag.downloadSeconds = elapsed_0249a(tAfterKernel, tAfterDownload);
    diag.totalSeconds = elapsed_0249a(t0, tAfterDownload);
    return diag;
}

} // namespace mpcd
