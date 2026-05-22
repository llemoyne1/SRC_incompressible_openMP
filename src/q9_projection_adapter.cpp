#include "q9_projection_adapter.h"

#include <algorithm>
#include <cctype>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <limits>
#include <stdexcept>
#include <string>

#ifdef _OPENMP
#include <omp.h>
#endif

namespace mpcd {
namespace {

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

void resize_q9_workspace(Q9ProjectionWorkspace& ws,
                         std::uint64_t numParticles,
                         int numCells,
                         int numThreads) {
    if (numCells <= 0) {
        throw std::runtime_error("resize_q9_workspace: invalid number of cells");
    }
    if (numThreads <= 0) {
        numThreads = 1;
    }

    const bool sameSize = ws.allocatedCells == numCells &&
                          ws.allocatedParticles == numParticles &&
                          static_cast<int>(ws.localMass.size()) == numThreads * numCells;
    if (sameSize) {
        return;
    }

    ws.allocatedCells = numCells;
    ws.allocatedParticles = numParticles;
    const std::size_t np = static_cast<std::size_t>(numParticles);
    const std::size_t nc = static_cast<std::size_t>(numCells);
    const std::size_t nLocal = static_cast<std::size_t>(numThreads * numCells);

    ws.cellId.assign(np, 0);
    ws.cellMass.assign(nc, 0.0);
    ws.cellPx.assign(nc, 0.0);
    ws.cellPy.assign(nc, 0.0);
    ws.cellDUx.assign(nc, 0.0);
    ws.cellDUy.assign(nc, 0.0);
    ws.localMass.assign(nLocal, 0.0);
    ws.localPx.assign(nLocal, 0.0);
    ws.localPy.assign(nLocal, 0.0);
    ws.targetDivergence.assign(nc, 0.0);
    ws.massAfterEstimate.assign(nc, 0.0);
    resize_periodic_face_field(ws.baseMassFlux, numCells);
    resize_periodic_face_field(ws.alpha, numCells);
    resize_periodic_face_field(ws.appliedCorrectionFlux, numCells);
    resize_periodic_face_field(ws.projectedMassFlux, numCells);
    resize_elliptic_projection_workspace(ws.elliptic, numCells);
}

EllipticProjectionBC q9_bc_from_particle_boundaries(const SimulationParams& params) {
    EllipticProjectionBC bc{};
    bc.x = is_x_periodic(params) ? EllipticBoundaryType::Periodic
                                 : EllipticBoundaryType::WallNoNormalFlux;
    bc.y = is_y_periodic(params) ? EllipticBoundaryType::Periodic
                                 : EllipticBoundaryType::WallNoNormalFlux;
    return bc;
}

void deposit_cell_mass_momentum(const ParticleState& state,
                                const SimulationParams& params,
                                const CellGrid& grid,
                                Q9ProjectionWorkspace& ws,
                                Q9ProjectionDiagnostics& diag) {
    const std::size_t n = static_cast<std::size_t>(state.Np);
    const int nc = grid.numCells;
    const int nt = std::max(1, thread_count());

    std::fill(ws.cellMass.begin(), ws.cellMass.end(), 0.0);
    std::fill(ws.cellPx.begin(), ws.cellPx.end(), 0.0);
    std::fill(ws.cellPy.begin(), ws.cellPy.end(), 0.0);
    std::fill(ws.localMass.begin(), ws.localMass.end(), 0.0);
    std::fill(ws.localPx.begin(), ws.localPx.end(), 0.0);
    std::fill(ws.localPy.begin(), ws.localPy.end(), 0.0);

    const GridShift noShift{};
#pragma omp parallel
    {
        const int tid = thread_id();
        const std::size_t offset = static_cast<std::size_t>(tid * nc);

#pragma omp for
        for (std::int64_t ii = 0; ii < static_cast<std::int64_t>(n); ++ii) {
            const std::size_t i = static_cast<std::size_t>(ii);
            const int c = cell_index_from_position(state.x[i], state.y[i], grid, noShift, params);
            ws.cellId[i] = c;
            const std::size_t k = offset + static_cast<std::size_t>(c);
            const double m = state.mass[i];
            ws.localMass[k] += m;
            ws.localPx[k] += m * state.vx[i];
            ws.localPy[k] += m * state.vy[i];
        }
    }

    std::uint64_t empty = 0u;
#pragma omp parallel for reduction(+:empty) if(nc > 256)
    for (int c = 0; c < nc; ++c) {
        double m = 0.0;
        double px = 0.0;
        double py = 0.0;
        for (int t = 0; t < nt; ++t) {
            const std::size_t k = static_cast<std::size_t>(t * nc + c);
            m += ws.localMass[k];
            px += ws.localPx[k];
            py += ws.localPy[k];
        }
        const std::size_t kk = static_cast<std::size_t>(c);
        ws.cellMass[kk] = m;
        ws.cellPx[kk] = px;
        ws.cellPy[kk] = py;
        if (!(m > 0.0)) {
            ++empty;
        }
    }
    diag.emptyCells = empty;
}

void build_mass_flux_from_cell_momentum(const CellGrid& grid,
                                        const std::vector<double>& px,
                                        const std::vector<double>& py,
                                        PeriodicFaceField& flux) {
    const int nc = grid.numCells;
    if (static_cast<int>(px.size()) != nc || static_cast<int>(py.size()) != nc) {
        throw std::runtime_error("build_mass_flux_from_cell_momentum: invalid array size");
    }
    resize_periodic_face_field(flux, nc);
#pragma omp parallel for if(nc > 4096)
    for (int c = 0; c < nc; ++c) {
        const std::size_t k = static_cast<std::size_t>(c);
        flux.x[k] = px[k];
        flux.y[k] = py[k];
    }
}

void fill_alpha(PeriodicFaceField& alpha, int numCells, double value) {
    resize_periodic_face_field(alpha, numCells);
    std::fill(alpha.x.begin(), alpha.x.end(), value);
    std::fill(alpha.y.begin(), alpha.y.end(), value);
}


std::string canonical_filter_name(std::string s) {
    std::transform(s.begin(), s.end(), s.begin(), [](unsigned char ch) {
        return static_cast<char>(std::tolower(ch));
    });
    std::replace(s.begin(), s.end(), '-', '_');
    return s;
}

bool q9_target_filter_is_none(const SimulationParams& params) {
    const std::string f = canonical_filter_name(params.q9TargetFilter);
    return f == "none" || f == "off" || f == "identity" || f == "raw";
}

bool q9_target_filter_is_elliptic_lowpass(const SimulationParams& params) {
    const std::string f = canonical_filter_name(params.q9TargetFilter);
    return f == "elliptic_lowpass" || f == "operator_lowpass" ||
           f == "lowpass_operator" || f == "lowpass_elliptic" ||
           f == "lowk_elliptic";
}

double vector_mean(const std::vector<double>& v) {
    if (v.empty()) {
        return 0.0;
    }
    double sum = 0.0;
    const std::size_t n = v.size();
#pragma omp parallel for reduction(+:sum) if(n > 4096)
    for (std::int64_t ii = 0; ii < static_cast<std::int64_t>(n); ++ii) {
        sum += v[static_cast<std::size_t>(ii)];
    }
    return sum / static_cast<double>(n);
}

void subtract_vector_mean(std::vector<double>& v) {
    const double m = vector_mean(v);
    const std::size_t n = v.size();
#pragma omp parallel for if(n > 4096)
    for (std::int64_t ii = 0; ii < static_cast<std::int64_t>(n); ++ii) {
        v[static_cast<std::size_t>(ii)] -= m;
    }
}

double vector_rms(const std::vector<double>& v) {
    if (v.empty()) {
        return 0.0;
    }
    double sum2 = 0.0;
    const std::size_t n = v.size();
#pragma omp parallel for reduction(+:sum2) if(n > 4096)
    for (std::int64_t ii = 0; ii < static_cast<std::int64_t>(n); ++ii) {
        const double a = v[static_cast<std::size_t>(ii)];
        sum2 += a * a;
    }
    return std::sqrt(sum2 / static_cast<double>(n));
}

EllipticLowPassParams make_q9_lowpass_params(const SimulationParams& params,
                                             const EllipticProjectionGrid& egrid) {
    const int nc = egrid.numCells;
    const double nApprox = std::sqrt(static_cast<double>(std::max(1, nc)));
    const double denom = std::max(1.0, 2.0 * static_cast<double>(params.q9LowKMaxIndex) + 1.0);
    const double lenCells = params.q9EllipticLowPassLengthCells > 0.0
        ? params.q9EllipticLowPassLengthCells
        : std::max(1.0, nApprox / denom);
    const double ell = lenCells * 0.5 * (egrid.dx + egrid.dy);

    EllipticLowPassParams filterParams{};
    filterParams.passes = std::max(0, params.q9EllipticLowPassPasses);
    filterParams.length = ell;
    filterParams.maxIterations = std::max(1, params.projectionMaxIterations);
    filterParams.tolerance = std::max(0.0, params.projectionTolerance);
    filterParams.removeMeanEachPass = true;
    return filterParams;
}

bool q9_lowk_correction_only(const SimulationParams& params) {
    return !q9_target_filter_is_none(params) && params.q9EllipticLowPassPasses != 0;
}

void apply_q9_target_filter(const SimulationParams& params,
                            const EllipticProjectionGrid& egrid,
                            const EllipticProjectionBC& bc,
                            const PeriodicFaceField& alpha,
                            std::vector<double>& target,
                            Q9ProjectionWorkspace& ws,
                            Q9ProjectionDiagnostics& diag) {
    subtract_vector_mean(target);
    diag.targetDivergenceRawRms = vector_rms(target);
    if (q9_target_filter_is_none(params) || params.q9EllipticLowPassPasses == 0) {
        diag.targetDivergenceRms = diag.targetDivergenceRawRms;
        diag.targetDivergenceFilterRatio = 1.0;
        return;
    }
    if (!q9_target_filter_is_elliptic_lowpass(params)) {
        throw std::runtime_error("Unsupported q9TargetFilter in Q9 adapter: " + params.q9TargetFilter);
    }

    const EllipticLowPassParams filterParams = make_q9_lowpass_params(params, egrid);

    EllipticLowPassDiagnostics filterDiag{};
    target = elliptic_lowpass_cell_field(egrid, target, alpha, filterParams, bc, ws.elliptic, &filterDiag);

    diag.targetDivergenceRms = filterDiag.outputRms;
    diag.targetDivergenceFilterRatio = filterDiag.filterRatio;
}

void build_uniform_density_relaxation_target(const SimulationParams& params,
                                             const std::vector<double>& cellMass,
                                             std::vector<double>& target,
                                             Q9ProjectionDiagnostics& diag) {
    const int nc = static_cast<int>(cellMass.size());
    target.assign(static_cast<std::size_t>(nc), 0.0);
    if (nc <= 0) {
        return;
    }

    double sum = 0.0;
    double sum2 = 0.0;
#pragma omp parallel for reduction(+:sum,sum2) if(nc > 4096)
    for (int c = 0; c < nc; ++c) {
        const double m = cellMass[static_cast<std::size_t>(c)];
        sum += m;
        sum2 += m * m;
    }
    const double mean = sum / static_cast<double>(nc);
    const double var = std::max(0.0, sum2 / static_cast<double>(nc) - mean * mean);
    diag.densityMean = mean;
    diag.densityStdBefore = std::sqrt(var);

    const double beta = params.q9DensityRelaxationBeta;
    const double invDt = 1.0 / params.dt;
#pragma omp parallel for if(nc > 4096)
    for (int c = 0; c < nc; ++c) {
        const std::size_t k = static_cast<std::size_t>(c);
        // With continuity M_new = M - dt div(J_new), this raw target relaxes
        // M toward the mean by approximately beta per application. A separate
        // low-pass stage may then remove cell-scale occupancy noise, following
        // the MATLAB Q9 general_bc path.
        target[k] = beta * invDt * (cellMass[k] - mean);
    }
    diag.targetDivergenceRawRms = vector_rms(target);
    diag.targetDivergenceRms = diag.targetDivergenceRawRms;
    diag.targetDivergenceFilterRatio = 1.0;
}

void correction_flux_to_velocity_kick(const std::vector<double>& cellMass,
                                      const PeriodicFaceField& correctionFlux,
                                      double strength,
                                      std::vector<double>& dux,
                                      std::vector<double>& duy,
                                      PeriodicFaceField& appliedCorrectionFlux,
                                      Q9ProjectionDiagnostics& diag) {
    const int nc = static_cast<int>(cellMass.size());
    dux.assign(static_cast<std::size_t>(nc), 0.0);
    duy.assign(static_cast<std::size_t>(nc), 0.0);
    resize_periodic_face_field(appliedCorrectionFlux, nc);

    double sum2 = 0.0;
    double maxAbs = 0.0;
#pragma omp parallel for reduction(+:sum2) reduction(max:maxAbs) if(nc > 4096)
    for (int c = 0; c < nc; ++c) {
        const std::size_t k = static_cast<std::size_t>(c);
        const double dcx = strength * correctionFlux.x[k];
        const double dcy = strength * correctionFlux.y[k];
        appliedCorrectionFlux.x[k] = dcx;
        appliedCorrectionFlux.y[k] = dcy;
        if (cellMass[k] > 0.0) {
            dux[k] = dcx / cellMass[k];
            duy[k] = dcy / cellMass[k];
        }
        const double mag = std::sqrt(dux[k] * dux[k] + duy[k] * duy[k]);
        sum2 += dux[k] * dux[k] + duy[k] * duy[k];
        maxAbs = std::max(maxAbs, mag);
    }
    diag.correctionVelocityRms = nc > 0 ? std::sqrt(sum2 / static_cast<double>(nc)) : 0.0;
    diag.correctionVelocityMaxAbs = maxAbs;
}

std::vector<double> build_q9_projection_target(const SimulationParams& params,
                                                const EllipticProjectionGrid& egrid,
                                                const EllipticProjectionBC& bc,
                                                const PeriodicFaceField& baseFlux,
                                                const PeriodicFaceField& alpha,
                                                const std::vector<double>& densityTarget,
                                                Q9ProjectionWorkspace& ws) {
    if (!q9_lowk_correction_only(params)) {
        return densityTarget;
    }

    const std::vector<double> divBefore = compute_face_divergence(egrid, baseFlux, bc);
    std::vector<double> rhs(divBefore.size(), 0.0);
    const std::size_t n = divBefore.size();
#pragma omp parallel for if(n > 4096)
    for (std::int64_t ii = 0; ii < static_cast<std::int64_t>(n); ++ii) {
        const std::size_t k = static_cast<std::size_t>(ii);
        rhs[k] = densityTarget[k] - divBefore[k];
    }
    subtract_vector_mean(rhs);

    const EllipticLowPassParams filterParams = make_q9_lowpass_params(params, egrid);
    rhs = elliptic_lowpass_cell_field(egrid, rhs, alpha, filterParams, bc, ws.elliptic, nullptr);
    subtract_vector_mean(rhs);

    std::vector<double> projectionTarget(n, 0.0);
#pragma omp parallel for if(n > 4096)
    for (std::int64_t ii = 0; ii < static_cast<std::int64_t>(n); ++ii) {
        const std::size_t k = static_cast<std::size_t>(ii);
        projectionTarget[k] = divBefore[k] + rhs[k];
    }
    return projectionTarget;
}

void compute_estimated_density_after(const SimulationParams& params,
                                     const std::vector<double>& cellMass,
                                     const std::vector<double>& divAfter,
                                     std::vector<double>& massAfter,
                                     Q9ProjectionDiagnostics& diag) {
    const int nc = static_cast<int>(cellMass.size());
    massAfter.assign(static_cast<std::size_t>(nc), 0.0);
    if (nc <= 0) {
        return;
    }
    double sum = 0.0;
    double sum2 = 0.0;
#pragma omp parallel for reduction(+:sum,sum2) if(nc > 4096)
    for (int c = 0; c < nc; ++c) {
        const std::size_t k = static_cast<std::size_t>(c);
        const double m = cellMass[k] - params.dt * divAfter[k];
        massAfter[k] = m;
        sum += m;
        sum2 += m * m;
    }
    const double mean = sum / static_cast<double>(nc);
    const double var = std::max(0.0, sum2 / static_cast<double>(nc) - mean * mean);
    diag.densityStdAfterEstimate = std::sqrt(var);
    diag.densityStdRatioEstimate = diag.densityStdBefore > 0.0
        ? diag.densityStdAfterEstimate / diag.densityStdBefore
        : 0.0;
}

void apply_cell_velocity_kick(ParticleState& state,
                              const Q9ProjectionWorkspace& ws,
                              Q9ProjectionDiagnostics& diag,
                              bool momentumCorrectionEnable) {
    const std::size_t n = static_cast<std::size_t>(state.Np);
    double mass = 0.0;
    double dpx = 0.0;
    double dpy = 0.0;

#pragma omp parallel for reduction(+:mass,dpx,dpy) if(n > 10000)
    for (std::int64_t ii = 0; ii < static_cast<std::int64_t>(n); ++ii) {
        const std::size_t i = static_cast<std::size_t>(ii);
        const int c = ws.cellId[i];
        const std::size_t k = static_cast<std::size_t>(c);
        const double m = state.mass[i];
        mass += m;
        dpx += m * ws.cellDUx[k];
        dpy += m * ws.cellDUy[k];
        state.vx[i] += ws.cellDUx[k];
        state.vy[i] += ws.cellDUy[k];
    }

    diag.momentumResidualBeforeCorrection = std::sqrt(dpx * dpx + dpy * dpy);
    if (momentumCorrectionEnable && mass > 0.0) {
        const double cvx = dpx / mass;
        const double cvy = dpy / mass;
        diag.momentumCorrectionVx = cvx;
        diag.momentumCorrectionVy = cvy;
#pragma omp parallel for if(n > 10000)
        for (std::int64_t ii = 0; ii < static_cast<std::int64_t>(n); ++ii) {
            const std::size_t i = static_cast<std::size_t>(ii);
            state.vx[i] -= cvx;
            state.vy[i] -= cvy;
        }
    }
}

} // namespace

bool q9_projection_requested(const SimulationParams& params) {
    return params.q9MassFluxProjectionEnable || params.method == "q9" || params.method == "q9_virial";
}

Q9ProjectionDiagnostics apply_q9_mass_flux_projection(ParticleState& state,
                                                      const SimulationParams& params,
                                                      const CellGrid& grid,
                                                      Q9ProjectionWorkspace& workspace) {
    validate_particle_state(state, "apply_q9_mass_flux_projection");

    Q9ProjectionDiagnostics diag{};
    if (!q9_projection_requested(params)) {
        return diag;
    }

    const int nc = grid.numCells;
    const int nt = std::max(1, thread_count());
    resize_q9_workspace(workspace, state.Np, nc, nt);

    deposit_cell_mass_momentum(state, params, grid, workspace, diag);
    build_mass_flux_from_cell_momentum(grid, workspace.cellPx, workspace.cellPy, workspace.baseMassFlux);
    fill_alpha(workspace.alpha, nc, 1.0);
    build_uniform_density_relaxation_target(params, workspace.cellMass, workspace.targetDivergence, diag);

    const EllipticProjectionGrid egrid = make_elliptic_projection_grid(params.Nx, params.Ny, params.Lx, params.Ly);
    const EllipticProjectionBC bc = q9_bc_from_particle_boundaries(params);
    apply_q9_target_filter(params, egrid, bc, workspace.alpha, workspace.targetDivergence, workspace, diag);
    const std::vector<double> projectionTarget = build_q9_projection_target(
        params, egrid, bc, workspace.baseMassFlux, workspace.alpha, workspace.targetDivergence, workspace);

    EllipticProjectionParams eparams{};
    eparams.maxIterations = params.projectionMaxIterations;
    eparams.tolerance = params.projectionTolerance;
    eparams.removeRhsMean = true;
    eparams.removePhiMean = true;

    EllipticProjectionResult result = project_face_field(
        egrid, workspace.baseMassFlux, workspace.alpha, projectionTarget, eparams, bc, workspace.elliptic);

    diag.applied = true;
    diag.converged = result.diagnostics.converged;
    diag.iterations = result.diagnostics.iterations;
    diag.residualRel = result.diagnostics.residualRel;
    diag.massFluxDivBeforeRms = result.diagnostics.divBeforeRms;
    diag.massFluxDivBeforeMaxAbs = result.diagnostics.divBeforeMaxAbs;
    diag.massFluxDivAfterRms = result.diagnostics.divAfterRms;
    diag.massFluxDivAfterMaxAbs = result.diagnostics.divAfterMaxAbs;

    correction_flux_to_velocity_kick(workspace.cellMass,
                                     result.correctionFlux,
                                     params.q9MassFluxProjectionStrength,
                                     workspace.cellDUx,
                                     workspace.cellDUy,
                                     workspace.appliedCorrectionFlux,
                                     diag);

    if (params.q9MassFluxProjectionStrength == 1.0) {
        workspace.projectedMassFlux = result.projectedFlux;
        compute_estimated_density_after(params, workspace.cellMass, result.divAfter, workspace.massAfterEstimate, diag);
    } else {
#pragma omp parallel for if(nc > 4096)
        for (int c = 0; c < nc; ++c) {
            const std::size_t k = static_cast<std::size_t>(c);
            workspace.projectedMassFlux.x[k] = workspace.baseMassFlux.x[k] + workspace.appliedCorrectionFlux.x[k];
            workspace.projectedMassFlux.y[k] = workspace.baseMassFlux.y[k] + workspace.appliedCorrectionFlux.y[k];
        }
        const std::vector<double> divApplied = compute_face_divergence(egrid, workspace.projectedMassFlux, bc);
        double div2 = 0.0;
        double divMax = 0.0;
#pragma omp parallel for reduction(+:div2) reduction(max:divMax) if(nc > 4096)
        for (int c = 0; c < nc; ++c) {
            const double d = divApplied[static_cast<std::size_t>(c)];
            div2 += d * d;
            divMax = std::max(divMax, std::abs(d));
        }
        diag.massFluxDivAfterRms = nc > 0 ? std::sqrt(div2 / static_cast<double>(nc)) : 0.0;
        diag.massFluxDivAfterMaxAbs = divMax;
        compute_estimated_density_after(params, workspace.cellMass, divApplied, workspace.massAfterEstimate, diag);
    }

    apply_cell_velocity_kick(state, workspace, diag, params.q9MomentumCorrectionEnable);
    return diag;
}

} // namespace mpcd
