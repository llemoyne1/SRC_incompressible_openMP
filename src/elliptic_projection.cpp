#include "elliptic_projection.h"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdlib>
#include <fstream>
#include <iomanip>
#include <cstddef>
#include <cstdint>
#include <limits>
#include <stdexcept>
#include <string>

namespace mpcd {
namespace {

using Q6TimingClock = std::chrono::steady_clock;

struct Q6TimingRecord {
    std::uint64_t call = 0u;
    double total = 0.0;
    double divBefore = 0.0;
    double fieldSetup = 0.0;
    double solveBaseFlux = 0.0;
    double divForSolve = 0.0;
    double rhsBuild = 0.0;
    double gauge = 0.0;
    double solveTotal = 0.0;
    double solveInit = 0.0;
    double solveRhsNorm = 0.0;
    double solvePlan = 0.0;
    double solveApplyDot = 0.0;
    double solveUpdateResidual = 0.0;
    double solveRemoveMean = 0.0;
    double solveBetaUpdate = 0.0;
    double solveFinalMean = 0.0;
    double solveFinalResidual = 0.0;
    double fluxReconstruct = 0.0;
    double divAfter = 0.0;
    double stats = 0.0;
    double unaccounted = 0.0;
    int iterations = 0;
    int converged = 0;
    double residualRel = 0.0;
};

class Q6TimingWriter {
public:
    Q6TimingWriter() {
        const char* pathEnv = std::getenv("MPCD_Q6_TIMING_CSV");
        if (pathEnv == nullptr || pathEnv[0] == '\0') {
            return;
        }
        path_ = pathEnv;
        const char* everyEnv = std::getenv("MPCD_Q6_TIMING_EVERY");
        if (everyEnv != nullptr && everyEnv[0] != '\0') {
            char* end = nullptr;
            const long v = std::strtol(everyEnv, &end, 10);
            if (end != everyEnv && v > 0) {
                every_ = static_cast<std::uint64_t>(v);
            }
        }
        out_.open(path_, std::ios::out | std::ios::trunc);
        if (!out_) {
            return;
        }
        enabled_ = true;
        out_ << "call,total,div_before,field_setup,solve_base_flux,div_for_solve,"
             << "rhs_build,gauge,solve_total,solve_init,solve_rhs_norm,solve_plan,"
             << "solve_apply_dot,solve_update_residual,solve_remove_mean,solve_beta_update,"
             << "solve_final_mean,solve_final_residual,flux_reconstruct,div_after,stats,"
             << "unaccounted,iterations,converged,residual_rel\n";
        out_ << std::setprecision(17);
    }

    bool enabled() const { return enabled_; }

    std::uint64_t next_call() { return ++callCounter_; }

    bool should_record(const std::uint64_t call) const {
        return enabled_ && every_ > 0u && ((call - 1u) % every_ == 0u);
    }

    void append(const Q6TimingRecord& r) {
        if (!enabled_) {
            return;
        }
        out_ << r.call << ','
             << r.total << ','
             << r.divBefore << ','
             << r.fieldSetup << ','
             << r.solveBaseFlux << ','
             << r.divForSolve << ','
             << r.rhsBuild << ','
             << r.gauge << ','
             << r.solveTotal << ','
             << r.solveInit << ','
             << r.solveRhsNorm << ','
             << r.solvePlan << ','
             << r.solveApplyDot << ','
             << r.solveUpdateResidual << ','
             << r.solveRemoveMean << ','
             << r.solveBetaUpdate << ','
             << r.solveFinalMean << ','
             << r.solveFinalResidual << ','
             << r.fluxReconstruct << ','
             << r.divAfter << ','
             << r.stats << ','
             << r.unaccounted << ','
             << r.iterations << ','
             << r.converged << ','
             << r.residualRel << '\n';
    }

private:
    bool enabled_ = false;
    std::uint64_t every_ = 1u;
    std::uint64_t callCounter_ = 0u;
    std::string path_;
    std::ofstream out_;
};

Q6TimingWriter& q6_timing_writer() {
    static Q6TimingWriter writer;
    return writer;
}

inline double q6_seconds_since(const Q6TimingClock::time_point& t0) {
    return std::chrono::duration<double>(Q6TimingClock::now() - t0).count();
}

int cell_index(int i, int j, int Nx) {
    return i + Nx * j;
}

int wrap_index(int i, int n) {
    if (i < 0) return i + n;
    if (i >= n) return i - n;
    return i;
}

void require_scalar_size(const std::vector<double>& v, int nc, const char* name) {
    if (static_cast<int>(v.size()) != nc) {
        throw std::runtime_error(std::string(name) + ": invalid scalar field size");
    }
}

void require_face_size(const PeriodicFaceField& f, int nc, const char* name) {
    if (static_cast<int>(f.x.size()) != nc || static_cast<int>(f.y.size()) != nc) {
        throw std::runtime_error(std::string(name) + ": invalid face field size");
    }
}

void require_grid(const EllipticProjectionGrid& grid) {
    if (grid.Nx <= 0 || grid.Ny <= 0 || grid.numCells != grid.Nx * grid.Ny ||
        !(grid.Lx > 0.0) || !(grid.Ly > 0.0) || !(grid.dx > 0.0) || !(grid.dy > 0.0)) {
        throw std::runtime_error("Invalid elliptic projection grid");
    }
}

void require_mask(const EllipticProjectionMask* mask, int nc, const char* name) {
    if (mask && static_cast<int>(mask->activeCell.size()) != nc) {
        throw std::runtime_error(std::string(name) + ": invalid active-cell mask size");
    }
}

inline bool mask_active(const EllipticProjectionMask* mask, int c) {
    return !mask || mask->activeCell[static_cast<std::size_t>(c)] != 0u;
}

double boundary_flux_value(const std::vector<double>& profile, int index, double fallback) {
    if (profile.empty()) {
        return fallback;
    }
    if (index < 0 || index >= static_cast<int>(profile.size())) {
        throw std::runtime_error("boundary_flux_value: invalid boundary-flux profile size");
    }
    return profile[static_cast<std::size_t>(index)];
}

std::uint64_t mask_active_count(const EllipticProjectionMask* mask, int nc) {
    if (!mask) return static_cast<std::uint64_t>(std::max(0, nc));
    if (mask->activeCells > 0u || mask->inactiveCells > 0u) return mask->activeCells;
    std::uint64_t n = 0u;
    for (int c = 0; c < nc; ++c) {
        if (mask_active(mask, c)) ++n;
    }
    return n;
}

double dot_product(const std::vector<double>& a, const std::vector<double>& b) {
    if (a.size() != b.size()) {
        throw std::runtime_error("dot_product: size mismatch");
    }
    const std::size_t n = a.size();
    double sum = 0.0;
#pragma omp parallel for reduction(+:sum) if(n > 4096)
    for (std::int64_t ii = 0; ii < static_cast<std::int64_t>(n); ++ii) {
        const std::size_t i = static_cast<std::size_t>(ii);
        sum += a[i] * b[i];
    }
    return sum;
}

double mean_value(const std::vector<double>& v, const EllipticProjectionMask* mask = nullptr) {
    if (v.empty()) return 0.0;
    const std::size_t n = v.size();
    require_mask(mask, static_cast<int>(n), "mean_value.mask");
    double sum = 0.0;
    std::uint64_t count = 0u;
#pragma omp parallel for reduction(+:sum,count) if(n > 4096)
    for (std::int64_t ii = 0; ii < static_cast<std::int64_t>(n); ++ii) {
        const int c = static_cast<int>(ii);
        if (!mask_active(mask, c)) continue;
        sum += v[static_cast<std::size_t>(ii)];
        count += 1u;
    }
    return count > 0u ? sum / static_cast<double>(count) : 0.0;
}

void subtract_mean(std::vector<double>& v, const EllipticProjectionMask* mask = nullptr) {
    const double m = mean_value(v, mask);
    const std::size_t n = v.size();
#pragma omp parallel for if(n > 4096)
    for (std::int64_t ii = 0; ii < static_cast<std::int64_t>(n); ++ii) {
        const int c = static_cast<int>(ii);
        const std::size_t k = static_cast<std::size_t>(ii);
        if (mask_active(mask, c)) {
            v[k] -= m;
        } else {
            v[k] = 0.0;
        }
    }
}

struct ScalarStats {
    double rms = 0.0;
    double maxAbs = 0.0;
};

ScalarStats scalar_stats(const std::vector<double>& v, const EllipticProjectionMask* mask = nullptr) {
    ScalarStats s{};
    if (v.empty()) return s;
    const std::size_t n = v.size();
    require_mask(mask, static_cast<int>(n), "scalar_stats.mask");
    double sum2 = 0.0;
    double maxAbs = 0.0;
    std::uint64_t count = 0u;
#pragma omp parallel for reduction(+:sum2,count) reduction(max:maxAbs) if(n > 4096)
    for (std::int64_t ii = 0; ii < static_cast<std::int64_t>(n); ++ii) {
        const int c = static_cast<int>(ii);
        if (!mask_active(mask, c)) continue;
        const double a = std::abs(v[static_cast<std::size_t>(ii)]);
        sum2 += a * a;
        if (a > maxAbs) maxAbs = a;
        count += 1u;
    }
    s.rms = count > 0u ? std::sqrt(sum2 / static_cast<double>(count)) : 0.0;
    s.maxAbs = maxAbs;
    return s;
}

ScalarStats face_stats(const PeriodicFaceField& f) {
    if (f.x.size() != f.y.size()) {
        throw std::runtime_error("face_stats: size mismatch");
    }
    ScalarStats s{};
    const std::size_t n = f.x.size();
    if (n == 0u) return s;
    double sum2 = 0.0;
    double maxAbs = 0.0;
#pragma omp parallel for reduction(+:sum2) reduction(max:maxAbs) if(n > 4096)
    for (std::int64_t ii = 0; ii < static_cast<std::int64_t>(n); ++ii) {
        const std::size_t i = static_cast<std::size_t>(ii);
        const double ax = std::abs(f.x[i]);
        const double ay = std::abs(f.y[i]);
        sum2 += ax * ax + ay * ay;
        if (ax > maxAbs) maxAbs = ax;
        if (ay > maxAbs) maxAbs = ay;
    }
    s.rms = std::sqrt(sum2 / static_cast<double>(2u * n));
    s.maxAbs = maxAbs;
    return s;
}


void prepare_operator_plan_storage(EllipticOperatorPlan& plan, const int nc) {
    const std::size_t n = static_cast<std::size_t>(nc);
    plan.activeCells.clear();
    plan.inactiveCells.clear();
    plan.activeCells.reserve(n);
    plan.inactiveCells.reserve(n / 16u + 1u);

    auto resize_int = [n](std::vector<int>& v) {
        if (v.size() != n) v.resize(n);
    };
    auto resize_double = [n](std::vector<double>& v) {
        if (v.size() != n) v.resize(n);
    };

    resize_int(plan.east);
    resize_int(plan.west);
    resize_int(plan.north);
    resize_int(plan.south);
    resize_double(plan.coeffEast);
    resize_double(plan.coeffWest);
    resize_double(plan.coeffNorth);
    resize_double(plan.coeffSouth);
}

void build_elliptic_operator_plan(const EllipticProjectionGrid& grid,
                                  const PeriodicFaceField& alpha,
                                  const EllipticProjectionBC& bc,
                                  const EllipticProjectionMask* mask,
                                  EllipticOperatorPlan& plan) {
    require_grid(grid);
    require_face_size(alpha, grid.numCells, "build_elliptic_operator_plan.alpha");
    require_mask(mask, grid.numCells, "build_elliptic_operator_plan.mask");

    const int nc = grid.numCells;
    prepare_operator_plan_storage(plan, nc);
    plan.Nx = grid.Nx;
    plan.Ny = grid.Ny;
    plan.numCells = nc;
    plan.dx = grid.dx;
    plan.dy = grid.dy;
    plan.bcX = bc.x;
    plan.bcY = bc.y;

    const double invDx2 = 1.0 / (grid.dx * grid.dx);
    const double invDy2 = 1.0 / (grid.dy * grid.dy);
    const bool periodicX = bc.x == EllipticBoundaryType::Periodic;
    const bool periodicY = bc.y == EllipticBoundaryType::Periodic;

    for (int j = 0; j < grid.Ny; ++j) {
        for (int i = 0; i < grid.Nx; ++i) {
            const int c = cell_index(i, j, grid.Nx);
            const std::size_t k = static_cast<std::size_t>(c);

            plan.east[k] = c;
            plan.west[k] = c;
            plan.north[k] = c;
            plan.south[k] = c;
            plan.coeffEast[k] = 0.0;
            plan.coeffWest[k] = 0.0;
            plan.coeffNorth[k] = 0.0;
            plan.coeffSouth[k] = 0.0;

            if (!mask_active(mask, c)) {
                plan.inactiveCells.push_back(c);
                continue;
            }
            plan.activeCells.push_back(c);

            if (periodicX || i < grid.Nx - 1) {
                const int ip = periodicX ? wrap_index(i + 1, grid.Nx) : (i + 1);
                const int e = cell_index(ip, j, grid.Nx);
                if (mask_active(mask, e)) {
                    plan.east[k] = e;
                    plan.coeffEast[k] = alpha.x[k] * invDx2;
                }
            }
            if (periodicX || i > 0) {
                const int im = periodicX ? wrap_index(i - 1, grid.Nx) : (i - 1);
                const int w = cell_index(im, j, grid.Nx);
                if (mask_active(mask, w)) {
                    plan.west[k] = w;
                    plan.coeffWest[k] = alpha.x[static_cast<std::size_t>(w)] * invDx2;
                }
            }
            if (periodicY || j < grid.Ny - 1) {
                const int jp = periodicY ? wrap_index(j + 1, grid.Ny) : (j + 1);
                const int n = cell_index(i, jp, grid.Nx);
                if (mask_active(mask, n)) {
                    plan.north[k] = n;
                    plan.coeffNorth[k] = alpha.y[k] * invDy2;
                }
            }
            if (periodicY || j > 0) {
                const int jm = periodicY ? wrap_index(j - 1, grid.Ny) : (j - 1);
                const int s = cell_index(i, jm, grid.Nx);
                if (mask_active(mask, s)) {
                    plan.south[k] = s;
                    plan.coeffSouth[k] = alpha.y[static_cast<std::size_t>(s)] * invDy2;
                }
            }
        }
    }
}

double apply_elliptic_operator_plan_and_dot(const EllipticOperatorPlan& plan,
                                            const std::vector<double>& phi,
                                            std::vector<double>& Aphi) {
    require_scalar_size(phi, plan.numCells, "apply_elliptic_operator_plan_and_dot.phi");
    require_scalar_size(Aphi, plan.numCells, "apply_elliptic_operator_plan_and_dot.Aphi");

    const std::size_t nInactive = plan.inactiveCells.size();
#pragma omp parallel for if(nInactive > 4096)
    for (std::int64_t aa = 0; aa < static_cast<std::int64_t>(nInactive); ++aa) {
        const int c = plan.inactiveCells[static_cast<std::size_t>(aa)];
        Aphi[static_cast<std::size_t>(c)] = 0.0;
    }

    const std::size_t nActive = plan.activeCells.size();
    double pAp = 0.0;
#pragma omp parallel for reduction(+:pAp) if(nActive > 4096)
    for (std::int64_t aa = 0; aa < static_cast<std::int64_t>(nActive); ++aa) {
        const int c = plan.activeCells[static_cast<std::size_t>(aa)];
        const std::size_t k = static_cast<std::size_t>(c);
        const double pc = phi[k];
        const double v =
            plan.coeffEast[k]  * (pc - phi[static_cast<std::size_t>(plan.east[k])]) +
            plan.coeffWest[k]  * (pc - phi[static_cast<std::size_t>(plan.west[k])]) +
            plan.coeffNorth[k] * (pc - phi[static_cast<std::size_t>(plan.north[k])]) +
            plan.coeffSouth[k] * (pc - phi[static_cast<std::size_t>(plan.south[k])]);
        Aphi[k] = v;
        pAp += pc * v;
    }
    return pAp;
}

void solve_cg(const EllipticProjectionGrid& grid,
              const PeriodicFaceField& alpha,
              const EllipticProjectionParams& params,
              const EllipticProjectionBC& bc,
              const EllipticProjectionMask* mask,
              std::vector<double>& phi,
              EllipticProjectionWorkspace& workspace,
              EllipticProjectionDiagnostics& diag,
              Q6TimingRecord* timing = nullptr) {
    const int nc = grid.numCells;
    require_scalar_size(workspace.r, nc, "workspace.r");
    require_scalar_size(workspace.p, nc, "workspace.p");
    require_scalar_size(workspace.Ap, nc, "workspace.Ap");
    require_scalar_size(workspace.rhs, nc, "workspace.rhs");
    require_mask(mask, nc, "solve_cg.mask");

    {
        const auto q6PhaseT0 = Q6TimingClock::now();
        phi.assign(static_cast<std::size_t>(nc), 0.0);
        workspace.r = workspace.rhs;
        workspace.p = workspace.r;
        if (timing) timing->solveInit += q6_seconds_since(q6PhaseT0);
    }

    double rhsNorm2 = 0.0;
    std::uint64_t activeCount = 0u;
    {
        const auto q6PhaseT0 = Q6TimingClock::now();
        rhsNorm2 = dot_product(workspace.rhs, workspace.rhs);
        activeCount = mask_active_count(mask, nc);
        diag.rhsRms = activeCount > 0u ? std::sqrt(rhsNorm2 / static_cast<double>(activeCount)) : 0.0;
        diag.rhsMaxAbs = scalar_stats(workspace.rhs, mask).maxAbs;
        if (timing) timing->solveRhsNorm += q6_seconds_since(q6PhaseT0);
    }

    if (rhsNorm2 <= std::numeric_limits<double>::epsilon()) {
        diag.converged = true;
        diag.iterations = 0;
        diag.residualAbs = 0.0;
        diag.residualRel = 0.0;
        return;
    }

    const double rhsNorm = std::sqrt(rhsNorm2);
    const double absTol = std::max(0.0, params.tolerance) * rhsNorm;
    double rr = rhsNorm2;
    const int maxIt = std::max(0, params.maxIterations);

    diag.converged = false;
    diag.iterations = 0;

    {
        const auto q6PhaseT0 = Q6TimingClock::now();
        build_elliptic_operator_plan(grid, alpha, bc, mask, workspace.operatorPlan);
        if (timing) timing->solvePlan += q6_seconds_since(q6PhaseT0);
    }

    for (int it = 0; it < maxIt; ++it) {
        double pAp = 0.0;
        {
            const auto q6PhaseT0 = Q6TimingClock::now();
            pAp = apply_elliptic_operator_plan_and_dot(workspace.operatorPlan, workspace.p, workspace.Ap);
            if (timing) timing->solveApplyDot += q6_seconds_since(q6PhaseT0);
        }
        if (!(pAp > 0.0) || !std::isfinite(pAp)) {
            break;
        }
        const double a = rr / pAp;

        const bool removeMeanThisIteration = params.removePhiMean && ((it + 1) % 25 == 0);
        double rrNew = 0.0;
        {
            const auto q6PhaseT0 = Q6TimingClock::now();
#pragma omp parallel for reduction(+:rrNew) if(nc > 4096)
            for (int c = 0; c < nc; ++c) {
                const std::size_t k = static_cast<std::size_t>(c);
                phi[k] += a * workspace.p[k];
                workspace.r[k] -= a * workspace.Ap[k];
                if (!removeMeanThisIteration) {
                    rrNew += workspace.r[k] * workspace.r[k];
                }
            }
            if (timing) timing->solveUpdateResidual += q6_seconds_since(q6PhaseT0);
        }

        if (removeMeanThisIteration) {
            const auto q6PhaseT0 = Q6TimingClock::now();
            subtract_mean(phi, mask);
            subtract_mean(workspace.r, mask);
            {
                rrNew = dot_product(workspace.r, workspace.r);
            }
            if (timing) timing->solveRemoveMean += q6_seconds_since(q6PhaseT0);
        }
        diag.iterations = it + 1;
        diag.residualAbs = std::sqrt(rrNew);
        diag.residualRel = diag.residualAbs / rhsNorm;
        if (diag.residualAbs <= absTol) {
            diag.converged = true;
            rr = rrNew;
            break;
        }

        const double beta = rrNew / rr;
        {
            const auto q6PhaseT0 = Q6TimingClock::now();
#pragma omp parallel for if(nc > 4096)
            for (int c = 0; c < nc; ++c) {
                const std::size_t k = static_cast<std::size_t>(c);
                workspace.p[k] = workspace.r[k] + beta * workspace.p[k];
            }
            if (timing) timing->solveBetaUpdate += q6_seconds_since(q6PhaseT0);
        }
        rr = rrNew;
    }

    if (params.removePhiMean) {
        const auto q6PhaseT0 = Q6TimingClock::now();
        subtract_mean(phi, mask);
        if (timing) timing->solveFinalMean += q6_seconds_since(q6PhaseT0);
    }

    if (!diag.converged) {
        const auto q6PhaseT0 = Q6TimingClock::now();
        diag.residualAbs = std::sqrt(dot_product(workspace.r, workspace.r));
        diag.residualRel = diag.residualAbs / rhsNorm;
        if (timing) timing->solveFinalResidual += q6_seconds_since(q6PhaseT0);
    }
}

} // namespace

EllipticProjectionGrid make_elliptic_projection_grid(int Nx, int Ny, double Lx, double Ly) {
    EllipticProjectionGrid grid{};
    grid.Nx = Nx;
    grid.Ny = Ny;
    grid.numCells = Nx * Ny;
    grid.Lx = Lx;
    grid.Ly = Ly;
    grid.dx = Lx / static_cast<double>(Nx);
    grid.dy = Ly / static_cast<double>(Ny);
    require_grid(grid);
    return grid;
}

void resize_periodic_face_field(PeriodicFaceField& f, int numCells) {
    if (numCells < 0) {
        throw std::runtime_error("resize_periodic_face_field: negative cell count");
    }
    f.x.assign(static_cast<std::size_t>(numCells), 0.0);
    f.y.assign(static_cast<std::size_t>(numCells), 0.0);
}

void resize_elliptic_projection_workspace(EllipticProjectionWorkspace& workspace, int numCells) {
    if (numCells < 0) {
        throw std::runtime_error("resize_elliptic_projection_workspace: negative cell count");
    }
    const std::size_t n = static_cast<std::size_t>(numCells);
    workspace.rhs.assign(n, 0.0);
    workspace.r.assign(n, 0.0);
    workspace.p.assign(n, 0.0);
    workspace.Ap.assign(n, 0.0);
}

std::vector<double> compute_face_divergence(const EllipticProjectionGrid& grid,
                                            const PeriodicFaceField& flux,
                                            const EllipticProjectionBC& bc,
                                            const EllipticProjectionMask* mask) {
    require_grid(grid);
    require_face_size(flux, grid.numCells, "compute_face_divergence.flux");
    require_mask(mask, grid.numCells, "compute_face_divergence.mask");
    std::vector<double> div(static_cast<std::size_t>(grid.numCells), 0.0);
    const double invDx = 1.0 / grid.dx;
    const double invDy = 1.0 / grid.dy;
    const bool periodicX = bc.x == EllipticBoundaryType::Periodic;
    const bool periodicY = bc.y == EllipticBoundaryType::Periodic;

#pragma omp parallel for if(grid.numCells > 4096)
    for (int j = 0; j < grid.Ny; ++j) {
        for (int i = 0; i < grid.Nx; ++i) {
            const int c = cell_index(i, j, grid.Nx);
            const std::size_t k = static_cast<std::size_t>(c);
            if (!mask_active(mask, c)) {
                div[k] = 0.0;
                continue;
            }

            double fxE = 0.0;
            double fxW = 0.0;
            if (periodicX || i < grid.Nx - 1) {
                const int ip = periodicX ? wrap_index(i + 1, grid.Nx) : (i + 1);
                const int e = cell_index(ip, j, grid.Nx);
                fxE = mask_active(mask, e) ? flux.x[k] : 0.0;
            } else {
                fxE = flux.x[k];
            }
            if (periodicX || i > 0) {
                const int im = periodicX ? wrap_index(i - 1, grid.Nx) : (i - 1);
                const int w = cell_index(im, j, grid.Nx);
                fxW = mask_active(mask, w) ? flux.x[static_cast<std::size_t>(w)] : 0.0;
            } else {
                fxW = boundary_flux_value(bc.xLowFluxProfile, j, bc.xLowFlux);
            }

            double fyN = 0.0;
            double fyS = 0.0;
            if (periodicY || j < grid.Ny - 1) {
                const int jp = periodicY ? wrap_index(j + 1, grid.Ny) : (j + 1);
                const int n = cell_index(i, jp, grid.Nx);
                fyN = mask_active(mask, n) ? flux.y[k] : 0.0;
            } else {
                fyN = flux.y[k];
            }
            if (periodicY || j > 0) {
                const int jm = periodicY ? wrap_index(j - 1, grid.Ny) : (j - 1);
                const int s = cell_index(i, jm, grid.Nx);
                fyS = mask_active(mask, s) ? flux.y[static_cast<std::size_t>(s)] : 0.0;
            } else {
                fyS = boundary_flux_value(bc.yLowFluxProfile, i, bc.yLowFlux);
            }

            div[k] = (fxE - fxW) * invDx + (fyN - fyS) * invDy;
        }
    }
    return div;
}

std::vector<double> compute_periodic_face_divergence(const EllipticProjectionGrid& grid,
                                                     const PeriodicFaceField& flux) {
    EllipticProjectionBC bc{};
    bc.x = EllipticBoundaryType::Periodic;
    bc.y = EllipticBoundaryType::Periodic;
    return compute_face_divergence(grid, flux, bc);
}

void apply_elliptic_operator(const EllipticProjectionGrid& grid,
                             const PeriodicFaceField& alpha,
                             const std::vector<double>& phi,
                             std::vector<double>& Aphi,
                             const EllipticProjectionBC& bc,
                             const EllipticProjectionMask* mask) {
    require_grid(grid);
    require_face_size(alpha, grid.numCells, "apply_elliptic_operator.alpha");
    require_scalar_size(phi, grid.numCells, "apply_elliptic_operator.phi");
    require_mask(mask, grid.numCells, "apply_elliptic_operator.mask");
    Aphi.assign(static_cast<std::size_t>(grid.numCells), 0.0);

    const double invDx2 = 1.0 / (grid.dx * grid.dx);
    const double invDy2 = 1.0 / (grid.dy * grid.dy);
    const bool periodicX = bc.x == EllipticBoundaryType::Periodic;
    const bool periodicY = bc.y == EllipticBoundaryType::Periodic;

#pragma omp parallel for if(grid.numCells > 4096)
    for (int j = 0; j < grid.Ny; ++j) {
        for (int i = 0; i < grid.Nx; ++i) {
            const int c = cell_index(i, j, grid.Nx);
            const std::size_t k = static_cast<std::size_t>(c);
            if (!mask_active(mask, c)) {
                Aphi[k] = phi[k];
                continue;
            }
            const double pc = phi[k];
            double a = 0.0;

            if (periodicX || i < grid.Nx - 1) {
                const int ip = periodicX ? wrap_index(i + 1, grid.Nx) : (i + 1);
                const int e = cell_index(ip, j, grid.Nx);
                if (mask_active(mask, e)) {
                    a += alpha.x[k] * (pc - phi[static_cast<std::size_t>(e)]) * invDx2;
                }
            }
            if (periodicX || i > 0) {
                const int im = periodicX ? wrap_index(i - 1, grid.Nx) : (i - 1);
                const int w = cell_index(im, j, grid.Nx);
                if (mask_active(mask, w)) {
                    a += alpha.x[static_cast<std::size_t>(w)] *
                         (pc - phi[static_cast<std::size_t>(w)]) * invDx2;
                }
            }
            if (periodicY || j < grid.Ny - 1) {
                const int jp = periodicY ? wrap_index(j + 1, grid.Ny) : (j + 1);
                const int n = cell_index(i, jp, grid.Nx);
                if (mask_active(mask, n)) {
                    a += alpha.y[k] * (pc - phi[static_cast<std::size_t>(n)]) * invDy2;
                }
            }
            if (periodicY || j > 0) {
                const int jm = periodicY ? wrap_index(j - 1, grid.Ny) : (j - 1);
                const int s = cell_index(i, jm, grid.Nx);
                if (mask_active(mask, s)) {
                    a += alpha.y[static_cast<std::size_t>(s)] *
                         (pc - phi[static_cast<std::size_t>(s)]) * invDy2;
                }
            }

            Aphi[k] = a;
        }
    }
}

void apply_periodic_elliptic_operator(const EllipticProjectionGrid& grid,
                                      const PeriodicFaceField& alpha,
                                      const std::vector<double>& phi,
                                      std::vector<double>& Aphi) {
    EllipticProjectionBC bc{};
    bc.x = EllipticBoundaryType::Periodic;
    bc.y = EllipticBoundaryType::Periodic;
    apply_elliptic_operator(grid, alpha, phi, Aphi, bc);
}

EllipticProjectionResult project_face_field(const EllipticProjectionGrid& grid,
                                                const PeriodicFaceField& baseFlux,
                                                const PeriodicFaceField& alpha,
                                                const std::vector<double>& targetDivergence,
                                                const EllipticProjectionParams& params,
                                                const EllipticProjectionBC& bc,
                                                EllipticProjectionWorkspace& workspace,
                                                const EllipticProjectionMask* mask) {
    require_grid(grid);
    require_face_size(baseFlux, grid.numCells, "project_face_field.baseFlux");
    require_face_size(alpha, grid.numCells, "project_face_field.alpha");
    require_scalar_size(targetDivergence, grid.numCells, "project_face_field.targetDivergence");
    require_mask(mask, grid.numCells, "project_face_field.mask");

    Q6TimingWriter& q6Writer = q6_timing_writer();
    Q6TimingRecord q6Timing{};
    q6Timing.call = q6Writer.next_call();
    const bool q6TimingEnabled = q6Writer.should_record(q6Timing.call);
    const auto q6TotalT0 = Q6TimingClock::now();

    {
        const auto q6PhaseT0 = Q6TimingClock::now();
        resize_elliptic_projection_workspace(workspace, grid.numCells);
        if (q6TimingEnabled) q6Timing.fieldSetup += q6_seconds_since(q6PhaseT0);
    }

    EllipticProjectionResult result{};
    {
        const auto q6PhaseT0 = Q6TimingClock::now();
        result.divBefore = compute_face_divergence(grid, baseFlux, bc, mask);
        if (q6TimingEnabled) q6Timing.divBefore += q6_seconds_since(q6PhaseT0);
    }
    {
        const auto q6PhaseT0 = Q6TimingClock::now();
        result.phi.assign(static_cast<std::size_t>(grid.numCells), 0.0);
        resize_periodic_face_field(result.correctionFlux, grid.numCells);
        resize_periodic_face_field(result.projectedFlux, grid.numCells);
        if (q6TimingEnabled) q6Timing.fieldSetup += q6_seconds_since(q6PhaseT0);
    }

    PeriodicFaceField solveBaseFlux;
    {
        const auto q6PhaseT0 = Q6TimingClock::now();
        solveBaseFlux = baseFlux;

    if (bc.x != EllipticBoundaryType::Periodic) {
        for (int j = 0; j < grid.Ny; ++j) {
            const int c = cell_index(grid.Nx - 1, j, grid.Nx);
            solveBaseFlux.x[static_cast<std::size_t>(c)] =
                boundary_flux_value(bc.xHighFluxProfile, j, bc.xHighFlux);
        }
    }
    if (bc.y != EllipticBoundaryType::Periodic) {
        for (int i = 0; i < grid.Nx; ++i) {
            const int c = cell_index(i, grid.Ny - 1, grid.Nx);
            solveBaseFlux.y[static_cast<std::size_t>(c)] =
                boundary_flux_value(bc.yHighFluxProfile, i, bc.yHighFlux);
        }
    }
        if (q6TimingEnabled) q6Timing.solveBaseFlux += q6_seconds_since(q6PhaseT0);
    }
    // Faces with alpha=0 are internal no-flux faces.  This matters for curved
    // immersed solids where two neighbouring cell centres can both be fluid
    // while the face segment itself is cut by the solid.  The solve RHS must
    // not include base flux through such faces.
    {
        const auto q6PhaseT0 = Q6TimingClock::now();
#pragma omp parallel for if(grid.numCells > 4096)
        for (int c = 0; c < grid.numCells; ++c) {
            const std::size_t k = static_cast<std::size_t>(c);
            if (alpha.x[k] == 0.0) solveBaseFlux.x[k] = 0.0;
            if (alpha.y[k] == 0.0) solveBaseFlux.y[k] = 0.0;
        }
        if (q6TimingEnabled) q6Timing.solveBaseFlux += q6_seconds_since(q6PhaseT0);
    }
    std::vector<double> divForSolve;
    {
        const auto q6PhaseT0 = Q6TimingClock::now();
        divForSolve = compute_face_divergence(grid, solveBaseFlux, bc, mask);
        if (q6TimingEnabled) q6Timing.divForSolve += q6_seconds_since(q6PhaseT0);
    }

    {
        const auto q6PhaseT0 = Q6TimingClock::now();
        for (int c = 0; c < grid.numCells; ++c) {
            const std::size_t k = static_cast<std::size_t>(c);
            workspace.rhs[k] = mask_active(mask, c) ? (targetDivergence[k] - divForSolve[k]) : 0.0;
        }
        if (q6TimingEnabled) q6Timing.rhsBuild += q6_seconds_since(q6PhaseT0);
    }

    {
        const auto q6PhaseT0 = Q6TimingClock::now();
        result.diagnostics.rhsMeanBeforeGauge = mean_value(workspace.rhs, mask);
        if (params.removeRhsMean) {
            subtract_mean(workspace.rhs, mask);
        }
        result.diagnostics.rhsMeanAfterGauge = mean_value(workspace.rhs, mask);
        if (q6TimingEnabled) q6Timing.gauge += q6_seconds_since(q6PhaseT0);
    }

    {
        const auto q6PhaseT0 = Q6TimingClock::now();
        solve_cg(grid, alpha, params, bc, mask, result.phi, workspace, result.diagnostics,
                 q6TimingEnabled ? &q6Timing : nullptr);
        if (q6TimingEnabled) q6Timing.solveTotal += q6_seconds_since(q6PhaseT0);
    }

    const double invDx = 1.0 / grid.dx;
    const double invDy = 1.0 / grid.dy;
    const bool periodicX = bc.x == EllipticBoundaryType::Periodic;
    const bool periodicY = bc.y == EllipticBoundaryType::Periodic;

    {
        const auto q6PhaseT0 = Q6TimingClock::now();
#pragma omp parallel for if(grid.numCells > 4096)
        for (int j = 0; j < grid.Ny; ++j) {
        for (int i = 0; i < grid.Nx; ++i) {
            const int c = cell_index(i, j, grid.Nx);
            const std::size_t k = static_cast<std::size_t>(c);
            if (!mask_active(mask, c)) {
                result.correctionFlux.x[k] = 0.0;
                result.correctionFlux.y[k] = 0.0;
                result.projectedFlux.x[k] = 0.0;
                result.projectedFlux.y[k] = 0.0;
                continue;
            }

            if (periodicX || i < grid.Nx - 1) {
                const int ip = periodicX ? wrap_index(i + 1, grid.Nx) : (i + 1);
                const int e = cell_index(ip, j, grid.Nx);
                if (mask_active(mask, e)) {
                    if (alpha.x[k] == 0.0) {
                        result.correctionFlux.x[k] = -baseFlux.x[k];
                        result.projectedFlux.x[k] = 0.0;
                    } else {
                        const double gradX = (result.phi[static_cast<std::size_t>(e)] - result.phi[k]) * invDx;
                        result.correctionFlux.x[k] = -alpha.x[k] * gradX;
                        result.projectedFlux.x[k] = baseFlux.x[k] + result.correctionFlux.x[k];
                    }
                } else {
                    result.correctionFlux.x[k] = -baseFlux.x[k];
                    result.projectedFlux.x[k] = 0.0;
                }
            } else {
                const double faceFlux = boundary_flux_value(bc.xHighFluxProfile, j, bc.xHighFlux);
                result.correctionFlux.x[k] = faceFlux - baseFlux.x[k];
                result.projectedFlux.x[k] = faceFlux;
            }

            if (periodicY || j < grid.Ny - 1) {
                const int jp = periodicY ? wrap_index(j + 1, grid.Ny) : (j + 1);
                const int n = cell_index(i, jp, grid.Nx);
                if (mask_active(mask, n)) {
                    if (alpha.y[k] == 0.0) {
                        result.correctionFlux.y[k] = -baseFlux.y[k];
                        result.projectedFlux.y[k] = 0.0;
                    } else {
                        const double gradY = (result.phi[static_cast<std::size_t>(n)] - result.phi[k]) * invDy;
                        result.correctionFlux.y[k] = -alpha.y[k] * gradY;
                        result.projectedFlux.y[k] = baseFlux.y[k] + result.correctionFlux.y[k];
                    }
                } else {
                    result.correctionFlux.y[k] = -baseFlux.y[k];
                    result.projectedFlux.y[k] = 0.0;
                }
            } else {
                const double faceFlux = boundary_flux_value(bc.yHighFluxProfile, i, bc.yHighFlux);
                result.correctionFlux.y[k] = faceFlux - baseFlux.y[k];
                result.projectedFlux.y[k] = faceFlux;
            }
        }
    }

        if (q6TimingEnabled) q6Timing.fluxReconstruct += q6_seconds_since(q6PhaseT0);
    }

    {
        const auto q6PhaseT0 = Q6TimingClock::now();
        result.divAfter = compute_face_divergence(grid, result.projectedFlux, bc, mask);
        if (q6TimingEnabled) q6Timing.divAfter += q6_seconds_since(q6PhaseT0);
    }

    const auto q6StatsT0 = Q6TimingClock::now();
    ScalarStats divBeforeStats{};
    ScalarStats targetStats{};
    ScalarStats divAfterStats{};
    ScalarStats corrStats{};
    ScalarStats projStats{};
    {
        divBeforeStats = scalar_stats(result.divBefore, mask);
    }
    {

        targetStats = scalar_stats(targetDivergence, mask);
    }
    {

        divAfterStats = scalar_stats(result.divAfter, mask);
    }
#ifdef MPCD_ENABLE_EXPENSIVE_Q6_DIAGNOSTICS
    {

        corrStats = face_stats(result.correctionFlux);
    }
    {

        projStats = face_stats(result.projectedFlux);
    }
#endif

    result.diagnostics.divBeforeRms = divBeforeStats.rms;
    result.diagnostics.divBeforeMaxAbs = divBeforeStats.maxAbs;
    result.diagnostics.targetDivergenceRms = targetStats.rms;
    result.diagnostics.divAfterRms = divAfterStats.rms;
    result.diagnostics.divAfterMaxAbs = divAfterStats.maxAbs;
    result.diagnostics.correctionFluxRms = corrStats.rms;
    result.diagnostics.correctionFluxMaxAbs = corrStats.maxAbs;
    result.diagnostics.projectedFluxRms = projStats.rms;
    result.diagnostics.projectedFluxMaxAbs = projStats.maxAbs;
    if (q6TimingEnabled) {
        q6Timing.stats += q6_seconds_since(q6StatsT0);
        q6Timing.total = q6_seconds_since(q6TotalT0);
        q6Timing.iterations = result.diagnostics.iterations;
        q6Timing.converged = result.diagnostics.converged ? 1 : 0;
        q6Timing.residualRel = result.diagnostics.residualRel;
        const double accounted = q6Timing.divBefore + q6Timing.fieldSetup +
            q6Timing.solveBaseFlux + q6Timing.divForSolve + q6Timing.rhsBuild +
            q6Timing.gauge + q6Timing.solveTotal + q6Timing.fluxReconstruct +
            q6Timing.divAfter + q6Timing.stats;
        q6Timing.unaccounted = q6Timing.total - accounted;
        q6Writer.append(q6Timing);
    }

    return result;
}


namespace {

void apply_helmholtz_lowpass_operator(const EllipticProjectionGrid& grid,
                                      const PeriodicFaceField& alpha,
                                      const EllipticProjectionBC& bc,
                                      const EllipticProjectionMask* mask,
                                      double lengthSquared,
                                      const std::vector<double>& x,
                                      std::vector<double>& Bx) {
    apply_elliptic_operator(grid, alpha, x, Bx, bc, mask);
    const int nc = grid.numCells;
#pragma omp parallel for if(nc > 4096)
    for (int c = 0; c < nc; ++c) {
        const std::size_t k = static_cast<std::size_t>(c);
        Bx[k] = mask_active(mask, c) ? (x[k] + lengthSquared * Bx[k]) : x[k];
    }
}

struct HelmholtzLowPassSolveInfo {
    bool converged = false;
    int iterations = 0;
    double residualRel = 0.0;
};

HelmholtzLowPassSolveInfo solve_helmholtz_lowpass_once(const EllipticProjectionGrid& grid,
                                                       const PeriodicFaceField& alpha,
                                                       const EllipticProjectionBC& bc,
                                                       const EllipticProjectionMask* mask,
                                                       double length,
                                                       const std::vector<double>& rhs,
                                                       int maxIterations,
                                                       double tolerance,
                                                       std::vector<double>& out,
                                                       EllipticProjectionWorkspace& workspace) {
    const int nc = grid.numCells;
    require_scalar_size(rhs, nc, "elliptic_lowpass rhs");
    require_scalar_size(workspace.r, nc, "workspace.r");
    require_scalar_size(workspace.p, nc, "workspace.p");
    require_scalar_size(workspace.Ap, nc, "workspace.Ap");
    require_mask(mask, nc, "solve_helmholtz_lowpass_once.mask");

    out.assign(static_cast<std::size_t>(nc), 0.0);
    workspace.r = rhs;
    workspace.p = workspace.r;
    std::fill(workspace.Ap.begin(), workspace.Ap.end(), 0.0);

    HelmholtzLowPassSolveInfo info{};
    const double rhsNorm2 = dot_product(rhs, rhs);
    if (rhsNorm2 <= std::numeric_limits<double>::epsilon()) {
        info.converged = true;
        return info;
    }

    const double rhsNorm = std::sqrt(rhsNorm2);
    const double absTol = std::max(0.0, tolerance) * rhsNorm;
    const double lengthSquared = length * length;
    double rr = rhsNorm2;
    const int maxIt = std::max(1, maxIterations);

    for (int it = 0; it < maxIt; ++it) {
        apply_helmholtz_lowpass_operator(grid, alpha, bc, mask, lengthSquared, workspace.p, workspace.Ap);
        const double pAp = dot_product(workspace.p, workspace.Ap);
        if (!(pAp > 0.0) || !std::isfinite(pAp)) {
            break;
        }

        const double a = rr / pAp;
#pragma omp parallel for if(nc > 4096)
        for (int c = 0; c < nc; ++c) {
            const std::size_t k = static_cast<std::size_t>(c);
            out[k] += a * workspace.p[k];
            workspace.r[k] -= a * workspace.Ap[k];
        }

        const double rrNew = dot_product(workspace.r, workspace.r);
        info.iterations = it + 1;
        info.residualRel = std::sqrt(rrNew) / rhsNorm;
        if (std::sqrt(rrNew) <= absTol) {
            info.converged = true;
            rr = rrNew;
            break;
        }

        const double beta = rrNew / rr;
#pragma omp parallel for if(nc > 4096)
        for (int c = 0; c < nc; ++c) {
            const std::size_t k = static_cast<std::size_t>(c);
            workspace.p[k] = workspace.r[k] + beta * workspace.p[k];
        }
        rr = rrNew;
    }

    if (!info.converged) {
        info.residualRel = std::sqrt(dot_product(workspace.r, workspace.r)) / rhsNorm;
    }
    return info;
}

} // namespace

std::vector<double> elliptic_lowpass_cell_field(const EllipticProjectionGrid& grid,
                                                const std::vector<double>& input,
                                                const PeriodicFaceField& alpha,
                                                const EllipticLowPassParams& params,
                                                const EllipticProjectionBC& bc,
                                                EllipticProjectionWorkspace& workspace,
                                                EllipticLowPassDiagnostics* diagnostics,
                                                const EllipticProjectionMask* mask) {
    require_grid(grid);
    require_scalar_size(input, grid.numCells, "elliptic_lowpass input");
    require_face_size(alpha, grid.numCells, "elliptic_lowpass alpha");
    require_mask(mask, grid.numCells, "elliptic_lowpass.mask");
    resize_elliptic_projection_workspace(workspace, grid.numCells);

    EllipticLowPassDiagnostics diag{};
    diag.passes = std::max(0, params.passes);

    std::vector<double> current = input;
    if (params.removeMeanEachPass) {
        subtract_mean(current, mask);
    }
    diag.inputRms = scalar_stats(current, mask).rms;

    if (diag.passes == 0 || !(params.length > 0.0)) {
        diag.applied = false;
        diag.converged = true;
        diag.outputRms = diag.inputRms;
        diag.filterRatio = diag.inputRms > 0.0 ? 1.0 : 0.0;
        if (diagnostics) *diagnostics = diag;
        return current;
    }

    diag.applied = true;
    diag.converged = true;
    std::vector<double> filtered;
    for (int pass = 0; pass < diag.passes; ++pass) {
        const HelmholtzLowPassSolveInfo info = solve_helmholtz_lowpass_once(
            grid, alpha, bc, mask, params.length, current,
            params.maxIterations, params.tolerance, filtered, workspace);
        if (params.removeMeanEachPass) {
            subtract_mean(filtered, mask);
        }
        current.swap(filtered);
        diag.lastIterations = info.iterations;
        diag.lastResidualRel = info.residualRel;
        diag.converged = diag.converged && info.converged;
    }

    diag.outputRms = scalar_stats(current, mask).rms;
    diag.filterRatio = diag.inputRms > 0.0 ? diag.outputRms / diag.inputRms : 0.0;
    if (diagnostics) *diagnostics = diag;
    return current;
}

EllipticProjectionResult project_periodic_face_field(const EllipticProjectionGrid& grid,
                                                     const PeriodicFaceField& baseFlux,
                                                     const PeriodicFaceField& alpha,
                                                     const std::vector<double>& targetDivergence,
                                                     const EllipticProjectionParams& params,
                                                     EllipticProjectionWorkspace& workspace) {
    EllipticProjectionBC bc{};
    bc.x = EllipticBoundaryType::Periodic;
    bc.y = EllipticBoundaryType::Periodic;
    return project_face_field(grid, baseFlux, alpha, targetDivergence, params, bc, workspace);
}

} // namespace mpcd
