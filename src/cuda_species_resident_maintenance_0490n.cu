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
               "poorCells,richCells,receiverCells,donorCells,cellMirrorDownloadBytes,poolScalarDownloadBytes,"
               "allocatedBytes,totalMass,totalPx,totalPy,targetCellMass,maxCellMassMirrorError,particleUploadSeconds,"
               "speciesDepositSeconds,poolBuildSeconds,compactDownloadSeconds,hostCellMirrorSeconds,totalSeconds\n";
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
        << d.cellMirrorDownloadBytes << ',' << d.poolScalarDownloadBytes << ',' << d.allocatedBytes << ','
        << d.totalMass << ',' << d.totalPx << ',' << d.totalPy << ',' << d.targetCellMass << ','
        << d.maxCellMassMirrorError << ',' << d.particleUploadSeconds << ',' << d.speciesDepositSeconds << ','
        << d.poolBuildSeconds << ',' << d.compactDownloadSeconds << ',' << d.hostCellMirrorSeconds << ','
        << d.totalSeconds << '\n';
}

void resize_compact_host_mirror_0490n(WeightedRealFluidDepositWorkspace& ws,
                                      std::uint64_t particles,
                                      int cells) {
    ws.allocatedParticles = particles;
    ws.allocatedCells = cells;
    ws.allocatedThreads = 1;
    ws.cellId.clear();
    ws.count.assign(static_cast<std::size_t>(cells), 0u);
    ws.mass.assign(static_cast<std::size_t>(cells), 0.0);
    ws.px.assign(static_cast<std::size_t>(cells), 0.0);
    ws.py.assign(static_cast<std::size_t>(cells), 0.0);
    ws.ux.assign(static_cast<std::size_t>(cells), 0.0);
    ws.uy.assign(static_cast<std::size_t>(cells), 0.0);
    ws.localCount.clear();
    ws.localMass.clear();
    ws.localPx.clear();
    ws.localPy.clear();
    ws.activeCell.assign(static_cast<std::size_t>(cells), 0u);
    ws.wetCell.assign(static_cast<std::size_t>(cells), 0u);
    ws.dryCell.assign(static_cast<std::size_t>(cells), 0u);
    ws.poorCell.assign(static_cast<std::size_t>(cells), 0u);
    ws.richCell.assign(static_cast<std::size_t>(cells), 0u);
    ws.targetBandCell.assign(static_cast<std::size_t>(cells), 0u);
    ws.receiverPoorCells.clear();
    ws.donorRichCells.clear();
    ws.emptyWetReceiverCells.clear();
    ws.transferPlan.clear();
    ws.selectedDonorParticles.clear();
    ws.passiveExtractionOperations.clear();
    ws.donorSelectedParticleCount.assign(static_cast<std::size_t>(cells), 0u);
    ws.donorSelectedMass.assign(static_cast<std::size_t>(cells), 0.0);
    ws.cellParticleOffsets.clear();
    ws.cellParticleCursor.clear();
    ws.cellParticleIndices.clear();
    ws.populationGuardOverfullCells.clear();
    ws.populationGuardUnderfullCells.clear();
    ws.remapThermalEnergyTarget.assign(static_cast<std::size_t>(cells), 0.0);
    ws.remapThermalCell.assign(static_cast<std::size_t>(cells), 0u);
}

void build_host_cell_policy_mirror_0490n(
    const SimulationParams& params,
    const CellGrid& grid,
    const FluidDomainBounds& domain,
    double time,
    const CudaSpeciesCellFields0490h& species,
    WeightedRealFluidDepositWorkspace& ws,
    WeightedResamplingDiagnostics& d,
    CudaSpeciesResidentMaintenanceDiagnostics0490n& md) {
    (void)domain;
    (void)time;
    const int nc = grid.numCells;
    const int ns = static_cast<int>(species.speciesTypes.size());
    if (nc <= 0 || species.numCells != nc || ns <= 0) {
        throw std::runtime_error("0490n invalid downloaded species-cell shape");
    }
    const std::size_t expected = static_cast<std::size_t>(nc) * static_cast<std::size_t>(ns);
    if (species.count.size() != expected || species.mass.size() != expected ||
        species.px.size() != expected || species.py.size() != expected) {
        throw std::runtime_error("0490n incomplete downloaded species-cell fields");
    }

    resize_compact_host_mirror_0490n(ws, md.fluidSlots, nc);
    double sumN = 0.0;
    double sumN2 = 0.0;
    double sumM = 0.0;
    double sumM2 = 0.0;
    double minMass = std::numeric_limits<double>::infinity();
    double maxMass = 0.0;
    std::uint32_t minN = std::numeric_limits<std::uint32_t>::max();
    std::uint32_t maxN = 0u;
    std::uint64_t nonEmpty = 0u;
    double cellUx2 = 0.0;
    double cellUy2 = 0.0;

    for (int c = 0; c < nc; ++c) {
        std::uint32_t count = 0u;
        double mass = 0.0;
        double px = 0.0;
        double py = 0.0;
        for (int s = 0; s < ns; ++s) {
            const std::size_t k = static_cast<std::size_t>(s * nc + c);
            count += species.count[k];
            mass += species.mass[k];
            px += species.px[k];
            py += species.py[k];
        }
        const std::size_t k = static_cast<std::size_t>(c);
        ws.count[k] = count;
        ws.mass[k] = mass;
        ws.px[k] = px;
        if (k < species.totalCellMass.size()) {
            md.maxCellMassMirrorError = std::max(
                md.maxCellMassMirrorError,
                std::abs(mass - species.totalCellMass[k]));
        }
        ws.py[k] = py;
        if (mass > 0.0) {
            ws.ux[k] = px / mass;
            ws.uy[k] = py / mass;
            ++nonEmpty;
            cellUx2 += ws.ux[k] * ws.ux[k];
            cellUy2 += ws.uy[k] * ws.uy[k];
        }
        d.totalMass += mass;
        d.totalPx += px;
        d.totalPy += py;
        const double dn = static_cast<double>(count);
        sumN += dn;
        sumN2 += dn * dn;
        sumM += mass;
        sumM2 += mass * mass;
        minMass = std::min(minMass, mass);
        maxMass = std::max(maxMass, mass);
        minN = std::min(minN, count);
        maxN = std::max(maxN, count);
    }

    d.computed = true;
    d.nFluid = md.fluidSlots;
    d.nLatent = md.latentSlots;
    d.nInactive = md.inactiveSlots;
    d.nCells = static_cast<std::uint64_t>(nc);
    d.nNonEmptyCells = nonEmpty;
    d.nEmptyCells = static_cast<std::uint64_t>(nc) - nonEmpty;
    const double invNc = nc > 0 ? 1.0 / static_cast<double>(nc) : 0.0;
    d.meanN = sumN * invNc;
    d.stdN = std::sqrt(std::max(0.0, sumN2 * invNc - d.meanN * d.meanN));
    d.minN = minN == std::numeric_limits<std::uint32_t>::max() ? 0u : minN;
    d.maxN = maxN;
    d.meanMass = sumM * invNc;
    d.stdMass = std::sqrt(std::max(0.0, sumM2 * invNc - d.meanMass * d.meanMass));
    d.minMass = std::isfinite(minMass) ? minMass : 0.0;
    d.maxMass = maxMass;
    d.meanUx = d.totalMass > 0.0 ? d.totalPx / d.totalMass : 0.0;
    d.meanUy = d.totalMass > 0.0 ? d.totalPy / d.totalMass : 0.0;
    d.cellUxRms = nonEmpty > 0u ? std::sqrt(cellUx2 / static_cast<double>(nonEmpty)) : 0.0;
    d.cellUyRms = nonEmpty > 0u ? std::sqrt(cellUy2 / static_cast<double>(nonEmpty)) : 0.0;

    std::uint64_t nWet = 0u;
    double wetMass = 0.0;
    for (int c = 0; c < nc; ++c) {
        const std::size_t k = static_cast<std::size_t>(c);
        // 0490m/0490n validated production subset is periodic and wall-free, so
        // every grid cell is active. Occupied wet-mask mode remains supported.
        const bool active = true;
        const bool wet = active &&
            (params.resamplingWetMaskMode != "occupied" ||
             ws.mass[k] > params.resamplingWetCellMassThreshold);
        ws.activeCell[k] = active ? 1u : 0u;
        ws.wetCell[k] = wet ? 1u : 0u;
        ws.dryCell[k] = wet ? 0u : 1u;
        if (wet) {
            ++nWet;
            wetMass += ws.mass[k];
        }
    }
    d.targetCellMass = params.resamplingTargetCellMass > 0.0
        ? params.resamplingTargetCellMass
        : (nWet > 0u ? wetMass / static_cast<double>(nWet) : d.meanMass);
    d.cellClassificationComputed = true;
    d.nActiveCells = static_cast<std::uint64_t>(nc);
    d.nWetCells = nWet;
    d.nDryCells = static_cast<std::uint64_t>(nc) - nWet;
    d.wetMassThreshold = params.resamplingWetCellMassThreshold;
    d.poorMassThreshold = d.targetCellMass * params.resamplingPoorCellMassFraction;
    d.richMassThreshold = d.targetCellMass * params.resamplingRichCellMassFraction;
    d.wetCellFraction = static_cast<double>(nWet) * invNc;
    d.dryCellFraction = static_cast<double>(d.nDryCells) * invNc;

    double rel2 = 0.0;
    double relMax = 0.0;
    double receiverDeficit = 0.0;
    double donorExcess = 0.0;
    for (int c = 0; c < nc; ++c) {
        const std::size_t k = static_cast<std::size_t>(c);
        if (!ws.wetCell[k] || !(d.targetCellMass > 0.0)) continue;
        const double mc = ws.mass[k];
        const double rel = (mc - d.targetCellMass) / d.targetCellMass;
        rel2 += rel * rel;
        relMax = std::max(relMax, std::abs(rel));
        const bool poor = mc < d.poorMassThreshold;
        const bool rich = mc > d.richMassThreshold;
        ws.poorCell[k] = poor ? 1u : 0u;
        ws.richCell[k] = rich ? 1u : 0u;
        ws.targetBandCell[k] = (!poor && !rich) ? 1u : 0u;
        if (poor) {
            ++d.nPoorCells;
            ws.receiverPoorCells.push_back(c);
            receiverDeficit += std::max(0.0, d.targetCellMass - mc);
            if (ws.count[k] == 0u) ws.emptyWetReceiverCells.push_back(c);
        } else if (rich) {
            ++d.nRichCells;
            ws.donorRichCells.push_back(c);
            donorExcess += std::max(0.0, mc - d.targetCellMass);
        } else {
            ++d.nTargetBandCells;
        }
        if (ws.count[k] == 0u) ++d.nEmptyWetCells;
    }
    const double invWet = nWet > 0u ? 1.0 / static_cast<double>(nWet) : 0.0;
    d.mRelRms = std::sqrt(rel2 * invWet);
    d.mRelMaxAbs = relMax;
    d.poorCellFraction = static_cast<double>(d.nPoorCells) * invWet;
    d.richCellFraction = static_cast<double>(d.nRichCells) * invWet;
    d.emptyWetCellFraction = static_cast<double>(d.nEmptyWetCells) * invWet;
    d.candidateListsBuilt = true;
    d.nReceiverCells = static_cast<std::uint64_t>(ws.receiverPoorCells.size());
    d.nDonorCells = static_cast<std::uint64_t>(ws.donorRichCells.size());
    d.nEmptyWetReceiverCells = static_cast<std::uint64_t>(ws.emptyWetReceiverCells.size());
    if (!ws.receiverPoorCells.empty()) {
        d.firstReceiverCell = ws.receiverPoorCells.front();
        d.lastReceiverCell = ws.receiverPoorCells.back();
    }
    if (!ws.donorRichCells.empty()) {
        d.firstDonorCell = ws.donorRichCells.front();
        d.lastDonorCell = ws.donorRichCells.back();
    }
    d.receiverMassDeficitToTarget = receiverDeficit;
    d.donorMassExcessAboveTarget = donorExcess;
    d.donorReceiverMassBalance = donorExcess - receiverDeficit;
    d.potentialTransferMass = std::min(receiverDeficit, donorExcess);
    d.receiverFractionOfWetCells = static_cast<double>(d.nReceiverCells) * invWet;
    d.donorFractionOfWetCells = static_cast<double>(d.nDonorCells) * invWet;
    d.poolCanSeedReceivers = md.inactiveSlots > 0u;

    md.nonEmptyCells = nonEmpty;
    md.wetCells = nWet;
    md.poorCells = d.nPoorCells;
    md.richCells = d.nRichCells;
    md.receiverCells = d.nReceiverCells;
    md.donorCells = d.nDonorCells;
    md.totalMass = d.totalMass;
    md.totalPx = d.totalPx;
    md.totalPy = d.totalPy;
    md.targetCellMass = d.targetCellMass;
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
    }
#endif
    if (impl_ != nullptr) *impl_ = Impl{};
}

void CudaSpeciesResidentMaintenanceWorkspace0490n::ensure_capacity(
    std::uint64_t particles,
    CudaSpeciesResidentMaintenanceDiagnostics0490n* diagnostics) {
#if !defined(MPCD_ENABLE_CUDA_PARTICLE_STATE) || !defined(MPCD_ENABLE_CUDA_CELL_WORKSPACE)
    (void)particles;
    (void)diagnostics;
    throw std::runtime_error("0490n CUDA workspace requires CUDA particle/cell support");
#else
    if (particles == 0u) particles = 1u;
    if (impl_ == nullptr) throw std::runtime_error("0490n workspace has null impl");
    const bool reuse = impl_->capacity >= particles;
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

        if (refreshPool) {
            maintenanceWorkspace.ensure_capacity(state.Np, &d);
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
            const Clock0490n::time_point download0 = Clock0490n::now();
            CudaSpeciesCellFields0490h downloaded = cuda_download_species_cell_fields_0490h(
                speciesWorkspace, params.speciesDefinitions, &deposit);
            d.compactDownloadSeconds += seconds_since_0490n(download0);
            if (downloaded.invalidTypeCount != 0u) {
                throw std::runtime_error("0490n resident deposit found unregistered particle types");
            }
            d.cellMirrorDownloadBytes =
                static_cast<std::uint64_t>(downloaded.count.size()) * sizeof(std::uint32_t) +
                static_cast<std::uint64_t>(downloaded.mass.size() + downloaded.px.size() +
                                           downloaded.py.size()) * sizeof(double);
            if (!refreshPool) {
                // Role counts are still needed in legacy diagnostics. In the
                // validated active-prefix path NactiveFluid is authoritative and
                // the dormant tail contains no latent slots.
                d.fluidSlots = state.NactiveFluid;
                d.latentSlots = 0u;
                d.inactiveSlots = state.Np >= state.NactiveFluid
                    ? state.Np - state.NactiveFluid : 0u;
            }
            const Clock0490n::time_point mirror0 = Clock0490n::now();
            depositDiagnostics = WeightedResamplingDiagnostics{};
            build_host_cell_policy_mirror_0490n(
                params, grid, domain, time, downloaded,
                depositMirror, depositDiagnostics, d);
            d.hostCellMirrorSeconds = seconds_since_0490n(mirror0);
        }

        d.allocatedBytes = maintenanceWorkspace.allocated_bytes() +
                           speciesWorkspace.allocated_bytes();
        d.handled = true;
        d.pass = d.invalidRoleSlots == 0u && d.activePrefixViolations == 0u &&
                 d.duplicateFreeSlots == 0u && d.activeAndFreeSlots == 0u &&
                 d.maxCellMassMirrorError <= params.speciesCellCudaComparisonTolerance &&
                 (!refreshDeposit || depositDiagnostics.computed) &&
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
