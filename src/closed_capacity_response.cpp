#include "closed_capacity_response.h"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <limits>
#include <stdexcept>

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

int cell_index_from_position(double x,
                             double y,
                             const SimulationParams& params,
                             const FluidDomainBounds& domain) {
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
    int ix = static_cast<int>(std::floor(xr / (width / static_cast<double>(params.Nx))));
    int iy = static_cast<int>(std::floor(yr / (height / static_cast<double>(params.Ny))));
    ix = std::clamp(ix, 0, params.Nx - 1);
    iy = std::clamp(iy, 0, params.Ny - 1);
    return ix + params.Nx * iy;
}

void resize_capacity_workspace(ClosedCapacityResponseWorkspace& ws,
                               int numCells,
                               std::uint64_t numParticles,
                               int numThreads) {
    if (numThreads <= 0) numThreads = 1;
    const bool same = ws.allocatedCells == numCells &&
                      ws.allocatedParticles == numParticles &&
                      static_cast<int>(ws.localMass.size()) == numThreads * numCells;
    if (same) return;
    ws.allocatedCells = numCells;
    ws.allocatedParticles = numParticles;
    ws.cellId.assign(static_cast<std::size_t>(numParticles), -1);
    ws.cellMass.assign(static_cast<std::size_t>(numCells), 0.0);
    ws.localMass.assign(static_cast<std::size_t>(numThreads * numCells), 0.0);
    ws.pressure.assign(static_cast<std::size_t>(numCells), 0.0);
    ws.kickVx.assign(static_cast<std::size_t>(numCells), 0.0);
    ws.kickVy.assign(static_cast<std::size_t>(numCells), 0.0);
}

void deposit_cell_mass_for_capacity(const ParticleState& state,
                                    const SimulationParams& params,
                                    const CellGrid& grid,
                                    const FluidDomainBounds& domain,
                                    ClosedCapacityResponseWorkspace& ws) {
    const int nc = grid.numCells;
    const int nt = std::max(1, thread_count());
    std::fill(ws.cellMass.begin(), ws.cellMass.end(), 0.0);
    std::fill(ws.localMass.begin(), ws.localMass.end(), 0.0);
    std::fill(ws.cellId.begin(), ws.cellId.end(), -1);

#pragma omp parallel
    {
        const int tid = thread_id();
        const std::size_t offset = static_cast<std::size_t>(tid * nc);
#pragma omp for
        for (std::int64_t ii = 0; ii < static_cast<std::int64_t>(state.Np); ++ii) {
            const std::size_t i = static_cast<std::size_t>(ii);
            if (!is_fluid_particle(state, i)) continue;
            const int c = cell_index_from_position(state.x[i], state.y[i], params, domain);
            ws.cellId[i] = c;
            ws.localMass[offset + static_cast<std::size_t>(c)] += state.mass[i];
        }
    }

#pragma omp parallel for if(nc > 256)
    for (int c = 0; c < nc; ++c) {
        double m = 0.0;
        for (int t = 0; t < nt; ++t) {
            m += ws.localMass[static_cast<std::size_t>(t * nc + c)];
        }
        ws.cellMass[static_cast<std::size_t>(c)] = m;
    }
}

double decay_factor(double overfill, double eta, double power) {
    if (!(overfill > 0.0)) return 1.0;
    if (!(eta > 0.0) || !(power > 0.0)) return 1.0;
    const double x = overfill / eta;
    return std::exp(-std::pow(x, power));
}

double growth_factor(double overfill, double eta, double power, double gain) {
    if (!(overfill > 0.0)) return 1.0;
    if (!(eta > 0.0) || !(power > 0.0) || !(gain > 0.0)) return 1.0;
    const double x = overfill / eta;
    return 1.0 + gain * std::pow(x, power);
}

bool cell_active(const std::vector<std::uint8_t>* mask, std::size_t k) {
    return mask == nullptr || mask->empty() || (*mask)[k] != 0u;
}

} // namespace

bool closed_capacity_response_requested(const SimulationParams& params) {
    return params.closedCapacityResponseEnable;
}

double closed_capacity_reference_cell_mass(const SimulationParams& params) {
    if (params.closedCapacityReferenceCellMass > 0.0) {
        return params.closedCapacityReferenceCellMass;
    }
    if (params.resamplingTargetCellMass > 0.0) {
        return params.resamplingTargetCellMass;
    }
    if (params.inletTargetOccupancy > 0) {
        return static_cast<double>(params.inletTargetOccupancy) * params.closedCapacityReferenceParticleMass;
    }
    return 0.0;
}

ClosedCapacityResponseDiagnostics compute_closed_capacity_response_from_cell_masses(
    const SimulationParams& params,
    const CellGrid& grid,
    const FluidDomainBounds&,
    const std::vector<double>& cellMass,
    const std::vector<std::uint8_t>* activeCellMask,
    double q6NominalStrength) {
    ClosedCapacityResponseDiagnostics d{};
    d.enabled = params.closedCapacityResponseEnable;
    d.q6ProjectionStrengthNominal = q6NominalStrength;
    d.q6ProjectionStrengthEffective = q6NominalStrength;
    d.virialKBase = params.closedCapacityVirialBaseK;

    if (!params.closedCapacityResponseEnable) {
        return d;
    }
    if (static_cast<int>(cellMass.size()) != grid.numCells) {
        throw std::runtime_error("compute_closed_capacity_response_from_cell_masses: invalid cell mass size");
    }

    const double refCellMass = closed_capacity_reference_cell_mass(params);
    if (!(refCellMass > 0.0) || !std::isfinite(refCellMass)) {
        return d;
    }

    double totalMass = 0.0;
    std::uint64_t referenceCells = 0u;
    const std::size_t nc = cellMass.size();
#pragma omp parallel for reduction(+:totalMass,referenceCells) if(nc > 4096)
    for (std::int64_t ii = 0; ii < static_cast<std::int64_t>(nc); ++ii) {
        const std::size_t k = static_cast<std::size_t>(ii);
        if (!cell_active(activeCellMask, k)) continue;
        totalMass += cellMass[k];
        referenceCells += 1u;
    }

    const double referenceMass = static_cast<double>(referenceCells) * refCellMass;
    d.computed = referenceCells > 0u && referenceMass > 0.0;
    d.referenceCells = referenceCells;
    d.referenceCellMass = refCellMass;
    d.referenceMass = referenceMass;
    d.totalMass = totalMass;
    if (!d.computed) {
        return d;
    }

    d.overfillMass = std::max(0.0, totalMass - referenceMass);
    d.overfillRatio = d.overfillMass / referenceMass;
    d.q6ProjectionFactor = decay_factor(d.overfillRatio,
                                        params.closedCapacityQ6Eta,
                                        params.closedCapacityQ6Power);
    d.q6ProjectionStrengthEffective = q6NominalStrength * d.q6ProjectionFactor;
    d.massRemapFactor = decay_factor(d.overfillRatio,
                                     params.closedCapacityMassRemapEta,
                                     params.closedCapacityMassRemapPower);
    d.virialKFactor = growth_factor(d.overfillRatio,
                                    params.closedCapacityVirialEta,
                                    params.closedCapacityVirialPower,
                                    params.closedCapacityVirialGain);
    d.virialKEffective = params.closedCapacityVirialBaseK * d.virialKFactor;
    return d;
}

ClosedCapacityResponseDiagnostics apply_closed_capacity_virial_kick(
    ParticleState& state,
    const SimulationParams& params,
    const CellGrid& grid,
    const FluidDomainBounds& domain,
    ClosedCapacityResponseWorkspace& ws) {
    validate_particle_state(state, "apply_closed_capacity_virial_kick");
    ensure_particle_roles(state, ParticleRole::Fluid);

    const int nc = grid.numCells;
    const int nt = std::max(1, thread_count());
    resize_capacity_workspace(ws, nc, state.Np, nt);
    deposit_cell_mass_for_capacity(state, params, grid, domain, ws);

    ClosedCapacityResponseDiagnostics d = compute_closed_capacity_response_from_cell_masses(
        params, grid, domain, ws.cellMass, nullptr, params.q6ProjectionStrength);
    if (!d.enabled || !d.computed) {
        return d;
    }

    if (!params.closedCapacityVirialKickEnable || !(d.virialKEffective > 0.0)) {
        return d;
    }

    const double refCellMass = d.referenceCellMass;
    double pSum = 0.0;
    double p2 = 0.0;
    double pMin = std::numeric_limits<double>::infinity();
    double pMax = -std::numeric_limits<double>::infinity();
#pragma omp parallel for reduction(+:pSum,p2) reduction(min:pMin) reduction(max:pMax) if(nc > 4096)
    for (int c = 0; c < nc; ++c) {
        const std::size_t k = static_cast<std::size_t>(c);
        const double pvir = d.virialKEffective * (ws.cellMass[k] / refCellMass - 1.0);
        ws.pressure[k] = pvir;
        pSum += pvir;
        p2 += pvir * pvir;
        pMin = std::min(pMin, pvir);
        pMax = std::max(pMax, pvir);
    }
    d.virialPressureMean = nc > 0 ? pSum / static_cast<double>(nc) : 0.0;
    d.virialPressureRms = nc > 0 ? std::sqrt(p2 / static_cast<double>(nc)) : 0.0;
    d.virialPressureMin = std::isfinite(pMin) ? pMin : 0.0;
    d.virialPressureMax = std::isfinite(pMax) ? pMax : 0.0;

    const double width = fluid_domain_width(domain);
    const double height = fluid_domain_height(domain);
    const double dx = width / static_cast<double>(std::max(1, params.Nx));
    const double dy = height / static_cast<double>(std::max(1, params.Ny));
    const double area = dx * dy;
    const bool px = is_x_periodic(params);
    const bool py = is_y_periodic(params);

    double kick2 = 0.0;
    double kickMax = 0.0;
#pragma omp parallel for reduction(+:kick2) reduction(max:kickMax) if(nc > 4096)
    for (int j = 0; j < params.Ny; ++j) {
        for (int i = 0; i < params.Nx; ++i) {
            const int c = i + params.Nx * j;
            const std::size_t k = static_cast<std::size_t>(c);
            const int im = (i > 0) ? (i - 1) : (px ? params.Nx - 1 : i);
            const int ip = (i + 1 < params.Nx) ? (i + 1) : (px ? 0 : i);
            const int jm = (j > 0) ? (j - 1) : (py ? params.Ny - 1 : j);
            const int jp = (j + 1 < params.Ny) ? (j + 1) : (py ? 0 : j);
            const double denomX = (im == i || ip == i) ? dx : (2.0 * dx);
            const double denomY = (jm == j || jp == j) ? dy : (2.0 * dy);
            const double dpdx = (ws.pressure[static_cast<std::size_t>(ip + params.Nx * j)] -
                                 ws.pressure[static_cast<std::size_t>(im + params.Nx * j)]) / denomX;
            const double dpdy = (ws.pressure[static_cast<std::size_t>(i + params.Nx * jp)] -
                                 ws.pressure[static_cast<std::size_t>(i + params.Nx * jm)]) / denomY;
            const double rho = ws.cellMass[k] / std::max(area, 1.0e-300);
            const double invRho = rho > 1.0e-300 ? 1.0 / rho : 0.0;
            const double dvx = -params.closedCapacityVirialKickStrength * params.dt * dpdx * invRho;
            const double dvy = -params.closedCapacityVirialKickStrength * params.dt * dpdy * invRho;
            ws.kickVx[k] = std::isfinite(dvx) ? dvx : 0.0;
            ws.kickVy[k] = std::isfinite(dvy) ? dvy : 0.0;
            const double kmag = std::sqrt(ws.kickVx[k] * ws.kickVx[k] + ws.kickVy[k] * ws.kickVy[k]);
            kick2 += kmag * kmag;
            kickMax = std::max(kickMax, kmag);
        }
    }
    d.virialKickVelocityRms = nc > 0 ? std::sqrt(kick2 / static_cast<double>(nc)) : 0.0;
    d.virialKickVelocityMaxAbs = kickMax;

    double mass = 0.0;
    double dpx = 0.0;
    double dpy = 0.0;
#pragma omp parallel for reduction(+:mass,dpx,dpy) if(state.Np > 10000)
    for (std::int64_t ii = 0; ii < static_cast<std::int64_t>(state.Np); ++ii) {
        const std::size_t i = static_cast<std::size_t>(ii);
        if (!is_fluid_particle(state, i)) continue;
        const int c = ws.cellId[i];
        if (c < 0 || c >= nc) continue;
        const std::size_t k = static_cast<std::size_t>(c);
        const double m = state.mass[i];
        const double dvx = ws.kickVx[k];
        const double dvy = ws.kickVy[k];
        state.vx[i] += dvx;
        state.vy[i] += dvy;
        mass += m;
        dpx += m * dvx;
        dpy += m * dvy;
    }
    d.virialMomentumResidualBeforeCorrection = std::sqrt(dpx * dpx + dpy * dpy);
    if (params.closedCapacityVirialMomentumCorrectionEnable && mass > 0.0) {
        const double cvx = dpx / mass;
        const double cvy = dpy / mass;
        d.virialMomentumCorrectionVx = cvx;
        d.virialMomentumCorrectionVy = cvy;
#pragma omp parallel for if(state.Np > 10000)
        for (std::int64_t ii = 0; ii < static_cast<std::int64_t>(state.Np); ++ii) {
            const std::size_t i = static_cast<std::size_t>(ii);
            if (!is_fluid_particle(state, i)) continue;
            state.vx[i] -= cvx;
            state.vy[i] -= cvy;
        }
    }
    d.virialKickApplied = true;
    return d;
}

} // namespace mpcd
