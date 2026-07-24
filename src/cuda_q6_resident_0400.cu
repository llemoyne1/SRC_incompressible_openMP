#include "cuda_q6_resident_0400.h"

#if defined(MPCD_ENABLE_CUDA_Q6_RESIDENT_0400)

#include "cuda_cell_workspace.h"
#include "cuda_shared_particle_state_0251.h"
#include "cuda_species_cell_fields_0490h.h"
#include "open_boundary_segments.h"

#include <cuda_runtime.h>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <limits>
#include <stdexcept>
#include <string>
#include <vector>

namespace mpcd {
namespace {

using Clock0400 = std::chrono::steady_clock;

bool truthy_0400(const char* value) {
    if (value == nullptr || *value == '\0') {
        return false;
    }
    const std::string s(value);
    return !(s == "0" || s == "false" || s == "FALSE" ||
             s == "off" || s == "OFF" || s == "no" || s == "NO");
}

int env_int_0400(const char* name, int fallback) {
    const char* value = std::getenv(name);
    if (value == nullptr || *value == '\0') return fallback;
    char* end = nullptr;
    const long parsed = std::strtol(value, &end, 10);
    if (end == value) return fallback;
    return static_cast<int>(parsed);
}

bool cuda_q6_single_block_cg_0407_enabled(int numCells) {
    const char* forced = std::getenv("MPCD_CUDA_Q6_RESIDENT_SINGLE_BLOCK_CG_0407");
    if (forced != nullptr && *forced != '\0') return truthy_0400(forced);
    const int threshold = env_int_0400("MPCD_CUDA_Q6_RESIDENT_SINGLE_BLOCK_CG_MAX_CELLS_0407", 65536);
    return threshold > 0 && numCells <= threshold;
}

bool cuda_q6_warm_start_0408_requested() {
    return truthy_0400(std::getenv("MPCD_CUDA_Q6_RESIDENT_WARM_START_0408"));
}

bool cuda_q6_segmented_io_0409_requested() {
    return truthy_0400(std::getenv("MPCD_CUDA_Q6_RESIDENT_SRC_IO_SEGMENTED_0409"));
}

struct Q6SegmentedIo0409 {
    int enabled = 0;
    int count = 0;
    int face[kOpenBoundaryMaxSegments]{}; // 0 left, 1 right, 2 bottom, 3 top
    double sMin[kOpenBoundaryMaxSegments]{};
    double sMax[kOpenBoundaryMaxSegments]{};
    double flux[kOpenBoundaryMaxSegments]{};
};

bool q6_open_fullface_0404_supported(const SimulationParams& params);
bool q6_open_segmented_0409_supported(const SimulationParams& params);

void check_cuda_0400(cudaError_t err, const char* where) {
    if (err != cudaSuccess) {
        throw std::runtime_error(std::string("cuda_q6_resident_0400 ") + where + ": " +
                                 cudaGetErrorString(err));
    }
}

double seconds_since_0400(const Clock0400::time_point& t0) {
    return std::chrono::duration<double>(Clock0400::now() - t0).count();
}

std::string q6_boundary_family_0491g(const SimulationParams& params) {
    if (q6_open_segmented_0409_supported(params)) return "open_segmented";
    if (q6_open_fullface_0404_supported(params)) return "open_fullface";
    if (is_x_periodic(params) && is_y_periodic(params)) return "periodic";
    if (is_x_periodic(params) && !is_y_periodic(params)) return "channel_wall";
    return "other";
}

void append_species_q6_resident_audit_0491e(
    const SimulationParams& params,
    int step,
    double time,
    int speciesCount,
    const CudaQ6Resident0400Diagnostics& diag) {
    if (!params.speciesQ6Enable || params.outputDir.empty()) return;
    const std::filesystem::path path =
        std::filesystem::path(params.outputDir) / "cuda_species_q6_0491.csv";
    std::filesystem::create_directories(path.parent_path());
    const bool header = !std::filesystem::exists(path) ||
                        std::filesystem::file_size(path) == 0u;
    std::ofstream out(path, std::ios::app);
    if (!out) {
        throw std::runtime_error("0491e failed to open species-Q6 resident audit CSV: " +
                                 path.string());
    }
    if (header) {
        out << "step,time,mode,sensitivity,speciesCount,boundaryFamily,"
               "openBoundaryEnabled,darcyBrinkmanEnable,"
               "species_q6_device_resident,species_q6_host_cell_array_entries,"
               "species_q6_weight_h2d,species_q6_full_state_download,"
               "species_q6_cpu_fallback,species_q6_remaining_cpu_scope,"
               "species_q6_allocated_bytes,species_q6_allocation_calls,"
               "species_q6_metadata_h2d_bytes,"
               "species_q6_deposit_seconds,species_q6_weight_seconds,"
               "species_q6_particle_apply_seconds,"
               "q6Applied,q6Converged,q6Iterations,barycentricResidualMaxAbs,"
               "barycentricResidualMaxScaled,"
               "depositSeconds,solveSeconds,applySeconds,totalSeconds\n";
    }
    out << std::setprecision(17)
        << step << ',' << time << ','
        << '"' << params.speciesQ6Mode << '"' << ','
        << params.speciesQ6Sensitivity << ','
        << speciesCount << ','
        << '"' << q6_boundary_family_0491g(params) << '"' << ','
        << (diag.openBoundaryEnabled ? 1 : 0) << ','
        << (params.darcyBrinkmanEnable ? 1 : 0) << ','
        << 1 << ','  // species-Q6 deposit, weights and correction are device-resident.
        << 0 << ','  // no host cell-species array is materialized by this path.
        << 0 << ','  // weights are derived from resident cell-species masses on device.
        << 0 << ','  // this path never downloads the full particle state.
        << 0 << ','
        << "\"none\","
        << diag.speciesQ6AllocatedBytes << ','
        << diag.speciesQ6AllocationCalls << ','
        << diag.speciesQ6MetadataH2DBytes << ','
        << diag.speciesQ6DepositSeconds << ','
        << diag.speciesQ6WeightSeconds << ','
        << diag.speciesQ6ParticleApplySeconds << ','
        << (diag.applied ? 1 : 0) << ','
        << (diag.converged ? 1 : 0) << ','
        << diag.iterations << ','
        << diag.speciesQ6BarycentricResidualMaxAbs << ','
        << diag.speciesQ6BarycentricResidualMaxScaled << ','
        << diag.depositSeconds << ','
        << diag.solveSeconds << ','
        << diag.applySeconds << ','
        << diag.totalSeconds << '\n';
}

void append_q6_resident_thermostat_audit_0491f(
    const SimulationParams& params,
    std::uint64_t step,
    double targetKBT,
    std::uint64_t cellIdH2DEntries,
    const CudaQ6ResidentThermostat0400Diagnostics& diag) {
    if (!params.speciesQ6Enable || params.outputDir.empty() || !diag.handled) return;
    const std::filesystem::path path =
        std::filesystem::path(params.outputDir) / "cuda_species_q6_energy_0491f.csv";
    std::filesystem::create_directories(path.parent_path());
    const bool header = !std::filesystem::exists(path) ||
                        std::filesystem::file_size(path) == 0u;
    std::ofstream out(path, std::ios::app);
    if (!out) {
        throw std::runtime_error("0491f failed to open species-Q6 energy audit CSV: " +
                                 path.string());
    }
    if (header) {
        out << "step,targetKBT,thermostat_device_resident,thermostat_cpu_fallback,"
               "thermostat_collision_cell_id_h2d_entries,thermostatApplied,"
               "thermostatCells,thermostatParticles,thermostatKBTBefore,"
               "thermostatKBTAfter,thermostatKBTErrorAbs,thermostatScaleMean,"
               "thermostatScaleMin,thermostatScaleMax,kineticSeconds,scaleSeconds,"
               "applySeconds,diagnosticsDownloadSeconds,totalSeconds\n";
    }
    const double kbtError =
        std::abs(diag.thermostat.kBTAfter - targetKBT);
    out << std::setprecision(17)
        << step << ','
        << targetKBT << ','
        << 1 << ','
        << 0 << ','
        << cellIdH2DEntries << ','
        << (diag.thermostat.applied ? 1 : 0) << ','
        << diag.thermostat.cellsRescaled << ','
        << diag.thermostat.particlesRescaled << ','
        << diag.thermostat.kBTBefore << ','
        << diag.thermostat.kBTAfter << ','
        << kbtError << ','
        << diag.thermostat.scaleMean << ','
        << diag.thermostat.scaleMin << ','
        << diag.thermostat.scaleMax << ','
        << diag.kineticSeconds << ','
        << diag.scaleSeconds << ','
        << diag.applySeconds << ','
        << diag.diagnosticsDownloadSeconds << ','
        << diag.totalSeconds << '\n';
}

double inlet_velocity_ramp_factor_0400(const SimulationParams& params, double time) {
    if (!params.inletVelocityRampEnable) return 1.0;
    const double t0 = params.inletVelocityRampStartTime;
    const double t1 = params.inletVelocityRampEndTime;
    if (!(t1 > t0)) return params.inletVelocityRampFinalFactor;
    double a = 0.0;
    if (time <= t0) a = 0.0;
    else if (time >= t1) a = 1.0;
    else a = (time - t0) / (t1 - t0);
    if (params.inletVelocityRampProfile == "smoothstep") {
        a = a * a * (3.0 - 2.0 * a);
    }
    return (1.0 - a) * params.inletVelocityRampInitialFactor +
           a * params.inletVelocityRampFinalFactor;
}

bool q6_wall_like_0409(const std::string& mode) {
    return mode == "solid" || mode == "specular" || mode == "bounceback";
}

int q6_face_code_0409(const std::string& face) {
    if (face == "left") return 0;
    if (face == "right") return 1;
    if (face == "bottom") return 2;
    if (face == "top") return 3;
    return -1;
}

bool q6_open_fullface_0404_supported(const SimulationParams& params) {
    const bool leftInlet = is_inlet_boundary_mode(params.bcLeft);
    const bool rightInlet = is_inlet_boundary_mode(params.bcRight);
    const bool bottomInlet = is_inlet_boundary_mode(params.bcBottom);
    const bool topInlet = is_inlet_boundary_mode(params.bcTop);
    const bool leftOutlet = is_outlet_boundary_mode(params.bcLeft);
    const bool rightOutlet = is_outlet_boundary_mode(params.bcRight);
    const bool bottomOutlet = is_outlet_boundary_mode(params.bcBottom);
    const bool topOutlet = is_outlet_boundary_mode(params.bcTop);
    const bool xPair = ((leftInlet && rightOutlet) || (leftOutlet && rightInlet)) &&
                       q6_wall_like_0409(params.bcBottom) && q6_wall_like_0409(params.bcTop);
    const bool yPair = ((bottomInlet && topOutlet) || (bottomOutlet && topInlet)) &&
                       q6_wall_like_0409(params.bcLeft) && q6_wall_like_0409(params.bcRight);
    return (xPair || yPair) &&
           !params.openBoundarySegmentsEnable && params.openBoundarySegmentCount == 0 &&
           params.inletVelocitySpatialProfile == "uniform" &&
           (params.openBoundaryOutletMode == "balanced_flux" || params.openBoundaryOutletMode == "balanced");
}

void q6_open_fullface_flux_0404(const SimulationParams& params,
                                double time,
                                double& xLowFlux,
                                double& xHighFlux,
                                double& yLowFlux,
                                double& yHighFlux) {
    const double ramp = inlet_velocity_ramp_factor_0400(params, time);
    xLowFlux = 0.0;
    xHighFlux = 0.0;
    yLowFlux = 0.0;
    yHighFlux = 0.0;
    if (is_inlet_boundary_mode(params.bcLeft)) {
        xLowFlux = ramp * params.inletUxLeft;
        xHighFlux = xLowFlux;
    } else if (is_inlet_boundary_mode(params.bcRight)) {
        xHighFlux = ramp * params.inletUxRight;
        xLowFlux = xHighFlux;
    } else if (is_inlet_boundary_mode(params.bcBottom)) {
        yLowFlux = ramp * params.inletUyBottom;
        yHighFlux = yLowFlux;
    } else if (is_inlet_boundary_mode(params.bcTop)) {
        yHighFlux = ramp * params.inletUyTop;
        yLowFlux = yHighFlux;
    }
}

bool q6_open_segmented_0409_supported(const SimulationParams& params) {
    if (!cuda_q6_segmented_io_0409_requested()) return false;
    if (!params.openBoundarySegmentsEnable || params.openBoundarySegmentCount <= 0) return false;
    if (static_cast<int>(params.openBoundarySegments.size()) != params.openBoundarySegmentCount) return false;
    if (params.openBoundarySegmentCount > kOpenBoundaryMaxSegments) return false;
    if (!q6_wall_like_0409(params.bcLeft) || !q6_wall_like_0409(params.bcRight) ||
        !q6_wall_like_0409(params.bcBottom) || !q6_wall_like_0409(params.bcTop)) return false;
    if (params.inletVelocitySpatialProfile != "uniform") return false;
    if (!(params.openBoundaryOutletMode == "neumann" ||
          params.openBoundaryOutletMode == "balanced_flux" ||
          params.openBoundaryOutletMode == "balanced" ||
          params.openBoundaryOutletMode == "hybrid")) return false;
    bool hasInlet = false;
    bool hasOutlet = false;
    for (const OpenBoundarySegment& seg : params.openBoundarySegments) {
        if (q6_face_code_0409(seg.face) < 0) return false;
        if (!(seg.sMin >= 0.0 && seg.sMax <= 1.0 && seg.sMax >= seg.sMin)) return false;
        if (open_boundary_segment_is_inlet(seg)) hasInlet = true;
        else if (open_boundary_segment_is_outlet(seg)) hasOutlet = true;
        else return false;
        if (!(std::isfinite(seg.ux) && std::isfinite(seg.uy))) return false;
        if (open_boundary_face_is_x(seg.face) && std::abs(seg.uy) > 1.0e-15) return false;
        if (open_boundary_face_is_y(seg.face) && std::abs(seg.ux) > 1.0e-15) return false;
    }
    return hasInlet && hasOutlet;
}

Q6SegmentedIo0409 q6_make_segmented_0409(const SimulationParams& params, double time) {
    Q6SegmentedIo0409 cfg{};
    if (!q6_open_segmented_0409_supported(params)) return cfg;
    const double ramp = inlet_velocity_ramp_factor_0400(params, time);
    cfg.enabled = 1;
    cfg.count = std::min(static_cast<int>(params.openBoundarySegments.size()), kOpenBoundaryMaxSegments);
    for (int k = 0; k < cfg.count; ++k) {
        const OpenBoundarySegment& seg = params.openBoundarySegments[static_cast<std::size_t>(k)];
        cfg.face[k] = q6_face_code_0409(seg.face);
        cfg.sMin[k] = seg.sMin;
        cfg.sMax[k] = seg.sMax;
        cfg.flux[k] = ramp * (open_boundary_face_is_x(seg.face) ? seg.ux : seg.uy);
    }
    return cfg;
}

double q6_segmented_flux_integral_0409(const Q6SegmentedIo0409& cfg, int face, double length) {
    if (!cfg.enabled || !(length > 0.0)) return 0.0;
    double flux = 0.0;
    for (int k = 0; k < cfg.count; ++k) {
        if (cfg.face[k] == face) flux += cfg.flux[k] * std::max(0.0, cfg.sMax[k] - cfg.sMin[k]) * length;
    }
    return flux;
}

template <typename T>
class DeviceBuffer0400 {
public:
    DeviceBuffer0400() = default;
    ~DeviceBuffer0400() { release(); }
    DeviceBuffer0400(const DeviceBuffer0400&) = delete;
    DeviceBuffer0400& operator=(const DeviceBuffer0400&) = delete;

    void release() {
        if (ptr_ != nullptr) {
            cudaFree(ptr_);
            ptr_ = nullptr;
            capacity_ = 0u;
        }
    }

    void ensure(std::size_t n) {
        if (n <= capacity_) {
            return;
        }
        release();
        check_cuda_0400(cudaMalloc(reinterpret_cast<void**>(&ptr_), n * sizeof(T)), "cudaMalloc");
        capacity_ = n;
    }

    T* data() { return ptr_; }
    const T* data() const { return ptr_; }

private:
    T* ptr_ = nullptr;
    std::size_t capacity_ = 0u;
};

struct ResidentWorkspace0400 {
    CudaCellWorkspace cells;
    DeviceBuffer0400<double> rhs;
    DeviceBuffer0400<double> phi;
    DeviceBuffer0400<double> r;
    DeviceBuffer0400<double> p;
    DeviceBuffer0400<double> Ap;
    DeviceBuffer0400<double> dux;
    DeviceBuffer0400<double> duy;
    DeviceBuffer0400<double> partial0;
    DeviceBuffer0400<double> partial1;
    DeviceBuffer0400<double> partial2;
    DeviceBuffer0400<unsigned long long> counter;
    bool warmPhiValid = false;
    int warmNx = 0;
    int warmNy = 0;
    int warmPeriodicX = 0;
    int warmPeriodicY = 0;

    void ensure(std::uint64_t particles, int numCells, int blocks) {
        cells.ensure_capacity(particles, numCells);
        const std::size_t c = static_cast<std::size_t>(std::max(1, numCells));
        rhs.ensure(c);
        phi.ensure(c);
        r.ensure(c);
        p.ensure(c);
        Ap.ensure(c);
        dux.ensure(c);
        duy.ensure(c);
        partial0.ensure(static_cast<std::size_t>(std::max(1, blocks)));
        partial1.ensure(static_cast<std::size_t>(std::max(1, blocks)));
        partial2.ensure(static_cast<std::size_t>(std::max(1, blocks)));
        counter.ensure(1u);
    }
};

ResidentWorkspace0400& resident_workspace_0400() {
    static ResidentWorkspace0400 ws;
    return ws;
}

__device__ double atomic_add_double_0400(double* address, double value) {
#if __CUDA_ARCH__ >= 600
    return atomicAdd(address, value);
#else
    unsigned long long int* addressAsUll = reinterpret_cast<unsigned long long int*>(address);
    unsigned long long int old = *addressAsUll;
    unsigned long long int assumed = 0ull;
    do {
        assumed = old;
        old = atomicCAS(addressAsUll,
                        assumed,
                        __double_as_longlong(value + __longlong_as_double(assumed)));
    } while (assumed != old);
    return __longlong_as_double(old);
#endif
}

__global__ void q6_zero_cells_0400(CudaCellWorkspaceDeviceView cells,
                                   double* rhs,
                                   double* phi,
                                   double* r,
                                   double* p,
                                   double* Ap,
                                   double* dux,
                                   double* duy,
                                   int resetPhi) {
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    const int stride = blockDim.x * gridDim.x;
    for (int c = idx; c < cells.numCells; c += stride) {
        cells.count[c] = 0u;
        cells.cellMass[c] = 0.0;
        cells.cellPx[c] = 0.0;
        cells.cellPy[c] = 0.0;
        cells.cellUx[c] = 0.0;
        cells.cellUy[c] = 0.0;
        rhs[c] = 0.0;
        if (resetPhi) phi[c] = 0.0;
        r[c] = 0.0;
        p[c] = 0.0;
        Ap[c] = 0.0;
        dux[c] = 0.0;
        duy[c] = 0.0;
    }
}

__global__ void q6_zero_particle_cell_ids_0400(CudaCellWorkspaceDeviceView cells,
                                              std::uint64_t nParticles) {
    const std::uint64_t idx = blockIdx.x * blockDim.x + threadIdx.x;
    const std::uint64_t stride = static_cast<std::uint64_t>(blockDim.x) * gridDim.x;
    for (std::uint64_t i = idx; i < nParticles; i += stride) {
        cells.cellId[i] = -1;
    }
}

__device__ int wrap_cell_index_0400(int i, int n) {
    if (i < 0) {
        return i + n;
    }
    if (i >= n) {
        return i - n;
    }
    return i;
}

__global__ void q6_deposit_periodic_0400(CudaParticleDeviceView particles,
                                         CudaCellWorkspaceDeviceView cells,
                                         std::uint64_t nParticles,
                                         int nx,
                                         int ny,
                                         double lx,
                                         double ly,
                                         int periodicX,
                                         int periodicY) {
    const std::uint64_t idx = blockIdx.x * blockDim.x + threadIdx.x;
    const std::uint64_t stride = static_cast<std::uint64_t>(blockDim.x) * gridDim.x;
    const double dx = lx / static_cast<double>(nx);
    const double dy = ly / static_cast<double>(ny);
    for (std::uint64_t i = idx; i < nParticles; i += stride) {
        if (particles.role != nullptr && particles.role[i] != kParticleRoleFluid) {
            continue;
        }
        double x = particles.x[i];
        double y = particles.y[i];
        if (periodicX) {
            x -= floor(x / lx) * lx;
        } else {
            x = fmin(fmax(x, 0.0), nextafter(lx, 0.0));
        }
        if (periodicY) {
            y -= floor(y / ly) * ly;
        } else {
            y = fmin(fmax(y, 0.0), nextafter(ly, 0.0));
        }
        int ix = static_cast<int>(floor(x / dx));
        int iy = static_cast<int>(floor(y / dy));
        if (periodicX) {
            ix = wrap_cell_index_0400(ix, nx);
        } else {
            if (ix < 0) ix = 0;
            if (ix >= nx) ix = nx - 1;
        }
        if (periodicY) {
            iy = wrap_cell_index_0400(iy, ny);
        } else {
            if (iy < 0) iy = 0;
            if (iy >= ny) iy = ny - 1;
        }
        const int c = iy * nx + ix;
        const double m = particles.mass ? particles.mass[i] : 1.0;
        cells.cellId[i] = c;
        atomicAdd(&cells.count[c], 1u);
        atomic_add_double_0400(&cells.cellMass[c], m);
        atomic_add_double_0400(&cells.cellPx[c], m * particles.vx[i]);
        atomic_add_double_0400(&cells.cellPy[c], m * particles.vy[i]);
    }
}

__global__ void q6_finalize_cells_0400(CudaCellWorkspaceDeviceView cells,
                                       unsigned long long* emptyCounter) {
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    const int stride = blockDim.x * gridDim.x;
    for (int c = idx; c < cells.numCells; c += stride) {
        const double m = cells.cellMass[c];
        if (m > 0.0) {
            cells.cellUx[c] = cells.cellPx[c] / m;
            cells.cellUy[c] = cells.cellPy[c] / m;
        } else {
            cells.cellUx[c] = 0.0;
            cells.cellUy[c] = 0.0;
            atomicAdd(emptyCounter, 1ull);
        }
    }
}

__device__ double q6_segmented_flux_for_cell_0409(const Q6SegmentedIo0409& cfg,
                                                        int face,
                                                        int ix,
                                                        int iy,
                                                        int nx,
                                                        int ny,
                                                        double fallback) {
    if (!cfg.enabled) return fallback;
    const double s = (face == 0 || face == 1)
        ? ((static_cast<double>(iy) + 0.5) / static_cast<double>(ny > 0 ? ny : 1))
        : ((static_cast<double>(ix) + 0.5) / static_cast<double>(nx > 0 ? nx : 1));
    for (int k = 0; k < cfg.count; ++k) {
        if (cfg.face[k] == face && s >= cfg.sMin[k] && s <= cfg.sMax[k]) {
            return cfg.flux[k];
        }
    }
    return 0.0;
}

__global__ void q6_build_rhs_and_stats_0400(CudaCellWorkspaceDeviceView cells,
                                           double* rhs,
                                           double* partialSum,
                                           double* partialSq,
                                           double* partialMax,
                                           int nx,
                                           int ny,
                                           double dx,
                                           double dy,
                                           int periodicX,
                                           int periodicY,
                                           double xLowFlux,
                                           double xHighFlux,
                                           double yLowFlux,
                                           double yHighFlux,
                                           Q6SegmentedIo0409 segmentedIo) {
    extern __shared__ double sh[];
    double* sh0 = sh;
    double* sh1 = sh + blockDim.x;
    double* sh2 = sh + 2 * blockDim.x;
    const int tid = threadIdx.x;
    double sum = 0.0;
    double sq = 0.0;
    double mx = 0.0;
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    const int stride = blockDim.x * gridDim.x;
    for (int c = idx; c < cells.numCells; c += stride) {
        const int ix = c % nx;
        const int iy = c / nx;
        const int west = (periodicX || ix > 0) ? (iy * nx + (periodicX ? wrap_cell_index_0400(ix - 1, nx) : (ix - 1))) : c;
        const int south = (periodicY || iy > 0) ? ((periodicY ? wrap_cell_index_0400(iy - 1, ny) : (iy - 1)) * nx + ix) : c;
        const double localXLowFlux = q6_segmented_flux_for_cell_0409(segmentedIo, 0, ix, iy, nx, ny, xLowFlux);
        const double localXHighFlux = q6_segmented_flux_for_cell_0409(segmentedIo, 1, ix, iy, nx, ny, xHighFlux);
        const double localYLowFlux = q6_segmented_flux_for_cell_0409(segmentedIo, 2, ix, iy, nx, ny, yLowFlux);
        const double localYHighFlux = q6_segmented_flux_for_cell_0409(segmentedIo, 3, ix, iy, nx, ny, yHighFlux);
        const double fxWest = (periodicX || ix > 0) ? cells.cellUx[west] : localXLowFlux;
        const double fxEastBefore = cells.cellUx[c];
        const double fxEastSolve = (periodicX || ix < nx - 1) ? cells.cellUx[c] : localXHighFlux;
        const double fySouth = (periodicY || iy > 0) ? cells.cellUy[south] : localYLowFlux;
        const double divBefore = (fxEastBefore - fxWest) / dx +
                                 (cells.cellUy[c] - fySouth) / dy;
        const double fyNorthSolve = (periodicY || iy < ny - 1) ? cells.cellUy[c] : localYHighFlux;
        const double divSolve = (fxEastSolve - fxWest) / dx +
                                (fyNorthSolve - fySouth) / dy;
        rhs[c] = -divSolve;
        sum += rhs[c];
        sq += divBefore * divBefore;
        mx = fmax(mx, fabs(divBefore));
    }
    sh0[tid] = sum;
    sh1[tid] = sq;
    sh2[tid] = mx;
    __syncthreads();
    for (int offset = blockDim.x / 2; offset > 0; offset >>= 1) {
        if (tid < offset) {
            sh0[tid] += sh0[tid + offset];
            sh1[tid] += sh1[tid + offset];
            sh2[tid] = fmax(sh2[tid], sh2[tid + offset]);
        }
        __syncthreads();
    }
    if (tid == 0) {
        partialSum[blockIdx.x] = sh0[0];
        partialSq[blockIdx.x] = sh1[0];
        partialMax[blockIdx.x] = sh2[0];
    }
}

__global__ void q6_init_cg_0400(double* rhs,
                                double* phi,
                                double* r,
                                double* p,
                                double mean,
                                int n) {
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    const int stride = blockDim.x * gridDim.x;
    for (int c = idx; c < n; c += stride) {
        const double v = rhs[c] - mean;
        rhs[c] = v;
        phi[c] = 0.0;
        r[c] = v;
        p[c] = v;
    }
}

__global__ void q6_apply_operator_and_dot_0400(const double* p,
                                               double* Ap,
                                               double* partialDot,
                                               int nx,
                                               int ny,
                                               double invDx2,
                                               double invDy2,
                                               int periodicX,
                                               int periodicY) {
    extern __shared__ double sh[];
    const int tid = threadIdx.x;
    double dot = 0.0;
    const int n = nx * ny;
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    const int stride = blockDim.x * gridDim.x;
    for (int c = idx; c < n; c += stride) {
        const int ix = c % nx;
        const int iy = c / nx;
        const int east = (periodicX || ix < nx - 1) ? (iy * nx + (periodicX ? wrap_cell_index_0400(ix + 1, nx) : (ix + 1))) : c;
        const int west = (periodicX || ix > 0) ? (iy * nx + (periodicX ? wrap_cell_index_0400(ix - 1, nx) : (ix - 1))) : c;
        const int north = (periodicY || iy < ny - 1) ? ((periodicY ? wrap_cell_index_0400(iy + 1, ny) : (iy + 1)) * nx + ix) : c;
        const int south = (periodicY || iy > 0) ? ((periodicY ? wrap_cell_index_0400(iy - 1, ny) : (iy - 1)) * nx + ix) : c;
        const double a = ((periodicX || ix < nx - 1) ? invDx2 * (p[c] - p[east]) : 0.0) +
                         ((periodicX || ix > 0) ? invDx2 * (p[c] - p[west]) : 0.0) +
                         ((periodicY || iy < ny - 1) ? invDy2 * (p[c] - p[north]) : 0.0) +
                         ((periodicY || iy > 0) ? invDy2 * (p[c] - p[south]) : 0.0);
        Ap[c] = a;
        dot += p[c] * a;
    }
    sh[tid] = dot;
    __syncthreads();
    for (int offset = blockDim.x / 2; offset > 0; offset >>= 1) {
        if (tid < offset) {
            sh[tid] += sh[tid + offset];
        }
        __syncthreads();
    }
    if (tid == 0) {
        partialDot[blockIdx.x] = sh[0];
    }
}

__global__ void q6_reduce_square_sum_0400(const double* v,
                                          double* partial,
                                          int n) {
    extern __shared__ double sh[];
    const int tid = threadIdx.x;
    double sum = 0.0;
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    const int stride = blockDim.x * gridDim.x;
    for (int i = idx; i < n; i += stride) {
        sum += v[i] * v[i];
    }
    sh[tid] = sum;
    __syncthreads();
    for (int offset = blockDim.x / 2; offset > 0; offset >>= 1) {
        if (tid < offset) {
            sh[tid] += sh[tid + offset];
        }
        __syncthreads();
    }
    if (tid == 0) {
        partial[blockIdx.x] = sh[0];
    }
}

__global__ void q6_reduce_sum_0400(const double* v,
                                   double* partial,
                                   int n) {
    extern __shared__ double sh[];
    const int tid = threadIdx.x;
    double sum = 0.0;
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    const int stride = blockDim.x * gridDim.x;
    for (int i = idx; i < n; i += stride) {
        sum += v[i];
    }
    sh[tid] = sum;
    __syncthreads();
    for (int offset = blockDim.x / 2; offset > 0; offset >>= 1) {
        if (tid < offset) {
            sh[tid] += sh[tid + offset];
        }
        __syncthreads();
    }
    if (tid == 0) {
        partial[blockIdx.x] = sh[0];
    }
}

__global__ void q6_axpy_residual_0400(double* phi,
                                      double* r,
                                      const double* p,
                                      const double* Ap,
                                      double alpha,
                                      int n) {
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    const int stride = blockDim.x * gridDim.x;
    for (int i = idx; i < n; i += stride) {
        phi[i] += alpha * p[i];
        r[i] -= alpha * Ap[i];
    }
}

__global__ void q6_update_p_0400(double* p,
                                 const double* r,
                                 double beta,
                                 int n) {
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    const int stride = blockDim.x * gridDim.x;
    for (int i = idx; i < n; i += stride) {
        p[i] = r[i] + beta * p[i];
    }
}

__global__ void q6_subtract_mean_pair_0400(double* a,
                                           double* b,
                                           double meanA,
                                           double meanB,
                                           int n) {
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    const int stride = blockDim.x * gridDim.x;
    for (int i = idx; i < n; i += stride) {
        a[i] -= meanA;
        b[i] -= meanB;
    }
}

__global__ void q6_compute_corrections_0400(CudaCellWorkspaceDeviceView cells,
                                            const double* phi,
                                            double* dux,
                                            double* duy,
                                            double* partialSq,
                                            double* partialMax,
                                            int nx,
                                            int ny,
                                            double dx,
                                            double dy,
                                            double strength,
                                            int periodicX,
                                            int periodicY,
                                            double xHighFlux,
                                            double yHighFlux,
                                            Q6SegmentedIo0409 segmentedIo) {
    extern __shared__ double sh[];
    double* shSq = sh;
    double* shMax = sh + blockDim.x;
    const int tid = threadIdx.x;
    double sq = 0.0;
    double mx = 0.0;
    const int n = nx * ny;
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    const int stride = blockDim.x * gridDim.x;
    for (int c = idx; c < n; c += stride) {
        const int ix = c % nx;
        const int iy = c / nx;
        const int east = (periodicX || ix < nx - 1) ? (iy * nx + (periodicX ? wrap_cell_index_0400(ix + 1, nx) : (ix + 1))) : c;
        const int north = (periodicY || iy < ny - 1) ? ((periodicY ? wrap_cell_index_0400(iy + 1, ny) : (iy + 1)) * nx + ix) : c;
        const double localXHighFlux = q6_segmented_flux_for_cell_0409(segmentedIo, 1, ix, iy, nx, ny, xHighFlux);
        const double localYHighFlux = q6_segmented_flux_for_cell_0409(segmentedIo, 3, ix, iy, nx, ny, yHighFlux);
        const double cx = (periodicX || ix < nx - 1) ?
            (-strength * (phi[east] - phi[c]) / dx) :
            (strength * (localXHighFlux - cells.cellUx[c]));
        const double cy = (periodicY || iy < ny - 1) ?
            (-strength * (phi[north] - phi[c]) / dy) :
            (strength * (localYHighFlux - cells.cellUy[c]));
        dux[c] = cx;
        duy[c] = cy;
        sq += cx * cx + cy * cy;
        mx = fmax(mx, sqrt(cx * cx + cy * cy));
    }
    shSq[tid] = sq;
    shMax[tid] = mx;
    __syncthreads();
    for (int offset = blockDim.x / 2; offset > 0; offset >>= 1) {
        if (tid < offset) {
            shSq[tid] += shSq[tid + offset];
            shMax[tid] = fmax(shMax[tid], shMax[tid + offset]);
        }
        __syncthreads();
    }
    if (tid == 0) {
        partialSq[blockIdx.x] = shSq[0];
        partialMax[blockIdx.x] = shMax[0];
    }
}

__global__ void q6_apply_particle_correction_0400(CudaParticleDeviceView particles,
                                                  CudaCellWorkspaceDeviceView cells,
                                                  const double* dux,
                                                  const double* duy,
                                                  std::uint64_t nParticles,
                                                  double* partialPx,
                                                  double* partialPy) {
    extern __shared__ double sh[];
    double* shX = sh;
    double* shY = sh + blockDim.x;
    const int tid = threadIdx.x;
    double px = 0.0;
    double py = 0.0;
    const std::uint64_t idx = blockIdx.x * blockDim.x + threadIdx.x;
    const std::uint64_t stride = static_cast<std::uint64_t>(blockDim.x) * gridDim.x;
    for (std::uint64_t i = idx; i < nParticles; i += stride) {
        if (particles.role != nullptr && particles.role[i] != kParticleRoleFluid) {
            continue;
        }
        const int c = cells.cellId[i];
        if (c < 0) {
            continue;
        }
        const double dvx = dux[c];
        const double dvy = duy[c];
        particles.vx[i] += dvx;
        particles.vy[i] += dvy;
        const double m = particles.mass ? particles.mass[i] : 1.0;
        px += m * dvx;
        py += m * dvy;
    }
    shX[tid] = px;
    shY[tid] = py;
    __syncthreads();
    for (int offset = blockDim.x / 2; offset > 0; offset >>= 1) {
        if (tid < offset) {
            shX[tid] += shX[tid + offset];
            shY[tid] += shY[tid + offset];
        }
        __syncthreads();
    }
    if (tid == 0) {
        partialPx[blockIdx.x] = shX[0];
        partialPy[blockIdx.x] = shY[0];
    }
}

__global__ void q6_reset_species_mass_0491c(CudaSpeciesCellDeviceView0490h species) {
    const int tid = blockIdx.x * blockDim.x + threadIdx.x;
    const int stride = blockDim.x * gridDim.x;
    const int dense = species.numCells * species.speciesCount;
    for (int k = tid; k < dense; k += stride) {
        species.mass[k] = 0.0;
    }
    for (int c = tid; c < species.numCells; c += stride) {
        species.totalCellMass[c] = 0.0;
    }
    if (tid == 0 && species.invalidTypeCounter != nullptr) {
        *species.invalidTypeCounter = 0ull;
    }
}

__global__ void q6_deposit_species_mass_from_cell_ids_0491c(
    CudaParticleDeviceView particles,
    CudaCellWorkspaceDeviceView cells,
    CudaSpeciesCellDeviceView0490h species,
    std::uint64_t nParticles) {
    const std::uint64_t idx = blockIdx.x * blockDim.x + threadIdx.x;
    const std::uint64_t stride = static_cast<std::uint64_t>(blockDim.x) * gridDim.x;
    for (std::uint64_t i = idx; i < nParticles; i += stride) {
        if (particles.role != nullptr && particles.role[i] != kParticleRoleFluid) {
            continue;
        }
        const int c = cells.cellId[i];
        if (c < 0 || c >= species.numCells) {
            continue;
        }
        int speciesIndex = -1;
        const std::uint32_t type = particles.type ? particles.type[i] : 0u;
        for (int s = 0; s < species.speciesCount; ++s) {
            if (species.speciesTypes[s] == type) {
                speciesIndex = s;
                break;
            }
        }
        if (speciesIndex < 0) {
            if (species.invalidTypeCounter != nullptr) {
                atomicAdd(species.invalidTypeCounter, 1ull);
            }
            continue;
        }
        const double m = particles.mass ? particles.mass[i] : 1.0;
        atomic_add_double_0400(&species.mass[speciesIndex * species.numCells + c], m);
        atomic_add_double_0400(&species.totalCellMass[c], m);
    }
}

__global__ void q6_apply_species_particle_correction_0491c(
    CudaParticleDeviceView particles,
    CudaCellWorkspaceDeviceView cells,
    CudaSpeciesCellDeviceView0490h species,
    const double* dux,
    const double* duy,
    std::uint64_t nParticles,
    double sensitivity,
    double alphaEpsilon,
    int weightedMode,
    int fatalFallback,
    double* partialPx,
    double* partialPy,
    unsigned long long* fallbackCounter) {
    extern __shared__ double sh[];
    double* shX = sh;
    double* shY = sh + blockDim.x;
    const int tid = threadIdx.x;
    double px = 0.0;
    double py = 0.0;
    const std::uint64_t idx = blockIdx.x * blockDim.x + threadIdx.x;
    const std::uint64_t stride = static_cast<std::uint64_t>(blockDim.x) * gridDim.x;
    for (std::uint64_t i = idx; i < nParticles; i += stride) {
        if (particles.role != nullptr && particles.role[i] != kParticleRoleFluid) {
            continue;
        }
        const int c = cells.cellId[i];
        if (c < 0 || c >= species.numCells) {
            continue;
        }
        int speciesIndex = -1;
        const std::uint32_t type = particles.type ? particles.type[i] : 0u;
        for (int s = 0; s < species.speciesCount; ++s) {
            if (species.speciesTypes[s] == type) {
                speciesIndex = s;
                break;
            }
        }
        if (speciesIndex < 0) {
            continue;
        }

        double weight = 1.0;
        if (weightedMode && sensitivity > 0.0) {
            const double totalMass = species.totalCellMass[c];
            double alphaBar = 0.0;
            if (totalMass > 0.0) {
                for (int s = 0; s < species.speciesCount; ++s) {
                    const double ms = species.mass[s * species.numCells + c];
                    alphaBar += (ms / totalMass) * species.q6Strength[s];
                }
            }
            if (alphaBar > alphaEpsilon) {
                weight = (1.0 - sensitivity) +
                         sensitivity * species.q6Strength[speciesIndex] / alphaBar;
            } else if (fatalFallback) {
                atomicAdd(fallbackCounter, 1ull);
                continue;
            }
        }

        const double dvx = weight * dux[c];
        const double dvy = weight * duy[c];
        particles.vx[i] += dvx;
        particles.vy[i] += dvy;
        const double m = particles.mass ? particles.mass[i] : 1.0;
        px += m * dvx;
        py += m * dvy;
    }
    shX[tid] = px;
    shY[tid] = py;
    __syncthreads();
    for (int offset = blockDim.x / 2; offset > 0; offset >>= 1) {
        if (tid < offset) {
            shX[tid] += shX[tid + offset];
            shY[tid] += shY[tid + offset];
        }
        __syncthreads();
    }
    if (tid == 0) {
        partialPx[blockIdx.x] = shX[0];
        partialPy[blockIdx.x] = shY[0];
    }
}

__global__ void q6_count_zero_alpha_bar_0491c(CudaSpeciesCellDeviceView0490h species,
                                              double alphaEpsilon,
                                              unsigned long long* fallbackCounter) {
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    const int stride = blockDim.x * gridDim.x;
    for (int c = idx; c < species.numCells; c += stride) {
        const double totalMass = species.totalCellMass[c];
        if (!(totalMass > 0.0)) {
            continue;
        }
        double alphaBar = 0.0;
        for (int s = 0; s < species.speciesCount; ++s) {
            const double ms = species.mass[s * species.numCells + c];
            alphaBar += (ms / totalMass) * species.q6Strength[s];
        }
        if (!(alphaBar > alphaEpsilon)) {
            atomicAdd(fallbackCounter, 1ull);
        }
    }
}

__global__ void q6_species_barycentric_residual_stats_0491c(
    CudaSpeciesCellDeviceView0490h species,
    const double* dux,
    const double* duy,
    double sensitivity,
    double alphaEpsilon,
    int weightedMode,
    double* partialX,
    double* partialY) {
    extern __shared__ double sh[];
    double* shX = sh;
    double* shY = sh + blockDim.x;
    const int tid = threadIdx.x;
    double maxX = 0.0;
    double maxY = 0.0;
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    const int stride = blockDim.x * gridDim.x;
    for (int c = idx; c < species.numCells; c += stride) {
        const double totalMass = species.totalCellMass[c];
        if (!(totalMass > 0.0)) {
            continue;
        }

        double alphaBar = 0.0;
        if (weightedMode && sensitivity > 0.0) {
            for (int s = 0; s < species.speciesCount; ++s) {
                const double ms = species.mass[s * species.numCells + c];
                alphaBar += (ms / totalMass) * species.q6Strength[s];
            }
        }
        const int useWeighted = weightedMode && sensitivity > 0.0 && alphaBar > alphaEpsilon;

        const double targetX = totalMass * dux[c];
        const double targetY = totalMass * duy[c];
        double residualX = -targetX;
        double residualY = -targetY;
        double scaleX = fabs(targetX);
        double scaleY = fabs(targetY);
        for (int s = 0; s < species.speciesCount; ++s) {
            const double weight = useWeighted
                ? ((1.0 - sensitivity) + sensitivity * species.q6Strength[s] / alphaBar)
                : 1.0;
            const double ms = species.mass[s * species.numCells + c];
            const double termX = ms * weight * dux[c];
            const double termY = ms * weight * duy[c];
            residualX += termX;
            residualY += termY;
            scaleX += fabs(termX);
            scaleY += fabs(termY);
        }
        const double absResidualX = fabs(residualX);
        const double absResidualY = fabs(residualY);
        const double scaledResidualX = absResidualX / fmax(1.0, scaleX);
        const double scaledResidualY = absResidualY / fmax(1.0, scaleY);
        maxX = fmax(maxX, fmax(absResidualX, absResidualY));
        maxY = fmax(maxY, fmax(scaledResidualX, scaledResidualY));
    }
    shX[tid] = maxX;
    shY[tid] = maxY;
    __syncthreads();
    for (int offset = blockDim.x / 2; offset > 0; offset >>= 1) {
        if (tid < offset) {
            shX[tid] = fmax(shX[tid], shX[tid + offset]);
            shY[tid] = fmax(shY[tid], shY[tid + offset]);
        }
        __syncthreads();
    }
    if (tid == 0) {
        partialX[blockIdx.x] = shX[0];
        partialY[blockIdx.x] = shY[0];
    }
}

__global__ void q6_apply_uniform_momentum_correction_0400(CudaParticleDeviceView particles,
                                                          std::uint64_t nParticles,
                                                          double cvx,
                                                          double cvy) {
    const std::uint64_t idx = blockIdx.x * blockDim.x + threadIdx.x;
    const std::uint64_t stride = static_cast<std::uint64_t>(blockDim.x) * gridDim.x;
    for (std::uint64_t i = idx; i < nParticles; i += stride) {
        if (particles.role != nullptr && particles.role[i] != kParticleRoleFluid) {
            continue;
        }
        particles.vx[i] -= cvx;
        particles.vy[i] -= cvy;
    }
}

__global__ void q6_update_corrected_cell_means_0400(CudaCellWorkspaceDeviceView cells,
                                                    const double* dux,
                                                    const double* duy,
                                                    double cvx,
                                                    double cvy) {
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    const int stride = blockDim.x * gridDim.x;
    for (int c = idx; c < cells.numCells; c += stride) {
        cells.cellUx[c] += dux[c] - cvx;
        cells.cellUy[c] += duy[c] - cvy;
    }
}

__global__ void q6_thermostat_deposit_moments_from_cell_ids_0400(CudaParticleDeviceView particles,
                                                                       CudaCellWorkspaceDeviceView cells,
                                                                       std::uint64_t nParticles) {
    const std::uint64_t idx = blockIdx.x * blockDim.x + threadIdx.x;
    const std::uint64_t stride = static_cast<std::uint64_t>(blockDim.x) * gridDim.x;
    for (std::uint64_t i = idx; i < nParticles; i += stride) {
        if (particles.role != nullptr && particles.role[i] != kParticleRoleFluid) {
            continue;
        }
        const int c = cells.cellId[i];
        if (c < 0 || c >= cells.numCells) {
            continue;
        }
        const double m = particles.mass ? particles.mass[i] : 1.0;
        atomicAdd(&cells.count[c], 1u);
        atomic_add_double_0400(&cells.cellMass[c], m);
        atomic_add_double_0400(&cells.cellPx[c], m * particles.vx[i]);
        atomic_add_double_0400(&cells.cellPy[c], m * particles.vy[i]);
    }
}

__global__ void q6_thermostat_kinetic_0400(CudaParticleDeviceView particles,
                                           CudaCellWorkspaceDeviceView cells,
                                           std::uint64_t nParticles) {
    const std::uint64_t idx = blockIdx.x * blockDim.x + threadIdx.x;
    const std::uint64_t stride = static_cast<std::uint64_t>(blockDim.x) * gridDim.x;
    for (std::uint64_t i = idx; i < nParticles; i += stride) {
        if (particles.role != nullptr && particles.role[i] != kParticleRoleFluid) {
            continue;
        }
        const int c = cells.cellId[i];
        if (c < 0 || c >= cells.numCells) {
            continue;
        }
        const double dvx = particles.vx[i] - cells.cellUx[c];
        const double dvy = particles.vy[i] - cells.cellUy[c];
        const double m = particles.mass ? particles.mass[i] : 1.0;
        atomic_add_double_0400(&cells.cellKinetic[c], 0.5 * m * (dvx * dvx + dvy * dvy));
        atomicAdd(cells.fluidCounter, 1ull);
    }
}

__global__ void q6_thermostat_scale_0400(CudaCellWorkspaceDeviceView cells,
                                         double targetKBT,
                                         int minParticles,
                                         double epsilon,
                                         double* partial0,
                                         double* partial1) {
    extern __shared__ double sh[];
    double* shK = sh;
    double* shTarget = sh + blockDim.x;
    const int tid = threadIdx.x;
    double kSum = 0.0;
    double targetSum = 0.0;
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    const int stride = blockDim.x * gridDim.x;
    for (int c = idx; c < cells.numCells; c += stride) {
        double scale = 1.0;
        const unsigned int count = cells.count[c];
        const double K = cells.cellKinetic[c];
        if (count >= static_cast<unsigned int>(minParticles) && K > epsilon) {
            const double dof = 2.0 * static_cast<double>(count - 1u);
            const double targetK = 0.5 * dof * targetKBT;
            scale = sqrt(targetK / K);
            kSum += K;
            targetSum += targetK;
        }
        cells.cellScale[c] = scale;
    }
    shK[tid] = kSum;
    shTarget[tid] = targetSum;
    __syncthreads();
    for (int offset = blockDim.x / 2; offset > 0; offset >>= 1) {
        if (tid < offset) {
            shK[tid] += shK[tid + offset];
            shTarget[tid] += shTarget[tid + offset];
        }
        __syncthreads();
    }
    if (tid == 0) {
        partial0[blockIdx.x] = shK[0];
        partial1[blockIdx.x] = shTarget[0];
    }
}

__global__ void q6_thermostat_apply_0400(CudaParticleDeviceView particles,
                                         CudaCellWorkspaceDeviceView cells,
                                         std::uint64_t nParticles) {
    const std::uint64_t idx = blockIdx.x * blockDim.x + threadIdx.x;
    const std::uint64_t stride = static_cast<std::uint64_t>(blockDim.x) * gridDim.x;
    for (std::uint64_t i = idx; i < nParticles; i += stride) {
        if (particles.role != nullptr && particles.role[i] != kParticleRoleFluid) {
            continue;
        }
        const int c = cells.cellId[i];
        if (c < 0 || c >= cells.numCells) {
            continue;
        }
        const double scale = cells.cellScale[c];
        if (scale == 1.0) {
            continue;
        }
        const double ux = cells.cellUx[c];
        const double uy = cells.cellUy[c];
        particles.vx[i] = ux + scale * (particles.vx[i] - ux);
        particles.vy[i] = uy + scale * (particles.vy[i] - uy);
    }
}

__global__ void q6_projected_divergence_stats_0400(CudaCellWorkspaceDeviceView cells,
                                                   const double* dux,
                                                   const double* duy,
                                                   double* partialSq,
                                                   double* partialMax,
                                                   int nx,
                                                   int ny,
                                                   double dx,
                                                   double dy,
                                                   int periodicX,
                                                   int periodicY,
                                                   double xLowFlux,
                                                   double yLowFlux,
                                                   Q6SegmentedIo0409 segmentedIo) {
    extern __shared__ double sh[];
    double* shSq = sh;
    double* shMax = sh + blockDim.x;
    const int tid = threadIdx.x;
    double sq = 0.0;
    double mx = 0.0;
    const int n = nx * ny;
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    const int stride = blockDim.x * gridDim.x;
    for (int c = idx; c < n; c += stride) {
        const int ix = c % nx;
        const int iy = c / nx;
        const int west = (periodicX || ix > 0) ? (iy * nx + (periodicX ? wrap_cell_index_0400(ix - 1, nx) : (ix - 1))) : c;
        const int south = (periodicY || iy > 0) ? ((periodicY ? wrap_cell_index_0400(iy - 1, ny) : (iy - 1)) * nx + ix) : c;
        const double fx = cells.cellUx[c] + dux[c];
        const double localXLowFlux = q6_segmented_flux_for_cell_0409(segmentedIo, 0, ix, iy, nx, ny, xLowFlux);
        const double localYLowFlux = q6_segmented_flux_for_cell_0409(segmentedIo, 2, ix, iy, nx, ny, yLowFlux);
        const double fxW = (periodicX || ix > 0) ? (cells.cellUx[west] + dux[west]) : localXLowFlux;
        const double fy = cells.cellUy[c] + duy[c];
        const double fyS = (periodicY || iy > 0) ? (cells.cellUy[south] + duy[south]) : localYLowFlux;
        const double div = (fx - fxW) / dx + (fy - fyS) / dy;
        sq += div * div;
        mx = fmax(mx, fabs(div));
    }
    shSq[tid] = sq;
    shMax[tid] = mx;
    __syncthreads();
    for (int offset = blockDim.x / 2; offset > 0; offset >>= 1) {
        if (tid < offset) {
            shSq[tid] += shSq[tid + offset];
            shMax[tid] = fmax(shMax[tid], shMax[tid + offset]);
        }
        __syncthreads();
    }
    if (tid == 0) {
        partialSq[blockIdx.x] = shSq[0];
        partialMax[blockIdx.x] = shMax[0];
    }
}


__global__ void q6_cg_single_block_0407(double* rhs,
                                        double* phi,
                                        double* r,
                                        double* p,
                                        double* Ap,
                                        double* outIterations,
                                        double* outResidualRel,
                                        double* outStatus,
                                        int nx,
                                        int ny,
                                        int n,
                                        int maxIterations,
                                        double tolerance,
                                        double rhsMean,
                                        double invDx2,
                                        double invDy2,
                                        int periodicX,
                                        int periodicY,
                                        int warmStart) {
    extern __shared__ double sh[];
    __shared__ double rr;
    __shared__ double rrNew;
    __shared__ double rhsNormSafe;
    __shared__ double pAp;
    __shared__ double residualRel;
    __shared__ double phiMean;
    __shared__ double rMean;
    __shared__ int iterations;
    __shared__ int status;
    __shared__ int done;

    const int tid = threadIdx.x;
    double local = 0.0;
    if (warmStart) {
        for (int c = tid; c < n; c += blockDim.x) local += phi[c];
        sh[tid] = local;
        __syncthreads();
        for (int offset = blockDim.x / 2; offset > 0; offset >>= 1) {
            if (tid < offset) sh[tid] += sh[tid + offset];
            __syncthreads();
        }
        if (tid == 0) phiMean = sh[0] / static_cast<double>(n);
        __syncthreads();
    } else if (tid == 0) {
        phiMean = 0.0;
    }
    __syncthreads();

    local = 0.0;
    double localRhsNorm = 0.0;
    for (int c = tid; c < n; c += blockDim.x) {
        const int ix = c % nx;
        const int iy = c / nx;
        const double phiOld = warmStart ? phi[c] : 0.0;
        double aPhi = 0.0;
        if (warmStart) {
            if (periodicX || ix > 0) {
                const int west = iy * nx + (periodicX ? wrap_cell_index_0400(ix - 1, nx) : (ix - 1));
                aPhi += (phiOld - phi[west]) * invDx2;
            }
            if (periodicX || ix < nx - 1) {
                const int east = iy * nx + (periodicX ? wrap_cell_index_0400(ix + 1, nx) : (ix + 1));
                aPhi += (phiOld - phi[east]) * invDx2;
            }
            if (periodicY || iy > 0) {
                const int south = (periodicY ? wrap_cell_index_0400(iy - 1, ny) : (iy - 1)) * nx + ix;
                aPhi += (phiOld - phi[south]) * invDy2;
            }
            if (periodicY || iy < ny - 1) {
                const int north = (periodicY ? wrap_cell_index_0400(iy + 1, ny) : (iy + 1)) * nx + ix;
                aPhi += (phiOld - phi[north]) * invDy2;
            }
        } else {
            phi[c] = 0.0;
        }
        const double v = rhs[c] - rhsMean;
        rhs[c] = v;
        const double rv = warmStart ? (v - aPhi) : v;
        r[c] = rv;
        p[c] = rv;
        local += rv * rv;
        localRhsNorm += v * v;
    }
    sh[tid] = local;
    sh[blockDim.x + tid] = localRhsNorm;
    __syncthreads();
    for (int offset = blockDim.x / 2; offset > 0; offset >>= 1) {
        if (tid < offset) {
            sh[tid] += sh[tid + offset];
            sh[blockDim.x + tid] += sh[blockDim.x + tid + offset];
        }
        __syncthreads();
    }
    if (tid == 0) {
        rr = sh[0];
        const double rhsNorm = sqrt(fmax(0.0, sh[blockDim.x]));
        rhsNormSafe = fmax(rhsNorm, 1.0e-300);
        residualRel = 0.0;
        iterations = 0;
        status = (rhsNorm <= tolerance) ? 1 : 0;
        done = (status == 1 || maxIterations <= 0) ? 1 : 0;
    }
    __syncthreads();
    if (warmStart) {
        for (int c = tid; c < n; c += blockDim.x) {
            phi[c] -= phiMean;
        }
    }
    __syncthreads();

    for (int it = 0; it < maxIterations; ++it) {
        if (done) break;
        local = 0.0;
        for (int c = tid; c < n; c += blockDim.x) {
            const int ix = c % nx;
            const int iy = c / nx;
            const double center = p[c];
            double value = 0.0;
            if (periodicX || ix > 0) {
                const int west = iy * nx + (periodicX ? wrap_cell_index_0400(ix - 1, nx) : (ix - 1));
                value += (center - p[west]) * invDx2;
            }
            if (periodicX || ix < nx - 1) {
                const int east = iy * nx + (periodicX ? wrap_cell_index_0400(ix + 1, nx) : (ix + 1));
                value += (center - p[east]) * invDx2;
            }
            if (periodicY || iy > 0) {
                const int south = (periodicY ? wrap_cell_index_0400(iy - 1, ny) : (iy - 1)) * nx + ix;
                value += (center - p[south]) * invDy2;
            }
            if (periodicY || iy < ny - 1) {
                const int north = (periodicY ? wrap_cell_index_0400(iy + 1, ny) : (iy + 1)) * nx + ix;
                value += (center - p[north]) * invDy2;
            }
            Ap[c] = value;
            local += center * value;
        }
        sh[tid] = local;
        __syncthreads();
        for (int offset = blockDim.x / 2; offset > 0; offset >>= 1) {
            if (tid < offset) sh[tid] += sh[tid + offset];
            __syncthreads();
        }
        if (tid == 0) {
            pAp = sh[0];
            if (!(pAp > 0.0) || !isfinite(pAp)) {
                status = -1;
                done = 1;
            }
        }
        __syncthreads();
        if (done) break;

        const double alpha = rr / pAp;
        local = 0.0;
        for (int c = tid; c < n; c += blockDim.x) {
            phi[c] += alpha * p[c];
            const double rv = r[c] - alpha * Ap[c];
            r[c] = rv;
            local += rv * rv;
        }
        sh[tid] = local;
        __syncthreads();
        for (int offset = blockDim.x / 2; offset > 0; offset >>= 1) {
            if (tid < offset) sh[tid] += sh[tid + offset];
            __syncthreads();
        }
        if (tid == 0) {
            rrNew = sh[0];
            iterations = it + 1;
            residualRel = sqrt(fmax(0.0, rrNew)) / rhsNormSafe;
            if (residualRel <= tolerance) {
                rr = rrNew;
                status = 1;
                done = 1;
            }
        }
        __syncthreads();
        if (done) break;

        if (((it + 1) % 25) == 0) {
            double sumPhi = 0.0;
            double sumR = 0.0;
            for (int c = tid; c < n; c += blockDim.x) {
                sumPhi += phi[c];
                sumR += r[c];
            }
            sh[tid] = sumPhi;
            sh[blockDim.x + tid] = sumR;
            __syncthreads();
            for (int offset = blockDim.x / 2; offset > 0; offset >>= 1) {
                if (tid < offset) {
                    sh[tid] += sh[tid + offset];
                    sh[blockDim.x + tid] += sh[blockDim.x + tid + offset];
                }
                __syncthreads();
            }
            if (tid == 0) {
                phiMean = sh[0] / static_cast<double>(n);
                rMean = sh[blockDim.x] / static_cast<double>(n);
            }
            __syncthreads();
            local = 0.0;
            for (int c = tid; c < n; c += blockDim.x) {
                phi[c] -= phiMean;
                const double rv = r[c] - rMean;
                r[c] = rv;
                local += rv * rv;
            }
            sh[tid] = local;
            __syncthreads();
            for (int offset = blockDim.x / 2; offset > 0; offset >>= 1) {
                if (tid < offset) sh[tid] += sh[tid + offset];
                __syncthreads();
            }
            if (tid == 0) rrNew = sh[0];
            __syncthreads();
        }

        const double beta = rrNew / fmax(rr, 1.0e-300);
        for (int c = tid; c < n; c += blockDim.x) {
            p[c] = r[c] + beta * p[c];
        }
        if (tid == 0) rr = rrNew;
        __syncthreads();
    }

    if (tid == 0) {
        outIterations[0] = static_cast<double>(iterations);
        outResidualRel[0] = residualRel;
        outStatus[0] = static_cast<double>(status);
    }
}

double reduce_host_sum_0400(double* devicePartials, int blocks) {
    std::vector<double> host(static_cast<std::size_t>(blocks), 0.0);
    check_cuda_0400(cudaMemcpy(host.data(), devicePartials,
                               static_cast<std::size_t>(blocks) * sizeof(double),
                               cudaMemcpyDeviceToHost),
                    "copy partial sum");
    double s = 0.0;
    for (double v : host) {
        s += v;
    }
    return s;
}

double reduce_host_max_0400(double* devicePartials, int blocks) {
    std::vector<double> host(static_cast<std::size_t>(blocks), 0.0);
    check_cuda_0400(cudaMemcpy(host.data(), devicePartials,
                               static_cast<std::size_t>(blocks) * sizeof(double),
                               cudaMemcpyDeviceToHost),
                    "copy partial max");
    double m = 0.0;
    for (double v : host) {
        m = std::max(m, v);
    }
    return m;
}

bool supported_subset_0400(const SimulationParams& params,
                           const CellGrid& grid,
                           const FluidDomainBounds& domain,
                           const CudaQ6Resident0400Diagnostics& diag,
                           const char** reason) {
    (void)diag;
    if (!params.projectionEnable) {
        *reason = "projection disabled";
        return false;
    }
    if (params.projectionBackend != "cuda") {
        *reason = "projectionBackend is not cuda";
        return false;
    }
    const bool periodicXY = is_x_periodic(params) && is_y_periodic(params);
    const bool channelXY = is_x_periodic(params) && !is_y_periodic(params) &&
        (params.bcBottom == "solid" || params.bcBottom == "specular" || params.bcBottom == "bounceback") &&
        (params.bcTop == "solid" || params.bcTop == "specular" || params.bcTop == "bounceback");
    const bool openFullface = q6_open_fullface_0404_supported(params);
    const bool openSegmented0409 = q6_open_segmented_0409_supported(params);
    if (!periodicXY && !channelXY && !openFullface && !openSegmented0409) {
        *reason = "unsupported boundary condition";
        return false;
    }
    if (params.immersedSolidEnable || params.projectionImmersedSolidMaskEnable) {
        *reason = "immersed solid or projection mask requested";
        return false;
    }
    if ((params.openBoundarySegmentsEnable && !openSegmented0409) ||
        params.closedCapacityResponseEnable || params.closedCapacityVirialKickEnable) {
        *reason = "unsupported segmented open boundary or closed-capacity coupling requested";
        return false;
    }
    if (grid.Nx <= 0 || grid.Ny <= 0 || grid.numCells != grid.Nx * grid.Ny) {
        *reason = "invalid grid";
        return false;
    }
    const double tol = 1.0e-12;
    if (std::abs(domain.xMin) > tol || std::abs(domain.yMin) > tol ||
        std::abs(domain.xMax - params.Lx) > tol || std::abs(domain.yMax - params.Ly) > tol ||
        std::abs(domain.vxMin) > tol || std::abs(domain.vxMax) > tol ||
        std::abs(domain.vyMin) > tol || std::abs(domain.vyMax) > tol) {
        *reason = "moving or truncated fluid domain";
        return false;
    }
    if (!(params.q6ProjectionStrength >= 0.0 && params.q6ProjectionStrength <= 1.0)) {
        *reason = "invalid projection strength";
        return false;
    }
    return true;
}

} // namespace

CudaQ6Resident0400Diagnostics try_apply_cuda_q6_resident_0400(ParticleState& state,
                                                              const SimulationParams& params,
                                                              const CellGrid& grid,
                                                              const FluidDomainBounds& domain,
                                                              int step,
                                                              double time,
                                                              CudaSpeciesCellWorkspace0490h* speciesWorkspace0491c) {
    (void)step;
    CudaQ6Resident0400Diagnostics diag;
    diag.requested = truthy_0400(std::getenv("MPCD_CUDA_Q6_RESIDENT_0400"));
    if (!diag.requested) {
        return diag;
    }
    const auto tTotal = Clock0400::now();
    const char* reason = "";
    diag.supported = supported_subset_0400(params, grid, domain, diag, &reason);
    diag.reason = reason;
    if (!diag.supported) {
        return diag;
    }

    const std::uint64_t active = active_fluid_count(state);
    if (active == 0u) {
        diag.reason = "no active fluid particles";
        return diag;
    }
    CudaParticleState& gpuState = cuda_shared_particle_state_0251();
    if (!cuda_shared_particle_state_0251_is_fresh()) {
        gpuState.upload_all(state);
        gpuState.set_active_fluid_size(active);
        cuda_shared_particle_state_0251_mark_fresh("cuda_q6_resident_0400_upload");
    }
    CudaParticleDeviceView particles = gpuState.device_view();
    const std::uint64_t nParticles = particles.nActiveFluid > 0u ? particles.nActiveFluid : active;
    if (nParticles == 0u || nParticles > particles.n) {
        diag.reason = "invalid resident active prefix";
        return diag;
    }

    const int threads = 256;
    const int cellBlocks = std::max(1, std::min(1024, (grid.numCells + threads - 1) / threads));
    const int particleBlocks = std::max(1, std::min(4096, static_cast<int>((nParticles + threads - 1u) / threads)));
    const int blocks = std::max(cellBlocks, particleBlocks);
    diag.blocks = blocks;
    diag.threads = threads;
    diag.particles = nParticles;
    diag.cells = static_cast<std::uint64_t>(grid.numCells);

    ResidentWorkspace0400& ws = resident_workspace_0400();
    ws.ensure(nParticles, grid.numCells, blocks);
    CudaCellWorkspaceDeviceView cells = ws.cells.device_view();
    CudaSpeciesCellDeviceView0490h species0491c{};
    const bool speciesQ6Weighted0491c =
        params.speciesQ6Enable && params.speciesQ6Mode == "weighted" &&
        params.speciesQ6Sensitivity > 0.0;
    if (params.speciesQ6Enable) {
        if (speciesWorkspace0491c == nullptr) {
            diag.reason = "speciesQ6Enable requires a resident CUDA species workspace";
            return diag;
        }
        if (params.speciesDefinitions.empty()) {
            diag.reason = "speciesQ6Enable requires registered species definitions";
            return diag;
        }
    }
    const std::size_t scalarShared = static_cast<std::size_t>(threads) * sizeof(double);
    const std::size_t pairShared = 2u * static_cast<std::size_t>(threads) * sizeof(double);
    const int periodicX = is_x_periodic(params) ? 1 : 0;
    const int periodicY = is_y_periodic(params) ? 1 : 0;
    double xLowFlux = 0.0;
    double xHighFlux = 0.0;
    double yLowFlux = 0.0;
    double yHighFlux = 0.0;
    Q6SegmentedIo0409 segmentedIo0409 = q6_make_segmented_0409(params, time);
    if (q6_open_fullface_0404_supported(params)) {
        q6_open_fullface_flux_0404(params, time, xLowFlux, xHighFlux, yLowFlux, yHighFlux);
        diag.openBoundaryEnabled = true;
    } else if (segmentedIo0409.enabled) {
        const double xLowIntegratedFlux = q6_segmented_flux_integral_0409(segmentedIo0409, 0, params.Ly);
        const double xHighIntegratedFlux = q6_segmented_flux_integral_0409(segmentedIo0409, 1, params.Ly);
        const double yLowIntegratedFlux = q6_segmented_flux_integral_0409(segmentedIo0409, 2, params.Lx);
        const double yHighIntegratedFlux = q6_segmented_flux_integral_0409(segmentedIo0409, 3, params.Lx);
        xLowFlux = params.Ly > 0.0 ? xLowIntegratedFlux / params.Ly : 0.0;
        xHighFlux = params.Ly > 0.0 ? xHighIntegratedFlux / params.Ly : 0.0;
        yLowFlux = params.Lx > 0.0 ? yLowIntegratedFlux / params.Lx : 0.0;
        yHighFlux = params.Lx > 0.0 ? yHighIntegratedFlux / params.Lx : 0.0;
        diag.openBoundaryEnabled = true;
    }
    if (diag.openBoundaryEnabled) {
        diag.openBoundaryFluxXLow = xLowFlux;
        diag.openBoundaryFluxXHigh = xHighFlux;
        diag.openBoundaryFluxYLow = yLowFlux;
        diag.openBoundaryFluxYHigh = yHighFlux;
        diag.openBoundaryFluxBalance = (xHighFlux - xLowFlux) * params.Ly + (yHighFlux - yLowFlux) * params.Lx;
        const double area = params.Lx * params.Ly;
        diag.openBoundaryMeanDivergence = area > 0.0 ? diag.openBoundaryFluxBalance / area : 0.0;
    }

    const bool singleBlockCg0407 = cuda_q6_single_block_cg_0407_enabled(grid.numCells);
    const bool warmRequested0408 = cuda_q6_warm_start_0408_requested();
    const bool warmUsable0408 = warmRequested0408 && singleBlockCg0407 && ws.warmPhiValid &&
                                ws.warmNx == grid.Nx && ws.warmNy == grid.Ny &&
                                ws.warmPeriodicX == periodicX && ws.warmPeriodicY == periodicY;
    const int resetPhi0408 = warmUsable0408 ? 0 : 1;

    check_cuda_0400(cudaMemset(ws.counter.data(), 0, sizeof(unsigned long long)), "counter zero");
    const auto tDeposit = Clock0400::now();
    q6_zero_cells_0400<<<cellBlocks, threads>>>(cells, ws.rhs.data(), ws.phi.data(), ws.r.data(),
                                                ws.p.data(), ws.Ap.data(), ws.dux.data(), ws.duy.data(),
                                                resetPhi0408);
    check_cuda_0400(cudaGetLastError(), "zero cells launch");
    q6_zero_particle_cell_ids_0400<<<particleBlocks, threads>>>(cells, nParticles);
    check_cuda_0400(cudaGetLastError(), "zero particle cell ids launch");
    q6_deposit_periodic_0400<<<particleBlocks, threads>>>(particles, cells, nParticles,
                                                          grid.Nx, grid.Ny, params.Lx, params.Ly, periodicX, periodicY);
    check_cuda_0400(cudaGetLastError(), "deposit launch");
    q6_finalize_cells_0400<<<cellBlocks, threads>>>(cells, ws.counter.data());
    check_cuda_0400(cudaGetLastError(), "finalize cells launch");
    if (params.speciesQ6Enable) {
        const auto tSpeciesDeposit0491h = Clock0400::now();
        CudaSpeciesCellDepositDiagnostics0490h speciesDiag0491c{};
        speciesWorkspace0491c->ensure_capacity(
            grid.numCells,
            static_cast<int>(params.speciesDefinitions.size()),
            &speciesDiag0491c);
        diag.speciesQ6AllocatedBytes = speciesDiag0491c.allocatedBytes;
        diag.speciesQ6AllocationCalls = speciesDiag0491c.allocationCalls;
        species0491c = speciesWorkspace0491c->device_view();
        std::vector<std::uint32_t> hSpeciesTypes0491c(params.speciesDefinitions.size());
        std::vector<double> hQ6Strength0491c(params.speciesDefinitions.size());
        for (std::size_t s = 0; s < params.speciesDefinitions.size(); ++s) {
            hSpeciesTypes0491c[s] = params.speciesDefinitions[s].type;
            hQ6Strength0491c[s] = params.speciesDefinitions[s].q6StrengthDeclared;
        }
        diag.speciesQ6MetadataH2DBytes =
            hSpeciesTypes0491c.size() * sizeof(std::uint32_t) +
            hQ6Strength0491c.size() * sizeof(double);
        check_cuda_0400(cudaMemcpy(species0491c.speciesTypes, hSpeciesTypes0491c.data(),
                                   hSpeciesTypes0491c.size() * sizeof(std::uint32_t),
                                   cudaMemcpyHostToDevice),
                        "species q6 type metadata upload");
        check_cuda_0400(cudaMemcpy(species0491c.q6Strength, hQ6Strength0491c.data(),
                                   hQ6Strength0491c.size() * sizeof(double),
                                   cudaMemcpyHostToDevice),
                        "species q6 strength metadata upload");
        const int denseSpecies0491c =
            grid.numCells * static_cast<int>(params.speciesDefinitions.size());
        const int speciesResetBlocks0491c =
            std::max(1, std::min(1024, (std::max(grid.numCells, denseSpecies0491c) + threads - 1) / threads));
        q6_reset_species_mass_0491c<<<speciesResetBlocks0491c, threads>>>(species0491c);
        check_cuda_0400(cudaGetLastError(), "species q6 mass reset launch");
        q6_deposit_species_mass_from_cell_ids_0491c<<<particleBlocks, threads>>>(
            particles, cells, species0491c, nParticles);
        check_cuda_0400(cudaGetLastError(), "species q6 mass deposit launch");
        unsigned long long invalidSpecies0491c = 0ull;
        check_cuda_0400(cudaMemcpy(&invalidSpecies0491c, species0491c.invalidTypeCounter,
                                   sizeof(invalidSpecies0491c), cudaMemcpyDeviceToHost),
                        "species q6 invalid type counter download");
        if (invalidSpecies0491c != 0ull) {
            diag.reason = "speciesQ6Enable encountered unregistered fluid particle types";
            return diag;
        }
        diag.speciesQ6DepositSeconds = seconds_since_0400(tSpeciesDeposit0491h);
    }
    check_cuda_0400(cudaMemcpy(&diag.emptyCells, ws.counter.data(), sizeof(unsigned long long),
                               cudaMemcpyDeviceToHost),
                    "copy empty counter");
    diag.depositSeconds = seconds_since_0400(tDeposit);

    const auto tSolve = Clock0400::now();
    const double dx = grid.dx;
    const double dy = grid.dy;
    const std::size_t tripleShared = 3u * static_cast<std::size_t>(threads) * sizeof(double);
    q6_build_rhs_and_stats_0400<<<cellBlocks, threads, tripleShared>>>(
        cells, ws.rhs.data(), ws.partial0.data(), ws.partial1.data(), ws.partial2.data(), grid.Nx, grid.Ny, dx, dy,
        periodicX, periodicY, xLowFlux, xHighFlux, yLowFlux, yHighFlux, segmentedIo0409);
    check_cuda_0400(cudaGetLastError(), "build rhs launch");
    const double rhsSum = reduce_host_sum_0400(ws.partial0.data(), cellBlocks);
    const double divSq = reduce_host_sum_0400(ws.partial1.data(), cellBlocks);
    diag.divBeforeMaxAbs = reduce_host_max_0400(ws.partial2.data(), cellBlocks);
    diag.divBeforeRms = std::sqrt(divSq / static_cast<double>(grid.numCells));
    const double rhsMean = rhsSum / static_cast<double>(grid.numCells);
    const double tol = std::max(0.0, params.projectionTolerance);
    const double invDx2 = 1.0 / (dx * dx);
    const double invDy2 = 1.0 / (dy * dy);

    if (singleBlockCg0407) {
        constexpr int cgThreads0407 = 256;
        const std::size_t cgShared0407 = 2u * static_cast<std::size_t>(cgThreads0407) * sizeof(double);
        q6_cg_single_block_0407<<<1, cgThreads0407, cgShared0407>>>(
            ws.rhs.data(), ws.phi.data(), ws.r.data(), ws.p.data(), ws.Ap.data(),
            ws.partial0.data(), ws.partial1.data(), ws.partial2.data(),
            grid.Nx, grid.Ny, grid.numCells, params.projectionMaxIterations, tol, rhsMean,
            invDx2, invDy2, periodicX, periodicY, warmUsable0408 ? 1 : 0);
        check_cuda_0400(cudaGetLastError(), "single-block cg launch");
        double cgIterations = 0.0;
        double cgResidualRel = 0.0;
        double cgStatus = 0.0;
        check_cuda_0400(cudaMemcpy(&cgIterations, ws.partial0.data(), sizeof(double), cudaMemcpyDeviceToHost),
                        "copy single-block cg iterations");
        check_cuda_0400(cudaMemcpy(&cgResidualRel, ws.partial1.data(), sizeof(double), cudaMemcpyDeviceToHost),
                        "copy single-block cg residual");
        check_cuda_0400(cudaMemcpy(&cgStatus, ws.partial2.data(), sizeof(double), cudaMemcpyDeviceToHost),
                        "copy single-block cg status");
        diag.iterations = static_cast<int>(std::llround(cgIterations));
        diag.residualRel = cgResidualRel;
        diag.converged = cgStatus > 0.5;
        if (cgStatus < -0.5) {
            diag.reason = "non-positive CG pAp";
        }
    } else {
    q6_init_cg_0400<<<cellBlocks, threads>>>(ws.rhs.data(), ws.phi.data(), ws.r.data(), ws.p.data(),
                                             rhsMean, grid.numCells);
    check_cuda_0400(cudaGetLastError(), "init cg launch");
    q6_reduce_square_sum_0400<<<cellBlocks, threads, scalarShared>>>(ws.r.data(), ws.partial0.data(),
                                                                     grid.numCells);
    check_cuda_0400(cudaGetLastError(), "initial rr launch");
    double rr = reduce_host_sum_0400(ws.partial0.data(), cellBlocks);
    const double rhsNorm = std::sqrt(std::max(0.0, rr));
    const double rhsNormSafe = std::max(rhsNorm, 1.0e-300);
    const double tol = std::max(0.0, params.projectionTolerance);
    const double invDx2 = 1.0 / (dx * dx);
    const double invDy2 = 1.0 / (dy * dy);

    diag.converged = rhsNorm <= tol;
    for (int it = 0; it < params.projectionMaxIterations && !diag.converged; ++it) {
        q6_apply_operator_and_dot_0400<<<cellBlocks, threads, scalarShared>>>(
            ws.p.data(), ws.Ap.data(), ws.partial0.data(), grid.Nx, grid.Ny, invDx2, invDy2,
            periodicX, periodicY);
        check_cuda_0400(cudaGetLastError(), "apply operator launch");
        const double pAp = reduce_host_sum_0400(ws.partial0.data(), cellBlocks);
        if (!(pAp > 0.0) || !std::isfinite(pAp)) {
            diag.reason = "non-positive CG pAp";
            break;
        }
        const double alpha = rr / pAp;
        q6_axpy_residual_0400<<<cellBlocks, threads>>>(ws.phi.data(), ws.r.data(), ws.p.data(),
                                                       ws.Ap.data(), alpha, grid.numCells);
        check_cuda_0400(cudaGetLastError(), "axpy residual launch");
        q6_reduce_square_sum_0400<<<cellBlocks, threads, scalarShared>>>(ws.r.data(), ws.partial0.data(),
                                                                         grid.numCells);
        check_cuda_0400(cudaGetLastError(), "rr update launch");
        double rrNew = reduce_host_sum_0400(ws.partial0.data(), cellBlocks);
        diag.iterations = it + 1;
        diag.residualRel = std::sqrt(std::max(0.0, rrNew)) / rhsNormSafe;
        if (diag.residualRel <= tol) {
            rr = rrNew;
            diag.converged = true;
            break;
        }
        if ((it + 1) % 25 == 0) {
            q6_reduce_sum_0400<<<cellBlocks, threads, scalarShared>>>(ws.phi.data(), ws.partial0.data(),
                                                                      grid.numCells);
            q6_reduce_sum_0400<<<cellBlocks, threads, scalarShared>>>(ws.r.data(), ws.partial1.data(),
                                                                      grid.numCells);
            check_cuda_0400(cudaGetLastError(), "mean reduction launch");
            const double phiMean = reduce_host_sum_0400(ws.partial0.data(), cellBlocks) /
                                   static_cast<double>(grid.numCells);
            const double rMean = reduce_host_sum_0400(ws.partial1.data(), cellBlocks) /
                                 static_cast<double>(grid.numCells);
            q6_subtract_mean_pair_0400<<<cellBlocks, threads>>>(ws.phi.data(), ws.r.data(),
                                                                phiMean, rMean, grid.numCells);
            check_cuda_0400(cudaGetLastError(), "mean subtract launch");
            q6_reduce_square_sum_0400<<<cellBlocks, threads, scalarShared>>>(ws.r.data(), ws.partial0.data(),
                                                                             grid.numCells);
            check_cuda_0400(cudaGetLastError(), "rr after mean launch");
            rrNew = reduce_host_sum_0400(ws.partial0.data(), cellBlocks);
        }
        const double beta = rrNew / std::max(rr, 1.0e-300);
        q6_update_p_0400<<<cellBlocks, threads>>>(ws.p.data(), ws.r.data(), beta, grid.numCells);
        check_cuda_0400(cudaGetLastError(), "update p launch");
        rr = rrNew;
    }
    }
    if (warmRequested0408 && singleBlockCg0407 && diag.converged) {
        ws.warmPhiValid = true;
        ws.warmNx = grid.Nx;
        ws.warmNy = grid.Ny;
        ws.warmPeriodicX = periodicX;
        ws.warmPeriodicY = periodicY;
    } else {
        ws.warmPhiValid = false;
    }
    diag.solveSeconds = seconds_since_0400(tSolve);
    if (!diag.converged && params.projectionMaxIterations <= 0) {
        diag.reason = "zero CG iterations";
    }

    const auto tApply = Clock0400::now();
    q6_compute_corrections_0400<<<cellBlocks, threads, pairShared>>>(
        cells, ws.phi.data(), ws.dux.data(), ws.duy.data(), ws.partial0.data(), ws.partial1.data(),
        grid.Nx, grid.Ny, dx, dy, params.q6ProjectionStrength, periodicX, periodicY, xHighFlux, yHighFlux, segmentedIo0409);
    check_cuda_0400(cudaGetLastError(), "compute correction launch");
    const double corrSq = reduce_host_sum_0400(ws.partial0.data(), cellBlocks);
    diag.correctionVelocityMaxAbs = reduce_host_max_0400(ws.partial1.data(), cellBlocks);
    diag.correctionVelocityRms = std::sqrt(corrSq / static_cast<double>(grid.numCells));

    q6_projected_divergence_stats_0400<<<cellBlocks, threads, pairShared>>>(
        cells, ws.dux.data(), ws.duy.data(), ws.partial0.data(), ws.partial1.data(),
        grid.Nx, grid.Ny, dx, dy, periodicX, periodicY, xLowFlux, yLowFlux, segmentedIo0409);
    check_cuda_0400(cudaGetLastError(), "projected divergence stats launch");
    const double divAfterSq = reduce_host_sum_0400(ws.partial0.data(), cellBlocks);
    diag.divAfterProjectedFluxMaxAbs = reduce_host_max_0400(ws.partial1.data(), cellBlocks);
    diag.divAfterProjectedFluxRms = std::sqrt(divAfterSq / static_cast<double>(grid.numCells));
    diag.divAfterCellVelocityRms = diag.divAfterProjectedFluxRms;
    diag.divAfterCellVelocityMaxAbs = diag.divAfterProjectedFluxMaxAbs;

    q6_reduce_sum_0400<<<cellBlocks, threads, scalarShared>>>(cells.cellMass, ws.partial0.data(),
                                                              grid.numCells);
    check_cuda_0400(cudaGetLastError(), "total mass reduction launch");
    const double totalMass = std::max(1.0e-300, reduce_host_sum_0400(ws.partial0.data(), cellBlocks));

    if (params.speciesQ6Enable) {
        const auto tSpeciesWeight0491h = Clock0400::now();
        check_cuda_0400(cudaMemset(ws.counter.data(), 0, sizeof(unsigned long long)),
                        "species q6 fallback counter zero");
        if (speciesQ6Weighted0491c && params.speciesQ6FallbackMode == "fatal") {
            q6_count_zero_alpha_bar_0491c<<<cellBlocks, threads>>>(
                species0491c, params.speciesQ6AlphaEpsilon, ws.counter.data());
            check_cuda_0400(cudaGetLastError(), "species q6 alphaBar validation launch");
            unsigned long long fallbackCount0491c = 0ull;
            check_cuda_0400(cudaMemcpy(&fallbackCount0491c, ws.counter.data(),
                                       sizeof(fallbackCount0491c), cudaMemcpyDeviceToHost),
                            "species q6 alphaBar validation counter download");
            if (fallbackCount0491c != 0ull) {
                diag.reason = "speciesQ6 fallback=fatal encountered cells with zero alphaBar";
                return diag;
            }
            check_cuda_0400(cudaMemset(ws.counter.data(), 0, sizeof(unsigned long long)),
                            "species q6 fallback counter reset after validation");
        }
        q6_species_barycentric_residual_stats_0491c<<<cellBlocks, threads, pairShared>>>(
            species0491c, ws.dux.data(), ws.duy.data(),
            params.speciesQ6Sensitivity, params.speciesQ6AlphaEpsilon,
            speciesQ6Weighted0491c ? 1 : 0,
            ws.partial0.data(), ws.partial1.data());
        check_cuda_0400(cudaGetLastError(), "species q6 barycentric residual launch");
        diag.speciesQ6BarycentricResidualMaxAbs =
            reduce_host_max_0400(ws.partial0.data(), cellBlocks);
        diag.speciesQ6BarycentricResidualMaxScaled =
            reduce_host_max_0400(ws.partial1.data(), cellBlocks);
        if (diag.speciesQ6BarycentricResidualMaxScaled > params.speciesQ6ComparisonTolerance) {
            diag.reason = "speciesQ6 barycentric recomposition scaled residual exceeded tolerance";
            return diag;
        }
        diag.speciesQ6WeightSeconds = seconds_since_0400(tSpeciesWeight0491h);
        const auto tSpeciesApply0491h = Clock0400::now();
        q6_apply_species_particle_correction_0491c<<<particleBlocks, threads, pairShared>>>(
            particles, cells, species0491c, ws.dux.data(), ws.duy.data(), nParticles,
            params.speciesQ6Sensitivity, params.speciesQ6AlphaEpsilon,
            speciesQ6Weighted0491c ? 1 : 0,
            params.speciesQ6FallbackMode == "fatal" ? 1 : 0,
            ws.partial0.data(), ws.partial1.data(), ws.counter.data());
        check_cuda_0400(cudaGetLastError(), "apply species q6 particle correction launch");
        unsigned long long fallbackCount0491c = 0ull;
        check_cuda_0400(cudaMemcpy(&fallbackCount0491c, ws.counter.data(),
                                   sizeof(fallbackCount0491c), cudaMemcpyDeviceToHost),
                        "species q6 fallback counter download");
        if (fallbackCount0491c != 0ull) {
            diag.reason = "speciesQ6 fallback=fatal encountered cells with zero alphaBar";
            return diag;
        }
        diag.speciesQ6ParticleApplySeconds = seconds_since_0400(tSpeciesApply0491h);
    } else {
        q6_apply_particle_correction_0400<<<particleBlocks, threads, pairShared>>>(
            particles, cells, ws.dux.data(), ws.duy.data(), nParticles, ws.partial0.data(), ws.partial1.data());
        check_cuda_0400(cudaGetLastError(), "apply particle correction launch");
    }
    const double dpx = reduce_host_sum_0400(ws.partial0.data(), particleBlocks);
    const double dpy = reduce_host_sum_0400(ws.partial1.data(), particleBlocks);
    diag.momentumResidualBeforeCorrection = std::sqrt(dpx * dpx + dpy * dpy);
    if (params.projectionMomentumCorrectionEnable) {
        diag.momentumCorrectionVx = dpx / totalMass;
        diag.momentumCorrectionVy = dpy / totalMass;
        q6_apply_uniform_momentum_correction_0400<<<particleBlocks, threads>>>(
            particles, nParticles, diag.momentumCorrectionVx, diag.momentumCorrectionVy);
        check_cuda_0400(cudaGetLastError(), "uniform momentum correction launch");
    }
    q6_update_corrected_cell_means_0400<<<cellBlocks, threads>>>(
        cells, ws.dux.data(), ws.duy.data(), diag.momentumCorrectionVx, diag.momentumCorrectionVy);
    check_cuda_0400(cudaGetLastError(), "update corrected cell means launch");
    diag.applySeconds = seconds_since_0400(tApply);

    cuda_shared_particle_state_0251_mark_fresh("cuda_q6_resident_0400");
    diag.applied = true;
    diag.handled = true;
    diag.reason = "ok";
    diag.totalSeconds = seconds_since_0400(tTotal);
    append_species_q6_resident_audit_0491e(
        params, step, time, static_cast<int>(params.speciesDefinitions.size()), diag);
    return diag;
}


CudaQ6ResidentThermostat0400Diagnostics try_apply_cuda_q6_resident_thermostat_0400(
    ParticleState& state,
    const SimulationParams& params,
    const CellGrid& grid,
    const std::vector<int>& collisionCellId,
    std::uint64_t step) {
    CudaQ6ResidentThermostat0400Diagnostics diag;
    diag.requested = truthy_0400(std::getenv("MPCD_CUDA_Q6_RESIDENT_THERMOSTAT_0400"));
    if (!diag.requested) {
        return diag;
    }
    const auto tTotal = Clock0400::now();
    if (!params.thermostatEnable) {
        diag.reason = "thermostat disabled";
        return diag;
    }
    if (params.thermostatEvery <= 0 ||
        (step % static_cast<std::uint64_t>(params.thermostatEvery)) != 0u) {
        diag.reason = "thermostat not due";
        return diag;
    }
    if (params.thermostatMode != "cell_relative_rescale") {
        diag.reason = "unsupported thermostat mode";
        return diag;
    }
    const double targetKBT = params.thermostatTargetKBT > 0.0 ? params.thermostatTargetKBT : params.kBT;
    if (!(targetKBT > 0.0)) {
        diag.reason = "invalid thermostat target";
        return diag;
    }
    if (!cuda_shared_particle_state_0251_is_fresh()) {
        diag.reason = "shared CUDA particle state is not fresh";
        return diag;
    }

    CudaParticleState& gpuState = cuda_shared_particle_state_0251();
    CudaParticleDeviceView particles = gpuState.device_view();
    const std::uint64_t nParticles = particles.nActiveFluid > 0u ? particles.nActiveFluid : active_fluid_count(state);
    if (nParticles == 0u || grid.numCells <= 0) {
        diag.reason = "empty particle/grid state";
        return diag;
    }
    ResidentWorkspace0400& ws = resident_workspace_0400();
    CudaCellWorkspaceDeviceView cells = ws.cells.device_view();
    if (cells.numCells != grid.numCells || cells.cellId == nullptr || cells.count == nullptr ||
        cells.cellUx == nullptr || cells.cellUy == nullptr || cells.cellKinetic == nullptr ||
        cells.cellScale == nullptr || cells.fluidCounter == nullptr) {
        diag.reason = "resident Q6 cell workspace unavailable";
        return diag;
    }

    const int threads = 256;
    const int cellBlocks = std::max(1, std::min(1024, (grid.numCells + threads - 1) / threads));
    const int particleBlocks = std::max(1, std::min(4096, static_cast<int>((nParticles + threads - 1u) / threads)));
    const std::size_t pairShared = 2u * static_cast<std::size_t>(threads) * sizeof(double);

    diag.supported = true;
    std::uint64_t cellIdH2DEntries0491f = 0u;
    if (collisionCellId.size() == static_cast<std::size_t>(nParticles)) {
        check_cuda_0400(cudaMemcpy(cells.cellId, collisionCellId.data(),
                                   static_cast<std::size_t>(nParticles) * sizeof(int),
                                   cudaMemcpyHostToDevice),
                        "thermostat collision cellId upload");
        cellIdH2DEntries0491f = nParticles;
    }
    q6_zero_cells_0400<<<cellBlocks, threads>>>(cells, ws.rhs.data(), ws.phi.data(), ws.r.data(),
                                                ws.p.data(), ws.Ap.data(), ws.dux.data(), ws.duy.data(),
                                                0);
    check_cuda_0400(cudaGetLastError(), "thermostat zero cell moments launch");
    check_cuda_0400(cudaMemset(cells.cellKinetic, 0, static_cast<std::size_t>(grid.numCells) * sizeof(double)),
                    "thermostat kinetic zero");
    check_cuda_0400(cudaMemset(cells.cellScale, 0, static_cast<std::size_t>(grid.numCells) * sizeof(double)),
                    "thermostat scale zero");
    check_cuda_0400(cudaMemset(cells.fluidCounter, 0, sizeof(unsigned long long)),
                    "thermostat fluid counter zero");
    check_cuda_0400(cudaMemset(ws.counter.data(), 0, sizeof(unsigned long long)),
                    "thermostat empty counter zero");

    auto t0 = Clock0400::now();
    q6_thermostat_deposit_moments_from_cell_ids_0400<<<particleBlocks, threads>>>(particles, cells, nParticles);
    check_cuda_0400(cudaGetLastError(), "thermostat moment deposit launch");
    q6_finalize_cells_0400<<<cellBlocks, threads>>>(cells, ws.counter.data());
    check_cuda_0400(cudaGetLastError(), "thermostat finalize moments launch");
    q6_thermostat_kinetic_0400<<<particleBlocks, threads>>>(particles, cells, nParticles);
    check_cuda_0400(cudaGetLastError(), "thermostat kinetic launch");
    diag.kineticSeconds = seconds_since_0400(t0);

    t0 = Clock0400::now();
    const int minParticles = std::max(1, params.thermostatMinParticles);
    const double epsilon = std::max(0.0, params.thermostatEpsilon);
    q6_thermostat_scale_0400<<<cellBlocks, threads, pairShared>>>(
        cells, targetKBT, minParticles, epsilon, ws.partial0.data(), ws.partial1.data());
    check_cuda_0400(cudaGetLastError(), "thermostat scale launch");
    const double totalKBefore = reduce_host_sum_0400(ws.partial0.data(), cellBlocks);
    const double targetKTotal = reduce_host_sum_0400(ws.partial1.data(), cellBlocks);
    diag.scaleSeconds = seconds_since_0400(t0);

    t0 = Clock0400::now();
    q6_thermostat_apply_0400<<<particleBlocks, threads>>>(particles, cells, nParticles);
    check_cuda_0400(cudaGetLastError(), "thermostat apply launch");
    diag.applySeconds = seconds_since_0400(t0);

    t0 = Clock0400::now();
    std::vector<std::uint32_t> hostCount(static_cast<std::size_t>(grid.numCells), 0u);
    std::vector<double> hostKinetic(static_cast<std::size_t>(grid.numCells), 0.0);
    std::vector<double> hostScale(static_cast<std::size_t>(grid.numCells), 1.0);
    unsigned long long fluidCounter = 0ull;
    check_cuda_0400(cudaMemcpy(hostCount.data(), cells.count,
                               static_cast<std::size_t>(grid.numCells) * sizeof(std::uint32_t),
                               cudaMemcpyDeviceToHost),
                    "thermostat count download");
    check_cuda_0400(cudaMemcpy(hostKinetic.data(), cells.cellKinetic,
                               static_cast<std::size_t>(grid.numCells) * sizeof(double),
                               cudaMemcpyDeviceToHost),
                    "thermostat kinetic download");
    check_cuda_0400(cudaMemcpy(hostScale.data(), cells.cellScale,
                               static_cast<std::size_t>(grid.numCells) * sizeof(double),
                               cudaMemcpyDeviceToHost),
                    "thermostat scale download");
    check_cuda_0400(cudaMemcpy(&fluidCounter, cells.fluidCounter, sizeof(unsigned long long),
                               cudaMemcpyDeviceToHost),
                    "thermostat fluid counter download");
    diag.diagnosticsDownloadSeconds = seconds_since_0400(t0);

    double scaleSum = 0.0;
    double scaleMin = std::numeric_limits<double>::infinity();
    double scaleMax = 0.0;
    std::uint64_t dofTotal = 0u;
    std::uint64_t cellsRescaled = 0u;
    std::uint64_t particlesRescaled = 0u;
    for (int c = 0; c < grid.numCells; ++c) {
        const std::uint32_t count = hostCount[static_cast<std::size_t>(c)];
        const double K = hostKinetic[static_cast<std::size_t>(c)];
        const double scale = hostScale[static_cast<std::size_t>(c)];
        if (count < static_cast<std::uint32_t>(minParticles) || !(K > epsilon)) {
            continue;
        }
        cellsRescaled += 1u;
        particlesRescaled += static_cast<std::uint64_t>(count);
        dofTotal += static_cast<std::uint64_t>(2u * (count - 1u));
        scaleSum += scale;
        scaleMin = std::min(scaleMin, scale);
        scaleMax = std::max(scaleMax, scale);
    }
    diag.thermostat.applied = cellsRescaled > 0u;
    diag.thermostat.cellsRescaled = cellsRescaled;
    diag.thermostat.particlesRescaled = particlesRescaled;
    diag.thermostat.kBTBefore = dofTotal > 0u ? (2.0 * totalKBefore / static_cast<double>(dofTotal)) : 0.0;
    diag.thermostat.kBTAfter = dofTotal > 0u ? (2.0 * targetKTotal / static_cast<double>(dofTotal)) : 0.0;
    diag.thermostat.scaleMean = cellsRescaled > 0u ? scaleSum / static_cast<double>(cellsRescaled) : 1.0;
    diag.thermostat.scaleMin = cellsRescaled > 0u ? scaleMin : 1.0;
    diag.thermostat.scaleMax = cellsRescaled > 0u ? scaleMax : 1.0;
    (void)fluidCounter;
    state.NactiveFluid = nParticles;
    cuda_shared_particle_state_0251_mark_fresh("cuda_q6_resident_thermostat_0400");
    diag.handled = true;
    diag.reason = "ok";
    diag.totalSeconds = seconds_since_0400(tTotal);
    append_q6_resident_thermostat_audit_0491f(
        params, step, targetKBT, cellIdH2DEntries0491f, diag);
    return diag;
}

} // namespace mpcd

#endif
