
// mpcd_vonkarman_cuda_omp.cu
// MPCD/SRD 2D around a cylinder with "solid fixed particles" wall treatment (Crespin-style),
// translated from mpcd_vonkarman_v2_solid_cyl.m.
//
// Key steps per iteration:
// 1) Streaming: x += dt * v
// 2) Periodic wrap
// 3) Cylinder interaction: repulsion vs fixed solid particles (angle-binned nearest)
// 4) SRD collision with random grid shift (Galilean invariance), per-cell rotation ±alpha
// 5) Optional local thermostat (rescale relative velocities to target kBT)
// 6) Optional keepMeanFlow: enforce <ux>=U0 and <uy>=0
// 7) Dump velocity field and vorticity every dumpStride steps
//
// Build (example):
//   nvcc -O3 -std=c++17 -Xcompiler -fopenmp mpcd_vonkarman_cuda_omp.cu -o mpcd_vk
//
// Notes:
// - Uses float on GPU for speed; totals (energy, means) computed in double on host.
// - Per-cell reductions use atomicAdd; for higher perf you can switch to sort-by-cell + reduce-by-key,
//   but this version is stable, readable, and already fast for gamma ~ 5-10.
//

#include <cuda_runtime.h>

#ifdef USE_GL_VIS
#ifndef GL_GLEXT_PROTOTYPES
#define GL_GLEXT_PROTOTYPES 1
#endif
#include <GLFW/glfw3.h>
#include <cuda_gl_interop.h>
#endif
#include <cstdio>
#include <cstdlib>
#include <cstdint>
#include <cmath>
#include <vector>
#include <string>
#include <random>
#include <algorithm>
#include <fstream>
#include <sstream>
#include <iomanip>
#include <iostream>

#ifdef _OPENMP
#include <omp.h>
#endif

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

// ----------------------- CUDA helpers -----------------------
static inline void cudaCheck(cudaError_t err, const char* msg) {
    if (err != cudaSuccess) {
        std::fprintf(stderr, "CUDA error: %s: %s\n", msg, cudaGetErrorString(err));
        std::exit(1);
    }
}

__host__ __device__ static inline uint32_t wang_hash(uint32_t a) {
    a = (a ^ 61u) ^ (a >> 16);
    a *= 9u;
    a = a ^ (a >> 4);
    a *= 0x27d4eb2du;
    a = a ^ (a >> 15);
    return a;
}

__device__ static inline float hash_u01(uint32_t seed, uint32_t i, uint32_t step, uint32_t salt) {
    uint32_t h = wang_hash(seed ^ (i * 747796405u) ^ (step * 2891336453u) ^ salt);
    // map to [0,1)
    return ((float)h) * (1.0f / 4294967296.0f);
}

__device__ static inline float wrap_periodic(float x, float L) {
    // Wrap into [0, L)
    x -= floorf(x / L) * L;
    // guard tiny negative due to float error
    if (x >= L) x -= L;
    if (x < 0.f) x += L;
    return x;
}

__host__ __device__ static inline float periodic_delta(float d, float L) {
    if (d >  0.5f*L) d -= L;
    if (d < -0.5f*L) d += L;
    return d;
}

__device__ __forceinline__ float species_mass_from_tag(unsigned char s, int useSpeciesMass, float m1, float m2) {
    if (!useSpeciesMass) return 1.f;
    return (s == 0) ? m1 : m2;
}


__global__ void streaming_wrap_kernel(
    float* __restrict__ x, float* __restrict__ y,
    float* __restrict__ vx, float* __restrict__ vy,
    int n, float dt, float Lx, float Ly)
{
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= n) return;
    x[i] += dt * vx[i];
    y[i] += dt * vy[i];
    x[i] = wrap_periodic(x[i], Lx);
    y[i] = wrap_periodic(y[i], Ly);
}



// Streaming with y-periodicity and x open boundary with reinjection at inlet x~0.
// Any particle exiting downstream (x>=Lx) -- and optionally upstream (x<0) -- is re-injected
// with a clean inflow velocity (homogeneous U0, vy=0), which prevents wake vortices from
// being wrapped back into the upstream region.
__global__ void streaming_injectx_ywrap_kernel(
    float* __restrict__ x, float* __restrict__ y,
    float* __restrict__ vx, float* __restrict__ vy,
    unsigned char* __restrict__ tag,
    int n, float dt, float Lx, float Ly,
    float a0, float Uin,
    int reinjectBackflow,
    int randomizeY,
    int twoFluidTracer,
    float tracerSplitY,
    uint32_t seed, uint32_t step)
{
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= n) return;

    float xi = x[i] + dt * vx[i];
    float yi = y[i] + dt * vy[i];

    yi = wrap_periodic(yi, Ly);

    bool reinj = (xi >= Lx) || (reinjectBackflow && xi < 0.f);
    if (reinj) {
        // Put the particle back near x=0 with a random y to keep a homogeneous inlet density.
        float u1 = hash_u01(seed, (uint32_t)i, step, 0xA511E9B3u);
        float u2 = hash_u01(seed, (uint32_t)i, step, 0x9E3779B9u);

        float xinj = u1 * fmaxf(a0, 1e-12f);      // thin inlet slab [0,a0)
        if (xinj >= Lx) xinj = nextafterf(Lx, 0.f);
        xi = xinj;
        if (randomizeY) yi = u2 * Ly;

        vx[i] = Uin;   // homogeneous inflow speed
        vy[i] = 0.f;   // no transverse bias at injection

        if (twoFluidTracer && tag) {
            float ytag = yi;
            if (ytag < 0.f) ytag = 0.f;
            if (ytag >= Ly) ytag = nextafterf(Ly, 0.f);
            tag[i] = (unsigned char)((ytag < tracerSplitY) ? 0 : 1);
        }
    } else if (xi < 0.f) {
        // If upstream reinjection is disabled, keep particles in-domain (simple clamp).
        xi = 0.f;
    }

    x[i] = xi;
    y[i] = yi;

}

//
// Streaming with y-periodicity and x open boundary, but inlet reinjection can impose a
// central *band* (strip) of species-2/jet velocity around y=yJet with thickness Djet.
// This is the 2D analogue of an injector jet entering from x=0; in 3D the same idea can
// be extended to a circular injector footprint in (y,z).
__global__ void streaming_injectx_ywrap_stripejet_kernel(
    float* __restrict__ x, float* __restrict__ y,
    float* __restrict__ vx, float* __restrict__ vy,
    unsigned char* __restrict__ tag,
    int n, float dt, float Lx, float Ly,
    float a0,
    int reinjectBackflow,
    int randomizeY,
    int twoFluidTracer,
    int periodicY,
    float yJet,
    float jetD,
    float Ujet,
    float deltaU,
    float deltaRho,
    uint32_t seed, uint32_t step)
{
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= n) return;

    float xi = x[i] + dt * vx[i];
    float yi = y[i] + dt * vy[i];

    if (periodicY) yi = wrap_periodic(yi, Ly);

    bool reinj = (xi >= Lx) || (reinjectBackflow && xi < 0.f);
    if (reinj) {
        float u1 = hash_u01(seed, (uint32_t)i, step, 0xA511E9B3u);
        float u2 = hash_u01(seed, (uint32_t)i, step, 0x9E3779B9u);
        float u3 = hash_u01(seed, (uint32_t)i, step, 0x243F6A88u);

        float xinj = u1 * fmaxf(a0, 1e-12f);  // thin inlet slab [0,a0)
        if (xinj >= Lx) xinj = nextafterf(Lx, 0.f);
        xi = xinj;
        if (randomizeY) yi = u2 * Ly;

        // Central band profile in y (periodic in y), smoothed over deltaU/deltaRho.
        float dy = periodicY ? periodic_delta(yi - yJet, Ly) : (yi - yJet);
        float q  = fabsf(dy) - 0.5f * fmaxf(jetD, 0.f);   // signed distance to band edge
        float Su = 0.5f * (1.f - tanhf(q / fmaxf(deltaU, 1e-12f)));   // ~1 in jet core, ~0 ambient
        float Sr = 0.5f * (1.f - tanhf(q / fmaxf(deltaRho, 1e-12f))); // species-2 probability

        unsigned char tg_local = (tag ? tag[i] : (unsigned char)0);
        if (twoFluidTracer && tag) {
            // species-2 in jet core, species-1 in ambient (smooth probabilistic transition)
            float p2 = fminf(1.f, fmaxf(0.f, Sr));
            tg_local = (unsigned char)((u3 < p2) ? 1 : 0);
            tag[i] = tg_local;
        }

        // Important for inlet-jet KH with walls: inject ambient/species-1 exactly at rest to avoid
        // slowly spinning up the whole surrounding fluid via smooth tanh tails near the jet edge.
        vx[i] = (twoFluidTracer && tag && tg_local == (unsigned char)0) ? 0.f : (Ujet * Su);
        vy[i] = 0.f;
    } else if (xi < 0.f) {
        xi = 0.f;
    }

    x[i] = xi;
    y[i] = yi;
}

__global__ void streaming_xwrap_kernel(
    float* __restrict__ x, float* __restrict__ y,
    float* __restrict__ vx, float* __restrict__ vy,
    int n, float dt, float Lx)
{
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= n) return;
    x[i] += dt * vx[i];
    y[i] += dt * vy[i];
    x[i] = wrap_periodic(x[i], Lx);
    // y is not wrapped here (used for Couette with solid y-walls)
}

// Cylinder interaction via fixed solid particles on circumference (angle-binned nearest).
// Repeats nIter times (host loops calling kernel) for stability.
__global__ void solid_cylinder_repulsion_kernel(
    float* __restrict__ x, float* __restrict__ y,
    float* __restrict__ vx, float* __restrict__ vy,
    int n,
    float Lx, float Ly,
    float xc, float yc, float Rc,
    int nSolid,
    float Lr, float dV, float maxDisp,
    float* __restrict__ dPy_accum)
{
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= n) return;

    float xi = x[i];
    float yi = y[i];

    float dx = xi - xc;
    float dy = yi - yc;
    float rr = hypotf(dx, dy);
    if (rr < 1e-14f) rr = 1e-14f;

    // Closest solid particle by angle bin
    float th = atan2f(dy, dx);
    if (th < 0.f) th += 2.f * (float)M_PI;
    int idx = (int)floorf(th * ((float)nSolid / (2.f * (float)M_PI)));
    if (idx < 0) idx = 0;
    if (idx >= nSolid) idx = nSolid - 1;
    float angle = (2.f * (float)M_PI) * ((float)idx / (float)nSolid);

    float ca = cosf(angle), sa = sinf(angle);
    float sx = xc + Rc * ca;
    float sy = yc + Rc * sa;

    float rx = xi - sx;
    float ry = yi - sy;
    float ds = hypotf(rx, ry);
    if (ds < 1e-14f) ds = 1e-14f;

    bool inside = (rr < Rc);
    bool interact = (ds < Lr) || inside;
    if (!interact) return;

    // Repulsion normal
    float nx = rx / ds;
    float ny = ry / ds;
    if (inside) {
        nx = dx / rr;
        ny = dy / rr;
    }

    float dispMag = 0.5f * (Lr - ds);
    if (dispMag < 0.f) dispMag = 0.f;
    if (inside) {
        dispMag = fmaxf(dispMag, (Rc - rr) + 0.5f * Lr);
    }
    dispMag = fminf(dispMag, maxDisp);

    float dposx = dispMag * nx;
    float dposy = dispMag * ny;

    xi += dposx;
    yi += dposy;

    // wrap after displacement (important if repulsion pushes across boundaries)
    xi = wrap_periodic(xi, Lx);
    yi = wrap_periodic(yi, Ly);

    float oldVy = vy[i];
    vx[i] += dV * dposx;
    vy[i] += dV * dposy;

    x[i] = xi;
    y[i] = yi;

    if (dPy_accum) {
        atomicAdd(dPy_accum, (vy[i] - oldVy));
    }
}

// Safety projection: ensure outside Rc+epsWall and remove inward normal component
__global__ void solid_cylinder_project_kernel(
    float* __restrict__ x, float* __restrict__ y,
    float* __restrict__ vx, float* __restrict__ vy,
    int n,
    float Lx, float Ly,
    float xc, float yc, float Rc, float epsWall)
{
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= n) return;

    float xi = x[i];
    float yi = y[i];
    float dx = xi - xc;
    float dy = yi - yc;
    float rr = hypotf(dx, dy);
    if (rr < 1e-14f) rr = 1e-14f;

    float Rmin = Rc + epsWall;
    if (rr < Rmin) {
        float nx = dx / rr;
        float ny = dy / rr;
        xi = xc + Rmin * nx;
        yi = yc + Rmin * ny;

        // remove inward normal component only
        float vn = vx[i] * nx + vy[i] * ny;
        if (vn < 0.f) {
            vx[i] -= vn * nx;
            vy[i] -= vn * ny;
        }

        x[i] = wrap_periodic(xi, Lx);
        y[i] = wrap_periodic(yi, Ly);
    }
}


// Cylinder bounce-back on analytic cylinder.
//   * bbEt = -1 : no-slip bounce-back (tangential component reversed)
//   * bbEt = +1 : specular / free-slip reflection (tangential preserved)
// Applied after streaming. Projects particle to Rc+epsWall and reflects velocity.
__global__ void cylinder_bounceback_kernel(
    float* __restrict__ x, float* __restrict__ y,
    float* __restrict__ vx, float* __restrict__ vy,
    int n,
    float Lx, float Ly,
    float xc, float yc, float Rc, float epsWall,
    float bbEn, float bbEt,
    float* __restrict__ dPy_accum)
{
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= n) return;

    float xi = x[i];
    float yi = y[i];
    float dx = xi - xc;
    float dy = yi - yc;
    float rr = hypotf(dx, dy);
    if (rr < 1e-14f) rr = 1e-14f;

    if (rr >= Rc) return;

    float nx = dx / rr;
    float ny = dy / rr;

    // Project out
    xi = xc + (Rc + epsWall) * nx;
    yi = yc + (Rc + epsWall) * ny;
    xi = wrap_periodic(xi, Lx);
    yi = wrap_periodic(yi, Ly);

    float oldVy = vy[i];

    // Decompose v = vn n + vt
    float vxi = vx[i];
    float vyi = vy[i];
    float vn = vxi * nx + vyi * ny;
    float vtx = vxi - vn * nx;
    float vty = vyi - vn * ny;

    // Reflect: vn' = -bbEn*vn ; vt' = bbEt*vt
    float vxn = (-bbEn * vn) * nx;
    float vyn = (-bbEn * vn) * ny;
    float vxt = bbEt * vtx;
    float vyt = bbEt * vty;

    vx[i] = vxn + vxt;
    vy[i] = vyn + vyt;
    x[i] = xi;
    y[i] = yi;

    if (dPy_accum) {
        atomicAdd(dPy_accum, (vy[i] - oldVy));
    }
}

// Couette y-wall bounce-back with moving walls.
// Bottom wall at y=0 moves with Ubot (x-direction); top wall at y=Ly moves with Utop.
__global__ void couette_ywall_bounce_kernel(
    float* __restrict__ y,
    float* __restrict__ vx, float* __restrict__ vy,
    int n,
    float Ly,
    float Ubot, float Utop,
    float* __restrict__ dPx_bot,
    float* __restrict__ dPx_top)
{
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= n) return;

    float yi = y[i];
    float vxi = vx[i];
    float vyi = vy[i];

    // bottom wall
    if (yi < 0.f) {
        float oldvx = vxi;
        yi = -yi;
        vyi = -vyi;
        vxi = 2.f * Ubot - vxi; // no-slip bounce in moving wall frame
        if (dPx_bot) atomicAdd(dPx_bot, (vxi - oldvx));
    }
    // top wall
    else if (yi >= Ly) {
        float oldvx = vxi;
        yi = 2.f * Ly - yi;
        vyi = -vyi;
        vxi = 2.f * Utop - vxi;
        if (dPx_top) atomicAdd(dPx_top, (vxi - oldvx));
    }

    // clamp for safety (handles too-large dt overshoots)
    if (yi < 0.f) yi = 0.f;
    if (yi >= Ly) yi = nextafterf(Ly, 0.f);

    y[i]  = yi;
    vx[i] = vxi;
    vy[i] = vyi;
}


// KH inlet-jet helper: y-wall reflection with *tangential reset* (u_wall=0 enforced strongly).
// Normal component is reflected; tangential x-velocity is reset to zero on wall crossing.
// This damps the ambient entrainment faster than a pure bounce-back and preserves a shear reservoir.
__global__ void kh_ywall_reflect_zeroUx_kernel(
    float* __restrict__ y,
    float* __restrict__ vx, float* __restrict__ vy,
    int n,
    float Ly,
    float* __restrict__ dPx_bot,
    float* __restrict__ dPx_top)
{
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= n) return;

    float yi = y[i];
    float vxi = vx[i];
    float vyi = vy[i];

    if (yi < 0.f) {
        float oldvx = vxi;
        yi = -yi;
        vyi = fabsf(vyi); // reflect back into domain
        vxi = 0.f;        // enforce stationary wall tangential velocity
        if (dPx_bot) atomicAdd(dPx_bot, (vxi - oldvx));
    }
    else if (yi >= Ly) {
        float oldvx = vxi;
        yi = 2.f * Ly - yi;
        vyi = -fabsf(vyi);
        vxi = 0.f;
        if (dPx_top) atomicAdd(dPx_top, (vxi - oldvx));
    }

    if (yi < 0.f) yi = 0.f;
    if (yi >= Ly) yi = nextafterf(Ly, 0.f);

    y[i]  = yi;
    vx[i] = vxi;
    vy[i] = vyi;
}

// 1D velocity profile bins in y (for Couette viscosity check)
__global__ void profile_y_sums_kernel(
    const float* __restrict__ y,
    const float* __restrict__ vx,
    int n,
    float Ly,
    int nBins,
    int* __restrict__ cnt,
    float* __restrict__ sumUx)
{
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= n) return;

    int iy = (int)floorf(y[i] / Ly * (float)nBins);
    if (iy < 0) iy = 0;
    if (iy >= nBins) iy = nBins - 1;
    atomicAdd(&cnt[iy], 1);
    atomicAdd(&sumUx[iy], vx[i]);
}

// Compute cell id with random shift (same a0 used in x and y).
__global__ void compute_cell_ids_kernel(
    const float* __restrict__ x, const float* __restrict__ y,
    int* __restrict__ cid,
    int n,
    float Lx, float Ly,
    float a0, int Nx, int Ny,
    float shiftx, float shifty)
{
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= n) return;

    float xs = x[i] + shiftx;
    float ys = y[i] + shifty;
    xs = wrap_periodic(xs, Lx);
    ys = wrap_periodic(ys, Ly);

    int ix = (int)floorf(xs / a0);
    int iy = (int)floorf(ys / a0);

    if (ix < 0) ix = 0; if (ix >= Nx) ix = Nx - 1;
    if (iy < 0) iy = 0; if (iy >= Ny) iy = Ny - 1;

    cid[i] = ix + iy * Nx; // 0-based linear id (Nx-major, matches MATLAB sub2ind([Nx,Ny],ix,iy))
}


// Compute cell id with random shift, but CLAMP y (used with solid y-walls, e.g. Couette).
__global__ void compute_cell_ids_kernel_couette(
    const float* __restrict__ x, const float* __restrict__ y,
    int* __restrict__ cid,
    int n,
    float Lx, float Ly,
    float a0, int Nx, int Ny,
    float shiftx, float shifty)
{
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= n) return;

    float xs = x[i] + shiftx;
    xs = wrap_periodic(xs, Lx);

    float ys = y[i] + shifty;
    // clamp to [0,Ly)
    if (ys < 0.f) ys = 0.f;
    if (ys >= Ly) ys = nextafterf(Ly, 0.f);

    int ix = (int)floorf(xs / a0);
    int iy = (int)floorf(ys / a0);

    if (ix < 0) ix = 0; if (ix >= Nx) ix = Nx - 1;
    if (iy < 0) iy = 0; if (iy >= Ny) iy = Ny - 1;

    cid[i] = ix + iy * Nx;
}

// Per-cell sums (mass-aware): count, total mass, and momentum sums.
// If useSpeciesMass=0, masses are effectively 1 and this reduces to the legacy behavior.
__global__ void cell_sums_mass_kernel(
    const float* __restrict__ vx, const float* __restrict__ vy,
    const unsigned char* __restrict__ tag,
    const int* __restrict__ cid,
    int n,
    int Nc,
    int useSpeciesMass,
    float m1, float m2,
    int* __restrict__ cnt,
    float* __restrict__ sumM,
    float* __restrict__ sumPx,
    float* __restrict__ sumPy,
    float* __restrict__ sumColorM)
{
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= n) return;
    int c = cid[i];
    if ((unsigned)c >= (unsigned)Nc) return;

    unsigned char s = (tag ? tag[i] : (unsigned char)0);
    float mi = species_mass_from_tag(s, useSpeciesMass, m1, m2);

    atomicAdd(&cnt[c], 1);
    atomicAdd(&sumM[c], mi);
    atomicAdd(&sumPx[c], mi * vx[i]);
    atomicAdd(&sumPy[c], mi * vy[i]);
    if (sumColorM) {
        float sgn = (s == (unsigned char)0) ? -1.f : 1.f; // fluid1=-1, fluid2=+1
        atomicAdd(&sumColorM[c], sgn * mi);
    }
}

// Compute per-cell barycentric (mass-weighted) velocity and rotation cos/sin.
// If useSpeciesMass=0, sumM equals cnt and this matches the legacy mean velocity.
__global__ void cell_params_kernel(
    const int* __restrict__ cnt,
    const float* __restrict__ sumM,
    const float* __restrict__ sumPx,
    const float* __restrict__ sumPy,
    int Nc,
    float* __restrict__ ux,
    float* __restrict__ uy,
    float* __restrict__ ctheta,
    float* __restrict__ stheta,
    float alpha,
    uint32_t seed,
    uint32_t step)
{
    int c = blockIdx.x * blockDim.x + threadIdx.x;
    if (c >= Nc) return;

    int k = cnt[c];
    float Mc = sumM[c];
    float invM = (Mc > 0.f) ? (1.0f / Mc) : 0.f;
    float uxc = sumPx[c] * invM;
    float uyc = sumPy[c] * invM;
    ux[c] = uxc;
    uy[c] = uyc;

    float th = 0.f;
    if (k >= 2) {
        uint32_t h = wang_hash(seed ^ (uint32_t)c ^ (uint32_t)(step * 2654435761u));
        float sgn = (h & 1u) ? 1.f : -1.f;
        th = alpha * sgn;
    }
    ctheta[c] = cosf(th);
    stheta[c] = sinf(th);
}



__device__ __forceinline__ float phi_from_cell_color(
    int jx, int jy, int Nx, int Ny, int periodicY,
    const int* __restrict__ cnt,
    const float* __restrict__ sumM,
    const float* __restrict__ sumColorM)
{
    if (jx < 0) jx += Nx;
    if (jx >= Nx) jx -= Nx;
    if (periodicY) {
        if (jy < 0) jy += Ny;
        if (jy >= Ny) jy -= Ny;
    } else {
        if (jy < 0) jy = 0;
        if (jy >= Ny) jy = Ny - 1;
    }
    int cc = jx + jy * Nx;
    if (!sumM || !sumColorM) return 0.f;
    if (cnt && cnt[cc] <= 0) return 0.f;
    float M = sumM[cc];
    return (M > 1e-20f) ? (sumColorM[cc] / M) : 0.f;
}

// Build a per-cell color normal n = grad(phi)/|grad(phi)| from mass-weighted color field
// phi = (M2 - M1) / (M1 + M2) = sumColorM / sumM in [-1,1].
// x-neighbors are periodic; y-neighbors are periodic or clamped depending on periodicY.
__global__ void cell_color_normals_kernel(
    const int* __restrict__ cnt,
    const float* __restrict__ sumM,
    const float* __restrict__ sumColorM,
    int Nx, int Ny,
    int periodicY,
    float gradMin,
    float* __restrict__ nxColor,
    float* __restrict__ nyColor)
{
    int c = blockIdx.x * blockDim.x + threadIdx.x;
    int Nc = Nx * Ny;
    if (c >= Nc) return;

    int ix = c % Nx;
    int iy = c / Nx;

    float phiL = phi_from_cell_color(ix - 1, iy, Nx, Ny, periodicY, cnt, sumM, sumColorM);
    float phiR = phi_from_cell_color(ix + 1, iy, Nx, Ny, periodicY, cnt, sumM, sumColorM);
    float phiD = phi_from_cell_color(ix, iy - 1, Nx, Ny, periodicY, cnt, sumM, sumColorM);
    float phiU = phi_from_cell_color(ix, iy + 1, Nx, Ny, periodicY, cnt, sumM, sumColorM);

    float gx = 0.5f * (phiR - phiL);
    float gy = 0.5f * (phiU - phiD);
    float gm = sqrtf(gx*gx + gy*gy);

    if (gm > fmaxf(gradMin, 0.f)) {
        float inv = 1.f / gm;
        nxColor[c] = gx * inv;
        nyColor[c] = gy * inv;
    } else {
        nxColor[c] = 0.f;
        nyColor[c] = 0.f;
    }
}



__device__ __forceinline__ int cell_index_bc(int jx, int jy, int Nx, int Ny, int periodicY)
{
    if (jx < 0) jx += Nx;
    if (jx >= Nx) jx -= Nx;
    if (periodicY) {
        if (jy < 0) jy += Ny;
        if (jy >= Ny) jy -= Ny;
    } else {
        if (jy < 0) jy = 0;
        if (jy >= Ny) jy = Ny - 1;
    }
    return jx + jy * Nx;
}

// Phase M2: compute a surface-tension-like cell acceleration from color field.
// Continuum-surface-force inspired form (dimensionless / tunable):
//   a ~ sigmaLike * kappa * grad(phi) / rho
// where phi=(M2-M1)/(M1+M2), n = grad(phi)/|grad(phi)|, kappa = -div(n).
// Notes:
// - Discrete derivatives are taken in cell units (not physical dx); sigmaLike is therefore
//   an effective parameter to calibrate empirically.
// - We threshold weak gradients to avoid amplifying color noise in homogeneous regions.
__global__ void cell_capillary_accel_kernel(
    const int* __restrict__ cnt,
    const float* __restrict__ sumM,
    const float* __restrict__ sumColorM,
    const float* __restrict__ nxColor,
    const float* __restrict__ nyColor,
    int Nx, int Ny,
    int periodicY,
    float a0,
    float sigmaLike,
    float gradMin,
    float kappaClip,
    float* __restrict__ axCell,
    float* __restrict__ ayCell)
{
    int c = blockIdx.x * blockDim.x + threadIdx.x;
    int Nc = Nx * Ny;
    if (c >= Nc) return;

    int ix = c % Nx;
    int iy = c / Nx;

    // Default: no capillary acceleration.
    axCell[c] = 0.f;
    ayCell[c] = 0.f;

    if (!sumM || !sumColorM || !nxColor || !nyColor || sigmaLike == 0.f) return;
    if (cnt && cnt[c] <= 0) return;

    float Mc = sumM[c];
    if (Mc <= 1e-20f) return;

    // grad(phi) at current cell (cell-index units)
    float phiL = phi_from_cell_color(ix - 1, iy, Nx, Ny, periodicY, cnt, sumM, sumColorM);
    float phiR = phi_from_cell_color(ix + 1, iy, Nx, Ny, periodicY, cnt, sumM, sumColorM);
    float phiD = phi_from_cell_color(ix, iy - 1, Nx, Ny, periodicY, cnt, sumM, sumColorM);
    float phiU = phi_from_cell_color(ix, iy + 1, Nx, Ny, periodicY, cnt, sumM, sumColorM);
    float gx = 0.5f * (phiR - phiL);
    float gy = 0.5f * (phiU - phiD);
    float gm = sqrtf(gx*gx + gy*gy);
    if (gm <= fmaxf(gradMin, 0.f)) return;

    // Curvature from divergence of unit normal.
    int cL = cell_index_bc(ix - 1, iy, Nx, Ny, periodicY);
    int cR = cell_index_bc(ix + 1, iy, Nx, Ny, periodicY);
    int cD = cell_index_bc(ix, iy - 1, Nx, Ny, periodicY);
    int cU = cell_index_bc(ix, iy + 1, Nx, Ny, periodicY);

    float divn = 0.5f * (nxColor[cR] - nxColor[cL]) + 0.5f * (nyColor[cU] - nyColor[cD]);
    float kappa = -divn;
    if (kappaClip > 0.f) {
        kappa = fmaxf(-kappaClip, fminf(kappa, kappaClip));
    }

    // Convert force density to acceleration using rho ~ M/a0^2.
    // a = (sigmaLike * kappa * grad(phi)) / rho = sigmaLike * kappa * grad(phi) * a0^2 / M
    // NOTE: gx,gy and kappa are computed in cell units; physical CSF scaling cancels a0 factors.
    float invRhoFactor = 1.f / fmaxf(Mc, 1e-20f);
    float pref = sigmaLike * kappa * invRhoFactor;
    axCell[c] = pref * gx;
    ayCell[c] = pref * gy;
}

__global__ void apply_cell_accel_kernel(
    float* __restrict__ vx,
    float* __restrict__ vy,
    const int* __restrict__ cid,
    const float* __restrict__ axCell,
    const float* __restrict__ ayCell,
    int n,
    int Nc,
    float dt)
{
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= n) return;
    int c = cid[i];
    if ((unsigned)c >= (unsigned)Nc) return;
    if (!axCell || !ayCell) return;
    vx[i] += dt * axCell[c];
    vy[i] += dt * ayCell[c];
}

// External body acceleration + optional species-dependent wall-wetting acceleration (distance-decaying).
// Convention for wallWetF{1,2}: positive => attraction toward enabled wall(s).
// Bottom wall attraction adds negative y-acceleration; top wall attraction adds positive y-acceleration.
__global__ void apply_body_wetting_kick_kernel(
    float* __restrict__ vx,
    float* __restrict__ vy,
    const float* __restrict__ y,
    const unsigned char* __restrict__ tag,
    int n,
    float Ly,
    float dt,
    float axUniform,
    float ayUniform,
    int useSpeciesTag,
    int wetBottom,
    int wetTop,
    float wetRange,
    float wetCutoff,
    float wallWetF1,
    float wallWetF2)
{
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= n) return;

    float dvx = dt * axUniform;
    float dvy = dt * ayUniform;

    bool useWet = (wetRange > 0.f) && (wetBottom || wetTop) &&
                  (wallWetF1 != 0.f || wallWetF2 != 0.f);
    if (useWet) {
        float yi = y[i];
        unsigned char sp = (useSpeciesTag && tag) ? tag[i] : (unsigned char)0;
        float Fw = (sp == (unsigned char)0) ? wallWetF1 : wallWetF2; // acceleration scale
        if (Fw != 0.f) {
            float invL = 1.f / fmaxf(wetRange, 1e-12f);
            float cut = (wetCutoff > 0.f) ? wetCutoff : (4.f * wetRange);

            if (wetBottom) {
                float d = yi; // distance to y=0 wall
                if (d < cut) dvy += dt * (-Fw) * expf(-d * invL);
            }
            if (wetTop) {
                float d = Ly - yi; // distance to y=Ly wall
                if (d < cut) dvy += dt * (+Fw) * expf(-d * invL);
            }
        }
    }

    vx[i] += dvx;
    vy[i] += dvy;
}

// Pass A: compute rotated relative velocities and accumulate sumRel2 per cell.
// Store rotated relatives to temp arrays to avoid recomputation.
__global__ void rel_rotate_and_sum_kernel(
    const float* __restrict__ vx,
    const float* __restrict__ vy,
    const unsigned char* __restrict__ tag,
    const int* __restrict__ cid,
    const float* __restrict__ ux,
    const float* __restrict__ uy,
    const float* __restrict__ ctheta,
    const float* __restrict__ stheta,
    const float* __restrict__ sumM_cell,
    const float* __restrict__ sumColorM_cell,
    const float* __restrict__ nxColor,
    const float* __restrict__ nyColor,
    int useImmiscible,
    float chiColor,
    int n,
    int Nc,
    int useSpeciesMass,
    float m1, float m2,
    float* __restrict__ vxrel_rot,
    float* __restrict__ vyrel_rot,
    float* __restrict__ sumRel2)
{
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= n) return;
    int c = cid[i];
    if ((unsigned)c >= (unsigned)Nc) return;

    float vxr = vx[i] - ux[c];
    float vyr = vy[i] - uy[c];
    float ci = ctheta[c];
    float si = stheta[c];
    float vx2 =  ci * vxr - si * vyr;
    float vy2 =  si * vxr + ci * vyr;

    unsigned char s = (tag ? tag[i] : (unsigned char)0);

    // Phase M1: weak color-gradient demixing bias (momentum-conservative at cell level)
    // delta v_rel = chiColor * (s_i - <s>_m) * n_color, with s_i in {-1,+1}, <s>_m = phi.
    if (useImmiscible && tag && nxColor && nyColor && sumM_cell && sumColorM_cell && chiColor != 0.f) {
        float ncx = nxColor[c];
        float ncy = nyColor[c];
        if (ncx != 0.f || ncy != 0.f) {
            float Mc = sumM_cell[c];
            if (Mc > 1e-20f) {
                float phi = sumColorM_cell[c] / Mc; // in [-1,1]
                float si_col = (s == (unsigned char)0) ? -1.f : 1.f;
                float coeff = chiColor * (si_col - phi);
                vx2 += coeff * ncx;
                vy2 += coeff * ncy;
            }
        }
    }

    vxrel_rot[i] = vx2;
    vyrel_rot[i] = vy2;

    float mi = species_mass_from_tag(s, useSpeciesMass, m1, m2);
    float rel2 = vx2 * vx2 + vy2 * vy2;
    atomicAdd(&sumRel2[c], mi * rel2);
}

// Compute lambda per cell for thermostat (or 1 if disabled / cnt<=1)
__global__ void thermostat_lambda_kernel(
    const int* __restrict__ cnt,
    const float* __restrict__ sumRel2,
    int Nc,
    float kBT,
    int useThermostat,
    float* __restrict__ lambda)
{
    int c = blockIdx.x * blockDim.x + threadIdx.x;
    if (c >= Nc) return;

    int k = cnt[c];
    float lam = 1.f;
    if (useThermostat && k > 1) {
        float dof = 2.f * (float)(k - 1);
        float target = dof * kBT;
        float s = sumRel2[c];
        if (s > 0.f) lam = sqrtf(target / s);
    }
    lambda[c] = lam;
}

// Pass B: apply collision result: v = u + lambda * vrel_rot
__global__ void apply_collision_kernel(
    float* __restrict__ vx,
    float* __restrict__ vy,
    const int* __restrict__ cid,
    const float* __restrict__ ux,
    const float* __restrict__ uy,
    const float* __restrict__ lambda,
    const float* __restrict__ vxrel_rot,
    const float* __restrict__ vyrel_rot,
    int n,
    int Nc)
{
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= n) return;
    int c = cid[i];
    if ((unsigned)c >= (unsigned)Nc) return;
    float lam = lambda[c];
    vx[i] = ux[c] + lam * vxrel_rot[i];
    vy[i] = uy[c] + lam * vyrel_rot[i];
}

// Simple reduction kernels for sums (vx, vy, energy). We do block reductions and finish on host.
__global__ void reduce_sum_kernel(const float* __restrict__ a, double* __restrict__ partial, int n) {
    extern __shared__ double sdata[];
    int tid = threadIdx.x;
    int i = blockIdx.x * blockDim.x + tid;
    double x = 0.0;
    if (i < n) x = (double)a[i];
    sdata[tid] = x;
    __syncthreads();
    for (int s = blockDim.x / 2; s > 0; s >>= 1) {
        if (tid < s) sdata[tid] += sdata[tid + s];
        __syncthreads();
    }
    if (tid == 0) partial[blockIdx.x] = sdata[0];
}

__global__ void reduce_energy_kernel(const float* __restrict__ vx, const float* __restrict__ vy, double* __restrict__ partial, int n) {
    extern __shared__ double sdata[];
    int tid = threadIdx.x;
    int i = blockIdx.x * blockDim.x + tid;
    double e = 0.0;
    if (i < n) {
        double ux = (double)vx[i];
        double uy = (double)vy[i];
        e = 0.5 * (ux*ux + uy*uy);
    }
    sdata[tid] = e;
    __syncthreads();
    for (int s = blockDim.x / 2; s > 0; s >>= 1) {
        if (tid < s) sdata[tid] += sdata[tid + s];
        __syncthreads();
    }
    if (tid == 0) partial[blockIdx.x] = sdata[0];
}

__global__ void add_constants_kernel(float* __restrict__ vx, float* __restrict__ vy, int n, float addx, float addy) {
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= n) return;
    vx[i] += addx;
    vy[i] += addy;
}

// Field accumulation (no random shift): sums and counts on (NxF,NyF) grid
__global__ void field_sums_kernel(
    const float* __restrict__ x, const float* __restrict__ y,
    const float* __restrict__ vx, const float* __restrict__ vy,
    int n,
    float Lx, float Ly,
    int NxF, int NyF,
    int* __restrict__ cnt,
    float* __restrict__ sumUx,
    float* __restrict__ sumUy)
{
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= n) return;

    int ix = (int)floorf(x[i] / Lx * (float)NxF);
    int iy = (int)floorf(y[i] / Ly * (float)NyF);
    if (ix < 0) ix = 0; if (ix >= NxF) ix = NxF - 1;
    if (iy < 0) iy = 0; if (iy >= NyF) iy = NyF - 1;
    int c = ix + iy * NxF;
    atomicAdd(&cnt[c], 1);
    atomicAdd(&sumUx[c], vx[i]);
    atomicAdd(&sumUy[c], vy[i]);
}

// Field accumulation for tracer/species label (same spatial binning as field_sums_kernel).
// tag=0 -> fluid 1 (lower inlet), tag=1 -> fluid 2 (upper inlet).
__global__ void tracer_field_counts_kernel(
    const float* __restrict__ x, const float* __restrict__ y,
    const unsigned char* __restrict__ tag,
    int n,
    float Lx, float Ly,
    int NxF, int NyF,
    int* __restrict__ cntF1,
    int* __restrict__ cntF2)
{
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= n) return;

    int ix = (int)floorf(x[i] / Lx * (float)NxF);
    int iy = (int)floorf(y[i] / Ly * (float)NyF);
    if (ix < 0) ix = 0; if (ix >= NxF) ix = NxF - 1;
    if (iy < 0) iy = 0; if (iy >= NyF) iy = NyF - 1;
    int c = ix + iy * NxF;

    unsigned char s = tag ? tag[i] : 0;
    if (s == 0) atomicAdd(&cntF1[c], 1);
    else        atomicAdd(&cntF2[c], 1);
}


// ----------------------- Optional GPU visualization kernels -----------------------
// These kernels build a reduced Eulerian visualization grid directly from particles
// (local averaging, not simple decimation), then optionally smooth and color-map it.

__global__ void vis_accumulate_particles_kernel(
    const float* __restrict__ x, const float* __restrict__ y,
    const float* __restrict__ vx, const float* __restrict__ vy,
    int n, float Lx, float Ly, int NxV, int NyV,
    int* __restrict__ cnt, float* __restrict__ sumUx, float* __restrict__ sumUy)
{
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= n) return;

    int ix = (int)floorf(x[i] / Lx * (float)NxV);
    int iy = (int)floorf(y[i] / Ly * (float)NyV);
    if (ix < 0) ix = 0; if (ix >= NxV) ix = NxV - 1;
    if (iy < 0) iy = 0; if (iy >= NyV) iy = NyV - 1;
    int c = ix + iy * NxV;
    atomicAdd(&cnt[c], 1);
    atomicAdd(&sumUx[c], vx[i]);
    atomicAdd(&sumUy[c], vy[i]);
}


__global__ void vis_accumulate_tracer_kernel(
    const float* __restrict__ x, const float* __restrict__ y,
    const unsigned char* __restrict__ tag,
    int n, float Lx, float Ly, int NxV, int NyV,
    float* __restrict__ sumTag)
{
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= n) return;

    int ix = (int)floorf(x[i] / Lx * (float)NxV);
    int iy = (int)floorf(y[i] / Ly * (float)NyV);
    if (ix < 0) ix = 0; if (ix >= NxV) ix = NxV - 1;
    if (iy < 0) iy = 0; if (iy >= NyV) iy = NyV - 1;
    int c = ix + iy * NxV;

    unsigned char s = tag ? tag[i] : 0; // 0 -> fluid1, 1 -> fluid2
    atomicAdd(&sumTag[c], (float)(s != 0));
}

__global__ void vis_scalar_from_tracer_kernel(
    const int* __restrict__ cnt,
    const float* __restrict__ sumTag,
    int N,
    float* __restrict__ scalar)
{
    int c = blockIdx.x * blockDim.x + threadIdx.x;
    if (c >= N) return;

    int k = cnt[c];
    if (k <= 0) {
        scalar[c] = 0.f;
        return;
    }

    // tag=0 -> fluid1, tag=1 -> fluid2
    // c_signed = 2*c_f1 - 1 = 1 - 2*c_f2, in [-1,1]
    float cf2 = sumTag[c] / (float)k;
    scalar[c] = 1.f - 2.f * cf2;
}

__global__ void vis_smooth_scalar_box3_weighted_kernel(
    const float* __restrict__ inS,
    const int* __restrict__ cnt,
    int NxV, int NyV,
    int periodicY,
    float* __restrict__ outS)
{
    int c = blockIdx.x * blockDim.x + threadIdx.x;
    int N = NxV * NyV;
    if (c >= N) return;

    int ix = c % NxV;
    int iy = c / NxV;

    float ss = 0.f, sw = 0.f;
    for (int dj = -1; dj <= 1; ++dj) {
        int jy = iy + dj;
        if (periodicY) jy = (jy % NyV + NyV) % NyV;
        else {
            if (jy < 0) jy = 0;
            if (jy >= NyV) jy = NyV - 1;
        }
        for (int di = -1; di <= 1; ++di) {
            int jx = ix + di;
            if (jx < 0) jx = 0;
            if (jx >= NxV) jx = NxV - 1;
            int cc = jx + jy * NxV;
            float w = (float)max(cnt[cc], 0);
            if (w <= 0.f) continue;
            ss += w * inS[cc];
            sw += w;
        }
    }

    outS[c] = (sw > 0.f) ? (ss / sw) : 0.f;
}

__global__ void vis_normalize_kernel(
    const int* __restrict__ cnt,
    const float* __restrict__ sumUx,
    const float* __restrict__ sumUy,
    int N,
    float* __restrict__ ux,
    float* __restrict__ uy)
{
    int c = blockIdx.x * blockDim.x + threadIdx.x;
    if (c >= N) return;
    int k = cnt[c];
    if (k > 0) {
        float inv = 1.f / (float)k;
        ux[c] = sumUx[c] * inv;
        uy[c] = sumUy[c] * inv;
    } else {
        ux[c] = 0.f;
        uy[c] = 0.f;
    }
}

// Box smoothing weighted by local particle counts (coarse display grid only).
// periodicY=1 (VK); periodicY=0 (Couette). x is clamped (works for inlet/outlet too).
__global__ void vis_smooth_box3_weighted_kernel(
    const float* __restrict__ inUx,
    const float* __restrict__ inUy,
    const int* __restrict__ cnt,
    int NxV, int NyV,
    int periodicY,
    float* __restrict__ outUx,
    float* __restrict__ outUy)
{
    int c = blockIdx.x * blockDim.x + threadIdx.x;
    int N = NxV * NyV;
    if (c >= N) return;

    int ix = c % NxV;
    int iy = c / NxV;

    float sux = 0.f, suy = 0.f, sw = 0.f;
    for (int dj = -1; dj <= 1; ++dj) {
        int jy = iy + dj;
        if (periodicY) {
            jy = (jy % NyV + NyV) % NyV;
        } else {
            if (jy < 0) jy = 0;
            if (jy >= NyV) jy = NyV - 1;
        }
        for (int di = -1; di <= 1; ++di) {
            int jx = ix + di;
            if (jx < 0) jx = 0;
            if (jx >= NxV) jx = NxV - 1;
            int cc = jx + jy * NxV;
            float w = (float)max(cnt[cc], 0);
            if (w <= 0.f) continue;
            sux += w * inUx[cc];
            suy += w * inUy[cc];
            sw  += w;
        }
    }

    if (sw > 0.f) {
        outUx[c] = sux / sw;
        outUy[c] = suy / sw;
    } else {
        outUx[c] = 0.f;
        outUy[c] = 0.f;
    }
}

__global__ void vis_scalar_from_velocity_kernel(
    const float* __restrict__ ux,
    const float* __restrict__ uy,
    const int* __restrict__ cnt,
    int NxV, int NyV,
    float Lx, float Ly,
    int periodicY,
    int fieldMode,                 // 0=omega, 1=speed, 2=ux, 3=uy, 4=tracer(c_signed)
    float* __restrict__ scalar)
{
    int c = blockIdx.x * blockDim.x + threadIdx.x;
    int N = NxV * NyV;
    if (c >= N) return;

    int ix = c % NxV;
    int iy = c / NxV;

    if (cnt[c] <= 0) {
        scalar[c] = 0.f;
        return;
    }

    if (fieldMode == 1) { // speed
        float u = ux[c], v = uy[c];
        scalar[c] = sqrtf(u*u + v*v);
        return;
    }
    if (fieldMode == 2) { scalar[c] = ux[c]; return; }
    if (fieldMode == 3) { scalar[c] = uy[c]; return; }

    // omega_z = dUy/dx - dUx/dy
    int ixm = max(ix - 1, 0), ixp = min(ix + 1, NxV - 1);
    int iym = iy - 1, iyp = iy + 1;
    if (periodicY) {
        iym = (iym % NyV + NyV) % NyV;
        iyp = (iyp % NyV + NyV) % NyV;
    } else {
        if (iym < 0) iym = 0;
        if (iyp >= NyV) iyp = NyV - 1;
    }

    float dx = Lx / (float)NxV;
    float dy = Ly / (float)NyV;

    float Uy_mx = uy[ixm + iy  * NxV];
    float Uy_px = uy[ixp + iy  * NxV];
    float Ux_my = ux[ix  + iym * NxV];
    float Ux_py = ux[ix  + iyp * NxV];

    float dUydx;
    if (ix == 0) dUydx = (Uy_px - uy[c]) / dx;
    else if (ix == NxV - 1) dUydx = (uy[c] - Uy_mx) / dx;
    else dUydx = (Uy_px - Uy_mx) / (2.f * dx);

    float dUxdy;
    if (!periodicY && iy == 0) dUxdy = (Ux_py - ux[c]) / dy;
    else if (!periodicY && iy == NyV - 1) dUxdy = (ux[c] - Ux_my) / dy;
    else dUxdy = (Ux_py - Ux_my) / (2.f * dy);

    scalar[c] = dUydx - dUxdy;
}

__global__ void vis_temporal_blend_kernel(
    float* __restrict__ accum,       // in/out
    const float* __restrict__ instant,
    int N, float alpha)
{
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= N) return;
    accum[i] = (1.f - alpha) * accum[i] + alpha * instant[i];
}

__device__ static inline unsigned char vis_u8(float x) {
    x = fminf(fmaxf(x, 0.f), 255.f);
    return (unsigned char)(x + 0.5f);
}

__global__ void vis_colormap_kernel(
    const float* __restrict__ scalar,
    const int* __restrict__ cnt,
    int NxV, int NyV,
    int fieldMode,
    float clip,
    float xc, float yc, float Rc, int maskCylinder,
    float Lx, float Ly,
    uchar4* __restrict__ rgba)
{
    int c = blockIdx.x * blockDim.x + threadIdx.x;
    int N = NxV * NyV;
    if (c >= N) return;

    int ix = c % NxV;
    int iy = c / NxV;
    float x = ((float)ix + 0.5f) * (Lx / (float)NxV);
    float y = ((float)iy + 0.5f) * (Ly / (float)NyV);

    if (maskCylinder) {
        float dx = x - xc, dy = y - yc;
        if (dx*dx + dy*dy <= Rc*Rc) {
            rgba[c] = make_uchar4(0, 0, 0, 255);
            return;
        }
    }

    if (cnt[c] <= 0) {
        rgba[c] = make_uchar4(12, 12, 12, 255);
        return;
    }

    float s = scalar[c];
    float c0 = fmaxf(clip, 1e-12f);

    if (fieldMode == 1) {
        // speed: sequential dark->cyan->yellow-ish
        float t = fminf(fmaxf(s / c0, 0.f), 1.f);
        float r = (t < 0.5f) ? (0.2f * (t/0.5f)) : (0.2f + 0.8f*((t-0.5f)/0.5f));
        float g = (t < 0.5f) ? (0.4f + 0.6f*(t/0.5f)) : 1.0f;
        float b = (t < 0.5f) ? (0.7f + 0.3f*(t/0.5f)) : (1.0f - 0.85f*((t-0.5f)/0.5f));
        rgba[c] = make_uchar4(vis_u8(255.f*r), vis_u8(255.f*g), vis_u8(255.f*b), 255);
        return;
    }

    // signed fields: blue-white-red diverging
    float t = fminf(fmaxf(s / c0, -1.f), 1.f);
    float a = fabsf(t);
    float r, g, b;
    if (t >= 0.f) { // white -> red
        r = 1.f;
        g = 1.f - 0.9f * a;
        b = 1.f - 0.9f * a;
    } else {        // blue -> white
        r = 1.f - 0.9f * a;
        g = 1.f - 0.9f * a;
        b = 1.f;
    }
    // slightly darken low magnitude to improve contrast
    float gain = 0.25f + 0.75f * a;
    rgba[c] = make_uchar4(vis_u8(255.f*r*gain), vis_u8(255.f*g*gain), vis_u8(255.f*b*gain), 255);
}

// ----------------------- Host utilities -----------------------
struct Params {
    float Lx = 1.5f, Ly = 0.4f;
    int Nx = 360, Ny = 19; //1200 et 640
    float gamma = 20.f; //6
    float dt = 5e-4f;
    int nSteps = 100000;
    float alphaDeg = 90.f;
    float U0 = 0.051f; //0.9
    float kBT = 5.f;
    int useThermostat = 1;
    int keepMeanFlow = 1;

    // x-boundary for VK mode:
    // 0 = periodic wrap (legacy), 1 = open outflow + clean inflow reinjection at x~0
    int xInletInject = 1;
    int reinjectBackflow = 0;   // also re-inject particles that cross x<0
    int injectRandomY = 1;      // randomize y on injection to keep inlet density homogeneous

    // Two-fluid mode (species tag)
    // tag=0: fluid 1 (lower half), tag=1: fluid 2 (upper half)
    int twoFluidTracer = 0;
    float tracerSplitY = -1.f;     // <0 => default Ly/2

    // Phase 1: mass-aware bi-species MPCD (same collision law, different particle masses)
    // Enabled only if useSpeciesMass=1. If twoFluidTracer=0, all particles use m1.
    int useSpeciesMass = 0;
    float m1 = 1.f;
    float m2 = 2.f;

    // Phase M1: weak immiscibility / demixing via color-gradient bias in SRD collision
    // (conservative in cell momentum; thermostat handles kinetic rescaling afterwards)
    int immiscible = 0;          // 0=miscible (default), 1=enable color-gradient demixing
    float chiColor = 0.f;        // demixing strength (velocity bias in collision space)
    float chiGrad0 = 0.02f;      // minimum |grad(phi)| (cell units) to apply demixing

    // Phase M2: surface-tension-like capillary acceleration from color curvature (CSF-inspired)
    // This is an effective model (sigmaLike is not yet physically calibrated).
    int capillaryM2 = 0;         // 0=off, 1=apply capillary-like acceleration from color interface
    float sigmaLike = 0.f;       // capillary strength (effective, to calibrate)
    float sigmaGrad0 = 0.02f;    // minimum |grad(phi)| to apply capillary force
    float sigmaKappaMax = 2.f;   // clamp on discrete curvature |kappa| in cell units (<=0 disables)

    // Drop-capillary calibration preset / diagnostics (built on KH round-jet init used as a static droplet)
    int calibDrop = 0;            // 1 => preset a static droplet calibration case (mode=kh, khJet=1, khU=0, periodic x/y)
    float dropEllipse = 0.f;        // optional ellipticity for droplet init (0=circle). For sigma calibration, try 0.05-0.15.
    int dropDiagStride = 0;       // <=0 => use dumpStride; diagnostics written to dropcal_diag.csv when calibDrop=1
    float dropIsoC2 = 0.5f;       // droplet indicator threshold on count fraction c_f2
    float dropInFrac = 0.6f;      // p_in average over r < dropInFrac * Req
    float dropOutR1Frac = 1.6f;   // p_out average over dropOutR1Frac * Req < r < dropOutR2Frac * Req
    float dropOutR2Frac = 2.2f;

    // Sessile-drop-on-wall preset (built on KH round-droplet initializer + y walls)
    // Introduces gravity and a simple distance-decaying species-dependent wall force (wetting proxy).
    int dropWall = 0;              // 1 => preset a wall-bounded droplet settling case (internally uses mode=kh + khJet + khWallY)
    float gravX = 0.f;             // uniform body acceleration (x)
    float gravY = 0.f;             // uniform body acceleration (y); negative pulls toward y=0 bottom wall
    int wallWetBottom = 0;         // enable wetting force from y=0 wall
    int wallWetTop = 0;            // enable wetting force from y=Ly wall
    float wallWetRange = -1.f;     // decay length lambda (<=0 => default ~ few cells)
    float wallWetCut = -1.f;       // cutoff distance for wetting force (<=0 => 4*lambda)
    float wallWetF1 = 0.f;         // wetting acceleration scale for species-1 (positive => attraction to enabled wall)
    float wallWetF2 = 0.f;         // wetting acceleration scale for species-2 (positive => attraction to enabled wall)

    // Mode: 'vk' (cylinder wake), 'kh' (Kelvin-Helmholtz shear layer), or 'couette' (viscosity calibration)
    std::string mode = "vk";

    // Phase 2 (KH): variable-density KH-like initialization (miscible, bi-species via tags+masses)
    // Default geometry (khJet=0): planar shear layer
    //   ux(y) = khU * tanh((y-khY0)/khDeltaU)
    //   vy(x,y) perturbation = khEpsVy * sin(kx*x + phase) * exp(-0.5*((y-khY0)/khSigmaY)^2)
    //   species-1 probability p1(y) = 0.5*(1 - tanh((y-khY0)/khDeltaRho))
    // Optional geometry (khJet=1): central round jet of species-2 in species-1 ambient
    //   S(r)=0.5*(1-tanh((r-Rj)/khDeltaU)), ux~khU*S(r), composition transition via khDeltaRho
    //   vy perturbation remains sinusoidal in x, localized near the annular interface r~Rj
    // Defaults: khY0=Ly/2, khU=U0, khDeltaU~2a0, khDeltaRho=khDeltaU, khKx=2pi/Lx
    float khY0 = -1.f;
    float khDeltaU = -1.f;
    float khDeltaRho = -1.f;
    float khU = -1.f;
    float khEpsVy = 0.02f;
    float khKx = -1.f;
    float khSigmaY = -1.f;
    float khPhase = 0.f;
    int   khJet = 0;           // 0=planar shear layer, 1=central round jet (still mode=kh)
    int   khInletJet = 0;      // 1=x-open source jet at inlet (band in y), periodic in y only
    int   khWallY = 0;         // KH only: 0=periodic y (default), 1=no-slip walls at y=0,Ly
    float khJetD = -1.f;       // jet diameter; default min(Lx,Ly)/4
    float khJetX0 = -1.f;      // jet center x; default Lx/2
    float khJetY0 = -1.f;      // jet center y; default Ly/2

    float couetteU = 0.2f;          // Utop-Ubot for Couette
    int viscStart = 2000;           // start averaging after this step (Couette)
    int viscReportStride = 1000;    // report interval (Couette)
    int viscBins = 64;              // bins for velocity profile (Couette)
    int viscProfile = 1;            // compute and write profile (Couette)

    // Bounce-back cylinder parameters (used when --solid 0)
    float bbEn = 1.f;               // normal restitution (1=elastic)
    float bbEt = -1.f;              // tangential factor (-1=no-slip bounce-back, +1=specular)

    // Cylinder
    float xc = 0.25f;
    float yc = 0.2f+0.005f; // default updated after Ly parsing
    float Rc = 0.04f; // default updated after Ly parsing
    bool ycUserSet = false;
    bool RcUserSet = false;
    float epsWall = 1e-10f;

    int useSolidCylinderParticles = 1;
    float solidSpacingFactor = 0.7f; // spacing = factor * a0
    float solidDV = 0.10f;
    int solidRepulsionIters = 2;
    int solidUseRepulsion = 1;       // 1: soft repulsion from fixed wall particles
    int solidUseProject   = 1;       // 1: hard geometric exclusion/projection to Rc+epsWall
    float solidMaxDispFactor = 0.5f; // maxDisp = factor * Lr

    // Output
    int dumpStride = 5000000;
    std::string outDir = "vk3_Re300_C";
    int writeCSV = 1;
    int logStride = 10000;
    uint32_t rngSeed = 1u;

    // Minimal real-time visualization (optional, compile with -DUSE_GL_VIS)
    int visEnable = 1;           // 1 => open a minimal GLFW window and display coarse field
    int visStride = 5;          // update window every visStride iterations
    int visNx = 600;             // coarse display grid size (local averaging bins)
    int visNy = 160;
    int visSmoothPasses = 1;     // box3 smoothing passes on coarse grid
    int visField = 0;            // 0=omega, 1=speed, 2=ux, 3=uy, 4=tracer(c_signed)
    float visClip = -1.f;        // scalar clipping for colormap; <0 => auto heuristic
    float visAlpha = 0.30f;      // temporal smoothing alpha for display-only scalar
    int visWinScale = 1;         // window pixel scale = vis grid * scale
    int visVsync = 0;            // 0 recommended for low overhead

    // Field grid
    int NxF = -1, NyF = -1;
};

static inline bool starts_with(const std::string& s, const std::string& p) {
    return s.size() >= p.size() && std::equal(p.begin(), p.end(), s.begin());
}

static inline bool mode_is_couette(const Params& P) { return P.mode == "couette"; }
static inline bool mode_is_vk(const Params& P)      { return P.mode == "vk"; }
static inline bool mode_is_kh(const Params& P)      { return P.mode == "kh"; }
static inline bool mode_is_dropwall(const Params& P){ return P.dropWall != 0; }
static inline bool mode_has_cylinder(const Params& P){ return mode_is_vk(P); }
static inline bool mode_periodic_y(const Params& P) { return mode_is_vk(P) || (mode_is_kh(P) && !P.khWallY); }

static inline void parseArgs(int argc, char** argv, Params& P) {
    auto getf = [&](int& i)->float { return std::stof(argv[++i]); };
    auto geti = [&](int& i)->int { return std::stoi(argv[++i]); };
    for (int i=1;i<argc;i++){
        std::string a = argv[i];
        if (a=="--Lx") P.Lx = getf(i);
        else if (a=="--Ly") P.Ly = getf(i);
        else if (a=="--Nx") P.Nx = geti(i);
        else if (a=="--Ny") P.Ny = geti(i);
        else if (a=="--gamma") P.gamma = getf(i);
        else if (a=="--dt") P.dt = getf(i);
        else if (a=="--steps") P.nSteps = geti(i);
        else if (a=="--alphaDeg") P.alphaDeg = getf(i);
        else if (a=="--U0") P.U0 = getf(i);
        else if (a=="--kBT") P.kBT = getf(i);
        else if (a=="--thermostat") P.useThermostat = geti(i);
        else if (a=="--keepMeanFlow") P.keepMeanFlow = geti(i);
        else if (a=="--xInletInject") P.xInletInject = geti(i);
        else if (a=="--reinjectBackflow") P.reinjectBackflow = geti(i);
        else if (a=="--injectRandomY") P.injectRandomY = geti(i);
        else if (a=="--twoFluidTracer" || a=="--twoFluids" || a=="--tracer2") P.twoFluidTracer = geti(i);
        else if (a=="--tracerSplitY") P.tracerSplitY = getf(i);
        else if (a=="--useSpeciesMass" || a=="--speciesMass") P.useSpeciesMass = geti(i);
        else if (a=="--m1") P.m1 = getf(i);
        else if (a=="--m2") P.m2 = getf(i);
        else if (a=="--immiscible" || a=="--demix" || a=="--demixEnable") P.immiscible = geti(i);
        else if (a=="--chiColor" || a=="--demixStrength") P.chiColor = getf(i);
        else if (a=="--chiGrad0" || a=="--demixGradMin") P.chiGrad0 = getf(i);
        else if (a=="--capillaryM2" || a=="--capillary" || a=="--surfaceTension" || a=="--sigmaEnable") P.capillaryM2 = geti(i);
        else if (a=="--sigmaLike" || a=="--sigmaColor" || a=="--sigmaEff") P.sigmaLike = getf(i);
        else if (a=="--sigmaGrad0" || a=="--sigmaGradMin") P.sigmaGrad0 = getf(i);
        else if (a=="--sigmaKappaMax" || a=="--kappaClip") P.sigmaKappaMax = getf(i);
        else if (a=="--calibDrop" || a=="--dropCalib" || a=="--dropCalibration") P.calibDrop = geti(i);
        else if (a=="--dropEllipse" || a=="--dropEllipseEps" || a=="--dropEps") P.dropEllipse = getf(i);
        else if (a=="--dropDiagStride") P.dropDiagStride = geti(i);
        else if (a=="--dropIsoC2" || a=="--dropIso") P.dropIsoC2 = getf(i);
        else if (a=="--dropInFrac") P.dropInFrac = getf(i);
        else if (a=="--dropOutR1Frac") P.dropOutR1Frac = getf(i);
        else if (a=="--dropOutR2Frac") P.dropOutR2Frac = getf(i);
        else if (a=="--dropWall" || a=="--sessileDrop" || a=="--dropOnWall") P.dropWall = geti(i);
        else if (a=="--gravX" || a=="--gx") P.gravX = getf(i);
        else if (a=="--gravY" || a=="--gy") P.gravY = getf(i);
        else if (a=="--wallWetBottom") P.wallWetBottom = geti(i);
        else if (a=="--wallWetTop") P.wallWetTop = geti(i);
        else if (a=="--wallWetRange" || a=="--wallWetLambda") P.wallWetRange = getf(i);
        else if (a=="--wallWetCut" || a=="--wallWetCutoff") P.wallWetCut = getf(i);
        else if (a=="--wallWetF1") P.wallWetF1 = getf(i);
        else if (a=="--wallWetF2") P.wallWetF2 = getf(i);
        else if (a=="--mode") P.mode = argv[++i];
        else if (a=="--khY0") P.khY0 = getf(i);
        else if (a=="--khDeltaU") P.khDeltaU = getf(i);
        else if (a=="--khDeltaRho") P.khDeltaRho = getf(i);
        else if (a=="--khU" || a=="--khShearU") P.khU = getf(i);
        else if (a=="--khEpsVy" || a=="--epsVy") P.khEpsVy = getf(i);
        else if (a=="--khKx" || a=="--kPert") P.khKx = getf(i);
        else if (a=="--khSigmaY" || a=="--sigmaPertY") P.khSigmaY = getf(i);
        else if (a=="--khPhase") P.khPhase = getf(i);
        else if (a=="--khJet") P.khJet = geti(i);
        else if (a=="--khInletJet" || a=="--khStripeJet" || a=="--khJetInlet") P.khInletJet = geti(i);
        else if (a=="--khWallY" || a=="--khWallsY" || a=="--khNoSlipY") P.khWallY = geti(i);
        else if (a=="--khJetD" || a=="--khJetDiam" || a=="--khJetDiameter") P.khJetD = getf(i);
        else if (a=="--khJetX0" || a=="--khX0") P.khJetX0 = getf(i);
        else if (a=="--khJetY0") P.khJetY0 = getf(i);
        else if (a=="--couetteU") P.couetteU = getf(i);
        else if (a=="--viscStart") P.viscStart = geti(i);
        else if (a=="--viscReportStride") P.viscReportStride = geti(i);
        else if (a=="--viscBins") P.viscBins = geti(i);
        else if (a=="--viscProfile") P.viscProfile = geti(i);
        else if (a=="--bbEn") P.bbEn = getf(i);
        else if (a=="--bbEt") P.bbEt = getf(i);
        else if (a=="--xc") P.xc = getf(i);
        else if (a=="--yc") { P.yc = getf(i); P.ycUserSet = true; }
        else if (a=="--Rc") { P.Rc = getf(i); P.RcUserSet = true; }
        else if (a=="--epsWall") P.epsWall = getf(i);
        else if (a=="--solid") P.useSolidCylinderParticles = geti(i);
        else if (a=="--solidDV") P.solidDV = getf(i);
        else if (a=="--solidIters") P.solidRepulsionIters = geti(i);
        else if (a=="--solidUseRepulsion") P.solidUseRepulsion = geti(i);
        else if (a=="--solidUseProject") P.solidUseProject = geti(i);
        else if (a=="--solidSpacingFactor") P.solidSpacingFactor = getf(i);
        else if (a=="--solidMaxDispFactor") P.solidMaxDispFactor = getf(i);
        else if (a=="--vis") P.visEnable = geti(i);
        else if (a=="--visStride") P.visStride = geti(i);
        else if (a=="--visNx") P.visNx = geti(i);
        else if (a=="--visNy") P.visNy = geti(i);
        else if (a=="--visSmooth") P.visSmoothPasses = geti(i);
        else if (a=="--visClip") P.visClip = getf(i);
        else if (a=="--visAlpha") P.visAlpha = getf(i);
        else if (a=="--visWinScale") P.visWinScale = geti(i);
        else if (a=="--visVsync") P.visVsync = geti(i);
        else if (a=="--visField") {
            std::string v = argv[++i];
            if      (v=="omega" || v=="vort" || v=="vorticity") P.visField = 0;
            else if (v=="speed" || v=="umag" || v=="norm")      P.visField = 1;
            else if (v=="ux")                                   P.visField = 2;
            else if (v=="uy")                                   P.visField = 3;
            else if (v=="tracer" || v=="traceur" || v=="csigned" || v=="mix" || v=="species") P.visField = 4;
            else P.visField = std::stoi(v); // allow numeric 0..4
        }
        else if (a=="--dumpStride") P.dumpStride = geti(i);
        else if (a=="--outDir") P.outDir = argv[++i];
        else if (a=="--writeCSV") P.writeCSV = geti(i);
        else if (a=="--logStride") P.logStride = geti(i);
        else if (a=="--seed") P.rngSeed = (uint32_t)std::stoul(argv[++i]);
        else if (a=="--NxF") P.NxF = geti(i);
        else if (a=="--NyF") P.NyF = geti(i);
        else {
            std::fprintf(stderr,"Unknown arg: %s\n", a.c_str());
            std::exit(1);
        }
    }
}

static inline void ensureDir(const std::string& path) {
#if defined(_WIN32)
    std::string cmd = "mkdir " + path;
#else
    std::string cmd = "mkdir -p " + path;
#endif
    std::system(cmd.c_str());
}

static void writeFieldCSV(
    const std::string& filename,
    const std::vector<float>& Ux, const std::vector<float>& Uy,
    const std::vector<int>& Cnt,
    int Nx, int Ny, float Lx, float Ly,
    float xc, float yc, float Rc)
{
    // Ux,Uy,Cnt are stored with linear index c = ix + iy*Nx (ix fastest), 0-based.
    // We'll compute omega on host with periodic centered differences, and mask cylinder.
    std::vector<float> Om((size_t)Nx * (size_t)Ny, 0.f);
    const float dx = Lx / Nx;
    const float dy = Ly / Ny;

    auto at = [&](const std::vector<float>& A, int ix, int iy)->float {
        ix = (ix + Nx) % Nx;
        iy = (iy + Ny) % Ny;
        return A[(size_t)ix + (size_t)iy*(size_t)Nx];
    };

    #pragma omp parallel for
    for (int iy=0; iy<Ny; ++iy) {
        for (int ix=0; ix<Nx; ++ix) {
            float dUydx = (at(Uy, ix+1, iy) - at(Uy, ix-1, iy)) / (2.f*dx);
            float dUxdy = (at(Ux, ix, iy+1) - at(Ux, ix, iy-1)) / (2.f*dy);
            Om[(size_t)ix + (size_t)iy*(size_t)Nx] = dUydx - dUxdy;
        }
    }

    std::ofstream out(filename);
    out << "x_center,y_center,ux,uy,count,omega\n";
    for (int iy=0; iy<Ny; ++iy) {
        float y = (iy + 0.5f) * dy;
        for (int ix=0; ix<Nx; ++ix) {
            float x = (ix + 0.5f) * dx;
            float ux = Ux[(size_t)ix + (size_t)iy*(size_t)Nx];
            float uy = Uy[(size_t)ix + (size_t)iy*(size_t)Nx];
            int   c  = Cnt[(size_t)ix + (size_t)iy*(size_t)Nx];
            float om = Om[(size_t)ix + (size_t)iy*(size_t)Nx];

            // mask inside cylinder
            float dxm = x - xc;
            float dym = y - yc;
            if (Rc > 0.f && (dxm*dxm + dym*dym <= Rc*Rc)) {
                out << x << "," << y << ",nan,nan," << c << ",nan\n";
            } else {
                out << x << "," << y << "," << ux << "," << uy << "," << c << "," << om << "\n";
            }
        }
    }

}

static void writeTracerCSV(
    const std::string& filename,
    const std::vector<int>& CntF1, const std::vector<int>& CntF2,
    int Nx, int Ny, float Lx, float Ly,
    float xc, float yc, float Rc)
{
    const float dx = Lx / Nx;
    const float dy = Ly / Ny;

    std::ofstream out(filename);
    out << "x_center,y_center,count_f1,count_f2,count_total,c_f1,c_f2,c_signed\n";
    for (int iy=0; iy<Ny; ++iy) {
        float y = (iy + 0.5f) * dy;
        for (int ix=0; ix<Nx; ++ix) {
            float x = (ix + 0.5f) * dx;
            int c1 = CntF1[(size_t)ix + (size_t)iy*(size_t)Nx];
            int c2 = CntF2[(size_t)ix + (size_t)iy*(size_t)Nx];
            int ct = c1 + c2;
            float cf1 = (ct > 0) ? ((float)c1 / (float)ct) : 0.5f;
            float cf2 = (ct > 0) ? ((float)c2 / (float)ct) : 0.5f;
            float cs  = (ct > 0) ? (2.f*cf1 - 1.f) : 0.f;

            float dxm = x - xc;
            float dym = y - yc;
            if (Rc > 0.f && (dxm*dxm + dym*dym <= Rc*Rc)) {
                out << x << "," << y << "," << c1 << "," << c2 << "," << ct << ",nan,nan,nan\n";
            } else {
                out << x << "," << y << "," << c1 << "," << c2 << "," << ct << "," << cf1 << "," << cf2 << "," << cs << "\n";
            }
        }
    }
}


static void writeMassFieldCSV(
    const std::string& filename,
    const std::vector<int>& Cnt,
    const std::vector<int>* CntF1,
    const std::vector<int>* CntF2,
    int Nx, int Ny, float Lx, float Ly,
    float m1, float m2,
    float xc, float yc, float Rc)
{
    const float dx = Lx / Nx;
    const float dy = Ly / Ny;
    const float cellArea = dx * dy;

    std::ofstream out(filename);
    out << "x_center,y_center,count,rho_mass,rho1_mass,rho2_mass,Y1_mass,Y2_mass\n";
    for (int iy=0; iy<Ny; ++iy) {
        float y = (iy + 0.5f) * dy;
        for (int ix=0; ix<Nx; ++ix) {
            size_t id = (size_t)ix + (size_t)iy*(size_t)Nx;
            float x = (ix + 0.5f) * dx;
            int ct = Cnt[id];

            double mcell = 0.0, mcell1 = 0.0, mcell2 = 0.0;
            if (CntF1 && CntF2) {
                int c1 = (*CntF1)[id];
                int c2 = (*CntF2)[id];
                mcell1 = (double)c1 * (double)m1;
                mcell2 = (double)c2 * (double)m2;
                mcell  = mcell1 + mcell2;
            } else {
                mcell = (double)ct * (double)m1;
                mcell1 = mcell;
                mcell2 = 0.0;
            }

            double rho  = mcell  / (double)cellArea;
            double rho1 = mcell1 / (double)cellArea;
            double rho2 = mcell2 / (double)cellArea;
            double Y1 = (mcell > 0.0) ? (mcell1 / mcell) : 0.0;
            double Y2 = (mcell > 0.0) ? (mcell2 / mcell) : 0.0;

            float dxm = x - xc;
            float dym = y - yc;
            if (Rc > 0.f && (dxm*dxm + dym*dym <= Rc*Rc)) {
                out << x << "," << y << "," << ct << ",nan,nan,nan,nan,nan\n";
            } else {
                out << x << "," << y << "," << ct << "," << rho << "," << rho1 << "," << rho2
                    << "," << Y1 << "," << Y2 << "\n";
            }
        }
    }
}

// ----------------------- Optional real-time visualization (CUDA + OpenGL interop) -----------------------
static inline const char* visFieldName(int m) {
    switch (m) {
        case 0: return "omega";
        case 1: return "speed";
        case 2: return "ux";
        case 3: return "uy";
        case 4: return "tracer";
        default: return "scalar";
    }
}

#ifdef USE_GL_VIS

struct RealtimeVis {
    bool enabled = false;
    bool initialized = false;
    bool hasDisplayScalar = false;

    int NxV = 0, NyV = 0, N = 0;
    int smoothPasses = 1;
    int fieldMode = 0;
    float clip = -1.f;
    float alpha = 0.3f;
    int periodicY = 1;

    float Lx = 0.f, Ly = 0.f;
    float xc = 0.f, yc = 0.f, Rc = 0.f;
    int maskCylinder = 0;

    // Runtime visualization backend mode:
    //  - interopActive=true  : CUDA/OpenGL interop (Linux native typically)
    //  - fallbackCpuUpload=true : WSL / unsupported interop -> cudaMemcpy + glTexSubImage2D
    bool interopRequested = true;
    bool interopActive = false;
    bool fallbackCpuUpload = false;
    size_t rgbaBytes = 0;

    // Device buffers (coarse display grid)
    int* d_cnt = nullptr;
    float *d_sumUx = nullptr, *d_sumUy = nullptr;
    float *d_sumTag = nullptr;
    float *d_uA = nullptr, *d_vA = nullptr;
    float *d_uB = nullptr, *d_vB = nullptr;
    float *d_scalar = nullptr;
    float *d_scalarDisp = nullptr;
    uchar4* d_rgba = nullptr;      // colormapped display image on GPU (used by both backends)
    uchar4* h_rgba = nullptr;      // pinned host fallback buffer (WSL / no interop)

    // OpenGL / GLFW
    GLFWwindow* window = nullptr;
    GLuint pbo = 0;
    GLuint tex = 0;
    cudaGraphicsResource* cudaPbo = nullptr;
};

static void visDestroy(RealtimeVis& V) {
    if (V.cudaPbo) {
        cudaGraphicsUnregisterResource(V.cudaPbo);
        V.cudaPbo = nullptr;
    }
    if (V.pbo) {
        glDeleteBuffers(1, &V.pbo);
        V.pbo = 0;
    }
    if (V.tex) {
        glDeleteTextures(1, &V.tex);
        V.tex = 0;
    }
    if (V.window) {
        glfwDestroyWindow(V.window);
        V.window = nullptr;
        glfwTerminate();
    }

    if (V.d_cnt) cudaFree(V.d_cnt);
    if (V.d_sumUx) cudaFree(V.d_sumUx);
    if (V.d_sumUy) cudaFree(V.d_sumUy);
    if (V.d_sumTag) cudaFree(V.d_sumTag);
    if (V.d_uA) cudaFree(V.d_uA);
    if (V.d_vA) cudaFree(V.d_vA);
    if (V.d_uB) cudaFree(V.d_uB);
    if (V.d_vB) cudaFree(V.d_vB);
    if (V.d_scalar) cudaFree(V.d_scalar);
    if (V.d_scalarDisp) cudaFree(V.d_scalarDisp);
    if (V.d_rgba) cudaFree(V.d_rgba);
    if (V.h_rgba) cudaFreeHost(V.h_rgba);
    V = RealtimeVis{};
}

static bool visInit(RealtimeVis& V, const Params& P) {
    V.enabled = (P.visEnable != 0);
    if (!V.enabled) return false;

    V.NxV = std::max(16, P.visNx);
    V.NyV = std::max(16, P.visNy);
    V.N = V.NxV * V.NyV;
    V.smoothPasses = std::max(0, P.visSmoothPasses);
    V.fieldMode = P.visField;
    if (V.fieldMode == 4 && !P.twoFluidTracer) {
        std::fprintf(stderr, "[vis] tracer field requested (--visField tracer) but --twoFluids is off; falling back to omega.\n");
        V.fieldMode = 0;
    }
    V.clip = P.visClip;
    V.alpha = std::min(1.f, std::max(0.f, P.visAlpha));
    V.periodicY = mode_periodic_y(P) ? 1 : 0;
    V.Lx = P.Lx; V.Ly = P.Ly;
    V.xc = P.xc; V.yc = P.yc; V.Rc = P.Rc;
    V.maskCylinder = mode_has_cylinder(P) ? 1 : 0;

    cudaCheck(cudaMalloc(&V.d_cnt, V.N*sizeof(int)), "vis malloc d_cnt");
    cudaCheck(cudaMalloc(&V.d_sumUx, V.N*sizeof(float)), "vis malloc d_sumUx");
    cudaCheck(cudaMalloc(&V.d_sumUy, V.N*sizeof(float)), "vis malloc d_sumUy");
    cudaCheck(cudaMalloc(&V.d_sumTag, V.N*sizeof(float)), "vis malloc d_sumTag");
    cudaCheck(cudaMalloc(&V.d_uA, V.N*sizeof(float)), "vis malloc d_uA");
    cudaCheck(cudaMalloc(&V.d_vA, V.N*sizeof(float)), "vis malloc d_vA");
    cudaCheck(cudaMalloc(&V.d_uB, V.N*sizeof(float)), "vis malloc d_uB");
    cudaCheck(cudaMalloc(&V.d_vB, V.N*sizeof(float)), "vis malloc d_vB");
    cudaCheck(cudaMalloc(&V.d_scalar, V.N*sizeof(float)), "vis malloc d_scalar");
    cudaCheck(cudaMalloc(&V.d_scalarDisp, V.N*sizeof(float)), "vis malloc d_scalarDisp");
    cudaCheck(cudaMemset(V.d_scalarDisp, 0, V.N*sizeof(float)), "vis memset d_scalarDisp");

    V.rgbaBytes = (size_t)V.N * sizeof(uchar4);
    cudaCheck(cudaMalloc(&V.d_rgba, V.rgbaBytes), "vis malloc d_rgba");

    if (!glfwInit()) {
        std::fprintf(stderr, "[vis] glfwInit failed; visualization disabled.\n");
        visDestroy(V);
        return false;
    }

    glfwWindowHint(GLFW_RESIZABLE, GLFW_FALSE);
    glfwWindowHint(GLFW_VISIBLE, GLFW_TRUE);
    glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 2);
    glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 1);

    int scale = std::max(1, P.visWinScale);
    int w = V.NxV * scale;
    int h = V.NyV * scale;
    std::ostringstream title;
    title << "MPCD " << P.mode << " (" << visFieldName(V.fieldMode) << ", " << V.NxV << "x" << V.NyV << ")";

    V.window = glfwCreateWindow(w, h, title.str().c_str(), nullptr, nullptr);
    if (!V.window) {
        std::fprintf(stderr, "[vis] glfwCreateWindow failed; visualization disabled.\n");
        visDestroy(V);
        return false;
    }
    glfwMakeContextCurrent(V.window);
    glfwSwapInterval(P.visVsync ? 1 : 0);

    glDisable(GL_DEPTH_TEST);
    glDisable(GL_BLEND);
    glEnable(GL_TEXTURE_2D);

    glGenTextures(1, &V.tex);
    glBindTexture(GL_TEXTURE_2D, V.tex);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, V.NxV, V.NyV, 0, GL_RGBA, GL_UNSIGNED_BYTE, nullptr);
    glBindTexture(GL_TEXTURE_2D, 0);

    glGenBuffers(1, &V.pbo);
    glBindBuffer(GL_PIXEL_UNPACK_BUFFER, V.pbo);
    glBufferData(GL_PIXEL_UNPACK_BUFFER, V.rgbaBytes, nullptr, GL_STREAM_DRAW);
    glBindBuffer(GL_PIXEL_UNPACK_BUFFER, 0);

    // Try CUDA/OpenGL interop first (works on Linux native with compatible GL context),
    // then fall back automatically to CPU upload (WSL2 and other unsupported setups).
    cudaError_t regErr = cudaGraphicsGLRegisterBuffer(&V.cudaPbo, V.pbo, cudaGraphicsRegisterFlagsWriteDiscard);
    if (regErr == cudaSuccess) {
        V.interopActive = true;
        V.fallbackCpuUpload = false;
        std::printf("[vis] enabled (CUDA/OpenGL interop): field=%s grid=%dx%d stride=%d smooth=%d alpha=%.3g clip=%g\n",
            visFieldName(V.fieldMode), V.NxV, V.NyV, P.visStride, V.smoothPasses, V.alpha, V.clip);
    } else {
        V.cudaPbo = nullptr;
        V.interopActive = false;
        V.fallbackCpuUpload = true;

        // Clear sticky error state after failed interop registration.
        cudaGetLastError();

        cudaCheck(cudaHostAlloc((void**)&V.h_rgba, V.rgbaBytes, cudaHostAllocDefault),
                  "vis hostalloc h_rgba fallback");

        std::fprintf(stderr,
            "[vis] CUDA/OpenGL interop unavailable (%s). Using fallback CUDA->CPU upload (WSL-friendly).\n",
            cudaGetErrorString(regErr));
        std::printf("[vis] enabled (CPU upload fallback): field=%s grid=%dx%d stride=%d smooth=%d alpha=%.3g clip=%g\n",
            visFieldName(V.fieldMode), V.NxV, V.NyV, P.visStride, V.smoothPasses, V.alpha, V.clip);
    }

    V.initialized = true;
    return true;
}


static void visUpdateAndDraw(
    RealtimeVis& V, const Params& P,
    const float* d_x, const float* d_y, const float* d_vx, const float* d_vy,
    const unsigned char* d_tag,
    int n, uint32_t it)
{
    if (!V.initialized || !V.enabled) return;
    if (!V.window || glfwWindowShouldClose(V.window)) {
        V.enabled = false;
        return;
    }
    if (P.visStride <= 0) return;
    if (it % (uint32_t)P.visStride != 0 && it != 1u) return;

    const int threads = 256;
    const int blocksN = (n + threads - 1) / threads;
    const int blocksV = (V.N + threads - 1) / threads;

    cudaCheck(cudaMemset(V.d_cnt, 0, V.N*sizeof(int)), "vis memset cnt");
    cudaCheck(cudaMemset(V.d_sumUx, 0, V.N*sizeof(float)), "vis memset sumUx");
    cudaCheck(cudaMemset(V.d_sumUy, 0, V.N*sizeof(float)), "vis memset sumUy");
    if (V.fieldMode == 4) {
        cudaCheck(cudaMemset(V.d_sumTag, 0, V.N*sizeof(float)), "vis memset sumTag");
    }

    vis_accumulate_particles_kernel<<<blocksN, threads>>>(
        d_x, d_y, d_vx, d_vy, n, V.Lx, V.Ly, V.NxV, V.NyV,
        V.d_cnt, V.d_sumUx, V.d_sumUy);

    if (V.fieldMode == 4) {
        vis_accumulate_tracer_kernel<<<blocksN, threads>>>(
            d_x, d_y, d_tag, n, V.Lx, V.Ly, V.NxV, V.NyV, V.d_sumTag);

        vis_scalar_from_tracer_kernel<<<blocksV, threads>>>(V.d_cnt, V.d_sumTag, V.N, V.d_scalar);

        for (int s = 0; s < V.smoothPasses; ++s) {
            vis_smooth_scalar_box3_weighted_kernel<<<blocksV, threads>>>(
                V.d_scalar, V.d_cnt, V.NxV, V.NyV, V.periodicY, V.d_uA);
            std::swap(V.d_scalar, V.d_uA);
        }
    } else {
        vis_normalize_kernel<<<blocksV, threads>>>(V.d_cnt, V.d_sumUx, V.d_sumUy, V.N, V.d_uA, V.d_vA);

        for (int s = 0; s < V.smoothPasses; ++s) {
            vis_smooth_box3_weighted_kernel<<<blocksV, threads>>>(
                V.d_uA, V.d_vA, V.d_cnt, V.NxV, V.NyV, V.periodicY, V.d_uB, V.d_vB);
            std::swap(V.d_uA, V.d_uB);
            std::swap(V.d_vA, V.d_vB);
        }

        vis_scalar_from_velocity_kernel<<<blocksV, threads>>>(
            V.d_uA, V.d_vA, V.d_cnt, V.NxV, V.NyV, V.Lx, V.Ly, V.periodicY, V.fieldMode, V.d_scalar);
    }

    if (!V.hasDisplayScalar || V.alpha >= 1.f) {
        cudaCheck(cudaMemcpy(V.d_scalarDisp, V.d_scalar, V.N*sizeof(float), cudaMemcpyDeviceToDevice),
                  "vis copy scalar->scalarDisp");
        V.hasDisplayScalar = true;
    } else if (V.alpha > 0.f) {
        vis_temporal_blend_kernel<<<blocksV, threads>>>(V.d_scalarDisp, V.d_scalar, V.N, V.alpha);
    }

    float autoClip = V.clip;
    if (!(autoClip > 0.f)) {
        // Heuristics for display only (stable enough for tuning)
        if (V.fieldMode == 0) autoClip = std::max(1e-6f, 2.5f * std::fabs(P.U0) / std::max(P.Rc*2.f, 1e-6f));
        else if (V.fieldMode == 1) autoClip = std::max(1e-6f, 2.0f * std::fabs(P.U0));
        else if (V.fieldMode == 4) autoClip = 1.f;
        else autoClip = std::max(1e-6f, 1.5f * std::fabs(P.U0));
    }

    // Colormap always to an intermediate GPU RGBA buffer. Then:
    //   - interop path: D2D copy to mapped OpenGL PBO
    //   - fallback path: D2H copy to pinned host + glTexSubImage2D
    vis_colormap_kernel<<<blocksV, threads>>>(
        V.d_scalarDisp, V.d_cnt, V.NxV, V.NyV, V.fieldMode, autoClip,
        V.xc, V.yc, V.Rc, V.maskCylinder, V.Lx, V.Ly, V.d_rgba);
    cudaCheck(cudaGetLastError(), "vis kernels");

    if (V.interopActive && V.cudaPbo) {
        cudaCheck(cudaGraphicsMapResources(1, &V.cudaPbo), "vis map PBO");
        uchar4* d_pbo = nullptr;
        size_t nbytes = 0;
        cudaCheck(cudaGraphicsResourceGetMappedPointer((void**)&d_pbo, &nbytes, V.cudaPbo),
                  "vis get mapped PBO");
        if (nbytes < V.rgbaBytes) {
            std::fprintf(stderr, "[vis] mapped PBO too small (%zu bytes, need %zu)\n", nbytes, V.rgbaBytes);
        } else {
            cudaCheck(cudaMemcpy(d_pbo, V.d_rgba, V.rgbaBytes, cudaMemcpyDeviceToDevice),
                      "vis copy rgba->PBO");
        }
        cudaCheck(cudaGraphicsUnmapResources(1, &V.cudaPbo), "vis unmap PBO");
    } else if (V.fallbackCpuUpload) {
        cudaCheck(cudaMemcpy(V.h_rgba, V.d_rgba, V.rgbaBytes, cudaMemcpyDeviceToHost),
                  "vis copy rgba->host");
    }

    glfwMakeContextCurrent(V.window);
    int ww = 0, wh = 0;
    glfwGetFramebufferSize(V.window, &ww, &wh);
    glViewport(0, 0, ww, wh);
    glClearColor(0.03f, 0.03f, 0.03f, 1.f);
    glClear(GL_COLOR_BUFFER_BIT);

    glBindTexture(GL_TEXTURE_2D, V.tex);
    glPixelStorei(GL_UNPACK_ALIGNMENT, 1);

    if (V.interopActive && V.cudaPbo) {
        glBindBuffer(GL_PIXEL_UNPACK_BUFFER, V.pbo);
        glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, V.NxV, V.NyV, GL_RGBA, GL_UNSIGNED_BYTE, 0);
        glBindBuffer(GL_PIXEL_UNPACK_BUFFER, 0);
    } else if (V.fallbackCpuUpload && V.h_rgba) {
        glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, V.NxV, V.NyV, GL_RGBA, GL_UNSIGNED_BYTE, (const void*)V.h_rgba);
    }

    glMatrixMode(GL_PROJECTION);
    glLoadIdentity();
    glMatrixMode(GL_MODELVIEW);
    glLoadIdentity();

    glBegin(GL_QUADS);
      glTexCoord2f(0.f, 0.f); glVertex2f(-1.f, -1.f);
      glTexCoord2f(1.f, 0.f); glVertex2f( 1.f, -1.f);
      glTexCoord2f(1.f, 1.f); glVertex2f( 1.f,  1.f);
      glTexCoord2f(0.f, 1.f); glVertex2f(-1.f,  1.f);
    glEnd();

    glfwSwapBuffers(V.window);
    glfwPollEvents();
}

#else  // !USE_GL_VIS

struct RealtimeVis {
    bool enabled = false;
    bool initialized = false;
};

static bool visInit(RealtimeVis& V, const Params& P) {
    if (P.visEnable) {
        std::fprintf(stderr,"[vis] --vis 1 requested but binary was compiled without -DUSE_GL_VIS. Visualization disabled.\n");
    }
    V.enabled = false;
    V.initialized = false;
    return false;
}

static void visUpdateAndDraw(
    RealtimeVis&, const Params&,
    const float*, const float*, const float*, const float*,
    const unsigned char*,
    int, uint32_t) {}

static void visDestroy(RealtimeVis&) {}

#endif // USE_GL_VIS


struct DropCalibDiag {
    bool valid = false;
    double xcm = NAN, ycm = NAN;
    double area = NAN, Req = NAN;
    double p_in = NAN, p_out = NAN, dp = NAN, sigma_eff = NAN;
    double n_in = NAN, n_out = NAN;
    int cells_drop = 0, cells_in = 0, cells_out = 0;
};

static DropCalibDiag computeDropCalibDiagFromCounts(
    const Params& P,
    const std::vector<int>& Cnt,
    const std::vector<int>& CntF2,
    int Nx, int Ny)
{
    DropCalibDiag D;
    if (Nx <= 0 || Ny <= 0 || (int)Cnt.size() != Nx*Ny || (int)CntF2.size() != Nx*Ny) return D;

    const double dx = (double)P.Lx / (double)Nx;
    const double dy = (double)P.Ly / (double)Ny;
    const double cellArea = dx * dy;
    const double twoPi = 2.0 * M_PI;

    double wsum = 0.0;
    double sx = 0.0, cx = 0.0, sy = 0.0, cy = 0.0;
    double area = 0.0;
    int cellsDrop = 0;

    for (int iy=0; iy<Ny; ++iy) {
        double y = ((double)iy + 0.5) * dy;
        for (int ix=0; ix<Nx; ++ix) {
            double x = ((double)ix + 0.5) * dx;
            size_t id = (size_t)ix + (size_t)iy*(size_t)Nx;
            int ct = Cnt[id];
            int c2 = CntF2[id];
            if (ct <= 0 || c2 <= 0) continue;
            double c2frac = (double)c2 / (double)ct;
            if (c2frac >= (double)P.dropIsoC2) {
                double w = (double)c2; // weight center by amount of species-2
                area += cellArea;
                cellsDrop++;
                wsum += w;
                double thx = twoPi * x / (double)P.Lx;
                double thy = twoPi * y / (double)P.Ly;
                cx += w * cos(thx); sx += w * sin(thx);
                cy += w * cos(thy); sy += w * sin(thy);
            }
        }
    }

    if (cellsDrop <= 0 || area <= 0.0) return D;

    D.area = area;
    D.Req = std::sqrt(area / M_PI);
    D.cells_drop = cellsDrop;

    if (wsum > 0.0) {
        double thx = std::atan2(sx, cx);
        double thy = std::atan2(sy, cy);
        if (thx < 0.0) thx += twoPi;
        if (thy < 0.0) thy += twoPi;
        D.xcm = (double)P.Lx * thx / twoPi;
        D.ycm = (double)P.Ly * thy / twoPi;
    } else {
        D.xcm = 0.5 * (double)P.Lx;
        D.ycm = 0.5 * (double)P.Ly;
    }

    const double Rin  = std::max(0.0, (double)P.dropInFrac * D.Req);
    const double Rout1 = std::max(Rin, (double)P.dropOutR1Frac * D.Req);
    const double Rout2 = std::max(Rout1 + 1e-12, (double)P.dropOutR2Frac * D.Req);

    double sumNin = 0.0, sumNout = 0.0;
    int nin = 0, nout = 0;

    for (int iy=0; iy<Ny; ++iy) {
        double y = ((double)iy + 0.5) * dy;
        for (int ix=0; ix<Nx; ++ix) {
            double x = ((double)ix + 0.5) * dx;
            size_t id = (size_t)ix + (size_t)iy*(size_t)Nx;
            int ct = Cnt[id];
            if (ct <= 0) continue;

            double ddx = periodic_delta((float)(x - D.xcm), P.Lx);
            double ddy = periodic_delta((float)(y - D.ycm), P.Ly);
            double r = std::sqrt(ddx*ddx + ddy*ddy);

            if (r < Rin) {
                sumNin += (double)ct / cellArea;
                nin++;
            } else if (r >= Rout1 && r < Rout2) {
                sumNout += (double)ct / cellArea;
                nout++;
            }
        }
    }

    D.cells_in = nin;
    D.cells_out = nout;
    if (nin > 0) D.n_in = sumNin / (double)nin;
    if (nout > 0) D.n_out = sumNout / (double)nout;

    if (nin > 0) D.p_in = D.n_in * (double)P.kBT;
    if (nout > 0) D.p_out = D.n_out * (double)P.kBT;
    if (nin > 0 && nout > 0) {
        D.dp = D.p_in - D.p_out;
        D.sigma_eff = D.dp * D.Req; // 2D Laplace proxy: Delta p = sigma / R
        D.valid = true;
    }
    return D;
}


// ----------------------- Main -----------------------
int main(int argc, char** argv) {
    Params P;
    // Default yc,Rc depend on Ly; update after parsing if user changed Ly but didn't set yc/Rc is ambiguous.
    parseArgs(argc, argv, P);
    if (P.mode == "KelvinHelmholtz" || P.mode == "kelvinhelmholtz" || P.mode == "kelvin-helmholtz" || P.mode == "KH") P.mode = "kh";
    if (P.mode == "khjet" || P.mode == "KHJET" || P.mode == "kh-jet") { P.mode = "kh"; P.khJet = 1; }
    if (P.mode == "khinletjet" || P.mode == "kh-inlet-jet" || P.mode == "khstripejet" || P.mode == "kh-stripe-jet") { P.mode = "kh"; P.khInletJet = 1; }
    if (P.mode == "drop" || P.mode == "DROP" || P.mode == "dropcal" || P.mode == "drop-calib") P.calibDrop = 1;
    if (P.mode == "drop_wall" || P.mode == "dropwall" || P.mode == "sessile" || P.mode == "sessile-drop" || P.mode == "drop-on-wall") P.dropWall = 1;
    if (P.calibDrop) {
        P.mode = "kh";
        P.khJet = 1;
        P.khInletJet = 0;
        P.khWallY = 0;
        P.keepMeanFlow = 0;
        P.xInletInject = 0;
        P.reinjectBackflow = 0;
        P.injectRandomY = 1;
        P.khU = 0.f;
        P.khEpsVy = 0.f;
        P.khKx = 0.f;
        P.khPhase = 0.f;
        P.U0 = 0.f;
        P.twoFluidTracer = 1;
        if (P.dropDiagStride <= 0) P.dropDiagStride = P.dumpStride;
        if (P.visField == 0 || P.visField == 1 || P.visField == 2 || P.visField == 3) {
            // tracer is usually the most informative field for drop calibration unless user explicitly requested it.
        }
    }
    if (P.dropWall) {
        // Preset: sessile droplet settling on a wall (internally uses KH round-blob initializer).
        P.mode = "kh";
        P.khJet = 1;
        P.khInletJet = 0;
        P.khWallY = 1;           // no-slip walls at y=0,Ly
        P.keepMeanFlow = 0;
        P.xInletInject = 0;
        P.reinjectBackflow = 0;
        P.injectRandomY = 1;
        P.khU = 0.f;
        P.khEpsVy = 0.f;
        P.khKx = 0.f;
        P.khPhase = 0.f;
        P.U0 = 0.f;
        P.twoFluidTracer = 1;
        if (P.khJetY0 < 0.f) P.khJetY0 = 0.70f * P.Ly;   // start above the bottom wall
        if (P.khJetX0 < 0.f) P.khJetX0 = 0.50f * P.Lx;
        if (P.khJetD  <= 0.f) P.khJetD  = 0.18f * fminf(P.Lx, P.Ly);
        if (P.gravY == 0.f) P.gravY = -0.01f;            // weak settling acceleration (dimensionless)
        if (P.wallWetBottom == 0 && P.wallWetTop == 0) P.wallWetBottom = 1;
        if (P.wallWetF2 == 0.f && P.wallWetF1 == 0.f) {
            P.wallWetF2 = 0.02f;  // fluid-2 wets the bottom wall by default
            P.wallWetF1 = 0.f;    // ambient neutral (can be set >0 or <0 for preferential wetting)
        }
    }
    if ((P.immiscible || P.capillaryM2) && !P.twoFluidTracer) {
        if (P.immiscible) {
            std::fprintf(stderr, "[M1] immiscible requested but twoFluidTracer=0; disabling immiscible mode.\n");
            P.immiscible = 0;
        }
        if (P.capillaryM2) {
            std::fprintf(stderr, "[M2] capillaryM2 requested but twoFluidTracer=0; disabling capillary mode.\n");
            P.capillaryM2 = 0;
        }
    }
    if (P.immiscible && P.chiColor == 0.f) {
        std::fprintf(stderr, "[M1] immiscible=1 but chiColor=0 => no effective demixing (keeping mode enabled for diagnostics).\n");
    }
    if (P.capillaryM2 && P.sigmaLike == 0.f) {
        std::fprintf(stderr, "[M2] capillaryM2=1 but sigmaLike=0 => no effective capillary forcing (keeping mode enabled for diagnostics).\n");
    }
    if (P.mode == "VK") P.mode = "vk";
    if (P.mode == "Couette") P.mode = "couette";
    if (!(P.mode == "vk" || P.mode == "couette" || P.mode == "kh")) {
        std::fprintf(stderr, "Error: unsupported --mode '%s' (supported: vk, couette, kh, drop_wall).\n", P.mode.c_str());
        std::exit(1);
    }
    if (P.tracerSplitY < 0.f) P.tracerSplitY = 0.5f * P.Ly;
    if (P.tracerSplitY < 0.f) P.tracerSplitY = 0.f;
    if (P.tracerSplitY > P.Ly) P.tracerSplitY = P.Ly;
    if (P.m1 <= 0.f || P.m2 <= 0.f) {
        std::fprintf(stderr, "Error: --m1 and --m2 must be > 0.\n");
        std::exit(1);
    }
    if (P.NxF < 0) P.NxF = P.Nx;
    if (P.NyF < 0) P.NyF = P.Ny;
    P.dropIsoC2 = fminf(0.999f, fmaxf(0.001f, P.dropIsoC2));
    P.dropInFrac = fmaxf(0.05f, P.dropInFrac);
    P.dropOutR1Frac = fmaxf(P.dropInFrac + 0.05f, P.dropOutR1Frac);
    P.dropOutR2Frac = fmaxf(P.dropOutR1Frac + 0.05f, P.dropOutR2Frac);

    const float a0 = P.Lx / (float)P.Nx; // assumes square cells (user uses Ny so that Ly/Ny ~= a0)

    if (P.wallWetRange <= 0.f) P.wallWetRange = 3.f * a0;
    if (P.wallWetCut <= 0.f)   P.wallWetCut   = 4.f * P.wallWetRange;
    P.wallWetRange = fmaxf(P.wallWetRange, 0.25f * a0);
    P.wallWetCut   = fmaxf(P.wallWetCut, P.wallWetRange);

    if (mode_is_kh(P)) {
        if (P.khY0 < 0.f) P.khY0 = 0.5f * P.Ly;
        if (P.khDeltaU <= 0.f) P.khDeltaU = fmaxf(2.f * a0, 1e-6f * P.Ly);
        if (P.khDeltaRho <= 0.f) P.khDeltaRho = P.khDeltaU;
        if (P.khU < 0.f) P.khU = P.U0;
        if (P.khKx <= 0.f) P.khKx = 2.f * (float)M_PI / fmaxf(P.Lx, 1e-12f);
        if (P.khSigmaY <= 0.f) P.khSigmaY = 2.f * fmaxf(P.khDeltaU, P.khDeltaRho);
        if (P.khJet && P.khInletJet) {
            std::fprintf(stderr, "[kh] both khJet (round-blob init) and khInletJet (x-inlet stripe jet) requested; using khInletJet and disabling khJet.\n");
            P.khJet = 0;
        }
        if (P.khJet || P.khInletJet) {
            if (P.khJetX0 < 0.f) P.khJetX0 = 0.5f * P.Lx;
            if (P.khJetY0 < 0.f) P.khJetY0 = 0.5f * P.Ly;
            if (P.khJetD <= 0.f) P.khJetD = (P.calibDrop ? 0.18f : 0.25f) * fminf(P.Lx, P.Ly);
            P.khJetD = fmaxf(P.khJetD, 2.f * a0);
            // keep reference centers inside the box for visualization and periodic distance logic
            while (P.khJetX0 < 0.f) P.khJetX0 += P.Lx;
            while (P.khJetX0 >= P.Lx) P.khJetX0 -= P.Lx;
            while (P.khJetY0 < 0.f) P.khJetY0 += P.Ly;
            while (P.khJetY0 >= P.Ly) P.khJetY0 -= P.Ly;
        }
        // KH is a periodic shear-layer test; disable VK-specific mean-flow forcing / inflow unless user explicitly changed them.
        if (P.keepMeanFlow != 0) {
            std::fprintf(stderr, "[kh] forcing keepMeanFlow=0 (KH shear layer should evolve freely).\n");
            P.keepMeanFlow = 0;
        }
        if (!P.khInletJet) {
            if (P.xInletInject != 0) {
                std::fprintf(stderr, "[kh] forcing xInletInject=0 (periodic x/y for standard KH mode).\n");
                P.xInletInject = 0;
            }
        } else {
            if (P.xInletInject == 0) {
                std::fprintf(stderr, "[kh] enabling xInletInject=1 for inlet-stripe jet mode.\n");
                P.xInletInject = 1;
            }
            if (P.injectRandomY == 0) {
                std::fprintf(stderr, "[kh] enabling injectRandomY=1 for inlet-stripe jet mode (uniform inlet sampling in y).\n");
                P.injectRandomY = 1;
            }
            if (P.reinjectBackflow == 0) {
                std::fprintf(stderr, "[kh] enabling reinjectBackflow=1 for inlet-stripe jet mode (prevents upstream accumulation at x=0).\n");
                P.reinjectBackflow = 1;
            }
            if (P.khWallY) {
                std::fprintf(stderr, "[kh] khWallY=1: using no-slip walls at y=0,Ly for inlet-stripe jet mode.\n");
            }
        }
        if (!P.twoFluidTracer) {
            std::fprintf(stderr, "[kh] note: --twoFluids is OFF, enabling species tags for variable-density KH initialization.\n");
            P.twoFluidTracer = 1;
        }
        P.tracerSplitY = P.khY0; // legacy print/compatibility; actual KH init may use khJet geometry
    }
    const int Nc = P.Nx * P.Ny;
    const int n  = (int)llround((double)P.gamma * (double)Nc);

    // Geometry-dependent precomputations (a0 is the MPCD cell size).
    const float solidSpacing = P.solidSpacingFactor * a0;
    const float Lr = sqrtf(fmaxf(2.f * a0*a0 / (3.f * P.gamma), 1e-20f)); // Crespin-style estimate
    const float maxDisp = P.solidMaxDispFactor * Lr;
    const int nSolid = std::max(16, (int)ceil(2.0 * M_PI * P.Rc / std::max((double)solidSpacing, 1e-20)));

    std::printf("MPCD/SRD 2D (CUDA+OpenMP)\n");
    std::printf("Mode: %s\n", P.mode.c_str());
    std::printf("Domain: Lx=%.6g Ly=%.6g | Nx=%d Ny=%d -> a0=%.6g | Nc=%d | gamma=%.3g -> n=%d\n",
        P.Lx, P.Ly, P.Nx, P.Ny, a0, Nc, P.gamma, n);
    std::printf("Params: dt=%.3g steps=%d alphaDeg=%.3g U0=%.3g kBT=%.3g thermostat=%d keepMeanFlow=%d\n",
        P.dt, P.nSteps, P.alphaDeg, P.U0, P.kBT, P.useThermostat, P.keepMeanFlow);
    if (mode_is_vk(P)) {
        std::printf("x-boundary (VK): %s  (reinjectBackflow=%d, injectRandomY=%d)\n",
            P.xInletInject ? "open outflow + inlet injection @ x~0" : "periodic wrap",
            P.reinjectBackflow, P.injectRandomY);
    } else if (mode_is_kh(P)) {
        if (P.khInletJet) {
            std::printf("Boundary (KH inlet-jet): x open/outflow + inlet injection @ x~0, %s (no cylinder)\n", P.khWallY ? "no-slip walls in y" : "periodic y");
            if (P.khWallY) std::printf("  KH y-walls: tangential velocity reset to 0 on wall crossing (anti-entrainment)\n");
            std::printf("KH inlet stripe-jet: y0=%.6g D=%.6g  Ujet=%.6g  deltaU=%.6g  deltaRho=%.6g  kx=%.6g  epsVy=%.6g  sigmaEdge=%.6g  phase=%.6g\n",
                P.khJetY0, P.khJetD, P.khU, P.khDeltaU, P.khDeltaRho, P.khKx, P.khEpsVy, P.khSigmaY, P.khPhase);
            std::printf("Inlet control: reinjectBackflow=%d injectRandomY=%d\n", P.reinjectBackflow, P.injectRandomY);
        } else {
            std::printf("Boundary (KH): %s (no cylinder, no inlet injection)\n", P.khWallY ? "periodic x + no-slip walls in y" : "periodic x/y");
            if (!P.khJet) {
                std::printf("KH init (planar layer): y0=%.6g  U=%.6g  deltaU=%.6g  deltaRho=%.6g  kx=%.6g  epsVy=%.6g  sigmaY=%.6g  phase=%.6g\n",
                    P.khY0, P.khU, P.khDeltaU, P.khDeltaRho, P.khKx, P.khEpsVy, P.khSigmaY, P.khPhase);
            } else {
                std::printf("KH init (round jet): x0=%.6g y0=%.6g D=%.6g  Ucore=%.6g  deltaU=%.6g  deltaRho=%.6g  kx=%.6g  epsVy=%.6g  sigmaR=%.6g  phase=%.6g\n",
                    P.khJetX0, P.khJetY0, P.khJetD, P.khU, P.khDeltaU, P.khDeltaRho, P.khKx, P.khEpsVy, P.khSigmaY, P.khPhase);
                if (P.calibDrop) {
                    std::printf("  [drop-calib preset] static droplet at rest (periodic x/y) using KH round-jet initializer as species-2 blob.\n");
                    std::printf("  Init shape: dropEllipse=%.6g (0=circle; ellipse via x/(1+e), y/(1-e))\n", P.dropEllipse);
                    std::printf("  Diagnostics: dropcal_diag.csv every %d steps (or dumpStride if 0) | iso c_f2=%.3g | in<%.3gReq | out in [%.3g, %.3g]Req\n",
                        (P.dropDiagStride>0?P.dropDiagStride:P.dumpStride), P.dropIsoC2, P.dropInFrac, P.dropOutR1Frac, P.dropOutR2Frac);
                }
                if (P.dropWall) {
                    std::printf("  [drop-wall preset] sessile droplet settling toward y=0 with x-periodic / y no-slip walls.\n");
                    std::printf("  Forces: grav=(%.6g, %.6g) | wetBottom=%d wetTop=%d | wallWetRange=%.6g wallWetCut=%.6g | wallWetF1=%.6g wallWetF2=%.6g\n",
                        P.gravX, P.gravY, P.wallWetBottom, P.wallWetTop, P.wallWetRange, P.wallWetCut, P.wallWetF1, P.wallWetF2);
                    std::printf("  Note: dropcal_diag (Laplace proxy) is not strictly valid on a wall-contacting drop; use shape/contact-angle diagnostics.\n");
                }
            }
        }
    }
    if (P.twoFluidTracer) {
        if (mode_is_kh(P) && P.khInletJet) {
            std::printf("Two-fluid tracer/species tag: ON  KH inlet stripe-jet (species2 in source band, species1 ambient; smooth transition by deltaRho)\n");
        } else if (mode_is_kh(P) && P.khJet) {
            std::printf("Two-fluid tracer/species tag: ON  KH-jet initialization (species2 central jet, species1 ambient)\n");
        } else if (mode_is_kh(P)) {
            std::printf("Two-fluid tracer/species tag: ON  KH planar initialization (smooth probabilistic split about y0=%.6g)\n", P.khY0);
        } else {
            std::printf("Two-fluid tracer/species tag: ON  splitY=%.6g  (species1: y<split, species2: y>=split)\n", P.tracerSplitY);
        }
    } else {
        std::printf("Two-fluid tracer/species tag: OFF\n");
    }
    if (P.useSpeciesMass) {
        std::printf("Mass-aware species collisions: ON  m1=%.6g  m2=%.6g  (m2/m1=%.6g)\n",
            P.m1, P.m2, P.m2 / P.m1);
        if (!P.twoFluidTracer) {
            std::printf("  note: species tag OFF -> all particles use m1 (single-fluid mass mode).\n");
        }
        std::printf("  caveat: dPy and Couette wall-momentum diagnostics are still unit-mass in this phase-1 patch.\n");
    }
    std::printf("Interfacial model: M1-demix=%s", P.immiscible ? "ON" : "OFF");
    if (P.immiscible) std::printf(" (chiColor=%.6g chiGrad0=%.6g)", P.chiColor, P.chiGrad0);
    std::printf(" | M2-capillary=%s", P.capillaryM2 ? "ON" : "OFF");
    if (P.capillaryM2) std::printf(" (sigmaLike=%.6g sigmaGrad0=%.6g kappaClip=%.6g)", P.sigmaLike, P.sigmaGrad0, P.sigmaKappaMax);
    std::printf("\n");

    if (mode_is_couette(P)) {
        float Ubot = -0.5f * P.couetteU;
        float Utop =  0.5f * P.couetteU;
        std::printf("Couette: Ubot=%.6g Utop=%.6g (dU=%.6g) | shear=%.6g | viscStart=%d viscReportStride=%d bins=%d\n",
            Ubot, Utop, P.couetteU, P.couetteU / P.Ly, P.viscStart, P.viscReportStride, P.viscBins);
        if (P.keepMeanFlow) {
            std::printf("  [note] keepMeanFlow=1 in Couette will bias the shear profile; consider --keepMeanFlow 0.\n");
        }
        // In Couette mode, cylinder parameters are ignored.
    } else if (mode_is_vk(P)) {
        std::printf("Cylinder: xc=%.3g yc=%.3g Rc=%.3g | wallModel=%s\n",
            P.xc, P.yc, P.Rc, P.useSolidCylinderParticles ? "solid-particles" : "bounce-back");
        if (P.useSolidCylinderParticles) {
            std::printf("  Solid particles (fixed wall markers): nSolid=%d spacing~%.3g Lr=%.3g dV=%.3g iters=%d maxDisp=%.3g\n",
                nSolid, solidSpacing, Lr, P.solidDV, P.solidRepulsionIters, maxDisp);
            std::printf("    options: softRepulsion=%d  hardProject=%d\n", P.solidUseRepulsion, P.solidUseProject);
            std::printf("    note: set --solidUseRepulsion 0 --solidUseProject 1 for a hard obstacle with zero soft repulsion bias.\n");
        } else {
            std::printf("  Bounce-back on analytic cylinder: bbEn=%.3g bbEt=%.3g\n", P.bbEn, P.bbEt);
            std::printf("    bbEt=-1 -> no-slip (tangent reversed), bbEt=+1 -> specular/free-slip (tangent preserved).\n");
        }
    }


    ensureDir(P.outDir);

    // Host init
    std::mt19937 rng(P.rngSeed);
    std::uniform_real_distribution<float> unifx(0.f, P.Lx);
    std::uniform_real_distribution<float> unify(0.f, P.Ly);
    std::normal_distribution<float> gauss(0.f, 1.f);

    std::vector<float> h_x(n), h_y(n), h_vx(n), h_vy(n);
    std::vector<unsigned char> h_tag;
    if (P.twoFluidTracer) h_tag.resize(n, (unsigned char)0);

    int nF1_init = 0, nF2_init = 0;
    for (int i=0;i<n;i++){
        float xi = unifx(rng);
        float yi = unify(rng);
        if (mode_is_vk(P)) {
            // avoid cylinder for wake simulations
            float dx = xi - P.xc;
            float dy = yi - P.yc;
            while (dx*dx + dy*dy < P.Rc*P.Rc) {
                xi = unifx(rng);
                yi = unify(rng);
                dx = xi - P.xc;
                dy = yi - P.yc;
            }
        }
        h_x[i] = xi;
        h_y[i] = yi;

        unsigned char s = 0;
        if (P.twoFluidTracer) {
            if (mode_is_kh(P)) {
                float p1 = 1.f; // default ambient species-1
                if (P.khInletJet) {
                    // In inlet-jet KH mode, start from a quiescent ambient entirely filled with fluid-1.
                    // Fluid-2 then penetrates only through the x=0 source injection during the time loop.
                    p1 = 1.f;
                } else if (!P.khJet) {
                    float zrho = (yi - P.khY0) / fmaxf(P.khDeltaRho, 1e-12f);
                    p1 = 0.5f * (1.f - tanhf(zrho));
                } else {
                    float dxp = xi - P.khJetX0;
                    float dyp = yi - P.khJetY0;
                    // periodic minimum-image distance in KH mode
                    dxp = periodic_delta(dxp, P.Lx);
                    dyp = mode_periodic_y(P) ? periodic_delta(dyp, P.Ly) : dyp;
                    float ex = 1.f + P.dropEllipse;
                    float ey = 1.f - P.dropEllipse;
                    float dxq = dxp / fmaxf(ex, 1e-6f);
                    float dyq = dyp / fmaxf(ey, 1e-6f);
                    float r = sqrtf(dxq*dxq + dyq*dyq);
                    float Rj = 0.5f * P.khJetD;
                    // species-2 in the core, species-1 in ambient
                    float zrho = (r - Rj) / fmaxf(P.khDeltaRho, 1e-12f);
                    float p2 = 0.5f * (1.f - tanhf(zrho));
                    p1 = 1.f - p2;
                }
                p1 = fminf(1.f, fmaxf(0.f, p1));
                float ur = unifx(rng) / fmaxf(P.Lx, 1e-12f); // reuse [0,1) from x RNG for Bernoulli draw
                s = (unsigned char)((ur < p1) ? 0 : 1);
            } else {
                s = (unsigned char)((yi < P.tracerSplitY) ? 0 : 1);
            }
            h_tag[i] = s;
            if (s == 0) nF1_init++; else nF2_init++;
        }
        float mi = 1.f;
        if (P.useSpeciesMass) {
            mi = (P.twoFluidTracer ? ((s == 0) ? P.m1 : P.m2) : P.m1);
        }
        float sigma = sqrtf(P.kBT / fmaxf(mi, 1e-12f));
        if (mode_is_kh(P)) {
            float ux0 = 0.f;
            float vyPert = 0.f;
            if (P.khInletJet) {
                // In inlet-jet KH mode, do NOT pre-fill the domain with a moving jet profile.
                // Start from a quiescent ambient (fluid-1) so the penetration of injected fluid-2 is visible.
                ux0 = 0.f;
                vyPert = 0.f;
            } else if (!P.khJet) {
                float zu = (yi - P.khY0) / fmaxf(P.khDeltaU, 1e-12f);
                ux0 = P.khU * tanhf(zu);
                float gy = (yi - P.khY0) / fmaxf(P.khSigmaY, 1e-12f);
                vyPert = P.khEpsVy * sinf(P.khKx * xi + P.khPhase) * expf(-0.5f * gy * gy);
            } else {
                float dxp = xi - P.khJetX0;
                float dyp = yi - P.khJetY0;
                dxp = periodic_delta(dxp, P.Lx);
                dyp = mode_periodic_y(P) ? periodic_delta(dyp, P.Ly) : dyp;
                float ex = 1.f + P.dropEllipse;
                    float ey = 1.f - P.dropEllipse;
                    float dxq = dxp / fmaxf(ex, 1e-6f);
                    float dyq = dyp / fmaxf(ey, 1e-6f);
                    float r = sqrtf(dxq*dxq + dyq*dyq);
                float Rj = 0.5f * P.khJetD;
                float zu = (r - Rj) / fmaxf(P.khDeltaU, 1e-12f);
                float S = 0.5f * (1.f - tanhf(zu)); // ~1 in jet core, ~0 in ambient
                ux0 = P.khU * S;
                float gr = (r - Rj) / fmaxf(P.khSigmaY, 1e-12f);
                vyPert = P.khEpsVy * sinf(P.khKx * xi + P.khPhase) * expf(-0.5f * gr * gr);
            }
            h_vx[i] = ux0 + sigma * gauss(rng);
            h_vy[i] = vyPert + sigma * gauss(rng);
        } else {
            h_vx[i] = P.U0 + sigma * gauss(rng);
            h_vy[i] =        sigma * gauss(rng);
        }
    }
    if (P.twoFluidTracer) {
        std::printf("Initial tracer split: Nf1=%d (%.3f%%), Nf2=%d (%.3f%%)\n",
            nF1_init, 100.0 * (double)nF1_init / (double)n,
            nF2_init, 100.0 * (double)nF2_init / (double)n);
    }
    const double totalMassNominal = P.useSpeciesMass
        ? (P.twoFluidTracer ? ((double)nF1_init * (double)P.m1 + (double)nF2_init * (double)P.m2)
                            : ((double)n * (double)P.m1))
        : (double)n;

    // Device arrays
    float *d_x=nullptr,*d_y=nullptr,*d_vx=nullptr,*d_vy=nullptr;
    unsigned char *d_tag=nullptr;
    int *d_cid=nullptr;
    int *d_cnt=nullptr;
    float *d_sumM=nullptr,*d_sumVx=nullptr,*d_sumVy=nullptr,*d_sumColorM=nullptr;
    float *d_ux=nullptr,*d_uy=nullptr,*d_cth=nullptr,*d_sth=nullptr;
    float *d_colorNx=nullptr,*d_colorNy=nullptr;
    float *d_capAx=nullptr,*d_capAy=nullptr;
    float *d_vxrel=nullptr,*d_vyrel=nullptr,*d_sumRel2=nullptr,*d_lambda=nullptr;

    cudaCheck(cudaMalloc(&d_x, n*sizeof(float)), "malloc x");
    cudaCheck(cudaMalloc(&d_y, n*sizeof(float)), "malloc y");
    cudaCheck(cudaMalloc(&d_vx, n*sizeof(float)), "malloc vx");
    cudaCheck(cudaMalloc(&d_vy, n*sizeof(float)), "malloc vy");
    if (P.twoFluidTracer) cudaCheck(cudaMalloc(&d_tag, n*sizeof(unsigned char)), "malloc tag");
    cudaCheck(cudaMalloc(&d_cid, n*sizeof(int)), "malloc cid");

    cudaCheck(cudaMalloc(&d_cnt, Nc*sizeof(int)), "malloc cnt");
    cudaCheck(cudaMalloc(&d_sumM, Nc*sizeof(float)), "malloc sumM");
    cudaCheck(cudaMalloc(&d_sumVx, Nc*sizeof(float)), "malloc sumVx");
    cudaCheck(cudaMalloc(&d_sumVy, Nc*sizeof(float)), "malloc sumVy");
    if ((P.immiscible || P.capillaryM2) && P.twoFluidTracer) cudaCheck(cudaMalloc(&d_sumColorM, Nc*sizeof(float)), "malloc sumColorM");

    cudaCheck(cudaMalloc(&d_ux, Nc*sizeof(float)), "malloc ux");
    cudaCheck(cudaMalloc(&d_uy, Nc*sizeof(float)), "malloc uy");
    cudaCheck(cudaMalloc(&d_cth, Nc*sizeof(float)), "malloc cth");
    cudaCheck(cudaMalloc(&d_sth, Nc*sizeof(float)), "malloc sth");
    if ((P.immiscible || P.capillaryM2) && P.twoFluidTracer) {
        cudaCheck(cudaMalloc(&d_colorNx, Nc*sizeof(float)), "malloc colorNx");
        cudaCheck(cudaMalloc(&d_colorNy, Nc*sizeof(float)), "malloc colorNy");
    }
    if (P.capillaryM2 && P.twoFluidTracer) {
        cudaCheck(cudaMalloc(&d_capAx, Nc*sizeof(float)), "malloc capAx");
        cudaCheck(cudaMalloc(&d_capAy, Nc*sizeof(float)), "malloc capAy");
    }

    cudaCheck(cudaMalloc(&d_vxrel, n*sizeof(float)), "malloc vxrel");
    cudaCheck(cudaMalloc(&d_vyrel, n*sizeof(float)), "malloc vyrel");
    cudaCheck(cudaMalloc(&d_sumRel2, Nc*sizeof(float)), "malloc sumRel2");
    cudaCheck(cudaMalloc(&d_lambda, Nc*sizeof(float)), "malloc lambda");

    cudaCheck(cudaMemcpy(d_x, h_x.data(), n*sizeof(float), cudaMemcpyHostToDevice), "cpy x");
    cudaCheck(cudaMemcpy(d_y, h_y.data(), n*sizeof(float), cudaMemcpyHostToDevice), "cpy y");
    cudaCheck(cudaMemcpy(d_vx, h_vx.data(), n*sizeof(float), cudaMemcpyHostToDevice), "cpy vx");
    cudaCheck(cudaMemcpy(d_vy, h_vy.data(), n*sizeof(float), cudaMemcpyHostToDevice), "cpy vy");
    if (P.twoFluidTracer) cudaCheck(cudaMemcpy(d_tag, h_tag.data(), n*sizeof(unsigned char), cudaMemcpyHostToDevice), "cpy tag");

    // Reduction buffers
    const int threads = 256;
    const int blocksN = (n + threads - 1) / threads;
    double *d_partial=nullptr;
    cudaCheck(cudaMalloc(&d_partial, blocksN*sizeof(double)), "malloc partial");
    std::vector<double> h_partial(blocksN);

    // Momentum exchange accumulators (single floats on device, accumulated via atomicAdd)
// - dPy: for cylinder transverse impulse (used in VK mode for diagnostics)
// - dPx_bot/top: for Couette viscosity measurement (momentum flux at walls)
    float *d_dPy=nullptr;
    float *d_dPx_bot=nullptr, *d_dPx_top=nullptr;
    cudaCheck(cudaMalloc(&d_dPy, sizeof(float)), "malloc dPy");
    cudaCheck(cudaMalloc(&d_dPx_bot, sizeof(float)), "malloc dPx_bot");
    cudaCheck(cudaMalloc(&d_dPx_top, sizeof(float)), "malloc dPx_top");
    cudaCheck(cudaMemset(d_dPy, 0, sizeof(float)), "memset dPy");
    cudaCheck(cudaMemset(d_dPx_bot, 0, sizeof(float)), "memset dPx_bot");
    cudaCheck(cudaMemset(d_dPx_top, 0, sizeof(float)), "memset dPx_top");

    // Field buffers (dump)
    const int Nf = P.NxF * P.NyF;
    int *d_fcnt=nullptr;
    float *d_fsumUx=nullptr,*d_fsumUy=nullptr;
    int *d_fcntF1=nullptr, *d_fcntF2=nullptr;
    cudaCheck(cudaMalloc(&d_fcnt, Nf*sizeof(int)), "malloc fcnt");
    cudaCheck(cudaMalloc(&d_fsumUx, Nf*sizeof(float)), "malloc fsumUx");
    cudaCheck(cudaMalloc(&d_fsumUy, Nf*sizeof(float)), "malloc fsumUy");
    if (P.twoFluidTracer) {
        cudaCheck(cudaMalloc(&d_fcntF1, Nf*sizeof(int)), "malloc fcntF1");
        cudaCheck(cudaMalloc(&d_fcntF2, Nf*sizeof(int)), "malloc fcntF2");
    }

    // Couette 1D profile buffers (optional)
    int *d_pcnt=nullptr;
    float *d_psumUx=nullptr;
    if (mode_is_couette(P) && P.viscProfile) {
        cudaCheck(cudaMalloc(&d_pcnt, P.viscBins*sizeof(int)), "malloc pcnt");
        cudaCheck(cudaMalloc(&d_psumUx, P.viscBins*sizeof(float)), "malloc psumUx");
    }

    std::vector<int> h_fcnt(Nf);
    std::vector<int> h_fcntF1, h_fcntF2;
    if (P.twoFluidTracer) {
        h_fcntF1.resize(Nf);
        h_fcntF2.resize(Nf);
    }
    std::vector<float> h_Ux(Nf), h_Uy(Nf), h_fsumUx(Nf), h_fsumUy(Nf);

    // RNG for random shifts
    std::uniform_real_distribution<float> shiftDist(-0.5f*a0, 0.5f*a0);

    const float alpha = (float)(P.alphaDeg * M_PI / 180.0);

    // Diagnostics file
    std::ofstream diag(P.outDir + "/diagnostics.csv");
    diag << "it,E,meanUx,meanUy,vmax,dPy_dt\n";

    std::ofstream dropdiag;
    if (P.calibDrop) {
        dropdiag.open(P.outDir + "/dropcal_diag.csv");
        dropdiag << "it,t,xcm,ycm,A_drop,Req,cells_drop,n_in,n_out,p_in_id,p_out_id,dp_id,sigma_eff_id,cells_in,cells_out\n";
    }

    // Optional real-time visualization (GPU local averaging on a reduced grid)
    RealtimeVis vis;
    visInit(vis, P);

    // Optional Couette viscosity measurement
    std::ofstream visc;
    double pxBot_prev = 0.0, pxTop_prev = 0.0;
    double eta_sum = 0.0;
    int eta_n = 0;
    int viscInit = 0;
    if (mode_is_couette(P)) {
        visc.open(P.outDir + "/viscosity.csv");
        visc << "it,tau_top,tau_bot,eta,nu\n";
    }

    // Main loop
    for (uint32_t it=1; it <= (uint32_t)P.nSteps; ++it) {
        // 1) Streaming + boundary conditions
        float dPy = 0.f;
        if (mode_is_couette(P)) {
            // Periodic in x, solid moving walls in y
            streaming_xwrap_kernel<<<blocksN, threads>>>(d_x, d_y, d_vx, d_vy, n, P.dt, P.Lx);
            float Ubot = -0.5f * P.couetteU;
            float Utop =  0.5f * P.couetteU;
            couette_ywall_bounce_kernel<<<blocksN, threads>>>(d_y, d_vx, d_vy, n, P.Ly, Ubot, Utop, d_dPx_bot, d_dPx_top);
        } else if (mode_is_kh(P)) {
            // KH mode variants:
            // - standard KH: periodic x/y, no obstacle
            // - inlet-stripe jet: x-open with reinjection source at x~0, periodic y or no-slip y-walls (khWallY)
            if (P.khInletJet) {
                streaming_injectx_ywrap_stripejet_kernel<<<blocksN, threads>>>(
                    d_x, d_y, d_vx, d_vy, d_tag, n, P.dt, P.Lx, P.Ly,
                    a0, P.reinjectBackflow, P.injectRandomY, P.twoFluidTracer,
                    mode_periodic_y(P) ? 1 : 0,
                    P.khJetY0, P.khJetD, P.khU, P.khDeltaU, P.khDeltaRho,
                    P.rngSeed, it);
                if (!mode_periodic_y(P)) {
                    // Stronger no-slip anchoring for inlet-jet KH: reset tangential wall velocity to 0 on y-wall hits.
                    kh_ywall_reflect_zeroUx_kernel<<<blocksN, threads>>>(d_y, d_vx, d_vy, n, P.Ly, d_dPx_bot, d_dPx_top);
                }
            } else {
                if (mode_periodic_y(P)) {
                    streaming_wrap_kernel<<<blocksN, threads>>>(d_x, d_y, d_vx, d_vy, n, P.dt, P.Lx, P.Ly);
                } else {
                    streaming_xwrap_kernel<<<blocksN, threads>>>(d_x, d_y, d_vx, d_vy, n, P.dt, P.Lx);
                    couette_ywall_bounce_kernel<<<blocksN, threads>>>(d_y, d_vx, d_vy, n, P.Ly, 0.f, 0.f, d_dPx_bot, d_dPx_top);
                }
            }
            dPy = 0.f;
        } else {
            // VK mode: either legacy periodic x-wrap or open x with clean inlet injection.
            if (P.xInletInject) {
                streaming_injectx_ywrap_kernel<<<blocksN, threads>>>(
                    d_x, d_y, d_vx, d_vy, d_tag, n, P.dt, P.Lx, P.Ly,
                    a0, P.U0, P.reinjectBackflow, P.injectRandomY,
                    P.twoFluidTracer, P.tracerSplitY, P.rngSeed, it);
            } else {
                streaming_wrap_kernel<<<blocksN, threads>>>(d_x, d_y, d_vx, d_vy, n, P.dt, P.Lx, P.Ly);
            }

            // 2) Cylinder wall model
            cudaCheck(cudaMemset(d_dPy, 0, sizeof(float)), "memset dPy");
            if (P.useSolidCylinderParticles) {
                if (P.solidUseRepulsion && P.solidRepulsionIters > 0 &&
                    (maxDisp > 0.f) && (Lr > 0.f) &&
                    (P.solidDV != 0.f || maxDisp > 0.f)) {
                    for (int k=0;k<P.solidRepulsionIters;k++){
                        solid_cylinder_repulsion_kernel<<<blocksN, threads>>>(
                            d_x, d_y, d_vx, d_vy, n, P.Lx, P.Ly,
                            P.xc, P.yc, P.Rc, nSolid, Lr, P.solidDV, maxDisp, d_dPy);
                    }
                }
                if (P.solidUseProject) {
                    solid_cylinder_project_kernel<<<blocksN, threads>>>(
                        d_x, d_y, d_vx, d_vy, n, P.Lx, P.Ly, P.xc, P.yc, P.Rc, P.epsWall);
                }
            } else {
                // Bounce-back reflection on cylinder
                cylinder_bounceback_kernel<<<blocksN, threads>>>(
                    d_x, d_y, d_vx, d_vy, n, P.Lx, P.Ly,
                    P.xc, P.yc, P.Rc, P.epsWall, P.bbEn, P.bbEt, d_dPy);
            }
            cudaCheck(cudaMemcpy(&dPy, d_dPy, sizeof(float), cudaMemcpyDeviceToHost), "cpy dPy");
        }

        // 3) Cell ids with random shift
        float shiftx = shiftDist(rng);
        float shifty = shiftDist(rng);
        if (!mode_periodic_y(P)) {
            compute_cell_ids_kernel_couette<<<blocksN, threads>>>(d_x, d_y, d_cid, n, P.Lx, P.Ly, a0, P.Nx, P.Ny, shiftx, shifty);
        } else {
            compute_cell_ids_kernel<<<blocksN, threads>>>(d_x, d_y, d_cid, n, P.Lx, P.Ly, a0, P.Nx, P.Ny, shiftx, shifty);
        }

        // 4) Per-cell sums
        cudaCheck(cudaMemset(d_cnt, 0, Nc*sizeof(int)), "memset cnt");
        cudaCheck(cudaMemset(d_sumM, 0, Nc*sizeof(float)), "memset sumM");
        cudaCheck(cudaMemset(d_sumVx, 0, Nc*sizeof(float)), "memset sumPx");
        cudaCheck(cudaMemset(d_sumVy, 0, Nc*sizeof(float)), "memset sumPy");
        if (d_sumColorM) cudaCheck(cudaMemset(d_sumColorM, 0, Nc*sizeof(float)), "memset sumColorM");
        cell_sums_mass_kernel<<<blocksN, threads>>>(
            d_vx, d_vy, d_tag, d_cid, n, Nc, P.useSpeciesMass, P.m1, P.m2,
            d_cnt, d_sumM, d_sumVx, d_sumVy, d_sumColorM);

        // 5) Cell params (means + rotation)
        const int blocksC = (Nc + threads - 1) / threads;
        cell_params_kernel<<<blocksC, threads>>>(d_cnt, d_sumM, d_sumVx, d_sumVy, Nc, d_ux, d_uy, d_cth, d_sth, alpha, P.rngSeed, it);
        if ((P.immiscible || P.capillaryM2) && d_sumColorM && d_colorNx && d_colorNy) {
            float gradMinColor = 0.f;
            if (P.immiscible) gradMinColor = (gradMinColor > 0.f) ? fminf(gradMinColor, P.chiGrad0) : P.chiGrad0;
            if (P.capillaryM2) gradMinColor = (gradMinColor > 0.f) ? fminf(gradMinColor, P.sigmaGrad0) : P.sigmaGrad0;
            cell_color_normals_kernel<<<blocksC, threads>>>(d_cnt, d_sumM, d_sumColorM, P.Nx, P.Ny, mode_periodic_y(P) ? 1 : 0,
                                                            gradMinColor, d_colorNx, d_colorNy);
        }
        if (P.capillaryM2 && d_sumColorM && d_colorNx && d_colorNy && d_capAx && d_capAy) {
            cell_capillary_accel_kernel<<<blocksC, threads>>>(d_cnt, d_sumM, d_sumColorM, d_colorNx, d_colorNy,
                                                              P.Nx, P.Ny, mode_periodic_y(P) ? 1 : 0,
                                                              a0, P.sigmaLike, P.sigmaGrad0, P.sigmaKappaMax,
                                                              d_capAx, d_capAy);
        }

        // 6) Rotated relatives + sumRel2
        cudaCheck(cudaMemset(d_sumRel2, 0, Nc*sizeof(float)), "memset sumRel2");
        rel_rotate_and_sum_kernel<<<blocksN, threads>>>(
            d_vx, d_vy, d_tag, d_cid, d_ux, d_uy, d_cth, d_sth,
            d_sumM, d_sumColorM, d_colorNx, d_colorNy, (P.immiscible && P.twoFluidTracer) ? 1 : 0, P.chiColor,
            n, Nc, P.useSpeciesMass, P.m1, P.m2, d_vxrel, d_vyrel, d_sumRel2);

        // 7) Thermostat lambdas
        thermostat_lambda_kernel<<<blocksC, threads>>>(d_cnt, d_sumRel2, Nc, P.kBT, P.useThermostat, d_lambda);

        // 8) Apply collision
        apply_collision_kernel<<<blocksN, threads>>>(d_vx, d_vy, d_cid, d_ux, d_uy, d_lambda, d_vxrel, d_vyrel, n, Nc);

        // 8b) Phase M2 capillary-like kick (uses interface field from current positions/cells)
        if (P.capillaryM2 && d_capAx && d_capAy) {
            apply_cell_accel_kernel<<<blocksN, threads>>>(d_vx, d_vy, d_cid, d_capAx, d_capAy, n, Nc, P.dt);
        }

        // 8c) External body force / wall wetting proxy (used e.g. in drop_wall preset)
        if (P.gravX != 0.f || P.gravY != 0.f ||
            ((P.wallWetBottom || P.wallWetTop) && (P.wallWetF1 != 0.f || P.wallWetF2 != 0.f))) {
            apply_body_wetting_kick_kernel<<<blocksN, threads>>>(
                d_vx, d_vy, d_y, d_tag, n, P.Ly, P.dt,
                P.gravX, P.gravY, P.twoFluidTracer,
                P.wallWetBottom, P.wallWetTop, P.wallWetRange, P.wallWetCut,
                P.wallWetF1, P.wallWetF2);
        }

        // 9) KeepMeanFlow (global mean)
        double meanUx=0.0, meanUy=0.0, E=0.0;
        if (P.keepMeanFlow || (P.logStride>0 && (it % (uint32_t)P.logStride==0)) ) {
            // meanUx
            reduce_sum_kernel<<<blocksN, threads, threads*sizeof(double)>>>(d_vx, d_partial, n);
            cudaCheck(cudaMemcpy(h_partial.data(), d_partial, blocksN*sizeof(double), cudaMemcpyDeviceToHost), "cpy partial vx");
            double sumUx = 0.0;
            for (double s : h_partial) sumUx += s;
            meanUx = sumUx / (double)n;

            // meanUy
            reduce_sum_kernel<<<blocksN, threads, threads*sizeof(double)>>>(d_vy, d_partial, n);
            cudaCheck(cudaMemcpy(h_partial.data(), d_partial, blocksN*sizeof(double), cudaMemcpyDeviceToHost), "cpy partial vy");
            double sumUy = 0.0;
            for (double s : h_partial) sumUy += s;
            meanUy = sumUy / (double)n;

            if (P.keepMeanFlow) {
                float addx = P.U0 - (float)meanUx;
                float addy = -(float)meanUy;
                add_constants_kernel<<<blocksN, threads>>>(d_vx, d_vy, n, addx, addy);
                meanUx = P.U0;
                meanUy = 0.0;
            }

            // Energy for diagnostics
            reduce_energy_kernel<<<blocksN, threads, threads*sizeof(double)>>>(d_vx, d_vy, d_partial, n);
            cudaCheck(cudaMemcpy(h_partial.data(), d_partial, blocksN*sizeof(double), cudaMemcpyDeviceToHost), "cpy partial E");
            for (double s : h_partial) E += s;
        }

        // vmax (optional, cheap-ish: copy a subset? We'll compute approximate on host every logStride by sampling)
        float vmax = 0.f;
        if (P.logStride > 0 && (it % (uint32_t)P.logStride == 0)) {
            // sample first 20000 particles
            int ns = std::min(n, 20000);
            std::vector<float> tmpvx(ns), tmpvy(ns);
            cudaCheck(cudaMemcpy(tmpvx.data(), d_vx, ns*sizeof(float), cudaMemcpyDeviceToHost), "cpy vx sample");
            cudaCheck(cudaMemcpy(tmpvy.data(), d_vy, ns*sizeof(float), cudaMemcpyDeviceToHost), "cpy vy sample");
            for (int i=0;i<ns;i++){
                float s = hypotf(tmpvx[i], tmpvy[i]);
                if (s > vmax) vmax = s;
            }
            std::printf("[%6u] E=%10.4e  <ux>=%.6g  <uy>=%.6g  vmax~%.6g  dPy/dt=%.6g\n",
                it, E, meanUx, meanUy, vmax, (double)dPy / (double)P.dt);
        }

        // Write diagnostics
        if (P.logStride > 0 && (it % (uint32_t)P.logStride == 0)) {
            diag << it << "," << E << "," << meanUx << "," << meanUy << "," << vmax << "," << ((double)dPy / (double)P.dt) << "\n";
        }

        // Optional in-situ visualization (coarse-grid local averaging + smoothing, display only)
        visUpdateAndDraw(vis, P, d_x, d_y, d_vx, d_vy, d_tag, n, it);

        // Couette viscosity reporting (from momentum exchange at y-walls)
        if (mode_is_couette(P) && P.viscReportStride > 0 &&
            (it % (uint32_t)P.viscReportStride == 0) && (it >= (uint32_t)P.viscStart)) {

            float pxBot_f = 0.f, pxTop_f = 0.f;
            cudaCheck(cudaMemcpy(&pxBot_f, d_dPx_bot, sizeof(float), cudaMemcpyDeviceToHost), "cpy dPx_bot");
            cudaCheck(cudaMemcpy(&pxTop_f, d_dPx_top, sizeof(float), cudaMemcpyDeviceToHost), "cpy dPx_top");

            double pxBot = (double)pxBot_f;
            double pxTop = (double)pxTop_f;

            if (!viscInit) {
                // initialize windowed differencing after the transient
                pxBot_prev = pxBot;
                pxTop_prev = pxTop;
                viscInit = 1;
            } else {
                double dpxBot = pxBot - pxBot_prev; pxBot_prev = pxBot;
                double dpxTop = pxTop - pxTop_prev; pxTop_prev = pxTop;

                double dtwin = (double)P.viscReportStride * (double)P.dt;
                double tau_bot = (dpxBot / dtwin) / (double)P.Lx;
                double tau_top = (dpxTop / dtwin) / (double)P.Lx;

                double shear = (double)P.couetteU / (double)P.Ly;
                if (shear == 0.0) shear = 1.0;

                double eta = 0.5 * (std::fabs(tau_top) + std::fabs(tau_bot)) / shear;
                double rho = totalMassNominal / ((double)P.Lx * (double)P.Ly);
                double nu  = eta / rho;

                if (visc.is_open()) {
                    visc << it << "," << tau_top << "," << tau_bot << "," << eta << "," << nu << "\n";
                }
                eta_sum += eta;
                eta_n   += 1;

                if (P.logStride > 0 && (it % (uint32_t)P.logStride == 0)) {
                    std::printf("  [couette] eta~%.6g  nu~%.6g\n", eta, nu);
                }
            }
        }

        // 10) Dump field
        if (P.writeCSV && (P.dumpStride > 0) && (it % (uint32_t)P.dumpStride == 0 || it == 1)) {
            cudaCheck(cudaMemset(d_fcnt, 0, Nf*sizeof(int)), "memset fcnt");
            cudaCheck(cudaMemset(d_fsumUx, 0, Nf*sizeof(float)), "memset fsumUx");
            cudaCheck(cudaMemset(d_fsumUy, 0, Nf*sizeof(float)), "memset fsumUy");
            field_sums_kernel<<<blocksN, threads>>>(d_x, d_y, d_vx, d_vy, n, P.Lx, P.Ly, P.NxF, P.NyF, d_fcnt, d_fsumUx, d_fsumUy);

            cudaCheck(cudaMemcpy(h_fcnt.data(), d_fcnt, Nf*sizeof(int), cudaMemcpyDeviceToHost), "cpy fcnt");
            cudaCheck(cudaMemcpy(h_fsumUx.data(), d_fsumUx, Nf*sizeof(float), cudaMemcpyDeviceToHost), "cpy fsumUx");
            cudaCheck(cudaMemcpy(h_fsumUy.data(), d_fsumUy, Nf*sizeof(float), cudaMemcpyDeviceToHost), "cpy fsumUy");

            // Compute mean per cell on host
            #pragma omp parallel for
            for (int c=0;c<Nf;c++){
                int k = h_fcnt[c];
                if (k > 0) {
                    h_Ux[c] = h_fsumUx[c] / (float)k;
                    h_Uy[c] = h_fsumUy[c] / (float)k;
                } else {
                    h_Ux[c] = 0.f;
                    h_Uy[c] = 0.f;
                }
            }

            const float RcMask = mode_has_cylinder(P) ? P.Rc : -1.f;
            std::ostringstream fn;
            fn << P.outDir << "/field_" << std::setw(6) << std::setfill('0') << it << ".csv";
            writeFieldCSV(fn.str(), h_Ux, h_Uy, h_fcnt, P.NxF, P.NyF, P.Lx, P.Ly, P.xc, P.yc, RcMask);

            if (P.twoFluidTracer) {
                cudaCheck(cudaMemset(d_fcntF1, 0, Nf*sizeof(int)), "memset fcntF1");
                cudaCheck(cudaMemset(d_fcntF2, 0, Nf*sizeof(int)), "memset fcntF2");
                tracer_field_counts_kernel<<<blocksN, threads>>>(
                    d_x, d_y, d_tag, n, P.Lx, P.Ly, P.NxF, P.NyF, d_fcntF1, d_fcntF2);

                cudaCheck(cudaMemcpy(h_fcntF1.data(), d_fcntF1, Nf*sizeof(int), cudaMemcpyDeviceToHost), "cpy fcntF1");
                cudaCheck(cudaMemcpy(h_fcntF2.data(), d_fcntF2, Nf*sizeof(int), cudaMemcpyDeviceToHost), "cpy fcntF2");

                std::ostringstream fnt;
                fnt << P.outDir << "/tracer_" << std::setw(6) << std::setfill('0') << it << ".csv";
                writeTracerCSV(fnt.str(), h_fcntF1, h_fcntF2, P.NxF, P.NyF, P.Lx, P.Ly, P.xc, P.yc, RcMask);

                if (P.useSpeciesMass) {
                    std::ostringstream fnm;
                    fnm << P.outDir << "/massfield_" << std::setw(6) << std::setfill('0') << it << ".csv";
                    writeMassFieldCSV(fnm.str(), h_fcnt, &h_fcntF1, &h_fcntF2,
                        P.NxF, P.NyF, P.Lx, P.Ly, P.m1, P.m2, P.xc, P.yc, RcMask);
                }

                if (P.calibDrop && dropdiag.is_open()) {
                    int dstride = (P.dropDiagStride > 0) ? P.dropDiagStride : P.dumpStride;
                    if (dstride <= 0 || (it % (uint32_t)dstride) == 0 || it == 1) {
                        DropCalibDiag DD = computeDropCalibDiagFromCounts(P, h_fcnt, h_fcntF2, P.NxF, P.NyF);
                        dropdiag << it << "," << ((double)it * (double)P.dt) << ","
                                 << DD.xcm << "," << DD.ycm << "," << DD.area << "," << DD.Req << "," << DD.cells_drop << ","
                                 << DD.n_in << "," << DD.n_out << "," << DD.p_in << "," << DD.p_out << "," << DD.dp << "," << DD.sigma_eff << ","
                                 << DD.cells_in << "," << DD.cells_out << "\n";
                    }
                }
            } else if (P.useSpeciesMass) {
                std::ostringstream fnm;
                fnm << P.outDir << "/massfield_" << std::setw(6) << std::setfill('0') << it << ".csv";
                writeMassFieldCSV(fnm.str(), h_fcnt, nullptr, nullptr,
                    P.NxF, P.NyF, P.Lx, P.Ly, P.m1, P.m2, P.xc, P.yc, RcMask);
            }
        }

        cudaCheck(cudaGetLastError(), "kernel execution");
    }


    // Post-processing for Couette viscosity mode
    if (mode_is_couette(P)) {
        if (eta_n > 0) {
            double eta_mean = eta_sum / (double)eta_n;
            double rho = totalMassNominal / ((double)P.Lx * (double)P.Ly);
            double nu_mean = eta_mean / rho;
            std::printf("Couette viscosity estimate (mean over %d windows): eta=%.6g  nu=%.6g\n", eta_n, eta_mean, nu_mean);
        } else {
            std::printf("Couette mode: not enough viscosity windows collected (increase steps or decrease viscReportStride).\n");
        }
        if (visc.is_open()) visc.close();

        if (P.viscProfile && d_pcnt && d_psumUx) {
            cudaCheck(cudaMemset(d_pcnt, 0, P.viscBins*sizeof(int)), "memset pcnt");
            cudaCheck(cudaMemset(d_psumUx, 0, P.viscBins*sizeof(float)), "memset psumUx");
            profile_y_sums_kernel<<<blocksN, threads>>>(d_y, d_vx, n, P.Ly, P.viscBins, d_pcnt, d_psumUx);

            std::vector<int>   h_pcnt(P.viscBins);
            std::vector<float> h_psum(P.viscBins), h_pUx(P.viscBins, 0.f);
            cudaCheck(cudaMemcpy(h_pcnt.data(), d_pcnt, P.viscBins*sizeof(int), cudaMemcpyDeviceToHost), "cpy pcnt");
            cudaCheck(cudaMemcpy(h_psum.data(), d_psumUx, P.viscBins*sizeof(float), cudaMemcpyDeviceToHost), "cpy psumUx");

            for (int i=0;i<P.viscBins;i++){
                int k = h_pcnt[i];
                h_pUx[i] = (k>0) ? (h_psum[i]/(float)k) : 0.f;
            }

            std::ofstream prof(P.outDir + "/couette_profile.csv");
            prof << "y,ux,count\n";
            for (int i=0;i<P.viscBins;i++){
                double y = ((double)i + 0.5) * (double)P.Ly / (double)P.viscBins;
                prof << y << "," << h_pUx[i] << "," << h_pcnt[i] << "\n";
            }
            prof.close();
            std::printf("Wrote Couette profile to %s/couette_profile.csv\n", P.outDir.c_str());
        }
    }

    diag.close();
    if (dropdiag.is_open()) dropdiag.close();

    visDestroy(vis);

    // Cleanup
    cudaFree(d_x); cudaFree(d_y); cudaFree(d_vx); cudaFree(d_vy);
    if (d_tag) cudaFree(d_tag);
    cudaFree(d_cid);
    cudaFree(d_cnt); cudaFree(d_sumM); cudaFree(d_sumVx); cudaFree(d_sumVy); if (d_sumColorM) cudaFree(d_sumColorM);
    cudaFree(d_ux); cudaFree(d_uy); cudaFree(d_cth); cudaFree(d_sth); if (d_colorNx) cudaFree(d_colorNx); if (d_colorNy) cudaFree(d_colorNy);
    if (d_capAx) cudaFree(d_capAx); if (d_capAy) cudaFree(d_capAy);
    cudaFree(d_vxrel); cudaFree(d_vyrel); cudaFree(d_sumRel2); cudaFree(d_lambda);
    cudaFree(d_partial);
    cudaFree(d_dPy);
    cudaFree(d_dPx_bot);
    cudaFree(d_dPx_top);
    if (d_pcnt) cudaFree(d_pcnt);
    if (d_psumUx) cudaFree(d_psumUx);
    cudaFree(d_fcnt); cudaFree(d_fsumUx); cudaFree(d_fsumUy);
    if (d_fcntF1) cudaFree(d_fcntF1);
    if (d_fcntF2) cudaFree(d_fcntF2);

    std::printf("Done. Outputs in %s\n", P.outDir.c_str());
    return 0;
}
