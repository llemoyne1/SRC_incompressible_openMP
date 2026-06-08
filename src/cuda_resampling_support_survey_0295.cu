#include "cuda_resampling_support_survey_0295.h"

#if defined(MPCD_ENABLE_CUDA_RESAMPLING) && \
    defined(MPCD_ENABLE_CUDA_PARTICLE_STATE) && \
    defined(MPCD_ENABLE_CUDA_CELL_WORKSPACE) && \
    defined(MPCD_ENABLE_CUDA_CELL_MOMENTS)

#include "cuda_cell_moments.h"
#include "cuda_cell_workspace.h"
#include "cuda_shared_particle_state_0251.h"
#include "immersed_solid.h"

#include <cuda_runtime.h>

#include <algorithm>
#include <chrono>
#include <cstdlib>
#include <cmath>
#include <cctype>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <limits>
#include <stdexcept>
#include <string>
#include <vector>

namespace mpcd {
namespace {

using Clock = std::chrono::steady_clock;

constexpr unsigned char kSurveyFlagActive = 1u << 0u;
constexpr unsigned char kSurveyFlagWet    = 1u << 1u;
constexpr unsigned char kSurveyFlagEmpty  = 1u << 2u;
constexpr unsigned char kSurveyFlagPoor   = 1u << 3u;
constexpr unsigned char kSurveyFlagRich   = 1u << 4u;
constexpr unsigned char kSurveyFlagTarget = 1u << 5u;
constexpr unsigned char kSurveyFlagSolid  = 1u << 6u;

struct DeviceSurveyConfig0295 {
    int nx = 0;
    int ny = 0;
    int numCells = 0;
    double lx = 1.0;
    double ly = 1.0;
    double dx = 1.0;
    double dy = 1.0;

    double domainXMin = 0.0;
    double domainXMax = 1.0;
    double domainYMin = 0.0;
    double domainYMax = 1.0;

    int solidShape = 0; // 0 none, 1 circle, 2 rectangle.
    double circleCx = 0.0;
    double circleCy = 0.0;
    double circleR = 0.0;
    double rectXMin = 0.0;
    double rectXMax = 0.0;
    double rectYMin = 0.0;
    double rectYMax = 0.0;

    double targetMass = 1.0;
    double poorMassFraction = 0.5;
    double richMassFraction = 1.5;
    int nMin = 1;
    int nTarget = 1;
    int nMax = 2;
};

inline double seconds_between(const Clock::time_point a, const Clock::time_point b) {
    return std::chrono::duration<double>(b - a).count();
}

void cuda_check_0295(cudaError_t err, const char* context) {
    if (err != cudaSuccess) {
        throw std::runtime_error(std::string("cuda_resampling_support_survey_0295: ") +
                                 context + ": " + cudaGetErrorString(err));
    }
}

bool env_truthy_0295(const char* name) {
    const char* v = std::getenv(name);
    if (v == nullptr || *v == '\0') return false;
    std::string s(v);
    std::transform(s.begin(), s.end(), s.begin(), [](unsigned char c) {
        return static_cast<char>(std::tolower(c));
    });
    return !(s == "0" || s == "false" || s == "off" || s == "no");
}

int env_int_0295(const char* name, int fallback) {
    const char* v = std::getenv(name);
    if (v == nullptr || *v == '\0') return fallback;
    try {
        return std::stoi(v);
    } catch (...) {
        return fallback;
    }
}

std::string csv_escape_0295(const std::string& s) {
    if (s.find_first_of(",\"\n\r") == std::string::npos) return s;
    std::string out = "\"";
    for (const char ch : s) {
        if (ch == '"') out += "\"\"";
        else out += ch;
    }
    out += "\"";
    return out;
}

__device__ inline double atomic_add_double_compat_0295(double* address, double value) {
#if defined(__CUDA_ARCH__) && (__CUDA_ARCH__ >= 600)
    return atomicAdd(address, value);
#else
    auto* addressAsUll = reinterpret_cast<unsigned long long int*>(address);
    unsigned long long int old = *addressAsUll;
    unsigned long long int assumed;
    do {
        assumed = old;
        old = atomicCAS(addressAsUll,
                        assumed,
                        __double_as_longlong(value + __longlong_as_double(assumed)));
    } while (assumed != old);
    return __longlong_as_double(old);
#endif
}

__device__ bool cell_center_inside_active_domain_0295(int ix, int iy, DeviceSurveyConfig0295 cfg) {
    const double x = (static_cast<double>(ix) + 0.5) * cfg.dx;
    const double y = (static_cast<double>(iy) + 0.5) * cfg.dy;
    if (x < cfg.domainXMin || x > cfg.domainXMax || y < cfg.domainYMin || y > cfg.domainYMax) {
        return false;
    }
    if (cfg.solidShape == 1) {
        const double dx = x - cfg.circleCx;
        const double dy = y - cfg.circleCy;
        return dx * dx + dy * dy >= cfg.circleR * cfg.circleR;
    }
    if (cfg.solidShape == 2) {
        const bool insideRect = x >= cfg.rectXMin && x <= cfg.rectXMax &&
                                y >= cfg.rectYMin && y <= cfg.rectYMax;
        return !insideRect;
    }
    return true;
}

__global__ void reset_krel_kernel_0295(int numCells, double* cellKinetic) {
    const int c = blockIdx.x * blockDim.x + threadIdx.x;
    if (c < numCells) {
        cellKinetic[c] = 0.0;
    }
}

__global__ void accumulate_relative_kinetic_kernel_0295(
    int nParticles,
    const double* __restrict__ vx,
    const double* __restrict__ vy,
    const double* __restrict__ mass,
    const unsigned char* __restrict__ role,
    const int* __restrict__ cellId,
    const double* __restrict__ cellUx,
    const double* __restrict__ cellUy,
    double* __restrict__ cellKinetic) {
    const int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= nParticles) return;
    if (role && role[i] != static_cast<unsigned char>(kParticleRoleFluid)) return;
    const int c = cellId[i];
    if (c < 0) return;
    const double dux = vx[i] - cellUx[c];
    const double duy = vy[i] - cellUy[c];
    const double e = 0.5 * mass[i] * (dux * dux + duy * duy);
    atomic_add_double_compat_0295(&cellKinetic[c], e);
}

__global__ void classify_support_cells_kernel_0295(
    const unsigned int* __restrict__ count,
    const double* __restrict__ mass,
    DeviceSurveyConfig0295 cfg,
    unsigned char* __restrict__ flags) {
    const int c = blockIdx.x * blockDim.x + threadIdx.x;
    if (c >= cfg.numCells) return;
    const int ix = c % cfg.nx;
    const int iy = c / cfg.nx;
    const bool centerInsideDomain =
        (static_cast<double>(ix) + 0.5) * cfg.dx >= cfg.domainXMin &&
        (static_cast<double>(ix) + 0.5) * cfg.dx <= cfg.domainXMax &&
        (static_cast<double>(iy) + 0.5) * cfg.dy >= cfg.domainYMin &&
        (static_cast<double>(iy) + 0.5) * cfg.dy <= cfg.domainYMax;
    const bool active = cell_center_inside_active_domain_0295(ix, iy, cfg);
    const bool solid = centerInsideDomain && !active;
    const unsigned int n = count[c];
    const double m = mass[c];
    const bool wet = active && n > 0u;
    const bool empty = active && n == 0u;
    const bool poor = active && (static_cast<int>(n) < cfg.nMin || m < cfg.targetMass * cfg.poorMassFraction);
    const bool rich = active && (static_cast<int>(n) > cfg.nMax || m > cfg.targetMass * cfg.richMassFraction);
    const bool target = wet && !poor && !rich;

    unsigned char f = 0u;
    if (active) f |= kSurveyFlagActive;
    if (wet) f |= kSurveyFlagWet;
    if (empty) f |= kSurveyFlagEmpty;
    if (poor) f |= kSurveyFlagPoor;
    if (rich) f |= kSurveyFlagRich;
    if (target) f |= kSurveyFlagTarget;
    if (solid) f |= kSurveyFlagSolid;
    flags[c] = f;
}

struct DeviceFlagBuffer0295 {
    unsigned char* d_flags = nullptr;
    std::size_t capacity = 0u;

    ~DeviceFlagBuffer0295() { release(); }

    void release() {
        if (d_flags != nullptr) {
            cudaFree(d_flags);
            d_flags = nullptr;
        }
        capacity = 0u;
    }

    void ensure(std::size_t n) {
        if (n <= capacity) return;
        release();
        cuda_check_0295(cudaMalloc(reinterpret_cast<void**>(&d_flags), n * sizeof(unsigned char)),
                        "malloc support flags");
        capacity = n;
    }
};

thread_local CudaCellWorkspace g_surveyCellWorkspace0295;
thread_local DeviceFlagBuffer0295 g_surveyFlags0295;

DeviceSurveyConfig0295 make_config_0295(const SimulationParams& params,
                                        const CellGrid& grid,
                                        const FluidDomainBounds& domain,
                                        double time) {
    DeviceSurveyConfig0295 cfg{};
    cfg.nx = grid.Nx;
    cfg.ny = grid.Ny;
    cfg.numCells = grid.numCells;
    cfg.lx = grid.Lx;
    cfg.ly = grid.Ly;
    cfg.dx = grid.dx;
    cfg.dy = grid.dy;
    cfg.domainXMin = domain.xMin;
    cfg.domainXMax = domain.xMax;
    cfg.domainYMin = domain.yMin;
    cfg.domainYMax = domain.yMax;

    if (immersed_solid_enabled(params)) {
        const ImmersedSolidShape shape = immersed_solid_shape(params);
        if (shape == ImmersedSolidShape::Circle) {
            cfg.solidShape = 1;
            immersed_solid_circle_center(params, time, cfg.circleCx, cfg.circleCy);
            cfg.circleR = params.immersedSolidR;
        } else if (shape == ImmersedSolidShape::Rectangle) {
            cfg.solidShape = 2;
            immersed_solid_rectangle_bounds(params, time,
                                            cfg.rectXMin, cfg.rectXMax,
                                            cfg.rectYMin, cfg.rectYMax);
        }
    }

    cfg.targetMass = params.resamplingTargetCellMass > 0.0
        ? params.resamplingTargetCellMass
        : std::max(1.0, static_cast<double>(params.inletTargetOccupancy > 0 ? params.inletTargetOccupancy : 1));
    cfg.poorMassFraction = params.resamplingPoorCellMassFraction > 0.0
        ? params.resamplingPoorCellMassFraction : 0.5;
    cfg.richMassFraction = params.resamplingRichCellMassFraction > 0.0
        ? params.resamplingRichCellMassFraction : 1.5;

    const int inferredTarget = std::max(1, static_cast<int>(std::llround(cfg.targetMass)));
    cfg.nTarget = params.resamplingPopulationNTarget > 0 ? params.resamplingPopulationNTarget : inferredTarget;
    cfg.nMin = params.resamplingPopulationNMin > 0
        ? params.resamplingPopulationNMin
        : std::max(1, static_cast<int>(std::floor(params.resamplingPopulationNMinFraction * cfg.nTarget)));
    cfg.nMax = params.resamplingPopulationNMax > 0
        ? params.resamplingPopulationNMax
        : std::max(cfg.nMin, static_cast<int>(std::ceil(params.resamplingPopulationNMaxFraction * cfg.nTarget)));
    return cfg;
}

void write_csv_row_0295(const SimulationParams& params,
                        CudaResamplingSupportSurvey0295Diagnostics& d) {
    std::filesystem::create_directories(params.outputDir);
    const std::filesystem::path path = std::filesystem::path(params.outputDir) /
        "cuda_resampling_support_survey_0295.csv";
    const bool needHeader = !std::filesystem::exists(path) || std::filesystem::file_size(path) == 0u;
    std::ofstream out(path, std::ios::app);
    if (!out) return;
    d.outputCsv = path.string();
    if (needHeader) {
        out << "step,stage,handled,cudaAvailable,sharedStateFreshBefore,uploadedHostState,"
               "particles,fluidParticles,cells,activeCells,solidCells,wetCells,emptyCells,poorCells,richCells,targetBandCells,"
               "totalMass,totalPx,totalPy,meanNActive,stdNActive,minNWet,maxNWet,meanMassWet,minMassWet,maxMassWet,massRelRmsWet,"
               "relativeKineticEnergy,kBTWeighted,depositUploadSeconds,depositKernelSeconds,depositDownloadSeconds,"
               "surveyKernelSeconds,surveyDownloadSeconds,totalSeconds\n";
    }
    out << std::setprecision(17)
        << d.step << ','
        << csv_escape_0295(d.stage) << ','
        << (d.handled ? 1 : 0) << ','
        << (d.cudaAvailable ? 1 : 0) << ','
        << (d.sharedStateFreshBefore ? 1 : 0) << ','
        << (d.uploadedHostState ? 1 : 0) << ','
        << d.particles << ',' << d.fluidParticles << ',' << d.cells << ','
        << d.activeCells << ',' << d.solidCells << ',' << d.wetCells << ','
        << d.emptyCells << ',' << d.poorCells << ',' << d.richCells << ',' << d.targetBandCells << ','
        << d.totalMass << ',' << d.totalPx << ',' << d.totalPy << ','
        << d.meanNActive << ',' << d.stdNActive << ',' << d.minNWet << ',' << d.maxNWet << ','
        << d.meanMassWet << ',' << d.minMassWet << ',' << d.maxMassWet << ',' << d.massRelRmsWet << ','
        << d.relativeKineticEnergy << ',' << d.kBTWeighted << ','
        << d.depositUploadSeconds << ',' << d.depositKernelSeconds << ',' << d.depositDownloadSeconds << ','
        << d.surveyKernelSeconds << ',' << d.surveyDownloadSeconds << ',' << d.totalSeconds << '\n';
}

} // namespace

bool cuda_resampling_support_survey_0295_requested(std::uint64_t step) {
    if (!env_truthy_0295("MPCD_CUDA_RESAMPLING_SUPPORT_SURVEY_0295")) return false;
    const int every = std::max(1, env_int_0295("MPCD_CUDA_RESAMPLING_SUPPORT_SURVEY_0295_EVERY", 1));
    return (step % static_cast<std::uint64_t>(every)) == 0u;
}

CudaResamplingSupportSurvey0295Diagnostics try_run_cuda_resampling_support_survey_0295(
    const ParticleState& hostMirror,
    const SimulationParams& params,
    const CellGrid& grid,
    const FluidDomainBounds& domain,
    std::uint64_t step,
    double time,
    const char* stage) {
    CudaResamplingSupportSurvey0295Diagnostics d{};
    d.attempted = true;
    d.step = step;
    d.stage = stage != nullptr ? stage : "post_src";
    d.particles = hostMirror.Np;
    const Clock::time_point t0 = Clock::now();

    d.cudaAvailable = cuda_cell_moments_available();
    if (!d.cudaAvailable) {
        write_csv_row_0295(params, d);
        return d;
    }
    if (grid.Nx <= 0 || grid.Ny <= 0 || grid.numCells != grid.Nx * grid.Ny) {
        throw std::runtime_error("cuda_resampling_support_survey_0295: invalid grid");
    }

    d.sharedStateFreshBefore = cuda_shared_particle_state_0251_is_fresh();
    if (!d.sharedStateFreshBefore) {
        CudaParticleStateDiagnostics uploadDiag{};
        cuda_shared_particle_state_0251().upload_all(hostMirror, &uploadDiag);
        cuda_shared_particle_state_0251_mark_fresh("cuda_resampling_support_survey_0295_host_upload");
        d.uploadedHostState = true;
        d.depositUploadSeconds += uploadDiag.allocateSeconds + uploadDiag.uploadSeconds;
    }

    CudaCellWorkspaceDiagnostics workspaceDiag{};
    g_surveyCellWorkspace0295.ensure_capacity(hostMirror.Np, grid.numCells, &workspaceDiag);
    d.depositUploadSeconds += workspaceDiag.allocateSeconds;

    CudaCellMoments moments{};
    CudaCellMomentsDiagnostics depositDiag{};
    CudaCellMomentsOptions options{};
    options.threadsPerBlock = std::max(32, env_int_0295("MPCD_CUDA_RESAMPLING_SUPPORT_SURVEY_0295_THREADS", 256));
    options.reuseDeviceBuffers = true;
    options.computeCellVelocities = true;
    options.downloadCellVelocities = true;
    options.enableAllFluidFastPath = false;
    options.enableUniformMassFastPath = false;

    cuda_deposit_cell_moments_atomic_from_persistent_state(
        hostMirror,
        cuda_shared_particle_state_0251(),
        g_surveyCellWorkspace0295,
        grid,
        GridShift{},
        params,
        moments,
        &depositDiag,
        options);
    d.depositUploadSeconds += depositDiag.uploadSeconds;
    d.depositKernelSeconds += depositDiag.kernelSeconds;
    d.depositDownloadSeconds += depositDiag.downloadSeconds;
    // The persistent IO path may leave the host role mirror stale while the
    // device role array is current.  The authoritative fluid count for this
    // survey is therefore reconstructed from the CUDA-deposited cell counts
    // below, not from the host-side fast-path diagnostic.
    d.fluidParticles = 0u;
    d.cells = static_cast<std::uint64_t>(grid.numCells);

    const DeviceSurveyConfig0295 cfg = make_config_0295(params, grid, domain, time);
    CudaCellWorkspaceDeviceView cv = g_surveyCellWorkspace0295.device_view();
    CudaParticleDeviceView pv = cuda_shared_particle_state_0251().device_view();
    if (cv.cellKinetic == nullptr || cv.count == nullptr || cv.cellMass == nullptr ||
        cv.cellPx == nullptr || cv.cellPy == nullptr || cv.cellUx == nullptr || cv.cellUy == nullptr ||
        cv.cellId == nullptr || pv.vx == nullptr || pv.vy == nullptr || pv.mass == nullptr || pv.role == nullptr) {
        throw std::runtime_error("cuda_resampling_support_survey_0295: incomplete persistent device views");
    }

    g_surveyFlags0295.ensure(static_cast<std::size_t>(grid.numCells));
    std::vector<unsigned char> flags(static_cast<std::size_t>(grid.numCells), 0u);
    std::vector<double> cellKinetic(static_cast<std::size_t>(grid.numCells), 0.0);

    const int block = options.threadsPerBlock;
    const int particleGrid = std::max(1, (static_cast<int>(hostMirror.Np) + block - 1) / block);
    const int cellGrid = std::max(1, (grid.numCells + block - 1) / block);

    const Clock::time_point tk0 = Clock::now();
    reset_krel_kernel_0295<<<cellGrid, block>>>(grid.numCells, cv.cellKinetic);
    cuda_check_0295(cudaGetLastError(), "launch reset_krel_kernel_0295");
    accumulate_relative_kinetic_kernel_0295<<<particleGrid, block>>>(
        static_cast<int>(hostMirror.Np), pv.vx, pv.vy, pv.mass, pv.role, cv.cellId,
        cv.cellUx, cv.cellUy, cv.cellKinetic);
    cuda_check_0295(cudaGetLastError(), "launch accumulate_relative_kinetic_kernel_0295");
    classify_support_cells_kernel_0295<<<cellGrid, block>>>(cv.count, cv.cellMass, cfg, g_surveyFlags0295.d_flags);
    cuda_check_0295(cudaGetLastError(), "launch classify_support_cells_kernel_0295");
    cuda_check_0295(cudaDeviceSynchronize(), "synchronize support survey kernels");
    const Clock::time_point tk1 = Clock::now();
    d.surveyKernelSeconds = seconds_between(tk0, tk1);

    const Clock::time_point td0 = Clock::now();
    cuda_check_0295(cudaMemcpy(flags.data(), g_surveyFlags0295.d_flags,
                               flags.size() * sizeof(unsigned char), cudaMemcpyDeviceToHost),
                    "copy support flags D2H");
    cuda_check_0295(cudaMemcpy(cellKinetic.data(), cv.cellKinetic,
                               cellKinetic.size() * sizeof(double), cudaMemcpyDeviceToHost),
                    "copy cell kinetic D2H");
    const Clock::time_point td1 = Clock::now();
    d.surveyDownloadSeconds = seconds_between(td0, td1);

    double sumNActive = 0.0;
    double sumN2Active = 0.0;
    double sumMassWet = 0.0;
    double sumMassRel2Wet = 0.0;
    double minNWet = std::numeric_limits<double>::infinity();
    double maxNWet = 0.0;
    double minMassWet = std::numeric_limits<double>::infinity();
    double maxMassWet = 0.0;
    for (int c = 0; c < grid.numCells; ++c) {
        const std::size_t cc = static_cast<std::size_t>(c);
        const unsigned char f = flags[cc];
        const bool active = (f & kSurveyFlagActive) != 0u;
        const bool wet = (f & kSurveyFlagWet) != 0u;
        if (active) {
            ++d.activeCells;
            const double n = static_cast<double>(moments.cellCount[cc]);
            sumNActive += n;
            sumN2Active += n * n;
        }
        if ((f & kSurveyFlagSolid) != 0u) ++d.solidCells;
        if (wet) {
            ++d.wetCells;
            const double n = static_cast<double>(moments.cellCount[cc]);
            const double m = moments.cellMass[cc];
            minNWet = std::min(minNWet, n);
            maxNWet = std::max(maxNWet, n);
            minMassWet = std::min(minMassWet, m);
            maxMassWet = std::max(maxMassWet, m);
            sumMassWet += m;
            const double rel = cfg.targetMass > 0.0 ? (m - cfg.targetMass) / cfg.targetMass : 0.0;
            sumMassRel2Wet += rel * rel;
        }
        if ((f & kSurveyFlagEmpty) != 0u) ++d.emptyCells;
        if ((f & kSurveyFlagPoor) != 0u) ++d.poorCells;
        if ((f & kSurveyFlagRich) != 0u) ++d.richCells;
        if ((f & kSurveyFlagTarget) != 0u) ++d.targetBandCells;
        d.fluidParticles += static_cast<std::uint64_t>(moments.cellCount[cc]);
        d.totalMass += moments.cellMass[cc];
        d.totalPx += moments.cellPx[cc];
        d.totalPy += moments.cellPy[cc];
        d.relativeKineticEnergy += cellKinetic[cc];
    }
    if (d.activeCells > 0u) {
        const double inv = 1.0 / static_cast<double>(d.activeCells);
        d.meanNActive = sumNActive * inv;
        d.stdNActive = std::sqrt(std::max(0.0, sumN2Active * inv - d.meanNActive * d.meanNActive));
    }
    if (d.wetCells > 0u) {
        d.minNWet = std::isfinite(minNWet) ? minNWet : 0.0;
        d.maxNWet = maxNWet;
        d.meanMassWet = sumMassWet / static_cast<double>(d.wetCells);
        d.minMassWet = std::isfinite(minMassWet) ? minMassWet : 0.0;
        d.maxMassWet = maxMassWet;
        d.massRelRmsWet = std::sqrt(sumMassRel2Wet / static_cast<double>(d.wetCells));
    }
    if (d.fluidParticles > d.wetCells && d.fluidParticles > 0u) {
        // 2D: thermal energy per real particle degree pair gives kBT estimate
        // with cell mean velocity removed.  This is a survey only; no thermostat
        // decision is made here.
        const double dof = 2.0 * static_cast<double>(d.fluidParticles > d.wetCells
            ? d.fluidParticles - d.wetCells : d.fluidParticles);
        if (dof > 0.0) {
            d.kBTWeighted = 2.0 * d.relativeKineticEnergy / dof;
        }
    }

    d.handled = true;
    d.totalSeconds = seconds_between(t0, Clock::now());
    write_csv_row_0295(params, d);
    return d;
}

} // namespace mpcd

#endif
