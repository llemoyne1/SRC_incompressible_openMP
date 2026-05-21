#include "boundary_base.h"
#include "cell_grid.h"
#include "params_io_base.h"
#include "runtime_summary.h"
#include "src_mpcd_base.h"
#include "state_smpcd_io.h"

#include <chrono>
#include <exception>
#include <filesystem>
#include <iomanip>
#include <iostream>
#include <sstream>
#include <string>

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

        std::filesystem::create_directories(params.outputDir);
        const std::filesystem::path paramsCopy = std::filesystem::path(params.outputDir) / "params_used.kv";
        std::error_code ec;
        std::filesystem::copy_file(paramsFile, paramsCopy,
                                   std::filesystem::copy_options::overwrite_existing, ec);

        mpcd::ParticleState state = mpcd::read_smpcd_state(params.inputState);
        mpcd::CellGrid grid = mpcd::make_cell_grid(params);
        mpcd::apply_periodic_boundaries(state, params);

        mpcd::RuntimeSummaryWriter summary(params.outputDir + "/summary_runtime.csv");
        const auto t0 = std::chrono::steady_clock::now();

        summary.append(mpcd::compute_runtime_summary(state, params, 0, elapsed_seconds(t0), nullptr));
        if (params.dumpStateEvery > 0) {
            mpcd::write_smpcd_state(state_dump_name(params.outputDir, 0), state);
        }

        std::cout << "[src_mpcd_base] Np=" << state.Np
                  << " grid=" << params.Nx << "x" << params.Ny
                  << " steps=" << params.nSteps
                  << " outputDir=" << params.outputDir << '\n';

        for (int step = 1; step <= params.nSteps; ++step) {
            mpcd::StepResult result = mpcd::run_src_mpcd_base_step(state, params, grid, static_cast<std::uint64_t>(step));

            if (step % params.summaryEvery == 0 || step == params.nSteps) {
                const double wallTime = elapsed_seconds(t0);
                const auto s = mpcd::compute_runtime_summary(state, params, step, wallTime, &result.collision.cellCount);
                summary.append(s);
                std::cout << "\r[src_mpcd_base] step=" << step
                          << "/" << params.nSteps
                          << " t=" << s.time
                          << " kBT=" << s.kBTEstimate
                          << " stdN=" << s.stdN
                          << " wall=" << wallTime << " s" << std::flush;
            }

            if (params.dumpStateEvery > 0 && (step % params.dumpStateEvery == 0 || step == params.nSteps)) {
                mpcd::write_smpcd_state(state_dump_name(params.outputDir, step), state);
            }
        }

        std::cout << "\n[src_mpcd_base] done\n";
        return 0;
    } catch (const std::exception& e) {
        std::cerr << "Fatal error: " << e.what() << '\n';
        return 1;
    }
}
