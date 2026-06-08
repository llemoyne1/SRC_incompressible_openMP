#include "cuda_resampling_population_guard_0297.h"

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
constexpr unsigned int kInvalidParticle0297 = 0xffffffffu;

struct DevicePopulationGuardConfig0297 {
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

    int nMin = 0;
    int nTarget = 0;
    int nMax = 0;
    double splitFraction = 0.5;
    double minDonorMassAfterSplit = 1.0e-12;
};

struct DeviceBuffers0297 {
    unsigned int* dPoorCells = nullptr;
    unsigned int* dRichCells = nullptr;
    unsigned int* dPoorCount = nullptr;
    unsigned int* dRichCount = nullptr;
    unsigned int* dInactiveList = nullptr;
    unsigned int* dInactiveCount = nullptr;
    unsigned int* dInactiveCursor = nullptr;
    unsigned int* dPoorDonor = nullptr;
    unsigned int* dRichKeep = nullptr;
    unsigned int* dRichExtract = nullptr;
    unsigned long long* dCounters = nullptr; // 0 merge, 1 split, 2 noInactive, 3 noDonor, 4 noPair
    int cellCapacity = 0;
    std::uint64_t particleCapacity = 0u;

    ~DeviceBuffers0297() { release(); }

    void release() {
        if (dPoorCells) cudaFree(dPoorCells);
        if (dRichCells) cudaFree(dRichCells);
        if (dPoorCount) cudaFree(dPoorCount);
        if (dRichCount) cudaFree(dRichCount);
        if (dInactiveList) cudaFree(dInactiveList);
        if (dInactiveCount) cudaFree(dInactiveCount);
        if (dInactiveCursor) cudaFree(dInactiveCursor);
        if (dPoorDonor) cudaFree(dPoorDonor);
        if (dRichKeep) cudaFree(dRichKeep);
        if (dRichExtract) cudaFree(dRichExtract);
        if (dCounters) cudaFree(dCounters);
        dPoorCells = nullptr;
        dRichCells = nullptr;
        dPoorCount = nullptr;
        dRichCount = nullptr;
        dInactiveList = nullptr;
        dInactiveCount = nullptr;
        dInactiveCursor = nullptr;
        dPoorDonor = nullptr;
        dRichKeep = nullptr;
        dRichExtract = nullptr;
        dCounters = nullptr;
        cellCapacity = 0;
        particleCapacity = 0u;
    }

    void ensure(int numCells, std::uint64_t nParticles) {
        if (numCells <= cellCapacity && nParticles <= particleCapacity && dPoorCells && dRichCells &&
            dPoorCount && dRichCount && dInactiveList && dInactiveCount && dInactiveCursor && dPoorDonor &&
            dRichKeep && dRichExtract && dCounters) {
            return;
        }
        release();
        if (numCells <= 0 || nParticles == 0u) return;
        cudaError_t err = cudaSuccess;
        err = cudaMalloc(reinterpret_cast<void**>(&dPoorCells), sizeof(unsigned int) * static_cast<std::size_t>(numCells));
        if (err != cudaSuccess) throw std::runtime_error(std::string("cuda_resampling_population_guard_0297: malloc poor cells: ") + cudaGetErrorString(err));
        err = cudaMalloc(reinterpret_cast<void**>(&dRichCells), sizeof(unsigned int) * static_cast<std::size_t>(numCells));
        if (err != cudaSuccess) throw std::runtime_error(std::string("cuda_resampling_population_guard_0297: malloc rich cells: ") + cudaGetErrorString(err));
        err = cudaMalloc(reinterpret_cast<void**>(&dPoorCount), sizeof(unsigned int));
        if (err != cudaSuccess) throw std::runtime_error(std::string("cuda_resampling_population_guard_0297: malloc poor count: ") + cudaGetErrorString(err));
        err = cudaMalloc(reinterpret_cast<void**>(&dRichCount), sizeof(unsigned int));
        if (err != cudaSuccess) throw std::runtime_error(std::string("cuda_resampling_population_guard_0297: malloc rich count: ") + cudaGetErrorString(err));
        err = cudaMalloc(reinterpret_cast<void**>(&dInactiveList), sizeof(unsigned int) * static_cast<std::size_t>(nParticles));
        if (err != cudaSuccess) throw std::runtime_error(std::string("cuda_resampling_population_guard_0297: malloc inactive list: ") + cudaGetErrorString(err));
        err = cudaMalloc(reinterpret_cast<void**>(&dInactiveCount), sizeof(unsigned int));
        if (err != cudaSuccess) throw std::runtime_error(std::string("cuda_resampling_population_guard_0297: malloc inactive count: ") + cudaGetErrorString(err));
        err = cudaMalloc(reinterpret_cast<void**>(&dInactiveCursor), sizeof(unsigned int));
        if (err != cudaSuccess) throw std::runtime_error(std::string("cuda_resampling_population_guard_0297: malloc inactive cursor: ") + cudaGetErrorString(err));
        err = cudaMalloc(reinterpret_cast<void**>(&dPoorDonor), sizeof(unsigned int) * static_cast<std::size_t>(numCells));
        if (err != cudaSuccess) throw std::runtime_error(std::string("cuda_resampling_population_guard_0297: malloc poor donor: ") + cudaGetErrorString(err));
        err = cudaMalloc(reinterpret_cast<void**>(&dRichKeep), sizeof(unsigned int) * static_cast<std::size_t>(numCells));
        if (err != cudaSuccess) throw std::runtime_error(std::string("cuda_resampling_population_guard_0297: malloc rich keep: ") + cudaGetErrorString(err));
        err = cudaMalloc(reinterpret_cast<void**>(&dRichExtract), sizeof(unsigned int) * static_cast<std::size_t>(numCells));
        if (err != cudaSuccess) throw std::runtime_error(std::string("cuda_resampling_population_guard_0297: malloc rich extract: ") + cudaGetErrorString(err));
        err = cudaMalloc(reinterpret_cast<void**>(&dCounters), sizeof(unsigned long long) * 5u);
        if (err != cudaSuccess) throw std::runtime_error(std::string("cuda_resampling_population_guard_0297: malloc counters: ") + cudaGetErrorString(err));
        cellCapacity = numCells;
        particleCapacity = nParticles;
    }
};

thread_local CudaCellWorkspace g_populationGuardWorkspace0297;
thread_local DeviceBuffers0297 g_populationGuardBuffers0297;

inline double seconds_between(const Clock::time_point a, const Clock::time_point b) {
    return std::chrono::duration<double>(b - a).count();
}

void cuda_check_0297(cudaError_t err, const char* context) {
    if (err != cudaSuccess) {
        throw std::runtime_error(std::string("cuda_resampling_population_guard_0297: ") +
                                 context + ": " + cudaGetErrorString(err));
    }
}

bool env_truthy_0297(const char* name) {
    const char* v = std::getenv(name);
    if (v == nullptr || *v == '\0') return false;
    std::string s(v);
    std::transform(s.begin(), s.end(), s.begin(), [](unsigned char c) {
        return static_cast<char>(std::tolower(c));
    });
    return !(s == "0" || s == "false" || s == "off" || s == "no");
}

int env_int_0297(const char* name, int fallback) {
    const char* v = std::getenv(name);
    if (v == nullptr || *v == '\0') return fallback;
    try {
        return std::stoi(v);
    } catch (...) {
        return fallback;
    }
}

double env_double_0297(const char* name, double fallback) {
    const char* v = std::getenv(name);
    if (v == nullptr || *v == '\0') return fallback;
    try {
        return std::stod(v);
    } catch (...) {
        return fallback;
    }
}

std::string csv_escape_0297(const std::string& s) {
    if (s.find_first_of(",\"\n\r") == std::string::npos) return s;
    std::string out = "\"";
    for (const char ch : s) {
        if (ch == '"') out += "\"\"";
        else out += ch;
    }
    out += "\"";
    return out;
}

__device__ bool point_inside_active_domain_0297(double x, double y, DevicePopulationGuardConfig0297 cfg) {
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

__device__ bool cell_center_inside_active_domain_0297(int c, DevicePopulationGuardConfig0297 cfg) {
    const int ix = c % cfg.nx;
    const int iy = c / cfg.nx;
    const double cx = (static_cast<double>(ix) + 0.5) * cfg.dx;
    const double cy = (static_cast<double>(iy) + 0.5) * cfg.dy;
    return point_inside_active_domain_0297(cx, cy, cfg);
}

__global__ void reset_population_guard_buffers_kernel_0297(
    int numCells,
    unsigned int* __restrict__ poorCount,
    unsigned int* __restrict__ richCount,
    unsigned int* __restrict__ inactiveCount,
    unsigned int* __restrict__ poorDonor,
    unsigned int* __restrict__ richKeep,
    unsigned int* __restrict__ richExtract,
    unsigned long long* __restrict__ counters) {
    const int c = blockIdx.x * blockDim.x + threadIdx.x;
    if (c < numCells) {
        poorDonor[c] = kInvalidParticle0297;
        richKeep[c] = kInvalidParticle0297;
        richExtract[c] = kInvalidParticle0297;
    }
    if (c == 0) {
        *poorCount = 0u;
        *richCount = 0u;
        *inactiveCount = 0u;
        for (int i = 0; i < 5; ++i) counters[i] = 0ull;
    }
}

__global__ void classify_population_guard_cells_kernel_0297(
    const unsigned int* __restrict__ cellCount,
    DevicePopulationGuardConfig0297 cfg,
    unsigned int* __restrict__ poorCells,
    unsigned int* __restrict__ richCells,
    unsigned int* __restrict__ poorCount,
    unsigned int* __restrict__ richCount) {
    const int c = blockIdx.x * blockDim.x + threadIdx.x;
    if (c >= cfg.numCells) return;
    if (!cell_center_inside_active_domain_0297(c, cfg)) return;
    const int n = static_cast<int>(cellCount[c]);
    if (n > 0 && cfg.nMin > 0 && n < cfg.nMin) {
        const unsigned int k = atomicAdd(poorCount, 1u);
        poorCells[k] = static_cast<unsigned int>(c);
    } else if (cfg.nMax > 0 && n > cfg.nMax) {
        const unsigned int k = atomicAdd(richCount, 1u);
        richCells[k] = static_cast<unsigned int>(c);
    }
}

__global__ void select_population_guard_primary_particles_kernel_0297(
    int nParticles,
    const double* __restrict__ x,
    const double* __restrict__ y,
    const unsigned char* __restrict__ role,
    const int* __restrict__ cellId,
    const unsigned int* __restrict__ cellCount,
    DevicePopulationGuardConfig0297 cfg,
    unsigned int* __restrict__ poorDonor,
    unsigned int* __restrict__ richKeep) {
    const int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= nParticles) return;
    if (role && role[i] != static_cast<unsigned char>(kParticleRoleFluid)) return;
    const int c = cellId[i];
    if (c < 0 || c >= cfg.numCells) return;
    if (!point_inside_active_domain_0297(x[i], y[i], cfg)) return;
    const int n = static_cast<int>(cellCount[c]);
    if (n > 0 && cfg.nMin > 0 && n < cfg.nMin) {
        atomicMin(&poorDonor[c], static_cast<unsigned int>(i));
    } else if (cfg.nMax > 0 && n > cfg.nMax) {
        atomicMin(&richKeep[c], static_cast<unsigned int>(i));
    }
}

__global__ void select_population_guard_rich_extract_kernel_0297(
    int nParticles,
    const double* __restrict__ x,
    const double* __restrict__ y,
    const unsigned char* __restrict__ role,
    const int* __restrict__ cellId,
    const unsigned int* __restrict__ cellCount,
    DevicePopulationGuardConfig0297 cfg,
    const unsigned int* __restrict__ richKeep,
    unsigned int* __restrict__ richExtract) {
    const int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= nParticles) return;
    if (role && role[i] != static_cast<unsigned char>(kParticleRoleFluid)) return;
    const int c = cellId[i];
    if (c < 0 || c >= cfg.numCells) return;
    if (!point_inside_active_domain_0297(x[i], y[i], cfg)) return;
    const int n = static_cast<int>(cellCount[c]);
    if (!(cfg.nMax > 0 && n > cfg.nMax)) return;
    const unsigned int keep = richKeep[c];
    const unsigned int ui = static_cast<unsigned int>(i);
    if (keep == kInvalidParticle0297 || ui == keep) return;
    atomicMin(&richExtract[c], ui);
}

__global__ void merge_rich_cells_kernel_0297(
    unsigned int richCount,
    const unsigned int* __restrict__ richCells,
    unsigned int* __restrict__ richKeep,
    unsigned int* __restrict__ richExtract,
    double* __restrict__ vx,
    double* __restrict__ vy,
    double* __restrict__ mass,
    unsigned char* __restrict__ role,
    unsigned long long* __restrict__ counters) {
    const unsigned int k = blockIdx.x * blockDim.x + threadIdx.x;
    if (k >= richCount) return;
    const unsigned int c = richCells[k];
    const unsigned int keep = richKeep[c];
    const unsigned int drop = richExtract[c];
    if (keep == kInvalidParticle0297 || drop == kInvalidParticle0297 || keep == drop) {
        atomicAdd(&counters[4], 1ull);
        return;
    }
    if (role[keep] != static_cast<unsigned char>(kParticleRoleFluid) ||
        role[drop] != static_cast<unsigned char>(kParticleRoleFluid)) {
        atomicAdd(&counters[4], 1ull);
        return;
    }
    const double mk = mass[keep];
    const double md = mass[drop];
    if (!(mk > 0.0) || !(md > 0.0)) {
        atomicAdd(&counters[4], 1ull);
        return;
    }
    const double M = mk + md;
    const double px = mk * vx[keep] + md * vx[drop];
    const double py = mk * vy[keep] + md * vy[drop];
    mass[keep] = M;
    vx[keep] = px / M;
    vy[keep] = py / M;
    mass[drop] = 0.0;
    vx[drop] = 0.0;
    vy[drop] = 0.0;
    role[drop] = static_cast<unsigned char>(kParticleRoleInactive);
    atomicAdd(&counters[0], 1ull);
}

__global__ void build_inactive_list_kernel_0297(
    int nParticles,
    const unsigned char* __restrict__ role,
    unsigned int* __restrict__ inactiveList,
    unsigned int* __restrict__ inactiveCount) {
    const int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= nParticles) return;
    if (role && role[i] == static_cast<unsigned char>(kParticleRoleInactive)) {
        const unsigned int k = atomicAdd(inactiveCount, 1u);
        inactiveList[k] = static_cast<unsigned int>(i);
    }
}

__device__ double clamp_0297(double v, double lo, double hi) {
    return fmin(fmax(v, lo), hi);
}

__global__ void split_poor_cells_kernel_0297(
    unsigned int poorCount,
    const unsigned int* __restrict__ poorCells,
    const unsigned int* __restrict__ inactiveList,
    const unsigned int* __restrict__ inactiveCount,
    unsigned int* __restrict__ inactiveCursor,
    const unsigned int* __restrict__ poorDonor,
    double* __restrict__ x,
    double* __restrict__ y,
    double* __restrict__ vx,
    double* __restrict__ vy,
    double* __restrict__ mass,
    unsigned int* __restrict__ type,
    unsigned char* __restrict__ role,
    DevicePopulationGuardConfig0297 cfg,
    unsigned long long* __restrict__ counters) {
    const unsigned int k = blockIdx.x * blockDim.x + threadIdx.x;
    if (k >= poorCount) return;
    const unsigned int c = poorCells[k];
    const unsigned int donor = poorDonor[c];
    if (donor == kInvalidParticle0297 || role[donor] != static_cast<unsigned char>(kParticleRoleFluid)) {
        atomicAdd(&counters[3], 1ull);
        return;
    }
    const unsigned int slotOrdinal = atomicAdd(inactiveCursor, 1u);
    if (slotOrdinal >= *inactiveCount) {
        atomicAdd(&counters[2], 1ull);
        return;
    }
    const unsigned int slot = inactiveList[slotOrdinal];
    if (slot == donor || role[slot] != static_cast<unsigned char>(kParticleRoleInactive)) {
        atomicAdd(&counters[2], 1ull);
        return;
    }
    const double md = mass[donor];
    if (!(md > 0.0)) {
        atomicAdd(&counters[3], 1ull);
        return;
    }
    const double dm = fmin(md * cfg.splitFraction, fmax(0.0, md - cfg.minDonorMassAfterSplit));
    if (!(dm > 0.0) || !isfinite(dm)) {
        atomicAdd(&counters[3], 1ull);
        return;
    }

    const int ix = static_cast<int>(c % static_cast<unsigned int>(cfg.nx));
    const int iy = static_cast<int>(c / static_cast<unsigned int>(cfg.nx));
    const double xmin = static_cast<double>(ix) * cfg.dx;
    const double xmax = xmin + cfg.dx;
    const double ymin = static_cast<double>(iy) * cfg.dy;
    const double ymax = ymin + cfg.dy;
    const double epsx = 0.0625 * cfg.dx;
    const double epsy = 0.0625 * cfg.dy;
    double xn = clamp_0297(x[donor] + ((k & 1u) ? epsx : -epsx), xmin + 1.0e-12 * cfg.dx, xmax - 1.0e-12 * cfg.dx);
    double yn = clamp_0297(y[donor] + ((k & 2u) ? epsy : -epsy), ymin + 1.0e-12 * cfg.dy, ymax - 1.0e-12 * cfg.dy);
    if (!point_inside_active_domain_0297(xn, yn, cfg)) {
        xn = x[donor];
        yn = y[donor];
    }

    mass[donor] = md - dm;
    x[slot] = xn;
    y[slot] = yn;
    vx[slot] = vx[donor];
    vy[slot] = vy[donor];
    mass[slot] = dm;
    type[slot] = type[donor];
    role[slot] = static_cast<unsigned char>(kParticleRoleFluid);
    atomicAdd(&counters[1], 1ull);
}

DevicePopulationGuardConfig0297 make_config_0297(const SimulationParams& params,
                                                 const CellGrid& grid,
                                                 const FluidDomainBounds& domain,
                                                 double time) {
    DevicePopulationGuardConfig0297 cfg{};
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
    cfg.nMin = std::max(0, env_int_0297("MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297_NMIN", 0));
    cfg.nTarget = std::max(cfg.nMin, env_int_0297("MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297_NTARGET", 20));
    cfg.nMax = std::max(0, env_int_0297("MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297_NMAX", 0));
    cfg.splitFraction = std::clamp(env_double_0297("MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297_SPLIT_FRACTION", 0.5), 1.0e-6, 0.5);
    cfg.minDonorMassAfterSplit = std::max(0.0, env_double_0297("MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297_MIN_DONOR_MASS_AFTER_SPLIT", 1.0e-12));

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

void write_csv_row_0297(const SimulationParams& params,
                        CudaResamplingPopulationGuard0297Diagnostics& d) {
    std::filesystem::create_directories(params.outputDir);
    const std::filesystem::path path = std::filesystem::path(params.outputDir) /
        "cuda_resampling_population_guard_0297.csv";
    const bool needHeader = !std::filesystem::exists(path) || std::filesystem::file_size(path) == 0u;
    std::ofstream out(path, std::ios::app);
    if (!out) return;
    d.outputCsv = path.string();
    if (needHeader) {
        out << "step,stage,handled,cudaAvailable,sharedStateFreshBefore,skippedBecauseStateNotFresh,"
               "particles,cells,fluidParticlesBefore,fluidParticlesAfter,inactiveParticlesBefore,inactiveParticlesAfter,"
               "wetCellsBefore,wetCellsAfter,poorCells,richCells,mergeApplied,splitApplied,splitSkippedNoInactive,"
               "splitSkippedNoDonor,mergeSkippedNoPair,nMin,nTarget,nMax,splitFraction,minDonorMassAfterSplit,"
               "totalMassBefore,totalMassAfter,totalPxBefore,totalPxAfter,totalPyBefore,totalPyAfter,"
               "maxAbsCellMassError,maxRelCellMassError,maxAbsCellMomentumError,maxRelCellMomentumError,"
               "depositBeforeSeconds,kernelSeconds,depositAfterSeconds,downloadSeconds,totalSeconds\n";
    }
    out << std::setprecision(17)
        << d.step << ','
        << csv_escape_0297(d.stage) << ','
        << (d.handled ? 1 : 0) << ','
        << (d.cudaAvailable ? 1 : 0) << ','
        << (d.sharedStateFreshBefore ? 1 : 0) << ','
        << (d.skippedBecauseStateNotFresh ? 1 : 0) << ','
        << d.particles << ',' << d.cells << ','
        << d.fluidParticlesBefore << ',' << d.fluidParticlesAfter << ','
        << d.inactiveParticlesBefore << ',' << d.inactiveParticlesAfter << ','
        << d.wetCellsBefore << ',' << d.wetCellsAfter << ','
        << d.poorCells << ',' << d.richCells << ','
        << d.mergeApplied << ',' << d.splitApplied << ','
        << d.splitSkippedNoInactive << ',' << d.splitSkippedNoDonor << ',' << d.mergeSkippedNoPair << ','
        << d.nMin << ',' << d.nTarget << ',' << d.nMax << ','
        << d.splitFraction << ',' << d.minDonorMassAfterSplit << ','
        << d.totalMassBefore << ',' << d.totalMassAfter << ','
        << d.totalPxBefore << ',' << d.totalPxAfter << ','
        << d.totalPyBefore << ',' << d.totalPyAfter << ','
        << d.maxAbsCellMassError << ',' << d.maxRelCellMassError << ','
        << d.maxAbsCellMomentumError << ',' << d.maxRelCellMomentumError << ','
        << d.depositBeforeSeconds << ',' << d.kernelSeconds << ','
        << d.depositAfterSeconds << ',' << d.downloadSeconds << ',' << d.totalSeconds << '\n';
}

void accumulate_global_diagnostics_0297(const CudaCellMoments& m,
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

void compare_before_after_0297(const CudaCellMoments& before,
                               const CudaCellMoments& after,
                               CudaResamplingPopulationGuard0297Diagnostics& d) {
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

bool cuda_resampling_population_guard_0297_requested(std::uint64_t step) {
    if (!env_truthy_0297("MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297")) return false;
    const int every = std::max(1, env_int_0297("MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297_EVERY", 1));
    return (step % static_cast<std::uint64_t>(every)) == 0u;
}

CudaResamplingPopulationGuard0297Diagnostics try_apply_cuda_resampling_population_guard_0297(
    ParticleState& hostMirror,
    const SimulationParams& params,
    const CellGrid& grid,
    const FluidDomainBounds& domain,
    std::uint64_t step,
    double time,
    const char* stage) {
    CudaResamplingPopulationGuard0297Diagnostics d{};
    d.attempted = true;
    d.step = step;
    d.stage = stage != nullptr ? stage : "post_src_population_guard";
    d.particles = hostMirror.Np;
    d.cells = static_cast<std::uint64_t>(std::max(0, grid.numCells));
    const DevicePopulationGuardConfig0297 cfg = make_config_0297(params, grid, domain, time);
    d.nMin = cfg.nMin;
    d.nTarget = cfg.nTarget;
    d.nMax = cfg.nMax;
    d.splitFraction = cfg.splitFraction;
    d.minDonorMassAfterSplit = cfg.minDonorMassAfterSplit;
    const Clock::time_point t0 = Clock::now();

    d.cudaAvailable = cuda_cell_moments_available();
    if (!d.cudaAvailable) {
        d.totalSeconds = seconds_between(t0, Clock::now());
        write_csv_row_0297(params, d);
        return d;
    }
    if (grid.Nx <= 0 || grid.Ny <= 0 || grid.numCells != grid.Nx * grid.Ny) {
        throw std::runtime_error("cuda_resampling_population_guard_0297: invalid grid");
    }

    d.sharedStateFreshBefore = cuda_shared_particle_state_0251_is_fresh();
    if (!d.sharedStateFreshBefore) {
        // 0297 mutates roles/masses/positions.  It is only allowed when the
        // resident CUDA state is authoritative.  A later CPU/Q6 handoff can add
        // an explicit upload/download contract; this minimal patch must not
        // infer authority from a stale host mirror.
        d.skippedBecauseStateNotFresh = true;
        d.totalSeconds = seconds_between(t0, Clock::now());
        write_csv_row_0297(params, d);
        return d;
    }

    CudaParticleState& gpuState = cuda_shared_particle_state_0251();
    CudaCellWorkspaceDiagnostics workspaceDiag{};
    g_populationGuardWorkspace0297.ensure_capacity(hostMirror.Np, grid.numCells, &workspaceDiag);

    CudaCellMomentsOptions options{};
    options.threadsPerBlock = std::max(32, env_int_0297("MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297_THREADS", 256));
    options.reuseDeviceBuffers = true;
    options.computeCellVelocities = true;
    options.downloadCellVelocities = true;
    options.enableAllFluidFastPath = false;
    options.enableUniformMassFastPath = false;

    CudaCellMoments before{};
    CudaCellMomentsDiagnostics beforeDiag{};
    cuda_deposit_cell_moments_atomic_from_persistent_state(
        hostMirror, gpuState, g_populationGuardWorkspace0297, grid, GridShift{}, params,
        before, &beforeDiag, options);
    d.depositBeforeSeconds = beforeDiag.totalSeconds + workspaceDiag.totalSeconds;
    accumulate_global_diagnostics_0297(before,
                                       d.fluidParticlesBefore,
                                       d.wetCellsBefore,
                                       d.totalMassBefore,
                                       d.totalPxBefore,
                                       d.totalPyBefore);

    CudaCellWorkspaceDeviceView cv = g_populationGuardWorkspace0297.device_view();
    CudaParticleDeviceView pv = gpuState.device_view();
    if (cv.cellId == nullptr || cv.count == nullptr || cv.cellMass == nullptr ||
        pv.x == nullptr || pv.y == nullptr || pv.vx == nullptr || pv.vy == nullptr ||
        pv.mass == nullptr || pv.type == nullptr || pv.role == nullptr) {
        throw std::runtime_error("cuda_resampling_population_guard_0297: incomplete device views");
    }

    g_populationGuardBuffers0297.ensure(grid.numCells, hostMirror.Np);
    const int block = options.threadsPerBlock;
    const int cellGrid = std::max(1, (grid.numCells + block - 1) / block);
    const int particleGrid = std::max(1, (static_cast<int>(hostMirror.Np) + block - 1) / block);

    const Clock::time_point tk0 = Clock::now();
    reset_population_guard_buffers_kernel_0297<<<cellGrid, block>>>(
        grid.numCells,
        g_populationGuardBuffers0297.dPoorCount,
        g_populationGuardBuffers0297.dRichCount,
        g_populationGuardBuffers0297.dInactiveCount,
        g_populationGuardBuffers0297.dPoorDonor,
        g_populationGuardBuffers0297.dRichKeep,
        g_populationGuardBuffers0297.dRichExtract,
        g_populationGuardBuffers0297.dCounters);
    cuda_check_0297(cudaGetLastError(), "launch reset_population_guard_buffers_kernel_0297");

    classify_population_guard_cells_kernel_0297<<<cellGrid, block>>>(
        cv.count,
        cfg,
        g_populationGuardBuffers0297.dPoorCells,
        g_populationGuardBuffers0297.dRichCells,
        g_populationGuardBuffers0297.dPoorCount,
        g_populationGuardBuffers0297.dRichCount);
    cuda_check_0297(cudaGetLastError(), "launch classify_population_guard_cells_kernel_0297");

    select_population_guard_primary_particles_kernel_0297<<<particleGrid, block>>>(
        static_cast<int>(hostMirror.Np),
        pv.x, pv.y, pv.role, cv.cellId, cv.count, cfg,
        g_populationGuardBuffers0297.dPoorDonor,
        g_populationGuardBuffers0297.dRichKeep);
    cuda_check_0297(cudaGetLastError(), "launch select_population_guard_primary_particles_kernel_0297");
    select_population_guard_rich_extract_kernel_0297<<<particleGrid, block>>>(
        static_cast<int>(hostMirror.Np),
        pv.x, pv.y, pv.role, cv.cellId, cv.count, cfg,
        g_populationGuardBuffers0297.dRichKeep,
        g_populationGuardBuffers0297.dRichExtract);
    cuda_check_0297(cudaGetLastError(), "launch select_population_guard_rich_extract_kernel_0297");

    unsigned int hPoorCount = 0u;
    unsigned int hRichCount = 0u;
    cuda_check_0297(cudaMemcpy(&hPoorCount, g_populationGuardBuffers0297.dPoorCount,
                               sizeof(unsigned int), cudaMemcpyDeviceToHost),
                    "copy poor count D2H");
    cuda_check_0297(cudaMemcpy(&hRichCount, g_populationGuardBuffers0297.dRichCount,
                               sizeof(unsigned int), cudaMemcpyDeviceToHost),
                    "copy rich count D2H");
    d.poorCells = hPoorCount;
    d.richCells = hRichCount;

    const int richGrid = std::max(1, (static_cast<int>(hRichCount) + block - 1) / block);
    if (hRichCount > 0u) {
        merge_rich_cells_kernel_0297<<<richGrid, block>>>(
            hRichCount,
            g_populationGuardBuffers0297.dRichCells,
            g_populationGuardBuffers0297.dRichKeep,
            g_populationGuardBuffers0297.dRichExtract,
            pv.vx, pv.vy, pv.mass, pv.role,
            g_populationGuardBuffers0297.dCounters);
        cuda_check_0297(cudaGetLastError(), "launch merge_rich_cells_kernel_0297");
    }
    cuda_check_0297(cudaDeviceSynchronize(), "synchronize after rich merge");

    cuda_check_0297(cudaMemset(g_populationGuardBuffers0297.dInactiveCount, 0, sizeof(unsigned int)),
                    "reset inactive count");
    build_inactive_list_kernel_0297<<<particleGrid, block>>>(
        static_cast<int>(hostMirror.Np), pv.role,
        g_populationGuardBuffers0297.dInactiveList,
        g_populationGuardBuffers0297.dInactiveCount);
    cuda_check_0297(cudaGetLastError(), "launch build_inactive_list_kernel_0297");
    cuda_check_0297(cudaMemset(g_populationGuardBuffers0297.dInactiveCursor, 0, sizeof(unsigned int)),
                    "reset inactive cursor");

    const int poorGrid = std::max(1, (static_cast<int>(hPoorCount) + block - 1) / block);
    if (hPoorCount > 0u) {
        split_poor_cells_kernel_0297<<<poorGrid, block>>>(
            hPoorCount,
            g_populationGuardBuffers0297.dPoorCells,
            g_populationGuardBuffers0297.dInactiveList,
            g_populationGuardBuffers0297.dInactiveCount,
            g_populationGuardBuffers0297.dInactiveCursor,
            g_populationGuardBuffers0297.dPoorDonor,
            pv.x, pv.y, pv.vx, pv.vy, pv.mass, pv.type, pv.role,
            cfg,
            g_populationGuardBuffers0297.dCounters);
        cuda_check_0297(cudaGetLastError(), "launch split_poor_cells_kernel_0297");
    }
    cuda_check_0297(cudaDeviceSynchronize(), "synchronize population guard kernels");
    const Clock::time_point tk1 = Clock::now();
    d.kernelSeconds = seconds_between(tk0, tk1);

    unsigned long long hCounters[5] = {0ull, 0ull, 0ull, 0ull, 0ull};
    const Clock::time_point td0 = Clock::now();
    cuda_check_0297(cudaMemcpy(hCounters, g_populationGuardBuffers0297.dCounters,
                               sizeof(hCounters), cudaMemcpyDeviceToHost),
                    "copy counters D2H");
    const Clock::time_point td1 = Clock::now();
    d.downloadSeconds = seconds_between(td0, td1);
    d.mergeApplied = static_cast<std::uint64_t>(hCounters[0]);
    d.splitApplied = static_cast<std::uint64_t>(hCounters[1]);
    d.splitSkippedNoInactive = static_cast<std::uint64_t>(hCounters[2]);
    d.splitSkippedNoDonor = static_cast<std::uint64_t>(hCounters[3]);
    d.mergeSkippedNoPair = static_cast<std::uint64_t>(hCounters[4]);

    if (d.mergeApplied > 0u || d.splitApplied > 0u) {
        cuda_shared_particle_state_0251_mark_fresh("cuda_resampling_population_guard_0297");
    }

    CudaCellMoments after{};
    CudaCellMomentsDiagnostics afterDiag{};
    cuda_deposit_cell_moments_atomic_from_persistent_state(
        hostMirror, gpuState, g_populationGuardWorkspace0297, grid, GridShift{}, params,
        after, &afterDiag, options);
    d.depositAfterSeconds = afterDiag.totalSeconds;
    accumulate_global_diagnostics_0297(after,
                                       d.fluidParticlesAfter,
                                       d.wetCellsAfter,
                                       d.totalMassAfter,
                                       d.totalPxAfter,
                                       d.totalPyAfter);
    compare_before_after_0297(before, after, d);

    // Do not download the resident particle state just for 0297 diagnostics.
    // These counts are non-fluid storage slots (inactive plus any latent slots)
    // inferred from the deposited fluid count; downstream CPU diagnostics still
    // perform their usual explicit download on summary/final steps.
    d.inactiveParticlesBefore = hostMirror.Np >= d.fluidParticlesBefore ? hostMirror.Np - d.fluidParticlesBefore : 0u;
    d.inactiveParticlesAfter = hostMirror.Np >= d.fluidParticlesAfter ? hostMirror.Np - d.fluidParticlesAfter : 0u;

    d.handled = true;
    d.totalSeconds = seconds_between(t0, Clock::now());
    write_csv_row_0297(params, d);
    return d;
}

} // namespace mpcd

#endif
