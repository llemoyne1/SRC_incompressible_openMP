#include "cuda_persistent_mpcd_step.h"
#include "cuda_particle_state.h"

#include <cuda_runtime.h>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdlib>
#include <cstddef>
#include <cstdint>
#include <stdexcept>
#include <string>
#include <vector>

namespace mpcd {
namespace {

#define MPCD_CUDA_CHECK(call) do { \
    cudaError_t err__ = (call); \
    if (err__ != cudaSuccess) { \
        throw std::runtime_error(std::string("CUDA error in ") + #call + ": " + cudaGetErrorString(err__)); \
    } \
} while (0)

using Clock = std::chrono::steady_clock;

double seconds_since(const Clock::time_point& t0) {
    return std::chrono::duration<double>(Clock::now() - t0).count();
}

template <typename T>
void cuda_free(T*& ptr) {
    if (ptr != nullptr) {
        cudaFree(ptr);
        ptr = nullptr;
    }
}


bool env_flag_enabled_0257(const char* name, const bool fallback = false) {
    const char* v = std::getenv(name);
    if (v == nullptr || *v == '\0') return fallback;
    const std::string s(v);
    return !(s == "0" || s == "false" || s == "FALSE" ||
             s == "off" || s == "OFF" || s == "no" || s == "NO");
}

std::uint64_t splitmix64_host(std::uint64_t x) {
    x += 0x9e3779b97f4a7c15ULL;
    x = (x ^ (x >> 30U)) * 0xbf58476d1ce4e5b9ULL;
    x = (x ^ (x >> 27U)) * 0x94d049bb133111ebULL;
    return x ^ (x >> 31U);
}

std::vector<std::uint8_t> normalized_roles(const ParticleState& state) {
    const std::size_t n = static_cast<std::size_t>(state.Np);
    if (state.role.empty()) return std::vector<std::uint8_t>(n, kParticleRoleFluid);
    return state.role;
}

struct DeviceBuffers {
    double *x = nullptr, *y = nullptr, *vx = nullptr, *vy = nullptr, *mass = nullptr;
    unsigned char* role = nullptr;
    int* cellId = nullptr;
    unsigned int* count = nullptr;
    double *cellMass = nullptr, *cellPx = nullptr, *cellPy = nullptr, *cellUx = nullptr, *cellUy = nullptr;
    double *cosA = nullptr, *sinA = nullptr, *cellKinetic = nullptr, *cellScale = nullptr;
    unsigned long long *fluidCounter = nullptr, *rotatedCounter = nullptr, *invalidCounter = nullptr;

    void release() {
        cuda_free(x); cuda_free(y); cuda_free(vx); cuda_free(vy); cuda_free(mass); cuda_free(role);
        cuda_free(cellId); cuda_free(count); cuda_free(cellMass); cuda_free(cellPx); cuda_free(cellPy);
        cuda_free(cellUx); cuda_free(cellUy); cuda_free(cosA); cuda_free(sinA); cuda_free(cellKinetic);
        cuda_free(cellScale); cuda_free(fluidCounter); cuda_free(rotatedCounter); cuda_free(invalidCounter);
    }
    ~DeviceBuffers() { release(); }
};

struct DeviceConfig {
    int Nx, Ny, numCells;
    double Lx, Ly, dx, dy;
    double shiftX, shiftY;
    int periodicX, periodicY;
    double domainXMin, domainXMax, domainYMin, domainYMax;
    int wallLeftEnabled, wallRightEnabled, wallBottomEnabled, wallTopEnabled;
    double wallAccommodation, wallGamma, wallVpMass;
    double wallUxLeft, wallUyLeft, wallUxRight, wallUyRight;
    double wallUxBottom, wallUyBottom, wallUxTop, wallUyTop;
    int immersedRectangleEnabled;
    int immersedFractionSamples;
    double immersedXMin, immersedXMax, immersedYMin, immersedYMax;
    double immersedWallUx, immersedWallUy;
    unsigned char fluidRole;
};

__device__ double wrap_periodic(double x, double L) {
    x = fmod(x, L);
    if (x < 0.0) x += L;
    if (x >= L) x -= L;
    return x;
}

__device__ int bounded_cell_index_device(double xs, double L, double dx, int N) {
    (void)L;
    int i = static_cast<int>(floor(xs / dx));
    if (i < 0) i = 0;
    if (i >= N) i = N - 1;
    return i;
}

__device__ int periodic_cell_index_device(double xs, double L, double dx, int N) {
    xs = wrap_periodic(xs, L);
    int i = static_cast<int>(floor(xs / dx));
    if (i < 0) i = 0;
    if (i >= N) i = N - 1;
    return i;
}

__device__ int cell_index_device(double x, double y, DeviceConfig cfg) {
    const double xs = x + cfg.shiftX;
    const double ys = y + cfg.shiftY;
    const int ix = cfg.periodicX
        ? periodic_cell_index_device(xs, cfg.Lx, cfg.dx, cfg.Nx)
        : bounded_cell_index_device(xs, cfg.Lx, cfg.dx, cfg.Nx);
    const int iy = cfg.periodicY
        ? periodic_cell_index_device(ys, cfg.Ly, cfg.dy, cfg.Ny)
        : bounded_cell_index_device(ys, cfg.Ly, cfg.dy, cfg.Ny);
    return ix + cfg.Nx * iy;
}

__device__ double overlap_length_device(double a0, double a1, double b0, double b1) {
    const double lo = fmax(a0, b0);
    const double hi = fmin(a1, b1);
    return hi > lo ? hi - lo : 0.0;
}

__device__ void add_virtual_wall_mass_momentum_device(double faceArea,
                                                       double fullCellArea,
                                                       double wallUx,
                                                       double wallUy,
                                                       DeviceConfig cfg,
                                                       double& mass,
                                                       double& px,
                                                       double& py) {
    if (!(faceArea > 0.0) || !(fullCellArea > 0.0)) return;
    const double equivalentCount = cfg.wallAccommodation * cfg.wallGamma * faceArea / fullCellArea;
    if (!(equivalentCount > 0.0)) return;
    const double vmass = equivalentCount * cfg.wallVpMass;
    mass += vmass;
    px += vmass * wallUx;
    py += vmass * wallUy;
}

__device__ bool point_inside_domain_device(double x, double y, DeviceConfig cfg) {
    return x >= cfg.domainXMin && x <= cfg.domainXMax &&
           y >= cfg.domainYMin && y <= cfg.domainYMax;
}

__device__ bool point_inside_immersed_rectangle_device(double x, double y, DeviceConfig cfg) {
    return x >= cfg.immersedXMin && x <= cfg.immersedXMax &&
           y >= cfg.immersedYMin && y <= cfg.immersedYMax;
}

__device__ double immersed_rectangle_fraction_device(int ix, int iy, DeviceConfig cfg) {
    if (!cfg.immersedRectangleEnabled) return 0.0;
    const int ns = cfg.immersedFractionSamples > 0 ? cfg.immersedFractionSamples : 1;
    const double x0 = static_cast<double>(ix) * cfg.dx - cfg.shiftX;
    const double y0 = static_cast<double>(iy) * cfg.dy - cfg.shiftY;
    int inside = 0;
    int fluidSamples = 0;
    const int total = ns * ns;
    for (int sy = 0; sy < ns; ++sy) {
        double y = y0 + (static_cast<double>(sy) + 0.5) * cfg.dy / static_cast<double>(ns);
        if (cfg.periodicY) y = wrap_periodic(y, cfg.Ly);
        for (int sx = 0; sx < ns; ++sx) {
            double x = x0 + (static_cast<double>(sx) + 0.5) * cfg.dx / static_cast<double>(ns);
            if (cfg.periodicX) x = wrap_periodic(x, cfg.Lx);
            if (!point_inside_domain_device(x, y, cfg)) continue;
            ++fluidSamples;
            if (point_inside_immersed_rectangle_device(x, y, cfg)) ++inside;
        }
    }
    const int denom = fluidSamples > 0 ? fluidSamples : total;
    return static_cast<double>(inside) / static_cast<double>(denom);
}

__global__ void add_wall_virtual_faces_persistent_kernel(int nc,
                                                         DeviceConfig cfg,
                                                         double* cellMass,
                                                         double* cellPx,
                                                         double* cellPy) {
    const int c = blockIdx.x * blockDim.x + threadIdx.x;
    if (c >= nc) return;
    if (cfg.wallAccommodation <= 0.0 || cfg.wallGamma <= 0.0 || cfg.wallVpMass <= 0.0) return;

    const int ix = c % cfg.Nx;
    const int iy = c / cfg.Nx;
    const double x0 = static_cast<double>(ix) * cfg.dx - cfg.shiftX;
    const double x1 = x0 + cfg.dx;
    const double y0 = static_cast<double>(iy) * cfg.dy - cfg.shiftY;
    const double y1 = y0 + cfg.dy;
    const double fullCellArea = cfg.dx * cfg.dy;

    double mass = cellMass[c];
    double px = cellPx[c];
    double py = cellPy[c];

    if (cfg.wallLeftEnabled) {
        const double outsideX = overlap_length_device(x0, x1, cfg.domainXMin - cfg.dx, cfg.domainXMin);
        const double insideY = cfg.periodicY ? cfg.dy : overlap_length_device(y0, y1, cfg.domainYMin, cfg.domainYMax);
        add_virtual_wall_mass_momentum_device(outsideX * insideY, fullCellArea, cfg.wallUxLeft, cfg.wallUyLeft, cfg, mass, px, py);
    }
    if (cfg.wallRightEnabled) {
        const double outsideX = overlap_length_device(x0, x1, cfg.domainXMax, cfg.domainXMax + cfg.dx);
        const double insideY = cfg.periodicY ? cfg.dy : overlap_length_device(y0, y1, cfg.domainYMin, cfg.domainYMax);
        add_virtual_wall_mass_momentum_device(outsideX * insideY, fullCellArea, cfg.wallUxRight, cfg.wallUyRight, cfg, mass, px, py);
    }
    if (cfg.wallBottomEnabled) {
        const double insideX = cfg.periodicX ? cfg.dx : overlap_length_device(x0, x1, cfg.domainXMin, cfg.domainXMax);
        const double outsideY = overlap_length_device(y0, y1, cfg.domainYMin - cfg.dy, cfg.domainYMin);
        add_virtual_wall_mass_momentum_device(insideX * outsideY, fullCellArea, cfg.wallUxBottom, cfg.wallUyBottom, cfg, mass, px, py);
    }
    if (cfg.wallTopEnabled) {
        const double insideX = cfg.periodicX ? cfg.dx : overlap_length_device(x0, x1, cfg.domainXMin, cfg.domainXMax);
        const double outsideY = overlap_length_device(y0, y1, cfg.domainYMax, cfg.domainYMax + cfg.dy);
        add_virtual_wall_mass_momentum_device(insideX * outsideY, fullCellArea, cfg.wallUxTop, cfg.wallUyTop, cfg, mass, px, py);
    }
    if (cfg.immersedRectangleEnabled) {
        const double solidFraction = immersed_rectangle_fraction_device(ix, iy, cfg);
        add_virtual_wall_mass_momentum_device(solidFraction * fullCellArea, fullCellArea,
                                              cfg.immersedWallUx, cfg.immersedWallUy, cfg, mass, px, py);
    }

    cellMass[c] = mass;
    cellPx[c] = px;
    cellPy[c] = py;
}

__global__ void reset_persistent_cells_kernel(int n, int nc,
                                              int* cellId,
                                              unsigned int* count,
                                              double* cellMass,
                                              double* cellPx,
                                              double* cellPy,
                                              double* cellUx,
                                              double* cellUy,
                                              double* cellKinetic,
                                              double* cellScale) {
    const int tid = blockIdx.x * blockDim.x + threadIdx.x;
    const int stride = blockDim.x * gridDim.x;
    for (int i = tid; i < n; i += stride) cellId[i] = -1;
    for (int c = tid; c < nc; c += stride) {
        count[c] = 0u;
        cellMass[c] = 0.0;
        cellPx[c] = 0.0;
        cellPy[c] = 0.0;
        cellUx[c] = 0.0;
        cellUy[c] = 0.0;
        cellKinetic[c] = 0.0;
        cellScale[c] = 1.0;
    }
}

__global__ void deposit_persistent_kernel(int n,
                                          const double* x,
                                          const double* y,
                                          const double* vx,
                                          const double* vy,
                                          const double* mass,
                                          const unsigned char* role,
                                          DeviceConfig cfg,
                                          int* cellId,
                                          unsigned int* count,
                                          double* cellMass,
                                          double* cellPx,
                                          double* cellPy,
                                          unsigned long long* fluidCounter) {
    const int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= n) return;
    if (role[i] != cfg.fluidRole) return;
    const int c = cell_index_device(x[i], y[i], cfg);
    cellId[i] = c;
    const double m = mass[i];
    atomicAdd(&count[c], 1u);
    atomicAdd(&cellMass[c], m);
    atomicAdd(&cellPx[c], m * vx[i]);
    atomicAdd(&cellPy[c], m * vy[i]);
    atomicAdd(fluidCounter, 1ull);
}

__global__ void finalize_velocity_persistent_kernel(int nc,
                                                    const double* cellMass,
                                                    const double* cellPx,
                                                    const double* cellPy,
                                                    double* cellUx,
                                                    double* cellUy) {
    const int c = blockIdx.x * blockDim.x + threadIdx.x;
    if (c >= nc) return;
    const double m = cellMass[c];
    if (m > 0.0) {
        cellUx[c] = cellPx[c] / m;
        cellUy[c] = cellPy[c] / m;
    } else {
        cellUx[c] = 0.0;
        cellUy[c] = 0.0;
    }
}

__global__ void src_rotate_persistent_kernel(int n,
                                             const int* cellId,
                                             const unsigned char* role,
                                             const double* cellUx,
                                             const double* cellUy,
                                             const double* cosA,
                                             const double* sinA,
                                             DeviceConfig cfg,
                                             double* vx,
                                             double* vy,
                                             unsigned long long* rotatedCounter,
                                             unsigned long long* invalidCounter) {
    const int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= n) return;
    if (role[i] != cfg.fluidRole) return;
    const int c = cellId[i];
    if (c < 0 || c >= cfg.numCells) {
        atomicAdd(invalidCounter, 1ull);
        return;
    }
    const double ux = cellUx[c];
    const double uy = cellUy[c];
    const double dvx = vx[i] - ux;
    const double dvy = vy[i] - uy;
    const double ca = cosA[c];
    const double sa = sinA[c];
    vx[i] = ux + ca * dvx - sa * dvy;
    vy[i] = uy + sa * dvx + ca * dvy;
    atomicAdd(rotatedCounter, 1ull);
}

__global__ void kinetic_persistent_kernel(int n,
                                          const int* cellId,
                                          const unsigned char* role,
                                          const double* mass,
                                          const double* vx,
                                          const double* vy,
                                          const double* cellUx,
                                          const double* cellUy,
                                          DeviceConfig cfg,
                                          double* cellKinetic) {
    const int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= n) return;
    if (role[i] != cfg.fluidRole) return;
    const int c = cellId[i];
    if (c < 0 || c >= cfg.numCells) return;
    const double dvx = vx[i] - cellUx[c];
    const double dvy = vy[i] - cellUy[c];
    atomicAdd(&cellKinetic[c], 0.5 * mass[i] * (dvx * dvx + dvy * dvy));
}

__global__ void scale_persistent_kernel(int nc,
                                        const unsigned int* count,
                                        const double* cellKinetic,
                                        double targetKBT,
                                        int minParticles,
                                        double epsilon,
                                        double* cellScale) {
    const int c = blockIdx.x * blockDim.x + threadIdx.x;
    if (c >= nc) return;
    double s = 1.0;
    const unsigned int n = count[c];
    const double K = cellKinetic[c];
    if (n >= static_cast<unsigned int>(minParticles) && K > epsilon) {
        const double dof = 2.0 * static_cast<double>(n - 1u);
        const double targetK = 0.5 * dof * targetKBT;
        s = sqrt(targetK / K);
    }
    cellScale[c] = s;
}

__global__ void apply_thermostat_persistent_kernel(int n,
                                                   const int* cellId,
                                                   const unsigned char* role,
                                                   const double* cellUx,
                                                   const double* cellUy,
                                                   const double* cellScale,
                                                   DeviceConfig cfg,
                                                   double* vx,
                                                   double* vy) {
    const int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= n) return;
    if (role[i] != cfg.fluidRole) return;
    const int c = cellId[i];
    if (c < 0 || c >= cfg.numCells) return;
    const double s = cellScale[c];
    if (s == 1.0) return;
    const double ux = cellUx[c];
    const double uy = cellUy[c];
    vx[i] = ux + s * (vx[i] - ux);
    vy[i] = uy + s * (vy[i] - uy);
}

} // namespace

bool cuda_persistent_mpcd_step_available() {
#ifdef MPCD_ENABLE_CUDA_PERSISTENT_STEP
    int count = 0;
    const cudaError_t err = cudaGetDeviceCount(&count);
    if (err != cudaSuccess) {
        cudaGetLastError();
        return false;
    }
    return count > 0;
#else
    return false;
#endif
}


namespace {
std::uint64_t g_consumedThermostatStep = 0u;
bool g_consumedThermostatValid = false;
ThermostatDiagnostics g_consumedThermostatDiag{};
}

void cuda_persistent_record_consumed_thermostat(std::uint64_t step, const ThermostatDiagnostics& diag) {
    g_consumedThermostatStep = step;
    g_consumedThermostatDiag = diag;
    g_consumedThermostatValid = true;
}

bool cuda_persistent_take_consumed_thermostat(std::uint64_t step, ThermostatDiagnostics& diag) {
    if (!g_consumedThermostatValid || g_consumedThermostatStep != step) return false;
    diag = g_consumedThermostatDiag;
    g_consumedThermostatValid = false;
    return true;
}

CudaPersistentMpcdStepDiagnostics cuda_apply_persistent_tg_impl(
    ParticleState& state,
    std::vector<int>* cellIdOut,
    std::vector<std::uint32_t>* cellCountOut,
    std::vector<double>* cellMassOut,
    std::vector<double>* cellUxOut,
    std::vector<double>* cellUyOut,
    const CudaPersistentMpcdStepConfig& config,
    const bool applyThermostat,
    ThermostatDiagnostics* thermostatDiagOut) {
#ifndef MPCD_ENABLE_CUDA_PERSISTENT_STEP
    (void)state; (void)cellIdOut; (void)cellCountOut; (void)cellMassOut; (void)cellUxOut; (void)cellUyOut; (void)config; (void)applyThermostat; (void)thermostatDiagOut;
    throw std::runtime_error("cuda_apply_persistent_tg_impl called without MPCD_ENABLE_CUDA_PERSISTENT_STEP");
#else
    validate_particle_state(state, "cuda_apply_persistent_tg_deposit_src_thermostat");
    if (config.Nx <= 0 || config.Ny <= 0) throw std::runtime_error("persistent CUDA step: invalid grid");
    if (!(config.Lx > 0.0) || !(config.Ly > 0.0)) throw std::runtime_error("persistent CUDA step: invalid domain");
    if (!(config.targetKBT > 0.0)) throw std::runtime_error("persistent CUDA step: targetKBT must be positive");

    const std::size_t n = static_cast<std::size_t>(state.Np);
    const int nInt = static_cast<int>(n);
    if (static_cast<std::size_t>(nInt) != n) throw std::runtime_error("persistent CUDA step: too many particles for prototype int kernels");
    const int nc = config.Nx * config.Ny;
    const int cycles = std::max(1, config.cycles);
    const int threads = std::max(32, config.threadsPerBlock);
    const int particleBlocks = std::max(1, (nInt + threads - 1) / threads);
    const int cellBlocks = std::max(1, (nc + threads - 1) / threads);
    const int resetBlocks = std::max(particleBlocks, cellBlocks);

    std::vector<std::uint8_t> roleHost = normalized_roles(state);
    std::vector<double> cosHost(static_cast<std::size_t>(nc), std::cos(config.rotationAngle));
    std::vector<double> sinHost(static_cast<std::size_t>(nc), std::sin(config.rotationAngle));
    if (config.randomRotationSign) {
        for (int c = 0; c < nc; ++c) {
            const std::uint64_t h = splitmix64_host(config.rngSeed ^
                                                    (config.step * 0x9e3779b97f4a7c15ULL) ^
                                                    static_cast<std::uint64_t>(c));
            if ((h & 1ULL) == 0ULL) sinHost[static_cast<std::size_t>(c)] = -sinHost[static_cast<std::size_t>(c)];
        }
    }

    CudaPersistentMpcdStepDiagnostics diag{};
    diag.particlesVisited = state.Np;
    diag.numCells = nc;
    diag.cycles = cycles;

    DeviceBuffers b;
    const std::size_t nBytesD = n * sizeof(double);
    const std::size_t nBytesR = n * sizeof(unsigned char);
    const std::size_t nBytesI = n * sizeof(int);
    const std::size_t cBytesD = static_cast<std::size_t>(nc) * sizeof(double);
    const std::size_t cBytesU = static_cast<std::size_t>(nc) * sizeof(unsigned int);

    const auto tTotal0 = Clock::now();
    auto t0 = Clock::now();

    MPCD_CUDA_CHECK(cudaMalloc(&b.x, nBytesD));
    MPCD_CUDA_CHECK(cudaMalloc(&b.y, nBytesD));
    MPCD_CUDA_CHECK(cudaMalloc(&b.vx, nBytesD));
    MPCD_CUDA_CHECK(cudaMalloc(&b.vy, nBytesD));
    MPCD_CUDA_CHECK(cudaMalloc(&b.mass, nBytesD));
    MPCD_CUDA_CHECK(cudaMalloc(&b.role, nBytesR));
    MPCD_CUDA_CHECK(cudaMalloc(&b.cellId, nBytesI));
    MPCD_CUDA_CHECK(cudaMalloc(&b.count, cBytesU));
    MPCD_CUDA_CHECK(cudaMalloc(&b.cellMass, cBytesD));
    MPCD_CUDA_CHECK(cudaMalloc(&b.cellPx, cBytesD));
    MPCD_CUDA_CHECK(cudaMalloc(&b.cellPy, cBytesD));
    MPCD_CUDA_CHECK(cudaMalloc(&b.cellUx, cBytesD));
    MPCD_CUDA_CHECK(cudaMalloc(&b.cellUy, cBytesD));
    MPCD_CUDA_CHECK(cudaMalloc(&b.cosA, cBytesD));
    MPCD_CUDA_CHECK(cudaMalloc(&b.sinA, cBytesD));
    MPCD_CUDA_CHECK(cudaMalloc(&b.cellKinetic, cBytesD));
    MPCD_CUDA_CHECK(cudaMalloc(&b.cellScale, cBytesD));
    MPCD_CUDA_CHECK(cudaMalloc(&b.fluidCounter, sizeof(unsigned long long)));
    MPCD_CUDA_CHECK(cudaMalloc(&b.rotatedCounter, sizeof(unsigned long long)));
    MPCD_CUDA_CHECK(cudaMalloc(&b.invalidCounter, sizeof(unsigned long long)));

    MPCD_CUDA_CHECK(cudaMemcpy(b.x, state.x.data(), nBytesD, cudaMemcpyHostToDevice));
    MPCD_CUDA_CHECK(cudaMemcpy(b.y, state.y.data(), nBytesD, cudaMemcpyHostToDevice));
    MPCD_CUDA_CHECK(cudaMemcpy(b.vx, state.vx.data(), nBytesD, cudaMemcpyHostToDevice));
    MPCD_CUDA_CHECK(cudaMemcpy(b.vy, state.vy.data(), nBytesD, cudaMemcpyHostToDevice));
    MPCD_CUDA_CHECK(cudaMemcpy(b.mass, state.mass.data(), nBytesD, cudaMemcpyHostToDevice));
    MPCD_CUDA_CHECK(cudaMemcpy(b.role, roleHost.data(), nBytesR, cudaMemcpyHostToDevice));
    MPCD_CUDA_CHECK(cudaMemcpy(b.cosA, cosHost.data(), cBytesD, cudaMemcpyHostToDevice));
    MPCD_CUDA_CHECK(cudaMemcpy(b.sinA, sinHost.data(), cBytesD, cudaMemcpyHostToDevice));
    MPCD_CUDA_CHECK(cudaMemset(b.fluidCounter, 0, sizeof(unsigned long long)));
    MPCD_CUDA_CHECK(cudaMemset(b.rotatedCounter, 0, sizeof(unsigned long long)));
    MPCD_CUDA_CHECK(cudaMemset(b.invalidCounter, 0, sizeof(unsigned long long)));
    MPCD_CUDA_CHECK(cudaDeviceSynchronize());
    diag.uploadSeconds = seconds_since(t0);

    DeviceConfig cfg{};
    cfg.Nx = config.Nx;
    cfg.Ny = config.Ny;
    cfg.numCells = nc;
    cfg.Lx = config.Lx;
    cfg.Ly = config.Ly;
    cfg.dx = config.Lx / static_cast<double>(config.Nx);
    cfg.dy = config.Ly / static_cast<double>(config.Ny);
    cfg.shiftX = config.shiftX;
    cfg.shiftY = config.shiftY;
    cfg.periodicX = config.periodicX ? 1 : 0;
    cfg.periodicY = config.periodicY ? 1 : 0;
    cfg.domainXMin = config.domainXMin;
    cfg.domainXMax = config.domainXMax;
    cfg.domainYMin = config.domainYMin;
    cfg.domainYMax = config.domainYMax;
    cfg.wallLeftEnabled = config.wallLeftEnabled;
    cfg.wallRightEnabled = config.wallRightEnabled;
    cfg.wallBottomEnabled = config.wallBottomEnabled;
    cfg.wallTopEnabled = config.wallTopEnabled;
    cfg.wallAccommodation = config.wallAccommodation;
    cfg.wallGamma = config.wallGamma;
    cfg.wallVpMass = config.wallVpMass;
    cfg.wallUxLeft = config.wallUxLeft;
    cfg.wallUyLeft = config.wallUyLeft;
    cfg.wallUxRight = config.wallUxRight;
    cfg.wallUyRight = config.wallUyRight;
    cfg.wallUxBottom = config.wallUxBottom;
    cfg.wallUyBottom = config.wallUyBottom;
    cfg.wallUxTop = config.wallUxTop;
    cfg.wallUyTop = config.wallUyTop;
    cfg.immersedRectangleEnabled = config.immersedRectangleEnabled;
    cfg.immersedFractionSamples = config.immersedFractionSamples;
    cfg.immersedXMin = config.immersedXMin;
    cfg.immersedXMax = config.immersedXMax;
    cfg.immersedYMin = config.immersedYMin;
    cfg.immersedYMax = config.immersedYMax;
    cfg.immersedWallUx = config.immersedWallUx;
    cfg.immersedWallUy = config.immersedWallUy;
    cfg.fluidRole = static_cast<unsigned char>(kParticleRoleFluid);

    t0 = Clock::now();
    for (int cycle = 0; cycle < cycles; ++cycle) {
        reset_persistent_cells_kernel<<<resetBlocks, threads>>>(nInt, nc, b.cellId, b.count, b.cellMass,
                                                                b.cellPx, b.cellPy, b.cellUx, b.cellUy,
                                                                b.cellKinetic, b.cellScale);
        MPCD_CUDA_CHECK(cudaGetLastError());
        deposit_persistent_kernel<<<particleBlocks, threads>>>(nInt, b.x, b.y, b.vx, b.vy, b.mass, b.role,
                                                               cfg, b.cellId, b.count, b.cellMass, b.cellPx,
                                                               b.cellPy, b.fluidCounter);
        MPCD_CUDA_CHECK(cudaGetLastError());
        if (cfg.wallLeftEnabled || cfg.wallRightEnabled || cfg.wallBottomEnabled || cfg.wallTopEnabled || cfg.immersedRectangleEnabled) {
            add_wall_virtual_faces_persistent_kernel<<<cellBlocks, threads>>>(nc, cfg, b.cellMass, b.cellPx, b.cellPy);
            MPCD_CUDA_CHECK(cudaGetLastError());
        }
        finalize_velocity_persistent_kernel<<<cellBlocks, threads>>>(nc, b.cellMass, b.cellPx, b.cellPy,
                                                                     b.cellUx, b.cellUy);
        MPCD_CUDA_CHECK(cudaGetLastError());
        src_rotate_persistent_kernel<<<particleBlocks, threads>>>(nInt, b.cellId, b.role, b.cellUx, b.cellUy,
                                                                  b.cosA, b.sinA, cfg, b.vx, b.vy,
                                                                  b.rotatedCounter, b.invalidCounter);
        MPCD_CUDA_CHECK(cudaGetLastError());
        if (applyThermostat) {
            MPCD_CUDA_CHECK(cudaMemset(b.cellKinetic, 0, cBytesD));
            kinetic_persistent_kernel<<<particleBlocks, threads>>>(nInt, b.cellId, b.role, b.mass, b.vx, b.vy,
                                                                   b.cellUx, b.cellUy, cfg, b.cellKinetic);
            MPCD_CUDA_CHECK(cudaGetLastError());
            scale_persistent_kernel<<<cellBlocks, threads>>>(nc, b.count, b.cellKinetic, config.targetKBT,
                                                             std::max(1, config.thermostatMinParticles),
                                                             config.thermostatEpsilon, b.cellScale);
            MPCD_CUDA_CHECK(cudaGetLastError());
            apply_thermostat_persistent_kernel<<<particleBlocks, threads>>>(nInt, b.cellId, b.role, b.cellUx,
                                                                           b.cellUy, b.cellScale, cfg, b.vx, b.vy);
            MPCD_CUDA_CHECK(cudaGetLastError());
        }
    }
    MPCD_CUDA_CHECK(cudaDeviceSynchronize());
    diag.kernelSeconds = seconds_since(t0);

    t0 = Clock::now();
    MPCD_CUDA_CHECK(cudaMemcpy(state.vx.data(), b.vx, nBytesD, cudaMemcpyDeviceToHost));
    MPCD_CUDA_CHECK(cudaMemcpy(state.vy.data(), b.vy, nBytesD, cudaMemcpyDeviceToHost));
    if (cellIdOut != nullptr) {
        cellIdOut->assign(n, -1);
        MPCD_CUDA_CHECK(cudaMemcpy(cellIdOut->data(), b.cellId, nBytesI, cudaMemcpyDeviceToHost));
    }
    if (cellCountOut != nullptr) {
        cellCountOut->assign(static_cast<std::size_t>(nc), 0u);
        MPCD_CUDA_CHECK(cudaMemcpy(cellCountOut->data(), b.count, cBytesU, cudaMemcpyDeviceToHost));
    }
    if (cellMassOut != nullptr) {
        cellMassOut->assign(static_cast<std::size_t>(nc), 0.0);
        MPCD_CUDA_CHECK(cudaMemcpy(cellMassOut->data(), b.cellMass, cBytesD, cudaMemcpyDeviceToHost));
    }
    if (cellUxOut != nullptr) {
        cellUxOut->assign(static_cast<std::size_t>(nc), 0.0);
        MPCD_CUDA_CHECK(cudaMemcpy(cellUxOut->data(), b.cellUx, cBytesD, cudaMemcpyDeviceToHost));
    }
    if (cellUyOut != nullptr) {
        cellUyOut->assign(static_cast<std::size_t>(nc), 0.0);
        MPCD_CUDA_CHECK(cudaMemcpy(cellUyOut->data(), b.cellUy, cBytesD, cudaMemcpyDeviceToHost));
    }
    std::vector<double> kineticHost;
    std::vector<double> scaleHost;
    if (applyThermostat && thermostatDiagOut != nullptr) {
        kineticHost.assign(static_cast<std::size_t>(nc), 0.0);
        scaleHost.assign(static_cast<std::size_t>(nc), 1.0);
        MPCD_CUDA_CHECK(cudaMemcpy(kineticHost.data(), b.cellKinetic, cBytesD, cudaMemcpyDeviceToHost));
        MPCD_CUDA_CHECK(cudaMemcpy(scaleHost.data(), b.cellScale, cBytesD, cudaMemcpyDeviceToHost));
    }
    unsigned long long fluid = 0ull, rotated = 0ull, invalid = 0ull;
    MPCD_CUDA_CHECK(cudaMemcpy(&fluid, b.fluidCounter, sizeof(unsigned long long), cudaMemcpyDeviceToHost));
    MPCD_CUDA_CHECK(cudaMemcpy(&rotated, b.rotatedCounter, sizeof(unsigned long long), cudaMemcpyDeviceToHost));
    MPCD_CUDA_CHECK(cudaMemcpy(&invalid, b.invalidCounter, sizeof(unsigned long long), cudaMemcpyDeviceToHost));
    MPCD_CUDA_CHECK(cudaDeviceSynchronize());
    diag.downloadSeconds = seconds_since(t0);

    diag.fluidParticles = static_cast<std::uint64_t>(fluid) / static_cast<std::uint64_t>(cycles);
    diag.particlesRotated = static_cast<std::uint64_t>(rotated);
    diag.invalidCellParticles = static_cast<std::uint64_t>(invalid);

    if (applyThermostat && thermostatDiagOut != nullptr && cellCountOut != nullptr && !kineticHost.empty()) {
        ThermostatDiagnostics td{};
        double totalKBefore = 0.0;
        double targetKTotal = 0.0;
        double scaleSum = 0.0;
        double scaleMin = 1.0e300;
        double scaleMax = 0.0;
        std::uint64_t dofTotal = 0u;
        for (int c = 0; c < nc; ++c) {
            const std::size_t kk = static_cast<std::size_t>(c);
            const std::uint32_t count = (*cellCountOut)[kk];
            const double K = kineticHost[kk];
            if (count < static_cast<std::uint32_t>(std::max(1, config.thermostatMinParticles))) continue;
            if (!(K > config.thermostatEpsilon)) continue;
            const double dof = 2.0 * static_cast<double>(count - 1u);
            const double targetK = 0.5 * dof * config.targetKBT;
            const double scale = scaleHost[kk];
            totalKBefore += K;
            targetKTotal += targetK;
            dofTotal += static_cast<std::uint64_t>(2u * (count - 1u));
            td.cellsRescaled += 1u;
            td.particlesRescaled += static_cast<std::uint64_t>(count);
            scaleSum += scale;
            if (scale < scaleMin) scaleMin = scale;
            if (scale > scaleMax) scaleMax = scale;
        }
        td.applied = td.cellsRescaled > 0u;
        td.kBTBefore = dofTotal > 0u ? (2.0 * totalKBefore / static_cast<double>(dofTotal)) : 0.0;
        td.kBTAfter = dofTotal > 0u ? (2.0 * targetKTotal / static_cast<double>(dofTotal)) : 0.0;
        td.scaleMean = td.cellsRescaled > 0u ? scaleSum / static_cast<double>(td.cellsRescaled) : 1.0;
        td.scaleMin = td.cellsRescaled > 0u ? scaleMin : 1.0;
        td.scaleMax = td.cellsRescaled > 0u ? scaleMax : 1.0;
        *thermostatDiagOut = td;
        diag.thermostatCellsRescaled = td.cellsRescaled;
        diag.thermostatParticlesRescaled = td.particlesRescaled;
        diag.thermostatKBTBefore = td.kBTBefore;
        diag.thermostatKBTAfter = td.kBTAfter;
        diag.thermostatScaleMean = td.scaleMean;
        diag.thermostatScaleMin = td.scaleMin;
        diag.thermostatScaleMax = td.scaleMax;
    }

    diag.totalSeconds = seconds_since(tTotal0);
    return diag;
#endif
}


CudaPersistentMpcdStepDiagnostics cuda_apply_persistent_tg_deposit_src_thermostat(
    ParticleState& state,
    const CudaPersistentMpcdStepConfig& config) {
    return cuda_apply_persistent_tg_impl(state, nullptr, nullptr, nullptr, nullptr, nullptr, config, true, nullptr);
}

CudaPersistentMpcdStepDiagnostics cuda_apply_persistent_tg_deposit_src_collision(
    ParticleState& state,
    std::vector<int>& cellIdOut,
    std::vector<std::uint32_t>& cellCountOut,
    std::vector<double>& cellMassOut,
    std::vector<double>& cellUxOut,
    std::vector<double>& cellUyOut,
    const CudaPersistentMpcdStepConfig& config) {
    return cuda_apply_persistent_tg_impl(state, &cellIdOut, &cellCountOut, &cellMassOut, &cellUxOut, &cellUyOut, config, false, nullptr);
}

CudaPersistentMpcdStepDiagnostics cuda_apply_persistent_tg_deposit_src_collision_thermostat(
    ParticleState& state,
    std::vector<int>& cellIdOut,
    std::vector<std::uint32_t>& cellCountOut,
    std::vector<double>& cellMassOut,
    std::vector<double>& cellUxOut,
    std::vector<double>& cellUyOut,
    const CudaPersistentMpcdStepConfig& config,
    ThermostatDiagnostics* thermostatDiagOut) {
    return cuda_apply_persistent_tg_impl(state, &cellIdOut, &cellCountOut, &cellMassOut, &cellUxOut, &cellUyOut, config, true, thermostatDiagOut);
}


CudaPersistentMpcdStepDiagnostics cuda_apply_persistent_tg_deposit_src_collision_thermostat(
    CudaParticleState& gpuState,
    ParticleState& downloadTarget,
    std::vector<int>& cellIdOut,
    std::vector<std::uint32_t>& cellCountOut,
    std::vector<double>& cellMassOut,
    std::vector<double>& cellUxOut,
    std::vector<double>& cellUyOut,
    const CudaPersistentMpcdStepConfig& config,
    ThermostatDiagnostics* thermostatDiagOut) {
#if !defined(MPCD_ENABLE_CUDA_PERSISTENT_STEP) || !defined(MPCD_ENABLE_CUDA_PARTICLE_STATE)
    (void)gpuState; (void)downloadTarget; (void)cellIdOut; (void)cellCountOut; (void)cellMassOut; (void)cellUxOut; (void)cellUyOut; (void)config; (void)thermostatDiagOut;
    throw std::runtime_error("cuda_apply_persistent_tg_deposit_src_collision_thermostat(CudaParticleState) requires MPCD_ENABLE_CUDA_PERSISTENT_STEP and MPCD_ENABLE_CUDA_PARTICLE_STATE");
#else
    validate_particle_state(downloadTarget, "cuda_apply_persistent_tg_deposit_src_collision_thermostat(shared downloadTarget)");
    if (config.Nx <= 0 || config.Ny <= 0) throw std::runtime_error("persistent CUDA shared-state step: invalid grid");
    if (!(config.Lx > 0.0) || !(config.Ly > 0.0)) throw std::runtime_error("persistent CUDA shared-state step: invalid domain");
    if (!(config.targetKBT > 0.0)) throw std::runtime_error("persistent CUDA shared-state step: targetKBT must be positive");

    const CudaParticleDeviceView pv = gpuState.device_view();
    if (pv.n == 0u) throw std::runtime_error("persistent CUDA shared-state step: empty CudaParticleState");
    if (downloadTarget.Np != pv.n) throw std::runtime_error("persistent CUDA shared-state step: host particle count mismatch");
    if (pv.x == nullptr || pv.y == nullptr || pv.vx == nullptr || pv.vy == nullptr || pv.mass == nullptr || pv.role == nullptr) {
        throw std::runtime_error("persistent CUDA shared-state step: incomplete CudaParticleState device view");
    }

    const std::size_t n = static_cast<std::size_t>(pv.n);
    const int nInt = static_cast<int>(n);
    if (static_cast<std::size_t>(nInt) != n) throw std::runtime_error("persistent CUDA shared-state step: too many particles for prototype int kernels");
    const int nc = config.Nx * config.Ny;
    const int cycles = std::max(1, config.cycles);
    const int threads = std::max(32, config.threadsPerBlock);
    const int particleBlocks = std::max(1, (nInt + threads - 1) / threads);
    const int cellBlocks = std::max(1, (nc + threads - 1) / threads);
    const int resetBlocks = std::max(particleBlocks, cellBlocks);

    std::vector<double> cosHost(static_cast<std::size_t>(nc), std::cos(config.rotationAngle));
    std::vector<double> sinHost(static_cast<std::size_t>(nc), std::sin(config.rotationAngle));
    if (config.randomRotationSign) {
        for (int c = 0; c < nc; ++c) {
            const std::uint64_t h = splitmix64_host(config.rngSeed ^
                                                    (config.step * 0x9e3779b97f4a7c15ULL) ^
                                                    static_cast<std::uint64_t>(c));
            if ((h & 1ULL) == 0ULL) sinHost[static_cast<std::size_t>(c)] = -sinHost[static_cast<std::size_t>(c)];
        }
    }

    CudaPersistentMpcdStepDiagnostics diag{};
    diag.particlesVisited = pv.n;
    diag.numCells = nc;
    diag.cycles = cycles;

    DeviceBuffers b;
    const std::size_t nBytesI = n * sizeof(int);
    const std::size_t cBytesD = static_cast<std::size_t>(nc) * sizeof(double);
    const std::size_t cBytesU = static_cast<std::size_t>(nc) * sizeof(unsigned int);

    const auto tTotal0 = Clock::now();
    auto t0 = Clock::now();

    // 0219: particle arrays are owned by CudaParticleState. Allocate only the
    // transient cell/workspace arrays needed by the persistent substep.
    MPCD_CUDA_CHECK(cudaMalloc(&b.cellId, nBytesI));
    MPCD_CUDA_CHECK(cudaMalloc(&b.count, cBytesU));
    MPCD_CUDA_CHECK(cudaMalloc(&b.cellMass, cBytesD));
    MPCD_CUDA_CHECK(cudaMalloc(&b.cellPx, cBytesD));
    MPCD_CUDA_CHECK(cudaMalloc(&b.cellPy, cBytesD));
    MPCD_CUDA_CHECK(cudaMalloc(&b.cellUx, cBytesD));
    MPCD_CUDA_CHECK(cudaMalloc(&b.cellUy, cBytesD));
    MPCD_CUDA_CHECK(cudaMalloc(&b.cosA, cBytesD));
    MPCD_CUDA_CHECK(cudaMalloc(&b.sinA, cBytesD));
    MPCD_CUDA_CHECK(cudaMalloc(&b.cellKinetic, cBytesD));
    MPCD_CUDA_CHECK(cudaMalloc(&b.cellScale, cBytesD));
    MPCD_CUDA_CHECK(cudaMalloc(&b.fluidCounter, sizeof(unsigned long long)));
    MPCD_CUDA_CHECK(cudaMalloc(&b.rotatedCounter, sizeof(unsigned long long)));
    MPCD_CUDA_CHECK(cudaMalloc(&b.invalidCounter, sizeof(unsigned long long)));

    MPCD_CUDA_CHECK(cudaMemcpy(b.cosA, cosHost.data(), cBytesD, cudaMemcpyHostToDevice));
    MPCD_CUDA_CHECK(cudaMemcpy(b.sinA, sinHost.data(), cBytesD, cudaMemcpyHostToDevice));
    MPCD_CUDA_CHECK(cudaMemset(b.fluidCounter, 0, sizeof(unsigned long long)));
    MPCD_CUDA_CHECK(cudaMemset(b.rotatedCounter, 0, sizeof(unsigned long long)));
    MPCD_CUDA_CHECK(cudaMemset(b.invalidCounter, 0, sizeof(unsigned long long)));
    MPCD_CUDA_CHECK(cudaDeviceSynchronize());
    diag.uploadSeconds = seconds_since(t0);

    DeviceConfig cfg{};
    cfg.Nx = config.Nx;
    cfg.Ny = config.Ny;
    cfg.numCells = nc;
    cfg.Lx = config.Lx;
    cfg.Ly = config.Ly;
    cfg.dx = config.Lx / static_cast<double>(config.Nx);
    cfg.dy = config.Ly / static_cast<double>(config.Ny);
    cfg.shiftX = config.shiftX;
    cfg.shiftY = config.shiftY;
    cfg.periodicX = config.periodicX ? 1 : 0;
    cfg.periodicY = config.periodicY ? 1 : 0;
    cfg.domainXMin = config.domainXMin;
    cfg.domainXMax = config.domainXMax;
    cfg.domainYMin = config.domainYMin;
    cfg.domainYMax = config.domainYMax;
    cfg.wallLeftEnabled = config.wallLeftEnabled;
    cfg.wallRightEnabled = config.wallRightEnabled;
    cfg.wallBottomEnabled = config.wallBottomEnabled;
    cfg.wallTopEnabled = config.wallTopEnabled;
    cfg.wallAccommodation = config.wallAccommodation;
    cfg.wallGamma = config.wallGamma;
    cfg.wallVpMass = config.wallVpMass;
    cfg.wallUxLeft = config.wallUxLeft;
    cfg.wallUyLeft = config.wallUyLeft;
    cfg.wallUxRight = config.wallUxRight;
    cfg.wallUyRight = config.wallUyRight;
    cfg.wallUxBottom = config.wallUxBottom;
    cfg.wallUyBottom = config.wallUyBottom;
    cfg.wallUxTop = config.wallUxTop;
    cfg.wallUyTop = config.wallUyTop;
    cfg.immersedRectangleEnabled = config.immersedRectangleEnabled;
    cfg.immersedFractionSamples = config.immersedFractionSamples;
    cfg.immersedXMin = config.immersedXMin;
    cfg.immersedXMax = config.immersedXMax;
    cfg.immersedYMin = config.immersedYMin;
    cfg.immersedYMax = config.immersedYMax;
    cfg.immersedWallUx = config.immersedWallUx;
    cfg.immersedWallUy = config.immersedWallUy;
    cfg.fluidRole = static_cast<unsigned char>(kParticleRoleFluid);

    t0 = Clock::now();
    for (int cycle = 0; cycle < cycles; ++cycle) {
        reset_persistent_cells_kernel<<<resetBlocks, threads>>>(nInt, nc, b.cellId, b.count, b.cellMass,
                                                                b.cellPx, b.cellPy, b.cellUx, b.cellUy,
                                                                b.cellKinetic, b.cellScale);
        MPCD_CUDA_CHECK(cudaGetLastError());
        deposit_persistent_kernel<<<particleBlocks, threads>>>(nInt, pv.x, pv.y, pv.vx, pv.vy, pv.mass, pv.role,
                                                               cfg, b.cellId, b.count, b.cellMass, b.cellPx,
                                                               b.cellPy, b.fluidCounter);
        MPCD_CUDA_CHECK(cudaGetLastError());
        if (cfg.wallLeftEnabled || cfg.wallRightEnabled || cfg.wallBottomEnabled || cfg.wallTopEnabled || cfg.immersedRectangleEnabled) {
            add_wall_virtual_faces_persistent_kernel<<<cellBlocks, threads>>>(nc, cfg, b.cellMass, b.cellPx, b.cellPy);
            MPCD_CUDA_CHECK(cudaGetLastError());
        }
        finalize_velocity_persistent_kernel<<<cellBlocks, threads>>>(nc, b.cellMass, b.cellPx, b.cellPy,
                                                                     b.cellUx, b.cellUy);
        MPCD_CUDA_CHECK(cudaGetLastError());
        src_rotate_persistent_kernel<<<particleBlocks, threads>>>(nInt, b.cellId, pv.role, b.cellUx, b.cellUy,
                                                                  b.cosA, b.sinA, cfg, pv.vx, pv.vy,
                                                                  b.rotatedCounter, b.invalidCounter);
        MPCD_CUDA_CHECK(cudaGetLastError());
        MPCD_CUDA_CHECK(cudaMemset(b.cellKinetic, 0, cBytesD));
        kinetic_persistent_kernel<<<particleBlocks, threads>>>(nInt, b.cellId, pv.role, pv.mass, pv.vx, pv.vy,
                                                               b.cellUx, b.cellUy, cfg, b.cellKinetic);
        MPCD_CUDA_CHECK(cudaGetLastError());
        scale_persistent_kernel<<<cellBlocks, threads>>>(nc, b.count, b.cellKinetic, config.targetKBT,
                                                         std::max(1, config.thermostatMinParticles),
                                                         config.thermostatEpsilon, b.cellScale);
        MPCD_CUDA_CHECK(cudaGetLastError());
        apply_thermostat_persistent_kernel<<<particleBlocks, threads>>>(nInt, b.cellId, pv.role, b.cellUx,
                                                                       b.cellUy, b.cellScale, cfg, pv.vx, pv.vy);
        MPCD_CUDA_CHECK(cudaGetLastError());
    }
    MPCD_CUDA_CHECK(cudaDeviceSynchronize());
    diag.kernelSeconds = seconds_since(t0);

    t0 = Clock::now();
    gpuState.download_velocities(downloadTarget);
    cellIdOut.assign(n, -1);
    cellCountOut.assign(static_cast<std::size_t>(nc), 0u);
    cellMassOut.assign(static_cast<std::size_t>(nc), 0.0);
    cellUxOut.assign(static_cast<std::size_t>(nc), 0.0);
    cellUyOut.assign(static_cast<std::size_t>(nc), 0.0);
    MPCD_CUDA_CHECK(cudaMemcpy(cellIdOut.data(), b.cellId, nBytesI, cudaMemcpyDeviceToHost));
    MPCD_CUDA_CHECK(cudaMemcpy(cellCountOut.data(), b.count, cBytesU, cudaMemcpyDeviceToHost));
    MPCD_CUDA_CHECK(cudaMemcpy(cellMassOut.data(), b.cellMass, cBytesD, cudaMemcpyDeviceToHost));
    MPCD_CUDA_CHECK(cudaMemcpy(cellUxOut.data(), b.cellUx, cBytesD, cudaMemcpyDeviceToHost));
    MPCD_CUDA_CHECK(cudaMemcpy(cellUyOut.data(), b.cellUy, cBytesD, cudaMemcpyDeviceToHost));

    std::vector<double> kineticHost(static_cast<std::size_t>(nc), 0.0);
    std::vector<double> scaleHost(static_cast<std::size_t>(nc), 1.0);
    if (thermostatDiagOut != nullptr) {
        MPCD_CUDA_CHECK(cudaMemcpy(kineticHost.data(), b.cellKinetic, cBytesD, cudaMemcpyDeviceToHost));
        MPCD_CUDA_CHECK(cudaMemcpy(scaleHost.data(), b.cellScale, cBytesD, cudaMemcpyDeviceToHost));
    }
    unsigned long long fluid = 0ull, rotated = 0ull, invalid = 0ull;
    MPCD_CUDA_CHECK(cudaMemcpy(&fluid, b.fluidCounter, sizeof(unsigned long long), cudaMemcpyDeviceToHost));
    MPCD_CUDA_CHECK(cudaMemcpy(&rotated, b.rotatedCounter, sizeof(unsigned long long), cudaMemcpyDeviceToHost));
    MPCD_CUDA_CHECK(cudaMemcpy(&invalid, b.invalidCounter, sizeof(unsigned long long), cudaMemcpyDeviceToHost));
    MPCD_CUDA_CHECK(cudaDeviceSynchronize());
    diag.downloadSeconds = seconds_since(t0);

    diag.fluidParticles = static_cast<std::uint64_t>(fluid) / static_cast<std::uint64_t>(cycles);
    diag.particlesRotated = static_cast<std::uint64_t>(rotated);
    diag.invalidCellParticles = static_cast<std::uint64_t>(invalid);

    if (thermostatDiagOut != nullptr) {
        ThermostatDiagnostics td{};
        double totalKBefore = 0.0;
        double targetKTotal = 0.0;
        double scaleSum = 0.0;
        double scaleMin = 1.0e300;
        double scaleMax = 0.0;
        std::uint64_t dofTotal = 0u;
        for (int c = 0; c < nc; ++c) {
            const std::size_t kk = static_cast<std::size_t>(c);
            const std::uint32_t count = cellCountOut[kk];
            const double K = kineticHost[kk];
            if (count < static_cast<std::uint32_t>(std::max(1, config.thermostatMinParticles))) continue;
            if (!(K > config.thermostatEpsilon)) continue;
            const double dof = 2.0 * static_cast<double>(count - 1u);
            const double targetK = 0.5 * dof * config.targetKBT;
            const double scale = scaleHost[kk];
            totalKBefore += K;
            targetKTotal += targetK;
            dofTotal += static_cast<std::uint64_t>(2u * (count - 1u));
            td.cellsRescaled += 1u;
            td.particlesRescaled += static_cast<std::uint64_t>(count);
            scaleSum += scale;
            if (scale < scaleMin) scaleMin = scale;
            if (scale > scaleMax) scaleMax = scale;
        }
        td.applied = td.cellsRescaled > 0u;
        td.kBTBefore = dofTotal > 0u ? (2.0 * totalKBefore / static_cast<double>(dofTotal)) : 0.0;
        td.kBTAfter = dofTotal > 0u ? (2.0 * targetKTotal / static_cast<double>(dofTotal)) : 0.0;
        td.scaleMean = td.cellsRescaled > 0u ? scaleSum / static_cast<double>(td.cellsRescaled) : 1.0;
        td.scaleMin = td.cellsRescaled > 0u ? scaleMin : 1.0;
        td.scaleMax = td.cellsRescaled > 0u ? scaleMax : 1.0;
        *thermostatDiagOut = td;
        diag.thermostatCellsRescaled = td.cellsRescaled;
        diag.thermostatParticlesRescaled = td.particlesRescaled;
        diag.thermostatKBTBefore = td.kBTBefore;
        diag.thermostatKBTAfter = td.kBTAfter;
        diag.thermostatScaleMean = td.scaleMean;
        diag.thermostatScaleMin = td.scaleMin;
        diag.thermostatScaleMax = td.scaleMax;
    }

    diag.totalSeconds = seconds_since(tTotal0);
    return diag;
#endif
}



CudaPersistentMpcdStepDiagnostics cuda_apply_persistent_tg_deposit_src_collision_thermostat(
    CudaParticleState& gpuState,
    CudaCellWorkspace& cellWorkspace,
    ParticleState& downloadTarget,
    std::vector<int>& cellIdOut,
    std::vector<std::uint32_t>& cellCountOut,
    std::vector<double>& cellMassOut,
    std::vector<double>& cellUxOut,
    std::vector<double>& cellUyOut,
    const CudaPersistentMpcdStepConfig& config,
    ThermostatDiagnostics* thermostatDiagOut) {
#if !defined(MPCD_ENABLE_CUDA_PERSISTENT_STEP) || !defined(MPCD_ENABLE_CUDA_PARTICLE_STATE) || !defined(MPCD_ENABLE_CUDA_CELL_WORKSPACE)
    (void)gpuState; (void)cellWorkspace; (void)downloadTarget; (void)cellIdOut; (void)cellCountOut; (void)cellMassOut; (void)cellUxOut; (void)cellUyOut; (void)config; (void)thermostatDiagOut;
    throw std::runtime_error("cuda_apply_persistent_tg_deposit_src_collision_thermostat(CudaParticleState,CudaCellWorkspace) requires MPCD_ENABLE_CUDA_PERSISTENT_STEP, MPCD_ENABLE_CUDA_PARTICLE_STATE and MPCD_ENABLE_CUDA_CELL_WORKSPACE");
#else
    validate_particle_state(downloadTarget, "cuda_apply_persistent_tg_deposit_src_collision_thermostat(shared particle+cell downloadTarget)");
    if (config.Nx <= 0 || config.Ny <= 0) throw std::runtime_error("persistent CUDA shared particle+cell step: invalid grid");
    if (!(config.Lx > 0.0) || !(config.Ly > 0.0)) throw std::runtime_error("persistent CUDA shared particle+cell step: invalid domain");
    if (!(config.targetKBT > 0.0)) throw std::runtime_error("persistent CUDA shared particle+cell step: targetKBT must be positive");

    const CudaParticleDeviceView pv = gpuState.device_view();
    if (pv.n == 0u) throw std::runtime_error("persistent CUDA shared particle+cell step: empty CudaParticleState");
    if (downloadTarget.Np != pv.n) throw std::runtime_error("persistent CUDA shared particle+cell step: host particle count mismatch");
    if (pv.x == nullptr || pv.y == nullptr || pv.vx == nullptr || pv.vy == nullptr || pv.mass == nullptr || pv.role == nullptr) {
        throw std::runtime_error("persistent CUDA shared particle+cell step: incomplete CudaParticleState device view");
    }

    const std::size_t n = static_cast<std::size_t>(pv.n);
    const int nInt = static_cast<int>(n);
    if (static_cast<std::size_t>(nInt) != n) throw std::runtime_error("persistent CUDA shared particle+cell step: too many particles for prototype int kernels");
    const int nc = config.Nx * config.Ny;
    const int cycles = std::max(1, config.cycles);
    const int threads = std::max(32, config.threadsPerBlock);
    const int particleBlocks = std::max(1, (nInt + threads - 1) / threads);
    const int cellBlocks = std::max(1, (nc + threads - 1) / threads);
    const int resetBlocks = std::max(particleBlocks, cellBlocks);

    cellWorkspace.ensure_capacity(pv.n, nc, nullptr);
    const CudaCellWorkspaceDeviceView cv = cellWorkspace.device_view();
    if (cv.cellId == nullptr || cv.count == nullptr || cv.cellMass == nullptr || cv.cellPx == nullptr ||
        cv.cellPy == nullptr || cv.cellUx == nullptr || cv.cellUy == nullptr || cv.cosA == nullptr ||
        cv.sinA == nullptr || cv.cellKinetic == nullptr || cv.cellScale == nullptr ||
        cv.fluidCounter == nullptr || cv.rotatedCounter == nullptr || cv.invalidCounter == nullptr) {
        throw std::runtime_error("persistent CUDA shared particle+cell step: incomplete CudaCellWorkspace device view");
    }
    if (cv.particleCapacity < pv.n || cv.numCells < nc) {
        throw std::runtime_error("persistent CUDA shared particle+cell step: CudaCellWorkspace capacity mismatch");
    }

    std::vector<double> cosHost(static_cast<std::size_t>(nc), std::cos(config.rotationAngle));
    std::vector<double> sinHost(static_cast<std::size_t>(nc), std::sin(config.rotationAngle));
    if (config.randomRotationSign) {
        for (int c = 0; c < nc; ++c) {
            const std::uint64_t h = splitmix64_host(config.rngSeed ^
                                                    (config.step * 0x9e3779b97f4a7c15ULL) ^
                                                    static_cast<std::uint64_t>(c));
            if ((h & 1ULL) == 0ULL) sinHost[static_cast<std::size_t>(c)] = -sinHost[static_cast<std::size_t>(c)];
        }
    }

    CudaPersistentMpcdStepDiagnostics diag{};
    diag.particlesVisited = pv.n;
    diag.numCells = nc;
    diag.cycles = cycles;

    const std::size_t nBytesI = n * sizeof(int);
    const std::size_t cBytesD = static_cast<std::size_t>(nc) * sizeof(double);
    const std::size_t cBytesU = static_cast<std::size_t>(nc) * sizeof(unsigned int);

    const auto tTotal0 = Clock::now();
    auto t0 = Clock::now();
    MPCD_CUDA_CHECK(cudaMemcpy(cv.cosA, cosHost.data(), cBytesD, cudaMemcpyHostToDevice));
    MPCD_CUDA_CHECK(cudaMemcpy(cv.sinA, sinHost.data(), cBytesD, cudaMemcpyHostToDevice));
    MPCD_CUDA_CHECK(cudaMemset(cv.fluidCounter, 0, sizeof(unsigned long long)));
    MPCD_CUDA_CHECK(cudaMemset(cv.rotatedCounter, 0, sizeof(unsigned long long)));
    MPCD_CUDA_CHECK(cudaMemset(cv.invalidCounter, 0, sizeof(unsigned long long)));
    MPCD_CUDA_CHECK(cudaDeviceSynchronize());
    diag.uploadSeconds = seconds_since(t0);

    DeviceConfig cfg{};
    cfg.Nx = config.Nx;
    cfg.Ny = config.Ny;
    cfg.numCells = nc;
    cfg.Lx = config.Lx;
    cfg.Ly = config.Ly;
    cfg.dx = config.Lx / static_cast<double>(config.Nx);
    cfg.dy = config.Ly / static_cast<double>(config.Ny);
    cfg.shiftX = config.shiftX;
    cfg.shiftY = config.shiftY;
    cfg.periodicX = config.periodicX ? 1 : 0;
    cfg.periodicY = config.periodicY ? 1 : 0;
    cfg.domainXMin = config.domainXMin;
    cfg.domainXMax = config.domainXMax;
    cfg.domainYMin = config.domainYMin;
    cfg.domainYMax = config.domainYMax;
    cfg.wallLeftEnabled = config.wallLeftEnabled;
    cfg.wallRightEnabled = config.wallRightEnabled;
    cfg.wallBottomEnabled = config.wallBottomEnabled;
    cfg.wallTopEnabled = config.wallTopEnabled;
    cfg.wallAccommodation = config.wallAccommodation;
    cfg.wallGamma = config.wallGamma;
    cfg.wallVpMass = config.wallVpMass;
    cfg.wallUxLeft = config.wallUxLeft;
    cfg.wallUyLeft = config.wallUyLeft;
    cfg.wallUxRight = config.wallUxRight;
    cfg.wallUyRight = config.wallUyRight;
    cfg.wallUxBottom = config.wallUxBottom;
    cfg.wallUyBottom = config.wallUyBottom;
    cfg.wallUxTop = config.wallUxTop;
    cfg.wallUyTop = config.wallUyTop;
    cfg.immersedRectangleEnabled = config.immersedRectangleEnabled;
    cfg.immersedFractionSamples = config.immersedFractionSamples;
    cfg.immersedXMin = config.immersedXMin;
    cfg.immersedXMax = config.immersedXMax;
    cfg.immersedYMin = config.immersedYMin;
    cfg.immersedYMax = config.immersedYMax;
    cfg.immersedWallUx = config.immersedWallUx;
    cfg.immersedWallUy = config.immersedWallUy;
    cfg.fluidRole = static_cast<unsigned char>(kParticleRoleFluid);

    t0 = Clock::now();
    for (int cycle = 0; cycle < cycles; ++cycle) {
        reset_persistent_cells_kernel<<<resetBlocks, threads>>>(nInt, nc, cv.cellId, cv.count, cv.cellMass,
                                                                cv.cellPx, cv.cellPy, cv.cellUx, cv.cellUy,
                                                                cv.cellKinetic, cv.cellScale);
        MPCD_CUDA_CHECK(cudaGetLastError());
        deposit_persistent_kernel<<<particleBlocks, threads>>>(nInt, pv.x, pv.y, pv.vx, pv.vy, pv.mass, pv.role,
                                                               cfg, cv.cellId, cv.count, cv.cellMass, cv.cellPx,
                                                               cv.cellPy, cv.fluidCounter);
        MPCD_CUDA_CHECK(cudaGetLastError());
        if (cfg.wallLeftEnabled || cfg.wallRightEnabled || cfg.wallBottomEnabled || cfg.wallTopEnabled || cfg.immersedRectangleEnabled) {
            add_wall_virtual_faces_persistent_kernel<<<cellBlocks, threads>>>(nc, cfg, cv.cellMass, cv.cellPx, cv.cellPy);
            MPCD_CUDA_CHECK(cudaGetLastError());
        }
        finalize_velocity_persistent_kernel<<<cellBlocks, threads>>>(nc, cv.cellMass, cv.cellPx, cv.cellPy,
                                                                     cv.cellUx, cv.cellUy);
        MPCD_CUDA_CHECK(cudaGetLastError());
        src_rotate_persistent_kernel<<<particleBlocks, threads>>>(nInt, cv.cellId, pv.role, cv.cellUx, cv.cellUy,
                                                                  cv.cosA, cv.sinA, cfg, pv.vx, pv.vy,
                                                                  cv.rotatedCounter, cv.invalidCounter);
        MPCD_CUDA_CHECK(cudaGetLastError());
        MPCD_CUDA_CHECK(cudaMemset(cv.cellKinetic, 0, cBytesD));
        kinetic_persistent_kernel<<<particleBlocks, threads>>>(nInt, cv.cellId, pv.role, pv.mass, pv.vx, pv.vy,
                                                               cv.cellUx, cv.cellUy, cfg, cv.cellKinetic);
        MPCD_CUDA_CHECK(cudaGetLastError());
        scale_persistent_kernel<<<cellBlocks, threads>>>(nc, cv.count, cv.cellKinetic, config.targetKBT,
                                                         std::max(1, config.thermostatMinParticles),
                                                         config.thermostatEpsilon, cv.cellScale);
        MPCD_CUDA_CHECK(cudaGetLastError());
        apply_thermostat_persistent_kernel<<<particleBlocks, threads>>>(nInt, cv.cellId, pv.role, cv.cellUx,
                                                                       cv.cellUy, cv.cellScale, cfg, pv.vx, pv.vy);
        MPCD_CUDA_CHECK(cudaGetLastError());
    }
    MPCD_CUDA_CHECK(cudaDeviceSynchronize());
    diag.kernelSeconds = seconds_since(t0);

    t0 = Clock::now();
    const bool residentPeriodic0260 = env_flag_enabled_0257("MPCD_CUDA_CLASSIC_SRC_PERIODIC_RESIDENT_0260", false);
    if (!residentPeriodic0260) {
        gpuState.download_velocities(downloadTarget);
    }
    // The later thermostat phase checks that cellId has the particle count even
    // when it only consumes diagnostics recorded here. In resident 0260 mode the
    // values themselves are not needed on the host, so only size the vector.
    cellIdOut.assign(n, -1);
    cellCountOut.assign(static_cast<std::size_t>(nc), 0u);
    if (!residentPeriodic0260) {
        cellMassOut.assign(static_cast<std::size_t>(nc), 0.0);
        cellUxOut.assign(static_cast<std::size_t>(nc), 0.0);
        cellUyOut.assign(static_cast<std::size_t>(nc), 0.0);
        MPCD_CUDA_CHECK(cudaMemcpy(cellIdOut.data(), cv.cellId, nBytesI, cudaMemcpyDeviceToHost));
    } else {
        cellMassOut.clear();
        cellUxOut.clear();
        cellUyOut.clear();
    }
    // Keep population diagnostics available for runtime summaries; this is much
    // cheaper than downloading full velocities and cell moments every step.
    MPCD_CUDA_CHECK(cudaMemcpy(cellCountOut.data(), cv.count, cBytesU, cudaMemcpyDeviceToHost));
    if (!residentPeriodic0260) {
        MPCD_CUDA_CHECK(cudaMemcpy(cellMassOut.data(), cv.cellMass, cBytesD, cudaMemcpyDeviceToHost));
        MPCD_CUDA_CHECK(cudaMemcpy(cellUxOut.data(), cv.cellUx, cBytesD, cudaMemcpyDeviceToHost));
        MPCD_CUDA_CHECK(cudaMemcpy(cellUyOut.data(), cv.cellUy, cBytesD, cudaMemcpyDeviceToHost));
    }

    std::vector<double> kineticHost(static_cast<std::size_t>(nc), 0.0);
    std::vector<double> scaleHost(static_cast<std::size_t>(nc), 1.0);
    if (thermostatDiagOut != nullptr) {
        // Keep deterministic thermostat diagnostics bit-compatible with the CPU
        // validation path. This is still much cheaper than downloading full
        // particle velocities and all cell moments every step.
        MPCD_CUDA_CHECK(cudaMemcpy(kineticHost.data(), cv.cellKinetic, cBytesD, cudaMemcpyDeviceToHost));
        MPCD_CUDA_CHECK(cudaMemcpy(scaleHost.data(), cv.cellScale, cBytesD, cudaMemcpyDeviceToHost));
    }
    unsigned long long fluid = 0ull, rotated = 0ull, invalid = 0ull;
    MPCD_CUDA_CHECK(cudaMemcpy(&fluid, cv.fluidCounter, sizeof(unsigned long long), cudaMemcpyDeviceToHost));
    MPCD_CUDA_CHECK(cudaMemcpy(&rotated, cv.rotatedCounter, sizeof(unsigned long long), cudaMemcpyDeviceToHost));
    MPCD_CUDA_CHECK(cudaMemcpy(&invalid, cv.invalidCounter, sizeof(unsigned long long), cudaMemcpyDeviceToHost));
    MPCD_CUDA_CHECK(cudaDeviceSynchronize());
    diag.downloadSeconds = seconds_since(t0);

    diag.fluidParticles = static_cast<std::uint64_t>(fluid) / static_cast<std::uint64_t>(cycles);
    diag.particlesRotated = static_cast<std::uint64_t>(rotated);
    diag.invalidCellParticles = static_cast<std::uint64_t>(invalid);

    if (thermostatDiagOut != nullptr) {
        ThermostatDiagnostics td{};
        double totalKBefore = 0.0;
        double targetKTotal = 0.0;
        double scaleSum = 0.0;
        double scaleMin = 1.0e300;
        double scaleMax = 0.0;
        std::uint64_t dofTotal = 0u;
        for (int c = 0; c < nc; ++c) {
            const std::size_t kk = static_cast<std::size_t>(c);
            const std::uint32_t count = cellCountOut[kk];
            const double K = kineticHost[kk];
            if (count < static_cast<std::uint32_t>(std::max(1, config.thermostatMinParticles))) continue;
            if (!(K > config.thermostatEpsilon)) continue;
            const double dof = 2.0 * static_cast<double>(count - 1u);
            const double targetK = 0.5 * dof * config.targetKBT;
            const double scale = scaleHost[kk];
            totalKBefore += K;
            targetKTotal += targetK;
            dofTotal += static_cast<std::uint64_t>(2u * (count - 1u));
            td.cellsRescaled += 1u;
            td.particlesRescaled += static_cast<std::uint64_t>(count);
            scaleSum += scale;
            if (scale < scaleMin) scaleMin = scale;
            if (scale > scaleMax) scaleMax = scale;
        }
        td.applied = td.cellsRescaled > 0u;
        td.kBTBefore = dofTotal > 0u ? (2.0 * totalKBefore / static_cast<double>(dofTotal)) : 0.0;
        td.kBTAfter = dofTotal > 0u ? (2.0 * targetKTotal / static_cast<double>(dofTotal)) : 0.0;
        td.scaleMean = td.cellsRescaled > 0u ? scaleSum / static_cast<double>(td.cellsRescaled) : 1.0;
        td.scaleMin = td.cellsRescaled > 0u ? scaleMin : 1.0;
        td.scaleMax = td.cellsRescaled > 0u ? scaleMax : 1.0;
        *thermostatDiagOut = td;
        diag.thermostatCellsRescaled = td.cellsRescaled;
        diag.thermostatParticlesRescaled = td.particlesRescaled;
        diag.thermostatKBTBefore = td.kBTBefore;
        diag.thermostatKBTAfter = td.kBTAfter;
        diag.thermostatScaleMean = td.scaleMean;
        diag.thermostatScaleMin = td.scaleMin;
        diag.thermostatScaleMax = td.scaleMax;
    }

    diag.totalSeconds = seconds_since(tTotal0);
    return diag;
#endif
}


CudaPersistentMpcdStepDiagnostics cuda_apply_persistent_tg_deposit_src_collision(
    CudaParticleState& gpuState,
    CudaCellWorkspace& cellWorkspace,
    ParticleState& downloadTarget,
    std::vector<int>& cellIdOut,
    std::vector<std::uint32_t>& cellCountOut,
    std::vector<double>& cellMassOut,
    std::vector<double>& cellUxOut,
    std::vector<double>& cellUyOut,
    const CudaPersistentMpcdStepConfig& config) {
#if !defined(MPCD_ENABLE_CUDA_PERSISTENT_STEP) || !defined(MPCD_ENABLE_CUDA_PARTICLE_STATE) || !defined(MPCD_ENABLE_CUDA_CELL_WORKSPACE)
    (void)gpuState; (void)cellWorkspace; (void)downloadTarget; (void)cellIdOut; (void)cellCountOut; (void)cellMassOut; (void)cellUxOut; (void)cellUyOut; (void)config;
    throw std::runtime_error("cuda_apply_persistent_tg_deposit_src_collision(CudaParticleState,CudaCellWorkspace) requires MPCD_ENABLE_CUDA_PERSISTENT_STEP, MPCD_ENABLE_CUDA_PARTICLE_STATE and MPCD_ENABLE_CUDA_CELL_WORKSPACE");
#else
    validate_particle_state(downloadTarget, "cuda_apply_persistent_tg_deposit_src_collision(shared particle+cell downloadTarget)");
    if (config.Nx <= 0 || config.Ny <= 0) throw std::runtime_error("persistent CUDA shared collision step: invalid grid");
    if (!(config.Lx > 0.0) || !(config.Ly > 0.0)) throw std::runtime_error("persistent CUDA shared collision step: invalid domain");

    const CudaParticleDeviceView pv = gpuState.device_view();
    if (pv.n == 0u) throw std::runtime_error("persistent CUDA shared collision step: empty CudaParticleState");
    if (downloadTarget.Np != pv.n) throw std::runtime_error("persistent CUDA shared collision step: host particle count mismatch");
    if (pv.x == nullptr || pv.y == nullptr || pv.vx == nullptr || pv.vy == nullptr || pv.mass == nullptr || pv.role == nullptr) {
        throw std::runtime_error("persistent CUDA shared collision step: incomplete CudaParticleState device view");
    }

    const std::size_t n = static_cast<std::size_t>(pv.n);
    const int nInt = static_cast<int>(n);
    if (static_cast<std::size_t>(nInt) != n) throw std::runtime_error("persistent CUDA shared collision step: too many particles for prototype int kernels");
    const int nc = config.Nx * config.Ny;
    const int cycles = std::max(1, config.cycles);
    const int threads = std::max(32, config.threadsPerBlock);
    const int particleBlocks = std::max(1, (nInt + threads - 1) / threads);
    const int cellBlocks = std::max(1, (nc + threads - 1) / threads);
    const int resetBlocks = std::max(particleBlocks, cellBlocks);

    cellWorkspace.ensure_capacity(pv.n, nc, nullptr);
    const CudaCellWorkspaceDeviceView cv = cellWorkspace.device_view();
    if (cv.cellId == nullptr || cv.count == nullptr || cv.cellMass == nullptr || cv.cellPx == nullptr ||
        cv.cellPy == nullptr || cv.cellUx == nullptr || cv.cellUy == nullptr || cv.cosA == nullptr ||
        cv.sinA == nullptr || cv.fluidCounter == nullptr || cv.rotatedCounter == nullptr || cv.invalidCounter == nullptr) {
        throw std::runtime_error("persistent CUDA shared collision step: incomplete CudaCellWorkspace device view");
    }
    if (cv.particleCapacity < pv.n || cv.numCells < nc) {
        throw std::runtime_error("persistent CUDA shared collision step: CudaCellWorkspace capacity mismatch");
    }

    std::vector<double> cosHost(static_cast<std::size_t>(nc), std::cos(config.rotationAngle));
    std::vector<double> sinHost(static_cast<std::size_t>(nc), std::sin(config.rotationAngle));
    if (config.randomRotationSign) {
        for (int c = 0; c < nc; ++c) {
            const std::uint64_t h = splitmix64_host(config.rngSeed ^
                                                    (config.step * 0x9e3779b97f4a7c15ULL) ^
                                                    static_cast<std::uint64_t>(c));
            if ((h & 1ULL) == 0ULL) sinHost[static_cast<std::size_t>(c)] = -sinHost[static_cast<std::size_t>(c)];
        }
    }

    CudaPersistentMpcdStepDiagnostics diag{};
    diag.particlesVisited = pv.n;
    diag.numCells = nc;
    diag.cycles = cycles;

    const std::size_t nBytesI = n * sizeof(int);
    const std::size_t cBytesD = static_cast<std::size_t>(nc) * sizeof(double);
    const std::size_t cBytesU = static_cast<std::size_t>(nc) * sizeof(unsigned int);

    const auto tTotal0 = Clock::now();
    auto t0 = Clock::now();
    MPCD_CUDA_CHECK(cudaMemcpy(cv.cosA, cosHost.data(), cBytesD, cudaMemcpyHostToDevice));
    MPCD_CUDA_CHECK(cudaMemcpy(cv.sinA, sinHost.data(), cBytesD, cudaMemcpyHostToDevice));
    MPCD_CUDA_CHECK(cudaMemset(cv.fluidCounter, 0, sizeof(unsigned long long)));
    MPCD_CUDA_CHECK(cudaMemset(cv.rotatedCounter, 0, sizeof(unsigned long long)));
    MPCD_CUDA_CHECK(cudaMemset(cv.invalidCounter, 0, sizeof(unsigned long long)));
    MPCD_CUDA_CHECK(cudaDeviceSynchronize());
    diag.uploadSeconds = seconds_since(t0);

    DeviceConfig cfg{};
    cfg.Nx = config.Nx;
    cfg.Ny = config.Ny;
    cfg.numCells = nc;
    cfg.Lx = config.Lx;
    cfg.Ly = config.Ly;
    cfg.dx = config.Lx / static_cast<double>(config.Nx);
    cfg.dy = config.Ly / static_cast<double>(config.Ny);
    cfg.shiftX = config.shiftX;
    cfg.shiftY = config.shiftY;
    cfg.periodicX = config.periodicX ? 1 : 0;
    cfg.periodicY = config.periodicY ? 1 : 0;
    cfg.domainXMin = config.domainXMin;
    cfg.domainXMax = config.domainXMax;
    cfg.domainYMin = config.domainYMin;
    cfg.domainYMax = config.domainYMax;
    cfg.wallLeftEnabled = config.wallLeftEnabled;
    cfg.wallRightEnabled = config.wallRightEnabled;
    cfg.wallBottomEnabled = config.wallBottomEnabled;
    cfg.wallTopEnabled = config.wallTopEnabled;
    cfg.wallAccommodation = config.wallAccommodation;
    cfg.wallGamma = config.wallGamma;
    cfg.wallVpMass = config.wallVpMass;
    cfg.wallUxLeft = config.wallUxLeft;
    cfg.wallUyLeft = config.wallUyLeft;
    cfg.wallUxRight = config.wallUxRight;
    cfg.wallUyRight = config.wallUyRight;
    cfg.wallUxBottom = config.wallUxBottom;
    cfg.wallUyBottom = config.wallUyBottom;
    cfg.wallUxTop = config.wallUxTop;
    cfg.wallUyTop = config.wallUyTop;
    cfg.immersedRectangleEnabled = config.immersedRectangleEnabled;
    cfg.immersedFractionSamples = config.immersedFractionSamples;
    cfg.immersedXMin = config.immersedXMin;
    cfg.immersedXMax = config.immersedXMax;
    cfg.immersedYMin = config.immersedYMin;
    cfg.immersedYMax = config.immersedYMax;
    cfg.immersedWallUx = config.immersedWallUx;
    cfg.immersedWallUy = config.immersedWallUy;
    cfg.fluidRole = static_cast<unsigned char>(kParticleRoleFluid);

    t0 = Clock::now();
    for (int cycle = 0; cycle < cycles; ++cycle) {
        reset_persistent_cells_kernel<<<resetBlocks, threads>>>(nInt, nc, cv.cellId, cv.count, cv.cellMass,
                                                                cv.cellPx, cv.cellPy, cv.cellUx, cv.cellUy,
                                                                cv.cellKinetic, cv.cellScale);
        MPCD_CUDA_CHECK(cudaGetLastError());
        deposit_persistent_kernel<<<particleBlocks, threads>>>(nInt, pv.x, pv.y, pv.vx, pv.vy, pv.mass, pv.role,
                                                               cfg, cv.cellId, cv.count, cv.cellMass, cv.cellPx,
                                                               cv.cellPy, cv.fluidCounter);
        MPCD_CUDA_CHECK(cudaGetLastError());
        if (cfg.wallLeftEnabled || cfg.wallRightEnabled || cfg.wallBottomEnabled || cfg.wallTopEnabled || cfg.immersedRectangleEnabled) {
            add_wall_virtual_faces_persistent_kernel<<<cellBlocks, threads>>>(nc, cfg, cv.cellMass, cv.cellPx, cv.cellPy);
            MPCD_CUDA_CHECK(cudaGetLastError());
        }
        finalize_velocity_persistent_kernel<<<cellBlocks, threads>>>(nc, cv.cellMass, cv.cellPx, cv.cellPy,
                                                                     cv.cellUx, cv.cellUy);
        MPCD_CUDA_CHECK(cudaGetLastError());
        src_rotate_persistent_kernel<<<particleBlocks, threads>>>(nInt, cv.cellId, pv.role, cv.cellUx, cv.cellUy,
                                                                  cv.cosA, cv.sinA, cfg, pv.vx, pv.vy,
                                                                  cv.rotatedCounter, cv.invalidCounter);
        MPCD_CUDA_CHECK(cudaGetLastError());
    }
    MPCD_CUDA_CHECK(cudaDeviceSynchronize());
    diag.kernelSeconds = seconds_since(t0);

    t0 = Clock::now();
    const bool residentClassic0260or0261 =
        env_flag_enabled_0257("MPCD_CUDA_CLASSIC_SRC_PERIODIC_RESIDENT_0260", false) ||
        env_flag_enabled_0257("MPCD_CUDA_CLASSIC_SRC_WALL_RESIDENT_0261", false);
    if (!residentClassic0260or0261) {
        gpuState.download_velocities(downloadTarget);
    }
    cellIdOut.assign(n, -1);
    const bool minimalDownload0257 = env_flag_enabled_0257("MPCD_CUDA_PERSISTENT_SRC_COLLISION_MINIMAL_DOWNLOAD_0257", false);
    if (minimalDownload0257) {
        // 0257 conservative minimal-download mode: keep cellCount on the host
        // because runtime summaries/validation still consume population
        // diagnostics, but skip the heavier post-collision cellMass/cellUx/cellUy
        // arrays which are not needed by the current CPU continuation.
        cellCountOut.assign(static_cast<std::size_t>(nc), 0u);
        cellMassOut.clear();
        cellUxOut.clear();
        cellUyOut.clear();
    } else {
        cellCountOut.assign(static_cast<std::size_t>(nc), 0u);
        cellMassOut.assign(static_cast<std::size_t>(nc), 0.0);
        cellUxOut.assign(static_cast<std::size_t>(nc), 0.0);
        cellUyOut.assign(static_cast<std::size_t>(nc), 0.0);
    }
    MPCD_CUDA_CHECK(cudaMemcpy(cellIdOut.data(), cv.cellId, nBytesI, cudaMemcpyDeviceToHost));
    MPCD_CUDA_CHECK(cudaMemcpy(cellCountOut.data(), cv.count, cBytesU, cudaMemcpyDeviceToHost));
    if (!minimalDownload0257) {
        MPCD_CUDA_CHECK(cudaMemcpy(cellMassOut.data(), cv.cellMass, cBytesD, cudaMemcpyDeviceToHost));
        MPCD_CUDA_CHECK(cudaMemcpy(cellUxOut.data(), cv.cellUx, cBytesD, cudaMemcpyDeviceToHost));
        MPCD_CUDA_CHECK(cudaMemcpy(cellUyOut.data(), cv.cellUy, cBytesD, cudaMemcpyDeviceToHost));
    }
    unsigned long long fluid = 0ull, rotated = 0ull, invalid = 0ull;
    MPCD_CUDA_CHECK(cudaMemcpy(&fluid, cv.fluidCounter, sizeof(unsigned long long), cudaMemcpyDeviceToHost));
    MPCD_CUDA_CHECK(cudaMemcpy(&rotated, cv.rotatedCounter, sizeof(unsigned long long), cudaMemcpyDeviceToHost));
    MPCD_CUDA_CHECK(cudaMemcpy(&invalid, cv.invalidCounter, sizeof(unsigned long long), cudaMemcpyDeviceToHost));
    MPCD_CUDA_CHECK(cudaDeviceSynchronize());
    diag.downloadSeconds = seconds_since(t0);

    diag.fluidParticles = static_cast<std::uint64_t>(fluid) / static_cast<std::uint64_t>(cycles);
    diag.particlesRotated = static_cast<std::uint64_t>(rotated);
    diag.invalidCellParticles = static_cast<std::uint64_t>(invalid);
    diag.totalSeconds = seconds_since(tTotal0);
    return diag;
#endif
}

CudaPersistentMpcdStepDiagnostics cuda_apply_persistent_tg_deposit_src_collision(
    CudaParticleState& gpuState,
    ParticleState& downloadTarget,
    std::vector<int>& cellIdOut,
    std::vector<std::uint32_t>& cellCountOut,
    std::vector<double>& cellMassOut,
    std::vector<double>& cellUxOut,
    std::vector<double>& cellUyOut,
    const CudaPersistentMpcdStepConfig& config) {
#if !defined(MPCD_ENABLE_CUDA_PERSISTENT_STEP) || !defined(MPCD_ENABLE_CUDA_PARTICLE_STATE) || !defined(MPCD_ENABLE_CUDA_CELL_WORKSPACE)
    (void)gpuState; (void)downloadTarget; (void)cellIdOut; (void)cellCountOut; (void)cellMassOut; (void)cellUxOut; (void)cellUyOut; (void)config;
    throw std::runtime_error("cuda_apply_persistent_tg_deposit_src_collision(CudaParticleState) requires MPCD_ENABLE_CUDA_PERSISTENT_STEP, MPCD_ENABLE_CUDA_PARTICLE_STATE and MPCD_ENABLE_CUDA_CELL_WORKSPACE");
#else
    CudaCellWorkspace transientWorkspace;
    return cuda_apply_persistent_tg_deposit_src_collision(gpuState, transientWorkspace, downloadTarget,
                                                          cellIdOut, cellCountOut, cellMassOut, cellUxOut, cellUyOut,
                                                          config);
#endif
}

} // namespace mpcd
