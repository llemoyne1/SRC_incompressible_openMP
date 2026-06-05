#include "cuda_persistent_mpcd_step.h"

#include <cuda_runtime.h>

#include <algorithm>
#include <chrono>
#include <cmath>
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
    unsigned char fluidRole;
};

__device__ double wrap_periodic(double x, double L) {
    x = fmod(x, L);
    if (x < 0.0) x += L;
    if (x >= L) x -= L;
    return x;
}

__device__ int cell_index_device(double x, double y, DeviceConfig cfg) {
    const double xs = wrap_periodic(x + cfg.shiftX, cfg.Lx);
    const double ys = wrap_periodic(y + cfg.shiftY, cfg.Ly);
    int ix = static_cast<int>(floor(xs / cfg.dx));
    int iy = static_cast<int>(floor(ys / cfg.dy));
    if (ix < 0) ix = 0; if (ix >= cfg.Nx) ix = cfg.Nx - 1;
    if (iy < 0) iy = 0; if (iy >= cfg.Ny) iy = cfg.Ny - 1;
    return ix + cfg.Nx * iy;
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

CudaPersistentMpcdStepDiagnostics cuda_apply_persistent_tg_impl(
    ParticleState& state,
    std::vector<int>* cellIdOut,
    std::vector<std::uint32_t>* cellCountOut,
    std::vector<double>* cellMassOut,
    std::vector<double>* cellUxOut,
    std::vector<double>* cellUyOut,
    const CudaPersistentMpcdStepConfig& config,
    const bool applyThermostat) {
#ifndef MPCD_ENABLE_CUDA_PERSISTENT_STEP
    (void)state; (void)cellIdOut; (void)cellCountOut; (void)cellMassOut; (void)cellUxOut; (void)cellUyOut; (void)config; (void)applyThermostat;
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
    unsigned long long fluid = 0ull, rotated = 0ull, invalid = 0ull;
    MPCD_CUDA_CHECK(cudaMemcpy(&fluid, b.fluidCounter, sizeof(unsigned long long), cudaMemcpyDeviceToHost));
    MPCD_CUDA_CHECK(cudaMemcpy(&rotated, b.rotatedCounter, sizeof(unsigned long long), cudaMemcpyDeviceToHost));
    MPCD_CUDA_CHECK(cudaMemcpy(&invalid, b.invalidCounter, sizeof(unsigned long long), cudaMemcpyDeviceToHost));
    MPCD_CUDA_CHECK(cudaDeviceSynchronize());
    diag.downloadSeconds = seconds_since(t0);

    diag.fluidParticles = static_cast<std::uint64_t>(fluid) / static_cast<std::uint64_t>(cycles);
    diag.particlesRotated = static_cast<std::uint64_t>(rotated);
    diag.invalidCellParticles = static_cast<std::uint64_t>(invalid);
    diag.totalSeconds = seconds_since(tTotal0);
    return diag;
#endif
}


CudaPersistentMpcdStepDiagnostics cuda_apply_persistent_tg_deposit_src_thermostat(
    ParticleState& state,
    const CudaPersistentMpcdStepConfig& config) {
    return cuda_apply_persistent_tg_impl(state, nullptr, nullptr, nullptr, nullptr, nullptr, config, true);
}

CudaPersistentMpcdStepDiagnostics cuda_apply_persistent_tg_deposit_src_collision(
    ParticleState& state,
    std::vector<int>& cellIdOut,
    std::vector<std::uint32_t>& cellCountOut,
    std::vector<double>& cellMassOut,
    std::vector<double>& cellUxOut,
    std::vector<double>& cellUyOut,
    const CudaPersistentMpcdStepConfig& config) {
    return cuda_apply_persistent_tg_impl(state, &cellIdOut, &cellCountOut, &cellMassOut, &cellUxOut, &cellUyOut, config, false);
}

} // namespace mpcd
