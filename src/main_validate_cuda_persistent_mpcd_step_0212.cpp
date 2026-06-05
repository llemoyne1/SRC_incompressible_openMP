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
        s.x[static_cast<std::size_t>(i)] = U(rng);
        s.y[static_cast<std::size_t>(i)] = U(rng);
        // Smooth bulk flow plus thermal fluctuations to make both collision and thermostat non-trivial.
        const double x = s.x[static_cast<std::size_t>(i)];
        const double y = s.y[static_cast<std::size_t>(i)];
        s.vx[static_cast<std::size_t>(i)] = 0.05 * std::sin(6.2831853071795864769 * y) + 0.03 * N(rng);
        s.vy[static_cast<std::size_t>(i)] = -0.05 * std::sin(6.2831853071795864769 * x) + 0.03 * N(rng);
        s.mass[static_cast<std::size_t>(i)] = variableMass ? (1.0 + 0.05 * static_cast<double>(i % 7)) : 1.0;
        if (mixedRoles) {
            const std::uint64_t h = splitmix64(seed ^ static_cast<std::uint64_t>(i));
            if ((h % 97u) == 0u) s.role[static_cast<std::size_t>(i)] = mpcd::kParticleRoleInactive;
            else if ((h % 43u) == 0u) s.role[static_cast<std::size_t>(i)] = mpcd::kParticleRoleLatent;
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
            const std::uint64_t h = splitmix64(cfg.rngSeed ^ static_cast<std::uint64_t>(c));
            if ((h & 1ULL) == 0ULL) sinA[static_cast<std::size_t>(c)] = -sinA[static_cast<std::size_t>(c)];
        }
    }

    for (std::size_t i = 0; i < n; ++i) {
        if (s.role[i] != mpcd::kParticleRoleFluid) continue;
        const int ix = periodic_index(s.x[i], cfg.Lx, dx, cfg.Nx);
        const int iy = periodic_index(s.y[i], cfg.Ly, dy, cfg.Ny);
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
        if (mass[k] > 0.0) {
            ux[k] = px[k] / mass[k];
            uy[k] = py[k] / mass[k];
        }
    }
    for (std::size_t i = 0; i < n; ++i) {
        if (s.role[i] != mpcd::kParticleRoleFluid) continue;
        const int c = cellId[i];
        if (c < 0 || c >= nc) continue;
        const std::size_t k = static_cast<std::size_t>(c);
        const double dvx = s.vx[i] - ux[k];
        const double dvy = s.vy[i] - uy[k];
        const double vx = ux[k] + cosA[k] * dvx - sinA[k] * dvy;
        const double vy = uy[k] + sinA[k] * dvx + cosA[k] * dvy;
        s.vx[i] = vx; s.vy[i] = vy;
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
        const double sc = scale[k];
        s.vx[i] = ux[k] + sc * (s.vx[i] - ux[k]);
        s.vy[i] = uy[k] + sc * (s.vy[i] - uy[k]);
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
    const std::uint64_t seed = arg_u64(argc, argv, "--seed", 21200u);

    mpcd::CudaPersistentMpcdStepConfig cfg{};
    cfg.Nx = nx; cfg.Ny = ny; cfg.Lx = 1.0; cfg.Ly = 1.0;
    cfg.randomRotationSign = randomSign;
    cfg.rngSeed = seed ^ 0xa0212ULL;
    cfg.targetKBT = targetKBT;
    cfg.cycles = cycles;

    mpcd::ParticleState cpu = make_state(nx, ny, gamma, mixedRoles, variableMass, seed);
    mpcd::ParticleState gpu = cpu;

    for (int c = 0; c < cycles; ++c) cpu_cycle(cpu, cfg);
    const auto diag = mpcd::cuda_apply_persistent_tg_deposit_src_thermostat(gpu, cfg);

    double maxAbsVx = 0.0, maxAbsVy = 0.0, rms = 0.0;
    std::uint64_t mismatches = 0u, fluid = 0u;
    const std::size_t n = static_cast<std::size_t>(cpu.Np);
    for (std::size_t i = 0; i < n; ++i) {
        if (cpu.role[i] == mpcd::kParticleRoleFluid) ++fluid;
        const double dxv = std::abs(cpu.vx[i] - gpu.vx[i]);
        const double dyv = std::abs(cpu.vy[i] - gpu.vy[i]);
        maxAbsVx = std::max(maxAbsVx, dxv);
        maxAbsVy = std::max(maxAbsVy, dyv);
        rms += dxv * dxv + dyv * dyv;
        if (dxv > tolVelocity || dyv > tolVelocity) ++mismatches;
    }
    rms = std::sqrt(rms / std::max<std::size_t>(1u, 2u * n));

    const bool pass = mismatches == 0u && diag.invalidCellParticles == 0u;
    std::cout << std::setprecision(17)
              << "CUDA_PERSISTENT_MPCD_STEP_0212 " << (pass ? "PASS" : "FAIL")
              << " Nx=" << nx << " Ny=" << ny << " gamma=" << gamma
              << " cycles=" << cycles
              << " particles=" << n
              << " fluidParticles=" << fluid
              << " gpuFluidParticlesPerCycle=" << diag.fluidParticles
              << " particlesRotatedTotal=" << diag.particlesRotated
              << " invalidCellParticles=" << diag.invalidCellParticles
              << " maxAbsVx=" << maxAbsVx
              << " maxAbsVy=" << maxAbsVy
              << " rmsV=" << rms
              << " velocityMismatches=" << mismatches
              << " uploadSeconds=" << diag.uploadSeconds
              << " kernelSeconds=" << diag.kernelSeconds
              << " downloadSeconds=" << diag.downloadSeconds
              << " totalSeconds=" << diag.totalSeconds
              << '\n';
    return pass ? 0 : 1;
}
