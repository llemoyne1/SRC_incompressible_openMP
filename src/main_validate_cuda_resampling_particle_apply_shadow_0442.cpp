#include "cell_grid.h"
#include "cuda_particle_state.h"
#include "cuda_resampling_particle_ops.h"
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

// 0442 standalone validator support.
// This validator intentionally runs only periodic wall-free/no-solid synthetic cases.
// Define the small boundary/solid hooks needed by cell_grid.cpp and
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
                const std::size_t k = static_cast<std::size_t>(i);
                s.x[k] = xr;
                s.y[k] = yr;
                if (caseName == "tg") {
                    s.vx[k] = amp * std::sin(kx * xr) * std::cos(ky * yr) + thermal(rng);
                    s.vy[k] = -amp * std::cos(kx * xr) * std::sin(ky * yr) + thermal(rng);
                } else {
                    s.vx[k] = amp * std::sin(ky * yr) + thermal(rng);
                    s.vy[k] = thermal(rng);
                }
                if (massMode == "vary") {
                    const double a = 0.08 * std::sin(0.137 * static_cast<double>(i)) +
                                     0.03 * std::cos(0.071 * static_cast<double>(ix + 3 * iy + g));
                    s.mass[k] = 1.0 + a;
                }
                s.role[k] = mpcd::kParticleRoleFluid;
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
        s.type[k] = 0u;
        s.role[k] = mpcd::kParticleRoleInactive;
    }
    mpcd::validate_particle_state(s, "make_periodic_state_0442");
    mpcd::validate_active_fluid_prefix(s, "make_periodic_state_0442");
    return s;
}

struct StateTotals0442 {
    std::uint64_t fluidRoles = 0u;
    std::uint64_t inactiveRoles = 0u;
    double mass = 0.0;
    double px = 0.0;
    double py = 0.0;
    double ke = 0.0;
};

StateTotals0442 state_totals(const mpcd::ParticleState& s) {
    StateTotals0442 t{};
    for (std::size_t i = 0; i < static_cast<std::size_t>(s.Np); ++i) {
        if (s.role[i] == mpcd::kParticleRoleFluid) {
            ++t.fluidRoles;
            const double m = s.mass[i];
            t.mass += m;
            t.px += m * s.vx[i];
            t.py += m * s.vy[i];
            t.ke += 0.5 * m * (s.vx[i] * s.vx[i] + s.vy[i] * s.vy[i]);
        } else if (s.role[i] == mpcd::kParticleRoleInactive) {
            ++t.inactiveRoles;
        }
    }
    return t;
}

std::uint64_t invalid_active_prefix_count(const mpcd::ParticleState& s) {
    std::uint64_t bad = 0u;
    const std::size_t n = static_cast<std::size_t>(s.NactiveFluid);
    for (std::size_t i = 0; i < n && i < static_cast<std::size_t>(s.Np); ++i) {
        if (s.role[i] != mpcd::kParticleRoleFluid) ++bad;
    }
    return bad;
}

struct OperationVectors0442 {
    std::vector<std::uint32_t> particleIndex;
    std::vector<std::uint32_t> receiverCell;
    std::vector<std::uint32_t> particleType;
    std::vector<double> particleMass;
    std::vector<double> momentumX;
    std::vector<double> momentumY;
    std::vector<std::uint32_t> insertionOrdinal;
};

OperationVectors0442 make_operation_vectors(const mpcd::WeightedRealFluidDepositWorkspace& ws) {
    OperationVectors0442 ops{};
    ops.particleIndex.reserve(ws.passiveExtractionOperations.size());
    ops.receiverCell.reserve(ws.passiveExtractionOperations.size());
    ops.particleType.reserve(ws.passiveExtractionOperations.size());
    ops.particleMass.reserve(ws.passiveExtractionOperations.size());
    ops.momentumX.reserve(ws.passiveExtractionOperations.size());
    ops.momentumY.reserve(ws.passiveExtractionOperations.size());
    ops.insertionOrdinal.reserve(ws.passiveExtractionOperations.size());
    std::uint32_t ordinal = 0u;
    for (const auto& op : ws.passiveExtractionOperations) {
        if (op.particleIndex == mpcd::kInvalidParticleIndex || op.particleIndex > 0xffffffffull) {
            throw std::runtime_error("0442 operation particle index does not fit uint32");
        }
        if (op.receiverCell < 0) {
            throw std::runtime_error("0442 operation has invalid receiver cell");
        }
        ops.particleIndex.push_back(static_cast<std::uint32_t>(op.particleIndex));
        ops.receiverCell.push_back(static_cast<std::uint32_t>(op.receiverCell));
        ops.particleType.push_back(op.particleType);
        ops.particleMass.push_back(op.particleMass);
        ops.momentumX.push_back(op.momentumX);
        ops.momentumY.push_back(op.momentumY);
        ops.insertionOrdinal.push_back(ordinal++);
    }
    return ops;
}

struct CompareResult0442 {
    std::string caseName;
    std::string massMode;
    double shiftX = 0.0;
    double shiftY = 0.0;
    int pass = 0;
    std::uint64_t n = 0u;
    int cells = 0;
    std::uint64_t planEntries = 0u;
    std::uint64_t passiveOps = 0u;
    std::uint64_t cpuExtractionApplied = 0u;
    std::uint64_t cpuInsertionApplied = 0u;
    std::uint64_t gpuExtractionApplied = 0u;
    std::uint64_t gpuInsertionApplied = 0u;
    std::uint64_t gpuExtractionInvalid = 0u;
    std::uint64_t gpuInsertionInvalid = 0u;
    std::uint64_t roleMismatch = 0u;
    std::uint64_t typeMismatch = 0u;
    double maxAbsX = 0.0;
    double maxAbsY = 0.0;
    double maxAbsVx = 0.0;
    double maxAbsVy = 0.0;
    double maxAbsMass = 0.0;
    std::uint64_t cpuFluidRoles = 0u;
    std::uint64_t gpuFluidRoles = 0u;
    std::uint64_t cpuInactiveRoles = 0u;
    std::uint64_t gpuInactiveRoles = 0u;
    std::uint64_t cpuBadActivePrefix = 0u;
    std::uint64_t gpuBadActivePrefix = 0u;
    double cpuMass = 0.0;
    double gpuMass = 0.0;
    double cpuPx = 0.0;
    double gpuPx = 0.0;
    double cpuPy = 0.0;
    double gpuPy = 0.0;
    double cpuKe = 0.0;
    double gpuKe = 0.0;
    double maxMassConservationAbs = 0.0;
    double maxPxConservationAbs = 0.0;
    double maxPyConservationAbs = 0.0;
    double extractionKernelSeconds = 0.0;
    double insertionKernelSeconds = 0.0;
    double operationUploadSeconds = 0.0;
    double gpuApplyTotalSeconds = 0.0;
    double gpuDownloadSeconds = 0.0;
};

CompareResult0442 run_one(const std::string& caseName,
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
    mpcd::ParticleState initial = make_periodic_state(params, gamma, inactiveSlots, seed, caseName, massMode);
    const StateTotals0442 initialTotals = state_totals(initial);

    mpcd::WeightedRealFluidDepositWorkspace ws{};
    mpcd::WeightedResamplingDiagnostics dep = mpcd::deposit_weighted_real_fluid(
        initial, params, grid, domain, 0.0, shift, ws, true,
        mpcd::ResamplingDepositProfileContext::Generic, false);
    (void)dep;

    mpcd::ParticleState cpuState = initial;
    mpcd::ResamplingParticlePoolWorkspace cpuPool{};
    mpcd::rebuild_resampling_particle_pool(cpuState, cpuPool);
    mpcd::ResamplingExtractionApplyDiagnostics cpuExt =
        mpcd::apply_resampling_extraction_operations(cpuState, cpuPool, ws);
    mpcd::ResamplingInsertionApplyDiagnostics cpuIns =
        mpcd::apply_resampling_insertion_operations(cpuState, cpuPool, ws, grid);

    mpcd::CudaParticleState gpuState{};
    mpcd::CudaParticleStateDiagnostics uploadDiag{};
    gpuState.upload_all(initial, &uploadDiag);
    OperationVectors0442 ops = make_operation_vectors(ws);

    mpcd::CudaResamplingExtractionApplyParams ep{};
    ep.fluidRole = static_cast<std::uint8_t>(mpcd::ParticleRole::Fluid);
    ep.inactiveRole = static_cast<std::uint8_t>(mpcd::ParticleRole::Inactive);
    ep.invalidParticle = 0xffffffffu;
    mpcd::CudaResamplingPersistentOpsDiagnostics gpuExt{};
    const bool extOk = mpcd::cuda_resampling_apply_extraction_operations_on_state_0239(
        gpuState, ops.particleIndex, ops.particleMass, ops.momentumX, ops.momentumY, ep, &gpuExt);

    mpcd::CudaResamplingInsertionApplyParams ip{};
    ip.inactiveRole = static_cast<std::uint8_t>(mpcd::ParticleRole::Inactive);
    ip.fluidRole = static_cast<std::uint8_t>(mpcd::ParticleRole::Fluid);
    ip.invalidParticle = 0xffffffffu;
    ip.useHashPlacement = 0u;
    mpcd::CudaResamplingPersistentOpsDiagnostics gpuIns{};
    const bool insOk = mpcd::cuda_resampling_apply_insertion_operations_on_state_0239(
        gpuState, ops.particleIndex, ops.receiverCell, ops.particleType,
        ops.particleMass, ops.momentumX, ops.momentumY, ops.insertionOrdinal,
        static_cast<std::uint32_t>(grid.Nx), static_cast<std::uint32_t>(grid.Ny),
        grid.dx, grid.dy, ip, &gpuIns);

    mpcd::ParticleState gpuOut = initial;
    mpcd::CudaParticleStateDiagnostics downloadDiag{};
    gpuState.download_all(gpuOut, &downloadDiag);

    const StateTotals0442 cpuTotals = state_totals(cpuState);
    const StateTotals0442 gpuTotals = state_totals(gpuOut);

    CompareResult0442 r{};
    r.caseName = caseName;
    r.massMode = massMode;
    r.shiftX = shift.sx;
    r.shiftY = shift.sy;
    r.n = initial.NactiveFluid;
    r.cells = grid.numCells;
    r.planEntries = static_cast<std::uint64_t>(ws.transferPlan.size());
    r.passiveOps = static_cast<std::uint64_t>(ws.passiveExtractionOperations.size());
    r.cpuExtractionApplied = cpuExt.operationsApplied;
    r.cpuInsertionApplied = cpuIns.operationsApplied;
    r.gpuExtractionApplied = gpuExt.operationsApplied;
    r.gpuInsertionApplied = gpuIns.operationsApplied;
    r.gpuExtractionInvalid = gpuExt.invalidOperations;
    r.gpuInsertionInvalid = gpuIns.invalidOperations;
    r.extractionKernelSeconds = gpuExt.kernelSeconds;
    r.insertionKernelSeconds = gpuIns.kernelSeconds;
    r.operationUploadSeconds = gpuExt.operationUploadSeconds + gpuIns.operationUploadSeconds;
    r.gpuApplyTotalSeconds = gpuExt.totalSeconds + gpuIns.totalSeconds;
    r.gpuDownloadSeconds = downloadDiag.downloadSeconds;

    const std::size_t nTotal = static_cast<std::size_t>(initial.Np);
    for (std::size_t i = 0; i < nTotal; ++i) {
        if (cpuState.role[i] != gpuOut.role[i]) ++r.roleMismatch;
        if (cpuState.type[i] != gpuOut.type[i]) ++r.typeMismatch;

        // Only fluid-slot payload is semantically meaningful after extraction/insertion.
        // CPU and CUDA implementations are allowed to leave different stale x/y/v/m
        // payloads in inactive/free slots, provided roles, prefix, pool counts and
        // conserved fluid totals agree. 0442 therefore compares payload values only
        // where both sides still identify the slot as fluid.
        if (cpuState.role[i] == mpcd::kParticleRoleFluid &&
            gpuOut.role[i] == mpcd::kParticleRoleFluid) {
            r.maxAbsX = std::max(r.maxAbsX, std::abs(cpuState.x[i] - gpuOut.x[i]));
            r.maxAbsY = std::max(r.maxAbsY, std::abs(cpuState.y[i] - gpuOut.y[i]));
            r.maxAbsVx = std::max(r.maxAbsVx, std::abs(cpuState.vx[i] - gpuOut.vx[i]));
            r.maxAbsVy = std::max(r.maxAbsVy, std::abs(cpuState.vy[i] - gpuOut.vy[i]));
            r.maxAbsMass = std::max(r.maxAbsMass, std::abs(cpuState.mass[i] - gpuOut.mass[i]));
        }
    }
    r.cpuFluidRoles = cpuTotals.fluidRoles;
    r.gpuFluidRoles = gpuTotals.fluidRoles;
    r.cpuInactiveRoles = cpuTotals.inactiveRoles;
    r.gpuInactiveRoles = gpuTotals.inactiveRoles;
    r.cpuBadActivePrefix = invalid_active_prefix_count(cpuState);
    r.gpuBadActivePrefix = invalid_active_prefix_count(gpuOut);
    r.cpuMass = cpuTotals.mass;
    r.gpuMass = gpuTotals.mass;
    r.cpuPx = cpuTotals.px;
    r.gpuPx = gpuTotals.px;
    r.cpuPy = cpuTotals.py;
    r.gpuPy = gpuTotals.py;
    r.cpuKe = cpuTotals.ke;
    r.gpuKe = gpuTotals.ke;
    r.maxMassConservationAbs = std::max(std::abs(cpuTotals.mass - initialTotals.mass),
                                        std::abs(gpuTotals.mass - initialTotals.mass));
    r.maxPxConservationAbs = std::max(std::abs(cpuTotals.px - initialTotals.px),
                                      std::abs(gpuTotals.px - initialTotals.px));
    r.maxPyConservationAbs = std::max(std::abs(cpuTotals.py - initialTotals.py),
                                      std::abs(gpuTotals.py - initialTotals.py));

    auto ok_close = [&](double a, double b) {
        const double scale = std::max({1.0, std::abs(a), std::abs(b)});
        return std::abs(a - b) <= tolAbs + tolRel * scale;
    };
    bool pass = true;
    pass = pass && extOk && insOk;
    pass = pass && (r.cpuExtractionApplied == r.passiveOps);
    pass = pass && (r.cpuInsertionApplied == r.passiveOps);
    pass = pass && (r.gpuExtractionApplied == r.passiveOps);
    pass = pass && (r.gpuInsertionApplied == r.passiveOps);
    pass = pass && (r.gpuExtractionInvalid == 0u);
    pass = pass && (r.gpuInsertionInvalid == 0u);
    pass = pass && (r.roleMismatch == 0u);
    pass = pass && (r.typeMismatch == 0u);
    pass = pass && (r.cpuFluidRoles == r.gpuFluidRoles);
    pass = pass && (r.cpuInactiveRoles == r.gpuInactiveRoles);
    pass = pass && (r.cpuBadActivePrefix == 0u);
    pass = pass && (r.gpuBadActivePrefix == 0u);
    pass = pass && ok_close(r.cpuMass, r.gpuMass);
    pass = pass && ok_close(r.cpuPx, r.gpuPx);
    pass = pass && ok_close(r.cpuPy, r.gpuPy);
    pass = pass && ok_close(r.cpuKe, r.gpuKe);
    pass = pass && (r.maxAbsX <= tolAbs);
    pass = pass && (r.maxAbsY <= tolAbs);
    pass = pass && (r.maxAbsVx <= tolAbs + tolRel);
    pass = pass && (r.maxAbsVy <= tolAbs + tolRel);
    pass = pass && (r.maxAbsMass <= tolAbs + tolRel);
    pass = pass && (r.maxMassConservationAbs <= tolAbs + tolRel * std::max(1.0, std::abs(initialTotals.mass)));
    pass = pass && (r.maxPxConservationAbs <= tolAbs + tolRel * std::max(1.0, std::abs(initialTotals.px)));
    pass = pass && (r.maxPyConservationAbs <= tolAbs + tolRel * std::max(1.0, std::abs(initialTotals.py)));
    r.pass = pass ? 1 : 0;
    return r;
}

void print_csv_header() {
    std::cout << "case,massMode,shiftX,shiftY,pass,n,cells,planEntries,passiveOps,"
              << "cpuExtractionApplied,cpuInsertionApplied,gpuExtractionApplied,gpuInsertionApplied,"
              << "gpuExtractionInvalid,gpuInsertionInvalid,roleMismatch,typeMismatch,"
              << "maxAbsX,maxAbsY,maxAbsVx,maxAbsVy,maxAbsMass,"
              << "cpuFluidRoles,gpuFluidRoles,cpuInactiveRoles,gpuInactiveRoles,"
              << "cpuBadActivePrefix,gpuBadActivePrefix,cpuMass,gpuMass,cpuPx,gpuPx,cpuPy,gpuPy,cpuKe,gpuKe,"
              << "maxMassConservationAbs,maxPxConservationAbs,maxPyConservationAbs,"
              << "extractionKernelSeconds,insertionKernelSeconds,operationUploadSeconds,gpuApplyTotalSeconds,gpuDownloadSeconds\n";
}

void print_csv_row(const CompareResult0442& r) {
    std::cout << std::setprecision(17)
              << r.caseName << ',' << r.massMode << ',' << r.shiftX << ',' << r.shiftY << ','
              << r.pass << ',' << r.n << ',' << r.cells << ',' << r.planEntries << ',' << r.passiveOps << ','
              << r.cpuExtractionApplied << ',' << r.cpuInsertionApplied << ','
              << r.gpuExtractionApplied << ',' << r.gpuInsertionApplied << ','
              << r.gpuExtractionInvalid << ',' << r.gpuInsertionInvalid << ','
              << r.roleMismatch << ',' << r.typeMismatch << ','
              << r.maxAbsX << ',' << r.maxAbsY << ',' << r.maxAbsVx << ',' << r.maxAbsVy << ',' << r.maxAbsMass << ','
              << r.cpuFluidRoles << ',' << r.gpuFluidRoles << ',' << r.cpuInactiveRoles << ',' << r.gpuInactiveRoles << ','
              << r.cpuBadActivePrefix << ',' << r.gpuBadActivePrefix << ','
              << r.cpuMass << ',' << r.gpuMass << ',' << r.cpuPx << ',' << r.gpuPx << ','
              << r.cpuPy << ',' << r.gpuPy << ',' << r.cpuKe << ',' << r.gpuKe << ','
              << r.maxMassConservationAbs << ',' << r.maxPxConservationAbs << ',' << r.maxPyConservationAbs << ','
              << r.extractionKernelSeconds << ',' << r.insertionKernelSeconds << ','
              << r.operationUploadSeconds << ',' << r.gpuApplyTotalSeconds << ',' << r.gpuDownloadSeconds << '\n';
}

} // namespace

int main() {
    try {
        if (!mpcd::cuda_particle_state_available()) {
            std::cerr << "CUDA_RESAMPLING_PARTICLE_APPLY_SHADOW_0442 FAIL cuda particle state unavailable\n";
            return 2;
        }
        const int nx = env_int("NX", 64);
        const int ny = env_int("NY", 32);
        const int gamma = env_int("GAMMA", 20);
        const std::uint64_t inactive = env_u64("INACTIVE_SLOTS", 1024u);
        const std::uint64_t seed = env_u64("SEED", 1628638u);
        const double tolAbs = env_double("TOL_ABS", 2.0e-10);
        const double tolRel = env_double("TOL_REL", 2.0e-12);

        std::vector<CompareResult0442> rows;
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
        std::cerr << "CUDA_RESAMPLING_PARTICLE_APPLY_SHADOW_0442 "
                  << (passCount == static_cast<int>(rows.size()) ? "PASS" : "FAIL")
                  << " cases=" << passCount << "/" << rows.size()
                  << " nx=" << nx << " ny=" << ny << " gamma=" << gamma << "\n";
        return passCount == static_cast<int>(rows.size()) ? 0 : 1;
    } catch (const std::exception& e) {
        std::cerr << "CUDA_RESAMPLING_PARTICLE_APPLY_SHADOW_0442 EXCEPTION " << e.what() << "\n";
        return 3;
    }
}
