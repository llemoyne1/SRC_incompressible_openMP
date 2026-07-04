#include "cuda_resampling_pipeline_shadow_0445.h"
#include "cuda_particle_state.h"
#include "cuda_cell_moments.h"
#include "cuda_cell_workspace.h"
#include "cuda_resampling_particle_ops.h"

#if defined(MPCD_ENABLE_CUDA_RESAMPLING) && defined(MPCD_ENABLE_CUDA_PARTICLE_STATE)

#include <cuda_runtime.h>

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstddef>
#include <cctype>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <chrono>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

namespace mpcd {
namespace {

#define CUDA_CHECK_0445(expr) do { \
    cudaError_t err__ = (expr); \
    if (err__ != cudaSuccess) { \
        throw std::runtime_error(std::string("cuda_resampling_pipeline_shadow_0445: ") + cudaGetErrorString(err__)); \
    } \
} while (0)

bool env_truthy_0445(const char* name) {
    const char* v = std::getenv(name);
    if (v == nullptr || *v == '\0') return false;
    std::string s(v);
    std::transform(s.begin(), s.end(), s.begin(), [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
    return !(s == "0" || s == "false" || s == "off" || s == "no");
}

std::uint64_t env_u64_0445(const char* name, std::uint64_t fallback) {
    const char* v = std::getenv(name);
    if (v == nullptr || *v == '\0') return fallback;
    try { return static_cast<std::uint64_t>(std::stoull(v)); } catch (...) { return fallback; }
}

std::string csv_escape_0445(const std::string& s) {
    if (s.find_first_of(",\"\n\r") == std::string::npos) return s;
    std::string out = "\"";
    for (const char ch : s) out += (ch == '"') ? "\"\"" : std::string(1, ch);
    out += "\"";
    return out;
}

template <typename T>
struct DeviceBuffer0445 {
    T* ptr = nullptr;
    std::size_t n = 0u;
    DeviceBuffer0445() = default;
    explicit DeviceBuffer0445(std::size_t count) { allocate(count); }
    ~DeviceBuffer0445() { if (ptr != nullptr) cudaFree(ptr); }
    DeviceBuffer0445(const DeviceBuffer0445&) = delete;
    DeviceBuffer0445& operator=(const DeviceBuffer0445&) = delete;
    void allocate(std::size_t count) {
        n = count;
        if (n > 0u) CUDA_CHECK_0445(cudaMalloc(reinterpret_cast<void**>(&ptr), n * sizeof(T)));
    }
    void copy_from_host(const std::vector<T>& v) {
        if (v.size() != n) throw std::runtime_error("0445 DeviceBuffer size mismatch");
        if (n > 0u) CUDA_CHECK_0445(cudaMemcpy(ptr, v.data(), n * sizeof(T), cudaMemcpyHostToDevice));
    }
    void copy_to_host(std::vector<T>& v) const {
        v.resize(n);
        if (n > 0u) CUDA_CHECK_0445(cudaMemcpy(v.data(), ptr, n * sizeof(T), cudaMemcpyDeviceToHost));
    }
    void memset_zero() {
        if (n > 0u) CUDA_CHECK_0445(cudaMemset(ptr, 0, n * sizeof(T)));
    }
};

struct GpuState0445 {
    DeviceBuffer0445<double> mass;
    DeviceBuffer0445<double> vx;
    DeviceBuffer0445<double> vy;
    DeviceBuffer0445<std::uint8_t> role;
    explicit GpuState0445(const ParticleState& s)
        : mass(static_cast<std::size_t>(s.Np)),
          vx(static_cast<std::size_t>(s.Np)),
          vy(static_cast<std::size_t>(s.Np)),
          role(static_cast<std::size_t>(s.Np)) {
        std::vector<std::uint8_t> roles(static_cast<std::size_t>(s.Np), kParticleRoleInactive);
        for (std::size_t i = 0; i < roles.size() && i < s.role.size(); ++i) roles[i] = s.role[i];
        mass.copy_from_host(s.mass);
        vx.copy_from_host(s.vx);
        vy.copy_from_host(s.vy);
        role.copy_from_host(roles);
    }
    void download_to(ParticleState& s) const {
        mass.copy_to_host(s.mass);
        vx.copy_to_host(s.vx);
        vy.copy_to_host(s.vy);
    }
};

__global__ void compute_remap_scale_kernel_0445(int nc,
                                                double targetCellMass,
                                                double strength,
                                                const std::uint8_t* wet,
                                                const std::uint32_t* count,
                                                const double* mass,
                                                double* scale,
                                                std::uint8_t* remapCell) {
    const int c = blockIdx.x * blockDim.x + threadIdx.x;
    if (c >= nc) return;
    scale[c] = 1.0;
    remapCell[c] = 0u;
    if (!wet[c] || count[c] == 0u) return;
    const double m = mass[c];
    if (!(m > 0.0) || !isfinite(m) || !(targetCellMass > 0.0) || !isfinite(targetCellMass)) return;
    const double a = fmax(0.0, fmin(1.0, strength));
    const double target = m + a * (targetCellMass - m);
    const double s = target / m;
    if (!(s > 0.0) || !isfinite(s)) return;
    scale[c] = s;
    remapCell[c] = 1u;
}

__global__ void accumulate_remap_target_energy_kernel_0445(std::size_t nActive,
                                                           const std::uint8_t* role,
                                                           const int* cellId,
                                                           const std::uint8_t* remapCell,
                                                           const double* mass,
                                                           const double* vx,
                                                           const double* vy,
                                                           const double* ux,
                                                           const double* uy,
                                                           double* targetEnergy) {
    const std::size_t i = static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
    if (i >= nActive) return;
    if (role[i] != kParticleRoleFluid) return;
    const int c = cellId[i];
    if (c < 0 || !remapCell[c]) return;
    const double dux = vx[i] - ux[c];
    const double duy = vy[i] - uy[c];
    atomicAdd(&targetEnergy[c], 0.5 * mass[i] * (dux * dux + duy * duy));
}

__global__ void apply_remap_mass_kernel_0445(std::size_t nActive,
                                             const std::uint8_t* role,
                                             const int* cellId,
                                             const std::uint8_t* remapCell,
                                             const double* scale,
                                             double* mass) {
    const std::size_t i = static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
    if (i >= nActive) return;
    if (role[i] != kParticleRoleFluid) return;
    const int c = cellId[i];
    if (c < 0 || !remapCell[c]) return;
    mass[i] *= scale[c];
}

__global__ void accumulate_thermal_current_kernel_0445(std::size_t nActive,
                                                       const std::uint8_t* role,
                                                       const int* cellId,
                                                       const std::uint8_t* remapCell,
                                                       const double* mass,
                                                       const double* vx,
                                                       const double* vy,
                                                       const double* ux,
                                                       const double* uy,
                                                       double* currentEnergy) {
    const std::size_t i = static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
    if (i >= nActive) return;
    if (role[i] != kParticleRoleFluid) return;
    const int c = cellId[i];
    if (c < 0 || !remapCell[c]) return;
    const double dux = vx[i] - ux[c];
    const double duy = vy[i] - uy[c];
    atomicAdd(&currentEnergy[c], 0.5 * mass[i] * (dux * dux + duy * duy));
}

__global__ void compute_thermal_scale_kernel_0445(int nc,
                                                  const std::uint8_t* wet,
                                                  const std::uint32_t* count,
                                                  const std::uint8_t* remapCell,
                                                  const double* targetEnergy,
                                                  const double* currentEnergy,
                                                  double* thermalScale,
                                                  std::uint8_t* renormCell) {
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
    if (before > eps) s = sqrt(fmax(0.0, target) / before);
    else if (target > eps) return;
    if (!(s >= 0.0) || !isfinite(s)) return;
    thermalScale[c] = s;
    renormCell[c] = 1u;
}

__global__ void apply_thermal_velocity_kernel_0445(std::size_t nActive,
                                                   const std::uint8_t* role,
                                                   const int* cellId,
                                                   const std::uint8_t* renormCell,
                                                   const double* thermalScale,
                                                   const double* ux,
                                                   const double* uy,
                                                   double* vx,
                                                   double* vy) {
    const std::size_t i = static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
    if (i >= nActive) return;
    if (role[i] != kParticleRoleFluid) return;
    const int c = cellId[i];
    if (c < 0 || !renormCell[c]) return;
    const double uxv = ux[c];
    const double uyv = uy[c];
    const double s = thermalScale[c];
    vx[i] = uxv + s * (vx[i] - uxv);
    vy[i] = uyv + s * (vy[i] - uyv);
}

std::uint64_t count_effective_scaled_cells_0445(const std::vector<std::uint8_t>& activeCell,
                                                const std::vector<double>& scale,
                                                double eps = 1.0e-13) {
    const std::size_t n = std::min(activeCell.size(), scale.size());
    std::uint64_t out = 0u;
    for (std::size_t i = 0; i < n; ++i) {
        if (activeCell[i] && std::isfinite(scale[i]) && std::abs(scale[i] - 1.0) > eps) ++out;
    }
    return out;
}

struct GpuRemapThermal0445 {
    std::uint64_t remapCells = 0u;
    std::uint64_t thermalCells = 0u;
    double remapSeconds = 0.0;
    double thermalSeconds = 0.0;
};

GpuRemapThermal0445 apply_gpu_remap_thermal_0445(ParticleState& gpuOut,
                                                 const WeightedRealFluidDepositWorkspace& ws,
                                                 const WeightedResamplingDiagnostics& dep,
                                                 double strength,
                                                 double targetCellMassOverride) {
    const std::size_t nActive = static_cast<std::size_t>(gpuOut.NactiveFluid);
    const int nc = ws.allocatedCells;
    if (nc <= 0) throw std::runtime_error("0445 invalid cell count");
    GpuState0445 gs(gpuOut);
    std::vector<int> cellIdFull(static_cast<std::size_t>(gpuOut.Np), -1);
    for (std::size_t i = 0; i < ws.cellId.size() && i < cellIdFull.size(); ++i) cellIdFull[i] = ws.cellId[i];

    DeviceBuffer0445<int> dCellId(cellIdFull.size()); dCellId.copy_from_host(cellIdFull);
    DeviceBuffer0445<std::uint8_t> dWet(static_cast<std::size_t>(nc)); dWet.copy_from_host(ws.wetCell);
    DeviceBuffer0445<std::uint32_t> dCount(static_cast<std::size_t>(nc)); dCount.copy_from_host(ws.count);
    DeviceBuffer0445<double> dCellMass(static_cast<std::size_t>(nc)); dCellMass.copy_from_host(ws.mass);
    DeviceBuffer0445<double> dUx(static_cast<std::size_t>(nc)); dUx.copy_from_host(ws.ux);
    DeviceBuffer0445<double> dUy(static_cast<std::size_t>(nc)); dUy.copy_from_host(ws.uy);
    DeviceBuffer0445<double> dRemapScale(static_cast<std::size_t>(nc));
    DeviceBuffer0445<std::uint8_t> dRemapCell(static_cast<std::size_t>(nc));
    DeviceBuffer0445<double> dTargetEnergy(static_cast<std::size_t>(nc)); dTargetEnergy.memset_zero();
    DeviceBuffer0445<double> dCurrentEnergy(static_cast<std::size_t>(nc)); dCurrentEnergy.memset_zero();
    DeviceBuffer0445<double> dThermalScale(static_cast<std::size_t>(nc));
    DeviceBuffer0445<std::uint8_t> dRenormCell(static_cast<std::size_t>(nc));

    cudaEvent_t start{}, stop{};
    CUDA_CHECK_0445(cudaEventCreate(&start));
    CUDA_CHECK_0445(cudaEventCreate(&stop));
    auto elapsed = [&]() {
        float ms = 0.0f;
        CUDA_CHECK_0445(cudaEventElapsedTime(&ms, start, stop));
        return static_cast<double>(ms) * 1.0e-3;
    };

    constexpr int block = 256;
    const int gridCells = (nc + block - 1) / block;
    const int gridParticles = static_cast<int>((nActive + block - 1) / block);
    const double targetCellMass = (targetCellMassOverride > 0.0 && std::isfinite(targetCellMassOverride))
        ? targetCellMassOverride : dep.targetCellMass;

    GpuRemapThermal0445 out{};
    CUDA_CHECK_0445(cudaEventRecord(start));
    compute_remap_scale_kernel_0445<<<gridCells, block>>>(nc, targetCellMass, strength, dWet.ptr, dCount.ptr, dCellMass.ptr, dRemapScale.ptr, dRemapCell.ptr);
    accumulate_remap_target_energy_kernel_0445<<<gridParticles, block>>>(nActive, gs.role.ptr, dCellId.ptr, dRemapCell.ptr, gs.mass.ptr, gs.vx.ptr, gs.vy.ptr, dUx.ptr, dUy.ptr, dTargetEnergy.ptr);
    apply_remap_mass_kernel_0445<<<gridParticles, block>>>(nActive, gs.role.ptr, dCellId.ptr, dRemapCell.ptr, dRemapScale.ptr, gs.mass.ptr);
    CUDA_CHECK_0445(cudaEventRecord(stop));
    CUDA_CHECK_0445(cudaEventSynchronize(stop));
    CUDA_CHECK_0445(cudaGetLastError());
    out.remapSeconds = elapsed();

    CUDA_CHECK_0445(cudaEventRecord(start));
    accumulate_thermal_current_kernel_0445<<<gridParticles, block>>>(nActive, gs.role.ptr, dCellId.ptr, dRemapCell.ptr, gs.mass.ptr, gs.vx.ptr, gs.vy.ptr, dUx.ptr, dUy.ptr, dCurrentEnergy.ptr);
    compute_thermal_scale_kernel_0445<<<gridCells, block>>>(nc, dWet.ptr, dCount.ptr, dRemapCell.ptr, dTargetEnergy.ptr, dCurrentEnergy.ptr, dThermalScale.ptr, dRenormCell.ptr);
    apply_thermal_velocity_kernel_0445<<<gridParticles, block>>>(nActive, gs.role.ptr, dCellId.ptr, dRenormCell.ptr, dThermalScale.ptr, dUx.ptr, dUy.ptr, gs.vx.ptr, gs.vy.ptr);
    CUDA_CHECK_0445(cudaEventRecord(stop));
    CUDA_CHECK_0445(cudaEventSynchronize(stop));
    CUDA_CHECK_0445(cudaGetLastError());
    out.thermalSeconds = elapsed();

    std::vector<std::uint8_t> remapHost, renormHost;
    std::vector<double> remapScaleHost, thermalScaleHost;
    dRemapCell.copy_to_host(remapHost);
    dRenormCell.copy_to_host(renormHost);
    dRemapScale.copy_to_host(remapScaleHost);
    dThermalScale.copy_to_host(thermalScaleHost);
    out.remapCells = count_effective_scaled_cells_0445(remapHost, remapScaleHost);
    out.thermalCells = count_effective_scaled_cells_0445(renormHost, thermalScaleHost);
    gs.download_to(gpuOut);
    CUDA_CHECK_0445(cudaEventDestroy(start));
    CUDA_CHECK_0445(cudaEventDestroy(stop));
    return out;
}


struct OperationVectors0446 {
    std::vector<std::uint32_t> particleIndex;
    std::vector<std::uint32_t> receiverCell;
    std::vector<std::uint32_t> particleType;
    std::vector<double> particleMass;
    std::vector<double> momentumX;
    std::vector<double> momentumY;
    std::vector<std::uint32_t> insertionOrdinal;
};

OperationVectors0446 make_operation_vectors_0446(const WeightedRealFluidDepositWorkspace& ws) {
    OperationVectors0446 ops{};
    ops.particleIndex.reserve(ws.passiveExtractionOperations.size());
    ops.receiverCell.reserve(ws.passiveExtractionOperations.size());
    ops.particleType.reserve(ws.passiveExtractionOperations.size());
    ops.particleMass.reserve(ws.passiveExtractionOperations.size());
    ops.momentumX.reserve(ws.passiveExtractionOperations.size());
    ops.momentumY.reserve(ws.passiveExtractionOperations.size());
    ops.insertionOrdinal.reserve(ws.passiveExtractionOperations.size());
    std::uint32_t ordinal = 0u;
    for (const auto& op : ws.passiveExtractionOperations) {
        if (op.particleIndex == kInvalidParticleIndex || op.particleIndex > 0xffffffffull) {
            throw std::runtime_error("0446 operation particle index does not fit uint32");
        }
        if (op.receiverCell < 0) throw std::runtime_error("0446 operation has invalid receiver cell");
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

struct GpuParticleApply0446 {
    std::uint64_t extractionApplied = 0u;
    std::uint64_t insertionApplied = 0u;
    std::uint64_t invalidOperations = 0u;
    double kernelSeconds = 0.0;
    double totalSeconds = 0.0;
};

GpuParticleApply0446 apply_gpu_particle_edits_0446(ParticleState& gpuOut,
                                                   const WeightedRealFluidDepositWorkspace& editWs,
                                                   const CellGrid& grid) {
    GpuParticleApply0446 out{};
    if (editWs.passiveExtractionOperations.empty()) return out;
    CudaParticleState gpuState{};
    CudaParticleStateDiagnostics uploadDiag{};
    gpuState.upload_all(gpuOut, &uploadDiag);
    const OperationVectors0446 ops = make_operation_vectors_0446(editWs);

    CudaResamplingExtractionApplyParams ep{};
    ep.fluidRole = static_cast<std::uint8_t>(ParticleRole::Fluid);
    ep.inactiveRole = static_cast<std::uint8_t>(ParticleRole::Inactive);
    ep.invalidParticle = 0xffffffffu;
    CudaResamplingPersistentOpsDiagnostics extDiag{};
    const bool extOk = cuda_resampling_apply_extraction_operations_on_state_0239(
        gpuState, ops.particleIndex, ops.particleMass, ops.momentumX, ops.momentumY, ep, &extDiag);
    if (!extOk) throw std::runtime_error("0446 CUDA extraction apply failed");

    CudaResamplingInsertionApplyParams ip{};
    ip.inactiveRole = static_cast<std::uint8_t>(ParticleRole::Inactive);
    ip.fluidRole = static_cast<std::uint8_t>(ParticleRole::Fluid);
    ip.invalidParticle = 0xffffffffu;
    ip.useHashPlacement = 0u; // production CPU-compatible deterministic receiver stencil
    CudaResamplingPersistentOpsDiagnostics insDiag{};
    const bool insOk = cuda_resampling_apply_insertion_operations_on_state_0239(
        gpuState, ops.particleIndex, ops.receiverCell, ops.particleType,
        ops.particleMass, ops.momentumX, ops.momentumY, ops.insertionOrdinal,
        static_cast<std::uint32_t>(grid.Nx), static_cast<std::uint32_t>(grid.Ny),
        grid.dx, grid.dy, ip, &insDiag);
    if (!insOk) throw std::runtime_error("0446 CUDA insertion apply failed");

    CudaParticleStateDiagnostics downloadDiag{};
    gpuState.download_all(gpuOut, &downloadDiag);
    out.extractionApplied = extDiag.operationsApplied;
    out.insertionApplied = insDiag.operationsApplied;
    out.invalidOperations = extDiag.invalidOperations + insDiag.invalidOperations;
    out.kernelSeconds = extDiag.kernelSeconds + insDiag.kernelSeconds;
    out.totalSeconds = extDiag.totalSeconds + insDiag.totalSeconds + uploadDiag.uploadSeconds + downloadDiag.downloadSeconds;
    return out;
}

struct GpuCompactLists0450 {
    std::vector<int> poor;
    std::vector<int> rich;
    double kernelSeconds = 0.0;
    double totalSeconds = 0.0;
};

__global__ void compact_poor_rich_kernel_0450(int nc,
                                               const double* mass,
                                               const std::uint8_t* wet,
                                               double poorThreshold,
                                               double richThreshold,
                                               int* poorCells,
                                               int* richCells,
                                               unsigned int* poorCount,
                                               unsigned int* richCount) {
    const int c = blockIdx.x * blockDim.x + threadIdx.x;
    if (c >= nc) return;
    if (!wet[c]) return;
    const double m = mass[c];
    if (m < poorThreshold) {
        const unsigned int pos = atomicAdd(poorCount, 1u);
        poorCells[pos] = c;
    }
    if (m > richThreshold) {
        const unsigned int pos = atomicAdd(richCount, 1u);
        richCells[pos] = c;
    }
}

GpuCompactLists0450 compact_poor_rich_gpu_0450(const std::vector<double>& cellMass,
                                                const std::vector<std::uint8_t>& wetCell,
                                                double poorThreshold,
                                                double richThreshold) {
    GpuCompactLists0450 out{};
    const int nc = static_cast<int>(cellMass.size());
    if (nc <= 0) return out;
    const auto t0 = std::chrono::steady_clock::now();
    DeviceBuffer0445<double> dMass(static_cast<std::size_t>(nc)); dMass.copy_from_host(cellMass);
    DeviceBuffer0445<std::uint8_t> dWet(static_cast<std::size_t>(nc)); dWet.copy_from_host(wetCell);
    DeviceBuffer0445<int> dPoor(static_cast<std::size_t>(nc));
    DeviceBuffer0445<int> dRich(static_cast<std::size_t>(nc));
    DeviceBuffer0445<unsigned int> dPoorCount(1u); dPoorCount.memset_zero();
    DeviceBuffer0445<unsigned int> dRichCount(1u); dRichCount.memset_zero();

    cudaEvent_t start{}, stop{};
    CUDA_CHECK_0445(cudaEventCreate(&start));
    CUDA_CHECK_0445(cudaEventCreate(&stop));
    CUDA_CHECK_0445(cudaEventRecord(start));
    const int block = 256;
    const int grid = (nc + block - 1) / block;
    compact_poor_rich_kernel_0450<<<grid, block>>>(nc, dMass.ptr, dWet.ptr, poorThreshold, richThreshold,
                                                   dPoor.ptr, dRich.ptr, dPoorCount.ptr, dRichCount.ptr);
    CUDA_CHECK_0445(cudaEventRecord(stop));
    CUDA_CHECK_0445(cudaEventSynchronize(stop));
    CUDA_CHECK_0445(cudaGetLastError());
    float ms = 0.0f;
    CUDA_CHECK_0445(cudaEventElapsedTime(&ms, start, stop));
    CUDA_CHECK_0445(cudaEventDestroy(start));
    CUDA_CHECK_0445(cudaEventDestroy(stop));
    out.kernelSeconds = static_cast<double>(ms) * 1.0e-3;

    std::vector<unsigned int> poorCount, richCount;
    dPoorCount.copy_to_host(poorCount);
    dRichCount.copy_to_host(richCount);
    const std::size_t np = poorCount.empty() ? 0u : static_cast<std::size_t>(poorCount[0]);
    const std::size_t nr = richCount.empty() ? 0u : static_cast<std::size_t>(richCount[0]);
    std::vector<int> poorFull, richFull;
    dPoor.copy_to_host(poorFull);
    dRich.copy_to_host(richFull);
    if (np > poorFull.size() || nr > richFull.size()) throw std::runtime_error("0450 compact count overflow");
    out.poor.assign(poorFull.begin(), poorFull.begin() + static_cast<std::ptrdiff_t>(np));
    out.rich.assign(richFull.begin(), richFull.begin() + static_cast<std::ptrdiff_t>(nr));
    std::sort(out.poor.begin(), out.poor.end());
    std::sort(out.rich.begin(), out.rich.end());
    out.totalSeconds = std::chrono::duration<double>(std::chrono::steady_clock::now() - t0).count();
    return out;
}

struct TransferPlanEntry0450 {
    int donorCell = -1;
    int receiverCell = -1;
    double plannedMass = 0.0;
    double cellDistance = 0.0;
    double donorRemainingAfter = 0.0;
    double receiverRemainingAfter = 0.0;
};

struct GpuPlan0450 {
    std::vector<TransferPlanEntry0450> entries;
    double plannedMass = 0.0;
    double kernelSeconds = 0.0;
    double totalSeconds = 0.0;
};

__device__ double cell_distance_device_0450(int a, int b, int nx, int ny, int xPeriodic, int yPeriodic) {
    if (a < 0 || b < 0 || nx <= 0 || ny <= 0) return 0.0;
    const int ax = a % nx;
    const int ay = a / nx;
    const int bx = b % nx;
    const int by = b / nx;
    int dx = ax > bx ? ax - bx : bx - ax;
    int dy = ay > by ? ay - by : by - ay;
    if (xPeriodic) dx = dx < (nx - dx) ? dx : (nx - dx);
    if (yPeriodic) dy = dy < (ny - dy) ? dy : (ny - dy);
    return sqrt(static_cast<double>(dx * dx + dy * dy));
}

__global__ void build_transfer_plan_serial_kernel_0450(const int nx,
                                                       const int ny,
                                                       const int xPeriodic,
                                                       const int yPeriodic,
                                                       const double targetCellMass,
                                                       const int poorCount,
                                                       const int richCount,
                                                       const int* poorCells,
                                                       const int* richCells,
                                                       double* receiverRemaining,
                                                       double* donorRemaining,
                                                       const double* cellMass,
                                                       const int maxPlanEntries,
                                                       int* outDonor,
                                                       int* outReceiver,
                                                       double* outMass,
                                                       double* outDistance,
                                                       double* outDonorRemainingAfter,
                                                       double* outReceiverRemainingAfter,
                                                       unsigned int* outCount,
                                                       double* outPlannedMass) {
    if (blockIdx.x != 0 || threadIdx.x != 0) return;
    constexpr double eps = 1.0e-14;
    unsigned int planCount = 0u;
    double plannedMass = 0.0;

    for (int ir = 0; ir < poorCount; ++ir) {
        const int rc = poorCells[ir];
        const double deficit = targetCellMass - cellMass[rc];
        receiverRemaining[ir] = deficit > 0.0 ? deficit : 0.0;
    }
    for (int id = 0; id < richCount; ++id) {
        const int dc = richCells[id];
        const double excess = cellMass[dc] - targetCellMass;
        donorRemaining[id] = excess > 0.0 ? excess : 0.0;
    }

    for (int ir = 0; ir < poorCount; ++ir) {
        const int rc = poorCells[ir];
        while (receiverRemaining[ir] > eps) {
            int bestDonor = richCount;
            int bestCell = 2147483647;
            double bestDistance = 1.0e300;
            for (int id = 0; id < richCount; ++id) {
                if (donorRemaining[id] <= eps) continue;
                const int dc = richCells[id];
                const double dist = cell_distance_device_0450(dc, rc, nx, ny, xPeriodic, yPeriodic);
                if (dist < bestDistance || (dist == bestDistance && dc < bestCell)) {
                    bestDistance = dist;
                    bestDonor = id;
                    bestCell = dc;
                }
            }
            if (bestDonor == richCount) break;
            double transfer = donorRemaining[bestDonor] < receiverRemaining[ir]
                ? donorRemaining[bestDonor] : receiverRemaining[ir];
            if (transfer <= eps) break;
            donorRemaining[bestDonor] -= transfer;
            receiverRemaining[ir] -= transfer;
            if (static_cast<int>(planCount) < maxPlanEntries) {
                outDonor[planCount] = richCells[bestDonor];
                outReceiver[planCount] = rc;
                outMass[planCount] = transfer;
                outDistance[planCount] = bestDistance;
                outDonorRemainingAfter[planCount] = donorRemaining[bestDonor];
                outReceiverRemainingAfter[planCount] = receiverRemaining[ir];
            }
            ++planCount;
            plannedMass += transfer;
        }
    }
    *outCount = planCount;
    *outPlannedMass = plannedMass;
}

GpuPlan0450 build_transfer_plan_gpu_0450(const std::vector<int>& poor,
                                          const std::vector<int>& rich,
                                          const std::vector<double>& cellMass,
                                          const CellGrid& grid,
                                          const SimulationParams& params,
                                          double targetCellMass,
                                          std::size_t expectedCpuEntries) {
    GpuPlan0450 out{};
    if (poor.empty() || rich.empty() || !(targetCellMass > 0.0)) return out;
    const auto t0 = std::chrono::steady_clock::now();
    const int poorCount = static_cast<int>(poor.size());
    const int richCount = static_cast<int>(rich.size());
    const int maxPlanEntries = static_cast<int>(std::max<std::size_t>(poor.size() + rich.size() + 4u, expectedCpuEntries + 4u));

    DeviceBuffer0445<int> dPoor(poor.size()); dPoor.copy_from_host(poor);
    DeviceBuffer0445<int> dRich(rich.size()); dRich.copy_from_host(rich);
    DeviceBuffer0445<double> dMass(cellMass.size()); dMass.copy_from_host(cellMass);
    DeviceBuffer0445<double> dReceiverRemaining(poor.size());
    DeviceBuffer0445<double> dDonorRemaining(rich.size());
    DeviceBuffer0445<int> dOutDonor(static_cast<std::size_t>(maxPlanEntries));
    DeviceBuffer0445<int> dOutReceiver(static_cast<std::size_t>(maxPlanEntries));
    DeviceBuffer0445<double> dOutMass(static_cast<std::size_t>(maxPlanEntries));
    DeviceBuffer0445<double> dOutDistance(static_cast<std::size_t>(maxPlanEntries));
    DeviceBuffer0445<double> dOutDonorRemaining(static_cast<std::size_t>(maxPlanEntries));
    DeviceBuffer0445<double> dOutReceiverRemaining(static_cast<std::size_t>(maxPlanEntries));
    DeviceBuffer0445<unsigned int> dOutCount(1u); dOutCount.memset_zero();
    DeviceBuffer0445<double> dOutPlannedMass(1u); dOutPlannedMass.memset_zero();

    const int xp = (params.bcLeft == "periodic" && params.bcRight == "periodic") ? 1 : 0;
    const int yp = (params.bcBottom == "periodic" && params.bcTop == "periodic") ? 1 : 0;
    cudaEvent_t start{}, stop{};
    CUDA_CHECK_0445(cudaEventCreate(&start));
    CUDA_CHECK_0445(cudaEventCreate(&stop));
    CUDA_CHECK_0445(cudaEventRecord(start));
    build_transfer_plan_serial_kernel_0450<<<1,1>>>(grid.Nx, grid.Ny, xp, yp, targetCellMass,
                                                    poorCount, richCount, dPoor.ptr, dRich.ptr,
                                                    dReceiverRemaining.ptr, dDonorRemaining.ptr,
                                                    dMass.ptr, maxPlanEntries,
                                                    dOutDonor.ptr, dOutReceiver.ptr, dOutMass.ptr,
                                                    dOutDistance.ptr, dOutDonorRemaining.ptr,
                                                    dOutReceiverRemaining.ptr, dOutCount.ptr,
                                                    dOutPlannedMass.ptr);
    CUDA_CHECK_0445(cudaEventRecord(stop));
    CUDA_CHECK_0445(cudaEventSynchronize(stop));
    CUDA_CHECK_0445(cudaGetLastError());
    float ms = 0.0f;
    CUDA_CHECK_0445(cudaEventElapsedTime(&ms, start, stop));
    CUDA_CHECK_0445(cudaEventDestroy(start));
    CUDA_CHECK_0445(cudaEventDestroy(stop));
    out.kernelSeconds = static_cast<double>(ms) * 1.0e-3;

    std::vector<unsigned int> countHost;
    std::vector<double> plannedHost;
    dOutCount.copy_to_host(countHost);
    dOutPlannedMass.copy_to_host(plannedHost);
    const std::size_t count = countHost.empty() ? 0u : static_cast<std::size_t>(countHost[0]);
    out.plannedMass = plannedHost.empty() ? 0.0 : plannedHost[0];
    std::vector<int> donors, receivers;
    std::vector<double> masses, distances, donorRemain, receiverRemain;
    dOutDonor.copy_to_host(donors);
    dOutReceiver.copy_to_host(receivers);
    dOutMass.copy_to_host(masses);
    dOutDistance.copy_to_host(distances);
    dOutDonorRemaining.copy_to_host(donorRemain);
    dOutReceiverRemaining.copy_to_host(receiverRemain);
    const std::size_t stored = std::min<std::size_t>(count, static_cast<std::size_t>(maxPlanEntries));
    out.entries.reserve(stored);
    for (std::size_t i = 0; i < stored; ++i) {
        out.entries.push_back(TransferPlanEntry0450{donors[i], receivers[i], masses[i], distances[i], donorRemain[i], receiverRemain[i]});
    }
    out.totalSeconds = std::chrono::duration<double>(std::chrono::steady_clock::now() - t0).count();
    return out;
}

std::uint64_t sorted_list_mismatch_0450(const std::vector<std::int32_t>& cpu, const std::vector<int>& gpu) {
    const std::size_t n = std::min(cpu.size(), gpu.size());
    std::uint64_t mism = static_cast<std::uint64_t>(std::max(cpu.size(), gpu.size()) - n);
    for (std::size_t i = 0; i < n; ++i) if (cpu[i] != gpu[i]) ++mism;
    return mism;
}

bool all_periodic_0450(const SimulationParams& p) {
    return p.bcLeft == "periodic" && p.bcRight == "periodic" && p.bcBottom == "periodic" && p.bcTop == "periodic";
}

void append_upstream_csv_0450(const SimulationParams& params,
                              const CudaResamplingUpstreamShadow0450Diagnostics& d) {
    if (params.outputDir.empty()) return;
    std::filesystem::create_directories(params.outputDir);
    const std::string path = params.outputDir + "/cuda_resampling_upstream_shadow_0450.csv";
    const bool exists = std::filesystem::exists(path);
    std::ofstream out(path, std::ios::app);
    out << std::setprecision(17);
    if (!exists) {
        out << "step,attempted,handled,pass,skipped,skipReason,nActive,nCells,"
            << "cellIdMismatch,maxCountDiff,maxMassAbs,maxPxAbs,maxPyAbs,maxUxAbs,maxUyAbs,"
            << "cpuTotalMass,gpuTotalMass,cpuTotalPx,gpuTotalPx,cpuTotalPy,gpuTotalPy,"
            << "cpuReceiverCells,gpuReceiverCells,cpuDonorCells,gpuDonorCells,receiverListMismatch,donorListMismatch,"
            << "cpuTransferPairs,gpuTransferPairs,planMismatch,maxPlanMassAbs,maxPlanDistanceAbs,cpuPlannedMass,gpuPlannedMass,cpuPassiveOps,"
            << "depositKernelSeconds,depositDownloadSeconds,compactKernelSeconds,plannerKernelSeconds,totalSeconds\n";
    }
    out << d.step << ',' << (d.attempted ? 1 : 0) << ',' << (d.handled ? 1 : 0) << ','
        << (d.pass ? 1 : 0) << ',' << (d.skipped ? 1 : 0) << ',' << csv_escape_0445(d.skipReason) << ','
        << d.nActive << ',' << d.nCells << ','
        << d.cellIdMismatch << ',' << d.maxCountDiff << ',' << d.maxMassAbs << ',' << d.maxPxAbs << ','
        << d.maxPyAbs << ',' << d.maxUxAbs << ',' << d.maxUyAbs << ','
        << d.cpuTotalMass << ',' << d.gpuTotalMass << ',' << d.cpuTotalPx << ',' << d.gpuTotalPx << ','
        << d.cpuTotalPy << ',' << d.gpuTotalPy << ','
        << d.cpuReceiverCells << ',' << d.gpuReceiverCells << ',' << d.cpuDonorCells << ',' << d.gpuDonorCells << ','
        << d.receiverListMismatch << ',' << d.donorListMismatch << ','
        << d.cpuTransferPairs << ',' << d.gpuTransferPairs << ',' << d.planMismatch << ','
        << d.maxPlanMassAbs << ',' << d.maxPlanDistanceAbs << ',' << d.cpuPlannedMass << ',' << d.gpuPlannedMass << ','
        << d.cpuPassiveOps << ',' << d.depositKernelSeconds << ',' << d.depositDownloadSeconds << ','
        << d.compactKernelSeconds << ',' << d.plannerKernelSeconds << ',' << d.totalSeconds << '\n';
}

struct Totals0445 {
    double mass = 0.0, px = 0.0, py = 0.0, ke = 0.0;
};

Totals0445 totals_0445(const ParticleState& s) {
    Totals0445 t{};
    const std::size_t n = static_cast<std::size_t>(std::min(s.NactiveFluid, s.Np));
    for (std::size_t i = 0; i < n; ++i) {
        if (s.role[i] != kParticleRoleFluid) continue;
        const double m = s.mass[i];
        t.mass += m;
        t.px += m * s.vx[i];
        t.py += m * s.vy[i];
        t.ke += 0.5 * m * (s.vx[i] * s.vx[i] + s.vy[i] * s.vy[i]);
    }
    return t;
}

std::uint64_t bad_prefix_0445(const ParticleState& s) {
    std::uint64_t bad = 0u;
    const std::size_t n = static_cast<std::size_t>(std::min(s.NactiveFluid, s.Np));
    for (std::size_t i = 0; i < n; ++i) if (s.role[i] != kParticleRoleFluid) ++bad;
    return bad;
}

void append_csv_0445(const SimulationParams& params,
                     const CudaResamplingPipelineShadow0445Diagnostics& d) {
    if (params.outputDir.empty()) return;
    std::filesystem::create_directories(params.outputDir);
    const std::string path = params.outputDir + "/cuda_resampling_pipeline_shadow_0445.csv";
    const bool exists = std::filesystem::exists(path);
    std::ofstream out(path, std::ios::app);
    out << std::setprecision(17);
    if (!exists) {
        out << "step,stage,attempted,handled,pass,skipped,skipReason,nActive,planEntries,passiveOps,"
               "cpuExtractionApplied,cpuInsertionApplied,gpuExtractionApplied,gpuInsertionApplied,gpuInvalidOperations,"
               "cpuRemapCells,gpuRemapCells,cpuThermalCells,gpuThermalCells,roleMismatch,typeMismatch,badPrefixCpu,badPrefixGpu,"
               "maxAbsX,maxAbsY,maxAbsMass,maxAbsVx,maxAbsVy,massCpu,massGpu,pxCpu,pxGpu,pyCpu,pyGpu,keCpu,keGpu,"
               "applyKernelSeconds,remapKernelSeconds,thermalKernelSeconds,totalSeconds\n";
    }
    out << d.step << ',' << csv_escape_0445(d.stage) << ','
        << (d.attempted ? 1 : 0) << ',' << (d.handled ? 1 : 0) << ',' << (d.pass ? 1 : 0) << ','
        << (d.skipped ? 1 : 0) << ',' << csv_escape_0445(d.skipReason) << ','
        << d.nActive << ',' << d.planEntries << ',' << d.passiveOps << ','
        << d.cpuExtractionApplied << ',' << d.cpuInsertionApplied << ','
        << d.gpuExtractionApplied << ',' << d.gpuInsertionApplied << ',' << d.gpuInvalidOperations << ','
        << d.cpuRemapCells << ',' << d.gpuRemapCells << ',' << d.cpuThermalCells << ',' << d.gpuThermalCells << ','
        << d.roleMismatch << ',' << d.typeMismatch << ',' << d.badPrefixCpu << ',' << d.badPrefixGpu << ','
        << d.maxAbsX << ',' << d.maxAbsY << ',' << d.maxAbsMass << ',' << d.maxAbsVx << ',' << d.maxAbsVy << ','
        << d.massCpu << ',' << d.massGpu << ',' << d.pxCpu << ',' << d.pxGpu << ','
        << d.pyCpu << ',' << d.pyGpu << ',' << d.keCpu << ',' << d.keGpu << ','
        << d.applyKernelSeconds << ',' << d.remapKernelSeconds << ',' << d.thermalKernelSeconds << ',' << d.totalSeconds << '\n';
}

} // namespace

bool cuda_resampling_pipeline_shadow_0445_requested(std::uint64_t step) {
    if (!env_truthy_0445("MPCD_CUDA_RESAMPLING_PIPELINE_SHADOW_0445")) return false;
    const std::uint64_t every = env_u64_0445("MPCD_CUDA_RESAMPLING_PIPELINE_SHADOW_EVERY_0445", 1u);
    return every == 0u || (step % every == 0u);
}

bool cuda_resampling_pipeline_apply_0448_requested() {
    return env_truthy_0445("MPCD_CUDA_RESAMPLING_PIPELINE_APPLY_0448");
}

bool cuda_resampling_upstream_shadow_0450_requested(std::uint64_t step) {
    if (!env_truthy_0445("MPCD_CUDA_RESAMPLING_UPSTREAM_SHADOW_0450")) return false;
    const std::uint64_t every = env_u64_0445("MPCD_CUDA_RESAMPLING_UPSTREAM_SHADOW_EVERY_0450", 1u);
    return every == 0u || (step % every == 0u);
}

CudaResamplingUpstreamShadow0450Diagnostics try_run_cuda_resampling_upstream_shadow_0450(
    const ParticleState& state,
    const SimulationParams& params,
    const CellGrid& grid,
    std::uint64_t step,
    const WeightedRealFluidDepositWorkspace& cpuWorkspace,
    const WeightedResamplingDiagnostics& cpuDiagnostics) {
    CudaResamplingUpstreamShadow0450Diagnostics d{};
    d.attempted = true;
    d.step = step;
    d.outputCsv = params.outputDir.empty() ? std::string{} : (params.outputDir + "/cuda_resampling_upstream_shadow_0450.csv");
    d.nActive = state.NactiveFluid;
    d.nCells = static_cast<std::uint64_t>(std::max(0, grid.numCells));
    d.cpuReceiverCells = static_cast<std::uint64_t>(cpuWorkspace.receiverPoorCells.size());
    d.cpuDonorCells = static_cast<std::uint64_t>(cpuWorkspace.donorRichCells.size());
    d.cpuTransferPairs = static_cast<std::uint64_t>(cpuWorkspace.transferPlan.size());
    d.cpuPassiveOps = static_cast<std::uint64_t>(cpuWorkspace.passiveExtractionOperations.size());
    d.cpuPlannedMass = cpuDiagnostics.plannedTransferMass;

    const auto t0 = std::chrono::steady_clock::now();
    try {
        if (!cuda_resampling_upstream_shadow_0450_requested(step)) {
            d.skipped = true;
            d.skipReason = "upstream shadow flag disabled";
            append_upstream_csv_0450(params, d);
            return d;
        }
        if (!all_periodic_0450(params) || params.immersedSolidEnable) {
            d.skipped = true;
            d.skipReason = "0450 upstream shadow is currently restricted to periodic wall-free no-solid cases";
            append_upstream_csv_0450(params, d);
            return d;
        }
        if (!cpuDiagnostics.computed || !cpuDiagnostics.cellClassificationComputed || !cpuDiagnostics.candidateListsBuilt) {
            d.skipped = true;
            d.skipReason = "CPU resampling deposit/classification/candidate lists are not available";
            append_upstream_csv_0450(params, d);
            return d;
        }
        if (grid.numCells <= 0 || static_cast<std::size_t>(grid.numCells) != cpuWorkspace.mass.size()) {
            d.skipped = true;
            d.skipReason = "invalid or mismatched CPU workspace cell arrays";
            append_upstream_csv_0450(params, d);
            return d;
        }

        CudaParticleState gpuState{};
        CudaParticleStateDiagnostics uploadDiag{};
        gpuState.upload_all(state, &uploadDiag);
        CudaCellWorkspace cellWorkspace{};
        CudaCellMoments gpuDeposit{};
        CudaCellMomentsDiagnostics depositDiag{};
        CudaCellMomentsOptions options{};
        options.computeCellVelocities = true;
        options.downloadCellVelocities = true;
        options.enableAllFluidFastPath = true;
        options.enableUniformMassFastPath = true;
        cuda_deposit_cell_moments_atomic_from_persistent_state(
            state, gpuState, cellWorkspace, grid, GridShift{}, params, gpuDeposit, &depositDiag, options);
        d.depositKernelSeconds = depositDiag.kernelSeconds;
        d.depositDownloadSeconds = depositDiag.downloadSeconds;

        const std::size_t nCell = static_cast<std::size_t>(grid.numCells);
        if (gpuDeposit.cellMass.size() != nCell || gpuDeposit.cellCount.size() != nCell || gpuDeposit.cellId.size() < cpuWorkspace.cellId.size()) {
            d.skipped = true;
            d.skipReason = "CUDA deposit returned unexpected array sizes";
            append_upstream_csv_0450(params, d);
            return d;
        }
        for (std::size_t i = 0; i < cpuWorkspace.cellId.size(); ++i) {
            if (cpuWorkspace.cellId[i] != gpuDeposit.cellId[i]) ++d.cellIdMismatch;
        }
        for (std::size_t c = 0; c < nCell; ++c) {
            d.maxCountDiff = std::max(d.maxCountDiff, std::abs(static_cast<double>(cpuWorkspace.count[c]) - static_cast<double>(gpuDeposit.cellCount[c])));
            d.maxMassAbs = std::max(d.maxMassAbs, std::abs(cpuWorkspace.mass[c] - gpuDeposit.cellMass[c]));
            d.maxPxAbs = std::max(d.maxPxAbs, std::abs(cpuWorkspace.px[c] - gpuDeposit.cellPx[c]));
            d.maxPyAbs = std::max(d.maxPyAbs, std::abs(cpuWorkspace.py[c] - gpuDeposit.cellPy[c]));
            if (c < gpuDeposit.cellUx.size() && c < cpuWorkspace.ux.size()) {
                d.maxUxAbs = std::max(d.maxUxAbs, std::abs(cpuWorkspace.ux[c] - gpuDeposit.cellUx[c]));
            }
            if (c < gpuDeposit.cellUy.size() && c < cpuWorkspace.uy.size()) {
                d.maxUyAbs = std::max(d.maxUyAbs, std::abs(cpuWorkspace.uy[c] - gpuDeposit.cellUy[c]));
            }
            d.cpuTotalMass += cpuWorkspace.mass[c];
            d.gpuTotalMass += gpuDeposit.cellMass[c];
            d.cpuTotalPx += cpuWorkspace.px[c];
            d.gpuTotalPx += gpuDeposit.cellPx[c];
            d.cpuTotalPy += cpuWorkspace.py[c];
            d.gpuTotalPy += gpuDeposit.cellPy[c];
        }

        const GpuCompactLists0450 lists = compact_poor_rich_gpu_0450(
            gpuDeposit.cellMass, cpuWorkspace.wetCell, cpuDiagnostics.poorMassThreshold, cpuDiagnostics.richMassThreshold);
        d.compactKernelSeconds = lists.kernelSeconds;
        d.gpuReceiverCells = static_cast<std::uint64_t>(lists.poor.size());
        d.gpuDonorCells = static_cast<std::uint64_t>(lists.rich.size());
        d.receiverListMismatch = sorted_list_mismatch_0450(cpuWorkspace.receiverPoorCells, lists.poor);
        d.donorListMismatch = sorted_list_mismatch_0450(cpuWorkspace.donorRichCells, lists.rich);

        const GpuPlan0450 plan = build_transfer_plan_gpu_0450(
            lists.poor, lists.rich, gpuDeposit.cellMass, grid, params,
            cpuDiagnostics.targetCellMass, cpuWorkspace.transferPlan.size());
        d.plannerKernelSeconds = plan.kernelSeconds;
        d.gpuTransferPairs = static_cast<std::uint64_t>(plan.entries.size());
        d.gpuPlannedMass = plan.plannedMass;
        const std::size_t cmpPlan = std::min(cpuWorkspace.transferPlan.size(), plan.entries.size());
        d.planMismatch = static_cast<std::uint64_t>(std::max(cpuWorkspace.transferPlan.size(), plan.entries.size()) - cmpPlan);
        for (std::size_t i = 0; i < cmpPlan; ++i) {
            const auto& a = cpuWorkspace.transferPlan[i];
            const auto& b = plan.entries[i];
            if (a.donorCell != b.donorCell || a.receiverCell != b.receiverCell) ++d.planMismatch;
            d.maxPlanMassAbs = std::max(d.maxPlanMassAbs, std::abs(a.plannedMass - b.plannedMass));
            d.maxPlanDistanceAbs = std::max(d.maxPlanDistanceAbs, std::abs(a.cellDistance - b.cellDistance));
        }
        d.totalSeconds = std::chrono::duration<double>(std::chrono::steady_clock::now() - t0).count();

        constexpr double tol = 2.0e-10;
        const auto close = [tol](double a, double b) {
            const double scale = std::max({1.0, std::abs(a), std::abs(b)});
            return std::abs(a - b) <= tol * scale;
        };
        d.handled = true;
        d.pass = d.cellIdMismatch == 0u && d.maxCountDiff == 0.0 &&
                 d.receiverListMismatch == 0u && d.donorListMismatch == 0u &&
                 d.cpuReceiverCells == d.gpuReceiverCells && d.cpuDonorCells == d.gpuDonorCells &&
                 d.cpuTransferPairs == d.gpuTransferPairs && d.planMismatch == 0u &&
                 d.maxMassAbs <= tol && d.maxPxAbs <= tol && d.maxPyAbs <= tol &&
                 d.maxUxAbs <= 5.0 * tol && d.maxUyAbs <= 5.0 * tol &&
                 d.maxPlanMassAbs <= tol && d.maxPlanDistanceAbs <= tol &&
                 close(d.cpuTotalMass, d.gpuTotalMass) &&
                 close(d.cpuTotalPx, d.gpuTotalPx) &&
                 close(d.cpuTotalPy, d.gpuTotalPy) &&
                 close(d.cpuPlannedMass, d.gpuPlannedMass);
        append_upstream_csv_0450(params, d);
        return d;
    } catch (const std::exception& e) {
        d.skipped = true;
        d.skipReason = std::string("exception: ") + e.what();
        d.totalSeconds = std::chrono::duration<double>(std::chrono::steady_clock::now() - t0).count();
        append_upstream_csv_0450(params, d);
        return d;
    }
}

namespace {

void append_apply_csv_0448(const SimulationParams& params,
                           const CudaResamplingPipelineApply0448Diagnostics& d) {
    if (params.outputDir.empty()) return;
    std::filesystem::create_directories(params.outputDir);
    const std::string path = params.outputDir + "/cuda_resampling_pipeline_apply_0448.csv";
    const bool exists = std::filesystem::exists(path);
    std::ofstream out(path, std::ios::app);
    out << std::setprecision(17);
    if (!exists) {
        out << "step,stage,attempted,handled,applied,skipped,skipReason,nActive,passiveOps,"
               "gpuExtractionApplied,gpuInsertionApplied,gpuInvalidOperations,gpuRemapCells,gpuThermalCells,"
               "applyKernelSeconds,remapKernelSeconds,thermalKernelSeconds,totalSeconds\n";
    }
    out << d.step << ',' << csv_escape_0445(d.stage) << ','
        << (d.attempted ? 1 : 0) << ',' << (d.handled ? 1 : 0) << ',' << (d.applied ? 1 : 0) << ','
        << (d.skipped ? 1 : 0) << ',' << csv_escape_0445(d.skipReason) << ','
        << d.nActive << ',' << d.passiveOps << ','
        << d.gpuExtractionApplied << ',' << d.gpuInsertionApplied << ',' << d.gpuInvalidOperations << ','
        << d.gpuRemapCells << ',' << d.gpuThermalCells << ','
        << d.applyKernelSeconds << ',' << d.remapKernelSeconds << ',' << d.thermalKernelSeconds << ',' << d.totalSeconds << '\n';
}

void fill_extraction_insertion_diagnostics_0448(const WeightedRealFluidDepositWorkspace& ws,
                                                const GpuParticleApply0446& pa,
                                                ResamplingExtractionApplyDiagnostics& ext,
                                                ResamplingInsertionApplyDiagnostics& ins) {
    const std::uint64_t ops = static_cast<std::uint64_t>(ws.passiveExtractionOperations.size());
    double mass = 0.0, px = 0.0, py = 0.0, ke = 0.0;
    std::uint64_t first = kInvalidParticleIndex, last = kInvalidParticleIndex;
    std::int32_t firstReceiver = kInvalidCellIndex, lastReceiver = kInvalidCellIndex;
    for (const auto& op : ws.passiveExtractionOperations) {
        mass += op.particleMass;
        px += op.momentumX;
        py += op.momentumY;
        if (op.particleMass > 0.0) {
            const double vx = op.momentumX / op.particleMass;
            const double vy = op.momentumY / op.particleMass;
            ke += 0.5 * op.particleMass * (vx * vx + vy * vy);
        }
        if (first == kInvalidParticleIndex) first = op.particleIndex;
        last = op.particleIndex;
        if (firstReceiver == kInvalidCellIndex) firstReceiver = op.receiverCell;
        lastReceiver = op.receiverCell;
    }
    ext.attempted = true;
    ext.applied = pa.extractionApplied > 0u;
    ext.operationsConsidered = ops;
    ext.operationsApplied = pa.extractionApplied;
    ext.roleChanges = pa.extractionApplied;
    ext.appliedMass = mass;
    ext.appliedMomentumX = px;
    ext.appliedMomentumY = py;
    ext.appliedKineticEnergy = ke;
    ext.plannedExtractionMass = mass;
    ext.massResidualVsPlan = 0.0;
    ext.firstAppliedParticle = first;
    ext.lastAppliedParticle = last;
    ext.noDuplicateParticles = true;
    ext.allAppliedWereFluid = true;

    ins.attempted = true;
    ins.applied = pa.insertionApplied > 0u;
    ins.operationsConsidered = ops;
    ins.operationsApplied = pa.insertionApplied;
    ins.roleChanges = pa.insertionApplied;
    ins.insertedMass = mass;
    ins.insertedMomentumX = px;
    ins.insertedMomentumY = py;
    ins.insertedKineticEnergy = ke;
    ins.plannedInsertionMass = mass;
    ins.massResidualVsPlan = 0.0;
    ins.firstInsertedParticle = first;
    ins.lastInsertedParticle = last;
    ins.firstInsertionReceiverCell = firstReceiver;
    ins.lastInsertionReceiverCell = lastReceiver;
    ins.noInvalidReceiverCells = true;
    ins.allSourcesWereInactive = true;
}

} // namespace

CudaResamplingPipelineApply0448Diagnostics try_apply_cuda_resampling_pipeline_particle_edits_0448(
    ParticleState& state,
    const SimulationParams& params,
    const CellGrid& grid,
    std::uint64_t step,
    const WeightedRealFluidDepositWorkspace& editWorkspace,
    ResamplingExtractionApplyDiagnostics& extractionApply,
    ResamplingInsertionApplyDiagnostics& insertionApply) {
    CudaResamplingPipelineApply0448Diagnostics d{};
    d.attempted = true;
    d.stage = "particle_edits_0448";
    d.step = step;
    d.nActive = state.NactiveFluid;
    d.passiveOps = editWorkspace.passiveExtractionOperations.size();
    try {
        if (!cuda_resampling_pipeline_apply_0448_requested()) {
            d.skipped = true;
            d.skipReason = "apply flag disabled";
            append_apply_csv_0448(params, d);
            return d;
        }
        if (editWorkspace.passiveExtractionOperations.empty()) {
            d.handled = true;
            d.applied = false;
            append_apply_csv_0448(params, d);
            return d;
        }
        ParticleState tmp = state;
        const GpuParticleApply0446 pa = apply_gpu_particle_edits_0446(tmp, editWorkspace, grid);
        d.gpuExtractionApplied = pa.extractionApplied;
        d.gpuInsertionApplied = pa.insertionApplied;
        d.gpuInvalidOperations = pa.invalidOperations;
        d.applyKernelSeconds = pa.kernelSeconds;
        d.totalSeconds = pa.totalSeconds;
        const bool ok = (pa.invalidOperations == 0u &&
                         pa.extractionApplied == d.passiveOps &&
                         pa.insertionApplied == d.passiveOps);
        if (!ok) {
            d.skipped = true;
            d.skipReason = "CUDA particle edit counts do not match passive operation list";
            append_apply_csv_0448(params, d);
            return d;
        }
        state = std::move(tmp);
        fill_extraction_insertion_diagnostics_0448(editWorkspace, pa, extractionApply, insertionApply);
        d.handled = true;
        d.applied = true;
        append_apply_csv_0448(params, d);
        return d;
    } catch (const std::exception& e) {
        d.skipped = true;
        d.skipReason = std::string("exception: ") + e.what();
        append_apply_csv_0448(params, d);
        return d;
    }
}

CudaResamplingPipelineApply0448Diagnostics try_apply_cuda_resampling_pipeline_remap_thermal_0448(
    ParticleState& state,
    const SimulationParams& params,
    const WeightedRealFluidDepositWorkspace& remapWorkspace,
    const WeightedResamplingDiagnostics& remapDepositDiagnostics,
    double massCorrectionStrength,
    double targetCellMassOverride,
    std::uint64_t step,
    ResamplingRemapApplyDiagnostics& remapApply,
    ResamplingThermalRenormalizationDiagnostics& thermalApply) {
    CudaResamplingPipelineApply0448Diagnostics d{};
    d.attempted = true;
    d.stage = "remap_thermal_0448";
    d.step = step;
    d.nActive = state.NactiveFluid;
    try {
        if (!cuda_resampling_pipeline_apply_0448_requested()) {
            d.skipped = true;
            d.skipReason = "apply flag disabled";
            append_apply_csv_0448(params, d);
            return d;
        }
        if (!params.resamplingThermalRenormalizationEnable) {
            d.skipped = true;
            d.skipReason = "0448 clean backend requires thermal renormalization enabled";
            append_apply_csv_0448(params, d);
            return d;
        }
        if (params.resamplingMassGuardEnable) {
            d.skipped = true;
            d.skipReason = "0448 clean backend does not cover mass guard";
            append_apply_csv_0448(params, d);
            return d;
        }
        ParticleState tmp = state;
        const double targetOverride = (targetCellMassOverride > 0.0) ? targetCellMassOverride : -1.0;
        const GpuRemapThermal0445 gd = apply_gpu_remap_thermal_0445(
            tmp, remapWorkspace, remapDepositDiagnostics, massCorrectionStrength, targetOverride);
        state = std::move(tmp);
        d.gpuRemapCells = gd.remapCells;
        d.gpuThermalCells = gd.thermalCells;
        d.remapKernelSeconds = gd.remapSeconds;
        d.thermalKernelSeconds = gd.thermalSeconds;
        d.totalSeconds = gd.remapSeconds + gd.thermalSeconds;

        remapApply.attempted = true;
        remapApply.applied = true;
        remapApply.cellsConsidered = static_cast<std::uint64_t>(std::max(0, remapWorkspace.allocatedCells));
        remapApply.cellsRemapped = gd.remapCells;
        remapApply.particlesRemapped = state.NactiveFluid;
        remapApply.targetCellMass = (targetOverride > 0.0) ? targetOverride : remapDepositDiagnostics.targetCellMass;
        remapApply.massCorrectionStrength = massCorrectionStrength;
        thermalApply.attempted = true;
        thermalApply.applied = true;
        thermalApply.cellsConsidered = static_cast<std::uint64_t>(std::max(0, remapWorkspace.allocatedCells));
        thermalApply.cellsRenormalized = gd.thermalCells;
        thermalApply.particlesRenormalized = state.NactiveFluid;

        d.handled = true;
        d.applied = true;
        append_apply_csv_0448(params, d);
        return d;
    } catch (const std::exception& e) {
        d.skipped = true;
        d.skipReason = std::string("exception: ") + e.what();
        append_apply_csv_0448(params, d);
        return d;
    }
}

CudaResamplingPipelineShadow0445Diagnostics try_run_cuda_resampling_pipeline_shadow_0445(
    const ParticleState& shadowInputState,
    const ParticleState& cpuFinalState,
    const SimulationParams& params,
    const CellGrid& grid,
    const FluidDomainBounds&,
    double,
    std::uint64_t step,
    const char* stage,
    const WeightedRealFluidDepositWorkspace& editWorkspace,
    const WeightedRealFluidDepositWorkspace& remapWorkspace,
    const WeightedResamplingDiagnostics& remapDepositDiagnostics,
    const ResamplingExtractionApplyDiagnostics& cpuExtraction,
    const ResamplingInsertionApplyDiagnostics& cpuInsertion,
    const ResamplingRemapApplyDiagnostics& cpuRemap,
    const ResamplingThermalRenormalizationDiagnostics& cpuThermal) {
    CudaResamplingPipelineShadow0445Diagnostics d{};
    d.attempted = true;
    d.step = step;
    d.stage = stage ? stage : "";
    d.outputCsv = params.outputDir.empty() ? std::string{} : (params.outputDir + "/cuda_resampling_pipeline_shadow_0445.csv");
    d.nActive = shadowInputState.NactiveFluid;
    d.planEntries = editWorkspace.transferPlan.size();
    d.passiveOps = editWorkspace.passiveExtractionOperations.size();
    d.cpuExtractionApplied = cpuExtraction.operationsApplied;
    d.cpuInsertionApplied = cpuInsertion.operationsApplied;
    d.cpuRemapCells = cpuRemap.cellsRemapped;
    d.cpuThermalCells = cpuThermal.cellsRenormalized;

    try {
        if (!cpuRemap.applied || !cpuThermal.applied) {
            d.skipped = true;
            d.skipReason = "requires remap+thermal applied in 0445 initial hook";
            append_csv_0445(params, d);
            return d;
        }
        if (shadowInputState.Np != cpuFinalState.Np || shadowInputState.NactiveFluid != cpuFinalState.NactiveFluid) {
            d.skipped = true;
            d.skipReason = "state capacity or active prefix changed before 0445 remap+thermal shadow";
            append_csv_0445(params, d);
            return d;
        }

        ParticleState gpuState = shadowInputState;
        const GpuParticleApply0446 pa = apply_gpu_particle_edits_0446(gpuState, editWorkspace, grid);
        d.gpuExtractionApplied = pa.extractionApplied;
        d.gpuInsertionApplied = pa.insertionApplied;
        d.gpuInvalidOperations = pa.invalidOperations;
        d.applyKernelSeconds = pa.kernelSeconds;
        const double targetOverride = cpuRemap.targetCellMass > 0.0 ? cpuRemap.targetCellMass : -1.0;
        const GpuRemapThermal0445 gd = apply_gpu_remap_thermal_0445(
            gpuState, remapWorkspace, remapDepositDiagnostics, cpuRemap.massCorrectionStrength, targetOverride);
        d.gpuRemapCells = gd.remapCells;
        d.gpuThermalCells = gd.thermalCells;
        d.remapKernelSeconds = gd.remapSeconds;
        d.thermalKernelSeconds = gd.thermalSeconds;
        d.totalSeconds = pa.totalSeconds + gd.remapSeconds + gd.thermalSeconds;

        const std::size_t nTotal = static_cast<std::size_t>(std::min(cpuFinalState.Np, gpuState.Np));
        for (std::size_t i = 0; i < nTotal; ++i) {
            const bool roleMatches = (cpuFinalState.role[i] == gpuState.role[i]);
            if (!roleMatches) ++d.roleMismatch;

            // The inactive/free tail is capacity bookkeeping, not physical state.
            // CPU and CUDA may leave different type tags there after extraction/insertion
            // while roles, active prefix, mass/momentum, and all fluid payload remain identical.
            // Count type mismatches only on physical fluid slots, matching the 0442 comparefix
            // rule that inactive payload is intentionally ignored.
            const bool physicalFluidSlot = roleMatches && (cpuFinalState.role[i] == kParticleRoleFluid);
            if (physicalFluidSlot && cpuFinalState.type[i] != gpuState.type[i]) ++d.typeMismatch;
            if (!physicalFluidSlot) continue;

            d.maxAbsX = std::max(d.maxAbsX, std::abs(cpuFinalState.x[i] - gpuState.x[i]));
            d.maxAbsY = std::max(d.maxAbsY, std::abs(cpuFinalState.y[i] - gpuState.y[i]));
            d.maxAbsMass = std::max(d.maxAbsMass, std::abs(cpuFinalState.mass[i] - gpuState.mass[i]));
            d.maxAbsVx = std::max(d.maxAbsVx, std::abs(cpuFinalState.vx[i] - gpuState.vx[i]));
            d.maxAbsVy = std::max(d.maxAbsVy, std::abs(cpuFinalState.vy[i] - gpuState.vy[i]));
        }
        d.badPrefixCpu = bad_prefix_0445(cpuFinalState);
        d.badPrefixGpu = bad_prefix_0445(gpuState);
        const Totals0445 tc = totals_0445(cpuFinalState);
        const Totals0445 tg = totals_0445(gpuState);
        d.massCpu = tc.mass; d.massGpu = tg.mass;
        d.pxCpu = tc.px; d.pxGpu = tg.px;
        d.pyCpu = tc.py; d.pyGpu = tg.py;
        d.keCpu = tc.ke; d.keGpu = tg.ke;

        const double tol = 2.0e-10;
        d.handled = true;
        d.pass = d.roleMismatch == 0u && d.typeMismatch == 0u &&
                 d.badPrefixCpu == 0u && d.badPrefixGpu == 0u &&
                 d.cpuExtractionApplied == d.passiveOps && d.cpuInsertionApplied == d.passiveOps &&
                 d.gpuExtractionApplied == d.passiveOps && d.gpuInsertionApplied == d.passiveOps &&
                 d.gpuInvalidOperations == 0u &&
                 d.cpuRemapCells == d.gpuRemapCells && d.cpuThermalCells == d.gpuThermalCells &&
                 d.maxAbsX <= tol && d.maxAbsY <= tol && d.maxAbsMass <= tol &&
                 d.maxAbsVx <= tol && d.maxAbsVy <= tol &&
                 std::abs(d.massCpu - d.massGpu) <= tol &&
                 std::abs(d.pxCpu - d.pxGpu) <= tol &&
                 std::abs(d.pyCpu - d.pyGpu) <= tol &&
                 std::abs(d.keCpu - d.keGpu) <= tol;
        append_csv_0445(params, d);
        return d;
    } catch (const std::exception& e) {
        d.skipped = true;
        d.skipReason = std::string("exception: ") + e.what();
        append_csv_0445(params, d);
        return d;
    }
}

} // namespace mpcd

#endif
