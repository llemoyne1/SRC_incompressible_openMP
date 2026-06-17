#include "cuda_live_field_0337.h"

#include "cuda_shared_particle_state_0251.h"
#include "particle_state.h"

#include <cuda_runtime.h>

#include <algorithm>
#include <chrono>
#include <cstdlib>
#include <cctype>
#include <cmath>
#include <cstdint>
#include <fstream>
#include <iomanip>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>

namespace mpcd {

#if defined(MPCD_ENABLE_CUDA_PARTICLE_STATE)
namespace {

struct LiveFieldWorkspace0337 {
    int nx = 0;
    int ny = 0;
    double* d_mass = nullptr;
    double* d_ux = nullptr;
    double* d_uy = nullptr;
    double* d_scalar = nullptr;
    double* d_tmp = nullptr;
    unsigned char* d_rgba = nullptr;
    float* d_chi = nullptr;
    float* d_alpha = nullptr;
    std::string topoSignature;
};

LiveFieldWorkspace0337& workspace_0337() {
    static LiveFieldWorkspace0337 w;
    return w;
}

void free_workspace_0337(LiveFieldWorkspace0337& w) {
    cudaFree(w.d_mass); cudaFree(w.d_ux); cudaFree(w.d_uy);
    cudaFree(w.d_scalar); cudaFree(w.d_tmp); cudaFree(w.d_rgba);
    cudaFree(w.d_chi); cudaFree(w.d_alpha);
    w = LiveFieldWorkspace0337{};
}

bool ensure_workspace_0337(LiveFieldWorkspace0337& w, int nx, int ny) {
    if (nx <= 0 || ny <= 0) return false;
    if (w.nx == nx && w.ny == ny && w.d_mass && w.d_ux && w.d_uy && w.d_scalar && w.d_tmp && w.d_rgba && w.d_chi && w.d_alpha) return true;
    free_workspace_0337(w);
    w.nx = nx; w.ny = ny;
    const std::size_t n = static_cast<std::size_t>(nx) * static_cast<std::size_t>(ny);
    bool ok = true;
    ok = ok && cudaMalloc(&w.d_mass, n * sizeof(double)) == cudaSuccess;
    ok = ok && cudaMalloc(&w.d_ux, n * sizeof(double)) == cudaSuccess;
    ok = ok && cudaMalloc(&w.d_uy, n * sizeof(double)) == cudaSuccess;
    ok = ok && cudaMalloc(&w.d_scalar, n * sizeof(double)) == cudaSuccess;
    ok = ok && cudaMalloc(&w.d_tmp, n * sizeof(double)) == cudaSuccess;
    ok = ok && cudaMalloc(&w.d_rgba, 4u * n * sizeof(unsigned char)) == cudaSuccess;
    ok = ok && cudaMalloc(&w.d_chi, n * sizeof(float)) == cudaSuccess;
    ok = ok && cudaMalloc(&w.d_alpha, n * sizeof(float)) == cudaSuccess;
    if (!ok) { free_workspace_0337(w); return false; }
    return true;
}

int field_code_0337(const std::string& f) {
    if (f == "ux" || f == "vx") return 0;
    if (f == "uy" || f == "vy") return 1;
    if (f == "speed") return 2;
    if (f == "vorticity" || f == "omega" || f == "curl") return 3;
    if (f == "mass" || f == "density") return 4;
    if (f == "chi" || f == "topo_chi") return 5;
    if (f == "alpha" || f == "darcy_alpha") return 6;
    if (f == "darcy_power" || f == "darcy" || f == "brinkman_power") return 7;
    return 0;
}

bool signed_field_0337(int code) { return code == 0 || code == 1 || code == 3; }

double default_clip_0337(int code) {
    if (code == 0 || code == 1 || code == 2) return 0.2;
    if (code == 3) return 10.0;
    if (code == 5) return 1.0;
    if (code == 6 || code == 7) return 1.0;
    return 40.0;
}

int colormap_code_0342() {
    const char* raw = std::getenv("SRC_LIVE_VIS_COLORMAP");
    std::string cm = raw && *raw ? std::string(raw) : std::string("blue_red");
    std::transform(cm.begin(), cm.end(), cm.begin(), [](unsigned char c){ return static_cast<char>(std::tolower(c)); });
    if (cm == "gray" || cm == "grey" || cm == "grayscale" || cm == "greyscale") return 1;
    if (cm == "thermal" || cm == "heat" || cm == "hot") return 2;
    return 0;
}

__global__ void reset_field_kernel_0337(double* mass, double* ux, double* uy, double* scalar, int n) {
    const int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= n) return;
    mass[i] = 0.0; ux[i] = 0.0; uy[i] = 0.0; scalar[i] = 0.0;
}

__global__ void deposit_field_kernel_0337(CudaParticleDeviceView pv, int nx, int ny,
                                          double Lx, double Ly,
                                          double* massGrid, double* uxGrid, double* uyGrid,
                                          unsigned char fluidRole) {
    const unsigned long long i = static_cast<unsigned long long>(blockIdx.x) * blockDim.x + threadIdx.x;
    if (i >= pv.n) return;
    if (pv.role && pv.role[i] != fluidRole) return;
    const double invLx = Lx > 0.0 ? 1.0 / Lx : 1.0;
    const double invLy = Ly > 0.0 ? 1.0 / Ly : 1.0;
    double x = pv.x[i];
    double y = pv.y[i];
    if (!isfinite(x) || !isfinite(y)) return;
    x -= floor(x * invLx) * Lx;
    y -= floor(y * invLy) * Ly;
    int ix = static_cast<int>(floor(x * invLx * nx));
    int iy = static_cast<int>(floor(y * invLy * ny));
    ix = max(0, min(nx - 1, ix)); iy = max(0, min(ny - 1, iy));
    const int c = iy * nx + ix;
    const double m = pv.mass ? pv.mass[i] : 1.0;
    atomicAdd(&massGrid[c], m);
    atomicAdd(&uxGrid[c], m * pv.vx[i]);
    atomicAdd(&uyGrid[c], m * pv.vy[i]);
}

__global__ void finalize_scalar_kernel_0337(const double* mass, const double* ux, const double* uy,
                                            double* scalar, int nx, int ny, int fieldCode) {
    const int c = blockIdx.x * blockDim.x + threadIdx.x;
    const int n = nx * ny;
    if (c >= n) return;
    const double m = mass[c];
    const double u = m > 0.0 ? ux[c] / m : 0.0;
    const double v = m > 0.0 ? uy[c] / m : 0.0;
    if (fieldCode == 0) scalar[c] = u;
    else if (fieldCode == 1) scalar[c] = v;
    else if (fieldCode == 2) scalar[c] = sqrt(u*u + v*v);
    else if (fieldCode == 4) scalar[c] = m;
    else scalar[c] = 0.0;
}

__global__ void vorticity_kernel_0337(const double* mass, const double* ux, const double* uy,
                                      double* scalar, int nx, int ny, double Lx, double Ly) {
    const int c = blockIdx.x * blockDim.x + threadIdx.x;
    const int n = nx * ny;
    if (c >= n) return;
    const int ix = c % nx, iy = c / nx;
    const int xm = max(0, ix - 1), xp = min(nx - 1, ix + 1);
    const int ym = max(0, iy - 1), yp = min(ny - 1, iy + 1);
    const int cxm = iy * nx + xm, cxp = iy * nx + xp;
    const int cym = ym * nx + ix, cyp = yp * nx + ix;
    const double mxm = mass[cxm], mxp = mass[cxp], mym = mass[cym], myp = mass[cyp];
    const double uy_xm = mxm > 0.0 ? uy[cxm] / mxm : 0.0;
    const double uy_xp = mxp > 0.0 ? uy[cxp] / mxp : 0.0;
    const double ux_ym = mym > 0.0 ? ux[cym] / mym : 0.0;
    const double ux_yp = myp > 0.0 ? ux[cyp] / myp : 0.0;
    const double dx = Lx / static_cast<double>(max(1, nx));
    const double dy = Ly / static_cast<double>(max(1, ny));
    scalar[c] = (uy_xp - uy_xm) / (static_cast<double>(xp - xm) * dx + 1e-300)
              - (ux_yp - ux_ym) / (static_cast<double>(yp - ym) * dy + 1e-300);
}


__device__ double alpha_live_0345(double chi, double alphaMin, double alphaMax, double q) {
    const double qq = fmax(q, 1.0e-300);
    return alphaMin + (alphaMax - alphaMin) * qq * (1.0 - chi) / (qq + chi);
}

__global__ void precompute_live_alpha_from_chi_kernel_0345(float* chiField, float* alphaField,
                                                           int ncell, double alphaMin, double alphaMax, double q) {
    const int c = blockIdx.x * blockDim.x + threadIdx.x;
    if (c >= ncell) return;
    const double chi = fmin(1.0, fmax(0.0, static_cast<double>(chiField[c])));
    chiField[c] = static_cast<float>(chi);
    alphaField[c] = static_cast<float>(alpha_live_0345(chi, alphaMin, alphaMax, q));
}

std::string live_topo_signature_0345(const SimulationParams& p) {
    std::ostringstream ss;
    ss << std::setprecision(17) << p.Nx << '|' << p.Ny << '|'
       << p.darcyChiMode << '|' << p.darcyChiFile << '|' << p.darcyChiNx << '|' << p.darcyChiNy << '|'
       << p.darcyChiFileFormat << '|' << p.darcyAlphaMin << '|' << p.darcyAlphaMax << '|' << p.darcyQ;
    return ss.str();
}

std::vector<float> load_live_chi_file_0345(const SimulationParams& p, std::size_t ncell) {
    std::ifstream in(p.darcyChiFile, std::ios::binary);
    if (!in) return {};
    std::vector<float> chi(ncell, 1.0f);
    const std::string fmt = p.darcyChiFileFormat;
    if (fmt == "float64" || fmt == "f64" || fmt == "double") {
        std::vector<double> tmp(ncell);
        in.read(reinterpret_cast<char*>(tmp.data()), static_cast<std::streamsize>(tmp.size() * sizeof(double)));
        if (in.gcount() != static_cast<std::streamsize>(tmp.size() * sizeof(double))) return {};
        for (std::size_t i = 0; i < ncell; ++i) {
            const double v = std::isfinite(tmp[i]) ? tmp[i] : 1.0;
            chi[i] = static_cast<float>(std::min(1.0, std::max(0.0, v)));
        }
    } else {
        in.read(reinterpret_cast<char*>(chi.data()), static_cast<std::streamsize>(chi.size() * sizeof(float)));
        if (in.gcount() != static_cast<std::streamsize>(chi.size() * sizeof(float))) return {};
        for (float& v : chi) {
            const double d = std::isfinite(static_cast<double>(v)) ? static_cast<double>(v) : 1.0;
            v = static_cast<float>(std::min(1.0, std::max(0.0, d)));
        }
    }
    return chi;
}

bool ensure_live_topo_file_fields_0345(LiveFieldWorkspace0337& w, const SimulationParams& p, int threads) {
    if (p.darcyChiMode != "file") return true;
    const int ncell = p.Nx * p.Ny;
    if (ncell <= 0 || !w.d_chi || !w.d_alpha) return false;
    const std::string sig = live_topo_signature_0345(p);
    if (w.topoSignature == sig) return true;
    const auto chi = load_live_chi_file_0345(p, static_cast<std::size_t>(ncell));
    if (chi.size() != static_cast<std::size_t>(ncell)) return false;
    if (cudaMemcpy(w.d_chi, chi.data(), chi.size() * sizeof(float), cudaMemcpyHostToDevice) != cudaSuccess) return false;
    const int blocks = (ncell + threads - 1) / threads;
    precompute_live_alpha_from_chi_kernel_0345<<<blocks, threads>>>(w.d_chi, w.d_alpha, ncell,
                                                                   p.darcyAlphaMin, p.darcyAlphaMax, p.darcyQ);
    if (cudaDeviceSynchronize() != cudaSuccess) return false;
    w.topoSignature = sig;
    return true;
}

__device__ double smoothstep_dev_0343_live(double t) {
    t = fmin(1.0, fmax(0.0, t));
    return t * t * (3.0 - 2.0 * t);
}

__device__ double chi_live_0343(int ix, int iy, int nx, int ny, double Lx, double Ly,
                                int mode, double uniformChi,
                                double circleCx, double circleCy, double circleR,
                                double boxXMin, double boxXMax, double boxYMin, double boxYMax,
                                double interfaceWidth) {
    const double x = (static_cast<double>(ix) + 0.5) * Lx / static_cast<double>(max(1, nx));
    const double y = (static_cast<double>(iy) + 0.5) * Ly / static_cast<double>(max(1, ny));
    double chi = uniformChi;
    if (mode == 1) {
        const double d = sqrt((x - circleCx) * (x - circleCx) + (y - circleCy) * (y - circleCy));
        chi = interfaceWidth > 0.0 ? smoothstep_dev_0343_live((d - circleR) / interfaceWidth) : (d <= circleR ? 0.0 : 1.0);
    } else if (mode == 2) {
        const bool inside = (x >= boxXMin && x <= boxXMax && y >= boxYMin && y <= boxYMax);
        chi = inside ? 0.0 : 1.0;
    }
    return fmin(1.0, fmax(0.0, chi));
}

__device__ double alpha_live_0343(double chi, double alphaMin, double alphaMax, double q) {
    const double qq = fmax(q, 1.0e-300);
    return alphaMin + (alphaMax - alphaMin) * qq * (1.0 - chi) / (qq + chi);
}

__global__ void darcy_scalar_live_kernel_0343(const double* mass, const double* ux, const double* uy,
                                              double* scalar, int nx, int ny, double Lx, double Ly,
                                              int fieldCode, int chiMode, double uniformChi,
                                              const float* fileChiField,
                                              const float* fileAlphaField,
                                              double alphaMin, double alphaMax, double q,
                                              double uSolidX, double uSolidY,
                                              double circleCx, double circleCy, double circleR,
                                              double boxXMin, double boxXMax, double boxYMin, double boxYMax,
                                              double interfaceWidth) {
    const int c = blockIdx.x * blockDim.x + threadIdx.x;
    const int n = nx * ny;
    if (c >= n) return;
    const int ix = c % nx, iy = c / nx;
    const double chi = (chiMode == 3 && fileChiField) ? static_cast<double>(fileChiField[c])
                      : chi_live_0343(ix, iy, nx, ny, Lx, Ly, chiMode, uniformChi,
                                      circleCx, circleCy, circleR,
                                      boxXMin, boxXMax, boxYMin, boxYMax, interfaceWidth);
    const double alpha = (chiMode == 3 && fileAlphaField) ? static_cast<double>(fileAlphaField[c])
                        : alpha_live_0343(chi, alphaMin, alphaMax, q);
    if (fieldCode == 5) { scalar[c] = chi; return; }
    if (fieldCode == 6) { scalar[c] = alpha; return; }
    const double m = mass[c];
    const double u = m > 0.0 ? ux[c] / m : 0.0;
    const double v = m > 0.0 ? uy[c] / m : 0.0;
    const double rx = u - uSolidX;
    const double ry = v - uSolidY;
    scalar[c] = alpha * (rx * rx + ry * ry);
}

__global__ void smooth_scalar_kernel_0337(const double* in, double* out, int nx, int ny) {
    const int c = blockIdx.x * blockDim.x + threadIdx.x;
    const int n = nx * ny;
    if (c >= n) return;
    const int ix = c % nx, iy = c / nx;
    double acc = 0.0; int cnt = 0;
    for (int dy = -1; dy <= 1; ++dy) {
        const int yy = iy + dy;
        if (yy < 0 || yy >= ny) continue;
        for (int dx = -1; dx <= 1; ++dx) {
            const int xx = ix + dx;
            if (xx < 0 || xx >= nx) continue;
            acc += in[yy * nx + xx]; ++cnt;
        }
    }
    out[c] = cnt > 0 ? acc / static_cast<double>(cnt) : 0.0;
}

__device__ unsigned char clamp_u8_dev_0337(double x) {
    x = fmin(255.0, fmax(0.0, x));
    return static_cast<unsigned char>(llrint(x));
}

__device__ void map_color_dev_0342(double q, int signedField, int colormapCode,
                                   unsigned char& rr, unsigned char& gg, unsigned char& bb) {
    q = fmin(1.0, fmax(0.0, q));
    if (colormapCode == 1) {
        const unsigned char v = clamp_u8_dev_0337(255.0 * q);
        rr = v; gg = v; bb = v;
        return;
    }
    if (colormapCode == 2) {
        rr = clamp_u8_dev_0337(255.0 * fmin(1.0, fmax(0.0, 3.0*q - 1.0)));
        gg = clamp_u8_dev_0337(255.0 * fmin(1.0, fmax(0.0, 3.0*q - 2.0)));
        bb = clamp_u8_dev_0337(255.0 * fmin(1.0, fmax(0.0, 1.5 - 3.0*q)));
        return;
    }
    if (signedField) {
        const double mid = 1.0 - fabs(2.0*q - 1.0);
        rr = clamp_u8_dev_0337(255.0 * fmax(mid, fmax(0.0, 2.0*q - 1.0)));
        gg = clamp_u8_dev_0337(255.0 * mid);
        bb = clamp_u8_dev_0337(255.0 * fmax(mid, fmax(0.0, 1.0 - 2.0*q)));
    } else {
        rr = clamp_u8_dev_0337(255.0 * fmax(0.0, 2.0*q - 1.0));
        gg = clamp_u8_dev_0337(255.0 * (1.0 - fabs(2.0*q - 1.0)));
        bb = clamp_u8_dev_0337(255.0 * fmax(0.0, 1.0 - 2.0*q));
    }
}

__global__ void rgba_kernel_0337(const double* scalar, unsigned char* rgba,
                                 int nx, int ny, int signedField, int colormapCode,
                                 double scale, double gain,
                                 int overlayCircle, double Lx, double Ly,
                                 double cx, double cy, double r) {
    const int c = blockIdx.x * blockDim.x + threadIdx.x;
    const int n = nx * ny;
    if (c >= n) return;
    const int ix = c % nx, iy = c / nx;
    const double denom = scale > 1e-300 ? scale : 1.0;
    unsigned char rr=0, gg=0, bb=0;
    const double q = signedField
        ? (0.5 + 0.5 * gain * scalar[c] / denom)
        : (gain * scalar[c] / denom);
    map_color_dev_0342(q, signedField, colormapCode, rr, gg, bb);
    if (overlayCircle) {
        const double px = Lx / static_cast<double>(max(1, nx));
        const double py = Ly / static_cast<double>(max(1, ny));
        const double x = (static_cast<double>(ix) + 0.5) * px;
        const double y = (static_cast<double>(iy) + 0.5) * py;
        const double d = sqrt((x-cx)*(x-cx) + (y-cy)*(y-cy));
        const double thickness = 1.75 * fmax(px, py);
        if (fabs(d - r) <= thickness) { rr=0; gg=0; bb=0; }
    }
    const int o = 4*c;
    rgba[o+0] = rr; rgba[o+1] = gg; rgba[o+2] = bb; rgba[o+3] = 255;
}

double seconds_since_0337(std::chrono::steady_clock::time_point t0) {
    return std::chrono::duration<double>(std::chrono::steady_clock::now() - t0).count();
}

} // namespace

int chi_mode_code_live_0343(const std::string& mode) {
    if (mode == "uniform") return 0;
    if (mode == "circle" || mode == "cylinder") return 1;
    if (mode == "box" || mode == "rectangle") return 2;
    return 0;
}

bool cuda_live_field_render_shared_0337(std::vector<unsigned char>& rgba,
                                        int nx,
                                        int ny,
                                        const SimulationParams& params,
                                        const std::string& field,
                                        double clip,
                                        double gain,
                                        int smoothPasses,
                                        CudaLiveField0337Diagnostics* diag) {
    CudaLiveField0337Diagnostics local{};
    local.attempted = 1;
    local.nx = nx; local.ny = ny;
    const auto t0 = std::chrono::steady_clock::now();
    CudaParticleState& shared = cuda_shared_particle_state_0251();
    CudaParticleDeviceView pv = shared.device_view();
    if (pv.x == nullptr || pv.y == nullptr || pv.vx == nullptr || pv.vy == nullptr || pv.role == nullptr || pv.n == 0u) {
        if (diag) *diag = local; return false;
    }
    local.supported = 1; local.particles = pv.n; local.activeFluid = pv.nActiveFluid;
    auto& w = workspace_0337();
    if (!ensure_workspace_0337(w, nx, ny)) { if (diag) *diag = local; return false; }
    const int ncell = nx * ny;
    const int threads = 256;
    const int cellBlocks = (ncell + threads - 1) / threads;
    const int particleBlocks = static_cast<int>((pv.n + threads - 1u) / threads);
    auto ta = std::chrono::steady_clock::now();
    reset_field_kernel_0337<<<cellBlocks, threads>>>(w.d_mass, w.d_ux, w.d_uy, w.d_scalar, ncell);
    if (cudaDeviceSynchronize() != cudaSuccess) { if (diag) *diag = local; return false; }
    local.resetSeconds = seconds_since_0337(ta);
    ta = std::chrono::steady_clock::now();
    deposit_field_kernel_0337<<<particleBlocks, threads>>>(pv, nx, ny, params.Lx, params.Ly, w.d_mass, w.d_ux, w.d_uy, static_cast<unsigned char>(kParticleRoleFluid));
    if (cudaDeviceSynchronize() != cudaSuccess) { if (diag) *diag = local; return false; }
    local.depositSeconds = seconds_since_0337(ta);
    ta = std::chrono::steady_clock::now();
    const int fcode = field_code_0337(field);
    if (fcode == 3) {
        vorticity_kernel_0337<<<cellBlocks, threads>>>(w.d_mass, w.d_ux, w.d_uy, w.d_scalar, nx, ny, params.Lx, params.Ly);
    } else if (fcode == 5 || fcode == 6 || fcode == 7) {
        if (!ensure_live_topo_file_fields_0345(w, params, threads)) { if (diag) *diag = local; return false; }
        darcy_scalar_live_kernel_0343<<<cellBlocks, threads>>>(w.d_mass, w.d_ux, w.d_uy, w.d_scalar,
                                                               nx, ny, params.Lx, params.Ly, fcode,
                                                               chi_mode_code_live_0343(params.darcyChiMode), params.darcyUniformChi,
                                                               w.d_chi, w.d_alpha,
                                                               params.darcyAlphaMin, params.darcyAlphaMax, params.darcyQ,
                                                               params.darcyUSolidX, params.darcyUSolidY,
                                                               params.darcyCircleCx, params.darcyCircleCy, params.darcyCircleR,
                                                               params.darcyBoxXMin, params.darcyBoxXMax,
                                                               params.darcyBoxYMin, params.darcyBoxYMax,
                                                               params.darcyInterfaceWidth);
    } else {
        finalize_scalar_kernel_0337<<<cellBlocks, threads>>>(w.d_mass, w.d_ux, w.d_uy, w.d_scalar, nx, ny, fcode);
    }
    if (cudaDeviceSynchronize() != cudaSuccess) { if (diag) *diag = local; return false; }
    for (int pass = 0; pass < std::max(0, smoothPasses); ++pass) {
        smooth_scalar_kernel_0337<<<cellBlocks, threads>>>(w.d_scalar, w.d_tmp, nx, ny);
        if (cudaDeviceSynchronize() != cudaSuccess) { if (diag) *diag = local; return false; }
        std::swap(w.d_scalar, w.d_tmp);
    }
    const double scale = clip > 0.0 ? clip : default_clip_0337(fcode);
    rgba_kernel_0337<<<cellBlocks, threads>>>(w.d_scalar, w.d_rgba, nx, ny, signed_field_0337(fcode) ? 1 : 0, colormap_code_0342(), scale, std::max(1.0e-12, gain), params.immersedSolidEnable ? 1 : 0, params.Lx, params.Ly, params.immersedSolidCx, params.immersedSolidCy, params.immersedSolidR);
    if (cudaDeviceSynchronize() != cudaSuccess) { if (diag) *diag = local; return false; }
    local.finalizeSeconds = seconds_since_0337(ta);
    ta = std::chrono::steady_clock::now();
    rgba.resize(4u * static_cast<std::size_t>(ncell));
    if (cudaMemcpy(rgba.data(), w.d_rgba, rgba.size() * sizeof(unsigned char), cudaMemcpyDeviceToHost) != cudaSuccess) { if (diag) *diag = local; return false; }
    local.downloadSeconds = seconds_since_0337(ta);
    local.totalSeconds = seconds_since_0337(t0);
    local.rendered = 1;
    if (diag) *diag = local;
    return true;
}

#else

bool cuda_live_field_render_shared_0337(std::vector<unsigned char>&, int, int, const SimulationParams&, const std::string&, double, double, int, CudaLiveField0337Diagnostics* diag) {
    if (diag) diag->attempted = 1;
    return false;
}

#endif

} // namespace mpcd
