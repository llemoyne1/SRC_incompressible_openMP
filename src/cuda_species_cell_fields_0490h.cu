#include "cuda_species_cell_fields_0490h.h"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <iomanip>
#include <limits>
#include <stdexcept>
#include <string>

#if defined(MPCD_ENABLE_CUDA_PARTICLE_STATE) && defined(MPCD_ENABLE_CUDA_CELL_WORKSPACE)
#include <cuda_runtime.h>
#endif

namespace mpcd {
namespace {

using Clock = std::chrono::steady_clock;

double seconds_since_0490h(const Clock::time_point& t0) {
    return std::chrono::duration<double>(Clock::now() - t0).count();
}

double max_abs_0490h(double a, double b) {
    return std::max(a, std::abs(b));
}

#if defined(MPCD_ENABLE_CUDA_PARTICLE_STATE) && defined(MPCD_ENABLE_CUDA_CELL_WORKSPACE)
#define MPCD_CUDA_0490H_CHECK(call) do { \
    const cudaError_t err__ = (call); \
    if (err__ != cudaSuccess) { \
        throw std::runtime_error(std::string("CUDA error in ") + #call + ": " + \
                                 cudaGetErrorString(err__)); \
    } \
} while (0)

template <typename T>
void cuda_free_0490h(T*& ptr) {
    if (ptr != nullptr) {
        cudaFree(ptr);
        ptr = nullptr;
    }
}

__device__ double atomic_add_double_0490h(double* address, double value) {
#if __CUDA_ARCH__ >= 600
    return atomicAdd(address, value);
#else
    unsigned long long int* addressAsUll =
        reinterpret_cast<unsigned long long int*>(address);
    unsigned long long int old = *addressAsUll;
    unsigned long long int assumed;
    do {
        assumed = old;
        old = atomicCAS(addressAsUll, assumed,
                        __double_as_longlong(value + __longlong_as_double(assumed)));
    } while (assumed != old);
    return __longlong_as_double(old);
#endif
}

struct DeviceGridConfig0490h {
    int nx = 0;
    int ny = 0;
    int numCells = 0;
    double lx = 0.0;
    double ly = 0.0;
    double dx = 0.0;
    double dy = 0.0;
    int periodicX = 0;
    int periodicY = 0;
};

__device__ double wrap_periodic_0490h(double x, double L) {
    x = fmod(x, L);
    if (x < 0.0) x += L;
    if (x >= L) x -= L;
    return x;
}

__device__ int bounded_cell_index_0490h(double x, double L, double dx, int n) {
    if (x < 0.0) x = 0.0;
    if (x > L) x = L;
    int i = static_cast<int>(floor(x / dx));
    if (i < 0) i = 0;
    if (i >= n) i = n - 1;
    return i;
}

__device__ int periodic_cell_index_0490h(double x, double L, double dx, int n) {
    x = wrap_periodic_0490h(x, L);
    int i = static_cast<int>(floor(x / dx));
    if (i < 0) i = 0;
    if (i >= n) i = n - 1;
    return i;
}

__device__ int cell_index_0490h(double x, double y, DeviceGridConfig0490h cfg) {
    const int ix = cfg.periodicX
        ? periodic_cell_index_0490h(x, cfg.lx, cfg.dx, cfg.nx)
        : bounded_cell_index_0490h(x, cfg.lx, cfg.dx, cfg.nx);
    const int iy = cfg.periodicY
        ? periodic_cell_index_0490h(y, cfg.ly, cfg.dy, cfg.ny)
        : bounded_cell_index_0490h(y, cfg.ly, cfg.dy, cfg.ny);
    return ix + cfg.nx * iy;
}

__global__ void reset_species_cell_fields_0490h(
    int denseSize,
    int numCells,
    unsigned int* count,
    double* mass,
    double* massSquared,
    double* px,
    double* py,
    double* kinetic,
    double* totalCellMass,
    double* totalOccupancyWeight,
    double* massFraction,
    double* occupancyFraction,
    double* liquidFractionProxy,
    double* gasFractionProxy,
    unsigned long long* invalidTypeCounter) {
    const int tid = blockIdx.x * blockDim.x + threadIdx.x;
    const int stride = blockDim.x * gridDim.x;
    for (int k = tid; k < denseSize; k += stride) {
        count[k] = 0u;
        mass[k] = 0.0;
        massSquared[k] = 0.0;
        px[k] = 0.0;
        py[k] = 0.0;
        kinetic[k] = 0.0;
        massFraction[k] = 0.0;
        occupancyFraction[k] = 0.0;
    }
    for (int c = tid; c < numCells; c += stride) {
        totalCellMass[c] = 0.0;
        totalOccupancyWeight[c] = 0.0;
        liquidFractionProxy[c] = 0.0;
        gasFractionProxy[c] = 0.0;
    }
    if (tid == 0) *invalidTypeCounter = 0ull;
}

__global__ void deposit_species_cell_fields_0490h(
    std::uint64_t nParticles,
    const double* x,
    const double* y,
    const double* vx,
    const double* vy,
    const double* particleMass,
    const std::uint32_t* particleType,
    const unsigned char* role,
    unsigned char fluidRole,
    DeviceGridConfig0490h grid,
    int speciesCount,
    const std::uint32_t* speciesTypes,
    unsigned int* count,
    double* mass,
    double* massSquared,
    double* px,
    double* py,
    double* kinetic,
    unsigned long long* invalidTypeCounter) {
    const std::uint64_t i = static_cast<std::uint64_t>(blockIdx.x) * blockDim.x + threadIdx.x;
    if (i >= nParticles) return;
    if (role[i] != fluidRole) return;

    int speciesIndex = -1;
    const std::uint32_t type = particleType[i];
    for (int s = 0; s < speciesCount; ++s) {
        if (speciesTypes[s] == type) {
            speciesIndex = s;
            break;
        }
    }
    if (speciesIndex < 0) {
        atomicAdd(invalidTypeCounter, 1ull);
        return;
    }

    const int c = cell_index_0490h(x[i], y[i], grid);
    const int k = speciesIndex * grid.numCells + c;
    const double m = particleMass[i];
    atomicAdd(&count[k], 1u);
    atomic_add_double_0490h(&mass[k], m);
    // 0493o1: sum(m^2) is deposited in the same particle pass.
    atomic_add_double_0490h(&massSquared[k], m * m);
    atomic_add_double_0490h(&px[k], m * vx[i]);
    atomic_add_double_0490h(&py[k], m * vy[i]);
    atomic_add_double_0490h(
        &kinetic[k], 0.5 * m * (vx[i] * vx[i] + vy[i] * vy[i]));
}

__global__ void finalize_species_cell_fields_0490h(
    int numCells,
    int speciesCount,
    const double* referenceCellMass,
    const unsigned char* phaseFamily,
    const double* mass,
    double* totalCellMass,
    double* totalOccupancyWeight,
    double* massFraction,
    double* occupancyFraction,
    double* liquidFractionProxy,
    double* gasFractionProxy) {
    const int c = blockIdx.x * blockDim.x + threadIdx.x;
    if (c >= numCells) return;

    double totalMass = 0.0;
    double totalWeight = 0.0;
    for (int s = 0; s < speciesCount; ++s) {
        const int k = s * numCells + c;
        const double m = mass[k];
        totalMass += m;
        totalWeight += m / referenceCellMass[s];
    }
    totalCellMass[c] = totalMass;
    totalOccupancyWeight[c] = totalWeight;

    double liquid = 0.0;
    double gas = 0.0;
    for (int s = 0; s < speciesCount; ++s) {
        const int k = s * numCells + c;
        const double m = mass[k];
        const double mf = totalMass > 0.0 ? m / totalMass : 0.0;
        const double of = totalWeight > 0.0
            ? (m / referenceCellMass[s]) / totalWeight
            : 0.0;
        massFraction[k] = mf;
        occupancyFraction[k] = of;
        if (phaseFamily[s] == static_cast<unsigned char>(SpeciesPhaseFamily::Liquid)) {
            liquid += of;
        } else if (phaseFamily[s] == static_cast<unsigned char>(SpeciesPhaseFamily::Gas)) {
            gas += of;
        }
    }
    liquidFractionProxy[c] = liquid;
    gasFractionProxy[c] = gas;
}

bool periodic_x_0490h(const SimulationParams& params) {
    return params.bcLeft == "periodic" && params.bcRight == "periodic";
}

bool periodic_y_0490h(const SimulationParams& params) {
    return params.bcBottom == "periodic" && params.bcTop == "periodic";
}
#endif

} // namespace

struct CudaSpeciesCellWorkspace0490h::Impl {
    int cellCapacity = 0;
    int speciesCapacity = 0;
    int numCells = 0;
    int speciesCount = 0;
    std::uint64_t allocatedBytes = 0u;
    std::uint32_t* speciesTypes = nullptr;
    double* q6Strength = nullptr;
    double* referenceCellMass = nullptr;
    unsigned char* phaseFamily = nullptr;
    unsigned char* resamplingEnabled = nullptr;
    unsigned int* count = nullptr;
    double* mass = nullptr;
    // 0493o1: sum(m^2), species-major.
    double* massSquared = nullptr;
    double* px = nullptr;
    double* py = nullptr;
    double* kinetic = nullptr;
    double* totalCellMass = nullptr;
    double* totalOccupancyWeight = nullptr;
    double* massFraction = nullptr;
    double* occupancyFraction = nullptr;
    double* liquidFractionProxy = nullptr;
    double* gasFractionProxy = nullptr;
    unsigned long long* invalidTypeCounter = nullptr;
};

bool cuda_species_cell_fields_available_0490h() {
#if defined(MPCD_ENABLE_CUDA_PARTICLE_STATE) && defined(MPCD_ENABLE_CUDA_CELL_WORKSPACE)
    int count = 0;
    const cudaError_t err = cudaGetDeviceCount(&count);
    if (err != cudaSuccess) {
        cudaGetLastError();
        return false;
    }
    return count > 0;
#else
    return false;
#endif
}

CudaSpeciesCellWorkspace0490h::CudaSpeciesCellWorkspace0490h()
    : impl_(new Impl()) {}

CudaSpeciesCellWorkspace0490h::~CudaSpeciesCellWorkspace0490h() {
    release();
    delete impl_;
    impl_ = nullptr;
}

CudaSpeciesCellWorkspace0490h::CudaSpeciesCellWorkspace0490h(
    CudaSpeciesCellWorkspace0490h&& other) noexcept
    : impl_(other.impl_) {
    other.impl_ = new Impl();
}

CudaSpeciesCellWorkspace0490h& CudaSpeciesCellWorkspace0490h::operator=(
    CudaSpeciesCellWorkspace0490h&& other) noexcept {
    if (this != &other) {
        release();
        delete impl_;
        impl_ = other.impl_;
        other.impl_ = new Impl();
    }
    return *this;
}

void CudaSpeciesCellWorkspace0490h::release() {
#if defined(MPCD_ENABLE_CUDA_PARTICLE_STATE) && defined(MPCD_ENABLE_CUDA_CELL_WORKSPACE)
    if (impl_ != nullptr) {
        cuda_free_0490h(impl_->speciesTypes);
        cuda_free_0490h(impl_->q6Strength);
        cuda_free_0490h(impl_->referenceCellMass);
        cuda_free_0490h(impl_->phaseFamily);
        cuda_free_0490h(impl_->resamplingEnabled);
        cuda_free_0490h(impl_->count);
        cuda_free_0490h(impl_->mass);
        cuda_free_0490h(impl_->massSquared);
        cuda_free_0490h(impl_->px);
        cuda_free_0490h(impl_->py);
        cuda_free_0490h(impl_->kinetic);
        cuda_free_0490h(impl_->totalCellMass);
        cuda_free_0490h(impl_->totalOccupancyWeight);
        cuda_free_0490h(impl_->massFraction);
        cuda_free_0490h(impl_->occupancyFraction);
        cuda_free_0490h(impl_->liquidFractionProxy);
        cuda_free_0490h(impl_->gasFractionProxy);
        cuda_free_0490h(impl_->invalidTypeCounter);
    }
#endif
    if (impl_ != nullptr) *impl_ = Impl{};
}

void CudaSpeciesCellWorkspace0490h::ensure_capacity(
    int numCells,
    int speciesCount,
    CudaSpeciesCellDepositDiagnostics0490h* diag) {
#if !defined(MPCD_ENABLE_CUDA_PARTICLE_STATE) || !defined(MPCD_ENABLE_CUDA_CELL_WORKSPACE)
    (void)numCells; (void)speciesCount; (void)diag;
    throw std::runtime_error(
        "CudaSpeciesCellWorkspace0490h::ensure_capacity requires CUDA particle state and cell workspace");
#else
    if (impl_ == nullptr) throw std::runtime_error("0490h species workspace has null impl");
    if (numCells <= 0 || speciesCount <= 0) {
        throw std::runtime_error("0490h species workspace requires positive dimensions");
    }
    const Clock::time_point tTotal0 = Clock::now();
    const bool reusable = impl_->cellCapacity >= numCells &&
                          impl_->speciesCapacity >= speciesCount &&
                          impl_->count != nullptr && impl_->massSquared != nullptr;
    if (reusable) {
        impl_->numCells = numCells;
        impl_->speciesCount = speciesCount;
        if (diag != nullptr) {
            diag->numCells = numCells;
            diag->speciesCount = speciesCount;
            diag->allocatedBytes = impl_->allocatedBytes;
            diag->reusedAllocation = 1;
            diag->totalSeconds += seconds_since_0490h(tTotal0);
        }
        return;
    }

    release();
    const Clock::time_point t0 = Clock::now();
    const std::size_t nc = static_cast<std::size_t>(numCells);
    const std::size_t ns = static_cast<std::size_t>(speciesCount);
    const std::size_t dense = nc * ns;

    MPCD_CUDA_0490H_CHECK(cudaMalloc(&impl_->speciesTypes, ns * sizeof(std::uint32_t)));
    MPCD_CUDA_0490H_CHECK(cudaMalloc(&impl_->q6Strength, ns * sizeof(double)));
    MPCD_CUDA_0490H_CHECK(cudaMalloc(&impl_->referenceCellMass, ns * sizeof(double)));
    MPCD_CUDA_0490H_CHECK(cudaMalloc(&impl_->phaseFamily, ns * sizeof(unsigned char)));
    MPCD_CUDA_0490H_CHECK(cudaMalloc(&impl_->resamplingEnabled, ns * sizeof(unsigned char)));
    MPCD_CUDA_0490H_CHECK(cudaMalloc(&impl_->count, dense * sizeof(unsigned int)));
    MPCD_CUDA_0490H_CHECK(cudaMalloc(&impl_->mass, dense * sizeof(double)));
    MPCD_CUDA_0490H_CHECK(cudaMalloc(&impl_->massSquared, dense * sizeof(double)));
    MPCD_CUDA_0490H_CHECK(cudaMalloc(&impl_->px, dense * sizeof(double)));
    MPCD_CUDA_0490H_CHECK(cudaMalloc(&impl_->py, dense * sizeof(double)));
    MPCD_CUDA_0490H_CHECK(cudaMalloc(&impl_->kinetic, dense * sizeof(double)));
    MPCD_CUDA_0490H_CHECK(cudaMalloc(&impl_->totalCellMass, nc * sizeof(double)));
    MPCD_CUDA_0490H_CHECK(cudaMalloc(&impl_->totalOccupancyWeight, nc * sizeof(double)));
    MPCD_CUDA_0490H_CHECK(cudaMalloc(&impl_->massFraction, dense * sizeof(double)));
    MPCD_CUDA_0490H_CHECK(cudaMalloc(&impl_->occupancyFraction, dense * sizeof(double)));
    MPCD_CUDA_0490H_CHECK(cudaMalloc(&impl_->liquidFractionProxy, nc * sizeof(double)));
    MPCD_CUDA_0490H_CHECK(cudaMalloc(&impl_->gasFractionProxy, nc * sizeof(double)));
    MPCD_CUDA_0490H_CHECK(cudaMalloc(&impl_->invalidTypeCounter, sizeof(unsigned long long)));

    impl_->cellCapacity = numCells;
    impl_->speciesCapacity = speciesCount;
    impl_->numCells = numCells;
    impl_->speciesCount = speciesCount;
    impl_->allocatedBytes =
        ns * (sizeof(std::uint32_t) + 2u * sizeof(double) + 2u * sizeof(unsigned char)) +
        dense * (sizeof(unsigned int) + 7u * sizeof(double)) +
        nc * 4u * sizeof(double) + sizeof(unsigned long long);

    if (diag != nullptr) {
        diag->numCells = numCells;
        diag->speciesCount = speciesCount;
        diag->allocatedBytes = impl_->allocatedBytes;
        diag->allocationCalls += 1u;
        diag->reusedAllocation = 0;
        diag->allocateSeconds += seconds_since_0490h(t0);
        diag->totalSeconds += seconds_since_0490h(tTotal0);
    }
#endif
}

CudaSpeciesCellDeviceView0490h CudaSpeciesCellWorkspace0490h::device_view() {
    return static_cast<const CudaSpeciesCellWorkspace0490h*>(this)->device_view();
}

CudaSpeciesCellDeviceView0490h CudaSpeciesCellWorkspace0490h::device_view() const {
    CudaSpeciesCellDeviceView0490h v{};
    if (impl_ == nullptr) return v;
    v.numCells = impl_->numCells;
    v.speciesCount = impl_->speciesCount;
    v.speciesTypes = impl_->speciesTypes;
    v.q6Strength = impl_->q6Strength;
    v.referenceCellMass = impl_->referenceCellMass;
    v.phaseFamily = impl_->phaseFamily;
    v.resamplingEnabled = impl_->resamplingEnabled;
    v.count = impl_->count;
    v.mass = impl_->mass;
    v.massSquared = impl_->massSquared;
    v.px = impl_->px;
    v.py = impl_->py;
    v.kinetic = impl_->kinetic;
    v.totalCellMass = impl_->totalCellMass;
    v.totalOccupancyWeight = impl_->totalOccupancyWeight;
    v.massFraction = impl_->massFraction;
    v.occupancyFraction = impl_->occupancyFraction;
    v.liquidFractionProxy = impl_->liquidFractionProxy;
    v.gasFractionProxy = impl_->gasFractionProxy;
    v.invalidTypeCounter = impl_->invalidTypeCounter;
    return v;
}

int CudaSpeciesCellWorkspace0490h::cell_capacity() const {
    return impl_ ? impl_->cellCapacity : 0;
}

int CudaSpeciesCellWorkspace0490h::species_capacity() const {
    return impl_ ? impl_->speciesCapacity : 0;
}

std::uint64_t CudaSpeciesCellWorkspace0490h::allocated_bytes() const {
    return impl_ ? impl_->allocatedBytes : 0u;
}

void cuda_deposit_species_cell_fields_resident_0490h(
    const CudaParticleDeviceView& particles,
    const CellGrid& grid,
    const SimulationParams& params,
    const std::vector<SpeciesDefinition>& definitions,
    CudaSpeciesCellWorkspace0490h& workspace,
    CudaSpeciesCellDepositDiagnostics0490h* diagnostics,
    int threadsPerBlock) {
#if !defined(MPCD_ENABLE_CUDA_PARTICLE_STATE) || !defined(MPCD_ENABLE_CUDA_CELL_WORKSPACE)
    (void)particles; (void)grid; (void)params; (void)definitions;
    (void)workspace; (void)diagnostics; (void)threadsPerBlock;
    throw std::runtime_error("0490h resident CUDA species deposit is unavailable in this build");
#else
    validate_species_definitions(definitions, "0490h resident CUDA species deposit");
    if (definitions.empty()) {
        throw std::runtime_error("0490h resident CUDA species deposit requires species");
    }
    if (grid.Nx <= 0 || grid.Ny <= 0 || grid.numCells != grid.Nx * grid.Ny ||
        !(grid.dx > 0.0) || !(grid.dy > 0.0)) {
        throw std::runtime_error("0490h resident CUDA species deposit received invalid grid");
    }
    if (particles.x == nullptr || particles.y == nullptr || particles.vx == nullptr ||
        particles.vy == nullptr || particles.mass == nullptr || particles.type == nullptr ||
        particles.role == nullptr) {
        throw std::runtime_error("0490h resident CUDA species deposit received incomplete particle view");
    }
    if (threadsPerBlock <= 0) threadsPerBlock = 256;

    CudaSpeciesCellDepositDiagnostics0490h local{};
    CudaSpeciesCellDepositDiagnostics0490h& diag = diagnostics ? *diagnostics : local;
    const Clock::time_point tTotal0 = Clock::now();
    const int speciesCount = static_cast<int>(definitions.size());
    if (static_cast<std::size_t>(speciesCount) != definitions.size()) {
        throw std::runtime_error("0490h species count exceeds int range");
    }
    workspace.ensure_capacity(grid.numCells, speciesCount, &diag);
    CudaSpeciesCellDeviceView0490h out = workspace.device_view();

    std::vector<std::uint32_t> hTypes(definitions.size());
    std::vector<double> hQ6Strength(definitions.size());
    std::vector<double> hRefMass(definitions.size());
    std::vector<unsigned char> hPhase(definitions.size());
    std::vector<unsigned char> hResamplingEnabled(definitions.size());
    for (std::size_t s = 0; s < definitions.size(); ++s) {
        hTypes[s] = definitions[s].type;
        hQ6Strength[s] = definitions[s].q6StrengthDeclared;
        hRefMass[s] = definitions[s].referenceCellMassDeclared;
        hPhase[s] = static_cast<unsigned char>(definitions[s].phaseFamily);
        hResamplingEnabled[s] = definitions[s].resamplingEnable ? 1u : 0u;
    }

    const Clock::time_point tMeta = Clock::now();
    MPCD_CUDA_0490H_CHECK(cudaMemcpy(out.speciesTypes, hTypes.data(),
                                    hTypes.size() * sizeof(std::uint32_t),
                                    cudaMemcpyHostToDevice));
    MPCD_CUDA_0490H_CHECK(cudaMemcpy(out.q6Strength, hQ6Strength.data(),
                                    hQ6Strength.size() * sizeof(double),
                                    cudaMemcpyHostToDevice));
    MPCD_CUDA_0490H_CHECK(cudaMemcpy(out.referenceCellMass, hRefMass.data(),
                                    hRefMass.size() * sizeof(double),
                                    cudaMemcpyHostToDevice));
    MPCD_CUDA_0490H_CHECK(cudaMemcpy(out.phaseFamily, hPhase.data(),
                                    hPhase.size() * sizeof(unsigned char),
                                    cudaMemcpyHostToDevice));
    MPCD_CUDA_0490H_CHECK(cudaMemcpy(out.resamplingEnabled, hResamplingEnabled.data(),
                                    hResamplingEnabled.size() * sizeof(unsigned char),
                                    cudaMemcpyHostToDevice));
    diag.metadataUploadBytes +=
        hTypes.size() * sizeof(std::uint32_t) +
        hQ6Strength.size() * sizeof(double) +
        hRefMass.size() * sizeof(double) +
        hPhase.size() * sizeof(unsigned char) +
        hResamplingEnabled.size() * sizeof(unsigned char);
    diag.metadataUploadSeconds += seconds_since_0490h(tMeta);

    const int denseSize = speciesCount * grid.numCells;
    const int resetWork = std::max(denseSize, grid.numCells);
    const int resetBlocks = std::max(1, (resetWork + threadsPerBlock - 1) / threadsPerBlock);
    const Clock::time_point tReset = Clock::now();
    reset_species_cell_fields_0490h<<<resetBlocks, threadsPerBlock>>>(
        denseSize, grid.numCells, out.count, out.mass, out.massSquared, out.px, out.py, out.kinetic,
        out.totalCellMass, out.totalOccupancyWeight, out.massFraction,
        out.occupancyFraction, out.liquidFractionProxy, out.gasFractionProxy,
        out.invalidTypeCounter);
    MPCD_CUDA_0490H_CHECK(cudaGetLastError());
    MPCD_CUDA_0490H_CHECK(cudaDeviceSynchronize());
    diag.resetSeconds += seconds_since_0490h(tReset);

    const std::uint64_t nParticles = particles.nActiveFluid > 0u
        ? particles.nActiveFluid
        : particles.n;
    diag.particlesScanned = nParticles;
    diag.numCells = grid.numCells;
    diag.speciesCount = speciesCount;
    if (nParticles > 0u) {
        const std::uint64_t blocks64 =
            (nParticles + static_cast<std::uint64_t>(threadsPerBlock) - 1u) /
            static_cast<std::uint64_t>(threadsPerBlock);
        if (blocks64 > static_cast<std::uint64_t>(std::numeric_limits<int>::max())) {
            throw std::runtime_error("0490h particle block count exceeds int range");
        }
        DeviceGridConfig0490h cfg{};
        cfg.nx = grid.Nx;
        cfg.ny = grid.Ny;
        cfg.numCells = grid.numCells;
        cfg.lx = grid.Lx;
        cfg.ly = grid.Ly;
        cfg.dx = grid.dx;
        cfg.dy = grid.dy;
        cfg.periodicX = periodic_x_0490h(params) ? 1 : 0;
        cfg.periodicY = periodic_y_0490h(params) ? 1 : 0;

        const Clock::time_point tDeposit = Clock::now();
        deposit_species_cell_fields_0490h<<<static_cast<int>(blocks64), threadsPerBlock>>>(
            nParticles, particles.x, particles.y, particles.vx, particles.vy,
            particles.mass, particles.type, particles.role,
            static_cast<unsigned char>(kParticleRoleFluid), cfg, speciesCount,
            out.speciesTypes, out.count, out.mass, out.massSquared, out.px, out.py, out.kinetic,
            out.invalidTypeCounter);
        MPCD_CUDA_0490H_CHECK(cudaGetLastError());
        MPCD_CUDA_0490H_CHECK(cudaDeviceSynchronize());
        diag.depositSeconds += seconds_since_0490h(tDeposit);
    }

    const int cellBlocks = std::max(1, (grid.numCells + threadsPerBlock - 1) / threadsPerBlock);
    const Clock::time_point tFinalize = Clock::now();
    finalize_species_cell_fields_0490h<<<cellBlocks, threadsPerBlock>>>(
        grid.numCells, speciesCount, out.referenceCellMass, out.phaseFamily,
        out.mass, out.totalCellMass, out.totalOccupancyWeight, out.massFraction,
        out.occupancyFraction, out.liquidFractionProxy, out.gasFractionProxy);
    MPCD_CUDA_0490H_CHECK(cudaGetLastError());
    MPCD_CUDA_0490H_CHECK(cudaDeviceSynchronize());
    diag.finalizeSeconds += seconds_since_0490h(tFinalize);

    unsigned long long invalid = 0ull;
    MPCD_CUDA_0490H_CHECK(cudaMemcpy(&invalid, out.invalidTypeCounter,
                                    sizeof(invalid), cudaMemcpyDeviceToHost));
    diag.invalidTypeCount = static_cast<std::uint64_t>(invalid);
    diag.totalSeconds += seconds_since_0490h(tTotal0);
#endif
}

CudaSpeciesCellFields0490h cuda_download_species_cell_fields_0490h(
    const CudaSpeciesCellWorkspace0490h& workspace,
    const std::vector<SpeciesDefinition>& definitions,
    CudaSpeciesCellDepositDiagnostics0490h* diagnostics) {
#if !defined(MPCD_ENABLE_CUDA_PARTICLE_STATE) || !defined(MPCD_ENABLE_CUDA_CELL_WORKSPACE)
    (void)workspace; (void)definitions; (void)diagnostics;
    throw std::runtime_error("0490h CUDA species field download is unavailable in this build");
#else
    const CudaSpeciesCellDeviceView0490h view = workspace.device_view();
    if (view.numCells <= 0 || view.speciesCount <= 0 ||
        static_cast<std::size_t>(view.speciesCount) != definitions.size() ||
        view.count == nullptr || view.mass == nullptr || view.px == nullptr ||
        view.py == nullptr || view.kinetic == nullptr) {
        throw std::runtime_error("0490h CUDA species field download received incompatible workspace");
    }
    const Clock::time_point t0 = Clock::now();
    const std::size_t nc = static_cast<std::size_t>(view.numCells);
    const std::size_t dense = nc * definitions.size();
    CudaSpeciesCellFields0490h out{};
    out.numCells = view.numCells;
    out.speciesTypes.reserve(definitions.size());
    out.q6Strength.reserve(definitions.size());
    out.resamplingEnabled.reserve(definitions.size());
    for (const SpeciesDefinition& d : definitions) {
        out.speciesTypes.push_back(d.type);
        out.q6Strength.push_back(d.q6StrengthDeclared);
        out.resamplingEnabled.push_back(d.resamplingEnable ? 1u : 0u);
    }
    out.count.resize(dense);
    out.mass.resize(dense);
    out.px.resize(dense);
    out.py.resize(dense);
    out.kinetic.resize(dense);
    out.totalCellMass.resize(nc);
    out.totalOccupancyWeight.resize(nc);
    out.massFraction.resize(dense);
    out.occupancyFraction.resize(dense);
    out.liquidFractionProxy.resize(nc);
    out.gasFractionProxy.resize(nc);

    MPCD_CUDA_0490H_CHECK(cudaMemcpy(out.count.data(), view.count,
                                    dense * sizeof(unsigned int), cudaMemcpyDeviceToHost));
    MPCD_CUDA_0490H_CHECK(cudaMemcpy(out.mass.data(), view.mass,
                                    dense * sizeof(double), cudaMemcpyDeviceToHost));
    MPCD_CUDA_0490H_CHECK(cudaMemcpy(out.px.data(), view.px,
                                    dense * sizeof(double), cudaMemcpyDeviceToHost));
    MPCD_CUDA_0490H_CHECK(cudaMemcpy(out.py.data(), view.py,
                                    dense * sizeof(double), cudaMemcpyDeviceToHost));
    MPCD_CUDA_0490H_CHECK(cudaMemcpy(out.kinetic.data(), view.kinetic,
                                    dense * sizeof(double), cudaMemcpyDeviceToHost));
    MPCD_CUDA_0490H_CHECK(cudaMemcpy(out.totalCellMass.data(), view.totalCellMass,
                                    nc * sizeof(double), cudaMemcpyDeviceToHost));
    MPCD_CUDA_0490H_CHECK(cudaMemcpy(out.totalOccupancyWeight.data(), view.totalOccupancyWeight,
                                    nc * sizeof(double), cudaMemcpyDeviceToHost));
    MPCD_CUDA_0490H_CHECK(cudaMemcpy(out.massFraction.data(), view.massFraction,
                                    dense * sizeof(double), cudaMemcpyDeviceToHost));
    MPCD_CUDA_0490H_CHECK(cudaMemcpy(out.occupancyFraction.data(), view.occupancyFraction,
                                    dense * sizeof(double), cudaMemcpyDeviceToHost));
    MPCD_CUDA_0490H_CHECK(cudaMemcpy(out.liquidFractionProxy.data(), view.liquidFractionProxy,
                                    nc * sizeof(double), cudaMemcpyDeviceToHost));
    MPCD_CUDA_0490H_CHECK(cudaMemcpy(out.gasFractionProxy.data(), view.gasFractionProxy,
                                    nc * sizeof(double), cudaMemcpyDeviceToHost));
    unsigned long long invalid = 0ull;
    MPCD_CUDA_0490H_CHECK(cudaMemcpy(&invalid, view.invalidTypeCounter,
                                    sizeof(invalid), cudaMemcpyDeviceToHost));
    out.invalidTypeCount = static_cast<std::uint64_t>(invalid);
    if (diagnostics != nullptr) diagnostics->downloadSeconds += seconds_since_0490h(t0);
    return out;
#endif
}

SpeciesCellCudaEquivalence0490h compare_species_cell_cuda_cpu_0490h(
    const CudaParticleDeviceView& particles,
    const ParticleState& cpuReferenceState,
    const std::vector<SpeciesDefinition>& definitions,
    const CellGrid& grid,
    const SimulationParams& params,
    bool requireRegisteredTypes,
    double tolerance,
    CudaSpeciesCellWorkspace0490h& workspace,
    int usedSharedResidentState,
    int threadsPerBlock) {
    if (!(tolerance >= 0.0) || !std::isfinite(tolerance)) {
        throw std::runtime_error("0490h comparison tolerance must be finite and non-negative");
    }
    const SpeciesCellFields0490b cpu = deposit_species_cell_fields_0490b(
        cpuReferenceState, definitions, grid, params, requireRegisteredTypes);

    SpeciesCellCudaEquivalence0490h eq{};
    eq.usedSharedResidentState = usedSharedResidentState ? 1 : 0;
    cuda_deposit_species_cell_fields_resident_0490h(
        particles, grid, params, definitions, workspace, &eq.cuda, threadsPerBlock);
    const CudaSpeciesCellFields0490h gpu =
        cuda_download_species_cell_fields_0490h(workspace, definitions, &eq.cuda);
    eq.reusedAllocation = eq.cuda.reusedAllocation;
    eq.particlesScanned = eq.cuda.particlesScanned;
    eq.invalidTypeCount = gpu.invalidTypeCount;

    if (gpu.numCells != cpu.numCells || gpu.speciesTypes != cpu.speciesTypes ||
        gpu.count.size() != cpu.count.size() ||
        gpu.kinetic.size() != cpu.kinetic.size()) {
        return eq;
    }

    for (std::size_t k = 0; k < cpu.count.size(); ++k) {
        if (gpu.count[k] != cpu.count[k]) ++eq.countMismatches;
        eq.maxAbsMassError = max_abs_0490h(eq.maxAbsMassError, gpu.mass[k] - cpu.mass[k]);
        eq.maxAbsPxError = max_abs_0490h(eq.maxAbsPxError, gpu.px[k] - cpu.px[k]);
        eq.maxAbsPyError = max_abs_0490h(eq.maxAbsPyError, gpu.py[k] - cpu.py[k]);
        eq.maxAbsKineticError = max_abs_0490h(
            eq.maxAbsKineticError, gpu.kinetic[k] - cpu.kinetic[k]);
        const std::size_t c = k % static_cast<std::size_t>(cpu.numCells);
        const double expectedMassFraction = cpu.totalCellMass[c] > 0.0
            ? cpu.mass[k] / cpu.totalCellMass[c]
            : 0.0;
        const double expectedOccupancyFraction = cpu.totalOccupancyWeight[c] > 0.0
            ? (cpu.mass[k] /
               definitions[k / static_cast<std::size_t>(cpu.numCells)].referenceCellMassDeclared) /
              cpu.totalOccupancyWeight[c]
            : 0.0;
        eq.maxAbsMassFractionError = max_abs_0490h(
            eq.maxAbsMassFractionError, gpu.massFraction[k] - expectedMassFraction);
        eq.maxAbsOccupancyFractionError = max_abs_0490h(
            eq.maxAbsOccupancyFractionError,
            gpu.occupancyFraction[k] - expectedOccupancyFraction);
    }
    for (std::size_t c = 0; c < cpu.totalCellMass.size(); ++c) {
        eq.maxAbsTotalMassError = max_abs_0490h(
            eq.maxAbsTotalMassError, gpu.totalCellMass[c] - cpu.totalCellMass[c]);
        eq.maxAbsTotalOccupancyWeightError = max_abs_0490h(
            eq.maxAbsTotalOccupancyWeightError,
            gpu.totalOccupancyWeight[c] - cpu.totalOccupancyWeight[c]);
        eq.maxAbsLiquidFractionError = max_abs_0490h(
            eq.maxAbsLiquidFractionError,
            gpu.liquidFractionProxy[c] - cpu.liquidFractionProxy[c]);
        eq.maxAbsGasFractionError = max_abs_0490h(
            eq.maxAbsGasFractionError,
            gpu.gasFractionProxy[c] - cpu.gasFractionProxy[c]);
    }

    const double maxError = std::max({
        eq.maxAbsMassError,
        eq.maxAbsPxError,
        eq.maxAbsPyError,
        eq.maxAbsKineticError,
        eq.maxAbsTotalMassError,
        eq.maxAbsTotalOccupancyWeightError,
        eq.maxAbsMassFractionError,
        eq.maxAbsOccupancyFractionError,
        eq.maxAbsLiquidFractionError,
        eq.maxAbsGasFractionError});
    eq.pass = (eq.countMismatches == 0u && eq.invalidTypeCount == 0u &&
               maxError <= tolerance) ? 1 : 0;
    return eq;
}

SpeciesCellCudaEquivalenceWriter0490h::SpeciesCellCudaEquivalenceWriter0490h(
    const std::string& filepath)
    : out_(filepath) {
    if (!out_) {
        throw std::runtime_error("Cannot open 0490h species CUDA equivalence file: " + filepath);
    }
    out_ << "step,time,pass,usedSharedResidentState,reusedAllocation,particlesScanned,"
            "invalidTypeCount,countMismatches,maxAbsMassError,maxAbsPxError,maxAbsPyError,maxAbsKineticError,"
            "maxAbsTotalMassError,maxAbsTotalOccupancyWeightError,maxAbsMassFractionError,"
            "maxAbsOccupancyFractionError,maxAbsLiquidFractionError,maxAbsGasFractionError,"
            "numCells,speciesCount,allocatedBytes,allocationCalls,metadataUploadBytes,"
            "allocateSeconds,resetSeconds,metadataUploadSeconds,depositSeconds,"
            "finalizeSeconds,downloadSeconds,totalSeconds\n";
}

SpeciesCellCudaEquivalence0490h SpeciesCellCudaEquivalenceWriter0490h::append(
    const CudaParticleDeviceView& particles,
    const ParticleState& cpuReferenceState,
    const std::vector<SpeciesDefinition>& definitions,
    const CellGrid& grid,
    const SimulationParams& params,
    bool requireRegisteredTypes,
    double tolerance,
    CudaSpeciesCellWorkspace0490h& workspace,
    std::uint64_t step,
    double time,
    int usedSharedResidentState,
    int threadsPerBlock) {
    const SpeciesCellCudaEquivalence0490h eq = compare_species_cell_cuda_cpu_0490h(
        particles, cpuReferenceState, definitions, grid, params,
        requireRegisteredTypes, tolerance, workspace,
        usedSharedResidentState, threadsPerBlock);
    out_ << std::setprecision(17)
         << step << ',' << time << ',' << eq.pass << ','
         << eq.usedSharedResidentState << ',' << eq.reusedAllocation << ','
         << eq.particlesScanned << ',' << eq.invalidTypeCount << ','
         << eq.countMismatches << ',' << eq.maxAbsMassError << ','
         << eq.maxAbsPxError << ',' << eq.maxAbsPyError << ','
         << eq.maxAbsKineticError << ',' << eq.maxAbsTotalMassError << ','
         << eq.maxAbsTotalOccupancyWeightError << ','
         << eq.maxAbsMassFractionError << ','
         << eq.maxAbsOccupancyFractionError << ','
         << eq.maxAbsLiquidFractionError << ','
         << eq.maxAbsGasFractionError << ','
         << eq.cuda.numCells << ',' << eq.cuda.speciesCount << ','
         << eq.cuda.allocatedBytes << ',' << eq.cuda.allocationCalls << ','
         << eq.cuda.metadataUploadBytes << ',' << eq.cuda.allocateSeconds << ','
         << eq.cuda.resetSeconds << ',' << eq.cuda.metadataUploadSeconds << ','
         << eq.cuda.depositSeconds << ',' << eq.cuda.finalizeSeconds << ','
         << eq.cuda.downloadSeconds << ',' << eq.cuda.totalSeconds << '\n';
    out_.flush();
    return eq;
}

} // namespace mpcd
