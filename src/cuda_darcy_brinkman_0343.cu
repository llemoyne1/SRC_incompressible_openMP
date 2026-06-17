#include "cuda_darcy_brinkman_0343.h"

#include "cuda_shared_particle_state_0251.h"

#include <cuda_runtime.h>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <stdexcept>
#include <string>

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
    double* d_sums = nullptr; // 8 doubles
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
    w = DarcyWorkspace0343{};
}

void check_cuda_0343(cudaError_t err, const char* what) {
    if (err != cudaSuccess) {
        throw std::runtime_error(std::string("cuda_darcy_brinkman_0343: ") + what + ": " + cudaGetErrorString(err));
    }
}

bool ensure_workspace_0343(DarcyWorkspace0343& w, int nx, int ny) {
    if (nx <= 0 || ny <= 0) return false;
    if (w.nx == nx && w.ny == ny && w.d_mass && w.d_mx && w.d_my && w.d_sums) return true;
    free_workspace_0343(w);
    w.nx = nx;
    w.ny = ny;
    const std::size_t ncell = static_cast<std::size_t>(nx) * static_cast<std::size_t>(ny);
    bool ok = true;
    ok = ok && cudaMalloc(&w.d_mass, ncell * sizeof(double)) == cudaSuccess;
    ok = ok && cudaMalloc(&w.d_mx, ncell * sizeof(double)) == cudaSuccess;
    ok = ok && cudaMalloc(&w.d_my, ncell * sizeof(double)) == cudaSuccess;
    ok = ok && cudaMalloc(&w.d_sums, 8u * sizeof(double)) == cudaSuccess;
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

__global__ void reset_darcy_cells_kernel_0343(double* mass, double* mx, double* my, double* sums, int ncell) {
    const int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i < ncell) {
        mass[i] = 0.0;
        mx[i] = 0.0;
        my[i] = 0.0;
    }
    if (i < 8) sums[i] = 0.0;
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
                                                    double Lx, double Ly,
                                                    int chiMode,
                                                    double uniformChi,
                                                    double alphaMin,
                                                    double alphaMax,
                                                    double q,
                                                    double uSolidX,
                                                    double uSolidY,
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
                                             int chiMode,
                                             double uniformChi,
                                             double alphaMin,
                                             double alphaMax,
                                             double q,
                                             double uSolidX,
                                             double uSolidY,
                                             double dt,
                                             double circleCx,
                                             double circleCy,
                                             double circleR,
                                             double boxXMin,
                                             double boxXMax,
                                             double boxYMin,
                                             double boxYMax,
                                             double interfaceWidth,
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
    const double chi = chi_at_cell_dev_0343(ix, iy, nx, ny, Lx, Ly, chiMode, uniformChi,
                                            circleCx, circleCy, circleR,
                                            boxXMin, boxXMax, boxYMin, boxYMax, interfaceWidth);
    const double alpha = alpha_from_chi_dev_0343(chi, alphaMin, alphaMax, q);
    const double lambda = 1.0 - exp(-fmax(0.0, alpha) * fmax(0.0, dt));
    const double dvx = -lambda * (ux - uSolidX);
    const double dvy = -lambda * (uy - uSolidY);
    pv.vx[i] += dvx;
    pv.vy[i] += dvy;
}

std::string darcy_csv_path_0343(const SimulationParams& params) {
    const std::string filename = params.darcyCostFilename.empty() ? std::string("darcy_cost_0343.csv") : params.darcyCostFilename;
    if (filename.find('/') != std::string::npos || filename.find('\\') != std::string::npos) {
        return filename;
    }
    return (std::filesystem::path(params.outputDir) / filename).string();
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
        out << "step,time,particles,activeFluid,numCells,mass,fluidVolumeFraction,meanChi,meanAlpha,darcyPower,darcyPowerPerMass,meanSpeedRms,solidLeakRms,alphaMin,alphaMax,q,chiMode\n";
    }
    out << step << ',' << time << ',' << d.particles << ',' << d.activeFluid << ',' << d.numCells << ','
        << d.mass << ',' << d.fluidVolumeFraction << ',' << d.meanChi << ',' << d.meanAlpha << ','
        << d.darcyPower << ',' << d.darcyPowerPerMass << ',' << d.meanSpeedRms << ',' << d.solidLeakRms << ','
        << params.darcyAlphaMin << ',' << params.darcyAlphaMax << ',' << params.darcyQ << ',' << params.darcyChiMode << '\n';
}

} // namespace

CudaDarcyBrinkman0343Diagnostics try_apply_cuda_darcy_brinkman_0343(
    ParticleState& state,
    const SimulationParams& params,
    const CellGrid&,
    const FluidDomainBounds&,
    std::uint64_t step,
    double time) {
    CudaDarcyBrinkman0343Diagnostics d{};
    d.requested = params.darcyBrinkmanEnable;
    if (!params.darcyBrinkmanEnable) return d;
    d.supported = true;
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
    if (!cuda_shared_particle_state_0251_is_fresh()) {
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

    t0 = Clock0343::now();
    diagnostics_darcy_cells_kernel_0343<<<cellBlocks, threads>>>(w.d_mass, w.d_mx, w.d_my, w.d_sums,
                                                                 nx, ny, params.Lx, params.Ly,
                                                                 chiMode, params.darcyUniformChi,
                                                                 params.darcyAlphaMin, params.darcyAlphaMax, params.darcyQ,
                                                                 params.darcyUSolidX, params.darcyUSolidY,
                                                                 params.darcyCircleCx, params.darcyCircleCy, params.darcyCircleR,
                                                                 params.darcyBoxXMin, params.darcyBoxXMax,
                                                                 params.darcyBoxYMin, params.darcyBoxYMax,
                                                                 params.darcyInterfaceWidth);
    check_cuda_0343(cudaDeviceSynchronize(), "diagnostics cells");
    double hSums[8]{};
    check_cuda_0343(cudaMemcpy(hSums, w.d_sums, sizeof(hSums), cudaMemcpyDeviceToHost), "copy diagnostics sums");
    d.diagnosticsSeconds = seconds_since_0343(t0);

    t0 = Clock0343::now();
    apply_darcy_kick_kernel_0343<<<particleBlocks, threads>>>(pv, w.d_mass, w.d_mx, w.d_my,
                                                              nx, ny, params.Lx, params.Ly,
                                                              chiMode, params.darcyUniformChi,
                                                              params.darcyAlphaMin, params.darcyAlphaMax, params.darcyQ,
                                                              params.darcyUSolidX, params.darcyUSolidY, params.dt,
                                                              params.darcyCircleCx, params.darcyCircleCy, params.darcyCircleR,
                                                              params.darcyBoxXMin, params.darcyBoxXMax,
                                                              params.darcyBoxYMin, params.darcyBoxYMax,
                                                              params.darcyInterfaceWidth,
                                                              static_cast<unsigned char>(kParticleRoleFluid));
    check_cuda_0343(cudaDeviceSynchronize(), "apply kick");
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
    d.totalSeconds = seconds_since_0343(total0);
    d.handled = true;
    d.applied = true;
    d.csvPath = darcy_csv_path_0343(params);
    append_darcy_csv_0343(params, step, time, d);
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
