#include "cuda_particle_state.h"
#include "cuda_cell_workspace.h"
#include "cuda_persistent_mpcd_step.h"
#include "particle_state.h"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstdlib>
#include <iomanip>
#include <iostream>
#include <random>
#include <stdexcept>
#include <string>
#include <vector>

namespace {

std::uint64_t splitmix64(std::uint64_t x) {
    x += 0x9e3779b97f4a7c15ULL;
    x = (x ^ (x >> 30U)) * 0xbf58476d1ce4e5b9ULL;
    x = (x ^ (x >> 27U)) * 0x94d049bb133111ebULL;
    return x ^ (x >> 31U);
}

double arg_double(int argc, char** argv, const std::string& name, double fallback) {
    for (int i = 1; i + 1 < argc; ++i) if (argv[i] == name) return std::stod(argv[i + 1]);
    return fallback;
}

int arg_int(int argc, char** argv, const std::string& name, int fallback) {
    for (int i = 1; i + 1 < argc; ++i) if (argv[i] == name) return std::stoi(argv[i + 1]);
    return fallback;
}

std::uint64_t arg_u64(int argc, char** argv, const std::string& name, std::uint64_t fallback) {
    for (int i = 1; i + 1 < argc; ++i) if (argv[i] == name) return static_cast<std::uint64_t>(std::stoull(argv[i + 1]));
    return fallback;
}

mpcd::ParticleState make_state(int nx, int ny, int gamma, int mixedRoles, int variableMass, std::uint64_t seed) {
    const int n = nx * ny * gamma;
    mpcd::ParticleState s{};
    s.Np = static_cast<std::uint64_t>(n);
    s.dim = 2;
    s.x.resize(n); s.y.resize(n); s.vx.resize(n); s.vy.resize(n);
    s.type.assign(n, 0u); s.mass.resize(n); s.role.resize(n, mpcd::kParticleRoleFluid);

    std::mt19937_64 rng(seed);
    std::uniform_real_distribution<double> U(0.0, 1.0);
    std::normal_distribution<double> N(0.0, 1.0);

    for (int i = 0; i < n; ++i) {
        const std::size_t k = static_cast<std::size_t>(i);
        s.x[k] = U(rng);
        s.y[k] = U(rng);
        s.vx[k] = 0.05 * std::sin(6.2831853071795864769 * s.y[k]) + 0.03 * N(rng);
        s.vy[k] = -0.05 * std::sin(6.2831853071795864769 * s.x[k]) + 0.03 * N(rng);
        s.mass[k] = variableMass ? (1.0 + 0.05 * static_cast<double>(i % 7)) : 1.0;
        if (mixedRoles) {
            const std::uint64_t h = splitmix64(seed ^ static_cast<std::uint64_t>(i));
            if ((h % 97u) == 0u) s.role[k] = mpcd::kParticleRoleInactive;
            else if ((h % 43u) == 0u) s.role[k] = mpcd::kParticleRoleLatent;
        }
    }
    return s;
}

int periodic_index(double x, double L, double dx, int N) {
    x = std::fmod(x, L);
    if (x < 0.0) x += L;
    if (x >= L) x -= L;
    int i = static_cast<int>(std::floor(x / dx));
    if (i < 0) i = 0;
    if (i >= N) i = N - 1;
    return i;
}

void cpu_cycle(mpcd::ParticleState& s, const mpcd::CudaPersistentMpcdStepConfig& cfg) {
    const int nc = cfg.Nx * cfg.Ny;
    const double dx = cfg.Lx / static_cast<double>(cfg.Nx);
    const double dy = cfg.Ly / static_cast<double>(cfg.Ny);
    const std::size_t n = static_cast<std::size_t>(s.Np);
    std::vector<int> cellId(n, -1);
    std::vector<unsigned int> count(static_cast<std::size_t>(nc), 0u);
    std::vector<double> mass(static_cast<std::size_t>(nc), 0.0);
    std::vector<double> px(static_cast<std::size_t>(nc), 0.0);
    std::vector<double> py(static_cast<std::size_t>(nc), 0.0);
    std::vector<double> ux(static_cast<std::size_t>(nc), 0.0);
    std::vector<double> uy(static_cast<std::size_t>(nc), 0.0);
    std::vector<double> cosA(static_cast<std::size_t>(nc), std::cos(cfg.rotationAngle));
    std::vector<double> sinA(static_cast<std::size_t>(nc), std::sin(cfg.rotationAngle));
    if (cfg.randomRotationSign) {
        for (int c = 0; c < nc; ++c) {
            const std::uint64_t h = splitmix64(cfg.rngSeed ^ (cfg.step * 0x9e3779b97f4a7c15ULL) ^ static_cast<std::uint64_t>(c));
            if ((h & 1ULL) == 0ULL) sinA[static_cast<std::size_t>(c)] = -sinA[static_cast<std::size_t>(c)];
        }
    }

    for (std::size_t i = 0; i < n; ++i) {
        if (s.role[i] != mpcd::kParticleRoleFluid) continue;
        const int ix = periodic_index(s.x[i] + cfg.shiftX, cfg.Lx, dx, cfg.Nx);
        const int iy = periodic_index(s.y[i] + cfg.shiftY, cfg.Ly, dy, cfg.Ny);
        const int c = ix + cfg.Nx * iy;
        cellId[i] = c;
        const std::size_t k = static_cast<std::size_t>(c);
        const double m = s.mass[i];
        count[k] += 1u;
        mass[k] += m;
        px[k] += m * s.vx[i];
        py[k] += m * s.vy[i];
    }
    for (int c = 0; c < nc; ++c) {
        const std::size_t k = static_cast<std::size_t>(c);
        if (mass[k] > 0.0) { ux[k] = px[k] / mass[k]; uy[k] = py[k] / mass[k]; }
    }
    for (std::size_t i = 0; i < n; ++i) {
        if (s.role[i] != mpcd::kParticleRoleFluid) continue;
        const int c = cellId[i];
        if (c < 0 || c >= nc) continue;
        const std::size_t k = static_cast<std::size_t>(c);
        const double dvx = s.vx[i] - ux[k];
        const double dvy = s.vy[i] - uy[k];
        s.vx[i] = ux[k] + cosA[k] * dvx - sinA[k] * dvy;
        s.vy[i] = uy[k] + sinA[k] * dvx + cosA[k] * dvy;
    }
    std::vector<double> K(static_cast<std::size_t>(nc), 0.0);
    for (std::size_t i = 0; i < n; ++i) {
        if (s.role[i] != mpcd::kParticleRoleFluid) continue;
        const int c = cellId[i];
        if (c < 0 || c >= nc) continue;
        const std::size_t k = static_cast<std::size_t>(c);
        const double dvx = s.vx[i] - ux[k];
        const double dvy = s.vy[i] - uy[k];
        K[k] += 0.5 * s.mass[i] * (dvx * dvx + dvy * dvy);
    }
    std::vector<double> scale(static_cast<std::size_t>(nc), 1.0);
    for (int c = 0; c < nc; ++c) {
        const std::size_t k = static_cast<std::size_t>(c);
        if (count[k] >= static_cast<unsigned int>(std::max(1, cfg.thermostatMinParticles)) && K[k] > cfg.thermostatEpsilon) {
            const double dof = 2.0 * static_cast<double>(count[k] - 1u);
            const double targetK = 0.5 * dof * cfg.targetKBT;
            scale[k] = std::sqrt(targetK / K[k]);
        }
    }
    for (std::size_t i = 0; i < n; ++i) {
        if (s.role[i] != mpcd::kParticleRoleFluid) continue;
        const int c = cellId[i];
        if (c < 0 || c >= nc) continue;
        const std::size_t k = static_cast<std::size_t>(c);
        s.vx[i] = ux[k] + scale[k] * (s.vx[i] - ux[k]);
        s.vy[i] = uy[k] + scale[k] * (s.vy[i] - uy[k]);
    }
}

} // namespace

int main(int argc, char** argv) {
    const int nx = arg_int(argc, argv, "--nx", 64);
    const int ny = arg_int(argc, argv, "--ny", 64);
    const int gamma = arg_int(argc, argv, "--gamma", 20);
    const int cycles = arg_int(argc, argv, "--cycles", 5);
    const int mixedRoles = arg_int(argc, argv, "--mixed-roles", 1);
    const int variableMass = arg_int(argc, argv, "--variable-mass", 1);
    const int randomSign = arg_int(argc, argv, "--random-sign", 1);
    const double targetKBT = arg_double(argc, argv, "--target-kbt", 1.0e-3);
    const double tolVelocity = arg_double(argc, argv, "--tol-velocity", 1.0e-10);
    const std::uint64_t seed = arg_u64(argc, argv, "--seed", 21900u);

    mpcd::CudaPersistentMpcdStepConfig cfg{};
    cfg.Nx = nx; cfg.Ny = ny; cfg.Lx = 1.0; cfg.Ly = 1.0;
    cfg.randomRotationSign = randomSign;
    cfg.rngSeed = seed ^ 0xa0219ULL;
    cfg.targetKBT = targetKBT;
    cfg.cycles = cycles;

    mpcd::ParticleState cpu = make_state(nx, ny, gamma, mixedRoles, variableMass, seed);
    mpcd::ParticleState shared = cpu;
    mpcd::ParticleState legacy = cpu;

    for (int c = 0; c < cycles; ++c) cpu_cycle(cpu, cfg);

    std::vector<int> legacyCellId, sharedCellId;
    std::vector<std::uint32_t> legacyCount, sharedCount;
    std::vector<double> legacyMass, legacyUx, legacyUy, sharedMass, sharedUx, sharedUy;
    mpcd::ThermostatDiagnostics legacyThermo{}, sharedThermo{};
    const auto legacyDiag = mpcd::cuda_apply_persistent_tg_deposit_src_collision_thermostat(
        legacy, legacyCellId, legacyCount, legacyMass, legacyUx, legacyUy, cfg, &legacyThermo);

    mpcd::CudaParticleState gpuState;
    mpcd::CudaParticleStateDiagnostics particleDiag{};
    gpuState.upload_all(shared, &particleDiag);
    const auto sharedDiag = mpcd::cuda_apply_persistent_tg_deposit_src_collision_thermostat(
        gpuState, shared, sharedCellId, sharedCount, sharedMass, sharedUx, sharedUy, cfg, &sharedThermo);

    mpcd::ParticleState cellShared = cpu;
    // Reset cellShared to the same initial state used by legacy/shared before CPU cycling.
    cellShared = make_state(nx, ny, gamma, mixedRoles, variableMass, seed);
    std::vector<int> cellWsCellId;
    std::vector<std::uint32_t> cellWsCount;
    std::vector<double> cellWsMass, cellWsUx, cellWsUy;
    mpcd::ThermostatDiagnostics cellWsThermo{};
    mpcd::CudaParticleState gpuState2;
    mpcd::CudaParticleStateDiagnostics particleDiag2{};
    gpuState2.upload_all(cellShared, &particleDiag2);
    mpcd::CudaCellWorkspace cellWorkspace;
    mpcd::CudaCellWorkspaceDiagnostics cellWorkspaceDiag{};
    cellWorkspace.ensure_capacity(cellShared.Np, nx * ny, &cellWorkspaceDiag);
    // Second ensure call verifies allocation reuse in the standalone bridge.
    cellWorkspace.ensure_capacity(cellShared.Np, nx * ny, &cellWorkspaceDiag);
    const auto cellWsDiag = mpcd::cuda_apply_persistent_tg_deposit_src_collision_thermostat(
        gpuState2, cellWorkspace, cellShared, cellWsCellId, cellWsCount, cellWsMass, cellWsUx, cellWsUy, cfg, &cellWsThermo);

    double maxAbsVxCpu = 0.0, maxAbsVyCpu = 0.0, maxAbsVxLegacy = 0.0, maxAbsVyLegacy = 0.0;
    double maxAbsVxCellWs = 0.0, maxAbsVyCellWs = 0.0, rms = 0.0;
    std::uint64_t cpuMismatches = 0u, legacyMismatches = 0u, cellWsMismatches = 0u;
    std::uint64_t cellMismatches = 0u, countMismatches = 0u, cellWsCellMismatches = 0u, cellWsCountMismatches = 0u;
    const std::size_t n = static_cast<std::size_t>(cpu.Np);
    for (std::size_t i = 0; i < n; ++i) {
        const double dxv = std::abs(cpu.vx[i] - shared.vx[i]);
        const double dyv = std::abs(cpu.vy[i] - shared.vy[i]);
        const double lxv = std::abs(legacy.vx[i] - shared.vx[i]);
        const double lyv = std::abs(legacy.vy[i] - shared.vy[i]);
        const double cxv = std::abs(cpu.vx[i] - cellShared.vx[i]);
        const double cyv = std::abs(cpu.vy[i] - cellShared.vy[i]);
        maxAbsVxCpu = std::max(maxAbsVxCpu, dxv);
        maxAbsVyCpu = std::max(maxAbsVyCpu, dyv);
        maxAbsVxLegacy = std::max(maxAbsVxLegacy, lxv);
        maxAbsVyLegacy = std::max(maxAbsVyLegacy, lyv);
        maxAbsVxCellWs = std::max(maxAbsVxCellWs, cxv);
        maxAbsVyCellWs = std::max(maxAbsVyCellWs, cyv);
        rms += cxv * cxv + cyv * cyv;
        if (dxv > tolVelocity || dyv > tolVelocity) ++cpuMismatches;
        if (lxv > tolVelocity || lyv > tolVelocity) ++legacyMismatches;
        if (cxv > tolVelocity || cyv > tolVelocity) ++cellWsMismatches;
        if (legacyCellId.size() == sharedCellId.size() && legacyCellId[i] != sharedCellId[i]) ++cellMismatches;
        if (legacyCellId.size() == cellWsCellId.size() && legacyCellId[i] != cellWsCellId[i]) ++cellWsCellMismatches;
    }
    if (legacyCount.size() == sharedCount.size()) {
        for (std::size_t c = 0; c < legacyCount.size(); ++c) {
            if (legacyCount[c] != sharedCount[c]) ++countMismatches;
        }
    } else {
        countMismatches = 1u;
    }
    if (legacyCount.size() == cellWsCount.size()) {
        for (std::size_t c = 0; c < legacyCount.size(); ++c) {
            if (legacyCount[c] != cellWsCount[c]) ++cellWsCountMismatches;
        }
    } else {
        cellWsCountMismatches = 1u;
    }
    rms = std::sqrt(rms / std::max<std::size_t>(1u, 2u * n));

    const bool pass = cpuMismatches == 0u && legacyMismatches == 0u && cellWsMismatches == 0u &&
                      cellMismatches == 0u && countMismatches == 0u &&
                      cellWsCellMismatches == 0u && cellWsCountMismatches == 0u &&
                      sharedDiag.invalidCellParticles == 0u && cellWsDiag.invalidCellParticles == 0u;
    std::cout << std::setprecision(17)
              << "CUDA_PERSISTENT_CELL_WORKSPACE_BRIDGE_0224 " << (pass ? "PASS" : "FAIL")
              << " Nx=" << nx << " Ny=" << ny << " gamma=" << gamma
              << " cycles=" << cycles
              << " particles=" << n
              << " allocationCalls=" << particleDiag.allocationCalls
              << " reusedAllocation=" << particleDiag.reusedAllocation
              << " particleUploadSeconds=" << particleDiag.uploadSeconds
              << " sharedStepUploadSeconds=" << sharedDiag.uploadSeconds
              << " sharedKernelSeconds=" << sharedDiag.kernelSeconds
              << " sharedDownloadSeconds=" << sharedDiag.downloadSeconds
              << " sharedTotalSeconds=" << sharedDiag.totalSeconds
              << " cellWorkspaceAllocationCalls=" << cellWorkspaceDiag.allocationCalls
              << " cellWorkspaceReusedAllocation=" << cellWorkspaceDiag.reusedAllocation
              << " cellWorkspaceAllocateSeconds=" << cellWorkspaceDiag.allocateSeconds
              << " cellWorkspaceTotalSeconds=" << cellWorkspaceDiag.totalSeconds
              << " cellWorkspaceStepUploadSeconds=" << cellWsDiag.uploadSeconds
              << " cellWorkspaceKernelSeconds=" << cellWsDiag.kernelSeconds
              << " cellWorkspaceDownloadSeconds=" << cellWsDiag.downloadSeconds
              << " cellWorkspaceTotalStepSeconds=" << cellWsDiag.totalSeconds
              << " legacyTotalSeconds=" << legacyDiag.totalSeconds
              << " invalidCellParticles=" << sharedDiag.invalidCellParticles
              << " cellWorkspaceInvalidCellParticles=" << cellWsDiag.invalidCellParticles
              << " cpuVelocityMismatches=" << cpuMismatches
              << " legacyVelocityMismatches=" << legacyMismatches
              << " cellWorkspaceVelocityMismatches=" << cellWsMismatches
              << " cellIdMismatches=" << cellMismatches
              << " countMismatches=" << countMismatches
              << " cellWorkspaceCellIdMismatches=" << cellWsCellMismatches
              << " cellWorkspaceCountMismatches=" << cellWsCountMismatches
              << " maxAbsVxCpu=" << maxAbsVxCpu
              << " maxAbsVyCpu=" << maxAbsVyCpu
              << " maxAbsVxLegacy=" << maxAbsVxLegacy
              << " maxAbsVyLegacy=" << maxAbsVyLegacy
              << " maxAbsVxCellWorkspace=" << maxAbsVxCellWs
              << " maxAbsVyCellWorkspace=" << maxAbsVyCellWs
              << " rmsCpu=" << rms
              << " thermostatKBTAfter=" << cellWsThermo.kBTAfter
              << '\n';
    return pass ? 0 : 1;
}
