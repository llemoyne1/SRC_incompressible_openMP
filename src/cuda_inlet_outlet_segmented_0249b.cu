#include "cuda_inlet_outlet_segmented_0249b.h"

#include "cuda_particle_state.h"
#include "open_boundary_segments.h"

#include <cuda_runtime.h>

#include <algorithm>
#include <array>
#include <chrono>
#include <cstdlib>
#include <cstdint>
#include <stdexcept>
#include <string>

namespace mpcd {
namespace {

inline void check_cuda_0249b(cudaError_t err, const char* what) {
    if (err != cudaSuccess) {
        throw std::runtime_error(std::string("cuda_inlet_outlet_segmented_0249b: ") + what + ": " + cudaGetErrorString(err));
    }
}

using Clock = std::chrono::steady_clock;
inline double elapsed_0249b(const Clock::time_point& a, const Clock::time_point& b) {
    return std::chrono::duration<double>(b - a).count();
}

bool env_truthy_0249b(const char* name) {
    const char* v = std::getenv(name);
    if (v == nullptr || *v == '\0') return false;
    const std::string s(v);
    return !(s == "0" || s == "false" || s == "FALSE" || s == "off" || s == "OFF" || s == "no" || s == "NO");
}

int env_int_0249b(const char* name, int defaultValue) {
    const char* v = std::getenv(name);
    if (v == nullptr || *v == '\0') return defaultValue;
    try {
        return std::max(1, std::stoi(std::string(v)));
    } catch (...) {
        return defaultValue;
    }
}

std::string normalized_inlet_reservoir_mode_0249b(const SimulationParams& params) {
    std::string mode = params.inletReservoirMode;
    std::replace(mode.begin(), mode.end(), '-', '_');
    if (mode.empty() || mode == "default") {
        mode = params.inletInjectionMode;
        std::replace(mode.begin(), mode.end(), '-', '_');
    }
    if (mode == "cuda_recycle" || mode == "thin_slab") return "recycle";
    return mode;
}

bool hard_inlet_reservoir_enabled_0249b(const SimulationParams& params) {
    const std::string mode = normalized_inlet_reservoir_mode_0249b(params);
    return mode == "hard_cell_density" || mode == "hard_density" || mode == "hard" || mode == "cell_density";
}

bool is_wall_like_mode_0249b(const std::string& mode) {
    return mode == "solid" || mode == "specular" || mode == "bounceback";
}

int segment_face_code_0249b(const std::string& face) {
    if (face == "left") return 0;
    if (face == "right") return 1;
    if (face == "bottom") return 2;
    if (face == "top") return 3;
    return -1;
}

int segment_mode_code_0249b(const OpenBoundarySegment& seg) {
    if (open_boundary_segment_is_inlet(seg)) return 1;
    if (open_boundary_segment_is_outlet(seg)) return 2;
    return 0;
}

__device__ inline double clamp_device_0249b(double x, double lo, double hi) {
    return fmin(fmax(x, lo), hi);
}

__device__ inline double segment_s_device_0249b(int face, double x, double y,
                                                double xMin, double xMax,
                                                double yMin, double yMax) {
    if (face == 0 || face == 1) {
        const double h = yMax - yMin;
        return h > 0.0 ? (y - yMin) / h : -1.0;
    }
    if (face == 2 || face == 3) {
        const double w = xMax - xMin;
        return w > 0.0 ? (x - xMin) / w : -1.0;
    }
    return -1.0;
}

__device__ inline int find_segment_mode_device_0249b(int crossingFace,
                                                     double s,
                                                     const int* __restrict__ segFaces,
                                                     const int* __restrict__ segModes,
                                                     const double* __restrict__ segSMin,
                                                     const double* __restrict__ segSMax,
                                                     int nSegments) {
    for (int k = 0; k < nSegments; ++k) {
        if (segFaces[k] == crossingFace && s >= segSMin[k] && s <= segSMax[k]) {
            return segModes[k];
        }
    }
    return 0;
}

__device__ inline bool mark_if_segment_exit_device_0249b(
    int face,
    double xi,
    double yi,
    double xMin,
    double xMax,
    double yMin,
    double yMax,
    const int* __restrict__ segFaces,
    const int* __restrict__ segModes,
    const double* __restrict__ segSMin,
    const double* __restrict__ segSMax,
    int nSegments,
    int& removeMode)
{
    const double s = segment_s_device_0249b(face, xi, yi, xMin, xMax, yMin, yMax);
    const int mode = find_segment_mode_device_0249b(face, s, segFaces, segModes, segSMin, segSMax, nSegments);
    if (mode == 0) return false;
    removeMode = mode;
    return true;
}

__global__ void inlet_outlet_segmented_mark_exits_kernel_0249b(
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
    const int* __restrict__ segFaces,
    const int* __restrict__ segModes,
    const double* __restrict__ segSMin,
    const double* __restrict__ segSMax,
    const int nSegments,
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

    // Keep the same face order as apply_hard_inlet_reservoir_boundary:
    // x-faces first, y-faces only if the x-face did not consume the particle.
    if (xi < xMin) {
        remove = mark_if_segment_exit_device_0249b(0, xi, yi, xMin, xMax, yMin, yMax,
                                                   segFaces, segModes, segSMin, segSMax, nSegments, removeMode);
        if (remove) atomicAdd(hitsLeft, 1ULL);
    } else if (xi > xMax) {
        remove = mark_if_segment_exit_device_0249b(1, xi, yi, xMin, xMax, yMin, yMax,
                                                   segFaces, segModes, segSMin, segSMax, nSegments, removeMode);
        if (remove) atomicAdd(hitsRight, 1ULL);
    }

    if (!remove) {
        if (yi < yMin) {
            remove = mark_if_segment_exit_device_0249b(2, xi, yi, xMin, xMax, yMin, yMax,
                                                       segFaces, segModes, segSMin, segSMax, nSegments, removeMode);
            if (remove) atomicAdd(hitsBottom, 1ULL);
        } else if (yi > yMax) {
            remove = mark_if_segment_exit_device_0249b(3, xi, yi, xMin, xMax, yMin, yMax,
                                                       segFaces, segModes, segSMin, segSMax, nSegments, removeMode);
            if (remove) atomicAdd(hitsTop, 1ULL);
        }
    }

    if (!remove) return;

    x[i] = clamp_device_0249b(xi, xMin, xMax);
    y[i] = clamp_device_0249b(yi, yMin, yMax);
    roleOut[i] = inactiveRole;
    atomicAdd(roleChanges, 1ULL);
    if (removeMode == 1) {
        atomicAdd(inletBackflowDeleted, 1ULL);
    } else if (removeMode == 2) {
        atomicAdd(outletParticlesDeleted, 1ULL);
    }
}

CudaParticleState& persistent_inlet_outlet_state_0249b() {
    static CudaParticleState gpuState;
    return gpuState;
}

} // namespace

bool cuda_inlet_outlet_segmented_0249b_requested() {
    return env_truthy_0249b("MPCD_CUDA_INLET_OUTLET_SEGMENTED_0249B");
}

bool cuda_inlet_outlet_segmented_0249b_supported(const SimulationParams& params) {
    if (!hard_inlet_reservoir_enabled_0249b(params)) return false;
    if (!params.openBoundarySegmentsEnable || params.openBoundarySegmentCount <= 0) return false;
    if (static_cast<int>(params.openBoundarySegments.size()) != params.openBoundarySegmentCount) return false;
    if (params.openBoundarySegmentCount > kOpenBoundaryMaxSegments) return false;
    if (!(params.Lx > 0.0) || !(params.Ly > 0.0) || !(params.dt >= 0.0)) return false;

    // 0249b is deliberately the segmented-wall subset: no full-face I/O modes,
    // no periodic face carrying segments.  Uncovered portions of segmented faces
    // remain wall-like and are still handled by the CPU boundary pass.
    if (is_io_boundary_mode(params.bcLeft) || is_io_boundary_mode(params.bcRight) ||
        is_io_boundary_mode(params.bcBottom) || is_io_boundary_mode(params.bcTop)) return false;
    if (!is_wall_like_mode_0249b(params.bcLeft) || !is_wall_like_mode_0249b(params.bcRight) ||
        !is_wall_like_mode_0249b(params.bcBottom) || !is_wall_like_mode_0249b(params.bcTop)) return false;
    if (params.immersedSolidEnable) return false;

    bool hasInlet = false;
    bool hasOutlet = false;
    bool hasLeft = false;
    for (const OpenBoundarySegment& seg : params.openBoundarySegments) {
        const int face = segment_face_code_0249b(seg.face);
        const int mode = segment_mode_code_0249b(seg);
        if (face < 0 || mode == 0) return false;
        // 0249b validation is deliberately same-face U-turn only: inlet and
        // outlet segments on the left boundary x=0. Other segment topologies are
        // left on the CPU until their own validation patch.
        if (face != 0) return false;
        if (!(seg.sMin >= 0.0 && seg.sMax <= 1.0 && seg.sMax >= seg.sMin)) return false;
        if (mode == 1) hasInlet = true;
        if (mode == 2) hasOutlet = true;
        if (face == 0) hasLeft = true;
    }
    // The validation target is the U-turn flow with inlet and outlet segments on x=0.
    // Keeping the guard explicit avoids accidentally claiming support for all segment
    // topologies before dedicated tests exist.
    return hasInlet && hasOutlet && hasLeft;
}

CudaInletOutletSegmented0249bDiagnostics try_apply_cuda_inlet_outlet_segmented_0249b(
    ParticleState& state,
    const SimulationParams& params,
    const FluidDomainBounds& domain,
    std::uint64_t step,
    double time)
{
    (void)step;
    (void)time;
    CudaInletOutletSegmented0249bDiagnostics diag{};
    diag.requested = cuda_inlet_outlet_segmented_0249b_requested();
    diag.supported = cuda_inlet_outlet_segmented_0249b_supported(params);
    diag.particles = state.Np;
    diag.segments = params.openBoundarySegments.size();
    if (!diag.requested || !diag.supported || state.Np == 0u) {
        return diag;
    }
    if (!cuda_particle_state_available()) {
        return diag;
    }

    const int nSegments = static_cast<int>(params.openBoundarySegments.size());
    std::array<int, kOpenBoundaryMaxSegments> hFaces{};
    std::array<int, kOpenBoundaryMaxSegments> hModes{};
    std::array<double, kOpenBoundaryMaxSegments> hSMin{};
    std::array<double, kOpenBoundaryMaxSegments> hSMax{};
    for (int k = 0; k < nSegments; ++k) {
        const OpenBoundarySegment& seg = params.openBoundarySegments[static_cast<std::size_t>(k)];
        hFaces[static_cast<std::size_t>(k)] = segment_face_code_0249b(seg.face);
        hModes[static_cast<std::size_t>(k)] = segment_mode_code_0249b(seg);
        hSMin[static_cast<std::size_t>(k)] = seg.sMin;
        hSMax[static_cast<std::size_t>(k)] = seg.sMax;
    }

    const auto t0 = Clock::now();
    CudaParticleStateDiagnostics particleDiag{};
    CudaParticleState& gpuState = persistent_inlet_outlet_state_0249b();
    gpuState.upload_all(state, &particleDiag);
    const auto tAfterUpload = Clock::now();

    int* dFaces = nullptr;
    int* dModes = nullptr;
    double* dSMin = nullptr;
    double* dSMax = nullptr;
    unsigned long long* dHitsLeft = nullptr;
    unsigned long long* dHitsRight = nullptr;
    unsigned long long* dHitsBottom = nullptr;
    unsigned long long* dHitsTop = nullptr;
    unsigned long long* dInletBackflowDeleted = nullptr;
    unsigned long long* dOutletParticlesDeleted = nullptr;
    unsigned long long* dRoleChanges = nullptr;

    const std::size_t segIntBytes = static_cast<std::size_t>(nSegments) * sizeof(int);
    const std::size_t segDoubleBytes = static_cast<std::size_t>(nSegments) * sizeof(double);
    check_cuda_0249b(cudaMalloc(&dFaces, segIntBytes), "allocate segment faces");
    check_cuda_0249b(cudaMalloc(&dModes, segIntBytes), "allocate segment modes");
    check_cuda_0249b(cudaMalloc(&dSMin, segDoubleBytes), "allocate segment sMin");
    check_cuda_0249b(cudaMalloc(&dSMax, segDoubleBytes), "allocate segment sMax");
    check_cuda_0249b(cudaMemcpy(dFaces, hFaces.data(), segIntBytes, cudaMemcpyHostToDevice), "copy segment faces");
    check_cuda_0249b(cudaMemcpy(dModes, hModes.data(), segIntBytes, cudaMemcpyHostToDevice), "copy segment modes");
    check_cuda_0249b(cudaMemcpy(dSMin, hSMin.data(), segDoubleBytes, cudaMemcpyHostToDevice), "copy segment sMin");
    check_cuda_0249b(cudaMemcpy(dSMax, hSMax.data(), segDoubleBytes, cudaMemcpyHostToDevice), "copy segment sMax");

    check_cuda_0249b(cudaMalloc(&dHitsLeft, sizeof(unsigned long long)), "allocate hitsLeft");
    check_cuda_0249b(cudaMalloc(&dHitsRight, sizeof(unsigned long long)), "allocate hitsRight");
    check_cuda_0249b(cudaMalloc(&dHitsBottom, sizeof(unsigned long long)), "allocate hitsBottom");
    check_cuda_0249b(cudaMalloc(&dHitsTop, sizeof(unsigned long long)), "allocate hitsTop");
    check_cuda_0249b(cudaMalloc(&dInletBackflowDeleted, sizeof(unsigned long long)), "allocate inletBackflowDeleted");
    check_cuda_0249b(cudaMalloc(&dOutletParticlesDeleted, sizeof(unsigned long long)), "allocate outletParticlesDeleted");
    check_cuda_0249b(cudaMalloc(&dRoleChanges, sizeof(unsigned long long)), "allocate roleChanges");
    check_cuda_0249b(cudaMemset(dHitsLeft, 0, sizeof(unsigned long long)), "clear hitsLeft");
    check_cuda_0249b(cudaMemset(dHitsRight, 0, sizeof(unsigned long long)), "clear hitsRight");
    check_cuda_0249b(cudaMemset(dHitsBottom, 0, sizeof(unsigned long long)), "clear hitsBottom");
    check_cuda_0249b(cudaMemset(dHitsTop, 0, sizeof(unsigned long long)), "clear hitsTop");
    check_cuda_0249b(cudaMemset(dInletBackflowDeleted, 0, sizeof(unsigned long long)), "clear inletBackflowDeleted");
    check_cuda_0249b(cudaMemset(dOutletParticlesDeleted, 0, sizeof(unsigned long long)), "clear outletParticlesDeleted");
    check_cuda_0249b(cudaMemset(dRoleChanges, 0, sizeof(unsigned long long)), "clear roleChanges");

    CudaParticleDeviceView view = gpuState.device_view();
    const int threads = env_int_0249b("MPCD_CUDA_INLET_OUTLET_SEGMENTED_0249B_THREADS", 256);
    const std::uint64_t blocks64 = (state.Np + static_cast<std::uint64_t>(threads) - 1u) /
                                   static_cast<std::uint64_t>(threads);
    if (blocks64 > static_cast<std::uint64_t>(2147483647)) {
        throw std::runtime_error("cuda_inlet_outlet_segmented_0249b: grid too large for 1D launch");
    }

    inlet_outlet_segmented_mark_exits_kernel_0249b<<<static_cast<unsigned int>(blocks64), threads>>>(
        view.n,
        view.x, view.y, view.role, view.role,
        kParticleRoleFluid, kParticleRoleInactive,
        domain.xMin, domain.xMax, domain.yMin, domain.yMax,
        dFaces, dModes, dSMin, dSMax, nSegments,
        dHitsLeft, dHitsRight, dHitsBottom, dHitsTop,
        dInletBackflowDeleted, dOutletParticlesDeleted, dRoleChanges);
    check_cuda_0249b(cudaGetLastError(), "inlet_outlet_segmented_mark_exits_kernel_0249b launch");
    check_cuda_0249b(cudaDeviceSynchronize(), "inlet_outlet_segmented_mark_exits_kernel_0249b synchronize");
    const auto tAfterKernel = Clock::now();

    unsigned long long hHitsLeft = 0ULL;
    unsigned long long hHitsRight = 0ULL;
    unsigned long long hHitsBottom = 0ULL;
    unsigned long long hHitsTop = 0ULL;
    unsigned long long hInletBackflowDeleted = 0ULL;
    unsigned long long hOutletParticlesDeleted = 0ULL;
    unsigned long long hRoleChanges = 0ULL;
    check_cuda_0249b(cudaMemcpy(&hHitsLeft, dHitsLeft, sizeof(unsigned long long), cudaMemcpyDeviceToHost), "copy hitsLeft");
    check_cuda_0249b(cudaMemcpy(&hHitsRight, dHitsRight, sizeof(unsigned long long), cudaMemcpyDeviceToHost), "copy hitsRight");
    check_cuda_0249b(cudaMemcpy(&hHitsBottom, dHitsBottom, sizeof(unsigned long long), cudaMemcpyDeviceToHost), "copy hitsBottom");
    check_cuda_0249b(cudaMemcpy(&hHitsTop, dHitsTop, sizeof(unsigned long long), cudaMemcpyDeviceToHost), "copy hitsTop");
    check_cuda_0249b(cudaMemcpy(&hInletBackflowDeleted, dInletBackflowDeleted, sizeof(unsigned long long), cudaMemcpyDeviceToHost), "copy inletBackflowDeleted");
    check_cuda_0249b(cudaMemcpy(&hOutletParticlesDeleted, dOutletParticlesDeleted, sizeof(unsigned long long), cudaMemcpyDeviceToHost), "copy outletParticlesDeleted");
    check_cuda_0249b(cudaMemcpy(&hRoleChanges, dRoleChanges, sizeof(unsigned long long), cudaMemcpyDeviceToHost), "copy roleChanges");

    check_cuda_0249b(cudaFree(dFaces), "free segment faces");
    check_cuda_0249b(cudaFree(dModes), "free segment modes");
    check_cuda_0249b(cudaFree(dSMin), "free segment sMin");
    check_cuda_0249b(cudaFree(dSMax), "free segment sMax");
    check_cuda_0249b(cudaFree(dHitsLeft), "free hitsLeft");
    check_cuda_0249b(cudaFree(dHitsRight), "free hitsRight");
    check_cuda_0249b(cudaFree(dHitsBottom), "free hitsBottom");
    check_cuda_0249b(cudaFree(dHitsTop), "free hitsTop");
    check_cuda_0249b(cudaFree(dInletBackflowDeleted), "free inletBackflowDeleted");
    check_cuda_0249b(cudaFree(dOutletParticlesDeleted), "free outletParticlesDeleted");
    check_cuda_0249b(cudaFree(dRoleChanges), "free roleChanges");

    gpuState.download_all(state, &particleDiag);
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
    diag.fluidParticles = 0u;
    for (std::size_t i = 0; i < static_cast<std::size_t>(state.Np); ++i) {
        if (is_fluid_particle(state, i)) ++diag.fluidParticles;
    }
    diag.allocationCalls = particleDiag.allocationCalls;
    diag.uploadCalls = particleDiag.uploadCalls;
    diag.downloadCalls = particleDiag.downloadCalls;
    diag.uploadSeconds = elapsed_0249b(t0, tAfterUpload);
    diag.kernelSeconds = elapsed_0249b(tAfterUpload, tAfterKernel);
    diag.downloadSeconds = elapsed_0249b(tAfterKernel, tAfterDownload);
    diag.totalSeconds = elapsed_0249b(t0, tAfterDownload);
    return diag;
}

} // namespace mpcd
