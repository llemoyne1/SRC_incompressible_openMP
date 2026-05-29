#include "weighted_resampling.h"

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


ResamplingParticlePoolDiagnostics rebuild_resampling_particle_pool(
    const ParticleState& state,
    ResamplingParticlePoolWorkspace& pool) {
    validate_particle_state(state, "rebuild_resampling_particle_pool");
    const std::size_t n = static_cast<std::size_t>(state.Np);

    pool.allocatedParticles = state.Np;
    pool.freeInactiveSlots.clear();
    pool.latentSlots.clear();
    pool.fluidSlots.clear();
    pool.freeInactiveSlots.reserve(n);
    pool.latentSlots.reserve(n);
    pool.fluidSlots.reserve(n);

    ResamplingParticlePoolDiagnostics d{};
    d.built = true;
    d.storageSlots = state.Np;

    for (std::size_t i = 0; i < n; ++i) {
        const std::uint8_t r = particle_role_value(state, i);
        const std::uint64_t index = static_cast<std::uint64_t>(i);
        if (is_fluid_role(r)) {
            pool.fluidSlots.push_back(index);
        } else if (is_latent_role(r)) {
            pool.latentSlots.push_back(index);
        } else if (is_inactive_role(r)) {
            pool.freeInactiveSlots.push_back(index);
        } else {
            throw std::runtime_error("rebuild_resampling_particle_pool: invalid particle role");
        }
    }

    d.fluidSlots = static_cast<std::uint64_t>(pool.fluidSlots.size());
    d.latentSlots = static_cast<std::uint64_t>(pool.latentSlots.size());
    d.freeSlots = static_cast<std::uint64_t>(pool.freeInactiveSlots.size());
    d.nFluid = d.fluidSlots;
    d.nLatent = d.latentSlots;
    d.nInactive = d.freeSlots;

    if (!pool.freeInactiveSlots.empty()) {
        d.firstFreeIndex = pool.freeInactiveSlots.front();
        d.lastFreeIndex = pool.freeInactiveSlots.back();
    }
    if (d.storageSlots > 0u) {
        const double invStorage = 1.0 / static_cast<double>(d.storageSlots);
        d.freeSlotFraction = static_cast<double>(d.freeSlots) * invStorage;
        d.dormantSlotFraction = static_cast<double>(d.freeSlots + d.latentSlots) * invStorage;
    }

    pool.diagnostics = d;
    return d;
}

bool resampling_pool_has_free_slot(const ResamplingParticlePoolWorkspace& pool) {
    return !pool.freeInactiveSlots.empty();
}

std::uint64_t resampling_pool_pop_free_slot(ResamplingParticlePoolWorkspace& pool) {
    if (pool.freeInactiveSlots.empty()) {
        throw std::runtime_error("resampling_pool_pop_free_slot: no inactive slot available");
    }
    const std::uint64_t index = pool.freeInactiveSlots.back();
    pool.freeInactiveSlots.pop_back();
    pool.diagnostics.freeSlots = static_cast<std::uint64_t>(pool.freeInactiveSlots.size());
    if (pool.freeInactiveSlots.empty()) {
        pool.diagnostics.firstFreeIndex = kInvalidParticleIndex;
        pool.diagnostics.lastFreeIndex = kInvalidParticleIndex;
    } else {
        pool.diagnostics.firstFreeIndex = pool.freeInactiveSlots.front();
        pool.diagnostics.lastFreeIndex = pool.freeInactiveSlots.back();
    }
    if (pool.diagnostics.storageSlots > 0u) {
        pool.diagnostics.freeSlotFraction =
            static_cast<double>(pool.diagnostics.freeSlots) / static_cast<double>(pool.diagnostics.storageSlots);
        pool.diagnostics.dormantSlotFraction =
            static_cast<double>(pool.diagnostics.freeSlots + pool.diagnostics.latentSlots) /
            static_cast<double>(pool.diagnostics.storageSlots);
    }
    return index;
}

void resampling_pool_push_free_slot(ResamplingParticlePoolWorkspace& pool, std::uint64_t index) {
    if (index == kInvalidParticleIndex) {
        throw std::runtime_error("resampling_pool_push_free_slot: invalid index");
    }
    pool.freeInactiveSlots.push_back(index);
    pool.diagnostics.freeSlots = static_cast<std::uint64_t>(pool.freeInactiveSlots.size());
    pool.diagnostics.firstFreeIndex = pool.freeInactiveSlots.front();
    pool.diagnostics.lastFreeIndex = pool.freeInactiveSlots.back();
    if (pool.diagnostics.storageSlots > 0u) {
        pool.diagnostics.freeSlotFraction =
            static_cast<double>(pool.diagnostics.freeSlots) / static_cast<double>(pool.diagnostics.storageSlots);
        pool.diagnostics.dormantSlotFraction =
            static_cast<double>(pool.diagnostics.freeSlots + pool.diagnostics.latentSlots) /
            static_cast<double>(pool.diagnostics.storageSlots);
    }
}

void attach_resampling_pool_diagnostics(WeightedResamplingDiagnostics& diagnostics,
                                        const ResamplingParticlePoolDiagnostics& poolDiagnostics) {
    diagnostics.poolBuilt = poolDiagnostics.built;
    diagnostics.poolStorageSlots = poolDiagnostics.storageSlots;
    diagnostics.poolFreeSlots = poolDiagnostics.freeSlots;
    diagnostics.poolLatentSlots = poolDiagnostics.latentSlots;
    diagnostics.poolFluidSlots = poolDiagnostics.fluidSlots;
    diagnostics.poolFirstFreeIndex = poolDiagnostics.firstFreeIndex;
    diagnostics.poolLastFreeIndex = poolDiagnostics.lastFreeIndex;
    diagnostics.poolFreeSlotFraction = poolDiagnostics.freeSlotFraction;
    diagnostics.poolDormantSlotFraction = poolDiagnostics.dormantSlotFraction;
}

void resize_weighted_real_fluid_deposit(WeightedRealFluidDepositWorkspace& ws,
                                        std::uint64_t numParticles,
                                        int numCells,
                                        int numThreads) {
    if (numCells <= 0) {
        throw std::runtime_error("resize_weighted_real_fluid_deposit: invalid number of cells");
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

        ws.cellId.assign(static_cast<std::size_t>(numParticles), -1);
        ws.count.assign(static_cast<std::size_t>(numCells), 0u);
        ws.mass.assign(static_cast<std::size_t>(numCells), 0.0);
        ws.px.assign(static_cast<std::size_t>(numCells), 0.0);
        ws.py.assign(static_cast<std::size_t>(numCells), 0.0);
        ws.ux.assign(static_cast<std::size_t>(numCells), 0.0);
        ws.uy.assign(static_cast<std::size_t>(numCells), 0.0);

        const std::size_t localSize = static_cast<std::size_t>(numThreads * numCells);
        ws.localCount.assign(localSize, 0u);
        ws.localMass.assign(localSize, 0.0);
        ws.localPx.assign(localSize, 0.0);
        ws.localPy.assign(localSize, 0.0);
    }
}

WeightedResamplingDiagnostics deposit_weighted_real_fluid(const ParticleState& state,
                                                          const SimulationParams& params,
                                                          const CellGrid& grid,
                                                          const GridShift& shift,
                                                          WeightedRealFluidDepositWorkspace& ws) {
    validate_particle_state(state, "deposit_weighted_real_fluid");

    const int nc = grid.numCells;
    if (nc <= 0) {
        throw std::runtime_error("deposit_weighted_real_fluid: invalid number of cells");
    }
    const std::size_t n = static_cast<std::size_t>(state.Np);
    const int nt = std::max(1, thread_count());
    resize_weighted_real_fluid_deposit(ws, state.Np, nc, nt);

    std::fill(ws.cellId.begin(), ws.cellId.end(), -1);
    std::fill(ws.count.begin(), ws.count.end(), 0u);
    std::fill(ws.mass.begin(), ws.mass.end(), 0.0);
    std::fill(ws.px.begin(), ws.px.end(), 0.0);
    std::fill(ws.py.begin(), ws.py.end(), 0.0);
    std::fill(ws.ux.begin(), ws.ux.end(), 0.0);
    std::fill(ws.uy.begin(), ws.uy.end(), 0.0);
    std::fill(ws.localCount.begin(), ws.localCount.end(), 0u);
    std::fill(ws.localMass.begin(), ws.localMass.end(), 0.0);
    std::fill(ws.localPx.begin(), ws.localPx.end(), 0.0);
    std::fill(ws.localPy.begin(), ws.localPy.end(), 0.0);

    const ParticleRoleCounts roles = count_particle_roles(state);

    double particleMassSum = 0.0;
    double particleMassSum2 = 0.0;
    double particleMassMin = std::numeric_limits<double>::infinity();
    double particleMassMax = 0.0;

#pragma omp parallel reduction(+:particleMassSum,particleMassSum2) reduction(min:particleMassMin) reduction(max:particleMassMax)
    {
        const int tid = thread_id();
        const std::size_t offset = static_cast<std::size_t>(tid * nc);

#pragma omp for
        for (std::int64_t ii = 0; ii < static_cast<std::int64_t>(n); ++ii) {
            const std::size_t i = static_cast<std::size_t>(ii);
            if (!is_fluid_particle(state, i)) {
                continue;
            }
            const double m = state.mass[i];
            const int c = cell_index_from_position(state.x[i], state.y[i], grid, shift, params);
            ws.cellId[i] = c;
            const std::size_t k = offset + static_cast<std::size_t>(c);
            ws.localCount[k] += 1u;
            ws.localMass[k] += m;
            ws.localPx[k] += m * state.vx[i];
            ws.localPy[k] += m * state.vy[i];
            particleMassSum += m;
            particleMassSum2 += m * m;
            particleMassMin = std::min(particleMassMin, m);
            particleMassMax = std::max(particleMassMax, m);
        }
    }

    double totalMass = 0.0;
    double totalPx = 0.0;
    double totalPy = 0.0;
    double sumN = 0.0;
    double sumN2 = 0.0;
    double sumM = 0.0;
    double sumM2 = 0.0;
    double minMass = std::numeric_limits<double>::infinity();
    double maxMass = 0.0;
    std::uint32_t minN = std::numeric_limits<std::uint32_t>::max();
    std::uint32_t maxN = 0u;
    std::uint64_t nonEmpty = 0u;
    double cellUxRmsAccum = 0.0;
    double cellUyRmsAccum = 0.0;

#pragma omp parallel for reduction(+:totalMass,totalPx,totalPy,sumN,sumN2,sumM,sumM2,nonEmpty,cellUxRmsAccum,cellUyRmsAccum) reduction(min:minMass,minN) reduction(max:maxMass,maxN) if(nc > 256)
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
        ws.count[kk] = count;
        ws.mass[kk] = mass;
        ws.px[kk] = px;
        ws.py[kk] = py;
        if (mass > 0.0) {
            ws.ux[kk] = px / mass;
            ws.uy[kk] = py / mass;
            nonEmpty += 1u;
            cellUxRmsAccum += ws.ux[kk] * ws.ux[kk];
            cellUyRmsAccum += ws.uy[kk] * ws.uy[kk];
        }

        totalMass += mass;
        totalPx += px;
        totalPy += py;
        const double dn = static_cast<double>(count);
        sumN += dn;
        sumN2 += dn * dn;
        sumM += mass;
        sumM2 += mass * mass;
        minMass = std::min(minMass, mass);
        maxMass = std::max(maxMass, mass);
        minN = std::min(minN, count);
        maxN = std::max(maxN, count);
    }

    WeightedResamplingDiagnostics d{};
    d.computed = true;
    d.nFluid = roles.fluid;
    d.nLatent = roles.latent;
    d.nInactive = roles.inactive;
    d.nCells = static_cast<std::uint64_t>(nc);
    d.nNonEmptyCells = nonEmpty;
    d.nEmptyCells = static_cast<std::uint64_t>(nc) - nonEmpty;
    d.totalMass = totalMass;
    d.totalPx = totalPx;
    d.totalPy = totalPy;

    const double invNc = nc > 0 ? 1.0 / static_cast<double>(nc) : 0.0;
    d.meanN = sumN * invNc;
    d.stdN = std::sqrt(std::max(0.0, sumN2 * invNc - d.meanN * d.meanN));
    d.minN = (minN == std::numeric_limits<std::uint32_t>::max()) ? 0u : minN;
    d.maxN = maxN;
    d.meanMass = sumM * invNc;
    d.stdMass = std::sqrt(std::max(0.0, sumM2 * invNc - d.meanMass * d.meanMass));
    d.minMass = std::isfinite(minMass) ? minMass : 0.0;
    d.maxMass = maxMass;
    d.targetCellMass = params.resamplingTargetCellMass > 0.0
        ? params.resamplingTargetCellMass
        : d.meanMass;

    if (d.targetCellMass > 0.0) {
        double rel2 = 0.0;
        double relMax = 0.0;
#pragma omp parallel for reduction(+:rel2) reduction(max:relMax) if(nc > 256)
        for (int c = 0; c < nc; ++c) {
            const double rel = (ws.mass[static_cast<std::size_t>(c)] - d.targetCellMass) / d.targetCellMass;
            rel2 += rel * rel;
            relMax = std::max(relMax, std::abs(rel));
        }
        d.mRelRms = std::sqrt(rel2 * invNc);
        d.mRelMaxAbs = relMax;
    }

    if (totalMass > 0.0) {
        d.meanUx = totalPx / totalMass;
        d.meanUy = totalPy / totalMass;
    }
    if (nonEmpty > 0u) {
        const double invNonEmpty = 1.0 / static_cast<double>(nonEmpty);
        d.cellUxRms = std::sqrt(cellUxRmsAccum * invNonEmpty);
        d.cellUyRms = std::sqrt(cellUyRmsAccum * invNonEmpty);
    }

    if (roles.fluid > 0u) {
        const double invNp = 1.0 / static_cast<double>(roles.fluid);
        d.particleMassMean = particleMassSum * invNp;
        d.particleMassStd = std::sqrt(std::max(0.0, particleMassSum2 * invNp - d.particleMassMean * d.particleMassMean));
        d.particleMassRelStd = d.particleMassMean > 0.0 ? d.particleMassStd / d.particleMassMean : 0.0;
        d.particleMassMin = std::isfinite(particleMassMin) ? particleMassMin : 0.0;
        d.particleMassMax = particleMassMax;
    }

    return d;
}

} // namespace mpcd
