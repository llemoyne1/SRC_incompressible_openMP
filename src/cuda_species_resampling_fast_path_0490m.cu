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
               "invalidOperations,typeRejectedCandidates,usedSharedResidentState,particleUploadSkipped,workspaceReused,"
               "directDevicePlanHandoff,planArrayDownloadSkipped,planArrayUploadSkipped,operationRoundTripSkipped,"
               "fullStateCopySkipped,fullStateDownloadSkipped,allocatedBytes,allocationCalls,compactPatchbackBytes,"
               "movedMass,movedMomentumX,movedMomentumY,stateUploadSeconds,kernelSeconds,scalarDownloadSeconds,"
               "patchbackDownloadSeconds,hostPatchbackSeconds,totalSeconds\n";
    }
    out << std::setprecision(17)
        << d.step << ',' << (d.attempted ? 1 : 0) << ',' << (d.handled ? 1 : 0) << ','
        << (d.applied ? 1 : 0) << ',' << (d.pass ? 1 : 0) << ',' << (d.skipped ? 1 : 0) << ','
        << '"' << d.skipReason << '"' << ','
        << d.particlesScanned << ',' << d.planEntries << ',' << d.operations << ','
        << d.invalidOperations << ',' << d.typeRejectedCandidates << ','
        << d.usedSharedResidentState << ',' << d.particleUploadSkipped << ',' << d.workspaceReused << ','
        << d.directDevicePlanHandoff << ',' << d.planArrayDownloadSkipped << ','
        << d.planArrayUploadSkipped << ',' << d.operationRoundTripSkipped << ','
        << d.fullStateCopySkipped << ',' << d.fullStateDownloadSkipped << ','
        << d.allocatedBytes << ',' << d.allocationCalls << ',' << d.compactPatchbackBytes << ','
        << d.movedMass << ',' << d.movedMomentumX << ',' << d.movedMomentumY << ','
        << d.stateUploadSeconds << ',' << d.kernelSeconds << ',' << d.scalarDownloadSeconds << ','
        << d.patchbackDownloadSeconds << ',' << d.hostPatchbackSeconds << ',' << d.totalSeconds << '\n';
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
                                   double dy) {
    if (nx <= 0 || ny <= 0 || !(dx > 0.0) || !(dy > 0.0)) return -1;
    int ix = static_cast<int>(floor(x / dx));
    int iy = static_cast<int>(floor(y / dy));
    while (ix < 0) ix += nx;
    while (ix >= nx) ix -= nx;
    while (iy < 0) iy += ny;
    while (iy >= ny) iy -= ny;
    return iy * nx + ix;
}

// Correctness-first direct resident consumer. One thread preserves the exact
// deterministic ordering used by 0490g/0490k: plan order then ascending active
// particle index. Unlike the transitional 0453 materializer, particle type is
// checked explicitly against the species-constrained plan entry.
__global__ void apply_species_plan_direct_serial_0490m(
    int planCapacity,
    const unsigned int* planCount,
    const unsigned int* planOverflow,
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
    std::uint8_t fluidRole,
    unsigned char* selected,
    unsigned int maxOps,
    unsigned int* outCount,
    unsigned int* outInvalid,
    unsigned long long* outTypeRejected,
    unsigned int* outParticle,
    int* outReceiver,
    std::uint32_t* outType,
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
    constexpr double eps = 1.0e-14;
    unsigned int ops = 0u;
    unsigned int invalid = 0u;
    unsigned long long typeRejected = 0u;
    unsigned int entries = planCount != nullptr ? *planCount : 0u;
    const unsigned int overflow = planOverflow != nullptr ? *planOverflow : 0u;
    if (entries > static_cast<unsigned int>(planCapacity)) {
        entries = static_cast<unsigned int>(planCapacity);
        ++invalid;
    }
    if (overflow != 0u) invalid += overflow;

    for (unsigned int e = 0u; e < entries; ++e) {
        const int donor = planDonor[e];
        const int receiver = planReceiver[e];
        const std::uint32_t wantedType = planType[e];
        const double wantedMass = planMass[e];
        if (donor < 0 || receiver < 0 || !(wantedMass > eps)) continue;
        double gathered = 0.0;
        for (std::uint64_t p = 0u; p < nActive; ++p) {
            if (p >= nParticles || selected[p] != 0u || role[p] != fluidRole) continue;
            const int cell = particle_cell_0490m(x[p], y[p], nx, ny, dx, dy);
            if (cell != donor) continue;
            if (type[p] != wantedType) {
                ++typeRejected;
                continue;
            }
            const double mp = mass[p];
            if (!(mp > 0.0) || !isfinite(mp)) continue;
            if (ops >= maxOps) {
                ++invalid;
                break;
            }
            selected[p] = 1u;
            const double px = mp * vx[p];
            const double py = mp * vy[p];
            outParticle[ops] = static_cast<unsigned int>(p);
            outReceiver[ops] = receiver;
            outType[ops] = type[p];
            outMass[ops] = mp;
            outPx[ops] = px;
            outPy[ops] = py;

            const unsigned int c = static_cast<unsigned int>(receiver);
            const unsigned int ix = c % static_cast<unsigned int>(nx);
            const unsigned int iy = c / static_cast<unsigned int>(nx);
            const unsigned int q = ops & 15u;
            const double fx = 0.2 + 0.2 * static_cast<double>(q & 3u);
            const double fy = 0.2 + 0.2 * static_cast<double>(q >> 2u);
            x[p] = (static_cast<double>(ix) + fx) * dx;
            y[p] = (static_cast<double>(iy) + fy) * dy;
            mass[p] = mp;
            type[p] = wantedType;
            vx[p] = px / mp;
            vy[p] = py / mp;
            role[p] = fluidRole;

            ++ops;
            gathered += mp;
            if (gathered + eps >= wantedMass) break;
        }
        if (gathered + eps < wantedMass) ++invalid;
    }
    *outCount = ops;
    *outInvalid = invalid;
    *outTypeRejected = typeRejected;
}
#endif

} // namespace

struct CudaSpeciesResamplingFastPathWorkspace0490m::Impl {
    std::uint64_t capacity = 0u;
    std::uint64_t allocatedBytes = 0u;
#if defined(MPCD_ENABLE_CUDA_PARTICLE_STATE) && defined(MPCD_ENABLE_CUDA_CELL_WORKSPACE)
    unsigned char* selected = nullptr;
    unsigned int* outCount = nullptr;
    unsigned int* outInvalid = nullptr;
    unsigned long long* outTypeRejected = nullptr;
    unsigned int* outParticle = nullptr;
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
        cuda_free_0490m(impl_->selected);
        cuda_free_0490m(impl_->outCount);
        cuda_free_0490m(impl_->outInvalid);
        cuda_free_0490m(impl_->outTypeRejected);
        cuda_free_0490m(impl_->outParticle);
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
    CudaSpeciesResamplingFastPathDiagnostics0490m* diagnostics) {
#if !defined(MPCD_ENABLE_CUDA_PARTICLE_STATE) || !defined(MPCD_ENABLE_CUDA_CELL_WORKSPACE)
    (void)activeParticles; (void)diagnostics;
    throw std::runtime_error("0490m CUDA workspace requires CUDA particle/cell support");
#else
    if (activeParticles == 0u) activeParticles = 1u;
    if (impl_ == nullptr) throw std::runtime_error("0490m workspace has null impl");
    const bool reuse = impl_->capacity >= activeParticles;
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
    alloc(impl_->selected, activeParticles);
    alloc(impl_->outCount, 1u);
    alloc(impl_->outInvalid, 1u);
    alloc(impl_->outTypeRejected, 1u);
    alloc(impl_->outParticle, activeParticles);
    alloc(impl_->outReceiver, activeParticles);
    alloc(impl_->outType, activeParticles);
    alloc(impl_->outMass, activeParticles);
    alloc(impl_->outPx, activeParticles);
    alloc(impl_->outPy, activeParticles);
    impl_->capacity = activeParticles;
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
    (void)state; (void)params; (void)grid; (void)planWorkspace; (void)fastWorkspace;
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
        if (!(params.bcLeft == "periodic" && params.bcRight == "periodic" &&
              params.bcBottom == "periodic" && params.bcTop == "periodic") ||
            params.immersedSolidEnable) {
            throw std::runtime_error("0490m direct fast path requires periodic wall-free no-solid geometry");
        }
        if (!cuda_species_resampling_fast_path_available_0490m()) {
            throw std::runtime_error("0490m requested but no CUDA device is available");
        }
        const CudaSpeciesTransferPlanDeviceView0490m plan =
            planWorkspace.device_view_0490m();
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

        fastWorkspace.ensure_capacity(state.NactiveFluid, &d);
        d.allocatedBytes = fastWorkspace.allocated_bytes();
        auto* impl = fastWorkspace.impl_;
        MPCD_CUDA_0490M_CHECK(cudaMemset(impl->selected, 0,
            static_cast<std::size_t>(std::max<std::uint64_t>(1u, state.NactiveFluid)) * sizeof(unsigned char)));
        MPCD_CUDA_0490M_CHECK(cudaMemset(impl->outCount, 0, sizeof(unsigned int)));
        MPCD_CUDA_0490M_CHECK(cudaMemset(impl->outInvalid, 0, sizeof(unsigned int)));
        MPCD_CUDA_0490M_CHECK(cudaMemset(impl->outTypeRejected, 0, sizeof(unsigned long long)));

        cudaEvent_t start{}, stop{};
        MPCD_CUDA_0490M_CHECK(cudaEventCreate(&start));
        MPCD_CUDA_0490M_CHECK(cudaEventCreate(&stop));
        MPCD_CUDA_0490M_CHECK(cudaEventRecord(start));
        apply_species_plan_direct_serial_0490m<<<1, 1>>>(
            plan.capacity, plan.count, plan.overflow,
            plan.donorCell, plan.receiverCell, plan.particleType, plan.plannedMass,
            view.n, view.nActiveFluid, grid.Nx, grid.Ny, grid.dx, grid.dy,
            static_cast<std::uint8_t>(ParticleRole::Fluid),
            impl->selected, static_cast<unsigned int>(fastWorkspace.capacity()),
            impl->outCount, impl->outInvalid, impl->outTypeRejected,
            impl->outParticle, impl->outReceiver, impl->outType,
            impl->outMass, impl->outPx, impl->outPy,
            view.x, view.y, view.vx, view.vy, view.mass, view.type, view.role);
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
        unsigned long long rejected = 0u;
        MPCD_CUDA_0490M_CHECK(cudaMemcpy(&operations, impl->outCount,
                                         sizeof(operations), cudaMemcpyDeviceToHost));
        MPCD_CUDA_0490M_CHECK(cudaMemcpy(&invalid, impl->outInvalid,
                                         sizeof(invalid), cudaMemcpyDeviceToHost));
        MPCD_CUDA_0490M_CHECK(cudaMemcpy(&rejected, impl->outTypeRejected,
                                         sizeof(rejected), cudaMemcpyDeviceToHost));
        unsigned int planEntries = 0u;
        MPCD_CUDA_0490M_CHECK(cudaMemcpy(&planEntries, plan.count,
                                         sizeof(planEntries), cudaMemcpyDeviceToHost));
        d.scalarDownloadSeconds = seconds_since_0490m(scalar0);
        d.planEntries = planEntries;
        d.operations = operations;
        d.invalidOperations = invalid;
        d.typeRejectedCandidates = static_cast<std::uint64_t>(rejected);
        if (operations > fastWorkspace.capacity()) {
            throw std::runtime_error("0490m compact patchback capacity overflow");
        }

        std::vector<unsigned int> particle(operations);
        std::vector<int> receiver(operations);
        std::vector<std::uint32_t> type(operations);
        std::vector<double> mass(operations), px(operations), py(operations);
        const Clock0490m::time_point patchDownload0 = Clock0490m::now();
        if (operations > 0u) {
            const std::size_t n = static_cast<std::size_t>(operations);
            MPCD_CUDA_0490M_CHECK(cudaMemcpy(particle.data(), impl->outParticle,
                n * sizeof(unsigned int), cudaMemcpyDeviceToHost));
            MPCD_CUDA_0490M_CHECK(cudaMemcpy(receiver.data(), impl->outReceiver,
                n * sizeof(int), cudaMemcpyDeviceToHost));
            MPCD_CUDA_0490M_CHECK(cudaMemcpy(type.data(), impl->outType,
                n * sizeof(std::uint32_t), cudaMemcpyDeviceToHost));
            MPCD_CUDA_0490M_CHECK(cudaMemcpy(mass.data(), impl->outMass,
                n * sizeof(double), cudaMemcpyDeviceToHost));
            MPCD_CUDA_0490M_CHECK(cudaMemcpy(px.data(), impl->outPx,
                n * sizeof(double), cudaMemcpyDeviceToHost));
            MPCD_CUDA_0490M_CHECK(cudaMemcpy(py.data(), impl->outPy,
                n * sizeof(double), cudaMemcpyDeviceToHost));
            d.compactPatchbackBytes = static_cast<std::uint64_t>(n) *
                (sizeof(unsigned int) + sizeof(int) + sizeof(std::uint32_t) + 3u * sizeof(double));
        }
        d.patchbackDownloadSeconds = seconds_since_0490m(patchDownload0);

        const Clock0490m::time_point patchHost0 = Clock0490m::now();
        for (std::size_t op = 0; op < static_cast<std::size_t>(operations); ++op) {
            const std::size_t i = static_cast<std::size_t>(particle[op]);
            const int cSigned = receiver[op];
            const double mp = mass[op];
            if (i >= static_cast<std::size_t>(state.Np) || cSigned < 0 || !(mp > 0.0)) {
                ++d.invalidOperations;
                continue;
            }
            const unsigned int c = static_cast<unsigned int>(cSigned);
            if (c >= static_cast<unsigned int>(grid.numCells)) {
                ++d.invalidOperations;
                continue;
            }
            const unsigned int ix = c % static_cast<unsigned int>(grid.Nx);
            const unsigned int iy = c / static_cast<unsigned int>(grid.Nx);
            const unsigned int q = static_cast<unsigned int>(op) & 15u;
            const double fx = 0.2 + 0.2 * static_cast<double>(q & 3u);
            const double fy = 0.2 + 0.2 * static_cast<double>(q >> 2u);
            state.x[i] = (static_cast<double>(ix) + fx) * grid.dx;
            state.y[i] = (static_cast<double>(iy) + fy) * grid.dy;
            state.mass[i] = mp;
            state.type[i] = type[op];
            state.vx[i] = px[op] / mp;
            state.vy[i] = py[op] / mp;
            if (!state.role.empty()) {
                state.role[i] = static_cast<std::uint8_t>(ParticleRole::Fluid);
            }
            d.movedMass += mp;
            d.movedMomentumX += px[op];
            d.movedMomentumY += py[op];
        }
        d.hostPatchbackSeconds = seconds_since_0490m(patchHost0);

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
        if (operations > 0u) {
            extractionApply.firstAppliedParticle = particle.front();
            extractionApply.lastAppliedParticle = particle.back();
            insertionApply.firstInsertedParticle = particle.front();
            insertionApply.lastInsertedParticle = particle.back();
            insertionApply.firstInsertionReceiverCell = receiver.front();
            insertionApply.lastInsertionReceiverCell = receiver.back();
        }

        d.handled = true;
        d.applied = operations > 0u;
        d.pass = d.invalidOperations == 0u;
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
