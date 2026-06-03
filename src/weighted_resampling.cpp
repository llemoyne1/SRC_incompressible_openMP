#include "weighted_resampling.h"

#include "immersed_solid.h"

#include <algorithm>
#include <array>
#include <chrono>
#include <filesystem>
#include <fstream>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <limits>
#include <stdexcept>

#ifdef _OPENMP
#include <omp.h>
#endif

namespace mpcd {
namespace {

int thread_count() {
#ifdef _OPENMP
    return omp_get_max_threads();
#else
    return 1;
#endif
}

int thread_id() {
#ifdef _OPENMP
    return omp_get_thread_num();
#else
    return 0;
#endif
}


inline void set_particle_role_preconditioned(ParticleState& state,
                                             const std::size_t i,
                                             const ParticleRole role) {
#ifndef NDEBUG
    if (state.role.size() != static_cast<std::size_t>(state.Np)) {
        throw std::runtime_error("set_particle_role_preconditioned: role array not initialized");
    }
    if (i >= state.role.size()) {
        throw std::runtime_error("set_particle_role_preconditioned: index out of range");
    }
#endif
    state.role[i] = static_cast<std::uint8_t>(role);
}


using ResamplingProfileClock = std::chrono::steady_clock;

struct PopulationGuardProfilePhaseIndex {
    enum : std::size_t {
        InitThresholds = 0,
        CountCopy = 1,
        StatsBefore = 2,
        EnsureCellParticleIndex = 3,
        OverfullExtractionLoop = 4,
        UnderfullSplitLoop = 5,
        StatsAfterFinalize = 6,
        OverfullCandidateSetup = 7,
        OverfullParticleScan = 8,
        OverfullApplyMutation = 9,
        OverfullDiagnostics = 10,
        UnderfullCandidateSetup = 11,
        UnderfullParticleScan = 12,
        UnderfullApplyMutation = 13,
        UnderfullDiagnostics = 14,
        OverfullMutationMomentumMerge = 15,
        OverfullMutationStateWrite = 16,
        OverfullMutationRoleInactivate = 17,
        OverfullMutationPoolPush = 18,
        OverfullMutationCountUpdate = 19,
        UnderfullMutationPoolPop = 20,
        UnderfullMutationParticleClone = 21,
        UnderfullMutationRoleActivate = 22,
        UnderfullMutationPoolFluidPush = 23,
        UnderfullMutationCountersUpdate = 24
    };
};

struct MassGuardProfilePhaseIndex {
    enum : std::size_t {
        InitValidate = 0,
        BuildParticlesByCell = 1,
        CellLoop = 2,
        Finalize = 3
    };
};

struct DepositProfilePhaseIndex {
    enum : std::size_t {
        ValidateResize = 0,
        ClearArrays = 1,
        RoleCounts = 2,
        ParticleLoopCellAccum = 3,
        ReduceCellsFinalize = 4,
        ActiveWetClassification = 5,
        PoorRichClassification = 6,
        CandidateLists = 7,
        MutationPlanCellIndex = 8,
        TransferPlanBuild = 9,
        DonorParticleSelection = 10,
        PassiveExtractionPlan = 11
    };
};

static_assert(ResamplingPopulationGuardProfilePhaseCount == 25u, "population-guard profile phase count mismatch");
static_assert(ResamplingMassGuardProfilePhaseCount == 4u, "mass-guard profile phase count mismatch");
static_assert(ResamplingDepositProfilePhaseCount == 12u, "deposit profile phase count mismatch");

class ScopedPopulationGuardProfileTimer {
public:
    ScopedPopulationGuardProfileTimer(ResamplingPopulationGuardProfile& profile,
                                      const std::size_t phaseIndex)
        : profile_(profile), phaseIndex_(phaseIndex), t0_(ResamplingProfileClock::now()) {}
    ScopedPopulationGuardProfileTimer(const ScopedPopulationGuardProfileTimer&) = delete;
    ScopedPopulationGuardProfileTimer& operator=(const ScopedPopulationGuardProfileTimer&) = delete;
    ~ScopedPopulationGuardProfileTimer() {
        if (phaseIndex_ < profile_.seconds.size()) {
            profile_.seconds[phaseIndex_] +=
                std::chrono::duration<double>(ResamplingProfileClock::now() - t0_).count();
        }
    }
private:
    ResamplingPopulationGuardProfile& profile_;
    std::size_t phaseIndex_;
    ResamplingProfileClock::time_point t0_;
};

class ScopedMassGuardProfileTimer {
public:
    ScopedMassGuardProfileTimer(ResamplingMassGuardProfile& profile,
                                const std::size_t phaseIndex)
        : profile_(profile), phaseIndex_(phaseIndex), t0_(ResamplingProfileClock::now()) {}
    ScopedMassGuardProfileTimer(const ScopedMassGuardProfileTimer&) = delete;
    ScopedMassGuardProfileTimer& operator=(const ScopedMassGuardProfileTimer&) = delete;
    ~ScopedMassGuardProfileTimer() {
        if (phaseIndex_ < profile_.seconds.size()) {
            profile_.seconds[phaseIndex_] +=
                std::chrono::duration<double>(ResamplingProfileClock::now() - t0_).count();
        }
    }
private:
    ResamplingMassGuardProfile& profile_;
    std::size_t phaseIndex_;
    ResamplingProfileClock::time_point t0_;
};

#define MPCD_POP_GUARD_PROFILE(profile, phaseName) \
    ScopedPopulationGuardProfileTimer mpcdPopGuardProfileTimer_##phaseName((profile), PopulationGuardProfilePhaseIndex::phaseName)

class ScopedDepositProfileTimer {
public:
    ScopedDepositProfileTimer(std::array<double, ResamplingDepositProfilePhaseCount>& seconds,
                              const std::size_t phaseIndex)
        : seconds_(seconds), phaseIndex_(phaseIndex), t0_(ResamplingProfileClock::now()) {}
    ScopedDepositProfileTimer(const ScopedDepositProfileTimer&) = delete;
    ScopedDepositProfileTimer& operator=(const ScopedDepositProfileTimer&) = delete;
    ~ScopedDepositProfileTimer() {
        if (phaseIndex_ < seconds_.size()) {
            seconds_[phaseIndex_] +=
                std::chrono::duration<double>(ResamplingProfileClock::now() - t0_).count();
        }
    }
private:
    std::array<double, ResamplingDepositProfilePhaseCount>& seconds_;
    std::size_t phaseIndex_;
    ResamplingProfileClock::time_point t0_;
};

#define MPCD_MASS_GUARD_PROFILE(profile, phaseName) \
    ScopedMassGuardProfileTimer mpcdMassGuardProfileTimer_##phaseName((profile), MassGuardProfilePhaseIndex::phaseName)

#define MPCD_DEPOSIT_PROFILE(seconds, phaseName) \
    ScopedDepositProfileTimer mpcdDepositProfileTimer_##phaseName((seconds), DepositProfilePhaseIndex::phaseName)

struct DepositProfileAccumulator {
    std::array<std::array<double, ResamplingDepositProfilePhaseCount>,
               static_cast<std::size_t>(ResamplingDepositProfileContext::Count)> seconds{};
    std::array<std::uint64_t, static_cast<std::size_t>(ResamplingDepositProfileContext::Count)> calls{};
    std::array<std::uint64_t, static_cast<std::size_t>(ResamplingDepositProfileContext::Count)> particlesVisited{};
    std::array<std::uint64_t, static_cast<std::size_t>(ResamplingDepositProfileContext::Count)> fluidParticles{};
    std::array<std::uint64_t, static_cast<std::size_t>(ResamplingDepositProfileContext::Count)> cells{};
    std::string outputDir;

    void add(const std::string& out,
             ResamplingDepositProfileContext context,
             const std::array<double, ResamplingDepositProfilePhaseCount>& localSeconds,
             std::uint64_t nParticles,
             std::uint64_t nFluid,
             std::uint64_t nCells) {
        const std::size_t idx = static_cast<std::size_t>(context);
        if (idx >= calls.size()) {
            return;
        }
        if (!out.empty()) {
            outputDir = out;
        }
        calls[idx] += 1u;
        particlesVisited[idx] += nParticles;
        fluidParticles[idx] += nFluid;
        cells[idx] += nCells;
        for (std::size_t i = 0; i < ResamplingDepositProfilePhaseCount; ++i) {
            seconds[idx][i] += localSeconds[i];
        }
    }

    ~DepositProfileAccumulator() {
        if (outputDir.empty()) {
            return;
        }
        std::error_code ec;
        std::filesystem::create_directories(outputDir, ec);
        const std::filesystem::path path = std::filesystem::path(outputDir) / "deposit_profile_0172.csv";
        std::ofstream out(path);
        if (!out) {
            return;
        }
        out << "context,phase,total_s,ms_per_call,percent_context_total,calls,particles_visited,fluid_particles,cells\n";
        out.setf(std::ios::fmtflags(0), std::ios::floatfield);
        out.precision(17);
        for (std::size_t c = 0; c < calls.size(); ++c) {
            if (calls[c] == 0u) {
                continue;
            }
            const auto context = static_cast<ResamplingDepositProfileContext>(c);
            double total = 0.0;
            for (double v : seconds[c]) {
                total += v;
            }
            const double denom = static_cast<double>(calls[c]);
            for (std::size_t p = 0; p < ResamplingDepositProfilePhaseCount; ++p) {
                const double value = seconds[c][p];
                const double percent = total > std::numeric_limits<double>::min()
                    ? 100.0 * value / total : 0.0;
                out << resampling_deposit_profile_context_name(context) << ','
                    << resampling_deposit_profile_phase_name(p) << ','
                    << value << ','
                    << (1000.0 * value / denom) << ','
                    << percent << ','
                    << calls[c] << ','
                    << particlesVisited[c] << ','
                    << fluidParticles[c] << ','
                    << cells[c] << '\n';
            }
            out << resampling_deposit_profile_context_name(context) << ",total_deposit,"
                << total << ',' << (1000.0 * total / denom) << ",100,"
                << calls[c] << ',' << particlesVisited[c] << ','
                << fluidParticles[c] << ',' << cells[c] << '\n';
        }
    }
};

DepositProfileAccumulator& deposit_profile_accumulator() {
    static DepositProfileAccumulator acc;
    return acc;
}


bool cell_center_inside_domain(int ix, int iy, const CellGrid& grid, const FluidDomainBounds& domain) {
    const double x = (static_cast<double>(ix) + 0.5) * grid.dx;
    const double y = (static_cast<double>(iy) + 0.5) * grid.dy;
    return point_is_inside_fluid_domain(x, y, domain);
}

bool cell_is_active_for_resampling(int ix,
                                   int iy,
                                   const CellGrid& grid,
                                   const SimulationParams& params,
                                   const FluidDomainBounds& domain,
                                   double time) {
    if (!cell_center_inside_domain(ix, iy, grid, domain)) {
        return false;
    }
    if (!immersed_solid_enabled(params)) {
        return true;
    }
    const double solidFraction = immersed_solid_fraction_in_cell(
        ix, iy, grid, GridShift{}, params, domain, time);
    const double fluidFraction = 1.0 - solidFraction;
    return fluidFraction > params.resamplingActiveFluidFractionThreshold;
}

double passive_cell_distance(std::int32_t a,
                             std::int32_t b,
                             const CellGrid& grid,
                             const SimulationParams& params) {
    if (a < 0 || b < 0 || grid.Nx <= 0 || grid.Ny <= 0) {
        return 0.0;
    }
    const int ax = static_cast<int>(a) % grid.Nx;
    const int ay = static_cast<int>(a) / grid.Nx;
    const int bx = static_cast<int>(b) % grid.Nx;
    const int by = static_cast<int>(b) / grid.Nx;

    int dx = std::abs(ax - bx);
    int dy = std::abs(ay - by);
    if (is_x_periodic(params)) {
        dx = std::min(dx, grid.Nx - dx);
    }
    if (is_y_periodic(params)) {
        dy = std::min(dy, grid.Ny - dy);
    }
    return std::sqrt(static_cast<double>(dx * dx + dy * dy));
}

void deterministic_receiver_position(std::int32_t cell,
                                     std::uint64_t ordinal,
                                     const CellGrid& grid,
                                     double& x,
                                     double& y) {
    if (cell < 0 || cell >= grid.numCells || grid.Nx <= 0 || grid.Ny <= 0) {
        throw std::runtime_error("deterministic_receiver_position: invalid receiver cell");
    }
    const int ix = static_cast<int>(cell) % grid.Nx;
    const int iy = static_cast<int>(cell) / grid.Nx;

    // Deterministic 4x4 interior stencil.  It avoids exact particle overlap in
    // simple smoke tests while staying safely inside the receiver cell.  Later
    // remap/thermalisation patches may replace this by a local stochastic or
    // energy-preserving placement rule.
    const std::uint64_t q = ordinal % 16u;
    const double fx = 0.2 + 0.2 * static_cast<double>(q % 4u);
    const double fy = 0.2 + 0.2 * static_cast<double>(q / 4u);
    x = (static_cast<double>(ix) + fx) * grid.dx;
    y = (static_cast<double>(iy) + fy) * grid.dy;
}

} // namespace

const char* resampling_population_guard_profile_phase_name(const std::size_t phaseIndex) {
    static constexpr const char* names[ResamplingPopulationGuardProfilePhaseCount] = {
        "init_thresholds",
        "count_copy",
        "stats_before",
        "ensure_cell_particle_index",
        "overfull_extraction_loop",
        "underfull_split_loop",
        "stats_after_finalize",
        "overfull_candidate_setup",
        "overfull_particle_scan",
        "overfull_apply_mutation",
        "overfull_diagnostics",
        "underfull_candidate_setup",
        "underfull_particle_scan",
        "underfull_apply_mutation",
        "underfull_diagnostics",
        "overfull_mutation_momentum_merge",
        "overfull_mutation_state_write",
        "overfull_mutation_role_inactivate",
        "overfull_mutation_pool_push",
        "overfull_mutation_count_update",
        "underfull_mutation_pool_pop",
        "underfull_mutation_particle_clone",
        "underfull_mutation_role_activate",
        "underfull_mutation_pool_fluid_push",
        "underfull_mutation_counters_update"
    };
    return phaseIndex < ResamplingPopulationGuardProfilePhaseCount ? names[phaseIndex] : "unknown";
}

const char* resampling_mass_guard_profile_phase_name(const std::size_t phaseIndex) {
    static constexpr const char* names[ResamplingMassGuardProfilePhaseCount] = {
        "init_validate",
        "build_particles_by_cell",
        "cell_loop",
        "finalize"
    };
    return phaseIndex < ResamplingMassGuardProfilePhaseCount ? names[phaseIndex] : "unknown";
}

const char* resampling_deposit_profile_phase_name(const std::size_t phaseIndex) {
    static constexpr const char* names[ResamplingDepositProfilePhaseCount] = {
        "validate_resize",
        "clear_arrays",
        "role_counts",
        "particle_loop_cell_accum",
        "reduce_cells_finalize",
        "active_wet_classification",
        "poor_rich_classification",
        "candidate_lists",
        "mutation_plan_cell_index",
        "transfer_plan_build",
        "donor_particle_selection",
        "passive_extraction_plan"
    };
    return phaseIndex < ResamplingDepositProfilePhaseCount ? names[phaseIndex] : "unknown";
}

const char* resampling_deposit_profile_context_name(const ResamplingDepositProfileContext context) {
    switch (context) {
        case ResamplingDepositProfileContext::Generic: return "generic";
        case ResamplingDepositProfileContext::Initial: return "initial";
        case ResamplingDepositProfileContext::PostGuard: return "post_guard";
        case ResamplingDepositProfileContext::PostEdit: return "post_edit";
        case ResamplingDepositProfileContext::PostRemap: return "post_remap";
        case ResamplingDepositProfileContext::PostThermal: return "post_thermal";
        case ResamplingDepositProfileContext::MainInitial: return "main_initial";
        case ResamplingDepositProfileContext::Count: break;
    }
    return "unknown";
}


ResamplingParticlePoolDiagnostics rebuild_resampling_particle_pool(
    const ParticleState& state,
    ResamplingParticlePoolWorkspace& pool) {
    validate_particle_state(state, "rebuild_resampling_particle_pool");
    const std::size_t n = static_cast<std::size_t>(state.Np);

    pool.allocatedParticles = state.Np;
    pool.freeInactiveSlots.clear();
    pool.latentSlots.clear();
    pool.fluidSlots.clear();
    pool.freeInactiveSlots.reserve(n);
    pool.latentSlots.reserve(n);
    pool.fluidSlots.reserve(n);

    ResamplingParticlePoolDiagnostics d{};
    d.built = true;
    d.storageSlots = state.Np;

    for (std::size_t i = 0; i < n; ++i) {
        const std::uint8_t r = particle_role_value(state, i);
        const std::uint64_t index = static_cast<std::uint64_t>(i);
        if (is_fluid_role(r)) {
            pool.fluidSlots.push_back(index);
        } else if (is_latent_role(r)) {
            pool.latentSlots.push_back(index);
        } else if (is_inactive_role(r)) {
            pool.freeInactiveSlots.push_back(index);
        } else {
            throw std::runtime_error("rebuild_resampling_particle_pool: invalid particle role");
        }
    }

    d.fluidSlots = static_cast<std::uint64_t>(pool.fluidSlots.size());
    d.latentSlots = static_cast<std::uint64_t>(pool.latentSlots.size());
    d.freeSlots = static_cast<std::uint64_t>(pool.freeInactiveSlots.size());
    d.nFluid = d.fluidSlots;
    d.nLatent = d.latentSlots;
    d.nInactive = d.freeSlots;

    if (!pool.freeInactiveSlots.empty()) {
        d.firstFreeIndex = pool.freeInactiveSlots.front();
        d.lastFreeIndex = pool.freeInactiveSlots.back();
    }
    if (d.storageSlots > 0u) {
        const double invStorage = 1.0 / static_cast<double>(d.storageSlots);
        d.freeSlotFraction = static_cast<double>(d.freeSlots) * invStorage;
        d.dormantSlotFraction = static_cast<double>(d.freeSlots + d.latentSlots) * invStorage;
    }

    pool.diagnostics = d;
    return d;
}

bool resampling_pool_has_free_slot(const ResamplingParticlePoolWorkspace& pool) {
    return !pool.freeInactiveSlots.empty();
}

std::uint64_t resampling_pool_pop_free_slot(ResamplingParticlePoolWorkspace& pool) {
    if (pool.freeInactiveSlots.empty()) {
        throw std::runtime_error("resampling_pool_pop_free_slot: no inactive slot available");
    }
    const std::uint64_t index = pool.freeInactiveSlots.back();
    pool.freeInactiveSlots.pop_back();
    pool.diagnostics.freeSlots = static_cast<std::uint64_t>(pool.freeInactiveSlots.size());
    if (pool.freeInactiveSlots.empty()) {
        pool.diagnostics.firstFreeIndex = kInvalidParticleIndex;
        pool.diagnostics.lastFreeIndex = kInvalidParticleIndex;
    } else {
        pool.diagnostics.firstFreeIndex = pool.freeInactiveSlots.front();
        pool.diagnostics.lastFreeIndex = pool.freeInactiveSlots.back();
    }
    if (pool.diagnostics.storageSlots > 0u) {
        pool.diagnostics.freeSlotFraction =
            static_cast<double>(pool.diagnostics.freeSlots) / static_cast<double>(pool.diagnostics.storageSlots);
        pool.diagnostics.dormantSlotFraction =
            static_cast<double>(pool.diagnostics.freeSlots + pool.diagnostics.latentSlots) /
            static_cast<double>(pool.diagnostics.storageSlots);
    }
    return index;
}

void resampling_pool_push_free_slot(ResamplingParticlePoolWorkspace& pool, std::uint64_t index) {
    if (index == kInvalidParticleIndex) {
        throw std::runtime_error("resampling_pool_push_free_slot: invalid index");
    }
    pool.freeInactiveSlots.push_back(index);
    pool.diagnostics.freeSlots = static_cast<std::uint64_t>(pool.freeInactiveSlots.size());
    pool.diagnostics.firstFreeIndex = pool.freeInactiveSlots.front();
    pool.diagnostics.lastFreeIndex = pool.freeInactiveSlots.back();
    if (pool.diagnostics.storageSlots > 0u) {
        pool.diagnostics.freeSlotFraction =
            static_cast<double>(pool.diagnostics.freeSlots) / static_cast<double>(pool.diagnostics.storageSlots);
        pool.diagnostics.dormantSlotFraction =
            static_cast<double>(pool.diagnostics.freeSlots + pool.diagnostics.latentSlots) /
            static_cast<double>(pool.diagnostics.storageSlots);
    }
}

void attach_resampling_pool_diagnostics(WeightedResamplingDiagnostics& diagnostics,
                                        const ResamplingParticlePoolDiagnostics& poolDiagnostics) {
    diagnostics.poolBuilt = poolDiagnostics.built;
    diagnostics.poolStorageSlots = poolDiagnostics.storageSlots;
    diagnostics.poolFreeSlots = poolDiagnostics.freeSlots;
    diagnostics.poolLatentSlots = poolDiagnostics.latentSlots;
    diagnostics.poolFluidSlots = poolDiagnostics.fluidSlots;
    diagnostics.poolFirstFreeIndex = poolDiagnostics.firstFreeIndex;
    diagnostics.poolLastFreeIndex = poolDiagnostics.lastFreeIndex;
    diagnostics.poolFreeSlotFraction = poolDiagnostics.freeSlotFraction;
    diagnostics.poolDormantSlotFraction = poolDiagnostics.dormantSlotFraction;
    diagnostics.poolCanSeedReceivers = poolDiagnostics.freeSlots >= diagnostics.nReceiverCells;
    diagnostics.hypotheticalPoolFreeSlotsAfterExtraction =
        poolDiagnostics.freeSlots + diagnostics.nExtractionParticles;
}

ResamplingLatentActivationDiagnostics apply_resampling_latent_activation(
    ParticleState& state,
    ResamplingParticlePoolWorkspace& pool,
    const WeightedRealFluidDepositWorkspace& depositWorkspace,
    const WeightedResamplingDiagnostics& depositDiagnostics,
    const SimulationParams& params,
    const CellGrid& grid) {
    validate_particle_state(state, "apply_resampling_latent_activation");
    ensure_particle_roles(state, ParticleRole::Fluid);

    ResamplingLatentActivationDiagnostics d{};
    d.attempted = true;
    d.latentSlotsBefore = static_cast<std::uint64_t>(pool.latentSlots.size());
    d.fluidSlotsBefore = static_cast<std::uint64_t>(pool.fluidSlots.size());
    d.targetCellMass = depositDiagnostics.targetCellMass;

    const int nc = depositWorkspace.allocatedCells;
    if (nc <= 0 || depositWorkspace.wetCell.size() != static_cast<std::size_t>(nc) ||
        depositWorkspace.poorCell.size() != static_cast<std::size_t>(nc)) {
        throw std::runtime_error("apply_resampling_latent_activation: invalid deposit workspace");
    }
    const int maxPerCell = std::max(1, params.resamplingLatentActivationMaxPerCell);
    d.activationParticleMass = params.resamplingLatentActivationParticleMass > 0.0
        ? params.resamplingLatentActivationParticleMass
        : (d.targetCellMass > 0.0 ? d.targetCellMass / static_cast<double>(maxPerCell) : 1.0);
    if (!(d.activationParticleMass > 0.0) || !std::isfinite(d.activationParticleMass)) {
        return d;
    }

    std::vector<std::int32_t> receiverCells;
    receiverCells.reserve(depositWorkspace.receiverPoorCells.size());
    std::vector<std::uint8_t> seenCell(static_cast<std::size_t>(nc), 0u);
    auto add_receiver = [&](std::int32_t c) {
        if (c < 0 || c >= nc) {
            return;
        }
        const std::size_t kk = static_cast<std::size_t>(c);
        if (!seenCell[kk]) {
            seenCell[kk] = 1u;
            receiverCells.push_back(c);
        }
    };
    for (const std::int32_t c : depositWorkspace.emptyWetReceiverCells) {
        add_receiver(c);
    }
    for (const std::int32_t c : depositWorkspace.receiverPoorCells) {
        add_receiver(c);
    }

    std::vector<std::uint32_t> activatedPerCell(static_cast<std::size_t>(nc), 0u);
    std::vector<std::uint8_t> activatedCell(static_cast<std::size_t>(nc), 0u);

    for (const std::int32_t c : receiverCells) {
        d.receiverCellsConsidered += 1u;
        if (c < 0 || c >= nc) {
            d.skippedInvalidReceiverCells += 1u;
            continue;
        }
        const std::size_t kk = static_cast<std::size_t>(c);
        if (!depositWorkspace.wetCell[kk]) {
            d.skippedReceiverNotWet += 1u;
            d.noDryCellsActivated = false;
            continue;
        }
        if (!depositWorkspace.poorCell[kk]) {
            d.skippedReceiverNotPoor += 1u;
            continue;
        }

        for (int q = 0; q < maxPerCell; ++q) {
            if (pool.latentSlots.empty()) {
                d.skippedNoLatentSlots += 1u;
                break;
            }
            const std::uint64_t slot64 = pool.latentSlots.back();
            pool.latentSlots.pop_back();
            if (slot64 == kInvalidParticleIndex || slot64 >= state.Np) {
                d.allSourcesWereLatent = false;
                continue;
            }
            const std::size_t slot = static_cast<std::size_t>(slot64);
            if (!is_latent_particle(state, slot)) {
                d.allSourcesWereLatent = false;
                continue;
            }

            double newX = 0.0;
            double newY = 0.0;
            deterministic_receiver_position(c, activatedPerCell[kk], grid, newX, newY);

            const double ux = depositWorkspace.mass[kk] > 0.0 ? depositWorkspace.ux[kk] : 0.0;
            const double uy = depositWorkspace.mass[kk] > 0.0 ? depositWorkspace.uy[kk] : 0.0;
            state.x[slot] = newX;
            state.y[slot] = newY;
            state.vx[slot] = ux;
            state.vy[slot] = uy;
            state.mass[slot] = d.activationParticleMass;
            set_particle_role(state, slot, ParticleRole::Fluid);
            pool.fluidSlots.push_back(slot64);

            activatedPerCell[kk] += 1u;
            activatedCell[kk] = 1u;
            d.particlesActivated += 1u;
            d.roleChanges += 1u;
            d.activatedMass += d.activationParticleMass;
            d.activatedMomentumX += d.activationParticleMass * ux;
            d.activatedMomentumY += d.activationParticleMass * uy;
            d.activatedKineticEnergy += 0.5 * d.activationParticleMass * (ux * ux + uy * uy);
            if (d.firstActivatedParticle == kInvalidParticleIndex) {
                d.firstActivatedParticle = slot64;
                d.firstActivatedCell = c;
            }
            d.lastActivatedParticle = slot64;
            d.lastActivatedCell = c;
        }
        if (activatedPerCell[kk] >= static_cast<std::uint32_t>(maxPerCell)) {
            d.skippedMaxPerCell += 1u;
        }
    }

    for (const std::uint8_t flag : activatedCell) {
        d.cellsActivated += flag ? 1u : 0u;
    }
    d.latentSlotsAfter = static_cast<std::uint64_t>(pool.latentSlots.size());
    d.fluidSlotsAfter = static_cast<std::uint64_t>(pool.fluidSlots.size());
    d.applied = d.particlesActivated > 0u;
    d.allSourcesWereLatent = d.allSourcesWereLatent && d.roleChanges == d.particlesActivated;
    d.noDryCellsActivated = d.noDryCellsActivated && d.skippedReceiverNotWet == 0u;
    return d;
}

void attach_resampling_latent_activation_diagnostics(
    WeightedResamplingDiagnostics& diagnostics,
    const ResamplingLatentActivationDiagnostics& activationDiagnostics) {
    diagnostics.latentActivationAttempted = activationDiagnostics.attempted;
    diagnostics.latentActivationApplied = activationDiagnostics.applied;
    diagnostics.latentActivationReceiverCellsConsidered = activationDiagnostics.receiverCellsConsidered;
    diagnostics.latentActivationCellsActivated = activationDiagnostics.cellsActivated;
    diagnostics.latentActivationParticlesActivated = activationDiagnostics.particlesActivated;
    diagnostics.latentActivationRoleChanges = activationDiagnostics.roleChanges;
    diagnostics.latentActivationSkippedNoLatentSlots = activationDiagnostics.skippedNoLatentSlots;
    diagnostics.latentActivationSkippedInvalidReceiverCells = activationDiagnostics.skippedInvalidReceiverCells;
    diagnostics.latentActivationSkippedReceiverNotWet = activationDiagnostics.skippedReceiverNotWet;
    diagnostics.latentActivationSkippedReceiverNotPoor = activationDiagnostics.skippedReceiverNotPoor;
    diagnostics.latentActivationSkippedMaxPerCell = activationDiagnostics.skippedMaxPerCell;
    diagnostics.latentActivationLatentSlotsBefore = activationDiagnostics.latentSlotsBefore;
    diagnostics.latentActivationLatentSlotsAfter = activationDiagnostics.latentSlotsAfter;
    diagnostics.latentActivationFluidSlotsBefore = activationDiagnostics.fluidSlotsBefore;
    diagnostics.latentActivationFluidSlotsAfter = activationDiagnostics.fluidSlotsAfter;
    diagnostics.latentActivationTargetCellMass = activationDiagnostics.targetCellMass;
    diagnostics.latentActivationParticleMass = activationDiagnostics.activationParticleMass;
    diagnostics.latentActivationMass = activationDiagnostics.activatedMass;
    diagnostics.latentActivationMomentumX = activationDiagnostics.activatedMomentumX;
    diagnostics.latentActivationMomentumY = activationDiagnostics.activatedMomentumY;
    diagnostics.latentActivationKineticEnergy = activationDiagnostics.activatedKineticEnergy;
    diagnostics.firstLatentActivatedParticle = activationDiagnostics.firstActivatedParticle;
    diagnostics.lastLatentActivatedParticle = activationDiagnostics.lastActivatedParticle;
    diagnostics.firstLatentActivatedCell = activationDiagnostics.firstActivatedCell;
    diagnostics.lastLatentActivatedCell = activationDiagnostics.lastActivatedCell;
    diagnostics.latentActivationAllSourcesWereLatent = activationDiagnostics.allSourcesWereLatent;
    diagnostics.latentActivationNoDryCellsActivated = activationDiagnostics.noDryCellsActivated;
}


ResamplingExtractionApplyDiagnostics apply_resampling_extraction_operations(
    ParticleState& state,
    ResamplingParticlePoolWorkspace& pool,
    const WeightedRealFluidDepositWorkspace& depositWorkspace) {
    validate_particle_state(state, "apply_resampling_extraction_operations");
    ensure_particle_roles(state, ParticleRole::Fluid);

    ResamplingExtractionApplyDiagnostics d{};
    d.attempted = true;
    d.operationsConsidered = static_cast<std::uint64_t>(depositWorkspace.passiveExtractionOperations.size());
    d.poolFreeSlotsBefore = static_cast<std::uint64_t>(pool.freeInactiveSlots.size());

    const std::size_t n = static_cast<std::size_t>(state.Np);
    std::vector<std::uint8_t> seen(n, 0u);

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

        d.operationsApplied += 1u;
        d.roleChanges += 1u;
        d.appliedMass += mp;
        d.appliedMomentumX += px;
        d.appliedMomentumY += py;
        d.appliedKineticEnergy += ke;
        if (d.firstAppliedParticle == kInvalidParticleIndex) {
            d.firstAppliedParticle = pi64;
        }
        d.lastAppliedParticle = pi64;
    }

    d.poolFreeSlotsAfter = static_cast<std::uint64_t>(pool.freeInactiveSlots.size());
    d.poolFreeSlotDelta = d.poolFreeSlotsAfter >= d.poolFreeSlotsBefore
        ? d.poolFreeSlotsAfter - d.poolFreeSlotsBefore : 0u;
    d.massResidualVsPlan = d.appliedMass - d.plannedExtractionMass;
    d.applied = d.operationsApplied > 0u;
    d.allAppliedWereFluid = d.allAppliedWereFluid && d.skippedNonFluidParticles == 0u;
    return d;
}

void attach_resampling_extraction_apply_diagnostics(
    WeightedResamplingDiagnostics& diagnostics,
    const ResamplingExtractionApplyDiagnostics& extractionDiagnostics) {
    diagnostics.extractionApplyAttempted = extractionDiagnostics.attempted;
    diagnostics.extractionApplied = extractionDiagnostics.applied;
    diagnostics.extractionApplyOpsConsidered = extractionDiagnostics.operationsConsidered;
    diagnostics.extractionApplyOpsApplied = extractionDiagnostics.operationsApplied;
    diagnostics.extractionApplyRoleChanges = extractionDiagnostics.roleChanges;
    diagnostics.extractionApplySkippedInvalidParticles = extractionDiagnostics.skippedInvalidParticles;
    diagnostics.extractionApplySkippedNonFluidParticles = extractionDiagnostics.skippedNonFluidParticles;
    diagnostics.extractionApplySkippedDuplicateParticles = extractionDiagnostics.skippedDuplicateParticles;
    diagnostics.extractionApplyPoolFreeSlotsBefore = extractionDiagnostics.poolFreeSlotsBefore;
    diagnostics.extractionApplyPoolFreeSlotsAfter = extractionDiagnostics.poolFreeSlotsAfter;
    diagnostics.extractionApplyPoolFreeSlotDelta = extractionDiagnostics.poolFreeSlotDelta;
    diagnostics.extractionApplyMass = extractionDiagnostics.appliedMass;
    diagnostics.extractionApplyMomentumX = extractionDiagnostics.appliedMomentumX;
    diagnostics.extractionApplyMomentumY = extractionDiagnostics.appliedMomentumY;
    diagnostics.extractionApplyKineticEnergy = extractionDiagnostics.appliedKineticEnergy;
    diagnostics.extractionApplyPlannedMass = extractionDiagnostics.plannedExtractionMass;
    diagnostics.extractionApplyMassResidualVsPlan = extractionDiagnostics.massResidualVsPlan;
    diagnostics.firstAppliedExtractionParticle = extractionDiagnostics.firstAppliedParticle;
    diagnostics.lastAppliedExtractionParticle = extractionDiagnostics.lastAppliedParticle;
    diagnostics.extractionApplyNoDuplicateParticles = extractionDiagnostics.noDuplicateParticles;
    diagnostics.extractionApplyAllAppliedWereFluid = extractionDiagnostics.allAppliedWereFluid;
}

ResamplingInsertionApplyDiagnostics apply_resampling_insertion_operations(
    ParticleState& state,
    ResamplingParticlePoolWorkspace& pool,
    const WeightedRealFluidDepositWorkspace& depositWorkspace,
    const CellGrid& grid) {
    validate_particle_state(state, "apply_resampling_insertion_operations");
    ensure_particle_roles(state, ParticleRole::Fluid);

    ResamplingInsertionApplyDiagnostics d{};
    d.attempted = true;
    d.operationsConsidered = static_cast<std::uint64_t>(depositWorkspace.passiveExtractionOperations.size());
    d.poolFreeSlotsBefore = static_cast<std::uint64_t>(pool.freeInactiveSlots.size());

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
        auto freeIt = std::find(pool.freeInactiveSlots.begin(),
                                pool.freeInactiveSlots.end(),
                                op.particleIndex);
        if (freeIt == pool.freeInactiveSlots.end()) {
            d.skippedNoFreeSlots += 1u;
            continue;
        }

        const std::uint64_t slot64 = op.particleIndex;
        pool.freeInactiveSlots.erase(freeIt);
        const std::size_t slot = static_cast<std::size_t>(slot64);

        double newX = 0.0;
        double newY = 0.0;
        deterministic_receiver_position(op.receiverCell, d.operationsApplied, grid, newX, newY);

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
    return d;
}

void attach_resampling_insertion_apply_diagnostics(
    WeightedResamplingDiagnostics& diagnostics,
    const ResamplingInsertionApplyDiagnostics& insertionDiagnostics) {
    diagnostics.insertionApplyAttempted = insertionDiagnostics.attempted;
    diagnostics.insertionApplied = insertionDiagnostics.applied;
    diagnostics.insertionApplyOpsConsidered = insertionDiagnostics.operationsConsidered;
    diagnostics.insertionApplyOpsApplied = insertionDiagnostics.operationsApplied;
    diagnostics.insertionApplyRoleChanges = insertionDiagnostics.roleChanges;
    diagnostics.insertionApplySkippedInvalidSourceParticles = insertionDiagnostics.skippedInvalidSourceParticles;
    diagnostics.insertionApplySkippedSourceNotInactive = insertionDiagnostics.skippedSourceNotInactive;
    diagnostics.insertionApplySkippedInvalidReceiverCells = insertionDiagnostics.skippedInvalidReceiverCells;
    diagnostics.insertionApplySkippedNoFreeSlots = insertionDiagnostics.skippedNoFreeSlots;
    diagnostics.insertionApplySkippedInvalidMass = insertionDiagnostics.skippedInvalidMass;
    diagnostics.insertionApplyPoolFreeSlotsBefore = insertionDiagnostics.poolFreeSlotsBefore;
    diagnostics.insertionApplyPoolFreeSlotsAfter = insertionDiagnostics.poolFreeSlotsAfter;
    diagnostics.insertionApplyPoolFreeSlotDelta = insertionDiagnostics.poolFreeSlotDelta;
    diagnostics.insertionApplyMass = insertionDiagnostics.insertedMass;
    diagnostics.insertionApplyMomentumX = insertionDiagnostics.insertedMomentumX;
    diagnostics.insertionApplyMomentumY = insertionDiagnostics.insertedMomentumY;
    diagnostics.insertionApplyKineticEnergy = insertionDiagnostics.insertedKineticEnergy;
    diagnostics.insertionApplyPlannedMass = insertionDiagnostics.plannedInsertionMass;
    diagnostics.insertionApplyMassResidualVsPlan = insertionDiagnostics.massResidualVsPlan;
    diagnostics.firstAppliedInsertionParticle = insertionDiagnostics.firstInsertedParticle;
    diagnostics.lastAppliedInsertionParticle = insertionDiagnostics.lastInsertedParticle;
    diagnostics.firstAppliedInsertionReceiverCell = insertionDiagnostics.firstInsertionReceiverCell;
    diagnostics.lastAppliedInsertionReceiverCell = insertionDiagnostics.lastInsertionReceiverCell;
    diagnostics.insertionApplyNoInvalidReceiverCells = insertionDiagnostics.noInvalidReceiverCells;
    diagnostics.insertionApplyAllSourcesWereInactive = insertionDiagnostics.allSourcesWereInactive;
}


namespace {

void ensure_cell_particle_index(WeightedRealFluidDepositWorkspace& ws,
                                const ParticleState& state,
                                int nc) {
    ws.cellParticleOffsets.assign(static_cast<std::size_t>(nc) + 1u, 0u);
    for (int c = 0; c < nc; ++c) {
        ws.cellParticleOffsets[static_cast<std::size_t>(c) + 1u] =
            ws.cellParticleOffsets[static_cast<std::size_t>(c)] +
            static_cast<std::uint64_t>(ws.count[static_cast<std::size_t>(c)]);
    }
    ws.cellParticleIndices.assign(static_cast<std::size_t>(ws.cellParticleOffsets.back()),
                                  kInvalidParticleIndex);
    ws.cellParticleCursor.assign(ws.cellParticleOffsets.begin(), ws.cellParticleOffsets.end() - 1);
    const std::size_t n = static_cast<std::size_t>(state.Np);
    for (std::size_t i = 0; i < n; ++i) {
        if (!is_fluid_particle(state, i)) {
            continue;
        }
        if (i >= ws.cellId.size()) {
            continue;
        }
        const int c = ws.cellId[i];
        if (c < 0 || c >= nc) {
            continue;
        }
        const std::size_t cc = static_cast<std::size_t>(c);
        const std::size_t pos = static_cast<std::size_t>(ws.cellParticleCursor[cc]++);
        if (pos < ws.cellParticleIndices.size()) {
            ws.cellParticleIndices[pos] = static_cast<std::uint64_t>(i);
        }
    }
}

void accumulate_wet_population_stats(const WeightedRealFluidDepositWorkspace& ws,
                                      const std::vector<std::uint32_t>& counts,
                                      int nMin,
                                      std::uint64_t& wetCells,
                                      std::uint32_t& minWetN,
                                      double& meanWetN,
                                      double& stdWetN,
                                      double& lowFraction) {
    wetCells = 0u;
    minWetN = std::numeric_limits<std::uint32_t>::max();
    double sum = 0.0;
    double sum2 = 0.0;
    std::uint64_t low = 0u;
    const int nc = ws.allocatedCells;
    for (int c = 0; c < nc; ++c) {
        const std::size_t kk = static_cast<std::size_t>(c);
        if (kk >= ws.wetCell.size() || !ws.wetCell[kk]) {
            continue;
        }
        const std::uint32_t n = counts[kk];
        wetCells += 1u;
        minWetN = std::min(minWetN, n);
        const double dn = static_cast<double>(n);
        sum += dn;
        sum2 += dn * dn;
        if (static_cast<int>(n) < nMin) {
            low += 1u;
        }
    }
    if (wetCells == 0u) {
        minWetN = 0u;
        meanWetN = 0.0;
        stdWetN = 0.0;
        lowFraction = 0.0;
        return;
    }
    const double inv = 1.0 / static_cast<double>(wetCells);
    meanWetN = sum * inv;
    stdWetN = std::sqrt(std::max(0.0, sum2 * inv - meanWetN * meanWetN));
    lowFraction = static_cast<double>(low) * inv;
}

} // namespace

ResamplingPopulationGuardDiagnostics apply_resampling_population_support_guard(
    ParticleState& state,
    ResamplingParticlePoolWorkspace& pool,
    WeightedRealFluidDepositWorkspace& depositWorkspace,
    const WeightedResamplingDiagnostics& depositDiagnostics,
    const SimulationParams& params,
    const CellGrid& /*grid*/) {
    validate_particle_state(state, "apply_resampling_population_support_guard");
    ensure_particle_roles(state, ParticleRole::Fluid);

    ResamplingPopulationGuardDiagnostics d{};
    d.attempted = true;
    const int nc = depositWorkspace.allocatedCells;
    {
        MPCD_POP_GUARD_PROFILE(d.profile, InitThresholds);
        d.freeSlotsBefore = static_cast<std::uint64_t>(pool.freeInactiveSlots.size());

        if (nc <= 0 || depositWorkspace.count.size() != static_cast<std::size_t>(nc) ||
            depositWorkspace.wetCell.size() != static_cast<std::size_t>(nc)) {
            return d;
        }

        const double meanParticleMass = depositDiagnostics.particleMassMean > 0.0
            ? depositDiagnostics.particleMassMean : 1.0;
        const int inferredTarget = std::max(1, static_cast<int>(std::llround(
            (depositDiagnostics.targetCellMass > 0.0 ? depositDiagnostics.targetCellMass : meanParticleMass) /
            meanParticleMass)));
        d.nTarget = params.resamplingPopulationNTarget > 0
            ? params.resamplingPopulationNTarget : inferredTarget;
        d.nMin = params.resamplingPopulationNMin > 0
            ? params.resamplingPopulationNMin
            : std::max(1, static_cast<int>(std::floor(params.resamplingPopulationNMinFraction * static_cast<double>(d.nTarget))));
        d.nMax = params.resamplingPopulationNMax > 0
            ? params.resamplingPopulationNMax
            : std::max(d.nTarget, static_cast<int>(std::ceil(params.resamplingPopulationNMaxFraction * static_cast<double>(d.nTarget))));
        d.nMin = std::min(d.nMin, d.nTarget);
        d.nMax = std::max(d.nMax, d.nTarget);
    }

    std::vector<std::uint32_t> countAfter;
    std::vector<int>& overfullCandidateCells = depositWorkspace.populationGuardOverfullCells;
    std::vector<int>& underfullCandidateCells = depositWorkspace.populationGuardUnderfullCells;
    {
        MPCD_POP_GUARD_PROFILE(d.profile, CountCopy);
        countAfter = depositWorkspace.count;
        overfullCandidateCells.clear();
        underfullCandidateCells.clear();
        if (overfullCandidateCells.capacity() < static_cast<std::size_t>(nc)) {
            overfullCandidateCells.reserve(static_cast<std::size_t>(nc));
        }
        if (underfullCandidateCells.capacity() < static_cast<std::size_t>(nc)) {
            underfullCandidateCells.reserve(static_cast<std::size_t>(nc));
        }
        for (int c = 0; c < nc; ++c) {
            const std::size_t kk = static_cast<std::size_t>(c);
            if (!depositWorkspace.wetCell[kk]) {
                continue;
            }
            const int nCell = static_cast<int>(countAfter[kk]);
            if (nCell > d.nMax) {
                overfullCandidateCells.push_back(c);
            } else if (nCell < d.nMin) {
                underfullCandidateCells.push_back(c);
            }
        }
        d.overfullCandidateCells = static_cast<std::uint64_t>(overfullCandidateCells.size());
        d.underfullCandidateCells = static_cast<std::uint64_t>(underfullCandidateCells.size());
    }
    {
        MPCD_POP_GUARD_PROFILE(d.profile, StatsBefore);
        accumulate_wet_population_stats(depositWorkspace, countAfter, d.nMin,
                                        d.wetCellsConsidered, d.wetNMinBefore,
                                        d.wetNMeanBefore, d.wetNStdBefore,
                                        d.wetLowNFractionBefore);
    }
    if (d.wetCellsConsidered == 0u) {
        d.freeSlotsAfter = d.freeSlotsBefore;
        return d;
    }

    {
        MPCD_POP_GUARD_PROFILE(d.profile, EnsureCellParticleIndex);
        ensure_cell_particle_index(depositWorkspace, state, nc);
    }

    std::uint64_t extractionBudget = params.resamplingPopulationMaxExtractionsPerStep > 0
        ? static_cast<std::uint64_t>(params.resamplingPopulationMaxExtractionsPerStep)
        : std::numeric_limits<std::uint64_t>::max();
    const int maxExtractPerCell = params.resamplingPopulationMaxExtractionsPerCell > 0
        ? params.resamplingPopulationMaxExtractionsPerCell : std::numeric_limits<int>::max();

    {
        MPCD_POP_GUARD_PROFILE(d.profile, OverfullExtractionLoop);
    for (std::size_t cc = 0; cc < overfullCandidateCells.size() && extractionBudget > 0u; ++cc) {
        const int c = overfullCandidateCells[cc];
        const std::size_t kk = static_cast<std::size_t>(c);
        if (static_cast<int>(countAfter[kk]) <= d.nMax) {
            continue;
        }
        d.overfullCells += 1u;
        int need = static_cast<int>(countAfter[kk]) - d.nTarget;
        if (need <= 0) {
            continue;
        }
        const int allowed = std::min(need, maxExtractPerCell);
        int doneCell = 0;
        std::uint64_t begin = 0u;
        std::uint64_t end = 0u;
        {
            MPCD_POP_GUARD_PROFILE(d.profile, OverfullCandidateSetup);
            begin = kk + 1u < depositWorkspace.cellParticleOffsets.size()
                ? depositWorkspace.cellParticleOffsets[kk] : 0u;
            end = kk + 1u < depositWorkspace.cellParticleOffsets.size()
                ? depositWorkspace.cellParticleOffsets[kk + 1u] : 0u;
            const std::uint64_t span = end >= begin ? (end - begin) : 0u;
            d.overfullCandidateParticleRefs += span;
            d.overfullCandidatePopulationMax = std::max(
                d.overfullCandidatePopulationMax, static_cast<std::uint32_t>(std::min<std::uint64_t>(
                    span, static_cast<std::uint64_t>(std::numeric_limits<std::uint32_t>::max()))));
        }
        while (doneCell < allowed && extractionBudget > 0u && static_cast<int>(countAfter[kk]) > d.nTarget) {
            std::uint64_t victim64 = kInvalidParticleIndex;
            std::uint64_t survivor64 = kInvalidParticleIndex;
            double victimMass = std::numeric_limits<double>::infinity();
            double survivorMass = -1.0;
            {
                MPCD_POP_GUARD_PROFILE(d.profile, OverfullParticleScan);
                d.overfullScanPasses += 1u;
                for (std::uint64_t pp = begin; pp < end; ++pp) {
                    d.overfullParticleRefsScanned += 1u;
                    if (pp >= depositWorkspace.cellParticleIndices.size()) break;
                    const std::uint64_t pi64 = depositWorkspace.cellParticleIndices[static_cast<std::size_t>(pp)];
                    if (pi64 == kInvalidParticleIndex || pi64 >= state.Np) continue;
                    const std::size_t pi = static_cast<std::size_t>(pi64);
                    if (!is_fluid_particle(state, pi)) continue;
                    const double mp = state.mass[pi];
                    if (!(mp > 0.0)) continue;
                    d.overfullEligibleParticleRefs += 1u;
                    if (mp < victimMass) { victimMass = mp; victim64 = pi64; }
                    if (mp > survivorMass) { survivorMass = mp; survivor64 = pi64; }
                }
            }
            if (victim64 == kInvalidParticleIndex || survivor64 == kInvalidParticleIndex || victim64 == survivor64) {
                { MPCD_POP_GUARD_PROFILE(d.profile, OverfullDiagnostics); d.skippedExtractionLimit += 1u; }
                break;
            }
            const std::size_t victim = static_cast<std::size_t>(victim64);
            const std::size_t survivor = static_cast<std::size_t>(survivor64);
            const double mv = state.mass[victim];
            const double ms = state.mass[survivor];
            const double mNew = mv + ms;
            if (!(mNew > 0.0)) {
                { MPCD_POP_GUARD_PROFILE(d.profile, OverfullDiagnostics); d.skippedExtractionLimit += 1u; }
                break;
            }
            {
                MPCD_POP_GUARD_PROFILE(d.profile, OverfullApplyMutation);
                double vxNew = 0.0;
                double vyNew = 0.0;
                {
                    MPCD_POP_GUARD_PROFILE(d.profile, OverfullMutationMomentumMerge);
                    vxNew = (ms * state.vx[survivor] + mv * state.vx[victim]) / mNew;
                    vyNew = (ms * state.vy[survivor] + mv * state.vy[victim]) / mNew;
                    d.extractedMass += mv;
                    d.extractedMomentumX += mv * state.vx[victim];
                    d.extractedMomentumY += mv * state.vy[victim];
                }
                {
                    MPCD_POP_GUARD_PROFILE(d.profile, OverfullMutationStateWrite);
                    state.mass[survivor] = mNew;
                    state.vx[survivor] = vxNew;
                    state.vy[survivor] = vyNew;
                }
                {
                    MPCD_POP_GUARD_PROFILE(d.profile, OverfullMutationRoleInactivate);
                    set_particle_role_preconditioned(state, victim, ParticleRole::Inactive);
                    if (victim < depositWorkspace.cellId.size()) {
                        depositWorkspace.cellId[victim] = -1;
                    }
                }
                {
                    MPCD_POP_GUARD_PROFILE(d.profile, OverfullMutationPoolPush);
                    resampling_pool_push_free_slot(pool, victim64);
                }
                {
                    MPCD_POP_GUARD_PROFILE(d.profile, OverfullMutationCountUpdate);
                    countAfter[kk] -= 1u;
                }
            }
            {
                MPCD_POP_GUARD_PROFILE(d.profile, OverfullDiagnostics);
                d.extractedParticles += 1u;
                doneCell += 1;
                extractionBudget -= 1u;
            }
        }
        {
            MPCD_POP_GUARD_PROFILE(d.profile, OverfullDiagnostics);
            if (doneCell > 0) {
                d.cellsExtracted += 1u;
                d.overfullEditedCells += 1u;
            }
            if (need > doneCell) {
                d.skippedExtractionLimit += static_cast<std::uint64_t>(need - doneCell);
            }
        }
    }

    }

    std::uint64_t splitBudget = params.resamplingPopulationMaxSplitsPerStep > 0
        ? static_cast<std::uint64_t>(params.resamplingPopulationMaxSplitsPerStep)
        : std::numeric_limits<std::uint64_t>::max();
    const int maxSplitPerCell = params.resamplingPopulationMaxSplitsPerCell > 0
        ? params.resamplingPopulationMaxSplitsPerCell : std::numeric_limits<int>::max();

    {
        MPCD_POP_GUARD_PROFILE(d.profile, UnderfullSplitLoop);
    for (std::size_t cc = 0; cc < underfullCandidateCells.size() && splitBudget > 0u; ++cc) {
        const int c = underfullCandidateCells[cc];
        const std::size_t kk = static_cast<std::size_t>(c);
        if (static_cast<int>(countAfter[kk]) >= d.nMin) {
            continue;
        }
        d.underfullCells += 1u;
        if (countAfter[kk] == 0u) {
            {
                MPCD_POP_GUARD_PROFILE(d.profile, UnderfullDiagnostics);
                d.emptyUnderfullCells += 1u;
                d.skippedEmptyCells += 1u;
            }
            continue;
        }
        int need = d.nTarget - static_cast<int>(countAfter[kk]);
        if (need <= 0) {
            continue;
        }
        const int allowed = std::min(need, maxSplitPerCell);
        int doneCell = 0;
        std::uint64_t begin = 0u;
        std::uint64_t end = 0u;
        {
            MPCD_POP_GUARD_PROFILE(d.profile, UnderfullCandidateSetup);
            begin = kk + 1u < depositWorkspace.cellParticleOffsets.size()
                ? depositWorkspace.cellParticleOffsets[kk] : 0u;
            end = kk + 1u < depositWorkspace.cellParticleOffsets.size()
                ? depositWorkspace.cellParticleOffsets[kk + 1u] : 0u;
            const std::uint64_t span = end >= begin ? (end - begin) : 0u;
            d.underfullCandidateParticleRefs += span;
            d.underfullCandidatePopulationMax = std::max(
                d.underfullCandidatePopulationMax, static_cast<std::uint32_t>(std::min<std::uint64_t>(
                    span, static_cast<std::uint64_t>(std::numeric_limits<std::uint32_t>::max()))));
        }
        while (doneCell < allowed && splitBudget > 0u && static_cast<int>(countAfter[kk]) < d.nTarget) {
            if (!resampling_pool_has_free_slot(pool)) {
                { MPCD_POP_GUARD_PROFILE(d.profile, UnderfullDiagnostics); d.skippedNoFreeSlots += static_cast<std::uint64_t>(allowed - doneCell); }
                break;
            }
            std::uint64_t parent64 = kInvalidParticleIndex;
            double parentMass = -1.0;
            {
                MPCD_POP_GUARD_PROFILE(d.profile, UnderfullParticleScan);
                d.underfullScanPasses += 1u;
                for (std::uint64_t pp = begin; pp < end; ++pp) {
                    d.underfullParticleRefsScanned += 1u;
                    if (pp >= depositWorkspace.cellParticleIndices.size()) break;
                    const std::uint64_t pi64 = depositWorkspace.cellParticleIndices[static_cast<std::size_t>(pp)];
                    if (pi64 == kInvalidParticleIndex || pi64 >= state.Np) continue;
                    const std::size_t pi = static_cast<std::size_t>(pi64);
                    if (!is_fluid_particle(state, pi)) continue;
                    const double mp = state.mass[pi];
                    d.underfullEligibleParticleRefs += 1u;
                    if (mp > parentMass) { parentMass = mp; parent64 = pi64; }
                }
            }
            if (parent64 == kInvalidParticleIndex || !(parentMass > 0.0)) {
                { MPCD_POP_GUARD_PROFILE(d.profile, UnderfullDiagnostics); d.skippedSplitLimit += 1u; }
                break;
            }
            std::uint64_t child64 = kInvalidParticleIndex;
            {
                MPCD_POP_GUARD_PROFILE(d.profile, UnderfullApplyMutation);
                {
                    MPCD_POP_GUARD_PROFILE(d.profile, UnderfullMutationPoolPop);
                    child64 = resampling_pool_pop_free_slot(pool);
                }
                if (child64 == kInvalidParticleIndex || child64 >= state.Np) {
                    d.skippedNoFreeSlots += 1u;
                    break;
                }
                const std::size_t parent = static_cast<std::size_t>(parent64);
                const std::size_t child = static_cast<std::size_t>(child64);
                double halfMass = 0.0;
                {
                    MPCD_POP_GUARD_PROFILE(d.profile, UnderfullMutationParticleClone);
                    halfMass = 0.5 * state.mass[parent];
                    state.mass[parent] = halfMass;
                    state.x[child] = state.x[parent];
                    state.y[child] = state.y[parent];
                    state.vx[child] = state.vx[parent];
                    state.vy[child] = state.vy[parent];
                    state.mass[child] = halfMass;
                    state.type[child] = state.type[parent];
                }
                {
                    MPCD_POP_GUARD_PROFILE(d.profile, UnderfullMutationRoleActivate);
                    set_particle_role_preconditioned(state, child, ParticleRole::Fluid);
                    if (child < depositWorkspace.cellId.size()) {
                        depositWorkspace.cellId[child] = static_cast<int>(kk);
                    }
                }
                {
                    MPCD_POP_GUARD_PROFILE(d.profile, UnderfullMutationPoolFluidPush);
                    pool.fluidSlots.push_back(child64);
                }
                {
                    MPCD_POP_GUARD_PROFILE(d.profile, UnderfullMutationCountersUpdate);
                    countAfter[kk] += 1u;
                    d.splitParticlesCreated += 1u;
                    d.splitMass += halfMass;
                    d.splitMomentumX += halfMass * state.vx[child];
                    d.splitMomentumY += halfMass * state.vy[child];
                    doneCell += 1;
                    splitBudget -= 1u;
                }
            }
        }
        {
            MPCD_POP_GUARD_PROFILE(d.profile, UnderfullDiagnostics);
            if (doneCell > 0) {
                d.cellsSplit += 1u;
                d.underfullEditedCells += 1u;
            }
            if (need > doneCell) {
                d.skippedSplitLimit += static_cast<std::uint64_t>(need - doneCell);
            }
        }
    }

    }

    std::uint64_t wetAfter = 0u;
    {
        MPCD_POP_GUARD_PROFILE(d.profile, StatsAfterFinalize);
    accumulate_wet_population_stats(depositWorkspace, countAfter, d.nMin,
                                    wetAfter, d.wetNMinAfter, d.wetNMeanAfter,
                                    d.wetNStdAfter, d.wetLowNFractionAfter);
    d.freeSlotsAfter = static_cast<std::uint64_t>(pool.freeInactiveSlots.size());
    d.activeParticleDelta = static_cast<std::int64_t>(d.splitParticlesCreated) -
                            static_cast<std::int64_t>(d.extractedParticles);
    d.applied = d.splitParticlesCreated > 0u || d.extractedParticles > 0u;
    }
    return d;
}

void attach_resampling_population_guard_diagnostics(
    WeightedResamplingDiagnostics& diagnostics,
    const ResamplingPopulationGuardDiagnostics& pop) {
    diagnostics.populationGuardAttempted = pop.attempted;
    diagnostics.populationGuardApplied = pop.applied;
    diagnostics.populationGuardNMin = pop.nMin;
    diagnostics.populationGuardNTarget = pop.nTarget;
    diagnostics.populationGuardNMax = pop.nMax;
    diagnostics.populationGuardWetCellsConsidered = pop.wetCellsConsidered;
    diagnostics.populationGuardUnderfullCells = pop.underfullCells;
    diagnostics.populationGuardEmptyUnderfullCells = pop.emptyUnderfullCells;
    diagnostics.populationGuardOverfullCells = pop.overfullCells;
    diagnostics.populationGuardCellsSplit = pop.cellsSplit;
    diagnostics.populationGuardCellsExtracted = pop.cellsExtracted;
    diagnostics.populationGuardOverfullCandidateCells = pop.overfullCandidateCells;
    diagnostics.populationGuardUnderfullCandidateCells = pop.underfullCandidateCells;
    diagnostics.populationGuardOverfullEditedCells = pop.overfullEditedCells;
    diagnostics.populationGuardUnderfullEditedCells = pop.underfullEditedCells;
    diagnostics.populationGuardOverfullCandidateParticleRefs = pop.overfullCandidateParticleRefs;
    diagnostics.populationGuardUnderfullCandidateParticleRefs = pop.underfullCandidateParticleRefs;
    diagnostics.populationGuardOverfullScanPasses = pop.overfullScanPasses;
    diagnostics.populationGuardUnderfullScanPasses = pop.underfullScanPasses;
    diagnostics.populationGuardOverfullParticleRefsScanned = pop.overfullParticleRefsScanned;
    diagnostics.populationGuardUnderfullParticleRefsScanned = pop.underfullParticleRefsScanned;
    diagnostics.populationGuardOverfullEligibleParticleRefs = pop.overfullEligibleParticleRefs;
    diagnostics.populationGuardUnderfullEligibleParticleRefs = pop.underfullEligibleParticleRefs;
    diagnostics.populationGuardOverfullCandidatePopulationMax = pop.overfullCandidatePopulationMax;
    diagnostics.populationGuardUnderfullCandidatePopulationMax = pop.underfullCandidatePopulationMax;
    diagnostics.populationGuardSplitParticlesCreated = pop.splitParticlesCreated;
    diagnostics.populationGuardExtractedParticles = pop.extractedParticles;
    diagnostics.populationGuardSkippedNoFreeSlots = pop.skippedNoFreeSlots;
    diagnostics.populationGuardSkippedEmptyCells = pop.skippedEmptyCells;
    diagnostics.populationGuardSkippedSplitLimit = pop.skippedSplitLimit;
    diagnostics.populationGuardSkippedExtractionLimit = pop.skippedExtractionLimit;
    diagnostics.populationGuardFreeSlotsBefore = pop.freeSlotsBefore;
    diagnostics.populationGuardFreeSlotsAfter = pop.freeSlotsAfter;
    diagnostics.populationGuardActiveParticleDelta = pop.activeParticleDelta;
    diagnostics.populationGuardSplitMass = pop.splitMass;
    diagnostics.populationGuardExtractedMass = pop.extractedMass;
    diagnostics.populationGuardWetNMeanBefore = pop.wetNMeanBefore;
    diagnostics.populationGuardWetNMeanAfter = pop.wetNMeanAfter;
    diagnostics.populationGuardWetNStdBefore = pop.wetNStdBefore;
    diagnostics.populationGuardWetNStdAfter = pop.wetNStdAfter;
    diagnostics.populationGuardWetNMinBefore = pop.wetNMinBefore;
    diagnostics.populationGuardWetNMinAfter = pop.wetNMinAfter;
    diagnostics.populationGuardWetLowNFractionBefore = pop.wetLowNFractionBefore;
    diagnostics.populationGuardWetLowNFractionAfter = pop.wetLowNFractionAfter;
    diagnostics.populationGuardProfileSeconds = pop.profile.seconds;
}


ResamplingRemapApplyDiagnostics apply_resampling_local_mass_momentum_remap(
    ParticleState& state,
    WeightedRealFluidDepositWorkspace& depositWorkspace,
    const WeightedResamplingDiagnostics& depositDiagnostics,
    double massCorrectionStrength,
    double targetCellMassOverride) {
    validate_particle_state(state, "apply_resampling_local_mass_momentum_remap");
    ensure_particle_roles(state, ParticleRole::Fluid);

    ResamplingRemapApplyDiagnostics d{};
    d.attempted = true;
    d.targetCellMass = (targetCellMassOverride > 0.0 && std::isfinite(targetCellMassOverride))
        ? targetCellMassOverride
        : depositDiagnostics.targetCellMass;
    d.massCorrectionStrength = std::clamp(massCorrectionStrength, 0.0, 1.0);

    const int nc = depositWorkspace.allocatedCells;
    if (nc <= 0 || depositWorkspace.mass.size() != static_cast<std::size_t>(nc)) {
        throw std::runtime_error("apply_resampling_local_mass_momentum_remap: invalid deposit workspace");
    }
    if (!(d.targetCellMass > 0.0) || !std::isfinite(d.targetCellMass)) {
        d.skippedInvalidMassCells = static_cast<std::uint64_t>(nc);
        return d;
    }

    std::vector<double> scaleByCell(static_cast<std::size_t>(nc), 1.0);
    std::vector<std::uint8_t> remapCell(static_cast<std::size_t>(nc), 0u);

    constexpr double eps = 1.0e-13;
    double residual2 = 0.0;
    std::uint64_t residualCount = 0u;
    d.scaleMin = std::numeric_limits<double>::infinity();
    d.scaleMax = 0.0;

    for (int c = 0; c < nc; ++c) {
        const std::size_t kk = static_cast<std::size_t>(c);
        if (kk >= depositWorkspace.wetCell.size() || !depositWorkspace.wetCell[kk]) {
            d.skippedDryCells += 1u;
            continue;
        }
        d.cellsConsidered += 1u;
        const std::uint32_t count = depositWorkspace.count[kk];
        const double mass = depositWorkspace.mass[kk];
        const double px = depositWorkspace.px[kk];
        const double py = depositWorkspace.py[kk];
        if (count == 0u) {
            d.skippedEmptyCells += 1u;
            continue;
        }
        if (!(mass > 0.0) || !std::isfinite(mass)) {
            d.skippedInvalidMassCells += 1u;
            d.allRemappedCellsNonEmpty = false;
            continue;
        }

        const double effectiveTargetCellMass = mass + d.massCorrectionStrength * (d.targetCellMass - mass);
        const double scale = effectiveTargetCellMass / mass;
        if (!(scale > 0.0) || !std::isfinite(scale)) {
            d.skippedInvalidMassCells += 1u;
            continue;
        }
        scaleByCell[kk] = scale;
        remapCell[kk] = 1u;

        d.massBefore += mass;
        d.massAfter += effectiveTargetCellMass;
        d.massTargetSum += d.targetCellMass;
        d.momentumXBefore += px;
        d.momentumYBefore += py;
        const double targetPx = effectiveTargetCellMass * depositWorkspace.ux[kk];
        const double targetPy = effectiveTargetCellMass * depositWorkspace.uy[kk];
        d.momentumXTarget += targetPx;
        d.momentumYTarget += targetPy;
        d.momentumXAfter += scale * px;
        d.momentumYAfter += scale * py;

        const double cellMassRelResidual = std::abs((effectiveTargetCellMass - scale * mass) / d.targetCellMass);
        d.maxCellMassRelResidual = std::max(d.maxCellMassRelResidual, cellMassRelResidual);
        const double rx = scale * px - targetPx;
        const double ry = scale * py - targetPy;
        const double rnorm = std::sqrt(rx * rx + ry * ry);
        residual2 += rnorm * rnorm;
        residualCount += 1u;
        d.momentumResidualMaxAbs = std::max(d.momentumResidualMaxAbs, std::max(std::abs(rx), std::abs(ry)));

        if (std::abs(scale - 1.0) > eps) {
            d.cellsRemapped += 1u;
            if (d.firstRemappedCell == kInvalidCellIndex) {
                d.firstRemappedCell = static_cast<std::int32_t>(c);
            }
            d.lastRemappedCell = static_cast<std::int32_t>(c);
        }
        d.scaleMin = std::min(d.scaleMin, scale);
        d.scaleMax = std::max(d.scaleMax, scale);
    }

    if (depositWorkspace.remapThermalEnergyTarget.size() == static_cast<std::size_t>(nc) &&
        depositWorkspace.remapThermalCell.size() == static_cast<std::size_t>(nc)) {
        std::fill(depositWorkspace.remapThermalEnergyTarget.begin(),
                  depositWorkspace.remapThermalEnergyTarget.end(),
                  0.0);
        std::fill(depositWorkspace.remapThermalCell.begin(),
                  depositWorkspace.remapThermalCell.end(),
                  0u);
        for (int c = 0; c < nc; ++c) {
            const std::size_t kk = static_cast<std::size_t>(c);
            if (remapCell[kk]) {
                depositWorkspace.remapThermalCell[kk] = 1u;
            }
        }
        for (std::size_t i = 0; i < static_cast<std::size_t>(state.Np); ++i) {
            if (!is_fluid_particle(state, i)) {
                continue;
            }
            if (i >= depositWorkspace.cellId.size()) {
                continue;
            }
            const int c = depositWorkspace.cellId[i];
            if (c < 0 || c >= nc) {
                continue;
            }
            const std::size_t kk = static_cast<std::size_t>(c);
            if (!remapCell[kk]) {
                continue;
            }
            const double dux = state.vx[i] - depositWorkspace.ux[kk];
            const double duy = state.vy[i] - depositWorkspace.uy[kk];
            depositWorkspace.remapThermalEnergyTarget[kk] +=
                0.5 * state.mass[i] * (dux * dux + duy * duy);
        }
    }

    for (std::size_t i = 0; i < static_cast<std::size_t>(state.Np); ++i) {
        if (!is_fluid_particle(state, i)) {
            continue;
        }
        if (i >= depositWorkspace.cellId.size()) {
            continue;
        }
        const int c = depositWorkspace.cellId[i];
        if (c < 0 || c >= nc) {
            continue;
        }
        const std::size_t kk = static_cast<std::size_t>(c);
        if (!remapCell[kk]) {
            continue;
        }
        state.mass[i] *= scaleByCell[kk];
        d.particlesRemapped += 1u;
    }

    d.massDelta = d.massAfter - d.massBefore;
    d.momentumResidualRms = residualCount > 0u ? std::sqrt(residual2 / static_cast<double>(residualCount)) : 0.0;
    if (!std::isfinite(d.scaleMin)) {
        d.scaleMin = 1.0;
    }
    if (!(d.scaleMax > 0.0)) {
        d.scaleMax = 1.0;
    }
    d.applied = d.particlesRemapped > 0u;
    d.allRemappedCellsNonEmpty = d.allRemappedCellsNonEmpty && d.skippedInvalidMassCells == 0u;
    return d;
}

void attach_resampling_remap_apply_diagnostics(
    WeightedResamplingDiagnostics& diagnostics,
    const ResamplingRemapApplyDiagnostics& remapDiagnostics) {
    diagnostics.remapApplyAttempted = remapDiagnostics.attempted;
    diagnostics.remapApplied = remapDiagnostics.applied;
    diagnostics.remapCellsConsidered = remapDiagnostics.cellsConsidered;
    diagnostics.remapCellsRemapped = remapDiagnostics.cellsRemapped;
    diagnostics.remapParticlesRemapped = remapDiagnostics.particlesRemapped;
    diagnostics.remapSkippedDryCells = remapDiagnostics.skippedDryCells;
    diagnostics.remapSkippedEmptyCells = remapDiagnostics.skippedEmptyCells;
    diagnostics.remapSkippedInvalidMassCells = remapDiagnostics.skippedInvalidMassCells;
    diagnostics.remapTargetCellMass = remapDiagnostics.targetCellMass;
    diagnostics.remapMassCorrectionStrength = remapDiagnostics.massCorrectionStrength;
    diagnostics.remapMassBefore = remapDiagnostics.massBefore;
    diagnostics.remapMassAfter = remapDiagnostics.massAfter;
    diagnostics.remapMassTargetSum = remapDiagnostics.massTargetSum;
    diagnostics.remapMassDelta = remapDiagnostics.massDelta;
    diagnostics.remapMomentumXBefore = remapDiagnostics.momentumXBefore;
    diagnostics.remapMomentumYBefore = remapDiagnostics.momentumYBefore;
    diagnostics.remapMomentumXAfter = remapDiagnostics.momentumXAfter;
    diagnostics.remapMomentumYAfter = remapDiagnostics.momentumYAfter;
    diagnostics.remapMomentumXTarget = remapDiagnostics.momentumXTarget;
    diagnostics.remapMomentumYTarget = remapDiagnostics.momentumYTarget;
    diagnostics.remapMomentumResidualRms = remapDiagnostics.momentumResidualRms;
    diagnostics.remapMomentumResidualMaxAbs = remapDiagnostics.momentumResidualMaxAbs;
    diagnostics.remapMaxCellMassRelResidual = remapDiagnostics.maxCellMassRelResidual;
    diagnostics.remapScaleMin = remapDiagnostics.scaleMin;
    diagnostics.remapScaleMax = remapDiagnostics.scaleMax;
    diagnostics.firstRemappedCell = remapDiagnostics.firstRemappedCell;
    diagnostics.lastRemappedCell = remapDiagnostics.lastRemappedCell;
    diagnostics.remapAllRemappedCellsNonEmpty = remapDiagnostics.allRemappedCellsNonEmpty;
}


ResamplingThermalRenormalizationDiagnostics apply_resampling_local_thermal_renormalization(
    ParticleState& state,
    const WeightedRealFluidDepositWorkspace& depositWorkspace,
    const ResamplingRemapApplyDiagnostics& remapDiagnostics) {
    validate_particle_state(state, "apply_resampling_local_thermal_renormalization");
    ensure_particle_roles(state, ParticleRole::Fluid);

    ResamplingThermalRenormalizationDiagnostics d{};
    d.attempted = true;

    const int nc = depositWorkspace.allocatedCells;
    if (nc <= 0 || depositWorkspace.mass.size() != static_cast<std::size_t>(nc) ||
        depositWorkspace.remapThermalEnergyTarget.size() != static_cast<std::size_t>(nc) ||
        depositWorkspace.remapThermalCell.size() != static_cast<std::size_t>(nc)) {
        throw std::runtime_error("apply_resampling_local_thermal_renormalization: invalid deposit workspace");
    }
    if (!remapDiagnostics.applied) {
        return d;
    }

    std::vector<double> currentEnergy(static_cast<std::size_t>(nc), 0.0);
    std::vector<double> massByCell(static_cast<std::size_t>(nc), 0.0);
    std::vector<double> pxBefore(static_cast<std::size_t>(nc), 0.0);
    std::vector<double> pyBefore(static_cast<std::size_t>(nc), 0.0);
    std::vector<double> pxAfter(static_cast<std::size_t>(nc), 0.0);
    std::vector<double> pyAfter(static_cast<std::size_t>(nc), 0.0);
    std::vector<double> scaleByCell(static_cast<std::size_t>(nc), 1.0);
    std::vector<std::uint8_t> renormCell(static_cast<std::size_t>(nc), 0u);

    const std::size_t n = static_cast<std::size_t>(state.Np);
    const int nt = std::max(1, thread_count());
    const bool parallelParticles = n > 10000u;

    if (parallelParticles) {
        const std::size_t localSize = static_cast<std::size_t>(nt * nc);
        std::vector<double> localCurrentEnergy(localSize, 0.0);
        std::vector<double> localMassByCell(localSize, 0.0);
        std::vector<double> localPxBefore(localSize, 0.0);
        std::vector<double> localPyBefore(localSize, 0.0);

#pragma omp parallel
        {
            const int tid = thread_id();
            const std::size_t offset = static_cast<std::size_t>(tid * nc);
#pragma omp for
            for (std::int64_t ii = 0; ii < static_cast<std::int64_t>(n); ++ii) {
                const std::size_t i = static_cast<std::size_t>(ii);
                if (!is_fluid_particle(state, i)) {
                    continue;
                }
                if (i >= depositWorkspace.cellId.size()) {
                    continue;
                }
                const int c = depositWorkspace.cellId[i];
                if (c < 0 || c >= nc) {
                    continue;
                }
                const std::size_t kk = static_cast<std::size_t>(c);
                const std::size_t lk = offset + kk;
                const double mp = state.mass[i];
                const double vx = state.vx[i];
                const double vy = state.vy[i];
                const double dux = vx - depositWorkspace.ux[kk];
                const double duy = vy - depositWorkspace.uy[kk];
                localCurrentEnergy[lk] += 0.5 * mp * (dux * dux + duy * duy);
                localMassByCell[lk] += mp;
                localPxBefore[lk] += mp * vx;
                localPyBefore[lk] += mp * vy;
            }
        }

#pragma omp parallel for if(nc > 256)
        for (int c = 0; c < nc; ++c) {
            const std::size_t kk = static_cast<std::size_t>(c);
            double e = 0.0;
            double m = 0.0;
            double px = 0.0;
            double py = 0.0;
            for (int t = 0; t < nt; ++t) {
                const std::size_t lk = static_cast<std::size_t>(t * nc + c);
                e += localCurrentEnergy[lk];
                m += localMassByCell[lk];
                px += localPxBefore[lk];
                py += localPyBefore[lk];
            }
            currentEnergy[kk] = e;
            massByCell[kk] = m;
            pxBefore[kk] = px;
            pyBefore[kk] = py;
        }
    } else {
        for (std::size_t i = 0; i < n; ++i) {
            if (!is_fluid_particle(state, i)) {
                continue;
            }
            if (i >= depositWorkspace.cellId.size()) {
                continue;
            }
            const int c = depositWorkspace.cellId[i];
            if (c < 0 || c >= nc) {
                continue;
            }
            const std::size_t kk = static_cast<std::size_t>(c);
            const double mp = state.mass[i];
            const double vx = state.vx[i];
            const double vy = state.vy[i];
            const double dux = vx - depositWorkspace.ux[kk];
            const double duy = vy - depositWorkspace.uy[kk];
            currentEnergy[kk] += 0.5 * mp * (dux * dux + duy * duy);
            massByCell[kk] += mp;
            pxBefore[kk] += mp * vx;
            pyBefore[kk] += mp * vy;
        }
    }

    constexpr double eps = 1.0e-30;
    double residual2 = 0.0;
    double momentumResidual2 = 0.0;
    std::uint64_t residualCount = 0u;
    d.velocityScaleMin = std::numeric_limits<double>::infinity();
    d.velocityScaleMax = 0.0;

    for (int c = 0; c < nc; ++c) {
        const std::size_t kk = static_cast<std::size_t>(c);
        if (!depositWorkspace.remapThermalCell[kk]) {
            continue;
        }
        if (!depositWorkspace.wetCell[kk]) {
            d.skippedDryCells += 1u;
            continue;
        }
        if (depositWorkspace.count[kk] == 0u || !(massByCell[kk] > 0.0)) {
            d.skippedEmptyCells += 1u;
            continue;
        }
        d.cellsConsidered += 1u;
        const double targetE = depositWorkspace.remapThermalEnergyTarget[kk];
        const double beforeE = currentEnergy[kk];
        if (!(targetE >= 0.0) || !std::isfinite(targetE) || !(beforeE >= 0.0) || !std::isfinite(beforeE)) {
            d.skippedInvalidEnergyCells += 1u;
            d.allRenormalizedCellsNonEmpty = false;
            continue;
        }

        double scale = 1.0;
        if (beforeE > eps) {
            scale = std::sqrt(std::max(0.0, targetE) / beforeE);
        } else if (targetE > eps) {
            d.skippedInvalidEnergyCells += 1u;
            continue;
        } else {
            scale = 1.0;
        }
        if (!(scale >= 0.0) || !std::isfinite(scale)) {
            d.skippedInvalidEnergyCells += 1u;
            continue;
        }

        scaleByCell[kk] = scale;
        renormCell[kk] = 1u;
        d.cellsRenormalized += (std::abs(scale - 1.0) > 1.0e-13) ? 1u : 0u;
        if (std::abs(scale - 1.0) > 1.0e-13) {
            if (d.firstRenormalizedCell == kInvalidCellIndex) {
                d.firstRenormalizedCell = static_cast<std::int32_t>(c);
            }
            d.lastRenormalizedCell = static_cast<std::int32_t>(c);
        }
        d.targetThermalEnergy += targetE;
        d.thermalEnergyBefore += beforeE;
        const double afterE = scale * scale * beforeE;
        d.thermalEnergyAfter += afterE;
        const double er = afterE - targetE;
        residual2 += er * er;
        residualCount += 1u;
        d.thermalEnergyResidualMaxAbs = std::max(d.thermalEnergyResidualMaxAbs, std::abs(er));
        d.velocityScaleMin = std::min(d.velocityScaleMin, scale);
        d.velocityScaleMax = std::max(d.velocityScaleMax, scale);
    }

    if (parallelParticles) {
        const std::size_t localSize = static_cast<std::size_t>(nt * nc);
        std::vector<double> localPxAfter(localSize, 0.0);
        std::vector<double> localPyAfter(localSize, 0.0);
        std::uint64_t particlesRenormalized = 0u;

#pragma omp parallel reduction(+:particlesRenormalized)
        {
            const int tid = thread_id();
            const std::size_t offset = static_cast<std::size_t>(tid * nc);
#pragma omp for
            for (std::int64_t ii = 0; ii < static_cast<std::int64_t>(n); ++ii) {
                const std::size_t i = static_cast<std::size_t>(ii);
                if (!is_fluid_particle(state, i)) {
                    continue;
                }
                if (i >= depositWorkspace.cellId.size()) {
                    continue;
                }
                const int c = depositWorkspace.cellId[i];
                if (c < 0 || c >= nc) {
                    continue;
                }
                const std::size_t kk = static_cast<std::size_t>(c);
                if (!renormCell[kk]) {
                    continue;
                }
                const double ux = depositWorkspace.ux[kk];
                const double uy = depositWorkspace.uy[kk];
                const double scale = scaleByCell[kk];
                state.vx[i] = ux + scale * (state.vx[i] - ux);
                state.vy[i] = uy + scale * (state.vy[i] - uy);
                const std::size_t lk = offset + kk;
                localPxAfter[lk] += state.mass[i] * state.vx[i];
                localPyAfter[lk] += state.mass[i] * state.vy[i];
                particlesRenormalized += 1u;
            }
        }

#pragma omp parallel for if(nc > 256)
        for (int c = 0; c < nc; ++c) {
            const std::size_t kk = static_cast<std::size_t>(c);
            double px = 0.0;
            double py = 0.0;
            for (int t = 0; t < nt; ++t) {
                const std::size_t lk = static_cast<std::size_t>(t * nc + c);
                px += localPxAfter[lk];
                py += localPyAfter[lk];
            }
            pxAfter[kk] = px;
            pyAfter[kk] = py;
        }
        d.particlesRenormalized = particlesRenormalized;
    } else {
        for (std::size_t i = 0; i < n; ++i) {
            if (!is_fluid_particle(state, i)) {
                continue;
            }
            if (i >= depositWorkspace.cellId.size()) {
                continue;
            }
            const int c = depositWorkspace.cellId[i];
            if (c < 0 || c >= nc) {
                continue;
            }
            const std::size_t kk = static_cast<std::size_t>(c);
            if (!renormCell[kk]) {
                continue;
            }
            const double ux = depositWorkspace.ux[kk];
            const double uy = depositWorkspace.uy[kk];
            const double scale = scaleByCell[kk];
            state.vx[i] = ux + scale * (state.vx[i] - ux);
            state.vy[i] = uy + scale * (state.vy[i] - uy);
            pxAfter[kk] += state.mass[i] * state.vx[i];
            pyAfter[kk] += state.mass[i] * state.vy[i];
            d.particlesRenormalized += 1u;
        }
    }

    // The previous diagnostic path scanned all particles once for every
    // renormalized cell, which made thermal renormalization O(Ncells*Np) in
    // fully wet periodic/channel cases.  The post-renormalization momentum is
    // now accumulated in the particle loop above, so this residual pass is
    // only O(Ncells).
    for (int c = 0; c < nc; ++c) {
        const std::size_t kk = static_cast<std::size_t>(c);
        if (!renormCell[kk]) {
            continue;
        }
        const double rx = pxAfter[kk] - pxBefore[kk];
        const double ry = pyAfter[kk] - pyBefore[kk];
        momentumResidual2 += rx * rx + ry * ry;
        d.momentumResidualMaxAbs = std::max(d.momentumResidualMaxAbs, std::max(std::abs(rx), std::abs(ry)));
    }

    d.thermalEnergyResidualRms = residualCount > 0u
        ? std::sqrt(residual2 / static_cast<double>(residualCount)) : 0.0;
    d.momentumResidualRms = residualCount > 0u
        ? std::sqrt(momentumResidual2 / static_cast<double>(residualCount)) : 0.0;
    if (!std::isfinite(d.velocityScaleMin)) {
        d.velocityScaleMin = 1.0;
    }
    if (!(d.velocityScaleMax > 0.0)) {
        d.velocityScaleMax = 1.0;
    }
    d.applied = d.particlesRenormalized > 0u;
    d.allRenormalizedCellsNonEmpty = d.allRenormalizedCellsNonEmpty && d.skippedInvalidEnergyCells == 0u;
    return d;
}

void attach_resampling_thermal_renormalization_diagnostics(
    WeightedResamplingDiagnostics& diagnostics,
    const ResamplingThermalRenormalizationDiagnostics& thermalDiagnostics) {
    diagnostics.thermalRenormAttempted = thermalDiagnostics.attempted;
    diagnostics.thermalRenormApplied = thermalDiagnostics.applied;
    diagnostics.thermalRenormCellsConsidered = thermalDiagnostics.cellsConsidered;
    diagnostics.thermalRenormCellsRenormalized = thermalDiagnostics.cellsRenormalized;
    diagnostics.thermalRenormParticlesRenormalized = thermalDiagnostics.particlesRenormalized;
    diagnostics.thermalRenormSkippedDryCells = thermalDiagnostics.skippedDryCells;
    diagnostics.thermalRenormSkippedEmptyCells = thermalDiagnostics.skippedEmptyCells;
    diagnostics.thermalRenormSkippedInvalidEnergyCells = thermalDiagnostics.skippedInvalidEnergyCells;
    diagnostics.thermalRenormTargetEnergy = thermalDiagnostics.targetThermalEnergy;
    diagnostics.thermalRenormEnergyBefore = thermalDiagnostics.thermalEnergyBefore;
    diagnostics.thermalRenormEnergyAfter = thermalDiagnostics.thermalEnergyAfter;
    diagnostics.thermalRenormEnergyResidualRms = thermalDiagnostics.thermalEnergyResidualRms;
    diagnostics.thermalRenormEnergyResidualMaxAbs = thermalDiagnostics.thermalEnergyResidualMaxAbs;
    diagnostics.thermalRenormVelocityScaleMin = thermalDiagnostics.velocityScaleMin;
    diagnostics.thermalRenormVelocityScaleMax = thermalDiagnostics.velocityScaleMax;
    diagnostics.thermalRenormMomentumResidualRms = thermalDiagnostics.momentumResidualRms;
    diagnostics.thermalRenormMomentumResidualMaxAbs = thermalDiagnostics.momentumResidualMaxAbs;
    diagnostics.firstThermalRenormCell = thermalDiagnostics.firstRenormalizedCell;
    diagnostics.lastThermalRenormCell = thermalDiagnostics.lastRenormalizedCell;
    diagnostics.thermalRenormAllCellsNonEmpty = thermalDiagnostics.allRenormalizedCellsNonEmpty;
}



ResamplingMassGuardDiagnostics apply_resampling_particle_mass_guards(
    ParticleState& state,
    const SimulationParams& params,
    const WeightedRealFluidDepositWorkspace& depositWorkspace,
    const WeightedResamplingDiagnostics& depositDiagnostics,
    double targetCellMassOverride) {
    validate_particle_state(state, "apply_resampling_particle_mass_guards");
    ensure_particle_roles(state, ParticleRole::Fluid);

    ResamplingMassGuardDiagnostics d{};
    d.attempted = true;
    int nc = 0;
    {
        MPCD_MASS_GUARD_PROFILE(d.profile, InitValidate);
        d.massMinBound = params.resamplingParticleMassMin;
        d.massMaxBound = params.resamplingParticleMassMax;
        d.targetCellMass = (targetCellMassOverride > 0.0 && std::isfinite(targetCellMassOverride))
            ? targetCellMassOverride
            : depositDiagnostics.targetCellMass;

        nc = depositWorkspace.allocatedCells;
        if (nc <= 0 || depositWorkspace.wetCell.size() != static_cast<std::size_t>(nc) ||
            depositWorkspace.cellId.size() < static_cast<std::size_t>(state.Np)) {
            throw std::runtime_error("apply_resampling_particle_mass_guards: invalid deposit workspace");
        }
        if (!(d.massMinBound >= 0.0) || !(d.massMaxBound > d.massMinBound) ||
            !(d.targetCellMass > 0.0) || !std::isfinite(d.targetCellMass)) {
            d.skippedInvalidMassCells = static_cast<std::uint64_t>(nc);
            d.allGuardedCellsFeasible = false;
            return d;
        }
    }

    std::vector<std::vector<std::size_t>> particlesByCell(static_cast<std::size_t>(nc));
    {
        MPCD_MASS_GUARD_PROFILE(d.profile, BuildParticlesByCell);
    for (std::size_t i = 0; i < static_cast<std::size_t>(state.Np); ++i) {
        if (!is_fluid_particle(state, i)) {
            continue;
        }
        const int c = depositWorkspace.cellId[i];
        if (c < 0 || c >= nc) {
            continue;
        }
        particlesByCell[static_cast<std::size_t>(c)].push_back(i);
    }
    }

    constexpr double eps = 1.0e-12;
    constexpr double energyEps = 1.0e-30;
    double massResidual2 = 0.0;
    double thermalResidual2 = 0.0;
    double momentumResidual2 = 0.0;
    std::uint64_t residualCount = 0u;
    d.particleMassMinBefore = std::numeric_limits<double>::infinity();
    d.particleMassMaxBefore = 0.0;
    d.particleMassMinAfter = std::numeric_limits<double>::infinity();
    d.particleMassMaxAfter = 0.0;
    d.velocityScaleMin = std::numeric_limits<double>::infinity();
    d.velocityScaleMax = 0.0;

    {
        MPCD_MASS_GUARD_PROFILE(d.profile, CellLoop);
    for (int c = 0; c < nc; ++c) {
        const std::size_t kk = static_cast<std::size_t>(c);
        if (!depositWorkspace.wetCell[kk]) {
            d.skippedDryCells += 1u;
            continue;
        }
        auto& ids = particlesByCell[kk];
        if (ids.empty()) {
            d.skippedEmptyCells += 1u;
            continue;
        }
        d.cellsConsidered += 1u;
        d.particlesConsidered += static_cast<std::uint64_t>(ids.size());

        const double feasibleMin = static_cast<double>(ids.size()) * d.massMinBound;
        const double feasibleMax = static_cast<double>(ids.size()) * d.massMaxBound;
        if (d.targetCellMass < feasibleMin - eps || d.targetCellMass > feasibleMax + eps) {
            d.skippedInfeasibleCells += 1u;
            d.allGuardedCellsFeasible = false;
            continue;
        }

        double massBefore = 0.0;
        double pxBefore = 0.0;
        double pyBefore = 0.0;
        double minOld = std::numeric_limits<double>::infinity();
        double maxOld = -std::numeric_limits<double>::infinity();
        bool invalid = false;
        std::vector<double> oldMass(ids.size(), 0.0);
        for (std::size_t j = 0; j < ids.size(); ++j) {
            const std::size_t i = ids[j];
            const double m = state.mass[i];
            if (!(m > 0.0) || !std::isfinite(m)) {
                invalid = true;
                break;
            }
            oldMass[j] = m;
            massBefore += m;
            pxBefore += m * state.vx[i];
            pyBefore += m * state.vy[i];
            minOld = std::min(minOld, m);
            maxOld = std::max(maxOld, m);
            d.particleMassMinBefore = std::min(d.particleMassMinBefore, m);
            d.particleMassMaxBefore = std::max(d.particleMassMaxBefore, m);
            d.particlesBelowMinBefore += (m < d.massMinBound - eps) ? 1u : 0u;
            d.particlesAboveMaxBefore += (m > d.massMaxBound + eps) ? 1u : 0u;
        }
        if (invalid || !(massBefore > 0.0)) {
            d.skippedInvalidMassCells += 1u;
            d.allGuardedCellsFeasible = false;
            continue;
        }

        const double uxTarget = pxBefore / massBefore;
        const double uyTarget = pyBefore / massBefore;
        double thermalTarget = 0.0;
        for (const std::size_t i : ids) {
            const double dux = state.vx[i] - uxTarget;
            const double duy = state.vy[i] - uyTarget;
            thermalTarget += 0.5 * state.mass[i] * (dux * dux + duy * duy);
        }

        // Project m_old onto the box [m_min,m_max] with the affine constraint
        // sum(m_new)=M_target.  The additive Lagrange multiplier gives the
        // closest bounded vector to the current masses in Euclidean norm.
        double lo = d.massMinBound - maxOld - std::abs(d.targetCellMass) - 1.0;
        double hi = d.massMaxBound - minOld + std::abs(d.targetCellMass) + 1.0;
        for (int it = 0; it < 96; ++it) {
            const double mid = 0.5 * (lo + hi);
            double sum = 0.0;
            for (double m : oldMass) {
                sum += std::min(d.massMaxBound, std::max(d.massMinBound, m + mid));
            }
            if (sum < d.targetCellMass) {
                lo = mid;
            } else {
                hi = mid;
            }
        }
        const double lambda = 0.5 * (lo + hi);
        std::vector<double> newMass(ids.size(), 0.0);
        double massAfter = 0.0;
        double pxMassOnly = 0.0;
        double pyMassOnly = 0.0;
        bool changed = false;
        for (std::size_t j = 0; j < ids.size(); ++j) {
            const std::size_t i = ids[j];
            const double m = std::min(d.massMaxBound, std::max(d.massMinBound, oldMass[j] + lambda));
            newMass[j] = m;
            massAfter += m;
            pxMassOnly += m * state.vx[i];
            pyMassOnly += m * state.vy[i];
            changed = changed || (std::abs(m - oldMass[j]) > eps * std::max(1.0, std::abs(oldMass[j])));
        }
        if (!(massAfter > 0.0) || !std::isfinite(massAfter)) {
            d.skippedInvalidMassCells += 1u;
            d.allGuardedCellsFeasible = false;
            continue;
        }
        const double uxCurrent = pxMassOnly / massAfter;
        const double uyCurrent = pyMassOnly / massAfter;
        double thermalBeforeVelocityRenorm = 0.0;
        for (std::size_t j = 0; j < ids.size(); ++j) {
            const std::size_t i = ids[j];
            const double dux = state.vx[i] - uxCurrent;
            const double duy = state.vy[i] - uyCurrent;
            thermalBeforeVelocityRenorm += 0.5 * newMass[j] * (dux * dux + duy * duy);
        }

        double vscale = 1.0;
        if (thermalBeforeVelocityRenorm > energyEps) {
            vscale = std::sqrt(std::max(0.0, thermalTarget) / thermalBeforeVelocityRenorm);
        } else if (thermalTarget > energyEps) {
            d.skippedInvalidMassCells += 1u;
            d.allGuardedCellsFeasible = false;
            continue;
        }
        if (!(vscale >= 0.0) || !std::isfinite(vscale)) {
            d.skippedInvalidMassCells += 1u;
            d.allGuardedCellsFeasible = false;
            continue;
        }

        for (std::size_t j = 0; j < ids.size(); ++j) {
            const std::size_t i = ids[j];
            state.mass[i] = newMass[j];
            state.vx[i] = uxTarget + vscale * (state.vx[i] - uxCurrent);
            state.vy[i] = uyTarget + vscale * (state.vy[i] - uyCurrent);
            d.particlesAdjusted += (std::abs(newMass[j] - oldMass[j]) > eps * std::max(1.0, std::abs(oldMass[j]))) ? 1u : 0u;
            d.particleMassMinAfter = std::min(d.particleMassMinAfter, newMass[j]);
            d.particleMassMaxAfter = std::max(d.particleMassMaxAfter, newMass[j]);
            d.particlesBelowMinAfter += (newMass[j] < d.massMinBound - 1.0e-10) ? 1u : 0u;
            d.particlesAboveMaxAfter += (newMass[j] > d.massMaxBound + 1.0e-10) ? 1u : 0u;
            d.particlesAtMinAfter += (std::abs(newMass[j] - d.massMinBound) <= 1.0e-10) ? 1u : 0u;
            d.particlesAtMaxAfter += (std::abs(newMass[j] - d.massMaxBound) <= 1.0e-10) ? 1u : 0u;
        }

        double pxAfter = 0.0;
        double pyAfter = 0.0;
        double thermalAfter = 0.0;
        for (const std::size_t i : ids) {
            pxAfter += state.mass[i] * state.vx[i];
            pyAfter += state.mass[i] * state.vy[i];
            const double dux = state.vx[i] - uxTarget;
            const double duy = state.vy[i] - uyTarget;
            thermalAfter += 0.5 * state.mass[i] * (dux * dux + duy * duy);
        }

        d.massBefore += massBefore;
        d.massAfter += massAfter;
        d.massTargetSum += d.targetCellMass;
        d.thermalEnergyTarget += thermalTarget;
        d.thermalEnergyBefore += thermalBeforeVelocityRenorm;
        d.thermalEnergyAfter += thermalAfter;
        d.velocityScaleMin = std::min(d.velocityScaleMin, vscale);
        d.velocityScaleMax = std::max(d.velocityScaleMax, vscale);
        const double mr = massAfter - d.targetCellMass;
        const double er = thermalAfter - thermalTarget;
        const double rx = pxAfter - d.targetCellMass * uxTarget;
        const double ry = pyAfter - d.targetCellMass * uyTarget;
        massResidual2 += mr * mr;
        thermalResidual2 += er * er;
        momentumResidual2 += rx * rx + ry * ry;
        residualCount += 1u;
        d.massResidualMaxAbs = std::max(d.massResidualMaxAbs, std::abs(mr));
        d.thermalEnergyResidualMaxAbs = std::max(d.thermalEnergyResidualMaxAbs, std::abs(er));
        d.momentumResidualMaxAbs = std::max(d.momentumResidualMaxAbs, std::max(std::abs(rx), std::abs(ry)));

        if (changed || std::abs(vscale - 1.0) > eps) {
            d.cellsGuarded += 1u;
            if (d.firstGuardedCell == kInvalidCellIndex) {
                d.firstGuardedCell = static_cast<std::int32_t>(c);
            }
            d.lastGuardedCell = static_cast<std::int32_t>(c);
        }
    }

    }

    {
        MPCD_MASS_GUARD_PROFILE(d.profile, Finalize);
    if (!std::isfinite(d.particleMassMinBefore)) {
        d.particleMassMinBefore = 0.0;
    }
    if (!std::isfinite(d.particleMassMinAfter)) {
        d.particleMassMinAfter = 0.0;
    }
    if (!std::isfinite(d.velocityScaleMin)) {
        d.velocityScaleMin = 1.0;
    }
    if (!(d.velocityScaleMax > 0.0)) {
        d.velocityScaleMax = 1.0;
    }
    if (residualCount > 0u) {
        const double inv = 1.0 / static_cast<double>(residualCount);
        d.massResidualRms = std::sqrt(massResidual2 * inv);
        d.thermalEnergyResidualRms = std::sqrt(thermalResidual2 * inv);
        d.momentumResidualRms = std::sqrt(momentumResidual2 * inv);
    }
    d.applied = d.cellsGuarded > 0u || d.particlesAdjusted > 0u;
    }
    return d;
}

void attach_resampling_mass_guard_diagnostics(
    WeightedResamplingDiagnostics& diagnostics,
    const ResamplingMassGuardDiagnostics& massGuardDiagnostics) {
    diagnostics.massGuardAttempted = massGuardDiagnostics.attempted;
    diagnostics.massGuardApplied = massGuardDiagnostics.applied;
    diagnostics.massGuardCellsConsidered = massGuardDiagnostics.cellsConsidered;
    diagnostics.massGuardCellsGuarded = massGuardDiagnostics.cellsGuarded;
    diagnostics.massGuardParticlesConsidered = massGuardDiagnostics.particlesConsidered;
    diagnostics.massGuardParticlesAdjusted = massGuardDiagnostics.particlesAdjusted;
    diagnostics.massGuardSkippedDryCells = massGuardDiagnostics.skippedDryCells;
    diagnostics.massGuardSkippedEmptyCells = massGuardDiagnostics.skippedEmptyCells;
    diagnostics.massGuardSkippedInfeasibleCells = massGuardDiagnostics.skippedInfeasibleCells;
    diagnostics.massGuardSkippedInvalidMassCells = massGuardDiagnostics.skippedInvalidMassCells;
    diagnostics.massGuardMinBound = massGuardDiagnostics.massMinBound;
    diagnostics.massGuardMaxBound = massGuardDiagnostics.massMaxBound;
    diagnostics.massGuardTargetCellMass = massGuardDiagnostics.targetCellMass;
    diagnostics.massGuardMassBefore = massGuardDiagnostics.massBefore;
    diagnostics.massGuardMassAfter = massGuardDiagnostics.massAfter;
    diagnostics.massGuardMassTargetSum = massGuardDiagnostics.massTargetSum;
    diagnostics.massGuardMassResidualRms = massGuardDiagnostics.massResidualRms;
    diagnostics.massGuardMassResidualMaxAbs = massGuardDiagnostics.massResidualMaxAbs;
    diagnostics.massGuardParticleMassMinBefore = massGuardDiagnostics.particleMassMinBefore;
    diagnostics.massGuardParticleMassMaxBefore = massGuardDiagnostics.particleMassMaxBefore;
    diagnostics.massGuardParticleMassMinAfter = massGuardDiagnostics.particleMassMinAfter;
    diagnostics.massGuardParticleMassMaxAfter = massGuardDiagnostics.particleMassMaxAfter;
    diagnostics.massGuardParticlesBelowMinBefore = massGuardDiagnostics.particlesBelowMinBefore;
    diagnostics.massGuardParticlesAboveMaxBefore = massGuardDiagnostics.particlesAboveMaxBefore;
    diagnostics.massGuardParticlesBelowMinAfter = massGuardDiagnostics.particlesBelowMinAfter;
    diagnostics.massGuardParticlesAboveMaxAfter = massGuardDiagnostics.particlesAboveMaxAfter;
    diagnostics.massGuardParticlesAtMinAfter = massGuardDiagnostics.particlesAtMinAfter;
    diagnostics.massGuardParticlesAtMaxAfter = massGuardDiagnostics.particlesAtMaxAfter;
    diagnostics.massGuardThermalEnergyTarget = massGuardDiagnostics.thermalEnergyTarget;
    diagnostics.massGuardThermalEnergyBefore = massGuardDiagnostics.thermalEnergyBefore;
    diagnostics.massGuardThermalEnergyAfter = massGuardDiagnostics.thermalEnergyAfter;
    diagnostics.massGuardThermalEnergyResidualRms = massGuardDiagnostics.thermalEnergyResidualRms;
    diagnostics.massGuardThermalEnergyResidualMaxAbs = massGuardDiagnostics.thermalEnergyResidualMaxAbs;
    diagnostics.massGuardVelocityScaleMin = massGuardDiagnostics.velocityScaleMin;
    diagnostics.massGuardVelocityScaleMax = massGuardDiagnostics.velocityScaleMax;
    diagnostics.massGuardMomentumResidualRms = massGuardDiagnostics.momentumResidualRms;
    diagnostics.massGuardMomentumResidualMaxAbs = massGuardDiagnostics.momentumResidualMaxAbs;
    diagnostics.firstMassGuardedCell = massGuardDiagnostics.firstGuardedCell;
    diagnostics.lastMassGuardedCell = massGuardDiagnostics.lastGuardedCell;
    diagnostics.massGuardAllCellsFeasible = massGuardDiagnostics.allGuardedCellsFeasible;
    diagnostics.massGuardProfileSeconds = massGuardDiagnostics.profile.seconds;
}

void resize_weighted_real_fluid_deposit(WeightedRealFluidDepositWorkspace& ws,
                                        std::uint64_t numParticles,
                                        int numCells,
                                        int numThreads) {
    if (numCells <= 0) {
        throw std::runtime_error("resize_weighted_real_fluid_deposit: invalid number of cells");
    }
    if (numThreads <= 0) {
        numThreads = 1;
    }

    const bool sameSize = ws.allocatedParticles == numParticles &&
                          ws.allocatedCells == numCells &&
                          ws.allocatedThreads == numThreads;
    if (!sameSize) {
        ws.allocatedParticles = numParticles;
        ws.allocatedCells = numCells;
        ws.allocatedThreads = numThreads;

        ws.cellId.assign(static_cast<std::size_t>(numParticles), -1);
        ws.count.assign(static_cast<std::size_t>(numCells), 0u);
        ws.mass.assign(static_cast<std::size_t>(numCells), 0.0);
        ws.px.assign(static_cast<std::size_t>(numCells), 0.0);
        ws.py.assign(static_cast<std::size_t>(numCells), 0.0);
        ws.ux.assign(static_cast<std::size_t>(numCells), 0.0);
        ws.uy.assign(static_cast<std::size_t>(numCells), 0.0);

        const std::size_t localSize = static_cast<std::size_t>(numThreads * numCells);
        ws.localCount.assign(localSize, 0u);
        ws.localMass.assign(localSize, 0.0);
        ws.localPx.assign(localSize, 0.0);
        ws.localPy.assign(localSize, 0.0);

        ws.activeCell.assign(static_cast<std::size_t>(numCells), 0u);
        ws.wetCell.assign(static_cast<std::size_t>(numCells), 0u);
        ws.dryCell.assign(static_cast<std::size_t>(numCells), 0u);
        ws.poorCell.assign(static_cast<std::size_t>(numCells), 0u);
        ws.richCell.assign(static_cast<std::size_t>(numCells), 0u);
        ws.targetBandCell.assign(static_cast<std::size_t>(numCells), 0u);
        ws.receiverPoorCells.reserve(static_cast<std::size_t>(numCells));
        ws.donorRichCells.reserve(static_cast<std::size_t>(numCells));
        ws.emptyWetReceiverCells.reserve(static_cast<std::size_t>(numCells));
        ws.transferPlan.reserve(static_cast<std::size_t>(numCells));
        ws.selectedDonorParticles.reserve(static_cast<std::size_t>(numParticles));
        ws.passiveExtractionOperations.reserve(static_cast<std::size_t>(numParticles));
        ws.donorSelectedParticleCount.assign(static_cast<std::size_t>(numCells), 0u);
        ws.donorSelectedMass.assign(static_cast<std::size_t>(numCells), 0.0);
        ws.cellParticleOffsets.reserve(static_cast<std::size_t>(numCells) + 1u);
        ws.cellParticleCursor.reserve(static_cast<std::size_t>(numCells));
        ws.cellParticleIndices.reserve(static_cast<std::size_t>(numParticles));
        ws.remapThermalEnergyTarget.assign(static_cast<std::size_t>(numCells), 0.0);
        ws.remapThermalCell.assign(static_cast<std::size_t>(numCells), 0u);
    }
}

WeightedResamplingDiagnostics deposit_weighted_real_fluid(const ParticleState& state,
                                                          const SimulationParams& params,
                                                          const CellGrid& grid,
                                                          const FluidDomainBounds& domain,
                                                          double time,
                                                          const GridShift& shift,
                                                          WeightedRealFluidDepositWorkspace& ws,
                                                          bool buildMutationPlan,
                                                          ResamplingDepositProfileContext profileContext,
                                                          bool reuseExistingCellIds) {
    std::array<double, ResamplingDepositProfilePhaseCount> depositProfileSeconds{};

    int nc = 0;
    std::size_t n = 0u;
    int nt = 1;
    {
        MPCD_DEPOSIT_PROFILE(depositProfileSeconds, ValidateResize);
        validate_particle_state(state, "deposit_weighted_real_fluid");

        nc = grid.numCells;
        if (nc <= 0) {
            throw std::runtime_error("deposit_weighted_real_fluid: invalid number of cells");
        }
        n = static_cast<std::size_t>(state.Np);
        nt = std::max(1, thread_count());
        resize_weighted_real_fluid_deposit(ws, state.Np, nc, nt);
    }

    const bool useExistingCellIds =
        reuseExistingCellIds && profileContext == ResamplingDepositProfileContext::PostGuard &&
        ws.cellId.size() >= n;

    {
        MPCD_DEPOSIT_PROFILE(depositProfileSeconds, ClearArrays);
    if (!useExistingCellIds) {
        std::fill(ws.cellId.begin(), ws.cellId.end(), -1);
    }
    std::fill(ws.count.begin(), ws.count.end(), 0u);
    std::fill(ws.mass.begin(), ws.mass.end(), 0.0);
    std::fill(ws.px.begin(), ws.px.end(), 0.0);
    std::fill(ws.py.begin(), ws.py.end(), 0.0);
    std::fill(ws.ux.begin(), ws.ux.end(), 0.0);
    std::fill(ws.uy.begin(), ws.uy.end(), 0.0);
    std::fill(ws.localCount.begin(), ws.localCount.end(), 0u);
    std::fill(ws.localMass.begin(), ws.localMass.end(), 0.0);
    std::fill(ws.localPx.begin(), ws.localPx.end(), 0.0);
    std::fill(ws.localPy.begin(), ws.localPy.end(), 0.0);
    std::fill(ws.activeCell.begin(), ws.activeCell.end(), 0u);
    std::fill(ws.wetCell.begin(), ws.wetCell.end(), 0u);
    std::fill(ws.dryCell.begin(), ws.dryCell.end(), 0u);
    std::fill(ws.poorCell.begin(), ws.poorCell.end(), 0u);
    std::fill(ws.richCell.begin(), ws.richCell.end(), 0u);
    std::fill(ws.targetBandCell.begin(), ws.targetBandCell.end(), 0u);
    ws.receiverPoorCells.clear();
    ws.donorRichCells.clear();
    ws.emptyWetReceiverCells.clear();
    ws.transferPlan.clear();
    ws.selectedDonorParticles.clear();
    ws.passiveExtractionOperations.clear();
    if (!buildMutationPlan) {
        ws.cellParticleOffsets.clear();
        ws.cellParticleCursor.clear();
        ws.cellParticleIndices.clear();
    }
    std::fill(ws.donorSelectedParticleCount.begin(), ws.donorSelectedParticleCount.end(), 0u);
    std::fill(ws.donorSelectedMass.begin(), ws.donorSelectedMass.end(), 0.0);
    std::fill(ws.remapThermalEnergyTarget.begin(), ws.remapThermalEnergyTarget.end(), 0.0);
    std::fill(ws.remapThermalCell.begin(), ws.remapThermalCell.end(), 0u);
    }

    ParticleRoleCounts roles{};
    {
        MPCD_DEPOSIT_PROFILE(depositProfileSeconds, RoleCounts);
        roles = count_particle_roles(state);
    }

    double particleMassSum = 0.0;
    double particleMassSum2 = 0.0;
    double particleMassMin = std::numeric_limits<double>::infinity();
    double particleMassMax = 0.0;

{
        MPCD_DEPOSIT_PROFILE(depositProfileSeconds, ParticleLoopCellAccum);
#pragma omp parallel reduction(+:particleMassSum,particleMassSum2) reduction(min:particleMassMin) reduction(max:particleMassMax)
    {
        const int tid = thread_id();
        const std::size_t offset = static_cast<std::size_t>(tid * nc);

#pragma omp for
        for (std::int64_t ii = 0; ii < static_cast<std::int64_t>(n); ++ii) {
            const std::size_t i = static_cast<std::size_t>(ii);
            if (!is_fluid_particle(state, i)) {
                continue;
            }
            const double m = state.mass[i];
            int c = -1;
            if (useExistingCellIds) {
                c = i < ws.cellId.size() ? ws.cellId[i] : -1;
                if (c < 0 || c >= nc) {
                    c = cell_index_from_position(state.x[i], state.y[i], grid, shift, params);
                    if (i < ws.cellId.size()) {
                        ws.cellId[i] = c;
                    }
                }
            } else {
                c = cell_index_from_position(state.x[i], state.y[i], grid, shift, params);
                ws.cellId[i] = c;
            }
            const std::size_t k = offset + static_cast<std::size_t>(c);
            ws.localCount[k] += 1u;
            ws.localMass[k] += m;
            ws.localPx[k] += m * state.vx[i];
            ws.localPy[k] += m * state.vy[i];
            particleMassSum += m;
            particleMassSum2 += m * m;
            particleMassMin = std::min(particleMassMin, m);
            particleMassMax = std::max(particleMassMax, m);
        }
    }
    }

    double totalMass = 0.0;
    double totalPx = 0.0;
    double totalPy = 0.0;
    double sumN = 0.0;
    double sumN2 = 0.0;
    double sumM = 0.0;
    double sumM2 = 0.0;
    double minMass = std::numeric_limits<double>::infinity();
    double maxMass = 0.0;
    std::uint32_t minN = std::numeric_limits<std::uint32_t>::max();
    std::uint32_t maxN = 0u;
    std::uint64_t nonEmpty = 0u;
    double cellUxRmsAccum = 0.0;
    double cellUyRmsAccum = 0.0;

{
        MPCD_DEPOSIT_PROFILE(depositProfileSeconds, ReduceCellsFinalize);
#pragma omp parallel for reduction(+:totalMass,totalPx,totalPy,sumN,sumN2,sumM,sumM2,nonEmpty,cellUxRmsAccum,cellUyRmsAccum) reduction(min:minMass,minN) reduction(max:maxMass,maxN) if(nc > 256)
    for (int c = 0; c < nc; ++c) {
        std::uint32_t count = 0u;
        double mass = 0.0;
        double px = 0.0;
        double py = 0.0;
        for (int t = 0; t < nt; ++t) {
            const std::size_t k = static_cast<std::size_t>(t * nc + c);
            count += ws.localCount[k];
            mass += ws.localMass[k];
            px += ws.localPx[k];
            py += ws.localPy[k];
        }

        const std::size_t kk = static_cast<std::size_t>(c);
        ws.count[kk] = count;
        ws.mass[kk] = mass;
        ws.px[kk] = px;
        ws.py[kk] = py;
        if (mass > 0.0) {
            ws.ux[kk] = px / mass;
            ws.uy[kk] = py / mass;
            nonEmpty += 1u;
            cellUxRmsAccum += ws.ux[kk] * ws.ux[kk];
            cellUyRmsAccum += ws.uy[kk] * ws.uy[kk];
        }

        totalMass += mass;
        totalPx += px;
        totalPy += py;
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
    }

    WeightedResamplingDiagnostics d{};
    d.computed = true;
    d.nFluid = roles.fluid;
    d.nLatent = roles.latent;
    d.nInactive = roles.inactive;
    d.nCells = static_cast<std::uint64_t>(nc);
    d.nNonEmptyCells = nonEmpty;
    d.nEmptyCells = static_cast<std::uint64_t>(nc) - nonEmpty;
    d.totalMass = totalMass;
    d.totalPx = totalPx;
    d.totalPy = totalPy;

    const double invNc = nc > 0 ? 1.0 / static_cast<double>(nc) : 0.0;
    d.meanN = sumN * invNc;
    d.stdN = std::sqrt(std::max(0.0, sumN2 * invNc - d.meanN * d.meanN));
    d.minN = (minN == std::numeric_limits<std::uint32_t>::max()) ? 0u : minN;
    d.maxN = maxN;
    d.meanMass = sumM * invNc;
    d.stdMass = std::sqrt(std::max(0.0, sumM2 * invNc - d.meanMass * d.meanMass));
    d.minMass = std::isfinite(minMass) ? minMass : 0.0;
    d.maxMass = maxMass;
    // Passive active/wet/dry and poor/rich classification.  The default
    // active_domain mask marks every active fluid-domain cell as wet, so a true
    // void pocket inside the fluid is classified as poor instead of being
    // silently treated as a dry/free-surface cell.  The optional occupied mode
    // is provided for future free-surface/injection tests where empty cells must
    // remain dry/latent.
    std::uint64_t nActive = 0u;
    std::uint64_t nWet = 0u;
    std::uint64_t nDry = 0u;
    std::uint64_t nOccupiedDry = 0u;
    double activeMassSum = 0.0;

{
        MPCD_DEPOSIT_PROFILE(depositProfileSeconds, ActiveWetClassification);
#pragma omp parallel for reduction(+:nActive,nWet,nDry,nOccupiedDry,activeMassSum) if(nc > 256)
    for (int c = 0; c < nc; ++c) {
        const int ix = c % grid.Nx;
        const int iy = c / grid.Nx;
        const bool active = cell_is_active_for_resampling(ix, iy, grid, params, domain, time);
        const double mc = ws.mass[static_cast<std::size_t>(c)];
        bool wet = false;
        if (active) {
            if (params.resamplingWetMaskMode == "occupied") {
                wet = mc > params.resamplingWetCellMassThreshold;
            } else {
                wet = true;
            }
        }
        const bool dry = !wet;
        ws.activeCell[static_cast<std::size_t>(c)] = active ? 1u : 0u;
        ws.wetCell[static_cast<std::size_t>(c)] = wet ? 1u : 0u;
        ws.dryCell[static_cast<std::size_t>(c)] = dry ? 1u : 0u;
        nActive += active ? 1u : 0u;
        nWet += wet ? 1u : 0u;
        nDry += dry ? 1u : 0u;
        nOccupiedDry += (dry && mc > params.resamplingWetCellMassThreshold) ? 1u : 0u;
        activeMassSum += wet ? mc : 0.0;
    }
    }

    d.targetCellMass = params.resamplingTargetCellMass > 0.0
        ? params.resamplingTargetCellMass
        : (nWet > 0u ? activeMassSum / static_cast<double>(nWet) : d.meanMass);

    d.cellClassificationComputed = true;
    d.nActiveCells = nActive;
    d.nWetCells = nWet;
    d.nDryCells = nDry;
    d.nOccupiedDryCells = nOccupiedDry;
    d.wetMassThreshold = params.resamplingWetCellMassThreshold;
    d.poorMassThreshold = d.targetCellMass * params.resamplingPoorCellMassFraction;
    d.richMassThreshold = d.targetCellMass * params.resamplingRichCellMassFraction;
    d.wetCellFraction = invNc > 0.0 ? static_cast<double>(nWet) * invNc : 0.0;
    d.dryCellFraction = invNc > 0.0 ? static_cast<double>(nDry) * invNc : 0.0;

    if (d.targetCellMass > 0.0) {
        MPCD_DEPOSIT_PROFILE(depositProfileSeconds, PoorRichClassification);
        double rel2 = 0.0;
        double relMax = 0.0;
        std::uint64_t nPoor = 0u;
        std::uint64_t nRich = 0u;
        std::uint64_t nTargetBand = 0u;
        std::uint64_t nEmptyWet = 0u;
#pragma omp parallel for reduction(+:rel2,nPoor,nRich,nTargetBand,nEmptyWet) reduction(max:relMax) if(nc > 256)
        for (int c = 0; c < nc; ++c) {
            const std::size_t kk = static_cast<std::size_t>(c);
            if (!ws.wetCell[kk]) {
                continue;
            }
            const double mc = ws.mass[kk];
            const double rel = (mc - d.targetCellMass) / d.targetCellMass;
            rel2 += rel * rel;
            relMax = std::max(relMax, std::abs(rel));

            const bool poor = mc < d.poorMassThreshold;
            const bool rich = mc > d.richMassThreshold;
            const bool emptyWet = ws.count[kk] == 0u;
            ws.poorCell[kk] = poor ? 1u : 0u;
            ws.richCell[kk] = rich ? 1u : 0u;
            ws.targetBandCell[kk] = (!poor && !rich) ? 1u : 0u;
            nPoor += poor ? 1u : 0u;
            nRich += rich ? 1u : 0u;
            nTargetBand += (!poor && !rich) ? 1u : 0u;
            nEmptyWet += emptyWet ? 1u : 0u;
        }
        const double invWet = nWet > 0u ? 1.0 / static_cast<double>(nWet) : 0.0;
        d.mRelRms = std::sqrt(rel2 * invWet);
        d.mRelMaxAbs = relMax;
        d.nPoorCells = nPoor;
        d.nRichCells = nRich;
        d.nTargetBandCells = nTargetBand;
        d.nEmptyWetCells = nEmptyWet;
        d.poorCellFraction = static_cast<double>(nPoor) * invWet;
        d.richCellFraction = static_cast<double>(nRich) * invWet;
        d.emptyWetCellFraction = static_cast<double>(nEmptyWet) * invWet;
    }

    if (d.cellClassificationComputed && d.targetCellMass > 0.0) {
        MPCD_DEPOSIT_PROFILE(depositProfileSeconds, CandidateLists);
        double receiverDeficit = 0.0;
        double donorExcess = 0.0;
        for (int c = 0; c < nc; ++c) {
            const std::size_t kk = static_cast<std::size_t>(c);
            if (!ws.wetCell[kk]) {
                continue;
            }
            if (ws.poorCell[kk]) {
                ws.receiverPoorCells.push_back(static_cast<std::int32_t>(c));
                const double deficit = d.targetCellMass - ws.mass[kk];
                if (deficit > 0.0) {
                    receiverDeficit += deficit;
                }
                if (ws.count[kk] == 0u) {
                    ws.emptyWetReceiverCells.push_back(static_cast<std::int32_t>(c));
                }
            }
            if (ws.richCell[kk]) {
                ws.donorRichCells.push_back(static_cast<std::int32_t>(c));
                const double excess = ws.mass[kk] - d.targetCellMass;
                if (excess > 0.0) {
                    donorExcess += excess;
                }
            }
        }

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
        if (d.nWetCells > 0u) {
            const double invWet = 1.0 / static_cast<double>(d.nWetCells);
            d.receiverFractionOfWetCells = static_cast<double>(d.nReceiverCells) * invWet;
            d.donorFractionOfWetCells = static_cast<double>(d.nDonorCells) * invWet;
        }

        const bool buildFullMutationPlan = buildMutationPlan && params.resamplingEnable && params.resamplingExtractionEnable;

        if (buildFullMutationPlan && !ws.receiverPoorCells.empty() && !ws.donorRichCells.empty()) {
            {
            MPCD_DEPOSIT_PROFILE(depositProfileSeconds, MutationPlanCellIndex);
            // Build a compact cell -> particle index once per planning pass.
            // The earlier implementation scanned all particles for every
            // donor/receiver transfer entry, which is catastrophic in channel
            // runs with many weak poor/rich cells.
            ws.cellParticleOffsets.assign(static_cast<std::size_t>(nc) + 1u, 0u);
            for (int c = 0; c < nc; ++c) {
                ws.cellParticleOffsets[static_cast<std::size_t>(c) + 1u] =
                    ws.cellParticleOffsets[static_cast<std::size_t>(c)] +
                    static_cast<std::uint64_t>(ws.count[static_cast<std::size_t>(c)]);
            }
            ws.cellParticleIndices.assign(static_cast<std::size_t>(ws.cellParticleOffsets.back()),
                                          kInvalidParticleIndex);
            ws.cellParticleCursor.assign(ws.cellParticleOffsets.begin(),
                                         ws.cellParticleOffsets.end() - 1);
            for (std::size_t i = 0; i < n; ++i) {
                if (!is_fluid_particle(state, i)) {
                    continue;
                }
                const int c = ws.cellId[i];
                if (c < 0 || c >= nc) {
                    continue;
                }
                const std::size_t cc = static_cast<std::size_t>(c);
                const std::size_t pos = static_cast<std::size_t>(ws.cellParticleCursor[cc]++);
                if (pos < ws.cellParticleIndices.size()) {
                    ws.cellParticleIndices[pos] = static_cast<std::uint64_t>(i);
                }
            }

            }

            {
            MPCD_DEPOSIT_PROFILE(depositProfileSeconds, TransferPlanBuild);
            std::vector<double> receiverRemaining(ws.receiverPoorCells.size(), 0.0);
            std::vector<double> donorRemaining(ws.donorRichCells.size(), 0.0);
            for (std::size_t ir = 0; ir < ws.receiverPoorCells.size(); ++ir) {
                const std::int32_t rc = ws.receiverPoorCells[ir];
                const double deficit = d.targetCellMass - ws.mass[static_cast<std::size_t>(rc)];
                receiverRemaining[ir] = deficit > 0.0 ? deficit : 0.0;
            }
            for (std::size_t id = 0; id < ws.donorRichCells.size(); ++id) {
                const std::int32_t dc = ws.donorRichCells[id];
                const double excess = ws.mass[static_cast<std::size_t>(dc)] - d.targetCellMass;
                donorRemaining[id] = excess > 0.0 ? excess : 0.0;
            }

            double plannedMass = 0.0;
            double massWeightedDistance = 0.0;
            double maxDistance = 0.0;
            std::uint64_t adjacentPairs = 0u;
            constexpr double eps = 1.0e-14;
            const double adjacentLimit = std::sqrt(2.0) + 1.0e-12;

            // Greedy nearest-donor planner without materialising and sorting the
            // complete donor x receiver Cartesian product.  It preserves the
            // locality bias but avoids the O(R*D log(R*D)) allocation/sort and
            // the additional O(R*D*(R+D)) std::find lookups of the prototype.
            for (std::size_t ir = 0; ir < ws.receiverPoorCells.size(); ++ir) {
                const std::int32_t rc = ws.receiverPoorCells[ir];
                while (receiverRemaining[ir] > eps) {
                    std::size_t bestDonor = ws.donorRichCells.size();
                    double bestDistance = std::numeric_limits<double>::infinity();
                    std::int32_t bestCell = kInvalidCellIndex;
                    for (std::size_t id = 0; id < ws.donorRichCells.size(); ++id) {
                        if (donorRemaining[id] <= eps) {
                            continue;
                        }
                        const std::int32_t dc = ws.donorRichCells[id];
                        const double dist = passive_cell_distance(dc, rc, grid, params);
                        if (dist < bestDistance ||
                            (dist == bestDistance && dc < bestCell)) {
                            bestDistance = dist;
                            bestDonor = id;
                            bestCell = dc;
                        }
                    }
                    if (bestDonor == ws.donorRichCells.size()) {
                        break;
                    }
                    const double transfer = std::min(donorRemaining[bestDonor], receiverRemaining[ir]);
                    if (transfer <= eps) {
                        break;
                    }
                    donorRemaining[bestDonor] -= transfer;
                    receiverRemaining[ir] -= transfer;
                    ws.transferPlan.push_back(ResamplingTransferPlanEntry{
                        bestCell,
                        rc,
                        transfer,
                        bestDistance,
                        donorRemaining[bestDonor],
                        receiverRemaining[ir]});
                    plannedMass += transfer;
                    massWeightedDistance += transfer * bestDistance;
                    maxDistance = std::max(maxDistance, bestDistance);
                    if (bestDistance <= adjacentLimit) {
                        adjacentPairs += 1u;
                    }
                }
            }

            double remainingReceiver = 0.0;
            double remainingDonor = 0.0;
            for (double v : receiverRemaining) remainingReceiver += v;
            for (double v : donorRemaining) remainingDonor += v;

            d.transferPlanBuilt = true;
            d.nTransferPairs = static_cast<std::uint64_t>(ws.transferPlan.size());
            d.nAdjacentTransferPairs = adjacentPairs;
            d.plannedTransferMass = plannedMass;
            d.remainingReceiverDeficitAfterPlan = remainingReceiver;
            d.remainingDonorExcessAfterPlan = remainingDonor;
            d.transferMassCoverageFraction = d.receiverMassDeficitToTarget > 0.0
                ? plannedMass / d.receiverMassDeficitToTarget : 0.0;
            d.transferMeanCellDistance = plannedMass > 0.0 ? massWeightedDistance / plannedMass : 0.0;
            d.transferMaxCellDistance = maxDistance;
            d.transferPlanDonorLimited = remainingReceiver > eps && remainingDonor <= eps;
            d.transferPlanReceiverLimited = remainingDonor > eps && remainingReceiver <= eps;
            if (!ws.transferPlan.empty()) {
                d.firstTransferDonorCell = ws.transferPlan.front().donorCell;
                d.firstTransferReceiverCell = ws.transferPlan.front().receiverCell;
                d.lastTransferDonorCell = ws.transferPlan.back().donorCell;
                d.lastTransferReceiverCell = ws.transferPlan.back().receiverCell;
            }
            }

            // Patch 0117: passive donor particle selection.
            //
            // Follow the passive transfer plan and select true Fluid particle
            // indices from each donor cell.  The state is deliberately left
            // untouched.  Selection is deterministic: for each plan entry, scan
            // particle indices in increasing order and skip particles already
            // selected by an earlier entry.  Because future extraction operates
            // on indivisible particle slots before exact mass/momentum remap,
            // the selected mass can overshoot the continuous planned mass.
            if (!ws.transferPlan.empty()) {
                std::vector<std::uint8_t> selected(static_cast<std::size_t>(state.Np), 0u);
                double selectedMassTotal = 0.0;
                double selectedMaxMass = 0.0;
                std::uint64_t maxPerEntry = 0u;
                constexpr double selectEps = 1.0e-14;

                for (const ResamplingTransferPlanEntry& entry : ws.transferPlan) {
                    if (entry.donorCell < 0 || entry.plannedMass <= selectEps) {
                        continue;
                    }
                    double selectedForEntry = 0.0;
                    std::uint64_t countForEntry = 0u;
                    const std::size_t donorCell = static_cast<std::size_t>(entry.donorCell);
                    const std::uint64_t begin = donorCell + 1u < ws.cellParticleOffsets.size()
                        ? ws.cellParticleOffsets[donorCell] : 0u;
                    const std::uint64_t end = donorCell + 1u < ws.cellParticleOffsets.size()
                        ? ws.cellParticleOffsets[donorCell + 1u] : 0u;
                    for (std::uint64_t pp = begin; pp < end; ++pp) {
                        if (pp >= ws.cellParticleIndices.size()) {
                            break;
                        }
                        const std::uint64_t pi64 = ws.cellParticleIndices[static_cast<std::size_t>(pp)];
                        if (pi64 == kInvalidParticleIndex || pi64 >= state.Np) {
                            continue;
                        }
                        const std::size_t i = static_cast<std::size_t>(pi64);
                        if (selected[i]) {
                            continue;
                        }
                        const double mp = state.mass[i];
                        if (!(mp > 0.0)) {
                            continue;
                        }
                        selected[i] = 1u;
                        selectedForEntry += mp;
                        selectedMassTotal += mp;
                        selectedMaxMass = std::max(selectedMaxMass, mp);
                        countForEntry += 1u;
                        const std::size_t dc = static_cast<std::size_t>(entry.donorCell);
                        if (dc < ws.donorSelectedParticleCount.size()) {
                            ws.donorSelectedParticleCount[dc] += 1u;
                            ws.donorSelectedMass[dc] += mp;
                        }
                        ws.selectedDonorParticles.push_back(ResamplingSelectedDonorParticle{
                            static_cast<std::uint64_t>(i),
                            entry.donorCell,
                            entry.receiverCell,
                            mp,
                            entry.plannedMass,
                            selectedForEntry});
                        if (selectedForEntry + selectEps >= entry.plannedMass) {
                            break;
                        }
                    }
                    maxPerEntry = std::max(maxPerEntry, countForEntry);
                }

                std::uint64_t donorCellsWithSelection = 0u;
                std::uint64_t maxPerCell = 0u;
                for (int c = 0; c < nc; ++c) {
                    const std::uint32_t cc = ws.donorSelectedParticleCount[static_cast<std::size_t>(c)];
                    if (cc > 0u) {
                        donorCellsWithSelection += 1u;
                        maxPerCell = std::max(maxPerCell, static_cast<std::uint64_t>(cc));
                    }
                }

                d.donorParticleSelectionBuilt = d.transferPlanBuilt;
                d.nSelectedDonorParticles = static_cast<std::uint64_t>(ws.selectedDonorParticles.size());
                d.nDonorCellsWithSelectedParticles = donorCellsWithSelection;
                d.maxSelectedParticlesForTransferEntry = maxPerEntry;
                d.maxSelectedParticlesPerDonorCell = maxPerCell;
                d.selectedDonorParticleMass = selectedMassTotal;
                d.selectedDonorMassOvershoot = selectedMassTotal - d.plannedTransferMass;
                d.selectedDonorMassCoverageFraction = d.plannedTransferMass > 0.0
                    ? selectedMassTotal / d.plannedTransferMass : 0.0;
                d.selectedDonorMeanParticleMass = d.nSelectedDonorParticles > 0u
                    ? selectedMassTotal / static_cast<double>(d.nSelectedDonorParticles) : 0.0;
                d.selectedDonorMaxParticleMass = selectedMaxMass;
                d.donorParticleSelectionExactOrOvershoot =
                    selectedMassTotal + selectEps >= d.plannedTransferMass;
                d.donorParticleSelectionUnderfilled =
                    selectedMassTotal + selectEps < d.plannedTransferMass;
                if (!ws.selectedDonorParticles.empty()) {
                    const auto& first = ws.selectedDonorParticles.front();
                    const auto& last = ws.selectedDonorParticles.back();
                    d.firstSelectedDonorParticle = first.particleIndex;
                    d.lastSelectedDonorParticle = last.particleIndex;
                    d.firstSelectedDonorCell = first.donorCell;
                    d.lastSelectedDonorCell = last.donorCell;
                    d.firstSelectedReceiverCell = first.receiverCell;
                    d.lastSelectedReceiverCell = last.receiverCell;
                }

                // Patch 0118: passive extraction operation plan.
                //
                // Convert the 0117 selected donor-particle list into explicit
                // extraction operations that a future mutating patch can apply
                // by changing role Fluid -> Inactive and pushing the extracted
                // slots into the free-list.  This builder is deliberately
                // read-only: it records mass, momentum and kinetic energy but
                // never changes state.role, state.mass, state.x or state.v.
                if (!ws.selectedDonorParticles.empty()) {
                    MPCD_DEPOSIT_PROFILE(depositProfileSeconds, PassiveExtractionPlan);
                    std::vector<std::uint8_t> seenExtracted(static_cast<std::size_t>(state.Np), 0u);
                    std::vector<std::uint8_t> donorCellSeen(static_cast<std::size_t>(nc), 0u);
                    std::vector<std::uint8_t> receiverCellSeen(static_cast<std::size_t>(nc), 0u);
                    double extractionMass = 0.0;
                    double extractionPx = 0.0;
                    double extractionPy = 0.0;
                    double extractionKinetic = 0.0;
                    double extractionMaxMass = 0.0;
                    bool allSelectedAreFluid = true;
                    bool noDuplicateParticles = true;
                    std::uint64_t donorCells = 0u;
                    std::uint64_t receiverCells = 0u;

                    for (const ResamplingSelectedDonorParticle& selectedParticle : ws.selectedDonorParticles) {
                        const std::uint64_t pi64 = selectedParticle.particleIndex;
                        if (pi64 == kInvalidParticleIndex || pi64 >= state.Np) {
                            allSelectedAreFluid = false;
                            noDuplicateParticles = false;
                            continue;
                        }
                        const std::size_t pi = static_cast<std::size_t>(pi64);
                        if (seenExtracted[pi]) {
                            noDuplicateParticles = false;
                            continue;
                        }
                        seenExtracted[pi] = 1u;

                        const bool isFluid = is_fluid_particle(state, pi);
                        allSelectedAreFluid = allSelectedAreFluid && isFluid;
                        const double mp = state.mass[pi];
                        const double vx = state.vx[pi];
                        const double vy = state.vy[pi];
                        const double px = mp * vx;
                        const double py = mp * vy;
                        const double ke = 0.5 * mp * (vx * vx + vy * vy);

                        if (selectedParticle.donorCell >= 0 && selectedParticle.donorCell < nc) {
                            const std::size_t dc = static_cast<std::size_t>(selectedParticle.donorCell);
                            if (!donorCellSeen[dc]) {
                                donorCellSeen[dc] = 1u;
                                donorCells += 1u;
                            }
                        }
                        if (selectedParticle.receiverCell >= 0 && selectedParticle.receiverCell < nc) {
                            const std::size_t rc = static_cast<std::size_t>(selectedParticle.receiverCell);
                            if (!receiverCellSeen[rc]) {
                                receiverCellSeen[rc] = 1u;
                                receiverCells += 1u;
                            }
                        }

                        extractionMass += mp;
                        extractionPx += px;
                        extractionPy += py;
                        extractionKinetic += ke;
                        extractionMaxMass = std::max(extractionMaxMass, mp);
                        ws.passiveExtractionOperations.push_back(ResamplingPassiveExtractionOperation{
                            pi64,
                            selectedParticle.donorCell,
                            selectedParticle.receiverCell,
                            state.type[pi],
                            mp,
                            px,
                            py,
                            ke,
                            particle_role_value(state, pi),
                            static_cast<std::uint8_t>(ParticleRole::Inactive)});
                    }

                    d.extractionPlanBuilt = d.donorParticleSelectionBuilt;
                    d.nExtractionOperations = static_cast<std::uint64_t>(ws.passiveExtractionOperations.size());
                    d.nExtractionParticles = d.nExtractionOperations;
                    d.nExtractionDonorCells = donorCells;
                    d.nExtractionReceiverCells = receiverCells;
                    d.extractionMass = extractionMass;
                    d.extractionMomentumX = extractionPx;
                    d.extractionMomentumY = extractionPy;
                    d.extractionKineticEnergy = extractionKinetic;
                    d.extractionMeanParticleMass = d.nExtractionParticles > 0u
                        ? extractionMass / static_cast<double>(d.nExtractionParticles) : 0.0;
                    d.extractionMaxParticleMass = extractionMaxMass;
                    d.extractionMassOvershoot = extractionMass - d.plannedTransferMass;
                    d.extractionMassCoverageFraction = d.plannedTransferMass > 0.0
                        ? extractionMass / d.plannedTransferMass : 0.0;
                    d.hypotheticalPoolFreeSlotsAfterExtraction = d.poolFreeSlots + d.nExtractionParticles;
                    d.extractionAllSelectedAreFluid = allSelectedAreFluid;
                    d.extractionNoDuplicateParticles = noDuplicateParticles;
                    if (!ws.passiveExtractionOperations.empty()) {
                        const auto& first = ws.passiveExtractionOperations.front();
                        const auto& last = ws.passiveExtractionOperations.back();
                        d.firstExtractionParticle = first.particleIndex;
                        d.lastExtractionParticle = last.particleIndex;
                        d.firstExtractionDonorCell = first.donorCell;
                        d.lastExtractionDonorCell = last.donorCell;
                        d.firstExtractionReceiverCell = first.receiverCell;
                        d.lastExtractionReceiverCell = last.receiverCell;
                    }
                } else {
                    d.extractionPlanBuilt = d.donorParticleSelectionBuilt;
                    d.hypotheticalPoolFreeSlotsAfterExtraction = d.poolFreeSlots;
                    d.extractionAllSelectedAreFluid = d.donorParticleSelectionBuilt;
                    d.extractionNoDuplicateParticles = d.donorParticleSelectionBuilt;
                }
            }
        } else {
            d.transferPlanBuilt = d.candidateListsBuilt;
            d.remainingReceiverDeficitAfterPlan = d.receiverMassDeficitToTarget;
            d.remainingDonorExcessAfterPlan = d.donorMassExcessAboveTarget;
        }
    }

    if (totalMass > 0.0) {
        d.meanUx = totalPx / totalMass;
        d.meanUy = totalPy / totalMass;
    }
    if (nonEmpty > 0u) {
        const double invNonEmpty = 1.0 / static_cast<double>(nonEmpty);
        d.cellUxRms = std::sqrt(cellUxRmsAccum * invNonEmpty);
        d.cellUyRms = std::sqrt(cellUyRmsAccum * invNonEmpty);
    }

    if (roles.fluid > 0u) {
        const double invNp = 1.0 / static_cast<double>(roles.fluid);
        d.particleMassMean = particleMassSum * invNp;
        d.particleMassStd = std::sqrt(std::max(0.0, particleMassSum2 * invNp - d.particleMassMean * d.particleMassMean));
        d.particleMassRelStd = d.particleMassMean > 0.0 ? d.particleMassStd / d.particleMassMean : 0.0;
        d.particleMassMin = std::isfinite(particleMassMin) ? particleMassMin : 0.0;
        d.particleMassMax = particleMassMax;
    }

    d.depositProfileSeconds = depositProfileSeconds;
    d.depositProfileParticlesVisited = static_cast<std::uint64_t>(n);
    d.depositProfileFluidParticles = roles.fluid;
    d.depositProfileCells = static_cast<std::uint64_t>(std::max(0, nc));
    d.depositProfileBuildMutationPlan = buildMutationPlan;
    deposit_profile_accumulator().add(
        params.outputDir, profileContext, depositProfileSeconds,
        static_cast<std::uint64_t>(n), roles.fluid,
        static_cast<std::uint64_t>(std::max(0, nc)));

    return d;
}


WeightedResamplingDiagnostics refresh_weighted_real_fluid_velocity_deposit(
    const ParticleState& state,
    const SimulationParams& params,
    const CellGrid& grid,
    const FluidDomainBounds& domain,
    double time,
    const GridShift& shift,
    WeightedRealFluidDepositWorkspace& ws,
    const WeightedResamplingDiagnostics& previousDiagnostics,
    ResamplingDepositProfileContext profileContext) {
    (void)params;
    (void)domain;
    (void)time;
    (void)shift;

    std::array<double, ResamplingDepositProfilePhaseCount> depositProfileSeconds{};

    int nc = 0;
    std::size_t n = 0u;
    int nt = 1;
    {
        MPCD_DEPOSIT_PROFILE(depositProfileSeconds, ValidateResize);
        validate_particle_state(state, "refresh_weighted_real_fluid_velocity_deposit");
        nc = grid.numCells;
        if (nc <= 0) {
            throw std::runtime_error("refresh_weighted_real_fluid_velocity_deposit: invalid number of cells");
        }
        if (ws.allocatedCells != nc || ws.allocatedParticles < state.Np) {
            // Fall back to the full deposit if the caller did not provide a
            // valid current deposit workspace.  This preserves correctness for
            // accidental direct use outside the post-thermal path.
            return deposit_weighted_real_fluid(
                state, params, grid, domain, time, shift, ws, false, profileContext);
        }
        n = static_cast<std::size_t>(state.Np);
        nt = std::max(1, thread_count());
        if (ws.allocatedThreads < nt ||
            ws.localPx.size() < static_cast<std::size_t>(nt * nc) ||
            ws.localPy.size() < static_cast<std::size_t>(nt * nc)) {
            return deposit_weighted_real_fluid(
                state, params, grid, domain, time, shift, ws, false, profileContext);
        }
    }

    {
        MPCD_DEPOSIT_PROFILE(depositProfileSeconds, ClearArrays);
        std::fill(ws.px.begin(), ws.px.end(), 0.0);
        std::fill(ws.py.begin(), ws.py.end(), 0.0);
        std::fill(ws.ux.begin(), ws.ux.end(), 0.0);
        std::fill(ws.uy.begin(), ws.uy.end(), 0.0);
        std::fill(ws.localPx.begin(), ws.localPx.end(), 0.0);
        std::fill(ws.localPy.begin(), ws.localPy.end(), 0.0);
    }

    std::uint64_t fluidParticles = 0u;
    {
        MPCD_DEPOSIT_PROFILE(depositProfileSeconds, ParticleLoopCellAccum);
#pragma omp parallel reduction(+:fluidParticles)
        {
            const int tid = thread_id();
            const std::size_t offset = static_cast<std::size_t>(tid * nc);
#pragma omp for
            for (std::int64_t ii = 0; ii < static_cast<std::int64_t>(n); ++ii) {
                const std::size_t i = static_cast<std::size_t>(ii);
                if (!is_fluid_particle(state, i)) {
                    continue;
                }
                if (i >= ws.cellId.size()) {
                    continue;
                }
                const int c = ws.cellId[i];
                if (c < 0 || c >= nc) {
                    continue;
                }
                const double m = state.mass[i];
                const std::size_t k = offset + static_cast<std::size_t>(c);
                ws.localPx[k] += m * state.vx[i];
                ws.localPy[k] += m * state.vy[i];
                fluidParticles += 1u;
            }
        }
    }

    double totalPx = 0.0;
    double totalPy = 0.0;
    std::uint64_t nonEmpty = 0u;
    double cellUxRmsAccum = 0.0;
    double cellUyRmsAccum = 0.0;
    {
        MPCD_DEPOSIT_PROFILE(depositProfileSeconds, ReduceCellsFinalize);
#pragma omp parallel for reduction(+:totalPx,totalPy,nonEmpty,cellUxRmsAccum,cellUyRmsAccum) if(nc > 256)
        for (int c = 0; c < nc; ++c) {
            double px = 0.0;
            double py = 0.0;
            for (int t = 0; t < nt; ++t) {
                const std::size_t k = static_cast<std::size_t>(t * nc + c);
                px += ws.localPx[k];
                py += ws.localPy[k];
            }
            const std::size_t kk = static_cast<std::size_t>(c);
            ws.px[kk] = px;
            ws.py[kk] = py;
            const double mass = ws.mass[kk];
            if (mass > 0.0) {
                const double ux = px / mass;
                const double uy = py / mass;
                ws.ux[kk] = ux;
                ws.uy[kk] = uy;
                nonEmpty += 1u;
                cellUxRmsAccum += ux * ux;
                cellUyRmsAccum += uy * uy;
            }
            totalPx += px;
            totalPy += py;
        }
    }

    WeightedResamplingDiagnostics d = previousDiagnostics;
    d.totalPx = totalPx;
    d.totalPy = totalPy;
    if (d.totalMass > 0.0) {
        d.meanUx = totalPx / d.totalMass;
        d.meanUy = totalPy / d.totalMass;
    } else {
        d.meanUx = 0.0;
        d.meanUy = 0.0;
    }
    if (nonEmpty > 0u) {
        const double invNonEmpty = 1.0 / static_cast<double>(nonEmpty);
        d.cellUxRms = std::sqrt(cellUxRmsAccum * invNonEmpty);
        d.cellUyRms = std::sqrt(cellUyRmsAccum * invNonEmpty);
    } else {
        d.cellUxRms = 0.0;
        d.cellUyRms = 0.0;
    }

    d.depositProfileSeconds = depositProfileSeconds;
    d.depositProfileParticlesVisited = static_cast<std::uint64_t>(n);
    d.depositProfileFluidParticles = fluidParticles;
    d.depositProfileCells = static_cast<std::uint64_t>(std::max(0, nc));
    d.depositProfileBuildMutationPlan = false;
    deposit_profile_accumulator().add(
        params.outputDir, profileContext, depositProfileSeconds,
        static_cast<std::uint64_t>(n), fluidParticles,
        static_cast<std::uint64_t>(std::max(0, nc)));

    return d;
}

} // namespace mpcd
