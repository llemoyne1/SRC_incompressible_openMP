#include "cuda_classic_src_io_resident_0263.h"

#include "cuda_particle_state.h"
#include "cuda_shared_particle_state_0251.h"
#include "immersed_solid.h"
#include "open_boundary_segments.h"

#include <cuda_runtime.h>
#include <thrust/execution_policy.h>
#include <thrust/scan.h>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdlib>
#include <cstdint>
#include <cstdio>
#include <stdexcept>
#include <limits>
#include <string>
#include <vector>

namespace mpcd {
namespace {

inline void check_cuda_0263(cudaError_t err, const char* what) {
    if (err != cudaSuccess) {
        throw std::runtime_error(std::string("cuda_classic_src_io_resident_0263: ") + what + ": " + cudaGetErrorString(err));
    }
}

using Clock = std::chrono::steady_clock;
inline double elapsed_0263(const Clock::time_point& a, const Clock::time_point& b) {
    return std::chrono::duration<double>(b - a).count();
}

bool env_truthy_0263(const char* name) {
    const char* v = std::getenv(name);
    if (v == nullptr || *v == '\0') return false;
    const std::string s(v);
    return !(s == "0" || s == "false" || s == "FALSE" || s == "off" || s == "OFF" || s == "no" || s == "NO");
}

int env_int_0263(const char* name, int defaultValue) {
    const char* v = std::getenv(name);
    if (v == nullptr || *v == '\0') return defaultValue;
    try { return std::max(1, std::stoi(std::string(v))); }
    catch (...) { return defaultValue; }
}

// 0493x9d-fix1: conservative performance-only gate.  Unlike the first x9d
// attempt, fix1 deliberately keeps the exact host-visible candidate count so
// tail-pool sizing and insertion launch geometry remain identical to x9c.
bool neumann_resident_opt_0493x9d_fix1_enabled() {
    return env_truthy_0263(
        "MPCD_CUDA_OPEN_BOUNDARY_NEUMANN_RESIDENT_OPT_0493X9D_FIX1");
}

// 0493x9e: resident recycle optimization. Deleted fluid slots are recycled
// first for ghost/inlet insertion, then the compact inactive tail is used.
// x9e-fix3 restores the compact prefix with a targeted repair over the mutation
// support and keeps 0315c as the exact fallback for atypical steps.
bool neumann_recycle_pool_0493x9e_enabled() {
    return neumann_resident_opt_0493x9d_fix1_enabled() &&
           env_truthy_0263(
               "MPCD_CUDA_OPEN_BOUNDARY_NEUMANN_RECYCLE_POOL_0493X9E");
}

std::string normalized_inlet_reservoir_mode_0263(const SimulationParams& params) {
    std::string mode = params.inletReservoirMode;
    std::replace(mode.begin(), mode.end(), '-', '_');
    if (mode.empty() || mode == "default") {
        mode = params.inletInjectionMode;
        std::replace(mode.begin(), mode.end(), '-', '_');
    }
    if (mode == "cuda_recycle" || mode == "thin_slab") return "recycle";
    return mode;
}

bool hard_inlet_reservoir_enabled_0263(const SimulationParams& params) {
    const std::string mode = normalized_inlet_reservoir_mode_0263(params);
    return mode == "hard_cell_density" || mode == "hard_density" || mode == "hard" || mode == "cell_density";
}

int io_mode_code_0263(const std::string& mode) {
    if (is_inlet_boundary_mode(mode)) return 1;
    if (is_outlet_boundary_mode(mode)) return 2;
    return 0;
}

int wall_mode_code_0263(const std::string& mode) {
    if (mode == "solid" || mode == "specular") return 1;
    if (mode == "bounceback") return 2;
    return 0;
}

__host__ __device__ inline std::uint64_t face_tag_0263(const int face) {
    if (face == 0) return 0x4c454654ULL;
    if (face == 1) return 0x5249474854ULL;
    if (face == 2) return 0x424f54544f4dULL;
    if (face == 3) return 0x544f50ULL;
    return 0x46414345ULL;
}

struct CudaClassicSrcIoFullfaceConfig0263 {
    double Lx = 1.0;
    double Ly = 1.0;
    int Nx = 1;
    int Ny = 1;
    double dt = 0.0;
    double xMin = 0.0;
    double xMax = 1.0;
    double yMin = 0.0;
    double yMax = 1.0;
    int leftMode = 0;   // 0 none/wall, 1 inlet, 2 outlet
    int rightMode = 0;
    int bottomMode = 0;
    int topMode = 0;
    int leftWallMode = 0;
    int rightWallMode = 0;
    int bottomWallMode = 0; // 1 specular/solid, 2 bounceback
    int topWallMode = 0;
    double wallUxBottom = 0.0;
    double wallUyBottom = 0.0;
    double wallUxTop = 0.0;
    double wallUyTop = 0.0;
    double bodyAx = 0.0;
    double bodyAy = 0.0;
    int tgEnable = 0;
    double tgAmplitude = 0.0;
    int tgModeX = 1;
    int tgModeY = 1;
    int inletFace = 0; // 0 left, 1 right, 2 bottom, 3 top
    int inletReservoirCells = 1;
    int inletTargetOccupancy = 0;
    double inletUxLeft = 0.0;
    double inletUyLeft = 0.0;
    double inletUxRight = 0.0;
    double inletUyRight = 0.0;
    double inletUxBottom = 0.0;
    double inletUyBottom = 0.0;
    double inletUxTop = 0.0;
    double inletUyTop = 0.0;
    int rampEnable = 0;
    double rampT0 = 0.0;
    double rampT1 = 0.0;
    double rampInitial = 1.0;
    double rampFinal = 1.0;
    int rampSmoothstep = 0;
    int oscillationEnable = 0;
    double oscillationAmplitude = 0.0;
    double oscillationPeriod = 1.0;
    double oscillationPhase = 0.0;
    double oscillationStartTime = 0.0;
    double oscillationTimeOffset = 0.0;
    int profileCode = 0; // 0 uniform, 1 poiseuille_y_max, 2 poiseuille_y_mean, 3 flat_taper_y_mean
    double wallTaperCells = 0.0;
    double refMass = 1.0;
    std::uint32_t refType = 0u;
    double inletKBT = 0.0;
    double inletThermalNoise = 0.0;
    int inletHardCellVelocityMean = 0;
    int inletHardCellThermalRescale = 0;
    std::uint64_t rngSeed = 1u;
    std::uint64_t step = 0u;
    int immersedRectangleEnabled = 0;
    double immersedXMin = 0.0;
    double immersedXMax = 0.0;
    double immersedYMin = 0.0;
    double immersedYMax = 0.0;
    int immersedCircleEnabled = 0;
    double immersedCircleCx = 0.0;
    double immersedCircleCy = 0.0;
    double immersedCircleR = 0.0;
    int segmentedEnable = 0;
    int segmentedMultiAxis0414 = 0;
    int segmentCount = 0;
    int segmentFace[kOpenBoundaryMaxSegments]{};
    int segmentMode[kOpenBoundaryMaxSegments]{}; // 1 inlet, 2 outlet
    double segmentSMin[kOpenBoundaryMaxSegments]{};
    double segmentSMax[kOpenBoundaryMaxSegments]{};
    double segmentUx[kOpenBoundaryMaxSegments]{};
    double segmentUy[kOpenBoundaryMaxSegments]{};
    double segmentMass[kOpenBoundaryMaxSegments]{};
    std::uint32_t segmentType[kOpenBoundaryMaxSegments]{};
    int outletRegimeCode = 0; // 0 natural crossing, 1 equilibrium_flux, 2 forced_flux
    int outletNeumannKinetic0493x8q = 0; // kinetic Neumann continuation enabled
    int outletNeumannReplica0493x8v = 0; // microscopic mirror-replica continuation
    int outletNeumannReplicaSourceLayers0493x8v = 1; // local phase-trace proxy depth
    int outletNeumannVirtualCells0493x8w = 0; // independent virtual-cell continuation
    int outletNeumannVirtualLayers0493x8w = 2; // exterior cell layers sampled each step
    int outletNeumannVirtualReservoir0493x8x = 0; // coarse-grained virtual reservoir cells
    int outletNeumannReservoirLayers0493x8x = 2; // exterior layers populated statistically
    int outletNeumannReservoirCoarseLayers0493x8x = 8; // interior normal layers for macroscopic state
    int outletNeumannPressureReservoir0493x8y = 0; // pressure/reference-density virtual reservoir
    double outletNeumannReservoirTargetOccupancy0493x8y = 0.0; // mean total occupancy per exterior cell
    int outletNeumannNoBackflowReservoir0493x8z = 0; // clamp reservoir mean normal velocity to outward/nonnegative
    int outletNeumannZeroDriftOnBackflow0493x9a = 0; // when x8z clamps, also suppress tangential reservoir drift
    int outletNeumannLiquidStrictOutflow0493x9b = 0; // disable virtual reservoir candidates for selected liquid type
    int outletNeumannLiquidType0493x9b = -1; // particle type treated as strict-outflow liquid
    double outletForcedMassPerStep = 0.0;
    unsigned long long outletForcedParticlesPerStep = 0ULL;
    int outletForcedLayerCells = 1;
};

struct CudaClassicSrcIoCounters0263 {
    unsigned long long hitsLeft = 0ULL;
    unsigned long long hitsRight = 0ULL;
    unsigned long long hitsBottom = 0ULL;
    unsigned long long hitsTop = 0ULL;
    unsigned long long inletReservoirDeleted = 0ULL;
    unsigned long long inletBackflowDeleted = 0ULL;
    unsigned long long outletParticlesDeleted = 0ULL;
    unsigned long long outletParticlesInserted = 0ULL;
    unsigned long long inletParticlesInserted = 0ULL;
    unsigned long long inletReservoirCells = 0ULL;
    unsigned long long inletReservoirTargetParticles = 0ULL;
    unsigned long long fluidParticles = 0ULL;
    double inletMeanUxSum = 0.0;
    double inletMeanUySum = 0.0;
    double inletKbtNumerator = 0.0;
    int maxYReflections = 0;
    int failureFlag = 0;
    int overflowFlag = 0;
};

// 0493x9d-fix1: allocation-only optimization.  Boundary counters are cleared
// every boundary application but their storage size never changes, so retain a
// single process-persistent device object.  The legacy malloc/free path remains
// available when the fix1 gate is disabled.
CudaClassicSrcIoCounters0263* acquire_boundary_counters_0493x9d_fix1(
    const char* allocateLabel, const char* clearLabel)
{
    static CudaClassicSrcIoCounters0263* cached = nullptr;
    if (cached == nullptr) {
        check_cuda_0263(cudaMalloc(&cached, sizeof(CudaClassicSrcIoCounters0263)),
                        allocateLabel);
    }
    check_cuda_0263(cudaMemset(cached, 0, sizeof(CudaClassicSrcIoCounters0263)),
                    clearLabel);
    return cached;
}

// 0493x9e persistent recycle workspace.  deletedIndices records holes created
// inside the active prefix during the boundary pass.  poolIndices is rebuilt
// each step as [deleted holes first | compact inactive tail].  This preserves
// the physical candidate generation and insertion kernels while avoiding the
// role[] tail scan on the balanced fast path.
struct NeumannRecycleWorkspace0493x9e {
    std::uint64_t* deletedIndices = nullptr;
    unsigned int* deletedCount = nullptr;
    std::uint64_t deletedCapacity = 0u;
    std::uint64_t* poolIndices = nullptr;
    std::uint64_t poolCapacity = 0u;
    int* targetedRepairStatus0493x9eFix3 = nullptr;
};

NeumannRecycleWorkspace0493x9e& neumann_recycle_workspace_0493x9e() {
    static NeumannRecycleWorkspace0493x9e w{};
    return w;
}

NeumannRecycleWorkspace0493x9e& prepare_neumann_recycle_workspace_0493x9e(
    std::uint64_t activeCapacity)
{
    NeumannRecycleWorkspace0493x9e& w = neumann_recycle_workspace_0493x9e();
    if (w.deletedIndices == nullptr || w.deletedCapacity < activeCapacity) {
        if (w.deletedIndices != nullptr)
            check_cuda_0263(cudaFree(w.deletedIndices),
                            "resize 0493x9e deleted-slot buffer");
        if (activeCapacity > 0u) {
            check_cuda_0263(cudaMalloc(
                &w.deletedIndices,
                sizeof(std::uint64_t) * static_cast<std::size_t>(activeCapacity)),
                "allocate 0493x9e deleted-slot buffer");
        }
        w.deletedCapacity = activeCapacity;
    }
    if (w.deletedCount == nullptr)
        check_cuda_0263(cudaMalloc(&w.deletedCount, sizeof(unsigned int)),
                        "allocate 0493x9e deleted-slot count");
    if (w.targetedRepairStatus0493x9eFix3 == nullptr)
        check_cuda_0263(cudaMalloc(&w.targetedRepairStatus0493x9eFix3, sizeof(int)),
                        "allocate 0493x9e-fix3 targeted-repair status");
    check_cuda_0263(cudaMemset(w.deletedCount, 0, sizeof(unsigned int)),
                    "clear 0493x9e deleted-slot count");
    return w;
}

std::uint64_t* ensure_neumann_recycle_pool_0493x9e(std::uint64_t need) {
    NeumannRecycleWorkspace0493x9e& w = neumann_recycle_workspace_0493x9e();
    if (w.poolIndices == nullptr || w.poolCapacity < need) {
        if (w.poolIndices != nullptr)
            check_cuda_0263(cudaFree(w.poolIndices),
                            "resize 0493x9e recycle pool");
        if (need > 0u)
            check_cuda_0263(cudaMalloc(
                &w.poolIndices,
                sizeof(std::uint64_t) * static_cast<std::size_t>(need)),
                "allocate 0493x9e recycle pool");
        w.poolCapacity = need;
    }
    return w.poolIndices;
}

struct CudaForcedOutletBudget0291 {
    double targetMass = 0.0;
    double removedMass = 0.0;
    unsigned long long targetParticles = 0ULL;
    unsigned long long claimedParticles = 0ULL;
};

__device__ inline double clamp_device_0263(double x, double lo, double hi) {
    return fmin(fmax(x, lo), hi);
}

__device__ inline double clamp_strictly_inside_device_0263(double x, double lo, double hi) {
    const double width = hi - lo;
    const double eps = 1.0e-12 * fmax(1.0, fabs(width));
    return clamp_device_0263(x, lo + eps, hi - eps);
}

// 0414: the multi-axis chronological crossing resolver is declared before the
// historical wall-reflection definitions below, so keep explicit device
// prototypes here without moving the qualified mono-axis implementation.
__device__ inline void apply_y_wall_reflection_device_0263(int mode,
                                                           double wallUx,
                                                           double wallUy,
                                                           double& vx,
                                                           double& vy);
__device__ inline void apply_x_wall_reflection_device_0263(int mode,
                                                           double wallUx,
                                                           double wallUy,
                                                           double& vx,
                                                           double& vy);

__device__ inline std::uint64_t splitmix64_device_0263(std::uint64_t x) {
    x += 0x9e3779b97f4a7c15ULL;
    x = (x ^ (x >> 30U)) * 0xbf58476d1ce4e5b9ULL;
    x = (x ^ (x >> 27U)) * 0x94d049bb133111ebULL;
    return x ^ (x >> 31U);
}

struct Mt19937_64_Device_0263 {
    static constexpr int NN = 312;
    static constexpr int MM = 156;
    std::uint64_t mt[NN];
    int idx;
};

__device__ void mt_seed_device_0263(Mt19937_64_Device_0263& r, std::uint64_t seed) {
    r.mt[0] = seed;
    for (int i = 1; i < Mt19937_64_Device_0263::NN; ++i) {
        r.mt[i] = 6364136223846793005ULL * (r.mt[i - 1] ^ (r.mt[i - 1] >> 62U)) + static_cast<std::uint64_t>(i);
    }
    r.idx = Mt19937_64_Device_0263::NN;
}

__device__ void mt_twist_device_0263(Mt19937_64_Device_0263& r) {
    constexpr std::uint64_t MATRIX_A = 0xB5026F5AA96619E9ULL;
    constexpr std::uint64_t UM = 0xFFFFFFFF80000000ULL;
    constexpr std::uint64_t LM = 0x7FFFFFFFULL;
    for (int i = 0; i < Mt19937_64_Device_0263::NN; ++i) {
        const std::uint64_t x = (r.mt[i] & UM) | (r.mt[(i + 1) % Mt19937_64_Device_0263::NN] & LM);
        std::uint64_t xa = x >> 1U;
        if (x & 1ULL) xa ^= MATRIX_A;
        r.mt[i] = r.mt[(i + Mt19937_64_Device_0263::MM) % Mt19937_64_Device_0263::NN] ^ xa;
    }
    r.idx = 0;
}

__device__ std::uint64_t mt_next_device_0263(Mt19937_64_Device_0263& r) {
    if (r.idx >= Mt19937_64_Device_0263::NN) mt_twist_device_0263(r);
    std::uint64_t x = r.mt[r.idx++];
    x ^= (x >> 29U) & 0x5555555555555555ULL;
    x ^= (x << 17U) & 0x71D67FFFEDA60000ULL;
    x ^= (x << 37U) & 0xFFF7EEE000000000ULL;
    x ^= (x >> 43U);
    return x;
}

__device__ double uniform01_device_0263(Mt19937_64_Device_0263& r) {
    // libstdc++ uniform_real_distribution<double>(0,1) for mt19937_64 is
    // equivalent here to U / 2^64 followed by rounding to double. 2^64 is
    // exactly representable as a binary floating-point power of two.
    constexpr double denom = 18446744073709551616.0;
    double out = static_cast<double>(mt_next_device_0263(r)) / denom;
    if (out >= 1.0) out = nextafter(1.0, 0.0);
    return out;
}

struct NormalDeviceState0263 {
    double spare = 0.0;
    int hasSpare = 0;
};

__device__ double normal01_device_0263(Mt19937_64_Device_0263& r,
                                       NormalDeviceState0263& normal) {
    if (normal.hasSpare) {
        normal.hasSpare = 0;
        return normal.spare;
    }
    double x = 0.0;
    double y = 0.0;
    double r2 = 0.0;
    do {
        x = 2.0 * uniform01_device_0263(r) - 1.0;
        y = 2.0 * uniform01_device_0263(r) - 1.0;
        r2 = x * x + y * y;
    } while (r2 > 1.0 || r2 == 0.0);
    const double multiplier = sqrt(-2.0 * log(r2) / r2);
    normal.spare = x * multiplier;
    normal.hasSpare = 1;
    return y * multiplier;
}

struct InletThermalCell0263 {
    double meanFx = 0.0;
    double meanFy = 0.0;
    double scale = 1.0;
};

__device__ InletThermalCell0263 prepare_inlet_thermal_cell_0435d(
    const CudaClassicSrcIoFullfaceConfig0263& cfg,
    std::uint64_t seed,
    int particleCount,
    double particleMass)
{
    InletThermalCell0263 thermal{};
    if (particleCount <= 0 || !(cfg.inletThermalNoise > 0.0) ||
        !(cfg.inletKBT > 0.0) || !(particleMass > 0.0)) {
        return thermal;
    }
    const double sigma = cfg.inletThermalNoise * sqrt(cfg.inletKBT / particleMass);
    Mt19937_64_Device_0263 rng{};
    mt_seed_device_0263(rng, seed);
    NormalDeviceState0263 normal{};
    double sumFx = 0.0;
    double sumFy = 0.0;
    double sumSquares = 0.0;
    for (int k = 0; k < particleCount; ++k) {
        (void)uniform01_device_0263(rng);
        (void)uniform01_device_0263(rng);
        const double fx = sigma * normal01_device_0263(rng, normal);
        const double fy = sigma * normal01_device_0263(rng, normal);
        sumFx += fx;
        sumFy += fy;
        sumSquares += fx * fx + fy * fy;
    }
    if (cfg.inletHardCellVelocityMean) {
        thermal.meanFx = sumFx / static_cast<double>(particleCount);
        thermal.meanFy = sumFy / static_cast<double>(particleCount);
    }
    if (cfg.inletHardCellThermalRescale && particleCount > 1) {
        const double centeredSquares = sumSquares
            - 2.0 * thermal.meanFx * sumFx
            - 2.0 * thermal.meanFy * sumFy
            + static_cast<double>(particleCount) *
                (thermal.meanFx * thermal.meanFx + thermal.meanFy * thermal.meanFy);
        const double measured = particleMass * fmax(0.0, centeredSquares);
        const double desired = 2.0 * static_cast<double>(particleCount) * cfg.inletKBT;
        if (measured > 0.0 && desired > 0.0) thermal.scale = sqrt(desired / measured);
    }
    return thermal;
}

__device__ inline int imin_device_0263(int a, int b) { return a < b ? a : b; }
__device__ inline int imax_device_0263(int a, int b) { return a > b ? a : b; }

__device__ inline double segment_s_device_0263(int face, double x, double y, const CudaClassicSrcIoFullfaceConfig0263& cfg) {
    if (face == 0 || face == 1) {
        const double h = cfg.yMax - cfg.yMin;
        return h > 0.0 ? (y - cfg.yMin) / h : -1.0;
    }
    if (face == 2 || face == 3) {
        const double w = cfg.xMax - cfg.xMin;
        return w > 0.0 ? (x - cfg.xMin) / w : -1.0;
    }
    return -1.0;
}

__device__ inline int segment_mode_at_device_0263(const CudaClassicSrcIoFullfaceConfig0263& cfg, int face, double s) {
    if (!cfg.segmentedEnable) return 0;
    for (int k = 0; k < cfg.segmentCount; ++k) {
        if (cfg.segmentFace[k] == face && s >= cfg.segmentSMin[k] && s <= cfg.segmentSMax[k]) {
            return cfg.segmentMode[k];
        }
    }
    return 0;
}


__device__ inline void count_boundary_face_hit_0414(
    int face, CudaClassicSrcIoCounters0263& local) {
    if (face == 0) local.hitsLeft += 1ULL;
    else if (face == 1) local.hitsRight += 1ULL;
    else if (face == 2) local.hitsBottom += 1ULL;
    else if (face == 3) local.hitsTop += 1ULL;
}

__device__ inline void reflect_boundary_face_0414(
    int face,
    const CudaClassicSrcIoFullfaceConfig0263& cfg,
    double& vx,
    double& vy) {
    if (face == 0) {
        apply_x_wall_reflection_device_0263(
            cfg.leftWallMode == 0 ? 1 : cfg.leftWallMode, 0.0, 0.0, vx, vy);
    } else if (face == 1) {
        apply_x_wall_reflection_device_0263(
            cfg.rightWallMode == 0 ? 1 : cfg.rightWallMode, 0.0, 0.0, vx, vy);
    } else if (face == 2) {
        apply_y_wall_reflection_device_0263(
            cfg.bottomWallMode, cfg.wallUxBottom, cfg.wallUyBottom, vx, vy);
    } else if (face == 3) {
        apply_y_wall_reflection_device_0263(
            cfg.topWallMode, cfg.wallUxTop, cfg.wallUyTop, vx, vy);
    }
}

// 0414 multi-axis segmented crossing.  The historical resident path resolves
// x overshoots before y overshoots; with openings on both axes that ordering
// is not rotationally covariant.  For the new multi-axis subset only, trace
// the streamed straight segment from its reconstructed pre-stream position,
// process the earliest physical face intersection, reflect on a solid part,
// and continue for the remaining fraction of the same time step.
__device__ inline bool resolve_segmented_multi_axis_crossing_0414(
    double xPre,
    double yPre,
    double& xPost,
    double& yPost,
    double& vx,
    double& vy,
    const CudaClassicSrcIoFullfaceConfig0263& cfg,
    CudaClassicSrcIoCounters0263& local,
    int& removeMode,
    int& yReflections) {
    if (!cfg.segmentedEnable || !cfg.segmentedMultiAxis0414 || !(cfg.dt > 0.0)) {
        return false;
    }

    double cx = clamp_device_0263(xPre, cfg.xMin, cfg.xMax);
    double cy = clamp_device_0263(yPre, cfg.yMin, cfg.yMax);
    double remaining = cfg.dt;
    constexpr double inf = 1.0e300;
    constexpr double epsTime = 1.0e-12;
    constexpr int maxEvents = 128;

    for (int event = 0; event < maxEvents && remaining > 0.0; ++event) {
        double tx = inf;
        double ty = inf;
        int faceX = -1;
        int faceY = -1;
        if (vx < 0.0) {
            tx = (cfg.xMin - cx) / vx;
            faceX = 0;
        } else if (vx > 0.0) {
            tx = (cfg.xMax - cx) / vx;
            faceX = 1;
        }
        if (vy < 0.0) {
            ty = (cfg.yMin - cy) / vy;
            faceY = 2;
        } else if (vy > 0.0) {
            ty = (cfg.yMax - cy) / vy;
            faceY = 3;
        }
        if (tx < 0.0 && tx > -epsTime) tx = 0.0;
        if (ty < 0.0 && ty > -epsTime) ty = 0.0;
        if (tx < 0.0) tx = inf;
        if (ty < 0.0) ty = inf;

        const double tEvent = tx < ty ? tx : ty;
        const double tol = epsTime * fmax(1.0, remaining);
        if (!(tEvent <= remaining + tol) || tEvent >= inf * 0.5) {
            cx += vx * remaining;
            cy += vy * remaining;
            remaining = 0.0;
            break;
        }

        const bool hitX = fabs(tx - tEvent) <= tol;
        const bool hitY = fabs(ty - tEvent) <= tol;
        const double ex = cx + vx * tEvent;
        const double ey = cy + vy * tEvent;
        int modeX = 0;
        int modeY = 0;
        if (hitX) {
            count_boundary_face_hit_0414(faceX, local);
            modeX = segment_mode_at_device_0263(
                cfg, faceX, segment_s_device_0263(faceX, ex, ey, cfg));
        }
        if (hitY) {
            count_boundary_face_hit_0414(faceY, local);
            modeY = segment_mode_at_device_0263(
                cfg, faceY, segment_s_device_0263(faceY, ex, ey, cfg));
        }

        // A geometrically simultaneous open/open corner is consumed once.
        // Mixed inlet/outlet ownership is rejected by host validation; retain
        // a hard device guard in case a malformed configuration bypasses it.
        if (modeX != 0 || modeY != 0) {
            if (modeX != 0 && modeY != 0 && modeX != modeY) {
                local.failureFlag = 41;
                xPost = clamp_device_0263(ex, cfg.xMin, cfg.xMax);
                yPost = clamp_device_0263(ey, cfg.yMin, cfg.yMax);
                removeMode = 0;
                return true;
            }
            removeMode = modeX != 0 ? modeX : modeY;
            xPost = clamp_device_0263(ex, cfg.xMin, cfg.xMax);
            yPost = clamp_device_0263(ey, cfg.yMin, cfg.yMax);
            return true;
        }

        cx = clamp_device_0263(ex, cfg.xMin, cfg.xMax);
        cy = clamp_device_0263(ey, cfg.yMin, cfg.yMax);
        remaining = fmax(0.0, remaining - tEvent);
        if (hitX) reflect_boundary_face_0414(faceX, cfg, vx, vy);
        if (hitY) {
            reflect_boundary_face_0414(faceY, cfg, vx, vy);
            ++yReflections;
        }
    }

    if (remaining > 0.0) {
        local.failureFlag = 42;
    }
    xPost = clamp_device_0263(cx, cfg.xMin, cfg.xMax);
    yPost = clamp_device_0263(cy, cfg.yMin, cfg.yMax);
    return false;
}

__device__ inline int inlet_segment_index_for_cell_device_0263(const CudaClassicSrcIoFullfaceConfig0263& cfg, int face, double s) {
    if (!cfg.segmentedEnable) return -1;
    for (int k = 0; k < cfg.segmentCount; ++k) {
        if (cfg.segmentFace[k] == face && cfg.segmentMode[k] == 1 &&
            s >= cfg.segmentSMin[k] && s <= cfg.segmentSMax[k]) {
            return k;
        }
    }
    return -1;
}


__host__ __device__ inline double max2_device_0288(double a, double b) { return a > b ? a : b; }
__host__ __device__ inline double min2_device_0288(double a, double b) { return a < b ? a : b; }

__host__ __device__ inline bool interval_overlap_device_0288(double a0, double a1,
                                                              double b0, double b1,
                                                              double& lo,
                                                              double& hi) {
    lo = max2_device_0288(a0, b0);
    hi = min2_device_0288(a1, b1);
    return hi > lo;
}

__host__ __device__ inline int inlet_segment_index_for_cell_interval_core_0288(
    const CudaClassicSrcIoFullfaceConfig0263& cfg,
    int face,
    double s0,
    double s1)
{
    if (!cfg.segmentedEnable) return -1;
    if (s1 < s0) { const double tmp = s0; s0 = s1; s1 = tmp; }
    for (int k = 0; k < cfg.segmentCount; ++k) {
        if (cfg.segmentFace[k] != face || cfg.segmentMode[k] != 1) continue;
        double lo = 0.0, hi = 0.0;
        if (interval_overlap_device_0288(s0, s1, cfg.segmentSMin[k], cfg.segmentSMax[k], lo, hi)) {
            return k;
        }
    }
    return -1;
}

__device__ inline int inlet_segment_index_for_cell_interval_device_0288(
    const CudaClassicSrcIoFullfaceConfig0263& cfg,
    int face,
    double s0,
    double s1)
{
    return inlet_segment_index_for_cell_interval_core_0288(cfg, face, s0, s1);
}

__host__ inline int inlet_segment_index_for_cell_interval_host_0288(
    const CudaClassicSrcIoFullfaceConfig0263& cfg,
    int face,
    double s0,
    double s1)
{
    return inlet_segment_index_for_cell_interval_core_0288(cfg, face, s0, s1);
}

__host__ __device__ inline bool clip_reservoir_cell_to_segment_device_0288(
    const CudaClassicSrcIoFullfaceConfig0263& cfg,
    int inletFace,
    int segmentIndex,
    double& x0,
    double& x1,
    double& y0,
    double& y1,
    double& areaFraction)
{
    areaFraction = 1.0;
    if (segmentIndex < 0 || segmentIndex >= cfg.segmentCount) return true;
    if (cfg.segmentFace[segmentIndex] != inletFace || cfg.segmentMode[segmentIndex] != 1) return false;

    const double sMin = cfg.segmentSMin[segmentIndex];
    const double sMax = cfg.segmentSMax[segmentIndex];
    if (inletFace == 0 || inletFace == 1) {
        const double h = cfg.yMax - cfg.yMin;
        if (!(h > 0.0) || !(y1 > y0)) return false;
        const double segY0 = cfg.yMin + sMin * h;
        const double segY1 = cfg.yMin + sMax * h;
        double cy0 = 0.0, cy1 = 0.0;
        if (!interval_overlap_device_0288(y0, y1, segY0, segY1, cy0, cy1)) return false;
        areaFraction = (cy1 - cy0) / (y1 - y0);
        y0 = cy0; y1 = cy1;
        return areaFraction > 0.0;
    }
    if (inletFace == 2 || inletFace == 3) {
        const double w = cfg.xMax - cfg.xMin;
        if (!(w > 0.0) || !(x1 > x0)) return false;
        const double segX0 = cfg.xMin + sMin * w;
        const double segX1 = cfg.xMin + sMax * w;
        double cx0 = 0.0, cx1 = 0.0;
        if (!interval_overlap_device_0288(x0, x1, segX0, segX1, cx0, cx1)) return false;
        areaFraction = (cx1 - cx0) / (x1 - x0);
        x0 = cx0; x1 = cx1;
        return areaFraction > 0.0;
    }
    return true;
}

__host__ __device__ inline int scaled_partial_cell_target_0493w3(int targetN,
                                                                  double areaFraction) {
    if (targetN <= 0 || !(areaFraction > 0.0)) return 0;
    const double boundedFraction = min2_device_0288(1.0, max2_device_0288(0.0, areaFraction));
    const double scaled = static_cast<double>(targetN) * boundedFraction;
    return static_cast<int>(scaled + 0.5);
}

__device__ inline double smoothstep01_device_0263(double x) {
    x = clamp_device_0263(x, 0.0, 1.0);
    return x * x * (3.0 - 2.0 * x);
}

__device__ double ramp_factor_device_0263(const CudaClassicSrcIoFullfaceConfig0263& cfg, double time) {
    if (!cfg.rampEnable) return 1.0;
    if (!(cfg.rampT1 > cfg.rampT0)) return cfg.rampFinal;
    double a = 0.0;
    if (time <= cfg.rampT0) a = 0.0;
    else if (time >= cfg.rampT1) a = 1.0;
    else a = (time - cfg.rampT0) / (cfg.rampT1 - cfg.rampT0);
    if (cfg.rampSmoothstep) a = smoothstep01_device_0263(a);
    return (1.0 - a) * cfg.rampInitial + a * cfg.rampFinal;
}

__device__ double oscillation_factor_device_0493x14ba(
    const CudaClassicSrcIoFullfaceConfig0263& cfg, double time) {
    if (!cfg.oscillationEnable) return 1.0;
    const double effectiveTime = time + cfg.oscillationTimeOffset;
    if (effectiveTime < cfg.oscillationStartTime) return 1.0;
    const double twoPi = 6.283185307179586476925286766559;
    const double theta = twoPi * (effectiveTime - cfg.oscillationStartTime) /
                         cfg.oscillationPeriod + cfg.oscillationPhase;
    return 1.0 + cfg.oscillationAmplitude * sin(theta);
}

__device__ double inlet_time_factor_device_0493x14ba(
    const CudaClassicSrcIoFullfaceConfig0263& cfg, double time) {
    return ramp_factor_device_0263(cfg, time) *
           oscillation_factor_device_0493x14ba(cfg, time);
}

__device__ double flat_taper_y_base_device_0263(const CudaClassicSrcIoFullfaceConfig0263& cfg, double y) {
    if (!(cfg.wallTaperCells > 0.0)) return 1.0;
    const double h = cfg.yMax - cfg.yMin;
    if (!(h > 0.0)) return 1.0;
    const double dy = h / static_cast<double>(cfg.Ny > 0 ? cfg.Ny : 1);
    const double taperWidth = cfg.wallTaperCells * dy;
    if (!(taperWidth > 0.0)) return 1.0;
    const double dist = fmin(y - cfg.yMin, cfg.yMax - y);
    return smoothstep01_device_0263(dist / taperWidth);
}

__device__ double inlet_y_profile_factor_device_0263(const CudaClassicSrcIoFullfaceConfig0263& cfg, double y) {
    const double h = cfg.yMax - cfg.yMin;
    if (!(h > 0.0)) return 1.0;
    const double eta = clamp_device_0263((y - cfg.yMin) / h, 0.0, 1.0);
    const double shape = eta * (1.0 - eta);
    if (cfg.profileCode == 1) return 4.0 * shape;
    if (cfg.profileCode == 2) return 6.0 * shape;
    if (cfg.profileCode == 3) {
        const double base = flat_taper_y_base_device_0263(cfg, y);
        double meanBase = 0.0;
        const int ny = cfg.Ny > 0 ? cfg.Ny : 1;
        for (int j = 0; j < ny; ++j) {
            const double yc = cfg.yMin + (static_cast<double>(j) + 0.5) * h / static_cast<double>(ny);
            meanBase += flat_taper_y_base_device_0263(cfg, yc);
        }
        meanBase /= static_cast<double>(ny);
        return meanBase > 0.0 ? base / meanBase : base;
    }
    return 1.0;
}

// 0493x8k: segmented Poiseuille is local to the open segment.
// xi=0/1 are segment endpoints; xi=1/2 is the midpoint.
__device__ double segmented_inlet_profile_factor_device_0493x8k(
    const CudaClassicSrcIoFullfaceConfig0263& cfg,
    int segmentIndex,
    double x,
    double y) {
    if (segmentIndex < 0 || segmentIndex >= cfg.segmentCount) return 1.0;
    if (cfg.profileCode != 1 && cfg.profileCode != 2) return 1.0;

    const int face = cfg.segmentFace[segmentIndex];
    double s = 0.0;
    if (face == 0 || face == 1) {
        const double h = cfg.yMax - cfg.yMin;
        if (!(h > 0.0)) return 1.0;
        s = (y - cfg.yMin) / h;
    } else {
        const double w = cfg.xMax - cfg.xMin;
        if (!(w > 0.0)) return 1.0;
        s = (x - cfg.xMin) / w;
    }

    const double sMin = cfg.segmentSMin[segmentIndex];
    const double sMax = cfg.segmentSMax[segmentIndex];
    const double span = sMax - sMin;
    if (!(span > 0.0)) return 0.0;

    const double xi = clamp_device_0263((s - sMin) / span, 0.0, 1.0);
    const double shape = xi * (1.0 - xi);
    return cfg.profileCode == 1 ? 4.0 * shape : 6.0 * shape;
}

__device__ void segmented_inlet_velocity_device_0493x8k(
    const CudaClassicSrcIoFullfaceConfig0263& cfg,
    int segmentIndex,
    double x,
    double y,
    double time,
    double& ux,
    double& uy) {
    const double fRamp = inlet_time_factor_device_0493x14ba(cfg, time);
    ux = fRamp * cfg.segmentUx[segmentIndex];
    uy = fRamp * cfg.segmentUy[segmentIndex];

    // Preserve historical uniform segmented inlet exactly.
    if (cfg.profileCode != 1 && cfg.profileCode != 2) return;

    const double factor =
        segmented_inlet_profile_factor_device_0493x8k(cfg, segmentIndex, x, y);
    const int face = cfg.segmentFace[segmentIndex];
    if (face == 0 || face == 1) ux *= factor;
    else uy *= factor;
}

__device__ void inlet_velocity_device_0263(const CudaClassicSrcIoFullfaceConfig0263& cfg,
                                           int face,
                                           double x,
                                           double y,
                                           double time,
                                           double& ux,
                                           double& uy) {
    (void)x;
    if (face == 0) { ux = cfg.inletUxLeft; uy = cfg.inletUyLeft; }
    else if (face == 1) { ux = cfg.inletUxRight; uy = cfg.inletUyRight; }
    else if (face == 2) { ux = cfg.inletUxBottom; uy = cfg.inletUyBottom; }
    else if (face == 3) { ux = cfg.inletUxTop; uy = cfg.inletUyTop; }
    else { ux = 0.0; uy = 0.0; }
    const double fRamp = inlet_time_factor_device_0493x14ba(cfg, time);
    ux *= fRamp;
    uy *= fRamp;
    if (face == 0 || face == 1) {
        ux *= inlet_y_profile_factor_device_0263(cfg, y);
    }
}

__device__ inline void apply_y_wall_reflection_device_0263(int mode,
                                                           double wallUx,
                                                           double wallUy,
                                                           double& vx,
                                                           double& vy) {
    if (mode == 2) {
        vx = 2.0 * wallUx - vx;
        vy = 2.0 * wallUy - vy;
    } else {
        (void)wallUx;
        vy = 2.0 * wallUy - vy;
    }
}

__device__ inline void apply_x_wall_reflection_device_0263(int mode,
                                                           double wallUx,
                                                           double wallUy,
                                                           double& vx,
                                                           double& vy) {
    if (mode == 2) {
        vx = 2.0 * wallUx - vx;
        vy = 2.0 * wallUy - vy;
    } else {
        (void)wallUy;
        vx = 2.0 * wallUx - vx;
    }
}

__device__ bool point_in_inlet_reservoir_device_0263(double x, double y, const CudaClassicSrcIoFullfaceConfig0263& cfg) {
    const int cellsX = imax_device_0263(1, imin_device_0263(cfg.inletReservoirCells, cfg.Nx));
    const int cellsY = imax_device_0263(1, imin_device_0263(cfg.inletReservoirCells, cfg.Ny));
    const double dx = (cfg.xMax - cfg.xMin) / static_cast<double>(cfg.Nx > 0 ? cfg.Nx : 1);
    const double dy = (cfg.yMax - cfg.yMin) / static_cast<double>(cfg.Ny > 0 ? cfg.Ny : 1);
    if (cfg.segmentedEnable) {
        if (x >= cfg.xMin && x < cfg.xMin + static_cast<double>(cellsX) * dx) {
            const double s = segment_s_device_0263(0, x, y, cfg);
            if (segment_mode_at_device_0263(cfg, 0, s) == 1) return true;
        }
        if (x > cfg.xMax - static_cast<double>(cellsX) * dx && x <= cfg.xMax) {
            const double s = segment_s_device_0263(1, x, y, cfg);
            if (segment_mode_at_device_0263(cfg, 1, s) == 1) return true;
        }
        if (y >= cfg.yMin && y < cfg.yMin + static_cast<double>(cellsY) * dy) {
            const double s = segment_s_device_0263(2, x, y, cfg);
            if (segment_mode_at_device_0263(cfg, 2, s) == 1) return true;
        }
        if (y > cfg.yMax - static_cast<double>(cellsY) * dy && y <= cfg.yMax) {
            const double s = segment_s_device_0263(3, x, y, cfg);
            if (segment_mode_at_device_0263(cfg, 3, s) == 1) return true;
        }
        return false;
    }
    if (cfg.inletFace == 0) return x >= cfg.xMin && x < cfg.xMin + static_cast<double>(cellsX) * dx;
    if (cfg.inletFace == 1) return x > cfg.xMax - static_cast<double>(cellsX) * dx && x <= cfg.xMax;
    if (cfg.inletFace == 2) return y >= cfg.yMin && y < cfg.yMin + static_cast<double>(cellsY) * dy;
    if (cfg.inletFace == 3) return y > cfg.yMax - static_cast<double>(cellsY) * dy && y <= cfg.yMax;
    return false;
}



__device__ bool point_in_forced_outlet_layer_device_0291(double x, double y, const CudaClassicSrcIoFullfaceConfig0263& cfg) {
    const int nx = cfg.Nx > 0 ? cfg.Nx : 1;
    const int ny = cfg.Ny > 0 ? cfg.Ny : 1;
    const int layersX = imax_device_0263(1, imin_device_0263(cfg.outletForcedLayerCells, nx));
    const int layersY = imax_device_0263(1, imin_device_0263(cfg.outletForcedLayerCells, ny));
    const double dx = (cfg.xMax - cfg.xMin) / static_cast<double>(nx);
    const double dy = (cfg.yMax - cfg.yMin) / static_cast<double>(ny);

    if (cfg.segmentedEnable) {
        if (x >= cfg.xMin && x < cfg.xMin + static_cast<double>(layersX) * dx) {
            const double s = segment_s_device_0263(0, x, y, cfg);
            if (segment_mode_at_device_0263(cfg, 0, s) == 2) return true;
        }
        if (x > cfg.xMax - static_cast<double>(layersX) * dx && x <= cfg.xMax) {
            const double s = segment_s_device_0263(1, x, y, cfg);
            if (segment_mode_at_device_0263(cfg, 1, s) == 2) return true;
        }
        if (y >= cfg.yMin && y < cfg.yMin + static_cast<double>(layersY) * dy) {
            const double s = segment_s_device_0263(2, x, y, cfg);
            if (segment_mode_at_device_0263(cfg, 2, s) == 2) return true;
        }
        if (y > cfg.yMax - static_cast<double>(layersY) * dy && y <= cfg.yMax) {
            const double s = segment_s_device_0263(3, x, y, cfg);
            if (segment_mode_at_device_0263(cfg, 3, s) == 2) return true;
        }
        return false;
    }

    if (cfg.leftMode == 2 && x >= cfg.xMin && x < cfg.xMin + static_cast<double>(layersX) * dx) return true;
    if (cfg.rightMode == 2 && x > cfg.xMax - static_cast<double>(layersX) * dx && x <= cfg.xMax) return true;
    // Full-face 0263 currently validates x-pair inlet/outlet; keep y-face support
    // here for future extensions and for consistency with segmented outlets.
    if (cfg.bottomWallMode == 0 && y >= cfg.yMin && y < cfg.yMin + static_cast<double>(layersY) * dy) return true;
    if (cfg.topWallMode == 0 && y > cfg.yMax - static_cast<double>(layersY) * dy && y <= cfg.yMax) return true;
    return false;
}

__host__ __device__ bool reservoir_cell_center_inside_immersed_core_0285(double xc, double yc, const CudaClassicSrcIoFullfaceConfig0263& cfg) {
    if (cfg.immersedRectangleEnabled) {
        if (xc >= cfg.immersedXMin && xc <= cfg.immersedXMax &&
            yc >= cfg.immersedYMin && yc <= cfg.immersedYMax) {
            return true;
        }
    }
    if (cfg.immersedCircleEnabled) {
        const double dx = xc - cfg.immersedCircleCx;
        const double dy = yc - cfg.immersedCircleCy;
        return dx * dx + dy * dy <= cfg.immersedCircleR * cfg.immersedCircleR;
    }
    return false;
}

__device__ bool reservoir_cell_center_inside_immersed_device_0263(double xc, double yc, const CudaClassicSrcIoFullfaceConfig0263& cfg) {
    return reservoir_cell_center_inside_immersed_core_0285(xc, yc, cfg);
}

__global__ void io_fullface_force_stream_kernel_0263(
    std::uint64_t n,
    double* __restrict__ x,
    double* __restrict__ y,
    double* __restrict__ vx,
    double* __restrict__ vy,
    const unsigned char* __restrict__ role,
    unsigned char fluidRole,
    CudaClassicSrcIoFullfaceConfig0263 cfg)
{
    const std::uint64_t i = static_cast<std::uint64_t>(blockIdx.x) * static_cast<std::uint64_t>(blockDim.x) +
                            static_cast<std::uint64_t>(threadIdx.x);
    if (i >= n) return;
    if (role[i] != fluidRole) return;
    const double x0 = x[i];
    const double y0 = y[i];
    double ax = cfg.bodyAx;
    double ay = cfg.bodyAy;
    if (cfg.tgEnable && cfg.tgAmplitude > 0.0) {
        constexpr double pi = 3.141592653589793238462643383279502884;
        const double kx = 2.0 * pi * static_cast<double>(cfg.tgModeX) / cfg.Lx;
        const double ky = 2.0 * pi * static_cast<double>(cfg.tgModeY) / cfg.Ly;
        const double sx = sin(kx * x0);
        const double cx = cos(kx * x0);
        const double sy = sin(ky * y0);
        const double cy = cos(ky * y0);
        ax += cfg.tgAmplitude * sx * cy;
        ay += -cfg.tgAmplitude * cx * sy;
    }
    const double vx1 = vx[i] + ax * cfg.dt;
    const double vy1 = vy[i] + ay * cfg.dt;
    vx[i] = vx1;
    vy[i] = vy1;
    x[i] = x0 + vx1 * cfg.dt;
    y[i] = y0 + vy1 * cfg.dt;
}

__device__ void activate_reservoir_slot_device_0263(
    std::uint64_t n,
    double* __restrict__ x,
    double* __restrict__ y,
    double* __restrict__ vx,
    double* __restrict__ vy,
    double* __restrict__ mass,
    std::uint32_t* __restrict__ type,
    unsigned char* __restrict__ role,
    unsigned char fluidRole,
    unsigned char inactiveRole,
    const CudaClassicSrcIoFullfaceConfig0263& cfg,
    std::uint64_t& inactiveCursor,
    double xp,
    double yp,
    double vxp,
    double vyp,
    double particleMass,
    std::uint32_t particleType,
    CudaClassicSrcIoCounters0263& local)
{
    while (inactiveCursor < n && role[inactiveCursor] != inactiveRole) ++inactiveCursor;
    if (inactiveCursor >= n) {
        local.overflowFlag = 1;
        return;
    }
    x[inactiveCursor] = xp;
    y[inactiveCursor] = yp;
    vx[inactiveCursor] = vxp;
    vy[inactiveCursor] = vyp;
    mass[inactiveCursor] = particleMass;
    type[inactiveCursor] = particleType;
    role[inactiveCursor] = fluidRole;
    ++inactiveCursor;
    local.inletParticlesInserted += 1ULL;
    local.inletMeanUxSum += vxp;
    local.inletMeanUySum += vyp;
}

__device__ void insert_reservoir_cell_device_0263(
    std::uint64_t n,
    double* __restrict__ x,
    double* __restrict__ y,
    double* __restrict__ vx,
    double* __restrict__ vy,
    double* __restrict__ mass,
    std::uint32_t* __restrict__ type,
    unsigned char* __restrict__ role,
    unsigned char fluidRole,
    unsigned char inactiveRole,
    const CudaClassicSrcIoFullfaceConfig0263& cfg,
    int ix,
    int iy,
    double dx,
    double dy,
    int targetN,
    double time,
    int inletFace,
    int segmentIndex,
    std::uint64_t& inactiveCursor,
    std::uint64_t& ordinal,
    CudaClassicSrcIoCounters0263& local)
{
    if (targetN <= 0) return;
    double x0 = cfg.xMin + static_cast<double>(ix) * dx;
    double x1 = cfg.xMin + static_cast<double>(ix + 1) * dx;
    double y0 = cfg.yMin + static_cast<double>(iy) * dy;
    double y1 = cfg.yMin + static_cast<double>(iy + 1) * dy;
    double clippedX0 = x0, clippedX1 = x1, clippedY0 = y0, clippedY1 = y1;
    double clippedAreaFraction = 1.0;
    if (!clip_reservoir_cell_to_segment_device_0288(
            cfg, inletFace, segmentIndex,
            clippedX0, clippedX1, clippedY0, clippedY1, clippedAreaFraction)) return;
    const int effectiveTargetN = scaled_partial_cell_target_0493w3(targetN, clippedAreaFraction);
    if (effectiveTargetN <= 0) return;
    const double xc = 0.5 * (x0 + x1);
    const double yc = 0.5 * (y0 + y1);
    if (reservoir_cell_center_inside_immersed_device_0263(xc, yc, cfg)) return;
    local.inletReservoirCells += 1ULL;
    local.inletReservoirTargetParticles += static_cast<unsigned long long>(effectiveTargetN);
    const std::uint64_t seed = splitmix64_device_0263(cfg.rngSeed ^ (cfg.step * 0x9e3779b97f4a7c15ULL) ^
                                                      (ordinal * 0xbf58476d1ce4e5b9ULL) ^
                                                      face_tag_0263(inletFace));
    ++ordinal;
    double particleMass = cfg.refMass;
    if (segmentIndex >= 0 && segmentIndex < cfg.segmentCount) {
        particleMass = cfg.segmentMass[segmentIndex];
    }
    const InletThermalCell0263 thermal = prepare_inlet_thermal_cell_0435d(
        cfg, seed, effectiveTargetN, particleMass);
    const double sigma = (cfg.inletThermalNoise > 0.0 && cfg.inletKBT > 0.0 && particleMass > 0.0)
        ? cfg.inletThermalNoise * sqrt(cfg.inletKBT / particleMass) : 0.0;
    Mt19937_64_Device_0263 rng{};
    mt_seed_device_0263(rng, seed);
    NormalDeviceState0263 normal{};
    for (int k = 0; k < effectiveTargetN; ++k) {
        const double rx = uniform01_device_0263(rng);
        const double ry = uniform01_device_0263(rng);
        const double xp = clamp_strictly_inside_device_0263(
            clippedX0 + rx * (clippedX1 - clippedX0), clippedX0, clippedX1);
        const double yp = clamp_strictly_inside_device_0263(
            clippedY0 + ry * (clippedY1 - clippedY0), clippedY0, clippedY1);
        double ux = 0.0, uy = 0.0;
        std::uint32_t particleType = cfg.refType;
        if (segmentIndex >= 0 && segmentIndex < cfg.segmentCount) {
            segmented_inlet_velocity_device_0493x8k(
                cfg, segmentIndex, xp, yp, time, ux, uy);
            particleType = cfg.segmentType[segmentIndex];
        } else {
            inlet_velocity_device_0263(cfg, inletFace, xp, yp, time, ux, uy);
        }
        const double fx = sigma > 0.0 ? sigma * normal01_device_0263(rng, normal) : 0.0;
        const double fy = sigma > 0.0 ? sigma * normal01_device_0263(rng, normal) : 0.0;
        const double dvx = thermal.scale * (fx - thermal.meanFx);
        const double dvy = thermal.scale * (fy - thermal.meanFy);
        activate_reservoir_slot_device_0263(n, x, y, vx, vy, mass, type, role,
                                            fluidRole, inactiveRole, cfg, inactiveCursor,
                                            xp, yp, ux + dvx, uy + dvy, particleMass, particleType, local);
        local.inletKbtNumerator += particleMass * (dvx * dvx + dvy * dvy);
        if (local.overflowFlag) return;
    }
}

__global__ void io_fullface_hard_reservoir_kernel_0263(
    std::uint64_t n,
    double* __restrict__ x,
    double* __restrict__ y,
    double* __restrict__ vx,
    double* __restrict__ vy,
    double* __restrict__ mass,
    std::uint32_t* __restrict__ type,
    unsigned char* __restrict__ role,
    unsigned char fluidRole,
    unsigned char inactiveRole,
    CudaClassicSrcIoFullfaceConfig0263 cfg,
    CudaClassicSrcIoCounters0263* counters)
{
    if (blockIdx.x != 0 || threadIdx.x != 0) return;
    CudaClassicSrcIoCounters0263 local{};
    int maxY = 0;

    for (std::uint64_t i = 0; i < n; ++i) {
        if (role[i] != fluidRole) continue;
        if (!isfinite(x[i]) || !isfinite(y[i]) || !isfinite(vx[i]) || !isfinite(vy[i])) {
            local.failureFlag = 1;
            continue;
        }
        bool remove = false;
        int removeMode = 0;

        int guardX = 0;
        while (x[i] < cfg.xMin || x[i] > cfg.xMax) {
            if (++guardX > 64) { local.failureFlag = 3; break; }
            if (x[i] < cfg.xMin) {
                local.hitsLeft += 1ULL;
                int mode = cfg.leftMode;
                if (cfg.segmentedEnable) {
                    const double s = segment_s_device_0263(0, x[i], y[i], cfg);
                    mode = segment_mode_at_device_0263(cfg, 0, s);
                }
                if (mode != 0) { remove = true; removeMode = mode; break; }
                x[i] = 2.0 * cfg.xMin - x[i];
                apply_x_wall_reflection_device_0263(cfg.leftWallMode == 0 ? 1 : cfg.leftWallMode, 0.0, 0.0, vx[i], vy[i]);
            } else if (x[i] > cfg.xMax) {
                local.hitsRight += 1ULL;
                int mode = cfg.rightMode;
                if (cfg.segmentedEnable) {
                    const double s = segment_s_device_0263(1, x[i], y[i], cfg);
                    mode = segment_mode_at_device_0263(cfg, 1, s);
                }
                if (mode != 0) { remove = true; removeMode = mode; break; }
                x[i] = 2.0 * cfg.xMax - x[i];
                apply_x_wall_reflection_device_0263(cfg.rightWallMode == 0 ? 1 : cfg.rightWallMode, 0.0, 0.0, vx[i], vy[i]);
            }
        }

        if (!remove) {
            int guard = 0;
            while (y[i] < cfg.yMin || y[i] > cfg.yMax) {
                if (++guard > 64) { local.failureFlag = 2; break; }
                if (y[i] < cfg.yMin) {
                    local.hitsBottom += 1ULL;
                    int mode = cfg.bottomMode;
                    if (cfg.segmentedEnable) {
                        const double s = segment_s_device_0263(2, x[i], y[i], cfg);
                        mode = segment_mode_at_device_0263(cfg, 2, s);
                    }
                    if (mode != 0) { remove = true; removeMode = mode; break; }
                    y[i] = 2.0 * cfg.yMin - y[i];
                    apply_y_wall_reflection_device_0263(cfg.bottomWallMode, cfg.wallUxBottom, cfg.wallUyBottom, vx[i], vy[i]);
                } else if (y[i] > cfg.yMax) {
                    local.hitsTop += 1ULL;
                    int mode = cfg.topMode;
                    if (cfg.segmentedEnable) {
                        const double s = segment_s_device_0263(3, x[i], y[i], cfg);
                        mode = segment_mode_at_device_0263(cfg, 3, s);
                    }
                    if (mode != 0) { remove = true; removeMode = mode; break; }
                    y[i] = 2.0 * cfg.yMax - y[i];
                    apply_y_wall_reflection_device_0263(cfg.topWallMode, cfg.wallUxTop, cfg.wallUyTop, vx[i], vy[i]);
                }
            }
            if (guard > maxY) maxY = guard;
        }

        if (!remove && point_in_inlet_reservoir_device_0263(x[i], y[i], cfg)) {
            local.inletReservoirDeleted += 1ULL;
            remove = true;
        }

        if (remove) {
            x[i] = clamp_device_0263(x[i], cfg.xMin, cfg.xMax);
            y[i] = clamp_device_0263(y[i], cfg.yMin, cfg.yMax);
            role[i] = inactiveRole;
            if (removeMode == 1) local.inletBackflowDeleted += 1ULL;
            else if (removeMode == 2) local.outletParticlesDeleted += 1ULL;
        }
    }

    const int nx = cfg.Nx > 0 ? cfg.Nx : 1;
    const int ny = cfg.Ny > 0 ? cfg.Ny : 1;
    const int cellsX = imax_device_0263(1, imin_device_0263(cfg.inletReservoirCells, nx));
    const int cellsY = imax_device_0263(1, imin_device_0263(cfg.inletReservoirCells, ny));
    const double dx = (cfg.xMax - cfg.xMin) / static_cast<double>(nx);
    const double dy = (cfg.yMax - cfg.yMin) / static_cast<double>(ny);
    const int targetN = cfg.inletTargetOccupancy;
    std::uint64_t inactiveCursor = 0ULL;
    std::uint64_t ordinal = 0ULL;
    const double time = static_cast<double>(cfg.step) * cfg.dt;

    if (cfg.segmentedEnable) {
        for (int seg = 0; seg < cfg.segmentCount; ++seg) {
            if (cfg.segmentMode[seg] != 1) continue;
            const int face = cfg.segmentFace[seg];
            if (face == 0) {
                for (int ix = 0; ix < cellsX; ++ix) {
                    for (int iy = 0; iy < ny; ++iy) {
                        const double s = (static_cast<double>(iy) + 0.5) / static_cast<double>(ny);
                        if (inlet_segment_index_for_cell_device_0263(cfg, face, s) != seg) continue;
                        insert_reservoir_cell_device_0263(n, x, y, vx, vy, mass, type, role,
                                                          fluidRole, inactiveRole, cfg, ix, iy, dx, dy,
                                                          targetN, time, face, seg, inactiveCursor, ordinal, local);
                        if (local.overflowFlag) break;
                    }
                    if (local.overflowFlag) break;
                }
            } else if (face == 1) {
                for (int ix = nx - cellsX; ix < nx; ++ix) {
                    for (int iy = 0; iy < ny; ++iy) {
                        const double s = (static_cast<double>(iy) + 0.5) / static_cast<double>(ny);
                        if (inlet_segment_index_for_cell_device_0263(cfg, face, s) != seg) continue;
                        insert_reservoir_cell_device_0263(n, x, y, vx, vy, mass, type, role,
                                                          fluidRole, inactiveRole, cfg, ix, iy, dx, dy,
                                                          targetN, time, face, seg, inactiveCursor, ordinal, local);
                        if (local.overflowFlag) break;
                    }
                    if (local.overflowFlag) break;
                }
            } else if (face == 2) {
                for (int iy = 0; iy < cellsY; ++iy) {
                    for (int ix = 0; ix < nx; ++ix) {
                        const double s = (static_cast<double>(ix) + 0.5) / static_cast<double>(nx);
                        if (inlet_segment_index_for_cell_device_0263(cfg, face, s) != seg) continue;
                        insert_reservoir_cell_device_0263(n, x, y, vx, vy, mass, type, role,
                                                          fluidRole, inactiveRole, cfg, ix, iy, dx, dy,
                                                          targetN, time, face, seg, inactiveCursor, ordinal, local);
                        if (local.overflowFlag) break;
                    }
                    if (local.overflowFlag) break;
                }
            } else if (face == 3) {
                for (int iy = ny - cellsY; iy < ny; ++iy) {
                    for (int ix = 0; ix < nx; ++ix) {
                        const double s = (static_cast<double>(ix) + 0.5) / static_cast<double>(nx);
                        if (inlet_segment_index_for_cell_device_0263(cfg, face, s) != seg) continue;
                        insert_reservoir_cell_device_0263(n, x, y, vx, vy, mass, type, role,
                                                          fluidRole, inactiveRole, cfg, ix, iy, dx, dy,
                                                          targetN, time, face, seg, inactiveCursor, ordinal, local);
                        if (local.overflowFlag) break;
                    }
                    if (local.overflowFlag) break;
                }
            }
            if (local.overflowFlag) break;
        }
    } else if (cfg.inletFace == 0) {
        for (int ix = 0; ix < cellsX; ++ix) {
            for (int iy = 0; iy < ny; ++iy) {
                insert_reservoir_cell_device_0263(n, x, y, vx, vy, mass, type, role,
                                                  fluidRole, inactiveRole, cfg, ix, iy, dx, dy,
                                                  targetN, time, cfg.inletFace, -1, inactiveCursor, ordinal, local);
                if (local.overflowFlag) break;
            }
            if (local.overflowFlag) break;
        }
    } else if (cfg.inletFace == 1) {
        for (int ix = nx - cellsX; ix < nx; ++ix) {
            for (int iy = 0; iy < ny; ++iy) {
                insert_reservoir_cell_device_0263(n, x, y, vx, vy, mass, type, role,
                                                  fluidRole, inactiveRole, cfg, ix, iy, dx, dy,
                                                  targetN, time, cfg.inletFace, -1, inactiveCursor, ordinal, local);
                if (local.overflowFlag) break;
            }
            if (local.overflowFlag) break;
        }
    } else if (cfg.inletFace == 2) {
        for (int iy = 0; iy < cellsY; ++iy) {
            for (int ix = 0; ix < nx; ++ix) {
                insert_reservoir_cell_device_0263(n, x, y, vx, vy, mass, type, role,
                                                  fluidRole, inactiveRole, cfg, ix, iy, dx, dy,
                                                  targetN, time, cfg.inletFace, -1, inactiveCursor, ordinal, local);
                if (local.overflowFlag) break;
            }
            if (local.overflowFlag) break;
        }
    } else if (cfg.inletFace == 3) {
        for (int iy = ny - cellsY; iy < ny; ++iy) {
            for (int ix = 0; ix < nx; ++ix) {
                insert_reservoir_cell_device_0263(n, x, y, vx, vy, mass, type, role,
                                                  fluidRole, inactiveRole, cfg, ix, iy, dx, dy,
                                                  targetN, time, cfg.inletFace, -1, inactiveCursor, ordinal, local);
                if (local.overflowFlag) break;
            }
            if (local.overflowFlag) break;
        }
    }

    local.maxYReflections = maxY;
    for (std::uint64_t i = 0; i < n; ++i) {
        if (role[i] == fluidRole) local.fluidParticles += 1ULL;
    }
    *counters = local;
}

__device__ inline void add_counter_ull_0267(unsigned long long* dst, unsigned long long v) {
    if (v != 0ULL) atomicAdd(dst, v);
}

__device__ inline void merge_particle_boundary_counter_0267(CudaClassicSrcIoCounters0263* counters,
                                                             const CudaClassicSrcIoCounters0263& local) {
    add_counter_ull_0267(&counters->hitsLeft, local.hitsLeft);
    add_counter_ull_0267(&counters->hitsRight, local.hitsRight);
    add_counter_ull_0267(&counters->hitsBottom, local.hitsBottom);
    add_counter_ull_0267(&counters->hitsTop, local.hitsTop);
    add_counter_ull_0267(&counters->inletReservoirDeleted, local.inletReservoirDeleted);
    add_counter_ull_0267(&counters->inletBackflowDeleted, local.inletBackflowDeleted);
    add_counter_ull_0267(&counters->outletParticlesDeleted, local.outletParticlesDeleted);
    add_counter_ull_0267(&counters->fluidParticles, local.fluidParticles);
    if (local.failureFlag != 0) atomicMax(&counters->failureFlag, local.failureFlag);
    if (local.maxYReflections != 0) atomicMax(&counters->maxYReflections, local.maxYReflections);
}

__device__ inline void record_recycled_deleted_slot_0493x9e(
    std::uint64_t slot,
    std::uint64_t* deletedIndices,
    unsigned int* deletedCount,
    std::uint64_t deletedCapacity,
    CudaClassicSrcIoCounters0263* counters)
{
    if (deletedIndices == nullptr || deletedCount == nullptr) return;
    const unsigned int pos = atomicAdd(deletedCount, 1u);
    if (static_cast<std::uint64_t>(pos) < deletedCapacity) {
        deletedIndices[pos] = slot;
    } else if (counters != nullptr) {
        atomicMax(&counters->overflowFlag, 31);
    }
}

__global__ void io_forced_outlet_extraction_kernel_0291(
    std::uint64_t n,
    const double* __restrict__ x,
    const double* __restrict__ y,
    const double* __restrict__ mass,
    unsigned char* __restrict__ role,
    unsigned char fluidRole,
    unsigned char inactiveRole,
    CudaClassicSrcIoFullfaceConfig0263 cfg,
    CudaForcedOutletBudget0291* budget,
    CudaClassicSrcIoCounters0263* counters,
    std::uint64_t* recycleDeletedIndices0493x9e,
    unsigned int* recycleDeletedCount0493x9e,
    std::uint64_t recycleDeletedCapacity0493x9e)
{
    const std::uint64_t i = static_cast<std::uint64_t>(blockIdx.x) * static_cast<std::uint64_t>(blockDim.x) +
                            static_cast<std::uint64_t>(threadIdx.x);
    if (i >= n) return;
    if (role[i] != fluidRole) return;
    if (!point_in_forced_outlet_layer_device_0291(x[i], y[i], cfg)) return;

    bool remove = false;
    if (budget->targetParticles > 0ULL) {
        const unsigned long long old = atomicAdd(&budget->claimedParticles, 1ULL);
        remove = old < budget->targetParticles;
    } else if (budget->targetMass > 0.0) {
        const double m = isfinite(mass[i]) && mass[i] > 0.0 ? mass[i] : cfg.refMass;
        const double old = atomicAdd(&budget->removedMass, m);
        remove = old < budget->targetMass;
    }

    if (remove) {
        role[i] = inactiveRole;
        record_recycled_deleted_slot_0493x9e(
            i, recycleDeletedIndices0493x9e, recycleDeletedCount0493x9e,
            recycleDeletedCapacity0493x9e, counters);
        add_counter_ull_0267(&counters->outletParticlesDeleted, 1ULL);
    }
}


struct CudaNeumannGhostCandidate0493x8q {
    std::uint64_t source = 0ULL; // metadata source used when the bath count was built
    unsigned int bathCell = 0u;
    int face = -1;
    double particleMass = 1.0;
    std::uint32_t particleType = 0u;
};

__device__ inline int outlet_mode_at_particle_0493x8q(
    const CudaClassicSrcIoFullfaceConfig0263& cfg,
    int face,
    double xp,
    double yp)
{
    int mode = 0;
    if (face == 0) mode = cfg.leftMode;
    else if (face == 1) mode = cfg.rightMode;
    else if (face == 2) mode = cfg.bottomMode;
    else if (face == 3) mode = cfg.topMode;
    if (cfg.segmentedEnable) {
        const double s = segment_s_device_0263(face, xp, yp, cfg);
        mode = segment_mode_at_device_0263(cfg, face, s);
    }
    return mode;
}

// A surviving interior particle is a source for one exterior mirror particle
// iff the mirror crosses the outlet inward during this same dt.  This extends
// the local distribution f with zero normal gradient without fitting moments.

__device__ inline int neumann_ghost_face_for_survivor_0493x8q(
    const CudaClassicSrcIoFullfaceConfig0263& cfg,
    std::uint64_t particleIndex,
    double xp,
    double yp,
    double vxp,
    double vyp,
    unsigned int& outCopies)
{
    outCopies = 0u;
    if (!cfg.outletNeumannKinetic0493x8q || !(cfg.dt > 0.0)) return -1;

    const int nx = cfg.Nx > 0 ? cfg.Nx : 1;
    const int ny = cfg.Ny > 0 ? cfg.Ny : 1;
    const double dx = (cfg.xMax - cfg.xMin) / static_cast<double>(nx);
    const double dy = (cfg.yMax - cfg.yMin) / static_cast<double>(ny);
    const double wx = 2.0 * dx;
    const double wy = 2.0 * dy;

    const double xpre = xp - vxp * cfg.dt;
    const double ypre = yp - vyp * cfg.dt;

    double q = 0.0;
    int face = -1;
    std::uint64_t salt = 0ULL;

    if (vxp > 0.0 &&
        xpre >= cfg.xMin && xpre < cfg.xMin + wx &&
        outlet_mode_at_particle_0493x8q(cfg, 0, xpre, ypre) == 2) {
        q = vxp * cfg.dt / wx;
        face = 0;
        salt = 0x243f6a8885a308d3ULL;
    } else if (vxp < 0.0 &&
               xpre <= cfg.xMax && xpre > cfg.xMax - wx &&
               outlet_mode_at_particle_0493x8q(cfg, 1, xpre, ypre) == 2) {
        q = (-vxp) * cfg.dt / wx;
        face = 1;
        salt = 0x13198a2e03707344ULL;
    } else if (vyp > 0.0 &&
               ypre >= cfg.yMin && ypre < cfg.yMin + wy &&
               outlet_mode_at_particle_0493x8q(cfg, 2, xpre, ypre) == 2) {
        q = vyp * cfg.dt / wy;
        face = 2;
        salt = 0xa4093822299f31d0ULL;
    } else if (vyp < 0.0 &&
               ypre <= cfg.yMax && ypre > cfg.yMax - wy &&
               outlet_mode_at_particle_0493x8q(cfg, 3, xpre, ypre) == 2) {
        q = (-vyp) * cfg.dt / wy;
        face = 3;
        salt = 0x082efa98ec4e6c89ULL;
    } else {
        return -1;
    }

    if (!(q > 0.0) || !isfinite(q)) return -1;

    const double qFloor = floor(q);
    if (qFloor > static_cast<double>(0xffffffffu - 1u)) return -1;

    unsigned int copies = static_cast<unsigned int>(qFloor);
    const double frac = q - qFloor;

    const std::uint64_t key =
        cfg.rngSeed ^
        (cfg.step * 0x9e3779b97f4a7c15ULL) ^
        (particleIndex * 0xbf58476d1ce4e5b9ULL) ^
        face_tag_0263(face) ^ salt;
    const std::uint64_t z = splitmix64_device_0263(key);
    const double u = static_cast<double>(z >> 11) * 0x1.0p-53;
    if (u < frac) ++copies;

    outCopies = copies;
    return copies > 0u ? face : -1;
}



__device__ inline void record_neumann_ghost_candidate_0493x8q(
    std::uint64_t source,
    int face,
    unsigned int copies,
    CudaNeumannGhostCandidate0493x8q* candidates,
    unsigned int* candidateCount,
    unsigned int candidateCapacity,
    CudaClassicSrcIoCounters0263* counters)
{
    if (face < 0 || copies == 0u ||
        candidates == nullptr || candidateCount == nullptr) return;

    const unsigned int first = atomicAdd(candidateCount, copies);
    if (first > candidateCapacity || copies > candidateCapacity - first) {
        atomicMax(&counters->overflowFlag, 8);
        return;
    }

    for (unsigned int k = 0u; k < copies; ++k) {
        candidates[first + k].source = source;
        candidates[first + k].face = face;
    }
}




// -----------------------------------------------------------------------------
// 0493x8w -- virtual-cell kinetic Neumann continuation (physics-first).
//
// This path follows the finite-volume ghost-cell idea at the particle level.
// For every outlet boundary cell and registered species, the immediately
// adjacent physical cell provides the Neumann state (N, mean velocity, kBT,
// mean particle mass). One or more exterior virtual cells are populated with
// an INDEPENDENT statistical realization of that state. Virtual particles are
// streamed for dt; only those that cross the outlet into the physical domain
// are materialized in inactive resident slots. Virtual particles that remain
// outside are never resident particles and consume no inactive slot.
//
// This first implementation deliberately keeps the existing x8q host-side
// count synchronization and inactive-pool machinery. Performance optimization
// is deferred until the physical boundary contract is qualified.
struct CudaNeumannVirtualCellMoments0493x8w {
    unsigned int count = 0u;
    double sumMass = 0.0;
    double sumMomX = 0.0;
    double sumMomY = 0.0;
    double sumMvv = 0.0;
};

struct CudaNeumannVirtualCellCandidate0493x8w {
    double x = 0.0;
    double y = 0.0;
    double vx = 0.0;
    double vy = 0.0;
    double particleMass = 1.0;
    std::uint32_t particleType = 0u;
    int face = -1;
};

__host__ __device__ inline unsigned int neumann_virtual_spatial_count_0493x8w(
    const CudaClassicSrcIoFullfaceConfig0263& cfg)
{
    const unsigned int nx = static_cast<unsigned int>(cfg.Nx > 0 ? cfg.Nx : 1);
    const unsigned int ny = static_cast<unsigned int>(cfg.Ny > 0 ? cfg.Ny : 1);
    return 2u * (nx + ny);
}

__host__ __device__ inline unsigned int neumann_virtual_spatial_index_0493x8w(
    const CudaClassicSrcIoFullfaceConfig0263& cfg,
    int face,
    int tangentialCell)
{
    const unsigned int nx = static_cast<unsigned int>(cfg.Nx > 0 ? cfg.Nx : 1);
    const unsigned int ny = static_cast<unsigned int>(cfg.Ny > 0 ? cfg.Ny : 1);
    if (face == 0) return static_cast<unsigned int>(tangentialCell);
    if (face == 1) return ny + static_cast<unsigned int>(tangentialCell);
    if (face == 2) return 2u * ny + static_cast<unsigned int>(tangentialCell);
    return 2u * ny + nx + static_cast<unsigned int>(tangentialCell);
}

__host__ __device__ inline bool neumann_virtual_spatial_decode_0493x8w(
    const CudaClassicSrcIoFullfaceConfig0263& cfg,
    unsigned int spatialCell,
    int& face,
    int& tangentialCell)
{
    const unsigned int nx = static_cast<unsigned int>(cfg.Nx > 0 ? cfg.Nx : 1);
    const unsigned int ny = static_cast<unsigned int>(cfg.Ny > 0 ? cfg.Ny : 1);
    if (spatialCell < ny) {
        face = 0; tangentialCell = static_cast<int>(spatialCell); return true;
    }
    spatialCell -= ny;
    if (spatialCell < ny) {
        face = 1; tangentialCell = static_cast<int>(spatialCell); return true;
    }
    spatialCell -= ny;
    if (spatialCell < nx) {
        face = 2; tangentialCell = static_cast<int>(spatialCell); return true;
    }
    spatialCell -= nx;
    if (spatialCell < nx) {
        face = 3; tangentialCell = static_cast<int>(spatialCell); return true;
    }
    return false;
}

__device__ inline double uniform_from_u64_0493x8w(std::uint64_t z)
{
    return static_cast<double>(z >> 11) * 0x1.0p-53;
}

__device__ inline void accumulate_one_neumann_virtual_cell_0493x8w(
    int face,
    int tangentialCell,
    unsigned int speciesIndex,
    unsigned int speciesCount,
    double xp,
    double yp,
    double vxp,
    double vyp,
    double particleMass,
    const CudaClassicSrcIoFullfaceConfig0263& cfg,
    CudaNeumannVirtualCellMoments0493x8w* moments,
    unsigned int momentEntryCount)
{
    if (moments == nullptr || speciesCount == 0u || speciesIndex >= speciesCount)
        return;
    if (outlet_mode_at_particle_0493x8q(cfg, face, xp, yp) != 2) return;

    const unsigned int spatial =
        neumann_virtual_spatial_index_0493x8w(cfg, face, tangentialCell);
    const unsigned long long flat64 =
        static_cast<unsigned long long>(spatial) *
            static_cast<unsigned long long>(speciesCount) +
        static_cast<unsigned long long>(speciesIndex);
    if (flat64 >= static_cast<unsigned long long>(momentEntryCount)) return;

    CudaNeumannVirtualCellMoments0493x8w* b =
        moments + static_cast<unsigned int>(flat64);
    const double m = isfinite(particleMass) && particleMass > 0.0
        ? particleMass : cfg.refMass;
    atomicAdd(&b->count, 1u);
    atomicAdd(&b->sumMass, m);
    atomicAdd(&b->sumMomX, m * vxp);
    atomicAdd(&b->sumMomY, m * vyp);
    atomicAdd(&b->sumMvv, m * (vxp * vxp + vyp * vyp));
}

__global__ void io_neumann_virtual_cell_accumulate_kernel_0493x8w(
    std::uint64_t n,
    const double* __restrict__ x,
    const double* __restrict__ y,
    const double* __restrict__ vx,
    const double* __restrict__ vy,
    const double* __restrict__ mass,
    const std::uint32_t* __restrict__ type,
    const unsigned char* __restrict__ role,
    unsigned char fluidRole,
    CudaClassicSrcIoFullfaceConfig0263 cfg,
    const std::uint32_t* __restrict__ speciesTypes,
    unsigned int speciesCount,
    CudaNeumannVirtualCellMoments0493x8w* __restrict__ moments,
    unsigned int momentEntryCount)
{
    const std::uint64_t i =
        static_cast<std::uint64_t>(blockIdx.x) *
            static_cast<std::uint64_t>(blockDim.x) +
        static_cast<std::uint64_t>(threadIdx.x);
    if (i >= n || role[i] != fluidRole || speciesCount == 0u ||
        speciesTypes == nullptr || moments == nullptr) return;
    if (!isfinite(x[i]) || !isfinite(y[i]) ||
        !isfinite(vx[i]) || !isfinite(vy[i])) return;

    // The force/stream kernel has already advanced x,y. Recover the position at
    // the start of this streaming step so the copied cell is the physical cell
    // adjacent to the outlet before boundary deletion/reflection is applied.
    const double xpre = x[i] - vx[i] * cfg.dt;
    const double ypre = y[i] - vy[i] * cfg.dt;
    if (!(xpre >= cfg.xMin && xpre <= cfg.xMax &&
          ypre >= cfg.yMin && ypre <= cfg.yMax)) return;

    int speciesIndex = -1;
    for (unsigned int s = 0u; s < speciesCount; ++s) {
        if (speciesTypes[s] == type[i]) {
            speciesIndex = static_cast<int>(s);
            break;
        }
    }
    if (speciesIndex < 0) return;

    const int nx = cfg.Nx > 0 ? cfg.Nx : 1;
    const int ny = cfg.Ny > 0 ? cfg.Ny : 1;
    const double dx = (cfg.xMax - cfg.xMin) / static_cast<double>(nx);
    const double dy = (cfg.yMax - cfg.yMin) / static_cast<double>(ny);
    if (!(dx > 0.0) || !(dy > 0.0)) return;

    int ix = static_cast<int>(floor((xpre - cfg.xMin) / dx));
    int iy = static_cast<int>(floor((ypre - cfg.yMin) / dy));
    ix = imax_device_0263(0, imin_device_0263(nx - 1, ix));
    iy = imax_device_0263(0, imin_device_0263(ny - 1, iy));

    // A Neumann ghost cell copies ONLY the immediately adjacent physical cell.
    // Extra exterior layers duplicate that same boundary-cell state; they do not
    // widen the interior averaging stencil.
    if (xpre < cfg.xMin + dx) {
        accumulate_one_neumann_virtual_cell_0493x8w(
            0, iy, static_cast<unsigned int>(speciesIndex), speciesCount,
            xpre, ypre, vx[i], vy[i], mass[i], cfg, moments, momentEntryCount);
    }
    if (xpre >= cfg.xMax - dx) {
        accumulate_one_neumann_virtual_cell_0493x8w(
            1, iy, static_cast<unsigned int>(speciesIndex), speciesCount,
            xpre, ypre, vx[i], vy[i], mass[i], cfg, moments, momentEntryCount);
    }
    if (ypre < cfg.yMin + dy) {
        accumulate_one_neumann_virtual_cell_0493x8w(
            2, ix, static_cast<unsigned int>(speciesIndex), speciesCount,
            xpre, ypre, vx[i], vy[i], mass[i], cfg, moments, momentEntryCount);
    }
    if (ypre >= cfg.yMax - dy) {
        accumulate_one_neumann_virtual_cell_0493x8w(
            3, ix, static_cast<unsigned int>(speciesIndex), speciesCount,
            xpre, ypre, vx[i], vy[i], mass[i], cfg, moments, momentEntryCount);
    }
}

__device__ inline bool stream_virtual_particle_through_face_0493x8w(
    int face,
    double x0,
    double y0,
    double vxp,
    double vyp,
    const CudaClassicSrcIoFullfaceConfig0263& cfg,
    double& x1,
    double& y1)
{
    x1 = x0 + vxp * cfg.dt;
    y1 = y0 + vyp * cfg.dt;

    double tc = -1.0;
    if (face == 0) {
        if (!(vxp > 0.0 && x0 < cfg.xMin && x1 > cfg.xMin)) return false;
        tc = (cfg.xMin - x0) / vxp;
    } else if (face == 1) {
        if (!(vxp < 0.0 && x0 > cfg.xMax && x1 < cfg.xMax)) return false;
        tc = (cfg.xMax - x0) / vxp;
    } else if (face == 2) {
        if (!(vyp > 0.0 && y0 < cfg.yMin && y1 > cfg.yMin)) return false;
        tc = (cfg.yMin - y0) / vyp;
    } else if (face == 3) {
        if (!(vyp < 0.0 && y0 > cfg.yMax && y1 < cfg.yMax)) return false;
        tc = (cfg.yMax - y0) / vyp;
    } else {
        return false;
    }
    if (!(tc >= 0.0 && tc <= cfg.dt) || !isfinite(tc)) return false;

    const double xc = x0 + vxp * tc;
    const double yc = y0 + vyp * tc;
    if (!(xc >= cfg.xMin && xc <= cfg.xMax &&
          yc >= cfg.yMin && yc <= cfg.yMax)) return false;
    if (outlet_mode_at_particle_0493x8q(cfg, face, xc, yc) != 2) return false;

    // Physics-first restriction: a virtual particle is materialized only when
    // its streamed endpoint lies inside the physical domain. Very rare paths
    // crossing two boundaries within one dt are skipped rather than subjected
    // to a second virtual boundary solver.
    return x1 > cfg.xMin && x1 < cfg.xMax &&
           y1 > cfg.yMin && y1 < cfg.yMax &&
           isfinite(x1) && isfinite(y1);
}

__global__ void io_neumann_virtual_cell_candidates_kernel_0493x8w(
    CudaClassicSrcIoFullfaceConfig0263 cfg,
    const CudaNeumannVirtualCellMoments0493x8w* __restrict__ moments,
    unsigned int momentEntryCount,
    const std::uint32_t* __restrict__ speciesTypes,
    const double* __restrict__ speciesFallbackKBT,
    unsigned int speciesCount,
    CudaNeumannVirtualCellCandidate0493x8w* __restrict__ candidates,
    unsigned int* candidateCount,
    unsigned int candidateCapacity)
{
    const unsigned int entry = blockIdx.x * blockDim.x + threadIdx.x;
    if (entry >= momentEntryCount || speciesCount == 0u ||
        speciesTypes == nullptr || moments == nullptr || candidates == nullptr ||
        candidateCount == nullptr) return;

    const CudaNeumannVirtualCellMoments0493x8w b = moments[entry];
    const unsigned int N = b.count;
    if (N == 0u || !(b.sumMass > 0.0)) return;

    const unsigned int speciesIndex = entry % speciesCount;
    const unsigned int spatialCell = entry / speciesCount;
    int face = -1;
    int tangentialCell = -1;
    if (speciesIndex >= speciesCount ||
        !neumann_virtual_spatial_decode_0493x8w(cfg, spatialCell, face, tangentialCell))
        return;

    const double sumM = b.sumMass;
    const double ux = b.sumMomX / sumM;
    const double uy = b.sumMomY / sumM;
    const double rel =
        b.sumMvv - (b.sumMomX * b.sumMomX + b.sumMomY * b.sumMomY) / sumM;
    const double fallbackKBT = speciesFallbackKBT != nullptr
        ? speciesFallbackKBT[speciesIndex] : cfg.inletKBT;
    double kBTlocal = N >= 2u
        ? 0.5 * fmax(0.0, rel) / static_cast<double>(N)
        : fmax(0.0, fallbackKBT);
    if (!isfinite(kBTlocal) || !(kBTlocal > 0.0))
        kBTlocal = fmax(0.0, fallbackKBT);

    const double particleMass = sumM / static_cast<double>(N);
    if (!(particleMass > 0.0) || !isfinite(particleMass)) return;
    const double sigma = kBTlocal > 0.0 ? sqrt(kBTlocal / particleMass) : 0.0;

    const int nx = cfg.Nx > 0 ? cfg.Nx : 1;
    const int ny = cfg.Ny > 0 ? cfg.Ny : 1;
    const double dx = (cfg.xMax - cfg.xMin) / static_cast<double>(nx);
    const double dy = (cfg.yMax - cfg.yMin) / static_cast<double>(ny);
    if (!(dx > 0.0) || !(dy > 0.0) || !(cfg.dt > 0.0)) return;

    const unsigned int layers = static_cast<unsigned int>(
        cfg.outletNeumannVirtualLayers0493x8w > 0
            ? cfg.outletNeumannVirtualLayers0493x8w : 1);

    // Every exterior layer has the same macroscopic state as the adjacent
    // physical cell (zero normal gradient). Each layer contains N independent
    // virtual particles. Streaming decides the incoming half-space naturally.
    for (unsigned int layer = 0u; layer < layers; ++layer) {
        for (unsigned int k = 0u; k < N; ++k) {
            const std::uint64_t base =
                cfg.rngSeed ^
                (cfg.step * 0xd2b74407b1ce6e93ULL) ^
                (static_cast<std::uint64_t>(entry + 1u) * 0x9e3779b97f4a7c15ULL) ^
                (static_cast<std::uint64_t>(layer + 1u) * 0xbf58476d1ce4e5b9ULL) ^
                (static_cast<std::uint64_t>(k + 1u) * 0x94d049bb133111ebULL);
            const std::uint64_t z0 = splitmix64_device_0263(base);
            const std::uint64_t z1 = splitmix64_device_0263(z0 ^ 0x243f6a8885a308d3ULL);
            const std::uint64_t z2 = splitmix64_device_0263(z1 ^ 0x13198a2e03707344ULL);
            const std::uint64_t z3 = splitmix64_device_0263(z2 ^ 0xa4093822299f31d0ULL);

            const double rNormal = uniform_from_u64_0493x8w(z0);
            const double rTangential = uniform_from_u64_0493x8w(z1);
            const double rG1 = fmax(1.0e-15, uniform_from_u64_0493x8w(z2));
            const double rG2 = uniform_from_u64_0493x8w(z3);
            const double radius = sqrt(-2.0 * log(rG1));
            const double angle = 6.28318530717958647693 * rG2;
            const double g0 = radius * cos(angle);
            const double g1 = radius * sin(angle);
            const double vxp = ux + sigma * g0;
            const double vyp = uy + sigma * g1;

            double x0 = 0.5 * (cfg.xMin + cfg.xMax);
            double y0 = 0.5 * (cfg.yMin + cfg.yMax);
            if (face == 0 || face == 1) {
                y0 = cfg.yMin +
                    (static_cast<double>(tangentialCell) + rTangential) * dy;
                const double d = (static_cast<double>(layer) + rNormal) * dx;
                x0 = face == 0 ? cfg.xMin - d : cfg.xMax + d;
            } else {
                x0 = cfg.xMin +
                    (static_cast<double>(tangentialCell) + rTangential) * dx;
                const double d = (static_cast<double>(layer) + rNormal) * dy;
                y0 = face == 2 ? cfg.yMin - d : cfg.yMax + d;
            }

            double x1 = 0.0;
            double y1 = 0.0;
            if (!stream_virtual_particle_through_face_0493x8w(
                    face, x0, y0, vxp, vyp, cfg, x1, y1)) continue;

            const unsigned int j = atomicAdd(candidateCount, 1u);
            if (j >= candidateCapacity) continue;
            CudaNeumannVirtualCellCandidate0493x8w& c = candidates[j];
            c.x = x1;
            c.y = y1;
            c.vx = vxp;
            c.vy = vyp;
            c.particleMass = particleMass;
            c.particleType = speciesTypes[speciesIndex];
            c.face = face;
        }
    }
}

__global__ void io_neumann_virtual_cell_insert_kernel_0493x8w(
    std::uint64_t n,
    double* __restrict__ x,
    double* __restrict__ y,
    double* __restrict__ vx,
    double* __restrict__ vy,
    double* __restrict__ mass,
    std::uint32_t* __restrict__ type,
    unsigned char* __restrict__ role,
    unsigned char fluidRole,
    unsigned char inactiveRole,
    const CudaNeumannVirtualCellCandidate0493x8w* __restrict__ candidates,
    unsigned int candidateCount,
    const std::uint64_t* __restrict__ inactiveIndices,
    unsigned int inactiveCount,
    CudaClassicSrcIoCounters0263* counters)
{
    const unsigned int j = blockIdx.x * blockDim.x + threadIdx.x;
    if (j >= candidateCount) return;
    if (j >= inactiveCount) {
        atomicMax(&counters->overflowFlag, 14);
        return;
    }
    const CudaNeumannVirtualCellCandidate0493x8w c = candidates[j];
    if (!(c.particleMass > 0.0) || c.face < 0 || c.face > 3 ||
        !isfinite(c.x) || !isfinite(c.y) ||
        !isfinite(c.vx) || !isfinite(c.vy)) {
        atomicMax(&counters->failureFlag, 12);
        return;
    }
    const std::uint64_t slot = inactiveIndices[j];
    if (slot >= n || role[slot] != inactiveRole) {
        atomicMax(&counters->overflowFlag, 15);
        return;
    }

    x[slot] = c.x;
    y[slot] = c.y;
    vx[slot] = c.vx;
    vy[slot] = c.vy;
    mass[slot] = c.particleMass;
    type[slot] = c.particleType;
    role[slot] = fluidRole;
    add_counter_ull_0267(&counters->outletParticlesInserted, 1ULL);
    add_counter_ull_0267(&counters->fluidParticles, 1ULL);
}


// -----------------------------------------------------------------------------
// 0493x8x -- coarse-grained virtual-reservoir Neumann continuation.
//
// x8w showed that copying the instantaneous occupancy of the boundary-adjacent
// MPCD cell makes the external reservoir follow O(1/sqrt(gamma)) cell noise and
// can create a positive rarefaction feedback. x8x therefore separates:
//   (a) phase support at the outlet face, measured ONLY in the adjacent cell;
//   (b) macroscopic kinetic state, coarse-grained over several inward normal
//       layers at the same tangential location;
//   (c) an independent exterior realization, drawn anew each step.
//
// The expected total occupancy of an exterior cell is the coarse-grained total
// occupancy. Species composition is the face-cell number fraction. Hence
//     lambda_s = alpha_s^Gamma * Nbar_total_bulk.
// If the face cell is momentarily empty, alpha falls back to the coarse-grained
// species fraction instead of interpreting one empty MPCD sample as vacuum.
// Virtual occupancy is Poisson sampled, positions are uniform in each exterior
// cell, and velocities are independent Gaussian samples from the species-resolved
// coarse moments. Only streamed particles that actually cross an outlet become
// resident candidates; exterior particles otherwise remain virtual.
struct CudaNeumannVirtualReservoirMoments0493x8x {
    unsigned int faceCount = 0u;
    unsigned int bulkCount = 0u;
    double sumMass = 0.0;
    double sumMomX = 0.0;
    double sumMomY = 0.0;
    double sumMvv = 0.0;
};

__device__ inline unsigned int poisson_small_or_normal_0493x8x(
    double lambda,
    std::uint64_t seed)
{
    if (!(lambda > 0.0) || !isfinite(lambda)) return 0u;
    if (lambda < 30.0) {
        const double stop = exp(-lambda);
        double product = 1.0;
        unsigned int k = 0u;
        std::uint64_t state = seed;
        do {
            state = splitmix64_device_0263(state ^ 0x9e3779b97f4a7c15ULL);
            const double u = fmax(1.0e-15, uniform_from_u64_0493x8w(state));
            product *= u;
            ++k;
        } while (product > stop && k < 256u);
        return k > 0u ? k - 1u : 0u;
    }

    // Large lambda is not expected for the qualified gamma~O(10) cases, but a
    // Gaussian approximation avoids an unbounded Knuth loop in compressed cells.
    const std::uint64_t z0 = splitmix64_device_0263(seed ^ 0x243f6a8885a308d3ULL);
    const std::uint64_t z1 = splitmix64_device_0263(z0 ^ 0x13198a2e03707344ULL);
    const double u0 = fmax(1.0e-15, uniform_from_u64_0493x8w(z0));
    const double u1 = uniform_from_u64_0493x8w(z1);
    const double g = sqrt(-2.0 * log(u0)) * cos(6.28318530717958647693 * u1);
    const double sample = lambda + sqrt(lambda) * g;
    if (!(sample > 0.0) || !isfinite(sample)) return 0u;
    const double rounded = floor(sample + 0.5);
    if (rounded >= static_cast<double>(0xffffffffu)) return 0xffffffffu;
    return static_cast<unsigned int>(rounded);
}

__device__ inline void accumulate_one_neumann_virtual_reservoir_0493x8x(
    int face,
    int tangentialCell,
    bool faceLayer,
    unsigned int speciesIndex,
    unsigned int speciesCount,
    double xp,
    double yp,
    double vxp,
    double vyp,
    double particleMass,
    const CudaClassicSrcIoFullfaceConfig0263& cfg,
    CudaNeumannVirtualReservoirMoments0493x8x* moments,
    unsigned int momentEntryCount)
{
    if (moments == nullptr || speciesCount == 0u || speciesIndex >= speciesCount)
        return;
    if (outlet_mode_at_particle_0493x8q(cfg, face, xp, yp) != 2) return;

    const unsigned int spatial =
        neumann_virtual_spatial_index_0493x8w(cfg, face, tangentialCell);
    const unsigned long long flat64 =
        static_cast<unsigned long long>(spatial) *
            static_cast<unsigned long long>(speciesCount) +
        static_cast<unsigned long long>(speciesIndex);
    if (flat64 >= static_cast<unsigned long long>(momentEntryCount)) return;

    CudaNeumannVirtualReservoirMoments0493x8x* b =
        moments + static_cast<unsigned int>(flat64);
    const double m = isfinite(particleMass) && particleMass > 0.0
        ? particleMass : cfg.refMass;
    if (faceLayer) atomicAdd(&b->faceCount, 1u);
    atomicAdd(&b->bulkCount, 1u);
    atomicAdd(&b->sumMass, m);
    atomicAdd(&b->sumMomX, m * vxp);
    atomicAdd(&b->sumMomY, m * vyp);
    atomicAdd(&b->sumMvv, m * (vxp * vxp + vyp * vyp));
}

__global__ void io_neumann_virtual_reservoir_accumulate_kernel_0493x8x(
    std::uint64_t n,
    const double* __restrict__ x,
    const double* __restrict__ y,
    const double* __restrict__ vx,
    const double* __restrict__ vy,
    const double* __restrict__ mass,
    const std::uint32_t* __restrict__ type,
    const unsigned char* __restrict__ role,
    unsigned char fluidRole,
    CudaClassicSrcIoFullfaceConfig0263 cfg,
    const std::uint32_t* __restrict__ speciesTypes,
    unsigned int speciesCount,
    CudaNeumannVirtualReservoirMoments0493x8x* __restrict__ moments,
    unsigned int momentEntryCount)
{
    const std::uint64_t i =
        static_cast<std::uint64_t>(blockIdx.x) *
            static_cast<std::uint64_t>(blockDim.x) +
        static_cast<std::uint64_t>(threadIdx.x);
    if (i >= n || role[i] != fluidRole || speciesCount == 0u ||
        speciesTypes == nullptr || moments == nullptr) return;
    if (!isfinite(x[i]) || !isfinite(y[i]) ||
        !isfinite(vx[i]) || !isfinite(vy[i])) return;

    // Boundary kernels run after streaming. Recover the pre-stream position so
    // the reservoir state is based on physical cells before crossing deletion.
    const double xpre = x[i] - vx[i] * cfg.dt;
    const double ypre = y[i] - vy[i] * cfg.dt;
    if (!(xpre >= cfg.xMin && xpre <= cfg.xMax &&
          ypre >= cfg.yMin && ypre <= cfg.yMax)) return;

    int speciesIndex = -1;
    for (unsigned int s = 0u; s < speciesCount; ++s) {
        if (speciesTypes[s] == type[i]) {
            speciesIndex = static_cast<int>(s);
            break;
        }
    }
    if (speciesIndex < 0) return;

    const int nx = cfg.Nx > 0 ? cfg.Nx : 1;
    const int ny = cfg.Ny > 0 ? cfg.Ny : 1;
    const double dx = (cfg.xMax - cfg.xMin) / static_cast<double>(nx);
    const double dy = (cfg.yMax - cfg.yMin) / static_cast<double>(ny);
    if (!(dx > 0.0) || !(dy > 0.0)) return;

    int ix = static_cast<int>(floor((xpre - cfg.xMin) / dx));
    int iy = static_cast<int>(floor((ypre - cfg.yMin) / dy));
    ix = imax_device_0263(0, imin_device_0263(nx - 1, ix));
    iy = imax_device_0263(0, imin_device_0263(ny - 1, iy));

    const int requested = cfg.outletNeumannReservoirCoarseLayers0493x8x > 0
        ? cfg.outletNeumannReservoirCoarseLayers0493x8x : 1;
    const int kx = imin_device_0263(nx, requested);
    const int ky = imin_device_0263(ny, requested);

    const int leftLayer = ix;
    const int rightLayer = nx - 1 - ix;
    const int bottomLayer = iy;
    const int topLayer = ny - 1 - iy;

    if (leftLayer < kx) {
        accumulate_one_neumann_virtual_reservoir_0493x8x(
            0, iy, leftLayer == 0, static_cast<unsigned int>(speciesIndex),
            speciesCount, xpre, ypre, vx[i], vy[i], mass[i], cfg,
            moments, momentEntryCount);
    }
    if (rightLayer < kx) {
        accumulate_one_neumann_virtual_reservoir_0493x8x(
            1, iy, rightLayer == 0, static_cast<unsigned int>(speciesIndex),
            speciesCount, xpre, ypre, vx[i], vy[i], mass[i], cfg,
            moments, momentEntryCount);
    }
    if (bottomLayer < ky) {
        accumulate_one_neumann_virtual_reservoir_0493x8x(
            2, ix, bottomLayer == 0, static_cast<unsigned int>(speciesIndex),
            speciesCount, xpre, ypre, vx[i], vy[i], mass[i], cfg,
            moments, momentEntryCount);
    }
    if (topLayer < ky) {
        accumulate_one_neumann_virtual_reservoir_0493x8x(
            3, ix, topLayer == 0, static_cast<unsigned int>(speciesIndex),
            speciesCount, xpre, ypre, vx[i], vy[i], mass[i], cfg,
            moments, momentEntryCount);
    }
}

__global__ void io_neumann_virtual_reservoir_candidates_kernel_0493x8x(
    CudaClassicSrcIoFullfaceConfig0263 cfg,
    const CudaNeumannVirtualReservoirMoments0493x8x* __restrict__ moments,
    unsigned int momentEntryCount,
    const std::uint32_t* __restrict__ speciesTypes,
    const double* __restrict__ speciesFallbackKBT,
    unsigned int speciesCount,
    CudaNeumannVirtualCellCandidate0493x8w* __restrict__ candidates,
    unsigned int* candidateCount,
    unsigned int candidateCapacity)
{
    const unsigned int entry = blockIdx.x * blockDim.x + threadIdx.x;
    if (entry >= momentEntryCount || speciesCount == 0u ||
        speciesTypes == nullptr || moments == nullptr || candidates == nullptr ||
        candidateCount == nullptr) return;

    const unsigned int speciesIndex = entry % speciesCount;
    const unsigned int spatialCell = entry / speciesCount;
    int face = -1;
    int tangentialCell = -1;
    if (speciesIndex >= speciesCount ||
        !neumann_virtual_spatial_decode_0493x8w(
            cfg, spatialCell, face, tangentialCell)) return;

    // 0493x9b ablation: the selected liquid species is strict outflow on an
    // outlet. Physical liquid particles may leave and become inactive through
    // the existing streaming/deletion path, but the exterior virtual reservoir
    // never synthesizes liquid candidates entering the physical domain.
    if (cfg.outletNeumannLiquidStrictOutflow0493x9b != 0 &&
        cfg.outletNeumannLiquidType0493x9b >= 0 &&
        speciesTypes[speciesIndex] ==
            static_cast<std::uint32_t>(cfg.outletNeumannLiquidType0493x9b)) return;

    const unsigned int base = spatialCell * speciesCount;
    unsigned int faceTotal = 0u;
    unsigned int bulkTotal = 0u;
    for (unsigned int s = 0u; s < speciesCount; ++s) {
        const CudaNeumannVirtualReservoirMoments0493x8x q = moments[base + s];
        faceTotal += q.faceCount;
        bulkTotal += q.bulkCount;
    }
    if (bulkTotal == 0u) return;

    const CudaNeumannVirtualReservoirMoments0493x8x b = moments[entry];
    if (b.bulkCount == 0u || !(b.sumMass > 0.0)) return;

    const int nx = cfg.Nx > 0 ? cfg.Nx : 1;
    const int ny = cfg.Ny > 0 ? cfg.Ny : 1;
    const int requested = cfg.outletNeumannReservoirCoarseLayers0493x8x > 0
        ? cfg.outletNeumannReservoirCoarseLayers0493x8x : 1;
    const unsigned int coarseLayers = static_cast<unsigned int>(
        face == 0 || face == 1 ? imin_device_0263(nx, requested)
                               : imin_device_0263(ny, requested));
    if (coarseLayers == 0u) return;

    const double alpha = faceTotal > 0u
        ? static_cast<double>(b.faceCount) / static_cast<double>(faceTotal)
        : static_cast<double>(b.bulkCount) / static_cast<double>(bulkTotal);
    if (!(alpha > 0.0) || !isfinite(alpha)) return;

    // x8x density uses the inward coarse stencil. x8y keeps exactly the same
    // phase support and kinetic moments but decouples the exterior pressure
    // reservoir density from an outlet rarefaction: its expected total
    // occupancy is prescribed by the qualified reference occupancy.
    const double meanTotalOccupancy =
        static_cast<double>(bulkTotal) / static_cast<double>(coarseLayers);
    const double reservoirTotalOccupancy =
        (cfg.outletNeumannPressureReservoir0493x8y != 0 &&
         cfg.outletNeumannReservoirTargetOccupancy0493x8y > 0.0)
            ? cfg.outletNeumannReservoirTargetOccupancy0493x8y
            : meanTotalOccupancy;
    const double lambdaSpecies = alpha * reservoirTotalOccupancy;
    if (!(lambdaSpecies > 0.0) || !isfinite(lambdaSpecies)) return;

    const double sumM = b.sumMass;
    const unsigned int Nbulk = b.bulkCount;
    const double uxInterior = b.sumMomX / sumM;
    const double uyInterior = b.sumMomY / sumM;

    // 0493x8z: an outlet reservoir may preserve thermal inward crossings, but
    // its MACROSCOPIC mean velocity must never point into the physical domain.
    // x8z clamps only the normal mean component. 0493x9a is a stricter guard:
    // if the interior coarse mean is in macroscopic backflow, suppress the
    // complete reservoir drift vector for that face. The thermal variance is
    // still inherited unchanged, so microscopic thermal inward crossings remain.
    double uxReservoir = uxInterior;
    double uyReservoir = uyInterior;
    if (cfg.outletNeumannNoBackflowReservoir0493x8z != 0) {
        bool macroscopicBackflow = false;
        if (face == 0) macroscopicBackflow = uxInterior > 0.0;       // left: outward is -x
        else if (face == 1) macroscopicBackflow = uxInterior < 0.0;  // right: outward is +x
        else if (face == 2) macroscopicBackflow = uyInterior > 0.0;  // bottom: outward is -y
        else if (face == 3) macroscopicBackflow = uyInterior < 0.0;  // top: outward is +y

        if (cfg.outletNeumannZeroDriftOnBackflow0493x9a != 0 && macroscopicBackflow) {
            uxReservoir = 0.0;
            uyReservoir = 0.0;
        } else {
            if (face == 0) uxReservoir = fmin(uxReservoir, 0.0);
            else if (face == 1) uxReservoir = fmax(uxReservoir, 0.0);
            else if (face == 2) uyReservoir = fmin(uyReservoir, 0.0);
            else if (face == 3) uyReservoir = fmax(uyReservoir, 0.0);
        }
    }

    const double rel =
        b.sumMvv - (b.sumMomX * b.sumMomX + b.sumMomY * b.sumMomY) / sumM;
    const double fallbackKBT = speciesFallbackKBT != nullptr
        ? speciesFallbackKBT[speciesIndex] : cfg.inletKBT;
    double kBTlocal = Nbulk >= 4u
        ? 0.5 * fmax(0.0, rel) / static_cast<double>(Nbulk)
        : fmax(0.0, fallbackKBT);
    if (!isfinite(kBTlocal) || !(kBTlocal > 0.0))
        kBTlocal = fmax(0.0, fallbackKBT);

    const double particleMass = sumM / static_cast<double>(Nbulk);
    if (!(particleMass > 0.0) || !isfinite(particleMass)) return;
    const double sigma = kBTlocal > 0.0 ? sqrt(kBTlocal / particleMass) : 0.0;

    const double dx = (cfg.xMax - cfg.xMin) / static_cast<double>(nx);
    const double dy = (cfg.yMax - cfg.yMin) / static_cast<double>(ny);
    if (!(dx > 0.0) || !(dy > 0.0) || !(cfg.dt > 0.0)) return;

    const unsigned int layers = static_cast<unsigned int>(
        cfg.outletNeumannReservoirLayers0493x8x > 0
            ? cfg.outletNeumannReservoirLayers0493x8x : 1);

    for (unsigned int layer = 0u; layer < layers; ++layer) {
        const std::uint64_t populationSeed =
            cfg.rngSeed ^
            (cfg.step * 0x6a09e667f3bcc909ULL) ^
            (static_cast<std::uint64_t>(entry + 1u) * 0xbb67ae8584caa73bULL) ^
            (static_cast<std::uint64_t>(layer + 1u) * 0x3c6ef372fe94f82bULL);
        const unsigned int Nvirtual =
            poisson_small_or_normal_0493x8x(lambdaSpecies, populationSeed);

        for (unsigned int k = 0u; k < Nvirtual; ++k) {
            const std::uint64_t baseSeed =
                populationSeed ^
                (static_cast<std::uint64_t>(k + 1u) * 0xa54ff53a5f1d36f1ULL);
            const std::uint64_t z0 = splitmix64_device_0263(baseSeed);
            const std::uint64_t z1 = splitmix64_device_0263(z0 ^ 0x510e527fade682d1ULL);
            const std::uint64_t z2 = splitmix64_device_0263(z1 ^ 0x9b05688c2b3e6c1fULL);
            const std::uint64_t z3 = splitmix64_device_0263(z2 ^ 0x1f83d9abfb41bd6bULL);

            const double rNormal = uniform_from_u64_0493x8w(z0);
            const double rTangential = uniform_from_u64_0493x8w(z1);
            const double rG1 = fmax(1.0e-15, uniform_from_u64_0493x8w(z2));
            const double rG2 = uniform_from_u64_0493x8w(z3);
            const double radius = sqrt(-2.0 * log(rG1));
            const double angle = 6.28318530717958647693 * rG2;
            const double g0 = radius * cos(angle);
            const double g1 = radius * sin(angle);
            const double vxp = uxReservoir + sigma * g0;
            const double vyp = uyReservoir + sigma * g1;

            double x0 = 0.5 * (cfg.xMin + cfg.xMax);
            double y0 = 0.5 * (cfg.yMin + cfg.yMax);
            if (face == 0 || face == 1) {
                y0 = cfg.yMin +
                    (static_cast<double>(tangentialCell) + rTangential) * dy;
                const double d = (static_cast<double>(layer) + rNormal) * dx;
                x0 = face == 0 ? cfg.xMin - d : cfg.xMax + d;
            } else {
                x0 = cfg.xMin +
                    (static_cast<double>(tangentialCell) + rTangential) * dx;
                const double d = (static_cast<double>(layer) + rNormal) * dy;
                y0 = face == 2 ? cfg.yMin - d : cfg.yMax + d;
            }

            double x1 = 0.0;
            double y1 = 0.0;
            if (!stream_virtual_particle_through_face_0493x8w(
                    face, x0, y0, vxp, vyp, cfg, x1, y1)) continue;

            const unsigned int j = atomicAdd(candidateCount, 1u);
            if (j >= candidateCapacity) continue;
            CudaNeumannVirtualCellCandidate0493x8w& c = candidates[j];
            c.x = x1;
            c.y = y1;
            c.vx = vxp;
            c.vy = vyp;
            c.particleMass = particleMass;
            c.particleType = speciesTypes[speciesIndex];
            c.face = face;
        }
    }
}


// 0493x8v -- microscopic Neumann replica.
//
// Unlike x8q/x8r, this path does not fit bath moments and does not synthesize
// a Maxwellian.  A real, surviving interior particle is extended across an
// outlet by mirror symmetry at its PRE-stream position.  A ghost is materialized
// only if that virtual exterior copy streams back through the same outlet during
// this dt.  Type, mass and velocity are therefore inherited from one labelled
// microscopic source.  Restricting sources to the boundary-adjacent cell
// (default one layer) is the phase-support/trace proxy: a phase deeper in the
// domain cannot seed the outlet merely because it was present in a two-cell bath.
struct CudaNeumannReplicaCandidate0493x8v {
    std::uint64_t source = 0ULL;
    double x = 0.0;
    double y = 0.0;
    double vx = 0.0;
    double vy = 0.0;
    int face = -1;
};

__device__ inline void record_one_neumann_replica_0493x8v(
    std::uint64_t source,
    int face,
    double xpre,
    double ypre,
    double vxp,
    double vyp,
    const CudaClassicSrcIoFullfaceConfig0263& cfg,
    CudaNeumannReplicaCandidate0493x8v* candidates,
    unsigned int* candidateCount,
    unsigned int candidateCapacity,
    CudaClassicSrcIoCounters0263* counters)
{
    if (!cfg.outletNeumannReplica0493x8v || face < 0 || face > 3 ||
        candidates == nullptr || candidateCount == nullptr ||
        !(cfg.dt > 0.0)) return;

    const int nx = cfg.Nx > 0 ? cfg.Nx : 1;
    const int ny = cfg.Ny > 0 ? cfg.Ny : 1;
    const double dx = (cfg.xMax - cfg.xMin) / static_cast<double>(nx);
    const double dy = (cfg.yMax - cfg.yMin) / static_cast<double>(ny);
    if (!(dx > 0.0) || !(dy > 0.0)) return;
    const double sourceLayers = static_cast<double>(
        cfg.outletNeumannReplicaSourceLayers0493x8v > 0
            ? cfg.outletNeumannReplicaSourceLayers0493x8v : 1);

    double distance = 0.0;
    double inwardSpeed = 0.0;
    double normalCell = dx;
    double xCross = xpre;
    double yCross = ypre;
    double xGhost = xpre;
    double yGhost = ypre;

    if (face == 0) {
        if (!(vxp > 0.0)) return;
        distance = xpre - cfg.xMin;
        inwardSpeed = vxp;
        normalCell = dx;
        if (!(distance >= 0.0 && distance <= sourceLayers * normalCell)) return;
        const double tc = distance / inwardSpeed;
        if (!(tc >= 0.0 && tc < cfg.dt)) return;
        xCross = cfg.xMin;
        yCross = ypre + vyp * tc;
        xGhost = 2.0 * cfg.xMin - xpre + vxp * cfg.dt;
        yGhost = ypre + vyp * cfg.dt;
    } else if (face == 1) {
        if (!(vxp < 0.0)) return;
        distance = cfg.xMax - xpre;
        inwardSpeed = -vxp;
        normalCell = dx;
        if (!(distance >= 0.0 && distance <= sourceLayers * normalCell)) return;
        const double tc = distance / inwardSpeed;
        if (!(tc >= 0.0 && tc < cfg.dt)) return;
        xCross = cfg.xMax;
        yCross = ypre + vyp * tc;
        xGhost = 2.0 * cfg.xMax - xpre + vxp * cfg.dt;
        yGhost = ypre + vyp * cfg.dt;
    } else if (face == 2) {
        if (!(vyp > 0.0)) return;
        distance = ypre - cfg.yMin;
        inwardSpeed = vyp;
        normalCell = dy;
        if (!(distance >= 0.0 && distance <= sourceLayers * normalCell)) return;
        const double tc = distance / inwardSpeed;
        if (!(tc >= 0.0 && tc < cfg.dt)) return;
        xCross = xpre + vxp * tc;
        yCross = cfg.yMin;
        xGhost = xpre + vxp * cfg.dt;
        yGhost = 2.0 * cfg.yMin - ypre + vyp * cfg.dt;
    } else {
        if (!(vyp < 0.0)) return;
        distance = cfg.yMax - ypre;
        inwardSpeed = -vyp;
        normalCell = dy;
        if (!(distance >= 0.0 && distance <= sourceLayers * normalCell)) return;
        const double tc = distance / inwardSpeed;
        if (!(tc >= 0.0 && tc < cfg.dt)) return;
        xCross = xpre + vxp * tc;
        yCross = cfg.yMax;
        xGhost = xpre + vxp * cfg.dt;
        yGhost = 2.0 * cfg.yMax - ypre + vyp * cfg.dt;
    }

    // The virtual particle must cross an actual outlet segment.  Evaluate the
    // segment at the crossing point, not at the source-cell centre.
    if (!(xCross >= cfg.xMin && xCross <= cfg.xMax &&
          yCross >= cfg.yMin && yCross <= cfg.yMax)) return;
    if (outlet_mode_at_particle_0493x8q(cfg, face, xCross, yCross) != 2) return;

    // x8v-physics deliberately avoids a second chronological boundary solver
    // for the virtual particle.  Corner-crossing replicas are skipped rather
    // than clamped or reflected.  This is negligible for a non-corner outlet
    // and makes the first experiment unambiguous.
    if (!(xGhost > cfg.xMin && xGhost < cfg.xMax &&
          yGhost > cfg.yMin && yGhost < cfg.yMax)) return;
    if (!isfinite(xGhost) || !isfinite(yGhost) ||
        !isfinite(vxp) || !isfinite(vyp)) return;

    const unsigned int j = atomicAdd(candidateCount, 1u);
    if (j >= candidateCapacity) {
        atomicMax(&counters->overflowFlag, 11);
        return;
    }
    CudaNeumannReplicaCandidate0493x8v& c = candidates[j];
    c.source = source;
    c.x = xGhost;
    c.y = yGhost;
    c.vx = vxp;
    c.vy = vyp;
    c.face = face;
}

__device__ inline void record_neumann_replicas_for_survivor_0493x8v(
    std::uint64_t source,
    double xpre,
    double ypre,
    double vxp,
    double vyp,
    const CudaClassicSrcIoFullfaceConfig0263& cfg,
    CudaNeumannReplicaCandidate0493x8v* candidates,
    unsigned int* candidateCount,
    unsigned int candidateCapacity,
    CudaClassicSrcIoCounters0263* counters)
{
    if (!cfg.outletNeumannReplica0493x8v ||
        !(xpre >= cfg.xMin && xpre <= cfg.xMax &&
          ypre >= cfg.yMin && ypre <= cfg.yMax)) return;

    // More than one face can be an outlet in the 0414 multi-axis contract.
    // Each geometrically valid mirror crossing is an independent exterior copy.
    record_one_neumann_replica_0493x8v(
        source, 0, xpre, ypre, vxp, vyp, cfg,
        candidates, candidateCount, candidateCapacity, counters);
    record_one_neumann_replica_0493x8v(
        source, 1, xpre, ypre, vxp, vyp, cfg,
        candidates, candidateCount, candidateCapacity, counters);
    record_one_neumann_replica_0493x8v(
        source, 2, xpre, ypre, vxp, vyp, cfg,
        candidates, candidateCount, candidateCapacity, counters);
    record_one_neumann_replica_0493x8v(
        source, 3, xpre, ypre, vxp, vyp, cfg,
        candidates, candidateCount, candidateCapacity, counters);
}

__global__ void io_neumann_replica_insert_kernel_0493x8v(
    std::uint64_t n,
    double* __restrict__ x,
    double* __restrict__ y,
    double* __restrict__ vx,
    double* __restrict__ vy,
    double* __restrict__ mass,
    std::uint32_t* __restrict__ type,
    unsigned char* __restrict__ role,
    unsigned char fluidRole,
    unsigned char inactiveRole,
    CudaClassicSrcIoFullfaceConfig0263 cfg,
    const CudaNeumannReplicaCandidate0493x8v* __restrict__ candidates,
    unsigned int candidateCount,
    const std::uint64_t* __restrict__ inactiveIndices,
    unsigned int inactiveCount,
    CudaClassicSrcIoCounters0263* counters)
{
    const unsigned int j = blockIdx.x * blockDim.x + threadIdx.x;
    if (j >= candidateCount) return;
    if (j >= inactiveCount) {
        atomicMax(&counters->overflowFlag, 12);
        return;
    }

    const CudaNeumannReplicaCandidate0493x8v c = candidates[j];
    if (c.source >= n || c.face < 0 || c.face > 3 ||
        role[c.source] != fluidRole) {
        atomicMax(&counters->failureFlag, 10);
        return;
    }
    const std::uint64_t slot = inactiveIndices[j];
    if (slot >= n || role[slot] != inactiveRole) {
        atomicMax(&counters->overflowFlag, 13);
        return;
    }

    const double m = mass[c.source];
    if (!(m > 0.0) || !isfinite(m)) {
        atomicMax(&counters->failureFlag, 11);
        return;
    }

    x[slot] = clamp_strictly_inside_device_0263(c.x, cfg.xMin, cfg.xMax);
    y[slot] = clamp_strictly_inside_device_0263(c.y, cfg.yMin, cfg.yMax);
    vx[slot] = c.vx;
    vy[slot] = c.vy;
    mass[slot] = m;
    type[slot] = type[c.source];
    role[slot] = fluidRole;

    add_counter_ull_0267(&counters->outletParticlesInserted, 1ULL);
    add_counter_ull_0267(&counters->fluidParticles, 1ULL);
}



struct CudaNeumannBathMoments0493x8q {
    unsigned int count = 0u;
    double sumMass = 0.0;
    double sumMomX = 0.0;
    double sumMomY = 0.0;
    double sumMvv = 0.0;
    unsigned long long sourcePacked = 0ULL;

    // After io_neumann_bath_candidates_kernel_0493x8q these four fields are
    // overwritten with derived bath values:
    // sumMass=mbar, sumMomX=ux, sumMomY=uy, sumMvv=kBT.
};

__host__ __device__ inline unsigned int neumann_bath_cell_count_0493x8q(
    const CudaClassicSrcIoFullfaceConfig0263& cfg)
{
    const unsigned int nx = static_cast<unsigned int>(cfg.Nx > 0 ? cfg.Nx : 1);
    const unsigned int ny = static_cast<unsigned int>(cfg.Ny > 0 ? cfg.Ny : 1);
    return 2u * (nx + ny);
}

__host__ __device__ inline unsigned int neumann_bath_index_0493x8q(
    const CudaClassicSrcIoFullfaceConfig0263& cfg,
    int face,
    int tangentialCell)
{
    const unsigned int nx = static_cast<unsigned int>(cfg.Nx > 0 ? cfg.Nx : 1);
    const unsigned int ny = static_cast<unsigned int>(cfg.Ny > 0 ? cfg.Ny : 1);
    if (face == 0) return static_cast<unsigned int>(tangentialCell);
    if (face == 1) return ny + static_cast<unsigned int>(tangentialCell);
    if (face == 2) return 2u * ny + static_cast<unsigned int>(tangentialCell);
    return 2u * ny + nx + static_cast<unsigned int>(tangentialCell);
}

__host__ __device__ inline bool neumann_bath_decode_0493x8q(
    const CudaClassicSrcIoFullfaceConfig0263& cfg,
    unsigned int bathCell,
    int& face,
    int& tangentialCell)
{
    const unsigned int nx = static_cast<unsigned int>(cfg.Nx > 0 ? cfg.Nx : 1);
    const unsigned int ny = static_cast<unsigned int>(cfg.Ny > 0 ? cfg.Ny : 1);
    if (bathCell < ny) {
        face = 0; tangentialCell = static_cast<int>(bathCell); return true;
    }
    bathCell -= ny;
    if (bathCell < ny) {
        face = 1; tangentialCell = static_cast<int>(bathCell); return true;
    }
    bathCell -= ny;
    if (bathCell < nx) {
        face = 2; tangentialCell = static_cast<int>(bathCell); return true;
    }
    bathCell -= nx;
    if (bathCell < nx) {
        face = 3; tangentialCell = static_cast<int>(bathCell); return true;
    }
    return false;
}

__device__ inline void accumulate_one_neumann_bath_0493x8q(
    std::uint64_t particleIndex,
    int face,
    int tangentialCell,
    double xp,
    double yp,
    double vxp,
    double vyp,
    double particleMass,
    const CudaClassicSrcIoFullfaceConfig0263& cfg,
    CudaNeumannBathMoments0493x8q* bath,
    unsigned int bathCellCount)
{
    if (outlet_mode_at_particle_0493x8q(cfg, face, xp, yp) != 2) return;
    const unsigned int bidx =
        neumann_bath_index_0493x8q(cfg, face, tangentialCell);
    if (bidx >= bathCellCount) return;

    CudaNeumannBathMoments0493x8q* b = bath + bidx;
    const double m = isfinite(particleMass) && particleMass > 0.0
        ? particleMass : cfg.refMass;

    atomicAdd(&b->count, 1u);
    atomicAdd(&b->sumMass, m);
    atomicAdd(&b->sumMomX, m * vxp);
    atomicAdd(&b->sumMomY, m * vyp);
    atomicAdd(&b->sumMvv, m * (vxp * vxp + vyp * vyp));

    if (particleIndex <= 0xffffffffULL) {
        const std::uint64_t z = splitmix64_device_0263(
            cfg.rngSeed ^
            (cfg.step * 0x9e3779b97f4a7c15ULL) ^
            (particleIndex * 0xbf58476d1ce4e5b9ULL) ^
            (static_cast<std::uint64_t>(bidx + 1u) * 0x94d049bb133111ebULL));
        const unsigned long long priority =
            static_cast<unsigned long long>(static_cast<unsigned int>(z >> 32));
        const unsigned long long packed =
            ((priority | 1ULL) << 32) |
            static_cast<unsigned long long>(
                static_cast<unsigned int>(particleIndex));
        atomicMax(&b->sourcePacked, packed);
    }
}

__device__ inline void accumulate_neumann_bath_moments_0493x8q(
    std::uint64_t particleIndex,
    double xpre,
    double ypre,
    double vxp,
    double vyp,
    double particleMass,
    const CudaClassicSrcIoFullfaceConfig0263& cfg,
    CudaNeumannBathMoments0493x8q* bath,
    unsigned int bathCellCount)
{
    if (!cfg.outletNeumannKinetic0493x8q ||
        bath == nullptr || bathCellCount == 0u) return;
    if (!(xpre >= cfg.xMin && xpre <= cfg.xMax &&
          ypre >= cfg.yMin && ypre <= cfg.yMax)) return;

    const int nx = cfg.Nx > 0 ? cfg.Nx : 1;
    const int ny = cfg.Ny > 0 ? cfg.Ny : 1;
    const double dx = (cfg.xMax - cfg.xMin) / static_cast<double>(nx);
    const double dy = (cfg.yMax - cfg.yMin) / static_cast<double>(ny);
    if (!(dx > 0.0) || !(dy > 0.0)) return;

    constexpr int layers = 2;
    const bool nearLeft   = xpre <  cfg.xMin + layers * dx;
    const bool nearRight  = xpre >= cfg.xMax - layers * dx;
    const bool nearBottom = ypre <  cfg.yMin + layers * dy;
    const bool nearTop    = ypre >= cfg.yMax - layers * dy;
    if (!(nearLeft || nearRight || nearBottom || nearTop)) return;

    int ix = static_cast<int>(floor((xpre - cfg.xMin) / dx));
    int iy = static_cast<int>(floor((ypre - cfg.yMin) / dy));
    ix = imax_device_0263(0, imin_device_0263(nx - 1, ix));
    iy = imax_device_0263(0, imin_device_0263(ny - 1, iy));

    if (nearLeft) {
        accumulate_one_neumann_bath_0493x8q(
            particleIndex, 0, iy, xpre, ypre, vxp, vyp, particleMass,
            cfg, bath, bathCellCount);
    }
    if (nearRight) {
        accumulate_one_neumann_bath_0493x8q(
            particleIndex, 1, iy, xpre, ypre, vxp, vyp, particleMass,
            cfg, bath, bathCellCount);
    }
    if (nearBottom) {
        accumulate_one_neumann_bath_0493x8q(
            particleIndex, 2, ix, xpre, ypre, vxp, vyp, particleMass,
            cfg, bath, bathCellCount);
    }
    if (nearTop) {
        accumulate_one_neumann_bath_0493x8q(
            particleIndex, 3, ix, xpre, ypre, vxp, vyp, particleMass,
            cfg, bath, bathCellCount);
    }
}

// -----------------------------------------------------------------------------
// 0493x8r -- species-resolved Neumann kinetic continuation.
//
// The legacy x8q kernels above remain unchanged. x8r is a separate path selected
// only for a strict registered multi-species state. Its bath layout is
// [spatial boundary cell][registered species], so no kinetic moment or metadata
// source can mix particle types.
// -----------------------------------------------------------------------------

__device__ inline int neumann_species_index_0493x8r(
    std::uint32_t particleType,
    const std::uint32_t* speciesTypes,
    unsigned int speciesCount)
{
    if (speciesTypes == nullptr || speciesCount == 0u) return -1;
    for (unsigned int s = 0u; s < speciesCount; ++s) {
        if (speciesTypes[s] == particleType) return static_cast<int>(s);
    }
    return -1;
}

__device__ inline void accumulate_one_neumann_species_bath_0493x8r(
    std::uint64_t particleIndex,
    int face,
    int tangentialCell,
    unsigned int speciesIndex,
    unsigned int speciesCount,
    double xp,
    double yp,
    double vxp,
    double vyp,
    double particleMass,
    const CudaClassicSrcIoFullfaceConfig0263& cfg,
    CudaNeumannBathMoments0493x8q* bath,
    unsigned int bathEntryCount)
{
    if (outlet_mode_at_particle_0493x8q(cfg, face, xp, yp) != 2) return;
    if (speciesIndex >= speciesCount || speciesCount == 0u) return;

    const unsigned int spatial =
        neumann_bath_index_0493x8q(cfg, face, tangentialCell);
    const unsigned long long flat64 =
        static_cast<unsigned long long>(spatial) *
            static_cast<unsigned long long>(speciesCount) +
        static_cast<unsigned long long>(speciesIndex);
    if (flat64 >= static_cast<unsigned long long>(bathEntryCount)) return;
    const unsigned int bidx = static_cast<unsigned int>(flat64);

    CudaNeumannBathMoments0493x8q* b = bath + bidx;
    const double m = isfinite(particleMass) && particleMass > 0.0
        ? particleMass : cfg.refMass;

    atomicAdd(&b->count, 1u);
    atomicAdd(&b->sumMass, m);
    atomicAdd(&b->sumMomX, m * vxp);
    atomicAdd(&b->sumMomY, m * vyp);
    atomicAdd(&b->sumMvv, m * (vxp * vxp + vyp * vyp));

    // The metadata source is selected only from this species-resolved entry.
    if (particleIndex <= 0xffffffffULL) {
        const std::uint64_t z = splitmix64_device_0263(
            cfg.rngSeed ^
            (cfg.step * 0x9e3779b97f4a7c15ULL) ^
            (particleIndex * 0xbf58476d1ce4e5b9ULL) ^
            (static_cast<std::uint64_t>(bidx + 1u) * 0x94d049bb133111ebULL));
        const unsigned long long priority =
            static_cast<unsigned long long>(static_cast<unsigned int>(z >> 32));
        const unsigned long long packed =
            ((priority | 1ULL) << 32) |
            static_cast<unsigned long long>(
                static_cast<unsigned int>(particleIndex));
        atomicMax(&b->sourcePacked, packed);
    }
}

__device__ inline void accumulate_neumann_species_bath_moments_0493x8r(
    std::uint64_t particleIndex,
    double xpre,
    double ypre,
    double vxp,
    double vyp,
    double particleMass,
    std::uint32_t particleType,
    const CudaClassicSrcIoFullfaceConfig0263& cfg,
    const std::uint32_t* speciesTypes,
    unsigned int speciesCount,
    CudaNeumannBathMoments0493x8q* bath,
    unsigned int bathEntryCount)
{
    if (!cfg.outletNeumannKinetic0493x8q || bath == nullptr ||
        bathEntryCount == 0u || speciesCount == 0u) return;
    if (!(xpre >= cfg.xMin && xpre <= cfg.xMax &&
          ypre >= cfg.yMin && ypre <= cfg.yMax)) return;

    const int speciesIndexSigned =
        neumann_species_index_0493x8r(particleType, speciesTypes, speciesCount);
    if (speciesIndexSigned < 0) return;
    const unsigned int speciesIndex =
        static_cast<unsigned int>(speciesIndexSigned);

    const int nx = cfg.Nx > 0 ? cfg.Nx : 1;
    const int ny = cfg.Ny > 0 ? cfg.Ny : 1;
    const double dx = (cfg.xMax - cfg.xMin) / static_cast<double>(nx);
    const double dy = (cfg.yMax - cfg.yMin) / static_cast<double>(ny);
    if (!(dx > 0.0) || !(dy > 0.0)) return;

    constexpr int layers = 2;
    const bool nearLeft   = xpre <  cfg.xMin + layers * dx;
    const bool nearRight  = xpre >= cfg.xMax - layers * dx;
    const bool nearBottom = ypre <  cfg.yMin + layers * dy;
    const bool nearTop    = ypre >= cfg.yMax - layers * dy;
    if (!(nearLeft || nearRight || nearBottom || nearTop)) return;

    int ix = static_cast<int>(floor((xpre - cfg.xMin) / dx));
    int iy = static_cast<int>(floor((ypre - cfg.yMin) / dy));
    ix = imax_device_0263(0, imin_device_0263(nx - 1, ix));
    iy = imax_device_0263(0, imin_device_0263(ny - 1, iy));

    if (nearLeft) {
        accumulate_one_neumann_species_bath_0493x8r(
            particleIndex, 0, iy, speciesIndex, speciesCount,
            xpre, ypre, vxp, vyp, particleMass, cfg, bath, bathEntryCount);
    }
    if (nearRight) {
        accumulate_one_neumann_species_bath_0493x8r(
            particleIndex, 1, iy, speciesIndex, speciesCount,
            xpre, ypre, vxp, vyp, particleMass, cfg, bath, bathEntryCount);
    }
    if (nearBottom) {
        accumulate_one_neumann_species_bath_0493x8r(
            particleIndex, 2, ix, speciesIndex, speciesCount,
            xpre, ypre, vxp, vyp, particleMass, cfg, bath, bathEntryCount);
    }
    if (nearTop) {
        accumulate_one_neumann_species_bath_0493x8r(
            particleIndex, 3, ix, speciesIndex, speciesCount,
            xpre, ypre, vxp, vyp, particleMass, cfg, bath, bathEntryCount);
    }
}

__global__ void io_neumann_species_bath_accumulate_kernel_0493x8r(
    std::uint64_t n,
    const double* __restrict__ x,
    const double* __restrict__ y,
    const double* __restrict__ vx,
    const double* __restrict__ vy,
    const double* __restrict__ mass,
    const std::uint32_t* __restrict__ type,
    const unsigned char* __restrict__ role,
    unsigned char fluidRole,
    CudaClassicSrcIoFullfaceConfig0263 cfg,
    const std::uint32_t* __restrict__ speciesTypes,
    unsigned int speciesCount,
    CudaNeumannBathMoments0493x8q* __restrict__ bath,
    unsigned int bathEntryCount)
{
    const std::uint64_t i =
        static_cast<std::uint64_t>(blockIdx.x) *
            static_cast<std::uint64_t>(blockDim.x) +
        static_cast<std::uint64_t>(threadIdx.x);
    if (i >= n || role[i] != fluidRole) return;
    if (!isfinite(x[i]) || !isfinite(y[i]) ||
        !isfinite(vx[i]) || !isfinite(vy[i])) return;

    const double xpre = x[i] - vx[i] * cfg.dt;
    const double ypre = y[i] - vy[i] * cfg.dt;
    accumulate_neumann_species_bath_moments_0493x8r(
        i, xpre, ypre, vx[i], vy[i], mass[i], type[i], cfg,
        speciesTypes, speciesCount, bath, bathEntryCount);
}

__device__ inline double normal_pdf_0493x8q(double z)
{
    return 0.39894228040143267794 * exp(-0.5 * z * z);
}

__device__ inline double normal_cdf_0493x8q(double z)
{
    return 0.5 * erfc(-0.70710678118654752440 * z);
}

__device__ inline double incoming_normal_moment_0493x8q(double un, double sigma)
{
    if (!(sigma > 0.0) || !isfinite(sigma))
        return fmax(0.0, -un);
    const double a = un / sigma;
    const double m =
        sigma * normal_pdf_0493x8q(a) -
        un * (0.5 * erfc(0.70710678118654752440 * a));
    return isfinite(m) ? fmax(0.0, m) : 0.0;
}

__device__ inline double sample_incoming_normal_velocity_0493x8q(
    double un,
    double sigma,
    double uniform01)
{
    if (!(sigma > 0.0) || !isfinite(sigma))
        return un < 0.0 ? un : -0.0;

    const double zhi = -un / sigma;
    const double total = incoming_normal_moment_0493x8q(un, sigma);
    if (!(total > 0.0)) return -0.0;

    const double target = fmin(fmax(uniform01, 0.0), 1.0) * total;
    double zlo = fmin(-12.0, zhi - 12.0);
    double hi = zhi;

    for (int it = 0; it < 18; ++it) {
        const double z = 0.5 * (zlo + hi);
        const double F =
            sigma * normal_pdf_0493x8q(z) -
            un * normal_cdf_0493x8q(z);
        if (F < target) zlo = z;
        else hi = z;
    }
    return fmin(0.0, un + sigma * 0.5 * (zlo + hi));
}

__device__ inline double uniform_from_u64_0493x8q(std::uint64_t z)
{
    return static_cast<double>(z >> 11) * 0x1.0p-53;
}

__global__ void io_neumann_bath_candidates_kernel_0493x8q(
    std::uint64_t n,
    const double* __restrict__ mass,
    const std::uint32_t* __restrict__ type,
    CudaClassicSrcIoFullfaceConfig0263 cfg,
    CudaNeumannBathMoments0493x8q* __restrict__ bath,
    unsigned int bathCellCount,
    CudaNeumannGhostCandidate0493x8q* __restrict__ candidates,
    unsigned int* candidateCount,
    unsigned int candidateCapacity)
{
    const unsigned int bidx = blockIdx.x * blockDim.x + threadIdx.x;
    if (bidx >= bathCellCount) return;

    CudaNeumannBathMoments0493x8q& b = bath[bidx];
    const unsigned int N = b.count;
    if (N < 2u || !(b.sumMass > 0.0) || b.sourcePacked == 0ULL) return;

    int face = -1;
    int tangentialCell = -1;
    if (!neumann_bath_decode_0493x8q(cfg, bidx, face, tangentialCell)) return;

    const double sumM = b.sumMass;
    const double ux = b.sumMomX / sumM;
    const double uy = b.sumMomY / sumM;
    const double rel =
        b.sumMvv - (b.sumMomX * b.sumMomX + b.sumMomY * b.sumMomY) / sumM;

    double kBTlocal = 0.5 * fmax(0.0, rel) / static_cast<double>(N);
    if (!isfinite(kBTlocal) || kBTlocal < 0.0)
        kBTlocal = fmax(0.0, cfg.inletKBT);
    if (!(kBTlocal > 0.0) && cfg.inletKBT > 0.0)
        kBTlocal = cfg.inletKBT;

    const double mbar = sumM / static_cast<double>(N);
    const double sigmaBar =
        (kBTlocal > 0.0 && mbar > 0.0) ? sqrt(kBTlocal / mbar) : 0.0;

    double un = 0.0;
    double normalWidth = 1.0;
    const int nx = cfg.Nx > 0 ? cfg.Nx : 1;
    const int ny = cfg.Ny > 0 ? cfg.Ny : 1;
    const double dx = (cfg.xMax - cfg.xMin) / static_cast<double>(nx);
    const double dy = (cfg.yMax - cfg.yMin) / static_cast<double>(ny);
    constexpr double layers = 2.0;

    if (face == 0) { un = -ux; normalWidth = layers * dx; }
    else if (face == 1) { un = ux; normalWidth = layers * dx; }
    else if (face == 2) { un = -uy; normalWidth = layers * dy; }
    else if (face == 3) { un = uy; normalWidth = layers * dy; }
    else return;

    if (!(normalWidth > 0.0) || !(cfg.dt > 0.0)) return;

    const double oneWay = incoming_normal_moment_0493x8q(un, sigmaBar);
    const double lambda =
        static_cast<double>(N) * (cfg.dt / normalWidth) * oneWay;
    if (!(lambda > 0.0) || !isfinite(lambda)) return;

    const double baseD = floor(lambda);
    if (baseD > static_cast<double>(0xffffffffu - 1u)) return;
    unsigned int copies = static_cast<unsigned int>(baseD);
    const double frac = lambda - baseD;

    std::uint64_t z = splitmix64_device_0263(
        cfg.rngSeed ^
        (cfg.step * 0xd2b74407b1ce6e93ULL) ^
        (static_cast<std::uint64_t>(bidx + 1u) * 0x9e3779b97f4a7c15ULL));
    if (uniform_from_u64_0493x8q(z) < frac) ++copies;

    b.sumMass = mbar;
    b.sumMomX = ux;
    b.sumMomY = uy;
    b.sumMvv = kBTlocal;

    if (copies == 0u) return;

    const std::uint64_t source =
        static_cast<std::uint64_t>(
            static_cast<unsigned int>(b.sourcePacked & 0xffffffffULL));
    if (source >= n) return;

    const double particleMass =
        isfinite(mass[source]) && mass[source] > 0.0 ? mass[source] : mbar;
    const std::uint32_t particleType = type[source];

    const unsigned int first = atomicAdd(candidateCount, copies);
    if (first > candidateCapacity || copies > candidateCapacity - first) return;

    for (unsigned int k = 0u; k < copies; ++k) {
        CudaNeumannGhostCandidate0493x8q& c = candidates[first + k];
        c.source = source;
        c.bathCell = bidx;
        c.face = face;
        c.particleMass = particleMass;
        c.particleType = particleType;
    }
}

__global__ void io_neumann_species_bath_candidates_kernel_0493x8r(
    std::uint64_t n,
    const double* __restrict__ mass,
    const std::uint32_t* __restrict__ type,
    CudaClassicSrcIoFullfaceConfig0263 cfg,
    CudaNeumannBathMoments0493x8q* __restrict__ bath,
    unsigned int bathEntryCount,
    const std::uint32_t* __restrict__ speciesTypes,
    const double* __restrict__ speciesFallbackKBT,
    unsigned int speciesCount,
    CudaNeumannGhostCandidate0493x8q* __restrict__ candidates,
    unsigned int* candidateCount,
    unsigned int candidateCapacity)
{
    const unsigned int bidx = blockIdx.x * blockDim.x + threadIdx.x;
    if (bidx >= bathEntryCount || speciesCount == 0u) return;

    CudaNeumannBathMoments0493x8q& b = bath[bidx];
    const unsigned int N = b.count;
    if (N < 2u || !(b.sumMass > 0.0) || b.sourcePacked == 0ULL) return;

    const unsigned int speciesIndex = bidx % speciesCount;
    const unsigned int spatialBidx = bidx / speciesCount;
    if (speciesIndex >= speciesCount) return;

    int face = -1;
    int tangentialCell = -1;
    if (!neumann_bath_decode_0493x8q(
            cfg, spatialBidx, face, tangentialCell)) return;

    const double sumM = b.sumMass;
    const double ux = b.sumMomX / sumM;
    const double uy = b.sumMomY / sumM;
    const double rel =
        b.sumMvv - (b.sumMomX * b.sumMomX + b.sumMomY * b.sumMomY) / sumM;

    const double fallbackKBT = speciesFallbackKBT != nullptr
        ? speciesFallbackKBT[speciesIndex] : cfg.inletKBT;
    double kBTlocal = 0.5 * fmax(0.0, rel) / static_cast<double>(N);
    if (!isfinite(kBTlocal) || kBTlocal < 0.0)
        kBTlocal = fmax(0.0, fallbackKBT);
    if (!(kBTlocal > 0.0) && fallbackKBT > 0.0)
        kBTlocal = fallbackKBT;

    const double mbar = sumM / static_cast<double>(N);
    const double sigmaBar =
        (kBTlocal > 0.0 && mbar > 0.0) ? sqrt(kBTlocal / mbar) : 0.0;

    double un = 0.0;
    double normalWidth = 1.0;
    const int nx = cfg.Nx > 0 ? cfg.Nx : 1;
    const int ny = cfg.Ny > 0 ? cfg.Ny : 1;
    const double dx = (cfg.xMax - cfg.xMin) / static_cast<double>(nx);
    const double dy = (cfg.yMax - cfg.yMin) / static_cast<double>(ny);
    constexpr double layers = 2.0;

    if (face == 0) { un = -ux; normalWidth = layers * dx; }
    else if (face == 1) { un = ux; normalWidth = layers * dx; }
    else if (face == 2) { un = -uy; normalWidth = layers * dy; }
    else if (face == 3) { un = uy; normalWidth = layers * dy; }
    else return;

    if (!(normalWidth > 0.0) || !(cfg.dt > 0.0)) return;

    const double oneWay = incoming_normal_moment_0493x8q(un, sigmaBar);
    const double lambda =
        static_cast<double>(N) * (cfg.dt / normalWidth) * oneWay;
    if (!(lambda > 0.0) || !isfinite(lambda)) return;

    const double baseD = floor(lambda);
    if (baseD > static_cast<double>(0xffffffffu - 1u)) return;
    unsigned int copies = static_cast<unsigned int>(baseD);
    const double frac = lambda - baseD;

    std::uint64_t z = splitmix64_device_0263(
        cfg.rngSeed ^
        (cfg.step * 0xd2b74407b1ce6e93ULL) ^
        (static_cast<std::uint64_t>(bidx + 1u) * 0x9e3779b97f4a7c15ULL));
    if (uniform_from_u64_0493x8q(z) < frac) ++copies;

    b.sumMass = mbar;
    b.sumMomX = ux;
    b.sumMomY = uy;
    b.sumMvv = kBTlocal;

    if (copies == 0u) return;

    const std::uint64_t source =
        static_cast<std::uint64_t>(
            static_cast<unsigned int>(b.sourcePacked & 0xffffffffULL));
    if (source >= n) return;
    if (speciesTypes == nullptr || type[source] != speciesTypes[speciesIndex])
        return;

    const double particleMass =
        isfinite(mass[source]) && mass[source] > 0.0 ? mass[source] : mbar;
    const std::uint32_t particleType = speciesTypes[speciesIndex];

    const unsigned int first = atomicAdd(candidateCount, copies);
    if (first > candidateCapacity || copies > candidateCapacity - first) return;

    for (unsigned int k = 0u; k < copies; ++k) {
        CudaNeumannGhostCandidate0493x8q& c = candidates[first + k];
        c.source = source;
        c.bathCell = bidx;
        c.face = face;
        c.particleMass = particleMass;
        c.particleType = particleType;
    }
}

__global__ void io_neumann_ghost_insert_kernel_0493x8q(
    std::uint64_t n,
    double* __restrict__ x,
    double* __restrict__ y,
    double* __restrict__ vx,
    double* __restrict__ vy,
    double* __restrict__ mass,
    std::uint32_t* __restrict__ type,
    unsigned char* __restrict__ role,
    unsigned char fluidRole,
    unsigned char inactiveRole,
    CudaClassicSrcIoFullfaceConfig0263 cfg,
    const CudaNeumannGhostCandidate0493x8q* __restrict__ candidates,
    unsigned int candidateCount,
    const CudaNeumannBathMoments0493x8q* __restrict__ bath,
    unsigned int bathCellCount,
    const std::uint64_t* __restrict__ inactiveIndices,
    unsigned int inactiveCount,
    CudaClassicSrcIoCounters0263* counters)
{
    const unsigned int j = blockIdx.x * blockDim.x + threadIdx.x;
    if (j >= candidateCount) return;
    if (j >= inactiveCount) {
        atomicMax(&counters->overflowFlag, 9);
        return;
    }

    const CudaNeumannGhostCandidate0493x8q c = candidates[j];
    if (c.bathCell >= bathCellCount || c.face < 0 || c.face > 3) {
        atomicMax(&counters->failureFlag, 8);
        return;
    }

    const std::uint64_t slot = inactiveIndices[j];
    if (slot >= n || role[slot] != inactiveRole) {
        atomicMax(&counters->overflowFlag, 10);
        return;
    }

    const CudaNeumannBathMoments0493x8q b = bath[c.bathCell];
    const double ux = b.sumMomX;
    const double uy = b.sumMomY;
    const double kBTlocal = fmax(0.0, b.sumMvv);
    const double particleMass =
        c.particleMass > 0.0 ? c.particleMass :
        (b.sumMass > 0.0 ? b.sumMass : cfg.refMass);
    const double sigma =
        (kBTlocal > 0.0 && particleMass > 0.0)
        ? sqrt(kBTlocal / particleMass) : 0.0;

    double un = 0.0;
    double ut = 0.0;
    if (c.face == 0) { un = -ux; ut = uy; }
    else if (c.face == 1) { un = ux; ut = uy; }
    else if (c.face == 2) { un = -uy; ut = ux; }
    else { un = uy; ut = ux; }

    std::uint64_t z1 = splitmix64_device_0263(
        cfg.rngSeed ^
        (cfg.step * 0x94d049bb133111ebULL) ^
        (static_cast<std::uint64_t>(j + 1u) * 0x369dea0f31a53f85ULL) ^
        (static_cast<std::uint64_t>(c.bathCell + 1u) * 0x9e3779b97f4a7c15ULL));
    const std::uint64_t z2 = splitmix64_device_0263(z1 ^ 0x243f6a8885a308d3ULL);
    const std::uint64_t z3 = splitmix64_device_0263(z2 ^ 0x13198a2e03707344ULL);
    const std::uint64_t z4 = splitmix64_device_0263(z3 ^ 0xa4093822299f31d0ULL);
    const std::uint64_t z5 = splitmix64_device_0263(z4 ^ 0x082efa98ec4e6c89ULL);

    const double rFlux = uniform_from_u64_0493x8q(z1);
    const double r1 = fmax(1.0e-15, uniform_from_u64_0493x8q(z2));
    const double r2 = uniform_from_u64_0493x8q(z3);
    const double rNormalPos = uniform_from_u64_0493x8q(z4);
    const double rTangentialPos = uniform_from_u64_0493x8q(z5);

    const double vn =
        sample_incoming_normal_velocity_0493x8q(un, sigma, rFlux);
    const double gaussian =
        sqrt(-2.0 * log(r1)) *
        cos(6.28318530717958647693 * r2);
    const double vt = ut + sigma * gaussian;

    double vxp = 0.0;
    double vyp = 0.0;
    if (c.face == 0) { vxp = -vn; vyp = vt; }
    else if (c.face == 1) { vxp = vn; vyp = vt; }
    else if (c.face == 2) { vxp = vt; vyp = -vn; }
    else { vxp = vt; vyp = vn; }

    int decodedFace = -1;
    int tangentialCell = -1;
    if (!neumann_bath_decode_0493x8q(
            cfg, c.bathCell, decodedFace, tangentialCell) ||
        decodedFace != c.face) {
        atomicMax(&counters->failureFlag, 9);
        return;
    }

    const int nx = cfg.Nx > 0 ? cfg.Nx : 1;
    const int ny = cfg.Ny > 0 ? cfg.Ny : 1;
    const double dx = (cfg.xMax - cfg.xMin) / static_cast<double>(nx);
    const double dy = (cfg.yMax - cfg.yMin) / static_cast<double>(ny);
    const double penetration = rNormalPos * fmax(0.0, -vn) * cfg.dt;

    double xp = 0.5 * (cfg.xMin + cfg.xMax);
    double yp = 0.5 * (cfg.yMin + cfg.yMax);

    if (c.face == 0 || c.face == 1) {
        yp = cfg.yMin +
            (static_cast<double>(tangentialCell) + rTangentialPos) * dy;
        xp = c.face == 0 ? cfg.xMin + penetration : cfg.xMax - penetration;
    } else {
        xp = cfg.xMin +
            (static_cast<double>(tangentialCell) + rTangentialPos) * dx;
        yp = c.face == 2 ? cfg.yMin + penetration : cfg.yMax - penetration;
    }

    xp = clamp_strictly_inside_device_0263(xp, cfg.xMin, cfg.xMax);
    yp = clamp_strictly_inside_device_0263(yp, cfg.yMin, cfg.yMax);

    x[slot] = xp;
    y[slot] = yp;
    vx[slot] = vxp;
    vy[slot] = vyp;
    mass[slot] = particleMass;
    type[slot] = c.particleType;
    role[slot] = fluidRole;

    add_counter_ull_0267(&counters->outletParticlesInserted, 1ULL);
    add_counter_ull_0267(&counters->fluidParticles, 1ULL);
}

__global__ void io_neumann_species_ghost_insert_kernel_0493x8r(
    std::uint64_t n,
    double* __restrict__ x,
    double* __restrict__ y,
    double* __restrict__ vx,
    double* __restrict__ vy,
    double* __restrict__ mass,
    std::uint32_t* __restrict__ type,
    unsigned char* __restrict__ role,
    unsigned char fluidRole,
    unsigned char inactiveRole,
    CudaClassicSrcIoFullfaceConfig0263 cfg,
    const CudaNeumannGhostCandidate0493x8q* __restrict__ candidates,
    unsigned int candidateCount,
    const CudaNeumannBathMoments0493x8q* __restrict__ bath,
    unsigned int bathEntryCount,
    unsigned int speciesCount,
    const std::uint64_t* __restrict__ inactiveIndices,
    unsigned int inactiveCount,
    CudaClassicSrcIoCounters0263* counters)
{
    const unsigned int j = blockIdx.x * blockDim.x + threadIdx.x;
    if (j >= candidateCount) return;
    if (j >= inactiveCount) {
        atomicMax(&counters->overflowFlag, 9);
        return;
    }

    const CudaNeumannGhostCandidate0493x8q c = candidates[j];
    if (c.bathCell >= bathEntryCount || c.face < 0 || c.face > 3 ||
        speciesCount == 0u) {
        atomicMax(&counters->failureFlag, 8);
        return;
    }

    const std::uint64_t slot = inactiveIndices[j];
    if (slot >= n || role[slot] != inactiveRole) {
        atomicMax(&counters->overflowFlag, 10);
        return;
    }

    const CudaNeumannBathMoments0493x8q b = bath[c.bathCell];
    const double ux = b.sumMomX;
    const double uy = b.sumMomY;
    const double kBTlocal = fmax(0.0, b.sumMvv);
    const double particleMass =
        c.particleMass > 0.0 ? c.particleMass :
        (b.sumMass > 0.0 ? b.sumMass : cfg.refMass);
    const double sigma =
        (kBTlocal > 0.0 && particleMass > 0.0)
        ? sqrt(kBTlocal / particleMass) : 0.0;

    double un = 0.0;
    double ut = 0.0;
    if (c.face == 0) { un = -ux; ut = uy; }
    else if (c.face == 1) { un = ux; ut = uy; }
    else if (c.face == 2) { un = -uy; ut = ux; }
    else { un = uy; ut = ux; }

    std::uint64_t z1 = splitmix64_device_0263(
        cfg.rngSeed ^
        (cfg.step * 0x94d049bb133111ebULL) ^
        (static_cast<std::uint64_t>(j + 1u) * 0x369dea0f31a53f85ULL) ^
        (static_cast<std::uint64_t>(c.bathCell + 1u) * 0x9e3779b97f4a7c15ULL));
    const std::uint64_t z2 = splitmix64_device_0263(z1 ^ 0x243f6a8885a308d3ULL);
    const std::uint64_t z3 = splitmix64_device_0263(z2 ^ 0x13198a2e03707344ULL);
    const std::uint64_t z4 = splitmix64_device_0263(z3 ^ 0xa4093822299f31d0ULL);
    const std::uint64_t z5 = splitmix64_device_0263(z4 ^ 0x082efa98ec4e6c89ULL);

    const double rFlux = uniform_from_u64_0493x8q(z1);
    const double r1 = fmax(1.0e-15, uniform_from_u64_0493x8q(z2));
    const double r2 = uniform_from_u64_0493x8q(z3);
    const double rNormalPos = uniform_from_u64_0493x8q(z4);
    const double rTangentialPos = uniform_from_u64_0493x8q(z5);

    const double vn =
        sample_incoming_normal_velocity_0493x8q(un, sigma, rFlux);
    const double gaussian =
        sqrt(-2.0 * log(r1)) *
        cos(6.28318530717958647693 * r2);
    const double vt = ut + sigma * gaussian;

    double vxp = 0.0;
    double vyp = 0.0;
    if (c.face == 0) { vxp = -vn; vyp = vt; }
    else if (c.face == 1) { vxp = vn; vyp = vt; }
    else if (c.face == 2) { vxp = vt; vyp = -vn; }
    else { vxp = vt; vyp = vn; }

    const unsigned int spatialBathCell = c.bathCell / speciesCount;
    int decodedFace = -1;
    int tangentialCell = -1;
    if (!neumann_bath_decode_0493x8q(
            cfg, spatialBathCell, decodedFace, tangentialCell) ||
        decodedFace != c.face) {
        atomicMax(&counters->failureFlag, 9);
        return;
    }

    const int nx = cfg.Nx > 0 ? cfg.Nx : 1;
    const int ny = cfg.Ny > 0 ? cfg.Ny : 1;
    const double dx = (cfg.xMax - cfg.xMin) / static_cast<double>(nx);
    const double dy = (cfg.yMax - cfg.yMin) / static_cast<double>(ny);
    const double penetration = rNormalPos * fmax(0.0, -vn) * cfg.dt;

    double xp = 0.5 * (cfg.xMin + cfg.xMax);
    double yp = 0.5 * (cfg.yMin + cfg.yMax);

    if (c.face == 0 || c.face == 1) {
        yp = cfg.yMin +
            (static_cast<double>(tangentialCell) + rTangentialPos) * dy;
        xp = c.face == 0 ? cfg.xMin + penetration : cfg.xMax - penetration;
    } else {
        xp = cfg.xMin +
            (static_cast<double>(tangentialCell) + rTangentialPos) * dx;
        yp = c.face == 2 ? cfg.yMin + penetration : cfg.yMax - penetration;
    }

    xp = clamp_strictly_inside_device_0263(xp, cfg.xMin, cfg.xMax);
    yp = clamp_strictly_inside_device_0263(yp, cfg.yMin, cfg.yMax);

    x[slot] = xp;
    y[slot] = yp;
    vx[slot] = vxp;
    vy[slot] = vyp;
    mass[slot] = particleMass;
    type[slot] = c.particleType;
    role[slot] = fluidRole;

    add_counter_ull_0267(&counters->outletParticlesInserted, 1ULL);
    add_counter_ull_0267(&counters->fluidParticles, 1ULL);
}



__global__ void io_fullface_boundary_particles_kernel_0267(
    std::uint64_t n,
    double* __restrict__ x,
    double* __restrict__ y,
    double* __restrict__ vx,
    double* __restrict__ vy,
    const double* __restrict__ mass,
    unsigned char* __restrict__ role,
    unsigned char fluidRole,
    unsigned char inactiveRole,
    CudaClassicSrcIoFullfaceConfig0263 cfg,
    CudaClassicSrcIoCounters0263* counters,
    CudaNeumannGhostCandidate0493x8q* ghostCandidates,
    unsigned int* ghostCandidateCount,
    unsigned int ghostCandidateCapacity,
    CudaNeumannBathMoments0493x8q* bathMoments0493x8q,
    unsigned int bathCellCount0493x8q,
    CudaNeumannReplicaCandidate0493x8v* replicaCandidates0493x8v,
    unsigned int* replicaCandidateCount0493x8v,
    unsigned int replicaCandidateCapacity0493x8v,
    std::uint64_t* recycleDeletedIndices0493x9e,
    unsigned int* recycleDeletedCount0493x9e,
    std::uint64_t recycleDeletedCapacity0493x9e)
{
    const std::uint64_t i = static_cast<std::uint64_t>(blockIdx.x) * static_cast<std::uint64_t>(blockDim.x) +
                            static_cast<std::uint64_t>(threadIdx.x);
    if (i >= n) return;
    if (role[i] != fluidRole) return;

    CudaClassicSrcIoCounters0263 local{};
    int maxY = 0;

    if (!isfinite(x[i]) || !isfinite(y[i]) || !isfinite(vx[i]) || !isfinite(vy[i])) {
        local.failureFlag = 1;
        merge_particle_boundary_counter_0267(counters, local);
        return;
    }

    const double vxSource0493x8v = vx[i];
    const double vySource0493x8v = vy[i];
    const double xpre0493x8q = x[i] - vxSource0493x8v * cfg.dt;
    const double ypre0493x8q = y[i] - vySource0493x8v * cfg.dt;
    accumulate_neumann_bath_moments_0493x8q(
        i, xpre0493x8q, ypre0493x8q, vxSource0493x8v, vySource0493x8v, mass[i],
        cfg, bathMoments0493x8q, bathCellCount0493x8q);

    bool remove = false;
    int removeMode = 0;

    if (cfg.segmentedMultiAxis0414) {
        int yReflections0414 = 0;
        remove = resolve_segmented_multi_axis_crossing_0414(
            xpre0493x8q, ypre0493x8q, x[i], y[i], vx[i], vy[i],
            cfg, local, removeMode, yReflections0414);
        if (yReflections0414 > maxY) maxY = yReflections0414;
    } else {
        int guardX = 0;
        while (x[i] < cfg.xMin || x[i] > cfg.xMax) {
            if (++guardX > 64) { local.failureFlag = 3; break; }
            if (x[i] < cfg.xMin) {
                local.hitsLeft += 1ULL;
                int mode = cfg.leftMode;
                if (cfg.segmentedEnable) {
                    const double sseg = segment_s_device_0263(0, x[i], y[i], cfg);
                    mode = segment_mode_at_device_0263(cfg, 0, sseg);
                }
                if (mode != 0) { remove = true; removeMode = mode; break; }
                x[i] = 2.0 * cfg.xMin - x[i];
                apply_x_wall_reflection_device_0263(cfg.leftWallMode == 0 ? 1 : cfg.leftWallMode, 0.0, 0.0, vx[i], vy[i]);
            } else if (x[i] > cfg.xMax) {
                local.hitsRight += 1ULL;
                int mode = cfg.rightMode;
                if (cfg.segmentedEnable) {
                    const double sseg = segment_s_device_0263(1, x[i], y[i], cfg);
                    mode = segment_mode_at_device_0263(cfg, 1, sseg);
                }
                if (mode != 0) { remove = true; removeMode = mode; break; }
                x[i] = 2.0 * cfg.xMax - x[i];
                apply_x_wall_reflection_device_0263(cfg.rightWallMode == 0 ? 1 : cfg.rightWallMode, 0.0, 0.0, vx[i], vy[i]);
            }
        }

        if (!remove) {
            int guard = 0;
            while (y[i] < cfg.yMin || y[i] > cfg.yMax) {
                if (++guard > 64) { local.failureFlag = 2; break; }
                if (y[i] < cfg.yMin) {
                    local.hitsBottom += 1ULL;
                    int mode = cfg.bottomMode;
                    if (cfg.segmentedEnable) {
                        const double sseg = segment_s_device_0263(2, x[i], y[i], cfg);
                        mode = segment_mode_at_device_0263(cfg, 2, sseg);
                    }
                    if (mode != 0) { remove = true; removeMode = mode; break; }
                    y[i] = 2.0 * cfg.yMin - y[i];
                    apply_y_wall_reflection_device_0263(cfg.bottomWallMode, cfg.wallUxBottom, cfg.wallUyBottom, vx[i], vy[i]);
                } else if (y[i] > cfg.yMax) {
                    local.hitsTop += 1ULL;
                    int mode = cfg.topMode;
                    if (cfg.segmentedEnable) {
                        const double sseg = segment_s_device_0263(3, x[i], y[i], cfg);
                        mode = segment_mode_at_device_0263(cfg, 3, sseg);
                    }
                    if (mode != 0) { remove = true; removeMode = mode; break; }
                    y[i] = 2.0 * cfg.yMax - y[i];
                    apply_y_wall_reflection_device_0263(cfg.topWallMode, cfg.wallUxTop, cfg.wallUyTop, vx[i], vy[i]);
                }
            }
            if (guard > maxY) maxY = guard;
        }

    }

    if (!remove && point_in_inlet_reservoir_device_0263(x[i], y[i], cfg)) {
        local.inletReservoirDeleted += 1ULL;
        remove = true;
    }

    if (!remove) {
        record_neumann_replicas_for_survivor_0493x8v(
            i, xpre0493x8q, ypre0493x8q,
            vxSource0493x8v, vySource0493x8v, cfg,
            replicaCandidates0493x8v, replicaCandidateCount0493x8v,
            replicaCandidateCapacity0493x8v, counters);
    }

    if (remove) {
        x[i] = clamp_device_0263(x[i], cfg.xMin, cfg.xMax);
        y[i] = clamp_device_0263(y[i], cfg.yMin, cfg.yMax);
        role[i] = inactiveRole;
        record_recycled_deleted_slot_0493x9e(
            i, recycleDeletedIndices0493x9e, recycleDeletedCount0493x9e,
            recycleDeletedCapacity0493x9e, counters);
        if (removeMode == 1) local.inletBackflowDeleted += 1ULL;
        else if (removeMode == 2) local.outletParticlesDeleted += 1ULL;
    } else {
        local.fluidParticles += 1ULL;
    }

    local.maxYReflections = maxY;
    merge_particle_boundary_counter_0267(counters, local);
}

__device__ inline void merge_reservoir_insert_counter_0267(CudaClassicSrcIoCounters0263* counters,
                                                            const CudaClassicSrcIoCounters0263& local) {
    counters->inletReservoirCells += local.inletReservoirCells;
    counters->inletReservoirTargetParticles += local.inletReservoirTargetParticles;
    counters->inletParticlesInserted += local.inletParticlesInserted;
    counters->inletMeanUxSum += local.inletMeanUxSum;
    counters->inletMeanUySum += local.inletMeanUySum;
    counters->inletKbtNumerator += local.inletKbtNumerator;
    counters->fluidParticles += local.inletParticlesInserted;
    if (local.overflowFlag != 0) counters->overflowFlag = local.overflowFlag;
    if (local.failureFlag != 0 && counters->failureFlag == 0) counters->failureFlag = local.failureFlag;
}

__global__ void io_fullface_hard_reservoir_insert_kernel_0267(
    std::uint64_t n,
    double* __restrict__ x,
    double* __restrict__ y,
    double* __restrict__ vx,
    double* __restrict__ vy,
    double* __restrict__ mass,
    std::uint32_t* __restrict__ type,
    unsigned char* __restrict__ role,
    unsigned char fluidRole,
    unsigned char inactiveRole,
    CudaClassicSrcIoFullfaceConfig0263 cfg,
    CudaClassicSrcIoCounters0263* counters)
{
    if (blockIdx.x != 0 || threadIdx.x != 0) return;
    CudaClassicSrcIoCounters0263 local{};

    const int nx = cfg.Nx > 0 ? cfg.Nx : 1;
    const int ny = cfg.Ny > 0 ? cfg.Ny : 1;
    const int cellsX = imax_device_0263(1, imin_device_0263(cfg.inletReservoirCells, nx));
    const int cellsY = imax_device_0263(1, imin_device_0263(cfg.inletReservoirCells, ny));
    const double dx = (cfg.xMax - cfg.xMin) / static_cast<double>(nx);
    const double dy = (cfg.yMax - cfg.yMin) / static_cast<double>(ny);
    const int targetN = cfg.inletTargetOccupancy;
    std::uint64_t inactiveCursor = 0ULL;
    std::uint64_t ordinal = 0ULL;
    const double time = static_cast<double>(cfg.step) * cfg.dt;

    if (cfg.segmentedEnable) {
        for (int seg = 0; seg < cfg.segmentCount; ++seg) {
            if (cfg.segmentMode[seg] != 1) continue;
            const int face = cfg.segmentFace[seg];
            if (face == 0) {
                for (int ix = 0; ix < cellsX; ++ix) {
                    for (int iy = 0; iy < ny; ++iy) {
                        const double s0 = static_cast<double>(iy) / static_cast<double>(ny);
                        const double s1 = static_cast<double>(iy + 1) / static_cast<double>(ny);
                        if (inlet_segment_index_for_cell_interval_device_0288(cfg, face, s0, s1) != seg) continue;
                        insert_reservoir_cell_device_0263(n, x, y, vx, vy, mass, type, role,
                                                          fluidRole, inactiveRole, cfg, ix, iy, dx, dy,
                                                          targetN, time, face, seg, inactiveCursor, ordinal, local);
                        if (local.overflowFlag) break;
                    }
                    if (local.overflowFlag) break;
                }
            } else if (face == 1) {
                for (int ix = nx - cellsX; ix < nx; ++ix) {
                    for (int iy = 0; iy < ny; ++iy) {
                        const double s0 = static_cast<double>(iy) / static_cast<double>(ny);
                        const double s1 = static_cast<double>(iy + 1) / static_cast<double>(ny);
                        if (inlet_segment_index_for_cell_interval_device_0288(cfg, face, s0, s1) != seg) continue;
                        insert_reservoir_cell_device_0263(n, x, y, vx, vy, mass, type, role,
                                                          fluidRole, inactiveRole, cfg, ix, iy, dx, dy,
                                                          targetN, time, face, seg, inactiveCursor, ordinal, local);
                        if (local.overflowFlag) break;
                    }
                    if (local.overflowFlag) break;
                }
            } else if (face == 2) {
                for (int iy = 0; iy < cellsY; ++iy) {
                    for (int ix = 0; ix < nx; ++ix) {
                        const double s0 = static_cast<double>(ix) / static_cast<double>(nx);
                        const double s1 = static_cast<double>(ix + 1) / static_cast<double>(nx);
                        if (inlet_segment_index_for_cell_interval_device_0288(cfg, face, s0, s1) != seg) continue;
                        insert_reservoir_cell_device_0263(n, x, y, vx, vy, mass, type, role,
                                                          fluidRole, inactiveRole, cfg, ix, iy, dx, dy,
                                                          targetN, time, face, seg, inactiveCursor, ordinal, local);
                        if (local.overflowFlag) break;
                    }
                    if (local.overflowFlag) break;
                }
            } else if (face == 3) {
                for (int iy = ny - cellsY; iy < ny; ++iy) {
                    for (int ix = 0; ix < nx; ++ix) {
                        const double s0 = static_cast<double>(ix) / static_cast<double>(nx);
                        const double s1 = static_cast<double>(ix + 1) / static_cast<double>(nx);
                        if (inlet_segment_index_for_cell_interval_device_0288(cfg, face, s0, s1) != seg) continue;
                        insert_reservoir_cell_device_0263(n, x, y, vx, vy, mass, type, role,
                                                          fluidRole, inactiveRole, cfg, ix, iy, dx, dy,
                                                          targetN, time, face, seg, inactiveCursor, ordinal, local);
                        if (local.overflowFlag) break;
                    }
                    if (local.overflowFlag) break;
                }
            }
            if (local.overflowFlag) break;
        }
    } else if (cfg.inletFace == 0) {
        for (int ix = 0; ix < cellsX; ++ix) {
            for (int iy = 0; iy < ny; ++iy) {
                insert_reservoir_cell_device_0263(n, x, y, vx, vy, mass, type, role,
                                                  fluidRole, inactiveRole, cfg, ix, iy, dx, dy,
                                                  targetN, time, cfg.inletFace, -1, inactiveCursor, ordinal, local);
                if (local.overflowFlag) break;
            }
            if (local.overflowFlag) break;
        }
    } else if (cfg.inletFace == 1) {
        for (int ix = nx - cellsX; ix < nx; ++ix) {
            for (int iy = 0; iy < ny; ++iy) {
                insert_reservoir_cell_device_0263(n, x, y, vx, vy, mass, type, role,
                                                  fluidRole, inactiveRole, cfg, ix, iy, dx, dy,
                                                  targetN, time, cfg.inletFace, -1, inactiveCursor, ordinal, local);
                if (local.overflowFlag) break;
            }
            if (local.overflowFlag) break;
        }
    } else if (cfg.inletFace == 2) {
        for (int iy = 0; iy < cellsY; ++iy) {
            for (int ix = 0; ix < nx; ++ix) {
                insert_reservoir_cell_device_0263(n, x, y, vx, vy, mass, type, role,
                                                  fluidRole, inactiveRole, cfg, ix, iy, dx, dy,
                                                  targetN, time, cfg.inletFace, -1, inactiveCursor, ordinal, local);
                if (local.overflowFlag) break;
            }
            if (local.overflowFlag) break;
        }
    } else if (cfg.inletFace == 3) {
        for (int iy = ny - cellsY; iy < ny; ++iy) {
            for (int ix = 0; ix < nx; ++ix) {
                insert_reservoir_cell_device_0263(n, x, y, vx, vy, mass, type, role,
                                                  fluidRole, inactiveRole, cfg, ix, iy, dx, dy,
                                                  targetN, time, cfg.inletFace, -1, inactiveCursor, ordinal, local);
                if (local.overflowFlag) break;
            }
            if (local.overflowFlag) break;
        }
    }

    merge_reservoir_insert_counter_0267(counters, local);
}


__global__ void io_fullface_mark_inactive_flags_kernel_0268(
    std::uint64_t n,
    const unsigned char* __restrict__ role,
    unsigned char inactiveRole,
    unsigned int* __restrict__ flags)
{
    const std::uint64_t i = static_cast<std::uint64_t>(blockIdx.x) * static_cast<std::uint64_t>(blockDim.x) +
                            static_cast<std::uint64_t>(threadIdx.x);
    if (i >= n) return;
    flags[i] = (role[i] == inactiveRole) ? 1u : 0u;
}

__global__ void io_fullface_compact_inactive_slots_kernel_0268(
    std::uint64_t n,
    const unsigned char* __restrict__ role,
    unsigned char inactiveRole,
    const unsigned int* __restrict__ prefix,
    std::uint64_t* __restrict__ inactiveIndices)
{
    const std::uint64_t i = static_cast<std::uint64_t>(blockIdx.x) * static_cast<std::uint64_t>(blockDim.x) +
                            static_cast<std::uint64_t>(threadIdx.x);
    if (i >= n) return;
    if (role[i] == inactiveRole) {
        inactiveIndices[prefix[i]] = i;
    }
}

// 0313: bounded inactive-tail pool collector. This avoids the previous
// full-capacity prefix scan over all slots when a large inactive reservoir is
// appended to the particle array. It is a fast path only: when the tail window
// does not contain enough inactive slots, the exact full scan remains the
// fallback.
__global__ void io_collect_tail_inactive_slots_kernel_0313(
    std::uint64_t n,
    std::uint64_t tailScan,
    const unsigned char* __restrict__ role,
    unsigned char inactiveRole,
    std::uint64_t* __restrict__ inactiveIndices,
    unsigned int* __restrict__ inactiveCount)
{
    const std::uint64_t k = static_cast<std::uint64_t>(blockIdx.x) * static_cast<std::uint64_t>(blockDim.x) +
                            static_cast<std::uint64_t>(threadIdx.x);
    if (k >= tailScan || k >= n) return;
    const std::uint64_t i = n - 1u - k;
    if (role[i] == inactiveRole) {
        const unsigned int pos = atomicAdd(inactiveCount, 1u);
        if (pos < tailScan) inactiveIndices[pos] = i;
    }
}

std::uint64_t inactive_tail_scan_count_0313(std::uint64_t n, std::uint64_t need) {
    if (n == 0u) return 0u;
    const std::uint64_t minScan = static_cast<std::uint64_t>(std::max(1, env_int_0263("MPCD_CUDA_INACTIVE_TAIL_POOL_MIN_SCAN_0313", 8192)));
    const std::uint64_t maxScan = static_cast<std::uint64_t>(std::max(1, env_int_0263("MPCD_CUDA_INACTIVE_TAIL_POOL_MAX_SCAN_0313", 262144)));
    const std::uint64_t mult = static_cast<std::uint64_t>(std::max(1, env_int_0263("MPCD_CUDA_INACTIVE_TAIL_POOL_SCAN_MULT_0313", 4)));
    std::uint64_t scan = std::max(minScan, need * mult + 1024u);
    scan = std::min(scan, maxScan);
    scan = std::min(scan, n);
    return scan;
}

// 0493x9d-fix1 persistent workspace for the *exactly sized* 0313 tail scan.
// This is intentionally different from x9d v1: the required tailScan is still
// computed from the real host-visible candidate count.  Only the allocations
// are retained between steps.
struct InactiveTailPoolWorkspace0493x9dFix1 {
    std::uint64_t* indices = nullptr;
    unsigned int* count = nullptr;
    std::uint64_t capacity = 0u;
};

InactiveTailPoolWorkspace0493x9dFix1& inactive_tail_pool_workspace_0493x9d_fix1() {
    static InactiveTailPoolWorkspace0493x9dFix1 w{};
    return w;
}

bool collect_tail_inactive_pool_0313(std::uint64_t n,
                                      unsigned char* dRole,
                                      unsigned char inactiveRole,
                                      std::uint64_t need,
                                      int threads,
                                      std::uint64_t** dInactiveIndicesOut,
                                      unsigned int* inactiveCountOut,
                                      bool* persistentWorkspaceOut = nullptr) {
    if (persistentWorkspaceOut != nullptr) *persistentWorkspaceOut = false;
    const char* enableEnv0313 = std::getenv("MPCD_CUDA_INACTIVE_TAIL_POOL_0313");
    if (enableEnv0313 != nullptr && !env_truthy_0263("MPCD_CUDA_INACTIVE_TAIL_POOL_0313")) return false;
    if (n == 0u || need == 0u || dRole == nullptr || dInactiveIndicesOut == nullptr || inactiveCountOut == nullptr) return false;
    const std::uint64_t tailScan = inactive_tail_scan_count_0313(n, need);
    if (tailScan == 0u || tailScan > static_cast<std::uint64_t>(std::numeric_limits<unsigned int>::max())) return false;

    const bool persistent0493x9dFix1 = neumann_resident_opt_0493x9d_fix1_enabled();
    std::uint64_t* dInactiveIndices = nullptr;
    unsigned int* dInactiveCount = nullptr;
    if (persistent0493x9dFix1) {
        InactiveTailPoolWorkspace0493x9dFix1& w = inactive_tail_pool_workspace_0493x9d_fix1();
        if (w.indices == nullptr || w.capacity < tailScan) {
            if (w.indices != nullptr)
                check_cuda_0263(cudaFree(w.indices),
                                "resize 0493x9d-fix1 inactive tail index pool");
            check_cuda_0263(cudaMalloc(
                &w.indices, sizeof(std::uint64_t) * static_cast<std::size_t>(tailScan)),
                "allocate 0493x9d-fix1 inactive tail index pool");
            w.capacity = tailScan;
        }
        if (w.count == nullptr) {
            check_cuda_0263(cudaMalloc(&w.count, sizeof(unsigned int)),
                            "allocate 0493x9d-fix1 inactive tail count");
        }
        dInactiveIndices = w.indices;
        dInactiveCount = w.count;
    } else {
        check_cuda_0263(cudaMalloc(&dInactiveIndices, sizeof(std::uint64_t) * static_cast<std::size_t>(tailScan)),
                        "allocate 0313 inactive tail index pool");
        check_cuda_0263(cudaMalloc(&dInactiveCount, sizeof(unsigned int)),
                        "allocate 0313 inactive tail count");
    }

    check_cuda_0263(cudaMemset(dInactiveCount, 0, sizeof(unsigned int)),
                    persistent0493x9dFix1
                        ? "clear 0493x9d-fix1 inactive tail count"
                        : "clear 0313 inactive tail count");
    const int block = std::max(32, threads);
    const std::uint64_t blocks64 = (tailScan + static_cast<std::uint64_t>(block) - 1u) / static_cast<std::uint64_t>(block);
    if (blocks64 > static_cast<std::uint64_t>(2147483647)) {
        if (!persistent0493x9dFix1) {
            cudaFree(dInactiveIndices);
            cudaFree(dInactiveCount);
        }
        throw std::runtime_error("cuda_classic_src_io_resident_0263: grid too large for 0313 inactive tail pool launch");
    }
    io_collect_tail_inactive_slots_kernel_0313<<<static_cast<unsigned int>(blocks64), block>>>(
        n, tailScan, dRole, inactiveRole, dInactiveIndices, dInactiveCount);
    check_cuda_0263(cudaGetLastError(), "io_collect_tail_inactive_slots_kernel_0313 launch");
    unsigned int count = 0u;
    check_cuda_0263(cudaMemcpy(&count, dInactiveCount, sizeof(unsigned int), cudaMemcpyDeviceToHost),
                    "copy 0313 inactive tail count");
    if (!persistent0493x9dFix1) cudaFree(dInactiveCount);
    if (count < need && !env_truthy_0263("MPCD_CUDA_INACTIVE_TAIL_POOL_NO_FALLBACK_0313")) {
        if (!persistent0493x9dFix1) cudaFree(dInactiveIndices);
        return false;
    }
    *dInactiveIndicesOut = dInactiveIndices;
    *inactiveCountOut = count;
    if (persistentWorkspaceOut != nullptr) *persistentWorkspaceOut = persistent0493x9dFix1;
    return true;
}

// 0493x9e: build an insertion pool without scanning role[] over the inactive
// tail.  Slots deleted during the boundary pass are recycled first.  Any
// additional slots come from the compact inactive tail starting at oldActive.
// The previous timestep's targeted repair (or exact 0315c fallback) guarantees
// that this tail is inactive; each chosen slot is nevertheless checked on GPU.
__global__ void io_build_recycled_inactive_pool_kernel_0493x9e(
    std::uint64_t need,
    std::uint64_t oldActive,
    std::uint64_t nTotal,
    const unsigned char* __restrict__ role,
    unsigned char inactiveRole,
    const std::uint64_t* __restrict__ deletedIndices,
    const unsigned int* __restrict__ deletedCount,
    std::uint64_t* __restrict__ poolIndices,
    CudaClassicSrcIoCounters0263* counters)
{
    const std::uint64_t j = static_cast<std::uint64_t>(blockIdx.x) *
                            static_cast<std::uint64_t>(blockDim.x) +
                            static_cast<std::uint64_t>(threadIdx.x);
    if (j >= need) return;
    const unsigned int dRaw = deletedCount != nullptr ? *deletedCount : 0u;
    const std::uint64_t dRaw64 = static_cast<std::uint64_t>(dRaw);
    const std::uint64_t d = dRaw64 < need ? dRaw64 : need;
    std::uint64_t slot = nTotal;
    if (j < d) {
        slot = deletedIndices[j];
    } else {
        slot = oldActive + (j - d);
    }
    if (slot >= nTotal || role[slot] != inactiveRole) {
        poolIndices[j] = nTotal;
        atomicMax(&counters->overflowFlag, 32);
        return;
    }
    poolIndices[j] = slot;
}

std::uint64_t* build_recycled_inactive_pool_0493x9e(
    std::uint64_t need,
    std::uint64_t oldActive,
    const CudaParticleDeviceView& view,
    unsigned char inactiveRole,
    CudaClassicSrcIoCounters0263* dCounters,
    int threads)
{
    if (need == 0u) return nullptr;
    if (need > static_cast<std::uint64_t>(std::numeric_limits<unsigned int>::max()))
        throw std::runtime_error("0493x9e recycle-pool need exceeds unsigned int");
    NeumannRecycleWorkspace0493x9e& w = neumann_recycle_workspace_0493x9e();
    std::uint64_t* pool = ensure_neumann_recycle_pool_0493x9e(need);
    const int block = std::max(32, threads);
    const std::uint64_t blocks64 =
        (need + static_cast<std::uint64_t>(block) - 1u) /
        static_cast<std::uint64_t>(block);
    if (blocks64 > static_cast<std::uint64_t>(2147483647))
        throw std::runtime_error("0493x9e recycle-pool launch too large");
    io_build_recycled_inactive_pool_kernel_0493x9e<<<
        static_cast<unsigned int>(blocks64), block>>>(
        need, oldActive, view.n, view.role, inactiveRole,
        w.deletedIndices, w.deletedCount, pool, dCounters);
    check_cuda_0263(cudaGetLastError(),
                    "io_build_recycled_inactive_pool_kernel_0493x9e launch");
    return pool;
}

__device__ inline void io_swap_particle_slots_device_0493x9e_fix3(
    std::uint64_t a, std::uint64_t b,
    double* x, double* y, double* vx, double* vy, double* mass,
    std::uint32_t* type, unsigned char* role)
{
    if (a == b) return;
    double td = x[a]; x[a] = x[b]; x[b] = td;
    td = y[a]; y[a] = y[b]; y[b] = td;
    td = vx[a]; vx[a] = vx[b]; vx[b] = td;
    td = vy[a]; vy[a] = vy[b]; vy[b] = td;
    td = mass[a]; mass[a] = mass[b]; mass[b] = td;
    std::uint32_t tt = type[a]; type[a] = type[b]; type[b] = tt;
    unsigned char tr = role[a]; role[a] = role[b]; role[b] = tr;
}

// 0493x9e-fix3: exact targeted prefix repair on the x9e recycle path.
// The previous step ends compact. New holes can only be recorded deletions or,
// for net growth, gaps in the bounded pool tail. Donors can only live in the
// same bounded tail. Lowest holes are paired with highest donors, matching the
// ordering of the exact 0315c swap repair. Large atypical work falls back.
__global__ void io_targeted_prefix_repair_kernel_0493x9e_fix3(
    std::uint64_t nTotal, std::uint64_t oldActive, std::uint64_t expectedActive,
    std::uint64_t repairUpper, const std::uint64_t* __restrict__ deletedIndices,
    const unsigned int* __restrict__ deletedCountDevice,
    std::uint64_t expectedDeletedCount, unsigned long long maxWork,
    double* x, double* y, double* vx, double* vy, double* mass,
    std::uint32_t* type, unsigned char* role, unsigned char fluidRole,
    int* status)
{
    if (blockIdx.x != 0 || threadIdx.x != 0 || status == nullptr) return;
    *status = 0;
    if (expectedActive > nTotal || oldActive > nTotal || repairUpper > nTotal ||
        repairUpper < expectedActive || deletedIndices == nullptr ||
        deletedCountDevice == nullptr) {
        *status = 2; return;
    }
    const std::uint64_t deletedCount = static_cast<std::uint64_t>(*deletedCountDevice);
    if (deletedCount != expectedDeletedCount) { *status = 10; return; }
    if (deletedCount > oldActive) { *status = 3; return; }

    const std::uint64_t oldPrefixLimit = expectedActive < oldActive ? expectedActive : oldActive;
    unsigned long long holes = 0ULL;
    for (std::uint64_t j = 0; j < deletedCount; ++j) {
        const std::uint64_t s = deletedIndices[j];
        if (s >= oldActive) { *status = 4; return; }
        if (s < oldPrefixLimit && role[s] != fluidRole) ++holes;
    }
    if (expectedActive > oldActive) {
        for (std::uint64_t s = oldActive; s < expectedActive; ++s)
            if (role[s] != fluidRole) ++holes;
    }
    unsigned long long donors = 0ULL;
    for (std::uint64_t s = expectedActive; s < repairUpper; ++s)
        if (role[s] == fluidRole) ++donors;

    const unsigned long long searchWidth = static_cast<unsigned long long>(deletedCount) +
        static_cast<unsigned long long>(expectedActive > oldActive ? expectedActive - oldActive : 0u);
    const unsigned long long work = holes > 0ULL && searchWidth > 0ULL && holes > (~0ULL / searchWidth)
        ? ~0ULL : holes * searchWidth;
    if (holes != donors) { *status = 6; return; }
    if (work > maxWork) { *status = 5; return; }

    std::uint64_t donorCursor = repairUpper;
    for (;;) {
        std::uint64_t minHole = expectedActive;
        for (std::uint64_t j = 0; j < deletedCount; ++j) {
            const std::uint64_t s = deletedIndices[j];
            if (s < oldPrefixLimit && role[s] != fluidRole && s < minHole) minHole = s;
        }
        if (expectedActive > oldActive && minHole == expectedActive) {
            for (std::uint64_t s = oldActive; s < expectedActive; ++s) {
                if (role[s] != fluidRole) { minHole = s; break; }
            }
        }
        if (minHole == expectedActive) break;
        bool foundDonor = false;
        while (donorCursor > expectedActive) {
            --donorCursor;
            if (role[donorCursor] == fluidRole) { foundDonor = true; break; }
        }
        if (!foundDonor) { *status = 7; return; }
        io_swap_particle_slots_device_0493x9e_fix3(
            minHole, donorCursor, x, y, vx, vy, mass, type, role);
    }

    // Production correctness check over the only regions this step could have
    // changed.  This is intentionally retained: it is O(mutation support), not
    // the removed O(Nactive) qualification oracle.
    for (std::uint64_t j = 0; j < deletedCount; ++j) {
        const std::uint64_t s = deletedIndices[j];
        if (s < oldPrefixLimit && role[s] != fluidRole) { *status = 8; return; }
    }
    if (expectedActive > oldActive) {
        for (std::uint64_t s = oldActive; s < expectedActive; ++s) {
            if (role[s] != fluidRole) { *status = 8; return; }
        }
    }
    for (std::uint64_t s = expectedActive; s < repairUpper; ++s) {
        if (role[s] == fluidRole) { *status = 9; return; }
    }
    *status = 1;
}

bool try_targeted_prefix_repair_0493x9e_fix3(
    CudaParticleState& gpuState, ParticleState& state,
    std::uint64_t oldActive, std::uint64_t expectedActive,
    std::uint64_t recyclePoolNeed, std::uint64_t expectedDeleted,
    CudaParticleStateDiagnostics& diag, int& hostStatus)
{
    CudaParticleDeviceView view = gpuState.device_view();
    NeumannRecycleWorkspace0493x9e& w = neumann_recycle_workspace_0493x9e();
    hostStatus = 0;
    if (w.targetedRepairStatus0493x9eFix3 == nullptr || w.deletedIndices == nullptr ||
        w.deletedCount == nullptr) return false;
    if (recyclePoolNeed == 0u) return false;
    if (expectedActive > view.n || oldActive > view.n || expectedDeleted > oldActive) return false;
    const std::uint64_t recycledHead = std::min<std::uint64_t>(expectedDeleted, recyclePoolNeed);
    const std::uint64_t tailExtent = recyclePoolNeed - recycledHead;
    if (tailExtent > view.n - oldActive) return false;
    const std::uint64_t repairUpper = oldActive + tailExtent;
    if (expectedActive > repairUpper) return false;
    static const unsigned long long maxWork = static_cast<unsigned long long>(std::max(
        1000, env_int_0263("MPCD_CUDA_OPEN_BOUNDARY_NEUMANN_TARGETED_REPAIR_MAX_WORK_0493X9E_FIX3", 4000000)));
    const auto t0 = Clock::now();
    io_targeted_prefix_repair_kernel_0493x9e_fix3<<<1, 1>>>(
        view.n, oldActive, expectedActive, repairUpper, w.deletedIndices,
        w.deletedCount, expectedDeleted, maxWork,
        view.x, view.y, view.vx, view.vy, view.mass,
        view.type, view.role, kParticleRoleFluid, w.targetedRepairStatus0493x9eFix3);
    check_cuda_0263(cudaGetLastError(), "io_targeted_prefix_repair_kernel_0493x9e_fix3 launch");
    check_cuda_0263(cudaMemcpy(&hostStatus, w.targetedRepairStatus0493x9eFix3,
                              sizeof(hostStatus), cudaMemcpyDeviceToHost),
                    "copy 0493x9e-fix3 targeted-repair status");
    if (hostStatus != 1) return false;

    gpuState.set_active_fluid_size(expectedActive);
    state.NactiveFluid = expectedActive;
    diag.kernelSeconds += elapsed_0263(t0, Clock::now());
    diag.particles = expectedActive; diag.capacity = view.capacity;
    return true;
}

// 0315c: device-side active-fluid prefix repair used after inlet/outlet
// mutations. It replaces the 0315b-fix02 host roundtrip. 0315c-fix04 counts
// the actual Fluid roles on-device after all mutations, then applies a
// swap-tail compaction equivalent to compact_active_fluid_prefix(). This avoids
// trusting inlet/outlet counters for the active-size invariant.
struct ActivePrefixTemp0315c {
    double* x = nullptr;
    double* y = nullptr;
    double* vx = nullptr;
    double* vy = nullptr;
    double* mass = nullptr;
    std::uint32_t* type = nullptr;
    std::uint64_t n = 0u;
};

void free_active_prefix_temp_0315c(ActivePrefixTemp0315c& t) {
    if (t.x != nullptr) cudaFree(t.x);
    if (t.y != nullptr) cudaFree(t.y);
    if (t.vx != nullptr) cudaFree(t.vx);
    if (t.vy != nullptr) cudaFree(t.vy);
    if (t.mass != nullptr) cudaFree(t.mass);
    if (t.type != nullptr) cudaFree(t.type);
    t = {};
}

void allocate_active_prefix_temp_0315c(ActivePrefixTemp0315c& t, std::uint64_t n) {
    t.n = n;
    if (n == 0u) return;
    const std::size_t nn = static_cast<std::size_t>(n);
    if (static_cast<std::uint64_t>(nn) != n) {
        throw std::runtime_error("cuda_classic_src_io_resident_0263: 0315c active prefix temp size does not fit size_t");
    }
    check_cuda_0263(cudaMalloc(&t.x, nn * sizeof(double)), "allocate 0315c temp x");
    check_cuda_0263(cudaMalloc(&t.y, nn * sizeof(double)), "allocate 0315c temp y");
    check_cuda_0263(cudaMalloc(&t.vx, nn * sizeof(double)), "allocate 0315c temp vx");
    check_cuda_0263(cudaMalloc(&t.vy, nn * sizeof(double)), "allocate 0315c temp vy");
    check_cuda_0263(cudaMalloc(&t.mass, nn * sizeof(double)), "allocate 0315c temp mass");
    check_cuda_0263(cudaMalloc(&t.type, nn * sizeof(std::uint32_t)), "allocate 0315c temp type");
}

__global__ void io_mark_fluid_flags_kernel_0315c(
    std::uint64_t n,
    const unsigned char* __restrict__ role,
    unsigned char fluidRole,
    unsigned int* __restrict__ flags)
{
    const std::uint64_t i = static_cast<std::uint64_t>(blockIdx.x) * static_cast<std::uint64_t>(blockDim.x) +
                            static_cast<std::uint64_t>(threadIdx.x);
    if (i >= n) return;
    flags[i] = (role[i] == fluidRole) ? 1u : 0u;
}

__global__ void io_mark_tail_fluid_flags_kernel_0315c(
    std::uint64_t n,
    std::uint64_t tailScan,
    const unsigned char* __restrict__ role,
    unsigned char fluidRole,
    unsigned int* __restrict__ flags)
{
    const std::uint64_t k = static_cast<std::uint64_t>(blockIdx.x) * static_cast<std::uint64_t>(blockDim.x) +
                            static_cast<std::uint64_t>(threadIdx.x);
    if (k >= tailScan || k >= n) return;
    const std::uint64_t start = n - tailScan;
    const std::uint64_t i = start + k;
    flags[k] = (role[i] == fluidRole) ? 1u : 0u;
}

__global__ void io_scatter_fluid_range_to_temp_kernel_0315c(
    std::uint64_t n,
    std::uint64_t srcOffset,
    std::uint64_t dstOffset,
    const double* __restrict__ x,
    const double* __restrict__ y,
    const double* __restrict__ vx,
    const double* __restrict__ vy,
    const double* __restrict__ mass,
    const std::uint32_t* __restrict__ type,
    const unsigned char* __restrict__ role,
    unsigned char fluidRole,
    const unsigned int* __restrict__ flags,
    const unsigned int* __restrict__ prefix,
    double* __restrict__ tx,
    double* __restrict__ ty,
    double* __restrict__ tvx,
    double* __restrict__ tvy,
    double* __restrict__ tmass,
    std::uint32_t* __restrict__ ttype)
{
    const std::uint64_t k = static_cast<std::uint64_t>(blockIdx.x) * static_cast<std::uint64_t>(blockDim.x) +
                            static_cast<std::uint64_t>(threadIdx.x);
    if (k >= n) return;
    if (flags[k] == 0u) return;
    const std::uint64_t src = srcOffset + k;
    if (role[src] != fluidRole) return;
    const std::uint64_t dst = dstOffset + static_cast<std::uint64_t>(prefix[k]);
    tx[dst] = x[src];
    ty[dst] = y[src];
    tvx[dst] = vx[src];
    tvy[dst] = vy[src];
    tmass[dst] = mass[src];
    ttype[dst] = type[src];
}

__global__ void io_copy_temp_to_prefix_kernel_0315c(
    std::uint64_t n,
    double* __restrict__ x,
    double* __restrict__ y,
    double* __restrict__ vx,
    double* __restrict__ vy,
    double* __restrict__ mass,
    std::uint32_t* __restrict__ type,
    unsigned char* __restrict__ role,
    unsigned char fluidRole,
    const double* __restrict__ tx,
    const double* __restrict__ ty,
    const double* __restrict__ tvx,
    const double* __restrict__ tvy,
    const double* __restrict__ tmass,
    const std::uint32_t* __restrict__ ttype)
{
    const std::uint64_t i = static_cast<std::uint64_t>(blockIdx.x) * static_cast<std::uint64_t>(blockDim.x) +
                            static_cast<std::uint64_t>(threadIdx.x);
    if (i >= n) return;
    x[i] = tx[i];
    y[i] = ty[i];
    vx[i] = tvx[i];
    vy[i] = tvy[i];
    mass[i] = tmass[i];
    type[i] = ttype[i];
    role[i] = fluidRole;
}

__global__ void io_set_role_range_kernel_0315c(
    std::uint64_t start,
    std::uint64_t n,
    unsigned char* __restrict__ role,
    unsigned char value)
{
    const std::uint64_t k = static_cast<std::uint64_t>(blockIdx.x) * static_cast<std::uint64_t>(blockDim.x) +
                            static_cast<std::uint64_t>(threadIdx.x);
    if (k >= n) return;
    role[start + k] = value;
}

unsigned int copy_scan_count_0315c(unsigned int* dFlags, unsigned int* dPrefix, std::uint64_t n, const char* context) {
    if (n == 0u) return 0u;
    unsigned int lastFlag = 0u;
    unsigned int lastPrefix = 0u;
    check_cuda_0263(cudaMemcpy(&lastFlag, dFlags + (n - 1u), sizeof(unsigned int), cudaMemcpyDeviceToHost), context);
    check_cuda_0263(cudaMemcpy(&lastPrefix, dPrefix + (n - 1u), sizeof(unsigned int), cudaMemcpyDeviceToHost), context);
    return lastPrefix + lastFlag;
}

void launch_set_role_range_0315c(std::uint64_t start,
                                 std::uint64_t n,
                                 unsigned char* role,
                                 unsigned char value,
                                 int threads,
                                 const char* context) {
    if (n == 0u) return;
    const std::uint64_t blocks64 = (n + static_cast<std::uint64_t>(threads) - 1u) / static_cast<std::uint64_t>(threads);
    if (blocks64 > static_cast<std::uint64_t>(2147483647)) {
        throw std::runtime_error("cuda_classic_src_io_resident_0263: grid too large for 0315c role cleanup");
    }
    io_set_role_range_kernel_0315c<<<static_cast<unsigned int>(blocks64), threads>>>(start, n, role, value);
    check_cuda_0263(cudaGetLastError(), context);
}


__global__ void io_mark_prefix_hole_flags_kernel_0315c(
    std::uint64_t nPrefix,
    const unsigned char* __restrict__ role,
    unsigned char fluidRole,
    unsigned int* __restrict__ flags)
{
    const std::uint64_t i = static_cast<std::uint64_t>(blockIdx.x) * static_cast<std::uint64_t>(blockDim.x) +
                            static_cast<std::uint64_t>(threadIdx.x);
    if (i >= nPrefix) return;
    flags[i] = (role[i] == fluidRole) ? 0u : 1u;
}

__global__ void io_mark_tail_fluid_reverse_flags_kernel_0315c(
    std::uint64_t nTotal,
    std::uint64_t nActive,
    const unsigned char* __restrict__ role,
    unsigned char fluidRole,
    unsigned int* __restrict__ flags)
{
    const std::uint64_t tailN = nTotal - nActive;
    const std::uint64_t k = static_cast<std::uint64_t>(blockIdx.x) * static_cast<std::uint64_t>(blockDim.x) +
                            static_cast<std::uint64_t>(threadIdx.x);
    if (k >= tailN) return;
    const std::uint64_t idx = nTotal - 1u - k;
    flags[k] = (role[idx] == fluidRole) ? 1u : 0u;
}

__global__ void io_collect_prefix_holes_kernel_0315c(
    std::uint64_t nPrefix,
    const unsigned char* __restrict__ role,
    unsigned char fluidRole,
    const unsigned int* __restrict__ flags,
    const unsigned int* __restrict__ prefix,
    std::uint64_t* __restrict__ holeIndices)
{
    const std::uint64_t i = static_cast<std::uint64_t>(blockIdx.x) * static_cast<std::uint64_t>(blockDim.x) +
                            static_cast<std::uint64_t>(threadIdx.x);
    if (i >= nPrefix) return;
    if (flags[i] == 0u) return;
    if (role[i] == fluidRole) return;
    holeIndices[static_cast<std::uint64_t>(prefix[i])] = i;
}

__global__ void io_collect_tail_donors_reverse_kernel_0315c(
    std::uint64_t nTotal,
    std::uint64_t nActive,
    const unsigned char* __restrict__ role,
    unsigned char fluidRole,
    const unsigned int* __restrict__ flags,
    const unsigned int* __restrict__ prefix,
    std::uint64_t* __restrict__ donorIndices)
{
    const std::uint64_t tailN = nTotal - nActive;
    const std::uint64_t k = static_cast<std::uint64_t>(blockIdx.x) * static_cast<std::uint64_t>(blockDim.x) +
                            static_cast<std::uint64_t>(threadIdx.x);
    if (k >= tailN) return;
    if (flags[k] == 0u) return;
    const std::uint64_t idx = nTotal - 1u - k;
    if (role[idx] != fluidRole) return;
    donorIndices[static_cast<std::uint64_t>(prefix[k])] = idx;
}

__global__ void io_mark_tail_fluid_reverse_flags_kernel_0315k(
    std::uint64_t nTotal,
    std::uint64_t tailScan,
    const unsigned char* __restrict__ role,
    unsigned char fluidRole,
    unsigned int* __restrict__ flags)
{
    const std::uint64_t k = static_cast<std::uint64_t>(blockIdx.x) * static_cast<std::uint64_t>(blockDim.x) +
                            static_cast<std::uint64_t>(threadIdx.x);
    if (k >= tailScan || k >= nTotal) return;
    const std::uint64_t idx = nTotal - 1u - k;
    flags[k] = (role[idx] == fluidRole) ? 1u : 0u;
}

__global__ void io_collect_tail_donors_bounded_reverse_kernel_0315k(
    std::uint64_t nTotal,
    std::uint64_t tailScan,
    const unsigned char* __restrict__ role,
    unsigned char fluidRole,
    const unsigned int* __restrict__ flags,
    const unsigned int* __restrict__ prefix,
    std::uint64_t* __restrict__ donorIndices)
{
    const std::uint64_t k = static_cast<std::uint64_t>(blockIdx.x) * static_cast<std::uint64_t>(blockDim.x) +
                            static_cast<std::uint64_t>(threadIdx.x);
    if (k >= tailScan || k >= nTotal) return;
    if (flags[k] == 0u) return;
    const std::uint64_t idx = nTotal - 1u - k;
    if (role[idx] != fluidRole) return;
    donorIndices[static_cast<std::uint64_t>(prefix[k])] = idx;
}


__global__ void io_swap_particle_pairs_kernel_0315c(
    std::uint64_t nPairs,
    const std::uint64_t* __restrict__ holeIndices,
    const std::uint64_t* __restrict__ donorIndices,
    double* __restrict__ x,
    double* __restrict__ y,
    double* __restrict__ vx,
    double* __restrict__ vy,
    double* __restrict__ mass,
    std::uint32_t* __restrict__ type,
    unsigned char* __restrict__ role)
{
    const std::uint64_t k = static_cast<std::uint64_t>(blockIdx.x) * static_cast<std::uint64_t>(blockDim.x) +
                            static_cast<std::uint64_t>(threadIdx.x);
    if (k >= nPairs) return;
    const std::uint64_t a = holeIndices[k];
    const std::uint64_t b = donorIndices[k];
    if (a == b) return;

    double td = x[a]; x[a] = x[b]; x[b] = td;
    td = y[a]; y[a] = y[b]; y[b] = td;
    td = vx[a]; vx[a] = vx[b]; vx[b] = td;
    td = vy[a]; vy[a] = vy[b]; vy[b] = td;
    td = mass[a]; mass[a] = mass[b]; mass[b] = td;

    std::uint32_t tt = type[a]; type[a] = type[b]; type[b] = tt;
    unsigned char tr = role[a]; role[a] = role[b]; role[b] = tr;
}

bool try_compact_active_prefix_bounded_0315k(CudaParticleState& gpuState,
                                             ParticleState& state,
                                             const std::uint64_t expectedActive,
                                             const std::uint64_t tailScanHint,
                                             const int threads,
                                             CudaParticleStateDiagnostics& diag,
                                             std::uint64_t& actualActiveOut)
{
    if (env_truthy_0263("MPCD_CUDA_ACTIVE_PREFIX_COMPACT_FULLSCAN_0315K") ||
        env_truthy_0263("MPCD_CUDA_ACTIVE_PREFIX_COMPACT_FULLSCAN_0315C")) {
        return false;
    }
    CudaParticleDeviceView view = gpuState.device_view();
    if (view.n == 0u) {
        actualActiveOut = 0u;
        return true;
    }
    if (expectedActive > view.n) return false;
    const std::uint64_t tailScan = std::min<std::uint64_t>(tailScanHint, view.n - expectedActive);
    if (tailScan == 0u) return false;
    if (expectedActive > static_cast<std::uint64_t>(std::numeric_limits<unsigned int>::max()) ||
        tailScan > static_cast<std::uint64_t>(std::numeric_limits<unsigned int>::max())) {
        return false;
    }

    const auto t0 = Clock::now();
    unsigned int* dHoleFlags = nullptr;
    unsigned int* dHoleScan = nullptr;
    unsigned int* dDonorFlags = nullptr;
    unsigned int* dDonorScan = nullptr;
    std::uint64_t* dHoleIndices = nullptr;
    std::uint64_t* dDonorIndices = nullptr;
    auto cleanup = [&]() {
        if (dHoleFlags != nullptr) cudaFree(dHoleFlags);
        if (dHoleScan != nullptr) cudaFree(dHoleScan);
        if (dDonorFlags != nullptr) cudaFree(dDonorFlags);
        if (dDonorScan != nullptr) cudaFree(dDonorScan);
        if (dHoleIndices != nullptr) cudaFree(dHoleIndices);
        if (dDonorIndices != nullptr) cudaFree(dDonorIndices);
    };

    try {
        unsigned int holeCount = 0u;
        if (expectedActive > 0u) {
            check_cuda_0263(cudaMalloc(&dHoleFlags, sizeof(unsigned int) * static_cast<std::size_t>(expectedActive)),
                            "allocate 0315k bounded hole flags");
            check_cuda_0263(cudaMalloc(&dHoleScan, sizeof(unsigned int) * static_cast<std::size_t>(expectedActive)),
                            "allocate 0315k bounded hole scan");
            const std::uint64_t blocks64 = (expectedActive + static_cast<std::uint64_t>(threads) - 1u) /
                                           static_cast<std::uint64_t>(threads);
            if (blocks64 > static_cast<std::uint64_t>(2147483647)) { cleanup(); return false; }
            io_mark_prefix_hole_flags_kernel_0315c<<<static_cast<unsigned int>(blocks64), threads>>>(
                expectedActive, view.role, kParticleRoleFluid, dHoleFlags);
            check_cuda_0263(cudaGetLastError(), "0315k bounded hole flag launch");
            thrust::exclusive_scan(thrust::device, dHoleFlags, dHoleFlags + expectedActive, dHoleScan);
            check_cuda_0263(cudaGetLastError(), "0315k bounded hole scan");
            holeCount = copy_scan_count_0315c(dHoleFlags, dHoleScan, expectedActive,
                                              "copy 0315k bounded hole count");
        }

        unsigned int donorCount = 0u;
        check_cuda_0263(cudaMalloc(&dDonorFlags, sizeof(unsigned int) * static_cast<std::size_t>(tailScan)),
                        "allocate 0315k bounded donor flags");
        check_cuda_0263(cudaMalloc(&dDonorScan, sizeof(unsigned int) * static_cast<std::size_t>(tailScan)),
                        "allocate 0315k bounded donor scan");
        const std::uint64_t donorBlocks64 = (tailScan + static_cast<std::uint64_t>(threads) - 1u) /
                                            static_cast<std::uint64_t>(threads);
        if (donorBlocks64 > static_cast<std::uint64_t>(2147483647)) { cleanup(); return false; }
        io_mark_tail_fluid_reverse_flags_kernel_0315k<<<static_cast<unsigned int>(donorBlocks64), threads>>>(
            view.n, tailScan, view.role, kParticleRoleFluid, dDonorFlags);
        check_cuda_0263(cudaGetLastError(), "0315k bounded donor flag launch");
        thrust::exclusive_scan(thrust::device, dDonorFlags, dDonorFlags + tailScan, dDonorScan);
        check_cuda_0263(cudaGetLastError(), "0315k bounded donor scan");
        donorCount = copy_scan_count_0315c(dDonorFlags, dDonorScan, tailScan,
                                           "copy 0315k bounded donor count");

        if (holeCount != donorCount) {
            cleanup();
            return false;
        }

        if (holeCount > 0u) {
            const std::uint64_t nPairs = static_cast<std::uint64_t>(holeCount);
            check_cuda_0263(cudaMalloc(&dHoleIndices, sizeof(std::uint64_t) * static_cast<std::size_t>(nPairs)),
                            "allocate 0315k bounded hole indices");
            check_cuda_0263(cudaMalloc(&dDonorIndices, sizeof(std::uint64_t) * static_cast<std::size_t>(nPairs)),
                            "allocate 0315k bounded donor indices");
            const std::uint64_t holeBlocks64 = (expectedActive + static_cast<std::uint64_t>(threads) - 1u) /
                                               static_cast<std::uint64_t>(threads);
            io_collect_prefix_holes_kernel_0315c<<<static_cast<unsigned int>(holeBlocks64), threads>>>(
                expectedActive, view.role, kParticleRoleFluid, dHoleFlags, dHoleScan, dHoleIndices);
            check_cuda_0263(cudaGetLastError(), "0315k bounded collect holes launch");
            io_collect_tail_donors_bounded_reverse_kernel_0315k<<<static_cast<unsigned int>(donorBlocks64), threads>>>(
                view.n, tailScan, view.role, kParticleRoleFluid, dDonorFlags, dDonorScan, dDonorIndices);
            check_cuda_0263(cudaGetLastError(), "0315k bounded collect donors launch");
            const std::uint64_t swapBlocks64 = (nPairs + static_cast<std::uint64_t>(threads) - 1u) /
                                               static_cast<std::uint64_t>(threads);
            if (swapBlocks64 > static_cast<std::uint64_t>(2147483647)) { cleanup(); return false; }
            io_swap_particle_pairs_kernel_0315c<<<static_cast<unsigned int>(swapBlocks64), threads>>>(
                nPairs, dHoleIndices, dDonorIndices,
                view.x, view.y, view.vx, view.vy, view.mass, view.type, view.role);
            check_cuda_0263(cudaGetLastError(), "0315k bounded swaps launch");
        }

        check_cuda_0263(cudaDeviceSynchronize(), "0315k bounded active-prefix compaction synchronize");
        gpuState.set_active_fluid_size(expectedActive);
        state.NactiveFluid = expectedActive;
        actualActiveOut = expectedActive;
        cleanup();
        diag.kernelSeconds += elapsed_0263(t0, Clock::now());
        diag.particles = expectedActive;
        diag.capacity = view.capacity;
        return true;
    } catch (...) {
        cleanup();
        throw;
    }
}

std::uint64_t compact_active_prefix_device_0315c(CudaParticleState& gpuState,
                                                 ParticleState& state,
                                                 const std::uint64_t oldActive,
                                                 const std::uint64_t expectedActive,
                                                 const std::uint64_t tailScanHint,
                                                 CudaParticleStateDiagnostics& diag)
{
    (void)oldActive;
    (void)tailScanHint;

    CudaParticleDeviceView view = gpuState.device_view();
    if (view.n == 0u) {
        state.NactiveFluid = 0u;
        gpuState.set_active_fluid_size(0u);
        return 0u;
    }
    if (expectedActive > view.n) {
        throw std::runtime_error("cuda_classic_src_io_resident_0263: invalid 0315c active-prefix bounds");
    }

    const auto t0 = Clock::now();
    const int threads = std::max(32, env_int_0263("MPCD_CUDA_ACTIVE_PREFIX_COMPACT_THREADS_0315C", 256));

    // 0315k: in the hard-inlet resident path, inserted particles are allocated
    // from a bounded tail pool.  The exact 0315c-fix04 repair scanned role[] over
    // the full storage capacity to recompute actualActive and find donors, which
    // made box/step runtime scale with inactive slots.  Try the bounded repair
    // first; if the step is deletion-only or otherwise outside that invariant,
    // fall back to the exact full scan below.
    std::uint64_t boundedActual0315k = 0u;
    if (try_compact_active_prefix_bounded_0315k(gpuState, state, expectedActive,
                                                tailScanHint, threads, diag, boundedActual0315k)) {
        return boundedActual0315k;
    }

    if (view.n > static_cast<std::uint64_t>(std::numeric_limits<unsigned int>::max())) {
        throw std::runtime_error("cuda_classic_src_io_resident_0263: 0315c exact swap scan range exceeds uint capacity");
    }

    unsigned int* dAllFluidFlags = nullptr;
    unsigned int* dAllFluidScan = nullptr;
    unsigned int* dHoleFlags = nullptr;
    unsigned int* dHoleScan = nullptr;
    unsigned int* dDonorFlags = nullptr;
    unsigned int* dDonorScan = nullptr;
    std::uint64_t* dHoleIndices = nullptr;
    std::uint64_t* dDonorIndices = nullptr;

    auto cleanup = [&]() {
        if (dAllFluidFlags != nullptr) cudaFree(dAllFluidFlags);
        if (dAllFluidScan != nullptr) cudaFree(dAllFluidScan);
        if (dHoleFlags != nullptr) cudaFree(dHoleFlags);
        if (dHoleScan != nullptr) cudaFree(dHoleScan);
        if (dDonorFlags != nullptr) cudaFree(dDonorFlags);
        if (dDonorScan != nullptr) cudaFree(dDonorScan);
        if (dHoleIndices != nullptr) cudaFree(dHoleIndices);
        if (dDonorIndices != nullptr) cudaFree(dDonorIndices);
    };

    try {
        check_cuda_0263(cudaMalloc(&dAllFluidFlags, sizeof(unsigned int) * static_cast<std::size_t>(view.n)),
                        "allocate 0315c-fix04 all-fluid flags");
        check_cuda_0263(cudaMalloc(&dAllFluidScan, sizeof(unsigned int) * static_cast<std::size_t>(view.n)),
                        "allocate 0315c-fix04 all-fluid scan");
        const std::uint64_t allBlocks64 = (view.n + static_cast<std::uint64_t>(threads) - 1u) /
                                          static_cast<std::uint64_t>(threads);
        if (allBlocks64 > static_cast<std::uint64_t>(2147483647)) {
            throw std::runtime_error("cuda_classic_src_io_resident_0263: grid too large for 0315c-fix04 active count");
        }
        io_mark_fluid_flags_kernel_0315c<<<static_cast<unsigned int>(allBlocks64), threads>>>(
            view.n, view.role, kParticleRoleFluid, dAllFluidFlags);
        check_cuda_0263(cudaGetLastError(), "io_mark_fluid_flags_kernel_0315c active-count launch");
        thrust::exclusive_scan(thrust::device, dAllFluidFlags, dAllFluidFlags + view.n, dAllFluidScan);
        check_cuda_0263(cudaGetLastError(), "0315c-fix04 all-fluid exclusive scan");
        const unsigned int actualActive32 = copy_scan_count_0315c(dAllFluidFlags, dAllFluidScan, view.n,
                                                                  "copy 0315c-fix04 active count");
        const std::uint64_t actualActive = static_cast<std::uint64_t>(actualActive32);
        if (env_truthy_0263("MPCD_CUDA_ACTIVE_PREFIX_STRICT_EXPECTED_0315C") && actualActive != expectedActive) {
            throw std::runtime_error("cuda_classic_src_io_resident_0263: 0315c-fix04 actual active count differs from inlet/outlet counter prediction");
        }

        unsigned int holeCount = 0u;
        if (actualActive > 0u) {
            check_cuda_0263(cudaMalloc(&dHoleFlags, sizeof(unsigned int) * static_cast<std::size_t>(actualActive)),
                            "allocate 0315c exact hole flags");
            check_cuda_0263(cudaMalloc(&dHoleScan, sizeof(unsigned int) * static_cast<std::size_t>(actualActive)),
                            "allocate 0315c exact hole scan");
            const std::uint64_t blocks64 = (actualActive + static_cast<std::uint64_t>(threads) - 1u) /
                                           static_cast<std::uint64_t>(threads);
            if (blocks64 > static_cast<std::uint64_t>(2147483647)) {
                throw std::runtime_error("cuda_classic_src_io_resident_0263: grid too large for 0315c exact holes");
            }
            io_mark_prefix_hole_flags_kernel_0315c<<<static_cast<unsigned int>(blocks64), threads>>>(
                actualActive, view.role, kParticleRoleFluid, dHoleFlags);
            check_cuda_0263(cudaGetLastError(), "io_mark_prefix_hole_flags_kernel_0315c launch");
            thrust::exclusive_scan(thrust::device, dHoleFlags, dHoleFlags + actualActive, dHoleScan);
            check_cuda_0263(cudaGetLastError(), "0315c exact hole exclusive scan");
            holeCount = copy_scan_count_0315c(dHoleFlags, dHoleScan, actualActive,
                                              "copy 0315c exact hole scan count");
        }

        const std::uint64_t tailN = view.n - actualActive;
        unsigned int donorCount = 0u;
        if (tailN > 0u) {
            check_cuda_0263(cudaMalloc(&dDonorFlags, sizeof(unsigned int) * static_cast<std::size_t>(tailN)),
                            "allocate 0315c exact donor flags");
            check_cuda_0263(cudaMalloc(&dDonorScan, sizeof(unsigned int) * static_cast<std::size_t>(tailN)),
                            "allocate 0315c exact donor scan");
            const std::uint64_t blocks64 = (tailN + static_cast<std::uint64_t>(threads) - 1u) /
                                           static_cast<std::uint64_t>(threads);
            if (blocks64 > static_cast<std::uint64_t>(2147483647)) {
                throw std::runtime_error("cuda_classic_src_io_resident_0263: grid too large for 0315c exact donors");
            }
            io_mark_tail_fluid_reverse_flags_kernel_0315c<<<static_cast<unsigned int>(blocks64), threads>>>(
                view.n, actualActive, view.role, kParticleRoleFluid, dDonorFlags);
            check_cuda_0263(cudaGetLastError(), "io_mark_tail_fluid_reverse_flags_kernel_0315c launch");
            thrust::exclusive_scan(thrust::device, dDonorFlags, dDonorFlags + tailN, dDonorScan);
            check_cuda_0263(cudaGetLastError(), "0315c exact donor exclusive scan");
            donorCount = copy_scan_count_0315c(dDonorFlags, dDonorScan, tailN,
                                               "copy 0315c exact donor scan count");
        }

        if (holeCount != donorCount) {
            throw std::runtime_error("cuda_classic_src_io_resident_0263: 0315c exact swap compaction count mismatch");
        }

        if (holeCount > 0u) {
            const std::uint64_t nPairs = static_cast<std::uint64_t>(holeCount);
            check_cuda_0263(cudaMalloc(&dHoleIndices, sizeof(std::uint64_t) * static_cast<std::size_t>(nPairs)),
                            "allocate 0315c exact hole indices");
            check_cuda_0263(cudaMalloc(&dDonorIndices, sizeof(std::uint64_t) * static_cast<std::size_t>(nPairs)),
                            "allocate 0315c exact donor indices");

            const std::uint64_t holeBlocks64 = (actualActive + static_cast<std::uint64_t>(threads) - 1u) /
                                               static_cast<std::uint64_t>(threads);
            io_collect_prefix_holes_kernel_0315c<<<static_cast<unsigned int>(holeBlocks64), threads>>>(
                actualActive, view.role, kParticleRoleFluid, dHoleFlags, dHoleScan, dHoleIndices);
            check_cuda_0263(cudaGetLastError(), "io_collect_prefix_holes_kernel_0315c launch");

            const std::uint64_t donorBlocks64 = (tailN + static_cast<std::uint64_t>(threads) - 1u) /
                                                static_cast<std::uint64_t>(threads);
            io_collect_tail_donors_reverse_kernel_0315c<<<static_cast<unsigned int>(donorBlocks64), threads>>>(
                view.n, actualActive, view.role, kParticleRoleFluid, dDonorFlags, dDonorScan, dDonorIndices);
            check_cuda_0263(cudaGetLastError(), "io_collect_tail_donors_reverse_kernel_0315c launch");

            const std::uint64_t swapBlocks64 = (nPairs + static_cast<std::uint64_t>(threads) - 1u) /
                                               static_cast<std::uint64_t>(threads);
            if (swapBlocks64 > static_cast<std::uint64_t>(2147483647)) {
                throw std::runtime_error("cuda_classic_src_io_resident_0263: grid too large for 0315c exact swaps");
            }
            io_swap_particle_pairs_kernel_0315c<<<static_cast<unsigned int>(swapBlocks64), threads>>>(
                nPairs, dHoleIndices, dDonorIndices,
                view.x, view.y, view.vx, view.vy, view.mass, view.type, view.role);
            check_cuda_0263(cudaGetLastError(), "io_swap_particle_pairs_kernel_0315c launch");
        }

        check_cuda_0263(cudaDeviceSynchronize(), "0315c exact active-prefix swap compaction synchronize");
        gpuState.set_active_fluid_size(actualActive);
        state.NactiveFluid = actualActive;
        cleanup();
        diag.kernelSeconds += elapsed_0263(t0, Clock::now());
        diag.particles = actualActive;
        diag.capacity = view.capacity;
        return actualActive;
    } catch (...) {
        cleanup();
        throw;
    }
}

__device__ void activate_reservoir_pool_slot_device_0268(
    double* __restrict__ x,
    double* __restrict__ y,
    double* __restrict__ vx,
    double* __restrict__ vy,
    double* __restrict__ mass,
    std::uint32_t* __restrict__ type,
    unsigned char* __restrict__ role,
    unsigned char fluidRole,
    unsigned char inactiveRole,
    const std::uint64_t* __restrict__ inactiveIndices,
    unsigned int inactiveCount,
    std::uint64_t slotOrdinal,
    double xp,
    double yp,
    double vxp,
    double vyp,
    double particleMass,
    std::uint32_t particleType,
    CudaClassicSrcIoCounters0263& local)
{
    if (slotOrdinal >= static_cast<std::uint64_t>(inactiveCount)) {
        local.overflowFlag = 1;
        return;
    }
    const std::uint64_t slot = inactiveIndices[slotOrdinal];
    if (role[slot] != inactiveRole) {
        local.overflowFlag = 2;
        return;
    }
    x[slot] = xp;
    y[slot] = yp;
    vx[slot] = vxp;
    vy[slot] = vyp;
    mass[slot] = particleMass;
    type[slot] = particleType;
    role[slot] = fluidRole;
    local.inletParticlesInserted += 1ULL;
    local.inletMeanUxSum += vxp;
    local.inletMeanUySum += vyp;
}

__device__ void insert_reservoir_cell_pool_device_0268(
    double* __restrict__ x,
    double* __restrict__ y,
    double* __restrict__ vx,
    double* __restrict__ vy,
    double* __restrict__ mass,
    std::uint32_t* __restrict__ type,
    unsigned char* __restrict__ role,
    unsigned char fluidRole,
    unsigned char inactiveRole,
    const std::uint64_t* __restrict__ inactiveIndices,
    unsigned int inactiveCount,
    std::uint64_t poolBaseOffset0493x8q,
    const CudaClassicSrcIoFullfaceConfig0263& cfg,
    int ix,
    int iy,
    double dx,
    double dy,
    int targetN,
    double time,
    int inletFace,
    int segmentIndex,
    std::uint64_t cellOrdinal,
    CudaClassicSrcIoCounters0263& local)
{
    if (targetN <= 0) return;
    double x0 = cfg.xMin + static_cast<double>(ix) * dx;
    double x1 = cfg.xMin + static_cast<double>(ix + 1) * dx;
    double y0 = cfg.yMin + static_cast<double>(iy) * dy;
    double y1 = cfg.yMin + static_cast<double>(iy + 1) * dy;
    double clippedX0 = x0, clippedX1 = x1, clippedY0 = y0, clippedY1 = y1;
    double clippedAreaFraction = 1.0;
    if (!clip_reservoir_cell_to_segment_device_0288(
            cfg, inletFace, segmentIndex,
            clippedX0, clippedX1, clippedY0, clippedY1, clippedAreaFraction)) return;
    const int effectiveTargetN = scaled_partial_cell_target_0493w3(targetN, clippedAreaFraction);
    if (effectiveTargetN <= 0) return;
    const double xc = 0.5 * (x0 + x1);
    const double yc = 0.5 * (y0 + y1);
    if (reservoir_cell_center_inside_immersed_device_0263(xc, yc, cfg)) return;
    local.inletReservoirCells += 1ULL;
    local.inletReservoirTargetParticles += static_cast<unsigned long long>(effectiveTargetN);
    const std::uint64_t seed = splitmix64_device_0263(cfg.rngSeed ^ (cfg.step * 0x9e3779b97f4a7c15ULL) ^
                                                      (cellOrdinal * 0xbf58476d1ce4e5b9ULL) ^
                                                      face_tag_0263(inletFace));
    double particleMass = cfg.refMass;
    if (segmentIndex >= 0 && segmentIndex < cfg.segmentCount) {
        particleMass = cfg.segmentMass[segmentIndex];
    }
    const InletThermalCell0263 thermal = prepare_inlet_thermal_cell_0435d(
        cfg, seed, effectiveTargetN, particleMass);
    const double sigma = (cfg.inletThermalNoise > 0.0 && cfg.inletKBT > 0.0 && particleMass > 0.0)
        ? cfg.inletThermalNoise * sqrt(cfg.inletKBT / particleMass) : 0.0;
    Mt19937_64_Device_0263 rng{};
    mt_seed_device_0263(rng, seed);
    NormalDeviceState0263 normal{};
    const std::uint64_t baseSlot = poolBaseOffset0493x8q +
        cellOrdinal * static_cast<std::uint64_t>(targetN);
    for (int k = 0; k < effectiveTargetN; ++k) {
        const double rx = uniform01_device_0263(rng);
        const double ry = uniform01_device_0263(rng);
        const double xp = clamp_strictly_inside_device_0263(
            clippedX0 + rx * (clippedX1 - clippedX0), clippedX0, clippedX1);
        const double yp = clamp_strictly_inside_device_0263(
            clippedY0 + ry * (clippedY1 - clippedY0), clippedY0, clippedY1);
        double ux = 0.0, uy = 0.0;
        std::uint32_t particleType = cfg.refType;
        if (segmentIndex >= 0 && segmentIndex < cfg.segmentCount) {
            segmented_inlet_velocity_device_0493x8k(
                cfg, segmentIndex, xp, yp, time, ux, uy);
            particleType = cfg.segmentType[segmentIndex];
        } else {
            inlet_velocity_device_0263(cfg, inletFace, xp, yp, time, ux, uy);
        }
        const double fx = sigma > 0.0 ? sigma * normal01_device_0263(rng, normal) : 0.0;
        const double fy = sigma > 0.0 ? sigma * normal01_device_0263(rng, normal) : 0.0;
        const double dvx = thermal.scale * (fx - thermal.meanFx);
        const double dvy = thermal.scale * (fy - thermal.meanFy);
        activate_reservoir_pool_slot_device_0268(x, y, vx, vy, mass, type, role,
                                                 fluidRole, inactiveRole,
                                                 inactiveIndices, inactiveCount,
                                                 baseSlot + static_cast<std::uint64_t>(k),
                                                 xp, yp, ux + dvx, uy + dvy, particleMass, particleType, local);
        local.inletKbtNumerator += particleMass * (dvx * dvx + dvy * dvy);
        if (local.overflowFlag) return;
    }
}

__device__ inline void merge_reservoir_insert_counter_0268(CudaClassicSrcIoCounters0263* counters,
                                                            const CudaClassicSrcIoCounters0263& local) {
    add_counter_ull_0267(&counters->inletReservoirCells, local.inletReservoirCells);
    add_counter_ull_0267(&counters->inletReservoirTargetParticles, local.inletReservoirTargetParticles);
    add_counter_ull_0267(&counters->inletParticlesInserted, local.inletParticlesInserted);
    add_counter_ull_0267(&counters->fluidParticles, local.inletParticlesInserted);
    if (local.inletMeanUxSum != 0.0) atomicAdd(&counters->inletMeanUxSum, local.inletMeanUxSum);
    if (local.inletMeanUySum != 0.0) atomicAdd(&counters->inletMeanUySum, local.inletMeanUySum);
    if (local.inletKbtNumerator != 0.0) atomicAdd(&counters->inletKbtNumerator, local.inletKbtNumerator);
    if (local.overflowFlag != 0) atomicMax(&counters->overflowFlag, local.overflowFlag);
    if (local.failureFlag != 0) atomicMax(&counters->failureFlag, local.failureFlag);
}

__global__ void io_fullface_hard_reservoir_insert_pool_kernel_0268(
    double* __restrict__ x,
    double* __restrict__ y,
    double* __restrict__ vx,
    double* __restrict__ vy,
    double* __restrict__ mass,
    std::uint32_t* __restrict__ type,
    unsigned char* __restrict__ role,
    unsigned char fluidRole,
    unsigned char inactiveRole,
    CudaClassicSrcIoFullfaceConfig0263 cfg,
    const std::uint64_t* __restrict__ inactiveIndices,
    unsigned int inactiveCount,
    std::uint64_t poolBaseOffset0493x8q,
    CudaClassicSrcIoCounters0263* counters)
{
    const std::uint64_t cellOrdinal = static_cast<std::uint64_t>(blockIdx.x) * static_cast<std::uint64_t>(blockDim.x) +
                                      static_cast<std::uint64_t>(threadIdx.x);
    const int nx = cfg.Nx > 0 ? cfg.Nx : 1;
    const int ny = cfg.Ny > 0 ? cfg.Ny : 1;
    const int cellsX = imax_device_0263(1, imin_device_0263(cfg.inletReservoirCells, nx));
    const int cellsY = imax_device_0263(1, imin_device_0263(cfg.inletReservoirCells, ny));
    std::uint64_t cellCount = 0ULL;
    if (cfg.inletFace == 0 || cfg.inletFace == 1) cellCount = static_cast<std::uint64_t>(cellsX) * static_cast<std::uint64_t>(ny);
    else if (cfg.inletFace == 2 || cfg.inletFace == 3) cellCount = static_cast<std::uint64_t>(cellsY) * static_cast<std::uint64_t>(nx);
    if (cellOrdinal >= cellCount) return;

    const double dx = (cfg.xMax - cfg.xMin) / static_cast<double>(nx);
    const double dy = (cfg.yMax - cfg.yMin) / static_cast<double>(ny);
    const int targetN = cfg.inletTargetOccupancy;
    const double time = static_cast<double>(cfg.step) * cfg.dt;

    int ix = 0;
    int iy = 0;
    if (cfg.inletFace == 0) {
        ix = static_cast<int>(cellOrdinal / static_cast<std::uint64_t>(ny));
        iy = static_cast<int>(cellOrdinal % static_cast<std::uint64_t>(ny));
    } else if (cfg.inletFace == 1) {
        ix = nx - cellsX + static_cast<int>(cellOrdinal / static_cast<std::uint64_t>(ny));
        iy = static_cast<int>(cellOrdinal % static_cast<std::uint64_t>(ny));
    } else if (cfg.inletFace == 2) {
        iy = static_cast<int>(cellOrdinal / static_cast<std::uint64_t>(nx));
        ix = static_cast<int>(cellOrdinal % static_cast<std::uint64_t>(nx));
    } else if (cfg.inletFace == 3) {
        iy = ny - cellsY + static_cast<int>(cellOrdinal / static_cast<std::uint64_t>(nx));
        ix = static_cast<int>(cellOrdinal % static_cast<std::uint64_t>(nx));
    } else {
        return;
    }

    CudaClassicSrcIoCounters0263 local{};
    insert_reservoir_cell_pool_device_0268(x, y, vx, vy, mass, type, role,
                                           fluidRole, inactiveRole,
                                           inactiveIndices, inactiveCount,
                                           poolBaseOffset0493x8q,
                                           cfg, ix, iy, dx, dy,
                                           targetN, time, cfg.inletFace, -1,
                                           cellOrdinal, local);
    merge_reservoir_insert_counter_0268(counters, local);
}

std::uint64_t fullface_reservoir_cell_count_host_0268(const CudaClassicSrcIoFullfaceConfig0263& cfg) {
    const int nx = cfg.Nx > 0 ? cfg.Nx : 1;
    const int ny = cfg.Ny > 0 ? cfg.Ny : 1;
    const int cellsX = std::max(1, std::min(cfg.inletReservoirCells, nx));
    const int cellsY = std::max(1, std::min(cfg.inletReservoirCells, ny));
    if (cfg.inletFace == 0 || cfg.inletFace == 1) return static_cast<std::uint64_t>(cellsX) * static_cast<std::uint64_t>(ny);
    if (cfg.inletFace == 2 || cfg.inletFace == 3) return static_cast<std::uint64_t>(cellsY) * static_cast<std::uint64_t>(nx);
    return 0ULL;
}


bool reservoir_cell_center_inside_immersed_host_0269(double xc, double yc, const CudaClassicSrcIoFullfaceConfig0263& cfg) {
    return reservoir_cell_center_inside_immersed_core_0285(xc, yc, cfg);
}

std::uint64_t segmented_reservoir_cell_count_host_0269(const CudaClassicSrcIoFullfaceConfig0263& cfg) {
    const int nx = cfg.Nx > 0 ? cfg.Nx : 1;
    const int ny = cfg.Ny > 0 ? cfg.Ny : 1;
    const int cellsX = std::max(1, std::min(cfg.inletReservoirCells, nx));
    const int cellsY = std::max(1, std::min(cfg.inletReservoirCells, ny));
    const double dx = (cfg.xMax - cfg.xMin) / static_cast<double>(nx);
    const double dy = (cfg.yMax - cfg.yMin) / static_cast<double>(ny);
    std::uint64_t out = 0ULL;
    for (int seg = 0; seg < cfg.segmentCount; ++seg) {
        if (cfg.segmentMode[seg] != 1) continue;
        const int face = cfg.segmentFace[seg];
        if (face == 0) {
            for (int ix = 0; ix < cellsX; ++ix) {
                for (int iy = 0; iy < ny; ++iy) {
                    const double s0 = static_cast<double>(iy) / static_cast<double>(ny);
                    const double s1 = static_cast<double>(iy + 1) / static_cast<double>(ny);
                    if (inlet_segment_index_for_cell_interval_host_0288(cfg, face, s0, s1) != seg) continue;
                    const double xc = cfg.xMin + (static_cast<double>(ix) + 0.5) * dx;
                    const double yc = cfg.yMin + (static_cast<double>(iy) + 0.5) * dy;
                    if (reservoir_cell_center_inside_immersed_host_0269(xc, yc, cfg)) continue;
                    ++out;
                }
            }
        } else if (face == 1) {
            for (int ix = nx - cellsX; ix < nx; ++ix) {
                for (int iy = 0; iy < ny; ++iy) {
                    const double s0 = static_cast<double>(iy) / static_cast<double>(ny);
                    const double s1 = static_cast<double>(iy + 1) / static_cast<double>(ny);
                    if (inlet_segment_index_for_cell_interval_host_0288(cfg, face, s0, s1) != seg) continue;
                    const double xc = cfg.xMin + (static_cast<double>(ix) + 0.5) * dx;
                    const double yc = cfg.yMin + (static_cast<double>(iy) + 0.5) * dy;
                    if (reservoir_cell_center_inside_immersed_host_0269(xc, yc, cfg)) continue;
                    ++out;
                }
            }
        } else if (face == 2) {
            for (int iy = 0; iy < cellsY; ++iy) {
                for (int ix = 0; ix < nx; ++ix) {
                    const double s0 = static_cast<double>(ix) / static_cast<double>(nx);
                    const double s1 = static_cast<double>(ix + 1) / static_cast<double>(nx);
                    if (inlet_segment_index_for_cell_interval_host_0288(cfg, face, s0, s1) != seg) continue;
                    const double xc = cfg.xMin + (static_cast<double>(ix) + 0.5) * dx;
                    const double yc = cfg.yMin + (static_cast<double>(iy) + 0.5) * dy;
                    if (reservoir_cell_center_inside_immersed_host_0269(xc, yc, cfg)) continue;
                    ++out;
                }
            }
        } else if (face == 3) {
            for (int iy = ny - cellsY; iy < ny; ++iy) {
                for (int ix = 0; ix < nx; ++ix) {
                    const double s0 = static_cast<double>(ix) / static_cast<double>(nx);
                    const double s1 = static_cast<double>(ix + 1) / static_cast<double>(nx);
                    if (inlet_segment_index_for_cell_interval_host_0288(cfg, face, s0, s1) != seg) continue;
                    const double xc = cfg.xMin + (static_cast<double>(ix) + 0.5) * dx;
                    const double yc = cfg.yMin + (static_cast<double>(iy) + 0.5) * dy;
                    if (reservoir_cell_center_inside_immersed_host_0269(xc, yc, cfg)) continue;
                    ++out;
                }
            }
        }
    }
    return out;
}


unsigned long long fullface_reservoir_target_particles_host_0293(const CudaClassicSrcIoFullfaceConfig0263& cfg) {
    const int targetN = cfg.inletTargetOccupancy;
    if (targetN <= 0) return 0ULL;
    const int nx = cfg.Nx > 0 ? cfg.Nx : 1;
    const int ny = cfg.Ny > 0 ? cfg.Ny : 1;
    const int cellsX = std::max(1, std::min(cfg.inletReservoirCells, nx));
    const int cellsY = std::max(1, std::min(cfg.inletReservoirCells, ny));
    const double dx = (cfg.xMax - cfg.xMin) / static_cast<double>(nx);
    const double dy = (cfg.yMax - cfg.yMin) / static_cast<double>(ny);
    unsigned long long out = 0ULL;
    auto add_cell = [&](int ix, int iy) {
        const double xc = cfg.xMin + (static_cast<double>(ix) + 0.5) * dx;
        const double yc = cfg.yMin + (static_cast<double>(iy) + 0.5) * dy;
        if (reservoir_cell_center_inside_immersed_host_0269(xc, yc, cfg)) return;
        out += static_cast<unsigned long long>(targetN);
    };
    if (cfg.inletFace == 0) {
        for (int ix = 0; ix < cellsX; ++ix) for (int iy = 0; iy < ny; ++iy) add_cell(ix, iy);
    } else if (cfg.inletFace == 1) {
        for (int ix = nx - cellsX; ix < nx; ++ix) for (int iy = 0; iy < ny; ++iy) add_cell(ix, iy);
    } else if (cfg.inletFace == 2) {
        for (int iy = 0; iy < cellsY; ++iy) for (int ix = 0; ix < nx; ++ix) add_cell(ix, iy);
    } else if (cfg.inletFace == 3) {
        for (int iy = ny - cellsY; iy < ny; ++iy) for (int ix = 0; ix < nx; ++ix) add_cell(ix, iy);
    }
    return out;
}

unsigned long long segmented_reservoir_target_particles_host_0293(const CudaClassicSrcIoFullfaceConfig0263& cfg) {
    const int targetN = cfg.inletTargetOccupancy;
    if (targetN <= 0) return 0ULL;

    const int nx = cfg.Nx > 0 ? cfg.Nx : 1;
    const int ny = cfg.Ny > 0 ? cfg.Ny : 1;
    const int cellsX = std::max(1, std::min(cfg.inletReservoirCells, nx));
    const int cellsY = std::max(1, std::min(cfg.inletReservoirCells, ny));
    const double dx = (cfg.xMax - cfg.xMin) / static_cast<double>(nx);
    const double dy = (cfg.yMax - cfg.yMin) / static_cast<double>(ny);
    unsigned long long out = 0ULL;

    auto add_cell = [&](int face, int seg, int ix, int iy) {
        double x0 = cfg.xMin + static_cast<double>(ix) * dx;
        double x1 = cfg.xMin + static_cast<double>(ix + 1) * dx;
        double y0 = cfg.yMin + static_cast<double>(iy) * dy;
        double y1 = cfg.yMin + static_cast<double>(iy + 1) * dy;
        double areaFraction = 1.0;
        if (!clip_reservoir_cell_to_segment_device_0288(
                cfg, face, seg, x0, x1, y0, y1, areaFraction)) return;
        const double xc = cfg.xMin + (static_cast<double>(ix) + 0.5) * dx;
        const double yc = cfg.yMin + (static_cast<double>(iy) + 0.5) * dy;
        if (reservoir_cell_center_inside_immersed_host_0269(xc, yc, cfg)) return;
        out += static_cast<unsigned long long>(
            scaled_partial_cell_target_0493w3(targetN, areaFraction));
    };

    for (int seg = 0; seg < cfg.segmentCount; ++seg) {
        if (cfg.segmentMode[seg] != 1) continue;
        const int face = cfg.segmentFace[seg];
        if (face == 0) {
            for (int ix = 0; ix < cellsX; ++ix) {
                for (int iy = 0; iy < ny; ++iy) {
                    const double s0 = static_cast<double>(iy) / static_cast<double>(ny);
                    const double s1 = static_cast<double>(iy + 1) / static_cast<double>(ny);
                    if (inlet_segment_index_for_cell_interval_host_0288(cfg, face, s0, s1) == seg) {
                        add_cell(face, seg, ix, iy);
                    }
                }
            }
        } else if (face == 1) {
            for (int ix = nx - cellsX; ix < nx; ++ix) {
                for (int iy = 0; iy < ny; ++iy) {
                    const double s0 = static_cast<double>(iy) / static_cast<double>(ny);
                    const double s1 = static_cast<double>(iy + 1) / static_cast<double>(ny);
                    if (inlet_segment_index_for_cell_interval_host_0288(cfg, face, s0, s1) == seg) {
                        add_cell(face, seg, ix, iy);
                    }
                }
            }
        } else if (face == 2) {
            for (int iy = 0; iy < cellsY; ++iy) {
                for (int ix = 0; ix < nx; ++ix) {
                    const double s0 = static_cast<double>(ix) / static_cast<double>(nx);
                    const double s1 = static_cast<double>(ix + 1) / static_cast<double>(nx);
                    if (inlet_segment_index_for_cell_interval_host_0288(cfg, face, s0, s1) == seg) {
                        add_cell(face, seg, ix, iy);
                    }
                }
            }
        } else if (face == 3) {
            for (int iy = ny - cellsY; iy < ny; ++iy) {
                for (int ix = 0; ix < nx; ++ix) {
                    const double s0 = static_cast<double>(ix) / static_cast<double>(nx);
                    const double s1 = static_cast<double>(ix + 1) / static_cast<double>(nx);
                    if (inlet_segment_index_for_cell_interval_host_0288(cfg, face, s0, s1) == seg) {
                        add_cell(face, seg, ix, iy);
                    }
                }
            }
        }
    }
    return out;
}

__device__ bool map_segmented_reservoir_cell_device_0269(
    const CudaClassicSrcIoFullfaceConfig0263& cfg,
    std::uint64_t wantedOrdinal,
    int& outIx,
    int& outIy,
    int& outFace,
    int& outSegment)
{
    const int nx = cfg.Nx > 0 ? cfg.Nx : 1;
    const int ny = cfg.Ny > 0 ? cfg.Ny : 1;
    const int cellsX = imax_device_0263(1, imin_device_0263(cfg.inletReservoirCells, nx));
    const int cellsY = imax_device_0263(1, imin_device_0263(cfg.inletReservoirCells, ny));
    const double dx = (cfg.xMax - cfg.xMin) / static_cast<double>(nx);
    const double dy = (cfg.yMax - cfg.yMin) / static_cast<double>(ny);
    std::uint64_t ordinal = 0ULL;
    for (int seg = 0; seg < cfg.segmentCount; ++seg) {
        if (cfg.segmentMode[seg] != 1) continue;
        const int face = cfg.segmentFace[seg];
        if (face == 0) {
            for (int ix = 0; ix < cellsX; ++ix) {
                for (int iy = 0; iy < ny; ++iy) {
                    const double s0 = static_cast<double>(iy) / static_cast<double>(ny);
                    const double s1 = static_cast<double>(iy + 1) / static_cast<double>(ny);
                    if (inlet_segment_index_for_cell_interval_device_0288(cfg, face, s0, s1) != seg) continue;
                    const double xc = cfg.xMin + (static_cast<double>(ix) + 0.5) * dx;
                    const double yc = cfg.yMin + (static_cast<double>(iy) + 0.5) * dy;
                    if (reservoir_cell_center_inside_immersed_device_0263(xc, yc, cfg)) continue;
                    if (ordinal == wantedOrdinal) { outIx = ix; outIy = iy; outFace = face; outSegment = seg; return true; }
                    ++ordinal;
                }
            }
        } else if (face == 1) {
            for (int ix = nx - cellsX; ix < nx; ++ix) {
                for (int iy = 0; iy < ny; ++iy) {
                    const double s0 = static_cast<double>(iy) / static_cast<double>(ny);
                    const double s1 = static_cast<double>(iy + 1) / static_cast<double>(ny);
                    if (inlet_segment_index_for_cell_interval_device_0288(cfg, face, s0, s1) != seg) continue;
                    const double xc = cfg.xMin + (static_cast<double>(ix) + 0.5) * dx;
                    const double yc = cfg.yMin + (static_cast<double>(iy) + 0.5) * dy;
                    if (reservoir_cell_center_inside_immersed_device_0263(xc, yc, cfg)) continue;
                    if (ordinal == wantedOrdinal) { outIx = ix; outIy = iy; outFace = face; outSegment = seg; return true; }
                    ++ordinal;
                }
            }
        } else if (face == 2) {
            for (int iy = 0; iy < cellsY; ++iy) {
                for (int ix = 0; ix < nx; ++ix) {
                    const double s0 = static_cast<double>(ix) / static_cast<double>(nx);
                    const double s1 = static_cast<double>(ix + 1) / static_cast<double>(nx);
                    if (inlet_segment_index_for_cell_interval_device_0288(cfg, face, s0, s1) != seg) continue;
                    const double xc = cfg.xMin + (static_cast<double>(ix) + 0.5) * dx;
                    const double yc = cfg.yMin + (static_cast<double>(iy) + 0.5) * dy;
                    if (reservoir_cell_center_inside_immersed_device_0263(xc, yc, cfg)) continue;
                    if (ordinal == wantedOrdinal) { outIx = ix; outIy = iy; outFace = face; outSegment = seg; return true; }
                    ++ordinal;
                }
            }
        } else if (face == 3) {
            for (int iy = ny - cellsY; iy < ny; ++iy) {
                for (int ix = 0; ix < nx; ++ix) {
                    const double s0 = static_cast<double>(ix) / static_cast<double>(nx);
                    const double s1 = static_cast<double>(ix + 1) / static_cast<double>(nx);
                    if (inlet_segment_index_for_cell_interval_device_0288(cfg, face, s0, s1) != seg) continue;
                    const double xc = cfg.xMin + (static_cast<double>(ix) + 0.5) * dx;
                    const double yc = cfg.yMin + (static_cast<double>(iy) + 0.5) * dy;
                    if (reservoir_cell_center_inside_immersed_device_0263(xc, yc, cfg)) continue;
                    if (ordinal == wantedOrdinal) { outIx = ix; outIy = iy; outFace = face; outSegment = seg; return true; }
                    ++ordinal;
                }
            }
        }
    }
    return false;
}

__global__ void io_segmented_hard_reservoir_insert_pool_kernel_0269(
    double* __restrict__ x,
    double* __restrict__ y,
    double* __restrict__ vx,
    double* __restrict__ vy,
    double* __restrict__ mass,
    std::uint32_t* __restrict__ type,
    unsigned char* __restrict__ role,
    unsigned char fluidRole,
    unsigned char inactiveRole,
    CudaClassicSrcIoFullfaceConfig0263 cfg,
    const std::uint64_t* __restrict__ inactiveIndices,
    unsigned int inactiveCount,
    std::uint64_t poolBaseOffset0493x8q,
    CudaClassicSrcIoCounters0263* counters)
{
    const std::uint64_t cellOrdinal = static_cast<std::uint64_t>(blockIdx.x) * static_cast<std::uint64_t>(blockDim.x) +
                                      static_cast<std::uint64_t>(threadIdx.x);
    int ix = 0;
    int iy = 0;
    int face = -1;
    int seg = -1;
    if (!map_segmented_reservoir_cell_device_0269(cfg, cellOrdinal, ix, iy, face, seg)) return;

    const int nx = cfg.Nx > 0 ? cfg.Nx : 1;
    const int ny = cfg.Ny > 0 ? cfg.Ny : 1;
    const double dx = (cfg.xMax - cfg.xMin) / static_cast<double>(nx);
    const double dy = (cfg.yMax - cfg.yMin) / static_cast<double>(ny);
    const int targetN = cfg.inletTargetOccupancy;
    const double time = static_cast<double>(cfg.step) * cfg.dt;

    CudaClassicSrcIoCounters0263 local{};
    insert_reservoir_cell_pool_device_0268(x, y, vx, vy, mass, type, role,
                                           fluidRole, inactiveRole,
                                           inactiveIndices, inactiveCount,
                                           poolBaseOffset0493x8q,
                                           cfg, ix, iy, dx, dy,
                                           targetN, time, face, seg,
                                           cellOrdinal, local);
    merge_reservoir_insert_counter_0268(counters, local);
}

CudaParticleState& shared_state_0263() {
    return cuda_shared_particle_state_0251();
}

int inlet_face_code_0263(const SimulationParams& params) {
    if (is_inlet_boundary_mode(params.bcLeft)) return 0;
    if (is_inlet_boundary_mode(params.bcRight)) return 1;
    if (is_inlet_boundary_mode(params.bcBottom)) return 2;
    if (is_inlet_boundary_mode(params.bcTop)) return 3;
    return -1;
}

int segment_face_code_0264(const std::string& face) {
    if (face == "left") return 0;
    if (face == "right") return 1;
    if (face == "bottom") return 2;
    if (face == "top") return 3;
    return -1;
}

int segment_mode_code_0264(const OpenBoundarySegment& seg) {
    if (open_boundary_segment_is_inlet(seg)) return 1;
    if (open_boundary_segment_is_outlet(seg)) return 2;
    return 0;
}

bool wall_like_mode_0264(const std::string& mode) {
    return mode == "solid" || mode == "specular" || mode == "bounceback";
}

int outlet_regime_code_0291(const SimulationParams& params) {
    std::string mode = params.openBoundaryOutletMode;
    std::replace(mode.begin(), mode.end(), '-', '_');
    if (mode == "equilibrium_flux" || mode == "equilibrium" || mode == "balanced_particle_flux") return 1;
    if (mode == "forced_flux" || mode == "forced_mass_flux" || mode == "suction" || mode == "forced") return 2;
    return 0;
}

unsigned long long forced_particles_per_step_0291(const SimulationParams& params) {
    if (params.openBoundaryOutletForcedParticlesPerStep > 0) {
        return static_cast<unsigned long long>(params.openBoundaryOutletForcedParticlesPerStep);
    }
    if (params.openBoundaryOutletForcedParticleFlux > 0.0 && params.dt > 0.0) {
        const double particles = params.openBoundaryOutletForcedParticleFlux * params.dt;
        return particles > 0.0 ? static_cast<unsigned long long>(std::floor(particles + 0.5)) : 0ULL;
    }
    return 0ULL;
}

int profile_code_0263(const SimulationParams& params) {
    if (params.inletVelocitySpatialProfile == "poiseuille_y_max") return 1;
    if (params.inletVelocitySpatialProfile == "poiseuille_y" ||
        params.inletVelocitySpatialProfile == "poiseuille_y_mean") return 2;
    if (params.inletVelocitySpatialProfile == "flat_taper_y" ||
        params.inletVelocitySpatialProfile == "flat_taper_y_mean") return 3;
    return 0;
}

CudaClassicSrcIoFullfaceConfig0263 make_config_0263(const ParticleState& state,
                                                    const SimulationParams& params,
                                                    const FluidDomainBounds& domain,
                                                    std::uint64_t step,
                                                    double time) {
    (void)time;
    CudaClassicSrcIoFullfaceConfig0263 cfg{};
    cfg.Lx = params.Lx;
    cfg.Ly = params.Ly;
    cfg.Nx = std::max(1, params.Nx);
    cfg.Ny = std::max(1, params.Ny);
    cfg.dt = params.dt;
    cfg.xMin = domain.xMin;
    cfg.xMax = domain.xMax;
    cfg.yMin = domain.yMin;
    cfg.yMax = domain.yMax;
    cfg.leftMode = io_mode_code_0263(params.bcLeft);
    cfg.rightMode = io_mode_code_0263(params.bcRight);
    cfg.bottomMode = io_mode_code_0263(params.bcBottom);
    cfg.topMode = io_mode_code_0263(params.bcTop);
    cfg.leftWallMode = wall_mode_code_0263(params.bcLeft);
    cfg.rightWallMode = wall_mode_code_0263(params.bcRight);
    cfg.bottomWallMode = wall_mode_code_0263(params.bcBottom);
    cfg.topWallMode = wall_mode_code_0263(params.bcTop);
    cfg.wallUxBottom = params.wallVpUxBottom;
    cfg.wallUyBottom = domain.vyMin + params.wallVpUyBottom;
    cfg.wallUxTop = params.wallVpUxTop;
    cfg.wallUyTop = domain.vyMax + params.wallVpUyTop;
    cfg.bodyAx = params.bodyAccelerationX;
    cfg.bodyAy = params.bodyAccelerationY;
    cfg.tgEnable = params.taylorGreenForcingEnable ? 1 : 0;
    cfg.tgAmplitude = params.taylorGreenForcingAmplitude;
    cfg.tgModeX = params.taylorGreenForcingModeX;
    cfg.tgModeY = params.taylorGreenForcingModeY;
    cfg.inletFace = inlet_face_code_0263(params);
    cfg.inletReservoirCells = std::max(1, params.inletReservoirCells);
    cfg.inletTargetOccupancy = std::max(0, params.inletTargetOccupancy);
    cfg.inletUxLeft = params.inletUxLeft;
    cfg.inletUyLeft = params.inletUyLeft;
    cfg.inletUxRight = params.inletUxRight;
    cfg.inletUyRight = params.inletUyRight;
    cfg.inletUxBottom = params.inletUxBottom;
    cfg.inletUyBottom = params.inletUyBottom;
    cfg.inletUxTop = params.inletUxTop;
    cfg.inletUyTop = params.inletUyTop;
    cfg.rampEnable = params.inletVelocityRampEnable ? 1 : 0;
    cfg.rampT0 = params.inletVelocityRampStartTime;
    cfg.rampT1 = params.inletVelocityRampEndTime;
    cfg.rampInitial = params.inletVelocityRampInitialFactor;
    cfg.rampFinal = params.inletVelocityRampFinalFactor;
    cfg.rampSmoothstep = params.inletVelocityRampProfile == "smoothstep" ? 1 : 0;
    cfg.oscillationEnable = params.inletVelocityOscillationEnable ? 1 : 0;
    cfg.oscillationAmplitude = params.inletVelocityOscillationAmplitude;
    cfg.oscillationPeriod = params.inletVelocityOscillationPeriod;
    cfg.oscillationPhase = params.inletVelocityOscillationPhase;
    cfg.oscillationStartTime = params.inletVelocityOscillationStartTime;
    cfg.oscillationTimeOffset = params.inletVelocityOscillationTimeOffset;
    cfg.profileCode = profile_code_0263(params);
    cfg.wallTaperCells = params.inletVelocityWallTaperCells;
    cfg.rngSeed = params.rngSeed;
    cfg.step = step;
    cfg.refMass = 1.0;
    cfg.refType = 0u;
    cfg.inletKBT = params.inletKBT > 0.0 ? params.inletKBT : params.kBT;
    cfg.inletThermalNoise = params.inletThermalNoise;
    cfg.inletHardCellVelocityMean = params.inletHardCellVelocityMean ? 1 : 0;
    cfg.inletHardCellThermalRescale = params.inletHardCellThermalRescale ? 1 : 0;
    cfg.outletRegimeCode = outlet_regime_code_0291(params);
    {
        std::string mode0493x8q = params.openBoundaryOutletMode;
        std::replace(mode0493x8q.begin(), mode0493x8q.end(), '-', '_');
        // Diagnostic ablation gate: preserve the qualified Neumann pressure/Q6
        // boundary while disabling only the x8q kinetic exterior continuation.
        // OFF by default, so existing runners are bit-for-bit unchanged unless
        // the dedicated environment variable is explicitly enabled.
        const bool disableKinetic0493x8q =
            env_truthy_0263("MPCD_CUDA_OPEN_BOUNDARY_NEUMANN_KINETIC_0493X8Q_DISABLE");
        cfg.outletNeumannKinetic0493x8q =
            (mode0493x8q == "neumann" && !disableKinetic0493x8q) ? 1 : 0;
        cfg.outletNeumannPressureReservoir0493x8y =
            (cfg.outletNeumannKinetic0493x8q &&
             env_truthy_0263("MPCD_CUDA_OPEN_BOUNDARY_NEUMANN_PRESSURE_RESERVOIR_0493X8Y")) ? 1 : 0;
        cfg.outletNeumannNoBackflowReservoir0493x8z =
            (cfg.outletNeumannPressureReservoir0493x8y &&
             env_truthy_0263("MPCD_CUDA_OPEN_BOUNDARY_NEUMANN_NO_BACKFLOW_0493X8Z")) ? 1 : 0;
        cfg.outletNeumannZeroDriftOnBackflow0493x9a =
            (cfg.outletNeumannNoBackflowReservoir0493x8z &&
             env_truthy_0263("MPCD_CUDA_OPEN_BOUNDARY_NEUMANN_ZERO_DRIFT_ON_BACKFLOW_0493X9A")) ? 1 : 0;
        cfg.outletNeumannLiquidType0493x9b = env_int_0263(
            "MPCD_CUDA_OPEN_BOUNDARY_NEUMANN_LIQUID_TYPE_0493X9B", -1);
        cfg.outletNeumannLiquidStrictOutflow0493x9b =
            (cfg.outletNeumannZeroDriftOnBackflow0493x9a &&
             cfg.outletNeumannLiquidType0493x9b >= 0 &&
             env_truthy_0263("MPCD_CUDA_OPEN_BOUNDARY_NEUMANN_LIQUID_STRICT_OUTFLOW_0493X9B")) ? 1 : 0;
        cfg.outletNeumannVirtualReservoir0493x8x =
            (cfg.outletNeumannKinetic0493x8q &&
             (cfg.outletNeumannPressureReservoir0493x8y ||
              env_truthy_0263("MPCD_CUDA_OPEN_BOUNDARY_NEUMANN_VIRTUAL_RESERVOIR_0493X8X"))) ? 1 : 0;
        cfg.outletNeumannReservoirTargetOccupancy0493x8y =
            static_cast<double>(std::max(0, env_int_0263(
                "MPCD_CUDA_OPEN_BOUNDARY_NEUMANN_PRESSURE_RESERVOIR_0493X8Y_TARGET_OCCUPANCY",
                cfg.inletTargetOccupancy)));
        if (cfg.outletNeumannPressureReservoir0493x8y &&
            !(cfg.outletNeumannReservoirTargetOccupancy0493x8y > 0.0)) {
            throw std::runtime_error(
                "0493x8y pressure-reservoir Neumann requires positive target occupancy");
        }
        cfg.outletNeumannReservoirLayers0493x8x = std::max(
            1, std::min(4, env_int_0263(
                "MPCD_CUDA_OPEN_BOUNDARY_NEUMANN_VIRTUAL_RESERVOIR_0493X8X_LAYERS", 2)));
        cfg.outletNeumannReservoirCoarseLayers0493x8x = std::max(
            1, std::min(32, env_int_0263(
                "MPCD_CUDA_OPEN_BOUNDARY_NEUMANN_VIRTUAL_RESERVOIR_0493X8X_COARSE_LAYERS", 8)));
        cfg.outletNeumannVirtualCells0493x8w =
            (cfg.outletNeumannKinetic0493x8q &&
             !cfg.outletNeumannVirtualReservoir0493x8x &&
             env_truthy_0263("MPCD_CUDA_OPEN_BOUNDARY_NEUMANN_VIRTUAL_CELLS_0493X8W")) ? 1 : 0;
        cfg.outletNeumannVirtualLayers0493x8w = std::max(
            1, std::min(4, env_int_0263(
                "MPCD_CUDA_OPEN_BOUNDARY_NEUMANN_VIRTUAL_CELLS_0493X8W_LAYERS", 2)));
        cfg.outletNeumannReplica0493x8v =
            (cfg.outletNeumannKinetic0493x8q &&
             !cfg.outletNeumannVirtualReservoir0493x8x &&
             !cfg.outletNeumannVirtualCells0493x8w &&
             env_truthy_0263("MPCD_CUDA_OPEN_BOUNDARY_NEUMANN_REPLICA_0493X8V")) ? 1 : 0;
        cfg.outletNeumannReplicaSourceLayers0493x8v = std::min(
            4, env_int_0263(
                "MPCD_CUDA_OPEN_BOUNDARY_NEUMANN_REPLICA_0493X8V_SOURCE_LAYERS", 1));
    }
    cfg.outletForcedMassPerStep = std::max(0.0, params.openBoundaryOutletForcedMassPerStep);
    if (params.openBoundaryOutletForcedMassFlux > 0.0) {
        cfg.outletForcedMassPerStep = std::max(cfg.outletForcedMassPerStep,
                                               params.openBoundaryOutletForcedMassFlux * params.dt);
    }
    cfg.outletForcedParticlesPerStep = forced_particles_per_step_0291(params);
    cfg.outletForcedLayerCells = std::max(1, params.openBoundaryOutletForcedLayerCells);
    const std::size_t nActiveRef = active_fluid_count_size(state);
    for (std::size_t i = 0; i < nActiveRef; ++i) {
        if (is_fluid_particle(state, i)) {
            cfg.refMass = state.mass[i];
            cfg.refType = state.type[i];
            break;
        }
    }
    if (immersed_solid_enabled(params) && immersed_solid_shape(params) == ImmersedSolidShape::Rectangle) {
        cfg.immersedRectangleEnabled = 1;
        immersed_solid_rectangle_bounds(params, time, cfg.immersedXMin, cfg.immersedXMax, cfg.immersedYMin, cfg.immersedYMax);
    }
    if (immersed_solid_enabled(params) && immersed_solid_shape(params) == ImmersedSolidShape::Circle) {
        cfg.immersedCircleEnabled = 1;
        immersed_solid_circle_center(params, time, cfg.immersedCircleCx, cfg.immersedCircleCy);
        cfg.immersedCircleR = params.immersedSolidR;
    }
    if (params.openBoundarySegmentsEnable) {
        cfg.segmentedEnable = 1;
        cfg.segmentCount = std::min(static_cast<int>(params.openBoundarySegments.size()), kOpenBoundaryMaxSegments);
        bool hasSegmentX0414 = false;
        bool hasSegmentY0414 = false;
        for (int k = 0; k < cfg.segmentCount; ++k) {
            const OpenBoundarySegment& seg = params.openBoundarySegments[static_cast<std::size_t>(k)];
            cfg.segmentFace[k] = segment_face_code_0264(seg.face);
            cfg.segmentMode[k] = segment_mode_code_0264(seg);
            cfg.segmentSMin[k] = seg.sMin;
            cfg.segmentSMax[k] = seg.sMax;
            cfg.segmentUx[k] = seg.ux;
            cfg.segmentUy[k] = seg.uy;
            cfg.segmentMass[k] = seg.mass;
            cfg.segmentType[k] = seg.type;
            hasSegmentX0414 = hasSegmentX0414 || open_boundary_face_is_x(seg.face);
            hasSegmentY0414 = hasSegmentY0414 || open_boundary_face_is_y(seg.face);
        }
        cfg.segmentedMultiAxis0414 = hasSegmentX0414 && hasSegmentY0414 ? 1 : 0;
    }
    return cfg;
}

bool fused_src_thermostat_resident_io_0280c_requested() {
    return env_truthy_0263("MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_USE");
}

bool q6_resident_io_fullface_0404_requested() {
    return env_truthy_0263("MPCD_CUDA_Q6_RESIDENT_SRC_IO_FULLFACE_0404");
}

bool q6_resident_io_segmented_0409_requested() {
    return env_truthy_0263("MPCD_CUDA_Q6_RESIDENT_SRC_IO_SEGMENTED_0409");
}

bool thermostat_allowed_for_resident_io_0280c(const SimulationParams& params) {
    if (!params.thermostatEnable) return true;
    // 0280c: the original classic resident inlet/outlet gates were deliberately
    // classic-only and rejected thermostatEnable=true.  That made the 0279/0280
    // thermostat validators silently fall back to the CPU inlet/outlet path (or,
    // for segmented shared-state mode, leave no fresh CUDA state for the fused
    // thermostat consumer).  Permit the thermostat only when the validated
    // fused persistent SRC+thermostat consumer is explicitly requested and no
    // CPU continuation (Q6, resampling, virial/capacity) can intervene between
    // collision and thermostat.
    if (!fused_src_thermostat_resident_io_0280c_requested()) return false;
    if (params.projectionEnable || params.closedCapacityResponseEnable) return false;
    if (params.thermostatEvery <= 0) return false;
    if (params.thermostatMode != "cell_relative_rescale") return false;
    return true;
}

bool supported_common_0263(const SimulationParams& params) {
    const bool q6ResidentIo0404 = q6_resident_io_fullface_0404_requested();
    if (!params.srcClassicCudaModeEnable && !q6ResidentIo0404) return false;
    if (!hard_inlet_reservoir_enabled_0263(params)) return false;
    if (params.openBoundarySegmentsEnable || params.openBoundarySegmentCount != 0) return false;
    if (!(params.Lx > 0.0) || !(params.Ly > 0.0) || !(params.dt >= 0.0)) return false;
    if (params.closedCapacityResponseEnable) return false;
    if (q6ResidentIo0404) {
        if (!params.projectionEnable || params.projectionBackend != "cuda") return false;
        if (!env_truthy_0263("MPCD_CUDA_Q6_RESIDENT_0400")) return false;
        if (params.inletVelocitySpatialProfile != "uniform") return false;
        if (!(params.openBoundaryOutletMode == "balanced_flux" || params.openBoundaryOutletMode == "balanced")) return false;
    } else {
        if (params.projectionEnable) return false;
        if (!thermostat_allowed_for_resident_io_0280c(params)) return false;
    }
    if (params.closedCapacityInletMassFluxEnable) return false;
    if (params.fluidXMinVelocity != 0.0 || params.fluidXMaxVelocity != 0.0 ||
        params.fluidYMinVelocity != 0.0 || params.fluidYMaxVelocity != 0.0) return false;
    const int left = io_mode_code_0263(params.bcLeft);
    const int right = io_mode_code_0263(params.bcRight);
    const int bottom = io_mode_code_0263(params.bcBottom);
    const int top = io_mode_code_0263(params.bcTop);
    const bool xPair = left != 0 && right != 0 && left != right && bottom == 0 && top == 0 &&
                       wall_mode_code_0263(params.bcBottom) != 0 && wall_mode_code_0263(params.bcTop) != 0;
    const bool yPair = bottom != 0 && top != 0 && bottom != top && left == 0 && right == 0 &&
                       wall_mode_code_0263(params.bcLeft) != 0 && wall_mode_code_0263(params.bcRight) != 0;
    return xPair || yPair;
}

bool supported_segmented_0264(const SimulationParams& params) {
    const bool q6ResidentIo0409 = q6_resident_io_segmented_0409_requested();
    if (!params.srcClassicCudaModeEnable && !q6ResidentIo0409) return false;
    if (!hard_inlet_reservoir_enabled_0263(params)) return false;
    if (!params.openBoundarySegmentsEnable || params.openBoundarySegmentCount <= 0) return false;
    if (static_cast<int>(params.openBoundarySegments.size()) != params.openBoundarySegmentCount) return false;
    if (params.openBoundarySegmentCount > kOpenBoundaryMaxSegments) return false;
    if (!(params.Lx > 0.0) || !(params.Ly > 0.0) || !(params.dt >= 0.0)) return false;
    if (params.closedCapacityResponseEnable) return false;
    if (q6ResidentIo0409) {
        if (!params.projectionEnable || params.projectionBackend != "cuda") return false;
        if (!env_truthy_0263("MPCD_CUDA_Q6_RESIDENT_0400")) return false;
        if (!(params.inletVelocitySpatialProfile == "uniform" ||
              params.inletVelocitySpatialProfile == "poiseuille_y_max" ||
              params.inletVelocitySpatialProfile == "poiseuille_y" ||
              params.inletVelocitySpatialProfile == "poiseuille_y_mean")) return false;
    } else {
        // 0264 is still restricted to the classic SRC resident subset when the
        // explicit Q6 continuation is not requested.
        if (params.projectionEnable) return false;
        if (!thermostat_allowed_for_resident_io_0280c(params)) return false;
    }
    if (params.closedCapacityInletMassFluxEnable) return false;
    if (params.fluidXMinVelocity != 0.0 || params.fluidXMaxVelocity != 0.0 ||
        params.fluidYMinVelocity != 0.0 || params.fluidYMaxVelocity != 0.0) return false;
    if (params.immersedSolidEnable) return false;
    if (is_io_boundary_mode(params.bcLeft) || is_io_boundary_mode(params.bcRight) ||
        is_io_boundary_mode(params.bcBottom) || is_io_boundary_mode(params.bcTop)) return false;
    if (!wall_like_mode_0264(params.bcLeft) || !wall_like_mode_0264(params.bcRight) ||
        !wall_like_mode_0264(params.bcBottom) || !wall_like_mode_0264(params.bcTop)) return false;

    bool hasInlet = false;
    bool hasOutlet = false;
    for (const OpenBoundarySegment& seg : params.openBoundarySegments) {
        const int face = segment_face_code_0264(seg.face);
        const int mode = segment_mode_code_0264(seg);
        if (face < 0 || mode == 0) return false;
        // 0412: broaden SRC-classic resident segmented IO beyond the original
        // same-left U-turn validation target.  The resident kernels already use
        // segmentFace for crossing, reservoir insertion and outlet extraction;
        // keep the structural safety guards but allow multi-face segmented IO.
        if (!(seg.sMin >= 0.0 && seg.sMax <= 1.0 && seg.sMax >= seg.sMin)) return false;
        if (mode == 1) hasInlet = true;
        if (mode == 2) hasOutlet = true;
    }
    return hasInlet && hasOutlet;
}

void maybe_apply_forced_outlet_extraction_0291(
    const CudaParticleDeviceView& view,
    const CudaClassicSrcIoFullfaceConfig0263& cfg,
    CudaClassicSrcIoCounters0263* dCounters,
    const char* context,
    unsigned long long equilibriumPredictedInletInsertions = 0ULL,
    std::uint64_t* recycleDeletedIndices0493x9e = nullptr,
    unsigned int* recycleDeletedCount0493x9e = nullptr,
    std::uint64_t recycleDeletedCapacity0493x9e = 0u)
{
    const std::uint64_t nActiveFluid = view.nActiveFluid;
    if (cfg.outletRegimeCode == 0 || nActiveFluid == 0u) return;

    CudaForcedOutletBudget0291 hBudget{};
    if (cfg.outletRegimeCode == 1) {
        CudaClassicSrcIoCounters0263 h{};
        check_cuda_0263(cudaMemcpy(&h, dCounters, sizeof(CudaClassicSrcIoCounters0263), cudaMemcpyDeviceToHost),
                        "copy counters before equilibrium outlet extraction");
        const unsigned long long inserted = equilibriumPredictedInletInsertions > 0ULL
            ? equilibriumPredictedInletInsertions
            : h.inletParticlesInserted;
        const long long net = static_cast<long long>(inserted) -
                              static_cast<long long>(h.inletReservoirDeleted) -
                              static_cast<long long>(h.inletBackflowDeleted) -
                              static_cast<long long>(h.outletParticlesDeleted);
        if (net <= 0LL) return;
        hBudget.targetParticles = static_cast<unsigned long long>(net);
    } else if (cfg.outletRegimeCode == 2) {
        hBudget.targetParticles = cfg.outletForcedParticlesPerStep;
        if (hBudget.targetParticles == 0ULL) hBudget.targetMass = cfg.outletForcedMassPerStep;
        if (hBudget.targetParticles == 0ULL && !(hBudget.targetMass > 0.0)) return;
    } else {
        return;
    }

    CudaForcedOutletBudget0291* dBudget = nullptr;
    check_cuda_0263(cudaMalloc(&dBudget, sizeof(CudaForcedOutletBudget0291)), "allocate forced outlet budget 0291");
    check_cuda_0263(cudaMemcpy(dBudget, &hBudget, sizeof(CudaForcedOutletBudget0291), cudaMemcpyHostToDevice),
                    "upload forced outlet budget 0291");

    const int threads = env_int_0263("MPCD_CUDA_CLASSIC_SRC_IO_RESIDENT_0291_FORCED_OUTLET_THREADS",
                                    env_int_0263("MPCD_CUDA_CLASSIC_SRC_IO_RESIDENT_0267_BOUNDARY_THREADS", 256));
    const std::uint64_t blocks64 = (nActiveFluid + static_cast<std::uint64_t>(threads) - 1u) /
                                   static_cast<std::uint64_t>(threads);
    if (blocks64 > static_cast<std::uint64_t>(2147483647)) {
        check_cuda_0263(cudaFree(dBudget), "free forced outlet budget after grid-too-large");
        throw std::runtime_error("cuda_classic_src_io_resident_0263: grid too large for 0291 forced outlet extraction launch");
    }
    io_forced_outlet_extraction_kernel_0291<<<static_cast<unsigned int>(blocks64), threads>>>(
        nActiveFluid, view.x, view.y, view.mass, view.role,
        kParticleRoleFluid, kParticleRoleInactive, cfg, dBudget, dCounters,
        recycleDeletedIndices0493x9e, recycleDeletedCount0493x9e,
        recycleDeletedCapacity0493x9e);
    check_cuda_0263(cudaGetLastError(), context);
    check_cuda_0263(cudaFree(dBudget), "free forced outlet budget 0291");
}


} // namespace

bool cuda_classic_src_io_fullface_resident_0263_requested() {
    return env_truthy_0263("MPCD_CUDA_CLASSIC_SRC_IO_FULLFACE_RESIDENT_0263");
}

bool cuda_classic_src_io_fullface_resident_0263_supported(const SimulationParams& params) {
    return supported_common_0263(params);
}

bool cuda_classic_src_io_segmented_resident_0264_requested() {
    return env_truthy_0263("MPCD_CUDA_CLASSIC_SRC_IO_SEGMENTED_RESIDENT_0264") ||
           q6_resident_io_segmented_0409_requested();
}

bool cuda_classic_src_io_segmented_resident_0264_supported(const SimulationParams& params) {
    return supported_segmented_0264(params);
}

CudaClassicSrcIoResident0263Diagnostics try_apply_cuda_classic_src_io_fullface_stream_0263(
    ParticleState& state,
    const SimulationParams& params,
    const FluidDomainBounds& domain,
    std::uint64_t step)
{
    CudaClassicSrcIoResident0263Diagnostics diag{};
    diag.requested = cuda_classic_src_io_fullface_resident_0263_requested();
    diag.supported = cuda_classic_src_io_fullface_resident_0263_supported(params);
    const std::uint64_t nActiveFluid = active_fluid_count(state);
    diag.particles = nActiveFluid;
    if (!diag.requested || !diag.supported || nActiveFluid == 0u) return diag;
    if (!cuda_particle_state_available()) return diag;

    const auto t0 = Clock::now();
    CudaParticleStateDiagnostics particleDiag{};
    CudaParticleState& gpuState = shared_state_0263();
    if (!cuda_shared_particle_state_0251_is_fresh()) {
        gpuState.upload_all(state, &particleDiag);
    }
    const auto tAfterUpload = Clock::now();

    const CudaClassicSrcIoFullfaceConfig0263 cfg = make_config_0263(
        state, params, domain, step, static_cast<double>(step) * params.dt);
    const int threads = env_int_0263("MPCD_CUDA_CLASSIC_SRC_IO_FULLFACE_RESIDENT_0263_THREADS", 256);
    const std::uint64_t blocks64 = (nActiveFluid + static_cast<std::uint64_t>(threads) - 1u) /
                                   static_cast<std::uint64_t>(threads);
    if (blocks64 > static_cast<std::uint64_t>(2147483647)) {
        throw std::runtime_error("cuda_classic_src_io_resident_0263: grid too large for stream launch");
    }
    CudaParticleDeviceView view = gpuState.device_view();
    io_fullface_force_stream_kernel_0263<<<static_cast<unsigned int>(blocks64), threads>>>(
        nActiveFluid, view.x, view.y, view.vx, view.vy, view.role, kParticleRoleFluid, cfg);
    check_cuda_0263(cudaGetLastError(), "io_fullface_force_stream_kernel_0263 launch");
    check_cuda_0263(cudaDeviceSynchronize(), "io_fullface_force_stream_kernel_0263 synchronize");
    cuda_shared_particle_state_0251_mark_fresh("classic_src_io_fullface_stream_0263");
    const auto tAfterKernel = Clock::now();

    diag.handled = true;
    diag.applied = true;
    diag.allocationCalls = particleDiag.allocationCalls;
    diag.uploadCalls = particleDiag.uploadCalls;
    diag.downloadCalls = particleDiag.downloadCalls;
    diag.uploadSeconds = elapsed_0263(t0, tAfterUpload);
    diag.kernelSeconds = elapsed_0263(tAfterUpload, tAfterKernel);
    diag.downloadSeconds = 0.0;
    diag.totalSeconds = elapsed_0263(t0, tAfterKernel);
    return diag;
}


struct NeumannGhostWorkspace0493x8q {
    CudaNeumannGhostCandidate0493x8q* candidates = nullptr;
    unsigned int* count = nullptr;
    unsigned int capacity = 0u;

    CudaNeumannBathMoments0493x8q* bath = nullptr;
    unsigned int bathCells = 0u;
    unsigned int bathCapacity = 0u;

    // 0493x8r device metadata. speciesCount==0 means dispatch the untouched
    // legacy x8q path.
    std::uint32_t* speciesTypes0493x8r = nullptr;
    double* speciesFallbackKBT0493x8r = nullptr;
    unsigned int speciesCount0493x8r = 0u;
    unsigned int speciesCapacity0493x8r = 0u;

    // 0493x8v uses a separate lightweight candidate buffer: no bath moments.
    CudaNeumannReplicaCandidate0493x8v* replicaCandidates0493x8v = nullptr;
    unsigned int* replicaCount0493x8v = nullptr;
    unsigned int replicaCapacity0493x8v = 0u;
    int replicaActive0493x8v = 0;

    // 0493x8w virtual-cell workspace. The exterior population itself is
    // ephemeral: only moments and the particles that actually cross inward
    // are stored. This is semantically a virtual-cell population without
    // consuming resident inactive slots for particles that stay outside.
    CudaNeumannVirtualCellMoments0493x8w* virtualMoments0493x8w = nullptr;
    unsigned int virtualMomentEntries0493x8w = 0u;
    unsigned int virtualMomentCapacity0493x8w = 0u;
    CudaNeumannVirtualCellCandidate0493x8w* virtualCandidates0493x8w = nullptr;
    unsigned int* virtualCount0493x8w = nullptr;
    unsigned int virtualCapacity0493x8w = 0u;
    std::uint32_t* virtualSpeciesTypes0493x8w = nullptr;
    double* virtualSpeciesFallbackKBT0493x8w = nullptr;
    unsigned int virtualSpeciesCount0493x8w = 0u;
    unsigned int virtualSpeciesCapacity0493x8w = 0u;
    int virtualCellsActive0493x8w = 0;

    // 0493x8x coarse-grained virtual-reservoir workspace.
    CudaNeumannVirtualReservoirMoments0493x8x* reservoirMoments0493x8x = nullptr;
    unsigned int reservoirMomentEntries0493x8x = 0u;
    unsigned int reservoirMomentCapacity0493x8x = 0u;
    CudaNeumannVirtualCellCandidate0493x8w* reservoirCandidates0493x8x = nullptr;
    unsigned int* reservoirCount0493x8x = nullptr;
    unsigned int reservoirCapacity0493x8x = 0u;
    std::uint32_t* reservoirSpeciesTypes0493x8x = nullptr;
    double* reservoirSpeciesFallbackKBT0493x8x = nullptr;
    unsigned int reservoirSpeciesCount0493x8x = 0u;
    unsigned int reservoirSpeciesCapacity0493x8x = 0u;
    int reservoirActive0493x8x = 0;
};


NeumannGhostWorkspace0493x8q prepare_neumann_ghost_candidates_0493x8q(
    const CudaClassicSrcIoFullfaceConfig0263& cfg,
    const SimulationParams& params,
    std::uint64_t nActiveFluid)
{
    static NeumannGhostWorkspace0493x8q cached{};
    if (!cfg.outletNeumannKinetic0493x8q || nActiveFluid == 0ULL)
        return NeumannGhostWorkspace0493x8q{};

    // x8x/x8w are explicit experimental opt-ins and require a strict registry:
    // every transported physical type must have a well-defined exterior identity
    // and a per-species thermal fallback. x8x has precedence over x8w.
    const bool reservoirActive0493x8x =
        cfg.outletNeumannVirtualReservoir0493x8x != 0;
    const bool virtualCellsActive0493x8w =
        !reservoirActive0493x8x && cfg.outletNeumannVirtualCells0493x8w != 0;
    if ((reservoirActive0493x8x || virtualCellsActive0493x8w) &&
        !(params.speciesRegistryEnable && params.speciesRequireRegisteredTypes &&
          !params.speciesDefinitions.empty())) {
        throw std::runtime_error(
            reservoirActive0493x8x
                ? "0493x8x virtual-reservoir Neumann requires strict species registry"
                : "0493x8w virtual-cell Neumann requires strict species registry");
    }

    // Automatic x8r selection requires a strict multi-species registry. This
    // makes an unregistered transported type impossible by contract. The
    // disable switch provides a direct legacy-x8q A/B control.
    const bool replicaActive0493x8v =
        !reservoirActive0493x8x && !virtualCellsActive0493x8w &&
        cfg.outletNeumannReplica0493x8v != 0;
    const bool speciesResolved0493x8r =
        !reservoirActive0493x8x && !virtualCellsActive0493x8w &&
        !replicaActive0493x8v &&
        params.speciesRegistryEnable && params.speciesRequireRegisteredTypes &&
        params.speciesDefinitions.size() > 1u &&
        !env_truthy_0263(
            "MPCD_CUDA_OPEN_BOUNDARY_NEUMANN_SPECIES_0493X8R_DISABLE");
    const std::size_t speciesCountSize0493x8r = speciesResolved0493x8r
        ? params.speciesDefinitions.size() : 0u;
    if (speciesCountSize0493x8r >
        static_cast<std::size_t>(std::numeric_limits<unsigned int>::max()))
        throw std::runtime_error(
            "0493x8r Neumann species count exceeds unsigned int");
    const unsigned int speciesCount0493x8r =
        static_cast<unsigned int>(speciesCountSize0493x8r);

    if (speciesCount0493x8r > 0u) {
        if (cached.speciesCapacity0493x8r < speciesCount0493x8r ||
            cached.speciesTypes0493x8r == nullptr ||
            cached.speciesFallbackKBT0493x8r == nullptr) {
            if (cached.speciesTypes0493x8r)
                check_cuda_0263(cudaFree(cached.speciesTypes0493x8r),
                                "resize 0493x8r Neumann species types");
            if (cached.speciesFallbackKBT0493x8r)
                check_cuda_0263(cudaFree(cached.speciesFallbackKBT0493x8r),
                                "resize 0493x8r Neumann species kBT");
            check_cuda_0263(cudaMalloc(
                &cached.speciesTypes0493x8r,
                sizeof(std::uint32_t) *
                    static_cast<std::size_t>(speciesCount0493x8r)),
                "allocate 0493x8r Neumann species types");
            check_cuda_0263(cudaMalloc(
                &cached.speciesFallbackKBT0493x8r,
                sizeof(double) *
                    static_cast<std::size_t>(speciesCount0493x8r)),
                "allocate 0493x8r Neumann species kBT");
            cached.speciesCapacity0493x8r = speciesCount0493x8r;
        }

        std::vector<std::uint32_t> typesH(speciesCount0493x8r);
        std::vector<double> kbtH(speciesCount0493x8r);
        const double inheritedTarget = params.thermostatTargetKBT > 0.0
            ? params.thermostatTargetKBT : params.kBT;
        for (unsigned int s = 0u; s < speciesCount0493x8r; ++s) {
            const SpeciesDefinition& d =
                params.speciesDefinitions[static_cast<std::size_t>(s)];
            typesH[s] = d.type;
            double target = cfg.inletKBT;
            if (params.speciesThermostatEnable) {
                target = d.thermostatTargetKBTDeclared > 0.0
                    ? d.thermostatTargetKBTDeclared : inheritedTarget;
            }
            kbtH[s] = std::isfinite(target) && target > 0.0 ? target : 0.0;
        }
        check_cuda_0263(cudaMemcpy(
            cached.speciesTypes0493x8r, typesH.data(),
            sizeof(std::uint32_t) *
                static_cast<std::size_t>(speciesCount0493x8r),
            cudaMemcpyHostToDevice),
            "upload 0493x8r Neumann species types");
        check_cuda_0263(cudaMemcpy(
            cached.speciesFallbackKBT0493x8r, kbtH.data(),
            sizeof(double) * static_cast<std::size_t>(speciesCount0493x8r),
            cudaMemcpyHostToDevice),
            "upload 0493x8r Neumann species kBT");
    }
    cached.speciesCount0493x8r = speciesCount0493x8r;

    if (reservoirActive0493x8x) {
        const std::size_t scSize = params.speciesDefinitions.size();
        if (scSize > static_cast<std::size_t>(
                std::numeric_limits<unsigned int>::max()))
            throw std::runtime_error(
                "0493x8x virtual-reservoir species count exceeds unsigned int");
        const unsigned int sc = static_cast<unsigned int>(scSize);
        bool reservoirMetadataReallocated0493x9dFix1 = false;
        if (cached.reservoirSpeciesCapacity0493x8x < sc ||
            cached.reservoirSpeciesTypes0493x8x == nullptr ||
            cached.reservoirSpeciesFallbackKBT0493x8x == nullptr) {
            if (cached.reservoirSpeciesTypes0493x8x)
                check_cuda_0263(cudaFree(cached.reservoirSpeciesTypes0493x8x),
                                "resize 0493x8x reservoir species types");
            if (cached.reservoirSpeciesFallbackKBT0493x8x)
                check_cuda_0263(cudaFree(cached.reservoirSpeciesFallbackKBT0493x8x),
                                "resize 0493x8x reservoir species kBT");
            check_cuda_0263(cudaMalloc(
                &cached.reservoirSpeciesTypes0493x8x,
                sizeof(std::uint32_t) * static_cast<std::size_t>(sc)),
                "allocate 0493x8x reservoir species types");
            check_cuda_0263(cudaMalloc(
                &cached.reservoirSpeciesFallbackKBT0493x8x,
                sizeof(double) * static_cast<std::size_t>(sc)),
                "allocate 0493x8x reservoir species kBT");
            cached.reservoirSpeciesCapacity0493x8x = sc;
            reservoirMetadataReallocated0493x9dFix1 = true;
        }

        std::vector<std::uint32_t> typesH(sc);
        std::vector<double> kbtH(sc);
        const double inheritedTarget = params.thermostatTargetKBT > 0.0
            ? params.thermostatTargetKBT : params.kBT;
        for (unsigned int si = 0u; si < sc; ++si) {
            const SpeciesDefinition& d =
                params.speciesDefinitions[static_cast<std::size_t>(si)];
            typesH[si] = d.type;
            double target = cfg.inletKBT;
            if (params.speciesThermostatEnable) {
                target = d.thermostatTargetKBTDeclared > 0.0
                    ? d.thermostatTargetKBTDeclared : inheritedTarget;
            }
            kbtH[si] = std::isfinite(target) && target > 0.0 ? target : 0.0;
        }
        // 0493x9d-fix1: these arrays are invariant in the atomizer and normally
        // invariant in a run.  Keep a host mirror and skip the two tiny H->D
        // copies unless the species configuration actually changes.
        static std::vector<std::uint32_t> cachedTypesH0493x9dFix1;
        static std::vector<double> cachedKbtH0493x9dFix1;
        const bool metadataChanged0493x9dFix1 =
            reservoirMetadataReallocated0493x9dFix1 ||
            cachedTypesH0493x9dFix1 != typesH || cachedKbtH0493x9dFix1 != kbtH;
        if (!neumann_resident_opt_0493x9d_fix1_enabled() || metadataChanged0493x9dFix1) {
            check_cuda_0263(cudaMemcpy(
                cached.reservoirSpeciesTypes0493x8x, typesH.data(),
                sizeof(std::uint32_t) * static_cast<std::size_t>(sc),
                cudaMemcpyHostToDevice),
                "upload 0493x8x reservoir species types");
            check_cuda_0263(cudaMemcpy(
                cached.reservoirSpeciesFallbackKBT0493x8x, kbtH.data(),
                sizeof(double) * static_cast<std::size_t>(sc),
                cudaMemcpyHostToDevice),
                "upload 0493x8x reservoir species kBT");
            if (neumann_resident_opt_0493x9d_fix1_enabled()) {
                cachedTypesH0493x9dFix1 = typesH;
                cachedKbtH0493x9dFix1 = kbtH;
            }
        }
        cached.reservoirSpeciesCount0493x8x = sc;

        const unsigned int spatial = neumann_virtual_spatial_count_0493x8w(cfg);
        const std::uint64_t entries64 =
            static_cast<std::uint64_t>(spatial) * static_cast<std::uint64_t>(sc);
        if (entries64 > static_cast<std::uint64_t>(
                std::numeric_limits<unsigned int>::max()))
            throw std::runtime_error(
                "0493x8x virtual-reservoir moment size exceeds unsigned int");
        const unsigned int entries = static_cast<unsigned int>(entries64);
        if (cached.reservoirMomentCapacity0493x8x < entries ||
            cached.reservoirMoments0493x8x == nullptr) {
            if (cached.reservoirMoments0493x8x)
                check_cuda_0263(cudaFree(cached.reservoirMoments0493x8x),
                                "resize 0493x8x reservoir moments");
            check_cuda_0263(cudaMalloc(
                &cached.reservoirMoments0493x8x,
                sizeof(CudaNeumannVirtualReservoirMoments0493x8x) *
                    static_cast<std::size_t>(entries)),
                "allocate 0493x8x reservoir moments");
            cached.reservoirMomentCapacity0493x8x = entries;
        }
        cached.reservoirMomentEntries0493x8x = entries;
        check_cuda_0263(cudaMemset(
            cached.reservoirMoments0493x8x, 0,
            sizeof(CudaNeumannVirtualReservoirMoments0493x8x) *
                static_cast<std::size_t>(entries)),
            "clear 0493x8x reservoir moments");

        const std::uint64_t layers = static_cast<std::uint64_t>(
            std::max(1, cfg.outletNeumannReservoirLayers0493x8x));
        const std::uint64_t perSpatial = static_cast<std::uint64_t>(
            std::max(64, 8 * std::max(1, cfg.inletTargetOccupancy) *
                             static_cast<int>(layers)));
        const std::uint64_t cap64 = std::max<std::uint64_t>(
            1024ULL, static_cast<std::uint64_t>(spatial) * perSpatial);
        if (cap64 > static_cast<std::uint64_t>(
                std::numeric_limits<unsigned int>::max()))
            throw std::runtime_error(
                "0493x8x reservoir candidate capacity exceeds unsigned int");
        const unsigned int cap = static_cast<unsigned int>(cap64);
        if (cached.reservoirCapacity0493x8x < cap ||
            cached.reservoirCandidates0493x8x == nullptr) {
            if (cached.reservoirCandidates0493x8x)
                check_cuda_0263(cudaFree(cached.reservoirCandidates0493x8x),
                                "resize 0493x8x reservoir candidates");
            check_cuda_0263(cudaMalloc(
                &cached.reservoirCandidates0493x8x,
                sizeof(CudaNeumannVirtualCellCandidate0493x8w) *
                    static_cast<std::size_t>(cap)),
                "allocate 0493x8x reservoir candidates");
            cached.reservoirCapacity0493x8x = cap;
        }
        if (cached.reservoirCount0493x8x == nullptr) {
            check_cuda_0263(cudaMalloc(
                &cached.reservoirCount0493x8x, sizeof(unsigned int)),
                "allocate 0493x8x reservoir candidate count");
        }
        check_cuda_0263(cudaMemset(
            cached.reservoirCount0493x8x, 0, sizeof(unsigned int)),
            "clear 0493x8x reservoir candidate count");

        cached.reservoirActive0493x8x = 1;
        cached.virtualCellsActive0493x8w = 0;
        cached.replicaActive0493x8v = 0;
        cached.speciesCount0493x8r = 0u;
        cached.bathCells = 0u;
        static bool announced0493x8x = false;
        static bool announced0493x8y = false;
        static bool announced0493x8z = false;
        static bool announced0493x9a = false;
        static bool announced0493x9b = false;
        static bool announced0493x9dFix1 = false;
        static bool announced0493x9e = false;
        if (neumann_recycle_pool_0493x9e_enabled() && !announced0493x9e) {
            std::fprintf(
                stderr,
                "[0493x9e-neumann] mode=recycle_deleted_slots physics=x9c_unchanged "
                "pool=deleted_first_plus_compact_tail prefixRepair=targeted_deleted_list_exact "
                "fallback=0315c_exact candidateCount=host_exact\n");
            announced0493x9e = true;
        }
        if (neumann_resident_opt_0493x9d_fix1_enabled() && !announced0493x9dFix1) {
            std::fprintf(
                stderr,
                "[0493x9d-fix1-neumann] mode=resident_workspace_exact_counts physics=x9c_unchanged "
                "counters=persistent tailPool=persistent_exact speciesMetadata=change_only "
                "preCandidateSync=elided candidateCount=host_exact inactiveCount=host_exact "
                "launchGeometry=exact candidateBuffer=preserved fallback=legacy_exact\n");
            announced0493x9dFix1 = true;
        }
        if (cfg.outletNeumannLiquidStrictOutflow0493x9b && !announced0493x9b) {
            std::fprintf(
                stderr,
                "[0493x9b-neumann] mode=gas_virtual_pressure_reservoir_liquid_strict_outflow "
                "liquidType=%d liquidReservoir=off physicalLiquidCrossing=inactive "
                "gasReservoir=x9a thermalGasInflow=preserved layers=%d coarseLayers=%d "
                "targetN=%.9g candidateCount=%s pool=%s species=%u\n",
                cfg.outletNeumannLiquidType0493x9b,
                cfg.outletNeumannReservoirLayers0493x8x,
                cfg.outletNeumannReservoirCoarseLayers0493x8x,
                cfg.outletNeumannReservoirTargetOccupancy0493x8y,
                neumann_resident_opt_0493x9d_fix1_enabled() ? "host_exact" : "host_legacy",
                neumann_recycle_pool_0493x9e_enabled() ? "recycle_deleted_plus_tail" :
                    (neumann_resident_opt_0493x9d_fix1_enabled() ? "persistent_exact_tail" : "legacy"),
                sc);
            announced0493x9b = true;
        } else if (cfg.outletNeumannZeroDriftOnBackflow0493x9a && !announced0493x9a) {
            std::fprintf(
                stderr,
                "[0493x9a-neumann] mode=virtual_pressure_reservoir_zero_drift_on_backflow "
                "layers=%d coarseLayers=%d support=face_count_fraction "
                "density=reference_target_occupancy targetN=%.9g population=poisson "
                "moments=species_coarse backflowGuard=zero_full_mean_drift thermalInflow=preserved "
                "independent=1 residentOutside=0 hostCountSync=legacy pool=legacy species=%u\n",
                cfg.outletNeumannReservoirLayers0493x8x,
                cfg.outletNeumannReservoirCoarseLayers0493x8x,
                cfg.outletNeumannReservoirTargetOccupancy0493x8y, sc);
            announced0493x9a = true;
        } else if (cfg.outletNeumannNoBackflowReservoir0493x8z && !announced0493x8z) {
            std::fprintf(
                stderr,
                "[0493x8z-neumann] mode=virtual_pressure_reservoir_no_backflow "
                "layers=%d coarseLayers=%d support=face_count_fraction "
                "density=reference_target_occupancy targetN=%.9g population=poisson "
                "moments=species_coarse normalMean=outward_clamp thermalInflow=preserved "
                "independent=1 residentOutside=0 hostCountSync=legacy pool=legacy species=%u\n",
                cfg.outletNeumannReservoirLayers0493x8x,
                cfg.outletNeumannReservoirCoarseLayers0493x8x,
                cfg.outletNeumannReservoirTargetOccupancy0493x8y, sc);
            announced0493x8z = true;
        } else if (cfg.outletNeumannPressureReservoir0493x8y && !announced0493x8y) {
            std::fprintf(
                stderr,
                "[0493x8y-neumann] mode=virtual_pressure_reservoir_cells "
                "layers=%d coarseLayers=%d support=face_count_fraction "
                "density=reference_target_occupancy targetN=%.9g population=poisson "
                "moments=species_coarse independent=1 residentOutside=0 "
                "hostCountSync=legacy pool=legacy species=%u\n",
                cfg.outletNeumannReservoirLayers0493x8x,
                cfg.outletNeumannReservoirCoarseLayers0493x8x,
                cfg.outletNeumannReservoirTargetOccupancy0493x8y, sc);
            announced0493x8y = true;
        } else if (!cfg.outletNeumannPressureReservoir0493x8y && !announced0493x8x) {
            std::fprintf(
                stderr,
                "[0493x8x-neumann] mode=virtual_reservoir_cells "
                "layers=%d coarseLayers=%d support=face_count_fraction "
                "density=coarse_total_occupancy population=poisson "
                "moments=species_coarse independent=1 residentOutside=0 "
                "hostCountSync=legacy pool=legacy species=%u\n",
                cfg.outletNeumannReservoirLayers0493x8x,
                cfg.outletNeumannReservoirCoarseLayers0493x8x, sc);
            announced0493x8x = true;
        }
        return cached;
    }
    cached.reservoirActive0493x8x = 0;
    cached.reservoirSpeciesCount0493x8x = 0u;

    if (virtualCellsActive0493x8w) {
        const std::size_t scSize = params.speciesDefinitions.size();
        if (scSize > static_cast<std::size_t>(
                std::numeric_limits<unsigned int>::max()))
            throw std::runtime_error(
                "0493x8w virtual-cell species count exceeds unsigned int");
        const unsigned int sc = static_cast<unsigned int>(scSize);
        if (cached.virtualSpeciesCapacity0493x8w < sc ||
            cached.virtualSpeciesTypes0493x8w == nullptr ||
            cached.virtualSpeciesFallbackKBT0493x8w == nullptr) {
            if (cached.virtualSpeciesTypes0493x8w)
                check_cuda_0263(cudaFree(cached.virtualSpeciesTypes0493x8w),
                                "resize 0493x8w virtual species types");
            if (cached.virtualSpeciesFallbackKBT0493x8w)
                check_cuda_0263(cudaFree(cached.virtualSpeciesFallbackKBT0493x8w),
                                "resize 0493x8w virtual species kBT");
            check_cuda_0263(cudaMalloc(
                &cached.virtualSpeciesTypes0493x8w,
                sizeof(std::uint32_t) * static_cast<std::size_t>(sc)),
                "allocate 0493x8w virtual species types");
            check_cuda_0263(cudaMalloc(
                &cached.virtualSpeciesFallbackKBT0493x8w,
                sizeof(double) * static_cast<std::size_t>(sc)),
                "allocate 0493x8w virtual species kBT");
            cached.virtualSpeciesCapacity0493x8w = sc;
        }

        std::vector<std::uint32_t> typesH(sc);
        std::vector<double> kbtH(sc);
        const double inheritedTarget = params.thermostatTargetKBT > 0.0
            ? params.thermostatTargetKBT : params.kBT;
        for (unsigned int si = 0u; si < sc; ++si) {
            const SpeciesDefinition& d =
                params.speciesDefinitions[static_cast<std::size_t>(si)];
            typesH[si] = d.type;
            double target = cfg.inletKBT;
            if (params.speciesThermostatEnable) {
                target = d.thermostatTargetKBTDeclared > 0.0
                    ? d.thermostatTargetKBTDeclared : inheritedTarget;
            }
            kbtH[si] = std::isfinite(target) && target > 0.0 ? target : 0.0;
        }
        check_cuda_0263(cudaMemcpy(
            cached.virtualSpeciesTypes0493x8w, typesH.data(),
            sizeof(std::uint32_t) * static_cast<std::size_t>(sc),
            cudaMemcpyHostToDevice),
            "upload 0493x8w virtual species types");
        check_cuda_0263(cudaMemcpy(
            cached.virtualSpeciesFallbackKBT0493x8w, kbtH.data(),
            sizeof(double) * static_cast<std::size_t>(sc),
            cudaMemcpyHostToDevice),
            "upload 0493x8w virtual species kBT");
        cached.virtualSpeciesCount0493x8w = sc;

        const unsigned int spatial = neumann_virtual_spatial_count_0493x8w(cfg);
        const std::uint64_t entries64 =
            static_cast<std::uint64_t>(spatial) * static_cast<std::uint64_t>(sc);
        if (entries64 > static_cast<std::uint64_t>(
                std::numeric_limits<unsigned int>::max()))
            throw std::runtime_error(
                "0493x8w virtual-cell moment size exceeds unsigned int");
        const unsigned int entries = static_cast<unsigned int>(entries64);
        if (cached.virtualMomentCapacity0493x8w < entries ||
            cached.virtualMoments0493x8w == nullptr) {
            if (cached.virtualMoments0493x8w)
                check_cuda_0263(cudaFree(cached.virtualMoments0493x8w),
                                "resize 0493x8w virtual moments");
            check_cuda_0263(cudaMalloc(
                &cached.virtualMoments0493x8w,
                sizeof(CudaNeumannVirtualCellMoments0493x8w) *
                    static_cast<std::size_t>(entries)),
                "allocate 0493x8w virtual moments");
            cached.virtualMomentCapacity0493x8w = entries;
        }
        cached.virtualMomentEntries0493x8w = entries;
        check_cuda_0263(cudaMemset(
            cached.virtualMoments0493x8w, 0,
            sizeof(CudaNeumannVirtualCellMoments0493x8w) *
                static_cast<std::size_t>(entries)),
            "clear 0493x8w virtual moments");

        // Candidate capacity is deliberately generous in the physics-first
        // implementation. It is based on all boundary cells, target occupancy
        // and virtual depth, not on the total resident particle count.
        const std::uint64_t layers = static_cast<std::uint64_t>(
            std::max(1, cfg.outletNeumannVirtualLayers0493x8w));
        const std::uint64_t perSpatial = static_cast<std::uint64_t>(
            std::max(64, 8 * std::max(1, cfg.inletTargetOccupancy) *
                             static_cast<int>(layers)));
        const std::uint64_t cap64 = std::max<std::uint64_t>(
            1024ULL, static_cast<std::uint64_t>(spatial) * perSpatial);
        if (cap64 > static_cast<std::uint64_t>(
                std::numeric_limits<unsigned int>::max()))
            throw std::runtime_error(
                "0493x8w virtual-cell candidate capacity exceeds unsigned int");
        const unsigned int cap = static_cast<unsigned int>(cap64);
        if (cached.virtualCapacity0493x8w < cap ||
            cached.virtualCandidates0493x8w == nullptr) {
            if (cached.virtualCandidates0493x8w)
                check_cuda_0263(cudaFree(cached.virtualCandidates0493x8w),
                                "resize 0493x8w virtual candidates");
            check_cuda_0263(cudaMalloc(
                &cached.virtualCandidates0493x8w,
                sizeof(CudaNeumannVirtualCellCandidate0493x8w) *
                    static_cast<std::size_t>(cap)),
                "allocate 0493x8w virtual candidates");
            cached.virtualCapacity0493x8w = cap;
        }
        if (cached.virtualCount0493x8w == nullptr) {
            check_cuda_0263(cudaMalloc(
                &cached.virtualCount0493x8w, sizeof(unsigned int)),
                "allocate 0493x8w virtual candidate count");
        }
        check_cuda_0263(cudaMemset(
            cached.virtualCount0493x8w, 0, sizeof(unsigned int)),
            "clear 0493x8w virtual candidate count");

        cached.virtualCellsActive0493x8w = 1;
        cached.replicaActive0493x8v = 0;
        cached.speciesCount0493x8r = 0u;
        cached.bathCells = 0u;
        static bool announced0493x8w = false;
        if (!announced0493x8w) {
            std::fprintf(
                stderr,
                "[0493x8w-neumann] mode=virtual_cells physics=streamed_independent "
                "layers=%d sourceCellLayers=1 species=%u "
                "residentOutside=0 hostCountSync=legacy pool=legacy\n",
                cfg.outletNeumannVirtualLayers0493x8w, sc);
            announced0493x8w = true;
        }
        return cached;
    }
    cached.virtualCellsActive0493x8w = 0;
    cached.virtualSpeciesCount0493x8w = 0u;

    const std::uint64_t boundaryCells =
        static_cast<std::uint64_t>(std::max(cfg.Nx, cfg.Ny));
    const std::uint64_t perCell = static_cast<std::uint64_t>(
        std::max(128, 4 * std::max(1, cfg.inletTargetOccupancy)));
    const std::uint64_t cap64 = std::min<std::uint64_t>(
        nActiveFluid, std::max<std::uint64_t>(1024ULL, boundaryCells * perCell));
    if (cap64 > static_cast<std::uint64_t>(
            std::numeric_limits<unsigned int>::max()))
        throw std::runtime_error(
            "0493x8q Neumann candidate capacity exceeds unsigned int");

    const unsigned int wanted = static_cast<unsigned int>(cap64);

    if (replicaActive0493x8v) {
        if (cached.replicaCapacity0493x8v < wanted ||
            cached.replicaCandidates0493x8v == nullptr) {
            if (cached.replicaCandidates0493x8v)
                check_cuda_0263(cudaFree(cached.replicaCandidates0493x8v),
                                "resize 0493x8v Neumann replica candidates");
            check_cuda_0263(cudaMalloc(
                &cached.replicaCandidates0493x8v,
                sizeof(CudaNeumannReplicaCandidate0493x8v) *
                    static_cast<std::size_t>(wanted)),
                "allocate 0493x8v Neumann replica candidates");
            cached.replicaCapacity0493x8v = wanted;
        }
        if (cached.replicaCount0493x8v == nullptr) {
            check_cuda_0263(cudaMalloc(
                &cached.replicaCount0493x8v, sizeof(unsigned int)),
                "allocate 0493x8v Neumann replica count");
        }
        check_cuda_0263(cudaMemset(
            cached.replicaCount0493x8v, 0, sizeof(unsigned int)),
            "clear 0493x8v Neumann replica count");
        cached.replicaActive0493x8v = 1;
        cached.speciesCount0493x8r = 0u;
        cached.bathCells = 0u;
        static bool announced0493x8v = false;
        if (!announced0493x8v) {
            std::fprintf(
                stderr,
                "[0493x8v-neumann] mode=microscopic_mirror_replica "
                "sourceLayers=%d bathMoments=off maxwellFit=off "
                "phaseSupport=labelled_local_source hostCountSync=legacy\n",
                cfg.outletNeumannReplicaSourceLayers0493x8v);
            announced0493x8v = true;
        }
        return cached;
    }
    cached.replicaActive0493x8v = 0;

    if (cached.capacity < wanted || cached.candidates == nullptr) {
        if (cached.candidates)
            check_cuda_0263(cudaFree(cached.candidates),
                            "resize 0493x8q Neumann candidates");
        check_cuda_0263(cudaMalloc(
            &cached.candidates,
            sizeof(CudaNeumannGhostCandidate0493x8q) *
                static_cast<std::size_t>(wanted)),
            "allocate 0493x8q Neumann candidates");
        cached.capacity = wanted;
    }
    if (cached.count == nullptr) {
        check_cuda_0263(cudaMalloc(&cached.count, sizeof(unsigned int)),
                        "allocate 0493x8q Neumann count");
    }

    const unsigned int spatialBathCount = neumann_bath_cell_count_0493x8q(cfg);
    const std::uint64_t wantedBath64 =
        static_cast<std::uint64_t>(spatialBathCount) *
        static_cast<std::uint64_t>(speciesCount0493x8r > 0u
            ? speciesCount0493x8r : 1u);
    if (wantedBath64 > static_cast<std::uint64_t>(
            std::numeric_limits<unsigned int>::max()))
        throw std::runtime_error(
            "0493x8r Neumann bath size exceeds unsigned int");
    const unsigned int wantedBath = static_cast<unsigned int>(wantedBath64);
    if (cached.bathCapacity < wantedBath || cached.bath == nullptr) {
        if (cached.bath)
            check_cuda_0263(cudaFree(cached.bath),
                            "resize 0493x8q Neumann bath");
        check_cuda_0263(cudaMalloc(
            &cached.bath,
            sizeof(CudaNeumannBathMoments0493x8q) *
                static_cast<std::size_t>(wantedBath)),
            "allocate 0493x8q Neumann bath");
        cached.bathCapacity = wantedBath;
    }
    cached.bathCells = wantedBath;

    check_cuda_0263(cudaMemset(cached.count, 0, sizeof(unsigned int)),
                    "clear 0493x8q Neumann count");
    check_cuda_0263(cudaMemset(
        cached.bath, 0,
        sizeof(CudaNeumannBathMoments0493x8q) *
            static_cast<std::size_t>(cached.bathCells)),
        "clear 0493x8q Neumann bath");

    return cached;
}



void launch_neumann_virtual_reservoir_accumulate_0493x8x(
    CudaParticleDeviceView view,
    std::uint64_t nActiveFluid,
    const CudaClassicSrcIoFullfaceConfig0263& cfg,
    const NeumannGhostWorkspace0493x8q& w,
    int threads,
    const char* label)
{
    if (!w.reservoirActive0493x8x ||
        w.reservoirSpeciesCount0493x8x == 0u || nActiveFluid == 0u) return;
    const std::uint64_t blocks64 =
        (nActiveFluid + static_cast<std::uint64_t>(threads) - 1u) /
        static_cast<std::uint64_t>(threads);
    if (blocks64 > static_cast<std::uint64_t>(2147483647))
        throw std::runtime_error(
            "0493x8x virtual-reservoir accumulation grid too large");
    io_neumann_virtual_reservoir_accumulate_kernel_0493x8x<<<
        static_cast<unsigned int>(blocks64), threads>>>(
        nActiveFluid, view.x, view.y, view.vx, view.vy, view.mass, view.type,
        view.role, kParticleRoleFluid, cfg,
        w.reservoirSpeciesTypes0493x8x, w.reservoirSpeciesCount0493x8x,
        w.reservoirMoments0493x8x, w.reservoirMomentEntries0493x8x);
    check_cuda_0263(cudaGetLastError(), label);
}

void launch_neumann_virtual_cell_accumulate_0493x8w(
    CudaParticleDeviceView view,
    std::uint64_t nActiveFluid,
    const CudaClassicSrcIoFullfaceConfig0263& cfg,
    const NeumannGhostWorkspace0493x8q& w,
    int threads,
    const char* label)
{
    if (!w.virtualCellsActive0493x8w ||
        w.virtualSpeciesCount0493x8w == 0u || nActiveFluid == 0u) return;
    const std::uint64_t blocks64 =
        (nActiveFluid + static_cast<std::uint64_t>(threads) - 1u) /
        static_cast<std::uint64_t>(threads);
    if (blocks64 > static_cast<std::uint64_t>(2147483647))
        throw std::runtime_error(
            "0493x8w virtual-cell accumulation grid too large");
    io_neumann_virtual_cell_accumulate_kernel_0493x8w<<<
        static_cast<unsigned int>(blocks64), threads>>>(
        nActiveFluid, view.x, view.y, view.vx, view.vy, view.mass, view.type,
        view.role, kParticleRoleFluid, cfg,
        w.virtualSpeciesTypes0493x8w, w.virtualSpeciesCount0493x8w,
        w.virtualMoments0493x8w, w.virtualMomentEntries0493x8w);
    check_cuda_0263(cudaGetLastError(), label);
}

void launch_neumann_species_bath_accumulate_0493x8r(
    CudaParticleDeviceView view,
    std::uint64_t nActiveFluid,
    const CudaClassicSrcIoFullfaceConfig0263& cfg,
    const NeumannGhostWorkspace0493x8q& w,
    int threads,
    const char* label)
{
    if (w.speciesCount0493x8r == 0u || nActiveFluid == 0u) return;
    const std::uint64_t blocks64 =
        (nActiveFluid + static_cast<std::uint64_t>(threads) - 1u) /
        static_cast<std::uint64_t>(threads);
    if (blocks64 > static_cast<std::uint64_t>(2147483647))
        throw std::runtime_error(
            "0493x8r Neumann species bath grid too large");
    io_neumann_species_bath_accumulate_kernel_0493x8r<<<
        static_cast<unsigned int>(blocks64), threads>>>(
        nActiveFluid, view.x, view.y, view.vx, view.vy, view.mass, view.type,
        view.role, kParticleRoleFluid, cfg,
        w.speciesTypes0493x8r, w.speciesCount0493x8r,
        w.bath, w.bathCells);
    check_cuda_0263(cudaGetLastError(), label);
}

unsigned int read_neumann_ghost_count_0493x8q(
    const NeumannGhostWorkspace0493x8q& w,
    const CudaClassicSrcIoFullfaceConfig0263& cfg,
    CudaParticleDeviceView view)
{
    if (w.reservoirActive0493x8x) {
        if (w.reservoirCount0493x8x == nullptr ||
            w.reservoirMoments0493x8x == nullptr ||
            w.reservoirMomentEntries0493x8x == 0u) return 0u;
        const int threads = 128;
        const unsigned int blocks =
            (w.reservoirMomentEntries0493x8x +
             static_cast<unsigned int>(threads) - 1u) /
            static_cast<unsigned int>(threads);
        io_neumann_virtual_reservoir_candidates_kernel_0493x8x<<<blocks, threads>>>(
            cfg, w.reservoirMoments0493x8x,
            w.reservoirMomentEntries0493x8x,
            w.reservoirSpeciesTypes0493x8x,
            w.reservoirSpeciesFallbackKBT0493x8x,
            w.reservoirSpeciesCount0493x8x,
            w.reservoirCandidates0493x8x, w.reservoirCount0493x8x,
            w.reservoirCapacity0493x8x);
        check_cuda_0263(cudaGetLastError(),
                        "io_neumann_virtual_reservoir_candidates_kernel_0493x8x launch");
        unsigned int n = 0u;
        check_cuda_0263(cudaMemcpy(
            &n, w.reservoirCount0493x8x, sizeof(unsigned int),
            cudaMemcpyDeviceToHost),
            "read 0493x8x virtual-reservoir candidate count");
        if (n > w.reservoirCapacity0493x8x)
            throw std::runtime_error(
                "0493x8x reservoir candidate buffer overflow count=" +
                std::to_string(n) + " capacity=" +
                std::to_string(w.reservoirCapacity0493x8x));
        return n;
    }

    if (w.virtualCellsActive0493x8w) {
        if (w.virtualCount0493x8w == nullptr ||
            w.virtualMoments0493x8w == nullptr ||
            w.virtualMomentEntries0493x8w == 0u) return 0u;
        const int threads = 128;
        const unsigned int blocks =
            (w.virtualMomentEntries0493x8w +
             static_cast<unsigned int>(threads) - 1u) /
            static_cast<unsigned int>(threads);
        io_neumann_virtual_cell_candidates_kernel_0493x8w<<<blocks, threads>>>(
            cfg, w.virtualMoments0493x8w, w.virtualMomentEntries0493x8w,
            w.virtualSpeciesTypes0493x8w,
            w.virtualSpeciesFallbackKBT0493x8w,
            w.virtualSpeciesCount0493x8w,
            w.virtualCandidates0493x8w, w.virtualCount0493x8w,
            w.virtualCapacity0493x8w);
        check_cuda_0263(cudaGetLastError(),
                        "io_neumann_virtual_cell_candidates_kernel_0493x8w launch");
        unsigned int n = 0u;
        check_cuda_0263(cudaMemcpy(
            &n, w.virtualCount0493x8w, sizeof(unsigned int),
            cudaMemcpyDeviceToHost),
            "read 0493x8w virtual-cell candidate count");
        if (n > w.virtualCapacity0493x8w)
            throw std::runtime_error(
                "0493x8w virtual-cell candidate buffer overflow count=" +
                std::to_string(n) + " capacity=" +
                std::to_string(w.virtualCapacity0493x8w));
        return n;
    }

    if (w.replicaActive0493x8v) {
        if (w.replicaCount0493x8v == nullptr) return 0u;
        unsigned int n = 0u;
        check_cuda_0263(cudaMemcpy(
            &n, w.replicaCount0493x8v, sizeof(unsigned int), cudaMemcpyDeviceToHost),
            "read 0493x8v Neumann replica count");
        if (n > w.replicaCapacity0493x8v)
            throw std::runtime_error(
                "0493x8v Neumann replica buffer overflow count=" +
                std::to_string(n) + " capacity=" +
                std::to_string(w.replicaCapacity0493x8v));
        return n;
    }
    if (w.count == nullptr || w.bath == nullptr || w.bathCells == 0u)
        return 0u;

    const int threads = 128;
    const unsigned int blocks =
        (w.bathCells + static_cast<unsigned int>(threads) - 1u) /
        static_cast<unsigned int>(threads);
    if (w.speciesCount0493x8r > 0u) {
        io_neumann_species_bath_candidates_kernel_0493x8r<<<blocks, threads>>>(
            view.n, view.mass, view.type, cfg,
            w.bath, w.bathCells, w.speciesTypes0493x8r,
            w.speciesFallbackKBT0493x8r, w.speciesCount0493x8r,
            w.candidates, w.count, w.capacity);
        check_cuda_0263(cudaGetLastError(),
                        "io_neumann_species_bath_candidates_kernel_0493x8r launch");
    } else {
        io_neumann_bath_candidates_kernel_0493x8q<<<blocks, threads>>>(
            view.n, view.mass, view.type, cfg,
            w.bath, w.bathCells,
            w.candidates, w.count, w.capacity);
        check_cuda_0263(cudaGetLastError(),
                        "io_neumann_bath_candidates_kernel_0493x8q launch");
    }

    unsigned int n = 0u;
    check_cuda_0263(cudaMemcpy(
        &n, w.count, sizeof(unsigned int), cudaMemcpyDeviceToHost),
        "read 0493x8q Neumann bath count");
    if (n > w.capacity)
        throw std::runtime_error(
            "0493x8q Neumann candidate buffer overflow count=" +
            std::to_string(n) +
            " capacity=" + std::to_string(w.capacity));
    return n;
}


void free_neumann_ghost_workspace_0493x8q(NeumannGhostWorkspace0493x8q& w)
{
    // Workspace is process-persistent and reused on the next timestep.
    // Only clear the local non-owning view.
    w = NeumannGhostWorkspace0493x8q{};
}


void launch_neumann_ghost_insert_0493x8q(
    CudaParticleDeviceView view,
    const CudaClassicSrcIoFullfaceConfig0263& cfg,
    const NeumannGhostWorkspace0493x8q& w,
    unsigned int ghostCount,
    const std::uint64_t* dInactiveIndices,
    unsigned int inactiveCount,
    CudaClassicSrcIoCounters0263* dCounters,
    int threads,
    const char* label)
{
    if (ghostCount == 0u) return;
    if (ghostCount > inactiveCount)
        throw std::runtime_error(
            "0493x8q insufficient inactive slots for Neumann bath");

    const unsigned int blocks =
        (ghostCount + static_cast<unsigned int>(threads) - 1u) /
        static_cast<unsigned int>(threads);
    if (w.reservoirActive0493x8x) {
        io_neumann_virtual_cell_insert_kernel_0493x8w<<<blocks, threads>>>(
            view.n, view.x, view.y, view.vx, view.vy, view.mass, view.type, view.role,
            kParticleRoleFluid, kParticleRoleInactive,
            w.reservoirCandidates0493x8x, ghostCount,
            dInactiveIndices, inactiveCount, dCounters);
    } else if (w.virtualCellsActive0493x8w) {
        io_neumann_virtual_cell_insert_kernel_0493x8w<<<blocks, threads>>>(
            view.n, view.x, view.y, view.vx, view.vy, view.mass, view.type, view.role,
            kParticleRoleFluid, kParticleRoleInactive,
            w.virtualCandidates0493x8w, ghostCount,
            dInactiveIndices, inactiveCount, dCounters);
    } else if (w.replicaActive0493x8v) {
        io_neumann_replica_insert_kernel_0493x8v<<<blocks, threads>>>(
            view.n, view.x, view.y, view.vx, view.vy, view.mass, view.type, view.role,
            kParticleRoleFluid, kParticleRoleInactive, cfg,
            w.replicaCandidates0493x8v, ghostCount,
            dInactiveIndices, inactiveCount, dCounters);
    } else if (w.speciesCount0493x8r > 0u) {
        io_neumann_species_ghost_insert_kernel_0493x8r<<<blocks, threads>>>(
            view.n, view.x, view.y, view.vx, view.vy, view.mass, view.type, view.role,
            kParticleRoleFluid, kParticleRoleInactive, cfg,
            w.candidates, ghostCount, w.bath, w.bathCells,
            w.speciesCount0493x8r,
            dInactiveIndices, inactiveCount, dCounters);
    } else {
        io_neumann_ghost_insert_kernel_0493x8q<<<blocks, threads>>>(
            view.n, view.x, view.y, view.vx, view.vy, view.mass, view.type, view.role,
            kParticleRoleFluid, kParticleRoleInactive, cfg,
            w.candidates, ghostCount, w.bath, w.bathCells,
            dInactiveIndices, inactiveCount, dCounters);
    }
    check_cuda_0263(cudaGetLastError(), label);
}


CudaClassicSrcIoResident0263Diagnostics try_apply_cuda_classic_src_io_fullface_boundary_0263(
    ParticleState& state,
    const SimulationParams& params,
    const FluidDomainBounds& domain,
    std::uint64_t step,
    double time)
{
    CudaClassicSrcIoResident0263Diagnostics diag{};
    diag.requested = cuda_classic_src_io_fullface_resident_0263_requested();
    diag.supported = cuda_classic_src_io_fullface_resident_0263_supported(params);
    const std::uint64_t nActiveFluid = active_fluid_count(state);
    diag.particles = nActiveFluid;
    if (!diag.requested || !diag.supported || nActiveFluid == 0u) return diag;
    if (!cuda_particle_state_available()) return diag;
    if (!cuda_shared_particle_state_0251_is_fresh()) {
        const bool strict = env_truthy_0263("MPCD_CUDA_CLASSIC_SRC_IO_FULLFACE_RESIDENT_0263_STRICT");
        if (strict) {
            throw std::runtime_error(std::string("0263 boundary requested but shared CUDA state is stale; lastWriter=") +
                                     cuda_shared_particle_state_0251_last_writer() +
                                     " lastInvalidator=" + cuda_shared_particle_state_0251_last_invalidator());
        }
        return diag;
    }

    const auto t0 = Clock::now();
    CudaParticleStateDiagnostics particleDiag{};
    CudaParticleState& gpuState = shared_state_0263();
    const auto tAfterUpload = Clock::now();

    const bool residentOpt0493x9dFix1 = neumann_resident_opt_0493x9d_fix1_enabled();
    const bool recycleOpt0493x9e = neumann_recycle_pool_0493x9e_enabled();
    NeumannRecycleWorkspace0493x9e* recycleWorkspace0493x9e = nullptr;
    if (recycleOpt0493x9e) {
        recycleWorkspace0493x9e = &prepare_neumann_recycle_workspace_0493x9e(nActiveFluid);
    }
    CudaClassicSrcIoCounters0263* dCounters = nullptr;
    if (residentOpt0493x9dFix1) {
        dCounters = acquire_boundary_counters_0493x9d_fix1(
            "allocate 0493x9d-fix1 counters",
            "clear 0493x9d-fix1 counters");
    } else {
        check_cuda_0263(cudaMalloc(&dCounters, sizeof(CudaClassicSrcIoCounters0263)), "allocate counters");
        check_cuda_0263(cudaMemset(dCounters, 0, sizeof(CudaClassicSrcIoCounters0263)), "clear counters");
    }
    const CudaClassicSrcIoFullfaceConfig0263 cfg = make_config_0263(state, params, domain, step, time);
    CudaParticleDeviceView view = gpuState.device_view();
    std::uint64_t activePrefixCompactTailScan0315c = 0u;
    const std::uint64_t oldActivePrefix0315c = nActiveFluid;
    std::uint64_t recyclePoolNeed0493x9eFix3 = 0u;
    const bool serialBoundary0267 =
        env_truthy_0263("MPCD_CUDA_CLASSIC_SRC_IO_RESIDENT_0267_SERIAL_BOUNDARY") &&
        !cfg.outletNeumannKinetic0493x8q &&
        !cfg.segmentedMultiAxis0414;
    NeumannGhostWorkspace0493x8q ghostWorkspace0493x8q =
        prepare_neumann_ghost_candidates_0493x8q(cfg, params, nActiveFluid);
    if (serialBoundary0267) {
        io_fullface_hard_reservoir_kernel_0263<<<1, 1>>>(
            view.n, view.x, view.y, view.vx, view.vy, view.mass, view.type, view.role,
            kParticleRoleFluid, kParticleRoleInactive, cfg, dCounters);
        check_cuda_0263(cudaGetLastError(), "io_fullface_hard_reservoir_kernel_0263 launch");
    } else {
        const int boundaryThreads = env_int_0263("MPCD_CUDA_CLASSIC_SRC_IO_RESIDENT_0267_BOUNDARY_THREADS",
                                                env_int_0263("MPCD_CUDA_CLASSIC_SRC_IO_FULLFACE_RESIDENT_0263_THREADS", 256));
        const std::uint64_t boundaryBlocks64 = (nActiveFluid + static_cast<std::uint64_t>(boundaryThreads) - 1u) /
                                               static_cast<std::uint64_t>(boundaryThreads);
        if (boundaryBlocks64 > static_cast<std::uint64_t>(2147483647)) {
            throw std::runtime_error("cuda_classic_src_io_resident_0263: grid too large for 0267 full-face boundary launch");
        }
        launch_neumann_virtual_reservoir_accumulate_0493x8x(
            view, nActiveFluid, cfg, ghostWorkspace0493x8q, boundaryThreads,
            "io_fullface_neumann_virtual_reservoir_accumulate_kernel_0493x8x launch");
        launch_neumann_virtual_cell_accumulate_0493x8w(
            view, nActiveFluid, cfg, ghostWorkspace0493x8q, boundaryThreads,
            "io_fullface_neumann_virtual_cell_accumulate_kernel_0493x8w launch");
        launch_neumann_species_bath_accumulate_0493x8r(
            view, nActiveFluid, cfg, ghostWorkspace0493x8q, boundaryThreads,
            "io_fullface_neumann_species_bath_accumulate_kernel_0493x8r launch");
        CudaClassicSrcIoFullfaceConfig0263 boundaryCfgNeumann0493x8x = cfg;
        if (ghostWorkspace0493x8q.reservoirActive0493x8x ||
            ghostWorkspace0493x8q.virtualCellsActive0493x8w ||
            ghostWorkspace0493x8q.speciesCount0493x8r > 0u)
            boundaryCfgNeumann0493x8x.outletNeumannKinetic0493x8q = 0;
        io_fullface_boundary_particles_kernel_0267<<<static_cast<unsigned int>(boundaryBlocks64), boundaryThreads>>>(
            nActiveFluid, view.x, view.y, view.vx, view.vy, view.mass, view.role,
            kParticleRoleFluid, kParticleRoleInactive, boundaryCfgNeumann0493x8x, dCounters,
            ghostWorkspace0493x8q.candidates, ghostWorkspace0493x8q.count,
            ghostWorkspace0493x8q.capacity,
            ghostWorkspace0493x8q.bath, ghostWorkspace0493x8q.bathCells,
            ghostWorkspace0493x8q.replicaCandidates0493x8v,
            ghostWorkspace0493x8q.replicaCount0493x8v,
            ghostWorkspace0493x8q.replicaCapacity0493x8v,
            recycleWorkspace0493x9e != nullptr ? recycleWorkspace0493x9e->deletedIndices : nullptr,
            recycleWorkspace0493x9e != nullptr ? recycleWorkspace0493x9e->deletedCount : nullptr,
            recycleWorkspace0493x9e != nullptr ? recycleWorkspace0493x9e->deletedCapacity : 0u);
        check_cuda_0263(cudaGetLastError(), "io_fullface_boundary_particles_kernel_0267 launch");

        const bool usePoolInsert0268 = !cfg.segmentedEnable &&
            !env_truthy_0263("MPCD_CUDA_CLASSIC_SRC_IO_RESIDENT_0268_DISABLE_POOL");
        const unsigned long long equilibriumPredictedInsertions0293 = cfg.segmentedEnable
            ? segmented_reservoir_target_particles_host_0293(cfg)
            : fullface_reservoir_target_particles_host_0293(cfg);
        // 0293: outlet extraction must run before hard inlet insertion.
        // Otherwise equilibrium/forced outlet modes may be too late to free
        // inactive slots and the inlet pool can overflow even though an outlet
        // extraction was requested for the same step.
        maybe_apply_forced_outlet_extraction_0291(view, cfg, dCounters,
                                                  "io_fullface_pre_insert_outlet_extraction_kernel_0293 launch",
                                                  equilibriumPredictedInsertions0293,
                                                  recycleWorkspace0493x9e != nullptr ? recycleWorkspace0493x9e->deletedIndices : nullptr,
                                                  recycleWorkspace0493x9e != nullptr ? recycleWorkspace0493x9e->deletedCount : nullptr,
                                                  recycleWorkspace0493x9e != nullptr ? recycleWorkspace0493x9e->deletedCapacity : 0u);
        // x9d-fix1: read_neumann_ghost_count_0493x8q() performs a blocking
        // D->H copy on the same default stream, so this explicit device-wide
        // synchronization is redundant.  Keep it for the exact x9c path.
        if (!residentOpt0493x9dFix1)
            check_cuda_0263(cudaDeviceSynchronize(),
                            "io_fullface_pre_insert_outlet_extraction_kernel_0293 synchronize");
        const unsigned int ghostCount0493x8q =
            read_neumann_ghost_count_0493x8q(ghostWorkspace0493x8q, cfg, view);
        if (usePoolInsert0268) {
            const int poolThreads = env_int_0263("MPCD_CUDA_CLASSIC_SRC_IO_RESIDENT_0268_POOL_THREADS", boundaryThreads);
            const std::uint64_t reservoirCells = fullface_reservoir_cell_count_host_0268(cfg);
            const std::uint64_t reservoirPoolNeed0493x8q = std::max<std::uint64_t>(
                reservoirCells * static_cast<std::uint64_t>(std::max(0, cfg.inletTargetOccupancy)),
                static_cast<std::uint64_t>(equilibriumPredictedInsertions0293));
            const std::uint64_t neededInactive =
                static_cast<std::uint64_t>(ghostCount0493x8q) + reservoirPoolNeed0493x8q;
            std::uint64_t* dInactiveIndices = nullptr;
            unsigned int inactiveCount = 0u;
            bool persistentTailPool0493x9dFix1 = false;
            bool usedTailPool0313 = false;
            bool usedRecyclePool0493x9e = false;
            unsigned int* dInactiveFlags = nullptr;
            unsigned int* dInactivePrefix = nullptr;
            if (recycleOpt0493x9e) {
                recyclePoolNeed0493x9eFix3 = neededInactive;
                dInactiveIndices = build_recycled_inactive_pool_0493x9e(
                    neededInactive, oldActivePrefix0315c, view,
                    kParticleRoleInactive, dCounters, poolThreads);
                inactiveCount = static_cast<unsigned int>(neededInactive);
                usedRecyclePool0493x9e = true;
            } else {
                const std::uint64_t tailScanForPool0315c = inactive_tail_scan_count_0313(view.n, neededInactive);
                usedTailPool0313 = collect_tail_inactive_pool_0313(
                view.n, view.role, kParticleRoleInactive, neededInactive, poolThreads,
                    &dInactiveIndices, &inactiveCount, &persistentTailPool0493x9dFix1);
                if (usedTailPool0313) activePrefixCompactTailScan0315c = std::max(activePrefixCompactTailScan0315c, tailScanForPool0315c);

                if (!usedTailPool0313) {
                if (view.n > static_cast<std::uint64_t>(std::numeric_limits<unsigned int>::max())) {
                    throw std::runtime_error("cuda_classic_src_io_resident_0263: too many particles for 0268 inactive-prefix pool");
                }
                const unsigned int n32 = static_cast<unsigned int>(view.n);
                check_cuda_0263(cudaMalloc(&dInactiveFlags, sizeof(unsigned int) * static_cast<std::size_t>(n32)),
                                "allocate 0268 inactive flags");
                check_cuda_0263(cudaMalloc(&dInactivePrefix, sizeof(unsigned int) * static_cast<std::size_t>(n32)),
                                "allocate 0268 inactive prefix");
                check_cuda_0263(cudaMalloc(&dInactiveIndices, sizeof(std::uint64_t) * static_cast<std::size_t>(n32)),
                                "allocate 0268 inactive index pool");

                const std::uint64_t poolBlocks64 = (view.n + static_cast<std::uint64_t>(poolThreads) - 1u) /
                                                   static_cast<std::uint64_t>(poolThreads);
                if (poolBlocks64 > static_cast<std::uint64_t>(2147483647)) {
                    throw std::runtime_error("cuda_classic_src_io_resident_0263: grid too large for 0268 inactive pool launch");
                }
                io_fullface_mark_inactive_flags_kernel_0268<<<static_cast<unsigned int>(poolBlocks64), poolThreads>>>(
                    view.n, view.role, kParticleRoleInactive, dInactiveFlags);
                check_cuda_0263(cudaGetLastError(), "io_fullface_mark_inactive_flags_kernel_0268 launch");
                thrust::exclusive_scan(thrust::device, dInactiveFlags, dInactiveFlags + n32, dInactivePrefix);
                check_cuda_0263(cudaGetLastError(), "io_fullface inactive prefix scan 0268");
                io_fullface_compact_inactive_slots_kernel_0268<<<static_cast<unsigned int>(poolBlocks64), poolThreads>>>(
                    view.n, view.role, kParticleRoleInactive, dInactivePrefix, dInactiveIndices);
                check_cuda_0263(cudaGetLastError(), "io_fullface_compact_inactive_slots_kernel_0268 launch");

                unsigned int lastFlag = 0u;
                unsigned int lastPrefix = 0u;
                if (n32 > 0u) {
                    check_cuda_0263(cudaMemcpy(&lastFlag, dInactiveFlags + (n32 - 1u), sizeof(unsigned int), cudaMemcpyDeviceToHost),
                                    "copy 0268 inactive last flag");
                    check_cuda_0263(cudaMemcpy(&lastPrefix, dInactivePrefix + (n32 - 1u), sizeof(unsigned int), cudaMemcpyDeviceToHost),
                                    "copy 0268 inactive last prefix");
                }
                    inactiveCount = lastPrefix + lastFlag;
                }
            }

            launch_neumann_ghost_insert_0493x8q(
                view, cfg, ghostWorkspace0493x8q, ghostCount0493x8q,
                dInactiveIndices, inactiveCount, dCounters, poolThreads,
                "io_fullface_neumann_ghost_insert_0493x8q launch");
            if (reservoirCells > 0u) {
                const int insertThreads = env_int_0263("MPCD_CUDA_CLASSIC_SRC_IO_RESIDENT_0268_INSERT_THREADS", 128);
                const std::uint64_t insertBlocks64 = (reservoirCells + static_cast<std::uint64_t>(insertThreads) - 1u) /
                                                     static_cast<std::uint64_t>(insertThreads);
                if (insertBlocks64 > static_cast<std::uint64_t>(2147483647)) {
                    throw std::runtime_error("cuda_classic_src_io_resident_0263: grid too large for 0268 full-face insert launch");
                }
                io_fullface_hard_reservoir_insert_pool_kernel_0268<<<static_cast<unsigned int>(insertBlocks64), insertThreads>>>(
                    view.x, view.y, view.vx, view.vy, view.mass, view.type, view.role,
                    kParticleRoleFluid, kParticleRoleInactive, cfg,
                    dInactiveIndices, inactiveCount,
                    static_cast<std::uint64_t>(ghostCount0493x8q), dCounters);
                check_cuda_0263(cudaGetLastError(), "io_fullface_hard_reservoir_insert_pool_kernel_0268 launch");
            }
            if (dInactiveFlags != nullptr) check_cuda_0263(cudaFree(dInactiveFlags), "free 0268 inactive flags");
            if (dInactivePrefix != nullptr) check_cuda_0263(cudaFree(dInactivePrefix), "free 0268 inactive prefix");
            if (dInactiveIndices != nullptr && !usedRecyclePool0493x9e && !persistentTailPool0493x9dFix1)
                check_cuda_0263(cudaFree(dInactiveIndices),
                                usedTailPool0313 ? "free 0313 inactive tail index pool"
                                                : "free 0268 inactive index pool");
        } else {
            io_fullface_hard_reservoir_insert_kernel_0267<<<1, 1>>>(
                view.n, view.x, view.y, view.vx, view.vy, view.mass, view.type, view.role,
                kParticleRoleFluid, kParticleRoleInactive, cfg, dCounters);
            check_cuda_0263(cudaGetLastError(), "io_fullface_hard_reservoir_insert_kernel_0267 launch");
        }
    }
    check_cuda_0263(cudaDeviceSynchronize(), serialBoundary0267 ?
                    "io_fullface_hard_reservoir_kernel_0263 synchronize" :
                    "io_fullface_boundary_insert_0267 synchronize");
    const auto tAfterKernel = Clock::now();    free_neumann_ghost_workspace_0493x8q(ghostWorkspace0493x8q);


    CudaClassicSrcIoCounters0263 h{};
    check_cuda_0263(cudaMemcpy(&h, dCounters, sizeof(CudaClassicSrcIoCounters0263), cudaMemcpyDeviceToHost), "copy counters");
    if (!residentOpt0493x9dFix1)
        check_cuda_0263(cudaFree(dCounters), "free counters");
    if (h.failureFlag != 0) {
        throw std::runtime_error("cuda_classic_src_io_resident_0263: non-finite particle or too many wall reflections in boundary kernel");
    }
    if (h.overflowFlag != 0) {
        throw std::runtime_error(
            std::string("cuda_classic_src_io_resident_0263: Reservoir exhausted at step ") +
            std::to_string(static_cast<unsigned long long>(cfg.step)) +
            " in full-face hard inlet reservoir; GPU append is disabled. Increase inactive slots or reduce the net injected flux. Details: " +
            "reservoirCells=" + std::to_string(static_cast<unsigned long long>(h.inletReservoirCells)) +
            " targetParticles=" + std::to_string(static_cast<unsigned long long>(h.inletReservoirTargetParticles)) +
            " reservoirDeleted=" + std::to_string(static_cast<unsigned long long>(h.inletReservoirDeleted)) +
            " outletDeleted=" + std::to_string(static_cast<unsigned long long>(h.outletParticlesDeleted)) +
            " insertedBeforeOverflow=" + std::to_string(static_cast<unsigned long long>(h.inletParticlesInserted)) +
            " fluidAfterBoundary=" + std::to_string(static_cast<unsigned long long>(h.fluidParticles)));
    }

    CudaParticleStateDiagnostics prefixRepairDiag{};
    const std::uint64_t deleted0315c = static_cast<std::uint64_t>(h.inletReservoirDeleted + h.inletBackflowDeleted + h.outletParticlesDeleted);
    if (deleted0315c > oldActivePrefix0315c) {
        throw std::runtime_error("cuda_classic_src_io_resident_0263: 0315c deletion count exceeds active prefix");
    }
    const std::uint64_t expectedActive0315c = oldActivePrefix0315c - deleted0315c +
                                             static_cast<std::uint64_t>(h.inletParticlesInserted + h.outletParticlesInserted);
    int targetedRepairStatus0493x9eFix3 = 0;
    const bool targetedRepair0493x9eFix3 = recycleOpt0493x9e &&
        try_targeted_prefix_repair_0493x9e_fix3(
            gpuState, state, oldActivePrefix0315c, expectedActive0315c,
            recyclePoolNeed0493x9eFix3, deleted0315c,
            prefixRepairDiag, targetedRepairStatus0493x9eFix3);

    std::uint64_t actualActive0315c = expectedActive0315c;
    if (targetedRepair0493x9eFix3) {
        static bool announcedTargetedRepair0493x9eFix3 = false;
        if (!announcedTargetedRepair0493x9eFix3) {
            std::fprintf(stderr,
                "[0493x9e-fastpath] prefixRepair=targeted_deleted_list_exact fallback=0315c_exact\n");
            announcedTargetedRepair0493x9eFix3 = true;
        }
    } else {
        if (recycleOpt0493x9e) {
            static bool announcedTargetedFallback0493x9eFix3 = false;
            if (!announcedTargetedFallback0493x9eFix3) {
                std::fprintf(stderr,
                    "[0493x9e-fallback] prefixRepair=0315c_exact targetedStatus=%d\n",
                    targetedRepairStatus0493x9eFix3);
                announcedTargetedFallback0493x9eFix3 = true;
            }
        }
        actualActive0315c = compact_active_prefix_device_0315c(
            gpuState, state, oldActivePrefix0315c, expectedActive0315c,
            activePrefixCompactTailScan0315c, prefixRepairDiag);
    }
    // 0315d: keep the device state authoritative after inlet/outlet mutation.
    // The 0315c-fix06 eager host mirror was functionally safe but expensive
    // for large active prefixes.  By default we now update only the logical
    // active count on the host; runtime summaries/dumps pull an active-prefix
    // mirror lazily through cuda_shared_particle_state_0251_download_if_fresh().
    // Use MPCD_CUDA_ACTIVE_PREFIX_EAGER_HOST_MIRROR_0315D=1 for legacy
    // step-by-step debugging.
    if (env_truthy_0263("MPCD_CUDA_ACTIVE_PREFIX_EAGER_HOST_MIRROR_0315D")) {
        gpuState.download_active_prefix(state, &prefixRepairDiag);
    } else {
        state.NactiveFluid = actualActive0315c;
    }
    cuda_shared_particle_state_0251_mark_fresh("classic_src_io_fullface_boundary_0263_prefix_compacted_0315c");
    const auto tAfterDownload = Clock::now();

    BoundaryDiagnostics b{};
    b.inletHardReservoirEnabled = 1;
    b.hitsLeft = static_cast<std::uint64_t>(h.hitsLeft);
    b.hitsRight = static_cast<std::uint64_t>(h.hitsRight);
    b.hitsBottom = static_cast<std::uint64_t>(h.hitsBottom);
    b.hitsTop = static_cast<std::uint64_t>(h.hitsTop);
    b.inletReservoirCells = static_cast<std::uint64_t>(h.inletReservoirCells);
    b.inletReservoirTargetParticles = static_cast<std::uint64_t>(h.inletReservoirTargetParticles);
    b.inletReservoirDeleted = static_cast<std::uint64_t>(h.inletReservoirDeleted);
    b.inletBackflowDeleted = static_cast<std::uint64_t>(h.inletBackflowDeleted);
    b.outletParticlesDeleted = static_cast<std::uint64_t>(h.outletParticlesDeleted);
    b.outletParticlesInserted = static_cast<std::uint64_t>(h.outletParticlesInserted);
    b.inletParticlesInserted = static_cast<std::uint64_t>(h.inletParticlesInserted);
    const std::int64_t deleted = static_cast<std::int64_t>(b.inletReservoirDeleted + b.inletBackflowDeleted + b.outletParticlesDeleted);
    b.inletNetParticleDelta = static_cast<std::int64_t>(b.inletParticlesInserted) + static_cast<std::int64_t>(b.outletParticlesInserted) - deleted;
    b.inletReservoirMeanN = b.inletReservoirCells == 0u ? 0.0 : static_cast<double>(std::max(0, params.inletTargetOccupancy));
    b.inletReservoirStdN = 0.0;
    b.inletReservoirMinN = b.inletReservoirCells == 0u ? 0u : static_cast<std::uint32_t>(std::max(0, params.inletTargetOccupancy));
    b.inletReservoirMaxN = b.inletReservoirCells == 0u ? 0u : static_cast<std::uint32_t>(std::max(0, params.inletTargetOccupancy));
    b.inletReservoirEmptyFraction = b.inletReservoirCells == 0u ? 0.0 : (params.inletTargetOccupancy == 0 ? 1.0 : 0.0);
    if (b.inletParticlesInserted > 0u) {
        const double inserted = static_cast<double>(b.inletParticlesInserted);
        b.inletMeanUx = h.inletMeanUxSum / inserted;
        b.inletMeanUy = h.inletMeanUySum / inserted;
        b.inletKBT = h.inletKbtNumerator / (2.0 * inserted);
    }
    b.maxYWallReflectionsPerParticle = h.maxYReflections;

    diag.handled = true;
    diag.applied = true;
    diag.boundary = b;
    diag.fluidParticles = actualActive0315c;
    diag.allocationCalls = particleDiag.allocationCalls + prefixRepairDiag.allocationCalls;
    diag.uploadCalls = particleDiag.uploadCalls + prefixRepairDiag.uploadCalls;
    diag.downloadCalls = particleDiag.downloadCalls + prefixRepairDiag.downloadCalls;
    diag.uploadSeconds = elapsed_0263(t0, tAfterUpload) + prefixRepairDiag.uploadSeconds;
    diag.kernelSeconds = elapsed_0263(tAfterUpload, tAfterKernel) + prefixRepairDiag.kernelSeconds;
    diag.downloadSeconds = 0.0;
    diag.totalSeconds = elapsed_0263(t0, tAfterDownload);
    return diag;
}

CudaClassicSrcIoResident0263Diagnostics try_apply_cuda_classic_src_io_segmented_stream_0264(
    ParticleState& state,
    const SimulationParams& params,
    const FluidDomainBounds& domain,
    std::uint64_t step)
{
    CudaClassicSrcIoResident0263Diagnostics diag{};
    diag.requested = cuda_classic_src_io_segmented_resident_0264_requested();
    diag.supported = cuda_classic_src_io_segmented_resident_0264_supported(params);
    const std::uint64_t nActiveFluid = active_fluid_count(state);
    diag.particles = nActiveFluid;
    if (!diag.requested || !diag.supported || nActiveFluid == 0u) return diag;
    if (!cuda_particle_state_available()) return diag;

    const auto t0 = Clock::now();
    CudaParticleStateDiagnostics particleDiag{};
    CudaParticleState& gpuState = shared_state_0263();
    if (!cuda_shared_particle_state_0251_is_fresh()) {
        gpuState.upload_all(state, &particleDiag);
    }
    const auto tAfterUpload = Clock::now();

    const CudaClassicSrcIoFullfaceConfig0263 cfg = make_config_0263(
        state, params, domain, step, static_cast<double>(step) * params.dt);
    const int threads = env_int_0263("MPCD_CUDA_CLASSIC_SRC_IO_SEGMENTED_RESIDENT_0264_THREADS",
                                     env_int_0263("MPCD_CUDA_CLASSIC_SRC_IO_FULLFACE_RESIDENT_0263_THREADS", 256));
    const std::uint64_t blocks64 = (nActiveFluid + static_cast<std::uint64_t>(threads) - 1u) /
                                   static_cast<std::uint64_t>(threads);
    if (blocks64 > static_cast<std::uint64_t>(2147483647)) {
        throw std::runtime_error("cuda_classic_src_io_resident_0263: grid too large for segmented stream launch");
    }
    CudaParticleDeviceView view = gpuState.device_view();
    io_fullface_force_stream_kernel_0263<<<static_cast<unsigned int>(blocks64), threads>>>(
        nActiveFluid, view.x, view.y, view.vx, view.vy, view.role, kParticleRoleFluid, cfg);
    check_cuda_0263(cudaGetLastError(), "io_segmented_force_stream_kernel_0264 launch");
    check_cuda_0263(cudaDeviceSynchronize(), "io_segmented_force_stream_kernel_0264 synchronize");
    cuda_shared_particle_state_0251_mark_fresh("classic_src_io_segmented_stream_0264");
    const auto tAfterKernel = Clock::now();

    diag.handled = true;
    diag.applied = true;
    diag.allocationCalls = particleDiag.allocationCalls;
    diag.uploadCalls = particleDiag.uploadCalls;
    diag.downloadCalls = particleDiag.downloadCalls;
    diag.uploadSeconds = elapsed_0263(t0, tAfterUpload);
    diag.kernelSeconds = elapsed_0263(tAfterUpload, tAfterKernel);
    diag.downloadSeconds = 0.0;
    diag.totalSeconds = elapsed_0263(t0, tAfterKernel);
    return diag;
}

CudaClassicSrcIoResident0263Diagnostics try_apply_cuda_classic_src_io_segmented_boundary_0264(
    ParticleState& state,
    const SimulationParams& params,
    const FluidDomainBounds& domain,
    std::uint64_t step,
    double time)
{
    CudaClassicSrcIoResident0263Diagnostics diag{};
    diag.requested = cuda_classic_src_io_segmented_resident_0264_requested();
    diag.supported = cuda_classic_src_io_segmented_resident_0264_supported(params);
    const std::uint64_t nActiveFluid = active_fluid_count(state);
    diag.particles = nActiveFluid;
    if (!diag.requested || !diag.supported || nActiveFluid == 0u) return diag;
    if (!cuda_particle_state_available()) return diag;
    if (!cuda_shared_particle_state_0251_is_fresh()) {
        const bool strict = env_truthy_0263("MPCD_CUDA_CLASSIC_SRC_IO_SEGMENTED_RESIDENT_0264_STRICT");
        if (strict) {
            throw std::runtime_error(std::string("0264 boundary requested but shared CUDA state is stale; lastWriter=") +
                                     cuda_shared_particle_state_0251_last_writer() +
                                     " lastInvalidator=" + cuda_shared_particle_state_0251_last_invalidator());
        }
        return diag;
    }

    const auto t0 = Clock::now();
    CudaParticleStateDiagnostics particleDiag{};
    CudaParticleState& gpuState = shared_state_0263();
    const auto tAfterUpload = Clock::now();

    const bool residentOpt0493x9dFix1 = neumann_resident_opt_0493x9d_fix1_enabled();
    const bool recycleOpt0493x9e = neumann_recycle_pool_0493x9e_enabled();
    NeumannRecycleWorkspace0493x9e* recycleWorkspace0493x9e = nullptr;
    if (recycleOpt0493x9e) {
        recycleWorkspace0493x9e = &prepare_neumann_recycle_workspace_0493x9e(nActiveFluid);
    }
    CudaClassicSrcIoCounters0263* dCounters = nullptr;
    if (residentOpt0493x9dFix1) {
        dCounters = acquire_boundary_counters_0493x9d_fix1(
            "allocate 0493x9d-fix1 segmented counters",
            "clear 0493x9d-fix1 segmented counters");
    } else {
        check_cuda_0263(cudaMalloc(&dCounters, sizeof(CudaClassicSrcIoCounters0263)), "allocate segmented counters");
        check_cuda_0263(cudaMemset(dCounters, 0, sizeof(CudaClassicSrcIoCounters0263)), "clear segmented counters");
    }
    const CudaClassicSrcIoFullfaceConfig0263 cfg = make_config_0263(state, params, domain, step, time);
    CudaParticleDeviceView view = gpuState.device_view();
    std::uint64_t activePrefixCompactTailScan0315c = 0u;
    const std::uint64_t oldActivePrefix0315c = nActiveFluid;
    std::uint64_t recyclePoolNeed0493x9eFix3 = 0u;
    const bool serialBoundary0267 =
        env_truthy_0263("MPCD_CUDA_CLASSIC_SRC_IO_RESIDENT_0267_SERIAL_BOUNDARY") &&
        !cfg.outletNeumannKinetic0493x8q &&
        !cfg.segmentedMultiAxis0414;
    NeumannGhostWorkspace0493x8q ghostWorkspace0493x8q =
        prepare_neumann_ghost_candidates_0493x8q(cfg, params, nActiveFluid);
    if (serialBoundary0267) {
        io_fullface_hard_reservoir_kernel_0263<<<1, 1>>>(
            view.n, view.x, view.y, view.vx, view.vy, view.mass, view.type, view.role,
            kParticleRoleFluid, kParticleRoleInactive, cfg, dCounters);
        check_cuda_0263(cudaGetLastError(), "io_segmented_hard_reservoir_kernel_0264 launch");
    } else {
        const int boundaryThreads = env_int_0263("MPCD_CUDA_CLASSIC_SRC_IO_RESIDENT_0267_BOUNDARY_THREADS",
                                                env_int_0263("MPCD_CUDA_CLASSIC_SRC_IO_SEGMENTED_RESIDENT_0264_THREADS",
                                                            env_int_0263("MPCD_CUDA_CLASSIC_SRC_IO_FULLFACE_RESIDENT_0263_THREADS", 256)));
        const std::uint64_t boundaryBlocks64 = (nActiveFluid + static_cast<std::uint64_t>(boundaryThreads) - 1u) /
                                               static_cast<std::uint64_t>(boundaryThreads);
        if (boundaryBlocks64 > static_cast<std::uint64_t>(2147483647)) {
            throw std::runtime_error("cuda_classic_src_io_resident_0263: grid too large for 0267 segmented boundary launch");
        }
        launch_neumann_virtual_reservoir_accumulate_0493x8x(
            view, nActiveFluid, cfg, ghostWorkspace0493x8q, boundaryThreads,
            "io_segmented_neumann_virtual_reservoir_accumulate_kernel_0493x8x launch");
        launch_neumann_virtual_cell_accumulate_0493x8w(
            view, nActiveFluid, cfg, ghostWorkspace0493x8q, boundaryThreads,
            "io_segmented_neumann_virtual_cell_accumulate_kernel_0493x8w launch");
        launch_neumann_species_bath_accumulate_0493x8r(
            view, nActiveFluid, cfg, ghostWorkspace0493x8q, boundaryThreads,
            "io_segmented_neumann_species_bath_accumulate_kernel_0493x8r launch");
        CudaClassicSrcIoFullfaceConfig0263 boundaryCfgNeumann0493x8x = cfg;
        if (ghostWorkspace0493x8q.reservoirActive0493x8x ||
            ghostWorkspace0493x8q.virtualCellsActive0493x8w ||
            ghostWorkspace0493x8q.speciesCount0493x8r > 0u)
            boundaryCfgNeumann0493x8x.outletNeumannKinetic0493x8q = 0;
        io_fullface_boundary_particles_kernel_0267<<<static_cast<unsigned int>(boundaryBlocks64), boundaryThreads>>>(
            nActiveFluid, view.x, view.y, view.vx, view.vy, view.mass, view.role,
            kParticleRoleFluid, kParticleRoleInactive, boundaryCfgNeumann0493x8x, dCounters,
            ghostWorkspace0493x8q.candidates, ghostWorkspace0493x8q.count,
            ghostWorkspace0493x8q.capacity,
            ghostWorkspace0493x8q.bath, ghostWorkspace0493x8q.bathCells,
            ghostWorkspace0493x8q.replicaCandidates0493x8v,
            ghostWorkspace0493x8q.replicaCount0493x8v,
            ghostWorkspace0493x8q.replicaCapacity0493x8v,
            recycleWorkspace0493x9e != nullptr ? recycleWorkspace0493x9e->deletedIndices : nullptr,
            recycleWorkspace0493x9e != nullptr ? recycleWorkspace0493x9e->deletedCount : nullptr,
            recycleWorkspace0493x9e != nullptr ? recycleWorkspace0493x9e->deletedCapacity : 0u);
        check_cuda_0263(cudaGetLastError(), "io_segmented_boundary_particles_kernel_0267 launch");

        const bool useSegmentedPool0269 = !env_truthy_0263("MPCD_CUDA_CLASSIC_SRC_IO_RESIDENT_0269_DISABLE_SEGMENTED_POOL");
        const unsigned long long equilibriumPredictedInsertions0293 = segmented_reservoir_target_particles_host_0293(cfg);
        // 0293: outlet extraction must run before hard segmented inlet refill.
        // This lets equilibrium_flux/forced_flux free inactive slots before
        // reservoir insertion consumes the pool.
        maybe_apply_forced_outlet_extraction_0291(view, cfg, dCounters,
                                                  "io_segmented_pre_insert_outlet_extraction_kernel_0293 launch",
                                                  equilibriumPredictedInsertions0293,
                                                  recycleWorkspace0493x9e != nullptr ? recycleWorkspace0493x9e->deletedIndices : nullptr,
                                                  recycleWorkspace0493x9e != nullptr ? recycleWorkspace0493x9e->deletedCount : nullptr,
                                                  recycleWorkspace0493x9e != nullptr ? recycleWorkspace0493x9e->deletedCapacity : 0u);
        if (!residentOpt0493x9dFix1)
            check_cuda_0263(cudaDeviceSynchronize(),
                            "io_segmented_pre_insert_outlet_extraction_kernel_0293 synchronize");
        const unsigned int ghostCount0493x8q =
            read_neumann_ghost_count_0493x8q(ghostWorkspace0493x8q, cfg, view);
        if (useSegmentedPool0269) {
            const int poolThreads = env_int_0263("MPCD_CUDA_CLASSIC_SRC_IO_RESIDENT_0269_POOL_THREADS", boundaryThreads);
            const std::uint64_t reservoirCells = segmented_reservoir_cell_count_host_0269(cfg);
            const std::uint64_t reservoirPoolNeed0493x8q = std::max<std::uint64_t>(
                reservoirCells * static_cast<std::uint64_t>(std::max(0, cfg.inletTargetOccupancy)),
                static_cast<std::uint64_t>(equilibriumPredictedInsertions0293));
            const std::uint64_t neededInactive =
                static_cast<std::uint64_t>(ghostCount0493x8q) + reservoirPoolNeed0493x8q;
            std::uint64_t* dInactiveIndices = nullptr;
            unsigned int inactiveCount = 0u;
            bool persistentTailPool0493x9dFix1 = false;
            bool usedTailPool0313 = false;
            bool usedRecyclePool0493x9e = false;
            unsigned int* dInactiveFlags = nullptr;
            unsigned int* dInactivePrefix = nullptr;
            if (recycleOpt0493x9e) {
                recyclePoolNeed0493x9eFix3 = neededInactive;
                dInactiveIndices = build_recycled_inactive_pool_0493x9e(
                    neededInactive, oldActivePrefix0315c, view,
                    kParticleRoleInactive, dCounters, poolThreads);
                inactiveCount = static_cast<unsigned int>(neededInactive);
                usedRecyclePool0493x9e = true;
            } else {
                const std::uint64_t tailScanForPool0315c = inactive_tail_scan_count_0313(view.n, neededInactive);
                usedTailPool0313 = collect_tail_inactive_pool_0313(
                view.n, view.role, kParticleRoleInactive, neededInactive, poolThreads,
                    &dInactiveIndices, &inactiveCount, &persistentTailPool0493x9dFix1);
                if (usedTailPool0313) activePrefixCompactTailScan0315c = std::max(activePrefixCompactTailScan0315c, tailScanForPool0315c);

                if (!usedTailPool0313) {
                if (view.n > static_cast<std::uint64_t>(std::numeric_limits<unsigned int>::max())) {
                    throw std::runtime_error("cuda_classic_src_io_resident_0263: too many particles for 0269 segmented inactive-prefix pool");
                }
                check_cuda_0263(cudaMalloc(&dInactiveFlags, sizeof(unsigned int) * static_cast<std::size_t>(view.n)),
                                "allocate 0269 segmented inactive flags");
                check_cuda_0263(cudaMalloc(&dInactivePrefix, sizeof(unsigned int) * static_cast<std::size_t>(view.n)),
                                "allocate 0269 segmented inactive prefix");
                check_cuda_0263(cudaMalloc(&dInactiveIndices, sizeof(std::uint64_t) * static_cast<std::size_t>(view.n)),
                                "allocate 0269 segmented inactive index pool");
                const std::uint64_t poolBlocks64 = (view.n + static_cast<std::uint64_t>(poolThreads) - 1u) /
                                                   static_cast<std::uint64_t>(poolThreads);
                if (poolBlocks64 > static_cast<std::uint64_t>(2147483647)) {
                    throw std::runtime_error("cuda_classic_src_io_resident_0263: grid too large for 0269 segmented inactive pool launch");
                }
                io_fullface_mark_inactive_flags_kernel_0268<<<static_cast<unsigned int>(poolBlocks64), poolThreads>>>(
                    view.n, view.role, kParticleRoleInactive, dInactiveFlags);
                check_cuda_0263(cudaGetLastError(), "io_segmented_mark_inactive_flags_kernel_0269 launch");
                thrust::exclusive_scan(thrust::device, dInactiveFlags, dInactiveFlags + view.n, dInactivePrefix);
                check_cuda_0263(cudaGetLastError(), "io_segmented inactive prefix scan 0269");
                io_fullface_compact_inactive_slots_kernel_0268<<<static_cast<unsigned int>(poolBlocks64), poolThreads>>>(
                    view.n, view.role, kParticleRoleInactive, dInactivePrefix, dInactiveIndices);
                check_cuda_0263(cudaGetLastError(), "io_segmented_compact_inactive_slots_kernel_0269 launch");
                unsigned int lastFlag = 0u;
                unsigned int lastPrefix = 0u;
                if (view.n > 0u) {
                    check_cuda_0263(cudaMemcpy(&lastFlag, dInactiveFlags + (view.n - 1u), sizeof(unsigned int), cudaMemcpyDeviceToHost),
                                    "copy 0269 segmented inactive last flag");
                    check_cuda_0263(cudaMemcpy(&lastPrefix, dInactivePrefix + (view.n - 1u), sizeof(unsigned int), cudaMemcpyDeviceToHost),
                                    "copy 0269 segmented inactive last prefix");
                }
                    inactiveCount = lastPrefix + lastFlag;
                }
            }

            launch_neumann_ghost_insert_0493x8q(
                view, cfg, ghostWorkspace0493x8q, ghostCount0493x8q,
                dInactiveIndices, inactiveCount, dCounters, poolThreads,
                "io_segmented_neumann_ghost_insert_0493x8q launch");
            if (reservoirCells > 0ULL) {
                const int insertThreads = env_int_0263("MPCD_CUDA_CLASSIC_SRC_IO_RESIDENT_0269_SEGMENTED_INSERT_THREADS", 128);
                const std::uint64_t insertBlocks64 = (reservoirCells + static_cast<std::uint64_t>(insertThreads) - 1u) /
                                                     static_cast<std::uint64_t>(insertThreads);
                if (insertBlocks64 > static_cast<std::uint64_t>(2147483647)) {
                    throw std::runtime_error("cuda_classic_src_io_resident_0263: grid too large for 0269 segmented insert launch");
                }
                io_segmented_hard_reservoir_insert_pool_kernel_0269<<<static_cast<unsigned int>(insertBlocks64), insertThreads>>>(
                    view.x, view.y, view.vx, view.vy, view.mass, view.type, view.role,
                    kParticleRoleFluid, kParticleRoleInactive, cfg,
                    dInactiveIndices, inactiveCount,
                    static_cast<std::uint64_t>(ghostCount0493x8q), dCounters);
                check_cuda_0263(cudaGetLastError(), "io_segmented_hard_reservoir_insert_pool_kernel_0269 launch");
            }
            if (dInactiveFlags != nullptr) check_cuda_0263(cudaFree(dInactiveFlags), "free 0269 segmented inactive flags");
            if (dInactivePrefix != nullptr) check_cuda_0263(cudaFree(dInactivePrefix), "free 0269 segmented inactive prefix");
            if (dInactiveIndices != nullptr && !usedRecyclePool0493x9e && !persistentTailPool0493x9dFix1)
                check_cuda_0263(cudaFree(dInactiveIndices),
                                usedTailPool0313 ? "free 0313 segmented inactive tail index pool"
                                                : "free 0269 segmented inactive index pool");
        } else {
            io_fullface_hard_reservoir_insert_kernel_0267<<<1, 1>>>(
                view.n, view.x, view.y, view.vx, view.vy, view.mass, view.type, view.role,
                kParticleRoleFluid, kParticleRoleInactive, cfg, dCounters);
            check_cuda_0263(cudaGetLastError(), "io_segmented_hard_reservoir_insert_kernel_0267 launch");
        }
    }
    check_cuda_0263(cudaDeviceSynchronize(), serialBoundary0267 ?
                    "io_segmented_hard_reservoir_kernel_0264 synchronize" :
                    "io_segmented_boundary_insert_0267 synchronize");
    const auto tAfterKernel = Clock::now();    free_neumann_ghost_workspace_0493x8q(ghostWorkspace0493x8q);


    CudaClassicSrcIoCounters0263 h{};
    check_cuda_0263(cudaMemcpy(&h, dCounters, sizeof(CudaClassicSrcIoCounters0263), cudaMemcpyDeviceToHost), "copy segmented counters");
    if (!residentOpt0493x9dFix1)
        check_cuda_0263(cudaFree(dCounters), "free segmented counters");
    if (h.failureFlag != 0) {
        throw std::runtime_error("cuda_classic_src_io_resident_0263: non-finite particle or too many wall reflections in segmented boundary kernel");
    }
    if (h.overflowFlag != 0) {
        throw std::runtime_error(
            std::string("cuda_classic_src_io_resident_0263: Reservoir exhausted at step ") +
            std::to_string(static_cast<unsigned long long>(cfg.step)) +
            " in segmented hard inlet reservoir; GPU append is disabled. Increase inactive slots or reduce the net injected flux. Details: " +
            "reservoirCells=" + std::to_string(static_cast<unsigned long long>(h.inletReservoirCells)) +
            " targetParticles=" + std::to_string(static_cast<unsigned long long>(h.inletReservoirTargetParticles)) +
            " reservoirDeleted=" + std::to_string(static_cast<unsigned long long>(h.inletReservoirDeleted)) +
            " outletDeleted=" + std::to_string(static_cast<unsigned long long>(h.outletParticlesDeleted)) +
            " insertedBeforeOverflow=" + std::to_string(static_cast<unsigned long long>(h.inletParticlesInserted)) +
            " fluidAfterBoundary=" + std::to_string(static_cast<unsigned long long>(h.fluidParticles)));
    }

    CudaParticleStateDiagnostics prefixRepairDiag{};
    const std::uint64_t deleted0315c = static_cast<std::uint64_t>(h.inletReservoirDeleted + h.inletBackflowDeleted + h.outletParticlesDeleted);
    if (deleted0315c > oldActivePrefix0315c) {
        throw std::runtime_error("cuda_classic_src_io_resident_0263: 0315c segmented deletion count exceeds active prefix");
    }
    const std::uint64_t expectedActive0315c = oldActivePrefix0315c - deleted0315c +
                                             static_cast<std::uint64_t>(h.inletParticlesInserted + h.outletParticlesInserted);
    int targetedRepairStatus0493x9eFix3 = 0;
    const bool targetedRepair0493x9eFix3 = recycleOpt0493x9e &&
        try_targeted_prefix_repair_0493x9e_fix3(
            gpuState, state, oldActivePrefix0315c, expectedActive0315c,
            recyclePoolNeed0493x9eFix3, deleted0315c,
            prefixRepairDiag, targetedRepairStatus0493x9eFix3);

    std::uint64_t actualActive0315c = expectedActive0315c;
    if (targetedRepair0493x9eFix3) {
        static bool announcedTargetedRepair0493x9eFix3 = false;
        if (!announcedTargetedRepair0493x9eFix3) {
            std::fprintf(stderr,
                "[0493x9e-fastpath] prefixRepair=targeted_deleted_list_exact fallback=0315c_exact\n");
            announcedTargetedRepair0493x9eFix3 = true;
        }
    } else {
        if (recycleOpt0493x9e) {
            static bool announcedTargetedFallback0493x9eFix3 = false;
            if (!announcedTargetedFallback0493x9eFix3) {
                std::fprintf(stderr,
                    "[0493x9e-fallback] prefixRepair=0315c_exact targetedStatus=%d\n",
                    targetedRepairStatus0493x9eFix3);
                announcedTargetedFallback0493x9eFix3 = true;
            }
        }
        actualActive0315c = compact_active_prefix_device_0315c(
            gpuState, state, oldActivePrefix0315c, expectedActive0315c,
            activePrefixCompactTailScan0315c, prefixRepairDiag);
    }
    // 0315d: lazy host mirror for segmented inlet/outlet as well.  Keep only
    // the logical active count on the host during normal resident execution;
    // summaries/dumps synchronize the active prefix on demand.
    if (env_truthy_0263("MPCD_CUDA_ACTIVE_PREFIX_EAGER_HOST_MIRROR_0315D")) {
        gpuState.download_active_prefix(state, &prefixRepairDiag);
    } else {
        state.NactiveFluid = actualActive0315c;
    }
    cuda_shared_particle_state_0251_mark_fresh("classic_src_io_segmented_boundary_0264_prefix_compacted_0315c");
    const auto tAfterDownload = Clock::now();

    BoundaryDiagnostics b{};
    b.inletHardReservoirEnabled = 1;
    b.hitsLeft = static_cast<std::uint64_t>(h.hitsLeft);
    b.hitsRight = static_cast<std::uint64_t>(h.hitsRight);
    b.hitsBottom = static_cast<std::uint64_t>(h.hitsBottom);
    b.hitsTop = static_cast<std::uint64_t>(h.hitsTop);
    b.inletReservoirCells = static_cast<std::uint64_t>(h.inletReservoirCells);
    b.inletReservoirTargetParticles = static_cast<std::uint64_t>(h.inletReservoirTargetParticles);
    b.inletReservoirDeleted = static_cast<std::uint64_t>(h.inletReservoirDeleted);
    b.inletBackflowDeleted = static_cast<std::uint64_t>(h.inletBackflowDeleted);
    b.outletParticlesDeleted = static_cast<std::uint64_t>(h.outletParticlesDeleted);
    b.outletParticlesInserted = static_cast<std::uint64_t>(h.outletParticlesInserted);
    b.inletParticlesInserted = static_cast<std::uint64_t>(h.inletParticlesInserted);
    const std::int64_t deleted = static_cast<std::int64_t>(b.inletReservoirDeleted + b.inletBackflowDeleted + b.outletParticlesDeleted);
    b.inletNetParticleDelta = static_cast<std::int64_t>(b.inletParticlesInserted) + static_cast<std::int64_t>(b.outletParticlesInserted) - deleted;
    b.inletReservoirMeanN = b.inletReservoirCells == 0u ? 0.0 : static_cast<double>(std::max(0, params.inletTargetOccupancy));
    b.inletReservoirStdN = 0.0;
    b.inletReservoirMinN = b.inletReservoirCells == 0u ? 0u : static_cast<std::uint32_t>(std::max(0, params.inletTargetOccupancy));
    b.inletReservoirMaxN = b.inletReservoirCells == 0u ? 0u : static_cast<std::uint32_t>(std::max(0, params.inletTargetOccupancy));
    b.inletReservoirEmptyFraction = b.inletReservoirCells == 0u ? 0.0 : (params.inletTargetOccupancy == 0 ? 1.0 : 0.0);
    if (b.inletParticlesInserted > 0u) {
        const double inserted = static_cast<double>(b.inletParticlesInserted);
        b.inletMeanUx = h.inletMeanUxSum / inserted;
        b.inletMeanUy = h.inletMeanUySum / inserted;
        b.inletKBT = h.inletKbtNumerator / (2.0 * inserted);
    }
    b.maxYWallReflectionsPerParticle = h.maxYReflections;

    diag.handled = true;
    diag.applied = true;
    diag.boundary = b;
    diag.fluidParticles = actualActive0315c;
    diag.allocationCalls = particleDiag.allocationCalls + prefixRepairDiag.allocationCalls;
    diag.uploadCalls = particleDiag.uploadCalls + prefixRepairDiag.uploadCalls;
    diag.downloadCalls = particleDiag.downloadCalls + prefixRepairDiag.downloadCalls;
    diag.uploadSeconds = elapsed_0263(t0, tAfterUpload) + prefixRepairDiag.uploadSeconds;
    diag.kernelSeconds = elapsed_0263(tAfterUpload, tAfterKernel) + prefixRepairDiag.kernelSeconds;
    diag.downloadSeconds = 0.0;
    diag.totalSeconds = elapsed_0263(t0, tAfterDownload);
    return diag;
}

} // namespace mpcd
