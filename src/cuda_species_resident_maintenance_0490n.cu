#include "cuda_species_resident_maintenance_0490n.h"

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
#include <type_traits>
#include <utility>
#include <vector>

#if defined(MPCD_ENABLE_CUDA_PARTICLE_STATE) && defined(MPCD_ENABLE_CUDA_CELL_WORKSPACE)
#include <cuda_runtime.h>
#include <cub/device/device_select.cuh>
#include <cub/iterator/counting_input_iterator.cuh>
#endif

namespace mpcd {
namespace {

using Clock0490n = std::chrono::steady_clock;

double seconds_since_0490n(const Clock0490n::time_point& t0) {
    return std::chrono::duration<double>(Clock0490n::now() - t0).count();
}

void append_csv_0490n(const SimulationParams& params,
                      const CudaSpeciesResidentMaintenanceDiagnostics0490n& d) {
    if (params.outputDir.empty() ||
        params.speciesCudaResidentMaintenanceDiagnosticsFilename.empty()) return;
    const std::filesystem::path path =
        std::filesystem::path(params.outputDir) /
        params.speciesCudaResidentMaintenanceDiagnosticsFilename;
    std::filesystem::create_directories(path.parent_path());
    const bool header = !std::filesystem::exists(path) ||
                        std::filesystem::file_size(path) == 0u;
    std::ofstream out(path, std::ios::app);
    if (!out) throw std::runtime_error("0490n failed to open diagnostics CSV: " + path.string());
    if (header) {
        out << "step,context,attempted,handled,pass,skipped,skipReason,depositRequested,poolRequested,strictMode,"
               "usedSharedResidentState,particleUploadSkipped,speciesWorkspaceReused,maintenanceWorkspaceReused,"
               "storageSlots,fluidSlots,latentSlots,inactiveSlots,firstFluidSlot,lastFluidSlot,"
               "firstInactiveSlot,lastInactiveSlot,activePrefixViolations,duplicateFreeSlots,"
               "activeAndFreeSlots,invalidRoleSlots,cells,species,nonEmptyCells,wetCells,"
               "poorCells,richCells,receiverCells,donorCells,cellMirrorDownloadBytes,policySummaryDownloadBytes,"
               "policyHostArrayEntries,poolScalarDownloadBytes,cellPolicyDeviceResident,allocatedBytes,"
               "totalMass,totalPx,totalPy,targetCellMass,maxCellMassMirrorError,particleUploadSeconds,"
               "speciesDepositSeconds,poolBuildSeconds,compactDownloadSeconds,hostCellMirrorSeconds,"
               "policyKernelSeconds,totalSeconds\n";
    }
    out << std::setprecision(17)
        << d.step << ',' << '"' << d.context << '"' << ','
        << (d.attempted ? 1 : 0) << ',' << (d.handled ? 1 : 0) << ','
        << (d.pass ? 1 : 0) << ',' << (d.skipped ? 1 : 0) << ','
        << '"' << d.skipReason << '"' << ','
        << d.depositRequested << ',' << d.poolRequested << ',' << d.strictMode << ','
        << d.usedSharedResidentState << ',' << d.particleUploadSkipped << ','
        << d.speciesWorkspaceReused << ',' << d.maintenanceWorkspaceReused << ','
        << d.storageSlots << ',' << d.fluidSlots << ',' << d.latentSlots << ','
        << d.inactiveSlots << ',' << d.firstFluidSlot << ',' << d.lastFluidSlot << ','
        << d.firstInactiveSlot << ',' << d.lastInactiveSlot << ',' << d.activePrefixViolations << ','
        << d.duplicateFreeSlots << ',' << d.activeAndFreeSlots << ',' << d.invalidRoleSlots << ','
        << d.cells << ',' << d.species << ',' << d.nonEmptyCells << ',' << d.wetCells << ','
        << d.poorCells << ',' << d.richCells << ',' << d.receiverCells << ',' << d.donorCells << ','
        << d.cellMirrorDownloadBytes << ',' << d.policySummaryDownloadBytes << ','
        << d.policyHostArrayEntries << ',' << d.poolScalarDownloadBytes << ','
        << d.cellPolicyDeviceResident << ',' << d.allocatedBytes << ','
        << d.totalMass << ',' << d.totalPx << ',' << d.totalPy << ',' << d.targetCellMass << ','
        << d.maxCellMassMirrorError << ',' << d.particleUploadSeconds << ',' << d.speciesDepositSeconds << ','
        << d.poolBuildSeconds << ',' << d.compactDownloadSeconds << ',' << d.hostCellMirrorSeconds << ','
        << d.policyKernelSeconds << ',' << d.totalSeconds << '\n';
}

struct CellPolicySummary0490p {
    unsigned long long nonEmptyCells = 0u;
    unsigned long long wetCells = 0u;
    unsigned long long poorCells = 0u;
    unsigned long long richCells = 0u;
    unsigned long long targetBandCells = 0u;
    unsigned long long emptyWetCells = 0u;
    unsigned long long emptyWetReceiverCells = 0u;
    unsigned long long receiverCells = 0u;
    unsigned long long donorCells = 0u;
    unsigned int minN = 0u;
    unsigned int maxN = 0u;
    int firstReceiverCell = kInvalidCellIndex;
    int lastReceiverCell = kInvalidCellIndex;
    int firstDonorCell = kInvalidCellIndex;
    int lastDonorCell = kInvalidCellIndex;
    double sumN = 0.0;
    double sumN2 = 0.0;
    double totalMass = 0.0;
    double totalPx = 0.0;
    double totalPy = 0.0;
    double sumMass2 = 0.0;
    double minMass = 0.0;
    double maxMass = 0.0;
    double cellUx2 = 0.0;
    double cellUy2 = 0.0;
    double targetCellMass = 0.0;
    double rel2 = 0.0;
    double relMax = 0.0;
    double receiverDeficit = 0.0;
    double donorExcess = 0.0;
};

void clear_host_cell_policy_mirror_0490p(
    WeightedRealFluidDepositWorkspace& ws,
    std::uint64_t fluidSlots) {
    ws = WeightedRealFluidDepositWorkspace{};
    ws.allocatedParticles = fluidSlots;
}

void install_device_cell_policy_summary_0490p(
    const SimulationParams& params,
    int numCells,
    const CellPolicySummary0490p& s,
    WeightedRealFluidDepositWorkspace& ws,
    WeightedResamplingDiagnostics& d,
    CudaSpeciesResidentMaintenanceDiagnostics0490n& md) {
    if (numCells <= 0) {
        throw std::runtime_error("0490p invalid cell count");
    }
    clear_host_cell_policy_mirror_0490p(ws, md.fluidSlots);
    d = WeightedResamplingDiagnostics{};
    d.computed = true;
    d.nFluid = md.fluidSlots;
    d.nLatent = md.latentSlots;
    d.nInactive = md.inactiveSlots;
    d.nCells = static_cast<std::uint64_t>(numCells);
    d.nNonEmptyCells = s.nonEmptyCells;
    d.nEmptyCells = d.nCells - d.nNonEmptyCells;
    const double invNc = 1.0 / static_cast<double>(numCells);
    d.meanN = s.sumN * invNc;
    d.stdN = std::sqrt(std::max(0.0, s.sumN2 * invNc - d.meanN * d.meanN));
    d.minN = s.minN;
    d.maxN = s.maxN;
    d.totalMass = s.totalMass;
    d.totalPx = s.totalPx;
    d.totalPy = s.totalPy;
    d.meanMass = s.totalMass * invNc;
    d.stdMass = std::sqrt(std::max(0.0, s.sumMass2 * invNc - d.meanMass * d.meanMass));
    d.minMass = s.minMass;
    d.maxMass = s.maxMass;
    d.targetCellMass = s.targetCellMass;
    d.meanUx = s.totalMass > 0.0 ? s.totalPx / s.totalMass : 0.0;
    d.meanUy = s.totalMass > 0.0 ? s.totalPy / s.totalMass : 0.0;
    d.cellUxRms = s.nonEmptyCells > 0u
        ? std::sqrt(s.cellUx2 / static_cast<double>(s.nonEmptyCells)) : 0.0;
    d.cellUyRms = s.nonEmptyCells > 0u
        ? std::sqrt(s.cellUy2 / static_cast<double>(s.nonEmptyCells)) : 0.0;

    d.cellClassificationComputed = true;
    d.nActiveCells = d.nCells;
    d.nWetCells = s.wetCells;
    d.nDryCells = d.nCells - d.nWetCells;
    d.nPoorCells = s.poorCells;
    d.nRichCells = s.richCells;
    d.nTargetBandCells = s.targetBandCells;
    d.nEmptyWetCells = s.emptyWetCells;
    d.wetMassThreshold = params.resamplingWetCellMassThreshold;
    d.poorMassThreshold = d.targetCellMass * params.resamplingPoorCellMassFraction;
    d.richMassThreshold = d.targetCellMass * params.resamplingRichCellMassFraction;
    const double invWet = d.nWetCells > 0u
        ? 1.0 / static_cast<double>(d.nWetCells) : 0.0;
    d.wetCellFraction = static_cast<double>(d.nWetCells) * invNc;
    d.dryCellFraction = static_cast<double>(d.nDryCells) * invNc;
    d.poorCellFraction = static_cast<double>(d.nPoorCells) * invWet;
    d.richCellFraction = static_cast<double>(d.nRichCells) * invWet;
    d.emptyWetCellFraction = static_cast<double>(d.nEmptyWetCells) * invWet;
    d.mRelRms = std::sqrt(s.rel2 * invWet);
    d.mRelMaxAbs = s.relMax;

    d.candidateListsBuilt = true;
    d.nReceiverCells = s.receiverCells;
    d.nDonorCells = s.donorCells;
    d.nEmptyWetReceiverCells = s.emptyWetReceiverCells;
    d.firstReceiverCell = s.firstReceiverCell;
    d.lastReceiverCell = s.lastReceiverCell;
    d.firstDonorCell = s.firstDonorCell;
    d.lastDonorCell = s.lastDonorCell;
    d.receiverMassDeficitToTarget = s.receiverDeficit;
    d.donorMassExcessAboveTarget = s.donorExcess;
    d.donorReceiverMassBalance = s.donorExcess - s.receiverDeficit;
    d.potentialTransferMass = std::min(s.receiverDeficit, s.donorExcess);
    d.receiverFractionOfWetCells = static_cast<double>(d.nReceiverCells) * invWet;
    d.donorFractionOfWetCells = static_cast<double>(d.nDonorCells) * invWet;
    d.poolCanSeedReceivers = md.inactiveSlots > 0u;

    md.nonEmptyCells = s.nonEmptyCells;
    md.wetCells = s.wetCells;
    md.poorCells = s.poorCells;
    md.richCells = s.richCells;
    md.receiverCells = s.receiverCells;
    md.donorCells = s.donorCells;
    md.totalMass = s.totalMass;
    md.totalPx = s.totalPx;
    md.totalPy = s.totalPy;
    md.targetCellMass = s.targetCellMass;
    md.policyHostArrayEntries = 0u;
    md.cellPolicyDeviceResident = 1;
}

#if defined(MPCD_ENABLE_CUDA_PARTICLE_STATE) && defined(MPCD_ENABLE_CUDA_CELL_WORKSPACE)
#define MPCD_CUDA_0490N_CHECK(call) do { \
    const cudaError_t err__ = (call); \
    if (err__ != cudaSuccess) { \
        throw std::runtime_error(std::string("CUDA error in ") + #call + ": " + \
                                 cudaGetErrorString(err__)); \
    } \
} while (0)

template <typename T>
void cuda_free_0490n(T*& ptr) {
    if (ptr != nullptr) {
        cudaFree(ptr);
        ptr = nullptr;
    }
}

struct RoleEquals0490n {
    const unsigned char* role = nullptr;
    unsigned char wanted = 0u;
    __device__ bool operator()(const unsigned int index) const {
        return role[index] == wanted;
    }
};


__global__ void build_species_cell_policy_serial_0490p(
    int numCells,
    int speciesCount,
    int occupiedWetMode,
    double wetMassThreshold,
    double configuredTargetCellMass,
    double poorFraction,
    double richFraction,
    const unsigned int* speciesCountField,
    const double* speciesPx,
    const double* speciesPy,
    const double* totalCellMass,
    unsigned char* wetCell,
    unsigned char* poorCell,
    unsigned char* richCell,
    unsigned char* targetBandCell,
    CellPolicySummary0490p* outSummary) {
    if (blockIdx.x != 0 || threadIdx.x != 0) return;
    CellPolicySummary0490p s{};
    s.minN = 0xffffffffu;
    s.minMass = 1.0e300;
    s.firstReceiverCell = kInvalidCellIndex;
    s.lastReceiverCell = kInvalidCellIndex;
    s.firstDonorCell = kInvalidCellIndex;
    s.lastDonorCell = kInvalidCellIndex;
    double wetMass = 0.0;

    for (int c = 0; c < numCells; ++c) {
        unsigned int count = 0u;
        double px = 0.0;
        double py = 0.0;
        for (int species = 0; species < speciesCount; ++species) {
            const int k = species * numCells + c;
            count += speciesCountField[k];
            px += speciesPx[k];
            py += speciesPy[k];
        }
        const double mass = totalCellMass[c];
        const bool nonEmpty = mass > 0.0;
        const bool wet = !occupiedWetMode || mass > wetMassThreshold;
        wetCell[c] = wet ? 1u : 0u;
        poorCell[c] = 0u;
        richCell[c] = 0u;
        targetBandCell[c] = 0u;
        if (nonEmpty) {
            ++s.nonEmptyCells;
            const double ux = px / mass;
            const double uy = py / mass;
            s.cellUx2 += ux * ux;
            s.cellUy2 += uy * uy;
        }
        if (wet) {
            ++s.wetCells;
            wetMass += mass;
        }
        const double dn = static_cast<double>(count);
        s.sumN += dn;
        s.sumN2 += dn * dn;
        s.totalMass += mass;
        s.totalPx += px;
        s.totalPy += py;
        s.sumMass2 += mass * mass;
        if (count < s.minN) s.minN = count;
        if (count > s.maxN) s.maxN = count;
        if (mass < s.minMass) s.minMass = mass;
        if (mass > s.maxMass) s.maxMass = mass;
    }

    if (s.minN == 0xffffffffu) s.minN = 0u;
    if (s.minMass > 1.0e299) s.minMass = 0.0;
    s.targetCellMass = configuredTargetCellMass > 0.0
        ? configuredTargetCellMass
        : (s.wetCells > 0u
            ? wetMass / static_cast<double>(s.wetCells)
            : (numCells > 0 ? s.totalMass / static_cast<double>(numCells) : 0.0));
    const double poorThreshold = s.targetCellMass * poorFraction;
    const double richThreshold = s.targetCellMass * richFraction;

    for (int c = 0; c < numCells; ++c) {
        if (wetCell[c] == 0u || !(s.targetCellMass > 0.0)) continue;
        unsigned int count = 0u;
        for (int species = 0; species < speciesCount; ++species) {
            count += speciesCountField[species * numCells + c];
        }
        const double mass = totalCellMass[c];
        const double rel = (mass - s.targetCellMass) / s.targetCellMass;
        s.rel2 += rel * rel;
        const double absRel = rel < 0.0 ? -rel : rel;
        if (absRel > s.relMax) s.relMax = absRel;
        const bool poor = mass < poorThreshold;
        const bool rich = mass > richThreshold;
        poorCell[c] = poor ? 1u : 0u;
        richCell[c] = rich ? 1u : 0u;
        targetBandCell[c] = (!poor && !rich) ? 1u : 0u;
        if (count == 0u) ++s.emptyWetCells;
        if (poor) {
            ++s.poorCells;
            if (count == 0u) ++s.emptyWetReceiverCells;
            ++s.receiverCells;
            if (s.firstReceiverCell == kInvalidCellIndex) s.firstReceiverCell = c;
            s.lastReceiverCell = c;
            s.receiverDeficit += s.targetCellMass > mass ? s.targetCellMass - mass : 0.0;
        } else if (rich) {
            ++s.richCells;
            ++s.donorCells;
            if (s.firstDonorCell == kInvalidCellIndex) s.firstDonorCell = c;
            s.lastDonorCell = c;
            s.donorExcess += mass > s.targetCellMass ? mass - s.targetCellMass : 0.0;
        } else {
            ++s.targetBandCells;
        }
    }
    *outSummary = s;
}
#endif

} // namespace

struct CudaSpeciesResidentMaintenanceWorkspace0490n::Impl {
    std::uint64_t capacity = 0u;
    std::uint64_t allocatedBytes = 0u;
#if defined(MPCD_ENABLE_CUDA_PARTICLE_STATE) && defined(MPCD_ENABLE_CUDA_CELL_WORKSPACE)
    unsigned int* fluidSlots = nullptr;
    unsigned int* latentSlots = nullptr;
    unsigned int* inactiveSlots = nullptr;
    unsigned int* fluidCount = nullptr;
    unsigned int* latentCount = nullptr;
    unsigned int* inactiveCount = nullptr;
    void* selectTemp = nullptr;
    std::size_t selectTempBytes = 0u;
    int cellCapacity = 0;
    unsigned char* wetCell = nullptr;
    unsigned char* poorCell = nullptr;
    unsigned char* richCell = nullptr;
    unsigned char* targetBandCell = nullptr;
    CellPolicySummary0490p* policySummary = nullptr;
#endif
};

CudaSpeciesResidentMaintenanceWorkspace0490n::CudaSpeciesResidentMaintenanceWorkspace0490n()
    : impl_(new Impl()) {}

CudaSpeciesResidentMaintenanceWorkspace0490n::~CudaSpeciesResidentMaintenanceWorkspace0490n() {
    release();
    delete impl_;
    impl_ = nullptr;
}

CudaSpeciesResidentMaintenanceWorkspace0490n::CudaSpeciesResidentMaintenanceWorkspace0490n(
    CudaSpeciesResidentMaintenanceWorkspace0490n&& other) noexcept
    : impl_(other.impl_) {
    other.impl_ = new Impl();
}

CudaSpeciesResidentMaintenanceWorkspace0490n&
CudaSpeciesResidentMaintenanceWorkspace0490n::operator=(
    CudaSpeciesResidentMaintenanceWorkspace0490n&& other) noexcept {
    if (this != &other) {
        release();
        delete impl_;
        impl_ = other.impl_;
        other.impl_ = new Impl();
    }
    return *this;
}

void CudaSpeciesResidentMaintenanceWorkspace0490n::release() {
#if defined(MPCD_ENABLE_CUDA_PARTICLE_STATE) && defined(MPCD_ENABLE_CUDA_CELL_WORKSPACE)
    if (impl_ != nullptr) {
        cuda_free_0490n(impl_->fluidSlots);
        cuda_free_0490n(impl_->latentSlots);
        cuda_free_0490n(impl_->inactiveSlots);
        cuda_free_0490n(impl_->fluidCount);
        cuda_free_0490n(impl_->latentCount);
        cuda_free_0490n(impl_->inactiveCount);
        cuda_free_0490n(impl_->selectTemp);
        cuda_free_0490n(impl_->wetCell);
        cuda_free_0490n(impl_->poorCell);
        cuda_free_0490n(impl_->richCell);
        cuda_free_0490n(impl_->targetBandCell);
        cuda_free_0490n(impl_->policySummary);
    }
#endif
    if (impl_ != nullptr) *impl_ = Impl{};
}

void CudaSpeciesResidentMaintenanceWorkspace0490n::ensure_capacity(
    std::uint64_t particles,
    int cells,
    CudaSpeciesResidentMaintenanceDiagnostics0490n* diagnostics) {
#if !defined(MPCD_ENABLE_CUDA_PARTICLE_STATE) || !defined(MPCD_ENABLE_CUDA_CELL_WORKSPACE)
    (void)particles;
    (void)cells;
    (void)diagnostics;
    throw std::runtime_error("0490n CUDA workspace requires CUDA particle/cell support");
#else
    if (particles == 0u) particles = 1u;
    if (cells <= 0) throw std::runtime_error("0490p workspace requires positive cell count");
    if (impl_ == nullptr) throw std::runtime_error("0490n workspace has null impl");
    const bool reuse = impl_->capacity >= particles && impl_->cellCapacity >= cells;
    if (diagnostics) diagnostics->maintenanceWorkspaceReused = reuse ? 1 : 0;
    if (reuse) {
        if (diagnostics) diagnostics->allocatedBytes = impl_->allocatedBytes;
        return;
    }
    release();
    std::uint64_t bytes = 0u;
    auto alloc = [&](auto*& ptr, std::uint64_t count) {
        using T = std::remove_pointer_t<std::remove_reference_t<decltype(ptr)>>;
        MPCD_CUDA_0490N_CHECK(cudaMalloc(reinterpret_cast<void**>(&ptr),
            static_cast<std::size_t>(count) * sizeof(T)));
        bytes += count * static_cast<std::uint64_t>(sizeof(T));
    };
    alloc(impl_->fluidSlots, particles);
    alloc(impl_->latentSlots, particles);
    alloc(impl_->inactiveSlots, particles);
    alloc(impl_->fluidCount, 1u);
    alloc(impl_->latentCount, 1u);
    alloc(impl_->inactiveCount, 1u);
    alloc(impl_->wetCell, static_cast<std::uint64_t>(cells));
    alloc(impl_->poorCell, static_cast<std::uint64_t>(cells));
    alloc(impl_->richCell, static_cast<std::uint64_t>(cells));
    alloc(impl_->targetBandCell, static_cast<std::uint64_t>(cells));
    alloc(impl_->policySummary, 1u);

    cub::CountingInputIterator<unsigned int> counting(0u);
    std::size_t tempBytes = 0u;
    RoleEquals0490n predicate{};
    MPCD_CUDA_0490N_CHECK(cub::DeviceSelect::If(
        nullptr, tempBytes, counting, impl_->fluidSlots, impl_->fluidCount,
        static_cast<int>(particles), predicate));
    MPCD_CUDA_0490N_CHECK(cudaMalloc(&impl_->selectTemp, tempBytes));
    impl_->selectTempBytes = tempBytes;
    bytes += static_cast<std::uint64_t>(tempBytes);
    impl_->capacity = particles;
    impl_->cellCapacity = cells;
    impl_->allocatedBytes = bytes;
    if (diagnostics) diagnostics->allocatedBytes = bytes;
#endif
}

std::uint64_t CudaSpeciesResidentMaintenanceWorkspace0490n::capacity() const {
    return impl_ ? impl_->capacity : 0u;
}

std::uint64_t CudaSpeciesResidentMaintenanceWorkspace0490n::allocated_bytes() const {
    return impl_ ? impl_->allocatedBytes : 0u;
}

CudaSpeciesResidentPoolDeviceView0490n
CudaSpeciesResidentMaintenanceWorkspace0490n::pool_device_view() const {
    CudaSpeciesResidentPoolDeviceView0490n view{};
#if defined(MPCD_ENABLE_CUDA_PARTICLE_STATE) && defined(MPCD_ENABLE_CUDA_CELL_WORKSPACE)
    if (impl_ != nullptr) {
        view.capacity = impl_->capacity;
        view.fluidSlots = impl_->fluidSlots;
        view.latentSlots = impl_->latentSlots;
        view.inactiveSlots = impl_->inactiveSlots;
        view.fluidCount = impl_->fluidCount;
        view.latentCount = impl_->latentCount;
        view.inactiveCount = impl_->inactiveCount;
    }
#endif
    return view;
}

CudaSpeciesCellPolicyDeviceView0490p
CudaSpeciesResidentMaintenanceWorkspace0490n::cell_policy_device_view_0490p() const {
    CudaSpeciesCellPolicyDeviceView0490p view{};
#if defined(MPCD_ENABLE_CUDA_PARTICLE_STATE) && defined(MPCD_ENABLE_CUDA_CELL_WORKSPACE)
    if (impl_ != nullptr) {
        view.numCells = impl_->cellCapacity;
        view.wetCell = impl_->wetCell;
        view.poorCell = impl_->poorCell;
        view.richCell = impl_->richCell;
        view.targetBandCell = impl_->targetBandCell;
    }
#endif
    return view;
}

bool cuda_species_resident_maintenance_available_0490n() {
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

CudaSpeciesResidentMaintenanceDiagnostics0490n
refresh_cuda_species_resident_maintenance_0490n(
    ParticleState& state,
    const SimulationParams& params,
    const CellGrid& grid,
    const FluidDomainBounds& domain,
    double time,
    std::uint64_t step,
    const char* context,
    bool refreshDeposit,
    bool refreshPool,
    CudaSpeciesCellWorkspace0490h& speciesWorkspace,
    CudaSpeciesResidentMaintenanceWorkspace0490n& maintenanceWorkspace,
    WeightedRealFluidDepositWorkspace& depositMirror,
    WeightedResamplingDiagnostics& depositDiagnostics,
    ResamplingParticlePoolWorkspace& poolMirror,
    ResamplingParticlePoolDiagnostics& poolDiagnostics) {
    CudaSpeciesResidentMaintenanceDiagnostics0490n d{};
    d.attempted = true;
    d.step = step;
    d.context = context != nullptr ? context : "unknown";
    d.depositRequested = refreshDeposit ? 1 : 0;
    d.poolRequested = refreshPool ? 1 : 0;
    d.strictMode = params.speciesResamplingCudaResidentMaintenanceStrict ? 1 : 0;
    d.storageSlots = state.Np;
    d.cells = static_cast<std::uint64_t>(std::max(0, grid.numCells));
    d.species = static_cast<std::uint64_t>(params.speciesDefinitions.size());
    const Clock0490n::time_point total0 = Clock0490n::now();

#if !defined(MPCD_ENABLE_CUDA_PARTICLE_STATE) || !defined(MPCD_ENABLE_CUDA_CELL_WORKSPACE)
    (void)state; (void)params; (void)grid; (void)domain; (void)time;
    (void)speciesWorkspace; (void)maintenanceWorkspace; (void)depositMirror;
    (void)depositDiagnostics; (void)poolMirror; (void)poolDiagnostics;
    d.skipped = true;
    d.skipReason = "CUDA particle/cell support is not compiled";
    d.totalSeconds = seconds_since_0490n(total0);
    append_csv_0490n(params, d);
    return d;
#else
    try {
        if (!refreshDeposit && !refreshPool) {
            d.skipped = true;
            d.skipReason = "no resident maintenance component requested";
            d.totalSeconds = seconds_since_0490n(total0);
            append_csv_0490n(params, d);
            return d;
        }
        if (!params.speciesResamplingCudaResidentFastPathEnable) {
            throw std::runtime_error("0490n requires the validated 0490m resident fast path");
        }
        if (state.Np > static_cast<std::uint64_t>(std::numeric_limits<int>::max())) {
            throw std::runtime_error("0490n particle storage exceeds CUB selection index range");
        }
        if (!(params.bcLeft == "periodic" && params.bcRight == "periodic" &&
              params.bcBottom == "periodic" && params.bcTop == "periodic") ||
            params.immersedSolidEnable) {
            throw std::runtime_error("0490n currently requires periodic wall-free no-solid geometry");
        }
        if (!cuda_species_resident_maintenance_available_0490n()) {
            throw std::runtime_error("0490n requested but no CUDA device is available");
        }

        CudaParticleState& particles = cuda_shared_particle_state_0251();
        CudaParticleStateDiagnostics upload{};
        if (cuda_shared_particle_state_0251_is_fresh() && particles.size() == state.Np) {
            d.usedSharedResidentState = 1;
            d.particleUploadSkipped = 1;
        } else {
            particles.upload_all(state, &upload);
            d.particleUploadSeconds = upload.uploadSeconds;
            cuda_shared_particle_state_0251_mark_fresh("species_resident_maintenance_0490n");
        }
        const CudaParticleDeviceView pv = particles.device_view();
        if (pv.n != state.Np || pv.role == nullptr) {
            throw std::runtime_error("0490n shared particle-state shape mismatch");
        }
        maintenanceWorkspace.ensure_capacity(state.Np, grid.numCells, &d);

        if (refreshPool) {
            auto* impl = maintenanceWorkspace.impl_;
            cub::CountingInputIterator<unsigned int> counting(0u);
            const Clock0490n::time_point pool0 = Clock0490n::now();
            const RoleEquals0490n fluid{pv.role, static_cast<unsigned char>(ParticleRole::Fluid)};
            const RoleEquals0490n latent{pv.role, static_cast<unsigned char>(ParticleRole::Latent)};
            const RoleEquals0490n inactive{pv.role, static_cast<unsigned char>(ParticleRole::Inactive)};
            MPCD_CUDA_0490N_CHECK(cub::DeviceSelect::If(
                impl->selectTemp, impl->selectTempBytes, counting,
                impl->fluidSlots, impl->fluidCount, static_cast<int>(state.Np), fluid));
            MPCD_CUDA_0490N_CHECK(cub::DeviceSelect::If(
                impl->selectTemp, impl->selectTempBytes, counting,
                impl->latentSlots, impl->latentCount, static_cast<int>(state.Np), latent));
            MPCD_CUDA_0490N_CHECK(cub::DeviceSelect::If(
                impl->selectTemp, impl->selectTempBytes, counting,
                impl->inactiveSlots, impl->inactiveCount, static_cast<int>(state.Np), inactive));
            MPCD_CUDA_0490N_CHECK(cudaDeviceSynchronize());
            d.poolBuildSeconds = seconds_since_0490n(pool0);

            const Clock0490n::time_point download0 = Clock0490n::now();
            unsigned int fluidCount = 0u, latentCount = 0u, inactiveCount = 0u;
            MPCD_CUDA_0490N_CHECK(cudaMemcpy(&fluidCount, impl->fluidCount,
                sizeof(fluidCount), cudaMemcpyDeviceToHost));
            MPCD_CUDA_0490N_CHECK(cudaMemcpy(&latentCount, impl->latentCount,
                sizeof(latentCount), cudaMemcpyDeviceToHost));
            MPCD_CUDA_0490N_CHECK(cudaMemcpy(&inactiveCount, impl->inactiveCount,
                sizeof(inactiveCount), cudaMemcpyDeviceToHost));
            d.poolScalarDownloadBytes = 3u * sizeof(unsigned int);
            d.fluidSlots = fluidCount;
            d.latentSlots = latentCount;
            d.inactiveSlots = inactiveCount;
            if (fluidCount > 0u) {
                unsigned int first = 0u, last = 0u;
                MPCD_CUDA_0490N_CHECK(cudaMemcpy(&first, impl->fluidSlots,
                    sizeof(first), cudaMemcpyDeviceToHost));
                MPCD_CUDA_0490N_CHECK(cudaMemcpy(&last, impl->fluidSlots + fluidCount - 1u,
                    sizeof(last), cudaMemcpyDeviceToHost));
                d.firstFluidSlot = first;
                d.lastFluidSlot = last;
                d.poolScalarDownloadBytes += 2u * sizeof(unsigned int);
            }
            if (inactiveCount > 0u) {
                unsigned int first = 0u, last = 0u;
                MPCD_CUDA_0490N_CHECK(cudaMemcpy(&first, impl->inactiveSlots,
                    sizeof(first), cudaMemcpyDeviceToHost));
                MPCD_CUDA_0490N_CHECK(cudaMemcpy(&last, impl->inactiveSlots + inactiveCount - 1u,
                    sizeof(last), cudaMemcpyDeviceToHost));
                d.firstInactiveSlot = first;
                d.lastInactiveSlot = last;
                d.poolScalarDownloadBytes += 2u * sizeof(unsigned int);
            }
            d.compactDownloadSeconds += seconds_since_0490n(download0);
            d.invalidRoleSlots = state.Np >= d.fluidSlots + d.latentSlots + d.inactiveSlots
                ? state.Np - (d.fluidSlots + d.latentSlots + d.inactiveSlots)
                : state.Np;
            const bool fluidPrefix = fluidCount == 0u ||
                (d.firstFluidSlot == 0u && d.lastFluidSlot + 1u == d.fluidSlots);
            const bool inactiveTail = inactiveCount == 0u ||
                (d.firstInactiveSlot == d.fluidSlots &&
                 d.lastInactiveSlot + 1u == state.Np);
            const bool activeMetadataMatches = particles.active_fluid_size() == d.fluidSlots;
            d.activePrefixViolations =
                (fluidPrefix && inactiveTail && d.latentSlots == 0u && activeMetadataMatches) ? 0u : 1u;
            // Mirror only the authoritative active-prefix scalar. Particle arrays
            // remain resident and are not downloaded.
            state.NactiveFluid = d.fluidSlots;

            poolMirror.allocatedParticles = state.Np;
            poolMirror.freeInactiveSlots.clear();
            poolMirror.freeInactiveSlotPosition.clear();
            poolMirror.freeInactiveCount = d.inactiveSlots;
            poolMirror.freeInactiveFirstPosition = 0u;
            poolMirror.latentSlots.clear();
            poolMirror.fluidSlots.clear();
            poolDiagnostics = ResamplingParticlePoolDiagnostics{};
            poolDiagnostics.built = true;
            poolDiagnostics.storageSlots = state.Np;
            poolDiagnostics.nFluid = d.fluidSlots;
            poolDiagnostics.nLatent = d.latentSlots;
            poolDiagnostics.nInactive = d.inactiveSlots;
            poolDiagnostics.fluidSlots = d.fluidSlots;
            poolDiagnostics.latentSlots = d.latentSlots;
            poolDiagnostics.freeSlots = d.inactiveSlots;
            poolDiagnostics.firstFreeIndex = d.firstInactiveSlot;
            poolDiagnostics.lastFreeIndex = d.lastInactiveSlot;
            if (state.Np > 0u) {
                const double inv = 1.0 / static_cast<double>(state.Np);
                poolDiagnostics.freeSlotFraction = static_cast<double>(d.inactiveSlots) * inv;
                poolDiagnostics.dormantSlotFraction =
                    static_cast<double>(d.inactiveSlots + d.latentSlots) * inv;
            }
            poolMirror.diagnostics = poolDiagnostics;
        } else {
            d.fluidSlots = poolDiagnostics.nFluid;
            d.latentSlots = poolDiagnostics.nLatent;
            d.inactiveSlots = poolDiagnostics.nInactive;
        }

        if (refreshDeposit) {
            CudaSpeciesCellDepositDiagnostics0490h deposit{};
            cuda_deposit_species_cell_fields_resident_0490h(
                pv, grid, params, params.speciesDefinitions,
                speciesWorkspace, &deposit, params.speciesCellCudaThreadsPerBlock);
            d.speciesWorkspaceReused = deposit.reusedAllocation;
            d.speciesDepositSeconds = deposit.depositSeconds + deposit.finalizeSeconds;
            if (deposit.invalidTypeCount != 0u) {
                throw std::runtime_error("0490p resident deposit found unregistered particle types");
            }
            if (!refreshPool) {
                // Role counts are still needed in legacy diagnostics. In the
                // validated active-prefix path NactiveFluid is authoritative and
                // the dormant tail contains no latent slots.
                d.fluidSlots = state.NactiveFluid;
                d.latentSlots = 0u;
                d.inactiveSlots = state.Np >= state.NactiveFluid
                    ? state.Np - state.NactiveFluid : 0u;
            }
            auto* impl = maintenanceWorkspace.impl_;
            const CudaSpeciesCellDeviceView0490h speciesView = speciesWorkspace.device_view();
            if (speciesView.numCells != grid.numCells ||
                speciesView.speciesCount != static_cast<int>(params.speciesDefinitions.size()) ||
                speciesView.count == nullptr || speciesView.px == nullptr ||
                speciesView.py == nullptr || speciesView.totalCellMass == nullptr) {
                throw std::runtime_error("0490p species workspace is not ready for device policy");
            }
            const Clock0490n::time_point policy0 = Clock0490n::now();
            build_species_cell_policy_serial_0490p<<<1, 1>>>(
                grid.numCells, speciesView.speciesCount,
                params.resamplingWetMaskMode == "occupied" ? 1 : 0,
                params.resamplingWetCellMassThreshold,
                params.resamplingTargetCellMass,
                params.resamplingPoorCellMassFraction,
                params.resamplingRichCellMassFraction,
                speciesView.count, speciesView.px, speciesView.py,
                speciesView.totalCellMass,
                impl->wetCell, impl->poorCell, impl->richCell,
                impl->targetBandCell, impl->policySummary);
            MPCD_CUDA_0490N_CHECK(cudaGetLastError());
            MPCD_CUDA_0490N_CHECK(cudaDeviceSynchronize());
            d.policyKernelSeconds = seconds_since_0490n(policy0);

            const Clock0490n::time_point download0 = Clock0490n::now();
            CellPolicySummary0490p summary{};
            MPCD_CUDA_0490N_CHECK(cudaMemcpy(
                &summary, impl->policySummary, sizeof(summary), cudaMemcpyDeviceToHost));
            d.compactDownloadSeconds += seconds_since_0490n(download0);
            d.cellMirrorDownloadBytes = 0u;
            d.policySummaryDownloadBytes = sizeof(summary);
            d.hostCellMirrorSeconds = 0.0;
            depositDiagnostics = WeightedResamplingDiagnostics{};
            install_device_cell_policy_summary_0490p(
                params, grid.numCells, summary,
                depositMirror, depositDiagnostics, d);
        }

        d.allocatedBytes = maintenanceWorkspace.allocated_bytes() +
                           speciesWorkspace.allocated_bytes();
        d.handled = true;
        d.pass = d.invalidRoleSlots == 0u && d.activePrefixViolations == 0u &&
                 d.duplicateFreeSlots == 0u && d.activeAndFreeSlots == 0u &&
                 d.maxCellMassMirrorError <= params.speciesCellCudaComparisonTolerance &&
                 (!refreshDeposit ||
                  (depositDiagnostics.computed && d.cellPolicyDeviceResident == 1 &&
                   d.policyHostArrayEntries == 0u && d.cellMirrorDownloadBytes == 0u)) &&
                 (!refreshPool || poolDiagnostics.built);
        d.totalSeconds = seconds_since_0490n(total0);
        append_csv_0490n(params, d);
        return d;
    } catch (const std::exception& e) {
        d.skipped = true;
        d.skipReason = e.what();
        d.totalSeconds = seconds_since_0490n(total0);
        append_csv_0490n(params, d);
        return d;
    }
#endif
}

} // namespace mpcd
