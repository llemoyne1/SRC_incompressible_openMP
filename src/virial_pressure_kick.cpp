#include "virial_pressure_kick.h"

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

void resize_workspace(VirialPressureWorkspace& ws,
                      std::uint64_t numParticles,
                      int numCells,
                      int numThreads) {
    if (numCells <= 0) {
        throw std::runtime_error("resize_virial_workspace: invalid number of cells");
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
    ws.cellCount.assign(nc, 0.0);
    ws.cellPx.assign(nc, 0.0);
    ws.cellPy.assign(nc, 0.0);
    ws.cellRelKinetic.assign(nc, 0.0);
    ws.cellRho.assign(nc, 0.0);
    ws.cellTemperature.assign(nc, 0.0);
    ws.Pkin.assign(nc, 0.0);
    ws.PvirEOS.assign(nc, 0.0);
    ws.PtotEOS.assign(nc, 0.0);
    ws.Pdrive.assign(nc, 0.0);
    ws.gradPx.assign(nc, 0.0);
    ws.gradPy.assign(nc, 0.0);
    ws.dux.assign(nc, 0.0);
    ws.duy.assign(nc, 0.0);

    ws.localMass.assign(nLocal, 0.0);
    ws.localCount.assign(nLocal, 0.0);
    ws.localPx.assign(nLocal, 0.0);
    ws.localPy.assign(nLocal, 0.0);
    ws.localRelKinetic.assign(nLocal, 0.0);
}

int active_domain_cell_index(double x,
                             double y,
                             const FluidDomainBounds& domain,
                             const SimulationParams& params) {
    const double width = fluid_domain_width(domain);
    const double height = fluid_domain_height(domain);
    double xr = x - domain.xMin;
    double yr = y - domain.yMin;
    if (is_x_periodic(params)) {
        xr = std::fmod(xr, width);
        if (xr < 0.0) xr += width;
    } else {
        xr = std::clamp(xr, 0.0, width);
    }
    if (is_y_periodic(params)) {
        yr = std::fmod(yr, height);
        if (yr < 0.0) yr += height;
    } else {
        yr = std::clamp(yr, 0.0, height);
    }

    const double dx = width / static_cast<double>(params.Nx);
    const double dy = height / static_cast<double>(params.Ny);
    int ix = static_cast<int>(std::floor(xr / dx));
    int iy = static_cast<int>(std::floor(yr / dy));
    ix = std::clamp(ix, 0, params.Nx - 1);
    iy = std::clamp(iy, 0, params.Ny - 1);
    return ix + params.Nx * iy;
}

void deposit_cell_mass_momentum(const ParticleState& state,
                                const SimulationParams& params,
                                const FluidDomainBounds& domain,
                                VirialPressureWorkspace& ws) {
    const std::size_t n = static_cast<std::size_t>(state.Np);
    const int nc = params.Nx * params.Ny;
    const int nt = std::max(1, thread_count());

    std::fill(ws.cellMass.begin(), ws.cellMass.end(), 0.0);
    std::fill(ws.cellCount.begin(), ws.cellCount.end(), 0.0);
    std::fill(ws.cellPx.begin(), ws.cellPx.end(), 0.0);
    std::fill(ws.cellPy.begin(), ws.cellPy.end(), 0.0);
    std::fill(ws.cellRelKinetic.begin(), ws.cellRelKinetic.end(), 0.0);
    std::fill(ws.localMass.begin(), ws.localMass.end(), 0.0);
    std::fill(ws.localCount.begin(), ws.localCount.end(), 0.0);
    std::fill(ws.localPx.begin(), ws.localPx.end(), 0.0);
    std::fill(ws.localPy.begin(), ws.localPy.end(), 0.0);
    std::fill(ws.localRelKinetic.begin(), ws.localRelKinetic.end(), 0.0);

#pragma omp parallel
    {
        const int tid = thread_id();
        const std::size_t offset = static_cast<std::size_t>(tid * nc);
#pragma omp for
        for (std::int64_t ii = 0; ii < static_cast<std::int64_t>(n); ++ii) {
            const std::size_t i = static_cast<std::size_t>(ii);
            const int c = active_domain_cell_index(state.x[i], state.y[i], domain, params);
            ws.cellId[i] = c;
            const std::size_t k = offset + static_cast<std::size_t>(c);
            const double m = state.mass[i];
            ws.localMass[k] += m;
            ws.localCount[k] += 1.0;
            ws.localPx[k] += m * state.vx[i];
            ws.localPy[k] += m * state.vy[i];
        }
    }

#pragma omp parallel for if(nc > 256)
    for (int c = 0; c < nc; ++c) {
        double m = 0.0;
        double cnt = 0.0;
        double px = 0.0;
        double py = 0.0;
        for (int t = 0; t < nt; ++t) {
            const std::size_t k = static_cast<std::size_t>(t * nc + c);
            m += ws.localMass[k];
            cnt += ws.localCount[k];
            px += ws.localPx[k];
            py += ws.localPy[k];
        }
        const std::size_t kk = static_cast<std::size_t>(c);
        ws.cellMass[kk] = m;
        ws.cellCount[kk] = cnt;
        ws.cellPx[kk] = px;
        ws.cellPy[kk] = py;
    }

    // Second pass for cell-relative kinetic temperature.
#pragma omp parallel
    {
        const int tid = thread_id();
        const std::size_t offset = static_cast<std::size_t>(tid * nc);
#pragma omp for
        for (std::int64_t ii = 0; ii < static_cast<std::int64_t>(n); ++ii) {
            const std::size_t i = static_cast<std::size_t>(ii);
            const int c = ws.cellId[i];
            const std::size_t kc = static_cast<std::size_t>(c);
            double ux = 0.0;
            double uy = 0.0;
            if (ws.cellMass[kc] > 0.0) {
                ux = ws.cellPx[kc] / ws.cellMass[kc];
                uy = ws.cellPy[kc] / ws.cellMass[kc];
            }
            const double dvx = state.vx[i] - ux;
            const double dvy = state.vy[i] - uy;
            const double m = state.mass[i];
            ws.localRelKinetic[offset + kc] += m * (dvx * dvx + dvy * dvy);
        }
    }

#pragma omp parallel for if(nc > 256)
    for (int c = 0; c < nc; ++c) {
        double rel = 0.0;
        for (int t = 0; t < nt; ++t) {
            rel += ws.localRelKinetic[static_cast<std::size_t>(t * nc + c)];
        }
        ws.cellRelKinetic[static_cast<std::size_t>(c)] = rel;
    }
}

std::string canonical(std::string s) {
    std::transform(s.begin(), s.end(), s.begin(), [](unsigned char ch) {
        return static_cast<char>(std::tolower(ch));
    });
    std::replace(s.begin(), s.end(), '-', '_');
    return s;
}

double initial_domain_area(const SimulationParams& params) {
    const double xMax0 = params.fluidXMax0 >= 0.0 ? params.fluidXMax0 : params.Lx;
    const double yMax0 = params.fluidYMax0 >= 0.0 ? params.fluidYMax0 : params.Ly;
    return std::max(0.0, xMax0 - params.fluidXMin0) * std::max(0.0, yMax0 - params.fluidYMin0);
}

double resolve_rho_eos_ref(const SimulationParams& params,
                           const ParticleState& state,
                           double rhoMean) {
    const std::string mode = canonical(params.virialRhoEOSRefMode);
    if (mode == "initial_physical_density" || mode == "initial" || mode == "rho0") {
        const double area0 = initial_domain_area(params);
        return area0 > 0.0 ? static_cast<double>(state.Np) / area0 : rhoMean;
    }
    if (mode == "current_uniform" || mode == "uniform_now" || mode == "rho_mean") {
        return rhoMean;
    }
    if (mode == "explicit" || mode == "user") {
        return params.virialRhoEOSRef;
    }
    throw std::runtime_error("Unknown virialRhoEOSRefMode: " + params.virialRhoEOSRefMode);
}

double resolve_rho_uniform_now(const SimulationParams& params,
                               const ParticleState& state,
                               const FluidDomainBounds& domain,
                               double rhoMean) {
    const std::string mode = canonical(params.virialRhoUniformMode);
    if (mode == "reference_gamma_current_volume" || mode == "current_volume" || mode == "gamma_current_volume") {
        const double area = fluid_domain_area(domain);
        return area > 0.0 ? static_cast<double>(state.Np) / area : rhoMean;
    }
    if (mode == "particle_mean" || mode == "rho_mean" || mode == "actual") {
        return rhoMean;
    }
    if (mode == "explicit" || mode == "user") {
        return params.virialRhoUniformNow;
    }
    throw std::runtime_error("Unknown virialRhoUniformMode: " + params.virialRhoUniformMode);
}

double resolve_rho_drive_ref(const SimulationParams& params,
                             double rhoEOSRef,
                             double rhoUniformNow) {
    const std::string mode = canonical(params.virialDriveTargetMode);
    if (mode == "current_uniform" || mode == "uniform_now" || mode == "rho_uniform_now" || mode == "historical") {
        return rhoUniformNow;
    }
    if (mode == "eos_ref" || mode == "initial" || mode == "initial_density" || mode == "rho_eos_ref") {
        return rhoEOSRef;
    }
    if (mode == "zero" || mode == "none") {
        return 0.0;
    }
    throw std::runtime_error("Unknown virialDriveTargetMode: " + params.virialDriveTargetMode);
}

void compute_pressure_maps(const ParticleState& state,
                           const SimulationParams& params,
                           const FluidDomainBounds& domain,
                           VirialPressureWorkspace& ws,
                           VirialPressureDiagnostics& diag) {
    const int nc = params.Nx * params.Ny;
    const double area = fluid_domain_area(domain);
    const double cellArea = area / static_cast<double>(std::max(1, nc));
    diag.rhoMean = area > 0.0 ? static_cast<double>(state.Np) / area : 0.0;
    diag.rhoEOSRef = resolve_rho_eos_ref(params, state, diag.rhoMean);
    diag.rhoUniformNow = resolve_rho_uniform_now(params, state, domain, diag.rhoMean);
    diag.rhoDriveRef = resolve_rho_drive_ref(params, diag.rhoEOSRef, diag.rhoUniformNow);

    double rhoDef2 = 0.0;
    double pkinSum = 0.0;
    double pvirSum = 0.0;
    double ptotSum = 0.0;
    double pdriveSum = 0.0;
    double rhoMin = std::numeric_limits<double>::infinity();
    double rhoMax = 0.0;
    double pkinMin = std::numeric_limits<double>::infinity();
    double pkinMax = -std::numeric_limits<double>::infinity();
    double pvirMin = std::numeric_limits<double>::infinity();
    double pvirMax = -std::numeric_limits<double>::infinity();
    double ptotMin = std::numeric_limits<double>::infinity();
    double ptotMax = -std::numeric_limits<double>::infinity();

#pragma omp parallel for reduction(+:rhoDef2,pkinSum,pvirSum,ptotSum,pdriveSum) reduction(min:rhoMin,pkinMin,pvirMin,ptotMin) reduction(max:rhoMax,pkinMax,pvirMax,ptotMax) if(nc > 256)
    for (int c = 0; c < nc; ++c) {
        const std::size_t k = static_cast<std::size_t>(c);
        const double rho = cellArea > 0.0 ? ws.cellMass[k] / cellArea : 0.0;
        double temp = 0.0;
        if (ws.cellCount[k] > 1.0) {
            temp = ws.cellRelKinetic[k] / (2.0 * (ws.cellCount[k] - 1.0));
        }
        const double pkin = rho * std::max(0.0, temp);
        const double pvir = params.Kvirial * (rho - diag.rhoEOSRef);
        const double ptot = pkin + pvir;
        const double pdrive = pkin + params.Kvirial * (rho - diag.rhoDriveRef);

        ws.cellRho[k] = rho;
        ws.cellTemperature[k] = temp;
        ws.Pkin[k] = pkin;
        ws.PvirEOS[k] = pvir;
        ws.PtotEOS[k] = ptot;
        ws.Pdrive[k] = pdrive;

        const double dr = rho - diag.rhoUniformNow;
        rhoDef2 += dr * dr;
        pkinSum += pkin;
        pvirSum += pvir;
        ptotSum += ptot;
        pdriveSum += pdrive;
        rhoMin = std::min(rhoMin, rho);
        rhoMax = std::max(rhoMax, rho);
        pkinMin = std::min(pkinMin, pkin);
        pkinMax = std::max(pkinMax, pkin);
        pvirMin = std::min(pvirMin, pvir);
        pvirMax = std::max(pvirMax, pvir);
        ptotMin = std::min(ptotMin, ptot);
        ptotMax = std::max(ptotMax, ptot);
    }

    const double invNc = nc > 0 ? 1.0 / static_cast<double>(nc) : 0.0;
    diag.rhoDefectRms = std::sqrt(std::max(0.0, rhoDef2 * invNc));
    diag.rhoDefectRelRms = diag.rhoUniformNow != 0.0 ? diag.rhoDefectRms / std::abs(diag.rhoUniformNow) : 0.0;
    diag.rhoMin = std::isfinite(rhoMin) ? rhoMin : 0.0;
    diag.rhoMax = rhoMax;
    diag.PkinMean = pkinSum * invNc;
    diag.PvirMean = pvirSum * invNc;
    diag.PtotMean = ptotSum * invNc;
    diag.PdriveMean = pdriveSum * invNc;
    diag.PkinMin = std::isfinite(pkinMin) ? pkinMin : 0.0;
    diag.PkinMax = std::isfinite(pkinMax) ? pkinMax : 0.0;
    diag.PvirMin = std::isfinite(pvirMin) ? pvirMin : 0.0;
    diag.PvirMax = std::isfinite(pvirMax) ? pvirMax : 0.0;
    diag.PtotMin = std::isfinite(ptotMin) ? ptotMin : 0.0;
    diag.PtotMax = std::isfinite(ptotMax) ? ptotMax : 0.0;
}

double field_at(const std::vector<double>& f, int ix, int iy, int Nx) {
    return f[static_cast<std::size_t>(ix + Nx * iy)];
}

void compute_boundary_aware_gradient(const SimulationParams& params,
                                     const FluidDomainBounds& domain,
                                     const std::vector<double>& f,
                                     std::vector<double>& gx,
                                     std::vector<double>& gy,
                                     VirialPressureDiagnostics& diag) {
    const int Nx = params.Nx;
    const int Ny = params.Ny;
    const int nc = Nx * Ny;
    const double dx = fluid_domain_width(domain) / static_cast<double>(Nx);
    const double dy = fluid_domain_height(domain) / static_cast<double>(Ny);
    gx.assign(static_cast<std::size_t>(nc), 0.0);
    gy.assign(static_cast<std::size_t>(nc), 0.0);

    double sum2 = 0.0;
    double maxAbs = 0.0;
#pragma omp parallel for reduction(+:sum2) reduction(max:maxAbs) if(nc > 256)
    for (int iy = 0; iy < Ny; ++iy) {
        for (int ix = 0; ix < Nx; ++ix) {
            const int c = ix + Nx * iy;
            double dfdx = 0.0;
            double dfdy = 0.0;
            if (is_x_periodic(params)) {
                const int im = (ix + Nx - 1) % Nx;
                const int ip = (ix + 1) % Nx;
                dfdx = (field_at(f, ip, iy, Nx) - field_at(f, im, iy, Nx)) / (2.0 * dx);
            } else if (Nx > 1) {
                if (ix == 0) {
                    dfdx = (field_at(f, 1, iy, Nx) - field_at(f, 0, iy, Nx)) / dx;
                } else if (ix == Nx - 1) {
                    dfdx = (field_at(f, Nx - 1, iy, Nx) - field_at(f, Nx - 2, iy, Nx)) / dx;
                } else {
                    dfdx = (field_at(f, ix + 1, iy, Nx) - field_at(f, ix - 1, iy, Nx)) / (2.0 * dx);
                }
            }
            if (is_y_periodic(params)) {
                const int jm = (iy + Ny - 1) % Ny;
                const int jp = (iy + 1) % Ny;
                dfdy = (field_at(f, ix, jp, Nx) - field_at(f, ix, jm, Nx)) / (2.0 * dy);
            } else if (Ny > 1) {
                if (iy == 0) {
                    dfdy = (field_at(f, ix, 1, Nx) - field_at(f, ix, 0, Nx)) / dy;
                } else if (iy == Ny - 1) {
                    dfdy = (field_at(f, ix, Ny - 1, Nx) - field_at(f, ix, Ny - 2, Nx)) / dy;
                } else {
                    dfdy = (field_at(f, ix, iy + 1, Nx) - field_at(f, ix, iy - 1, Nx)) / (2.0 * dy);
                }
            }
            const std::size_t k = static_cast<std::size_t>(c);
            gx[k] = dfdx;
            gy[k] = dfdy;
            const double mag2 = dfdx * dfdx + dfdy * dfdy;
            sum2 += mag2;
            maxAbs = std::max(maxAbs, std::sqrt(mag2));
        }
    }
    diag.gradPdriveRms = nc > 0 ? std::sqrt(sum2 / static_cast<double>(nc)) : 0.0;
    diag.gradPdriveMaxAbs = maxAbs;
}

void compute_virial_velocity_kick(const SimulationParams& params,
                                  const VirialPressureWorkspace& ws,
                                  VirialPressureWorkspace& out,
                                  const VirialPressureDiagnostics& inDiag,
                                  VirialPressureDiagnostics& diag) {
    const int nc = params.Nx * params.Ny;
    const std::string rhoKickMode = canonical(params.virialRhoKickMode);
    const double rhoMin = params.virialRhoKickMinFraction * std::max(inDiag.rhoUniformNow, 1.0e-300);
    double raw2 = 0.0;
    double applied2 = 0.0;
    double appliedMax = 0.0;
#pragma omp parallel for reduction(+:raw2,applied2) reduction(max:appliedMax) if(nc > 256)
    for (int c = 0; c < nc; ++c) {
        const std::size_t k = static_cast<std::size_t>(c);
        double rhoKick = inDiag.rhoUniformNow;
        if (rhoKickMode == "local" || rhoKickMode == "cell" || rhoKickMode == "rho_local") {
            rhoKick = std::max(ws.cellRho[k], rhoMin);
        } else if (!(rhoKickMode == "uniform_now" || rhoKickMode == "current_uniform" || rhoKickMode == "constant")) {
            // Validation of the string happens in validate_simulation_params; keep this branch safe.
            rhoKick = inDiag.rhoUniformNow;
        }
        double duxRaw = 0.0;
        double duyRaw = 0.0;
        if (rhoKick > 0.0 && std::isfinite(rhoKick)) {
            duxRaw = -params.dt * out.gradPx[k] / rhoKick;
            duyRaw = -params.dt * out.gradPy[k] / rhoKick;
        }
        const double dux = params.virialBeta * duxRaw;
        const double duy = params.virialBeta * duyRaw;
        out.dux[k] = dux;
        out.duy[k] = duy;
        raw2 += duxRaw * duxRaw + duyRaw * duyRaw;
        applied2 += dux * dux + duy * duy;
        appliedMax = std::max(appliedMax, std::sqrt(dux * dux + duy * duy));
    }
    diag.duVirialRawRms = nc > 0 ? std::sqrt(raw2 / static_cast<double>(nc)) : 0.0;
    diag.duVirialAppliedRms = nc > 0 ? std::sqrt(applied2 / static_cast<double>(nc)) : 0.0;
    diag.duVirialAppliedMaxAbs = appliedMax;
    const double thermal = params.kBT > 0.0 ? std::sqrt(params.kBT) : 0.0;
    diag.duVirialOverThermalRms = thermal > 0.0 ? diag.duVirialAppliedRms / thermal : 0.0;
}

void apply_cell_kick_to_particles(ParticleState& state,
                                  const VirialPressureWorkspace& ws,
                                  VirialPressureDiagnostics& diag,
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
        dpx += m * ws.dux[k];
        dpy += m * ws.duy[k];
        state.vx[i] += ws.dux[k];
        state.vy[i] += ws.duy[k];
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
        diag.momentumResidualAfterCorrection = 0.0;
    } else {
        diag.momentumResidualAfterCorrection = diag.momentumResidualBeforeCorrection;
    }
}

} // namespace

bool virial_pressure_requested(const SimulationParams& params) {
    return params.virialDiagnosticsEnable || params.virialKickEnable || params.method == "q9_virial";
}

VirialPressureDiagnostics apply_virial_pressure_kick(ParticleState& state,
                                                     const SimulationParams& params,
                                                     const CellGrid& grid,
                                                     const FluidDomainBounds& domain,
                                                     VirialPressureWorkspace& workspace) {
    (void)grid;
    validate_particle_state(state, "apply_virial_pressure_kick");

    VirialPressureDiagnostics diag{};
    if (!virial_pressure_requested(params)) {
        return diag;
    }

    diag.enabled = true;
    diag.diagnosticsEnabled = params.virialDiagnosticsEnable || params.method == "q9_virial";
    diag.kickEnabled = params.virialKickEnable || params.method == "q9_virial";
    diag.Kvirial = params.Kvirial;
    diag.betaVirial = params.virialBeta;

    const int nc = params.Nx * params.Ny;
    const int nt = std::max(1, thread_count());
    resize_workspace(workspace, state.Np, nc, nt);
    deposit_cell_mass_momentum(state, params, domain, workspace);
    compute_pressure_maps(state, params, domain, workspace, diag);
    compute_boundary_aware_gradient(params, domain, workspace.Pdrive, workspace.gradPx, workspace.gradPy, diag);
    compute_virial_velocity_kick(params, workspace, workspace, diag, diag);

    if (diag.kickEnabled && params.Kvirial != 0.0 && params.virialBeta != 0.0) {
        diag.kickApplied = true;
        apply_cell_kick_to_particles(state, workspace, diag, params.virialMomentumCorrectionEnable);
    }

    return diag;
}

} // namespace mpcd
