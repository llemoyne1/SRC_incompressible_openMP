#include "cell_grid.h"
#include "cuda_cell_moments.h"
#include "cuda_cell_workspace.h"
#include "cuda_particle_state.h"
#include "fluid_domain.h"
#include "particle_state.h"
#include "simulation_params.h"
#include "weighted_resampling.h"

#include <cuda_runtime.h>

#include <algorithm>
#include <cmath>
#include <chrono>
#include <cstdint>
#include <cstdlib>
#include <iomanip>
#include <iostream>
#include <limits>
#include <random>
#include <stdexcept>
#include <string>
#include <vector>

// 0441 standalone validator support.
// The validator intentionally runs only periodic wall-free/no-solid synthetic cases.
// We define the small boundary/solid hooks needed by cell_grid.cpp and
// weighted_resampling.cpp without linking the full production params/solid stack.
namespace mpcd {

bool is_x_periodic(const SimulationParams& p) {
    return p.bcLeft == "periodic" && p.bcRight == "periodic";
}

bool is_y_periodic(const SimulationParams& p) {
    return p.bcBottom == "periodic" && p.bcTop == "periodic";
}

bool immersed_solid_enabled(const SimulationParams&) {
    return false;
}

double immersed_solid_fraction_in_cell(int,
                                       int,
                                       const CellGrid&,
                                       const GridShift&,
                                       const SimulationParams&,
                                       const FluidDomainBounds&,
                                       double) {
    return 0.0;
}

} // namespace mpcd

namespace {

using Clock0441 = std::chrono::steady_clock;

double seconds_between0441(const Clock0441::time_point a, const Clock0441::time_point b) {
    return std::chrono::duration<double>(b - a).count();
}

void cuda_check0441(cudaError_t err, const char* context) {
    if (err != cudaSuccess) {
        throw std::runtime_error(std::string(context) + ": " + cudaGetErrorString(err));
    }
}

__global__ void compact_poor_rich_cells_kernel_0441(const int numCells,
                                                    const double* cellMass,
                                                    const double poorThreshold,
                                                    const double richThreshold,
                                                    int* poorList,
                                                    int* richList,
                                                    unsigned int* poorCount,
                                                    unsigned int* richCount) {
    const int tid = blockIdx.x * blockDim.x + threadIdx.x;
    const int stride = blockDim.x * gridDim.x;
    for (int c = tid; c < numCells; c += stride) {
        const double m = cellMass[c];
        if (m < poorThreshold) {
            const unsigned int pos = atomicAdd(poorCount, 1u);
            poorList[pos] = c;
        }
        if (m > richThreshold) {
            const unsigned int pos = atomicAdd(richCount, 1u);
            richList[pos] = c;
        }
    }
}

struct GpuCompactedLists0441 {
    std::vector<int> poor;
    std::vector<int> rich;
    double kernelSeconds = 0.0;
    double totalSeconds = 0.0;
};

GpuCompactedLists0441 compact_poor_rich_gpu_0441(const std::vector<double>& cellMass,
                                                 const double poorThreshold,
                                                 const double richThreshold,
                                                 const int threadsPerBlock) {
    GpuCompactedLists0441 out{};
    const int numCells = static_cast<int>(cellMass.size());
    if (numCells <= 0) return out;

    double* d_mass = nullptr;
    int* d_poor = nullptr;
    int* d_rich = nullptr;
    unsigned int* d_poorCount = nullptr;
    unsigned int* d_richCount = nullptr;

    const auto t0 = Clock0441::now();
    cuda_check0441(cudaMalloc(reinterpret_cast<void**>(&d_mass), sizeof(double) * static_cast<std::size_t>(numCells)), "cudaMalloc d_mass compact 0441");
    cuda_check0441(cudaMalloc(reinterpret_cast<void**>(&d_poor), sizeof(int) * static_cast<std::size_t>(numCells)), "cudaMalloc d_poor compact 0441");
    cuda_check0441(cudaMalloc(reinterpret_cast<void**>(&d_rich), sizeof(int) * static_cast<std::size_t>(numCells)), "cudaMalloc d_rich compact 0441");
    cuda_check0441(cudaMalloc(reinterpret_cast<void**>(&d_poorCount), sizeof(unsigned int)), "cudaMalloc d_poorCount compact 0441");
    cuda_check0441(cudaMalloc(reinterpret_cast<void**>(&d_richCount), sizeof(unsigned int)), "cudaMalloc d_richCount compact 0441");
    cuda_check0441(cudaMemcpy(d_mass, cellMass.data(), sizeof(double) * static_cast<std::size_t>(numCells), cudaMemcpyHostToDevice), "cudaMemcpy compact mass H2D 0441");
    cuda_check0441(cudaMemset(d_poorCount, 0, sizeof(unsigned int)), "cudaMemset poorCount 0441");
    cuda_check0441(cudaMemset(d_richCount, 0, sizeof(unsigned int)), "cudaMemset richCount 0441");

    const int tpb = std::max(32, threadsPerBlock);
    const int blocks = std::max(1, (numCells + tpb - 1) / tpb);
    const auto k0 = Clock0441::now();
    compact_poor_rich_cells_kernel_0441<<<blocks, tpb>>>(numCells, d_mass, poorThreshold, richThreshold,
                                                         d_poor, d_rich, d_poorCount, d_richCount);
    cuda_check0441(cudaGetLastError(), "launch compact_poor_rich_cells_kernel_0441");
    cuda_check0441(cudaDeviceSynchronize(), "sync compact_poor_rich_cells_kernel_0441");
    const auto k1 = Clock0441::now();

    unsigned int h_poorCount = 0u;
    unsigned int h_richCount = 0u;
    cuda_check0441(cudaMemcpy(&h_poorCount, d_poorCount, sizeof(unsigned int), cudaMemcpyDeviceToHost), "copy poorCount D2H 0441");
    cuda_check0441(cudaMemcpy(&h_richCount, d_richCount, sizeof(unsigned int), cudaMemcpyDeviceToHost), "copy richCount D2H 0441");
    out.poor.assign(static_cast<std::size_t>(h_poorCount), -1);
    out.rich.assign(static_cast<std::size_t>(h_richCount), -1);
    if (h_poorCount > 0u) {
        cuda_check0441(cudaMemcpy(out.poor.data(), d_poor, sizeof(int) * static_cast<std::size_t>(h_poorCount), cudaMemcpyDeviceToHost), "copy poorList D2H 0441");
    }
    if (h_richCount > 0u) {
        cuda_check0441(cudaMemcpy(out.rich.data(), d_rich, sizeof(int) * static_cast<std::size_t>(h_richCount), cudaMemcpyDeviceToHost), "copy richList D2H 0441");
    }
    std::sort(out.poor.begin(), out.poor.end());
    std::sort(out.rich.begin(), out.rich.end());

    cudaFree(d_mass);
    cudaFree(d_poor);
    cudaFree(d_rich);
    cudaFree(d_poorCount);
    cudaFree(d_richCount);
    const auto t1 = Clock0441::now();
    out.kernelSeconds = seconds_between0441(k0, k1);
    out.totalSeconds = seconds_between0441(t0, t1);
    return out;
}

std::uint64_t sorted_list_mismatch0441(const std::vector<int>& a, const std::vector<int>& b) {
    const std::size_t n = std::min(a.size(), b.size());
    std::uint64_t mism = static_cast<std::uint64_t>(std::max(a.size(), b.size()) - n);
    for (std::size_t i = 0; i < n; ++i) {
        if (a[i] != b[i]) ++mism;
    }
    return mism;
}

int env_int(const char* name, int fallback) {
    const char* v = std::getenv(name);
    if (v == nullptr || *v == '\0') return fallback;
    return std::stoi(v);
}

double env_double(const char* name, double fallback) {
    const char* v = std::getenv(name);
    if (v == nullptr || *v == '\0') return fallback;
    return std::stod(v);
}

std::uint64_t env_u64(const char* name, std::uint64_t fallback) {
    const char* v = std::getenv(name);
    if (v == nullptr || *v == '\0') return fallback;
    return static_cast<std::uint64_t>(std::stoull(v));
}


struct TransferPlanEntry0441 {
    int donorCell = -1;
    int receiverCell = -1;
    double plannedMass = 0.0;
    double cellDistance = 0.0;
    double donorRemainingAfter = 0.0;
    double receiverRemainingAfter = 0.0;
};

__device__ double cell_distance_device_0441(int a, int b, int nx, int ny, int xPeriodic, int yPeriodic) {
    if (a < 0 || b < 0 || nx <= 0 || ny <= 0) return 0.0;
    const int ax = a % nx;
    const int ay = a / nx;
    const int bx = b % nx;
    const int by = b / nx;
    int dx = ax > bx ? ax - bx : bx - ax;
    int dy = ay > by ? ay - by : by - ay;
    if (xPeriodic) dx = dx < (nx - dx) ? dx : (nx - dx);
    if (yPeriodic) dy = dy < (ny - dy) ? dy : (ny - dy);
    return sqrt(static_cast<double>(dx * dx + dy * dy));
}

__global__ void build_transfer_plan_serial_kernel_0441(const int nx,
                                                       const int ny,
                                                       const int xPeriodic,
                                                       const int yPeriodic,
                                                       const double targetCellMass,
                                                       const int poorCount,
                                                       const int richCount,
                                                       const int* poorCells,
                                                       const int* richCells,
                                                       double* receiverRemaining,
                                                       double* donorRemaining,
                                                       const double* cellMass,
                                                       const int maxPlanEntries,
                                                       int* outDonor,
                                                       int* outReceiver,
                                                       double* outMass,
                                                       double* outDistance,
                                                       double* outDonorRemainingAfter,
                                                       double* outReceiverRemainingAfter,
                                                       unsigned int* outCount,
                                                       double* outPlannedMass,
                                                       double* outRemainingReceiver,
                                                       double* outRemainingDonor,
                                                       unsigned int* outAdjacentPairs) {
    if (blockIdx.x != 0 || threadIdx.x != 0) return;
    constexpr double eps = 1.0e-14;
    constexpr double adjacentLimit = 1.4142135623730950488 + 1.0e-12;
    unsigned int planCount = 0u;
    double plannedMass = 0.0;
    unsigned int adjacentPairs = 0u;

    for (int ir = 0; ir < poorCount; ++ir) {
        const int rc = poorCells[ir];
        const double deficit = targetCellMass - cellMass[rc];
        receiverRemaining[ir] = deficit > 0.0 ? deficit : 0.0;
    }
    for (int id = 0; id < richCount; ++id) {
        const int dc = richCells[id];
        const double excess = cellMass[dc] - targetCellMass;
        donorRemaining[id] = excess > 0.0 ? excess : 0.0;
    }

    for (int ir = 0; ir < poorCount; ++ir) {
        const int rc = poorCells[ir];
        while (receiverRemaining[ir] > eps) {
            int bestDonor = richCount;
            int bestCell = -1;
            double bestDistance = 1.0e300;
            for (int id = 0; id < richCount; ++id) {
                if (donorRemaining[id] <= eps) continue;
                const int dc = richCells[id];
                const double dist = cell_distance_device_0441(dc, rc, nx, ny, xPeriodic, yPeriodic);
                if (dist < bestDistance || (dist == bestDistance && dc < bestCell)) {
                    bestDistance = dist;
                    bestDonor = id;
                    bestCell = dc;
                }
            }
            if (bestDonor == richCount) break;
            double transfer = donorRemaining[bestDonor] < receiverRemaining[ir]
                ? donorRemaining[bestDonor] : receiverRemaining[ir];
            if (transfer <= eps) break;
            donorRemaining[bestDonor] -= transfer;
            receiverRemaining[ir] -= transfer;
            if (static_cast<int>(planCount) < maxPlanEntries) {
                outDonor[planCount] = richCells[bestDonor];
                outReceiver[planCount] = rc;
                outMass[planCount] = transfer;
                outDistance[planCount] = bestDistance;
                outDonorRemainingAfter[planCount] = donorRemaining[bestDonor];
                outReceiverRemainingAfter[planCount] = receiverRemaining[ir];
            }
            ++planCount;
            plannedMass += transfer;
            if (bestDistance <= adjacentLimit) ++adjacentPairs;
        }
    }

    double remReceiver = 0.0;
    double remDonor = 0.0;
    for (int ir = 0; ir < poorCount; ++ir) remReceiver += receiverRemaining[ir];
    for (int id = 0; id < richCount; ++id) remDonor += donorRemaining[id];
    *outCount = planCount;
    *outPlannedMass = plannedMass;
    *outRemainingReceiver = remReceiver;
    *outRemainingDonor = remDonor;
    *outAdjacentPairs = adjacentPairs;
}

struct GpuTransferPlan0441 {
    std::vector<TransferPlanEntry0441> entries;
    double kernelSeconds = 0.0;
    double totalSeconds = 0.0;
    double plannedMass = 0.0;
    double remainingReceiver = 0.0;
    double remainingDonor = 0.0;
    std::uint64_t adjacentPairs = 0u;
};

GpuTransferPlan0441 build_transfer_plan_gpu_0441(const std::vector<double>& cellMass,
                                                 const std::vector<int>& poorCells,
                                                 const std::vector<int>& richCells,
                                                 int nx,
                                                 int ny,
                                                 bool xPeriodic,
                                                 bool yPeriodic,
                                                 double targetCellMass) {
    GpuTransferPlan0441 out{};
    const int numCells = static_cast<int>(cellMass.size());
    const int poorCount = static_cast<int>(poorCells.size());
    const int richCount = static_cast<int>(richCells.size());
    const int maxPlanEntries = std::max(1, poorCount * std::max(1, richCount));
    if (numCells <= 0 || poorCount <= 0 || richCount <= 0) return out;

    double* d_mass = nullptr;
    int* d_poor = nullptr;
    int* d_rich = nullptr;
    double* d_receiverRemaining = nullptr;
    double* d_donorRemaining = nullptr;
    int* d_outDonor = nullptr;
    int* d_outReceiver = nullptr;
    double* d_outMass = nullptr;
    double* d_outDistance = nullptr;
    double* d_outDonorRemainingAfter = nullptr;
    double* d_outReceiverRemainingAfter = nullptr;
    unsigned int* d_count = nullptr;
    double* d_plannedMass = nullptr;
    double* d_remainingReceiver = nullptr;
    double* d_remainingDonor = nullptr;
    unsigned int* d_adjacentPairs = nullptr;

    const auto t0 = Clock0441::now();
    cuda_check0441(cudaMalloc(reinterpret_cast<void**>(&d_mass), sizeof(double) * static_cast<std::size_t>(numCells)), "cudaMalloc planner d_mass 0441");
    cuda_check0441(cudaMalloc(reinterpret_cast<void**>(&d_poor), sizeof(int) * static_cast<std::size_t>(poorCount)), "cudaMalloc planner d_poor 0441");
    cuda_check0441(cudaMalloc(reinterpret_cast<void**>(&d_rich), sizeof(int) * static_cast<std::size_t>(richCount)), "cudaMalloc planner d_rich 0441");
    cuda_check0441(cudaMalloc(reinterpret_cast<void**>(&d_receiverRemaining), sizeof(double) * static_cast<std::size_t>(poorCount)), "cudaMalloc planner receiverRemaining 0441");
    cuda_check0441(cudaMalloc(reinterpret_cast<void**>(&d_donorRemaining), sizeof(double) * static_cast<std::size_t>(richCount)), "cudaMalloc planner donorRemaining 0441");
    cuda_check0441(cudaMalloc(reinterpret_cast<void**>(&d_outDonor), sizeof(int) * static_cast<std::size_t>(maxPlanEntries)), "cudaMalloc planner donor 0441");
    cuda_check0441(cudaMalloc(reinterpret_cast<void**>(&d_outReceiver), sizeof(int) * static_cast<std::size_t>(maxPlanEntries)), "cudaMalloc planner receiver 0441");
    cuda_check0441(cudaMalloc(reinterpret_cast<void**>(&d_outMass), sizeof(double) * static_cast<std::size_t>(maxPlanEntries)), "cudaMalloc planner mass 0441");
    cuda_check0441(cudaMalloc(reinterpret_cast<void**>(&d_outDistance), sizeof(double) * static_cast<std::size_t>(maxPlanEntries)), "cudaMalloc planner distance 0441");
    cuda_check0441(cudaMalloc(reinterpret_cast<void**>(&d_outDonorRemainingAfter), sizeof(double) * static_cast<std::size_t>(maxPlanEntries)), "cudaMalloc planner donor rem 0441");
    cuda_check0441(cudaMalloc(reinterpret_cast<void**>(&d_outReceiverRemainingAfter), sizeof(double) * static_cast<std::size_t>(maxPlanEntries)), "cudaMalloc planner receiver rem 0441");
    cuda_check0441(cudaMalloc(reinterpret_cast<void**>(&d_count), sizeof(unsigned int)), "cudaMalloc planner count 0441");
    cuda_check0441(cudaMalloc(reinterpret_cast<void**>(&d_plannedMass), sizeof(double)), "cudaMalloc planner plannedMass 0441");
    cuda_check0441(cudaMalloc(reinterpret_cast<void**>(&d_remainingReceiver), sizeof(double)), "cudaMalloc planner remainingReceiver 0441");
    cuda_check0441(cudaMalloc(reinterpret_cast<void**>(&d_remainingDonor), sizeof(double)), "cudaMalloc planner remainingDonor 0441");
    cuda_check0441(cudaMalloc(reinterpret_cast<void**>(&d_adjacentPairs), sizeof(unsigned int)), "cudaMalloc planner adjacentPairs 0441");
    cuda_check0441(cudaMemcpy(d_mass, cellMass.data(), sizeof(double) * static_cast<std::size_t>(numCells), cudaMemcpyHostToDevice), "copy planner mass H2D 0441");
    cuda_check0441(cudaMemcpy(d_poor, poorCells.data(), sizeof(int) * static_cast<std::size_t>(poorCount), cudaMemcpyHostToDevice), "copy planner poor H2D 0441");
    cuda_check0441(cudaMemcpy(d_rich, richCells.data(), sizeof(int) * static_cast<std::size_t>(richCount), cudaMemcpyHostToDevice), "copy planner rich H2D 0441");
    cuda_check0441(cudaMemset(d_count, 0, sizeof(unsigned int)), "memset planner count 0441");

    const auto k0 = Clock0441::now();
    build_transfer_plan_serial_kernel_0441<<<1, 1>>>(nx, ny, xPeriodic ? 1 : 0, yPeriodic ? 1 : 0,
                                                     targetCellMass, poorCount, richCount, d_poor, d_rich,
                                                     d_receiverRemaining, d_donorRemaining, d_mass, maxPlanEntries, d_outDonor, d_outReceiver,
                                                     d_outMass, d_outDistance, d_outDonorRemainingAfter,
                                                     d_outReceiverRemainingAfter, d_count, d_plannedMass,
                                                     d_remainingReceiver, d_remainingDonor, d_adjacentPairs);
    cuda_check0441(cudaGetLastError(), "launch build_transfer_plan_serial_kernel_0441");
    cuda_check0441(cudaDeviceSynchronize(), "sync build_transfer_plan_serial_kernel_0441");
    const auto k1 = Clock0441::now();

    unsigned int h_count = 0u;
    cuda_check0441(cudaMemcpy(&h_count, d_count, sizeof(unsigned int), cudaMemcpyDeviceToHost), "copy planner count D2H 0441");
    if (h_count > static_cast<unsigned int>(maxPlanEntries)) {
        throw std::runtime_error("planner 0441 produced more entries than allocated");
    }
    std::vector<int> h_donor(h_count, -1);
    std::vector<int> h_receiver(h_count, -1);
    std::vector<double> h_mass(h_count, 0.0);
    std::vector<double> h_distance(h_count, 0.0);
    std::vector<double> h_donorRem(h_count, 0.0);
    std::vector<double> h_receiverRem(h_count, 0.0);
    if (h_count > 0u) {
        cuda_check0441(cudaMemcpy(h_donor.data(), d_outDonor, sizeof(int) * h_count, cudaMemcpyDeviceToHost), "copy planner donor D2H 0441");
        cuda_check0441(cudaMemcpy(h_receiver.data(), d_outReceiver, sizeof(int) * h_count, cudaMemcpyDeviceToHost), "copy planner receiver D2H 0441");
        cuda_check0441(cudaMemcpy(h_mass.data(), d_outMass, sizeof(double) * h_count, cudaMemcpyDeviceToHost), "copy planner mass D2H 0441");
        cuda_check0441(cudaMemcpy(h_distance.data(), d_outDistance, sizeof(double) * h_count, cudaMemcpyDeviceToHost), "copy planner distance D2H 0441");
        cuda_check0441(cudaMemcpy(h_donorRem.data(), d_outDonorRemainingAfter, sizeof(double) * h_count, cudaMemcpyDeviceToHost), "copy planner donorRem D2H 0441");
        cuda_check0441(cudaMemcpy(h_receiverRem.data(), d_outReceiverRemainingAfter, sizeof(double) * h_count, cudaMemcpyDeviceToHost), "copy planner receiverRem D2H 0441");
    }
    unsigned int h_adjacent = 0u;
    cuda_check0441(cudaMemcpy(&out.plannedMass, d_plannedMass, sizeof(double), cudaMemcpyDeviceToHost), "copy plannedMass D2H 0441");
    cuda_check0441(cudaMemcpy(&out.remainingReceiver, d_remainingReceiver, sizeof(double), cudaMemcpyDeviceToHost), "copy remainingReceiver D2H 0441");
    cuda_check0441(cudaMemcpy(&out.remainingDonor, d_remainingDonor, sizeof(double), cudaMemcpyDeviceToHost), "copy remainingDonor D2H 0441");
    cuda_check0441(cudaMemcpy(&h_adjacent, d_adjacentPairs, sizeof(unsigned int), cudaMemcpyDeviceToHost), "copy adjacentPairs D2H 0441");
    out.adjacentPairs = h_adjacent;
    out.entries.resize(h_count);
    for (unsigned int i = 0u; i < h_count; ++i) {
        out.entries[i] = TransferPlanEntry0441{h_donor[i], h_receiver[i], h_mass[i], h_distance[i], h_donorRem[i], h_receiverRem[i]};
    }

    cudaFree(d_mass); cudaFree(d_poor); cudaFree(d_rich); cudaFree(d_receiverRemaining); cudaFree(d_donorRemaining);
    cudaFree(d_outDonor); cudaFree(d_outReceiver); cudaFree(d_outMass); cudaFree(d_outDistance);
    cudaFree(d_outDonorRemainingAfter); cudaFree(d_outReceiverRemainingAfter);
    cudaFree(d_count); cudaFree(d_plannedMass); cudaFree(d_remainingReceiver); cudaFree(d_remainingDonor); cudaFree(d_adjacentPairs);
    const auto t1 = Clock0441::now();
    out.kernelSeconds = seconds_between0441(k0, k1);
    out.totalSeconds = seconds_between0441(t0, t1);
    return out;
}

struct GpuDerivedDeposit0441 {
    std::uint64_t nFluid = 0u;
    std::uint64_t nCells = 0u;
    std::uint64_t nonEmpty = 0u;
    std::uint64_t empty = 0u;
    std::uint64_t poor = 0u;
    std::uint64_t rich = 0u;
    std::uint64_t targetBand = 0u;
    std::uint64_t emptyWet = 0u;
    double totalMass = 0.0;
    double totalPx = 0.0;
    double totalPy = 0.0;
    double targetCellMass = 0.0;
    double mRelMaxAbs = 0.0;
};

mpcd::SimulationParams make_params(int nx, int ny, int gamma) {
    mpcd::SimulationParams p{};
    p.Nx = nx;
    p.Ny = ny;
    p.Lx = static_cast<double>(nx);
    p.Ly = static_cast<double>(ny);
    p.dt = 1.0e-3;
    p.bcLeft = "periodic";
    p.bcRight = "periodic";
    p.bcBottom = "periodic";
    p.bcTop = "periodic";
    p.gridShiftEnable = true;
    p.resamplingTargetCellMass = static_cast<double>(gamma);
    p.resamplingWetMaskMode = "active_domain";
    p.resamplingWetCellMassThreshold = 0.0;
    p.resamplingPoorCellMassFraction = 0.5;
    p.resamplingRichCellMassFraction = 1.5;
    p.resamplingActiveFluidFractionThreshold = 0.5;
    p.resamplingEnable = true;
    p.resamplingExtractionEnable = true;
    p.resamplingInsertionEnable = true;
    p.resamplingRemapEnable = false;
    p.resamplingThermalRenormalizationEnable = false;
    return p;
}

mpcd::ParticleState make_periodic_state(const mpcd::SimulationParams& params,
                                        int gamma,
                                        std::uint64_t inactiveSlots,
                                        std::uint64_t seed,
                                        const std::string& caseName,
                                        const std::string& massMode) {
    if (params.Nx <= 0 || params.Ny <= 0 || gamma <= 0) {
        throw std::runtime_error("invalid synthetic state dimensions");
    }
    const std::uint64_t nFluid = static_cast<std::uint64_t>(params.Nx) *
                                 static_cast<std::uint64_t>(params.Ny) *
                                 static_cast<std::uint64_t>(gamma);
    const std::uint64_t nTotal = nFluid + inactiveSlots;
    mpcd::ParticleState s{};
    s.Np = nTotal;
    s.NactiveFluid = nFluid;
    s.dim = 2u;
    s.x.assign(static_cast<std::size_t>(nTotal), 0.0);
    s.y.assign(static_cast<std::size_t>(nTotal), 0.0);
    s.vx.assign(static_cast<std::size_t>(nTotal), 0.0);
    s.vy.assign(static_cast<std::size_t>(nTotal), 0.0);
    s.mass.assign(static_cast<std::size_t>(nTotal), 1.0);
    s.type.assign(static_cast<std::size_t>(nTotal), 0u);
    s.role.assign(static_cast<std::size_t>(nTotal), mpcd::kParticleRoleInactive);

    std::mt19937_64 rng(seed);
    std::uniform_real_distribution<double> unit(0.0, 1.0);
    std::normal_distribution<double> thermal(0.0, 0.015);

    const double pi = std::acos(-1.0);
    const double kx = 2.0 * pi / params.Lx;
    const double ky = 2.0 * pi / params.Ly;
    const double amp = 0.04;

    std::uint64_t i = 0u;
    for (int iy = 0; iy < params.Ny; ++iy) {
        for (int ix = 0; ix < params.Nx; ++ix) {
            for (int g = 0; g < gamma; ++g) {
                const double xr = (static_cast<double>(ix) + unit(rng)) * (params.Lx / params.Nx);
                const double yr = (static_cast<double>(iy) + unit(rng)) * (params.Ly / params.Ny);
                s.x[static_cast<std::size_t>(i)] = xr;
                s.y[static_cast<std::size_t>(i)] = yr;
                if (caseName == "tg") {
                    s.vx[static_cast<std::size_t>(i)] = amp * std::sin(kx * xr) * std::cos(ky * yr) + thermal(rng);
                    s.vy[static_cast<std::size_t>(i)] = -amp * std::cos(kx * xr) * std::sin(ky * yr) + thermal(rng);
                } else {
                    s.vx[static_cast<std::size_t>(i)] = amp * std::sin(ky * yr) + thermal(rng);
                    s.vy[static_cast<std::size_t>(i)] = thermal(rng);
                }
                if (massMode == "vary") {
                    const double a = 0.08 * std::sin(0.137 * static_cast<double>(i)) +
                                     0.03 * std::cos(0.071 * static_cast<double>(ix + 3 * iy + g));
                    s.mass[static_cast<std::size_t>(i)] = 1.0 + a;
                }
                s.role[static_cast<std::size_t>(i)] = mpcd::kParticleRoleFluid;
                ++i;
            }
        }
    }

    for (; i < nTotal; ++i) {
        const std::size_t k = static_cast<std::size_t>(i);
        s.x[k] = 0.0;
        s.y[k] = 0.0;
        s.vx[k] = 0.0;
        s.vy[k] = 0.0;
        s.mass[k] = 1.0;
        s.role[k] = mpcd::kParticleRoleInactive;
    }
    mpcd::validate_particle_state(s, "make_periodic_state_0441");
    mpcd::validate_active_fluid_prefix(s, "make_periodic_state_0441");
    return s;
}

GpuDerivedDeposit0441 derive_gpu_diagnostics(const mpcd::CudaCellMoments& gpu,
                                             const mpcd::SimulationParams& params,
                                             const mpcd::CellGrid& grid,
                                             std::uint64_t nFluid) {
    GpuDerivedDeposit0441 d{};
    d.nFluid = nFluid;
    d.nCells = static_cast<std::uint64_t>(grid.numCells);
    d.targetCellMass = params.resamplingTargetCellMass;
    for (int c = 0; c < grid.numCells; ++c) {
        const std::size_t k = static_cast<std::size_t>(c);
        const double m = gpu.cellMass[k];
        d.totalMass += m;
        d.totalPx += gpu.cellPx[k];
        d.totalPy += gpu.cellPy[k];
        if (gpu.cellCount[k] > 0u) ++d.nonEmpty;
    }
    d.empty = d.nCells - d.nonEmpty;
    if (!(d.targetCellMass > 0.0) && d.nCells > 0u) {
        d.targetCellMass = d.totalMass / static_cast<double>(d.nCells);
    }
    const double poorThreshold = d.targetCellMass * params.resamplingPoorCellMassFraction;
    const double richThreshold = d.targetCellMass * params.resamplingRichCellMassFraction;
    if (d.targetCellMass > 0.0) {
        for (int c = 0; c < grid.numCells; ++c) {
            const std::size_t k = static_cast<std::size_t>(c);
            const double m = gpu.cellMass[k];
            const bool poor = m < poorThreshold;
            const bool rich = m > richThreshold;
            d.poor += poor ? 1u : 0u;
            d.rich += rich ? 1u : 0u;
            d.targetBand += (!poor && !rich) ? 1u : 0u;
            d.emptyWet += gpu.cellCount[k] == 0u ? 1u : 0u;
            d.mRelMaxAbs = std::max(d.mRelMaxAbs, std::abs((m - d.targetCellMass) / d.targetCellMass));
        }
    }
    return d;
}

struct CompareResult0441 {
    std::string caseName;
    std::string massMode;
    double shiftX = 0.0;
    double shiftY = 0.0;
    int pass = 0;
    std::uint64_t n = 0u;
    int cells = 0;
    double maxCountDiff = 0.0;
    double maxMassAbs = 0.0;
    double maxPxAbs = 0.0;
    double maxPyAbs = 0.0;
    double maxUxAbs = 0.0;
    double maxUyAbs = 0.0;
    std::uint64_t cellIdMismatch = 0u;
    std::uint64_t poorCpu = 0u;
    std::uint64_t poorGpu = 0u;
    std::uint64_t richCpu = 0u;
    std::uint64_t richGpu = 0u;
    double cpuTotalMass = 0.0;
    double gpuTotalMass = 0.0;
    double cpuTotalPx = 0.0;
    double gpuTotalPx = 0.0;
    double cpuTotalPy = 0.0;
    double gpuTotalPy = 0.0;
    double depositKernelSeconds = 0.0;
    double depositDownloadSeconds = 0.0;
    double depositTotalSeconds = 0.0;
    std::uint64_t poorListMismatch = 0u;
    std::uint64_t richListMismatch = 0u;
    double compactKernelSeconds = 0.0;
    double compactTotalSeconds = 0.0;
    std::uint64_t cpuPlanEntries = 0u;
    std::uint64_t gpuPlanEntries = 0u;
    std::uint64_t planEntryMismatch = 0u;
    double maxPlanMassAbs = 0.0;
    double maxPlanDistanceAbs = 0.0;
    double maxPlanDonorRemainingAbs = 0.0;
    double maxPlanReceiverRemainingAbs = 0.0;
    double cpuPlannedMass = 0.0;
    double gpuPlannedMass = 0.0;
    double cpuRemainingReceiver = 0.0;
    double gpuRemainingReceiver = 0.0;
    double cpuRemainingDonor = 0.0;
    double gpuRemainingDonor = 0.0;
    std::uint64_t cpuAdjacentPairs = 0u;
    std::uint64_t gpuAdjacentPairs = 0u;
    double plannerKernelSeconds = 0.0;
    double plannerTotalSeconds = 0.0;
};

CompareResult0441 run_one(const std::string& caseName,
                          const std::string& massMode,
                          int nx,
                          int ny,
                          int gamma,
                          std::uint64_t inactiveSlots,
                          std::uint64_t seed,
                          double sxFrac,
                          double syFrac,
                          double tolAbs,
                          double tolRel) {
    mpcd::SimulationParams params = make_params(nx, ny, gamma);
    mpcd::CellGrid grid = mpcd::make_cell_grid(params);
    mpcd::GridShift shift{sxFrac * grid.dx, syFrac * grid.dy};
    mpcd::FluidDomainBounds domain = mpcd::make_fluid_domain_bounds(params, 0.0);
    mpcd::ParticleState state = make_periodic_state(params, gamma, inactiveSlots, seed, caseName, massMode);

    mpcd::WeightedRealFluidDepositWorkspace cpuWs{};
    mpcd::WeightedResamplingDiagnostics cpu = mpcd::deposit_weighted_real_fluid(
        state, params, grid, domain, 0.0, shift, cpuWs, true,
        mpcd::ResamplingDepositProfileContext::Generic, false);

    mpcd::CudaParticleState gpuState{};
    mpcd::CudaParticleStateDiagnostics uploadDiag{};
    gpuState.upload_all(state, &uploadDiag);
    mpcd::CudaCellWorkspace cellWs{};
    mpcd::CudaCellMoments gpu{};
    mpcd::CudaCellMomentsDiagnostics gpuDiag{};
    mpcd::CudaCellMomentsOptions options{};
    options.computeCellVelocities = true;
    options.downloadCellVelocities = true;
    options.enableAllFluidFastPath = true;
    options.enableUniformMassFastPath = true;
    mpcd::cuda_deposit_cell_moments_atomic_from_persistent_state(
        state, gpuState, cellWs, grid, shift, params, gpu, &gpuDiag, options);


    const double targetCellMass = params.resamplingTargetCellMass > 0.0
        ? params.resamplingTargetCellMass
        : (static_cast<double>(state.NactiveFluid) / static_cast<double>(grid.numCells));
    const double poorThreshold = targetCellMass * params.resamplingPoorCellMassFraction;
    const double richThreshold = targetCellMass * params.resamplingRichCellMassFraction;
    GpuCompactedLists0441 compact = compact_poor_rich_gpu_0441(gpu.cellMass, poorThreshold, richThreshold, 256);
    GpuTransferPlan0441 gpuPlan = build_transfer_plan_gpu_0441(
        gpu.cellMass, compact.poor, compact.rich, grid.Nx, grid.Ny,
        mpcd::is_x_periodic(params), mpcd::is_y_periodic(params), targetCellMass);

    GpuDerivedDeposit0441 gd = derive_gpu_diagnostics(gpu, params, grid, state.NactiveFluid);

    CompareResult0441 r{};
    r.caseName = caseName;
    r.massMode = massMode;
    r.shiftX = shift.sx;
    r.shiftY = shift.sy;
    r.n = state.NactiveFluid;
    r.cells = grid.numCells;
    r.poorCpu = cpu.nPoorCells;
    r.poorGpu = gd.poor;
    r.richCpu = cpu.nRichCells;
    r.richGpu = gd.rich;
    r.cpuTotalMass = cpu.totalMass;
    r.gpuTotalMass = gd.totalMass;
    r.cpuTotalPx = cpu.totalPx;
    r.gpuTotalPx = gd.totalPx;
    r.cpuTotalPy = cpu.totalPy;
    r.gpuTotalPy = gd.totalPy;
    r.depositKernelSeconds = gpuDiag.kernelSeconds;
    r.depositDownloadSeconds = gpuDiag.downloadSeconds;
    r.depositTotalSeconds = gpuDiag.totalSeconds;
    r.compactKernelSeconds = compact.kernelSeconds;
    r.compactTotalSeconds = compact.totalSeconds;
    std::vector<int> cpuPoor(cpuWs.receiverPoorCells.begin(), cpuWs.receiverPoorCells.end());
    std::vector<int> cpuRich(cpuWs.donorRichCells.begin(), cpuWs.donorRichCells.end());
    std::sort(cpuPoor.begin(), cpuPoor.end());
    std::sort(cpuRich.begin(), cpuRich.end());
    r.poorListMismatch = sorted_list_mismatch0441(cpuPoor, compact.poor);
    r.richListMismatch = sorted_list_mismatch0441(cpuRich, compact.rich);
    r.cpuPlanEntries = static_cast<std::uint64_t>(cpuWs.transferPlan.size());
    r.gpuPlanEntries = static_cast<std::uint64_t>(gpuPlan.entries.size());
    r.cpuPlannedMass = cpu.plannedTransferMass;
    r.gpuPlannedMass = gpuPlan.plannedMass;
    r.cpuRemainingReceiver = cpu.remainingReceiverDeficitAfterPlan;
    r.gpuRemainingReceiver = gpuPlan.remainingReceiver;
    r.cpuRemainingDonor = cpu.remainingDonorExcessAfterPlan;
    r.gpuRemainingDonor = gpuPlan.remainingDonor;
    r.cpuAdjacentPairs = cpu.nAdjacentTransferPairs;
    r.gpuAdjacentPairs = gpuPlan.adjacentPairs;
    r.plannerKernelSeconds = gpuPlan.kernelSeconds;
    r.plannerTotalSeconds = gpuPlan.totalSeconds;
    const std::size_t planCompareN = std::min(cpuWs.transferPlan.size(), gpuPlan.entries.size());
    r.planEntryMismatch = static_cast<std::uint64_t>(std::max(cpuWs.transferPlan.size(), gpuPlan.entries.size()) - planCompareN);
    for (std::size_t ip = 0; ip < planCompareN; ++ip) {
        const auto& a = cpuWs.transferPlan[ip];
        const auto& b = gpuPlan.entries[ip];
        if (a.donorCell != b.donorCell || a.receiverCell != b.receiverCell) {
            ++r.planEntryMismatch;
        }
        r.maxPlanMassAbs = std::max(r.maxPlanMassAbs, std::abs(a.plannedMass - b.plannedMass));
        r.maxPlanDistanceAbs = std::max(r.maxPlanDistanceAbs, std::abs(a.cellDistance - b.cellDistance));
        r.maxPlanDonorRemainingAbs = std::max(r.maxPlanDonorRemainingAbs, std::abs(a.donorRemainingAfter - b.donorRemainingAfter));
        r.maxPlanReceiverRemainingAbs = std::max(r.maxPlanReceiverRemainingAbs, std::abs(a.receiverRemainingAfter - b.receiverRemainingAfter));
    }

    for (std::size_t i = 0; i < cpuWs.cellId.size(); ++i) {
        if (i >= gpu.cellId.size() || cpuWs.cellId[i] != gpu.cellId[i]) {
            ++r.cellIdMismatch;
        }
    }
    for (int c = 0; c < grid.numCells; ++c) {
        const std::size_t k = static_cast<std::size_t>(c);
        r.maxCountDiff = std::max(r.maxCountDiff, std::abs(static_cast<double>(cpuWs.count[k]) - static_cast<double>(gpu.cellCount[k])));
        r.maxMassAbs = std::max(r.maxMassAbs, std::abs(cpuWs.mass[k] - gpu.cellMass[k]));
        r.maxPxAbs = std::max(r.maxPxAbs, std::abs(cpuWs.px[k] - gpu.cellPx[k]));
        r.maxPyAbs = std::max(r.maxPyAbs, std::abs(cpuWs.py[k] - gpu.cellPy[k]));
        r.maxUxAbs = std::max(r.maxUxAbs, std::abs(cpuWs.ux[k] - gpu.cellUx[k]));
        r.maxUyAbs = std::max(r.maxUyAbs, std::abs(cpuWs.uy[k] - gpu.cellUy[k]));
    }

    auto ok_close = [&](double a, double b) {
        const double scale = std::max({1.0, std::abs(a), std::abs(b)});
        return std::abs(a - b) <= tolAbs + tolRel * scale;
    };
    bool pass = true;
    pass = pass && (r.cellIdMismatch == 0u);
    pass = pass && (r.maxCountDiff == 0.0);
    pass = pass && (r.poorCpu == r.poorGpu);
    pass = pass && (r.richCpu == r.richGpu);
    pass = pass && (r.poorListMismatch == 0u);
    pass = pass && (r.richListMismatch == 0u);
    pass = pass && (r.cpuPlanEntries == r.gpuPlanEntries);
    pass = pass && (r.planEntryMismatch == 0u);
    pass = pass && (r.cpuAdjacentPairs == r.gpuAdjacentPairs);
    pass = pass && ok_close(r.cpuPlannedMass, r.gpuPlannedMass);
    pass = pass && ok_close(r.cpuRemainingReceiver, r.gpuRemainingReceiver);
    pass = pass && ok_close(r.cpuRemainingDonor, r.gpuRemainingDonor);
    pass = pass && (r.maxPlanMassAbs <= tolAbs + tolRel * std::max(1.0, std::abs(r.cpuPlannedMass)));
    pass = pass && (r.maxPlanDistanceAbs <= 1.0e-14);
    pass = pass && (r.maxPlanDonorRemainingAbs <= tolAbs + tolRel * std::max(1.0, std::abs(r.cpuPlannedMass)));
    pass = pass && (r.maxPlanReceiverRemainingAbs <= tolAbs + tolRel * std::max(1.0, std::abs(r.cpuPlannedMass)));
    pass = pass && ok_close(r.cpuTotalMass, r.gpuTotalMass);
    pass = pass && ok_close(r.cpuTotalPx, r.gpuTotalPx);
    pass = pass && ok_close(r.cpuTotalPy, r.gpuTotalPy);
    pass = pass && (r.maxMassAbs <= tolAbs + tolRel * std::max(1.0, std::abs(cpu.maxMass)));
    pass = pass && (r.maxPxAbs <= tolAbs + tolRel * std::max(1.0, std::abs(cpu.totalPx)));
    pass = pass && (r.maxPyAbs <= tolAbs + tolRel * std::max(1.0, std::abs(cpu.totalPy)));
    pass = pass && (r.maxUxAbs <= 5.0 * (tolAbs + tolRel));
    pass = pass && (r.maxUyAbs <= 5.0 * (tolAbs + tolRel));
    r.pass = pass ? 1 : 0;
    return r;
}

void print_csv_header() {
    std::cout << "case,massMode,shiftX,shiftY,pass,n,cells,cellIdMismatch,maxCountDiff,maxMassAbs,maxPxAbs,maxPyAbs,maxUxAbs,maxUyAbs,poorCpu,poorGpu,poorListMismatch,richCpu,richGpu,richListMismatch,cpuPlanEntries,gpuPlanEntries,planEntryMismatch,maxPlanMassAbs,maxPlanDistanceAbs,maxPlanDonorRemainingAbs,maxPlanReceiverRemainingAbs,cpuPlannedMass,gpuPlannedMass,cpuRemainingReceiver,gpuRemainingReceiver,cpuRemainingDonor,gpuRemainingDonor,cpuAdjacentPairs,gpuAdjacentPairs,cpuTotalMass,gpuTotalMass,cpuTotalPx,gpuTotalPx,cpuTotalPy,gpuTotalPy,depositKernelSeconds,depositDownloadSeconds,depositTotalSeconds,compactKernelSeconds,compactTotalSeconds,plannerKernelSeconds,plannerTotalSeconds\n";
}

void print_csv_row(const CompareResult0441& r) {
    std::cout << std::setprecision(17)
              << r.caseName << ',' << r.massMode << ',' << r.shiftX << ',' << r.shiftY << ','
              << r.pass << ',' << r.n << ',' << r.cells << ',' << r.cellIdMismatch << ','
              << r.maxCountDiff << ',' << r.maxMassAbs << ',' << r.maxPxAbs << ',' << r.maxPyAbs << ','
              << r.maxUxAbs << ',' << r.maxUyAbs << ',' << r.poorCpu << ',' << r.poorGpu << ','
              << r.poorListMismatch << ',' << r.richCpu << ',' << r.richGpu << ',' << r.richListMismatch << ','
              << r.cpuPlanEntries << ',' << r.gpuPlanEntries << ',' << r.planEntryMismatch << ','
              << r.maxPlanMassAbs << ',' << r.maxPlanDistanceAbs << ','
              << r.maxPlanDonorRemainingAbs << ',' << r.maxPlanReceiverRemainingAbs << ','
              << r.cpuPlannedMass << ',' << r.gpuPlannedMass << ','
              << r.cpuRemainingReceiver << ',' << r.gpuRemainingReceiver << ','
              << r.cpuRemainingDonor << ',' << r.gpuRemainingDonor << ','
              << r.cpuAdjacentPairs << ',' << r.gpuAdjacentPairs << ','
              << r.cpuTotalMass << ',' << r.gpuTotalMass << ','
              << r.cpuTotalPx << ',' << r.gpuTotalPx << ',' << r.cpuTotalPy << ',' << r.gpuTotalPy << ','
              << r.depositKernelSeconds << ',' << r.depositDownloadSeconds << ',' << r.depositTotalSeconds << ','
              << r.compactKernelSeconds << ',' << r.compactTotalSeconds << ','
              << r.plannerKernelSeconds << ',' << r.plannerTotalSeconds << '\n';
}

} // namespace

int main() {
    try {
        if (!mpcd::cuda_particle_state_available() || !mpcd::cuda_cell_moments_available()) {
            std::cerr << "CUDA_RESAMPLING_PLANNER_SHADOW_0441 FAIL cuda unavailable\n";
            return 2;
        }
        const int nx = env_int("NX", 64);
        const int ny = env_int("NY", 32);
        const int gamma = env_int("GAMMA", 20);
        const std::uint64_t inactive = env_u64("INACTIVE_SLOTS", 1024u);
        const std::uint64_t seed = env_u64("SEED", 1628638u);
        const double tolAbs = env_double("TOL_ABS", 2.0e-10);
        const double tolRel = env_double("TOL_REL", 2.0e-12);

        std::vector<CompareResult0441> rows;
        rows.push_back(run_one("shear", "uniform", nx, ny, gamma, inactive, seed, 0.0, 0.0, tolAbs, tolRel));
        rows.push_back(run_one("shear", "uniform", nx, ny, gamma, inactive, seed + 1u, 0.37, 0.23, tolAbs, tolRel));
        rows.push_back(run_one("tg", "vary", nx, ny, gamma, inactive, seed + 2u, 0.0, 0.0, tolAbs, tolRel));
        rows.push_back(run_one("tg", "vary", nx, ny, gamma, inactive, seed + 3u, 0.37, 0.23, tolAbs, tolRel));

        print_csv_header();
        int passCount = 0;
        for (const auto& r : rows) {
            print_csv_row(r);
            passCount += r.pass ? 1 : 0;
        }
        std::cerr << "CUDA_RESAMPLING_PLANNER_SHADOW_0441 "
                  << (passCount == static_cast<int>(rows.size()) ? "PASS" : "FAIL")
                  << " cases=" << passCount << "/" << rows.size()
                  << " nx=" << nx << " ny=" << ny << " gamma=" << gamma << "\n";
        return passCount == static_cast<int>(rows.size()) ? 0 : 1;
    } catch (const std::exception& e) {
        std::cerr << "CUDA_RESAMPLING_PLANNER_SHADOW_0441 EXCEPTION " << e.what() << "\n";
        return 3;
    }
}
