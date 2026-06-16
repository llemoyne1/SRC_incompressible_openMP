#include "thermostat.h"

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

} // namespace

void resize_thermostat_workspace(ThermostatWorkspace& ws,
                                 std::uint64_t numParticles,
                                 int numCells,
                                 int numThreads) {
    if (numCells <= 0) {
        throw std::runtime_error("resize_thermostat_workspace: invalid number of cells");
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

        ws.cellCount.assign(static_cast<std::size_t>(numCells), 0u);
        ws.cellMass.assign(static_cast<std::size_t>(numCells), 0.0);
        ws.cellUx.assign(static_cast<std::size_t>(numCells), 0.0);
        ws.cellUy.assign(static_cast<std::size_t>(numCells), 0.0);
        ws.cellKinetic.assign(static_cast<std::size_t>(numCells), 0.0);
        ws.cellScale.assign(static_cast<std::size_t>(numCells), 1.0);

        const std::size_t localSize = static_cast<std::size_t>(numThreads * numCells);
        ws.localCount.assign(localSize, 0u);
        ws.localMass.assign(localSize, 0.0);
        ws.localPx.assign(localSize, 0.0);
        ws.localPy.assign(localSize, 0.0);
        ws.localKinetic.assign(localSize, 0.0);
    }
}

ThermostatDiagnostics apply_cell_relative_rescale_thermostat(ParticleState& state,
                                                              const SimulationParams& params,
                                                              const CellGrid& grid,
                                                              const std::vector<int>& cellId,
                                                              std::uint64_t step,
                                                              ThermostatWorkspace& ws,
                                                              const std::vector<std::uint64_t>* fluidSlots) {
    validate_particle_state(state, "apply_cell_relative_rescale_thermostat");

    ThermostatDiagnostics diag{};
    if (!params.thermostatEnable) {
        return diag;
    }
    if (params.thermostatEvery <= 0) {
        throw std::runtime_error("thermostatEvery must be positive when thermostatEnable=true");
    }
    if ((step % static_cast<std::uint64_t>(params.thermostatEvery)) != 0u) {
        return diag;
    }
    if (params.thermostatMode != "cell_relative_rescale") {
        throw std::runtime_error("Unsupported thermostatMode: " + params.thermostatMode);
    }
    if (cellId.size() != static_cast<std::size_t>(state.Np)) {
        throw std::runtime_error("Thermostat cellId array has wrong size");
    }

    const double targetKBT = params.thermostatTargetKBT > 0.0 ? params.thermostatTargetKBT : params.kBT;
    if (!(targetKBT > 0.0)) {
        throw std::runtime_error("Thermostat requires positive thermostatTargetKBT or kBT");
    }

    const std::size_t n = static_cast<std::size_t>(state.Np);
    const bool useFluidSlots = fluidSlots != nullptr;
    const int nc = grid.numCells;
    const int nt = std::max(1, thread_count());
    resize_thermostat_workspace(ws, state.Np, nc, nt);

    std::fill(ws.cellCount.begin(), ws.cellCount.end(), 0u);
    std::fill(ws.cellMass.begin(), ws.cellMass.end(), 0.0);
    std::fill(ws.cellUx.begin(), ws.cellUx.end(), 0.0);
    std::fill(ws.cellUy.begin(), ws.cellUy.end(), 0.0);
    std::fill(ws.cellKinetic.begin(), ws.cellKinetic.end(), 0.0);
    std::fill(ws.cellScale.begin(), ws.cellScale.end(), 1.0);
    std::fill(ws.localCount.begin(), ws.localCount.end(), 0u);
    std::fill(ws.localMass.begin(), ws.localMass.end(), 0.0);
    std::fill(ws.localPx.begin(), ws.localPx.end(), 0.0);
    std::fill(ws.localPy.begin(), ws.localPy.end(), 0.0);
    std::fill(ws.localKinetic.begin(), ws.localKinetic.end(), 0.0);

#pragma omp parallel
    {
        const int tid = thread_id();
        const std::size_t offset = static_cast<std::size_t>(tid * nc);

#pragma omp for
        for (std::int64_t ii = 0; ii < static_cast<std::int64_t>(useFluidSlots ? fluidSlots->size() : n); ++ii) {
            const std::size_t i = useFluidSlots
                ? static_cast<std::size_t>((*fluidSlots)[static_cast<std::size_t>(ii)])
                : static_cast<std::size_t>(ii);
            if (i >= n) {
                continue;
            }
            if (!useFluidSlots && !is_fluid_particle(state, i)) {
                continue;
            }
            const int c = cellId[i];
            if (c < 0 || c >= nc) {
                continue;
            }
            const std::size_t k = offset + static_cast<std::size_t>(c);
            const double m = state.mass[i];
            ws.localCount[k] += 1u;
            ws.localMass[k] += m;
            ws.localPx[k] += m * state.vx[i];
            ws.localPy[k] += m * state.vy[i];
        }
    }

#pragma omp parallel for if(nc > 256)
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
        ws.cellCount[kk] = count;
        ws.cellMass[kk] = mass;
        if (mass > 0.0) {
            ws.cellUx[kk] = px / mass;
            ws.cellUy[kk] = py / mass;
        }
    }

#pragma omp parallel
    {
        const int tid = thread_id();
        const std::size_t offset = static_cast<std::size_t>(tid * nc);

#pragma omp for
        for (std::int64_t ii = 0; ii < static_cast<std::int64_t>(useFluidSlots ? fluidSlots->size() : n); ++ii) {
            const std::size_t i = useFluidSlots
                ? static_cast<std::size_t>((*fluidSlots)[static_cast<std::size_t>(ii)])
                : static_cast<std::size_t>(ii);
            if (i >= n) {
                continue;
            }
            if (!useFluidSlots && !is_fluid_particle(state, i)) {
                continue;
            }
            const int c = cellId[i];
            if (c < 0 || c >= nc) {
                continue;
            }
            const std::size_t kk = static_cast<std::size_t>(c);
            const double dvx = state.vx[i] - ws.cellUx[kk];
            const double dvy = state.vy[i] - ws.cellUy[kk];
            ws.localKinetic[offset + kk] += 0.5 * state.mass[i] * (dvx * dvx + dvy * dvy);
        }
    }

    double totalKBefore = 0.0;
    double targetKTotal = 0.0;
    double scaleSum = 0.0;
    double scaleMin = std::numeric_limits<double>::infinity();
    double scaleMax = 0.0;
    std::uint64_t dofTotal = 0u;
    std::uint64_t cellsRescaled = 0u;
    std::uint64_t particlesRescaled = 0u;

#pragma omp parallel for reduction(+:totalKBefore,targetKTotal,scaleSum,dofTotal,cellsRescaled,particlesRescaled) reduction(min:scaleMin) reduction(max:scaleMax) if(nc > 256)
    for (int c = 0; c < nc; ++c) {
        double K = 0.0;
        for (int t = 0; t < nt; ++t) {
            K += ws.localKinetic[static_cast<std::size_t>(t * nc + c)];
        }
        const std::size_t kk = static_cast<std::size_t>(c);
        ws.cellKinetic[kk] = K;

        const std::uint32_t count = ws.cellCount[kk];
        if (count < static_cast<std::uint32_t>(params.thermostatMinParticles)) {
            continue;
        }
        if (!(K > params.thermostatEpsilon)) {
            continue;
        }

        const double dof = 2.0 * static_cast<double>(count - 1u);
        const double targetK = 0.5 * dof * targetKBT;
        const double scale = std::sqrt(targetK / K);
        ws.cellScale[kk] = scale;

        totalKBefore += K;
        targetKTotal += targetK;
        dofTotal += static_cast<std::uint64_t>(2u * (count - 1u));
        cellsRescaled += 1u;
        particlesRescaled += static_cast<std::uint64_t>(count);
        scaleSum += scale;
        if (scale < scaleMin) scaleMin = scale;
        if (scale > scaleMax) scaleMax = scale;
    }

#pragma omp parallel for if(n > 10000)
    for (std::int64_t ii = 0; ii < static_cast<std::int64_t>(useFluidSlots ? fluidSlots->size() : n); ++ii) {
        const std::size_t i = useFluidSlots
            ? static_cast<std::size_t>((*fluidSlots)[static_cast<std::size_t>(ii)])
            : static_cast<std::size_t>(ii);
        if (i >= n) {
            continue;
        }
        if (!useFluidSlots && !is_fluid_particle(state, i)) {
            continue;
        }
        const int c = cellId[i];
        if (c < 0 || c >= nc) {
            continue;
        }
        const std::size_t kk = static_cast<std::size_t>(c);
        const double scale = ws.cellScale[kk];
        if (scale == 1.0) {
            continue;
        }
        const double ux = ws.cellUx[kk];
        const double uy = ws.cellUy[kk];
        state.vx[i] = ux + scale * (state.vx[i] - ux);
        state.vy[i] = uy + scale * (state.vy[i] - uy);
    }

    diag.applied = cellsRescaled > 0u;
    diag.cellsRescaled = cellsRescaled;
    diag.particlesRescaled = particlesRescaled;
    diag.kBTBefore = dofTotal > 0u ? (2.0 * totalKBefore / static_cast<double>(dofTotal)) : 0.0;
    diag.kBTAfter = dofTotal > 0u ? (2.0 * targetKTotal / static_cast<double>(dofTotal)) : 0.0;
    diag.scaleMean = cellsRescaled > 0u ? scaleSum / static_cast<double>(cellsRescaled) : 1.0;
    diag.scaleMin = cellsRescaled > 0u ? scaleMin : 1.0;
    diag.scaleMax = cellsRescaled > 0u ? scaleMax : 1.0;
    return diag;
}

} // namespace mpcd
