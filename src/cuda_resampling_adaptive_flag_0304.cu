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
    double highUThreshold = 1.0;

    int bcLeftOpen = 0;
    int bcRightOpen = 0;
    int bcBottomOpen = 0;
    int bcTopOpen = 0;
    int bcLeftSolid = 0;
    int bcRightSolid = 0;
    int bcBottomSolid = 0;
    int bcTopSolid = 0;

    int segmentCount = 0;
    int segmentFace[16]; // 0 left, 1 right, 2 bottom, 3 top.
    double segmentSMin[16];
    double segmentSMax[16];
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

    unsigned int emptyBulkCells0305;
    unsigned int emptyWallAdjacentCells0305;
    unsigned int emptySolidAdjacentCells0305;
    unsigned int emptyOpenAdjacentCells0305;
    unsigned int emptyCornerAdjacentCells0305;
    unsigned int lowNBulkCells0305;
    unsigned int lowNWallAdjacentCells0305;
    unsigned int lowNSolidAdjacentCells0305;
    unsigned int lowNOpenAdjacentCells0305;
    unsigned int lowNCornerAdjacentCells0305;
    unsigned int wetBulkCells0305;
    unsigned int wetWallAdjacentCells0305;
    unsigned int wetSolidAdjacentCells0305;
    unsigned int wetOpenAdjacentCells0305;
    unsigned int wetCornerAdjacentCells0305;
    unsigned int highUBulkCells0305;
    unsigned int highUWallAdjacentCells0305;
    unsigned int highUSolidAdjacentCells0305;
    unsigned int highUOpenAdjacentCells0305;
    unsigned int highUCornerAdjacentCells0305;
    double maxAbsUBulk0305;
    double maxAbsUWallAdjacent0305;
    double maxAbsUSolidAdjacent0305;
    double maxAbsUOpenAdjacent0305;
    double maxAbsUCornerAdjacent0305;
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
        stats->emptyBulkCells0305 = 0u;
        stats->emptyWallAdjacentCells0305 = 0u;
        stats->emptySolidAdjacentCells0305 = 0u;
        stats->emptyOpenAdjacentCells0305 = 0u;
        stats->emptyCornerAdjacentCells0305 = 0u;
        stats->lowNBulkCells0305 = 0u;
        stats->lowNWallAdjacentCells0305 = 0u;
        stats->lowNSolidAdjacentCells0305 = 0u;
        stats->lowNOpenAdjacentCells0305 = 0u;
        stats->lowNCornerAdjacentCells0305 = 0u;
        stats->wetBulkCells0305 = 0u;
        stats->wetWallAdjacentCells0305 = 0u;
        stats->wetSolidAdjacentCells0305 = 0u;
        stats->wetOpenAdjacentCells0305 = 0u;
        stats->wetCornerAdjacentCells0305 = 0u;
        stats->highUBulkCells0305 = 0u;
        stats->highUWallAdjacentCells0305 = 0u;
        stats->highUSolidAdjacentCells0305 = 0u;
        stats->highUOpenAdjacentCells0305 = 0u;
        stats->highUCornerAdjacentCells0305 = 0u;
        stats->maxAbsUBulk0305 = 0.0;
        stats->maxAbsUWallAdjacent0305 = 0.0;
        stats->maxAbsUSolidAdjacent0305 = 0.0;
        stats->maxAbsUOpenAdjacent0305 = 0.0;
        stats->maxAbsUCornerAdjacent0305 = 0.0;
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


__device__ inline int face_from_string_index_0305(int face) { return face; }

__device__ bool cell_inside_immersed_solid_center_0305(int ix, int iy, const DeviceFlagConfig0304 cfg) {
    const double x = (static_cast<double>(ix) + 0.5) * cfg.dx;
    const double y = (static_cast<double>(iy) + 0.5) * cfg.dy;
    if (cfg.solidShape == 1) {
        const double dx = x - cfg.circleCx;
        const double dy = y - cfg.circleCy;
        return dx * dx + dy * dy < cfg.circleR * cfg.circleR;
    }
    if (cfg.solidShape == 2) {
        return x >= cfg.rectXMin && x <= cfg.rectXMax && y >= cfg.rectYMin && y <= cfg.rectYMax;
    }
    return false;
}

__device__ bool segment_open_at_face_cell_0305(int face, int ix, int iy, const DeviceFlagConfig0304 cfg) {
    double s = 0.0;
    if (face == 0 || face == 1) {
        s = (static_cast<double>(iy) + 0.5) / static_cast<double>(cfg.ny);
    } else {
        s = (static_cast<double>(ix) + 0.5) / static_cast<double>(cfg.nx);
    }
    for (int k = 0; k < cfg.segmentCount && k < 16; ++k) {
        if (cfg.segmentFace[k] == face && s >= cfg.segmentSMin[k] && s <= cfg.segmentSMax[k]) {
            return true;
        }
    }
    return false;
}

__device__ bool open_boundary_adjacent_0305(int ix, int iy, const DeviceFlagConfig0304 cfg) {
    if (ix == 0 && (cfg.bcLeftOpen || segment_open_at_face_cell_0305(0, ix, iy, cfg))) return true;
    if (ix == cfg.nx - 1 && (cfg.bcRightOpen || segment_open_at_face_cell_0305(1, ix, iy, cfg))) return true;
    if (iy == 0 && (cfg.bcBottomOpen || segment_open_at_face_cell_0305(2, ix, iy, cfg))) return true;
    if (iy == cfg.ny - 1 && (cfg.bcTopOpen || segment_open_at_face_cell_0305(3, ix, iy, cfg))) return true;
    return false;
}

__device__ bool wall_boundary_adjacent_0305(int ix, int iy, const DeviceFlagConfig0304 cfg) {
    if (ix == 0) {
        const bool segOpen = segment_open_at_face_cell_0305(0, ix, iy, cfg);
        if (!segOpen && (cfg.bcLeftSolid || (!cfg.bcLeftOpen && cfg.segmentCount > 0))) return true;
    }
    if (ix == cfg.nx - 1) {
        const bool segOpen = segment_open_at_face_cell_0305(1, ix, iy, cfg);
        if (!segOpen && (cfg.bcRightSolid || (!cfg.bcRightOpen && cfg.segmentCount > 0))) return true;
    }
    if (iy == 0) {
        const bool segOpen = segment_open_at_face_cell_0305(2, ix, iy, cfg);
        if (!segOpen && (cfg.bcBottomSolid || (!cfg.bcBottomOpen && cfg.segmentCount > 0))) return true;
    }
    if (iy == cfg.ny - 1) {
        const bool segOpen = segment_open_at_face_cell_0305(3, ix, iy, cfg);
        if (!segOpen && (cfg.bcTopSolid || (!cfg.bcTopOpen && cfg.segmentCount > 0))) return true;
    }
    return false;
}

__device__ bool solid_neighbor_adjacent_0305(int ix, int iy, const DeviceFlagConfig0304 cfg) {
    if (cfg.solidShape == 0) return false;
    const int dxs[4] = {-1, 1, 0, 0};
    const int dys[4] = {0, 0, -1, 1};
    for (int q = 0; q < 4; ++q) {
        const int jx = ix + dxs[q];
        const int jy = iy + dys[q];
        if (jx < 0 || jx >= cfg.nx || jy < 0 || jy >= cfg.ny) continue;
        if (cell_inside_immersed_solid_center_0305(jx, jy, cfg)) return true;
    }
    return false;
}

__device__ int blocked_neighbor_count_0305(int ix, int iy, const DeviceFlagConfig0304 cfg) {
    int blocked = 0;
    if (ix == 0 && !cfg.periodicX && !open_boundary_adjacent_0305(ix, iy, cfg)) ++blocked;
    if (ix == cfg.nx - 1 && !cfg.periodicX && !open_boundary_adjacent_0305(ix, iy, cfg)) ++blocked;
    if (iy == 0 && !cfg.periodicY && !open_boundary_adjacent_0305(ix, iy, cfg)) ++blocked;
    if (iy == cfg.ny - 1 && !cfg.periodicY && !open_boundary_adjacent_0305(ix, iy, cfg)) ++blocked;
    if (cfg.solidShape != 0) {
        const int dxs[4] = {-1, 1, 0, 0};
        const int dys[4] = {0, 0, -1, 1};
        for (int q = 0; q < 4; ++q) {
            const int jx = ix + dxs[q];
            const int jy = iy + dys[q];
            if (jx < 0 || jx >= cfg.nx || jy < 0 || jy >= cfg.ny) continue;
            if (cell_inside_immersed_solid_center_0305(jx, jy, cfg)) ++blocked;
        }
    }
    return blocked;
}

__device__ double atomic_max_double_compat_0305(double* address, double value) {
    if (value <= 0.0) return *address;
    unsigned long long int* addressAsUll = reinterpret_cast<unsigned long long int*>(address);
    unsigned long long int old = *addressAsUll;
    unsigned long long int assumed;
    do {
        assumed = old;
        const double oldVal = __longlong_as_double(static_cast<long long>(assumed));
        if (oldVal >= value) break;
        old = atomicCAS(addressAsUll, assumed, static_cast<unsigned long long int>(__double_as_longlong(value)));
    } while (assumed != old);
    return __longlong_as_double(static_cast<long long>(old));
}

__device__ void update_geometry_class_counts_0305(DeviceFlagStats0304* stats,
                                                  bool isEmpty,
                                                  bool isLowN,
                                                  bool isWet,
                                                  double absU,
                                                  bool bulk,
                                                  bool wallAdj,
                                                  bool solidAdj,
                                                  bool openAdj,
                                                  bool cornerAdj,
                                                  const DeviceFlagConfig0304 cfg) {
    if (isEmpty) {
        if (bulk) atomicAdd(&stats->emptyBulkCells0305, 1u);
        if (wallAdj) atomicAdd(&stats->emptyWallAdjacentCells0305, 1u);
        if (solidAdj) atomicAdd(&stats->emptySolidAdjacentCells0305, 1u);
        if (openAdj) atomicAdd(&stats->emptyOpenAdjacentCells0305, 1u);
        if (cornerAdj) atomicAdd(&stats->emptyCornerAdjacentCells0305, 1u);
    }
    if (isLowN) {
        if (bulk) atomicAdd(&stats->lowNBulkCells0305, 1u);
        if (wallAdj) atomicAdd(&stats->lowNWallAdjacentCells0305, 1u);
        if (solidAdj) atomicAdd(&stats->lowNSolidAdjacentCells0305, 1u);
        if (openAdj) atomicAdd(&stats->lowNOpenAdjacentCells0305, 1u);
        if (cornerAdj) atomicAdd(&stats->lowNCornerAdjacentCells0305, 1u);
    }
    if (isWet) {
        if (bulk) atomicAdd(&stats->wetBulkCells0305, 1u);
        if (wallAdj) atomicAdd(&stats->wetWallAdjacentCells0305, 1u);
        if (solidAdj) atomicAdd(&stats->wetSolidAdjacentCells0305, 1u);
        if (openAdj) atomicAdd(&stats->wetOpenAdjacentCells0305, 1u);
        if (cornerAdj) atomicAdd(&stats->wetCornerAdjacentCells0305, 1u);
        if (bulk) atomic_max_double_compat_0305(&stats->maxAbsUBulk0305, absU);
        if (wallAdj) atomic_max_double_compat_0305(&stats->maxAbsUWallAdjacent0305, absU);
        if (solidAdj) atomic_max_double_compat_0305(&stats->maxAbsUSolidAdjacent0305, absU);
        if (openAdj) atomic_max_double_compat_0305(&stats->maxAbsUOpenAdjacent0305, absU);
        if (cornerAdj) atomic_max_double_compat_0305(&stats->maxAbsUCornerAdjacent0305, absU);
        if (cfg.highUThreshold > 0.0 && absU >= cfg.highUThreshold) {
            if (bulk) atomicAdd(&stats->highUBulkCells0305, 1u);
            if (wallAdj) atomicAdd(&stats->highUWallAdjacentCells0305, 1u);
            if (solidAdj) atomicAdd(&stats->highUSolidAdjacentCells0305, 1u);
            if (openAdj) atomicAdd(&stats->highUOpenAdjacentCells0305, 1u);
            if (cornerAdj) atomicAdd(&stats->highUCornerAdjacentCells0305, 1u);
        }
    }
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

    const bool openAdj = open_boundary_adjacent_0305(ix, iy, cfg);
    const bool wallAdj = wall_boundary_adjacent_0305(ix, iy, cfg);
    const bool solidAdj = solid_neighbor_adjacent_0305(ix, iy, cfg);
    const bool cornerAdj = blocked_neighbor_count_0305(ix, iy, cfg) >= 2;
    const bool bulk = !openAdj && !wallAdj && !solidAdj && !cornerAdj;

    atomicAdd(&stats->activeCells, 1u);
    const unsigned int n = count[c];
    if (n == 0u) {
        atomicAdd(&stats->emptyWetCells, 1u);
        update_geometry_class_counts_0305(stats, true, false, false, 0.0,
                                          bulk, wallAdj, solidAdj, openAdj, cornerAdj, cfg);
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

    const double m = mass[c];
    double absU = 0.0;
    if (m > 0.0) {
        const double ux = px[c] / m;
        const double uy = py[c] / m;
        absU = sqrt(ux * ux + uy * uy);
    }

    const bool isLowN = (cfg.triggerNMin > 0 && static_cast<int>(n) <= cfg.triggerNMin);
    update_geometry_class_counts_0305(stats, false, isLowN, true, absU,
                                      bulk, wallAdj, solidAdj, openAdj, cornerAdj, cfg);

    if (isLowN) {
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

bool boundary_open_mode_0305(const std::string& bc) {
    return bc == "inlet" || bc == "outlet";
}

bool boundary_solid_mode_0305(const std::string& bc) {
    return bc == "solid" || bc == "wall" || bc == "bounceback" || bc == "specular";
}

int face_index_0305(const std::string& face) {
    if (face == "left") return 0;
    if (face == "right") return 1;
    if (face == "bottom") return 2;
    if (face == "top") return 3;
    return -1;
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
    cfg.highUThreshold = std::max(0.0, std::atof(std::getenv("MPCD_CUDA_RESAMPLING_GEOMETRY_DIAG_0305_HIGH_U") ?
                                                 std::getenv("MPCD_CUDA_RESAMPLING_GEOMETRY_DIAG_0305_HIGH_U") : "1.0"));

    cfg.bcLeftOpen = boundary_open_mode_0305(params.bcLeft) ? 1 : 0;
    cfg.bcRightOpen = boundary_open_mode_0305(params.bcRight) ? 1 : 0;
    cfg.bcBottomOpen = boundary_open_mode_0305(params.bcBottom) ? 1 : 0;
    cfg.bcTopOpen = boundary_open_mode_0305(params.bcTop) ? 1 : 0;
    cfg.bcLeftSolid = boundary_solid_mode_0305(params.bcLeft) ? 1 : 0;
    cfg.bcRightSolid = boundary_solid_mode_0305(params.bcRight) ? 1 : 0;
    cfg.bcBottomSolid = boundary_solid_mode_0305(params.bcBottom) ? 1 : 0;
    cfg.bcTopSolid = boundary_solid_mode_0305(params.bcTop) ? 1 : 0;

    if (params.openBoundarySegmentsEnable) {
        for (const auto& seg : params.openBoundarySegments) {
            if (cfg.segmentCount >= 16) break;
            if (!(seg.mode == "inlet" || seg.mode == "outlet")) continue;
            const int f = face_index_0305(seg.face);
            if (f < 0) continue;
            const int k = cfg.segmentCount++;
            cfg.segmentFace[k] = f;
            cfg.segmentSMin[k] = std::max(0.0, std::min(1.0, seg.sMin));
            cfg.segmentSMax[k] = std::max(0.0, std::min(1.0, seg.sMax));
        }
    }

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
               "totalMass,totalPx,totalPy,"
               "emptyBulkCells0305,emptyWallAdjacentCells0305,emptySolidAdjacentCells0305,emptyOpenAdjacentCells0305,emptyCornerAdjacentCells0305,"
               "lowNBulkCells0305,lowNWallAdjacentCells0305,lowNSolidAdjacentCells0305,lowNOpenAdjacentCells0305,lowNCornerAdjacentCells0305,"
               "wetBulkCells0305,wetWallAdjacentCells0305,wetSolidAdjacentCells0305,wetOpenAdjacentCells0305,wetCornerAdjacentCells0305,"
               "highUThreshold0305,highUBulkCells0305,highUWallAdjacentCells0305,highUSolidAdjacentCells0305,highUOpenAdjacentCells0305,highUCornerAdjacentCells0305,"
               "maxAbsUBulk0305,maxAbsUWallAdjacent0305,maxAbsUSolidAdjacent0305,maxAbsUOpenAdjacent0305,maxAbsUCornerAdjacent0305,"
               "uploadSeconds,depositKernelSeconds,flagKernelSeconds,downloadSeconds,totalSeconds\n";
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
        << d.emptyBulkCells0305 << ',' << d.emptyWallAdjacentCells0305 << ','
        << d.emptySolidAdjacentCells0305 << ',' << d.emptyOpenAdjacentCells0305 << ','
        << d.emptyCornerAdjacentCells0305 << ','
        << d.lowNBulkCells0305 << ',' << d.lowNWallAdjacentCells0305 << ','
        << d.lowNSolidAdjacentCells0305 << ',' << d.lowNOpenAdjacentCells0305 << ','
        << d.lowNCornerAdjacentCells0305 << ','
        << d.wetBulkCells0305 << ',' << d.wetWallAdjacentCells0305 << ','
        << d.wetSolidAdjacentCells0305 << ',' << d.wetOpenAdjacentCells0305 << ','
        << d.wetCornerAdjacentCells0305 << ','
        << d.highUThreshold0305 << ',' << d.highUBulkCells0305 << ','
        << d.highUWallAdjacentCells0305 << ',' << d.highUSolidAdjacentCells0305 << ','
        << d.highUOpenAdjacentCells0305 << ',' << d.highUCornerAdjacentCells0305 << ','
        << d.maxAbsUBulk0305 << ',' << d.maxAbsUWallAdjacent0305 << ','
        << d.maxAbsUSolidAdjacent0305 << ',' << d.maxAbsUOpenAdjacent0305 << ','
        << d.maxAbsUCornerAdjacent0305 << ','
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
    d.emptyBulkCells0305 = hs.emptyBulkCells0305;
    d.emptyWallAdjacentCells0305 = hs.emptyWallAdjacentCells0305;
    d.emptySolidAdjacentCells0305 = hs.emptySolidAdjacentCells0305;
    d.emptyOpenAdjacentCells0305 = hs.emptyOpenAdjacentCells0305;
    d.emptyCornerAdjacentCells0305 = hs.emptyCornerAdjacentCells0305;
    d.lowNBulkCells0305 = hs.lowNBulkCells0305;
    d.lowNWallAdjacentCells0305 = hs.lowNWallAdjacentCells0305;
    d.lowNSolidAdjacentCells0305 = hs.lowNSolidAdjacentCells0305;
    d.lowNOpenAdjacentCells0305 = hs.lowNOpenAdjacentCells0305;
    d.lowNCornerAdjacentCells0305 = hs.lowNCornerAdjacentCells0305;
    d.wetBulkCells0305 = hs.wetBulkCells0305;
    d.wetWallAdjacentCells0305 = hs.wetWallAdjacentCells0305;
    d.wetSolidAdjacentCells0305 = hs.wetSolidAdjacentCells0305;
    d.wetOpenAdjacentCells0305 = hs.wetOpenAdjacentCells0305;
    d.wetCornerAdjacentCells0305 = hs.wetCornerAdjacentCells0305;
    d.highUThreshold0305 = cfg.highUThreshold;
    d.highUBulkCells0305 = hs.highUBulkCells0305;
    d.highUWallAdjacentCells0305 = hs.highUWallAdjacentCells0305;
    d.highUSolidAdjacentCells0305 = hs.highUSolidAdjacentCells0305;
    d.highUOpenAdjacentCells0305 = hs.highUOpenAdjacentCells0305;
    d.highUCornerAdjacentCells0305 = hs.highUCornerAdjacentCells0305;
    d.maxAbsUBulk0305 = hs.maxAbsUBulk0305;
    d.maxAbsUWallAdjacent0305 = hs.maxAbsUWallAdjacent0305;
    d.maxAbsUSolidAdjacent0305 = hs.maxAbsUSolidAdjacent0305;
    d.maxAbsUOpenAdjacent0305 = hs.maxAbsUOpenAdjacent0305;
    d.maxAbsUCornerAdjacent0305 = hs.maxAbsUCornerAdjacent0305;
    d.handled = true;
    d.totalSeconds = seconds_between(t0, Clock::now());
    write_csv_row_0304(params, d);
    return d;
}

} // namespace mpcd

#endif
