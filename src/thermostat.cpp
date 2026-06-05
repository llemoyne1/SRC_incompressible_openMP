#include "thermostat.h"

#ifdef MPCD_ENABLE_CUDA_THERMOSTAT
#include "cuda_cell_thermostat.h"
#endif

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <limits>
#include <stdexcept>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <string>

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

[[maybe_unused]] bool env_flag_enabled(const char* name, const bool fallback = false) {
    const char* v = std::getenv(name);
    if (v == nullptr || *v == '\0') return fallback;
    const std::string s(v);
    return !(s == "0" || s == "false" || s == "FALSE" ||
             s == "off" || s == "OFF" || s == "no" || s == "NO");
}

[[maybe_unused]] int env_int_value(const char* name, const int fallback) {
    const char* v = std::getenv(name);
    if (v == nullptr || *v == '\0') return fallback;
    try {
        return std::stoi(std::string(v));
    } catch (...) {
        return fallback;
    }
}

[[maybe_unused]] double env_double_value(const char* name, const double fallback) {
    const char* v = std::getenv(name);
    if (v == nullptr || *v == '\0') return fallback;
    try {
        return std::stod(std::string(v));
    } catch (...) {
        return fallback;
    }
}

#ifdef MPCD_ENABLE_CUDA_THERMOSTAT
struct CudaThermostatShadowRow {
    std::uint64_t step = 0u;
    std::uint64_t particlesVisited = 0u;
    std::uint64_t fluidParticles = 0u;
    int numCells = 0;
    std::uint64_t cellsRescaledCpu = 0u;
    std::uint64_t cellsRescaledCuda = 0u;
    std::uint64_t particlesRescaledCpu = 0u;
    std::uint64_t particlesRescaledCuda = 0u;
    double cpuKBTBefore = 0.0;
    double cudaKBTBefore = 0.0;
    double cpuKBTAfter = 0.0;
    double cudaKBTAfter = 0.0;
    double cpuScaleMean = 1.0;
    double cudaScaleMean = 1.0;
    double maxAbsVx = 0.0;
    double maxAbsVy = 0.0;
    double rmsV = 0.0;
    std::uint64_t velocityMismatches = 0u;
    double maxDiagDiff = 0.0;
    double uploadSeconds = 0.0;
    double kineticKernelSeconds = 0.0;
    double scaleKernelSeconds = 0.0;
    double applyKernelSeconds = 0.0;
    double downloadSeconds = 0.0;
    double totalSeconds = 0.0;
};

class CudaThermostatShadowAccumulator {
public:
    void set_output_dir(const std::string& dir) {
        if (!dir.empty()) outputDir_ = dir;
    }

    void add(const CudaThermostatShadowRow& row) {
        rows_.push_back(row);
    }

    ~CudaThermostatShadowAccumulator() {
        if (outputDir_.empty() || rows_.empty()) return;
        std::error_code ec;
        std::filesystem::create_directories(outputDir_, ec);
        const std::filesystem::path path = std::filesystem::path(outputDir_) / "cuda_cell_thermostat_shadow_0206.csv";
        std::ofstream out(path);
        if (!out) return;
        out << std::setprecision(17);
        out << "step,particlesVisited,fluidParticles,numCells,"
            << "cellsRescaledCpu,cellsRescaledCuda,particlesRescaledCpu,particlesRescaledCuda,"
            << "cpuKBTBefore,cudaKBTBefore,cpuKBTAfter,cudaKBTAfter,cpuScaleMean,cudaScaleMean,"
            << "maxAbsVx,maxAbsVy,rmsV,velocityMismatches,maxDiagDiff,"
            << "uploadSeconds,kineticKernelSeconds,scaleKernelSeconds,applyKernelSeconds,downloadSeconds,totalSeconds\n";
        for (const auto& r : rows_) {
            out << r.step << ',' << r.particlesVisited << ',' << r.fluidParticles << ',' << r.numCells << ','
                << r.cellsRescaledCpu << ',' << r.cellsRescaledCuda << ','
                << r.particlesRescaledCpu << ',' << r.particlesRescaledCuda << ','
                << r.cpuKBTBefore << ',' << r.cudaKBTBefore << ','
                << r.cpuKBTAfter << ',' << r.cudaKBTAfter << ','
                << r.cpuScaleMean << ',' << r.cudaScaleMean << ','
                << r.maxAbsVx << ',' << r.maxAbsVy << ',' << r.rmsV << ','
                << r.velocityMismatches << ',' << r.maxDiagDiff << ','
                << r.uploadSeconds << ',' << r.kineticKernelSeconds << ','
                << r.scaleKernelSeconds << ',' << r.applyKernelSeconds << ','
                << r.downloadSeconds << ',' << r.totalSeconds << '\n';
        }
    }

private:
    std::string outputDir_;
    std::vector<CudaThermostatShadowRow> rows_;
};

CudaThermostatShadowAccumulator& cuda_thermostat_shadow_accumulator() {
    static CudaThermostatShadowAccumulator acc;
    return acc;
}

double max_diag_diff(const ThermostatDiagnostics& cpu, const ThermostatDiagnostics& cuda) {
    double d = 0.0;
    d = std::max(d, std::abs(static_cast<double>(cpu.cellsRescaled) - static_cast<double>(cuda.cellsRescaled)));
    d = std::max(d, std::abs(static_cast<double>(cpu.particlesRescaled) - static_cast<double>(cuda.particlesRescaled)));
    d = std::max(d, std::abs(cpu.kBTBefore - cuda.kBTBefore));
    d = std::max(d, std::abs(cpu.kBTAfter - cuda.kBTAfter));
    d = std::max(d, std::abs(cpu.scaleMean - cuda.scaleMean));
    d = std::max(d, std::abs(cpu.scaleMin - cuda.scaleMin));
    d = std::max(d, std::abs(cpu.scaleMax - cuda.scaleMax));
    return d;
}

void maybe_validate_cuda_cell_thermostat_shadow(const ParticleState& preState,
                                                const ParticleState& postCpuState,
                                                const SimulationParams& params,
                                                const CellGrid& grid,
                                                const std::vector<int>& cellId,
                                                const ThermostatWorkspace& ws,
                                                std::uint64_t step,
                                                const ThermostatDiagnostics& cpuDiag,
                                                double targetKBT) {
    if (!env_flag_enabled("MPCD_CUDA_THERMOSTAT_SHADOW", false)) return;
    const int every = std::max(1, env_int_value("MPCD_CUDA_THERMOSTAT_SHADOW_EVERY", 1));
    if ((step % static_cast<std::uint64_t>(every)) != 0u) return;

    ParticleState cudaState = preState;
    CudaCellThermostatDiagnostics cudaRaw{};
    CudaCellThermostatOptions opts{};
    opts.threadsPerBlock = std::max(32, env_int_value("MPCD_CUDA_THERMOSTAT_THREADS_PER_BLOCK", 256));

    const ThermostatDiagnostics cudaDiag = cuda_apply_cell_relative_rescale_thermostat_from_moments(
        cudaState, grid.numCells, cellId, ws.cellCount, ws.cellUx, ws.cellUy,
        targetKBT, params.thermostatMinParticles, params.thermostatEpsilon, &cudaRaw, opts);

    CudaThermostatShadowRow row{};
    row.step = step;
    row.particlesVisited = preState.Np;
    row.fluidParticles = cudaRaw.fluidParticles;
    row.numCells = grid.numCells;
    row.cellsRescaledCpu = cpuDiag.cellsRescaled;
    row.cellsRescaledCuda = cudaDiag.cellsRescaled;
    row.particlesRescaledCpu = cpuDiag.particlesRescaled;
    row.particlesRescaledCuda = cudaDiag.particlesRescaled;
    row.cpuKBTBefore = cpuDiag.kBTBefore;
    row.cudaKBTBefore = cudaDiag.kBTBefore;
    row.cpuKBTAfter = cpuDiag.kBTAfter;
    row.cudaKBTAfter = cudaDiag.kBTAfter;
    row.cpuScaleMean = cpuDiag.scaleMean;
    row.cudaScaleMean = cudaDiag.scaleMean;
    row.maxDiagDiff = max_diag_diff(cpuDiag, cudaDiag);
    row.uploadSeconds = cudaRaw.uploadSeconds;
    row.kineticKernelSeconds = cudaRaw.kineticKernelSeconds;
    row.scaleKernelSeconds = cudaRaw.scaleKernelSeconds;
    row.applyKernelSeconds = cudaRaw.applyKernelSeconds;
    row.downloadSeconds = cudaRaw.downloadSeconds;
    row.totalSeconds = cudaRaw.totalSeconds;

    const std::size_t n = static_cast<std::size_t>(preState.Np);
    const double tol = env_double_value("MPCD_CUDA_THERMOSTAT_SHADOW_TOL", 1.0e-10);
    double sumSq = 0.0;
    for (std::size_t i = 0; i < n; ++i) {
        const double dvx = std::abs(postCpuState.vx[i] - cudaState.vx[i]);
        const double dvy = std::abs(postCpuState.vy[i] - cudaState.vy[i]);
        row.maxAbsVx = std::max(row.maxAbsVx, dvx);
        row.maxAbsVy = std::max(row.maxAbsVy, dvy);
        sumSq += dvx * dvx + dvy * dvy;
        if (dvx > tol || dvy > tol) ++row.velocityMismatches;
    }
    row.rmsV = n > 0u ? std::sqrt(sumSq / static_cast<double>(2u * n)) : 0.0;

    CudaThermostatShadowAccumulator& acc = cuda_thermostat_shadow_accumulator();
    acc.set_output_dir(params.outputDir);
    acc.add(row);

    const bool strict = env_flag_enabled("MPCD_CUDA_THERMOSTAT_SHADOW_STRICT", true);
    const double diagTol = env_double_value("MPCD_CUDA_THERMOSTAT_SHADOW_DIAG_TOL", 1.0e-10);
    if (strict && (row.velocityMismatches != 0u || row.maxDiagDiff > diagTol)) {
        throw std::runtime_error("CUDA thermostat shadow mismatch: velocityMismatches=" +
                                 std::to_string(row.velocityMismatches) +
                                 " maxAbsVx=" + std::to_string(row.maxAbsVx) +
                                 " maxAbsVy=" + std::to_string(row.maxAbsVy) +
                                 " maxDiagDiff=" + std::to_string(row.maxDiagDiff));
    }
}
#endif

} // namespace

void resize_thermostat_workspace(ThermostatWorkspace& ws,
                                 std::uint64_t numParticles,
                                 int numCells,
                                 int numThreads) {
    if (numCells <= 0) {
        throw std::runtime_error("resize_thermostat_workspace: invalid number of cells");
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

        ws.cellCount.assign(static_cast<std::size_t>(numCells), 0u);
        ws.cellMass.assign(static_cast<std::size_t>(numCells), 0.0);
        ws.cellUx.assign(static_cast<std::size_t>(numCells), 0.0);
        ws.cellUy.assign(static_cast<std::size_t>(numCells), 0.0);
        ws.cellKinetic.assign(static_cast<std::size_t>(numCells), 0.0);
        ws.cellScale.assign(static_cast<std::size_t>(numCells), 1.0);

        const std::size_t localSize = static_cast<std::size_t>(numThreads * numCells);
        ws.localCount.assign(localSize, 0u);
        ws.localMass.assign(localSize, 0.0);
        ws.localPx.assign(localSize, 0.0);
        ws.localPy.assign(localSize, 0.0);
        ws.localKinetic.assign(localSize, 0.0);
    }
}

ThermostatDiagnostics apply_cell_relative_rescale_thermostat(ParticleState& state,
                                                              const SimulationParams& params,
                                                              const CellGrid& grid,
                                                              const std::vector<int>& cellId,
                                                              std::uint64_t step,
                                                              ThermostatWorkspace& ws) {
    validate_particle_state(state, "apply_cell_relative_rescale_thermostat");

    ThermostatDiagnostics diag{};
    if (!params.thermostatEnable) {
        return diag;
    }
    if (params.thermostatEvery <= 0) {
        throw std::runtime_error("thermostatEvery must be positive when thermostatEnable=true");
    }
    if ((step % static_cast<std::uint64_t>(params.thermostatEvery)) != 0u) {
        return diag;
    }
    if (params.thermostatMode != "cell_relative_rescale") {
        throw std::runtime_error("Unsupported thermostatMode: " + params.thermostatMode);
    }
    if (cellId.size() != static_cast<std::size_t>(state.Np)) {
        throw std::runtime_error("Thermostat cellId array has wrong size");
    }

    const double targetKBT = params.thermostatTargetKBT > 0.0 ? params.thermostatTargetKBT : params.kBT;
    if (!(targetKBT > 0.0)) {
        throw std::runtime_error("Thermostat requires positive thermostatTargetKBT or kBT");
    }

    const std::size_t n = static_cast<std::size_t>(state.Np);
    const int nc = grid.numCells;
    const int nt = std::max(1, thread_count());
    resize_thermostat_workspace(ws, state.Np, nc, nt);

    std::fill(ws.cellCount.begin(), ws.cellCount.end(), 0u);
    std::fill(ws.cellMass.begin(), ws.cellMass.end(), 0.0);
    std::fill(ws.cellUx.begin(), ws.cellUx.end(), 0.0);
    std::fill(ws.cellUy.begin(), ws.cellUy.end(), 0.0);
    std::fill(ws.cellKinetic.begin(), ws.cellKinetic.end(), 0.0);
    std::fill(ws.cellScale.begin(), ws.cellScale.end(), 1.0);
    std::fill(ws.localCount.begin(), ws.localCount.end(), 0u);
    std::fill(ws.localMass.begin(), ws.localMass.end(), 0.0);
    std::fill(ws.localPx.begin(), ws.localPx.end(), 0.0);
    std::fill(ws.localPy.begin(), ws.localPy.end(), 0.0);
    std::fill(ws.localKinetic.begin(), ws.localKinetic.end(), 0.0);

#ifdef MPCD_ENABLE_CUDA_THERMOSTAT
    const bool cudaThermostatShadowEnabled = env_flag_enabled("MPCD_CUDA_THERMOSTAT_SHADOW", false);
    ParticleState cudaThermostatPreState;
    if (cudaThermostatShadowEnabled) {
        cudaThermostatPreState = state;
    }
#else
    const bool cudaThermostatShadowEnabled = false;
#endif

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
            const int c = cellId[i];
            if (c < 0 || c >= nc) {
                continue;
            }
            const std::size_t k = offset + static_cast<std::size_t>(c);
            const double m = state.mass[i];
            ws.localCount[k] += 1u;
            ws.localMass[k] += m;
            ws.localPx[k] += m * state.vx[i];
            ws.localPy[k] += m * state.vy[i];
        }
    }

#pragma omp parallel for if(nc > 256)
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
        ws.cellCount[kk] = count;
        ws.cellMass[kk] = mass;
        if (mass > 0.0) {
            ws.cellUx[kk] = px / mass;
            ws.cellUy[kk] = py / mass;
        }
    }

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
            const int c = cellId[i];
            if (c < 0 || c >= nc) {
                continue;
            }
            const std::size_t kk = static_cast<std::size_t>(c);
            const double dvx = state.vx[i] - ws.cellUx[kk];
            const double dvy = state.vy[i] - ws.cellUy[kk];
            ws.localKinetic[offset + kk] += 0.5 * state.mass[i] * (dvx * dvx + dvy * dvy);
        }
    }

    double totalKBefore = 0.0;
    double targetKTotal = 0.0;
    double scaleSum = 0.0;
    double scaleMin = std::numeric_limits<double>::infinity();
    double scaleMax = 0.0;
    std::uint64_t dofTotal = 0u;
    std::uint64_t cellsRescaled = 0u;
    std::uint64_t particlesRescaled = 0u;

#pragma omp parallel for reduction(+:totalKBefore,targetKTotal,scaleSum,dofTotal,cellsRescaled,particlesRescaled) reduction(min:scaleMin) reduction(max:scaleMax) if(nc > 256)
    for (int c = 0; c < nc; ++c) {
        double K = 0.0;
        for (int t = 0; t < nt; ++t) {
            K += ws.localKinetic[static_cast<std::size_t>(t * nc + c)];
        }
        const std::size_t kk = static_cast<std::size_t>(c);
        ws.cellKinetic[kk] = K;

        const std::uint32_t count = ws.cellCount[kk];
        if (count < static_cast<std::uint32_t>(params.thermostatMinParticles)) {
            continue;
        }
        if (!(K > params.thermostatEpsilon)) {
            continue;
        }

        const double dof = 2.0 * static_cast<double>(count - 1u);
        const double targetK = 0.5 * dof * targetKBT;
        const double scale = std::sqrt(targetK / K);
        ws.cellScale[kk] = scale;

        totalKBefore += K;
        targetKTotal += targetK;
        dofTotal += static_cast<std::uint64_t>(2u * (count - 1u));
        cellsRescaled += 1u;
        particlesRescaled += static_cast<std::uint64_t>(count);
        scaleSum += scale;
        if (scale < scaleMin) scaleMin = scale;
        if (scale > scaleMax) scaleMax = scale;
    }

#pragma omp parallel for if(n > 10000)
    for (std::int64_t ii = 0; ii < static_cast<std::int64_t>(n); ++ii) {
        const std::size_t i = static_cast<std::size_t>(ii);
        if (!is_fluid_particle(state, i)) {
            continue;
        }
        const int c = cellId[i];
        if (c < 0 || c >= nc) {
            continue;
        }
        const std::size_t kk = static_cast<std::size_t>(c);
        const double scale = ws.cellScale[kk];
        if (scale == 1.0) {
            continue;
        }
        const double ux = ws.cellUx[kk];
        const double uy = ws.cellUy[kk];
        state.vx[i] = ux + scale * (state.vx[i] - ux);
        state.vy[i] = uy + scale * (state.vy[i] - uy);
    }

    diag.applied = cellsRescaled > 0u;
    diag.cellsRescaled = cellsRescaled;
    diag.particlesRescaled = particlesRescaled;
    diag.kBTBefore = dofTotal > 0u ? (2.0 * totalKBefore / static_cast<double>(dofTotal)) : 0.0;
    diag.kBTAfter = dofTotal > 0u ? (2.0 * targetKTotal / static_cast<double>(dofTotal)) : 0.0;
    diag.scaleMean = cellsRescaled > 0u ? scaleSum / static_cast<double>(cellsRescaled) : 1.0;
    diag.scaleMin = cellsRescaled > 0u ? scaleMin : 1.0;
    diag.scaleMax = cellsRescaled > 0u ? scaleMax : 1.0;

#ifdef MPCD_ENABLE_CUDA_THERMOSTAT
    if (cudaThermostatShadowEnabled) {
        maybe_validate_cuda_cell_thermostat_shadow(cudaThermostatPreState, state, params, grid,
                                                   cellId, ws, step, diag, targetKBT);
    }
#else
    (void)cudaThermostatShadowEnabled;
#endif

    return diag;
}

} // namespace mpcd
