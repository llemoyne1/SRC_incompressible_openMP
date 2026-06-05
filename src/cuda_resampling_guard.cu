#include "cuda_resampling_guard.h"

#include <cuda_runtime.h>

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <limits>
#include <stdexcept>
#include <string>

namespace mpcd {
namespace {

inline void check_cuda(cudaError_t err, const char* what) {
    if (err != cudaSuccess) {
        throw std::runtime_error(std::string("cuda_resampling_guard_0227: ") + what + ": " + cudaGetErrorString(err));
    }
}

__global__ void classify_cells_kernel_0227(
    const std::uint32_t* __restrict__ count,
    const double* __restrict__ mass,
    const std::uint8_t* __restrict__ activeMask,
    int nCells,
    double targetMass,
    double poorRel,
    double richRel,
    std::uint32_t minFluidCount,
    int useActiveMask,
    std::uint8_t* __restrict__ wet,
    std::uint8_t* __restrict__ dry,
    std::uint8_t* __restrict__ poor,
    std::uint8_t* __restrict__ rich,
    std::uint8_t* __restrict__ targetBand)
{
    const int c = blockIdx.x * blockDim.x + threadIdx.x;
    if (c >= nCells) return;

    const bool active = (!useActiveMask) || (activeMask && activeMask[c] != 0u);
    const std::uint32_t n = count[c];
    const double m = mass[c];
    const bool isWet = active && n > 0u;
    const bool isDry = active && n == 0u;
    const double poorLimit = targetMass * (1.0 - poorRel);
    const double richLimit = targetMass * (1.0 + richRel);

    const bool isPoor = active && (n < minFluidCount || m < poorLimit);
    const bool isRich = active && (m > richLimit);
    const bool isTarget = active && isWet && !isPoor && !isRich;

    wet[c] = static_cast<std::uint8_t>(isWet ? 1u : 0u);
    dry[c] = static_cast<std::uint8_t>(isDry ? 1u : 0u);
    poor[c] = static_cast<std::uint8_t>(isPoor ? 1u : 0u);
    rich[c] = static_cast<std::uint8_t>(isRich ? 1u : 0u);
    targetBand[c] = static_cast<std::uint8_t>(isTarget ? 1u : 0u);
}

std::uint64_t sum_flags(const std::vector<std::uint8_t>& v) {
    std::uint64_t s = 0u;
    for (std::uint8_t x : v) s += static_cast<std::uint64_t>(x != 0u);
    return s;
}

} // namespace

bool cuda_resampling_classify_cells_0227(
    const std::vector<std::uint32_t>& cellCount,
    const std::vector<double>& cellMass,
    const std::vector<std::uint8_t>& activeCell,
    const CudaResamplingGuardParams& params,
    std::vector<std::uint8_t>& wetCell,
    std::vector<std::uint8_t>& dryCell,
    std::vector<std::uint8_t>& poorCell,
    std::vector<std::uint8_t>& richCell,
    std::vector<std::uint8_t>& targetBandCell,
    CudaResamplingGuardDiagnostics* diagnostics)
{
    if (cellCount.size() != cellMass.size()) {
        throw std::runtime_error("cuda_resampling_classify_cells_0227: count/mass size mismatch");
    }
    if (params.useActiveMask && activeCell.size() != cellCount.size()) {
        throw std::runtime_error("cuda_resampling_classify_cells_0227: active mask size mismatch");
    }
    if (!(params.targetCellMass > 0.0) || !std::isfinite(params.targetCellMass)) {
        throw std::runtime_error("cuda_resampling_classify_cells_0227: invalid targetCellMass");
    }
    const int nCells = static_cast<int>(cellCount.size());
    wetCell.assign(cellCount.size(), 0u);
    dryCell.assign(cellCount.size(), 0u);
    poorCell.assign(cellCount.size(), 0u);
    richCell.assign(cellCount.size(), 0u);
    targetBandCell.assign(cellCount.size(), 0u);

    if (diagnostics) {
        *diagnostics = CudaResamplingGuardDiagnostics{};
        diagnostics->attempted = true;
        diagnostics->cells = static_cast<std::uint64_t>(cellCount.size());
    }
    if (nCells == 0) return true;

    std::uint32_t* d_count = nullptr;
    double* d_mass = nullptr;
    std::uint8_t* d_active = nullptr;
    std::uint8_t* d_wet = nullptr;
    std::uint8_t* d_dry = nullptr;
    std::uint8_t* d_poor = nullptr;
    std::uint8_t* d_rich = nullptr;
    std::uint8_t* d_target = nullptr;

    const std::size_t nCountBytes = cellCount.size() * sizeof(std::uint32_t);
    const std::size_t nMassBytes = cellMass.size() * sizeof(double);
    const std::size_t nFlagBytes = cellCount.size() * sizeof(std::uint8_t);

    check_cuda(cudaMalloc(&d_count, nCountBytes), "malloc count");
    check_cuda(cudaMalloc(&d_mass, nMassBytes), "malloc mass");
    check_cuda(cudaMalloc(&d_wet, nFlagBytes), "malloc wet");
    check_cuda(cudaMalloc(&d_dry, nFlagBytes), "malloc dry");
    check_cuda(cudaMalloc(&d_poor, nFlagBytes), "malloc poor");
    check_cuda(cudaMalloc(&d_rich, nFlagBytes), "malloc rich");
    check_cuda(cudaMalloc(&d_target, nFlagBytes), "malloc target");
    check_cuda(cudaMemcpy(d_count, cellCount.data(), nCountBytes, cudaMemcpyHostToDevice), "copy count");
    check_cuda(cudaMemcpy(d_mass, cellMass.data(), nMassBytes, cudaMemcpyHostToDevice), "copy mass");
    if (params.useActiveMask) {
        check_cuda(cudaMalloc(&d_active, nFlagBytes), "malloc active");
        check_cuda(cudaMemcpy(d_active, activeCell.data(), nFlagBytes, cudaMemcpyHostToDevice), "copy active");
    }

    const int threads = 256;
    const int blocks = (nCells + threads - 1) / threads;
    classify_cells_kernel_0227<<<blocks, threads>>>(
        d_count, d_mass, d_active, nCells,
        params.targetCellMass,
        params.poorRelativeThreshold,
        params.richRelativeThreshold,
        params.minFluidCount,
        params.useActiveMask ? 1 : 0,
        d_wet, d_dry, d_poor, d_rich, d_target);
    check_cuda(cudaGetLastError(), "launch classify");
    check_cuda(cudaDeviceSynchronize(), "sync classify");

    check_cuda(cudaMemcpy(wetCell.data(), d_wet, nFlagBytes, cudaMemcpyDeviceToHost), "copy wet");
    check_cuda(cudaMemcpy(dryCell.data(), d_dry, nFlagBytes, cudaMemcpyDeviceToHost), "copy dry");
    check_cuda(cudaMemcpy(poorCell.data(), d_poor, nFlagBytes, cudaMemcpyDeviceToHost), "copy poor");
    check_cuda(cudaMemcpy(richCell.data(), d_rich, nFlagBytes, cudaMemcpyDeviceToHost), "copy rich");
    check_cuda(cudaMemcpy(targetBandCell.data(), d_target, nFlagBytes, cudaMemcpyDeviceToHost), "copy target");

    if (diagnostics) {
        diagnostics->applied = true;
        diagnostics->wetCells = sum_flags(wetCell);
        diagnostics->dryCells = sum_flags(dryCell);
        diagnostics->poorCells = sum_flags(poorCell);
        diagnostics->richCells = sum_flags(richCell);
        diagnostics->targetBandCells = sum_flags(targetBandCell);
        diagnostics->activeCells = params.useActiveMask ? sum_flags(activeCell) : diagnostics->cells;
        double total = 0.0;
        double mn = std::numeric_limits<double>::infinity();
        double mx = 0.0;
        for (double m : cellMass) {
            total += m;
            mn = std::min(mn, m);
            mx = std::max(mx, m);
        }
        diagnostics->totalMass = total;
        diagnostics->minMass = std::isfinite(mn) ? mn : 0.0;
        diagnostics->maxMass = mx;
    }

    cudaFree(d_count);
    cudaFree(d_mass);
    cudaFree(d_active);
    cudaFree(d_wet);
    cudaFree(d_dry);
    cudaFree(d_poor);
    cudaFree(d_rich);
    cudaFree(d_target);
    return true;
}

} // namespace mpcd
