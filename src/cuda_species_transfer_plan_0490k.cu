#include "cuda_species_transfer_plan_0490k.h"

#include "cuda_shared_particle_state_0251.h"
#include "species_registry.h"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <limits>
#include <stdexcept>
#include <string>
#include <type_traits>
#include <vector>

#if defined(MPCD_ENABLE_CUDA_PARTICLE_STATE) && defined(MPCD_ENABLE_CUDA_CELL_WORKSPACE)
#include <cuda_runtime.h>
#endif

namespace mpcd {
namespace {

using Clock0490k = std::chrono::steady_clock;

double seconds_since_0490k(const Clock0490k::time_point& t0) {
    return std::chrono::duration<double>(Clock0490k::now() - t0).count();
}

#if defined(MPCD_ENABLE_CUDA_PARTICLE_STATE) && defined(MPCD_ENABLE_CUDA_CELL_WORKSPACE)
#define MPCD_CUDA_0490K_CHECK(call) do { \
    const cudaError_t err__ = (call); \
    if (err__ != cudaSuccess) { \
        throw std::runtime_error(std::string("CUDA error in ") + #call + ": " + \
                                 cudaGetErrorString(err__)); \
    } \
} while (0)

template <typename T>
void cuda_free_0490k(T*& ptr) {
    if (ptr != nullptr) {
        cudaFree(ptr);
        ptr = nullptr;
    }
}

__device__ double cell_distance_0490k(
    int a,
    int b,
    int nx,
    int ny,
    int periodicX,
    int periodicY) {
    if (a < 0 || b < 0 || nx <= 0 || ny <= 0) return 0.0;
    const int ax = a % nx;
    const int ay = a / nx;
    const int bx = b % nx;
    const int by = b / nx;
    int dx = ax > bx ? ax - bx : bx - ax;
    int dy = ay > by ? ay - by : by - ay;
    if (periodicX) dx = dx < (nx - dx) ? dx : (nx - dx);
    if (periodicY) dy = dy < (ny - dy) ? dy : (ny - dy);
    return sqrt(static_cast<double>(dx * dx + dy * dy));
}

// Correctness-first deterministic native GPU planner. One CUDA thread follows
// exactly the 0490g reference ordering: receiver cell, registry species, then
// nearest compatible donor with donor-cell tie break.
__global__ void build_species_transfer_plan_serial_0490k(
    int numCells,
    int speciesCount,
    int nx,
    int ny,
    int periodicX,
    int periodicY,
    double targetCellMass,
    double poorThreshold,
    double richThreshold,
    const unsigned char* wetCell,
    const std::uint32_t* speciesTypes,
    const double* speciesMass,
    const double* totalCellMass,
    double* receiverRemaining,
    double* donorRemaining,
    double* receiverSpeciesRemaining,
    double* donorSpeciesRemaining,
    int maxPlanEntries,
    int* outDonor,
    int* outReceiver,
    std::uint32_t* outType,
    double* outMass,
    double* outDistance,
    double* outDonorRemainingAfter,
    double* outReceiverRemainingAfter,
    unsigned int* outCount,
    unsigned int* outOverflow,
    unsigned int* outReceiverCells,
    unsigned int* outDonorCells,
    double* outPlannedMass) {
    if (blockIdx.x != 0 || threadIdx.x != 0) return;

    constexpr double eps = 1.0e-14;
    unsigned int count = 0u;
    unsigned int overflow = 0u;
    unsigned int receiverCells = 0u;
    unsigned int donorCells = 0u;
    double plannedMass = 0.0;

    for (int c = 0; c < numCells; ++c) {
        const double total = totalCellMass[c];
        const bool wet = wetCell[c] != 0u;
        const bool receiver = wet && total < poorThreshold;
        const bool donor = wet && total > richThreshold;
        const double deficit = receiver && targetCellMass > total
            ? targetCellMass - total : 0.0;
        const double excess = donor && total > targetCellMass
            ? total - targetCellMass : 0.0;
        receiverRemaining[c] = deficit;
        donorRemaining[c] = excess;
        if (deficit > eps) ++receiverCells;
        if (excess > eps) ++donorCells;
        for (int s = 0; s < speciesCount; ++s) {
            const int k = s * numCells + c;
            const double ms = speciesMass[k];
            receiverSpeciesRemaining[k] =
                deficit > eps && total > eps && ms > eps ? deficit * ms / total : 0.0;
            donorSpeciesRemaining[k] =
                excess > eps && total > eps && ms > eps ? excess * ms / total : 0.0;
        }
    }

    for (int rc = 0; rc < numCells; ++rc) {
        if (receiverRemaining[rc] <= eps) continue;
        for (int s = 0; s < speciesCount; ++s) {
            const int rk = s * numCells + rc;
            while (receiverSpeciesRemaining[rk] > eps) {
                int bestDonor = -1;
                int bestCell = 2147483647;
                double bestDistance = 1.0e300;
                for (int dc = 0; dc < numCells; ++dc) {
                    const int dk = s * numCells + dc;
                    if (donorSpeciesRemaining[dk] <= eps) continue;
                    const double distance = cell_distance_0490k(
                        dc, rc, nx, ny, periodicX, periodicY);
                    if (distance < bestDistance ||
                        (distance == bestDistance && dc < bestCell)) {
                        bestDonor = dc;
                        bestCell = dc;
                        bestDistance = distance;
                    }
                }
                if (bestDonor < 0) break;
                const int dk = s * numCells + bestDonor;
                const double available = donorSpeciesRemaining[dk];
                const double wanted = receiverSpeciesRemaining[rk];
                const double transfer = available < wanted ? available : wanted;
                if (!(transfer > eps)) break;

                donorSpeciesRemaining[dk] -= transfer;
                receiverSpeciesRemaining[rk] -= transfer;
                donorRemaining[bestDonor] -= transfer;
                receiverRemaining[rc] -= transfer;

                if (static_cast<int>(count) < maxPlanEntries) {
                    outDonor[count] = bestDonor;
                    outReceiver[count] = rc;
                    outType[count] = speciesTypes[s];
                    outMass[count] = transfer;
                    outDistance[count] = bestDistance;
                    outDonorRemainingAfter[count] = donorRemaining[bestDonor];
                    outReceiverRemainingAfter[count] = receiverRemaining[rc];
                } else {
                    ++overflow;
                }
                ++count;
                plannedMass += transfer;
            }
        }
    }

    *outCount = count;
    *outOverflow = overflow;
    *outReceiverCells = receiverCells;
    *outDonorCells = donorCells;
    *outPlannedMass = plannedMass;
}

bool periodic_x_0490k(const SimulationParams& params) {
    return params.bcLeft == "periodic" && params.bcRight == "periodic";
}

bool periodic_y_0490k(const SimulationParams& params) {
    return params.bcBottom == "periodic" && params.bcTop == "periodic";
}
#endif

void append_csv_0490k(
    const SimulationParams& params,
    const CudaSpeciesTransferPlanDiagnostics0490k& d) {
    if (params.outputDir.empty() || params.speciesTransferCudaDiagnosticsFilename.empty()) return;
    const std::filesystem::path path =
        std::filesystem::path(params.outputDir) / params.speciesTransferCudaDiagnosticsFilename;
    std::filesystem::create_directories(path.parent_path());
    const bool writeHeader = !std::filesystem::exists(path) || std::filesystem::file_size(path) == 0u;
    std::ofstream out(path, std::ios::app);
    if (!out) throw std::runtime_error("0490k failed to open diagnostics CSV: " + path.string());
    if (writeHeader) {
        out << "step,handled,pass,accepted,particlesScanned,receiverCells,donorCells,"
               "cpuPlanEntries,gpuPlanEntries,planMismatch,typeMismatch,overflowCount,"
               "usedSharedResidentState,particleUploadSkipped,speciesWorkspaceReused,planWorkspaceReused,"
               "cpuPlannedMass,gpuPlannedMass,maxPlanMassError,maxPlanDistanceError,"
               "maxDonorRemainingError,maxReceiverRemainingError,"
               "firstDonorCell,firstReceiverCell,firstParticleType,lastDonorCell,lastReceiverCell,lastParticleType,"
               "allocatedBytes,allocationCalls,stateUploadSeconds,speciesDepositSeconds,metadataUploadSeconds,"
               "plannerKernelSeconds,compactDownloadSeconds,totalSeconds\n";
    }
    out << d.step << ',' << (d.handled ? 1 : 0) << ',' << (d.pass ? 1 : 0) << ','
        << (d.accepted ? 1 : 0) << ',' << d.particlesScanned << ',' << d.receiverCells << ','
        << d.donorCells << ',' << d.cpuPlanEntries << ',' << d.gpuPlanEntries << ','
        << d.planMismatch << ',' << d.typeMismatch << ',' << d.overflowCount << ','
        << d.usedSharedResidentState << ',' << d.particleUploadSkipped << ','
        << d.speciesWorkspaceReused << ',' << d.planWorkspaceReused << ','
        << std::setprecision(17)
        << d.cpuPlannedMass << ',' << d.gpuPlannedMass << ',' << d.maxPlanMassError << ','
        << d.maxPlanDistanceError << ',' << d.maxDonorRemainingError << ','
        << d.maxReceiverRemainingError << ',' << d.firstDonorCell << ','
        << d.firstReceiverCell << ',' << d.firstParticleType << ',' << d.lastDonorCell << ','
        << d.lastReceiverCell << ',' << d.lastParticleType << ',' << d.allocatedBytes << ','
        << d.allocationCalls << ',' << d.stateUploadSeconds << ',' << d.speciesDepositSeconds << ','
        << d.metadataUploadSeconds << ',' << d.plannerKernelSeconds << ','
        << d.compactDownloadSeconds << ',' << d.totalSeconds << '\n';
}

} // namespace

struct CudaSpeciesTransferPlanWorkspace0490k::Impl {
    int cellCapacity = 0;
    int speciesCapacity = 0;
    int planCapacity = 0;
    std::uint64_t allocatedBytes = 0u;
    unsigned char* wetCell = nullptr;
    double* receiverRemaining = nullptr;
    double* donorRemaining = nullptr;
    double* receiverSpeciesRemaining = nullptr;
    double* donorSpeciesRemaining = nullptr;
    int* outDonor = nullptr;
    int* outReceiver = nullptr;
    std::uint32_t* outType = nullptr;
    double* outMass = nullptr;
    double* outDistance = nullptr;
    double* outDonorRemainingAfter = nullptr;
    double* outReceiverRemainingAfter = nullptr;
    unsigned int* outCount = nullptr;
    unsigned int* outOverflow = nullptr;
    unsigned int* outReceiverCells = nullptr;
    unsigned int* outDonorCells = nullptr;
    double* outPlannedMass = nullptr;
};

CudaSpeciesTransferPlanWorkspace0490k::CudaSpeciesTransferPlanWorkspace0490k()
    : impl_(new Impl()) {}

CudaSpeciesTransferPlanWorkspace0490k::~CudaSpeciesTransferPlanWorkspace0490k() {
    release();
    delete impl_;
    impl_ = nullptr;
}

CudaSpeciesTransferPlanWorkspace0490k::CudaSpeciesTransferPlanWorkspace0490k(
    CudaSpeciesTransferPlanWorkspace0490k&& other) noexcept
    : impl_(other.impl_) {
    other.impl_ = new Impl();
}

CudaSpeciesTransferPlanWorkspace0490k& CudaSpeciesTransferPlanWorkspace0490k::operator=(
    CudaSpeciesTransferPlanWorkspace0490k&& other) noexcept {
    if (this != &other) {
        release();
        delete impl_;
        impl_ = other.impl_;
        other.impl_ = new Impl();
    }
    return *this;
}

void CudaSpeciesTransferPlanWorkspace0490k::release() {
#if defined(MPCD_ENABLE_CUDA_PARTICLE_STATE) && defined(MPCD_ENABLE_CUDA_CELL_WORKSPACE)
    if (impl_ != nullptr) {
        cuda_free_0490k(impl_->wetCell);
        cuda_free_0490k(impl_->receiverRemaining);
        cuda_free_0490k(impl_->donorRemaining);
        cuda_free_0490k(impl_->receiverSpeciesRemaining);
        cuda_free_0490k(impl_->donorSpeciesRemaining);
        cuda_free_0490k(impl_->outDonor);
        cuda_free_0490k(impl_->outReceiver);
        cuda_free_0490k(impl_->outType);
        cuda_free_0490k(impl_->outMass);
        cuda_free_0490k(impl_->outDistance);
        cuda_free_0490k(impl_->outDonorRemainingAfter);
        cuda_free_0490k(impl_->outReceiverRemainingAfter);
        cuda_free_0490k(impl_->outCount);
        cuda_free_0490k(impl_->outOverflow);
        cuda_free_0490k(impl_->outReceiverCells);
        cuda_free_0490k(impl_->outDonorCells);
        cuda_free_0490k(impl_->outPlannedMass);
    }
#endif
    if (impl_ != nullptr) *impl_ = Impl{};
}

void CudaSpeciesTransferPlanWorkspace0490k::ensure_capacity(
    int numCells,
    int speciesCount,
    int maxPlanEntries,
    CudaSpeciesTransferPlanDiagnostics0490k* diagnostics) {
#if !defined(MPCD_ENABLE_CUDA_PARTICLE_STATE) || !defined(MPCD_ENABLE_CUDA_CELL_WORKSPACE)
    (void)numCells; (void)speciesCount; (void)maxPlanEntries; (void)diagnostics;
    throw std::runtime_error("0490k CUDA workspace requires CUDA particle/cell support");
#else
    if (impl_ == nullptr) throw std::runtime_error("0490k workspace has null impl");
    if (numCells <= 0 || speciesCount <= 0 || maxPlanEntries <= 0) {
        throw std::runtime_error("0490k workspace requires positive capacities");
    }
    const bool reuse = impl_->cellCapacity >= numCells &&
                       impl_->speciesCapacity >= speciesCount &&
                       impl_->planCapacity >= maxPlanEntries;
    if (diagnostics) diagnostics->planWorkspaceReused = reuse ? 1 : 0;
    if (reuse) {
        if (diagnostics) diagnostics->allocatedBytes = impl_->allocatedBytes;
        return;
    }

    release();
    const std::size_t nc = static_cast<std::size_t>(numCells);
    const std::size_t dense = nc * static_cast<std::size_t>(speciesCount);
    const std::size_t np = static_cast<std::size_t>(maxPlanEntries);
    std::uint64_t bytes = 0u;
    auto alloc = [&](auto*& ptr, std::size_t count) {
        using T = std::remove_pointer_t<std::remove_reference_t<decltype(ptr)>>;
        MPCD_CUDA_0490K_CHECK(cudaMalloc(reinterpret_cast<void**>(&ptr), count * sizeof(T)));
        bytes += static_cast<std::uint64_t>(count * sizeof(T));
    };
    alloc(impl_->wetCell, nc);
    alloc(impl_->receiverRemaining, nc);
    alloc(impl_->donorRemaining, nc);
    alloc(impl_->receiverSpeciesRemaining, dense);
    alloc(impl_->donorSpeciesRemaining, dense);
    alloc(impl_->outDonor, np);
    alloc(impl_->outReceiver, np);
    alloc(impl_->outType, np);
    alloc(impl_->outMass, np);
    alloc(impl_->outDistance, np);
    alloc(impl_->outDonorRemainingAfter, np);
    alloc(impl_->outReceiverRemainingAfter, np);
    alloc(impl_->outCount, 1u);
    alloc(impl_->outOverflow, 1u);
    alloc(impl_->outReceiverCells, 1u);
    alloc(impl_->outDonorCells, 1u);
    alloc(impl_->outPlannedMass, 1u);
    impl_->cellCapacity = numCells;
    impl_->speciesCapacity = speciesCount;
    impl_->planCapacity = maxPlanEntries;
    impl_->allocatedBytes = bytes;
    if (diagnostics) {
        diagnostics->allocationCalls += 1u;
        diagnostics->allocatedBytes = bytes;
    }
#endif
}

int CudaSpeciesTransferPlanWorkspace0490k::cell_capacity() const {
    return impl_ ? impl_->cellCapacity : 0;
}

int CudaSpeciesTransferPlanWorkspace0490k::species_capacity() const {
    return impl_ ? impl_->speciesCapacity : 0;
}

int CudaSpeciesTransferPlanWorkspace0490k::plan_capacity() const {
    return impl_ ? impl_->planCapacity : 0;
}

std::uint64_t CudaSpeciesTransferPlanWorkspace0490k::allocated_bytes() const {
    return impl_ ? impl_->allocatedBytes : 0u;
}

bool cuda_species_transfer_plan_available_0490k() {
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

CudaSpeciesTransferPlanDiagnostics0490k try_apply_cuda_species_transfer_plan_0490k(
    const ParticleState& state,
    const SimulationParams& params,
    const CellGrid& grid,
    std::uint64_t step,
    CudaSpeciesCellWorkspace0490h& speciesWorkspace,
    CudaSpeciesTransferPlanWorkspace0490k& planWorkspace,
    WeightedRealFluidDepositWorkspace& resamplingWorkspace,
    WeightedResamplingDiagnostics& resamplingDiagnostics) {
    CudaSpeciesTransferPlanDiagnostics0490k d{};
    d.attempted = true;
    d.step = step;
    d.outputCsv = params.outputDir.empty() || params.speciesTransferCudaDiagnosticsFilename.empty()
        ? std::string{}
        : (std::filesystem::path(params.outputDir) /
           params.speciesTransferCudaDiagnosticsFilename).string();
    d.particlesScanned = state.NactiveFluid;
    d.cpuPlanEntries = static_cast<std::uint64_t>(resamplingWorkspace.transferPlan.size());
    d.cpuPlannedMass = resamplingDiagnostics.plannedTransferMass;
    const Clock0490k::time_point total0 = Clock0490k::now();

#if !defined(MPCD_ENABLE_CUDA_PARTICLE_STATE) || !defined(MPCD_ENABLE_CUDA_CELL_WORKSPACE)
    (void)grid; (void)speciesWorkspace; (void)planWorkspace;
    d.totalSeconds = seconds_since_0490k(total0);
    append_csv_0490k(params, d);
    return d;
#else
    if (!params.speciesResamplingTransferCudaEnable) {
        d.totalSeconds = seconds_since_0490k(total0);
        append_csv_0490k(params, d);
        return d;
    }
    if (!params.speciesResamplingTransferEnable || !params.speciesRegistryEnable ||
        !params.speciesRequireRegisteredTypes) {
        throw std::runtime_error(
            "0490k requires the validated 0490g species transfer configuration");
    }
    if (!resamplingDiagnostics.computed || !resamplingDiagnostics.transferPlanBuilt ||
        !resamplingDiagnostics.candidateListsBuilt) {
        throw std::runtime_error("0490k requires a complete 0490g CPU reference plan");
    }
    if (grid.numCells <= 0 ||
        static_cast<std::size_t>(grid.numCells) != resamplingWorkspace.wetCell.size()) {
        throw std::runtime_error("0490k invalid cell grid/workspace shape");
    }
    validate_species_definitions(params.speciesDefinitions, "0490k species registry");
    validate_state_species_registry(
        state, params.speciesDefinitions, true, "0490k particle state");
    if (!cuda_species_transfer_plan_available_0490k()) {
        throw std::runtime_error("0490k requested but no CUDA device is available");
    }

    CudaParticleState& particles = cuda_shared_particle_state_0251();
    CudaParticleStateDiagnostics upload{};
    if (cuda_shared_particle_state_0251_is_fresh()) {
        d.usedSharedResidentState = 1;
        d.particleUploadSkipped = 1;
    } else {
        particles.upload_all(state, &upload);
        d.stateUploadSeconds = upload.uploadSeconds;
        cuda_shared_particle_state_0251_mark_fresh("species_transfer_plan_0490k");
    }
    const CudaParticleDeviceView particleView = particles.device_view();
    if (particleView.n != state.Np || particleView.nActiveFluid != state.NactiveFluid) {
        throw std::runtime_error("0490k shared particle state shape mismatch");
    }

    CudaSpeciesCellDepositDiagnostics0490h deposit{};
    cuda_deposit_species_cell_fields_resident_0490h(
        particleView, grid, params, params.speciesDefinitions,
        speciesWorkspace, &deposit, params.speciesCellCudaThreadsPerBlock);
    d.speciesWorkspaceReused = deposit.reusedAllocation;
    d.speciesDepositSeconds = deposit.depositSeconds + deposit.finalizeSeconds;
    d.metadataUploadSeconds = deposit.metadataUploadSeconds;

    const int nc = grid.numCells;
    const int ns = static_cast<int>(params.speciesDefinitions.size());
    const int maxPlanEntries = std::max(8, 2 * nc * ns + 8);
    planWorkspace.ensure_capacity(nc, ns, maxPlanEntries, &d);
    d.allocatedBytes = planWorkspace.allocated_bytes();
    auto* impl = planWorkspace.impl_;
    const CudaSpeciesCellDeviceView0490h speciesView = speciesWorkspace.device_view();
    if (speciesView.numCells != nc || speciesView.speciesCount != ns ||
        speciesView.mass == nullptr || speciesView.totalCellMass == nullptr ||
        speciesView.speciesTypes == nullptr) {
        throw std::runtime_error("0490k species workspace device view mismatch");
    }

    const Clock0490k::time_point metadata0 = Clock0490k::now();
    MPCD_CUDA_0490K_CHECK(cudaMemcpy(
        impl->wetCell, resamplingWorkspace.wetCell.data(),
        static_cast<std::size_t>(nc) * sizeof(unsigned char), cudaMemcpyHostToDevice));
    d.metadataUploadSeconds += seconds_since_0490k(metadata0);
    MPCD_CUDA_0490K_CHECK(cudaMemset(impl->outCount, 0, sizeof(unsigned int)));
    MPCD_CUDA_0490K_CHECK(cudaMemset(impl->outOverflow, 0, sizeof(unsigned int)));
    MPCD_CUDA_0490K_CHECK(cudaMemset(impl->outReceiverCells, 0, sizeof(unsigned int)));
    MPCD_CUDA_0490K_CHECK(cudaMemset(impl->outDonorCells, 0, sizeof(unsigned int)));
    MPCD_CUDA_0490K_CHECK(cudaMemset(impl->outPlannedMass, 0, sizeof(double)));

    cudaEvent_t start{}, stop{};
    MPCD_CUDA_0490K_CHECK(cudaEventCreate(&start));
    MPCD_CUDA_0490K_CHECK(cudaEventCreate(&stop));
    MPCD_CUDA_0490K_CHECK(cudaEventRecord(start));
    build_species_transfer_plan_serial_0490k<<<1, 1>>>(
        nc, ns, grid.Nx, grid.Ny,
        periodic_x_0490k(params) ? 1 : 0,
        periodic_y_0490k(params) ? 1 : 0,
        resamplingDiagnostics.targetCellMass,
        resamplingDiagnostics.poorMassThreshold,
        resamplingDiagnostics.richMassThreshold,
        impl->wetCell,
        speciesView.speciesTypes,
        speciesView.mass,
        speciesView.totalCellMass,
        impl->receiverRemaining,
        impl->donorRemaining,
        impl->receiverSpeciesRemaining,
        impl->donorSpeciesRemaining,
        maxPlanEntries,
        impl->outDonor,
        impl->outReceiver,
        impl->outType,
        impl->outMass,
        impl->outDistance,
        impl->outDonorRemainingAfter,
        impl->outReceiverRemainingAfter,
        impl->outCount,
        impl->outOverflow,
        impl->outReceiverCells,
        impl->outDonorCells,
        impl->outPlannedMass);
    MPCD_CUDA_0490K_CHECK(cudaEventRecord(stop));
    MPCD_CUDA_0490K_CHECK(cudaEventSynchronize(stop));
    MPCD_CUDA_0490K_CHECK(cudaGetLastError());
    float elapsedMs = 0.0f;
    MPCD_CUDA_0490K_CHECK(cudaEventElapsedTime(&elapsedMs, start, stop));
    MPCD_CUDA_0490K_CHECK(cudaEventDestroy(start));
    MPCD_CUDA_0490K_CHECK(cudaEventDestroy(stop));
    d.plannerKernelSeconds = static_cast<double>(elapsedMs) * 1.0e-3;

    const Clock0490k::time_point download0 = Clock0490k::now();
    unsigned int count = 0u;
    unsigned int overflow = 0u;
    unsigned int receiverCells = 0u;
    unsigned int donorCells = 0u;
    double plannedMass = 0.0;
    MPCD_CUDA_0490K_CHECK(cudaMemcpy(&count, impl->outCount, sizeof(count), cudaMemcpyDeviceToHost));
    MPCD_CUDA_0490K_CHECK(cudaMemcpy(&overflow, impl->outOverflow, sizeof(overflow), cudaMemcpyDeviceToHost));
    MPCD_CUDA_0490K_CHECK(cudaMemcpy(&receiverCells, impl->outReceiverCells, sizeof(receiverCells), cudaMemcpyDeviceToHost));
    MPCD_CUDA_0490K_CHECK(cudaMemcpy(&donorCells, impl->outDonorCells, sizeof(donorCells), cudaMemcpyDeviceToHost));
    MPCD_CUDA_0490K_CHECK(cudaMemcpy(&plannedMass, impl->outPlannedMass, sizeof(plannedMass), cudaMemcpyDeviceToHost));
    d.gpuPlanEntries = count;
    d.overflowCount = overflow;
    d.receiverCells = receiverCells;
    d.donorCells = donorCells;
    d.gpuPlannedMass = plannedMass;
    if (count > static_cast<unsigned int>(maxPlanEntries) || overflow > 0u) {
        d.totalSeconds = seconds_since_0490k(total0);
        append_csv_0490k(params, d);
        throw std::runtime_error("0490k native GPU plan capacity overflow");
    }

    std::vector<int> donor(count);
    std::vector<int> receiver(count);
    std::vector<std::uint32_t> type(count);
    std::vector<double> mass(count);
    std::vector<double> distance(count);
    std::vector<double> donorAfter(count);
    std::vector<double> receiverAfter(count);
    if (count > 0u) {
        const std::size_t bytesInt = static_cast<std::size_t>(count) * sizeof(int);
        const std::size_t bytesType = static_cast<std::size_t>(count) * sizeof(std::uint32_t);
        const std::size_t bytesDouble = static_cast<std::size_t>(count) * sizeof(double);
        MPCD_CUDA_0490K_CHECK(cudaMemcpy(donor.data(), impl->outDonor, bytesInt, cudaMemcpyDeviceToHost));
        MPCD_CUDA_0490K_CHECK(cudaMemcpy(receiver.data(), impl->outReceiver, bytesInt, cudaMemcpyDeviceToHost));
        MPCD_CUDA_0490K_CHECK(cudaMemcpy(type.data(), impl->outType, bytesType, cudaMemcpyDeviceToHost));
        MPCD_CUDA_0490K_CHECK(cudaMemcpy(mass.data(), impl->outMass, bytesDouble, cudaMemcpyDeviceToHost));
        MPCD_CUDA_0490K_CHECK(cudaMemcpy(distance.data(), impl->outDistance, bytesDouble, cudaMemcpyDeviceToHost));
        MPCD_CUDA_0490K_CHECK(cudaMemcpy(donorAfter.data(), impl->outDonorRemainingAfter, bytesDouble, cudaMemcpyDeviceToHost));
        MPCD_CUDA_0490K_CHECK(cudaMemcpy(receiverAfter.data(), impl->outReceiverRemainingAfter, bytesDouble, cudaMemcpyDeviceToHost));
    }
    d.compactDownloadSeconds = seconds_since_0490k(download0);

    std::vector<ResamplingTransferPlanEntry> gpuPlan;
    gpuPlan.reserve(count);
    for (std::size_t i = 0; i < static_cast<std::size_t>(count); ++i) {
        gpuPlan.push_back(ResamplingTransferPlanEntry{
            donor[i], receiver[i], type[i], true, mass[i], distance[i],
            donorAfter[i], receiverAfter[i]});
    }

    const auto& cpuPlan = resamplingWorkspace.transferPlan;
    const std::size_t compareCount = std::min(cpuPlan.size(), gpuPlan.size());
    d.planMismatch = static_cast<std::uint64_t>(
        std::max(cpuPlan.size(), gpuPlan.size()) - compareCount);
    const double tol = params.speciesTransferCudaComparisonTolerance;
    for (std::size_t i = 0; i < compareCount; ++i) {
        const auto& a = cpuPlan[i];
        const auto& b = gpuPlan[i];
        if (a.donorCell != b.donorCell || a.receiverCell != b.receiverCell ||
            a.speciesConstrained != b.speciesConstrained) {
            ++d.planMismatch;
        }
        if (a.particleType != b.particleType) {
            ++d.typeMismatch;
        }
        d.maxPlanMassError = std::max(d.maxPlanMassError, std::abs(a.plannedMass - b.plannedMass));
        d.maxPlanDistanceError = std::max(d.maxPlanDistanceError, std::abs(a.cellDistance - b.cellDistance));
        d.maxDonorRemainingError = std::max(
            d.maxDonorRemainingError,
            std::abs(a.donorRemainingAfter - b.donorRemainingAfter));
        d.maxReceiverRemainingError = std::max(
            d.maxReceiverRemainingError,
            std::abs(a.receiverRemainingAfter - b.receiverRemainingAfter));
    }
    const auto close = [tol](double a, double b) {
        const double scale = std::max({1.0, std::abs(a), std::abs(b)});
        return std::abs(a - b) <= tol * scale;
    };
    d.handled = true;
    d.pass = d.planMismatch == 0u && d.typeMismatch == 0u && d.overflowCount == 0u &&
             d.cpuPlanEntries == d.gpuPlanEntries &&
             d.maxPlanMassError <= tol && d.maxPlanDistanceError <= tol &&
             d.maxDonorRemainingError <= tol && d.maxReceiverRemainingError <= tol &&
             close(d.cpuPlannedMass, d.gpuPlannedMass);
    if (d.pass) {
        resamplingWorkspace.transferPlan = gpuPlan;
        d.accepted = true;
        if (!gpuPlan.empty()) {
            d.firstDonorCell = gpuPlan.front().donorCell;
            d.firstReceiverCell = gpuPlan.front().receiverCell;
            d.firstParticleType = gpuPlan.front().particleType;
            d.lastDonorCell = gpuPlan.back().donorCell;
            d.lastReceiverCell = gpuPlan.back().receiverCell;
            d.lastParticleType = gpuPlan.back().particleType;
        }
    }
    d.totalSeconds = seconds_since_0490k(total0);
    append_csv_0490k(params, d);
    return d;
#endif
}

} // namespace mpcd
