#include "cuda_resampling_particle_ops.h"

#include <cuda_runtime.h>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <limits>
#include <stdexcept>
#include <string>

namespace mpcd {
namespace {

inline void check_cuda(cudaError_t err, const char* what) {
    if (err != cudaSuccess) {
        throw std::runtime_error(std::string("cuda_resampling_particle_ops: ") + what + ": " + cudaGetErrorString(err));
    }
}

using Clock = std::chrono::steady_clock;
inline double elapsed_seconds(const Clock::time_point& a, const Clock::time_point& b) {
    return std::chrono::duration<double>(b - a).count();
}

__global__ void reset_first_particle_kernel_0232(
    std::uint32_t* __restrict__ firstParticleByCell,
    std::uint32_t* __restrict__ eligibleCountByCell,
    int nCells,
    std::uint32_t invalidParticle)
{
    const int c = blockIdx.x * blockDim.x + threadIdx.x;
    if (c >= nCells) return;
    firstParticleByCell[c] = invalidParticle;
    eligibleCountByCell[c] = 0u;
}

__global__ void build_first_particle_by_cell_kernel_0232(
    const std::uint32_t* __restrict__ particleCell,
    const std::uint8_t* __restrict__ particleRole,
    int nParticles,
    int nCells,
    std::uint8_t fluidRole,
    std::uint32_t* __restrict__ firstParticleByCell,
    std::uint32_t* __restrict__ eligibleCountByCell)
{
    const int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= nParticles) return;
    if (particleRole[i] != fluidRole) return;
    const std::uint32_t c = particleCell[i];
    if (c >= static_cast<std::uint32_t>(nCells)) return;
    atomicAdd(&eligibleCountByCell[c], 1u);
    atomicMin(&firstParticleByCell[c], static_cast<std::uint32_t>(i));
}

__global__ void select_transfer_donor_particle_kernel_0232(
    const std::uint32_t* __restrict__ donorCell,
    const double* __restrict__ transferMass,
    int nTransfers,
    int nCells,
    const std::uint32_t* __restrict__ firstParticleByCell,
    const double* __restrict__ particleMass,
    std::uint32_t invalidParticle,
    std::uint32_t* __restrict__ selectedParticle,
    double* __restrict__ selectedMass)
{
    const int t = blockIdx.x * blockDim.x + threadIdx.x;
    if (t >= nTransfers) return;
    const std::uint32_t c = donorCell[t];
    (void)transferMass;
    std::uint32_t p = invalidParticle;
    double m = 0.0;
    if (c < static_cast<std::uint32_t>(nCells)) {
        p = firstParticleByCell[c];
        if (p != invalidParticle) m = particleMass[p];
    }
    selectedParticle[t] = p;
    selectedMass[t] = m;
}

} // namespace

bool cuda_resampling_select_donor_particles_0232(
    const std::vector<std::uint32_t>& particleCell,
    const std::vector<std::uint8_t>& particleRole,
    const std::vector<double>& particleMass,
    std::uint32_t nCells,
    const std::vector<std::uint32_t>& donorCell,
    const std::vector<double>& transferMass,
    const CudaResamplingParticleSelectParams& params,
    std::vector<std::uint32_t>& selectedParticle,
    std::vector<double>& selectedMass,
    std::vector<std::uint32_t>* eligibleCountByCell,
    CudaResamplingParticleSelectDiagnostics* diagnostics)
{
    if (particleCell.size() != particleRole.size() || particleCell.size() != particleMass.size()) {
        throw std::runtime_error("cuda_resampling_select_donor_particles_0232: particle array size mismatch");
    }
    if (donorCell.size() != transferMass.size()) {
        throw std::runtime_error("cuda_resampling_select_donor_particles_0232: donor/transfer size mismatch");
    }
    if (nCells == 0u && !donorCell.empty()) {
        throw std::runtime_error("cuda_resampling_select_donor_particles_0232: non-empty plan with zero cells");
    }

    const auto t0 = Clock::now();
    const int nParticles = static_cast<int>(particleCell.size());
    const int nTransfers = static_cast<int>(donorCell.size());
    const int nCellsInt = static_cast<int>(nCells);
    selectedParticle.assign(donorCell.size(), params.invalidParticle);
    selectedMass.assign(donorCell.size(), 0.0);
    if (eligibleCountByCell) eligibleCountByCell->assign(nCells, 0u);

    if (diagnostics) {
        *diagnostics = CudaResamplingParticleSelectDiagnostics{};
        diagnostics->attempted = true;
        diagnostics->particles = static_cast<std::uint64_t>(particleCell.size());
        diagnostics->cells = static_cast<std::uint64_t>(nCells);
        diagnostics->transfers = static_cast<std::uint64_t>(donorCell.size());
        for (double m : transferMass) {
            diagnostics->totalTransferMass += m;
            diagnostics->maxTransferMass = std::max(diagnostics->maxTransferMass, m);
        }
    }

    if (nParticles == 0 || nCells == 0u || nTransfers == 0) {
        if (diagnostics) diagnostics->applied = true;
        return true;
    }

    std::uint32_t* d_particleCell = nullptr;
    std::uint8_t* d_particleRole = nullptr;
    double* d_particleMass = nullptr;
    std::uint32_t* d_donorCell = nullptr;
    double* d_transferMass = nullptr;
    std::uint32_t* d_firstParticleByCell = nullptr;
    std::uint32_t* d_eligibleCountByCell = nullptr;
    std::uint32_t* d_selectedParticle = nullptr;
    double* d_selectedMass = nullptr;

    const std::size_t nParticleCellBytes = particleCell.size() * sizeof(std::uint32_t);
    const std::size_t nParticleRoleBytes = particleRole.size() * sizeof(std::uint8_t);
    const std::size_t nParticleMassBytes = particleMass.size() * sizeof(double);
    const std::size_t nTransferCellBytes = donorCell.size() * sizeof(std::uint32_t);
    const std::size_t nTransferMassBytes = transferMass.size() * sizeof(double);
    const std::size_t nCellU32Bytes = static_cast<std::size_t>(nCells) * sizeof(std::uint32_t);

    check_cuda(cudaMalloc(&d_particleCell, nParticleCellBytes), "malloc particleCell");
    check_cuda(cudaMalloc(&d_particleRole, nParticleRoleBytes), "malloc particleRole");
    check_cuda(cudaMalloc(&d_particleMass, nParticleMassBytes), "malloc particleMass");
    check_cuda(cudaMalloc(&d_donorCell, nTransferCellBytes), "malloc donorCell");
    check_cuda(cudaMalloc(&d_transferMass, nTransferMassBytes), "malloc transferMass");
    check_cuda(cudaMalloc(&d_firstParticleByCell, nCellU32Bytes), "malloc firstParticleByCell");
    check_cuda(cudaMalloc(&d_eligibleCountByCell, nCellU32Bytes), "malloc eligibleCountByCell");
    check_cuda(cudaMalloc(&d_selectedParticle, nTransferCellBytes), "malloc selectedParticle");
    check_cuda(cudaMalloc(&d_selectedMass, nTransferMassBytes), "malloc selectedMass");

    const auto tu0 = Clock::now();
    check_cuda(cudaMemcpy(d_particleCell, particleCell.data(), nParticleCellBytes, cudaMemcpyHostToDevice), "copy particleCell");
    check_cuda(cudaMemcpy(d_particleRole, particleRole.data(), nParticleRoleBytes, cudaMemcpyHostToDevice), "copy particleRole");
    check_cuda(cudaMemcpy(d_particleMass, particleMass.data(), nParticleMassBytes, cudaMemcpyHostToDevice), "copy particleMass");
    check_cuda(cudaMemcpy(d_donorCell, donorCell.data(), nTransferCellBytes, cudaMemcpyHostToDevice), "copy donorCell");
    check_cuda(cudaMemcpy(d_transferMass, transferMass.data(), nTransferMassBytes, cudaMemcpyHostToDevice), "copy transferMass");
    const auto tu1 = Clock::now();

    cudaEvent_t ev0{}, ev1{};
    check_cuda(cudaEventCreate(&ev0), "event create 0");
    check_cuda(cudaEventCreate(&ev1), "event create 1");
    check_cuda(cudaEventRecord(ev0), "event record 0");

    const int threads = 256;
    const int cellBlocks = (nCellsInt + threads - 1) / threads;
    const int particleBlocks = (nParticles + threads - 1) / threads;
    const int transferBlocks = (nTransfers + threads - 1) / threads;

    reset_first_particle_kernel_0232<<<cellBlocks, threads>>>(
        d_firstParticleByCell, d_eligibleCountByCell, nCellsInt, params.invalidParticle);
    check_cuda(cudaGetLastError(), "launch reset first particle");
    build_first_particle_by_cell_kernel_0232<<<particleBlocks, threads>>>(
        d_particleCell, d_particleRole, nParticles, nCellsInt, params.fluidRole,
        d_firstParticleByCell, d_eligibleCountByCell);
    check_cuda(cudaGetLastError(), "launch build first particle");
    select_transfer_donor_particle_kernel_0232<<<transferBlocks, threads>>>(
        d_donorCell, d_transferMass, nTransfers, nCellsInt, d_firstParticleByCell,
        d_particleMass, params.invalidParticle, d_selectedParticle, d_selectedMass);
    check_cuda(cudaGetLastError(), "launch select transfer donor particle");

    check_cuda(cudaEventRecord(ev1), "event record 1");
    check_cuda(cudaEventSynchronize(ev1), "event sync 1");
    float kernelMs = 0.0f;
    check_cuda(cudaEventElapsedTime(&kernelMs, ev0, ev1), "event elapsed");
    check_cuda(cudaEventDestroy(ev0), "event destroy 0");
    check_cuda(cudaEventDestroy(ev1), "event destroy 1");

    const auto td0 = Clock::now();
    check_cuda(cudaMemcpy(selectedParticle.data(), d_selectedParticle, nTransferCellBytes, cudaMemcpyDeviceToHost), "copy selectedParticle");
    check_cuda(cudaMemcpy(selectedMass.data(), d_selectedMass, nTransferMassBytes, cudaMemcpyDeviceToHost), "copy selectedMass");
    if (eligibleCountByCell) {
        check_cuda(cudaMemcpy(eligibleCountByCell->data(), d_eligibleCountByCell, nCellU32Bytes, cudaMemcpyDeviceToHost), "copy eligibleCountByCell");
    }
    const auto td1 = Clock::now();

    if (diagnostics) {
        diagnostics->applied = true;
        diagnostics->kernelSeconds = static_cast<double>(kernelMs) * 1.0e-3;
        diagnostics->uploadSeconds = elapsed_seconds(tu0, tu1);
        diagnostics->downloadSeconds = elapsed_seconds(td0, td1);
        diagnostics->selectedTransfers = 0u;
        diagnostics->missingDonorParticleTransfers = 0u;
        for (std::uint32_t p : selectedParticle) {
            if (p == params.invalidParticle) ++diagnostics->missingDonorParticleTransfers;
            else ++diagnostics->selectedTransfers;
        }
        if (eligibleCountByCell) {
            for (std::uint32_t n : *eligibleCountByCell) {
                if (n > 0u) ++diagnostics->donorCellsWithEligibleParticles;
            }
        }
    }

    cudaFree(d_particleCell);
    cudaFree(d_particleRole);
    cudaFree(d_particleMass);
    cudaFree(d_donorCell);
    cudaFree(d_transferMass);
    cudaFree(d_firstParticleByCell);
    cudaFree(d_eligibleCountByCell);
    cudaFree(d_selectedParticle);
    cudaFree(d_selectedMass);

    if (diagnostics) diagnostics->totalSeconds = elapsed_seconds(t0, Clock::now());
    return true;
}

} // namespace mpcd
