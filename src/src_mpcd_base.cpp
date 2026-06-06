#include "src_mpcd_base.h"
#include "closed_capacity_response.h"
#include "cuda_resampling_persistent_active_path_0240.h"
#include "cuda_streaming_periodic_0245.h"
#include "cuda_streaming_wall_simple_0246.h"
#include "cuda_streaming_piston_0247b.h"
#include "cuda_immersed_rectangle_0247.h"
#include "cuda_inlet_outlet_fullface_0249a.h"
#include "cuda_inlet_outlet_segmented_0249b.h"
#include "cuda_shared_particle_state_0251.h"

#include <algorithm>
#include <chrono>
#include <cstdlib>
#include <cstddef>
#include <cstdint>
#include <cmath>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <limits>
#include <string>
#include <vector>


namespace mpcd {
namespace {

using ProfileClock = std::chrono::steady_clock;

struct StepProfilePhaseIndex {
    enum : std::size_t {
        ForceStream = 0,
        Domain = 1,
        Boundary = 2,
        Immersed = 3,
        Collision = 4,
        Q6Projection = 5,
        ClosedCapacity = 6,
        Thermostat = 7,
        KeepMeanFlow = 8,
        ResamplingPoolInitial = 9,
        ResamplingDepositInitial = 10,
        ResamplingAttachInitial = 11,
        ResamplingThermalReferenceCapture = 12,
        ResamplingPopulationGuard = 13,
        ResamplingPostGuardPool = 14,
        ResamplingPostGuardDeposit = 15,
        ResamplingLatentActivation = 16,
        ResamplingExtraction = 17,
        ResamplingInsertion = 18,
        ResamplingPostEditPool = 19,
        ResamplingPostEditDeposit = 20,
        ResamplingCapacityForRemap = 21,
        ResamplingRemap = 22,
        ResamplingThermalAfterRemap = 23,
        ResamplingMassGuard = 24,
        ResamplingPostRemapDeposit = 25,
        ResamplingPostRemapPool = 26,
        ResamplingThermalLate = 27,
        ResamplingPostThermalDeposit = 28,
        ResamplingPostThermalPool = 29,
        ResamplingAttachFinalDiagnostics = 30
    };
};

static_assert(StepProfilePhaseCount == 31u, "StepProfile phase count mismatch");

bool internal_profiles_enabled_0176();

class ScopedStepProfileTimer {
public:
    ScopedStepProfileTimer(StepProfile& profile, const std::size_t phaseIndex)
        : profile_(profile), phaseIndex_(phaseIndex), enabled_(internal_profiles_enabled_0176()) {
        if (enabled_) {
            t0_ = ProfileClock::now();
        }
    }

    ScopedStepProfileTimer(const ScopedStepProfileTimer&) = delete;
    ScopedStepProfileTimer& operator=(const ScopedStepProfileTimer&) = delete;

    ~ScopedStepProfileTimer() {
        if (enabled_ && phaseIndex_ < profile_.seconds.size()) {
            profile_.seconds[phaseIndex_] += std::chrono::duration<double>(ProfileClock::now() - t0_).count();
        }
    }

private:
    StepProfile& profile_;
    std::size_t phaseIndex_;
    bool enabled_ = false;
    ProfileClock::time_point t0_{};
};

#define MPCD_PROFILE_PHASE(profile, phaseName) \
    ScopedStepProfileTimer mpcdProfileTimer_##phaseName((profile), StepProfilePhaseIndex::phaseName)


bool internal_profiles_enabled_0176() {
    static const bool enabled = []() {
        const char* v = std::getenv("MPCD_INTERNAL_PROFILES");
        if (v == nullptr || *v == '\0') {
            return false;
        }
        const std::string s(v);
        return !(s == "0" || s == "false" || s == "FALSE" ||
                 s == "off" || s == "OFF" || s == "no" || s == "NO");
    }();
    return enabled;
}


bool cuda_classic_src_periodic_resident_0260_requested() {
    const char* v = std::getenv("MPCD_CUDA_CLASSIC_SRC_PERIODIC_RESIDENT_0260");
    if (v == nullptr || *v == '\0') {
        return false;
    }
    const std::string s(v);
    return !(s == "0" || s == "false" || s == "FALSE" ||
             s == "off" || s == "OFF" || s == "no" || s == "NO");
}

bool cuda_classic_src_periodic_resident_0260_supported(const SimulationParams& params) {
    return params.srcClassicCudaModeEnable &&
           params.bcLeft == "periodic" && params.bcRight == "periodic" &&
           params.bcBottom == "periodic" && params.bcTop == "periodic" &&
           !params.openBoundarySegmentsEnable && params.openBoundarySegmentCount == 0 &&
           !params.immersedSolidEnable &&
           !params.projectionEnable &&
           !params.closedCapacityResponseEnable &&
           !params.resamplingEnable;
}

bool cuda_classic_src_periodic_resident_0260_active(const SimulationParams& params) {
    return cuda_classic_src_periodic_resident_0260_requested() &&
           cuda_classic_src_periodic_resident_0260_supported(params);
}

bool cuda_classic_src_wall_resident_0261_requested() {
    const char* v = std::getenv("MPCD_CUDA_CLASSIC_SRC_WALL_RESIDENT_0261");
    if (v == nullptr || *v == '\0') {
        return false;
    }
    const std::string s(v);
    return !(s == "0" || s == "false" || s == "FALSE" ||
             s == "off" || s == "OFF" || s == "no" || s == "NO");
}

bool cuda_wall_mode_supported_0261(const std::string& bc) {
    return bc == "solid" || bc == "specular" || bc == "bounceback";
}

bool cuda_classic_src_wall_resident_0261_supported(const SimulationParams& params) {
    return params.srcClassicCudaModeEnable &&
           params.bcLeft == "periodic" && params.bcRight == "periodic" &&
           cuda_wall_mode_supported_0261(params.bcBottom) &&
           cuda_wall_mode_supported_0261(params.bcTop) &&
           !params.openBoundarySegmentsEnable && params.openBoundarySegmentCount == 0 &&
           !params.immersedSolidEnable &&
           !params.projectionEnable &&
           !params.closedCapacityResponseEnable &&
           !params.resamplingEnable &&
           params.fluidXMinVelocity == 0.0 && params.fluidXMaxVelocity == 0.0 &&
           params.fluidYMinVelocity == 0.0 && params.fluidYMaxVelocity == 0.0;
}

bool cuda_classic_src_wall_resident_0261_active(const SimulationParams& params) {
    return cuda_classic_src_wall_resident_0261_requested() &&
           cuda_classic_src_wall_resident_0261_supported(params);
}


struct PostGuardDepositProfileAccumulator {
    std::string outputDir;
    std::uint64_t calls = 0u;
    std::uint64_t buildMutationPlanCalls = 0u;
    std::uint64_t editedCells = 0u;
    std::uint64_t candidateCells = 0u;
    std::uint64_t candidateParticleRefs = 0u;
    std::uint64_t scannedParticleRefs = 0u;
    std::uint64_t eligibleParticleRefs = 0u;
    std::uint64_t splitParticles = 0u;
    std::uint64_t extractedParticles = 0u;
    std::uint64_t fullDepositParticlesVisited = 0u;
    std::uint64_t fullDepositFluidParticles = 0u;
    std::uint64_t fullDepositCells = 0u;
    std::array<double, ResamplingDepositProfilePhaseCount> depositSeconds{};

    void add(const std::string& out,
             const ResamplingPopulationGuardDiagnostics& populationGuard,
             const WeightedResamplingDiagnostics& postGuardDeposit) {
        if (!internal_profiles_enabled_0176()) {
            return;
        }
        if (!out.empty()) {
            outputDir = out;
        }
        calls += 1u;
        buildMutationPlanCalls += postGuardDeposit.depositProfileBuildMutationPlan ? 1u : 0u;
        editedCells += populationGuard.overfullEditedCells + populationGuard.underfullEditedCells;
        candidateCells += populationGuard.overfullCandidateCells + populationGuard.underfullCandidateCells;
        candidateParticleRefs += populationGuard.overfullCandidateParticleRefs +
                                 populationGuard.underfullCandidateParticleRefs;
        scannedParticleRefs += populationGuard.overfullParticleRefsScanned +
                               populationGuard.underfullParticleRefsScanned;
        eligibleParticleRefs += populationGuard.overfullEligibleParticleRefs +
                                populationGuard.underfullEligibleParticleRefs;
        splitParticles += populationGuard.splitParticlesCreated;
        extractedParticles += populationGuard.extractedParticles;
        fullDepositParticlesVisited += postGuardDeposit.depositProfileParticlesVisited;
        fullDepositFluidParticles += postGuardDeposit.depositProfileFluidParticles;
        fullDepositCells += postGuardDeposit.depositProfileCells;
        for (std::size_t i = 0; i < ResamplingDepositProfilePhaseCount; ++i) {
            depositSeconds[i] += postGuardDeposit.depositProfileSeconds[i];
        }
    }

    ~PostGuardDepositProfileAccumulator() {
        if (outputDir.empty() || calls == 0u) {
            return;
        }
        std::error_code ec;
        std::filesystem::create_directories(outputDir, ec);
        const std::filesystem::path path = std::filesystem::path(outputDir) / "post_guard_profile_0173.csv";
        std::ofstream out(path);
        if (!out) {
            return;
        }
        out << "group,phase,total_s,ms_per_call,percent_group_total,calls,value_total,value_per_call\n";
        out << std::setprecision(17);
        double total = 0.0;
        for (double v : depositSeconds) {
            total += v;
        }
        const double denom = static_cast<double>(calls);
        for (std::size_t i = 0; i < ResamplingDepositProfilePhaseCount; ++i) {
            const double value = depositSeconds[i];
            const double percent = total > std::numeric_limits<double>::min() ? 100.0 * value / total : 0.0;
            out << "post_guard_deposit," << resampling_deposit_profile_phase_name(i) << ','
                << value << ',' << (1000.0 * value / denom) << ',' << percent << ','
                << calls << ",0,0\n";
        }
        out << "post_guard_deposit,total_post_guard_deposit," << total << ','
            << (1000.0 * total / denom) << ",100," << calls << ",0,0\n";

        auto emit_meta = [&](const char* name, const std::uint64_t value) {
            out << "metadata," << name << ",0,0,0," << calls << ',' << value << ','
                << (static_cast<double>(value) / denom) << "\n";
        };
        emit_meta("post_guard_calls", calls);
        emit_meta("post_guard_build_mutation_plan_calls", buildMutationPlanCalls);
        emit_meta("post_guard_edited_cells_total", editedCells);
        emit_meta("post_guard_candidate_cells_total", candidateCells);
        emit_meta("post_guard_candidate_particle_refs_total", candidateParticleRefs);
        emit_meta("post_guard_scanned_particle_refs_total", scannedParticleRefs);
        emit_meta("post_guard_eligible_particle_refs_total", eligibleParticleRefs);
        emit_meta("post_guard_split_particles_total", splitParticles);
        emit_meta("post_guard_extracted_particles_total", extractedParticles);
        emit_meta("post_guard_full_deposit_particles_visited_total", fullDepositParticlesVisited);
        emit_meta("post_guard_full_deposit_fluid_particles_total", fullDepositFluidParticles);
        emit_meta("post_guard_full_deposit_cells_total", fullDepositCells);
    }
};

PostGuardDepositProfileAccumulator& post_guard_deposit_profile_accumulator() {
    static PostGuardDepositProfileAccumulator acc;
    return acc;
}

bool is_mass_renormalization_step(const SimulationParams& params, std::uint64_t step) {
    return params.resamplingMassRenormalizationPeriod > 0 &&
           (step % static_cast<std::uint64_t>(params.resamplingMassRenormalizationPeriod) == 0u);
}

void taylor_green_body_acceleration(const SimulationParams& params,
                                    double x,
                                    double y,
                                    double& ax,
                                    double& ay) {
    ax = 0.0;
    ay = 0.0;
    if (!params.taylorGreenForcingEnable || !(params.taylorGreenForcingAmplitude > 0.0)) {
        return;
    }

    constexpr double pi = 3.141592653589793238462643383279502884;
    const double kx = 2.0 * pi * static_cast<double>(params.taylorGreenForcingModeX) / params.Lx;
    const double ky = 2.0 * pi * static_cast<double>(params.taylorGreenForcingModeY) / params.Ly;
    const double sx = std::sin(kx * x);
    const double cx = std::cos(kx * x);
    const double sy = std::sin(ky * y);
    const double cy = std::cos(ky * y);

    ax = params.taylorGreenForcingAmplitude * sx * cy;
    ay = -params.taylorGreenForcingAmplitude * cx * sy;
}

void capture_resampling_thermal_reference(const ParticleState& state,
                                          const WeightedRealFluidDepositWorkspace& deposit,
                                          std::vector<double>& targetEnergy,
                                          std::vector<std::uint8_t>& targetCell) {
    const int nc = deposit.allocatedCells;
    targetEnergy.assign(static_cast<std::size_t>(std::max(0, nc)), 0.0);
    targetCell.assign(static_cast<std::size_t>(std::max(0, nc)), 0u);
    if (nc <= 0 || deposit.wetCell.size() != static_cast<std::size_t>(nc) ||
        deposit.count.size() != static_cast<std::size_t>(nc)) {
        return;
    }
    for (int c = 0; c < nc; ++c) {
        const std::size_t kk = static_cast<std::size_t>(c);
        if (deposit.wetCell[kk] && deposit.count[kk] > 0u && deposit.mass[kk] > 0.0) {
            targetCell[kk] = 1u;
        }
    }
    for (std::size_t i = 0; i < static_cast<std::size_t>(state.Np); ++i) {
        if (!is_fluid_particle(state, i) || i >= deposit.cellId.size()) {
            continue;
        }
        const int c = deposit.cellId[i];
        if (c < 0 || c >= nc) {
            continue;
        }
        const std::size_t kk = static_cast<std::size_t>(c);
        if (!targetCell[kk]) {
            continue;
        }
        const double dux = state.vx[i] - deposit.ux[kk];
        const double duy = state.vy[i] - deposit.uy[kk];
        targetEnergy[kk] += 0.5 * state.mass[i] * (dux * dux + duy * duy);
    }
}

void install_resampling_thermal_reference(WeightedRealFluidDepositWorkspace& deposit,
                                          const std::vector<double>& targetEnergy,
                                          const std::vector<std::uint8_t>& targetCell) {
    if (targetEnergy.empty() || targetEnergy.size() != targetCell.size()) {
        return;
    }
    if (deposit.remapThermalEnergyTarget.size() != targetEnergy.size() ||
        deposit.remapThermalCell.size() != targetCell.size()) {
        return;
    }
    deposit.remapThermalEnergyTarget = targetEnergy;
    deposit.remapThermalCell = targetCell;
}

ResamplingRemapApplyDiagnostics make_thermal_reference_gate(const std::vector<std::uint8_t>& targetCell) {
    ResamplingRemapApplyDiagnostics d{};
    d.attempted = true;
    for (const std::uint8_t v : targetCell) {
        if (v) {
            d.applied = true;
            break;
        }
    }
    return d;
}


bool cuda_resampling_persistent_active_path_0240_requested(const ParticleState& state) {
    const char* enabled = std::getenv("MPCD_CUDA_RESAMPLING_PERSISTENT_0240");
    if (enabled == nullptr) {
        return false;
    }
    std::string value(enabled);
    for (char& c : value) {
        c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
    }
    if (!(value == "1" || value == "true" || value == "yes" || value == "on")) {
        return false;
    }

    const char* minParticlesEnv = std::getenv("MPCD_CUDA_RESAMPLING_PERSISTENT_0240_MIN_PARTICLES");
    if (minParticlesEnv != nullptr && minParticlesEnv[0] != '\0') {
        try {
            const std::uint64_t minParticles = static_cast<std::uint64_t>(std::stoull(minParticlesEnv));
            if (state.Np < minParticles) {
                return false;
            }
        } catch (...) {
            return false;
        }
    }
    return true;
}

void apply_keep_mean_flow(ParticleState& state, const SimulationParams& params) {
    if (!params.keepMeanFlowEnable) {
        return;
    }
    validate_particle_state(state, "apply_keep_mean_flow");
    const std::size_t n = static_cast<std::size_t>(state.Np);

    double mass = 0.0;
    double px = 0.0;
    double py = 0.0;
#pragma omp parallel for reduction(+:mass,px,py) if(n > 10000)
    for (std::int64_t ii = 0; ii < static_cast<std::int64_t>(n); ++ii) {
        const std::size_t i = static_cast<std::size_t>(ii);
        if (!is_fluid_particle(state, i)) {
            continue;
        }
        const double m = state.mass[i];
        mass += m;
        px += m * state.vx[i];
        py += m * state.vy[i];
    }
    if (!(mass > 0.0)) {
        return;
    }

    const double dvx = params.targetMeanUx - px / mass;
    const double dvy = params.targetMeanUy - py / mass;
#pragma omp parallel for if(n > 10000)
    for (std::int64_t ii = 0; ii < static_cast<std::int64_t>(n); ++ii) {
        const std::size_t i = static_cast<std::size_t>(ii);
        if (!is_fluid_particle(state, i)) {
            continue;
        }
        state.vx[i] += dvx;
        state.vy[i] += dvy;
    }
}


bool boundary_cpu_may_have_edited_particles_0251(const BoundaryDiagnostics& b) {
    return b.hitsLeft != 0u || b.hitsRight != 0u || b.hitsBottom != 0u || b.hitsTop != 0u ||
           b.inletReservoirDeleted != 0u || b.inletBackflowDeleted != 0u ||
           b.outletParticlesDeleted != 0u || b.inletParticlesInserted != 0u ||
           b.inletNetParticleDelta != 0;
}

} // namespace

const char* step_profile_phase_name(const std::size_t phaseIndex) {
    static constexpr const char* names[StepProfilePhaseCount] = {
        "force_stream",
        "domain_bounds",
        "boundary_conditions",
        "immersed_solid",
        "src_collision",
        "q6_projection",
        "closed_capacity_virial",
        "thermostat",
        "keep_mean_flow",
        "resampling_pool_initial",
        "resampling_deposit_initial",
        "resampling_attach_initial",
        "resampling_thermal_reference_capture",
        "resampling_population_guard",
        "resampling_post_guard_pool",
        "resampling_post_guard_deposit",
        "resampling_latent_activation",
        "resampling_extraction",
        "resampling_insertion",
        "resampling_post_edit_pool",
        "resampling_post_edit_deposit",
        "resampling_capacity_for_remap",
        "resampling_remap",
        "resampling_thermal_after_remap",
        "resampling_mass_guard",
        "resampling_post_remap_deposit",
        "resampling_post_remap_pool",
        "resampling_thermal_late",
        "resampling_post_thermal_deposit",
        "resampling_post_thermal_pool",
        "resampling_attach_final_diagnostics"
    };
    return phaseIndex < StepProfilePhaseCount ? names[phaseIndex] : "unknown";
}

StepResult run_src_mpcd_base_step(ParticleState& state,
                                  const SimulationParams& params,
                                  const CellGrid& grid,
                                  std::uint64_t step,
                                  SrcMpcdBaseWorkspace& workspace,
                                  bool collectResamplingDiagnosticsWhenDisabled) {
    StepResult result{};

    validate_particle_state(state, "run_src_mpcd_base_step");
    ensure_particle_roles(state, ParticleRole::Fluid);
    const bool residentClassicPeriodic0260 = cuda_classic_src_periodic_resident_0260_active(params);
    const bool residentClassicWall0261 = cuda_classic_src_wall_resident_0261_active(params);
    const bool residentClassicCuda = residentClassicPeriodic0260 || residentClassicWall0261;
    if (!residentClassicCuda || !cuda_shared_particle_state_0251_is_fresh()) {
        cuda_shared_particle_state_0251_invalidate("start_step_cpu_state_authoritative");
    }
    const std::size_t n = static_cast<std::size_t>(state.Np);

    // Uniform and optional Taylor--Green body acceleration, then free streaming
    // in the fixed numerical box. Taylor--Green forcing is evaluated at the
    // pre-stream particle position. CUDA offloads are enabled only for explicitly
    // validated boundary subsets: 0245 periodic, 0246 static y-walls, 0247b
    // moving-y-wall piston. All unsupported cases fall back to the CPU path.
    {
        MPCD_PROFILE_PHASE(result.profile, ForceStream);
        bool handledByCudaStreaming = false;
        if (cuda_piston_streaming_0247b_requested()) {
            const CudaPistonStreaming0247bDiagnostics cudaStreaming0247b =
                try_apply_cuda_piston_streaming_0247b(state, params, step);
            handledByCudaStreaming = cudaStreaming0247b.handled;
        }
        if (!handledByCudaStreaming && cuda_wall_simple_streaming_0246_requested()) {
            const CudaWallSimpleStreaming0246Diagnostics cudaStreaming0246 =
                try_apply_cuda_wall_simple_streaming_0246(state, params, step);
            handledByCudaStreaming = cudaStreaming0246.handled;
        }
        if (!handledByCudaStreaming && cuda_periodic_streaming_0245_requested()) {
            const CudaPeriodicStreaming0245Diagnostics cudaStreaming0245 =
                try_apply_cuda_periodic_streaming_0245(state, params, step);
            handledByCudaStreaming = cudaStreaming0245.handled;
        }
        if (!handledByCudaStreaming) {
#pragma omp parallel for if(n > 10000)
            for (std::int64_t ii = 0; ii < static_cast<std::int64_t>(n); ++ii) {
                const std::size_t i = static_cast<std::size_t>(ii);
                if (!is_fluid_particle(state, i)) {
                    continue;
                }
                double tgAx = 0.0;
                double tgAy = 0.0;
                taylor_green_body_acceleration(params, state.x[i], state.y[i], tgAx, tgAy);
                state.vx[i] += (params.bodyAccelerationX + tgAx) * params.dt;
                state.vy[i] += (params.bodyAccelerationY + tgAy) * params.dt;
                state.x[i] += state.vx[i] * params.dt;
                state.y[i] += state.vy[i] * params.dt;
            }
        }
    }

    const double time = static_cast<double>(step) * params.dt;
    {
        MPCD_PROFILE_PHASE(result.profile, Domain);
        result.domain = make_fluid_domain_bounds(params, time);
    }
    {
        MPCD_PROFILE_PHASE(result.profile, Boundary);
        CudaInletOutletSegmented0249bDiagnostics cudaIo0249b{};
        if (cuda_inlet_outlet_segmented_0249b_requested()) {
            cudaIo0249b = try_apply_cuda_inlet_outlet_segmented_0249b(
                state, params, result.domain, step, time);
        }
        CudaInletOutletFullface0249aDiagnostics cudaIo0249a{};
        if (cuda_inlet_outlet_fullface_0249a_requested()) {
            cudaIo0249a = try_apply_cuda_inlet_outlet_fullface_0249a(
                state, params, result.domain, step, time);
        }
        result.boundary = apply_boundary_conditions(state, params, result.domain, step, time);
        merge_cuda_inlet_outlet_segmented_0249b_diagnostics(result.boundary, cudaIo0249b);
        merge_cuda_inlet_outlet_fullface_0249a_diagnostics(result.boundary, cudaIo0249a);
        if (boundary_cpu_may_have_edited_particles_0251(result.boundary)) {
            cuda_shared_particle_state_0251_invalidate("cpu_boundary_conditions_edited_particles");
        }
    }
    {
        MPCD_PROFILE_PHASE(result.profile, Immersed);
        bool handledByCudaImmersed = false;
        if (cuda_immersed_rectangle_0247_requested()) {
            const CudaImmersedRectangle0247Diagnostics cudaImmersed0247 =
                try_apply_cuda_immersed_rectangle_0247(state, params, result.domain, time);
            if (cudaImmersed0247.handled) {
                result.immersed.hits = cudaImmersed0247.hits;
                handledByCudaImmersed = true;
            }
        }
        if (!handledByCudaImmersed) {
            result.immersed = apply_immersed_solid_reflection(state, params, result.domain, time);
            if (result.immersed.hits != 0u) {
                cuda_shared_particle_state_0251_invalidate("cpu_immersed_solid_edited_particles");
            }
        }
    }
    {
        MPCD_PROFILE_PHASE(result.profile, Collision);
        result.collision = src_collision_step(state, params, grid, result.domain, step, workspace.collision);
    }
    {
        MPCD_PROFILE_PHASE(result.profile, Q6Projection);
        if (!params.srcClassicCudaModeEnable) {
            result.q6 = apply_q6_periodic_projection(state, params, grid, result.domain, time, workspace.q6);
            if (params.projectionEnable) {
                cuda_shared_particle_state_0251_invalidate("cpu_q6_projection_after_collision");
            }
        }
    }
    {
        MPCD_PROFILE_PHASE(result.profile, ClosedCapacity);
        if (!params.srcClassicCudaModeEnable) {
            result.capacity = apply_closed_capacity_virial_kick(state, params, grid, result.domain, workspace.capacity);
            if (params.closedCapacityVirialKickEnable) {
                cuda_shared_particle_state_0251_invalidate("cpu_closed_capacity_after_collision");
            }
        }
    }
    {
        MPCD_PROFILE_PHASE(result.profile, Thermostat);
        result.thermostat = apply_cell_relative_rescale_thermostat(
            state, params, grid, workspace.collision.cellId, step, workspace.thermostat);
        if (!residentClassicCuda) {
            cuda_shared_particle_state_0251_invalidate("cpu_thermostat_after_collision");
        }
    }
    {
        MPCD_PROFILE_PHASE(result.profile, KeepMeanFlow);
        apply_keep_mean_flow(state, params);
        if (params.keepMeanFlowEnable || !residentClassicCuda) {
            cuda_shared_particle_state_0251_invalidate("cpu_keep_mean_flow_after_collision");
        }
    }
    // 0158: when resampling is disabled, the pool/deposit diagnostics are only
    // needed on steps for which the caller will write a runtime summary.  The
    // default public API keeps the previous conservative behavior; the main
    // production loop passes false on non-summary steps.
    if (!params.resamplingEnable && !collectResamplingDiagnosticsWhenDisabled) {
        return result;
    }

    // 0260/0261 resident classic CUDA keeps the host ParticleState stale between summaries.
    // The disabled-resampling diagnostics below still read the host state to report
    // resampStdN/resampMRel* in runtime_summary.csv.  Synchronize only on summary/final
    // steps, i.e. exactly when collectResamplingDiagnosticsWhenDisabled is true, so the
    // resident performance path is preserved between summaries.
    if (residentClassicCuda) {
        (void)cuda_shared_particle_state_0251_download_if_fresh(state);
    }

    {
        MPCD_PROFILE_PHASE(result.profile, ResamplingPoolInitial);
        result.resamplingPool = rebuild_resampling_particle_pool(state, workspace.resamplingPool);
    }
    const bool buildInitialResamplingPlan =
        params.resamplingEnable && params.resamplingExtractionEnable;
    {
        MPCD_PROFILE_PHASE(result.profile, ResamplingDepositInitial);
        result.resampling = deposit_weighted_real_fluid(
            state, params, grid, result.domain, time, GridShift{}, workspace.resampling,
            buildInitialResamplingPlan,
            ResamplingDepositProfileContext::Initial);
    }
    {
        MPCD_PROFILE_PHASE(result.profile, ResamplingAttachInitial);
        attach_resampling_pool_diagnostics(result.resampling, result.resamplingPool);
    }

    if (!params.resamplingEnable) {
        return result;
    }

    std::vector<double> preEditThermalEnergyTarget;
    std::vector<std::uint8_t> preEditThermalCell;
    if (params.resamplingThermalRenormalizationEnable) {
        MPCD_PROFILE_PHASE(result.profile, ResamplingThermalReferenceCapture);
        capture_resampling_thermal_reference(
            state, workspace.resampling, preEditThermalEnergyTarget, preEditThermalCell);
    }

    bool populationGuardEdited = false;
    bool planOrTransferEdited = false;
    ResamplingPopulationGuardDiagnostics populationGuard{};
    {
        MPCD_PROFILE_PHASE(result.profile, ResamplingPopulationGuard);
        populationGuard = apply_resampling_population_support_guard(
            state, workspace.resamplingPool, workspace.resampling, result.resampling, params, grid);
    }
    populationGuardEdited = populationGuard.applied;

    if (populationGuardEdited) {
        {
            MPCD_PROFILE_PHASE(result.profile, ResamplingPostGuardPool);
            result.resamplingPool = rebuild_resampling_particle_pool(state, workspace.resamplingPool);
        }
        {
            MPCD_PROFILE_PHASE(result.profile, ResamplingPostGuardDeposit);
            result.resampling = deposit_weighted_real_fluid(
                state, params, grid, result.domain, time, GridShift{}, workspace.resampling,
                params.resamplingExtractionEnable,
                ResamplingDepositProfileContext::PostGuard,
                true);
            post_guard_deposit_profile_accumulator().add(
                params.outputDir, populationGuard, result.resampling);
        }
        {
            MPCD_PROFILE_PHASE(result.profile, ResamplingAttachFinalDiagnostics);
            attach_resampling_pool_diagnostics(result.resampling, result.resamplingPool);
            attach_resampling_population_guard_diagnostics(result.resampling, populationGuard);
        }
    }

    ResamplingLatentActivationDiagnostics latentActivation{};
    if (params.resamplingLatentActivationEnable && result.resampling.candidateListsBuilt) {
        MPCD_PROFILE_PHASE(result.profile, ResamplingLatentActivation);
        latentActivation = apply_resampling_latent_activation(
            state, workspace.resamplingPool, workspace.resampling, result.resampling, params, grid);
        planOrTransferEdited = planOrTransferEdited || latentActivation.applied;
    }

    ResamplingExtractionApplyDiagnostics extractionApply{};
    ResamplingInsertionApplyDiagnostics insertionApply{};
    if (params.resamplingExtractionEnable && result.resampling.extractionPlanBuilt &&
        !workspace.resampling.passiveExtractionOperations.empty()) {
        bool handledByCudaResampling0240 = false;
        if (cuda_resampling_persistent_active_path_0240_requested(state)) {
            const CudaResamplingPersistentActivePath0240Diagnostics cudaEdit0240 =
                try_apply_cuda_resampling_persistent_active_path_0240(
                    state,
                    workspace.resamplingPool,
                    workspace.resampling,
                    result.resampling,
                    params,
                    grid,
                    extractionApply,
                    insertionApply);
            handledByCudaResampling0240 = cudaEdit0240.handled;
            planOrTransferEdited = planOrTransferEdited || cudaEdit0240.applied;
        }

        if (!handledByCudaResampling0240) {
            {
                MPCD_PROFILE_PHASE(result.profile, ResamplingExtraction);
                extractionApply =
                    apply_resampling_extraction_operations(state, workspace.resamplingPool, workspace.resampling);
            }
            planOrTransferEdited = planOrTransferEdited || extractionApply.applied;

            if (params.resamplingInsertionEnable && extractionApply.applied) {
                MPCD_PROFILE_PHASE(result.profile, ResamplingInsertion);
                insertionApply = apply_resampling_insertion_operations(
                    state, workspace.resamplingPool, workspace.resampling, grid);
                planOrTransferEdited = planOrTransferEdited || insertionApply.applied;
            }
        }
    }

    if (planOrTransferEdited) {
        {
            MPCD_PROFILE_PHASE(result.profile, ResamplingPostEditPool);
            result.resamplingPool = rebuild_resampling_particle_pool(state, workspace.resamplingPool);
        }
        {
            MPCD_PROFILE_PHASE(result.profile, ResamplingPostEditDeposit);
            result.resampling = deposit_weighted_real_fluid(
                state, params, grid, result.domain, time, GridShift{}, workspace.resampling, false,
                ResamplingDepositProfileContext::PostEdit);
        }
        {
            MPCD_PROFILE_PHASE(result.profile, ResamplingAttachFinalDiagnostics);
            attach_resampling_pool_diagnostics(result.resampling, result.resamplingPool);
        }
    }

    const bool massRenormalizationStep = is_mass_renormalization_step(params, step);
    ClosedCapacityResponseDiagnostics remapCapacity{};
    double resamplingMassCorrectionStrength = 1.0;
    double capacityRemapTargetCellMass = -1.0;
    bool massGuardAllowedByCapacity = true;
    {
        MPCD_PROFILE_PHASE(result.profile, ResamplingCapacityForRemap);
        remapCapacity = compute_closed_capacity_response_from_cell_masses(
            params, grid, result.domain, workspace.resampling.mass, nullptr, params.q6ProjectionStrength);
        resamplingMassCorrectionStrength = remapCapacity.computed ? remapCapacity.massRemapFactor : 1.0;
        capacityRemapTargetCellMass =
            (params.closedCapacityResponseEnable && remapCapacity.computed &&
             remapCapacity.overfillRatio > 0.0 &&
             remapCapacity.massRemapTargetCellMassEffective > 0.0)
                ? remapCapacity.massRemapTargetCellMassEffective
                : -1.0;
        massGuardAllowedByCapacity = !params.closedCapacityResponseEnable ||
            !params.closedCapacityMassGuardDisableOnOverfill || !(remapCapacity.overfillRatio > 0.0);
    }
    ResamplingRemapApplyDiagnostics remapApply{};
    ResamplingThermalRenormalizationDiagnostics thermalApply{};
    ResamplingMassGuardDiagnostics massGuardApply{};

    if (params.resamplingRemapEnable && massRenormalizationStep) {
        {
            MPCD_PROFILE_PHASE(result.profile, ResamplingRemap);
            remapApply = apply_resampling_local_mass_momentum_remap(
                state, workspace.resampling, result.resampling,
                resamplingMassCorrectionStrength, capacityRemapTargetCellMass);
        }
        if (params.resamplingThermalRenormalizationEnable && remapApply.applied) {
            MPCD_PROFILE_PHASE(result.profile, ResamplingThermalAfterRemap);
            thermalApply = apply_resampling_local_thermal_renormalization(
                state, workspace.resampling, remapApply);
        }
        if (params.resamplingMassGuardEnable && massGuardAllowedByCapacity && remapApply.applied) {
            MPCD_PROFILE_PHASE(result.profile, ResamplingMassGuard);
            massGuardApply = apply_resampling_particle_mass_guards(
                state, params, workspace.resampling, result.resampling,
                capacityRemapTargetCellMass);
        }
        {
            MPCD_PROFILE_PHASE(result.profile, ResamplingPostRemapDeposit);
            result.resampling = deposit_weighted_real_fluid(
                state, params, grid, result.domain, time, GridShift{}, workspace.resampling, false,
                ResamplingDepositProfileContext::PostRemap);
        }
        {
            // Remap, thermal-after-remap and particle-mass guards only update
            // masses/velocities.  Particle roles and pool membership are
            // unchanged, so the existing pool diagnostics remain valid and do
            // not need an O(Np) rebuild on every renormalization step.
            MPCD_PROFILE_PHASE(result.profile, ResamplingAttachFinalDiagnostics);
            attach_resampling_pool_diagnostics(result.resampling, result.resamplingPool);
        }
    }

    if (params.resamplingThermalRenormalizationEnable && !thermalApply.attempted) {
        install_resampling_thermal_reference(
            workspace.resampling, preEditThermalEnergyTarget, preEditThermalCell);
        const ResamplingRemapApplyDiagnostics thermalGate = make_thermal_reference_gate(preEditThermalCell);
        {
            MPCD_PROFILE_PHASE(result.profile, ResamplingThermalLate);
            thermalApply = apply_resampling_local_thermal_renormalization(
                state, workspace.resampling, thermalGate);
        }
        if (thermalApply.applied) {
            {
                MPCD_PROFILE_PHASE(result.profile, ResamplingPostThermalDeposit);
                // 0172: thermal renormalization changes velocities only.
                // Reuse the current deposit topology/classification and refresh
                // only momentum/mean-velocity fields instead of rebuilding the
                // full particle->cell deposit, candidate lists and plans.
                const WeightedResamplingDiagnostics beforePostThermalDeposit = result.resampling;
                result.resampling = refresh_weighted_real_fluid_velocity_deposit(
                    state, params, grid, result.domain, time, GridShift{}, workspace.resampling,
                    beforePostThermalDeposit, ResamplingDepositProfileContext::PostThermal);
            }
            {
                // Thermal renormalization changes velocities only; keep the
                // already valid pool/free-list diagnostics instead of rebuilding
                // them after each late thermal pass.
                MPCD_PROFILE_PHASE(result.profile, ResamplingAttachFinalDiagnostics);
                attach_resampling_pool_diagnostics(result.resampling, result.resamplingPool);
            }
        }
    }

    {
        MPCD_PROFILE_PHASE(result.profile, ResamplingAttachFinalDiagnostics);
        if (extractionApply.attempted) {
            attach_resampling_extraction_apply_diagnostics(result.resampling, extractionApply);
        }
        if (insertionApply.attempted) {
            attach_resampling_insertion_apply_diagnostics(result.resampling, insertionApply);
        }
        if (remapApply.attempted) {
            attach_resampling_remap_apply_diagnostics(result.resampling, remapApply);
        }
        if (thermalApply.attempted) {
            attach_resampling_thermal_renormalization_diagnostics(result.resampling, thermalApply);
        }
        if (massGuardApply.attempted) {
            attach_resampling_mass_guard_diagnostics(result.resampling, massGuardApply);
        }
        if (latentActivation.attempted) {
            attach_resampling_latent_activation_diagnostics(result.resampling, latentActivation);
        }
        if (populationGuard.attempted) {
            attach_resampling_population_guard_diagnostics(result.resampling, populationGuard);
        }
    }
    return result;
}

} // namespace mpcd
