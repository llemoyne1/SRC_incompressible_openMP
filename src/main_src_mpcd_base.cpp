#include "boundary_base.h"
#include "cell_grid.h"
#include "params_io_base.h"
#include "runtime_summary.h"
#include "fluid_domain.h"
#include "immersed_solid.h"
#include "src_mpcd_base.h"
#include "state_smpcd_io.h"
#include "weighted_resampling.h"

#include <array>
#include <chrono>
#include <exception>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <limits>
#include <iostream>
#include <sstream>
#include <string>
#include <vector>

#ifdef _OPENMP
#include <omp.h>
#endif

namespace {

std::string state_dump_name(const std::string& outputDir, int step) {
    std::ostringstream oss;
    oss << outputDir << "/state_step_" << std::setw(8) << std::setfill('0') << step << ".smpcd";
    return oss.str();
}

double elapsed_seconds(std::chrono::steady_clock::time_point t0) {
    const auto now = std::chrono::steady_clock::now();
    return std::chrono::duration<double>(now - t0).count();
}

int openmp_max_threads() {
#ifdef _OPENMP
    return omp_get_max_threads();
#else
    return 1;
#endif
}


void write_phase_profile_0163(const std::string& outputDir,
                              const std::array<double, mpcd::StepProfilePhaseCount>& profileSeconds,
                              const int measuredSteps) {
    const std::filesystem::path path = std::filesystem::path(outputDir) / "phase_profile_0163.csv";
    std::ofstream out(path);
    out << "phase,total_s,ms_per_step,percent_total\n";
    double total = 0.0;
    for (double v : profileSeconds) {
        total += v;
    }
    const double steps = measuredSteps > 0 ? static_cast<double>(measuredSteps) : 1.0;
    out << std::setprecision(17);
    for (std::size_t i = 0; i < mpcd::StepProfilePhaseCount; ++i) {
        const double value = profileSeconds[i];
        const double msPerStep = 1000.0 * value / steps;
        const double percent = total > std::numeric_limits<double>::min() ? 100.0 * value / total : 0.0;
        out << mpcd::step_profile_phase_name(i) << ','
            << value << ','
            << msPerStep << ','
            << percent << '\n';
    }
    out << "total_profiled," << total << ',' << (1000.0 * total / steps) << ",100\n";
}


void write_q6_cg_profile_0163(const std::string& outputDir,
                              const std::array<double, mpcd::Q6ProjectionProfilePhaseCount>& q6Seconds,
                              const std::array<double, mpcd::EllipticProjectionProfilePhaseCount>& ellipticSeconds,
                              const int measuredQ6Steps) {
    const std::filesystem::path path = std::filesystem::path(outputDir) / "q6_cg_profile_0163.csv";
    std::ofstream out(path);
    out << "group,phase,total_s,ms_per_q6_step,percent_group_total\n";
    out << std::setprecision(17);
    const double steps = measuredQ6Steps > 0 ? static_cast<double>(measuredQ6Steps) : 1.0;

    double q6Total = 0.0;
    for (double v : q6Seconds) q6Total += v;
    for (std::size_t i = 0; i < mpcd::Q6ProjectionProfilePhaseCount; ++i) {
        const double value = q6Seconds[i];
        const double percent = q6Total > std::numeric_limits<double>::min() ? 100.0 * value / q6Total : 0.0;
        out << "q6_adapter," << mpcd::q6_projection_profile_phase_name(i) << ','
            << value << ',' << (1000.0 * value / steps) << ',' << percent << '\n';
    }
    out << "q6_adapter,total_q6_adapter," << q6Total << ',' << (1000.0 * q6Total / steps) << ",100\n";

    double ellipticTotal = 0.0;
    for (double v : ellipticSeconds) ellipticTotal += v;
    for (std::size_t i = 0; i < mpcd::EllipticProjectionProfilePhaseCount; ++i) {
        const double value = ellipticSeconds[i];
        const double percent = ellipticTotal > std::numeric_limits<double>::min() ? 100.0 * value / ellipticTotal : 0.0;
        out << "elliptic_cg," << mpcd::elliptic_projection_profile_phase_name(i) << ','
            << value << ',' << (1000.0 * value / steps) << ',' << percent << '\n';
    }
    out << "elliptic_cg,total_elliptic_cg," << ellipticTotal << ',' << (1000.0 * ellipticTotal / steps) << ",100\n";
    out << "metadata,q6_applied_steps," << measuredQ6Steps << ",0,0\n";
}


void write_resampling_guard_profile_0166(
    const std::string& outputDir,
    const std::array<double, mpcd::ResamplingPopulationGuardProfilePhaseCount>& populationSeconds,
    const int populationSteps,
    const std::uint64_t populationOverfullCandidateCells,
    const std::uint64_t populationUnderfullCandidateCells,
    const std::uint64_t populationOverfullEditedCells,
    const std::uint64_t populationUnderfullEditedCells,
    const std::array<double, mpcd::ResamplingMassGuardProfilePhaseCount>& massSeconds,
    const int massSteps) {
    const std::filesystem::path path = std::filesystem::path(outputDir) / "resampling_guard_profile_0166.csv";
    std::ofstream out(path);
    out << "group,phase,total_s,ms_per_guard_step,percent_group_total\n";
    out << std::setprecision(17);

    double populationTotal = 0.0;
    for (double v : populationSeconds) populationTotal += v;
    const double populationDenom = populationSteps > 0 ? static_cast<double>(populationSteps) : 1.0;
    for (std::size_t i = 0; i < mpcd::ResamplingPopulationGuardProfilePhaseCount; ++i) {
        const double value = populationSeconds[i];
        const double percent = populationTotal > std::numeric_limits<double>::min()
            ? 100.0 * value / populationTotal : 0.0;
        out << "population_guard," << mpcd::resampling_population_guard_profile_phase_name(i) << ','
            << value << ',' << (1000.0 * value / populationDenom) << ',' << percent << '\n';
    }
    out << "population_guard,total_population_guard," << populationTotal << ','
        << (1000.0 * populationTotal / populationDenom) << ",100\n";
    out << "metadata,population_guard_steps," << populationSteps << ",0,0\n";
    out << "metadata,population_guard_overfull_candidate_cells_total,"
        << populationOverfullCandidateCells << ','
        << (static_cast<double>(populationOverfullCandidateCells) / populationDenom) << ",0\n";
    out << "metadata,population_guard_underfull_candidate_cells_total,"
        << populationUnderfullCandidateCells << ','
        << (static_cast<double>(populationUnderfullCandidateCells) / populationDenom) << ",0\n";
    out << "metadata,population_guard_overfull_edited_cells_total,"
        << populationOverfullEditedCells << ','
        << (static_cast<double>(populationOverfullEditedCells) / populationDenom) << ",0\n";
    out << "metadata,population_guard_underfull_edited_cells_total,"
        << populationUnderfullEditedCells << ','
        << (static_cast<double>(populationUnderfullEditedCells) / populationDenom) << ",0\n";

    double massTotal = 0.0;
    for (double v : massSeconds) massTotal += v;
    const double massDenom = massSteps > 0 ? static_cast<double>(massSteps) : 1.0;
    for (std::size_t i = 0; i < mpcd::ResamplingMassGuardProfilePhaseCount; ++i) {
        const double value = massSeconds[i];
        const double percent = massTotal > std::numeric_limits<double>::min()
            ? 100.0 * value / massTotal : 0.0;
        out << "mass_guard," << mpcd::resampling_mass_guard_profile_phase_name(i) << ','
            << value << ',' << (1000.0 * value / massDenom) << ',' << percent << '\n';
    }
    out << "mass_guard,total_mass_guard," << massTotal << ','
        << (1000.0 * massTotal / massDenom) << ",100\n";
    out << "metadata,mass_guard_steps," << massSteps << ",0,0\n";
}

int openmp_active_threads() {
    int active = 1;
#ifdef _OPENMP
    #pragma omp parallel
    {
        #pragma omp single
        active = omp_get_num_threads();
    }
#endif
    return active;
}

} // namespace

int main(int argc, char** argv) {
    try {
        if (argc != 2) {
            std::cerr << "Usage: " << argv[0] << " params.kv\n";
            return 2;
        }

        const std::string paramsFile = argv[1];
        mpcd::SimulationParams params = mpcd::read_simulation_params_kv(paramsFile);

#ifdef _OPENMP
        if (params.numThreads > 0) {
            omp_set_num_threads(params.numThreads);
        }
#endif

        const int ompMaxThreads = openmp_max_threads();
        const int ompActiveThreads = openmp_active_threads();

        std::filesystem::create_directories(params.outputDir);
        const std::filesystem::path paramsCopy = std::filesystem::path(params.outputDir) / "params_used.kv";
        std::error_code ec;
        std::filesystem::copy_file(paramsFile, paramsCopy,
                                   std::filesystem::copy_options::overwrite_existing, ec);

        mpcd::ParticleState state = mpcd::read_smpcd_state(params.inputState);
        mpcd::ensure_particle_roles(state, mpcd::ParticleRole::Fluid);
        const mpcd::ParticleRoleCounts initialRoleCounts = mpcd::count_particle_roles(state);
        mpcd::CellGrid grid = mpcd::make_cell_grid(params);
        const mpcd::FluidDomainBounds initialDomain = mpcd::make_fluid_domain_bounds(params, 0.0);
        mpcd::apply_boundary_conditions(state, params, initialDomain, 0u, 0.0);
        mpcd::apply_immersed_solid_reflection(state, params, initialDomain, 0.0);

        mpcd::RuntimeSummaryWriter summary(params.outputDir + "/summary_runtime.csv");
        mpcd::SrcMpcdBaseWorkspace workspace;
        std::array<double, mpcd::StepProfilePhaseCount> phaseProfileSeconds{};
        std::array<double, mpcd::Q6ProjectionProfilePhaseCount> q6ProfileSeconds{};
        std::array<double, mpcd::EllipticProjectionProfilePhaseCount> ellipticProfileSeconds{};
        std::array<double, mpcd::ResamplingPopulationGuardProfilePhaseCount> populationGuardProfileSeconds{};
        std::array<double, mpcd::ResamplingMassGuardProfilePhaseCount> massGuardProfileSeconds{};
        int phaseProfileSteps = 0;
        int q6ProfileSteps = 0;
        int populationGuardProfileSteps = 0;
        int massGuardProfileSteps = 0;
        std::uint64_t populationGuardOverfullCandidateCells = 0;
        std::uint64_t populationGuardUnderfullCandidateCells = 0;
        std::uint64_t populationGuardOverfullEditedCells = 0;
        std::uint64_t populationGuardUnderfullEditedCells = 0;
        const auto t0 = std::chrono::steady_clock::now();

        const std::vector<std::uint32_t> initialCellCount =
            mpcd::compute_cell_counts(state, grid, mpcd::GridShift{}, params);
        const mpcd::ResamplingParticlePoolDiagnostics initialPool =
            mpcd::rebuild_resampling_particle_pool(state, workspace.resamplingPool);
        mpcd::WeightedResamplingDiagnostics initialResampling =
            mpcd::deposit_weighted_real_fluid(state, params, grid, initialDomain, 0.0, mpcd::GridShift{}, workspace.resampling);
        mpcd::attach_resampling_pool_diagnostics(initialResampling, initialPool);
        summary.append(mpcd::compute_runtime_summary(state, params, 0, elapsed_seconds(t0),
                                                     &initialCellCount, nullptr, nullptr, nullptr, nullptr, nullptr, nullptr,
                                                     &initialResampling, ompActiveThreads));
        if (params.dumpStateEvery > 0) {
            mpcd::write_smpcd_state(state_dump_name(params.outputDir, 0), state);
        }


        std::cout << "[src_mpcd_base] Np=" << state.Np
                  << " fluid=" << initialRoleCounts.fluid
                  << " latent=" << initialRoleCounts.latent
                  << " inactive=" << initialRoleCounts.inactive
                  << " grid=" << params.Nx << "x" << params.Ny
                  << " bc=[L:" << params.bcLeft
                  << ", R:" << params.bcRight
                  << ", B:" << params.bcBottom
                  << ", T:" << params.bcTop << "]"
                  << " wallAccommodation=" << params.wallAccommodation
                  << " immersedSolid=" << (params.immersedSolidEnable ? "on" : "off")
                  << " fluid=[" << initialDomain.xMin << "," << initialDomain.xMax
                  << "]x[" << initialDomain.yMin << "," << initialDomain.yMax << "]"
                  << " projection=" << (params.projectionEnable ? params.projectionOperator : std::string("off"))
                  << " resampling=" << (params.resamplingEnable ? std::string("on") : std::string("off"))
                  << " thermostat=" << (params.thermostatEnable ? params.thermostatMode : std::string("off"))
                  << " steps=" << params.nSteps
                  << " threadsActive=" << ompActiveThreads
                  << " threadsMax=" << ompMaxThreads
                  << " outputDir=" << params.outputDir << '\n';

        for (int step = 1; step <= params.nSteps; ++step) {
            const bool collectResamplingDiagnostics =
                (step % params.summaryEvery == 0) || (step == params.nSteps);
            const mpcd::StepResult stepResult = mpcd::run_src_mpcd_base_step(
                state, params, grid, static_cast<std::uint64_t>(step), workspace,
                collectResamplingDiagnostics);
            for (std::size_t phase = 0; phase < mpcd::StepProfilePhaseCount; ++phase) {
                phaseProfileSeconds[phase] += stepResult.profile.seconds[phase];
            }
            ++phaseProfileSteps;
            if (stepResult.q6.applied) {
                for (std::size_t phase = 0; phase < mpcd::Q6ProjectionProfilePhaseCount; ++phase) {
                    q6ProfileSeconds[phase] += stepResult.q6.profile.seconds[phase];
                }
                for (std::size_t phase = 0; phase < mpcd::EllipticProjectionProfilePhaseCount; ++phase) {
                    ellipticProfileSeconds[phase] += stepResult.q6.ellipticProfile.seconds[phase];
                }
                ++q6ProfileSteps;
            }
            if (stepResult.resampling.populationGuardAttempted) {
                for (std::size_t phase = 0; phase < mpcd::ResamplingPopulationGuardProfilePhaseCount; ++phase) {
                    populationGuardProfileSeconds[phase] += stepResult.resampling.populationGuardProfileSeconds[phase];
                }
                populationGuardOverfullCandidateCells += stepResult.resampling.populationGuardOverfullCandidateCells;
                populationGuardUnderfullCandidateCells += stepResult.resampling.populationGuardUnderfullCandidateCells;
                populationGuardOverfullEditedCells += stepResult.resampling.populationGuardOverfullEditedCells;
                populationGuardUnderfullEditedCells += stepResult.resampling.populationGuardUnderfullEditedCells;
                ++populationGuardProfileSteps;
            }
            if (stepResult.resampling.massGuardAttempted) {
                for (std::size_t phase = 0; phase < mpcd::ResamplingMassGuardProfilePhaseCount; ++phase) {
                    massGuardProfileSeconds[phase] += stepResult.resampling.massGuardProfileSeconds[phase];
                }
                ++massGuardProfileSteps;
            }

            if (step % params.summaryEvery == 0 || step == params.nSteps) {
                const double wallTime = elapsed_seconds(t0);
                const auto s = mpcd::compute_runtime_summary(state, params, step, wallTime,
                                                           &workspace.collision.cellCount,
                                                           &stepResult.boundary,
                                                           &stepResult.immersed,
                                                           &stepResult.collision,
                                                           &stepResult.q6,
                                                           &stepResult.capacity,
                                                           &stepResult.thermostat,
                                                           &stepResult.resampling,
                                                           ompActiveThreads);
                summary.append(s);
    std::cout << "\r\033[K[src_mpcd_base] step=" << step
          << "/" << params.nSteps
          << " t=" << std::fixed << std::setprecision(3) << s.time
          << " kBT=" << std::scientific << std::setprecision(3) << s.kBTEstimate
          << " stdN=" << std::fixed << std::setprecision(3) << s.stdN
          << " resM=" << std::scientific << std::setprecision(2) << s.resampMRelRms
          << " q6=" << std::scientific << std::setprecision(2) << s.q6DivAfterProjectedFluxRms
          << " wall=" << std::fixed << std::setprecision(1) << wallTime << "s"
          << std::flush;
            }

            if (params.dumpStateEvery > 0 && (step % params.dumpStateEvery == 0 || step == params.nSteps)) {
                mpcd::write_smpcd_state(state_dump_name(params.outputDir, step), state);
            }
        }

        write_phase_profile_0163(params.outputDir, phaseProfileSeconds, phaseProfileSteps);
        write_q6_cg_profile_0163(params.outputDir, q6ProfileSeconds, ellipticProfileSeconds, q6ProfileSteps);
        write_resampling_guard_profile_0166(params.outputDir,
                                            populationGuardProfileSeconds, populationGuardProfileSteps,
                                            populationGuardOverfullCandidateCells,
                                            populationGuardUnderfullCandidateCells,
                                            populationGuardOverfullEditedCells,
                                            populationGuardUnderfullEditedCells,
                                            massGuardProfileSeconds, massGuardProfileSteps);
        std::cout << "\n[src_mpcd_base] wrote " << params.outputDir << "/phase_profile_0163.csv";
        std::cout << "\n[src_mpcd_base] wrote " << params.outputDir << "/q6_cg_profile_0163.csv";
        std::cout << "\n[src_mpcd_base] wrote " << params.outputDir << "/resampling_guard_profile_0166.csv";
        std::cout << "\n[src_mpcd_base] done\n";
        return 0;
    } catch (const std::exception& e) {
        std::cerr << "Fatal error: " << e.what() << '\n';
        return 1;
    }
}
