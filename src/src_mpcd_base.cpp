#include "src_mpcd_base.h"

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <cmath>
#include <vector>

namespace mpcd {
namespace {


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

StepResult run_src_mpcd_base_step(ParticleState& state,
                                  const SimulationParams& params,
                                  const CellGrid& grid,
                                  std::uint64_t step,
                                  SrcMpcdBaseWorkspace& workspace) {
    validate_particle_state(state, "run_src_mpcd_base_step");
    ensure_particle_roles(state, ParticleRole::Fluid);
    const std::size_t n = static_cast<std::size_t>(state.Np);

    // Uniform and optional Taylor--Green body acceleration, then free streaming
    // in the fixed numerical box. Taylor--Green forcing is evaluated at the
    // pre-stream particle position and is therefore independent of boundary
    // wrapping done later in the step.
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

    StepResult result{};
    const double time = static_cast<double>(step) * params.dt;
    result.domain = make_fluid_domain_bounds(params, time);
    result.boundary = apply_boundary_conditions(state, params, result.domain, step, time);
    result.immersed = apply_immersed_solid_reflection(state, params, result.domain, time);
    result.collision = src_collision_step(state, params, grid, result.domain, step, workspace.collision);
    result.q6 = apply_q6_periodic_projection(state, params, grid, result.domain, time, workspace.q6);
    result.thermostat = apply_cell_relative_rescale_thermostat(
        state, params, grid, workspace.collision.cellId, step, workspace.thermostat);
    apply_keep_mean_flow(state, params);
    result.resamplingPool = rebuild_resampling_particle_pool(state, workspace.resamplingPool);
    const bool buildInitialResamplingPlan =
        params.resamplingEnable && params.resamplingExtractionEnable;
    result.resampling = deposit_weighted_real_fluid(
        state, params, grid, result.domain, time, GridShift{}, workspace.resampling,
        buildInitialResamplingPlan);
    attach_resampling_pool_diagnostics(result.resampling, result.resamplingPool);

    if (!params.resamplingEnable) {
        return result;
    }

    std::vector<double> preEditThermalEnergyTarget;
    std::vector<std::uint8_t> preEditThermalCell;
    if (params.resamplingThermalRenormalizationEnable) {
        capture_resampling_thermal_reference(
            state, workspace.resampling, preEditThermalEnergyTarget, preEditThermalCell);
    }

    bool roleOrPositionEdited = false;
    ResamplingPopulationGuardDiagnostics populationGuard{};
    if (params.resamplingPopulationGuardEnable) {
        populationGuard = apply_resampling_population_support_guard(
            state, workspace.resamplingPool, workspace.resampling, result.resampling, params, grid);
        roleOrPositionEdited = roleOrPositionEdited || populationGuard.applied;
    }

    if (roleOrPositionEdited) {
        result.resamplingPool = rebuild_resampling_particle_pool(state, workspace.resamplingPool);
        result.resampling = deposit_weighted_real_fluid(
            state, params, grid, result.domain, time, GridShift{}, workspace.resampling,
            params.resamplingExtractionEnable);
        attach_resampling_pool_diagnostics(result.resampling, result.resamplingPool);
        attach_resampling_population_guard_diagnostics(result.resampling, populationGuard);
    }

    ResamplingLatentActivationDiagnostics latentActivation{};
    if (params.resamplingLatentActivationEnable && result.resampling.candidateListsBuilt) {
        latentActivation = apply_resampling_latent_activation(
            state, workspace.resamplingPool, workspace.resampling, result.resampling, params, grid);
        roleOrPositionEdited = roleOrPositionEdited || latentActivation.applied;
    }

    ResamplingExtractionApplyDiagnostics extractionApply{};
    ResamplingInsertionApplyDiagnostics insertionApply{};
    if (params.resamplingExtractionEnable && result.resampling.extractionPlanBuilt &&
        !workspace.resampling.passiveExtractionOperations.empty()) {
        extractionApply =
            apply_resampling_extraction_operations(state, workspace.resamplingPool, workspace.resampling);
        roleOrPositionEdited = roleOrPositionEdited || extractionApply.applied;

        if (params.resamplingInsertionEnable && extractionApply.applied) {
            insertionApply = apply_resampling_insertion_operations(
                state, workspace.resamplingPool, workspace.resampling, grid);
            roleOrPositionEdited = roleOrPositionEdited || insertionApply.applied;
        }
    }

    if (roleOrPositionEdited) {
        result.resamplingPool = rebuild_resampling_particle_pool(state, workspace.resamplingPool);
        result.resampling = deposit_weighted_real_fluid(
            state, params, grid, result.domain, time, GridShift{}, workspace.resampling, false);
        attach_resampling_pool_diagnostics(result.resampling, result.resamplingPool);
    }

    const bool massRenormalizationStep = is_mass_renormalization_step(params, step);
    ResamplingRemapApplyDiagnostics remapApply{};
    ResamplingThermalRenormalizationDiagnostics thermalApply{};
    ResamplingMassGuardDiagnostics massGuardApply{};

    if (params.resamplingRemapEnable && massRenormalizationStep) {
        remapApply = apply_resampling_local_mass_momentum_remap(
            state, workspace.resampling, result.resampling);
        if (params.resamplingThermalRenormalizationEnable && remapApply.applied) {
            thermalApply = apply_resampling_local_thermal_renormalization(
                state, workspace.resampling, remapApply);
        }
        if (params.resamplingMassGuardEnable && remapApply.applied) {
            massGuardApply = apply_resampling_particle_mass_guards(
                state, params, workspace.resampling, result.resampling);
        }
        result.resampling = deposit_weighted_real_fluid(
            state, params, grid, result.domain, time, GridShift{}, workspace.resampling, false);
        result.resamplingPool = rebuild_resampling_particle_pool(state, workspace.resamplingPool);
        attach_resampling_pool_diagnostics(result.resampling, result.resamplingPool);
    }

    if (params.resamplingThermalRenormalizationEnable && !thermalApply.attempted) {
        install_resampling_thermal_reference(
            workspace.resampling, preEditThermalEnergyTarget, preEditThermalCell);
        const ResamplingRemapApplyDiagnostics thermalGate = make_thermal_reference_gate(preEditThermalCell);
        thermalApply = apply_resampling_local_thermal_renormalization(
            state, workspace.resampling, thermalGate);
        if (thermalApply.applied) {
            result.resampling = deposit_weighted_real_fluid(
                state, params, grid, result.domain, time, GridShift{}, workspace.resampling, false);
            result.resamplingPool = rebuild_resampling_particle_pool(state, workspace.resamplingPool);
            attach_resampling_pool_diagnostics(result.resampling, result.resamplingPool);
        }
    }

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
    return result;
}

} // namespace mpcd
