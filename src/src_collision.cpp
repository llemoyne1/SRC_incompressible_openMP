#include "src_collision.h"
#include "immersed_solid.h"

#ifdef MPCD_ENABLE_CUDA_CELL_MOMENTS
#include "cuda_cell_moments.h"
#if defined(MPCD_ENABLE_CUDA_PARTICLE_STATE) && defined(MPCD_ENABLE_CUDA_CELL_WORKSPACE)
#include "cuda_shared_particle_state_0251.h"
#include "cuda_cell_workspace.h"
#endif
#endif

#ifdef MPCD_ENABLE_CUDA_SRC_COLLISION
#include "cuda_src_collision.h"
#endif

#ifdef MPCD_ENABLE_CUDA_PERSISTENT_STEP
#include "cuda_persistent_mpcd_step.h"
#include "cuda_particle_state.h"
#if defined(MPCD_ENABLE_CUDA_PARTICLE_STATE)
#include "cuda_shared_particle_state_0251.h"
#endif
#ifdef MPCD_ENABLE_CUDA_CELL_WORKSPACE
#include "cuda_cell_workspace.h"
#endif
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

#if defined(MPCD_ENABLE_CUDA_PARTICLE_STATE) && defined(MPCD_ENABLE_CUDA_CELL_WORKSPACE)
CudaCellWorkspace& cuda_cell_moments_persistent_workspace_0251() {
    static CudaCellWorkspace workspace;
    return workspace;
}
#endif

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
    const bool preferPersistentParticleState0251 =
        env_flag_enabled("MPCD_CUDA_CELL_MOMENTS_PERSISTENT_STATE_0251", false);
#if defined(MPCD_ENABLE_CUDA_PARTICLE_STATE) && defined(MPCD_ENABLE_CUDA_CELL_WORKSPACE)
    if (preferPersistentParticleState0251 && cuda_shared_particle_state_0251_is_fresh()) {
        cuda_deposit_cell_moments_atomic_from_persistent_state(
            state,
            cuda_shared_particle_state_0251(),
            cuda_cell_moments_persistent_workspace_0251(),
            grid,
            shift,
            params,
            cuda,
            &diag,
            opts);
    } else
#endif
    {
        cuda_deposit_cell_moments_atomic(state, grid, shift, params, cuda, &diag, opts);
    }

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


#ifdef MPCD_ENABLE_CUDA_PERSISTENT_STEP
bool persistent_env_flag_enabled(const char* name, const bool fallback = false) {
    const char* v = std::getenv(name);
    if (v == nullptr || *v == '\0') return fallback;
    const std::string t(v);
    return !(t == "0" || t == "false" || t == "FALSE" ||
             t == "off" || t == "OFF" || t == "no" || t == "NO");
}

int persistent_env_int_value(const char* name, const int fallback) {
    const char* v = std::getenv(name);
    if (v == nullptr || *v == '\0') return fallback;
    try { return std::stoi(std::string(v)); }
    catch (...) { return fallback; }
}

struct CudaPersistentCollisionActiveRow {
    std::uint64_t step = 0u;
    std::uint64_t particlesVisited = 0u;
    std::uint64_t fluidParticles = 0u;
    std::uint64_t particlesRotated = 0u;
    std::uint64_t invalidCellParticles = 0u;
    int numCells = 0;
    double uploadSeconds = 0.0;
    double kernelSeconds = 0.0;
    double downloadSeconds = 0.0;
    double totalSeconds = 0.0;
    double shiftX = 0.0;
    double shiftY = 0.0;
    int thermostatAppliedOnGpu = 0;
    std::uint64_t thermostatCellsRescaled = 0u;
    std::uint64_t thermostatParticlesRescaled = 0u;
    double thermostatKBTBefore = 0.0;
    double thermostatKBTAfter = 0.0;
    double thermostatScaleMean = 1.0;
    double thermostatScaleMin = 1.0;
    double thermostatScaleMax = 1.0;
    int sharedParticleStateEnabled = 0;
    double particleStateAllocateSeconds = 0.0;
    double particleStateUploadSeconds = 0.0;
    std::uint64_t particleStateAllocationCalls = 0u;
    int particleStateReusedAllocation = 0;
    std::uint64_t particleStateHostToDeviceBytes = 0u;
    std::uint64_t particleStateMetadataUploadCalls = 0u;
    std::uint64_t particleStateMetadataCacheHits = 0u;
    std::uint64_t particleStateMetadataBytesSkipped = 0u;
    int sharedCellWorkspaceEnabled = 0;
    double cellWorkspaceAllocateSeconds = 0.0;
    std::uint64_t cellWorkspaceAllocationCalls = 0u;
    int cellWorkspaceReusedAllocation = 0;
    std::uint64_t cellWorkspaceAllocatedBytes = 0u;
};

class CudaPersistentCollisionActiveAccumulator {
public:
    void set_output_dir(const std::string& dir) {
        if (!dir.empty()) outputDir_ = dir;
    }

    void add(const CudaPersistentCollisionActiveRow& row) {
        rows_.push_back(row);
    }

    ~CudaPersistentCollisionActiveAccumulator() {
        if (outputDir_.empty() || rows_.empty()) return;
        std::error_code ec;
        std::filesystem::create_directories(outputDir_, ec);
        const std::filesystem::path path = std::filesystem::path(outputDir_) / "cuda_persistent_src_collision_thermostat_0215.csv";
        std::ofstream out(path);
        if (!out) return;
        out << std::setprecision(17);
        out << "step,particlesVisited,fluidParticles,particlesRotated,invalidCellParticles,numCells,uploadSeconds,kernelSeconds,downloadSeconds,totalSeconds,shiftX,shiftY,thermostatAppliedOnGpu,thermostatCellsRescaled,thermostatParticlesRescaled,thermostatKBTBefore,thermostatKBTAfter,thermostatScaleMean,thermostatScaleMin,thermostatScaleMax,sharedParticleStateEnabled,particleStateAllocateSeconds,particleStateUploadSeconds,particleStateAllocationCalls,particleStateReusedAllocation,particleStateHostToDeviceBytes,particleStateMetadataUploadCalls,particleStateMetadataCacheHits,particleStateMetadataBytesSkipped,sharedCellWorkspaceEnabled,cellWorkspaceAllocateSeconds,cellWorkspaceAllocationCalls,cellWorkspaceReusedAllocation,cellWorkspaceAllocatedBytes\n";
        for (const auto& r : rows_) {
            out << r.step << ',' << r.particlesVisited << ',' << r.fluidParticles << ','
                << r.particlesRotated << ',' << r.invalidCellParticles << ',' << r.numCells << ','
                << r.uploadSeconds << ',' << r.kernelSeconds << ',' << r.downloadSeconds << ','
                << r.totalSeconds << ',' << r.shiftX << ',' << r.shiftY << ','
                << r.thermostatAppliedOnGpu << ',' << r.thermostatCellsRescaled << ','
                << r.thermostatParticlesRescaled << ',' << r.thermostatKBTBefore << ','
                << r.thermostatKBTAfter << ',' << r.thermostatScaleMean << ','
                << r.thermostatScaleMin << ',' << r.thermostatScaleMax << ','
                << r.sharedParticleStateEnabled << ',' << r.particleStateAllocateSeconds << ','
                << r.particleStateUploadSeconds << ',' << r.particleStateAllocationCalls << ','
                << r.particleStateReusedAllocation << ',' << r.particleStateHostToDeviceBytes << ','
                << r.particleStateMetadataUploadCalls << ',' << r.particleStateMetadataCacheHits << ','
                << r.particleStateMetadataBytesSkipped << ',' << r.sharedCellWorkspaceEnabled << ','
                << r.cellWorkspaceAllocateSeconds << ',' << r.cellWorkspaceAllocationCalls << ','
                << r.cellWorkspaceReusedAllocation << ',' << r.cellWorkspaceAllocatedBytes << '\n';
        }
    }

private:
    std::string outputDir_;
    std::vector<CudaPersistentCollisionActiveRow> rows_;
};

CudaPersistentCollisionActiveAccumulator& cuda_persistent_collision_active_accumulator() {
    static CudaPersistentCollisionActiveAccumulator acc;
    return acc;
}

#if defined(MPCD_ENABLE_CUDA_PARTICLE_STATE)
CudaParticleState& cuda_persistent_particle_state_tls() {
    static thread_local CudaParticleState state;
    return state;
}
#endif

#if defined(MPCD_ENABLE_CUDA_CELL_WORKSPACE)
CudaCellWorkspace& cuda_persistent_cell_workspace_tls() {
    static thread_local CudaCellWorkspace workspace;
    return workspace;
}
#endif

bool cuda_wall_simple_collision_0253_enabled() {
    return persistent_env_flag_enabled("MPCD_CUDA_PERSISTENT_SRC_COLLISION_WALL_SIMPLE_0253", false);
}

bool cuda_immersed_rect_collision_0254_enabled() {
    return persistent_env_flag_enabled("MPCD_CUDA_PERSISTENT_SRC_COLLISION_IMMERSED_RECT_0254", false);
}

bool cuda_piston_collision_0255_enabled() {
    return persistent_env_flag_enabled("MPCD_CUDA_PERSISTENT_SRC_COLLISION_PISTON_0255", false);
}

bool is_full_domain_bounds(const CellGrid& grid,
                           const FluidDomainBounds& domain,
                           std::string* reason = nullptr) {
    const double eps = 1.0e-12;
    if (std::abs(domain.xMin) > eps || std::abs(domain.yMin) > eps ||
        std::abs(domain.xMax - grid.Lx) > eps || std::abs(domain.yMax - grid.Ly) > eps) {
        if (reason != nullptr) *reason = "moving/sub-domain fluid bounds are not supported";
        return false;
    }
    return true;
}

bool cuda_persistent_collision_subset_supported(const SimulationParams& params,
                                                const CellGrid& grid,
                                                const FluidDomainBounds& domain,
                                                std::string* reason = nullptr) {
    auto fail = [&](const std::string& why) {
        if (reason != nullptr) *reason = why;
        return false;
    };
    if (immersed_solid_enabled(params) && !cuda_immersed_rect_collision_0254_enabled()) {
        return fail("immersed solid requires MPCD_CUDA_PERSISTENT_SRC_COLLISION_IMMERSED_RECT_0254=1");
    }
    const bool fullDomainBounds = is_full_domain_bounds(grid, domain, nullptr);
    if (!fullDomainBounds && !cuda_piston_collision_0255_enabled()) {
        return fail("moving/sub-domain fluid bounds require MPCD_CUDA_PERSISTENT_SRC_COLLISION_PISTON_0255=1");
    }
    if (!cuda_persistent_mpcd_step_available()) return fail("CUDA persistent step backend is not available");

    if (is_x_periodic(params) && is_y_periodic(params)) {
        if (face_has_wall_coupling(params.bcLeft, params) || face_has_wall_coupling(params.bcRight, params) ||
            face_has_wall_coupling(params.bcBottom, params) || face_has_wall_coupling(params.bcTop, params)) {
            return fail("periodic collision subset cannot include wall/virtual-particle coupling");
        }
        if (reason != nullptr) *reason = "supported_periodic_0252";
        return true;
    }

    if (cuda_piston_collision_0255_enabled()) {
        if (!params.closedCapacityResponseEnable) {
            return fail("piston 0255 expects closedCapacityResponseEnable=true");
        }
        if (!is_x_periodic(params) || is_y_periodic(params)) {
            return fail("piston 0255 requires periodic x and bounded y");
        }
        if (face_has_wall_coupling(params.bcLeft, params) || face_has_wall_coupling(params.bcRight, params)) {
            return fail("piston 0255 does not support left/right wall coupling");
        }
        if (!face_has_wall_coupling(params.bcBottom, params) || !face_has_wall_coupling(params.bcTop, params)) {
            return fail("piston 0255 requires bottom/top wall coupling");
        }
        if (std::abs(params.wallThermalNoise) > 1.0e-15) {
            return fail("piston 0255 requires wallThermalNoise=0 for deterministic equivalence");
        }
        if (params.wallAccommodation < 0.0 || params.wallVpMass <= 0.0) {
            return fail("piston 0255 invalid wall accommodation/mass");
        }
        if (std::abs(domain.xMin) > 1.0e-12 || std::abs(domain.xMax - grid.Lx) > 1.0e-12) {
            return fail("piston 0255 requires full x domain bounds");
        }
        if (domain.yMax <= domain.yMin || domain.yMin < -1.0e-12 || domain.yMax > grid.Ly + 1.0e-12) {
            return fail("piston 0255 invalid y-domain bounds");
        }
        if (immersed_solid_enabled(params)) {
            return fail("piston 0255 does not combine with immersed solids");
        }
        if (reason != nullptr) *reason = "supported_piston_0255";
        return true;
    }

    if (cuda_immersed_rect_collision_0254_enabled()) {
        if (!immersed_solid_enabled(params)) return fail("immersed-rectangle 0254 requires immersedSolidEnable=true");
        if (immersed_solid_shape(params) != ImmersedSolidShape::Rectangle) {
            return fail("immersed-rectangle 0254 supports rectangle only");
        }
        if (std::abs(params.immersedSolidVx) > 1.0e-15 ||
            std::abs(params.immersedSolidVy) > 1.0e-15 ||
            std::abs(params.immersedSolidOmega) > 1.0e-15) {
            return fail("immersed-rectangle 0254 supports static rectangles only");
        }
        if (std::abs(params.wallThermalNoise) > 1.0e-15) {
            return fail("immersed-rectangle 0254 requires wallThermalNoise=0 for deterministic equivalence");
        }
        if (params.wallAccommodation < 0.0 || params.wallVpMass <= 0.0) {
            return fail("immersed-rectangle 0254 invalid wall accommodation/mass");
        }
        if (params.immersedSolidFractionSamples <= 0) {
            return fail("immersed-rectangle 0254 requires positive fraction samples");
        }
        if (reason != nullptr) *reason = "supported_immersed_rectangle_0254";
        return true;
    }

    if (cuda_wall_simple_collision_0253_enabled()) {
        if (!is_x_periodic(params) || is_y_periodic(params)) return fail("wall-simple 0253 requires periodic x and bounded y");
        if (face_has_wall_coupling(params.bcLeft, params) || face_has_wall_coupling(params.bcRight, params)) {
            return fail("wall-simple 0253 does not support left/right wall coupling");
        }
        if (!face_has_wall_coupling(params.bcBottom, params) || !face_has_wall_coupling(params.bcTop, params)) {
            return fail("wall-simple 0253 requires bottom/top wall coupling");
        }
        if (std::abs(params.wallThermalNoise) > 1.0e-15) {
            return fail("wall-simple 0253 requires wallThermalNoise=0 for deterministic equivalence");
        }
        if (params.wallAccommodation < 0.0 || params.wallVpMass <= 0.0) {
            return fail("wall-simple 0253 invalid wall accommodation/mass");
        }
        if (reason != nullptr) *reason = "supported_wall_simple_0253";
        return true;
    }

    return fail("requires periodic x/y, or wall-simple 0253 explicitly enabled");
}

void populate_cuda_persistent_wall_virtual_diagnostics_0253(CollisionDiagnostics& diag,
                                                            const ParticleState& state,
                                                            const SimulationParams& params,
                                                            const CellGrid& grid,
                                                            const FluidDomainBounds& domain,
                                                            std::uint64_t step) {
    if (is_x_periodic(params) && is_y_periodic(params)) return;
    const int nc = grid.numCells;
    if (nc <= 0) return;
    const ParticleRoleCounts roleCounts = count_particle_roles(state);
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
    double vpPxSum = 0.0;
    double vpPySum = 0.0;

    for (int c = 0; c < nc; ++c) {
        const int ix = c % grid.Nx;
        const int iy = c / grid.Nx;
        double cellVpEquivalent = 0.0;
        double cellVpMass = 0.0;
        double cellVpPx = 0.0;
        double cellVpPy = 0.0;
        double massDummy = 0.0;
        double pxDummy = 0.0;
        double pyDummy = 0.0;

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
            add_virtual_face_to_cell(v, massDummy, pxDummy, pyDummy, cellVpEquivalent, cellVpMass, cellVpPx, cellVpPy);
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
            add_virtual_face_to_cell(v, massDummy, pxDummy, pyDummy, cellVpEquivalent, cellVpMass, cellVpPx, cellVpPy);
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
            add_virtual_face_to_cell(v, massDummy, pxDummy, pyDummy, cellVpEquivalent, cellVpMass, cellVpPx, cellVpPy);
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
            add_virtual_face_to_cell(v, massDummy, pxDummy, pyDummy, cellVpEquivalent, cellVpMass, cellVpPx, cellVpPy);
            vpMassTopSum += v.mass;
        }
        vpEquivalentSum += cellVpEquivalent;
        vpMassSum += cellVpMass;
        vpPxSum += cellVpPx;
        vpPySum += cellVpPy;
    }

    diag.virtualParticleEquivalent = vpEquivalentSum;
    diag.virtualParticleCount = static_cast<std::uint64_t>(std::llround(vpEquivalentSum));
    diag.virtualMass = vpMassSum;
    diag.virtualMassLeft = vpMassLeftSum;
    diag.virtualMassRight = vpMassRightSum;
    diag.virtualMassBottom = vpMassBottomSum;
    diag.virtualMassTop = vpMassTopSum;
    diag.virtualMassImmersed = 0.0;
    diag.virtualMomentumX = vpPxSum;
    diag.virtualMomentumY = vpPySum;
}


bool try_cuda_persistent_src_collision_active(ParticleState& state,
                                              const SimulationParams& params,
                                              const CellGrid& grid,
                                              const FluidDomainBounds& domain,
                                              CollisionDiagnostics& diagOut,
                                              std::uint64_t step,
                                              CollisionWorkspace& ws) {
    const bool persistentCollision = persistent_env_flag_enabled("MPCD_CUDA_PERSISTENT_SRC_COLLISION_USE", false);
    const bool persistentCollisionThermostat = persistent_env_flag_enabled("MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_USE", false);
    if (!persistentCollision && !persistentCollisionThermostat) return false;

    std::string reason;
    if (!cuda_persistent_collision_subset_supported(params, grid, domain, &reason)) {
        const bool strict = persistent_env_flag_enabled("MPCD_CUDA_PERSISTENT_SRC_COLLISION_STRICT", true);
        if (strict) {
            throw std::runtime_error("CUDA persistent SRC collision active unsupported: " + reason);
        }
        return false;
    }
    if (persistentCollisionThermostat) {
        const bool strict = persistent_env_flag_enabled("MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_STRICT", true);
        auto failThermostat = [&](const std::string& why) {
            if (strict) throw std::runtime_error("CUDA persistent SRC+thermostat unsupported: " + why);
            return false;
        };
        if (!params.thermostatEnable) return failThermostat("thermostatEnable=false");
        if (params.thermostatEvery <= 0) return failThermostat("thermostatEvery must be positive");
        if ((step % static_cast<std::uint64_t>(params.thermostatEvery)) != 0u) {
            // No thermostat on this step; keep using the collision-only persistent path if requested.
        } else {
            if (params.thermostatMode != "cell_relative_rescale") return failThermostat("only cell_relative_rescale is supported");
            if (params.projectionEnable) return failThermostat("projectionEnable must be false because Q6 currently modifies velocities on CPU between collision and thermostat");
            if (params.closedCapacityResponseEnable) return failThermostat("capacity/virial velocity kicks between collision and thermostat are not supported");
        }
    }

    CudaPersistentMpcdStepConfig cfg{};
    cfg.Nx = grid.Nx;
    cfg.Ny = grid.Ny;
    cfg.Lx = grid.Lx;
    cfg.Ly = grid.Ly;
    cfg.shiftX = diagOut.shift.sx;
    cfg.shiftY = diagOut.shift.sy;
    cfg.step = step;
    cfg.rotationAngle = params.rotationAngle;
    cfg.randomRotationSign = params.randomRotationSign ? 1 : 0;
    cfg.rngSeed = params.rngSeed;
    cfg.periodicX = is_x_periodic(params) ? 1 : 0;
    cfg.periodicY = is_y_periodic(params) ? 1 : 0;
    cfg.domainXMin = domain.xMin;
    cfg.domainXMax = domain.xMax;
    cfg.domainYMin = domain.yMin;
    cfg.domainYMax = domain.yMax;
    cfg.wallLeftEnabled = face_has_wall_coupling(params.bcLeft, params) ? 1 : 0;
    cfg.wallRightEnabled = face_has_wall_coupling(params.bcRight, params) ? 1 : 0;
    cfg.wallBottomEnabled = face_has_wall_coupling(params.bcBottom, params) ? 1 : 0;
    cfg.wallTopEnabled = face_has_wall_coupling(params.bcTop, params) ? 1 : 0;
    const ParticleRoleCounts roleCountsForCudaWall = count_particle_roles(state);
    const double inferredGammaForCudaWall = static_cast<double>(roleCountsForCudaWall.fluid) / static_cast<double>(std::max(1, grid.numCells));
    cfg.wallAccommodation = params.wallAccommodation;
    cfg.wallGamma = params.wallVpGamma > 0.0 ? params.wallVpGamma : inferredGammaForCudaWall;
    cfg.wallVpMass = params.wallVpMass;
    wall_velocity_for_face(params, domain, "left", cfg.wallUxLeft, cfg.wallUyLeft);
    wall_velocity_for_face(params, domain, "right", cfg.wallUxRight, cfg.wallUyRight);
    wall_velocity_for_face(params, domain, "bottom", cfg.wallUxBottom, cfg.wallUyBottom);
    wall_velocity_for_face(params, domain, "top", cfg.wallUxTop, cfg.wallUyTop);
    if (immersed_solid_enabled(params) && immersed_solid_shape(params) == ImmersedSolidShape::Rectangle) {
        cfg.immersedRectangleEnabled = 1;
        cfg.immersedFractionSamples = std::max(1, params.immersedSolidFractionSamples);
        const double immersedTime = static_cast<double>(step) * params.dt;
        immersed_solid_rectangle_bounds(params, immersedTime, cfg.immersedXMin, cfg.immersedXMax, cfg.immersedYMin, cfg.immersedYMax);
        const double cx = 0.5 * (cfg.immersedXMin + cfg.immersedXMax);
        const double cy = 0.5 * (cfg.immersedYMin + cfg.immersedYMax);
        immersed_solid_wall_velocity(params, cx, cy, immersedTime, cfg.immersedWallUx, cfg.immersedWallUy);
    }
    cfg.targetKBT = params.thermostatTargetKBT > 0.0 ? params.thermostatTargetKBT : params.kBT;
    cfg.thermostatMinParticles = params.thermostatMinParticles;
    cfg.thermostatEpsilon = params.thermostatEpsilon;
    cfg.cycles = 1;
    cfg.threadsPerBlock = std::max(32, persistent_env_int_value("MPCD_CUDA_PERSISTENT_THREADS_PER_BLOCK", 256));

    ThermostatDiagnostics consumedThermostat{};
    const bool applyPersistentThermostat = persistentCollisionThermostat && params.thermostatEnable &&
        params.thermostatEvery > 0 && ((step % static_cast<std::uint64_t>(params.thermostatEvery)) == 0u);
    CudaPersistentMpcdStepDiagnostics raw{};
    CudaParticleStateDiagnostics particleDiag{};
    CudaCellWorkspaceDiagnostics cellDiag{};
    const bool useSharedParticleState = persistent_env_flag_enabled("MPCD_CUDA_PERSISTENT_PARTICLE_STATE_USE", false);
    const bool useSharedCellWorkspace = persistent_env_flag_enabled("MPCD_CUDA_PERSISTENT_CELL_WORKSPACE_USE", false);
    const bool useSharedParticleState0251 =
        persistent_env_flag_enabled("MPCD_CUDA_PERSISTENT_SRC_COLLISION_SHARED_0251", false);
#if !defined(MPCD_ENABLE_CUDA_PARTICLE_STATE)
    if (useSharedParticleState || useSharedParticleState0251) {
        const bool strict = persistent_env_flag_enabled("MPCD_CUDA_PERSISTENT_PARTICLE_STATE_STRICT", true);
        if (strict) throw std::runtime_error("CUDA persistent SRC collision shared particle state requires MPCD_ENABLE_CUDA_PARTICLE_STATE");
    }
#endif
#if !defined(MPCD_ENABLE_CUDA_CELL_WORKSPACE)
    if (useSharedCellWorkspace || useSharedParticleState0251) {
        const bool strict = persistent_env_flag_enabled("MPCD_CUDA_PERSISTENT_CELL_WORKSPACE_STRICT", true);
        if (strict) throw std::runtime_error("CUDA persistent SRC collision shared cell workspace requires MPCD_ENABLE_CUDA_CELL_WORKSPACE");
    }
#endif
    if (useSharedCellWorkspace && !useSharedParticleState) {
        const bool strict = persistent_env_flag_enabled("MPCD_CUDA_PERSISTENT_CELL_WORKSPACE_STRICT", true);
        if (strict) throw std::runtime_error("MPCD_CUDA_PERSISTENT_CELL_WORKSPACE_USE=1 requires MPCD_CUDA_PERSISTENT_PARTICLE_STATE_USE=1");
    }
    // 0226: shared particle/cell state is also useful for the collision-only
    // path, which preserves the physical order collision -> Q6 -> thermostat.
    const bool canUseSharedParticleState = useSharedParticleState && (applyPersistentThermostat || persistentCollision);
    const bool canUseSharedCellWorkspace = canUseSharedParticleState && useSharedCellWorkspace;
    if (applyPersistentThermostat) {
#if defined(MPCD_ENABLE_CUDA_PARTICLE_STATE)
        if (canUseSharedParticleState) {
            auto& gpuState = cuda_persistent_particle_state_tls();
            const bool metadataCache = persistent_env_flag_enabled("MPCD_CUDA_PERSISTENT_PARTICLE_METADATA_CACHE", true);
            if (metadataCache) {
                gpuState.upload_kinematics_with_cached_metadata(state, &particleDiag);
            } else {
                gpuState.upload_all(state, &particleDiag);
            }
#if defined(MPCD_ENABLE_CUDA_CELL_WORKSPACE)
            if (canUseSharedCellWorkspace) {
                auto& cellWorkspace = cuda_persistent_cell_workspace_tls();
                cellWorkspace.ensure_capacity(state.Np, grid.Nx * grid.Ny, &cellDiag);
                raw = cuda_apply_persistent_tg_deposit_src_collision_thermostat(
                    gpuState, cellWorkspace, state, ws.cellId, ws.cellCount, ws.cellMass, ws.cellUx, ws.cellUy, cfg, &consumedThermostat);
            } else
#endif
            {
                raw = cuda_apply_persistent_tg_deposit_src_collision_thermostat(
                    gpuState, state, ws.cellId, ws.cellCount, ws.cellMass, ws.cellUx, ws.cellUy, cfg, &consumedThermostat);
            }
            // Account for the explicit particle-state upload and optional cell-workspace allocation
            // done outside the shared-state substep.
            raw.uploadSeconds += particleDiag.allocateSeconds + particleDiag.uploadSeconds + cellDiag.allocateSeconds;
            raw.totalSeconds += particleDiag.allocateSeconds + particleDiag.uploadSeconds + cellDiag.allocateSeconds;
        } else
#endif
        {
            raw = cuda_apply_persistent_tg_deposit_src_collision_thermostat(
                state, ws.cellId, ws.cellCount, ws.cellMass, ws.cellUx, ws.cellUy, cfg, &consumedThermostat);
        }
        cuda_persistent_record_consumed_thermostat(step, consumedThermostat);
    } else {
#if defined(MPCD_ENABLE_CUDA_PARTICLE_STATE) && defined(MPCD_ENABLE_CUDA_CELL_WORKSPACE)
        bool consumedSharedParticleState0251 = false;
        if (useSharedParticleState0251) {
            const bool sharedFresh = cuda_shared_particle_state_0251_is_fresh();
            const bool strict0251 = persistent_env_flag_enabled("MPCD_CUDA_PERSISTENT_SRC_COLLISION_SHARED_0251_STRICT", true);
            if (!sharedFresh && strict0251) {
                throw std::runtime_error(std::string("CUDA persistent SRC collision 0252 requested shared 0251 state, but it is stale; lastWriter=") +
                                         cuda_shared_particle_state_0251_last_writer() +
                                         " lastInvalidator=" + cuda_shared_particle_state_0251_last_invalidator());
            }
            if (sharedFresh) {
                auto& gpuState = cuda_shared_particle_state_0251();
                auto& cellWorkspace = cuda_persistent_cell_workspace_tls();
                cellWorkspace.ensure_capacity(state.Np, grid.Nx * grid.Ny, &cellDiag);
                raw = cuda_apply_persistent_tg_deposit_src_collision(
                    gpuState, cellWorkspace, state, ws.cellId, ws.cellCount, ws.cellMass, ws.cellUx, ws.cellUy, cfg);
                raw.uploadSeconds += cellDiag.allocateSeconds;
                raw.totalSeconds += cellDiag.allocateSeconds;
                consumedSharedParticleState0251 = true;
            }
        }
        if (!consumedSharedParticleState0251) {
#endif
#if defined(MPCD_ENABLE_CUDA_PARTICLE_STATE)
        if (canUseSharedParticleState) {
            auto& gpuState = cuda_persistent_particle_state_tls();
            const bool metadataCache = persistent_env_flag_enabled("MPCD_CUDA_PERSISTENT_PARTICLE_METADATA_CACHE", true);
            if (metadataCache) {
                gpuState.upload_kinematics_with_cached_metadata(state, &particleDiag);
            } else {
                gpuState.upload_all(state, &particleDiag);
            }
#if defined(MPCD_ENABLE_CUDA_CELL_WORKSPACE)
            if (canUseSharedCellWorkspace) {
                auto& cellWorkspace = cuda_persistent_cell_workspace_tls();
                cellWorkspace.ensure_capacity(state.Np, grid.Nx * grid.Ny, &cellDiag);
                raw = cuda_apply_persistent_tg_deposit_src_collision(
                    gpuState, cellWorkspace, state, ws.cellId, ws.cellCount, ws.cellMass, ws.cellUx, ws.cellUy, cfg);
            } else
#endif
            {
                raw = cuda_apply_persistent_tg_deposit_src_collision(
                    gpuState, state, ws.cellId, ws.cellCount, ws.cellMass, ws.cellUx, ws.cellUy, cfg);
            }
            raw.uploadSeconds += particleDiag.allocateSeconds + particleDiag.uploadSeconds + cellDiag.allocateSeconds;
            raw.totalSeconds += particleDiag.allocateSeconds + particleDiag.uploadSeconds + cellDiag.allocateSeconds;
#if defined(MPCD_ENABLE_CUDA_PARTICLE_STATE)
            cuda_shared_particle_state_0251_invalidate("persistent_src_collision_private_state_0252");
#endif
        } else
#endif
        {
            raw = cuda_apply_persistent_tg_deposit_src_collision(
                state, ws.cellId, ws.cellCount, ws.cellMass, ws.cellUx, ws.cellUy, cfg);
#if defined(MPCD_ENABLE_CUDA_PARTICLE_STATE)
            cuda_shared_particle_state_0251_invalidate("persistent_src_collision_transient_state_0252");
#endif
        }
#if defined(MPCD_ENABLE_CUDA_PARTICLE_STATE) && defined(MPCD_ENABLE_CUDA_CELL_WORKSPACE)
        } else {
            cuda_shared_particle_state_0251_mark_fresh("persistent_src_collision_0252");
        }
#endif
    }

    CudaPersistentCollisionActiveRow row{};
    row.step = step;
    row.particlesVisited = raw.particlesVisited;
    row.fluidParticles = raw.fluidParticles;
    row.particlesRotated = raw.particlesRotated;
    row.invalidCellParticles = raw.invalidCellParticles;
    row.numCells = raw.numCells;
    row.uploadSeconds = raw.uploadSeconds;
    row.kernelSeconds = raw.kernelSeconds;
    row.downloadSeconds = raw.downloadSeconds;
    row.totalSeconds = raw.totalSeconds;
    row.shiftX = diagOut.shift.sx;
    row.shiftY = diagOut.shift.sy;
    row.thermostatAppliedOnGpu = applyPersistentThermostat ? 1 : 0;
    if (applyPersistentThermostat) {
        row.thermostatCellsRescaled = consumedThermostat.cellsRescaled;
        row.thermostatParticlesRescaled = consumedThermostat.particlesRescaled;
        row.thermostatKBTBefore = consumedThermostat.kBTBefore;
        row.thermostatKBTAfter = consumedThermostat.kBTAfter;
        row.thermostatScaleMean = consumedThermostat.scaleMean;
        row.thermostatScaleMin = consumedThermostat.scaleMin;
        row.thermostatScaleMax = consumedThermostat.scaleMax;
    }
    row.sharedParticleStateEnabled = (canUseSharedParticleState || useSharedParticleState0251) ? 1 : 0;
    row.particleStateAllocateSeconds = particleDiag.allocateSeconds;
    row.particleStateUploadSeconds = particleDiag.uploadSeconds;
    row.particleStateAllocationCalls = particleDiag.allocationCalls;
    row.particleStateReusedAllocation = particleDiag.reusedAllocation;
    row.particleStateHostToDeviceBytes = particleDiag.hostToDeviceBytes;
    row.particleStateMetadataUploadCalls = particleDiag.metadataUploadCalls;
    row.particleStateMetadataCacheHits = particleDiag.metadataCacheHits;
    row.particleStateMetadataBytesSkipped = particleDiag.metadataBytesSkipped;
    row.sharedCellWorkspaceEnabled = (canUseSharedCellWorkspace || useSharedParticleState0251) ? 1 : 0;
    row.cellWorkspaceAllocateSeconds = cellDiag.allocateSeconds;
    row.cellWorkspaceAllocationCalls = cellDiag.allocationCalls;
    row.cellWorkspaceReusedAllocation = cellDiag.reusedAllocation;
    row.cellWorkspaceAllocatedBytes = cellDiag.allocatedBytes;
    auto& acc = cuda_persistent_collision_active_accumulator();
    acc.set_output_dir(params.outputDir);
    acc.add(row);

    const bool strict = persistent_env_flag_enabled("MPCD_CUDA_PERSISTENT_SRC_COLLISION_ACTIVE_STRICT", true);
    if (strict && raw.invalidCellParticles != 0u) {
        throw std::runtime_error("CUDA persistent SRC collision active invalidCellParticles=" +
                                 std::to_string(raw.invalidCellParticles));
    }
    populate_cuda_persistent_wall_virtual_diagnostics_0253(diagOut, state, params, grid, domain, step);
    return true;
}
#endif

#ifdef MPCD_ENABLE_CUDA_SRC_COLLISION
bool cuda_src_collision_env_flag_enabled(const char* name, const bool fallback = false) {
    const char* v = std::getenv(name);
    if (v == nullptr || *v == '\0') return fallback;
    const std::string s(v);
    return !(s == "0" || s == "false" || s == "FALSE" ||
             s == "off" || s == "OFF" || s == "no" || s == "NO");
}

int cuda_src_collision_env_int_value(const char* name, const int fallback) {
    const char* v = std::getenv(name);
    if (v == nullptr || *v == '\0') return fallback;
    try {
        return std::stoi(std::string(v));
    } catch (...) {
        return fallback;
    }
}

double cuda_src_collision_env_double_value(const char* name, const double fallback) {
    const char* v = std::getenv(name);
    if (v == nullptr || *v == '\0') return fallback;
    try {
        return std::stod(std::string(v));
    } catch (...) {
        return fallback;
    }
}

struct CudaSrcCollisionShadowRow {
    std::uint64_t step = 0u;
    std::uint64_t particlesVisited = 0u;
    std::uint64_t particlesRotated = 0u;
    std::uint64_t invalidCellParticles = 0u;
    std::uint64_t velocityMismatches = 0u;
    int numCells = 0;
    double uploadSeconds = 0.0;
    double kernelSeconds = 0.0;
    double downloadSeconds = 0.0;
    double totalSeconds = 0.0;
    double maxAbsVx = 0.0;
    double maxAbsVy = 0.0;
    double rmsV = 0.0;
    double sumAbsVx = 0.0;
    double sumAbsVy = 0.0;
};

class CudaSrcCollisionShadowAccumulator {
public:
    void set_output_dir(const std::string& dir) {
        if (!dir.empty()) outputDir_ = dir;
    }

    void add(const CudaSrcCollisionShadowRow& row) {
        rows_.push_back(row);
    }

    ~CudaSrcCollisionShadowAccumulator() {
        if (outputDir_.empty() || rows_.empty()) return;
        std::error_code ec;
        std::filesystem::create_directories(outputDir_, ec);
        const std::filesystem::path path = std::filesystem::path(outputDir_) / "cuda_src_collision_shadow_0210.csv";
        std::ofstream out(path);
        if (!out) return;
        out << std::setprecision(17);
        out << "step,particlesVisited,particlesRotated,invalidCellParticles,numCells,uploadSeconds,kernelSeconds,downloadSeconds,totalSeconds,velocityMismatches,maxAbsVx,maxAbsVy,rmsV,sumAbsVx,sumAbsVy\n";
        for (const auto& r : rows_) {
            out << r.step << ',' << r.particlesVisited << ',' << r.particlesRotated << ','
                << r.invalidCellParticles << ',' << r.numCells << ','
                << r.uploadSeconds << ',' << r.kernelSeconds << ',' << r.downloadSeconds << ',' << r.totalSeconds << ','
                << r.velocityMismatches << ',' << r.maxAbsVx << ',' << r.maxAbsVy << ',' << r.rmsV << ','
                << r.sumAbsVx << ',' << r.sumAbsVy << '\n';
        }
    }

private:
    std::string outputDir_;
    std::vector<CudaSrcCollisionShadowRow> rows_;
};

CudaSrcCollisionShadowAccumulator& cuda_src_collision_shadow_accumulator() {
    static CudaSrcCollisionShadowAccumulator acc;
    return acc;
}

class CudaSrcCollisionActiveAccumulator {
public:
    void set_output_dir(const std::string& dir) {
        if (!dir.empty()) outputDir_ = dir;
    }

    void add(const CudaSrcCollisionShadowRow& row) {
        rows_.push_back(row);
    }

    ~CudaSrcCollisionActiveAccumulator() {
        if (outputDir_.empty() || rows_.empty()) return;
        std::error_code ec;
        std::filesystem::create_directories(outputDir_, ec);
        const std::filesystem::path path = std::filesystem::path(outputDir_) / "cuda_src_collision_active_0211.csv";
        std::ofstream out(path);
        if (!out) return;
        out << std::setprecision(17);
        out << "step,particlesVisited,particlesRotated,invalidCellParticles,numCells,uploadSeconds,kernelSeconds,downloadSeconds,totalSeconds,velocityMismatches,maxAbsVx,maxAbsVy,rmsV,sumAbsVx,sumAbsVy\n";
        for (const auto& r : rows_) {
            out << r.step << ',' << r.particlesVisited << ',' << r.particlesRotated << ','
                << r.invalidCellParticles << ',' << r.numCells << ','
                << r.uploadSeconds << ',' << r.kernelSeconds << ',' << r.downloadSeconds << ',' << r.totalSeconds << ','
                << r.velocityMismatches << ',' << r.maxAbsVx << ',' << r.maxAbsVy << ',' << r.rmsV << ','
                << r.sumAbsVx << ',' << r.sumAbsVy << '\n';
        }
    }

private:
    std::string outputDir_;
    std::vector<CudaSrcCollisionShadowRow> rows_;
};

CudaSrcCollisionActiveAccumulator& cuda_src_collision_active_accumulator() {
    static CudaSrcCollisionActiveAccumulator acc;
    return acc;
}

bool should_use_cuda_src_collision_active() {
    return cuda_src_collision_env_flag_enabled("MPCD_CUDA_SRC_COLLISION_USE", false);
}

bool should_run_cuda_src_collision_shadow(std::uint64_t step) {
    if (!cuda_src_collision_env_flag_enabled("MPCD_CUDA_SRC_COLLISION_SHADOW", false)) return false;
    const int every = std::max(1, cuda_src_collision_env_int_value("MPCD_CUDA_SRC_COLLISION_SHADOW_EVERY", 1));
    return (step % static_cast<std::uint64_t>(every)) == 0u;
}

void apply_cuda_src_collision_active(ParticleState& state,
                                     const SimulationParams& params,
                                     std::uint64_t step,
                                     const CollisionWorkspace& ws) {
    CudaSrcCollisionActiveAccumulator& acc = cuda_src_collision_active_accumulator();
    acc.set_output_dir(params.outputDir);

    CudaSrcCollisionOptions opts{};
    opts.threadsPerBlock = std::max(32, cuda_src_collision_env_int_value("MPCD_CUDA_SRC_COLLISION_THREADS_PER_BLOCK", 256));

    CudaSrcCollisionDiagnostics diag = cuda_apply_src_collision_from_cell_moments(
        state,
        static_cast<int>(ws.cellUx.size()),
        ws.cellId,
        ws.cellUx,
        ws.cellUy,
        ws.cosA,
        ws.sinA,
        opts);

    CudaSrcCollisionShadowRow row{};
    row.step = step;
    row.particlesVisited = diag.particlesVisited;
    row.particlesRotated = diag.particlesRotated;
    row.invalidCellParticles = diag.invalidCellParticles;
    row.numCells = diag.numCells;
    row.uploadSeconds = diag.uploadSeconds;
    row.kernelSeconds = diag.kernelSeconds;
    row.downloadSeconds = diag.downloadSeconds;
    row.totalSeconds = diag.totalSeconds;
    acc.add(row);

    const bool strict = cuda_src_collision_env_flag_enabled("MPCD_CUDA_SRC_COLLISION_ACTIVE_STRICT", true);
    if (strict && row.invalidCellParticles != 0u) {
        throw std::runtime_error("CUDA SRC collision active invalid cell particles: " +
                                 std::to_string(row.invalidCellParticles));
    }
}

void maybe_validate_cuda_src_collision_shadow(const ParticleState& cpuPostCollisionState,
                                              const SimulationParams& params,
                                              std::uint64_t step,
                                              const CollisionWorkspace& ws,
                                              ParticleState& cudaShadowState,
                                              bool enabledForThisStep) {
    if (!enabledForThisStep) return;

    CudaSrcCollisionShadowAccumulator& acc = cuda_src_collision_shadow_accumulator();
    acc.set_output_dir(params.outputDir);

    CudaSrcCollisionOptions opts{};
    opts.threadsPerBlock = std::max(32, cuda_src_collision_env_int_value("MPCD_CUDA_SRC_COLLISION_THREADS_PER_BLOCK", 256));

    CudaSrcCollisionDiagnostics diag = cuda_apply_src_collision_from_cell_moments(
        cudaShadowState,
        static_cast<int>(ws.cellUx.size()),
        ws.cellId,
        ws.cellUx,
        ws.cellUy,
        ws.cosA,
        ws.sinA,
        opts);

    const std::size_t n = static_cast<std::size_t>(cpuPostCollisionState.Np);
    if (cudaShadowState.Np != cpuPostCollisionState.Np || cudaShadowState.vx.size() != n || cudaShadowState.vy.size() != n) {
        throw std::runtime_error("CUDA SRC collision shadow: inconsistent shadow state size");
    }

    CudaSrcCollisionShadowRow row{};
    row.step = step;
    row.particlesVisited = diag.particlesVisited;
    row.particlesRotated = diag.particlesRotated;
    row.invalidCellParticles = diag.invalidCellParticles;
    row.numCells = diag.numCells;
    row.uploadSeconds = diag.uploadSeconds;
    row.kernelSeconds = diag.kernelSeconds;
    row.downloadSeconds = diag.downloadSeconds;
    row.totalSeconds = diag.totalSeconds;

    double rms2 = 0.0;
    const double tol = cuda_src_collision_env_double_value("MPCD_CUDA_SRC_COLLISION_SHADOW_TOL", 1.0e-12);
    for (std::size_t i = 0; i < n; ++i) {
        const double dvx = std::abs(cpuPostCollisionState.vx[i] - cudaShadowState.vx[i]);
        const double dvy = std::abs(cpuPostCollisionState.vy[i] - cudaShadowState.vy[i]);
        row.maxAbsVx = std::max(row.maxAbsVx, dvx);
        row.maxAbsVy = std::max(row.maxAbsVy, dvy);
        row.sumAbsVx += dvx;
        row.sumAbsVy += dvy;
        rms2 += dvx * dvx + dvy * dvy;
        if (dvx > tol || dvy > tol) ++row.velocityMismatches;
    }
    row.rmsV = n > 0 ? std::sqrt(rms2 / static_cast<double>(2u * n)) : 0.0;
    acc.add(row);

    const bool strict = cuda_src_collision_env_flag_enabled("MPCD_CUDA_SRC_COLLISION_SHADOW_STRICT", true);
    if (strict && (row.velocityMismatches != 0u || row.invalidCellParticles != 0u)) {
        throw std::runtime_error("CUDA SRC collision shadow mismatch: velocityMismatches=" +
                                 std::to_string(row.velocityMismatches) +
                                 " invalidCellParticles=" + std::to_string(row.invalidCellParticles) +
                                 " maxAbsVx=" + std::to_string(row.maxAbsVx) +
                                 " maxAbsVy=" + std::to_string(row.maxAbsVy));
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

#ifdef MPCD_ENABLE_CUDA_PERSISTENT_STEP
    if (try_cuda_persistent_src_collision_active(state, params, grid, domain, diag, step, ws)) {
        return diag;
    }
#endif

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

#ifdef MPCD_ENABLE_CUDA_SRC_COLLISION
    const bool cudaSrcCollisionActiveEnabled = should_use_cuda_src_collision_active();
    const bool cudaSrcCollisionShadowEnabled = (!cudaSrcCollisionActiveEnabled) && should_run_cuda_src_collision_shadow(step);
    ParticleState cudaSrcCollisionShadowState;
    if (cudaSrcCollisionShadowEnabled) {
        cudaSrcCollisionShadowState = state;
    }
#else
    const bool cudaSrcCollisionActiveEnabled = false;
    const bool cudaSrcCollisionShadowEnabled = false;
#endif

#ifdef MPCD_ENABLE_CUDA_SRC_COLLISION
    if (cudaSrcCollisionActiveEnabled) {
        apply_cuda_src_collision_active(state, params, step, ws);
    } else
#endif
    {
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
    }

#ifdef MPCD_ENABLE_CUDA_SRC_COLLISION
    maybe_validate_cuda_src_collision_shadow(state, params, step, ws,
                                             cudaSrcCollisionShadowState,
                                             cudaSrcCollisionShadowEnabled);
#else
    (void)cudaSrcCollisionActiveEnabled;
    (void)cudaSrcCollisionShadowEnabled;
#endif

    return diag;
}

} // namespace mpcd
