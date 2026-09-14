#include "cuda_chi_solid_0493x16e.h"

#if defined(MPCD_ENABLE_CUDA_CHI_SOLID_0493X16E)

#include <cuda_runtime.h>

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <stdexcept>
#include <string>

namespace mpcd {
namespace {

void check_cuda_0493x16e(cudaError_t err, const char* what) {
    if (err != cudaSuccess) {
        throw std::runtime_error(std::string("cuda_chi_solid_0493x16e: ") +
                                 what + ": " + cudaGetErrorString(err));
    }
}

bool env_truthy_0493x16i(const char* name) {
    const char* v = std::getenv(name);
    if (!v || !*v) return false;
    const std::string s(v);
    return !(s == "0" || s == "false" || s == "FALSE" || s == "off" || s == "OFF" || s == "no" || s == "NO");
}

double env_double_0493x16i(const char* name, double fallback) {
    const char* v = std::getenv(name);
    if (!v || !*v) return fallback;
    char* end = nullptr;
    const double x = std::strtod(v, &end);
    if (end == v || !std::isfinite(x)) {
        throw std::runtime_error(std::string("0493x16i invalid numeric environment value ") + name);
    }
    return x;
}

struct ResidentChiSolidWorkspace0493x16e {
    int nx = 0;
    int ny = 0;
    double Lx = 0.0;
    double Ly = 0.0;
    double mass = 0.0;
    double thickness = 0.0;
    bool initialized = false;
    std::uint64_t geometryVersion = 0u;

    // 0493x16i prescribed-deformable qualification parameters. These are
    // experimental runner-controlled values, not persistent solver inputs.
    bool prescribedDeformable0493x16i = false;
    double deformAmplitude0493x16i = 0.0;
    double deformOmega0493x16i = 0.0;
    double dt0493x16i = 0.0;

    // [centerX, velocityX, mass, thickness]
    double* d_state = nullptr;
    double* d_rasterSolidCellEquivalent = nullptr;
    // [reactionX, reactionY]
    double* d_reactionSums = nullptr;
    double* d_cellReactionX = nullptr;
    double* d_cellReactionY = nullptr;
    // 0493x16g: cells newly swallowed by the moving historical binary mask
    // during the post-stream geometry update.  This remains device-resident.
    unsigned char* d_newlySolidMask0493x16g = nullptr;
    // 0493x16i geometric solid fraction theta and per-step delta diagnostics.
    float* d_solidFraction0493x16i = nullptr;
    // [positiveDeltaCellsEq, negativeDeltaCellsEq, maxAbsDeltaTheta]
    double* d_fractionDeltaSums0493x16i = nullptr;

    ~ResidentChiSolidWorkspace0493x16e() {
        cudaFree(d_state);
        cudaFree(d_rasterSolidCellEquivalent);
        cudaFree(d_reactionSums);
        cudaFree(d_cellReactionX);
        cudaFree(d_cellReactionY);
        cudaFree(d_newlySolidMask0493x16g);
        cudaFree(d_solidFraction0493x16i);
        cudaFree(d_fractionDeltaSums0493x16i);
    }
};

ResidentChiSolidWorkspace0493x16e& workspace_0493x16e() {
    static ResidentChiSolidWorkspace0493x16e w;
    return w;
}

__device__ double wrap_periodic_0493x16e(double x, double L) {
    if (!(L > 0.0)) return x;
    x -= floor(x / L) * L;
    if (x >= L) x -= L;
    if (x < 0.0) x += L;
    return x;
}

__device__ double periodic_delta_0493x16e(double x, double c, double L) {
    double d = x - c;
    if (L > 0.0) d -= nearbyint(d / L) * L;
    return d;
}

__global__ void rasterize_rigid_slab_subcell_0493x16e(
    const double* state,
    float* chi,
    float* uSolidX,
    float* uSolidY,
    int nx,
    int ny,
    double Lx,
    double* solidCellEquivalent) {
    const int c = blockIdx.x * blockDim.x + threadIdx.x;
    const int ncell = nx * ny;
    if (c >= ncell) return;

    const int ix = c % nx;
    const double dx = Lx / static_cast<double>(max(1, nx));
    const double xCenter = (static_cast<double>(ix) + 0.5) * dx;
    const double slabCenter = state[0];
    const double slabVelocity = state[1];
    const double half = 0.5 * state[3];

    // Cell interval expressed in the nearest periodic image of the slab frame.
    // Exact overlap with [-half,+half] gives the solid volume fraction in x.
    const double d = periodic_delta_0493x16e(xCenter, slabCenter, Lx);
    const double cellLo = d - 0.5 * dx;
    const double cellHi = d + 0.5 * dx;
    const double overlap = fmax(0.0, fmin(cellHi, half) - fmax(cellLo, -half));
    const double solidFraction = fmin(1.0, fmax(0.0, overlap / dx));

    chi[c] = static_cast<float>(1.0 - solidFraction);
    uSolidX[c] = static_cast<float>(slabVelocity);
    uSolidY[c] = 0.0f;
    atomicAdd(solidCellEquivalent, solidFraction);
}

__device__ double atomicMaxDoublePositive_0493x16i(double* address, double val) {
    unsigned long long* addr = reinterpret_cast<unsigned long long*>(address);
    unsigned long long old = *addr, assumed;
    while (__longlong_as_double(old) < val) {
        assumed = old;
        old = atomicCAS(addr, assumed, __double_as_longlong(val));
        if (old == assumed) break;
    }
    return __longlong_as_double(old);
}

__device__ double prescribed_centerline_0493x16i(
    double globalCenter, double y, double Ly,
    double amplitude, double omega, double time) {
    if (!(Ly > 0.0) || amplitude == 0.0) return globalCenter;
    const double pi = 3.141592653589793238462643383279502884;
    const double ky = 2.0 * pi / Ly;
    const double shape = sin(ky * y);
    // 0493x16m-static-curve characterization: omega==0 with non-zero
    // amplitude means a frozen peak-shape x_c(y)=X+A sin(k_y y).  No
    // historical x16i runner can create this state: the legacy prescribed
    // deformable path always has omega>0.  The default behavior is therefore
    // unchanged unless the diagnostic-only environment switch below is used.
    if (omega == 0.0) return globalCenter + amplitude * shape;
    return globalCenter + amplitude * shape * sin(omega * time);
}

__device__ double prescribed_velocity_x_0493x16i(
    double globalVelocity, double y, double Ly,
    double amplitude, double omega, double time) {
    if (!(Ly > 0.0) || amplitude == 0.0 || omega == 0.0) return globalVelocity;
    const double pi = 3.141592653589793238462643383279502884;
    const double ky = 2.0 * pi / Ly;
    return globalVelocity + amplitude * omega * sin(ky * y) * cos(omega * time);
}

__global__ void rasterize_rigid_slab_binary_0493x16f(
    const double* state,
    float* chi,
    float* uSolidX,
    float* uSolidY,
    int nx,
    int ny,
    double Lx,
    double Ly,
    double geometryTime0493x16i,
    double deformAmplitude0493x16i,
    double deformOmega0493x16i,
    double* solidCellEquivalent,
    unsigned char* newlySolidMask0493x16g,
    int detectNewlySolid0493x16g,
    float* solidFraction0493x16i,
    double* fractionDeltaSums0493x16i,
    int trackFractionDelta0493x16i,
    int continuousChiGeometry0493x16j) {
    const int c = blockIdx.x * blockDim.x + threadIdx.x;
    const int ncell = nx * ny;
    if (c >= ncell) return;

    const int ix = c % nx;
    const int iy = c / nx;
    const double dx = Lx / static_cast<double>(max(1, nx));
    const double dy = Ly / static_cast<double>(max(1, ny));
    const double xCenter = (static_cast<double>(ix) + 0.5) * dx;
    const double yCenter = (static_cast<double>(iy) + 0.5) * dy;
    const double globalCenter = state[0];
    const double globalVelocity = state[1];
    const double half = 0.5 * state[3];
    const double localCenter = prescribed_centerline_0493x16i(
        globalCenter, yCenter, Ly, deformAmplitude0493x16i,
        deformOmega0493x16i, geometryTime0493x16i);
    const double localVelocity = prescribed_velocity_x_0493x16i(
        globalVelocity, yCenter, Ly, deformAmplitude0493x16i,
        deformOmega0493x16i, geometryTime0493x16i);
    const double d = periodic_delta_0493x16e(xCenter, localCenter, Lx);
    const double sd = fabs(d) - half;
    const double solid = sd <= 0.0 ? 1.0 : 0.0;

    // Geometric cell occupancy is kept separate from the historical Darcy chi.
    // It is an x-overlap fraction at this y row and is NEVER fed to alpha(chi).
    const double cellLo = d - 0.5 * dx;
    const double cellHi = d + 0.5 * dx;
    const double overlap = fmax(0.0, fmin(cellHi, half) - fmax(cellLo, -half));
    const double solidFraction = fmin(1.0, fmax(0.0, overlap / dx));
    const float oldFraction = solidFraction0493x16i ? solidFraction0493x16i[c] : 0.0f;
    if (solidFraction0493x16i) solidFraction0493x16i[c] = static_cast<float>(solidFraction);
    if (trackFractionDelta0493x16i && fractionDeltaSums0493x16i) {
        const double delta = solidFraction - static_cast<double>(oldFraction);
        if (delta > 0.0) atomicAdd(&fractionDeltaSums0493x16i[0], delta);
        if (delta < 0.0) atomicAdd(&fractionDeltaSums0493x16i[1], -delta);
        atomicMaxDoublePositive_0493x16i(&fractionDeltaSums0493x16i[2], fabs(delta));
    }

    const float oldChi0493x16g = chi[c];
    if (newlySolidMask0493x16g) {
        newlySolidMask0493x16g[c] =
            (detectNewlySolid0493x16g && oldChi0493x16g > 0.5f && solid > 0.5) ? 1u : 0u;
    }

    // 0493x16k: a moving material wall must be reconstructed from a level
    // field whose chi=0.5 contour translates with the solid.  Publishing the
    // cell occupancy (1-solidFraction) is conservative for volume, but its
    // linearly/Q2 reconstructed 0.5 contour is grid-phase dependent: after a
    // Galilean boost the rasterized wall lags the true solid displacement and
    // creates spurious x10p overlaps on the next step.
    //
    // Keep solidFraction unchanged for volume diagnostics, but publish a
    // purely GEOMETRIC level field for the kinetic wall.  Around either slab
    // face, S=1-chi is linear in signed distance over +/-2 cells, so every
    // 3-point Q2 stencil touching S=0.5 sees the same affine x-profile.  The
    // reconstructed contour is therefore translation-covariant while the
    // physical interface remains exactly sd=0.  This width is numerical only;
    // it is never fed to historical Darcy alpha(chi), because the branch is
    // active only for chiKineticBoundaryMode=specular.
    const double kineticLevelHalfWidth0493x16k = 2.0 * dx;
    const double solidLevel0493x16k = fmin(
        1.0, fmax(0.0,
            0.5 - sd / (2.0 * kineticLevelHalfWidth0493x16k)));
    chi[c] = continuousChiGeometry0493x16j
        ? static_cast<float>(1.0 - solidLevel0493x16k)
        : (solid > 0.5 ? 0.0f : 1.0f);
    uSolidX[c] = static_cast<float>(localVelocity);
    uSolidY[c] = 0.0f;
    const bool fractionalGeometryDiagnostic0493x16i =
        (deformAmplitude0493x16i != 0.0 && deformOmega0493x16i != 0.0);
    atomicAdd(solidCellEquivalent,
              (continuousChiGeometry0493x16j || fractionalGeometryDiagnostic0493x16i)
                  ? solidFraction : solid);
}

__global__ void drift_rigid_slab_state_0493x16f(
    double* state,
    double dt,
    double Lx) {
    if (blockIdx.x != 0 || threadIdx.x != 0) return;
    state[0] = wrap_periodic_0493x16e(state[0] + dt * state[1], Lx);
}

__global__ void assemble_reaction_field_0493x16e(
    const double* darcyFluidX,
    const double* darcyFluidY,
    const double* chiVpFluidX,
    const double* chiVpFluidY,
    const double* chiKineticWallReactionX0493x16j,
    const double* chiKineticWallReactionY0493x16j,
    double* reactionX,
    double* reactionY,
    double* reactionSums,
    int ncell) {
    const int c = blockIdx.x * blockDim.x + threadIdx.x;
    if (c >= ncell) return;
    const double dfx = darcyFluidX ? darcyFluidX[c] : 0.0;
    const double dfy = darcyFluidY ? darcyFluidY[c] : 0.0;
    const double vfx = chiVpFluidX ? chiVpFluidX[c] : 0.0;
    const double vfy = chiVpFluidY ? chiVpFluidY[c] : 0.0;
    // x16j buffers already store the reaction exerted ON the material wall;
    // Darcy/bath and chiVP arrays store the opposite, fluid-side impulse.
    const double kx = chiKineticWallReactionX0493x16j ? chiKineticWallReactionX0493x16j[c] : 0.0;
    const double ky = chiKineticWallReactionY0493x16j ? chiKineticWallReactionY0493x16j[c] : 0.0;
    const double sx = -(dfx + vfx) + kx;
    const double sy = -(dfy + vfy) + ky;
    reactionX[c] = sx;
    reactionY[c] = sy;
    atomicAdd(&reactionSums[0], sx);
    atomicAdd(&reactionSums[1], sy);
}

__global__ void kick_rigid_slab_state_0493x16f(
    double* state,
    const double* reactionSums) {
    if (blockIdx.x != 0 || threadIdx.x != 0) return;
    const double mass = state[2];
    if (!(mass > 0.0)) return;
    state[1] += reactionSums[0] / mass;
}

__global__ void advance_rigid_slab_state_0493x16e(
    double* state,
    const double* reactionSums,
    double dt,
    double Lx) {
    if (blockIdx.x != 0 || threadIdx.x != 0) return;
    const double mass = state[2];
    if (!(mass > 0.0)) return;
    double velocity = state[1] + reactionSums[0] / mass;
    double center = wrap_periodic_0493x16e(state[0] + dt * velocity, Lx);
    state[1] = velocity;
    state[0] = center;
}

void ensure_workspace_0493x16e(ResidentChiSolidWorkspace0493x16e& w,
                               int nx, int ny) {
    const std::size_t ncell = static_cast<std::size_t>(nx) * static_cast<std::size_t>(ny);
    if (w.nx == nx && w.ny == ny && w.d_state && w.d_rasterSolidCellEquivalent &&
        w.d_reactionSums && w.d_cellReactionX && w.d_cellReactionY &&
        w.d_newlySolidMask0493x16g && w.d_solidFraction0493x16i &&
        w.d_fractionDeltaSums0493x16i) {
        return;
    }
    cudaFree(w.d_state); w.d_state = nullptr;
    cudaFree(w.d_rasterSolidCellEquivalent); w.d_rasterSolidCellEquivalent = nullptr;
    cudaFree(w.d_reactionSums); w.d_reactionSums = nullptr;
    cudaFree(w.d_cellReactionX); w.d_cellReactionX = nullptr;
    cudaFree(w.d_cellReactionY); w.d_cellReactionY = nullptr;
    cudaFree(w.d_newlySolidMask0493x16g); w.d_newlySolidMask0493x16g = nullptr;
    cudaFree(w.d_solidFraction0493x16i); w.d_solidFraction0493x16i = nullptr;
    cudaFree(w.d_fractionDeltaSums0493x16i); w.d_fractionDeltaSums0493x16i = nullptr;
    w.initialized = false;
    w.nx = nx;
    w.ny = ny;
    check_cuda_0493x16e(cudaMalloc(&w.d_state, 4u * sizeof(double)), "allocate resident solid state");
    check_cuda_0493x16e(cudaMalloc(&w.d_rasterSolidCellEquivalent, sizeof(double)), "allocate raster sum");
    check_cuda_0493x16e(cudaMalloc(&w.d_reactionSums, 2u * sizeof(double)), "allocate reaction sums");
    check_cuda_0493x16e(cudaMalloc(&w.d_cellReactionX, ncell * sizeof(double)), "allocate reaction field x");
    check_cuda_0493x16e(cudaMalloc(&w.d_cellReactionY, ncell * sizeof(double)), "allocate reaction field y");
    check_cuda_0493x16e(cudaMalloc(&w.d_newlySolidMask0493x16g, ncell * sizeof(unsigned char)),
                        "allocate x16g newly-solid mask");
    check_cuda_0493x16e(cudaMemset(w.d_newlySolidMask0493x16g, 0, ncell * sizeof(unsigned char)),
                        "initialize x16g newly-solid mask");
    check_cuda_0493x16e(cudaMalloc(&w.d_solidFraction0493x16i, ncell * sizeof(float)),
                        "allocate x16i solid-fraction field");
    check_cuda_0493x16e(cudaMemset(w.d_solidFraction0493x16i, 0, ncell * sizeof(float)),
                        "initialize x16i solid-fraction field");
    check_cuda_0493x16e(cudaMalloc(&w.d_fractionDeltaSums0493x16i, 3u * sizeof(double)),
                        "allocate x16i fraction-delta sums");
    check_cuda_0493x16e(cudaMemset(w.d_fractionDeltaSums0493x16i, 0, 3u * sizeof(double)),
                        "initialize x16i fraction-delta sums");
}

void initialize_rigid_slab_state_if_needed_0493x16f(
    ResidentChiSolidWorkspace0493x16e& w,
    int nx,
    int ny,
    double Lx,
    double Ly,
    double initialCenterX,
    double initialVelocityX,
    double mass,
    double thickness) {
    ensure_workspace_0493x16e(w, nx, ny);
    if (!w.initialized) {
        const double hState[4] = {
            initialCenterX - floor(initialCenterX / Lx) * Lx,
            initialVelocityX,
            mass,
            thickness
        };
        check_cuda_0493x16e(cudaMemcpy(w.d_state, hState, sizeof(hState), cudaMemcpyHostToDevice),
                            "initialize x16f resident solid state");
        w.initialized = true;
        w.mass = mass;
        w.thickness = thickness;
        w.Lx = Lx;
        w.Ly = Ly;
        return;
    }
    const double scale = std::max({1.0, std::abs(w.mass), std::abs(mass),
                                   std::abs(w.thickness), std::abs(thickness),
                                   std::abs(w.Lx), std::abs(Lx), std::abs(w.Ly), std::abs(Ly)});
    if (std::abs(w.mass - mass) > 1.0e-12 * scale ||
        std::abs(w.thickness - thickness) > 1.0e-12 * scale ||
        std::abs(w.Lx - Lx) > 1.0e-12 * scale ||
        std::abs(w.Ly - Ly) > 1.0e-12 * scale) {
        throw std::runtime_error("0493x16f resident rigid-slab parameters changed after initialization");
    }
}

void fill_binary_geometry_diag_0493x16f(
    ResidentChiSolidWorkspace0493x16e& w,
    int nx,
    int ny,
    double Lx,
    double Ly,
    double centerBefore,
    double poststreamDrift,
    bool temporalSync,
    bool continuousChiGeometry0493x16j,
    CudaChiSolidDiagnostics0493x16e* diagnostics) {
    if (!diagnostics) return;
    double state[4]{0.0, 0.0, 0.0, 0.0};
    double solidCellEquivalent = 0.0;
    check_cuda_0493x16e(cudaMemcpy(state, w.d_state, sizeof(state), cudaMemcpyDeviceToHost),
                        "read x16f resident solid state after binary rasterization");
    check_cuda_0493x16e(cudaMemcpy(&solidCellEquivalent, w.d_rasterSolidCellEquivalent,
                                   sizeof(double), cudaMemcpyDeviceToHost),
                        "read x16f binary solid-volume sum");
    const double dx = Lx / static_cast<double>(nx);
    const double dy = Ly / static_cast<double>(ny);
    const double sampled = solidCellEquivalent * dx * dy;
    const double expected = state[3] * Ly;
    *diagnostics = CudaChiSolidDiagnostics0493x16e{};
    diagnostics->available = true;
    diagnostics->initialized = w.initialized;
    diagnostics->rasterized = continuousChiGeometry0493x16j;
    diagnostics->binaryHistorical0493x16f = !continuousChiGeometry0493x16j;
    diagnostics->temporalSync0493x16f = temporalSync;
    diagnostics->geometryVersion = w.geometryVersion;
    diagnostics->centerXBefore = centerBefore;
    diagnostics->centerXAfter = state[0];
    diagnostics->velocityXBefore = state[1];
    diagnostics->velocityXAfter = state[1];
    diagnostics->mass = state[2];
    diagnostics->thickness = state[3];
    diagnostics->sampledSolidVolume = sampled;
    diagnostics->expectedSolidVolume = expected;
    diagnostics->sampledSolidVolumeRelativeError =
        expected > 0.0 ? std::abs(sampled - expected) / expected : 0.0;
    diagnostics->poststreamDriftX0493x16f = poststreamDrift;
    diagnostics->prescribedDeformable0493x16i = w.prescribedDeformable0493x16i;
    diagnostics->deformAmplitude0493x16i = w.deformAmplitude0493x16i;
    diagnostics->deformOmega0493x16i = w.deformOmega0493x16i;
    if (w.d_fractionDeltaSums0493x16i) {
        double frac[3]{0.0,0.0,0.0};
        check_cuda_0493x16e(cudaMemcpy(frac, w.d_fractionDeltaSums0493x16i,
                                       sizeof(frac), cudaMemcpyDeviceToHost),
                            "read x16i fraction-delta diagnostics");
        diagnostics->positiveSolidFractionChange0493x16i = frac[0];
        diagnostics->negativeSolidFractionChange0493x16i = frac[1];
        diagnostics->maxAbsSolidFractionChange0493x16i = frac[2];
    }
    diagnostics->hostGeometryFieldUploadBytes = 0u;
    diagnostics->hostLoadFieldDownloadBytes = 0u;
}

void launch_binary_raster_0493x16f(
    ResidentChiSolidWorkspace0493x16e& w,
    float* deviceChi,
    float* deviceUSolidX,
    float* deviceUSolidY,
    int nx,
    int ny,
    double Lx,
    double Ly,
    double geometryTime0493x16i,
    bool detectNewlySolid0493x16g,
    bool trackFractionDelta0493x16i,
    bool continuousChiGeometry0493x16j) {
    check_cuda_0493x16e(cudaMemset(w.d_rasterSolidCellEquivalent, 0, sizeof(double)),
                        "reset x16f binary solid-volume sum");
    check_cuda_0493x16e(cudaMemset(w.d_fractionDeltaSums0493x16i, 0, 3u * sizeof(double)),
                        "reset x16i fraction-delta sums");
    const int threads = 256;
    const int ncell = nx * ny;
    const int blocks = (ncell + threads - 1) / threads;
    rasterize_rigid_slab_binary_0493x16f<<<blocks, threads>>>(
        w.d_state, deviceChi, deviceUSolidX, deviceUSolidY,
        nx, ny, Lx, Ly, geometryTime0493x16i,
        w.prescribedDeformable0493x16i ? w.deformAmplitude0493x16i : 0.0,
        w.prescribedDeformable0493x16i ? w.deformOmega0493x16i : 0.0,
        w.d_rasterSolidCellEquivalent,
        w.d_newlySolidMask0493x16g, detectNewlySolid0493x16g ? 1 : 0,
        w.d_solidFraction0493x16i, w.d_fractionDeltaSums0493x16i,
        trackFractionDelta0493x16i ? 1 : 0,
        continuousChiGeometry0493x16j ? 1 : 0);
    check_cuda_0493x16e(cudaGetLastError(), "launch x16f/x16i historical-binary deformable rasterizer");
    check_cuda_0493x16e(cudaDeviceSynchronize(), "x16f/x16i historical-binary deformable rasterizer");
}

} // namespace

bool cuda_chi_solid_0493x16e_available() { return true; }

bool cuda_chi_solid_0493x16f_prepare_rigid_slab_binary(
    float* deviceChi,
    float* deviceUSolidX,
    float* deviceUSolidY,
    int nx,
    int ny,
    double Lx,
    double Ly,
    double initialCenterX,
    double initialVelocityX,
    double mass,
    double thickness,
    double dt,
    std::uint64_t geometryVersion,
    int continuousChiGeometry0493x16j,
    CudaChiSolidDiagnostics0493x16e* diagnostics) {
    if (!deviceChi || !deviceUSolidX || !deviceUSolidY || nx <= 0 || ny <= 0 ||
        !(Lx > 0.0) || !(Ly > 0.0) || !(mass > 0.0) || !(thickness > 0.0) ||
        thickness >= Lx) {
        return false;
    }
    auto& w = workspace_0493x16e();
    initialize_rigid_slab_state_if_needed_0493x16f(
        w, nx, ny, Lx, Ly, initialCenterX, initialVelocityX, mass, thickness);
    w.geometryVersion = geometryVersion > 0u ? geometryVersion : 1u;
    w.dt0493x16i = dt;
    w.prescribedDeformable0493x16i = env_truthy_0493x16i("SRC_X16I_PRESCRIBED_DEFORMABLE");
    if (w.prescribedDeformable0493x16i) {
        const double dx = Lx / static_cast<double>(nx);
        const double ampCells = env_double_0493x16i("SRC_X16I_DEFORM_AMPLITUDE_CELLS", 0.75);
        const bool staticCurved0493x16m =
            env_truthy_0493x16i("SRC_X16I_STATIC_CURVED_0493X16M");
        w.deformAmplitude0493x16i = ampCells * dx;
        if (staticCurved0493x16m) {
            // Diagnostic only: freeze x16i at its maximum-curvature shape.
            // omega=0 is interpreted by prescribed_centerline_0493x16i as
            // x_c(y)=X+A sin(k_y y), while the local wall velocity contains
            // only the rigid translation velocity.
            w.deformOmega0493x16i = 0.0;
        } else {
            const double periodSteps = env_double_0493x16i("SRC_X16I_DEFORM_PERIOD_STEPS", 400.0);
            if (!(periodSteps > 4.0) || !(dt > 0.0)) {
                throw std::runtime_error("0493x16i requires DEFORM_PERIOD_STEPS>4 and dt>0");
            }
            w.deformOmega0493x16i = 2.0 * 3.141592653589793238462643383279502884 / (periodSteps * dt);
        }
    } else {
        w.deformAmplitude0493x16i = 0.0;
        w.deformOmega0493x16i = 0.0;
    }

    double before[4]{0.0, 0.0, 0.0, 0.0};
    if (diagnostics) {
        check_cuda_0493x16e(cudaMemcpy(before, w.d_state, sizeof(before), cudaMemcpyDeviceToHost),
                            "read x16f resident solid state before prepare");
    }
    const double geometryTime0493x16i = static_cast<double>(w.geometryVersion - 1u) * dt;
    launch_binary_raster_0493x16f(
        w, deviceChi, deviceUSolidX, deviceUSolidY, nx, ny, Lx, Ly,
        geometryTime0493x16i, false, false, continuousChiGeometry0493x16j != 0);
    fill_binary_geometry_diag_0493x16f(
        w, nx, ny, Lx, Ly, before[0], 0.0, false,
        continuousChiGeometry0493x16j != 0, diagnostics);
    return true;
}

bool cuda_chi_solid_0493x16f_poststream_sync_rigid_slab(
    float* deviceChi,
    float* deviceUSolidX,
    float* deviceUSolidY,
    int nx,
    int ny,
    double Lx,
    double Ly,
    double dt,
    std::uint64_t geometryVersion,
    int continuousChiGeometry0493x16j,
    CudaChiSolidDiagnostics0493x16e* diagnostics) {
    auto& w = workspace_0493x16e();
    if (!w.initialized || !w.d_state || !deviceChi || !deviceUSolidX || !deviceUSolidY ||
        nx != w.nx || ny != w.ny || !(Lx > 0.0) || !(Ly > 0.0) || !(dt > 0.0)) {
        return false;
    }
    w.geometryVersion = geometryVersion > 0u ? geometryVersion : 1u;
    double before[4]{0.0, 0.0, 0.0, 0.0};
    if (diagnostics) {
        check_cuda_0493x16e(cudaMemcpy(before, w.d_state, sizeof(before), cudaMemcpyDeviceToHost),
                            "read x16f resident solid state before poststream drift");
    }
    drift_rigid_slab_state_0493x16f<<<1,1>>>(w.d_state, dt, Lx);
    check_cuda_0493x16e(cudaGetLastError(), "launch x16f poststream solid drift");
    const double geometryTime0493x16i = static_cast<double>(w.geometryVersion) * dt;
    launch_binary_raster_0493x16f(
        w, deviceChi, deviceUSolidX, deviceUSolidY, nx, ny, Lx, Ly,
        geometryTime0493x16i, true, w.prescribedDeformable0493x16i,
        continuousChiGeometry0493x16j != 0);

    double after[4]{0.0, 0.0, 0.0, 0.0};
    if (diagnostics) {
        check_cuda_0493x16e(cudaMemcpy(after, w.d_state, sizeof(after), cudaMemcpyDeviceToHost),
                            "read x16f resident solid state after poststream drift");
    }
    double rawDrift = 0.0;
    if (diagnostics) {
        rawDrift = after[0] - before[0];
        rawDrift -= std::nearbyint(rawDrift / Lx) * Lx;
    }
    fill_binary_geometry_diag_0493x16f(
        w, nx, ny, Lx, Ly, before[0], rawDrift, true,
        continuousChiGeometry0493x16j != 0, diagnostics);
    return true;
}

bool cuda_chi_solid_0493x16g_device_newly_solid_mask(
    const unsigned char** deviceMask, int* nxOut, int* nyOut) {
    if (deviceMask) *deviceMask = nullptr;
    if (nxOut) *nxOut = 0;
    if (nyOut) *nyOut = 0;
    auto& w = workspace_0493x16e();
    if (!w.initialized || !w.d_newlySolidMask0493x16g || w.nx <= 0 || w.ny <= 0) {
        return false;
    }
    if (deviceMask) *deviceMask = w.d_newlySolidMask0493x16g;
    if (nxOut) *nxOut = w.nx;
    if (nyOut) *nyOut = w.ny;
    return true;
}


bool cuda_chi_solid_0493x16k_device_solid_fraction(
    const float** deviceSolidFraction, int* nxOut, int* nyOut) {
    if (deviceSolidFraction) *deviceSolidFraction = nullptr;
    if (nxOut) *nxOut = 0;
    if (nyOut) *nyOut = 0;
    auto& w = workspace_0493x16e();
    if (!w.initialized || !w.d_solidFraction0493x16i || w.nx <= 0 || w.ny <= 0) {
        return false;
    }
    if (deviceSolidFraction) *deviceSolidFraction = w.d_solidFraction0493x16i;
    if (nxOut) *nxOut = w.nx;
    if (nyOut) *nyOut = w.ny;
    return true;
}

bool cuda_chi_solid_0493x16i_prescribed_geometry(
    CudaPrescribedDeformableGeometry0493x16i* geometry) {
    if (geometry) *geometry = CudaPrescribedDeformableGeometry0493x16i{};
    auto& w = workspace_0493x16e();
    if (!w.initialized || !w.d_state || !w.prescribedDeformable0493x16i) return false;
    if (geometry) {
        geometry->enabled = true;
        geometry->deviceState = w.d_state;
        geometry->amplitude = w.deformAmplitude0493x16i;
        geometry->omega = w.deformOmega0493x16i;
        geometry->Lx = w.Lx;
        geometry->Ly = w.Ly;
        geometry->dt = w.dt0493x16i;
    }
    return true;
}

bool cuda_chi_solid_0493x16f_apply_rigid_slab_impulse(
    const double* deviceDarcyFluidImpulseX,
    const double* deviceDarcyFluidImpulseY,
    const double* deviceChiVpFluidImpulseX,
    const double* deviceChiVpFluidImpulseY,
    const double* deviceChiKineticWallReactionX0493x16j,
    const double* deviceChiKineticWallReactionY0493x16j,
    int nx,
    int ny,
    double dt,
    double Lx,
    CudaChiSolidDiagnostics0493x16e* diagnostics) {
    (void)dt;
    (void)Lx;
    auto& w = workspace_0493x16e();
    if (!w.initialized || !w.d_state || nx != w.nx || ny != w.ny ||
        !deviceDarcyFluidImpulseX || !deviceDarcyFluidImpulseY) {
        return false;
    }
    const int ncell = nx * ny;
    check_cuda_0493x16e(cudaMemset(w.d_reactionSums, 0, 2u * sizeof(double)),
                        "reset x16f resident reaction sums");
    const int threads = 256;
    const int blocks = (ncell + threads - 1) / threads;
    assemble_reaction_field_0493x16e<<<blocks, threads>>>(
        deviceDarcyFluidImpulseX, deviceDarcyFluidImpulseY,
        deviceChiVpFluidImpulseX, deviceChiVpFluidImpulseY,
        deviceChiKineticWallReactionX0493x16j,
        deviceChiKineticWallReactionY0493x16j,
        w.d_cellReactionX, w.d_cellReactionY, w.d_reactionSums, ncell);
    check_cuda_0493x16e(cudaGetLastError(), "launch x16f resident load assembly");

    double before[4]{0.0, 0.0, 0.0, 0.0};
    if (diagnostics) {
        check_cuda_0493x16e(cudaMemcpy(before, w.d_state, sizeof(before), cudaMemcpyDeviceToHost),
                            "read x16f resident solid state before kick");
    }
    kick_rigid_slab_state_0493x16f<<<1,1>>>(w.d_state, w.d_reactionSums);
    check_cuda_0493x16e(cudaGetLastError(), "launch x16f resident rigid-slab kick");
    check_cuda_0493x16e(cudaDeviceSynchronize(), "x16f resident rigid-slab kick");

    if (diagnostics) {
        double after[4]{0.0, 0.0, 0.0, 0.0};
        double reaction[2]{0.0, 0.0};
        check_cuda_0493x16e(cudaMemcpy(after, w.d_state, sizeof(after), cudaMemcpyDeviceToHost),
                            "read x16f resident solid state after kick");
        check_cuda_0493x16e(cudaMemcpy(reaction, w.d_reactionSums, sizeof(reaction), cudaMemcpyDeviceToHost),
                            "read x16f resident reaction sums");
        *diagnostics = CudaChiSolidDiagnostics0493x16e{};
        diagnostics->available = true;
        diagnostics->initialized = true;
        diagnostics->advanced = true;
        diagnostics->binaryHistorical0493x16f = true;
        diagnostics->temporalSync0493x16f = true;
        diagnostics->geometryVersion = w.geometryVersion;
        diagnostics->centerXBefore = before[0];
        diagnostics->centerXAfter = after[0];
        diagnostics->velocityXBefore = before[1];
        diagnostics->velocityXAfter = after[1];
        diagnostics->mass = after[2];
        diagnostics->thickness = after[3];
        diagnostics->cellReactionSumX = reaction[0];
        diagnostics->cellReactionSumY = reaction[1];
        diagnostics->generalizedImpulseX = reaction[0];
        diagnostics->primaryProjectionResidual = 0.0;
        diagnostics->hostGeometryFieldUploadBytes = 0u;
        diagnostics->hostLoadFieldDownloadBytes = 0u;
    }
    return true;
}

bool cuda_chi_solid_0493x16e_prepare_rigid_slab(
    float* deviceChi,
    float* deviceUSolidX,
    float* deviceUSolidY,
    int nx,
    int ny,
    double Lx,
    double Ly,
    double initialCenterX,
    double initialVelocityX,
    double mass,
    double thickness,
    std::uint64_t geometryVersion,
    CudaChiSolidDiagnostics0493x16e* diagnostics) {
    if (!deviceChi || !deviceUSolidX || !deviceUSolidY || nx <= 0 || ny <= 0 ||
        !(Lx > 0.0) || !(Ly > 0.0) || !(mass > 0.0) || !(thickness > 0.0) ||
        thickness >= Lx) {
        return false;
    }
    auto& w = workspace_0493x16e();
    ensure_workspace_0493x16e(w, nx, ny);
    if (!w.initialized) {
        const double hState[4] = {
            initialCenterX - floor(initialCenterX / Lx) * Lx,
            initialVelocityX,
            mass,
            thickness
        };
        check_cuda_0493x16e(cudaMemcpy(w.d_state, hState, sizeof(hState), cudaMemcpyHostToDevice),
                            "initialize resident solid state");
        w.initialized = true;
        w.mass = mass;
        w.thickness = thickness;
        w.Lx = Lx;
        w.Ly = Ly;
    } else {
        const double scale = std::max({1.0, std::abs(w.mass), std::abs(mass),
                                      std::abs(w.thickness), std::abs(thickness),
                                      std::abs(w.Lx), std::abs(Lx), std::abs(w.Ly), std::abs(Ly)});
        if (std::abs(w.mass - mass) > 1.0e-12 * scale ||
            std::abs(w.thickness - thickness) > 1.0e-12 * scale ||
            std::abs(w.Lx - Lx) > 1.0e-12 * scale ||
            std::abs(w.Ly - Ly) > 1.0e-12 * scale) {
            throw std::runtime_error("0493x16e resident rigid-slab parameters changed after initialization");
        }
    }

    w.geometryVersion = geometryVersion > 0u ? geometryVersion : 1u;
    check_cuda_0493x16e(cudaMemset(w.d_rasterSolidCellEquivalent, 0, sizeof(double)),
                        "reset raster solid-volume sum");
    const int threads = 256;
    const int ncell = nx * ny;
    const int blocks = (ncell + threads - 1) / threads;
    rasterize_rigid_slab_subcell_0493x16e<<<blocks, threads>>>(
        w.d_state, deviceChi, deviceUSolidX, deviceUSolidY,
        nx, ny, Lx, w.d_rasterSolidCellEquivalent);
    check_cuda_0493x16e(cudaGetLastError(), "launch subcell rigid-slab rasterizer");
    check_cuda_0493x16e(cudaDeviceSynchronize(), "subcell rigid-slab rasterizer");

    if (diagnostics) {
        double state[4]{0.0, 0.0, 0.0, 0.0};
        double solidCellEquivalent = 0.0;
        check_cuda_0493x16e(cudaMemcpy(state, w.d_state, sizeof(state), cudaMemcpyDeviceToHost),
                            "read resident solid state after rasterization");
        check_cuda_0493x16e(cudaMemcpy(&solidCellEquivalent, w.d_rasterSolidCellEquivalent,
                                       sizeof(double), cudaMemcpyDeviceToHost),
                            "read raster solid-volume sum");
        const double dx = Lx / static_cast<double>(nx);
        const double dy = Ly / static_cast<double>(ny);
        const double sampled = solidCellEquivalent * dx * dy;
        const double expected = thickness * Ly;
        *diagnostics = CudaChiSolidDiagnostics0493x16e{};
        diagnostics->available = true;
        diagnostics->initialized = w.initialized;
        diagnostics->rasterized = true;
        diagnostics->geometryVersion = w.geometryVersion;
        diagnostics->centerXBefore = state[0];
        diagnostics->centerXAfter = state[0];
        diagnostics->velocityXBefore = state[1];
        diagnostics->velocityXAfter = state[1];
        diagnostics->mass = state[2];
        diagnostics->thickness = state[3];
        diagnostics->sampledSolidVolume = sampled;
        diagnostics->expectedSolidVolume = expected;
        diagnostics->sampledSolidVolumeRelativeError =
            expected > 0.0 ? std::abs(sampled - expected) / expected : 0.0;
        diagnostics->hostGeometryFieldUploadBytes = 0u;
        diagnostics->hostLoadFieldDownloadBytes = 0u;
    }
    return true;
}

bool cuda_chi_solid_0493x16e_advance_rigid_slab(
    const double* deviceDarcyFluidImpulseX,
    const double* deviceDarcyFluidImpulseY,
    const double* deviceChiVpFluidImpulseX,
    const double* deviceChiVpFluidImpulseY,
    int nx,
    int ny,
    double dt,
    double Lx,
    CudaChiSolidDiagnostics0493x16e* diagnostics) {
    auto& w = workspace_0493x16e();
    if (!w.initialized || !w.d_state || nx != w.nx || ny != w.ny ||
        !deviceDarcyFluidImpulseX || !deviceDarcyFluidImpulseY || !(dt > 0.0) || !(Lx > 0.0)) {
        return false;
    }
    const int ncell = nx * ny;
    check_cuda_0493x16e(cudaMemset(w.d_reactionSums, 0, 2u * sizeof(double)),
                        "reset resident reaction sums");
    const int threads = 256;
    const int blocks = (ncell + threads - 1) / threads;
    assemble_reaction_field_0493x16e<<<blocks, threads>>>(
        deviceDarcyFluidImpulseX, deviceDarcyFluidImpulseY,
        deviceChiVpFluidImpulseX, deviceChiVpFluidImpulseY,
        nullptr, nullptr,
        w.d_cellReactionX, w.d_cellReactionY, w.d_reactionSums, ncell);
    check_cuda_0493x16e(cudaGetLastError(), "launch resident load assembly");

    double before[4]{0.0, 0.0, 0.0, 0.0};
    // Diagnostic-only scalar copy; it does not participate in the update.
    if (diagnostics) {
        check_cuda_0493x16e(cudaMemcpy(before, w.d_state, sizeof(before), cudaMemcpyDeviceToHost),
                            "read resident solid state before advance");
    }

    advance_rigid_slab_state_0493x16e<<<1,1>>>(w.d_state, w.d_reactionSums, dt, Lx);
    check_cuda_0493x16e(cudaGetLastError(), "launch resident rigid-slab advance");
    check_cuda_0493x16e(cudaDeviceSynchronize(), "resident rigid-slab advance");

    if (diagnostics) {
        double after[4]{0.0, 0.0, 0.0, 0.0};
        double reaction[2]{0.0, 0.0};
        check_cuda_0493x16e(cudaMemcpy(after, w.d_state, sizeof(after), cudaMemcpyDeviceToHost),
                            "read resident solid state after advance");
        check_cuda_0493x16e(cudaMemcpy(reaction, w.d_reactionSums, sizeof(reaction), cudaMemcpyDeviceToHost),
                            "read resident reaction sums");
        diagnostics->available = true;
        diagnostics->initialized = true;
        diagnostics->advanced = true;
        diagnostics->geometryVersion = w.geometryVersion;
        diagnostics->centerXBefore = before[0];
        diagnostics->centerXAfter = after[0];
        diagnostics->velocityXBefore = before[1];
        diagnostics->velocityXAfter = after[1];
        diagnostics->mass = after[2];
        diagnostics->thickness = after[3];
        diagnostics->cellReactionSumX = reaction[0];
        diagnostics->cellReactionSumY = reaction[1];
        diagnostics->generalizedImpulseX = reaction[0];
        diagnostics->primaryProjectionResidual = 0.0;
        diagnostics->hostGeometryFieldUploadBytes = 0u;
        diagnostics->hostLoadFieldDownloadBytes = 0u;
    }
    return true;
}

bool cuda_chi_solid_0493x16e_device_reaction_field(
    const double** deviceReactionX,
    const double** deviceReactionY,
    int* nx,
    int* ny) {
    if (deviceReactionX) *deviceReactionX = nullptr;
    if (deviceReactionY) *deviceReactionY = nullptr;
    if (nx) *nx = 0;
    if (ny) *ny = 0;
    auto& w = workspace_0493x16e();
    if (!w.initialized || !w.d_cellReactionX || !w.d_cellReactionY) return false;
    if (deviceReactionX) *deviceReactionX = w.d_cellReactionX;
    if (deviceReactionY) *deviceReactionY = w.d_cellReactionY;
    if (nx) *nx = w.nx;
    if (ny) *ny = w.ny;
    return true;
}

} // namespace mpcd

#endif
