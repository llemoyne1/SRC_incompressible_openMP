#include "cuda_resampling_guard.h"

#include <cuda_runtime.h>

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <limits>
#include <stdexcept>
#include <string>
#include <utility>

namespace mpcd {
namespace {

inline void check_cuda(cudaError_t err, const char* what) {
    if (err != cudaSuccess) {
        throw std::runtime_error(std::string("cuda_resampling_guard: ") + what + ": " + cudaGetErrorString(err));
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

__global__ void compact_poor_rich_kernel_0228(
    const std::uint32_t* __restrict__ count,
    const double* __restrict__ mass,
    const std::uint8_t* __restrict__ activeMask,
    int nCells,
    double targetMass,
    double poorRel,
    double richRel,
    std::uint32_t minFluidCount,
    int useActiveMask,
    std::uint32_t* __restrict__ poorCounter,
    std::uint32_t* __restrict__ richCounter,
    std::uint32_t* __restrict__ poorCells,
    std::uint32_t* __restrict__ richCells,
    double* __restrict__ deficits,
    double* __restrict__ excesses)
{
    const int c = blockIdx.x * blockDim.x + threadIdx.x;
    if (c >= nCells) return;

    const bool active = (!useActiveMask) || (activeMask && activeMask[c] != 0u);
    if (!active) return;

    const std::uint32_t n = count[c];
    const double m = mass[c];
    const double poorLimit = targetMass * (1.0 - poorRel);
    const double richLimit = targetMass * (1.0 + richRel);
    const bool isPoor = (n < minFluidCount || m < poorLimit);
    const bool isRich = (m > richLimit);

    if (isPoor) {
        const std::uint32_t k = atomicAdd(poorCounter, 1u);
        poorCells[k] = static_cast<std::uint32_t>(c);
        deficits[k] = fmax(0.0, targetMass - m);
    }
    if (isRich) {
        const std::uint32_t k = atomicAdd(richCounter, 1u);
        richCells[k] = static_cast<std::uint32_t>(c);
        excesses[k] = fmax(0.0, m - targetMass);
    }
}

std::uint64_t sum_flags(const std::vector<std::uint8_t>& v) {
    std::uint64_t s = 0u;
    for (std::uint8_t x : v) s += static_cast<std::uint64_t>(x != 0u);
    return s;
}

struct CellAmount {
    std::uint32_t cell = 0u;
    double amount = 0.0;
};

void sort_pairs(std::vector<std::uint32_t>& cells, std::vector<double>& amounts) {
    std::vector<CellAmount> pairs;
    pairs.reserve(cells.size());
    for (std::size_t i = 0; i < cells.size(); ++i) pairs.push_back({cells[i], amounts[i]});
    std::sort(pairs.begin(), pairs.end(), [](const CellAmount& a, const CellAmount& b) {
        return a.cell < b.cell;
    });
    for (std::size_t i = 0; i < pairs.size(); ++i) {
        cells[i] = pairs[i].cell;
        amounts[i] = pairs[i].amount;
    }
}

void greedy_plan_from_sorted_lists(
    const CudaResamplingPlanParams& params,
    const std::vector<std::uint32_t>& poorCells,
    const std::vector<double>& deficits,
    const std::vector<std::uint32_t>& richCells,
    const std::vector<double>& excesses,
    std::vector<std::uint32_t>& receiverCell,
    std::vector<std::uint32_t>& donorCell,
    std::vector<double>& transferMass,
    CudaResamplingPlanDiagnostics* diag)
{
    receiverCell.clear();
    donorCell.clear();
    transferMass.clear();

    double totalDeficit = 0.0;
    double totalExcess = 0.0;
    double minDef = std::numeric_limits<double>::infinity();
    double maxDef = 0.0;
    double minExc = std::numeric_limits<double>::infinity();
    double maxExc = 0.0;
    for (double d : deficits) {
        totalDeficit += d;
        if (d > 0.0) { minDef = std::min(minDef, d); maxDef = std::max(maxDef, d); }
    }
    for (double e : excesses) {
        totalExcess += e;
        if (e > 0.0) { minExc = std::min(minExc, e); maxExc = std::max(maxExc, e); }
    }

    std::size_t ip = 0u;
    std::size_t ir = 0u;
    double dp = deficits.empty() ? 0.0 : deficits[0];
    double er = excesses.empty() ? 0.0 : excesses[0];
    const std::size_t maxT = params.maxTransfers == 0u ? std::numeric_limits<std::size_t>::max() : params.maxTransfers;
    double planned = 0.0;

    while (ip < poorCells.size() && ir < richCells.size() && receiverCell.size() < maxT) {
        while (ip < poorCells.size() && dp <= params.minTransferMass) {
            ++ip;
            if (ip < poorCells.size()) dp = deficits[ip];
        }
        while (ir < richCells.size() && er <= params.minTransferMass) {
            ++ir;
            if (ir < richCells.size()) er = excesses[ir];
        }
        if (ip >= poorCells.size() || ir >= richCells.size()) break;

        const double m = std::min(dp, er);
        if (m > params.minTransferMass) {
            receiverCell.push_back(poorCells[ip]);
            donorCell.push_back(richCells[ir]);
            transferMass.push_back(m);
            planned += m;
        }
        dp -= m;
        er -= m;
    }

    if (diag) {
        diag->transfers = static_cast<std::uint64_t>(receiverCell.size());
        diag->totalDeficit = totalDeficit;
        diag->totalExcess = totalExcess;
        diag->plannedMass = planned;
        diag->unmatchedDeficit = std::max(0.0, totalDeficit - planned);
        diag->unmatchedExcess = std::max(0.0, totalExcess - planned);
        diag->minPoorDeficit = std::isfinite(minDef) ? minDef : 0.0;
        diag->maxPoorDeficit = maxDef;
        diag->minRichExcess = std::isfinite(minExc) ? minExc : 0.0;
        diag->maxRichExcess = maxExc;
    }
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

bool cuda_resampling_compact_and_plan_0228(
    const std::vector<std::uint32_t>& cellCount,
    const std::vector<double>& cellMass,
    const std::vector<std::uint8_t>& activeCell,
    const CudaResamplingPlanParams& params,
    std::vector<std::uint32_t>& poorCellIndices,
    std::vector<std::uint32_t>& richCellIndices,
    std::vector<double>& poorDeficit,
    std::vector<double>& richExcess,
    std::vector<std::uint32_t>& planReceiverCell,
    std::vector<std::uint32_t>& planDonorCell,
    std::vector<double>& planMass,
    CudaResamplingPlanDiagnostics* diagnostics)
{
    if (cellCount.size() != cellMass.size()) {
        throw std::runtime_error("cuda_resampling_compact_and_plan_0228: count/mass size mismatch");
    }
    if (params.guard.useActiveMask && activeCell.size() != cellCount.size()) {
        throw std::runtime_error("cuda_resampling_compact_and_plan_0228: active mask size mismatch");
    }
    if (!(params.guard.targetCellMass > 0.0) || !std::isfinite(params.guard.targetCellMass)) {
        throw std::runtime_error("cuda_resampling_compact_and_plan_0228: invalid targetCellMass");
    }
    if (!(params.minTransferMass >= 0.0) || !std::isfinite(params.minTransferMass)) {
        throw std::runtime_error("cuda_resampling_compact_and_plan_0228: invalid minTransferMass");
    }

    poorCellIndices.clear();
    richCellIndices.clear();
    poorDeficit.clear();
    richExcess.clear();
    planReceiverCell.clear();
    planDonorCell.clear();
    planMass.clear();

    if (diagnostics) {
        *diagnostics = CudaResamplingPlanDiagnostics{};
        diagnostics->attempted = true;
        diagnostics->cells = static_cast<std::uint64_t>(cellCount.size());
    }

    const int nCells = static_cast<int>(cellCount.size());
    if (nCells == 0) {
        if (diagnostics) diagnostics->applied = true;
        return true;
    }

    std::uint32_t* d_count = nullptr;
    double* d_mass = nullptr;
    std::uint8_t* d_active = nullptr;
    std::uint32_t* d_poorCounter = nullptr;
    std::uint32_t* d_richCounter = nullptr;
    std::uint32_t* d_poorCells = nullptr;
    std::uint32_t* d_richCells = nullptr;
    double* d_deficits = nullptr;
    double* d_excesses = nullptr;

    const std::size_t nCountBytes = cellCount.size() * sizeof(std::uint32_t);
    const std::size_t nMassBytes = cellMass.size() * sizeof(double);
    const std::size_t nFlagBytes = cellCount.size() * sizeof(std::uint8_t);
    const std::size_t nCellBytes = cellCount.size() * sizeof(std::uint32_t);
    const std::size_t nDoubleBytes = cellCount.size() * sizeof(double);

    check_cuda(cudaMalloc(&d_count, nCountBytes), "malloc count");
    check_cuda(cudaMalloc(&d_mass, nMassBytes), "malloc mass");
    check_cuda(cudaMalloc(&d_poorCounter, sizeof(std::uint32_t)), "malloc poorCounter");
    check_cuda(cudaMalloc(&d_richCounter, sizeof(std::uint32_t)), "malloc richCounter");
    check_cuda(cudaMalloc(&d_poorCells, nCellBytes), "malloc poorCells");
    check_cuda(cudaMalloc(&d_richCells, nCellBytes), "malloc richCells");
    check_cuda(cudaMalloc(&d_deficits, nDoubleBytes), "malloc deficits");
    check_cuda(cudaMalloc(&d_excesses, nDoubleBytes), "malloc excesses");

    check_cuda(cudaMemcpy(d_count, cellCount.data(), nCountBytes, cudaMemcpyHostToDevice), "copy count");
    check_cuda(cudaMemcpy(d_mass, cellMass.data(), nMassBytes, cudaMemcpyHostToDevice), "copy mass");
    check_cuda(cudaMemset(d_poorCounter, 0, sizeof(std::uint32_t)), "zero poorCounter");
    check_cuda(cudaMemset(d_richCounter, 0, sizeof(std::uint32_t)), "zero richCounter");
    if (params.guard.useActiveMask) {
        check_cuda(cudaMalloc(&d_active, nFlagBytes), "malloc active");
        check_cuda(cudaMemcpy(d_active, activeCell.data(), nFlagBytes, cudaMemcpyHostToDevice), "copy active");
    }

    const int threads = 256;
    const int blocks = (nCells + threads - 1) / threads;
    compact_poor_rich_kernel_0228<<<blocks, threads>>>(
        d_count, d_mass, d_active, nCells,
        params.guard.targetCellMass,
        params.guard.poorRelativeThreshold,
        params.guard.richRelativeThreshold,
        params.guard.minFluidCount,
        params.guard.useActiveMask ? 1 : 0,
        d_poorCounter, d_richCounter,
        d_poorCells, d_richCells, d_deficits, d_excesses);
    check_cuda(cudaGetLastError(), "launch compact");
    check_cuda(cudaDeviceSynchronize(), "sync compact");

    std::uint32_t hPoor = 0u;
    std::uint32_t hRich = 0u;
    check_cuda(cudaMemcpy(&hPoor, d_poorCounter, sizeof(std::uint32_t), cudaMemcpyDeviceToHost), "copy poorCounter");
    check_cuda(cudaMemcpy(&hRich, d_richCounter, sizeof(std::uint32_t), cudaMemcpyDeviceToHost), "copy richCounter");

    poorCellIndices.resize(hPoor);
    richCellIndices.resize(hRich);
    poorDeficit.resize(hPoor);
    richExcess.resize(hRich);
    if (hPoor > 0u) {
        check_cuda(cudaMemcpy(poorCellIndices.data(), d_poorCells, hPoor * sizeof(std::uint32_t), cudaMemcpyDeviceToHost), "copy poorCells");
        check_cuda(cudaMemcpy(poorDeficit.data(), d_deficits, hPoor * sizeof(double), cudaMemcpyDeviceToHost), "copy deficits");
    }
    if (hRich > 0u) {
        check_cuda(cudaMemcpy(richCellIndices.data(), d_richCells, hRich * sizeof(std::uint32_t), cudaMemcpyDeviceToHost), "copy richCells");
        check_cuda(cudaMemcpy(richExcess.data(), d_excesses, hRich * sizeof(double), cudaMemcpyDeviceToHost), "copy excesses");
    }

    sort_pairs(poorCellIndices, poorDeficit);
    sort_pairs(richCellIndices, richExcess);

    if (diagnostics) {
        diagnostics->activeCells = params.guard.useActiveMask ? sum_flags(activeCell) : static_cast<std::uint64_t>(cellCount.size());
        diagnostics->poorCells = poorCellIndices.size();
        diagnostics->richCells = richCellIndices.size();
    }
    greedy_plan_from_sorted_lists(params, poorCellIndices, poorDeficit, richCellIndices, richExcess,
                                  planReceiverCell, planDonorCell, planMass, diagnostics);
    if (diagnostics) diagnostics->applied = true;

    cudaFree(d_count);
    cudaFree(d_mass);
    cudaFree(d_active);
    cudaFree(d_poorCounter);
    cudaFree(d_richCounter);
    cudaFree(d_poorCells);
    cudaFree(d_richCells);
    cudaFree(d_deficits);
    cudaFree(d_excesses);
    return true;
}

} // namespace mpcd
