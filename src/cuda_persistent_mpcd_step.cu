#include "cuda_persistent_mpcd_step.h"
#include "cuda_particle_state.h"

#include <cuda_runtime.h>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdlib>
#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <stdexcept>
#include <string>
#include <vector>

namespace mpcd {
namespace {

#define MPCD_CUDA_CHECK(call) do { \
    cudaError_t err__ = (call); \
    if (err__ != cudaSuccess) { \
        throw std::runtime_error(std::string("CUDA error in ") + #call + ": " + cudaGetErrorString(err__)); \
    } \
} while (0)

using Clock = std::chrono::steady_clock;

double seconds_since(const Clock::time_point& t0) {
    return std::chrono::duration<double>(Clock::now() - t0).count();
}

template <typename T>
void cuda_free(T*& ptr) {
    if (ptr != nullptr) {
        cudaFree(ptr);
        ptr = nullptr;
    }
}


bool env_flag_enabled_0257(const char* name, const bool fallback = false) {
    const char* v = std::getenv(name);
    if (v == nullptr || *v == '\0') return fallback;
    const std::string s(v);
    return !(s == "0" || s == "false" || s == "FALSE" ||
             s == "off" || s == "OFF" || s == "no" || s == "NO");
}

std::uint64_t splitmix64_host(std::uint64_t x) {
    x += 0x9e3779b97f4a7c15ULL;
    x = (x ^ (x >> 30U)) * 0xbf58476d1ce4e5b9ULL;
    x = (x ^ (x >> 27U)) * 0x94d049bb133111ebULL;
    return x ^ (x >> 31U);
}

__device__ inline std::uint64_t splitmix64_device_0272(std::uint64_t x) {
    x += 0x9e3779b97f4a7c15ULL;
    x = (x ^ (x >> 30U)) * 0xbf58476d1ce4e5b9ULL;
    x = (x ^ (x >> 27U)) * 0x94d049bb133111ebULL;
    return x ^ (x >> 31U);
}

__global__ void fill_rotation_tables_persistent_0272_kernel(int nc,
                                                            double cosAngle,
                                                            double sinAngle,
                                                            int randomRotationSign,
                                                            std::uint64_t rngSeed,
                                                            std::uint64_t step,
                                                            double* cosA,
                                                            double* sinA) {
    const int c = blockIdx.x * blockDim.x + threadIdx.x;
    if (c >= nc) return;
    double sa = sinAngle;
    if (randomRotationSign) {
        const std::uint64_t h = splitmix64_device_0272(rngSeed ^
                                                       (step * 0x9e3779b97f4a7c15ULL) ^
                                                       static_cast<std::uint64_t>(c));
        if ((h & 1ULL) == 0ULL) sa = -sa;
    }
    cosA[c] = cosAngle;
    sinA[c] = sa;
}

std::vector<std::uint8_t> normalized_roles(const ParticleState& state) {
    // 0315l: kernels in this file are migrated to the active prefix.
    // Avoid constructing a role vector over the inactive capacity.
    const std::size_t n = active_fluid_count_size(state);
    if (state.role.empty()) return std::vector<std::uint8_t>(n, kParticleRoleFluid);
    return std::vector<std::uint8_t>(state.role.begin(), state.role.begin() + static_cast<std::ptrdiff_t>(n));
}

struct DeviceBuffers {
    double *x = nullptr, *y = nullptr, *vx = nullptr, *vy = nullptr, *mass = nullptr;
    unsigned char* role = nullptr;
    int* cellId = nullptr;
    unsigned int* count = nullptr;
    double *cellMass = nullptr, *cellPx = nullptr, *cellPy = nullptr, *cellUx = nullptr, *cellUy = nullptr;
    double *cosA = nullptr, *sinA = nullptr, *cellKinetic = nullptr, *cellScale = nullptr;
    unsigned long long *fluidCounter = nullptr, *rotatedCounter = nullptr, *invalidCounter = nullptr;

    void release() {
        cuda_free(x); cuda_free(y); cuda_free(vx); cuda_free(vy); cuda_free(mass); cuda_free(role);
        cuda_free(cellId); cuda_free(count); cuda_free(cellMass); cuda_free(cellPx); cuda_free(cellPy);
        cuda_free(cellUx); cuda_free(cellUy); cuda_free(cosA); cuda_free(sinA); cuda_free(cellKinetic);
        cuda_free(cellScale); cuda_free(fluidCounter); cuda_free(rotatedCounter); cuda_free(invalidCounter);
    }
    ~DeviceBuffers() { release(); }
};

struct DeviceConfig {
    int Nx, Ny, numCells;
    double Lx, Ly, dx, dy;
    double shiftX, shiftY;
    int periodicX, periodicY;
    double domainXMin, domainXMax, domainYMin, domainYMax;
    int wallLeftEnabled, wallRightEnabled, wallBottomEnabled, wallTopEnabled;
    double wallAccommodation, wallGamma, wallVpMass;
    double wallUxLeft, wallUyLeft, wallUxRight, wallUyRight;
    double wallUxBottom, wallUyBottom, wallUxTop, wallUyTop;
    int immersedRectangleEnabled;
    int immersedFractionSamples;
    double immersedXMin, immersedXMax, immersedYMin, immersedYMax;
    int immersedCircleEnabled;
    double immersedCircleCx, immersedCircleCy, immersedCircleR;
    double immersedWallUx, immersedWallUy;
    int fusedStreamDeposit0274;
    int fusedStreamMode0274;
    double streamDt0274;
    double streamBodyAccelerationX0274, streamBodyAccelerationY0274;
    int streamTaylorGreenEnable0274;
    double streamTaylorGreenAmplitude0274;
    int streamTaylorGreenModeX0274, streamTaylorGreenModeY0274;
    int streamBottomMode0274, streamTopMode0274;
    double streamWallUxBottom0274, streamWallUyBottom0274;
    double streamWallUxTop0274, streamWallUyTop0274;
    unsigned char fluidRole;
};

__device__ double wrap_periodic(double x, double L) {
    x = fmod(x, L);
    if (x < 0.0) x += L;
    if (x >= L) x -= L;
    return x;
}

__device__ int bounded_cell_index_device(double xs, double L, double dx, int N) {
    (void)L;
    int i = static_cast<int>(floor(xs / dx));
    if (i < 0) i = 0;
    if (i >= N) i = N - 1;
    return i;
}

__device__ int periodic_cell_index_device(double xs, double L, double dx, int N) {
    xs = wrap_periodic(xs, L);
    int i = static_cast<int>(floor(xs / dx));
    if (i < 0) i = 0;
    if (i >= N) i = N - 1;
    return i;
}

__device__ int cell_index_device(double x, double y, DeviceConfig cfg) {
    const double xs = x + cfg.shiftX;
    const double ys = y + cfg.shiftY;
    const int ix = cfg.periodicX
        ? periodic_cell_index_device(xs, cfg.Lx, cfg.dx, cfg.Nx)
        : bounded_cell_index_device(xs, cfg.Lx, cfg.dx, cfg.Nx);
    const int iy = cfg.periodicY
        ? periodic_cell_index_device(ys, cfg.Ly, cfg.dy, cfg.Ny)
        : bounded_cell_index_device(ys, cfg.Ly, cfg.dy, cfg.Ny);
    return ix + cfg.Nx * iy;
}

__device__ inline double clamp_persistent_0274(double x, double lo, double hi) {
    return fmin(fmax(x, lo), hi);
}

__device__ inline void apply_stream_wall_reflection_0274(
    const int mode,
    const double wallUx,
    const double wallUy,
    double& vx,
    double& vy)
{
    if (mode == 2) {
        vx = 2.0 * wallUx - vx;
        vy = 2.0 * wallUy - vy;
    } else {
        (void)wallUx;
        vy = 2.0 * wallUy - vy;
    }
}

__device__ inline void apply_fused_stream_0274(DeviceConfig cfg,
                                               double& x,
                                               double& y,
                                               double& vx,
                                               double& vy) {
    if (!cfg.fusedStreamDeposit0274) return;

    const double x0 = x;
    const double y0 = y;
    double ax = cfg.streamBodyAccelerationX0274;
    double ay = cfg.streamBodyAccelerationY0274;
    if (cfg.streamTaylorGreenEnable0274 && cfg.streamTaylorGreenAmplitude0274 > 0.0) {
        constexpr double pi = 3.141592653589793238462643383279502884;
        const double kx = 2.0 * pi * static_cast<double>(cfg.streamTaylorGreenModeX0274) / cfg.Lx;
        const double ky = 2.0 * pi * static_cast<double>(cfg.streamTaylorGreenModeY0274) / cfg.Ly;
        const double sx = sin(kx * x0);
        const double cx = cos(kx * x0);
        const double sy = sin(ky * y0);
        const double cy = cos(ky * y0);
        ax += cfg.streamTaylorGreenAmplitude0274 * sx * cy;
        ay += -cfg.streamTaylorGreenAmplitude0274 * cx * sy;
    }

    const double dt = cfg.streamDt0274;
    double vx1 = vx + ax * dt;
    double vy1 = vy + ay * dt;
    double x1 = wrap_periodic(x0 + vx1 * dt, cfg.Lx);
    double y1 = y0 + vy1 * dt;

    if (cfg.fusedStreamMode0274 == 1) {
        y1 = wrap_periodic(y1, cfg.Ly);
    } else if (cfg.fusedStreamMode0274 == 2) {
        int guard = 0;
        while (y1 < cfg.domainYMin || y1 > cfg.domainYMax) {
            if (++guard > 64) {
                y1 = clamp_persistent_0274(y1, cfg.domainYMin, cfg.domainYMax);
                break;
            }
            if (y1 < cfg.domainYMin) {
                y1 = 2.0 * cfg.domainYMin - y1;
                apply_stream_wall_reflection_0274(cfg.streamBottomMode0274,
                                                  cfg.streamWallUxBottom0274,
                                                  cfg.streamWallUyBottom0274,
                                                  vx1, vy1);
            } else if (y1 > cfg.domainYMax) {
                y1 = 2.0 * cfg.domainYMax - y1;
                apply_stream_wall_reflection_0274(cfg.streamTopMode0274,
                                                  cfg.streamWallUxTop0274,
                                                  cfg.streamWallUyTop0274,
                                                  vx1, vy1);
            }
        }
        y1 = clamp_persistent_0274(y1, cfg.domainYMin, cfg.domainYMax);
    }

    x = x1;
    y = y1;
    vx = vx1;
    vy = vy1;
}

__device__ double overlap_length_device(double a0, double a1, double b0, double b1) {
    const double lo = fmax(a0, b0);
    const double hi = fmin(a1, b1);
    return hi > lo ? hi - lo : 0.0;
}

__device__ void add_virtual_wall_mass_momentum_device(double faceArea,
                                                       double fullCellArea,
                                                       double wallUx,
                                                       double wallUy,
                                                       DeviceConfig cfg,
                                                       double& mass,
                                                       double& px,
                                                       double& py) {
    if (!(faceArea > 0.0) || !(fullCellArea > 0.0)) return;
    const double equivalentCount = cfg.wallAccommodation * cfg.wallGamma * faceArea / fullCellArea;
    if (!(equivalentCount > 0.0)) return;
    const double vmass = equivalentCount * cfg.wallVpMass;
    mass += vmass;
    px += vmass * wallUx;
    py += vmass * wallUy;
}

__device__ bool point_inside_domain_device(double x, double y, DeviceConfig cfg) {
    return x >= cfg.domainXMin && x <= cfg.domainXMax &&
           y >= cfg.domainYMin && y <= cfg.domainYMax;
}

__device__ bool point_inside_immersed_rectangle_device(double x, double y, DeviceConfig cfg) {
    return x >= cfg.immersedXMin && x <= cfg.immersedXMax &&
           y >= cfg.immersedYMin && y <= cfg.immersedYMax;
}

__device__ double immersed_rectangle_fraction_device(int ix, int iy, DeviceConfig cfg) {
    if (!cfg.immersedRectangleEnabled) return 0.0;
    const int ns = cfg.immersedFractionSamples > 0 ? cfg.immersedFractionSamples : 1;
    const double x0 = static_cast<double>(ix) * cfg.dx - cfg.shiftX;
    const double y0 = static_cast<double>(iy) * cfg.dy - cfg.shiftY;
    int inside = 0;
    int fluidSamples = 0;
    const int total = ns * ns;
    for (int sy = 0; sy < ns; ++sy) {
        double y = y0 + (static_cast<double>(sy) + 0.5) * cfg.dy / static_cast<double>(ns);
        if (cfg.periodicY) y = wrap_periodic(y, cfg.Ly);
        for (int sx = 0; sx < ns; ++sx) {
            double x = x0 + (static_cast<double>(sx) + 0.5) * cfg.dx / static_cast<double>(ns);
            if (cfg.periodicX) x = wrap_periodic(x, cfg.Lx);
            if (!point_inside_domain_device(x, y, cfg)) continue;
            ++fluidSamples;
            if (point_inside_immersed_rectangle_device(x, y, cfg)) ++inside;
        }
    }
    const int denom = fluidSamples > 0 ? fluidSamples : total;
    return static_cast<double>(inside) / static_cast<double>(denom);
}


__device__ bool point_inside_immersed_circle_device(double x, double y, DeviceConfig cfg) {
    const double dx = x - cfg.immersedCircleCx;
    const double dy = y - cfg.immersedCircleCy;
    return dx * dx + dy * dy <= cfg.immersedCircleR * cfg.immersedCircleR;
}

__device__ double immersed_circle_fraction_device(int ix, int iy, DeviceConfig cfg) {
    if (!cfg.immersedCircleEnabled) return 0.0;
    const int ns = cfg.immersedFractionSamples > 0 ? cfg.immersedFractionSamples : 1;
    const double x0 = static_cast<double>(ix) * cfg.dx - cfg.shiftX;
    const double y0 = static_cast<double>(iy) * cfg.dy - cfg.shiftY;
    int inside = 0;
    int fluidSamples = 0;
    const int total = ns * ns;
    for (int sy = 0; sy < ns; ++sy) {
        double y = y0 + (static_cast<double>(sy) + 0.5) * cfg.dy / static_cast<double>(ns);
        if (cfg.periodicY) y = wrap_periodic(y, cfg.Ly);
        for (int sx = 0; sx < ns; ++sx) {
            double x = x0 + (static_cast<double>(sx) + 0.5) * cfg.dx / static_cast<double>(ns);
            if (cfg.periodicX) x = wrap_periodic(x, cfg.Lx);
            if (!point_inside_domain_device(x, y, cfg)) continue;
            ++fluidSamples;
            if (point_inside_immersed_circle_device(x, y, cfg)) ++inside;
        }
    }
    const int denom = fluidSamples > 0 ? fluidSamples : total;
    return static_cast<double>(inside) / static_cast<double>(denom);
}

__global__ void add_wall_virtual_faces_persistent_kernel(int nc,
                                                         DeviceConfig cfg,
                                                         double* cellMass,
                                                         double* cellPx,
                                                         double* cellPy) {
    const int c = blockIdx.x * blockDim.x + threadIdx.x;
    if (c >= nc) return;
    if (cfg.wallAccommodation <= 0.0 || cfg.wallGamma <= 0.0 || cfg.wallVpMass <= 0.0) return;

    const int ix = c % cfg.Nx;
    const int iy = c / cfg.Nx;
    const double x0 = static_cast<double>(ix) * cfg.dx - cfg.shiftX;
    const double x1 = x0 + cfg.dx;
    const double y0 = static_cast<double>(iy) * cfg.dy - cfg.shiftY;
    const double y1 = y0 + cfg.dy;
    const double fullCellArea = cfg.dx * cfg.dy;

    double mass = cellMass[c];
    double px = cellPx[c];
    double py = cellPy[c];

    if (cfg.wallLeftEnabled) {
        const double outsideX = overlap_length_device(x0, x1, cfg.domainXMin - cfg.dx, cfg.domainXMin);
        const double insideY = cfg.periodicY ? cfg.dy : overlap_length_device(y0, y1, cfg.domainYMin, cfg.domainYMax);
        add_virtual_wall_mass_momentum_device(outsideX * insideY, fullCellArea, cfg.wallUxLeft, cfg.wallUyLeft, cfg, mass, px, py);
    }
    if (cfg.wallRightEnabled) {
        const double outsideX = overlap_length_device(x0, x1, cfg.domainXMax, cfg.domainXMax + cfg.dx);
        const double insideY = cfg.periodicY ? cfg.dy : overlap_length_device(y0, y1, cfg.domainYMin, cfg.domainYMax);
        add_virtual_wall_mass_momentum_device(outsideX * insideY, fullCellArea, cfg.wallUxRight, cfg.wallUyRight, cfg, mass, px, py);
    }
    if (cfg.wallBottomEnabled) {
        const double insideX = cfg.periodicX ? cfg.dx : overlap_length_device(x0, x1, cfg.domainXMin, cfg.domainXMax);
        const double outsideY = overlap_length_device(y0, y1, cfg.domainYMin - cfg.dy, cfg.domainYMin);
        add_virtual_wall_mass_momentum_device(insideX * outsideY, fullCellArea, cfg.wallUxBottom, cfg.wallUyBottom, cfg, mass, px, py);
    }
    if (cfg.wallTopEnabled) {
        const double insideX = cfg.periodicX ? cfg.dx : overlap_length_device(x0, x1, cfg.domainXMin, cfg.domainXMax);
        const double outsideY = overlap_length_device(y0, y1, cfg.domainYMax, cfg.domainYMax + cfg.dy);
        add_virtual_wall_mass_momentum_device(insideX * outsideY, fullCellArea, cfg.wallUxTop, cfg.wallUyTop, cfg, mass, px, py);
    }
    if (cfg.immersedRectangleEnabled) {
        const double solidFraction = immersed_rectangle_fraction_device(ix, iy, cfg);
        add_virtual_wall_mass_momentum_device(solidFraction * fullCellArea, fullCellArea,
                                              cfg.immersedWallUx, cfg.immersedWallUy, cfg, mass, px, py);
    }
    if (cfg.immersedCircleEnabled) {
        const double solidFraction = immersed_circle_fraction_device(ix, iy, cfg);
        add_virtual_wall_mass_momentum_device(solidFraction * fullCellArea, fullCellArea,
                                              cfg.immersedWallUx, cfg.immersedWallUy, cfg, mass, px, py);
    }

    cellMass[c] = mass;
    cellPx[c] = px;
    cellPy[c] = py;
}

__global__ void reset_persistent_cells_kernel(int n, int nc,
                                              int* cellId,
                                              unsigned int* count,
                                              double* cellMass,
                                              double* cellPx,
                                              double* cellPy,
                                              double* cellUx,
                                              double* cellUy,
                                              double* cellKinetic,
                                              double* cellScale) {
    const int tid = blockIdx.x * blockDim.x + threadIdx.x;
    const int stride = blockDim.x * gridDim.x;
    for (int i = tid; i < n; i += stride) cellId[i] = -1;
    for (int c = tid; c < nc; c += stride) {
        count[c] = 0u;
        cellMass[c] = 0.0;
        cellPx[c] = 0.0;
        cellPy[c] = 0.0;
        cellUx[c] = 0.0;
        cellUy[c] = 0.0;
        cellKinetic[c] = 0.0;
        cellScale[c] = 1.0;
    }
}

__global__ void deposit_persistent_kernel(int n,
                                          double* x,
                                          double* y,
                                          double* vx,
                                          double* vy,
                                          const double* mass,
                                          const unsigned char* role,
                                          DeviceConfig cfg,
                                          int* cellId,
                                          unsigned int* count,
                                          double* cellMass,
                                          double* cellPx,
                                          double* cellPy,
                                          unsigned long long* fluidCounter) {
    const int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= n) return;
    if (role[i] != cfg.fluidRole) return;

    double xi = x[i];
    double yi = y[i];
    double vxi = vx[i];
    double vyi = vy[i];
    apply_fused_stream_0274(cfg, xi, yi, vxi, vyi);
    if (cfg.fusedStreamDeposit0274) {
        x[i] = xi;
        y[i] = yi;
        vx[i] = vxi;
        vy[i] = vyi;
    }

    const int c = cell_index_device(xi, yi, cfg);
    cellId[i] = c;
    const double m = mass[i];
    atomicAdd(&count[c], 1u);
    atomicAdd(&cellMass[c], m);
    atomicAdd(&cellPx[c], m * vxi);
    atomicAdd(&cellPy[c], m * vyi);
    atomicAdd(fluidCounter, 1ull);
}

__global__ void finalize_velocity_persistent_kernel(int nc,
                                                    const double* cellMass,
                                                    const double* cellPx,
                                                    const double* cellPy,
                                                    double* cellUx,
                                                    double* cellUy) {
    const int c = blockIdx.x * blockDim.x + threadIdx.x;
    if (c >= nc) return;
    const double m = cellMass[c];
    if (m > 0.0) {
        cellUx[c] = cellPx[c] / m;
        cellUy[c] = cellPy[c] / m;
    } else {
        cellUx[c] = 0.0;
        cellUy[c] = 0.0;
    }
}

__global__ void src_rotate_persistent_kernel(int n,
                                             const int* cellId,
                                             const unsigned char* role,
                                             const double* cellUx,
                                             const double* cellUy,
                                             const double* cosA,
                                             const double* sinA,
                                             DeviceConfig cfg,
                                             double* vx,
                                             double* vy,
                                             unsigned long long* rotatedCounter,
                                             unsigned long long* invalidCounter) {
    const int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= n) return;
    if (role[i] != cfg.fluidRole) return;
    const int c = cellId[i];
    if (c < 0 || c >= cfg.numCells) {
        atomicAdd(invalidCounter, 1ull);
        return;
    }
    const double ux = cellUx[c];
    const double uy = cellUy[c];
    const double dvx = vx[i] - ux;
    const double dvy = vy[i] - uy;
    const double ca = cosA[c];
    const double sa = sinA[c];
    vx[i] = ux + ca * dvx - sa * dvy;
    vy[i] = uy + sa * dvx + ca * dvy;
    atomicAdd(rotatedCounter, 1ull);
}

// 0276: Thermostat means must be reconstructed from real post-collision
// particles only.  The SRC collision mean above may deliberately include
// virtual wall/solid particles; reusing it for relative rescaling is correct
// in fully periodic tests but biases wall/solid/piston/open-boundary cases.
// The CPU thermostat in src/thermostat.cpp recomputes these moments from the
// real particles, so the CUDA persistent fused path does the same here.
__global__ void reset_thermostat_real_moments_persistent_0276_kernel(int nc,
                                                                     double* cellMass,
                                                                     double* cellPx,
                                                                     double* cellPy,
                                                                     double* cellUx,
                                                                     double* cellUy,
                                                                     double* cellKinetic,
                                                                     double* cellScale) {
    const int c = blockIdx.x * blockDim.x + threadIdx.x;
    if (c >= nc) return;
    cellMass[c] = 0.0;
    cellPx[c] = 0.0;
    cellPy[c] = 0.0;
    cellUx[c] = 0.0;
    cellUy[c] = 0.0;
    cellKinetic[c] = 0.0;
    cellScale[c] = 1.0;
}

__global__ void deposit_thermostat_real_moments_persistent_0276_kernel(int n,
                                                                       const int* cellId,
                                                                       const unsigned char* role,
                                                                       const double* mass,
                                                                       const double* vx,
                                                                       const double* vy,
                                                                       DeviceConfig cfg,
                                                                       double* cellMass,
                                                                       double* cellPx,
                                                                       double* cellPy) {
    const int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= n) return;
    if (role[i] != cfg.fluidRole) return;
    const int c = cellId[i];
    if (c < 0 || c >= cfg.numCells) return;
    const double m = mass[i];
    atomicAdd(&cellMass[c], m);
    atomicAdd(&cellPx[c], m * vx[i]);
    atomicAdd(&cellPy[c], m * vy[i]);
}

__global__ void kinetic_persistent_kernel(int n,
                                          const int* cellId,
                                          const unsigned char* role,
                                          const double* mass,
                                          const double* vx,
                                          const double* vy,
                                          const double* cellUx,
                                          const double* cellUy,
                                          DeviceConfig cfg,
                                          double* cellKinetic) {
    const int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= n) return;
    if (role[i] != cfg.fluidRole) return;
    const int c = cellId[i];
    if (c < 0 || c >= cfg.numCells) return;
    const double dvx = vx[i] - cellUx[c];
    const double dvy = vy[i] - cellUy[c];
    atomicAdd(&cellKinetic[c], 0.5 * mass[i] * (dvx * dvx + dvy * dvy));
}

__global__ void scale_persistent_kernel(int nc,
                                        const unsigned int* count,
                                        const double* cellKinetic,
                                        double targetKBT,
                                        int minParticles,
                                        double epsilon,
                                        double* cellScale) {
    const int c = blockIdx.x * blockDim.x + threadIdx.x;
    if (c >= nc) return;
    double s = 1.0;
    const unsigned int n = count[c];
    const double K = cellKinetic[c];
    if (n >= static_cast<unsigned int>(minParticles) && K > epsilon) {
        const double dof = 2.0 * static_cast<double>(n - 1u);
        const double targetK = 0.5 * dof * targetKBT;
        s = sqrt(targetK / K);
    }
    cellScale[c] = s;
}

__global__ void apply_thermostat_persistent_kernel(int n,
                                                   const int* cellId,
                                                   const unsigned char* role,
                                                   const double* cellUx,
                                                   const double* cellUy,
                                                   const double* cellScale,
                                                   DeviceConfig cfg,
                                                   double* vx,
                                                   double* vy) {
    const int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= n) return;
    if (role[i] != cfg.fluidRole) return;
    const int c = cellId[i];
    if (c < 0 || c >= cfg.numCells) return;
    const double s = cellScale[c];
    if (s == 1.0) return;
    const double ux = cellUx[c];
    const double uy = cellUy[c];
    vx[i] = ux + s * (vx[i] - ux);
    vy[i] = uy + s * (vy[i] - uy);
}

} // namespace

bool cuda_persistent_mpcd_step_available() {
#ifdef MPCD_ENABLE_CUDA_PERSISTENT_STEP
    int count = 0;
    const cudaError_t err = cudaGetDeviceCount(&count);
    if (err != cudaSuccess) {
        cudaGetLastError();
        return false;
    }
    return count > 0;
#else
    return false;
#endif
}


namespace {
std::uint64_t g_consumedThermostatStep = 0u;
bool g_consumedThermostatValid = false;
ThermostatDiagnostics g_consumedThermostatDiag{};
}

void cuda_persistent_record_consumed_thermostat(std::uint64_t step, const ThermostatDiagnostics& diag) {
    g_consumedThermostatStep = step;
    g_consumedThermostatDiag = diag;
    g_consumedThermostatValid = true;
}

bool cuda_persistent_take_consumed_thermostat(std::uint64_t step, ThermostatDiagnostics& diag) {
    if (!g_consumedThermostatValid || g_consumedThermostatStep != step) return false;
    diag = g_consumedThermostatDiag;
    g_consumedThermostatValid = false;
    return true;
}

CudaPersistentMpcdStepDiagnostics cuda_apply_persistent_tg_impl(
    ParticleState& state,
    std::vector<int>* cellIdOut,
    std::vector<std::uint32_t>* cellCountOut,
    std::vector<double>* cellMassOut,
    std::vector<double>* cellUxOut,
    std::vector<double>* cellUyOut,
    const CudaPersistentMpcdStepConfig& config,
    const bool applyThermostat,
    ThermostatDiagnostics* thermostatDiagOut) {
#ifndef MPCD_ENABLE_CUDA_PERSISTENT_STEP
    (void)state; (void)cellIdOut; (void)cellCountOut; (void)cellMassOut; (void)cellUxOut; (void)cellUyOut; (void)config; (void)applyThermostat; (void)thermostatDiagOut;
    throw std::runtime_error("cuda_apply_persistent_tg_impl called without MPCD_ENABLE_CUDA_PERSISTENT_STEP");
#else
    validate_particle_state(state, "cuda_apply_persistent_tg_deposit_src_thermostat");
    if (config.Nx <= 0 || config.Ny <= 0) throw std::runtime_error("persistent CUDA step: invalid grid");
    if (!(config.Lx > 0.0) || !(config.Ly > 0.0)) throw std::runtime_error("persistent CUDA step: invalid domain");
    if (!(config.targetKBT > 0.0)) throw std::runtime_error("persistent CUDA step: targetKBT must be positive");

    const std::size_t n = active_fluid_count_size(state);
    const int nInt = static_cast<int>(n);
    if (static_cast<std::size_t>(nInt) != n) throw std::runtime_error("persistent CUDA step: too many particles for prototype int kernels");
    const int nc = config.Nx * config.Ny;
    const int cycles = std::max(1, config.cycles);
    const int threads = std::max(32, config.threadsPerBlock);
    const int particleBlocks = std::max(1, (nInt + threads - 1) / threads);
    const int cellBlocks = std::max(1, (nc + threads - 1) / threads);
    const int resetBlocks = std::max(particleBlocks, cellBlocks);

    std::vector<std::uint8_t> roleHost = normalized_roles(state);
    std::vector<double> cosHost(static_cast<std::size_t>(nc), std::cos(config.rotationAngle));
    std::vector<double> sinHost(static_cast<std::size_t>(nc), std::sin(config.rotationAngle));
    if (config.randomRotationSign) {
        for (int c = 0; c < nc; ++c) {
            const std::uint64_t h = splitmix64_host(config.rngSeed ^
                                                    (config.step * 0x9e3779b97f4a7c15ULL) ^
                                                    static_cast<std::uint64_t>(c));
            if ((h & 1ULL) == 0ULL) sinHost[static_cast<std::size_t>(c)] = -sinHost[static_cast<std::size_t>(c)];
        }
    }

    CudaPersistentMpcdStepDiagnostics diag{};
    diag.particlesVisited = static_cast<std::uint64_t>(n);
    diag.numCells = nc;
    diag.cycles = cycles;

    DeviceBuffers b;
    const std::size_t nBytesD = n * sizeof(double);
    const std::size_t nBytesR = n * sizeof(unsigned char);
    const std::size_t nBytesI = n * sizeof(int);
    const std::size_t cBytesD = static_cast<std::size_t>(nc) * sizeof(double);
    const std::size_t cBytesU = static_cast<std::size_t>(nc) * sizeof(unsigned int);

    const auto tTotal0 = Clock::now();
    auto t0 = Clock::now();

    MPCD_CUDA_CHECK(cudaMalloc(&b.x, nBytesD));
    MPCD_CUDA_CHECK(cudaMalloc(&b.y, nBytesD));
    MPCD_CUDA_CHECK(cudaMalloc(&b.vx, nBytesD));
    MPCD_CUDA_CHECK(cudaMalloc(&b.vy, nBytesD));
    MPCD_CUDA_CHECK(cudaMalloc(&b.mass, nBytesD));
    MPCD_CUDA_CHECK(cudaMalloc(&b.role, nBytesR));
    MPCD_CUDA_CHECK(cudaMalloc(&b.cellId, nBytesI));
    MPCD_CUDA_CHECK(cudaMalloc(&b.count, cBytesU));
    MPCD_CUDA_CHECK(cudaMalloc(&b.cellMass, cBytesD));
    MPCD_CUDA_CHECK(cudaMalloc(&b.cellPx, cBytesD));
    MPCD_CUDA_CHECK(cudaMalloc(&b.cellPy, cBytesD));
    MPCD_CUDA_CHECK(cudaMalloc(&b.cellUx, cBytesD));
    MPCD_CUDA_CHECK(cudaMalloc(&b.cellUy, cBytesD));
    MPCD_CUDA_CHECK(cudaMalloc(&b.cosA, cBytesD));
    MPCD_CUDA_CHECK(cudaMalloc(&b.sinA, cBytesD));
    MPCD_CUDA_CHECK(cudaMalloc(&b.cellKinetic, cBytesD));
    MPCD_CUDA_CHECK(cudaMalloc(&b.cellScale, cBytesD));
    MPCD_CUDA_CHECK(cudaMalloc(&b.fluidCounter, sizeof(unsigned long long)));
    MPCD_CUDA_CHECK(cudaMalloc(&b.rotatedCounter, sizeof(unsigned long long)));
    MPCD_CUDA_CHECK(cudaMalloc(&b.invalidCounter, sizeof(unsigned long long)));

    MPCD_CUDA_CHECK(cudaMemcpy(b.x, state.x.data(), nBytesD, cudaMemcpyHostToDevice));
    MPCD_CUDA_CHECK(cudaMemcpy(b.y, state.y.data(), nBytesD, cudaMemcpyHostToDevice));
    MPCD_CUDA_CHECK(cudaMemcpy(b.vx, state.vx.data(), nBytesD, cudaMemcpyHostToDevice));
    MPCD_CUDA_CHECK(cudaMemcpy(b.vy, state.vy.data(), nBytesD, cudaMemcpyHostToDevice));
    MPCD_CUDA_CHECK(cudaMemcpy(b.mass, state.mass.data(), nBytesD, cudaMemcpyHostToDevice));
    MPCD_CUDA_CHECK(cudaMemcpy(b.role, roleHost.data(), nBytesR, cudaMemcpyHostToDevice));
    MPCD_CUDA_CHECK(cudaMemcpy(b.cosA, cosHost.data(), cBytesD, cudaMemcpyHostToDevice));
    MPCD_CUDA_CHECK(cudaMemcpy(b.sinA, sinHost.data(), cBytesD, cudaMemcpyHostToDevice));
    MPCD_CUDA_CHECK(cudaMemset(b.fluidCounter, 0, sizeof(unsigned long long)));
    MPCD_CUDA_CHECK(cudaMemset(b.rotatedCounter, 0, sizeof(unsigned long long)));
    MPCD_CUDA_CHECK(cudaMemset(b.invalidCounter, 0, sizeof(unsigned long long)));
    MPCD_CUDA_CHECK(cudaDeviceSynchronize());
    diag.uploadSeconds = seconds_since(t0);

    DeviceConfig cfg{};
    cfg.Nx = config.Nx;
    cfg.Ny = config.Ny;
    cfg.numCells = nc;
    cfg.Lx = config.Lx;
    cfg.Ly = config.Ly;
    cfg.dx = config.Lx / static_cast<double>(config.Nx);
    cfg.dy = config.Ly / static_cast<double>(config.Ny);
    cfg.shiftX = config.shiftX;
    cfg.shiftY = config.shiftY;
    cfg.periodicX = config.periodicX ? 1 : 0;
    cfg.periodicY = config.periodicY ? 1 : 0;
    cfg.domainXMin = config.domainXMin;
    cfg.domainXMax = config.domainXMax;
    cfg.domainYMin = config.domainYMin;
    cfg.domainYMax = config.domainYMax;
    cfg.wallLeftEnabled = config.wallLeftEnabled;
    cfg.wallRightEnabled = config.wallRightEnabled;
    cfg.wallBottomEnabled = config.wallBottomEnabled;
    cfg.wallTopEnabled = config.wallTopEnabled;
    cfg.wallAccommodation = config.wallAccommodation;
    cfg.wallGamma = config.wallGamma;
    cfg.wallVpMass = config.wallVpMass;
    cfg.wallUxLeft = config.wallUxLeft;
    cfg.wallUyLeft = config.wallUyLeft;
    cfg.wallUxRight = config.wallUxRight;
    cfg.wallUyRight = config.wallUyRight;
    cfg.wallUxBottom = config.wallUxBottom;
    cfg.wallUyBottom = config.wallUyBottom;
    cfg.wallUxTop = config.wallUxTop;
    cfg.wallUyTop = config.wallUyTop;
    cfg.immersedRectangleEnabled = config.immersedRectangleEnabled;
    cfg.immersedFractionSamples = config.immersedFractionSamples;
    cfg.immersedXMin = config.immersedXMin;
    cfg.immersedXMax = config.immersedXMax;
    cfg.immersedYMin = config.immersedYMin;
    cfg.immersedYMax = config.immersedYMax;
    cfg.immersedCircleEnabled = config.immersedCircleEnabled;
    cfg.immersedCircleCx = config.immersedCircleCx;
    cfg.immersedCircleCy = config.immersedCircleCy;
    cfg.immersedCircleR = config.immersedCircleR;
    cfg.immersedWallUx = config.immersedWallUx;
    cfg.immersedWallUy = config.immersedWallUy;
    cfg.fusedStreamDeposit0274 = config.fusedStreamDeposit0274;
    cfg.fusedStreamMode0274 = config.fusedStreamMode0274;
    cfg.streamDt0274 = config.streamDt0274;
    cfg.streamBodyAccelerationX0274 = config.streamBodyAccelerationX0274;
    cfg.streamBodyAccelerationY0274 = config.streamBodyAccelerationY0274;
    cfg.streamTaylorGreenEnable0274 = config.streamTaylorGreenEnable0274;
    cfg.streamTaylorGreenAmplitude0274 = config.streamTaylorGreenAmplitude0274;
    cfg.streamTaylorGreenModeX0274 = config.streamTaylorGreenModeX0274;
    cfg.streamTaylorGreenModeY0274 = config.streamTaylorGreenModeY0274;
    cfg.streamBottomMode0274 = config.streamBottomMode0274;
    cfg.streamTopMode0274 = config.streamTopMode0274;
    cfg.streamWallUxBottom0274 = config.streamWallUxBottom0274;
    cfg.streamWallUyBottom0274 = config.streamWallUyBottom0274;
    cfg.streamWallUxTop0274 = config.streamWallUxTop0274;
    cfg.streamWallUyTop0274 = config.streamWallUyTop0274;
    cfg.fluidRole = static_cast<unsigned char>(kParticleRoleFluid);

    t0 = Clock::now();
    for (int cycle = 0; cycle < cycles; ++cycle) {
        reset_persistent_cells_kernel<<<resetBlocks, threads>>>(nInt, nc, b.cellId, b.count, b.cellMass,
                                                                b.cellPx, b.cellPy, b.cellUx, b.cellUy,
                                                                b.cellKinetic, b.cellScale);
        MPCD_CUDA_CHECK(cudaGetLastError());
        deposit_persistent_kernel<<<particleBlocks, threads>>>(nInt, b.x, b.y, b.vx, b.vy, b.mass, b.role,
                                                               cfg, b.cellId, b.count, b.cellMass, b.cellPx,
                                                               b.cellPy, b.fluidCounter);
        MPCD_CUDA_CHECK(cudaGetLastError());
        if (cfg.wallLeftEnabled || cfg.wallRightEnabled || cfg.wallBottomEnabled || cfg.wallTopEnabled || cfg.immersedRectangleEnabled || cfg.immersedCircleEnabled) {
            add_wall_virtual_faces_persistent_kernel<<<cellBlocks, threads>>>(nc, cfg, b.cellMass, b.cellPx, b.cellPy);
            MPCD_CUDA_CHECK(cudaGetLastError());
        }
        finalize_velocity_persistent_kernel<<<cellBlocks, threads>>>(nc, b.cellMass, b.cellPx, b.cellPy,
                                                                     b.cellUx, b.cellUy);
        MPCD_CUDA_CHECK(cudaGetLastError());
        src_rotate_persistent_kernel<<<particleBlocks, threads>>>(nInt, b.cellId, b.role, b.cellUx, b.cellUy,
                                                                  b.cosA, b.sinA, cfg, b.vx, b.vy,
                                                                  b.rotatedCounter, b.invalidCounter);
        MPCD_CUDA_CHECK(cudaGetLastError());
        if (applyThermostat) {
            reset_thermostat_real_moments_persistent_0276_kernel<<<cellBlocks, threads>>>(
                nc, b.cellMass, b.cellPx, b.cellPy, b.cellUx, b.cellUy, b.cellKinetic, b.cellScale);
            MPCD_CUDA_CHECK(cudaGetLastError());
            deposit_thermostat_real_moments_persistent_0276_kernel<<<particleBlocks, threads>>>(
                nInt, b.cellId, b.role, b.mass, b.vx, b.vy, cfg, b.cellMass, b.cellPx, b.cellPy);
            MPCD_CUDA_CHECK(cudaGetLastError());
            finalize_velocity_persistent_kernel<<<cellBlocks, threads>>>(nc, b.cellMass, b.cellPx, b.cellPy,
                                                                         b.cellUx, b.cellUy);
            MPCD_CUDA_CHECK(cudaGetLastError());
            kinetic_persistent_kernel<<<particleBlocks, threads>>>(nInt, b.cellId, b.role, b.mass, b.vx, b.vy,
                                                                   b.cellUx, b.cellUy, cfg, b.cellKinetic);
            MPCD_CUDA_CHECK(cudaGetLastError());
            scale_persistent_kernel<<<cellBlocks, threads>>>(nc, b.count, b.cellKinetic, config.targetKBT,
                                                             std::max(1, config.thermostatMinParticles),
                                                             config.thermostatEpsilon, b.cellScale);
            MPCD_CUDA_CHECK(cudaGetLastError());
            apply_thermostat_persistent_kernel<<<particleBlocks, threads>>>(nInt, b.cellId, b.role, b.cellUx,
                                                                           b.cellUy, b.cellScale, cfg, b.vx, b.vy);
            MPCD_CUDA_CHECK(cudaGetLastError());
        }
    }
    MPCD_CUDA_CHECK(cudaDeviceSynchronize());
    diag.kernelSeconds = seconds_since(t0);

    t0 = Clock::now();
    MPCD_CUDA_CHECK(cudaMemcpy(state.vx.data(), b.vx, nBytesD, cudaMemcpyDeviceToHost));
    MPCD_CUDA_CHECK(cudaMemcpy(state.vy.data(), b.vy, nBytesD, cudaMemcpyDeviceToHost));
    if (cellIdOut != nullptr) {
        cellIdOut->assign(n, -1);
        MPCD_CUDA_CHECK(cudaMemcpy(cellIdOut->data(), b.cellId, nBytesI, cudaMemcpyDeviceToHost));
    }
    if (cellCountOut != nullptr) {
        cellCountOut->assign(static_cast<std::size_t>(nc), 0u);
        MPCD_CUDA_CHECK(cudaMemcpy(cellCountOut->data(), b.count, cBytesU, cudaMemcpyDeviceToHost));
    }
    if (cellMassOut != nullptr) {
        cellMassOut->assign(static_cast<std::size_t>(nc), 0.0);
        MPCD_CUDA_CHECK(cudaMemcpy(cellMassOut->data(), b.cellMass, cBytesD, cudaMemcpyDeviceToHost));
    }
    if (cellUxOut != nullptr) {
        cellUxOut->assign(static_cast<std::size_t>(nc), 0.0);
        MPCD_CUDA_CHECK(cudaMemcpy(cellUxOut->data(), b.cellUx, cBytesD, cudaMemcpyDeviceToHost));
    }
    if (cellUyOut != nullptr) {
        cellUyOut->assign(static_cast<std::size_t>(nc), 0.0);
        MPCD_CUDA_CHECK(cudaMemcpy(cellUyOut->data(), b.cellUy, cBytesD, cudaMemcpyDeviceToHost));
    }
    std::vector<double> kineticHost;
    std::vector<double> scaleHost;
    if (applyThermostat && thermostatDiagOut != nullptr) {
        kineticHost.assign(static_cast<std::size_t>(nc), 0.0);
        scaleHost.assign(static_cast<std::size_t>(nc), 1.0);
        MPCD_CUDA_CHECK(cudaMemcpy(kineticHost.data(), b.cellKinetic, cBytesD, cudaMemcpyDeviceToHost));
        MPCD_CUDA_CHECK(cudaMemcpy(scaleHost.data(), b.cellScale, cBytesD, cudaMemcpyDeviceToHost));
    }
    unsigned long long fluid = 0ull, rotated = 0ull, invalid = 0ull;
    MPCD_CUDA_CHECK(cudaMemcpy(&fluid, b.fluidCounter, sizeof(unsigned long long), cudaMemcpyDeviceToHost));
    MPCD_CUDA_CHECK(cudaMemcpy(&rotated, b.rotatedCounter, sizeof(unsigned long long), cudaMemcpyDeviceToHost));
    MPCD_CUDA_CHECK(cudaMemcpy(&invalid, b.invalidCounter, sizeof(unsigned long long), cudaMemcpyDeviceToHost));
    MPCD_CUDA_CHECK(cudaDeviceSynchronize());
    diag.downloadSeconds = seconds_since(t0);

    diag.fluidParticles = static_cast<std::uint64_t>(fluid) / static_cast<std::uint64_t>(cycles);
    diag.particlesRotated = static_cast<std::uint64_t>(rotated);
    diag.invalidCellParticles = static_cast<std::uint64_t>(invalid);

    if (applyThermostat && thermostatDiagOut != nullptr && cellCountOut != nullptr && !kineticHost.empty()) {
        ThermostatDiagnostics td{};
        double totalKBefore = 0.0;
        double targetKTotal = 0.0;
        double scaleSum = 0.0;
        double scaleMin = 1.0e300;
        double scaleMax = 0.0;
        std::uint64_t dofTotal = 0u;
        for (int c = 0; c < nc; ++c) {
            const std::size_t kk = static_cast<std::size_t>(c);
            const std::uint32_t count = (*cellCountOut)[kk];
            const double K = kineticHost[kk];
            if (count < static_cast<std::uint32_t>(std::max(1, config.thermostatMinParticles))) continue;
            if (!(K > config.thermostatEpsilon)) continue;
            const double dof = 2.0 * static_cast<double>(count - 1u);
            const double targetK = 0.5 * dof * config.targetKBT;
            const double scale = scaleHost[kk];
            totalKBefore += K;
            targetKTotal += targetK;
            dofTotal += static_cast<std::uint64_t>(2u * (count - 1u));
            td.cellsRescaled += 1u;
            td.particlesRescaled += static_cast<std::uint64_t>(count);
            scaleSum += scale;
            if (scale < scaleMin) scaleMin = scale;
            if (scale > scaleMax) scaleMax = scale;
        }
        td.applied = td.cellsRescaled > 0u;
        td.kBTBefore = dofTotal > 0u ? (2.0 * totalKBefore / static_cast<double>(dofTotal)) : 0.0;
        td.kBTAfter = dofTotal > 0u ? (2.0 * targetKTotal / static_cast<double>(dofTotal)) : 0.0;
        td.scaleMean = td.cellsRescaled > 0u ? scaleSum / static_cast<double>(td.cellsRescaled) : 1.0;
        td.scaleMin = td.cellsRescaled > 0u ? scaleMin : 1.0;
        td.scaleMax = td.cellsRescaled > 0u ? scaleMax : 1.0;
        *thermostatDiagOut = td;
        diag.thermostatCellsRescaled = td.cellsRescaled;
        diag.thermostatParticlesRescaled = td.particlesRescaled;
        diag.thermostatKBTBefore = td.kBTBefore;
        diag.thermostatKBTAfter = td.kBTAfter;
        diag.thermostatScaleMean = td.scaleMean;
        diag.thermostatScaleMin = td.scaleMin;
        diag.thermostatScaleMax = td.scaleMax;
    }

    diag.totalSeconds = seconds_since(tTotal0);
    return diag;
#endif
}


CudaPersistentMpcdStepDiagnostics cuda_apply_persistent_tg_deposit_src_thermostat(
    ParticleState& state,
    const CudaPersistentMpcdStepConfig& config) {
    return cuda_apply_persistent_tg_impl(state, nullptr, nullptr, nullptr, nullptr, nullptr, config, true, nullptr);
}

CudaPersistentMpcdStepDiagnostics cuda_apply_persistent_tg_deposit_src_collision(
    ParticleState& state,
    std::vector<int>& cellIdOut,
    std::vector<std::uint32_t>& cellCountOut,
    std::vector<double>& cellMassOut,
    std::vector<double>& cellUxOut,
    std::vector<double>& cellUyOut,
    const CudaPersistentMpcdStepConfig& config) {
    return cuda_apply_persistent_tg_impl(state, &cellIdOut, &cellCountOut, &cellMassOut, &cellUxOut, &cellUyOut, config, false, nullptr);
}

CudaPersistentMpcdStepDiagnostics cuda_apply_persistent_tg_deposit_src_collision_thermostat(
    ParticleState& state,
    std::vector<int>& cellIdOut,
    std::vector<std::uint32_t>& cellCountOut,
    std::vector<double>& cellMassOut,
    std::vector<double>& cellUxOut,
    std::vector<double>& cellUyOut,
    const CudaPersistentMpcdStepConfig& config,
    ThermostatDiagnostics* thermostatDiagOut) {
    return cuda_apply_persistent_tg_impl(state, &cellIdOut, &cellCountOut, &cellMassOut, &cellUxOut, &cellUyOut, config, true, thermostatDiagOut);
}


CudaPersistentMpcdStepDiagnostics cuda_apply_persistent_tg_deposit_src_collision_thermostat(
    CudaParticleState& gpuState,
    ParticleState& downloadTarget,
    std::vector<int>& cellIdOut,
    std::vector<std::uint32_t>& cellCountOut,
    std::vector<double>& cellMassOut,
    std::vector<double>& cellUxOut,
    std::vector<double>& cellUyOut,
    const CudaPersistentMpcdStepConfig& config,
    ThermostatDiagnostics* thermostatDiagOut) {
#if !defined(MPCD_ENABLE_CUDA_PERSISTENT_STEP) || !defined(MPCD_ENABLE_CUDA_PARTICLE_STATE)
    (void)gpuState; (void)downloadTarget; (void)cellIdOut; (void)cellCountOut; (void)cellMassOut; (void)cellUxOut; (void)cellUyOut; (void)config; (void)thermostatDiagOut;
    throw std::runtime_error("cuda_apply_persistent_tg_deposit_src_collision_thermostat(CudaParticleState) requires MPCD_ENABLE_CUDA_PERSISTENT_STEP and MPCD_ENABLE_CUDA_PARTICLE_STATE");
#else
    validate_particle_state(downloadTarget, "cuda_apply_persistent_tg_deposit_src_collision_thermostat(shared downloadTarget)");
    if (config.Nx <= 0 || config.Ny <= 0) throw std::runtime_error("persistent CUDA shared-state step: invalid grid");
    if (!(config.Lx > 0.0) || !(config.Ly > 0.0)) throw std::runtime_error("persistent CUDA shared-state step: invalid domain");
    if (!(config.targetKBT > 0.0)) throw std::runtime_error("persistent CUDA shared-state step: targetKBT must be positive");

    const CudaParticleDeviceView pv = gpuState.device_view();
    if (pv.n == 0u) throw std::runtime_error("persistent CUDA shared-state step: empty CudaParticleState");
    if (downloadTarget.Np != pv.n) throw std::runtime_error("persistent CUDA shared-state step: host particle count mismatch");
    if (pv.x == nullptr || pv.y == nullptr || pv.vx == nullptr || pv.vy == nullptr || pv.mass == nullptr || pv.role == nullptr) {
        throw std::runtime_error("persistent CUDA shared-state step: incomplete CudaParticleState device view");
    }

    const std::uint64_t nActive64 = pv.nActiveFluid > 0u ? pv.nActiveFluid : active_fluid_count(downloadTarget);
    const std::size_t n = static_cast<std::size_t>(nActive64);
    const int nInt = static_cast<int>(n);
    if (static_cast<std::size_t>(nInt) != n) throw std::runtime_error("persistent CUDA shared-state step: too many particles for prototype int kernels");
    const int nc = config.Nx * config.Ny;
    const int cycles = std::max(1, config.cycles);
    const int threads = std::max(32, config.threadsPerBlock);
    const int particleBlocks = std::max(1, (nInt + threads - 1) / threads);
    const int cellBlocks = std::max(1, (nc + threads - 1) / threads);
    const int resetBlocks = std::max(particleBlocks, cellBlocks);

    std::vector<double> cosHost(static_cast<std::size_t>(nc), std::cos(config.rotationAngle));
    std::vector<double> sinHost(static_cast<std::size_t>(nc), std::sin(config.rotationAngle));
    if (config.randomRotationSign) {
        for (int c = 0; c < nc; ++c) {
            const std::uint64_t h = splitmix64_host(config.rngSeed ^
                                                    (config.step * 0x9e3779b97f4a7c15ULL) ^
                                                    static_cast<std::uint64_t>(c));
            if ((h & 1ULL) == 0ULL) sinHost[static_cast<std::size_t>(c)] = -sinHost[static_cast<std::size_t>(c)];
        }
    }

    CudaPersistentMpcdStepDiagnostics diag{};
    diag.particlesVisited = nActive64;
    diag.numCells = nc;
    diag.cycles = cycles;

    // 0315f: shared-state classic resident mode keeps the device particle arrays
    // authoritative across boundary -> immersed -> collision -> thermostat.
    // Avoid downloading velocities for the inactive reservoir; host consumers
    // synchronize lazily through active-prefix downloads when needed.
    const bool residentClassicMode0315f =
        env_flag_enabled_0257("MPCD_CUDA_CLASSIC_SRC_PERIODIC_RESIDENT_0260", false) ||
        env_flag_enabled_0257("MPCD_CUDA_CLASSIC_SRC_WALL_RESIDENT_0261", false) ||
        env_flag_enabled_0257("MPCD_CUDA_CLASSIC_SRC_SOLID_RESIDENT_0262", false) ||
        env_flag_enabled_0257("MPCD_CUDA_CLASSIC_SRC_IO_FULLFACE_RESIDENT_0263", false) ||
        env_flag_enabled_0257("MPCD_CUDA_CLASSIC_SRC_IO_SEGMENTED_RESIDENT_0264", false);
    const bool skipVelocityDownload0315f =
        residentClassicMode0315f &&
        !env_flag_enabled_0257("MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_DISABLE_SKIP_VELOCITY_DOWNLOAD_0315F", false);

    DeviceBuffers b;
    const std::size_t nBytesI = n * sizeof(int);
    const std::size_t cBytesD = static_cast<std::size_t>(nc) * sizeof(double);
    const std::size_t cBytesU = static_cast<std::size_t>(nc) * sizeof(unsigned int);

    const auto tTotal0 = Clock::now();
    auto t0 = Clock::now();

    // 0219: particle arrays are owned by CudaParticleState. Allocate only the
    // transient cell/workspace arrays needed by the persistent substep.
    MPCD_CUDA_CHECK(cudaMalloc(&b.cellId, nBytesI));
    MPCD_CUDA_CHECK(cudaMalloc(&b.count, cBytesU));
    MPCD_CUDA_CHECK(cudaMalloc(&b.cellMass, cBytesD));
    MPCD_CUDA_CHECK(cudaMalloc(&b.cellPx, cBytesD));
    MPCD_CUDA_CHECK(cudaMalloc(&b.cellPy, cBytesD));
    MPCD_CUDA_CHECK(cudaMalloc(&b.cellUx, cBytesD));
    MPCD_CUDA_CHECK(cudaMalloc(&b.cellUy, cBytesD));
    MPCD_CUDA_CHECK(cudaMalloc(&b.cosA, cBytesD));
    MPCD_CUDA_CHECK(cudaMalloc(&b.sinA, cBytesD));
    MPCD_CUDA_CHECK(cudaMalloc(&b.cellKinetic, cBytesD));
    MPCD_CUDA_CHECK(cudaMalloc(&b.cellScale, cBytesD));
    MPCD_CUDA_CHECK(cudaMalloc(&b.fluidCounter, sizeof(unsigned long long)));
    MPCD_CUDA_CHECK(cudaMalloc(&b.rotatedCounter, sizeof(unsigned long long)));
    MPCD_CUDA_CHECK(cudaMalloc(&b.invalidCounter, sizeof(unsigned long long)));

    MPCD_CUDA_CHECK(cudaMemcpy(b.cosA, cosHost.data(), cBytesD, cudaMemcpyHostToDevice));
    MPCD_CUDA_CHECK(cudaMemcpy(b.sinA, sinHost.data(), cBytesD, cudaMemcpyHostToDevice));
    MPCD_CUDA_CHECK(cudaMemset(b.fluidCounter, 0, sizeof(unsigned long long)));
    MPCD_CUDA_CHECK(cudaMemset(b.rotatedCounter, 0, sizeof(unsigned long long)));
    MPCD_CUDA_CHECK(cudaMemset(b.invalidCounter, 0, sizeof(unsigned long long)));
    MPCD_CUDA_CHECK(cudaDeviceSynchronize());
    diag.uploadSeconds = seconds_since(t0);

    DeviceConfig cfg{};
    cfg.Nx = config.Nx;
    cfg.Ny = config.Ny;
    cfg.numCells = nc;
    cfg.Lx = config.Lx;
    cfg.Ly = config.Ly;
    cfg.dx = config.Lx / static_cast<double>(config.Nx);
    cfg.dy = config.Ly / static_cast<double>(config.Ny);
    cfg.shiftX = config.shiftX;
    cfg.shiftY = config.shiftY;
    cfg.periodicX = config.periodicX ? 1 : 0;
    cfg.periodicY = config.periodicY ? 1 : 0;
    cfg.domainXMin = config.domainXMin;
    cfg.domainXMax = config.domainXMax;
    cfg.domainYMin = config.domainYMin;
    cfg.domainYMax = config.domainYMax;
    cfg.wallLeftEnabled = config.wallLeftEnabled;
    cfg.wallRightEnabled = config.wallRightEnabled;
    cfg.wallBottomEnabled = config.wallBottomEnabled;
    cfg.wallTopEnabled = config.wallTopEnabled;
    cfg.wallAccommodation = config.wallAccommodation;
    cfg.wallGamma = config.wallGamma;
    cfg.wallVpMass = config.wallVpMass;
    cfg.wallUxLeft = config.wallUxLeft;
    cfg.wallUyLeft = config.wallUyLeft;
    cfg.wallUxRight = config.wallUxRight;
    cfg.wallUyRight = config.wallUyRight;
    cfg.wallUxBottom = config.wallUxBottom;
    cfg.wallUyBottom = config.wallUyBottom;
    cfg.wallUxTop = config.wallUxTop;
    cfg.wallUyTop = config.wallUyTop;
    cfg.immersedRectangleEnabled = config.immersedRectangleEnabled;
    cfg.immersedFractionSamples = config.immersedFractionSamples;
    cfg.immersedXMin = config.immersedXMin;
    cfg.immersedXMax = config.immersedXMax;
    cfg.immersedYMin = config.immersedYMin;
    cfg.immersedYMax = config.immersedYMax;
    cfg.immersedCircleEnabled = config.immersedCircleEnabled;
    cfg.immersedCircleCx = config.immersedCircleCx;
    cfg.immersedCircleCy = config.immersedCircleCy;
    cfg.immersedCircleR = config.immersedCircleR;
    cfg.immersedWallUx = config.immersedWallUx;
    cfg.immersedWallUy = config.immersedWallUy;
    cfg.fusedStreamDeposit0274 = config.fusedStreamDeposit0274;
    cfg.fusedStreamMode0274 = config.fusedStreamMode0274;
    cfg.streamDt0274 = config.streamDt0274;
    cfg.streamBodyAccelerationX0274 = config.streamBodyAccelerationX0274;
    cfg.streamBodyAccelerationY0274 = config.streamBodyAccelerationY0274;
    cfg.streamTaylorGreenEnable0274 = config.streamTaylorGreenEnable0274;
    cfg.streamTaylorGreenAmplitude0274 = config.streamTaylorGreenAmplitude0274;
    cfg.streamTaylorGreenModeX0274 = config.streamTaylorGreenModeX0274;
    cfg.streamTaylorGreenModeY0274 = config.streamTaylorGreenModeY0274;
    cfg.streamBottomMode0274 = config.streamBottomMode0274;
    cfg.streamTopMode0274 = config.streamTopMode0274;
    cfg.streamWallUxBottom0274 = config.streamWallUxBottom0274;
    cfg.streamWallUyBottom0274 = config.streamWallUyBottom0274;
    cfg.streamWallUxTop0274 = config.streamWallUxTop0274;
    cfg.streamWallUyTop0274 = config.streamWallUyTop0274;
    cfg.fluidRole = static_cast<unsigned char>(kParticleRoleFluid);

    t0 = Clock::now();
    for (int cycle = 0; cycle < cycles; ++cycle) {
        reset_persistent_cells_kernel<<<resetBlocks, threads>>>(nInt, nc, b.cellId, b.count, b.cellMass,
                                                                b.cellPx, b.cellPy, b.cellUx, b.cellUy,
                                                                b.cellKinetic, b.cellScale);
        MPCD_CUDA_CHECK(cudaGetLastError());
        deposit_persistent_kernel<<<particleBlocks, threads>>>(nInt, pv.x, pv.y, pv.vx, pv.vy, pv.mass, pv.role,
                                                               cfg, b.cellId, b.count, b.cellMass, b.cellPx,
                                                               b.cellPy, b.fluidCounter);
        MPCD_CUDA_CHECK(cudaGetLastError());
        if (cfg.wallLeftEnabled || cfg.wallRightEnabled || cfg.wallBottomEnabled || cfg.wallTopEnabled || cfg.immersedRectangleEnabled || cfg.immersedCircleEnabled) {
            add_wall_virtual_faces_persistent_kernel<<<cellBlocks, threads>>>(nc, cfg, b.cellMass, b.cellPx, b.cellPy);
            MPCD_CUDA_CHECK(cudaGetLastError());
        }
        finalize_velocity_persistent_kernel<<<cellBlocks, threads>>>(nc, b.cellMass, b.cellPx, b.cellPy,
                                                                     b.cellUx, b.cellUy);
        MPCD_CUDA_CHECK(cudaGetLastError());
        src_rotate_persistent_kernel<<<particleBlocks, threads>>>(nInt, b.cellId, pv.role, b.cellUx, b.cellUy,
                                                                  b.cosA, b.sinA, cfg, pv.vx, pv.vy,
                                                                  b.rotatedCounter, b.invalidCounter);
        MPCD_CUDA_CHECK(cudaGetLastError());
        reset_thermostat_real_moments_persistent_0276_kernel<<<cellBlocks, threads>>>(
            nc, b.cellMass, b.cellPx, b.cellPy, b.cellUx, b.cellUy, b.cellKinetic, b.cellScale);
        MPCD_CUDA_CHECK(cudaGetLastError());
        deposit_thermostat_real_moments_persistent_0276_kernel<<<particleBlocks, threads>>>(
            nInt, b.cellId, pv.role, pv.mass, pv.vx, pv.vy, cfg, b.cellMass, b.cellPx, b.cellPy);
        MPCD_CUDA_CHECK(cudaGetLastError());
        finalize_velocity_persistent_kernel<<<cellBlocks, threads>>>(nc, b.cellMass, b.cellPx, b.cellPy,
                                                                     b.cellUx, b.cellUy);
        MPCD_CUDA_CHECK(cudaGetLastError());
        kinetic_persistent_kernel<<<particleBlocks, threads>>>(nInt, b.cellId, pv.role, pv.mass, pv.vx, pv.vy,
                                                               b.cellUx, b.cellUy, cfg, b.cellKinetic);
        MPCD_CUDA_CHECK(cudaGetLastError());
        scale_persistent_kernel<<<cellBlocks, threads>>>(nc, b.count, b.cellKinetic, config.targetKBT,
                                                         std::max(1, config.thermostatMinParticles),
                                                         config.thermostatEpsilon, b.cellScale);
        MPCD_CUDA_CHECK(cudaGetLastError());
        apply_thermostat_persistent_kernel<<<particleBlocks, threads>>>(nInt, b.cellId, pv.role, b.cellUx,
                                                                       b.cellUy, b.cellScale, cfg, pv.vx, pv.vy);
        MPCD_CUDA_CHECK(cudaGetLastError());
    }
    MPCD_CUDA_CHECK(cudaDeviceSynchronize());
    diag.kernelSeconds = seconds_since(t0);

    t0 = Clock::now();
    if (!skipVelocityDownload0315f) {
        gpuState.download_velocities(downloadTarget);
    }
    cellIdOut.assign(n, -1);
    cellCountOut.assign(static_cast<std::size_t>(nc), 0u);
    if (!skipVelocityDownload0315f) {
        cellMassOut.assign(static_cast<std::size_t>(nc), 0.0);
        cellUxOut.assign(static_cast<std::size_t>(nc), 0.0);
        cellUyOut.assign(static_cast<std::size_t>(nc), 0.0);
        MPCD_CUDA_CHECK(cudaMemcpy(cellIdOut.data(), b.cellId, nBytesI, cudaMemcpyDeviceToHost));
    } else {
        cellMassOut.clear();
        cellUxOut.clear();
        cellUyOut.clear();
    }
    MPCD_CUDA_CHECK(cudaMemcpy(cellCountOut.data(), b.count, cBytesU, cudaMemcpyDeviceToHost));
    if (!skipVelocityDownload0315f) {
        MPCD_CUDA_CHECK(cudaMemcpy(cellMassOut.data(), b.cellMass, cBytesD, cudaMemcpyDeviceToHost));
        MPCD_CUDA_CHECK(cudaMemcpy(cellUxOut.data(), b.cellUx, cBytesD, cudaMemcpyDeviceToHost));
        MPCD_CUDA_CHECK(cudaMemcpy(cellUyOut.data(), b.cellUy, cBytesD, cudaMemcpyDeviceToHost));
    }

    std::vector<double> kineticHost(static_cast<std::size_t>(nc), 0.0);
    std::vector<double> scaleHost(static_cast<std::size_t>(nc), 1.0);
    if (thermostatDiagOut != nullptr) {
        MPCD_CUDA_CHECK(cudaMemcpy(kineticHost.data(), b.cellKinetic, cBytesD, cudaMemcpyDeviceToHost));
        MPCD_CUDA_CHECK(cudaMemcpy(scaleHost.data(), b.cellScale, cBytesD, cudaMemcpyDeviceToHost));
    }
    unsigned long long fluid = 0ull, rotated = 0ull, invalid = 0ull;
    MPCD_CUDA_CHECK(cudaMemcpy(&fluid, b.fluidCounter, sizeof(unsigned long long), cudaMemcpyDeviceToHost));
    MPCD_CUDA_CHECK(cudaMemcpy(&rotated, b.rotatedCounter, sizeof(unsigned long long), cudaMemcpyDeviceToHost));
    MPCD_CUDA_CHECK(cudaMemcpy(&invalid, b.invalidCounter, sizeof(unsigned long long), cudaMemcpyDeviceToHost));
    MPCD_CUDA_CHECK(cudaDeviceSynchronize());
    diag.downloadSeconds = seconds_since(t0);

    diag.fluidParticles = static_cast<std::uint64_t>(fluid) / static_cast<std::uint64_t>(cycles);
    diag.particlesRotated = static_cast<std::uint64_t>(rotated);
    diag.invalidCellParticles = static_cast<std::uint64_t>(invalid);

    if (thermostatDiagOut != nullptr) {
        ThermostatDiagnostics td{};
        double totalKBefore = 0.0;
        double targetKTotal = 0.0;
        double scaleSum = 0.0;
        double scaleMin = 1.0e300;
        double scaleMax = 0.0;
        std::uint64_t dofTotal = 0u;
        for (int c = 0; c < nc; ++c) {
            const std::size_t kk = static_cast<std::size_t>(c);
            const std::uint32_t count = cellCountOut[kk];
            const double K = kineticHost[kk];
            if (count < static_cast<std::uint32_t>(std::max(1, config.thermostatMinParticles))) continue;
            if (!(K > config.thermostatEpsilon)) continue;
            const double dof = 2.0 * static_cast<double>(count - 1u);
            const double targetK = 0.5 * dof * config.targetKBT;
            const double scale = scaleHost[kk];
            totalKBefore += K;
            targetKTotal += targetK;
            dofTotal += static_cast<std::uint64_t>(2u * (count - 1u));
            td.cellsRescaled += 1u;
            td.particlesRescaled += static_cast<std::uint64_t>(count);
            scaleSum += scale;
            if (scale < scaleMin) scaleMin = scale;
            if (scale > scaleMax) scaleMax = scale;
        }
        td.applied = td.cellsRescaled > 0u;
        td.kBTBefore = dofTotal > 0u ? (2.0 * totalKBefore / static_cast<double>(dofTotal)) : 0.0;
        td.kBTAfter = dofTotal > 0u ? (2.0 * targetKTotal / static_cast<double>(dofTotal)) : 0.0;
        td.scaleMean = td.cellsRescaled > 0u ? scaleSum / static_cast<double>(td.cellsRescaled) : 1.0;
        td.scaleMin = td.cellsRescaled > 0u ? scaleMin : 1.0;
        td.scaleMax = td.cellsRescaled > 0u ? scaleMax : 1.0;
        *thermostatDiagOut = td;
        diag.thermostatCellsRescaled = td.cellsRescaled;
        diag.thermostatParticlesRescaled = td.particlesRescaled;
        diag.thermostatKBTBefore = td.kBTBefore;
        diag.thermostatKBTAfter = td.kBTAfter;
        diag.thermostatScaleMean = td.scaleMean;
        diag.thermostatScaleMin = td.scaleMin;
        diag.thermostatScaleMax = td.scaleMax;
    }

    diag.totalSeconds = seconds_since(tTotal0);
    return diag;
#endif
}



CudaPersistentMpcdStepDiagnostics cuda_apply_persistent_tg_deposit_src_collision_thermostat(
    CudaParticleState& gpuState,
    CudaCellWorkspace& cellWorkspace,
    ParticleState& downloadTarget,
    std::vector<int>& cellIdOut,
    std::vector<std::uint32_t>& cellCountOut,
    std::vector<double>& cellMassOut,
    std::vector<double>& cellUxOut,
    std::vector<double>& cellUyOut,
    const CudaPersistentMpcdStepConfig& config,
    ThermostatDiagnostics* thermostatDiagOut) {
#if !defined(MPCD_ENABLE_CUDA_PERSISTENT_STEP) || !defined(MPCD_ENABLE_CUDA_PARTICLE_STATE) || !defined(MPCD_ENABLE_CUDA_CELL_WORKSPACE)
    (void)gpuState; (void)cellWorkspace; (void)downloadTarget; (void)cellIdOut; (void)cellCountOut; (void)cellMassOut; (void)cellUxOut; (void)cellUyOut; (void)config; (void)thermostatDiagOut;
    throw std::runtime_error("cuda_apply_persistent_tg_deposit_src_collision_thermostat(CudaParticleState,CudaCellWorkspace) requires MPCD_ENABLE_CUDA_PERSISTENT_STEP, MPCD_ENABLE_CUDA_PARTICLE_STATE and MPCD_ENABLE_CUDA_CELL_WORKSPACE");
#else
    validate_particle_state(downloadTarget, "cuda_apply_persistent_tg_deposit_src_collision_thermostat(shared particle+cell downloadTarget)");
    if (config.Nx <= 0 || config.Ny <= 0) throw std::runtime_error("persistent CUDA shared particle+cell step: invalid grid");
    if (!(config.Lx > 0.0) || !(config.Ly > 0.0)) throw std::runtime_error("persistent CUDA shared particle+cell step: invalid domain");
    if (!(config.targetKBT > 0.0)) throw std::runtime_error("persistent CUDA shared particle+cell step: targetKBT must be positive");

    const CudaParticleDeviceView pv = gpuState.device_view();
    if (pv.n == 0u) throw std::runtime_error("persistent CUDA shared particle+cell step: empty CudaParticleState");
    if (downloadTarget.Np != pv.n) throw std::runtime_error("persistent CUDA shared particle+cell step: host particle count mismatch");
    if (pv.x == nullptr || pv.y == nullptr || pv.vx == nullptr || pv.vy == nullptr || pv.mass == nullptr || pv.role == nullptr) {
        throw std::runtime_error("persistent CUDA shared particle+cell step: incomplete CudaParticleState device view");
    }

    const std::uint64_t nActive64 = pv.nActiveFluid > 0u ? pv.nActiveFluid : active_fluid_count(downloadTarget);
    const std::size_t n = static_cast<std::size_t>(nActive64);
    const int nInt = static_cast<int>(n);
    if (static_cast<std::size_t>(nInt) != n) throw std::runtime_error("persistent CUDA shared particle+cell step: too many particles for prototype int kernels");
    const int nc = config.Nx * config.Ny;
    const int cycles = std::max(1, config.cycles);
    const int threads = std::max(32, config.threadsPerBlock);
    const int particleBlocks = std::max(1, (nInt + threads - 1) / threads);
    const int cellBlocks = std::max(1, (nc + threads - 1) / threads);
    const int resetBlocks = std::max(particleBlocks, cellBlocks);

    cellWorkspace.ensure_capacity(nActive64, nc, nullptr);
    const CudaCellWorkspaceDeviceView cv = cellWorkspace.device_view();
    if (cv.cellId == nullptr || cv.count == nullptr || cv.cellMass == nullptr || cv.cellPx == nullptr ||
        cv.cellPy == nullptr || cv.cellUx == nullptr || cv.cellUy == nullptr || cv.cosA == nullptr ||
        cv.sinA == nullptr || cv.cellKinetic == nullptr || cv.cellScale == nullptr ||
        cv.fluidCounter == nullptr || cv.rotatedCounter == nullptr || cv.invalidCounter == nullptr) {
        throw std::runtime_error("persistent CUDA shared particle+cell step: incomplete CudaCellWorkspace device view");
    }
    if (cv.particleCapacity < nActive64 || cv.numCells < nc) {
        throw std::runtime_error("persistent CUDA shared particle+cell step: CudaCellWorkspace capacity mismatch");
    }

    // 0315f: in all classic resident CUDA families, the shared particle state
    // remains device-authoritative after the fused collision+thermostat substep.
    // Do not download vx/vy to the host merely to keep a stale mirror alive;
    // summaries/dumps and host diagnostics already perform a lazy active-prefix
    // download when they actually need particle arrays.  The legacy behavior can
    // be restored for debugging through the DISABLE flag below.
    const bool residentClassicMode0315f =
        env_flag_enabled_0257("MPCD_CUDA_CLASSIC_SRC_PERIODIC_RESIDENT_0260", false) ||
        env_flag_enabled_0257("MPCD_CUDA_CLASSIC_SRC_WALL_RESIDENT_0261", false) ||
        env_flag_enabled_0257("MPCD_CUDA_CLASSIC_SRC_SOLID_RESIDENT_0262", false) ||
        env_flag_enabled_0257("MPCD_CUDA_CLASSIC_SRC_IO_FULLFACE_RESIDENT_0263", false) ||
        env_flag_enabled_0257("MPCD_CUDA_CLASSIC_SRC_IO_SEGMENTED_RESIDENT_0264", false);
    const bool skipVelocityDownload0315f =
        residentClassicMode0315f &&
        !env_flag_enabled_0257("MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_DISABLE_SKIP_VELOCITY_DOWNLOAD_0315F", false);

    // 0322: port the already-validated 0272/0273 collision-wrapper reductions
    // to the shared collision+thermostat resident path.  Before 0322 this path
    // still built cos/sin rotation tables on the host, copied them H2D every
    // step, and forced a setup synchronization before the kernel batch.  The
    // measured 0321 profile still spent ~1.9 s/10000 steps in upload/setup even
    // after all diagnostic downloads had been reduced.
    const bool deviceRotationTables0272 =
        env_flag_enabled_0257("MPCD_CUDA_PERSISTENT_SRC_COLLISION_DEVICE_ROTATION_0272", false) &&
        !env_flag_enabled_0257("MPCD_CUDA_PERSISTENT_SRC_COLLISION_DISABLE_DEVICE_ROTATION_0272", false);
    const bool lazyKernelLaunchCheck0273 =
        residentClassicMode0315f &&
        env_flag_enabled_0257("MPCD_CUDA_PERSISTENT_SRC_COLLISION_LAZY_KERNEL_CHECK_0273", false) &&
        !env_flag_enabled_0257("MPCD_CUDA_PERSISTENT_SRC_COLLISION_DISABLE_LAZY_KERNEL_CHECK_0273", false);
    const bool skipSetupSync0273 =
        residentClassicMode0315f &&
        env_flag_enabled_0257("MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_SETUP_SYNC_0273", false) &&
        !env_flag_enabled_0257("MPCD_CUDA_PERSISTENT_SRC_COLLISION_DISABLE_SKIP_SETUP_SYNC_0273", false);
    auto checkKernelLaunch0273 = [&]() {
        if (!lazyKernelLaunchCheck0273) {
            MPCD_CUDA_CHECK(cudaGetLastError());
        }
    };

    std::vector<double> cosHost;
    std::vector<double> sinHost;
    if (!deviceRotationTables0272) {
        cosHost.assign(static_cast<std::size_t>(nc), std::cos(config.rotationAngle));
        sinHost.assign(static_cast<std::size_t>(nc), std::sin(config.rotationAngle));
        if (config.randomRotationSign) {
            for (int c = 0; c < nc; ++c) {
                const std::uint64_t h = splitmix64_host(config.rngSeed ^
                                                        (config.step * 0x9e3779b97f4a7c15ULL) ^
                                                        static_cast<std::uint64_t>(c));
                if ((h & 1ULL) == 0ULL) sinHost[static_cast<std::size_t>(c)] = -sinHost[static_cast<std::size_t>(c)];
            }
        }
    }

    CudaPersistentMpcdStepDiagnostics diag{};
    diag.particlesVisited = nActive64;
    diag.numCells = nc;
    diag.cycles = cycles;

    const std::size_t nBytesI = n * sizeof(int);
    const std::size_t cBytesD = static_cast<std::size_t>(nc) * sizeof(double);
    const std::size_t cBytesU = static_cast<std::size_t>(nc) * sizeof(unsigned int);

    // 0324: optional internal CUDA-event microprofile for the persistent
    // collision+thermostat kernel batch.  It is disabled by default because it
    // synchronizes around every launch.  It is intended only for short
    // diagnostic runs when external profilers such as ncu/nsys cannot provide
    // kernel timing on the workstation.
    const bool kernelBreakdown0324 =
        env_flag_enabled_0257("MPCD_CUDA_PERSISTENT_SRC_COLLISION_KERNEL_BREAKDOWN_0324", false) &&
        !env_flag_enabled_0257("MPCD_CUDA_PERSISTENT_SRC_COLLISION_DISABLE_KERNEL_BREAKDOWN_0324", false);
    std::FILE* kernelBreakdownFile0324 = nullptr;
    cudaEvent_t kernelBreakdownStart0324 = nullptr;
    cudaEvent_t kernelBreakdownStop0324 = nullptr;
    if (kernelBreakdown0324) {
        const char* p = std::getenv("MPCD_CUDA_PERSISTENT_SRC_COLLISION_KERNEL_BREAKDOWN_0324_FILE");
        const std::string path = (p != nullptr && *p != '\0') ? std::string(p) : std::string("cuda_persistent_kernel_breakdown_0324.csv");
        kernelBreakdownFile0324 = std::fopen(path.c_str(), "w");
        if (kernelBreakdownFile0324 == nullptr) {
            throw std::runtime_error("0324 kernel breakdown: unable to open output file: " + path);
        }
        std::fprintf(kernelBreakdownFile0324,
                     "step,kernel,ms,nActiveFluid,numCells,particleBlocks,cellBlocks,resetBlocks,threads\n");
        MPCD_CUDA_CHECK(cudaEventCreate(&kernelBreakdownStart0324));
        MPCD_CUDA_CHECK(cudaEventCreate(&kernelBreakdownStop0324));
    }

#define MPCD_PROFILE_BEGIN_0324() do { \
        if (kernelBreakdown0324) { \
            MPCD_CUDA_CHECK(cudaEventRecord(kernelBreakdownStart0324, 0)); \
        } \
    } while (0)

#define MPCD_PROFILE_END_0324(label__) do { \
        if (kernelBreakdown0324) { \
            MPCD_CUDA_CHECK(cudaGetLastError()); \
            MPCD_CUDA_CHECK(cudaEventRecord(kernelBreakdownStop0324, 0)); \
            MPCD_CUDA_CHECK(cudaEventSynchronize(kernelBreakdownStop0324)); \
            float kernelMs0324__ = 0.0f; \
            MPCD_CUDA_CHECK(cudaEventElapsedTime(&kernelMs0324__, kernelBreakdownStart0324, kernelBreakdownStop0324)); \
            if (kernelBreakdownFile0324 != nullptr) { \
                std::fprintf(kernelBreakdownFile0324, "%llu,%s,%.9g,%llu,%d,%d,%d,%d,%d\n", \
                             static_cast<unsigned long long>(config.step), label__, static_cast<double>(kernelMs0324__), \
                             static_cast<unsigned long long>(nActive64), nc, particleBlocks, cellBlocks, resetBlocks, threads); \
            } \
        } else { \
            checkKernelLaunch0273(); \
        } \
    } while (0)

    const auto tTotal0 = Clock::now();
    auto t0 = Clock::now();
    if (deviceRotationTables0272) {
        MPCD_PROFILE_BEGIN_0324();
        fill_rotation_tables_persistent_0272_kernel<<<cellBlocks, threads>>>(
            nc, std::cos(config.rotationAngle), std::sin(config.rotationAngle),
            config.randomRotationSign, config.rngSeed, config.step, cv.cosA, cv.sinA);
        MPCD_PROFILE_END_0324("setup_fill_rotation_tables_0272");
    } else {
        MPCD_CUDA_CHECK(cudaMemcpy(cv.cosA, cosHost.data(), cBytesD, cudaMemcpyHostToDevice));
        MPCD_CUDA_CHECK(cudaMemcpy(cv.sinA, sinHost.data(), cBytesD, cudaMemcpyHostToDevice));
    }
    MPCD_CUDA_CHECK(cudaMemset(cv.fluidCounter, 0, sizeof(unsigned long long)));
    MPCD_CUDA_CHECK(cudaMemset(cv.rotatedCounter, 0, sizeof(unsigned long long)));
    MPCD_CUDA_CHECK(cudaMemset(cv.invalidCounter, 0, sizeof(unsigned long long)));
    if (!skipSetupSync0273) {
        MPCD_CUDA_CHECK(cudaDeviceSynchronize());
    }
    diag.uploadSeconds = seconds_since(t0);

    DeviceConfig cfg{};
    cfg.Nx = config.Nx;
    cfg.Ny = config.Ny;
    cfg.numCells = nc;
    cfg.Lx = config.Lx;
    cfg.Ly = config.Ly;
    cfg.dx = config.Lx / static_cast<double>(config.Nx);
    cfg.dy = config.Ly / static_cast<double>(config.Ny);
    cfg.shiftX = config.shiftX;
    cfg.shiftY = config.shiftY;
    cfg.periodicX = config.periodicX ? 1 : 0;
    cfg.periodicY = config.periodicY ? 1 : 0;
    cfg.domainXMin = config.domainXMin;
    cfg.domainXMax = config.domainXMax;
    cfg.domainYMin = config.domainYMin;
    cfg.domainYMax = config.domainYMax;
    cfg.wallLeftEnabled = config.wallLeftEnabled;
    cfg.wallRightEnabled = config.wallRightEnabled;
    cfg.wallBottomEnabled = config.wallBottomEnabled;
    cfg.wallTopEnabled = config.wallTopEnabled;
    cfg.wallAccommodation = config.wallAccommodation;
    cfg.wallGamma = config.wallGamma;
    cfg.wallVpMass = config.wallVpMass;
    cfg.wallUxLeft = config.wallUxLeft;
    cfg.wallUyLeft = config.wallUyLeft;
    cfg.wallUxRight = config.wallUxRight;
    cfg.wallUyRight = config.wallUyRight;
    cfg.wallUxBottom = config.wallUxBottom;
    cfg.wallUyBottom = config.wallUyBottom;
    cfg.wallUxTop = config.wallUxTop;
    cfg.wallUyTop = config.wallUyTop;
    cfg.immersedRectangleEnabled = config.immersedRectangleEnabled;
    cfg.immersedFractionSamples = config.immersedFractionSamples;
    cfg.immersedXMin = config.immersedXMin;
    cfg.immersedXMax = config.immersedXMax;
    cfg.immersedYMin = config.immersedYMin;
    cfg.immersedYMax = config.immersedYMax;
    cfg.immersedCircleEnabled = config.immersedCircleEnabled;
    cfg.immersedCircleCx = config.immersedCircleCx;
    cfg.immersedCircleCy = config.immersedCircleCy;
    cfg.immersedCircleR = config.immersedCircleR;
    cfg.immersedWallUx = config.immersedWallUx;
    cfg.immersedWallUy = config.immersedWallUy;
    cfg.fusedStreamDeposit0274 = config.fusedStreamDeposit0274;
    cfg.fusedStreamMode0274 = config.fusedStreamMode0274;
    cfg.streamDt0274 = config.streamDt0274;
    cfg.streamBodyAccelerationX0274 = config.streamBodyAccelerationX0274;
    cfg.streamBodyAccelerationY0274 = config.streamBodyAccelerationY0274;
    cfg.streamTaylorGreenEnable0274 = config.streamTaylorGreenEnable0274;
    cfg.streamTaylorGreenAmplitude0274 = config.streamTaylorGreenAmplitude0274;
    cfg.streamTaylorGreenModeX0274 = config.streamTaylorGreenModeX0274;
    cfg.streamTaylorGreenModeY0274 = config.streamTaylorGreenModeY0274;
    cfg.streamBottomMode0274 = config.streamBottomMode0274;
    cfg.streamTopMode0274 = config.streamTopMode0274;
    cfg.streamWallUxBottom0274 = config.streamWallUxBottom0274;
    cfg.streamWallUyBottom0274 = config.streamWallUyBottom0274;
    cfg.streamWallUxTop0274 = config.streamWallUxTop0274;
    cfg.streamWallUyTop0274 = config.streamWallUyTop0274;
    cfg.fluidRole = static_cast<unsigned char>(kParticleRoleFluid);

    t0 = Clock::now();
    for (int cycle = 0; cycle < cycles; ++cycle) {
        MPCD_PROFILE_BEGIN_0324();
        reset_persistent_cells_kernel<<<resetBlocks, threads>>>(nInt, nc, cv.cellId, cv.count, cv.cellMass,
                                                                cv.cellPx, cv.cellPy, cv.cellUx, cv.cellUy,
                                                                cv.cellKinetic, cv.cellScale);
        MPCD_PROFILE_END_0324("reset_persistent_cells");
        MPCD_PROFILE_BEGIN_0324();
        deposit_persistent_kernel<<<particleBlocks, threads>>>(nInt, pv.x, pv.y, pv.vx, pv.vy, pv.mass, pv.role,
                                                               cfg, cv.cellId, cv.count, cv.cellMass, cv.cellPx,
                                                               cv.cellPy, cv.fluidCounter);
        MPCD_PROFILE_END_0324("deposit_persistent");
        if (cfg.wallLeftEnabled || cfg.wallRightEnabled || cfg.wallBottomEnabled || cfg.wallTopEnabled || cfg.immersedRectangleEnabled || cfg.immersedCircleEnabled) {
            MPCD_PROFILE_BEGIN_0324();
            add_wall_virtual_faces_persistent_kernel<<<cellBlocks, threads>>>(nc, cfg, cv.cellMass, cv.cellPx, cv.cellPy);
            MPCD_PROFILE_END_0324("add_wall_virtual_faces_persistent");
        }
        MPCD_PROFILE_BEGIN_0324();
        finalize_velocity_persistent_kernel<<<cellBlocks, threads>>>(nc, cv.cellMass, cv.cellPx, cv.cellPy,
                                                                     cv.cellUx, cv.cellUy);
        MPCD_PROFILE_END_0324("finalize_velocity_persistent");
        MPCD_PROFILE_BEGIN_0324();
        src_rotate_persistent_kernel<<<particleBlocks, threads>>>(nInt, cv.cellId, pv.role, cv.cellUx, cv.cellUy,
                                                                  cv.cosA, cv.sinA, cfg, pv.vx, pv.vy,
                                                                  cv.rotatedCounter, cv.invalidCounter);
        MPCD_PROFILE_END_0324("src_rotate_persistent");
        MPCD_PROFILE_BEGIN_0324();
        reset_thermostat_real_moments_persistent_0276_kernel<<<cellBlocks, threads>>>(
            nc, cv.cellMass, cv.cellPx, cv.cellPy, cv.cellUx, cv.cellUy, cv.cellKinetic, cv.cellScale);
        MPCD_PROFILE_END_0324("reset_thermostat_real_moments_0276");
        MPCD_PROFILE_BEGIN_0324();
        deposit_thermostat_real_moments_persistent_0276_kernel<<<particleBlocks, threads>>>(
            nInt, cv.cellId, pv.role, pv.mass, pv.vx, pv.vy, cfg, cv.cellMass, cv.cellPx, cv.cellPy);
        MPCD_PROFILE_END_0324("deposit_thermostat_real_moments_0276");
        MPCD_PROFILE_BEGIN_0324();
        finalize_velocity_persistent_kernel<<<cellBlocks, threads>>>(nc, cv.cellMass, cv.cellPx, cv.cellPy,
                                                                     cv.cellUx, cv.cellUy);
        MPCD_PROFILE_END_0324("finalize_velocity_persistent");
        MPCD_PROFILE_BEGIN_0324();
        kinetic_persistent_kernel<<<particleBlocks, threads>>>(nInt, cv.cellId, pv.role, pv.mass, pv.vx, pv.vy,
                                                               cv.cellUx, cv.cellUy, cfg, cv.cellKinetic);
        MPCD_PROFILE_END_0324("kinetic_persistent");
        MPCD_PROFILE_BEGIN_0324();
        scale_persistent_kernel<<<cellBlocks, threads>>>(nc, cv.count, cv.cellKinetic, config.targetKBT,
                                                         std::max(1, config.thermostatMinParticles),
                                                         config.thermostatEpsilon, cv.cellScale);
        MPCD_PROFILE_END_0324("scale_persistent");
        MPCD_PROFILE_BEGIN_0324();
        apply_thermostat_persistent_kernel<<<particleBlocks, threads>>>(nInt, cv.cellId, pv.role, cv.cellUx,
                                                                       cv.cellUy, cv.cellScale, cfg, pv.vx, pv.vy);
        MPCD_PROFILE_END_0324("apply_thermostat_persistent");
    }
    MPCD_CUDA_CHECK(cudaDeviceSynchronize());
    diag.kernelSeconds = seconds_since(t0);

    if (kernelBreakdown0324) {
        if (kernelBreakdownFile0324 != nullptr) {
            std::fflush(kernelBreakdownFile0324);
            std::fclose(kernelBreakdownFile0324);
            kernelBreakdownFile0324 = nullptr;
        }
        if (kernelBreakdownStart0324 != nullptr) {
            MPCD_CUDA_CHECK(cudaEventDestroy(kernelBreakdownStart0324));
            kernelBreakdownStart0324 = nullptr;
        }
        if (kernelBreakdownStop0324 != nullptr) {
            MPCD_CUDA_CHECK(cudaEventDestroy(kernelBreakdownStop0324));
            kernelBreakdownStop0324 = nullptr;
        }
    }

#undef MPCD_PROFILE_BEGIN_0324
#undef MPCD_PROFILE_END_0324

    t0 = Clock::now();
    const bool fastThermostatDiag0321 =
        env_flag_enabled_0257("MPCD_CUDA_PERSISTENT_SRC_COLLISION_FAST_THERMOSTAT_DIAG_0321", false) &&
        !env_flag_enabled_0257("MPCD_CUDA_PERSISTENT_SRC_COLLISION_DISABLE_FAST_THERMOSTAT_DIAG_0321", false);
    // 0327: in the strict classic resident fast-diagnostics path, no CPU
    // continuation consumes the per-particle host cellId vector after the
    // fused collision+thermostat step.  0321 already skipped all heavy
    // thermostat diagnostic downloads but still filled cellIdOut with n
    // sentinel values every step, which shows up in the measured residual
    // download/envelope time.  Keep this guarded by both resident classic mode
    // and fastThermostatDiag0321 so Q6/resampling/virial hybrid paths keep the
    // conservative host workspaces they need.
    const bool skipHostCellIdFill0327 =
        residentClassicMode0315f &&
        fastThermostatDiag0321 &&
        env_flag_enabled_0257("MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_HOST_CELLID_FILL_0327", false) &&
        !env_flag_enabled_0257("MPCD_CUDA_PERSISTENT_SRC_COLLISION_DISABLE_SKIP_HOST_CELLID_FILL_0327", false);

    if (fastThermostatDiag0321) {
        // 0321 benchmark/production fast diagnostics path.  The collision and
        // cell-relative thermostat have already been applied on the device above.
        // The legacy path downloaded cellCount, cellKinetic, cellScale and three
        // scalar counters every step only to reconstruct runtime diagnostics.
        // That D2H/synchronization cost is now the measured dominant residual
        // after 0318/0319/0320.  Skip these diagnostic downloads while keeping
        // conservative host workspace shapes: downstream Q6/resampling/capacity
        // are disabled in the classic resident benchmark, and summary/dump
        // synchronization remains handled by the shared particle-state bridge.
        if (!skipVelocityDownload0315f) {
            gpuState.download_velocities(downloadTarget);
        }
        if (skipHostCellIdFill0327) {
            // 0327b: keep the host vector shape because the legacy CPU
            // thermostat wrapper validates cellId.size()==Nactive before it
            // consumes the GPU thermostat diagnostics.  resize(n) avoids the
            // per-step sentinel fill while satisfying that size contract; after
            // the first step the capacity/size are stable in strict classic
            // resident mode.
            cellIdOut.resize(n);
        } else {
            cellIdOut.assign(n, -1);
        }
        cellCountOut.clear();
        cellMassOut.clear();
        cellUxOut.clear();
        cellUyOut.clear();

        diag.downloadSeconds = seconds_since(t0);
        diag.fluidParticles = nActive64;
        diag.particlesRotated = nActive64;
        diag.invalidCellParticles = 0u;

        if (thermostatDiagOut != nullptr) {
            ThermostatDiagnostics td{};
            td.applied = true;
            td.cellsRescaled = 0u;
            td.particlesRescaled = nActive64;
            td.kBTBefore = config.targetKBT;
            td.kBTAfter = config.targetKBT;
            td.scaleMean = 1.0;
            td.scaleMin = 1.0;
            td.scaleMax = 1.0;
            *thermostatDiagOut = td;
            diag.thermostatCellsRescaled = td.cellsRescaled;
            diag.thermostatParticlesRescaled = td.particlesRescaled;
            diag.thermostatKBTBefore = td.kBTBefore;
            diag.thermostatKBTAfter = td.kBTAfter;
            diag.thermostatScaleMean = td.scaleMean;
            diag.thermostatScaleMin = td.scaleMin;
            diag.thermostatScaleMax = td.scaleMax;
        }

        diag.totalSeconds = seconds_since(tTotal0);
        return diag;
    }

    if (!skipVelocityDownload0315f) {
        gpuState.download_velocities(downloadTarget);
    }
    // The later thermostat phase checks that cellId has the particle count even
    // when it only consumes diagnostics recorded here. In resident classic mode
    // the values themselves are not needed on the host, so only size the vector.
    cellIdOut.assign(n, -1);
    cellCountOut.assign(static_cast<std::size_t>(nc), 0u);
    if (!skipVelocityDownload0315f) {
        cellMassOut.assign(static_cast<std::size_t>(nc), 0.0);
        cellUxOut.assign(static_cast<std::size_t>(nc), 0.0);
        cellUyOut.assign(static_cast<std::size_t>(nc), 0.0);
        MPCD_CUDA_CHECK(cudaMemcpy(cellIdOut.data(), cv.cellId, nBytesI, cudaMemcpyDeviceToHost));
    } else {
        cellMassOut.clear();
        cellUxOut.clear();
        cellUyOut.clear();
    }
    // Keep population diagnostics available for runtime summaries; this is much
    // cheaper than downloading full velocities and cell moments every step.
    MPCD_CUDA_CHECK(cudaMemcpy(cellCountOut.data(), cv.count, cBytesU, cudaMemcpyDeviceToHost));
    if (!skipVelocityDownload0315f) {
        MPCD_CUDA_CHECK(cudaMemcpy(cellMassOut.data(), cv.cellMass, cBytesD, cudaMemcpyDeviceToHost));
        MPCD_CUDA_CHECK(cudaMemcpy(cellUxOut.data(), cv.cellUx, cBytesD, cudaMemcpyDeviceToHost));
        MPCD_CUDA_CHECK(cudaMemcpy(cellUyOut.data(), cv.cellUy, cBytesD, cudaMemcpyDeviceToHost));
    }

    std::vector<double> kineticHost(static_cast<std::size_t>(nc), 0.0);
    std::vector<double> scaleHost(static_cast<std::size_t>(nc), 1.0);
    if (thermostatDiagOut != nullptr) {
        // Keep deterministic thermostat diagnostics bit-compatible with the CPU
        // validation path. This is still much cheaper than downloading full
        // particle velocities and all cell moments every step.
        MPCD_CUDA_CHECK(cudaMemcpy(kineticHost.data(), cv.cellKinetic, cBytesD, cudaMemcpyDeviceToHost));
        MPCD_CUDA_CHECK(cudaMemcpy(scaleHost.data(), cv.cellScale, cBytesD, cudaMemcpyDeviceToHost));
    }
    unsigned long long fluid = 0ull, rotated = 0ull, invalid = 0ull;
    MPCD_CUDA_CHECK(cudaMemcpy(&fluid, cv.fluidCounter, sizeof(unsigned long long), cudaMemcpyDeviceToHost));
    MPCD_CUDA_CHECK(cudaMemcpy(&rotated, cv.rotatedCounter, sizeof(unsigned long long), cudaMemcpyDeviceToHost));
    MPCD_CUDA_CHECK(cudaMemcpy(&invalid, cv.invalidCounter, sizeof(unsigned long long), cudaMemcpyDeviceToHost));
    MPCD_CUDA_CHECK(cudaDeviceSynchronize());
    diag.downloadSeconds = seconds_since(t0);

    diag.fluidParticles = static_cast<std::uint64_t>(fluid) / static_cast<std::uint64_t>(cycles);
    diag.particlesRotated = static_cast<std::uint64_t>(rotated);
    diag.invalidCellParticles = static_cast<std::uint64_t>(invalid);

    if (thermostatDiagOut != nullptr) {
        ThermostatDiagnostics td{};
        double totalKBefore = 0.0;
        double targetKTotal = 0.0;
        double scaleSum = 0.0;
        double scaleMin = 1.0e300;
        double scaleMax = 0.0;
        std::uint64_t dofTotal = 0u;
        for (int c = 0; c < nc; ++c) {
            const std::size_t kk = static_cast<std::size_t>(c);
            const std::uint32_t count = cellCountOut[kk];
            const double K = kineticHost[kk];
            if (count < static_cast<std::uint32_t>(std::max(1, config.thermostatMinParticles))) continue;
            if (!(K > config.thermostatEpsilon)) continue;
            const double dof = 2.0 * static_cast<double>(count - 1u);
            const double targetK = 0.5 * dof * config.targetKBT;
            const double scale = scaleHost[kk];
            totalKBefore += K;
            targetKTotal += targetK;
            dofTotal += static_cast<std::uint64_t>(2u * (count - 1u));
            td.cellsRescaled += 1u;
            td.particlesRescaled += static_cast<std::uint64_t>(count);
            scaleSum += scale;
            if (scale < scaleMin) scaleMin = scale;
            if (scale > scaleMax) scaleMax = scale;
        }
        td.applied = td.cellsRescaled > 0u;
        td.kBTBefore = dofTotal > 0u ? (2.0 * totalKBefore / static_cast<double>(dofTotal)) : 0.0;
        td.kBTAfter = dofTotal > 0u ? (2.0 * targetKTotal / static_cast<double>(dofTotal)) : 0.0;
        td.scaleMean = td.cellsRescaled > 0u ? scaleSum / static_cast<double>(td.cellsRescaled) : 1.0;
        td.scaleMin = td.cellsRescaled > 0u ? scaleMin : 1.0;
        td.scaleMax = td.cellsRescaled > 0u ? scaleMax : 1.0;
        *thermostatDiagOut = td;
        diag.thermostatCellsRescaled = td.cellsRescaled;
        diag.thermostatParticlesRescaled = td.particlesRescaled;
        diag.thermostatKBTBefore = td.kBTBefore;
        diag.thermostatKBTAfter = td.kBTAfter;
        diag.thermostatScaleMean = td.scaleMean;
        diag.thermostatScaleMin = td.scaleMin;
        diag.thermostatScaleMax = td.scaleMax;
    }

    diag.totalSeconds = seconds_since(tTotal0);
    return diag;
#endif
}


CudaPersistentMpcdStepDiagnostics cuda_apply_persistent_tg_deposit_src_collision(
    CudaParticleState& gpuState,
    CudaCellWorkspace& cellWorkspace,
    ParticleState& downloadTarget,
    std::vector<int>& cellIdOut,
    std::vector<std::uint32_t>& cellCountOut,
    std::vector<double>& cellMassOut,
    std::vector<double>& cellUxOut,
    std::vector<double>& cellUyOut,
    const CudaPersistentMpcdStepConfig& config) {
#if !defined(MPCD_ENABLE_CUDA_PERSISTENT_STEP) || !defined(MPCD_ENABLE_CUDA_PARTICLE_STATE) || !defined(MPCD_ENABLE_CUDA_CELL_WORKSPACE)
    (void)gpuState; (void)cellWorkspace; (void)downloadTarget; (void)cellIdOut; (void)cellCountOut; (void)cellMassOut; (void)cellUxOut; (void)cellUyOut; (void)config;
    throw std::runtime_error("cuda_apply_persistent_tg_deposit_src_collision(CudaParticleState,CudaCellWorkspace) requires MPCD_ENABLE_CUDA_PERSISTENT_STEP, MPCD_ENABLE_CUDA_PARTICLE_STATE and MPCD_ENABLE_CUDA_CELL_WORKSPACE");
#else
    validate_particle_state(downloadTarget, "cuda_apply_persistent_tg_deposit_src_collision(shared particle+cell downloadTarget)");
    if (config.Nx <= 0 || config.Ny <= 0) throw std::runtime_error("persistent CUDA shared collision step: invalid grid");
    if (!(config.Lx > 0.0) || !(config.Ly > 0.0)) throw std::runtime_error("persistent CUDA shared collision step: invalid domain");

    const CudaParticleDeviceView pv = gpuState.device_view();
    if (pv.n == 0u) throw std::runtime_error("persistent CUDA shared collision step: empty CudaParticleState");
    if (downloadTarget.Np != pv.n) throw std::runtime_error("persistent CUDA shared collision step: host particle count mismatch");
    if (pv.x == nullptr || pv.y == nullptr || pv.vx == nullptr || pv.vy == nullptr || pv.mass == nullptr || pv.role == nullptr) {
        throw std::runtime_error("persistent CUDA shared collision step: incomplete CudaParticleState device view");
    }

    const std::uint64_t nActive64 = pv.nActiveFluid > 0u ? pv.nActiveFluid : active_fluid_count(downloadTarget);
    const std::size_t n = static_cast<std::size_t>(nActive64);
    const int nInt = static_cast<int>(n);
    if (static_cast<std::size_t>(nInt) != n) throw std::runtime_error("persistent CUDA shared collision step: too many particles for prototype int kernels");
    const int nc = config.Nx * config.Ny;
    const int cycles = std::max(1, config.cycles);
    const int threads = std::max(32, config.threadsPerBlock);
    const int particleBlocks = std::max(1, (nInt + threads - 1) / threads);
    const int cellBlocks = std::max(1, (nc + threads - 1) / threads);
    const int resetBlocks = std::max(particleBlocks, cellBlocks);

    const bool residentClassicMode0273 =
        env_flag_enabled_0257("MPCD_CUDA_CLASSIC_SRC_PERIODIC_RESIDENT_0260", false) ||
        env_flag_enabled_0257("MPCD_CUDA_CLASSIC_SRC_WALL_RESIDENT_0261", false) ||
        env_flag_enabled_0257("MPCD_CUDA_CLASSIC_SRC_SOLID_RESIDENT_0262", false) ||
        env_flag_enabled_0257("MPCD_CUDA_CLASSIC_SRC_IO_FULLFACE_RESIDENT_0263", false) ||
        env_flag_enabled_0257("MPCD_CUDA_CLASSIC_SRC_IO_SEGMENTED_RESIDENT_0264", false);
    const bool lazyKernelLaunchCheck0273 =
        residentClassicMode0273 &&
        env_flag_enabled_0257("MPCD_CUDA_PERSISTENT_SRC_COLLISION_LAZY_KERNEL_CHECK_0273", false) &&
        !env_flag_enabled_0257("MPCD_CUDA_PERSISTENT_SRC_COLLISION_DISABLE_LAZY_KERNEL_CHECK_0273", false);
    const bool skipSetupSync0273 =
        residentClassicMode0273 &&
        env_flag_enabled_0257("MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_SETUP_SYNC_0273", false) &&
        !env_flag_enabled_0257("MPCD_CUDA_PERSISTENT_SRC_COLLISION_DISABLE_SKIP_SETUP_SYNC_0273", false);
    auto checkKernelLaunch0273 = [&]() {
        if (!lazyKernelLaunchCheck0273) {
            MPCD_CUDA_CHECK(cudaGetLastError());
        }
    };

    cellWorkspace.ensure_capacity(nActive64, nc, nullptr);
    const CudaCellWorkspaceDeviceView cv = cellWorkspace.device_view();
    if (cv.cellId == nullptr || cv.count == nullptr || cv.cellMass == nullptr || cv.cellPx == nullptr ||
        cv.cellPy == nullptr || cv.cellUx == nullptr || cv.cellUy == nullptr || cv.cosA == nullptr ||
        cv.sinA == nullptr || cv.fluidCounter == nullptr || cv.rotatedCounter == nullptr || cv.invalidCounter == nullptr) {
        throw std::runtime_error("persistent CUDA shared collision step: incomplete CudaCellWorkspace device view");
    }
    if (cv.particleCapacity < nActive64 || cv.numCells < nc) {
        throw std::runtime_error("persistent CUDA shared collision step: CudaCellWorkspace capacity mismatch");
    }

    const bool deviceRotationTables0272 =
        env_flag_enabled_0257("MPCD_CUDA_PERSISTENT_SRC_COLLISION_DEVICE_ROTATION_0272", false) &&
        !env_flag_enabled_0257("MPCD_CUDA_PERSISTENT_SRC_COLLISION_DISABLE_DEVICE_ROTATION_0272", false);

    std::vector<double> cosHost;
    std::vector<double> sinHost;
    if (!deviceRotationTables0272) {
        cosHost.assign(static_cast<std::size_t>(nc), std::cos(config.rotationAngle));
        sinHost.assign(static_cast<std::size_t>(nc), std::sin(config.rotationAngle));
        if (config.randomRotationSign) {
            for (int c = 0; c < nc; ++c) {
                const std::uint64_t h = splitmix64_host(config.rngSeed ^
                                                        (config.step * 0x9e3779b97f4a7c15ULL) ^
                                                        static_cast<std::uint64_t>(c));
                if ((h & 1ULL) == 0ULL) sinHost[static_cast<std::size_t>(c)] = -sinHost[static_cast<std::size_t>(c)];
            }
        }
    }

    CudaPersistentMpcdStepDiagnostics diag{};
    diag.particlesVisited = nActive64;
    diag.numCells = nc;
    diag.cycles = cycles;

    const std::size_t nBytesI = n * sizeof(int);
    const std::size_t cBytesD = static_cast<std::size_t>(nc) * sizeof(double);
    const std::size_t cBytesU = static_cast<std::size_t>(nc) * sizeof(unsigned int);

    const auto tTotal0 = Clock::now();
    auto t0 = Clock::now();
    if (deviceRotationTables0272) {
        fill_rotation_tables_persistent_0272_kernel<<<cellBlocks, threads>>>(
            nc, std::cos(config.rotationAngle), std::sin(config.rotationAngle),
            config.randomRotationSign, config.rngSeed, config.step, cv.cosA, cv.sinA);
        checkKernelLaunch0273();
    } else {
        MPCD_CUDA_CHECK(cudaMemcpy(cv.cosA, cosHost.data(), cBytesD, cudaMemcpyHostToDevice));
        MPCD_CUDA_CHECK(cudaMemcpy(cv.sinA, sinHost.data(), cBytesD, cudaMemcpyHostToDevice));
    }
    MPCD_CUDA_CHECK(cudaMemset(cv.fluidCounter, 0, sizeof(unsigned long long)));
    MPCD_CUDA_CHECK(cudaMemset(cv.rotatedCounter, 0, sizeof(unsigned long long)));
    MPCD_CUDA_CHECK(cudaMemset(cv.invalidCounter, 0, sizeof(unsigned long long)));
    if (!skipSetupSync0273) {
        MPCD_CUDA_CHECK(cudaDeviceSynchronize());
    }
    diag.uploadSeconds = seconds_since(t0);

    DeviceConfig cfg{};
    cfg.Nx = config.Nx;
    cfg.Ny = config.Ny;
    cfg.numCells = nc;
    cfg.Lx = config.Lx;
    cfg.Ly = config.Ly;
    cfg.dx = config.Lx / static_cast<double>(config.Nx);
    cfg.dy = config.Ly / static_cast<double>(config.Ny);
    cfg.shiftX = config.shiftX;
    cfg.shiftY = config.shiftY;
    cfg.periodicX = config.periodicX ? 1 : 0;
    cfg.periodicY = config.periodicY ? 1 : 0;
    cfg.domainXMin = config.domainXMin;
    cfg.domainXMax = config.domainXMax;
    cfg.domainYMin = config.domainYMin;
    cfg.domainYMax = config.domainYMax;
    cfg.wallLeftEnabled = config.wallLeftEnabled;
    cfg.wallRightEnabled = config.wallRightEnabled;
    cfg.wallBottomEnabled = config.wallBottomEnabled;
    cfg.wallTopEnabled = config.wallTopEnabled;
    cfg.wallAccommodation = config.wallAccommodation;
    cfg.wallGamma = config.wallGamma;
    cfg.wallVpMass = config.wallVpMass;
    cfg.wallUxLeft = config.wallUxLeft;
    cfg.wallUyLeft = config.wallUyLeft;
    cfg.wallUxRight = config.wallUxRight;
    cfg.wallUyRight = config.wallUyRight;
    cfg.wallUxBottom = config.wallUxBottom;
    cfg.wallUyBottom = config.wallUyBottom;
    cfg.wallUxTop = config.wallUxTop;
    cfg.wallUyTop = config.wallUyTop;
    cfg.immersedRectangleEnabled = config.immersedRectangleEnabled;
    cfg.immersedFractionSamples = config.immersedFractionSamples;
    cfg.immersedXMin = config.immersedXMin;
    cfg.immersedXMax = config.immersedXMax;
    cfg.immersedYMin = config.immersedYMin;
    cfg.immersedYMax = config.immersedYMax;
    cfg.immersedCircleEnabled = config.immersedCircleEnabled;
    cfg.immersedCircleCx = config.immersedCircleCx;
    cfg.immersedCircleCy = config.immersedCircleCy;
    cfg.immersedCircleR = config.immersedCircleR;
    cfg.immersedWallUx = config.immersedWallUx;
    cfg.immersedWallUy = config.immersedWallUy;
    cfg.fusedStreamDeposit0274 = config.fusedStreamDeposit0274;
    cfg.fusedStreamMode0274 = config.fusedStreamMode0274;
    cfg.streamDt0274 = config.streamDt0274;
    cfg.streamBodyAccelerationX0274 = config.streamBodyAccelerationX0274;
    cfg.streamBodyAccelerationY0274 = config.streamBodyAccelerationY0274;
    cfg.streamTaylorGreenEnable0274 = config.streamTaylorGreenEnable0274;
    cfg.streamTaylorGreenAmplitude0274 = config.streamTaylorGreenAmplitude0274;
    cfg.streamTaylorGreenModeX0274 = config.streamTaylorGreenModeX0274;
    cfg.streamTaylorGreenModeY0274 = config.streamTaylorGreenModeY0274;
    cfg.streamBottomMode0274 = config.streamBottomMode0274;
    cfg.streamTopMode0274 = config.streamTopMode0274;
    cfg.streamWallUxBottom0274 = config.streamWallUxBottom0274;
    cfg.streamWallUyBottom0274 = config.streamWallUyBottom0274;
    cfg.streamWallUxTop0274 = config.streamWallUxTop0274;
    cfg.streamWallUyTop0274 = config.streamWallUyTop0274;
    cfg.fluidRole = static_cast<unsigned char>(kParticleRoleFluid);

    t0 = Clock::now();
    for (int cycle = 0; cycle < cycles; ++cycle) {
        reset_persistent_cells_kernel<<<resetBlocks, threads>>>(nInt, nc, cv.cellId, cv.count, cv.cellMass,
                                                                cv.cellPx, cv.cellPy, cv.cellUx, cv.cellUy,
                                                                cv.cellKinetic, cv.cellScale);
        checkKernelLaunch0273();
        deposit_persistent_kernel<<<particleBlocks, threads>>>(nInt, pv.x, pv.y, pv.vx, pv.vy, pv.mass, pv.role,
                                                               cfg, cv.cellId, cv.count, cv.cellMass, cv.cellPx,
                                                               cv.cellPy, cv.fluidCounter);
        checkKernelLaunch0273();
        if (cfg.wallLeftEnabled || cfg.wallRightEnabled || cfg.wallBottomEnabled || cfg.wallTopEnabled || cfg.immersedRectangleEnabled || cfg.immersedCircleEnabled) {
            add_wall_virtual_faces_persistent_kernel<<<cellBlocks, threads>>>(nc, cfg, cv.cellMass, cv.cellPx, cv.cellPy);
            checkKernelLaunch0273();
        }
        finalize_velocity_persistent_kernel<<<cellBlocks, threads>>>(nc, cv.cellMass, cv.cellPx, cv.cellPy,
                                                                     cv.cellUx, cv.cellUy);
        checkKernelLaunch0273();
        src_rotate_persistent_kernel<<<particleBlocks, threads>>>(nInt, cv.cellId, pv.role, cv.cellUx, cv.cellUy,
                                                                  cv.cosA, cv.sinA, cfg, pv.vx, pv.vy,
                                                                  cv.rotatedCounter, cv.invalidCounter);
        checkKernelLaunch0273();
    }
    if (lazyKernelLaunchCheck0273) {
        MPCD_CUDA_CHECK(cudaGetLastError());
    }
    MPCD_CUDA_CHECK(cudaDeviceSynchronize());
    diag.kernelSeconds = seconds_since(t0);

    t0 = Clock::now();
    const bool residentClassicNoVelocityDownload = residentClassicMode0273;
    if (!residentClassicNoVelocityDownload) {
        gpuState.download_velocities(downloadTarget);
    }
    const bool skipWorkspaceDownload0272 =
        residentClassicNoVelocityDownload &&
        env_flag_enabled_0257("MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_WORKSPACE_DOWNLOAD_0272", false) &&
        !env_flag_enabled_0257("MPCD_CUDA_PERSISTENT_SRC_COLLISION_DISABLE_SKIP_WORKSPACE_DOWNLOAD_0272", false);
    const bool skipFinalDownloadSync0272 =
        env_flag_enabled_0257("MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_FINAL_SYNC_0272", false) &&
        !env_flag_enabled_0257("MPCD_CUDA_PERSISTENT_SRC_COLLISION_DISABLE_SKIP_FINAL_SYNC_0272", false);

    const bool minimalDownload0257 = env_flag_enabled_0257("MPCD_CUDA_PERSISTENT_SRC_COLLISION_MINIMAL_DOWNLOAD_0257", false);
    if (skipWorkspaceDownload0272) {
        // 0272b safe classic-resident fast path: the validated classic-only
        // runners have Q6/resampling/thermostat disabled, and the host
        // ParticleState is intentionally stale between summaries.  However,
        // runtime summaries and validation comparisons still consume
        // cellCountOut for meanN/stdN/minN/maxN, especially in wall-simple
        // Poiseuille.  Keep the lightweight per-cell count download and skip
        // only the heavier particle cellId and post-collision mass/velocity
        // workspaces.  Future Q6/resampling/host consumers must still leave
        // MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_WORKSPACE_DOWNLOAD_0272
        // disabled unless a dedicated synchronization bridge is implemented.
        cellIdOut.clear();
        cellCountOut.assign(static_cast<std::size_t>(nc), 0u);
        cellMassOut.clear();
        cellUxOut.clear();
        cellUyOut.clear();
        MPCD_CUDA_CHECK(cudaMemcpy(cellCountOut.data(), cv.count, cBytesU, cudaMemcpyDeviceToHost));
    } else {
        cellIdOut.assign(n, -1);
        if (minimalDownload0257) {
            // 0257 conservative minimal-download mode: keep cellCount on the host
            // because runtime summaries/validation still consume population
            // diagnostics, but skip the heavier post-collision cellMass/cellUx/cellUy
            // arrays which are not needed by the current CPU continuation.
            cellCountOut.assign(static_cast<std::size_t>(nc), 0u);
            cellMassOut.clear();
            cellUxOut.clear();
            cellUyOut.clear();
        } else {
            cellCountOut.assign(static_cast<std::size_t>(nc), 0u);
            cellMassOut.assign(static_cast<std::size_t>(nc), 0.0);
            cellUxOut.assign(static_cast<std::size_t>(nc), 0.0);
            cellUyOut.assign(static_cast<std::size_t>(nc), 0.0);
        }
        MPCD_CUDA_CHECK(cudaMemcpy(cellIdOut.data(), cv.cellId, nBytesI, cudaMemcpyDeviceToHost));
        MPCD_CUDA_CHECK(cudaMemcpy(cellCountOut.data(), cv.count, cBytesU, cudaMemcpyDeviceToHost));
        if (!minimalDownload0257) {
            MPCD_CUDA_CHECK(cudaMemcpy(cellMassOut.data(), cv.cellMass, cBytesD, cudaMemcpyDeviceToHost));
            MPCD_CUDA_CHECK(cudaMemcpy(cellUxOut.data(), cv.cellUx, cBytesD, cudaMemcpyDeviceToHost));
            MPCD_CUDA_CHECK(cudaMemcpy(cellUyOut.data(), cv.cellUy, cBytesD, cudaMemcpyDeviceToHost));
        }
    }
    unsigned long long fluid = 0ull, rotated = 0ull, invalid = 0ull;
    MPCD_CUDA_CHECK(cudaMemcpy(&fluid, cv.fluidCounter, sizeof(unsigned long long), cudaMemcpyDeviceToHost));
    MPCD_CUDA_CHECK(cudaMemcpy(&rotated, cv.rotatedCounter, sizeof(unsigned long long), cudaMemcpyDeviceToHost));
    MPCD_CUDA_CHECK(cudaMemcpy(&invalid, cv.invalidCounter, sizeof(unsigned long long), cudaMemcpyDeviceToHost));
    if (!skipFinalDownloadSync0272) {
        MPCD_CUDA_CHECK(cudaDeviceSynchronize());
    }
    diag.downloadSeconds = seconds_since(t0);

    diag.fluidParticles = static_cast<std::uint64_t>(fluid) / static_cast<std::uint64_t>(cycles);
    diag.particlesRotated = static_cast<std::uint64_t>(rotated);
    diag.invalidCellParticles = static_cast<std::uint64_t>(invalid);
    diag.totalSeconds = seconds_since(tTotal0);
    return diag;
#endif
}

CudaPersistentMpcdStepDiagnostics cuda_apply_persistent_tg_deposit_src_collision(
    CudaParticleState& gpuState,
    ParticleState& downloadTarget,
    std::vector<int>& cellIdOut,
    std::vector<std::uint32_t>& cellCountOut,
    std::vector<double>& cellMassOut,
    std::vector<double>& cellUxOut,
    std::vector<double>& cellUyOut,
    const CudaPersistentMpcdStepConfig& config) {
#if !defined(MPCD_ENABLE_CUDA_PERSISTENT_STEP) || !defined(MPCD_ENABLE_CUDA_PARTICLE_STATE) || !defined(MPCD_ENABLE_CUDA_CELL_WORKSPACE)
    (void)gpuState; (void)downloadTarget; (void)cellIdOut; (void)cellCountOut; (void)cellMassOut; (void)cellUxOut; (void)cellUyOut; (void)config;
    throw std::runtime_error("cuda_apply_persistent_tg_deposit_src_collision(CudaParticleState) requires MPCD_ENABLE_CUDA_PERSISTENT_STEP, MPCD_ENABLE_CUDA_PARTICLE_STATE and MPCD_ENABLE_CUDA_CELL_WORKSPACE");
#else
    CudaCellWorkspace transientWorkspace;
    return cuda_apply_persistent_tg_deposit_src_collision(gpuState, transientWorkspace, downloadTarget,
                                                          cellIdOut, cellCountOut, cellMassOut, cellUxOut, cellUyOut,
                                                          config);
#endif
}

} // namespace mpcd
