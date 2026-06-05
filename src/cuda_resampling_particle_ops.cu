#include "cuda_resampling_particle_ops.h"

#include <cuda_runtime.h>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <limits>
#include <stdexcept>
#include <string>
#include <unordered_set>

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


namespace {

__global__ void apply_shadow_transfer_kernel_0233(
    const std::uint32_t* __restrict__ receiverCell,
    const double* __restrict__ requestedTransferMass,
    const std::uint32_t* __restrict__ selectedDonorParticle,
    const std::uint32_t* __restrict__ insertionParticle,
    int nTransfers,
    int nParticles,
    std::uint8_t fluidRole,
    std::uint8_t insertionRole,
    std::uint32_t invalidParticle,
    double maxExtractFractionOfDonor,
    double minDonorMassAfterExtract,
    std::uint32_t* __restrict__ particleCell,
    std::uint8_t* __restrict__ particleRole,
    double* __restrict__ particleMass,
    double* __restrict__ particleVx,
    double* __restrict__ particleVy,
    double* __restrict__ actualTransferMass)
{
    const int t = blockIdx.x * blockDim.x + threadIdx.x;
    if (t >= nTransfers) return;

    actualTransferMass[t] = 0.0;
    const std::uint32_t p = selectedDonorParticle[t];
    const std::uint32_t q = insertionParticle[t];
    if (p == invalidParticle || q == invalidParticle) return;
    if (p >= static_cast<std::uint32_t>(nParticles) || q >= static_cast<std::uint32_t>(nParticles)) return;
    if (particleRole[p] != fluidRole) return;
    if (particleRole[q] != insertionRole) return;

    const double donorMass = particleMass[p];
    double dm = requestedTransferMass[t];
    if (!(dm > 0.0) || !(donorMass > minDonorMassAfterExtract)) return;
    if (maxExtractFractionOfDonor > 0.0 && maxExtractFractionOfDonor < 1.0) {
        dm = fmin(dm, maxExtractFractionOfDonor * donorMass);
    }
    dm = fmin(dm, donorMass - minDonorMassAfterExtract);
    if (!(dm > 0.0)) return;

    const double vx = particleVx[p];
    const double vy = particleVy[p];
    atomicAdd(&particleMass[p], -dm);
    atomicAdd(&particleMass[q], dm);
    particleCell[q] = receiverCell[t];
    particleRole[q] = fluidRole;
    particleVx[q] = vx;
    particleVy[q] = vy;
    actualTransferMass[t] = dm;
}

} // namespace

bool cuda_resampling_apply_shadow_transfers_0233(
    const std::vector<std::uint32_t>& particleCell,
    const std::vector<std::uint8_t>& particleRole,
    const std::vector<double>& particleMass,
    const std::vector<double>& particleVx,
    const std::vector<double>& particleVy,
    const std::vector<std::uint32_t>& receiverCell,
    const std::vector<double>& requestedTransferMass,
    const std::vector<std::uint32_t>& selectedDonorParticle,
    const std::vector<std::uint32_t>& insertionParticle,
    const CudaResamplingShadowTransferParams& params,
    std::vector<std::uint32_t>& outParticleCell,
    std::vector<std::uint8_t>& outParticleRole,
    std::vector<double>& outParticleMass,
    std::vector<double>& outParticleVx,
    std::vector<double>& outParticleVy,
    std::vector<double>* actualTransferMass,
    CudaResamplingShadowTransferDiagnostics* diagnostics)
{
    if (particleCell.size() != particleRole.size() || particleCell.size() != particleMass.size() ||
        particleCell.size() != particleVx.size() || particleCell.size() != particleVy.size()) {
        throw std::runtime_error("cuda_resampling_apply_shadow_transfers_0233: particle array size mismatch");
    }
    if (receiverCell.size() != requestedTransferMass.size() ||
        receiverCell.size() != selectedDonorParticle.size() ||
        receiverCell.size() != insertionParticle.size()) {
        throw std::runtime_error("cuda_resampling_apply_shadow_transfers_0233: transfer array size mismatch");
    }

    const auto t0 = Clock::now();
    const int nParticles = static_cast<int>(particleCell.size());
    const int nTransfers = static_cast<int>(receiverCell.size());

    outParticleCell = particleCell;
    outParticleRole = particleRole;
    outParticleMass = particleMass;
    outParticleVx = particleVx;
    outParticleVy = particleVy;
    if (actualTransferMass) actualTransferMass->assign(receiverCell.size(), 0.0);

    auto accumulate_state = [](const std::vector<double>& m, const std::vector<double>& vx, const std::vector<double>& vy,
                               double& mass, double& px, double& py) {
        mass = 0.0; px = 0.0; py = 0.0;
        for (std::size_t i = 0; i < m.size(); ++i) {
            mass += m[i];
            px += m[i] * vx[i];
            py += m[i] * vy[i];
        }
    };

    if (diagnostics) {
        *diagnostics = CudaResamplingShadowTransferDiagnostics{};
        diagnostics->attempted = true;
        diagnostics->particles = static_cast<std::uint64_t>(particleCell.size());
        diagnostics->transfers = static_cast<std::uint64_t>(receiverCell.size());
        for (double dm : requestedTransferMass) diagnostics->requestedTransferMass += dm;
        accumulate_state(particleMass, particleVx, particleVy,
                         diagnostics->totalMassBefore, diagnostics->totalPxBefore, diagnostics->totalPyBefore);

        std::unordered_set<std::uint32_t> donors;
        std::unordered_set<std::uint32_t> inserts;
        for (std::size_t t = 0; t < selectedDonorParticle.size(); ++t) {
            const std::uint32_t p = selectedDonorParticle[t];
            const std::uint32_t q = insertionParticle[t];
            if (p == params.invalidParticle || p >= particleCell.size()) ++diagnostics->invalidDonorTransfers;
            else if (particleRole[p] != params.fluidRole) ++diagnostics->donorRoleMismatchTransfers;
            else if (!donors.insert(p).second) ++diagnostics->duplicateDonorParticles;
            if (q == params.invalidParticle || q >= particleCell.size()) ++diagnostics->invalidInsertionTransfers;
            else if (particleRole[q] != params.insertionRole) ++diagnostics->insertionRoleMismatchTransfers;
            else if (!inserts.insert(q).second) ++diagnostics->duplicateInsertionParticles;
        }
    }

    if (nParticles == 0 || nTransfers == 0) {
        if (diagnostics) {
            diagnostics->applied = true;
            accumulate_state(outParticleMass, outParticleVx, outParticleVy,
                             diagnostics->totalMassAfter, diagnostics->totalPxAfter, diagnostics->totalPyAfter);
            diagnostics->totalSeconds = elapsed_seconds(t0, Clock::now());
        }
        return true;
    }

    std::uint32_t* d_cell = nullptr;
    std::uint8_t* d_role = nullptr;
    double* d_mass = nullptr;
    double* d_vx = nullptr;
    double* d_vy = nullptr;
    std::uint32_t* d_receiver = nullptr;
    double* d_requested = nullptr;
    std::uint32_t* d_selected = nullptr;
    std::uint32_t* d_insertion = nullptr;
    double* d_actual = nullptr;

    const std::size_t nU32ParticleBytes = particleCell.size() * sizeof(std::uint32_t);
    const std::size_t nU8ParticleBytes = particleRole.size() * sizeof(std::uint8_t);
    const std::size_t nDoubleParticleBytes = particleMass.size() * sizeof(double);
    const std::size_t nU32TransferBytes = receiverCell.size() * sizeof(std::uint32_t);
    const std::size_t nDoubleTransferBytes = requestedTransferMass.size() * sizeof(double);

    check_cuda(cudaMalloc(&d_cell, nU32ParticleBytes), "malloc transfer particleCell");
    check_cuda(cudaMalloc(&d_role, nU8ParticleBytes), "malloc transfer particleRole");
    check_cuda(cudaMalloc(&d_mass, nDoubleParticleBytes), "malloc transfer particleMass");
    check_cuda(cudaMalloc(&d_vx, nDoubleParticleBytes), "malloc transfer vx");
    check_cuda(cudaMalloc(&d_vy, nDoubleParticleBytes), "malloc transfer vy");
    check_cuda(cudaMalloc(&d_receiver, nU32TransferBytes), "malloc receiver");
    check_cuda(cudaMalloc(&d_requested, nDoubleTransferBytes), "malloc requested");
    check_cuda(cudaMalloc(&d_selected, nU32TransferBytes), "malloc selected");
    check_cuda(cudaMalloc(&d_insertion, nU32TransferBytes), "malloc insertion");
    check_cuda(cudaMalloc(&d_actual, nDoubleTransferBytes), "malloc actual");

    const auto tu0 = Clock::now();
    check_cuda(cudaMemcpy(d_cell, particleCell.data(), nU32ParticleBytes, cudaMemcpyHostToDevice), "copy transfer particleCell");
    check_cuda(cudaMemcpy(d_role, particleRole.data(), nU8ParticleBytes, cudaMemcpyHostToDevice), "copy transfer particleRole");
    check_cuda(cudaMemcpy(d_mass, particleMass.data(), nDoubleParticleBytes, cudaMemcpyHostToDevice), "copy transfer particleMass");
    check_cuda(cudaMemcpy(d_vx, particleVx.data(), nDoubleParticleBytes, cudaMemcpyHostToDevice), "copy transfer vx");
    check_cuda(cudaMemcpy(d_vy, particleVy.data(), nDoubleParticleBytes, cudaMemcpyHostToDevice), "copy transfer vy");
    check_cuda(cudaMemcpy(d_receiver, receiverCell.data(), nU32TransferBytes, cudaMemcpyHostToDevice), "copy receiver");
    check_cuda(cudaMemcpy(d_requested, requestedTransferMass.data(), nDoubleTransferBytes, cudaMemcpyHostToDevice), "copy requested");
    check_cuda(cudaMemcpy(d_selected, selectedDonorParticle.data(), nU32TransferBytes, cudaMemcpyHostToDevice), "copy selected");
    check_cuda(cudaMemcpy(d_insertion, insertionParticle.data(), nU32TransferBytes, cudaMemcpyHostToDevice), "copy insertion");
    const auto tu1 = Clock::now();

    cudaEvent_t ev0{}, ev1{};
    check_cuda(cudaEventCreate(&ev0), "event create transfer 0");
    check_cuda(cudaEventCreate(&ev1), "event create transfer 1");
    check_cuda(cudaEventRecord(ev0), "event record transfer 0");
    const int threads = 256;
    const int blocks = (nTransfers + threads - 1) / threads;
    apply_shadow_transfer_kernel_0233<<<blocks, threads>>>(
        d_receiver, d_requested, d_selected, d_insertion, nTransfers, nParticles,
        params.fluidRole, params.insertionRole, params.invalidParticle,
        params.maxExtractFractionOfDonor, params.minDonorMassAfterExtract,
        d_cell, d_role, d_mass, d_vx, d_vy, d_actual);
    check_cuda(cudaGetLastError(), "launch shadow transfer");
    check_cuda(cudaEventRecord(ev1), "event record transfer 1");
    check_cuda(cudaEventSynchronize(ev1), "event sync transfer 1");
    float kernelMs = 0.0f;
    check_cuda(cudaEventElapsedTime(&kernelMs, ev0, ev1), "event elapsed transfer");
    check_cuda(cudaEventDestroy(ev0), "event destroy transfer 0");
    check_cuda(cudaEventDestroy(ev1), "event destroy transfer 1");

    std::vector<double> actualTmp(receiverCell.size(), 0.0);
    const auto td0 = Clock::now();
    check_cuda(cudaMemcpy(outParticleCell.data(), d_cell, nU32ParticleBytes, cudaMemcpyDeviceToHost), "copy out cell");
    check_cuda(cudaMemcpy(outParticleRole.data(), d_role, nU8ParticleBytes, cudaMemcpyDeviceToHost), "copy out role");
    check_cuda(cudaMemcpy(outParticleMass.data(), d_mass, nDoubleParticleBytes, cudaMemcpyDeviceToHost), "copy out mass");
    check_cuda(cudaMemcpy(outParticleVx.data(), d_vx, nDoubleParticleBytes, cudaMemcpyDeviceToHost), "copy out vx");
    check_cuda(cudaMemcpy(outParticleVy.data(), d_vy, nDoubleParticleBytes, cudaMemcpyDeviceToHost), "copy out vy");
    check_cuda(cudaMemcpy(actualTmp.data(), d_actual, nDoubleTransferBytes, cudaMemcpyDeviceToHost), "copy actual transfer");
    const auto td1 = Clock::now();
    if (actualTransferMass) *actualTransferMass = actualTmp;

    if (diagnostics) {
        diagnostics->applied = true;
        diagnostics->kernelSeconds = static_cast<double>(kernelMs) * 1.0e-3;
        diagnostics->uploadSeconds = elapsed_seconds(tu0, tu1);
        diagnostics->downloadSeconds = elapsed_seconds(td0, td1);
        for (double dm : actualTmp) {
            diagnostics->actualTransferMass += dm;
            if (dm > 0.0) ++diagnostics->appliedTransfers;
            else ++diagnostics->skippedTransfers;
        }
        accumulate_state(outParticleMass, outParticleVx, outParticleVy,
                         diagnostics->totalMassAfter, diagnostics->totalPxAfter, diagnostics->totalPyAfter);
    }

    cudaFree(d_cell); cudaFree(d_role); cudaFree(d_mass); cudaFree(d_vx); cudaFree(d_vy);
    cudaFree(d_receiver); cudaFree(d_requested); cudaFree(d_selected); cudaFree(d_insertion); cudaFree(d_actual);

    if (diagnostics) diagnostics->totalSeconds = elapsed_seconds(t0, Clock::now());
    return true;
}

} // namespace mpcd
