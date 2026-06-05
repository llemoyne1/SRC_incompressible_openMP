#include "cuda_particle_state.h"
#include "cuda_resampling_particle_ops.h"
#include "particle_state.h"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstdlib>
#include <iomanip>
#include <iostream>
#include <numeric>
#include <string>
#include <vector>

namespace {

struct CaseConfig {
    std::uint32_t Nx = 64;
    std::uint32_t Ny = 64;
    std::uint32_t gamma = 20;
    std::uint32_t nOps = 0;
};

static double hash01(std::uint32_t a) {
    a ^= a >> 16;
    a *= 0x7feb352du;
    a ^= a >> 15;
    a *= 0x846ca68bu;
    a ^= a >> 16;
    return (static_cast<double>(a & 0x00ffffffu) + 0.5) / 16777216.0;
}

static mpcd::ParticleState make_state(const CaseConfig& cfg) {
    const std::uint64_t nCells = static_cast<std::uint64_t>(cfg.Nx) * cfg.Ny;
    const std::uint64_t n = nCells * cfg.gamma;
    mpcd::ParticleState s;
    s.Np = n;
    s.dim = 2;
    s.x.resize(n);
    s.y.resize(n);
    s.vx.resize(n);
    s.vy.resize(n);
    s.mass.resize(n);
    s.type.resize(n);
    s.role.resize(n, mpcd::kParticleRoleFluid);
    const double dx = 1.0 / static_cast<double>(cfg.Nx);
    const double dy = 1.0 / static_cast<double>(cfg.Ny);
    for (std::uint64_t i = 0; i < n; ++i) {
        const std::uint32_t c = static_cast<std::uint32_t>(i / cfg.gamma);
        const std::uint32_t ix = c % cfg.Nx;
        const std::uint32_t iy = c / cfg.Nx;
        const std::uint32_t lane = static_cast<std::uint32_t>(i % cfg.gamma);
        s.x[i] = (static_cast<double>(ix) + (static_cast<double>(lane) + 0.5) / cfg.gamma) * dx;
        s.y[i] = (static_cast<double>(iy) + hash01(static_cast<std::uint32_t>(i))) * dy;
        s.vx[i] = 0.01 * std::sin(0.001 * static_cast<double>(i + 3));
        s.vy[i] = 0.01 * std::cos(0.0013 * static_cast<double>(i + 7));
        s.mass[i] = 1.0 + 0.001 * static_cast<double>((i * 17u) % 11u);
        s.type[i] = static_cast<std::uint32_t>((i * 13u) % 3u);
    }
    return s;
}

static void build_ops(const CaseConfig& cfg,
                      const mpcd::ParticleState& s,
                      std::vector<std::uint32_t>& particleIndex,
                      std::vector<std::uint32_t>& receiverCell,
                      std::vector<std::uint32_t>& particleType,
                      std::vector<double>& particleMass,
                      std::vector<double>& momentumX,
                      std::vector<double>& momentumY,
                      std::vector<std::uint32_t>& insertionOrdinal)
{
    const std::uint32_t nCells = cfg.Nx * cfg.Ny;
    const std::uint32_t nOps = cfg.nOps ? cfg.nOps : std::max<std::uint32_t>(1u, nCells / 8u);
    particleIndex.clear();
    receiverCell.clear();
    particleType.clear();
    particleMass.clear();
    momentumX.clear();
    momentumY.clear();
    insertionOrdinal.clear();
    particleIndex.reserve(nOps);
    receiverCell.reserve(nOps);
    particleType.reserve(nOps);
    particleMass.reserve(nOps);
    momentumX.reserve(nOps);
    momentumY.reserve(nOps);
    insertionOrdinal.reserve(nOps);
    const std::uint32_t stride = std::max<std::uint32_t>(2u, cfg.gamma / 2u);
    for (std::uint32_t k = 0; k < nOps; ++k) {
        const std::uint32_t donorCell = (k * 37u + 11u) % nCells;
        const std::uint32_t lane = (k * 5u) % cfg.gamma;
        const std::uint32_t p = donorCell * cfg.gamma + lane;
        const std::uint32_t recv = (donorCell + 1u + (k % 17u)) % nCells;
        const double m = 0.2 + 0.01 * static_cast<double>((k * 3u) % 7u);
        const double vx = s.vx[p];
        const double vy = s.vy[p];
        particleIndex.push_back(p);
        receiverCell.push_back(recv);
        particleType.push_back(7u + (k % 5u));
        particleMass.push_back(m);
        momentumX.push_back(m * vx);
        momentumY.push_back(m * vy);
        insertionOrdinal.push_back(k + stride);
    }
}

static void apply_cpu_reference(mpcd::ParticleState& s,
                                const CaseConfig& cfg,
                                const std::vector<std::uint32_t>& particleIndex,
                                const std::vector<std::uint32_t>& receiverCell,
                                const std::vector<std::uint32_t>& particleType,
                                const std::vector<double>& particleMass,
                                const std::vector<double>& momentumX,
                                const std::vector<double>& momentumY,
                                const std::vector<std::uint32_t>& insertionOrdinal)
{
    const double dx = 1.0 / static_cast<double>(cfg.Nx);
    const double dy = 1.0 / static_cast<double>(cfg.Ny);
    for (std::uint32_t p : particleIndex) {
        s.role[p] = mpcd::kParticleRoleInactive;
    }
    for (std::size_t k = 0; k < particleIndex.size(); ++k) {
        const std::uint32_t p = particleIndex[k];
        const std::uint32_t c = receiverCell[k];
        const std::uint32_t ix = c % cfg.Nx;
        const std::uint32_t iy = c / cfg.Nx;
        const std::uint32_t ord = insertionOrdinal[k];
        const double fx = hash01(ord ^ (c * 747796405u));
        const double fy = hash01((ord + 0x9e3779b9u) ^ (c * 2891336453u));
        const double m = particleMass[k];
        s.x[p] = (static_cast<double>(ix) + fx) * dx;
        s.y[p] = (static_cast<double>(iy) + fy) * dy;
        s.mass[p] = m;
        s.type[p] = particleType[k];
        s.vx[p] = momentumX[k] / m;
        s.vy[p] = momentumY[k] / m;
        s.role[p] = mpcd::kParticleRoleFluid;
    }
}

static int run_case(const CaseConfig& cfg) {
    auto cpu = make_state(cfg);
    auto gpuHost = cpu;
    std::vector<std::uint32_t> particleIndex, receiverCell, particleType, insertionOrdinal;
    std::vector<double> particleMass, momentumX, momentumY;
    build_ops(cfg, cpu, particleIndex, receiverCell, particleType, particleMass, momentumX, momentumY, insertionOrdinal);
    apply_cpu_reference(cpu, cfg, particleIndex, receiverCell, particleType, particleMass, momentumX, momentumY, insertionOrdinal);

    mpcd::CudaParticleState gpu;
    mpcd::CudaParticleStateDiagnostics stateDiag{};
    gpu.upload_all(gpuHost, &stateDiag);

    mpcd::CudaResamplingExtractionApplyParams eparams{};
    eparams.fluidRole = mpcd::kParticleRoleFluid;
    eparams.inactiveRole = mpcd::kParticleRoleInactive;
    mpcd::CudaResamplingInsertionApplyParams iparams{};
    iparams.inactiveRole = mpcd::kParticleRoleInactive;
    iparams.fluidRole = mpcd::kParticleRoleFluid;
    mpcd::CudaResamplingPersistentOpsDiagnostics ediag{}, idiag{};
    mpcd::cuda_resampling_apply_extraction_operations_on_state_0239(
        gpu, particleIndex, particleMass, momentumX, momentumY, eparams, &ediag);
    mpcd::cuda_resampling_apply_insertion_operations_on_state_0239(
        gpu, particleIndex, receiverCell, particleType, particleMass, momentumX, momentumY, insertionOrdinal,
        cfg.Nx, cfg.Ny, 1.0/static_cast<double>(cfg.Nx), 1.0/static_cast<double>(cfg.Ny), iparams, &idiag);
    gpu.download_all(gpuHost, &stateDiag);

    double maxAbsX=0, maxAbsY=0, maxAbsVx=0, maxAbsVy=0, maxAbsMass=0;
    std::uint64_t roleMismatch=0, typeMismatch=0, valueMismatch=0;
    const double tol = 1.0e-12;
    for (std::uint64_t i=0; i<cpu.Np; ++i) {
        maxAbsX = std::max(maxAbsX, std::abs(cpu.x[i]-gpuHost.x[i]));
        maxAbsY = std::max(maxAbsY, std::abs(cpu.y[i]-gpuHost.y[i]));
        maxAbsVx = std::max(maxAbsVx, std::abs(cpu.vx[i]-gpuHost.vx[i]));
        maxAbsVy = std::max(maxAbsVy, std::abs(cpu.vy[i]-gpuHost.vy[i]));
        maxAbsMass = std::max(maxAbsMass, std::abs(cpu.mass[i]-gpuHost.mass[i]));
        if (cpu.role[i] != gpuHost.role[i]) ++roleMismatch;
        if (cpu.type[i] != gpuHost.type[i]) ++typeMismatch;
    }
    if (maxAbsX>tol || maxAbsY>tol || maxAbsVx>tol || maxAbsVy>tol || maxAbsMass>tol) valueMismatch=1;
    const bool pass = (roleMismatch==0 && typeMismatch==0 && valueMismatch==0 && ediag.invalidOperations==0 && idiag.invalidOperations==0);
    std::cout << "CUDA_RESAMPLING_PERSISTENT_STATE_OPS_0239 " << (pass?"PASS":"FAIL")
              << " Nx=" << cfg.Nx << " Ny=" << cfg.Ny << " gamma=" << cfg.gamma
              << " particles=" << cpu.Np << " operations=" << particleIndex.size()
              << " extractionApplied=" << ediag.operationsApplied
              << " insertionApplied=" << idiag.operationsApplied
              << " allocationCalls=" << stateDiag.allocationCalls
              << " maxAbsX=" << std::setprecision(17) << maxAbsX
              << " maxAbsY=" << maxAbsY
              << " maxAbsVx=" << maxAbsVx
              << " maxAbsVy=" << maxAbsVy
              << " maxAbsMass=" << maxAbsMass
              << " roleMismatches=" << roleMismatch
              << " typeMismatches=" << typeMismatch
              << " opUploadSeconds=" << (ediag.operationUploadSeconds + idiag.operationUploadSeconds)
              << " kernelSeconds=" << (ediag.kernelSeconds + idiag.kernelSeconds)
              << "\n";
    return pass ? 0 : 1;
}

} // namespace

int main(int argc, char** argv) {
    CaseConfig cfg;
    if (argc >= 4) {
        cfg.Nx = static_cast<std::uint32_t>(std::stoul(argv[1]));
        cfg.Ny = static_cast<std::uint32_t>(std::stoul(argv[2]));
        cfg.gamma = static_cast<std::uint32_t>(std::stoul(argv[3]));
    }
    if (argc >= 5) cfg.nOps = static_cast<std::uint32_t>(std::stoul(argv[4]));
    return run_case(cfg);
}
