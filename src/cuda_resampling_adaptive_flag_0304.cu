#include "cuda_resampling_adaptive_flag_0304.h"

#if defined(MPCD_ENABLE_CUDA_RESAMPLING) && defined(MPCD_ENABLE_CUDA_PARTICLE_STATE)

#include "cuda_particle_state.h"
#include "cuda_shared_particle_state_0251.h"
#include "immersed_solid.h"

#include <cuda_runtime.h>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cctype>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <limits>
#include <stdexcept>
#include <string>

namespace mpcd {
namespace {

using Clock = std::chrono::steady_clock;

struct DeviceFlagConfig0304 {
    int nx = 0;
    int ny = 0;
    int numCells = 0;
    double lx = 1.0;
    double ly = 1.0;
    double dx = 1.0;
    double dy = 1.0;
    int periodicX = 0;
    int periodicY = 0;

    double domainXMin = 0.0;
    double domainXMax = 1.0;
    double domainYMin = 0.0;
    double domainYMax = 1.0;

    int solidShape = 0; // 0 none, 1 circle, 2 rectangle.
    double circleCx = 0.0;
    double circleCy = 0.0;
    double circleR = 0.0;
    double rectXMin = 0.0;
    double rectXMax = 0.0;
    double rectYMin = 0.0;
    double rectYMax = 0.0;

    int triggerNMin = 6;
    int triggerEmpty = 1;
};

struct DeviceFlagStats0304 {
    unsigned int triggerFlag;
    unsigned int triggeredByLowN;
    unsigned int triggeredByEmpty;
    unsigned int activeCells;
    unsigned int wetCells;
    unsigned int emptyWetCells;
    unsigned int lowNCells;
    unsigned int fluidParticles;
    int minNWet;
    int maxNWet;
    double totalMass;
    double totalPx;
    double totalPy;
};

struct DeviceDepositBuffers0304 {
    std::size_t particleCapacity = 0u;
    std::size_t cellCapacity = 0u;
    unsigned int* d_count = nullptr;
    double* d_mass = nullptr;
    double* d_px = nullptr;
    double* d_py = nullptr;
    DeviceFlagStats0304* d_stats = nullptr;

    ~DeviceDepositBuffers0304() { release(); }

    void release() {
        if (d_count) cudaFree(d_count);
        if (d_mass) cudaFree(d_mass);
        if (d_px) cudaFree(d_px);
        if (d_py) cudaFree(d_py);
        if (d_stats) cudaFree(d_stats);
        d_count = nullptr;
        d_mass = nullptr;
        d_px = nullptr;
        d_py = nullptr;
        d_stats = nullptr;
        particleCapacity = 0u;
        cellCapacity = 0u;
    }

    void ensure(std::size_t /*n*/, std::size_t cells) {
        if (cells <= cellCapacity && d_stats != nullptr) return;
        release();
        cellCapacity = cells;
        cudaMalloc(reinterpret_cast<void**>(&d_count), cellCapacity * sizeof(unsigned int));
        cudaMalloc(reinterpret_cast<void**>(&d_mass), cellCapacity * sizeof(double));
        cudaMalloc(reinterpret_cast<void**>(&d_px), cellCapacity * sizeof(double));
        cudaMalloc(reinterpret_cast<void**>(&d_py), cellCapacity * sizeof(double));
        cudaMalloc(reinterpret_cast<void**>(&d_stats), sizeof(DeviceFlagStats0304));
    }
};

thread_local CudaParticleState g_privateParticleState0304;
thread_local DeviceDepositBuffers0304 g_buffers0304;

inline double seconds_between(Clock::time_point a, Clock::time_point b) {
    return std::chrono::duration<double>(b - a).count();
}

void cuda_check_0304(cudaError_t err, const char* context) {
    if (err != cudaSuccess) {
        throw std::runtime_error(std::string("cuda_resampling_adaptive_flag_0304: ") +
                                 context + ": " + cudaGetErrorString(err));
    }
}

bool env_truthy_0304(const char* name) {
    const char* v = std::getenv(name);
    if (v == nullptr || *v == '\0') return false;
    std::string s(v);
    std::transform(s.begin(), s.end(), s.begin(), [](unsigned char c) {
        return static_cast<char>(std::tolower(c));
    });
    return !(s == "0" || s == "false" || s == "off" || s == "no");
}

int env_int_0304(const char* name, int fallback) {
    const char* v = std::getenv(name);
    if (v == nullptr || *v == '\0') return fallback;
    try {
        return std::stoi(v);
    } catch (...) {
        return fallback;
    }
}

std::string csv_escape_0304(const std::string& s) {
    if (s.find_first_of(",\"\n\r") == std::string::npos) return s;
    std::string out = "\"";
    for (char ch : s) {
        if (ch == '"') out += "\"\"";
        else out += ch;
    }
    out += "\"";
    return out;
}

__device__ inline double atomic_add_double_compat_0304(double* address, double value) {
#if defined(__CUDA_ARCH__) && (__CUDA_ARCH__ >= 600)
    return atomicAdd(address, value);
#else
    auto* addressAsUll = reinterpret_cast<unsigned long long int*>(address);
    unsigned long long int old = *addressAsUll;
    unsigned long long int assumed;
    do {
        assumed = old;
        old = atomicCAS(addressAsUll,
                        assumed,
                        __double_as_longlong(value + __longlong_as_double(assumed)));
    } while (assumed != old);
    return __longlong_as_double(old);
#endif
}

__device__ double wrap_periodic_device_0304(double x, double L) {
    x = fmod(x, L);
    if (x < 0.0) x += L;
    if (x >= L) x -= L;
    return x;
}

__device__ int bounded_index_device_0304(double x, double L, double dx, int N) {
    if (x < 0.0) x = 0.0;
    if (x > L) x = L;
    int i = static_cast<int>(floor(x / dx));
    if (i < 0) i = 0;
    if (i >= N) i = N - 1;
    return i;
}

__device__ int periodic_index_device_0304(double x, double L, double dx, int N) {
    x = wrap_periodic_device_0304(x, L);
    int i = static_cast<int>(floor(x / dx));
    if (i < 0) i = 0;
    if (i >= N) i = N - 1;
    return i;
}

__device__ int cell_index_physical_0304(double x, double y, const DeviceFlagConfig0304 cfg) {
    const int ix = cfg.periodicX ? periodic_index_device_0304(x, cfg.lx, cfg.dx, cfg.nx)
                                 : bounded_index_device_0304(x, cfg.lx, cfg.dx, cfg.nx);
    const int iy = cfg.periodicY ? periodic_index_device_0304(y, cfg.ly, cfg.dy, cfg.ny)
                                 : bounded_index_device_0304(y, cfg.ly, cfg.dy, cfg.ny);
    return ix + cfg.nx * iy;
}

__device__ bool active_cell_center_0304(int ix, int iy, const DeviceFlagConfig0304 cfg) {
    const double x = (static_cast<double>(ix) + 0.5) * cfg.dx;
    const double y = (static_cast<double>(iy) + 0.5) * cfg.dy;
    if (x < cfg.domainXMin || x > cfg.domainXMax || y < cfg.domainYMin || y > cfg.domainYMax) {
        return false;
    }
    if (cfg.solidShape == 1) {
        const double dx = x - cfg.circleCx;
        const double dy = y - cfg.circleCy;
        return dx * dx + dy * dy >= cfg.circleR * cfg.circleR;
    }
    if (cfg.solidShape == 2) {
        const bool inside = x >= cfg.rectXMin && x <= cfg.rectXMax &&
                            y >= cfg.rectYMin && y <= cfg.rectYMax;
        return !inside;
    }
    return true;
}

__global__ void reset_adaptive_flag_deposit_kernel_0304(
    int numCells,
    unsigned int* count,
    double* mass,
    double* px,
    double* py,
    DeviceFlagStats0304* stats) {
    const int tid = blockIdx.x * blockDim.x + threadIdx.x;
    for (int c = tid; c < numCells; c += blockDim.x * gridDim.x) {
        count[c] = 0u;
        mass[c] = 0.0;
        px[c] = 0.0;
        py[c] = 0.0;
    }
    if (tid == 0) {
        stats->triggerFlag = 0u;
        stats->triggeredByLowN = 0u;
        stats->triggeredByEmpty = 0u;
        stats->activeCells = 0u;
        stats->wetCells = 0u;
        stats->emptyWetCells = 0u;
        stats->lowNCells = 0u;
        stats->fluidParticles = 0u;
        stats->minNWet = 2147483647;
        stats->maxNWet = 0;
        stats->totalMass = 0.0;
        stats->totalPx = 0.0;
        stats->totalPy = 0.0;
    }
}

__global__ void deposit_adaptive_flag_moments_kernel_0304(
    int nParticles,
    const double* __restrict__ x,
    const double* __restrict__ y,
    const double* __restrict__ vx,
    const double* __restrict__ vy,
    const double* __restrict__ particleMass,
    const unsigned char* __restrict__ role,
    DeviceFlagConfig0304 cfg,
    unsigned int* __restrict__ count,
    double* __restrict__ mass,
    double* __restrict__ px,
    double* __restrict__ py) {
    const int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= nParticles) return;
    if (role && role[i] != static_cast<unsigned char>(kParticleRoleFluid)) return;
    const int c = cell_index_physical_0304(x[i], y[i], cfg);
    const double m = particleMass[i];
    atomicAdd(&count[c], 1u);
    atomic_add_double_compat_0304(&mass[c], m);
    atomic_add_double_compat_0304(&px[c], m * vx[i]);
    atomic_add_double_compat_0304(&py[c], m * vy[i]);
}

__global__ void classify_adaptive_flag_cells_kernel_0304(
    const unsigned int* __restrict__ count,
    const double* __restrict__ mass,
    const double* __restrict__ px,
    const double* __restrict__ py,
    DeviceFlagConfig0304 cfg,
    DeviceFlagStats0304* stats) {
    const int c = blockIdx.x * blockDim.x + threadIdx.x;
    if (c >= cfg.numCells) return;
    const int ix = c % cfg.nx;
    const int iy = c / cfg.nx;
    if (!active_cell_center_0304(ix, iy, cfg)) return;

    atomicAdd(&stats->activeCells, 1u);
    const unsigned int n = count[c];
    if (n == 0u) {
        atomicAdd(&stats->emptyWetCells, 1u);
        if (cfg.triggerEmpty) {
            atomicExch(&stats->triggerFlag, 1u);
            atomicExch(&stats->triggeredByEmpty, 1u);
        }
        return;
    }

    atomicAdd(&stats->wetCells, 1u);
    atomicAdd(&stats->fluidParticles, n);
    atomicMin(&stats->minNWet, static_cast<int>(n));
    atomicMax(&stats->maxNWet, static_cast<int>(n));
    atomic_add_double_compat_0304(&stats->totalMass, mass[c]);
    atomic_add_double_compat_0304(&stats->totalPx, px[c]);
    atomic_add_double_compat_0304(&stats->totalPy, py[c]);

    if (cfg.triggerNMin > 0 && static_cast<int>(n) <= cfg.triggerNMin) {
        atomicAdd(&stats->lowNCells, 1u);
        atomicExch(&stats->triggerFlag, 1u);
        atomicExch(&stats->triggeredByLowN, 1u);
    }
}

bool periodic_x_0304(const SimulationParams& params) {
    return params.bcLeft == "periodic" && params.bcRight == "periodic";
}

bool periodic_y_0304(const SimulationParams& params) {
    return params.bcBottom == "periodic" && params.bcTop == "periodic";
}

DeviceFlagConfig0304 make_config_0304(const SimulationParams& params,
                                      const CellGrid& grid,
                                      const FluidDomainBounds& domain,
                                      double time) {
    DeviceFlagConfig0304 cfg{};
    cfg.nx = grid.Nx;
    cfg.ny = grid.Ny;
    cfg.numCells = grid.numCells;
    cfg.lx = grid.Lx;
    cfg.ly = grid.Ly;
    cfg.dx = grid.dx;
    cfg.dy = grid.dy;
    cfg.periodicX = periodic_x_0304(params) ? 1 : 0;
    cfg.periodicY = periodic_y_0304(params) ? 1 : 0;
    cfg.domainXMin = domain.xMin;
    cfg.domainXMax = domain.xMax;
    cfg.domainYMin = domain.yMin;
    cfg.domainYMax = domain.yMax;
    cfg.triggerNMin = std::max(0, env_int_0304("MPCD_CUDA_RESAMPLING_ADAPTIVE_FLAG_0304_TRIGGER_NMIN", 6));
    cfg.triggerEmpty = env_truthy_0304("MPCD_CUDA_RESAMPLING_ADAPTIVE_FLAG_0304_TRIGGER_EMPTY") ? 1 : 0;

    if (immersed_solid_enabled(params)) {
        const ImmersedSolidShape shape = immersed_solid_shape(params);
        if (shape == ImmersedSolidShape::Circle) {
            cfg.solidShape = 1;
            immersed_solid_circle_center(params, time, cfg.circleCx, cfg.circleCy);
            cfg.circleR = params.immersedSolidR;
        } else if (shape == ImmersedSolidShape::Rectangle) {
            cfg.solidShape = 2;
            immersed_solid_rectangle_bounds(params, time,
                                            cfg.rectXMin, cfg.rectXMax,
                                            cfg.rectYMin, cfg.rectYMax);
        }
    }
    return cfg;
}

void write_csv_row_0304(const SimulationParams& params,
                        CudaResamplingAdaptiveFlag0304Diagnostics& d) {
    std::filesystem::create_directories(params.outputDir);
    const std::filesystem::path path = std::filesystem::path(params.outputDir) /
        "cuda_resampling_adaptive_flag_0304.csv";
    const bool needHeader = !std::filesystem::exists(path) || std::filesystem::file_size(path) == 0u;
    std::ofstream out(path, std::ios::app);
    if (!out) return;
    d.outputCsv = path.string();
    if (needHeader) {
        out << "step,stage,handled,cudaAvailable,sharedStateFreshBefore,uploadedHostState,authoritativeDeviceState,"
               "triggerFlag,triggeredByLowN,triggeredByEmpty,triggerNMin,triggerEmpty,"
               "particles,cells,activeCells,wetCells,emptyWetCells,lowNCells,fluidParticles,minNWet,maxNWet,"
               "totalMass,totalPx,totalPy,uploadSeconds,depositKernelSeconds,flagKernelSeconds,downloadSeconds,totalSeconds\n";
    }
    out << std::setprecision(17)
        << d.step << ','
        << csv_escape_0304(d.stage) << ','
        << (d.handled ? 1 : 0) << ','
        << (d.cudaAvailable ? 1 : 0) << ','
        << (d.sharedStateFreshBefore ? 1 : 0) << ','
        << (d.uploadedHostState ? 1 : 0) << ','
        << (d.authoritativeDeviceState ? 1 : 0) << ','
        << (d.triggerFlag ? 1 : 0) << ','
        << (d.triggeredByLowN ? 1 : 0) << ','
        << (d.triggeredByEmpty ? 1 : 0) << ','
        << d.triggerNMin << ',' << d.triggerEmpty << ','
        << d.particles << ',' << d.cells << ',' << d.activeCells << ',' << d.wetCells << ','
        << d.emptyWetCells << ',' << d.lowNCells << ',' << d.fluidParticles << ','
        << d.minNWet << ',' << d.maxNWet << ','
        << d.totalMass << ',' << d.totalPx << ',' << d.totalPy << ','
        << d.uploadSeconds << ',' << d.depositKernelSeconds << ',' << d.flagKernelSeconds << ','
        << d.downloadSeconds << ',' << d.totalSeconds << '\n';
}

} // namespace

bool cuda_resampling_adaptive_flag_0304_requested(std::uint64_t step) {
    if (!env_truthy_0304("MPCD_CUDA_RESAMPLING_ADAPTIVE_FLAG_0304")) return false;
    const int every = std::max(1, env_int_0304("MPCD_CUDA_RESAMPLING_ADAPTIVE_FLAG_0304_EVERY", 1));
    return (step % static_cast<std::uint64_t>(every)) == 0u;
}

CudaResamplingAdaptiveFlag0304Diagnostics try_run_cuda_resampling_adaptive_flag_0304(
    const ParticleState& hostMirror,
    const SimulationParams& params,
    const CellGrid& grid,
    const FluidDomainBounds& domain,
    std::uint64_t step,
    double time,
    const char* stage) {
    CudaResamplingAdaptiveFlag0304Diagnostics d{};
    d.attempted = true;
    d.step = step;
    d.stage = stage != nullptr ? stage : "post_src_adaptive_flag";
    d.particles = hostMirror.Np;
    d.cells = static_cast<std::uint64_t>(grid.numCells);
    const Clock::time_point t0 = Clock::now();

    int deviceCount = 0;
    const cudaError_t deviceErr = cudaGetDeviceCount(&deviceCount);
    d.cudaAvailable = (deviceErr == cudaSuccess && deviceCount > 0);
    if (!d.cudaAvailable) {
        cudaGetLastError();
        write_csv_row_0304(params, d);
        return d;
    }
    if (grid.Nx <= 0 || grid.Ny <= 0 || grid.numCells != grid.Nx * grid.Ny) {
        throw std::runtime_error("cuda_resampling_adaptive_flag_0304: invalid grid");
    }

    d.sharedStateFreshBefore = cuda_shared_particle_state_0251_is_fresh();
    CudaParticleState* particleState = &cuda_shared_particle_state_0251();
    if (d.sharedStateFreshBefore) {
        d.authoritativeDeviceState = true;
    } else {
        CudaParticleStateDiagnostics uploadDiag{};
        g_privateParticleState0304.upload_all(hostMirror, &uploadDiag);
        particleState = &g_privateParticleState0304;
        d.uploadedHostState = true;
        d.uploadSeconds = uploadDiag.allocateSeconds + uploadDiag.uploadSeconds;
    }

    if (particleState->size() != hostMirror.Np) {
        throw std::runtime_error("cuda_resampling_adaptive_flag_0304: particle state size mismatch");
    }
    CudaParticleDeviceView pv = particleState->device_view();
    if (pv.x == nullptr || pv.y == nullptr || pv.vx == nullptr || pv.vy == nullptr ||
        pv.mass == nullptr || pv.role == nullptr) {
        throw std::runtime_error("cuda_resampling_adaptive_flag_0304: incomplete particle device view");
    }

    g_buffers0304.ensure(static_cast<std::size_t>(hostMirror.Np), static_cast<std::size_t>(grid.numCells));

    const DeviceFlagConfig0304 cfg = make_config_0304(params, grid, domain, time);
    d.triggerNMin = cfg.triggerNMin;
    d.triggerEmpty = cfg.triggerEmpty;

    const int block = std::max(32, env_int_0304("MPCD_CUDA_RESAMPLING_ADAPTIVE_FLAG_0304_THREADS", 256));
    const int particleGrid = std::max(1, (static_cast<int>(hostMirror.Np) + block - 1) / block);
    const int cellGrid = std::max(1, (grid.numCells + block - 1) / block);

    const Clock::time_point tk0 = Clock::now();
    reset_adaptive_flag_deposit_kernel_0304<<<cellGrid, block>>>(
        grid.numCells, g_buffers0304.d_count, g_buffers0304.d_mass,
        g_buffers0304.d_px, g_buffers0304.d_py, g_buffers0304.d_stats);
    cuda_check_0304(cudaGetLastError(), "launch reset_adaptive_flag_deposit_kernel_0304");
    deposit_adaptive_flag_moments_kernel_0304<<<particleGrid, block>>>(
        static_cast<int>(hostMirror.Np), pv.x, pv.y, pv.vx, pv.vy, pv.mass, pv.role, cfg,
        g_buffers0304.d_count, g_buffers0304.d_mass, g_buffers0304.d_px, g_buffers0304.d_py);
    cuda_check_0304(cudaGetLastError(), "launch deposit_adaptive_flag_moments_kernel_0304");
    cuda_check_0304(cudaDeviceSynchronize(), "synchronize adaptive flag deposit");
    const Clock::time_point tk1 = Clock::now();
    d.depositKernelSeconds = seconds_between(tk0, tk1);

    const Clock::time_point tf0 = Clock::now();
    classify_adaptive_flag_cells_kernel_0304<<<cellGrid, block>>>(
        g_buffers0304.d_count, g_buffers0304.d_mass, g_buffers0304.d_px, g_buffers0304.d_py,
        cfg, g_buffers0304.d_stats);
    cuda_check_0304(cudaGetLastError(), "launch classify_adaptive_flag_cells_kernel_0304");
    cuda_check_0304(cudaDeviceSynchronize(), "synchronize adaptive flag classify");
    const Clock::time_point tf1 = Clock::now();
    d.flagKernelSeconds = seconds_between(tf0, tf1);

    DeviceFlagStats0304 hs{};
    const Clock::time_point td0 = Clock::now();
    cuda_check_0304(cudaMemcpy(&hs, g_buffers0304.d_stats, sizeof(DeviceFlagStats0304), cudaMemcpyDeviceToHost),
                    "copy adaptive flag stats D2H");
    const Clock::time_point td1 = Clock::now();
    d.downloadSeconds = seconds_between(td0, td1);

    d.triggerFlag = hs.triggerFlag != 0u;
    d.triggeredByLowN = hs.triggeredByLowN != 0u;
    d.triggeredByEmpty = hs.triggeredByEmpty != 0u;
    d.activeCells = hs.activeCells;
    d.wetCells = hs.wetCells;
    d.emptyWetCells = hs.emptyWetCells;
    d.lowNCells = hs.lowNCells;
    d.fluidParticles = hs.fluidParticles;
    d.minNWet = hs.wetCells > 0u && hs.minNWet != 2147483647 ? hs.minNWet : 0;
    d.maxNWet = hs.maxNWet;
    d.totalMass = hs.totalMass;
    d.totalPx = hs.totalPx;
    d.totalPy = hs.totalPy;
    d.handled = true;
    d.totalSeconds = seconds_between(t0, Clock::now());
    write_csv_row_0304(params, d);
    return d;
}

} // namespace mpcd

#endif
