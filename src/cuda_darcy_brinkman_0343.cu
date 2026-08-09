#include "cuda_darcy_brinkman_0343.h"

#include "cuda_shared_particle_state_0251.h"

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
#include <iostream>
#include <stdexcept>
#include <sstream>
#include <string>
#include <vector>

namespace mpcd {

#if defined(MPCD_ENABLE_CUDA_DARCY_BRINKMAN_0343) && defined(MPCD_ENABLE_CUDA_PARTICLE_STATE)
namespace {

using Clock0343 = std::chrono::steady_clock;

struct DarcyWorkspace0343 {
    int nx = 0;
    int ny = 0;
    double* d_mass = nullptr;
    double* d_mx = nullptr;
    double* d_my = nullptr;
    double* d_sums = nullptr; // 10 doubles: legacy 0..7 plus force 8..9
    float* d_chi = nullptr;
    float* d_alpha = nullptr;
    float* d_lambda = nullptr;
    float* d_normalX = nullptr;
    float* d_normalY = nullptr;
    std::string fieldSignature;
};

DarcyWorkspace0343& workspace_0343() {
    static DarcyWorkspace0343 w;
    return w;
}

void free_workspace_0343(DarcyWorkspace0343& w) {
    cudaFree(w.d_mass);
    cudaFree(w.d_mx);
    cudaFree(w.d_my);
    cudaFree(w.d_sums);
    cudaFree(w.d_chi);
    cudaFree(w.d_alpha);
    cudaFree(w.d_lambda);
    cudaFree(w.d_normalX);
    cudaFree(w.d_normalY);
    w = DarcyWorkspace0343{};
}

void check_cuda_0343(cudaError_t err, const char* what) {
    if (err != cudaSuccess) {
        throw std::runtime_error(std::string("cuda_darcy_brinkman_0343: ") + what + ": " + cudaGetErrorString(err));
    }
}

bool ensure_workspace_0343(DarcyWorkspace0343& w, int nx, int ny) {
    if (nx <= 0 || ny <= 0) return false;
    if (w.nx == nx && w.ny == ny && w.d_mass && w.d_mx && w.d_my && w.d_sums &&
        w.d_chi && w.d_alpha && w.d_lambda && w.d_normalX && w.d_normalY) return true;
    free_workspace_0343(w);
    w.nx = nx;
    w.ny = ny;
    const std::size_t ncell = static_cast<std::size_t>(nx) * static_cast<std::size_t>(ny);
    bool ok = true;
    ok = ok && cudaMalloc(&w.d_mass, ncell * sizeof(double)) == cudaSuccess;
    ok = ok && cudaMalloc(&w.d_mx, ncell * sizeof(double)) == cudaSuccess;
    ok = ok && cudaMalloc(&w.d_my, ncell * sizeof(double)) == cudaSuccess;
    ok = ok && cudaMalloc(&w.d_sums, 10u * sizeof(double)) == cudaSuccess;
    ok = ok && cudaMalloc(&w.d_chi, ncell * sizeof(float)) == cudaSuccess;
    ok = ok && cudaMalloc(&w.d_alpha, ncell * sizeof(float)) == cudaSuccess;
    ok = ok && cudaMalloc(&w.d_lambda, ncell * sizeof(float)) == cudaSuccess;
    ok = ok && cudaMalloc(&w.d_normalX, ncell * sizeof(float)) == cudaSuccess;
    ok = ok && cudaMalloc(&w.d_normalY, ncell * sizeof(float)) == cudaSuccess;
    if (!ok) {
        free_workspace_0343(w);
        return false;
    }
    return true;
}

bool env_truthy_0343(const char* name) {
    const char* v = std::getenv(name);
    if (v == nullptr || *v == '\0') return false;
    const std::string s(v);
    return !(s == "0" || s == "false" || s == "FALSE" || s == "off" || s == "OFF" || s == "no" || s == "NO");
}

double seconds_since_0343(Clock0343::time_point t0) {
    return std::chrono::duration<double>(Clock0343::now() - t0).count();
}

int chi_mode_code_0343(const std::string& mode) {
    if (mode == "uniform") return 0;
    if (mode == "circle" || mode == "cylinder") return 1;
    if (mode == "box" || mode == "rectangle") return 2;
    if (mode == "file") return 3;
    return -1;
}

__device__ double smoothstep_dev_0343(double t) {
    t = fmin(1.0, fmax(0.0, t));
    return t * t * (3.0 - 2.0 * t);
}

__device__ double chi_at_cell_dev_0343(int ix, int iy,
                                       int nx, int ny,
                                       double Lx, double Ly,
                                       int mode,
                                       double uniformChi,
                                       double circleCx, double circleCy, double circleR,
                                       double boxXMin, double boxXMax,
                                       double boxYMin, double boxYMax,
                                       double interfaceWidth) {
    const double x = (static_cast<double>(ix) + 0.5) * Lx / static_cast<double>(max(1, nx));
    const double y = (static_cast<double>(iy) + 0.5) * Ly / static_cast<double>(max(1, ny));
    double chi = uniformChi;
    if (mode == 1) {
        const double d = sqrt((x - circleCx) * (x - circleCx) + (y - circleCy) * (y - circleCy));
        if (interfaceWidth > 0.0) {
            chi = smoothstep_dev_0343((d - circleR) / interfaceWidth);
        } else {
            chi = d <= circleR ? 0.0 : 1.0;
        }
    } else if (mode == 2) {
        const double dx = fmax(fmax(boxXMin - x, x - boxXMax), 0.0);
        const double dy = fmax(fmax(boxYMin - y, y - boxYMax), 0.0);
        const double outsideDist = sqrt(dx * dx + dy * dy);
        const bool inside = (x >= boxXMin && x <= boxXMax && y >= boxYMin && y <= boxYMax);
        if (interfaceWidth > 0.0) {
            chi = inside ? smoothstep_dev_0343(outsideDist / interfaceWidth) : 1.0;
        } else {
            chi = inside ? 0.0 : 1.0;
        }
    }
    return fmin(1.0, fmax(0.0, chi));
}

__device__ double alpha_from_chi_dev_0343(double chi, double alphaMin, double alphaMax, double q) {
    const double qq = fmax(q, 1.0e-300);
    const double frac = qq * (1.0 - chi) / (qq + chi);
    return alphaMin + (alphaMax - alphaMin) * frac;
}


__global__ void precompute_darcy_fields_kernel_0345(float* chiField,
                                                    float* alphaField,
                                                    float* lambdaField,
                                                    int nx, int ny,
                                                    double Lx, double Ly,
                                                    int chiMode,
                                                    double uniformChi,
                                                    double alphaMin,
                                                    double alphaMax,
                                                    double q,
                                                    double dt,
                                                    double circleCx,
                                                    double circleCy,
                                                    double circleR,
                                                    double boxXMin,
                                                    double boxXMax,
                                                    double boxYMin,
                                                    double boxYMax,
                                                    double interfaceWidth) {
    const int c = blockIdx.x * blockDim.x + threadIdx.x;
    const int ncell = nx * ny;
    if (c >= ncell) return;
    const int ix = c % nx;
    const int iy = c / nx;
    const double chi = chi_at_cell_dev_0343(ix, iy, nx, ny, Lx, Ly, chiMode, uniformChi,
                                            circleCx, circleCy, circleR,
                                            boxXMin, boxXMax, boxYMin, boxYMax, interfaceWidth);
    const double alpha = alpha_from_chi_dev_0343(chi, alphaMin, alphaMax, q);
    const double lambda = 1.0 - exp(-fmax(0.0, alpha) * fmax(0.0, dt));
    chiField[c] = static_cast<float>(chi);
    alphaField[c] = static_cast<float>(alpha);
    lambdaField[c] = static_cast<float>(lambda);
}

__global__ void precompute_alpha_lambda_from_chi_kernel_0345(float* chiField,
                                                             float* alphaField,
                                                             float* lambdaField,
                                                             int ncell,
                                                             double alphaMin,
                                                             double alphaMax,
                                                             double q,
                                                             double dt) {
    const int c = blockIdx.x * blockDim.x + threadIdx.x;
    if (c >= ncell) return;
    const double chi = fmin(1.0, fmax(0.0, static_cast<double>(chiField[c])));
    const double alpha = alpha_from_chi_dev_0343(chi, alphaMin, alphaMax, q);
    const double lambda = 1.0 - exp(-fmax(0.0, alpha) * fmax(0.0, dt));
    chiField[c] = static_cast<float>(chi);
    alphaField[c] = static_cast<float>(alpha);
    lambdaField[c] = static_cast<float>(lambda);
}

__global__ void precompute_darcy_normals_kernel_0419(const float* chiField,
                                                  float* normalX,
                                                  float* normalY,
                                                  int nx, int ny,
                                                  double Lx, double Ly) {
    const int c = blockIdx.x * blockDim.x + threadIdx.x;
    const int ncell = nx * ny;
    if (c >= ncell) return;
    const int ix = c % nx;
    const int iy = c / nx;
    const int ixm = max(0, ix - 1);
    const int ixp = min(nx - 1, ix + 1);
    const int iym = max(0, iy - 1);
    const int iyp = min(ny - 1, iy + 1);
    const double dx = Lx > 0.0 ? Lx / static_cast<double>(max(1, nx)) : 1.0;
    const double dy = Ly > 0.0 ? Ly / static_cast<double>(max(1, ny)) : 1.0;
    const double denomX = static_cast<double>(max(1, ixp - ixm)) * dx;
    const double denomY = static_cast<double>(max(1, iyp - iym)) * dy;
    const double gx = (static_cast<double>(chiField[iy * nx + ixp]) -
                       static_cast<double>(chiField[iy * nx + ixm])) / denomX;
    const double gy = (static_cast<double>(chiField[iyp * nx + ix]) -
                       static_cast<double>(chiField[iym * nx + ix])) / denomY;
    const double n = sqrt(gx * gx + gy * gy);
    if (n > 1.0e-30) {
        normalX[c] = static_cast<float>(gx / n); // grad chi points from solid chi=0 to fluid chi=1.
        normalY[c] = static_cast<float>(gy / n);
    } else {
        normalX[c] = 0.0f;
        normalY[c] = 0.0f;
    }
}

std::string darcy_field_signature_0345(const SimulationParams& p) {
    std::ostringstream ss;
    ss << std::setprecision(17)
       << p.Nx << '|' << p.Ny << '|' << p.Lx << '|' << p.Ly << '|'
       << p.darcyChiMode << '|' << p.darcyUniformChi << '|'
       << p.darcyChiFile << '|' << p.darcyChiNx << '|' << p.darcyChiNy << '|' << p.darcyChiFileFormat << '|'
       << p.darcyAlphaMin << '|' << p.darcyAlphaMax << '|' << p.darcyQ << '|' << p.dt << '|'
       << p.darcyCircleCx << '|' << p.darcyCircleCy << '|' << p.darcyCircleR << '|'
       << p.darcyBoxXMin << '|' << p.darcyBoxXMax << '|' << p.darcyBoxYMin << '|' << p.darcyBoxYMax << '|'
       << p.darcyInterfaceWidth;
    return ss.str();
}

std::vector<float> load_chi_file_host_0345(const SimulationParams& p, std::size_t ncell) {
    if (p.darcyChiFile.empty()) {
        throw std::runtime_error("cuda_darcy_brinkman_0345: darcyChiMode=file requires darcyChiFile");
    }
    std::ifstream in(p.darcyChiFile, std::ios::binary);
    if (!in) {
        throw std::runtime_error("cuda_darcy_brinkman_0345: cannot open darcyChiFile=" + p.darcyChiFile);
    }
    std::vector<float> chi(ncell, 1.0f);
    const std::string fmt = p.darcyChiFileFormat;
    if (fmt == "float64" || fmt == "f64" || fmt == "double") {
        std::vector<double> tmp(ncell);
        in.read(reinterpret_cast<char*>(tmp.data()), static_cast<std::streamsize>(tmp.size() * sizeof(double)));
        if (in.gcount() != static_cast<std::streamsize>(tmp.size() * sizeof(double))) {
            throw std::runtime_error("cuda_darcy_brinkman_0345: darcyChiFile float64 size mismatch");
        }
        char extra = 0;
        if (in.read(&extra, 1)) {
            throw std::runtime_error("cuda_darcy_brinkman_0345: darcyChiFile has trailing bytes");
        }
        for (std::size_t i = 0; i < ncell; ++i) {
            const double v = std::isfinite(tmp[i]) ? tmp[i] : 1.0;
            chi[i] = static_cast<float>(std::min(1.0, std::max(0.0, v)));
        }
    } else {
        in.read(reinterpret_cast<char*>(chi.data()), static_cast<std::streamsize>(chi.size() * sizeof(float)));
        if (in.gcount() != static_cast<std::streamsize>(chi.size() * sizeof(float))) {
            throw std::runtime_error("cuda_darcy_brinkman_0345: darcyChiFile float32 size mismatch");
        }
        char extra = 0;
        if (in.read(&extra, 1)) {
            throw std::runtime_error("cuda_darcy_brinkman_0345: darcyChiFile has trailing bytes");
        }
        for (float& v : chi) {
            const double d = std::isfinite(static_cast<double>(v)) ? static_cast<double>(v) : 1.0;
            v = static_cast<float>(std::min(1.0, std::max(0.0, d)));
        }
    }
    return chi;
}

bool ensure_darcy_fields_0345(DarcyWorkspace0343& w, const SimulationParams& p, int threads) {
    const int nx = p.Nx;
    const int ny = p.Ny;
    const int ncell = nx * ny;
    if (nx <= 0 || ny <= 0 || ncell <= 0) return false;
    const std::string sig = darcy_field_signature_0345(p);
    if (w.fieldSignature == sig && w.d_chi && w.d_alpha && w.d_lambda && w.d_normalX && w.d_normalY) return true;
    const int blocks = (ncell + threads - 1) / threads;
    const int chiMode = chi_mode_code_0343(p.darcyChiMode);
    if (chiMode == 3) {
        const auto chi = load_chi_file_host_0345(p, static_cast<std::size_t>(ncell));
        check_cuda_0343(cudaMemcpy(w.d_chi, chi.data(), chi.size() * sizeof(float), cudaMemcpyHostToDevice), "upload chi file");
        precompute_alpha_lambda_from_chi_kernel_0345<<<blocks, threads>>>(w.d_chi, w.d_alpha, w.d_lambda, ncell,
                                                                         p.darcyAlphaMin, p.darcyAlphaMax, p.darcyQ, p.dt);
    } else {
        precompute_darcy_fields_kernel_0345<<<blocks, threads>>>(w.d_chi, w.d_alpha, w.d_lambda,
                                                                 nx, ny, p.Lx, p.Ly,
                                                                 chiMode, p.darcyUniformChi,
                                                                 p.darcyAlphaMin, p.darcyAlphaMax, p.darcyQ, p.dt,
                                                                 p.darcyCircleCx, p.darcyCircleCy, p.darcyCircleR,
                                                                 p.darcyBoxXMin, p.darcyBoxXMax,
                                                                 p.darcyBoxYMin, p.darcyBoxYMax,
                                                                 p.darcyInterfaceWidth);
    }
    precompute_darcy_normals_kernel_0419<<<blocks, threads>>>(w.d_chi, w.d_normalX, w.d_normalY,
                                                              nx, ny, p.Lx, p.Ly);
    check_cuda_0343(cudaDeviceSynchronize(), "precompute darcy chi/alpha/lambda/normals");
    w.fieldSignature = sig;
    return true;
}

__global__ void reset_darcy_cells_kernel_0343(double* mass, double* mx, double* my, double* sums, int ncell) {
    const int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i < ncell) {
        mass[i] = 0.0;
        mx[i] = 0.0;
        my[i] = 0.0;
    }
    if (i < 10) sums[i] = 0.0;
}

__global__ void deposit_darcy_moments_kernel_0343(CudaParticleDeviceView pv,
                                                  int nx, int ny,
                                                  double Lx, double Ly,
                                                  double* massGrid,
                                                  double* mxGrid,
                                                  double* myGrid,
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
    ix = max(0, min(nx - 1, ix));
    iy = max(0, min(ny - 1, iy));
    const int c = iy * nx + ix;
    const double m = pv.mass ? pv.mass[i] : 1.0;
    atomicAdd(&massGrid[c], m);
    atomicAdd(&mxGrid[c], m * pv.vx[i]);
    atomicAdd(&myGrid[c], m * pv.vy[i]);
}

__global__ void diagnostics_darcy_cells_kernel_0343(const double* massGrid,
                                                    const double* mxGrid,
                                                    const double* myGrid,
                                                    double* sums,
                                                    int nx, int ny,
                                                    const float* chiField,
                                                    const float* alphaField,
                                                    double uSolidX,
                                                    double uSolidY,
                                                    int forceEnable) {
    const int c = blockIdx.x * blockDim.x + threadIdx.x;
    const int ncell = nx * ny;
    if (c >= ncell) return;
    const double chi = chiField ? static_cast<double>(chiField[c]) : 1.0;
    const double alpha = alphaField ? static_cast<double>(alphaField[c]) : 0.0;
    const double m = massGrid[c];
    double rel2 = 0.0;
    if (m > 0.0) {
        const double ux = mxGrid[c] / m;
        const double uy = myGrid[c] / m;
        const double rx = ux - uSolidX;
        const double ry = uy - uSolidY;
        rel2 = rx * rx + ry * ry;
        atomicAdd(&sums[0], m);
        atomicAdd(&sums[1], m * chi);
        atomicAdd(&sums[2], m * alpha);
        atomicAdd(&sums[3], m * alpha * rel2);
        atomicAdd(&sums[4], m * rel2);
        atomicAdd(&sums[5], m * (1.0 - chi) * (1.0 - chi) * rel2);
        if (forceEnable) {
            // Reaction proxy of the penalized material on the flow/geometry:
            // the Brinkman term on fluid is -m*alpha*(u-us); the opposite sign
            // is the integrated load proxy on the obstacle/material.
            atomicAdd(&sums[8], m * alpha * rx);
            atomicAdd(&sums[9], m * alpha * ry);
        }
    }
    atomicAdd(&sums[6], chi);
    atomicAdd(&sums[7], alpha);
}

__global__ void apply_darcy_kick_kernel_0343(CudaParticleDeviceView pv,
                                             const double* massGrid,
                                             const double* mxGrid,
                                             const double* myGrid,
                                             int nx, int ny,
                                             double Lx, double Ly,
                                             const float* lambdaField,
                                             double uSolidX,
                                             double uSolidY,
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
    ix = max(0, min(nx - 1, ix));
    iy = max(0, min(ny - 1, iy));
    const int c = iy * nx + ix;
    const double m = massGrid[c];
    if (!(m > 0.0)) return;
    const double ux = mxGrid[c] / m;
    const double uy = myGrid[c] / m;
    const double lambda = lambdaField ? static_cast<double>(lambdaField[c]) : 0.0;
    const double dvx = -lambda * (ux - uSolidX);
    const double dvy = -lambda * (uy - uSolidY);
    pv.vx[i] += dvx;
    pv.vy[i] += dvy;
}

__device__ unsigned long long splitmix64_0418(unsigned long long x) {
    x += 0x9E3779B97F4A7C15ull;
    x = (x ^ (x >> 30)) * 0xBF58476D1CE4E5B9ull;
    x = (x ^ (x >> 27)) * 0x94D049BB133111EBull;
    return x ^ (x >> 31);
}

__device__ double uniform01_0418(unsigned long long seed) {
    const unsigned long long z = splitmix64_0418(seed);
    return (static_cast<double>(z >> 11) + 0.5) * (1.0 / 9007199254740992.0);
}

__device__ double normal01_0418(unsigned long long seed0, unsigned long long seed1) {
    const double u1 = fmax(1.0e-300, uniform01_0418(seed0));
    const double u2 = uniform01_0418(seed1);
    const double pi = 3.141592653589793238462643383279502884;
    return sqrt(-2.0 * log(u1)) * cos(2.0 * pi * u2);
}

__global__ void apply_darcy_thermal_bath_kernel_0418(CudaParticleDeviceView pv,
                                                     int nx, int ny,
                                                     double Lx, double Ly,
                                                     const float* lambdaField,
                                                     double uSolidX,
                                                     double uSolidY,
                                                     double wallKBT,
                                                     unsigned long long step,
                                                     unsigned long long rngSeed,
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
    ix = max(0, min(nx - 1, ix));
    iy = max(0, min(ny - 1, iy));
    const int c = iy * nx + ix;
    const double strength = lambdaField ? fmin(1.0, fmax(0.0, static_cast<double>(lambdaField[c]))) : 0.0;
    if (!(strength > 0.0)) return;
    const double a = 1.0 - strength; // exp(-alpha dt), because lambdaField stores 1-exp(-alpha dt).
    const double m = (pv.mass && pv.mass[i] > 0.0) ? pv.mass[i] : 1.0;
    const double thermalVariance = fmax(0.0, 1.0 - a * a) * fmax(0.0, wallKBT) / m;
    const double sigma = sqrt(thermalVariance);
    const unsigned long long base = (step + 1ull) * 0xD1B54A32D192ED03ull ^
                                    (i + 1ull) * 0x9E3779B97F4A7C15ull ^
                                    (rngSeed + 1ull) * 0xBF58476D1CE4E5B9ull;
    const double nx0 = sigma > 0.0 ? normal01_0418(base ^ 0xA24BAED4963EE407ull, base ^ 0x9FB21C651E98DF25ull) : 0.0;
    const double ny0 = sigma > 0.0 ? normal01_0418(base ^ 0xC2B2AE3D27D4EB4Full, base ^ 0x165667B19E3779F9ull) : 0.0;
    pv.vx[i] = uSolidX + a * (pv.vx[i] - uSolidX) + sigma * nx0;
    pv.vy[i] = uSolidY + a * (pv.vy[i] - uSolidY) + sigma * ny0;
}

__global__ void apply_darcy_outward_bath_kernel_0419(CudaParticleDeviceView pv,
                                                     int nx, int ny,
                                                     double Lx, double Ly,
                                                     const float* lambdaField,
                                                     const float* normalXField,
                                                     const float* normalYField,
                                                     double uSolidX,
                                                     double uSolidY,
                                                     double wallKBT,
                                                     unsigned long long step,
                                                     unsigned long long rngSeed,
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
    ix = max(0, min(nx - 1, ix));
    iy = max(0, min(ny - 1, iy));
    const int c = iy * nx + ix;
    const double strength = lambdaField ? fmin(1.0, fmax(0.0, static_cast<double>(lambdaField[c]))) : 0.0;
    if (!(strength > 0.0)) return;
    const double a = 1.0 - strength; // exp(-alpha dt), because lambdaField stores 1-exp(-alpha dt).
    const double m = (pv.mass && pv.mass[i] > 0.0) ? pv.mass[i] : 1.0;
    const double thermalVariance = fmax(0.0, 1.0 - a * a) * fmax(0.0, wallKBT) / m;
    const double sigma = sqrt(thermalVariance);
    const unsigned long long base = (step + 1ull) * 0xA0761D6478BD642Full ^
                                    (i + 1ull) * 0xE7037ED1A0B428DBull ^
                                    (rngSeed + 1ull) * 0x8EBC6AF09C88C6E3ull;

    double nxn = normalXField ? static_cast<double>(normalXField[c]) : 0.0;
    double nyn = normalYField ? static_cast<double>(normalYField[c]) : 0.0;
    const double nn = sqrt(nxn * nxn + nyn * nyn);
    if (!(nn > 1.0e-12)) {
        const double gx = sigma > 0.0 ? normal01_0418(base ^ 0xA24BAED4963EE407ull, base ^ 0x9FB21C651E98DF25ull) : 0.0;
        const double gy = sigma > 0.0 ? normal01_0418(base ^ 0xC2B2AE3D27D4EB4Full, base ^ 0x165667B19E3779F9ull) : 0.0;
        pv.vx[i] = uSolidX + a * (pv.vx[i] - uSolidX) + sigma * gx;
        pv.vy[i] = uSolidY + a * (pv.vy[i] - uSolidY) + sigma * gy;
        return;
    }
    nxn /= nn;
    nyn /= nn;
    const double tx = -nyn;
    const double ty = nxn;
    const double relx = pv.vx[i] - uSolidX;
    const double rely = pv.vy[i] - uSolidY;
    const double vn = relx * nxn + rely * nyn;
    const double vt = relx * tx + rely * ty;
    const double gn = sigma > 0.0 ? normal01_0418(base ^ 0xD6E8FEB86659FD93ull, base ^ 0xCA5A826395121157ull) : 0.0;
    const double gt = sigma > 0.0 ? normal01_0418(base ^ 0x9E3779B97F4A7C15ull, base ^ 0xC6BC279692B5CC83ull) : 0.0;
    // Diffuse outward bath: the normal component is mirrored/re-emitted toward
    // increasing chi, i.e. from solid to fluid.  The tangential component is
    // OU-thermalized as in thermal_bath.
    const double vnTrial = a * vn + sigma * gn;
    const double vnOut = fabs(vnTrial);
    const double vtOut = a * vt + sigma * gt;
    pv.vx[i] = uSolidX + vnOut * nxn + vtOut * tx;
    pv.vy[i] = uSolidY + vnOut * nyn + vtOut * ty;
}

std::string darcy_csv_path_0343(const SimulationParams& params) {
    const std::string filename = params.darcyCostFilename.empty() ? std::string("darcy_cost_0343.csv") : params.darcyCostFilename;
    if (filename.find('/') != std::string::npos || filename.find('\\') != std::string::npos) {
        return filename;
    }
    return (std::filesystem::path(params.outputDir) / filename).string();
}

std::string topo_benchmark_csv_path_0348(const SimulationParams& params) {
    const std::string filename = params.topoBenchmarkFilename.empty() ? std::string("topo_benchmark_0348.csv") : params.topoBenchmarkFilename;
    if (filename.find('/') != std::string::npos || filename.find('\\') != std::string::npos) {
        return filename;
    }
    return (std::filesystem::path(params.outputDir) / filename).string();
}

bool topo_benchmark_write_step_0348(const SimulationParams& params, std::uint64_t step) {
    if (!params.topoBenchmarkEnable) return false;
    int every = params.topoBenchmarkEvery > 0 ? params.topoBenchmarkEvery : params.darcyCostEvery;
    if (every <= 0) return false;
    return (step % static_cast<std::uint64_t>(every) == 0u) ||
           (step == static_cast<std::uint64_t>(std::max(0, params.nSteps)));
}

void append_topo_benchmark_csv_0348(const SimulationParams& params,
                                    std::uint64_t step,
                                    double time,
                                    const CudaDarcyBrinkman0343Diagnostics& d) {
    if (!topo_benchmark_write_step_0348(params, step)) return;
    const std::string path = topo_benchmark_csv_path_0348(params);
    const std::filesystem::path p(path);
    if (!p.parent_path().empty()) {
        std::filesystem::create_directories(p.parent_path());
    }
    const bool writeHeader = !std::filesystem::exists(p) || std::filesystem::file_size(p) == 0u;
    std::ofstream out(path, std::ios::app);
    if (!out) return;
    out << std::setprecision(17);
    if (writeHeader) {
        out << "step,time,particles,activeFluid,numCells,mass,meanChi,meanAlpha,darcyPower,darcyPowerPerMass,meanSpeedRms,solidLeakRms,darcyForceX,darcyForceY,dragProxy,liftProxy,flowDirX,flowDirY,liftDirX,liftDirY,alphaMin,alphaMax,q,chiMode\n";
    }
    out << step << ',' << time << ',' << d.particles << ',' << d.activeFluid << ',' << d.numCells << ','
        << d.mass << ',' << d.meanChi << ',' << d.meanAlpha << ','
        << d.darcyPower << ',' << d.darcyPowerPerMass << ',' << d.meanSpeedRms << ',' << d.solidLeakRms << ','
        << d.darcyForceX << ',' << d.darcyForceY << ',' << d.dragProxy << ',' << d.liftProxy << ','
        << params.topoBenchmarkFlowDirX << ',' << params.topoBenchmarkFlowDirY << ','
        << params.topoBenchmarkLiftDirX << ',' << params.topoBenchmarkLiftDirY << ','
        << params.darcyAlphaMin << ',' << params.darcyAlphaMax << ',' << params.darcyQ << ',' << params.darcyChiMode << '\n';
}


void append_darcy_csv_0343(const SimulationParams& params,
                           std::uint64_t step,
                           double time,
                           const CudaDarcyBrinkman0343Diagnostics& d) {
    if (params.darcyCostEvery <= 0) return;
    if (!(step % static_cast<std::uint64_t>(params.darcyCostEvery) == 0u || step == static_cast<std::uint64_t>(std::max(0, params.nSteps)))) return;
    const std::string path = darcy_csv_path_0343(params);
    const std::filesystem::path p(path);
    if (!p.parent_path().empty()) {
        std::filesystem::create_directories(p.parent_path());
    }
    const bool writeHeader = !std::filesystem::exists(p) || std::filesystem::file_size(p) == 0u;
    std::ofstream out(path, std::ios::app);
    if (!out) return;
    out << std::setprecision(17);
    if (writeHeader) {
        out << "step,time,particles,activeFluid,numCells,mass,fluidVolumeFraction,meanChi,meanAlpha,darcyPower,darcyPowerPerMass,meanSpeedRms,solidLeakRms,alphaMin,alphaMax,q,chiMode,speciesQ6Enable,q6ResidentInputFresh,particleUploadSkipped,q6GfPrestream\n";
    }
    out << step << ',' << time << ',' << d.particles << ',' << d.activeFluid << ',' << d.numCells << ','
        << d.mass << ',' << d.fluidVolumeFraction << ',' << d.meanChi << ',' << d.meanAlpha << ','
        << d.darcyPower << ',' << d.darcyPowerPerMass << ',' << d.meanSpeedRms << ',' << d.solidLeakRms << ','
        << params.darcyAlphaMin << ',' << params.darcyAlphaMax << ',' << params.darcyQ << ',' << params.darcyChiMode << ','
        << d.speciesQ6Enable << ',' << d.q6ResidentInputFresh << ',' << d.particleUploadSkipped << ',' << d.q6GfPrestream << '\n';
}

} // namespace

bool cuda_darcy_brinkman_0343_device_chi_field(
    const SimulationParams& params,
    const float** deviceChi,
    int* nxOut,
    int* nyOut) {
    if (deviceChi) *deviceChi = nullptr;
    if (nxOut) *nxOut = 0;
    if (nyOut) *nyOut = 0;
    if (!params.darcyBrinkmanEnable) return false;
    const int nx = params.Nx;
    const int ny = params.Ny;
    if (nx <= 0 || ny <= 0) return false;
    const int chiMode = chi_mode_code_0343(params.darcyChiMode);
    if (chiMode < 0) return false;
    auto& w = workspace_0343();
    const int threads = std::max(32, params.darcyThreadsPerBlock);
    if (!ensure_workspace_0343(w, nx, ny)) return false;
    if (!ensure_darcy_fields_0345(w, params, threads)) return false;
    if (!w.d_chi) return false;
    if (deviceChi) *deviceChi = w.d_chi;
    if (nxOut) *nxOut = nx;
    if (nyOut) *nyOut = ny;
    return true;
}

CudaDarcyBrinkman0343Diagnostics try_apply_cuda_darcy_brinkman_0343(
    ParticleState& state,
    const SimulationParams& params,
    const CellGrid&,
    const FluidDomainBounds&,
    std::uint64_t step,
    double time,
    bool q6GfPrestream0493x7g) {
    CudaDarcyBrinkman0343Diagnostics d{};
    d.q6GfPrestream = q6GfPrestream0493x7g ? 1 : 0;
    d.requested = params.darcyBrinkmanEnable;
    if (!params.darcyBrinkmanEnable) return d;
    d.supported = true;
    d.speciesQ6Enable = params.speciesQ6Enable ? 1 : 0;
    const int nx = params.Nx;
    const int ny = params.Ny;
    const int ncell = nx * ny;
    d.numCells = ncell;
    if (nx <= 0 || ny <= 0 || !(params.Lx > 0.0) || !(params.Ly > 0.0) || !(params.dt >= 0.0)) {
        return d;
    }
    const int chiMode = chi_mode_code_0343(params.darcyChiMode);
    if (chiMode < 0) return d;

    auto& shared = cuda_shared_particle_state_0251();
    const bool sharedFreshBefore0343 = cuda_shared_particle_state_0251_is_fresh();
    const char* sharedWriter0343 = cuda_shared_particle_state_0251_last_writer();
    const bool q6ResidentWriter0343 =
        sharedWriter0343 != nullptr &&
        (std::strncmp(sharedWriter0343, "cuda_q6_resident_0400",
                      std::strlen("cuda_q6_resident_0400")) == 0 ||
         std::strcmp(sharedWriter0343, "cuda_q6_resident_thermostat_0400") == 0);
    d.q6ResidentInputFresh =
        (params.speciesQ6Enable && sharedFreshBefore0343 && q6ResidentWriter0343) ? 1 : 0;
    d.particleUploadSkipped = sharedFreshBefore0343 ? 1 : 0;
    if (!sharedFreshBefore0343) {
        CudaParticleStateDiagnostics uploadDiag{};
        shared.upload_all(state, &uploadDiag);
        cuda_shared_particle_state_0251_mark_fresh("cuda_darcy_brinkman_0343_upload");
    }
    CudaParticleDeviceView pv = shared.device_view();
    d.particles = pv.n;
    d.activeFluid = pv.nActiveFluid;
    if (pv.x == nullptr || pv.y == nullptr || pv.vx == nullptr || pv.vy == nullptr || pv.role == nullptr || pv.n == 0u) {
        return d;
    }

    auto& w = workspace_0343();
    if (!ensure_workspace_0343(w, nx, ny)) return d;
    const int threads = std::max(32, params.darcyThreadsPerBlock);
    if (!ensure_darcy_fields_0345(w, params, threads)) return d;
    const int cellBlocks = (ncell + threads - 1) / threads;
    const int particleBlocks = static_cast<int>((pv.n + static_cast<unsigned>(threads) - 1u) / static_cast<unsigned>(threads));
    const auto total0 = Clock0343::now();

    auto t0 = Clock0343::now();
    reset_darcy_cells_kernel_0343<<<cellBlocks, threads>>>(w.d_mass, w.d_mx, w.d_my, w.d_sums, ncell);
    check_cuda_0343(cudaDeviceSynchronize(), "reset cells");
    d.resetSeconds = seconds_since_0343(t0);

    t0 = Clock0343::now();
    deposit_darcy_moments_kernel_0343<<<particleBlocks, threads>>>(pv, nx, ny, params.Lx, params.Ly,
                                                                    w.d_mass, w.d_mx, w.d_my,
                                                                    static_cast<unsigned char>(kParticleRoleFluid));
    check_cuda_0343(cudaDeviceSynchronize(), "deposit moments");
    d.depositSeconds = seconds_since_0343(t0);

    const bool topoBenchThisStep = topo_benchmark_write_step_0348(params, step);
    const bool topoBenchForceThisStep = topoBenchThisStep && params.topoBenchmarkForceEnable;

    t0 = Clock0343::now();
    diagnostics_darcy_cells_kernel_0343<<<cellBlocks, threads>>>(w.d_mass, w.d_mx, w.d_my, w.d_sums,
                                                                 nx, ny, w.d_chi, w.d_alpha,
                                                                 params.darcyUSolidX, params.darcyUSolidY,
                                                                 topoBenchForceThisStep ? 1 : 0);
    check_cuda_0343(cudaDeviceSynchronize(), "diagnostics cells");
    double hSums[10]{};
    check_cuda_0343(cudaMemcpy(hSums, w.d_sums, sizeof(hSums), cudaMemcpyDeviceToHost), "copy diagnostics sums");
    d.diagnosticsSeconds = seconds_since_0343(t0);

    t0 = Clock0343::now();
    const bool thermalBath0418 = (params.darcyBrinkmanForcingMode == "thermal_bath" ||
                                  params.darcyBrinkmanForcingMode == "thermalbath" ||
                                  params.darcyBrinkmanForcingMode == "langevin" ||
                                  params.darcyBrinkmanForcingMode == "ou");
    const bool outwardBath0419 = (params.darcyBrinkmanForcingMode == "outward_bath" ||
                                  params.darcyBrinkmanForcingMode == "oriented_bath" ||
                                  params.darcyBrinkmanForcingMode == "oriented_thermal_bath" ||
                                  params.darcyBrinkmanForcingMode == "diffuse_reflection");
    const bool meanOutwardBath0420 = (params.darcyBrinkmanForcingMode == "mean_outward_bath" ||
                                      params.darcyBrinkmanForcingMode == "mean_oriented_bath" ||
                                      params.darcyBrinkmanForcingMode == "brinkman_outward_bath");
    if (meanOutwardBath0420) {
        const double wallKBT0418 = params.wallKBT > 0.0 ? params.wallKBT :
                                   (params.wallVpKBT > 0.0 ? params.wallVpKBT : params.kBT);
        apply_darcy_kick_kernel_0343<<<particleBlocks, threads>>>(pv, w.d_mass, w.d_mx, w.d_my,
                                                                  nx, ny, params.Lx, params.Ly,
                                                                  w.d_lambda,
                                                                  params.darcyUSolidX, params.darcyUSolidY,
                                                                  static_cast<unsigned char>(kParticleRoleFluid));
        check_cuda_0343(cudaDeviceSynchronize(), "apply mean kick before outward bath");
        apply_darcy_outward_bath_kernel_0419<<<particleBlocks, threads>>>(pv,
                                                                          nx, ny, params.Lx, params.Ly,
                                                                          w.d_lambda, w.d_normalX, w.d_normalY,
                                                                          params.darcyUSolidX, params.darcyUSolidY,
                                                                          wallKBT0418,
                                                                          static_cast<unsigned long long>(step),
                                                                          static_cast<unsigned long long>(params.rngSeed),
                                                                          static_cast<unsigned char>(kParticleRoleFluid));
        check_cuda_0343(cudaDeviceSynchronize(), "apply outward bath after mean kick");
    } else if (outwardBath0419) {
        const double wallKBT0418 = params.wallKBT > 0.0 ? params.wallKBT :
                                   (params.wallVpKBT > 0.0 ? params.wallVpKBT : params.kBT);
        apply_darcy_outward_bath_kernel_0419<<<particleBlocks, threads>>>(pv,
                                                                          nx, ny, params.Lx, params.Ly,
                                                                          w.d_lambda, w.d_normalX, w.d_normalY,
                                                                          params.darcyUSolidX, params.darcyUSolidY,
                                                                          wallKBT0418,
                                                                          static_cast<unsigned long long>(step),
                                                                          static_cast<unsigned long long>(params.rngSeed),
                                                                          static_cast<unsigned char>(kParticleRoleFluid));
        check_cuda_0343(cudaDeviceSynchronize(), "apply outward bath");
    } else if (thermalBath0418) {
        const double wallKBT0418 = params.wallKBT > 0.0 ? params.wallKBT :
                                   (params.wallVpKBT > 0.0 ? params.wallVpKBT : params.kBT);
        apply_darcy_thermal_bath_kernel_0418<<<particleBlocks, threads>>>(pv,
                                                                          nx, ny, params.Lx, params.Ly,
                                                                          w.d_lambda,
                                                                          params.darcyUSolidX, params.darcyUSolidY,
                                                                          wallKBT0418,
                                                                          static_cast<unsigned long long>(step),
                                                                          static_cast<unsigned long long>(params.rngSeed),
                                                                          static_cast<unsigned char>(kParticleRoleFluid));
        check_cuda_0343(cudaDeviceSynchronize(), "apply thermal bath");
    } else {
        apply_darcy_kick_kernel_0343<<<particleBlocks, threads>>>(pv, w.d_mass, w.d_mx, w.d_my,
                                                                  nx, ny, params.Lx, params.Ly,
                                                                  w.d_lambda,
                                                                  params.darcyUSolidX, params.darcyUSolidY,
                                                                  static_cast<unsigned char>(kParticleRoleFluid));
        check_cuda_0343(cudaDeviceSynchronize(), "apply kick");
    }
    d.applySeconds = seconds_since_0343(t0);

    cuda_shared_particle_state_0251_mark_fresh("cuda_darcy_brinkman_0343");
    d.mass = hSums[0];
    d.fluidVolumeFraction = hSums[0] > 0.0 ? hSums[1] / hSums[0] : 0.0;
    d.meanAlpha = hSums[0] > 0.0 ? hSums[2] / hSums[0] : 0.0;
    d.darcyPower = hSums[3];
    d.darcyPowerPerMass = hSums[0] > 0.0 ? hSums[3] / hSums[0] : 0.0;
    d.meanSpeedRms = hSums[0] > 0.0 ? std::sqrt(std::max(0.0, hSums[4] / hSums[0])) : 0.0;
    d.solidLeakRms = hSums[0] > 0.0 ? std::sqrt(std::max(0.0, hSums[5] / hSums[0])) : 0.0;
    d.meanChi = ncell > 0 ? hSums[6] / static_cast<double>(ncell) : 0.0;
    if (topoBenchForceThisStep) {
        d.darcyForceX = hSums[8];
        d.darcyForceY = hSums[9];
        if (params.topoBenchmarkDragLiftEnable) {
            const double dn = std::hypot(params.topoBenchmarkFlowDirX, params.topoBenchmarkFlowDirY);
            const double ln = std::hypot(params.topoBenchmarkLiftDirX, params.topoBenchmarkLiftDirY);
            const double dx = dn > 0.0 ? params.topoBenchmarkFlowDirX / dn : 1.0;
            const double dy = dn > 0.0 ? params.topoBenchmarkFlowDirY / dn : 0.0;
            const double lx = ln > 0.0 ? params.topoBenchmarkLiftDirX / ln : 0.0;
            const double ly = ln > 0.0 ? params.topoBenchmarkLiftDirY / ln : 1.0;
            d.dragProxy = d.darcyForceX * dx + d.darcyForceY * dy;
            d.liftProxy = d.darcyForceX * lx + d.darcyForceY * ly;
        }
    }
    d.totalSeconds = seconds_since_0343(total0);
    d.handled = true;
    d.applied = true;
    d.csvPath = darcy_csv_path_0343(params);
    append_darcy_csv_0343(params, step, time, d);
    append_topo_benchmark_csv_0348(params, step, time, d);
    if (env_truthy_0343("MPCD_CUDA_DARCY_BRINKMAN_LOG_0343") &&
        (params.darcyCostEvery <= 0 || step % static_cast<std::uint64_t>(std::max(1, params.darcyCostEvery)) == 0u)) {
        std::cerr << "\n[darcy0343] step=" << step
                  << " mass=" << d.mass
                  << " fluidFrac=" << d.fluidVolumeFraction
                  << " meanAlpha=" << d.meanAlpha
                  << " power=" << d.darcyPower
                  << " leak=" << d.solidLeakRms
                  << " total_s=" << d.totalSeconds << '\n';
    }
    return d;
}

#endif

} // namespace mpcd
