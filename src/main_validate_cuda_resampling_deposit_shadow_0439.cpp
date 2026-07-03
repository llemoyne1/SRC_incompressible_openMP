#include "cell_grid.h"
#include "cuda_cell_moments.h"
#include "cuda_cell_workspace.h"
#include "cuda_particle_state.h"
#include "fluid_domain.h"
#include "particle_state.h"
#include "simulation_params.h"
#include "weighted_resampling.h"

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

// 0439 standalone validator support.
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

struct GpuDerivedDeposit0439 {
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
    p.resamplingEnable = false;
    p.resamplingExtractionEnable = false;
    p.resamplingInsertionEnable = false;
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
    mpcd::validate_particle_state(s, "make_periodic_state_0439");
    mpcd::validate_active_fluid_prefix(s, "make_periodic_state_0439");
    return s;
}

GpuDerivedDeposit0439 derive_gpu_diagnostics(const mpcd::CudaCellMoments& gpu,
                                             const mpcd::SimulationParams& params,
                                             const mpcd::CellGrid& grid,
                                             std::uint64_t nFluid) {
    GpuDerivedDeposit0439 d{};
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

struct CompareResult0439 {
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
    double kernelSeconds = 0.0;
    double downloadSeconds = 0.0;
    double totalSeconds = 0.0;
};

CompareResult0439 run_one(const std::string& caseName,
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
        state, params, grid, domain, 0.0, shift, cpuWs, false,
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

    GpuDerivedDeposit0439 gd = derive_gpu_diagnostics(gpu, params, grid, state.NactiveFluid);

    CompareResult0439 r{};
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
    r.kernelSeconds = gpuDiag.kernelSeconds;
    r.downloadSeconds = gpuDiag.downloadSeconds;
    r.totalSeconds = gpuDiag.totalSeconds;

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
    std::cout << "case,massMode,shiftX,shiftY,pass,n,cells,cellIdMismatch,maxCountDiff,maxMassAbs,maxPxAbs,maxPyAbs,maxUxAbs,maxUyAbs,poorCpu,poorGpu,richCpu,richGpu,cpuTotalMass,gpuTotalMass,cpuTotalPx,gpuTotalPx,cpuTotalPy,gpuTotalPy,kernelSeconds,downloadSeconds,totalSeconds\n";
}

void print_csv_row(const CompareResult0439& r) {
    std::cout << std::setprecision(17)
              << r.caseName << ',' << r.massMode << ',' << r.shiftX << ',' << r.shiftY << ','
              << r.pass << ',' << r.n << ',' << r.cells << ',' << r.cellIdMismatch << ','
              << r.maxCountDiff << ',' << r.maxMassAbs << ',' << r.maxPxAbs << ',' << r.maxPyAbs << ','
              << r.maxUxAbs << ',' << r.maxUyAbs << ',' << r.poorCpu << ',' << r.poorGpu << ','
              << r.richCpu << ',' << r.richGpu << ',' << r.cpuTotalMass << ',' << r.gpuTotalMass << ','
              << r.cpuTotalPx << ',' << r.gpuTotalPx << ',' << r.cpuTotalPy << ',' << r.gpuTotalPy << ','
              << r.kernelSeconds << ',' << r.downloadSeconds << ',' << r.totalSeconds << '\n';
}

} // namespace

int main() {
    try {
        if (!mpcd::cuda_particle_state_available() || !mpcd::cuda_cell_moments_available()) {
            std::cerr << "CUDA_RESAMPLING_DEPOSIT_SHADOW_0439 FAIL cuda unavailable\n";
            return 2;
        }
        const int nx = env_int("NX", 64);
        const int ny = env_int("NY", 32);
        const int gamma = env_int("GAMMA", 20);
        const std::uint64_t inactive = env_u64("INACTIVE_SLOTS", 1024u);
        const std::uint64_t seed = env_u64("SEED", 1628638u);
        const double tolAbs = env_double("TOL_ABS", 2.0e-10);
        const double tolRel = env_double("TOL_REL", 2.0e-12);

        std::vector<CompareResult0439> rows;
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
        std::cerr << "CUDA_RESAMPLING_DEPOSIT_SHADOW_0439 "
                  << (passCount == static_cast<int>(rows.size()) ? "PASS" : "FAIL")
                  << " cases=" << passCount << "/" << rows.size()
                  << " nx=" << nx << " ny=" << ny << " gamma=" << gamma << "\n";
        return passCount == static_cast<int>(rows.size()) ? 0 : 1;
    } catch (const std::exception& e) {
        std::cerr << "CUDA_RESAMPLING_DEPOSIT_SHADOW_0439 EXCEPTION " << e.what() << "\n";
        return 3;
    }
}
