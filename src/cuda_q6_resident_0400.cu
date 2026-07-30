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
    int mode[kOpenBoundaryMaxSegments]{}; // 1 inlet, 2 outlet
    std::uint32_t type[kOpenBoundaryMaxSegments]{};
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

struct IndependentMaskedSpeciesAudit0493w5 {
    int speciesIndex = -1;
    std::uint32_t type = 0u;
    double strength = 0.0;
    std::uint64_t activeCells = 0u;
    std::uint64_t correctedParticles = 0u;
    bool fullDomain = false;
    bool converged = true;
    int iterations = 0;
    double residualRel = 0.0;
    double divBeforeRms = 0.0;
    double divBeforeMaxAbs = 0.0;
    // Compatibility aliases retained for the original 0493w5 CSV schema.
    // They continue to denote the divergence of the projected auxiliary face flux.
    double divAfterRms = 0.0;
    double divAfterMaxAbs = 0.0;
    double divAfterProjectedFaceFluxRms = 0.0;
    double divAfterProjectedFaceFluxMaxAbs = 0.0;
    // 0493w6: divergence rebuilt from the post-application, per-species
    // cell velocity deposited directly from the resident particle state.
    double divAfterAppliedCellVelocityRms = 0.0;
    double divAfterAppliedCellVelocityMaxAbs = 0.0;
    double correctionRms = 0.0;
    double correctionMaxAbs = 0.0;
    double momentumX = 0.0;
    double momentumY = 0.0;
};

void append_independent_masked_species_audit_0493w5(
    const SimulationParams& params,
    int step,
    double time,
    const std::vector<IndependentMaskedSpeciesAudit0493w5>& rows) {
    if (params.outputDir.empty()) return;
    const std::filesystem::path path = std::filesystem::path(params.outputDir) /
        "cuda_species_q6_independent_masked_0493w5.csv";
    std::filesystem::create_directories(path.parent_path());
    const bool header = !std::filesystem::exists(path) ||
                        std::filesystem::file_size(path) == 0u;
    std::ofstream out(path, std::ios::app);
    if (!out) {
        throw std::runtime_error(
            "0493w5 failed to open independent-masked species Q6 audit CSV: " +
            path.string());
    }
    if (header) {
        out << "step,time,speciesIndex,type,q6Strength,minOccupancyFraction,"
               "activeCells,fullDomain,correctedParticles,converged,iterations,"
               "residualRel,divBeforeRms,divBeforeMaxAbs,divAfterRms,"
               "divAfterMaxAbs,divAfterProjectedFaceFluxRms,"
               "divAfterProjectedFaceFluxMaxAbs,divAfterAppliedCellVelocityRms,"
               "divAfterAppliedCellVelocityMaxAbs,correctionRms,correctionMaxAbs,"
               "momentumX,momentumY\n";
    }
    for (const IndependentMaskedSpeciesAudit0493w5& r : rows) {
        out << std::setprecision(17)
            << step << ',' << time << ',' << r.speciesIndex << ',' << r.type << ','
            << r.strength << ',' << params.speciesQ6MinOccupancyFraction << ','
            << r.activeCells << ',' << (r.fullDomain ? 1 : 0) << ','
            << r.correctedParticles << ',' << (r.converged ? 1 : 0) << ','
            << r.iterations << ',' << r.residualRel << ','
            << r.divBeforeRms << ',' << r.divBeforeMaxAbs << ','
            << r.divAfterRms << ',' << r.divAfterMaxAbs << ','
            << r.divAfterProjectedFaceFluxRms << ','
            << r.divAfterProjectedFaceFluxMaxAbs << ','
            << r.divAfterAppliedCellVelocityRms << ','
            << r.divAfterAppliedCellVelocityMaxAbs << ','
            << r.correctionRms << ',' << r.correctionMaxAbs << ','
            << r.momentumX << ',' << r.momentumY << '\n';
    }
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
        cfg.mode[k] = open_boundary_segment_is_inlet(seg) ? 1 : 2;
        cfg.type[k] = seg.type;
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
    DeviceBuffer0400<unsigned char> speciesMask0493w5;
    // 0493w6 keeps the exact pre-application support mask of every species on
    // device.  The post-application diagnostic therefore cannot be perturbed by
    // a second threshold evaluation or require a host-side cell mask.
    DeviceBuffer0400<unsigned char> speciesMasks0493w6;
    DeviceBuffer0400<double> speciesDUx0493w5;
    DeviceBuffer0400<double> speciesDUy0493w5;
    DeviceBuffer0400<double> partial0;
    DeviceBuffer0400<double> partial1;
    DeviceBuffer0400<double> partial2;
    DeviceBuffer0400<unsigned long long> counter;
    bool warmPhiValid = false;
    int warmNx = 0;
    int warmNy = 0;
    int warmPeriodicX = 0;
    int warmPeriodicY = 0;

    void ensure(std::uint64_t particles, int numCells, int blocks, int speciesCount = 1) {
        cells.ensure_capacity(particles, numCells);
        const std::size_t c = static_cast<std::size_t>(std::max(1, numCells));
        const std::size_t denseSpecies = c * static_cast<std::size_t>(std::max(1, speciesCount));
        rhs.ensure(c);
        phi.ensure(c);
        r.ensure(c);
        p.ensure(c);
        Ap.ensure(c);
        dux.ensure(c);
        duy.ensure(c);
        speciesMask0493w5.ensure(c);
        speciesMasks0493w6.ensure(denseSpecies);
        speciesDUx0493w5.ensure(denseSpecies);
        speciesDUy0493w5.ensure(denseSpecies);
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



__device__ double q6_species_boundary_fraction_0493w7(
    CudaSpeciesCellDeviceView0490h species,
    int speciesIndex,
    int cell,
    int exclusiveProjectedSpecies) {
    if (exclusiveProjectedSpecies) return 1.0;
    if (speciesIndex < 0 || speciesIndex >= species.speciesCount ||
        cell < 0 || cell >= species.numCells) {
        return 0.0;
    }
    const int k = speciesIndex * species.numCells + cell;
    return fmin(1.0, fmax(0.0, species.occupancyFraction[k]));
}

__device__ double q6_species_boundary_flux_for_cell_0493w7(
    const Q6SegmentedIo0409& cfg,
    int face,
    int ix,
    int iy,
    int nx,
    int ny,
    double fallback,
    CudaSpeciesCellDeviceView0490h species,
    int speciesIndex,
    std::uint32_t speciesType,
    int cell,
    int exclusiveProjectedSpecies) {
    const double fraction = q6_species_boundary_fraction_0493w7(
        species, speciesIndex, cell, exclusiveProjectedSpecies);
    if (!cfg.enabled) return fallback * fraction;
    const double tangent = (face == 0 || face == 1)
        ? ((static_cast<double>(iy) + 0.5) /
           static_cast<double>(ny > 0 ? ny : 1))
        : ((static_cast<double>(ix) + 0.5) /
           static_cast<double>(nx > 0 ? nx : 1));
    for (int k = 0; k < cfg.count; ++k) {
        if (cfg.face[k] != face || tangent < cfg.sMin[k] || tangent > cfg.sMax[k]) {
            continue;
        }
        if (cfg.mode[k] == 1) {
            // A typed reservoir injects only its declared species.  Untyped
            // legacy inlets fall back to the local occupancy split.
            if (cfg.type[k] != 0u) {
                return cfg.type[k] == speciesType ? cfg.flux[k] : 0.0;
            }
            return cfg.flux[k] * fraction;
        }
        // Outlet flux is shared only when several species are independently
        // projected.  With the liquid-only target configuration, the sole
        // projected species retains the full prescribed outlet flux.
        return cfg.flux[k] * fraction;
    }
    // The complement of a segmented face remains an impermeable wall.
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
        species.count[k] = 0u;
        species.mass[k] = 0.0;
        species.px[k] = 0.0;
        species.py[k] = 0.0;
        species.massFraction[k] = 0.0;
        species.occupancyFraction[k] = 0.0;
    }
    for (int c = tid; c < species.numCells; c += stride) {
        species.totalCellMass[c] = 0.0;
        species.totalOccupancyWeight[c] = 0.0;
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
        const int k = speciesIndex * species.numCells + c;
        const double m = particles.mass ? particles.mass[i] : 1.0;
        atomicAdd(&species.count[k], 1u);
        atomic_add_double_0400(&species.mass[k], m);
        atomic_add_double_0400(&species.px[k], m * particles.vx[i]);
        atomic_add_double_0400(&species.py[k], m * particles.vy[i]);
        atomic_add_double_0400(&species.totalCellMass[c], m);
    }
}

__global__ void q6_finalize_species_occupancy_0493w5(
    CudaSpeciesCellDeviceView0490h species) {
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    const int stride = blockDim.x * gridDim.x;
    for (int c = idx; c < species.numCells; c += stride) {
        const double totalMass = species.totalCellMass[c];
        double totalOcc = 0.0;
        for (int s = 0; s < species.speciesCount; ++s) {
            const int k = s * species.numCells + c;
            const double ref = species.referenceCellMass[s];
            if (ref > 0.0) totalOcc += species.mass[k] / ref;
        }
        species.totalOccupancyWeight[c] = totalOcc;
        for (int s = 0; s < species.speciesCount; ++s) {
            const int k = s * species.numCells + c;
            species.massFraction[k] = totalMass > 0.0 ? species.mass[k] / totalMass : 0.0;
            const double ref = species.referenceCellMass[s];
            const double occ = ref > 0.0 ? species.mass[k] / ref : 0.0;
            species.occupancyFraction[k] = totalOcc > 0.0 ? occ / totalOcc : 0.0;
        }
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


__device__ bool q6_species_cell_active_0493w5(
    CudaSpeciesCellDeviceView0490h species,
    int speciesIndex,
    int cell,
    double minOccupancyFraction) {
    if (speciesIndex < 0 || speciesIndex >= species.speciesCount ||
        cell < 0 || cell >= species.numCells) {
        return false;
    }
    const int k = speciesIndex * species.numCells + cell;
    return species.q6Strength[speciesIndex] > 0.0 &&
           species.mass[k] > 0.0 &&
           species.occupancyFraction[k] >= minOccupancyFraction;
}

__device__ double q6_species_cell_velocity_component_0493w5(
    CudaSpeciesCellDeviceView0490h species,
    int speciesIndex,
    int cell,
    int component) {
    const int k = speciesIndex * species.numCells + cell;
    const double m = species.mass[k];
    if (!(m > 0.0)) return 0.0;
    return component == 0 ? species.px[k] / m : species.py[k] / m;
}

__device__ double q6_species_face_velocity_0493w5(
    CudaSpeciesCellDeviceView0490h species,
    const unsigned char* mask,
    int speciesIndex,
    int cellA,
    int cellB,
    int component) {
    const bool activeA = mask[cellA] != 0u;
    const bool activeB = mask[cellB] != 0u;
    if (!activeA && !activeB) return 0.0;
    const double ua = activeA
        ? q6_species_cell_velocity_component_0493w5(species, speciesIndex, cellA, component)
        : 0.0;
    const double ub = activeB
        ? q6_species_cell_velocity_component_0493w5(species, speciesIndex, cellB, component)
        : 0.0;
    if (activeA && activeB) return 0.5 * (ua + ub);
    return activeA ? ua : ub;
}

__global__ void q6_build_independent_mask_0493w5(
    CudaSpeciesCellDeviceView0490h species,
    int speciesIndex,
    double minOccupancyFraction,
    unsigned char* mask,
    double* rhs,
    int n,
    unsigned long long* activeCounter) {
    unsigned long long activeLocal = 0ull;
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    const int stride = blockDim.x * gridDim.x;
    for (int c = idx; c < n; c += stride) {
        const bool active = q6_species_cell_active_0493w5(
            species, speciesIndex, c, minOccupancyFraction);
        mask[c] = active ? 1u : 0u;
        rhs[c] = 0.0;
        if (active) ++activeLocal;
    }
    if (activeLocal != 0ull) atomicAdd(activeCounter, activeLocal);
}

__global__ void q6_build_independent_rhs_after_mask_0493w5(
    CudaSpeciesCellDeviceView0490h species,
    int speciesIndex,
    const unsigned char* mask,
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
    Q6SegmentedIo0409 segmentedIo,
    std::uint32_t speciesType,
    int exclusiveProjectedSpecies,
    int fullDomain) {
    extern __shared__ double sh[];
    double* shSum = sh;
    double* shSq = sh + blockDim.x;
    double* shMax = sh + 2 * blockDim.x;
    const int tid = threadIdx.x;
    double sum = 0.0;
    double sq = 0.0;
    double mx = 0.0;
    const int n = nx * ny;
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    const int stride = blockDim.x * gridDim.x;
    for (int c = idx; c < n; c += stride) {
        if (mask[c] == 0u) {
            rhs[c] = 0.0;
            continue;
        }
        const int ix = c % nx;
        const int iy = c / nx;
        const bool hasEast = periodicX || ix < nx - 1;
        const bool hasWest = periodicX || ix > 0;
        const bool hasNorth = periodicY || iy < ny - 1;
        const bool hasSouth = periodicY || iy > 0;
        const int east = hasEast
            ? iy * nx + (periodicX ? wrap_cell_index_0400(ix + 1, nx) : ix + 1)
            : c;
        const int west = hasWest
            ? iy * nx + (periodicX ? wrap_cell_index_0400(ix - 1, nx) : ix - 1)
            : c;
        const int north = hasNorth
            ? (periodicY ? wrap_cell_index_0400(iy + 1, ny) : iy + 1) * nx + ix
            : c;
        const int south = hasSouth
            ? (periodicY ? wrap_cell_index_0400(iy - 1, ny) : iy - 1) * nx + ix
            : c;

        const double localXLowFlux = q6_species_boundary_flux_for_cell_0493w7(
            segmentedIo, 0, ix, iy, nx, ny, xLowFlux, species, speciesIndex,
            speciesType, c, exclusiveProjectedSpecies);
        const double localXHighFlux = q6_species_boundary_flux_for_cell_0493w7(
            segmentedIo, 1, ix, iy, nx, ny, xHighFlux, species, speciesIndex,
            speciesType, c, exclusiveProjectedSpecies);
        const double localYLowFlux = q6_species_boundary_flux_for_cell_0493w7(
            segmentedIo, 2, ix, iy, nx, ny, yLowFlux, species, speciesIndex,
            speciesType, c, exclusiveProjectedSpecies);
        const double localYHighFlux = q6_species_boundary_flux_for_cell_0493w7(
            segmentedIo, 3, ix, iy, nx, ny, yHighFlux, species, speciesIndex,
            speciesType, c, exclusiveProjectedSpecies);

        const double uxC = q6_species_cell_velocity_component_0493w5(
            species, speciesIndex, c, 0);
        const double uyC = q6_species_cell_velocity_component_0493w5(
            species, speciesIndex, c, 1);
        const double fxEastInterior = fullDomain
            ? uxC
            : q6_species_face_velocity_0493w5(
                species, mask, speciesIndex, c, east, 0);
        const double fxWestInterior = fullDomain
            ? q6_species_cell_velocity_component_0493w5(
                species, speciesIndex, west, 0)
            : q6_species_face_velocity_0493w5(
                species, mask, speciesIndex, west, c, 0);
        const double fyNorthInterior = fullDomain
            ? uyC
            : q6_species_face_velocity_0493w5(
                species, mask, speciesIndex, c, north, 1);
        const double fySouthInterior = fullDomain
            ? q6_species_cell_velocity_component_0493w5(
                species, speciesIndex, south, 1)
            : q6_species_face_velocity_0493w5(
                species, mask, speciesIndex, south, c, 1);

        const double fxWest = hasWest ? fxWestInterior : localXLowFlux;
        const double fxEastBefore = hasEast ? fxEastInterior : uxC;
        const double fxEastSolve = hasEast ? fxEastInterior : localXHighFlux;
        const double fySouth = hasSouth ? fySouthInterior : localYLowFlux;
        const double fyNorthBefore = hasNorth ? fyNorthInterior : uyC;
        const double fyNorthSolve = hasNorth ? fyNorthInterior : localYHighFlux;
        const double divBefore = (fxEastBefore - fxWest) / dx +
                                 (fyNorthBefore - fySouth) / dy;
        const double divSolve = (fxEastSolve - fxWest) / dx +
                                (fyNorthSolve - fySouth) / dy;
        rhs[c] = -divSolve;
        sum += rhs[c];
        sq += divBefore * divBefore;
        mx = fmax(mx, fabs(divBefore));
    }
    shSum[tid] = sum;
    shSq[tid] = sq;
    shMax[tid] = mx;
    __syncthreads();
    for (int offset = blockDim.x / 2; offset > 0; offset >>= 1) {
        if (tid < offset) {
            shSum[tid] += shSum[tid + offset];
            shSq[tid] += shSq[tid + offset];
            shMax[tid] = fmax(shMax[tid], shMax[tid + offset]);
        }
        __syncthreads();
    }
    if (tid == 0) {
        partialSum[blockIdx.x] = shSum[0];
        partialSq[blockIdx.x] = shSq[0];
        partialMax[blockIdx.x] = shMax[0];
    }
}

__global__ void q6_init_masked_cg_0493w5(
    double* rhs,
    double* phi,
    double* r,
    double* p,
    const unsigned char* mask,
    double mean,
    int subtractMean,
    int n) {
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    const int stride = blockDim.x * gridDim.x;
    for (int c = idx; c < n; c += stride) {
        if (mask[c] == 0u) {
            rhs[c] = 0.0;
            phi[c] = 0.0;
            r[c] = 0.0;
            p[c] = 0.0;
            continue;
        }
        const double v = rhs[c] - (subtractMean ? mean : 0.0);
        rhs[c] = v;
        phi[c] = 0.0;
        r[c] = v;
        p[c] = v;
    }
}

__global__ void q6_apply_masked_operator_and_dot_0493w5(
    const double* p,
    double* Ap,
    const unsigned char* mask,
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
        if (mask[c] == 0u) {
            Ap[c] = 0.0;
            continue;
        }
        const int ix = c % nx;
        const int iy = c / nx;
        double a = 0.0;
        if (periodicX || ix < nx - 1) {
            const int east = iy * nx +
                (periodicX ? wrap_cell_index_0400(ix + 1, nx) : ix + 1);
            a += invDx2 * (p[c] - (mask[east] ? p[east] : 0.0));
        }
        if (periodicX || ix > 0) {
            const int west = iy * nx +
                (periodicX ? wrap_cell_index_0400(ix - 1, nx) : ix - 1);
            a += invDx2 * (p[c] - (mask[west] ? p[west] : 0.0));
        }
        if (periodicY || iy < ny - 1) {
            const int north =
                (periodicY ? wrap_cell_index_0400(iy + 1, ny) : iy + 1) * nx + ix;
            a += invDy2 * (p[c] - (mask[north] ? p[north] : 0.0));
        }
        if (periodicY || iy > 0) {
            const int south =
                (periodicY ? wrap_cell_index_0400(iy - 1, ny) : iy - 1) * nx + ix;
            a += invDy2 * (p[c] - (mask[south] ? p[south] : 0.0));
        }
        Ap[c] = a;
        dot += p[c] * a;
    }
    sh[tid] = dot;
    __syncthreads();
    for (int offset = blockDim.x / 2; offset > 0; offset >>= 1) {
        if (tid < offset) sh[tid] += sh[tid + offset];
        __syncthreads();
    }
    if (tid == 0) partialDot[blockIdx.x] = sh[0];
}

__global__ void q6_compute_masked_face_correction_0493w5(
    CudaSpeciesCellDeviceView0490h species,
    int speciesIndex,
    const double* phi,
    const unsigned char* mask,
    double* faceDUx,
    double* faceDUy,
    int nx,
    int ny,
    double dx,
    double dy,
    double strength,
    int periodicX,
    int periodicY,
    double xHighFlux,
    double yHighFlux,
    Q6SegmentedIo0409 segmentedIo,
    std::uint32_t speciesType,
    int exclusiveProjectedSpecies) {
    const int n = nx * ny;
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    const int stride = blockDim.x * gridDim.x;
    for (int c = idx; c < n; c += stride) {
        const int ix = c % nx;
        const int iy = c / nx;
        const bool hasEast = periodicX || ix < nx - 1;
        const bool hasNorth = periodicY || iy < ny - 1;
        const int east = hasEast
            ? iy * nx + (periodicX ? wrap_cell_index_0400(ix + 1, nx) : ix + 1)
            : c;
        const int north = hasNorth
            ? (periodicY ? wrap_cell_index_0400(iy + 1, ny) : iy + 1) * nx + ix
            : c;

        if (hasEast) {
            if (mask[c] || mask[east]) {
                const double pc = mask[c] ? phi[c] : 0.0;
                const double pe = mask[east] ? phi[east] : 0.0;
                faceDUx[c] = -strength * (pe - pc) / dx;
            } else {
                faceDUx[c] = 0.0;
            }
        } else if (mask[c]) {
            const double target = q6_species_boundary_flux_for_cell_0493w7(
                segmentedIo, 1, ix, iy, nx, ny, xHighFlux, species, speciesIndex,
                speciesType, c, exclusiveProjectedSpecies);
            const double before = q6_species_cell_velocity_component_0493w5(
                species, speciesIndex, c, 0);
            faceDUx[c] = strength * (target - before);
        } else {
            faceDUx[c] = 0.0;
        }

        if (hasNorth) {
            if (mask[c] || mask[north]) {
                const double pc = mask[c] ? phi[c] : 0.0;
                const double pn = mask[north] ? phi[north] : 0.0;
                faceDUy[c] = -strength * (pn - pc) / dy;
            } else {
                faceDUy[c] = 0.0;
            }
        } else if (mask[c]) {
            const double target = q6_species_boundary_flux_for_cell_0493w7(
                segmentedIo, 3, ix, iy, nx, ny, yHighFlux, species, speciesIndex,
                speciesType, c, exclusiveProjectedSpecies);
            const double before = q6_species_cell_velocity_component_0493w5(
                species, speciesIndex, c, 1);
            faceDUy[c] = strength * (target - before);
        } else {
            faceDUy[c] = 0.0;
        }
    }
}

__global__ void q6_compute_masked_cell_correction_stats_0493w5(
    const unsigned char* mask,
    const double* faceDUx,
    const double* faceDUy,
    double* cellDUx,
    double* cellDUy,
    double* partialSq,
    double* partialMax,
    int nx,
    int ny,
    int periodicX,
    int periodicY,
    int fullDomain) {
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
        if (mask[c] == 0u) {
            cellDUx[c] = 0.0;
            cellDUy[c] = 0.0;
            continue;
        }
        const int ix = c % nx;
        const int iy = c / nx;
        const bool hasWest = periodicX || ix > 0;
        const bool hasSouth = periodicY || iy > 0;
        const int west = hasWest
            ? iy * nx + (periodicX ? wrap_cell_index_0400(ix - 1, nx) : ix - 1)
            : c;
        const int south = hasSouth
            ? (periodicY ? wrap_cell_index_0400(iy - 1, ny) : iy - 1) * nx + ix
            : c;
        const double westCorrection = hasWest ? faceDUx[west] : 0.0;
        const double southCorrection = hasSouth ? faceDUy[south] : 0.0;
        const double cx = fullDomain
            ? faceDUx[c]
            : 0.5 * (faceDUx[c] + westCorrection);
        const double cy = fullDomain
            ? faceDUy[c]
            : 0.5 * (faceDUy[c] + southCorrection);
        cellDUx[c] = cx;
        cellDUy[c] = cy;
        const double q = cx * cx + cy * cy;
        sq += q;
        mx = fmax(mx, sqrt(q));
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

__global__ void q6_masked_projected_divergence_stats_0493w5(
    CudaSpeciesCellDeviceView0490h species,
    int speciesIndex,
    const unsigned char* mask,
    const double* faceDUx,
    const double* faceDUy,
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
    Q6SegmentedIo0409 segmentedIo,
    std::uint32_t speciesType,
    int exclusiveProjectedSpecies,
    int fullDomain) {
    extern __shared__ double sh[];
    double* shSq = sh;
    double* shMax = sh + blockDim.x;
    const int tid = threadIdx.x;
    (void)xHighFlux;
    (void)yHighFlux;
    double sq = 0.0;
    double mx = 0.0;
    const int n = nx * ny;
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    const int stride = blockDim.x * gridDim.x;
    for (int c = idx; c < n; c += stride) {
        if (mask[c] == 0u) continue;
        const int ix = c % nx;
        const int iy = c / nx;
        const bool hasEast = periodicX || ix < nx - 1;
        const bool hasWest = periodicX || ix > 0;
        const bool hasNorth = periodicY || iy < ny - 1;
        const bool hasSouth = periodicY || iy > 0;
        const int east = hasEast
            ? iy * nx + (periodicX ? wrap_cell_index_0400(ix + 1, nx) : ix + 1)
            : c;
        const int west = hasWest
            ? iy * nx + (periodicX ? wrap_cell_index_0400(ix - 1, nx) : ix - 1)
            : c;
        const int north = hasNorth
            ? (periodicY ? wrap_cell_index_0400(iy + 1, ny) : iy + 1) * nx + ix
            : c;
        const int south = hasSouth
            ? (periodicY ? wrap_cell_index_0400(iy - 1, ny) : iy - 1) * nx + ix
            : c;

        const double localXLowFlux = q6_species_boundary_flux_for_cell_0493w7(
            segmentedIo, 0, ix, iy, nx, ny, xLowFlux, species, speciesIndex,
            speciesType, c, exclusiveProjectedSpecies);
        const double localYLowFlux = q6_species_boundary_flux_for_cell_0493w7(
            segmentedIo, 2, ix, iy, nx, ny, yLowFlux, species, speciesIndex,
            speciesType, c, exclusiveProjectedSpecies);

        const double uxC = q6_species_cell_velocity_component_0493w5(
            species, speciesIndex, c, 0);
        const double uyC = q6_species_cell_velocity_component_0493w5(
            species, speciesIndex, c, 1);
        const double fxEastBase = hasEast
            ? (fullDomain ? uxC : q6_species_face_velocity_0493w5(
                species, mask, speciesIndex, c, east, 0))
            : uxC;
        const double fxWestBase = hasWest
            ? (fullDomain ? q6_species_cell_velocity_component_0493w5(
                    species, speciesIndex, west, 0)
                : q6_species_face_velocity_0493w5(
                    species, mask, speciesIndex, west, c, 0))
            : localXLowFlux;
        const double fyNorthBase = hasNorth
            ? (fullDomain ? uyC : q6_species_face_velocity_0493w5(
                species, mask, speciesIndex, c, north, 1))
            : uyC;
        const double fySouthBase = hasSouth
            ? (fullDomain ? q6_species_cell_velocity_component_0493w5(
                    species, speciesIndex, south, 1)
                : q6_species_face_velocity_0493w5(
                    species, mask, speciesIndex, south, c, 1))
            : localYLowFlux;

        const double fxEast = fxEastBase + faceDUx[c];
        const double fxWest = hasWest ? fxWestBase + faceDUx[west] : fxWestBase;
        const double fyNorth = fyNorthBase + faceDUy[c];
        const double fySouth = hasSouth ? fySouthBase + faceDUy[south] : fySouthBase;
        const double div = (fxEast - fxWest) / dx + (fyNorth - fySouth) / dy;
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

__global__ void q6_apply_independent_species_correction_0493w5(
    CudaParticleDeviceView particles,
    CudaCellWorkspaceDeviceView cells,
    CudaSpeciesCellDeviceView0490h species,
    int speciesIndex,
    double minOccupancyFraction,
    const double* cellDUx,
    const double* cellDUy,
    std::uint32_t speciesType,
    std::uint64_t nParticles,
    double* partialPx,
    double* partialPy,
    unsigned long long* correctedCounter) {
    extern __shared__ double sh[];
    double* shX = sh;
    double* shY = sh + blockDim.x;
    const int tid = threadIdx.x;
    double px = 0.0;
    double py = 0.0;
    unsigned long long correctedLocal = 0ull;
    const std::uint64_t idx = blockIdx.x * blockDim.x + threadIdx.x;
    const std::uint64_t stride = static_cast<std::uint64_t>(blockDim.x) * gridDim.x;
    for (std::uint64_t i = idx; i < nParticles; i += stride) {
        if (particles.role != nullptr && particles.role[i] != kParticleRoleFluid) continue;
        if (particles.type == nullptr || particles.type[i] != speciesType) continue;
        const int c = cells.cellId[i];
        if (c < 0 || !q6_species_cell_active_0493w5(
                species, speciesIndex, c, minOccupancyFraction)) continue;
        const double dvx = cellDUx[c];
        const double dvy = cellDUy[c];
        particles.vx[i] += dvx;
        particles.vy[i] += dvy;
        const double m = particles.mass ? particles.mass[i] : 1.0;
        px += m * dvx;
        py += m * dvy;
        ++correctedLocal;
    }
    if (correctedLocal != 0ull) atomicAdd(correctedCounter, correctedLocal);
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

__global__ void q6_zero_cell_moments_only_0493w5(CudaCellWorkspaceDeviceView cells) {
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    const int stride = blockDim.x * gridDim.x;
    for (int c = idx; c < cells.numCells; c += stride) {
        cells.count[c] = 0u;
        cells.cellMass[c] = 0.0;
        cells.cellPx[c] = 0.0;
        cells.cellPy[c] = 0.0;
        cells.cellUx[c] = 0.0;
        cells.cellUy[c] = 0.0;
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


bool apply_independent_masked_species_q6_0493w5(
    CudaParticleDeviceView particles,
    CudaCellWorkspaceDeviceView cells,
    CudaSpeciesCellDeviceView0490h species,
    ResidentWorkspace0400& ws,
    const SimulationParams& params,
    const CellGrid& grid,
    int step,
    double time,
    std::uint64_t nParticles,
    int threads,
    int cellBlocks,
    int particleBlocks,
    std::size_t scalarShared,
    std::size_t pairShared,
    std::size_t tripleShared,
    int periodicX,
    int periodicY,
    double xLowFlux,
    double xHighFlux,
    double yLowFlux,
    double yHighFlux,
    Q6SegmentedIo0409 segmentedIo,
    CudaQ6Resident0400Diagnostics& diag) {
    const auto tSolveAll = Clock0400::now();
    const int speciesCount = static_cast<int>(params.speciesDefinitions.size());
    const std::size_t dense = static_cast<std::size_t>(grid.numCells) *
                              static_cast<std::size_t>(speciesCount);
    check_cuda_0400(cudaMemset(ws.speciesMasks0493w6.data(), 0,
                                   dense * sizeof(unsigned char)),
                    "independent masked dense support zero");
    check_cuda_0400(cudaMemset(ws.speciesDUx0493w5.data(), 0, dense * sizeof(double)),
                    "independent masked dux zero");
    check_cuda_0400(cudaMemset(ws.speciesDUy0493w5.data(), 0, dense * sizeof(double)),
                    "independent masked duy zero");

    std::vector<IndependentMaskedSpeciesAudit0493w5> audits;
    audits.reserve(static_cast<std::size_t>(speciesCount));
    double totalDivBeforeSq = 0.0;
    double totalDivAfterSq = 0.0;
    double totalCorrectionSq = 0.0;
    std::uint64_t totalActiveCells = 0u;
    double maxDivBefore = 0.0;
    double maxDivAfter = 0.0;
    double maxCorrection = 0.0;
    int maxIterations = 0;
    double maxResidualRel = 0.0;
    bool allConverged = true;
    const double dx = grid.dx;
    const double dy = grid.dy;
    const double invDx2 = 1.0 / (dx * dx);
    const double invDy2 = 1.0 / (dy * dy);
    const double tol = std::max(0.0, params.projectionTolerance);
    int projectedSpeciesCount = 0;
    for (const SpeciesDefinition& def : params.speciesDefinitions) {
        if (def.q6StrengthDeclared > 0.0) ++projectedSpeciesCount;
    }
    const int exclusiveProjectedSpecies = projectedSpeciesCount == 1 ? 1 : 0;

    for (int s = 0; s < speciesCount; ++s) {
        IndependentMaskedSpeciesAudit0493w5 audit{};
        audit.speciesIndex = s;
        audit.type = params.speciesDefinitions[static_cast<std::size_t>(s)].type;
        audit.strength = params.speciesDefinitions[static_cast<std::size_t>(s)].q6StrengthDeclared;
        if (!(audit.strength > 0.0)) {
            audits.push_back(audit);
            continue;
        }

        check_cuda_0400(cudaMemset(ws.counter.data(), 0, sizeof(unsigned long long)),
                        "independent masked active counter zero");
        q6_build_independent_mask_0493w5<<<cellBlocks, threads>>>(
            species, s, params.speciesQ6MinOccupancyFraction,
            ws.speciesMask0493w5.data(), ws.rhs.data(),
            grid.numCells, ws.counter.data());
        check_cuda_0400(cudaGetLastError(), "independent masked support launch");
        unsigned char* denseMask0493w6 = ws.speciesMasks0493w6.data() +
            static_cast<std::size_t>(s) * static_cast<std::size_t>(grid.numCells);
        check_cuda_0400(cudaMemcpy(denseMask0493w6, ws.speciesMask0493w5.data(),
                                   static_cast<std::size_t>(grid.numCells) *
                                       sizeof(unsigned char),
                                   cudaMemcpyDeviceToDevice),
                        "independent masked dense support store");
        unsigned long long activeCells = 0ull;
        check_cuda_0400(cudaMemcpy(&activeCells, ws.counter.data(), sizeof(activeCells),
                                   cudaMemcpyDeviceToHost),
                        "independent masked active counter download");
        audit.activeCells = static_cast<std::uint64_t>(activeCells);
        audit.fullDomain = audit.activeCells == static_cast<std::uint64_t>(grid.numCells);
        if (audit.activeCells == 0u) {
            audits.push_back(audit);
            continue;
        }

        q6_build_independent_rhs_after_mask_0493w5<<<cellBlocks, threads, tripleShared>>>(
            species, s, ws.speciesMask0493w5.data(), ws.rhs.data(),
            ws.partial0.data(), ws.partial1.data(), ws.partial2.data(),
            grid.Nx, grid.Ny, dx, dy, periodicX, periodicY,
            xLowFlux, xHighFlux, yLowFlux, yHighFlux, segmentedIo,
            audit.type, exclusiveProjectedSpecies, audit.fullDomain ? 1 : 0);
        check_cuda_0400(cudaGetLastError(), "independent masked rhs launch");
        const double rhsSum = reduce_host_sum_0400(ws.partial0.data(), cellBlocks);
        const double divBeforeSq = reduce_host_sum_0400(ws.partial1.data(), cellBlocks);
        audit.divBeforeMaxAbs = reduce_host_max_0400(ws.partial2.data(), cellBlocks);
        audit.divBeforeRms = std::sqrt(
            divBeforeSq / static_cast<double>(std::max<std::uint64_t>(1u, audit.activeCells)));
        const double rhsMean = audit.fullDomain
            ? rhsSum / static_cast<double>(grid.numCells)
            : 0.0;

        q6_init_masked_cg_0493w5<<<cellBlocks, threads>>>(
            ws.rhs.data(), ws.phi.data(), ws.r.data(), ws.p.data(),
            ws.speciesMask0493w5.data(), rhsMean, audit.fullDomain ? 1 : 0,
            grid.numCells);
        check_cuda_0400(cudaGetLastError(), "independent masked cg init launch");
        q6_reduce_square_sum_0400<<<cellBlocks, threads, scalarShared>>>(
            ws.r.data(), ws.partial0.data(), grid.numCells);
        check_cuda_0400(cudaGetLastError(), "independent masked initial rr launch");
        double rr = reduce_host_sum_0400(ws.partial0.data(), cellBlocks);
        const double rhsNorm = std::sqrt(std::max(0.0, rr));
        const double rhsNormSafe = std::max(rhsNorm, 1.0e-300);
        audit.converged = rhsNorm <= tol;
        audit.residualRel = audit.converged ? 0.0 : 1.0;

        for (int it = 0; it < params.projectionMaxIterations && !audit.converged; ++it) {
            q6_apply_masked_operator_and_dot_0493w5<<<cellBlocks, threads, scalarShared>>>(
                ws.p.data(), ws.Ap.data(), ws.speciesMask0493w5.data(),
                ws.partial0.data(), grid.Nx, grid.Ny, invDx2, invDy2,
                periodicX, periodicY);
            check_cuda_0400(cudaGetLastError(), "independent masked operator launch");
            const double pAp = reduce_host_sum_0400(ws.partial0.data(), cellBlocks);
            if (!(pAp > 0.0) || !std::isfinite(pAp)) {
                audit.converged = false;
                audit.residualRel = std::numeric_limits<double>::infinity();
                break;
            }
            const double alpha = rr / pAp;
            q6_axpy_residual_0400<<<cellBlocks, threads>>>(
                ws.phi.data(), ws.r.data(), ws.p.data(), ws.Ap.data(), alpha,
                grid.numCells);
            check_cuda_0400(cudaGetLastError(), "independent masked axpy launch");
            q6_reduce_square_sum_0400<<<cellBlocks, threads, scalarShared>>>(
                ws.r.data(), ws.partial0.data(), grid.numCells);
            check_cuda_0400(cudaGetLastError(), "independent masked rr launch");
            double rrNew = reduce_host_sum_0400(ws.partial0.data(), cellBlocks);
            audit.iterations = it + 1;
            audit.residualRel = std::sqrt(std::max(0.0, rrNew)) / rhsNormSafe;
            if (audit.residualRel <= tol) {
                rr = rrNew;
                audit.converged = true;
                break;
            }
            if (audit.fullDomain && (it + 1) % 25 == 0) {
                q6_reduce_sum_0400<<<cellBlocks, threads, scalarShared>>>(
                    ws.phi.data(), ws.partial0.data(), grid.numCells);
                q6_reduce_sum_0400<<<cellBlocks, threads, scalarShared>>>(
                    ws.r.data(), ws.partial1.data(), grid.numCells);
                check_cuda_0400(cudaGetLastError(),
                                "independent masked mean reduction launch");
                const double phiMean = reduce_host_sum_0400(ws.partial0.data(), cellBlocks) /
                                       static_cast<double>(grid.numCells);
                const double rMean = reduce_host_sum_0400(ws.partial1.data(), cellBlocks) /
                                     static_cast<double>(grid.numCells);
                q6_subtract_mean_pair_0400<<<cellBlocks, threads>>>(
                    ws.phi.data(), ws.r.data(), phiMean, rMean, grid.numCells);
                check_cuda_0400(cudaGetLastError(),
                                "independent masked mean subtract launch");
                q6_reduce_square_sum_0400<<<cellBlocks, threads, scalarShared>>>(
                    ws.r.data(), ws.partial0.data(), grid.numCells);
                check_cuda_0400(cudaGetLastError(),
                                "independent masked rr after mean launch");
                rrNew = reduce_host_sum_0400(ws.partial0.data(), cellBlocks);
            }
            const double beta = rrNew / std::max(rr, 1.0e-300);
            q6_update_p_0400<<<cellBlocks, threads>>>(
                ws.p.data(), ws.r.data(), beta, grid.numCells);
            check_cuda_0400(cudaGetLastError(), "independent masked p update launch");
            rr = rrNew;
        }

        allConverged = allConverged && audit.converged;
        maxIterations = std::max(maxIterations, audit.iterations);
        maxResidualRel = std::max(maxResidualRel, audit.residualRel);
        if (!audit.converged) {
            audits.push_back(audit);
            append_independent_masked_species_audit_0493w5(params, step, time, audits);
            diag.reason = "independent_masked species solve did not converge";
            return false;
        }

        const double effectiveStrength = params.q6ProjectionStrength * audit.strength;
        q6_compute_masked_face_correction_0493w5<<<cellBlocks, threads>>>(
            species, s, ws.phi.data(), ws.speciesMask0493w5.data(),
            ws.r.data(), ws.p.data(), grid.Nx, grid.Ny, dx, dy,
            effectiveStrength, periodicX, periodicY, xHighFlux, yHighFlux,
            segmentedIo, audit.type, exclusiveProjectedSpecies);
        check_cuda_0400(cudaGetLastError(), "independent masked face correction launch");
        q6_compute_masked_cell_correction_stats_0493w5<<<
            cellBlocks, threads, pairShared>>>(
            ws.speciesMask0493w5.data(), ws.r.data(), ws.p.data(),
            ws.dux.data(), ws.duy.data(), ws.partial0.data(), ws.partial1.data(),
            grid.Nx, grid.Ny, periodicX, periodicY,
            audit.fullDomain ? 1 : 0);
        check_cuda_0400(cudaGetLastError(), "independent masked cell correction launch");
        const double correctionSq = reduce_host_sum_0400(ws.partial0.data(), cellBlocks);
        audit.correctionMaxAbs = reduce_host_max_0400(ws.partial1.data(), cellBlocks);
        audit.correctionRms = std::sqrt(
            correctionSq / static_cast<double>(std::max<std::uint64_t>(1u, audit.activeCells)));

        q6_masked_projected_divergence_stats_0493w5<<<
            cellBlocks, threads, pairShared>>>(
            species, s, ws.speciesMask0493w5.data(), ws.r.data(), ws.p.data(),
            ws.partial0.data(), ws.partial1.data(), grid.Nx, grid.Ny, dx, dy,
            periodicX, periodicY, xLowFlux, xHighFlux, yLowFlux, yHighFlux,
            segmentedIo, audit.type, exclusiveProjectedSpecies,
            audit.fullDomain ? 1 : 0);
        check_cuda_0400(cudaGetLastError(),
                        "independent masked projected divergence launch");
        const double divAfterSq = reduce_host_sum_0400(ws.partial0.data(), cellBlocks);
        audit.divAfterProjectedFaceFluxMaxAbs =
            reduce_host_max_0400(ws.partial1.data(), cellBlocks);
        audit.divAfterProjectedFaceFluxRms = std::sqrt(
            divAfterSq / static_cast<double>(std::max<std::uint64_t>(1u, audit.activeCells)));
        // Preserve the 0493w5 column meaning while exposing an unambiguous name.
        audit.divAfterMaxAbs = audit.divAfterProjectedFaceFluxMaxAbs;
        audit.divAfterRms = audit.divAfterProjectedFaceFluxRms;

        double* denseDUx = ws.speciesDUx0493w5.data() +
            static_cast<std::size_t>(s) * static_cast<std::size_t>(grid.numCells);
        double* denseDUy = ws.speciesDUy0493w5.data() +
            static_cast<std::size_t>(s) * static_cast<std::size_t>(grid.numCells);
        check_cuda_0400(cudaMemcpy(denseDUx, ws.dux.data(),
                                   static_cast<std::size_t>(grid.numCells) * sizeof(double),
                                   cudaMemcpyDeviceToDevice),
                        "independent masked dux store");
        check_cuda_0400(cudaMemcpy(denseDUy, ws.duy.data(),
                                   static_cast<std::size_t>(grid.numCells) * sizeof(double),
                                   cudaMemcpyDeviceToDevice),
                        "independent masked duy store");

        totalDivBeforeSq += divBeforeSq;
        totalDivAfterSq += divAfterSq;
        totalCorrectionSq += correctionSq;
        totalActiveCells += audit.activeCells;
        maxDivBefore = std::max(maxDivBefore, audit.divBeforeMaxAbs);
        maxDivAfter = std::max(maxDivAfter, audit.divAfterProjectedFaceFluxMaxAbs);
        maxCorrection = std::max(maxCorrection, audit.correctionMaxAbs);
        ++diag.speciesQ6IndependentSolves;
        diag.speciesQ6IndependentActiveCells += audit.activeCells;
        audits.push_back(audit);
    }

    diag.solveSeconds = seconds_since_0400(tSolveAll);
    diag.converged = allConverged;
    diag.iterations = maxIterations;
    diag.residualRel = maxResidualRel;
    if (totalActiveCells > 0u) {
        const double denom = static_cast<double>(totalActiveCells);
        diag.divBeforeRms = std::sqrt(totalDivBeforeSq / denom);
        diag.divAfterProjectedFluxRms = std::sqrt(totalDivAfterSq / denom);
        diag.correctionVelocityRms = std::sqrt(totalCorrectionSq / denom);
    }
    diag.divBeforeMaxAbs = maxDivBefore;
    diag.divAfterProjectedFluxMaxAbs = maxDivAfter;
    diag.correctionVelocityMaxAbs = maxCorrection;

    const auto tApplyAll = Clock0400::now();
    double totalDpx = 0.0;
    double totalDpy = 0.0;
    for (IndependentMaskedSpeciesAudit0493w5& audit : audits) {
        if (!(audit.strength > 0.0) || audit.activeCells == 0u) continue;
        const int s = audit.speciesIndex;
        const double* denseDUx = ws.speciesDUx0493w5.data() +
            static_cast<std::size_t>(s) * static_cast<std::size_t>(grid.numCells);
        const double* denseDUy = ws.speciesDUy0493w5.data() +
            static_cast<std::size_t>(s) * static_cast<std::size_t>(grid.numCells);
        check_cuda_0400(cudaMemset(ws.counter.data(), 0, sizeof(unsigned long long)),
                        "independent masked corrected counter zero");
        q6_apply_independent_species_correction_0493w5<<<
            particleBlocks, threads, pairShared>>>(
            particles, cells, species, s, params.speciesQ6MinOccupancyFraction,
            denseDUx, denseDUy, audit.type, nParticles,
            ws.partial0.data(), ws.partial1.data(), ws.counter.data());
        check_cuda_0400(cudaGetLastError(), "independent masked particle apply launch");
        audit.momentumX = reduce_host_sum_0400(ws.partial0.data(), particleBlocks);
        audit.momentumY = reduce_host_sum_0400(ws.partial1.data(), particleBlocks);
        unsigned long long corrected = 0ull;
        check_cuda_0400(cudaMemcpy(&corrected, ws.counter.data(), sizeof(corrected),
                                   cudaMemcpyDeviceToHost),
                        "independent masked corrected counter download");
        audit.correctedParticles = static_cast<std::uint64_t>(corrected);
        diag.speciesQ6IndependentCorrectedParticles += audit.correctedParticles;
        totalDpx += audit.momentumX;
        totalDpy += audit.momentumY;
    }
    diag.speciesQ6ParticleApplySeconds = seconds_since_0400(tApplyAll);
    diag.applySeconds = diag.speciesQ6ParticleApplySeconds;
    diag.momentumResidualBeforeCorrection = std::sqrt(totalDpx * totalDpx + totalDpy * totalDpy);
    // A masked free-surface pressure solve may legitimately change the momentum
    // of the projected species through its Dirichlet interface.  Do not apply
    // the legacy all-particle uniform momentum correction, which would directly
    // modify species declared compressible.
    diag.momentumCorrectionVx = 0.0;
    diag.momentumCorrectionVy = 0.0;

    // 0493w6: rebuild each species mass and momentum directly from the corrected
    // resident particle state.  No particle or dense cell array is downloaded.
    // Only the already-established scalar block reductions cross to the host.
    const int speciesResetBlocks0493w6 = std::max(
        1, std::min(1024,
            (std::max(grid.numCells, grid.numCells * speciesCount) + threads - 1) / threads));
    q6_reset_species_mass_0491c<<<speciesResetBlocks0493w6, threads>>>(species);
    check_cuda_0400(cudaGetLastError(),
                    "independent masked post-apply species reset launch");
    q6_deposit_species_mass_from_cell_ids_0491c<<<particleBlocks, threads>>>(
        particles, cells, species, nParticles);
    check_cuda_0400(cudaGetLastError(),
                    "independent masked post-apply species deposit launch");
    q6_finalize_species_occupancy_0493w5<<<cellBlocks, threads>>>(species);
    check_cuda_0400(cudaGetLastError(),
                    "independent masked post-apply occupancy finalize launch");

    double totalAppliedCellDivSq0493w6 = 0.0;
    double maxAppliedCellDiv0493w6 = 0.0;
    std::uint64_t totalAppliedActiveCells0493w6 = 0u;
    for (IndependentMaskedSpeciesAudit0493w5& audit : audits) {
        if (!(audit.strength > 0.0) || audit.activeCells == 0u) continue;
        const unsigned char* denseMask0493w6 = ws.speciesMasks0493w6.data() +
            static_cast<std::size_t>(audit.speciesIndex) *
                static_cast<std::size_t>(grid.numCells);
        q6_build_independent_rhs_after_mask_0493w5<<<
            cellBlocks, threads, tripleShared>>>(
            species, audit.speciesIndex, denseMask0493w6, ws.rhs.data(),
            ws.partial0.data(), ws.partial1.data(), ws.partial2.data(),
            grid.Nx, grid.Ny, dx, dy, periodicX, periodicY,
            xLowFlux, xHighFlux, yLowFlux, yHighFlux, segmentedIo,
            audit.type, exclusiveProjectedSpecies, audit.fullDomain ? 1 : 0);
        check_cuda_0400(cudaGetLastError(),
                        "independent masked post-apply divergence launch");
        const double divAppliedSq0493w6 =
            reduce_host_sum_0400(ws.partial1.data(), cellBlocks);
        audit.divAfterAppliedCellVelocityMaxAbs =
            reduce_host_max_0400(ws.partial2.data(), cellBlocks);
        audit.divAfterAppliedCellVelocityRms = std::sqrt(
            divAppliedSq0493w6 /
            static_cast<double>(std::max<std::uint64_t>(1u, audit.activeCells)));
        totalAppliedCellDivSq0493w6 += divAppliedSq0493w6;
        totalAppliedActiveCells0493w6 += audit.activeCells;
        maxAppliedCellDiv0493w6 = std::max(
            maxAppliedCellDiv0493w6, audit.divAfterAppliedCellVelocityMaxAbs);
    }
    if (totalAppliedActiveCells0493w6 > 0u) {
        diag.divAfterCellVelocityRms = std::sqrt(
            totalAppliedCellDivSq0493w6 /
            static_cast<double>(totalAppliedActiveCells0493w6));
    }
    diag.divAfterCellVelocityMaxAbs = maxAppliedCellDiv0493w6;

    check_cuda_0400(cudaMemset(ws.counter.data(), 0, sizeof(unsigned long long)),
                    "independent masked cell refresh counter zero");
    q6_zero_cell_moments_only_0493w5<<<cellBlocks, threads>>>(cells);
    check_cuda_0400(cudaGetLastError(), "independent masked cell moments reset launch");
    q6_thermostat_deposit_moments_from_cell_ids_0400<<<particleBlocks, threads>>>(
        particles, cells, nParticles);
    check_cuda_0400(cudaGetLastError(), "independent masked cell moments redeposit launch");
    q6_finalize_cells_0400<<<cellBlocks, threads>>>(cells, ws.counter.data());
    check_cuda_0400(cudaGetLastError(), "independent masked cell moments finalize launch");

    append_independent_masked_species_audit_0493w5(params, step, time, audits);
    diag.speciesQ6IndependentMasked = true;
    diag.speciesQ6IndependentDisabledCorrectionMaxAbs = 0.0;
    diag.speciesQ6BarycentricResidualMaxAbs = 0.0;
    diag.speciesQ6BarycentricResidualMaxScaled = 0.0;
    return true;
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
    ws.ensure(nParticles, grid.numCells, blocks,
              params.speciesQ6Enable ? static_cast<int>(params.speciesDefinitions.size()) : 1);
    CudaCellWorkspaceDeviceView cells = ws.cells.device_view();
    CudaSpeciesCellDeviceView0490h species0491c{};
    const bool speciesQ6Weighted0491c =
        params.speciesQ6Enable && params.speciesQ6Mode == "weighted" &&
        params.speciesQ6Sensitivity > 0.0;
    const bool speciesQ6IndependentMasked0493w5 =
        params.speciesQ6Enable && params.speciesQ6Mode == "independent_masked";
    diag.speciesQ6IndependentMasked = speciesQ6IndependentMasked0493w5;
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
        std::vector<double> hReferenceCellMass0493w5(params.speciesDefinitions.size());
        for (std::size_t s = 0; s < params.speciesDefinitions.size(); ++s) {
            hSpeciesTypes0491c[s] = params.speciesDefinitions[s].type;
            hQ6Strength0491c[s] = params.speciesDefinitions[s].q6StrengthDeclared;
            hReferenceCellMass0493w5[s] =
                params.speciesDefinitions[s].referenceCellMassDeclared;
        }
        diag.speciesQ6MetadataH2DBytes =
            hSpeciesTypes0491c.size() * sizeof(std::uint32_t) +
            hQ6Strength0491c.size() * sizeof(double) +
            hReferenceCellMass0493w5.size() * sizeof(double);
        check_cuda_0400(cudaMemcpy(species0491c.speciesTypes, hSpeciesTypes0491c.data(),
                                   hSpeciesTypes0491c.size() * sizeof(std::uint32_t),
                                   cudaMemcpyHostToDevice),
                        "species q6 type metadata upload");
        check_cuda_0400(cudaMemcpy(species0491c.q6Strength, hQ6Strength0491c.data(),
                                   hQ6Strength0491c.size() * sizeof(double),
                                   cudaMemcpyHostToDevice),
                        "species q6 strength metadata upload");
        check_cuda_0400(cudaMemcpy(species0491c.referenceCellMass,
                                   hReferenceCellMass0493w5.data(),
                                   hReferenceCellMass0493w5.size() * sizeof(double),
                                   cudaMemcpyHostToDevice),
                        "species q6 reference cell mass metadata upload");
        const int denseSpecies0491c =
            grid.numCells * static_cast<int>(params.speciesDefinitions.size());
        const int speciesResetBlocks0491c =
            std::max(1, std::min(1024, (std::max(grid.numCells, denseSpecies0491c) + threads - 1) / threads));
        q6_reset_species_mass_0491c<<<speciesResetBlocks0491c, threads>>>(species0491c);
        check_cuda_0400(cudaGetLastError(), "species q6 mass reset launch");
        q6_deposit_species_mass_from_cell_ids_0491c<<<particleBlocks, threads>>>(
            particles, cells, species0491c, nParticles);
        check_cuda_0400(cudaGetLastError(), "species q6 mass deposit launch");
        q6_finalize_species_occupancy_0493w5<<<cellBlocks, threads>>>(species0491c);
        check_cuda_0400(cudaGetLastError(), "species q6 occupancy finalize launch");
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

    const std::size_t tripleShared = 3u * static_cast<std::size_t>(threads) * sizeof(double);
    if (speciesQ6IndependentMasked0493w5) {
        ws.warmPhiValid = false;
        const bool ok0493w5 = apply_independent_masked_species_q6_0493w5(
            particles, cells, species0491c, ws, params, grid, step, time,
            nParticles, threads, cellBlocks, particleBlocks,
            scalarShared, pairShared, tripleShared, periodicX, periodicY,
            xLowFlux, xHighFlux, yLowFlux, yHighFlux, segmentedIo0409, diag);
        if (!ok0493w5) {
            return diag;
        }
        cuda_shared_particle_state_0251_mark_fresh(
            "cuda_q6_resident_0400_independent_masked_0493w5");
        diag.applied = true;
        diag.handled = true;
        diag.reason = "ok";
        diag.totalSeconds = seconds_since_0400(tTotal);
        append_species_q6_resident_audit_0491e(
            params, step, time, static_cast<int>(params.speciesDefinitions.size()), diag);
        return diag;
    }

    const auto tSolve = Clock0400::now();
    const double dx = grid.dx;
    const double dy = grid.dy;
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
