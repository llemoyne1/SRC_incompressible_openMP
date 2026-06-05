#include "src_collision.h"
#include "immersed_solid.h"

#ifdef MPCD_ENABLE_CUDA_CELL_MOMENTS
#include "cuda_cell_moments.h"
#endif

#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <cstddef>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <limits>
#include <random>
#include <stdexcept>
#include <string>
#include <vector>

#ifdef _OPENMP
#include <omp.h>
#endif

namespace mpcd {
namespace {

std::uint64_t splitmix64(std::uint64_t x) {
    x += 0x9e3779b97f4a7c15ULL;
    x = (x ^ (x >> 30U)) * 0xbf58476d1ce4e5b9ULL;
    x = (x ^ (x >> 27U)) * 0x94d049bb133111ebULL;
    return x ^ (x >> 31U);
}

int thread_count() {
#ifdef _OPENMP
    return omp_get_max_threads();
#else
    return 1;
#endif
}

int thread_id() {
#ifdef _OPENMP
    return omp_get_thread_num();
#else
    return 0;
#endif
}

double overlap_length(double a0, double a1, double b0, double b1) {
    const double lo = std::max(a0, b0);
    const double hi = std::min(a1, b1);
    return hi > lo ? hi - lo : 0.0;
}

double face_area_left(int ix, int iy, const CellGrid& grid, const GridShift& shift,
                      const SimulationParams& params, const FluidDomainBounds& domain) {
    if (is_x_periodic(params)) return 0.0;
    const double x0 = static_cast<double>(ix) * grid.dx - shift.sx;
    const double x1 = x0 + grid.dx;
    const double y0 = static_cast<double>(iy) * grid.dy - shift.sy;
    const double y1 = y0 + grid.dy;
    const double outsideX = overlap_length(x0, x1, domain.xMin - grid.dx, domain.xMin);
    const double insideY = is_y_periodic(params) ? grid.dy : overlap_length(y0, y1, domain.yMin, domain.yMax);
    return outsideX * insideY;
}

double face_area_right(int ix, int iy, const CellGrid& grid, const GridShift& shift,
                       const SimulationParams& params, const FluidDomainBounds& domain) {
    if (is_x_periodic(params)) return 0.0;
    const double x0 = static_cast<double>(ix) * grid.dx - shift.sx;
    const double x1 = x0 + grid.dx;
    const double y0 = static_cast<double>(iy) * grid.dy - shift.sy;
    const double y1 = y0 + grid.dy;
    const double outsideX = overlap_length(x0, x1, domain.xMax, domain.xMax + grid.dx);
    const double insideY = is_y_periodic(params) ? grid.dy : overlap_length(y0, y1, domain.yMin, domain.yMax);
    return outsideX * insideY;
}

double face_area_bottom(int ix, int iy, const CellGrid& grid, const GridShift& shift,
                        const SimulationParams& params, const FluidDomainBounds& domain) {
    if (is_y_periodic(params)) return 0.0;
    const double x0 = static_cast<double>(ix) * grid.dx - shift.sx;
    const double x1 = x0 + grid.dx;
    const double y0 = static_cast<double>(iy) * grid.dy - shift.sy;
    const double y1 = y0 + grid.dy;
    const double insideX = is_x_periodic(params) ? grid.dx : overlap_length(x0, x1, domain.xMin, domain.xMax);
    const double outsideY = overlap_length(y0, y1, domain.yMin - grid.dy, domain.yMin);
    return insideX * outsideY;
}

double face_area_top(int ix, int iy, const CellGrid& grid, const GridShift& shift,
                     const SimulationParams& params, const FluidDomainBounds& domain) {
    if (is_y_periodic(params)) return 0.0;
    const double x0 = static_cast<double>(ix) * grid.dx - shift.sx;
    const double x1 = x0 + grid.dx;
    const double y0 = static_cast<double>(iy) * grid.dy - shift.sy;
    const double y1 = y0 + grid.dy;
    const double insideX = is_x_periodic(params) ? grid.dx : overlap_length(x0, x1, domain.xMin, domain.xMax);
    const double outsideY = overlap_length(y0, y1, domain.yMax, domain.yMax + grid.dy);
    return insideX * outsideY;
}

void wall_velocity_for_face(const SimulationParams& params,
                            const FluidDomainBounds& domain,
                            const char* face,
                            double& ux,
                            double& uy) {
    const std::string f(face);
    if (f == "left") {
        ux = domain.vxMin + params.wallVpUxLeft;
        uy = params.wallVpUyLeft;
    } else if (f == "right") {
        ux = domain.vxMax + params.wallVpUxRight;
        uy = params.wallVpUyRight;
    } else if (f == "bottom") {
        ux = params.wallVpUxBottom;
        uy = domain.vyMin + params.wallVpUyBottom;
    } else if (f == "top") {
        ux = params.wallVpUxTop;
        uy = domain.vyMax + params.wallVpUyTop;
    } else {
        ux = 0.0;
        uy = 0.0;
    }
}

struct VirtualFaceContribution {
    double equivalentCount = 0.0;
    double mass = 0.0;
    double px = 0.0;
    double py = 0.0;
};

VirtualFaceContribution make_virtual_face_contribution(double faceArea,
                                                       double fullCellArea,
                                                       double gamma,
                                                       double accommodation,
                                                       double vpMass,
                                                       double kBT,
                                                       double thermalNoise,
                                                       double wallUx,
                                                       double wallUy,
                                                       std::uint64_t seed) {
    VirtualFaceContribution out{};
    if (!(faceArea > 0.0) || !(fullCellArea > 0.0)) return out;

    const double equivalentCount = accommodation * gamma * faceArea / fullCellArea;
    if (!(equivalentCount > 0.0)) return out;

    out.equivalentCount = equivalentCount;
    out.mass = equivalentCount * vpMass;
    out.px = out.mass * wallUx;
    out.py = out.mass * wallUy;

    if (thermalNoise > 0.0 && kBT > 0.0 && out.mass > 0.0) {
        std::mt19937_64 rng(seed);
        std::normal_distribution<double> normal(0.0, 1.0);
        const double sigmaP = thermalNoise * std::sqrt(out.mass * kBT);
        out.px += sigmaP * normal(rng);
        out.py += sigmaP * normal(rng);
    }

    return out;
}

bool face_has_wall_coupling(const std::string& mode, const SimulationParams& params) {
    // Recommended path: bcFace=solid activates the generic thermal wall.
    // Legacy path: wallVpEnable=true also couples specular/bounceback walls.
    return mode == "solid" || (params.wallVpEnable && (mode == "specular" || mode == "bounceback"));
}

void add_virtual_face_to_cell(const VirtualFaceContribution& v,
                              double& mass,
                              double& px,
                              double& py,
                              double& vpEquivalent,
                              double& vpMassTotal,
                              double& vpPxTotal,
                              double& vpPyTotal) {
    if (!(v.mass > 0.0)) return;
    mass += v.mass;
    px += v.px;
    py += v.py;
    vpEquivalent += v.equivalentCount;
    vpMassTotal += v.mass;
    vpPxTotal += v.px;
    vpPyTotal += v.py;
}


#ifdef MPCD_ENABLE_CUDA_CELL_MOMENTS
bool env_flag_enabled(const char* name, const bool fallback = false) {
    const char* v = std::getenv(name);
    if (v == nullptr || *v == '\0') return fallback;
    const std::string s(v);
    return !(s == "0" || s == "false" || s == "FALSE" ||
             s == "off" || s == "OFF" || s == "no" || s == "NO");
}

int env_int_value(const char* name, const int fallback) {
    const char* v = std::getenv(name);
    if (v == nullptr || *v == '\0') return fallback;
    try {
        return std::stoi(std::string(v));
    } catch (...) {
        return fallback;
    }
}

double env_double_value(const char* name, const double fallback) {
    const char* v = std::getenv(name);
    if (v == nullptr || *v == '\0') return fallback;
    try {
        return std::stod(std::string(v));
    } catch (...) {
        return fallback;
    }
}

struct CudaCellMomentsShadowRow {
    std::uint64_t step = 0u;
    std::uint64_t particlesVisited = 0u;
    std::uint64_t fluidParticles = 0u;
    int numCells = 0;
    double uploadSeconds = 0.0;
    double kernelSeconds = 0.0;
    double downloadSeconds = 0.0;
    double totalSeconds = 0.0;
    std::uint64_t cellIdMismatches = 0u;
    std::uint64_t countMismatches = 0u;
    double maxAbsMass = 0.0;
    double maxAbsPx = 0.0;
    double maxAbsPy = 0.0;
    double maxAbsUx = 0.0;
    double maxAbsUy = 0.0;
    double sumAbsMass = 0.0;
    double sumAbsPx = 0.0;
    double sumAbsPy = 0.0;
};

class CudaCellMomentsShadowAccumulator {
public:
    void set_output_dir(const std::string& dir) {
        if (!dir.empty()) outputDir_ = dir;
    }

    void add(const CudaCellMomentsShadowRow& row) {
        rows_.push_back(row);
    }

    ~CudaCellMomentsShadowAccumulator() {
        if (outputDir_.empty() || rows_.empty()) return;
        std::error_code ec;
        std::filesystem::create_directories(outputDir_, ec);
        const std::filesystem::path path = std::filesystem::path(outputDir_) / "cuda_cell_moments_shadow_0200.csv";
        std::ofstream out(path);
        if (!out) return;
        out << std::setprecision(17);
        out << "step,particlesVisited,fluidParticles,numCells,uploadSeconds,kernelSeconds,downloadSeconds,totalSeconds,cellIdMismatches,countMismatches,maxAbsMass,maxAbsPx,maxAbsPy,maxAbsUx,maxAbsUy,sumAbsMass,sumAbsPx,sumAbsPy\n";
        for (const auto& r : rows_) {
            out << r.step << ',' << r.particlesVisited << ',' << r.fluidParticles << ',' << r.numCells << ','
                << r.uploadSeconds << ',' << r.kernelSeconds << ',' << r.downloadSeconds << ',' << r.totalSeconds << ','
                << r.cellIdMismatches << ',' << r.countMismatches << ','
                << r.maxAbsMass << ',' << r.maxAbsPx << ',' << r.maxAbsPy << ','
                << r.maxAbsUx << ',' << r.maxAbsUy << ','
                << r.sumAbsMass << ',' << r.sumAbsPx << ',' << r.sumAbsPy << '\n';
        }
    }

private:
    std::string outputDir_;
    std::vector<CudaCellMomentsShadowRow> rows_;
};

CudaCellMomentsShadowAccumulator& cuda_cell_moments_shadow_accumulator() {
    static CudaCellMomentsShadowAccumulator acc;
    return acc;
}

struct CudaCellMomentsActiveRow {
    std::uint64_t step = 0u;
    std::uint64_t particlesVisited = 0u;
    std::uint64_t fluidParticles = 0u;
    int numCells = 0;
    double uploadSeconds = 0.0;
    double kernelSeconds = 0.0;
    double downloadSeconds = 0.0;
    double totalSeconds = 0.0;
    int reusedDeviceBuffers = 0;
    int allFluidFastPath = 0;
    int uniformMassFastPath = 0;
    int downloadedCellVelocities = 1;
};

class CudaCellMomentsActiveAccumulator {
public:
    void set_output_dir(const std::string& dir) {
        if (!dir.empty()) outputDir_ = dir;
    }

    void add(const CudaCellMomentsActiveRow& row) {
        rows_.push_back(row);
    }

    ~CudaCellMomentsActiveAccumulator() {
        if (outputDir_.empty() || rows_.empty()) return;
        std::error_code ec;
        std::filesystem::create_directories(outputDir_, ec);
        const std::filesystem::path path = std::filesystem::path(outputDir_) / "cuda_cell_moments_active_0202.csv";
        std::ofstream out(path);
        if (!out) return;
        out << std::setprecision(17);
        out << "step,particlesVisited,fluidParticles,numCells,uploadSeconds,kernelSeconds,downloadSeconds,totalSeconds,reusedDeviceBuffers,allFluidFastPath,uniformMassFastPath,downloadedCellVelocities\n";
        for (const auto& r : rows_) {
            out << r.step << ',' << r.particlesVisited << ',' << r.fluidParticles << ',' << r.numCells << ','
                << r.uploadSeconds << ',' << r.kernelSeconds << ',' << r.downloadSeconds << ',' << r.totalSeconds << ','
                << r.reusedDeviceBuffers << ',' << r.allFluidFastPath << ',' << r.uniformMassFastPath << ','
                << r.downloadedCellVelocities << '\n';
        }
    }

private:
    std::string outputDir_;
    std::vector<CudaCellMomentsActiveRow> rows_;
};

CudaCellMomentsActiveAccumulator& cuda_cell_moments_active_accumulator() {
    static CudaCellMomentsActiveAccumulator acc;
    return acc;
}

bool try_cuda_cell_moments_active(const ParticleState& state,
                                  const SimulationParams& params,
                                  const CellGrid& grid,
                                  const GridShift& shift,
                                  std::uint64_t step,
                                  CollisionWorkspace& ws,
                                  CudaCellMoments& cuda) {
    if (!env_flag_enabled("MPCD_CUDA_CELL_MOMENTS_USE", false)) return false;

    CudaCellMomentsDiagnostics diag{};
    CudaCellMomentsOptions opts{};
    opts.threadsPerBlock = std::max(32, env_int_value("MPCD_CUDA_CELL_MOMENTS_THREADS_PER_BLOCK", 256));
    opts.reuseDeviceBuffers = env_flag_enabled("MPCD_CUDA_CELL_MOMENTS_REUSE_BUFFERS", true);
    opts.computeCellVelocities = false;
    opts.downloadCellVelocities = false;
    opts.enableAllFluidFastPath = env_flag_enabled("MPCD_CUDA_CELL_MOMENTS_ALL_FLUID_FASTPATH", true);
    opts.enableUniformMassFastPath = env_flag_enabled("MPCD_CUDA_CELL_MOMENTS_UNIFORM_MASS_FASTPATH", true);
    cuda_deposit_cell_moments_atomic(state, grid, shift, params, cuda, &diag, opts);

    const std::size_t n = static_cast<std::size_t>(state.Np);
    const int nc = grid.numCells;
    if (cuda.cellId.size() != n || cuda.cellCount.size() != static_cast<std::size_t>(nc) ||
        cuda.cellMass.size() != static_cast<std::size_t>(nc) || cuda.cellPx.size() != static_cast<std::size_t>(nc) ||
        cuda.cellPy.size() != static_cast<std::size_t>(nc)) {
        throw std::runtime_error("CUDA cell moments active: incompatible CUDA output sizes");
    }

    ws.cellId = cuda.cellId;

    CudaCellMomentsActiveRow row{};
    row.step = step;
    row.particlesVisited = diag.particlesVisited;
    row.fluidParticles = diag.fluidParticles;
    row.numCells = diag.numCells;
    row.uploadSeconds = diag.uploadSeconds;
    row.kernelSeconds = diag.kernelSeconds;
    row.downloadSeconds = diag.downloadSeconds;
    row.totalSeconds = diag.totalSeconds;
    row.reusedDeviceBuffers = diag.reusedDeviceBuffers;
    row.allFluidFastPath = diag.allFluidFastPath;
    row.uniformMassFastPath = diag.uniformMassFastPath;
    row.downloadedCellVelocities = diag.downloadedCellVelocities;
    CudaCellMomentsActiveAccumulator& acc = cuda_cell_moments_active_accumulator();
    acc.set_output_dir(params.outputDir);
    acc.add(row);
    return true;
}

void maybe_validate_cuda_cell_moments_shadow(const ParticleState& state,
                                             const SimulationParams& params,
                                             const CellGrid& grid,
                                             const GridShift& shift,
                                             std::uint64_t step,
                                             const CollisionWorkspace& ws,
                                             const int nt) {
    if (!env_flag_enabled("MPCD_CUDA_CELL_MOMENTS_SHADOW", false)) return;
    const int every = std::max(1, env_int_value("MPCD_CUDA_CELL_MOMENTS_SHADOW_EVERY", 1));
    if ((step % static_cast<std::uint64_t>(every)) != 0u) return;

    CudaCellMomentsShadowAccumulator& acc = cuda_cell_moments_shadow_accumulator();
    acc.set_output_dir(params.outputDir);

    CudaCellMoments cuda{};
    CudaCellMomentsDiagnostics diag{};
    CudaCellMomentsOptions opts{};
    opts.threadsPerBlock = std::max(32, env_int_value("MPCD_CUDA_CELL_MOMENTS_THREADS_PER_BLOCK", 256));
    cuda_deposit_cell_moments_atomic(state, grid, shift, params, cuda, &diag, opts);

    const std::size_t n = static_cast<std::size_t>(state.Np);
    const int nc = grid.numCells;
    if (cuda.cellId.size() != n || cuda.cellCount.size() != static_cast<std::size_t>(nc)) {
        throw std::runtime_error("CUDA cell moments shadow: incompatible CUDA output sizes");
    }

    CudaCellMomentsShadowRow row{};
    row.step = step;
    row.particlesVisited = diag.particlesVisited;
    row.fluidParticles = diag.fluidParticles;
    row.numCells = diag.numCells;
    row.uploadSeconds = diag.uploadSeconds;
    row.kernelSeconds = diag.kernelSeconds;
    row.downloadSeconds = diag.downloadSeconds;
    row.totalSeconds = diag.totalSeconds;

    for (std::size_t i = 0; i < n; ++i) {
        if (ws.cellId[i] != cuda.cellId[i]) ++row.cellIdMismatches;
    }

    for (int c = 0; c < nc; ++c) {
        std::uint32_t count = 0u;
        double mass = 0.0;
        double px = 0.0;
        double py = 0.0;
        for (int t = 0; t < nt; ++t) {
            const std::size_t k = static_cast<std::size_t>(t * nc + c);
            count += ws.localCount[k];
            mass += ws.localMass[k];
            px += ws.localPx[k];
            py += ws.localPy[k];
        }
        const std::size_t kk = static_cast<std::size_t>(c);
        if (count != cuda.cellCount[kk]) ++row.countMismatches;
        const double ux = mass > 0.0 ? px / mass : 0.0;
        const double uy = mass > 0.0 ? py / mass : 0.0;
        const double dm = std::abs(mass - cuda.cellMass[kk]);
        const double dpx = std::abs(px - cuda.cellPx[kk]);
        const double dpy = std::abs(py - cuda.cellPy[kk]);
        const double dux = std::abs(ux - cuda.cellUx[kk]);
        const double duy = std::abs(uy - cuda.cellUy[kk]);
        row.maxAbsMass = std::max(row.maxAbsMass, dm);
        row.maxAbsPx = std::max(row.maxAbsPx, dpx);
        row.maxAbsPy = std::max(row.maxAbsPy, dpy);
        row.maxAbsUx = std::max(row.maxAbsUx, dux);
        row.maxAbsUy = std::max(row.maxAbsUy, duy);
        row.sumAbsMass += dm;
        row.sumAbsPx += dpx;
        row.sumAbsPy += dpy;
    }

    acc.add(row);

    const bool strict = env_flag_enabled("MPCD_CUDA_CELL_MOMENTS_SHADOW_STRICT", true);
    const double tol = env_double_value("MPCD_CUDA_CELL_MOMENTS_SHADOW_TOL", 1.0e-9);
    if (strict && (row.cellIdMismatches != 0u || row.countMismatches != 0u ||
                   row.maxAbsMass > tol || row.maxAbsPx > tol || row.maxAbsPy > tol ||
                   row.maxAbsUx > tol || row.maxAbsUy > tol)) {
        throw std::runtime_error("CUDA cell moments shadow mismatch: cellId=" +
                                 std::to_string(row.cellIdMismatches) +
                                 " count=" + std::to_string(row.countMismatches) +
                                 " maxAbsMass=" + std::to_string(row.maxAbsMass) +
                                 " maxAbsPx=" + std::to_string(row.maxAbsPx) +
                                 " maxAbsPy=" + std::to_string(row.maxAbsPy));
    }
}
#endif

} // namespace

GridShift sample_grid_shift(const SimulationParams& params, std::uint64_t step) {
    GridShift shift{};
    if (!params.gridShiftEnable) {
        return shift;
    }

    std::mt19937_64 rng(params.rngSeed ^ splitmix64(step));
    std::uniform_real_distribution<double> ux(-0.5 * params.Lx / static_cast<double>(params.Nx),
                                               0.5 * params.Lx / static_cast<double>(params.Nx));
    std::uniform_real_distribution<double> uy(-0.5 * params.Ly / static_cast<double>(params.Ny),
                                               0.5 * params.Ly / static_cast<double>(params.Ny));
    shift.sx = ux(rng);
    shift.sy = uy(rng);
    return shift;
}

void resize_collision_workspace(CollisionWorkspace& ws,
                                std::uint64_t numParticles,
                                int numCells,
                                int numThreads) {
    if (numCells <= 0) {
        throw std::runtime_error("resize_collision_workspace: invalid number of cells");
    }
    if (numThreads <= 0) {
        numThreads = 1;
    }

    const bool sameSize = ws.allocatedParticles == numParticles &&
                          ws.allocatedCells == numCells &&
                          ws.allocatedThreads == numThreads;
    if (!sameSize) {
        ws.allocatedParticles = numParticles;
        ws.allocatedCells = numCells;
        ws.allocatedThreads = numThreads;

        ws.cellId.assign(static_cast<std::size_t>(numParticles), 0);

        ws.cellCount.assign(static_cast<std::size_t>(numCells), 0u);
        ws.cellMass.assign(static_cast<std::size_t>(numCells), 0.0);
        ws.cellUx.assign(static_cast<std::size_t>(numCells), 0.0);
        ws.cellUy.assign(static_cast<std::size_t>(numCells), 0.0);

        const std::size_t localSize = static_cast<std::size_t>(numThreads * numCells);
        ws.localCount.assign(localSize, 0u);
        ws.localMass.assign(localSize, 0.0);
        ws.localPx.assign(localSize, 0.0);
        ws.localPy.assign(localSize, 0.0);

        ws.cosA.assign(static_cast<std::size_t>(numCells), 1.0);
        ws.sinA.assign(static_cast<std::size_t>(numCells), 0.0);
    }
}

CollisionDiagnostics src_collision_step(ParticleState& state,
                                        const SimulationParams& params,
                                        const CellGrid& grid,
                                        const FluidDomainBounds& domain,
                                        std::uint64_t step,
                                        CollisionWorkspace& ws) {
    validate_particle_state(state, "src_collision_step");

    const std::size_t n = static_cast<std::size_t>(state.Np);
    const ParticleRoleCounts roleCounts = count_particle_roles(state);
    const int nc = grid.numCells;
    if (nc <= 0) {
        throw std::runtime_error("src_collision_step: invalid number of cells");
    }

    const int nt = std::max(1, thread_count());
    resize_collision_workspace(ws, state.Np, nc, nt);

    CollisionDiagnostics diag{};
    diag.shift = sample_grid_shift(params, step);

    std::fill(ws.cellCount.begin(), ws.cellCount.end(), 0u);
    std::fill(ws.cellMass.begin(), ws.cellMass.end(), 0.0);
    std::fill(ws.cellUx.begin(), ws.cellUx.end(), 0.0);
    std::fill(ws.cellUy.begin(), ws.cellUy.end(), 0.0);
    std::fill(ws.cellId.begin(), ws.cellId.end(), -1);
    std::fill(ws.localCount.begin(), ws.localCount.end(), 0u);
    std::fill(ws.localMass.begin(), ws.localMass.end(), 0.0);
    std::fill(ws.localPx.begin(), ws.localPx.end(), 0.0);
    std::fill(ws.localPy.begin(), ws.localPy.end(), 0.0);

#ifdef MPCD_ENABLE_CUDA_CELL_MOMENTS
    CudaCellMoments cudaCellMomentsActive{};
    const bool usingCudaCellMomentsActive = try_cuda_cell_moments_active(
        state, params, grid, diag.shift, step, ws, cudaCellMomentsActive);
#else
    const bool usingCudaCellMomentsActive = false;
#endif

    if (!usingCudaCellMomentsActive) {
#pragma omp parallel
        {
            const int tid = thread_id();
            const std::size_t offset = static_cast<std::size_t>(tid * nc);

#pragma omp for
            for (std::int64_t ii = 0; ii < static_cast<std::int64_t>(n); ++ii) {
                const std::size_t i = static_cast<std::size_t>(ii);
                if (!is_fluid_particle(state, i)) {
                    continue;
                }
                const int c = cell_index_from_position(state.x[i], state.y[i], grid, diag.shift, params);
                ws.cellId[i] = c;
                const std::size_t k = offset + static_cast<std::size_t>(c);
                const double m = state.mass[i];
                ws.localCount[k] += 1u;
                ws.localMass[k] += m;
                ws.localPx[k] += m * state.vx[i];
                ws.localPy[k] += m * state.vy[i];
            }
        }
    }

#ifdef MPCD_ENABLE_CUDA_CELL_MOMENTS
    if (!usingCudaCellMomentsActive) {
        maybe_validate_cuda_cell_moments_shadow(state, params, grid, diag.shift, step, ws, nt);
    }
#endif

    const double inferredGamma = static_cast<double>(roleCounts.fluid) / static_cast<double>(nc);
    const double wallVpGamma = params.wallVpGamma > 0.0 ? params.wallVpGamma : inferredGamma;
    const double wallKBT = params.wallKBT > 0.0 ? params.wallKBT :
                           (params.wallVpKBT > 0.0 ? params.wallVpKBT : params.kBT);
    const double fullCellArea = grid.dx * grid.dy;

    double vpEquivalentSum = 0.0;
    double vpMassSum = 0.0;
    double vpMassLeftSum = 0.0;
    double vpMassRightSum = 0.0;
    double vpMassBottomSum = 0.0;
    double vpMassTopSum = 0.0;
    double vpMassImmersedSum = 0.0;
    double vpPxSum = 0.0;
    double vpPySum = 0.0;

#pragma omp parallel for reduction(+:vpEquivalentSum,vpMassSum,vpMassLeftSum,vpMassRightSum,vpMassBottomSum,vpMassTopSum,vpMassImmersedSum,vpPxSum,vpPySum) if(nc > 256)
    for (int c = 0; c < nc; ++c) {
        std::uint32_t count = 0u;
        double mass = 0.0;
        double px = 0.0;
        double py = 0.0;
#ifdef MPCD_ENABLE_CUDA_CELL_MOMENTS
        if (usingCudaCellMomentsActive) {
            const std::size_t kk = static_cast<std::size_t>(c);
            count = cudaCellMomentsActive.cellCount[kk];
            mass = cudaCellMomentsActive.cellMass[kk];
            px = cudaCellMomentsActive.cellPx[kk];
            py = cudaCellMomentsActive.cellPy[kk];
        } else
#endif
        {
            for (int t = 0; t < nt; ++t) {
                const std::size_t k = static_cast<std::size_t>(t * nc + c);
                count += ws.localCount[k];
                mass += ws.localMass[k];
                px += ws.localPx[k];
                py += ws.localPy[k];
            }
        }

        const int ix = c % grid.Nx;
        const int iy = c / grid.Nx;
        double cellVpEquivalent = 0.0;
        double cellVpMass = 0.0;
        double cellVpPx = 0.0;
        double cellVpPy = 0.0;

        if (face_has_wall_coupling(params.bcLeft, params)) {
            double wallUx = 0.0, wallUy = 0.0;
            wall_velocity_for_face(params, domain, "left", wallUx, wallUy);
            const auto v = make_virtual_face_contribution(
                face_area_left(ix, iy, grid, diag.shift, params, domain),
                fullCellArea, wallVpGamma, params.wallAccommodation,
                params.wallVpMass, wallKBT, params.wallThermalNoise,
                wallUx, wallUy,
                splitmix64(params.rngSeed ^ (step * 0x9e3779b97f4a7c15ULL) ^
                           (static_cast<std::uint64_t>(c) * 0xbf58476d1ce4e5b9ULL) ^
                           0x4c454654ULL));
            add_virtual_face_to_cell(v, mass, px, py, cellVpEquivalent, cellVpMass, cellVpPx, cellVpPy);
            vpMassLeftSum += v.mass;
        }
        if (face_has_wall_coupling(params.bcRight, params)) {
            double wallUx = 0.0, wallUy = 0.0;
            wall_velocity_for_face(params, domain, "right", wallUx, wallUy);
            const auto v = make_virtual_face_contribution(
                face_area_right(ix, iy, grid, diag.shift, params, domain),
                fullCellArea, wallVpGamma, params.wallAccommodation,
                params.wallVpMass, wallKBT, params.wallThermalNoise,
                wallUx, wallUy,
                splitmix64(params.rngSeed ^ (step * 0x9e3779b97f4a7c15ULL) ^
                           (static_cast<std::uint64_t>(c) * 0xbf58476d1ce4e5b9ULL) ^
                           0x5249474854ULL));
            add_virtual_face_to_cell(v, mass, px, py, cellVpEquivalent, cellVpMass, cellVpPx, cellVpPy);
            vpMassRightSum += v.mass;
        }
        if (face_has_wall_coupling(params.bcBottom, params)) {
            double wallUx = 0.0, wallUy = 0.0;
            wall_velocity_for_face(params, domain, "bottom", wallUx, wallUy);
            const auto v = make_virtual_face_contribution(
                face_area_bottom(ix, iy, grid, diag.shift, params, domain),
                fullCellArea, wallVpGamma, params.wallAccommodation,
                params.wallVpMass, wallKBT, params.wallThermalNoise,
                wallUx, wallUy,
                splitmix64(params.rngSeed ^ (step * 0x9e3779b97f4a7c15ULL) ^
                           (static_cast<std::uint64_t>(c) * 0xbf58476d1ce4e5b9ULL) ^
                           0x424f54544f4dULL));
            add_virtual_face_to_cell(v, mass, px, py, cellVpEquivalent, cellVpMass, cellVpPx, cellVpPy);
            vpMassBottomSum += v.mass;
        }
        if (face_has_wall_coupling(params.bcTop, params)) {
            double wallUx = 0.0, wallUy = 0.0;
            wall_velocity_for_face(params, domain, "top", wallUx, wallUy);
            const auto v = make_virtual_face_contribution(
                face_area_top(ix, iy, grid, diag.shift, params, domain),
                fullCellArea, wallVpGamma, params.wallAccommodation,
                params.wallVpMass, wallKBT, params.wallThermalNoise,
                wallUx, wallUy,
                splitmix64(params.rngSeed ^ (step * 0x9e3779b97f4a7c15ULL) ^
                           (static_cast<std::uint64_t>(c) * 0xbf58476d1ce4e5b9ULL) ^
                           0x544f50ULL));
            add_virtual_face_to_cell(v, mass, px, py, cellVpEquivalent, cellVpMass, cellVpPx, cellVpPy);
            vpMassTopSum += v.mass;
        }
        if (immersed_solid_enabled(params)) {
            double wallUx = 0.0, wallUy = 0.0;
            const double cellCx = (static_cast<double>(ix) + 0.5) * grid.dx - diag.shift.sx;
            const double cellCy = (static_cast<double>(iy) + 0.5) * grid.dy - diag.shift.sy;
            const double immersedTime = static_cast<double>(step) * params.dt;
            immersed_solid_wall_velocity(params, cellCx, cellCy, immersedTime, wallUx, wallUy);
            const double solidFraction = immersed_solid_fraction_in_cell(ix, iy, grid, diag.shift, params, domain, immersedTime);
            const auto v = make_virtual_face_contribution(
                solidFraction * fullCellArea,
                fullCellArea, wallVpGamma, params.wallAccommodation,
                params.wallVpMass, wallKBT, params.wallThermalNoise,
                wallUx, wallUy,
                splitmix64(params.rngSeed ^ (step * 0x9e3779b97f4a7c15ULL) ^
                           (static_cast<std::uint64_t>(c) * 0xbf58476d1ce4e5b9ULL) ^
                           0x494d4d4552534544ULL));
            add_virtual_face_to_cell(v, mass, px, py, cellVpEquivalent, cellVpMass, cellVpPx, cellVpPy);
            vpMassImmersedSum += v.mass;
        }

        vpEquivalentSum += cellVpEquivalent;
        vpMassSum += cellVpMass;
        vpPxSum += cellVpPx;
        vpPySum += cellVpPy;

        const std::size_t kk = static_cast<std::size_t>(c);
        ws.cellCount[kk] = count; // real-particle occupancy only; wall diagnostics are separate.
        ws.cellMass[kk] = mass;
        if (mass > 0.0) {
            ws.cellUx[kk] = px / mass;
            ws.cellUy[kk] = py / mass;
        }
    }
    diag.virtualParticleEquivalent = vpEquivalentSum;
    diag.virtualParticleCount = static_cast<std::uint64_t>(std::llround(vpEquivalentSum));
    diag.virtualMass = vpMassSum;
    diag.virtualMassLeft = vpMassLeftSum;
    diag.virtualMassRight = vpMassRightSum;
    diag.virtualMassBottom = vpMassBottomSum;
    diag.virtualMassTop = vpMassTopSum;
    diag.virtualMassImmersed = vpMassImmersedSum;
    diag.virtualMomentumX = vpPxSum;
    diag.virtualMomentumY = vpPySum;

    const double ca0 = std::cos(params.rotationAngle);
    const double sa0 = std::sin(params.rotationAngle);
#pragma omp parallel for if(nc > 256)
    for (int c = 0; c < nc; ++c) {
        const std::size_t k = static_cast<std::size_t>(c);
        ws.cosA[k] = ca0;
        double sa = sa0;
        if (params.randomRotationSign) {
            const std::uint64_t h = splitmix64(params.rngSeed ^
                                               (step * 0x9e3779b97f4a7c15ULL) ^
                                               static_cast<std::uint64_t>(c));
            if ((h & 1ULL) == 0ULL) {
                sa = -sa;
            }
        }
        ws.sinA[k] = sa;
    }

#pragma omp parallel for if(n > 10000)
    for (std::int64_t ii = 0; ii < static_cast<std::int64_t>(n); ++ii) {
        const std::size_t i = static_cast<std::size_t>(ii);
        if (!is_fluid_particle(state, i)) {
            continue;
        }
        const int c = ws.cellId[i];
        if (c < 0 || c >= nc) {
            continue;
        }
        const std::size_t k = static_cast<std::size_t>(c);
        const double ux = ws.cellUx[k];
        const double uy = ws.cellUy[k];
        const double dvx = state.vx[i] - ux;
        const double dvy = state.vy[i] - uy;
        const double ca = ws.cosA[k];
        const double sa = ws.sinA[k];
        state.vx[i] = ux + ca * dvx - sa * dvy;
        state.vy[i] = uy + sa * dvx + ca * dvy;
    }

    return diag;
}

} // namespace mpcd
