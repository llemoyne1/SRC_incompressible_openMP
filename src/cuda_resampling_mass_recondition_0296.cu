#include "cuda_resampling_mass_recondition_0296.h"

#if defined(MPCD_ENABLE_CUDA_RESAMPLING) && \
    defined(MPCD_ENABLE_CUDA_PARTICLE_STATE) && \
    defined(MPCD_ENABLE_CUDA_CELL_WORKSPACE) && \
    defined(MPCD_ENABLE_CUDA_CELL_MOMENTS)

#include "cuda_cell_moments.h"
#include "cuda_cell_workspace.h"
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
#include <vector>

namespace mpcd {
namespace {

using Clock = std::chrono::steady_clock;

struct DeviceMassReconditionConfig0296 {
    int nx = 0;
    int ny = 0;
    int numCells = 0;
    double lx = 1.0;
    double ly = 1.0;
    double dx = 1.0;
    double dy = 1.0;

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

    double strength = 1.0;
};

struct DeviceBuffers0296 {
    double* dDeltaPx = nullptr;
    double* dDeltaPy = nullptr;
    unsigned int* dCellChanged = nullptr;
    unsigned long long* dCounters = nullptr; // [0] particles, [1] cells
    double* dMaxRelChange = nullptr;
    int cellCapacity = 0;

    ~DeviceBuffers0296() { release(); }

    void release() {
        if (dDeltaPx) cudaFree(dDeltaPx);
        if (dDeltaPy) cudaFree(dDeltaPy);
        if (dCellChanged) cudaFree(dCellChanged);
        if (dCounters) cudaFree(dCounters);
        if (dMaxRelChange) cudaFree(dMaxRelChange);
        dDeltaPx = nullptr;
        dDeltaPy = nullptr;
        dCellChanged = nullptr;
        dCounters = nullptr;
        dMaxRelChange = nullptr;
        cellCapacity = 0;
    }

    void ensure(int numCells) {
        if (numCells <= cellCapacity && dDeltaPx && dDeltaPy && dCellChanged && dCounters && dMaxRelChange) return;
        release();
        if (numCells <= 0) return;
        cudaError_t err = cudaMalloc(reinterpret_cast<void**>(&dDeltaPx), sizeof(double) * static_cast<std::size_t>(numCells));
        if (err != cudaSuccess) throw std::runtime_error(std::string("cuda_resampling_mass_recondition_0296: malloc deltaPx: ") + cudaGetErrorString(err));
        err = cudaMalloc(reinterpret_cast<void**>(&dDeltaPy), sizeof(double) * static_cast<std::size_t>(numCells));
        if (err != cudaSuccess) throw std::runtime_error(std::string("cuda_resampling_mass_recondition_0296: malloc deltaPy: ") + cudaGetErrorString(err));
        err = cudaMalloc(reinterpret_cast<void**>(&dCellChanged), sizeof(unsigned int) * static_cast<std::size_t>(numCells));
        if (err != cudaSuccess) throw std::runtime_error(std::string("cuda_resampling_mass_recondition_0296: malloc changed flags: ") + cudaGetErrorString(err));
        err = cudaMalloc(reinterpret_cast<void**>(&dCounters), sizeof(unsigned long long) * 2u);
        if (err != cudaSuccess) throw std::runtime_error(std::string("cuda_resampling_mass_recondition_0296: malloc counters: ") + cudaGetErrorString(err));
        err = cudaMalloc(reinterpret_cast<void**>(&dMaxRelChange), sizeof(double));
        if (err != cudaSuccess) throw std::runtime_error(std::string("cuda_resampling_mass_recondition_0296: malloc max rel change: ") + cudaGetErrorString(err));
        cellCapacity = numCells;
    }
};

thread_local CudaCellWorkspace g_massReconditionWorkspace0296;
thread_local DeviceBuffers0296 g_massReconditionBuffers0296;

inline double seconds_between(const Clock::time_point a, const Clock::time_point b) {
    return std::chrono::duration<double>(b - a).count();
}

void cuda_check_0296(cudaError_t err, const char* context) {
    if (err != cudaSuccess) {
        throw std::runtime_error(std::string("cuda_resampling_mass_recondition_0296: ") +
                                 context + ": " + cudaGetErrorString(err));
    }
}

bool env_truthy_0296(const char* name) {
    const char* v = std::getenv(name);
    if (v == nullptr || *v == '\0') return false;
    std::string s(v);
    std::transform(s.begin(), s.end(), s.begin(), [](unsigned char c) {
        return static_cast<char>(std::tolower(c));
    });
    return !(s == "0" || s == "false" || s == "off" || s == "no");
}

int env_int_0296(const char* name, int fallback) {
    const char* v = std::getenv(name);
    if (v == nullptr || *v == '\0') return fallback;
    try {
        return std::stoi(v);
    } catch (...) {
        return fallback;
    }
}

double env_double_0296(const char* name, double fallback) {
    const char* v = std::getenv(name);
    if (v == nullptr || *v == '\0') return fallback;
    try {
        return std::stod(v);
    } catch (...) {
        return fallback;
    }
}

std::string csv_escape_0296(const std::string& s) {
    if (s.find_first_of(",\"\n\r") == std::string::npos) return s;
    std::string out = "\"";
    for (const char ch : s) {
        if (ch == '"') out += "\"\"";
        else out += ch;
    }
    out += "\"";
    return out;
}

__device__ inline double atomic_add_double_compat_0296(double* address, double value) {
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

__device__ inline void atomic_max_double_positive_0296(double* address, double value) {
    auto* addressAsUll = reinterpret_cast<unsigned long long int*>(address);
    unsigned long long int old = *addressAsUll;
    unsigned long long int assumed;
    do {
        assumed = old;
        if (__longlong_as_double(assumed) >= value) return;
        old = atomicCAS(addressAsUll, assumed, __double_as_longlong(value));
    } while (assumed != old);
}

__device__ bool point_inside_active_domain_0296(double x, double y, DeviceMassReconditionConfig0296 cfg) {
    if (x < cfg.domainXMin || x > cfg.domainXMax || y < cfg.domainYMin || y > cfg.domainYMax) {
        return false;
    }
    if (cfg.solidShape == 1) {
        const double dx = x - cfg.circleCx;
        const double dy = y - cfg.circleCy;
        return dx * dx + dy * dy >= cfg.circleR * cfg.circleR;
    }
    if (cfg.solidShape == 2) {
        const bool insideRect = x >= cfg.rectXMin && x <= cfg.rectXMax &&
                                y >= cfg.rectYMin && y <= cfg.rectYMax;
        return !insideRect;
    }
    return true;
}

__global__ void reset_mass_recondition_buffers_kernel_0296(
    int numCells,
    double* __restrict__ deltaPx,
    double* __restrict__ deltaPy,
    unsigned int* __restrict__ cellChanged,
    unsigned long long* __restrict__ counters,
    double* __restrict__ maxRelChange) {
    const int c = blockIdx.x * blockDim.x + threadIdx.x;
    if (c < numCells) {
        deltaPx[c] = 0.0;
        deltaPy[c] = 0.0;
        cellChanged[c] = 0u;
    }
    if (c == 0) {
        counters[0] = 0ull;
        counters[1] = 0ull;
        *maxRelChange = 0.0;
    }
}

__global__ void recondition_particle_masses_kernel_0296(
    int nParticles,
    double* __restrict__ x,
    double* __restrict__ y,
    double* __restrict__ vx,
    double* __restrict__ vy,
    double* __restrict__ mass,
    const unsigned char* __restrict__ role,
    const int* __restrict__ cellId,
    const unsigned int* __restrict__ cellCount,
    const double* __restrict__ cellMass,
    DeviceMassReconditionConfig0296 cfg,
    double* __restrict__ deltaPx,
    double* __restrict__ deltaPy,
    unsigned int* __restrict__ cellChanged,
    unsigned long long* __restrict__ counters,
    double* __restrict__ maxRelChange) {
    const int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= nParticles) return;
    if (role && role[i] != static_cast<unsigned char>(kParticleRoleFluid)) return;
    const int c = cellId[i];
    if (c < 0 || c >= cfg.numCells) return;
    const unsigned int n = cellCount[c];
    if (n <= 1u) return;
    if (!point_inside_active_domain_0296(x[i], y[i], cfg)) return;
    const double M = cellMass[c];
    if (!(M > 0.0)) return;
    const double oldMass = mass[i];
    if (!(oldMass > 0.0)) return;
    const double targetMass = M / static_cast<double>(n);
    const double newMass = oldMass + cfg.strength * (targetMass - oldMass);
    if (!(newMass > 0.0) || !isfinite(newMass)) return;
    if (newMass == oldMass) return;
    mass[i] = newMass;
    const double dm = newMass - oldMass;
    const double rel = fabs(dm) / fmax(fabs(oldMass), 1.0e-300);
    atomic_max_double_positive_0296(maxRelChange, rel);
    atomic_add_double_compat_0296(&deltaPx[c], dm * vx[i]);
    atomic_add_double_compat_0296(&deltaPy[c], dm * vy[i]);
    cellChanged[c] = 1u;
    atomicAdd(&counters[0], 1ull);
}

__global__ void count_changed_cells_kernel_0296(
    int numCells,
    const unsigned int* __restrict__ cellChanged,
    unsigned long long* __restrict__ counters) {
    const int c = blockIdx.x * blockDim.x + threadIdx.x;
    if (c >= numCells) return;
    if (cellChanged[c] != 0u) {
        atomicAdd(&counters[1], 1ull);
    }
}

__global__ void restore_cell_momentum_kernel_0296(
    int nParticles,
    double* __restrict__ x,
    double* __restrict__ y,
    double* __restrict__ vx,
    double* __restrict__ vy,
    const double* __restrict__ mass,
    const unsigned char* __restrict__ role,
    const int* __restrict__ cellId,
    const double* __restrict__ cellMass,
    DeviceMassReconditionConfig0296 cfg,
    const double* __restrict__ deltaPx,
    const double* __restrict__ deltaPy) {
    const int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= nParticles) return;
    if (role && role[i] != static_cast<unsigned char>(kParticleRoleFluid)) return;
    const int c = cellId[i];
    if (c < 0 || c >= cfg.numCells) return;
    if (!point_inside_active_domain_0296(x[i], y[i], cfg)) return;
    const double M = cellMass[c];
    if (!(M > 0.0) || !(mass[i] > 0.0)) return;
    vx[i] += -deltaPx[c] / M;
    vy[i] += -deltaPy[c] / M;
}

DeviceMassReconditionConfig0296 make_config_0296(const SimulationParams& params,
                                                  const CellGrid& grid,
                                                  const FluidDomainBounds& domain,
                                                  double time,
                                                  double strength) {
    DeviceMassReconditionConfig0296 cfg{};
    cfg.nx = grid.Nx;
    cfg.ny = grid.Ny;
    cfg.numCells = grid.numCells;
    cfg.lx = grid.Lx;
    cfg.ly = grid.Ly;
    cfg.dx = grid.dx;
    cfg.dy = grid.dy;
    cfg.domainXMin = domain.xMin;
    cfg.domainXMax = domain.xMax;
    cfg.domainYMin = domain.yMin;
    cfg.domainYMax = domain.yMax;
    cfg.strength = std::clamp(strength, 0.0, 1.0);

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

void write_csv_row_0296(const SimulationParams& params,
                        CudaResamplingMassRecondition0296Diagnostics& d) {
    std::filesystem::create_directories(params.outputDir);
    const std::filesystem::path path = std::filesystem::path(params.outputDir) /
        "cuda_resampling_mass_recondition_0296.csv";
    const bool needHeader = !std::filesystem::exists(path) || std::filesystem::file_size(path) == 0u;
    std::ofstream out(path, std::ios::app);
    if (!out) return;
    d.outputCsv = path.string();
    if (needHeader) {
        out << "step,stage,handled,cudaAvailable,sharedStateFreshBefore,skippedBecauseStateNotFresh,"
               "particles,fluidParticlesBefore,fluidParticlesAfter,cells,wetCellsBefore,wetCellsAfter,"
               "appliedParticles,appliedCells,strength,totalMassBefore,totalMassAfter,totalPxBefore,totalPxAfter,totalPyBefore,totalPyAfter,"
               "maxAbsCellMassError,maxRelCellMassError,maxAbsCellMomentumError,maxRelCellMomentumError,maxParticleMassRelChange,"
               "depositBeforeSeconds,kernelSeconds,depositAfterSeconds,downloadSeconds,totalSeconds\n";
    }
    out << std::setprecision(17)
        << d.step << ','
        << csv_escape_0296(d.stage) << ','
        << (d.handled ? 1 : 0) << ','
        << (d.cudaAvailable ? 1 : 0) << ','
        << (d.sharedStateFreshBefore ? 1 : 0) << ','
        << (d.skippedBecauseStateNotFresh ? 1 : 0) << ','
        << d.particles << ',' << d.fluidParticlesBefore << ',' << d.fluidParticlesAfter << ','
        << d.cells << ',' << d.wetCellsBefore << ',' << d.wetCellsAfter << ','
        << d.appliedParticles << ',' << d.appliedCells << ',' << d.strength << ','
        << d.totalMassBefore << ',' << d.totalMassAfter << ','
        << d.totalPxBefore << ',' << d.totalPxAfter << ','
        << d.totalPyBefore << ',' << d.totalPyAfter << ','
        << d.maxAbsCellMassError << ',' << d.maxRelCellMassError << ','
        << d.maxAbsCellMomentumError << ',' << d.maxRelCellMomentumError << ','
        << d.maxParticleMassRelChange << ','
        << d.depositBeforeSeconds << ',' << d.kernelSeconds << ','
        << d.depositAfterSeconds << ',' << d.downloadSeconds << ',' << d.totalSeconds << '\n';
}

void accumulate_global_diagnostics_0296(const CudaCellMoments& m,
                                        std::uint64_t& fluid,
                                        std::uint64_t& wet,
                                        double& mass,
                                        double& px,
                                        double& py) {
    fluid = 0u;
    wet = 0u;
    mass = 0.0;
    px = 0.0;
    py = 0.0;
    const std::size_t n = m.cellCount.size();
    for (std::size_t c = 0; c < n; ++c) {
        const std::uint32_t cnt = m.cellCount[c];
        fluid += static_cast<std::uint64_t>(cnt);
        if (cnt > 0u) ++wet;
        mass += m.cellMass[c];
        px += m.cellPx[c];
        py += m.cellPy[c];
    }
}

void compare_before_after_0296(const CudaCellMoments& before,
                               const CudaCellMoments& after,
                               CudaResamplingMassRecondition0296Diagnostics& d) {
    const std::size_t n = std::min(before.cellCount.size(), after.cellCount.size());
    for (std::size_t c = 0; c < n; ++c) {
        if (before.cellCount[c] == 0u && after.cellCount[c] == 0u) continue;
        const double dm = after.cellMass[c] - before.cellMass[c];
        const double dpx = after.cellPx[c] - before.cellPx[c];
        const double dpy = after.cellPy[c] - before.cellPy[c];
        const double massDen = std::max(1.0, std::abs(before.cellMass[c]));
        const double momDen = std::max(1.0, std::hypot(before.cellPx[c], before.cellPy[c]));
        d.maxAbsCellMassError = std::max(d.maxAbsCellMassError, std::abs(dm));
        d.maxRelCellMassError = std::max(d.maxRelCellMassError, std::abs(dm) / massDen);
        d.maxAbsCellMomentumError = std::max(d.maxAbsCellMomentumError, std::hypot(dpx, dpy));
        d.maxRelCellMomentumError = std::max(d.maxRelCellMomentumError, std::hypot(dpx, dpy) / momDen);
    }
}

} // namespace

bool cuda_resampling_mass_recondition_0296_requested(std::uint64_t step) {
    if (!env_truthy_0296("MPCD_CUDA_RESAMPLING_MASS_RECONDITION_0296")) return false;
    const int every = std::max(1, env_int_0296("MPCD_CUDA_RESAMPLING_MASS_RECONDITION_0296_EVERY", 1));
    return (step % static_cast<std::uint64_t>(every)) == 0u;
}

CudaResamplingMassRecondition0296Diagnostics try_apply_cuda_resampling_mass_recondition_0296(
    ParticleState& hostMirror,
    const SimulationParams& params,
    const CellGrid& grid,
    const FluidDomainBounds& domain,
    std::uint64_t step,
    double time,
    const char* stage) {
    CudaResamplingMassRecondition0296Diagnostics d{};
    d.attempted = true;
    d.step = step;
    d.stage = stage != nullptr ? stage : "post_src_mass_recondition";
    d.particles = hostMirror.Np;
    d.cells = static_cast<std::uint64_t>(std::max(0, grid.numCells));
    d.strength = std::clamp(env_double_0296("MPCD_CUDA_RESAMPLING_MASS_RECONDITION_0296_STRENGTH", 1.0), 0.0, 1.0);
    const Clock::time_point t0 = Clock::now();

    d.cudaAvailable = cuda_cell_moments_available();
    if (!d.cudaAvailable || d.strength <= 0.0) {
        d.handled = d.cudaAvailable;
        d.totalSeconds = seconds_between(t0, Clock::now());
        write_csv_row_0296(params, d);
        return d;
    }
    if (grid.Nx <= 0 || grid.Ny <= 0 || grid.numCells != grid.Nx * grid.Ny) {
        throw std::runtime_error("cuda_resampling_mass_recondition_0296: invalid grid");
    }

    d.sharedStateFreshBefore = cuda_shared_particle_state_0251_is_fresh();
    if (!d.sharedStateFreshBefore) {
        // 0296 is mutating.  Unlike the passive 0295 survey, it must never infer
        // authority from a stale host mirror in resident CUDA cases.  The first
        // version therefore applies only when the shared CUDA particle state is
        // explicitly fresh.  CPU/Q6-host handoff can be enabled later with an
        // explicit upload+download contract.
        d.skippedBecauseStateNotFresh = true;
        d.totalSeconds = seconds_between(t0, Clock::now());
        write_csv_row_0296(params, d);
        return d;
    }

    CudaParticleState& gpuState = cuda_shared_particle_state_0251();
    CudaCellWorkspaceDiagnostics workspaceDiag{};
    g_massReconditionWorkspace0296.ensure_capacity(hostMirror.Np, grid.numCells, &workspaceDiag);

    CudaCellMomentsOptions options{};
    options.threadsPerBlock = std::max(32, env_int_0296("MPCD_CUDA_RESAMPLING_MASS_RECONDITION_0296_THREADS", 256));
    options.reuseDeviceBuffers = true;
    options.computeCellVelocities = true;
    options.downloadCellVelocities = true;
    options.enableAllFluidFastPath = false;
    options.enableUniformMassFastPath = false;

    CudaCellMoments before{};
    CudaCellMomentsDiagnostics beforeDiag{};
    cuda_deposit_cell_moments_atomic_from_persistent_state(
        hostMirror, gpuState, g_massReconditionWorkspace0296, grid, GridShift{}, params,
        before, &beforeDiag, options);
    d.depositBeforeSeconds = beforeDiag.totalSeconds + workspaceDiag.totalSeconds;
    accumulate_global_diagnostics_0296(before,
                                       d.fluidParticlesBefore,
                                       d.wetCellsBefore,
                                       d.totalMassBefore,
                                       d.totalPxBefore,
                                       d.totalPyBefore);

    g_massReconditionBuffers0296.ensure(grid.numCells);
    CudaCellWorkspaceDeviceView cv = g_massReconditionWorkspace0296.device_view();
    CudaParticleDeviceView pv = gpuState.device_view();
    if (cv.cellId == nullptr || cv.count == nullptr || cv.cellMass == nullptr ||
        pv.x == nullptr || pv.y == nullptr || pv.vx == nullptr || pv.vy == nullptr ||
        pv.mass == nullptr || pv.role == nullptr) {
        throw std::runtime_error("cuda_resampling_mass_recondition_0296: incomplete device views");
    }

    const DeviceMassReconditionConfig0296 cfg = make_config_0296(params, grid, domain, time, d.strength);
    const int block = options.threadsPerBlock;
    const int cellGrid = std::max(1, (grid.numCells + block - 1) / block);
    const int particleGrid = std::max(1, (static_cast<int>(hostMirror.Np) + block - 1) / block);

    const Clock::time_point tk0 = Clock::now();
    reset_mass_recondition_buffers_kernel_0296<<<cellGrid, block>>>(
        grid.numCells,
        g_massReconditionBuffers0296.dDeltaPx,
        g_massReconditionBuffers0296.dDeltaPy,
        g_massReconditionBuffers0296.dCellChanged,
        g_massReconditionBuffers0296.dCounters,
        g_massReconditionBuffers0296.dMaxRelChange);
    cuda_check_0296(cudaGetLastError(), "launch reset_mass_recondition_buffers_kernel_0296");
    recondition_particle_masses_kernel_0296<<<particleGrid, block>>>(
        static_cast<int>(hostMirror.Np),
        pv.x, pv.y, pv.vx, pv.vy, pv.mass, pv.role, cv.cellId, cv.count, cv.cellMass,
        cfg,
        g_massReconditionBuffers0296.dDeltaPx,
        g_massReconditionBuffers0296.dDeltaPy,
        g_massReconditionBuffers0296.dCellChanged,
        g_massReconditionBuffers0296.dCounters,
        g_massReconditionBuffers0296.dMaxRelChange);
    cuda_check_0296(cudaGetLastError(), "launch recondition_particle_masses_kernel_0296");
    restore_cell_momentum_kernel_0296<<<particleGrid, block>>>(
        static_cast<int>(hostMirror.Np),
        pv.x, pv.y, pv.vx, pv.vy, pv.mass, pv.role, cv.cellId, cv.cellMass,
        cfg,
        g_massReconditionBuffers0296.dDeltaPx,
        g_massReconditionBuffers0296.dDeltaPy);
    cuda_check_0296(cudaGetLastError(), "launch restore_cell_momentum_kernel_0296");
    count_changed_cells_kernel_0296<<<cellGrid, block>>>(
        grid.numCells,
        g_massReconditionBuffers0296.dCellChanged,
        g_massReconditionBuffers0296.dCounters);
    cuda_check_0296(cudaGetLastError(), "launch count_changed_cells_kernel_0296");
    cuda_check_0296(cudaDeviceSynchronize(), "synchronize mass recondition kernels");
    const Clock::time_point tk1 = Clock::now();
    d.kernelSeconds = seconds_between(tk0, tk1);

    unsigned long long hCounters[2] = {0ull, 0ull};
    double hMaxRelChange = 0.0;
    const Clock::time_point td0 = Clock::now();
    cuda_check_0296(cudaMemcpy(hCounters, g_massReconditionBuffers0296.dCounters,
                               sizeof(hCounters), cudaMemcpyDeviceToHost),
                    "copy counters D2H");
    cuda_check_0296(cudaMemcpy(&hMaxRelChange, g_massReconditionBuffers0296.dMaxRelChange,
                               sizeof(double), cudaMemcpyDeviceToHost),
                    "copy max rel change D2H");
    const Clock::time_point td1 = Clock::now();
    d.downloadSeconds = seconds_between(td0, td1);
    d.appliedParticles = static_cast<std::uint64_t>(hCounters[0]);
    d.appliedCells = static_cast<std::uint64_t>(hCounters[1]);
    d.maxParticleMassRelChange = hMaxRelChange;

    CudaCellMoments after{};
    CudaCellMomentsDiagnostics afterDiag{};
    cuda_deposit_cell_moments_atomic_from_persistent_state(
        hostMirror, gpuState, g_massReconditionWorkspace0296, grid, GridShift{}, params,
        after, &afterDiag, options);
    d.depositAfterSeconds = afterDiag.totalSeconds;
    accumulate_global_diagnostics_0296(after,
                                       d.fluidParticlesAfter,
                                       d.wetCellsAfter,
                                       d.totalMassAfter,
                                       d.totalPxAfter,
                                       d.totalPyAfter);
    compare_before_after_0296(before, after, d);

    d.handled = true;
    d.totalSeconds = seconds_between(t0, Clock::now());
    write_csv_row_0296(params, d);
    return d;
}

} // namespace mpcd

#endif
