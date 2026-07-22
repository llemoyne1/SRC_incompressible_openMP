#include "src_mpcd_base.h"
#include "closed_capacity_response.h"
#include "cuda_resampling_persistent_active_path_0240.h"
#include "cuda_streaming_periodic_0245.h"
#include "cuda_streaming_wall_simple_0246.h"
#include "cuda_streaming_piston_0247b.h"
#include "cuda_immersed_rectangle_0247.h"
#include "cuda_immersed_circle_0284.h"
#include "cuda_inlet_outlet_fullface_0249a.h"
#include "cuda_inlet_outlet_segmented_0249b.h"
#include "cuda_shared_particle_state_0251.h"
#include "cuda_classic_src_io_resident_0263.h"
#include "cuda_resampling_support_survey_0295.h"
#include "cuda_resampling_adaptive_flag_0304.h"
#include "cuda_resampling_mass_recondition_0296.h"
#include "cuda_resampling_population_guard_0297.h"
#include "cuda_resampling_pipeline_shadow_0445.h"
#include "cuda_darcy_brinkman_0343.h"
#include "cuda_q6_resident_0400.h"

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
#include <stdexcept>
#include <string>
#include <vector>


namespace mpcd {
namespace {

bool env_truthy_src_base_0475a(const char* name) {
    const char* v = std::getenv(name);
    if (v == nullptr || v[0] == '\0') return false;
    const char c0 = v[0];
    if (c0 == '0' || c0 == 'f' || c0 == 'F' || c0 == 'n' || c0 == 'N') return false;
    return true;
}

} // namespace


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


bool env_truthy_0270(const char* name) {
    const char* v = std::getenv(name);
    if (v == nullptr || *v == '\0') {
        return false;
    }
    const std::string s(v);
    return !(s == "0" || s == "false" || s == "FALSE" ||
             s == "off" || s == "OFF" || s == "no" || s == "NO");
}

// 0401/0402: experimental resident chains for incompressible Q6 paths.
// They deliberately do not set srcClassicCudaModeEnable, because that runtime
// switch means "short-circuit Q6" in the validated parameter semantics.
bool cuda_q6_resident_src_step_0401_requested() {
    return env_truthy_0270("MPCD_CUDA_Q6_RESIDENT_SRC_STEP_0401");
}

bool cuda_q6_resident_src_wall_step_0402_requested() {
    return env_truthy_0270("MPCD_CUDA_Q6_RESIDENT_SRC_WALL_STEP_0402");
}

bool cuda_q6_resident_src_io_fullface_0404_requested() {
    return env_truthy_0270("MPCD_CUDA_Q6_RESIDENT_SRC_IO_FULLFACE_0404");
}

bool cuda_q6_resident_src_io_segmented_0409_requested() {
    return env_truthy_0270("MPCD_CUDA_Q6_RESIDENT_SRC_IO_SEGMENTED_0409");
}

bool cuda_q6_resident_src_common_0401_supported(const SimulationParams& params) {
    return !params.srcClassicCudaModeEnable &&
           params.projectionEnable && params.projectionBackend == "cuda" &&
           env_truthy_0270("MPCD_CUDA_Q6_RESIDENT_0400") &&
           env_truthy_0270("MPCD_CUDA_PERSISTENT_SRC_COLLISION_USE") &&
           env_truthy_0270("MPCD_CUDA_PERSISTENT_SRC_COLLISION_SHARED_0251") &&
           !params.openBoundarySegmentsEnable && params.openBoundarySegmentCount == 0 &&
           !params.immersedSolidEnable &&
           !params.closedCapacityResponseEnable && !params.closedCapacityVirialKickEnable &&
           params.fluidXMinVelocity == 0.0 && params.fluidXMaxVelocity == 0.0 &&
           params.fluidYMinVelocity == 0.0 && params.fluidYMaxVelocity == 0.0;
}

bool cuda_q6_resident_src_step_0401_supported(const SimulationParams& params) {
    return cuda_q6_resident_src_step_0401_requested() &&
           cuda_q6_resident_src_common_0401_supported(params) &&
           env_truthy_0270("MPCD_CUDA_STREAMING_PERIODIC_0245") &&
           env_truthy_0270("MPCD_CUDA_CLASSIC_SRC_PERIODIC_RESIDENT_0260") &&
           params.bcLeft == "periodic" && params.bcRight == "periodic" &&
           params.bcBottom == "periodic" && params.bcTop == "periodic";
}

bool cuda_q6_resident_src_wall_step_0402_supported(const SimulationParams& params) {
    return cuda_q6_resident_src_wall_step_0402_requested() &&
           cuda_q6_resident_src_common_0401_supported(params) &&
           env_truthy_0270("MPCD_CUDA_STREAMING_WALL_SIMPLE_0246") &&
           env_truthy_0270("MPCD_CUDA_CLASSIC_SRC_WALL_RESIDENT_0261") &&
           params.bcLeft == "periodic" && params.bcRight == "periodic" &&
           (params.bcBottom == "solid" || params.bcBottom == "specular" || params.bcBottom == "bounceback") &&
           (params.bcTop == "solid" || params.bcTop == "specular" || params.bcTop == "bounceback") &&
           (params.projectionOperator == "channel_fv_cg" || params.projectionOperator == "auto_fv_cg" ||
            params.projectionOperator == "elliptic_fv_cg");
}

bool cuda_q6_wall_like_0409(const std::string& bc) {
    return bc == "solid" || bc == "specular" || bc == "bounceback";
}

bool hard_inlet_reservoir_requested_0435d(const SimulationParams& params) {
    std::string mode = params.inletReservoirMode;
    std::replace(mode.begin(), mode.end(), '-', '_');
    if (mode.empty() || mode == "default") {
        mode = params.inletInjectionMode;
        std::replace(mode.begin(), mode.end(), '-', '_');
    }
    return mode == "hard_cell_density" || mode == "hard_density" ||
           mode == "hard" || mode == "cell_density";
}

bool cuda_q6_resident_src_io_fullface_0404_supported(const SimulationParams& params) {
    const bool leftInlet = params.bcLeft == "inlet";
    const bool rightInlet = params.bcRight == "inlet";
    const bool bottomInlet = params.bcBottom == "inlet";
    const bool topInlet = params.bcTop == "inlet";
    const bool leftOutlet = params.bcLeft == "outlet";
    const bool rightOutlet = params.bcRight == "outlet";
    const bool bottomOutlet = params.bcBottom == "outlet";
    const bool topOutlet = params.bcTop == "outlet";
    const bool xPair = ((leftInlet && rightOutlet) || (leftOutlet && rightInlet)) &&
                       cuda_q6_wall_like_0409(params.bcBottom) && cuda_q6_wall_like_0409(params.bcTop);
    const bool yPair = ((bottomInlet && topOutlet) || (bottomOutlet && topInlet)) &&
                       cuda_q6_wall_like_0409(params.bcLeft) && cuda_q6_wall_like_0409(params.bcRight);
    return cuda_q6_resident_src_io_fullface_0404_requested() &&
           cuda_q6_resident_src_common_0401_supported(params) &&
           env_truthy_0270("MPCD_CUDA_CLASSIC_SRC_IO_FULLFACE_RESIDENT_0263") &&
           (xPair || yPair) &&
           params.inletReservoirMode == "hard_cell_density" &&
           params.inletInjectionMode == "hard_cell_density" &&
           params.inletVelocitySpatialProfile == "uniform" &&
           (params.openBoundaryOutletMode == "balanced_flux" || params.openBoundaryOutletMode == "balanced") &&
           (params.projectionOperator == "elliptic_fv_cg" || params.projectionOperator == "auto_fv_cg");
}

bool cuda_q6_resident_src_io_segmented_0409_supported(const SimulationParams& params) {
    const bool base = !params.srcClassicCudaModeEnable &&
        params.projectionEnable && params.projectionBackend == "cuda" &&
        env_truthy_0270("MPCD_CUDA_Q6_RESIDENT_0400") &&
        env_truthy_0270("MPCD_CUDA_PERSISTENT_SRC_COLLISION_USE") &&
        env_truthy_0270("MPCD_CUDA_PERSISTENT_SRC_COLLISION_SHARED_0251") &&
        !params.immersedSolidEnable &&
        !params.closedCapacityResponseEnable && !params.closedCapacityVirialKickEnable &&
        params.fluidXMinVelocity == 0.0 && params.fluidXMaxVelocity == 0.0 &&
        params.fluidYMinVelocity == 0.0 && params.fluidYMaxVelocity == 0.0;
    return cuda_q6_resident_src_io_segmented_0409_requested() && base &&
           env_truthy_0270("MPCD_CUDA_CLASSIC_SRC_IO_SEGMENTED_RESIDENT_0264") &&
           params.openBoundarySegmentsEnable && params.openBoundarySegmentCount > 0 &&
           cuda_q6_wall_like_0409(params.bcLeft) && cuda_q6_wall_like_0409(params.bcRight) &&
           cuda_q6_wall_like_0409(params.bcBottom) && cuda_q6_wall_like_0409(params.bcTop) &&
           params.inletReservoirMode == "hard_cell_density" &&
           params.inletInjectionMode == "hard_cell_density" &&
           params.inletVelocitySpatialProfile == "uniform" &&
           (params.openBoundaryOutletMode == "neumann" || params.openBoundaryOutletMode == "balanced_flux" ||
            params.openBoundaryOutletMode == "balanced" || params.openBoundaryOutletMode == "hybrid") &&
           (params.projectionOperator == "elliptic_fv_cg" || params.projectionOperator == "auto_fv_cg");
}

bool cuda_q6_resident_src_any_step_0401_supported(const SimulationParams& params) {
    return cuda_q6_resident_src_step_0401_supported(params) ||
           cuda_q6_resident_src_wall_step_0402_supported(params) ||
           cuda_q6_resident_src_io_fullface_0404_supported(params) ||
           cuda_q6_resident_src_io_segmented_0409_supported(params);
}

// 0315e: after CUDA inlet/outlet active-prefix compaction, the shared GPU
// particle state can remain authoritative provided every immediately downstream
// consumer also consumes that shared state.  This helper is intentionally
// conservative: when it cannot prove that collision + thermostat are handled by
// the validated persistent shared CUDA path, the caller synchronizes only the
// active host prefix before continuing.  Summary/dump synchronization remains
// lazy and is handled separately through cuda_shared_particle_state_0251_*.
bool cuda_src_classic_shared_collision_thermostat_pipeline_0315e(const SimulationParams& params,
                                                                const CellGrid& grid,
                                                                const FluidDomainBounds& domain,
                                                                std::uint64_t step) {
    (void)grid;
    (void)domain;
    if (!params.srcClassicCudaModeEnable) {
        return false;
    }
    if (params.projectionEnable ||
        params.closedCapacityResponseEnable || params.closedCapacityVirialKickEnable) {
        return false;
    }
    if (!env_truthy_0270("MPCD_CUDA_PERSISTENT_SRC_COLLISION_USE") ||
        !env_truthy_0270("MPCD_CUDA_PERSISTENT_SRC_COLLISION_SHARED_0251")) {
        return false;
    }
    if (!cuda_shared_particle_state_0251_is_fresh()) {
        return false;
    }

    // If the physical thermostat is due on this step, it must be consumed by the
    // fused persistent SRC+thermostat shared-state path.  Otherwise
    // apply_cell_relative_rescale_thermostat() may perform a host-side deposit.
    if (params.thermostatEnable) {
        if (params.thermostatEvery <= 0) {
            return false;
        }
        const bool thermostatDue =
            (step % static_cast<std::uint64_t>(params.thermostatEvery)) == 0u;
        if (thermostatDue) {
            if (params.thermostatMode != "cell_relative_rescale") {
                return false;
            }
            if (!env_truthy_0270("MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_USE") ||
                !env_truthy_0270("MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_SHARED_0251_0260")) {
                return false;
            }
        }
    }

    // Mean-flow correction is still a CPU particle pass.
    if (params.keepMeanFlowEnable) {
        return false;
    }
    return true;
}

bool cuda_immersed_solid_is_handled_on_device_0315e(const SimulationParams& params) {
    if (!immersed_solid_enabled(params)) {
        return true;
    }
    const ImmersedSolidShape shape = immersed_solid_shape(params);
    if (shape == ImmersedSolidShape::Rectangle) {
        return cuda_immersed_rectangle_0247_requested();
    }
    if (shape == ImmersedSolidShape::Circle) {
        return cuda_immersed_circle_0284_requested();
    }
    return false;
}

bool cuda_io_boundary_requires_active_host_prefix_sync_0315e(const SimulationParams& params,
                                                            const CellGrid& grid,
                                                            const FluidDomainBounds& domain,
                                                            std::uint64_t step,
                                                            bool collectResamplingDiagnosticsWhenDisabled) {
    // Explicit override for all-GPU experiments.  Unsafe unless all downstream
    // consumers are known to be device/shared-state consumers.
    if (env_truthy_0270("MPCD_CUDA_ACTIVE_PREFIX_ASSUME_NO_HOST_CONSUMERS_0315D")) {
        return false;
    }

    if (!cuda_immersed_solid_is_handled_on_device_0315e(params)) {
        return true;
    }
    if (!cuda_src_classic_shared_collision_thermostat_pipeline_0315e(params, grid, domain, step)) {
        return true;
    }

    // Q6/capacity are immediate host particle consumers in the current mixed
    // pipeline. Resampling is synchronized later at its own insertion point.
    if (params.projectionEnable || params.closedCapacityResponseEnable ||
        params.closedCapacityVirialKickEnable) {
        return true;
    }

    // Disabled-resampling diagnostics are summary-only and already synchronize
    // lazily just before rebuild_resampling_particle_pool()/deposit below. Do
    // not pay this cost every step merely because a future summary may need it.
    (void)collectResamplingDiagnosticsWhenDisabled;
    return false;
}




bool cuda_io_resident_state_is_device_fresh_0315f(bool residentClassicIo0263,
                                                  bool residentClassicIo0264) {
    return (residentClassicIo0263 || residentClassicIo0264) &&
           cuda_shared_particle_state_0251_is_fresh();
}

void cuda_io_sync_active_prefix_before_host_consumer_0315f(ParticleState& state,
                                                           bool residentClassicIo0263,
                                                           bool residentClassicIo0264,
                                                           const char* /*reason*/) {
    if (!cuda_io_resident_state_is_device_fresh_0315f(residentClassicIo0263, residentClassicIo0264)) {
        return;
    }
    // 0315f: keep this as an active-prefix download only.  It repairs the
    // remaining mixed host/device consumers without returning to the 0315b-fix02
    // full download -> host compact -> upload cycle, and without scanning the
    // inactive reservoir.
    (void)cuda_shared_particle_state_0251_download_if_fresh(state);
}

void cuda_classic_resident_sync_active_prefix_before_host_consumer_0334(
    ParticleState& state,
    bool residentClassicCuda,
    const char* /*reason*/) {
    if (!residentClassicCuda || !cuda_shared_particle_state_0251_is_fresh()) {
        return;
    }
    // 0334a: the same mixed host/device safety rule is needed beyond IO.  A
    // periodic/wall/IO resident stream may leave the host mirror stale; if a
    // downstream CPU fallback is selected, synchronize only the active prefix
    // before that fallback and do not scan/download the inactive reservoir.
    (void)cuda_shared_particle_state_0251_download_if_fresh(state);
}

bool cuda_collision_wrapper_still_needs_host_particles_0315f(const SimulationParams& params,
                                                             const CellGrid& /*grid*/,
                                                             const FluidDomainBounds& /*domain*/,
                                                             std::uint64_t step) {
    // The persistent SRC collision kernels can consume the shared 0251 device
    // state, but the current wrapper still passes ParticleState into the CUDA
    // call for sizing/metadata/diagnostic side inputs.  The 0401/0402 Q6 paths
    // are explicitly constrained to shared-0251 collision, so they may keep host
    // kinematics stale between steps.
    const bool q6ResidentSrc = cuda_q6_resident_src_any_step_0401_supported(params);
    if (!params.srcClassicCudaModeEnable && !q6ResidentSrc) {
        return true;
    }
    if (!env_truthy_0270("MPCD_CUDA_PERSISTENT_SRC_COLLISION_USE") ||
        !env_truthy_0270("MPCD_CUDA_PERSISTENT_SRC_COLLISION_SHARED_0251")) {
        return true;
    }
    if (params.thermostatEnable && params.thermostatEvery > 0) {
        const bool thermostatDue =
            (step % static_cast<std::uint64_t>(params.thermostatEvery)) == 0u;
        if (thermostatDue) {
            // If the thermostat is not fused/consumed by the persistent SRC
            // collision, apply_cell_relative_rescale_thermostat() performs a
            // host-side deposit before any CUDA active thermostat path.
            if (!env_truthy_0270("MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_USE") ||
                !env_truthy_0270("MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_SHARED_0251_0260")) {
                return true;
            }
        }
    }
    return env_truthy_0270("MPCD_CUDA_COLLISION_WRAPPER_HOST_SYNC_0315F");
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
    const bool immersedOk =
        !params.immersedSolidEnable || cuda_immersed_solid_is_handled_on_device_0315e(params);
    return params.srcClassicCudaModeEnable &&
           params.bcLeft == "periodic" && params.bcRight == "periodic" &&
           params.bcBottom == "periodic" && params.bcTop == "periodic" &&
           !params.openBoundarySegmentsEnable && params.openBoundarySegmentCount == 0 &&
           immersedOk &&
           !params.projectionEnable &&
           !params.closedCapacityResponseEnable;
}

bool cuda_classic_src_periodic_resident_0260_active(const SimulationParams& params) {
    return (cuda_classic_src_periodic_resident_0260_requested() &&
            cuda_classic_src_periodic_resident_0260_supported(params)) ||
           cuda_q6_resident_src_step_0401_supported(params);
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
    const bool thermostatHandledOnShared0251 =
        !params.thermostatEnable ||
        (params.thermostatEvery > 0 &&
         params.thermostatMode == "cell_relative_rescale" &&
         env_truthy_0270("MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_USE") &&
         env_truthy_0270("MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_SHARED_0251_0260"));
    return params.srcClassicCudaModeEnable &&
           params.bcLeft == "periodic" && params.bcRight == "periodic" &&
           (params.bcBottom == "solid" || params.bcBottom == "specular" || params.bcBottom == "bounceback") &&
           (params.bcTop == "solid" || params.bcTop == "specular" || params.bcTop == "bounceback") &&
           !params.openBoundarySegmentsEnable && params.openBoundarySegmentCount == 0 &&
           !params.immersedSolidEnable &&
           !params.projectionEnable &&
           !params.closedCapacityResponseEnable &&
           thermostatHandledOnShared0251 &&
           params.fluidXMinVelocity == 0.0 && params.fluidXMaxVelocity == 0.0 &&
           params.fluidYMinVelocity == 0.0 && params.fluidYMaxVelocity == 0.0;
}

bool cuda_classic_src_wall_resident_0261_active(const SimulationParams& params) {
    return (cuda_classic_src_wall_resident_0261_requested() &&
            cuda_classic_src_wall_resident_0261_supported(params)) ||
           cuda_q6_resident_src_wall_step_0402_supported(params);
}


bool cuda_classic_src_wall_circle_resident_0318_requested() {
    return env_truthy_0270("MPCD_CUDA_CLASSIC_SRC_WALL_CIRCLE_RESIDENT_0318");
}

bool cuda_classic_src_wall_circle_resident_0318_supported(const SimulationParams& params) {
    if (!env_truthy_0270("MPCD_CUDA_CLASSIC_SRC_WALL_CIRCLE_RESIDENT_0318_UNSAFE_ENABLE")) {
        return false;
    }
    return params.srcClassicCudaModeEnable &&
           params.bcLeft == "periodic" && params.bcRight == "periodic" &&
           (params.bcBottom == "solid" || params.bcBottom == "specular" || params.bcBottom == "bounceback") &&
           (params.bcTop == "solid" || params.bcTop == "specular" || params.bcTop == "bounceback") &&
           !params.openBoundarySegmentsEnable && params.openBoundarySegmentCount == 0 &&
           params.immersedSolidEnable &&
           immersed_solid_shape(params) == ImmersedSolidShape::Circle &&
           params.immersedSolidVx == 0.0 && params.immersedSolidVy == 0.0 && params.immersedSolidOmega == 0.0 &&
           !params.projectionEnable &&
           !params.closedCapacityResponseEnable &&
           params.fluidXMinVelocity == 0.0 && params.fluidXMaxVelocity == 0.0 &&
           params.fluidYMinVelocity == 0.0 && params.fluidYMaxVelocity == 0.0;
}

bool cuda_classic_src_wall_circle_resident_0318_active(const SimulationParams& params) {
    return cuda_classic_src_wall_circle_resident_0318_requested() &&
           cuda_classic_src_wall_circle_resident_0318_supported(params);
}


bool cuda_classic_src_solid_resident_0262_requested() {
    const char* v = std::getenv("MPCD_CUDA_CLASSIC_SRC_SOLID_RESIDENT_0262");
    if (v == nullptr || *v == '\0') {
        return false;
    }
    const std::string s(v);
    return !(s == "0" || s == "false" || s == "FALSE" ||
             s == "off" || s == "OFF" || s == "no" || s == "NO");
}

bool cuda_classic_src_solid_resident_0262_supported(const SimulationParams& params) {
    return params.srcClassicCudaModeEnable &&
           params.bcLeft == "periodic" && params.bcRight == "periodic" &&
           params.bcBottom == "periodic" && params.bcTop == "periodic" &&
           !params.openBoundarySegmentsEnable && params.openBoundarySegmentCount == 0 &&
           params.immersedSolidEnable &&
           immersed_solid_shape(params) == ImmersedSolidShape::Rectangle &&
           params.immersedSolidVx == 0.0 && params.immersedSolidVy == 0.0 && params.immersedSolidOmega == 0.0 &&
           !params.projectionEnable &&
           !params.closedCapacityResponseEnable &&
           !params.thermostatEnable &&
           params.fluidXMinVelocity == 0.0 && params.fluidXMaxVelocity == 0.0 &&
           params.fluidYMinVelocity == 0.0 && params.fluidYMaxVelocity == 0.0;
}

bool cuda_classic_src_solid_resident_0262_active(const SimulationParams& params) {
    return cuda_classic_src_solid_resident_0262_requested() &&
           cuda_classic_src_solid_resident_0262_supported(params);
}

bool cuda_classic_src_io_fullface_resident_0263_active(const SimulationParams& params) {
    return (cuda_classic_src_io_fullface_resident_0263_requested() &&
            cuda_classic_src_io_fullface_resident_0263_supported(params)) ||
           cuda_q6_resident_src_io_fullface_0404_supported(params);
}

bool cuda_classic_src_io_segmented_resident_0264_active(const SimulationParams& params) {
    return (cuda_classic_src_io_segmented_resident_0264_requested() &&
            cuda_classic_src_io_segmented_resident_0264_supported(params)) ||
           cuda_q6_resident_src_io_segmented_0409_supported(params);
}



bool cuda_resident_profile_0266_enabled() {
    static const bool enabled = []() {
        const char* v = std::getenv("MPCD_CUDA_RESIDENT_PROFILE_0266");
        if (v != nullptr && *v != '\0') {
            const std::string s(v);
            return !(s == "0" || s == "false" || s == "FALSE" ||
                     s == "off" || s == "OFF" || s == "no" || s == "NO");
        }
        return internal_profiles_enabled_0176();
    }();
    return enabled;
}

struct CudaResidentProfileRow0266 {
    std::uint64_t step = 0u;
    std::string mode;
    std::string phase;
    int requested = 0;
    int supported = 0;
    int handled = 0;
    int applied = 0;
    std::uint64_t particles = 0u;
    std::uint64_t fluidParticles = 0u;
    std::uint64_t allocationCalls = 0u;
    std::uint64_t uploadCalls = 0u;
    std::uint64_t downloadCalls = 0u;
    double uploadSeconds = 0.0;
    double kernelSeconds = 0.0;
    double downloadSeconds = 0.0;
    double totalSeconds = 0.0;
    std::uint64_t hitsBottom = 0u;
    std::uint64_t hitsTop = 0u;
    std::uint64_t immersedHits = 0u;
    int maxReflections = 0;
    std::uint64_t inletReservoirCells = 0u;
    std::uint64_t inletReservoirTargetParticles = 0u;
    std::uint64_t inletReservoirDeleted = 0u;
    std::uint64_t inletBackflowDeleted = 0u;
    std::uint64_t outletParticlesDeleted = 0u;
    std::uint64_t inletParticlesInserted = 0u;
    std::int64_t inletNetParticleDelta = 0;
};

class CudaResidentProfileAccumulator0266 {
public:
    void set_output_dir(const std::string& dir) {
        if (!dir.empty()) outputDir_ = dir;
    }

    void add(const CudaResidentProfileRow0266& row) {
        if (!cuda_resident_profile_0266_enabled()) return;
        rows_.push_back(row);
    }

    ~CudaResidentProfileAccumulator0266() {
        if (!cuda_resident_profile_0266_enabled() || outputDir_.empty() || rows_.empty()) return;
        std::error_code ec;
        std::filesystem::create_directories(outputDir_, ec);
        const std::filesystem::path path = std::filesystem::path(outputDir_) / "cuda_resident_phase_profile_0266.csv";
        std::ofstream out(path);
        if (!out) return;
        out << std::setprecision(17);
        out << "step,mode,phase,requested,supported,handled,applied,particles,fluidParticles,allocationCalls,uploadCalls,downloadCalls,uploadSeconds,kernelSeconds,downloadSeconds,totalSeconds,hitsBottom,hitsTop,immersedHits,maxReflections,inletReservoirCells,inletReservoirTargetParticles,inletReservoirDeleted,inletBackflowDeleted,outletParticlesDeleted,inletParticlesInserted,inletNetParticleDelta\n";
        for (const auto& r : rows_) {
            out << r.step << ',' << r.mode << ',' << r.phase << ','
                << r.requested << ',' << r.supported << ',' << r.handled << ',' << r.applied << ','
                << r.particles << ',' << r.fluidParticles << ','
                << r.allocationCalls << ',' << r.uploadCalls << ',' << r.downloadCalls << ','
                << r.uploadSeconds << ',' << r.kernelSeconds << ',' << r.downloadSeconds << ',' << r.totalSeconds << ','
                << r.hitsBottom << ',' << r.hitsTop << ',' << r.immersedHits << ',' << r.maxReflections << ','
                << r.inletReservoirCells << ',' << r.inletReservoirTargetParticles << ','
                << r.inletReservoirDeleted << ',' << r.inletBackflowDeleted << ','
                << r.outletParticlesDeleted << ',' << r.inletParticlesInserted << ','
                << r.inletNetParticleDelta << '\n';
        }
    }

private:
    std::string outputDir_;
    std::vector<CudaResidentProfileRow0266> rows_;
};

CudaResidentProfileAccumulator0266& cuda_resident_profile_accumulator_0266() {
    static CudaResidentProfileAccumulator0266 acc;
    return acc;
}

CudaResidentProfileRow0266 make_cuda_resident_profile_row_0266(std::uint64_t step,
                                                                const char* mode,
                                                                const char* phase) {
    CudaResidentProfileRow0266 row{};
    row.step = step;
    row.mode = mode != nullptr ? mode : "unknown";
    row.phase = phase != nullptr ? phase : "unknown";
    return row;
}

void record_cuda_resident_profile_0266(const std::string& outputDir,
                                       std::uint64_t step,
                                       const char* mode,
                                       const char* phase,
                                       const CudaPeriodicStreaming0245Diagnostics& d) {
    auto row = make_cuda_resident_profile_row_0266(step, mode, phase);
    row.requested = d.requested ? 1 : 0;
    row.supported = d.supported ? 1 : 0;
    row.handled = d.handled ? 1 : 0;
    row.applied = d.applied ? 1 : 0;
    row.particles = d.particles;
    row.fluidParticles = d.fluidParticles;
    row.allocationCalls = d.allocationCalls;
    row.uploadCalls = d.uploadCalls;
    row.downloadCalls = d.downloadCalls;
    row.uploadSeconds = d.uploadSeconds;
    row.kernelSeconds = d.kernelSeconds;
    row.downloadSeconds = d.downloadSeconds;
    row.totalSeconds = d.totalSeconds;
    auto& acc = cuda_resident_profile_accumulator_0266();
    acc.set_output_dir(outputDir);
    acc.add(row);
}

void record_cuda_resident_profile_0266(const std::string& outputDir,
                                       std::uint64_t step,
                                       const char* mode,
                                       const char* phase,
                                       const CudaWallSimpleStreaming0246Diagnostics& d) {
    auto row = make_cuda_resident_profile_row_0266(step, mode, phase);
    row.requested = d.requested ? 1 : 0;
    row.supported = d.supported ? 1 : 0;
    row.handled = d.handled ? 1 : 0;
    row.applied = d.applied ? 1 : 0;
    row.particles = d.particles;
    row.fluidParticles = d.fluidParticles;
    row.allocationCalls = d.allocationCalls;
    row.uploadCalls = d.uploadCalls;
    row.downloadCalls = d.downloadCalls;
    row.uploadSeconds = d.uploadSeconds;
    row.kernelSeconds = d.kernelSeconds;
    row.downloadSeconds = d.downloadSeconds;
    row.totalSeconds = d.totalSeconds;
    row.hitsBottom = d.hitsBottom;
    row.hitsTop = d.hitsTop;
    row.maxReflections = d.maxYWallReflectionsPerParticle;
    auto& acc = cuda_resident_profile_accumulator_0266();
    acc.set_output_dir(outputDir);
    acc.add(row);
}

void record_cuda_resident_profile_0266(const std::string& outputDir,
                                       std::uint64_t step,
                                       const char* mode,
                                       const char* phase,
                                       const CudaPistonStreaming0247bDiagnostics& d) {
    auto row = make_cuda_resident_profile_row_0266(step, mode, phase);
    row.requested = d.requested ? 1 : 0;
    row.supported = d.supported ? 1 : 0;
    row.handled = d.handled ? 1 : 0;
    row.applied = d.applied ? 1 : 0;
    row.particles = d.particles;
    row.fluidParticles = d.fluidParticles;
    row.allocationCalls = d.allocationCalls;
    row.uploadCalls = d.uploadCalls;
    row.downloadCalls = d.downloadCalls;
    row.uploadSeconds = d.uploadSeconds;
    row.kernelSeconds = d.kernelSeconds;
    row.downloadSeconds = d.downloadSeconds;
    row.totalSeconds = d.totalSeconds;
    row.hitsBottom = d.hitsBottom;
    row.hitsTop = d.hitsTop;
    row.maxReflections = d.maxYWallReflectionsPerParticle;
    auto& acc = cuda_resident_profile_accumulator_0266();
    acc.set_output_dir(outputDir);
    acc.add(row);
}

void record_cuda_resident_profile_0266(const std::string& outputDir,
                                       std::uint64_t step,
                                       const char* mode,
                                       const char* phase,
                                       const CudaImmersedRectangle0247Diagnostics& d) {
    auto row = make_cuda_resident_profile_row_0266(step, mode, phase);
    row.requested = d.requested ? 1 : 0;
    row.supported = d.supported ? 1 : 0;
    row.handled = d.handled ? 1 : 0;
    row.applied = d.applied ? 1 : 0;
    row.particles = d.particles;
    row.fluidParticles = d.fluidParticles;
    row.allocationCalls = d.allocationCalls;
    row.uploadCalls = d.uploadCalls;
    row.downloadCalls = d.downloadCalls;
    row.uploadSeconds = d.uploadSeconds;
    row.kernelSeconds = d.kernelSeconds;
    row.downloadSeconds = d.downloadSeconds;
    row.totalSeconds = d.totalSeconds;
    row.immersedHits = d.hits;
    auto& acc = cuda_resident_profile_accumulator_0266();
    acc.set_output_dir(outputDir);
    acc.add(row);
}

void record_cuda_resident_profile_0266(const std::string& outputDir,
                                       std::uint64_t step,
                                       const char* mode,
                                       const char* phase,
                                       const CudaImmersedCircle0284Diagnostics& d) {
    auto row = make_cuda_resident_profile_row_0266(step, mode, phase);
    row.requested = d.requested ? 1 : 0;
    row.supported = d.supported ? 1 : 0;
    row.handled = d.handled ? 1 : 0;
    row.applied = d.applied ? 1 : 0;
    row.particles = d.particles;
    row.fluidParticles = d.fluidParticles;
    row.allocationCalls = d.allocationCalls;
    row.uploadCalls = d.uploadCalls;
    row.downloadCalls = d.downloadCalls;
    row.uploadSeconds = d.uploadSeconds;
    row.kernelSeconds = d.kernelSeconds;
    row.downloadSeconds = d.downloadSeconds;
    row.totalSeconds = d.totalSeconds;
    row.immersedHits = d.hits;
    auto& acc = cuda_resident_profile_accumulator_0266();
    acc.set_output_dir(outputDir);
    acc.add(row);
}

void record_cuda_resident_profile_0266(const std::string& outputDir,
                                       std::uint64_t step,
                                       const char* mode,
                                       const char* phase,
                                       const CudaClassicSrcIoResident0263Diagnostics& d) {
    auto row = make_cuda_resident_profile_row_0266(step, mode, phase);
    row.requested = d.requested ? 1 : 0;
    row.supported = d.supported ? 1 : 0;
    row.handled = d.handled ? 1 : 0;
    row.applied = d.applied ? 1 : 0;
    row.particles = d.particles;
    row.fluidParticles = d.fluidParticles;
    row.allocationCalls = d.allocationCalls;
    row.uploadCalls = d.uploadCalls;
    row.downloadCalls = d.downloadCalls;
    row.uploadSeconds = d.uploadSeconds;
    row.kernelSeconds = d.kernelSeconds;
    row.downloadSeconds = d.downloadSeconds;
    row.totalSeconds = d.totalSeconds;
    row.hitsBottom = d.boundary.hitsBottom;
    row.hitsTop = d.boundary.hitsTop;
    row.maxReflections = d.boundary.maxYWallReflectionsPerParticle;
    row.inletReservoirCells = d.boundary.inletReservoirCells;
    row.inletReservoirTargetParticles = d.boundary.inletReservoirTargetParticles;
    row.inletReservoirDeleted = d.boundary.inletReservoirDeleted;
    row.inletBackflowDeleted = d.boundary.inletBackflowDeleted;
    row.outletParticlesDeleted = d.boundary.outletParticlesDeleted;
    row.inletParticlesInserted = d.boundary.inletParticlesInserted;
    row.inletNetParticleDelta = d.boundary.inletNetParticleDelta;
    auto& acc = cuda_resident_profile_accumulator_0266();
    acc.set_output_dir(outputDir);
    acc.add(row);
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
    const std::size_t nActiveThermalRef = active_fluid_count_size(state);
    for (std::size_t i = 0; i < nActiveThermalRef; ++i) {
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
            if (active_fluid_count(state) < minParticles) {
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
    const std::size_t n = active_fluid_count_size(state);

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

void rebuild_active_cell_ids_0431(const ParticleState& state,
                                  const SimulationParams& params,
                                  const CellGrid& grid,
                                  const GridShift& shift,
                                  std::vector<int>& cellId) {
    const std::size_t n = active_fluid_count_size(state);
    cellId.assign(n, -1);
#pragma omp parallel for if(n > 10000)
    for (std::int64_t ii = 0; ii < static_cast<std::int64_t>(n); ++ii) {
        const std::size_t i = static_cast<std::size_t>(ii);
        if (!is_fluid_particle(state, i)) {
            continue;
        }
        cellId[i] = cell_index_from_position(state.x[i], state.y[i], grid, shift, params);
    }
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
    const bool residentClassicSolid0262 = cuda_classic_src_solid_resident_0262_active(params);
    const bool residentClassicWallCircle0318 = cuda_classic_src_wall_circle_resident_0318_active(params);
    const bool residentClassicIo0263 = cuda_classic_src_io_fullface_resident_0263_active(params);
    const bool residentClassicIo0264 = cuda_classic_src_io_segmented_resident_0264_active(params);
    const bool residentClassicCuda = residentClassicPeriodic0260 || residentClassicWall0261 ||
                                     residentClassicSolid0262 || residentClassicWallCircle0318 ||
                                     residentClassicIo0263 || residentClassicIo0264;
    if (!residentClassicCuda || !cuda_shared_particle_state_0251_is_fresh()) {
        cuda_shared_particle_state_0251_invalidate("start_step_cpu_state_authoritative");
    }
    const std::size_t n = active_fluid_count_size(state);
    const std::uint64_t nActiveFluid = static_cast<std::uint64_t>(n);
    const double time = static_cast<double>(step) * params.dt;

    // 0270: wall-simple resident CUDA performs y-wall reflection directly in
    // the force/stream kernel.  The generic CPU boundary pass is therefore a
    // redundant full particle scan for the validated Poiseuille wall subset.
    // Keep this as a per-step fact rather than a global guard so future Q6,
    // resampling or thermostat reactivation can still force explicit
    // host/device synchronization where needed.
    bool wallSimpleResidentStreamHandled0270 = false;
    bool periodicFusedStreamHandled0274 = false;
    bool periodicResidentStreamHandled0334 = false;
    BoundaryDiagnostics cudaWallResidentBoundaryDiagnostics0270{};
    bool cudaWallResidentBoundaryDiagnosticsValid0270 = false;

    // Uniform and optional Taylor--Green body acceleration, then free streaming
    // in the fixed numerical box. Taylor--Green forcing is evaluated at the
    // pre-stream particle position. CUDA offloads are enabled only for explicitly
    // validated boundary subsets: 0245 periodic, 0246 static y-walls, 0247b
    // moving-y-wall piston. All unsupported cases fall back to the CPU path.
    {
        MPCD_PROFILE_PHASE(result.profile, ForceStream);
        bool handledByCudaStreaming = false;
        if (residentClassicIo0264) {
            const FluidDomainBounds streamDomain = make_fluid_domain_bounds(params, time);
            const CudaClassicSrcIoResident0263Diagnostics cudaIoStream0264 =
                try_apply_cuda_classic_src_io_segmented_stream_0264(state, params, streamDomain, step);
            record_cuda_resident_profile_0266(params.outputDir, step, "io_segmented_0264", "force_stream", cudaIoStream0264);
            handledByCudaStreaming = cudaIoStream0264.handled;
        }
        if (!handledByCudaStreaming && residentClassicIo0263) {
            const FluidDomainBounds streamDomain = make_fluid_domain_bounds(params, time);
            const CudaClassicSrcIoResident0263Diagnostics cudaIoStream0263 =
                try_apply_cuda_classic_src_io_fullface_stream_0263(state, params, streamDomain, step);
            record_cuda_resident_profile_0266(params.outputDir, step, "io_fullface_0263", "force_stream", cudaIoStream0263);
            handledByCudaStreaming = cudaIoStream0263.handled;
        }
        if (!handledByCudaStreaming && cuda_piston_streaming_0247b_requested()) {
            const CudaPistonStreaming0247bDiagnostics cudaStreaming0247b =
                try_apply_cuda_piston_streaming_0247b(state, params, step);
            record_cuda_resident_profile_0266(params.outputDir, step, "piston_0247b", "force_stream", cudaStreaming0247b);
            handledByCudaStreaming = cudaStreaming0247b.handled;
        }
        const bool fusedClassicOnly0274 =
            !params.projectionEnable && !params.resamplingEnable &&
            !params.closedCapacityResponseEnable && !params.thermostatEnable;
        const bool fusedStreamDeposit0274 = fusedClassicOnly0274 &&
            env_truthy_0270("MPCD_CUDA_PERSISTENT_SRC_COLLISION_FUSED_STREAM_DEPOSIT_0274") &&
            !env_truthy_0270("MPCD_CUDA_PERSISTENT_SRC_COLLISION_DISABLE_FUSED_STREAM_DEPOSIT_0274");
        if (!handledByCudaStreaming && fusedStreamDeposit0274 && residentClassicWall0261) {
            CudaWallSimpleStreaming0246Diagnostics deferred{};
            deferred.requested = true;
            deferred.supported = true;
            deferred.handled = true;
            deferred.applied = true;
            deferred.particles = nActiveFluid;
            deferred.fluidParticles = nActiveFluid;
            const auto upload0 = ProfileClock::now();
#if defined(MPCD_ENABLE_CUDA_PARTICLE_STATE)
            if (!cuda_shared_particle_state_0251_is_fresh()) {
                CudaParticleStateDiagnostics particleDiag{};
                cuda_shared_particle_state_0251().upload_all(state, &particleDiag);
                cuda_shared_particle_state_0251_mark_fresh("fused_stream_deposit_0274_initial_wall_upload");
                deferred.allocationCalls = particleDiag.allocationCalls;
                deferred.uploadCalls = particleDiag.uploadCalls;
            }
#else
            deferred.handled = false;
            deferred.applied = false;
#endif
            const auto upload1 = ProfileClock::now();
            deferred.totalSeconds = std::chrono::duration<double>(upload1 - upload0).count();
            deferred.uploadSeconds = deferred.totalSeconds;
            record_cuda_resident_profile_0266(params.outputDir, step, "wall_simple_0274_fused_deferred", "force_stream", deferred);
            handledByCudaStreaming = deferred.handled;
            wallSimpleResidentStreamHandled0270 = deferred.handled;
        }
        if (!handledByCudaStreaming && fusedStreamDeposit0274 && residentClassicPeriodic0260) {
            CudaPeriodicStreaming0245Diagnostics deferred{};
            deferred.requested = true;
            deferred.supported = true;
            deferred.handled = true;
            deferred.applied = true;
            deferred.particles = nActiveFluid;
            deferred.fluidParticles = nActiveFluid;
            const auto upload0 = ProfileClock::now();
#if defined(MPCD_ENABLE_CUDA_PARTICLE_STATE)
            if (!cuda_shared_particle_state_0251_is_fresh()) {
                CudaParticleStateDiagnostics particleDiag{};
                cuda_shared_particle_state_0251().upload_all(state, &particleDiag);
                cuda_shared_particle_state_0251_mark_fresh("fused_stream_deposit_0274_initial_periodic_upload");
                deferred.allocationCalls = particleDiag.allocationCalls;
                deferred.uploadCalls = particleDiag.uploadCalls;
            }
#else
            deferred.handled = false;
            deferred.applied = false;
#endif
            const auto upload1 = ProfileClock::now();
            deferred.totalSeconds = std::chrono::duration<double>(upload1 - upload0).count();
            deferred.uploadSeconds = deferred.totalSeconds;
            record_cuda_resident_profile_0266(params.outputDir, step, "periodic_0274_fused_deferred", "force_stream", deferred);
            handledByCudaStreaming = deferred.handled;
            periodicFusedStreamHandled0274 = deferred.handled;
        }
        if (!handledByCudaStreaming && cuda_wall_simple_streaming_0246_requested()) {
            const CudaWallSimpleStreaming0246Diagnostics cudaStreaming0246 =
                try_apply_cuda_wall_simple_streaming_0246(state, params, step);
            record_cuda_resident_profile_0266(params.outputDir, step, "wall_simple_0246", "force_stream", cudaStreaming0246);
            handledByCudaStreaming = cudaStreaming0246.handled;
            wallSimpleResidentStreamHandled0270 =
                (residentClassicWall0261 || residentClassicWallCircle0318) && cudaStreaming0246.handled;
            if (wallSimpleResidentStreamHandled0270) {
                cudaWallResidentBoundaryDiagnostics0270 = BoundaryDiagnostics{};
                cudaWallResidentBoundaryDiagnostics0270.hitsBottom = cudaStreaming0246.hitsBottom;
                cudaWallResidentBoundaryDiagnostics0270.hitsTop = cudaStreaming0246.hitsTop;
                cudaWallResidentBoundaryDiagnostics0270.maxYWallReflectionsPerParticle =
                    cudaStreaming0246.maxYWallReflectionsPerParticle;
                cudaWallResidentBoundaryDiagnosticsValid0270 = true;
            }
        }
        if (!handledByCudaStreaming && cuda_periodic_streaming_0245_requested()) {
            const CudaPeriodicStreaming0245Diagnostics cudaStreaming0245 =
                try_apply_cuda_periodic_streaming_0245(state, params, step);
            record_cuda_resident_profile_0266(params.outputDir, step, "periodic_0245", "force_stream", cudaStreaming0245);
            handledByCudaStreaming = cudaStreaming0245.handled;
            periodicResidentStreamHandled0334 = residentClassicPeriodic0260 && cudaStreaming0245.handled;
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

    {
        MPCD_PROFILE_PHASE(result.profile, Domain);
        result.domain = make_fluid_domain_bounds(params, time);
    }
    {
        MPCD_PROFILE_PHASE(result.profile, Boundary);
        bool handledByCudaBoundary = false;
        if (residentClassicIo0264) {
            const CudaClassicSrcIoResident0263Diagnostics cudaIoBoundary0264 =
                try_apply_cuda_classic_src_io_segmented_boundary_0264(state, params, result.domain, step, time);
            record_cuda_resident_profile_0266(params.outputDir, step, "io_segmented_0264", "boundary_conditions", cudaIoBoundary0264);
            if (cudaIoBoundary0264.handled) {
                result.boundary = cudaIoBoundary0264.boundary;
                handledByCudaBoundary = true;
            }
        }
        if (!handledByCudaBoundary && residentClassicIo0263) {
            const CudaClassicSrcIoResident0263Diagnostics cudaIoBoundary0263 =
                try_apply_cuda_classic_src_io_fullface_boundary_0263(state, params, result.domain, step, time);
            record_cuda_resident_profile_0266(params.outputDir, step, "io_fullface_0263", "boundary_conditions", cudaIoBoundary0263);
            if (cudaIoBoundary0263.handled) {
                result.boundary = cudaIoBoundary0263.boundary;
                handledByCudaBoundary = true;
            }
        }
        if (!handledByCudaBoundary && (periodicFusedStreamHandled0274 || periodicResidentStreamHandled0334)) {
            // 0334a: full-periodic CUDA streaming already applied the only
            // external-boundary operation, namely periodic wrapping.  Re-running
            // the CPU boundary pass scans a stale host ParticleState in resident
            // mode and costs a full particle pass without changing physics.
            result.boundary = BoundaryDiagnostics{};
            handledByCudaBoundary = true;
        }
        if (!handledByCudaBoundary && wallSimpleResidentStreamHandled0270 &&
            !env_truthy_0270("MPCD_CUDA_CLASSIC_SRC_WALL_RESIDENT_0270_DISABLE_BOUNDARY_SKIP")) {
            // The wall-simple CUDA stream kernel already applies the periodic-x
            // wrap and bounded-y reflections for the validated static channel
            // subset.  Re-running apply_boundary_conditions() here only scans
            // the host ParticleState, which is intentionally stale in resident
            // mode.  The physical reflections have already been applied by
            // CUDA 0246, so keep the CPU boundary pass skipped but propagate the
            // CUDA wall-hit diagnostics into the runtime summary.
            result.boundary = cudaWallResidentBoundaryDiagnosticsValid0270
                ? cudaWallResidentBoundaryDiagnostics0270
                : BoundaryDiagnostics{};
            handledByCudaBoundary = true;
        }
        if (!handledByCudaBoundary) {
            const bool hardReservoir0435d = hard_inlet_reservoir_requested_0435d(params);
            CudaInletOutletSegmented0249bDiagnostics cudaIo0249b{};
            if (!hardReservoir0435d && cuda_inlet_outlet_segmented_0249b_requested()) {
                cudaIo0249b = try_apply_cuda_inlet_outlet_segmented_0249b(
                    state, params, result.domain, step, time);
            }
            CudaInletOutletFullface0249aDiagnostics cudaIo0249a{};
            if (!hardReservoir0435d && cuda_inlet_outlet_fullface_0249a_requested()) {
                cudaIo0249a = try_apply_cuda_inlet_outlet_fullface_0249a(
                    state, params, result.domain, step, time);
            }

            // 0435c: decide CPU-boundary execution after actual CUDA IO handling.
            // The segmented/full-face CUDA IO paths may edit particles and then
            // mark shared_0251 fresh.  Re-running apply_boundary_conditions()
            // afterwards can edit a stale host ParticleState and invalidate the
            // fresh CUDA shared state needed by persistent collision/thermostat.
            if (cudaIo0249b.handled || cudaIo0249a.handled) {
                result.boundary = BoundaryDiagnostics{};
                merge_cuda_inlet_outlet_segmented_0249b_diagnostics(result.boundary, cudaIo0249b);
                merge_cuda_inlet_outlet_fullface_0249a_diagnostics(result.boundary, cudaIo0249a);
                handledByCudaBoundary = true;
            } else {
                BoundaryDiagnostics cpuBoundary0251 =
                    apply_boundary_conditions(state, params, result.domain, step, time);
                const bool cpuBoundaryEditedParticles0251 =
                    boundary_cpu_may_have_edited_particles_0251(cpuBoundary0251);

                result.boundary = cpuBoundary0251;
                merge_cuda_inlet_outlet_segmented_0249b_diagnostics(result.boundary, cudaIo0249b);
                merge_cuda_inlet_outlet_fullface_0249a_diagnostics(result.boundary, cudaIo0249a);

                if (cpuBoundaryEditedParticles0251) {
                    cuda_shared_particle_state_0251_invalidate("cpu_boundary_conditions_edited_particles");
                }
            }
        }
    }
    // 0315e: synchronize the active host prefix only when an immediate
    // downstream CPU/host particle consumer is actually present.  In the
    // validated resident IO classic path, collision and the due thermostat can
    // consume the shared 0251 device state directly; summaries/dumps keep using
    // their own lazy active-prefix download later.  This removes the per-step
    // host mirror that 0315d-fix07 needed as a conservative safety net.
    if ((residentClassicIo0263 || residentClassicIo0264) &&
        cuda_shared_particle_state_0251_is_fresh() &&
        cuda_io_boundary_requires_active_host_prefix_sync_0315e(
            params, grid, result.domain, step, collectResamplingDiagnosticsWhenDisabled)) {
        (void)cuda_shared_particle_state_0251_download_if_fresh(state);
    }

    {
        MPCD_PROFILE_PHASE(result.profile, Immersed);
        bool handledByCudaImmersed = false;

        // 0315e-fix09: the CUDA immersed-solid handlers are not yet fully
        // device-authoritative with respect to the active-prefix IO boundary
        // update.  The backward-step validation uses the rectangle handler and
        // diverges if it is called with a stale host ParticleState after the
        // resident inlet/outlet CUDA compaction.  Synchronize only the active
        // prefix, and only when a CUDA immersed handler is actually requested.
        // This preserves the optimized box/TG/Poiseuille paths while restoring
        // the validated step trajectory.
        if (cuda_immersed_rectangle_0247_requested() || cuda_immersed_circle_0284_requested()) {
            // 0334a: CUDA immersed handlers consume the shared resident device
            // state directly.  Avoid a pre-handler active-prefix download for
            // all resident boundary families.  If no CUDA handler accepts the
            // case, synchronize immediately before the CPU fallback below.
        }

        if (cuda_immersed_rectangle_0247_requested()) {
            const CudaImmersedRectangle0247Diagnostics cudaImmersed0247 =
                try_apply_cuda_immersed_rectangle_0247(state, params, result.domain, time);
            record_cuda_resident_profile_0266(params.outputDir, step, "immersed_rectangle_0247", "immersed_solid", cudaImmersed0247);
            if (cudaImmersed0247.handled) {
                result.immersed.hits = cudaImmersed0247.hits;
                handledByCudaImmersed = true;
            }
        }
        if (!handledByCudaImmersed && cuda_immersed_circle_0284_requested()) {
            const CudaImmersedCircle0284Diagnostics cudaImmersed0284 =
                try_apply_cuda_immersed_circle_0284(state, params, result.domain, time);
            record_cuda_resident_profile_0266(params.outputDir, step, "immersed_circle_0284", "immersed_solid", cudaImmersed0284);
            if (cudaImmersed0284.handled) {
                result.immersed.hits = cudaImmersed0284.hits;
                handledByCudaImmersed = true;
            }
        }
        if (!handledByCudaImmersed) {
            cuda_classic_resident_sync_active_prefix_before_host_consumer_0334(
                state, residentClassicCuda, "cpu_immersed_solid_fallback");
            result.immersed = apply_immersed_solid_reflection(state, params, result.domain, time);
            if (result.immersed.hits != 0u) {
                cuda_shared_particle_state_0251_invalidate("cpu_immersed_solid_edited_particles");
            }
        }
    }
    {
        MPCD_PROFILE_PHASE(result.profile, Collision);
        if (cuda_collision_wrapper_still_needs_host_particles_0315f(params, grid, result.domain, step)) {
            cuda_classic_resident_sync_active_prefix_before_host_consumer_0334(
                state, residentClassicCuda, "collision_wrapper_host_side_inputs");
        }
        result.collision = src_collision_step(state, params, grid, result.domain, step, workspace.collision);
    }
    bool q6ResidentHandled0400 = false;
    bool thermostatHandledByQ6Resident0400 = false;
    {
        MPCD_PROFILE_PHASE(result.profile, Q6Projection);
        if (!params.srcClassicCudaModeEnable) {
            const CudaQ6Resident0400Diagnostics cudaQ6 =
                try_apply_cuda_q6_resident_0400(state, params, grid, result.domain, step, time);
            if (cudaQ6.handled) {
                result.q6 = q6_projection_diagnostics_from_cuda_resident_0400(cudaQ6, params);
                q6ResidentHandled0400 = true;
            } else {
                if (env_truthy_0270("MPCD_CUDA_Q6_RESIDENT_STRICT_0400")) {
                    throw std::runtime_error(std::string("CUDA resident Q6 strict path was requested but not handled: ") +
                                             cudaQ6.reason);
                }
                result.q6 = apply_q6_periodic_projection(state, params, grid, result.domain, time, workspace.q6);
                if (params.projectionEnable) {
                    cuda_shared_particle_state_0251_invalidate("cpu_q6_projection_after_collision");
                }
            }
        }
    }
    {
        MPCD_PROFILE_PHASE(result.profile, ClosedCapacity);
        if (!params.srcClassicCudaModeEnable) {
            if (q6ResidentHandled0400 &&
                (params.closedCapacityResponseEnable || params.closedCapacityVirialKickEnable)) {
                if (!cuda_shared_particle_state_0251_download_if_fresh(state)) {
                    throw std::runtime_error("cuda_q6_resident_0400 failed to synchronize before CPU closed-capacity consumer");
                }
            }
            result.capacity = apply_closed_capacity_virial_kick(state, params, grid, result.domain, workspace.capacity);
            if (params.closedCapacityVirialKickEnable) {
                cuda_shared_particle_state_0251_invalidate("cpu_closed_capacity_after_collision");
                q6ResidentHandled0400 = false;
            }
        }
    }
    {
        MPCD_PROFILE_PHASE(result.profile, Thermostat);
        if (q6ResidentHandled0400) {
            const CudaQ6ResidentThermostat0400Diagnostics cudaThermo =
                try_apply_cuda_q6_resident_thermostat_0400(state, params, grid, workspace.collision.cellId, step);
            if (cudaThermo.handled) {
                result.thermostat = cudaThermo.thermostat;
                thermostatHandledByQ6Resident0400 = true;
            }
        }
        if (!thermostatHandledByQ6Resident0400) {
            if (q6ResidentHandled0400 && params.thermostatEnable) {
                if (!cuda_shared_particle_state_0251_download_if_fresh(state)) {
                    throw std::runtime_error("cuda_q6_resident_0400 failed to synchronize before CPU thermostat consumer");
                }
                q6ResidentHandled0400 = false;
            }
            if (workspace.collision.cellId.size() != active_fluid_count_size(state)) {
                rebuild_active_cell_ids_0431(state, params, grid, result.collision.shift, workspace.collision.cellId);
            }
            result.thermostat = apply_cell_relative_rescale_thermostat(
                state, params, grid, workspace.collision.cellId, step, workspace.thermostat);
            if (!residentClassicCuda && !cuda_shared_particle_state_0251_is_fresh()) {
                cuda_shared_particle_state_0251_invalidate("cpu_thermostat_after_collision");
            }
        }
    }
    {
        MPCD_PROFILE_PHASE(result.profile, KeepMeanFlow);
        if (q6ResidentHandled0400 && params.keepMeanFlowEnable) {
            if (!cuda_shared_particle_state_0251_download_if_fresh(state)) {
                throw std::runtime_error("cuda_q6_resident_0400 failed to synchronize before CPU mean-flow consumer");
            }
            q6ResidentHandled0400 = false;
        }
        apply_keep_mean_flow(state, params);
        if (params.keepMeanFlowEnable || (!residentClassicCuda && !cuda_shared_particle_state_0251_is_fresh())) {
            cuda_shared_particle_state_0251_invalidate("cpu_keep_mean_flow_after_collision");
        }
    }

    // 0343/topo: pure Brinkman/Darcy penalization for SRC classic CUDA-VIZ.
    // It is deliberately placed after thermostat/mean-flow correction and before
    // any resampling/Q6 future continuation.  The kernel applies a collective
    // cell-mean velocity kick, leaving thermal fluctuations unchanged.
    if (params.darcyBrinkmanEnable) {
        result.darcy = try_apply_cuda_darcy_brinkman_0343(state, params, grid, result.domain, step, time);
    }

    // 0304: passive adaptive-trigger flag diagnostic.  This is intentionally
    // placed at the same post-SRC/post-thermostat physical-grid point as the
    // survey and future guard/refill decisions.  It deposits only enough cell
    // population information to emit low-N / empty-cell flags and compact
    // counters; it never triggers resampling yet and never mutates particles.
    if (cuda_resampling_adaptive_flag_0304_requested(step)) {
        (void)try_run_cuda_resampling_adaptive_flag_0304(
            state, params, grid, result.domain, step, time, "post_src_classic_post_thermostat_adaptive_flag");
    }

    // 0295: passive CUDA support survey at the physically validated insertion
    // point for future non-destructive resampling: after SRC classic has produced
    // the step state, after optional CPU Q6/capacity stages if they are enabled
    // in a non-classic run, and before the existing CPU resampling block.  The
    // survey uses the physical non-shifted grid, matching the validated
    // MATLAB/OpenMP resampling placement; it never mutates particles, masses or
    // roles.
    if (cuda_resampling_support_survey_0295_requested(step)) {
        (void)try_run_cuda_resampling_support_survey_0295(
            state, params, grid, result.domain, step, time, "post_src_classic_post_thermostat_pre_resampling");
    }

    // 0296: conservative CUDA mass reconditioning at the same post-SRC,
    // non-shifted-grid insertion point.  This first mutating resampling brick
    // changes neither support nor roles: it only smooths particle masses inside
    // wet cells and restores the cell momentum.  It is intentionally separate
    // from the future population guard (0297).
    if (cuda_resampling_mass_recondition_0296_requested(step)) {
        (void)try_apply_cuda_resampling_mass_recondition_0296(
            state, params, grid, result.domain, step, time, "post_src_classic_post_thermostat_pre_cpu_resampling");
    }

    // 0297: minimal local CUDA population guard at the same post-SRC,
    // physical-grid insertion point.  Unlike 0296, this brick can change the
    // support by one local merge per rich cell and one local split per poor cell,
    // preserving local mass and momentum up to roundoff.  It remains independent
    // of Q6 CUDA and does not build long-distance transfer plans.
    if (cuda_resampling_population_guard_0297_requested(params, step)) {
        (void)try_apply_cuda_resampling_population_guard_0297(
            state, params, grid, result.domain, step, time, "post_src_classic_post_thermostat_pre_cpu_resampling");
    }

    // 0158: when resampling is disabled, the pool/deposit diagnostics are only
    // needed on steps for which the caller will write a runtime summary.  The
    // default public API keeps the previous conservative behavior; the main
    // production loop passes false on non-summary steps.
    if (!params.resamplingEnable && !collectResamplingDiagnosticsWhenDisabled) {
        if ((q6ResidentHandled0400 || thermostatHandledByQ6Resident0400) &&
            !cuda_q6_resident_src_any_step_0401_supported(params) &&
            !env_truthy_0270("MPCD_CUDA_Q6_RESIDENT_SKIP_STEP_BOUNDARY_SYNC_0400")) {
            (void)cuda_shared_particle_state_0251_download_if_fresh(state);
        }
        return result;
    }

    // 0260/0261/0262/0263/0264 resident classic CUDA keeps the host ParticleState stale between summaries.
    // The disabled-resampling diagnostics below still read the host state to report
    // resampStdN/resampMRel* in runtime_summary.csv.  Synchronize only on summary/final
    // steps, i.e. exactly when collectResamplingDiagnosticsWhenDisabled is true, so the
    // resident performance path is preserved between summaries.
    if (residentClassicCuda || q6ResidentHandled0400 || thermostatHandledByQ6Resident0400) {
        (void)cuda_shared_particle_state_0251_download_if_fresh(state);
        q6ResidentHandled0400 = false;
        thermostatHandledByQ6Resident0400 = false;
    }

    {
        MPCD_PROFILE_PHASE(result.profile, ResamplingPoolInitial);
        result.resamplingPool = rebuild_resampling_particle_pool(state, workspace.resamplingPool);
    }
    // 0437: the population guard may change particle support before any
    // extraction plan is consumed. Building the expensive global transfer plan
    // here made edited steps discard it and rebuild the same structure from the
    // post-guard state. Deposit moments/classification first, then build exactly
    // one mutation plan from the state that will actually feed extraction.
    const bool buildInitialResamplingPlan = false;
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
        cuda_shared_particle_state_0251_invalidate("cpu_resampling_population_guard_edited_0472");
    }

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
    } else if (params.resamplingExtractionEnable) {
        // No support edit occurred, so no post-guard rebuild is needed. Build
        // the deferred mutation plan from the unchanged initial state.
        MPCD_PROFILE_PHASE(result.profile, ResamplingPostGuardDeposit);
        result.resampling = deposit_weighted_real_fluid(
            state, params, grid, result.domain, time, GridShift{}, workspace.resampling,
            true, ResamplingDepositProfileContext::PostGuard, true);
        attach_resampling_pool_diagnostics(result.resampling, result.resamplingPool);
        attach_resampling_population_guard_diagnostics(result.resampling, populationGuard);
    }

    ResamplingLatentActivationDiagnostics latentActivation{};
    if (params.resamplingLatentActivationEnable && result.resampling.candidateListsBuilt) {
        MPCD_PROFILE_PHASE(result.profile, ResamplingLatentActivation);
        latentActivation = apply_resampling_latent_activation(
            state, workspace.resamplingPool, workspace.resampling, result.resampling, params, grid);
        planOrTransferEdited = planOrTransferEdited || latentActivation.applied;
        if (latentActivation.applied) {
            cuda_shared_particle_state_0251_invalidate("cpu_resampling_latent_activation_edited_0472");
        }
    }

    ResamplingExtractionApplyDiagnostics extractionApply{};
    ResamplingInsertionApplyDiagnostics insertionApply{};

    const bool cudaResamplingPipelineShadow0445Requested =
        cuda_resampling_pipeline_shadow_0445_requested(step);
    const bool cudaResamplingPipelineApply0448Requested =
        cuda_resampling_pipeline_apply_0448_requested();
    const bool cudaResamplingUpstreamShadow0450Requested =
        cuda_resampling_upstream_shadow_0450_requested(step);
    const bool cudaResamplingUpstreamApply0451Requested =
        cuda_resampling_upstream_apply_0451_requested(step);
    const bool cudaResamplingOperationMaterialize0453Requested =
        cuda_resampling_operation_materialize_0453_requested(step);
    const bool cudaResamplingOperationMaterializeOnPlan0475ARequested =
        env_truthy_src_base_0475a("MPCD_CUDA_RESAMPLING_MATERIALIZER_ON_PLAN_0475A") &&
        !workspace.resampling.transferPlan.empty() &&
        !workspace.resampling.passiveExtractionOperations.empty();
    ParticleState cudaResamplingPipelineShadowInput0445{};
    WeightedRealFluidDepositWorkspace cudaResamplingPipelineShadowEditWorkspace0445{};
    WeightedRealFluidDepositWorkspace cudaResamplingPipelineShadowRemapWorkspace0445{};
    WeightedResamplingDiagnostics cudaResamplingPipelineShadowRemapDeposit0445{};
    if (cudaResamplingPipelineShadow0445Requested) {
        // 0446: capture before CPU extraction/insertion so the CUDA shadow can
        // replay the same passive operation list and then compare against the
        // CPU-authoritative final state after remap+thermal.
        cudaResamplingPipelineShadowInput0445 = state;
        cudaResamplingPipelineShadowEditWorkspace0445 = workspace.resampling;
    }

    if (cudaResamplingUpstreamApply0451Requested) {
        // 0451: CUDA upstream apply gate.  CUDA recomputes and validates
        // deposit/classification/poor-rich compaction/planner before the
        // downstream mutating path.  The current legacy donor-particle
        // materializer still consumes the host mirror workspace, so this stage
        // is an accepted CUDA-authority gate rather than the final host-free
        // upstream replacement.
        (void)try_apply_cuda_resampling_upstream_plan_0451(
            state, params, grid, step, workspace.resampling, result.resampling);
    } else if (cudaResamplingUpstreamShadow0450Requested) {
        // 0450: validate CUDA deposit/classification/poor-rich compaction and
        // transfer planning inside the real solver before the CPU or CUDA
        // apply path mutates extraction/insertion state. CPU remains authoritative.
        (void)try_run_cuda_resampling_upstream_shadow_0450(
            state, params, grid, step, workspace.resampling, result.resampling);
    }

    if (cudaResamplingOperationMaterialize0453Requested ||
        cudaResamplingOperationMaterializeOnPlan0475ARequested) {
        // 0453: CUDA donor-particle operation materializer.  CUDA scans the
        // accepted transfer plan and active particles to rebuild the passive
        // extraction/insertion operation vector.  A strict CPU/GPU operation
        // gate is kept; on PASS, the downstream 0448 apply backend consumes the
        // CUDA-materialized compact operation list.
        (void)try_apply_cuda_resampling_operation_materializer_0453(
            state, params, grid, step, workspace.resampling);
    }

    if (params.resamplingExtractionEnable && result.resampling.extractionPlanBuilt &&
        !workspace.resampling.passiveExtractionOperations.empty()) {
        bool handledByCudaResampling0448 = false;
        if (cudaResamplingPipelineApply0448Requested) {
            const CudaResamplingPipelineApply0448Diagnostics cudaApply0448 =
                try_apply_cuda_resampling_pipeline_particle_edits_0448(
                    state, params, grid, step, workspace.resampling, extractionApply, insertionApply);
            handledByCudaResampling0448 = cudaApply0448.handled;
            planOrTransferEdited = planOrTransferEdited || cudaApply0448.applied;
        }

        bool handledByCudaResampling0240 = false;
        if (!handledByCudaResampling0448 && cuda_resampling_persistent_active_path_0240_requested(state)) {
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

        if (!handledByCudaResampling0448 && !handledByCudaResampling0240) {
            {
                MPCD_PROFILE_PHASE(result.profile, ResamplingExtraction);
                extractionApply =
                    apply_resampling_extraction_operations(state, workspace.resamplingPool, workspace.resampling);
            }
            planOrTransferEdited = planOrTransferEdited || extractionApply.applied;
            if (extractionApply.applied) {
                cuda_shared_particle_state_0251_invalidate("cpu_resampling_extraction_edited_0472");
            }

            if (params.resamplingInsertionEnable && extractionApply.applied) {
                MPCD_PROFILE_PHASE(result.profile, ResamplingInsertion);
                insertionApply = apply_resampling_insertion_operations(
                    state, workspace.resamplingPool, workspace.resampling, grid);
                planOrTransferEdited = planOrTransferEdited || insertionApply.applied;
                if (insertionApply.applied) {
                    cuda_shared_particle_state_0251_invalidate("cpu_resampling_insertion_edited_0472");
                }
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

    if (cudaResamplingPipelineShadow0445Requested) {
        cudaResamplingPipelineShadowRemapWorkspace0445 = workspace.resampling;
        cudaResamplingPipelineShadowRemapDeposit0445 = result.resampling;
    }

    if (params.resamplingRemapEnable && massRenormalizationStep) {
        bool handledByCudaResamplingApply0448 = false;
        bool sharedStatePreservedByCudaRemap = false;
        if (cudaResamplingPipelineApply0448Requested &&
            !params.speciesResamplingMassClosureEnable) {
            MPCD_PROFILE_PHASE(result.profile, ResamplingRemap);
            const CudaResamplingPipelineApply0448Diagnostics cudaApply0448 =
                try_apply_cuda_resampling_pipeline_remap_thermal_0448(
                    state, params, workspace.resampling, result.resampling,
                    resamplingMassCorrectionStrength, capacityRemapTargetCellMass,
                    step, remapApply, thermalApply);
            handledByCudaResamplingApply0448 = cudaApply0448.handled;
            sharedStatePreservedByCudaRemap = cudaApply0448.handled && cudaApply0448.remapSharedState != 0u;
        }
        if (!handledByCudaResamplingApply0448) {
            {
                MPCD_PROFILE_PHASE(result.profile, ResamplingRemap);
                remapApply = apply_resampling_local_mass_momentum_remap(
                    state, workspace.resampling, result.resampling,
                    resamplingMassCorrectionStrength, capacityRemapTargetCellMass, &params);
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
        }
        if ((remapApply.applied || thermalApply.applied || massGuardApply.applied) &&
            !sharedStatePreservedByCudaRemap) {
            cuda_shared_particle_state_0251_invalidate("resampling_remap_thermal_or_massguard_edited_0472");
        }
        {
            MPCD_PROFILE_PHASE(result.profile, ResamplingPostRemapDeposit);
            result.resampling = deposit_weighted_real_fluid(
                state, params, grid, result.domain, time, GridShift{}, workspace.resampling, false,
                ResamplingDepositProfileContext::PostRemap, true);
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
            cuda_shared_particle_state_0251_invalidate("resampling_late_thermal_edited_0472");
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

    if (cudaResamplingPipelineShadow0445Requested) {
        (void)try_run_cuda_resampling_pipeline_shadow_0445(
            cudaResamplingPipelineShadowInput0445,
            state,
            params,
            grid,
            result.domain,
            time,
            step,
            "post_cpu_resampling_remap_thermal_shadow_0445",
            cudaResamplingPipelineShadowEditWorkspace0445,
            cudaResamplingPipelineShadowRemapWorkspace0445,
            cudaResamplingPipelineShadowRemapDeposit0445,
            extractionApply,
            insertionApply,
            remapApply,
            thermalApply);
    }
    return result;
}

} // namespace mpcd
