#include "cuda_classic_src_io_resident_0263.h"

#include "cuda_particle_state.h"
#include "cuda_shared_particle_state_0251.h"
#include "immersed_solid.h"

#include <cuda_runtime.h>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdlib>
#include <cstdint>
#include <stdexcept>
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
    std::uint64_t rngSeed = 1u;
    std::uint64_t step = 0u;
    int immersedRectangleEnabled = 0;
    double immersedXMin = 0.0;
    double immersedXMax = 0.0;
    double immersedYMin = 0.0;
    double immersedYMax = 0.0;
};

struct CudaClassicSrcIoCounters0263 {
    unsigned long long hitsLeft = 0ULL;
    unsigned long long hitsRight = 0ULL;
    unsigned long long hitsBottom = 0ULL;
    unsigned long long hitsTop = 0ULL;
    unsigned long long inletReservoirDeleted = 0ULL;
    unsigned long long inletBackflowDeleted = 0ULL;
    unsigned long long outletParticlesDeleted = 0ULL;
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

__device__ inline int imin_device_0263(int a, int b) { return a < b ? a : b; }
__device__ inline int imax_device_0263(int a, int b) { return a > b ? a : b; }

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

__device__ bool point_in_inlet_reservoir_device_0263(double x, double y, const CudaClassicSrcIoFullfaceConfig0263& cfg) {
    const int cellsX = imax_device_0263(1, imin_device_0263(cfg.inletReservoirCells, cfg.Nx));
    const int cellsY = imax_device_0263(1, imin_device_0263(cfg.inletReservoirCells, cfg.Ny));
    const double dx = (cfg.xMax - cfg.xMin) / static_cast<double>(cfg.Nx > 0 ? cfg.Nx : 1);
    const double dy = (cfg.yMax - cfg.yMin) / static_cast<double>(cfg.Ny > 0 ? cfg.Ny : 1);
    if (cfg.inletFace == 0) return x >= cfg.xMin && x < cfg.xMin + static_cast<double>(cellsX) * dx;
    if (cfg.inletFace == 1) return x > cfg.xMax - static_cast<double>(cellsX) * dx && x <= cfg.xMax;
    if (cfg.inletFace == 2) return y >= cfg.yMin && y < cfg.yMin + static_cast<double>(cellsY) * dy;
    if (cfg.inletFace == 3) return y > cfg.yMax - static_cast<double>(cellsY) * dy && y <= cfg.yMax;
    return false;
}

__device__ bool reservoir_cell_center_inside_immersed_device_0263(double xc, double yc, const CudaClassicSrcIoFullfaceConfig0263& cfg) {
    if (!cfg.immersedRectangleEnabled) return false;
    return xc >= cfg.immersedXMin && xc <= cfg.immersedXMax && yc >= cfg.immersedYMin && yc <= cfg.immersedYMax;
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
    mass[inactiveCursor] = cfg.refMass;
    type[inactiveCursor] = cfg.refType;
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
    std::uint64_t& inactiveCursor,
    std::uint64_t& ordinal,
    CudaClassicSrcIoCounters0263& local)
{
    if (targetN <= 0) return;
    const double x0 = cfg.xMin + static_cast<double>(ix) * dx;
    const double x1 = cfg.xMin + static_cast<double>(ix + 1) * dx;
    const double y0 = cfg.yMin + static_cast<double>(iy) * dy;
    const double y1 = cfg.yMin + static_cast<double>(iy + 1) * dy;
    const double xc = 0.5 * (x0 + x1);
    const double yc = 0.5 * (y0 + y1);
    if (reservoir_cell_center_inside_immersed_device_0263(xc, yc, cfg)) return;
    local.inletReservoirCells += 1ULL;
    local.inletReservoirTargetParticles += static_cast<unsigned long long>(targetN);
    const std::uint64_t seed = splitmix64_device_0263(cfg.rngSeed ^ (cfg.step * 0x9e3779b97f4a7c15ULL) ^
                                                      (ordinal * 0xbf58476d1ce4e5b9ULL) ^
                                                      face_tag_0263(cfg.inletFace));
    ++ordinal;
    Mt19937_64_Device_0263 rng{};
    mt_seed_device_0263(rng, seed);
    for (int k = 0; k < targetN; ++k) {
        const double rx = uniform01_device_0263(rng);
        const double ry = uniform01_device_0263(rng);
        const double xp = clamp_strictly_inside_device_0263(x0 + rx * (x1 - x0), x0, x1);
        const double yp = clamp_strictly_inside_device_0263(y0 + ry * (y1 - y0), y0, y1);
        double ux = 0.0, uy = 0.0;
        inlet_velocity_device_0263(cfg, cfg.inletFace, xp, yp, time, ux, uy);
        activate_reservoir_slot_device_0263(n, x, y, vx, vy, mass, type, role,
                                            fluidRole, inactiveRole, cfg, inactiveCursor,
                                            xp, yp, ux, uy, local);
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

        if (x[i] < cfg.xMin) {
            local.hitsLeft += 1ULL;
            if (cfg.leftMode != 0) { remove = true; removeMode = cfg.leftMode; }
        } else if (x[i] > cfg.xMax) {
            local.hitsRight += 1ULL;
            if (cfg.rightMode != 0) { remove = true; removeMode = cfg.rightMode; }
        }

        if (!remove) {
            int guard = 0;
            while (y[i] < cfg.yMin || y[i] > cfg.yMax) {
                if (++guard > 64) { local.failureFlag = 2; break; }
                if (y[i] < cfg.yMin) {
                    y[i] = 2.0 * cfg.yMin - y[i];
                    local.hitsBottom += 1ULL;
                    apply_y_wall_reflection_device_0263(cfg.bottomWallMode, cfg.wallUxBottom, cfg.wallUyBottom, vx[i], vy[i]);
                } else if (y[i] > cfg.yMax) {
                    y[i] = 2.0 * cfg.yMax - y[i];
                    local.hitsTop += 1ULL;
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

    if (cfg.inletFace == 0) {
        for (int ix = 0; ix < cellsX; ++ix) {
            for (int iy = 0; iy < ny; ++iy) {
                insert_reservoir_cell_device_0263(n, x, y, vx, vy, mass, type, role,
                                                  fluidRole, inactiveRole, cfg, ix, iy, dx, dy,
                                                  targetN, time, inactiveCursor, ordinal, local);
                if (local.overflowFlag) break;
            }
            if (local.overflowFlag) break;
        }
    } else if (cfg.inletFace == 1) {
        for (int ix = nx - cellsX; ix < nx; ++ix) {
            for (int iy = 0; iy < ny; ++iy) {
                insert_reservoir_cell_device_0263(n, x, y, vx, vy, mass, type, role,
                                                  fluidRole, inactiveRole, cfg, ix, iy, dx, dy,
                                                  targetN, time, inactiveCursor, ordinal, local);
                if (local.overflowFlag) break;
            }
            if (local.overflowFlag) break;
        }
    } else if (cfg.inletFace == 2) {
        for (int iy = 0; iy < cellsY; ++iy) {
            for (int ix = 0; ix < nx; ++ix) {
                insert_reservoir_cell_device_0263(n, x, y, vx, vy, mass, type, role,
                                                  fluidRole, inactiveRole, cfg, ix, iy, dx, dy,
                                                  targetN, time, inactiveCursor, ordinal, local);
                if (local.overflowFlag) break;
            }
            if (local.overflowFlag) break;
        }
    } else if (cfg.inletFace == 3) {
        for (int iy = ny - cellsY; iy < ny; ++iy) {
            for (int ix = 0; ix < nx; ++ix) {
                insert_reservoir_cell_device_0263(n, x, y, vx, vy, mass, type, role,
                                                  fluidRole, inactiveRole, cfg, ix, iy, dx, dy,
                                                  targetN, time, inactiveCursor, ordinal, local);
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
    for (std::size_t i = 0; i < static_cast<std::size_t>(state.Np); ++i) {
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
    return cfg;
}

bool supported_common_0263(const SimulationParams& params) {
    if (!params.srcClassicCudaModeEnable) return false;
    if (!hard_inlet_reservoir_enabled_0263(params)) return false;
    if (params.openBoundarySegmentsEnable || params.openBoundarySegmentCount != 0) return false;
    if (!(params.Lx > 0.0) || !(params.Ly > 0.0) || !(params.dt >= 0.0)) return false;
    if (params.projectionEnable || params.closedCapacityResponseEnable || params.resamplingEnable || params.thermostatEnable) return false;
    if (std::abs(params.inletThermalNoise) > 1.0e-15) return false;
    if (params.closedCapacityInletMassFluxEnable) return false;
    if (params.fluidXMinVelocity != 0.0 || params.fluidXMaxVelocity != 0.0 ||
        params.fluidYMinVelocity != 0.0 || params.fluidYMaxVelocity != 0.0) return false;
    const int left = io_mode_code_0263(params.bcLeft);
    const int right = io_mode_code_0263(params.bcRight);
    const int bottom = io_mode_code_0263(params.bcBottom);
    const int top = io_mode_code_0263(params.bcTop);
    const bool xPair = left != 0 && right != 0 && left != right && bottom == 0 && top == 0 &&
                       wall_mode_code_0263(params.bcBottom) != 0 && wall_mode_code_0263(params.bcTop) != 0;
    // 0263 is intentionally full-face x-inlet/outlet first. Same-face and y-axis
    // inlet/outlet are kept for the segmented follow-up.
    return xPair;
}

} // namespace

bool cuda_classic_src_io_fullface_resident_0263_requested() {
    return env_truthy_0263("MPCD_CUDA_CLASSIC_SRC_IO_FULLFACE_RESIDENT_0263");
}

bool cuda_classic_src_io_fullface_resident_0263_supported(const SimulationParams& params) {
    return supported_common_0263(params);
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
    diag.particles = state.Np;
    if (!diag.requested || !diag.supported || state.Np == 0u) return diag;
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
    const std::uint64_t blocks64 = (state.Np + static_cast<std::uint64_t>(threads) - 1u) /
                                   static_cast<std::uint64_t>(threads);
    if (blocks64 > static_cast<std::uint64_t>(2147483647)) {
        throw std::runtime_error("cuda_classic_src_io_resident_0263: grid too large for stream launch");
    }
    CudaParticleDeviceView view = gpuState.device_view();
    io_fullface_force_stream_kernel_0263<<<static_cast<unsigned int>(blocks64), threads>>>(
        view.n, view.x, view.y, view.vx, view.vy, view.role, kParticleRoleFluid, cfg);
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
    diag.particles = state.Np;
    if (!diag.requested || !diag.supported || state.Np == 0u) return diag;
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
    io_fullface_hard_reservoir_kernel_0263<<<1, 1>>>(
        view.n, view.x, view.y, view.vx, view.vy, view.mass, view.type, view.role,
        kParticleRoleFluid, kParticleRoleInactive, cfg, dCounters);
    check_cuda_0263(cudaGetLastError(), "io_fullface_hard_reservoir_kernel_0263 launch");
    check_cuda_0263(cudaDeviceSynchronize(), "io_fullface_hard_reservoir_kernel_0263 synchronize");
    const auto tAfterKernel = Clock::now();

    CudaClassicSrcIoCounters0263 h{};
    check_cuda_0263(cudaMemcpy(&h, dCounters, sizeof(CudaClassicSrcIoCounters0263), cudaMemcpyDeviceToHost), "copy counters");
    check_cuda_0263(cudaFree(dCounters), "free counters");
    if (h.failureFlag != 0) {
        throw std::runtime_error("cuda_classic_src_io_resident_0263: non-finite particle or too many wall reflections in boundary kernel");
    }
    if (h.overflowFlag != 0) {
        throw std::runtime_error(
            std::string("cuda_classic_src_io_resident_0263: hard reservoir needs more inactive slots; ") +
            "GPU append is intentionally disabled in 0263; " +
            "reservoirCells=" + std::to_string(static_cast<unsigned long long>(h.inletReservoirCells)) +
            " targetParticles=" + std::to_string(static_cast<unsigned long long>(h.inletReservoirTargetParticles)) +
            " reservoirDeleted=" + std::to_string(static_cast<unsigned long long>(h.inletReservoirDeleted)) +
            " outletDeleted=" + std::to_string(static_cast<unsigned long long>(h.outletParticlesDeleted)) +
            " insertedBeforeOverflow=" + std::to_string(static_cast<unsigned long long>(h.inletParticlesInserted)) +
            " fluidAfterBoundary=" + std::to_string(static_cast<unsigned long long>(h.fluidParticles)));
    }

    cuda_shared_particle_state_0251_mark_fresh("classic_src_io_fullface_boundary_0263");
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
    b.inletParticlesInserted = static_cast<std::uint64_t>(h.inletParticlesInserted);
    const std::int64_t deleted = static_cast<std::int64_t>(b.inletReservoirDeleted + b.inletBackflowDeleted + b.outletParticlesDeleted);
    b.inletNetParticleDelta = static_cast<std::int64_t>(b.inletParticlesInserted) - deleted;
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
    diag.fluidParticles = static_cast<std::uint64_t>(h.fluidParticles);
    diag.allocationCalls = particleDiag.allocationCalls;
    diag.uploadCalls = particleDiag.uploadCalls;
    diag.downloadCalls = particleDiag.downloadCalls;
    diag.uploadSeconds = elapsed_0263(t0, tAfterUpload);
    diag.kernelSeconds = elapsed_0263(tAfterUpload, tAfterKernel);
    diag.downloadSeconds = elapsed_0263(tAfterKernel, tAfterDownload);
    diag.totalSeconds = elapsed_0263(t0, tAfterDownload);
    return diag;
}

} // namespace mpcd
