#include "boundary_base.h"
#include "cell_grid.h"
#include "params_io_base.h"
#include "runtime_summary.h"
#include "fluid_domain.h"
#include "immersed_solid.h"
#include "src_mpcd_base.h"
#include "state_smpcd_io.h"

#include <chrono>
#include <exception>
#include <filesystem>
#include <iomanip>
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

bool should_dump_q9_diagnostic_fields(const mpcd::SimulationParams& params, int step) {
    if (!params.q9DiagnosticFieldDumpEnable) {
        return false;
    }
    const int every = params.q9DiagnosticFieldDumpEvery > 0
        ? params.q9DiagnosticFieldDumpEvery
        : params.dumpStateEvery;
    return every > 0 && (step % every == 0 || step == params.nSteps);
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
        mpcd::CellGrid grid = mpcd::make_cell_grid(params);
        const mpcd::FluidDomainBounds initialDomain = mpcd::make_fluid_domain_bounds(params, 0.0);
        mpcd::apply_boundary_conditions(state, params, initialDomain, 0u, 0.0);
        mpcd::apply_immersed_solid_reflection(state, params, initialDomain, 0.0);

        mpcd::RuntimeSummaryWriter summary(params.outputDir + "/summary_runtime.csv");
        mpcd::SrcMpcdBaseWorkspace workspace;
        const auto t0 = std::chrono::steady_clock::now();

        const std::vector<std::uint32_t> initialCellCount =
            mpcd::compute_cell_counts(state, grid, mpcd::GridShift{}, params);
        summary.append(mpcd::compute_runtime_summary(state, params, 0, elapsed_seconds(t0),
                                                     &initialCellCount, nullptr, nullptr, nullptr, nullptr, nullptr, nullptr, nullptr,
                                                     ompActiveThreads));
        if (params.dumpStateEvery > 0) {
            mpcd::write_smpcd_state(state_dump_name(params.outputDir, 0), state);
        }

        if (params.immersedSolidEnable && params.q9ImmersedSolidHaloCells > 0) {
            std::cerr << "[src_mpcd_base] WARNING: q9ImmersedSolidHaloCells="
                      << params.q9ImmersedSolidHaloCells
                      << " enables legacy conservative Q9 halo exclusion near the immersed solid. "
                      << "For nominal face/cell solid-boundary validation, use q9ImmersedSolidHaloCells=0.\n";
        }

        std::cout << "[src_mpcd_base] Np=" << state.Np
                  << " grid=" << params.Nx << "x" << params.Ny
                  << " bc=[L:" << params.bcLeft
                  << ", R:" << params.bcRight
                  << ", B:" << params.bcBottom
                  << ", T:" << params.bcTop << "]"
                  << " wallAccommodation=" << params.wallAccommodation
                  << " immersedSolid=" << (params.immersedSolidEnable ? "on" : "off")
                  << " fluid=[" << initialDomain.xMin << "," << initialDomain.xMax
                  << "]x[" << initialDomain.yMin << "," << initialDomain.yMax << "]"
                  << " method=" << params.method
                  << " projection=" << (params.projectionEnable ? params.projectionOperator : std::string("off"))
                  << " thermostat=" << (params.thermostatEnable ? params.thermostatMode : std::string("off"))
                  << " steps=" << params.nSteps
                  << " threadsActive=" << ompActiveThreads
                  << " threadsMax=" << ompMaxThreads
                  << " outputDir=" << params.outputDir << '\n';

        for (int step = 1; step <= params.nSteps; ++step) {
            const mpcd::StepResult stepResult = mpcd::run_src_mpcd_base_step(
                state, params, grid, static_cast<std::uint64_t>(step), workspace);

            if (step % params.summaryEvery == 0 || step == params.nSteps) {
                const double wallTime = elapsed_seconds(t0);
                const auto s = mpcd::compute_runtime_summary(state, params, step, wallTime,
                                                           &workspace.collision.cellCount,
                                                           &stepResult.boundary,
                                                           &stepResult.immersed,
                                                           &stepResult.collision,
                                                           &stepResult.q6,
                                                           &stepResult.q9,
                                                           &stepResult.virial,
                                                           &stepResult.thermostat,
                                                           ompActiveThreads);
                summary.append(s);
    std::cout << "\r\033[K[src_mpcd_base] step=" << step
          << "/" << params.nSteps
          << " t=" << std::fixed << std::setprecision(3) << s.time
          << " kBT=" << std::scientific << std::setprecision(3) << s.kBTEstimate
          << " stdN=" << std::fixed << std::setprecision(3) << s.stdN
          << " q6=" << std::scientific << std::setprecision(2) << s.q6DivAfterProjectedFluxRms
          << " q9r=" << std::fixed << std::setprecision(4) << s.q9DensityStdRatioEstimate
          << " wall=" << std::fixed << std::setprecision(1) << wallTime << "s"
          << std::flush;
            }

            if (params.dumpStateEvery > 0 && (step % params.dumpStateEvery == 0 || step == params.nSteps)) {
                mpcd::write_smpcd_state(state_dump_name(params.outputDir, step), state);
            }
            if (should_dump_q9_diagnostic_fields(params, step)) {
                mpcd::write_q9_diagnostic_field_dump(params.outputDir, step, params, workspace.q9);
            }
        }

        std::cout << "\n[src_mpcd_base] done\n";
        return 0;
    } catch (const std::exception& e) {
        std::cerr << "Fatal error: " << e.what() << '\n';
        return 1;
    }
}
