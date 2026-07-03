#include "cell_grid.h"
#include "fluid_domain.h"
#include "particle_state.h"
#include "simulation_params.h"
#include "weighted_resampling.h"

#include <cuda_runtime.h>

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

bool is_x_periodic(const SimulationParams& p) {
    return p.bcLeft == "periodic" && p.bcRight == "periodic";
}

bool is_y_periodic(const SimulationParams& p) {
    return p.bcBottom == "periodic" && p.bcTop == "periodic";
}

bool immersed_solid_enabled(const SimulationParams&) { return false; }

double immersed_solid_fraction_in_cell(int, int, const CellGrid&, const GridShift&, const SimulationParams&, const FluidDomainBounds&, double) {
    return 0.0;
}

} // namespace mpcd

namespace {

#define CUDA_CHECK_0443(expr) do { \
    cudaError_t err__ = (expr); \
    if (err__ != cudaSuccess) { \
        throw std::runtime_error(std::string("CUDA error 0443: ") + cudaGetErrorString(err__)); \
    } \
} while (0)

int env_int(const char* name, int fallback) {
    const char* v = std::getenv(name);
    if (v == nullptr || *v == '\0') return fallback;
    return std::stoi(v);
}

std::uint64_t env_u64(const char* name, std::uint64_t fallback) {
    const char* v = std::getenv(name);
    if (v == nullptr || *v == '\0') return fallback;
    return static_cast<std::uint64_t>(std::stoull(v));
}

double env_double(const char* name, double fallback) {
    const char* v = std::getenv(name);
    if (v == nullptr || *v == '\0') return fallback;
    return std::stod(v);
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
    p.resamplingEnable = true;
    p.resamplingExtractionEnable = true;
    p.resamplingInsertionEnable = true;
    p.resamplingRemapEnable = true;
    p.resamplingThermalRenormalizationEnable = true;
    p.resamplingTargetCellMass = static_cast<double>(gamma);
    p.resamplingWetMaskMode = "active_domain";
    p.resamplingWetCellMassThreshold = 0.0;
    p.resamplingPoorCellMassFraction = 0.5;
    p.resamplingRichCellMassFraction = 1.5;
    p.resamplingActiveFluidFractionThreshold = 0.5;
    return p;
}

mpcd::ParticleState make_periodic_state(const mpcd::SimulationParams& params,
                                        int gamma,
                                        std::uint64_t inactiveSlots,
                                        std::uint64_t seed,
                                        const std::string& caseName,
                                        const std::string& massMode) {
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
                const std::size_t k = static_cast<std::size_t>(i);
                const double xr = static_cast<double>(ix) + unit(rng);
                const double yr = static_cast<double>(iy) + unit(rng);
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
        s.role[k] = mpcd::kParticleRoleInactive;
        s.mass[k] = 1.0;
    }
    mpcd::validate_particle_state(s, "make_periodic_state_0443");
    mpcd::validate_active_fluid_prefix(s, "make_periodic_state_0443");
    return s;
}

struct Totals0443 {
    double mass = 0.0;
    double px = 0.0;
    double py = 0.0;
    double ke = 0.0;
};

Totals0443 totals(const mpcd::ParticleState& s) {
    Totals0443 t{};
    const std::size_t n = static_cast<std::size_t>(s.NactiveFluid);
    for (std::size_t i = 0; i < n; ++i) {
        if (s.role[i] != mpcd::kParticleRoleFluid) continue;
        const double m = s.mass[i];
        t.mass += m;
        t.px += m * s.vx[i];
        t.py += m * s.vy[i];
        t.ke += 0.5 * m * (s.vx[i] * s.vx[i] + s.vy[i] * s.vy[i]);
    }
    return t;
}

template <typename T>
struct DeviceBuffer0443 {
    T* ptr = nullptr;
    std::size_t n = 0;
    DeviceBuffer0443() = default;
    explicit DeviceBuffer0443(std::size_t count) { allocate(count); }
    ~DeviceBuffer0443() { if (ptr) cudaFree(ptr); }
    DeviceBuffer0443(const DeviceBuffer0443&) = delete;
    DeviceBuffer0443& operator=(const DeviceBuffer0443&) = delete;
    void allocate(std::size_t count) {
        n = count;
        if (n > 0) CUDA_CHECK_0443(cudaMalloc(&ptr, n * sizeof(T)));
    }
    void copy_from_host(const std::vector<T>& v) {
        if (v.size() != n) throw std::runtime_error("DeviceBuffer0443 size mismatch");
        if (n > 0) CUDA_CHECK_0443(cudaMemcpy(ptr, v.data(), n * sizeof(T), cudaMemcpyHostToDevice));
    }
    void copy_to_host(std::vector<T>& v) const {
        v.resize(n);
        if (n > 0) CUDA_CHECK_0443(cudaMemcpy(v.data(), ptr, n * sizeof(T), cudaMemcpyDeviceToHost));
    }
    void memset_zero() {
        if (n > 0) CUDA_CHECK_0443(cudaMemset(ptr, 0, n * sizeof(T)));
    }
};

struct GpuState0443 {
    DeviceBuffer0443<double> mass;
    DeviceBuffer0443<double> vx;
    DeviceBuffer0443<double> vy;
    DeviceBuffer0443<std::uint8_t> role;
    std::size_t n = 0;
    explicit GpuState0443(const mpcd::ParticleState& s)
        : mass(static_cast<std::size_t>(s.Np)),
          vx(static_cast<std::size_t>(s.Np)),
          vy(static_cast<std::size_t>(s.Np)),
          role(static_cast<std::size_t>(s.Np)),
          n(static_cast<std::size_t>(s.Np)) {
        std::vector<std::uint8_t> roles(n, 0u);
        for (std::size_t i = 0; i < n; ++i) roles[i] = s.role[i];
        mass.copy_from_host(s.mass);
        vx.copy_from_host(s.vx);
        vy.copy_from_host(s.vy);
        role.copy_from_host(roles);
    }
    void download_to(mpcd::ParticleState& s) const {
        mass.copy_to_host(s.mass);
        vx.copy_to_host(s.vx);
        vy.copy_to_host(s.vy);
    }
};

__global__ void compute_remap_scale_kernel_0443(int nc,
                                                double targetCellMass,
                                                double strength,
                                                const uint8_t* wet,
                                                const uint32_t* count,
                                                const double* mass,
                                                double* scale,
                                                uint8_t* remapCell) {
    const int c = blockIdx.x * blockDim.x + threadIdx.x;
    if (c >= nc) return;
    scale[c] = 1.0;
    remapCell[c] = 0u;
    if (!wet[c] || count[c] == 0u) return;
    const double m = mass[c];
    if (!(m > 0.0) || !isfinite(m) || !(targetCellMass > 0.0) || !isfinite(targetCellMass)) return;
    const double target = m + fmax(0.0, fmin(1.0, strength)) * (targetCellMass - m);
    const double s = target / m;
    if (!(s > 0.0) || !isfinite(s)) return;
    scale[c] = s;
    remapCell[c] = 1u;
}

__global__ void accumulate_remap_target_energy_kernel_0443(std::size_t nActive,
                                                           const uint8_t* role,
                                                           const int* cellId,
                                                           const uint8_t* remapCell,
                                                           const double* mass,
                                                           const double* vx,
                                                           const double* vy,
                                                           const double* ux,
                                                           const double* uy,
                                                           double* targetEnergy) {
    const std::size_t i = static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
    if (i >= nActive) return;
    if (role[i] != static_cast<uint8_t>(mpcd::ParticleRole::Fluid)) return;
    const int c = cellId[i];
    if (c < 0 || !remapCell[c]) return;
    const double dux = vx[i] - ux[c];
    const double duy = vy[i] - uy[c];
    atomicAdd(&targetEnergy[c], 0.5 * mass[i] * (dux * dux + duy * duy));
}

__global__ void apply_remap_mass_kernel_0443(std::size_t nActive,
                                             const uint8_t* role,
                                             const int* cellId,
                                             const uint8_t* remapCell,
                                             const double* scale,
                                             double* mass) {
    const std::size_t i = static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
    if (i >= nActive) return;
    if (role[i] != static_cast<uint8_t>(mpcd::ParticleRole::Fluid)) return;
    const int c = cellId[i];
    if (c < 0 || !remapCell[c]) return;
    mass[i] *= scale[c];
}

__global__ void accumulate_thermal_current_kernel_0443(std::size_t nActive,
                                                       const uint8_t* role,
                                                       const int* cellId,
                                                       const uint8_t* remapCell,
                                                       const double* mass,
                                                       const double* vx,
                                                       const double* vy,
                                                       const double* ux,
                                                       const double* uy,
                                                       double* currentEnergy) {
    const std::size_t i = static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
    if (i >= nActive) return;
    if (role[i] != static_cast<uint8_t>(mpcd::ParticleRole::Fluid)) return;
    const int c = cellId[i];
    if (c < 0 || !remapCell[c]) return;
    const double dux = vx[i] - ux[c];
    const double duy = vy[i] - uy[c];
    atomicAdd(&currentEnergy[c], 0.5 * mass[i] * (dux * dux + duy * duy));
}

__global__ void compute_thermal_scale_kernel_0443(int nc,
                                                  const uint8_t* wet,
                                                  const uint32_t* count,
                                                  const uint8_t* remapCell,
                                                  const double* targetEnergy,
                                                  const double* currentEnergy,
                                                  double* thermalScale,
                                                  uint8_t* renormCell) {
    const int c = blockIdx.x * blockDim.x + threadIdx.x;
    if (c >= nc) return;
    thermalScale[c] = 1.0;
    renormCell[c] = 0u;
    if (!remapCell[c] || !wet[c] || count[c] == 0u) return;
    const double target = targetEnergy[c];
    const double before = currentEnergy[c];
    if (!(target >= 0.0) || !isfinite(target) || !(before >= 0.0) || !isfinite(before)) return;
    double s = 1.0;
    constexpr double eps = 1.0e-30;
    if (before > eps) {
        s = sqrt(fmax(0.0, target) / before);
    } else if (target > eps) {
        return;
    }
    if (!(s >= 0.0) || !isfinite(s)) return;
    thermalScale[c] = s;
    renormCell[c] = 1u;
}

__global__ void apply_thermal_velocity_kernel_0443(std::size_t nActive,
                                                   const uint8_t* role,
                                                   const int* cellId,
                                                   const uint8_t* renormCell,
                                                   const double* thermalScale,
                                                   const double* ux,
                                                   const double* uy,
                                                   double* vx,
                                                   double* vy) {
    const std::size_t i = static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
    if (i >= nActive) return;
    if (role[i] != static_cast<uint8_t>(mpcd::ParticleRole::Fluid)) return;
    const int c = cellId[i];
    if (c < 0 || !renormCell[c]) return;
    const double uxv = ux[c];
    const double uyv = uy[c];
    const double s = thermalScale[c];
    vx[i] = uxv + s * (vx[i] - uxv);
    vy[i] = uyv + s * (vy[i] - uyv);
}

struct GpuRemapThermalDiag0443 {
    std::uint64_t remapCells = 0u;
    std::uint64_t thermalCells = 0u;
    double remapKernelSeconds = 0.0;
    double thermalKernelSeconds = 0.0;
    double totalSeconds = 0.0;
};

std::uint64_t count_nonzero_u8(const std::vector<std::uint8_t>& v) {
    return static_cast<std::uint64_t>(std::count_if(v.begin(), v.end(), [](std::uint8_t x){ return x != 0u; }));
}

std::uint64_t count_effective_scaled_cells_0443(const std::vector<std::uint8_t>& activeCell,
                                                const std::vector<double>& scale,
                                                double eps = 1.0e-13) {
    const std::size_t n = std::min(activeCell.size(), scale.size());
    std::uint64_t out = 0u;
    for (std::size_t i = 0; i < n; ++i) {
        if (activeCell[i] && std::isfinite(scale[i]) && std::abs(scale[i] - 1.0) > eps) {
            out += 1u;
        }
    }
    return out;
}

GpuRemapThermalDiag0443 apply_gpu_remap_thermal(mpcd::ParticleState& gpuOut,
                                                const mpcd::WeightedRealFluidDepositWorkspace& ws,
                                                const mpcd::WeightedResamplingDiagnostics& dep,
                                                double strength) {
    const std::size_t nActive = static_cast<std::size_t>(gpuOut.NactiveFluid);
    const int nc = ws.allocatedCells;
    if (nc <= 0) throw std::runtime_error("0443 invalid cell count");
    GpuState0443 gs(gpuOut);
    DeviceBuffer0443<int> dCellId(static_cast<std::size_t>(gpuOut.Np));
    std::vector<int> cellIdFull(static_cast<std::size_t>(gpuOut.Np), -1);
    for (std::size_t i = 0; i < ws.cellId.size() && i < cellIdFull.size(); ++i) cellIdFull[i] = ws.cellId[i];
    dCellId.copy_from_host(cellIdFull);

    DeviceBuffer0443<std::uint8_t> dWet(static_cast<std::size_t>(nc)); dWet.copy_from_host(ws.wetCell);
    DeviceBuffer0443<std::uint32_t> dCount(static_cast<std::size_t>(nc)); dCount.copy_from_host(ws.count);
    DeviceBuffer0443<double> dCellMass(static_cast<std::size_t>(nc)); dCellMass.copy_from_host(ws.mass);
    DeviceBuffer0443<double> dUx(static_cast<std::size_t>(nc)); dUx.copy_from_host(ws.ux);
    DeviceBuffer0443<double> dUy(static_cast<std::size_t>(nc)); dUy.copy_from_host(ws.uy);
    DeviceBuffer0443<double> dRemapScale(static_cast<std::size_t>(nc));
    DeviceBuffer0443<std::uint8_t> dRemapCell(static_cast<std::size_t>(nc));
    DeviceBuffer0443<double> dTargetEnergy(static_cast<std::size_t>(nc)); dTargetEnergy.memset_zero();
    DeviceBuffer0443<double> dCurrentEnergy(static_cast<std::size_t>(nc)); dCurrentEnergy.memset_zero();
    DeviceBuffer0443<double> dThermalScale(static_cast<std::size_t>(nc));
    DeviceBuffer0443<std::uint8_t> dRenormCell(static_cast<std::size_t>(nc));

    cudaEvent_t start{}, stop{};
    CUDA_CHECK_0443(cudaEventCreate(&start));
    CUDA_CHECK_0443(cudaEventCreate(&stop));
    auto elapsed = [&]() {
        float ms = 0.0f;
        CUDA_CHECK_0443(cudaEventElapsedTime(&ms, start, stop));
        return static_cast<double>(ms) * 1.0e-3;
    };

    constexpr int block = 256;
    const int gridCells = (nc + block - 1) / block;
    const int gridParticles = static_cast<int>((nActive + block - 1) / block);

    GpuRemapThermalDiag0443 gd{};
    CUDA_CHECK_0443(cudaEventRecord(start));
    compute_remap_scale_kernel_0443<<<gridCells, block>>>(nc, dep.targetCellMass, strength, dWet.ptr, dCount.ptr, dCellMass.ptr, dRemapScale.ptr, dRemapCell.ptr);
    accumulate_remap_target_energy_kernel_0443<<<gridParticles, block>>>(nActive, gs.role.ptr, dCellId.ptr, dRemapCell.ptr, gs.mass.ptr, gs.vx.ptr, gs.vy.ptr, dUx.ptr, dUy.ptr, dTargetEnergy.ptr);
    apply_remap_mass_kernel_0443<<<gridParticles, block>>>(nActive, gs.role.ptr, dCellId.ptr, dRemapCell.ptr, dRemapScale.ptr, gs.mass.ptr);
    CUDA_CHECK_0443(cudaEventRecord(stop));
    CUDA_CHECK_0443(cudaEventSynchronize(stop));
    CUDA_CHECK_0443(cudaGetLastError());
    gd.remapKernelSeconds = elapsed();

    CUDA_CHECK_0443(cudaEventRecord(start));
    accumulate_thermal_current_kernel_0443<<<gridParticles, block>>>(nActive, gs.role.ptr, dCellId.ptr, dRemapCell.ptr, gs.mass.ptr, gs.vx.ptr, gs.vy.ptr, dUx.ptr, dUy.ptr, dCurrentEnergy.ptr);
    compute_thermal_scale_kernel_0443<<<gridCells, block>>>(nc, dWet.ptr, dCount.ptr, dRemapCell.ptr, dTargetEnergy.ptr, dCurrentEnergy.ptr, dThermalScale.ptr, dRenormCell.ptr);
    apply_thermal_velocity_kernel_0443<<<gridParticles, block>>>(nActive, gs.role.ptr, dCellId.ptr, dRenormCell.ptr, dThermalScale.ptr, dUx.ptr, dUy.ptr, gs.vx.ptr, gs.vy.ptr);
    CUDA_CHECK_0443(cudaEventRecord(stop));
    CUDA_CHECK_0443(cudaEventSynchronize(stop));
    CUDA_CHECK_0443(cudaGetLastError());
    gd.thermalKernelSeconds = elapsed();
    gd.totalSeconds = gd.remapKernelSeconds + gd.thermalKernelSeconds;

    std::vector<std::uint8_t> remapHost, renormHost;
    std::vector<double> remapScaleHost, thermalScaleHost;
    dRemapCell.copy_to_host(remapHost);
    dRenormCell.copy_to_host(renormHost);
    dRemapScale.copy_to_host(remapScaleHost);
    dThermalScale.copy_to_host(thermalScaleHost);
    // CPU diagnostics count only cells whose scale differs from one, although the
    // CPU path also touches particles in unit-scale remap/renorm cells.  Keep the
    // GPU operation semantically identical, but report the same effective counters.
    gd.remapCells = count_effective_scaled_cells_0443(remapHost, remapScaleHost);
    gd.thermalCells = count_effective_scaled_cells_0443(renormHost, thermalScaleHost);
    gs.download_to(gpuOut);
    CUDA_CHECK_0443(cudaEventDestroy(start));
    CUDA_CHECK_0443(cudaEventDestroy(stop));
    return gd;
}

struct CompareResult0443 {
    std::string caseName;
    std::string massMode;
    double shiftX = 0.0;
    double shiftY = 0.0;
    int pass = 0;
    std::uint64_t n = 0u;
    std::uint64_t cells = 0u;
    std::uint64_t cpuRemapCells = 0u;
    std::uint64_t gpuRemapCells = 0u;
    std::uint64_t cpuRemapParticles = 0u;
    std::uint64_t cpuThermalCells = 0u;
    std::uint64_t gpuThermalCells = 0u;
    std::uint64_t cpuThermalParticles = 0u;
    double maxAbsMass = 0.0;
    double maxAbsVx = 0.0;
    double maxAbsVy = 0.0;
    double maxAbsX = 0.0;
    double maxAbsY = 0.0;
    std::uint64_t roleMismatch = 0u;
    double cpuMass = 0.0, gpuMass = 0.0;
    double cpuPx = 0.0, gpuPx = 0.0;
    double cpuPy = 0.0, gpuPy = 0.0;
    double cpuKe = 0.0, gpuKe = 0.0;
    double remapKernelSeconds = 0.0;
    double thermalKernelSeconds = 0.0;
    double totalSeconds = 0.0;
};

CompareResult0443 run_case(const std::string& caseName,
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

    mpcd::WeightedRealFluidDepositWorkspace ws{};
    mpcd::WeightedResamplingDiagnostics dep = mpcd::deposit_weighted_real_fluid(
        initial, params, grid, domain, 0.0, shift, ws, true,
        mpcd::ResamplingDepositProfileContext::Generic, false);

    mpcd::ParticleState cpuState = initial;
    mpcd::WeightedRealFluidDepositWorkspace cpuWs = ws;
    mpcd::ResamplingRemapApplyDiagnostics remapCpu =
        mpcd::apply_resampling_local_mass_momentum_remap(cpuState, cpuWs, dep, 1.0, -1.0);
    mpcd::ResamplingThermalRenormalizationDiagnostics thermalCpu =
        mpcd::apply_resampling_local_thermal_renormalization(cpuState, cpuWs, remapCpu);

    mpcd::ParticleState gpuState = initial;
    GpuRemapThermalDiag0443 gd = apply_gpu_remap_thermal(gpuState, ws, dep, 1.0);

    CompareResult0443 r{};
    r.caseName = caseName;
    r.massMode = massMode;
    r.shiftX = shift.sx;
    r.shiftY = shift.sy;
    r.n = initial.NactiveFluid;
    r.cells = static_cast<std::uint64_t>(grid.numCells);
    r.cpuRemapCells = remapCpu.cellsRemapped;
    r.gpuRemapCells = gd.remapCells;
    r.cpuRemapParticles = remapCpu.particlesRemapped;
    r.cpuThermalCells = thermalCpu.cellsRenormalized;
    r.gpuThermalCells = gd.thermalCells;
    r.cpuThermalParticles = thermalCpu.particlesRenormalized;
    r.remapKernelSeconds = gd.remapKernelSeconds;
    r.thermalKernelSeconds = gd.thermalKernelSeconds;
    r.totalSeconds = gd.totalSeconds;

    const std::size_t nTotal = static_cast<std::size_t>(initial.Np);
    for (std::size_t i = 0; i < nTotal; ++i) {
        if (cpuState.role[i] != gpuState.role[i]) ++r.roleMismatch;
        if (cpuState.role[i] != mpcd::kParticleRoleFluid && gpuState.role[i] != mpcd::kParticleRoleFluid) {
            continue;
        }
        r.maxAbsX = std::max(r.maxAbsX, std::abs(cpuState.x[i] - gpuState.x[i]));
        r.maxAbsY = std::max(r.maxAbsY, std::abs(cpuState.y[i] - gpuState.y[i]));
        r.maxAbsVx = std::max(r.maxAbsVx, std::abs(cpuState.vx[i] - gpuState.vx[i]));
        r.maxAbsVy = std::max(r.maxAbsVy, std::abs(cpuState.vy[i] - gpuState.vy[i]));
        r.maxAbsMass = std::max(r.maxAbsMass, std::abs(cpuState.mass[i] - gpuState.mass[i]));
    }
    const Totals0443 ct = totals(cpuState);
    const Totals0443 gt = totals(gpuState);
    r.cpuMass = ct.mass; r.gpuMass = gt.mass;
    r.cpuPx = ct.px; r.gpuPx = gt.px;
    r.cpuPy = ct.py; r.gpuPy = gt.py;
    r.cpuKe = ct.ke; r.gpuKe = gt.ke;

    auto ok_close = [&](double a, double b) {
        const double scale = std::max({1.0, std::abs(a), std::abs(b)});
        return std::abs(a - b) <= tolAbs + tolRel * scale;
    };
    bool pass = true;
    pass = pass && (r.roleMismatch == 0u);
    pass = pass && (r.cpuRemapCells == r.gpuRemapCells);
    pass = pass && (r.cpuThermalCells == r.gpuThermalCells);
    pass = pass && (r.maxAbsX <= tolAbs);
    pass = pass && (r.maxAbsY <= tolAbs);
    pass = pass && (r.maxAbsMass <= tolAbs + tolRel);
    pass = pass && (r.maxAbsVx <= tolAbs + tolRel);
    pass = pass && (r.maxAbsVy <= tolAbs + tolRel);
    pass = pass && ok_close(r.cpuMass, r.gpuMass);
    pass = pass && ok_close(r.cpuPx, r.gpuPx);
    pass = pass && ok_close(r.cpuPy, r.gpuPy);
    pass = pass && ok_close(r.cpuKe, r.gpuKe);
    r.pass = pass ? 1 : 0;
    return r;
}

void print_csv_header() {
    std::cout << "case,massMode,shiftX,shiftY,pass,n,cells,"
              << "cpuRemapCells,gpuRemapCells,cpuRemapParticles,"
              << "cpuThermalCells,gpuThermalCells,cpuThermalParticles,"
              << "roleMismatch,maxAbsX,maxAbsY,maxAbsVx,maxAbsVy,maxAbsMass,"
              << "cpuMass,gpuMass,cpuPx,gpuPx,cpuPy,gpuPy,cpuKe,gpuKe,"
              << "remapKernelSeconds,thermalKernelSeconds,totalSeconds\n";
}

void print_csv_row(const CompareResult0443& r) {
    std::cout << std::setprecision(17)
              << r.caseName << ',' << r.massMode << ',' << r.shiftX << ',' << r.shiftY << ','
              << r.pass << ',' << r.n << ',' << r.cells << ','
              << r.cpuRemapCells << ',' << r.gpuRemapCells << ',' << r.cpuRemapParticles << ','
              << r.cpuThermalCells << ',' << r.gpuThermalCells << ',' << r.cpuThermalParticles << ','
              << r.roleMismatch << ',' << r.maxAbsX << ',' << r.maxAbsY << ','
              << r.maxAbsVx << ',' << r.maxAbsVy << ',' << r.maxAbsMass << ','
              << r.cpuMass << ',' << r.gpuMass << ',' << r.cpuPx << ',' << r.gpuPx << ','
              << r.cpuPy << ',' << r.gpuPy << ',' << r.cpuKe << ',' << r.gpuKe << ','
              << r.remapKernelSeconds << ',' << r.thermalKernelSeconds << ',' << r.totalSeconds << '\n';
}

} // namespace

int main() {
    const int nx = env_int("NX", 64);
    const int ny = env_int("NY", 32);
    const int gamma = env_int("GAMMA", 20);
    const std::uint64_t inactiveSlots = env_u64("INACTIVE_SLOTS", 1024u);
    const std::uint64_t seed = env_u64("SEED", 1628638u);
    const double tolAbs = env_double("TOL_ABS", 2.0e-10);
    const double tolRel = env_double("TOL_REL", 2.0e-12);

    std::vector<CompareResult0443> results;
    results.push_back(run_case("shear", "uniform", nx, ny, gamma, inactiveSlots, seed, 0.0, 0.0, tolAbs, tolRel));
    results.push_back(run_case("shear", "uniform", nx, ny, gamma, inactiveSlots, seed, 0.37, 0.23, tolAbs, tolRel));
    results.push_back(run_case("tg", "vary", nx, ny, gamma, inactiveSlots, seed + 17u, 0.0, 0.0, tolAbs, tolRel));
    results.push_back(run_case("tg", "vary", nx, ny, gamma, inactiveSlots, seed + 17u, 0.37, 0.23, tolAbs, tolRel));

    print_csv_header();
    int passCount = 0;
    for (const auto& r : results) {
        print_csv_row(r);
        passCount += r.pass ? 1 : 0;
    }
    if (passCount == static_cast<int>(results.size())) {
        std::cerr << "CUDA_RESAMPLING_REMAP_THERMAL_SHADOW_0443 PASS cases=" << passCount << "/" << results.size()
                  << " nx=" << nx << " ny=" << ny << " gamma=" << gamma << "\n";
        return 0;
    }
    std::cerr << "CUDA_RESAMPLING_REMAP_THERMAL_SHADOW_0443 FAIL cases=" << passCount << "/" << results.size()
              << " nx=" << nx << " ny=" << ny << " gamma=" << gamma << "\n";
    return 1;
}
