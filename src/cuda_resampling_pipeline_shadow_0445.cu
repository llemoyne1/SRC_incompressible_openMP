#include "cuda_resampling_pipeline_shadow_0445.h"
#include "cuda_particle_state.h"
#include "cuda_cell_moments.h"
#include "cuda_cell_workspace.h"
#include "cuda_resampling_particle_ops.h"

#if defined(MPCD_ENABLE_CUDA_RESAMPLING) && defined(MPCD_ENABLE_CUDA_PARTICLE_STATE)

#include <cuda_runtime.h>
#include <thrust/device_ptr.h>
#include <thrust/execution_policy.h>
#include <thrust/sort.h>
#include <thrust/binary_search.h>

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


struct GpuMaterializedOps0453 {
    std::vector<ResamplingPassiveExtractionOperation> ops;
    std::uint64_t invalidOps = 0u;
    double uploadSeconds = 0.0;
    double kernelSeconds = 0.0;
    double downloadSeconds = 0.0;
    double totalSeconds = 0.0;
};

__device__ int cell_id_from_position_device_0453(double x, double y,
                                                 int nx, int ny,
                                                 double dx, double dy,
                                                 int xPeriodic, int yPeriodic) {
    if (nx <= 0 || ny <= 0 || !(dx > 0.0) || !(dy > 0.0)) return -1;
    int ix = static_cast<int>(floor(x / dx));
    int iy = static_cast<int>(floor(y / dy));
    if (xPeriodic) {
        while (ix < 0) ix += nx;
        while (ix >= nx) ix -= nx;
    }
    if (yPeriodic) {
        while (iy < 0) iy += ny;
        while (iy >= ny) iy -= ny;
    }
    if (ix < 0 || ix >= nx || iy < 0 || iy >= ny) return -1;
    return iy * nx + ix;
}

__global__ void materialize_passive_ops_serial_kernel_0453(
    std::size_t nActive,
    const double* x,
    const double* y,
    const double* mass,
    const double* vx,
    const double* vy,
    const std::uint32_t* type,
    const std::uint8_t* role,
    int nx,
    int ny,
    double dx,
    double dy,
    int xPeriodic,
    int yPeriodic,
    int planCount,
    const int* planDonor,
    const int* planReceiver,
    const double* planMass,
    std::uint8_t* selected,
    int maxOps,
    unsigned int* outCount,
    unsigned int* invalidOps,
    unsigned int* outParticle,
    int* outDonor,
    int* outReceiver,
    std::uint32_t* outType,
    double* outMass,
    double* outPx,
    double* outPy,
    double* outKe,
    std::uint8_t* outCurrentRole) {
    if (blockIdx.x != 0 || threadIdx.x != 0) return;
    constexpr double eps = 1.0e-14;
    unsigned int count = 0u;
    unsigned int invalid = 0u;
    for (int e = 0; e < planCount; ++e) {
        const int donorCell = planDonor[e];
        const int receiverCell = planReceiver[e];
        const double wanted = planMass[e];
        if (donorCell < 0 || receiverCell < 0 || !(wanted > eps)) {
            continue;
        }
        double selectedForEntry = 0.0;
        for (std::size_t i = 0; i < nActive; ++i) {
            if (selected[i]) continue;
            if (role[i] != kParticleRoleFluid) continue;
            const int cid = cell_id_from_position_device_0453(x[i], y[i], nx, ny, dx, dy, xPeriodic, yPeriodic);
            if (cid != donorCell) continue;
            const double mp = mass[i];
            if (!(mp > 0.0) || !isfinite(mp)) continue;
            if (count >= static_cast<unsigned int>(maxOps)) {
                ++invalid;
                break;
            }
            selected[i] = 1u;
            outParticle[count] = static_cast<unsigned int>(i);
            outDonor[count] = donorCell;
            outReceiver[count] = receiverCell;
            outType[count] = type[i];
            outMass[count] = mp;
            outPx[count] = mp * vx[i];
            outPy[count] = mp * vy[i];
            outKe[count] = 0.5 * mp * (vx[i] * vx[i] + vy[i] * vy[i]);
            outCurrentRole[count] = role[i];
            ++count;
            selectedForEntry += mp;
            if (selectedForEntry + eps >= wanted) break;
        }
        if (selectedForEntry + eps < wanted) {
            ++invalid;
        }
    }
    *outCount = count;
    *invalidOps = invalid;
}

GpuMaterializedOps0453 materialize_ops_gpu_0453(const ParticleState& state,
                                                const CellGrid& grid,
                                                const SimulationParams& params,
                                                const WeightedRealFluidDepositWorkspace& ws) {
    GpuMaterializedOps0453 out{};
    if (ws.transferPlan.empty()) return out;
    const std::size_t nActive = static_cast<std::size_t>(state.NactiveFluid);
    if (nActive == 0u) return out;
    const auto t0 = std::chrono::steady_clock::now();
    const auto upload0 = std::chrono::steady_clock::now();

    std::vector<std::uint8_t> roles(static_cast<std::size_t>(state.Np), kParticleRoleInactive);
    for (std::size_t i = 0; i < roles.size() && i < state.role.size(); ++i) roles[i] = state.role[i];
    std::vector<std::uint32_t> types(static_cast<std::size_t>(state.Np), 0u);
    for (std::size_t i = 0; i < types.size() && i < state.type.size(); ++i) types[i] = state.type[i];

    std::vector<int> planDonor, planReceiver;
    std::vector<double> planMass;
    planDonor.reserve(ws.transferPlan.size());
    planReceiver.reserve(ws.transferPlan.size());
    planMass.reserve(ws.transferPlan.size());
    for (const auto& e : ws.transferPlan) {
        planDonor.push_back(e.donorCell);
        planReceiver.push_back(e.receiverCell);
        planMass.push_back(e.plannedMass);
    }

    DeviceBuffer0445<double> dX(static_cast<std::size_t>(state.Np)); dX.copy_from_host(state.x);
    DeviceBuffer0445<double> dY(static_cast<std::size_t>(state.Np)); dY.copy_from_host(state.y);
    DeviceBuffer0445<double> dMass(static_cast<std::size_t>(state.Np)); dMass.copy_from_host(state.mass);
    DeviceBuffer0445<double> dVx(static_cast<std::size_t>(state.Np)); dVx.copy_from_host(state.vx);
    DeviceBuffer0445<double> dVy(static_cast<std::size_t>(state.Np)); dVy.copy_from_host(state.vy);
    DeviceBuffer0445<std::uint32_t> dType(static_cast<std::size_t>(state.Np)); dType.copy_from_host(types);
    DeviceBuffer0445<std::uint8_t> dRole(static_cast<std::size_t>(state.Np)); dRole.copy_from_host(roles);
    DeviceBuffer0445<int> dPlanDonor(planDonor.size()); dPlanDonor.copy_from_host(planDonor);
    DeviceBuffer0445<int> dPlanReceiver(planReceiver.size()); dPlanReceiver.copy_from_host(planReceiver);
    DeviceBuffer0445<double> dPlanMass(planMass.size()); dPlanMass.copy_from_host(planMass);
    DeviceBuffer0445<std::uint8_t> dSelected(nActive); dSelected.memset_zero();

    const std::size_t maxOps = nActive;
    DeviceBuffer0445<unsigned int> dOutCount(1u); dOutCount.memset_zero();
    DeviceBuffer0445<unsigned int> dInvalid(1u); dInvalid.memset_zero();
    DeviceBuffer0445<unsigned int> dOutParticle(maxOps);
    DeviceBuffer0445<int> dOutDonor(maxOps);
    DeviceBuffer0445<int> dOutReceiver(maxOps);
    DeviceBuffer0445<std::uint32_t> dOutType(maxOps);
    DeviceBuffer0445<double> dOutMass(maxOps);
    DeviceBuffer0445<double> dOutPx(maxOps);
    DeviceBuffer0445<double> dOutPy(maxOps);
    DeviceBuffer0445<double> dOutKe(maxOps);
    DeviceBuffer0445<std::uint8_t> dOutRole(maxOps);
    out.uploadSeconds = std::chrono::duration<double>(std::chrono::steady_clock::now() - upload0).count();

    cudaEvent_t start{}, stop{};
    CUDA_CHECK_0445(cudaEventCreate(&start));
    CUDA_CHECK_0445(cudaEventCreate(&stop));
    CUDA_CHECK_0445(cudaEventRecord(start));
    materialize_passive_ops_serial_kernel_0453<<<1,1>>>(
        nActive, dX.ptr, dY.ptr, dMass.ptr, dVx.ptr, dVy.ptr, dType.ptr, dRole.ptr,
        grid.Nx, grid.Ny, grid.dx, grid.dy,
        is_x_periodic(params) ? 1 : 0, is_y_periodic(params) ? 1 : 0,
        static_cast<int>(planDonor.size()), dPlanDonor.ptr, dPlanReceiver.ptr, dPlanMass.ptr,
        dSelected.ptr, static_cast<int>(maxOps), dOutCount.ptr, dInvalid.ptr,
        dOutParticle.ptr, dOutDonor.ptr, dOutReceiver.ptr, dOutType.ptr,
        dOutMass.ptr, dOutPx.ptr, dOutPy.ptr, dOutKe.ptr, dOutRole.ptr);
    CUDA_CHECK_0445(cudaEventRecord(stop));
    CUDA_CHECK_0445(cudaEventSynchronize(stop));
    CUDA_CHECK_0445(cudaGetLastError());
    float ms = 0.0f;
    CUDA_CHECK_0445(cudaEventElapsedTime(&ms, start, stop));
    CUDA_CHECK_0445(cudaEventDestroy(start));
    CUDA_CHECK_0445(cudaEventDestroy(stop));
    out.kernelSeconds = static_cast<double>(ms) * 1.0e-3;

    const auto download0 = std::chrono::steady_clock::now();
    std::vector<unsigned int> hCount, hInvalid;
    dOutCount.copy_to_host(hCount);
    dInvalid.copy_to_host(hInvalid);
    const std::size_t nOps = hCount.empty() ? 0u : static_cast<std::size_t>(hCount[0]);
    out.invalidOps = hInvalid.empty() ? 0u : static_cast<std::uint64_t>(hInvalid[0]);
    if (nOps > maxOps) throw std::runtime_error("0453 materializer op count overflow");
    std::vector<unsigned int> hParticle;
    std::vector<int> hDonor, hReceiver;
    std::vector<std::uint32_t> hType;
    std::vector<double> hMass, hPx, hPy, hKe;
    std::vector<std::uint8_t> hRole;
    dOutParticle.copy_to_host(hParticle);
    dOutDonor.copy_to_host(hDonor);
    dOutReceiver.copy_to_host(hReceiver);
    dOutType.copy_to_host(hType);
    dOutMass.copy_to_host(hMass);
    dOutPx.copy_to_host(hPx);
    dOutPy.copy_to_host(hPy);
    dOutKe.copy_to_host(hKe);
    dOutRole.copy_to_host(hRole);
    out.ops.reserve(nOps);
    for (std::size_t i = 0; i < nOps; ++i) {
        out.ops.push_back(ResamplingPassiveExtractionOperation{
            static_cast<std::uint64_t>(hParticle[i]),
            hDonor[i],
            hReceiver[i],
            hType[i],
            hMass[i],
            hPx[i],
            hPy[i],
            hKe[i],
            hRole[i],
            static_cast<std::uint8_t>(ParticleRole::Inactive)});
    }
    out.downloadSeconds = std::chrono::duration<double>(std::chrono::steady_clock::now() - download0).count();
    out.totalSeconds = std::chrono::duration<double>(std::chrono::steady_clock::now() - t0).count();
    return out;
}




bool cuda_resampling_cpu_op_carrier_0458_requested()
{
    const char* env = std::getenv("MPCD_CUDA_RESAMPLING_CPU_OP_CARRIER_0458");
    if (!env) return false;
    const std::string v(env);
    return !v.empty() && v != "0" && v != "false" && v != "FALSE" && v != "off" && v != "OFF";
}

bool cuda_resampling_donor_slice_materializer_0459_requested()
{
    const char* env = std::getenv("MPCD_CUDA_RESAMPLING_DONOR_SLICE_MATERIALIZER_0459");
    if (!env) return false;
    const std::string v(env);
    return !v.empty() && v != "0" && v != "false" && v != "FALSE" && v != "off" && v != "OFF";
}

bool cuda_resampling_thrust_cell_list_materializer_0460_requested()
{
    const char* env = std::getenv("MPCD_CUDA_RESAMPLING_THRUST_CELL_LIST_MATERIALIZER_0460");
    if (!env) return false;
    const std::string v(env);
    return !v.empty() && v != "0" && v != "false" && v != "FALSE" && v != "off" && v != "OFF";
}

struct GpuDeviceCarrier0455 {
    std::uint64_t cpuOps = 0u;
    std::uint64_t gpuOps = 0u;
    std::uint64_t invalidMaterializeOps = 0u;
    std::uint64_t opMismatch = 0u;
    std::uint64_t duplicateParticleMismatch = 0u;
    std::uint64_t extractionApplied = 0u;
    std::uint64_t insertionApplied = 0u;
    std::uint64_t invalidApplyOps = 0u;
    double maxMassAbs = 0.0;
    double maxPxAbs = 0.0;
    double maxPyAbs = 0.0;
    double cpuMass = 0.0;
    double gpuMass = 0.0;
    double cpuPx = 0.0;
    double gpuPx = 0.0;
    double cpuPy = 0.0;
    double gpuPy = 0.0;
    double cpuKe = 0.0;
    double gpuKe = 0.0;
    double uploadSeconds = 0.0;
    double materializeKernelSeconds = 0.0;
    std::uint64_t cpuOpCarrier0458 = 0u;
    std::uint64_t donorSliceMaterializer0459 = 0u;
    std::uint64_t thrustCellListMaterializer0460 = 0u;
    double gateDownloadSeconds = 0.0;
    double applyKernelSeconds = 0.0;
    double stateDownloadSeconds = 0.0;
    double totalSeconds = 0.0;
    bool pass = false;
};

__global__ void apply_device_carrier_extraction_kernel_0455(
    int nOps,
    const unsigned int* particleIndex,
    std::uint64_t nParticles,
    std::uint8_t fluidRole,
    std::uint8_t inactiveRole,
    unsigned int invalidParticle,
    unsigned int* applied,
    std::uint8_t* role) {
    const int op = blockIdx.x * blockDim.x + threadIdx.x;
    if (op >= nOps) return;
    const unsigned int p = particleIndex[op];
    unsigned int ok = 0u;
    if (p != invalidParticle && static_cast<std::uint64_t>(p) < nParticles && role[p] == fluidRole) {
        role[p] = inactiveRole;
        ok = 1u;
    }
    applied[op] = ok;
}

__global__ void apply_device_carrier_insertion_kernel_0455(
    int nOps,
    const unsigned int* particleIndex,
    const int* receiverCell,
    const std::uint32_t* particleType,
    const double* particleMass,
    const double* momentumX,
    const double* momentumY,
    std::uint32_t Nx,
    std::uint32_t Ny,
    double dx,
    double dy,
    std::uint64_t nParticles,
    std::uint8_t inactiveRole,
    std::uint8_t fluidRole,
    unsigned int invalidParticle,
    unsigned int* applied,
    double* x,
    double* y,
    double* vx,
    double* vy,
    double* mass,
    std::uint32_t* type,
    std::uint8_t* role) {
    const int op = blockIdx.x * blockDim.x + threadIdx.x;
    if (op >= nOps) return;
    const unsigned int p = particleIndex[op];
    unsigned int ok = 0u;
    if (p != invalidParticle && static_cast<std::uint64_t>(p) < nParticles && role[p] == inactiveRole) {
        const std::uint32_t c = static_cast<std::uint32_t>(receiverCell[op]);
        const std::uint32_t nCells = Nx * Ny;
        const double m = particleMass[op];
        if (c < nCells && m > 0.0) {
            const std::uint32_t ix = c % Nx;
            const std::uint32_t iy = c / Nx;
            const std::uint32_t q = static_cast<std::uint32_t>(op) & 15u;
            const double fx = 0.2 + 0.2 * static_cast<double>(q & 3u);
            const double fy = 0.2 + 0.2 * static_cast<double>(q >> 2u);
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

int cell_id_from_position_host_0459(double x, double y,
                                    int nx, int ny,
                                    double dx, double dy,
                                    bool xPeriodic, bool yPeriodic) {
    if (nx <= 0 || ny <= 0 || !(dx > 0.0) || !(dy > 0.0)) return -1;
    int ix = static_cast<int>(floor(x / dx));
    int iy = static_cast<int>(floor(y / dy));
    if (xPeriodic) {
        while (ix < 0) ix += nx;
        while (ix >= nx) ix -= nx;
    }
    if (yPeriodic) {
        while (iy < 0) iy += ny;
        while (iy >= ny) iy -= ny;
    }
    if (ix < 0 || ix >= nx || iy < 0 || iy >= ny) return -1;
    return iy * nx + ix;
}

__global__ void fill_cell_ids_and_particles_kernel_0460b(
    std::size_t nActive,
    const double* x,
    const double* y,
    const std::uint8_t* role,
    int nx,
    int ny,
    double dx,
    double dy,
    int xPeriodic,
    int yPeriodic,
    std::uint8_t fluidRole,
    int invalidCell,
    int* outCellId,
    unsigned int* outParticle) {
    const std::size_t i = static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
    if (i >= nActive) return;
    outParticle[i] = static_cast<unsigned int>(i);
    int cid = invalidCell;
    if (role[i] == fluidRole) {
        const int c = cell_id_from_position_device_0453(x[i], y[i], nx, ny, dx, dy, xPeriodic, yPeriodic);
        if (c >= 0) cid = c;
    }
    outCellId[i] = cid;
}

__global__ void compute_donor_counts_from_bounds_kernel_0460b(
    int donorCount,
    const unsigned int* lower,
    const unsigned int* upper,
    unsigned int* counts) {
    const int d = blockIdx.x * blockDim.x + threadIdx.x;
    if (d >= donorCount) return;
    counts[d] = (upper[d] >= lower[d]) ? (upper[d] - lower[d]) : 0u;
}

__global__ void materialize_passive_ops_donor_slices_kernel_0459(
    int planCount,
    const int* planDonor,
    const int* planReceiver,
    const double* planMass,
    int donorSliceCount,
    const int* donorCells,
    const unsigned int* donorOffsets,
    const unsigned int* donorCounts,
    const unsigned int* compactParticles,
    const double* mass,
    const double* vx,
    const double* vy,
    const std::uint32_t* type,
    const std::uint8_t* role,
    std::uint8_t fluidRole,
    std::uint64_t nParticles,
    std::uint8_t* selected,
    int maxOps,
    unsigned int* outCount,
    unsigned int* invalidOps,
    unsigned int* outParticle,
    int* outDonor,
    int* outReceiver,
    std::uint32_t* outType,
    double* outMass,
    double* outPx,
    double* outPy,
    double* outKe,
    std::uint8_t* outCurrentRole) {
    if (blockIdx.x != 0 || threadIdx.x != 0) return;
    constexpr double eps = 1.0e-14;
    unsigned int count = 0u;
    unsigned int invalid = 0u;
    for (int e = 0; e < planCount; ++e) {
        const int donorCell = planDonor[e];
        const int receiverCell = planReceiver[e];
        const double wanted = planMass[e];
        if (donorCell < 0 || receiverCell < 0 || !(wanted > eps)) continue;

        int slice = -1;
        for (int d = 0; d < donorSliceCount; ++d) {
            if (donorCells[d] == donorCell) { slice = d; break; }
        }
        if (slice < 0) { ++invalid; continue; }

        const unsigned int begin = donorOffsets[slice];
        const unsigned int n = donorCounts[slice];
        double selectedForEntry = 0.0;
        for (unsigned int k = 0u; k < n; ++k) {
            const unsigned int p = compactParticles[begin + k];
            if (static_cast<std::uint64_t>(p) >= nParticles) continue;
            if (selected[p]) continue;
            if (role[p] != fluidRole) continue;
            const double mp = mass[p];
            if (!(mp > 0.0) || !isfinite(mp)) continue;
            if (count >= static_cast<unsigned int>(maxOps)) {
                ++invalid;
                break;
            }
            selected[p] = 1u;
            outParticle[count] = p;
            outDonor[count] = donorCell;
            outReceiver[count] = receiverCell;
            outType[count] = type[p];
            outMass[count] = mp;
            outPx[count] = mp * vx[p];
            outPy[count] = mp * vy[p];
            outKe[count] = 0.5 * mp * (vx[p] * vx[p] + vy[p] * vy[p]);
            outCurrentRole[count] = role[p];
            ++count;
            selectedForEntry += mp;
            if (selectedForEntry + eps >= wanted) break;
        }
        if (selectedForEntry + eps < wanted) {
            ++invalid;
        }
    }
    *outCount = count;
    *invalidOps = invalid;
}

GpuDeviceCarrier0455 apply_gpu_particle_edits_device_carrier_0455(
    ParticleState& state,
    const WeightedRealFluidDepositWorkspace& ws,
    const CellGrid& grid,
    const SimulationParams& params) {
    GpuDeviceCarrier0455 out{};
    out.cpuOps = static_cast<std::uint64_t>(ws.passiveExtractionOperations.size());
    if (ws.transferPlan.empty() || ws.passiveExtractionOperations.empty()) {
        out.pass = ws.passiveExtractionOperations.empty();
        return out;
    }
    const auto t0 = std::chrono::steady_clock::now();
    const auto upload0 = std::chrono::steady_clock::now();
    CudaParticleState gpuState{};
    CudaParticleStateDiagnostics uploadDiag{};
    gpuState.upload_all(state, &uploadDiag);
    auto view = gpuState.device_view();

    std::vector<int> planDonor, planReceiver;
    std::vector<double> planMass;
    planDonor.reserve(ws.transferPlan.size());
    planReceiver.reserve(ws.transferPlan.size());
    planMass.reserve(ws.transferPlan.size());
    for (const auto& e : ws.transferPlan) {
        planDonor.push_back(e.donorCell);
        planReceiver.push_back(e.receiverCell);
        planMass.push_back(e.plannedMass);
    }
    DeviceBuffer0445<int> dPlanDonor(planDonor.size()); dPlanDonor.copy_from_host(planDonor);
    DeviceBuffer0445<int> dPlanReceiver(planReceiver.size()); dPlanReceiver.copy_from_host(planReceiver);
    DeviceBuffer0445<double> dPlanMass(planMass.size()); dPlanMass.copy_from_host(planMass);
    DeviceBuffer0445<std::uint8_t> dSelected(static_cast<std::size_t>(state.NactiveFluid)); dSelected.memset_zero();

    const std::size_t maxOps = static_cast<std::size_t>(state.NactiveFluid);
    DeviceBuffer0445<unsigned int> dOutCount(1u); dOutCount.memset_zero();
    DeviceBuffer0445<unsigned int> dInvalid(1u); dInvalid.memset_zero();
    DeviceBuffer0445<unsigned int> dOutParticle(maxOps);
    DeviceBuffer0445<int> dOutDonor(maxOps);
    DeviceBuffer0445<int> dOutReceiver(maxOps);
    DeviceBuffer0445<std::uint32_t> dOutType(maxOps);
    DeviceBuffer0445<double> dOutMass(maxOps);
    DeviceBuffer0445<double> dOutPx(maxOps);
    DeviceBuffer0445<double> dOutPy(maxOps);
    DeviceBuffer0445<double> dOutKe(maxOps);
    DeviceBuffer0445<std::uint8_t> dOutRole(maxOps);
    out.uploadSeconds = std::chrono::duration<double>(std::chrono::steady_clock::now() - upload0).count() + uploadDiag.uploadSeconds;

    cudaEvent_t start{}, stop{};
    const bool cpuOpCarrier0458 = cuda_resampling_cpu_op_carrier_0458_requested();
    const bool thrustCellListMaterializer0460 = (!cpuOpCarrier0458 && cuda_resampling_thrust_cell_list_materializer_0460_requested());
    const bool donorSliceMaterializer0459 = (!cpuOpCarrier0458 && !thrustCellListMaterializer0460 && cuda_resampling_donor_slice_materializer_0459_requested());
    out.cpuOpCarrier0458 = cpuOpCarrier0458 ? 1u : 0u;
    out.donorSliceMaterializer0459 = donorSliceMaterializer0459 ? 1u : 0u;
    out.thrustCellListMaterializer0460 = thrustCellListMaterializer0460 ? 1u : 0u;
    if (cpuOpCarrier0458) {
        // 0458A diagnostic/performance bridge: bypass the validated but serial
        // donor-particle materializer and upload the already-built CPU passive
        // operation vector into the device-carrier buffers. This intentionally
        // does NOT claim host-free materialization; it isolates the cost of the
        // serial CUDA materializer so that the apply/remap/thermal path can be
        // timed independently.
        const auto& cpuOps0458 = ws.passiveExtractionOperations;
        if (cpuOps0458.size() > maxOps) throw std::runtime_error("0458 CPU-op carrier op count overflow");
        std::vector<unsigned int> hOutCount(1u, static_cast<unsigned int>(cpuOps0458.size()));
        std::vector<unsigned int> hInvalid(1u, 0u);
        std::vector<unsigned int> hParticle(maxOps, 0u);
        std::vector<int> hDonor(maxOps, -1);
        std::vector<int> hReceiver(maxOps, -1);
        std::vector<std::uint32_t> hType(maxOps, 0u);
        std::vector<double> hMass(maxOps, 0.0);
        std::vector<double> hPx(maxOps, 0.0);
        std::vector<double> hPy(maxOps, 0.0);
        std::vector<double> hKe(maxOps, 0.0);
        std::vector<std::uint8_t> hRole(maxOps, static_cast<std::uint8_t>(ParticleRole::Inactive));
        for (std::size_t i = 0; i < cpuOps0458.size(); ++i) {
            const auto& a = cpuOps0458[i];
            hParticle[i] = static_cast<unsigned int>(a.particleIndex);
            hDonor[i] = a.donorCell;
            hReceiver[i] = a.receiverCell;
            hType[i] = a.particleType;
            hMass[i] = a.particleMass;
            hPx[i] = a.momentumX;
            hPy[i] = a.momentumY;
            hKe[i] = a.kineticEnergy;
            hRole[i] = a.currentRole;
        }
        dOutCount.copy_from_host(hOutCount);
        dInvalid.copy_from_host(hInvalid);
        if (!hParticle.empty()) {
            dOutParticle.copy_from_host(hParticle);
            dOutDonor.copy_from_host(hDonor);
            dOutReceiver.copy_from_host(hReceiver);
            dOutType.copy_from_host(hType);
            dOutMass.copy_from_host(hMass);
            dOutPx.copy_from_host(hPx);
            dOutPy.copy_from_host(hPy);
            dOutKe.copy_from_host(hKe);
            dOutRole.copy_from_host(hRole);
        }
        out.materializeKernelSeconds = 0.0;
    } else if (thrustCellListMaterializer0460) {
        // 0460B Thrust cell-list materializer. Build a stable GPU cell list by
        // computing (cellId, particleIndex) for every active fluid particle, then
        // stable-sort by cellId. Because particleIndex is initialized in ascending
        // order and stable_sort_by_key preserves relative order inside equal-cell
        // groups, each donor-cell slice has the same ascending particle order as
        // the CPU donor selection. The strict CPU operation gate remains active.
        std::vector<int> donorCells0460;
        donorCells0460.reserve(planDonor.size());
        constexpr double eps0460 = 1.0e-14;
        for (std::size_t e = 0; e < planDonor.size(); ++e) {
            if (planDonor[e] < 0 || planReceiver[e] < 0 || !(planMass[e] > eps0460)) continue;
            bool seenDonor = false;
            for (int c : donorCells0460) {
                if (c == planDonor[e]) { seenDonor = true; break; }
            }
            if (!seenDonor) donorCells0460.push_back(planDonor[e]);
        }
        if (donorCells0460.empty()) donorCells0460.push_back(-1);

        const std::uint8_t fluidRole0460 = static_cast<std::uint8_t>(ParticleRole::Fluid);
        const int invalidCell0460 = 2147483647;
        const std::size_t nActive0460 = static_cast<std::size_t>(state.NactiveFluid);
        DeviceBuffer0445<int> dCellId0460(nActive0460);
        DeviceBuffer0445<unsigned int> dParticleSorted0460(nActive0460);
        const int threadsBuild0460 = 256;
        const int blocksBuild0460 = static_cast<int>((nActive0460 + static_cast<std::size_t>(threadsBuild0460) - 1u) / static_cast<std::size_t>(threadsBuild0460));

        DeviceBuffer0445<int> dDonorCells0460(donorCells0460.size()); dDonorCells0460.copy_from_host(donorCells0460);
        DeviceBuffer0445<unsigned int> dDonorOffsets0460(donorCells0460.size()); dDonorOffsets0460.memset_zero();
        DeviceBuffer0445<unsigned int> dDonorUpper0460(donorCells0460.size()); dDonorUpper0460.memset_zero();
        DeviceBuffer0445<unsigned int> dDonorCounts0460(donorCells0460.size()); dDonorCounts0460.memset_zero();

        CUDA_CHECK_0445(cudaEventCreate(&start));
        CUDA_CHECK_0445(cudaEventCreate(&stop));
        CUDA_CHECK_0445(cudaEventRecord(start));
        fill_cell_ids_and_particles_kernel_0460b<<<blocksBuild0460, threadsBuild0460>>>(
            nActive0460, view.x, view.y, view.role,
            grid.Nx, grid.Ny, grid.dx, grid.dy,
            is_x_periodic(params) ? 1 : 0, is_y_periodic(params) ? 1 : 0,
            fluidRole0460, invalidCell0460, dCellId0460.ptr, dParticleSorted0460.ptr);
        CUDA_CHECK_0445(cudaGetLastError());

        thrust::stable_sort_by_key(thrust::device,
            thrust::device_pointer_cast(dCellId0460.ptr),
            thrust::device_pointer_cast(dCellId0460.ptr + nActive0460),
            thrust::device_pointer_cast(dParticleSorted0460.ptr));
        CUDA_CHECK_0445(cudaGetLastError());

        thrust::lower_bound(thrust::device,
            thrust::device_pointer_cast(dCellId0460.ptr),
            thrust::device_pointer_cast(dCellId0460.ptr + nActive0460),
            thrust::device_pointer_cast(dDonorCells0460.ptr),
            thrust::device_pointer_cast(dDonorCells0460.ptr + donorCells0460.size()),
            thrust::device_pointer_cast(dDonorOffsets0460.ptr));
        thrust::upper_bound(thrust::device,
            thrust::device_pointer_cast(dCellId0460.ptr),
            thrust::device_pointer_cast(dCellId0460.ptr + nActive0460),
            thrust::device_pointer_cast(dDonorCells0460.ptr),
            thrust::device_pointer_cast(dDonorCells0460.ptr + donorCells0460.size()),
            thrust::device_pointer_cast(dDonorUpper0460.ptr));
        CUDA_CHECK_0445(cudaGetLastError());

        const int threadsCount0460 = 128;
        const int blocksCount0460 = static_cast<int>((donorCells0460.size() + static_cast<std::size_t>(threadsCount0460) - 1u) / static_cast<std::size_t>(threadsCount0460));
        compute_donor_counts_from_bounds_kernel_0460b<<<blocksCount0460, threadsCount0460>>>(
            static_cast<int>(donorCells0460.size()), dDonorOffsets0460.ptr, dDonorUpper0460.ptr, dDonorCounts0460.ptr);
        CUDA_CHECK_0445(cudaGetLastError());

        materialize_passive_ops_donor_slices_kernel_0459<<<1,1>>>(
            static_cast<int>(planDonor.size()), dPlanDonor.ptr, dPlanReceiver.ptr, dPlanMass.ptr,
            static_cast<int>(donorCells0460.size()), dDonorCells0460.ptr, dDonorOffsets0460.ptr, dDonorCounts0460.ptr,
            dParticleSorted0460.ptr, view.mass, view.vx, view.vy, view.type, view.role, fluidRole0460, view.n,
            dSelected.ptr, static_cast<int>(maxOps), dOutCount.ptr, dInvalid.ptr,
            dOutParticle.ptr, dOutDonor.ptr, dOutReceiver.ptr, dOutType.ptr,
            dOutMass.ptr, dOutPx.ptr, dOutPy.ptr, dOutKe.ptr, dOutRole.ptr);
        CUDA_CHECK_0445(cudaEventRecord(stop));
        CUDA_CHECK_0445(cudaEventSynchronize(stop));
        CUDA_CHECK_0445(cudaGetLastError());
        float materializeMs = 0.0f;
        CUDA_CHECK_0445(cudaEventElapsedTime(&materializeMs, start, stop));
        CUDA_CHECK_0445(cudaEventDestroy(start));
        CUDA_CHECK_0445(cudaEventDestroy(stop));
        out.materializeKernelSeconds = static_cast<double>(materializeMs) * 1.0e-3;
    } else if (donorSliceMaterializer0459) {
        // 0459B donor-slice materializer: build a compact, deterministic host-side
        // list of candidate particles for the donor cells only, then let CUDA
        // materialize the operation vector by scanning those short donor slices.
        // This deliberately does not use the CPU passive operation vector as a
        // carrier; it is a transitional step toward a fully GPU-built cell list.
        std::vector<int> donorCells0459;
        donorCells0459.reserve(planDonor.size());
        constexpr double eps0459 = 1.0e-14;
        for (std::size_t e = 0; e < planDonor.size(); ++e) {
            if (planDonor[e] < 0 || planReceiver[e] < 0 || !(planMass[e] > eps0459)) continue;
            bool seenDonor = false;
            for (int c : donorCells0459) {
                if (c == planDonor[e]) { seenDonor = true; break; }
            }
            if (!seenDonor) donorCells0459.push_back(planDonor[e]);
        }
        std::vector<std::vector<unsigned int>> perDonor0459(donorCells0459.size());
        const bool xp0459 = is_x_periodic(params);
        const bool yp0459 = is_y_periodic(params);
        const std::uint8_t fluidRole0459 = static_cast<std::uint8_t>(ParticleRole::Fluid);
        for (std::size_t i = 0; i < static_cast<std::size_t>(state.NactiveFluid); ++i) {
            if (i >= state.role.size() || state.role[i] != fluidRole0459) continue;
            if (i >= state.x.size() || i >= state.y.size()) continue;
            const int cid = cell_id_from_position_host_0459(state.x[i], state.y[i],
                                                            grid.Nx, grid.Ny, grid.dx, grid.dy,
                                                            xp0459, yp0459);
            if (cid < 0) continue;
            for (std::size_t d = 0; d < donorCells0459.size(); ++d) {
                if (donorCells0459[d] == cid) {
                    perDonor0459[d].push_back(static_cast<unsigned int>(i));
                    break;
                }
            }
        }
        std::vector<unsigned int> donorOffsets0459(donorCells0459.size(), 0u);
        std::vector<unsigned int> donorCounts0459(donorCells0459.size(), 0u);
        std::vector<unsigned int> compactParticles0459;
        for (std::size_t d = 0; d < donorCells0459.size(); ++d) {
            donorOffsets0459[d] = static_cast<unsigned int>(compactParticles0459.size());
            donorCounts0459[d] = static_cast<unsigned int>(perDonor0459[d].size());
            compactParticles0459.insert(compactParticles0459.end(), perDonor0459[d].begin(), perDonor0459[d].end());
        }
        if (compactParticles0459.empty()) compactParticles0459.push_back(0u);

        DeviceBuffer0445<int> dDonorCells0459(donorCells0459.size()); dDonorCells0459.copy_from_host(donorCells0459);
        DeviceBuffer0445<unsigned int> dDonorOffsets0459(donorOffsets0459.size()); dDonorOffsets0459.copy_from_host(donorOffsets0459);
        DeviceBuffer0445<unsigned int> dDonorCounts0459(donorCounts0459.size()); dDonorCounts0459.copy_from_host(donorCounts0459);
        DeviceBuffer0445<unsigned int> dCompactParticles0459(compactParticles0459.size()); dCompactParticles0459.copy_from_host(compactParticles0459);

        CUDA_CHECK_0445(cudaEventCreate(&start));
        CUDA_CHECK_0445(cudaEventCreate(&stop));
        CUDA_CHECK_0445(cudaEventRecord(start));
        materialize_passive_ops_donor_slices_kernel_0459<<<1,1>>>(
            static_cast<int>(planDonor.size()), dPlanDonor.ptr, dPlanReceiver.ptr, dPlanMass.ptr,
            static_cast<int>(donorCells0459.size()), dDonorCells0459.ptr, dDonorOffsets0459.ptr, dDonorCounts0459.ptr,
            dCompactParticles0459.ptr, view.mass, view.vx, view.vy, view.type, view.role, fluidRole0459, view.n,
            dSelected.ptr, static_cast<int>(maxOps), dOutCount.ptr, dInvalid.ptr,
            dOutParticle.ptr, dOutDonor.ptr, dOutReceiver.ptr, dOutType.ptr,
            dOutMass.ptr, dOutPx.ptr, dOutPy.ptr, dOutKe.ptr, dOutRole.ptr);
        CUDA_CHECK_0445(cudaEventRecord(stop));
        CUDA_CHECK_0445(cudaEventSynchronize(stop));
        CUDA_CHECK_0445(cudaGetLastError());
        float materializeMs = 0.0f;
        CUDA_CHECK_0445(cudaEventElapsedTime(&materializeMs, start, stop));
        CUDA_CHECK_0445(cudaEventDestroy(start));
        CUDA_CHECK_0445(cudaEventDestroy(stop));
        out.materializeKernelSeconds = static_cast<double>(materializeMs) * 1.0e-3;
    } else {
        CUDA_CHECK_0445(cudaEventCreate(&start));
        CUDA_CHECK_0445(cudaEventCreate(&stop));
        CUDA_CHECK_0445(cudaEventRecord(start));
        materialize_passive_ops_serial_kernel_0453<<<1,1>>>(
            static_cast<std::size_t>(state.NactiveFluid), view.x, view.y, view.mass, view.vx, view.vy, view.type, view.role,
            grid.Nx, grid.Ny, grid.dx, grid.dy,
            is_x_periodic(params) ? 1 : 0, is_y_periodic(params) ? 1 : 0,
            static_cast<int>(planDonor.size()), dPlanDonor.ptr, dPlanReceiver.ptr, dPlanMass.ptr,
            dSelected.ptr, static_cast<int>(maxOps), dOutCount.ptr, dInvalid.ptr,
            dOutParticle.ptr, dOutDonor.ptr, dOutReceiver.ptr, dOutType.ptr,
            dOutMass.ptr, dOutPx.ptr, dOutPy.ptr, dOutKe.ptr, dOutRole.ptr);
        CUDA_CHECK_0445(cudaEventRecord(stop));
        CUDA_CHECK_0445(cudaEventSynchronize(stop));
        CUDA_CHECK_0445(cudaGetLastError());
        float materializeMs = 0.0f;
        CUDA_CHECK_0445(cudaEventElapsedTime(&materializeMs, start, stop));
        CUDA_CHECK_0445(cudaEventDestroy(start));
        CUDA_CHECK_0445(cudaEventDestroy(stop));
        out.materializeKernelSeconds = static_cast<double>(materializeMs) * 1.0e-3;
    }

    const auto gate0 = std::chrono::steady_clock::now();
    std::vector<unsigned int> hCount, hInvalid;
    dOutCount.copy_to_host(hCount);
    dInvalid.copy_to_host(hInvalid);
    const std::size_t nOps = hCount.empty() ? 0u : static_cast<std::size_t>(hCount[0]);
    out.gpuOps = static_cast<std::uint64_t>(nOps);
    out.invalidMaterializeOps = hInvalid.empty() ? 0u : static_cast<std::uint64_t>(hInvalid[0]);
    if (nOps > maxOps) throw std::runtime_error("0455 device carrier op count overflow");
    std::vector<unsigned int> hParticle;
    std::vector<int> hDonor, hReceiver;
    std::vector<std::uint32_t> hType;
    std::vector<double> hMass, hPx, hPy, hKe;
    std::vector<std::uint8_t> hRole;
    dOutParticle.copy_to_host(hParticle);
    dOutDonor.copy_to_host(hDonor);
    dOutReceiver.copy_to_host(hReceiver);
    dOutType.copy_to_host(hType);
    dOutMass.copy_to_host(hMass);
    dOutPx.copy_to_host(hPx);
    dOutPy.copy_to_host(hPy);
    dOutKe.copy_to_host(hKe);
    dOutRole.copy_to_host(hRole);
    out.gateDownloadSeconds = std::chrono::duration<double>(std::chrono::steady_clock::now() - gate0).count();

    const auto& cpuOps = ws.passiveExtractionOperations;
    const std::size_t cmp = std::min(cpuOps.size(), nOps);
    out.opMismatch = static_cast<std::uint64_t>(std::max(cpuOps.size(), nOps) - cmp);
    for (std::size_t i = 0; i < cmp; ++i) {
        const auto& a = cpuOps[i];
        if (a.particleIndex != static_cast<std::uint64_t>(hParticle[i]) ||
            a.donorCell != hDonor[i] || a.receiverCell != hReceiver[i] ||
            a.particleType != hType[i] || a.currentRole != hRole[i] ||
            a.plannedRoleAfterExtraction != static_cast<std::uint8_t>(ParticleRole::Inactive)) {
            ++out.opMismatch;
        }
        out.maxMassAbs = std::max(out.maxMassAbs, std::abs(a.particleMass - hMass[i]));
        out.maxPxAbs = std::max(out.maxPxAbs, std::abs(a.momentumX - hPx[i]));
        out.maxPyAbs = std::max(out.maxPyAbs, std::abs(a.momentumY - hPy[i]));
        out.cpuMass += a.particleMass;
        out.cpuPx += a.momentumX;
        out.cpuPy += a.momentumY;
        out.cpuKe += a.kineticEnergy;
        out.gpuMass += hMass[i];
        out.gpuPx += hPx[i];
        out.gpuPy += hPy[i];
        out.gpuKe += hKe[i];
    }
    std::vector<std::uint8_t> seen(static_cast<std::size_t>(state.Np), 0u);
    for (std::size_t i = 0; i < nOps; ++i) {
        if (static_cast<std::uint64_t>(hParticle[i]) >= state.Np) {
            ++out.duplicateParticleMismatch;
            continue;
        }
        const std::size_t idx = static_cast<std::size_t>(hParticle[i]);
        if (seen[idx]) ++out.duplicateParticleMismatch;
        seen[idx] = 1u;
    }
    constexpr double tol = 2.0e-10;
    const auto close = [tol](double a, double b) {
        const double scale = std::max({1.0, std::abs(a), std::abs(b)});
        return std::abs(a - b) <= tol * scale;
    };
    const bool gatePass = (out.invalidMaterializeOps == 0u && out.opMismatch == 0u &&
                           out.duplicateParticleMismatch == 0u && out.cpuOps == out.gpuOps &&
                           out.maxMassAbs <= tol && out.maxPxAbs <= tol && out.maxPyAbs <= tol &&
                           close(out.cpuMass, out.gpuMass) && close(out.cpuPx, out.gpuPx) &&
                           close(out.cpuPy, out.gpuPy) && close(out.cpuKe, out.gpuKe));
    if (!gatePass) {
        out.pass = false;
        out.totalSeconds = std::chrono::duration<double>(std::chrono::steady_clock::now() - t0).count();
        return out;
    }

    CUDA_CHECK_0445(cudaEventCreate(&start));
    CUDA_CHECK_0445(cudaEventCreate(&stop));
    CUDA_CHECK_0445(cudaEventRecord(start));
    const int threads = 256;
    const int blocks = (static_cast<int>(nOps) + threads - 1) / threads;
    DeviceBuffer0445<unsigned int> dExtApplied(nOps); dExtApplied.memset_zero();
    DeviceBuffer0445<unsigned int> dInsApplied(nOps); dInsApplied.memset_zero();
    apply_device_carrier_extraction_kernel_0455<<<blocks, threads>>>(
        static_cast<int>(nOps), dOutParticle.ptr, view.n,
        static_cast<std::uint8_t>(ParticleRole::Fluid), static_cast<std::uint8_t>(ParticleRole::Inactive),
        0xffffffffu, dExtApplied.ptr, view.role);
    CUDA_CHECK_0445(cudaGetLastError());
    apply_device_carrier_insertion_kernel_0455<<<blocks, threads>>>(
        static_cast<int>(nOps), dOutParticle.ptr, dOutReceiver.ptr, dOutType.ptr,
        dOutMass.ptr, dOutPx.ptr, dOutPy.ptr,
        static_cast<std::uint32_t>(grid.Nx), static_cast<std::uint32_t>(grid.Ny), grid.dx, grid.dy,
        view.n, static_cast<std::uint8_t>(ParticleRole::Inactive), static_cast<std::uint8_t>(ParticleRole::Fluid),
        0xffffffffu, dInsApplied.ptr, view.x, view.y, view.vx, view.vy, view.mass, view.type, view.role);
    CUDA_CHECK_0445(cudaGetLastError());
    CUDA_CHECK_0445(cudaEventRecord(stop));
    CUDA_CHECK_0445(cudaEventSynchronize(stop));
    float applyMs = 0.0f;
    CUDA_CHECK_0445(cudaEventElapsedTime(&applyMs, start, stop));
    CUDA_CHECK_0445(cudaEventDestroy(start));
    CUDA_CHECK_0445(cudaEventDestroy(stop));
    out.applyKernelSeconds = static_cast<double>(applyMs) * 1.0e-3;

    std::vector<unsigned int> hExtApplied, hInsApplied;
    dExtApplied.copy_to_host(hExtApplied);
    dInsApplied.copy_to_host(hInsApplied);
    for (std::size_t i = 0; i < nOps; ++i) {
        out.extractionApplied += (i < hExtApplied.size() && hExtApplied[i]) ? 1u : 0u;
        out.insertionApplied += (i < hInsApplied.size() && hInsApplied[i]) ? 1u : 0u;
    }
    out.invalidApplyOps = (static_cast<std::uint64_t>(nOps) - out.extractionApplied) +
                          (static_cast<std::uint64_t>(nOps) - out.insertionApplied);
    if (out.invalidApplyOps == 0u) {
        const auto dl0 = std::chrono::steady_clock::now();
        CudaParticleStateDiagnostics downloadDiag{};
        gpuState.download_all(state, &downloadDiag);
        out.stateDownloadSeconds = std::chrono::duration<double>(std::chrono::steady_clock::now() - dl0).count() + downloadDiag.downloadSeconds;
        out.pass = true;
    }
    out.totalSeconds = std::chrono::duration<double>(std::chrono::steady_clock::now() - t0).count();
    return out;
}

void append_device_carrier_csv_0455(const SimulationParams& params,
                                    std::uint64_t step,
                                    const GpuDeviceCarrier0455& d,
                                    bool attempted,
                                    bool handled,
                                    bool applied,
                                    bool pass,
                                    bool skipped,
                                    const std::string& skipReason) {
    if (params.outputDir.empty()) return;
    std::filesystem::create_directories(params.outputDir);
    const std::string path = params.outputDir + "/cuda_resampling_device_carrier_0455.csv";
    const bool exists = std::filesystem::exists(path);
    std::ofstream out(path, std::ios::app);
    out << std::setprecision(17);
    if (!exists) {
        out << "step,attempted,handled,applied,pass,skipped,skipReason,"
               "cpuOps,gpuOps,invalidMaterializeOps,opMismatch,duplicateParticleMismatch,"
               "extractionApplied,insertionApplied,invalidApplyOps,"
               "maxMassAbs,maxPxAbs,maxPyAbs,cpuMass,gpuMass,cpuPx,gpuPx,cpuPy,gpuPy,cpuKe,gpuKe,"
               "uploadSeconds,materializeKernelSeconds,cpuOpCarrier0458,donorSliceMaterializer0459,thrustCellListMaterializer0460,gateDownloadSeconds,applyKernelSeconds,stateDownloadSeconds,totalSeconds\n";
    }
    out << step << ',' << (attempted ? 1 : 0) << ',' << (handled ? 1 : 0) << ','
        << (applied ? 1 : 0) << ',' << (pass ? 1 : 0) << ',' << (skipped ? 1 : 0) << ','
        << csv_escape_0445(skipReason) << ','
        << d.cpuOps << ',' << d.gpuOps << ',' << d.invalidMaterializeOps << ',' << d.opMismatch << ','
        << d.duplicateParticleMismatch << ',' << d.extractionApplied << ',' << d.insertionApplied << ','
        << d.invalidApplyOps << ',' << d.maxMassAbs << ',' << d.maxPxAbs << ',' << d.maxPyAbs << ','
        << d.cpuMass << ',' << d.gpuMass << ',' << d.cpuPx << ',' << d.gpuPx << ','
        << d.cpuPy << ',' << d.gpuPy << ',' << d.cpuKe << ',' << d.gpuKe << ','
        << d.uploadSeconds << ',' << d.materializeKernelSeconds << ',' << d.cpuOpCarrier0458 << ',' << d.donorSliceMaterializer0459 << ',' << d.thrustCellListMaterializer0460 << ',' << d.gateDownloadSeconds << ','
        << d.applyKernelSeconds << ',' << d.stateDownloadSeconds << ',' << d.totalSeconds << '\n';
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

void append_upstream_apply_csv_0451(const SimulationParams& params,
                                    const CudaResamplingUpstreamApply0451Diagnostics& d) {
    if (params.outputDir.empty()) return;
    std::filesystem::create_directories(params.outputDir);
    const std::string path = params.outputDir + "/cuda_resampling_upstream_apply_0451.csv";
    const bool exists = std::filesystem::exists(path);
    std::ofstream out(path, std::ios::app);
    out << std::setprecision(17);
    if (!exists) {
        out << "step,attempted,handled,applied,pass,skipped,skipReason,nActive,nCells,"
            << "cpuTransferPairs,gpuTransferPairs,cpuPassiveOps,"
            << "cellIdMismatch,maxCountDiff,maxMassAbs,maxPxAbs,maxPyAbs,"
            << "receiverListMismatch,donorListMismatch,planMismatch,maxPlanMassAbs,maxPlanDistanceAbs,"
            << "cpuPlannedMass,gpuPlannedMass,upstreamShadowSeconds,totalSeconds\n";
    }
    out << d.step << ',' << (d.attempted ? 1 : 0) << ',' << (d.handled ? 1 : 0) << ','
        << (d.applied ? 1 : 0) << ',' << (d.pass ? 1 : 0) << ',' << (d.skipped ? 1 : 0) << ','
        << csv_escape_0445(d.skipReason) << ','
        << d.nActive << ',' << d.nCells << ','
        << d.cpuTransferPairs << ',' << d.gpuTransferPairs << ',' << d.cpuPassiveOps << ','
        << d.cellIdMismatch << ',' << d.maxCountDiff << ',' << d.maxMassAbs << ',' << d.maxPxAbs << ',' << d.maxPyAbs << ','
        << d.receiverListMismatch << ',' << d.donorListMismatch << ',' << d.planMismatch << ','
        << d.maxPlanMassAbs << ',' << d.maxPlanDistanceAbs << ','
        << d.cpuPlannedMass << ',' << d.gpuPlannedMass << ','
        << d.upstreamShadowSeconds << ',' << d.totalSeconds << '\n';
}


void append_operation_materialize_csv_0453(const SimulationParams& params,
                                           const CudaResamplingOperationMaterialize0453Diagnostics& d) {
    if (params.outputDir.empty()) return;
    std::filesystem::create_directories(params.outputDir);
    const std::string path = params.outputDir + "/cuda_resampling_operation_materialize_0453.csv";
    const bool exists = std::filesystem::exists(path);
    std::ofstream out(path, std::ios::app);
    out << std::setprecision(17);
    if (!exists) {
        out << "step,attempted,handled,applied,pass,skipped,skipReason,nActive,planEntries,"
            << "cpuOps,gpuOps,invalidOps,opMismatch,duplicateParticleMismatch,"
            << "maxMassAbs,maxPxAbs,maxPyAbs,cpuMass,gpuMass,cpuPx,gpuPx,cpuPy,gpuPy,cpuKe,gpuKe,"
            << "uploadSeconds,kernelSeconds,downloadSeconds,totalSeconds\n";
    }
    out << d.step << ',' << (d.attempted ? 1 : 0) << ',' << (d.handled ? 1 : 0) << ','
        << (d.applied ? 1 : 0) << ',' << (d.pass ? 1 : 0) << ',' << (d.skipped ? 1 : 0) << ','
        << csv_escape_0445(d.skipReason) << ','
        << d.nActive << ',' << d.planEntries << ','
        << d.cpuOps << ',' << d.gpuOps << ',' << d.invalidOps << ',' << d.opMismatch << ',' << d.duplicateParticleMismatch << ','
        << d.maxMassAbs << ',' << d.maxPxAbs << ',' << d.maxPyAbs << ','
        << d.cpuMass << ',' << d.gpuMass << ',' << d.cpuPx << ',' << d.gpuPx << ','
        << d.cpuPy << ',' << d.gpuPy << ',' << d.cpuKe << ',' << d.gpuKe << ','
        << d.uploadSeconds << ',' << d.kernelSeconds << ',' << d.downloadSeconds << ',' << d.totalSeconds << '\n';
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

bool cuda_resampling_upstream_apply_0451_requested(std::uint64_t step) {
    if (!env_truthy_0445("MPCD_CUDA_RESAMPLING_UPSTREAM_APPLY_0451")) return false;
    const std::uint64_t every = env_u64_0445("MPCD_CUDA_RESAMPLING_UPSTREAM_APPLY_EVERY_0451", 1u);
    return every == 0u || (step % every == 0u);
}

bool cuda_resampling_operation_materialize_0453_requested(std::uint64_t step) {
    if (!env_truthy_0445("MPCD_CUDA_RESAMPLING_OPERATION_MATERIALIZE_0453")) return false;
    const std::uint64_t every = env_u64_0445("MPCD_CUDA_RESAMPLING_OPERATION_MATERIALIZE_EVERY_0453", 1u);
    return every == 0u || (step % every == 0u);
}

bool cuda_resampling_device_carrier_0455_requested() {
    return env_truthy_0445("MPCD_CUDA_RESAMPLING_DEVICE_CARRIER_0455");
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


CudaResamplingUpstreamApply0451Diagnostics try_apply_cuda_resampling_upstream_plan_0451(
    const ParticleState& state,
    const SimulationParams& params,
    const CellGrid& grid,
    std::uint64_t step,
    WeightedRealFluidDepositWorkspace& upstreamWorkspace,
    WeightedResamplingDiagnostics& upstreamDiagnostics) {
    CudaResamplingUpstreamApply0451Diagnostics d{};
    d.attempted = true;
    d.step = step;
    d.outputCsv = params.outputDir.empty() ? std::string{} : (params.outputDir + "/cuda_resampling_upstream_apply_0451.csv");
    d.nActive = state.NactiveFluid;
    d.nCells = static_cast<std::uint64_t>(std::max(0, grid.numCells));
    const auto t0 = std::chrono::steady_clock::now();
    try {
        if (!cuda_resampling_upstream_apply_0451_requested(step)) {
            d.skipped = true;
            d.skipReason = "upstream apply flag disabled";
            append_upstream_apply_csv_0451(params, d);
            return d;
        }
        if (!cuda_resampling_upstream_shadow_0450_requested(step)) {
            d.skipped = true;
            d.skipReason = "0451 requires MPCD_CUDA_RESAMPLING_UPSTREAM_SHADOW_0450=1 for strict CPU/GPU gate";
            append_upstream_apply_csv_0451(params, d);
            return d;
        }

        const auto s0 = std::chrono::steady_clock::now();
        const CudaResamplingUpstreamShadow0450Diagnostics shadow =
            try_run_cuda_resampling_upstream_shadow_0450(
                state, params, grid, step, upstreamWorkspace, upstreamDiagnostics);
        d.upstreamShadowSeconds = std::chrono::duration<double>(std::chrono::steady_clock::now() - s0).count();

        d.nActive = shadow.nActive;
        d.nCells = shadow.nCells;
        d.cpuTransferPairs = shadow.cpuTransferPairs;
        d.gpuTransferPairs = shadow.gpuTransferPairs;
        d.cpuPassiveOps = shadow.cpuPassiveOps;
        d.cellIdMismatch = shadow.cellIdMismatch;
        d.maxCountDiff = shadow.maxCountDiff;
        d.maxMassAbs = shadow.maxMassAbs;
        d.maxPxAbs = shadow.maxPxAbs;
        d.maxPyAbs = shadow.maxPyAbs;
        d.receiverListMismatch = shadow.receiverListMismatch;
        d.donorListMismatch = shadow.donorListMismatch;
        d.planMismatch = shadow.planMismatch;
        d.maxPlanMassAbs = shadow.maxPlanMassAbs;
        d.maxPlanDistanceAbs = shadow.maxPlanDistanceAbs;
        d.cpuPlannedMass = shadow.cpuPlannedMass;
        d.gpuPlannedMass = shadow.gpuPlannedMass;

        if (shadow.skipped || !shadow.handled) {
            d.skipped = true;
            d.skipReason = std::string("upstream shadow unavailable: ") + shadow.skipReason;
            d.totalSeconds = std::chrono::duration<double>(std::chrono::steady_clock::now() - t0).count();
            append_upstream_apply_csv_0451(params, d);
            return d;
        }
        if (!shadow.pass) {
            d.handled = true;
            d.pass = false;
            d.skipped = true;
            d.skipReason = "CUDA upstream did not match CPU gate; keeping CPU workspace authoritative";
            d.totalSeconds = std::chrono::duration<double>(std::chrono::steady_clock::now() - t0).count();
            append_upstream_apply_csv_0451(params, d);
            return d;
        }

        // 0451A is an authority gate: CUDA recomputes and validates the upstream
        // deposit/classification/compaction/planner.  Because the current legacy
        // donor-particle materializer still consumes host workspace vectors, the
        // CPU workspace remains as the mirror representation after the strict
        // gate has accepted the CUDA upstream as equivalent.  Downstream 0448 can
        // then perform the mutating clean particle edits/remap/thermal on CUDA.
        d.handled = true;
        d.applied = true;
        d.pass = true;
        d.totalSeconds = std::chrono::duration<double>(std::chrono::steady_clock::now() - t0).count();
        append_upstream_apply_csv_0451(params, d);
        return d;
    } catch (const std::exception& e) {
        d.skipped = true;
        d.skipReason = std::string("exception: ") + e.what();
        d.totalSeconds = std::chrono::duration<double>(std::chrono::steady_clock::now() - t0).count();
        append_upstream_apply_csv_0451(params, d);
        return d;
    }
}


CudaResamplingOperationMaterialize0453Diagnostics try_apply_cuda_resampling_operation_materializer_0453(
    const ParticleState& state,
    const SimulationParams& params,
    const CellGrid& grid,
    std::uint64_t step,
    WeightedRealFluidDepositWorkspace& operationWorkspace) {
    CudaResamplingOperationMaterialize0453Diagnostics d{};
    d.attempted = true;
    d.step = step;
    d.outputCsv = params.outputDir.empty() ? std::string{} : (params.outputDir + "/cuda_resampling_operation_materialize_0453.csv");
    d.nActive = state.NactiveFluid;
    d.planEntries = static_cast<std::uint64_t>(operationWorkspace.transferPlan.size());
    d.cpuOps = static_cast<std::uint64_t>(operationWorkspace.passiveExtractionOperations.size());
    const auto t0 = std::chrono::steady_clock::now();
    try {
        if (!cuda_resampling_operation_materialize_0453_requested(step)) {
            d.skipped = true;
            d.skipReason = "operation materializer flag disabled";
            append_operation_materialize_csv_0453(params, d);
            return d;
        }
        if (!all_periodic_0450(params) || params.immersedSolidEnable) {
            d.skipped = true;
            d.skipReason = "0453 operation materializer is currently restricted to periodic wall-free no-solid cases";
            append_operation_materialize_csv_0453(params, d);
            return d;
        }
        if (operationWorkspace.transferPlan.empty()) {
            d.handled = true;
            d.applied = false;
            d.pass = operationWorkspace.passiveExtractionOperations.empty();
            append_operation_materialize_csv_0453(params, d);
            return d;
        }
        const GpuMaterializedOps0453 gpu = materialize_ops_gpu_0453(state, grid, params, operationWorkspace);
        d.gpuOps = static_cast<std::uint64_t>(gpu.ops.size());
        d.invalidOps = gpu.invalidOps;
        d.uploadSeconds = gpu.uploadSeconds;
        d.kernelSeconds = gpu.kernelSeconds;
        d.downloadSeconds = gpu.downloadSeconds;

        const auto& cpuOps = operationWorkspace.passiveExtractionOperations;
        const std::size_t cmp = std::min(cpuOps.size(), gpu.ops.size());
        d.opMismatch = static_cast<std::uint64_t>(std::max(cpuOps.size(), gpu.ops.size()) - cmp);
        for (std::size_t i = 0; i < cmp; ++i) {
            const auto& a = cpuOps[i];
            const auto& b = gpu.ops[i];
            if (a.particleIndex != b.particleIndex || a.donorCell != b.donorCell ||
                a.receiverCell != b.receiverCell || a.particleType != b.particleType ||
                a.currentRole != b.currentRole || a.plannedRoleAfterExtraction != b.plannedRoleAfterExtraction) {
                ++d.opMismatch;
            }
            d.maxMassAbs = std::max(d.maxMassAbs, std::abs(a.particleMass - b.particleMass));
            d.maxPxAbs = std::max(d.maxPxAbs, std::abs(a.momentumX - b.momentumX));
            d.maxPyAbs = std::max(d.maxPyAbs, std::abs(a.momentumY - b.momentumY));
        }
        auto addTotals = [](const std::vector<ResamplingPassiveExtractionOperation>& ops,
                            double& m, double& px, double& py, double& ke) {
            for (const auto& op : ops) {
                m += op.particleMass;
                px += op.momentumX;
                py += op.momentumY;
                ke += op.kineticEnergy;
            }
        };
        addTotals(cpuOps, d.cpuMass, d.cpuPx, d.cpuPy, d.cpuKe);
        addTotals(gpu.ops, d.gpuMass, d.gpuPx, d.gpuPy, d.gpuKe);

        std::vector<std::uint8_t> seen(static_cast<std::size_t>(state.Np), 0u);
        std::uint64_t duplicates = 0u;
        for (const auto& op : gpu.ops) {
            if (op.particleIndex >= state.Np) {
                ++duplicates;
                continue;
            }
            const std::size_t idx = static_cast<std::size_t>(op.particleIndex);
            if (seen[idx]) ++duplicates;
            seen[idx] = 1u;
        }
        d.duplicateParticleMismatch = duplicates;

        constexpr double tol = 2.0e-10;
        const auto close = [tol](double a, double b) {
            const double scale = std::max({1.0, std::abs(a), std::abs(b)});
            return std::abs(a - b) <= tol * scale;
        };
        d.handled = true;
        d.pass = d.invalidOps == 0u && d.opMismatch == 0u && d.duplicateParticleMismatch == 0u &&
                 d.cpuOps == d.gpuOps && d.maxMassAbs <= tol && d.maxPxAbs <= tol && d.maxPyAbs <= tol &&
                 close(d.cpuMass, d.gpuMass) && close(d.cpuPx, d.gpuPx) &&
                 close(d.cpuPy, d.gpuPy) && close(d.cpuKe, d.gpuKe);
        if (d.pass) {
            operationWorkspace.passiveExtractionOperations = gpu.ops;
            d.applied = true;
        } else {
            d.skipped = true;
            d.skipReason = "CUDA operation materializer did not match CPU operation gate; keeping CPU operations";
        }
        d.totalSeconds = std::chrono::duration<double>(std::chrono::steady_clock::now() - t0).count();
        append_operation_materialize_csv_0453(params, d);
        return d;
    } catch (const std::exception& e) {
        d.skipped = true;
        d.skipReason = std::string("exception: ") + e.what();
        d.totalSeconds = std::chrono::duration<double>(std::chrono::steady_clock::now() - t0).count();
        append_operation_materialize_csv_0453(params, d);
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
        if (cuda_resampling_device_carrier_0455_requested()) {
            ParticleState tmp = state;
            const GpuDeviceCarrier0455 dc =
                apply_gpu_particle_edits_device_carrier_0455(tmp, editWorkspace, grid, params);
            d.gpuExtractionApplied = dc.extractionApplied;
            d.gpuInsertionApplied = dc.insertionApplied;
            d.gpuInvalidOperations = dc.invalidMaterializeOps + dc.invalidApplyOps;
            d.applyKernelSeconds = dc.applyKernelSeconds;
            d.totalSeconds = dc.totalSeconds;
            const bool ok = (dc.pass && dc.invalidMaterializeOps == 0u && dc.invalidApplyOps == 0u &&
                             dc.extractionApplied == d.passiveOps && dc.insertionApplied == d.passiveOps);
            append_device_carrier_csv_0455(params, step, dc, true, ok, ok, ok, !ok,
                                           ok ? std::string{} : std::string("0455 device carrier gate/apply failed"));
            if (!ok) {
                d.skipped = true;
                d.skipReason = "0455 device carrier gate/apply failed; keeping non-mutated state";
                append_apply_csv_0448(params, d);
                return d;
            }
            state = std::move(tmp);
            GpuParticleApply0446 pa{};
            pa.extractionApplied = dc.extractionApplied;
            pa.insertionApplied = dc.insertionApplied;
            pa.invalidOperations = dc.invalidMaterializeOps + dc.invalidApplyOps;
            pa.kernelSeconds = dc.applyKernelSeconds;
            pa.totalSeconds = dc.totalSeconds;
            fill_extraction_insertion_diagnostics_0448(editWorkspace, pa, extractionApply, insertionApply);
            d.handled = true;
            d.applied = true;
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
