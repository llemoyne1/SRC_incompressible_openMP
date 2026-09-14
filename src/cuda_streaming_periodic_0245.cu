#include "cuda_streaming_periodic_0245.h"

#include "cuda_particle_state.h"
#include "cuda_shared_particle_state_0251.h"
#include "cuda_darcy_brinkman_0343.h"

#include <cuda_runtime.h>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdlib>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <stdexcept>
#include <string>
#include <vector>

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

// 0493x15c — permeability diagnostic for the qualification geometry only.
// The diagnostic reuses the existing chi-solid audit switch and introduces no
// new runtime parameter.  It activates only when chi is a single full-height
// vertical solid slab.  The measured surface is the slab mid-plane, so signed
// crossing mass is an exact through-flow measure; back-and-forth thermal
// crossings cancel in the net flux but remain visible in the gross flux.
struct ChiSlabPlane0493x15c {
    bool valid = false;
    std::uint64_t geometryVersion = 0u;
    int ixLo = -1;
    int ixHi = -1;
    double xLo = 0.0;
    double xHi = 0.0;
    double xPlane = 0.0;
};

ChiSlabPlane0493x15c& chi_slab_plane_cache_0493x15c() {
    static ChiSlabPlane0493x15c c{};
    return c;
}

bool chi_permeability_diag_requested_0493x15c(const SimulationParams& params) {
    return params.darcyBrinkmanEnable &&
           env_truthy_0245("MPCD_CHI_SOLID_IMPULSE_DIAG_0493X15A");
}

ChiSlabPlane0493x15c derive_chi_slab_plane_0493x15c(const SimulationParams& params) {
    ChiSlabPlane0493x15c out{};
    out.geometryVersion = cuda_darcy_brinkman_0343_chi_geometry_version();
    const float* dChi = nullptr;
    int nx = 0, ny = 0;
    if (!cuda_darcy_brinkman_0343_device_chi_field(params, &dChi, &nx, &ny) ||
        dChi == nullptr || nx <= 0 || ny <= 0 || !(params.Lx > 0.0)) {
        return out;
    }
    std::vector<float> hChi(static_cast<std::size_t>(nx) * static_cast<std::size_t>(ny), 1.0f);
    check_cuda_0245(cudaMemcpy(hChi.data(), dChi, hChi.size() * sizeof(float), cudaMemcpyDeviceToHost),
                    "copy chi for x15c slab detection");

    std::vector<int> solidColumn(static_cast<std::size_t>(nx), 0);
    for (int ix = 0; ix < nx; ++ix) {
        bool fullHeightSolid = true;
        for (int iy = 0; iy < ny; ++iy) {
            const float chi = hChi[static_cast<std::size_t>(iy) * static_cast<std::size_t>(nx) + static_cast<std::size_t>(ix)];
            if (!(chi < 0.5f)) {
                fullHeightSolid = false;
                break;
            }
        }
        solidColumn[static_cast<std::size_t>(ix)] = fullHeightSolid ? 1 : 0;
    }

    int components = 0;
    int lo = -1, hi = -1;
    for (int ix = 0; ix < nx; ) {
        if (!solidColumn[static_cast<std::size_t>(ix)]) { ++ix; continue; }
        const int begin = ix;
        while (ix + 1 < nx && solidColumn[static_cast<std::size_t>(ix + 1)]) ++ix;
        const int end = ix;
        ++components;
        lo = begin;
        hi = end;
        ++ix;
    }
    if (components != 1 || lo < 0 || hi < lo) return out;

    // x15c is deliberately restricted to an interior slab.  This avoids any
    // ambiguity with a solid component that wraps across the periodic seam.
    if (lo == 0 || hi == nx - 1) return out;
    const double dx = params.Lx / static_cast<double>(nx);
    out.valid = true;
    out.ixLo = lo;
    out.ixHi = hi;
    out.xLo = static_cast<double>(lo) * dx;
    out.xHi = static_cast<double>(hi + 1) * dx;
    out.xPlane = 0.5 * (out.xLo + out.xHi);
    return out;
}

const ChiSlabPlane0493x15c& ensure_chi_slab_plane_0493x15c(const SimulationParams& params) {
    auto& c = chi_slab_plane_cache_0493x15c();
    const std::uint64_t version = cuda_darcy_brinkman_0343_chi_geometry_version();
    if (c.geometryVersion != version || (!c.valid && version != 0u)) {
        c = derive_chi_slab_plane_0493x15c(params);
    }
    return c;
}

__device__ double g_chiSlabCrossMass0493x15c[2]; // 0: left->right, 1: right->left
__device__ unsigned long long g_chiSlabCrossCount0493x15c[2];

void reset_chi_slab_crossing_0493x15c(bool enabled) {
    if (!enabled) return;
    const double zeroMass[2] = {0.0, 0.0};
    const unsigned long long zeroCount[2] = {0ull, 0ull};
    check_cuda_0245(cudaMemcpyToSymbol(g_chiSlabCrossMass0493x15c, zeroMass, sizeof(zeroMass), 0, cudaMemcpyHostToDevice),
                    "reset x15c crossing mass");
    check_cuda_0245(cudaMemcpyToSymbol(g_chiSlabCrossCount0493x15c, zeroCount, sizeof(zeroCount), 0, cudaMemcpyHostToDevice),
                    "reset x15c crossing count");
}

struct ChiSlabCrossingStep0493x15c {
    unsigned long long leftToRightCount = 0ull;
    unsigned long long rightToLeftCount = 0ull;
    double leftToRightMass = 0.0;
    double rightToLeftMass = 0.0;
};

ChiSlabCrossingStep0493x15c read_chi_slab_crossing_0493x15c(bool enabled) {
    ChiSlabCrossingStep0493x15c out{};
    if (!enabled) return out;
    double mass[2] = {0.0, 0.0};
    unsigned long long count[2] = {0ull, 0ull};
    check_cuda_0245(cudaMemcpyFromSymbol(mass, g_chiSlabCrossMass0493x15c, sizeof(mass), 0, cudaMemcpyDeviceToHost),
                    "read x15c crossing mass");
    check_cuda_0245(cudaMemcpyFromSymbol(count, g_chiSlabCrossCount0493x15c, sizeof(count), 0, cudaMemcpyDeviceToHost),
                    "read x15c crossing count");
    out.leftToRightMass = mass[0];
    out.rightToLeftMass = mass[1];
    out.leftToRightCount = count[0];
    out.rightToLeftCount = count[1];
    return out;
}

void append_chi_permeability_csv_0493x15c(const SimulationParams& params,
                                           std::uint64_t step,
                                           const ChiSlabPlane0493x15c& slab,
                                           const ChiSlabCrossingStep0493x15c& cross) {
    if (!slab.valid) return;
    const std::filesystem::path path = std::filesystem::path(params.outputDir) /
                                       "chi_permeability_0493x15c.csv";
    if (!path.parent_path().empty()) std::filesystem::create_directories(path.parent_path());
    const bool writeHeader = !std::filesystem::exists(path) || std::filesystem::file_size(path) == 0u;
    std::ofstream out(path.string(), std::ios::app);
    if (!out) return;
    out << std::setprecision(17);
    if (writeHeader) {
        out << "step,time,geometryVersion,ixLo,ixHi,xLo,xHi,xPlane,slabWidth,"
               "leftToRightCount,rightToLeftCount,leftToRightMass,rightToLeftMass,"
               "netCrossingMass,grossCrossingMass,netMassFlux,grossMassFlux\n";
    }
    const double lr = cross.leftToRightMass;
    const double rl = cross.rightToLeftMass;
    const double invDt = params.dt > 0.0 ? 1.0 / params.dt : 0.0;
    out << step << ',' << (static_cast<double>(step) * params.dt) << ',' << slab.geometryVersion << ','
        << slab.ixLo << ',' << slab.ixHi << ',' << slab.xLo << ',' << slab.xHi << ','
        << slab.xPlane << ',' << (slab.xHi - slab.xLo) << ','
        << cross.leftToRightCount << ',' << cross.rightToLeftCount << ','
        << lr << ',' << rl << ',' << (lr - rl) << ',' << (lr + rl) << ','
        << (lr - rl) * invDt << ',' << (lr + rl) * invDt << '\n';
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
    const double* __restrict__ mass,
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
    const int tgModeY,
    const int permeabilityDiag0493x15c,
    const double permeabilityPlaneX0493x15c)
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
    const double xUnwrapped1 = x0 + vx1 * dt;
    if (permeabilityDiag0493x15c) {
        const bool lr = (x0 < permeabilityPlaneX0493x15c && xUnwrapped1 >= permeabilityPlaneX0493x15c);
        const bool rl = (x0 >= permeabilityPlaneX0493x15c && xUnwrapped1 < permeabilityPlaneX0493x15c);
        if (lr || rl) {
            const int dir = lr ? 0 : 1;
            atomicAdd(&g_chiSlabCrossMass0493x15c[dir], mass[i]);
            atomicAdd(&g_chiSlabCrossCount0493x15c[dir], 1ull);
        }
    }
    // 0245 keeps the CPU boundary operator active downstream.  For the strictly
    // periodic validation subset, wrapping here is exact and leaves the boundary
    // pass idempotent; it also avoids exposing downstream CPU code to stale
    // out-of-box positions if later diagnostics inspect the state between phases.
    x[i] = wrap_periodic_device_0245(xUnwrapped1, Lx);
    y[i] = wrap_periodic_device_0245(y0 + vy1 * dt, Ly);
}

CudaParticleState& persistent_streaming_state_0245() {
    return cuda_shared_particle_state_0251();
}

} // namespace

bool cuda_periodic_streaming_0245_requested() {
    return env_truthy_0245("MPCD_CUDA_STREAMING_PERIODIC_0245");
}

bool cuda_periodic_streaming_0245_resident_0260_requested() {
    // 0260 introduced the periodic resident path.  0262 reuses the same
    // periodic force/stream kernel before applying the immersed-rectangle
    // reflection kernel on the same shared CudaParticleState.  Treat both
    // modes as resident here; otherwise a periodic+solid run falls back to
    // CPU streaming on a stale host ParticleState between summaries.
    return env_truthy_0245("MPCD_CUDA_CLASSIC_SRC_PERIODIC_RESIDENT_0260") ||
           env_truthy_0245("MPCD_CUDA_CLASSIC_SRC_SOLID_RESIDENT_0262");
}

bool cuda_periodic_streaming_0245_download_all_requested_0260() {
    const char* v = std::getenv("MPCD_CUDA_STREAMING_PERIODIC_0245_DOWNLOAD_ALL");
    if (v == nullptr || *v == '\0') {
        return !cuda_periodic_streaming_0245_resident_0260_requested();
    }
    const std::string s(v);
    return !(s == "0" || s == "false" || s == "FALSE" || s == "off" || s == "OFF" || s == "no" || s == "NO");
}

bool cuda_periodic_streaming_0271_async_resident_enabled(const bool resident0260, const bool downloadAll) {
    if (!resident0260 || downloadAll) return false;
    return env_truthy_0245("MPCD_CUDA_CLASSIC_SRC_RESIDENT_0271_ASYNC_STREAM") &&
           !env_truthy_0245("MPCD_CUDA_CLASSIC_SRC_RESIDENT_0271_DISABLE_ASYNC_STREAM");
}

bool cuda_periodic_streaming_0245_supported(const SimulationParams& params) {
    if (!is_periodic_pair_0245(params.bcLeft, params.bcRight)) return false;
    if (!is_periodic_pair_0245(params.bcBottom, params.bcTop)) return false;
    if (params.openBoundarySegmentsEnable || params.openBoundarySegmentCount != 0) return false;
    // 0334a: periodic streaming is independent of the immersed-solid shape.
    // Downstream immersed CUDA handlers consume the same shared resident state;
    // if they refuse a case, src_mpcd_base.cpp synchronizes the active prefix
    // before a CPU fallback.
    (void)params.immersedSolidEnable;
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
    CudaParticleState& gpuState = persistent_streaming_state_0245();
    const bool resident0260 = cuda_periodic_streaming_0245_resident_0260_requested();
    const bool canReuseResident = resident0260 && cuda_shared_particle_state_0251_is_fresh();
    if (!canReuseResident) {
        gpuState.upload_all(state, &particleDiag);
    }
    const auto tAfterUpload = Clock::now();

    CudaParticleDeviceView view = gpuState.device_view();
    const int threads = env_int_0245("MPCD_CUDA_STREAMING_PERIODIC_0245_THREADS", 256);
    const std::uint64_t blocks64 = (nActiveFluid + static_cast<std::uint64_t>(threads) - 1u) /
                                   static_cast<std::uint64_t>(threads);
    if (blocks64 > static_cast<std::uint64_t>(2147483647)) {
        throw std::runtime_error("cuda_streaming_periodic_0245: grid too large for 1D launch");
    }
    const bool downloadAll = cuda_periodic_streaming_0245_download_all_requested_0260();
    const bool asyncResident0271 = cuda_periodic_streaming_0271_async_resident_enabled(resident0260, downloadAll);

    const bool permeabilityRequested0493x15c = chi_permeability_diag_requested_0493x15c(params);
    ChiSlabPlane0493x15c slab0493x15c{};
    if (permeabilityRequested0493x15c) {
        slab0493x15c = ensure_chi_slab_plane_0493x15c(params);
    }
    const bool permeabilityEnabled0493x15c = permeabilityRequested0493x15c && slab0493x15c.valid;
    reset_chi_slab_crossing_0493x15c(permeabilityEnabled0493x15c);

    periodic_force_stream_kernel_0245<<<static_cast<unsigned int>(blocks64), threads>>>(
        nActiveFluid, view.x, view.y, view.vx, view.vy, view.mass, view.role,
        kParticleRoleFluid,
        params.dt, params.Lx, params.Ly,
        params.bodyAccelerationX, params.bodyAccelerationY,
        params.taylorGreenForcingEnable ? 1 : 0,
        params.taylorGreenForcingAmplitude,
        params.taylorGreenForcingModeX,
        params.taylorGreenForcingModeY,
        permeabilityEnabled0493x15c ? 1 : 0,
        permeabilityEnabled0493x15c ? slab0493x15c.xPlane : 0.0);
    check_cuda_0245(cudaGetLastError(), "periodic_force_stream_kernel_0245 launch");
    if (!asyncResident0271 || permeabilityEnabled0493x15c) {
        check_cuda_0245(cudaDeviceSynchronize(), "periodic_force_stream_kernel_0245 synchronize");
    }
    if (permeabilityEnabled0493x15c) {
        const ChiSlabCrossingStep0493x15c cross0493x15c = read_chi_slab_crossing_0493x15c(true);
        append_chi_permeability_csv_0493x15c(params, step, slab0493x15c, cross0493x15c);
    }
    const auto tAfterKernel = Clock::now();

    if (downloadAll) {
        gpuState.download_active_prefix(state, &particleDiag);
    }
    cuda_shared_particle_state_0251_mark_fresh("streaming_periodic_0245");
    const auto tAfterDownload = Clock::now();

    diag.handled = true;
    diag.applied = true;
    diag.fluidParticles = nActiveFluid;
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
