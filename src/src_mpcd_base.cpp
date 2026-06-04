#include "src_mpcd_base.h"
#include "closed_capacity_response.h"

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

#define MPCD_PROFILE_PHASE(profile, phaseName) ((void)0)


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
    const std::size_t n = static_cast<std::size_t>(state.Np);

    // Uniform and optional Taylor--Green body acceleration, then free streaming
    // in the fixed numerical box. Taylor--Green forcing is evaluated at the
    // pre-stream particle position and is therefore independent of boundary
    // wrapping done later in the step.
    {
        MPCD_PROFILE_PHASE(result.profile, ForceStream);
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

    const double time = static_cast<double>(step) * params.dt;
    {
        MPCD_PROFILE_PHASE(result.profile, Domain);
        result.domain = make_fluid_domain_bounds(params, time);
    }
    {
        MPCD_PROFILE_PHASE(result.profile, Boundary);
        result.boundary = apply_boundary_conditions(state, params, result.domain, step, time);
    }
    {
        MPCD_PROFILE_PHASE(result.profile, Immersed);
        result.immersed = apply_immersed_solid_reflection(state, params, result.domain, time);
    }
    {
        MPCD_PROFILE_PHASE(result.profile, Collision);
        result.collision = src_collision_step(state, params, grid, result.domain, step, workspace.collision);
    }
    {
        MPCD_PROFILE_PHASE(result.profile, Q6Projection);
        result.q6 = apply_q6_periodic_projection(state, params, grid, result.domain, time, workspace.q6);
    }
    {
        MPCD_PROFILE_PHASE(result.profile, ClosedCapacity);
        result.capacity = apply_closed_capacity_virial_kick(state, params, grid, result.domain, workspace.capacity);
    }
    {
        MPCD_PROFILE_PHASE(result.profile, Thermostat);
        result.thermostat = apply_cell_relative_rescale_thermostat(
            state, params, grid, workspace.collision.cellId, step, workspace.thermostat);
    }
    {
        MPCD_PROFILE_PHASE(result.profile, KeepMeanFlow);
        apply_keep_mean_flow(state, params);
    }
    // 0158: when resampling is disabled, the pool/deposit diagnostics are only
    // needed on steps for which the caller will write a runtime summary.  The
    // default public API keeps the previous conservative behavior; the main
    // production loop passes false on non-summary steps.
    if (!params.resamplingEnable && !collectResamplingDiagnosticsWhenDisabled) {
        return result;
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
