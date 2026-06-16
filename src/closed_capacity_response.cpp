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
                                    ClosedCapacityResponseWorkspace& ws,
                                    const std::vector<std::uint64_t>* fluidSlots = nullptr) {
    const int nc = grid.numCells;
    const std::size_t n = static_cast<std::size_t>(state.Np);
    const bool useFluidSlots = fluidSlots != nullptr;
    const int nt = std::max(1, thread_count());
    std::fill(ws.cellMass.begin(), ws.cellMass.end(), 0.0);
    std::fill(ws.localMass.begin(), ws.localMass.end(), 0.0);
    std::fill(ws.cellId.begin(), ws.cellId.end(), -1);

#pragma omp parallel
    {
        const int tid = thread_id();
        const std::size_t offset = static_cast<std::size_t>(tid * nc);
#pragma omp for
        for (std::int64_t ii = 0; ii < static_cast<std::int64_t>(useFluidSlots ? fluidSlots->size() : n); ++ii) {
            const std::size_t i = useFluidSlots
                ? static_cast<std::size_t>((*fluidSlots)[static_cast<std::size_t>(ii)])
                : static_cast<std::size_t>(ii);
            if (i >= n) continue;
            if (!useFluidSlots && !is_fluid_particle(state, i)) continue;
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

struct WallLoadAccum {
    double length = 0.0;
    double kinetic = 0.0;
    double virial = 0.0;
    double total = 0.0;
};

double capacity_wall_kbt_estimate(const SimulationParams& params) {
    if (params.thermostatTargetKBT > 0.0 && std::isfinite(params.thermostatTargetKBT)) {
        return params.thermostatTargetKBT;
    }
    if (params.kBT > 0.0 && std::isfinite(params.kBT)) {
        return params.kBT;
    }
    return 0.0;
}

const std::string& face_mode(const SimulationParams& params, const char* face) {
    const std::string name(face);
    if (name == "left") return params.bcLeft;
    if (name == "right") return params.bcRight;
    if (name == "bottom") return params.bcBottom;
    return params.bcTop;
}

bool face_segment_covers(const OpenBoundarySegment& seg, const char* face, double s) {
    if (seg.face != face) return false;
    const double a = std::min(seg.sMin, seg.sMax);
    const double b = std::max(seg.sMin, seg.sMax);
    return s >= a && s <= b;
}

bool solid_wall_portion(const SimulationParams& params, const char* face, double s) {
    const std::string& mode = face_mode(params, face);
    if (!is_solid_wall_mode(mode)) {
        return false;
    }
    if (params.openBoundarySegmentsEnable) {
        for (const OpenBoundarySegment& seg : params.openBoundarySegments) {
            if ((is_inlet_boundary_mode(seg.mode) || is_outlet_boundary_mode(seg.mode)) &&
                face_segment_covers(seg, face, s)) {
                return false;
            }
        }
    }
    return true;
}

void add_wall_cell_load(WallLoadAccum& side,
                        double segmentLength,
                        double pKin,
                        double pVir,
                        double nx,
                        double ny,
                        double& fKinX,
                        double& fKinY,
                        double& fVirX,
                        double& fVirY,
                        double& fTotX,
                        double& fTotY) {
    const double pTot = pKin + pVir;
    side.length += segmentLength;
    side.kinetic += pKin * segmentLength;
    side.virial += pVir * segmentLength;
    side.total += pTot * segmentLength;
    fKinX += pKin * segmentLength * nx;
    fKinY += pKin * segmentLength * ny;
    fVirX += pVir * segmentLength * nx;
    fVirY += pVir * segmentLength * ny;
    fTotX += pTot * segmentLength * nx;
    fTotY += pTot * segmentLength * ny;
}

double mean_pressure(const WallLoadAccum& a, double load) {
    return a.length > 0.0 ? load / a.length : 0.0;
}

void compute_closed_capacity_wall_loads(const SimulationParams& params,
                                        const CellGrid& grid,
                                        const FluidDomainBounds& domain,
                                        const std::vector<double>& cellMass,
                                        const std::vector<double>& pVir,
                                        ClosedCapacityResponseDiagnostics& d) {
    if (!d.enabled || !d.computed || static_cast<int>(cellMass.size()) != grid.numCells ||
        static_cast<int>(pVir.size()) != grid.numCells) {
        return;
    }
    const double width = fluid_domain_width(domain);
    const double height = fluid_domain_height(domain);
    if (!(width > 0.0) || !(height > 0.0) || params.Nx <= 0 || params.Ny <= 0) {
        return;
    }
    const double dx = width / static_cast<double>(params.Nx);
    const double dy = height / static_cast<double>(params.Ny);
    const double area = dx * dy;
    const double kBT = capacity_wall_kbt_estimate(params);
    d.wallKineticKBT = kBT;

    WallLoadAccum left, right, bottom, top;
    double fKinX = 0.0, fKinY = 0.0, fVirX = 0.0, fVirY = 0.0, fTotX = 0.0, fTotY = 0.0;

    for (int j = 0; j < params.Ny; ++j) {
        const double s = (static_cast<double>(j) + 0.5) / static_cast<double>(params.Ny);
        if (solid_wall_portion(params, "left", s)) {
            const int c = params.Nx * j;
            const double pK = (cellMass[static_cast<std::size_t>(c)] / area) * kBT;
            add_wall_cell_load(left, dy, pK, pVir[static_cast<std::size_t>(c)], -1.0, 0.0,
                               fKinX, fKinY, fVirX, fVirY, fTotX, fTotY);
        }
        if (solid_wall_portion(params, "right", s)) {
            const int c = (params.Nx - 1) + params.Nx * j;
            const double pK = (cellMass[static_cast<std::size_t>(c)] / area) * kBT;
            add_wall_cell_load(right, dy, pK, pVir[static_cast<std::size_t>(c)], 1.0, 0.0,
                               fKinX, fKinY, fVirX, fVirY, fTotX, fTotY);
        }
    }
    for (int i = 0; i < params.Nx; ++i) {
        const double s = (static_cast<double>(i) + 0.5) / static_cast<double>(params.Nx);
        if (solid_wall_portion(params, "bottom", s)) {
            const int c = i;
            const double pK = (cellMass[static_cast<std::size_t>(c)] / area) * kBT;
            add_wall_cell_load(bottom, dx, pK, pVir[static_cast<std::size_t>(c)], 0.0, -1.0,
                               fKinX, fKinY, fVirX, fVirY, fTotX, fTotY);
        }
        if (solid_wall_portion(params, "top", s)) {
            const int c = i + params.Nx * (params.Ny - 1);
            const double pK = (cellMass[static_cast<std::size_t>(c)] / area) * kBT;
            add_wall_cell_load(top, dx, pK, pVir[static_cast<std::size_t>(c)], 0.0, 1.0,
                               fKinX, fKinY, fVirX, fVirY, fTotX, fTotY);
        }
    }

    d.wallSolidLengthLeft = left.length;
    d.wallSolidLengthRight = right.length;
    d.wallSolidLengthBottom = bottom.length;
    d.wallSolidLengthTop = top.length;
    d.wallSolidLengthTotal = left.length + right.length + bottom.length + top.length;

    d.wallPressureKineticMeanLeft = mean_pressure(left, left.kinetic);
    d.wallPressureKineticMeanRight = mean_pressure(right, right.kinetic);
    d.wallPressureKineticMeanBottom = mean_pressure(bottom, bottom.kinetic);
    d.wallPressureKineticMeanTop = mean_pressure(top, top.kinetic);
    d.wallPressureVirialMeanLeft = mean_pressure(left, left.virial);
    d.wallPressureVirialMeanRight = mean_pressure(right, right.virial);
    d.wallPressureVirialMeanBottom = mean_pressure(bottom, bottom.virial);
    d.wallPressureVirialMeanTop = mean_pressure(top, top.virial);
    d.wallPressureTotalMeanLeft = mean_pressure(left, left.total);
    d.wallPressureTotalMeanRight = mean_pressure(right, right.total);
    d.wallPressureTotalMeanBottom = mean_pressure(bottom, bottom.total);
    d.wallPressureTotalMeanTop = mean_pressure(top, top.total);

    const double kinAll = left.kinetic + right.kinetic + bottom.kinetic + top.kinetic;
    const double virAll = left.virial + right.virial + bottom.virial + top.virial;
    const double totAll = left.total + right.total + bottom.total + top.total;
    d.wallPressureKineticMeanAll = d.wallSolidLengthTotal > 0.0 ? kinAll / d.wallSolidLengthTotal : 0.0;
    d.wallPressureVirialMeanAll = d.wallSolidLengthTotal > 0.0 ? virAll / d.wallSolidLengthTotal : 0.0;
    d.wallPressureTotalMeanAll = d.wallSolidLengthTotal > 0.0 ? totAll / d.wallSolidLengthTotal : 0.0;
    d.wallForceKineticX = fKinX;
    d.wallForceKineticY = fKinY;
    d.wallForceVirialX = fVirX;
    d.wallForceVirialY = fVirY;
    d.wallForceTotalX = fTotX;
    d.wallForceTotalY = fTotY;
    d.wallLoadComputed = d.wallSolidLengthTotal > 0.0;
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
    d.massRemapTargetCellMassNominal = refCellMass;
    d.massRemapOverfillPerCell = referenceCells > 0u
        ? d.overfillMass / static_cast<double>(referenceCells)
        : 0.0;
    d.massRemapTargetCellMassEffective = refCellMass + d.massRemapOverfillPerCell;
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
    ClosedCapacityResponseWorkspace& ws,
    const std::vector<std::uint64_t>* fluidSlots) {
    if (!params.closedCapacityResponseEnable) {
        return ClosedCapacityResponseDiagnostics{};
    }

    validate_particle_state(state, "apply_closed_capacity_virial_kick");
    ensure_particle_roles(state, ParticleRole::Fluid);

    const int nc = grid.numCells;
    const int nt = std::max(1, thread_count());
    const std::size_t n = static_cast<std::size_t>(state.Np);
    const bool useFluidSlots = fluidSlots != nullptr;
    const std::size_t nLoop = useFluidSlots ? fluidSlots->size() : n;
    resize_capacity_workspace(ws, nc, state.Np, nt);
    deposit_cell_mass_for_capacity(state, params, grid, domain, ws, fluidSlots);

    ClosedCapacityResponseDiagnostics d = compute_closed_capacity_response_from_cell_masses(
        params, grid, domain, ws.cellMass, nullptr, params.q6ProjectionStrength);
    if (!d.enabled || !d.computed) {
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

    compute_closed_capacity_wall_loads(params, grid, domain, ws.cellMass, ws.pressure, d);

    if (!params.closedCapacityVirialKickEnable || !(d.virialKEffective > 0.0)) {
        return d;
    }

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
#pragma omp parallel for reduction(+:mass,dpx,dpy) if(nLoop > 10000)
    for (std::int64_t ii = 0; ii < static_cast<std::int64_t>(nLoop); ++ii) {
        const std::size_t i = useFluidSlots
            ? static_cast<std::size_t>((*fluidSlots)[static_cast<std::size_t>(ii)])
            : static_cast<std::size_t>(ii);
        if (i >= n) continue;
        if (!useFluidSlots && !is_fluid_particle(state, i)) continue;
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
#pragma omp parallel for if(nLoop > 10000)
        for (std::int64_t ii = 0; ii < static_cast<std::int64_t>(nLoop); ++ii) {
            const std::size_t i = useFluidSlots
                ? static_cast<std::size_t>((*fluidSlots)[static_cast<std::size_t>(ii)])
                : static_cast<std::size_t>(ii);
            if (i >= n) continue;
            if (!useFluidSlots && !is_fluid_particle(state, i)) continue;
            state.vx[i] -= cvx;
            state.vy[i] -= cvy;
        }
    }
    d.virialKickApplied = true;
    return d;
}

} // namespace mpcd
