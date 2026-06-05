#include "cuda_cell_moments.h"

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

using Clock = std::chrono::steady_clock;

double seconds_between(const Clock::time_point a, const Clock::time_point b) {
    return std::chrono::duration<double>(b - a).count();
}

void cuda_check(cudaError_t err, const char* context) {
    if (err != cudaSuccess) {
        throw std::runtime_error(std::string(context) + ": " + cudaGetErrorString(err));
    }
}

template <typename T>
void cuda_alloc(T** ptr, std::size_t count, const char* context) {
    cuda_check(cudaMalloc(reinterpret_cast<void**>(ptr), count * sizeof(T)), context);
}

template <typename T>
void cuda_free(T*& ptr) {
    if (ptr != nullptr) {
        cudaFree(ptr);
        ptr = nullptr;
    }
}

struct DeviceDepositConfig {
    int nx;
    int ny;
    int numCells;
    double lx;
    double ly;
    double dx;
    double dy;
    double shiftX;
    double shiftY;
    int periodicX;
    int periodicY;
};

__device__ double wrap_periodic_device(double x, const double L) {
    x = fmod(x, L);
    if (x < 0.0) x += L;
    if (x >= L) x -= L;
    return x;
}

__device__ int bounded_cell_index_device(double xs, const double L, const double dx, const int N) {
    if (xs < 0.0) xs = 0.0;
    if (xs > L) xs = L;
    int i = static_cast<int>(floor(xs / dx));
    if (i < 0) i = 0;
    if (i >= N) i = N - 1;
    return i;
}

__device__ int periodic_cell_index_device(double xs, const double L, const double dx, const int N) {
    xs = wrap_periodic_device(xs, L);
    int i = static_cast<int>(floor(xs / dx));
    if (i < 0) i = 0;
    if (i >= N) i = N - 1;
    return i;
}

__device__ int cell_index_from_position_device(const double x, const double y,
                                               const DeviceDepositConfig cfg) {
    const double xs = x + cfg.shiftX;
    const double ys = y + cfg.shiftY;
    const int ix = cfg.periodicX
        ? periodic_cell_index_device(xs, cfg.lx, cfg.dx, cfg.nx)
        : bounded_cell_index_device(xs, cfg.lx, cfg.dx, cfg.nx);
    const int iy = cfg.periodicY
        ? periodic_cell_index_device(ys, cfg.ly, cfg.dy, cfg.ny)
        : bounded_cell_index_device(ys, cfg.ly, cfg.dy, cfg.ny);
    return ix + cfg.nx * iy;
}

__global__ void reset_cell_moments_kernel(const int nParticles,
                                          const int numCells,
                                          int* cellId,
                                          unsigned int* cellCount,
                                          double* cellMass,
                                          double* cellPx,
                                          double* cellPy,
                                          double* cellUx,
                                          double* cellUy) {
    const int tid = blockIdx.x * blockDim.x + threadIdx.x;
    const int stride = blockDim.x * gridDim.x;
    for (int i = tid; i < nParticles; i += stride) {
        cellId[i] = -1;
    }
    for (int c = tid; c < numCells; c += stride) {
        cellCount[c] = 0u;
        cellMass[c] = 0.0;
        cellPx[c] = 0.0;
        cellPy[c] = 0.0;
        cellUx[c] = 0.0;
        cellUy[c] = 0.0;
    }
}

__global__ void deposit_cell_moments_atomic_kernel(const int nParticles,
                                                   const double* x,
                                                   const double* y,
                                                   const double* vx,
                                                   const double* vy,
                                                   const double* mass,
                                                   const unsigned char* role,
                                                   const DeviceDepositConfig cfg,
                                                   int* cellId,
                                                   unsigned int* cellCount,
                                                   double* cellMass,
                                                   double* cellPx,
                                                   double* cellPy) {
    const int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= nParticles) return;
    if (role[i] != static_cast<unsigned char>(kParticleRoleFluid)) {
        cellId[i] = -1;
        return;
    }
    const int c = cell_index_from_position_device(x[i], y[i], cfg);
    cellId[i] = c;
    const double m = mass[i];
    atomicAdd(&cellCount[c], 1u);
    atomicAdd(&cellMass[c], m);
    atomicAdd(&cellPx[c], m * vx[i]);
    atomicAdd(&cellPy[c], m * vy[i]);
}

__global__ void finalize_cell_velocities_kernel(const int numCells,
                                                const double* cellMass,
                                                const double* cellPx,
                                                const double* cellPy,
                                                double* cellUx,
                                                double* cellUy) {
    const int c = blockIdx.x * blockDim.x + threadIdx.x;
    if (c >= numCells) return;
    const double m = cellMass[c];
    if (m > 0.0) {
        cellUx[c] = cellPx[c] / m;
        cellUy[c] = cellPy[c] / m;
    } else {
        cellUx[c] = 0.0;
        cellUy[c] = 0.0;
    }
}

bool periodic_x(const SimulationParams& params) {
    return params.bcLeft == "periodic" && params.bcRight == "periodic";
}

bool periodic_y(const SimulationParams& params) {
    return params.bcBottom == "periodic" && params.bcTop == "periodic";
}

} // namespace

bool cuda_cell_moments_available() {
    int count = 0;
    const cudaError_t err = cudaGetDeviceCount(&count);
    if (err != cudaSuccess) {
        cudaGetLastError();
        return false;
    }
    return count > 0;
}

void cuda_deposit_cell_moments_atomic(const ParticleState& state,
                                      const CellGrid& grid,
                                      const GridShift& shift,
                                      const SimulationParams& params,
                                      CudaCellMoments& out,
                                      CudaCellMomentsDiagnostics* diagnostics,
                                      CudaCellMomentsOptions options) {
    validate_particle_state(state, "cuda_deposit_cell_moments_atomic");
    if (grid.Nx <= 0 || grid.Ny <= 0 || grid.numCells != grid.Nx * grid.Ny) {
        throw std::runtime_error("cuda_deposit_cell_moments_atomic: invalid grid");
    }
    if (!(grid.dx > 0.0) || !(grid.dy > 0.0) || !(grid.Lx > 0.0) || !(grid.Ly > 0.0)) {
        throw std::runtime_error("cuda_deposit_cell_moments_atomic: invalid grid spacing/domain");
    }
    if (options.threadsPerBlock <= 0) {
        options.threadsPerBlock = 256;
    }

    const Clock::time_point t0 = Clock::now();
    const std::size_t n = static_cast<std::size_t>(state.Np);
    const int nInt = static_cast<int>(n);
    if (static_cast<std::size_t>(nInt) != n) {
        throw std::runtime_error("cuda_deposit_cell_moments_atomic: particle count exceeds int range for prototype kernel");
    }
    const int nc = grid.numCells;

    std::vector<std::uint8_t> roleFallback;
    const std::uint8_t* h_role = nullptr;
    if (state.role.empty()) {
        roleFallback.assign(n, kParticleRoleFluid);
        h_role = roleFallback.data();
    } else {
        h_role = state.role.data();
    }

    std::uint64_t fluidParticles = 0u;
    for (std::size_t i = 0; i < n; ++i) {
        if (h_role[i] == kParticleRoleFluid) ++fluidParticles;
    }

    out.cellId.assign(n, -1);
    out.cellCount.assign(static_cast<std::size_t>(nc), 0u);
    out.cellMass.assign(static_cast<std::size_t>(nc), 0.0);
    out.cellPx.assign(static_cast<std::size_t>(nc), 0.0);
    out.cellPy.assign(static_cast<std::size_t>(nc), 0.0);
    out.cellUx.assign(static_cast<std::size_t>(nc), 0.0);
    out.cellUy.assign(static_cast<std::size_t>(nc), 0.0);

    double* d_x = nullptr;
    double* d_y = nullptr;
    double* d_vx = nullptr;
    double* d_vy = nullptr;
    double* d_mass = nullptr;
    unsigned char* d_role = nullptr;
    int* d_cellId = nullptr;
    unsigned int* d_count = nullptr;
    double* d_cellMass = nullptr;
    double* d_cellPx = nullptr;
    double* d_cellPy = nullptr;
    double* d_cellUx = nullptr;
    double* d_cellUy = nullptr;

    const Clock::time_point tu0 = Clock::now();
    cuda_alloc(&d_x, n, "cudaMalloc d_x");
    cuda_alloc(&d_y, n, "cudaMalloc d_y");
    cuda_alloc(&d_vx, n, "cudaMalloc d_vx");
    cuda_alloc(&d_vy, n, "cudaMalloc d_vy");
    cuda_alloc(&d_mass, n, "cudaMalloc d_mass");
    cuda_alloc(&d_role, n, "cudaMalloc d_role");
    cuda_alloc(&d_cellId, n, "cudaMalloc d_cellId");
    cuda_alloc(&d_count, static_cast<std::size_t>(nc), "cudaMalloc d_count");
    cuda_alloc(&d_cellMass, static_cast<std::size_t>(nc), "cudaMalloc d_cellMass");
    cuda_alloc(&d_cellPx, static_cast<std::size_t>(nc), "cudaMalloc d_cellPx");
    cuda_alloc(&d_cellPy, static_cast<std::size_t>(nc), "cudaMalloc d_cellPy");
    cuda_alloc(&d_cellUx, static_cast<std::size_t>(nc), "cudaMalloc d_cellUx");
    cuda_alloc(&d_cellUy, static_cast<std::size_t>(nc), "cudaMalloc d_cellUy");

    cuda_check(cudaMemcpy(d_x, state.x.data(), n * sizeof(double), cudaMemcpyHostToDevice), "copy x H2D");
    cuda_check(cudaMemcpy(d_y, state.y.data(), n * sizeof(double), cudaMemcpyHostToDevice), "copy y H2D");
    cuda_check(cudaMemcpy(d_vx, state.vx.data(), n * sizeof(double), cudaMemcpyHostToDevice), "copy vx H2D");
    cuda_check(cudaMemcpy(d_vy, state.vy.data(), n * sizeof(double), cudaMemcpyHostToDevice), "copy vy H2D");
    cuda_check(cudaMemcpy(d_mass, state.mass.data(), n * sizeof(double), cudaMemcpyHostToDevice), "copy mass H2D");
    cuda_check(cudaMemcpy(d_role, h_role, n * sizeof(unsigned char), cudaMemcpyHostToDevice), "copy role H2D");
    const Clock::time_point tu1 = Clock::now();

    DeviceDepositConfig cfg{};
    cfg.nx = grid.Nx;
    cfg.ny = grid.Ny;
    cfg.numCells = grid.numCells;
    cfg.lx = grid.Lx;
    cfg.ly = grid.Ly;
    cfg.dx = grid.dx;
    cfg.dy = grid.dy;
    cfg.shiftX = shift.sx;
    cfg.shiftY = shift.sy;
    cfg.periodicX = periodic_x(params) ? 1 : 0;
    cfg.periodicY = periodic_y(params) ? 1 : 0;

    const int block = options.threadsPerBlock;
    const int particleGrid = std::max(1, (nInt + block - 1) / block);
    const int cellGrid = std::max(1, (nc + block - 1) / block);
    const int resetGrid = std::max(particleGrid, cellGrid);

    const Clock::time_point tk0 = Clock::now();
    reset_cell_moments_kernel<<<resetGrid, block>>>(nInt, nc, d_cellId, d_count, d_cellMass,
                                                    d_cellPx, d_cellPy, d_cellUx, d_cellUy);
    cuda_check(cudaGetLastError(), "launch reset_cell_moments_kernel");
    deposit_cell_moments_atomic_kernel<<<particleGrid, block>>>(nInt, d_x, d_y, d_vx, d_vy, d_mass,
                                                                d_role, cfg, d_cellId, d_count,
                                                                d_cellMass, d_cellPx, d_cellPy);
    cuda_check(cudaGetLastError(), "launch deposit_cell_moments_atomic_kernel");
    finalize_cell_velocities_kernel<<<cellGrid, block>>>(nc, d_cellMass, d_cellPx, d_cellPy, d_cellUx, d_cellUy);
    cuda_check(cudaGetLastError(), "launch finalize_cell_velocities_kernel");
    cuda_check(cudaDeviceSynchronize(), "cuda_deposit_cell_moments_atomic synchronize");
    const Clock::time_point tk1 = Clock::now();

    const Clock::time_point td0 = Clock::now();
    cuda_check(cudaMemcpy(out.cellId.data(), d_cellId, n * sizeof(int), cudaMemcpyDeviceToHost), "copy cellId D2H");
    cuda_check(cudaMemcpy(out.cellCount.data(), d_count, static_cast<std::size_t>(nc) * sizeof(std::uint32_t), cudaMemcpyDeviceToHost), "copy count D2H");
    cuda_check(cudaMemcpy(out.cellMass.data(), d_cellMass, static_cast<std::size_t>(nc) * sizeof(double), cudaMemcpyDeviceToHost), "copy cellMass D2H");
    cuda_check(cudaMemcpy(out.cellPx.data(), d_cellPx, static_cast<std::size_t>(nc) * sizeof(double), cudaMemcpyDeviceToHost), "copy cellPx D2H");
    cuda_check(cudaMemcpy(out.cellPy.data(), d_cellPy, static_cast<std::size_t>(nc) * sizeof(double), cudaMemcpyDeviceToHost), "copy cellPy D2H");
    cuda_check(cudaMemcpy(out.cellUx.data(), d_cellUx, static_cast<std::size_t>(nc) * sizeof(double), cudaMemcpyDeviceToHost), "copy cellUx D2H");
    cuda_check(cudaMemcpy(out.cellUy.data(), d_cellUy, static_cast<std::size_t>(nc) * sizeof(double), cudaMemcpyDeviceToHost), "copy cellUy D2H");
    const Clock::time_point td1 = Clock::now();

    cuda_free(d_x);
    cuda_free(d_y);
    cuda_free(d_vx);
    cuda_free(d_vy);
    cuda_free(d_mass);
    cuda_free(d_role);
    cuda_free(d_cellId);
    cuda_free(d_count);
    cuda_free(d_cellMass);
    cuda_free(d_cellPx);
    cuda_free(d_cellPy);
    cuda_free(d_cellUx);
    cuda_free(d_cellUy);

    const Clock::time_point t1 = Clock::now();
    if (diagnostics != nullptr) {
        diagnostics->particlesVisited = static_cast<std::uint64_t>(n);
        diagnostics->fluidParticles = fluidParticles;
        diagnostics->numCells = nc;
        diagnostics->uploadSeconds = seconds_between(tu0, tu1);
        diagnostics->kernelSeconds = seconds_between(tk0, tk1);
        diagnostics->downloadSeconds = seconds_between(td0, td1);
        diagnostics->totalSeconds = seconds_between(t0, t1);
    }
}

} // namespace mpcd
