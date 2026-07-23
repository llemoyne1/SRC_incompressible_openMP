#include "cuda_species_mass_closure_0490i.h"

#include "cuda_shared_particle_state_0251.h"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <limits>
#include <stdexcept>
#include <string>

#if defined(MPCD_ENABLE_CUDA_PARTICLE_STATE) && defined(MPCD_ENABLE_CUDA_CELL_WORKSPACE)
#include <cuda_runtime.h>
#endif

namespace mpcd {
namespace {

using Clock0490i = std::chrono::steady_clock;

double seconds_since_0490i(const Clock0490i::time_point& t0) {
    return std::chrono::duration<double>(Clock0490i::now() - t0).count();
}

#if defined(MPCD_ENABLE_CUDA_PARTICLE_STATE) && defined(MPCD_ENABLE_CUDA_CELL_WORKSPACE)
#define MPCD_CUDA_0490I_CHECK(call) do { \
    const cudaError_t err__ = (call); \
    if (err__ != cudaSuccess) { \
        throw std::runtime_error(std::string("CUDA error in ") + #call + ": " + \
                                 cudaGetErrorString(err__)); \
    } \
} while (0)

template <typename T>
void cuda_free_0490i(T*& ptr) {
    if (ptr != nullptr) {
        cudaFree(ptr);
        ptr = nullptr;
    }
}

struct DeviceGridConfig0490i {
    int nx = 0;
    int ny = 0;
    double lx = 0.0;
    double ly = 0.0;
    double dx = 0.0;
    double dy = 0.0;
    int periodicX = 0;
    int periodicY = 0;
};

__device__ double wrap_periodic_0490i(double x, double L) {
    x = fmod(x, L);
    if (x < 0.0) x += L;
    if (x >= L) x -= L;
    return x;
}

__device__ int bounded_cell_index_0490i(double x, double L, double dx, int n) {
    if (x < 0.0) x = 0.0;
    if (x > L) x = L;
    int i = static_cast<int>(floor(x / dx));
    if (i < 0) i = 0;
    if (i >= n) i = n - 1;
    return i;
}

__device__ int periodic_cell_index_0490i(double x, double L, double dx, int n) {
    x = wrap_periodic_0490i(x, L);
    int i = static_cast<int>(floor(x / dx));
    if (i < 0) i = 0;
    if (i >= n) i = n - 1;
    return i;
}

__device__ int cell_index_0490i(double x, double y, DeviceGridConfig0490i cfg) {
    const int ix = cfg.periodicX
        ? periodic_cell_index_0490i(x, cfg.lx, cfg.dx, cfg.nx)
        : bounded_cell_index_0490i(x, cfg.lx, cfg.dx, cfg.nx);
    const int iy = cfg.periodicY
        ? periodic_cell_index_0490i(y, cfg.ly, cfg.dy, cfg.ny)
        : bounded_cell_index_0490i(y, cfg.ly, cfg.dy, cfg.ny);
    return ix + cfg.nx * iy;
}

__global__ void compute_species_mass_closure_scale_kernel_0490i(
    int numCells,
    int speciesCount,
    double globalStrength,
    const double* speciesMass,
    const double* totalCellMass,
    const double* totalOccupancyWeight,
    const double* referenceCellMass,
    const double* speciesClosureStrength,
    double* targetCellMass,
    double* localClosureStrength,
    double* scale,
    unsigned char* remapCell) {
    const int c = blockIdx.x * blockDim.x + threadIdx.x;
    if (c >= numCells) return;

    targetCellMass[c] = 0.0;
    localClosureStrength[c] = 0.0;
    scale[c] = 1.0;
    remapCell[c] = 0u;

    const double mass = totalCellMass[c];
    const double occupancy = totalOccupancyWeight[c];
    if (!(mass > 0.0) || !isfinite(mass) ||
        !(occupancy > 0.0) || !isfinite(occupancy)) {
        return;
    }

    double closureWeight = 0.0;
    for (int s = 0; s < speciesCount; ++s) {
        const int k = s * numCells + c;
        const double ms = speciesMass[k];
        const double ref = referenceCellMass[s];
        if (!(ms >= 0.0) || !isfinite(ms) || !(ref > 0.0) || !isfinite(ref)) {
            return;
        }
        closureWeight += (ms / ref) * speciesClosureStrength[s];
    }

    const double localTarget = mass / occupancy;
    const double speciesStrength = closureWeight / occupancy;
    const double localStrength = fmax(0.0, fmin(1.0,
        fmax(0.0, fmin(1.0, globalStrength)) * speciesStrength));
    const double effectiveTarget = mass + localStrength * (localTarget - mass);
    const double localScale = effectiveTarget / mass;
    if (!(localTarget > 0.0) || !isfinite(localTarget) ||
        !isfinite(localStrength) || !(localScale > 0.0) || !isfinite(localScale)) {
        return;
    }

    targetCellMass[c] = localTarget;
    localClosureStrength[c] = localStrength;
    scale[c] = localScale;
    remapCell[c] = 1u;
}

__global__ void apply_species_mass_closure_kernel_0490i(
    std::uint64_t nParticles,
    const double* x,
    const double* y,
    const unsigned char* role,
    unsigned char fluidRole,
    DeviceGridConfig0490i grid,
    const unsigned char* remapCell,
    const double* scale,
    double* particleMass,
    unsigned long long* particlesScaled) {
    const std::uint64_t i = static_cast<std::uint64_t>(blockIdx.x) * blockDim.x + threadIdx.x;
    if (i >= nParticles) return;
    if (role[i] != fluidRole) return;
    const int c = cell_index_0490i(x[i], y[i], grid);
    if (!remapCell[c]) return;
    const double s = scale[c];
    if (!(s > 0.0) || !isfinite(s)) return;
    particleMass[i] *= s;
    atomicAdd(particlesScaled, 1ull);
}

__device__ void atomic_max_nonnegative_double_0490m(double* address, double value) {
    if (!(value >= 0.0) || !isfinite(value)) return;
    auto* addressAsUll = reinterpret_cast<unsigned long long*>(address);
    unsigned long long old = *addressAsUll;
    while (__longlong_as_double(static_cast<long long>(old)) < value) {
        const unsigned long long assumed = old;
        old = atomicCAS(
            addressAsUll, assumed,
            static_cast<unsigned long long>(__double_as_longlong(value)));
        if (old == assumed) break;
    }
}

__global__ void initialize_species_balance_kernel_0490m(
    int numCells,
    int speciesCount,
    const unsigned char* remapCell,
    const double* cellScale,
    double* speciesCellScale) {
    const int k = blockIdx.x * blockDim.x + threadIdx.x;
    const int total = numCells * speciesCount;
    if (k >= total) return;
    const int c = k % numCells;
    speciesCellScale[k] = remapCell[c] ? cellScale[c] : 1.0;
}

__global__ void compute_species_totals_kernel_0490m(
    int numCells,
    int speciesCount,
    const double* speciesMass,
    const double* speciesCellScale,
    double* speciesTotals) {
    const int species = blockIdx.x;
    if (species >= speciesCount) return;
    extern __shared__ double partial[];
    double sum = 0.0;
    const int base = species * numCells;
    for (int c = threadIdx.x; c < numCells; c += blockDim.x) {
        const double factor = speciesCellScale ? speciesCellScale[base + c] : 1.0;
        sum += speciesMass[base + c] * factor;
    }
    partial[threadIdx.x] = sum;
    __syncthreads();
    for (int stride = blockDim.x / 2; stride > 0; stride >>= 1) {
        if (threadIdx.x < stride) partial[threadIdx.x] += partial[threadIdx.x + stride];
        __syncthreads();
    }
    if (threadIdx.x == 0) speciesTotals[species] = partial[0];
}

__global__ void apply_species_column_balance_kernel_0490m(
    int numCells,
    int speciesCount,
    const double* targetSpeciesMass,
    const double* currentSpeciesMass,
    double* speciesCellScale) {
    const int k = blockIdx.x * blockDim.x + threadIdx.x;
    const int total = numCells * speciesCount;
    if (k >= total) return;
    const int species = k / numCells;
    const double target = targetSpeciesMass[species];
    const double current = currentSpeciesMass[species];
    if (!(target >= 0.0) || !isfinite(target) || !(current > 0.0) || !isfinite(current)) {
        return;
    }
    const double correction = target / current;
    if (!(correction > 0.0) || !isfinite(correction)) return;
    speciesCellScale[k] *= correction;
}

__global__ void compute_cell_totals_kernel_0490m(
    int numCells,
    int speciesCount,
    const double* speciesMass,
    const double* speciesCellScale,
    double* cellTotals) {
    const int c = blockIdx.x * blockDim.x + threadIdx.x;
    if (c >= numCells) return;
    double total = 0.0;
    for (int species = 0; species < speciesCount; ++species) {
        const int k = species * numCells + c;
        total += speciesMass[k] * speciesCellScale[k];
    }
    cellTotals[c] = total;
}

__global__ void apply_cell_row_balance_kernel_0490m(
    int numCells,
    int speciesCount,
    const double* totalCellMass,
    const double* desiredCellScale,
    const unsigned char* remapCell,
    const double* currentCellMass,
    double* speciesCellScale) {
    const int k = blockIdx.x * blockDim.x + threadIdx.x;
    const int total = numCells * speciesCount;
    if (k >= total) return;
    const int c = k % numCells;
    if (!remapCell[c]) return;
    const double target = totalCellMass[c] * desiredCellScale[c];
    const double current = currentCellMass[c];
    if (!(target > 0.0) || !isfinite(target) || !(current > 0.0) || !isfinite(current)) {
        return;
    }
    const double correction = target / current;
    if (!(correction > 0.0) || !isfinite(correction)) return;
    speciesCellScale[k] *= correction;
}

__global__ void compute_species_balance_residual_kernel_0490m(
    int speciesCount,
    const double* targetSpeciesMass,
    const double* currentSpeciesMass,
    double* maxRelativeResidual) {
    const int species = blockIdx.x * blockDim.x + threadIdx.x;
    if (species >= speciesCount) return;
    const double target = targetSpeciesMass[species];
    const double current = currentSpeciesMass[species];
    const double denom = fmax(1.0, fabs(target));
    const double residual = fabs(current - target) / denom;
    atomic_max_nonnegative_double_0490m(maxRelativeResidual, residual);
}

__global__ void compute_cell_balance_and_velocity_shift_kernel_0490m(
    int numCells,
    int speciesCount,
    const double* speciesMass,
    const double* speciesPx,
    const double* speciesPy,
    const double* totalCellMass,
    const double* desiredCellScale,
    const double* speciesCellScale,
    double* currentCellMass,
    double* velocityShiftX,
    double* velocityShiftY,
    double* maxCellRelativeResidual,
    double* maxVelocityShift) {
    const int c = blockIdx.x * blockDim.x + threadIdx.x;
    if (c >= numCells) return;

    double originalPx = 0.0;
    double originalPy = 0.0;
    double balancedMass = 0.0;
    double balancedPx = 0.0;
    double balancedPy = 0.0;
    for (int species = 0; species < speciesCount; ++species) {
        const int k = species * numCells + c;
        const double factor = speciesCellScale[k];
        originalPx += speciesPx[k];
        originalPy += speciesPy[k];
        balancedMass += speciesMass[k] * factor;
        balancedPx += speciesPx[k] * factor;
        balancedPy += speciesPy[k] * factor;
    }
    currentCellMass[c] = balancedMass;

    const double originalMass = totalCellMass[c];
    const double desiredMass = originalMass * desiredCellScale[c];
    const double denom = fmax(1.0, fabs(desiredMass));
    const double residual = fabs(balancedMass - desiredMass) / denom;
    atomic_max_nonnegative_double_0490m(maxCellRelativeResidual, residual);

    double shiftX = 0.0;
    double shiftY = 0.0;
    if (originalMass > 0.0 && isfinite(originalMass) &&
        balancedMass > 0.0 && isfinite(balancedMass)) {
        shiftX = originalPx / originalMass - balancedPx / balancedMass;
        shiftY = originalPy / originalMass - balancedPy / balancedMass;
    }
    velocityShiftX[c] = shiftX;
    velocityShiftY[c] = shiftY;
    atomic_max_nonnegative_double_0490m(
        maxVelocityShift, fmax(fabs(shiftX), fabs(shiftY)));
}

__global__ void apply_species_balanced_mass_closure_kernel_0490m(
    std::uint64_t nParticles,
    const double* x,
    const double* y,
    double* vx,
    double* vy,
    double* particleMass,
    const std::uint32_t* particleType,
    const unsigned char* role,
    unsigned char fluidRole,
    DeviceGridConfig0490i grid,
    int numCells,
    int speciesCount,
    const std::uint32_t* speciesTypes,
    const double* speciesCellScale,
    const double* velocityShiftX,
    const double* velocityShiftY,
    unsigned long long* particlesScaled) {
    const std::uint64_t i = static_cast<std::uint64_t>(blockIdx.x) * blockDim.x + threadIdx.x;
    if (i >= nParticles) return;
    if (role[i] != fluidRole) return;
    const int c = cell_index_0490i(x[i], y[i], grid);
    int species = -1;
    const std::uint32_t type = particleType[i];
    for (int s = 0; s < speciesCount; ++s) {
        if (speciesTypes[s] == type) {
            species = s;
            break;
        }
    }
    if (species < 0) return;
    const double factor = speciesCellScale[species * numCells + c];
    if (!(factor > 0.0) || !isfinite(factor)) return;
    particleMass[i] *= factor;
    vx[i] += velocityShiftX[c];
    vy[i] += velocityShiftY[c];
    atomicAdd(particlesScaled, 1ull);
}

bool periodic_x_0490i(const SimulationParams& params) {
    return params.bcLeft == "periodic" && params.bcRight == "periodic";
}

bool periodic_y_0490i(const SimulationParams& params) {
    return params.bcBottom == "periodic" && params.bcTop == "periodic";
}
#endif

void append_diagnostics_0490i(const SimulationParams& params,
                              const CudaSpeciesMassClosure0490iDiagnostics& d) {
    if (params.outputDir.empty() || params.speciesMassClosureCudaDiagnosticsFilename.empty()) return;
    const std::filesystem::path path =
        std::filesystem::path(params.outputDir) /
        params.speciesMassClosureCudaDiagnosticsFilename;
    std::filesystem::create_directories(path.parent_path());
    const bool writeHeader = !std::filesystem::exists(path) ||
        std::filesystem::file_size(path) == 0u;
    std::ofstream out(path, std::ios::app);
    if (!out) throw std::runtime_error("0490i failed to open diagnostics CSV: " + path.string());
    if (writeHeader) {
        out << "step,attempted,handled,applied,usedSharedResidentState,particleUploadSkipped,"
               "speciesWorkspaceReused,closureWorkspaceReused,sharedStatePreserved,productionFastPath,"
               "diagnosticCellDownloadSkipped,cpuDepositComparisonSkipped,speciesConservativeBalance,"
               "balanceIterations,particlesScanned,"
               "particlesScaled,cellsConsidered,cellsRemapped,invalidTypeCount,allocatedBytes,"
               "maxAbsDepositMassError,scaleMin,scaleMax,targetCellMassMin,targetCellMassMax,"
               "closureStrengthMin,closureStrengthMax,massBefore,massAfter,massDelta,"
               "maxSpeciesMassRelResidual,maxCellMassRelResidual,maxVelocityShift,"
               "particleUploadSeconds,speciesDepositSeconds,metadataUploadSeconds,scaleKernelSeconds,"
               "applyKernelSeconds,diagnosticDownloadSeconds,particleDownloadSeconds,totalSeconds\n";
    }
    out << std::setprecision(17)
        << d.step << ',' << d.attempted << ',' << d.handled << ',' << d.applied << ','
        << d.usedSharedResidentState << ',' << d.particleUploadSkipped << ','
        << d.speciesWorkspaceReused << ',' << d.closureWorkspaceReused << ','
        << d.sharedStatePreserved << ',' << d.productionFastPath << ','
        << d.diagnosticCellDownloadSkipped << ',' << d.cpuDepositComparisonSkipped << ','
        << d.speciesConservativeBalance << ',' << d.balanceIterations << ','
        << d.particlesScanned << ',' << d.particlesScaled << ','
        << d.cellsConsidered << ',' << d.cellsRemapped << ',' << d.invalidTypeCount << ','
        << d.allocatedBytes << ',' << d.maxAbsDepositMassError << ',' << d.scaleMin << ','
        << d.scaleMax << ',' << d.targetCellMassMin << ',' << d.targetCellMassMax << ','
        << d.closureStrengthMin << ',' << d.closureStrengthMax << ',' << d.massBefore << ','
        << d.massAfter << ',' << d.massDelta << ','
        << d.maxSpeciesMassRelResidual << ',' << d.maxCellMassRelResidual << ','
        << d.maxVelocityShift << ',' << d.particleUploadSeconds << ','
        << d.speciesDepositSeconds << ',' << d.metadataUploadSeconds << ','
        << d.scaleKernelSeconds << ',' << d.applyKernelSeconds << ','
        << d.diagnosticDownloadSeconds << ',' << d.particleDownloadSeconds << ','
        << d.totalSeconds << '\n';
}

} // namespace

struct CudaSpeciesMassClosureWorkspace0490i::Impl {
    int cellCapacity = 0;
    int speciesCapacity = 0;
    int numCells = 0;
    int speciesCount = 0;
    std::uint64_t allocatedBytes = 0u;
    double* speciesClosureStrength = nullptr;
    double* targetCellMass = nullptr;
    double* localClosureStrength = nullptr;
    double* scale = nullptr;
    unsigned char* remapCell = nullptr;
    double* speciesCellScale = nullptr;
    double* targetSpeciesMass = nullptr;
    double* currentSpeciesMass = nullptr;
    double* currentCellMass = nullptr;
    double* velocityShiftX = nullptr;
    double* velocityShiftY = nullptr;
    double* maxSpeciesMassRelResidual = nullptr;
    double* maxCellMassRelResidual = nullptr;
    double* maxVelocityShift = nullptr;
    unsigned long long* particlesScaled = nullptr;
};

CudaSpeciesMassClosureWorkspace0490i::CudaSpeciesMassClosureWorkspace0490i()
    : impl_(new Impl()) {}

CudaSpeciesMassClosureWorkspace0490i::~CudaSpeciesMassClosureWorkspace0490i() {
    release();
    delete impl_;
    impl_ = nullptr;
}

CudaSpeciesMassClosureWorkspace0490i::CudaSpeciesMassClosureWorkspace0490i(
    CudaSpeciesMassClosureWorkspace0490i&& other) noexcept
    : impl_(other.impl_) {
    other.impl_ = new Impl();
}

CudaSpeciesMassClosureWorkspace0490i& CudaSpeciesMassClosureWorkspace0490i::operator=(
    CudaSpeciesMassClosureWorkspace0490i&& other) noexcept {
    if (this != &other) {
        release();
        delete impl_;
        impl_ = other.impl_;
        other.impl_ = new Impl();
    }
    return *this;
}

void CudaSpeciesMassClosureWorkspace0490i::release() {
#if defined(MPCD_ENABLE_CUDA_PARTICLE_STATE) && defined(MPCD_ENABLE_CUDA_CELL_WORKSPACE)
    if (impl_ != nullptr) {
        cuda_free_0490i(impl_->speciesClosureStrength);
        cuda_free_0490i(impl_->targetCellMass);
        cuda_free_0490i(impl_->localClosureStrength);
        cuda_free_0490i(impl_->scale);
        cuda_free_0490i(impl_->remapCell);
        cuda_free_0490i(impl_->speciesCellScale);
        cuda_free_0490i(impl_->targetSpeciesMass);
        cuda_free_0490i(impl_->currentSpeciesMass);
        cuda_free_0490i(impl_->currentCellMass);
        cuda_free_0490i(impl_->velocityShiftX);
        cuda_free_0490i(impl_->velocityShiftY);
        cuda_free_0490i(impl_->maxSpeciesMassRelResidual);
        cuda_free_0490i(impl_->maxCellMassRelResidual);
        cuda_free_0490i(impl_->maxVelocityShift);
        cuda_free_0490i(impl_->particlesScaled);
    }
#endif
    if (impl_ != nullptr) *impl_ = Impl{};
}

void CudaSpeciesMassClosureWorkspace0490i::ensure_capacity(
    int numCells, int speciesCount, int* reused) {
#if !defined(MPCD_ENABLE_CUDA_PARTICLE_STATE) || !defined(MPCD_ENABLE_CUDA_CELL_WORKSPACE)
    (void)numCells; (void)speciesCount; (void)reused;
    throw std::runtime_error("0490i workspace requires CUDA particle state and cell workspace");
#else
    if (impl_ == nullptr) throw std::runtime_error("0490i workspace has null impl");
    if (numCells <= 0 || speciesCount <= 0) {
        throw std::runtime_error("0490i workspace requires positive dimensions");
    }
    const bool canReuse = impl_->cellCapacity >= numCells &&
                          impl_->speciesCapacity >= speciesCount &&
                          impl_->scale != nullptr;
    if (canReuse) {
        impl_->numCells = numCells;
        impl_->speciesCount = speciesCount;
        if (reused) *reused = 1;
        return;
    }
    release();
    const std::size_t nc = static_cast<std::size_t>(numCells);
    const std::size_t ns = static_cast<std::size_t>(speciesCount);
    MPCD_CUDA_0490I_CHECK(cudaMalloc(&impl_->speciesClosureStrength, ns * sizeof(double)));
    MPCD_CUDA_0490I_CHECK(cudaMalloc(&impl_->targetCellMass, nc * sizeof(double)));
    MPCD_CUDA_0490I_CHECK(cudaMalloc(&impl_->localClosureStrength, nc * sizeof(double)));
    MPCD_CUDA_0490I_CHECK(cudaMalloc(&impl_->scale, nc * sizeof(double)));
    MPCD_CUDA_0490I_CHECK(cudaMalloc(&impl_->remapCell, nc * sizeof(unsigned char)));
    MPCD_CUDA_0490I_CHECK(cudaMalloc(&impl_->speciesCellScale, nc * ns * sizeof(double)));
    MPCD_CUDA_0490I_CHECK(cudaMalloc(&impl_->targetSpeciesMass, ns * sizeof(double)));
    MPCD_CUDA_0490I_CHECK(cudaMalloc(&impl_->currentSpeciesMass, ns * sizeof(double)));
    MPCD_CUDA_0490I_CHECK(cudaMalloc(&impl_->currentCellMass, nc * sizeof(double)));
    MPCD_CUDA_0490I_CHECK(cudaMalloc(&impl_->velocityShiftX, nc * sizeof(double)));
    MPCD_CUDA_0490I_CHECK(cudaMalloc(&impl_->velocityShiftY, nc * sizeof(double)));
    MPCD_CUDA_0490I_CHECK(cudaMalloc(&impl_->maxSpeciesMassRelResidual, sizeof(double)));
    MPCD_CUDA_0490I_CHECK(cudaMalloc(&impl_->maxCellMassRelResidual, sizeof(double)));
    MPCD_CUDA_0490I_CHECK(cudaMalloc(&impl_->maxVelocityShift, sizeof(double)));
    MPCD_CUDA_0490I_CHECK(cudaMalloc(&impl_->particlesScaled, sizeof(unsigned long long)));
    impl_->cellCapacity = numCells;
    impl_->speciesCapacity = speciesCount;
    impl_->numCells = numCells;
    impl_->speciesCount = speciesCount;
    impl_->allocatedBytes =
        ns * sizeof(double) + nc * (3u * sizeof(double) + sizeof(unsigned char)) +
        nc * ns * sizeof(double) + 2u * ns * sizeof(double) +
        3u * nc * sizeof(double) + 3u * sizeof(double) +
        sizeof(unsigned long long);
    if (reused) *reused = 0;
#endif
}

CudaSpeciesMassClosureDeviceView0490i CudaSpeciesMassClosureWorkspace0490i::device_view() {
    return static_cast<const CudaSpeciesMassClosureWorkspace0490i*>(this)->device_view();
}

CudaSpeciesMassClosureDeviceView0490i CudaSpeciesMassClosureWorkspace0490i::device_view() const {
    CudaSpeciesMassClosureDeviceView0490i v{};
    if (impl_ == nullptr) return v;
    v.numCells = impl_->numCells;
    v.speciesCount = impl_->speciesCount;
    v.speciesClosureStrength = impl_->speciesClosureStrength;
    v.targetCellMass = impl_->targetCellMass;
    v.localClosureStrength = impl_->localClosureStrength;
    v.scale = impl_->scale;
    v.remapCell = impl_->remapCell;
    v.speciesCellScale = impl_->speciesCellScale;
    v.targetSpeciesMass = impl_->targetSpeciesMass;
    v.currentSpeciesMass = impl_->currentSpeciesMass;
    v.currentCellMass = impl_->currentCellMass;
    v.velocityShiftX = impl_->velocityShiftX;
    v.velocityShiftY = impl_->velocityShiftY;
    v.maxSpeciesMassRelResidual = impl_->maxSpeciesMassRelResidual;
    v.maxCellMassRelResidual = impl_->maxCellMassRelResidual;
    v.maxVelocityShift = impl_->maxVelocityShift;
    v.particlesScaled = impl_->particlesScaled;
    return v;
}

std::uint64_t CudaSpeciesMassClosureWorkspace0490i::allocated_bytes() const {
    return impl_ ? impl_->allocatedBytes : 0u;
}

bool cuda_species_mass_closure_available_0490i() {
#if defined(MPCD_ENABLE_CUDA_PARTICLE_STATE) && defined(MPCD_ENABLE_CUDA_CELL_WORKSPACE)
    return cuda_species_cell_fields_available_0490h();
#else
    return false;
#endif
}

CudaSpeciesMassClosure0490iDiagnostics apply_cuda_species_mass_closure_0490i(
    ParticleState& state,
    const SimulationParams& params,
    const CellGrid& grid,
    const WeightedRealFluidDepositWorkspace& cpuDepositWorkspace,
    const WeightedResamplingDiagnostics& cpuDepositDiagnostics,
    double massCorrectionStrength,
    double targetCellMassOverride,
    std::uint64_t step,
    CudaSpeciesCellWorkspace0490h& speciesWorkspace,
    CudaSpeciesMassClosureWorkspace0490i& closureWorkspace,
    ResamplingRemapApplyDiagnostics& remapApply,
    int threadsPerBlock) {
    CudaSpeciesMassClosure0490iDiagnostics d{};
    d.attempted = 1;
    d.step = step;
    d.productionFastPath = params.speciesResamplingCudaResidentFastPathEnable ? 1 : 0;
    d.diagnosticCellDownloadSkipped = d.productionFastPath;
    d.cpuDepositComparisonSkipped = d.productionFastPath;
    d.diagnosticsCsv = params.outputDir + "/" + params.speciesMassClosureCudaDiagnosticsFilename;
    const Clock0490i::time_point total0 = Clock0490i::now();
#if !defined(MPCD_ENABLE_CUDA_PARTICLE_STATE) || !defined(MPCD_ENABLE_CUDA_CELL_WORKSPACE)
    (void)state; (void)params; (void)grid; (void)cpuDepositWorkspace;
    (void)cpuDepositDiagnostics; (void)massCorrectionStrength;
    (void)targetCellMassOverride; (void)speciesWorkspace; (void)closureWorkspace;
    (void)remapApply; (void)threadsPerBlock;
    throw std::runtime_error("0490i resident CUDA species mass closure is unavailable in this build");
#else
    if (!params.speciesResamplingMassClosureCudaEnable) {
        throw std::runtime_error("0490i called while speciesResamplingMassClosureCudaEnable=false");
    }
    if (!params.speciesResamplingMassClosureEnable) {
        throw std::runtime_error("0490i requires the 0490d species mass closure policy");
    }
    if (params.resamplingThermalRenormalizationEnable) {
        throw std::runtime_error("0490i does not yet include CUDA thermal renormalization");
    }
    if (targetCellMassOverride > 0.0 && std::isfinite(targetCellMassOverride)) {
        throw std::runtime_error("0490i does not support targetCellMassOverride");
    }
    if (grid.numCells <= 0 || grid.numCells != grid.Nx * grid.Ny) {
        throw std::runtime_error("0490i received an invalid grid");
    }
    if (cpuDepositWorkspace.allocatedCells != grid.numCells ||
        cpuDepositWorkspace.mass.size() != static_cast<std::size_t>(grid.numCells)) {
        throw std::runtime_error("0490i received an invalid CPU reference deposit");
    }
    validate_species_definitions(params.speciesDefinitions, "0490i species registry");
    validate_state_species_registry(
        state, params.speciesDefinitions, true, "0490i host state registry");
    if (threadsPerBlock <= 0 || threadsPerBlock > 1024) threadsPerBlock = 256;

    CudaParticleState& shared = cuda_shared_particle_state_0251();
    const bool sharedFresh = cuda_shared_particle_state_0251_is_fresh() &&
                             shared.size() == state.Np &&
                             shared.active_fluid_size() == state.NactiveFluid;
    CudaParticleStateDiagnostics particleUpload{};
    if (!sharedFresh) shared.upload_all(state, &particleUpload);
    d.usedSharedResidentState = 1;
    d.particleUploadSkipped = sharedFresh ? 1 : 0;
    d.particleUploadSeconds = particleUpload.uploadSeconds;

    CudaSpeciesCellDepositDiagnostics0490h speciesDiag{};
    cuda_deposit_species_cell_fields_resident_0490h(
        shared.device_view(), grid, params, params.speciesDefinitions,
        speciesWorkspace, &speciesDiag, threadsPerBlock);
    d.speciesWorkspaceReused = speciesDiag.reusedAllocation;
    d.speciesDepositSeconds = speciesDiag.resetSeconds + speciesDiag.depositSeconds +
                              speciesDiag.finalizeSeconds;
    d.invalidTypeCount = speciesDiag.invalidTypeCount;
    d.particlesScanned = speciesDiag.particlesScanned;
    if (d.invalidTypeCount != 0u) {
        throw std::runtime_error("0490i CUDA species deposit found unregistered types");
    }

    int closureReused = 0;
    closureWorkspace.ensure_capacity(
        grid.numCells, static_cast<int>(params.speciesDefinitions.size()), &closureReused);
    d.closureWorkspaceReused = closureReused;
    d.allocatedBytes = speciesWorkspace.allocated_bytes() + closureWorkspace.allocated_bytes();
    CudaSpeciesCellDeviceView0490h speciesView = speciesWorkspace.device_view();
    CudaSpeciesMassClosureDeviceView0490i closureView = closureWorkspace.device_view();

    std::vector<double> hostClosureStrength(params.speciesDefinitions.size(), 0.0);
    for (std::size_t s = 0; s < params.speciesDefinitions.size(); ++s) {
        hostClosureStrength[s] =
            params.speciesDefinitions[s].resamplingMassClosureStrengthDeclared;
    }
    const Clock0490i::time_point meta0 = Clock0490i::now();
    MPCD_CUDA_0490I_CHECK(cudaMemcpy(
        closureView.speciesClosureStrength, hostClosureStrength.data(),
        hostClosureStrength.size() * sizeof(double), cudaMemcpyHostToDevice));
    MPCD_CUDA_0490I_CHECK(cudaMemset(
        closureView.particlesScaled, 0, sizeof(unsigned long long)));
    d.metadataUploadSeconds = seconds_since_0490i(meta0);

    const int cellBlocks = std::max(1, (grid.numCells + threadsPerBlock - 1) / threadsPerBlock);
    cudaEvent_t start{}, stop{};
    MPCD_CUDA_0490I_CHECK(cudaEventCreate(&start));
    MPCD_CUDA_0490I_CHECK(cudaEventCreate(&stop));
    auto elapsed = [&]() {
        float ms = 0.0f;
        MPCD_CUDA_0490I_CHECK(cudaEventElapsedTime(&ms, start, stop));
        return static_cast<double>(ms) * 1.0e-3;
    };

    const int speciesCount = static_cast<int>(params.speciesDefinitions.size());
    constexpr int speciesReductionThreads = 256;
    const std::size_t speciesReductionSharedBytes =
        static_cast<std::size_t>(speciesReductionThreads) * sizeof(double);
    const int speciesBlocks =
        std::max(1, (speciesCount + threadsPerBlock - 1) / threadsPerBlock);
    const int matrixEntries = grid.numCells * speciesCount;
    const int matrixBlocks = std::max(1, (matrixEntries + threadsPerBlock - 1) / threadsPerBlock);
    const bool useSpeciesConservativeBalance = d.productionFastPath && speciesCount > 1;

    MPCD_CUDA_0490I_CHECK(cudaEventRecord(start));
    compute_species_mass_closure_scale_kernel_0490i<<<cellBlocks, threadsPerBlock>>>(
        grid.numCells, speciesCount, massCorrectionStrength, speciesView.mass,
        speciesView.totalCellMass, speciesView.totalOccupancyWeight,
        speciesView.referenceCellMass, closureView.speciesClosureStrength,
        closureView.targetCellMass, closureView.localClosureStrength,
        closureView.scale, closureView.remapCell);
    MPCD_CUDA_0490I_CHECK(cudaGetLastError());

    if (useSpeciesConservativeBalance) {
        constexpr int balanceIterations0490m = 8;
        d.speciesConservativeBalance = 1;
        d.balanceIterations = balanceIterations0490m;
        MPCD_CUDA_0490I_CHECK(cudaMemset(
            closureView.maxSpeciesMassRelResidual, 0, sizeof(double)));
        MPCD_CUDA_0490I_CHECK(cudaMemset(
            closureView.maxCellMassRelResidual, 0, sizeof(double)));
        MPCD_CUDA_0490I_CHECK(cudaMemset(
            closureView.maxVelocityShift, 0, sizeof(double)));

        initialize_species_balance_kernel_0490m<<<matrixBlocks, threadsPerBlock>>>(
            grid.numCells, speciesCount, closureView.remapCell, closureView.scale,
            closureView.speciesCellScale);
        MPCD_CUDA_0490I_CHECK(cudaGetLastError());
        compute_species_totals_kernel_0490m<<<
            speciesCount, speciesReductionThreads, speciesReductionSharedBytes>>>(
            grid.numCells, speciesCount, speciesView.mass, nullptr,
            closureView.targetSpeciesMass);
        MPCD_CUDA_0490I_CHECK(cudaGetLastError());

        for (int iteration = 0; iteration < balanceIterations0490m; ++iteration) {
            compute_species_totals_kernel_0490m<<<
            speciesCount, speciesReductionThreads, speciesReductionSharedBytes>>>(
                grid.numCells, speciesCount, speciesView.mass,
                closureView.speciesCellScale, closureView.currentSpeciesMass);
            MPCD_CUDA_0490I_CHECK(cudaGetLastError());
            apply_species_column_balance_kernel_0490m<<<matrixBlocks, threadsPerBlock>>>(
                grid.numCells, speciesCount, closureView.targetSpeciesMass,
                closureView.currentSpeciesMass, closureView.speciesCellScale);
            MPCD_CUDA_0490I_CHECK(cudaGetLastError());
            compute_cell_totals_kernel_0490m<<<cellBlocks, threadsPerBlock>>>(
                grid.numCells, speciesCount, speciesView.mass,
                closureView.speciesCellScale, closureView.currentCellMass);
            MPCD_CUDA_0490I_CHECK(cudaGetLastError());
            apply_cell_row_balance_kernel_0490m<<<matrixBlocks, threadsPerBlock>>>(
                grid.numCells, speciesCount, speciesView.totalCellMass,
                closureView.scale, closureView.remapCell, closureView.currentCellMass,
                closureView.speciesCellScale);
            MPCD_CUDA_0490I_CHECK(cudaGetLastError());
        }

        // End on the species constraint. This makes global mass by registered
        // type the hard invariant even when a disconnected pure-species support
        // makes the requested cell targets mathematically incompatible.
        compute_species_totals_kernel_0490m<<<
            speciesCount, speciesReductionThreads, speciesReductionSharedBytes>>>(
            grid.numCells, speciesCount, speciesView.mass,
            closureView.speciesCellScale, closureView.currentSpeciesMass);
        MPCD_CUDA_0490I_CHECK(cudaGetLastError());
        apply_species_column_balance_kernel_0490m<<<matrixBlocks, threadsPerBlock>>>(
            grid.numCells, speciesCount, closureView.targetSpeciesMass,
            closureView.currentSpeciesMass, closureView.speciesCellScale);
        MPCD_CUDA_0490I_CHECK(cudaGetLastError());
        compute_species_totals_kernel_0490m<<<
            speciesCount, speciesReductionThreads, speciesReductionSharedBytes>>>(
            grid.numCells, speciesCount, speciesView.mass,
            closureView.speciesCellScale, closureView.currentSpeciesMass);
        MPCD_CUDA_0490I_CHECK(cudaGetLastError());
        compute_species_balance_residual_kernel_0490m<<<speciesBlocks, threadsPerBlock>>>(
            speciesCount, closureView.targetSpeciesMass,
            closureView.currentSpeciesMass, closureView.maxSpeciesMassRelResidual);
        MPCD_CUDA_0490I_CHECK(cudaGetLastError());
        compute_cell_balance_and_velocity_shift_kernel_0490m<<<cellBlocks, threadsPerBlock>>>(
            grid.numCells, speciesCount, speciesView.mass, speciesView.px,
            speciesView.py, speciesView.totalCellMass, closureView.scale,
            closureView.speciesCellScale, closureView.currentCellMass,
            closureView.velocityShiftX, closureView.velocityShiftY,
            closureView.maxCellMassRelResidual, closureView.maxVelocityShift);
        MPCD_CUDA_0490I_CHECK(cudaGetLastError());
    }

    MPCD_CUDA_0490I_CHECK(cudaEventRecord(stop));
    MPCD_CUDA_0490I_CHECK(cudaEventSynchronize(stop));
    d.scaleKernelSeconds = elapsed();

    if (useSpeciesConservativeBalance) {
        MPCD_CUDA_0490I_CHECK(cudaMemcpy(
            &d.maxSpeciesMassRelResidual, closureView.maxSpeciesMassRelResidual,
            sizeof(double), cudaMemcpyDeviceToHost));
        MPCD_CUDA_0490I_CHECK(cudaMemcpy(
            &d.maxCellMassRelResidual, closureView.maxCellMassRelResidual,
            sizeof(double), cudaMemcpyDeviceToHost));
        MPCD_CUDA_0490I_CHECK(cudaMemcpy(
            &d.maxVelocityShift, closureView.maxVelocityShift,
            sizeof(double), cudaMemcpyDeviceToHost));
        const double conservationTolerance = std::max(
            1.0e-13, params.speciesMassClosureCudaComparisonTolerance);
        if (!std::isfinite(d.maxSpeciesMassRelResidual) ||
            d.maxSpeciesMassRelResidual > conservationTolerance) {
            throw std::runtime_error(
                "0490m species-conservative CUDA mass closure failed: maxRelativeResidual=" +
                std::to_string(d.maxSpeciesMassRelResidual));
        }
    }

    DeviceGridConfig0490i cfg{};
    cfg.nx = grid.Nx;
    cfg.ny = grid.Ny;
    cfg.lx = grid.Lx;
    cfg.ly = grid.Ly;
    cfg.dx = grid.dx;
    cfg.dy = grid.dy;
    cfg.periodicX = periodic_x_0490i(params) ? 1 : 0;
    cfg.periodicY = periodic_y_0490i(params) ? 1 : 0;
    const CudaParticleDeviceView particleView = shared.device_view();
    const std::uint64_t nParticles = particleView.nActiveFluid > 0u
        ? particleView.nActiveFluid : particleView.n;
    const std::uint64_t blockCount64 =
        (nParticles + static_cast<std::uint64_t>(threadsPerBlock) - 1u) /
        static_cast<std::uint64_t>(threadsPerBlock);
    if (blockCount64 > static_cast<std::uint64_t>(std::numeric_limits<int>::max())) {
        throw std::runtime_error("0490i particle block count exceeds int range");
    }
    MPCD_CUDA_0490I_CHECK(cudaEventRecord(start));
    if (nParticles > 0u) {
        if (useSpeciesConservativeBalance) {
            apply_species_balanced_mass_closure_kernel_0490m<<<
                static_cast<int>(blockCount64), threadsPerBlock>>>(
                nParticles, particleView.x, particleView.y, particleView.vx,
                particleView.vy, particleView.mass, particleView.type,
                particleView.role, static_cast<unsigned char>(kParticleRoleFluid),
                cfg, grid.numCells, speciesCount, speciesView.speciesTypes,
                closureView.speciesCellScale, closureView.velocityShiftX,
                closureView.velocityShiftY, closureView.particlesScaled);
        } else {
            apply_species_mass_closure_kernel_0490i<<<
                static_cast<int>(blockCount64), threadsPerBlock>>>(
                nParticles, particleView.x, particleView.y, particleView.role,
                static_cast<unsigned char>(kParticleRoleFluid), cfg,
                closureView.remapCell, closureView.scale, particleView.mass,
                closureView.particlesScaled);
        }
        MPCD_CUDA_0490I_CHECK(cudaGetLastError());
    }
    MPCD_CUDA_0490I_CHECK(cudaEventRecord(stop));
    MPCD_CUDA_0490I_CHECK(cudaEventSynchronize(stop));
    d.applyKernelSeconds = elapsed();
    MPCD_CUDA_0490I_CHECK(cudaEventDestroy(start));
    MPCD_CUDA_0490I_CHECK(cudaEventDestroy(stop));

    const Clock0490i::time_point download0 = Clock0490i::now();
    unsigned long long particlesScaled = 0ull;
    MPCD_CUDA_0490I_CHECK(cudaMemcpy(&particlesScaled, closureView.particlesScaled,
                                    sizeof(particlesScaled), cudaMemcpyDeviceToHost));
    d.particlesScaled = static_cast<std::uint64_t>(particlesScaled);

    remapApply = ResamplingRemapApplyDiagnostics{};
    remapApply.attempted = true;
    remapApply.targetCellMass = cpuDepositDiagnostics.targetCellMass;
    remapApply.massCorrectionStrength = std::clamp(massCorrectionStrength, 0.0, 1.0);
    remapApply.speciesMassClosureActive = true;
    remapApply.particlesRemapped = d.particlesScaled;
    remapApply.applied = d.particlesScaled > 0u;
    remapApply.allRemappedCellsNonEmpty = true;

    if (!params.speciesResamplingCudaResidentFastPathEnable) {
        std::vector<double> totalMass(static_cast<std::size_t>(grid.numCells), 0.0);
        std::vector<double> target(static_cast<std::size_t>(grid.numCells), 0.0);
        std::vector<double> localStrength(static_cast<std::size_t>(grid.numCells), 0.0);
        std::vector<double> scale(static_cast<std::size_t>(grid.numCells), 1.0);
        std::vector<unsigned char> remap(static_cast<std::size_t>(grid.numCells), 0u);
        MPCD_CUDA_0490I_CHECK(cudaMemcpy(totalMass.data(), speciesView.totalCellMass,
                                        totalMass.size() * sizeof(double), cudaMemcpyDeviceToHost));
        MPCD_CUDA_0490I_CHECK(cudaMemcpy(target.data(), closureView.targetCellMass,
                                        target.size() * sizeof(double), cudaMemcpyDeviceToHost));
        MPCD_CUDA_0490I_CHECK(cudaMemcpy(localStrength.data(), closureView.localClosureStrength,
                                        localStrength.size() * sizeof(double), cudaMemcpyDeviceToHost));
        MPCD_CUDA_0490I_CHECK(cudaMemcpy(scale.data(), closureView.scale,
                                        scale.size() * sizeof(double), cudaMemcpyDeviceToHost));
        MPCD_CUDA_0490I_CHECK(cudaMemcpy(remap.data(), closureView.remapCell,
                                        remap.size() * sizeof(unsigned char), cudaMemcpyDeviceToHost));

        remapApply.speciesTargetCellMassMin = std::numeric_limits<double>::infinity();
        remapApply.speciesClosureStrengthMin = std::numeric_limits<double>::infinity();
        remapApply.scaleMin = std::numeric_limits<double>::infinity();
        remapApply.scaleMax = 0.0;
        constexpr double eps = 1.0e-13;
        for (int c = 0; c < grid.numCells; ++c) {
            const std::size_t k = static_cast<std::size_t>(c);
            d.maxAbsDepositMassError = std::max(
                d.maxAbsDepositMassError,
                std::abs(totalMass[k] - cpuDepositWorkspace.mass[k]));
            if (!remap[k]) continue;
            d.cellsConsidered += 1u;
            remapApply.cellsConsidered += 1u;
            remapApply.speciesMassClosureCells += 1u;
            remapApply.speciesTargetCellMassMin =
                std::min(remapApply.speciesTargetCellMassMin, target[k]);
            remapApply.speciesTargetCellMassMax =
                std::max(remapApply.speciesTargetCellMassMax, target[k]);
            remapApply.speciesClosureStrengthMin =
                std::min(remapApply.speciesClosureStrengthMin, localStrength[k]);
            remapApply.speciesClosureStrengthMax =
                std::max(remapApply.speciesClosureStrengthMax, localStrength[k]);
            remapApply.scaleMin = std::min(remapApply.scaleMin, scale[k]);
            remapApply.scaleMax = std::max(remapApply.scaleMax, scale[k]);
            const double m0 = totalMass[k];
            const double m1 = m0 * scale[k];
            remapApply.massBefore += m0;
            remapApply.massAfter += m1;
            remapApply.massTargetSum += target[k];
            if (k < cpuDepositWorkspace.px.size()) {
                const double px = cpuDepositWorkspace.px[k];
                const double py = cpuDepositWorkspace.py[k];
                remapApply.momentumXBefore += px;
                remapApply.momentumYBefore += py;
                remapApply.momentumXAfter += scale[k] * px;
                remapApply.momentumYAfter += scale[k] * py;
                remapApply.momentumXTarget += m1 * cpuDepositWorkspace.ux[k];
                remapApply.momentumYTarget += m1 * cpuDepositWorkspace.uy[k];
            }
            if (std::abs(scale[k] - 1.0) > eps) {
                d.cellsRemapped += 1u;
                remapApply.cellsRemapped += 1u;
                if (remapApply.firstRemappedCell == kInvalidCellIndex) {
                    remapApply.firstRemappedCell = static_cast<std::int32_t>(c);
                }
                remapApply.lastRemappedCell = static_cast<std::int32_t>(c);
            }
        }
        if (!std::isfinite(remapApply.speciesTargetCellMassMin)) {
            remapApply.speciesTargetCellMassMin = 0.0;
        }
        if (!std::isfinite(remapApply.speciesClosureStrengthMin)) {
            remapApply.speciesClosureStrengthMin = 0.0;
        }
        if (!std::isfinite(remapApply.scaleMin)) remapApply.scaleMin = 1.0;
        if (!(remapApply.scaleMax > 0.0)) remapApply.scaleMax = 1.0;
        remapApply.massDelta = remapApply.massAfter - remapApply.massBefore;

        d.scaleMin = remapApply.scaleMin;
        d.scaleMax = remapApply.scaleMax;
        d.targetCellMassMin = remapApply.speciesTargetCellMassMin;
        d.targetCellMassMax = remapApply.speciesTargetCellMassMax;
        d.closureStrengthMin = remapApply.speciesClosureStrengthMin;
        d.closureStrengthMax = remapApply.speciesClosureStrengthMax;
        d.massBefore = remapApply.massBefore;
        d.massAfter = remapApply.massAfter;
        d.massDelta = remapApply.massDelta;
        if (d.maxAbsDepositMassError > params.speciesMassClosureCudaComparisonTolerance) {
            throw std::runtime_error(
                "0490i CUDA/CPU pre-remap deposit mismatch: maxAbsMassError=" +
                std::to_string(d.maxAbsDepositMassError));
        }
    } else {
        // Production-fast diagnostics remain scalar. The resident balancing
        // above preserves every global species mass and reports the residual of
        // the requested cell targets without downloading dense cell arrays or
        // executing the CPU equivalence loop.
        remapApply.scaleMin = 1.0;
        remapApply.scaleMax = 1.0;
        d.scaleMin = 1.0;
        d.scaleMax = 1.0;
    }
    d.diagnosticDownloadSeconds = seconds_since_0490i(download0);
    cuda_shared_particle_state_0251_mark_fresh("species_mass_closure_0490i");
    d.sharedStatePreserved = 1;
    CudaParticleStateDiagnostics particleDownload{};
    shared.download_masses_and_velocities(state, &particleDownload);
    d.particleDownloadSeconds = particleDownload.downloadSeconds;

    d.handled = 1;
    d.applied = remapApply.applied ? 1 : 0;
    d.totalSeconds = seconds_since_0490i(total0);
    append_diagnostics_0490i(params, d);
    return d;
#endif
}

} // namespace mpcd
