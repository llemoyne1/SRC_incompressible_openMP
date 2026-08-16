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
#include <stdexcept>
#include <limits>
#include <string>

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
    int outletNeumannKinetic0493x8q = 0; // mirror exterior kinetic continuation
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
    const double fRamp = ramp_factor_device_0263(cfg, time);
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
    const double fRamp = ramp_factor_device_0263(cfg, time);
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
    CudaClassicSrcIoCounters0263* counters)
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
    unsigned int bathCellCount0493x8q)
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

    const double xpre0493x8q = x[i] - vx[i] * cfg.dt;
    const double ypre0493x8q = y[i] - vy[i] * cfg.dt;
    accumulate_neumann_bath_moments_0493x8q(
        i, xpre0493x8q, ypre0493x8q, vx[i], vy[i], mass[i],
        cfg, bathMoments0493x8q, bathCellCount0493x8q);

    bool remove = false;
    int removeMode = 0;

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

bool collect_tail_inactive_pool_0313(std::uint64_t n,
                                      unsigned char* dRole,
                                      unsigned char inactiveRole,
                                      std::uint64_t need,
                                      int threads,
                                      std::uint64_t** dInactiveIndicesOut,
                                      unsigned int* inactiveCountOut) {
    const char* enableEnv0313 = std::getenv("MPCD_CUDA_INACTIVE_TAIL_POOL_0313");
    if (enableEnv0313 != nullptr && !env_truthy_0263("MPCD_CUDA_INACTIVE_TAIL_POOL_0313")) return false;
    if (n == 0u || need == 0u || dRole == nullptr || dInactiveIndicesOut == nullptr || inactiveCountOut == nullptr) return false;
    const std::uint64_t tailScan = inactive_tail_scan_count_0313(n, need);
    if (tailScan == 0u || tailScan > static_cast<std::uint64_t>(std::numeric_limits<unsigned int>::max())) return false;
    std::uint64_t* dInactiveIndices = nullptr;
    unsigned int* dInactiveCount = nullptr;
    check_cuda_0263(cudaMalloc(&dInactiveIndices, sizeof(std::uint64_t) * static_cast<std::size_t>(tailScan)),
                    "allocate 0313 inactive tail index pool");
    check_cuda_0263(cudaMalloc(&dInactiveCount, sizeof(unsigned int)),
                    "allocate 0313 inactive tail count");
    check_cuda_0263(cudaMemset(dInactiveCount, 0, sizeof(unsigned int)),
                    "clear 0313 inactive tail count");
    const int block = std::max(32, threads);
    const std::uint64_t blocks64 = (tailScan + static_cast<std::uint64_t>(block) - 1u) / static_cast<std::uint64_t>(block);
    if (blocks64 > static_cast<std::uint64_t>(2147483647)) {
        cudaFree(dInactiveIndices);
        cudaFree(dInactiveCount);
        throw std::runtime_error("cuda_classic_src_io_resident_0263: grid too large for 0313 inactive tail pool launch");
    }
    io_collect_tail_inactive_slots_kernel_0313<<<static_cast<unsigned int>(blocks64), block>>>(
        n, tailScan, dRole, inactiveRole, dInactiveIndices, dInactiveCount);
    check_cuda_0263(cudaGetLastError(), "io_collect_tail_inactive_slots_kernel_0313 launch");
    unsigned int count = 0u;
    check_cuda_0263(cudaMemcpy(&count, dInactiveCount, sizeof(unsigned int), cudaMemcpyDeviceToHost),
                    "copy 0313 inactive tail count");
    cudaFree(dInactiveCount);
    if (count < need && !env_truthy_0263("MPCD_CUDA_INACTIVE_TAIL_POOL_NO_FALLBACK_0313")) {
        cudaFree(dInactiveIndices);
        return false;
    }
    *dInactiveIndicesOut = dInactiveIndices;
    *inactiveCountOut = count;
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
        cfg.outletNeumannKinetic0493x8q = mode0493x8q == "neumann" ? 1 : 0;
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
        }
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
    unsigned long long equilibriumPredictedInletInsertions = 0ULL)
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
        kParticleRoleFluid, kParticleRoleInactive, cfg, dBudget, dCounters);
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
};


NeumannGhostWorkspace0493x8q prepare_neumann_ghost_candidates_0493x8q(
    const CudaClassicSrcIoFullfaceConfig0263& cfg,
    std::uint64_t nActiveFluid)
{
    static NeumannGhostWorkspace0493x8q cached{};
    if (!cfg.outletNeumannKinetic0493x8q || nActiveFluid == 0ULL)
        return NeumannGhostWorkspace0493x8q{};

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

    const unsigned int wantedBath = neumann_bath_cell_count_0493x8q(cfg);
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



unsigned int read_neumann_ghost_count_0493x8q(
    const NeumannGhostWorkspace0493x8q& w,
    const CudaClassicSrcIoFullfaceConfig0263& cfg,
    CudaParticleDeviceView view)
{
    if (w.count == nullptr || w.bath == nullptr || w.bathCells == 0u)
        return 0u;

    const int threads = 128;
    const unsigned int blocks =
        (w.bathCells + static_cast<unsigned int>(threads) - 1u) /
        static_cast<unsigned int>(threads);
    io_neumann_bath_candidates_kernel_0493x8q<<<blocks, threads>>>(
        view.n, view.mass, view.type, cfg,
        w.bath, w.bathCells,
        w.candidates, w.count, w.capacity);
    check_cuda_0263(cudaGetLastError(),
                    "io_neumann_bath_candidates_kernel_0493x8q launch");

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
    io_neumann_ghost_insert_kernel_0493x8q<<<blocks, threads>>>(
        view.n, view.x, view.y, view.vx, view.vy, view.mass, view.type, view.role,
        kParticleRoleFluid, kParticleRoleInactive, cfg,
        w.candidates, ghostCount, w.bath, w.bathCells,
        dInactiveIndices, inactiveCount, dCounters);
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

    CudaClassicSrcIoCounters0263* dCounters = nullptr;
    check_cuda_0263(cudaMalloc(&dCounters, sizeof(CudaClassicSrcIoCounters0263)), "allocate counters");
    check_cuda_0263(cudaMemset(dCounters, 0, sizeof(CudaClassicSrcIoCounters0263)), "clear counters");
    const CudaClassicSrcIoFullfaceConfig0263 cfg = make_config_0263(state, params, domain, step, time);
    CudaParticleDeviceView view = gpuState.device_view();
    std::uint64_t activePrefixCompactTailScan0315c = 0u;
    const std::uint64_t oldActivePrefix0315c = nActiveFluid;
    const bool serialBoundary0267 =
        env_truthy_0263("MPCD_CUDA_CLASSIC_SRC_IO_RESIDENT_0267_SERIAL_BOUNDARY") &&
        !cfg.outletNeumannKinetic0493x8q;
    NeumannGhostWorkspace0493x8q ghostWorkspace0493x8q =
        prepare_neumann_ghost_candidates_0493x8q(cfg, nActiveFluid);
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
        io_fullface_boundary_particles_kernel_0267<<<static_cast<unsigned int>(boundaryBlocks64), boundaryThreads>>>(
            nActiveFluid, view.x, view.y, view.vx, view.vy, view.mass, view.role,
            kParticleRoleFluid, kParticleRoleInactive, cfg, dCounters,
            ghostWorkspace0493x8q.candidates, ghostWorkspace0493x8q.count,
            ghostWorkspace0493x8q.capacity,
            ghostWorkspace0493x8q.bath, ghostWorkspace0493x8q.bathCells);
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
                                                  equilibriumPredictedInsertions0293);
        check_cuda_0263(cudaDeviceSynchronize(), "io_fullface_pre_insert_outlet_extraction_kernel_0293 synchronize");
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
            const std::uint64_t tailScanForPool0315c = inactive_tail_scan_count_0313(view.n, neededInactive);
            bool usedTailPool0313 = collect_tail_inactive_pool_0313(
                view.n, view.role, kParticleRoleInactive, neededInactive, poolThreads,
                &dInactiveIndices, &inactiveCount);
            if (usedTailPool0313) activePrefixCompactTailScan0315c = std::max(activePrefixCompactTailScan0315c, tailScanForPool0315c);

            unsigned int* dInactiveFlags = nullptr;
            unsigned int* dInactivePrefix = nullptr;
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
            if (dInactiveIndices != nullptr) check_cuda_0263(cudaFree(dInactiveIndices), usedTailPool0313 ? "free 0313 inactive tail index pool" : "free 0268 inactive index pool");
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
    const std::uint64_t actualActive0315c = compact_active_prefix_device_0315c(
        gpuState, state, oldActivePrefix0315c, expectedActive0315c,
        activePrefixCompactTailScan0315c, prefixRepairDiag);
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

    CudaClassicSrcIoCounters0263* dCounters = nullptr;
    check_cuda_0263(cudaMalloc(&dCounters, sizeof(CudaClassicSrcIoCounters0263)), "allocate segmented counters");
    check_cuda_0263(cudaMemset(dCounters, 0, sizeof(CudaClassicSrcIoCounters0263)), "clear segmented counters");
    const CudaClassicSrcIoFullfaceConfig0263 cfg = make_config_0263(state, params, domain, step, time);
    CudaParticleDeviceView view = gpuState.device_view();
    std::uint64_t activePrefixCompactTailScan0315c = 0u;
    const std::uint64_t oldActivePrefix0315c = nActiveFluid;
    const bool serialBoundary0267 =
        env_truthy_0263("MPCD_CUDA_CLASSIC_SRC_IO_RESIDENT_0267_SERIAL_BOUNDARY") &&
        !cfg.outletNeumannKinetic0493x8q;
    NeumannGhostWorkspace0493x8q ghostWorkspace0493x8q =
        prepare_neumann_ghost_candidates_0493x8q(cfg, nActiveFluid);
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
        io_fullface_boundary_particles_kernel_0267<<<static_cast<unsigned int>(boundaryBlocks64), boundaryThreads>>>(
            nActiveFluid, view.x, view.y, view.vx, view.vy, view.mass, view.role,
            kParticleRoleFluid, kParticleRoleInactive, cfg, dCounters,
            ghostWorkspace0493x8q.candidates, ghostWorkspace0493x8q.count,
            ghostWorkspace0493x8q.capacity,
            ghostWorkspace0493x8q.bath, ghostWorkspace0493x8q.bathCells);
        check_cuda_0263(cudaGetLastError(), "io_segmented_boundary_particles_kernel_0267 launch");

        const bool useSegmentedPool0269 = !env_truthy_0263("MPCD_CUDA_CLASSIC_SRC_IO_RESIDENT_0269_DISABLE_SEGMENTED_POOL");
        const unsigned long long equilibriumPredictedInsertions0293 = segmented_reservoir_target_particles_host_0293(cfg);
        // 0293: outlet extraction must run before hard segmented inlet refill.
        // This lets equilibrium_flux/forced_flux free inactive slots before
        // reservoir insertion consumes the pool.
        maybe_apply_forced_outlet_extraction_0291(view, cfg, dCounters,
                                                  "io_segmented_pre_insert_outlet_extraction_kernel_0293 launch",
                                                  equilibriumPredictedInsertions0293);
        check_cuda_0263(cudaDeviceSynchronize(), "io_segmented_pre_insert_outlet_extraction_kernel_0293 synchronize");
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
            const std::uint64_t tailScanForPool0315c = inactive_tail_scan_count_0313(view.n, neededInactive);
            bool usedTailPool0313 = collect_tail_inactive_pool_0313(
                view.n, view.role, kParticleRoleInactive, neededInactive, poolThreads,
                &dInactiveIndices, &inactiveCount);
            if (usedTailPool0313) activePrefixCompactTailScan0315c = std::max(activePrefixCompactTailScan0315c, tailScanForPool0315c);

            unsigned int* dInactiveFlags = nullptr;
            unsigned int* dInactivePrefix = nullptr;
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
            if (dInactiveIndices != nullptr) check_cuda_0263(cudaFree(dInactiveIndices), usedTailPool0313 ? "free 0313 segmented inactive tail index pool" : "free 0269 segmented inactive index pool");
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
    const std::uint64_t actualActive0315c = compact_active_prefix_device_0315c(
        gpuState, state, oldActivePrefix0315c, expectedActive0315c,
        activePrefixCompactTailScan0315c, prefixRepairDiag);
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
