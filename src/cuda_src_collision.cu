#include "cuda_src_collision.h"

#include <cuda_runtime.h>

#include <algorithm>
#include <chrono>
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

std::vector<std::uint8_t> normalized_roles(const ParticleState& state) {
    const std::size_t n = static_cast<std::size_t>(state.Np);
    if (state.role.empty()) {
        return std::vector<std::uint8_t>(n, kParticleRoleFluid);
    }
    return state.role;
}

__global__ void src_rotate_kernel(std::uint64_t n,
                                  const int* __restrict__ cellId,
                                  const std::uint8_t* __restrict__ role,
                                  const double* __restrict__ cellUx,
                                  const double* __restrict__ cellUy,
                                  const double* __restrict__ cosA,
                                  const double* __restrict__ sinA,
                                  int numCells,
                                  std::uint8_t fluidRole,
                                  double* __restrict__ vx,
                                  double* __restrict__ vy,
                                  unsigned long long* __restrict__ rotatedCounter,
                                  unsigned long long* __restrict__ invalidCellCounter) {
    const std::uint64_t i = static_cast<std::uint64_t>(blockIdx.x) * blockDim.x + threadIdx.x;
    if (i >= n) return;
    if (role[i] != fluidRole) return;

    const int c = cellId[i];
    if (c < 0 || c >= numCells) {
        atomicAdd(invalidCellCounter, 1ull);
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

} // namespace

bool cuda_src_collision_available() {
#ifdef MPCD_ENABLE_CUDA_SRC_COLLISION
    return true;
#else
    return false;
#endif
}

CudaSrcCollisionDiagnostics cuda_apply_src_collision_from_cell_moments(
    ParticleState& state,
    int numCells,
    const std::vector<int>& cellId,
    const std::vector<double>& cellUx,
    const std::vector<double>& cellUy,
    const std::vector<double>& cosA,
    const std::vector<double>& sinA,
    CudaSrcCollisionOptions options) {
#ifndef MPCD_ENABLE_CUDA_SRC_COLLISION
    (void)state; (void)numCells; (void)cellId; (void)cellUx; (void)cellUy; (void)cosA; (void)sinA; (void)options;
    throw std::runtime_error("cuda_apply_src_collision_from_cell_moments called without MPCD_ENABLE_CUDA_SRC_COLLISION");
#else
    validate_particle_state(state, "cuda_apply_src_collision_from_cell_moments");
    if (numCells <= 0) throw std::runtime_error("cuda SRC collision: invalid numCells");
    const std::size_t n = static_cast<std::size_t>(state.Np);
    if (cellId.size() != n) throw std::runtime_error("cuda SRC collision: cellId size mismatch");
    const std::size_t nc = static_cast<std::size_t>(numCells);
    if (cellUx.size() != nc || cellUy.size() != nc || cosA.size() != nc || sinA.size() != nc) {
        throw std::runtime_error("cuda SRC collision: cell array size mismatch");
    }

    CudaSrcCollisionDiagnostics diag{};
    diag.particlesVisited = state.Np;
    diag.numCells = numCells;

    const int threads = std::max(32, options.threadsPerBlock);
    const int blocks = static_cast<int>((n + static_cast<std::size_t>(threads) - 1u) / static_cast<std::size_t>(threads));

    const auto tTotal0 = Clock::now();
    auto t0 = Clock::now();

    std::vector<std::uint8_t> roleHost = normalized_roles(state);

    double *dVx = nullptr, *dVy = nullptr;
    double *dCellUx = nullptr, *dCellUy = nullptr, *dCosA = nullptr, *dSinA = nullptr;
    int* dCellId = nullptr;
    std::uint8_t* dRole = nullptr;
    unsigned long long* dRotatedCounter = nullptr;
    unsigned long long* dInvalidCellCounter = nullptr;

    const std::size_t nBytesD = n * sizeof(double);
    const std::size_t nBytesI = n * sizeof(int);
    const std::size_t nBytesR = n * sizeof(std::uint8_t);
    const std::size_t cBytesD = nc * sizeof(double);

    MPCD_CUDA_CHECK(cudaMalloc(&dVx, nBytesD));
    MPCD_CUDA_CHECK(cudaMalloc(&dVy, nBytesD));
    MPCD_CUDA_CHECK(cudaMalloc(&dCellId, nBytesI));
    MPCD_CUDA_CHECK(cudaMalloc(&dRole, nBytesR));
    MPCD_CUDA_CHECK(cudaMalloc(&dCellUx, cBytesD));
    MPCD_CUDA_CHECK(cudaMalloc(&dCellUy, cBytesD));
    MPCD_CUDA_CHECK(cudaMalloc(&dCosA, cBytesD));
    MPCD_CUDA_CHECK(cudaMalloc(&dSinA, cBytesD));
    MPCD_CUDA_CHECK(cudaMalloc(&dRotatedCounter, sizeof(unsigned long long)));
    MPCD_CUDA_CHECK(cudaMalloc(&dInvalidCellCounter, sizeof(unsigned long long)));

    MPCD_CUDA_CHECK(cudaMemcpy(dVx, state.vx.data(), nBytesD, cudaMemcpyHostToDevice));
    MPCD_CUDA_CHECK(cudaMemcpy(dVy, state.vy.data(), nBytesD, cudaMemcpyHostToDevice));
    MPCD_CUDA_CHECK(cudaMemcpy(dCellId, cellId.data(), nBytesI, cudaMemcpyHostToDevice));
    MPCD_CUDA_CHECK(cudaMemcpy(dRole, roleHost.data(), nBytesR, cudaMemcpyHostToDevice));
    MPCD_CUDA_CHECK(cudaMemcpy(dCellUx, cellUx.data(), cBytesD, cudaMemcpyHostToDevice));
    MPCD_CUDA_CHECK(cudaMemcpy(dCellUy, cellUy.data(), cBytesD, cudaMemcpyHostToDevice));
    MPCD_CUDA_CHECK(cudaMemcpy(dCosA, cosA.data(), cBytesD, cudaMemcpyHostToDevice));
    MPCD_CUDA_CHECK(cudaMemcpy(dSinA, sinA.data(), cBytesD, cudaMemcpyHostToDevice));
    MPCD_CUDA_CHECK(cudaMemset(dRotatedCounter, 0, sizeof(unsigned long long)));
    MPCD_CUDA_CHECK(cudaMemset(dInvalidCellCounter, 0, sizeof(unsigned long long)));
    MPCD_CUDA_CHECK(cudaDeviceSynchronize());
    diag.uploadSeconds = seconds_since(t0);

    t0 = Clock::now();
    if (blocks > 0) {
        src_rotate_kernel<<<blocks, threads>>>(state.Np, dCellId, dRole, dCellUx, dCellUy, dCosA, dSinA,
                                               numCells, kParticleRoleFluid, dVx, dVy,
                                               dRotatedCounter, dInvalidCellCounter);
        MPCD_CUDA_CHECK(cudaGetLastError());
    }
    MPCD_CUDA_CHECK(cudaDeviceSynchronize());
    diag.kernelSeconds = seconds_since(t0);

    t0 = Clock::now();
    MPCD_CUDA_CHECK(cudaMemcpy(state.vx.data(), dVx, nBytesD, cudaMemcpyDeviceToHost));
    MPCD_CUDA_CHECK(cudaMemcpy(state.vy.data(), dVy, nBytesD, cudaMemcpyDeviceToHost));
    unsigned long long rotated = 0ull;
    unsigned long long invalid = 0ull;
    MPCD_CUDA_CHECK(cudaMemcpy(&rotated, dRotatedCounter, sizeof(unsigned long long), cudaMemcpyDeviceToHost));
    MPCD_CUDA_CHECK(cudaMemcpy(&invalid, dInvalidCellCounter, sizeof(unsigned long long), cudaMemcpyDeviceToHost));
    MPCD_CUDA_CHECK(cudaDeviceSynchronize());
    diag.downloadSeconds = seconds_since(t0);

    diag.particlesRotated = static_cast<std::uint64_t>(rotated);
    diag.invalidCellParticles = static_cast<std::uint64_t>(invalid);
    diag.totalSeconds = seconds_since(tTotal0);

    cudaFree(dVx);
    cudaFree(dVy);
    cudaFree(dCellId);
    cudaFree(dRole);
    cudaFree(dCellUx);
    cudaFree(dCellUy);
    cudaFree(dCosA);
    cudaFree(dSinA);
    cudaFree(dRotatedCounter);
    cudaFree(dInvalidCellCounter);

    return diag;
#endif
}

} // namespace mpcd
