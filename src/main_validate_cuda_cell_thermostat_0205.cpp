#include "cuda_cell_thermostat.h"
#include "cell_grid.h"
#include "particle_state.h"
#include "simulation_params.h"
#include "thermostat.h"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstdlib>
#include <iomanip>
#include <iostream>
#include <limits>
#include <random>
#include <stdexcept>
#include <string>
#include <vector>

namespace mpcd {
namespace {

struct Args {
    int Nx = 64;
    int Ny = 64;
    int gamma = 20;
    int mixedRoles = 1;
    int variableMass = 1;
    double targetKBT = 1.0e-3;
    double tolVelocity = 1.0e-10;
    double tolDiag = 1.0e-10;
    std::uint64_t seed = 205u;
};

int parse_int(const char* s) { return std::stoi(std::string(s)); }
double parse_double(const char* s) { return std::stod(std::string(s)); }
std::uint64_t parse_u64(const char* s) { return static_cast<std::uint64_t>(std::stoull(std::string(s))); }

Args parse_args(int argc, char** argv) {
    Args a{};
    for (int i = 1; i < argc; ++i) {
        const std::string k = argv[i];
        auto need = [&](const char* name) -> const char* {
            if (i + 1 >= argc) throw std::runtime_error(std::string("missing value after ") + name);
            return argv[++i];
        };
        if (k == "--nx") a.Nx = parse_int(need("--nx"));
        else if (k == "--ny") a.Ny = parse_int(need("--ny"));
        else if (k == "--gamma") a.gamma = parse_int(need("--gamma"));
        else if (k == "--mixed-roles") a.mixedRoles = parse_int(need("--mixed-roles"));
        else if (k == "--variable-mass") a.variableMass = parse_int(need("--variable-mass"));
        else if (k == "--target-kbt") a.targetKBT = parse_double(need("--target-kbt"));
        else if (k == "--tol-velocity") a.tolVelocity = parse_double(need("--tol-velocity"));
        else if (k == "--tol-diag") a.tolDiag = parse_double(need("--tol-diag"));
        else if (k == "--seed") a.seed = parse_u64(need("--seed"));
        else throw std::runtime_error("unknown argument: " + k);
    }
    if (a.Nx <= 0 || a.Ny <= 0 || a.gamma <= 0) throw std::runtime_error("invalid grid/gamma");
    return a;
}

ParticleState make_state(const Args& a, CellGrid& grid, std::vector<int>& cellId) {
    grid.Nx = a.Nx;
    grid.Ny = a.Ny;
    grid.numCells = a.Nx * a.Ny;
    grid.Lx = 1.0;
    grid.Ly = 1.0;
    grid.dx = grid.Lx / static_cast<double>(grid.Nx);
    grid.dy = grid.Ly / static_cast<double>(grid.Ny);
    const std::uint64_t n64 = static_cast<std::uint64_t>(grid.numCells) * static_cast<std::uint64_t>(a.gamma);
    const std::size_t n = static_cast<std::size_t>(n64);

    ParticleState s{};
    s.Np = n64;
    s.dim = 2;
    s.x.resize(n);
    s.y.resize(n);
    s.vx.resize(n);
    s.vy.resize(n);
    s.type.assign(n, 0u);
    s.mass.resize(n);
    s.role.assign(n, kParticleRoleFluid);
    cellId.resize(n);

    std::mt19937_64 rng(a.seed);
    std::uniform_real_distribution<double> jitter(-0.45, 0.45);
    std::normal_distribution<double> noise(0.0, std::sqrt(a.targetKBT));

    std::size_t p = 0;
    constexpr double pi = 3.141592653589793238462643383279502884;
    for (int iy = 0; iy < grid.Ny; ++iy) {
        for (int ix = 0; ix < grid.Nx; ++ix) {
            const int c = ix + grid.Nx * iy;
            const double cx = (static_cast<double>(ix) + 0.5) * grid.dx;
            const double cy = (static_cast<double>(iy) + 0.5) * grid.dy;
            const double meanUx = 0.05 * std::sin(2.0 * pi * cx) * std::cos(2.0 * pi * cy);
            const double meanUy = -0.05 * std::cos(2.0 * pi * cx) * std::sin(2.0 * pi * cy);
            for (int g = 0; g < a.gamma; ++g) {
                s.x[p] = std::clamp(cx + jitter(rng) * grid.dx, 0.0, std::nextafter(1.0, 0.0));
                s.y[p] = std::clamp(cy + jitter(rng) * grid.dy, 0.0, std::nextafter(1.0, 0.0));
                s.vx[p] = meanUx + 1.35 * noise(rng);
                s.vy[p] = meanUy + 0.75 * noise(rng);
                s.mass[p] = a.variableMass ? (1.0 + 0.05 * static_cast<double>((p * 17u + 3u) % 7u)) : 1.0;
                if (a.mixedRoles) {
                    const std::uint64_t r = (static_cast<std::uint64_t>(p) * 1103515245ull + 12345ull) % 101ull;
                    if (r < 3ull) s.role[p] = kParticleRoleInactive;
                    else if (r < 7ull) s.role[p] = kParticleRoleLatent;
                }
                cellId[p] = c;
                ++p;
            }
        }
    }
    validate_particle_state(s, "make_state");
    return s;
}

struct Moments {
    std::vector<std::uint32_t> count;
    std::vector<double> mass;
    std::vector<double> ux;
    std::vector<double> uy;
};

Moments compute_moments(const ParticleState& s, int numCells, const std::vector<int>& cellId) {
    Moments m{};
    m.count.assign(static_cast<std::size_t>(numCells), 0u);
    m.mass.assign(static_cast<std::size_t>(numCells), 0.0);
    m.ux.assign(static_cast<std::size_t>(numCells), 0.0);
    m.uy.assign(static_cast<std::size_t>(numCells), 0.0);
    std::vector<double> px(static_cast<std::size_t>(numCells), 0.0);
    std::vector<double> py(static_cast<std::size_t>(numCells), 0.0);
    const std::size_t n = static_cast<std::size_t>(s.Np);
    for (std::size_t i = 0; i < n; ++i) {
        if (!is_fluid_particle(s, i)) continue;
        const int c = cellId[i];
        if (c < 0 || c >= numCells) continue;
        const std::size_t k = static_cast<std::size_t>(c);
        const double mm = s.mass[i];
        m.count[k] += 1u;
        m.mass[k] += mm;
        px[k] += mm * s.vx[i];
        py[k] += mm * s.vy[i];
    }
    for (int c = 0; c < numCells; ++c) {
        const std::size_t k = static_cast<std::size_t>(c);
        if (m.mass[k] > 0.0) {
            m.ux[k] = px[k] / m.mass[k];
            m.uy[k] = py[k] / m.mass[k];
        }
    }
    return m;
}

double absdiff(double a, double b) { return std::abs(a - b); }

} // namespace
} // namespace mpcd

int main(int argc, char** argv) {
    using namespace mpcd;
    try {
        const Args args = parse_args(argc, argv);
        CellGrid grid{};
        std::vector<int> cellId;
        ParticleState initial = make_state(args, grid, cellId);
        ParticleState cpu = initial;
        ParticleState gpu = initial;
        const Moments moments = compute_moments(initial, grid.numCells, cellId);

        SimulationParams params{};
        params.thermostatEnable = true;
        params.thermostatMode = "cell_relative_rescale";
        params.thermostatEvery = 1;
        params.thermostatTargetKBT = args.targetKBT;
        params.kBT = args.targetKBT;
        params.thermostatMinParticles = 3;
        params.thermostatEpsilon = 1.0e-30;

        ThermostatWorkspace ws;
        ThermostatDiagnostics cpuDiag = apply_cell_relative_rescale_thermostat(cpu, params, grid, cellId, 0u, ws);

        CudaCellThermostatDiagnostics cudaDiag{};
        CudaCellThermostatOptions opts{};
        ThermostatDiagnostics gpuDiag = cuda_apply_cell_relative_rescale_thermostat_from_moments(
            gpu, grid.numCells, cellId, moments.count, moments.ux, moments.uy,
            args.targetKBT, params.thermostatMinParticles, params.thermostatEpsilon,
            &cudaDiag, opts);

        double maxAbsVx = 0.0;
        double maxAbsVy = 0.0;
        double rmsV = 0.0;
        std::uint64_t mismatches = 0u;
        const std::size_t n = static_cast<std::size_t>(initial.Np);
        for (std::size_t i = 0; i < n; ++i) {
            const double dx = absdiff(cpu.vx[i], gpu.vx[i]);
            const double dy = absdiff(cpu.vy[i], gpu.vy[i]);
            maxAbsVx = std::max(maxAbsVx, dx);
            maxAbsVy = std::max(maxAbsVy, dy);
            rmsV += dx * dx + dy * dy;
            if (dx > args.tolVelocity || dy > args.tolVelocity) ++mismatches;
        }
        rmsV = std::sqrt(rmsV / std::max<std::size_t>(1u, n));

        const double maxDiagDiff = std::max({
            absdiff(cpuDiag.kBTBefore, gpuDiag.kBTBefore),
            absdiff(cpuDiag.kBTAfter, gpuDiag.kBTAfter),
            absdiff(cpuDiag.scaleMean, gpuDiag.scaleMean),
            absdiff(cpuDiag.scaleMin, gpuDiag.scaleMin),
            absdiff(cpuDiag.scaleMax, gpuDiag.scaleMax),
            absdiff(static_cast<double>(cpuDiag.cellsRescaled), static_cast<double>(gpuDiag.cellsRescaled)),
            absdiff(static_cast<double>(cpuDiag.particlesRescaled), static_cast<double>(gpuDiag.particlesRescaled))
        });

        const bool pass = mismatches == 0u && maxDiagDiff <= args.tolDiag;
        std::cout << std::setprecision(17)
                  << "CUDA_CELL_THERMOSTAT_0205 " << (pass ? "PASS" : "FAIL")
                  << " Nx=" << args.Nx
                  << " Ny=" << args.Ny
                  << " gamma=" << args.gamma
                  << " particles=" << initial.Np
                  << " fluidParticles=" << cudaDiag.fluidParticles
                  << " cellsRescaled=" << gpuDiag.cellsRescaled
                  << " particlesRescaled=" << gpuDiag.particlesRescaled
                  << " maxAbsVx=" << maxAbsVx
                  << " maxAbsVy=" << maxAbsVy
                  << " rmsV=" << rmsV
                  << " velocityMismatches=" << mismatches
                  << " maxDiagDiff=" << maxDiagDiff
                  << " cpuKBTBefore=" << cpuDiag.kBTBefore
                  << " gpuKBTBefore=" << gpuDiag.kBTBefore
                  << " cpuKBTAfter=" << cpuDiag.kBTAfter
                  << " gpuKBTAfter=" << gpuDiag.kBTAfter
                  << " uploadSeconds=" << cudaDiag.uploadSeconds
                  << " kineticKernelSeconds=" << cudaDiag.kineticKernelSeconds
                  << " scaleKernelSeconds=" << cudaDiag.scaleKernelSeconds
                  << " applyKernelSeconds=" << cudaDiag.applyKernelSeconds
                  << " downloadSeconds=" << cudaDiag.downloadSeconds
                  << " totalSeconds=" << cudaDiag.totalSeconds
                  << "\n";
        return pass ? 0 : 1;
    } catch (const std::exception& e) {
        std::cerr << "CUDA_CELL_THERMOSTAT_0205 ERROR: " << e.what() << "\n";
        return 2;
    }
}
