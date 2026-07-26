#include "cuda_species_resampling_fast_path_0490m.h"

#include "cuda_shared_particle_state_0251.h"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <stdexcept>
#include <string>
#include <type_traits>
#include <utility>
#include <vector>

#if defined(MPCD_ENABLE_CUDA_PARTICLE_STATE) && defined(MPCD_ENABLE_CUDA_CELL_WORKSPACE)
#include <cuda_runtime.h>
#endif

namespace mpcd {
namespace {

using Clock0490m = std::chrono::steady_clock;

double seconds_since_0490m(const Clock0490m::time_point& t0) {
    return std::chrono::duration<double>(Clock0490m::now() - t0).count();
}

void append_csv_0490m(const SimulationParams& params,
                      const CudaSpeciesResamplingFastPathDiagnostics0490m& d) {
    if (params.outputDir.empty() ||
        params.speciesCudaResidentFastPathDiagnosticsFilename.empty()) return;
    const std::filesystem::path path =
        std::filesystem::path(params.outputDir) /
        params.speciesCudaResidentFastPathDiagnosticsFilename;
    std::filesystem::create_directories(path.parent_path());
    const bool header = !std::filesystem::exists(path) ||
                        std::filesystem::file_size(path) == 0u;
    std::ofstream out(path, std::ios::app);
    if (!out) throw std::runtime_error("0490m failed to open diagnostics CSV: " + path.string());
    if (header) {
        out << "step,attempted,handled,applied,pass,skipped,skipReason,particlesScanned,planEntries,operations,"
               "invalidOperations,disabledSpeciesMutationCount,typeRejectedCandidates,usedSharedResidentState,particleUploadSkipped,workspaceReused,"
               "directDevicePlanHandoff,planArrayDownloadSkipped,planArrayUploadSkipped,operationRoundTripSkipped,"
               "fullStateCopySkipped,fullStateDownloadSkipped,allocatedBytes,allocationCalls,compactPatchbackBytes,"
               "movedMass,movedMomentumX,movedMomentumY,stateUploadSeconds,kernelSeconds,scalarDownloadSeconds,"
               "patchbackDownloadSeconds,hostPatchbackSeconds,totalSeconds,entryMassShortfalls,"
               "donorTypeGroupUnderfills,plannedMass,selectedMass,selectedMassCoverageFraction\n";
    }
    out << std::setprecision(17)
        << d.step << ',' << (d.attempted ? 1 : 0) << ',' << (d.handled ? 1 : 0) << ','
        << (d.applied ? 1 : 0) << ',' << (d.pass ? 1 : 0) << ',' << (d.skipped ? 1 : 0) << ','
        << '"' << d.skipReason << '"' << ','
        << d.particlesScanned << ',' << d.planEntries << ',' << d.operations << ','
        << d.invalidOperations << ',' << d.disabledSpeciesMutationCount << ','
        << d.typeRejectedCandidates << ',' << d.usedSharedResidentState << ',' << d.particleUploadSkipped << ',' << d.workspaceReused << ','
        << d.directDevicePlanHandoff << ',' << d.planArrayDownloadSkipped << ','
        << d.planArrayUploadSkipped << ',' << d.operationRoundTripSkipped << ','
        << d.fullStateCopySkipped << ',' << d.fullStateDownloadSkipped << ','
        << d.allocatedBytes << ',' << d.allocationCalls << ',' << d.compactPatchbackBytes << ','
        << d.movedMass << ',' << d.movedMomentumX << ',' << d.movedMomentumY << ','
        << d.stateUploadSeconds << ',' << d.kernelSeconds << ',' << d.scalarDownloadSeconds << ','
        << d.patchbackDownloadSeconds << ',' << d.hostPatchbackSeconds << ',' << d.totalSeconds << ','
        << d.entryMassShortfalls << ',' << d.donorTypeGroupUnderfills << ','
        << d.plannedMass << ',' << d.selectedMass << ','
        << d.selectedMassCoverageFraction << '\n';
}

#if defined(MPCD_ENABLE_CUDA_PARTICLE_STATE) && defined(MPCD_ENABLE_CUDA_CELL_WORKSPACE)
#define MPCD_CUDA_0490M_CHECK(call) do { \
    const cudaError_t err__ = (call); \
    if (err__ != cudaSuccess) { \
        throw std::runtime_error(std::string("CUDA error in ") + #call + ": " + \
                                 cudaGetErrorString(err__)); \
    } \
} while (0)

template <typename T>
void cuda_free_0490m(T*& ptr) {
    if (ptr != nullptr) {
        cudaFree(ptr);
        ptr = nullptr;
    }
}

__device__ int particle_cell_0490m(double x,
                                   double y,
                                   int nx,
                                   int ny,
                                   double dx,
                                   double dy,
                                   int periodicX,
                                   int periodicY) {
    if (nx <= 0 || ny <= 0 || !(dx > 0.0) || !(dy > 0.0)) return -1;
    int ix = static_cast<int>(floor(x / dx));
    int iy = static_cast<int>(floor(y / dy));
    if (periodicX) {
        while (ix < 0) ix += nx;
        while (ix >= nx) ix -= nx;
    } else {
        if (ix < 0) ix = 0;
        if (ix >= nx) ix = nx - 1;
    }
    if (periodicY) {
        while (iy < 0) iy += ny;
        while (iy >= ny) iy -= ny;
    } else {
        if (iy < 0) iy = 0;
        if (iy >= ny) iy = ny - 1;
    }
    return iy * nx + ix;
}

__device__ int species_index_0493b(
    std::uint32_t type, int speciesCount, const std::uint32_t* speciesTypes) {
    for (int s = 0; s < speciesCount; ++s) {
        if (speciesTypes[s] == type) return s;
    }
    return -1;
}

// 0493d deterministic parallel resident consumer.
//
// A particle can only be selected by transfer entries sharing its original
// (donor cell, particle type) pair. Different donor/type groups are therefore
// independent. One CUDA thread owns each first entry of a donor/type group,
// processes that group's entries in original plan order, and consumes matching
// particles in ascending active-particle order. A later device prefix over plan
// entries reconstructs the exact global operation order used by the historical
// serial algorithm, including the sub-cell placement phase q = operation & 15.
__global__ void assign_species_plan_groups_0493d(
    int planCapacity,
    const unsigned int* planCount,
    const int* planDonor,
    const int* planReceiver,
    const std::uint32_t* planType,
    const double* planMass,
    std::uint64_t nParticles,
    std::uint64_t nActive,
    int nx,
    int ny,
    double dx,
    double dy,
    int periodicX,
    int periodicY,
    int speciesCount,
    const std::uint32_t* speciesTypes,
    const unsigned char* resamplingEnabled,
    std::uint8_t fluidRole,
    const double* x,
    const double* y,
    const double* mass,
    const std::uint32_t* type,
    const unsigned char* role,
    int* assignedEntry,
    unsigned int* assignedLocalIndex,
    unsigned int* entrySelectedCount,
    double* entrySelectedMass,
    unsigned char* entryShortfall,
    unsigned char* groupFirst,
    unsigned char* groupUnderfill) {
    const unsigned int e0 = blockIdx.x * blockDim.x + threadIdx.x;
    unsigned int entries = planCount != nullptr ? *planCount : 0u;
    if (entries > static_cast<unsigned int>(planCapacity)) {
        entries = static_cast<unsigned int>(planCapacity);
    }
    if (e0 >= entries) return;

    constexpr double eps = 1.0e-14;
    const int donor = planDonor[e0];
    const int receiver = planReceiver[e0];
    const std::uint32_t wantedType = planType[e0];
    const double wantedMass = planMass[e0];
    if (donor < 0 || receiver < 0 || !(wantedMass > eps)) return;

    const int wantedSpecies = species_index_0493b(
        wantedType, speciesCount, speciesTypes);
    if (wantedSpecies < 0 || resamplingEnabled[wantedSpecies] == 0u) return;

    // Exactly one thread owns each valid donor/type group: the earliest valid
    // plan entry for that pair. Interleaving with other groups is immaterial to
    // selection because original donor/type memberships are disjoint.
    for (unsigned int f = 0u; f < e0; ++f) {
        if (planDonor[f] == donor && planReceiver[f] >= 0 &&
            planType[f] == wantedType && planMass[f] > eps) {
            return;
        }
    }
    groupFirst[e0] = 1u;

    std::uint64_t particleCursor = 0u;
    double plannedGroup = 0.0;
    double selectedGroup = 0.0;

    for (unsigned int e = e0; e < entries; ++e) {
        if (planDonor[e] != donor || planReceiver[e] < 0 ||
            planType[e] != wantedType || !(planMass[e] > eps)) {
            continue;
        }

        const double target = planMass[e];
        plannedGroup += target;
        double gathered = 0.0;
        unsigned int localCount = 0u;

        // Continuing the cursor is exactly equivalent to restarting at zero and
        // skipping particles selected by earlier entries in this group.
        while (particleCursor < nActive && gathered + eps < target) {
            const std::uint64_t p = particleCursor++;
            if (p >= nParticles || role[p] != fluidRole) continue;
            const int cell = particle_cell_0490m(
                x[p], y[p], nx, ny, dx, dy, periodicX, periodicY);
            if (cell != donor || type[p] != wantedType) continue;
            const double mp = mass[p];
            if (!(mp > 0.0) || !isfinite(mp)) continue;

            assignedEntry[p] = static_cast<int>(e);
            assignedLocalIndex[p] = localCount;
            ++localCount;
            gathered += mp;
            selectedGroup += mp;
        }

        entrySelectedCount[e] = localCount;
        entrySelectedMass[e] = gathered;
        if (gathered + eps < target) entryShortfall[e] = 1u;
    }

    if (selectedGroup + eps < plannedGroup) groupUnderfill[e0] = 1u;
}

// Preserve the historical typeRejectedCandidates diagnostic exactly. The
// assignment map identifies particles consumed by earlier global plan entries,
// reproducing the original selected[p] gate before donor/type inspection.
__global__ void count_type_rejections_0493d(
    int planCapacity,
    const unsigned int* planCount,
    const int* planDonor,
    const int* planReceiver,
    const std::uint32_t* planType,
    const double* planMass,
    std::uint64_t nParticles,
    std::uint64_t nActive,
    int nx,
    int ny,
    double dx,
    double dy,
    int periodicX,
    int periodicY,
    int speciesCount,
    const std::uint32_t* speciesTypes,
    const unsigned char* resamplingEnabled,
    std::uint8_t fluidRole,
    const int* assignedEntry,
    unsigned long long* entryTypeRejected,
    const double* x,
    const double* y,
    const double* mass,
    const std::uint32_t* type,
    const unsigned char* role) {
    const unsigned int e = blockIdx.x * blockDim.x + threadIdx.x;
    unsigned int entries = planCount != nullptr ? *planCount : 0u;
    if (entries > static_cast<unsigned int>(planCapacity)) {
        entries = static_cast<unsigned int>(planCapacity);
    }
    if (e >= entries) return;

    constexpr double eps = 1.0e-14;
    const int donor = planDonor[e];
    const int receiver = planReceiver[e];
    const std::uint32_t wantedType = planType[e];
    const double target = planMass[e];
    if (donor < 0 || receiver < 0 || !(target > eps)) return;
    const int wantedSpecies = species_index_0493b(
        wantedType, speciesCount, speciesTypes);
    if (wantedSpecies < 0 || resamplingEnabled[wantedSpecies] == 0u) return;

    unsigned long long rejected = 0u;
    double gathered = 0.0;
    for (std::uint64_t p = 0u; p < nActive; ++p) {
        if (p >= nParticles || role[p] != fluidRole) continue;
        const int owner = assignedEntry[p];
        if (owner >= 0 && static_cast<unsigned int>(owner) < e) continue;
        const int cell = particle_cell_0490m(
            x[p], y[p], nx, ny, dx, dy, periodicX, periodicY);
        if (cell != donor) continue;
        if (type[p] != wantedType) {
            ++rejected;
            continue;
        }
        const double mp = mass[p];
        if (!(mp > 0.0) || !isfinite(mp)) continue;
        if (owner == static_cast<int>(e)) {
            gathered += mp;
            if (gathered + eps >= target) break;
        }
    }
    entryTypeRejected[e] = rejected;
}

// A serial device prefix over O(plan entries), not O(particles x entries).
// This reconstructs the exact historical global operation order while keeping
// all plan and operation arrays resident on the GPU.
__global__ void finalize_species_plan_offsets_0493d(
    int planCapacity,
    const unsigned int* planCount,
    const unsigned int* planOverflow,
    const int* planDonor,
    const int* planReceiver,
    const std::uint32_t* planType,
    const double* planMass,
    int speciesCount,
    const std::uint32_t* speciesTypes,
    const unsigned char* resamplingEnabled,
    unsigned int maxOps,
    const unsigned int* entrySelectedCount,
    const unsigned char* entryShortfall,
    const unsigned char* groupFirst,
    const unsigned char* groupUnderfill,
    const unsigned long long* entryTypeRejected,
    unsigned int* entryOpOffset,
    unsigned int* outCount,
    unsigned int* outInvalid,
    unsigned long long* outDisabledSpeciesMutation,
    unsigned int* outEntryShortfalls,
    unsigned int* outGroupUnderfills,
    unsigned long long* outTypeRejected,
    double* outPlannedMass) {
    if (blockIdx.x != 0 || threadIdx.x != 0) return;
    constexpr double eps = 1.0e-14;

    const unsigned int rawEntries = planCount != nullptr ? *planCount : 0u;
    unsigned int entries = rawEntries;
    unsigned int invalid = 0u;
    if (entries > static_cast<unsigned int>(planCapacity)) {
        entries = static_cast<unsigned int>(planCapacity);
        ++invalid;
    }
    if (planOverflow != nullptr) invalid += *planOverflow;

    unsigned int operations = 0u;
    unsigned int shortfalls = 0u;
    unsigned int groupUnderfills = 0u;
    unsigned long long disabled = 0u;
    unsigned long long rejected = 0u;
    double plannedMassTotal = 0.0;

    for (unsigned int e = 0u; e < entries; ++e) {
        entryOpOffset[e] = operations;
        const int donor = planDonor[e];
        const int receiver = planReceiver[e];
        const std::uint32_t wantedType = planType[e];
        const double wantedMass = planMass[e];
        if (donor < 0 || receiver < 0 || !(wantedMass > eps)) continue;
        const int wantedSpecies = species_index_0493b(
            wantedType, speciesCount, speciesTypes);
        if (wantedSpecies < 0) {
            ++invalid;
            continue;
        }
        if (resamplingEnabled[wantedSpecies] == 0u) {
            ++disabled;
            continue;
        }
        plannedMassTotal += wantedMass;
        operations += entrySelectedCount[e];
        shortfalls += entryShortfall[e] != 0u ? 1u : 0u;
        rejected += entryTypeRejected[e];
        if (groupFirst[e] != 0u && groupUnderfill[e] != 0u) {
            ++groupUnderfills;
        }
    }

    if (operations > maxOps) ++invalid;
    invalid += groupUnderfills;
    *outCount = operations;
    *outInvalid = invalid;
    *outDisabledSpeciesMutation = disabled;
    *outEntryShortfalls = shortfalls;
    *outGroupUnderfills = groupUnderfills;
    *outTypeRejected = rejected;
    *outPlannedMass = plannedMassTotal;
}

__global__ void materialize_assigned_species_particles_0493d_fix1(
    std::uint64_t nParticles,
    std::uint64_t nActive,
    unsigned int maxOps,
    const int* assignedEntry,
    const unsigned int* assignedLocalIndex,
    const unsigned int* entryOpOffset,
    const int* planDonor,
    const int* planReceiver,
    const std::uint32_t* planType,
    unsigned int* outParticle,
    int* outDonor,
    int* outReceiver,
    std::uint32_t* outType) {
    const std::uint64_t p =
        static_cast<std::uint64_t>(blockIdx.x) * blockDim.x + threadIdx.x;
    if (p >= nActive || p >= nParticles) return;
    const int e = assignedEntry[p];
    if (e < 0) return;

    const unsigned int op = entryOpOffset[e] + assignedLocalIndex[p];
    if (op >= maxOps) return;
    outParticle[op] = static_cast<unsigned int>(p);
    outDonor[op] = planDonor[e];
    outReceiver[op] = planReceiver[e];
    outType[op] = planType[e];
}

// 0493d-fix1: preserve the historical state-update arithmetic and operation
// order exactly. Selection remains parallel by independent donor/type groups,
// but all particle mutations and diagnostic reductions are replayed by one
// device thread in global plan/particle order, as in the original 0490m kernel.
// This O(number of operations) serial tail is small; the removed pathological
// cost was the O(plan entries x active particles) serial search.
__global__ void apply_materialized_species_operations_serial_0493d_fix1(
    const unsigned int* outCount,
    unsigned int maxOps,
    std::uint64_t nParticles,
    std::uint64_t nActive,
    int nx,
    double dx,
    double dy,
    std::uint8_t fluidRole,
    unsigned int* outInvalid,
    double* outSelectedMass,
    double* outMovedPx,
    double* outMovedPy,
    unsigned int* outFirstParticle,
    unsigned int* outLastParticle,
    int* outFirstReceiver,
    int* outLastReceiver,
    const unsigned int* outParticle,
    const int* outReceiver,
    const std::uint32_t* outType,
    double* outMass,
    double* outPx,
    double* outPy,
    double* x,
    double* y,
    double* vx,
    double* vy,
    double* mass,
    std::uint32_t* type,
    unsigned char* role) {
    if (blockIdx.x != 0 || threadIdx.x != 0) return;
    unsigned int operations = outCount != nullptr ? *outCount : 0u;
    if (operations > maxOps) operations = maxOps;

    unsigned int invalid = outInvalid != nullptr ? *outInvalid : 0u;
    double selectedMass = 0.0;
    double movedPx = 0.0;
    double movedPy = 0.0;
    unsigned int firstParticle = 0xffffffffu;
    unsigned int lastParticle = 0xffffffffu;
    int firstReceiver = -1;
    int lastReceiver = -1;

    for (unsigned int op = 0u; op < operations; ++op) {
        const unsigned int p = outParticle[op];
        const int receiver = outReceiver[op];
        const std::uint32_t wantedType = outType[op];
        if (p >= nActive || p >= nParticles || receiver < 0) {
            ++invalid;
            continue;
        }
        const double mp = mass[p];
        if (!(mp > 0.0) || !isfinite(mp)) {
            ++invalid;
            continue;
        }
        const double px = mp * vx[p];
        const double py = mp * vy[p];
        outMass[op] = mp;
        outPx[op] = px;
        outPy[op] = py;

        const unsigned int c = static_cast<unsigned int>(receiver);
        const unsigned int ix = c % static_cast<unsigned int>(nx);
        const unsigned int iy = c / static_cast<unsigned int>(nx);
        const unsigned int q = op & 15u;
        const double fx = 0.2 + 0.2 * static_cast<double>(q & 3u);
        const double fy = 0.2 + 0.2 * static_cast<double>(q >> 2u);
        x[p] = (static_cast<double>(ix) + fx) * dx;
        y[p] = (static_cast<double>(iy) + fy) * dy;
        mass[p] = mp;
        type[p] = wantedType;
        vx[p] = px / mp;
        vy[p] = py / mp;
        role[p] = fluidRole;

        if (firstParticle == 0xffffffffu) {
            firstParticle = p;
            firstReceiver = receiver;
        }
        lastParticle = p;
        lastReceiver = receiver;
        selectedMass += mp;
        movedPx += px;
        movedPy += py;
    }

    *outInvalid = invalid;
    *outSelectedMass = selectedMass;
    *outMovedPx = movedPx;
    *outMovedPy = movedPy;
    *outFirstParticle = firstParticle;
    *outLastParticle = lastParticle;
    *outFirstReceiver = firstReceiver;
    *outLastReceiver = lastReceiver;
}
#endif

} // namespace

struct CudaSpeciesResamplingFastPathWorkspace0490m::Impl {
    std::uint64_t capacity = 0u;
    int planCapacity = 0;
    std::uint64_t allocatedBytes = 0u;
#if defined(MPCD_ENABLE_CUDA_PARTICLE_STATE) && defined(MPCD_ENABLE_CUDA_CELL_WORKSPACE)
    int* assignedEntry = nullptr;
    unsigned int* assignedLocalIndex = nullptr;
    unsigned int* entrySelectedCount = nullptr;
    unsigned int* entryOpOffset = nullptr;
    double* entrySelectedMass = nullptr;
    unsigned char* entryShortfall = nullptr;
    unsigned char* groupFirst = nullptr;
    unsigned char* groupUnderfill = nullptr;
    unsigned long long* entryTypeRejected = nullptr;
    unsigned int* outCount = nullptr;
    unsigned int* outInvalid = nullptr;
    unsigned long long* outDisabledSpeciesMutation = nullptr;
    unsigned int* outEntryShortfalls = nullptr;
    unsigned int* outGroupUnderfills = nullptr;
    unsigned long long* outTypeRejected = nullptr;
    double* outPlannedMass = nullptr;
    double* outSelectedMass = nullptr;
    double* outMovedPx = nullptr;
    double* outMovedPy = nullptr;
    unsigned int* outFirstParticle = nullptr;
    unsigned int* outLastParticle = nullptr;
    int* outFirstReceiver = nullptr;
    int* outLastReceiver = nullptr;
    unsigned int* outParticle = nullptr;
    int* outDonor = nullptr;
    int* outReceiver = nullptr;
    std::uint32_t* outType = nullptr;
    double* outMass = nullptr;
    double* outPx = nullptr;
    double* outPy = nullptr;
#endif
};

CudaSpeciesResamplingFastPathWorkspace0490m::CudaSpeciesResamplingFastPathWorkspace0490m()
    : impl_(new Impl()) {}

CudaSpeciesResamplingFastPathWorkspace0490m::~CudaSpeciesResamplingFastPathWorkspace0490m() {
    release();
    delete impl_;
    impl_ = nullptr;
}

CudaSpeciesResamplingFastPathWorkspace0490m::CudaSpeciesResamplingFastPathWorkspace0490m(
    CudaSpeciesResamplingFastPathWorkspace0490m&& other) noexcept
    : impl_(other.impl_) {
    other.impl_ = new Impl();
}

CudaSpeciesResamplingFastPathWorkspace0490m&
CudaSpeciesResamplingFastPathWorkspace0490m::operator=(
    CudaSpeciesResamplingFastPathWorkspace0490m&& other) noexcept {
    if (this != &other) {
        release();
        delete impl_;
        impl_ = other.impl_;
        other.impl_ = new Impl();
    }
    return *this;
}

void CudaSpeciesResamplingFastPathWorkspace0490m::release() {
#if defined(MPCD_ENABLE_CUDA_PARTICLE_STATE) && defined(MPCD_ENABLE_CUDA_CELL_WORKSPACE)
    if (impl_ != nullptr) {
        cuda_free_0490m(impl_->assignedEntry);
        cuda_free_0490m(impl_->assignedLocalIndex);
        cuda_free_0490m(impl_->entrySelectedCount);
        cuda_free_0490m(impl_->entryOpOffset);
        cuda_free_0490m(impl_->entrySelectedMass);
        cuda_free_0490m(impl_->entryShortfall);
        cuda_free_0490m(impl_->groupFirst);
        cuda_free_0490m(impl_->groupUnderfill);
        cuda_free_0490m(impl_->entryTypeRejected);
        cuda_free_0490m(impl_->outCount);
        cuda_free_0490m(impl_->outInvalid);
        cuda_free_0490m(impl_->outDisabledSpeciesMutation);
        cuda_free_0490m(impl_->outEntryShortfalls);
        cuda_free_0490m(impl_->outGroupUnderfills);
        cuda_free_0490m(impl_->outTypeRejected);
        cuda_free_0490m(impl_->outPlannedMass);
        cuda_free_0490m(impl_->outSelectedMass);
        cuda_free_0490m(impl_->outMovedPx);
        cuda_free_0490m(impl_->outMovedPy);
        cuda_free_0490m(impl_->outFirstParticle);
        cuda_free_0490m(impl_->outLastParticle);
        cuda_free_0490m(impl_->outFirstReceiver);
        cuda_free_0490m(impl_->outLastReceiver);
        cuda_free_0490m(impl_->outParticle);
        cuda_free_0490m(impl_->outDonor);
        cuda_free_0490m(impl_->outReceiver);
        cuda_free_0490m(impl_->outType);
        cuda_free_0490m(impl_->outMass);
        cuda_free_0490m(impl_->outPx);
        cuda_free_0490m(impl_->outPy);
    }
#endif
    if (impl_ != nullptr) *impl_ = Impl{};
}

void CudaSpeciesResamplingFastPathWorkspace0490m::ensure_capacity(
    std::uint64_t activeParticles,
    int planCapacity,
    CudaSpeciesResamplingFastPathDiagnostics0490m* diagnostics) {
#if !defined(MPCD_ENABLE_CUDA_PARTICLE_STATE) || !defined(MPCD_ENABLE_CUDA_CELL_WORKSPACE)
    (void)activeParticles; (void)planCapacity; (void)diagnostics;
    throw std::runtime_error("0490m CUDA workspace requires CUDA particle/cell support");
#else
    if (activeParticles == 0u) activeParticles = 1u;
    if (planCapacity <= 0) planCapacity = 1;
    if (impl_ == nullptr) throw std::runtime_error("0490m workspace has null impl");
    const bool reuse = impl_->capacity >= activeParticles &&
                       impl_->planCapacity >= planCapacity;
    if (diagnostics) diagnostics->workspaceReused = reuse ? 1 : 0;
    if (reuse) {
        if (diagnostics) diagnostics->allocatedBytes = impl_->allocatedBytes;
        return;
    }
    release();
    std::uint64_t bytes = 0u;
    auto alloc = [&](auto*& ptr, std::uint64_t count) {
        using T = std::remove_pointer_t<std::remove_reference_t<decltype(ptr)>>;
        MPCD_CUDA_0490M_CHECK(cudaMalloc(reinterpret_cast<void**>(&ptr),
                                         static_cast<std::size_t>(count) * sizeof(T)));
        bytes += count * static_cast<std::uint64_t>(sizeof(T));
    };
    const std::uint64_t planEntries = static_cast<std::uint64_t>(planCapacity);
    alloc(impl_->assignedEntry, activeParticles);
    alloc(impl_->assignedLocalIndex, activeParticles);
    alloc(impl_->entrySelectedCount, planEntries);
    alloc(impl_->entryOpOffset, planEntries);
    alloc(impl_->entrySelectedMass, planEntries);
    alloc(impl_->entryShortfall, planEntries);
    alloc(impl_->groupFirst, planEntries);
    alloc(impl_->groupUnderfill, planEntries);
    alloc(impl_->entryTypeRejected, planEntries);
    alloc(impl_->outCount, 1u);
    alloc(impl_->outInvalid, 1u);
    alloc(impl_->outDisabledSpeciesMutation, 1u);
    alloc(impl_->outEntryShortfalls, 1u);
    alloc(impl_->outGroupUnderfills, 1u);
    alloc(impl_->outTypeRejected, 1u);
    alloc(impl_->outPlannedMass, 1u);
    alloc(impl_->outSelectedMass, 1u);
    alloc(impl_->outMovedPx, 1u);
    alloc(impl_->outMovedPy, 1u);
    alloc(impl_->outFirstParticle, 1u);
    alloc(impl_->outLastParticle, 1u);
    alloc(impl_->outFirstReceiver, 1u);
    alloc(impl_->outLastReceiver, 1u);
    alloc(impl_->outParticle, activeParticles);
    alloc(impl_->outDonor, activeParticles);
    alloc(impl_->outReceiver, activeParticles);
    alloc(impl_->outType, activeParticles);
    alloc(impl_->outMass, activeParticles);
    alloc(impl_->outPx, activeParticles);
    alloc(impl_->outPy, activeParticles);
    impl_->capacity = activeParticles;
    impl_->planCapacity = planCapacity;
    impl_->allocatedBytes = bytes;
    if (diagnostics) {
        diagnostics->allocationCalls += 1u;
        diagnostics->allocatedBytes = bytes;
    }
#endif
}

std::uint64_t CudaSpeciesResamplingFastPathWorkspace0490m::capacity() const {
    return impl_ ? impl_->capacity : 0u;
}

std::uint64_t CudaSpeciesResamplingFastPathWorkspace0490m::allocated_bytes() const {
    return impl_ ? impl_->allocatedBytes : 0u;
}

bool cuda_species_resampling_fast_path_available_0490m() {
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

CudaSpeciesResamplingFastPathDiagnostics0490m
try_apply_cuda_species_resampling_fast_path_0490m(
    ParticleState& state,
    const SimulationParams& params,
    const CellGrid& grid,
    std::uint64_t step,
    const CudaSpeciesTransferPlanWorkspace0490k& planWorkspace,
    const CudaSpeciesCellWorkspace0490h& speciesWorkspace,
    CudaSpeciesResamplingFastPathWorkspace0490m& fastWorkspace,
    ResamplingExtractionApplyDiagnostics& extractionApply,
    ResamplingInsertionApplyDiagnostics& insertionApply) {
    CudaSpeciesResamplingFastPathDiagnostics0490m d{};
    d.attempted = true;
    d.step = step;
    d.particlesScanned = state.NactiveFluid;
    d.directDevicePlanHandoff = 1;
    d.planArrayDownloadSkipped = 1;
    d.planArrayUploadSkipped = 1;
    d.operationRoundTripSkipped = 1;
    d.fullStateCopySkipped = 1;
    d.fullStateDownloadSkipped = 1;
    const Clock0490m::time_point total0 = Clock0490m::now();

#if !defined(MPCD_ENABLE_CUDA_PARTICLE_STATE) || !defined(MPCD_ENABLE_CUDA_CELL_WORKSPACE)
    (void)state; (void)params; (void)grid; (void)planWorkspace; (void)speciesWorkspace; (void)fastWorkspace;
    (void)extractionApply; (void)insertionApply;
    d.skipped = true;
    d.skipReason = "CUDA particle/cell support is not compiled";
    d.totalSeconds = seconds_since_0490m(total0);
    append_csv_0490m(params, d);
    return d;
#else
    try {
        if (!params.speciesResamplingCudaResidentFastPathEnable) {
            d.skipped = true;
            d.skipReason = "0490m fast path disabled";
            d.totalSeconds = seconds_since_0490m(total0);
            append_csv_0490m(params, d);
            return d;
        }
        if (!cuda_species_resampling_fast_path_available_0490m()) {
            throw std::runtime_error("0490m requested but no CUDA device is available");
        }
        const CudaSpeciesTransferPlanDeviceView0490m plan =
            planWorkspace.device_view_0490m();
        const CudaSpeciesCellDeviceView0490h species = speciesWorkspace.device_view();
        if (species.speciesCount <= 0 || species.speciesTypes == nullptr ||
            species.resamplingEnabled == nullptr) {
            throw std::runtime_error("0493b fast path requires resident species mutation metadata");
        }
        if (plan.capacity <= 0 || plan.donorCell == nullptr ||
            plan.receiverCell == nullptr || plan.particleType == nullptr ||
            plan.plannedMass == nullptr || plan.count == nullptr ||
            plan.overflow == nullptr) {
            throw std::runtime_error("0490m invalid resident transfer-plan device view");
        }

        CudaParticleState& particles = cuda_shared_particle_state_0251();
        CudaParticleStateDiagnostics upload{};
        if (cuda_shared_particle_state_0251_is_fresh() &&
            particles.size() == state.Np &&
            particles.active_fluid_size() == state.NactiveFluid) {
            d.usedSharedResidentState = 1;
            d.particleUploadSkipped = 1;
        } else {
            particles.upload_all(state, &upload);
            d.stateUploadSeconds = upload.uploadSeconds;
            cuda_shared_particle_state_0251_mark_fresh("species_fast_path_upload_0490m");
        }
        CudaParticleDeviceView view = particles.device_view();
        if (view.n != state.Np || view.nActiveFluid != state.NactiveFluid) {
            throw std::runtime_error("0490m shared particle state shape mismatch");
        }

        fastWorkspace.ensure_capacity(state.NactiveFluid, plan.capacity, &d);
        d.allocatedBytes = fastWorkspace.allocated_bytes();
        auto* impl = fastWorkspace.impl_;
        const std::size_t particleBytes = static_cast<std::size_t>(
            std::max<std::uint64_t>(1u, state.NactiveFluid));
        const std::size_t planBytes = static_cast<std::size_t>(
            std::max(1, plan.capacity));
        MPCD_CUDA_0490M_CHECK(cudaMemset(impl->assignedEntry, 0xff,
                                         particleBytes * sizeof(int)));
        MPCD_CUDA_0490M_CHECK(cudaMemset(impl->assignedLocalIndex, 0,
                                         particleBytes * sizeof(unsigned int)));
        MPCD_CUDA_0490M_CHECK(cudaMemset(impl->entrySelectedCount, 0,
                                         planBytes * sizeof(unsigned int)));
        MPCD_CUDA_0490M_CHECK(cudaMemset(impl->entryOpOffset, 0,
                                         planBytes * sizeof(unsigned int)));
        MPCD_CUDA_0490M_CHECK(cudaMemset(impl->entrySelectedMass, 0,
                                         planBytes * sizeof(double)));
        MPCD_CUDA_0490M_CHECK(cudaMemset(impl->entryShortfall, 0,
                                         planBytes * sizeof(unsigned char)));
        MPCD_CUDA_0490M_CHECK(cudaMemset(impl->groupFirst, 0,
                                         planBytes * sizeof(unsigned char)));
        MPCD_CUDA_0490M_CHECK(cudaMemset(impl->groupUnderfill, 0,
                                         planBytes * sizeof(unsigned char)));
        MPCD_CUDA_0490M_CHECK(cudaMemset(impl->entryTypeRejected, 0,
                                         planBytes * sizeof(unsigned long long)));
        MPCD_CUDA_0490M_CHECK(cudaMemset(impl->outCount, 0, sizeof(unsigned int)));
        MPCD_CUDA_0490M_CHECK(cudaMemset(impl->outInvalid, 0, sizeof(unsigned int)));
        MPCD_CUDA_0490M_CHECK(cudaMemset(impl->outDisabledSpeciesMutation, 0, sizeof(unsigned long long)));
        MPCD_CUDA_0490M_CHECK(cudaMemset(impl->outEntryShortfalls, 0, sizeof(unsigned int)));
        MPCD_CUDA_0490M_CHECK(cudaMemset(impl->outGroupUnderfills, 0, sizeof(unsigned int)));
        MPCD_CUDA_0490M_CHECK(cudaMemset(impl->outTypeRejected, 0, sizeof(unsigned long long)));
        MPCD_CUDA_0490M_CHECK(cudaMemset(impl->outPlannedMass, 0, sizeof(double)));
        MPCD_CUDA_0490M_CHECK(cudaMemset(impl->outSelectedMass, 0, sizeof(double)));
        MPCD_CUDA_0490M_CHECK(cudaMemset(impl->outMovedPx, 0, sizeof(double)));
        MPCD_CUDA_0490M_CHECK(cudaMemset(impl->outMovedPy, 0, sizeof(double)));
        MPCD_CUDA_0490M_CHECK(cudaMemset(impl->outFirstParticle, 0xff, sizeof(unsigned int)));
        MPCD_CUDA_0490M_CHECK(cudaMemset(impl->outLastParticle, 0xff, sizeof(unsigned int)));
        MPCD_CUDA_0490M_CHECK(cudaMemset(impl->outFirstReceiver, 0xff, sizeof(int)));
        MPCD_CUDA_0490M_CHECK(cudaMemset(impl->outLastReceiver, 0xff, sizeof(int)));

        cudaEvent_t start{}, stop{};
        MPCD_CUDA_0490M_CHECK(cudaEventCreate(&start));
        MPCD_CUDA_0490M_CHECK(cudaEventCreate(&stop));
        MPCD_CUDA_0490M_CHECK(cudaEventRecord(start));

        constexpr int planThreads = 128;
        const int planBlocks = (plan.capacity + planThreads - 1) / planThreads;
        assign_species_plan_groups_0493d<<<planBlocks, planThreads>>>(
            plan.capacity, plan.count,
            plan.donorCell, plan.receiverCell, plan.particleType, plan.plannedMass,
            view.n, view.nActiveFluid, grid.Nx, grid.Ny, grid.dx, grid.dy,
            (params.bcLeft == "periodic" && params.bcRight == "periodic") ? 1 : 0,
            (params.bcBottom == "periodic" && params.bcTop == "periodic") ? 1 : 0,
            species.speciesCount, species.speciesTypes, species.resamplingEnabled,
            static_cast<std::uint8_t>(ParticleRole::Fluid),
            view.x, view.y, view.mass, view.type, view.role,
            impl->assignedEntry, impl->assignedLocalIndex,
            impl->entrySelectedCount, impl->entrySelectedMass,
            impl->entryShortfall, impl->groupFirst, impl->groupUnderfill);
        MPCD_CUDA_0490M_CHECK(cudaGetLastError());

        count_type_rejections_0493d<<<planBlocks, planThreads>>>(
            plan.capacity, plan.count,
            plan.donorCell, plan.receiverCell, plan.particleType, plan.plannedMass,
            view.n, view.nActiveFluid, grid.Nx, grid.Ny, grid.dx, grid.dy,
            (params.bcLeft == "periodic" && params.bcRight == "periodic") ? 1 : 0,
            (params.bcBottom == "periodic" && params.bcTop == "periodic") ? 1 : 0,
            species.speciesCount, species.speciesTypes, species.resamplingEnabled,
            static_cast<std::uint8_t>(ParticleRole::Fluid),
            impl->assignedEntry, impl->entryTypeRejected,
            view.x, view.y, view.mass, view.type, view.role);
        MPCD_CUDA_0490M_CHECK(cudaGetLastError());

        finalize_species_plan_offsets_0493d<<<1, 1>>>(
            plan.capacity, plan.count, plan.overflow,
            plan.donorCell, plan.receiverCell, plan.particleType, plan.plannedMass,
            species.speciesCount, species.speciesTypes, species.resamplingEnabled,
            static_cast<unsigned int>(fastWorkspace.capacity()),
            impl->entrySelectedCount, impl->entryShortfall,
            impl->groupFirst, impl->groupUnderfill, impl->entryTypeRejected,
            impl->entryOpOffset,
            impl->outCount, impl->outInvalid, impl->outDisabledSpeciesMutation,
            impl->outEntryShortfalls, impl->outGroupUnderfills,
            impl->outTypeRejected, impl->outPlannedMass);
        MPCD_CUDA_0490M_CHECK(cudaGetLastError());

        constexpr int particleThreads = 256;
        const int particleBlocks = static_cast<int>(
            (view.nActiveFluid + particleThreads - 1u) / particleThreads);
        materialize_assigned_species_particles_0493d_fix1<<<particleBlocks, particleThreads>>>(
            view.n, view.nActiveFluid,
            static_cast<unsigned int>(fastWorkspace.capacity()),
            impl->assignedEntry, impl->assignedLocalIndex, impl->entryOpOffset,
            plan.donorCell, plan.receiverCell, plan.particleType,
            impl->outParticle, impl->outDonor, impl->outReceiver, impl->outType);
        MPCD_CUDA_0490M_CHECK(cudaGetLastError());

        apply_materialized_species_operations_serial_0493d_fix1<<<1, 1>>>(
            impl->outCount, static_cast<unsigned int>(fastWorkspace.capacity()),
            view.n, view.nActiveFluid, grid.Nx, grid.dx, grid.dy,
            static_cast<std::uint8_t>(ParticleRole::Fluid),
            impl->outInvalid,
            impl->outSelectedMass, impl->outMovedPx, impl->outMovedPy,
            impl->outFirstParticle, impl->outLastParticle,
            impl->outFirstReceiver, impl->outLastReceiver,
            impl->outParticle, impl->outReceiver, impl->outType,
            impl->outMass, impl->outPx, impl->outPy,
            view.x, view.y, view.vx, view.vy, view.mass, view.type, view.role);
        MPCD_CUDA_0490M_CHECK(cudaGetLastError());
        MPCD_CUDA_0490M_CHECK(cudaEventRecord(stop));
        MPCD_CUDA_0490M_CHECK(cudaEventSynchronize(stop));
        MPCD_CUDA_0490M_CHECK(cudaGetLastError());
        float elapsedMs = 0.0f;
        MPCD_CUDA_0490M_CHECK(cudaEventElapsedTime(&elapsedMs, start, stop));
        MPCD_CUDA_0490M_CHECK(cudaEventDestroy(start));
        MPCD_CUDA_0490M_CHECK(cudaEventDestroy(stop));
        d.kernelSeconds = static_cast<double>(elapsedMs) * 1.0e-3;

        const Clock0490m::time_point scalar0 = Clock0490m::now();
        unsigned int operations = 0u;
        unsigned int invalid = 0u;
        unsigned long long disabledSpeciesMutation = 0u;
        unsigned int entryShortfalls = 0u;
        unsigned int groupUnderfills = 0u;
        unsigned long long rejected = 0u;
        double plannedMass = 0.0;
        double selectedMass = 0.0;
        double movedPx = 0.0;
        double movedPy = 0.0;
        unsigned int firstParticle = 0xffffffffu;
        unsigned int lastParticle = 0xffffffffu;
        int firstReceiver = -1;
        int lastReceiver = -1;
        MPCD_CUDA_0490M_CHECK(cudaMemcpy(&operations, impl->outCount,
                                         sizeof(operations), cudaMemcpyDeviceToHost));
        MPCD_CUDA_0490M_CHECK(cudaMemcpy(&invalid, impl->outInvalid,
                                         sizeof(invalid), cudaMemcpyDeviceToHost));
        MPCD_CUDA_0490M_CHECK(cudaMemcpy(&disabledSpeciesMutation,
                                         impl->outDisabledSpeciesMutation,
                                         sizeof(disabledSpeciesMutation), cudaMemcpyDeviceToHost));
        MPCD_CUDA_0490M_CHECK(cudaMemcpy(&entryShortfalls, impl->outEntryShortfalls,
                                         sizeof(entryShortfalls), cudaMemcpyDeviceToHost));
        MPCD_CUDA_0490M_CHECK(cudaMemcpy(&groupUnderfills, impl->outGroupUnderfills,
                                         sizeof(groupUnderfills), cudaMemcpyDeviceToHost));
        MPCD_CUDA_0490M_CHECK(cudaMemcpy(&rejected, impl->outTypeRejected,
                                         sizeof(rejected), cudaMemcpyDeviceToHost));
        MPCD_CUDA_0490M_CHECK(cudaMemcpy(&plannedMass, impl->outPlannedMass,
                                         sizeof(plannedMass), cudaMemcpyDeviceToHost));
        MPCD_CUDA_0490M_CHECK(cudaMemcpy(&selectedMass, impl->outSelectedMass,
                                         sizeof(selectedMass), cudaMemcpyDeviceToHost));
        MPCD_CUDA_0490M_CHECK(cudaMemcpy(&movedPx, impl->outMovedPx,
                                         sizeof(movedPx), cudaMemcpyDeviceToHost));
        MPCD_CUDA_0490M_CHECK(cudaMemcpy(&movedPy, impl->outMovedPy,
                                         sizeof(movedPy), cudaMemcpyDeviceToHost));
        MPCD_CUDA_0490M_CHECK(cudaMemcpy(&firstParticle, impl->outFirstParticle,
                                         sizeof(firstParticle), cudaMemcpyDeviceToHost));
        MPCD_CUDA_0490M_CHECK(cudaMemcpy(&lastParticle, impl->outLastParticle,
                                         sizeof(lastParticle), cudaMemcpyDeviceToHost));
        MPCD_CUDA_0490M_CHECK(cudaMemcpy(&firstReceiver, impl->outFirstReceiver,
                                         sizeof(firstReceiver), cudaMemcpyDeviceToHost));
        MPCD_CUDA_0490M_CHECK(cudaMemcpy(&lastReceiver, impl->outLastReceiver,
                                         sizeof(lastReceiver), cudaMemcpyDeviceToHost));
        unsigned int planEntries = 0u;
        MPCD_CUDA_0490M_CHECK(cudaMemcpy(&planEntries, plan.count,
                                         sizeof(planEntries), cudaMemcpyDeviceToHost));
        d.scalarDownloadSeconds = seconds_since_0490m(scalar0);
        d.planEntries = planEntries;
        d.operations = operations;
        d.invalidOperations = invalid;
        d.disabledSpeciesMutationCount =
            static_cast<std::uint64_t>(disabledSpeciesMutation);
        d.entryMassShortfalls = entryShortfalls;
        d.donorTypeGroupUnderfills = groupUnderfills;
        d.typeRejectedCandidates = static_cast<std::uint64_t>(rejected);
        d.plannedMass = plannedMass;
        d.selectedMass = selectedMass;
        d.movedMass = selectedMass;
        d.movedMomentumX = movedPx;
        d.movedMomentumY = movedPy;
        d.selectedMassCoverageFraction = plannedMass > 0.0
            ? selectedMass / plannedMass : 1.0;
        if (operations > fastWorkspace.capacity()) {
            throw std::runtime_error("0490m resident operation capacity overflow");
        }
        // 0493b: CUDA state is authoritative. No operation arrays or particle
        // attributes are downloaded and no host particle patchback is applied.
        d.compactPatchbackBytes = 0u;
        d.patchbackDownloadSeconds = 0.0;
        d.hostPatchbackSeconds = 0.0;

        extractionApply = ResamplingExtractionApplyDiagnostics{};
        insertionApply = ResamplingInsertionApplyDiagnostics{};
        extractionApply.attempted = true;
        extractionApply.applied = operations > 0u;
        extractionApply.operationsConsidered = operations;
        extractionApply.operationsApplied = operations;
        extractionApply.roleChanges = operations;
        extractionApply.appliedMass = d.movedMass;
        extractionApply.appliedMomentumX = d.movedMomentumX;
        extractionApply.appliedMomentumY = d.movedMomentumY;
        extractionApply.plannedExtractionMass = d.movedMass;
        extractionApply.massResidualVsPlan = 0.0;
        extractionApply.noDuplicateParticles = d.invalidOperations == 0u;
        extractionApply.allAppliedWereFluid = d.invalidOperations == 0u;
        insertionApply.attempted = true;
        insertionApply.applied = operations > 0u;
        insertionApply.operationsConsidered = operations;
        insertionApply.operationsApplied = operations;
        insertionApply.roleChanges = operations;
        insertionApply.insertedMass = d.movedMass;
        insertionApply.insertedMomentumX = d.movedMomentumX;
        insertionApply.insertedMomentumY = d.movedMomentumY;
        insertionApply.plannedInsertionMass = d.movedMass;
        insertionApply.massResidualVsPlan = 0.0;
        insertionApply.noInvalidReceiverCells = d.invalidOperations == 0u;
        insertionApply.allSourcesWereInactive = d.invalidOperations == 0u;
        if (operations > 0u && firstParticle != 0xffffffffu) {
            extractionApply.firstAppliedParticle = firstParticle;
            extractionApply.lastAppliedParticle = lastParticle;
            insertionApply.firstInsertedParticle = firstParticle;
            insertionApply.lastInsertedParticle = lastParticle;
            insertionApply.firstInsertionReceiverCell = firstReceiver;
            insertionApply.lastInsertionReceiverCell = lastReceiver;
        }

        d.handled = true;
        d.applied = operations > 0u;
        d.pass = d.invalidOperations == 0u &&
                 d.disabledSpeciesMutationCount == 0u;
        if (d.pass) {
            cuda_shared_particle_state_0251_mark_fresh("species_resampling_fast_path_0490m");
        } else {
            cuda_shared_particle_state_0251_invalidate("species_resampling_fast_path_0490m_failed");
        }
        d.totalSeconds = seconds_since_0490m(total0);
        append_csv_0490m(params, d);
        return d;
    } catch (const std::exception& e) {
        d.skipped = true;
        d.skipReason = e.what();
        d.totalSeconds = seconds_since_0490m(total0);
        append_csv_0490m(params, d);
        return d;
    }
#endif
}

} // namespace mpcd
