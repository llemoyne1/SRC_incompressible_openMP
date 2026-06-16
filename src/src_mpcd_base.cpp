#include "src_mpcd_base.h"
#include "closed_capacity_response.h"
#include "particle_audit.h"

#include <algorithm>
#include <chrono>
#include <cstddef>
#include <cstdint>
#include <cmath>
#include <cstdlib>
#include <fstream>
#include <iomanip>
#include <limits>
#include <string>
#include <vector>


namespace mpcd {
namespace {

struct StepTimingRecord {
    std::uint64_t step = 0u;
    double total = 0.0;
    double validation = 0.0;
    double stream = 0.0;
    double domain = 0.0;
    double boundary = 0.0;
    double immersed = 0.0;
    double collision = 0.0;
    double q6 = 0.0;
    double virial = 0.0;
    double thermostat = 0.0;
    double meanFlow = 0.0;
    double resampPool0 = 0.0;
    double resampDeposit0 = 0.0;
    double resampAttach = 0.0;
    double resampThermalReference = 0.0;
    double resampPopulationGuard = 0.0;
    double resampPoolGuard = 0.0;
    double resampDepositGuard = 0.0;
    double resampLatent = 0.0;
    double resampExtract = 0.0;
    double resampInsert = 0.0;
    double resampPoolEdit = 0.0;
    double resampDepositEdit = 0.0;
    double resampRemapCapacity = 0.0;
    double resampRemap = 0.0;
    double resampMassGuard = 0.0;
    double resampDepositRemap = 0.0;
    double resampThermalLate = 0.0;
    double resampVelocityRefresh = 0.0;
    double unaccounted = 0.0;
};

class StepTimingWriter {
public:
    StepTimingWriter() {
        const char* pathEnv = std::getenv("MPCD_TIMING_CSV");
        if (pathEnv == nullptr || std::string(pathEnv).empty()) {
            return;
        }
        path_ = pathEnv;
        const char* everyEnv = std::getenv("MPCD_TIMING_EVERY");
        if (everyEnv != nullptr && *everyEnv != '\0') {
            char* end = nullptr;
            const unsigned long long parsed = std::strtoull(everyEnv, &end, 10);
            if (end != everyEnv && parsed > 0ull) {
                every_ = static_cast<std::uint64_t>(parsed);
            }
        }
        out_.open(path_, std::ios::out | std::ios::trunc);
        if (!out_) {
            return;
        }
        enabled_ = true;
        out_ << "step,total,validation,stream,domain,boundary,immersed,collision,q6,virial,thermostat,mean_flow,"
             << "resamp_pool0,resamp_deposit0,resamp_attach,resamp_thermal_reference,resamp_population_guard,"
             << "resamp_pool_guard,resamp_deposit_guard,resamp_latent,resamp_extract,resamp_insert,"
             << "resamp_pool_edit,resamp_deposit_edit,resamp_remap_capacity,resamp_remap,resamp_mass_guard,"
             << "resamp_deposit_remap,resamp_thermal_late,resamp_velocity_refresh,unaccounted\n";
        out_ << std::setprecision(9);
    }

    bool enabled_for_step(std::uint64_t step) const {
        return enabled_ && every_ > 0u && (step % every_ == 0u);
    }

    void write(const StepTimingRecord& r) {
        if (!enabled_) return;
        out_ << r.step << ',' << r.total << ',' << r.validation << ',' << r.stream << ','
             << r.domain << ',' << r.boundary << ',' << r.immersed << ',' << r.collision << ','
             << r.q6 << ',' << r.virial << ',' << r.thermostat << ',' << r.meanFlow << ','
             << r.resampPool0 << ',' << r.resampDeposit0 << ',' << r.resampAttach << ','
             << r.resampThermalReference << ',' << r.resampPopulationGuard << ','
             << r.resampPoolGuard << ',' << r.resampDepositGuard << ',' << r.resampLatent << ','
             << r.resampExtract << ',' << r.resampInsert << ',' << r.resampPoolEdit << ','
             << r.resampDepositEdit << ',' << r.resampRemapCapacity << ',' << r.resampRemap << ','
             << r.resampMassGuard << ',' << r.resampDepositRemap << ',' << r.resampThermalLate << ','
             << r.resampVelocityRefresh << ',' << r.unaccounted << '\n';
    }

private:
    bool enabled_ = false;
    std::uint64_t every_ = 1u;
    std::string path_;
    std::ofstream out_;
};

StepTimingWriter& step_timing_writer() {
    static StepTimingWriter writer;
    return writer;
}

bool resampling_cellid_reuse_enabled() {
    const char* env = std::getenv("MPCD_DISABLE_RESAMPLING_CELLID_REUSE");
    if (env == nullptr || *env == '\0') {
        return true;
    }
    const std::string value(env);
    return value == "0" || value == "false" || value == "FALSE" || value == "off" || value == "OFF";
}

bool resampling_fluid_slots_enabled() {
    const char* env = std::getenv("MPCD_DISABLE_RESAMPLING_FLUID_SLOTS");
    if (env == nullptr || *env == '\0') {
        return true;
    }
    const std::string value(env);
    return value == "0" || value == "false" || value == "FALSE" || value == "off" || value == "OFF";
}

class StepPhaseTimer {
public:
    explicit StepPhaseTimer(std::uint64_t step)
        : enabled_(step_timing_writer().enabled_for_step(step)) {
        if (enabled_) {
            start_ = Clock::now();
            last_ = start_;
        }
    }

    void mark(StepTimingRecord& r, double StepTimingRecord::* field) {
        if (!enabled_) return;
        const auto now = Clock::now();
        r.*field += seconds(last_, now);
        last_ = now;
    }

    void finish(StepTimingRecord& r) {
        if (!enabled_) return;
        const auto now = Clock::now();
        r.total = seconds(start_, now);
        const double accounted = r.validation + r.stream + r.domain + r.boundary + r.immersed +
            r.collision + r.q6 + r.virial + r.thermostat + r.meanFlow + r.resampPool0 +
            r.resampDeposit0 + r.resampAttach + r.resampThermalReference +
            r.resampPopulationGuard + r.resampPoolGuard + r.resampDepositGuard + r.resampLatent +
            r.resampExtract + r.resampInsert + r.resampPoolEdit + r.resampDepositEdit +
            r.resampRemapCapacity + r.resampRemap + r.resampMassGuard + r.resampDepositRemap +
            r.resampThermalLate + r.resampVelocityRefresh;
        r.unaccounted = r.total - accounted;
        step_timing_writer().write(r);
    }

private:
    using Clock = std::chrono::steady_clock;
    bool enabled_ = false;
    Clock::time_point start_{};
    Clock::time_point last_{};

    static double seconds(const Clock::time_point& a, const Clock::time_point& b) {
        return std::chrono::duration<double>(b - a).count();
    }
};

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
                                  SrcMpcdBaseWorkspace& workspace,
                                  bool collectResamplingDiagnosticsWhenDisabled) {
    StepResult result{};
    StepTimingRecord timing{};
    timing.step = step;
    StepPhaseTimer phaseTimer(step);

    const std::size_t n = static_cast<std::size_t>(state.Np);
    particle_audit_start_step(step, state.Np, grid.numCells);
    validate_particle_state(state, "run_src_mpcd_base_step");
    ensure_particle_roles(state, ParticleRole::Fluid);
    phaseTimer.mark(timing, &StepTimingRecord::validation);

    // Uniform and optional Taylor--Green body acceleration, then free streaming
    // in the fixed numerical box. Taylor--Green forcing is evaluated at the
    // pre-stream particle position and is therefore independent of boundary
    // wrapping done later in the step.
    {

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
    phaseTimer.mark(timing, &StepTimingRecord::stream);

    const double time = static_cast<double>(step) * params.dt;
    {

        result.domain = make_fluid_domain_bounds(params, time);
    }
    phaseTimer.mark(timing, &StepTimingRecord::domain);
    {

        result.boundary = apply_boundary_conditions(state, params, result.domain, step, time);
    }
    phaseTimer.mark(timing, &StepTimingRecord::boundary);
    {

        result.immersed = apply_immersed_solid_reflection(state, params, result.domain, time);
    }
    phaseTimer.mark(timing, &StepTimingRecord::immersed);
    {

        result.collision = src_collision_step(state, params, grid, result.domain, step, workspace.collision);
    }
    phaseTimer.mark(timing, &StepTimingRecord::collision);
    {

        result.q6 = apply_q6_periodic_projection(state, params, grid, result.domain, time, workspace.q6);
    }
    phaseTimer.mark(timing, &StepTimingRecord::q6);
    {

        result.capacity = apply_closed_capacity_virial_kick(state, params, grid, result.domain, workspace.capacity);
    }
    phaseTimer.mark(timing, &StepTimingRecord::virial);
    {

        result.thermostat = apply_cell_relative_rescale_thermostat(
            state, params, grid, workspace.collision.cellId, step, workspace.thermostat);
    }
    phaseTimer.mark(timing, &StepTimingRecord::thermostat);
    {

        apply_keep_mean_flow(state, params);
    }
    phaseTimer.mark(timing, &StepTimingRecord::meanFlow);
    // 0158: when resampling is disabled, the pool/deposit diagnostics are only
    // needed on steps for which the caller will write a runtime summary.  The
    // default public API keeps the previous conservative behavior; the main
    // production loop passes false on non-summary steps.
    if (!params.resamplingEnable && !collectResamplingDiagnosticsWhenDisabled) {
        phaseTimer.finish(timing);
        particle_audit_finish_step();
        return result;
    }

    {

        result.resamplingPool = rebuild_resampling_particle_pool(state, workspace.resamplingPool);
    }
    phaseTimer.mark(timing, &StepTimingRecord::resampPool0);
    const bool buildInitialResamplingPlan =
        params.resamplingEnable && params.resamplingExtractionEnable;
    const bool reuseResamplingCellIds = resampling_cellid_reuse_enabled();
    const bool useResamplingFluidSlots = resampling_fluid_slots_enabled();
    const ResamplingParticlePoolWorkspace* resamplingPoolForDeposit =
        useResamplingFluidSlots ? &workspace.resamplingPool : nullptr;
    {

        result.resampling = deposit_weighted_real_fluid(
            state, params, grid, result.domain, time, GridShift{}, workspace.resampling,
            buildInitialResamplingPlan, false, resamplingPoolForDeposit);
    }
    phaseTimer.mark(timing, &StepTimingRecord::resampDeposit0);
    {

        attach_resampling_pool_diagnostics(result.resampling, result.resamplingPool);
    }
    phaseTimer.mark(timing, &StepTimingRecord::resampAttach);

    if (!params.resamplingEnable) {
        phaseTimer.finish(timing);
        particle_audit_finish_step();
        return result;
    }

    std::vector<double> preEditThermalEnergyTarget;
    std::vector<std::uint8_t> preEditThermalCell;
    if (params.resamplingThermalRenormalizationEnable) {

        capture_resampling_thermal_reference(
            state, workspace.resampling, preEditThermalEnergyTarget, preEditThermalCell);
    }
    phaseTimer.mark(timing, &StepTimingRecord::resampThermalReference);

    bool populationGuardEdited = false;
    bool planOrTransferEdited = false;
    ResamplingPopulationGuardDiagnostics populationGuard{};
    {

        populationGuard = apply_resampling_population_support_guard(
            state, workspace.resamplingPool, workspace.resampling, result.resampling, params, grid);
    }
    phaseTimer.mark(timing, &StepTimingRecord::resampPopulationGuard);
    populationGuardEdited = populationGuard.applied;

    if (populationGuardEdited) {
        {

            result.resamplingPool = rebuild_resampling_particle_pool(state, workspace.resamplingPool);
        }
        phaseTimer.mark(timing, &StepTimingRecord::resampPoolGuard);
        {

            result.resampling = deposit_weighted_real_fluid(
                state, params, grid, result.domain, time, GridShift{}, workspace.resampling,
                params.resamplingExtractionEnable,
                reuseResamplingCellIds,
                resamplingPoolForDeposit);
        }
        phaseTimer.mark(timing, &StepTimingRecord::resampDepositGuard);
        {

            attach_resampling_pool_diagnostics(result.resampling, result.resamplingPool);
            attach_resampling_population_guard_diagnostics(result.resampling, populationGuard);
        }
        phaseTimer.mark(timing, &StepTimingRecord::resampAttach);
    }

    ResamplingLatentActivationDiagnostics latentActivation{};
    if (params.resamplingLatentActivationEnable && result.resampling.candidateListsBuilt) {

        latentActivation = apply_resampling_latent_activation(
            state, workspace.resamplingPool, workspace.resampling, result.resampling, params, grid);
        planOrTransferEdited = planOrTransferEdited || latentActivation.applied;
    }
    phaseTimer.mark(timing, &StepTimingRecord::resampLatent);

    ResamplingExtractionApplyDiagnostics extractionApply{};
    ResamplingInsertionApplyDiagnostics insertionApply{};
    if (params.resamplingExtractionEnable && result.resampling.extractionPlanBuilt &&
        !workspace.resampling.passiveExtractionOperations.empty()) {
        {

            extractionApply =
                apply_resampling_extraction_operations(state, workspace.resamplingPool, workspace.resampling);
        }
        phaseTimer.mark(timing, &StepTimingRecord::resampExtract);
        planOrTransferEdited = planOrTransferEdited || extractionApply.applied;

        if (params.resamplingInsertionEnable && extractionApply.applied) {

            insertionApply = apply_resampling_insertion_operations(
                state, workspace.resamplingPool, workspace.resampling, grid);
            phaseTimer.mark(timing, &StepTimingRecord::resampInsert);
            planOrTransferEdited = planOrTransferEdited || insertionApply.applied;
        }
    }

    if (planOrTransferEdited) {
        {

            result.resamplingPool = rebuild_resampling_particle_pool(state, workspace.resamplingPool);
        }
        phaseTimer.mark(timing, &StepTimingRecord::resampPoolEdit);
        {

            result.resampling = deposit_weighted_real_fluid(
                state, params, grid, result.domain, time, GridShift{}, workspace.resampling, false,
                reuseResamplingCellIds,
                resamplingPoolForDeposit);
        }
        phaseTimer.mark(timing, &StepTimingRecord::resampDepositEdit);
        {

            attach_resampling_pool_diagnostics(result.resampling, result.resamplingPool);
        }
        phaseTimer.mark(timing, &StepTimingRecord::resampAttach);
    }

    const bool massRenormalizationStep = is_mass_renormalization_step(params, step);
    ClosedCapacityResponseDiagnostics remapCapacity{};
    double resamplingMassCorrectionStrength = 1.0;
    double capacityRemapTargetCellMass = -1.0;
    bool massGuardAllowedByCapacity = true;
    {

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
    phaseTimer.mark(timing, &StepTimingRecord::resampRemapCapacity);
    ResamplingRemapApplyDiagnostics remapApply{};
    ResamplingThermalRenormalizationDiagnostics thermalApply{};
    ResamplingMassGuardDiagnostics massGuardApply{};

    if (params.resamplingRemapEnable && massRenormalizationStep) {
        {

            remapApply = apply_resampling_local_mass_momentum_remap(
                state, workspace.resampling, result.resampling,
                resamplingMassCorrectionStrength, capacityRemapTargetCellMass);
        }
        phaseTimer.mark(timing, &StepTimingRecord::resampRemap);
        if (params.resamplingThermalRenormalizationEnable && remapApply.applied) {

            thermalApply = apply_resampling_local_thermal_renormalization(
                state, workspace.resampling, remapApply);
        }
        phaseTimer.mark(timing, &StepTimingRecord::resampThermalLate);
        if (params.resamplingMassGuardEnable && massGuardAllowedByCapacity && remapApply.applied) {

            massGuardApply = apply_resampling_particle_mass_guards(
                state, params, workspace.resampling, result.resampling,
                capacityRemapTargetCellMass);
        }
        phaseTimer.mark(timing, &StepTimingRecord::resampMassGuard);
        {

            result.resampling = deposit_weighted_real_fluid(
                state, params, grid, result.domain, time, GridShift{}, workspace.resampling, false,
                reuseResamplingCellIds,
                resamplingPoolForDeposit);
        }
        phaseTimer.mark(timing, &StepTimingRecord::resampDepositRemap);
        {
            // Remap, thermal-after-remap and particle-mass guards only update
            // masses/velocities.  Particle roles and pool membership are
            // unchanged, so the existing pool diagnostics remain valid and do
            // not need an O(Np) rebuild on every renormalization step.

            attach_resampling_pool_diagnostics(result.resampling, result.resamplingPool);
        }
        phaseTimer.mark(timing, &StepTimingRecord::resampAttach);
    }

    if (params.resamplingThermalRenormalizationEnable && !thermalApply.attempted) {
        install_resampling_thermal_reference(
            workspace.resampling, preEditThermalEnergyTarget, preEditThermalCell);
        const ResamplingRemapApplyDiagnostics thermalGate = make_thermal_reference_gate(preEditThermalCell);
        {

            thermalApply = apply_resampling_local_thermal_renormalization(
                state, workspace.resampling, thermalGate);
        }
        phaseTimer.mark(timing, &StepTimingRecord::resampThermalLate);
        if (thermalApply.applied) {
            {

                // 0172: thermal renormalization changes velocities only.
                // Reuse the current deposit topology/classification and refresh
                // only momentum/mean-velocity fields instead of rebuilding the
                // full particle->cell deposit, candidate lists and plans.
                const WeightedResamplingDiagnostics beforePostThermalDeposit = result.resampling;
                result.resampling = refresh_weighted_real_fluid_velocity_deposit(
                    state, params, grid, result.domain, time, GridShift{}, workspace.resampling,
                    beforePostThermalDeposit,
                    resamplingPoolForDeposit);
            }
            phaseTimer.mark(timing, &StepTimingRecord::resampVelocityRefresh);
            {
                // Thermal renormalization changes velocities only; keep the
                // already valid pool/free-list diagnostics instead of rebuilding
                // them after each late thermal pass.

                attach_resampling_pool_diagnostics(result.resampling, result.resamplingPool);
            }
            phaseTimer.mark(timing, &StepTimingRecord::resampAttach);
        }
    }

    {

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
    phaseTimer.mark(timing, &StepTimingRecord::resampAttach);
    phaseTimer.finish(timing);
    particle_audit_finish_step();
    return result;
}

} // namespace mpcd
