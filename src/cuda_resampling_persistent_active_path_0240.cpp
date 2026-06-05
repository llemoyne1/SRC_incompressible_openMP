#include "cuda_resampling_persistent_active_path_0240.h"

#include <algorithm>
#include <cmath>
#include <cctype>
#include <cstdlib>
#include <cstdint>
#include <stdexcept>
#include <string>
#include <vector>

#if defined(MPCD_ENABLE_CUDA_PARTICLE_STATE) && defined(MPCD_ENABLE_CUDA_RESAMPLING)
#include "cuda_particle_state.h"
#include "cuda_resampling_particle_ops.h"
#endif

namespace mpcd {
namespace {

bool env_flag_true_0241(const char* name, bool defaultValue) {
    const char* v = std::getenv(name);
    if (v == nullptr || *v == '\0') return defaultValue;
    std::string s(v);
    for (char& c : s) c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
    if (s == "0" || s == "false" || s == "off" || s == "no") return false;
    if (s == "1" || s == "true" || s == "on" || s == "yes") return true;
    return defaultValue;
}

std::string env_string_0242(const char* name, const char* defaultValue) {
    const char* v = std::getenv(name);
    if (v == nullptr || *v == '\0') return std::string(defaultValue ? defaultValue : "");
    std::string s(v);
    for (char& c : s) c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
    return s;
}

void deterministic_receiver_position_0241(std::int32_t cell,
                                           std::uint64_t ordinal,
                                           const CellGrid& grid,
                                           double& x,
                                           double& y) {
    if (cell < 0 || cell >= grid.numCells || grid.Nx <= 0 || grid.Ny <= 0) {
        throw std::runtime_error("deterministic_receiver_position_0241: invalid receiver cell");
    }
    const int ix = static_cast<int>(cell) % grid.Nx;
    const int iy = static_cast<int>(cell) / grid.Nx;
    const std::uint64_t q = ordinal % 16u;
    const double fx = 0.2 + 0.2 * static_cast<double>(q % 4u);
    const double fy = 0.2 + 0.2 * static_cast<double>(q / 4u);
    x = (static_cast<double>(ix) + fx) * grid.dx;
    y = (static_cast<double>(iy) + fy) * grid.dy;
}

#if defined(MPCD_ENABLE_CUDA_PARTICLE_STATE) && defined(MPCD_ENABLE_CUDA_RESAMPLING)

void accumulate_particle_state_diag_0242(CudaResamplingPersistentActivePath0240Diagnostics& out,
                                         const CudaParticleStateDiagnostics& in) {
    out.allocationCalls += in.allocationCalls;
    out.uploadCalls += in.uploadCalls;
    out.downloadCalls += in.downloadCalls;
    out.metadataUploadCalls += in.metadataUploadCalls;
    out.metadataCacheHits += in.metadataCacheHits;
    out.hostToDeviceBytes += in.hostToDeviceBytes;
    out.deviceToHostBytes += in.deviceToHostBytes;
    out.metadataBytesSkipped += in.metadataBytesSkipped;
    out.uploadSeconds += in.uploadSeconds;
    out.downloadSeconds += in.downloadSeconds;
}

struct ActivePathPreparedOps0241 {
    std::vector<std::uint32_t> extractionParticle;
    std::vector<double> extractionMass;
    std::vector<double> extractionPx;
    std::vector<double> extractionPy;

    std::vector<std::uint32_t> insertionParticle;
    std::vector<std::uint32_t> insertionReceiver;
    std::vector<std::uint32_t> insertionType;
    std::vector<double> insertionMass;
    std::vector<double> insertionPx;
    std::vector<double> insertionPy;
    std::vector<std::uint32_t> insertionOrdinal;
};

void prepare_extraction_ops_0241(
    ParticleState& state,
    ResamplingParticlePoolWorkspace& pool,
    const WeightedRealFluidDepositWorkspace& depositWorkspace,
    ResamplingExtractionApplyDiagnostics& d,
    ActivePathPreparedOps0241& ops) {

    validate_particle_state(state, "prepare_extraction_ops_0241");
    ensure_particle_roles(state, ParticleRole::Fluid);

    d = ResamplingExtractionApplyDiagnostics{};
    d.attempted = true;
    d.operationsConsidered = static_cast<std::uint64_t>(depositWorkspace.passiveExtractionOperations.size());
    d.poolFreeSlotsBefore = static_cast<std::uint64_t>(pool.freeInactiveSlots.size());

    const std::size_t n = static_cast<std::size_t>(state.Np);
    std::vector<std::uint8_t> seen(n, 0u);
    ops.extractionParticle.reserve(depositWorkspace.passiveExtractionOperations.size());
    ops.extractionMass.reserve(depositWorkspace.passiveExtractionOperations.size());
    ops.extractionPx.reserve(depositWorkspace.passiveExtractionOperations.size());
    ops.extractionPy.reserve(depositWorkspace.passiveExtractionOperations.size());

    for (const ResamplingPassiveExtractionOperation& op : depositWorkspace.passiveExtractionOperations) {
        d.plannedExtractionMass += op.particleMass;
        const std::uint64_t pi64 = op.particleIndex;
        if (pi64 == kInvalidParticleIndex || pi64 >= state.Np) {
            d.skippedInvalidParticles += 1u;
            d.noDuplicateParticles = false;
            continue;
        }
        const std::size_t pi = static_cast<std::size_t>(pi64);
        if (seen[pi]) {
            d.skippedDuplicateParticles += 1u;
            d.noDuplicateParticles = false;
            continue;
        }
        seen[pi] = 1u;
        if (!is_fluid_particle(state, pi)) {
            d.skippedNonFluidParticles += 1u;
            d.allAppliedWereFluid = false;
            continue;
        }

        const double mp = state.mass[pi];
        const double vx = state.vx[pi];
        const double vy = state.vy[pi];
        const double px = mp * vx;
        const double py = mp * vy;
        const double ke = 0.5 * mp * (vx * vx + vy * vy);

        set_particle_role(state, pi, ParticleRole::Inactive);
        resampling_pool_push_free_slot(pool, pi64);

        ops.extractionParticle.push_back(static_cast<std::uint32_t>(pi64));
        ops.extractionMass.push_back(mp);
        ops.extractionPx.push_back(px);
        ops.extractionPy.push_back(py);

        d.operationsApplied += 1u;
        d.roleChanges += 1u;
        d.appliedMass += mp;
        d.appliedMomentumX += px;
        d.appliedMomentumY += py;
        d.appliedKineticEnergy += ke;
        if (d.firstAppliedParticle == kInvalidParticleIndex) d.firstAppliedParticle = pi64;
        d.lastAppliedParticle = pi64;
    }

    d.poolFreeSlotsAfter = static_cast<std::uint64_t>(pool.freeInactiveSlots.size());
    d.poolFreeSlotDelta = d.poolFreeSlotsAfter >= d.poolFreeSlotsBefore
        ? d.poolFreeSlotsAfter - d.poolFreeSlotsBefore : 0u;
    d.massResidualVsPlan = d.appliedMass - d.plannedExtractionMass;
    d.applied = d.operationsApplied > 0u;
    d.allAppliedWereFluid = d.allAppliedWereFluid && d.skippedNonFluidParticles == 0u;
}

void prepare_insertion_ops_0241(
    ParticleState& state,
    ResamplingParticlePoolWorkspace& pool,
    const WeightedRealFluidDepositWorkspace& depositWorkspace,
    const CellGrid& grid,
    ResamplingInsertionApplyDiagnostics& d,
    ActivePathPreparedOps0241& ops) {

    validate_particle_state(state, "prepare_insertion_ops_0241");
    ensure_particle_roles(state, ParticleRole::Fluid);

    d = ResamplingInsertionApplyDiagnostics{};
    d.attempted = true;
    d.operationsConsidered = static_cast<std::uint64_t>(depositWorkspace.passiveExtractionOperations.size());
    d.poolFreeSlotsBefore = static_cast<std::uint64_t>(pool.freeInactiveSlots.size());

    ops.insertionParticle.reserve(depositWorkspace.passiveExtractionOperations.size());
    ops.insertionReceiver.reserve(depositWorkspace.passiveExtractionOperations.size());
    ops.insertionType.reserve(depositWorkspace.passiveExtractionOperations.size());
    ops.insertionMass.reserve(depositWorkspace.passiveExtractionOperations.size());
    ops.insertionPx.reserve(depositWorkspace.passiveExtractionOperations.size());
    ops.insertionPy.reserve(depositWorkspace.passiveExtractionOperations.size());
    ops.insertionOrdinal.reserve(depositWorkspace.passiveExtractionOperations.size());

    for (const ResamplingPassiveExtractionOperation& op : depositWorkspace.passiveExtractionOperations) {
        if (op.particleMass > 0.0 && std::isfinite(op.particleMass)) {
            d.plannedInsertionMass += op.particleMass;
        }

        if (op.particleIndex == kInvalidParticleIndex || op.particleIndex >= state.Np) {
            d.skippedInvalidSourceParticles += 1u;
            d.allSourcesWereInactive = false;
            continue;
        }
        const std::size_t sourceIndex = static_cast<std::size_t>(op.particleIndex);
        if (!is_inactive_particle(state, sourceIndex)) {
            d.skippedSourceNotInactive += 1u;
            d.allSourcesWereInactive = false;
            continue;
        }
        if (op.receiverCell < 0 || op.receiverCell >= grid.numCells) {
            d.skippedInvalidReceiverCells += 1u;
            d.noInvalidReceiverCells = false;
            continue;
        }
        if (!(op.particleMass > 0.0) || !std::isfinite(op.particleMass)) {
            d.skippedInvalidMass += 1u;
            continue;
        }
        auto freeIt = std::find(pool.freeInactiveSlots.begin(), pool.freeInactiveSlots.end(), op.particleIndex);
        if (freeIt == pool.freeInactiveSlots.end()) {
            d.skippedNoFreeSlots += 1u;
            continue;
        }

        const std::uint64_t slot64 = op.particleIndex;
        pool.freeInactiveSlots.erase(freeIt);
        const std::size_t slot = static_cast<std::size_t>(slot64);

        const std::uint32_t ordinal = static_cast<std::uint32_t>(d.operationsApplied);
        ops.insertionParticle.push_back(static_cast<std::uint32_t>(slot64));
        ops.insertionReceiver.push_back(static_cast<std::uint32_t>(op.receiverCell));
        ops.insertionType.push_back(op.particleType);
        ops.insertionMass.push_back(op.particleMass);
        ops.insertionPx.push_back(op.momentumX);
        ops.insertionPy.push_back(op.momentumY);
        ops.insertionOrdinal.push_back(ordinal);

        // Keep the CPU shadow state coherent while the GPU state is mutated.
        // The final download overwrites these fields; this mirror update is used
        // only to reproduce the CPU diagnostics and pool/role semantics exactly.
        double newX = 0.0;
        double newY = 0.0;
        deterministic_receiver_position_0241(op.receiverCell, ordinal, grid, newX, newY);
        const double invM = 1.0 / op.particleMass;
        state.x[slot] = newX;
        state.y[slot] = newY;
        state.vx[slot] = op.momentumX * invM;
        state.vy[slot] = op.momentumY * invM;
        state.mass[slot] = op.particleMass;
        state.type[slot] = op.particleType;
        set_particle_role(state, slot, ParticleRole::Fluid);

        d.operationsApplied += 1u;
        d.roleChanges += 1u;
        d.insertedMass += op.particleMass;
        d.insertedMomentumX += op.momentumX;
        d.insertedMomentumY += op.momentumY;
        d.insertedKineticEnergy += op.kineticEnergy;
        if (d.firstInsertedParticle == kInvalidParticleIndex) {
            d.firstInsertedParticle = slot64;
            d.firstInsertionReceiverCell = op.receiverCell;
        }
        d.lastInsertedParticle = slot64;
        d.lastInsertionReceiverCell = op.receiverCell;
    }

    d.poolFreeSlotsAfter = static_cast<std::uint64_t>(pool.freeInactiveSlots.size());
    d.poolFreeSlotDelta = d.poolFreeSlotsBefore >= d.poolFreeSlotsAfter
        ? d.poolFreeSlotsBefore - d.poolFreeSlotsAfter : 0u;
    d.massResidualVsPlan = d.insertedMass - d.plannedInsertionMass;
    d.applied = d.operationsApplied > 0u;
    d.allSourcesWereInactive = d.allSourcesWereInactive && d.skippedSourceNotInactive == 0u;
    d.noInvalidReceiverCells = d.noInvalidReceiverCells && d.skippedInvalidReceiverCells == 0u;
}

#endif // MPCD_ENABLE_CUDA_PARTICLE_STATE && MPCD_ENABLE_CUDA_RESAMPLING

} // namespace

CudaResamplingPersistentActivePath0240Diagnostics
try_apply_cuda_resampling_persistent_active_path_0240(
    ParticleState& state,
    ResamplingParticlePoolWorkspace& poolWorkspace,
    WeightedRealFluidDepositWorkspace& depositWorkspace,
    const WeightedResamplingDiagnostics& depositDiagnostics,
    const SimulationParams& params,
    const CellGrid& grid,
    ResamplingExtractionApplyDiagnostics& extractionDiagnostics,
    ResamplingInsertionApplyDiagnostics& insertionDiagnostics) {
    (void)depositDiagnostics;

    CudaResamplingPersistentActivePath0240Diagnostics d{};
    d.attempted = true;

#if defined(MPCD_ENABLE_CUDA_PARTICLE_STATE) && defined(MPCD_ENABLE_CUDA_RESAMPLING)
    if (!cuda_particle_state_available()) {
        return d;
    }

    thread_local CudaParticleState gpuState;
    CudaParticleStateDiagnostics stateDiag{};
    const std::string uploadMode0242 = env_string_0242(
        "MPCD_CUDA_RESAMPLING_PERSISTENT_ACTIVE_PATH_0242_UPLOAD_MODE", "all");
    if (uploadMode0242 == "roles_only" || uploadMode0242 == "role_only") {
        // 0243 diagnostic/transition mode: the CPU shadow remains authoritative
        // and no full device->host particle download is performed. The kernels
        // only need role[] to validate/apply the Fluid->Inactive->Fluid edits;
        // insertion writes all touched particle fields explicitly. Non-touched
        // device kinematics may be stale and must not be consumed downstream.
        if (!env_flag_true_0241("MPCD_CUDA_RESAMPLING_PERSISTENT_ACTIVE_PATH_0242_HOST_SHADOW_AUTHORITATIVE", false) ||
            env_flag_true_0241("MPCD_CUDA_RESAMPLING_PERSISTENT_ACTIVE_PATH_0242_DOWNLOAD_ALL", false)) {
            if (env_flag_true_0241("MPCD_CUDA_RESAMPLING_PERSISTENT_ACTIVE_PATH_0243_STRICT_ROLES_ONLY", true)) {
                throw std::runtime_error("roles_only upload mode requires HOST_SHADOW_AUTHORITATIVE=1 and DOWNLOAD_ALL=0");
            }
        }
        gpuState.upload_roles(state, &stateDiag);
    } else if (uploadMode0242 == "cached" || uploadMode0242 == "kinematics_cached") {
        gpuState.upload_kinematics_with_cached_metadata(state, &stateDiag);
    } else {
        gpuState.upload_all(state, &stateDiag);
    }
    accumulate_particle_state_diag_0242(d, stateDiag);

    ActivePathPreparedOps0241 ops{};
    prepare_extraction_ops_0241(state, poolWorkspace, depositWorkspace, extractionDiagnostics, ops);

    CudaResamplingPersistentOpsDiagnostics cudaExtraction{};
    if (!ops.extractionParticle.empty()) {
        CudaResamplingExtractionApplyParams ep{};
        ep.fluidRole = static_cast<std::uint8_t>(ParticleRole::Fluid);
        ep.inactiveRole = static_cast<std::uint8_t>(ParticleRole::Inactive);
        ep.invalidParticle = 0xffffffffu;
        const bool ok = cuda_resampling_apply_extraction_operations_on_state_0239(
            gpuState, ops.extractionParticle, ops.extractionMass, ops.extractionPx, ops.extractionPy, ep, &cudaExtraction);
        if (!ok || cudaExtraction.operationsApplied != ops.extractionParticle.size()) {
            if (env_flag_true_0241("MPCD_CUDA_RESAMPLING_PERSISTENT_ACTIVE_PATH_0241_STRICT", true)) {
                throw std::runtime_error("CUDA persistent active-path 0241 extraction failed or applied fewer operations than CPU plan");
            }
        }
    }

    if (params.resamplingInsertionEnable && extractionDiagnostics.applied) {
        prepare_insertion_ops_0241(state, poolWorkspace, depositWorkspace, grid, insertionDiagnostics, ops);

        CudaResamplingPersistentOpsDiagnostics cudaInsertion{};
        if (!ops.insertionParticle.empty()) {
            CudaResamplingInsertionApplyParams ip{};
            ip.inactiveRole = static_cast<std::uint8_t>(ParticleRole::Inactive);
            ip.fluidRole = static_cast<std::uint8_t>(ParticleRole::Fluid);
            ip.invalidParticle = 0xffffffffu;
            ip.useHashPlacement = 0u; // match CPU deterministic_receiver_position().
            const bool ok = cuda_resampling_apply_insertion_operations_on_state_0239(
                gpuState,
                ops.insertionParticle,
                ops.insertionReceiver,
                ops.insertionType,
                ops.insertionMass,
                ops.insertionPx,
                ops.insertionPy,
                ops.insertionOrdinal,
                static_cast<std::uint32_t>(grid.Nx),
                static_cast<std::uint32_t>(grid.Ny),
                grid.dx,
                grid.dy,
                ip,
                &cudaInsertion);
            if (!ok || cudaInsertion.operationsApplied != ops.insertionParticle.size()) {
                if (env_flag_true_0241("MPCD_CUDA_RESAMPLING_PERSISTENT_ACTIVE_PATH_0241_STRICT", true)) {
                    throw std::runtime_error("CUDA persistent active-path 0241 insertion failed or applied fewer operations than CPU plan");
                }
            }
        }
    } else {
        insertionDiagnostics = ResamplingInsertionApplyDiagnostics{};
    }

    const bool hostShadowAuthoritative0242 = env_flag_true_0241(
        "MPCD_CUDA_RESAMPLING_PERSISTENT_ACTIVE_PATH_0242_HOST_SHADOW_AUTHORITATIVE", false);
    const bool downloadAll0242 = env_flag_true_0241(
        "MPCD_CUDA_RESAMPLING_PERSISTENT_ACTIVE_PATH_0242_DOWNLOAD_ALL", !hostShadowAuthoritative0242);

    d.hostShadowAuthoritative = hostShadowAuthoritative0242;
    if (downloadAll0242) {
        CudaParticleStateDiagnostics downloadDiag{};
        gpuState.download_all(state, &downloadDiag);
        accumulate_particle_state_diag_0242(d, downloadDiag);
    } else {
        // 0242 performance mode: the host shadow was already edited using the
        // exact same validated plan as the GPU kernels.  Skipping the full
        // device->host particle copy exposes the transfer overhead while keeping
        // the surrounding CPU-owned pipeline deterministic.  Strict operation
        // count checks above remain active by default.
        d.downloadSkipped = true;
    }

    d.handled = true;
    d.applied = extractionDiagnostics.applied || insertionDiagnostics.applied;
    d.extractionApplied = extractionDiagnostics.operationsApplied;
    d.insertionApplied = insertionDiagnostics.operationsApplied;
    return d;
#else
    (void)state;
    (void)poolWorkspace;
    (void)depositWorkspace;
    (void)params;
    (void)grid;
    (void)extractionDiagnostics;
    (void)insertionDiagnostics;

    // CPU-only builds keep compiling and simply fall back to the original CPU
    // extraction/insertion path in src_mpcd_base.cpp.
    d.handled = false;
    d.applied = false;
    return d;
#endif
}

} // namespace mpcd
