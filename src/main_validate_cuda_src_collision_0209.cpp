#include "cuda_src_collision.h"

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

struct Args {
    int nx = 64;
    int ny = 64;
    int gamma = 20;
    int mixedRoles = 1;
    int variableMass = 1;
    int randomSign = 1;
    double angle = 2.0943951023931954923; // 120 degrees
    double tolVelocity = 1e-12;
    double tolMomentum = 1e-10;
    double tolEnergy = 1e-10;
    std::uint64_t seed = 20900u;
};

std::uint64_t splitmix64(std::uint64_t x) {
    x += 0x9e3779b97f4a7c15ULL;
    x = (x ^ (x >> 30U)) * 0xbf58476d1ce4e5b9ULL;
    x = (x ^ (x >> 27U)) * 0x94d049bb133111ebULL;
    return x ^ (x >> 31U);
}

Args parse_args(int argc, char** argv) {
    Args a;
    for (int i = 1; i < argc; ++i) {
        const std::string k(argv[i]);
        auto need = [&](const char* name) -> const char* {
            if (i + 1 >= argc) throw std::runtime_error(std::string("missing value for ") + name);
            return argv[++i];
        };
        if (k == "--nx") a.nx = std::stoi(need("--nx"));
        else if (k == "--ny") a.ny = std::stoi(need("--ny"));
        else if (k == "--gamma") a.gamma = std::stoi(need("--gamma"));
        else if (k == "--mixed-roles") a.mixedRoles = std::stoi(need("--mixed-roles"));
        else if (k == "--variable-mass") a.variableMass = std::stoi(need("--variable-mass"));
        else if (k == "--random-sign") a.randomSign = std::stoi(need("--random-sign"));
        else if (k == "--angle") a.angle = std::stod(need("--angle"));
        else if (k == "--tol-velocity") a.tolVelocity = std::stod(need("--tol-velocity"));
        else if (k == "--tol-momentum") a.tolMomentum = std::stod(need("--tol-momentum"));
        else if (k == "--tol-energy") a.tolEnergy = std::stod(need("--tol-energy"));
        else if (k == "--seed") a.seed = static_cast<std::uint64_t>(std::stoull(need("--seed")));
        else throw std::runtime_error("unknown argument: " + k);
    }
    if (a.nx <= 0 || a.ny <= 0 || a.gamma <= 0) throw std::runtime_error("invalid grid/gamma");
    return a;
}

bool is_fluid(const mpcd::ParticleState& s, std::size_t i) {
    return s.role.empty() || s.role[i] == mpcd::kParticleRoleFluid;
}

struct CellStats {
    std::vector<std::uint32_t> count;
    std::vector<double> mass;
    std::vector<double> px;
    std::vector<double> py;
    std::vector<double> ux;
    std::vector<double> uy;
    std::vector<double> kineticRel;
};

CellStats compute_stats(const mpcd::ParticleState& state,
                        const std::vector<int>& cellId,
                        int numCells,
                        const std::vector<double>* fixedUx = nullptr,
                        const std::vector<double>* fixedUy = nullptr) {
    CellStats st;
    st.count.assign(static_cast<std::size_t>(numCells), 0u);
    st.mass.assign(static_cast<std::size_t>(numCells), 0.0);
    st.px.assign(static_cast<std::size_t>(numCells), 0.0);
    st.py.assign(static_cast<std::size_t>(numCells), 0.0);
    st.ux.assign(static_cast<std::size_t>(numCells), 0.0);
    st.uy.assign(static_cast<std::size_t>(numCells), 0.0);
    st.kineticRel.assign(static_cast<std::size_t>(numCells), 0.0);

    const std::size_t n = static_cast<std::size_t>(state.Np);
    for (std::size_t i = 0; i < n; ++i) {
        if (!is_fluid(state, i)) continue;
        const int c = cellId[i];
        if (c < 0 || c >= numCells) continue;
        const std::size_t k = static_cast<std::size_t>(c);
        const double m = state.mass[i];
        st.count[k] += 1u;
        st.mass[k] += m;
        st.px[k] += m * state.vx[i];
        st.py[k] += m * state.vy[i];
    }
    for (int c = 0; c < numCells; ++c) {
        const std::size_t k = static_cast<std::size_t>(c);
        if (fixedUx && fixedUy) {
            st.ux[k] = (*fixedUx)[k];
            st.uy[k] = (*fixedUy)[k];
        } else if (st.mass[k] > 0.0) {
            st.ux[k] = st.px[k] / st.mass[k];
            st.uy[k] = st.py[k] / st.mass[k];
        }
    }
    for (std::size_t i = 0; i < n; ++i) {
        if (!is_fluid(state, i)) continue;
        const int c = cellId[i];
        if (c < 0 || c >= numCells) continue;
        const std::size_t k = static_cast<std::size_t>(c);
        const double dvx = state.vx[i] - st.ux[k];
        const double dvy = state.vy[i] - st.uy[k];
        st.kineticRel[k] += 0.5 * state.mass[i] * (dvx * dvx + dvy * dvy);
    }
    return st;
}

void apply_cpu_src_collision(mpcd::ParticleState& state,
                             int numCells,
                             const std::vector<int>& cellId,
                             const std::vector<double>& cellUx,
                             const std::vector<double>& cellUy,
                             const std::vector<double>& cosA,
                             const std::vector<double>& sinA) {
    const std::size_t n = static_cast<std::size_t>(state.Np);
    for (std::size_t i = 0; i < n; ++i) {
        if (!is_fluid(state, i)) continue;
        const int c = cellId[i];
        if (c < 0 || c >= numCells) continue;
        const std::size_t k = static_cast<std::size_t>(c);
        const double ux = cellUx[k];
        const double uy = cellUy[k];
        const double dvx = state.vx[i] - ux;
        const double dvy = state.vy[i] - uy;
        const double ca = cosA[k];
        const double sa = sinA[k];
        state.vx[i] = ux + ca * dvx - sa * dvy;
        state.vy[i] = uy + sa * dvx + ca * dvy;
    }
}

} // namespace

int main(int argc, char** argv) {
    try {
        const Args args = parse_args(argc, argv);
        const int numCells = args.nx * args.ny;
        const std::size_t n = static_cast<std::size_t>(numCells) * static_cast<std::size_t>(args.gamma);

        std::mt19937_64 rng(args.seed);
        std::uniform_real_distribution<double> pos01(0.0, 1.0);
        std::normal_distribution<double> velDist(0.0, 0.04);

        mpcd::ParticleState initial;
        initial.Np = static_cast<std::uint64_t>(n);
        initial.dim = 2;
        initial.x.resize(n);
        initial.y.resize(n);
        initial.vx.resize(n);
        initial.vy.resize(n);
        initial.type.assign(n, 0u);
        initial.mass.resize(n);
        initial.role.assign(n, mpcd::kParticleRoleFluid);
        std::vector<int> cellId(n, -1);

        std::uint64_t fluidParticles = 0u;
        for (std::size_t i = 0; i < n; ++i) {
            const int c = static_cast<int>((i * 1103515245ull + 12345ull + args.seed) % static_cast<std::uint64_t>(numCells));
            cellId[i] = c;
            const int ix = c % args.nx;
            const int iy = c / args.nx;
            initial.x[i] = (static_cast<double>(ix) + pos01(rng)) / static_cast<double>(args.nx);
            initial.y[i] = (static_cast<double>(iy) + pos01(rng)) / static_cast<double>(args.ny);
            initial.vx[i] = 0.02 * std::sin(0.1 * static_cast<double>(ix)) + velDist(rng);
            initial.vy[i] = 0.02 * std::cos(0.1 * static_cast<double>(iy)) + velDist(rng);
            initial.mass[i] = args.variableMass ? (1.0 + 0.02 * static_cast<double>((i % 11u))) : 1.0;
            if (args.mixedRoles) {
                if ((i % 37u) == 0u) initial.role[i] = mpcd::kParticleRoleInactive;
                else if ((i % 29u) == 0u) initial.role[i] = mpcd::kParticleRoleLatent;
            }
            if (initial.role[i] == mpcd::kParticleRoleFluid) ++fluidParticles;
        }

        const CellStats before = compute_stats(initial, cellId, numCells);
        std::vector<double> cosA(static_cast<std::size_t>(numCells), std::cos(args.angle));
        std::vector<double> sinA(static_cast<std::size_t>(numCells), std::sin(args.angle));
        if (args.randomSign) {
            for (int c = 0; c < numCells; ++c) {
                const std::uint64_t h = splitmix64(args.seed ^ static_cast<std::uint64_t>(c));
                if ((h & 1ull) == 0ull) sinA[static_cast<std::size_t>(c)] = -sinA[static_cast<std::size_t>(c)];
            }
        }

        mpcd::ParticleState cpuState = initial;
        mpcd::ParticleState gpuState = initial;
        apply_cpu_src_collision(cpuState, numCells, cellId, before.ux, before.uy, cosA, sinA);
        mpcd::CudaSrcCollisionDiagnostics cudaDiag = mpcd::cuda_apply_src_collision_from_cell_moments(
            gpuState, numCells, cellId, before.ux, before.uy, cosA, sinA);

        double maxAbsVx = 0.0;
        double maxAbsVy = 0.0;
        double sumSq = 0.0;
        std::uint64_t velocityMismatches = 0u;
        for (std::size_t i = 0; i < n; ++i) {
            const double dx = std::abs(cpuState.vx[i] - gpuState.vx[i]);
            const double dy = std::abs(cpuState.vy[i] - gpuState.vy[i]);
            maxAbsVx = std::max(maxAbsVx, dx);
            maxAbsVy = std::max(maxAbsVy, dy);
            sumSq += dx * dx + dy * dy;
            if (dx > args.tolVelocity || dy > args.tolVelocity) ++velocityMismatches;
        }
        const double rmsV = std::sqrt(sumSq / std::max<double>(1.0, 2.0 * static_cast<double>(n)));

        const CellStats cpuAfter = compute_stats(cpuState, cellId, numCells, &before.ux, &before.uy);
        const CellStats gpuAfter = compute_stats(gpuState, cellId, numCells, &before.ux, &before.uy);
        double maxCpuMomentumDrift = 0.0;
        double maxGpuMomentumDrift = 0.0;
        double maxCpuEnergyDrift = 0.0;
        double maxGpuEnergyDrift = 0.0;
        double maxCpuGpuMomentumDiff = 0.0;
        double maxCpuGpuEnergyDiff = 0.0;
        for (int c = 0; c < numCells; ++c) {
            const std::size_t k = static_cast<std::size_t>(c);
            const double cpuDpx = cpuAfter.px[k] - before.px[k];
            const double cpuDpy = cpuAfter.py[k] - before.py[k];
            const double gpuDpx = gpuAfter.px[k] - before.px[k];
            const double gpuDpy = gpuAfter.py[k] - before.py[k];
            maxCpuMomentumDrift = std::max(maxCpuMomentumDrift, std::sqrt(cpuDpx * cpuDpx + cpuDpy * cpuDpy));
            maxGpuMomentumDrift = std::max(maxGpuMomentumDrift, std::sqrt(gpuDpx * gpuDpx + gpuDpy * gpuDpy));
            const double dpx = cpuAfter.px[k] - gpuAfter.px[k];
            const double dpy = cpuAfter.py[k] - gpuAfter.py[k];
            maxCpuGpuMomentumDiff = std::max(maxCpuGpuMomentumDiff, std::sqrt(dpx * dpx + dpy * dpy));
            maxCpuEnergyDrift = std::max(maxCpuEnergyDrift, std::abs(cpuAfter.kineticRel[k] - before.kineticRel[k]));
            maxGpuEnergyDrift = std::max(maxGpuEnergyDrift, std::abs(gpuAfter.kineticRel[k] - before.kineticRel[k]));
            maxCpuGpuEnergyDiff = std::max(maxCpuGpuEnergyDiff, std::abs(cpuAfter.kineticRel[k] - gpuAfter.kineticRel[k]));
        }

        const bool pass = velocityMismatches == 0u &&
                          maxCpuGpuMomentumDiff <= args.tolMomentum &&
                          maxCpuGpuEnergyDiff <= args.tolEnergy &&
                          cudaDiag.invalidCellParticles == 0u &&
                          cudaDiag.particlesRotated == fluidParticles;

        std::cout << std::setprecision(17)
                  << "CUDA_SRC_COLLISION_0209 " << (pass ? "PASS" : "FAIL")
                  << " Nx=" << args.nx
                  << " Ny=" << args.ny
                  << " gamma=" << args.gamma
                  << " mixedRoles=" << args.mixedRoles
                  << " variableMass=" << args.variableMass
                  << " randomSign=" << args.randomSign
                  << " particles=" << n
                  << " fluidParticles=" << fluidParticles
                  << " particlesRotated=" << cudaDiag.particlesRotated
                  << " invalidCellParticles=" << cudaDiag.invalidCellParticles
                  << " maxAbsVx=" << maxAbsVx
                  << " maxAbsVy=" << maxAbsVy
                  << " rmsV=" << rmsV
                  << " velocityMismatches=" << velocityMismatches
                  << " maxCpuMomentumDrift=" << maxCpuMomentumDrift
                  << " maxGpuMomentumDrift=" << maxGpuMomentumDrift
                  << " maxCpuGpuMomentumDiff=" << maxCpuGpuMomentumDiff
                  << " maxCpuEnergyDrift=" << maxCpuEnergyDrift
                  << " maxGpuEnergyDrift=" << maxGpuEnergyDrift
                  << " maxCpuGpuEnergyDiff=" << maxCpuGpuEnergyDiff
                  << " uploadSeconds=" << cudaDiag.uploadSeconds
                  << " kernelSeconds=" << cudaDiag.kernelSeconds
                  << " downloadSeconds=" << cudaDiag.downloadSeconds
                  << " totalSeconds=" << cudaDiag.totalSeconds
                  << "\n";
        return pass ? 0 : 1;
    } catch (const std::exception& e) {
        std::cerr << "CUDA_SRC_COLLISION_0209 ERROR " << e.what() << "\n";
        return 2;
    }
}
