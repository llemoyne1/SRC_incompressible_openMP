#include "cuda_resampling_particle_ops.h"
#include "cuda_particle_state.h"

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


namespace {

__global__ void apply_insertion_operations_kernel_0236(
    double* __restrict__ x,
    double* __restrict__ y,
    double* __restrict__ vx,
    double* __restrict__ vy,
    double* __restrict__ mass,
    std::uint32_t* __restrict__ type,
    std::uint8_t* __restrict__ role,
    const std::uint32_t* __restrict__ particleIndex,
    const std::uint32_t* __restrict__ receiverCell,
    const std::uint32_t* __restrict__ particleType,
    const double* __restrict__ particleMass,
    const double* __restrict__ momentumX,
    const double* __restrict__ momentumY,
    const std::uint32_t* __restrict__ insertionOrdinal,
    int nOperations,
    int nParticles,
    int Nx,
    int Ny,
    double dx,
    double dy,
    std::uint8_t fluidRole,
    std::uint8_t inactiveRole,
    std::uint32_t invalidParticle,
    std::uint32_t* __restrict__ appliedFlags)
{
    const int t = blockIdx.x * blockDim.x + threadIdx.x;
    if (t >= nOperations) return;
    appliedFlags[t] = 0u;

    const std::uint32_t p = particleIndex[t];
    if (p == invalidParticle || p >= static_cast<std::uint32_t>(nParticles)) return;
    if (role[p] != inactiveRole) return;
    const std::uint32_t cell = receiverCell[t];
    if (cell >= static_cast<std::uint32_t>(Nx * Ny)) return;
    const double m = particleMass[t];
    if (!(m > 0.0)) return;

    const int ix = static_cast<int>(cell % static_cast<std::uint32_t>(Nx));
    const int iy = static_cast<int>(cell / static_cast<std::uint32_t>(Nx));
    const std::uint32_t q = insertionOrdinal[t] & 15u;
    const double fx = 0.2 + 0.2 * static_cast<double>(q & 3u);
    const double fy = 0.2 + 0.2 * static_cast<double>(q >> 2u);

    x[p] = (static_cast<double>(ix) + fx) * dx;
    y[p] = (static_cast<double>(iy) + fy) * dy;
    vx[p] = momentumX[t] / m;
    vy[p] = momentumY[t] / m;
    mass[p] = m;
    type[p] = particleType[t];
    role[p] = fluidRole;
    appliedFlags[t] = 1u;
}

} // namespace

bool cuda_resampling_apply_insertion_operations_0236(
    std::vector<double>& x,
    std::vector<double>& y,
    std::vector<double>& vx,
    std::vector<double>& vy,
    std::vector<double>& mass,
    std::vector<std::uint32_t>& type,
    std::vector<std::uint8_t>& role,
    const std::vector<std::uint32_t>& particleIndex,
    const std::vector<std::uint32_t>& receiverCell,
    const std::vector<std::uint32_t>& particleType,
    const std::vector<double>& particleMass,
    const std::vector<double>& momentumX,
    const std::vector<double>& momentumY,
    const std::vector<std::uint32_t>& insertionOrdinal,
    std::uint32_t Nx,
    std::uint32_t Ny,
    double dx,
    double dy,
    const CudaResamplingInsertionApplyParams& params,
    CudaResamplingInsertionApplyDiagnostics* diagnostics)
{
    const auto t0 = Clock::now();
    const std::size_t n = x.size();
    const std::size_t mOps = particleIndex.size();
    if (y.size() != n || vx.size() != n || vy.size() != n || mass.size() != n || type.size() != n || role.size() != n) {
        throw std::runtime_error("cuda_resampling_apply_insertion_operations_0236: particle array size mismatch");
    }
    if (receiverCell.size() != mOps || particleType.size() != mOps || particleMass.size() != mOps ||
        momentumX.size() != mOps || momentumY.size() != mOps || insertionOrdinal.size() != mOps) {
        throw std::runtime_error("cuda_resampling_apply_insertion_operations_0236: operation array size mismatch");
    }
    if (diagnostics) {
        *diagnostics = CudaResamplingInsertionApplyDiagnostics{};
        diagnostics->attempted = true;
        diagnostics->particles = static_cast<std::uint64_t>(n);
        diagnostics->operations = static_cast<std::uint64_t>(mOps);
        for (std::size_t i = 0; i < mOps; ++i) {
            diagnostics->insertedMass += particleMass[i];
            diagnostics->insertedMomentumX += momentumX[i];
            diagnostics->insertedMomentumY += momentumY[i];
        }
    }
    if (n == 0 || mOps == 0) {
        if (diagnostics) {
            diagnostics->applied = true;
            diagnostics->totalSeconds = elapsed_seconds(t0, Clock::now());
        }
        return true;
    }

    double *d_x=nullptr,*d_y=nullptr,*d_vx=nullptr,*d_vy=nullptr,*d_mass=nullptr;
    std::uint32_t *d_type=nullptr,*d_index=nullptr,*d_receiver=nullptr,*d_particleType=nullptr,*d_ordinal=nullptr,*d_applied=nullptr;
    std::uint8_t *d_role=nullptr;
    double *d_opMass=nullptr,*d_mx=nullptr,*d_my=nullptr;
    const std::size_t bytesD = n * sizeof(double);
    const std::size_t bytesU32 = n * sizeof(std::uint32_t);
    const std::size_t bytesU8 = n * sizeof(std::uint8_t);
    const std::size_t opU32 = mOps * sizeof(std::uint32_t);
    const std::size_t opD = mOps * sizeof(double);
    check_cuda(cudaMalloc(&d_x, bytesD), "malloc insertion x");
    check_cuda(cudaMalloc(&d_y, bytesD), "malloc insertion y");
    check_cuda(cudaMalloc(&d_vx, bytesD), "malloc insertion vx");
    check_cuda(cudaMalloc(&d_vy, bytesD), "malloc insertion vy");
    check_cuda(cudaMalloc(&d_mass, bytesD), "malloc insertion mass");
    check_cuda(cudaMalloc(&d_type, bytesU32), "malloc insertion type");
    check_cuda(cudaMalloc(&d_role, bytesU8), "malloc insertion role");
    check_cuda(cudaMalloc(&d_index, opU32), "malloc insertion index");
    check_cuda(cudaMalloc(&d_receiver, opU32), "malloc insertion receiver");
    check_cuda(cudaMalloc(&d_particleType, opU32), "malloc insertion op type");
    check_cuda(cudaMalloc(&d_opMass, opD), "malloc insertion op mass");
    check_cuda(cudaMalloc(&d_mx, opD), "malloc insertion mx");
    check_cuda(cudaMalloc(&d_my, opD), "malloc insertion my");
    check_cuda(cudaMalloc(&d_ordinal, opU32), "malloc insertion ordinal");
    check_cuda(cudaMalloc(&d_applied, opU32), "malloc insertion applied");

    const auto tu0 = Clock::now();
    check_cuda(cudaMemcpy(d_x, x.data(), bytesD, cudaMemcpyHostToDevice), "copy insertion x");
    check_cuda(cudaMemcpy(d_y, y.data(), bytesD, cudaMemcpyHostToDevice), "copy insertion y");
    check_cuda(cudaMemcpy(d_vx, vx.data(), bytesD, cudaMemcpyHostToDevice), "copy insertion vx");
    check_cuda(cudaMemcpy(d_vy, vy.data(), bytesD, cudaMemcpyHostToDevice), "copy insertion vy");
    check_cuda(cudaMemcpy(d_mass, mass.data(), bytesD, cudaMemcpyHostToDevice), "copy insertion mass");
    check_cuda(cudaMemcpy(d_type, type.data(), bytesU32, cudaMemcpyHostToDevice), "copy insertion type");
    check_cuda(cudaMemcpy(d_role, role.data(), bytesU8, cudaMemcpyHostToDevice), "copy insertion role");
    check_cuda(cudaMemcpy(d_index, particleIndex.data(), opU32, cudaMemcpyHostToDevice), "copy insertion index");
    check_cuda(cudaMemcpy(d_receiver, receiverCell.data(), opU32, cudaMemcpyHostToDevice), "copy insertion receiver");
    check_cuda(cudaMemcpy(d_particleType, particleType.data(), opU32, cudaMemcpyHostToDevice), "copy insertion particle type");
    check_cuda(cudaMemcpy(d_opMass, particleMass.data(), opD, cudaMemcpyHostToDevice), "copy insertion mass ops");
    check_cuda(cudaMemcpy(d_mx, momentumX.data(), opD, cudaMemcpyHostToDevice), "copy insertion mx");
    check_cuda(cudaMemcpy(d_my, momentumY.data(), opD, cudaMemcpyHostToDevice), "copy insertion my");
    check_cuda(cudaMemcpy(d_ordinal, insertionOrdinal.data(), opU32, cudaMemcpyHostToDevice), "copy insertion ordinal");
    const auto tu1 = Clock::now();

    cudaEvent_t ev0{}, ev1{};
    check_cuda(cudaEventCreate(&ev0), "event insertion 0");
    check_cuda(cudaEventCreate(&ev1), "event insertion 1");
    check_cuda(cudaEventRecord(ev0), "record insertion 0");
    const int threads = 256;
    const int blocks = (static_cast<int>(mOps) + threads - 1) / threads;
    apply_insertion_operations_kernel_0236<<<blocks, threads>>>(
        d_x, d_y, d_vx, d_vy, d_mass, d_type, d_role,
        d_index, d_receiver, d_particleType, d_opMass, d_mx, d_my, d_ordinal,
        static_cast<int>(mOps), static_cast<int>(n), static_cast<int>(Nx), static_cast<int>(Ny), dx, dy,
        params.fluidRole, params.inactiveRole, params.invalidParticle, d_applied);
    check_cuda(cudaGetLastError(), "launch insertion operations");
    check_cuda(cudaEventRecord(ev1), "record insertion 1");
    check_cuda(cudaEventSynchronize(ev1), "sync insertion 1");
    float kernelMs = 0.0f;
    check_cuda(cudaEventElapsedTime(&kernelMs, ev0, ev1), "elapsed insertion");
    check_cuda(cudaEventDestroy(ev0), "destroy insertion 0");
    check_cuda(cudaEventDestroy(ev1), "destroy insertion 1");

    std::vector<std::uint32_t> applied(mOps, 0u);
    const auto td0 = Clock::now();
    check_cuda(cudaMemcpy(x.data(), d_x, bytesD, cudaMemcpyDeviceToHost), "download insertion x");
    check_cuda(cudaMemcpy(y.data(), d_y, bytesD, cudaMemcpyDeviceToHost), "download insertion y");
    check_cuda(cudaMemcpy(vx.data(), d_vx, bytesD, cudaMemcpyDeviceToHost), "download insertion vx");
    check_cuda(cudaMemcpy(vy.data(), d_vy, bytesD, cudaMemcpyDeviceToHost), "download insertion vy");
    check_cuda(cudaMemcpy(mass.data(), d_mass, bytesD, cudaMemcpyDeviceToHost), "download insertion mass");
    check_cuda(cudaMemcpy(type.data(), d_type, bytesU32, cudaMemcpyDeviceToHost), "download insertion type");
    check_cuda(cudaMemcpy(role.data(), d_role, bytesU8, cudaMemcpyDeviceToHost), "download insertion role");
    check_cuda(cudaMemcpy(applied.data(), d_applied, opU32, cudaMemcpyDeviceToHost), "download insertion applied");
    const auto td1 = Clock::now();

    if (diagnostics) {
        diagnostics->applied = true;
        diagnostics->kernelSeconds = static_cast<double>(kernelMs) * 1e-3;
        diagnostics->uploadSeconds = elapsed_seconds(tu0, tu1);
        diagnostics->downloadSeconds = elapsed_seconds(td0, td1);
        for (std::uint32_t v : applied) {
            if (v) ++diagnostics->operationsApplied;
            else ++diagnostics->invalidOperations;
        }
        diagnostics->totalSeconds = elapsed_seconds(t0, Clock::now());
    }

    cudaFree(d_x); cudaFree(d_y); cudaFree(d_vx); cudaFree(d_vy); cudaFree(d_mass);
    cudaFree(d_type); cudaFree(d_role); cudaFree(d_index); cudaFree(d_receiver); cudaFree(d_particleType);
    cudaFree(d_opMass); cudaFree(d_mx); cudaFree(d_my); cudaFree(d_ordinal); cudaFree(d_applied);
    return true;
}


namespace {

__global__ void apply_extraction_operations_kernel_0237(
    std::uint8_t* __restrict__ role,
    const std::uint32_t* __restrict__ particleIndex,
    int nOps,
    int nParticles,
    std::uint8_t fluidRole,
    std::uint8_t inactiveRole,
    std::uint32_t invalidParticle,
    std::uint32_t* __restrict__ appliedFlags)
{
    const int t = blockIdx.x * blockDim.x + threadIdx.x;
    if (t >= nOps) return;
    const std::uint32_t p = particleIndex[t];
    if (p == invalidParticle || p >= static_cast<std::uint32_t>(nParticles)) {
        appliedFlags[t] = 0u;
        return;
    }
    if (role[p] != fluidRole) {
        appliedFlags[t] = 0u;
        return;
    }
    role[p] = inactiveRole;
    appliedFlags[t] = 1u;
}

} // namespace

bool cuda_resampling_apply_extraction_operations_0237(
    std::vector<std::uint8_t>& role,
    const std::vector<std::uint32_t>& particleIndex,
    const std::vector<double>& particleMass,
    const std::vector<double>& momentumX,
    const std::vector<double>& momentumY,
    const CudaResamplingExtractionApplyParams& params,
    CudaResamplingExtractionApplyDiagnostics* diagnostics)
{
    const auto t0 = Clock::now();
    const std::size_t n = role.size();
    const std::size_t mOps = particleIndex.size();
    if (particleMass.size() != mOps || momentumX.size() != mOps || momentumY.size() != mOps) {
        throw std::runtime_error("cuda_resampling_apply_extraction_operations_0237: operation array size mismatch");
    }
    if (diagnostics) {
        *diagnostics = CudaResamplingExtractionApplyDiagnostics{};
        diagnostics->attempted = true;
        diagnostics->particles = static_cast<std::uint64_t>(n);
        diagnostics->operations = static_cast<std::uint64_t>(mOps);
        for (std::size_t i = 0; i < mOps; ++i) {
            diagnostics->extractedMass += particleMass[i];
            diagnostics->extractedMomentumX += momentumX[i];
            diagnostics->extractedMomentumY += momentumY[i];
        }
    }
    if (n == 0 || mOps == 0) {
        if (diagnostics) {
            diagnostics->applied = true;
            diagnostics->totalSeconds = elapsed_seconds(t0, Clock::now());
        }
        return true;
    }

    std::uint8_t* d_role = nullptr;
    std::uint32_t* d_index = nullptr;
    std::uint32_t* d_applied = nullptr;
    const std::size_t bytesRole = n * sizeof(std::uint8_t);
    const std::size_t opU32 = mOps * sizeof(std::uint32_t);
    check_cuda(cudaMalloc(&d_role, bytesRole), "malloc extraction role");
    check_cuda(cudaMalloc(&d_index, opU32), "malloc extraction index");
    check_cuda(cudaMalloc(&d_applied, opU32), "malloc extraction applied");

    const auto tu0 = Clock::now();
    check_cuda(cudaMemcpy(d_role, role.data(), bytesRole, cudaMemcpyHostToDevice), "copy extraction role");
    check_cuda(cudaMemcpy(d_index, particleIndex.data(), opU32, cudaMemcpyHostToDevice), "copy extraction index");
    const auto tu1 = Clock::now();

    cudaEvent_t ev0{}, ev1{};
    check_cuda(cudaEventCreate(&ev0), "event extraction 0");
    check_cuda(cudaEventCreate(&ev1), "event extraction 1");
    check_cuda(cudaEventRecord(ev0), "record extraction 0");
    const int threads = 256;
    const int blocks = (static_cast<int>(mOps) + threads - 1) / threads;
    apply_extraction_operations_kernel_0237<<<blocks, threads>>>(
        d_role, d_index, static_cast<int>(mOps), static_cast<int>(n),
        params.fluidRole, params.inactiveRole, params.invalidParticle, d_applied);
    check_cuda(cudaGetLastError(), "launch extraction operations");
    check_cuda(cudaEventRecord(ev1), "record extraction 1");
    check_cuda(cudaEventSynchronize(ev1), "sync extraction 1");
    float kernelMs = 0.0f;
    check_cuda(cudaEventElapsedTime(&kernelMs, ev0, ev1), "elapsed extraction");
    check_cuda(cudaEventDestroy(ev0), "destroy extraction 0");
    check_cuda(cudaEventDestroy(ev1), "destroy extraction 1");

    std::vector<std::uint32_t> applied(mOps, 0u);
    const auto td0 = Clock::now();
    check_cuda(cudaMemcpy(role.data(), d_role, bytesRole, cudaMemcpyDeviceToHost), "download extraction role");
    check_cuda(cudaMemcpy(applied.data(), d_applied, opU32, cudaMemcpyDeviceToHost), "download extraction applied");
    const auto td1 = Clock::now();

    if (diagnostics) {
        diagnostics->applied = true;
        diagnostics->kernelSeconds = static_cast<double>(kernelMs) * 1e-3;
        diagnostics->uploadSeconds = elapsed_seconds(tu0, tu1);
        diagnostics->downloadSeconds = elapsed_seconds(td0, td1);
        for (std::uint32_t v : applied) {
            if (v) ++diagnostics->operationsApplied;
            else ++diagnostics->invalidOperations;
        }
        diagnostics->totalSeconds = elapsed_seconds(t0, Clock::now());
    }

    cudaFree(d_role);
    cudaFree(d_index);
    cudaFree(d_applied);
    return true;
}

namespace {

__global__ void apply_extraction_on_particle_state_kernel_0239(
    unsigned char* __restrict__ role,
    const std::uint32_t* __restrict__ particleIndex,
    int nOps,
    int nParticles,
    std::uint8_t fluidRole,
    std::uint8_t inactiveRole,
    std::uint32_t invalidParticle,
    std::uint32_t* __restrict__ applied)
{
    const int op = blockIdx.x * blockDim.x + threadIdx.x;
    if (op >= nOps) return;
    const std::uint32_t p = particleIndex[op];
    std::uint32_t ok = 0u;
    if (p != invalidParticle && p < static_cast<std::uint32_t>(nParticles) && role[p] == fluidRole) {
        role[p] = inactiveRole;
        ok = 1u;
    }
    applied[op] = ok;
}

__device__ __host__ inline double resampling_hash01_0239(std::uint32_t a) {
    a ^= a >> 16;
    a *= 0x7feb352du;
    a ^= a >> 15;
    a *= 0x846ca68bu;
    a ^= a >> 16;
    return (static_cast<double>(a & 0x00ffffffu) + 0.5) / 16777216.0;
}

__global__ void apply_insertion_on_particle_state_kernel_0239(
    double* __restrict__ x,
    double* __restrict__ y,
    double* __restrict__ vx,
    double* __restrict__ vy,
    double* __restrict__ mass,
    std::uint32_t* __restrict__ type,
    unsigned char* __restrict__ role,
    const std::uint32_t* __restrict__ particleIndex,
    const std::uint32_t* __restrict__ receiverCell,
    const std::uint32_t* __restrict__ particleType,
    const double* __restrict__ particleMass,
    const double* __restrict__ momentumX,
    const double* __restrict__ momentumY,
    const std::uint32_t* __restrict__ insertionOrdinal,
    int nOps,
    int nParticles,
    std::uint32_t Nx,
    std::uint32_t Ny,
    double dx,
    double dy,
    std::uint8_t inactiveRole,
    std::uint8_t fluidRole,
    std::uint32_t invalidParticle,
    std::uint8_t useHashPlacement,
    std::uint32_t* __restrict__ applied)
{
    const int op = blockIdx.x * blockDim.x + threadIdx.x;
    if (op >= nOps) return;
    const std::uint32_t p = particleIndex[op];
    std::uint32_t ok = 0u;
    if (p != invalidParticle && p < static_cast<std::uint32_t>(nParticles) && role[p] == inactiveRole) {
        const std::uint32_t c = receiverCell[op];
        const std::uint32_t nCells = Nx * Ny;
        const double m = particleMass[op];
        if (c < nCells && m > 0.0) {
            const std::uint32_t ix = c % Nx;
            const std::uint32_t iy = c / Nx;
            const std::uint32_t ord = insertionOrdinal[op];
            double fx = 0.0;
            double fy = 0.0;
            if (useHashPlacement) {
                fx = resampling_hash01_0239(ord ^ (c * 747796405u));
                fy = resampling_hash01_0239((ord + 0x9e3779b9u) ^ (c * 2891336453u));
            } else {
                const std::uint32_t q = ord & 15u;
                fx = 0.2 + 0.2 * static_cast<double>(q & 3u);
                fy = 0.2 + 0.2 * static_cast<double>(q >> 2u);
            }
            x[p] = (static_cast<double>(ix) + fx) * dx;
            y[p] = (static_cast<double>(iy) + fy) * dy;
            mass[p] = m;
            type[p] = particleType[op];
            vx[p] = momentumX[op] / m;
            vy[p] = momentumY[op] / m;
            role[p] = fluidRole;
            ok = 1u;
        }
    }
    applied[op] = ok;
}

} // namespace

bool cuda_resampling_apply_extraction_operations_on_state_0239(
    CudaParticleState& gpuState,
    const std::vector<std::uint32_t>& particleIndex,
    const std::vector<double>& particleMass,
    const std::vector<double>& momentumX,
    const std::vector<double>& momentumY,
    const CudaResamplingExtractionApplyParams& params,
    CudaResamplingPersistentOpsDiagnostics* diagnostics)
{
    const auto t0 = Clock::now();
    auto view = gpuState.device_view();
    const std::size_t mOps = particleIndex.size();
    if (particleMass.size() != mOps || momentumX.size() != mOps || momentumY.size() != mOps) {
        throw std::runtime_error("cuda_resampling_apply_extraction_operations_on_state_0239: operation array size mismatch");
    }
    if (diagnostics) {
        *diagnostics = CudaResamplingPersistentOpsDiagnostics{};
        diagnostics->attempted = true;
        diagnostics->particles = view.n;
        diagnostics->extractionOperations = static_cast<std::uint64_t>(mOps);
        for (std::size_t k = 0; k < mOps; ++k) {
            diagnostics->extractedMass += particleMass[k];
            diagnostics->extractedMomentumX += momentumX[k];
            diagnostics->extractedMomentumY += momentumY[k];
        }
    }
    if (view.n == 0 || mOps == 0) {
        if (diagnostics) {
            diagnostics->applied = true;
            diagnostics->totalSeconds = elapsed_seconds(t0, Clock::now());
        }
        return true;
    }

    std::uint32_t* d_index = nullptr;
    std::uint32_t* d_applied = nullptr;
    const std::size_t opBytes = mOps * sizeof(std::uint32_t);
    check_cuda(cudaMalloc(&d_index, opBytes), "malloc state extraction index");
    check_cuda(cudaMalloc(&d_applied, opBytes), "malloc state extraction applied");
    const auto tu0 = Clock::now();
    check_cuda(cudaMemcpy(d_index, particleIndex.data(), opBytes, cudaMemcpyHostToDevice), "copy state extraction index");
    const auto tu1 = Clock::now();

    cudaEvent_t ev0{}, ev1{};
    check_cuda(cudaEventCreate(&ev0), "event state extraction 0");
    check_cuda(cudaEventCreate(&ev1), "event state extraction 1");
    check_cuda(cudaEventRecord(ev0), "record state extraction 0");
    const int threads = 256;
    const int blocks = (static_cast<int>(mOps) + threads - 1) / threads;
    apply_extraction_on_particle_state_kernel_0239<<<blocks, threads>>>(
        view.role, d_index, static_cast<int>(mOps), static_cast<int>(view.n),
        params.fluidRole, params.inactiveRole, params.invalidParticle, d_applied);
    check_cuda(cudaGetLastError(), "launch state extraction");
    check_cuda(cudaEventRecord(ev1), "record state extraction 1");
    check_cuda(cudaEventSynchronize(ev1), "sync state extraction 1");
    float kernelMs = 0.0f;
    check_cuda(cudaEventElapsedTime(&kernelMs, ev0, ev1), "elapsed state extraction");
    check_cuda(cudaEventDestroy(ev0), "destroy state extraction 0");
    check_cuda(cudaEventDestroy(ev1), "destroy state extraction 1");

    std::vector<std::uint32_t> applied(mOps, 0u);
    check_cuda(cudaMemcpy(applied.data(), d_applied, opBytes, cudaMemcpyDeviceToHost), "download state extraction applied");
    if (diagnostics) {
        diagnostics->applied = true;
        diagnostics->operationUploadSeconds = elapsed_seconds(tu0, tu1);
        diagnostics->kernelSeconds = static_cast<double>(kernelMs) * 1.0e-3;
        for (std::uint32_t v : applied) {
            if (v) ++diagnostics->operationsApplied;
            else ++diagnostics->invalidOperations;
        }
        diagnostics->totalSeconds = elapsed_seconds(t0, Clock::now());
    }
    cudaFree(d_index);
    cudaFree(d_applied);
    return true;
}

bool cuda_resampling_apply_insertion_operations_on_state_0239(
    CudaParticleState& gpuState,
    const std::vector<std::uint32_t>& particleIndex,
    const std::vector<std::uint32_t>& receiverCell,
    const std::vector<std::uint32_t>& particleType,
    const std::vector<double>& particleMass,
    const std::vector<double>& momentumX,
    const std::vector<double>& momentumY,
    const std::vector<std::uint32_t>& insertionOrdinal,
    std::uint32_t Nx,
    std::uint32_t Ny,
    double dx,
    double dy,
    const CudaResamplingInsertionApplyParams& params,
    CudaResamplingPersistentOpsDiagnostics* diagnostics)
{
    const auto t0 = Clock::now();
    auto view = gpuState.device_view();
    const std::size_t mOps = particleIndex.size();
    if (receiverCell.size() != mOps || particleType.size() != mOps || particleMass.size() != mOps ||
        momentumX.size() != mOps || momentumY.size() != mOps || insertionOrdinal.size() != mOps) {
        throw std::runtime_error("cuda_resampling_apply_insertion_operations_on_state_0239: operation array size mismatch");
    }
    if (diagnostics) {
        *diagnostics = CudaResamplingPersistentOpsDiagnostics{};
        diagnostics->attempted = true;
        diagnostics->particles = view.n;
        diagnostics->insertionOperations = static_cast<std::uint64_t>(mOps);
        for (std::size_t k = 0; k < mOps; ++k) {
            diagnostics->insertedMass += particleMass[k];
            diagnostics->insertedMomentumX += momentumX[k];
            diagnostics->insertedMomentumY += momentumY[k];
        }
    }
    if (view.n == 0 || mOps == 0) {
        if (diagnostics) {
            diagnostics->applied = true;
            diagnostics->totalSeconds = elapsed_seconds(t0, Clock::now());
        }
        return true;
    }

    std::uint32_t* d_index = nullptr;
    std::uint32_t* d_receiverCell = nullptr;
    std::uint32_t* d_particleType = nullptr;
    double* d_particleMass = nullptr;
    double* d_momentumX = nullptr;
    double* d_momentumY = nullptr;
    std::uint32_t* d_insertionOrdinal = nullptr;
    std::uint32_t* d_applied = nullptr;
    const std::size_t u32Bytes = mOps * sizeof(std::uint32_t);
    const std::size_t dblBytes = mOps * sizeof(double);
    check_cuda(cudaMalloc(&d_index, u32Bytes), "malloc state insertion index");
    check_cuda(cudaMalloc(&d_receiverCell, u32Bytes), "malloc state insertion receiverCell");
    check_cuda(cudaMalloc(&d_particleType, u32Bytes), "malloc state insertion particleType");
    check_cuda(cudaMalloc(&d_particleMass, dblBytes), "malloc state insertion particleMass");
    check_cuda(cudaMalloc(&d_momentumX, dblBytes), "malloc state insertion momentumX");
    check_cuda(cudaMalloc(&d_momentumY, dblBytes), "malloc state insertion momentumY");
    check_cuda(cudaMalloc(&d_insertionOrdinal, u32Bytes), "malloc state insertion ordinal");
    check_cuda(cudaMalloc(&d_applied, u32Bytes), "malloc state insertion applied");

    const auto tu0 = Clock::now();
    check_cuda(cudaMemcpy(d_index, particleIndex.data(), u32Bytes, cudaMemcpyHostToDevice), "copy state insertion index");
    check_cuda(cudaMemcpy(d_receiverCell, receiverCell.data(), u32Bytes, cudaMemcpyHostToDevice), "copy state insertion receiverCell");
    check_cuda(cudaMemcpy(d_particleType, particleType.data(), u32Bytes, cudaMemcpyHostToDevice), "copy state insertion particleType");
    check_cuda(cudaMemcpy(d_particleMass, particleMass.data(), dblBytes, cudaMemcpyHostToDevice), "copy state insertion particleMass");
    check_cuda(cudaMemcpy(d_momentumX, momentumX.data(), dblBytes, cudaMemcpyHostToDevice), "copy state insertion momentumX");
    check_cuda(cudaMemcpy(d_momentumY, momentumY.data(), dblBytes, cudaMemcpyHostToDevice), "copy state insertion momentumY");
    check_cuda(cudaMemcpy(d_insertionOrdinal, insertionOrdinal.data(), u32Bytes, cudaMemcpyHostToDevice), "copy state insertion ordinal");
    const auto tu1 = Clock::now();

    cudaEvent_t ev0{}, ev1{};
    check_cuda(cudaEventCreate(&ev0), "event state insertion 0");
    check_cuda(cudaEventCreate(&ev1), "event state insertion 1");
    check_cuda(cudaEventRecord(ev0), "record state insertion 0");
    const int threads = 256;
    const int blocks = (static_cast<int>(mOps) + threads - 1) / threads;
    apply_insertion_on_particle_state_kernel_0239<<<blocks, threads>>>(
        view.x, view.y, view.vx, view.vy, view.mass, view.type, view.role,
        d_index, d_receiverCell, d_particleType, d_particleMass, d_momentumX, d_momentumY,
        d_insertionOrdinal, static_cast<int>(mOps), static_cast<int>(view.n), Nx, Ny, dx, dy,
        params.inactiveRole, params.fluidRole, params.invalidParticle, params.useHashPlacement, d_applied);
    check_cuda(cudaGetLastError(), "launch state insertion");
    check_cuda(cudaEventRecord(ev1), "record state insertion 1");
    check_cuda(cudaEventSynchronize(ev1), "sync state insertion 1");
    float kernelMs = 0.0f;
    check_cuda(cudaEventElapsedTime(&kernelMs, ev0, ev1), "elapsed state insertion");
    check_cuda(cudaEventDestroy(ev0), "destroy state insertion 0");
    check_cuda(cudaEventDestroy(ev1), "destroy state insertion 1");

    std::vector<std::uint32_t> applied(mOps, 0u);
    check_cuda(cudaMemcpy(applied.data(), d_applied, u32Bytes, cudaMemcpyDeviceToHost), "download state insertion applied");
    if (diagnostics) {
        diagnostics->applied = true;
        diagnostics->operationUploadSeconds = elapsed_seconds(tu0, tu1);
        diagnostics->kernelSeconds = static_cast<double>(kernelMs) * 1.0e-3;
        for (std::uint32_t v : applied) {
            if (v) ++diagnostics->operationsApplied;
            else ++diagnostics->invalidOperations;
        }
        diagnostics->totalSeconds = elapsed_seconds(t0, Clock::now());
    }

    cudaFree(d_index);
    cudaFree(d_receiverCell);
    cudaFree(d_particleType);
    cudaFree(d_particleMass);
    cudaFree(d_momentumX);
    cudaFree(d_momentumY);
    cudaFree(d_insertionOrdinal);
    cudaFree(d_applied);
    return true;
}

} // namespace mpcd
