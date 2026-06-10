#include "cuda_cell_thermostat.h"
#include "cuda_particle_state.h"
#include "cuda_cell_workspace.h"

#include <cuda_runtime.h>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <limits>
#include <numeric>
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

__global__ void kinetic_relative_kernel(const std::uint64_t n,
                                        const int* __restrict__ cellId,
                                        const std::uint8_t* __restrict__ role,
                                        const double* __restrict__ mass,
                                        const double* __restrict__ vx,
                                        const double* __restrict__ vy,
                                        const double* __restrict__ cellUx,
                                        const double* __restrict__ cellUy,
                                        const int numCells,
                                        const std::uint8_t fluidRole,
                                        double* __restrict__ cellKinetic,
                                        unsigned long long* __restrict__ fluidCounter) {
    const std::uint64_t i = static_cast<std::uint64_t>(blockIdx.x) * blockDim.x + threadIdx.x;
    if (i >= n) return;
    if (role[i] != fluidRole) return;
    const int c = cellId[i];
    if (c < 0 || c >= numCells) return;
    const double dvx = vx[i] - cellUx[c];
    const double dvy = vy[i] - cellUy[c];
    const double k = 0.5 * mass[i] * (dvx * dvx + dvy * dvy);
    atomicAdd(&cellKinetic[c], k);
    atomicAdd(fluidCounter, 1ull);
}

__global__ void scale_kernel(const int numCells,
                             const std::uint32_t* __restrict__ cellCount,
                             const double* __restrict__ cellKinetic,
                             const double targetKBT,
                             const int minParticles,
                             const double epsilon,
                             double* __restrict__ cellScale) {
    const int c = blockIdx.x * blockDim.x + threadIdx.x;
    if (c >= numCells) return;
    double scale = 1.0;
    const std::uint32_t count = cellCount[c];
    const double K = cellKinetic[c];
    if (count >= static_cast<std::uint32_t>(minParticles) && K > epsilon) {
        const double dof = 2.0 * static_cast<double>(count - 1u);
        const double targetK = 0.5 * dof * targetKBT;
        scale = sqrt(targetK / K);
    }
    cellScale[c] = scale;
}

__global__ void apply_rescale_kernel(const std::uint64_t n,
                                     const int* __restrict__ cellId,
                                     const std::uint8_t* __restrict__ role,
                                     const double* __restrict__ cellUx,
                                     const double* __restrict__ cellUy,
                                     const double* __restrict__ cellScale,
                                     const int numCells,
                                     const std::uint8_t fluidRole,
                                     double* __restrict__ vx,
                                     double* __restrict__ vy) {
    const std::uint64_t i = static_cast<std::uint64_t>(blockIdx.x) * blockDim.x + threadIdx.x;
    if (i >= n) return;
    if (role[i] != fluidRole) return;
    const int c = cellId[i];
    if (c < 0 || c >= numCells) return;
    const double scale = cellScale[c];
    if (scale == 1.0) return;
    const double ux = cellUx[c];
    const double uy = cellUy[c];
    vx[i] = ux + scale * (vx[i] - ux);
    vy[i] = uy + scale * (vy[i] - uy);
}

std::vector<std::uint8_t> normalized_roles(const ParticleState& state) {
    // 0315l: legacy CUDA wrappers launch kernels only over the active prefix.
    // Do not materialise role[0:Np_total] just to guard those active-prefix
    // kernels; that made the wrappers scale with the inactive reservoir.
    const std::size_t n = active_fluid_count_size(state);
    if (state.role.empty()) {
        return std::vector<std::uint8_t>(n, kParticleRoleFluid);
    }
    return std::vector<std::uint8_t>(state.role.begin(), state.role.begin() + static_cast<std::ptrdiff_t>(n));
}

ThermostatDiagnostics diagnostics_from_cells(const std::vector<std::uint32_t>& cellCount,
                                             const std::vector<double>& cellKinetic,
                                             const std::vector<double>& cellScale,
                                             double targetKBT,
                                             int minParticles,
                                             double epsilon) {
    ThermostatDiagnostics diag{};
    double totalKBefore = 0.0;
    double targetKTotal = 0.0;
    double scaleSum = 0.0;
    double scaleMin = std::numeric_limits<double>::infinity();
    double scaleMax = 0.0;
    std::uint64_t dofTotal = 0u;
    std::uint64_t cellsRescaled = 0u;
    std::uint64_t particlesRescaled = 0u;

    const int nc = static_cast<int>(cellCount.size());
    for (int c = 0; c < nc; ++c) {
        const std::uint32_t count = cellCount[static_cast<std::size_t>(c)];
        const double K = cellKinetic[static_cast<std::size_t>(c)];
        if (count < static_cast<std::uint32_t>(minParticles)) continue;
        if (!(K > epsilon)) continue;
        const double dof = 2.0 * static_cast<double>(count - 1u);
        const double targetK = 0.5 * dof * targetKBT;
        const double scale = cellScale[static_cast<std::size_t>(c)];
        totalKBefore += K;
        targetKTotal += targetK;
        dofTotal += static_cast<std::uint64_t>(2u * (count - 1u));
        cellsRescaled += 1u;
        particlesRescaled += static_cast<std::uint64_t>(count);
        scaleSum += scale;
        if (scale < scaleMin) scaleMin = scale;
        if (scale > scaleMax) scaleMax = scale;
    }

    diag.applied = cellsRescaled > 0u;
    diag.cellsRescaled = cellsRescaled;
    diag.particlesRescaled = particlesRescaled;
    diag.kBTBefore = dofTotal > 0u ? (2.0 * totalKBefore / static_cast<double>(dofTotal)) : 0.0;
    diag.kBTAfter = dofTotal > 0u ? (2.0 * targetKTotal / static_cast<double>(dofTotal)) : 0.0;
    diag.scaleMean = cellsRescaled > 0u ? scaleSum / static_cast<double>(cellsRescaled) : 1.0;
    diag.scaleMin = cellsRescaled > 0u ? scaleMin : 1.0;
    diag.scaleMax = cellsRescaled > 0u ? scaleMax : 1.0;
    return diag;
}

} // namespace

bool cuda_cell_thermostat_available() {
#ifdef MPCD_ENABLE_CUDA_THERMOSTAT
    return true;
#else
    return false;
#endif
}

ThermostatDiagnostics cuda_apply_cell_relative_rescale_thermostat_from_moments(
    ParticleState& state,
    int numCells,
    const std::vector<int>& cellId,
    const std::vector<std::uint32_t>& cellCount,
    const std::vector<double>& cellUx,
    const std::vector<double>& cellUy,
    double targetKBT,
    int minParticles,
    double epsilon,
    CudaCellThermostatDiagnostics* cudaDiag,
    CudaCellThermostatOptions options) {
#ifndef MPCD_ENABLE_CUDA_THERMOSTAT
    (void)state; (void)numCells; (void)cellId; (void)cellCount; (void)cellUx; (void)cellUy;
    (void)targetKBT; (void)minParticles; (void)epsilon; (void)cudaDiag; (void)options;
    throw std::runtime_error("cuda_apply_cell_relative_rescale_thermostat_from_moments called without MPCD_ENABLE_CUDA_THERMOSTAT");
#else
    validate_particle_state(state, "cuda_apply_cell_relative_rescale_thermostat_from_moments");
    if (numCells <= 0) throw std::runtime_error("cuda thermostat: invalid numCells");
    const std::size_t n = active_fluid_count_size(state);
    if (cellId.size() != n) throw std::runtime_error("cuda thermostat: cellId size mismatch");
    if (cellCount.size() != static_cast<std::size_t>(numCells) ||
        cellUx.size() != static_cast<std::size_t>(numCells) ||
        cellUy.size() != static_cast<std::size_t>(numCells)) {
        throw std::runtime_error("cuda thermostat: cell moment array size mismatch");
    }
    if (!(targetKBT > 0.0)) throw std::runtime_error("cuda thermostat: targetKBT must be positive");
    if (minParticles < 1) minParticles = 1;
    if (!(epsilon >= 0.0)) epsilon = 0.0;
    const int threads = std::max(32, options.threadsPerBlock);
    const int particleBlocks = static_cast<int>((n + static_cast<std::size_t>(threads) - 1u) / static_cast<std::size_t>(threads));
    const int cellBlocks = (numCells + threads - 1) / threads;

    CudaCellThermostatDiagnostics localDiag{};
    localDiag.particlesVisited = static_cast<std::uint64_t>(n);
    localDiag.numCells = numCells;

    const auto tTotal0 = Clock::now();
    auto t0 = Clock::now();

    std::vector<std::uint8_t> roleHost = normalized_roles(state);

    double *dVx = nullptr, *dVy = nullptr, *dMass = nullptr, *dCellUx = nullptr, *dCellUy = nullptr;
    double *dCellKinetic = nullptr, *dCellScale = nullptr;
    int* dCellId = nullptr;
    std::uint32_t* dCellCount = nullptr;
    std::uint8_t* dRole = nullptr;
    unsigned long long* dFluidCounter = nullptr;

    const std::size_t nBytesD = n * sizeof(double);
    const std::size_t nBytesI = n * sizeof(int);
    const std::size_t nBytesR = n * sizeof(std::uint8_t);
    const std::size_t cBytesD = static_cast<std::size_t>(numCells) * sizeof(double);
    const std::size_t cBytesC = static_cast<std::size_t>(numCells) * sizeof(std::uint32_t);

    MPCD_CUDA_CHECK(cudaMalloc(&dVx, nBytesD));
    MPCD_CUDA_CHECK(cudaMalloc(&dVy, nBytesD));
    MPCD_CUDA_CHECK(cudaMalloc(&dMass, nBytesD));
    MPCD_CUDA_CHECK(cudaMalloc(&dCellId, nBytesI));
    MPCD_CUDA_CHECK(cudaMalloc(&dRole, nBytesR));
    MPCD_CUDA_CHECK(cudaMalloc(&dCellCount, cBytesC));
    MPCD_CUDA_CHECK(cudaMalloc(&dCellUx, cBytesD));
    MPCD_CUDA_CHECK(cudaMalloc(&dCellUy, cBytesD));
    MPCD_CUDA_CHECK(cudaMalloc(&dCellKinetic, cBytesD));
    MPCD_CUDA_CHECK(cudaMalloc(&dCellScale, cBytesD));
    MPCD_CUDA_CHECK(cudaMalloc(&dFluidCounter, sizeof(unsigned long long)));

    MPCD_CUDA_CHECK(cudaMemcpy(dVx, state.vx.data(), nBytesD, cudaMemcpyHostToDevice));
    MPCD_CUDA_CHECK(cudaMemcpy(dVy, state.vy.data(), nBytesD, cudaMemcpyHostToDevice));
    MPCD_CUDA_CHECK(cudaMemcpy(dMass, state.mass.data(), nBytesD, cudaMemcpyHostToDevice));
    MPCD_CUDA_CHECK(cudaMemcpy(dCellId, cellId.data(), nBytesI, cudaMemcpyHostToDevice));
    MPCD_CUDA_CHECK(cudaMemcpy(dRole, roleHost.data(), nBytesR, cudaMemcpyHostToDevice));
    MPCD_CUDA_CHECK(cudaMemcpy(dCellCount, cellCount.data(), cBytesC, cudaMemcpyHostToDevice));
    MPCD_CUDA_CHECK(cudaMemcpy(dCellUx, cellUx.data(), cBytesD, cudaMemcpyHostToDevice));
    MPCD_CUDA_CHECK(cudaMemcpy(dCellUy, cellUy.data(), cBytesD, cudaMemcpyHostToDevice));
    MPCD_CUDA_CHECK(cudaMemset(dCellKinetic, 0, cBytesD));
    MPCD_CUDA_CHECK(cudaMemset(dFluidCounter, 0, sizeof(unsigned long long)));
    MPCD_CUDA_CHECK(cudaDeviceSynchronize());
    localDiag.uploadSeconds = seconds_since(t0);

    t0 = Clock::now();
    kinetic_relative_kernel<<<particleBlocks, threads>>>(static_cast<std::uint64_t>(n), dCellId, dRole, dMass, dVx, dVy,
                                                         dCellUx, dCellUy, numCells,
                                                         kParticleRoleFluid, dCellKinetic, dFluidCounter);
    MPCD_CUDA_CHECK(cudaGetLastError());
    MPCD_CUDA_CHECK(cudaDeviceSynchronize());
    localDiag.kineticKernelSeconds = seconds_since(t0);

    t0 = Clock::now();
    scale_kernel<<<cellBlocks, threads>>>(numCells, dCellCount, dCellKinetic,
                                          targetKBT, minParticles, epsilon, dCellScale);
    MPCD_CUDA_CHECK(cudaGetLastError());
    MPCD_CUDA_CHECK(cudaDeviceSynchronize());
    localDiag.scaleKernelSeconds = seconds_since(t0);

    t0 = Clock::now();
    apply_rescale_kernel<<<particleBlocks, threads>>>(static_cast<std::uint64_t>(n), dCellId, dRole, dCellUx, dCellUy,
                                                      dCellScale, numCells, kParticleRoleFluid,
                                                      dVx, dVy);
    MPCD_CUDA_CHECK(cudaGetLastError());
    MPCD_CUDA_CHECK(cudaDeviceSynchronize());
    localDiag.applyKernelSeconds = seconds_since(t0);

    t0 = Clock::now();
    std::vector<double> cellKinetic(static_cast<std::size_t>(numCells), 0.0);
    std::vector<double> cellScale(static_cast<std::size_t>(numCells), 1.0);
    unsigned long long fluidCounter = 0ull;
    MPCD_CUDA_CHECK(cudaMemcpy(state.vx.data(), dVx, nBytesD, cudaMemcpyDeviceToHost));
    MPCD_CUDA_CHECK(cudaMemcpy(state.vy.data(), dVy, nBytesD, cudaMemcpyDeviceToHost));
    MPCD_CUDA_CHECK(cudaMemcpy(cellKinetic.data(), dCellKinetic, cBytesD, cudaMemcpyDeviceToHost));
    MPCD_CUDA_CHECK(cudaMemcpy(cellScale.data(), dCellScale, cBytesD, cudaMemcpyDeviceToHost));
    MPCD_CUDA_CHECK(cudaMemcpy(&fluidCounter, dFluidCounter, sizeof(unsigned long long), cudaMemcpyDeviceToHost));
    MPCD_CUDA_CHECK(cudaDeviceSynchronize());
    localDiag.downloadSeconds = seconds_since(t0);
    localDiag.fluidParticles = static_cast<std::uint64_t>(fluidCounter);

    cudaFree(dVx); cudaFree(dVy); cudaFree(dMass); cudaFree(dCellId); cudaFree(dRole);
    cudaFree(dCellCount); cudaFree(dCellUx); cudaFree(dCellUy); cudaFree(dCellKinetic);
    cudaFree(dCellScale); cudaFree(dFluidCounter);

    ThermostatDiagnostics diag = diagnostics_from_cells(cellCount, cellKinetic, cellScale,
                                                        targetKBT, minParticles, epsilon);
    localDiag.applied = diag.applied;
    localDiag.cellsRescaled = diag.cellsRescaled;
    localDiag.particlesRescaled = diag.particlesRescaled;
    localDiag.kBTBefore = diag.kBTBefore;
    localDiag.kBTAfter = diag.kBTAfter;
    localDiag.scaleMean = diag.scaleMean;
    localDiag.scaleMin = diag.scaleMin;
    localDiag.scaleMax = diag.scaleMax;
    localDiag.totalSeconds = seconds_since(tTotal0);
    if (cudaDiag) *cudaDiag = localDiag;
    return diag;
#endif
}


ThermostatDiagnostics cuda_apply_cell_relative_rescale_thermostat_from_shared_state_0258(
    CudaParticleState& gpuState,
    CudaCellWorkspace& cellWorkspace,
    ParticleState& downloadTarget,
    int numCells,
    const std::vector<int>& cellId,
    const std::vector<std::uint32_t>& cellCount,
    const std::vector<double>& cellUx,
    const std::vector<double>& cellUy,
    double targetKBT,
    int minParticles,
    double epsilon,
    CudaCellThermostatDiagnostics* cudaDiag,
    CudaCellThermostatOptions options) {
#if !defined(MPCD_ENABLE_CUDA_THERMOSTAT) || !defined(MPCD_ENABLE_CUDA_PARTICLE_STATE) || !defined(MPCD_ENABLE_CUDA_CELL_WORKSPACE)
    (void)gpuState; (void)cellWorkspace; (void)downloadTarget; (void)numCells; (void)cellId;
    (void)cellCount; (void)cellUx; (void)cellUy; (void)targetKBT; (void)minParticles;
    (void)epsilon; (void)cudaDiag; (void)options;
    throw std::runtime_error("cuda_apply_cell_relative_rescale_thermostat_from_shared_state_0258 requires CUDA thermostat, particle state and cell workspace");
#else
    validate_particle_state(downloadTarget, "cuda_apply_cell_relative_rescale_thermostat_from_shared_state_0258");
    if (numCells <= 0) throw std::runtime_error("cuda thermostat 0258: invalid numCells");
    const std::size_t n = active_fluid_count_size(downloadTarget);
    if (gpuState.size() != downloadTarget.Np) throw std::runtime_error("cuda thermostat 0258: particle-state size mismatch");
    if (cellWorkspace.particle_capacity() < active_fluid_count(downloadTarget) || cellWorkspace.cell_capacity() < numCells) {
        throw std::runtime_error("cuda thermostat 0258: cell workspace capacity too small");
    }
    if (cellId.size() != n) throw std::runtime_error("cuda thermostat 0258: cellId size mismatch");
    if (cellCount.size() != static_cast<std::size_t>(numCells) ||
        cellUx.size() != static_cast<std::size_t>(numCells) ||
        cellUy.size() != static_cast<std::size_t>(numCells)) {
        throw std::runtime_error("cuda thermostat 0258: cell moment array size mismatch");
    }
    if (!(targetKBT > 0.0)) throw std::runtime_error("cuda thermostat 0258: targetKBT must be positive");
    if (minParticles < 1) minParticles = 1;
    if (!(epsilon >= 0.0)) epsilon = 0.0;

    const int threads = std::max(32, options.threadsPerBlock);
    const int particleBlocks = static_cast<int>((n + static_cast<std::size_t>(threads) - 1u) / static_cast<std::size_t>(threads));
    const int cellBlocks = (numCells + threads - 1) / threads;

    CudaCellThermostatDiagnostics localDiag{};
    localDiag.particlesVisited = static_cast<std::uint64_t>(n);
    localDiag.numCells = numCells;

    const auto tTotal0 = Clock::now();
    auto t0 = Clock::now();

    CudaParticleDeviceView pv = gpuState.device_view();
    CudaCellWorkspaceDeviceView cv = cellWorkspace.device_view();
    if (pv.vx == nullptr || pv.vy == nullptr || pv.mass == nullptr || pv.role == nullptr ||
        cv.cellId == nullptr || cv.count == nullptr || cv.cellUx == nullptr || cv.cellUy == nullptr ||
        cv.cellKinetic == nullptr || cv.cellScale == nullptr || cv.fluidCounter == nullptr) {
        throw std::runtime_error("cuda thermostat 0258: null device view");
    }

    const std::size_t nBytesI = n * sizeof(int);
    const std::size_t cBytesD = static_cast<std::size_t>(numCells) * sizeof(double);
    const std::size_t cBytesC = static_cast<std::size_t>(numCells) * sizeof(std::uint32_t);

    MPCD_CUDA_CHECK(cudaMemcpy(cv.cellId, cellId.data(), nBytesI, cudaMemcpyHostToDevice));
    MPCD_CUDA_CHECK(cudaMemcpy(cv.count, cellCount.data(), cBytesC, cudaMemcpyHostToDevice));
    MPCD_CUDA_CHECK(cudaMemcpy(cv.cellUx, cellUx.data(), cBytesD, cudaMemcpyHostToDevice));
    MPCD_CUDA_CHECK(cudaMemcpy(cv.cellUy, cellUy.data(), cBytesD, cudaMemcpyHostToDevice));
    MPCD_CUDA_CHECK(cudaMemset(cv.cellKinetic, 0, cBytesD));
    MPCD_CUDA_CHECK(cudaMemset(cv.fluidCounter, 0, sizeof(unsigned long long)));
    MPCD_CUDA_CHECK(cudaDeviceSynchronize());
    localDiag.uploadSeconds = seconds_since(t0);

    t0 = Clock::now();
    kinetic_relative_kernel<<<particleBlocks, threads>>>(static_cast<std::uint64_t>(n), cv.cellId,
                                                         reinterpret_cast<const std::uint8_t*>(pv.role),
                                                         pv.mass, pv.vx, pv.vy,
                                                         cv.cellUx, cv.cellUy, numCells,
                                                         kParticleRoleFluid, cv.cellKinetic, cv.fluidCounter);
    MPCD_CUDA_CHECK(cudaGetLastError());
    MPCD_CUDA_CHECK(cudaDeviceSynchronize());
    localDiag.kineticKernelSeconds = seconds_since(t0);

    t0 = Clock::now();
    scale_kernel<<<cellBlocks, threads>>>(numCells, cv.count, cv.cellKinetic,
                                          targetKBT, minParticles, epsilon, cv.cellScale);
    MPCD_CUDA_CHECK(cudaGetLastError());
    MPCD_CUDA_CHECK(cudaDeviceSynchronize());
    localDiag.scaleKernelSeconds = seconds_since(t0);

    t0 = Clock::now();
    apply_rescale_kernel<<<particleBlocks, threads>>>(static_cast<std::uint64_t>(n), cv.cellId,
                                                      reinterpret_cast<const std::uint8_t*>(pv.role),
                                                      cv.cellUx, cv.cellUy, cv.cellScale,
                                                      numCells, kParticleRoleFluid,
                                                      pv.vx, pv.vy);
    MPCD_CUDA_CHECK(cudaGetLastError());
    MPCD_CUDA_CHECK(cudaDeviceSynchronize());
    localDiag.applyKernelSeconds = seconds_since(t0);

    t0 = Clock::now();
    CudaParticleStateDiagnostics downloadDiag{};
    gpuState.download_velocities(downloadTarget, &downloadDiag);
    std::vector<double> cellKinetic(static_cast<std::size_t>(numCells), 0.0);
    std::vector<double> cellScale(static_cast<std::size_t>(numCells), 1.0);
    unsigned long long fluidCounter = 0ull;
    MPCD_CUDA_CHECK(cudaMemcpy(cellKinetic.data(), cv.cellKinetic, cBytesD, cudaMemcpyDeviceToHost));
    MPCD_CUDA_CHECK(cudaMemcpy(cellScale.data(), cv.cellScale, cBytesD, cudaMemcpyDeviceToHost));
    MPCD_CUDA_CHECK(cudaMemcpy(&fluidCounter, cv.fluidCounter, sizeof(unsigned long long), cudaMemcpyDeviceToHost));
    MPCD_CUDA_CHECK(cudaDeviceSynchronize());
    localDiag.downloadSeconds = seconds_since(t0);
    localDiag.fluidParticles = static_cast<std::uint64_t>(fluidCounter);

    ThermostatDiagnostics diag = diagnostics_from_cells(cellCount, cellKinetic, cellScale,
                                                        targetKBT, minParticles, epsilon);
    localDiag.applied = diag.applied;
    localDiag.cellsRescaled = diag.cellsRescaled;
    localDiag.particlesRescaled = diag.particlesRescaled;
    localDiag.kBTBefore = diag.kBTBefore;
    localDiag.kBTAfter = diag.kBTAfter;
    localDiag.scaleMean = diag.scaleMean;
    localDiag.scaleMin = diag.scaleMin;
    localDiag.scaleMax = diag.scaleMax;
    localDiag.totalSeconds = seconds_since(tTotal0);
    localDiag.particleStateUploadSeconds = 0.0;
    if (cudaDiag) *cudaDiag = localDiag;
    return diag;
#endif
}

} // namespace mpcd
