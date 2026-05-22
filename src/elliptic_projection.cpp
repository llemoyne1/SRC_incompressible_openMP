#include "elliptic_projection.h"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <limits>
#include <stdexcept>
#include <string>

namespace mpcd {
namespace {

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

double mean_value(const std::vector<double>& v) {
    if (v.empty()) return 0.0;
    double sum = 0.0;
    const std::size_t n = v.size();
#pragma omp parallel for reduction(+:sum) if(n > 4096)
    for (std::int64_t ii = 0; ii < static_cast<std::int64_t>(n); ++ii) {
        sum += v[static_cast<std::size_t>(ii)];
    }
    return sum / static_cast<double>(n);
}

void subtract_mean(std::vector<double>& v) {
    const double m = mean_value(v);
    const std::size_t n = v.size();
#pragma omp parallel for if(n > 4096)
    for (std::int64_t ii = 0; ii < static_cast<std::int64_t>(n); ++ii) {
        v[static_cast<std::size_t>(ii)] -= m;
    }
}

struct ScalarStats {
    double rms = 0.0;
    double maxAbs = 0.0;
};

ScalarStats scalar_stats(const std::vector<double>& v) {
    ScalarStats s{};
    if (v.empty()) return s;
    const std::size_t n = v.size();
    double sum2 = 0.0;
    double maxAbs = 0.0;
#pragma omp parallel for reduction(+:sum2) reduction(max:maxAbs) if(n > 4096)
    for (std::int64_t ii = 0; ii < static_cast<std::int64_t>(n); ++ii) {
        const double a = std::abs(v[static_cast<std::size_t>(ii)]);
        sum2 += a * a;
        if (a > maxAbs) maxAbs = a;
    }
    s.rms = std::sqrt(sum2 / static_cast<double>(n));
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

void solve_cg(const EllipticProjectionGrid& grid,
              const PeriodicFaceField& alpha,
              const EllipticProjectionParams& params,
              const EllipticProjectionBC& bc,
              std::vector<double>& phi,
              EllipticProjectionWorkspace& workspace,
              EllipticProjectionDiagnostics& diag) {
    const int nc = grid.numCells;
    require_scalar_size(workspace.r, nc, "workspace.r");
    require_scalar_size(workspace.p, nc, "workspace.p");
    require_scalar_size(workspace.Ap, nc, "workspace.Ap");
    require_scalar_size(workspace.rhs, nc, "workspace.rhs");

    phi.assign(static_cast<std::size_t>(nc), 0.0);
    workspace.r = workspace.rhs;
    workspace.p = workspace.r;

    const double rhsNorm2 = dot_product(workspace.rhs, workspace.rhs);
    diag.rhsRms = std::sqrt(rhsNorm2 / static_cast<double>(nc));
    diag.rhsMaxAbs = scalar_stats(workspace.rhs).maxAbs;

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

    for (int it = 0; it < maxIt; ++it) {
        apply_elliptic_operator(grid, alpha, workspace.p, workspace.Ap, bc);
        const double pAp = dot_product(workspace.p, workspace.Ap);
        if (!(pAp > 0.0) || !std::isfinite(pAp)) {
            break;
        }
        const double a = rr / pAp;

#pragma omp parallel for if(nc > 4096)
        for (int c = 0; c < nc; ++c) {
            const std::size_t k = static_cast<std::size_t>(c);
            phi[k] += a * workspace.p[k];
            workspace.r[k] -= a * workspace.Ap[k];
        }

        if (params.removePhiMean && ((it + 1) % 25 == 0)) {
            subtract_mean(phi);
            subtract_mean(workspace.r);
        }

        const double rrNew = dot_product(workspace.r, workspace.r);
        diag.iterations = it + 1;
        diag.residualAbs = std::sqrt(rrNew);
        diag.residualRel = diag.residualAbs / rhsNorm;
        if (diag.residualAbs <= absTol) {
            diag.converged = true;
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

    if (params.removePhiMean) {
        subtract_mean(phi);
    }

    if (!diag.converged) {
        diag.residualAbs = std::sqrt(dot_product(workspace.r, workspace.r));
        diag.residualRel = diag.residualAbs / rhsNorm;
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
                                            const EllipticProjectionBC& bc) {
    require_grid(grid);
    require_face_size(flux, grid.numCells, "compute_face_divergence.flux");
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

            double fxE = 0.0;
            double fxW = 0.0;
            if (periodicX || i < grid.Nx - 1) {
                fxE = flux.x[k];
            } else {
                // High non-periodic boundary face is stored by the last cell.
                fxE = flux.x[k];
            }
            if (periodicX || i > 0) {
                const int im = periodicX ? wrap_index(i - 1, grid.Nx) : (i - 1);
                const int w = cell_index(im, j, grid.Nx);
                fxW = flux.x[static_cast<std::size_t>(w)];
            } else {
                fxW = bc.xLowFlux;
            }

            double fyN = 0.0;
            double fyS = 0.0;
            if (periodicY || j < grid.Ny - 1) {
                fyN = flux.y[k];
            } else {
                // High non-periodic boundary face is stored by the last cell.
                fyN = flux.y[k];
            }
            if (periodicY || j > 0) {
                const int jm = periodicY ? wrap_index(j - 1, grid.Ny) : (j - 1);
                const int s = cell_index(i, jm, grid.Nx);
                fyS = flux.y[static_cast<std::size_t>(s)];
            } else {
                fyS = bc.yLowFlux;
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
                             const EllipticProjectionBC& bc) {
    require_grid(grid);
    require_face_size(alpha, grid.numCells, "apply_elliptic_operator.alpha");
    require_scalar_size(phi, grid.numCells, "apply_elliptic_operator.phi");
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
            const double pc = phi[k];
            double a = 0.0;

            if (periodicX || i < grid.Nx - 1) {
                const int ip = periodicX ? wrap_index(i + 1, grid.Nx) : (i + 1);
                const int e = cell_index(ip, j, grid.Nx);
                a += alpha.x[k] * (pc - phi[static_cast<std::size_t>(e)]) * invDx2;
            }
            if (periodicX || i > 0) {
                const int im = periodicX ? wrap_index(i - 1, grid.Nx) : (i - 1);
                const int w = cell_index(im, j, grid.Nx);
                a += alpha.x[static_cast<std::size_t>(w)] *
                     (pc - phi[static_cast<std::size_t>(w)]) * invDx2;
            }
            if (periodicY || j < grid.Ny - 1) {
                const int jp = periodicY ? wrap_index(j + 1, grid.Ny) : (j + 1);
                const int n = cell_index(i, jp, grid.Nx);
                a += alpha.y[k] * (pc - phi[static_cast<std::size_t>(n)]) * invDy2;
            }
            if (periodicY || j > 0) {
                const int jm = periodicY ? wrap_index(j - 1, grid.Ny) : (j - 1);
                const int s = cell_index(i, jm, grid.Nx);
                a += alpha.y[static_cast<std::size_t>(s)] *
                     (pc - phi[static_cast<std::size_t>(s)]) * invDy2;
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
                                                EllipticProjectionWorkspace& workspace) {
    require_grid(grid);
    require_face_size(baseFlux, grid.numCells, "project_periodic_face_field.baseFlux");
    require_face_size(alpha, grid.numCells, "project_periodic_face_field.alpha");
    require_scalar_size(targetDivergence, grid.numCells, "project_periodic_face_field.targetDivergence");

    resize_elliptic_projection_workspace(workspace, grid.numCells);

    EllipticProjectionResult result{};
    result.divBefore = compute_face_divergence(grid, baseFlux, bc);
    result.phi.assign(static_cast<std::size_t>(grid.numCells), 0.0);
    resize_periodic_face_field(result.correctionFlux, grid.numCells);
    resize_periodic_face_field(result.projectedFlux, grid.numCells);

    // Inhomogeneous moving-wall fluxes are handled as prescribed projected
    // boundary fluxes. The elliptic solve only computes the interior gradient
    // correction; high non-periodic boundary faces are fixed before the solve
    // for compatibility of the Neumann problem.
    PeriodicFaceField solveBaseFlux = baseFlux;
    if (bc.x != EllipticBoundaryType::Periodic) {
        for (int j = 0; j < grid.Ny; ++j) {
            const int c = cell_index(grid.Nx - 1, j, grid.Nx);
            solveBaseFlux.x[static_cast<std::size_t>(c)] = bc.xHighFlux;
        }
    }
    if (bc.y != EllipticBoundaryType::Periodic) {
        for (int i = 0; i < grid.Nx; ++i) {
            const int c = cell_index(i, grid.Ny - 1, grid.Nx);
            solveBaseFlux.y[static_cast<std::size_t>(c)] = bc.yHighFlux;
        }
    }
    const std::vector<double> divForSolve = compute_face_divergence(grid, solveBaseFlux, bc);

    for (int c = 0; c < grid.numCells; ++c) {
        const std::size_t k = static_cast<std::size_t>(c);
        workspace.rhs[k] = targetDivergence[k] - divForSolve[k];
    }

    result.diagnostics.rhsMeanBeforeGauge = mean_value(workspace.rhs);
    if (params.removeRhsMean) {
        subtract_mean(workspace.rhs);
    }
    result.diagnostics.rhsMeanAfterGauge = mean_value(workspace.rhs);

    solve_cg(grid, alpha, params, bc, result.phi, workspace, result.diagnostics);

    const double invDx = 1.0 / grid.dx;
    const double invDy = 1.0 / grid.dy;

    const bool periodicX = bc.x == EllipticBoundaryType::Periodic;
    const bool periodicY = bc.y == EllipticBoundaryType::Periodic;

#pragma omp parallel for if(grid.numCells > 4096)
    for (int j = 0; j < grid.Ny; ++j) {
        for (int i = 0; i < grid.Nx; ++i) {
            const int c = cell_index(i, j, grid.Nx);
            const std::size_t k = static_cast<std::size_t>(c);

            if (periodicX || i < grid.Nx - 1) {
                const int ip = periodicX ? wrap_index(i + 1, grid.Nx) : (i + 1);
                const int e = cell_index(ip, j, grid.Nx);
                const double gradX = (result.phi[static_cast<std::size_t>(e)] - result.phi[k]) * invDx;
                result.correctionFlux.x[k] = -alpha.x[k] * gradX;
                result.projectedFlux.x[k] = baseFlux.x[k] + result.correctionFlux.x[k];
            } else {
                result.correctionFlux.x[k] = bc.xHighFlux - baseFlux.x[k];
                result.projectedFlux.x[k] = bc.xHighFlux;
            }

            if (periodicY || j < grid.Ny - 1) {
                const int jp = periodicY ? wrap_index(j + 1, grid.Ny) : (j + 1);
                const int n = cell_index(i, jp, grid.Nx);
                const double gradY = (result.phi[static_cast<std::size_t>(n)] - result.phi[k]) * invDy;
                result.correctionFlux.y[k] = -alpha.y[k] * gradY;
                result.projectedFlux.y[k] = baseFlux.y[k] + result.correctionFlux.y[k];
            } else {
                result.correctionFlux.y[k] = bc.yHighFlux - baseFlux.y[k];
                result.projectedFlux.y[k] = bc.yHighFlux;
            }
        }
    }

    result.divAfter = compute_face_divergence(grid, result.projectedFlux, bc);

    const ScalarStats divBeforeStats = scalar_stats(result.divBefore);
    const ScalarStats targetStats = scalar_stats(targetDivergence);
    const ScalarStats divAfterStats = scalar_stats(result.divAfter);
    const ScalarStats corrStats = face_stats(result.correctionFlux);
    const ScalarStats projStats = face_stats(result.projectedFlux);

    result.diagnostics.divBeforeRms = divBeforeStats.rms;
    result.diagnostics.divBeforeMaxAbs = divBeforeStats.maxAbs;
    result.diagnostics.targetDivergenceRms = targetStats.rms;
    result.diagnostics.divAfterRms = divAfterStats.rms;
    result.diagnostics.divAfterMaxAbs = divAfterStats.maxAbs;
    result.diagnostics.correctionFluxRms = corrStats.rms;
    result.diagnostics.correctionFluxMaxAbs = corrStats.maxAbs;
    result.diagnostics.projectedFluxRms = projStats.rms;
    result.diagnostics.projectedFluxMaxAbs = projStats.maxAbs;

    return result;
}


namespace {

void apply_helmholtz_lowpass_operator(const EllipticProjectionGrid& grid,
                                      const PeriodicFaceField& alpha,
                                      const EllipticProjectionBC& bc,
                                      double lengthSquared,
                                      const std::vector<double>& x,
                                      std::vector<double>& Bx) {
    apply_elliptic_operator(grid, alpha, x, Bx, bc);
    const int nc = grid.numCells;
#pragma omp parallel for if(nc > 4096)
    for (int c = 0; c < nc; ++c) {
        const std::size_t k = static_cast<std::size_t>(c);
        Bx[k] = x[k] + lengthSquared * Bx[k];
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
        apply_helmholtz_lowpass_operator(grid, alpha, bc, lengthSquared, workspace.p, workspace.Ap);
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
                                                EllipticLowPassDiagnostics* diagnostics) {
    require_grid(grid);
    require_scalar_size(input, grid.numCells, "elliptic_lowpass input");
    require_face_size(alpha, grid.numCells, "elliptic_lowpass alpha");
    resize_elliptic_projection_workspace(workspace, grid.numCells);

    EllipticLowPassDiagnostics diag{};
    diag.passes = std::max(0, params.passes);

    std::vector<double> current = input;
    if (params.removeMeanEachPass) {
        subtract_mean(current);
    }
    diag.inputRms = scalar_stats(current).rms;

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
            grid, alpha, bc, params.length, current,
            params.maxIterations, params.tolerance, filtered, workspace);
        if (params.removeMeanEachPass) {
            subtract_mean(filtered);
        }
        current.swap(filtered);
        diag.lastIterations = info.iterations;
        diag.lastResidualRel = info.residualRel;
        diag.converged = diag.converged && info.converged;
    }

    diag.outputRms = scalar_stats(current).rms;
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
